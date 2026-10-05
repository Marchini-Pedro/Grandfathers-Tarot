-- Definitions for the Nightmare's dread (2026-10-04): a full-screen overlay drawn on the root node "screen" (custom_hud lists only the
-- nodes under the root, so it offers nothing to move). One widget of rectangles: a black veil over the whole screen, darker frames
-- toward the edges (a stepped vignette: the UI has no gradient), and banks of ash-grey fog that drift across. Every pass starts
-- hidden; hud_element_dread.lua writes the alphas and the fog's places every frame while the dread lasts.
local mod = get_mod("GrandfathersTarot")

local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")

local definitions = {}

definitions.W, definitions.H = 1920, 1080
definitions.VIGNETTE_STEPS = 16 -- nested frames from the edge inward, each VIGNETTE_STEP wide (thin, so the steps do not show)
definitions.VIGNETTE_STEP = 15
definitions.FOG_BANKS = 4
definitions.FOG_HEIGHT = 300
definitions.FOG_LAYERS = { 1, 0.62, 0.3 } -- a bank is three layers stacked, full, 62 and 30 percent high: its edges feather

local function rect(passes, id, z)
	passes[#passes + 1] = { pass_type = "rect", style_id = id, style = { offset = { 0, 0, z }, size = { 1, 1 }, color = { 0, 0, 0, 0 }, visible = false } }
end

local passes = {}

rect(passes, "veil", 1)

for i = 1, definitions.FOG_BANKS do
	for l = 1, #definitions.FOG_LAYERS do
		rect(passes, "fog_" .. i .. "_" .. l, 2)
	end
end

for j = 1, definitions.VIGNETTE_STEPS do
	for _, side in ipairs({ "t", "b", "l", "r" }) do
		rect(passes, "vig_" .. j .. "_" .. side, 3)
	end
end

definitions.scenegraph_definition = { screen = UIWorkspaceSettings.screen }
definitions.widget_definitions = { dread = UIWidget.create_definition(passes, "screen") }

return definitions
