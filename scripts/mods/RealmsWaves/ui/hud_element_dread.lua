-- The Nightmare's dread (2026-10-04, the user: "like the Spillway's whole-screen effect before its boss, but black and grey and a bit
-- transparent so players can still see, when a Nightmare card is chosen, together with its sound; a toggle"). The Spillway's effect is
-- a mood (scripts/settings/camera/mood/mood_settings.lua spillway_nurgle_transition: a shading environment and a screen particle in
-- Nurgle green, which cannot be recoloured), so this is the mod's own overlay: a black veil that breathes, darker edges, ash-grey fog
-- drifting across, and the Nightmare's dying light flickering in it (Cards.dread). It rises when a Nightmare card is drawn (every
-- player sees it: the draw is synced), holds while its sound plays and fades out after DURATION seconds.
--
-- The option "Nightmare's dread on screen" (nightmare_dread) turns it off. No allocation per frame: the passes are written in place.
local mod = get_mod("RealmsWaves")

local Definitions = mod:io_dofile("RealmsWaves/scripts/mods/RealmsWaves/ui/hud_element_dread_definitions")

local HudElementRealmsWavesDread = class("HudElementRealmsWavesDread", "HudElementBase")

local W, H = Definitions.W, Definitions.H
local RISE, HOLD, DURATION = 0.8, 5.5, 8 -- seconds: up to full strength, held until, gone at
local VEIL_ALPHA, EDGE_ALPHA, FOG_ALPHA, FLASH_ALPHA = 85, 210, 95, 60
local ASH = { 26, 25, 32 }

-- style ids, built once
local FOG, VIG = {}, {}

for i = 1, Definitions.FOG_BANKS do
	FOG[i] = {}

	for l = 1, #Definitions.FOG_LAYERS do
		FOG[i][l] = "fog_" .. i .. "_" .. l
	end
end

for j = 1, Definitions.VIGNETTE_STEPS do
	VIG[j] = { "vig_" .. j .. "_t", "vig_" .. j .. "_b", "vig_" .. j .. "_l", "vig_" .. j .. "_r" }
end

-- How strong the dread is `age` seconds after the draw: rises, holds, fades (0..1)
HudElementRealmsWavesDread.envelope = function (age)
	if age < 0 or age >= DURATION then
		return 0
	elseif age < RISE then
		return age / RISE
	elseif age <= HOLD then
		return 1
	end

	return 1 - (age - HOLD) / (DURATION - HOLD)
end

HudElementRealmsWavesDread.DURATION = DURATION

local function box(style, x, y, w, h)
	style.offset[1], style.offset[2], style.size[1], style.size[2] = x, y, w, h
end

local function paint(style, alpha, rgb)
	local c = style.color

	c[1], c[2], c[3], c[4] = math.max(0, math.min(255, math.floor(alpha + 0.5))), rgb[1], rgb[2], rgb[3]
	style.visible = c[1] > 0
end

local BLACK = { 0, 0, 0 }

HudElementRealmsWavesDread.init = function (self, parent, draw_layer, start_scale)
	HudElementRealmsWavesDread.super.init(self, parent, draw_layer, start_scale, Definitions)

	self._widget = self._widgets_by_name.dread
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

HudElementRealmsWavesDread._hide = function (self)
	self._age = nil
	self._widget.visible = false
end

-- A Nightmare card that was just drawn (a hand this element has not answered yet) starts the dread
HudElementRealmsWavesDread._watch = function (self, view, Cards)
	if not (view.drawn and view.hand and view.hand_seq) or view.hand_seq == self._seen then
		return
	end

	self._seen = view.hand_seq

	local card = view.hand[view.win]

	-- (a late joiner does not get the dread of a card drawn long before)
	if card and Cards.normalize_suit(card.suit) == "nightmare" and (tonumber(view.drawn_age) or 0) < 2 then
		self._age = 0
	end
end

HudElementRealmsWavesDread._refresh = function (self, dt)
	local rw = mod.rw
	local director, Cards = rw and rw.director, rw and rw.cards

	if not director or not Cards or not mod:is_enabled() or mod:get("nightmare_dread") == false then
		return self:_hide()
	end

	self._clock = self._clock + dt
	self:_watch(director.view(), Cards)

	if not self._age then
		return self:_hide()
	end

	self._age = self._age + dt

	local strength = HudElementRealmsWavesDread.envelope(self._age)

	if strength <= 0 then
		return self:_hide()
	end

	local style, t = self._widget.style, self._clock
	local breath, flash = Cards.dread(t)

	self._widget.visible = true
	box(style.veil, 0, 0, W, H)
	paint(style.veil, strength * (VEIL_ALPHA * (0.7 + 0.3 * breath) + FLASH_ALPHA * flash), BLACK)

	for i = 1, #FOG do
		local middle = ((t * (0.035 + 0.012 * i) + i * 0.29) % 1.4 - 0.2) * H
		local alpha = strength * FOG_ALPHA * (0.6 + 0.4 * math.sin(t * 0.7 + i * 1.9)) / #Definitions.FOG_LAYERS

		for l = 1, #Definitions.FOG_LAYERS do
			local h = Definitions.FOG_HEIGHT * Definitions.FOG_LAYERS[l]

			box(style[FOG[i][l]], 0, middle - h / 2, W, h)
			paint(style[FOG[i][l]], alpha, ASH)
		end
	end

	for j = 1, #VIG do
		local alpha = strength * EDGE_ALPHA * (1 - (j - 1) / #VIG) ^ 1.6

		for k = 1, 4 do
			paint(style[VIG[j][k]], alpha, BLACK)
		end
	end
end

HudElementRealmsWavesDread.update = function (self, dt, t, ui_renderer, render_settings, input_service)
	HudElementRealmsWavesDread.super.update(self, dt, t, ui_renderer, render_settings, input_service)

	local ok, err = pcall(self._refresh, self, tonumber(dt) or 0)

	if not ok then
		self:_hide()

		if not self._reported then
			self._reported = true
			mod:error("[hud] Nightmare dread failed: %s", tostring(err))
		end
	end
end

return HudElementRealmsWavesDread
