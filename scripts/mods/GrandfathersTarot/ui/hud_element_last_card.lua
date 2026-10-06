-- The "last card" HUD window: the card whose wave went out last, as the Spread draws it, with how long ago it was and its whisper. It renders what core/director.lua's view() returns (view.last, view.last_seq, view.last_age): on the host the
-- authoritative card, on clients the last one the host synced, so every player sees the same card. It stays on the screen until the
-- next card goes out (the Spread itself is gone a few seconds after the pick); before the first card of a mission there is no window.
--
-- No allocation per frame: the geometry and the colours are written into the widget style when the card changes (the table
-- view.last stays the same until another card goes out), and only the age text changes, once a second.
--
-- Position: the "panel" scenegraph node is the ONE movable node of the custom_hud mod (its edit mode lists this element as
-- "HudElementGrandfathersTarotLast|panel"); a sample card is shown while that edit mode is open. The option "Show the last card window" turns
-- it off.
local mod = get_mod("GrandfathersTarot")

local Definitions = mod:io_dofile("GrandfathersTarot/scripts/mods/GrandfathersTarot/ui/hud_element_last_card_definitions")
local Paint = mod:io_dofile("GrandfathersTarot/scripts/mods/GrandfathersTarot/ui/last_card_paint")

local Spread = Definitions.Spread

local HudElementGrandfathersTarotLast = class("HudElementGrandfathersTarotLast", "HudElementBase")

-- what the custom_hud edit mode shows when no card has gone out yet
local SAMPLE = { key = "sample", name = "The Chariot", suit = "rage", threat = 3, breeds = { "renegade_executor", "renegade_gunner", "cultist_shocktrooper" }, whisper = "Faster. Faster.", modifiers = "Enraged", rare = false, cooldown = 180 }
local SAMPLE_AGE = 154

local function customizing()
	local custom_hud = get_mod("custom_hud")

	return custom_hud ~= nil and custom_hud.is_customizing == true
end

-- ------------------------------------------------------------------------------------------------- init
HudElementGrandfathersTarotLast.init = function (self, parent, draw_layer, start_scale)
	HudElementGrandfathersTarotLast.super.init(self, parent, draw_layer, start_scale, Definitions)

	self._widget = self._widgets_by_name.last
	self._shape_icon = Spread.new_shape(Spread.ICON_TRIS, Spread.ICON_CIRCS)
	self._card, self._seq, self._seconds, self._font = nil, nil, nil, nil
	self._visible = false
	self._widget.visible = false
end

-- ----------------------------------------------------------------------------------------- visibility
HudElementGrandfathersTarotLast._hide = function (self)
	self._widget.visible = false
	self._visible = false
	self._card, self._seq, self._seconds = nil, nil, nil
end

-- the painting is ui/last_card_paint.lua's (the Mirror of the editor paints its preview with it too)
local chosen_font = Paint.chosen_font

HudElementGrandfathersTarotLast._setup = Paint.setup
HudElementGrandfathersTarotLast._tick_fog = Paint.tick_fog
HudElementGrandfathersTarotLast._tick_aura = Paint.tick_aura

-- "m:ss ago" in played seconds (rounded down: the card is exactly as old as the seconds that have passed)
HudElementGrandfathersTarotLast._tick_age = function (self, age)
	local seconds = math.floor(math.max(0, age))

	if seconds ~= self._seconds then self._seconds, self._widget.content.age = seconds, mod:localize("hud_last_ago", Spread.time_text(seconds)) end
end

-- ------------------------------------------------------------------------------------------------ refresh
HudElementGrandfathersTarotLast._refresh = function (self)
	local rw = mod.rw
	local director = rw and rw.director
	local sample = customizing()

	if not director or not mod:is_enabled() or ((mod:get("hud_enabled") == false or mod:get("hud_last_card") == false) and not sample) then return self:_hide() end

	local view = director.view()
	local card, seq, age = view.last, view.last_seq or 0, view.last_age or 0

	if not card and sample then card, seq, age = SAMPLE, -1, SAMPLE_AGE end

	if not card then return self:_hide() end

	local font = chosen_font()

	if card ~= self._card or seq ~= self._seq or font ~= self._font then
		self._card, self._seq = card, seq
		self:_setup(card, font)
	end

	self._widget.alpha_multiplier = 1 - math.max(0, math.min(100, tonumber(mod:get("hud_last_transparency")) or 0)) / 100
	self._visible = true
	self._widget.visible = true
	self:_tick_age(age)
	self:_tick_fog(self._clock or 0)
	self:_tick_aura(self._clock or 0)
end

HudElementGrandfathersTarotLast.update = function (self, dt, t, ui_renderer, render_settings, input_service)
	HudElementGrandfathersTarotLast.super.update(self, dt, t, ui_renderer, render_settings, input_service)

	self._clock = (self._clock or 0) + (tonumber(dt) or 0)

	local ok, err = pcall(self._refresh, self)

	if not ok then
		self:_hide()

		if not self._reported then self._reported = mod:error("[hud] last card refresh failed: %s", tostring(err)) or true end
	end
end

-- (2026-10-06, a performance pass) nothing to draw while hidden: no render pass at all
HudElementGrandfathersTarotLast.draw = function (self, ...)
	if not (self._widget and self._widget.visible) then return end

	return HudElementGrandfathersTarotLast.super.draw(self, ...)
end

return HudElementGrandfathersTarotLast
