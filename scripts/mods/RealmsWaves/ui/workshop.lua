-- The Workshop (the card's own screens, docs/08-workshop-redesign.md): where everything sits, as pure arithmetic with no engine
-- calls, so it is tested offline (tools/editor_test.py). Sizes are in the editor's 1920 x 1080 units.
--
-- The Cauldron (screen "detail"): a left pane (x 105, 1135 wide) with the header, the enemy rows, a summary line, the shelf of
-- enemies, the spawn settings and the action bar; a right pane (x 1290, 525 wide) with the card on its stage and the quick
-- face under it.
local Workshop = {}

local floor, ceil, max = math.floor, math.ceil, math.max

Workshop.LEFT_X, Workshop.LEFT_W = 105, 1135
Workshop.RIGHT_X, Workshop.RIGHT_W = 1290, 525
Workshop.TOP = 134
Workshop.BOTTOM = 1014 -- nothing of a pane goes below this (the input legend is under it)

-- ------------------------------------------------------------------------------------------------- enemy rows
Workshop.ROWS = 5 -- enemy rows visible at once
Workshop.ROW_H = 48
Workshop.ROW_PITCH = 52
Workshop.HEADER_Y, Workshop.HEADER_H = 134, 22
Workshop.ROW_Y0 = 164

Workshop.row_y = function (i)
	return Workshop.ROW_Y0 + (i - 1) * Workshop.ROW_PITCH
end

-- x of the parts of an enemy row, inside the row: the name (and its modifier line), the weight stepper, the repeat stepper,
-- the Same diamond (its centre) and the three chips
Workshop.COL = {
	name = 24, name_w = 305,
	weight = 347, repeat_ = 523,
	same = 727,
	mods = 771, mods_w = 100,
	tune = 879, tune_w = 116,
	remove = 1003, remove_w = 108,
}
Workshop.STEPPER = { button = 40, value = 56, height = 40 } -- the plate of a stepper: minus, value, plus

-- the summary line under the rows ("The Magician: 9 enemies in total", "1 - 4 of 4" and the scroll buttons)
Workshop.SUMMARY_Y = Workshop.ROW_Y0 + Workshop.ROWS * Workshop.ROW_PITCH + 4
Workshop.SUMMARY_H = 34

-- ------------------------------------------------------------------------------------------------- the shelf
Workshop.CHIP_H = 34
Workshop.CHIP_GAP = 8 -- between chips of a row
Workshop.CHIP_PITCH = 42 -- between rows of chips
Workshop.SHELF_PAD = 16
Workshop.SHELF_HEAD = 56 -- the panel's title row (title, hint, the faction switch, Search all enemies)
Workshop.GROUP_LABEL_W = 100
Workshop.GROUP_GAP = 6
Workshop.CHIP_FONT = 16
Workshop.GLYPH = 0.64 -- of the font size: how wide a letter is of the bold sans (a "Hound" is 3.05 em), a little careful: a chip that is too wide only leaves a gap

Workshop.SHELF_Y = Workshop.SUMMARY_Y + Workshop.SUMMARY_H + 10

Workshop.text_width = function (text, font_size)
	return ceil(#tostring(text) * font_size * Workshop.GLYPH)
end

-- width of a chip: the dot (26 up to the label), the label and 14 of padding
Workshop.CHIP_DOT, Workshop.CHIP_PAD = 26, 14

Workshop.chip_width = function (label)
	return Workshop.CHIP_DOT + Workshop.text_width(label, Workshop.CHIP_FONT) + Workshop.CHIP_PAD
end

-- Where every chip of the shelf goes. `shelf` = Groups.SHELF, `groups` = the catalog (faction, display names). Chips of a group
-- flow left to right in a band to the right of the group's label and wrap to the next row of that band. Returns
-- { chips = { { group, index, entry, x, y, w } ... }, bands = { { id, y, rows } ... }, height }, x and y inside the
-- panel (the panel starts at LEFT_X, SHELF_Y).
Workshop.shelf_layout = function (shelf, groups)
	local chips, bands = {}, {}
	local x0 = Workshop.SHELF_PAD + Workshop.GROUP_LABEL_W
	local avail = Workshop.LEFT_W - Workshop.SHELF_PAD - x0
	local y = Workshop.SHELF_HEAD

	for g = 1, #shelf do
		local group = shelf[g]
		local x, row = 0, 0

		for i = 1, #group.entries do
			local entry = group.entries[i]
			local w = Workshop.chip_width(groups.shelf_label(entry))

			if x > 0 and x + w > avail then
				x, row = 0, row + 1
			end

			chips[#chips + 1] = { group = g, index = i, entry = entry, x = x0 + x, y = y + row * Workshop.CHIP_PITCH, w = w }
			x = x + w + Workshop.CHIP_GAP
		end

		bands[#bands + 1] = { id = group.id, y = y, rows = row + 1 }
		y = y + (row + 1) * Workshop.CHIP_PITCH + Workshop.GROUP_GAP
	end

	return { chips = chips, bands = bands, height = y - Workshop.GROUP_GAP + Workshop.SHELF_PAD - (Workshop.CHIP_PITCH - Workshop.CHIP_H) }
end

-- ------------------------------------------------------------------------------------------------- spawn settings, actions
Workshop.SPAWN_COLS = { 105, 491, 877 }
Workshop.SPAWN_W = 360
Workshop.SPAWN_ROW_H = 42
Workshop.SPAWN_ROW_PITCH = 48

-- Everything under the shelf, from the shelf's height: { label_y, row_y = { y1, y2 }, actions_y }
Workshop.under_shelf = function (shelf_height)
	local label_y = Workshop.SHELF_Y + shelf_height + 12
	local y1 = label_y + 22

	return { label_y = label_y, row_y = { y1, y1 + Workshop.SPAWN_ROW_PITCH }, actions_y = y1 + Workshop.SPAWN_ROW_PITCH + Workshop.SPAWN_ROW_H + 16 }
end

-- The six spawn steppers in two rows of three: { name, x, y } in this order
Workshop.SPAWN_ORDER = { "stepper_spread", "stepper_every", "stepper_for", "stepper_dmin", "stepper_dmax", "stepper_timer" }

Workshop.spawn_pos = function (index, rows_y)
	local col, row = (index - 1) % 3, floor((index - 1) / 3)

	return Workshop.SPAWN_COLS[col + 1], rows_y[row + 1]
end

-- ------------------------------------------------------------------------------------------------- the right pane
Workshop.CAPTION_Y = 134
Workshop.PLATE = { x = 1290, y = 164, w = 525, h = 440 }
Workshop.CARD_SCALE = 1.4
-- the card (228 x 270 at scale 1): centred in the plate, 22 below its top
Workshop.card_pos = function (card_w)
	return floor(Workshop.PLATE.x + (Workshop.PLATE.w - card_w) / 2 + 0.5), Workshop.PLATE.y + 22
end
-- the rings around the card on its plate (ui/workshop_blueprints.lua): radius, share of the suit's accent in the disc, a line on its edge
Workshop.STAGE_RINGS = { { 208, 0.09, true }, { 186, 0.13, false }, { 164, 0.18, true }, { 142, 0.23, false }, { 120, 0.29, true } } -- radius, accent share, line on its edge
Workshop.STATS_Y = Workshop.PLATE.y + Workshop.PLATE.h - 38
Workshop.TOOLBAR_Y = Workshop.PLATE.y + Workshop.PLATE.h + 8
Workshop.QUICK_Y = Workshop.TOOLBAR_Y + 44 + 16
Workshop.SUIT_W, Workshop.SUIT_H = 80, 58
Workshop.SUIT_GAP_X, Workshop.SUIT_GAP_Y = 9, 12
Workshop.SUIT_Y0 = Workshop.QUICK_Y + 40 -- (a chosen tile stands 4 higher: it must clear the button in the label row)
Workshop.THREAT_Y = Workshop.SUIT_Y0 + 2 * Workshop.SUIT_H + Workshop.SUIT_GAP_Y + 18
Workshop.CHANCE_Y = Workshop.THREAT_Y + 52
Workshop.ROW_LABEL_W = 84

Workshop.suit_pos = function (index)
	local col, row = (index - 1) % 6, floor((index - 1) / 6)

	return Workshop.RIGHT_X + col * (Workshop.SUIT_W + Workshop.SUIT_GAP_X), Workshop.SUIT_Y0 + row * (Workshop.SUIT_H + Workshop.SUIT_GAP_Y)
end

-- the five threat diamonds (their hit areas are 40 x 44) start after the label
Workshop.THREAT_PITCH = 40
Workshop.THREAT_X = Workshop.RIGHT_X + Workshop.ROW_LABEL_W

-- ------------------------------------------------------------------------------------------------- the Mirror
-- The card face screen (screen "face"): four sections on the left (suit, threat, whisper, cooldown with its look) and the same
-- stage on the right as the Cauldron's. y of every part; the action bar is the Cauldron's (Workshop.under_shelf).
Workshop.MIRROR = {
	head = { 134, 460, 566, 664 }, -- the section headers: suit, threat, whisper, cooldown
	head_h = 28,
	plate = { w = 274, h = 66, gap_x = 13, gap_y = 10, y0 = 170, cols = 4 }, -- the twelve suits as plates, 4 x 3
	desc_y = 396, desc_h = 52,
	threat_y = 494, threat_side = 26, threat_pitch = 54, threat_h = 56,
	whisper_y = 600, whisper_h = 44, whisper_w = 700,
	cooldown_y = 698,
	look = { y = 756, w = 365, h = 110, gap = 20 }, -- the three looks of the cooldown
	auto_y = 876, auto_h = 36,
}
Workshop.MIRROR.bottom = Workshop.MIRROR.auto_y + Workshop.MIRROR.auto_h

-- "In the hand" (under the toolbar): the card as the Spread HUD draws it, at 1.5 times its HUD size (176 wide there).
Workshop.HAND = { x = Workshop.RIGHT_X, caption_y = Workshop.TOOLBAR_Y + 44 + 28, scale = 1.5, hud_w = 176, pad = 12, bar = 4, icon = 18, name_font = 18 }
Workshop.HAND.y = Workshop.HAND.caption_y + 32
Workshop.HAND.w = Workshop.HAND.hud_w * Workshop.HAND.scale
Workshop.HAND.max_h = 150 -- (a name of three lines)

Workshop.plate_pos = function (index)
	local M = Workshop.MIRROR.plate
	local col, row = (index - 1) % M.cols, floor((index - 1) / M.cols)

	return Workshop.LEFT_X + col * (M.w + M.gap_x), M.y0 + row * (M.h + M.gap_y)
end

Workshop.look_pos = function (index)
	local L = Workshop.MIRROR.look

	return Workshop.LEFT_X + (index - 1) * (L.w + L.gap), L.y
end

return Workshop
