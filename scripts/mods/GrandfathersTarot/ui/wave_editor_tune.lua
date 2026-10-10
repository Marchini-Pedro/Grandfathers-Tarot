-- Custom mods of one enemy group (the screen "tune"), opened with the "Custom" button of a row in a card's own screen,
-- beside "Mods". Ten rows (catalog/groups.lua, Groups.TUNE; damage dealt since 2026-10-04): health, size, run speed, time between attacks, gunner fire
-- rate, shots per burst, hit mass, explosion and damage over time taken, each a number in percent of the normal value (100 = unchanged) with - and +, a
-- click on the number for a number box, and Reset while it is not 100. Everything is written into the group (part.tune)
-- and saved with the card's recipe ("3 crushers{health=150 size=130}"), like the modifiers of the Mods screen. How the
-- game gets the values is in spawn/tuning.lua. The rows are the editor's ordinary row blueprint; installed on the view
-- with `install` (see wave_editor_view.lua).
local mod = get_mod("GrandfathersTarot")

local TuneView = {}

TuneView.install = function (View, h)
	local guarded, Popup, Components = h.guarded, h.Popup, h.Components

	local function groups()
		return mod.rw.groups
	end

	-- the group being edited (the row whose Custom button was clicked)
	local function part_of(self)
		return self._parts and self._parts[self._part_index]
	end

	-- (2026-10-07) Twins: a row with the Twins modifier gets its own twins first on this screen (catalog/groups.lua part.twins,
	-- twins/twins.lua): Twin 1 and Twin 2 (- and + step through the enemies, a click types a name, Reset gives the game's own
	-- split), whether each splits again and keeps the row's mods, and the generations.
	local TWINS_ROWS = {
		{ id = "tw_a", twin_slot = "a" },
		{ id = "tw_sa", twin_flag = "sa", toggle = true },
		{ id = "tw_ka", twin_flag = "ka", toggle = true },
		{ id = "tw_b", twin_slot = "b" },
		{ id = "tw_sb", twin_flag = "sb", toggle = true },
		{ id = "tw_kb", twin_flag = "kb", toggle = true },
		{ id = "tw_gen", twin_gen = true },
	}
	local with_twins = nil

	local function twins_catalog()
		local twins = mod.rw.twins

		return twins and twins.is_installed and twins.is_installed() and twins.catalog() or nil
	end

	View._tune_rows = function (self)
		local part = self._parts and self._parts[self._part_index]

		if not (part and groups().has_twins_mod(part) and twins_catalog()) then
			return groups().TUNE_SCREEN
		end

		if not with_twins then
			with_twins = {}

			for _, row in ipairs(TWINS_ROWS) do with_twins[#with_twins + 1] = row end
			for _, row in ipairs(groups().TUNE_SCREEN) do with_twins[#with_twins + 1] = row end
		end

		return with_twins
	end

	local function twins_of(self)
		local part = self._parts and self._parts[self._part_index]
		local t = {}

		for key, value in pairs(part and part.twins or {}) do t[key] = value end

		return t, part
	end

	local function set_twins(self, t)
		local _, part = twins_of(self)

		if part then
			part.twins = groups().clean_twins(t)
			self:_save()
		end
	end

	-- the name of a twin slot's enemy: "None", the game's split ("Default: Reaper") or the enemy's name
	local function twin_name(self, choice)
		local catalog = twins_catalog()
		local _, part = twins_of(self)

		local function name_of(breed)
			local entry = catalog and catalog.by_id[breed]
			local ok, name = pcall(groups().display_name, breed)

			return ok and name and name ~= breed and name or entry and entry.name or tostring(breed)
		end

		if choice == "none" then
			return mod:localize("tw_twin_none")
		end

		if choice and choice ~= "default" then
			return name_of(choice)
		end

		local breed = part and (part.breed or (part.one_of and part.one_of[1]))
		local default = catalog and breed and catalog.default_twins[breed]

		return mod:localize("tw_row_default", default and name_of(default) or mod:localize("tw_twin_none"))
	end

	local function twin_choices()
		local catalog = twins_catalog()

		return catalog and catalog.twin_choices or { "default", "none" }
	end

	local function twin_index(choice)
		local list = twin_choices()

		for i = 1, #list do
			if list[i] == (choice or "default") then return i end
		end

		return 1
	end

	-- fills a Twins row; returns the colour of its name
	local function twins_row(self, item, content)
		local t = twins_of(self)

		content.show_share, content.show_mods, content.show_rep = false, false, false

		if item.twin_slot then
			local choice = t[item.twin_slot]

			content.row_name = mod:localize(item.id)
			content.info = twin_name(self, choice)
			content.show_check, content.show_stepper = false, true
			content.show_action = choice ~= nil
			content.hotspot_action_text = mod:localize("btn_tune_reset")
			content.stepper_value = tostring(twin_index(choice))

			return choice and Components.colors.gold or Components.colors.text
		end

		if item.twin_flag then
			content.row_name = mod:localize(item.id)
			content.info = mod:localize(item.id .. "_info")
			content.show_check, content.show_stepper, content.show_action = true, false, false
			content.checkbox_selected = t[item.twin_flag] == true
			content.stepper_value = ""

			return t[item.twin_flag] and Components.colors.gold or Components.colors.text
		end

		local gen = t.gen or 1

		content.row_name = mod:localize("tw_gen")
		content.info = mod:localize("tw_gen_info", groups().TWINS_MAX_GEN)
		content.show_check, content.show_stepper = false, true
		content.show_action = gen ~= 1
		content.hotspot_action_text = mod:localize("btn_tune_reset")
		content.stepper_value = tostring(gen)

		return gen ~= 1 and Components.colors.gold or Components.colors.text
	end

	local function is_twins_row(item)
		return item and (item.twin_slot or item.twin_flag or item.twin_gen) ~= nil
	end

	local function twins_step(self, item, delta)
		local t = twins_of(self)

		if item.twin_slot then
			local list = twin_choices()
			local i = (twin_index(t[item.twin_slot]) - 1 + delta) % #list + 1

			t[item.twin_slot] = list[i] ~= "default" and list[i] or nil
		elseif item.twin_gen then
			t.gen = math.max(1, math.min(groups().TWINS_MAX_GEN, (t.gen or 1) + delta))
		end

		set_twins(self, t)
	end

	local function twins_toggle(self, item)
		local t = twins_of(self)

		t[item.twin_flag] = not t[item.twin_flag] or nil
		set_twins(self, t)
	end

	local function twins_reset(self, item)
		local t = twins_of(self)

		if item.twin_slot then t[item.twin_slot] = nil elseif item.twin_gen then t.gen = nil end

		set_twins(self, t)
	end

	-- a click on a twin's name: type an enemy ("poxburster", "none", empty = the game's split); on Generations a number box
	local function twins_value(self, item)
		if item.twin_flag then
			twins_toggle(self, item)

			return
		end

		if item.twin_gen then
			Popup.open(self, {
				label = mod:localize("tw_gen"), value = tostring(twins_of(self).gen or 1), numeric = true, integer = true, min = 1, max = groups().TWINS_MAX_GEN,
				set = function (value)
					local t = twins_of(self)

					t.gen = value
					set_twins(self, t)
				end,
			})

			return
		end

		local current = twins_of(self)[item.twin_slot]

		-- the typed text as a slot value: nil (the game's split), "none" or a breed Twins can spawn; false and why when it is not one
		local function resolve(text)
			text = tostring(text or ""):lower():match("^%s*(.-)%s*$")

			if text == "" or text == "default" then return nil end
			if text == "none" then return "none" end

			local parts = groups().parse("1 " .. text)
			local breed = parts and #parts == 1 and parts[1].breed
			local catalog = twins_catalog()

			if not breed or not (catalog and catalog.by_id[breed]) then
				return false, mod:localize("tw_popup_unknown", text)
			end

			return breed
		end

		Popup.open(self, {
			label = mod:localize("tw_popup_title", mod:localize(item.id)),
			value = current and current ~= "none" and groups().recipe_name(current) or current or "",
			hint = mod:localize("tw_popup_hint"),
			validate = function (text)
				local value, why = resolve(text)

				if value == false then return false, why end

				return true
			end,
			set = function (text)
				local value = resolve(text)
				local t = twins_of(self)

				t[item.twin_slot] = value or nil
				set_twins(self, t)
			end,
		})
	end

	local function value_of(self, id)
		local part = part_of(self)

		return part and part.tune and part.tune[id] or groups().tune_default(id)
	end

	-- writes one value (100 removes it) and saves the card, which redraws the screen
	View._set_tune = function (self, id, value)
		local part = part_of(self)

		if not part then
			return
		end

		local tune = groups().copy_tune(part.tune) or {}

		value = groups().clamp_tune(id, value)
		tune[id] = value ~= groups().tune_default(id) and value or nil
		part.tune = next(tune) ~= nil and tune or nil
		self:_save()
	end

	-- Fills one row (called by _refresh_rows); returns the colour of the row's name: the bile green of a changed value,
	-- the text colour of an unchanged one.
	View._tune_row = function (self, item, content)
		if is_twins_row(item) then
			return twins_row(self, item, content)
		end

		local value = value_of(self, item.id)
		local changed = value ~= groups().tune_default(item.id)

		-- the Boss bar colour: the row's name in it; - and + step through the presets, a click on the name for a colour code
		if item.colour then
			local part = part_of(self)
			local hex = part and part.boss_colour
			local r, g, b = groups().hex_rgb(hex)

			content.row_name = mod:localize("tune_boss_colour")
			content.info = mod:localize("tune_boss_colour_info", groups().boss_colour_name(hex))
			content.show_check, content.show_stepper, content.show_share, content.show_mods, content.show_rep = false, true, false, false, false
			content.show_action = hex ~= nil
			content.hotspot_action_text = mod:localize("btn_tune_reset")
			content.stepper_value = tostring(groups().boss_colour_index(hex) or "#")

			return r and { 255, r, g, b } or { 255, 220, 40, 40 }
		end

		-- the Boss name: its text under the row's name, Edit on the right
		if item.text then
			local part = part_of(self)
			local name = part and part.boss_name

			content.row_name = mod:localize("tune_boss_name")
			content.info = name and mod:localize("tune_boss_name_set", name) or mod:localize("tune_boss_name_info")
			content.show_check, content.show_stepper, content.show_share, content.show_mods, content.show_rep = false, false, false, false, false
			content.show_action = true
			content.hotspot_action_text = mod:localize("btn_boss_name_edit")
			content.stepper_value = ""

			return name and Components.colors.gold or Components.colors.text
		end

		-- a toggle (the Boss bar): a checkbox, no number
		if item.toggle then
			content.row_name = mod:localize("tune_" .. item.id)
			content.info = mod:localize("tune_" .. item.id .. "_info")
			content.show_check, content.show_stepper, content.show_share, content.show_mods, content.show_rep = true, false, false, false, false
			content.show_action = false
			content.checkbox_selected = value == 1
			content.stepper_value = ""

			return changed and Components.colors.gold or Components.colors.text
		end

		content.row_name = mod:localize("tune_" .. item.id)
		content.info = mod:localize("tune_" .. item.id .. "_info", item.min, item.max)
		content.show_check, content.show_stepper, content.show_share, content.show_mods, content.show_rep = false, true, false, false, false
		content.show_action = changed
		content.hotspot_action_text = mod:localize("btn_tune_reset")
		-- a value in tenths of a second (the Net feint pause) is shown in seconds
		content.stepper_value = item.tenths and string.format("%gs", value / 10) or tostring(value)

		return changed and Components.colors.gold or Components.colors.text
	end

	-- - and +: one step of that value (10 for health and hit mass, 25 for the burst, 5 for the rest)
	View._tune_step = function (self, item, delta)
		if is_twins_row(item) then return twins_step(self, item, delta) end
		if item.text then return end

		if item.colour then
			local part = part_of(self)

			if part then
				part.boss_colour = groups().next_boss_colour(part.boss_colour, delta)
				self:_save()
			end

			return
		end

		self:_set_tune(item.id, value_of(self, item.id) + delta * item.step)
	end

	-- the Boss bar colour: a colour code box ("ff7a1a"; empty = the game's red)
	View._boss_colour_popup = function (self)
		local part = part_of(self)

		if not part then
			return
		end

		Popup.open(self, {
			label = mod:localize("popup_boss_colour_title", groups().describe_part(part)),
			value = part.boss_colour or "",
			max_length = 7,
			hint = mod:localize("popup_boss_colour_hint"),
			set = function (text)
				part.boss_colour = groups().clean_hex(text)
				self:_save()
			end,
		})
	end

	-- the Boss name: a text box (empty = the game's own name)
	View._boss_name_popup = function (self)
		local part = part_of(self)

		if not part then
			return
		end

		Popup.open(self, {
			label = mod:localize("popup_boss_name_title", groups().describe_part(part)),
			value = part.boss_name or "",
			max_length = groups().BOSS_NAME_MAX,
			hint = mod:localize("popup_boss_name_hint"),
			set = function (text)
				part.boss_name = groups().clean_boss_name(text)
				self:_save()
			end,
		})
	end

	-- a toggle row (the Boss bar): on and off
	View._tune_toggle = function (self, item)
		if item.twin_flag then return twins_toggle(self, item) end

		self:_set_tune(item.id, value_of(self, item.id) == 1 and 0 or 1)
	end

	-- a click on the number (or on the row's name): a number box, the value's own range
	View._tune_value = function (self, item)
		local part = part_of(self)

		if is_twins_row(item) then
			return twins_value(self, item)
		end

		if item.toggle then
			self:_tune_toggle(item)

			return
		end

		if item.text then
			self:_boss_name_popup()

			return
		end

		if item.colour then
			self:_boss_colour_popup()

			return
		end

		-- a value in tenths of a second: typed in seconds ("2.5")
		local scale = item.tenths and 10 or 1

		Popup.open(self, {
			label = mod:localize("popup_tune_title", mod:localize("tune_" .. item.id), part and groups().describe_part(part) or ""),
			value = item.tenths and string.format("%g", value_of(self, item.id) / 10) or tostring(value_of(self, item.id)),
			numeric = true, min = item.min / scale, max = item.max / scale, integer = not item.tenths,
			hint = item.tenths and mod:localize("popup_tune_seconds_hint", string.format("%g", item.min / scale), string.format("%g", item.max / scale)) or mod:localize("popup_tune_hint", item.min, item.max),
			set = function (value)
				self:_set_tune(item.id, value * scale)
			end,
		})
	end

	-- Reset: back to 100
	View._tune_action = function (self, item)
		if is_twins_row(item) then return twins_reset(self, item) end

		if item.text then
			self:_boss_name_popup()

			return
		end

		if item.colour then
			local part = part_of(self)

			if part then
				part.boss_colour = nil
				self:_save()
			end

			return
		end

		self:_set_tune(item.id, groups().tune_default(item.id))
	end

	-- the "Custom" button of an enemy row in a card's own screen
	View.cb_row_tune = guarded(function (self, row)
		if self._screen == "detail" and self._parts[self._offset + row] then
			self._part_index = self._offset + row
			self._screen = "tune"
			self:_apply_screen()
		end
	end)
end

return TuneView
