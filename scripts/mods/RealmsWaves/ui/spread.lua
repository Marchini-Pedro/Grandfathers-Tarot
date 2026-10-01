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

-- How many lines a name takes in a box `width` wide (a greedy word wrap with an average glyph width), at most 3.
local GLYPH = 0.54 -- of the font size

Spread.wrap_lines = function (text, width, font_size)
	local per_line = max(1, floor(width / (font_size * GLYPH)))
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

	return min(3, lines)
end

Spread.new_layout = function ()
	return { count = 0, cw = 176, ch = Spread.MIN_CARD_HEIGHT, lines = 1, name_w = 120, total_w = 0, x0 = 0, x = { 0, 0, 0, 0, 0 }, fuse_y = 0, banner_y = 0 }
end

-- Positions of the cards in the node for a hand (cards with a `name`), written into `layout`.
Spread.layout = function (layout, hand)
	local count = min(#hand, Spread.MAX_CARDS)
	local cw = Spread.card_width(count)
	local name_w = cw - Spread.ACCENT_WIDTH - 2 * Spread.PAD_X - Spread.ICON - Spread.ICON_GAP
	local lines = 1

	for i = 1, count do
		lines = max(lines, Spread.wrap_lines(hand[i].name, name_w, Spread.NAME_FONT))
	end

	local ch = max(Spread.MIN_CARD_HEIGHT, 2 * Spread.PAD_Y + lines * Spread.NAME_LINE + 4 + Spread.ROW_HEIGHT)
	local total = count * cw + max(0, count - 1) * Spread.GAP

	layout.count, layout.cw, layout.ch, layout.lines, layout.name_w, layout.total_w = count, cw, ch, lines, name_w, total
	layout.x0 = floor((Spread.NODE_WIDTH - total) / 2)

	for i = 1, Spread.MAX_CARDS do
		layout.x[i] = layout.x0 + (i - 1) * (cw + Spread.GAP)
	end

	layout.fuse_y = Spread.CARDS_Y + ch + Spread.FUSE_GAP
	layout.banner_y = layout.fuse_y + Spread.FUSE_HEIGHT + Spread.BANNER_GAP

	return layout
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
	return { stage = "waiting", count = 0, hi = 0, fuse = 0, urgent = false, reveal_t = 0, pop = 0, lose = 1, eye = 0, rot_p = 0 }
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
	out.reveal_t, out.pop, out.lose, out.eye, out.rot_p = 0, 0, 1, 0, 0

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
Spread.MAX_FLIES = MAX_FLIES
Spread.DRIPS = DRIPS

Spread.new_rot = function ()
	local fx = { blotch = {}, flies = {}, drips = {}, wash = 0, shrink = 1, fade = 1, bright = 1 }

	for i = 1, #BLOTCH do
		fx.blotch[i] = { circle = false, rect = false, cx = 0, cy = 0, r = 0, x0 = 0, y0 = 0, x1 = 0, y1 = 0 }
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
-- A blotch is a circle while it fits inside the card and a clipped square once it does not (the UI cannot clip shapes).
Spread.rot_fx = function (fx, r, k, cw, ch, time)
	r, k = clamp(r, 0, 1), clamp(k, 0, 1)

	local size = 14 + 52 * k

	fx.shrink = 1 - r * 0.22 * (0.4 + k) -- the card sags from its top edge
	fx.fade = 1 - max(0, r - 0.62) * 2.6
	fx.fade = clamp(fx.fade, 0, 1)
	fx.bright = 1 - r * 0.4
	fx.wash = r * 0.55 -- opacity of the brown wash over the whole card

	local height = ch * fx.shrink

	for i = 1, #BLOTCH do
		local spec, blotch = BLOTCH[i], fx.blotch[i]
		local radius = r * size * spec[3]
		local cx, cy = spec[1] * cw, spec[2] * height

		blotch.circle, blotch.rect = false, false

		if radius >= 0.75 then
			if radius <= min(cx, cw - cx, cy, height - cy) then
				blotch.circle, blotch.cx, blotch.cy, blotch.r = true, cx, cy, radius
			else
				blotch.rect = true
				blotch.x0, blotch.y0, blotch.x1, blotch.y1 = max(0, cx - radius), max(0, cy - radius), min(cw, cx + radius), min(height, cy + radius)
			end
		end
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
		drip.y = height + 34 * u
		drip.h = drip_height
		drip.alpha = (u < 0.2 and 0.9 * u / 0.2 or 0.9 * (1 - u) / 0.8) * 1
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

	slot.on, slot.col, slot.z = true, col, z
	slot.x1, slot.y1, slot.x2, slot.y2, slot.x3, slot.y3 = x1, y1, x2, y2, x3, y3
end

local function circ(shape, index, col, z, cx, cy, radius)
	local slot = shape.circ[index]

	slot.on, slot.col, slot.z = true, col, z
	slot.cx, slot.cy, slot.r = cx, cy, radius
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

-- The eye: a lens whose height is the opening (0 = shut, a thin sliver with three lashes; 1 = open, an outline with a
-- pupil). `size` is the width of the box (the eye is drawn in a size x size box, centred). Slots: tri 1-2 the lens,
-- 3-4 the inside (card colour, once it is open enough to have one), 5-7 the lashes; circ 1 the pupil. Returns the
-- opacity of the pupil and of the lashes (0..1).
Spread.eye = function (size, open, shape)
	open = clamp(open, 0, 1)
	clear(shape)

	local a = size * 20 / 24 / 2
	local b = max(size * 0.03, size * 14 / 24 / 2 * (0.12 + 0.88 * open))
	local cx, cy = size / 2, size / 2

	lens(shape, 1, 1, 1, cx, cy, a, b)

	-- the inside is the same diamond pulled in by the stroke, so the line is as thick everywhere
	local stroke = size * 1.6 / 24
	local factor = 1 - stroke * sqrt(a * a + b * b) / (a * b)
	local pupil_radius = size * 3 / 24
	local pupil = 0

	if factor > 0.06 then
		lens(shape, 3, 2, 2, cx, cy, a * factor, b * factor)

		if b * factor > pupil_radius * 0.9 then
			circ(shape, 1, 1, 3, cx, cy, pupil_radius)

			pupil = open
		end
	end

	local lashes = 0

	if open < 0.5 then
		lashes = 1 - open * 2

		for i = 1, 3 do
			local dx = (i - 2) * a * 0.55
			local base_y = cy + b * (1 - math.abs(dx) / a)
			local x = cx + dx

			tri(shape, 4 + i, 1, 1, x - size * 0.035, base_y - 0.5, x + size * 0.035, base_y - 0.5, x + (i - 2) * size * 0.05, base_y + size * 0.17)
		end
	end

	return pupil, lashes
end

Spread.ICON_TRIS = 4
Spread.ICON_CIRCS = 4
Spread.EYE_TRIS = 7
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
	else -- star: two thin diamonds crossing
		tri(shape, 1, 1, 1, 12 * s, 2 * s, 15.4 * s, 12 * s, 8.6 * s, 12 * s)
		tri(shape, 2, 1, 1, 8.6 * s, 12 * s, 15.4 * s, 12 * s, 12 * s, 22 * s)
		tri(shape, 3, 1, 1, 2 * s, 12 * s, 12 * s, 8.6 * s, 12 * s, 15.4 * s)
		tri(shape, 4, 1, 1, 22 * s, 12 * s, 12 * s, 8.6 * s, 12 * s, 15.4 * s)
	end
end

-- ------------------------------------------------------------------------------------------------- colours
-- The rot's brown wash and the card colours are plain {r, g, b}; these write {a, r, g, b} into a style colour.
Spread.set_color = function (target, alpha, rgb)
	target[1], target[2], target[3], target[4] = alpha, rgb[1], rgb[2], rgb[3]
end

Spread.set_alpha = function (target, alpha)
	target[1] = alpha
end

-- Opacity (0..255) from a 0..1 factor
Spread.alpha = function (factor)
	return floor(clamp(factor, 0, 1) * 255 + 0.5)
end

return Spread
