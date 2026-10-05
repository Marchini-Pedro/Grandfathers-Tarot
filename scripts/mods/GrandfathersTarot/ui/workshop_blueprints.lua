-- Widget definitions of the Workshop (docs/08-workshop-redesign.md): the enemy row of the Cauldron, the panel and the chips of
-- the shelf, the stage plate, the suit tile and the threat control of the quick face, and the compact stepper. Everything is a
-- rect, a circle, a triangle, a rotated rect or text, like the Deck's tiles. Where things sit comes from ui/workshop.lua.
local mod = get_mod("GrandfathersTarot")

local UIWidget = require("scripts/managers/ui/ui_widget")

local BASE = "GrandfathersTarot/scripts/mods/GrandfathersTarot"
local Components = mod:io_dofile(BASE .. "/ui/wave_editor_components")
local Workshop = mod:io_dofile(BASE .. "/ui/workshop")
local Spread = mod:io_dofile(BASE .. "/ui/spread")

local WB = {}

local put_rgb, put_mix, state_of = Components.put_rgb, Components.put_mix, Components.state_of
local R = Components.rgb
local STATE = Components.STATE

-- constants of the colour functions (a literal table in a change function would be allocated every frame)
local GROUND = { 10, 12, 7 }
local PANEL = { 18, 22, 12 }

local function shape_color()
	return { 255, 255, 255, 255 }
end

local function rect(passes, id, x, y, w, h, z, change, visible)
	passes[#passes + 1] = {
		pass_type = "rect",
		style_id = id,
		style = { offset = { x, y, z }, size = { w, h }, color = shape_color() },
		change_function = change,
		visibility_function = visible,
	}
end

local function text(passes, id, x, y, w, h, z, size, align, valign, change)
	passes[#passes + 1] = {
		pass_type = "text",
		style_id = id,
		value_id = id,
		value = "",
		style = {
			font_type = "proxima_nova_bold",
			font_size = size,
			text_color = shape_color(),
			text_horizontal_alignment = align or "left",
			text_vertical_alignment = valign or "center",
			offset = { x, y, z },
			size = { w, h },
		},
		change_function = change,
	}
end

-- ------------------------------------------------------------------------------------------------- the enemy row
-- One enemy group of a card (Cauldron): a coloured edge, the name in the enemy's colour with the modifiers under it, the
-- weight and the repeat steppers, the Same diamond, and the chips Mods, Custom and Remove. The content keys are the ones of
-- the old row (row_name, info, stepper_value, rep_value, same_selected, hotspot_*), so the same callbacks serve both.
-- content.edge_rgb = { r, g, b } is the enemy's colour (set by the view).
WB.enemy_row = function (node_id)
	local passes = {}
	local C = Workshop.COL
	local S = Workshop.STEPPER
	local W, H = Workshop.LEFT_W, Workshop.ROW_H

	rect(passes, "row_frame", 0, 0, W, H, 0, function (content, style)
		put_rgb(style.color, 200, R.frame)
	end)
	rect(passes, "row_background", 1, 1, W - 2, H - 2, 0.5, function (content, style)
		if content.hotspot_name.is_hover then
			put_mix(style.color, 255, PANEL, Components.accent, 0.10)
		else
			put_rgb(style.color, 255, PANEL)
		end
	end)
	rect(passes, "row_edge", 1, 1, 5, H - 2, 1, function (content, style)
		put_rgb(style.color, 255, content.edge_rgb or R.muted)
	end)

	text(passes, "row_name", C.name, 1, C.name_w, 30, 2, 26, "left", "center")
	text(passes, "info", C.name, 29, C.name_w + 20, 17, 2, 15, "left", "center", function (content, style)
		put_rgb(style.text_color, 255, R.muted)
	end)
	Components.hotspot_pass(passes, "hotspot_name", { 0, 0, 3 }, { C.weight - 10, H })

	local sy = (H - S.height) / 2

	local function stepper_layout(x)
		return {
			minus_offset = { x, sy, 2 },
			value_offset = { x + S.button, sy, 2 },
			value_size = { S.value, S.height },
			plus_offset = { x + S.button + S.value, sy, 2 },
			button_size = { S.button, S.height },
			font_size = S.font,
			sign = S.sign,
		}
	end

	Components.stepper_passes(passes, stepper_layout(C.weight))
	Components.stepper_passes(passes, stepper_layout(C.repeat_), nil, { minus = "hotspot_rep_minus", value = "hotspot_rep_value", plus = "hotspot_rep_plus", text = "rep_value" })

	Components.checkbox_passes(passes, { C.same - 14, 10, 1 }, { 28, 28 }, nil, "same", "same_selected", "hotspot_same")
	Components.hotspot_pass(passes, "hotspot_same", { C.same - 18, 6, 2 }, { 36, 36 })

	-- the chips are as compact as the steppers: 30 high, centred in the row
	local cy = (H - 30) / 2

	Components.button(passes, "hotspot_mods", { C.mods, cy, 2 }, { C.mods_w, 30 }, { font_size = 17, role = "chip", pip = true })
	Components.button(passes, "hotspot_tune", { C.tune, cy, 2 }, { C.tune_w, 30 }, { font_size = 17, role = "chip", pip = true })
	Components.button(passes, "hotspot_action", { C.remove, cy, 2 }, { C.remove_w, 30 }, { font_size = 17, role = "danger", brackets = false })

	return UIWidget.create_definition(passes, node_id, {
		row_name = "",
		info = "",
		stepper_value = "",
		rep_value = "",
		same_selected = false,
		edge_rgb = { 135, 135, 135 },
	}, { W, H })
end

-- ------------------------------------------------------------------------------------------------- the shelf
-- The panel under the enemy rows: a frame, the title and hint of its head row, and the labels of the four bands (fodder,
-- elites, specials, bosses). `layout` = Workshop.shelf_layout. The buttons of the head row (the Dreg / Scab switch and
-- Search all enemies) are ordinary buttons placed over it.
WB.shelf_panel = function (node_id, layout, hint_w)
	local passes = {}
	local W, H = Workshop.LEFT_W, layout.height

	rect(passes, "shelf_fill", 0, 0, W, H, 0, function (content, style)
		put_rgb(style.color, 230, Components.theme.panel)
	end)
	Components.frame_passes(passes, "shelf_frame", W, H, 1, { rgb = Components.theme.frame })
	text(passes, "shelf_title", Workshop.SHELF_PAD, 12, 220, 24, 2, 15, "left", "center", function (content, style)
		put_rgb(style.text_color, 255, R.text)
	end)
	text(passes, "shelf_hint", 232, 12, hint_w or 400, 24, 2, 17, "left", "center", function (content, style)
		put_rgb(style.text_color, 255, R.muted)
	end)
	text(passes, "faction_label", 640, 12, 70, 24, 2, 17, "right", "center", function (content, style)
		put_rgb(style.text_color, 255, R.muted)
	end)

	for i = 1, #layout.bands do
		local band = layout.bands[i]

		text(passes, "band_" .. i, band.x, band.y, band.w, Workshop.COLUMN_LABEL_H - 6, 2, 13, "left", "center", function (content, style)
			put_rgb(style.text_color, 255, R.muted)
		end)
	end

	local content = { shelf_title = "", shelf_hint = "", faction_label = "" }

	for i = 1, #layout.bands do
		content["band_" .. i] = ""
	end

	return UIWidget.create_definition(passes, node_id, content, { W, H })
end

-- One chip of the shelf, `w` wide (Workshop.chip_width: as wide as its label): a dot in the enemy's or the group's colour, the label,
-- a one unit outline, and with `pip` a diamond at the right end lit while the card holds the effect. The button's own flag (hotspot_on)
-- says the card already has this enemy or effect. content.tint (a { frame, fill, hi, text, bright } set, false for the plain chips the
-- shelves use since 2026-10-04) still colours a chip when given. Content: chip_label, dot_rgb, tint.
WB.shelf_chip = function (node_id, w, pip)
	local passes = {}
	local H = Workshop.CHIP_H

	Components.hotspot_pass(passes, "hotspot", { 0, 0, 0 }, { w, H })

	rect(passes, "chip_frame", 0, 0, w, H, 0, function (content, style)
		local st, tint = state_of(content.hotspot), content.tint or nil

		if st == STATE.OFF then
			put_rgb(style.color, 255, R.frame_off)
		elseif st ~= STATE.REST then
			put_rgb(style.color, 255, tint and tint.bright or Components.accent)
		elseif content.hotspot_on == true then
			put_mix(style.color, 255, tint and tint.frame or R.frame, tint and tint.bright or Components.accent, 0.55)
		else
			put_rgb(style.color, 255, tint and tint.frame or R.frame)
		end
	end)
	rect(passes, "chip_fill", 1, 1, w - 2, H - 2, 0.5, function (content, style)
		local st, tint = state_of(content.hotspot), content.tint or nil

		if st == STATE.OFF then
			put_rgb(style.color, 255, R.plate_off)
		elseif st == STATE.DOWN then
			put_mix(style.color, 255, R.plate_down, tint and tint.hi or Components.accent, tint and 0.5 or 0.07)
		elseif st == STATE.HOVER then
			if tint then
				put_rgb(style.color, 255, tint.hi)
			else
				put_mix(style.color, 255, R.plate, Components.accent, 0.14)
			end
		else
			put_rgb(style.color, 255, tint and tint.fill or R.plate)
		end
	end)

	for i = 1, 2 do
		local halo = i == 1
		local r = halo and 5.55 or 5

		passes[#passes + 1] = {
			pass_type = "circle",
			style_id = halo and "chip_dot_h" or "chip_dot",
			style = { offset = { Workshop.CHIP_DOT / 2 - r, H / 2 - r, halo and 3.5 or 4 }, size = { r * 2, r * 2 }, color = shape_color() },
			change_function = function (content, style)
				local rgb = content.dot_rgb or R.muted

				put_rgb(style.color, math.floor((halo and 70 or 255) * (state_of(content.hotspot) == STATE.OFF and 0.4 or 1)), rgb)
			end,
		}
	end

	local tail = pip and Workshop.CHIP_PIP or 0
	local label_w = w - Workshop.CHIP_DOT - Workshop.CHIP_PAD - tail

	text(passes, "chip_label", Workshop.CHIP_DOT, 0, label_w + Workshop.CHIP_PAD, H, 4, Workshop.CHIP_FONT, "left", "center", function (content, style)
		local st, tint = state_of(content.hotspot), content.tint or nil
		style.font_size = math.min(Workshop.CHIP_FONT, label_w / math.max(1, #content.chip_label * Workshop.GLYPH))

		if st == STATE.OFF then
			put_rgb(style.text_color, 255, R.label_off)
		elseif st ~= STATE.REST or content.hotspot_on == true then
			put_rgb(style.text_color, 255, tint and tint.bright or R.bright)
		else
			put_rgb(style.text_color, 255, tint and tint.text or R.text)
		end
	end)

	-- the effect chips: a diamond at the right end, lit while the card holds the effect (the outline stays one unit: the old second
	-- frame of two units made the shelf heavy)
	if pip then
		Components.diamond_passes(passes, "chip_pip", w - tail / 2 - 2, H / 2, 8, 4, nil, function (color, content, halo)
			local on = content.hotspot_on == true

			if state_of(content.hotspot) == STATE.OFF then
				put_rgb(color, halo and 30 or 90, R.label_off)
			else
				put_rgb(color, halo and 80 or 255, on and Components.accent or R.muted)
			end
		end)
		passes[#passes + 1] = { pass_type = "rotated_rect", style_id = "chip_pip_hole", style = { offset = { w - tail / 2 - 2 - 3, H / 2 - 3, 4.5 }, size = { 6, 6 }, color = { 255, 255, 255, 255 }, angle = math.pi / 4, pivot = { 3, 3 } },
			visibility_function = function (content) return content.hotspot_on ~= true end,
			change_function = function (content, style)
				local st = state_of(content.hotspot)

				put_rgb(style.color, 255, st == STATE.OFF and R.plate_off or R.plate)
			end }
	end

	return UIWidget.create_definition(passes, node_id, { chip_label = "", dot_rgb = { 135, 135, 135 }, tint = false }, { w, H })
end

-- ------------------------------------------------------------------------------------------------- the stage
-- The plate the card stands on (525 x 440): a ground tinted with the suit's frame colour, and rings of the suit's accent around the
-- card: concentric discs, each a little brighter than the one outside it, with a thin line of the accent on its edge (no gradient
-- exists, and translucent layers were too faint to see). Every colour is worked out from content.stage = { card, frame, accent }
-- as {r, g, b} (set by the view). The discs and lines have a faint larger copy under them (the UI draws circles without
-- anti-aliasing).
local RINGS = Workshop.STAGE_RINGS
local PLATE_TINT = 0.30 -- share of the suit's frame colour in the plate
local BASE = { 0, 0, 0 } -- scratch: the plate's colour (a literal table in a change function would be allocated every frame)

local function plate_base(stage)
	local frame = stage.frame

	BASE[1] = GROUND[1] + (frame[1] - GROUND[1]) * PLATE_TINT
	BASE[2] = GROUND[2] + (frame[2] - GROUND[2]) * PLATE_TINT
	BASE[3] = GROUND[3] + (frame[3] - GROUND[3]) * PLATE_TINT

	return BASE
end

WB.stage_plate = function (node_id)
	local passes = {}
	local W, H = Workshop.PLATE.w, Workshop.PLATE.h
	local cx, cy = W / 2, 22 + 270 * Workshop.CARD_SCALE / 2

	rect(passes, "plate_fill", 0, 0, W, H, 0, function (content, style)
		put_rgb(style.color, 255, plate_base(content.stage))
	end)

	for i, ring in ipairs(RINGS) do
		local r = ring[1]

		-- the faint copy (the line colour at a third), the line, then the disc inside it
		passes[#passes + 1] = {
			pass_type = "circle",
			style_id = "ring_h" .. i,
			style = { offset = { cx - r - 0.7, cy - r - 0.7, 0.4 + i * 0.1 }, size = { r * 2 + 1.4, r * 2 + 1.4 }, color = shape_color() },
			change_function = function (content, style)
				put_mix(style.color, 90, plate_base(content.stage), content.stage.accent, ring[2] + (1 - ring[2]) * (ring[3] and 0.35 or 0))
			end,
		}
		passes[#passes + 1] = {
			pass_type = "circle",
			style_id = "ring_l" .. i,
			style = { offset = { cx - r, cy - r, 0.45 + i * 0.1 }, size = { r * 2, r * 2 }, color = shape_color() },
			change_function = function (content, style)
				put_mix(style.color, 255, plate_base(content.stage), content.stage.accent, ring[2] + (1 - ring[2]) * (ring[3] and 0.35 or 0))
			end,
		}
		passes[#passes + 1] = {
			pass_type = "circle",
			style_id = "ring_d" .. i,
			style = { offset = { cx - r + (ring[3] and 1.6 or 0), cy - r + (ring[3] and 1.6 or 0), 0.5 + i * 0.1 }, size = { r * 2 - (ring[3] and 3.2 or 0), r * 2 - (ring[3] and 3.2 or 0) }, color = shape_color() },
			change_function = function (content, style)
				put_mix(style.color, 255, plate_base(content.stage), content.stage.accent, ring[2])
			end,
		}
	end

	local function frame(content, style)
		put_rgb(style.color, 255, content.stage.frame)
	end

	rect(passes, "plate_frame_t", 0, 0, W, 1, 3, frame)
	rect(passes, "plate_frame_b", 0, H - 1, W, 1, 3, frame)
	rect(passes, "plate_frame_l", 0, 0, 1, H, 3, frame)
	rect(passes, "plate_frame_r", W - 1, 0, 1, H, 3, frame)

	return UIWidget.create_definition(passes, node_id, { stage = { card = { 30, 36, 19 }, frame = { 58, 68, 33 }, accent = { 183, 194, 58 } } }, { W, H })
end

-- ------------------------------------------------------------------------------------------------- the quick face
-- A suit as a tile (80 x 58): the suit's colours, its mark, its name; lit with the suit's accent when it is the card's suit
-- (and a diamond under it) or under the pointer; a small diamond in the corner when the enemies suggest it. The mark's shapes
-- use the ids of the card tile (icon_t, icon_th, icon_c, icon_ch) so one routine paints both (wave_editor_deck.lua).
-- content.suit = { card, hi, frame, text, accent } as {r, g, b}; content.selected, content.suggested.
WB.suit_tile = function (node_id, tile_ids)
	local passes = {}
	local W, H = Workshop.SUIT_W, Workshop.SUIT_H

	Components.hotspot_pass(passes, "hotspot", { 0, 0, 6 }, { W, H })

	local function lit(content)
		return content.selected == true or state_of(content.hotspot) ~= STATE.REST
	end

	rect(passes, "suit_frame", 0, 0, W, H, 0, function (content, style)
		put_rgb(style.color, 255, lit(content) and content.suit.accent or content.suit.frame)
	end)
	rect(passes, "suit_fill", 1, 1, W - 2, H - 2, 0.5, function (content, style)
		put_rgb(style.color, 255, lit(content) and content.suit.hi or content.suit.card)
	end)

	for i = 1, Spread.ICON_TRIS do
		passes[#passes + 1] = { pass_type = "triangle", style_id = tile_ids.icon_th[i], style = { offset = { 0, 0, 4 }, color = shape_color(), triangle_corners = { { 0, 0 }, { 0, 0 }, { 0, 0 } }, visible = false } }
	end

	for i = 1, Spread.ICON_CIRCS do
		passes[#passes + 1] = { pass_type = "circle", style_id = tile_ids.icon_ch[i], style = { offset = { 0, 0, 4 }, size = { 1, 1 }, color = shape_color(), visible = false } }
	end

	for i = 1, Spread.ICON_TRIS do
		passes[#passes + 1] = { pass_type = "triangle", style_id = tile_ids.icon_t[i], style = { offset = { 0, 0, 4 }, color = shape_color(), triangle_corners = { { 0, 0 }, { 0, 0 }, { 0, 0 } }, visible = false } }
	end

	for i = 1, Spread.ICON_CIRCS do
		passes[#passes + 1] = { pass_type = "circle", style_id = tile_ids.icon_c[i], style = { offset = { 0, 0, 4 }, size = { 1, 1 }, color = shape_color(), visible = false } }
	end

	text(passes, "suit_name", 0, 30, W, 16, 5, 11, "center", "center", function (content, style)
		put_rgb(style.text_color, 255, content.suit.text)
	end)

	-- the diamond under a chosen suit, and the one in the corner of a suggested suit
	Components.diamond_passes(passes, "suit_mark", W / 2, H + 8, 6, 3, function (content)
		return content.selected == true
	end, function (color, content, halo)
		put_rgb(color, halo and 80 or 255, content.suit.accent)
	end)
	Components.diamond_passes(passes, "suit_hint", W - 9, 9, 5, 3, function (content)
		return content.suggested == true
	end, function (color, content, halo)
		put_rgb(color, halo and 80 or 255, Components.BILE)
	end)

	return UIWidget.create_definition(passes, node_id, {
		suit_name = "",
		selected = false,
		suggested = false,
		suit = { card = { 30, 36, 19 }, hi = { 42, 50, 25 }, frame = { 58, 68, 33 }, text = { 230, 223, 195 }, accent = { 183, 194, 58 } },
	}, { W, H })
end

-- The threat control: five diamonds in a row, each a hit area `pitch` wide (default 40) and `height` high (default 44), `side` long
-- (default 15): coloured by their level up to content.threat, dim after it, brighter under the pointer. Clicking one sets the
-- threat by hand. The Cauldron's is the small one, the Mirror's the big one (26, 54, 56).
WB.threat_control = function (node_id, side, pitch, height)
	local passes = {}

	side, pitch, height = side or 15, pitch or Workshop.THREAT_PITCH, height or 44

	for i = 1, 6 do
		Components.hotspot_pass(passes, "hotspot_t" .. i, { (i - 1) * pitch, 0, 6 }, { pitch, height })
		Components.diamond_passes(passes, "threat_" .. i, (i - 1) * pitch + pitch / 2, height / 2, side, 3, nil, function (color, content, halo)
			local on = i <= (content.threat or 0)
			local rgb = on and mod.rw.cards.threat_color(i, content.suit) or R.muted
			if halo and i == 6 then rgb = mod.rw.cards.threat_edge(content.suit) end
			local hover = content["hotspot_t" .. i].is_hover

			put_rgb(color, on and (halo and (i == 6 and 255 or 70) or 255) or (hover and (halo and 40 or 150) or (halo and 22 or 64)), rgb)
		end)
	end

	return UIWidget.create_definition(passes, node_id, { threat = 3 }, { 6 * pitch, height })
end

-- ------------------------------------------------------------------------------------------------- the Mirror
local FIELD = { 12, 15, 8 }
local TRACK_GREY, TRACK_BROWN, TRACK_OCHRE = { 74, 74, 64 }, { 90, 70, 49 }, { 194, 122, 44 }
local PUS = { 227, 207, 74 }

-- text that wraps (the passes of `text` do not)
local function wrapped(passes, id, x, y, w, h, z, size, change)
	text(passes, id, x, y, w, h, z, size, "left", "top", change)
	passes[#passes].style.word_wrap = true
end

-- A section's header on the Mirror: its title, a hint after it, a thin line under both. Content: head_title, head_hint.
WB.section_head = function (node_id)
	local passes = {}
	local W, H = Workshop.LEFT_W, Workshop.MIRROR.head_h

	text(passes, "head_title", 0, 0, 140, H - 2, 2, 15, "left", "center", function (content, style)
		put_rgb(style.text_color, 255, R.text)
	end)
	text(passes, "head_hint", 150, 0, W - 150, H - 2, 2, 18, "left", "center", function (content, style)
		put_rgb(style.text_color, 255, R.muted)
	end)
	rect(passes, "head_line", 0, H - 1, W, 1, 1, function (content, style)
		put_rgb(style.color, 255, R.frame)
	end)

	return UIWidget.create_definition(passes, node_id, { head_title = "", head_hint = "" }, { W, H })
end

-- The mark of a suit: the triangles and circles of the card tile, with the same style ids (so one routine paints both), the
-- feathers first. Used by the suit tile and the suit plate.
local function mark_passes(passes, tile_ids)
	for i = 1, Spread.ICON_TRIS do
		passes[#passes + 1] = { pass_type = "triangle", style_id = tile_ids.icon_th[i], style = { offset = { 0, 0, 4 }, color = shape_color(), triangle_corners = { { 0, 0 }, { 0, 0 }, { 0, 0 } }, visible = false } }
	end

	for i = 1, Spread.ICON_CIRCS do
		passes[#passes + 1] = { pass_type = "circle", style_id = tile_ids.icon_ch[i], style = { offset = { 0, 0, 4 }, size = { 1, 1 }, color = shape_color(), visible = false } }
	end

	for i = 1, Spread.ICON_TRIS do
		passes[#passes + 1] = { pass_type = "triangle", style_id = tile_ids.icon_t[i], style = { offset = { 0, 0, 4 }, color = shape_color(), triangle_corners = { { 0, 0 }, { 0, 0 }, { 0, 0 } }, visible = false } }
	end

	for i = 1, Spread.ICON_CIRCS do
		passes[#passes + 1] = { pass_type = "circle", style_id = tile_ids.icon_c[i], style = { offset = { 0, 0, 4 }, size = { 1, 1 }, color = shape_color(), visible = false } }
	end
end

-- A suit as a plate (274 x 66): the suit's colours, its mark (30 units), its name, its own line of whisper; the card's suit is
-- lit with a diamond at the right, the suit the enemies suggest says so in its corner. Content: suit_name, suit_line, sug_label,
-- selected, suit = { card, hi, frame, text, accent }.
WB.suit_plate = function (node_id, tile_ids)
	local passes = {}
	local W, H = Workshop.MIRROR.plate.w, Workshop.MIRROR.plate.h

	Components.hotspot_pass(passes, "hotspot", { 0, 0, 6 }, { W, H })

	local function lit(content)
		return content.selected == true or state_of(content.hotspot) ~= STATE.REST
	end

	rect(passes, "plate_frame", 0, 0, W, H, 0, function (content, style)
		put_rgb(style.color, 255, lit(content) and content.suit.accent or content.suit.frame)
	end)
	rect(passes, "plate_fill", 1, 1, W - 2, H - 2, 0.5, function (content, style)
		put_rgb(style.color, 255, lit(content) and content.suit.hi or content.suit.card)
	end)
	mark_passes(passes, tile_ids)
	text(passes, "suit_name", 56, 8, 190, 28, 5, 22, "left", "center", function (content, style)
		put_rgb(style.text_color, 255, content.suit.text)
	end)
	text(passes, "suit_line", 56, 34, W - 64, 28, 5, 12, "left", "center", function (content, style)
		put_rgb(style.text_color, 170, content.suit.text)
	end)
	text(passes, "sug_label", W - 118, 6, 106, 14, 5, 11, "right", "center", function (content, style)
		put_rgb(style.text_color, 255, Components.BILE)
	end)
	Components.diamond_passes(passes, "plate_mark", W - 18, H / 2 + 8, 9, 3, function (content)
		return content.selected == true
	end, function (color, content, halo)
		put_rgb(color, halo and 80 or 255, content.suit.accent)
	end)

	return UIWidget.create_definition(passes, node_id, {
		suit_name = "",
		suit_line = "",
		sug_label = "",
		selected = false,
		suit = { card = { 30, 36, 19 }, hi = { 42, 50, 25 }, frame = { 58, 68, 33 }, text = { 230, 223, 195 }, accent = { 183, 194, 58 } },
	}, { W, H })
end

-- The field that shows the card's whisper (the text, or the suit's own line when the card has none, dimmer); a click on it
-- opens the box, like Change does. Content: whisper_text, whisper_own.
WB.whisper_field = function (node_id)
	local passes = {}
	local W, H = Workshop.MIRROR.whisper_w, Workshop.MIRROR.whisper_h

	Components.hotspot_pass(passes, "hotspot", { 0, 0, 6 }, { W, H })
	rect(passes, "field_frame", 0, 0, W, H, 0, function (content, style)
		put_rgb(style.color, 255, state_of(content.hotspot) == STATE.REST and R.frame or Components.accent)
	end)
	rect(passes, "field_fill", 1, 1, W - 2, H - 2, 0.5, function (content, style)
		put_rgb(style.color, 255, FIELD)
	end)
	text(passes, "whisper_text", 16, 0, W - 32, H, 3, 22, "left", "center", function (content, style)
		put_rgb(style.text_color, 255, content.whisper_own and R.text or R.muted)
	end)

	return UIWidget.create_definition(passes, node_id, { whisper_text = "", whisper_own = false }, { W, H })
end

-- The look of the cooldown on the Mirror (365 x 110): its name, what it does, a small picture of it (four stripes from grey through
-- brown and ochre to the suit's colour, content.accent_rgb), and EVERY CARD in the corner, lit with an accent frame (the button's
-- own flag, hotspot_on). Since 2026-10-04 rot and renewal is the only look, so `kind` is "rot"; the plate is never clicked.
WB.look_plate = function (node_id, kind)
	local passes = {}
	local W, H = Workshop.MIRROR.look.w, Workshop.MIRROR.look.h
	local SX, SW, SY, SH = 16, W - 32, 82, 20

	Components.button(passes, "hotspot", { 0, 0, 0 }, { W, H }, { role = "chip", label = "" })

	local function selected(content)
		return content.hotspot_on == true
	end

	for i, frame in ipairs({ { 0, 0, W, 2 }, { 0, H - 2, W, 2 }, { 0, 0, 2, H }, { W - 2, 0, 2, H } }) do
		rect(passes, "look_sel_" .. i, frame[1], frame[2], frame[3], frame[4], 6, function (content, style)
			put_rgb(style.color, 255, Components.accent)
		end, selected)
	end

	text(passes, "look_name", 16, 10, W - 130, 28, 5, 22, "left", "center", function (content, style)
		Components.paint_label(style.text_color, "chip", state_of(content.hotspot), Components.accent, content.hotspot_on)
	end)
	wrapped(passes, "look_desc", 16, 40, W - 32, 38, 5, 16, function (content, style)
		put_rgb(style.text_color, 255, R.muted)
	end)
	text(passes, "look_auto", W - 114, 12, 100, 14, 5, 11, "right", "center", function (content, style)
		put_rgb(style.text_color, 255, Components.BILE)
	end)

	if kind == "rot" then
		local cell = SW / 4

		for i, rgb in ipairs({ TRACK_GREY, TRACK_BROWN, TRACK_OCHRE }) do
			rect(passes, "swatch_" .. i, SX + (i - 1) * cell, SY, cell, SH, 4, function (content, style)
				put_rgb(style.color, 255, rgb)
			end)
		end

		rect(passes, "swatch_4", SX + 3 * cell, SY, cell, SH, 4, function (content, style)
			put_rgb(style.color, 255, content.accent_rgb)
		end)
	end

	return UIWidget.create_definition(passes, node_id, {
		look_name = "",
		look_desc = "",
		look_auto = "",
		look_sample = "",
		accent_rgb = { 183, 194, 58 },
	}, { W, H })
end

-- The card as the Spread HUD draws it (a coloured bar at the left, the name, the suit's mark, the threat diamonds and the enemy dots)
-- at 1.5 times its size: "In the hand" on the Mirror. The shapes use the ids of the card tile (icon_*, th_*, dot_*). The view
-- sets the size of the background and the bar (they follow the lines of the name) and the places of everything.
WB.hand_card = function (node_id, tile_ids)
	local passes = {}
	local H = Workshop.HAND

	passes[#passes + 1] = { pass_type = "rect", style_id = "hand_bg", style = { offset = { 0, 0, 0 }, size = { H.w, H.max_h }, color = shape_color() } }
	passes[#passes + 1] = { pass_type = "rect", style_id = "hand_bar", style = { offset = { 0, 0, 1 }, size = { H.bar * H.scale, H.max_h }, color = shape_color() } }

	-- the frame of a Heresy card (hidden for every other suit): four lines, placed by View._paint_hand
	for _, side in ipairs({ "t", "b", "l", "r" }) do
		passes[#passes + 1] = { pass_type = "rect", style_id = "hand_edge_" .. side, style = { offset = { 0, 0, 2 }, size = { 1, 1 }, color = shape_color(), visible = false } }
	end
	mark_passes(passes, tile_ids)
	passes[#passes + 1] = {
		pass_type = "text",
		style_id = "hand_name",
		value_id = "hand_name",
		value = "",
		style = {
			font_type = "itc_novarese_bold",
			font_size = H.name_font * H.scale,
			text_color = shape_color(),
			text_horizontal_alignment = "left",
			text_vertical_alignment = "top",
			offset = { 0, 0, 5 },
			size = { 100, 30 },
			word_wrap = true,
		},
	}

	for i = 1, 6 do
		passes[#passes + 1] = { pass_type = "rotated_rect", style_id = tile_ids.th_h[i], style = { offset = { 0, 0, 3.8 }, size = { 13, 13 }, color = shape_color(), angle = math.pi / 4, pivot = { 6.5, 6.5 }, visible = false } }
	end

	for i = 1, 6 do
		passes[#passes + 1] = { pass_type = "rotated_rect", style_id = tile_ids.th_o[i], style = { offset = { 0, 0, 4 }, size = { 12, 12 }, color = shape_color(), angle = math.pi / 4, pivot = { 6, 6 }, visible = false } }
	end

	for i = 1, 6 do
		passes[#passes + 1] = { pass_type = "circle", style_id = tile_ids.dot_h[i], style = { offset = { 0, 0, 3.8 }, size = { 1, 1 }, color = shape_color(), visible = false } }
	end

	for i = 1, 6 do
		passes[#passes + 1] = { pass_type = "circle", style_id = tile_ids.dot[i], style = { offset = { 0, 0, 4 }, size = { 1, 1 }, color = shape_color(), visible = false } }
	end

	return UIWidget.create_definition(passes, node_id, { hand_name = "" }, { H.w, H.max_h })
end

return WB
