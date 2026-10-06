-- The murmur of a card's letters (2026-10-05, the user: "for Murmur cards of threat 5 and 6, all the letters in the card do the
-- murmur effect"): the murmur is the way a threat 5 or 6 card's whisper is written letter by letter when it is drawn (the Spread's
-- banner). On a Murmur card of threat 5 or 6 every text of the card does it, over and over: its name, its enemies, its modifiers and
-- its whisper are written one letter after another, in that order, held, wiped away from the end, and after a breath written again.
-- Each text may carry the game's markup ({#color(...)}): a tag never counts as a letter and is never cut. Pure, tested offline.
local Murmur = {}

local floor, max, min = math.floor, math.max, math.min

Murmur.SPEED = 26 -- letters a second
Murmur.HOLD, Murmur.ERASE, Murmur.GAP = 5, 0.7, 0.6 -- seconds: written and held, wiped, nothing

Murmur.on = function (suit, threat)
	return suit == "murmur" and (tonumber(threat) or 0) >= 5
end

-- the bytes of the letter starting with byte b
local function letter_size(b)
	return b >= 0xF0 and 4 or b >= 0xE0 and 3 or b >= 0xC0 and 2 or 1
end

-- The first n letters of `text` (tags kept, a colour left open is closed), and the letters it has in all
Murmur.cut = function (text, n)
	text = tostring(text or "")

	local i, len, shown, tagged = 1, #text, 0, false

	while i <= len do
		if text:sub(i, i + 1) == "{#" then
			local close = text:find("}", i, true)

			if not close then break end

			i, tagged = close + 1, true
		elseif shown < n then
			i, shown = i + letter_size(text:byte(i)), shown + 1
		else
			break
		end
	end

	if i > len then
		return text, shown
	end

	return text:sub(1, i - 1) .. (tagged and "{#reset()}" or ""), shown
end

Murmur.length = function (text)
	local _, n = Murmur.cut(text, math.huge)

	return n
end

-- the letters written at time t of a murmur over `total` letters
Murmur.letters = function (t, total)
	local write = total / Murmur.SPEED
	local u = (tonumber(t) or 0) % (write + Murmur.HOLD + Murmur.ERASE + Murmur.GAP)

	if u < write then return floor(u * Murmur.SPEED) end

	u = u - write

	if u < Murmur.HOLD then return total end

	u = u - Murmur.HOLD

	if u < Murmur.ERASE then return floor(total * (1 - u / Murmur.ERASE)) end

	return 0
end

-- A murmur over several texts (written in their order): Murmur.new({ name, comp, ... }) then Murmur.tick(m, t) returns true when the
-- letters written changed, with m.shown[j] the text j as it is to be shown now
Murmur.new = function (texts)
	local m = { texts = texts, lengths = {}, shown = {}, total = 0, n = -1 }

	for j = 1, #texts do
		m.lengths[j] = Murmur.length(texts[j])
		m.total = m.total + m.lengths[j]
		m.shown[j] = texts[j]
	end

	return m
end

Murmur.tick = function (m, t)
	local n = Murmur.letters(t, m.total)

	if n == m.n then return false end

	m.n = n

	local before = 0

	for j = 1, #m.texts do
		m.shown[j] = Murmur.cut(m.texts[j], max(0, min(m.lengths[j], n - before)))
		before = before + m.lengths[j]
	end

	return true
end

return Murmur
