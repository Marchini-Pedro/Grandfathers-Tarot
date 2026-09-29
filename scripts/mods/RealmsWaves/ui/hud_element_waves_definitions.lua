-- Definitions for the wave panel: one full-screen node holding LINES text
-- passes. Position, text and colour are written into the widget by
-- hud_element_waves.lua whenever the synced state changes.
--
-- Font names must be exact; an unknown one crashes the renderer mid-draw.
local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")

local definitions = {}

definitions.SCREEN_WIDTH = 1920
definitions.SCREEN_HEIGHT = 1080
definitions.LINES = 7 -- header + up to 5 candidates + key hint
definitions.LINE_HEIGHT = 30
definitions.FONT = "proxima_nova_bold"

-- The "panel" node is the box the custom_hud mod lets the player drag around
-- (it lists every non-root scenegraph node of a registered HUD element), so it
-- has the real size of the text block. All text is positioned inside it.
definitions.PANEL_WIDTH = 640
definitions.PANEL_HEIGHT = definitions.LINES * definitions.LINE_HEIGHT

local scenegraph_definition = {
	screen = UIWorkspaceSettings.screen,

	panel = {
		parent = "screen",
		vertical_alignment = "top",
		horizontal_alignment = "left",
		size = { definitions.PANEL_WIDTH, definitions.PANEL_HEIGHT },
		position = { 40, 330, 50 },
	},
}

local passes = {}

for i = 0, definitions.LINES - 1 do
	passes[#passes + 1] = {
		pass_type = "text",
		style_id = "line_" .. i,
		value_id = "line_" .. i,
		value = "",
		style = {
			font_type = definitions.FONT,
			font_size = i == 0 and 26 or 22,
			text_color = { 255, 255, 255, 255 },
			offset = { 0, i * definitions.LINE_HEIGHT, 5 },
			text_horizontal_alignment = "left",
			text_vertical_alignment = "top",
			size = { definitions.PANEL_WIDTH, definitions.LINE_HEIGHT },
			drop_shadow = true,
		},
	}
end

definitions.scenegraph_definition = scenegraph_definition
definitions.widget_definitions = {
	panel = UIWidget.create_definition(passes, "panel"),
}

return definitions
