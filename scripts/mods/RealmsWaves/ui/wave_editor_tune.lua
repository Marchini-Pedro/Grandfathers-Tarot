-- Custom mods of one enemy group (the screen "tune"), opened with the "Custom" button of a row in a card's own screen,
-- beside "Mods". Seven rows (catalog/groups.lua, Groups.TUNE): health, size, run speed, melee attack speed, gunner fire
-- rate, shots per burst and hit mass, each a number in percent of the normal value (100 = unchanged) with - and +, a
-- click on the number for a number box, and Reset while it is not 100. Everything is written into the group (part.tune)
-- and saved with the card's recipe ("3 crushers{health=150 size=130}"), like the modifiers of the Mods screen. How the
-- game gets the values is in spawn/tuning.lua. The rows are the editor's ordinary row blueprint; installed on the view
-- with `install` (see wave_editor_view.lua).
local mod = get_mod("RealmsWaves")

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

	local function value_of(self, id)
		local part = part_of(self)

		return part and part.tune and part.tune[id] or 100
	end

	-- writes one value (100 removes it) and saves the card, which redraws the screen
	View._set_tune = function (self, id, value)
		local part = part_of(self)

		if not part then
			return
		end

		local tune = groups().copy_tune(part.tune) or {}

		value = groups().clamp_tune(id, value)
		tune[id] = value ~= 100 and value or nil
		part.tune = next(tune) ~= nil and tune or nil
		self:_save()
	end

	-- Fills one row (called by _refresh_rows); returns the colour of the row's name: the bile green of a changed value,
	-- the text colour of an unchanged one.
	View._tune_row = function (self, item, content)
		local value = value_of(self, item.id)
		local changed = value ~= 100

		content.row_name = mod:localize("tune_" .. item.id)
		content.info = mod:localize("tune_" .. item.id .. "_info", item.min, item.max)
		content.show_check, content.show_stepper, content.show_share, content.show_mods, content.show_rep = false, true, false, false, false
		content.show_action = changed
		content.hotspot_action_text = mod:localize("btn_tune_reset")
		content.stepper_value = tostring(value)

		return changed and Components.colors.gold or Components.colors.text
	end

	-- - and +: one step of that value (10 for health and hit mass, 25 for the burst, 5 for the rest)
	View._tune_step = function (self, item, delta)
		self:_set_tune(item.id, value_of(self, item.id) + delta * item.step)
	end

	-- a click on the number (or on the row's name): a number box, the value's own range
	View._tune_value = function (self, item)
		local part = part_of(self)

		Popup.open(self, {
			label = mod:localize("popup_tune_title", mod:localize("tune_" .. item.id), part and groups().describe_part(part) or ""),
			value = tostring(value_of(self, item.id)),
			numeric = true, min = item.min, max = item.max, integer = true,
			hint = mod:localize("popup_tune_hint", item.min, item.max),
			set = function (value)
				self:_set_tune(item.id, value)
			end,
		})
	end

	-- Reset: back to 100
	View._tune_action = function (self, item)
		self:_set_tune(item.id, 100)
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
