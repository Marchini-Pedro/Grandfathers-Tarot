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
Workshop.ROWS = 6 -- enemy rows visible at once (5 while the shelf chips were taller: the room the smaller chips free is the sixth row)
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
	mods = 771, mods_w = 84,
	tune = 863, tune_w = 100,
	remove = 971, remove_w = 84,
	dogs = 1063, dogs_w = 64, -- a Packmaster's group only: whether he calls his hounds (2026-10-06)
}
-- the plate of a stepper on a row: minus, value, plus. Compact since 2026-10-04 (the user: "too large, make it cleaner"): it was
-- 40, 56 and 40 high with a 22 unit value; the signs are 6 units from the middle instead of 7
Workshop.STEPPER = { button = 32, value = 46, height = 32, font = 19, sign = 6 }

-- the summary line under the rows ("The Magician: 9 enemies in total", "1 - 4 of 4" and the scroll buttons)
Workshop.SUMMARY_Y = Workshop.ROW_Y0 + Workshop.ROWS * Workshop.ROW_PITCH + 4
Workshop.SUMMARY_H = 34

-- ------------------------------------------------------------------------------------------------- the shelf
-- Since 2026-10-04 (the user's design page): four COLUMNS side by side (Fodder, Elites, Specials, Bosses; or Healing, Buffs, Items,
-- Game Effects), each with its title on top and its chips flowing under it, every chip as wide as its label (not six equal cells),
-- with a one unit outline.
Workshop.CHIP_H = 30
Workshop.CHIP_GAP = 8 -- between chips of a line
Workshop.CHIP_PITCH = 38 -- between lines of chips
Workshop.SHELF_PAD = 16
Workshop.SHELF_HEAD = 52 -- the panel's title row (title, hint, the faction switch, Search all enemies)
Workshop.COLUMN_GAP = 16
Workshop.COLUMN_LABEL_H = 24 -- a column's title over its chips
Workshop.CHIP_FONT = 16
Workshop.GLYPH = 0.6 -- of the font size: how wide a letter of the bold sans is, a little careful (a chip a bit too wide only leaves room)
-- the share of the width each column gets: the enemies' names grow longer from Fodder to Bosses; the effects' are alike
Workshop.ENEMY_COLUMNS = { 0.9, 1.05, 1.25, 1.3 }
Workshop.EFFECT_COLUMNS = { 1, 1, 1, 1 }
Workshop.CHIP_PIP = 20 -- room for the diamond at the right end of an effect chip (lit while the card holds the effect)

Workshop.SHELF_Y = Workshop.SUMMARY_Y + Workshop.SUMMARY_H + 10

-- width of a chip: the dot (22 up to the label), the label, 12 of padding and the room of a pip (`tail`)
Workshop.CHIP_DOT, Workshop.CHIP_PAD = 22, 12

Workshop.chip_width = function (label, tail)
	return ceil(Workshop.CHIP_DOT + #tostring(label or "") * Workshop.CHIP_FONT * Workshop.GLYPH + Workshop.CHIP_PAD + (tail or 0))
end

-- The columns of a shelf: `columns` = { { id, labels = { ... } } ... }, `weights` their shares of the width. Returns
-- { chips = { { column, index, x, y, w } ... }, bands = { { id, x, y, w } ... }, height }, x and y inside the panel.
local function column_layout(columns, weights, tail)
	local chips, bands, total = {}, {}, 0
	for i = 1, #columns do total = total + (weights[i] or 1) end
	local avail = Workshop.LEFT_W - 2 * Workshop.SHELF_PAD - (#columns - 1) * Workshop.COLUMN_GAP
	local x0, bottom = Workshop.SHELF_PAD, Workshop.SHELF_HEAD + Workshop.COLUMN_LABEL_H

	for c, column in ipairs(columns) do
		local width = floor(avail * (weights[c] or 1) / total)
		local x, y = 0, Workshop.SHELF_HEAD + Workshop.COLUMN_LABEL_H

		for i, label in ipairs(column.labels) do
			local w = math.min(width, Workshop.chip_width(label, tail))
			-- a chip that does not fit beside the last one starts a new line of the column
			if x > 0 and x + w > width then x, y = 0, y + Workshop.CHIP_PITCH end
			chips[#chips + 1] = { column = c, index = i, x = x0 + x, y = y, w = w }
			x = x + w + Workshop.CHIP_GAP
		end

		bottom = max(bottom, y + Workshop.CHIP_H)
		bands[#bands + 1] = { id = column.id, x = x0, y = Workshop.SHELF_HEAD, w = width }
		x0 = x0 + width + Workshop.COLUMN_GAP
	end

	return { chips = chips, bands = bands, height = bottom + Workshop.SHELF_PAD }
end

-- Where every chip of the enemy shelf goes. `shelf` = Groups.SHELF, `groups` = the catalog (display names). Every chip also
-- carries `group` and `entry`.
Workshop.shelf_layout = function (shelf, groups)
	local columns = {}

	for g, group in ipairs(shelf) do
		columns[g] = { id = group.id, labels = {} }
		for i, entry in ipairs(group.entries) do columns[g].labels[i] = groups.shelf_label(entry) end
	end

	local layout = column_layout(columns, Workshop.ENEMY_COLUMNS)
	for _, chip in ipairs(layout.chips) do chip.group, chip.entry = chip.column, shelf[chip.column].entries[chip.index] end

	return layout
end

-- ------------------------------------------------------------------------------------------------- the beneficial Cauldron
-- A beneficial card's rows (ui/wave_editor_effects.lua): the name and its group under it, the amount stepper (its value cell wide
-- enough for "100 percent"), the players stepper (Blue Stimm only), Remove at the enemy rows' place.
Workshop.FX = { name = 24, name_w = 400, amount = 470, amount_w = 150, players = 712, players_w = 110 }

-- The label of an effect's chip (a disabled one says so)
Workshop.fx_chip_label = function (def, off_word)
	return def.disabled and (def.short .. "  (" .. (off_word or "off") .. ")") or def.short
end

-- Where every effect chip of the beneficial shelf goes: one column per group (`categories` = Effects.CATEGORIES), in order. `defs` =
-- the effects (not Blackout). Every chip also carries `def`.
Workshop.fx_shelf_layout = function (categories, defs)
	local columns, by_column = {}, {}

	for _, category in ipairs(categories) do
		local labels, list = {}, {}
		for _, def in ipairs(defs) do if def.category == category.id then labels[#labels + 1], list[#list + 1] = Workshop.fx_chip_label(def), def end end
		if #list > 0 then columns[#columns + 1], by_column[#columns + 1] = { id = category.id, labels = labels }, list end
	end

	local layout = column_layout(columns, Workshop.EFFECT_COLUMNS, Workshop.CHIP_PIP)
	for _, chip in ipairs(layout.chips) do chip.def = by_column[chip.column][chip.index] end

	return layout
end

-- The completion sound screen, in the bottom panel (y 750 to 1030): the two slots, Remove the second and Search in one line, the
-- volume sliders under it, right of Back (125, 800).
Workshop.SOUND = { slots_y = 754, slots_h = 40, slot1_x = 125, slot2_x = 745, slot_w = 600, remove_x = 1365, remove_w = 200, search_x = 1585, search_w = 215, stop_x = 1365, stop_y = 802, stop_w = 435, slider_x = 325, slider_y = { 802, 860 }, slider_h = 52, label_w = 160, track_x = 170, track_w = 760 }

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
-- the suits: two rows of six across the pane (2026-10-04: the user asked for 2 x 6, not 2 x 8)
Workshop.SUIT_COLS = 6
Workshop.SUIT_W, Workshop.SUIT_H = 80, 48
Workshop.SUIT_GAP_X, Workshop.SUIT_GAP_Y = 9, 12
Workshop.SUIT_Y0 = Workshop.QUICK_Y + 40 -- (a chosen tile stands 4 higher: it must clear the button in the label row)
Workshop.THREAT_Y = Workshop.SUIT_Y0 + 2 * Workshop.SUIT_H + Workshop.SUIT_GAP_Y + 18
Workshop.CHANCE_Y = Workshop.THREAT_Y + 52
Workshop.ROW_LABEL_W = 84

-- The quick face's switch between the twelve hostile suits and the four beneficial ones (right of the FACE label), and the quiet
-- "Whisper and cooldown" button at the right end of the same line
Workshop.KIND = { x = Workshop.RIGHT_X + 64, w_hostile = 104, w_ben = 112, h = 32 }
Workshop.QUICKFACE_W = 236

Workshop.suit_pos = function (index)
	local col, row = (index - 1) % Workshop.SUIT_COLS, floor((index - 1) / Workshop.SUIT_COLS)

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
	plate = { w = 216, h = 66, gap_x = 13, gap_y = 10, y0 = 170, cols = 5 }, -- the twelve suits as plates, 4 x 3
	desc_y = 396, desc_h = 52,
	threat_y = 494, threat_side = 26, threat_pitch = 54, threat_h = 56,
	whisper_y = 600, whisper_h = 44, whisper_w = 700,
	cooldown_y = 698,
	look = { y = 756, w = 365, h = 110, gap = 20 }, -- the three looks of the cooldown
	auto_y = 876, auto_h = 36,
}
Workshop.MIRROR.bottom = Workshop.MIRROR.auto_y + Workshop.MIRROR.auto_h
-- the same switch on the Mirror, at the right end of the Suit header
Workshop.MIRROR.kind_x = Workshop.LEFT_X + Workshop.LEFT_W - Workshop.KIND.w_hostile - Workshop.KIND.w_ben
Workshop.MIRROR.kind_y = Workshop.MIRROR.head[1] - 4

-- "In the hand" (under the toolbar): the card as the Spread HUD draws it, at 1.5 times its HUD size (176 wide there).
Workshop.HAND = { x = Workshop.RIGHT_X, caption_y = Workshop.TOOLBAR_Y + 44 + 28, scale = 1.5, hud_w = 176, pad = 12, bar = 4, icon = 18, name_font = 18 }
Workshop.HAND.y = Workshop.HAND.caption_y + 32
Workshop.HAND.w = Workshop.HAND.hud_w * Workshop.HAND.scale
Workshop.HAND.max_h = 150 -- (a name of three lines)
Workshop.HAND.last_gap = 16 -- the last card window's preview beside it (240 wide: the two fill the 525 of the right side)

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
