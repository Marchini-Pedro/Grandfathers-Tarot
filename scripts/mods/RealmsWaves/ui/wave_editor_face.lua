-- The card face (the Mirror, docs/08-workshop-redesign.md): the screen "face", opened from a card's own screen with the Face tab.
-- It sets what is on the card besides its enemies: the suit (with a suggestion made from the enemies), the threat (worked out
-- from the enemies, or set by hand), the whisper, the look of its cooldown and the cooldown itself, with the card on its stage
-- on the right (the same as the Cauldron's). Everything is written straight to the card's settings (su_, th_, wh_, cl_, cd_,
-- see catalog/events.lua) like the rest of the editor. What is painted is in ui/wave_editor_workshop.lua (_refresh_mirror),
-- here are the callbacks of its own buttons (the suit plates, the threat diamonds and the preview are the Cauldron's, shared).
-- Installed on the view with `install` (see wave_editor_view.lua).
local mod = get_mod("RealmsWaves")

local FaceView = {}

FaceView.install = function (View, h)
	local guarded, set_setting, Popup = h.guarded, h.set_setting, h.Popup
	local COOLDOWN_STEP = 30
	local LOOKS = h.definitions.MIRROR_LOOKS -- the three looks in the order of the plates

	-- the cooldown can be as long as the "Longest cooldown" option (minutes) says, 10 minutes by default
	View._longest_cooldown = function (self)
		return math.max(2, tonumber(mod:get("tarot_longest")) or 10) * 60
	end

	local function key_of(self)
		return self._wave and self._wave.key
	end

	-- "Threat 3 by the numbers: 24 enemies give 2, elites +1." (and the override, and the suggested suit)
	View._face_numbers_text = function (self)
		local rw = mod.rw
		local Cards, wave = rw.cards, self._wave
		if Cards.suit(wave.suit).beneficial then return "Blessing strength: " .. Cards.threat(wave.parts, wave.threat_override, rw.groups) .. ". Set the pips at any time." end
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

	local function changed(self)
		self:_reload()
		self:_apply_screen(true)
	end

	-- Change (or a click on the field): a box for the whisper. The card on the stage shows what is typed as it is typed; Cancel
	-- or Esc puts the old line back.
	View.cb_whisper_change = guarded(function (self)
		local Cards = mod.rw.cards
		local key = key_of(self)
		local original = Cards.clean_whisper(self._wave.whisper)
		local raw = mod:get("wh_" .. key) -- what Cancel puts back (nothing at all when the card had no line of its own)

		Popup.open(self, {
			label = mod:localize("popup_whisper_title", self._wave.name),
			value = original,
			max_length = Cards.MAX_WHISPER,
			hint = mod:localize("popup_whisper_hint"),
			on_change = function (text)
				set_setting("wh_" .. key, Cards.clean_whisper(text))
				changed(self)
			end,
			on_cancel = function ()
				set_setting("wh_" .. key, raw)
				changed(self)
			end,
			set = function (text)
				set_setting("wh_" .. key, Cards.clean_whisper(text))
				changed(self)
			end,
		})
	end)

	-- Use the suit's line: the card's own whisper is cleared
	View.cb_whisper_suit = guarded(function (self)
		set_setting("wh_" .. key_of(self), "")
		changed(self)
	end)

	-- a plate of the cooldown looks: that look, chosen for this card
	View.cb_look_pick = guarded(function (self, index)
		if self._screen == "face" and LOOKS[index] then
			set_setting("cl_" .. key_of(self), LOOKS[index])
			changed(self)
		end
	end)

	-- Automatic for this suit: the suit decides the look (rot and renewal, the murmur returns for Murmur)
	View.cb_look_auto = guarded(function (self)
		if self._screen == "face" then
			set_setting("cl_" .. key_of(self), "")
			changed(self)
		end
	end)

	-- the cooldown stepper (30 s steps, between 30 s and the longest cooldown option) and its number box
	View.cb_cooldown_step = guarded(function (self, delta)
		set_setting("cd_" .. key_of(self), h.Deck.cooldown_after(self._wave.cooldown, delta, self:_longest_cooldown()))
		changed(self)
	end)

	View.cb_cooldown_input = guarded(function (self)
		local key = key_of(self)

		Popup.open(self, {
			label = mod:localize("popup_cooldown_title", self._wave.name),
			value = tostring(math.floor(self._wave.cooldown)),
			numeric = true, min = COOLDOWN_STEP, max = self:_longest_cooldown(), integer = true,
			set = function (value)
				set_setting("cd_" .. key, value)
				changed(self)
			end,
		})
	end)

	-- Reset face: the suit, the threat, the whisper, the look and the cooldown of this card back to their defaults (its enemies stay)
	View.cb_face_reset = guarded(function (self)
		if self._screen == "face" then
			mod.rw.events.reset_face(set_setting, key_of(self))
			changed(self)
		end
	end)

	-- the Face tab of a card's own screen (and the quiet button under the card)
	View.cb_face = guarded(function (self)
		if self._screen == "detail" and self._wave then
			self._screen = "face"
			self:_apply_screen()
		end
	end)
end

return FaceView
