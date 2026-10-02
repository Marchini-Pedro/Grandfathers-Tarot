-- Scenegraph and static widgets of the wave editor (1920x1080 canvas, one layout for every resolution: the engine scales it).
-- The Deck (list), the settings, the presets, the picker, Mods and Custom use a title, a table panel with a scrolling row pool
-- and a bottom panel; one row blueprint serves them. A card's own screens, the Cauldron (detail) and the Mirror (face), have
-- their own nodes and widgets (ui/workshop.lua for where things sit, docs/08-workshop-redesign.md); see wave_editor_view.lua.
local mod = get_mod("RealmsWaves")

local UIWidget = require("scripts/managers/ui/ui_widget")
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
local Components = mod:io_dofile("RealmsWaves/scripts/mods/RealmsWaves/ui/wave_editor_components")
local Workshop = mod:io_dofile("RealmsWaves/scripts/mods/RealmsWaves/ui/workshop")
local WB = mod:io_dofile("RealmsWaves/scripts/mods/RealmsWaves/ui/workshop_blueprints")

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
	title_text = node(80, 38, 800, 50, 2),
	-- the Deck (home screen): "N in the draw", the weight strip and its captions, the card tiles
	deck_count = node(890, 40, 270, 44, 2),
	deck_strip = node(105, 144, 1710, 14, 1),
	deck_caption = node(105, 162, 800, 22, 2),
	deck_hover = node(1015, 162, 800, 22, 2),
	description_text = node(80, 95, 1700, 40, 2),
	list_panel = node(105, 160, 1710, 580, 0),
	list_header = node(105, 168, 1710, 28, 1),
	scroll_up = node(1771, 168, 44, 36, 2),
	scroll_down = node(1771, 696, 44, 36, 2),
	list_range = node(1400, 700, 340, 28, 2),
	-- Bottom panel: a title line, one row of buttons (y 800) and up to three rows of steppers (858, 910, 962).
	-- Rows are 52 px apart; the panel ends at 1030 so the last stepper row stays above the input legend.
	bottom_panel = node(105, 750, 1710, 280, 0),
	bottom_title = node(125, 758, 900, 34, 2),
	hint_text = node(125, 852, 1660, 120, 2), -- below the button row (800)

	btn_back = node(125, 800, 180, 44, 2),
	btn_search = node(325, 800, 420, 44, 2), -- enemy picker only (same spot as Rename)
	btn_stay = node(765, 800, 380, 44, 2), -- enemy picker only: stay after adding / back to the wave
	btn_random = node(1165, 800, 310, 44, 2), -- enemy picker only: collect several enemies into ONE random group
	btn_random_done = node(1495, 800, 290, 44, 2), -- ...and create it
	btn_rename = node(325, 800, 200, 44, 2),
	btn_text = node(545, 800, 250, 44, 2),
	btn_add = node(815, 800, 230, 44, 2),
	btn_enabled = node(1065, 800, 260, 44, 2),
	btn_reset = node(1345, 800, 300, 44, 2),
	-- presets: list screen button (where Back sits on the other screens), and one preset's actions in two rows
	-- NOT under Back (x 125-305): Back is drawn before this button, so a click on Back that switches to the
	-- list would land on a Presets button at the same spot in the same frame and open the presets page.
	btn_presets = node(1170, 36, 290, 44, 2), -- header of the Deck ("Spreads"); the Back button is not on that screen
	-- corner buttons, top right (the title text ends at x 1280): "More options" (list screen only) and the
	-- help icon whose tooltip replaces the long gray texts that used to fill the bottom of the screen
	btn_settings = node(1480, 36, 270, 44, 2),
	btn_help = node(1766, 36, 50, 44, 2),
	btn_face = node(1480, 36, 270, 44, 2), -- a card's own screen: its face (suit, threat, whisper, look); same spot as More options, which is list-only
	-- the card face screen: "Threat N by the numbers" under the rows, the live preview of the tile in the bottom right
	help_panel = node(880, 90, 935, 300, 70),
	help_text = node(900, 100, 895, 280, 71),
	btn_wimport = node(645, 800, 300, 44, 2), -- list screen: import a shared wave into the first free custom slot
	btn_default = node(965, 800, 320, 44, 2), -- list screen: restore every wave to the defaults
	-- list screen: the time between waves (the options menu has the same two settings)
	stepper_tmin = node(125, 858, 700, 48, 2),
	stepper_tmax = node(870, 858, 700, 48, 2),
	-- detail screen: export this wave / import over it. Top right of the panel, beside the title line (the
	-- steppers need every pixel of the three rows below)
	btn_share = node(1520, 752, 280, 44, 2),
	btn_pload = node(325, 800, 250, 44, 2),
	btn_psave = node(595, 800, 400, 44, 2),
	btn_prename = node(1015, 800, 200, 44, 2),
	btn_pexport = node(1235, 800, 220, 44, 2),
	btn_pimport = node(1475, 800, 220, 44, 2),
	btn_delete = node(1660, 800, 155, 44, 2), -- detail screen: delete the card (second click: Sure?)
	btn_pundo = node(125, 858, 380, 44, 2),
	btn_pclear = node(525, 858, 260, 44, 2),
	stepper_chance = node(125, 858, 860, 48, 2),
	stepper_cooldown = node(1000, 858, 800, 48, 2),
	stepper_spread = node(125, 910, 480, 48, 2),
	stepper_every = node(640, 910, 640, 48, 2),
	stepper_for = node(1300, 910, 515, 48, 2),
	stepper_dmin = node(125, 962, 540, 48, 2),
	stepper_dmax = node(680, 962, 540, 48, 2),
	stepper_timer = node(1235, 962, 580, 48, 2), -- fixed timer: this wave ignores its chance and spawns every N seconds
	-- input popup, centred
	rw_popup_panel = node(560, 400, 800, 260, 45),
	rw_popup_input = node(600, 470, 720, 46, 50),
	-- OK and Cancel are the mod's own buttons (Components.button), 200 x 48, on the right of the panel
	rw_popup_confirm = node(1130, 596, 200, 48, 50),
	rw_popup_cancel = node(910, 596, 200, 48, 50),
}

for i = 1, definitions.LIST_CAPACITY do
	scenegraph_definition[definitions.ROW_NODE_PREFIX .. i] = node(105, definitions.LIST_TOP + (i - 1) * definitions.ROW_HEIGHT, 1710, 46, 1)
end

-- the Deck: 14 card tiles (7 columns, 2 rows; the view moves them) and the blank tile that makes a new card
definitions.TILE_CAPACITY = 14
definitions.TILE_NODE_PREFIX = "rw_tile_"
definitions.TILE_BLANK_NODE = "rw_tile_blank"

for i = 1, definitions.TILE_CAPACITY do
	scenegraph_definition[definitions.TILE_NODE_PREFIX .. i] = node(126, 190, 228, 270, 3)
end

scenegraph_definition[definitions.TILE_BLANK_NODE] = node(126, 190, 228, 270, 3)

-- ---- the Workshop (docs/08-workshop-redesign.md): the card's own screens. Where everything sits comes from ui/workshop.lua;
-- the nodes of the buttons that only the Cauldron uses are placed here, the ones other screens share (Back, the scroll
-- buttons, the summary line) are moved by the view while a screen is shown.
local shelf = Workshop.shelf_layout(mod.rw.groups.SHELF, mod.rw.groups)
local under = Workshop.under_shelf(shelf.height)
local LX, SY, P = Workshop.LEFT_X, Workshop.SHELF_Y, Workshop.PLATE

definitions.shelf_layout, definitions.under_shelf = shelf, under
definitions.ERROW_NODE_PREFIX, definitions.CHIP_NODE_PREFIX, definitions.SUIT_NODE_PREFIX = "rw_erow_", "rw_chip_", "rw_suit_"
definitions.STAGE_CARD_NODE = "rw_stage_card"

-- header: the tabs
scenegraph_definition.btn_enemies = node(1478, 36, 150, 44, 2)
scenegraph_definition.btn_face = node(1628, 36, 124, 44, 2)

-- left pane: the rows, the shelf, the spawn block, the action bar
scenegraph_definition.enemy_header = node(LX, Workshop.HEADER_Y, Workshop.LEFT_W, Workshop.HEADER_H, 2)

for i = 1, Workshop.ROWS do
	scenegraph_definition[definitions.ERROW_NODE_PREFIX .. i] = node(LX, Workshop.row_y(i), Workshop.LEFT_W, Workshop.ROW_H, 1)
end

scenegraph_definition.shelf_panel = node(LX, SY, Workshop.LEFT_W, shelf.height, 0)
scenegraph_definition.btn_add = node(LX + 889, SY + 6, 230, 44, 3)
scenegraph_definition.btn_dreg = node(LX + 712, SY + 10, 80, 36, 3)
scenegraph_definition.btn_scab = node(LX + 792, SY + 10, 80, 36, 3)

for i = 1, #shelf.chips do
	local chip = shelf.chips[i]

	scenegraph_definition[definitions.CHIP_NODE_PREFIX .. i] = node(LX + chip.x, SY + chip.y, chip.w, Workshop.CHIP_H, 3)
end

scenegraph_definition.spawn_label = node(LX, under.label_y, 600, 22, 2)
scenegraph_definition.btn_keep_pick = node(LX + Workshop.LEFT_W - 360, under.label_y - 10, 360, 30, 2)

for i, name in ipairs(Workshop.SPAWN_ORDER) do
	local x, y = Workshop.spawn_pos(i, under.row_y)

	scenegraph_definition[name] = node(x, y, Workshop.SPAWN_W, 48, 2)
end

scenegraph_definition.btn_rename = node(297, under.actions_y, 150, 44, 2)
scenegraph_definition.btn_text = node(459, under.actions_y, 190, 44, 2)
scenegraph_definition.btn_share = node(661, under.actions_y, 190, 44, 2)
scenegraph_definition.btn_reset = node(868, under.actions_y, 230, 44, 2)
scenegraph_definition.btn_delete = node(1110, under.actions_y, 130, 44, 2)

-- right pane: the stage, the toolbar, the quick face
local card_w, card_h = 228 * Workshop.CARD_SCALE, 270 * Workshop.CARD_SCALE
local card_x, card_y = Workshop.card_pos(card_w)

scenegraph_definition.stage_caption = node(P.x, Workshop.CAPTION_Y, P.w, 28, 2)
scenegraph_definition.stage_plate = node(P.x, P.y, P.w, P.h, 0)
scenegraph_definition[definitions.STAGE_CARD_NODE] = node(card_x, card_y, card_w, card_h, 3)
scenegraph_definition.stage_stats = node(P.x, Workshop.STATS_Y, P.w, 28, 4)
scenegraph_definition.btn_enabled = node(P.x, Workshop.TOOLBAR_Y, 230, 44, 2)
scenegraph_definition.btn_preview = node(P.x + 242, Workshop.TOOLBAR_Y, 283, 44, 2)
scenegraph_definition.quick_label = node(P.x, Workshop.QUICK_Y, 200, 28, 2)
scenegraph_definition.btn_quickface = node(P.x + P.w - 250, Workshop.QUICK_Y - 4, 250, 36, 2)

for i = 1, 12 do
	local x, y = Workshop.suit_pos(i)

	scenegraph_definition[definitions.SUIT_NODE_PREFIX .. i] = node(x, y, Workshop.SUIT_W, Workshop.SUIT_H, 3)
end

scenegraph_definition.threat_label = node(P.x, Workshop.THREAT_Y, Workshop.ROW_LABEL_W, 44, 2)
scenegraph_definition.rw_threat = node(Workshop.THREAT_X, Workshop.THREAT_Y, 5 * Workshop.THREAT_PITCH, 44, 2)
scenegraph_definition.btn_thr_auto = node(Workshop.THREAT_X + 5 * Workshop.THREAT_PITCH + 12, Workshop.THREAT_Y + 4, 76, 36, 2)
scenegraph_definition.btn_thr_hand = node(Workshop.THREAT_X + 5 * Workshop.THREAT_PITCH + 12 + 76, Workshop.THREAT_Y + 4, 100, 36, 2)
scenegraph_definition.stepper_chance = node(P.x, Workshop.CHANCE_Y, P.w, 48, 2)

-- ---- the Mirror (the card face screen): four sections on the left, the stage of the Cauldron on the right
local M = Workshop.MIRROR

definitions.PLATE_NODE_PREFIX, definitions.LOOK_NODE_PREFIX = "rw_plate_", "rw_look_"
definitions.MIRROR_LOOKS = { "rot", "whisper", "vial" }

for i = 1, 4 do
	scenegraph_definition["mirror_head_" .. i] = node(LX, M.head[i], Workshop.LEFT_W, M.head_h, 2)
end

scenegraph_definition.mirror_desc = node(LX, M.desc_y, Workshop.LEFT_W, M.desc_h, 2)

for i = 1, 12 do
	local x, y = Workshop.plate_pos(i)

	scenegraph_definition[definitions.PLATE_NODE_PREFIX .. i] = node(x, y, M.plate.w, M.plate.h, 3)
end

scenegraph_definition.rw_threat_big = node(LX, M.threat_y, 5 * M.threat_pitch, M.threat_h, 2)
scenegraph_definition.mirror_numbers = node(LX + 5 * M.threat_pitch + 12 + 76 + 100 + 24, M.threat_y, Workshop.LEFT_W - (5 * M.threat_pitch + 12 + 76 + 100 + 24), M.threat_h, 2)
scenegraph_definition.whisper_field = node(LX, M.whisper_y, M.whisper_w, M.whisper_h, 2)
scenegraph_definition.btn_whisper_change = node(LX + M.whisper_w + 12, M.whisper_y, 150, 44, 2)
scenegraph_definition.btn_whisper_suit = node(LX + M.whisper_w + 12 + 150 + 12, M.whisper_y + 4, Workshop.LEFT_W - (M.whisper_w + 12 + 150 + 12), 36, 2)
scenegraph_definition.stepper_cooldown = node(LX, M.cooldown_y, 700, 48, 2)

for i = 1, 3 do
	local x, y = Workshop.look_pos(i)

	scenegraph_definition[definitions.LOOK_NODE_PREFIX .. i] = node(x, y, M.look.w, M.look.h, 3)
end

scenegraph_definition.btn_look_auto = node(LX, M.auto_y, 330, M.auto_h, 2)
scenegraph_definition.hand_caption = node(Workshop.HAND.x, Workshop.HAND.caption_y, P.w, 28, 2)
scenegraph_definition.rw_hand_card = node(Workshop.HAND.x, Workshop.HAND.y, Workshop.HAND.w, Workshop.HAND.max_h, 2)
scenegraph_definition.btn_reset_face = node(1070, under.actions_y, 170, 44, 2)

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

-- the frames of the tooltip and of the input popup: four rects in the accent, the popup with the two corner brackets
local help_frame, popup_frame = {}, {}

Components.frame_passes(help_frame, "frame", 935, 300, 1)
Components.frame_passes(popup_frame, "frame", 800, 260, 1, { brackets = true })

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
			style = (function ()
				local style = table.clone(UIFontSettings.header_1)

				style.text_color = Components.clone_color(colors.title)

				return style
			end)(),
		},
	}, "title_text"),

	deck_count = plain_text("deck_count", "deck_count", 20, colors.muted, 270, 44, "right"),
	deck_caption = plain_text("deck_caption", "deck_caption", 15, colors.muted, 800, 22, "left"),
	deck_hover = plain_text("deck_hover", "deck_hover", 15, colors.text, 800, 22, "right"),

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

	-- the Workshop's static widgets (shown by the view only while the Cauldron is)
	enemy_header = UIWidget.create_definition({
		header_pass("col_1", Workshop.COL.name, 300),
		header_pass("col_2", Workshop.COL.weight, 136, "center"),
		header_pass("col_3", Workshop.COL.repeat_ - 30, 196, "center"),
		header_pass("col_4", Workshop.COL.same - 40, 80, "center"),
	}, "enemy_header"),
	shelf_panel = WB.shelf_panel("shelf_panel", shelf),
	stage_plate = WB.stage_plate("stage_plate"),
	stage_caption = plain_text("stage_caption", "stage_caption", 16, colors.text, P.w, 28, "left"),
	stage_stats = plain_text("stage_stats", "stage_stats", 18, colors.muted, P.w, 28, "center"),
	quick_label = plain_text("quick_label", "quick_label", 16, colors.text, 200, 28, "left"),
	threat_label = plain_text("threat_label", "threat_label", 16, colors.muted, Workshop.ROW_LABEL_W, 44, "left"),
	spawn_label = plain_text("spawn_label", "spawn_label", 16, colors.muted, 600, 22, "left"),

	-- the Mirror's static widgets: the section headers, the suit's description, the threat sum
	mirror_head_1 = WB.section_head("mirror_head_1"),
	mirror_head_2 = WB.section_head("mirror_head_2"),
	mirror_head_3 = WB.section_head("mirror_head_3"),
	mirror_head_4 = WB.section_head("mirror_head_4"),
	hand_caption = plain_text("hand_caption", "hand_caption", 16, colors.text, P.w, 28, "left"),
	mirror_desc = plain_text("mirror_desc", "mirror_desc", 20, colors.muted, Workshop.LEFT_W, M.desc_h, "left", "top"),
	mirror_numbers = plain_text("mirror_numbers", "mirror_numbers", 19, colors.muted, Workshop.LEFT_W - (5 * M.threat_pitch + 12 + 76 + 100 + 24), M.threat_h, "left", "center"),

	bottom_panel = UIWidget.create_definition({
		{ pass_type = "rect", style = { color = Components.clone_color(colors.panel) } },
	}, "bottom_panel"),

	bottom_title = plain_text("bottom_title", "bottom_title", 24, colors.gold, 900, 34),
	hint_text = plain_text("hint_text", "hint_text", 20, colors.muted, 1660, 120, "left", "top"),

	-- tooltip shown while the pointer is on the "?" corner button
	help_panel = UIWidget.create_definition({
		{ pass_type = "rect", style = { color = { 245, 15, 23, 19 } } },
		unpack(help_frame),
	}, "help_panel"),
	help_text = plain_text("help_text", "help_text", 20, colors.text, 895, 280, "left", "top"),

	-- input popup: fill, gold frame, title and hint (input and buttons are dynamic)
	rw_popup_panel = UIWidget.create_definition({
		{ pass_type = "rect", style = { color = { 245, 15, 23, 19 } } },
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
				offset = { 20, 130, 2 },
				word_wrap = true,
			},
		},
		unpack(popup_frame),
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
