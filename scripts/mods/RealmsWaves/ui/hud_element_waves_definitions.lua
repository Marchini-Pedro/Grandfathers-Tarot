-- Definitions for the wave HUD: ONE scenegraph node ("panel", the box the custom_hud mod lets the player drag around;
-- it lists every non-root node, so there must be only one) and several widgets drawn inside it:
--   legacy    the old text panel, still used by the Random countdown and Votes modes
--   header    "Card revealed in m:ss" / "Next card in m:ss" and the fuse
--   card_1..5 one card of the Spread (shapes only: rectangles, circles, triangles, rotated squares, a glow texture, text)
--   fx        what rots the picked card: a wash, blotches, flies, drips
--   banner    "THE CARD IS DRAWN", the card's name, its whisper and modifiers
-- Every pass starts hidden; hud_element_waves.lua writes geometry, colours and visibility into the widget styles when
-- the hand changes, and only the winner's passes are touched while it animates.
--
-- Font names must be exact; an unknown one crashes the renderer mid-draw.
local mod = get_mod("RealmsWaves")

local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")
local Spread = mod:io_dofile("RealmsWaves/scripts/mods/RealmsWaves/ui/spread")

local definitions = {}

definitions.Spread = Spread
definitions.SCREEN_WIDTH = 1920
definitions.SCREEN_HEIGHT = 1080
definitions.LINES = 7 -- legacy panel: header + up to 5 candidates + key hint
definitions.LINE_HEIGHT = 30
definitions.FONT = "proxima_nova_bold"
-- the default font of the Spread's text (the player can choose another one in the options, see hud_element_waves.lua)
definitions.DISPLAY_FONT = "itc_novarese_bold"

definitions.PANEL_WIDTH = Spread.NODE_WIDTH
definitions.PANEL_HEIGHT = Spread.NODE_HEIGHT

-- layers (the passes of one widget are ordered by their z offset, widgets by theirs)
definitions.Z = { header = 10, card = 20, fx = 70, banner = 100 }

local scenegraph_definition = {
	screen = UIWorkspaceSettings.screen,

	panel = {
		parent = "screen",
		vertical_alignment = "top",
		-- top-left basis: that is what the custom_hud mod pins nodes on, so its edit box sits exactly on the HUD. The x
		-- puts the 700 wide node in the middle of the 1920 wide screen.
		horizontal_alignment = "left",
		size = { definitions.PANEL_WIDTH, definitions.PANEL_HEIGHT },
		position = { 610, 36, 50 },
	},
}

-- ------------------------------------------------------------------------------------------- pass helpers
local function color()
	return { 255, 255, 255, 255 }
end

local function rect(passes, id, z)
	passes[#passes + 1] = { pass_type = "rect", style_id = id, style = { offset = { 0, 0, z }, size = { 1, 1 }, color = color(), visible = false } }
end

local function circle(passes, id, z)
	passes[#passes + 1] = { pass_type = "circle", style_id = id, style = { offset = { 0, 0, z }, size = { 1, 1 }, color = color(), visible = false } }
end

local function triangle(passes, id, z)
	passes[#passes + 1] = {
		pass_type = "triangle",
		style_id = id,
		style = { offset = { 0, 0, z }, color = color(), triangle_corners = { { 0, 0 }, { 0, 0 }, { 0, 0 } }, visible = false },
	}
end

local function diamond(passes, id, z, side)
	passes[#passes + 1] = {
		pass_type = "rotated_rect",
		style_id = id,
		style = { offset = { 0, 0, z }, size = { side, side }, color = color(), angle = math.pi / 4, pivot = { side / 2, side / 2 }, visible = false },
	}
end

local function text(passes, id, z, font, size, horizontal, vertical, shadow, display)
	passes[#passes + 1] = {
		pass_type = "text",
		style_id = id,
		value_id = id,
		value = "",
		style = {
			font_type = font,
			font_size = size,
			text_color = color(),
			offset = { 0, 0, z },
			size = { 100, size + 6 },
			text_horizontal_alignment = horizontal or "left",
			text_vertical_alignment = vertical or "top",
			drop_shadow = shadow ~= false, -- off on the cards: a shadow on a dark card only muddies thin strokes
			display = display, -- the font option changes the texts flagged like this (card names, countdown, banner name)
			visible = false,
		},
	}
end

-- ------------------------------------------------------------------------------------------- legacy panel
local legacy_passes = {}

for i = 0, definitions.LINES - 1 do
	legacy_passes[#legacy_passes + 1] = {
		pass_type = "text",
		style_id = "line_" .. i,
		value_id = "line_" .. i,
		value = "",
		style = {
			font_type = definitions.FONT,
			font_size = i == 0 and 26 or 22,
			text_color = { 255, 255, 255, 255 },
			offset = { 0, i * definitions.LINE_HEIGHT, 5 },
			text_horizontal_alignment = "center",
			text_vertical_alignment = "top",
			size = { definitions.PANEL_WIDTH, definitions.LINE_HEIGHT },
			drop_shadow = true,
		},
	}
end

-- ---------------------------------------------------------------------------------------------- header
local header_passes = {}
local zh = definitions.Z.header

text(header_passes, "label", zh, definitions.FONT, 18, "right", "center")
text(header_passes, "time", zh, definitions.DISPLAY_FONT, 24, "left", "center", true, true)
text(header_passes, "status", zh, definitions.FONT, 20, "center", "center")
rect(header_passes, "fuse_track", zh)
rect(header_passes, "fuse_fill", zh + 1)

-- ------------------------------------------------------------------------------------------------ cards
definitions.THREAT_MAX = 6
definitions.DOTS_MAX = 6 -- the most dots a card shows (catalog/cards.lua MAX_DOTS)
definitions.GLOW_MATERIAL = "content/ui/materials/frames/frame_glow_01" -- a soft glowing frame, used by stock HUD elements
definitions.BLOOD_DROPS = 3 -- the drops that run down from a Heresy card

local function card_passes()
	local passes = {}
	local z = definitions.Z.card

	-- the glow of a highlighted or chosen card: a stock frame texture, tinted with the suit colour
	passes[#passes + 1] = {
		pass_type = "texture",
		style_id = "glow",
		value = definitions.GLOW_MATERIAL,
		style = { scale_to_material = true, offset = { 0, 0, z }, size = { 1, 1 }, color = color(), visible = false },
	}

	rect(passes, "bg", z + 4)
	rect(passes, "accent", z + 5)

	for _, side in ipairs({ "t", "b", "l", "r" }) do
		rect(passes, "rare_" .. side, z + 6)
	end

	-- Heresy bleeds: drops run down from its lower edge (a thin line and a bead), see HudElementRealmsWavesPanel._tick_living
	for i = 1, definitions.BLOOD_DROPS do
		rect(passes, "blood_" .. i, z + 6.5)
		circle(passes, "blood_c" .. i, z + 6.6)
	end

	for i = 1, Spread.EYE_TRIS do
		triangle(passes, "eye_t" .. i, z + 7)
	end

	for i = 1, Spread.EYE_CIRCS do
		circle(passes, "eye_c" .. i, z + 7)
	end

	-- the suit mark: every triangle and circle has a faint, slightly larger copy under it (see Spread.FEATHER)
	for i = 1, Spread.ICON_TRIS do
		triangle(passes, "icon_th" .. i, z + 9)
	end

	for i = 1, Spread.ICON_CIRCS do
		circle(passes, "icon_ch" .. i, z + 9)
	end

	for i = 1, Spread.ICON_TRIS do
		triangle(passes, "icon_t" .. i, z + 10)
	end

	for i = 1, Spread.ICON_CIRCS do
		circle(passes, "icon_c" .. i, z + 10)
	end

	-- every diamond and dot has a faint, slightly larger copy under it: the UI draws shapes without anti-aliasing and
	-- the copy softens the jagged edge
	for i = 1, definitions.THREAT_MAX do
		diamond(passes, "th_h" .. i, z + 13, Spread.THREAT_SIDE + 1.4)
	end

	for i = 1, definitions.THREAT_MAX do
		diamond(passes, "th_o" .. i, z + 14, Spread.THREAT_SIDE)
	end

	for i = 1, definitions.DOTS_MAX do
		circle(passes, "dh_" .. i, z + 15)
	end

	for i = 1, definitions.DOTS_MAX do
		circle(passes, "dot_" .. i, z + 16)
	end

	text(passes, "name", z + 20, definitions.DISPLAY_FONT, Spread.NAME_FONT, "left", "top", false, true)

	-- Nightmare's black fog over everything on the card: a veil and three drifting banks (HudElementRealmsWavesPanel._tick_living)
	rect(passes, "fog_veil", z + 30)

	for i = 1, 3 do
		rect(passes, "fog_" .. i, z + 31)
	end

	return passes
end

-- ---------------------------------------------------------------------------------------------------- fx
local fx_passes = {}
local zf = definitions.Z.fx

rect(fx_passes, "wash", zf)

for i = 1, Spread.BLOTCHES do
	for ring = 1, #Spread.BLOTCH_RINGS do
		circle(fx_passes, "blot_" .. i .. "_" .. ring, zf + 1)
	end
end

for i = 1, Spread.DRIPS do
	rect(fx_passes, "drip_" .. i, zf + 5)
end

for i = 1, Spread.MAX_FLIES do
	circle(fx_passes, "fly_r" .. i, zf + 10)
	circle(fx_passes, "fly_c" .. i, zf + 11)
end

-- -------------------------------------------------------------------------------------------------- banner
local banner_passes = {}
local zb = definitions.Z.banner

text(banner_passes, "kicker", zb, definitions.FONT, 14, "center", "top")
text(banner_passes, "name", zb, definitions.DISPLAY_FONT, 34, "center", "top", true, true)
text(banner_passes, "whisper", zb, definitions.FONT, 17, "center", "top")
text(banner_passes, "mods", zb, definitions.FONT, 14, "center", "top")

definitions.scenegraph_definition = scenegraph_definition
definitions.widget_definitions = {
	legacy = UIWidget.create_definition(legacy_passes, "panel"),
	header = UIWidget.create_definition(header_passes, "panel"),
	fx = UIWidget.create_definition(fx_passes, "panel"),
	banner = UIWidget.create_definition(banner_passes, "panel"),
}

for i = 1, Spread.MAX_CARDS do
	definitions.widget_definitions["card_" .. i] = UIWidget.create_definition(card_passes(), "panel")
end

return definitions
