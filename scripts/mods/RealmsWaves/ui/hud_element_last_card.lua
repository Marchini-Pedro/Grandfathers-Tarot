-- The "last card" HUD window: the card whose wave went out last, as the Spread draws it, with how long ago it was and its whisper and
-- modifiers. It renders what core/director.lua's view() returns (view.last, view.last_seq, view.last_age): on the host the
-- authoritative card, on clients the last one the host synced, so every player sees the same card. It stays on the screen until the
-- next card goes out (the Spread itself is gone a few seconds after the pick); before the first card of a mission there is no window.
--
-- No allocation per frame: the geometry and the colours are written into the widget style when the card changes (the table
-- view.last stays the same until another card goes out), and only the age text changes, once a second.
--
-- Position: the "panel" scenegraph node is the ONE movable node of the custom_hud mod (its edit mode lists this element as
-- "HudElementRealmsWavesLast|panel"); a sample card is shown while that edit mode is open. The option "Show the last card window" turns
-- it off.
local mod = get_mod("RealmsWaves")

local Definitions = mod:io_dofile("RealmsWaves/scripts/mods/RealmsWaves/ui/hud_element_last_card_definitions")

local Spread = Definitions.Spread
local Z = Definitions.Z

local HudElementRealmsWavesLast = class("HudElementRealmsWavesLast", "HudElementBase")

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
local TH_H = { "th_h1", "th_h2", "th_h3", "th_h4", "th_h5" }
local TH_O = { "th_o1", "th_o2", "th_o3", "th_o4", "th_o5" }
local DOT_H = { "dh_1", "dh_2", "dh_3", "dh_4", "dh_5", "dh_6" }
local DOT = { "dot_1", "dot_2", "dot_3", "dot_4", "dot_5", "dot_6" }

-- what the custom_hud edit mode shows when no card has gone out yet
local SAMPLE = { key = "sample", name = "The Chariot", suit = "rage", threat = 3, breeds = { "renegade_executor", "renegade_gunner", "cultist_shocktrooper" }, whisper = "Faster. Faster.", modifiers = "Enraged", rare = false, cooldown = 180 }
local SAMPLE_AGE = 154

local function cards_module()
	return mod.rw and mod.rw.cards
end

local function customizing()
	local custom_hud = get_mod("custom_hud")

	return custom_hud ~= nil and custom_hud.is_customizing == true
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

-- ------------------------------------------------------------------------------------------------- init
HudElementRealmsWavesLast.init = function (self, parent, draw_layer, start_scale)
	HudElementRealmsWavesLast.super.init(self, parent, draw_layer, start_scale, Definitions)

	self._widget = self._widgets_by_name.last
	self._shape_icon = Spread.new_shape(Spread.ICON_TRIS, Spread.ICON_CIRCS)
	self._card, self._seq, self._seconds, self._font = nil, nil, nil, nil
	self._visible = false
	self._widget.visible = false
end

-- ----------------------------------------------------------------------------------------- visibility
HudElementRealmsWavesLast._hide = function (self)
	self._widget.visible = false
	self._visible = false
	self._card, self._seq, self._seconds = nil, nil, nil
end

-- the card's name in the font the player chose for the Spread's text
local function chosen_font()
	local font = mod:get("tarot_font")

	return FONTS[font] and font or DEFAULT_FONT
end

-- ------------------------------------------------------------------------------------------------- the card
-- Lays the card out and paints it: positions, colours, texts. Called when another card goes out (or the font option changes).
HudElementRealmsWavesLast._setup = function (self, card, font)
	local Cards = cards_module()
	local widget = self._widget
	local style, content = widget.style, widget.content
	local suit = Cards.suit(card.suit)
	local cw = Definitions.CARD_W
	local x, y = Definitions.CARD_X, Definitions.CARD_Y

	self._font = font
	style.name.font_type = font

	-- the card: as tall as its name needs (a one-card Spread is laid out the same way)
	local name_w = cw - Spread.ACCENT_WIDTH - 2 * Spread.PAD_X - Spread.ICON - Spread.ICON_GAP
	local lines = Spread.wrap_lines(card.name, name_w, Spread.NAME_FONT, Spread.GLYPH_BY_FONT[font])
	local ch = math.max(Spread.MIN_CARD_HEIGHT, 2 * Spread.PAD_Y + lines * Spread.NAME_LINE + 4 + Spread.ROW_HEIGHT)
	local special = suit.special == true

	box(style.card_bg, x, y, cw, ch)
	box(style.card_accent, x, y, Spread.ACCENT_WIDTH, ch)
	box(style.glow, x - GLOW_EDGE, y - GLOW_EDGE, cw + 2 * GLOW_EDGE, ch + 2 * GLOW_EDGE)

	-- The card has an outline of its own (it sits on a panel nearly as dark as its face): one unit in the suit's frame colour, the pus
	-- yellow of a rare card, two units of blood red for Heresy (the Spread draws only the last two).
	local line = special and 2 or 1

	box(style.rare_t, x, y, cw, line)
	box(style.rare_b, x, y + ch - line, cw, line)
	box(style.rare_l, x, y, line, ch)
	box(style.rare_r, x + cw - line, y, line, ch)

	paint(style.card_bg, 255, suit.card)
	paint(style.card_accent, 255, suit.accent)

	if special then
		-- a card apart: its blood-red glow smoulders (the window is a place where the card rests, so no flare)
		paint(style.glow, 110, suit.frame)
		style.glow.visible = true
	else
		style.glow.visible = false
	end

	for j = 1, #RARE do
		paint(style[RARE[j]], 255, (special or card.rare ~= true) and suit.frame or Cards.BASE.pus)
		style[RARE[j]].visible = true
	end

	-- the name and the suit mark in the top right corner
	box(style.name, x + Spread.ACCENT_WIDTH + Spread.PAD_X, y + Spread.PAD_Y, name_w, lines * Spread.NAME_LINE)
	content.name = card.name
	paint(style.name, 255, suit.text)
	style.name.visible = true

	local shape = self._shape_icon

	Spread.icon(suit.icon, Spread.ICON, shape)

	local ox, oy = x + cw - Spread.PAD_X - Spread.ICON, y + Spread.PAD_Y
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

	-- the bottom row: the threat diamonds from the left (filled up to the threat, in its colour; the rest dimmed) ...
	local cy = y + ch - Spread.PAD_Y - Spread.ROW_HEIGHT / 2
	local side = Spread.THREAT_SIDE
	local halo = side + 1.4
	local threat = math.max(1, math.min(5, card.threat or 1))
	local threat_rgb = Cards.THREAT_COLORS[threat]

	for j = 1, #TH_O do
		local cx = x + Spread.ACCENT_WIDTH + Spread.PAD_X + side / 2 + (j - 1) * Spread.THREAT_PITCH
		local s_halo, s_outer = style[TH_H[j]], style[TH_O[j]]
		local filled = j <= threat
		local colour = filled and threat_rgb or Cards.BASE.muted

		s_halo.offset[1], s_halo.offset[2] = cx - halo / 2, cy - halo / 2
		s_outer.offset[1], s_outer.offset[2] = cx - side / 2, cy - side / 2
		paint(s_halo, filled and 70 or 22, colour)
		paint(s_outer, filled and 255 or 64, colour)
		s_halo.visible, s_outer.visible = true, true
	end

	-- ... and the enemy dots to the right: one per distinct enemy colour (the player's own colour settings)
	local colors = mod.rw and mod.rw.colors
	local dots = Cards.dots_from_breeds(card.breeds, function (breed)
		return colors and colors.rgb(breed) or Cards.BASE.muted
	end)
	local d, pitch, shown = Spread.dots_fit(cw, #dots)

	for j = 1, #DOT do
		local dot, dot_halo = style[DOT[j]], style[DOT_H[j]]

		dot.visible, dot_halo.visible = j <= shown, j <= shown

		if j <= shown then
			local dx = x + cw - Spread.PAD_X - d - (shown - j) * pitch

			box(dot, dx, cy - d / 2, d, d)
			box(dot_halo, dx - 0.6, cy - d / 2 - 0.6, d + 1.2, d + 1.2)
			paint(dot, 255, dots[j])
			paint(dot_halo, 70, dots[j])
		end
	end

	-- under the card: its whisper in quotes and its modifiers
	local whisper_y = y + ch + 6
	local whisper = tostring(card.whisper or "")
	local mods = string.upper(card.modifiers or "")

	content.whisper = whisper ~= "" and ("\"" .. whisper .. "\"") or ""
	box(style.whisper, x, whisper_y, cw, 34)
	paint(style.whisper, 255, Cards.BASE.whisper)
	style.whisper.visible = whisper ~= ""

	content.mods = mods
	local mods_h = mods ~= "" and Spread.wrap_lines(mods, cw, 12, 0.70, 8) * 16 or 0

	box(style.mods, x, whisper_y + (whisper ~= "" and 36 or 0), cw, mods_h)
	paint(style.mods, 255, Cards.BASE.rust)
	style.mods.visible = mods ~= ""

	local bottom = whisper_y + (whisper ~= "" and 36 or 0) + mods_h + 8

	bottom = math.min(bottom, Definitions.HEIGHT)

	-- the window round it: a panel (darker than any card) and a neutral line, a caption
	local w = Definitions.WIDTH

	box(style.bg, 0, 0, w, bottom)
	paint(style.bg, 225, Cards.BASE.ground)
	style.bg.visible = true

	box(style.win_t, 0, 0, w, 1)
	box(style.win_b, 0, bottom - 1, w, 1)
	box(style.win_l, 0, 0, 1, bottom)
	box(style.win_r, w - 1, 0, 1, bottom)

	for i = 1, #WIN do
		paint(style[WIN[i]], 255, Cards.BASE.line)
		style[WIN[i]].visible = true
	end

	content.kicker = string.upper(mod:localize("hud_last_card"))
	box(style.kicker, 12, 8, 110, 18)
	paint(style.kicker, 255, Cards.BASE.muted)
	style.kicker.visible = true

	box(style.age, 88, 8, 100, 18)
	paint(style.age, 255, Cards.BASE.muted)
	style.age.visible = true

	self._seconds = nil
end

-- "m:ss ago" in played seconds (rounded down: the card is exactly as old as the seconds that have passed)
HudElementRealmsWavesLast._tick_age = function (self, age)
	local seconds = math.floor(math.max(0, age))

	if seconds ~= self._seconds then
		self._seconds = seconds
		self._widget.content.age = mod:localize("hud_last_ago", Spread.time_text(seconds))
	end
end

-- ------------------------------------------------------------------------------------------------ refresh
HudElementRealmsWavesLast._refresh = function (self)
	local rw = mod.rw
	local director = rw and rw.director
	local sample = customizing()

	if not director or not mod:is_enabled() or ((mod:get("hud_enabled") == false or mod:get("hud_last_card") == false) and not sample) then
		return self:_hide()
	end

	local view = director.view()
	local card, seq, age = view.last, view.last_seq or 0, view.last_age or 0

	if not card and sample then
		card, seq, age = SAMPLE, -1, SAMPLE_AGE
	end

	if not card then
		return self:_hide()
	end

	local font = chosen_font()

	if card ~= self._card or seq ~= self._seq or font ~= self._font then
		self._card, self._seq = card, seq
		self:_setup(card, font)
	end

	self._visible = true
	self._widget.visible = true
	self:_tick_age(age)
end

HudElementRealmsWavesLast.update = function (self, dt, t, ui_renderer, render_settings, input_service)
	HudElementRealmsWavesLast.super.update(self, dt, t, ui_renderer, render_settings, input_service)

	local ok, err = pcall(self._refresh, self)

	if not ok then
		self:_hide()

		if not self._reported then
			self._reported = true

			mod:error("[hud] last card refresh failed: %s", tostring(err))
		end
	end
end

return HudElementRealmsWavesLast
