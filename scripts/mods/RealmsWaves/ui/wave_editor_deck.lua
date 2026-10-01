-- The Deck: the home screen of the wave editor (screen "list"). Every card is a tile (blueprints.tile) in a grid of 7
-- columns and 2 rows, with a strip above that shows how likely each card is to be dealt into a hand. Clicking a tile
-- puts the card in or out of the draw, clicking one of its ten pips sets its chance (relative to the other cards of the
-- draw), its Edit pill or a right click opens it, the blank tile at the end makes a new card.
-- The arithmetic and the texts are in ui/deck.lua; the shapes (suit marks) are drawn like the Spread HUD draws them
-- (ui/spread.lua). Installed on the view with `install` (see wave_editor_view.lua); nothing here is drawn per frame
-- except the hover.
local mod = get_mod("RealmsWaves")

local Text = require("scripts/utilities/ui/text")

local DeckView = {}

-- text styles keep their colour in text_color, the shapes in color
local function paint(style, alpha, rgb)
	local target = style.text_color or style.color

	target[1], target[2], target[3], target[4] = alpha, rgb[1], rgb[2], rgb[3]
end

local function mix(a, b, t)
	return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

-- Seconds of cooldown left on a card (0 when it is not resting, when there is no director, or when asking it fails: the
-- editor is also opened in the hub, where no mission runs).
local function cooldown_left(key, length)
	local director = mod.rw and mod.rw.director

	if not director or not director.cooldown_remaining then
		return 0
	end

	local ok, left = pcall(director.cooldown_remaining, key, length)

	return ok and tonumber(left) or 0
end

-- the first n bytes of a text, never cutting a multi-byte character
local function utf8_cut(text, n)
	if n >= #text then
		return text
	end

	local cut = n

	while cut > 0 do
		local byte = text:byte(cut + 1)

		if byte and byte >= 0x80 and byte < 0xC0 then
			cut = cut - 1
		else
			break
		end
	end

	return text:sub(1, cut)
end

-- the name's font in the tile, and its average glyph width (of the font size): how many lines a name takes, see Spread.wrap_lines
local NAME_FONT, NAME_GLYPH = 20, 0.6

DeckView.install = function (View, h)
	local Deck, Spread, T, IDS = h.Deck, h.Spread, h.TILE, h.TILE_IDS
	local guarded, set_setting = h.guarded, h.set_setting
	local TILE_PREFIX = h.TILE_PREFIX
	local TILE_HOTSPOTS = { "hotspot_top", "hotspot_state", "hotspot_edit" }

	for i = 1, Deck.PIPS do
		TILE_HOTSPOTS[#TILE_HOTSPOTS + 1] = IDS.hotspot_pip[i]
	end

	View.TILE_HOTSPOTS = TILE_HOTSPOTS

	local function place_tri(style, slot, ox, oy, z)
		style.visible = slot.on

		if slot.on then
			local offset, corners = style.offset, style.triangle_corners

			offset[1], offset[2], offset[3] = ox, oy, z + slot.z
			corners[1][1], corners[1][2], corners[2][1], corners[2][2], corners[3][1], corners[3][2] = slot.x1, slot.y1, slot.x2, slot.y2, slot.x3, slot.y3
		end
	end

	local function place_circ(style, slot, ox, oy, z)
		style.visible = slot.on

		if slot.on then
			local offset, size = style.offset, style.size
			local diameter = slot.r * 2

			offset[1], offset[2], offset[3] = ox + slot.cx - slot.r, oy + slot.cy - slot.r, z + slot.z
			size[1], size[2] = diameter, diameter
		end
	end

	-- the feather under a shape (see Spread.FEATHER): the same shape, a little larger, half a layer lower
	local function place_tri_halo(style, slot, ox, oy, z)
		style.visible = slot.on

		if slot.on then
			local offset = style.offset

			offset[1], offset[2], offset[3] = ox, oy, z + slot.z - 0.5
			Spread.write_corners(style.triangle_corners, slot, Spread.FEATHER)
		end
	end

	local function place_circ_halo(style, slot, ox, oy, z)
		style.visible = slot.on

		if slot.on then
			local offset, size = style.offset, style.size
			local r = slot.r + Spread.FEATHER

			offset[1], offset[2], offset[3] = ox + slot.cx - r, oy + slot.cy - r, z + slot.z - 0.5
			size[1], size[2] = r * 2, r * 2
		end
	end

	local FEATHER = Spread.alpha(Spread.FEATHER_ALPHA)

	-- How many lines a card's name takes in its box (1 to 3). The game measures it when the editor has a renderer (it knows
	-- the font; the divider, the composition and the room for enemies follow from it), else (offline tests, a failed
	-- measurement) it is estimated from the letters, which is a little careful: a name that turns out shorter than guessed
	-- only leaves a gap, a longer one would run into the divider.
	View._name_lines = function (self, name, style)
		local renderer = self._ui_renderer

		if renderer then
			local ok, lines = pcall(function ()
				local size = { T.name[3], 1000 }
				local one = Text.text_height(renderer, "Ag", style, size, true)

				if not one or one <= 0 then
					return nil
				end

				return math.floor(Text.text_height(renderer, name, style, size, true) / one + 0.5)
			end)

			if ok and lines then
				return math.max(1, math.min(3, lines))
			end
		end

		return Spread.wrap_lines(name, T.name[3], NAME_FONT, NAME_GLYPH)
	end

	-- A card is in the draw when it is enabled, has enemies, a weight and no fixed timer (the same rule the director uses).
	local function in_draw(wave)
		return wave.enabled and wave.parts and #wave.parts > 0 and (wave.pct or 0) > 0 and not ((wave.timer or 0) > 0)
	end

	-- --------------------------------------------------------------------------------------------- model
	-- The cards of the deck: every standard card and every custom card that has enemies, in the order of the wave list,
	-- then the blank tile (while a custom slot is free).
	View._build_deck = function (self)
		local deck, free = {}, nil

		for i = 1, #self._waves do
			local wave = self._waves[i]

			if (wave.parts and #wave.parts > 0) or not wave.is_custom then
				deck[#deck + 1] = wave
			elseif not free then
				free = wave
			end
		end

		self._deck_free = free

		if free then
			deck[#deck + 1] = { blank = true, key = free.key }
		end

		self._deck = deck

		-- the lightest and the heaviest weight of the draw: the chance pips and "rare" are relative to them
		local lo, hi = self:_draw_range(nil)

		self._deck_range = { lo = lo, hi = hi }
	end

	-- The lightest and the heaviest weight among the cards in the draw, leaving out the card `except` (a key, or nil).
	View._draw_range = function (self, except)
		local lo, hi

		for i = 1, #self._deck do
			local wave = self._deck[i]

			if not wave.blank and wave.key ~= except and in_draw(wave) then
				lo = lo and math.min(lo, wave.pct) or wave.pct
				hi = hi and math.max(hi, wave.pct) or wave.pct
			end
		end

		return lo, hi
	end

	View._deck_in_draw = function (self)
		local count = 0

		for i = 1, #self._deck do
			if not self._deck[i].blank and in_draw(self._deck[i]) then
				count = count + 1
			end
		end

		return count
	end

	-- --------------------------------------------------------------------------------------- painting
	-- The strip of the draw: a segment per card in the draw, as wide as its weight; the card under the pointer is taller.
	View._paint_strip = function (self)
		local widget = self._widgets_by_name.rw_strip

		if not widget then
			return
		end

		local rw = mod.rw
		local Cards = rw.cards
		local items = {}

		for i = 1, #self._deck do
			local wave = self._deck[i]

			if not wave.blank and in_draw(wave) and #items < Deck.STRIP_MAX then
				items[#items + 1] = { weight = wave.pct, key = wave.key, rgb = Cards.suit(wave.suit).accent }
			end
		end

		self._strip_segments = self._strip_segments or {}

		local n = Deck.strip_segments(items, Deck.STRIP_W, self._strip_segments)
		local style = widget.style

		paint(style.track, 255, Cards.BASE.line)
		style.track.visible = true
		style.track.color[1] = 150

		for i = 1, Deck.STRIP_MAX do
			local seg = style[h.STRIP_IDS[i]]
			local hot = style[h.STRIP_HOT[i]]
			local segment = self._strip_segments[i]

			if i <= n then
				local raised = segment.key == self._deck_hover

				seg.visible = true
				seg.offset[1], seg.offset[2] = segment.x, raised and -3 or 0
				seg.size[1], seg.size[2] = segment.w, raised and Deck.STRIP_H + 6 or Deck.STRIP_H
				paint(seg, raised and 255 or 215, segment.rgb)
				hot.offset[1], hot.offset[2], hot.size[1], hot.size[2] = segment.x, -3, segment.w, Deck.STRIP_H + 6
			else
				seg.visible = false
				hot.size[1] = 0
			end
		end
	end

	-- One card on its tile: the face (suit colours, name, composition, whisper, threat, dots), the chance pips and the
	-- state line. A card out of the draw is dimmed and drained of colour.
	View._paint_tile = function (self, widget, wave)
		local rw = mod.rw
		local Cards, groups, colors = rw.cards, rw.groups, rw.colors
		local style, content = widget.style, widget.content
		local card = Cards.describe(wave, groups, function (breed)
			return colors and colors.rgb(breed) or Cards.BASE.muted
		end, self._deck_range)
		local suit = Cards.suit(card.suit)
		local remaining = cooldown_left(wave.key, card.cooldown)
		local state = Deck.state(card, remaining)
		local sat = state == "off" and 0.7 or 0

		local function tone(rgb)
			return Spread.grey({ 0, 0, 0 }, rgb, sat)
		end

		local bg, accent, ink = tone(suit.card), tone(suit.accent), tone(suit.text)
		local border = card.rare and tone(Cards.BASE.pus) or tone(mix(suit.frame, suit.accent, 0.45))

		-- what the per-frame cooldown looks and the pips need to know (see _apply_look, _paint_pips); a new record on every paint
		local fx = {
			key = wave.key, wave = wave, cooldown = card.cooldown, look = card.look, state = state, suit = suit, rare = card.rare,
			accent = accent, ink = ink, bg = bg, whisper = card.whisper, p = -1, clock = -1, level = Deck.pips(card.level),
			pip_new = mix(accent, ink, 0.5), empty = tone(suit.frame), muted = tone(Cards.BASE.muted), edit_hover = false,
			tri_col = {}, circ_col = {},
		}

		content.fx = fx
		content.card_key, content.card_state = wave.key, state
		content.bg_rgb, content.bg_hi = bg, tone(suit.hi)
		widget.alpha_multiplier = state == "off" and 0.55 or 1

		for i = 1, #IDS.border do
			local s = style[IDS.border[i]]

			s.visible = true
			paint(s, 255, border)
		end

		style.glow.visible = state ~= "off"
		paint(style.glow, card.rare and 110 or 70, card.rare and Cards.BASE.pus or accent)

		-- the suit mark (26 units) in the top right corner, each shape on a feather; the suit's name and rarity at the left
		local shape = self._tile_shape
		local origin_x, origin_y = T.icon[1], T.icon[2]

		Spread.icon(suit.icon, T.icon[3], shape)

		for i = 1, Spread.ICON_TRIS do
			local s, halo = style[IDS.icon_t[i]], style[IDS.icon_th[i]]
			local rgb = shape.tri[i].col == 2 and bg or accent

			place_tri(s, shape.tri[i], origin_x, origin_y, 4)
			place_tri_halo(halo, shape.tri[i], origin_x, origin_y, 4)
			paint(s, 255, rgb)
			paint(halo, FEATHER, rgb)
			fx.tri_col[i] = shape.tri[i].col
		end

		for i = 1, Spread.ICON_CIRCS do
			local s, halo = style[IDS.icon_c[i]], style[IDS.icon_ch[i]]
			local rgb = shape.circ[i].col == 2 and bg or accent

			place_circ(s, shape.circ[i], origin_x, origin_y, 4)
			place_circ_halo(halo, shape.circ[i], origin_x, origin_y, 4)
			paint(s, 255, rgb)
			paint(halo, FEATHER, rgb)
			fx.circ_col[i] = shape.circ[i].col
		end

		content.suit_label = string.upper(suit.name .. (card.rare and (" \194\183 " .. mod:localize("tile_rare")) or ""))
		style.suit_label.visible = true
		paint(style.suit_label, 255, accent)

		content.name = card.name
		style.name.visible = true
		paint(style.name, 255, ink)

		-- the divider and the composition follow the name: a one line name leaves room for five lines of enemies, a two line name for four
		local layout = Deck.layout(self:_name_lines(card.name, style.name))

		style.divider.visible = true
		style.divider.offset[2] = layout.divider_y
		paint(style.divider, 255, tone(suit.frame))

		local has_parts = wave.parts and #wave.parts > 0
		-- colour tags only while the enemy colours are on (the option "Colour enemy names")
		local colour_on = colors ~= nil and colors.rgb("chaos_poxwalker") ~= nil
		local lines = has_parts and Deck.comp_lines(wave.parts, groups, function (breed)
			return colour_on and colors.rgb(breed) or nil
		end, colour_on and colors.markup or nil, Cards.BASE.text, mod:localize("tile_repeats"), function (n)
			return mod:localize("tile_more", n)
		end, layout.comp_lines) or { mod:localize("tile_no_enemies") }

		content.comp = table.concat(lines, "\n")
		style.comp.visible = true
		style.comp.offset[2], style.comp.size[2] = layout.comp_y, layout.comp_h
		paint(style.comp, 255, tone(Cards.BASE.muted))

		-- the modifiers, each in its Improved Havoc Tags colour (the mod's own setting when it is installed, else its default
		-- colour) while the enemy colours are on; rust otherwise
		content.mods = card.modifiers ~= "" and Cards.modifier_line(wave.parts, groups, colour_on and function (name, id)
			local rgb = colors.modifier_rgb(id)

			if not rgb then
				return name
			end

			local drained = tone(rgb) -- whole numbers: the colour tag is written with %d

			return colors.markup(name, { math.floor(drained[1] + 0.5), math.floor(drained[2] + 0.5), math.floor(drained[3] + 0.5) })
		end or nil) or ""
		style.mods.visible = card.modifiers ~= ""
		paint(style.mods, 255, tone(Cards.BASE.rust))

		content.whisper = "\"" .. card.whisper .. "\""
		style.whisper.visible = true
		paint(style.whisper, 255, tone(card.suit == "murmur" and Cards.BASE.whisper or Cards.BASE.muted))

		-- threat: filled diamonds up to the level (its colour), the rest the same diamonds dimmed; each on a faint feather
		local threat_rgb = Cards.THREAT_COLORS[card.threat]

		for i = 1, 5 do
			local cx = T.diamonds_x + (i - 1) * Spread.THREAT_PITCH
			local outer, halo = style[IDS.th_o[i]], style[IDS.th_h[i]]
			local filled = i <= card.threat
			local rgb = tone(filled and threat_rgb or Cards.BASE.muted)

			outer.visible, halo.visible = true, true
			outer.offset[1], outer.offset[2] = cx - 4, T.row_y - 4
			halo.offset[1], halo.offset[2] = cx - 4.7, T.row_y - 4.7
			paint(outer, filled and 255 or 64, rgb)
			paint(halo, filled and 70 or 22, rgb)
		end

		-- one dot per enemy colour, right aligned, each on a feather
		local dots = card.dots
		local count = math.min(#dots, 6)

		for i = 1, 6 do
			local dot, halo = style[IDS.dot[i]], style[IDS.dot_h[i]]

			dot.visible, halo.visible = i <= count, i <= count

			if i <= count then
				local x, y = T.dots_right - 9 - (count - i) * 13, T.row_y - 4.5

				dot.offset[1], dot.offset[2] = x, y
				dot.size[1], dot.size[2] = 9, 9
				halo.offset[1], halo.offset[2] = x - 0.6, y - 0.6
				halo.size[1], halo.size[2] = 10.2, 10.2
				paint(dot, 255, tone(dots[i]))
				paint(halo, 70, tone(dots[i]))
			end
		end

		-- the ten chance pips: filled up to the card's level among the cards of the draw
		self:_paint_pips(widget, nil)

		-- the state line: what the card does, the clock while it rests, and the Edit pill
		content.state_left = mod:localize(state == "off" and "tile_off" or state == "cooling" and "tile_cooling" or "tile_in")
		content.state_clock = state == "cooling" and Deck.clock_text(remaining) or ""
		style.state_left.visible, style.state_clock.visible = true, true
		paint(style.state_left, 255, state == "cooling" and ink or fx.muted)
		paint(style.state_clock, 255, ink)

		content.edit_label = mod:localize("tile_edit")
		style.edit_label.visible = true
		paint(style.edit_label, 255, fx.muted)
		paint(style.edit_bg, 130, tone(suit.frame))
		style.edit_bg.visible = false

		-- the effects of a cooldown and of the ready ping start hidden; a resting card gets its look right away
		style.vial.visible, style.vial_line.visible = false, false

		for i = 1, #IDS.bubble do
			style[IDS.bubble[i]].visible = false
		end

		for i = 1, #IDS.ping do
			style[IDS.ping[i]].visible = false
		end

		if state == "cooling" then
			fx.clock = math.ceil(remaining)
			self:_apply_look(widget, fx, math.max(0, math.min(1, 1 - remaining / math.max(1, card.cooldown))), 0)
		end
	end

	-- The ten chance pips of a tile. `hover` (1..10, or nil) is the pip under the pointer: the pips up to it light up, the
	-- ones past it go dark, to show what a click would set; the new ones are lighter than the ones the card has now.
	View._paint_pips = function (self, widget, hover)
		local fx = widget.content.fx
		local style = widget.style

		if not fx then
			return
		end

		fx.hover_level = hover

		local shown = hover or fx.level

		for i = 1, Deck.PIPS do
			local pip = style[IDS.pip[i]]

			pip.visible = true

			if i <= shown then
				paint(pip, 255, hover and i > fx.level and fx.pip_new or fx.accent)
			else
				paint(pip, 130, fx.empty)
			end
		end
	end

	-- ---------------------------------------------------------------------------------- cooldown looks
	-- A resting card shows how far its cooldown has come (p = 0..1) in the look of its card:
	--   rot      "rot and renewal": everything that has the suit's colour goes grey, then brown, then ochre, then back to
	--            the suit's colour; the text is faint (50 percent) and returns to full
	--   whisper  "the murmur returns": the whisper writes itself letter by letter and the whole card is faint (60
	--            percent) until it is back
	--   vial     "the vial fills": a liquid rises from the bottom, pus yellow, with a bright top line and bubbles
	View._apply_look = function (self, widget, fx, p, time)
		local rw = mod.rw
		local Cards = rw.cards
		local style, content = widget.style, widget.content

		fx.p = p

		if fx.look == "rot" then
			local rgb = Cards.rot_color(p, fx.suit.accent)
			local alpha = Spread.alpha(Cards.rot_text_alpha(p))

			paint(style.suit_label, 255, rgb)

			for i = 1, Spread.ICON_TRIS do
				if fx.tri_col[i] == 1 then
					paint(style[IDS.icon_t[i]], 255, rgb)
					paint(style[IDS.icon_th[i]], FEATHER, rgb)
				end
			end

			for i = 1, Spread.ICON_CIRCS do
				if fx.circ_col[i] == 1 then
					paint(style[IDS.icon_c[i]], 255, rgb)
					paint(style[IDS.icon_ch[i]], FEATHER, rgb)
				end
			end

			paint(style.glow, fx.rare and 110 or 70, fx.rare and Cards.BASE.pus or rgb)

			if not fx.rare then
				local border = mix(fx.suit.frame, rgb, 0.45)

				for i = 1, #IDS.border do
					paint(style[IDS.border[i]], 255, border)
				end
			end

			-- the pips take the colour too, except while the pointer is on them (they show what a click would set)
			if not fx.hover_level then
				for i = 1, math.min(fx.level, Deck.PIPS) do
					paint(style[IDS.pip[i]], 255, rgb)
				end
			end

			paint(style.name, alpha, fx.ink)
			paint(style.comp, alpha, Cards.BASE.muted)
			paint(style.whisper, alpha, fx.suit == Cards.SUITS.murmur and Cards.BASE.whisper or Cards.BASE.muted)
		elseif fx.look == "whisper" then
			local letters = Cards.whisper_letters(fx.whisper, p)

			widget.alpha_multiplier = Cards.murmur_card_alpha(p)
			content.whisper = "\"" .. utf8_cut(fx.whisper, letters) .. (letters >= #fx.whisper and "\"" or "")
		elseif fx.look == "vial" then
			self:_animate_vial(widget, fx, p, time)
		end
	end

	-- the vial: the liquid's height follows the cooldown, three bubbles rise through it (every frame)
	View._animate_vial = function (self, widget, fx, p, time)
		local style = widget.style
		local Cards = mod.rw.cards
		local fill = (Deck.TILE_H) * p

		fx.p = p
		style.vial.visible = fill > 0.5
		style.vial.offset[2], style.vial.size[2] = Deck.TILE_H - fill, fill
		paint(style.vial, 70, Cards.BASE.pus)
		style.vial_line.visible = fill > 0.5
		style.vial_line.offset[2] = Deck.TILE_H - fill
		paint(style.vial_line, 230, Cards.BASE.pus)

		for i = 1, #IDS.bubble do
			local bubble = style[IDS.bubble[i]]
			local rise = ((time or 0) * 0.38 + (i - 1) / 3) % 1

			bubble.visible = fill > 24
			bubble.offset[1], bubble.offset[2] = 28 + (i - 1) * 84, Deck.TILE_H - 10 - rise * (fill - 10)
			bubble.size[1], bubble.size[2] = 6, 6
			paint(bubble, math.floor(150 * (1 - rise)), Cards.BASE.pus)
		end
	end

	-- the ready ping: a ring that leaves the card and fades, and the name that flashes in the suit's colour
	View._start_ping = function (self, widget)
		local fx = widget.content.fx

		if fx then
			fx.ping_t = 0
			widget.content.state_left = mod:localize("tile_ready")
		end
	end

	local PING_TIME, FLASH_TIME = 1.1, 0.9

	View._tick_ping = function (self, widget, fx, dt)
		local style, content = widget.style, widget.content

		fx.ping_t = fx.ping_t + dt

		local u = fx.ping_t / PING_TIME

		if u >= 1 then
			for i = 1, #IDS.ping do
				style[IDS.ping[i]].visible = false
			end

			content.state_left = mod:localize("tile_in")
			paint(style.name, 255, fx.ink)
			fx.ping_t = nil

			return
		end

		local scale = 0.96 + 0.16 * u
		local w, h = Deck.TILE_W * scale, Deck.TILE_H * scale
		local x0, y0 = (Deck.TILE_W - w) / 2, (Deck.TILE_H - h) / 2
		local alpha = math.floor(230 * (1 - u))

		for i = 1, #IDS.ping do
			style[IDS.ping[i]].visible = true
			paint(style[IDS.ping[i]], alpha, fx.accent)
		end

		style.ping_t.offset[1], style.ping_t.offset[2], style.ping_t.size[1] = x0, y0, w
		style.ping_b.offset[1], style.ping_b.offset[2], style.ping_b.size[1] = x0, y0 + h - 2, w
		style.ping_l.offset[1], style.ping_l.offset[2], style.ping_l.size[2] = x0, y0, h
		style.ping_r.offset[1], style.ping_r.offset[2], style.ping_r.size[2] = x0 + w - 2, y0, h

		local k = math.min(1, fx.ping_t / FLASH_TIME)

		paint(style.name, 255, mix(fx.accent, fx.ink, k))
	end

	-- ------------------------------------------------------------------------------------- the screen
	-- (Re)builds the whole Deck page: the header texts, the strip, the tiles of this page and the blank tile.
	View._refresh_deck = function (self)
		local widgets = self._widgets_by_name
		local Cards = mod.rw.cards

		self._tile_shape = self._tile_shape or Spread.new_shape(Spread.ICON_TRIS, Spread.ICON_CIRCS)

		for _, name in ipairs({ "deck_count", "deck_caption", "deck_hover", "rw_strip" }) do
			if widgets[name] then
				widgets[name].visible = true
			end
		end

		widgets.deck_count.content.deck_count = mod:localize("deck_count", self:_deck_in_draw())
		widgets.deck_caption.content.deck_caption = mod:localize("deck_caption")
		widgets.deck_hover.content.deck_hover = ""
		self._deck_hover, self._deck_hover_pip = nil, nil

		local blank_slot = nil

		for i = 1, Deck.CAPACITY do
			local widget = widgets[TILE_PREFIX .. i]
			local item = self._deck[self._offset + i]

			if widget then
				widget.visible = item ~= nil and not item.blank

				if item and item.blank then
					blank_slot = i
				elseif item then
					local x, y = Deck.tile_pos(i)

					self:_set_scenegraph_position(TILE_PREFIX .. i, x, y, 3)
					self:_paint_tile(widget, item)
				end
			end
		end

		local blank = widgets[h.BLANK_NAME]

		if blank then
			blank.visible = blank_slot ~= nil

			if blank_slot then
				local x, y = Deck.tile_pos(blank_slot)

				self:_set_scenegraph_position(h.BLANK_NAME, x, y, 3)
				blank.content.plus = "+"
				blank.content.title = mod:localize("tile_blank_title")
				blank.content.hint = mod:localize("tile_blank_hint")

				for _, id in ipairs({ "plus", "title", "hint" }) do
					blank.style[id].visible = true
					paint(blank.style[id], 255, id == "title" and Cards.BASE.text or Cards.BASE.muted)
				end
			end
		end

		self:_paint_strip()
	end

	-- hides every widget of the Deck (another screen is shown)
	View._hide_deck = function (self)
		local widgets = self._widgets_by_name

		for i = 1, Deck.CAPACITY do
			if widgets[TILE_PREFIX .. i] then
				widgets[TILE_PREFIX .. i].visible = false
			end
		end

		for _, name in ipairs({ h.BLANK_NAME, "deck_count", "deck_caption", "deck_hover", "rw_strip", "rw_tile_preview" }) do
			if widgets[name] then
				widgets[name].visible = false
			end
		end
	end

	-- Per frame (only while the Deck is shown): which tile (and which pip) the pointer is on, for the Edit pill, the pips,
	-- the strip and the caption.
	View._update_deck = function (self, dt, t)
		local widgets = self._widgets_by_name
		local hovered, hovered_widget, hovered_pip = nil, nil, nil

		-- the pointer on a segment of the strip: its card (a tile on this page lights up, the name is shown over the strip)
		local strip_key
		local strip = widgets.rw_strip

		if strip and strip.visible and self._strip_segments then
			for i = 1, #self._strip_segments do
				if strip.content[h.STRIP_HOT[i]].is_hover then
					strip_key = self._strip_segments[i].key

					break
				end
			end
		end

		for i = 1, Deck.CAPACITY do
			local widget = widgets[TILE_PREFIX .. i]

			if widget and widget.visible then
				local content = widget.content
				local on_edit = content.hotspot_edit.is_hover == true
				local pip = nil

				content.strip_hover = strip_key ~= nil and content.card_key == strip_key

				for k = 1, Deck.PIPS do
					if content[IDS.hotspot_pip[k]].is_hover then
						pip = k

						break
					end
				end

				local fx = content.fx

				if fx and fx.edit_hover ~= on_edit then
					fx.edit_hover = on_edit
					widget.style.edit_bg.visible = on_edit
					paint(widget.style.edit_label, 255, on_edit and fx.ink or fx.muted)
				end

				if fx and fx.hover_level ~= pip then
					self:_paint_pips(widget, pip)
				end

				if content.hotspot_top.is_hover or content.hotspot_state.is_hover or on_edit or pip then
					hovered, hovered_widget, hovered_pip = content.card_key, widget, pip
				end
			end
		end

		local strip_name

		if strip_key and not hovered then
			hovered = strip_key

			for i = 1, #self._deck do
				if self._deck[i].key == strip_key then
					strip_name = self._deck[i].name
				end
			end
		end

		-- the resting cards: the clock, the look, and the moment a card is back (repaint + ping)
		local ping_on = mod:get("tarot_ping") ~= false

		for i = 1, Deck.CAPACITY do
			local widget = widgets[TILE_PREFIX .. i]
			local fx = widget and widget.visible and widget.content.fx

			if fx and fx.state == "cooling" then
				local remaining = cooldown_left(fx.key, fx.cooldown)

				if remaining <= 0 then
					self:_paint_tile(widget, fx.wave)

					if ping_on then
						self:_start_ping(widget)
					end
				else
					local p = math.max(0, math.min(1, 1 - remaining / math.max(1, fx.cooldown)))
					local seconds = math.ceil(remaining)

					if seconds ~= fx.clock then
						fx.clock = seconds
						widget.content.state_clock = Deck.clock_text(remaining)
					end

					if fx.look == "vial" then
						self:_animate_vial(widget, fx, p, t)
					elseif math.abs(p - fx.p) >= 0.004 then
						self:_apply_look(widget, fx, p, t)
					end
				end
			end

			fx = widget and widget.visible and widget.content.fx

			if fx and fx.ping_t then
				self:_tick_ping(widget, fx, dt or 0)
			end
		end

		if hovered ~= self._deck_hover or hovered_pip ~= self._deck_hover_pip then
			local strip_changed = hovered ~= self._deck_hover

			self._deck_hover, self._deck_hover_pip = hovered, hovered_pip

			local caption = widgets.deck_hover

			if caption then
				if hovered_widget and hovered_pip then
					caption.content.deck_hover = mod:localize("tile_pip_hover", hovered_widget.content.name, hovered_pip)
				else
					caption.content.deck_hover = hovered_widget and hovered_widget.content.name or strip_name or ""
				end
			end

			if strip_changed then
				self:_paint_strip()
			end
		end
	end

	-- ------------------------------------------------------------------------------------- callbacks
	-- a click on a tile (the face or the left of the state line): the card goes in or out of the draw
	View.cb_tile_toggle = guarded(function (self, slot)
		local wave = self._deck[self._offset + slot]

		if wave and not wave.blank then
			set_setting("on_" .. wave.key, not wave.enabled)
			self:_reload()
			self:_apply_screen(true)
		end
	end)

	-- the Edit pill of a tile, or a right click anywhere on it: the card's own screen
	View.cb_tile_edit = guarded(function (self, slot)
		local wave = self._deck[self._offset + slot]

		if wave and not wave.blank then
			self:_open_detail(wave.key)
		end
	end)

	-- a click on pip `level` of a tile: the card's chance becomes that level among the other cards of the draw (the weight
	-- that shows it, see Cards.weight_for_level)
	View.cb_tile_pip = guarded(function (self, slot, level)
		local wave = self._deck[self._offset + slot]

		if wave and not wave.blank then
			local lo, hi = self:_draw_range(wave.key)

			set_setting("pct_" .. wave.key, mod.rw.cards.weight_for_level(level, lo, hi))
			self:_reload()
			self:_apply_screen(true)
		end
	end)

	-- the blank tile: a new card in the first free custom slot
	View.cb_tile_new = guarded(function (self)
		if self._deck_free then
			self:_open_detail(self._deck_free.key)
		end
	end)
end

return DeckView
