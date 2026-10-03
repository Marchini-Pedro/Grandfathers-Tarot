-- The Deck (the editor's home screen): the arithmetic and the texts of the card tiles, with no engine calls so it is
-- tested offline (tools/editor_test.py). Sizes are in the editor's 1920 x 1080 units.
local Deck = {}

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

-- ------------------------------------------------------------------------------------------------- the grid
Deck.COLS = 7
Deck.ROWS = 2
Deck.CAPACITY = Deck.COLS * Deck.ROWS -- tiles on one page
Deck.TILE_W = 228
Deck.TILE_H = 270
Deck.GAP = 12
Deck.X0 = 126 -- 7 tiles and 6 gaps are 1668 wide, centred in the 1710 wide panel (x 105)
Deck.Y0 = 190

-- the weight strip above the grid
Deck.STRIP_X, Deck.STRIP_Y, Deck.STRIP_W, Deck.STRIP_H = 105, 144, 1710, 14
Deck.STRIP_GAP = 2
Deck.STRIP_MIN = 3
Deck.STRIP_MAX = 100 -- segments, one per card that can be in the draw (Events.MAX_CARDS: 12 standard cards and 88 custom ones)

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

-- ------------------------------------------------------------------------------------------------- sorting and moving
Deck.SORTS = { "threat", "rarity", "enemies", "face" }
Deck.DRAG_HOLD = 0.3 -- seconds a card is held before it is lifted
local SORT_TIES = { "threat", "enemies", "chance" }

-- The cards of the Deck in the order of `sort` ("threat": the hardest last; "rarity": the rarest, the lowest chance, first; "enemies":
-- the fewest first; "face": by suit in the order of the suit list), `desc` turns it round. `items` = list of { key, threat, chance, enemies,
-- suit (the place of its suit) }; the sort is stable (equal cards keep the order they had) and the tie breakers are the
-- other numbers, threat then enemies. Returns a new list of the same items.
Deck.sorted = function (items, sort, desc)
	local order = {}

	for i = 1, #items do
		order[i] = { item = items[i], index = i }
	end

	local function primary(item)
		if sort == "rarity" then
			return item.chance
		elseif sort == "enemies" then
			return item.enemies
		elseif sort == "face" then
			return item.suit
		end

		return item.threat
	end

	table.sort(order, function (a, b)
		local pa, pb = primary(a.item), primary(b.item)

		if pa ~= pb then
			if desc then
				return pa > pb
			end

			return pa < pb
		end

		-- the tie breakers follow the direction of the sort too
		for _, field in ipairs(SORT_TIES) do
			local x, y = a.item[field], b.item[field]

			if x ~= y then
				if desc then
					return x > y
				end

				return x < y
			end
		end

		return a.index < b.index
	end)

	local out = {}

	for i = 1, #order do
		out[i] = order[i].item
	end

	return out
end

-- Swaps two places of a list of keys; returns a new list (the same list when a place is missing or both are the same place).
Deck.swapped = function (keys, a, b)
	if a == b or not keys[a] or not keys[b] then
		return keys
	end

	local out = {}

	for i = 1, #keys do
		out[i] = keys[i]
	end

	out[a], out[b] = keys[b], keys[a]

	return out
end

-- ----------------------------------------------------------------------------------------------- weights
Deck.PIPS = 10

-- How many of the ten chance pips are filled for a chance level (catalog/cards.lua, Cards.level: relative to the other
-- cards of the draw, so ten pips are the likeliest card and one pip the least likely), 0 = never drawn.
Deck.pips = function (level)
	return max(0, min(Deck.PIPS, floor((tonumber(level) or 0) + 0.5)))
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

Deck.MAX_COMP_LINES = 4 -- without a layout (see Deck.layout)
Deck.COMP_CHARS = 26 -- visible characters of a composition line

-- The name takes one to three lines and everything under it follows: a short name leaves room for more enemies. Heights
-- are in the tile's units: the name starts at NAME_Y, a line of it is NAME_LINE high, the composition ends at COMP_BOTTOM
-- (the modifier line follows), a line of it is COMP_LINE high.
Deck.NAME_Y, Deck.NAME_LINE = 38, 24
Deck.COMP_LINE, Deck.COMP_BOTTOM = 17, 164

-- { divider_y, comp_y, comp_lines, comp_h } of a tile whose name takes `name_lines` lines: 5, 4 or 2 composition lines
Deck.layout = function (name_lines)
	local lines = max(1, min(3, floor(tonumber(name_lines) or 1)))
	local divider = Deck.NAME_Y + lines * Deck.NAME_LINE + 2
	local comp_y = divider + 7
	local comp_lines = max(1, floor((Deck.COMP_BOTTOM - comp_y) / Deck.COMP_LINE))

	return { divider_y = divider, comp_y = comp_y, comp_lines = comp_lines, comp_h = comp_lines * Deck.COMP_LINE }
end

local function cut(text, chars)
	if #text > chars then
		return text:sub(1, chars - 3) .. "..."
	end

	return text
end

-- The composition of a card as at most `max_lines` (MAX_COMP_LINES) lines of text: one line per group "30 Poxwalker" (the count in
-- the bone colour, the enemy in its own colour), then "+N more", or the repeat note when there is room. `groups` is
-- catalog/groups.lua, `rgb_of(breed)` the enemy colour (or nil), `markup(text, rgb)` the colour tags (or nil: plain
-- text), `text_rgb` the colour of the counts, `note` the localized repeat note.
Deck.comp_lines = function (parts, groups, rgb_of, markup, text_rgb, note, more_format, max_lines)
	local lines = {}
	local limit = max_lines or Deck.MAX_COMP_LINES
	local shown = min(#parts, #parts > limit and limit - 1 or limit)

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
	elseif note and #lines < limit and groups.has_repeat(parts) then
		lines[#lines + 1] = note
	end

	return lines
end

return Deck
