-- The card face (the card builder): the screen "face", opened from a card's own screen with "Card face". It sets what is
-- on the card besides its enemies: the suit (with a suggestion made from the enemies), the threat (worked out from the
-- enemies, or set by hand), the whisper, the look of its cooldown and the cooldown itself, and shows a live preview of the
-- tile next to "Threat N by the numbers". Everything is written straight to the card's settings (su_, th_, wh_, cl_, cd_,
-- see catalog/events.lua) like the rest of the editor. The rows are the editor's ordinary row blueprint; installed on the
-- view with `install` (see wave_editor_view.lua).
local mod = get_mod("RealmsWaves")

local FaceView = {}

FaceView.install = function (View, h)
	local guarded, set_setting, Popup, Components = h.guarded, h.set_setting, h.Popup, h.Components
	local COOLDOWN_STEP = 30

	-- the cooldown can be as long as the "Longest cooldown" option (minutes) says, 10 minutes by default
	local function longest_cooldown()
		return math.max(2, tonumber(mod:get("tarot_longest")) or 10) * 60
	end

	local function key_of(self)
		return self._wave and self._wave.key
	end

	-- the rows of the screen: the six suits, then threat, whisper, look and cooldown (ten: one page)
	View._reload_face = function (self)
		local rows = {}

		for _, suit in ipairs(mod.rw.cards.SUIT_ORDER) do
			rows[#rows + 1] = { kind = "suit", id = suit }
		end

		rows[#rows + 1] = { kind = "threat" }
		rows[#rows + 1] = { kind = "whisper" }
		rows[#rows + 1] = { kind = "look" }
		rows[#rows + 1] = { kind = "cooldown" }

		self._face_rows = rows
	end

	-- "Threat 3 by the numbers: 24 enemies give 2, elites +1." (and the override, and the suggested suit)
	View._face_numbers_text = function (self)
		local rw = mod.rw
		local Cards, wave = rw.cards, self._wave
		local parts = wave.parts or {}
		local value, pieces = Cards.threat_auto(parts, rw.groups)
		local text = mod:localize("face_numbers", value, pieces.count, pieces.base)

		if pieces.elite then
			text = text .. mod:localize("face_elites")
		end

		if pieces.special then
			text = text .. mod:localize("face_specials")
		end

		if pieces.boss then
			text = text .. mod:localize("face_boss")
		end

		text = text .. "."

		if (wave.threat_override or 0) > 0 then
			text = text .. " " .. mod:localize("face_override", wave.threat_override)
		end

		local suggested = Cards.suggest_suit(parts, rw.groups)

		if suggested and suggested ~= Cards.normalize_suit(wave.suit) then
			text = text .. " " .. mod:localize("face_suggest", Cards.SUITS[suggested].name)
		end

		return text
	end

	local LOOK_KEY = { rot = "look_rot", whisper = "look_whisper", vial = "look_vial" }

	-- Fills one row of the screen (called by _refresh_rows); returns the colour of the row's name.
	View._face_row = function (self, item, content)
		local rw = mod.rw
		local Cards, wave = rw.cards, self._wave
		local suit_id = Cards.normalize_suit(wave.suit)

		content.show_check, content.show_stepper, content.show_share, content.show_action, content.show_mods, content.show_rep = false, false, false, false, false, false
		content.checkbox_selected = false

		if item.kind == "suit" then
			local suit = Cards.SUITS[item.id]
			local suggested = Cards.suggest_suit(wave.parts or {}, rw.groups) == item.id

			content.row_name = suit.name
			content.info = mod:localize("suit_desc_" .. item.id) .. (suggested and (" " .. mod:localize("face_suggested")) or "")
			content.show_check = true
			content.checkbox_selected = item.id == suit_id

			return { 255, suit.accent[1], suit.accent[2], suit.accent[3] }
		elseif item.kind == "threat" then
			local override = tonumber(wave.threat_override) or 0

			content.row_name = mod:localize("face_threat")
			content.show_stepper = true
			content.stepper_value = override > 0 and tostring(override) or mod:localize("val_auto")
			content.info = mod:localize(override > 0 and "face_threat_own" or "face_threat_auto")
		elseif item.kind == "whisper" then
			local own = rw.cards.clean_whisper(wave.whisper)

			content.row_name = mod:localize("face_whisper")
			content.info = own ~= "" and ("\"" .. own .. "\"") or mod:localize("face_whisper_suit", Cards.SUITS[suit_id].whisper)
			content.show_action = true
			content.hotspot_action_text = mod:localize("btn_change")
		elseif item.kind == "look" then
			local explicit = Cards.normalize_look(wave.look)

			content.row_name = mod:localize("face_look")
			content.info = explicit and mod:localize(LOOK_KEY[explicit]) or mod:localize("face_look_auto", mod:localize(LOOK_KEY[Cards.look({ suit = suit_id })]))
			content.show_action = true
			content.hotspot_action_text = mod:localize("btn_change")
		else
			content.row_name = mod:localize("face_cooldown")
			content.show_stepper = true
			content.stepper_value = tostring(math.floor(wave.cooldown))
			content.info = mod:localize("face_cooldown_info", math.floor(longest_cooldown() / 60))
		end

		return Components.colors.text
	end

	-- the live preview: the tile of this card, as the Deck shows it (not clickable)
	View._paint_preview = function (self)
		local widget = self._widgets_by_name.rw_tile_preview

		if widget then
			widget.visible = true
			self._tile_shape = self._tile_shape or h.Spread.new_shape(h.Spread.ICON_TRIS, h.Spread.ICON_CIRCS)
			self:_paint_tile(widget, self._wave)
		end
	end

	local function changed(self)
		self:_reload()
		self:_apply_screen(true)
	end

	-- a click on a suit row (the check box or the name) chooses that suit
	View._face_click = function (self, row)
		local item = self:_item_at(row)

		if item and item.kind == "suit" then
			set_setting("su_" .. key_of(self), item.id)
			changed(self)
		elseif item and item.kind == "whisper" then
			self:_face_action(row)
		elseif item and item.kind == "look" then
			self:_face_action(row)
		end
	end

	-- the buttons of the whisper row (a text box) and the look row (the next look)
	View._face_action = function (self, row)
		local item = self:_item_at(row)
		local Cards = mod.rw.cards

		if not item then
			return
		end

		if item.kind == "whisper" then
			local key = key_of(self)

			Popup.open(self, {
				label = mod:localize("popup_whisper_title", self._wave.name),
				value = Cards.clean_whisper(self._wave.whisper),
				max_length = Cards.MAX_WHISPER,
				hint = mod:localize("popup_whisper_hint"),
				set = function (text)
					set_setting("wh_" .. key, Cards.clean_whisper(text))
					changed(self)
				end,
			})
		elseif item.kind == "look" then
			-- automatic (the suit decides) -> rot -> whisper -> vial -> automatic
			local order = { "", "rot", "whisper", "vial" }
			local current = Cards.normalize_look(self._wave.look) or ""
			local at = 1

			for i = 1, #order do
				if order[i] == current then
					at = i
				end
			end

			set_setting("cl_" .. key_of(self), order[at % #order + 1])
			changed(self)
		end
	end

	-- the - and + of the threat row (automatic, 1 to 5) and of the cooldown row (30 s steps)
	View._face_step = function (self, item, delta)
		local key = key_of(self)

		if item.kind == "threat" then
			local value = math.max(0, math.min(5, (tonumber(self._wave.threat_override) or 0) + delta))

			set_setting("th_" .. key, value)
			changed(self)
		elseif item.kind == "cooldown" then
			local value = math.floor(self._wave.cooldown / COOLDOWN_STEP + 0.5) * COOLDOWN_STEP + delta * COOLDOWN_STEP

			set_setting("cd_" .. key, math.max(COOLDOWN_STEP, math.min(longest_cooldown(), value)))
			changed(self)
		end
	end

	-- a click on the value of the threat or cooldown row opens a number box
	View._face_value = function (self, item)
		local key = key_of(self)

		if item.kind == "threat" then
			Popup.open(self, {
				label = mod:localize("popup_threat_title", self._wave.name),
				value = tostring(math.floor(tonumber(self._wave.threat_override) or 0)),
				numeric = true, min = 0, max = 5, integer = true,
				hint = mod:localize("popup_threat_hint"),
				set = function (value)
					set_setting("th_" .. key, value)
					changed(self)
				end,
			})
		elseif item.kind == "cooldown" then
			Popup.open(self, {
				label = mod:localize("popup_cooldown_title", self._wave.name),
				value = tostring(math.floor(self._wave.cooldown)),
				numeric = true, min = COOLDOWN_STEP, max = longest_cooldown(), integer = true,
				set = function (value)
					set_setting("cd_" .. key, value)
					changed(self)
				end,
			})
		end
	end

	-- the "Card face" button of a card's own screen
	View.cb_face = guarded(function (self)
		if self._screen == "detail" and self._wave then
			self:_reload_face()
			self._screen = "face"
			self:_apply_screen()
		end
	end)
end

return FaceView
