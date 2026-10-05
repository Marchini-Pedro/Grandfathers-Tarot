-- The last card, painted (2026-10-05): the card whose wave went out last as the Spread draws it, with its caption, its whisper, its
-- suit's aura and Nightmare's fog. Shared by the HUD window (ui/hud_element_last_card.lua) and the preview on the Mirror, the card
-- face screen of the editor (ui/wave_editor_workshop.lua: "When it is drawn"). Each works on an object holding `_widget` (a widget
-- made from Definitions.passes) and `_shape_icon` (Paint.new makes one); the widget's style is written in place.
local mod = get_mod("GrandfathersTarot")

local Definitions = mod:io_dofile("GrandfathersTarot/scripts/mods/GrandfathersTarot/ui/hud_element_last_card_definitions")

local Spread = Definitions.Spread
local Aura = Definitions.Aura
local Z = Definitions.Z

local Paint = {}

-- the fonts the player can choose for the Spread's text (the same option and list as hud_element_waves.lua)
local FONTS = { itc_novarese_bold = true, itc_novarese_medium = true, friz_quadrata = true, proxima_nova_bold = true, rexlia = true, machine_medium = true }
local DEFAULT_FONT = Definitions.DISPLAY_FONT
local GLOW_EDGE = 12 -- how far the glow frame reaches beyond the card

-- style ids, built once so nothing is concatenated while the HUD runs
local WIN = { "win_t", "win_b", "win_l", "win_r" }
local RARE = { "rare_t", "rare_b", "rare_l", "rare_r" }
local ICON_T = { "icon_t1", "icon_t2", "icon_t3", "icon_t4" }
local ICON_C = { "icon_c1", "icon_c2", "icon_c3", "icon_c4" }
local ICON_TH = { "icon_th1", "icon_th2", "icon_th3", "icon_th4" }
local ICON_CH = { "icon_ch1", "icon_ch2", "icon_ch3", "icon_ch4" }
local TH_H = { "th_h1", "th_h2", "th_h3", "th_h4", "th_h5", "th_h6" }
local TH_O = { "th_o1", "th_o2", "th_o3", "th_o4", "th_o5", "th_o6" }
local DOT_H = { "dh_1", "dh_2", "dh_3", "dh_4", "dh_5", "dh_6" }
local DOT = { "dot_1", "dot_2", "dot_3", "dot_4", "dot_5", "dot_6" }
local AURA_C, AURA_R = {}, {}

for i = 1, Aura.COUNT do
	AURA_C[i], AURA_R[i] = "aura_c" .. i, "aura_r" .. i
end

local AURA_SIZE = 0.75 -- the aura's shapes on this card (the Deck's tile: 1)

local function cards_module()
	return mod.rw and mod.rw.cards
end

-- ------------------------------------------------------------------------------------------- style writers
local function box(style, x, y, w, h)
	local offset, size = style.offset, style.size

	offset[1], offset[2], size[1], size[2] = x, y, w, h
end

-- text styles keep their colour in text_color, the shapes in color
local function paint(style, alpha, rgb)
	Spread.set_color(style.text_color or style.color, alpha, rgb)
end

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

-- the feather under a shape (see Spread.FEATHER): the same shape, a little larger, one layer lower
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

-- an object to paint a last card widget with
Paint.new = function (widget)
	return { _widget = widget, _shape_icon = Spread.new_shape(Spread.ICON_TRIS, Spread.ICON_CIRCS) }
end

-- the card's name in the font the player chose for the Spread's text
Paint.chosen_font = function ()
	local font = mod:get("tarot_font")

	return FONTS[font] and font or DEFAULT_FONT
end

-- ------------------------------------------------------------------------------------------------- the card
-- Lays the card out and paints it: positions, colours, texts. Called when another card goes out (or the font option changes).
-- Since 2026-10-04 it is the card "in the hand" of the user's design page: the suit's accent as a bar on the left, the name at the top
-- with the suit mark at its right, the threat diamonds and the enemy dots on one row under it, and the whisper inside the card.
local L = Definitions.LAYOUT

Paint.setup = function (self, card, font)
	local Cards = cards_module()
	local widget = self._widget
	local style, content = widget.style, widget.content
	local suit = Cards.suit(card.suit)
	local cw = Definitions.WIDTH
	local x, y = Definitions.CARD_X, Definitions.CARD_Y
	local special = suit.special == true
	local left = x + Spread.ACCENT_WIDTH + L.pad_x

	self._font = font
	style.name.font_type = font
	style.name.font_size = L.name_font

	-- the name (one or two lines) beside the mark, the row under it, the whisper (one or two lines) under the row
	local name_w = cw - Spread.ACCENT_WIDTH - 2 * L.pad_x - L.icon - L.icon_gap
	local lines = Spread.wrap_lines(card.name, name_w, L.name_font, Spread.GLYPH_BY_FONT[font], 2)
	local whisper = tostring(card.whisper or "")
	local whisper_w = cw - Spread.ACCENT_WIDTH - 2 * L.pad_x
	local whisper_lines = whisper ~= "" and Spread.wrap_lines("\"" .. whisper .. "\"", whisper_w, L.whisper_font, 0.56, 2) or 0
	local name_y = y + L.pad_y
	local row_cy = name_y + lines * L.name_line + L.gap + Spread.ROW_HEIGHT / 2
	local whisper_y = row_cy + Spread.ROW_HEIGHT / 2 + L.gap
	local ch = whisper_y + whisper_lines * L.whisper_line + L.pad_y - y

	box(style.card_bg, x, y, cw, ch)
	box(style.card_accent, x, y, Spread.ACCENT_WIDTH, ch)
	box(style.glow, x - GLOW_EDGE, y - GLOW_EDGE, cw + 2 * GLOW_EDGE, ch + 2 * GLOW_EDGE)
	paint(style.card_bg, 255, suit.card)
	paint(style.card_accent, 255, suit.accent)
	style.card_bg.visible, style.card_accent.visible = true, true

	-- one unit of outline in the suit's frame colour (the pus yellow of a rare card; two units of blood for Heresy, which also smoulders)
	local line = special and 2 or 1

	box(style.rare_t, x, y, cw, line)
	box(style.rare_b, x, y + ch - line, cw, line)
	box(style.rare_l, x, y, line, ch)
	box(style.rare_r, x + cw - line, y, line, ch)

	for j = 1, #RARE do
		paint(style[RARE[j]], 255, (special or card.rare ~= true) and suit.frame or Cards.BASE.pus)
		style[RARE[j]].visible = true
	end

	paint(style.glow, 110, suit.frame)
	style.glow.visible = special

	box(style.name, left, name_y, name_w, lines * L.name_line + 4)
	content.name = card.name
	paint(style.name, 255, suit.text)
	style.name.visible = true

	-- the suit mark in the top right corner, in the accent (no ring: the hand card has none)
	style.sigil_ring.visible, style.sigil_disc.visible = false, false

	local shape = self._shape_icon

	Spread.icon(suit.icon, L.icon, shape)

	local ox, oy = x + cw - L.pad_x - L.icon, name_y + 1
	local feather = Spread.alpha(Spread.FEATHER_ALPHA)

	for j = 1, Spread.ICON_TRIS do
		local slot = shape.tri[j]
		local colour = slot.col == 2 and suit.card or suit.accent

		place_tri(style[ICON_T[j]], slot, ox, oy, Z.card + 10)
		place_tri_halo(style[ICON_TH[j]], slot, ox, oy, Z.card + 10)
		paint(style[ICON_T[j]], 255, colour)
		paint(style[ICON_TH[j]], feather, colour)
	end

	for j = 1, Spread.ICON_CIRCS do
		local slot = shape.circ[j]
		local colour = slot.col == 2 and suit.card or suit.accent

		place_circ(style[ICON_C[j]], slot, ox, oy, Z.card + 10)
		place_circ_halo(style[ICON_CH[j]], slot, ox, oy, Z.card + 10)
		paint(style[ICON_C[j]], 255, colour)
		paint(style[ICON_CH[j]], feather, colour)
	end

	-- the row: the threat diamonds from the left (filled up to the threat, in its colour; the rest as outlines) ...
	local side = Spread.THREAT_SIDE
	local halo = side + 1.4
	local threat = math.max(1, math.min(6, card.threat or 1))
	local threat_rgb = Cards.threat_color(threat, card.suit)

	for j = 1, #TH_O do
		local cx = left + side / 2 + (j - 1) * Spread.THREAT_PITCH
		local s_halo, s_outer = style[TH_H[j]], style[TH_O[j]]
		local filled = j <= threat
		local colour = filled and threat_rgb or Cards.BASE.muted

		s_halo.offset[1], s_halo.offset[2] = cx - halo / 2, row_cy - halo / 2
		s_outer.offset[1], s_outer.offset[2] = cx - side / 2, row_cy - side / 2
		paint(s_halo, threat == 6 and 255 or filled and 70 or 120, threat == 6 and Cards.threat_edge(card.suit) or colour)
		paint(s_outer, filled and 255 or 40, filled and colour or suit.card)
		s_halo.visible, s_outer.visible = j <= 5 or threat == 6, j <= 5 or threat == 6
	end

	-- ... and the enemy dots at the right: one per distinct enemy colour (the player's own colour settings)
	local colors = mod.rw and mod.rw.colors
	local dots = Cards.dots_from_breeds(card.breeds, function (breed)
		return colors and colors.rgb(breed) or Cards.BASE.muted
	end)
	local shown = math.min(#dots, #DOT)

	for j = 1, #DOT do
		local dot, dot_halo = style[DOT[j]], style[DOT_H[j]]

		dot.visible, dot_halo.visible = j <= shown, j <= shown

		if j <= shown then
			local d = Spread.DOT
			local dx = x + cw - L.pad_x - d - (shown - j) * Spread.DOT_PITCH

			box(dot, dx, row_cy - d / 2, d, d)
			box(dot_halo, dx - 0.6, row_cy - d / 2 - 0.6, d + 1.2, d + 1.2)
			paint(dot, 255, dots[j])
			paint(dot_halo, 70, dots[j])
		end
	end

	-- the whisper, in quotes, inside the card (Heresy's in its crimson)
	content.whisper = whisper ~= "" and ("\"" .. whisper .. "\"") or ""
	box(style.whisper, left, whisper_y, whisper_w, whisper_lines * L.whisper_line + 4)
	style.whisper.font_size = L.whisper_font
	style.whisper.offset[3] = Z.card + 20 -- over the card's face (the text layer of the old window was under it)
	paint(style.whisper, 255, card.suit == "heresy" and suit.accent or card.suit == "nightmare" and suit.lit or Cards.BASE.muted)
	style.whisper.visible = whisper ~= ""

	content.mods = ""
	style.mods.visible = false

	-- no window round it: only the caption over the card
	style.bg.visible = false

	for i = 1, #WIN do
		style[WIN[i]].visible = false
	end

	content.kicker = string.upper(mod:localize("hud_last_card"))
	box(style.kicker, 0, 0, cw / 2, 18)
	paint(style.kicker, 255, Cards.BASE.muted)
	style.kicker.visible = true

	box(style.age, cw / 2, 0, cw / 2, 18)
	paint(style.age, 255, Cards.BASE.muted)
	style.age.visible = true

	-- the suit's aura and Dream's rainbow are animated every frame (HudElementGrandfathersTarotLast._tick_aura)
	self._aura_suit = Aura.has(suit.id) and not suit.blood and not suit.gloom and suit.id or nil
	self._aura_box = { x, y, cw, ch }
	self._aura = self._aura or Aura.new()
	self._rainbow = suit.rainbow == true
	self._glow_rgb = self._glow_rgb or { 0, 0, 0 }

	for i = 1, Aura.COUNT do
		style[AURA_C[i]].visible, style[AURA_R[i]].visible = false, false
	end

	-- Nightmare's fog is animated every frame (HudElementGrandfathersTarotLast._tick_fog)
	self._fog_box = suit.fog and { x, y, cw, ch } or nil
	self._fog = self._fog or Spread.new_fog()
	style.fog_veil.visible, style.fog_1.visible, style.fog_2.visible, style.fog_3.visible = false, false, false, false

	self._seconds = nil
end

local BLACK = { 0, 0, 0 }

-- Every frame while a Nightmare card is in the window: the black fog comes and goes over it
Paint.tick_fog = function (self, t)
	local b = self._fog_box

	if not b then
		return
	end

	local Cards = cards_module()
	local style = self._widget.style
	local veil = Spread.fog(Cards, t, b[4], self._fog, mod:get("nightmare_fog_strength"))

	box(style.fog_veil, b[1], b[2], b[3], b[4])
	paint(style.fog_veil, veil, BLACK)
	style.fog_veil.visible = veil > 0

	for i = 1, 3 do
		local s, bank = style["fog_" .. i], self._fog[i]

		box(s, b[1], b[2] + bank[1], b[3], bank[2])
		paint(s, bank[3], BLACK)
		s.visible = bank[2] > 0 and bank[3] > 0
	end
end

-- Every frame: the suit's aura on the card (flames, bubbles, warp motes, clouds...), Dream's rainbow glow and frame, Brute's blows
Paint.tick_aura = function (self, t)
	local style = self._widget.style
	local b = self._aura_box
	local suit = self._aura_suit

	if not b then return end

	local glow = suit and Aura.glow(suit, t, self._glow_rgb)

	if glow then
		paint(style.glow, math.floor(170 * glow + 0.5), self._glow_rgb)
		style.glow.visible = true

		if self._rainbow then
			Aura.rainbow(t, self._glow_rgb, 0.12)

			for j = 1, #RARE do paint(style[RARE[j]], 255, self._glow_rgb) end
		end
	end

	local alive = suit ~= nil and mod:get("card_auras") ~= false and Aura.update(self._aura, suit, t, b[3], b[4], AURA_SIZE)

	for i = 1, Aura.COUNT do
		local p = self._aura[i]
		local circle_style, rect_style = style[AURA_C[i]], style[AURA_R[i]]
		local on = alive and p.on

		circle_style.visible, rect_style.visible = on and p.round, on and not p.round

		if on then
			local s = p.round and circle_style or rect_style

			box(s, b[1] + p.x, b[2] + p.y, p.w, p.h)
			paint(s, p.a, p.rgb)
		end
	end
end

return Paint
