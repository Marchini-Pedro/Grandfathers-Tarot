-- The Cauldron (the screen "detail", docs/08-workshop-redesign.md): the enemies of one card on the left (rows, the shelf of
-- common enemies, the spawn settings, the action bar) and the card itself on the right at 1.4 times its Deck size with the
-- quick face under it (suit, threat, chance). Everything the player changes is written to the card's settings at once and the
-- card on the right is painted again, so it follows every click. Where things sit is in ui/workshop.lua, the widgets in
-- ui/workshop_blueprints.lua. Installed on the view with `install` (see wave_editor_view.lua).
local mod = get_mod("GrandfathersTarot")

local WorkshopView = {}

local UIWidget = require("scripts/managers/ui/ui_widget")
local LastDefs = mod:io_dofile("GrandfathersTarot/scripts/mods/GrandfathersTarot/ui/hud_element_last_card_definitions")
local LastPaint = mod:io_dofile("GrandfathersTarot/scripts/mods/GrandfathersTarot/ui/last_card_paint")

local PREVIEW_SECONDS = 5 -- the cooldown preview of the stage card plays through its look in this time
local MOD_CHARS, INFO_CHARS = 22, 40 -- the modifiers of a row are cut at 22 visible characters, the line at 40
-- (2026-10-05, the user's picture: "1 random of Beast of Nurgle / Chaos Spawn / Packmaster / Plague Ogryn" ran over three lines, over
-- the header and the modifier line) a row's name is one line: its font shrinks from 26 down to 17 to fit, then it is cut with "..."
local NAME_FONT, NAME_FONT_MIN, NAME_GLYPH = 26, 17, 0.6

-- The font of a row's name that fits `visible` characters on one line `width` wide (NAME_FONT down to NAME_FONT_MIN), and how many
-- characters fit at that font (a longer name is cut to that many with "...").
local FIT = { font = NAME_FONT, chars = 0 }

WorkshopView.fit_name = function (visible, width)
	local font = math.max(NAME_FONT_MIN, math.min(NAME_FONT, math.floor(width / (math.max(1, visible) * NAME_GLYPH))))

	FIT.font, FIT.chars = font, math.floor(width / (font * NAME_GLYPH))

	return FIT
end

-- The colour of a group's colour experiment for the mark on its row (nil: no experiment). The skin effects have their own colour
-- (their colour channels do nothing); a colour too dark to see on the row is shown in a pale lilac.
local SKIN_RGB = { skin_burnt = { 232, 120, 40 }, skin_warp = { 96, 160, 255 }, skin_bruise = { 156, 116, 178 } }
local DARK_PAINT = { 190, 170, 220 }

WorkshopView.paint_rgb = function (appearance)
	if type(appearance) ~= "table" or ((appearance.method or "none") == "none" and not appearance.outline) then
		return nil
	end

	local skin = SKIN_RGB[appearance.method]

	if skin then
		return skin
	end

	local r, g, b = tonumber(appearance.r) or 0, tonumber(appearance.g) or 0, tonumber(appearance.b) or 0

	if math.max(r, g, b) < 60 then
		return DARK_PAINT
	end

	return { r, g, b }
end

WorkshopView.install = function (View, h)
	local Workshop, Spread, TILE_IDS, definitions = h.Workshop, h.Spread, h.TILE_IDS, h.definitions
	local guarded, set_setting, Components, with_faction = h.guarded, h.set_setting, h.Components, h.with_faction
	local shelf = definitions.shelf_layout
	local ERROW, CHIP, SUIT, STAGE = definitions.ERROW_NODE_PREFIX, definitions.CHIP_NODE_PREFIX, definitions.SUIT_NODE_PREFIX, definitions.STAGE_CARD_NODE

	-- the widgets that exist only while the Cauldron is shown (its buttons are shown with the other buttons, see _apply_screen)
	local STATIC = { "enemy_header", "shelf_panel", "quick_label", "threat_label", "threat_name", "spawn_label" }
	-- the stage: on the Cauldron and on the Mirror
	local STAGE_WIDGETS = { "stage_plate", "stage_caption", "stage_stats", STAGE }
	local ROW_HOTSPOTS = { "hotspot_name", "hotspot_minus", "hotspot_value", "hotspot_plus", "hotspot_rep_minus", "hotspot_rep_value", "hotspot_rep_plus", "hotspot_same", "hotspot_mods", "hotspot_tune", "hotspot_action" }

	-- every dynamic widget of the Cauldron by name (rows, chips, suit tiles, the threat control, the stage card)
	local DYNAMIC = { "rw_threat" }

	for i = 1, Workshop.ROWS do
		DYNAMIC[#DYNAMIC + 1] = ERROW .. i
	end

	for i = 1, #shelf.chips do
		DYNAMIC[#DYNAMIC + 1] = CHIP .. i
	end

	for i = 1, #mod.rw.cards.SUIT_ORDER do
		DYNAMIC[#DYNAMIC + 1] = SUIT .. i
	end

	View.WORKSHOP_ROW_HOTSPOTS = ROW_HOTSPOTS

	-- ------------------------------------------------------------------------------------------ creation
	View._create_workshop_widgets = function (self, blueprints, WB)
		for i = 1, Workshop.ROWS do
			local name = ERROW .. i
			local widget = self:_create_dynamic_widget(name, WB.enemy_row(name))
			local content = widget.content

			content.hotspot_minus.pressed_callback = callback(self, "cb_row_minus", i)
			content.hotspot_value.pressed_callback = callback(self, "cb_row_value", i)
			content.hotspot_plus.pressed_callback = callback(self, "cb_row_plus", i)
			content.hotspot_action.pressed_callback = callback(self, "cb_row_action", i)
			content.hotspot_mods.pressed_callback = callback(self, "cb_row_mods", i)
			content.hotspot_name.right_pressed_callback = callback(self, "cb_row_swap", i)
			content.hotspot_tune.pressed_callback = callback(self, "cb_row_tune", i)
			content.hotspot_rep_minus.pressed_callback = callback(self, "cb_row_rep_step", i, -1)
			content.hotspot_rep_plus.pressed_callback = callback(self, "cb_row_rep_step", i, 1)
			content.hotspot_rep_value.pressed_callback = callback(self, "cb_row_rep_input", i)
			content.hotspot_same.pressed_callback = callback(self, "cb_row_same", i)
			widget.visible = false
		end

		for i = 1, #shelf.chips do
			local name = CHIP .. i
			local widget = self:_create_dynamic_widget(name, WB.shelf_chip(name, shelf.chips[i].w))

			widget.content.hotspot.pressed_callback = callback(self, "cb_shelf_add", i)
			widget.visible = false
		end

		for i = 1, #mod.rw.cards.SUIT_ORDER do
			local name = SUIT .. i
			local widget = self:_create_dynamic_widget(name, WB.suit_tile(name, TILE_IDS))

			widget.content.hotspot.pressed_callback = callback(self, "cb_suit_pick", i)
			widget.visible = false
		end

		local threat = self:_create_dynamic_widget("rw_threat", WB.threat_control("rw_threat"))

		for k = 1, 6 do
			threat.content["hotspot_t" .. k].pressed_callback = callback(self, "cb_threat_pick", k)
		end

		threat.visible = false

		-- the card on its stage: the Deck's tile at 1.4 times its size. The Deck's click areas are off (it is not a button); its name
		-- and its line are click areas: the name renames the card, the line opens the whisper box
		local stage = self:_create_dynamic_widget(STAGE, blueprints.tile(STAGE, Workshop.CARD_SCALE, true))

		for _, hotspot in ipairs(self.TILE_HOTSPOTS) do
			stage.content[hotspot].disabled = true
		end

		stage.content.hotspot_name.pressed_callback = callback(self, "cb_rename")
		stage.content.hotspot_whisper.pressed_callback = callback(self, "cb_whisper_change")
		stage.content.hotspot_share.pressed_callback = callback(self, "cb_wave_share")

		-- (2026-10-05) the card's chance and cooldown are set on the card itself, as on the Deck: a pip sets the chance, the minus and
		-- the plus of the cooldown row step it, its value opens the number box
		for k = 1, h.Deck.PIPS do
			stage.content[h.TILE_IDS.hotspot_pip[k]].pressed_callback = callback(self, "cb_stage_pip", k)
		end

		stage.content.hotspot_cd_minus.pressed_callback = callback(self, "cb_cooldown_step", -1)
		stage.content.hotspot_cd_plus.pressed_callback = callback(self, "cb_cooldown_step", 1)
		stage.content.hotspot_cd_value.pressed_callback = callback(self, "cb_cooldown_input")

		stage.visible = false
		self:_create_mirror_widgets(WB)
	end

	-- ------------------------------------------------------------------------------------------ visibility
	View._hide_cauldron = function (self)
		local widgets = self._widgets_by_name

		for _, name in ipairs(STATIC) do
			if widgets[name] then
				widgets[name].visible = false
			end
		end

		for _, name in ipairs(DYNAMIC) do
			if widgets[name] then
				widgets[name].visible = false
			end
		end

		-- (the stage is shared: it goes with the Mirror when this is not the Cauldron or the Mirror)
		if self._screen ~= "face" then
			for _, name in ipairs(STAGE_WIDGETS) do
				if widgets[name] then
					widgets[name].visible = false
				end
			end

			self._preview = nil
		end
	end

	-- Enables or disables the hotspots of the Cauldron's dynamic widgets (a popup locks them all).
	View._set_cauldron_interaction = function (self, enabled)
		local widgets = self._widgets_by_name

		for i = 1, Workshop.ROWS do
			local widget = widgets[ERROW .. i]

			if widget then
				for _, id in ipairs(ROW_HOTSPOTS) do
					widget.content[id].disabled = not (enabled and widget.visible)
				end
			end
		end

		for i = 1, #shelf.chips do
			local widget = widgets[CHIP .. i]

			if widget then
				widget.content.hotspot.disabled = not (enabled and widget.visible)
			end
		end

		for i = 1, #mod.rw.cards.SUIT_ORDER do
			local widget = widgets[SUIT .. i]

			if widget then
				widget.content.hotspot.disabled = not (enabled and widget.visible)
			end
		end

		local threat = widgets.rw_threat

		if threat then
			for k = 1, 6 do
				threat.content["hotspot_t" .. k].disabled = not (enabled and threat.visible)
			end
		end

		self:_set_stage_interaction(enabled)
	end

	-- the stage card's name and line (shared by the Cauldron and the Mirror)
	View._set_stage_interaction = function (self, enabled)
		local stage = self._widgets_by_name[STAGE]

		if stage then
			stage.content.hotspot_share.disabled = not (enabled and stage.visible and mod:get("card_share_icons") ~= false)
			stage.content.hotspot_name.disabled = not (enabled and stage.visible)
			stage.content.hotspot_whisper.disabled = not (enabled and stage.visible)

			local on = enabled and stage.visible
			local timer = self._wave and (tonumber(self._wave.timer) or 0) > 0

			for k = 1, h.Deck.PIPS do
				stage.content[h.TILE_IDS.hotspot_pip[k]].disabled = not on
			end

			for _, id in ipairs({ "hotspot_cd_minus", "hotspot_cd_plus", "hotspot_cd_value" }) do
				stage.content[id].disabled = not on or timer
			end
		end
	end

	-- a pip of the card on the stage: the card's chance becomes that number
	View.cb_stage_pip = guarded(function (self, level)
		if self._key and self._wave then
			set_setting("pct_" .. self._key, mod.rw.cards.weight_for_level(level))
			self:_reload()
			self:_apply_screen(true)
		end
	end)

	-- ------------------------------------------------------------------------------------------ hostile or beneficial suits
	-- Which suits the quick face and the Mirror show: the twelve hostile ones or the four beneficial ones (2026-10-04, the switch that
	-- replaced Auto | By hand). It follows the card's own suit until the switch is clicked, and again after a suit is picked.
	View._suit_view = function (self)
		local key = self._wave and self._wave.key

		if self._suit_view_key ~= key then
			self._suit_view_key, self._suit_kind = key, nil
		end

		if not self._suit_kind then
			self._suit_kind = self._wave and mod.rw.cards.suit(self._wave.suit).beneficial and "ben" or "hostile"
		end

		return self._suit_kind
	end

	-- the suit `index` of Cards.SUIT_ORDER: shown under the switch's choice, and its place among the suits shown (1-based)
	View._suit_slot = function (self, index)
		local Cards = mod.rw.cards
		local ben = self:_suit_view() == "ben"
		local suit_ben = index > Cards.HOSTILE_COUNT

		return suit_ben == ben, ben and index - Cards.HOSTILE_COUNT or index
	end

	View.cb_suit_view = guarded(function (self, kind)
		if (self._screen == "detail" or self._screen == "face") and (kind == "hostile" or kind == "ben") then
			self:_suit_view()
			self._suit_kind = kind
			self:_apply_screen(true)
		end
	end)

	View._paint_kind_switch = function (self)
		local widgets = self._widgets_by_name
		local kind = self:_suit_view()

		widgets.btn_kind_hostile.content.hotspot_text = mod:localize("btn_kind_hostile")
		widgets.btn_kind_hostile.content.hotspot_on = kind == "hostile"
		widgets.btn_kind_ben.content.hotspot_text = mod:localize("btn_kind_ben")
		widgets.btn_kind_ben.content.hotspot_on = kind == "ben"
	end

	-- ------------------------------------------------------------------------------------------ the rows
	-- One enemy group on its row: the name (the weight in front of it, the faction after it), the modifiers and custom mods
	-- under it, the two steppers, the Same diamond, the chips. The edge and the name take the enemy's colour.
	View._fill_enemy_row = function (self, widget, item)
		local rw = mod.rw
		local groups, colors = rw.groups, rw.colors
		local content = widget.content
		local name_color = Components.colors.text
		local mods_text = groups.describe_mods(item)
		local mods_shown = mods_text
		local painter = self:_painter()

		local plain_name = groups.describe_part(item)
		local suffix = item.breed and groups.faction_suffix(item.breed)
		local name_fit = WorkshopView.fit_name(#plain_name + (suffix and #suffix + 2 or 0), Workshop.COL.name_w)
		local name_chars = name_fit.chars - (suffix and #suffix + 2 or 0)

		content.row_name = #plain_name > name_chars and plain_name:sub(1, math.max(1, name_chars - 3)) .. "..." or plain_name
		widget.style.row_name.font_size = name_fit.font

		-- a random group colours each enemy of the group, the modifier names get their own colours; the modifier text is cut at
		-- MOD_CHARS visible characters WITHOUT losing the colours
		if painter then
			if item.one_of then
				content.row_name = groups.render_segments(groups.paint_part_segments(item, painter, false), name_chars, painter.markup)
			end

			local _, modifiers = groups.describe_part_pieces(item)
			local segments = {}

			for i = 1, #modifiers do
				if i > 1 then
					segments[#segments + 1] = { text = ", " }
				end

				segments[#segments + 1] = { text = modifiers[i].name, rgb = painter.mod(modifiers[i].id) }
			end

			local shown_len = 0

			for i = 1, #segments do
				shown_len = shown_len + #segments[i].text
			end

			mods_shown = groups.render_segments(segments, MOD_CHARS, painter.markup)

			-- then the custom mods, in what is left of the line
			local tune_text = groups.tune_text(item.tune)

			if tune_text ~= "" then
				local room = INFO_CHARS - math.min(shown_len, MOD_CHARS) - 5

				if #tune_text > room then
					tune_text = tune_text:sub(1, math.max(3, room - 3)) .. "..."
				end

				mods_shown = mods_shown .. (shown_len > 0 and "  |  " or "") .. tune_text
			end
		elseif #mods_text > MOD_CHARS then
			mods_shown = mods_text:sub(1, MOD_CHARS - 3) .. "..."
		end

		-- without colours the custom mods follow the modifiers, cut like them and never wider than the line
		if not painter then
			local tune_plain = groups.tune_text(item.tune)

			if tune_plain ~= "" then
				mods_shown = (mods_text ~= "" and (mods_text .. "  |  ") or "") .. tune_plain
			end

			if #mods_shown > INFO_CHARS then
				mods_shown = mods_shown:sub(1, INFO_CHARS - 3) .. "..."
			end
		end

		content.row_name = with_faction(rw, item.breed, content.row_name)
		content.paint_rgb = WorkshopView.paint_rgb(item.appearance)
		content.info = mods_shown

		-- with no modifier line under it the name is centred in the row, like the steppers beside it
		local has_info = mods_shown ~= ""

		widget.style.row_name.offset[2], widget.style.row_name.size[2] = has_info and 1 or 0, has_info and 30 or Workshop.ROW_H
		content.stepper_value = tostring(item.count)
		content.same_selected = item.rep_same == true
		-- with "same" ticked the repeat number is the initial count, shown as "="
		content.rep_value = item.rep_same and "=" or tostring(item.rep or 0)
		content.hotspot_action_text = mod:localize("btn_remove")
		content.hotspot_mods_text = mod:localize("btn_mods")
		content.hotspot_tune_text = mod:localize("btn_tune")
		content.hotspot_mods_on = item.mods ~= nil and #item.mods > 0
		content.hotspot_tune_on = groups.tune_text(item.tune) ~= ""

		if colors and item.breed then
			name_color = colors.argb(item.breed) or name_color
		end

		Components.color_into(widget.style.row_name.text_color, name_color)
		content.edge_rgb = colors and item.breed and colors.rgb(item.breed) or Components.rgb.muted
	end

	-- True when the card has this enemy as a plain group (no modifiers, no custom mods): the shelf's chip is lit.
	View._card_has_plain = function (self, breed)
		for i = 1, #self._parts do
			local part = self._parts[i]

			if part.breed == breed and not part.mods and not part.tune and not part.appearance then
				return true
			end
		end

		return false
	end

	-- ------------------------------------------------------------------------------------------ the whole screen
	-- (Re)paints the Cauldron: the rows, the shelf, the stage and the quick face. Called by _refresh_rows for the screen "detail".
	View._refresh_cauldron = function (self)
		local widgets = self._widgets_by_name
		local rw = mod.rw
		local Cards, groups, colors = rw.cards, rw.groups, rw.colors
		local wave = self._wave

		self._tile_shape = self._tile_shape or Spread.new_shape(Spread.ICON_TRIS, Spread.ICON_CIRCS)

		for _, name in ipairs(STATIC) do
			if widgets[name] then
				widgets[name].visible = true
			end
		end

		local header = widgets.enemy_header.content

		header.col_1, header.col_2, header.col_3, header.col_4 = mod:localize("col_enemy"), mod:localize("col_count"), mod:localize("col_repeat"), mod:localize("col_same")

		for i = 1, Workshop.ROWS do
			local widget = widgets[ERROW .. i]
			local item = self._parts[self._offset + i]

			widget.visible = item ~= nil

			if item then
				self:_fill_enemy_row(widget, item)
			end
		end

		-- the shelf: the Dreg / Scab switch decides which breed a role adds; a chip is lit when the card has that enemy
		local faction = self._faction or "scab"
		local panel = widgets.shelf_panel.content

		panel.shelf_title = string.upper(mod:localize("shelf_title"))
		panel.shelf_hint = mod:localize("shelf_hint")
		panel.faction_label = mod:localize("faction_adds")

		for i = 1, #shelf.bands do
			panel["band_" .. i] = string.upper(mod:localize("band_" .. shelf.bands[i].id))
		end

		widgets.btn_dreg.content.hotspot_text = mod:localize("faction_dreg")
		widgets.btn_dreg.content.hotspot_on = faction == "dreg"
		widgets.btn_scab.content.hotspot_text = mod:localize("faction_scab")
		widgets.btn_scab.content.hotspot_on = faction == "scab"

		for i = 1, #shelf.chips do
			local chip = shelf.chips[i]
			local widget = widgets[CHIP .. i]
			local content = widget.content
			local breed = groups.shelf_breed(chip.entry, faction)

			widget.visible = true
			content.chip_label = groups.shelf_label(chip.entry)
			-- plain chips like the design page's (2026-10-04): the Dreg / Scab switch says which faction a click adds
			content.tint = false
			content.dot_rgb = colors and colors.rgb(breed) or Components.rgb.muted
			content.hotspot_on = self:_card_has_plain(breed)
		end

		widgets.spawn_label.content.spawn_label = string.upper(mod:localize("spawn_label"))

		local card = self:_refresh_stage()

		-- the quick face: the twelve suits (the chosen one lifted, the suggested one marked), the threat, the chance
		local suggested = Cards.suggest_suit(wave.parts or {}, groups)

		widgets.quick_label.content.quick_label = string.upper(mod:localize("quick_label"))
		widgets.threat_label.content.threat_label = string.upper(mod:localize("lbl_threat"))
		widgets.btn_quickface.content.hotspot_text = mod:localize("btn_quickface")
		widgets.btn_preview.content.hotspot_text = mod:localize("btn_preview_cooldown")

		self:_paint_kind_switch()

		for i = 1, #mod.rw.cards.SUIT_ORDER do
			local id = Cards.SUIT_ORDER[i]
			local def = Cards.SUITS[id]
			local widget = widgets[SUIT .. i]
			local content = widget.content
			local shown, place = self:_suit_slot(i)
			local x, y = Workshop.suit_pos(place)

			widget.visible = shown
			content.suit_name = string.upper(def.name)
			content.suit.card, content.suit.hi, content.suit.frame, content.suit.text, content.suit.accent = def.card, def.hi, def.frame, def.text, def.accent
			content.selected = id == card.suit
			content.suggested = suggested == id and id ~= card.suit
			self:_set_scenegraph_position(SUIT .. i, x, content.selected and y - 4 or y, 3)
			self:_paint_suit_mark(widget.style, def.icon, 24, (Workshop.SUIT_W - 24) / 2, 4, def.accent, def.card)
		end

		local threat = widgets.rw_threat

		threat.visible = true
		threat.content.threat, threat.content.suit = card.threat, card.suit

		-- the threat's name beside the diamonds: level 6 is DESPAIR (APOTHEOSIS on a beneficial card)
		local six = Cards.threat_name(card.threat, card.suit)

		widgets.threat_name.content.threat_name = six and mod:localize("threat_level_six", string.upper(six)) or mod:localize("threat_level", card.threat)
	end

	-- The stage, shared by the Cauldron and the Mirror: the card as the Deck draws it, 1.4 times as big, on a plate in the suit's
	-- colours, the line under it, the toolbar (In the draw, Preview cooldown). Returns Cards.describe of the card.
	View._refresh_stage = function (self)
		local widgets = self._widgets_by_name
		local rw = mod.rw
		local Cards, groups = rw.cards, rw.groups
		local wave = self._wave
		local suit = Cards.suit(wave.suit)
		local stage = widgets[STAGE]

		self._tile_shape = self._tile_shape or Spread.new_shape(Spread.ICON_TRIS, Spread.ICON_CIRCS)

		for _, name in ipairs(STAGE_WIDGETS) do
			if widgets[name] then
				widgets[name].visible = true
			end
		end

		stage.content.cd_buttons_always = true -- the cooldown's minus and plus are shown: the card on the stage takes them (2026-10-05)
		self:_paint_tile(stage, wave)

		local plate = widgets.stage_plate.content.stage

		plate.card, plate.frame, plate.accent = suit.card, suit.frame, suit.accent

		local colors = rw.colors
		local card = Cards.describe(wave, groups, function (breed)
			return colors and colors.rgb(breed) or Cards.BASE.muted
		end)
		local share = self:_share_of(wave)

		widgets.stage_caption.content.stage_caption = string.upper(mod:localize("stage_caption"))
		local Effects = groups.Effects
		local effects = 0

		for _ in pairs(Effects.beneficial(wave.suit) and Effects.allowed(wave.effects, wave.suit) or {}) do effects = effects + 1 end

		-- a beneficial card counts its effects, not enemies
		widgets.stage_stats.content.stage_stats = not share and mod:localize("stage_stats_off") or Effects.beneficial(wave.suit) and mod:localize(effects == 1 and "stage_stats_effect" or "stage_stats_effects", card.threat, effects, string.format("%.1f", share)) or mod:localize("stage_stats", card.threat, groups.total_count(self._parts), string.format("%.1f", share))
		widgets.btn_enabled.content.hotspot_text = mod:localize(wave.enabled and "btn_enabled_on" or "btn_enabled_off")
		widgets.btn_enabled.content.hotspot_on = wave.enabled == true
		widgets.btn_preview.content.hotspot_text = mod:localize("btn_preview_cooldown")

		return card
	end

	-- ------------------------------------------------------------------------------------------ the Mirror
	local MIRROR_STATIC = { "mirror_head_1", "mirror_head_2", "mirror_head_3", "mirror_head_4", "mirror_desc", "mirror_numbers", "hand_caption" }
	local MIRROR_BUTTONS = { "btn_whisper_change", "btn_whisper_suit", "btn_reset_face" }
	local PLATE, LOOK = definitions.PLATE_NODE_PREFIX, definitions.LOOK_NODE_PREFIX
	local LOOKS = definitions.MIRROR_LOOKS
	local MIRROR_DYNAMIC = { "rw_threat_big", "whisper_field", "rw_hand_card", "rw_last_card" }

	for i = 1, #mod.rw.cards.SUIT_ORDER do
		MIRROR_DYNAMIC[#MIRROR_DYNAMIC + 1] = PLATE .. i
	end

	for i = 1, #LOOKS do
		MIRROR_DYNAMIC[#MIRROR_DYNAMIC + 1] = LOOK .. i
	end

	View._create_mirror_widgets = function (self, WB)
		for i = 1, #mod.rw.cards.SUIT_ORDER do
			local name = PLATE .. i
			local widget = self:_create_dynamic_widget(name, WB.suit_plate(name, TILE_IDS))

			widget.content.hotspot.pressed_callback = callback(self, "cb_suit_pick", i)
			widget.visible = false
		end

		for i = 1, #LOOKS do
			local name = LOOK .. i
			-- a picture of what every card does, not a button (its hotspot stays disabled)
			self:_create_dynamic_widget(name, WB.look_plate(name, LOOKS[i])).visible = false
		end

		local big = self:_create_dynamic_widget("rw_threat_big", WB.threat_control("rw_threat_big", Workshop.MIRROR.threat_side, Workshop.MIRROR.threat_pitch, Workshop.MIRROR.threat_h))

		for k = 1, 6 do
			big.content["hotspot_t" .. k].pressed_callback = callback(self, "cb_threat_pick", k)
		end

		big.visible = false

		local field = self:_create_dynamic_widget("whisper_field", WB.whisper_field("whisper_field"))

		field.content.hotspot.pressed_callback = callback(self, "cb_whisper_change")
		field.visible = false

		self:_create_dynamic_widget("rw_hand_card", WB.hand_card("rw_hand_card", TILE_IDS)).visible = false

		-- the last card window of the HUD, painted by the HUD's own painter (ui/last_card_paint.lua)
		local last = self:_create_dynamic_widget("rw_last_card", UIWidget.create_definition(LastDefs.passes, "rw_last_card"))

		last.visible = false
		self._last_preview = LastPaint.new(last)
	end

	-- The card as the Spread draws it, at 1.5 times: the bar and the background as high as the lines of the name need (the HUD's
	-- rule: 76 high at least), the name, the mark, the diamonds and the dots in the places of the HUD (ui/spread.lua), all times 1.5.
	View._paint_hand = function (self, widget, card, suit)
		local H = Workshop.HAND
		local k = H.scale
		local style, content = widget.style, widget.content
		local rw = mod.rw
		local pad, icon = H.pad, H.icon
		local name_w = H.hud_w - H.bar - 2 * pad - icon - 6
		local lines = Spread.wrap_lines(card.name, name_w, H.name_font, Spread.GLYPH_BY_FONT.itc_novarese_bold)
		local height = math.max(Spread.MIN_CARD_HEIGHT, 2 * Spread.PAD_Y + lines * Spread.NAME_LINE + 4 + Spread.ROW_HEIGHT) * k

		style.hand_bg.size[2], style.hand_bar.size[2] = height, height
		Spread.set_color(style.hand_bg.color, 255, suit.card)
		Spread.set_color(style.hand_bar.color, 255, suit.accent)

		-- Heresy: the two unit thick frame the HUD gives it (the HUD's scale is k)
		local line, special = 2 * k, suit.special == true
		local edges = { t = { 0, 0, H.w, line }, b = { 0, height - line, H.w, line }, l = { 0, 0, line, height }, r = { H.w - line, 0, line, height } }

		for side, box in pairs(edges) do
			local edge = style["hand_edge_" .. side]

			edge.visible = special
			edge.offset[1], edge.offset[2], edge.size[1], edge.size[2] = box[1], box[2], box[3], box[4]
			Spread.set_color(edge.color, 255, suit.frame)
		end

		content.hand_name = card.name
		style.hand_name.offset[1], style.hand_name.offset[2] = (H.bar + pad) * k, Spread.PAD_Y * k
		style.hand_name.size[1], style.hand_name.size[2] = name_w * k, lines * Spread.NAME_LINE * k
		Spread.set_color(style.hand_name.text_color, 255, suit.text)

		self:_paint_suit_mark(style, suit.icon, icon * k, (H.hud_w - pad - icon) * k, Spread.PAD_Y * k, suit.accent, suit.card)

		-- the bottom row: the threat diamonds from the left, the dots to the right
		local cy = height - (Spread.PAD_Y + Spread.ROW_HEIGHT / 2) * k
		local side = Spread.THREAT_SIDE * k
		local threat_rgb = rw.cards.threat_color(card.threat, card.suit)

		for i = 1, 6 do
			local cx = (H.bar + pad + Spread.THREAT_SIDE / 2 + (i - 1) * Spread.THREAT_PITCH) * k
			local outer, halo = style[TILE_IDS.th_o[i]], style[TILE_IDS.th_h[i]]
			local filled = i <= card.threat
			local rgb = filled and threat_rgb or rw.cards.BASE.muted

			outer.visible, halo.visible = i <= 5 or card.threat == 6, i <= 5 or card.threat == 6
			outer.size[1], outer.size[2], outer.pivot[1], outer.pivot[2] = side, side, side / 2, side / 2
			halo.size[1], halo.size[2], halo.pivot[1], halo.pivot[2] = side + 1.1, side + 1.1, (side + 1.1) / 2, (side + 1.1) / 2
			outer.offset[1], outer.offset[2] = cx - side / 2, cy - side / 2
			halo.offset[1], halo.offset[2] = cx - (side + 1.1) / 2, cy - (side + 1.1) / 2
			Spread.set_color(outer.color, filled and 255 or 64, rgb)
			Spread.set_color(halo.color, card.threat == 6 and 255 or filled and 70 or 22, card.threat == 6 and rw.cards.threat_edge(card.suit) or rgb)
		end

		local dots = card.dots
		local diameter, pitch, count = Spread.dots_fit(H.hud_w, #dots, card.threat)

		for i = 1, 6 do
			local dot, halo = style[TILE_IDS.dot[i]], style[TILE_IDS.dot_h[i]]

			dot.visible, halo.visible = i <= count, i <= count

			if i <= count then
				local d = diameter * k
				local x = (H.hud_w - pad) * k - d - (count - i) * pitch * k

				dot.offset[1], dot.offset[2], dot.size[1], dot.size[2] = x, cy - d / 2, d, d
				halo.offset[1], halo.offset[2], halo.size[1], halo.size[2] = x - 0.6, cy - d / 2 - 0.6, d + 1.2, d + 1.2
				Spread.set_color(dot.color, 255, dots[i])
				Spread.set_color(halo.color, 70, dots[i])
			end
		end
	end

	View._hide_mirror = function (self)
		local widgets = self._widgets_by_name

		for _, name in ipairs(MIRROR_STATIC) do
			if widgets[name] then
				widgets[name].visible = false
			end
		end

		for _, name in ipairs(MIRROR_DYNAMIC) do
			if widgets[name] then
				widgets[name].visible = false
			end
		end

		if self._screen ~= "detail" then
			for _, name in ipairs(STAGE_WIDGETS) do
				if widgets[name] then
					widgets[name].visible = false
				end
			end

			self._preview = nil
		end
	end

	View._set_mirror_interaction = function (self, enabled)
		local widgets = self._widgets_by_name

		for i = 1, #mod.rw.cards.SUIT_ORDER do
			local widget = widgets[PLATE .. i]

			if widget then
				widget.content.hotspot.disabled = not (enabled and widget.visible)
			end
		end

		-- the look plate is a picture of what every card does: never a button
		for i = 1, #LOOKS do
			local widget = widgets[LOOK .. i]

			if widget then
				widget.content.hotspot.disabled = true
			end
		end

		local field = widgets.whisper_field

		if field then
			field.content.hotspot.disabled = not (enabled and field.visible)
		end

		local big = widgets.rw_threat_big

		if big then
			for k = 1, 6 do
				big.content["hotspot_t" .. k].disabled = not (enabled and big.visible)
			end
		end

		self:_set_stage_interaction(enabled)
	end

	-- (Re)paints the Mirror: the four sections and the stage. Called by _refresh_rows for the screen "face".
	View._refresh_mirror = function (self)
		local widgets = self._widgets_by_name
		local rw = mod.rw
		local Cards, groups, colors = rw.cards, rw.groups, rw.colors
		local wave = self._wave
		local M = Workshop.MIRROR

		for _, name in ipairs(MIRROR_STATIC) do
			widgets[name].visible = true
		end

		local card = self:_refresh_stage()
		local suggested = Cards.suggest_suit(wave.parts or {}, groups)

		-- the headers
		local titles = { "mirror_suit", "mirror_threat", "mirror_whisper", "mirror_cooldown" }

		for i = 1, 4 do
			local content = widgets["mirror_head_" .. i].content

			content.head_title = string.upper(mod:localize(titles[i]))
			content.head_hint = i == 4 and mod:localize("mirror_cooldown_hint", math.floor(self:_longest_cooldown() / 60)) or mod:localize(titles[i] .. "_hint")
		end

		-- the suit: the plates of the switch's choice (twelve hostile or four beneficial), then the description of the card's suit
		self:_paint_kind_switch()

		for i = 1, #mod.rw.cards.SUIT_ORDER do
			local id = Cards.SUIT_ORDER[i]
			local def = Cards.SUITS[id]
			local widget = widgets[PLATE .. i]
			local content = widget.content
			local shown, place = self:_suit_slot(i)
			local x, y = Workshop.plate_pos(place)

			widget.visible = shown
			self:_set_scenegraph_position(PLATE .. i, x, y, 3)
			content.suit_name = def.name
			content.suit_line = def.whisper
			content.selected = id == card.suit
			content.sug_label = suggested == id and id ~= card.suit and string.upper(mod:localize("mirror_suggested")) or ""
			content.suit.card, content.suit.hi, content.suit.frame, content.suit.text, content.suit.accent = def.card, def.hi, def.frame, def.text, def.accent
			self:_paint_suit_mark(widget.style, def.icon, 30, 14, 18, def.accent, def.card)
		end

		local own = Cards.suit(wave.suit)

		widgets.hand_caption.content.hand_caption = string.upper(mod:localize("hand_caption"))
		widgets.rw_hand_card.visible = true
		self:_paint_hand(widgets.rw_hand_card, card, own)

		-- and beside it the same card in the last card window, as the HUD draws it ("just drawn" where the HUD says how long ago)
		local last = self._last_preview

		if last and widgets.rw_last_card then
			widgets.rw_last_card.visible = true
			LastPaint.setup(last, card, LastPaint.chosen_font())
			last._widget.content.age = mod:localize("face_last_sample")
		end

		widgets.mirror_desc.content.mirror_desc = string.format("{#color(%d,%d,%d)}%s{#reset()}  %s", own.accent[1], own.accent[2], own.accent[3], own.name, mod:localize("suit_desc_" .. card.suit))

		-- the threat: the diamonds and what the level means (its name at 6, the murmur from 5)
		local big = widgets.rw_threat_big

		big.visible = true
		big.content.threat, big.content.suit = card.threat, card.suit
		widgets.mirror_numbers.content.mirror_numbers = self:_face_numbers_text()

		-- the whisper: the card's line (or the suit's own, dimmer) in quotes
		local field = widgets.whisper_field

		field.visible = true
		field.content.whisper_text = "\"" .. card.whisper .. "\""
		field.content.whisper_own = card.own_whisper
		widgets.btn_whisper_change.content.hotspot_text = mod:localize("btn_change")
		widgets.btn_whisper_suit.content.hotspot_text = mod:localize("btn_whisper_suit")

		-- the cooldown: the stepper and the one look every card has (rot and renewal: shown, not chosen)
		local stepper = widgets.stepper_cooldown.content

		stepper.label = ""
		stepper.stepper_value = h.Deck.clock_text(wave.cooldown)
		-- a card with a fixed timer ignores its cooldown and says so
		stepper.extra = wave.timer > 0 and mod:localize("extra_timer_ignored") or mod:localize("mirror_cooldown_extra", math.floor(wave.cooldown))

		for i = 1, #LOOKS do
			local kind = LOOKS[i]
			local widget = widgets[LOOK .. i]
			local content = widget.content

			widget.visible = true
			content.look_name = mod:localize("look_" .. kind)
			content.look_desc = mod:localize("look_" .. kind .. "_desc")
			content.hotspot_on = true
			content.look_auto = string.upper(mod:localize("look_every_card"))
			content.accent_rgb = own.accent
		end

		widgets.btn_reset_face.content.hotspot_text = mod:localize("btn_reset_face")
	end

	-- Per frame (while the Cauldron or the Mirror is shown): the cooldown preview of the stage card.
	View._update_cauldron = function (self, dt, t)
		local play = self._preview
		local stage = self._widgets_by_name[STAGE]

		-- the stage card lives too (Heresy's heartbeat, the sixth diamond's shine), but not while the cooldown preview plays
		if stage and stage.visible and not play then
			self:_tick_living_tile(stage, t)
		end

		-- the last card window's preview on the Mirror lives as on the HUD (its aura, Nightmare's fog)
		local last = self._last_preview

		if last and last._widget.visible and last._aura_box then
			LastPaint.tick_aura(last, t)
			LastPaint.tick_fog(last, t)
		end

		if not play then
			return
		end

		local widget = stage
		local fx = widget and widget.content.fx

		if not fx then
			self._preview = nil

			return
		end

		play.t = play.t + (dt or 0)

		local p = math.min(1, play.t / PREVIEW_SECONDS)

		self:_apply_look(widget, fx, p, t)

		if p >= 1 then
			self._preview = nil
			self:_paint_tile(widget, self._wave)
		end
	end

	-- ------------------------------------------------------------------------------------------ callbacks
	-- A click on a chip of the shelf: one more of that enemy (a new group when the card has none without modifiers).
	View.cb_shelf_add = guarded(function (self, index)
		local chip = shelf.chips[index]

		if self._screen ~= "detail" or not chip then
			return
		end

		self:_add_breed_quick(mod.rw.groups.shelf_breed(chip.entry, self._faction or "scab"))
	end)

	View._add_breed_quick = function (self, breed)
		if mod.rw.groups.Effects.beneficial(self._wave.suit) then return end
		local groups = mod.rw.groups

		if groups.total_count(self._parts) >= groups.MAX_TOTAL then
			mod:echo("%s", mod:localize("msg_max_total"))

			return
		end

		for i = 1, #self._parts do
			local part = self._parts[i]

			if part.breed == breed and not part.mods and not part.tune and not part.appearance then
				part.count = math.min(part.count + 1, groups.MAX_BREED_COUNT)
				self:_save()

				return
			end
		end

		if #self._parts >= groups.MAX_PARTS then
			mod:echo("%s", mod:localize("msg_max_groups"))

			return
		end

		self._parts[#self._parts + 1] = { breed = breed, count = 1 }
		-- the new group is the last row: the list scrolls so that it shows
		self._offset = self:_clamp_offset(math.max(0, #self._parts - Workshop.ROWS))
		self:_save()
	end

	-- the Dreg / Scab switch of the shelf (kept in the settings)
	View.cb_faction = guarded(function (self, faction)
		self._faction = faction
		set_setting("shelf_faction", faction)
		self:_apply_screen(true)
	end)

	local function changed(self)
		self:_reload()
		self:_apply_screen(true)
	end

	-- a suit tile: the card's suit
	View.cb_suit_pick = guarded(function (self, index)
		local id = mod.rw.cards.SUIT_ORDER[index]

		if (self._screen == "detail" or self._screen == "face") and id then
			set_setting("su_" .. self._key, id)
			self._suit_kind = nil -- the switch follows the suit just picked
			changed(self)
		end
	end)

	-- a threat diamond: the threat by hand (1 to 6)
	View.cb_threat_pick = guarded(function (self, level)
		if self._screen == "detail" or self._screen == "face" then
			set_setting("th_" .. self._key, math.max(1, math.min(6, level)))
			changed(self)
		end
	end)

	-- Preview cooldown: the stage card plays the look of its cooldown through, in PREVIEW_SECONDS
	View.cb_preview_cooldown = guarded(function (self)
		if self._screen == "detail" or self._screen == "face" then
			self._preview = { t = 0 }
		end
	end)

	-- the roll switch of the spawn block: random groups roll once and keep their enemy on every repeat (default), or roll for every unit
	View.cb_keep_pick = guarded(function (self)
		if self._screen == "detail" and self._wave then
			set_setting("rk_" .. self._key, self._wave.keep_pick == false)
			changed(self)
		end
	end)

	-- the Enemies tab (on the card's face screen it goes back to the Cauldron)
	View.cb_enemies = guarded(function (self)
		if self._screen == "face" then
			self._screen = "detail"
			self:_reload()
			self:_apply_screen()
		end
	end)
end

return WorkshopView
