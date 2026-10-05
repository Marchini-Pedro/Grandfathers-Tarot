-- UI building blocks for the wave editor: colours, pass builders (text, hotspot,
-- button, checkbox) and the input popup (numbers or free text).
-- Adapted from RealmsEvent's view_components.lua (same vanilla templates), with:
--   * a per-pass visibility flag so one row blueprint can serve every screen,
--   * button labels held in content so rows can change them,
--   * the popup generalised from numbers-only to numbers or text.
local mod = get_mod("GrandfathersTarot")

local UIWidget = require("scripts/managers/ui/ui_widget")
local TextInputPassTemplates = require("scripts/ui/pass_templates/text_input_pass_templates")
local UISoundEvents = require("scripts/settings/ui/ui_sound_events")

local Components = {}

-- Darktide colour format { alpha, r, g, b }
-- The Plague Tarot palette (catalog/cards.lua, the reference page): ground #0a0c07, panel #12160c, bone #e6dfc3, muted
-- #98936f, bile #b7c23a (what used to be gold: titles, values, the check mark), line #3a4421
Components.colors = {
	text = { 255, 230, 223, 195 },
	muted = { 255, 152, 147, 111 },
	gold = { 255, 183, 194, 58 },
	title = { 255, 183, 194, 58 },
	normal = { 235, 24, 30, 16 },
	hover = { 250, 42, 52, 26 },
	selected = { 245, 51, 64, 33 },
	disabled = { 150, 28, 32, 22 },
	panel = { 225, 18, 22, 12 },
	frame = { 200, 76, 88, 45 },
}

local function clone_color(color)
	return { color[1], color[2], color[3], color[4] }
end

Components.clone_color = clone_color

-- Writes into an existing colour table (no per-frame allocation).
local function color_into(target, source)
	target[1], target[2], target[3], target[4] = source[1], source[2], source[3], source[4]

	return target
end

Components.color_into = color_into

-- The engine calls visibility_function(pass_content, style) where pass_content is
-- content[content_id] for passes that have a content_id (hotspots!) and the widget
-- content for all others (ui_widget.lua:411-446). For hotspot passes the widget
-- content is reachable as pass_content.parent (set by the engine, :417-418).
-- Reading the flag from the wrong table made every flagged hotspot invisible, so
-- rows had no hover and their buttons never fired (1.2.1).
local function root_content(content)
	return content.parent or content
end

local function flag_visible(flag)
	if not flag then
		return nil
	end

	return function (content)
		return root_content(content)[flag] == true
	end
end

function Components.text_pass(passes, style_id, value_id, offset, size, font_size, color, horizontal_alignment, flag)
	passes[#passes + 1] = {
		value_id = value_id,
		style_id = style_id,
		pass_type = "text",
		value = "",
		style = {
			font_type = "proxima_nova_bold",
			font_size = font_size,
			text_color = clone_color(color),
			text_horizontal_alignment = horizontal_alignment or "left",
			text_vertical_alignment = "center",
			size = size,
			offset = offset,
		},
		visibility_function = flag_visible(flag),
	}
end

-- `quiet` = no sound when the pointer comes over it (the ten chance pips of a card: sliding along them would tick ten times)
function Components.hotspot_pass(passes, content_id, offset, size, flag, quiet)
	passes[#passes + 1] = {
		pass_type = "hotspot",
		content_id = content_id,
		style_id = content_id,
		content = {
			on_hover_sound = not quiet and UISoundEvents.default_mouse_hover or nil,
			on_pressed_sound = UISoundEvents.default_click,
		},
		style = {
			size = size,
			offset = offset,
		},
		visibility_function = flag_visible(flag),
	}
end

-- ---------------------------------------------------------------------------
-- The button family (docs/08-workshop-redesign.md): standard, primary, danger, quiet, chip, tab and icon buttons, the stepper
-- (one plate) and the diamond check. Every part is a rect, a triangle or a rotated rect (no textures: nothing to blur at
-- another resolution); the colours are worked out per frame into the style's own tables (no allocation while drawing).
-- ---------------------------------------------------------------------------
mod.rw_button_palette = mod.rw_button_palette or { plate = { 22, 27, 14 }, down = { 12, 15, 8 }, frame = { 58, 68, 33 }, text = { 230, 223, 195 } }
local PLATE, PLATE_DOWN, PLATE_OFF = mod.rw_button_palette.plate, mod.rw_button_palette.down, { 16, 19, 10 }
local FRAME, FRAME_OFF = mod.rw_button_palette.frame, { 38, 43, 24 }
local TEXT, BRIGHT, LABEL_OFF, MUTED = mod.rw_button_palette.text, { 244, 239, 214 }, { 95, 93, 72 }, { 152, 147, 111 }
local GROUND, WHITE, BLACK = { 10, 12, 7 }, { 255, 255, 255 }, { 0, 0, 0 }
local RUST, RUST_TEXT, RUST_BRIGHT = { 194, 122, 44 }, { 226, 164, 104 }, { 242, 199, 150 }
local PRIMARY_OFF, PRIMARY_LABEL_OFF = { 43, 48, 23 }, { 107, 106, 80 }

-- plain {r, g, b}, for the code that draws the other parts of the workshop in the same colours
Components.rgb = {
	plate = PLATE, plate_down = PLATE_DOWN, plate_off = PLATE_OFF, frame = FRAME, frame_off = FRAME_OFF, text = TEXT, bright = BRIGHT,
	label_off = LABEL_OFF, muted = MUTED, ground = GROUND, rust = RUST,
}

-- The accent of the buttons: bile everywhere, the suit's accent inside a card's screens (the view sets it, see
-- GrandfathersTarotView._apply_screen). Read every frame by the change functions below.
-- The table lives on the mod object: the view, the blueprints and the definitions each load this file with io_dofile (three
-- copies of Components), and the buttons built by one must see the accent set by another. Changed in place, never replaced.
Components.BILE = { 183, 194, 58 }
mod.rw_accent = mod.rw_accent or { 183, 194, 58 }
Components.accent = mod.rw_accent

function Components.set_accent(rgb)
	local accent = Components.accent

	accent[1], accent[2], accent[3] = rgb[1], rgb[2], rgb[3]
end

-- The page theme. On a card's own screens (the Cauldron, the picker, Mods, Custom and the Mirror) the whole page takes the colours of the
-- card's face, its suit: the ground, the panels, the rows and their frames (set_theme, called by the view with the card's suit);
-- everywhere else it is the Plague palette this mod always had (what Components.THEME_DEFAULT holds, the Plague suit's own numbers).
-- Shared through the mod object like the accent and read by the static widgets every frame, never copied, so a suit that is changed
-- on the page recolours it at once.
local THEME_DEFAULT = {
	ground = { 30, 32, 28 }, -- what the background texture is multiplied with
	panel = { 18, 22, 12 }, -- the table and bottom panels
	row = { 24, 30, 16 }, -- a row at rest
	hi = { 42, 52, 26 }, -- a row under the pointer, before the accent is mixed in
	frame = { 58, 68, 33 }, -- the line round a row and a panel
}

Components.THEME_DEFAULT = THEME_DEFAULT
mod.rw_theme = mod.rw_theme or { ground = { 30, 32, 28 }, panel = { 18, 22, 12 }, row = { 24, 30, 16 }, hi = { 42, 52, 26 }, frame = { 58, 68, 33 } }
Components.theme = mod.rw_theme

local function scale_into(out, rgb, k)
	out[1], out[2], out[3] = math.floor(rgb[1] * k + 0.5), math.floor(rgb[2] * k + 0.5), math.floor(rgb[3] * k + 0.5)
end

-- `suit` = a suit of catalog/cards.lua ({ card, hi, frame, accent ... } as {r, g, b}), or nil for the default look. Changes the tables
-- in place. The suit's face colour is the ground; the panel and the rows are darker steps of it (the factors keep the Plague suit at
-- the default numbers: 0.65 and 0.8 of its card colour), the hover and the frames are the suit's own.
function Components.set_theme(suit)
	local theme = Components.theme
	local source = suit or { card = { 22, 27, 14 }, hi = { 12, 15, 8 }, frame = { 58, 68, 33 }, text = { 230, 223, 195 } }
	scale_into(PLATE, source.card, 1)
	scale_into(PLATE_DOWN, source.hi, 0.65)
	scale_into(FRAME, source.frame, 1)
	scale_into(TEXT, source.text, 1)

	if suit then
		scale_into(theme.ground, suit.card, 1)
		scale_into(theme.panel, suit.card, 0.65)
		scale_into(theme.row, suit.card, 0.8)
		scale_into(theme.hi, suit.hi, 1)
		scale_into(theme.frame, suit.frame, 1)
		Components.set_accent(suit.accent)
	else
		for key, rgb in pairs(THEME_DEFAULT) do
			scale_into(theme[key], rgb, 1)
		end

		Components.set_accent(Components.BILE)
	end
end

local function put_rgb(out, alpha, rgb)
	out[1], out[2], out[3], out[4] = alpha, rgb[1], rgb[2], rgb[3]
end

local function put_mix(out, alpha, a, b, t)
	out[1], out[2], out[3], out[4] = alpha, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
end

Components.put_rgb, Components.put_mix = put_rgb, put_mix

local REST, HOVER, DOWN, OFF = 0, 1, 2, 3

-- what a button is doing: resting, under the pointer, pressed (held under the pointer) or disabled
local function state_of(hotspot)
	if hotspot.disabled then
		return OFF
	elseif hotspot.is_hover then
		return hotspot.is_held and DOWN or HOVER
	end

	return REST
end

Components.state_of = state_of
Components.STATE = { REST = REST, HOVER = HOVER, DOWN = DOWN, OFF = OFF }

-- `on` is the button's own flag (content[content_id .. "_on"]): a lit chip, the armed "Sure?" of a danger button, the
-- selected tab.
local function paint_fill(out, role, st, accent, on)
	if role == "primary" then
		if st == OFF then
			put_rgb(out, 255, PRIMARY_OFF)
		elseif st == DOWN then
			put_mix(out, 255, accent, BLACK, 0.26)
		elseif st == HOVER then
			put_mix(out, 255, accent, WHITE, 0.24)
		else
			put_rgb(out, 255, accent)
		end
	elseif role == "danger" then
		if on and st ~= OFF then
			put_rgb(out, 255, RUST)
		elseif st == OFF then
			put_rgb(out, 255, PLATE_OFF)
		elseif st == DOWN then
			put_mix(out, 255, PLATE_DOWN, RUST, 0.12)
		elseif st == HOVER then
			put_mix(out, 255, PLATE, RUST, 0.20)
		else
			put_rgb(out, 255, PLATE)
		end
	elseif role == "quiet" then
		-- transparent, a wash of the accent under the pointer
		put_rgb(out, st == DOWN and 24 or st == HOVER and 38 or 0, accent)
	elseif role == "tab" then
		if st == OFF then
			put_rgb(out, 255, PLATE_OFF)
		elseif on then
			put_mix(out, 255, PLATE, accent, 0.16)
		elseif st == HOVER or st == DOWN then
			put_mix(out, 255, PLATE, accent, 0.10)
		else
			put_rgb(out, 255, PLATE)
		end
	else -- standard, chip, icon
		if st == OFF then
			put_rgb(out, 255, PLATE_OFF)
		elseif st == DOWN then
			put_mix(out, 255, PLATE_DOWN, accent, 0.07)
		elseif st == HOVER then
			put_mix(out, 255, PLATE, accent, 0.14)
		else
			put_rgb(out, 255, PLATE)
		end
	end
end

local function paint_frame(out, role, st, accent, on)
	if role == "primary" then
		paint_fill(out, role, st, accent, on)
	elseif role == "danger" then
		if st == OFF then
			put_rgb(out, 255, FRAME_OFF)
		elseif on or st ~= REST then
			put_rgb(out, 255, RUST)
		else
			put_mix(out, 255, FRAME, RUST, 0.5)
		end
	elseif role == "quiet" then
		if st == OFF then
			put_rgb(out, 255, FRAME_OFF)
		elseif st ~= REST then
			put_rgb(out, 255, accent)
		else
			put_rgb(out, 255, FRAME)
		end
	elseif role == "tab" then
		put_rgb(out, 255, st == OFF and FRAME_OFF or FRAME)
	else -- standard, chip, icon
		if st == OFF then
			put_rgb(out, 255, FRAME_OFF)
		elseif st ~= REST then
			put_rgb(out, 255, accent)
		elseif on then
			put_mix(out, 255, FRAME, accent, 0.55)
		else
			put_rgb(out, 255, FRAME)
		end
	end
end

local function paint_label(out, role, st, accent, on)
	if role == "primary" then
		put_rgb(out, 255, st == OFF and PRIMARY_LABEL_OFF or GROUND)
	elseif role == "danger" then
		if st == OFF then
			put_rgb(out, 255, LABEL_OFF)
		elseif on then
			put_rgb(out, 255, GROUND)
		elseif st ~= REST then
			put_rgb(out, 255, RUST_BRIGHT)
		else
			put_rgb(out, 255, RUST_TEXT)
		end
	elseif role == "quiet" then
		if st == OFF then
			put_rgb(out, 255, LABEL_OFF)
		elseif st ~= REST then
			put_rgb(out, 255, BRIGHT)
		else
			put_rgb(out, 255, accent)
		end
	elseif role == "tab" then
		if st == OFF then
			put_rgb(out, 255, LABEL_OFF)
		elseif on then
			put_rgb(out, 255, BRIGHT)
		elseif st ~= REST then
			put_rgb(out, 255, TEXT)
		else
			put_rgb(out, 255, MUTED)
		end
	else -- standard, chip, icon
		if st == OFF then
			put_rgb(out, 255, LABEL_OFF)
		elseif st ~= REST or on then
			put_rgb(out, 255, BRIGHT)
		else
			put_rgb(out, 255, TEXT)
		end
	end
end

Components.paint_fill, Components.paint_frame, Components.paint_label = paint_fill, paint_frame, paint_label

local BRACKET = 9 -- length of a corner bracket, its thickness is 2
local BRACKET_OUT = 4 -- how far outside the frame it sits at rest on hover (1 when pressed)

local function rect_pass(passes, style_id, x, y, w, h, z, visibility, change)
	passes[#passes + 1] = {
		pass_type = "rect",
		style_id = style_id,
		style = { offset = { x, y, z }, size = { w, h }, color = { 255, 255, 255, 255 } },
		visibility_function = visibility,
		change_function = change,
	}
end

-- A triangle slightly larger than `corners` ({ {x, y} x3 }, relative to its offset): the faint copy that stands in for
-- anti-aliasing (see docs/08, section 3)
local function grown(corners, by)
	local cx, cy = (corners[1][1] + corners[2][1] + corners[3][1]) / 3, (corners[1][2] + corners[2][2] + corners[3][2]) / 3
	local out = {}

	for i = 1, 3 do
		local dx, dy = corners[i][1] - cx, corners[i][2] - cy
		local length = math.sqrt(dx * dx + dy * dy)

		out[i] = { corners[i][1] + dx / length * by, corners[i][2] + dy / length * by }
	end

	return out
end

local function glyph_corners(kind, w, h)
	local cx, cy = w / 2, h / 2

	if kind == "up" then
		return { { cx - 8, cy + 5 }, { cx + 8, cy + 5 }, { cx, cy - 5 } }
	end

	return { { cx - 8, cy - 5 }, { cx + 8, cy - 5 }, { cx, cy + 5 } }
end

-- A diamond (a square turned 45 degrees) centred at (cx, cy) with a faint larger copy under it. `paint(color, content,
-- halo)` writes the colour of the diamond (halo = true for the copy, whose opacity should be about a third).
function Components.diamond_passes(passes, id, cx, cy, side, z, visibility, paint)
	for i = 1, 2 do
		local halo = i == 1
		local s = halo and side + 1.1 or side

		passes[#passes + 1] = {
			pass_type = "rotated_rect",
			style_id = halo and (id .. "_h") or id,
			style = { offset = { cx - s / 2, cy - s / 2, halo and z - 0.5 or z }, size = { s, s }, color = { 255, 255, 255, 255 }, angle = math.pi / 4, pivot = { s / 2, s / 2 } },
			visibility_function = visibility,
			change_function = function (content, style)
				paint(style.color, content, halo)
			end,
		}
	end
end

-- Button (`opts`): label, font_size, flag (the visibility flag of the content), role ("standard" (default), "primary",
-- "danger", "quiet", "chip", "tab", "icon"), pip (a small diamond before the label, lit with the button's `_on` flag),
-- glyph ("up" or "down": a triangle instead of the label), brackets = false (no corner brackets: a small button of a role that
-- has them). The label lives in content[content_id .. "_text"], the
-- button's own flag in content[content_id .. "_on"].
function Components.button(passes, content_id, offset, size, opts)
	opts = opts or {}

	local role = opts.role or "standard"
	local x, y, z = offset[1], offset[2], offset[3] or 0
	local w, h = size[1], size[2]
	local visible = flag_visible(opts.flag)
	local on_key = content_id .. "_on"
	local accent = Components.accent

	Components.hotspot_pass(passes, content_id, offset, size, opts.flag)

	local function shown(content)
		return visible == nil or visible(content)
	end

	if role == "quiet" then
		rect_pass(passes, content_id .. "_fill", x, y, w, h, z, visible, function (content, style)
			paint_fill(style.color, role, state_of(content[content_id]), accent, content[on_key])
		end)
		rect_pass(passes, content_id .. "_line", x, y + h - 1, w, 1, z + 1, visible, function (content, style)
			local st = state_of(content[content_id])

			paint_frame(style.color, role, st, accent, content[on_key])
			style.offset[2], style.size[2] = (st == HOVER or st == DOWN) and y + h - 2 or y + h - 1, (st == HOVER or st == DOWN) and 2 or 1
		end)
	else
		-- the frame is the outer rect, the fill sits one unit inside it
		rect_pass(passes, content_id .. "_frame", x, y, w, h, z, visible, function (content, style)
			paint_frame(style.color, role, state_of(content[content_id]), accent, content[on_key])
		end)
		rect_pass(passes, content_id .. "_fill", x + 1, y + 1, w - 2, h - 2, z + 1, visible, function (content, style)
			paint_fill(style.color, role, state_of(content[content_id]), accent, content[on_key])
		end)
	end

	if role == "tab" then
		rect_pass(passes, content_id .. "_bar", x, y + h - 3, w, 3, z + 2, function (content)
			return shown(content) and content[on_key] == true
		end, function (content, style)
			put_rgb(style.color, 255, accent)
		end)
	end

	if (role == "standard" or role == "primary" or role == "danger") and opts.brackets ~= false then
		-- two corner brackets (top left, bottom right), 4 units outside the frame under the pointer, 1 unit when pressed
		local armed_shows = role == "danger"

		local function bracket_visible(content)
			local st = state_of(content[content_id])

			return shown(content) and st ~= OFF and (st == HOVER or st == DOWN or (armed_shows and content[on_key] == true))
		end

		local function bracket_paint(content, style)
			put_rgb(style.color, 255, role == "danger" and RUST or accent)
		end

		local function place(id, ox, oy, bw, bh, inward_x, inward_y)
			rect_pass(passes, content_id .. id, x + ox, y + oy, bw, bh, z + 4, bracket_visible, function (content, style)
				bracket_paint(content, style)

				local d = state_of(content[content_id]) == DOWN and 3 or 0

				style.offset[1], style.offset[2] = x + ox + d * inward_x, y + oy + d * inward_y
			end)
		end

		place("_b1", -BRACKET_OUT, -BRACKET_OUT, BRACKET, 2, 1, 1)
		place("_b2", -BRACKET_OUT, -BRACKET_OUT, 2, BRACKET, 1, 1)
		place("_b3", w + BRACKET_OUT - BRACKET, h + BRACKET_OUT - 2, BRACKET, 2, -1, -1)
		place("_b4", w + BRACKET_OUT - 2, h + BRACKET_OUT - BRACKET, 2, BRACKET, -1, -1)
	end

	local label_x, label_w = x, w

	if opts.pip then
		-- a small diamond before the label: lit while the button's flag is on
		local side = 7
		local pip_x = x + 14

		Components.diamond_passes(passes, content_id .. "_pip", pip_x, y + h / 2, side, z + 3, visible, function (color, content, halo)
			local st = state_of(content[content_id])

			if content[on_key] == true and st ~= OFF then
				put_rgb(color, halo and 80 or 255, accent)
			else
				put_rgb(color, halo and 24 or 90, st == OFF and LABEL_OFF or MUTED)
			end
		end)

		label_x, label_w = x + 10, w - 10
	end

	if opts.glyph then
		local corners = glyph_corners(opts.glyph, w, h)

		for i = 1, 2 do
			local halo = i == 1

			passes[#passes + 1] = {
				pass_type = "triangle",
				style_id = content_id .. (halo and "_glyph_h" or "_glyph"),
				style = { offset = { x, y, halo and z + 2.5 or z + 3 }, color = { 255, 255, 255, 255 }, triangle_corners = halo and grown(corners, 0.55) or corners },
				visibility_function = visible,
				change_function = function (content, style)
					local st = state_of(content[content_id])

					paint_label(style.color, role, st, accent, content[on_key])

					if halo then
						style.color[1] = 77
					end
				end,
			}
		end

		return
	end

	passes[#passes + 1] = {
		style_id = content_id .. "_label",
		value_id = content_id .. "_text",
		pass_type = "text",
		value = opts.label or "",
		style = {
			font_type = "proxima_nova_bold",
			font_size = opts.font_size or 22,
			text_color = { 255, 255, 255, 255 },
			text_horizontal_alignment = "center",
			text_vertical_alignment = "center",
			size = { label_w, h },
			offset = { label_x, y, z + 5 },
		},
		change_function = function (content, style)
			local st = state_of(content[content_id])

			paint_label(style.text_color, role, st, accent, content[on_key])
			style.offset[2] = y + (st == DOWN and 2 or 0)
		end,
		visibility_function = visible,
	}
end

-- The old call: kept for the places that have not named a role (the label colour is the role's now).
function Components.button_passes(passes, content_id, offset, size, label, font_size, label_color, flag, role)
	Components.button(passes, content_id, offset, size, { label = label, font_size = font_size, flag = flag, role = role })
end

-- Diamond check: a diamond that is lit (the accent) when content[selected_key] (default "checkbox_selected"), dimmed
-- when it is not, and brighter while the pointer is on `hover_id` (the hotspot of the box, optional). `flag` as above.
-- `id` (default "checkbox") prefixes the style ids so one widget can hold several checkboxes.
function Components.checkbox_passes(passes, offset, size, flag, id, selected_key, hover_id)
	size = size or { 28, 28 }
	id = id or "checkbox"
	selected_key = selected_key or "checkbox_selected"

	local accent = Components.accent
	local visible = flag_visible(flag)

	Components.diamond_passes(passes, id, offset[1] + size[1] / 2, offset[2] + size[2] / 2, 13, (offset[3] or 0) + 1, visible, function (color, content, halo)
		local hover = hover_id and content[hover_id] and content[hover_id].is_hover

		if content[selected_key] == true then
			put_rgb(color, halo and 80 or 255, accent)
		else
			put_rgb(color, halo and (hover and 40 or 24) or (hover and 150 or 80), hover and accent or MUTED)
		end
	end)
end

-- Stepper: one plate with the minus, the clickable value and the plus, prefixed by `prefix`
-- ("hotspot" gives hotspot_minus / hotspot_value / hotspot_plus and stepper_value).
-- `ids` (optional) renames the hotspots/text so a widget can hold several steppers:
-- { minus = "hotspot_rep_minus", value = "hotspot_rep_value", plus = "hotspot_rep_plus", text = "rep_value" }.
-- content[<text id> .. "_dim"] = true dims the whole plate (a value that is not used).
function Components.stepper_passes(passes, layout, flag, ids)
	ids = ids or {}

	local button_size = layout.button_size or { 44, 40 }
	local text_id = ids.text or "stepper_value"
	local minus_id, value_id, plus_id = ids.minus or "hotspot_minus", ids.value or "hotspot_value", ids.plus or "hotspot_plus"
	local dim_key = text_id .. "_dim"
	local accent = Components.accent
	local visible = flag_visible(flag)

	local x, y, z = layout.minus_offset[1], layout.minus_offset[2], layout.minus_offset[3] or 0
	local bw, h = button_size[1], button_size[2]
	local right = layout.plus_offset[1] + bw
	local w = right - x
	local plus_x = layout.plus_offset[1]

	local function dim(content)
		return content[dim_key] == true
	end

	Components.hotspot_pass(passes, minus_id, layout.minus_offset, button_size, flag)
	Components.hotspot_pass(passes, value_id, layout.value_offset, layout.value_size, flag)
	Components.hotspot_pass(passes, plus_id, layout.plus_offset, button_size, flag)

	-- the plate: frame, fill, and the two dividers
	rect_pass(passes, text_id .. "_frame", x, y, w, h, z, visible, function (content, style)
		put_rgb(style.color, 255, dim(content) and FRAME_OFF or FRAME)
	end)
	rect_pass(passes, text_id .. "_plate", x + 1, y + 1, w - 2, h - 2, z + 1, visible, function (content, style)
		put_rgb(style.color, 255, dim(content) and PLATE_OFF or PLATE)
	end)
	rect_pass(passes, text_id .. "_div1", x + bw, y + 1, 1, h - 2, z + 2, visible, function (content, style)
		put_rgb(style.color, 255, dim(content) and FRAME_OFF or FRAME)
	end)
	rect_pass(passes, text_id .. "_div2", plus_x - 1, y + 1, 1, h - 2, z + 2, visible, function (content, style)
		put_rgb(style.color, 255, dim(content) and FRAME_OFF or FRAME)
	end)

	-- one unit edges (2026-10-04: the user found the two unit ones too heavy)
	for _, edge in ipairs({ { "_edge_t", x, y, w, 1 }, { "_edge_b", x, y + h - 1, w, 1 }, { "_edge_l", x, y, 1, h }, { "_edge_r", right - 1, y, 1, h } }) do
		rect_pass(passes, text_id .. edge[1], edge[2], edge[3], edge[4], edge[5], z + 3, visible, function (content, style)
			put_rgb(style.color, 255, dim(content) and FRAME_OFF or FRAME)
		end)
	end

	-- the cells light up under the pointer
	for _, cell in ipairs({ { minus_id, x + 1, bw - 1, "_hl1" }, { plus_id, plus_x, bw - 1, "_hl2" } }) do
		rect_pass(passes, text_id .. cell[4], cell[2], y + 1, cell[3], h - 2, z + 2, function (content)
			return (visible == nil or visible(content)) and not dim(content) and state_of(content[cell[1]]) ~= REST and state_of(content[cell[1]]) ~= OFF
		end, function (content, style)
			local down = state_of(content[cell[1]]) == DOWN

			put_mix(style.color, 255, down and PLATE_DOWN or PLATE, accent, down and 0.07 or 0.16)
		end)
	end

	-- the signs: a bar for the minus, two bars for the plus
	local sign_y = y + h / 2
	local minus_x = x + bw / 2 + 0.5
	local plus_cx = plus_x + bw / 2

	local function sign_color(hotspot_id)
		return function (content, style)
			local st = state_of(content[hotspot_id])

			if dim(content) or st == OFF then
				put_rgb(style.color, 255, LABEL_OFF)
			elseif st ~= REST then
				put_rgb(style.color, 255, accent)
			else
				put_rgb(style.color, 255, TEXT)
			end
		end
	end

	local sign = layout.sign or 7 -- half the length of a sign (the compact steppers of the rows use 6)

	rect_pass(passes, text_id .. "_minus", minus_x - sign, sign_y - 1, 2 * sign, 2, z + 3, visible, sign_color(minus_id))
	rect_pass(passes, text_id .. "_plus_h", plus_cx - sign, sign_y - 1, 2 * sign, 2, z + 3, visible, sign_color(plus_id))
	rect_pass(passes, text_id .. "_plus_v", plus_cx - 1, sign_y - sign, 2, 2 * sign, z + 3, visible, sign_color(plus_id))

	-- the value, and a line under it while the pointer is on it (a click opens the number box)
	passes[#passes + 1] = {
		value_id = text_id,
		style_id = text_id,
		pass_type = "text",
		value = "",
		style = {
			font_type = "proxima_nova_bold",
			font_size = layout.font_size or 22,
			text_color = { 255, 255, 255, 255 },
			text_horizontal_alignment = "center",
			text_vertical_alignment = "center",
			size = { layout.value_size[1], layout.value_size[2] + 6 },
			offset = { layout.value_offset[1], layout.value_offset[2], z + 4 },
		},
		change_function = function (content, style)
			if dim(content) then
				put_rgb(style.text_color, 255, LABEL_OFF)
			else
				put_rgb(style.text_color, 255, accent)
			end
		end,
		visibility_function = visible,
	}
	rect_pass(passes, text_id .. "_underline", layout.value_offset[1] + layout.value_size[1] / 2 - 14, y + h - 9, 28, 1, z + 4, function (content)
		return (visible == nil or visible(content)) and not dim(content) and state_of(content[value_id]) == HOVER
	end, function (content, style)
		put_rgb(style.color, 255, accent)
	end)
end

-- A frame of four rects (`thickness` units, default 1) around a w x h box at the node's origin, in the accent (or the
-- fixed `rgb`, with `alpha`), and optionally the two corner brackets of the buttons, `out` units outside it (default 5), `len`
-- long (default 14) and `bracket` thick (default 3). Style ids: <prefix>_t, _b, _l, _r, and _k1.._k4 for the brackets.
function Components.frame_passes(passes, prefix, w, h, z, opts)
	opts = opts or {}

	local t = opts.thickness or 1
	local rgb, alpha = opts.rgb, opts.alpha or 255

	local function color(content, style)
		put_rgb(style.color, alpha, rgb or Components.accent)
	end

	rect_pass(passes, prefix .. "_t", 0, 0, w, t, z, nil, color)
	rect_pass(passes, prefix .. "_b", 0, h - t, w, t, z, nil, color)
	rect_pass(passes, prefix .. "_l", 0, 0, t, h, z, nil, color)
	rect_pass(passes, prefix .. "_r", w - t, 0, t, h, z, nil, color)

	if opts.brackets then
		local out, len, bt = opts.out or 5, opts.len or 14, opts.bracket or 3

		rect_pass(passes, prefix .. "_k1", -out, -out, len, bt, z + 1, nil, color)
		rect_pass(passes, prefix .. "_k2", -out, -out, bt, len, z + 1, nil, color)
		rect_pass(passes, prefix .. "_k3", w + out - len, h + out - bt, len, bt, z + 1, nil, color)
		rect_pass(passes, prefix .. "_k4", w + out - bt, h + out - len, bt, len, z + 1, nil, color)
	end
end

-- ---------------------------------------------------------------------------
-- Input popup (numbers or text)
-- ---------------------------------------------------------------------------
Components.POPUP_PANEL_NAME = "rw_popup_panel"
Components.POPUP_INPUT_NAME = "rw_popup_input"
Components.POPUP_CONFIRM_NAME = "rw_popup_confirm"
Components.POPUP_CANCEL_NAME = "rw_popup_cancel"
Components.POPUP_INPUT_SIZE = { 720, 46 }
Components.POPUP_BUTTON_WIDTH, Components.POPUP_BUTTON_HEIGHT = 200, 48

-- Text input widget definition (vanilla template, focus behaviour adjusted).
Components.popup_input_definition = function ()
	local passes = table.clone_instance(TextInputPassTemplates.simple_input_field)

	for _, pass in ipairs(passes) do
		if pass.pass_type == "hotspot" then
			pass.change_function = function (hotspot)
				if hotspot.on_pressed then
					hotspot.parent.is_writing = true
				end

				hotspot.double_click_timer = 0
			end
		elseif pass.style_id == "limit_text" then
			pass.visibility_function = function ()
				return false
			end
		elseif pass.style_id == "focused" then
			pass.visibility_function = function (content)
				return content.is_writing
			end
		elseif pass.style_id == "display_text" then
			pass.style.font_type = "proxima_nova_bold"
			pass.style.font_size = 24
		end
	end

	return UIWidget.create_definition(passes, Components.POPUP_INPUT_NAME, {
		input_text = "",
		max_length = 16,
		close_on_backspace = false,
	}, Components.POPUP_INPUT_SIZE)
end

local POPUP = {}

Components.Popup = POPUP

local POPUP_DEFAULT_Y, POPUP_DEFAULT_X = 400, 560
local POPUP_W, POPUP_H, POPUP_GRIP_H = 800, 260, 56 -- the title strip (above the input) is where the panel is dragged
-- a popup that filters a list as you type (spec.allow_rows) is see-through, so the rows stay readable under it
POPUP.SEE_THROUGH_ALPHA, POPUP.SOLID_ALPHA = 170, 245

-- Moves the four popup nodes so the panel's top left corner is at (x, y), kept on the screen.
local function place_popup(view, y, x)
	x = math.max(0, math.min(1920 - POPUP_W, x or POPUP_DEFAULT_X))
	y = math.max(0, math.min(1080 - POPUP_H, y))

	view:_set_scenegraph_position(Components.POPUP_PANEL_NAME, x, y, 45)
	view:_set_scenegraph_position(Components.POPUP_INPUT_NAME, x + 40, y + 70, 50)
	-- OK and Cancel on the right of the panel, Cancel on the left of OK, 30 from the edge
	view:_set_scenegraph_position(Components.POPUP_CONFIRM_NAME, x + 570, y + 196, 50)
	view:_set_scenegraph_position(Components.POPUP_CANCEL_NAME, x + 350, y + 196, 50)

	if view._popup then
		view._popup.x, view._popup.y = x, y
	end
end

POPUP.place = place_popup

-- spec = { label, value (string), max_length, set(value_or_text),
--          numeric = true -> min, max, integer, value is parsed and range-checked
--          validate = function(text) -> ok, error_message  (text mode, optional)
--          hint = text under the input (optional)
--          y = top edge of the popup (optional; lets a list stay visible above it)
--          always_commit = true -> OK runs `set` even when the text was not changed (a prefilled box)
--          on_change = function(text)  called whenever the typed text changes (live filtering)
--          on_cancel = function()      called when the popup closes WITHOUT confirming }
function POPUP.open(view, spec)
	POPUP.cancel(view)

	local text = tostring(spec.value or "")

	view._popup = { spec = spec, original = text, last_text = text, error = nil }
	view.is_text_input_focused = true

	-- DMF checks every mod's keybinds from the raw keyboard each frame and knows nothing about text
	-- fields, so typing "i" would open the inventory (hub_hotkey_menus) etc. The entry script hooks
	-- dmf.check_keybinds and skips it while this flag is set.
	if mod.rw then
		mod.rw.text_input_active = true
	end

	-- a movable popup opens where the player last dragged it (spec.place_key names the remembered spot)
	local spot = spec.place_key and view._popup_spots and view._popup_spots[spec.place_key]

	place_popup(view, spot and spot[2] or spec.y or POPUP_DEFAULT_Y, spot and spot[1] or spec.x)

	local panel = view._widgets_by_name[Components.POPUP_PANEL_NAME]

	if panel and panel.style.fill then
		panel.style.fill.color[1] = spec.allow_rows and POPUP.SEE_THROUGH_ALPHA or POPUP.SOLID_ALPHA
	end

	local content = view._widgets_by_name[Components.POPUP_INPUT_NAME].content

	content.max_length = spec.max_length or 16
	content.input_text = text
	content.display_text = text
	content._input_text = text
	content.caret_position = #text + 1
	content._caret_position = #text + 1
	content.selected_text = text
	content._selection_start = 1
	content._selection_end = #text + 1
	content._selection_changed = true
	content._is_selecting = nil
	content.last_input = nil
	content._input_text_first_visible_pos = 1
	content.force_caret_update = true
	content._blink_time = 0
	content.is_writing = true

	view:_set_interaction_enabled()
	POPUP.refresh(view)
end

-- Replaces the box's text, caret at the end (used to fill in characters typed before the box opened).
function POPUP.set_text(view, text)
	local content = view._widgets_by_name[Components.POPUP_INPUT_NAME].content

	content.input_text = text
	content.display_text = text
	content._input_text = text
	content.caret_position = #text + 1
	content._caret_position = #text + 1
	content.selected_text = nil
	content._selection_start = nil
	content._selection_end = nil
	content._selection_changed = true
	content.force_caret_update = true
end

local function parse_number(text, spec)
	text = text:match("^%s*(.-)%s*$")

	if not (text:match("^[+-]?%d+%.?%d*$") or text:match("^[+-]?%.%d+$")) then
		return nil
	end

	local value = tonumber(text)

	if not value or value ~= value or value < spec.min or value > spec.max then
		return nil
	end

	if spec.integer and value % 1 ~= 0 then
		return nil
	end

	return value
end

-- Commit: valid -> spec.set(value) and close; invalid -> keep open with an error line.
function POPUP.commit(view)
	local edit = view._popup

	if not edit then
		return false
	end

	local spec = edit.spec
	local text = view._widgets_by_name[Components.POPUP_INPUT_NAME].content.input_text or ""

	if text == edit.original and not spec.always_commit then
		POPUP.cancel(view)

		return true
	end

	local value

	if spec.numeric then
		value = parse_number(text, spec)

		if not value then
			edit.error = mod:localize("popup_number_error", spec.min, spec.max)
			POPUP.refresh(view)

			return false
		end
	else
		value = text

		if spec.validate then
			local ok, message = spec.validate(text)

			if not ok then
				edit.error = tostring(message)
				POPUP.refresh(view)

				return false
			end
		end
	end

	edit.committed = true
	POPUP.cancel(view)
	spec.set(value)

	return true
end

-- Closes the popup WITHOUT undoing anything (no on_cancel): used when the user clicked something
-- else on purpose while a live popup (the search box) was open.
function POPUP.close_keep(view)
	local edit = view._popup

	if edit then
		edit.committed = true
	end

	return POPUP.cancel(view)
end

function POPUP.cancel(view)
	local edit = view._popup

	if not edit then
		return false
	end

	view._popup = nil
	view.is_text_input_focused = false

	if mod.rw then
		mod.rw.text_input_active = false
	end

	-- the view may keep keybinds suspended anyway (enemy picker: any letter starts a search)
	if view._refresh_text_flag then
		view:_refresh_text_flag()
	end

	place_popup(view, POPUP_DEFAULT_Y)

	if edit.spec.on_cancel and not edit.committed then
		edit.spec.on_cancel()
	end

	local content = view._widgets_by_name[Components.POPUP_INPUT_NAME].content

	content.is_writing = false
	content.selected_text = nil
	content._selection_start = nil
	content._selection_end = nil

	view:_set_interaction_enabled()
	POPUP.refresh(view)

	return true
end

function POPUP.refresh(view)
	local edit = view._popup
	local visible = edit ~= nil
	local widgets = view._widgets_by_name

	for _, name in ipairs({
		Components.POPUP_PANEL_NAME,
		Components.POPUP_INPUT_NAME,
		Components.POPUP_CONFIRM_NAME,
		Components.POPUP_CANCEL_NAME,
	}) do
		local widget = widgets[name]

		if widget then
			widget.visible = visible
			widget.alpha_multiplier = visible and 1 or 0
		end
	end

	if visible then
		local spec = edit.spec
		local panel = widgets[Components.POPUP_PANEL_NAME]

		panel.content.title_text = tostring(spec.label)
		put_rgb(panel.style.title_text.text_color, 255, Components.accent)
		panel.content.hint_text = edit.error or spec.hint or mod:localize(spec.numeric and "popup_hint_number" or "popup_hint_text")

		panel.style.hint_text.text_color = clone_color(edit.error and Components.colors.gold or Components.colors.muted)

		local input_style = widgets[Components.POPUP_INPUT_NAME].style.display_text

		if input_style then
			input_style.text_color = clone_color(edit.error and Components.colors.gold or Components.colors.text)
		end
	end
end

-- Dragging the popup by its title strip (2026-10-04: the sound search box hid the names it was searching): a press on the strip
-- takes the panel, it follows the pointer while the button is held and stays where it is let go (remembered for spec.place_key).
function POPUP.drag(view, input_service)
	local edit = view._popup
	local x, y

	-- (not `a and f()`: that keeps only the first value, the y would be lost)
	if view._cursor_point then
		x, y = view:_cursor_point(input_service)
	end

	if not edit or not x then
		return
	end

	if edit.grab then
		if input_service:get("left_hold") then
			place_popup(view, y - edit.grab[2], x - edit.grab[1])
		else
			edit.grab = nil

			if edit.spec.place_key then
				view._popup_spots = view._popup_spots or {}
				view._popup_spots[edit.spec.place_key] = { edit.x, edit.y }
			end
		end
	elseif input_service:get("left_pressed") and edit.x and x >= edit.x and x <= edit.x + POPUP_W and y >= edit.y and y <= edit.y + POPUP_GRIP_H then
		edit.grab = { x - edit.x, y - edit.y }
	end
end

-- Enter commits; Esc goes through the view's back handling.
function POPUP.update(view, input_service)
	local edit = view._popup

	if not edit then
		return
	end

	if input_service.is_null_service and input_service:is_null_service() or view._input_disabled then
		POPUP.cancel(view)

		return
	end

	POPUP.drag(view, input_service)

	local on_change = edit.spec.on_change

	if on_change then
		local text = view._widgets_by_name[Components.POPUP_INPUT_NAME].content.input_text or ""

		if text ~= edit.last_text then
			edit.last_text = text
			on_change(text)
		end
	end

	if input_service:get("confirm_pressed") then
		POPUP.commit(view)
	end
end

return Components
