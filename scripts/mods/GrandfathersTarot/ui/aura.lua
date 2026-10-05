-- The aura of a card (2026-10-05, the user: "a fire like effect on Rage, a plague like effect on Plague, a thematic effect for every
-- suit, both in the Deck and in the HUD / last card; a new suit, Dream, cloudy and heavenly"): small shapes that live on the face of
-- a card, one animation per suit, drawn under its text. Pure arithmetic with no engine calls, so it is tested offline
-- (tools/hud_test.py); the Deck's tiles (ui/wave_editor_deck.lua), the Spread (ui/hud_element_waves.lua) and the last card
-- (ui/hud_element_last_card.lua) each have Aura.COUNT circle passes and Aura.COUNT rect passes for it.
--
-- Aura.update(out, suit, t, w, h, s) writes the particles of `suit` (an id of catalog/cards.lua) at time t on a card w x h into `out`
-- (Aura.new()): each one { on, round, x, y, w, h, a, rgb }, x and y from the card's top left, a the opacity 0..255. `s` is the size
-- of the shapes (1 on the Deck's tile; the HUD's smaller cards use less). Every particle stays inside the card (the UI cannot clip).
-- Nothing is allocated while it runs. Heresy and Nightmare have their own life (blood, fog) and no aura.
local Aura = {}

local floor, sin, cos, abs, max, min, pi = math.floor, math.sin, math.cos, math.abs, math.max, math.min, math.pi

Aura.COUNT = 12

Aura.new = function ()
	local out = {}

	for i = 1, Aura.COUNT do
		out[i] = { on = false, round = true, x = 0, y = 0, w = 0, h = 0, a = 0, rgb = { 0, 0, 0 } }
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

local function rgb_into(target, r, g, b)
	target[1], target[2], target[3] = r, g, b
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

-- one particle: kept inside the card (a shape larger than the card is shrunk to it)
local function put(p, round, x, y, w, h, a, W, H)
	w, h = min(w, W), min(h, H)
	p.on = a >= 1 and w > 0.2 and h > 0.2
	p.round, p.w, p.h = round, w, h
	p.x, p.y = clamp(x, 0, W - w), clamp(y, 0, H - h)
	p.a = floor(clamp(a, 0, 255) + 0.5)
end

-- the life of particle i: 0..1 through it at time t, with its own period
local function life(t, i, period, salt)
	return (t / period + hash(i, salt or 2)) % 1
end

-- ------------------------------------------------------------------------------------------------- colours
local FIRE_HOT, FIRE_MID, FIRE_LOW = { 255, 230, 130 }, { 255, 140, 40 }, { 175, 40, 20 }
local BILE, BILE_DARK, FLY = { 183, 194, 58 }, { 120, 140, 40 }, { 150, 160, 90 }
local MURMUR_A, MURMUR_B = { 207, 202, 176 }, { 157, 176, 127 }
local PUS, GAS = { 227, 207, 74 }, { 170, 160, 50 }
local SWARM_A, SWARM_B = { 175, 182, 140 }, { 110, 116, 88 }
local BONE, BRASS = { 239, 230, 201 }, { 205, 178, 100 }
local TRACER, TRACER_HOT = { 127, 178, 194 }, { 220, 244, 252 }
local LINK_A, LINK_B = { 95, 191, 165 }, { 60, 120, 105 }
local BRICK, BRICK_DARK, DUST, BRICK_FLASH = { 207, 92, 69 }, { 130, 60, 48 }, { 190, 160, 140 }, { 255, 170, 140 }
local WARP, WARP_LIT = { 177, 132, 224 }, { 234, 214, 255 }
local TEAL, TEAL_LIT = { 79, 156, 163 }, { 220, 241, 237 }
local GOLD, GOLD_LIT = { 216, 180, 90 }, { 255, 242, 207 }
local WHITE, SILVER = { 248, 250, 252 }, { 200, 214, 228 }
local ROSE, ROSE_DEEP, ROSE_PALE = { 240, 140, 184 }, { 194, 90, 140 }, { 255, 205, 226 }

-- the warp's crackle at time t (as Cards.warp_pulse: about one beat in eight at 14 a second)
local function crackle(t)
	local h = (sin(floor(t * 14) * 78.233) * 12543.873) % 1

	return h > 0.88 and 1 or 0
end

-- ------------------------------------------------------------------------------------------------- the suits
local EFFECTS = {}

-- RAGE: flames lick up from the bottom edge (yellow at their root, orange, then a deep red as they die) and embers rise above them
EFFECTS.rage = function (out, t, W, H, s)
	for i = 1, 9 do
		local u = life(t, i, 0.75 + 0.5 * hash(i, 1))
		local d = s * (13 * (1 - u) + 3)
		local x = W * (0.03 + 0.94 * (i - 0.5) / 9) - d / 2 + sin(t * 4 + i * 1.7) * 3 * s
		local y = H - d - H * 0.32 * u
		local p = out[i]

		if u < 0.35 then
			lerp_into(p.rgb, FIRE_HOT, FIRE_MID, u / 0.35)
		else
			lerp_into(p.rgb, FIRE_MID, FIRE_LOW, (u - 0.35) / 0.65)
		end

		put(p, true, x, y, d, d, 185 * min(1, u / 0.12) * (1 - u), W, H)
	end

	for i = 10, 12 do
		local u = life(t, i, 1.4 + 0.6 * hash(i, 1))
		local x = W * hash(i + floor(t / 2), 3) + sin(t * 2 + i) * 6 * s
		local p = out[i]

		rgb_into(p.rgb, 255, 196, 96)
		put(p, false, x, H * (1 - u) - 2 * s, 2.2 * s, 2.2 * s, 235 * (1 - u) * (0.6 + 0.4 * sin(t * 21 + i)), W, H)
	end
end

-- PLAGUE: bile bubbles rise and swell and pop near the top; flies buzz around them
EFFECTS.plague = function (out, t, W, H, s)
	for i = 1, 8 do
		local u = life(t, i, 2.6 + 1.4 * hash(i, 1))
		local pop = u > 0.88 and 1 + (u - 0.88) * 4 or 1
		local d = s * (4 + 6 * hash(i, 4)) * (0.55 + 0.45 * u) * pop
		local x = W * (0.06 + 0.88 * hash(i, 3)) + sin(t * 1.6 + i * 2) * 4 * s
		local y = H * (1 - u) - d / 2
		local fade = min(1, u / 0.1) * (u > 0.88 and (1 - u) / 0.12 or 1)
		local p = out[i]

		lerp_into(p.rgb, BILE, BILE_DARK, hash(i, 5))
		put(p, true, x, y, d, d, 140 * fade, W, H)
	end

	for i = 9, 12 do
		local cx = W * (0.3 + 0.4 * hash(i, 5)) + sin(t * 0.7 + i) * W * 0.18
		local cy = H * (0.3 + 0.3 * hash(i, 6)) + cos(t * 0.9 + i) * H * 0.12
		local x = cx + sin(t * 17 + i * 3) * 6 * s + cos(t * 7.3 + i) * 4 * s
		local y = cy + cos(t * 13 + i) * 5 * s
		local d = 2.6 * s
		local p = out[i]

		rgb_into(p.rgb, FLY[1], FLY[2], FLY[3])
		put(p, true, x - d / 2, y - d / 2, d, d, 210, W, H)
	end
end

-- MURMUR: pale lights drift slowly over the card and blink in and out, like whispers
EFFECTS.murmur = function (out, t, W, H, s)
	for i = 1, 10 do
		local x = W * (0.5 + 0.44 * sin(t * 0.31 * (1 + 0.3 * hash(i, 1)) + i * 2.1))
		local y = H * (0.5 + 0.44 * sin(t * 0.23 * (1 + 0.4 * hash(i, 2)) + i * 1.3))
		local blink = max(0, sin(t * (0.7 + 0.6 * hash(i, 3)) + i * 3))
		local d = s * (2.5 + 1.5 * blink)
		local p = out[i]

		lerp_into(p.rgb, MURMUR_A, MURMUR_B, hash(i, 4))
		put(p, true, x - d / 2, y - d / 2, d, d, 170 * blink * blink, W, H)
	end

	for i = 11, 12 do
		out[i].on = false
	end
end

-- BLIGHT: drops of pus fall from the top, each with a trail, and a yellow gas drifts at the bottom
EFFECTS.blight = function (out, t, W, H, s)
	for i = 1, 5 do
		local u = life(t, i, 1.7 + 1.1 * hash(i, 1))
		local d = s * (3.5 + 1.5 * hash(i, 4))
		local x = W * (0.08 + 0.84 * hash(i + floor(t / 1.7 + hash(i, 2)) * 7, 3))
		local y = u * u * (H - d)
		local fade = min(1, u / 0.08) * (1 - u * u * u)
		local drop, trail = out[i], out[i + 5]
		local length = s * 9 * u

		rgb_into(drop.rgb, PUS[1], PUS[2], PUS[3])
		put(drop, true, x, y, d, d, 205 * fade, W, H)
		rgb_into(trail.rgb, PUS[1], PUS[2], PUS[3])
		put(trail, false, x + d / 2 - 0.75 * s, y - length + d / 2, 1.5 * s, length, 110 * fade, W, H)
	end

	for i = 11, 12 do
		local d = min(W, H) * 0.42
		local drift = ((t * 0.035 * (i == 11 and 1 or -1) + hash(i, 1)) % 1)
		local x = drift * (W - d)
		local y = H - d * 0.75 + sin(t * 0.5 + i) * 3 * s
		local p = out[i]

		rgb_into(p.rgb, GAS[1], GAS[2], GAS[3])
		put(p, true, x, y, d, d, 34 + 14 * sin(t * 0.8 + i), W, H)
	end
end

-- SWARM: a cloud of tiny things whirls around a centre that wanders over the card
EFFECTS.swarm = function (out, t, W, H, s)
	local cx, cy = W * (0.5 + 0.22 * sin(t * 0.5)), H * (0.45 + 0.18 * sin(t * 0.37))
	local reach = min(W, H)

	for i = 1, 12 do
		local r = reach * (0.1 + 0.26 * hash(i, 1))
		local angle = t * (1.8 + 2.4 * hash(i, 2)) * (i % 2 == 0 and 1 or -1) + i
		local x = cx + cos(angle) * r * 1.4 + sin(t * 11 + i * 5) * 2 * s
		local y = cy + sin(angle) * r + cos(t * 9 + i) * 2 * s
		local d = s * (1.8 + 1.2 * hash(i, 3))
		local p = out[i]

		lerp_into(p.rgb, SWARM_A, SWARM_B, hash(i, 4))
		put(p, true, x - d / 2, y - d / 2, d, d, 185, W, H)
	end
end

-- a twinkling cross (two thin rects) in out[a] and out[b], centre (cx, cy), arm length `arm`
local function sparkle(out, a, b, cx, cy, arm, thick, alpha, rgb, W, H)
	local ha, hb = out[a], out[b]

	rgb_into(ha.rgb, rgb[1], rgb[2], rgb[3])
	rgb_into(hb.rgb, rgb[1], rgb[2], rgb[3])
	put(ha, false, cx - arm, cy - thick / 2, arm * 2, thick, alpha, W, H)
	put(hb, false, cx - thick / 2, cy - arm, thick, arm * 2, alpha, W, H)
end

-- FATEFUL: stars twinkle in the dark of the card and the dust of the last page sifts down through it
EFFECTS.fateful = function (out, t, W, H, s)
	for i = 1, 4 do
		local twinkle = max(0, sin(t * 1.1 + i * 2.3))
		local cx, cy = W * (0.12 + 0.76 * hash(i, 7)), H * (0.1 + 0.55 * hash(i, 8))

		sparkle(out, i * 2 - 1, i * 2, cx, cy, (2 + 7 * twinkle * twinkle) * s, 1.3 * s, 230 * twinkle, i % 2 == 0 and BRASS or BONE, W, H)
	end

	for i = 9, 12 do
		local u = life(t, i, 4 + 2 * hash(i, 1))
		local x = W * hash(i, 3) + sin(t * 0.9 + i) * 5 * s
		local p = out[i]

		rgb_into(p.rgb, BRASS[1], BRASS[2], BRASS[3])
		put(p, false, x, u * H, 2 * s, 2 * s, 150 * bell(u), W, H)
	end
end

-- VOLLEY: tracers streak across the card, a bright head on the first four
EFFECTS.volley = function (out, t, W, H, s)
	for i = 1, 8 do
		local period = 0.7 + 0.7 * hash(i, 1)
		local cycle = t / period + hash(i, 2)
		local u = cycle % 1
		local p = out[i]
		local length = (16 + 16 * hash(i, 4)) * s
		local y = H * (0.08 + 0.84 * hash(i * 7 + floor(cycle), 3))

		if u < 0.4 then
			local x = (W - length) * (u / 0.4)

			rgb_into(p.rgb, TRACER[1], TRACER[2], TRACER[3])
			put(p, false, x, y, length, 1.4 * s, 175 * (1 - u / 0.4 * 0.5), W, H)

			if i <= 4 then
				local head = out[8 + i]

				rgb_into(head.rgb, TRACER_HOT[1], TRACER_HOT[2], TRACER_HOT[3])
				put(head, false, x + length - 2.6 * s, y - 0.6 * s, 2.6 * s, 2.6 * s, 235, W, H)
			end
		else
			p.on = false

			if i <= 4 then
				out[8 + i].on = false
			end
		end
	end
end

-- SNARE: a chain of links creeps round the card's edge, the loop tightening and loosening
EFFECTS.snare = function (out, t, W, H, s)
	local inset = (6 + 2 * sin(t * 1.4)) * s
	local w, h = W - 2 * inset, H - 2 * inset
	local around = 2 * (w + h)

	for i = 1, 12 do
		local d = (t * 22 * s + (i - 1) * around / 12) % around
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
		local p = out[i]
		local link = i % 2 == 0 and LINK_A or LINK_B

		rgb_into(p.rgb, link[1], link[2], link[3])
		put(p, true, x - size / 2, y - size / 2, size, size, 150, W, H)
	end
end

-- BRUTE: every 2.2 s a blow lands at the bottom of the card: a shock runs along the floor and chunks of brick fly up and fall back
Aura.BRUTE_PERIOD = 2.2

EFFECTS.brute = function (out, t, W, H, s)
	local tau = t % Aura.BRUTE_PERIOD
	local blow = tau / Aura.BRUTE_PERIOD

	for i = 1, 10 do
		local p = out[i]
		local side = i % 2 == 0 and 1 or -1
		local vx = side * (18 + 40 * hash(i, 1)) * s
		local vy = (55 + 50 * hash(i, 2)) * s
		local g = 120 * s
		local x = W / 2 + vx * tau
		local y = H - 4 * s - (vy * tau - g * tau * tau)
		local size = (2.5 + 2.5 * hash(i, 3)) * s
		local alpha = blow < 0.55 and 220 * (1 - blow / 0.55) or 0
		local rock = i % 3 == 0 and DUST or i % 3 == 1 and BRICK or BRICK_DARK

		rgb_into(p.rgb, rock[1], rock[2], rock[3])
		put(p, false, x - size / 2, y - size, size, size, y > H and 0 or alpha, W, H)
	end

	for i = 11, 12 do
		local spread = W * min(1, blow * 4)
		local p = out[i]

		rgb_into(p.rgb, DUST[1], DUST[2], DUST[3])
		put(p, false, (W - spread) / 2, H - (i == 11 and 3 or 6) * s, spread, (i == 11 and 2 or 1) * s, 210 * max(0, 1 - blow * 4), W, H)
	end
end

-- WARP: motes of the warp rise through the card and flare when it crackles
EFFECTS.warp = function (out, t, W, H, s)
	local spark = crackle(t)

	for i = 1, 10 do
		local u = life(t, i, 2 + 1.2 * hash(i, 1))
		local d = (2.5 + 2 * hash(i, 4)) * s * (1 + 0.5 * spark)
		local x = W * (0.08 + 0.84 * hash(i, 3)) + sin(t * 3 + i) * 4 * s * u
		local p = out[i]

		lerp_into(p.rgb, WARP, WARP_LIT, spark)
		put(p, true, x - d / 2, H * (1 - u) - d / 2, d, d, 205 * bell(u) * (0.7 + 0.3 * spark), W, H)
	end

	for i = 11, 12 do
		local p = out[i]
		local x, y = W * hash(floor(t * 14) + i * 31, 5), H * hash(floor(t * 14) + i * 17, 6)

		rgb_into(p.rgb, WARP_LIT[1], WARP_LIT[2], WARP_LIT[3])
		put(p, false, x, y, 2 * s, 7 * s, 240 * spark, W, H)
	end
end

-- PRAYER: incense rises from the foot of the card, swaying and spreading as it fades, with sparks of light in it
EFFECTS.prayer = function (out, t, W, H, s)
	for i = 1, 8 do
		local u = life(t, i, 4 + 2 * hash(i, 1))
		local d = (4 + 15 * u) * s
		local x = W * (0.3 + 0.4 * hash(i, 3)) + sin(t * 0.8 + u * 4 + i) * W * 0.12
		local p = out[i]

		lerp_into(p.rgb, TEAL, TEAL_LIT, u * 0.5)
		put(p, true, x - d / 2, H * (1 - u) - d / 2, d, d, 62 * bell(u), W, H)
	end

	for i = 9, 12 do
		local u = life(t, i, 2.4 + hash(i, 1))
		local x = W * (0.2 + 0.6 * hash(i, 3)) + sin(t * 1.3 + i) * 6 * s
		local p = out[i]

		rgb_into(p.rgb, TEAL_LIT[1], TEAL_LIT[2], TEAL_LIT[3])
		put(p, true, x, H * (1 - u), 2.2 * s, 2.2 * s, 190 * bell(u), W, H)
	end
end

-- MIRACLE: golden stars flash open here and there, and motes of light float up
EFFECTS.miracle = function (out, t, W, H, s)
	for i = 1, 4 do
		local cycle = t / 1.3 + hash(i, 1)
		local u = cycle % 1
		local n = floor(cycle)
		local shine = bell(u)
		local cx, cy = W * (0.1 + 0.8 * hash(n * 13 + i, 3)), H * (0.1 + 0.8 * hash(n * 7 + i, 4))

		sparkle(out, i * 2 - 1, i * 2, cx, cy, (3 + 10 * shine) * s, 1.5 * s, 235 * shine, i % 2 == 0 and GOLD or GOLD_LIT, W, H)
	end

	for i = 9, 12 do
		local u = life(t, i, 3 + hash(i, 1))
		local p = out[i]

		rgb_into(p.rgb, GOLD[1], GOLD[2], GOLD[3])
		put(p, true, W * (0.1 + 0.8 * hash(i, 3)) + sin(t + i) * 4 * s, H * (1 - u), 2.6 * s, 2.6 * s, 180 * bell(u), W, H)
	end
end

-- GRACE: white feathers drift down, rocking from side to side (a feather seen edge on is narrower), with a few glints of light
EFFECTS.grace = function (out, t, W, H, s)
	for i = 1, 8 do
		local u = life(t, i, 5 + 2.5 * hash(i, 1))
		local rock = sin(t * 1.5 + i * 1.9)
		local w = (3 + 6 * abs(cos(t * 1.5 + i * 1.9))) * s
		local x = W * (0.1 + 0.8 * hash(i, 3)) + rock * W * 0.08
		local p = out[i]

		lerp_into(p.rgb, WHITE, SILVER, hash(i, 4) * 0.6)
		put(p, false, x - w / 2, u * H, w, 2.2 * s, 175 * bell(u), W, H)
	end

	for i = 9, 12 do
		local twinkle = max(0, sin(t * 2.2 + i * 2.7))
		local p = out[i]
		local d = (1.5 + 2 * twinkle) * s

		rgb_into(p.rgb, WHITE[1], WHITE[2], WHITE[3])
		put(p, true, W * hash(i, 5), H * hash(i, 6), d, d, 220 * twinkle * twinkle, W, H)
	end
end

-- FAITH: rose petals fall and tumble (a petal turning is seen narrower), three pinks
EFFECTS.faith = function (out, t, W, H, s)
	for i = 1, 11 do
		local u = life(t, i, 4 + 2 * hash(i, 1))
		local turn = abs(sin(t * 2.4 + i * 1.3))
		local w, h = (2.5 + 3 * turn) * s, (3.5 + 0.8 * hash(i, 5)) * s
		local x = W * (0.05 + 0.9 * hash(i, 3)) + sin(t * 1.1 + i * 2) * W * 0.1
		local p = out[i]
		local pink = i % 3 == 0 and ROSE_DEEP or i % 3 == 1 and ROSE or ROSE_PALE

		rgb_into(p.rgb, pink[1], pink[2], pink[3])
		put(p, true, x - w / 2, u * H, w, h, 190 * bell(u), W, H)
	end

	out[12].on = false
end

-- DREAM: soft clouds in every colour drift along the foot and the head of the card, rainbow stars twinkle between them
EFFECTS.dream = function (out, t, W, H, s)
	local puff = min(W, H) * 0.3

	for i = 1, 6 do
		local top = i > 4
		local d = puff * (0.75 + 0.5 * hash(i, 1)) * (top and 0.7 or 1)
		local drift = (hash(i, 2) + t * 0.025 * (i % 2 == 0 and 1 or -1)) % 1
		local x = drift * (W - d)
		local y = (top and 0 or H - d * 0.8) + sin(t * 0.6 + i) * 3 * s
		local p = out[i]

		hsv_into(p.rgb, t * 0.05 + i * 0.16, 0.28, 1)
		put(p, true, x, y, d, d, 60 + 16 * sin(t * 0.7 + i * 1.7), W, H)
	end

	for i = 7, 12 do
		local twinkle = max(0, sin(t * 1.7 + i * 2.2))
		local cx, cy = W * (0.1 + 0.8 * hash(i, 3)), H * (0.2 + 0.6 * hash(i, 4))
		local p = out[i]
		local d = (1.8 + 3.2 * twinkle) * s

		hsv_into(p.rgb, t * 0.12 + i * 0.13, 0.55, 1)
		put(p, i % 2 == 0, cx - d / 2, cy - d / 2, d, d, 235 * twinkle, W, H)
	end
end

-- True when the suit has an aura
Aura.has = function (suit)
	return EFFECTS[suit] ~= nil
end

Aura.update = function (out, suit, t, W, H, s)
	local effect = EFFECTS[suit]

	if not effect or not W or not H or W <= 0 or H <= 0 then
		for i = 1, Aura.COUNT do
			out[i].on = false
		end

		return false
	end

	effect(out, tonumber(t) or 0, W, H, s or 1)

	return true
end

-- The glow of a suit whose glow lives with its aura (nil for the others): Dream's slowly turns through the colours of a rainbow
-- (pastel), Brute's flares with every blow. Returns the glow's opacity 0..1 and writes its colour into `rgb`.
Aura.glow = function (suit, t, rgb)
	t = tonumber(t) or 0

	if suit == "dream" then
		hsv_into(rgb, t * 0.07, 0.35, 1)

		return 0.55 + 0.25 * sin(t * 1.3)
	elseif suit == "brute" then
		local blow = (t % Aura.BRUTE_PERIOD) / Aura.BRUTE_PERIOD
		local flash = max(0, 1 - blow * 5)

		lerp_into(rgb, BRICK_DARK, BRICK_FLASH, flash)

		return 0.3 + 0.7 * flash
	end

	return nil
end

-- Dream's frame: the same rainbow as its glow, a little behind it (written into `rgb`)
Aura.rainbow = function (t, rgb, offset)
	hsv_into(rgb, (tonumber(t) or 0) * 0.07 + (offset or 0), 0.42, 1)

	return rgb
end

return Aura
