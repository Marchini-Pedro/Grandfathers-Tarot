-- Definitions for the "last card" HUD window: ONE scenegraph node ("panel", the box the custom_hud mod lets the player drag around)
-- and ONE widget drawn inside it: a framed window with a caption ("LAST CARD" and how long ago), the card of the wave that went
-- out last as the Spread draws it (rectangles, circles, triangles, rotated squares, a glow texture, text), its whisper and its
-- modifiers. Every pass starts hidden; hud_element_last_card.lua writes geometry, colours and visibility into the widget style when
-- the card changes, and the age text once a second.
--
-- Font names must be exact; an unknown one crashes the renderer mid-draw.
local mod = get_mod("RealmsWaves")

local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")
local Spread = mod:io_dofile("RealmsWaves/scripts/mods/RealmsWaves/ui/spread")

local definitions = {}

definitions.Spread = Spread
definitions.WIDTH = 176
definitions.HEIGHT = 250 -- maximum: three name lines, two whisper lines and up to eight modifier lines
definitions.CARD_X, definitions.CARD_Y = 0, 24
definitions.CARD_W = Spread.card_width(1) -- the card is as wide as a card of a one-card Spread (176)
definitions.FONT = "proxima_nova_bold"
-- the default font of the card's name (the player can choose another one in the options, see hud_element_last_card.lua)
definitions.DISPLAY_FONT = "itc_novarese_bold"
definitions.GLOW_MATERIAL = "content/ui/materials/frames/frame_glow_01" -- a soft glowing frame, used by stock HUD elements
definitions.THREAT_MAX = 6
definitions.DOTS_MAX = 6 -- the most dots a card shows (catalog/cards.lua MAX_DOTS)

-- layers (the passes of the widget are ordered by their z offset)
definitions.Z = { window = 10, text = 14, card = 20 }

local scenegraph_definition = {
	screen = UIWorkspaceSettings.screen,

	panel = {
		parent = "screen",
		vertical_alignment = "top",
		-- top-left basis: that is what the custom_hud mod pins nodes on, so its edit box sits exactly on the HUD. To the right of
		-- the Spread (which is 700 wide from x 610); the player moves it where it suits them.
		horizontal_alignment = "left",
		size = { definitions.WIDTH, definitions.HEIGHT },
		position = { 1330, 36, 50 },
	},
}

-- ------------------------------------------------------------------------------------------- pass helpers
-- (the Spread's own definitions file has the same helpers: they are small and local to each file, like the HUD's other helpers)
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

local function text(passes, id, z, font, size, horizontal, vertical, wrap, display)
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
			word_wrap = wrap == true or nil, -- (a name is not given the key at all, like the Spread's: the engine wraps it in its box)
			drop_shadow = false,
			display = display, -- the font option changes the texts flagged like this (the card's name)
			visible = false,
		},
	}
end

-- ------------------------------------------------------------------------------------------------ the widget
local passes = {}
local Z = definitions.Z

-- the window: a panel and a frame of four lines (placed to the card's height by the element)
rect(passes, "bg", Z.window)

for _, side in ipairs({ "t", "b", "l", "r" }) do
	rect(passes, "win_" .. side, Z.window + 1)
end

text(passes, "kicker", Z.text, definitions.FONT, 14, "left", "center")
text(passes, "age", Z.text, definitions.FONT, 14, "right", "center")
text(passes, "whisper", Z.text, definitions.FONT, 14, "left", "top", true)
text(passes, "mods", Z.text, definitions.FONT, 12, "left", "top", true)

-- the card, as the Spread draws it
local z = Z.card

passes[#passes + 1] = {
	pass_type = "texture",
	style_id = "glow",
	value = definitions.GLOW_MATERIAL,
	style = { scale_to_material = true, offset = { 0, 0, z }, size = { 1, 1 }, color = color(), visible = false },
}

rect(passes, "card_bg", z + 4)
circle(passes, "sigil_ring", z + 7)
circle(passes, "sigil_disc", z + 8)
rect(passes, "card_accent", z + 5)

for _, side in ipairs({ "t", "b", "l", "r" }) do
	rect(passes, "rare_" .. side, z + 6)
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

definitions.scenegraph_definition = scenegraph_definition
definitions.widget_definitions = {
	last = UIWidget.create_definition(passes, "panel"),
}

return definitions
