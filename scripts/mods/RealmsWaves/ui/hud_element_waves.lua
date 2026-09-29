-- On-screen panel: countdown, upcoming wave(s), live votes, incoming banner.
-- It renders whatever core/director.lua's view() returns; on the host that is
-- the authoritative state, on clients the last state the host synced. The text
-- is rebuilt only when the state or the displayed second changes.
--
-- Position: the "panel" scenegraph node is movable with the custom_hud mod
-- (its edit mode lists this element as "HudElementRealmsWavesPanel|panel").
-- While that edit mode is open a sample panel is shown so there is something to drag.
local mod = get_mod("RealmsWaves")

local Definitions = mod:io_dofile("RealmsWaves/scripts/mods/RealmsWaves/ui/hud_element_waves_definitions")

local HudElementRealmsWavesPanel = class("HudElementRealmsWavesPanel", "HudElementBase")

local COLOUR_HEADER = { 255, 255, 220, 90 }
local COLOUR_URGENT = { 255, 255, 120, 90 }
local COLOUR_LINE = { 255, 235, 235, 235 }
local COLOUR_MINE = { 255, 120, 235, 120 }
local COLOUR_HINT = { 200, 190, 190, 190 }

local function time_text(seconds)
	seconds = math.max(0, math.ceil(seconds))

	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- 52.100000000000001 -> "52.1", 12.0 -> "12"
local function pct_text(value)
	local text = string.format("%.1f", tonumber(value) or 0)

	return (text:gsub("%.0$", ""))
end

local function key_label(index)
	local keys = mod:get("vote_" .. index .. "_bind")

	if type(keys) == "table" and #keys > 0 then
		return string.upper(table.concat(keys, "+"))
	end

	return tostring(index)
end

local function hint_text(count)
	local labels = {}

	for i = 1, count do
		labels[#labels + 1] = string.format("%s=%d", key_label(i), i)
	end

	return table.concat(labels, "  ")
end

local SAMPLE = {
	phase = "voting",
	mode = "vote",
	remaining = 45,
	ballot_id = 0,
	chosen = "",
	version = 0,
	my_vote = 1,
	cands = {
		{ name = "Hound Frenzy", pct = 9, votes = 2 },
		{ name = "Elite Squad", pct = 8, votes = 1 },
		{ name = "Medium Wave", pct = 14, votes = 0 },
	},
}

HudElementRealmsWavesPanel.init = function (self, parent, draw_layer, start_scale)
	HudElementRealmsWavesPanel.super.init(self, parent, draw_layer, start_scale, Definitions)

	self._sig = nil
	self._visible = false
end

local function set_line(widget, index, text, colour)
	local style = widget.style["line_" .. index]

	widget.content["line_" .. index] = text

	local target = style.text_color

	target[1], target[2], target[3], target[4] = colour[1], colour[2], colour[3], colour[4]
end

HudElementRealmsWavesPanel._hide = function (self)
	local widget = self._widgets_by_name.panel

	if widget and self._visible then
		for i = 0, Definitions.LINES - 1 do
			widget.content["line_" .. i] = ""
		end
	end

	self._visible = false
	self._sig = nil
end

local function customizing()
	local custom_hud = get_mod("custom_hud")

	return custom_hud ~= nil and custom_hud.is_customizing == true
end

HudElementRealmsWavesPanel._refresh = function (self)
	local rw = mod.rw
	local director = rw and rw.director
	local sample = customizing()

	if not director or not mod:is_enabled() or (mod:get("hud_enabled") == false and not sample) then
		return self:_hide()
	end

	local view = director.view()

	if sample and view.phase == "off" then
		view = SAMPLE
	end

	if view.phase == "off" then
		return self:_hide()
	end

	local seconds = math.ceil(view.remaining)
	local votes_total = 0
	local cands = view.cands or {}

	for i = 1, #cands do
		votes_total = votes_total + (cands[i].votes or 0)
	end

	local sig = view.phase .. "|" .. tostring(view.mode) .. "|" .. seconds .. "|" .. tostring(view.version) .. "|" .. tostring(view.my_vote) .. "|" .. votes_total .. "|" .. tostring(view == SAMPLE)

	if sig == self._sig then
		return
	end

	self._sig = sig
	self._visible = true

	local widget = self._widgets_by_name.panel

	if not widget then
		return
	end

	for i = 0, Definitions.LINES - 1 do
		widget.content["line_" .. i] = ""
	end

	local is_vote = view.mode == "vote"
	local line = 0
	local time = time_text(view.remaining)

	if view.phase == "incoming" then
		set_line(widget, 0, mod:localize("hud_incoming", view.chosen), COLOUR_URGENT)

		return
	end

	if view.empty then
		set_line(widget, 0, mod:localize("hud_empty"), COLOUR_HEADER)

		return
	end

	if view.phase == "voting" then
		set_line(widget, 0, mod:localize("hud_vote_now", time, ""), COLOUR_URGENT)
	elseif is_vote then
		set_line(widget, 0, mod:localize("hud_wave_in_vote", time, hint_text(#cands)), COLOUR_HEADER)
	else
		set_line(widget, 0, mod:localize("hud_wave_in", time), COLOUR_HEADER)
	end

	for i = 1, math.min(#cands, Definitions.LINES - 2) do
		local cand = cands[i]
		local colour = view.my_vote == i and COLOUR_MINE or COLOUR_LINE

		if is_vote then
			set_line(widget, i, mod:localize("hud_line_votes", key_label(i), cand.name, pct_text(cand.pct), cand.votes or 0), colour)
		else
			set_line(widget, i, mod:localize("hud_line", ">", cand.name, pct_text(cand.pct)), colour)
		end

		line = i
	end

	if is_vote and line > 0 then
		set_line(widget, line + 1, hint_text(line), COLOUR_HINT)
	end
end

HudElementRealmsWavesPanel.update = function (self, dt, t, ui_renderer, render_settings, input_service)
	HudElementRealmsWavesPanel.super.update(self, dt, t, ui_renderer, render_settings, input_service)

	local ok, err = pcall(self._refresh, self)

	if not ok then
		self._sig = nil

		if not self._reported then
			self._reported = true

			mod:error("[hud] refresh failed: %s", tostring(err))
		end
	end
end

return HudElementRealmsWavesPanel
