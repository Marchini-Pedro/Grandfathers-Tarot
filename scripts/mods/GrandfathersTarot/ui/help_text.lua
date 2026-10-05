-- The "?" tooltip's text (2026-10-05, the user: "a more clean "?" hover description in all windows; there is no formatting"). The help
-- strings of the localization are written in a tiny markup, one part per line:
--   "# Title"     the panel's title (drawn apart, in the display font)
--   "## Heading"  a section heading: upper case, smaller, in the accent
--   "- item"      a bullet
--   other lines   a paragraph
-- and *a few words* between stars are lit (the name of a button, a key). Help.format turns that into the game's own text markup
-- ({#color(r,g,b)}, {#size(n)}, {#reset()}) and estimates how high the text will be, so the panel is cut to it. A string without
-- any markup comes back as it is. Pure, tested offline (tools/editor_test.py).
local Help = {}

local floor, max = math.floor, math.max

-- the panel (wave_editor_definitions.lua help_panel): its width, the margin of the body, where the body starts, the footer's height
Help.WIDTH, Help.PAD, Help.BODY_Y, Help.FOOT = 760, 28, 76, 40
Help.BODY_FONT, Help.HEAD_FONT = 19, 15
-- the height of a line of the body, of a heading with the space above it, of the space between two paragraphs
Help.LINE, Help.HEAD, Help.GAP = 25, 34, 8
-- the average width of a glyph of proxima_nova_bold, in font sizes (a little wide, so the height is never short)
Help.GLYPH = 0.56
Help.BULLET = "\226\128\162" -- (a bullet as its UTF-8 bytes: LuaJIT reads no \u escape)
Help.LIT = { 255, 246, 222 }

local function tag(rgb)
	return string.format("{#color(%d,%d,%d)}", floor(rgb[1] + 0.5), floor(rgb[2] + 0.5), floor(rgb[3] + 0.5))
end

-- the lines a text needs in a box `chars` glyphs wide, wrapping between words as the engine does
local function wrapped(text, chars)
	local lines, used = 1, 0

	for word in text:gmatch("%S+") do
		local n = #word

		if used == 0 then
			used = n
		elseif used + 1 + n <= chars then
			used = used + 1 + n
		else
			lines, used = lines + 1, n
		end
	end

	return lines
end

Help.wrapped = wrapped

-- Returns the title (nil when the text has none), the body in the game's markup and its height. `width` is the body's width,
-- `accent` the colour of the headings and the bullets, `lit` the colour of the *lit* words (Help.LIT when nil).
Help.format = function (raw, width, accent, lit)
	raw = tostring(raw or "")
	lit = lit or Help.LIT

	local chars = max(10, floor(width / (Help.BODY_FONT * Help.GLYPH)))
	local title, out, height = nil, {}, 0
	local open, close = tag(lit), "{#reset()}"

	local function light(text)
		return (text:gsub("%*(.-)%*", function (words)
			return open .. words .. close
		end))
	end

	for each in (raw .. "\n"):gmatch("(.-)\n") do
		local line = each:match("^%s*(.-)%s*$")

		local bare = line:gsub("%*", "")

		if line == "" then
			-- (an empty line is only the space it leaves: the parts are spaced already)
		elseif line:sub(1, 2) == "# " and title == nil and #out == 0 then
			title = bare:sub(3)
		elseif line:sub(1, 3) == "## " then
			-- a little air above the heading (none at the top), then the heading
			if #out > 0 then
				out[#out + 1] = string.format("{#size(%d)} %s", Help.GAP + 4, close)
			end

			out[#out + 1] = string.format("{#size(%d)}%s%s%s", Help.HEAD_FONT, tag(accent), string.upper(bare:sub(4)), close)
			height = height + (#out > 1 and Help.HEAD or Help.HEAD - Help.GAP - 4)
		elseif line:sub(1, 2) == "- " then
			out[#out + 1] = tag(accent) .. Help.BULLET .. close .. "  " .. light(line:sub(3))
			height = height + wrapped(Help.BULLET .. "  " .. bare:sub(3), chars) * Help.LINE
		else
			if #out > 0 and not out[#out]:find("^{#size") then
				out[#out + 1] = string.format("{#size(%d)} %s", Help.GAP, close)
				height = height + Help.GAP
			end

			out[#out + 1] = light(line)
			height = height + wrapped(bare, chars) * Help.LINE
		end
	end

	return title, table.concat(out, "\n"), height
end

-- the height of the whole panel for a body `body_h` high (the title band above it, the footer under it)
Help.panel_height = function (body_h)
	return Help.BODY_Y + body_h + Help.FOOT
end

return Help
