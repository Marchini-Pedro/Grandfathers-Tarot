local mod = get_mod("RealmsWaves")
local UIWidget = require("scripts/managers/ui/ui_widget")
local BASE = "RealmsWaves/scripts/mods/RealmsWaves"
local C = mod:io_dofile(BASE .. "/ui/wave_editor_components")
local Schema = mod:io_dofile(BASE .. "/catalog/effects")
local Sounds = mod:io_dofile(BASE .. "/catalog/sounds")
local EffectsView = {}
EffectsView.definitions = function (nodes, widgets, node)
	for i, def in ipairs(Schema.ORDER) do
		local name, passes = "rw_effect_" .. i, {}
		nodes[name] = node(105, 164 + (i - 1) * 62, 1135, 54, 4)
		C.checkbox_passes(passes, { 8, 12, 2 }, { 28, 28 }, nil, "check", "selected", "toggle")
		C.hotspot_pass(passes, "toggle", { 0, 0, 4 }, { 720, 54 })
		C.text_pass(passes, "label", "label", { 52, 0, 2 }, { 660, 54 }, 23, C.colors.text)
		C.button(passes, "amount", { 740, 5, 2 }, { 220, 44 }, { font_size = 20, role = "chip" })
		C.button(passes, "players", { 975, 5, 2 }, { 160, 44 }, { font_size = 19, role = "chip", flag = "targets" })
		widgets[name] = UIWidget.create_definition(passes, name, { label = def.name, selected = false })
	end
	for _, button in ipairs({ { "rw_sound", 1290, 958, 255, "Completion sound" }, { "rw_blackout", 1560, 958, 255, "Blackout" }, { "rw_bless_deck", 325, 800, 300, "Consecrate 12 cards" } }) do
		local name, passes = button[1], {}
		nodes[name] = node(button[2], button[3], button[4], 44, 4)
		C.button(passes, "hotspot", { 0, 0, 0 }, { button[4], 44 }, { label = button[5], font_size = 20 })
		widgets[name] = UIWidget.create_definition(passes, name)
	end
end
EffectsView.install = function (View, h)
	local function changed(self) self:_reload(); self:_apply_screen(true) end
	local function save(self, values) mod:set("fx_" .. self._key, Schema.encode(values)); changed(self) end
	View._create_effect_callbacks = function (self)
		local widgets = self._widgets_by_name
		for i in ipairs(Schema.ORDER) do
			local content = widgets["rw_effect_" .. i].content
			content.toggle.pressed_callback = callback(self, "cb_effect_toggle", i)
			content.amount.pressed_callback = callback(self, "cb_effect_amount", i)
			content.players.pressed_callback = callback(self, "cb_effect_players", i)
		end
		widgets.rw_sound.content.hotspot.pressed_callback = callback(self, "cb_sound_picker")
		widgets.rw_blackout.content.hotspot.pressed_callback = callback(self, "cb_blackout")
		widgets.rw_bless_deck.content.hotspot.pressed_callback = callback(self, "cb_bless_deck")
	end
	View._refresh_effects = function (self)
		local widgets, wave = self._widgets_by_name, self._wave
		local card = wave and (self._screen == "detail" or self._screen == "face")
		local beneficial = card and Schema.beneficial(wave.suit)
		for i, def in ipairs(Schema.ORDER) do
			local widget = widgets["rw_effect_" .. i]
			widget.visible = beneficial and self._screen == "detail" and not def.hostile or false
			local effect = wave and wave.effects and wave.effects[def.id]
			widget.content.selected = effect ~= nil
			widget.content.targets = def.targets == true
			widget.content.amount_text = (effect and effect.value or def.default) .. " " .. def.unit
			widget.content.players_text = (effect and effect.players or 4) .. " players"
			for _, id in ipairs({ "toggle", "amount", "players" }) do widget.content[id].disabled = not widget.visible or self._popup ~= nil or (id == "players" and not def.targets) end
		end
		widgets.rw_sound.visible = card or false
		widgets.rw_sound.content.hotspot_text = wave and wave.sound ~= "" and "Sound: selected" or "Sound: silent"
		widgets.rw_blackout.visible = card and not beneficial or false
		widgets.rw_blackout.content.hotspot_text = wave and wave.effects.blackout and ("Blackout: " .. wave.effects.blackout.value .. " s") or "Blackout: off"
		widgets.rw_bless_deck.visible = self._screen == "list"
		for _, name in ipairs({ "rw_sound", "rw_blackout", "rw_bless_deck" }) do widgets[name].content.hotspot.disabled = not widgets[name].visible or self._popup ~= nil end
		if beneficial and self._screen == "detail" then
			widgets.description_text.content.description_text = "Beneficial Effects: " .. wave.name .. ". Items go to players with an empty slot."
			for _, name in ipairs({ "enemy_header", "shelf_panel", "spawn_label", "btn_add", "btn_dreg", "btn_scab", "btn_keep_pick", "btn_text", "bottom_title", "rw_scroll_up", "rw_scroll_down" }) do widgets[name].visible = false end
			for i = 1, #h.definitions.shelf_layout.chips do widgets["rw_chip_" .. i].visible = false end
			for i = 1, 6 do widgets["rw_erow_" .. i].visible = false end
			for _, name in ipairs({ "stepper_spread", "stepper_every", "stepper_for", "stepper_dmin", "stepper_dmax" }) do widgets[name].visible = false end
		end
		if card then
			widgets.btn_enemies.style.hotspot_label.font_size = beneficial and 18 or 24
			widgets.btn_enemies.content.hotspot_text = beneficial and "Beneficial Effects" or mod:localize("tab_enemies")
			widgets.btn_thr_auto.visible, widgets.btn_thr_hand.visible = false, false
		end
	end
	View.cb_effect_toggle = h.guarded(function (self, index)
		if not self._wave or not Schema.beneficial(self._wave.suit) then return end
		local def, values = Schema.ORDER[index], self._wave.effects
		if not def or def.hostile then return end
		values[def.id] = not values[def.id] and { value = def.default, players = 4 } or nil
		save(self, values)
	end)
	local function number(self, def, targets)
		local values = self._wave.effects
		local effect = values[def.id] or { value = def.default, players = 4 }
		h.Popup.open(self, { label = def.name .. (targets and ": players" or ": " .. def.unit), value = tostring(targets and effect.players or effect.value), numeric = true, integer = true, min = targets and 1 or 0, max = targets and 4 or def.max,
			hint = "0 disables the effect. Player targets follow a stable party order; occupied item slots are preserved.",
			set = function (value) effect[targets and "players" or "value"] = value; values[def.id] = effect; save(self, values) end })
	end
	View.cb_effect_amount = h.guarded(function (self, index) if self._wave and Schema.beneficial(self._wave.suit) then number(self, Schema.ORDER[index]) end end)
	View.cb_effect_players = h.guarded(function (self, index) if self._wave and Schema.beneficial(self._wave.suit) then number(self, Schema.ORDER[index], true) end end)
	View.cb_blackout = h.guarded(function (self) if self._wave and not Schema.beneficial(self._wave.suit) then number(self, Schema.definition("blackout")) end end)
	View.cb_sound_picker = h.guarded(function (self)
		if not self._wave then return end
		self._sound_results = Sounds.search("", self._wave, mod.rw.groups)
		table.insert(self._sound_results, 1, { event = "", score = 0 })
		self._screen, self._offset = "sounds", 0
		self:_apply_screen()
		h.Popup.open(self, { label = "Search completion sounds", value = "", max_length = 80, allow_rows = true,
			on_change = function (query) self._sound_results = Sounds.search(query, self._wave, mod.rw.groups); table.insert(self._sound_results, 1, { event = "", score = 0 }); self._offset = 0; self:_refresh_rows() end,
			set = function () self:_apply_screen(true) end })
	end)
	View.cb_sound_select = h.guarded(function (self, index)
		local item = self._sound_results and self._sound_results[self._offset + index]
		if not item then return end
		if self._popup then h.Popup.cancel(self) end
		mod:set("snd_" .. self._key, item.event)
		if mod.rw.effects then mod.rw.effects.preview_sound(item.event) end
		self._screen = "face"
		changed(self)
	end)
	View.cb_bless_deck = h.guarded(function (self)
		h.Popup.open(self, { label = "Consecrate the 12 standard cards?", value = "", hint = "Replaces their enemies with Prayer, Miracle and Grace effects. The current deck is saved as Presets Undo. Type CONSECRATE to apply.", max_length = 10,
			validate = function (text) return text == "CONSECRATE", "Type CONSECRATE" end,
			set = function ()
				local rw = mod.rw
				local before = rw.presets.capture(function (id) return mod:get(id) end, rw.events, rw.groups)
				mod:set(rw.presets.UNDO_ID, rw.presets.encode(before))
				local suits, effects = { "prayer", "miracle", "grace" }, { "blue_stimm", "cleanse", "cooldown" }
				for i, standard in ipairs(rw.events.STANDARD) do
					local n = (i - 1) % 3 + 1
					rw.events.set_def(function (id, value) mod:set(id, value) end, standard.key, suits[n]:gsub("^%l", string.upper) .. " " .. math.ceil(i / 3), {}, rw.groups)
					mod:set("su_" .. standard.key, suits[n]); mod:set("th_" .. standard.key, 1); mod:set("del_" .. standard.key, false)
					mod:set("fx_" .. standard.key, effects[n] .. "=" .. (n == 1 and 15 or 100) .. ":4")
				end
				changed(self)
			end })
	end)
end
return EffectsView
