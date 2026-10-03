-- Dynamic widget blueprints for the wave editor: the shared row, single
-- buttons, labelled steppers, scroll buttons and the popup buttons/input.
local mod = get_mod("RealmsWaves")

local UIWidget = require("scripts/managers/ui/ui_widget")
local Components = mod:io_dofile("RealmsWaves/scripts/mods/RealmsWaves/ui/wave_editor_components")
local Workshop = mod:io_dofile("RealmsWaves/scripts/mods/RealmsWaves/ui/workshop")

local blueprints = {}
local colors = Components.colors

-- One row serves three screens; content flags decide which parts exist:
--   show_check    checkbox (settings, modifiers)
--   show_stepper  - value +  (count in the detail screen, numbers in the settings)
--   show_share    share of total chance (unused since the Deck replaced the wave list)
--   show_action   right-hand button, label in content.hotspot_action_text
--   show_mods     "Mods" button (detail screen, where the share column is unused)
--   show_tune     "Custom" button beside it (detail screen): the group's custom mods (health, size, speed...)
--   show_rep      second stepper: units added on every repeat tick (detail screen)
blueprints.row = function (node_id)
	local passes = {}

	passes[#passes + 1] = {
		pass_type = "rect",
		style_id = "row_frame",
		style = { size = { 1710, 46 }, offset = { 0, 0, 0 }, color = { 190, 58, 68, 33 } },
		-- the frame of the page's theme (the card's suit on its screens)
		change_function = function (content, style)
			Components.put_rgb(style.color, 190, Components.theme.frame)
		end,
	}
	passes[#passes + 1] = {
		pass_type = "rect",
		style_id = "row_background",
		style = { size = { 1708, 44 }, offset = { 1, 1, 0.5 }, color = Components.clone_color(colors.normal) },
		-- highlight the whole row while the pointer is over its name/composition area: a wash of the accent
		change_function = function (content, style)
			if content.hotspot_name.is_hover then
				Components.put_mix(style.color, 250, Components.theme.hi, Components.accent, 0.10)
			else
				Components.put_rgb(style.color, colors.normal[1], Components.theme.row)
			end
		end,
	}

	Components.checkbox_passes(passes, { 10, 9, 1 }, nil, "show_check", nil, nil, "hotspot_check")
	Components.hotspot_pass(passes, "hotspot_check", { 4, 5, 2 }, { 36, 36 }, "show_check")

	-- clickable area: name + composition (everything left of the steppers)
	Components.hotspot_pass(passes, "hotspot_name", { 60, 0, 3 }, { 1130, 46 })
	Components.text_pass(passes, "row_name", "row_name", { 60, 0, 2 }, { 480, 46 }, 22, colors.text)
	Components.text_pass(passes, "info", "info", { 550, 0, 2 }, { 640, 46 }, 18, colors.muted)

	Components.stepper_passes(passes, {
		minus_offset = { 1210, 3, 2 },
		value_offset = { 1256, 3, 2 },
		value_size = { 60, 40 },
		plus_offset = { 1318, 3, 2 },
	}, "show_stepper")

	-- units added on every repeat tick (detail screen only); the count stepper above is the initial spawn
	Components.stepper_passes(passes, {
		minus_offset = { 905, 3, 2 },
		value_offset = { 951, 3, 2 },
		value_size = { 60, 40 },
		plus_offset = { 1013, 3, 2 },
	}, "show_rep", { minus = "hotspot_rep_minus", value = "hotspot_rep_value", plus = "hotspot_rep_plus", text = "rep_value" })

	-- "Same": every repeat spawns the same number as the initial spawn (the stepper is ignored)
	Components.checkbox_passes(passes, { 1128, 9, 1 }, nil, "show_rep", "same", "same_selected", "hotspot_same")
	Components.hotspot_pass(passes, "hotspot_same", { 1122, 5, 2 }, { 36, 36 }, "show_rep")

	Components.text_pass(passes, "share", "share", { 1390, 0, 2 }, { 120, 46 }, 20, colors.muted, "right", "show_share")
	-- Mods, Custom and the action button (Remove, Change, Open, Add...) side by side after the count stepper (ends at 1362)
	-- chips: Mods and Custom light up (a lit diamond) when the group has any
	Components.button(passes, "hotspot_mods", { 1372, 3, 2 }, { 104, 40 }, { font_size = 18, flag = "show_mods", role = "chip", pip = true })
	Components.button(passes, "hotspot_tune", { 1482, 3, 2 }, { 104, 40 }, { font_size = 18, flag = "show_tune", role = "chip", pip = true })
	Components.button(passes, "hotspot_action", { 1592, 3, 2 }, { 108, 40 }, { font_size = 20, flag = "show_action", role = "chip" })

	return UIWidget.create_definition(passes, node_id, {
		row_name = "",
		info = "",
		stepper_value = "",
		share = "",
		checkbox_selected = false,
		show_check = false,
		show_stepper = false,
		show_share = false,
		show_action = false,
		show_mods = false,
		show_tune = false,
		show_rep = false,
		rep_value = "",
		same_selected = false,
	}, { 1710, 46 })
end

-- role: "standard" (default), "primary", "danger", "quiet", "tab" (see Components.button); pip: a toggle diamond before the label
blueprints.button = function (node_id, width, role, height, label, pip, font_size)
	local passes = {}

	Components.button(passes, "hotspot", { 0, 0, 0 }, { width, height or 44 }, { font_size = font_size or 22, role = role, label = label, pip = pip })

	return UIWidget.create_definition(passes, node_id, {}, { width, height or 44 })
end

-- Label + minus + value + plus + trailing text (content.label / stepper_value / extra).
-- `label_width` (default 200) makes room for a long label; everything else moves right with it.
blueprints.setting_stepper = function (node_id, width, label_width)
	local passes = {}
	local x0 = label_width or 200

	width = width or 800

	Components.text_pass(passes, "label", "label", { 0, 0, 2 }, { x0, 48 }, 22, colors.text)
	Components.stepper_passes(passes, {
		-- the value sits close to the - and + buttons (44 px wide each, 2 px gaps)
		minus_offset = { x0 + 5, 4, 2 },
		value_offset = { x0 + 51, 4, 2 },
		value_size = { 64, 40 },
		plus_offset = { x0 + 117, 4, 2 },
	})
	Components.text_pass(passes, "extra", "extra", { x0 + 178, 0, 2 }, { width - x0 - 188, 48 }, 20, colors.muted)

	return UIWidget.create_definition(passes, node_id, { label = "", stepper_value = "", extra = "" }, { width, 48 })
end

-- The compact stepper of the Workshop (the spawn block and the chance): a label, the plate (Workshop.STEPPER: minus, value, plus,
-- 40 + 56 + 40 wide) after `label_width`, and a trailing text. The names are the ones of setting_stepper (label, stepper_value,
-- extra, hotspot_minus / value / plus), content.stepper_value_dim = true dims the plate.
blueprints.workshop_stepper = function (node_id, width, label_width, font_size, label_color)
	local passes = {}
	local S = Workshop.STEPPER
	local x0 = label_width
	local after = x0 + 2 * S.button + S.value + 12

	Components.text_pass(passes, "label", "label", { 0, 0, 2 }, { x0, 48 }, font_size or 20, label_color or colors.text)
	Components.stepper_passes(passes, {
		minus_offset = { x0, 4, 2 },
		value_offset = { x0 + S.button, 4, 2 },
		value_size = { S.value, S.height },
		plus_offset = { x0 + S.button + S.value, 4, 2 },
		button_size = { S.button, S.height },
	})
	-- the trailing text may run a little past the node (the next column starts 26 units later)
	Components.text_pass(passes, "extra", "extra", { after, 0, 2 }, { width - after + 20, 48 }, 17, colors.muted)

	return UIWidget.create_definition(passes, node_id, { label = "", stepper_value = "", extra = "" }, { width, 48 })
end

-- the scroll buttons: a triangle (`label` "^" points up, anything else down)
blueprints.scroll_button = function (node_id, label)
	local passes = {}

	Components.button(passes, "hotspot", { 0, 0, 0 }, { 44, 36 }, { role = "icon", glyph = label == "^" and "up" or "down" })

	return UIWidget.create_definition(passes, node_id, {}, { 44, 36 })
end

-- OK (primary) and Cancel (standard): the same buttons as everywhere, no vanilla ornamental frame
blueprints.popup_confirm = blueprints.button(Components.POPUP_CONFIRM_NAME, Components.POPUP_BUTTON_WIDTH, "primary", Components.POPUP_BUTTON_HEIGHT, mod:localize("popup_ok"))
blueprints.popup_cancel = blueprints.button(Components.POPUP_CANCEL_NAME, Components.POPUP_BUTTON_WIDTH, nil, Components.POPUP_BUTTON_HEIGHT, mod:localize("popup_cancel"))

blueprints.popup_input = Components.popup_input_definition()

-- ------------------------------------------------------------------------------------ the Deck: card tiles
-- A card tile (228 x 270) is made of rectangles, circles, triangles, rotated squares and text, exactly like the Spread
-- HUD (ui/spread.lua draws the suit mark). Every shape starts hidden: the view writes geometry, colours and visibility
-- into the widget styles (wave_editor_deck.lua, _paint_tile). The hotspots never overlap (a click would reach both): the
-- face above the pips toggles the card in or out of the draw, each of the ten pips sets the chance, the left of the state
-- line toggles too and the Edit pill opens the card; a right click on any of them opens the card as well.
local Spread = mod:io_dofile("RealmsWaves/scripts/mods/RealmsWaves/ui/spread")
local Deck = mod:io_dofile("RealmsWaves/scripts/mods/RealmsWaves/ui/deck")

blueprints.Deck, blueprints.Spread = Deck, Spread

local TILE_W, TILE_H = Deck.TILE_W, Deck.TILE_H
local DISPLAY_FONT = "itc_novarese_bold"

-- The boxes of a tile at scale k (x, y, w, h in the tile's units times k): 1 is the Deck's tile (228 x 270), the card on the
-- stage of a card's screens is 1.4. Fonts, shapes and hit areas scale with it, the 1 unit lines do not (docs/08).
blueprints.tile_metrics = function (k)
	k = k or 1

	local function box(x, y, w, h)
		return { x * k, y * k, w * k, h * k }
	end

	local metrics = {
		k = k,
		w = TILE_W * k,
		h = TILE_H * k,
		-- boxes (x, y, w, h) inside the tile
		suit_label = box(14, 12, 150, 20),
		icon = box(188, 8, 26, 26),
		name = box(14, Deck.NAME_Y, 200, 3 * Deck.NAME_LINE),
		-- the divider and the composition sit under the name, wherever Deck.layout puts them (these are the one-line values)
		divider = box(14, 64, 200, 1),
		comp = box(14, 71, 200, 85),
		mods = box(14, 148, 200, 16),
		whisper = box(14, 166, 200, 32),
		row_y = 208 * k, -- centre of the bottom row (threat diamonds left, dots right)
		diamonds_x = (14 + 4) * k, -- centre of the first diamond
		dots_right = 214 * k,
		pips_y = 220 * k,
		pips_x = 14 * k,
		pip = { 16 * k, 7 * k, 4 * k }, -- width, height, gap
		pip_hit_y = 217 * k,
		pip_hit_h = 15 * k,
		-- the cooldown row under the pips: a plate with a minus, the label and the value, a plate with a plus (30 s a click; the
		-- plates only on the Deck's own tiles, the stage card shows the value alone)
		cd_minus = box(14, 232, 24, 17),
		cd_plus = box(190, 232, 24, 17),
		cd_label = box(44, 232, 70, 17),
		cd_value = box(114, 232, 72, 17),
		state_left = box(14, 250, 100, 16),
		state_clock = box(100, 250, 62, 16),
		edit = box(168, 250, 46, 16), -- the pill: lit while the pointer is on it, and exactly its click area
		hot_top = box(0, 0, TILE_W, 217),
		-- the click areas of the cooldown row fill the row edge to edge (no dead strip), the middle one is the value (a number box)
		hot_cd_minus = box(0, 232, 42, 17),
		hot_cd_value = box(42, 232, 144, 17),
		hot_cd_plus = box(186, 232, 42, 17),
		hot_state = box(0, 249, 166, 21),
		hot_edit = box(168, 250, 46, 16),
	}

	metrics.divider[4] = 1 -- a line stays 1 unit thick

	return metrics
end

-- the Deck's own tile
blueprints.TILE = blueprints.tile_metrics(1)

local function shape_color()
	return { 255, 255, 255, 255 }
end

local function rect_pass(passes, id, x, y, w, h, z)
	passes[#passes + 1] = { pass_type = "rect", style_id = id, style = { offset = { x, y, z }, size = { w, h }, color = shape_color(), visible = false } }
end

local function circle_pass(passes, id, z)
	passes[#passes + 1] = { pass_type = "circle", style_id = id, style = { offset = { 0, 0, z }, size = { 1, 1 }, color = shape_color(), visible = false } }
end

local function triangle_pass(passes, id, z)
	passes[#passes + 1] = {
		pass_type = "triangle",
		style_id = id,
		style = { offset = { 0, 0, z }, color = shape_color(), triangle_corners = { { 0, 0 }, { 0, 0 }, { 0, 0 } }, visible = false },
	}
end

local function diamond_pass(passes, id, z, side)
	passes[#passes + 1] = {
		pass_type = "rotated_rect",
		style_id = id,
		style = { offset = { 0, 0, z }, size = { side, side }, color = shape_color(), angle = math.pi / 4, pivot = { side / 2, side / 2 }, visible = false },
	}
end

local function tile_text(passes, id, box, font, size, horizontal, vertical, z)
	passes[#passes + 1] = {
		pass_type = "text",
		style_id = id,
		value_id = id,
		value = "",
		style = {
			font_type = font,
			font_size = size,
			text_color = shape_color(),
			text_horizontal_alignment = horizontal or "left",
			text_vertical_alignment = vertical or "top",
			offset = { box[1], box[2], z },
			size = { box[3], box[4] },
			word_wrap = true,
			visible = false,
		},
	}
end

-- the ids of the repeated passes, so the view never concatenates strings while it paints
blueprints.TILE_IDS = {
	border = { "border_t", "border_b", "border_l", "border_r" },
	ping = { "ping_t", "ping_b", "ping_l", "ping_r" },
	bubble = { "bubble_1", "bubble_2", "bubble_3" },
	icon_t = {}, icon_c = {}, icon_th = {}, icon_ch = {}, th_o = {}, th_h = {}, dot = {}, dot_h = {}, pip = {}, hotspot_pip = {},
}

for i = 1, Spread.ICON_TRIS do
	blueprints.TILE_IDS.icon_t[i] = "icon_t" .. i
	blueprints.TILE_IDS.icon_th[i] = "icon_th" .. i
end

for i = 1, Spread.ICON_CIRCS do
	blueprints.TILE_IDS.icon_c[i] = "icon_c" .. i
	blueprints.TILE_IDS.icon_ch[i] = "icon_ch" .. i
end

for i = 1, 5 do
	blueprints.TILE_IDS.th_o[i], blueprints.TILE_IDS.th_h[i] = "th_o" .. i, "th_h" .. i
end

for i = 1, 6 do
	blueprints.TILE_IDS.dot[i], blueprints.TILE_IDS.dot_h[i] = "dot_" .. i, "dot_h" .. i
end

for i = 1, Deck.PIPS do
	blueprints.TILE_IDS.pip[i] = "pip_" .. i
	blueprints.TILE_IDS.hotspot_pip[i] = "hotspot_pip" .. i
end

-- The click area of pip i: its width plus half the gap on each side; the first and the last reach the edge of the tile, so
-- there is no dead strip beside the pips. `T` = the tile's metrics (default: the Deck's).
blueprints.pip_hit = function (i, T)
	T = T or blueprints.TILE

	local pitch = T.pip[1] + T.pip[3]
	local left = i == 1 and 0 or T.pips_x + (i - 1) * pitch - T.pip[3] / 2
	local right = i == Deck.PIPS and T.w or T.pips_x + i * pitch - T.pip[3] / 2

	return left, T.pip_hit_y, right - left, T.pip_hit_h
end

-- A card tile at scale `k` (default 1: 228 x 270, the Deck's; the stage of a card's screens uses 1.4). Its metrics are in
-- content.metrics, which the painting reads (ui/wave_editor_deck.lua). `interactive` (the stage card): the name and the line in quotes
-- are click areas (hotspot_name, hotspot_whisper: rename, change the whisper) that are underlined under the pointer; their
-- places are set by the painting. The Deck's tiles have none (the whole face there is the toggle).
blueprints.tile = function (node_id, k, interactive)
	local passes = {}
	local T = (k == nil or k == 1) and blueprints.TILE or blueprints.tile_metrics(k)
	local W, H = T.w, T.h

	local function font(size)
		return math.floor(size * T.k + 0.5)
	end

	-- the glow (the stock frame texture) and the face
	passes[#passes + 1] = {
		pass_type = "texture",
		style_id = "glow",
		value = "content/ui/materials/frames/frame_glow_01",
		style = { scale_to_material = true, offset = { -12 * T.k, -12 * T.k, 0 }, size = { W + 24 * T.k, H + 24 * T.k }, color = shape_color(), visible = false },
	}
	passes[#passes + 1] = {
		pass_type = "rect",
		style_id = "bg",
		style = { offset = { 0, 0, 1 }, size = { W, H }, color = shape_color() },
		-- the face takes the suit's lighter colour while the pointer is on the tile
		change_function = function (content, style)
			local hover = content.hotspot_top.is_hover or content.hotspot_state.is_hover or content.hotspot_edit.is_hover or content.strip_hover

			if not hover then
				for i = 1, Deck.PIPS do
					if content[blueprints.TILE_IDS.hotspot_pip[i]].is_hover then
						hover = true

						break
					end
				end
			end

			local rgb = hover and content.bg_hi or content.bg_rgb

			style.color[1], style.color[2], style.color[3], style.color[4] = 255, rgb[1], rgb[2], rgb[3]
		end,
	}

	-- "the vial fills": a liquid rising from the bottom of the card, with a bright top line and bubbles
	rect_pass(passes, "vial", 0, H, W, 0, 2)
	rect_pass(passes, "vial_line", 0, H, W, 2, 2)

	for i = 1, 3 do
		circle_pass(passes, blueprints.TILE_IDS.bubble[i], 3)
	end

	rect_pass(passes, "border_t", 0, 0, W, 1, 2)
	rect_pass(passes, "border_b", 0, H - 1, W, 1, 2)
	rect_pass(passes, "border_l", 0, 0, 1, H, 2)
	rect_pass(passes, "border_r", W - 1, 0, 1, H, 2)

	-- the suit mark: every triangle and circle has a faint, slightly larger copy under it (the UI draws shapes without
	-- anti-aliasing, the copy softens the stair-stepped edge, see Spread.FEATHER)
	for i = 1, Spread.ICON_TRIS do
		triangle_pass(passes, blueprints.TILE_IDS.icon_th[i], 4)
	end

	for i = 1, Spread.ICON_CIRCS do
		circle_pass(passes, blueprints.TILE_IDS.icon_ch[i], 4)
	end

	for i = 1, Spread.ICON_TRIS do
		triangle_pass(passes, blueprints.TILE_IDS.icon_t[i], 4)
	end

	for i = 1, Spread.ICON_CIRCS do
		circle_pass(passes, blueprints.TILE_IDS.icon_c[i], 4)
	end

	tile_text(passes, "suit_label", T.suit_label, "proxima_nova_bold", font(12), "left", "center", 4)
	tile_text(passes, "name", T.name, DISPLAY_FONT, font(20), "left", "top", 5)
	rect_pass(passes, "divider", T.divider[1], T.divider[2], T.divider[3], T.divider[4], 3)
	tile_text(passes, "comp", T.comp, "proxima_nova_bold", font(13), "left", "top", 4)
	tile_text(passes, "mods", T.mods, "proxima_nova_bold", font(12), "left", "center", 4)
	tile_text(passes, "whisper", T.whisper, "proxima_nova_bold", font(13), "left", "top", 4)

	-- threat: filled diamonds up to the level, the rest the same diamonds dimmed (never an outline: two rotated squares
	-- make an uneven one with gaps); the faint copy under each is its anti-aliasing
	for i = 1, 5 do
		diamond_pass(passes, blueprints.TILE_IDS.th_h[i], 3.8, 9.4 * T.k)
	end

	for i = 1, 5 do
		diamond_pass(passes, blueprints.TILE_IDS.th_o[i], 4, 8 * T.k)
	end

	for i = 1, 6 do
		circle_pass(passes, blueprints.TILE_IDS.dot_h[i], 3.8)
	end

	for i = 1, 6 do
		circle_pass(passes, blueprints.TILE_IDS.dot[i], 4)
	end

	for i = 1, Deck.PIPS do
		rect_pass(passes, blueprints.TILE_IDS.pip[i], T.pips_x + (i - 1) * (T.pip[1] + T.pip[3]), T.pips_y, T.pip[1], T.pip[2], 4)
	end

	-- the cooldown row: the plates of the minus and the plus with their glyphs (bars placed by the painting), the label and the value
	rect_pass(passes, "cd_minus_bg", T.cd_minus[1], T.cd_minus[2] + 1 * T.k, T.cd_minus[3], T.cd_minus[4] - 2 * T.k, 3)
	rect_pass(passes, "cd_plus_bg", T.cd_plus[1], T.cd_plus[2] + 1 * T.k, T.cd_plus[3], T.cd_plus[4] - 2 * T.k, 3)
	rect_pass(passes, "cd_minus_h", 0, 0, 1, 1, 5)
	rect_pass(passes, "cd_plus_h", 0, 0, 1, 1, 5)
	rect_pass(passes, "cd_plus_v", 0, 0, 1, 1, 5)
	tile_text(passes, "cd_label", T.cd_label, "proxima_nova_bold", font(11), "left", "center", 4)
	tile_text(passes, "cd_value", T.cd_value, "proxima_nova_bold", font(13), "right", "center", 4)

	-- the state line: what the card is doing, the cooldown clock, and the Edit pill
	tile_text(passes, "state_left", T.state_left, "proxima_nova_bold", font(12), "left", "center", 4)
	tile_text(passes, "state_clock", T.state_clock, "proxima_nova_bold", font(12), "right", "center", 4)
	rect_pass(passes, "edit_bg", T.edit[1], T.edit[2], T.edit[3], T.edit[4], 3)
	tile_text(passes, "edit_label", T.edit, "proxima_nova_bold", font(12), "center", "center", 5)

	-- the ready ping: a ring that leaves the card and fades, when its cooldown ends
	rect_pass(passes, "ping_t", 0, 0, W, 2, 7)
	rect_pass(passes, "ping_b", 0, 0, W, 2, 7)
	rect_pass(passes, "ping_l", 0, 0, 2, H, 7)
	rect_pass(passes, "ping_r", 0, 0, 2, H, 7)

	Components.hotspot_pass(passes, "hotspot_top", { T.hot_top[1], T.hot_top[2], 6 }, { T.hot_top[3], T.hot_top[4] })
	Components.hotspot_pass(passes, "hotspot_state", { T.hot_state[1], T.hot_state[2], 6 }, { T.hot_state[3], T.hot_state[4] })
	Components.hotspot_pass(passes, "hotspot_edit", { T.hot_edit[1], T.hot_edit[2], 6 }, { T.hot_edit[3], T.hot_edit[4] })
	Components.hotspot_pass(passes, "hotspot_cd_minus", { T.hot_cd_minus[1], T.hot_cd_minus[2], 6 }, { T.hot_cd_minus[3], T.hot_cd_minus[4] })
	Components.hotspot_pass(passes, "hotspot_cd_value", { T.hot_cd_value[1], T.hot_cd_value[2], 6 }, { T.hot_cd_value[3], T.hot_cd_value[4] })
	Components.hotspot_pass(passes, "hotspot_cd_plus", { T.hot_cd_plus[1], T.hot_cd_plus[2], 6 }, { T.hot_cd_plus[3], T.hot_cd_plus[4] })

	for i = 1, Deck.PIPS do
		local x, y, w, h = blueprints.pip_hit(i, T)

		Components.hotspot_pass(passes, blueprints.TILE_IDS.hotspot_pip[i], { x, y, 6 }, { w, h }, nil, true)
	end

	if interactive then
		for _, id in ipairs({ "name", "whisper" }) do
			Components.hotspot_pass(passes, "hotspot_" .. id, { 0, 0, 7 }, { 1, 1 })
			passes[#passes + 1] = {
				pass_type = "rect",
				style_id = id .. "_ul",
				style = { offset = { 0, 0, 6 }, size = { 1, 2 }, color = shape_color() },
				visibility_function = function (content)
					return content["hotspot_" .. id].is_hover == true and not content["hotspot_" .. id].disabled
				end,
			}
		end
	end

	return UIWidget.create_definition(passes, node_id, {
		bg_rgb = { 30, 36, 19 },
		bg_hi = { 42, 50, 25 },
		card_visible = false,
		metrics = T,
	}, { W, H })
end

-- The blank tile at the end of the deck: a dashed outline, a plus and two lines. Clicking it creates a new card.
blueprints.blank_tile = function (node_id)
	local passes = {}
	local dash, gap = 14, 8
	local count = 0

	local function dashes(x, y, horizontal, length)
		local at = 0

		while at < length do
			count = count + 1
			rect_pass(passes, "dash_" .. count, horizontal and x + at or x, horizontal and y or y + at, horizontal and math.min(dash, length - at) or 2, horizontal and 2 or math.min(dash, length - at), 2)
			at = at + dash + gap
		end
	end

	dashes(0, 0, true, TILE_W)
	dashes(0, TILE_H - 2, true, TILE_W)
	dashes(0, 0, false, TILE_H)
	dashes(TILE_W - 2, 0, false, TILE_H)

	passes[#passes + 1] = {
		pass_type = "rect",
		style_id = "bg",
		style = { offset = { 0, 0, 1 }, size = { TILE_W, TILE_H }, color = { 0, 0, 0, 0 } },
		change_function = function (content, style)
			style.color[1] = content.hotspot.is_hover and 70 or 0
			style.color[2], style.color[3], style.color[4] = 49, 62, 42
		end,
	}
	tile_text(passes, "plus", { 0, 70, TILE_W, 60 }, "proxima_nova_bold", 54, "center", "center", 4)
	tile_text(passes, "title", { 14, 140, TILE_W - 28, 28 }, DISPLAY_FONT, 22, "center", "center", 4)
	tile_text(passes, "hint", { 20, 172, TILE_W - 40, 60 }, "proxima_nova_bold", 14, "center", "top", 4)
	Components.hotspot_pass(passes, "hotspot", { 0, 0, 6 }, { TILE_W, TILE_H })

	local text_rgb = Components.colors.muted

	for i = 1, count do
		passes[i].style.color = Components.clone_color(text_rgb)
		passes[i].style.visible = true
	end

	return UIWidget.create_definition(passes, node_id, {}, { TILE_W, TILE_H })
end

-- The weight strip above the grid: one segment per card in the draw (see Deck.strip_segments); a track behind them.
blueprints.STRIP_IDS = {}

blueprints.STRIP_HOT = {}

for i = 1, Deck.STRIP_MAX do
	blueprints.STRIP_IDS[i] = "seg_" .. i
	blueprints.STRIP_HOT[i] = "hs_" .. i
end

blueprints.strip = function (node_id)
	local passes = {}

	rect_pass(passes, "track", 0, 0, Deck.STRIP_W, Deck.STRIP_H, 0)

	for i = 1, Deck.STRIP_MAX do
		rect_pass(passes, "seg_" .. i, 0, 0, 1, Deck.STRIP_H, 1)
	end

	-- one quiet hotspot per segment (placed by the view): the pointer on a segment lights the card of that segment
	for i = 1, Deck.STRIP_MAX do
		Components.hotspot_pass(passes, blueprints.STRIP_HOT[i], { 0, 0, 6 }, { 1, Deck.STRIP_H }, nil, true)
	end

	return UIWidget.create_definition(passes, node_id, {}, { Deck.STRIP_W, Deck.STRIP_H })
end

return blueprints
