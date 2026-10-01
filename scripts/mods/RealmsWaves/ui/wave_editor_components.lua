-- UI building blocks for the wave editor: colours, pass builders (text, hotspot,
-- button, checkbox) and the input popup (numbers or free text).
-- Adapted from RealmsEvent's view_components.lua (same vanilla templates), with:
--   * a per-pass visibility flag so one row blueprint can serve every screen,
--   * button labels held in content so rows can change them,
--   * the popup generalised from numbers-only to numbers or text.
local mod = get_mod("RealmsWaves")

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

function Components.hotspot_pass(passes, content_id, offset, size, flag)
	passes[#passes + 1] = {
		pass_type = "hotspot",
		content_id = content_id,
		style_id = content_id,
		content = {
			on_hover_sound = UISoundEvents.default_mouse_hover,
			on_pressed_sound = UISoundEvents.default_click,
		},
		style = {
			size = size,
			offset = offset,
		},
		visibility_function = flag_visible(flag),
	}
end

-- Button with hover layers. The label lives in content[content_id .. "_text"].
-- `flag` (optional): the button only exists while content[flag] == true.
function Components.button_passes(passes, content_id, offset, size, label, font_size, label_color, flag)
	Components.hotspot_pass(passes, content_id, offset, size, flag)

	local x, y, z = offset[1], offset[2], offset[3] or 0
	local visible = flag_visible(flag)

	passes[#passes + 1] = {
		pass_type = "texture",
		value = "content/ui/materials/backgrounds/default_square",
		style_id = content_id .. "_background",
		style = {
			size = size,
			offset = { x, y, z },
			color = clone_color(Components.colors.normal),
		},
		change_function = function (content, style)
			local hotspot = content[content_id]

			color_into(style.color, hotspot.disabled and Components.colors.disabled
				or hotspot.is_hover and Components.colors.hover
				or Components.colors.normal)
		end,
		visibility_function = visible,
	}

	passes[#passes + 1] = {
		pass_type = "texture",
		value = "content/ui/materials/buttons/background_selected",
		style_id = content_id .. "_highlight",
		style = {
			size = size,
			offset = { x, y, z + 1 },
			color = { 55, 151, 167, 122 },
		},
		visibility_function = function (content)
			local hotspot = content[content_id]

			return (visible == nil or visible(content)) and not hotspot.disabled and hotspot.is_hover
		end,
	}

	passes[#passes + 1] = {
		pass_type = "texture",
		value = "content/ui/materials/frames/hover",
		style_id = content_id .. "_frame",
		style = {
			size = size,
			offset = { x, y, z + 1 },
			color = { 120, 151, 167, 152 },
		},
		visibility_function = function (content)
			local hotspot = content[content_id]

			return (visible == nil or visible(content)) and not hotspot.disabled and hotspot.is_hover
		end,
	}

	passes[#passes + 1] = {
		pass_type = "rect",
		style_id = content_id .. "_edge",
		style = {
			size = { size[1], 1 },
			offset = { x, y + size[2] - 1, z + 1 },
			color = { 160, 70, 87, 62 },
		},
		visibility_function = visible,
	}

	passes[#passes + 1] = {
		style_id = content_id .. "_label",
		value_id = content_id .. "_text",
		pass_type = "text",
		value = label or "",
		style = {
			font_type = "proxima_nova_bold",
			font_size = font_size or 26,
			text_color = clone_color(label_color or Components.colors.text),
			text_horizontal_alignment = "center",
			text_vertical_alignment = "center",
			size = size,
			offset = { x, y, z + 2 },
		},
		change_function = function (content, style)
			local hotspot = content[content_id]

			color_into(style.text_color, hotspot.disabled and Components.colors.muted
				or label_color or Components.colors.text)
		end,
		visibility_function = visible,
	}
end

-- Checkbox: frame + filled square when content[selected_key] (default "checkbox_selected").
-- `flag` as above. `id` (default "checkbox") prefixes the style ids so one widget can hold
-- several checkboxes.
function Components.checkbox_passes(passes, offset, size, flag, id, selected_key)
	size = size or { 28, 28 }
	id = id or "checkbox"
	selected_key = selected_key or "checkbox_selected"

	passes[#passes + 1] = {
		pass_type = "texture",
		value = "content/ui/materials/backgrounds/default_square",
		style_id = id .. "_frame",
		style = {
			size = size,
			offset = offset,
			color = clone_color(Components.colors.frame),
		},
		visibility_function = flag_visible(flag),
	}

	passes[#passes + 1] = {
		pass_type = "texture",
		value = "content/ui/materials/backgrounds/default_square",
		style_id = id .. "_check",
		style = {
			size = { math.max(size[1] - 6, 0), math.max(size[2] - 6, 0) },
			offset = { offset[1] + 3, offset[2] + 3, (offset[3] or 0) + 1 },
			color = clone_color(Components.colors.gold),
		},
		visibility_function = function (content)
			return content[selected_key] == true and (flag == nil or content[flag] == true)
		end, -- no content_id: receives the widget content
	}
end

-- Stepper: minus button + clickable value + plus button, prefixed by `prefix`
-- ("hotspot" gives hotspot_minus / hotspot_value / hotspot_plus and stepper_value).
-- `ids` (optional) renames the hotspots/text so a widget can hold several steppers:
-- { minus = "hotspot_rep_minus", value = "hotspot_rep_value", plus = "hotspot_rep_plus", text = "rep_value" }.
function Components.stepper_passes(passes, layout, flag, ids)
	ids = ids or {}

	local button_size = layout.button_size or { 44, 40 }
	local text_id = ids.text or "stepper_value"

	Components.button_passes(passes, ids.minus or "hotspot_minus", layout.minus_offset, button_size, "-", nil, nil, flag)
	Components.hotspot_pass(passes, ids.value or "hotspot_value", layout.value_offset, layout.value_size, flag)
	Components.text_pass(passes, text_id, text_id, layout.value_offset, {
		layout.value_size[1],
		layout.value_size[2] + 6,
	}, 22, Components.colors.gold, "center", flag)
	Components.button_passes(passes, ids.plus or "hotspot_plus", layout.plus_offset, button_size, "+", nil, nil, flag)
end

-- ---------------------------------------------------------------------------
-- Input popup (numbers or text)
-- ---------------------------------------------------------------------------
Components.POPUP_PANEL_NAME = "rw_popup_panel"
Components.POPUP_INPUT_NAME = "rw_popup_input"
Components.POPUP_CONFIRM_NAME = "rw_popup_confirm"
Components.POPUP_CANCEL_NAME = "rw_popup_cancel"
Components.POPUP_INPUT_SIZE = { 720, 46 }

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

local POPUP_DEFAULT_Y = 400

-- Moves the four popup nodes so the panel's top edge is at `y` (default: screen centre).
local function place_popup(view, y)
	view:_set_scenegraph_position(Components.POPUP_PANEL_NAME, 560, y, 45)
	view:_set_scenegraph_position(Components.POPUP_INPUT_NAME, 600, y + 70, 50)
	view:_set_scenegraph_position(Components.POPUP_CONFIRM_NAME, 600, y + 200, 50)
	view:_set_scenegraph_position(Components.POPUP_CANCEL_NAME, 870, y + 200, 50)
end

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

	place_popup(view, spec.y or POPUP_DEFAULT_Y)

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
		panel.content.hint_text = edit.error or spec.hint or mod:localize(spec.numeric and "popup_hint_number" or "popup_hint_text")

		panel.style.hint_text.text_color = clone_color(edit.error and Components.colors.gold or Components.colors.muted)

		local input_style = widgets[Components.POPUP_INPUT_NAME].style.display_text

		if input_style then
			input_style.text_color = clone_color(edit.error and Components.colors.gold or Components.colors.text)
		end
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
