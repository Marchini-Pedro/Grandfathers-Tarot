-- Definitions for Dream's sky (2026-10-05): a full-screen overlay drawn on the root node "screen" (like the Nightmare's dread, which it
-- mirrors in light). One widget: a pastel veil over the whole screen, rays of light falling from the top (rotated rects), banks of
-- clouds along the foot and the head of the screen (circles, two of each puff: a soft outer one and a brighter heart), a frame of
-- light at the edges in the colours of a rainbow (a stepped vignette: the UI has no gradient), stars that twinkle and drift up, and the
-- bloom of light that opens from the middle when the card is drawn. Every pass starts hidden; hud_element_dream.lua writes them
-- every frame while the sky lasts.
local mod = get_mod("GrandfathersTarot")

local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")

local definitions = {}

definitions.W, definitions.H = 1920, 1080
definitions.VIGNETTE_STEPS = 12
definitions.VIGNETTE_STEP = 14
definitions.RAYS = 7
definitions.CLOUDS_FOOT = 14
definitions.CLOUDS_HEAD = 9
definitions.STARS = 28
definitions.BLOOM_RINGS = 3

local function pass(passes, kind, id, z)
	passes[#passes + 1] = { pass_type = kind, style_id = id, style = { offset = { 0, 0, z }, size = { 1, 1 }, color = { 0, 255, 255, 255 }, visible = false } }

	return passes[#passes].style
end

local passes = {}

pass(passes, "rect", "veil", 1)

for i = 1, definitions.RAYS do
	local style = pass(passes, "rotated_rect", "ray_" .. i, 2)

	style.angle, style.pivot = 0, { 0, 0 }
end

for i = 1, definitions.CLOUDS_FOOT + definitions.CLOUDS_HEAD do
	pass(passes, "circle", "cloud_" .. i, 3)
	pass(passes, "circle", "cloud_heart_" .. i, 4) -- (whole layers: a circle is drawn on the whole layer under its z)
end

for j = 1, definitions.VIGNETTE_STEPS do
	for _, side in ipairs({ "t", "b", "l", "r" }) do
		pass(passes, "rect", "vig_" .. j .. "_" .. side, 5)
	end
end

for i = 1, definitions.STARS do
	pass(passes, "rect", "star_h_" .. i, 6)
	pass(passes, "rect", "star_v_" .. i, 6)
end

for i = 1, definitions.BLOOM_RINGS do
	pass(passes, "circle", "bloom_" .. i, 7)
end

definitions.scenegraph_definition = { screen = UIWorkspaceSettings.screen }
definitions.widget_definitions = { dream = UIWidget.create_definition(passes, "screen") }

return definitions
