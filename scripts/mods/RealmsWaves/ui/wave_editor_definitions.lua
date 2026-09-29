-- Scenegraph and static widgets of the wave editor (1920x1080 canvas).
-- Layout follows RealmsEvent's editor: title, list panel with a scrolling row
-- pool, bottom panel with actions. One row blueprint serves three screens
-- (wave list, wave detail, enemy picker); see wave_editor_view.lua.
local mod = get_mod("RealmsWaves")

local UIWidget = require("scripts/managers/ui/ui_widget")
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
local Components = mod:io_dofile("RealmsWaves/scripts/mods/RealmsWaves/ui/wave_editor_components")

local definitions = {}

definitions.LIST_CAPACITY = 10
definitions.LIST_TOP = 205
definitions.ROW_HEIGHT = 50
definitions.ROW_NODE_PREFIX = "rw_row_"

local colors = Components.colors

local function node(x, y, w, h, z)
	return {
		parent = "screen",
		vertical_alignment = "top",
		horizontal_alignment = "left",
		size = { w, h },
		position = { x, y, z or 1 },
	}
end

local scenegraph_definition = {
	screen = {
		scale = "fit",
		size = { 1920, 1080 },
		position = { 0, 0, 80 },
	},
	title_text = node(80, 38, 1200, 50, 2),
	description_text = node(80, 95, 1700, 40, 2),
	list_panel = node(105, 160, 1710, 580, 0),
	list_header = node(105, 168, 1710, 28, 1),
	scroll_up = node(1771, 168, 44, 36, 2),
	scroll_down = node(1771, 696, 44, 36, 2),
	list_range = node(1400, 700, 340, 28, 2),
	bottom_panel = node(105, 770, 1710, 250, 0),
	bottom_title = node(125, 780, 900, 34, 2),
	hint_text = node(125, 885, 1660, 120, 2), -- below the button row (826)

	btn_back = node(125, 826, 180, 44, 2),
	btn_search = node(325, 826, 420, 44, 2), -- enemy picker only (same spot as Rename)
	btn_stay = node(765, 826, 560, 44, 2), -- enemy picker only: stay after adding / back to the wave
	btn_rename = node(325, 826, 200, 44, 2),
	btn_text = node(545, 826, 250, 44, 2),
	btn_add = node(815, 826, 230, 44, 2),
	btn_enabled = node(1065, 826, 260, 44, 2),
	btn_reset = node(1345, 826, 300, 44, 2),
	-- presets: list screen button (where Back sits on the other screens), and one preset's actions in two rows
	btn_presets = node(125, 826, 300, 44, 2),
	btn_pload = node(325, 826, 250, 44, 2),
	btn_psave = node(595, 826, 400, 44, 2),
	btn_prename = node(1015, 826, 200, 44, 2),
	btn_pexport = node(1235, 826, 220, 44, 2),
	btn_pimport = node(1475, 826, 220, 44, 2),
	btn_pundo = node(125, 890, 380, 44, 2),
	btn_pclear = node(525, 890, 260, 44, 2),
	stepper_chance = node(125, 890, 900, 48, 2),
	stepper_cooldown = node(1000, 890, 800, 48, 2),
	stepper_spread = node(125, 945, 480, 48, 2),
	stepper_every = node(640, 945, 640, 48, 2),
	stepper_for = node(1300, 945, 515, 48, 2),

	-- input popup, centred
	rw_popup_panel = node(560, 400, 800, 260, 45),
	rw_popup_input = node(600, 470, 720, 46, 50),
	-- The vanilla button template draws big ornamental side frames inside its box, so the box must
	-- be wide (the clickable/visible inner rectangle is roughly the width minus ~120 px).
	rw_popup_confirm = node(600, 600, 240, 56, 50),
	rw_popup_cancel = node(870, 600, 240, 56, 50),
}

for i = 1, definitions.LIST_CAPACITY do
	scenegraph_definition[definitions.ROW_NODE_PREFIX .. i] = node(105, definitions.LIST_TOP + (i - 1) * definitions.ROW_HEIGHT, 1710, 46, 1)
end

local function header_pass(id, x, w, align)
	return {
		value_id = id,
		style_id = id,
		pass_type = "text",
		value = "",
		style = {
			font_type = "proxima_nova_bold",
			font_size = 18,
			text_color = Components.clone_color(colors.muted),
			text_horizontal_alignment = align or "left",
			text_vertical_alignment = "center",
			size = { w, 28 },
			offset = { x, 0, 2 },
		},
	}
end

local function plain_text(node_id, value_id, font_size, color, w, h, align, valign)
	return UIWidget.create_definition({
		{
			value_id = value_id,
			style_id = value_id,
			pass_type = "text",
			value = "",
			style = {
				font_type = "proxima_nova_bold",
				font_size = font_size,
				text_color = Components.clone_color(color),
				text_horizontal_alignment = align or "left",
				text_vertical_alignment = valign or "center",
				size = { w, h },
				offset = { 0, 0, 2 },
				word_wrap = true,
			},
		},
	}, node_id)
end

local widget_definitions = {
	background = UIWidget.create_definition({
		{
			value = "content/ui/materials/backgrounds/terminal_basic",
			pass_type = "texture",
			style = {
				horizontal_alignment = "center",
				scale_to_material = true,
				vertical_alignment = "center",
				size_addition = { 40, 40 },
				offset = { -20, -20, 1 },
				color = Components.clone_color({ 255, 30, 32, 28 }),
			},
		},
		{
			pass_type = "rect",
			style = { color = { 255, 0, 0, 0 } },
			offset = { 0, 0, 0 },
		},
	}, "screen"),

	title_text = UIWidget.create_definition({
		{
			value_id = "title_text",
			style_id = "title_text",
			pass_type = "text",
			value = "",
			style = table.clone(UIFontSettings.header_1),
		},
	}, "title_text"),

	description_text = UIWidget.create_definition({
		{
			value_id = "description_text",
			style_id = "description_text",
			pass_type = "text",
			value = "",
			style = table.clone(UIFontSettings.header_5),
		},
	}, "description_text"),

	list_panel = UIWidget.create_definition({
		{ pass_type = "rect", style = { color = Components.clone_color(colors.panel) } },
	}, "list_panel"),

	list_header = UIWidget.create_definition({
		header_pass("col_1", 8, 60),
		header_pass("col_2", 60, 480),
		header_pass("col_3", 550, 640),
		header_pass("col_4", 1200, 190, "center"),
		header_pass("col_5", 1390, 120, "right"),
		header_pass("col_6", 890, 210, "center"),
		header_pass("col_7", 1110, 100, "center"),
	}, "list_header"),

	list_range = plain_text("list_range", "list_range", 18, colors.muted, 340, 28, "right"),

	bottom_panel = UIWidget.create_definition({
		{ pass_type = "rect", style = { color = Components.clone_color(colors.panel) } },
	}, "bottom_panel"),

	bottom_title = plain_text("bottom_title", "bottom_title", 24, colors.gold, 900, 34),
	hint_text = plain_text("hint_text", "hint_text", 20, colors.muted, 1660, 120, "left", "top"),

	-- input popup: fill, gold frame, title and hint (input and buttons are dynamic)
	rw_popup_panel = UIWidget.create_definition({
		{ pass_type = "rect", style = { color = { 245, 15, 23, 19 } } },
		{
			style_id = "frame",
			pass_type = "texture",
			value = "content/ui/materials/frames/frame_tile_2px",
			style = {
				scale_to_material = true,
				color = Components.clone_color(colors.gold),
				offset = { 0, 0, 1 },
			},
		},
		{
			value_id = "title_text",
			style_id = "title_text",
			pass_type = "text",
			value = "",
			style = {
				font_type = "proxima_nova_bold",
				font_size = 22,
				text_color = Components.clone_color(colors.gold),
				text_horizontal_alignment = "left",
				text_vertical_alignment = "center",
				size = { 760, 40 },
				offset = { 20, 12, 2 },
			},
		},
		{
			value_id = "hint_text",
			style_id = "hint_text",
			pass_type = "text",
			value = "",
			style = {
				font_type = "proxima_nova_bold",
				font_size = 18,
				text_color = Components.clone_color(colors.muted),
				text_horizontal_alignment = "left",
				text_vertical_alignment = "top",
				size = { 760, 60 },
				offset = { 20, 150, 2 },
				word_wrap = true,
			},
		},
	}, Components.POPUP_PANEL_NAME),
}

definitions.legend_inputs = {
	{
		input_action = "back",
		on_pressed_callback = "_on_back_pressed",
		display_name = "loc_class_selection_button_back",
		alignment = "left_alignment",
	},
}

definitions.scenegraph_definition = scenegraph_definition
definitions.widget_definitions = widget_definitions

return definitions
