-- The Deck: the home screen of the wave editor (screen "list"). Every card is a tile (blueprints.tile) in a grid of 7
-- columns and 2 rows, with a strip above that shows how likely each card is to be dealt into a hand. Clicking a tile
-- puts the card in or out of the draw, clicking one of its ten pips sets its chance (1 to 10), its Edit pill or a right click opens it, the blank tile at the end makes a new card.
-- The arithmetic and the texts are in ui/deck.lua; the shapes (suit marks) are drawn like the Spread HUD draws them
-- (ui/spread.lua). Installed on the view with `install` (see wave_editor_view.lua); nothing here is drawn per frame
-- except the hover.
local mod = get_mod("GrandfathersTarot")

local Text = require("scripts/utilities/ui/text")
local Aura = mod:io_dofile("GrandfathersTarot/scripts/mods/GrandfathersTarot/ui/aura")

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
-- a + (b - a) * k for {r, g, b}, written into out (no new table: this runs every frame)
local function mix_into(out, a, b, k)
	out[1], out[2], out[3] = a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k

	return out
end

local DESPAIR_DEEP = { 44, 24, 70 } -- the dark end of Despair's breathing halo (as in the HUD)
local WARM_WHITE = { 255, 250, 236 } -- the bright end of Apotheosis' glitter

local function cooldown_left(key, length)
	local director = mod.rw and mod.rw.director

	if not director or not director.cooldown_remaining then
		return 0
	end

	local ok, left = pcall(director.cooldown_remaining, key, length)

	return ok and tonumber(left) or 0
end

-- the name's font in the tile, and its average glyph width (of the font size): how many lines a name takes, see Spread.wrap_lines
local NAME_FONT, NAME_GLYPH = 20, 0.6

DeckView.install = function (View, h)
	local Deck, Spread, T, IDS = h.Deck, h.Spread, h.TILE, h.TILE_IDS
	local guarded, set_setting = h.guarded, h.set_setting
	local TILE_PREFIX = h.TILE_PREFIX
	local TILE_HOTSPOTS = { "hotspot_top", "hotspot_state", "hotspot_edit", "hotspot_share", "hotspot_cd_minus", "hotspot_cd_value", "hotspot_cd_plus" }

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

	-- The mark of a suit (`icon`: a shape id of Spread.icon) in a `size` box at (ox, oy) of the widget: every triangle and circle
	-- on its feather (the faint larger copy, Spread.FEATHER). `accent` paints the shapes of the suit's colour, `bg` the ones
	-- that cut a hole. `tri_col` and `circ_col` (optional tables) get the colour slot of every shape: the cooldown look
	-- repaints the accent ones. Used by the card tile and by the suit tiles of the quick face.
	View._paint_suit_mark = function (self, style, icon, size, ox, oy, accent, bg, tri_col, circ_col)
		local shape = self._tile_shape

		Spread.icon(icon, size, shape)

		for i = 1, Spread.ICON_TRIS do
			local s, halo = style[IDS.icon_t[i]], style[IDS.icon_th[i]]
			local rgb = shape.tri[i].col == 2 and bg or accent

			place_tri(s, shape.tri[i], ox, oy, 4)
			place_tri_halo(halo, shape.tri[i], ox, oy, 4)
			paint(s, 255, rgb)
			paint(halo, FEATHER, rgb)

			if tri_col then
				tri_col[i] = shape.tri[i].col
			end
		end

		for i = 1, Spread.ICON_CIRCS do
			local s, halo = style[IDS.icon_c[i]], style[IDS.icon_ch[i]]
			local rgb = shape.circ[i].col == 2 and bg or accent

			place_circ(s, shape.circ[i], ox, oy, 4)
			place_circ_halo(halo, shape.circ[i], ox, oy, 4)
			paint(s, 255, rgb)
			paint(halo, FEATHER, rgb)

			if circ_col then
				circ_col[i] = shape.circ[i].col
			end
		end
	end

	-- How many lines a card's name takes in its box (1 to 3). The game measures it when the editor has a renderer (it knows
	-- the font; the divider, the composition and the room for enemies follow from it), else (offline tests, a failed
	-- measurement) it is estimated from the letters, which is a little careful: a name that turns out shorter than guessed
	-- only leaves a gap, a longer one would run into the divider.
	View._name_lines = function (self, name, style, metrics)
		local T = metrics or T
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

		return Spread.wrap_lines(name, T.name[3], NAME_FONT * (T.k or 1), NAME_GLYPH)
	end

	-- A card is in the draw when it is enabled, has enemies, a weight and no fixed timer (the same rule the director uses).
	local function in_draw(wave)
		return wave.enabled and mod.rw.events.has_content(wave) and (wave.pct or 0) > 0 and not ((wave.timer or 0) > 0)
	end

	-- --------------------------------------------------------------------------------------------- model
	-- Whether a card holds the Deck's search text (lower case, plain): in its name, its suit, an enemy's name or an effect's name.
	local function holds(wave, query)
		local rw = mod.rw
		local words = { wave.name or "", rw.cards.suit(wave.suit).name }

		for _, part in ipairs(wave.parts or {}) do
			for _, breed in ipairs(part.one_of or { part.breed }) do
				words[#words + 1] = rw.groups.display_name(breed)
			end
		end

		for id in pairs(wave.effects or {}) do
			local def = rw.groups.Effects.definition(id)

			words[#words + 1] = def and def.short or ""
		end

		return table.concat(words, " "):lower():find(query, 1, true) ~= nil
	end

	-- The cards of the deck: every standard card and every custom card that has enemies, in the order of the wave list,
	-- then the blank tile (while a custom slot is free). While the Deck's search holds a text, only the cards that hold it (no blank).
	View._build_deck = function (self)
		local deck, free = {}, nil
		local query = ((self._deck_query or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))

		for i = 1, #self._waves do
			local wave = self._waves[i]

			if (mod.rw.events.has_content(wave)) or not wave.is_custom then
				if query == "" or holds(wave, query) then
					deck[#deck + 1] = wave
				end
			elseif not free then
				free = wave
			end
		end

		self._deck_free = free

		if free and query == "" then
			deck[#deck + 1] = { blank = true, key = free.key }
		end

		self._deck = deck
	end

	-- Seconds a card still rests (0 when it does not, or when no mission runs)
	View._cooldown_left = function (self, key, length)
		return cooldown_left(key, length)
	end

	-- The cards of the draw that rest after a pick leave it, so the others become likelier: the share of a card is its chance over
	-- the chances of the cards that can be dealt NOW. Called by _reload, and again when a card comes back.
	View._count_ready = function (self)
		local ready, resting = 0, {}

		for i = 1, #(self._waves or {}) do
			local wave = self._waves[i]

			if in_draw(wave) then
				if self:_cooldown_left(wave.key, wave.cooldown) > 0 then
					resting[wave.key] = true
				else
					ready = ready + wave.pct
				end
			end
		end

		self._ready_pct, self._resting = ready, resting
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
	-- The strip of the draw: a segment per card that can be dealt now (a resting card is out of the draw), as wide as its chance; the
	-- card under the pointer is taller.
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

			if not wave.blank and in_draw(wave) and not (self._resting and self._resting[wave.key]) and #items < Deck.STRIP_MAX then
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

	-- The cooldown row of a tile: "COOLDOWN 2:00" and, on the Deck's own tiles, a plate with a minus and a plate with a plus (30 s a
	-- click, drawn from rectangles like everything on the tile). `hover` is -1 or 1 while the pointer is on the minus or the plus: the
	-- value then shows what a click would set, in the card's accent, as the pips do. A plate at its limit (30 s, the longest cooldown)
	-- is dimmed and does nothing. A card with a fixed timer ignores its cooldown: the row says "EVERY 1:00" and has no plates.
	View._paint_cooldown = function (self, widget, hover)
		local style, content = widget.style, widget.content
		local fx = content.fx

		if not fx then
			return
		end

		local T = content.metrics or T
		local k = T.k or 1
		local timed = (tonumber(fx.wave.timer) or 0) > 0
		local longest = self:_longest_cooldown()
		local at_min, at_max = fx.cooldown <= Deck.COOLDOWN_STEP, fx.cooldown >= longest

		hover = hover or 0
		fx.cd_pointer = hover

		if timed then
			hover = 0
		end

		if (hover < 0 and at_min) or (hover > 0 and at_max) then
			hover = 0
		end

		fx.cd_hover = hover

		content.cd_label = string.upper(mod:localize(timed and "tile_cd_every" or "tile_cd"))
		content.cd_value = Deck.clock_text(timed and fx.wave.timer or hover ~= 0 and Deck.cooldown_after(fx.cooldown, hover, longest) or fx.cooldown)
		style.cd_label.visible, style.cd_value.visible = true, true
		paint(style.cd_label, 255, fx.muted)
		paint(style.cd_value, 255, hover ~= 0 and fx.accent or fx.ink)

		local show = content.cd_buttons == true and not timed
		local bar, thick = 8 * k, math.max(1, 2 * k)
		local plates = { { "cd_minus_bg", T.cd_minus, -1, at_min }, { "cd_plus_bg", T.cd_plus, 1, at_max } }

		for i = 1, #plates do
			local id, box, side, limit = plates[i][1], plates[i][2], plates[i][3], plates[i][4]
			local lit = hover == side
			local plate = style[id]
			local cx, cy = box[1] + box[3] / 2, box[2] + box[4] / 2

			plate.visible = show
			paint(plate, 255, mix(fx.bg, fx.accent, limit and 0.05 or lit and 0.4 or 0.16))

			local glyph_rgb = limit and fx.empty or lit and fx.ink or fx.accent

			local horizontal = style[side < 0 and "cd_minus_h" or "cd_plus_h"]

			horizontal.visible = show
			horizontal.offset[1], horizontal.offset[2], horizontal.size[1], horizontal.size[2] = cx - bar / 2, cy - thick / 2, bar, thick
			paint(horizontal, 255, glyph_rgb)

			if side > 0 then
				local vertical = style.cd_plus_v

				vertical.visible = show
				vertical.offset[1], vertical.offset[2], vertical.size[1], vertical.size[2] = cx - thick / 2, cy - bar / 2, thick, bar
				paint(vertical, 255, glyph_rgb)
			end
		end

		if not show then
			style.cd_plus_v.visible = false
		end
	end

	-- One card on its tile: the face (suit colours, name, composition, whisper, threat, dots), the chance pips and the
	-- state line. A card out of the draw is dimmed and drained of colour.
	View._paint_tile = function (self, widget, wave)
		local rw = mod.rw
		local Cards, groups, colors = rw.cards, rw.groups, rw.colors
		local style, content = widget.style, widget.content
		-- the tile's scale: 1 on the Deck, 1.4 on the stage of a card's screens (blueprints.tile_metrics)
		local T = content.metrics or T
		local k = T.k or 1
		local card = Cards.describe(wave, groups, function (breed)
			return colors and colors.rgb(breed) or Cards.BASE.muted
		end)
		local suit = Cards.suit(card.suit)
		local remaining = cooldown_left(wave.key, card.cooldown)
		local state = Deck.state(card, remaining)
		local sat = state == "off" and 0.7 or 0

		local function tone(rgb)
			return Spread.grey({ 0, 0, 0 }, rgb, sat)
		end

		local bg, accent, ink = tone(suit.card), tone(suit.accent), tone(suit.text)
		local special = suit.special == true
		local border = special and tone(suit.frame) or card.rare and tone(Cards.BASE.pus) or tone(mix(suit.frame, suit.accent, 0.45))

		-- what the per-frame cooldown looks and the pips need to know (see _apply_look, _paint_pips); a new record on every paint
		local fx = {
			key = wave.key, wave = wave, cooldown = card.cooldown, look = card.look, state = state, suit = suit, rare = card.rare, special = special,
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
		paint(style.glow, special and 150 or card.rare and 110 or 70, special and tone(suit.frame) or card.rare and Cards.BASE.pus or accent)

		-- the suit mark (26 units at scale 1) in the top right corner, each shape on a feather; the suit's name and rarity at the left
		self:_paint_suit_mark(style, suit.icon, T.icon[3], T.icon[1], T.icon[2], accent, bg, fx.tri_col, fx.circ_col)

		content.suit_label = string.upper(suit.name .. (card.rare and (" \194\183 " .. mod:localize("tile_rare")) or ""))
		style.suit_label.visible = true
		paint(style.suit_label, 255, accent)

		content.show_share_icon = mod:get("card_share_icons") ~= false
		content.hotspot_share.disabled = not content.show_share_icon
		for _, id in ipairs({ "share_l", "share_b", "share_r", "share_arrow" }) do style[id].visible = content.show_share_icon; paint(style[id], 180, accent) end
		local corners = style.share_arrow.triangle_corners
		corners[1][1], corners[1][2], corners[2][1], corners[2][2], corners[3][1], corners[3][2] = 151 * k, 256 * k, 163 * k, 256 * k, 157 * k, 250 * k
		content.name = card.name
		style.name.visible = true
		paint(style.name, 255, ink)

		-- the divider and the composition follow the name: a one line name leaves room for five lines of enemies, a two line name for four
		local name_lines = self:_name_lines(card.name, style.name, T)
		local layout = Deck.layout(name_lines)

		style.divider.visible = true
		style.divider.offset[2] = layout.divider_y * k
		paint(style.divider, 255, tone(suit.frame))

		local has_parts = wave.parts and #wave.parts > 0
		-- colour tags only while the enemy colours are on (the option "Colour enemy names")
		local colour_on = colors ~= nil and colors.rgb("chaos_poxwalker") ~= nil
		local lines = has_parts and Deck.comp_lines(wave.parts, groups, function (breed)
			return colour_on and colors.rgb(breed) or nil
		end, colour_on and colors.markup or nil, Cards.BASE.text, mod:localize("tile_repeats"), function (n)
			return mod:localize("tile_more", n)
		end, layout.comp_lines) or { mod:localize("tile_no_enemies") }

		local Effects = mod.rw.groups.Effects
		-- a beneficial card's lines: "95% Party health", the amount in the bone colour, the name in its group's colour
		content.comp = Effects.beneficial(wave.suit) and Effects.summary(wave.effects, layout.comp_lines, Deck.COMP_CHARS, colors and colors.markup or nil, Cards.BASE.text) or table.concat(lines, "\n")
		style.comp.visible = true
		style.comp.offset[2], style.comp.size[2] = layout.comp_y * k, layout.comp_h * k
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

		-- the stage card: its name and its line are click areas, underlined under the pointer (blueprints.tile, `interactive`)
		if style.hotspot_name then
			local name_h = math.max(1, math.min(3, name_lines)) * Deck.NAME_LINE * k
			local whisper_bottom = T.whisper[2] + T.whisper[4]

			style.hotspot_name.offset[1], style.hotspot_name.offset[2], style.hotspot_name.size[1], style.hotspot_name.size[2] = T.name[1], T.name[2], T.name[3], name_h
			style.hotspot_whisper.offset[1], style.hotspot_whisper.offset[2], style.hotspot_whisper.size[1], style.hotspot_whisper.size[2] = T.whisper[1], T.whisper[2], T.whisper[3], T.whisper[4]
			style.name_ul.offset[1], style.name_ul.offset[2], style.name_ul.size[1] = T.name[1], T.name[2] + name_h, T.name[3]
			style.whisper_ul.offset[1], style.whisper_ul.offset[2], style.whisper_ul.size[1] = T.whisper[1], whisper_bottom, T.whisper[3]
			paint(style.name_ul, 255, accent)
			paint(style.whisper_ul, 255, accent)
		end

		-- threat: filled diamonds up to the level (its colour), the rest the same diamonds dimmed; each on a faint feather
		local threat_rgb = Cards.threat_color(card.threat, card.suit)

		for i = 1, 6 do
			local cx = T.diamonds_x + (i - 1) * Spread.THREAT_PITCH * k
			local outer, halo = style[IDS.th_o[i]], style[IDS.th_h[i]]
			local filled = i <= card.threat
			local rgb = tone(filled and threat_rgb or Cards.BASE.muted)

			outer.visible, halo.visible = i <= 5 or card.threat == 6, i <= 5 or card.threat == 6
			outer.offset[1], outer.offset[2] = cx - 4 * k, T.row_y - 4 * k
			halo.offset[1], halo.offset[2] = cx - 4.7 * k, T.row_y - 4.7 * k
			paint(outer, filled and 255 or 64, rgb)
			paint(halo, card.threat == 6 and 255 or filled and 70 or 22, card.threat == 6 and Cards.threat_edge(card.suit) or rgb)
		end

		-- what _tick_living_tile needs every frame (the heartbeat of Heresy, the shine of the sixth diamond)
		fx.threat, fx.sat, fx.k, fx.dx, fx.row_y = card.threat, sat, k, T.diamonds_x, T.row_y
		fx.mix, fx.mix2, fx.tmp, fx.tmp2 = { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }

		-- (the fog of a Nightmare card this tile showed before is cleared; _tick_living_tile draws it again for a Nightmare card)
		if style.fog_veil then
			style.fog_veil.visible, style.fog_1.visible, style.fog_2.visible, style.fog_3.visible = false, false, false, false
		end

		-- the aura of the suit (ui/aura.lua) starts hidden too: _tick_living_tile moves it every frame
		if style[IDS.aura_c[1]] then
			for i = 1, Aura.COUNT do
				style[IDS.aura_c[i]].visible, style[IDS.aura_r[i]].visible = false, false
			end
		end

		fx.aura = Aura.new()
		fx.w, fx.h = T.w, T.h

		-- one dot per enemy colour, right aligned, each on a feather
		local dots = card.dots
		local count = math.min(#dots, 6)

		for i = 1, 6 do
			local dot, halo = style[IDS.dot[i]], style[IDS.dot_h[i]]

			dot.visible, halo.visible = i <= count, i <= count

			if i <= count then
				local x, y = T.dots_right - 9 * k - (count - i) * 13 * k, T.row_y - 4.5 * k

				dot.offset[1], dot.offset[2] = x, y
				dot.size[1], dot.size[2] = 9 * k, 9 * k
				halo.offset[1], halo.offset[2] = x - 0.6 * k, y - 0.6 * k
				halo.size[1], halo.size[2] = 10.2 * k, 10.2 * k
				paint(dot, 255, tone(dots[i]))
				paint(halo, 70, tone(dots[i]))
			end
		end

		-- the ten chance pips: filled up to the card's level among the cards of the draw
		self:_paint_pips(widget, nil)

		-- the cooldown row: what the card rests after its pick, with a minus and a plus on the Deck's own tiles
		content.cd_buttons = k == 1 or content.cd_buttons_always == true
		self:_paint_cooldown(widget, 0)

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
	--            the suit's colour; the text is faint (50 percent) and returns to full. Since 2026-10-04 it is the only look
	--            (the murmur and the vial were removed: Cards.look is always "rot")
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

			paint(style.glow, fx.special and 150 or fx.rare and 110 or 70, fx.special and fx.suit.frame or fx.rare and Cards.BASE.pus or rgb)

			if not fx.rare and not fx.special then
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

		local T = widget.content.metrics or T
		local scale = 0.96 + 0.16 * u
		local w, h = T.w * scale, T.h * scale
		local x0, y0 = (T.w - w) / 2, (T.h - h) / 2
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

	View.cb_tile_share = guarded(function (self, index)
		local wave = self._deck and self._deck[self._offset + index]
		if self._screen ~= "list" or not wave or wave.blank or mod:get("card_share_icons") == false then return end
		self:_open_detail(wave.key)
		self:cb_wave_share()
	end)

	-- ------------------------------------------------------------------------------------- the screen
	-- (Re)builds the whole Deck page: the header texts, the strip, the tiles of this page and the blank tile.
	View._refresh_deck = function (self)
		self:_end_drag()
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
	-- Every frame, on a tile that is shown (the Deck's and the stage card): a Heresy card's glow (and, while it is not cooling, its
	-- frame) beats like a heart; the sixth diamond of a threat 6 card shines, Despair darkly, Apotheosis in light. As in the HUD.
	View._tick_living_tile = function (self, widget, t)
		local fx = widget and widget.content.fx

		if not fx or fx.state == "off" or not fx.mix then
			return
		end

		local Cards = mod.rw.cards
		local style, suit = widget.style, fx.suit

		t = t or 0

		if suit.blood then
			local beat = Cards.heartbeat(t)

			paint(style.glow, math.floor(150 * (0.55 + 0.45 * beat) + 0.5), Spread.grey(fx.tmp, mix_into(fx.mix, suit.frame, suit.lit, 0.6 * beat), fx.sat))

			if fx.state ~= "cooling" then
				local edge = Spread.grey(fx.tmp2, mix_into(fx.mix2, suit.frame, suit.lit, 0.5 * beat), fx.sat)

				for i = 1, #IDS.border do
					paint(style[IDS.border[i]], 255, edge)
				end
			end
		elseif suit.gloom then
			-- Nightmare: darkness breathes around it and its frame is a dying light that flickers
			local breath, flash = Cards.dread(t)

			paint(style.glow, math.floor(200 * (0.6 + 0.4 * breath) + 0.5), Spread.grey(fx.tmp, mix_into(fx.mix, suit.gloom, suit.lit, 0.8 * flash), fx.sat))

			if fx.state ~= "cooling" then
				local edge = Spread.grey(fx.tmp2, mix_into(fx.mix2, mix_into(fx.mix, suit.gloom, suit.frame, breath), suit.lit, 0.9 * flash), fx.sat)

				for i = 1, #IDS.border do
					paint(style[IDS.border[i]], 255, edge)
				end
			end
		elseif suit.motes then
			-- Warp: an uneven pulse with crackles in its glow
			local pulse, crackle = Cards.warp_pulse(t)

			paint(style.glow, math.floor(150 * (0.45 + 0.55 * pulse) + 0.5), Spread.grey(fx.tmp, mix_into(fx.mix, suit.frame, suit.lit, 0.35 * pulse + 0.65 * crackle), fx.sat))
		else
			-- Dream's glow turns through a rainbow, Brute's flares with every blow (ui/aura.lua); Dream's frame follows its glow
			local glow = Aura.glow(suit.id, t, fx.mix)

			if glow then
				paint(style.glow, math.floor(190 * glow + 0.5), Spread.grey(fx.tmp, fx.mix, fx.sat))
			end

			if suit.rainbow and fx.state ~= "cooling" then
				local edge = Spread.grey(fx.tmp2, Aura.rainbow(t, fx.mix2, 0.12), fx.sat)

				for i = 1, #IDS.border do
					paint(style[IDS.border[i]], 255, edge)
				end
			end
		end

		-- the suit's aura (warp motes, flames, bubbles, feathers, clouds...): fainter while the card rests
		if fx.aura and style[IDS.aura_c[1]] then
			local alive = mod:get("card_auras") ~= false and Aura.update(fx.aura, suit.id, t, fx.w, fx.h, fx.k)
			local dim = fx.state == "cooling" and 0.45 or 1

			for i = 1, Aura.COUNT do
				local p = fx.aura[i]
				local circle, rect = style[IDS.aura_c[i]], style[IDS.aura_r[i]]
				local on = alive and p.on

				circle.visible, rect.visible = on and p.round, on and not p.round

				if on then
					local s = p.round and circle or rect

					s.offset[1], s.offset[2], s.size[1], s.size[2] = p.x, p.y, p.w, p.h
					paint(s, math.floor(p.a * dim + 0.5), Spread.grey(fx.tmp, p.rgb, fx.sat))
				end
			end
		end

		-- Nightmare's black fog comes and goes over the whole card
		if suit.fog and style.fog_veil then
			local H = 270 * fx.k

			fx.fog = fx.fog or Spread.new_fog()

			local veil = Spread.fog(Cards, t, H, fx.fog, mod:get("nightmare_fog_strength"))

			style.fog_veil.size[2] = H
			style.fog_veil.color[1] = veil
			style.fog_veil.visible = veil > 0

			for i = 1, 3 do
				local s, bank = style["fog_" .. i], fx.fog[i]

				s.offset[2], s.size[2], s.color[1] = bank[1], bank[2], bank[3]
				s.visible = bank[2] > 0 and bank[3] > 0
			end
		elseif style.fog_veil and style.fog_veil.visible then
			style.fog_veil.visible, style.fog_1.visible, style.fog_2.visible, style.fog_3.visible = false, false, false, false
		end

		if fx.threat == 6 then
			local shine = Cards.six_shine(t, suit)
			local k = fx.k
			local size = (9.4 + 2.6 * shine) * k
			local fill = Cards.threat_color(6, suit)

			for i = 1, 6 do
				local halo, outer = style[IDS.th_h[i]], style[IDS.th_o[i]]
				local cx = fx.dx + (i - 1) * Spread.THREAT_PITCH * k

				halo.size[1], halo.size[2] = size, size

				if halo.pivot then
					halo.pivot[1], halo.pivot[2] = size / 2, size / 2
				end

				halo.offset[1], halo.offset[2] = cx - size / 2, fx.row_y - size / 2

				if suit.beneficial then
					paint(halo, math.floor(160 + 95 * shine), Spread.grey(fx.tmp, mix_into(fx.mix, suit.accent, Cards.APOTHEOSIS_EDGE, shine), fx.sat))
					paint(outer, 255, Spread.grey(fx.tmp2, mix_into(fx.mix2, fill, WARM_WHITE, 0.45 * shine), fx.sat))
				else
					paint(halo, math.floor(140 + 115 * shine), Spread.grey(fx.tmp, mix_into(fx.mix, DESPAIR_DEEP, Cards.DESPAIR_EDGE, shine), fx.sat))
					paint(outer, 255, Spread.grey(fx.tmp2, mix_into(fx.mix2, fill, DESPAIR_DEEP, 0.6 * shine), fx.sat))
				end
			end
		end
	end

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

				-- the pointer on the minus or the plus of the cooldown row: the value shows what a click would set
				local cd_dir = content.hotspot_cd_minus.is_hover and -1 or content.hotspot_cd_plus.is_hover and 1 or 0
				local fx = content.fx

				if fx and (fx.cd_pointer or 0) ~= cd_dir then
					self:_paint_cooldown(widget, cd_dir)
				end

				if fx and fx.edit_hover ~= on_edit then
					fx.edit_hover = on_edit
					widget.style.edit_bg.visible = on_edit
					paint(widget.style.edit_label, 255, on_edit and fx.ink or fx.muted)
				end

				if fx and fx.hover_level ~= pip then
					self:_paint_pips(widget, pip)
				end

				if content.hotspot_top.is_hover or content.hotspot_state.is_hover or on_edit or pip or cd_dir ~= 0 or content.hotspot_cd_value.is_hover then
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
					self:_count_ready()
					self:_paint_strip()
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

					if math.abs(p - fx.p) >= 0.004 then
						self:_apply_look(widget, fx, p, t)
					end
				end
			end

			fx = widget and widget.visible and widget.content.fx

			if fx and fx.ping_t then
				self:_tick_ping(widget, fx, dt or 0)
			end

			if fx then
				self:_tick_living_tile(widget, t)
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

	-- ------------------------------------------------------------------------------------- order, sort, drag
	-- The keys of every card in the order shown now (the empty slots of custom cards and the blank tile are not in the Deck, they
	-- keep their place among the others).
	local function current_order(self)
		return mod.rw.events.ordered_keys(function (id) return mod:get(id) end)
	end

	local function save_order(self, keys, sort, desc)
		mod.rw.events.set_order(set_setting, keys)
		set_setting("deck_sort", sort or "")
		set_setting("deck_sort_desc", desc == true)
		self:_reload()
		self:_apply_screen(true)
	end

	-- A Sort button: the cards go in that order; a second click on the same button turns it round. The order is saved (the draw does
	-- not care about it), moving a card by hand afterwards leaves the sort button unlit.
	View.cb_sort = guarded(function (self, mode)
		if self._screen ~= "list" or (mode ~= "threat" and mode ~= "rarity" and mode ~= "enemies" and mode ~= "face") then
			return
		end

		local rw = mod.rw
		local items, in_deck = {}, {}

		for i = 1, #self._deck do
			local wave = self._deck[i]

			if not wave.blank then
				local card = rw.cards.describe(wave, rw.groups)

				in_deck[wave.key] = true
				items[#items + 1] = {
					key = wave.key,
					threat = card.threat,
					chance = tonumber(wave.pct) or 0,
					enemies = rw.groups.total_count(wave.parts),
					suit = rw.cards.suit_index and rw.cards.suit_index(card.suit) or 0,
				}
			end
		end

		local desc = mod:get("deck_sort") == mode and mod:get("deck_sort_desc") ~= true
		local sorted = Deck.sorted(items, mode, desc)
		local keys = {}

		for i = 1, #sorted do
			keys[i] = sorted[i].key
		end

		-- the slots that are not cards yet stay after them
		for _, key in ipairs(current_order(self)) do
			if not in_deck[key] then
				keys[#keys + 1] = key
			end
		end

		save_order(self, keys, mode, desc)
	end)

	-- the virtual position of the pointer (the editor is 1920 x 1080 whatever the window is)
	View._cursor_point = function (self, input_service)
		local cursor = input_service and input_service:get("cursor")

		if not cursor then
			return nil
		end

		local inverse = (self._render_settings and self._render_settings.inverse_scale) or (self._render_scale and self._render_scale > 0 and 1 / self._render_scale) or 1

		return cursor[1] * inverse, cursor[2] * inverse
	end

	-- the slot (1 to 14) of the tile of this page that the point is on
	View._tile_slot_at = function (self, x, y)
		for slot = 1, Deck.CAPACITY do
			local wave = self._deck[self._offset + slot]

			if wave and not wave.blank then
				local tx, ty = Deck.tile_pos(slot)

				if x >= tx and x <= tx + Deck.TILE_W and y >= ty and y <= ty + Deck.TILE_H then
					return slot
				end
			end
		end

		return nil
	end

	-- A tile of the Deck held with the left button for Deck.DRAG_HOLD seconds is lifted and follows the pointer; where it is let go
	-- over another tile the two cards swap places. Let go anywhere else it goes back. (Only the cards of the page shown.)
	View._end_drag = function (self)
		local drag, widgets = self._drag, self._widgets_by_name

		if drag and widgets then
			local widget = widgets[TILE_PREFIX .. drag.slot]

			if widget then
				local x, y = Deck.tile_pos(drag.slot)

				self:_set_scenegraph_position(TILE_PREFIX .. drag.slot, x, y, 3)
				widget.alpha_multiplier = drag.alpha
			end

			local target = drag.target and widgets[TILE_PREFIX .. drag.target]

			if target then
				target.alpha_multiplier = drag.target_alpha
			end
		end

		self._press, self._drag = nil, nil
	end

	View._update_deck_drag = function (self, input_service, dt)
		if self._popup or not self._deck or self._screen ~= "list" then
			if self._drag then
				self:_end_drag()
				self:_apply_screen(true)
			end

			self._press = nil

			return
		end

		local widgets = self._widgets_by_name
		local held = input_service ~= nil and input_service:get("left_hold") == true
		local x, y = self:_cursor_point(input_service)
		self._deck_cursor_x, self._deck_cursor_y = x, y
		local drag = self._drag

		if not drag then
			local press = self._press

			if not held then
				-- Hotspot releases run during drawing, after update. Retain an armed click for that frame only.
				if press and not press.released then
					press.released = true
				else
					self._press = nil
				end

				return
			end

			if not press or not x then
				return
			end

			press.t = press.t + (dt or 0)

			if press.t < Deck.DRAG_HOLD then
				return
			end

			local tx, ty = Deck.tile_pos(press.slot)

			drag = { slot = press.slot, gx = (press.x or x) - tx, gy = (press.y or y) - ty, alpha = widgets[TILE_PREFIX .. press.slot].alpha_multiplier }
			self._drag, self._press = drag, nil
		end

		local widget = widgets[TILE_PREFIX .. drag.slot]

		if not x then
			self:_end_drag()
			self:_apply_screen(true)

			return
		end

		if held and x then
			-- the lifted tile follows the pointer above the others; the tile under it is dimmed: the one it would swap with
			widget.alpha_multiplier = 0.85
			self:_set_scenegraph_position(TILE_PREFIX .. drag.slot, x - drag.gx, y - drag.gy, 40)

			local target = self:_tile_slot_at(x, y)

			if target == drag.slot then
				target = nil
			end

			if target ~= drag.target then
				local old = drag.target and widgets[TILE_PREFIX .. drag.target]

				if old then
					old.alpha_multiplier = drag.target_alpha
				end

				if target then
					drag.target_alpha = widgets[TILE_PREFIX .. target].alpha_multiplier
					widgets[TILE_PREFIX .. target].alpha_multiplier = 0.45
				end

				drag.target = target
			end

			drag.x, drag.y = x, y

			return
		end

		-- let go: swap with the tile it is over (the pointer where it was last seen), or go back
		local target = self:_tile_slot_at(x, y)

		if target == drag.slot then
			target = nil
		end

		self:_end_drag()

		local a, b = self._deck[self._offset + drag.slot], target and self._deck[self._offset + target]

		if a and b and not a.blank and not b.blank then
			local keys = current_order(self)
			local ia, ib

			for i = 1, #keys do
				if keys[i] == a.key then
					ia = i
				elseif keys[i] == b.key then
					ib = i
				end
			end

			save_order(self, Deck.swapped(keys, ia, ib), "", false)
		else
			self:_apply_screen(true)
		end
	end

	-- ------------------------------------------------------------------------------------- callbacks
	View.cb_tile_press = guarded(function (self, slot, toggle)
		local wave = self._deck[self._offset + slot]

		if self._screen == "list" and not self._drag and wave and not wave.blank then
			self._press = { slot = slot, key = wave.key, toggle = toggle, t = 0, x = self._deck_cursor_x, y = self._deck_cursor_y }
		end
	end)

	View.cb_tile_release = guarded(function (self, slot)
		local press = self._press
		local wave = self._deck[self._offset + slot]

		self._press = nil

		if press and press.slot == slot and press.toggle and wave and wave.key == press.key and self._screen == "list" then
			self:cb_tile_toggle(slot)
		end
	end)

	-- a click on a tile (the face or the left of the state line): the card goes in or out of the draw
	View.cb_tile_toggle = guarded(function (self, slot)
		-- (the release that ends a drag is not a click)
		if self._drag then
			return
		end

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

	-- a click on pip `level` of a tile: the card's chance becomes that number (1 to 10)
	View.cb_tile_pip = guarded(function (self, slot, level)
		local wave = self._deck[self._offset + slot]

		if wave and not wave.blank then
			set_setting("pct_" .. wave.key, mod.rw.cards.weight_for_level(level))
			self:_reload()
			self:_apply_screen(true)
		end
	end)

	-- a click on the minus or the plus of a tile's cooldown row: the cooldown changes by 30 seconds (between 30 s and the longest cooldown
	-- option); a card with a fixed timer ignores its cooldown, so nothing changes there
	View.cb_tile_cooldown = guarded(function (self, slot, delta)
		local wave = self._deck[self._offset + slot]

		if self._screen == "list" and wave and not wave.blank and (tonumber(wave.timer) or 0) <= 0 then
			set_setting("cd_" .. wave.key, Deck.cooldown_after(wave.cooldown, delta, self:_longest_cooldown()))
			self:_reload()
			self:_apply_screen(true)
		end
	end)

	-- a click on the value: the number box of the cooldown (seconds)
	View.cb_tile_cooldown_input = guarded(function (self, slot)
		local wave = self._deck[self._offset + slot]

		if self._screen == "list" and wave and not wave.blank and (tonumber(wave.timer) or 0) <= 0 then
			local key = wave.key

			h.Popup.open(self, {
				label = mod:localize("popup_cooldown_title", wave.name),
				value = tostring(math.floor(wave.cooldown)),
				numeric = true, min = Deck.COOLDOWN_STEP, max = self:_longest_cooldown(), integer = true,
				set = function (value)
					set_setting("cd_" .. key, value)
					self:_reload()
					self:_apply_screen(true)
				end,
			})
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
