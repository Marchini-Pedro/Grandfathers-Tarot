-- Wave editor: lists every wave (the standard cards + the custom slots, 100 in all), shows its
-- composition, and lets you rename it, change its enemies (stepper, add,
-- remove, or edit as text), and set its chance, cooldown and enabled state.
-- Everything is written straight to DMF settings (see catalog/events.lua), so
-- changes take effect on the host's next draw; nothing needs saving.
--
-- Screens (self._screen): "list" (the Deck: the cards as tiles, ui/wave_editor_deck.lua) -> "detail" (one card: the Cauldron,
-- ui/wave_editor_workshop.lua) <-> "face" (its face: the Mirror, ui/wave_editor_face.lua and the same file) and "picker" (add an
-- enemy), "mods", "tune" (the custom mods of a group); "settings" and "presets" from the Deck.
-- Structure and vanilla widget usage follow RealmsEvent's editor view.
local mod = get_mod("GrandfathersTarot")

local BASE = "GrandfathersTarot/scripts/mods/GrandfathersTarot"
local ViewElementInputLegend = require("scripts/ui/view_elements/view_element_input_legend/view_element_input_legend")
local Components = mod:io_dofile(BASE .. "/ui/wave_editor_components")
local definitions = mod:io_dofile(BASE .. "/ui/wave_editor_definitions")
local blueprints = mod:io_dofile(BASE .. "/ui/wave_editor_blueprints")

local DeckView = mod:io_dofile(BASE .. "/ui/wave_editor_deck")
local FaceView = mod:io_dofile(BASE .. "/ui/wave_editor_face")
local TuneView = mod:io_dofile(BASE .. "/ui/wave_editor_tune")
local EffectsView = mod:io_dofile(BASE .. "/ui/wave_editor_effects")
local ColourView = mod:io_dofile(BASE .. "/ui/wave_editor_appearance")
local WorkshopView = mod:io_dofile(BASE .. "/ui/wave_editor_workshop")
local WB = mod:io_dofile(BASE .. "/ui/workshop_blueprints")
local Workshop = mod:io_dofile(BASE .. "/ui/workshop")
local Help = mod:io_dofile(BASE .. "/ui/help_text")

local Popup = Components.Popup
local Deck = blueprints.Deck
local LIST_CAPACITY = definitions.LIST_CAPACITY
local TILE_PREFIX = definitions.TILE_NODE_PREFIX
local BLANK_NAME = definitions.TILE_BLANK_NODE
local LIST_TOP = definitions.LIST_TOP
local ROW_HEIGHT = definitions.ROW_HEIGHT
local ROW_NODE_PREFIX = definitions.ROW_NODE_PREFIX

local ROW_HOTSPOTS = { "hotspot_check", "hotspot_name", "hotspot_minus", "hotspot_value", "hotspot_plus", "hotspot_action", "hotspot_mods", "hotspot_tune", "hotspot_rep_minus", "hotspot_rep_value", "hotspot_rep_plus", "hotspot_same" }
local LIST_STEPPERS = { "stepper_tmin", "stepper_tmax" } -- list screen: time between waves
-- (the cooldown moved to the card face screen, the chance sits under the card)
local DETAIL_STEPPERS = { "stepper_chance", "stepper_qcd", "stepper_spread", "stepper_every", "stepper_for", "stepper_dmin", "stepper_dmax", "stepper_timer" }
local STEPPER_WIDGETS = { "stepper_chance", "stepper_qcd", "stepper_cooldown", "stepper_spread", "stepper_every", "stepper_for", "stepper_dmin", "stepper_dmax", "stepper_timer", "stepper_tmin", "stepper_tmax" }
local STEPPER_HOTSPOTS = { "hotspot_minus", "hotspot_value", "hotspot_plus" }
-- role: "primary" (the action a screen is for), "danger" (resets and removals), nothing = standard; pip = a toggle (a diamond
-- that is lit while it is on). See Components.button.
local BUTTONS = {
	{ name = "btn_appearance", width = 400, cb = "cb_appearance" },
	{ name = "btn_back", width = 180, cb = "cb_back" },
	{ name = "btn_search", width = 420, cb = "cb_search" },
	{ name = "btn_stay", width = 380, cb = "cb_toggle_stay", pip = true },
	{ name = "btn_random", width = 310, cb = "cb_toggle_random", pip = true },
	{ name = "btn_random_done", width = 290, cb = "cb_random_done", role = "primary" },
	{ name = "btn_rename", width = 150, cb = "cb_rename" },
	{ name = "btn_text", width = 190, cb = "cb_edit_text" },
	{ name = "btn_add", width = 230, cb = "cb_add", role = "primary" },
	{ name = "btn_enabled", width = 230, cb = "cb_toggle_enabled", pip = true },
	{ name = "btn_reset", width = 230, cb = "cb_reset", role = "danger" },
	{ name = "btn_delete", width = 130, cb = "cb_delete", role = "danger" },
	{ name = "btn_enemies", width = 150, cb = "cb_enemies", role = "tab" },
	{ name = "btn_face", width = 124, cb = "cb_face", role = "tab" },
	-- the shelf's Dreg / Scab switch, the quick face's threat switch, the toolbar under the card
	{ name = "btn_dreg", width = 80, height = 36, font = 19, cb = "cb_faction", arg = "dreg", role = "tab" },
	{ name = "btn_scab", width = 80, height = 36, font = 19, cb = "cb_faction", arg = "scab", role = "tab" },
	{ name = "btn_preview", width = 283, cb = "cb_preview_cooldown" },
	-- "How it spawns": a random group rolls once for the whole wave and keeps its enemy on every repeat (shown when the card has one)
	{ name = "btn_keep_pick", width = 360, height = 30, font = 17, cb = "cb_keep_pick", pip = true },
	{ name = "btn_quickface", width = 236, height = 36, font = 17, cb = "cb_face", role = "quiet" },
	-- the switch between the twelve hostile suits and the four beneficial ones (quick face and Mirror)
	{ name = "btn_kind_hostile", width = 104, height = 32, font = 17, cb = "cb_suit_view", arg = "hostile", role = "tab" },
	{ name = "btn_kind_ben", width = 112, height = 32, font = 17, cb = "cb_suit_view", arg = "ben", role = "tab" },
	-- the Mirror (the card face screen)
	{ name = "btn_whisper_change", width = 150, cb = "cb_whisper_change" },
	{ name = "btn_whisper_suit", width = 261, height = 36, font = 17, cb = "cb_whisper_suit", role = "quiet" },
	{ name = "btn_reset_face", width = 170, cb = "cb_face_reset", role = "danger" },
	-- presets (list screen -> presets screen -> one preset)
	{ name = "btn_presets", width = 290, cb = "cb_presets" },
	{ name = "btn_settings", width = 270, cb = "cb_settings" },
	{ name = "btn_wimport", width = 300, cb = "cb_wave_import", role = "primary" },
	{ name = "btn_default", width = 320, cb = "cb_defaults", role = "danger" },
	-- the Deck: every beneficial / enemy card into or out of the draw
	{ name = "btn_draw_ben_on", width = 410, font = 19, cb = "cb_draw_kind", arg = "ben_on" },
	{ name = "btn_draw_ben_off", width = 410, font = 19, cb = "cb_draw_kind", arg = "ben_off", role = "danger" },
	{ name = "btn_draw_foe_on", width = 410, font = 19, cb = "cb_draw_kind", arg = "foe_on" },
	{ name = "btn_draw_foe_off", width = 410, font = 19, cb = "cb_draw_kind", arg = "foe_off", role = "danger" },
	-- the Deck: sort the cards (the chosen one is lit; a second click turns the order round)
	{ name = "btn_sort_threat", width = 96, font = 18, cb = "cb_sort", arg = "threat", role = "chip" },
	{ name = "btn_sort_rarity", width = 96, font = 18, cb = "cb_sort", arg = "rarity", role = "chip" },
	{ name = "btn_sort_enemies", width = 112, font = 18, cb = "cb_sort", arg = "enemies", role = "chip" },
	{ name = "btn_sort_face", width = 84, font = 18, cb = "cb_sort", arg = "face", role = "chip" },
	{ name = "btn_help", width = 50, cb = "cb_help" },
	{ name = "btn_share", width = 190, cb = "cb_wave_share" },
	{ name = "btn_pload", width = 250, cb = "cb_preset_load", role = "primary" },
	{ name = "btn_psave", width = 400, cb = "cb_preset_save" },
	{ name = "btn_prename", width = 200, cb = "cb_preset_rename" },
	{ name = "btn_pexport", width = 220, cb = "cb_preset_export" },
	{ name = "btn_pimport", width = 220, cb = "cb_preset_import" },
	{ name = "btn_pundo", width = 380, cb = "cb_preset_undo" },
	{ name = "btn_pclear", width = 260, cb = "cb_preset_clear", role = "danger" },
}
local PRESET_BUTTONS = { "btn_pload", "btn_psave", "btn_prename", "btn_pexport", "btn_pimport", "btn_pundo", "btn_pclear" }

-- The screens of a card (its enemies, the picker, Mods, Custom and its face) have their own titles and take the card's suit
-- as the accent of the buttons; the others keep "The Grandfather's Tarot" and the bile accent (docs/08).
local CARD_SCREEN_TITLE = {
	detail = "view_title_cauldron",
	picker = "view_title_cauldron",
	mods = "view_title_cauldron",
	tune = "view_title_cauldron",
	appearance = "view_title_cauldron",
	sounds = "view_title_mirror",
	face = "view_title_mirror",
}

local function get_setting(id)
	return mod:get(id)
end

local function set_setting(id, value)
	mod:set(id, value)
end

-- "Gunner" -> "Gunner  Scab" with the faction word in its colour (or plain when the enemy colours are off): which kind of
-- human enemy a row or a picker line is. Nothing is added to a Chaos unit or to a name that already says it ("Dreg Gunner").
local function with_faction(rw, breed, text)
	local suffix = breed and rw.groups.faction_suffix(breed)

	if not suffix then
		return text
	end

	local rgb = rw.colors and rw.colors.faction_rgb(rw.groups.faction(breed))

	return text .. "  " .. (rgb and rw.colors.markup(suffix, rgb) or suffix)
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
			tune = mod.rw.groups.copy_tune(part.tune),
			appearance = mod.rw.groups.Appearance.copy(part.appearance),
			-- the row's own toggle (2026-10-06): without these a click on Dogs, Shield or a Daemonhost's kills was saved and lost
			nodogs = part.nodogs,
			noshield = part.noshield,
			leaves = part.leaves,
			boss_name = part.boss_name,
			boss_colour = part.boss_colour,
		}
	end

	return copy
end

GrandfathersTarotView = class("GrandfathersTarotView", "BaseView")

-- Where the editor was left (2026-10-05, the user: "the Deck remembers its scroll; the editor key opens the window I left"):
-- kept on mod.rw for this game session (the view object is made anew at every open). `deck_offset` is the Deck's scroll, the
-- rest is the screen that was open and what it showed.
local TYPING_BLOCK = 0.35 -- seconds after the editor opens in which typed keys do not open a search box

local function memory()
	local rw = mod.rw

	if not rw then
		return {}
	end

	rw.editor_memory = rw.editor_memory or {}

	return rw.editor_memory
end

GrandfathersTarotView.memory = memory

-- screens of one card (they need the card; those marked need the enemy group too)
local CARD_SCREENS = { detail = false, picker = false, face = false, sounds = false, mods = true, tune = true, appearance = true }

GrandfathersTarotView.init = function (self, settings)
	self._screen = "list"
	self._offset = 0
	self._waves = {}
	self._parts = {}
	self._breeds = {}
	self._preset_slots = {} -- presets screen rows
	self._preset_waves = {} -- rows of the preset being viewed
	self._settings_rows = {} -- rows of the timing/voting/display screen
	self._random_mode = false -- enemy picker: collecting a random group
	self._random_pick = {}

	GrandfathersTarotView.super.init(self, definitions, settings)
end

-- ------------------------------------------------------------------ lifecycle

GrandfathersTarotView.on_enter = function (self)
	GrandfathersTarotView.super.on_enter(self)

	-- Crisp lines at every resolution: the renderer snaps rects, bitmaps and text to whole device pixels (only when the UI
	-- scale is 1 or more; the stock default is off). docs/08, section 3.
	if self._render_settings then
		self._render_settings.snap_pixel_positions = true
	end

	self:_setup_input_legend()
	self:_create_editor_widgets()

	self._screen = "list"
	self._offset = memory().deck_offset or 0
	self._key = nil
	-- (2026-10-05) the key that opened the editor ("-" for one player) is still in this frame's keystrokes: typing does not open a
	-- search box for a moment after the editor opens
	self._typing_blocked = TYPING_BLOCK
	-- where each search box was last dragged to, kept for the game session (2026-10-05)
	memory().popup_spots = memory().popup_spots or {}
	self._popup_spots = memory().popup_spots
	self._confirm = nil
	self._faction = mod:get("shelf_faction") == "dreg" and "dreg" or "scab"
	self._help_pinned = false
	self._widgets_by_name.help_panel.visible = false
	self._widgets_by_name.help_text.visible = false

	-- the Spidey Sense colours (or this mod's colour options) may have changed since last time
	if mod.rw.colors then
		mod.rw.colors.clear_cache()
	end

	self:_reload()

	local ok, restored = pcall(self._restore, self)

	if not ok or not restored then
		if not ok then
			mod:warning("GrandfathersTarot: the editor could not reopen where it was left: %s", tostring(restored))
		end

		self._screen, self._key, self._wave = "list", nil, nil
		self._offset = memory().deck_offset or 0
		self:_apply_screen(true)
	end
end

-- Notes where the editor is now (on_exit, and the Deck's scroll every frame)
GrandfathersTarotView._remember = function (self)
	local m = memory()

	if self._screen == "list" then
		m.deck_offset = self._offset
	end

	m.screen, m.key, m.offset, m.part_index, m.preset_index = self._screen, self._key, self._offset, self._part_index, self._preset_index
	m.filter, m.suit_kind = self._filter, self._suit_kind
end

-- Opens the screen noted by _remember, when what it showed still exists. Returns true when it did.
GrandfathersTarotView._restore = function (self)
	local m = memory()
	local screen = m.screen

	if CARD_SCREENS[screen] ~= nil then
		if not m.key then
			return false
		end

		self._key = m.key
		self:_reload()

		if not self._wave or self._wave.key ~= m.key then
			self._key, self._wave = nil, nil

			return false
		end

		self._parts = copy_parts(self._wave.parts)
		self._suit_kind = m.suit_kind

		local index = tonumber(m.part_index)

		if CARD_SCREENS[screen] and not (index and self._parts[index]) then
			screen = "detail"
		else
			self._part_index = index
		end

		if screen == "picker" then
			self._filter = m.filter
		elseif screen == "sounds" then
			-- the sound list is built by its own button (and its search box opens, as when it is entered)
			self._screen, self._offset = "face", 0
			self:_apply_screen()
			self:cb_sound_picker()

			return self._screen == "sounds"
		end
	elseif screen == "settings" then
		self:_reload_settings()
	elseif screen == "presets" or screen == "preset_view" then
		self:_reload_presets()

		if screen == "preset_view" then
			if m.preset_index and self._preset_slots[m.preset_index] then
				self._preset_index = m.preset_index
				self:_reload_preset_view()
			else
				screen = "presets"
			end
		end
	else
		return false
	end

	self._screen = screen
	self._offset = tonumber(m.offset) or 0
	self:_apply_screen(true)

	return true
end

GrandfathersTarotView.on_exit = function (self)
	if self._colour_drag then self._colour_drag = nil; self:_save() end
	self:_end_drag()
	pcall(self._remember, self)
	self._screen = "list"
	Popup.cancel(self)
	self:_refresh_text_flag()

	-- a client's waves may have changed: tell the host (used when it has "use everyone's waves" on)
	local director = mod.rw and mod.rw.director

	if director and director.send_waves then
		pcall(director.send_waves)
	end

	GrandfathersTarotView.super.on_exit(self)
end

GrandfathersTarotView.update = function (self, dt, t, input_service)
	if self._auto_typed then
		self:_finish_auto_search()
	end

	Popup.update(self, input_service)
	self:_update_colour(input_service)
	self:_update_sound(input_service)

	-- a pending "Sure?" (second click to delete/reset) runs out after a few seconds
	self._t = t or self._t or 0

	if self._confirm and self._t > self._confirm.expires then
		self._confirm = nil
		self:_apply_screen(true)
	end

	-- the help tooltip shows while the pointer is on the "?" corner button (or after clicking it)
	local widgets = self._widgets_by_name
	local help = widgets.btn_help

	if help and widgets.help_panel then
		local show = self._popup == nil and help.visible == true and (help.content.hotspot.is_hover == true or self._help_pinned == true)

		if widgets.help_panel.visible ~= show or show and self._help_shown_pinned ~= self._help_pinned then
			-- (laid out again as it opens: the page's accent may have changed with the card's suit, the footer with the pin)
			if show then self:_layout_help() end

			widgets.help_panel.visible = show
			widgets.help_text.visible = show
		end
	end

	if (self._screen == "picker" or self._screen == "list") and not self._popup or (self._typing_blocked or 0) > 0 then
		self:_auto_search(dt)
	end

	if self._screen == "list" then
		memory().deck_offset = self._offset
	end

	if self._screen == "list" and self._deck then
		self:_update_deck(dt, t)
		self:_update_deck_drag(input_service, dt)
	end

	if self._screen == "detail" or self._screen == "face" then
		self:_update_cauldron(dt, t)
	end

	self:_update_hold(dt)

	if (self._popup == nil or self._popup.spec.allow_rows) and input_service:get("scroll_axis") then
		local scroll = input_service:get("scroll_axis")
		local amount = scroll and scroll[2] or 0
		local max_offset = self:_max_offset()

		if amount ~= 0 and max_offset > 0 then
			-- two rows of the list per notch, one row (seven cards) of the Deck
			self._offset = self:_clamp_offset(self._offset + (amount > 0 and -1 or 1) * (self._screen == "list" and Deck.COLS or 2))
			self:_refresh_rows()
			self:_set_interaction_enabled()
		end
	end

	return GrandfathersTarotView.super.update(self, dt, t, input_service)
end

-- Holding a cooldown's minus or plus (2026-10-05, the user: "when holding the - + in the cooldown windows, make it increase
-- constantly"): the click takes its step as before; held for HOLD_DELAY, the button repeats it every HOLD_EVERY until it is let go
-- (or the pointer leaves it). The Deck's tiles, the cooldown beside the chance, the Mirror's cooldown and the card on the stage.
local HOLD_DELAY, HOLD_EVERY = 0.4, 0.07
local TILE_NAMES = {}

local function held_in(widget, minus_id, plus_id)
	if not widget or not widget.visible then return nil end

	local content = widget.content
	local minus, plus = content[minus_id], content[plus_id]

	if minus and minus.is_held and not minus.disabled then
		return minus
	elseif plus and plus.is_held and not plus.disabled then
		return plus
	end

	return nil
end

GrandfathersTarotView._held_cooldown = function (self)
	if self._popup then
		return nil
	end

	local widgets = self._widgets_by_name

	if self._screen == "list" then
		for i = 1, Deck.CAPACITY do
			TILE_NAMES[i] = TILE_NAMES[i] or TILE_PREFIX .. i

			local held = held_in(widgets[TILE_NAMES[i]], "hotspot_cd_minus", "hotspot_cd_plus")

			if held then
				return held
			end
		end
	elseif self._screen == "detail" or self._screen == "face" then
		return held_in(widgets.stepper_qcd, "hotspot_minus", "hotspot_plus") or held_in(widgets.stepper_cooldown, "hotspot_minus", "hotspot_plus") or held_in(widgets[definitions.STAGE_CARD_NODE], "hotspot_cd_minus", "hotspot_cd_plus")
	end

	return nil
end

GrandfathersTarotView._update_hold = function (self, dt)
	local held = self:_held_cooldown()

	if held ~= self._hold_hotspot then
		self._hold_hotspot, self._hold_t = held, 0

		return
	end

	if not held then
		return
	end

	self._hold_t = (self._hold_t or 0) + (dt or 0)

	if self._hold_t >= HOLD_DELAY and held.pressed_callback then
		self._hold_t = HOLD_DELAY - HOLD_EVERY
		held.pressed_callback()
	end
end

GrandfathersTarotView._setup_input_legend = function (self)
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

GrandfathersTarotView._on_back_pressed = function (self)
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
GrandfathersTarotView._create_dynamic_widget = function (self, name, definition)
	local existing = self._widgets_by_name[name]

	if existing then
		for i = #self._widgets, 1, -1 do
			if self._widgets[i] == existing then
				table.remove(self._widgets, i)
			end
		end
	end

	local widget = GrandfathersTarotView.super._create_widget(self, name, definition)

	self._widgets[#self._widgets + 1] = widget

	return widget
end

-- NOTE: must not be called `_create_widgets`: BaseView already has a method of
-- that name that builds the static widgets from definitions.widget_definitions
-- (and BaseView calls it before on_enter). Overriding it left title_text etc. nil.
GrandfathersTarotView._create_editor_widgets = function (self)
	self:_create_colour_callbacks()
	self:_create_effect_callbacks()
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
		content.hotspot_tune.pressed_callback = callback(self, "cb_row_tune", i)
		content.hotspot_rep_minus.pressed_callback = callback(self, "cb_row_rep_step", i, -1)
		content.hotspot_rep_plus.pressed_callback = callback(self, "cb_row_rep_step", i, 1)
		content.hotspot_rep_value.pressed_callback = callback(self, "cb_row_rep_input", i)
		content.hotspot_same.pressed_callback = callback(self, "cb_row_same", i)
	end

	-- the Deck: card tiles, the blank tile that makes a new card, and the strip of the draw
	for i = 1, Deck.CAPACITY do
		local name = TILE_PREFIX .. i
		local widget = self:_create_dynamic_widget(name, blueprints.tile(name))
		local content = widget.content

		-- left click: the face and the left of the state line toggle the card, a pip sets the chance, the Edit pill opens the
		-- card. A right click anywhere on the tile opens it too. A second left click inside the double-click time only calls
		-- double_click_callback: the pips and the pill repeat their action (a fast second click is not lost), the toggles do
		-- not (two toggles in a row would cancel out).
		local toggle = callback(self, "cb_tile_release", i)
		local edit = callback(self, "cb_tile_edit", i)

		-- the toggles act when the button is let go (a card held down for a while is being dragged to swap places, see
		-- _update_deck_drag, and must not switch): a quick click is the same as it was
		content.hotspot_top.released_callback, content.hotspot_top.right_pressed_callback = toggle, edit
		content.hotspot_state.released_callback, content.hotspot_state.right_pressed_callback = toggle, edit
		for _, id in ipairs({ "hotspot_top", "hotspot_state" }) do
			content[id].pressed_callback = callback(self, "cb_tile_press", i, true)
			content[id].double_click_callback = callback(self, "cb_tile_press", i, false)
		end
		content.hotspot_edit.pressed_callback, content.hotspot_edit.right_pressed_callback = edit, edit
		content.hotspot_edit.double_click_callback = edit
		content.hotspot_share.pressed_callback = callback(self, "cb_tile_share", i)

		for k = 1, Deck.PIPS do
			local hotspot = content[blueprints.TILE_IDS.hotspot_pip[k]]
			local set = callback(self, "cb_tile_pip", i, k)

			hotspot.pressed_callback, hotspot.double_click_callback, hotspot.right_pressed_callback = set, set, edit
		end

		-- the cooldown row: the minus and the plus take a step (a fast second click repeats it), the value opens a number box, a
		-- right click anywhere on it opens the card like on the pips
		local less, more = callback(self, "cb_tile_cooldown", i, -1), callback(self, "cb_tile_cooldown", i, 1)

		content.hotspot_cd_minus.pressed_callback, content.hotspot_cd_minus.double_click_callback, content.hotspot_cd_minus.right_pressed_callback = less, less, edit
		content.hotspot_cd_plus.pressed_callback, content.hotspot_cd_plus.double_click_callback, content.hotspot_cd_plus.right_pressed_callback = more, more, edit
		content.hotspot_cd_value.pressed_callback, content.hotspot_cd_value.right_pressed_callback = callback(self, "cb_tile_cooldown_input", i), edit

		widget.visible = false
	end

	local blank = self:_create_dynamic_widget(BLANK_NAME, blueprints.blank_tile(BLANK_NAME))

	blank.content.hotspot.pressed_callback = callback(self, "cb_tile_new")
	blank.visible = false
	self:_create_dynamic_widget("rw_strip", blueprints.strip("deck_strip")).visible = false

	self:_create_workshop_widgets(blueprints, WB)

	for i = 1, #BUTTONS do
		local entry = BUTTONS[i]
		local widget = self:_create_dynamic_widget(entry.name, blueprints.button(entry.name, entry.width, entry.role, entry.height, nil, entry.pip, entry.font))

		widget.content.hotspot.pressed_callback = callback(self, entry.cb, entry.arg)
	end

	local chance = self:_create_dynamic_widget("stepper_chance", blueprints.workshop_stepper("stepper_chance", 290, Workshop.ROW_LABEL_W, 15, Components.colors.muted))
	-- the card's cooldown beside its chance (the Mirror's callbacks: 30 s steps, the value opens a number box)
	local qcd = self:_create_dynamic_widget("stepper_qcd", blueprints.workshop_stepper("stepper_qcd", Workshop.RIGHT_W - 290, 98, 15, Components.colors.muted))

	qcd.content.hotspot_minus.pressed_callback = callback(self, "cb_cooldown_step", -1)
	qcd.content.hotspot_plus.pressed_callback = callback(self, "cb_cooldown_step", 1)
	qcd.content.hotspot_value.pressed_callback = callback(self, "cb_cooldown_input")

	chance.content.hotspot_minus.pressed_callback = callback(self, "cb_chance_step", -1)
	chance.content.hotspot_plus.pressed_callback = callback(self, "cb_chance_step", 1)
	chance.content.hotspot_value.pressed_callback = callback(self, "cb_chance_input")

	local cooldown = self:_create_dynamic_widget("stepper_cooldown", blueprints.workshop_stepper("stepper_cooldown", 700, 0))

	cooldown.content.hotspot_minus.pressed_callback = callback(self, "cb_cooldown_step", -1)
	cooldown.content.hotspot_plus.pressed_callback = callback(self, "cb_cooldown_step", 1)
	cooldown.content.hotspot_value.pressed_callback = callback(self, "cb_cooldown_input")

	-- spread radius, repeat every, repeat for
	local extra_steppers = {
		{ name = "stepper_spread", compact = true, step = 1, cb = "spread" },
		{ name = "stepper_every", compact = true, step = 1, cb = "every" },
		{ name = "stepper_for", compact = true, step = 5, cb = "for" },
		{ name = "stepper_dmin", compact = true, step = 5, cb = "dmin" },
		{ name = "stepper_dmax", compact = true, step = 5, cb = "dmax" },
		{ name = "stepper_timer", compact = true, step = 1, cb = "timer" },
		-- list screen: the time between waves (long labels, so a wider label column)
		{ name = "stepper_tmin", width = 700, step = 1, cb = "tmin", label_width = 330 },
		{ name = "stepper_tmax", width = 700, step = 1, cb = "tmax", label_width = 330 },
	}

	for i = 1, #extra_steppers do
		local entry = extra_steppers[i]
		local widget = self:_create_dynamic_widget(entry.name, entry.compact and blueprints.workshop_stepper(entry.name, Workshop.SPAWN_W, 142, 18) or blueprints.setting_stepper(entry.name, entry.width, entry.label_width))

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

GrandfathersTarotView._reload = function (self)
	self:_end_drag()
	local rw = mod.rw
	local keys = rw.events.ordered_keys(get_setting)
	local waves, total, deleted = {}, 0, 0

	for i = 1, #keys do
		local wave = rw.events.get(keys[i], get_setting, rw.groups)

		-- deleted standard waves are hidden (Restore defaults brings them back)
		if wave.deleted then
			deleted = deleted + 1
		else
			waves[#waves + 1] = wave
		end

		if wave.key == self._key then
			self._wave = wave
		end

		if wave.enabled and mod.rw.events.has_content(wave) and wave.pct > 0 and not (wave.timer > 0) then
			total = total + wave.pct
		end
	end

	self._waves = waves
	self._total_pct = total
	self._deleted_count = deleted
	self:_build_deck()
	self:_count_ready()
end

-- how many items a page holds, where a page can start, and how far a scroll step goes (the Deck pages by rows of cards)
GrandfathersTarotView._max_offset = function (self)
	local count = #self:_source()

	if self._screen == "list" then
		return Deck.max_offset(count)
	end

	return math.max(0, count - (self._screen == "detail" and Workshop.ROWS or LIST_CAPACITY))
end

GrandfathersTarotView._clamp_offset = function (self, offset)
	if self._screen == "list" then
		return Deck.clamp_offset(offset, #self:_source())
	end

	return math.clamp(offset, 0, math.max(0, #self:_source() - (self._screen == "detail" and Workshop.ROWS or LIST_CAPACITY)))
end

-- Percent of the draw a card gets: its chance over the chances of the cards that can be dealt now (the cards that rest after a pick
-- are out of the draw, so the others are likelier). A resting card is counted with them: the share it has when it is back.
GrandfathersTarotView._share_of = function (self, wave)
	if wave.enabled and mod.rw.events.has_content(wave) and wave.pct > 0 and not (wave.timer > 0) then
		local total = (self._ready_pct or self._total_pct or 0) + ((self._resting and self._resting[wave.key]) and wave.pct or 0)

		return mod.rw.cards.share(wave.pct, total)
	end

	return nil
end

GrandfathersTarotView._source = function (self)
	if self._screen == "detail" then
		return self._parts
	elseif self._screen == "picker" then
		return self._breeds
	elseif self._screen == "mods" then
		return mod.rw.groups.MODIFIERS
	elseif self._screen == "tune" then
		return mod.rw.groups.TUNE_SCREEN
	elseif self._screen == "face" then
		return {} -- (the Mirror has no table)
	elseif self._screen == "sounds" then
		return self._sound_results or {}
	elseif self._screen == "appearance" then
		return {}
	elseif self._screen == "presets" then
		return self._preset_slots
	elseif self._screen == "preset_view" then
		return self._preset_waves
	elseif self._screen == "settings" then
		return self._settings_rows
	end

	return self._deck or self._waves
end

-- ------------------------------------------------------------ settings rows (timing, voting, display)

local SETTINGS_ROWS = {
	-- id, kind, then the numbers for a "number" row. Labels/infos are localized as set_<id> / set_<id>_info.
	{ id = "mode", kind = "mode" },
	{ id = "interval_random", kind = "toggle", default = false },
	{ id = "interval_min", kind = "number", default = 75, min = 5, max = 1800, step = 5 },
	{ id = "interval_max", kind = "number", default = 75, min = 5, max = 1800, step = 5, needs = "interval_random" },
	{ id = "initial_delay", kind = "number", default = 0, min = 0, max = 600, step = 5 },
	{ id = "vote_duration", kind = "number", default = 5, min = 5, max = 120, step = 5 },
	{ id = "ballot_size", kind = "number", default = 3, min = 2, max = 5, step = 1 },
	{ id = "pool_all_players", kind = "toggle", default = false },
	{ id = "hud_show_percent", kind = "toggle", default = false },
	{ id = "colour_enemies", kind = "toggle", default = true },
	{ id = "colour_spidey", kind = "toggle", default = false, needs = "colour_enemies" },
}

local function setting_flag(id, default)
	local value = mod:get(id)

	if value == nil then
		return default == true
	end

	return value == true
end

-- Live rows for the settings screen (values come straight from the mod's settings).
GrandfathersTarotView._reload_settings = function (self)
	local rows = {}
	local random_on = setting_flag("interval_random", false)

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
GrandfathersTarotView._painter = function (self)
	local colors = mod.rw.colors

	if not colors then
		return nil
	end

	-- painter table for Groups.summary: the enemy part in the enemy's colour, each modifier name in its
	-- Improved Havoc Tags colour
	return {
		part = function (part)
			return colors.rgb(part.breed)
		end,
		breed = function (breed)
			return colors.rgb(breed)
		end,
		mod = function (id)
			return colors.modifier_rgb(id)
		end,
		markup = colors.markup,
	}
end

-- ------------------------------------------------------------------- presets model

-- Reads the five slots (name, changed-wave count, a few wave names) for the presets screen.
GrandfathersTarotView._reload_presets = function (self)
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
GrandfathersTarotView._reload_preset_view = function (self)
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

GrandfathersTarotView._open_preset = function (self, index)
	self._preset_index = index
	self._preset_note = nil
	self._screen = "preset_view"
	self._offset = 0
	self:_reload_preset_view()
	self:_apply_screen()
end

-- After the stored preset changed (save, rename, import, clear): re-read everything and redraw.
GrandfathersTarotView._refresh_preset = function (self, note)
	self._preset_note = note
	self:_reload_presets()
	self:_reload_preset_view()
	self:_apply_screen(true)
end

GrandfathersTarotView._item_at = function (self, row_index)
	return self:_source()[self._offset + row_index]
end

GrandfathersTarotView._save = function (self)
	local rw = mod.rw
	local edited = self._parts[self._part_index or 0]
	local edited_key = edited and rw.groups.part_key(edited)

	rw.events.set_def(set_setting, self._key, self._wave.name, self._parts, rw.groups)
	self:_reload()
	self._parts = copy_parts(self._wave.parts)
	if edited_key then
		for i, part in ipairs(self._parts) do
			if rw.groups.part_key(part) == edited_key then self._part_index = i; break end
		end
	end
	self:_apply_screen(true)
end

GrandfathersTarotView._open_detail = function (self, key)
	if self._screen == "list" then
		memory().deck_offset = self._offset
	end

	-- (2026-10-05) the Deck's search box closes when a card is opened; its filter stays for the Deck
	if self._popup and self._popup.spec and self._popup.spec.place_key == "deck_search" then
		Popup.close_keep(self)
	end

	self._key = key
	self._suit_kind = nil -- the hostile / beneficial switch starts on the card's own kind
	self:_reload()
	self._parts = copy_parts(self._wave.parts)
	self._screen = "detail"
	self._offset = 0
	self:_apply_screen()
end

-- --------------------------------------------------------------------- display

GrandfathersTarotView._apply_screen = function (self, keep_offset)
	self:_end_drag()
	local widgets = self._widgets_by_name
	local screen = self._screen
	local rw = mod.rw

	self:_refresh_text_flag()

	if not keep_offset then
		self._offset = 0
		self._help_pinned = false
	end

	if screen == "picker" then
		self._breeds = rw.groups.search(self._filter or "")
	end

	self._offset = self:_clamp_offset(self._offset)

	widgets.title_text.content.title_text = mod:localize(CARD_SCREEN_TITLE[screen] or "view_title")
	Components.set_theme(CARD_SCREEN_TITLE[screen] and self._wave and rw.cards.suit(self._wave.suit) or nil)

	local header = widgets.list_header.content

	header.col_6 = ""
	header.col_7 = ""

	if screen == "list" then
		widgets.description_text.content.description_text = mod:localize("view_desc_list")
		widgets.bottom_title.content.bottom_title = (self._deleted_count or 0) > 0 and mod:localize("bottom_list_deleted", self._deleted_count) or mod:localize("bottom_list_title")

		-- the time between waves (the same two settings as in the options menu)
		local random_on = setting_flag("interval_random", false)
		local tmin, tmax = widgets.stepper_tmin.content, widgets.stepper_tmax.content

		tmin.label = mod:localize(random_on and "set_interval_min" or "set_interval_fixed")
		tmin.stepper_value = tostring(math.floor(tonumber(mod:get("interval_min")) or 75))
		tmin.extra = mod:localize("extra_seconds")
		tmax.label = mod:localize("set_interval_max")
		tmax.stepper_value = tostring(math.floor(tonumber(mod:get("interval_max")) or 75))
		tmax.extra = mod:localize(random_on and "extra_seconds" or "extra_not_random")
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

		if self._random_mode then
			local names = {}

			for i = 1, #self._random_pick do
				names[i] = rw.groups.display_name(self._random_pick[i])
			end

			status = mod:localize("picker_random_status", #names == 0 and mod:localize("picker_random_none") or table.concat(names, ", ")) .. "   " .. status
		end

		-- shown in the description (top of the screen) so it stays visible under the search popup
		if self._picker_note then
			status = self._picker_note .. "   " .. status
		end

		widgets.description_text.content.description_text = widgets.description_text.content.description_text .. "   " .. status
		widgets.bottom_title.content.bottom_title = status

		widgets.hint_text.content.hint_text = ""
	elseif screen == "face" then
		widgets.description_text.content.description_text = mod:localize("view_desc_face", self._wave.name)
		widgets.bottom_title.content.bottom_title = ""
		widgets.hint_text.content.hint_text = ""
	elseif screen == "sounds" then
		widgets.description_text.content.description_text = mod:localize("view_desc_sounds")
		header.col_1, header.col_2, header.col_3, header.col_4, header.col_5 = "", "Sound", "Game event", "", ""
		widgets.bottom_title.content.bottom_title = ""
		widgets.hint_text.content.hint_text = ""
	elseif screen == "appearance" then
		local part = self._parts[self._part_index]
		widgets.description_text.content.description_text = mod:localize("view_desc_appearance", part and rw.groups.describe_part(part) or "")
		widgets.bottom_title.content.bottom_title = mod:localize("appearance_strength_info")
	elseif screen == "tune" then
		local part = self._parts[self._part_index]

		widgets.description_text.content.description_text = mod:localize("view_desc_tune", part and rw.groups.describe_part(part) or "")
		header.col_1, header.col_2, header.col_3, header.col_4, header.col_5 = "", mod:localize("col_setting"), mod:localize("col_what_it_does"), mod:localize("col_percent"), ""
		widgets.bottom_title.content.bottom_title = mod:localize("bottom_tune_title", part and rw.groups.describe_part(part) or "")
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

	-- the long gray texts live in the help tooltip (the "?" corner button), not on the screen
	local help_keys = { list = "hint_list", mods = "hint_mods", presets = "hint_presets", settings = "hint_settings", detail = "help_detail", picker = "help_picker", preset_view = "help_preset_view", face = "help_face", tune = "help_tune" }

	widgets.hint_text.visible = false
	self._help_key = screen == "appearance" and "help_appearance" or help_keys[screen] or "hint_list"
	self:_layout_help()
	widgets.btn_help.visible = true
	widgets.btn_help.content.hotspot_text = "?"

	-- the Deck has no table: its panel, header and range text are hidden and the scroll buttons sit beside the grid
	local deck_screen = screen == "list"

	local cauldron = screen == "detail"
	local under = definitions.under_shelf

	widgets.list_panel.visible = not deck_screen and not cauldron and screen ~= "face"
	widgets.list_header.visible = not deck_screen and not cauldron and screen ~= "face"
	widgets.bottom_panel.visible = not cauldron and screen ~= "face"
	if screen == "appearance" then widgets.list_header.visible = false end

	-- Back is at the foot of every screen of a card (its enemies, the picker, Mods, Custom, its face) in the same place, with the
	-- picker's buttons beside it; the other screens keep it at 125, 800. Never on a spot where the screen it returns to has a button.
	local card_screen = CARD_SCREEN_TITLE[screen] ~= nil

	self:_set_scenegraph_position("btn_back", card_screen and Workshop.LEFT_X or 125, card_screen and under.actions_y or 800, 2)
	self:_set_scenegraph_position("btn_appearance", Workshop.LEFT_X + 200, under.actions_y, 2)
	self:_set_scenegraph_position("btn_search", screen == "picker" and 297 or 325, screen == "picker" and under.actions_y or 800, 2)
	self:_set_scenegraph_position("btn_stay", screen == "picker" and 729 or 765, screen == "picker" and under.actions_y or 800, 2)
	self:_set_scenegraph_position("btn_random", screen == "picker" and 1121 or 1165, screen == "picker" and under.actions_y or 800, 2)
	self:_set_scenegraph_position("btn_random_done", screen == "picker" and 1443 or 1495, screen == "picker" and under.actions_y or 800, 2)

	if cauldron then
		-- the summary line under the enemy rows, with the scroll buttons at its right end; the action bar at the foot of the pane
		self:_set_scenegraph_position("scroll_up", 1148, Workshop.SUMMARY_Y - 1, 2)
		self:_set_scenegraph_position("scroll_down", 1196, Workshop.SUMMARY_Y - 1, 2)
		self:_set_scenegraph_position("list_range", 800, Workshop.SUMMARY_Y + 3, 2)
		self:_set_scenegraph_position("bottom_title", Workshop.LEFT_X, Workshop.SUMMARY_Y, 2)
	else
		self:_set_scenegraph_position("scroll_up", deck_screen and 1826 or 1771, deck_screen and Deck.Y0 or 168, 2)
		self:_set_scenegraph_position("scroll_down", deck_screen and 1826 or 1771, deck_screen and Deck.Y0 + 2 * Deck.TILE_H + Deck.GAP - 36 or 696, 2)
		self:_set_scenegraph_position("list_range", 1400, 700, 2)
		self:_set_scenegraph_position("bottom_title", 125, 758, 2)
	end
	widgets.btn_default.visible = screen == "list"

	for _, name in ipairs({ "btn_draw_ben_on", "btn_draw_ben_off", "btn_draw_foe_on", "btn_draw_foe_off" }) do
		widgets[name].visible = screen == "list"
		widgets[name].content.hotspot_text = mod:localize(name)
	end
	widgets.sort_label.visible = screen == "list"
	widgets.sort_label.content.sort_label = string.upper(mod:localize("sort_label"))

	for _, mode in ipairs(Deck.SORTS) do
		local sort_button = widgets["btn_sort_" .. mode]
		local active = mod:get("deck_sort") == mode

		sort_button.visible = screen == "list"
		-- the arrow says which way: ^ from the lowest, v from the highest
		sort_button.content.hotspot_text = mod:localize("sort_" .. mode) .. (active and (mod:get("deck_sort_desc") == true and " v" or " ^") or "")
		sort_button.content.hotspot_on = active
	end
	widgets.btn_default.content.hotspot_text = mod:localize(self._confirm and self._confirm.key == "__defaults" and "btn_sure" or "btn_default")
	widgets.btn_default.content.hotspot_on = self._confirm ~= nil and self._confirm.key == "__defaults"
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
	widgets.btn_face.visible = detail or screen == "face"
	widgets.btn_face.content.hotspot_text = mod:localize("btn_face")
	widgets.btn_face.content.hotspot_on = screen == "face"
	widgets.btn_enemies.visible = detail or screen == "face"
	widgets.btn_enemies.content.hotspot_text = mod:localize("tab_enemies")
	widgets.btn_enemies.content.hotspot_on = detail

	local mirror = screen == "face"

	for _, name in ipairs({ "btn_dreg", "btn_scab", "btn_quickface" }) do
		widgets[name].visible = detail
	end

	-- (the stage's toolbar and the threat switch are on both screens, in their own places; the Mirror's buttons only on the Mirror)
	for _, name in ipairs({ "btn_preview", "btn_enabled" }) do
		widgets[name].visible = detail or mirror
	end

	for _, name in ipairs({ "btn_whisper_change", "btn_whisper_suit", "btn_reset_face" }) do
		widgets[name].visible = mirror
	end

	-- the hostile / beneficial switch: beside FACE under the card on the Cauldron, at the end of the Suit header on the Mirror
	local kind_x = mirror and Workshop.MIRROR.kind_x or Workshop.KIND.x
	local kind_y = mirror and Workshop.MIRROR.kind_y or Workshop.QUICK_Y - 2

	self:_set_scenegraph_position("btn_kind_hostile", kind_x, kind_y, 3)
	self:_set_scenegraph_position("btn_kind_ben", kind_x + Workshop.KIND.w_hostile, kind_y, 3)
	widgets.btn_kind_hostile.visible = detail or mirror
	widgets.btn_kind_ben.visible = detail or mirror

	widgets.rw_scroll_up.visible = not mirror and screen ~= "appearance"
	widgets.rw_scroll_down.visible = not mirror and screen ~= "appearance"
	widgets.bottom_title.visible = not mirror
	widgets.btn_delete.visible = detail
	widgets.btn_delete.content.hotspot_text = mod:localize(self._confirm and self._wave and self._confirm.key == self._wave.key and "btn_sure" or "btn_delete")
	widgets.btn_delete.content.hotspot_on = self._confirm ~= nil and self._wave ~= nil and self._confirm.key == self._wave.key
	widgets.btn_pload.content.hotspot_text = mod:localize("btn_pload")
	widgets.btn_psave.content.hotspot_text = mod:localize("btn_psave")
	widgets.btn_prename.content.hotspot_text = mod:localize("btn_rename")
	widgets.btn_pexport.content.hotspot_text = mod:localize("btn_pexport")
	widgets.btn_pimport.content.hotspot_text = mod:localize("btn_pimport")
	widgets.btn_pundo.content.hotspot_text = mod:localize("btn_pundo")
	widgets.btn_pclear.content.hotspot_text = mod:localize("btn_pclear")
	widgets.btn_search.visible = screen == "picker"
	widgets.btn_stay.visible = screen == "picker"
	widgets.btn_random.visible = screen == "picker"
	widgets.btn_random_done.visible = screen == "picker" and self._random_mode == true
	widgets.btn_random.content.hotspot_text = mod:localize(self._random_mode and "btn_random_on" or "btn_random_off")
	widgets.btn_random.content.hotspot_on = self._random_mode == true
	widgets.btn_random_done.content.hotspot_text = mod:localize("btn_random_done", #(self._random_pick or {}))
	widgets.btn_rename.visible = detail
	widgets.btn_keep_pick.visible = detail and rw.groups.has_random(self._parts)
	widgets.btn_keep_pick.content.hotspot_text = mod:localize(self._wave and self._wave.keep_pick == false and "btn_keep_pick_off" or "btn_keep_pick_on")
	widgets.btn_keep_pick.content.hotspot_on = self._wave ~= nil and self._wave.keep_pick ~= false
	widgets.btn_text.visible = detail
	widgets.btn_add.visible = detail
	widgets.btn_reset.visible = detail
	for i = 1, #DETAIL_STEPPERS do
		widgets[DETAIL_STEPPERS[i]].visible = detail
	end

	-- the cooldown stepper is the Mirror's
	widgets.stepper_cooldown.visible = screen == "face"

	for i = 1, #LIST_STEPPERS do
		widgets[LIST_STEPPERS[i]].visible = screen == "list"
	end

	widgets.btn_back.content.hotspot_text = mod:localize("btn_back")
	widgets.btn_search.content.hotspot_text = (self._filter or "") ~= "" and mod:localize("btn_search_active", self._filter) or mod:localize("btn_search")
	widgets.btn_stay.content.hotspot_text = mod:localize(mod:get("picker_stay") == true and "btn_stay_on" or "btn_stay_off")
	widgets.btn_stay.content.hotspot_on = mod:get("picker_stay") == true
	widgets.btn_rename.content.hotspot_text = mod:localize("btn_rename")
	widgets.btn_text.content.hotspot_text = mod:localize("btn_edit_text")
	widgets.btn_add.content.hotspot_text = mod:localize("btn_add_enemy")

	if detail then
		local wave = self._wave

		widgets.btn_enabled.content.hotspot_text = mod:localize(wave.enabled and "btn_enabled_on" or "btn_enabled_off")
		widgets.btn_enabled.content.hotspot_on = wave.enabled == true
		widgets.btn_reset.content.hotspot_text = mod:localize(wave.is_custom and "btn_reset_clear" or "btn_reset_default")

		local chance = widgets.stepper_chance.content
		local share = self:_share_of(wave)

		chance.label = string.upper(mod:localize("lbl_chance"))
		chance.stepper_value = tostring(math.floor(wave.pct))
		chance.extra = wave.timer > 0 and mod:localize("extra_timer_short") or share and mod:localize("extra_share_short", string.format("%.1f", share)) or mod:localize("extra_not_drawn_short")

		local qcd = widgets.stepper_qcd.content

		qcd.label = string.upper(mod:localize("lbl_cooldown_short"))
		qcd.stepper_value = Deck.clock_text(wave.cooldown)
		qcd.stepper_value_dim = wave.timer > 0
		qcd.extra = ""

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
		every.stepper_value_dim = not repeating
		rep_for.stepper_value_dim = not repeating
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

		-- fixed timer: 0 = off (the wave is drawn by its chance), otherwise it spawns every N seconds on its own
		local timer = widgets.stepper_timer.content

		timer.label = mod:localize("lbl_timer")
		timer.stepper_value = wave.timer > 0 and tostring(math.floor(wave.timer)) or mod:localize("val_off")
		timer.extra = mod:localize(wave.timer > 0 and "extra_timer_on" or "extra_timer_off")
	end

	self:_refresh_rows()
	self:_set_interaction_enabled()
end

GrandfathersTarotView._refresh_rows = function (self)
	local rw = mod.rw
	local colors = rw.colors
	local screen = self._screen
	local source = self:_source()

	if screen == "list" then
		-- the Deck: no rows, no range text; the tiles are painted instead
		for i = 1, LIST_CAPACITY do
			local widget = self._widgets_by_name[ROW_NODE_PREFIX .. i]

			if widget then
				widget.visible = false
			end
		end

		if self._widgets_by_name.list_range then
			self._widgets_by_name.list_range.content.list_range = ""
		end

		self:_hide_cauldron()
		self:_hide_mirror()
		self:_refresh_deck()

		return
	end

	self:_hide_deck()

	if screen == "detail" or screen == "face" then
		-- the Cauldron and the Mirror have their own widgets; the table rows are not used
		for i = 1, LIST_CAPACITY do
			local widget = self._widgets_by_name[ROW_NODE_PREFIX .. i]

			if widget then
				widget.visible = false
			end
		end

		if screen == "face" then
			self:_hide_cauldron()
			self:_refresh_mirror()
			self._widgets_by_name.list_range.content.list_range = ""

			return
		end

		self:_hide_mirror()
		self:_refresh_cauldron()

		local parts = #self._parts

		self._widgets_by_name.list_range.content.list_range = parts > 0 and mod:localize("list_range", self._offset + 1, math.min(self._offset + Workshop.ROWS, parts), parts) or ""

		return
	end

	self:_hide_cauldron()
	self:_hide_mirror()

	for i = 1, LIST_CAPACITY do
		local widget = self._widgets_by_name[ROW_NODE_PREFIX .. i]
		local item = source[self._offset + i]

		self:_set_scenegraph_position(ROW_NODE_PREFIX .. i, 105, LIST_TOP + (i - 1) * ROW_HEIGHT, 1)

		if widget then
			widget.visible = item ~= nil

			if item then
				local content = widget.content
				local name_color = Components.colors.text

				widget.style.info.size[1] = 640
				content.show_tune = false
				content.hotspot_mods_on, content.hotspot_tune_on = false, false

				if screen == "sounds" then
					content.row_name = item.event ~= "" and item.event:match("([^/]+)$") or mod:localize("snd_silence")
					content.info = item.event
					-- Preview (the row's chip) plays the sound without choosing it; Silence has nothing to play
					content.show_check, content.show_stepper, content.show_share, content.show_action, content.show_mods, content.show_rep = false, false, false, true, item.event ~= "", false
					content.hotspot_mods_text = mod:localize("snd_preview")
					content.hotspot_action_text = "Select"
				elseif screen == "tune" then
					name_color = self:_tune_row(item, content)
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
					content.row_name = with_faction(rw, item, rw.groups.display_name(item))
					content.info = string.format("%s  (%s)", item, rw.groups.kind(item))

					-- random group mode: the enemies picked so far are marked
					if self._random_mode then
						for j = 1, #self._random_pick do
							if self._random_pick[j] == item then
								content.info = "[picked]  " .. content.info
							end
						end
					end

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

					name_color = colors and colors.modifier_argb(item.id) or name_color
					content.row_name = item.name
					content.info = item.requires_havoc and (item.description .. " " .. mod:localize("note_havoc_only")) or item.description
					-- On Fire: its burn's damage on the right of the row (2026-10-04)
					local burn = item.id == "fire"

					content.show_check, content.show_stepper, content.show_share, content.show_action, content.show_mods = true, burn, false, false, false
					content.show_rep = false
					content.checkbox_selected = applied

					if burn then
						content.stepper_value = tostring(part and part.tune and part.tune.burn or mod.rw.groups.tune_default("burn")) .. "%"
						content.info = mod:localize("mod_fire_damage_info")
					end
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
GrandfathersTarotView._set_interaction_enabled = function (self)
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

	for i = 1, Deck.CAPACITY do
		local widget = widgets[TILE_PREFIX .. i]

		if widget then
			for j = 1, #self.TILE_HOTSPOTS do
				widget.content[self.TILE_HOTSPOTS[j]].disabled = not (rows_enabled and widget.visible)
			end
		end
	end

	local blank = widgets[BLANK_NAME]

	if blank then
		blank.content.hotspot.disabled = not (rows_enabled and blank.visible)
	end

	self:_set_cauldron_interaction(rows_enabled)
	self:_set_mirror_interaction(rows_enabled)

	local max_offset = self:_max_offset()
	local up, down = widgets.rw_scroll_up, widgets.rw_scroll_down

	if up then
		up.content.hotspot.disabled = not rows_enabled or self._offset <= 0
	end

	if down then
		down.content.hotspot.disabled = not rows_enabled or self._offset >= max_offset
	end
	self:_refresh_colour()
	self:_refresh_effects()
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

DeckView.install(GrandfathersTarotView, {
	Deck = Deck,
	Spread = blueprints.Spread,
	TILE = blueprints.TILE,
	TILE_IDS = blueprints.TILE_IDS,
	STRIP_IDS = blueprints.STRIP_IDS,
	STRIP_HOT = blueprints.STRIP_HOT,
	TILE_PREFIX = TILE_PREFIX,
	BLANK_NAME = BLANK_NAME,
	guarded = guarded,
	set_setting = set_setting,
	Popup = Popup,
})

FaceView.install(GrandfathersTarotView, {
	Deck = Deck,
	guarded = guarded,
	set_setting = set_setting,
	Popup = Popup,
	definitions = definitions,
})

TuneView.install(GrandfathersTarotView, {
	guarded = guarded,
	Popup = Popup,
	Components = Components,
})

EffectsView.install(GrandfathersTarotView, { guarded = guarded, Popup = Popup, definitions = definitions })
ColourView.install(GrandfathersTarotView, { guarded = guarded, Popup = Popup })

WorkshopView.install(GrandfathersTarotView, {
	Deck = Deck,
	Workshop = Workshop,
	Spread = blueprints.Spread,
	TILE_IDS = blueprints.TILE_IDS,
	definitions = definitions,
	guarded = guarded,
	set_setting = set_setting,
	Components = Components,
	with_faction = with_faction,
})

GrandfathersTarotView.cb_scroll = guarded(function (self, direction)
	self._offset = self:_clamp_offset(self._offset + direction * (self._screen == "list" and Deck.COLS or 1))

	if self._screen == "list" then
		memory().deck_offset = self._offset
	end

	self:_refresh_rows()
	self:_set_interaction_enabled()
end)

GrandfathersTarotView.cb_back = guarded(function (self)
	if self._colour_menu then self._colour_menu = false; self:_refresh_colour(); return end
	if self._colour_drag then self._colour_drag = nil; self:_save() end
	self._random_mode = false
	self._random_pick = {}
	self._replace_index = nil

	if self._screen == "sounds" then
		self._screen = "face"
	elseif self._screen == "appearance" then
		self._screen = "tune"
	elseif self._screen == "preset_view" then
		self._screen = "presets"
		self:_reload_presets()
	elseif self._screen == "picker" or self._screen == "mods" or self._screen == "face" or self._screen == "tune" then
		self._screen = "detail"
	else
		self._screen = "list"
		self._key = nil
	end

	-- back on the Deck: where it was scrolled to
	local deck = self._screen == "list"

	self:_reload()

	if deck then
		self._offset = memory().deck_offset or 0
	end

	self:_apply_screen(deck)
end)

-- rows -----------------------------------------------------------------------

-- Settings screen: flip a yes/no row (the "mode" row maps to vote / the Tarot draw; the Random countdown is chosen in
-- the mod options).
GrandfathersTarotView._toggle_setting = function (self, item)
	if item.kind == "mode" then
		set_setting("mode", item.on and "tarot" or "vote")
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

GrandfathersTarotView._set_number_setting = function (self, item, value)
	set_setting(item.id, math.clamp(math.floor(value + 0.5), item.min, item.max))
	self:_reload_settings()
	self:_apply_screen(true)
end

GrandfathersTarotView.cb_settings = guarded(function (self)
	self:_reload_settings()
	self._screen = "settings"
	self:_apply_screen()
end)

GrandfathersTarotView.cb_row_check = guarded(function (self, row)
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

	-- the Custom screen's toggles (the Boss bar)
	if self._screen == "tune" then
		local item = self:_item_at(row)

		if item and item.toggle then
			self:_tune_toggle(item)
		end

		return
	end

end)

-- The On Fire damage of a group (percent, 0 to 300; the default, 35, is not stored)
GrandfathersTarotView._set_burn = function (self, part, value)
	local burn = mod.rw.groups.clamp_tune("burn", value)

	part.tune = part.tune or {}
	part.tune.burn = burn ~= mod.rw.groups.tune_default("burn") and burn or nil

	if next(part.tune) == nil then
		part.tune = nil
	end

	self:_save()
end

-- Toggles one modifier on the enemy group being edited (self._part_index).
GrandfathersTarotView._toggle_mod = function (self, id)
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

GrandfathersTarotView.cb_row_mods = guarded(function (self, row)
	-- on the completion sound screen the chip of a row is Preview
	if self._screen == "sounds" then
		return self:_preview_sound_row(row)
	end

	if self._screen == "detail" and self._parts[self._offset + row] then
		self._part_index = self._offset + row
		self._screen = "mods"
		self:_apply_screen()
	end
end)

GrandfathersTarotView.cb_row_name = guarded(function (self, row)
	local item = self:_item_at(row)

	if not item then
		return
	end

	if self._screen == "presets" then
		self:_open_preset(item.index)
	elseif self._screen == "picker" then
		self:_add_breed(item)
	elseif self._screen == "mods" then
		self:_toggle_mod(item.id)
	elseif self._screen == "tune" then
		self:_tune_value(item)
	elseif self._screen == "settings" then
		if item.kind == "number" then
			self:_open_setting_popup(item)
		else
			self:_toggle_setting(item)
		end
	end
end)

GrandfathersTarotView._open_setting_popup = function (self, item)
	Popup.open(self, {
		label = item.label,
		value = tostring(item.number),
		numeric = true, min = item.min, max = item.max, integer = true,
		set = function (value)
			self:_set_number_setting(item, value)
		end,
	})
end

-- Delete (button of the card's own screen): a custom card is emptied, a standard card is hidden until the defaults are
-- restored. The first click asks "Sure?" for a few seconds, the second one does it.
GrandfathersTarotView.cb_delete = guarded(function (self)
	local wave = self._wave

	if self._screen ~= "detail" or not wave then
		return
	end

	if self._confirm and self._confirm.key == wave.key and (self._t or 0) <= self._confirm.expires then
		self._confirm = nil

		-- (2026-10-06) emptied, not given the default deck's card back (a plain reset would write that deck's card over it)
		if wave.is_custom then
			mod.rw.events.reset(set_setting, wave.key, true)
		else
			set_setting("del_" .. wave.key, true)
		end

		self._screen = "list"
		self._key = nil
		self:_reload()
		self:_apply_screen()

		return
	end

	self._confirm = { key = wave.key, expires = (self._t or 0) + 4 }
	self:_apply_screen(true)
end)

GrandfathersTarotView.cb_row_action = guarded(function (self, row)
	if self._screen == "sounds" then return self:cb_sound_select(row) end
	local item = self:_item_at(row)

	if not item then
		return
	end

	if self._screen == "tune" then
		self:_tune_action(item)
	elseif self._screen == "presets" then
		self:_open_preset(item.index)
	elseif self._screen == "detail" then
		self:_remove_part(self._offset + row)
	elseif self._screen == "picker" then
		self:_add_breed(item)
	end
end)

GrandfathersTarotView._step_row = function (self, row, delta)
	local item = self:_item_at(row)

	if not item then
		return
	end

	if self._screen == "settings" then
		if item.kind == "number" then
			self:_set_number_setting(item, item.number + delta * item.step)
		end
	elseif self._screen == "tune" then
		self:_tune_step(item, delta)
	elseif self._screen == "mods" and item.id == "fire" then
		local part = self._parts[self._part_index]

		if part then
			self:_set_burn(part, ((part.tune and part.tune.burn) or mod.rw.groups.tune_default("burn")) + delta * 10)
		end
	elseif self._screen == "detail" then
		-- a group that only repeats may have 0 initial units; otherwise at least 1
		item.count = math.clamp(item.count + delta, (item.rep or 0) > 0 and 0 or 1, mod.rw.groups.MAX_BREED_COUNT)
		self:_save()
	end
end

-- units added on every repeat tick for one enemy group (detail screen)
GrandfathersTarotView.cb_row_rep_step = guarded(function (self, row, delta)
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
GrandfathersTarotView.cb_row_same = guarded(function (self, row)
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

-- (2026-10-06) the row's own toggle (catalog/groups.lua): a Packmaster's Dogs ("(no dogs)"), a Captain's or a Twin's Shield
-- ("(no shield)"), a Daemonhost's kills before it leaves (1 > 2 > 3 > all, "(leaves 2)")
GrandfathersTarotView.cb_row_extra = guarded(function (self, row)
	local item = self._screen == "detail" and self:_item_at(row)
	local groups = mod.rw.groups
	local toggle = item and groups.row_toggle(item)

	if toggle == "dogs" then
		item.nodogs = not item.nodogs or nil
	elseif toggle == "shield" then
		item.noshield = not item.noshield or nil
	elseif toggle == "leave" then
		item.leaves = groups.next_leaves(item.leaves)
	else
		return
	end

	self:_save()
end)

GrandfathersTarotView.cb_row_rep_input = guarded(function (self, row)
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

GrandfathersTarotView.cb_row_minus = guarded(function (self, row)
	self:_step_row(row, -1)
end)

GrandfathersTarotView.cb_row_plus = guarded(function (self, row)
	self:_step_row(row, 1)
end)

GrandfathersTarotView.cb_row_value = guarded(function (self, row)
	local item = self:_item_at(row)

	if not item then
		return
	end

	if self._screen == "settings" then
		if item.kind == "number" then
			self:_open_setting_popup(item)
		end
	elseif self._screen == "mods" and item.id == "fire" then
		local part = self._parts[self._part_index]

		if part then
			Popup.open(self, { label = mod:localize("mod_fire_damage_title"), value = tostring(part.tune and part.tune.burn or mod.rw.groups.tune_default("burn")), numeric = true, integer = true, min = 0, max = 300,
				set = function (value) self:_set_burn(part, value) end })
		end
	elseif self._screen == "tune" then
		self:_tune_value(item)
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
GrandfathersTarotView._add_breed = function (self, breed)
	local groups = mod.rw.groups

	-- random group mode: clicking an enemy picks / unpicks it for the group instead of adding it
	if self._random_mode then
		local at

		for i = 1, #self._random_pick do
			if self._random_pick[i] == breed then
				at = i
			end
		end

		if at then
			table.remove(self._random_pick, at)
		else
			self._random_pick[#self._random_pick + 1] = breed
		end

		self:_apply_screen(true)

		return
	end

	-- (2026-10-05) a right click on a row of the Cauldron opened the picker to change that group's enemy: the group keeps everything
	-- else (count, repeats, modifiers, custom mods, colour experiment) and the picker goes back to the card
	local swap = self._replace_index and self._parts[self._replace_index]

	if swap then
		if self._popup then Popup.close_keep(self) end

		swap.breed, swap.one_of = breed, nil
		self._replace_index = nil
		self._screen = "detail"
		self._picker_note = nil
		self:_save()

		return
	end

	local stay = mod:get("picker_stay") == true

	-- picked while the search box was open: in "back" mode close it (keeping what was typed);
	-- in "stay" mode it stays open so the next enemy can be found right away
	if self._popup and not stay then
		Popup.close_keep(self)
	end

	local added, added_index

	for i = 1, #self._parts do
		if self._parts[i].breed == breed and not self._parts[i].mods and not self._parts[i].tune and not self._parts[i].appearance then
			self._parts[i].count = math.min(self._parts[i].count + 1, groups.MAX_BREED_COUNT)
			added = self._parts[i].count
			added_index = i

			break
		end
	end

	if not added then
		self._parts[#self._parts + 1] = { breed = breed, count = 1 }
		added = 1
		added_index = #self._parts
	end

	if stay then
		self._screen = "picker"
		self._picker_note = mod:localize("picker_added", groups.display_name(breed), added)
	else
		self._screen = "detail"
		self._picker_note = nil
		-- the list shows the group that was added (or got one more) as its last row
		self._offset = math.max(0, added_index - Workshop.ROWS)
	end

	self:_save()
end

-- Random group: turn the mode on, click two or more enemies, press Create. The group is "1 random of A / B / C"
-- (the count is changed like any other: with the - and + buttons).
GrandfathersTarotView.cb_toggle_random = guarded(function (self)
	self._random_mode = not self._random_mode
	self._random_pick = {}
	self._picker_note = nil
	self:_apply_screen(true)
end)

GrandfathersTarotView.cb_random_done = guarded(function (self)
	if #self._random_pick < 2 then
		self._picker_note = mod:localize("picker_random_need_two")
		self:_apply_screen(true)

		return
	end

	local stay = mod:get("picker_stay") == true
	local pick = { unpack(self._random_pick) }
	local swap = self._replace_index and self._parts[self._replace_index]

	-- changing a group's enemy (a right click on its row): the group becomes the random one and keeps the rest
	if swap then
		swap.one_of, swap.breed = pick, nil
		stay = false
		self._replace_index = nil
	else
		self._parts[#self._parts + 1] = { one_of = pick, count = 1 }
	end
	self._random_mode = false
	self._random_pick = {}

	if self._popup and not stay then
		Popup.close_keep(self)
	end

	self._screen = stay and "picker" or "detail"
	self._offset = stay and self._offset or math.max(0, #self._parts - Workshop.ROWS)
	self._picker_note = stay and mod:localize("picker_random_added", #pick) or nil
	self:_save()
end)

GrandfathersTarotView.cb_toggle_stay = guarded(function (self)
	mod:set("picker_stay", not (mod:get("picker_stay") == true))
	self:_apply_screen(true)
end)

GrandfathersTarotView._remove_part = function (self, index)
	if not self._wave.is_custom and #self._parts <= 1 then
		mod:echo("%s", mod:localize("msg_need_one_enemy"))

		return
	end

	table.remove(self._parts, index)
	self:_save()
end

GrandfathersTarotView.cb_rename = guarded(function (self)
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

GrandfathersTarotView.cb_edit_text = guarded(function (self)
	if self._wave and mod.rw.groups.Effects.beneficial(self._wave.suit) then return end
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

GrandfathersTarotView.cb_add = guarded(function (self)
	if self._wave and mod.rw.groups.Effects.beneficial(self._wave.suit) then return end
	self._random_mode = false
	self._random_pick = {}
	self._replace_index = nil
	self._screen = "picker"
	self._filter = ""
	self._picker_note = nil
	self:_apply_screen()
end)

-- A right click on an enemy row of the Cauldron (2026-10-05, the user: "right clicking an enemy lets you change the enemy while keeping
-- all the modifiers chosen"): the picker opens for that group; the enemy picked (or a random group made there) replaces its enemy.
GrandfathersTarotView.cb_row_swap = guarded(function (self, row)
	local index = self._offset + row
	local part = self._screen == "detail" and self._parts and self._parts[index]

	if not part or (self._wave and mod.rw.groups.Effects.beneficial(self._wave.suit)) then
		return
	end

	self._random_mode = false
	self._random_pick = {}
	self._replace_index = index
	self._screen = "picker"
	self._filter = ""
	self._picker_note = mod:localize("picker_swap", mod.rw.groups.describe_part(part))
	self:_apply_screen()
end)

-- Search box for the enemy picker. Filters live while typing (the popup sits low on the
-- screen so the list stays visible); OK keeps the filter, Cancel/Esc restores the old one.
-- `initial` (optional) replaces the box's starting text (auto-open on typing starts empty).
GrandfathersTarotView._open_search = function (self, initial)
	local original = self._filter or ""

	Popup.open(self, {
		label = mod:localize("popup_search_title"),
		hint = mod:localize("popup_search_hint"),
		value = initial or original,
		max_length = 40,
		y = 700,
		place_key = "picker_search",
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

GrandfathersTarotView.cb_search = guarded(function (self)
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

GrandfathersTarotView._auto_search = function (self, dt)
	if (self._typing_blocked or 0) > 0 then
		self._typing_blocked = self._typing_blocked - (dt or 0)
		typed_text() -- (the keys of these frames are dropped)

		return
	end

	if (self._screen ~= "picker" and self._screen ~= "list") or self._popup then
		return
	end

	local text = typed_text()

	if not text then
		return
	end

	-- (2026-10-05) on the Deck, typing opens the Deck's search the same way
	if self._screen == "list" then
		self:cb_deck_search()

		if self._popup then
			Popup.set_text(self, "")
		end
	else
		self:_open_search("")
	end

	-- The input widget reads this frame's keystrokes when it is drawn, right after this update. If
	-- it did not (it is text-empty next frame), fill the characters in ourselves, once.
	self._auto_typed = text
end

-- Next frame after an auto-open: make sure the typed characters really arrived.
GrandfathersTarotView._finish_auto_search = function (self)
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
GrandfathersTarotView._refresh_text_flag = function (self)
	if mod.rw then
		mod.rw.text_input_active = self._popup ~= nil or self._screen == "picker"
	end
end

GrandfathersTarotView.cb_toggle_enabled = guarded(function (self)
	set_setting("on_" .. self._key, not self._wave.enabled)
	self:_reload()
	self:_apply_screen(true)
end)

-- Reset: a standard card goes back to the default deck's; a custom card's "Clear this card" empties it (2026-10-06: it used to
-- give the default deck's custom card back, so a card of that deck could not be cleared)
GrandfathersTarotView.cb_reset = guarded(function (self)
	mod.rw.events.reset(set_setting, self._key, self._wave and self._wave.is_custom)
	self:_reload()
	self._parts = copy_parts(self._wave.parts)
	self:_apply_screen()
end)

GrandfathersTarotView.cb_chance_step = guarded(function (self, delta)
	set_setting("pct_" .. self._key, math.clamp(math.floor(self._wave.pct) + delta, 0, mod.rw.events.MAX_PCT))
	self:_reload()
	self:_apply_screen(true)
end)

GrandfathersTarotView.cb_chance_input = guarded(function (self)
	Popup.open(self, {
		label = mod:localize("popup_chance_title", self._wave.name),
		value = tostring(math.floor(self._wave.pct)),
		numeric = true, min = 0, max = mod.rw.events.MAX_PCT, integer = true,
		set = function (value)
			set_setting("pct_" .. self._key, value)
			self:_reload()
			self:_apply_screen(true)
		end,
	})
end)

-- spread radius / repeat every / repeat for -----------------------------------------

GrandfathersTarotView._setting_step = function (self, prefix, field, delta, min, max)
	set_setting(prefix .. self._key, math.clamp(math.floor(self._wave[field]) + delta, min, max))
	self:_reload()
	self:_apply_screen(true)
end

GrandfathersTarotView._setting_input = function (self, prefix, field, title_key, min, max)
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
GrandfathersTarotView.cb_spread_step = guarded(function (self, delta)
	local value = math.floor(self._wave.spread)
	local coarse = (delta > 0 and value >= 10) or (delta < 0 and value > 10)

	self:_setting_step("sp_", "spread", coarse and delta * 5 or delta, 0, 100)
end)

GrandfathersTarotView.cb_spread_input = guarded(function (self)
	self:_setting_input("sp_", "spread", "popup_spread_title", 0, 100)
end)

GrandfathersTarotView.cb_every_step = guarded(function (self, delta)
	self:_setting_step("re_", "rep_every", delta, 1, 600)
end)

GrandfathersTarotView.cb_every_input = guarded(function (self)
	self:_setting_input("re_", "rep_every", "popup_every_title", 1, 600)
end)

GrandfathersTarotView.cb_for_step = guarded(function (self, delta)
	self:_setting_step("rf_", "rep_for", delta, 0, 3600)
end)

GrandfathersTarotView.cb_for_input = guarded(function (self)
	self:_setting_input("rf_", "rep_for", "popup_for_title", 0, 3600)
end)

-- this wave's own spawn distances (0 = auto: the values from the options menu)
GrandfathersTarotView.cb_dmin_step = guarded(function (self, delta)
	self:_setting_step("dmin_", "dmin", delta, 0, 200)
end)

GrandfathersTarotView.cb_dmin_input = guarded(function (self)
	self:_setting_input("dmin_", "dmin", "popup_dmin_title", 0, 200)
end)

GrandfathersTarotView.cb_dmax_step = guarded(function (self, delta)
	self:_setting_step("dmax_", "dmax", delta, 0, 200)
end)

GrandfathersTarotView.cb_dmax_input = guarded(function (self)
	self:_setting_input("dmax_", "dmax", "popup_dmax_title", 0, 200)
end)

-- Fixed timer: from "off" the first + gives 30 s; 5 s steps up to 60 s, then 15 s up to 5 minutes, then 1 minute;
-- going down below 5 s switches it off.
local function next_timer(value, delta)
	if delta > 0 then
		if value <= 0 then
			return 30
		end

		return math.min(3600, value + (value < 60 and 5 or (value < 300 and 15 or 60)))
	end

	local next_value = value - (value <= 60 and 5 or (value <= 300 and 15 or 60))

	return next_value < 5 and 0 or next_value
end

GrandfathersTarotView.cb_timer_step = guarded(function (self, delta)
	set_setting("ev_" .. self._key, next_timer(math.floor(self._wave.timer), delta))
	self:_reload()
	self:_apply_screen(true)
end)

GrandfathersTarotView.cb_timer_input = guarded(function (self)
	Popup.open(self, {
		label = mod:localize("popup_timer_title", self._wave.name),
		value = tostring(math.floor(self._wave.timer)),
		numeric = true, min = 0, max = 3600, integer = true,
		set = function (value)
			set_setting("ev_" .. self._key, (value > 0 and value < 5) and 5 or value)
			self:_reload()
			self:_apply_screen(true)
		end,
	})
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

GrandfathersTarotView.cb_presets = guarded(function (self)
	self._preset_note = nil
	self:_reload_presets()
	self._screen = "presets"
	self:_apply_screen()
end)

GrandfathersTarotView._current_preset_slot = function (self)
	return self._preset_slots[self._preset_index]
end

-- Stores the current setup in the open slot (keeping the slot's name).
GrandfathersTarotView.cb_preset_save = guarded(function (self)
	local rw = mod.rw
	local slot = self:_current_preset_slot()
	local captured = rw.presets.capture(get_setting, rw.events, rw.groups)

	captured.name = slot.preset and slot.preset.name or rw.presets.default_name(self._preset_index)
	rw.presets.write(set_setting, rw.presets.slot_id(self._preset_index), captured)
	self:_refresh_preset(mod:localize("preset_saved", captured.name, #captured.waves))
end)

-- Replaces the current setup with the slot's. The setup being replaced is kept for "Undo last load".
GrandfathersTarotView.cb_preset_load = guarded(function (self)
	local rw = mod.rw
	local slot = self:_current_preset_slot()

	-- a damaged slot cannot be loaded; an EMPTY slot is a blank preset: loading it gives the default waves
	if not slot.preset and slot.problem then
		self:_refresh_preset(mod:localize("preset_nothing_to_load"))

		return
	end

	local backup = rw.presets.capture(get_setting, rw.events, rw.groups)

	backup.name = mod:localize("preset_undo_name")
	rw.presets.write(set_setting, rw.presets.UNDO_ID, backup)

	local blank = slot.preset == nil
	local written = 0

	if blank then
		rw.presets.restore_defaults(set_setting, rw.events)
	else
		written = rw.presets.apply(slot.preset, set_setting, rw.events, rw.groups)
	end

	self:_reload()
	self:_refresh_preset(blank and mod:localize("preset_loaded_blank", slot.index) or mod:localize("preset_loaded", slot.name, written))
end)

GrandfathersTarotView.cb_preset_undo = guarded(function (self)
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

GrandfathersTarotView.cb_preset_rename = guarded(function (self)
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
GrandfathersTarotView.cb_preset_export = guarded(function (self)
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
GrandfathersTarotView.cb_preset_import = guarded(function (self)
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

GrandfathersTarotView.cb_preset_clear = guarded(function (self)
	local rw = mod.rw

	rw.presets.clear(set_setting, rw.presets.slot_id(self._preset_index))
	self:_refresh_preset(mod:localize("preset_cleared"))
end)

-- sharing one wave -------------------------------------------------------------
-- Same text idea as the presets, for a single wave: "RWW1|...|check".

-- Share (detail screen): shows this wave as text (and copies it). Pasting a friend's wave over the text and
-- pressing OK replaces THIS wave with it.
GrandfathersTarotView.cb_wave_share = guarded(function (self)
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
GrandfathersTarotView.cb_wave_import = guarded(function (self)
	local rw = mod.rw
	local free

	for i = 1, #self._waves do
		local wave = self._waves[i]

		if wave.is_custom and not (mod.rw.events.has_content(wave)) then
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

-- The "?" tooltip of the screen (ui/help_text.lua): its title, the body in the game's text markup, and the panel cut to the text's
-- height (the shadow, the panel, the strip and the side frames as high as it, the bottom frame and the footer moved under it).
GrandfathersTarotView._layout_help = function (self)
	local widgets = self._widgets_by_name
	local panel, body = widgets.help_panel, widgets.help_text

	if not panel or not body then return end

	local title, text, height = Help.format(mod:localize(self._help_key or "hint_list"), Help.WIDTH - 2 * Help.PAD, Components.accent)
	local style = panel.style
	local H = Help.panel_height(height)

	body.content.help_text = text
	body.style.help_text.size[2] = height + 12
	panel.content.title = title or mod:localize("help_title")
	panel.content.badge_mark = "?"
	panel.content.footer = mod:localize(self._help_pinned and "help_footer_pinned" or "help_footer")
	self._help_shown_pinned = self._help_pinned

	for _, id in ipairs({ "shadow", "bg", "strip", "frame_l", "frame_r" }) do
		style[id].size[2] = H
	end

	style.frame_b.offset[2] = H - 1
	style.footer.offset[2] = H - Help.FOOT + 6
end

-- help tooltip ("?" corner button): hover shows it, a click pins it open (for a pointer that cannot hover)
GrandfathersTarotView.cb_help = function (self)
	self._help_pinned = not self._help_pinned
end

-- (2026-10-05) The Deck's four draw buttons: every beneficial card (the four blessing suits) or every enemy card goes into the
-- draw (on) or out of it (off). Returns how many cards changed.
GrandfathersTarotView.set_kind_in_draw = function (self, beneficial, on)
	local rw, changed = mod.rw, 0

	for _, wave in ipairs(self._waves or {}) do
		local suit = rw.cards.suit(wave.suit)
		local is_ben = suit ~= nil and suit.beneficial == true

		if is_ben == beneficial and wave.enabled ~= on then
			set_setting("on_" .. wave.key, on)
			changed = changed + 1
		end
	end

	return changed
end

GrandfathersTarotView.cb_draw_kind = guarded(function (self, which)
	local beneficial, on = which:sub(1, 3) == "ben", which:sub(-2) == "on"
	local changed = self:set_kind_in_draw(beneficial, on)

	self:_reload()
	self:_apply_screen(true)
	mod:echo("%s", mod:localize("msg_draw_kind", changed))
end)

-- Restore defaults (list screen): every wave back to the built-in setup, deleted waves included. Needs a second
-- click; the replaced setup is kept for "Undo last load" on the Presets screen.
GrandfathersTarotView.cb_defaults = guarded(function (self)
	local rw = mod.rw

	if self._confirm and self._confirm.key == "__defaults" and (self._t or 0) <= self._confirm.expires then
		self._confirm = nil

		local backup = rw.presets.capture(get_setting, rw.events, rw.groups)

		backup.name = mod:localize("preset_undo_name")
		rw.presets.write(set_setting, rw.presets.UNDO_ID, backup)
		rw.presets.restore_defaults(set_setting, rw.events)
		rw.events.set_order(set_setting, {})
		set_setting("deck_sort", "")

		-- (2026-10-06) the default deck's own order and sort (catalog/user_defaults.lua)
		for setting, value in pairs(rw.events.UserDefaults.deck) do
			if setting:find("^deck_") then set_setting(setting, value) end
		end
		self:_reload()
		self:_apply_screen()
		mod:echo("%s", mod:localize("msg_defaults_restored"))

		return
	end

	self._confirm = { key = "__defaults", expires = (self._t or 0) + 4 }
	self:_apply_screen(true)
end)

-- time between waves (list screen): 5 s steps below a minute, 15 s up to 5 minutes, then a minute
local function next_time(value, delta)
	local step

	if delta > 0 then
		step = value < 60 and 5 or (value < 300 and 15 or 60)
	else
		step = value <= 60 and 5 or (value <= 300 and 15 or 60)
	end

	return math.clamp(value + delta * step, 5, 1800)
end

GrandfathersTarotView._set_time = function (self, id, value)
	value = math.clamp(math.floor(value + 0.5), 5, 1800)
	set_setting(id, value)

	-- the maximum never ends up below the minimum
	local low = tonumber(mod:get("interval_min")) or 75
	local high = tonumber(mod:get("interval_max")) or 75

	if id == "interval_min" and value > high then
		set_setting("interval_max", value)
	elseif id == "interval_max" and value < low then
		set_setting("interval_min", value)
	end

	self:_apply_screen(true)
end

GrandfathersTarotView.cb_tmin_step = guarded(function (self, delta)
	self:_set_time("interval_min", next_time(tonumber(mod:get("interval_min")) or 75, delta))
end)

GrandfathersTarotView.cb_tmax_step = guarded(function (self, delta)
	self:_set_time("interval_max", next_time(tonumber(mod:get("interval_max")) or 75, delta))
end)

local function time_popup(self, id, label_key, default)
	Popup.open(self, {
		label = mod:localize(label_key),
		value = tostring(math.floor(tonumber(mod:get(id)) or default)),
		numeric = true, min = 5, max = 1800, integer = true,
		set = function (value)
			self:_set_time(id, value)
		end,
	})
end

GrandfathersTarotView.cb_tmin_input = guarded(function (self)
	time_popup(self, "interval_min", "set_interval_min", 75)
end)

GrandfathersTarotView.cb_tmax_input = guarded(function (self)
	time_popup(self, "interval_max", "set_interval_max", 75)
end)
-- popup ------------------------------------------------------------------------

GrandfathersTarotView.cb_popup_confirm = function (self)
	Popup.commit(self)
end

GrandfathersTarotView.cb_popup_cancel = function (self)
	Popup.cancel(self)
end

return GrandfathersTarotView
