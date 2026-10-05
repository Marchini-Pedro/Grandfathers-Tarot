-- The Spread (tarot HUD): everything about it that is arithmetic, with no engine calls, so it is tested offline
-- (tools/hud_test.py). Sizes are in the 1920 x 1080 units of the HUD. Reference design: docs/04 and the reference page.
--
-- Nothing here allocates while the HUD runs: every function that produces numbers fills a table the caller owns.
local Spread = {}

local floor, max, min, sqrt, cos, sin, pi = math.floor, math.max, math.min, math.sqrt, math.cos, math.sin, math.pi
local atan2 = math.atan2 or math.atan

local function clamp(value, low, high)
	return max(low, min(high, value))
end

Spread.clamp = clamp

-- ------------------------------------------------------------------------------------------------- sizes
Spread.NODE_WIDTH = 700
Spread.GAP = 8 -- between cards
Spread.MIN_CARD_HEIGHT = 76
Spread.TIME_HEIGHT = 30
Spread.TIME_GAP = 12 -- between the label and the time of the countdown
Spread.CARDS_Y = 38
Spread.FUSE_GAP = 10
Spread.FUSE_HEIGHT = 4
Spread.BANNER_GAP = 8
Spread.BANNER_HEIGHT = 100
Spread.NODE_HEIGHT = 262 -- the footprint custom_hud shows: time line, three-line cards, fuse, banner
Spread.MAX_CARDS = 5

Spread.ACCENT_WIDTH = 4 -- the suit-coloured bar on the left of a card
Spread.PAD_X = 12
Spread.PAD_Y = 8
Spread.ICON = 18
Spread.ICON_GAP = 6
Spread.NAME_FONT = 18
Spread.NAME_LINE = 21
Spread.THREAT_SIDE = 8
Spread.THREAT_PITCH = 11.2
Spread.DOT = 9
Spread.DOT_PITCH = 13
Spread.ROW_HEIGHT = 14 -- the bottom row (threat diamonds and dots)

-- timeline of the reveal (seconds), the same as the reference page
Spread.POP_TIME = 0.2 -- the winner rises and grows
Spread.FADE_TIME = 0.35 -- the others fall away
Spread.REST_TIME = 0.5 -- the rotted card lingers before the Spread is gone
Spread.URGENT_SECONDS = 5 -- the fuse turns rust for the last stretch

-- Card width by the number of cards in the hand: 176 px up to three cards, 152 for four, 132 for five.
Spread.card_width = function (count)
	return count <= 3 and 176 or count == 4 and 152 or 132
end

-- Greedy word-wrap estimate; names use three lines, other text may supply its own line limit.
local GLYPH = 0.54 -- of the font size, for the default font

-- average glyph width (of the font size) of the fonts the player can choose; unknown fonts use GLYPH
Spread.GLYPH_BY_FONT = { itc_novarese_bold = 0.56, itc_novarese_medium = 0.54, friz_quadrata = 0.56, proxima_nova_bold = 0.56, rexlia = 0.62, machine_medium = 0.62 }

Spread.wrap_lines = function (text, width, font_size, glyph, max_lines)
	local per_line = max(1, floor(width / (font_size * (glyph or GLYPH))))
	local lines, used = 1, 0

	for word in tostring(text or ""):gmatch("%S+") do
		local length = #word

		while length > per_line do
			if used > 0 then
				lines, used = lines + 1, 0
			end

			lines, length = lines + 1, length - per_line
		end

		if used == 0 then
			used = length
		elseif used + 1 + length <= per_line then
			used = used + 1 + length
		else
			lines, used = lines + 1, length
		end
	end

	return min(max_lines or 3, lines)
end

Spread.new_layout = function ()
	return { count = 0, cw = 176, ch = Spread.MIN_CARD_HEIGHT, lines = 1, name_w = 120, total_w = 0, x0 = 0, x = { 0, 0, 0, 0, 0 }, cards_y = Spread.CARDS_Y, fuse_y = 0, banner_y = 0, time_y = 0 }
end

-- Positions of the cards in the node for a hand (cards with a `name`), written into `layout`. `options` (all optional):
-- timer_below (the countdown goes under the fuse instead of above the cards), hide_icon (no suit mark in the corner,
-- the name gets its room), glyph (average glyph width of the font, see GLYPH_BY_FONT).
Spread.layout = function (layout, hand, options)
	options = options or {}

	local count = min(#hand, Spread.MAX_CARDS)
	local cw = Spread.card_width(count)
	local name_w = cw - Spread.ACCENT_WIDTH - 2 * Spread.PAD_X - (options.hide_icon and 0 or Spread.ICON + Spread.ICON_GAP)
	local lines = 1

	for i = 1, count do
		lines = max(lines, Spread.wrap_lines(hand[i].name, name_w, Spread.NAME_FONT, options.glyph))
	end

	local ch = max(Spread.MIN_CARD_HEIGHT, 2 * Spread.PAD_Y + lines * Spread.NAME_LINE + 4 + Spread.ROW_HEIGHT)
	local total = count * cw + max(0, count - 1) * Spread.GAP

	layout.count, layout.cw, layout.ch, layout.lines, layout.name_w, layout.total_w = count, cw, ch, lines, name_w, total
	layout.x0 = floor((Spread.NODE_WIDTH - total) / 2)

	for i = 1, Spread.MAX_CARDS do
		layout.x[i] = layout.x0 + (i - 1) * (cw + Spread.GAP)
	end

	layout.cards_y = options.timer_below and 0 or Spread.CARDS_Y
	layout.fuse_y = layout.cards_y + ch + Spread.FUSE_GAP
	layout.banner_y = layout.fuse_y + Spread.FUSE_HEIGHT + Spread.BANNER_GAP
	-- the countdown sits above the cards, or (timer below) where the banner will be: they are never shown together
	layout.time_y = options.timer_below and layout.banner_y or 0

	return layout
end

-- Dots on a card (bottom right): as big and as far apart as the room beside the threat diamonds allows, never closer to
-- the diamonds than DOTS_GAP. Returns the diameter, the distance between centres and how many of `count` fit (a narrow
-- card with many enemy kinds shows the first few).
Spread.DIAMONDS_END = Spread.ACCENT_WIDTH + Spread.PAD_X + Spread.THREAT_SIDE / 2 + 4 * Spread.THREAT_PITCH + Spread.THREAT_SIDE * 0.7071
Spread.DOTS_GAP = 12

local DOT_STEPS = { { 9, 13 }, { 8, 11 }, { 7, 9.5 }, { 6, 8.5 } }

Spread.dots_fit = function (cw, count, threat)
	local room = (cw - Spread.PAD_X) - (Spread.DIAMONDS_END + (threat == 6 and Spread.THREAT_PITCH or 0) + Spread.DOTS_GAP)

	count = max(0, min(count, 6))

	for i = 1, #DOT_STEPS do
		local diameter, pitch = DOT_STEPS[i][1], DOT_STEPS[i][2]

		if count == 0 or diameter + (count - 1) * pitch <= room then
			return diameter, pitch, count
		end
	end

	local diameter, pitch = DOT_STEPS[#DOT_STEPS][1], DOT_STEPS[#DOT_STEPS][2]

	return diameter, pitch, max(1, min(count, floor((room - diameter) / pitch) + 1))
end
-- "1:05" for 65 seconds (always rounded up, like the countdown of the old panel)
Spread.time_text = function (seconds)
	seconds = max(0, math.ceil(seconds))

	return string.format("%d:%02d", floor(seconds / 60), seconds % 60)
end

-- ----------------------------------------------------------------------------------------------- timeline
-- The roulette ticks across the cards and slows down, then lands on the winner: the first `total` steps (three laps)
-- are spread by an ease-out curve. p = 0..1 through the roulette. Returns the highlighted card, 1-based.
Spread.roulette_index = function (count, win, p)
	if count <= 1 then
		return 1
	end

	local total = 3 * count
	local step = floor(total * (1 - (1 - clamp(p, 0, 1)) ^ 2.2) + 1e-9)

	return (win - 1 - (total - step)) % count + 1
end

Spread.new_timeline = function ()
	return { stage = "waiting", count = 0, hi = 0, fuse = 0, urgent = false, reveal_t = 0, pop = 0, lose = 1, eye = 0, rot_p = 0, desat = 0 }
end

-- Where the Spread is on its timeline, from the director's view and the player's timing options
-- (T = { roulette, winner, eye, rot } seconds). Stages:
--   waiting   no hand: only "Next card in ..."
--   hand      the cards are shown, every eye shut, the fuse burns
--   roulette  the last `roulette` seconds before the pick: the highlight ticks across the cards (more than one card)
--   reveal    the pick is made: the winner rises, its eye opens, the others fall away, the banner shows
--   rot       the winner is consumed by rot (the others are gone)
-- A resolved hand is placed by the seconds since the pick (view.drawn_age), so a late joiner sees the same picture.
Spread.timeline = function (view, T, out)
	local hand = view.hand
	local count = hand and #hand or 0

	out.stage, out.count, out.hi, out.fuse, out.urgent = "waiting", count, 0, 0, false
	out.reveal_t, out.pop, out.lose, out.eye, out.rot_p, out.desat = 0, 0, 1, 0, 0, 0

	if count == 0 then
		return out
	end

	if view.drawn then
		local t = max(0, view.drawn_age or 0)
		local rot_start = T.winner

		out.hi = clamp(view.win or 1, 1, count)
		out.reveal_t = t
		out.pop = clamp(t / Spread.POP_TIME, 0, 1)
		out.eye = clamp(t / max(0.05, T.eye), 0, 1)
		-- the chosen card loses its colour from the moment it is shown and is completely grey when it starts to fade away
		out.desat = clamp(t / max(0.1, T.winner + 0.62 * T.rot), 0, 1)

		if t < rot_start then
			out.stage = "reveal"
			out.lose = 1 - (1 - 0.28) * clamp(t / Spread.FADE_TIME, 0, 1)
		elseif t < rot_start + T.rot + Spread.REST_TIME then
			out.stage = "rot"
			out.rot_p = clamp((t - rot_start) / max(0.05, T.rot), 0, 1)
			out.lose = 0.28 * (1 - clamp((t - rot_start) / Spread.FADE_TIME, 0, 1))
		else
			out.stage, out.count, out.hi = "waiting", 0, 0
		end

		return out
	end

	if view.phase ~= "hand" then
		out.count = 0

		return out
	end

	local remaining = max(0, view.remaining or 0)
	local seconds = max(0.001, view.hand_seconds or 0)
	local roulette = count > 1 and min(T.roulette, seconds) or 0

	out.fuse = clamp(remaining / seconds, 0, 1)
	out.urgent = remaining > 0 and remaining <= Spread.URGENT_SECONDS

	if remaining > roulette then
		out.stage = "hand"
	else
		out.stage = "roulette"
		out.hi = Spread.roulette_index(count, clamp(view.win or 1, 1, count), roulette > 0 and (roulette - remaining) / roulette or 1)
	end

	return out
end

-- ------------------------------------------------------------------------------------------------- the rot
-- The blotches of a rotting card: centre (as fractions of the card) and relative size, from the reference page.
local BLOTCH = { { 0.18, 0.30, 1.00 }, { 0.74, 0.22, 0.85 }, { 0.52, 0.74, 1.15 }, { 0.10, 0.82, 0.60 }, { 0.92, 0.70, 0.95 } }
local MAX_FLIES = 9
local DRIPS = 3

Spread.BLOTCH_COLORS = { { 43, 41, 16 }, { 74, 58, 22 }, { 43, 41, 16 }, { 90, 106, 31 }, { 59, 47, 18 } }
-- A blotch is stacked circles: no radial gradient exists, so the soft edge is faked with rings, outermost first
-- (radius as a fraction of the blotch, opacity of that ring 0..1; where they overlap the opacity adds up).
Spread.BLOTCH_RINGS = { { 1.00, 0.22 }, { 0.80, 0.28 }, { 0.58, 0.34 }, { 0.36, 0.42 } }
Spread.MAX_FLIES = MAX_FLIES
Spread.DRIPS = DRIPS
Spread.BLOTCHES = #BLOTCH

Spread.new_rot = function ()
	local fx = { blotch = {}, flies = {}, drips = {}, wash = 0, fade = 1, bright = 1 }

	for i = 1, #BLOTCH do
		fx.blotch[i] = { on = false, cx = 0, cy = 0, r = 0 }
	end

	for i = 1, MAX_FLIES do
		fx.flies[i] = { on = false, x = 0, y = 0 }
	end

	for i = 1, DRIPS do
		fx.drips[i] = { on = false, x = 0, y = 0, h = 0, alpha = 0 }
	end

	return fx
end

-- The look of the rot at progress r (0..1) for a strength k (0..1, the longer the cooldown the stronger), on a card of
-- cw x ch at a moment `time` (seconds, for the flies and drips). Geometry is relative to the card's top-left corner.
-- A blotch grows until it touches the nearest edge of the card and no further (circles cannot be clipped by the UI).
Spread.rot_fx = function (fx, r, k, cw, ch, time)
	r, k = clamp(r, 0, 1), clamp(k, 0, 1)

	local size = 14 + 52 * k

	fx.fade = clamp(1 - max(0, r - 0.62) * 2.6, 0, 1)
	fx.bright = 1 - r * 0.4
	fx.wash = r * 0.6 -- opacity of the brown wash over the whole card

	for i = 1, #BLOTCH do
		local spec, blotch = BLOTCH[i], fx.blotch[i]
		local cx, cy = spec[1] * cw, spec[2] * ch
		local radius = min(r * size * spec[3], cx, cw - cx, cy, ch - cy)

		blotch.on = radius >= 1.5
		blotch.cx, blotch.cy, blotch.r = cx, cy, radius
	end

	local flies = 3 + floor(6 * k + 0.5)

	for i = 1, MAX_FLIES do
		local fly = fx.flies[i]

		if i <= flies then
			local radius = 46 + ((i - 1) % 3) * 14
			local period = 1.4 + ((i - 1) % 4) * 0.35
			local angle = (i - 1) * 2 * pi / flies + (time / period) * 2 * pi

			fly.on, fly.x, fly.y = true, cw / 2 + cos(angle) * radius, ch / 2 + sin(angle) * radius
		else
			fly.on = false
		end
	end

	local drip_height = 14 + floor(40 * k + 0.5)

	for i = 1, DRIPS do
		local drip = fx.drips[i]
		local u = ((time - (i - 1) * 0.35) / 1.2) % 1

		drip.on = r > 0.02
		drip.x = (0.18 + 0.30 * (i - 1)) * cw
		drip.y = ch + 34 * u
		drip.h = drip_height
		drip.alpha = u < 0.2 and 0.9 * u / 0.2 or 0.9 * (1 - u) / 0.8
	end

	return fx
end
-- ----------------------------------------------------------------------------------------------- shapes
-- Suit icons and the eye are drawn from triangles and circles (the UI has no icon of them and no SVG). A shape is a set
-- of slots in a box; a slot says whether it is used, which colour it takes (1 = the suit's accent, 2 = the card's own
-- background, which "cuts" a hole), the layer order and its geometry relative to the box.
Spread.COLOR_ACCENT = 1
Spread.COLOR_CARD = 2

local function new_tri()
	return { on = false, col = 1, z = 0, x1 = 0, y1 = 0, x2 = 0, y2 = 0, x3 = 0, y3 = 0 }
end

local function new_circ()
	return { on = false, col = 1, z = 0, cx = 0, cy = 0, r = 0 }
end

Spread.new_shape = function (tris, circs)
	local shape = { tri = {}, circ = {} }

	for i = 1, tris do
		shape.tri[i] = new_tri()
	end

	for i = 1, circs do
		shape.circ[i] = new_circ()
	end

	return shape
end

local function clear(shape)
	for i = 1, #shape.tri do
		shape.tri[i].on = false
	end

	for i = 1, #shape.circ do
		shape.circ[i].on = false
	end
end

local function tri(shape, index, col, z, x1, y1, x2, y2, x3, y3)
	local slot = shape.tri[index]

	if slot then
		slot.on, slot.col, slot.z = true, col, z
		slot.x1, slot.y1, slot.x2, slot.y2, slot.x3, slot.y3 = x1, y1, x2, y2, x3, y3
	end
end

local function circ(shape, index, col, z, cx, cy, radius)
	local slot = shape.circ[index]

	if slot then
		slot.on, slot.col, slot.z = true, col, z
		slot.cx, slot.cy, slot.r = cx, cy, radius
	end
end

-- a lens (a wide diamond) of half-width a and half-height b around (cx, cy) as two triangles
local function lens(shape, first, col, z, cx, cy, a, b)
	tri(shape, first, col, z, cx - a, cy, cx, cy - b, cx + a, cy)
	tri(shape, first + 1, col, z, cx - a, cy, cx + a, cy, cx, cy + b)
end

-- a teardrop: a circle (centre cx, cy, radius r) with a point (tx, ty): the triangle between the point and the circle's
-- tangents, plus the circle
local function teardrop(shape, tri_index, circ_index, col, z, tx, ty, cx, cy, radius)
	local vx, vy = tx - cx, ty - cy
	local distance = max(radius + 0.01, sqrt(vx * vx + vy * vy))
	local phi = atan2(vy, vx)
	local alpha = math.acos(min(0.999, radius / distance))

	tri(shape, tri_index, col, z, tx, ty, cx + radius * cos(phi - alpha), cy + radius * sin(phi - alpha), cx + radius * cos(phi + alpha), cy + radius * sin(phi + alpha))
	circ(shape, circ_index, col, z, cx, cy, radius)
end

-- The shut lid, in the reference's 24 x 24 grid: a smile ("M2 11c3 4 7 6 10 6s7-2 10-6") as two cubic curves sampled at
-- seven points, with the unit normals there, so the stroke can be drawn as a ribbon of the same width everywhere.
local LID_X, LID_Y, LID_NX, LID_NY = {}, {}, {}, {}

do
	local function cubic(p0x, p0y, c1x, c1y, c2x, c2y, p1x, p1y, t)
		local u = 1 - t
		local a, b, c, d = u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t

		return a * p0x + b * c1x + c * c2x + d * p1x, a * p0y + b * c1y + c * c2y + d * p1y
	end

	local n = 0

	for _, t in ipairs({ 0, 1 / 3, 2 / 3, 1 }) do
		n = n + 1
		LID_X[n], LID_Y[n] = cubic(2, 11, 5, 15, 9, 17, 12, 17, t)
	end

	for _, t in ipairs({ 1 / 3, 2 / 3, 1 }) do
		n = n + 1
		LID_X[n], LID_Y[n] = cubic(12, 17, 15, 17, 19, 15, 22, 11, t)
	end

	for i = 1, n do
		local a, b = max(1, i - 1), min(n, i + 1)
		local tx, ty = LID_X[b] - LID_X[a], LID_Y[b] - LID_Y[a]
		local length = sqrt(tx * tx + ty * ty)

		LID_NX[i], LID_NY[i] = -ty / length, tx / length
	end
end

local LASH_BASE = { 2, 4, 6 } -- the lid points the three lashes grow from
local LASH_TIP_X = { 3.4, 12, 20.6 }
local LASH_TIP_Y = { 17.8, 20.6, 17.8 }
local LID_LIFT = 3.2 -- the shut eye is drawn this much higher (grid units) so its middle is the open eye's middle

-- The eye in a size x size box. Open (0..1) fades one drawing into the other: shut = the smile of the lid with three
-- lashes, open = a lens (a diamond, as high as it is open) with an inside and a pupil. Slots: tri 1-2 the lens, 3-4 its
-- inside (card colour), 5-16 the lid (a ribbon of six segments), 17-19 the lashes; circ 1 the pupil. Returns the
-- opacity (0..1) of the lens, of the lid and lashes, and of the pupil.
Spread.eye = function (size, open, shape)
	open = clamp(open, 0, 1)
	clear(shape)

	local s = size / 24
	local cx, cy = size / 2, size / 2
	local closed = 1 - open
	local pupil = 0

	if open > 0.02 then
		local a = size * 20 / 24 / 2
		local b = max(size * 0.03, size * 14 / 24 / 2 * (0.15 + 0.85 * open))

		lens(shape, 1, 1, 1, cx, cy, a, b)

		-- the inside is the same diamond pulled in by the stroke, so the line is as thick everywhere
		local stroke = size * 1.6 / 24
		local factor = 1 - stroke * sqrt(a * a + b * b) / (a * b)
		local pupil_radius = size * 3 / 24

		if factor > 0.06 then
			lens(shape, 3, 2, 2, cx, cy, a * factor, b * factor)

			if b * factor > pupil_radius * 0.9 then
				circ(shape, 1, 1, 3, cx, cy, pupil_radius)

				pupil = open
			end
		end
	end

	if closed > 0.02 and #shape.tri >= 19 then
		local half = max(0.55, size * 1.7 / 24 / 2)
		local dy = -LID_LIFT * s

		for k = 1, 6 do
			local x1, y1, x2, y2 = LID_X[k] * s, LID_Y[k] * s + dy, LID_X[k + 1] * s, LID_Y[k + 1] * s + dy
			local l1x, l1y, r1x, r1y = x1 + LID_NX[k] * half, y1 + LID_NY[k] * half, x1 - LID_NX[k] * half, y1 - LID_NY[k] * half
			local l2x, l2y, r2x, r2y = x2 + LID_NX[k + 1] * half, y2 + LID_NY[k + 1] * half, x2 - LID_NX[k + 1] * half, y2 - LID_NY[k + 1] * half

			tri(shape, 3 + 2 * k, 1, 1, l1x, l1y, r1x, r1y, l2x, l2y)
			tri(shape, 4 + 2 * k, 1, 1, r1x, r1y, r2x, r2y, l2x, l2y)
		end

		for i = 1, 3 do
			local base = LASH_BASE[i]
			local bx, by = LID_X[base] * s, LID_Y[base] * s + dy

			tri(shape, 16 + i, 1, 1, bx - half * 0.9, by, bx + half * 0.9, by, LASH_TIP_X[i] * s, LASH_TIP_Y[i] * s + dy)
		end
	end

	return open, closed, pupil
end

Spread.ICON_TRIS = 4
Spread.ICON_CIRCS = 4
Spread.EYE_TRIS = 19
Spread.EYE_CIRCS = 1
-- The six suit marks in a `size` box, from the shape ids of catalog/cards.lua (eye, moon, flame, drop, cluster, star).
-- Coordinates are the reference page's 24 x 24 grid scaled to the box.
Spread.icon = function (id, size, shape)
	clear(shape)

	local s = size / 24

	if id == "eye" then
		Spread.eye(size, 1, shape)
		-- the eye's own pupil rule hides it only for a very small box; the icon always has the 3-radius pupil
	elseif id == "moon" then
		circ(shape, 1, 1, 1, 11.5 * s, 12 * s, 9 * s)
		circ(shape, 2, 2, 2, 17 * s, 8.5 * s, 7 * s)
	elseif id == "flame" then
		teardrop(shape, 1, 1, 1, 1, 12 * s, 1.5 * s, 12 * s, 14.5 * s, 7 * s)
		teardrop(shape, 2, 2, 2, 2, 12.6 * s, 8 * s, 12 * s, 15.2 * s, 4.6 * s)
		teardrop(shape, 3, 3, 1, 3, 12.2 * s, 11.8 * s, 12 * s, 16.6 * s, 2.5 * s)
	elseif id == "drop" then
		teardrop(shape, 1, 1, 1, 1, 12 * s, 2.5 * s, 12 * s, 14.7 * s, 6.6 * s)
		teardrop(shape, 2, 2, 2, 2, 12 * s, 7.6 * s, 12 * s, 14.8 * s, 4.6 * s)
	elseif id == "cluster" then
		circ(shape, 1, 1, 1, 8 * s, 8 * s, 2.4 * s)
		circ(shape, 2, 1, 1, 16 * s, 9 * s, 2.4 * s)
		circ(shape, 3, 1, 1, 11 * s, 16 * s, 2.4 * s)
		circ(shape, 4, 1, 1, 18 * s, 17.5 * s, 1.7 * s)
	elseif id == "crosshair" then
		-- a ring with four ticks pointing in and a dot in the middle
		circ(shape, 1, 1, 1, 12 * s, 12 * s, 9.5 * s)
		circ(shape, 2, 2, 2, 12 * s, 12 * s, 7.3 * s)
		tri(shape, 1, 1, 3, 10.8 * s, 2.5 * s, 13.2 * s, 2.5 * s, 12 * s, 9.2 * s)
		tri(shape, 2, 1, 3, 10.8 * s, 21.5 * s, 13.2 * s, 21.5 * s, 12 * s, 14.8 * s)
		tri(shape, 3, 1, 3, 2.5 * s, 10.8 * s, 2.5 * s, 13.2 * s, 9.2 * s, 12 * s)
		tri(shape, 4, 1, 3, 21.5 * s, 10.8 * s, 21.5 * s, 13.2 * s, 14.8 * s, 12 * s)
		circ(shape, 3, 1, 3, 12 * s, 12 * s, 1.5 * s)
	elseif id == "links" then
		-- two rings that overlap: both discs first, then both holes
		circ(shape, 1, 1, 1, 8.6 * s, 12 * s, 6.6 * s)
		circ(shape, 2, 1, 1, 15.4 * s, 12 * s, 6.6 * s)
		circ(shape, 3, 2, 2, 8.6 * s, 12 * s, 4.4 * s)
		circ(shape, 4, 2, 2, 15.4 * s, 12 * s, 4.4 * s)
	elseif id == "plate" then
		-- a plated square: a frame with a rivet
		tri(shape, 1, 1, 1, 3.5 * s, 3.5 * s, 20.5 * s, 3.5 * s, 20.5 * s, 20.5 * s)
		tri(shape, 2, 1, 1, 3.5 * s, 3.5 * s, 20.5 * s, 20.5 * s, 3.5 * s, 20.5 * s)
		tri(shape, 3, 2, 2, 7.5 * s, 7.5 * s, 16.5 * s, 7.5 * s, 16.5 * s, 16.5 * s)
		tri(shape, 4, 2, 2, 7.5 * s, 7.5 * s, 16.5 * s, 16.5 * s, 7.5 * s, 16.5 * s)
		circ(shape, 1, 1, 3, 12 * s, 12 * s, 2.6 * s)
	elseif id == "faith" then
		-- a rose in a ring: the ring, five petals around a heart in the card's colour
		circ(shape, 1, 1, 1, 12 * s, 12 * s, 10 * s)
		circ(shape, 2, 2, 2, 12 * s, 12 * s, 8 * s)
		tri(shape, 1, 1, 3, 12 * s, 4.6 * s, 15.6 * s, 10.4 * s, 8.4 * s, 10.4 * s)
		tri(shape, 2, 1, 3, 15.6 * s, 10.4 * s, 14.6 * s, 17.2 * s, 12 * s, 12.6 * s)
		tri(shape, 3, 1, 3, 14.6 * s, 17.2 * s, 9.4 * s, 17.2 * s, 12 * s, 12.6 * s)
		tri(shape, 4, 1, 3, 9.4 * s, 17.2 * s, 8.4 * s, 10.4 * s, 12 * s, 12.6 * s)
		circ(shape, 3, 2, 4, 12 * s, 12.2 * s, 1.8 * s)
	elseif id == "prayer" or id == "miracle" or id == "grace" then
		circ(shape, 1, 1, 1, 12 * s, 12 * s, 10 * s)
		circ(shape, 2, 2, 2, 12 * s, 12 * s, 8 * s)
		if id == "prayer" then
			tri(shape, 1, 1, 3, 12 * s, 4 * s, 11 * s, 18 * s, 5 * s, 16 * s)
			tri(shape, 2, 1, 3, 12 * s, 4 * s, 19 * s, 16 * s, 13 * s, 18 * s)
		elseif id == "miracle" then
			tri(shape, 1, 1, 3, 12 * s, 3 * s, 16 * s, 12 * s, 8 * s, 12 * s)
			tri(shape, 2, 1, 3, 8 * s, 12 * s, 16 * s, 12 * s, 12 * s, 21 * s)
			tri(shape, 3, 1, 3, 3 * s, 12 * s, 12 * s, 8 * s, 12 * s, 16 * s)
			tri(shape, 4, 1, 3, 21 * s, 12 * s, 12 * s, 16 * s, 12 * s, 8 * s)
		else
			tri(shape, 1, 1, 3, 3 * s, 7 * s, 11 * s, 11 * s, 11 * s, 19 * s)
			tri(shape, 2, 1, 3, 21 * s, 7 * s, 13 * s, 19 * s, 13 * s, 11 * s)
			circ(shape, 3, 1, 3, 12 * s, 6 * s, 2 * s)
		end
	elseif id == "heresy" then
		-- a broken halo and an inverted blade: a ring, cut through at the upper left by a gap in the card's colour, and in it a
		-- blade that points down with a pommel on top
		circ(shape, 1, 1, 1, 12 * s, 12 * s, 10.2 * s)
		circ(shape, 2, 2, 2, 12 * s, 12 * s, 8.2 * s)
		tri(shape, 1, 2, 3, 5.2 * s, 2.4 * s, 8.9 * s, 6.1 * s, 6.1 * s, 8.9 * s)
		tri(shape, 2, 2, 3, 5.2 * s, 2.4 * s, 6.1 * s, 8.9 * s, 2.4 * s, 5.2 * s)
		tri(shape, 3, 1, 4, 8.6 * s, 7.4 * s, 15.4 * s, 7.4 * s, 12 * s, 20.4 * s)
		circ(shape, 3, 1, 4, 12 * s, 5.4 * s, 2 * s)
	elseif id == "nightmare" then
		-- a horned eye: two horns, a ring of an eye with a slit pupil, and a black tear under it
		tri(shape, 1, 1, 1, 3 * s, 2 * s, 9.6 * s, 7.6 * s, 6.4 * s, 9.8 * s)
		tri(shape, 2, 1, 1, 21 * s, 2 * s, 17.6 * s, 9.8 * s, 14.4 * s, 7.6 * s)
		circ(shape, 1, 1, 1, 12 * s, 13.5 * s, 7.6 * s)
		circ(shape, 2, 2, 2, 12 * s, 13.5 * s, 5.7 * s)
		tri(shape, 3, 1, 3, 12 * s, 8.2 * s, 13.5 * s, 13.5 * s, 10.5 * s, 13.5 * s)
		tri(shape, 4, 1, 3, 10.5 * s, 13.5 * s, 13.5 * s, 13.5 * s, 12 * s, 18.8 * s)
		circ(shape, 3, 1, 3, 12 * s, 22.6 * s, 1.2 * s)
	elseif id == "warp" then
		-- an eye in a triangle
		tri(shape, 1, 1, 1, 12 * s, 2.2 * s, 22 * s, 20.5 * s, 2 * s, 20.5 * s)
		tri(shape, 2, 2, 2, 12 * s, 8.2 * s, 18 * s, 18.2 * s, 6 * s, 18.2 * s)
		tri(shape, 3, 1, 3, 8.8 * s, 14.2 * s, 12 * s, 11.8 * s, 15.2 * s, 14.2 * s)
		tri(shape, 4, 1, 3, 8.8 * s, 14.2 * s, 15.2 * s, 14.2 * s, 12 * s, 16.6 * s)
		circ(shape, 1, 2, 4, 12 * s, 14.2 * s, 1.1 * s)
	else -- star: two thin diamonds crossing
		tri(shape, 1, 1, 1, 12 * s, 2 * s, 15.4 * s, 12 * s, 8.6 * s, 12 * s)
		tri(shape, 2, 1, 1, 8.6 * s, 12 * s, 15.4 * s, 12 * s, 12 * s, 22 * s)
		tri(shape, 3, 1, 1, 2 * s, 12 * s, 12 * s, 8.6 * s, 12 * s, 15.4 * s)
		tri(shape, 4, 1, 1, 22 * s, 12 * s, 12 * s, 8.6 * s, 12 * s, 15.4 * s)
	end
end

-- --------------------------------------------------------------------------------------------- Nightmare's fog
-- The fog over a card `ch` high at time t (catalog/cards.lua Cards.fog): writes { top, height, alpha } of each bank into
-- out[1..FOG_BANDS] (inside the card: a bank cut at its edges) and returns the alpha of the veil over the whole card.
Spread.FOG_HEIGHT = 0.45 -- of the card's height, one bank
Spread.FOG_ALPHA, Spread.VEIL_ALPHA = 215, 165

Spread.fog = function (Cards, t, ch, out, percent)
	local veil_alpha, bank_alpha = Spread.darkness(Spread.VEIL_ALPHA, percent), Spread.darkness(Spread.FOG_ALPHA, percent)

	for i = 1, Cards.FOG_BANDS do
		local centre, thick = Cards.fog(t, i)
		local half = ch * Spread.FOG_HEIGHT / 2
		local top, bottom = max(0, centre * ch - half), min(ch, centre * ch + half)
		local bank = out[i]

		bank[1], bank[2], bank[3] = top, max(0, bottom - top), floor(bank_alpha * thick + 0.5)
	end

	return floor(veil_alpha * Cards.fog(t) + 0.5)
end

-- The option "Nightmare darkness" (nightmare_fog_strength, percent; 2026-10-04, the user: "100 almost completely dark, 30 the
-- baseline we use"): the strongest alpha of a dark layer whose baseline (at DARK_BASE percent) is `base`: none at 0, `base` at 30,
-- DARK_MAX (almost black) at 100, straight lines between.
Spread.DARK_BASE, Spread.DARK_MAX = 30, 245

Spread.darkness = function (base, percent)
	percent = math.max(0, math.min(100, tonumber(percent) or Spread.DARK_BASE))

	if percent <= Spread.DARK_BASE then
		return base * percent / Spread.DARK_BASE
	end

	return base + (math.max(base, Spread.DARK_MAX) - base) * (percent - Spread.DARK_BASE) / (100 - Spread.DARK_BASE)
end

Spread.new_fog = function ()
	return { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } }
end

-- ----------------------------------------------------------------------------------------------- the feather
-- The UI draws triangles, circles and rotated squares without anti-aliasing, so their edges stair-step. Under every such
-- shape goes a faint copy that is FEATHER units larger: the edge then has a soft step between the shape and the
-- background, which the eye reads as a smooth edge. Callers draw the copy with FEATHER_ALPHA of the shape's opacity.
Spread.FEATHER = 0.55
Spread.FEATHER_ALPHA = 0.30

-- The corners of a triangle slot, each pushed `grow` units away from the triangle's centre, written into `corners`
-- ({ { x, y }, { x, y }, { x, y } }) without allocating.
Spread.write_corners = function (corners, slot, grow)
	local x1, y1, x2, y2, x3, y3 = slot.x1, slot.y1, slot.x2, slot.y2, slot.x3, slot.y3

	if grow and grow > 0 then
		local cx, cy = (x1 + x2 + x3) / 3, (y1 + y2 + y3) / 3
		local d1 = max(1e-6, sqrt((x1 - cx) ^ 2 + (y1 - cy) ^ 2))
		local d2 = max(1e-6, sqrt((x2 - cx) ^ 2 + (y2 - cy) ^ 2))
		local d3 = max(1e-6, sqrt((x3 - cx) ^ 2 + (y3 - cy) ^ 2))

		x1, y1 = x1 + (x1 - cx) / d1 * grow, y1 + (y1 - cy) / d1 * grow
		x2, y2 = x2 + (x2 - cx) / d2 * grow, y2 + (y2 - cy) / d2 * grow
		x3, y3 = x3 + (x3 - cx) / d3 * grow, y3 + (y3 - cy) / d3 * grow
	end

	corners[1][1], corners[1][2], corners[2][1], corners[2][2], corners[3][1], corners[3][2] = x1, y1, x2, y2, x3, y3
end

-- ------------------------------------------------------------------------------------------------- colours
-- The rot's brown wash and the card colours are plain {r, g, b}; these write {a, r, g, b} into a style colour.
Spread.set_color = function (target, alpha, rgb)
	target[1], target[2], target[3], target[4] = alpha, rgb[1], rgb[2], rgb[3]
end

-- rgb pulled toward its own grey by t (0 = unchanged, 1 = completely grey), written into `out` (returned)
Spread.grey = function (out, rgb, t)
	local grey = 0.299 * rgb[1] + 0.587 * rgb[2] + 0.114 * rgb[3]

	out[1], out[2], out[3] = rgb[1] + (grey - rgb[1]) * t, rgb[2] + (grey - rgb[2]) * t, rgb[3] + (grey - rgb[3]) * t

	return out
end

Spread.set_alpha = function (target, alpha)
	target[1] = alpha
end

-- Opacity (0..255) from a 0..1 factor
Spread.alpha = function (factor)
	return floor(clamp(factor, 0, 1) * 255 + 0.5)
end

return Spread
