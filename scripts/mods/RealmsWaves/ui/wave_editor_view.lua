-- Wave editor: lists every wave (standard + 20 custom slots), shows its
-- composition, and lets you rename it, change its enemies (stepper, add,
-- remove, or edit as text), and set its chance, cooldown and enabled state.
-- Everything is written straight to DMF settings (see catalog/events.lua), so
-- changes take effect on the host's next draw; nothing needs saving.
--
-- Screens (self._screen): "list" -> "detail" (one wave) -> "picker" (add an enemy).
-- Structure and vanilla widget usage follow RealmsEvent's editor view.
local mod = get_mod("RealmsWaves")

local BASE = "RealmsWaves/scripts/mods/RealmsWaves"
local ViewElementInputLegend = require("scripts/ui/view_elements/view_element_input_legend/view_element_input_legend")
local Components = mod:io_dofile(BASE .. "/ui/wave_editor_components")
local definitions = mod:io_dofile(BASE .. "/ui/wave_editor_definitions")
local blueprints = mod:io_dofile(BASE .. "/ui/wave_editor_blueprints")

local Popup = Components.Popup
local LIST_CAPACITY = definitions.LIST_CAPACITY
local LIST_TOP = definitions.LIST_TOP
local ROW_HEIGHT = definitions.ROW_HEIGHT
local ROW_NODE_PREFIX = definitions.ROW_NODE_PREFIX

local ROW_HOTSPOTS = { "hotspot_check", "hotspot_name", "hotspot_minus", "hotspot_value", "hotspot_plus", "hotspot_action", "hotspot_mods", "hotspot_rep_minus", "hotspot_rep_value", "hotspot_rep_plus", "hotspot_same" }
local STEPPER_WIDGETS = { "stepper_chance", "stepper_cooldown", "stepper_spread", "stepper_every", "stepper_for", "stepper_dmin", "stepper_dmax" }
local STEPPER_HOTSPOTS = { "hotspot_minus", "hotspot_value", "hotspot_plus" }
local BUTTONS = {
	{ name = "btn_back", width = 180, cb = "cb_back" },
	{ name = "btn_search", width = 420, cb = "cb_search" },
	{ name = "btn_stay", width = 560, cb = "cb_toggle_stay" },
	{ name = "btn_rename", width = 200, cb = "cb_rename" },
	{ name = "btn_text", width = 250, cb = "cb_edit_text" },
	{ name = "btn_add", width = 230, cb = "cb_add" },
	{ name = "btn_enabled", width = 260, cb = "cb_toggle_enabled" },
	{ name = "btn_reset", width = 300, cb = "cb_reset" },
	-- presets (list screen -> presets screen -> one preset)
	{ name = "btn_presets", width = 300, cb = "cb_presets" },
	{ name = "btn_settings", width = 340, cb = "cb_settings" },
	{ name = "btn_wimport", width = 300, cb = "cb_wave_import" },
	{ name = "btn_share", width = 280, cb = "cb_wave_share" },
	{ name = "btn_pload", width = 250, cb = "cb_preset_load" },
	{ name = "btn_psave", width = 400, cb = "cb_preset_save" },
	{ name = "btn_prename", width = 200, cb = "cb_preset_rename" },
	{ name = "btn_pexport", width = 220, cb = "cb_preset_export" },
	{ name = "btn_pimport", width = 220, cb = "cb_preset_import" },
	{ name = "btn_pundo", width = 380, cb = "cb_preset_undo" },
	{ name = "btn_pclear", width = 260, cb = "cb_preset_clear" },
}
local PRESET_BUTTONS = { "btn_pload", "btn_psave", "btn_prename", "btn_pexport", "btn_pimport", "btn_pundo", "btn_pclear" }

local function get_setting(id)
	return mod:get(id)
end

local function set_setting(id, value)
	mod:set(id, value)
end

-- True while the list rows/scrolling may be used even though a popup is open (the enemy search box).
local function rows_active(self)
	return self._popup == nil or self._popup.spec.allow_rows == true
end

local function copy_parts(parts)
	local copy = {}

	for i = 1, #(parts or {}) do
		local part = parts[i]

		copy[i] = {
			breed = part.breed,
			count = part.count,
			rep = part.rep,
			rep_same = part.rep_same,
			one_of = part.one_of and { unpack(part.one_of) } or nil,
			mods = part.mods and { unpack(part.mods) } or nil,
		}
	end

	return copy
end

RealmsWavesView = class("RealmsWavesView", "BaseView")

RealmsWavesView.init = function (self, settings)
	self._screen = "list"
	self._offset = 0
	self._waves = {}
	self._parts = {}
	self._breeds = {}
	self._preset_slots = {} -- presets screen rows
	self._preset_waves = {} -- rows of the preset being viewed
	self._settings_rows = {} -- rows of the timing/voting/display screen

	RealmsWavesView.super.init(self, definitions, settings)
end

-- ------------------------------------------------------------------ lifecycle

RealmsWavesView.on_enter = function (self)
	RealmsWavesView.super.on_enter(self)

	self:_setup_input_legend()
	self:_create_editor_widgets()

	self._screen = "list"
	self._offset = 0
	self._key = nil
	self._confirm = nil

	-- the Spidey Sense colours (or this mod's colour options) may have changed since last time
	if mod.rw.colors then
		mod.rw.colors.clear_cache()
	end

	self:_reload()
	self:_apply_screen()
end

RealmsWavesView.on_exit = function (self)
	self._screen = "list"
	Popup.cancel(self)
	self:_refresh_text_flag()

	-- a client's waves may have changed: tell the host (used when it has "use everyone's waves" on)
	local director = mod.rw and mod.rw.director

	if director and director.send_waves then
		pcall(director.send_waves)
	end

	RealmsWavesView.super.on_exit(self)
end

RealmsWavesView.update = function (self, dt, t, input_service)
	if self._auto_typed then
		self:_finish_auto_search()
	end

	Popup.update(self, input_service)

	-- a pending "Sure?" (second click to delete/reset) runs out after a few seconds
	self._t = t or self._t or 0

	if self._confirm and self._t > self._confirm.expires then
		self._confirm = nil
		self:_refresh_rows()
	end

	if self._screen == "picker" and not self._popup then
		self:_auto_search()
	end

	if (self._popup == nil or self._popup.spec.allow_rows) and input_service:get("scroll_axis") then
		local scroll = input_service:get("scroll_axis")
		local amount = scroll and scroll[2] or 0
		local max_offset = math.max(0, #self:_source() - LIST_CAPACITY)

		if amount ~= 0 and max_offset > 0 then
			self._offset = math.clamp(self._offset + (amount > 0 and -2 or 2), 0, max_offset)
			self:_refresh_rows()
			self:_set_interaction_enabled()
		end
	end

	return RealmsWavesView.super.update(self, dt, t, input_service)
end

RealmsWavesView._setup_input_legend = function (self)
	self._input_legend_element = self:_add_element(ViewElementInputLegend, "input_legend", 100)

	local legend_inputs = self._definitions.legend_inputs

	for i = 1, #legend_inputs do
		local legend_input = legend_inputs[i]
		local on_pressed_callback = legend_input.on_pressed_callback and callback(self, legend_input.on_pressed_callback)

		self._input_legend_element:add_entry(
			legend_input.display_name,
			legend_input.input_action,
			legend_input.visibility_function,
			on_pressed_callback,
			legend_input.alignment
		)
	end
end

RealmsWavesView._on_back_pressed = function (self)
	if Popup.cancel(self) then
		return
	end

	if self._screen ~= "list" then
		self:cb_back()

		return
	end

	Managers.ui:close_view(self.view_name)
end

-- BaseView._create_widget registers by name only; dynamic widgets must be
-- appended to _widgets to be drawn (RealmsEvent does the same).
RealmsWavesView._create_dynamic_widget = function (self, name, definition)
	local existing = self._widgets_by_name[name]

	if existing then
		for i = #self._widgets, 1, -1 do
			if self._widgets[i] == existing then
				table.remove(self._widgets, i)
			end
		end
	end

	local widget = RealmsWavesView.super._create_widget(self, name, definition)

	self._widgets[#self._widgets + 1] = widget

	return widget
end

-- NOTE: must not be called `_create_widgets`: BaseView already has a method of
-- that name that builds the static widgets from definitions.widget_definitions
-- (and BaseView calls it before on_enter). Overriding it left title_text etc. nil.
RealmsWavesView._create_editor_widgets = function (self)
	for i = 1, LIST_CAPACITY do
		local name = ROW_NODE_PREFIX .. i
		local widget = self:_create_dynamic_widget(name, blueprints.row(name))
		local content = widget.content

		content.hotspot_check.pressed_callback = callback(self, "cb_row_check", i)
		content.hotspot_name.pressed_callback = callback(self, "cb_row_name", i)
		content.hotspot_minus.pressed_callback = callback(self, "cb_row_minus", i)
		content.hotspot_value.pressed_callback = callback(self, "cb_row_value", i)
		content.hotspot_plus.pressed_callback = callback(self, "cb_row_plus", i)
		content.hotspot_action.pressed_callback = callback(self, "cb_row_action", i)
		content.hotspot_mods.pressed_callback = callback(self, "cb_row_mods", i)
		content.hotspot_rep_minus.pressed_callback = callback(self, "cb_row_rep_step", i, -1)
		content.hotspot_rep_plus.pressed_callback = callback(self, "cb_row_rep_step", i, 1)
		content.hotspot_rep_value.pressed_callback = callback(self, "cb_row_rep_input", i)
		content.hotspot_same.pressed_callback = callback(self, "cb_row_same", i)
	end

	for i = 1, #BUTTONS do
		local entry = BUTTONS[i]
		local widget = self:_create_dynamic_widget(entry.name, blueprints.button(entry.name, entry.width))

		widget.content.hotspot.pressed_callback = callback(self, entry.cb)
	end

	local chance = self:_create_dynamic_widget("stepper_chance", blueprints.setting_stepper("stepper_chance"))

	chance.content.hotspot_minus.pressed_callback = callback(self, "cb_chance_step", -1)
	chance.content.hotspot_plus.pressed_callback = callback(self, "cb_chance_step", 1)
	chance.content.hotspot_value.pressed_callback = callback(self, "cb_chance_input")

	local cooldown = self:_create_dynamic_widget("stepper_cooldown", blueprints.setting_stepper("stepper_cooldown"))

	cooldown.content.hotspot_minus.pressed_callback = callback(self, "cb_cooldown_step", -5)
	cooldown.content.hotspot_plus.pressed_callback = callback(self, "cb_cooldown_step", 5)
	cooldown.content.hotspot_value.pressed_callback = callback(self, "cb_cooldown_input")

	-- spread radius, repeat every, repeat for
	local extra_steppers = {
		{ name = "stepper_spread", width = 480, step = 1, cb = "spread" },
		{ name = "stepper_every", width = 640, step = 1, cb = "every" },
		{ name = "stepper_for", width = 515, step = 5, cb = "for" },
		{ name = "stepper_dmin", width = 640, step = 5, cb = "dmin" },
		{ name = "stepper_dmax", width = 640, step = 5, cb = "dmax" },
	}

	for i = 1, #extra_steppers do
		local entry = extra_steppers[i]
		local widget = self:_create_dynamic_widget(entry.name, blueprints.setting_stepper(entry.name, entry.width))

		widget.content.hotspot_minus.pressed_callback = callback(self, "cb_" .. entry.cb .. "_step", -entry.step)
		widget.content.hotspot_plus.pressed_callback = callback(self, "cb_" .. entry.cb .. "_step", entry.step)
		widget.content.hotspot_value.pressed_callback = callback(self, "cb_" .. entry.cb .. "_input")
	end

	local up = self:_create_dynamic_widget("rw_scroll_up", blueprints.scroll_button("scroll_up", "^"))
	local down = self:_create_dynamic_widget("rw_scroll_down", blueprints.scroll_button("scroll_down", "v"))

	up.content.hotspot.pressed_callback = callback(self, "cb_scroll", -1)
	down.content.hotspot.pressed_callback = callback(self, "cb_scroll", 1)

	local confirm = self:_create_dynamic_widget(Components.POPUP_CONFIRM_NAME, blueprints.popup_confirm)
	local cancel = self:_create_dynamic_widget(Components.POPUP_CANCEL_NAME, blueprints.popup_cancel)

	confirm.content.hotspot.pressed_callback = callback(self, "cb_popup_confirm")
	cancel.content.hotspot.pressed_callback = callback(self, "cb_popup_cancel")

	self:_create_dynamic_widget(Components.POPUP_INPUT_NAME, blueprints.popup_input)

	Popup.refresh(self)
end

-- ----------------------------------------------------------------------- model

RealmsWavesView._reload = function (self)
	local rw = mod.rw
	local keys = rw.events.keys()
	local waves, total = {}, 0

	for i = 1, #keys do
		local wave = rw.events.get(keys[i], get_setting, rw.groups)

		waves[i] = wave

		if wave.key == self._key then
			self._wave = wave
		end

		if wave.enabled and wave.parts and #wave.parts > 0 and wave.pct > 0 then
			total = total + wave.pct
		end
	end

	self._waves = waves
	self._total_pct = total
end

RealmsWavesView._share_of = function (self, wave)
	if wave.enabled and wave.parts and #wave.parts > 0 and wave.pct > 0 and (self._total_pct or 0) > 0 then
		return wave.pct / self._total_pct * 100
	end

	return nil
end

RealmsWavesView._source = function (self)
	if self._screen == "detail" then
		return self._parts
	elseif self._screen == "picker" then
		return self._breeds
	elseif self._screen == "mods" then
		return mod.rw.groups.MODIFIERS
	elseif self._screen == "presets" then
		return self._preset_slots
	elseif self._screen == "preset_view" then
		return self._preset_waves
	elseif self._screen == "settings" then
		return self._settings_rows
	end

	return self._waves
end

-- ------------------------------------------------------------ settings rows (timing, voting, display)

local SETTINGS_ROWS = {
	-- id, kind, then the numbers for a "number" row. Labels/infos are localized as set_<id> / set_<id>_info.
	{ id = "mode", kind = "mode" },
	{ id = "interval_random", kind = "toggle", default = true },
	{ id = "interval_min", kind = "number", default = 150, min = 5, max = 1800, step = 5 },
	{ id = "interval_max", kind = "number", default = 300, min = 5, max = 1800, step = 5, needs = "interval_random" },
	{ id = "initial_delay", kind = "number", default = 45, min = 0, max = 600, step = 5 },
	{ id = "vote_duration", kind = "number", default = 25, min = 5, max = 120, step = 5 },
	{ id = "ballot_size", kind = "number", default = 3, min = 2, max = 5, step = 1 },
	{ id = "pool_all_players", kind = "toggle", default = false },
	{ id = "hud_show_percent", kind = "toggle", default = true },
	{ id = "colour_enemies", kind = "toggle", default = true },
	{ id = "colour_spidey", kind = "toggle", default = true, needs = "colour_enemies" },
}

local function setting_flag(id, default)
	local value = mod:get(id)

	if value == nil then
		return default == true
	end

	return value == true
end

-- Live rows for the settings screen (values come straight from the mod's settings).
RealmsWavesView._reload_settings = function (self)
	local rows = {}
	local random_on = setting_flag("interval_random", true)

	for i = 1, #SETTINGS_ROWS do
		local def = SETTINGS_ROWS[i]
		local row = { id = def.id, kind = def.kind, min = def.min, max = def.max, step = def.step, number = nil, on = nil }
		local label_key = "set_" .. def.id

		if def.kind == "number" then
			row.number = math.clamp(math.floor((tonumber(mod:get(def.id)) or def.default) + 0.5), def.min, def.max)
		elseif def.kind == "mode" then
			row.on = mod:get("mode") == "vote"
		else
			row.on = setting_flag(def.id, def.default)
		end

		if def.id == "interval_min" and not random_on then
			label_key = "set_interval_fixed"
		end

		row.label = mod:localize(label_key)
		row.info = mod:localize(label_key .. "_info")
		row.muted = (def.id == "interval_max" and not random_on) or (def.needs == "colour_enemies" and not setting_flag("colour_enemies", true))
		rows[i] = row
	end

	self._settings_rows = rows
end

-- Colour tags for the enemy names inside a summary line (nil-safe: no colours -> plain text).
RealmsWavesView._painter = function (self)
	local colors = mod.rw.colors

	if not colors then
		return nil
	end

	return function (text, part)
		return colors.markup(text, colors.rgb(part.breed))
	end
end

-- What the right-hand button of a wave row does: "delete" (custom wave with enemies), "create" (empty
-- custom slot), "reset" (changed standard wave), or nil (nothing to do: unchanged standard wave).
RealmsWavesView._row_action = function (self, wave)
	if wave.is_custom then
		return (wave.parts and #wave.parts > 0) and "delete" or "create"
	end

	return wave.modified and "reset" or nil
end

-- ------------------------------------------------------------------- presets model

-- Reads the five slots (name, changed-wave count, a few wave names) for the presets screen.
RealmsWavesView._reload_presets = function (self)
	local rw = mod.rw
	local slots = {}

	for index = 1, rw.presets.COUNT do
		local preset, problem = rw.presets.read(get_setting, rw.presets.slot_id(index), rw.events, rw.groups)
		local slot = { index = index, preset = preset, problem = problem }

		if preset then
			local names = {}

			for i = 1, math.min(#preset.waves, 4) do
				names[i] = preset.waves[i].name
			end

			slot.name = preset.name
			slot.info = #preset.waves == 0 and mod:localize("preset_all_default") or mod:localize("preset_slot_info", #preset.waves, table.concat(names, ", ") .. (#preset.waves > 4 and ", ..." or ""))
		else
			slot.name = rw.presets.default_name(index)
			slot.info = problem and mod:localize("preset_slot_broken", problem) or mod:localize("preset_slot_empty")
		end

		slots[index] = slot
	end

	self._preset_slots = slots
end

-- The waves stored in the open preset, as list rows.
RealmsWavesView._reload_preset_view = function (self)
	local rw = mod.rw
	local slot = self._preset_slots[self._preset_index]
	local preset = slot and slot.preset
	local rows = {}

	for i = 1, #(preset and preset.waves or {}) do
		local wave = preset.waves[i]
		local parts = wave.recipe ~= "" and rw.groups.parse(wave.recipe) or nil
		local text = parts and rw.groups.summary(parts, 95, self:_painter()) or mod:localize("row_empty_slot")

		rows[i] = {
			name = wave.name,
			info = wave.enabled and text or (mod:localize("preset_wave_disabled") .. " " .. text),
			enabled = wave.enabled,
		}
	end

	self._preset_waves = rows
end

RealmsWavesView._open_preset = function (self, index)
	self._preset_index = index
	self._preset_note = nil
	self._screen = "preset_view"
	self._offset = 0
	self:_reload_preset_view()
	self:_apply_screen()
end

-- After the stored preset changed (save, rename, import, clear): re-read everything and redraw.
RealmsWavesView._refresh_preset = function (self, note)
	self._preset_note = note
	self:_reload_presets()
	self:_reload_preset_view()
	self:_apply_screen(true)
end

RealmsWavesView._item_at = function (self, row_index)
	return self:_source()[self._offset + row_index]
end

RealmsWavesView._save = function (self)
	local rw = mod.rw

	rw.events.set_def(set_setting, self._key, self._wave.name, self._parts, rw.groups)
	self:_reload()
	self._parts = copy_parts(self._wave.parts)
	self:_apply_screen(true)
end

RealmsWavesView._open_detail = function (self, key)
	self._key = key
	self:_reload()
	self._parts = copy_parts(self._wave.parts)
	self._screen = "detail"
	self._offset = 0
	self:_apply_screen()
end

-- --------------------------------------------------------------------- display

RealmsWavesView._apply_screen = function (self, keep_offset)
	local widgets = self._widgets_by_name
	local screen = self._screen
	local rw = mod.rw

	self:_refresh_text_flag()

	if not keep_offset then
		self._offset = 0
	end

	if screen == "picker" then
		self._breeds = rw.groups.search(self._filter or "")
	end

	self._offset = math.clamp(self._offset, 0, math.max(0, #self:_source() - LIST_CAPACITY))

	widgets.title_text.content.title_text = mod:localize("view_title")

	local header = widgets.list_header.content

	header.col_6 = ""
	header.col_7 = ""

	if screen == "list" then
		widgets.description_text.content.description_text = mod:localize("view_desc_list")
		header.col_1, header.col_2, header.col_3 = mod:localize("col_on"), mod:localize("col_wave"), mod:localize("col_composition")
		header.col_4, header.col_5 = mod:localize("col_chance"), mod:localize("col_share")
		widgets.bottom_title.content.bottom_title = mod:localize("bottom_list_title")
		widgets.hint_text.content.hint_text = mod:localize("hint_list")
	elseif screen == "detail" then
		widgets.description_text.content.description_text = mod:localize("view_desc_detail", self._wave.name)
		header.col_1, header.col_2, header.col_3 = "", mod:localize("col_enemy"), mod:localize("col_modifier")
		header.col_4, header.col_5 = mod:localize("col_count"), ""
		header.col_6 = mod:localize("col_repeat")
		header.col_7 = mod:localize("col_same")
		widgets.bottom_title.content.bottom_title = mod:localize("bottom_detail_title", self._wave.name, rw.groups.total_count(self._parts))
		widgets.hint_text.content.hint_text = ""
	elseif screen == "picker" then
		widgets.description_text.content.description_text = mod:localize("view_desc_picker", self._wave.name)
		header.col_1, header.col_2, header.col_3, header.col_4, header.col_5 = "", mod:localize("col_enemy"), mod:localize("col_id"), "", ""

		local shown, total = #self._breeds, #rw.groups.breed_list()

		local status

		if (self._filter or "") ~= "" then
			status = mod:localize("picker_status_filtered", shown, total, self._filter)
		else
			status = mod:localize("picker_status", shown, total)
		end

		-- shown in the description (top of the screen) so it stays visible under the search popup
		if self._picker_note then
			status = self._picker_note .. "   " .. status
		end

		widgets.description_text.content.description_text = widgets.description_text.content.description_text .. "   " .. status
		widgets.bottom_title.content.bottom_title = status

		widgets.hint_text.content.hint_text = ""
	elseif screen == "settings" then
		widgets.description_text.content.description_text = mod:localize("view_desc_settings")
		header.col_1, header.col_2, header.col_3, header.col_4, header.col_5 = "", mod:localize("col_setting"), mod:localize("col_what_it_does"), mod:localize("col_value"), ""
		widgets.bottom_title.content.bottom_title = ""
		widgets.hint_text.content.hint_text = mod:localize("hint_settings")
	elseif screen == "presets" then
		widgets.description_text.content.description_text = mod:localize("view_desc_presets")
		header.col_1, header.col_2, header.col_3, header.col_4, header.col_5 = "", mod:localize("col_preset"), mod:localize("col_preset_holds"), "", ""
		widgets.bottom_title.content.bottom_title = self._preset_note or ""
		widgets.hint_text.content.hint_text = mod:localize("hint_presets")
	elseif screen == "preset_view" then
		local slot = self._preset_slots[self._preset_index]
		local preset = slot and slot.preset

		widgets.description_text.content.description_text = mod:localize("view_desc_preset", self._preset_index, slot and slot.name or "")
		header.col_1, header.col_2, header.col_3, header.col_4, header.col_5 = "", mod:localize("col_wave"), mod:localize("col_composition"), "", ""
		widgets.bottom_title.content.bottom_title = self._preset_note or (preset and mod:localize("preset_view_title", #preset.waves) or mod:localize("preset_slot_empty_long"))
		widgets.hint_text.content.hint_text = ""
	else
		local part = self._parts[self._part_index]

		widgets.description_text.content.description_text = mod:localize("view_desc_mods", part and rw.groups.describe_part(part) or "")
		header.col_1, header.col_2, header.col_3 = mod:localize("col_on"), mod:localize("col_modifier"), mod:localize("col_effect")
		header.col_4, header.col_5 = "", ""
		widgets.bottom_title.content.bottom_title = ""
		widgets.hint_text.content.hint_text = mod:localize("hint_mods")
	end

	local detail = screen == "detail"
	local show_back = screen ~= "list"

	local preset_view = screen == "preset_view"
	local preset_slot = preset_view and self._preset_slots[self._preset_index]

	widgets.hint_text.visible = screen == "list" or screen == "mods" or screen == "presets" or screen == "settings"
	widgets.btn_presets.visible = screen == "list"
	widgets.btn_settings.visible = screen == "list"
	widgets.btn_settings.content.hotspot_text = mod:localize("btn_settings")
	widgets.btn_wimport.visible = screen == "list"
	widgets.btn_wimport.content.hotspot_text = mod:localize("btn_wimport")
	widgets.btn_share.visible = detail
	widgets.btn_share.content.hotspot_text = mod:localize("btn_share")
	widgets.btn_back.visible = show_back

	for i = 1, #PRESET_BUTTONS do
		widgets[PRESET_BUTTONS[i]].visible = preset_view
	end

	if preset_view then
		widgets.btn_pundo.visible = mod:get(mod.rw.presets.UNDO_ID) ~= nil and mod:get(mod.rw.presets.UNDO_ID) ~= ""
		widgets.btn_pclear.visible = preset_slot ~= nil and (preset_slot.preset ~= nil or preset_slot.problem ~= nil)
	end

	widgets.btn_presets.content.hotspot_text = mod:localize("btn_presets")
	widgets.btn_pload.content.hotspot_text = mod:localize("btn_pload")
	widgets.btn_psave.content.hotspot_text = mod:localize("btn_psave")
	widgets.btn_prename.content.hotspot_text = mod:localize("btn_rename")
	widgets.btn_pexport.content.hotspot_text = mod:localize("btn_pexport")
	widgets.btn_pimport.content.hotspot_text = mod:localize("btn_pimport")
	widgets.btn_pundo.content.hotspot_text = mod:localize("btn_pundo")
	widgets.btn_pclear.content.hotspot_text = mod:localize("btn_pclear")
	widgets.btn_search.visible = screen == "picker"
	widgets.btn_stay.visible = screen == "picker"
	widgets.btn_rename.visible = detail
	widgets.btn_text.visible = detail
	widgets.btn_add.visible = detail
	widgets.btn_enabled.visible = detail
	widgets.btn_reset.visible = detail
	for i = 1, #STEPPER_WIDGETS do
		widgets[STEPPER_WIDGETS[i]].visible = detail
	end

	widgets.btn_back.content.hotspot_text = mod:localize("btn_back")
	widgets.btn_search.content.hotspot_text = (self._filter or "") ~= "" and mod:localize("btn_search_active", self._filter) or mod:localize("btn_search")
	widgets.btn_stay.content.hotspot_text = mod:localize(mod:get("picker_stay") == true and "btn_stay_on" or "btn_stay_off")
	widgets.btn_rename.content.hotspot_text = mod:localize("btn_rename")
	widgets.btn_text.content.hotspot_text = mod:localize("btn_edit_text")
	widgets.btn_add.content.hotspot_text = mod:localize("btn_add_enemy")

	if detail then
		local wave = self._wave

		widgets.btn_enabled.content.hotspot_text = mod:localize(wave.enabled and "btn_enabled_on" or "btn_enabled_off")
		widgets.btn_reset.content.hotspot_text = mod:localize(wave.is_custom and "btn_reset_clear" or "btn_reset_default")

		local chance = widgets.stepper_chance.content
		local share = self:_share_of(wave)

		chance.label = mod:localize("lbl_chance")
		chance.stepper_value = tostring(math.floor(wave.pct))
		chance.extra = share and mod:localize("extra_share", string.format("%.1f", share)) or mod:localize("extra_not_drawn")

		local cooldown = widgets.stepper_cooldown.content

		cooldown.label = mod:localize("lbl_cooldown")
		cooldown.stepper_value = tostring(math.floor(wave.cooldown))
		cooldown.extra = mod:localize("extra_cooldown")

		local spread = widgets.stepper_spread.content

		spread.label = mod:localize("lbl_spread")
		spread.stepper_value = tostring(math.floor(wave.spread))
		spread.extra = mod:localize("extra_meters")

		local repeating = rw.groups.has_repeat(self._parts)
		local every = widgets.stepper_every.content
		local rep_for = widgets.stepper_for.content

		every.label = mod:localize("lbl_repeat_every")
		every.stepper_value = tostring(math.floor(wave.rep_every))
		every.extra = mod:localize(repeating and "extra_seconds" or "extra_no_repeat")
		rep_for.label = mod:localize("lbl_repeat_for")
		rep_for.stepper_value = tostring(math.floor(wave.rep_for))
		rep_for.extra = mod:localize("extra_seconds_short")

		-- this wave's own spawn distances; 0 shows "auto" = the options' values
		local dist_min, dist_max = widgets.stepper_dmin.content, widgets.stepper_dmax.content
		local option_min = tonumber(mod:get(wave.monster and "monster_min_distance" or "min_distance")) or (wave.monster and 28 or 22)
		local option_max = tonumber(mod:get(wave.monster and "monster_max_distance" or "max_distance")) or (wave.monster and 75 or 65)

		dist_min.label = mod:localize("lbl_dmin")
		dist_min.stepper_value = wave.dmin > 0 and tostring(math.floor(wave.dmin)) or mod:localize("val_auto")
		dist_min.extra = wave.dmin > 0 and mod:localize("extra_dist_own") or mod:localize("extra_dist_auto", math.floor(option_min))
		dist_max.label = mod:localize("lbl_dmax")
		dist_max.stepper_value = wave.dmax > 0 and tostring(math.floor(wave.dmax)) or mod:localize("val_auto")
		dist_max.extra = wave.dmax > 0 and mod:localize("extra_dist_own") or mod:localize("extra_dist_auto", math.floor(option_max))
	end

	self:_refresh_rows()
	self:_set_interaction_enabled()
end

RealmsWavesView._refresh_rows = function (self)
	local rw = mod.rw
	local colors = rw.colors
	local screen = self._screen
	local source = self:_source()

	for i = 1, LIST_CAPACITY do
		local widget = self._widgets_by_name[ROW_NODE_PREFIX .. i]
		local item = source[self._offset + i]

		self:_set_scenegraph_position(ROW_NODE_PREFIX .. i, 105, LIST_TOP + (i - 1) * ROW_HEIGHT, 1)

		if widget then
			widget.visible = item ~= nil

			if item then
				local content = widget.content
				local name_color = Components.colors.text

				if screen == "list" then
					local share = self:_share_of(item)
					local has_parts = item.parts and #item.parts > 0

					local action = self:_row_action(item)
					local pending = self._confirm and self._confirm.key == item.key

					content.row_name = item.name
					content.info = has_parts and rw.groups.summary(item.parts, 95, self:_painter()) or mod:localize("row_empty_slot")
					content.show_check, content.show_stepper, content.show_share, content.show_action, content.show_mods = true, true, true, action ~= nil, false
					content.show_rep = false
					content.checkbox_selected = item.enabled and has_parts == true
					content.stepper_value = tostring(math.floor(item.pct))
					content.share = share and string.format("%.1f%%", share) or "-"
					content.hotspot_action_text = action and mod:localize(pending and "btn_sure" or ("btn_" .. action)) or ""

					if not (item.enabled and has_parts) then
						name_color = Components.colors.muted
					end
				elseif screen == "detail" then
					local mods_text = rw.groups.describe_mods(item)

					content.row_name = rw.groups.describe_part(item)
					content.info = #mods_text > 40 and (mods_text:sub(1, 37) .. "...") or mods_text
					content.show_check, content.show_stepper, content.show_share, content.show_action, content.show_mods = false, true, false, true, true
					content.show_rep = true
					content.stepper_value = tostring(item.count)
					content.same_selected = item.rep_same == true
					-- with "same" ticked the repeat number is the initial count, shown as "="
					content.rep_value = item.rep_same and "=" or tostring(item.rep or 0)
					content.hotspot_action_text = mod:localize("btn_remove")
					content.hotspot_mods_text = mod:localize("btn_mods")
					name_color = colors and item.breed and colors.argb(item.breed) or name_color
				elseif screen == "presets" then
					content.row_name = string.format("%d. %s", item.index, item.name)
					content.info = item.info
					content.show_check, content.show_stepper, content.show_share, content.show_action, content.show_mods = false, false, false, true, false
					content.show_rep = false
					content.hotspot_action_text = mod:localize("btn_open")

					if not item.preset then
						name_color = Components.colors.muted
					end
				elseif screen == "settings" then
					local is_number = item.kind == "number"

					content.row_name = item.label
					content.info = item.info
					content.show_check, content.show_stepper, content.show_share, content.show_action, content.show_mods = not is_number, is_number, false, false, false
					content.show_rep = false
					content.checkbox_selected = item.on == true
					content.stepper_value = is_number and tostring(item.number) or ""

					if item.muted then
						name_color = Components.colors.muted
					end
				elseif screen == "preset_view" then
					content.row_name = item.name
					content.info = item.info
					content.show_check, content.show_stepper, content.show_share, content.show_action, content.show_mods = false, false, false, false, false
					content.show_rep = false

					if not item.enabled then
						name_color = Components.colors.muted
					end
				elseif screen == "picker" then
					content.row_name = rw.groups.display_name(item)
					content.info = string.format("%s  (%s)", item, rw.groups.kind(item))
					name_color = colors and colors.argb(item) or name_color
					content.show_check, content.show_stepper, content.show_share, content.show_action, content.show_mods = false, false, false, true, false
					content.show_rep = false
					content.hotspot_action_text = mod:localize("btn_add")
				else
					local part = self._parts[self._part_index]
					local applied = false

					for j = 1, #(part and part.mods or {}) do
						if part.mods[j] == item.id then
							applied = true
						end
					end

					content.row_name = item.name
					content.info = item.requires_havoc and (item.description .. " " .. mod:localize("note_havoc_only")) or item.description
					content.show_check, content.show_stepper, content.show_share, content.show_action, content.show_mods = true, false, false, false, false
					content.show_rep = false
					content.checkbox_selected = applied
				end

				Components.color_into(widget.style.row_name.text_color, name_color)
			end
		end
	end

	local range = self._widgets_by_name.list_range

	if range then
		range.content.list_range = #source > 0 and mod:localize("list_range", self._offset + 1, math.min(self._offset + LIST_CAPACITY, #source), #source) or ""
	end
end

-- Enables/disables every hotspot: everything is locked while the popup is open,
-- scroll buttons stop at the ends.
RealmsWavesView._set_interaction_enabled = function (self)
	local enabled = self._popup == nil
	local rows_enabled = rows_active(self)
	local widgets = self._widgets_by_name

	for i = 1, LIST_CAPACITY do
		local widget = widgets[ROW_NODE_PREFIX .. i]

		if widget then
			for j = 1, #ROW_HOTSPOTS do
				widget.content[ROW_HOTSPOTS[j]].disabled = not (rows_enabled and widget.visible)
			end
		end
	end

	for i = 1, #BUTTONS do
		local widget = widgets[BUTTONS[i].name]

		if widget then
			widget.content.hotspot.disabled = not (enabled and widget.visible)
		end
	end

	for _, name in ipairs(STEPPER_WIDGETS) do
		local widget = widgets[name]

		if widget then
			for j = 1, #STEPPER_HOTSPOTS do
				widget.content[STEPPER_HOTSPOTS[j]].disabled = not (enabled and widget.visible)
			end
		end
	end

	local max_offset = math.max(0, #self:_source() - LIST_CAPACITY)
	local up, down = widgets.rw_scroll_up, widgets.rw_scroll_down

	if up then
		up.content.hotspot.disabled = not rows_enabled or self._offset <= 0
	end

	if down then
		down.content.hotspot.disabled = not rows_enabled or self._offset >= max_offset
	end
end

-- ------------------------------------------------------------------- callbacks

local function guarded(fn)
	return function (self, ...)
		if self._popup and not self._popup.spec.allow_rows then
			return
		end

		local ok, err = pcall(fn, self, ...)

		if not ok then
			mod:error("[editor] %s", tostring(err))
		end
	end
end

RealmsWavesView.cb_scroll = guarded(function (self, direction)
	self._offset = math.clamp(self._offset + direction, 0, math.max(0, #self:_source() - LIST_CAPACITY))
	self:_refresh_rows()
	self:_set_interaction_enabled()
end)

RealmsWavesView.cb_back = guarded(function (self)
	if self._screen == "preset_view" then
		self._screen = "presets"
		self:_reload_presets()
	elseif self._screen == "picker" or self._screen == "mods" then
		self._screen = "detail"
	else
		self._screen = "list"
		self._key = nil
	end

	self:_reload()
	self:_apply_screen()
end)

-- rows -----------------------------------------------------------------------

-- Settings screen: flip a yes/no row (the "mode" row maps to random/vote).
RealmsWavesView._toggle_setting = function (self, item)
	if item.kind == "mode" then
		set_setting("mode", item.on and "random" or "vote")
	elseif item.kind == "toggle" then
		set_setting(item.id, not item.on)
	else
		return
	end

	if mod.rw.colors then
		mod.rw.colors.clear_cache()
	end

	self:_reload_settings()
	self:_apply_screen(true)
end

RealmsWavesView._set_number_setting = function (self, item, value)
	set_setting(item.id, math.clamp(math.floor(value + 0.5), item.min, item.max))
	self:_reload_settings()
	self:_apply_screen(true)
end

RealmsWavesView.cb_settings = guarded(function (self)
	self:_reload_settings()
	self._screen = "settings"
	self:_apply_screen()
end)

RealmsWavesView.cb_row_check = guarded(function (self, row)
	if self._screen == "settings" then
		local item = self:_item_at(row)

		if item then
			self:_toggle_setting(item)
		end

		return
	end

	if self._screen == "mods" then
		local modifier = self:_item_at(row)

		if modifier then
			self:_toggle_mod(modifier.id)
		end

		return
	end

	local wave = self._screen == "list" and self:_item_at(row)

	if wave then
		set_setting("on_" .. wave.key, not wave.enabled)
		self:_reload()
		self:_apply_screen(true)
	end
end)

-- Toggles one modifier on the enemy group being edited (self._part_index).
RealmsWavesView._toggle_mod = function (self, id)
	local part = self._parts[self._part_index]

	if not part then
		return
	end

	local have = {}

	for i = 1, #(part.mods or {}) do
		have[part.mods[i]] = true
	end

	have[id] = not have[id] or nil

	local mods = {}

	for _, modifier in ipairs(mod.rw.groups.MODIFIERS) do
		if have[modifier.id] then
			mods[#mods + 1] = modifier.id
		end
	end

	part.mods = #mods > 0 and mods or nil
	self:_save()
end

RealmsWavesView.cb_row_mods = guarded(function (self, row)
	if self._screen == "detail" and self._parts[self._offset + row] then
		self._part_index = self._offset + row
		self._screen = "mods"
		self:_apply_screen()
	end
end)

RealmsWavesView.cb_row_name = guarded(function (self, row)
	local item = self:_item_at(row)

	if not item then
		return
	end

	if self._screen == "list" then
		self:_open_detail(item.key)
	elseif self._screen == "presets" then
		self:_open_preset(item.index)
	elseif self._screen == "picker" then
		self:_add_breed(item)
	elseif self._screen == "mods" then
		self:_toggle_mod(item.id)
	elseif self._screen == "settings" then
		if item.kind == "number" then
			self:_open_setting_popup(item)
		else
			self:_toggle_setting(item)
		end
	end
end)

RealmsWavesView._open_setting_popup = function (self, item)
	Popup.open(self, {
		label = item.label,
		value = tostring(item.number),
		numeric = true, min = item.min, max = item.max, integer = true,
		set = function (value)
			self:_set_number_setting(item, value)
		end,
	})
end

-- Right-hand button of a wave row: Delete (custom wave with enemies), Create (empty custom slot) or
-- Reset (changed standard wave). Delete and Reset ask for a second click ("Sure?") for a few seconds.
RealmsWavesView._wave_row_action = function (self, wave)
	local action = self:_row_action(wave)

	if action == "create" then
		self:_open_detail(wave.key)

		return
	elseif not action then
		return
	end

	if self._confirm and self._confirm.key == wave.key and (self._t or 0) <= self._confirm.expires then
		self._confirm = nil
		mod.rw.events.reset(set_setting, wave.key)
		self:_reload()
		self:_apply_screen(true)

		return
	end

	self._confirm = { key = wave.key, expires = (self._t or 0) + 4 }
	self:_refresh_rows()
end

RealmsWavesView.cb_row_action = guarded(function (self, row)
	local item = self:_item_at(row)

	if not item then
		return
	end

	if self._screen == "list" then
		self:_wave_row_action(item)
	elseif self._screen == "presets" then
		self:_open_preset(item.index)
	elseif self._screen == "detail" then
		self:_remove_part(self._offset + row)
	elseif self._screen == "picker" then
		self:_add_breed(item)
	end
end)

RealmsWavesView._step_row = function (self, row, delta)
	local item = self:_item_at(row)

	if not item then
		return
	end

	if self._screen == "settings" then
		if item.kind == "number" then
			self:_set_number_setting(item, item.number + delta * item.step)
		end
	elseif self._screen == "list" then
		set_setting("pct_" .. item.key, math.clamp(math.floor(item.pct) + delta, 0, 1000))
		self:_reload()
		self:_apply_screen(true)
	elseif self._screen == "detail" then
		-- a group that only repeats may have 0 initial units; otherwise at least 1
		item.count = math.clamp(item.count + delta, (item.rep or 0) > 0 and 0 or 1, mod.rw.groups.MAX_BREED_COUNT)
		self:_save()
	end
end

-- units added on every repeat tick for one enemy group (detail screen)
RealmsWavesView.cb_row_rep_step = guarded(function (self, row, delta)
	local item = self._screen == "detail" and self:_item_at(row)

	if not item then
		return
	end

	-- using the stepper leaves "same" mode: start from the number it stood for (the count)
	if item.rep_same then
		item.rep_same = nil
		item.rep = item.count
	end

	item.rep = math.clamp((item.rep or 0) + delta, 0, mod.rw.groups.MAX_BREED_COUNT)

	if item.rep == 0 then
		item.rep = nil

		if item.count < 1 then
			item.count = 1
		end
	end

	self:_save()
end)

-- "Same" tick box: every repeat spawns the same number as the initial spawn. Ticking clears the
-- numeric repeat; unticking turns repeating off for this group (set a number with the stepper).
RealmsWavesView.cb_row_same = guarded(function (self, row)
	local item = self._screen == "detail" and self:_item_at(row)

	if not item then
		return
	end

	if item.rep_same then
		item.rep_same = nil
	else
		item.rep_same = true
		item.rep = nil

		if item.count < 1 then
			item.count = 1
		end
	end

	self:_save()
end)

RealmsWavesView.cb_row_rep_input = guarded(function (self, row)
	local item = self._screen == "detail" and self:_item_at(row)

	if not item then
		return
	end

	Popup.open(self, {
		label = mod:localize("popup_rep_title", mod.rw.groups.describe_part(item)),
		value = tostring(item.rep_same and item.count or item.rep or 0),
		numeric = true, min = 0, max = mod.rw.groups.MAX_BREED_COUNT, integer = true,
		set = function (value)
			item.rep_same = nil
			item.rep = value > 0 and value or nil

			if not item.rep and item.count < 1 then
				item.count = 1
			end

			self:_save()
		end,
	})
end)

RealmsWavesView.cb_row_minus = guarded(function (self, row)
	self:_step_row(row, -1)
end)

RealmsWavesView.cb_row_plus = guarded(function (self, row)
	self:_step_row(row, 1)
end)

RealmsWavesView.cb_row_value = guarded(function (self, row)
	local item = self:_item_at(row)

	if not item then
		return
	end

	if self._screen == "settings" then
		if item.kind == "number" then
			self:_open_setting_popup(item)
		end
	elseif self._screen == "list" then
		Popup.open(self, {
			label = mod:localize("popup_chance_title", item.name),
			value = tostring(math.floor(item.pct)),
			numeric = true, min = 0, max = 1000, integer = true,
			set = function (value)
				set_setting("pct_" .. item.key, value)
				self:_reload()
				self:_apply_screen(true)
			end,
		})
	elseif self._screen == "detail" then
		Popup.open(self, {
			label = mod:localize("popup_count_title", mod.rw.groups.describe_part(item)),
			value = tostring(item.count),
			numeric = true, min = (item.rep or 0) > 0 and 0 or 1, max = mod.rw.groups.MAX_BREED_COUNT, integer = true,
			set = function (value)
				item.count = value
				self:_save()
			end,
		})
	end
end)

-- detail actions -------------------------------------------------------------------

-- After adding an enemy the picker either returns to the wave ("back", default) or stays open so
-- several enemies can be added in a row ("stay", toggled with the button next to Search).
RealmsWavesView._add_breed = function (self, breed)
	local groups = mod.rw.groups
	local stay = mod:get("picker_stay") == true

	-- picked while the search box was open: in "back" mode close it (keeping what was typed);
	-- in "stay" mode it stays open so the next enemy can be found right away
	if self._popup and not stay then
		Popup.close_keep(self)
	end

	local added

	for i = 1, #self._parts do
		if self._parts[i].breed == breed and not self._parts[i].mods then
			self._parts[i].count = math.min(self._parts[i].count + 1, groups.MAX_BREED_COUNT)
			added = self._parts[i].count

			break
		end
	end

	if not added then
		self._parts[#self._parts + 1] = { breed = breed, count = 1 }
		added = 1
	end

	if stay then
		self._screen = "picker"
		self._picker_note = mod:localize("picker_added", groups.display_name(breed), added)
	else
		self._screen = "detail"
		self._picker_note = nil
	end

	self:_save()
end

RealmsWavesView.cb_toggle_stay = guarded(function (self)
	mod:set("picker_stay", not (mod:get("picker_stay") == true))
	self:_apply_screen(true)
end)

RealmsWavesView._remove_part = function (self, index)
	if not self._wave.is_custom and #self._parts <= 1 then
		mod:echo("%s", mod:localize("msg_need_one_enemy"))

		return
	end

	table.remove(self._parts, index)
	self:_save()
end

RealmsWavesView.cb_rename = guarded(function (self)
	Popup.open(self, {
		label = mod:localize("popup_rename_title"),
		value = self._wave.name,
		max_length = 40,
		set = function (text)
			local name = mod.rw.events.clean_name(text)

			if name ~= "" then
				self._wave.name = name
				self:_save()
			end
		end,
	})
end)

RealmsWavesView.cb_edit_text = guarded(function (self)
	local groups = mod.rw.groups

	Popup.open(self, {
		label = mod:localize("popup_recipe_title"),
		hint = mod:localize("popup_recipe_hint"),
		value = groups.to_recipe(self._parts),
		max_length = 300,
		validate = function (text)
			local parts, err = groups.parse(text)

			return parts ~= nil, err
		end,
		set = function (text)
			self._parts = groups.parse(text) or self._parts
			self:_save()
		end,
	})
end)

RealmsWavesView.cb_add = guarded(function (self)
	self._screen = "picker"
	self._filter = ""
	self._picker_note = nil
	self:_apply_screen()
end)

-- Search box for the enemy picker. Filters live while typing (the popup sits low on the
-- screen so the list stays visible); OK keeps the filter, Cancel/Esc restores the old one.
-- `initial` (optional) replaces the box's starting text (auto-open on typing starts empty).
RealmsWavesView._open_search = function (self, initial)
	local original = self._filter or ""

	Popup.open(self, {
		label = mod:localize("popup_search_title"),
		hint = mod:localize("popup_search_hint"),
		value = initial or original,
		max_length = 40,
		y = 700,
		allow_rows = true, -- the enemy rows (and scrolling) stay clickable while the box is open
		on_change = function (text)
			self._filter = text
			self:_apply_screen()
		end,
		on_cancel = function ()
			self._filter = original
			self:_apply_screen()
		end,
		set = function (text)
			self._filter = text
			self:_apply_screen()
		end,
	})
end

RealmsWavesView.cb_search = guarded(function (self)
	self:_open_search()
end)

-- Typing on the picker screen (no box open yet) opens the search box and types what was typed,
-- so the Search button never needs clicking. Only the printable characters of this frame count
-- (Keyboard.keystrokes(): strings are typed characters, numbers are special keys).
local function typed_text()
	if not (Keyboard and Keyboard.keystrokes) then
		return nil
	end

	local ok, strokes = pcall(Keyboard.keystrokes)

	if not ok or type(strokes) ~= "table" then
		return nil
	end

	local text = ""

	for i = 1, #strokes do
		local stroke = strokes[i]

		if type(stroke) == "string" and #stroke > 0 and not stroke:find("%c") and (text ~= "" or not stroke:find("^%s+$")) then
			text = text .. stroke
		end
	end

	return text ~= "" and text or nil
end

RealmsWavesView._auto_search = function (self)
	if self._screen ~= "picker" or self._popup then
		return
	end

	local text = typed_text()

	if not text then
		return
	end

	self:_open_search("")

	-- The input widget reads this frame's keystrokes when it is drawn, right after this update. If
	-- it did not (it is text-empty next frame), fill the characters in ourselves, once.
	self._auto_typed = text
end

-- Next frame after an auto-open: make sure the typed characters really arrived.
RealmsWavesView._finish_auto_search = function (self)
	local text = self._auto_typed

	self._auto_typed = nil

	if not text or not self._popup then
		return
	end

	local content = self._widgets_by_name[Components.POPUP_INPUT_NAME].content

	if (content.input_text or "") == "" then
		Popup.set_text(self, text)
	end
end

-- DMF keybinds are polled from the raw keyboard, so on the picker screen (where any letter starts a
-- search) they are suspended as well, not only while the box is open.
RealmsWavesView._refresh_text_flag = function (self)
	if mod.rw then
		mod.rw.text_input_active = self._popup ~= nil or self._screen == "picker"
	end
end

RealmsWavesView.cb_toggle_enabled = guarded(function (self)
	set_setting("on_" .. self._key, not self._wave.enabled)
	self:_reload()
	self:_apply_screen(true)
end)

RealmsWavesView.cb_reset = guarded(function (self)
	mod.rw.events.reset(set_setting, self._key)
	self:_reload()
	self._parts = copy_parts(self._wave.parts)
	self:_apply_screen()
end)

RealmsWavesView.cb_chance_step = guarded(function (self, delta)
	set_setting("pct_" .. self._key, math.clamp(math.floor(self._wave.pct) + delta, 0, 1000))
	self:_reload()
	self:_apply_screen(true)
end)

RealmsWavesView.cb_chance_input = guarded(function (self)
	Popup.open(self, {
		label = mod:localize("popup_chance_title", self._wave.name),
		value = tostring(math.floor(self._wave.pct)),
		numeric = true, min = 0, max = 1000, integer = true,
		set = function (value)
			set_setting("pct_" .. self._key, value)
			self:_reload()
			self:_apply_screen(true)
		end,
	})
end)

RealmsWavesView.cb_cooldown_step = guarded(function (self, delta)
	set_setting("cd_" .. self._key, math.clamp(math.floor(self._wave.cooldown) + delta, 0, 3600))
	self:_reload()
	self:_apply_screen(true)
end)

RealmsWavesView.cb_cooldown_input = guarded(function (self)
	Popup.open(self, {
		label = mod:localize("popup_cooldown_title", self._wave.name),
		value = tostring(math.floor(self._wave.cooldown)),
		numeric = true, min = 0, max = 3600, integer = true,
		set = function (value)
			set_setting("cd_" .. self._key, value)
			self:_reload()
			self:_apply_screen(true)
		end,
	})
end)

-- spread radius / repeat every / repeat for -----------------------------------------

RealmsWavesView._setting_step = function (self, prefix, field, delta, min, max)
	set_setting(prefix .. self._key, math.clamp(math.floor(self._wave[field]) + delta, min, max))
	self:_reload()
	self:_apply_screen(true)
end

RealmsWavesView._setting_input = function (self, prefix, field, title_key, min, max)
	Popup.open(self, {
		label = mod:localize(title_key, self._wave.name),
		value = tostring(math.floor(self._wave[field])),
		numeric = true, min = min, max = max, integer = true,
		set = function (value)
			set_setting(prefix .. self._key, value)
			self:_reload()
			self:_apply_screen(true)
		end,
	})
end

-- 1 m per click up to 10 m, then 5 m per click (0-100 m range)
RealmsWavesView.cb_spread_step = guarded(function (self, delta)
	local value = math.floor(self._wave.spread)
	local coarse = (delta > 0 and value >= 10) or (delta < 0 and value > 10)

	self:_setting_step("sp_", "spread", coarse and delta * 5 or delta, 0, 100)
end)

RealmsWavesView.cb_spread_input = guarded(function (self)
	self:_setting_input("sp_", "spread", "popup_spread_title", 0, 100)
end)

RealmsWavesView.cb_every_step = guarded(function (self, delta)
	self:_setting_step("re_", "rep_every", delta, 1, 600)
end)

RealmsWavesView.cb_every_input = guarded(function (self)
	self:_setting_input("re_", "rep_every", "popup_every_title", 1, 600)
end)

RealmsWavesView.cb_for_step = guarded(function (self, delta)
	self:_setting_step("rf_", "rep_for", delta, 0, 3600)
end)

RealmsWavesView.cb_for_input = guarded(function (self)
	self:_setting_input("rf_", "rep_for", "popup_for_title", 0, 3600)
end)

-- this wave's own spawn distances (0 = auto: the values from the options menu)
RealmsWavesView.cb_dmin_step = guarded(function (self, delta)
	self:_setting_step("dmin_", "dmin", delta, 0, 200)
end)

RealmsWavesView.cb_dmin_input = guarded(function (self)
	self:_setting_input("dmin_", "dmin", "popup_dmin_title", 0, 200)
end)

RealmsWavesView.cb_dmax_step = guarded(function (self, delta)
	self:_setting_step("dmax_", "dmax", delta, 0, 200)
end)

RealmsWavesView.cb_dmax_input = guarded(function (self)
	self:_setting_input("dmax_", "dmax", "popup_dmax_title", 0, 200)
end)

-- presets ----------------------------------------------------------------------
-- Five named snapshots of the whole wave setup, with text export/import (catalog/presets.lua).

local function clipboard_get()
	local ok, text = pcall(function ()
		return Clipboard and Clipboard.get and Clipboard.get()
	end)

	return ok and type(text) == "string" and text or nil
end

local function clipboard_put(text)
	local ok, result = pcall(function ()
		return Clipboard and Clipboard.put and Clipboard.put(text)
	end)

	return ok and result and true or false
end

RealmsWavesView.cb_presets = guarded(function (self)
	self._preset_note = nil
	self:_reload_presets()
	self._screen = "presets"
	self:_apply_screen()
end)

RealmsWavesView._current_preset_slot = function (self)
	return self._preset_slots[self._preset_index]
end

-- Stores the current setup in the open slot (keeping the slot's name).
RealmsWavesView.cb_preset_save = guarded(function (self)
	local rw = mod.rw
	local slot = self:_current_preset_slot()
	local captured = rw.presets.capture(get_setting, rw.events, rw.groups)

	captured.name = slot.preset and slot.preset.name or rw.presets.default_name(self._preset_index)
	rw.presets.write(set_setting, rw.presets.slot_id(self._preset_index), captured)
	self:_refresh_preset(mod:localize("preset_saved", captured.name, #captured.waves))
end)

-- Replaces the current setup with the slot's. The setup being replaced is kept for "Undo last load".
RealmsWavesView.cb_preset_load = guarded(function (self)
	local rw = mod.rw
	local slot = self:_current_preset_slot()

	if not slot.preset then
		self:_refresh_preset(mod:localize("preset_nothing_to_load"))

		return
	end

	local backup = rw.presets.capture(get_setting, rw.events, rw.groups)

	backup.name = mod:localize("preset_undo_name")
	rw.presets.write(set_setting, rw.presets.UNDO_ID, backup)

	local written = rw.presets.apply(slot.preset, set_setting, rw.events, rw.groups)

	self:_reload()
	self:_refresh_preset(mod:localize("preset_loaded", slot.name, written))
end)

RealmsWavesView.cb_preset_undo = guarded(function (self)
	local rw = mod.rw
	local backup = rw.presets.read(get_setting, rw.presets.UNDO_ID, rw.events, rw.groups)

	if not backup then
		self:_refresh_preset(mod:localize("preset_nothing_to_undo"))

		return
	end

	rw.presets.apply(backup, set_setting, rw.events, rw.groups)
	rw.presets.clear(set_setting, rw.presets.UNDO_ID)
	self:_reload()
	self:_refresh_preset(mod:localize("preset_undone"))
end)

RealmsWavesView.cb_preset_rename = guarded(function (self)
	local rw = mod.rw
	local slot = self:_current_preset_slot()

	if not slot.preset then
		self:_refresh_preset(mod:localize("preset_save_first"))

		return
	end

	Popup.open(self, {
		label = mod:localize("popup_preset_rename_title", self._preset_index),
		value = slot.preset.name,
		max_length = rw.presets.MAX_NAME,
		set = function (text)
			local name = rw.presets.clean_name(text)

			if name ~= "" then
				slot.preset.name = name
				rw.presets.write(set_setting, rw.presets.slot_id(self._preset_index), slot.preset)
				self:_refresh_preset(nil)
			end
		end,
	})
end)

-- Shows the preset as one line of text (also copied to the clipboard when the game lets us) to send to a friend.
RealmsWavesView.cb_preset_export = guarded(function (self)
	local rw = mod.rw
	local slot = self:_current_preset_slot()

	if not slot.preset then
		self:_refresh_preset(mod:localize("preset_nothing_to_export"))

		return
	end

	local text = rw.presets.encode(slot.preset)
	local copied = clipboard_put(text)

	Popup.open(self, {
		label = mod:localize("popup_export_title", slot.name),
		hint = mod:localize(copied and "popup_export_hint_copied" or "popup_export_hint"),
		value = text,
		max_length = #text + 16,
		set = function () end,
	})
end)

-- Pastes a friend's preset into the open slot (replacing what is there). If the clipboard already holds a
-- preset it is filled in, so it is one click on OK.
RealmsWavesView.cb_preset_import = guarded(function (self)
	local rw = mod.rw
	local clip = clipboard_get()
	local prefilled = clip ~= nil and clip:match("^%s*" .. rw.presets.PREFIX .. "|") ~= nil

	Popup.open(self, {
		label = mod:localize("popup_import_title", self._preset_index),
		hint = mod:localize(prefilled and "popup_import_hint_filled" or "popup_import_hint", self._preset_index),
		value = prefilled and clip or "",
		max_length = 30000,
		always_commit = true, -- a prefilled box is unchanged text, OK must still import it
		validate = function (text)
			local preset, err = rw.presets.decode(text, rw.events, rw.groups)

			return preset ~= nil, err
		end,
		set = function (text)
			local preset = rw.presets.decode(text, rw.events, rw.groups)

			if preset then
				rw.presets.write(set_setting, rw.presets.slot_id(self._preset_index), preset)
				self:_refresh_preset(mod:localize(preset.skipped > 0 and "preset_imported_skipped" or "preset_imported", preset.name, #preset.waves, preset.skipped))
			end
		end,
	})
end)

RealmsWavesView.cb_preset_clear = guarded(function (self)
	local rw = mod.rw

	rw.presets.clear(set_setting, rw.presets.slot_id(self._preset_index))
	self:_refresh_preset(mod:localize("preset_cleared"))
end)

-- sharing one wave -------------------------------------------------------------
-- Same text idea as the presets, for a single wave: "RWW1|...|check".

-- Share (detail screen): shows this wave as text (and copies it). Pasting a friend's wave over the text and
-- pressing OK replaces THIS wave with it.
RealmsWavesView.cb_wave_share = guarded(function (self)
	local rw = mod.rw
	local key = self._key
	local snapshot = rw.presets.capture_wave(get_setting, key, rw.events, rw.groups)

	if not snapshot then
		return
	end

	local text = rw.presets.encode_wave(snapshot)
	local copied = clipboard_put(text)

	Popup.open(self, {
		label = mod:localize("popup_share_title", self._wave.name),
		hint = mod:localize(copied and "popup_share_hint_copied" or "popup_share_hint"),
		value = text,
		max_length = #text + 4000,
		validate = function (pasted)
			local wave, err = rw.presets.decode_wave(pasted, rw.events, rw.groups)

			return wave ~= nil, err
		end,
		set = function (pasted)
			local wave = rw.presets.decode_wave(pasted, rw.events, rw.groups)

			if wave then
				rw.presets.apply_wave(wave, key, set_setting, rw.events, rw.groups)
				self:_reload()
				self._parts = copy_parts(self._wave.parts)
				self:_apply_screen(true)
				mod:echo("%s", mod:localize("msg_wave_replaced", self._wave.name))
			end
		end,
	})
end)

-- Import wave (list screen): a friend's wave goes into the first free custom slot, which then opens.
RealmsWavesView.cb_wave_import = guarded(function (self)
	local rw = mod.rw
	local free

	for i = 1, #self._waves do
		local wave = self._waves[i]

		if wave.is_custom and not (wave.parts and #wave.parts > 0) then
			free = wave

			break
		end
	end

	if not free then
		mod:echo("%s", mod:localize("msg_no_free_slot"))

		return
	end

	local clip = clipboard_get()
	local prefilled = clip ~= nil and clip:match("^%s*" .. rw.presets.WAVE_PREFIX .. "|") ~= nil

	Popup.open(self, {
		label = mod:localize("popup_wimport_title"),
		hint = mod:localize(prefilled and "popup_wimport_hint_filled" or "popup_wimport_hint", free.name),
		value = prefilled and clip or "",
		max_length = 30000,
		always_commit = true,
		validate = function (text)
			local wave, err = rw.presets.decode_wave(text, rw.events, rw.groups)

			return wave ~= nil, err
		end,
		set = function (text)
			local wave = rw.presets.decode_wave(text, rw.events, rw.groups)

			if wave then
				rw.presets.apply_wave(wave, free.key, set_setting, rw.events, rw.groups)
				self:_reload()
				mod:echo("%s", mod:localize("msg_wave_imported", wave.name ~= "" and wave.name or free.name, free.name))
				self:_open_detail(free.key)
			end
		end,
	})
end)

-- popup ------------------------------------------------------------------------

RealmsWavesView.cb_popup_confirm = function (self)
	Popup.commit(self)
end

RealmsWavesView.cb_popup_cancel = function (self)
	Popup.cancel(self)
end

return RealmsWavesView
