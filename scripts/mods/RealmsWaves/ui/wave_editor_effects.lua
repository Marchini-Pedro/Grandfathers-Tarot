-- The card effects in the editor (docs/12-card-effects-and-ui.md, docs/08-workshop-redesign.md).
--
-- A BENEFICIAL card (Prayer, Miracle, Grace, Faith) has no enemies: its Cauldron shows its effects instead, laid out like the
-- enemies (2026-10-04, the user's design page): one row per effect the card holds (its category's colour on the edge, the amount
-- and, for the Blue Stimm, the players as compact steppers, Remove), and under them a shelf of every effect in four groups:
-- Healing, Buffs, Items and Game Effects. A chip adds its effect, a second click takes it off. Recharge Med Station is shown
-- greyed: off for now.
--
-- The completion sound (screen "sounds"): the list of the game's events (Preview on every row plays it, Select puts it in the open
-- slot), a Search button, two slots (the second plays after the first) and a volume slider for each (catalog/sounds.lua).
local mod = get_mod("RealmsWaves")
local UIWidget = require("scripts/managers/ui/ui_widget")
local BASE = "RealmsWaves/scripts/mods/RealmsWaves"
local C = mod:io_dofile(BASE .. "/ui/wave_editor_components")
local Workshop = mod:io_dofile(BASE .. "/ui/workshop")
local WB = mod:io_dofile(BASE .. "/ui/workshop_blueprints")
local Schema = mod:io_dofile(BASE .. "/catalog/effects")
local Sounds = mod:io_dofile(BASE .. "/catalog/sounds")
local EffectsView = {}

local FX = Workshop.FX
local ROWS = Workshop.ROWS
local SND = Workshop.SOUND

-- the effects a card can hold (the hostile Blackout is a button of hostile cards, not a chip)
local BENEFITS = {}

for _, def in ipairs(Schema.ORDER) do
	if not def.hostile then
		BENEFITS[#BENEFITS + 1] = def
	end
end

EffectsView.BENEFITS = BENEFITS
-- where the chips of the beneficial shelf go (pure arithmetic, worked out by every copy of this file: the definitions and the view
-- each load it with io_dofile)
EffectsView.shelf_layout = Workshop.fx_shelf_layout(Schema.CATEGORIES, BENEFITS)

local CATEGORY_RGB = {}

for _, category in ipairs(Schema.CATEGORIES) do
	CATEGORY_RGB[category.id] = category.rgb
end

local function rect(passes, id, x, y, w, h, z, change, visible)
	passes[#passes + 1] = { pass_type = "rect", style_id = id, style = { offset = { x, y, z }, size = { w, h }, color = { 255, 255, 255, 255 } }, change_function = change, visibility_function = visible }
end

-- One effect of the card on its row (like an enemy row of the Cauldron). Content: label, info, edge_rgb, amount_value,
-- players_value, show_players.
local function effect_row(name)
	local passes = {}
	local W, H = Workshop.LEFT_W, Workshop.ROW_H
	local S = Workshop.STEPPER
	local y = (H - S.height) / 2

	rect(passes, "row_frame", 0, 0, W, H, 0, function (content, style)
		C.put_rgb(style.color, 200, C.rgb.frame)
	end)
	rect(passes, "row_background", 1, 1, W - 2, H - 2, 0.5, function (content, style)
		C.put_rgb(style.color, 255, C.theme.panel)
	end)
	rect(passes, "row_edge", 1, 1, 5, H - 2, 1, function (content, style)
		C.put_rgb(style.color, 255, content.edge_rgb or C.rgb.muted)
	end)
	C.text_pass(passes, "label", "label", { FX.name, 1, 2 }, { FX.name_w, 30 }, 25, C.colors.text)
	passes[#passes].change_function = function (content, style)
		C.put_rgb(style.text_color, 255, content.edge_rgb or C.rgb.text)
	end
	C.text_pass(passes, "info", "info", { FX.name, 29, 2 }, { FX.name_w, 17 }, 15, C.colors.muted)

	local function layout(x, value_w)
		return {
			minus_offset = { x, y, 2 },
			value_offset = { x + S.button, y, 2 },
			value_size = { value_w, S.height },
			plus_offset = { x + S.button + value_w, y, 2 },
			button_size = { S.button, S.height },
			font_size = S.font,
			sign = S.sign,
		}
	end

	C.stepper_passes(passes, layout(FX.amount, FX.amount_w), nil, { minus = "amount_minus", value = "amount_value_hotspot", plus = "amount_plus", text = "amount_value" })
	C.stepper_passes(passes, layout(FX.players, FX.players_w), "show_players", { minus = "players_minus", value = "players_value_hotspot", plus = "players_plus", text = "players_value" })
	C.text_pass(passes, "no_players", "no_players", { FX.players, 0, 2 }, { FX.players_w + 2 * S.button, H }, 20, C.colors.muted, "center")
	C.button(passes, "remove", { Workshop.COL.remove, (H - 30) / 2, 2 }, { Workshop.COL.remove_w, 30 }, { font_size = 17, role = "danger", brackets = false })

	return UIWidget.create_definition(passes, name, { label = "", info = "", edge_rgb = { 135, 135, 135 }, amount_value = "", players_value = "", no_players = "", show_players = false }, { W, H })
end

-- a volume slider of the sound screen: its label, a track with a fill and a handle, the number (a click on it opens the box)
local function slider(name)
	local passes = {}

	C.text_pass(passes, "label", "label", { 0, 0, 0 }, { SND.label_w, SND.slider_h }, 20, C.colors.text)
	rect(passes, "track", SND.track_x, SND.slider_h / 2 - 4, SND.track_w, 8, 1, function (content, style)
		C.put_rgb(style.color, 255, C.rgb.frame)
	end)
	rect(passes, "fill", SND.track_x, SND.slider_h / 2 - 4, 0, 8, 2, function (content, style)
		C.put_rgb(style.color, 255, C.accent)
	end, function (content) return content.show_fill == true end)
	rect(passes, "handle", SND.track_x - 4, SND.slider_h / 2 - 14, 8, 28, 3, function (content, style)
		C.put_rgb(style.color, 255, content.hotspot.is_hover and C.accent or C.rgb.bright)
	end)
	C.hotspot_pass(passes, "hotspot", { SND.track_x - 10, 0, 4 }, { SND.track_w + 20, SND.slider_h }, nil, true)
	C.button(passes, "number", { SND.track_x + SND.track_w + 24, (SND.slider_h - 40) / 2, 0 }, { 110, 40 }, { font_size = 20, role = "chip" })

	return UIWidget.create_definition(passes, name, { label = "", show_fill = false })
end

EffectsView.definitions = function (nodes, widgets, node)
	local LX = Workshop.LEFT_X
	local layout = EffectsView.shelf_layout

	-- the beneficial Cauldron: the header, the rows, the shelf
	nodes.fx_header = node(LX, Workshop.HEADER_Y, Workshop.LEFT_W, Workshop.HEADER_H, 2)
	widgets.fx_header = UIWidget.create_definition({
		{ value_id = "col_1", style_id = "col_1", pass_type = "text", value = "", style = { font_type = "proxima_nova_bold", font_size = 18, text_color = C.clone_color(C.colors.muted), text_horizontal_alignment = "left", text_vertical_alignment = "center", size = { 300, 28 }, offset = { FX.name, 0, 2 } } },
		{ value_id = "col_2", style_id = "col_2", pass_type = "text", value = "", style = { font_type = "proxima_nova_bold", font_size = 18, text_color = C.clone_color(C.colors.muted), text_horizontal_alignment = "center", text_vertical_alignment = "center", size = { FX.amount_w + 2 * Workshop.STEPPER.button, 28 }, offset = { FX.amount, 0, 2 } } },
		{ value_id = "col_3", style_id = "col_3", pass_type = "text", value = "", style = { font_type = "proxima_nova_bold", font_size = 18, text_color = C.clone_color(C.colors.muted), text_horizontal_alignment = "center", text_vertical_alignment = "center", size = { FX.players_w + 2 * Workshop.STEPPER.button, 28 }, offset = { FX.players, 0, 2 } } },
	}, "fx_header")

	for i = 1, ROWS do
		local name = "rw_fxrow_" .. i

		nodes[name] = node(LX, Workshop.row_y(i), Workshop.LEFT_W, Workshop.ROW_H, 1)
		widgets[name] = effect_row(name)
	end

	nodes.fx_shelf = node(LX, Workshop.SHELF_Y, Workshop.LEFT_W, layout.height, 0)
	widgets.fx_shelf = WB.shelf_panel("fx_shelf", layout, 860)

	for i, chip in ipairs(layout.chips) do
		local name = "rw_fxchip_" .. i

		nodes[name] = node(LX + chip.x, Workshop.SHELF_Y + chip.y, chip.w, Workshop.CHIP_H, 3)
		widgets[name] = WB.shelf_chip(name, chip.w, true)
	end

	-- the buttons under the card (Completion sound, Blackout) and the Deck's Search
	for _, button in ipairs({ { "rw_sound", 1290, 958, 255, "Completion sound" }, { "rw_blackout", 1560, 958, 255, "Blackout" }, { "rw_deck_search", 325, 800, 300, "Search cards" } }) do
		local name, passes = button[1], {}

		nodes[name] = node(button[2], button[3], button[4], 44, 4)
		C.button(passes, "hotspot", { 0, 0, 0 }, { button[4], 44 }, { label = button[5], font_size = 20 })
		widgets[name] = UIWidget.create_definition(passes, name)
	end

	-- the sound screen: the two slots, Remove the second, Search, and the two volume sliders
	for _, button in ipairs({
		{ "rw_snd_slot1", SND.slot1_x, SND.slots_y, SND.slot_w, "tab" },
		{ "rw_snd_slot2", SND.slot2_x, SND.slots_y, SND.slot_w, "tab" },
		{ "rw_snd_remove2", SND.remove_x, SND.slots_y, SND.remove_w, "danger" },
		{ "rw_snd_search", SND.search_x, SND.slots_y, SND.search_w, "primary" },
	}) do
		local name, passes = button[1], {}

		nodes[name] = node(button[2], button[3], button[4], SND.slots_h, 4)
		C.button(passes, "hotspot", { 0, 0, 0 }, { button[4], SND.slots_h }, { label = "", font_size = 19, role = button[5] })
		widgets[name] = UIWidget.create_definition(passes, name)
	end

	for i = 1, Sounds.MAX_SOUNDS do
		local name = "rw_snd_vol" .. i

		nodes[name] = node(SND.slider_x, SND.slider_y[i], SND.track_x + SND.track_w + 140, SND.slider_h, 4)
		widgets[name] = slider(name)
	end
end

EffectsView.install = function (View, h)
	local function changed(self) self:_reload(); self:_apply_screen(true) end
	local function save(self, values) mod:set("fx_" .. self._key, Schema.encode(values)); changed(self) end
	local FX_ROW_HOTSPOTS = { "amount_minus", "amount_value_hotspot", "amount_plus", "players_minus", "players_value_hotspot", "players_plus", "remove" }

	-- the effects of the card in the order of the catalog: the rows
	View._fx_rows = function (self)
		local list, values = {}, self._wave and self._wave.effects or {}

		for _, def in ipairs(BENEFITS) do
			if values[def.id] then
				list[#list + 1] = def
			end
		end

		return list
	end

	View._create_effect_callbacks = function (self)
		local widgets = self._widgets_by_name

		for i = 1, ROWS do
			local content = widgets["rw_fxrow_" .. i].content

			content.amount_minus.pressed_callback = callback(self, "cb_fx_step", i, "value", -1)
			content.amount_plus.pressed_callback = callback(self, "cb_fx_step", i, "value", 1)
			content.amount_value_hotspot.pressed_callback = callback(self, "cb_fx_number", i, "value")
			content.players_minus.pressed_callback = callback(self, "cb_fx_step", i, "players", -1)
			content.players_plus.pressed_callback = callback(self, "cb_fx_step", i, "players", 1)
			content.players_value_hotspot.pressed_callback = callback(self, "cb_fx_number", i, "players")
			content.remove.pressed_callback = callback(self, "cb_fx_remove", i)
		end

		for i in ipairs(EffectsView.shelf_layout.chips) do
			widgets["rw_fxchip_" .. i].content.hotspot.pressed_callback = callback(self, "cb_fx_chip", i)
		end

		widgets.rw_sound.content.hotspot.pressed_callback = callback(self, "cb_sound_picker")
		widgets.rw_blackout.content.hotspot.pressed_callback = callback(self, "cb_blackout")
		widgets.rw_deck_search.content.hotspot.pressed_callback = callback(self, "cb_deck_search")
		widgets.rw_snd_slot1.content.hotspot.pressed_callback = callback(self, "cb_sound_slot", 1)
		widgets.rw_snd_slot2.content.hotspot.pressed_callback = callback(self, "cb_sound_slot", 2)
		widgets.rw_snd_remove2.content.hotspot.pressed_callback = callback(self, "cb_sound_remove2")
		widgets.rw_snd_search.content.hotspot.pressed_callback = callback(self, "cb_sound_search")

		for i = 1, Sounds.MAX_SOUNDS do
			widgets["rw_snd_vol" .. i].content.hotspot.pressed_callback = callback(self, "cb_sound_drag", i)
			widgets["rw_snd_vol" .. i].content.number.pressed_callback = callback(self, "cb_sound_volume", i)
		end
	end

	local function value_text(def, value)
		if def.unit == "players" then
			return value .. (value == 1 and " player" or " players")
		elseif def.unit == "charges" then
			return value .. (value == 1 and " charge" or " charges")
		end

		return value .. " " .. def.unit
	end

	local function short_sound(event)
		return event and event:match("([^/]+)$") or ""
	end

	-- the sounds of the card being edited (the drag of a slider changes them before they are saved)
	View._sound_list = function (self)
		if self._snd_list_key ~= self._key then
			self._snd_list_key, self._snd_list = self._key, nil
		end

		self._snd_list = self._snd_list or Sounds.parse(self._wave and self._wave.sound or "")

		return self._snd_list
	end

	local function save_sounds(self, list)
		self._snd_list = list
		mod:set("snd_" .. self._key, Sounds.encode(list))
		self:_reload()
		self._snd_list = Sounds.parse(self._wave and self._wave.sound or "")
		self:_apply_screen(true)
	end

	View._refresh_sound_controls = function (self)
		local widgets = self._widgets_by_name
		local on = self._screen == "sounds" and self._wave ~= nil
		local enabled = on and self._popup == nil
		local list = on and self:_sound_list() or {}
		local slot = self._snd_slot or 1

		for _, name in ipairs({ "rw_snd_slot1", "rw_snd_slot2", "rw_snd_remove2", "rw_snd_search" }) do
			widgets[name].visible = on
		end

		widgets.rw_snd_remove2.visible = on and list[2] ~= nil
		widgets.rw_snd_slot1.content.hotspot_text = "1   " .. (list[1] and short_sound(list[1].event) or mod:localize("snd_silence"))
		widgets.rw_snd_slot1.content.hotspot_on = slot == 1
		widgets.rw_snd_slot2.content.hotspot_text = "2   " .. (list[2] and short_sound(list[2].event) or (slot == 2 and mod:localize("snd_choose") or mod:localize("snd_add_second")))
		widgets.rw_snd_slot2.content.hotspot_on = slot == 2
		widgets.rw_snd_remove2.content.hotspot_text = mod:localize("snd_remove_second")
		widgets.rw_snd_search.content.hotspot_text = mod:localize("snd_search")

		for _, name in ipairs({ "rw_snd_slot1", "rw_snd_slot2", "rw_snd_remove2", "rw_snd_search" }) do
			widgets[name].content.hotspot.disabled = not (enabled and widgets[name].visible)
		end

		-- the second slot can only be filled once there is a first sound
		widgets.rw_snd_slot2.content.hotspot.disabled = widgets.rw_snd_slot2.content.hotspot.disabled or list[1] == nil

		for i = 1, Sounds.MAX_SOUNDS do
			local widget = widgets["rw_snd_vol" .. i]
			local sound = list[i]
			local volume = sound and sound.volume or 0

			widget.visible = on and sound ~= nil
			widget.content.label = mod:localize("snd_volume", i)
			widget.content.number_text = volume .. "%"
			widget.content.show_fill = volume > 0
			widget.style.fill.size[1] = SND.track_w * volume / 100
			widget.style.handle.offset[1] = SND.track_x - 4 + SND.track_w * volume / 100
			widget.content.hotspot.disabled = not (enabled and widget.visible)
			widget.content.number.disabled = widget.content.hotspot.disabled
		end

		if not on or self._popup then
			self._snd_drag = nil
		end
	end

	View._refresh_effects = function (self)
		local widgets, wave = self._widgets_by_name, self._wave
		local card = wave and (self._screen == "detail" or self._screen == "face")
		local beneficial = card and Schema.beneficial(wave.suit)
		local rows = beneficial and self._screen == "detail"
		local enabled = rows and self._popup == nil
		local list = rows and self:_fx_rows() or {}

		widgets.fx_header.visible = rows or false
		widgets.fx_shelf.visible = rows or false

		if rows then
			widgets.fx_header.content.col_1 = mod:localize("col_effect")
			widgets.fx_header.content.col_2 = mod:localize("col_amount")
			widgets.fx_header.content.col_3 = mod:localize("col_players")

			local panel = widgets.fx_shelf.content

			panel.shelf_title = string.upper(mod:localize("shelf_title"))
			panel.shelf_hint = mod:localize("fx_shelf_hint")
			panel.faction_label = ""

			for i, band in ipairs(EffectsView.shelf_layout.bands) do
				panel["band_" .. i] = string.upper(band.id)
			end
		end

		for i = 1, ROWS do
			local widget = widgets["rw_fxrow_" .. i]
			local def = list[i]
			local effect = def and wave.effects[def.id]

			widget.visible = def ~= nil

			if def then
				local content = widget.content

				-- "100%  Party health": the amount first, in the bone colour, as on the card (the design page's rows)
				local lead, colors = Schema.lead(def, effect.value), mod.rw and mod.rw.colors

				content.label = (colors and colors.markup(lead, C.rgb.text) or lead) .. "  " .. def.short
				content.info = def.category
				content.edge_rgb = CATEGORY_RGB[def.category] or C.rgb.muted
				content.amount_value = value_text(def, effect.value)
				content.show_players = def.targets == true
				content.players_value = value_text({ unit = "players" }, effect.players or 4)
				content.no_players = def.targets and "" or "-"
				content.remove_text = mod:localize("btn_remove")
			end

			for _, id in ipairs(FX_ROW_HOTSPOTS) do
				widget.content[id].disabled = not (enabled and widget.visible) or (id:find("^players") ~= nil and not (def and def.targets))
			end
		end

		for i, chip in ipairs(EffectsView.shelf_layout.chips) do
			local widget = widgets["rw_fxchip_" .. i]
			local def = chip.def

			widget.visible = rows or false
			widget.content.chip_label = Workshop.fx_chip_label(def, mod:localize("fx_off_for_now"))
			widget.content.dot_rgb = CATEGORY_RGB[def.category] or C.rgb.muted
			widget.content.tint = false
			widget.content.hotspot_on = wave ~= nil and wave.effects ~= nil and wave.effects[def.id] ~= nil
			widget.content.hotspot.disabled = not (enabled and widget.visible) or def.disabled == true
		end

		widgets.rw_sound.visible = card or false

		local sounds = card and Sounds.parse(wave.sound) or {}

		widgets.rw_sound.content.hotspot_text = #sounds == 0 and mod:localize("snd_button_silent") or mod:localize(#sounds == 1 and "snd_button_one" or "snd_button_two")
		widgets.rw_blackout.visible = card and not beneficial or false
		widgets.rw_blackout.content.hotspot_text = wave and wave.effects.blackout and ("Blackout: " .. wave.effects.blackout.value .. " s") or "Blackout: off"
		widgets.rw_deck_search.visible = self._screen == "list"
		widgets.rw_deck_search.content.hotspot_text = (self._deck_query or "") ~= "" and mod:localize("btn_search_active", self._deck_query) or mod:localize("btn_deck_search")
		widgets.rw_deck_search.content.hotspot_on = (self._deck_query or "") ~= ""

		for _, name in ipairs({ "rw_sound", "rw_blackout", "rw_deck_search" }) do widgets[name].content.hotspot.disabled = not widgets[name].visible or self._popup ~= nil end

		if beneficial and self._screen == "detail" then
			widgets.description_text.content.description_text = "Beneficial Effects: " .. wave.name .. ". Items go to players with an empty slot."
			for _, name in ipairs({ "enemy_header", "shelf_panel", "spawn_label", "btn_add", "btn_dreg", "btn_scab", "btn_keep_pick", "btn_text", "bottom_title", "rw_scroll_up", "rw_scroll_down" }) do widgets[name].visible = false end
			for i = 1, #h.definitions.shelf_layout.chips do widgets["rw_chip_" .. i].visible = false end
			for i = 1, ROWS do widgets["rw_erow_" .. i].visible = false end
			for _, name in ipairs({ "stepper_spread", "stepper_every", "stepper_for", "stepper_dmin", "stepper_dmax" }) do widgets[name].visible = false end
		end

		if card then
			widgets.btn_enemies.style.hotspot_label.font_size = beneficial and 18 or 24
			widgets.btn_enemies.content.hotspot_text = beneficial and "Beneficial Effects" or mod:localize("tab_enemies")
		end

		self:_refresh_sound_controls()
	end

	local function fx_at(self, row)
		local def = self:_fx_rows()[row]

		return def, def and self._wave.effects[def.id]
	end

	-- a chip of the shelf: the effect on the card (at its default), or off it again
	View.cb_fx_chip = h.guarded(function (self, index)
		local chip = EffectsView.shelf_layout.chips[index]

		if not self._wave or not Schema.beneficial(self._wave.suit) or not chip or chip.def.disabled then return end

		local values = self._wave.effects

		values[chip.def.id] = not values[chip.def.id] and { value = chip.def.default, players = 4 } or nil
		save(self, values)
	end)

	-- the steppers of a row: the amount in steps of 5 (percent and seconds) or 1 (players, charges), the players 1 to 4; the amount
	-- never steps below one step (Remove takes the effect off)
	View.cb_fx_step = h.guarded(function (self, row, field, delta)
		local def, effect = fx_at(self, row)

		if not def or not Schema.beneficial(self._wave.suit) then return end

		if field == "players" then
			if not def.targets then return end
			effect.players = math.max(1, math.min(4, (effect.players or 4) + delta))
		else
			local step = (def.unit == "percent" or def.unit == "seconds") and 5 or 1

			effect.value = math.max(step, math.min(def.max, effect.value + delta * step))
		end

		save(self, self._wave.effects)
	end)

	local function number(self, def, targets)
		local values = self._wave.effects
		local effect = values[def.id] or { value = def.default, players = 4 }
		h.Popup.open(self, { label = def.name .. (targets and ": players" or ": " .. def.unit), value = tostring(targets and effect.players or effect.value), numeric = true, integer = true, min = targets and 1 or 0, max = targets and 4 or def.max,
			hint = "0 disables the effect. Player targets follow a stable party order; occupied item slots are preserved.",
			set = function (value) effect[targets and "players" or "value"] = value; values[def.id] = effect; save(self, values) end })
	end

	View.cb_fx_number = h.guarded(function (self, row, field)
		local def = fx_at(self, row)

		if def and Schema.beneficial(self._wave.suit) and (field ~= "players" or def.targets) then
			number(self, def, field == "players")
		end
	end)

	View.cb_fx_remove = h.guarded(function (self, row)
		local def = fx_at(self, row)

		if def and Schema.beneficial(self._wave.suit) then
			self._wave.effects[def.id] = nil
			save(self, self._wave.effects)
		end
	end)

	View.cb_blackout = h.guarded(function (self) if self._wave and not Schema.beneficial(self._wave.suit) then number(self, Schema.definition("blackout")) end end)

	-- ------------------------------------------------------------------------------------- the completion sound
	local function search_results(self, query)
		self._sound_results = Sounds.search(query or "", self._wave, mod.rw.groups)
		table.insert(self._sound_results, 1, { event = "", score = 0 })
	end

	local function open_search(self)
		h.Popup.open(self, { label = mod:localize("snd_search_title"), value = "", max_length = 80, allow_rows = true,
			on_change = function (query) search_results(self, query); self._offset = 0; self:_refresh_rows() end,
			set = function () self:_apply_screen(true) end })
	end

	View.cb_sound_picker = h.guarded(function (self)
		if not self._wave then return end
		search_results(self, "")
		self._screen, self._offset, self._snd_slot, self._snd_list_key = "sounds", 0, 1, nil
		self:_apply_screen()
		open_search(self)
	end)

	View.cb_sound_search = h.guarded(function (self)
		if self._screen == "sounds" and self._wave then open_search(self) end
	end)

	-- Select on a row: the sound goes into the open slot (Silence clears both) and plays once; the screen stays, so the second sound
	-- and the volumes can be set
	View.cb_sound_select = h.guarded(function (self, index)
		local item = self._sound_results and self._sound_results[self._offset + index]
		if not item then return end
		if self._popup then h.Popup.cancel(self) end

		if item.event == "" then
			self._snd_slot = 1
			save_sounds(self, {})

			return
		end

		local list = self:_sound_list()
		local slot = (self._snd_slot == 2 and list[1]) and 2 or 1

		list[slot] = { event = item.event, volume = list[slot] and list[slot].volume or 100 }
		save_sounds(self, list)

		if mod.rw.effects then mod.rw.effects.preview_sound(Sounds.encode({ list[slot] })) end
	end)

	-- Preview on a row: plays the sound once, nothing is saved
	View._preview_sound_row = function (self, row)
		local item = self._sound_results and self._sound_results[self._offset + row]

		if item and item.event ~= "" and mod.rw.effects then
			mod.rw.effects.preview_sound(item.event)
		end
	end

	View.cb_sound_slot = h.guarded(function (self, slot)
		if self._screen ~= "sounds" then return end
		if slot == 2 and not self:_sound_list()[1] then return end
		self._snd_slot = slot
		self:_apply_screen(true)
	end)

	View.cb_sound_remove2 = h.guarded(function (self)
		local list = self:_sound_list()

		if self._screen == "sounds" and list[2] then
			list[2] = nil
			self._snd_slot = 1
			save_sounds(self, list)
		end
	end)

	View.cb_sound_drag = h.guarded(function (self, slot)
		if self._screen == "sounds" and self:_sound_list()[slot] then self._snd_drag = slot end
	end)

	View.cb_sound_volume = h.guarded(function (self, slot)
		local list = self:_sound_list()

		if self._screen ~= "sounds" or not list[slot] then return end

		h.Popup.open(self, { label = mod:localize("snd_volume", slot), value = tostring(list[slot].volume), numeric = true, integer = true, min = 0, max = 100,
			hint = mod:localize("snd_volume_hint"),
			set = function (value) list[slot].volume = value; save_sounds(self, list) end })
	end)

	-- every frame on the sound screen: a slider being dragged follows the pointer; on release the volume is saved and played
	View._update_sound = function (self, input)
		local slot = self._snd_drag

		if not slot then return end
		if self._screen ~= "sounds" or self._popup then self._snd_drag = nil; return end

		local list = self:_sound_list()
		local x = self:_cursor_point(input)

		if x and list[slot] then
			list[slot].volume = math.max(0, math.min(100, math.floor((x - SND.slider_x - SND.track_x) / SND.track_w * 100 + 0.5)))
			self:_refresh_sound_controls()
		end

		if not input:get("left_hold") then
			self._snd_drag = nil
			save_sounds(self, list)

			if list[slot] and mod.rw.effects then mod.rw.effects.preview_sound(Sounds.encode({ list[slot] })) end
		end
	end

	-- The Deck's Search (2026-10-04: in place of Consecrate 12 cards): the Deck shows only the cards whose name, suit, enemies or
	-- effects hold the typed text, as it is typed. Escape puts the search back as it was; an empty search shows every card.
	View._set_deck_query = function (self, query)
		self._deck_query = query or ""
		self:_build_deck()
		self._offset = 0
		self:_apply_screen(true)
	end

	View.cb_deck_search = h.guarded(function (self)
		if self._screen ~= "list" then return end

		local before = self._deck_query or ""

		h.Popup.open(self, { label = mod:localize("deck_search_title"), value = before, max_length = 40, allow_rows = true, hint = mod:localize("deck_search_hint"),
			on_change = function (query) self:_set_deck_query(query) end,
			on_cancel = function () self:_set_deck_query(before) end,
			set = function (query) self:_set_deck_query(query) end })
	end)
end
return EffectsView
