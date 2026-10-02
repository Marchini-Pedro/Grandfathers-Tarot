-- The Cauldron (the screen "detail", docs/08-workshop-redesign.md): the enemies of one card on the left (rows, the shelf of
-- common enemies, the spawn settings, the action bar) and the card itself on the right at 1.4 times its Deck size with the
-- quick face under it (suit, threat, chance). Everything the player changes is written to the card's settings at once and the
-- card on the right is painted again, so it follows every click. Where things sit is in ui/workshop.lua, the widgets in
-- ui/workshop_blueprints.lua. Installed on the view with `install` (see wave_editor_view.lua).
local mod = get_mod("RealmsWaves")

local WorkshopView = {}

local PREVIEW_SECONDS = 5 -- the cooldown preview of the stage card plays through its look in this time
local MOD_CHARS, INFO_CHARS = 22, 40 -- the modifiers of a row are cut at 22 visible characters, the line at 40

WorkshopView.install = function (View, h)
	local Workshop, Spread, TILE_IDS, definitions = h.Workshop, h.Spread, h.TILE_IDS, h.definitions
	local guarded, set_setting, Components, with_faction = h.guarded, h.set_setting, h.Components, h.with_faction
	local shelf = definitions.shelf_layout
	local ERROW, CHIP, SUIT, STAGE = definitions.ERROW_NODE_PREFIX, definitions.CHIP_NODE_PREFIX, definitions.SUIT_NODE_PREFIX, definitions.STAGE_CARD_NODE

	-- the widgets that exist only while the Cauldron is shown (its buttons are shown with the other buttons, see _apply_screen)
	local STATIC = { "enemy_header", "shelf_panel", "stage_plate", "stage_caption", "stage_stats", "quick_label", "threat_label", "spawn_label" }
	local ROW_HOTSPOTS = { "hotspot_name", "hotspot_minus", "hotspot_value", "hotspot_plus", "hotspot_rep_minus", "hotspot_rep_value", "hotspot_rep_plus", "hotspot_same", "hotspot_mods", "hotspot_tune", "hotspot_action" }

	-- every dynamic widget of the Cauldron by name (rows, chips, suit tiles, the threat control, the stage card)
	local DYNAMIC = { "rw_threat", STAGE }

	for i = 1, Workshop.ROWS do
		DYNAMIC[#DYNAMIC + 1] = ERROW .. i
	end

	for i = 1, #shelf.chips do
		DYNAMIC[#DYNAMIC + 1] = CHIP .. i
	end

	for i = 1, 12 do
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

		for i = 1, 12 do
			local name = SUIT .. i
			local widget = self:_create_dynamic_widget(name, WB.suit_tile(name, TILE_IDS))

			widget.content.hotspot.pressed_callback = callback(self, "cb_suit_pick", i)
			widget.visible = false
		end

		local threat = self:_create_dynamic_widget("rw_threat", WB.threat_control("rw_threat"))

		for k = 1, 5 do
			threat.content["hotspot_t" .. k].pressed_callback = callback(self, "cb_threat_pick", k)
		end

		threat.visible = false

		-- the card on its stage: the Deck's tile at 1.4 times its size, nobody can click it
		local stage = self:_create_dynamic_widget(STAGE, blueprints.tile(STAGE, Workshop.CARD_SCALE))

		for _, hotspot in ipairs(self.TILE_HOTSPOTS) do
			stage.content[hotspot].disabled = true
		end

		stage.visible = false
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

		self._preview = nil
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

		for i = 1, 12 do
			local widget = widgets[SUIT .. i]

			if widget then
				widget.content.hotspot.disabled = not (enabled and widget.visible)
			end
		end

		local threat = widgets.rw_threat

		if threat then
			for k = 1, 5 do
				threat.content["hotspot_t" .. k].disabled = not (enabled and threat.visible)
			end
		end
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

		content.row_name = groups.describe_part(item)

		-- a random group colours each enemy of the group, the modifier names get their own colours; the modifier text is cut at
		-- MOD_CHARS visible characters WITHOUT losing the colours
		if painter then
			if item.one_of then
				content.row_name = groups.render_segments(groups.paint_part_segments(item, painter, false), nil, painter.markup)
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
		content.info = mods_shown
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

			if part.breed == breed and not part.mods and not part.tune then
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
			local chip_faction = groups.shelf_faction(chip.entry, faction)

			widget.visible = true
			content.chip_label = groups.shelf_label(chip.entry)
			content.chip_tag = chip.tag and chip_faction and groups.FACTION_NAMES[chip_faction]:sub(1, 1) or ""
			content.tag_rgb = chip_faction and colors and colors.faction_rgb(chip_faction) or Components.rgb.muted
			content.dot_rgb = colors and colors.rgb(breed) or Components.rgb.muted
			content.hotspot_on = self:_card_has_plain(breed)
		end

		widgets.spawn_label.content.spawn_label = string.upper(mod:localize("spawn_label"))

		-- the stage: the card as the Deck draws it, 1.4 times as big, on a plate in the suit's colours
		local suit = Cards.suit(wave.suit)
		local stage = widgets[STAGE]

		stage.visible = true
		self:_paint_tile(stage, wave)

		local plate = widgets.stage_plate.content.stage

		plate.card, plate.frame, plate.accent = suit.card, suit.frame, suit.accent

		local card = Cards.describe(wave, groups, nil, self._deck_range)
		local share = self:_share_of(wave)

		widgets.stage_caption.content.stage_caption = string.upper(mod:localize("stage_caption"))
		widgets.stage_stats.content.stage_stats = share and mod:localize("stage_stats", card.threat, groups.total_count(self._parts), string.format("%.1f", share)) or mod:localize("stage_stats_off")

		-- the quick face: the twelve suits (the chosen one lifted, the suggested one marked), the threat, the chance
		local suggested = Cards.suggest_suit(wave.parts or {}, groups)

		widgets.quick_label.content.quick_label = string.upper(mod:localize("quick_label"))
		widgets.threat_label.content.threat_label = string.upper(mod:localize("lbl_threat"))
		widgets.btn_quickface.content.hotspot_text = mod:localize("btn_quickface")
		widgets.btn_preview.content.hotspot_text = mod:localize("btn_preview_cooldown")

		for i = 1, 12 do
			local id = Cards.SUIT_ORDER[i]
			local def = Cards.SUITS[id]
			local widget = widgets[SUIT .. i]
			local content = widget.content
			local x, y = Workshop.suit_pos(i)

			widget.visible = true
			content.suit_name = string.upper(def.name)
			content.suit.card, content.suit.hi, content.suit.frame, content.suit.text, content.suit.accent = def.card, def.hi, def.frame, def.text, def.accent
			content.selected = id == card.suit
			content.suggested = suggested == id and id ~= card.suit
			self:_set_scenegraph_position(SUIT .. i, x, content.selected and y - 4 or y, 3)
			self:_paint_suit_mark(widget.style, def.icon, 26, 27, 6, def.accent, def.card)
		end

		local threat = widgets.rw_threat

		threat.visible = true
		threat.content.threat = card.threat
		widgets.btn_thr_auto.content.hotspot_text = mod:localize("btn_thr_auto")
		widgets.btn_thr_auto.content.hotspot_on = card.threat_override == 0
		widgets.btn_thr_hand.content.hotspot_text = mod:localize("btn_thr_hand")
		widgets.btn_thr_hand.content.hotspot_on = card.threat_override ~= 0
	end

	-- Per frame (only while the Cauldron is shown): the cooldown preview of the stage card.
	View._update_cauldron = function (self, dt, t)
		local play = self._preview

		if not play then
			return
		end

		local widget = self._widgets_by_name[STAGE]
		local fx = widget and widget.content.fx

		if not fx then
			self._preview = nil

			return
		end

		play.t = play.t + (dt or 0)

		local p = math.min(1, play.t / PREVIEW_SECONDS)

		if fx.look == "vial" then
			self:_animate_vial(widget, fx, p, t)
		else
			self:_apply_look(widget, fx, p, t)
		end

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
		local groups = mod.rw.groups

		if groups.total_count(self._parts) >= groups.MAX_TOTAL then
			mod:echo("%s", mod:localize("msg_max_total"))

			return
		end

		for i = 1, #self._parts do
			local part = self._parts[i]

			if part.breed == breed and not part.mods and not part.tune then
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

		if self._screen == "detail" and id then
			set_setting("su_" .. self._key, id)
			changed(self)
		end
	end)

	-- a threat diamond: the threat by hand (1 to 5)
	View.cb_threat_pick = guarded(function (self, level)
		if self._screen == "detail" then
			set_setting("th_" .. self._key, math.max(1, math.min(5, level)))
			changed(self)
		end
	end)

	-- Auto: the threat is worked out from the enemies again
	View.cb_threat_auto = guarded(function (self)
		if self._screen == "detail" then
			set_setting("th_" .. self._key, 0)
			changed(self)
		end
	end)

	-- By hand: the threat stays what it shows now, and the diamonds set it from here
	View.cb_threat_hand = guarded(function (self)
		if self._screen == "detail" then
			local rw = mod.rw
			local override = tonumber(self._wave.threat_override) or 0
			local value = override > 0 and override or rw.cards.threat_auto(self._parts, rw.groups)

			set_setting("th_" .. self._key, math.max(1, math.min(5, value)))
			changed(self)
		end
	end)

	-- Preview cooldown: the stage card plays the look of its cooldown through, in PREVIEW_SECONDS
	View.cb_preview_cooldown = guarded(function (self)
		if self._screen == "detail" then
			self._preview = { t = 0 }
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
