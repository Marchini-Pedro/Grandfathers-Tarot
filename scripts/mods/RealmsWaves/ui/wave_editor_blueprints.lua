-- Dynamic widget blueprints for the wave editor: the shared row, single
-- buttons, labelled steppers, scroll buttons and the popup buttons/input.
local mod = get_mod("RealmsWaves")

local UIWidget = require("scripts/managers/ui/ui_widget")
local ButtonPassTemplates = require("scripts/ui/pass_templates/button_pass_templates")
local Components = mod:io_dofile("RealmsWaves/scripts/mods/RealmsWaves/ui/wave_editor_components")

local blueprints = {}
local colors = Components.colors

-- One row serves three screens; content flags decide which parts exist:
--   show_check    checkbox (settings, modifiers)
--   show_stepper  - value +  (count in the detail screen, numbers in the settings)
--   show_share    share of total chance (unused since the Deck replaced the wave list)
--   show_action   right-hand button, label in content.hotspot_action_text
--   show_mods     "Mods" button (detail screen, where the share column is unused)
--   show_rep      second stepper: units added on every repeat tick (detail screen)
blueprints.row = function (node_id)
	local passes = {}

	passes[#passes + 1] = {
		pass_type = "texture",
		value = "content/ui/materials/backgrounds/default_square",
		style_id = "row_background",
		style = {
			size = { 1710, 46 },
			offset = { 0, 0, 0 },
			color = Components.clone_color(colors.normal),
		},
		-- highlight the whole row while the pointer is over its name/composition area
		change_function = function (content, style)
			Components.color_into(style.color, content.hotspot_name.is_hover and colors.hover or colors.normal)
		end,
	}

	Components.checkbox_passes(passes, { 10, 9, 1 }, nil, "show_check")
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
	Components.checkbox_passes(passes, { 1128, 9, 1 }, nil, "show_rep", "same", "same_selected")
	Components.hotspot_pass(passes, "hotspot_same", { 1122, 5, 2 }, { 36, 36 }, "show_rep")

	Components.text_pass(passes, "share", "share", { 1390, 0, 2 }, { 120, 46 }, 20, colors.muted, "right", "show_share")
	Components.button_passes(passes, "hotspot_mods", { 1390, 3, 2 }, { 130, 40 }, "", 18, colors.gold, "show_mods")
	Components.button_passes(passes, "hotspot_action", { 1530, 3, 2 }, { 160, 40 }, "", 20, colors.gold, "show_action")

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
		show_rep = false,
		rep_value = "",
		same_selected = false,
	}, { 1710, 46 })
end

blueprints.button = function (node_id, width)
	local passes = {}

	Components.button_passes(passes, "hotspot", { 0, 0, 0 }, { width, 44 }, "", 22)

	return UIWidget.create_definition(passes, node_id, {}, { width, 44 })
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

blueprints.scroll_button = function (node_id, label)
	local passes = {}

	Components.button_passes(passes, "hotspot", { 0, 0, 0 }, { 44, 36 }, label)

	return UIWidget.create_definition(passes, node_id, {}, { 44, 36 })
end

blueprints.popup_confirm = UIWidget.create_definition(ButtonPassTemplates.default_button, Components.POPUP_CONFIRM_NAME, {
	original_text = mod:localize("popup_ok"),
})

blueprints.popup_cancel = UIWidget.create_definition(ButtonPassTemplates.default_button, Components.POPUP_CANCEL_NAME, {
	original_text = mod:localize("popup_cancel"),
})

blueprints.popup_input = Components.popup_input_definition()

-- ------------------------------------------------------------------------------------ the Deck: card tiles
-- A card tile (228 x 262) is made of rectangles, circles, triangles, rotated squares and text, exactly like the Spread
-- HUD (ui/spread.lua draws the suit mark). Every shape starts hidden: the view writes geometry, colours and visibility
-- into the widget styles (wave_editor_view.lua, _paint_tile). The three hotspots do not overlap (a click would reach
-- both): the whole face above the state line toggles the card in or out of the draw, the state line's left part does
-- the same, its right part ("Edit") opens the card.
local Spread = mod:io_dofile("RealmsWaves/scripts/mods/RealmsWaves/ui/spread")
local Deck = mod:io_dofile("RealmsWaves/scripts/mods/RealmsWaves/ui/deck")

blueprints.Deck, blueprints.Spread = Deck, Spread

local TILE_W, TILE_H = Deck.TILE_W, Deck.TILE_H
local DISPLAY_FONT = "itc_novarese_bold"

blueprints.TILE = {
	-- boxes (x, y, w, h) inside the tile
	suit_label = { 14, 12, 150, 20 },
	icon = { 192, 10, 22, 22 },
	name = { 14, 36, 200, 52 },
	divider = { 14, 90, 200, 1 },
	comp = { 14, 96, 200, 68 },
	mods = { 14, 164, 200, 16 },
	whisper = { 14, 182, 200, 32 },
	row_y = 224, -- centre of the bottom row (threat diamonds left, dots right)
	diamonds_x = 14 + 4, -- centre of the first diamond
	dots_right = 214,
	pips_y = 236,
	pips_x = 14,
	pip = { 16, 7, 4 }, -- width, height, gap
	state_left = { 14, 246, 130, 14 },
	state_clock = { 130, 246, 84, 14 },
	hot_top = { 0, 0, TILE_W, 244 },
	hot_state = { 0, 244, 150, 18 },
	hot_edit = { 150, 244, TILE_W - 150, 18 },
	edit_label = { 150, 246, TILE_W - 150 - 14, 14 },
}

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
blueprints.TILE_IDS = { border = { "border_t", "border_b", "border_l", "border_r" }, icon_t = {}, icon_c = {}, th_o = {}, th_i = {}, dot = {}, pip = {} }

for i = 1, Spread.ICON_TRIS do
	blueprints.TILE_IDS.icon_t[i] = "icon_t" .. i
end

for i = 1, Spread.ICON_CIRCS do
	blueprints.TILE_IDS.icon_c[i] = "icon_c" .. i
end

for i = 1, 5 do
	blueprints.TILE_IDS.th_o[i], blueprints.TILE_IDS.th_i[i] = "th_o" .. i, "th_i" .. i
end

for i = 1, 6 do
	blueprints.TILE_IDS.dot[i] = "dot_" .. i
end

for i = 1, Deck.PIPS do
	blueprints.TILE_IDS.pip[i] = "pip_" .. i
end

blueprints.tile = function (node_id)
	local passes = {}
	local T = blueprints.TILE

	-- the glow (the stock frame texture) and the face
	passes[#passes + 1] = {
		pass_type = "texture",
		style_id = "glow",
		value = "content/ui/materials/frames/frame_glow_01",
		style = { scale_to_material = true, offset = { -12, -12, 0 }, size = { TILE_W + 24, TILE_H + 24 }, color = shape_color(), visible = false },
	}
	passes[#passes + 1] = {
		pass_type = "rect",
		style_id = "bg",
		style = { offset = { 0, 0, 1 }, size = { TILE_W, TILE_H }, color = shape_color() },
		-- the face takes the suit's lighter colour while the pointer is on the tile
		change_function = function (content, style)
			local hover = content.hotspot_top.is_hover or content.hotspot_state.is_hover or content.hotspot_edit.is_hover
			local rgb = hover and content.bg_hi or content.bg_rgb

			style.color[1], style.color[2], style.color[3], style.color[4] = 255, rgb[1], rgb[2], rgb[3]
		end,
	}

	rect_pass(passes, "border_t", 0, 0, TILE_W, 1, 2)
	rect_pass(passes, "border_b", 0, TILE_H - 1, TILE_W, 1, 2)
	rect_pass(passes, "border_l", 0, 0, 1, TILE_H, 2)
	rect_pass(passes, "border_r", TILE_W - 1, 0, 1, TILE_H, 2)

	for i = 1, Spread.ICON_TRIS do
		triangle_pass(passes, blueprints.TILE_IDS.icon_t[i], 4)
	end

	for i = 1, Spread.ICON_CIRCS do
		circle_pass(passes, blueprints.TILE_IDS.icon_c[i], 4)
	end

	tile_text(passes, "suit_label", T.suit_label, "proxima_nova_bold", 12, "left", "center", 4)
	tile_text(passes, "name", T.name, DISPLAY_FONT, 20, "left", "top", 5)
	rect_pass(passes, "divider", T.divider[1], T.divider[2], T.divider[3], T.divider[4], 3)
	tile_text(passes, "comp", T.comp, "proxima_nova_bold", 13, "left", "top", 4)
	tile_text(passes, "mods", T.mods, "proxima_nova_bold", 12, "left", "center", 4)
	tile_text(passes, "whisper", T.whisper, "proxima_nova_bold", 13, "left", "top", 4)

	for i = 1, 5 do
		diamond_pass(passes, blueprints.TILE_IDS.th_o[i], 4, 8)
	end

	for i = 1, 5 do
		diamond_pass(passes, blueprints.TILE_IDS.th_i[i], 5, 4.4)
	end

	for i = 1, 6 do
		circle_pass(passes, blueprints.TILE_IDS.dot[i], 4)
	end

	for i = 1, Deck.PIPS do
		rect_pass(passes, blueprints.TILE_IDS.pip[i], T.pips_x + (i - 1) * (T.pip[1] + T.pip[3]), T.pips_y, T.pip[1], T.pip[2], 4)
	end

	-- the state line: what the card is doing, the cooldown clock, and the Edit button
	tile_text(passes, "state_left", T.state_left, "proxima_nova_bold", 12, "left", "center", 4)
	tile_text(passes, "state_clock", T.state_clock, "proxima_nova_bold", 12, "right", "center", 4)
	rect_pass(passes, "edit_bg", T.hot_edit[1], T.hot_edit[2], T.hot_edit[3], T.hot_edit[4], 3)
	tile_text(passes, "edit_label", T.edit_label, "proxima_nova_bold", 12, "right", "center", 5)

	Components.hotspot_pass(passes, "hotspot_top", { T.hot_top[1], T.hot_top[2], 6 }, { T.hot_top[3], T.hot_top[4] })
	Components.hotspot_pass(passes, "hotspot_state", { T.hot_state[1], T.hot_state[2], 6 }, { T.hot_state[3], T.hot_state[4] })
	Components.hotspot_pass(passes, "hotspot_edit", { T.hot_edit[1], T.hot_edit[2], 6 }, { T.hot_edit[3], T.hot_edit[4] })

	return UIWidget.create_definition(passes, node_id, {
		bg_rgb = { 30, 36, 19 },
		bg_hi = { 42, 50, 25 },
		card_visible = false,
	}, { TILE_W, TILE_H })
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

for i = 1, Deck.STRIP_MAX do
	blueprints.STRIP_IDS[i] = "seg_" .. i
end

blueprints.strip = function (node_id)
	local passes = {}

	rect_pass(passes, "track", 0, 0, Deck.STRIP_W, Deck.STRIP_H, 0)

	for i = 1, Deck.STRIP_MAX do
		rect_pass(passes, "seg_" .. i, 0, 0, 1, Deck.STRIP_H, 1)
	end

	return UIWidget.create_definition(passes, node_id, {}, { Deck.STRIP_W, Deck.STRIP_H })
end

return blueprints
