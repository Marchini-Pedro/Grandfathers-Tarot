-- On-screen wave HUD. It renders whatever core/director.lua's view() returns; on the host that is the authoritative
-- state, on clients the last state the host synced.
--
--   Tarot draw (default): "The Spread". A hand of cards with a fuse; the last seconds a highlight ticks across the cards
--   and lands on the winner (the host chose it when the hand was dealt); the winner's eye opens, the others fall away and
--   the winner is eaten by rot. Where the Spread is on its timeline comes from the view only (remaining seconds, seconds
--   since the pick), so every player sees the same picture, even one who joined in the middle of it.
--   Random countdown / Votes (legacy): the old text panel.
--
-- No allocation per frame: geometry and colours are written into the widget styles when the hand changes, a stage is
-- entered or the highlight moves, and only the winner animates every frame. The arithmetic is in ui/spread.lua.
--
-- Position: the "panel" scenegraph node is the ONE movable node of the custom_hud mod (its edit mode lists this element as
-- "HudElementGrandfathersTarotPanel|panel"); a sample hand is shown while that edit mode is open.
local mod = get_mod("GrandfathersTarot")

local Definitions = mod:io_dofile("GrandfathersTarot/scripts/mods/GrandfathersTarot/ui/hud_element_waves_definitions")

local Spread = Definitions.Spread
local Aura = Definitions.Aura
local Z = Definitions.Z

local HudElementGrandfathersTarotPanel = class("HudElementGrandfathersTarotPanel", "HudElementBase")

local COLOUR_HEADER = { 255, 255, 220, 90 }
local COLOUR_URGENT = { 255, 255, 120, 90 }
local COLOUR_LINE = { 255, 235, 235, 235 }
local COLOUR_MINE = { 255, 120, 235, 120 }
local COLOUR_HINT = { 200, 190, 190, 190 }

local GLOW_EDGE = 12 -- how far the glow frame reaches beyond the card
local WASH_COLOR = { 70, 52, 20 } -- the brown tint of a rotting card
local FLY_RING = { 138, 154, 85 }
local FLY_CORE = { 29, 33, 19 }
local DRIP_COLOR = { 111, 130, 34 }

-- the fonts the player can choose for the Spread's text (all exist in the game: ui_fonts_definitions.lua)
local FONTS = { itc_novarese_bold = true, itc_novarese_medium = true, friz_quadrata = true, proxima_nova_bold = true, rexlia = true, machine_medium = true }
local DEFAULT_FONT = Definitions.DISPLAY_FONT

-- style ids, built once so nothing is concatenated while the HUD runs
local CARD = { "card_1", "card_2", "card_3", "card_4", "card_5" }
local RARE = { "rare_t", "rare_b", "rare_l", "rare_r" }
local ICON_T = { "icon_t1", "icon_t2", "icon_t3", "icon_t4" }
local ICON_C = { "icon_c1", "icon_c2", "icon_c3", "icon_c4" }
local ICON_TH = { "icon_th1", "icon_th2", "icon_th3", "icon_th4" }
local ICON_CH = { "icon_ch1", "icon_ch2", "icon_ch3", "icon_ch4" }
local TH_H = { "th_h1", "th_h2", "th_h3", "th_h4", "th_h5", "th_h6" }
local BLOOD, BLOOD_C = { "blood_1", "blood_2", "blood_3" }, { "blood_c1", "blood_c2", "blood_c3" }
local FOG = { "fog_1", "fog_2", "fog_3" }
local AURA_C, AURA_R, AURA_T = {}, {}, {}

for i = 1, Aura.COUNT do
	AURA_C[i], AURA_R[i] = "aura_c" .. i, "aura_r" .. i
end

for i = 1, Aura.TRIS do
	AURA_T[i] = "aura_t" .. i
end

local Murmur = mod:io_dofile("GrandfathersTarot/scripts/mods/GrandfathersTarot/ui/murmur_text")

local AURA_SIZE = 0.65 -- the aura's shapes on the Spread's cards (the Deck's tile is bigger: 1)
local BLACK = { 0, 0, 0 }
local MURMUR_SECONDS = 1.6 -- a threat 5 or 6 card writes its whisper letter by letter in this time after it is shown
local DESPAIR_DEEP = { 44, 24, 70 } -- the dark end of Despair's breathing halo (the pale end is Cards.DESPAIR_EDGE)
local WARM_WHITE = { 255, 250, 236 } -- the bright end of Apotheosis' glitter
local TH_O = { "th_o1", "th_o2", "th_o3", "th_o4", "th_o5", "th_o6" }
local DOT_H = { "dh_1", "dh_2", "dh_3", "dh_4", "dh_5", "dh_6" }
local DOT = { "dot_1", "dot_2", "dot_3", "dot_4", "dot_5", "dot_6" }
local DRIP = { "drip_1", "drip_2", "drip_3" }
local FLY_R = { "fly_r1", "fly_r2", "fly_r3", "fly_r4", "fly_r5", "fly_r6", "fly_r7", "fly_r8", "fly_r9" }
local FLY_C = { "fly_c1", "fly_c2", "fly_c3", "fly_c4", "fly_c5", "fly_c6", "fly_c7", "fly_c8", "fly_c9" }
local EYE_T, BLOT = {}, {}

for i = 1, Spread.EYE_TRIS do
	EYE_T[i] = "eye_t" .. i
end

for i = 1, Spread.BLOTCHES do
	BLOT[i] = {}

	for ring = 1, #Spread.BLOTCH_RINGS do
		BLOT[i][ring] = "blot_" .. i .. "_" .. ring
	end
end

-- the player's own timeline options (screen only) with their defaults, see the options menu
local TIMING = {
	scale = { "tarot_scale", 100 }, -- percent
	opacity = { "tarot_opacity", 100 }, -- percent
	roulette = { "tarot_roulette", 1.6 },
	winner = { "tarot_winner", 1.6 },
	eye = { "tarot_eye_open", 0.4 },
	eye_size = { "tarot_eye_size", 28 },
	rot_short = { "tarot_rot_short", 1.2 },
	rot_long = { "tarot_rot_long", 3.0 },
	longest = { "tarot_longest", 30 }, -- minutes
}

local function option(spec)
	local value = mod:get(spec[1])

	return type(value) == "number" and value or spec[2]
end

local function cards_module()
	return mod.rw and mod.rw.cards
end

local function time_text(seconds)
	return Spread.time_text(seconds)
end

-- 52.100000000000001 -> "52.1", 12.0 -> "12"
local function pct_text(value)
	local text = string.format("%.1f", tonumber(value) or 0)

	return (text:gsub("%.0$", ""))
end

local function key_label(index)
	local keys = mod:get("vote_" .. index .. "_bind")

	if type(keys) == "table" and #keys > 0 then
		return string.upper(table.concat(keys, "+"))
	end

	return tostring(index)
end

local function hint_text(count)
	local labels = {}

	for i = 1, count do
		labels[#labels + 1] = string.format("%s=%d", key_label(i), i)
	end

	return table.concat(labels, "  ")
end

local SAMPLE = {
	phase = "voting",
	mode = "vote",
	remaining = 45,
	ballot_id = 0,
	chosen = "",
	version = 0,
	my_vote = 1,
	cands = {
		{ name = "Hound Frenzy", pct = 9, votes = 2 },
		{ name = "Elite Squad", pct = 8, votes = 1 },
		{ name = "Medium Wave", pct = 14, votes = 0 },
	},
}

-- what the custom_hud edit mode shows when nothing is running: a hand, mid-countdown
local SAMPLE_TAROT = {
	phase = "hand",
	mode = "tarot",
	remaining = 7.4,
	hand_seconds = 10,
	hand_seq = -1,
	win = 2,
	drawn = false,
	drawn_age = 0,
	version = 0,
	cands = {},
	hand = {
		{ key = "s1", name = "The Multitude", suit = "swarm", threat = 3, breeds = { "chaos_poxwalker", "renegade_rifleman" }, whisper = "Too many to count.", modifiers = "", rare = false, cooldown = 120 },
		{ key = "s2", name = "The Devil", suit = "fateful", threat = 5, breeds = { "chaos_beast_of_nurgle", "chaos_spawn" }, whisper = "Something big is listening.", modifiers = "", rare = false, cooldown = 240 },
		{ key = "s3", name = "The Tower", suit = "blight", threat = 3, breeds = { "chaos_poxwalker_bomber" }, whisper = "Pop, pop, pop.", modifiers = "", rare = false, cooldown = 150 },
		{ key = "s4", name = "Death", suit = "fateful", threat = 5, breeds = { "renegade_shocktrooper", "chaos_ogryn_executor", "renegade_executor", "chaos_plague_ogryn" }, whisper = "It was always going to end here.", modifiers = "Enraged", rare = true, cooldown = 300 },
	},
}

-- every widget hidden (the legacy lines emptied); the stages show what they need
local function set_all_hidden(self)
	local by_name = self._widgets_by_name

	for name, widget in pairs(by_name) do
		widget.visible = false

		if name == "legacy" then
			for i = 0, Definitions.LINES - 1 do
				widget.content["line_" .. i] = ""
			end
		end
	end
end

HudElementGrandfathersTarotPanel.init = function (self, parent, draw_layer, start_scale)
	HudElementGrandfathersTarotPanel.super.init(self, parent, draw_layer, start_scale, Definitions)

	self._sig = nil
	self._visible = false

	-- the Spread's state
	self._layout = Spread.new_layout()
	self._timeline = Spread.new_timeline()
	self._rot = Spread.new_rot()
	self._shape_icon = Spread.new_shape(Spread.ICON_TRIS, Spread.ICON_CIRCS)
	self._shape_eye = Spread.new_shape(Spread.EYE_TRIS, Spread.EYE_CIRCS)
	self._T = { roulette = 1.6, winner = 1.6, eye = 0.4, eye_size = 28, rot_short = 1.2, rot_long = 3.0, longest = 10, rot = 1.2, k = 0 }
	self._cards = {}

	for i = 1, Spread.MAX_CARDS do
		self._cards[i] = {
			mode = 0, eye_open = 0, suit = nil, threat = 1, dots = 0, dot_d = 9, dot_pitch = 13, name = "", x = 0, y = 0, cw = 0, ch = 0,
			tri_col = { 1, 1, 1, 1 }, circ_col = { 1, 1, 1, 1 }, rare = false,
			-- the chosen card loses its colour: 0 = as it is, 1 = completely grey; the palette is rewritten into these
			desat = 0, tmp = { 0, 0, 0 }, p_bg = { 0, 0, 0 }, p_accent = { 0, 0, 0 }, p_text = { 0, 0, 0 }, mix = { 0, 0, 0 }, mix2 = { 0, 0, 0 },
			dot_rgb = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } },
		}
	end

	-- the player's look options (size, opacity, timer below, font, corner symbol), see _poll_options
	self._o = { scale = 1, opacity = 1, timer_below = false, font = DEFAULT_FONT, hide_icon = false }
	self._layout_opts = { timer_below = false, hide_icon = false, glyph = Spread.GLYPH_BY_FONT[DEFAULT_FONT] }
	self._tmp = { 0, 0, 0 }
	self._time_y = 0
	self._save_x, self._save_y, self._save_a = {}, {}, {}

	self._seq, self._count, self._win, self._stage, self._hi = nil, 0, 1, nil, 0
	self._clock, self._seconds, self._paused, self._label = 0, nil, nil, nil
	self._fuse_w, self._fuse_urgent = nil, nil

	self:_init_header()
	set_all_hidden(self)
	self:_poll_options()
end

-- ----------------------------------------------------------------------------------------- visibility
HudElementGrandfathersTarotPanel._hide = function (self)
	if self._visible then
		set_all_hidden(self)
	end

	self._visible = false
	self._shown = nil
	self._sig = nil
	self._seq, self._stage, self._count, self._hi = nil, nil, 0, 0
	self._seconds, self._paused, self._label = nil, nil, nil
end

local function customizing()
	local custom_hud = get_mod("custom_hud")

	return custom_hud ~= nil and custom_hud.is_customizing == true
end

-- ----------------------------------------------------------------------------------- legacy text panel
local function set_line(widget, index, text, colour)
	local style = widget.style["line_" .. index]

	widget.content["line_" .. index] = text

	local target = style.text_color

	target[1], target[2], target[3], target[4] = colour[1], colour[2], colour[3], colour[4]
end

HudElementGrandfathersTarotPanel._refresh_legacy = function (self, view, is_sample)
	local seconds = math.ceil(view.remaining)
	local votes_total = 0
	local cands = view.cands or {}

	for i = 1, #cands do
		votes_total = votes_total + (cands[i].votes or 0)
	end

	-- compared field by field: building a signature string here cost one allocation per frame
	local sig = self._sig

	if sig
		and sig.phase == view.phase
		and sig.mode == view.mode
		and sig.seconds == seconds
		and sig.version == view.version
		and sig.my_vote == view.my_vote
		and sig.votes_total == votes_total
		and sig.is_sample == is_sample
		and sig.paused == (view.paused == true)
	then
		return
	end

	sig = sig or {}
	sig.phase, sig.mode, sig.seconds, sig.version = view.phase, view.mode, seconds, view.version
	sig.my_vote, sig.votes_total, sig.is_sample = view.my_vote, votes_total, is_sample
	sig.paused = view.paused == true
	self._sig = sig

	local widget = self._widgets_by_name.legacy

	if not widget then
		return
	end

	for i = 0, Definitions.LINES - 1 do
		widget.content["line_" .. i] = ""
	end

	local is_vote = view.mode == "vote"
	local line = 0
	local time = time_text(view.remaining)

	if view.phase == "incoming" then
		set_line(widget, 0, mod:localize("hud_incoming", view.chosen), COLOUR_URGENT)

		return
	end

	if view.empty then
		set_line(widget, 0, mod:localize("hud_empty"), COLOUR_HEADER)

		return
	end

	if view.phase == "voting" then
		set_line(widget, 0, mod:localize("hud_vote_now", time, ""), COLOUR_URGENT)
	elseif is_vote then
		set_line(widget, 0, mod:localize("hud_wave_in_vote", time, hint_text(#cands)), COLOUR_HEADER)
	else
		set_line(widget, 0, mod:localize("hud_wave_in", time), COLOUR_HEADER)
	end

	if view.paused then
		widget.content.line_0 = widget.content.line_0 .. " " .. mod:localize("hud_paused")
	end

	for i = 1, math.min(#cands, Definitions.LINES - 2) do
		local cand = cands[i]
		local colour = view.my_vote == i and COLOUR_MINE or COLOUR_LINE

		local with_pct = mod:get("hud_show_percent") == true

		if is_vote then
			if with_pct then
				set_line(widget, i, mod:localize("hud_line_votes", key_label(i), cand.name, pct_text(cand.pct), cand.votes or 0), colour)
			else
				set_line(widget, i, mod:localize("hud_line_votes_plain", key_label(i), cand.name, cand.votes or 0), colour)
			end
		elseif with_pct then
			set_line(widget, i, mod:localize("hud_line", ">", cand.name, pct_text(cand.pct)), colour)
		else
			set_line(widget, i, mod:localize("hud_line_plain", ">", cand.name), colour)
		end

		line = i
	end

	if is_vote and line > 0 then
		set_line(widget, line + 1, hint_text(line), COLOUR_HINT)
	end
end

-- ----------------------------------------------------------------------------------- the Spread: helpers
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

local function box(style, x, y, w, h)
	local offset, size = style.offset, style.size

	offset[1], offset[2], size[1], size[2] = x, y, w, h
end

-- text styles keep their colour in text_color, the shapes in color
local function paint(style, alpha, rgb)
	Spread.set_color(style.text_color or style.color, alpha, rgb)
end

HudElementGrandfathersTarotPanel._read_timing = function (self)
	local T = self._T

	T.roulette = option(TIMING.roulette)
	T.winner = option(TIMING.winner)
	T.eye = option(TIMING.eye)
	T.eye_size = option(TIMING.eye_size)
	T.rot_short = option(TIMING.rot_short)
	T.rot_long = option(TIMING.rot_long)
	T.longest = option(TIMING.longest)
end

-- The look options: size and opacity of the whole HUD (applied when drawing), the timer above or below, the font, the
-- corner symbol. Read every frame (a few table lookups); a change of the ones that move things lays the hand out again.
HudElementGrandfathersTarotPanel._apply_font = function (self)
	local font = self._o.font

	for name, widget in pairs(self._widgets_by_name) do
		if name ~= "legacy" then
			for _, style in pairs(widget.style) do
				if style.display then
					style.font_type = font
				end
			end
		end
	end
end

HudElementGrandfathersTarotPanel._poll_options = function (self)
	local o = self._o
	local scale = Spread.clamp(option(TIMING.scale), 50, 200) / 100
	local opacity = Spread.clamp(option(TIMING.opacity), 10, 100) / 100
	local below = mod:get("tarot_timer_below") == true
	local hide_icon = mod:get("tarot_hide_icon") == true
	local font = mod:get("tarot_font")

	if not FONTS[font] then
		font = DEFAULT_FONT
	end

	-- the node is the box custom_hud shows: it follows the size option (only when that changes, never per frame)
	if scale ~= o.scale and self._set_scenegraph_size then
		self:_set_scenegraph_size("panel", Spread.NODE_WIDTH * scale, Spread.NODE_HEIGHT * scale)
	end

	o.scale, o.opacity = scale, opacity

	if below == o.timer_below and hide_icon == o.hide_icon and font == o.font then
		return
	end

	local font_changed = font ~= o.font

	o.timer_below, o.hide_icon, o.font = below, hide_icon, font
	self._layout_opts.timer_below, self._layout_opts.hide_icon = below, hide_icon
	self._layout_opts.glyph = Spread.GLYPH_BY_FONT[font]

	if font_changed then
		self:_apply_font()
	end

	-- the hand (if there is one) is laid out and set up again on the next frame
	self._seq, self._stage, self._seconds = nil, nil, nil
end

-- ---------------------------------------------------------------------------------------- the header
HudElementGrandfathersTarotPanel._init_header = function (self)
	local widget = self._widgets_by_name.header
	local style = widget.style
	local half = Spread.NODE_WIDTH / 2

	box(style.label, 0, 0, half - 6, Spread.TIME_HEIGHT)
	box(style.time, half + 6, 0, half - 6, Spread.TIME_HEIGHT)
	box(style.status, 0, 0, Spread.NODE_WIDTH, Spread.TIME_HEIGHT)

	style.label.offset[3], style.time.offset[3], style.status.offset[3] = Z.header, Z.header, Z.header
end

-- the countdown's height: above the cards (0) or, with the timer-below option and a hand on the table, under the fuse
HudElementGrandfathersTarotPanel._place_time = function (self, y)
	if self._time_y == y then
		return
	end

	local style = self._widgets_by_name.header.style

	self._time_y = y
	style.label.offset[2], style.time.offset[2], style.status.offset[2] = y, y, y
end

-- the fuse sits under the cards; its width is written every frame while a hand is burning
HudElementGrandfathersTarotPanel._place_fuse = function (self)
	local layout = self._layout
	local style = self._widgets_by_name.header.style

	box(style.fuse_track, layout.x0, layout.fuse_y, layout.total_w, Spread.FUSE_HEIGHT)
	box(style.fuse_fill, layout.x0, layout.fuse_y, layout.total_w, Spread.FUSE_HEIGHT)
	self._fuse_w, self._fuse_urgent = nil, nil
end

-- ------------------------------------------------------------------------------------------ a card
-- Positions the card's background layer (and the bottom row of threat diamonds and dots). `scale` grows the card layer
-- around its top middle (1.06 on the winner); the contents keep their size.
HudElementGrandfathersTarotPanel._apply_body = function (self, index, scale)
	local rec = self._cards[index]
	local style = self._widgets_by_name[CARD[index]].style
	local w, h = rec.cw * scale, rec.ch * scale
	local x, y = rec.x - (w - rec.cw) / 2, rec.y

	box(style.bg, x, y, w, h)
	box(style.accent, x, y, Spread.ACCENT_WIDTH, h)
	box(style.glow, x - GLOW_EDGE, y - GLOW_EDGE, w + 2 * GLOW_EDGE, h + 2 * GLOW_EDGE)
	-- the outline of a rare card is one unit thick, the frame of a Heresy card two
	local line = rec.special and 2 or 1

	box(style.rare_t, x, y, w, line)
	box(style.rare_b, x, y + h - line, w, line)
	box(style.rare_l, x, y, line, h)
	box(style.rare_r, x + w - line, y, line, h)

	-- the bottom row: the threat diamonds from the left, the enemy dots to the right of them
	local cy = rec.y + rec.ch - Spread.PAD_Y - Spread.ROW_HEIGHT / 2
	local side = Spread.THREAT_SIDE
	local halo = side + 1.4

	for j = 1, #TH_O do
		local cx = rec.x + Spread.ACCENT_WIDTH + Spread.PAD_X + side / 2 + (j - 1) * Spread.THREAT_PITCH
		local s_halo, s_outer = style[TH_H[j]], style[TH_O[j]]

		s_halo.offset[1], s_halo.offset[2] = cx - halo / 2, cy - halo / 2
		s_outer.offset[1], s_outer.offset[2] = cx - side / 2, cy - side / 2
	end

	local d = rec.dot_d

	for j = 1, rec.dots do
		local dx = rec.x + rec.cw - Spread.PAD_X - d - (rec.dots - j) * rec.dot_pitch

		box(style[DOT[j]], dx, cy - d / 2, d, d)
		box(style[DOT_H[j]], dx - 0.6, cy - d / 2 - 0.6, d + 1.2, d + 1.2)
	end
end

-- Colours of everything that depends on the card's state: mode 0 = resting, 1 = highlighted by the roulette,
-- 2 = the winner. The inside of the suit marks, the eye and the empty diamonds take the card's own background colour.
HudElementGrandfathersTarotPanel._apply_colors = function (self, index)
	local rec = self._cards[index]
	local style = self._widgets_by_name[CARD[index]].style
	local suit = rec.suit

	if not suit then
		return
	end

	local Cards = cards_module()
	local t = rec.desat

	-- every colour of the card goes through Spread.grey with the card's desaturation (0 for a card in the hand)
	local bg = Spread.grey(rec.p_bg, rec.mode > 0 and suit.hi or suit.card, t)
	local accent = Spread.grey(rec.p_accent, suit.accent, t)

	rec.bg, rec.accent = bg, accent

	paint(style.bg, 255, bg)
	paint(style.accent, 255, accent)
	if rec.special then
		-- a card apart: its blood-red glow smoulders at rest and flares when the card is highlighted or drawn
		paint(style.glow, rec.mode == 2 and 220 or rec.mode == 1 and 170 or 110, Spread.grey(rec.tmp, suit.frame, t))
		style.glow.visible = true
	else
		paint(style.glow, rec.mode == 2 and 200 or 150, accent)
		style.glow.visible = rec.mode > 0
	end

	for j = 1, #RARE do
		paint(style[RARE[j]], 255, Spread.grey(rec.tmp, rec.special and suit.frame or Cards.BASE.pus, t))
		style[RARE[j]].visible = rec.rare or rec.special
	end

	paint(style.name, 255, Spread.grey(rec.p_text, suit.text, t))

	local feather = Spread.alpha(Spread.FEATHER_ALPHA)

	for j = 1, Spread.ICON_TRIS do
		local rgb = rec.tri_col[j] == 2 and bg or accent

		paint(style[ICON_T[j]], 255, rgb)
		paint(style[ICON_TH[j]], feather, rgb)
	end

	for j = 1, Spread.ICON_CIRCS do
		local rgb = rec.circ_col[j] == 2 and bg or accent

		paint(style[ICON_C[j]], 255, rgb)
		paint(style[ICON_CH[j]], feather, rgb)
	end

	-- threat: filled diamonds in the colour of the level, the rest the same diamonds dimmed (never an outline: a thin
	-- outline drawn from two rotated squares comes out uneven, with gaps)
	local threat_rgb = Cards.threat_color(rec.threat, rec.suit)

	for j = 1, #TH_O do
		local filled = j <= rec.threat
		local rgb = Spread.grey(rec.tmp, filled and threat_rgb or Cards.BASE.muted, t)

		local halo_rgb = rec.threat == 6 and Cards.threat_edge(rec.suit) or rgb
		paint(style[TH_H[j]], rec.threat == 6 and 220 or (filled and 70 or 22), halo_rgb)
		paint(style[TH_O[j]], filled and 255 or 64, rgb)
		local visible = j <= 5 or rec.threat == 6
		style[TH_H[j]].visible, style[TH_O[j]].visible = visible, visible
	end

	for j = 1, rec.dots do
		local rgb = Spread.grey(rec.tmp, rec.dot_rgb[j], t)

		paint(style[DOT[j]], 255, rgb)
		paint(style[DOT_H[j]], 70, rgb)
	end

	self:_apply_eye(index, rec.eye_open)
end

-- The eye: shut on every card in the hand (a smile with three lashes), opens on the winner (a lens with a pupil). Faint
-- (16 percent) while the card is in the hand, 50 once it is chosen.
HudElementGrandfathersTarotPanel._apply_eye = function (self, index, open)
	local rec = self._cards[index]
	local style = self._widgets_by_name[CARD[index]].style
	local suit = rec.suit

	if not suit then
		return
	end

	rec.eye_open = open

	local size = self._T.eye_size
	local shape = self._shape_eye
	local open_alpha, closed_alpha, pupil_alpha = Spread.eye(size, open, shape)
	local ox, oy = rec.x + rec.cw / 2 - size / 2, rec.y + rec.ch * 0.56 - size / 2
	local base = rec.mode == 2 and 0.5 or 0.16
	local z = Z.card + 7

	for j = 1, Spread.EYE_TRIS do
		local slot = shape.tri[j]
		local s = style[EYE_T[j]]

		place_tri(s, slot, ox, oy, z)

		if slot.on then
			if slot.col == 2 then
				paint(s, Spread.alpha(open_alpha * 2), rec.bg)
			else
				paint(s, Spread.alpha(base * (j <= 2 and open_alpha or closed_alpha)), rec.accent)
			end
		end
	end

	local c = shape.circ[1]
	local pupil_style = style.eye_c1

	place_circ(pupil_style, c, ox, oy, z)

	if c.on then
		paint(pupil_style, Spread.alpha(base * pupil_alpha), rec.accent)
	end
end

-- Places a card of the hand in the Spread: text, geometry and colours (state: resting, eye shut).
HudElementGrandfathersTarotPanel._setup_card = function (self, index, card)
	local Cards = cards_module()
	local layout = self._layout
	local rec = self._cards[index]
	local widget = self._widgets_by_name[CARD[index]]
	local style = widget.style
	local suit = Cards.suit(card.suit)

	rec.suit = suit
	rec.mode, rec.eye_open = 0, 0
	rec.threat = math.max(1, math.min(6, card.threat or 1))
	rec.name = card.name
	rec.rare = card.rare == true
	rec.special = suit.special == true
	rec.x, rec.y, rec.cw, rec.ch = layout.x[index], layout.cards_y, layout.cw, layout.ch
	rec.desat = 0

	-- dots: one per distinct enemy colour (the player's own colour settings), a neutral one when colouring is off;
	-- as many and as big as the room beside the diamonds allows
	local colors = mod.rw and mod.rw.colors
	local dots = Cards.dots_from_breeds(card.breeds, function (breed)
		return colors and colors.rgb(breed) or Cards.BASE.muted
	end)

	rec.dot_d, rec.dot_pitch, rec.dots = Spread.dots_fit(rec.cw, #dots, rec.threat)

	for j = 1, #DOT do
		local dot, halo = style[DOT[j]], style[DOT_H[j]]
		local stored = rec.dot_rgb[j]

		dot.visible, halo.visible = j <= rec.dots, j <= rec.dots

		if dots[j] then
			stored[1], stored[2], stored[3] = dots[j][1], dots[j][2], dots[j][3]
		end
	end

	widget.content.name = card.name
	-- a Murmur card of threat 5 or 6: its name murmurs, written letter by letter, over and over (_tick_living)
	rec.murmur = Murmur.on(card.suit, card.threat) and Murmur.new({ card.name }, card.threat) or nil
	box(style.name, rec.x + Spread.ACCENT_WIDTH + Spread.PAD_X, rec.y + Spread.PAD_Y, layout.name_w, layout.lines * Spread.NAME_LINE)
	style.name.visible = true

	-- the suit mark in the top right corner (an option hides it)
	local shape = self._shape_icon

	Spread.icon(suit.icon, Spread.ICON, shape)

	local ox, oy = rec.x + rec.cw - Spread.PAD_X - Spread.ICON, rec.y + Spread.PAD_Y
	local hide_icon = self._o.hide_icon

	for j = 1, Spread.ICON_TRIS do
		place_tri(style[ICON_T[j]], shape.tri[j], ox, oy, Z.card + 10)
		place_tri_halo(style[ICON_TH[j]], shape.tri[j], ox, oy, Z.card + 10)
		rec.tri_col[j] = shape.tri[j].col

		if hide_icon then
			style[ICON_T[j]].visible, style[ICON_TH[j]].visible = false, false
		end
	end

	for j = 1, Spread.ICON_CIRCS do
		place_circ(style[ICON_C[j]], shape.circ[j], ox, oy, Z.card + 10)
		place_circ_halo(style[ICON_CH[j]], shape.circ[j], ox, oy, Z.card + 10)
		rec.circ_col[j] = shape.circ[j].col

		if hide_icon then
			style[ICON_C[j]].visible, style[ICON_CH[j]].visible = false, false
		end
	end

	style.bg.visible, style.accent.visible = true, true

	widget.visible = true
	widget.alpha_multiplier = 1
	widget.color_intensity_multiplier = 1
	widget.offset[2] = 0

	self:_apply_body(index, 1)
	self:_apply_colors(index)
end

-- 0 resting, 1 highlighted (raised, glowing), 2 the winner
HudElementGrandfathersTarotPanel._set_mode = function (self, index, mode)
	local rec = self._cards[index]

	if rec.mode == mode or index > self._count then
		return
	end

	rec.mode = mode

	self._widgets_by_name[CARD[index]].offset[2] = mode == 1 and -5 or 0
	self:_apply_colors(index)
end

-- ----------------------------------------------------------------------------------------- the hand
-- A new hand: lay it out and set every card up. Called when the hand number changes.
HudElementGrandfathersTarotPanel._setup_hand = function (self, view)
	local Cards = cards_module()
	local hand = view.hand
	local T = self._T

	self:_read_timing()
	Spread.layout(self._layout, hand, self._layout_opts)

	local count = self._layout.count

	self._count, self._seq = count, view.hand_seq
	self._win = math.max(1, math.min(count, view.win or 1))
	self._hi = 0

	for i = 1, Spread.MAX_CARDS do
		if i <= count then
			self:_setup_card(i, hand[i])
		else
			self._widgets_by_name[CARD[i]].visible = false
		end
	end

	-- how hard and how long the winner will rot: from its cooldown and the player's timeline options
	local longest = math.max(2, T.longest) * 60
	local cooldown = hand[self._win].cooldown or Cards.DEFAULT_COOLDOWN

	T.k = Cards.rot_strength(cooldown, longest)
	T.rot = Cards.rot_duration(cooldown, longest, T.rot_short, T.rot_long)

	self:_place_fuse()
	self._stage = nil
end

HudElementGrandfathersTarotPanel._clear_hand = function (self)
	for i = 1, Spread.MAX_CARDS do
		self._widgets_by_name[CARD[i]].visible = false
	end

	self._widgets_by_name.fx.visible = false
	self._widgets_by_name.banner.visible = false
	self._seq, self._count, self._stage, self._hi = nil, 0, nil, 0
end

-- The text of the banner under the Spread ("THE CARD IS DRAWN", the name, the whisper, the modifiers).
HudElementGrandfathersTarotPanel._setup_banner = function (self, card)
	local Cards = cards_module()
	local widget = self._widgets_by_name.banner
	local style = widget.style
	local suit = Cards.suit(card.suit)
	local y = self._layout.banner_y
	local width = Spread.NODE_WIDTH

	widget.content.kicker = string.upper(mod:localize(suit.beneficial and "hud_card_drawn_beneficial" or (suit.special and "hud_card_drawn_special" or "hud_card_drawn")))
	widget.content.name = card.name
	widget.content.whisper = "\"" .. tostring(card.whisper or "") .. "\""
	-- threat 5 and 6: the whisper murmurs, it comes back letter by letter once the card is shown (see _tick_banner)
	self._banner_text = tostring(card.whisper or "")
	self._banner_murmur = Cards.murmurs(card.threat)
	self._banner_letters = nil
	widget.content.mods = ""

	box(style.kicker, 0, y, width, 18)
	box(style.name, 0, y + 18, width, 40)
	box(style.whisper, 0, y + 58, width, 22)
	box(style.mods, 0, y + 82, width, 18)

	paint(style.kicker, 255, suit.special and (suit.lit or suit.accent) or Cards.BASE.whisper)
	paint(style.name, 255, suit.accent)
	paint(style.whisper, 255, Cards.BASE.whisper)
	paint(style.mods, 255, Cards.BASE.rust)

	style.kicker.visible, style.name.visible, style.whisper.visible = true, true, true
	style.mods.visible = widget.content.mods ~= ""
end

-- ------------------------------------------------------------------------------------------ stages
-- Puts everything in the state a stage needs, whatever came before (a late joiner may enter at any stage).
HudElementGrandfathersTarotPanel._enter_stage = function (self, stage, view)
	local by_name = self._widgets_by_name
	local count = self._count

	self._stage = stage

	if stage == "waiting" then
		for i = 1, Spread.MAX_CARDS do
			by_name[CARD[i]].visible = false
		end

		by_name.fx.visible = false
		by_name.banner.visible = false
		self._hi = 0

		return
	end

	for i = 1, count do
		local widget = by_name[CARD[i]]

		widget.visible = true

		if stage == "hand" or stage == "roulette" then
			widget.alpha_multiplier, widget.color_intensity_multiplier = 1, 1
			self._cards[i].eye_open = 0
			self:_set_mode(i, 0)
			self:_apply_body(i, 1)
			self:_apply_eye(i, 0)
		else
			self:_set_mode(i, i == self._win and 2 or 0)
		end
	end

	if stage == "hand" or stage == "roulette" then
		by_name.banner.visible = false
		by_name.fx.visible = false
	else
		-- reveal and rot: the banner is set up for both (it fades out in the first moments of the rot)
		self:_setup_banner(view.hand[self._win])
		by_name.fx.visible = stage == "rot"
	end
end

-- the highlight of the roulette moves to the card `hi` (1-based, 0 = none)
HudElementGrandfathersTarotPanel._tick_roulette = function (self, hi)
	if hi == self._hi then
		return
	end

	if self._hi > 0 then
		self:_set_mode(self._hi, 0)
	end

	self._hi = hi

	if hi > 0 then
		self:_set_mode(hi, 1)
	end
end

-- the banner under the Spread fades in with the reveal and out again 0.3 s after the winner has been shown
HudElementGrandfathersTarotPanel._tick_banner = function (self, tl)
	local banner = self._widgets_by_name.banner
	local rise = Spread.clamp(tl.reveal_t / 0.3, 0, 1)
	local out = 1 - Spread.clamp((tl.reveal_t - self._T.winner) / 0.3, 0, 1)
	local alpha = math.min(rise, out)

	banner.visible = alpha > 0.01
	banner.alpha_multiplier = alpha
	banner.offset[2] = -8 * (1 - rise)

	if self._banner_murmur then
		local Cards = cards_module()
		local text = self._banner_text
		local letters = Cards.whisper_letters(text, Spread.clamp(tl.reveal_t / MURMUR_SECONDS, 0, 1))

		-- the text is rebuilt only when another letter has appeared (a string a frame would be garbage)
		if letters ~= self._banner_letters then
			self._banner_letters = letters
			banner.content.whisper = "\"" .. Cards.utf8_cut(text, letters) .. (letters >= #text and "\"" or "")
		end
	end
end

-- a = a + (b - a) * k for {r, g, b}, written into out
local function mix_into(out, a, b, k)
	out[1], out[2], out[3] = a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k

	return out
end

-- Every frame, for every card that is shown: what lives on it. A Heresy card's glow and frame beat like a heart and blood runs
-- down from it; the sixth diamond of a threat 6 card shines (Despair breathes darkly, Apotheosis glitters in light).
HudElementGrandfathersTarotPanel._tick_living = function (self)
	if not self._stage or self._stage == "waiting" then
		return
	end

	local Cards = cards_module()
	local by_name = self._widgets_by_name
	local clock = self._clock

	for i = 1, self._count do
		local rec = self._cards[i]
		local suit = rec.suit
		local style = by_name[CARD[i]].style

		if suit and suit.blood then
			local beat = Cards.heartbeat(clock + i * 0.13)
			local base = rec.mode == 2 and 220 or rec.mode == 1 and 170 or 110

			paint(style.glow, math.floor(base * (0.55 + 0.45 * beat) + 0.5), Spread.grey(rec.tmp, mix_into(rec.mix, suit.frame, suit.lit, 0.6 * beat), rec.desat))

			for j = 1, #RARE do
				paint(style[RARE[j]], 255, Spread.grey(rec.tmp, mix_into(rec.mix, suit.frame, suit.lit, 0.5 * beat), rec.desat))
			end

			for k = 1, #BLOOD do
				local phase = (clock * 0.45 + k * 0.37) % 1
				local length = 3 + 14 * phase
				local x = rec.x + rec.cw * (0.22 + 0.28 * (k - 1))
				local y = rec.y + rec.ch - 1
				local alpha = math.floor(255 * (1 - phase) + 0.5)

				box(style[BLOOD[k]], x, y, 2, length)
				box(style[BLOOD_C[k]], x - 1.5, y + length - 2.5, 5, 5)
				paint(style[BLOOD[k]], alpha, Spread.grey(rec.tmp, suit.blood, rec.desat))
				paint(style[BLOOD_C[k]], alpha, Spread.grey(rec.tmp, suit.frame, rec.desat))
				style[BLOOD[k]].visible, style[BLOOD_C[k]].visible = true, true
			end
		elseif suit and suit.gloom then
			-- NIGHTMARE: darkness breathes around the card, its frame is a light that dies and flickers back, black ink drips from it
			local breath, flash = Cards.dread(clock + i * 0.37)
			local base = rec.mode == 2 and 245 or rec.mode == 1 and 215 or 175
			local edge = mix_into(rec.mix, suit.gloom, suit.frame, breath)

			paint(style.glow, math.floor(base * (0.6 + 0.4 * breath) + 0.5), Spread.grey(rec.tmp, mix_into(rec.mix2, suit.gloom, suit.lit, 0.8 * flash), rec.desat))
			style.glow.visible = true

			for j = 1, #RARE do
				paint(style[RARE[j]], 255, Spread.grey(rec.tmp, mix_into(rec.mix2, edge, suit.lit, 0.9 * flash), rec.desat))
			end

			for k = 1, #BLOOD do
				local phase = (clock * 0.22 + k * 0.29) % 1
				local length = 5 + 24 * phase
				local x = rec.x + rec.cw * (0.18 + 0.32 * (k - 1))
				local y = rec.y + rec.ch - 1
				local alpha = math.floor(255 * (1 - phase * phase) + 0.5)

				box(style[BLOOD[k]], x, y, 2, length)
				box(style[BLOOD_C[k]], x - 2, y + length - 3, 6, 6)
				paint(style[BLOOD[k]], alpha, suit.ink)
				paint(style[BLOOD_C[k]], alpha, Spread.grey(rec.tmp, suit.gloom, rec.desat))
				style[BLOOD[k]].visible, style[BLOOD_C[k]].visible = true, true
			end
		elseif suit and suit.motes then
			-- WARP: the glow pulses unevenly and crackles, motes of the warp rise from the card's top edge
			local pulse, crackle = Cards.warp_pulse(clock + i * 0.23)
			local base = rec.mode == 2 and 230 or rec.mode == 1 and 190 or 130

			paint(style.glow, math.floor(base * (0.45 + 0.55 * pulse) + 0.5), Spread.grey(rec.tmp, mix_into(rec.mix, suit.frame, suit.lit, 0.35 * pulse + 0.65 * crackle), rec.desat))
			style.glow.visible = true

			for k = 1, #BLOOD do
				local phase = (clock * 0.6 + k * 0.33) % 1
				local d = 3 + 2 * (1 - phase)
				local x = rec.x + rec.cw * (0.2 + 0.3 * (k - 1)) + 4 * math.sin(clock * 3 + k)
				local y = rec.y + 1 - 18 * phase

				style[BLOOD[k]].visible = false
				box(style[BLOOD_C[k]], x - d / 2, y - d / 2, d, d)
				paint(style[BLOOD_C[k]], math.floor(230 * (1 - phase) + 0.5), Spread.grey(rec.tmp, mix_into(rec.mix2, suit.accent, suit.lit, crackle), rec.desat))
				style[BLOOD_C[k]].visible = true
			end
		else
			for k = 1, #BLOOD do
				style[BLOOD[k]].visible, style[BLOOD_C[k]].visible = false, false
			end

			-- Dream's glow turns through a rainbow and Brute's flares with every blow (ui/aura.lua); Dream's frame follows its glow
			local glow = suit and Aura.glow(suit.id, clock + i * 0.31, rec.mix, rec.threat)

			if glow then
				local base = rec.mode == 2 and 235 or rec.mode == 1 and 200 or 150

				paint(style.glow, math.floor(base * glow + 0.5), Spread.grey(rec.tmp, rec.mix, rec.desat))
				style.glow.visible = true
			end

			if suit and suit.rainbow then
				Spread.grey(rec.tmp, Aura.rainbow(clock + i * 0.31, rec.mix2, 0.12), rec.desat)

				for j = 1, #RARE do
					paint(style[RARE[j]], 255, rec.tmp)
				end
			end
		end

		-- the suit's aura on the card's face, as strong as its threat (Nightmare and Warp have their own life above, Heresy its blood and,
		-- at threat 5 and 6, a storm); the option "Card effects on the HUD" turns it off
		local effects_on = mod:get("card_auras") ~= false
		local aura_on = suit ~= nil and not suit.motes and effects_on and Aura.has(suit.id, rec.threat)

		rec.aura = rec.aura or Aura.new()
		rec.aura_paint = rec.aura_paint or function (s, alpha, rgb)
			paint(s, alpha, Spread.grey(rec.tmp, rgb, rec.desat))
		end

		if aura_on then
			aura_on = Aura.update(rec.aura, suit.id, clock + i * 0.43, rec.cw, rec.ch, AURA_SIZE, rec.threat)
		end

		Aura.draw(rec.aura, style, AURA_C, AURA_R, AURA_T, rec.x, rec.y, aura_on, 1, rec.aura_paint)

		-- a Murmur card of threat 5 or 6: its name is written, held and wiped, over and over
		if rec.murmur and effects_on and Murmur.tick(rec.murmur, clock + i * 0.9) then
			by_name[CARD[i]].content.name = rec.murmur.shown[1]
		end

		-- Nightmare's black fog comes and goes over the whole card
		if suit and suit.fog then
			rec.fog = rec.fog or Spread.new_fog()

			local veil = Spread.fog(Cards, clock + i * 0.5, rec.ch, rec.fog, mod:get("nightmare_fog_strength"))

			box(style.fog_veil, rec.x, rec.y, rec.cw, rec.ch)
			paint(style.fog_veil, veil, BLACK)
			style.fog_veil.visible = veil > 0

			for k = 1, #FOG do
				local bank = rec.fog[k]

				box(style[FOG[k]], rec.x, rec.y + bank[1], rec.cw, bank[2])
				paint(style[FOG[k]], bank[3], BLACK)
				style[FOG[k]].visible = bank[2] > 0 and bank[3] > 0
			end
		else
			style.fog_veil.visible = false

			for k = 1, #FOG do
				style[FOG[k]].visible = false
			end
		end

		if rec.threat == 6 and suit then
			local shine = Cards.six_shine(clock + i * 0.21, suit)
			local side = Spread.THREAT_SIDE
			local halo = side + 1.4 + 2.6 * shine
			local cy = rec.y + rec.ch - Spread.PAD_Y - Spread.ROW_HEIGHT / 2
			local fill = Cards.threat_color(6, suit)

			for j = 1, #TH_O do
				local cx = rec.x + Spread.ACCENT_WIDTH + Spread.PAD_X + side / 2 + (j - 1) * Spread.THREAT_PITCH
				local s_halo, s_outer = style[TH_H[j]], style[TH_O[j]]

				s_halo.size[1], s_halo.size[2], s_halo.pivot[1], s_halo.pivot[2] = halo, halo, halo / 2, halo / 2
				s_halo.offset[1], s_halo.offset[2] = cx - halo / 2, cy - halo / 2

				if suit.beneficial then
					paint(s_halo, math.floor(160 + 95 * shine), Spread.grey(rec.tmp, mix_into(rec.mix, suit.accent, Cards.APOTHEOSIS_EDGE, shine), rec.desat))
					paint(s_outer, 255, Spread.grey(rec.tmp, mix_into(rec.mix2, fill, WARM_WHITE, 0.45 * shine), rec.desat))
				else
					paint(s_halo, math.floor(140 + 115 * shine), Spread.grey(rec.tmp, mix_into(rec.mix, DESPAIR_DEEP, Cards.DESPAIR_EDGE, shine), rec.desat))
					paint(s_outer, 255, Spread.grey(rec.tmp, mix_into(rec.mix2, fill, DESPAIR_DEEP, 0.6 * shine), rec.desat))
				end
			end
		end
	end
end

-- The chosen card loses its colour from the moment it is shown until it is completely grey (tl.desat 0..1). Its colours
-- are rewritten only when the amount has moved.
HudElementGrandfathersTarotPanel._tick_desat = function (self, tl)
	local rec = self._cards[self._win]

	if math.abs(rec.desat - tl.desat) > 0.003 or (tl.desat >= 1 and rec.desat ~= 1) then
		rec.desat = tl.desat
		self:_apply_colors(self._win)
	end
end

-- Every frame of the reveal: the winner rises, grows and opens its eye, the others fall away.
HudElementGrandfathersTarotPanel._tick_reveal = function (self, tl)
	local by_name = self._widgets_by_name
	local pop = 1 - (1 - tl.pop) * (1 - tl.pop) -- ease out
	local fall = math.min(6, 6 * (1 - tl.lose) / 0.72)

	self:_tick_desat(tl)

	for i = 1, self._count do
		local widget = by_name[CARD[i]]

		if i == self._win then
			widget.offset[2] = -6 * pop
			self:_apply_body(i, 1 + 0.06 * pop)

			if self._cards[i].eye_open < 1 or tl.eye < 1 then
				self:_apply_eye(i, tl.eye)
			end
		else
			widget.alpha_multiplier = tl.lose
			widget.offset[2] = fall
		end
	end

	self:_tick_banner(tl)
end

-- Every frame of the rot: the winner browns, darkens and fades, soft blotches grow over it, flies circle it, drips fall.
HudElementGrandfathersTarotPanel._tick_rot = function (self, tl)
	local by_name = self._widgets_by_name
	local rec = self._cards[self._win]
	local fx = Spread.rot_fx(self._rot, tl.rot_p, self._T.k, rec.cw, rec.ch, self._clock)
	local widget = by_name[CARD[self._win]]
	local scale = 1.06

	self:_tick_desat(tl)

	for i = 1, self._count do
		if i ~= self._win then
			by_name[CARD[i]].alpha_multiplier = tl.lose
		end
	end

	widget.alpha_multiplier = fx.fade
	widget.color_intensity_multiplier = fx.bright
	widget.offset[2] = -6

	if rec.eye_open < 1 then
		self:_apply_eye(self._win, 1)
	end

	self:_apply_body(self._win, scale)
	self:_tick_banner(tl)

	-- the effects are drawn in node coordinates over the card (the card layer is 6 percent wider, raised by 6)
	local style = by_name.fx.style
	local w, h = rec.cw * scale, rec.ch * scale
	local ox, oy = rec.x - (w - rec.cw) / 2, rec.y - 6

	by_name.fx.alpha_multiplier = fx.fade

	box(style.wash, ox, oy, w, h)
	paint(style.wash, Spread.alpha(fx.wash), Spread.grey(self._tmp, WASH_COLOR, tl.desat))
	style.wash.visible = fx.wash > 0.01

	for i = 1, Spread.BLOTCHES do
		local blotch = fx.blotch[i]

		for ring = 1, #Spread.BLOTCH_RINGS do
			local spec = Spread.BLOTCH_RINGS[ring]
			local s = style[BLOT[i][ring]]

			s.visible = blotch.on

			if blotch.on then
				local r = blotch.r * spec[1]

				box(s, ox + blotch.cx - r, oy + blotch.cy - r, r * 2, r * 2)
				paint(s, Spread.alpha(spec[2]), Spread.grey(self._tmp, Spread.BLOTCH_COLORS[i], tl.desat))
			end
		end
	end

	for i = 1, Spread.DRIPS do
		local drip = fx.drips[i]
		local s = style[DRIP[i]]

		s.visible = drip.on

		if drip.on then
			box(s, ox + drip.x, oy + drip.y, 3, drip.h)
			paint(s, Spread.alpha(drip.alpha), DRIP_COLOR)
		end
	end

	for i = 1, Spread.MAX_FLIES do
		local fly = fx.flies[i]
		local ring, core = style[FLY_R[i]], style[FLY_C[i]]

		ring.visible, core.visible = fly.on, fly.on

		if fly.on then
			box(ring, ox + fly.x - 3.5, oy + fly.y - 3.5, 7, 7)
			box(core, ox + fly.x - 2.5, oy + fly.y - 2.5, 5, 5)
			paint(ring, 255, FLY_RING)
			paint(core, 255, FLY_CORE)
		end
	end
end

-- ----------------------------------------------------------------------------------- the time and fuse
-- "Card revealed in m:ss" while a hand is on the table (until the pick); nothing while the card is shown and rotting;
-- "Next card in m:ss" while the mod waits for the next hand.
HudElementGrandfathersTarotPanel._refresh_header = function (self, view, tl)
	local Cards = cards_module()
	local header = self._widgets_by_name.header
	local style = header.style
	local stage = tl.stage

	if stage == "reveal" or stage == "rot" then
		header.visible = false

		return
	end

	header.visible = true

	local burning = stage == "hand" or stage == "roulette"
	local label = burning and "hud_card_in" or "hud_next_card"

	self:_place_time(burning and self._layout.time_y or 0)
	local seconds = math.ceil(math.max(0, view.remaining))
	local paused = view.paused == true

	if view.empty and stage == "waiting" then
		-- nothing can be drawn: say why instead of a countdown
		local key = view.cooling and "hud_all_cooling" or "hud_empty_tarot"

		if self._seconds ~= key then
			self._seconds, self._paused = key, nil
			header.content.status = mod:localize(key)
			paint(style.status, 255, Cards.BASE.muted)
		end

		style.status.visible, style.label.visible, style.time.visible = true, false, false
		style.fuse_track.visible, style.fuse_fill.visible = false, false

		return
	end

	style.status.visible, style.label.visible, style.time.visible = false, true, true

	if self._seconds ~= seconds or self._paused ~= paused or self._label ~= label then
		self._seconds, self._paused, self._label = seconds, paused, label

		local text = time_text(view.remaining)

		header.content.label = mod:localize(label)
		header.content.time = paused and (text .. " " .. mod:localize("hud_paused")) or text
		paint(style.label, 255, Cards.BASE.muted)

		-- the label and the time as ONE line centred on the node (and so on the fuse): the label ends where the time
		-- starts, widths estimated from the letters (the label is much wider than the time)
		local half = Spread.NODE_WIDTH / 2
		local label_w = #header.content.label * style.label.font_size * 0.52
		local time_w = #header.content.time * style.time.font_size * 0.5
		local left = half - (label_w + Spread.TIME_GAP + time_w) / 2

		style.label.offset[1] = left + label_w - (half - 6)
		style.time.offset[1] = left + label_w + Spread.TIME_GAP
	end

	local urgent = tl.urgent

	paint(style.time, 255, urgent and Cards.BASE.rust or Cards.BASE.text)

	if burning then
		local width = self._layout.total_w * tl.fuse

		style.fuse_track.visible, style.fuse_fill.visible = true, width > 0.5
		paint(style.fuse_track, 255, Cards.BASE.line)

		if self._fuse_w ~= width then
			self._fuse_w = width
			style.fuse_fill.size[1] = width
		end

		if self._fuse_urgent ~= urgent then
			self._fuse_urgent = urgent
			paint(style.fuse_fill, 255, urgent and Cards.BASE.rust or Cards.BASE.bile)
		end
	else
		style.fuse_track.visible, style.fuse_fill.visible = false, false
	end
end

-- ----------------------------------------------------------------------------------------- the Spread
HudElementGrandfathersTarotPanel._refresh_tarot = function (self, view, dt)
	local tl = self._timeline
	local has_hand = view.hand ~= nil and #view.hand > 0

	self._clock = self._clock + dt
	self._widgets_by_name.legacy.visible = false

	if has_hand and view.hand_seq ~= self._seq then
		-- a new hand (or one seen for the first time, e.g. after joining): lay it out
		self:_setup_hand(view)
	elseif not has_hand and self._seq ~= nil then
		self:_clear_hand()
	end

	Spread.timeline(view, self._T, tl)

	if tl.stage ~= self._stage then
		self:_enter_stage(tl.stage, view)
	end

	local stage = self._stage

	if stage == "roulette" then
		self:_tick_roulette(tl.hi)
	elseif stage == "reveal" then
		self:_tick_reveal(tl)
	elseif stage == "rot" then
		self:_tick_rot(tl)
	end

	self:_tick_living()
	self:_refresh_header(view, tl)
end

-- ------------------------------------------------------------------------------------------ update
HudElementGrandfathersTarotPanel._refresh = function (self, dt)
	self:_poll_options()

	local rw = mod.rw
	local director = rw and rw.director
	local sample = customizing()

	if not director or not mod:is_enabled() or (mod:get("hud_enabled") == false and not sample) then
		return self:_hide()
	end

	local view = director.view()

	if sample and view.phase == "off" then
		view = (mod:get("mode") == "random" or mod:get("mode") == "vote") and SAMPLE or SAMPLE_TAROT
	end

	if view.phase == "off" then
		return self:_hide()
	end

	self._visible = true

	if view.mode == "tarot" then
		if self._shown ~= "tarot" then
			self._shown = "tarot"
			set_all_hidden(self)
			self._sig, self._seq, self._stage, self._seconds = nil, nil, nil, nil
		end

		self:_refresh_tarot(view, dt)
	else
		-- Random countdown / Votes: the old text panel; the Spread's widgets stay hidden
		if self._shown ~= "legacy" then
			self._shown = "legacy"
			set_all_hidden(self)
			self._sig, self._seq, self._stage, self._count = nil, nil, nil, 0
		end

		self._widgets_by_name.legacy.visible = true
		self:_refresh_legacy(view, view == SAMPLE)
	end
end

-- Size and opacity of the whole HUD: the widgets are drawn with the renderer's scale multiplied by the size option (text,
-- shapes and textures all follow it) and their opacity multiplied by the opacity option. To keep the node's top-left
-- corner where custom_hud put it, every widget is shifted by node * (1/size - 1) for the duration of the draw; all
-- changes are undone afterwards (the widgets and the shared render settings are left as they were).
-- (2026-10-06, a performance pass) the game's _draw_widgets walks every pass of every widget, hidden ones too: the Spread has 768
-- passes (five card slots of 142), of which a hand of three shows about 150. Only the widgets shown are handed to it.
HudElementGrandfathersTarotPanel._draw_widgets = function (self, dt, t, input_service, ui_renderer, render_settings)
	local all, shown = self._widgets, self._shown_widgets or {}
	local n = 0

	self._shown_widgets = shown

	for i = 1, #all do
		if all[i].visible then
		n = n + 1
		shown[n] = all[i]
		end
	end

	for i = #shown, n + 1, -1 do
		shown[i] = nil
	end

	self._widgets = shown

	local ok, err = pcall(HudElementGrandfathersTarotPanel.super._draw_widgets, self, dt, t, input_service, ui_renderer, render_settings)

	self._widgets = all

	if not ok then
		error(err)
	end
end

HudElementGrandfathersTarotPanel.draw = function (self, dt, t, ui_renderer, render_settings, input_service)
	local o = self._o
	local size, opacity = o.scale, o.opacity * (self._boss_fade or 1)
	local push = self._boss_push or 0

	-- (2026-10-06, a performance pass) hidden (every widget hidden by _hide): no render pass at all
	if not self._visible then
		return
	end

	if size == 1 and opacity == 1 and push == 0 then
		return HudElementGrandfathersTarotPanel.super.draw(self, dt, t, ui_renderer, render_settings, input_service)
	end

	local widgets = self._widgets
	local node = self._ui_scenegraph.panel.world_position
	local shift = 1 / size - 1
	-- (the push below the boss bars is in screen units: divided by the size, as the widgets are drawn `size` times bigger)
	local dx, dy = node[1] * shift, node[2] * shift + push / size
	local saved_scale, saved_inverse = render_settings.scale, render_settings.inverse_scale
	local scale = (saved_scale or RESOLUTION_LOOKUP.scale) * size

	for i = 1, #widgets do
		local widget = widgets[i]
		local offset = widget.offset

		self._save_x[i], self._save_y[i], self._save_a[i] = offset[1], offset[2], widget.alpha_multiplier or 1
		offset[1], offset[2] = offset[1] + dx, offset[2] + dy
		widget.alpha_multiplier = (widget.alpha_multiplier or 1) * opacity
	end

	render_settings.scale, render_settings.inverse_scale = scale, 1 / scale

	local ok, err = pcall(HudElementGrandfathersTarotPanel.super.draw, self, dt, t, ui_renderer, render_settings, input_service)

	render_settings.scale, render_settings.inverse_scale = saved_scale, saved_inverse

	for i = 1, #widgets do
		local widget = widgets[i]
		local offset = widget.offset

		offset[1], offset[2], widget.alpha_multiplier = self._save_x[i], self._save_y[i], self._save_a[i]
	end

	if not ok then
		error(err, 0)
	end
end

-- Out of the way of the boss health bars (2026-10-04, the user: "when there are bosses the Draw HUD moves below them, and back up once
-- they are killed"). The game's bars (scripts/ui/hud/elements/boss_health) sit at the top centre: a band BOSS_BAND wide from y
-- BOSS_TOP down to BOSS_BOTTOM, in the same HUD-scaled space as this panel. While the element has an active boss and the panel overlaps
-- that band, the panel is drawn lower by the push (it slides at BOSS_SLIDE units a second, both ways); the node itself (where
-- custom_hud put it) never moves. The option "Move the Draw HUD below boss bars" (hud_avoid_boss_bars) turns it off.
local BOSS_BAND, BOSS_TOP, BOSS_BOTTOM, BOSS_SLIDE = 748, 36, 172, 500
-- (2026-10-04, second round) while a boss is up the Draw HUD is also drawn see-through (option hud_boss_opacity, percent; it fades
-- there and back at BOSS_FADE a second), and the option hud_boss_bars_below swaps the two: the Draw HUD stays at the top and the
-- boss bars are moved below it (their element's own node, put back where it was, custom_hud's place included, when the boss is gone).
local BOSS_FADE, BARS_BELOW_GAP = 2, 30

-- whether a boss is up, and whether the panel is in the bars' band
HudElementGrandfathersTarotPanel._boss_state = function (self)
	local hud = self._parent
	local bosses = hud and hud.element and hud:element("HudElementBossHealth")
	local active = bosses and bosses._active_targets_array
	local up = active ~= nil and #active > 0
	local node = self._ui_scenegraph and self._ui_scenegraph.panel and self._ui_scenegraph.panel.world_position

	if not up or not node then
		return up, false, bosses, node
	end

	local left, right = (1920 - BOSS_BAND) / 2, (1920 + BOSS_BAND) / 2
	local width = Spread.NODE_WIDTH * (self._o.scale or 1)

	return up, not (node[1] >= right or node[1] + width <= left or node[2] >= BOSS_BOTTOM), bosses, node
end

HudElementGrandfathersTarotPanel._boss_push_target = function (self)
	if mod:get("hud_avoid_boss_bars") == false or mod:get("hud_boss_bars_below") == true then
		return 0
	end

	local _, overlap, _, node = self:_boss_state()

	return overlap and BOSS_BOTTOM - node[2] or 0
end

local function slide(value, target, step)
	if value < target then
		return math.min(target, value + step)
	end

	return math.max(target, value - step)
end

-- the boss bars below the Draw HUD (hud_boss_bars_below): their node moves down by `bars_push`, back to its own place at 0
HudElementGrandfathersTarotPanel._move_bars = function (self, bosses, push)
	if not bosses or not bosses.set_scenegraph_position or not bosses.scenegraph_position then
		return
	end

	if not self._bars_home or self._bars_owner ~= bosses then
		if push == 0 then
			return
		end

		local x, y, z = bosses:scenegraph_position("background")

		if type(x) == "table" then
			x, y, z = x[1], x[2], x[3]
		end

		self._bars_home, self._bars_owner = { x or 0, y or BOSS_TOP, z or 0 }, bosses
	end

	local home = self._bars_home

	if push ~= self._bars_written then
		self._bars_written = push
		bosses:set_scenegraph_position("background", home[1], home[2] + push, home[3])
	end

	if push == 0 then
		self._bars_home, self._bars_owner, self._bars_written = nil, nil, nil
	end
end

HudElementGrandfathersTarotPanel._update_boss_push = function (self, dt)
	local ok, up, overlap, bosses, node = pcall(self._boss_state, self)

	if not ok then
		up, overlap, bosses, node = false, false, nil, nil
	end

	local ok2, target = pcall(self._boss_push_target, self)

	self._boss_push = slide(self._boss_push or 0, ok2 and target or 0, BOSS_SLIDE * dt)

	-- see-through while a boss is up
	local opacity = math.max(10, math.min(100, tonumber(mod:get("hud_boss_opacity")) or 65)) / 100

	self._boss_fade = slide(self._boss_fade or 1, up and opacity or 1, BOSS_FADE * dt)

	-- or the bars below the Draw HUD
	local below = mod:get("hud_boss_bars_below") == true and mod:get("hud_avoid_boss_bars") ~= false and overlap and node
	local bars_target = below and math.max(0, node[2] + Spread.NODE_HEIGHT * (self._o.scale or 1) - BARS_BELOW_GAP - BOSS_TOP) or 0

	self._bars_push = slide(self._bars_push or 0, bars_target, BOSS_SLIDE * dt)

	local moved, err = pcall(self._move_bars, self, bosses or self._bars_owner, self._bars_push)

	if not moved and not self._bars_reported then
		self._bars_reported = true
		mod:warning("GrandfathersTarot: the boss bars could not be moved: %s", tostring(err))
	end
end

HudElementGrandfathersTarotPanel.update = function (self, dt, t, ui_renderer, render_settings, input_service)
	HudElementGrandfathersTarotPanel.super.update(self, dt, t, ui_renderer, render_settings, input_service)
	self:_update_boss_push(tonumber(dt) or 0)

	local ok, err = pcall(self._refresh, self, dt)

	if not ok then
		self._sig = nil
		self._seq, self._stage = nil, nil

		if not self._reported then
			self._reported = true

			mod:error("[hud] refresh failed: %s", tostring(err))
		end
	end
end

return HudElementGrandfathersTarotPanel
