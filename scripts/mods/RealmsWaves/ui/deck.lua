-- The Deck (the editor's home screen): the arithmetic and the texts of the card tiles, with no engine calls so it is
-- tested offline (tools/editor_test.py). Sizes are in the editor's 1920 x 1080 units.
local Deck = {}

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

-- ------------------------------------------------------------------------------------------------- the grid
Deck.COLS = 7
Deck.ROWS = 2
Deck.CAPACITY = Deck.COLS * Deck.ROWS -- tiles on one page
Deck.TILE_W = 228
Deck.TILE_H = 262
Deck.GAP = 14
Deck.X0 = 120 -- 7 tiles and 6 gaps are 1680 wide, centred in the 1710 wide panel (x 105)
Deck.Y0 = 206

-- the weight strip above the grid
Deck.STRIP_X, Deck.STRIP_Y, Deck.STRIP_W, Deck.STRIP_H = 105, 158, 1710, 14
Deck.STRIP_GAP = 2
Deck.STRIP_MIN = 3
Deck.STRIP_MAX = 32 -- segments (12 standard cards and 20 custom ones)

-- Screen position of the tile in grid slot `slot` (1..CAPACITY, row by row).
Deck.tile_pos = function (slot)
	local col, row = (slot - 1) % Deck.COLS, floor((slot - 1) / Deck.COLS)

	return Deck.X0 + col * (Deck.TILE_W + Deck.GAP), Deck.Y0 + row * (Deck.TILE_H + Deck.GAP)
end

-- The page offset is a whole number of rows, so a scroll moves one row of seven cards.
Deck.max_offset = function (count)
	return max(0, ceil((count - Deck.CAPACITY) / Deck.COLS) * Deck.COLS)
end

Deck.clamp_offset = function (offset, count)
	offset = max(0, min(offset, Deck.max_offset(count)))

	return floor(offset / Deck.COLS) * Deck.COLS
end

-- ----------------------------------------------------------------------------------------------- weights
Deck.PIPS = 10

-- How many of the ten weight pips are filled: the weight rounded, 0 (never drawn) to 10 (10 or more).
Deck.pips = function (weight)
	return max(0, min(Deck.PIPS, floor((tonumber(weight) or 0) + 0.5)))
end

-- The strip of the draw: one segment per card that is in the draw, as wide as its weight says. `items` = list of
-- { weight, key, rgb }. Writes { x, w, key, rgb } entries (x relative to the strip) into `out` and returns how many.
-- No segment is narrower than STRIP_MIN; the narrow ones take their minimum and the rest share what is left.
Deck.strip_segments = function (items, width, out)
	local n = #items

	for i = #out, n + 1, -1 do
		out[i] = nil
	end

	if n == 0 then
		return 0
	end

	local room = width - Deck.STRIP_GAP * (n - 1)
	local total = 0

	for i = 1, n do
		total = total + max(0.0001, items[i].weight)
	end

	local fixed, free_weight = 0, 0

	for i = 1, n do
		local w = room * max(0.0001, items[i].weight) / total

		if w < Deck.STRIP_MIN then
			fixed = fixed + Deck.STRIP_MIN
		else
			free_weight = free_weight + max(0.0001, items[i].weight)
		end
	end

	local x = 0

	for i = 1, n do
		local weight = max(0.0001, items[i].weight)
		local w = room * weight / total

		if w < Deck.STRIP_MIN then
			w = Deck.STRIP_MIN
		else
			w = (room - fixed) * weight / free_weight
		end

		local segment = out[i] or {}

		segment.x, segment.w, segment.key, segment.rgb = x, w, items[i].key, items[i].rgb
		out[i] = segment
		x = x + w + Deck.STRIP_GAP
	end

	return n
end

-- ----------------------------------------------------------------------------------------------- the tile
-- Every card is one of these states: "off" (out of the draw), "in" (in the draw) or "cooling" (in the draw but
-- resting after its pick). `remaining` is the cooldown left in seconds.
Deck.state = function (card, remaining)
	if not card.enabled then
		return "off"
	elseif (remaining or 0) > 0 then
		return "cooling"
	end

	return "in"
end

Deck.clock_text = function (seconds)
	seconds = max(0, ceil(seconds or 0))

	return string.format("%d:%02d", floor(seconds / 60), seconds % 60)
end

Deck.MAX_COMP_LINES = 4
Deck.COMP_CHARS = 26 -- visible characters of a composition line

local function cut(text, chars)
	if #text > chars then
		return text:sub(1, chars - 3) .. "..."
	end

	return text
end

-- The composition of a card as at most MAX_COMP_LINES lines of text: one line per group "30 Poxwalker" (the count in
-- the bone colour, the enemy in its own colour), then "+N more", or the repeat note when there is room. `groups` is
-- catalog/groups.lua, `rgb_of(breed)` the enemy colour (or nil), `markup(text, rgb)` the colour tags (or nil: plain
-- text), `text_rgb` the colour of the counts, `note` the localized repeat note.
Deck.comp_lines = function (parts, groups, rgb_of, markup, text_rgb, note, more_format)
	local lines = {}
	local shown = min(#parts, #parts > Deck.MAX_COMP_LINES and Deck.MAX_COMP_LINES - 1 or Deck.MAX_COMP_LINES)

	for i = 1, shown do
		local part = parts[i]
		local count = tostring(part.count or 0)
		local name

		if part.one_of then
			local names = {}

			for j = 1, #part.one_of do
				names[j] = groups.display_name(part.one_of[j])
			end

			name = cut("of " .. table.concat(names, " / "), Deck.COMP_CHARS - #count - 1) -- "1 of A / B": the count is the number of picks
		else
			name = cut(groups.display_name(part.breed), Deck.COMP_CHARS - #count - 1)
		end

		if markup then
			local rgb = not part.one_of and rgb_of and rgb_of(part.breed) or nil

			lines[#lines + 1] = markup(count, text_rgb) .. " " .. (rgb and markup(name, rgb) or name)
		else
			lines[#lines + 1] = count .. " " .. name
		end
	end

	if #parts > shown then
		lines[#lines + 1] = more_format and more_format(#parts - shown) or ("+" .. (#parts - shown) .. " more")
	elseif note and #lines < Deck.MAX_COMP_LINES and groups.has_repeat(parts) then
		lines[#lines + 1] = note
	end

	return lines
end

return Deck
