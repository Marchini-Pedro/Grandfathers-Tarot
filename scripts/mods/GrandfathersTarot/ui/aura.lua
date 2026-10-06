-- The aura of a card (2026-10-05, the user: "a fire like effect on Rage, a plague like effect on Plague, a thematic effect for every
-- suit, both in the Deck and in the HUD / last card; a new suit, Dream, cloudy and heavenly"; then "all the effects should
-- increase / decrease with the card's difficulty"): small shapes that live on the face of a card, one animation per suit, drawn
-- under its text, growing with the card's threat (1 to 6): more shapes, larger, brighter, and at 5 and 6 more of their own (Swarm's
-- second cloud, Fateful's falling star, Entrapment's second chain, Heresy's lightning...). Pure arithmetic with no engine
-- calls, so it is tested offline (tools/hud_test.py); the Deck's tiles (ui/wave_editor_deck.lua), the Spread
-- (ui/hud_element_waves.lua) and the last card (ui/last_card_paint.lua) each have Aura.COUNT circle passes, Aura.COUNT rect passes
-- and Aura.TRIS triangle passes for it, and draw it with Aura.draw.
--
-- Aura.update(out, suit, t, w, h, s, level) writes the particles of `suit` (an id of catalog/cards.lua) at time t on a card w x h
-- into `out` (Aura.new()): each one { on, round, x, y, w, h, a, rgb }, and out.tri[i] { on, x1, y1, x2, y2, x3, y3, a, rgb }, the
-- coordinates from the card's top left, a the opacity 0..255. `s` is the size of the shapes (1 on the Deck's tile; the HUD's smaller
-- cards use less), `level` the card's threat (Aura.LEVEL when not given). Every shape stays inside the card (the UI cannot clip).
-- Nothing is allocated while it runs. Nightmare has its own fog and no aura; Heresy its blood, and lightning at threat 5 and 6.
local Aura = {}

local floor, sin, cos, abs, max, min, pi = math.floor, math.sin, math.cos, math.abs, math.max, math.min, math.pi

Aura.COUNT = 28 -- circles and rects
Aura.TRIS = 8 -- triangles: Heresy's lightning
Aura.LEVEL = 4 -- the threat used when none is given

Aura.new = function ()
	local out = { tri = {} }

	for i = 1, Aura.COUNT do
		out[i] = { on = false, round = true, x = 0, y = 0, w = 0, h = 0, a = 0, rgb = { 0, 0, 0 } }
	end

	for i = 1, Aura.TRIS do
		out.tri[i] = { on = false, x1 = 0, y1 = 0, x2 = 0, y2 = 0, x3 = 0, y3 = 0, a = 0, rgb = { 0, 0, 0 } }
	end

	return out
end

-- a number 0..1 that looks random and is always the same for the same i and salt
local function hash(i, salt)
	local v = sin(i * 12.9898 + salt * 78.233) * 43758.5453

	return v - floor(v)
end

Aura.hash = hash

local function clamp(v, lo, hi)
	return max(lo, min(hi, v))
end

-- 0 at the ends of a life u (0..1), 1 in its middle
local function bell(u)
	return sin(pi * clamp(u, 0, 1))
end

local function rgb_into(target, rgb)
	target[1], target[2], target[3] = rgb[1], rgb[2], rgb[3]
end

local function lerp_into(target, a, b, k)
	target[1], target[2], target[3] = a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k
end

-- Hue (0..1), saturation and value (0..1) to { r, g, b } 0..255, written into `target`
local function hsv_into(target, h, s, v)
	h = (h % 1) * 6

	local i = floor(h)
	local f = h - i
	local p, q, u = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
	local r, g, b

	if i == 0 then
		r, g, b = v, u, p
	elseif i == 1 then
		r, g, b = q, v, p
	elseif i == 2 then
		r, g, b = p, v, u
	elseif i == 3 then
		r, g, b = p, q, v
	elseif i == 4 then
		r, g, b = u, p, v
	else
		r, g, b = v, p, q
	end

	target[1], target[2], target[3] = r * 255, g * 255, b * 255
end

Aura.hsv_into = hsv_into

-- how many of something a card of threat `lv` has: `lo` at 1, `hi` at 6
local function amount(lv, lo, hi)
	return floor(lo + (hi - lo) * (lv - 1) / 5 + 0.5)
end

Aura.amount = amount

-- the opacity of every shape at threat lv (0.62 at 1, 1 at 6) and the size of the shapes (0.85 at 1, 1.05 at 6)
Aura.strength = function (lv)
	return 0.62 + 0.076 * (clamp(lv, 1, 6) - 1)
end

local function size_of(lv)
	return 0.85 + 0.04 * (lv - 1)
end

-- one particle: kept inside the card (a shape larger than the card is shrunk to it)
local function put(p, round, x, y, w, h, a, W, H)
	w, h = min(w, W), min(h, H)
	p.on = a >= 1 and w > 0.2 and h > 0.2
	p.round, p.w, p.h = round, w, h
	p.x, p.y = clamp(x, 0, W - w), clamp(y, 0, H - h)
	p.a = floor(clamp(a, 0, 255) + 0.5)
end

-- one triangle, every corner kept inside the card
local function put_tri(q, x1, y1, x2, y2, x3, y3, a, W, H)
	q.x1, q.y1, q.x2, q.y2, q.x3, q.y3 = clamp(x1, 0, W), clamp(y1, 0, H), clamp(x2, 0, W), clamp(y2, 0, H), clamp(x3, 0, W), clamp(y3, 0, H)
	q.a = floor(clamp(a, 0, 255) + 0.5)
	q.on = q.a >= 1
end

-- the life of particle i: 0..1 through it at time t, with its own period
local function life(t, i, period, salt)
	return (t / period + hash(i, salt or 2)) % 1
end

-- ------------------------------------------------------------------------------------------------- colours
local ANGER, ANGER_DEEP, ANGER_GLOW_LOW, ANGER_GLOW_HIGH = { 214, 28, 18 }, { 110, 6, 6 }, { 120, 16, 10 }, { 255, 52, 30 }
local BILE, BILE_DARK, FLY = { 183, 194, 58 }, { 120, 140, 40 }, { 150, 160, 90 }
local MURMUR_A, MURMUR_B = { 207, 202, 176 }, { 157, 176, 127 }
local PUS, PUS_DARK = { 227, 207, 74 }, { 150, 132, 40 }
local SWARM_A, SWARM_B = { 175, 182, 140 }, { 110, 116, 88 }
local BONE, BRASS = { 239, 230, 201 }, { 205, 178, 100 }
local TRACER, TRACER_HOT, SPARK = { 127, 178, 194 }, { 220, 244, 252 }, { 255, 226, 160 }
local LINK_A, LINK_B = { 95, 191, 165 }, { 60, 120, 105 }
local BRICK, BRICK_DARK, DUST, BRICK_FLASH, CRACK = { 207, 92, 69 }, { 130, 60, 48 }, { 190, 160, 140 }, { 255, 170, 140 }, { 40, 18, 14 }
local WARP, WARP_LIT = { 177, 132, 224 }, { 234, 214, 255 }
local RAY = { 255, 236, 190 }
local GOLD, GOLD_LIT = { 216, 180, 90 }, { 255, 242, 207 }
local WHITE, SILVER = { 248, 250, 252 }, { 200, 214, 228 }
local ROSE, ROSE_DEEP, ROSE_PALE = { 240, 140, 184 }, { 194, 90, 140 }, { 255, 205, 226 }
local CLOUD_HEART = { 255, 250, 255 }
local BOLT, FLASH = { 236, 236, 255 }, { 220, 222, 255 }

-- the warp's crackle at time t (as Cards.warp_pulse: about one beat in eight at 14 a second)
local function crackle(t)
	local h = (sin(floor(t * 14) * 78.233) * 12543.873) % 1

	return h > 0.88 and 1 or 0
end

-- a twinkling cross (two thin rects) in out[a] and out[b], centre (cx, cy), arm length `arm`
local function sparkle(out, a, b, cx, cy, arm, thick, alpha, rgb, W, H)
	local ha, hb = out[a], out[b]

	rgb_into(ha.rgb, rgb)
	rgb_into(hb.rgb, rgb)
	put(ha, false, cx - arm, cy - thick / 2, arm * 2, thick, alpha, W, H)
	put(hb, false, cx - thick / 2, cy - arm, thick, arm * 2, alpha, W, H)
end

-- ------------------------------------------------------------------------------------------------- the suits
-- Every effect is (out, t, W, H, s, lv): s already holds the threat's size, lv is the threat 1..6
local EFFECTS = {}

-- RAGE (2026-10-05, the user: "remove the rage animation; the whole card turns more red, more angry, the higher the difficulty"): a
-- red heat floods the card's face, darker and deeper at its edges, and it throbs like blood in the temples. The higher the threat
-- the redder the face, the deeper the edges and the faster the throb (Aura.anger).
Aura.anger = function (t, lv)
	local rate = 0.6 + 0.22 * lv -- throbs a second
	local throb = (0.5 + 0.5 * sin(t * 2 * pi * rate)) ^ 2

	return (lv - 1) / 5, throb
end

EFFECTS.rage = function (out, t, W, H, s, lv)
	local heat, throb = Aura.anger(t, lv)

	rgb_into(out[1].rgb, ANGER)
	put(out[1], false, 0, 0, W, H, (28 + 100 * heat) * (0.75 + 0.25 * throb), W, H)

	-- the edges: three bands a side, each wider than the one before, so the red deepens towards the frame
	for band = 1, 3 do
		local depth = band * (3 + 2.4 * lv) * s
		local alpha = (14 + 30 * heat) * (0.65 + 0.35 * throb)
		local first = 2 + (band - 1) * 4

		for k = 0, 3 do
			rgb_into(out[first + k].rgb, ANGER_DEEP)
		end

		put(out[first], false, 0, 0, W, depth, alpha, W, H)
		put(out[first + 1], false, 0, H - depth, W, depth, alpha, W, H)
		put(out[first + 2], false, 0, depth, depth, H - 2 * depth, alpha, W, H)
		put(out[first + 3], false, W - depth, depth, depth, H - 2 * depth, alpha, W, H)
	end
end

-- PLAGUE: bile bubbles rise and swell and pop near the top; flies buzz around them
EFFECTS.plague = function (out, t, W, H, s, lv)
	for i = 1, amount(lv, 4, 12) do
		local u = life(t, i, 2.6 + 1.4 * hash(i, 1))
		local pop = u > 0.88 and 1 + (u - 0.88) * 4 or 1
		local d = s * (4 + 6 * hash(i, 4)) * (0.55 + 0.45 * u) * pop
		local x = W * (0.06 + 0.88 * hash(i, 3)) + sin(t * 1.6 + i * 2) * 4 * s
		local fade = min(1, u / 0.1) * (u > 0.88 and (1 - u) / 0.12 or 1)
		local p = out[i]

		lerp_into(p.rgb, BILE, BILE_DARK, hash(i, 5))
		put(p, true, x, H * (1 - u) - d / 2, d, d, 150 * fade, W, H)
	end

	for i = 1, amount(lv, 2, 8) do
		local cx = W * (0.3 + 0.4 * hash(i, 5)) + sin(t * 0.7 + i) * W * 0.18
		local cy = H * (0.3 + 0.3 * hash(i, 6)) + cos(t * 0.9 + i) * H * 0.12
		local x = cx + sin(t * 17 + i * 3) * 6 * s + cos(t * 7.3 + i) * 4 * s
		local y = cy + cos(t * 13 + i) * 5 * s
		local d = 2.6 * s
		local p = out[12 + i]

		rgb_into(p.rgb, FLY)
		put(p, true, x - d / 2, y - d / 2, d, d, 210, W, H)
	end
end

-- MURMUR: pale lights drift slowly over the card and blink in and out, like whispers (more and brighter as the threat grows; at 5
-- and 6 every letter on the card murmurs too: ui/murmur_text.lua)
EFFECTS.murmur = function (out, t, W, H, s, lv)
	for i = 1, amount(lv, 5, 20) do
		local x = W * (0.5 + 0.44 * sin(t * 0.31 * (1 + 0.3 * hash(i, 1)) + i * 2.1))
		local y = H * (0.5 + 0.44 * sin(t * 0.23 * (1 + 0.4 * hash(i, 2)) + i * 1.3))
		local blink = max(0, sin(t * (0.7 + 0.6 * hash(i, 3)) + i * 3))
		local d = s * (2.5 + (1.5 + 0.3 * lv) * blink)
		local p = out[i]

		lerp_into(p.rgb, MURMUR_A, MURMUR_B, hash(i, 4))
		put(p, true, x - d / 2, y - d / 2, d, d, (150 + 10 * lv) * blink * blink, W, H)
	end
end

-- BLIGHT: drops of pus fall from the top, each with a trail, and burst into two droplets where they land in the pool of pus that
-- lies along the foot, its surface trembling
EFFECTS.blight = function (out, t, W, H, s, lv)
	local depth = (4 + 1.2 * lv) * s
	local surface = H - depth + sin(t * 2.1) * 0.8 * s

	for i = 1, amount(lv, 2, 6) do
		local u = life(t, i, 1.7 + 1.1 * hash(i, 1))
		local d = s * (3.5 + 1.5 * hash(i, 4))
		local x = W * (0.08 + 0.84 * hash(i + floor(t / 1.7 + hash(i, 2)) * 7, 3))
		local drop, trail, left, right = out[i], out[6 + i], out[11 + 2 * i], out[12 + 2 * i]

		rgb_into(drop.rgb, PUS)
		rgb_into(trail.rgb, PUS)
		rgb_into(left.rgb, PUS)
		rgb_into(right.rgb, PUS)

		if u < 0.8 then
			local fall = u / 0.8
			local y = fall * fall * (surface - d)
			local length = s * 10 * fall

			put(drop, true, x, y, d, d, 215 * min(1, fall / 0.1), W, H)
			put(trail, false, x + d / 2 - 0.75 * s, y - length + d / 2, 1.5 * s, length, 120, W, H)
		else
			-- the splash: two droplets thrown up and out of the pool
			local k = (u - 0.8) / 0.2
			local spread = (5 + 7 * hash(i, 5)) * s * k
			local rise = 9 * s * (4 * k * (1 - k))
			local dd = 2.2 * s

			put(left, true, x + d / 2 - spread - dd / 2, surface - rise - dd, dd, dd, 220 * (1 - k), W, H)
			put(right, true, x + d / 2 + spread - dd / 2, surface - rise - dd, dd, dd, 220 * (1 - k), W, H)
		end
	end

	-- the pool, and its bright surface
	rgb_into(out[25].rgb, PUS_DARK)
	put(out[25], false, 0, surface, W, H - surface, 150, W, H)
	rgb_into(out[26].rgb, PUS)
	put(out[26], false, 0, surface - 0.5 * s, W, 1.5 * s, 200 + 40 * sin(t * 3), W, H)
end

-- SWARM: a cloud of tiny things whirls around a centre that wanders over the card; the higher the threat the bigger and faster the
-- cloud, and at 5 and 6 a second cloud whirls the other way
EFFECTS.swarm = function (out, t, W, H, s, lv)
	local n = amount(lv, 8, 26)
	local split = lv >= 5 and floor(n * 0.4) or 0
	local reach = min(W, H) * (0.85 + 0.07 * lv)
	local speed = 0.8 + 0.12 * lv

	for i = 1, n do
		local second = i > n - split
		local cx = second and W * (0.5 - 0.25 * sin(t * 0.43)) or W * (0.5 + 0.22 * sin(t * 0.5))
		local cy = second and H * (0.55 + 0.2 * cos(t * 0.31)) or H * (0.45 + 0.18 * sin(t * 0.37))
		local r = reach * (0.1 + 0.24 * hash(i, 1)) * (second and 0.7 or 1)
		local angle = t * speed * (1.8 + 2.4 * hash(i, 2)) * ((i % 2 == 0) ~= second and 1 or -1) + i
		local x = cx + cos(angle) * r * 1.4 + sin(t * 11 + i * 5) * 2 * s
		local y = cy + sin(angle) * r + cos(t * 9 + i) * 2 * s
		local d = s * (1.8 + 1.2 * hash(i, 3))
		local p = out[i]

		lerp_into(p.rgb, SWARM_A, SWARM_B, hash(i, 4))
		put(p, true, x - d / 2, y - d / 2, d, d, 195, W, H)
	end
end

-- FATEFUL: stars twinkle in the dark of the card and the dust of the last page sifts down through it; at 5 and 6 a star falls
EFFECTS.fateful = function (out, t, W, H, s, lv)
	for i = 1, amount(lv, 2, 6) do
		local twinkle = max(0, sin(t * 1.1 + i * 2.3))
		local cx, cy = W * (0.12 + 0.76 * hash(i, 7)), H * (0.1 + 0.55 * hash(i, 8))

		sparkle(out, i * 2 - 1, i * 2, cx, cy, (2 + (5 + lv) * twinkle * twinkle) * s, 1.3 * s, 230 * twinkle, i % 2 == 0 and BRASS or BONE, W, H)
	end

	for i = 1, amount(lv, 3, 10) do
		local u = life(t, 12 + i, 4 + 2 * hash(i, 1))
		local x = W * hash(i, 3) + sin(t * 0.9 + i) * 5 * s
		local p = out[12 + i]

		rgb_into(p.rgb, BRASS)
		put(p, false, x, u * H, 2 * s, 2 * s, 160 * bell(u), W, H)
	end

	if lv >= 5 then
		-- the falling star: a bright head and its tail, across the card and down, now and then (more often at 6)
		local cycle = t / (lv >= 6 and 2.2 or 3.4)
		local u = cycle % 1

		if u < 0.35 then
			local k = u / 0.35
			local n = floor(cycle)
			local x0, y0 = W * (0.1 + 0.3 * hash(n, 4)), H * (0.08 + 0.2 * hash(n, 5))
			local x, y = x0 + W * 0.6 * k, y0 + H * 0.3 * k
			local tail = 22 * s * min(1, k * 4)
			local head, streak = out[23], out[24]

			rgb_into(head.rgb, BONE)
			put(head, true, x - 2.2 * s, y - 2.2 * s, 4.4 * s, 4.4 * s, 255 * (1 - k * k), W, H)
			rgb_into(streak.rgb, BRASS)
			put(streak, false, x - tail, y - 0.7 * s, tail, 1.4 * s, 200 * (1 - k * k), W, H)
		end
	end
end

-- VOLLEY: bullets fly across the card: a brass slug with a white-hot nose and a fading tracer behind it, and a spark where it strikes
-- the far edge; two at a time on a quiet card, seven and faster at 6
EFFECTS.volley = function (out, t, W, H, s, lv)
	local flight = 0.22

	for i = 1, amount(lv, 2, 7) do
		local period = 0.95 + 0.7 * hash(i, 1) - 0.07 * lv
		local cycle = t / period + hash(i, 2)
		local u = cycle % 1
		local y = H * (0.1 + 0.8 * hash(i * 7 + floor(cycle), 3))
		local trail, slug, nose, spark = out[i], out[7 + i], out[14 + i], out[21 + i]
		local slug_w, slug_h = 8 * s, 2.8 * s

		if u < flight then
			local k = u / flight
			local x = (W - slug_w) * k
			local length = min(x, (26 + 18 * hash(i, 4)) * s)

			rgb_into(trail.rgb, TRACER)
			put(trail, false, x - length, y + slug_h / 2 - 0.6 * s, length, 1.2 * s, 150, W, H)
			rgb_into(slug.rgb, BRASS)
			put(slug, false, x, y, slug_w, slug_h, 250, W, H)
			rgb_into(nose.rgb, TRACER_HOT)
			put(nose, true, x + slug_w - 1.6 * s, y - 0.2 * s, 3.2 * s, slug_h + 0.4 * s, 255, W, H)
		elseif u < flight + 0.12 then
			local k = (u - flight) / 0.12
			local d = (4 + 10 * k) * s

			rgb_into(spark.rgb, SPARK)
			put(spark, true, W - d, y + slug_h / 2 - d / 2, d, d, 230 * (1 - k), W, H)
		end
	end
end

-- ENTRAPMENT (the suit "snare"): a chain of links creeps round the card's edge, the loop tightening and loosening; more links as the
-- threat grows, and at 5 and 6 a second chain closes inside it the other way
local function chain(out, first, n, t, W, H, s, inset, speed)
	local w, h = W - 2 * inset, H - 2 * inset
	local around = 2 * (w + h)

	for i = 1, n do
		local d = (t * speed * s + (i - 1) * around / n) % around
		local x, y

		if d < w then
			x, y = inset + d, inset
		elseif d < w + h then
			x, y = inset + w, inset + d - w
		elseif d < 2 * w + h then
			x, y = inset + w - (d - w - h), inset + h
		else
			x, y = inset, inset + h - (d - 2 * w - h)
		end

		local size = 4.5 * s
		local p = out[first + i - 1]

		rgb_into(p.rgb, i % 2 == 0 and LINK_A or LINK_B)
		put(p, true, x - size / 2, y - size / 2, size, size, 160, W, H)
	end
end

EFFECTS.snare = function (out, t, W, H, s, lv)
	chain(out, 1, amount(lv, 8, 18), t, W, H, s, (6 + 2 * sin(t * 1.4)) * s, 18 + 2 * lv)

	if lv >= 5 then
		chain(out, 19, lv >= 6 and 10 or 8, t, W, H, s, (18 + 4 * sin(t * 1.9)) * s, -(16 + 2 * lv))
	end
end

-- BRUTE: a blow lands at the foot of the card (more often as the threat grows): the floor cracks, a shock runs along it, dust bursts
-- up and chunks of brick fly high and fall back
Aura.brute_period = function (lv)
	return 2.3 - 0.1 * clamp(tonumber(lv) or Aura.LEVEL, 1, 6)
end

EFFECTS.brute = function (out, t, W, H, s, lv)
	local period = Aura.brute_period(lv)
	local tau = t % period
	local blow = tau / period

	for i = 1, amount(lv, 5, 14) do
		local p = out[i]
		local side = i % 2 == 0 and 1 or -1
		local vx = side * (25 + 70 * hash(i, 1)) * s
		local vy = (80 + 100 * hash(i, 2) + 6 * lv) * s
		local g = 170 * s
		local x = W / 2 + vx * tau
		local y = H - 4 * s - (vy * tau - g * tau * tau)
		local size = (3 + 4.5 * hash(i, 3)) * s
		local alpha = blow < 0.7 and 250 * (1 - (blow / 0.7) ^ 2) or 0
		local rock = i % 3 == 0 and DUST or i % 3 == 1 and BRICK or BRICK_DARK

		rgb_into(p.rgb, rock)
		put(p, false, x - size / 2, y - size, size, size, y > H and 0 or alpha, W, H)
	end

	-- the dust: puffs swell from the point of the blow and thin away
	local puffs = amount(lv, 2, 6)

	for i = 1, puffs do
		local k = min(1, blow * 3)
		local d = (8 + 46 * k) * s * (0.7 + 0.5 * hash(i, 1))
		local cx = W / 2 + (i - (puffs + 1) / 2) * 16 * s * (0.4 + k)
		local p = out[14 + i]

		rgb_into(p.rgb, DUST)
		put(p, true, cx - d / 2, H - d * 0.75, d, d, 120 * (1 - k), W, H)
	end

	-- the shock along the floor, and the cracks the blow opens in it (they close as it fades)
	for i = 1, 2 do
		local spread = W * min(1, blow * 5)
		local p = out[20 + i]

		rgb_into(p.rgb, BRICK_FLASH)
		put(p, false, (W - spread) / 2, H - (i == 1 and 3 or 7) * s, spread, (i == 1 and 3 or 1.5) * s, 240 * max(0, 1 - blow * 3), W, H)
	end

	for i = 1, amount(lv, 1, 4) do
		local k = min(1, blow * 8)
		local length = H * (0.14 + 0.12 * hash(i, 1)) * k
		local p = out[22 + i]

		rgb_into(p.rgb, CRACK)
		put(p, false, W / 2 + (hash(i, 2) - 0.5) * 40 * s, H - length, 2 * s, length, 220 * max(0, 1 - blow * 1.6), W, H)
	end
end

-- WARP: motes of the warp rise through the card and flare when it crackles, streaks of light jump when it does
EFFECTS.warp = function (out, t, W, H, s, lv)
	local spark = crackle(t)

	for i = 1, amount(lv, 5, 16) do
		local u = life(t, i, 2 + 1.2 * hash(i, 1))
		local d = (2.5 + 2 * hash(i, 4)) * s * (1 + 0.5 * spark)
		local x = W * (0.08 + 0.84 * hash(i, 3)) + sin(t * 3 + i) * 4 * s * u
		local p = out[i]

		lerp_into(p.rgb, WARP, WARP_LIT, spark)
		put(p, true, x - d / 2, H * (1 - u) - d / 2, d, d, 205 * bell(u) * (0.7 + 0.3 * spark), W, H)
	end

	for i = 1, amount(lv, 1, 4) do
		local p = out[16 + i]
		local x, y = W * hash(floor(t * 14) + i * 31, 5), H * hash(floor(t * 14) + i * 17, 6)

		rgb_into(p.rgb, WARP_LIT)
		put(p, false, x, y, 2 * s, 7 * s, 240 * spark, W, H)
	end
end

-- HERESY, at threat 5 and 6 only: lightning strikes now and then (more often at 6, with a second flicker), lighting the whole card
EFFECTS.heresy = function (out, t, W, H, s, lv)
	local cycle = t / (lv >= 6 and 2.1 or 3.3)
	local u, n = cycle % 1, floor(cycle)
	local window = 0.07
	local on = u < window or lv >= 6 and u > 0.1 and u < 0.1 + window * 0.6
	local fade = on and (u < window and 1 - u / window or 0.8) or 0

	-- the flash over the whole card
	rgb_into(out[1].rgb, FLASH)
	put(out[1], false, 0, 0, W, H, 95 * fade, W, H)

	-- the bolt: six slivers from the top down to a point in the lower half, and a short branch from its middle
	local x, y = W * (0.25 + 0.5 * hash(n, 1)), 0
	local reach = H * (0.55 + 0.3 * hash(n, 2))
	local thick = 1.8 * s
	local bx, by = x, 0

	for j = 1, 7 do
		local q = out.tri[j]

		if on and j <= 6 then
			local nx, ny = x + (hash(n * 7 + j, 3) - 0.5) * W * 0.24, reach * j / 6

			rgb_into(q.rgb, BOLT)
			put_tri(q, x - thick, y, x + thick, y, nx, ny, 255 * fade, W, H)
			x, y = nx, ny

			if j == 3 then
				bx, by = nx, ny
			end
		elseif on then
			rgb_into(q.rgb, BOLT)
			put_tri(q, bx - thick * 0.6, by, bx + thick * 0.6, by, bx + (hash(n, 9) - 0.5) * W * 0.5, by + H * 0.15, 200 * fade, W, H)
		end
	end
end

-- PRAYER (2026-10-05, the user: "remove the candles and the circles, keep the beams"): soft beams of light fall from above and sway
-- slowly, more of them as the threat grows
EFFECTS.prayer = function (out, t, W, H, s, lv)
	for i = 1, amount(lv, 2, 6) do
		local p = out[i]
		local w = (3 + 5 * hash(i, 4)) * s

		rgb_into(p.rgb, RAY)
		put(p, false, W * (0.1 + 0.8 * hash(i, 3)) + sin(t * 0.2 + i) * W * 0.05, 0, w, H * (0.55 + 0.3 * hash(i, 5)), 40 + 26 * sin(t * 0.8 + i * 1.9), W, H)
	end
end

-- MIRACLE: golden stars flash open here and there, and motes of light float up
EFFECTS.miracle = function (out, t, W, H, s, lv)
	for i = 1, amount(lv, 2, 6) do
		local cycle = t / 1.3 + hash(i, 1)
		local u = cycle % 1
		local n = floor(cycle)
		local shine = bell(u)
		local cx, cy = W * (0.1 + 0.8 * hash(n * 13 + i, 3)), H * (0.1 + 0.8 * hash(n * 7 + i, 4))

		sparkle(out, i * 2 - 1, i * 2, cx, cy, (3 + (8 + lv) * shine) * s, 1.5 * s, 235 * shine, i % 2 == 0 and GOLD or GOLD_LIT, W, H)
	end

	for i = 1, amount(lv, 3, 10) do
		local u = life(t, 12 + i, 3 + hash(i, 1))
		local p = out[12 + i]

		rgb_into(p.rgb, GOLD)
		put(p, true, W * (0.1 + 0.8 * hash(i, 3)) + sin(t + i) * 4 * s, H * (1 - u), 2.6 * s, 2.6 * s, 180 * bell(u), W, H)
	end
end

-- GRACE: white feathers drift down, rocking from side to side (a feather seen edge on is narrower), with a few glints of light
EFFECTS.grace = function (out, t, W, H, s, lv)
	for i = 1, amount(lv, 4, 14) do
		local u = life(t, i, 5 + 2.5 * hash(i, 1))
		local rock = sin(t * 1.5 + i * 1.9)
		local w = (3 + 6 * abs(cos(t * 1.5 + i * 1.9))) * s
		local x = W * (0.1 + 0.8 * hash(i, 3)) + rock * W * 0.08
		local p = out[i]

		lerp_into(p.rgb, WHITE, SILVER, hash(i, 4) * 0.6)
		put(p, false, x - w / 2, u * H, w, 2.2 * s, 180 * bell(u), W, H)
	end

	for i = 1, amount(lv, 2, 6) do
		local twinkle = max(0, sin(t * 2.2 + i * 2.7))
		local p = out[14 + i]
		local d = (1.5 + 2 * twinkle) * s

		rgb_into(p.rgb, WHITE)
		put(p, true, W * hash(i, 5), H * hash(i, 6), d, d, 220 * twinkle * twinkle, W, H)
	end
end

-- FAITH: rose petals fall and tumble (a petal turning is seen narrower), three pinks
EFFECTS.faith = function (out, t, W, H, s, lv)
	for i = 1, amount(lv, 5, 18) do
		local u = life(t, i, 4 + 2 * hash(i, 1))
		local turn = abs(sin(t * 2.4 + i * 1.3))
		local w, h = (2.5 + 3 * turn) * s, (3.5 + 0.8 * hash(i, 5)) * s
		local x = W * (0.05 + 0.9 * hash(i, 3)) + sin(t * 1.1 + i * 2) * W * 0.1
		local p = out[i]

		rgb_into(p.rgb, i % 3 == 0 and ROSE_DEEP or i % 3 == 1 and ROSE or ROSE_PALE)
		put(p, true, x - w / 2, u * H, w, h, 195 * bell(u), W, H)
	end
end

-- DREAM: big soft clouds in every colour roll along the foot and the head of the card, a bright heart in each, motes of light rise
-- through the middle and rainbow stars flash open between them
EFFECTS.dream = function (out, t, W, H, s, lv)
	local puff = min(W, H) * 0.42
	local clouds = amount(lv, 4, 8)

	for i = 1, clouds do
		local top = i > clouds - floor(clouds * 0.4)
		local d = puff * (0.7 + 0.5 * hash(i, 1)) * (top and 0.75 or 1)
		local drift = (hash(i, 2) + t * 0.03 * (i % 2 == 0 and 1 or -1)) % 1
		local x = drift * (W - d)
		local y = (top and -d * 0.15 or H - d * 0.75) + sin(t * 0.6 + i) * 4 * s
		local p = out[i]

		hsv_into(p.rgb, t * 0.05 + i * 0.13, 0.3, 1)
		put(p, true, x, y, d, d, 120 + 30 * sin(t * 0.7 + i * 1.7), W, H)

		-- the bright heart of the first four clouds
		if i <= 4 then
			local heart = out[8 + i]
			local hd = d * 0.5

			rgb_into(heart.rgb, CLOUD_HEART)
			put(heart, true, x + d * 0.25, y + d * 0.2, hd, hd, 110 + 30 * sin(t * 0.9 + i), W, H)
		end
	end

	for i = 1, amount(lv, 2, 8) do
		local u = life(t, 12 + i, 2.6 + hash(i, 1))
		local d = (2.5 + 2 * hash(i, 4)) * s
		local p = out[12 + i]

		hsv_into(p.rgb, t * 0.1 + i * 0.21, 0.45, 1)
		put(p, true, W * (0.12 + 0.76 * hash(i, 3)) + sin(t * 1.4 + i) * 6 * s - d / 2, H * (0.85 - 0.7 * u), d, d, 230 * bell(u), W, H)
	end

	for i = 1, amount(lv, 1, 4) do
		local cycle = t / 1.6 + hash(i, 5)
		local n = floor(cycle)
		local shine = bell(cycle % 1)
		local cx, cy = W * (0.15 + 0.7 * hash(n * 11 + i, 6)), H * (0.25 + 0.5 * hash(n * 5 + i, 7))
		local rgb = out[19 + i * 2].rgb

		hsv_into(rgb, t * 0.15 + i * 0.5, 0.5, 1)
		sparkle(out, 19 + i * 2, 20 + i * 2, cx, cy, (3 + 12 * shine) * s, 1.8 * s, 250 * shine, rgb, W, H)
	end
end

-- True when a card of this suit and threat has an aura (Heresy only from threat 5, its lightning; Nightmare never)
Aura.has = function (suit, level)
	if suit == "heresy" then
		return (tonumber(level) or Aura.LEVEL) >= 5
	end

	return EFFECTS[suit] ~= nil
end

Aura.update = function (out, suit, t, W, H, s, level)
	local lv = clamp(floor(tonumber(level) or Aura.LEVEL), 1, 6)
	local effect = Aura.has(suit, lv) and EFFECTS[suit]

	-- (a suit leaves the shapes it does not use off)
	for i = 1, Aura.COUNT do
		out[i].on = false
	end

	for i = 1, Aura.TRIS do
		out.tri[i].on = false
	end

	if not effect or not W or not H or W <= 0 or H <= 0 then
		return false
	end

	effect(out, tonumber(t) or 0, W, H, (s or 1) * size_of(lv), lv)

	-- the threat's strength over every shape
	local k = Aura.strength(lv)

	for i = 1, Aura.COUNT do
		local p = out[i]

		if p.on then
			p.a = floor(p.a * k + 0.5)
			p.on = p.a >= 1
		end
	end

	for i = 1, Aura.TRIS do
		local q = out.tri[i]

		if q.on then
			q.a = floor(q.a * k + 0.5)
			q.on = q.a >= 1
		end
	end

	return true
end

-- Writes the aura `out` into a widget's style: the circle, rect and triangle passes named by C, R and T, placed at (ox, oy) (the
-- card's top left in the widget). `alive` false hides them all, `dim` scales every opacity (a resting card's aura is fainter) and
-- `paint(style, alpha, rgb)` colours a pass the renderer's way (the Deck and the Spread grey a resting or lost card).
Aura.draw = function (out, style, C, R, T, ox, oy, alive, dim, paint)
	dim = dim or 1

	for i = 1, Aura.COUNT do
		local p = out[i]
		local circle, rect = style[C[i]], style[R[i]]
		local on = alive and p.on

		circle.visible, rect.visible = on and p.round, on and not p.round

		if on then
			local s = p.round and circle or rect

			s.offset[1], s.offset[2], s.size[1], s.size[2] = ox + p.x, oy + p.y, p.w, p.h
			paint(s, floor(p.a * dim + 0.5), p.rgb)
		end
	end

	for i = 1, Aura.TRIS do
		local q = out.tri[i]
		local s = style[T[i]]
		local on = alive and q.on

		s.visible = on

		if on then
			local c = s.triangle_corners

			s.offset[1], s.offset[2] = ox, oy
			c[1][1], c[1][2], c[2][1], c[2][2], c[3][1], c[3][2] = q.x1, q.y1, q.x2, q.y2, q.x3, q.y3
			paint(s, floor(q.a * dim + 0.5), q.rgb)
		end
	end
end

-- The glow of a suit whose glow lives with its aura (nil for the others): Dream's slowly turns through the colours of a rainbow
-- (pastel), Brute's flares with every blow, Rage's throbs with its anger; all of them stronger as the threat grows. Returns the glow's
-- opacity 0..1 and writes its colour into `rgb`.
Aura.glow = function (suit, t, rgb, level)
	t = tonumber(t) or 0

	local lv = clamp(floor(tonumber(level) or Aura.LEVEL), 1, 6)
	local k = Aura.strength(lv)

	if suit == "dream" then
		hsv_into(rgb, t * 0.07, 0.35, 1)

		return (0.55 + 0.25 * sin(t * 1.3)) * k
	elseif suit == "brute" then
		local blow = (t % Aura.brute_period(lv)) / Aura.brute_period(lv)
		local flash = max(0, 1 - blow * 4)

		lerp_into(rgb, BRICK_DARK, BRICK_FLASH, flash)

		return (0.35 + 0.65 * flash) * k
	elseif suit == "rage" then
		-- the glow throbs with the card's anger, redder and stronger as the threat grows
		local heat, throb = Aura.anger(t, lv)

		lerp_into(rgb, ANGER_GLOW_LOW, ANGER_GLOW_HIGH, 0.4 * heat + 0.6 * throb)

		return (0.35 + 0.25 * heat + 0.4 * throb) * k
	end

	return nil
end

-- Dream's frame: the same rainbow as its glow, a little behind it (written into `rgb`)
Aura.rainbow = function (t, rgb, offset)
	hsv_into(rgb, (tonumber(t) or 0) * 0.07 + (offset or 0), 0.42, 1)

	return rgb
end

return Aura
