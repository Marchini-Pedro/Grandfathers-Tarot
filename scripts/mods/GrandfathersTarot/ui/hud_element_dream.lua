-- Dream's sky (2026-10-05, the user: "a new suit, Dream, the opposite of Nightmare, full of colours, something positive; create an
-- impactful effect for it, cloudy, heaven, dreamy like, go hard!"). The Nightmare's dread darkens the screen; this lights it: when a
-- Dream card is drawn a bloom of light opens from the middle of the screen, rays fall from above, clouds in every pastel colour roll in
-- along the foot and the head of the screen, its edges glow in a rainbow that turns, and stars twinkle and drift up. It rises when the
-- card is drawn (every player sees it: the draw is synced), holds, and fades out after DURATION seconds. Everything is see-through.
--
-- The option "Dream's sky strength" (dream_sky_strength, percent: 0 turns it off, 150 is half again as bright) scales it. No allocation per frame: the passes are written in place.
local mod = get_mod("GrandfathersTarot")

local Definitions = mod:io_dofile("GrandfathersTarot/scripts/mods/GrandfathersTarot/ui/hud_element_dream_definitions")
local Aura = mod:io_dofile("GrandfathersTarot/scripts/mods/GrandfathersTarot/ui/aura")

local HudElementGrandfathersTarotDream = class("HudElementGrandfathersTarotDream", "HudElementBase")

local W, H = Definitions.W, Definitions.H
local RISE, HOLD, DURATION, BLOOM = 0.5, 5, 7.5, 1.8 -- seconds: up to full strength, held until, gone at; the bloom's time
local VEIL_ALPHA, RAY_ALPHA, CLOUD_ALPHA, HEART_ALPHA, EDGE_ALPHA, STAR_ALPHA, BLOOM_ALPHA = 30, 34, 78, 62, 130, 235, 150
local sin, floor, max, min, pi = math.sin, math.floor, math.max, math.min, math.pi
local hash, hsv_into = Aura.hash, Aura.hsv_into

-- style ids, built once
local RAY, CLOUD, HEART, STAR_H, STAR_V, BLOOM_ID, VIG = {}, {}, {}, {}, {}, {}, {}
local CLOUDS = Definitions.CLOUDS_FOOT + Definitions.CLOUDS_HEAD

for i = 1, Definitions.RAYS do
	RAY[i] = "ray_" .. i
end

for i = 1, CLOUDS do
	CLOUD[i], HEART[i] = "cloud_" .. i, "cloud_heart_" .. i
end

for i = 1, Definitions.STARS do
	STAR_H[i], STAR_V[i] = "star_h_" .. i, "star_v_" .. i
end

for i = 1, Definitions.BLOOM_RINGS do
	BLOOM_ID[i] = "bloom_" .. i
end

for j = 1, Definitions.VIGNETTE_STEPS do
	VIG[j] = { "vig_" .. j .. "_t", "vig_" .. j .. "_b", "vig_" .. j .. "_l", "vig_" .. j .. "_r" }
end

-- How strong the sky is `age` seconds after the draw: rises, holds, fades (0..1)
-- the option "Dream's sky strength" as a factor (1 = 100 percent; 0 to 1.5)
HudElementGrandfathersTarotDream.option = function ()
	local value = tonumber(mod:get("dream_sky_strength"))

	return value and math.max(0, math.min(150, value)) / 100 or 1
end

HudElementGrandfathersTarotDream.envelope = function (age)
	if age < 0 or age >= DURATION then
		return 0
	elseif age < RISE then
		return age / RISE
	elseif age <= HOLD then
		return 1
	end

	return 1 - (age - HOLD) / (DURATION - HOLD)
end

HudElementGrandfathersTarotDream.DURATION = DURATION

local function box(style, x, y, w, h)
	style.offset[1], style.offset[2], style.size[1], style.size[2] = x, y, w, h
end

local function paint(style, alpha, rgb)
	local c = style.color

	c[1], c[2], c[3], c[4] = max(0, min(255, floor(alpha + 0.5))), rgb[1], rgb[2], rgb[3]
	style.visible = c[1] > 0
end

local RGB = { 0, 0, 0 }
local GOLD_WHITE = { 255, 248, 222 }

HudElementGrandfathersTarotDream.init = function (self, parent, draw_layer, start_scale)
	HudElementGrandfathersTarotDream.super.init(self, parent, draw_layer, start_scale, Definitions)

	self._widget = self._widgets_by_name.dream
	self._widget.visible = false
	self._age, self._seen, self._clock = nil, nil, 0

	-- the frames of the vignette do not move: placed once
	local style, step = self._widget.style, Definitions.VIGNETTE_STEP

	for j = 1, Definitions.VIGNETTE_STEPS do
		local inset = (j - 1) * step
		local ids = VIG[j]

		box(style[ids[1]], inset, inset, W - 2 * inset, step)
		box(style[ids[2]], inset, H - inset - step, W - 2 * inset, step)
		box(style[ids[3]], inset, inset + step, step, H - 2 * inset - 2 * step)
		box(style[ids[4]], W - inset - step, inset + step, step, H - 2 * inset - 2 * step)
	end
end

HudElementGrandfathersTarotDream._hide = function (self)
	self._age = nil
	self._widget.visible = false
end

-- A Dream card that was just drawn (a hand this element has not answered yet) opens the sky
HudElementGrandfathersTarotDream._watch = function (self, view, Cards)
	if not (view.drawn and view.hand and view.hand_seq) or view.hand_seq == self._seen then
		return
	end

	self._seen = view.hand_seq

	local card = view.hand[view.win]

	-- (a late joiner does not get the sky of a card drawn long before)
	if card and Cards.normalize_suit(card.suit) == "dream" and (tonumber(view.drawn_age) or 0) < 2 then
		self._age = 0
	end
end

-- the sky at `age` seconds after the draw with strength 0..1, at the clock t: every pass written in place
HudElementGrandfathersTarotDream._paint = function (self, age, strength, t)
	local style = self._widget.style

	self._widget.visible = true

	-- a pastel light over the whole screen
	hsv_into(RGB, t * 0.05, 0.25, 1)
	box(style.veil, 0, 0, W, H)
	paint(style.veil, strength * VEIL_ALPHA, RGB)

	-- rays fall from a point above the top of the screen, fanning out and swaying, each in its own colour
	for i = 1, Definitions.RAYS do
		local s = style[RAY[i]]
		local width = 70 + 70 * hash(i, 1)
		local angle = (i - (Definitions.RAYS + 1) / 2) * 0.17 + sin(t * 0.35 + i * 1.7) * 0.05

		box(s, W / 2 + (i - 4) * 90 - width / 2, -120, width, 1500)
		s.pivot[1], s.pivot[2], s.angle = width / 2, 0, angle
		hsv_into(RGB, t * 0.04 + i * 0.13, 0.22, 1)
		paint(s, strength * RAY_ALPHA * (0.55 + 0.45 * sin(t * 0.9 + i * 2.3)), RGB)
	end

	-- the clouds: puffs that roll along the foot and the head of the screen, bobbing, each with a brighter heart
	for i = 1, CLOUDS do
		local head = i > Definitions.CLOUDS_FOOT
		local n = head and Definitions.CLOUDS_HEAD or Definitions.CLOUDS_FOOT
		local k = head and i - Definitions.CLOUDS_FOOT or i
		local r = (head and 95 or 130) + 70 * hash(i, 2)
		local span = W + 2 * r
		local drift = t * (10 + 8 * hash(i, 3)) * (head and -1 or 1)
		local x = ((k - 1) / n * span + drift) % span - r
		-- they roll in with the sky: from below (and above) the screen to their places
		local arrive = 1 - (1 - min(1, age / 1.2)) ^ 2
		local y = head and (-r * 0.5 - r * (1 - arrive)) or (H - r * 0.55 + r * (1 - arrive))

		y = y + sin(t * 0.6 + i * 1.3) * 10

		hsv_into(RGB, t * 0.03 + i * 0.071, 0.2, 1)
		box(style[CLOUD[i]], x - r, y - r, 2 * r, 2 * r)
		paint(style[CLOUD[i]], strength * CLOUD_ALPHA, RGB)

		local heart = r * 0.62

		hsv_into(RGB, t * 0.03 + i * 0.071 + 0.05, 0.1, 1)
		box(style[HEART[i]], x - heart, y - heart - r * 0.1, 2 * heart, 2 * heart)
		paint(style[HEART[i]], strength * HEART_ALPHA, RGB)
	end

	-- the edges glow in a rainbow that turns
	for j = 1, #VIG do
		local alpha = strength * EDGE_ALPHA * (1 - (j - 1) / #VIG) ^ 1.8

		hsv_into(RGB, t * 0.08 + j * 0.035, 0.4, 1)

		for side = 1, 4 do
			paint(style[VIG[j][side]], alpha, RGB)
		end
	end

	-- stars that twinkle and drift up, a cross of light each
	for i = 1, Definitions.STARS do
		local u = (t / (6 + 4 * hash(i, 4)) + hash(i, 5)) % 1
		local twinkle = max(0, sin(t * (1.6 + hash(i, 6)) + i * 2.1))
		local x = W * hash(i, 7) + sin(t * 0.5 + i) * 20
		local y = H * (1 - u)
		local arm = (3 + 11 * twinkle * twinkle)
		local fade = sin(pi * u)

		hsv_into(RGB, t * 0.1 + i * 0.09, 0.45, 1)
		box(style[STAR_H[i]], x - arm, y - 1, arm * 2, 2)
		box(style[STAR_V[i]], x - 1, y - arm, 2, arm * 2)
		paint(style[STAR_H[i]], strength * STAR_ALPHA * twinkle * fade, RGB)
		paint(style[STAR_V[i]], strength * STAR_ALPHA * twinkle * fade, RGB)
	end

	-- the bloom: rings of light that open from the middle of the screen when the card is drawn
	for i = 1, Definitions.BLOOM_RINGS do
		local u = (age - (i - 1) * 0.15) / BLOOM

		if u > 0 and u < 1 then
			local r = 60 + (1100 + 180 * i) * (1 - (1 - u) ^ 2)

			box(style[BLOOM_ID[i]], W / 2 - r, H / 2 - r, 2 * r, 2 * r)
			paint(style[BLOOM_ID[i]], BLOOM_ALPHA * (1 - u) ^ 2 / i, GOLD_WHITE)
		else
			style[BLOOM_ID[i]].visible = false
		end
	end
end

HudElementGrandfathersTarotDream._refresh = function (self, dt)
	local rw = mod.rw
	local director, Cards = rw and rw.director, rw and rw.cards

	if not director or not Cards or not mod:is_enabled() or HudElementGrandfathersTarotDream.option() <= 0 then
		return self:_hide()
	end

	self._clock = self._clock + dt
	self:_watch(director.view(), Cards)

	if not self._age then
		return self:_hide()
	end

	self._age = self._age + dt

	local strength = HudElementGrandfathersTarotDream.envelope(self._age)

	if strength <= 0 then
		return self:_hide()
	end

	self:_paint(self._age, strength * HudElementGrandfathersTarotDream.option(), self._clock)
end

HudElementGrandfathersTarotDream.update = function (self, dt, t, ui_renderer, render_settings, input_service)
	HudElementGrandfathersTarotDream.super.update(self, dt, t, ui_renderer, render_settings, input_service)

	local ok, err = pcall(self._refresh, self, tonumber(dt) or 0)

	if not ok then
		self:_hide()

		if not self._reported then
			self._reported = true
			mod:error("[hud] Dream's sky failed: %s", tostring(err))
		end
	end
end

-- (2026-10-06, a performance pass) nothing to draw while hidden: no render pass at all
HudElementGrandfathersTarotDream.draw = function (self, ...)
	if not (self._widget and self._widget.visible) then return end

	return HudElementGrandfathersTarotDream.super.draw(self, ...)
end

return HudElementGrandfathersTarotDream
