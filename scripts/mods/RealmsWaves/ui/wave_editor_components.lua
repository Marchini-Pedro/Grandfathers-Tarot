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
Components.colors = {
	text = { 255, 222, 229, 214 },
	muted = { 255, 151, 167, 152 },
	gold = { 255, 221, 194, 122 },
	normal = { 225, 25, 35, 27 },
	hover = { 250, 49, 62, 42 },
	selected = { 245, 51, 70, 44 },
	disabled = { 150, 40, 44, 40 },
	panel = { 220, 15, 23, 19 },
	frame = { 160, 151, 167, 152 },
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

local function flag_visible(flag)
	if not flag then
		return nil
	end

	return function (content)
		return content[flag] == true
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

-- Checkbox: frame + filled square when content.checkbox_selected. `flag` as above.
function Components.checkbox_passes(passes, offset, size, flag)
	size = size or { 28, 28 }

	passes[#passes + 1] = {
		pass_type = "texture",
		value = "content/ui/materials/backgrounds/default_square",
		style_id = "checkbox_frame",
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
		style_id = "checkbox_check",
		style = {
			size = { math.max(size[1] - 6, 0), math.max(size[2] - 6, 0) },
			offset = { offset[1] + 3, offset[2] + 3, (offset[3] or 0) + 1 },
			color = clone_color(Components.colors.gold),
		},
		visibility_function = function (content)
			return content.checkbox_selected == true and (flag == nil or content[flag] == true)
		end,
	}
end

-- Stepper: minus button + clickable value + plus button, prefixed by `prefix`
-- ("hotspot" gives hotspot_minus / hotspot_value / hotspot_plus and stepper_value).
function Components.stepper_passes(passes, layout, flag)
	local button_size = layout.button_size or { 44, 40 }

	Components.button_passes(passes, "hotspot_minus", layout.minus_offset, button_size, "-", nil, nil, flag)
	Components.hotspot_pass(passes, "hotspot_value", layout.value_offset, layout.value_size, flag)
	Components.text_pass(passes, "stepper_value", "stepper_value", layout.value_offset, {
		layout.value_size[1],
		layout.value_size[2] + 6,
	}, 22, Components.colors.gold, "center", flag)
	Components.button_passes(passes, "hotspot_plus", layout.plus_offset, button_size, "+", nil, nil, flag)
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

-- spec = { label, value (string), max_length, set(value_or_text),
--          numeric = true -> min, max, integer, value is parsed and range-checked
--          validate = function(text) -> ok, error_message  (text mode, optional) }
function POPUP.open(view, spec)
	POPUP.cancel(view)

	local text = tostring(spec.value or "")

	view._popup = { spec = spec, original = text, error = nil }
	view.is_text_input_focused = true

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

	if text == edit.original then
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

	POPUP.cancel(view)
	spec.set(value)

	return true
end

function POPUP.cancel(view)
	if not view._popup then
		return false
	end

	view._popup = nil
	view.is_text_input_focused = false

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
		panel.content.hint_text = edit.error or mod:localize(spec.numeric and "popup_hint_number" or "popup_hint_text")

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

	if input_service:get("confirm_pressed") then
		POPUP.commit(view)
	end
end

return Components
