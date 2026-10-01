-- Dynamic widget blueprints for the wave editor: the shared row, single
-- buttons, labelled steppers, scroll buttons and the popup buttons/input.
local mod = get_mod("RealmsWaves")

local UIWidget = require("scripts/managers/ui/ui_widget")
local ButtonPassTemplates = require("scripts/ui/pass_templates/button_pass_templates")
local Components = mod:io_dofile("RealmsWaves/scripts/mods/RealmsWaves/ui/wave_editor_components")

local blueprints = {}
local colors = Components.colors

-- One row serves three screens; content flags decide which parts exist:
--   show_check    checkbox (wave list)
--   show_stepper  - value +  (chance on the list, count in the detail screen)
--   show_share    share of total chance (wave list)
--   show_action   right-hand button, label in content.hotspot_action_text
--   show_mods     "Mods" button (detail screen, where the share column is unused)
--   show_rep      second stepper: units added on every repeat tick (detail screen)
blueprints.row = function (node_id)
	local passes = {}

	passes[#passes + 1] = {
		pass_type = "texture",
		value = "content/ui/materials/backgrounds/default_square",
		style_id = "row_background",
		style = {
			size = { 1710, 46 },
			offset = { 0, 0, 0 },
			color = Components.clone_color(colors.normal),
		},
		-- highlight the whole row while the pointer is over its name/composition area
		change_function = function (content, style)
			Components.color_into(style.color, content.hotspot_name.is_hover and colors.hover or colors.normal)
		end,
	}

	Components.checkbox_passes(passes, { 10, 9, 1 }, nil, "show_check")
	Components.hotspot_pass(passes, "hotspot_check", { 4, 5, 2 }, { 36, 36 }, "show_check")

	-- clickable area: name + composition (everything left of the steppers)
	Components.hotspot_pass(passes, "hotspot_name", { 60, 0, 3 }, { 1130, 46 })
	Components.text_pass(passes, "row_name", "row_name", { 60, 0, 2 }, { 480, 46 }, 22, colors.text)
	Components.text_pass(passes, "info", "info", { 550, 0, 2 }, { 640, 46 }, 18, colors.muted)

	Components.stepper_passes(passes, {
		minus_offset = { 1210, 3, 2 },
		value_offset = { 1256, 3, 2 },
		value_size = { 60, 40 },
		plus_offset = { 1318, 3, 2 },
	}, "show_stepper")

	-- units added on every repeat tick (detail screen only); the count stepper above is the initial spawn
	Components.stepper_passes(passes, {
		minus_offset = { 905, 3, 2 },
		value_offset = { 951, 3, 2 },
		value_size = { 60, 40 },
		plus_offset = { 1013, 3, 2 },
	}, "show_rep", { minus = "hotspot_rep_minus", value = "hotspot_rep_value", plus = "hotspot_rep_plus", text = "rep_value" })

	-- "Same": every repeat spawns the same number as the initial spawn (the stepper is ignored)
	Components.checkbox_passes(passes, { 1128, 9, 1 }, nil, "show_rep", "same", "same_selected")
	Components.hotspot_pass(passes, "hotspot_same", { 1122, 5, 2 }, { 36, 36 }, "show_rep")

	Components.text_pass(passes, "share", "share", { 1390, 0, 2 }, { 120, 46 }, 20, colors.muted, "right", "show_share")
	Components.button_passes(passes, "hotspot_mods", { 1390, 3, 2 }, { 130, 40 }, "", 18, colors.gold, "show_mods")
	Components.button_passes(passes, "hotspot_action", { 1530, 3, 2 }, { 160, 40 }, "", 20, colors.gold, "show_action")

	return UIWidget.create_definition(passes, node_id, {
		row_name = "",
		info = "",
		stepper_value = "",
		share = "",
		checkbox_selected = false,
		show_check = false,
		show_stepper = false,
		show_share = false,
		show_action = false,
		show_mods = false,
		show_rep = false,
		rep_value = "",
		same_selected = false,
	}, { 1710, 46 })
end

blueprints.button = function (node_id, width)
	local passes = {}

	Components.button_passes(passes, "hotspot", { 0, 0, 0 }, { width, 44 }, "", 22)

	return UIWidget.create_definition(passes, node_id, {}, { width, 44 })
end

-- Label + minus + value + plus + trailing text (content.label / stepper_value / extra).
-- `label_width` (default 200) makes room for a long label; everything else moves right with it.
blueprints.setting_stepper = function (node_id, width, label_width)
	local passes = {}
	local x0 = label_width or 200

	width = width or 800

	Components.text_pass(passes, "label", "label", { 0, 0, 2 }, { x0, 48 }, 22, colors.text)
	Components.stepper_passes(passes, {
		-- the value sits close to the - and + buttons (44 px wide each, 2 px gaps)
		minus_offset = { x0 + 5, 4, 2 },
		value_offset = { x0 + 51, 4, 2 },
		value_size = { 64, 40 },
		plus_offset = { x0 + 117, 4, 2 },
	})
	Components.text_pass(passes, "extra", "extra", { x0 + 178, 0, 2 }, { width - x0 - 188, 48 }, 20, colors.muted)

	return UIWidget.create_definition(passes, node_id, { label = "", stepper_value = "", extra = "" }, { width, 48 })
end

blueprints.scroll_button = function (node_id, label)
	local passes = {}

	Components.button_passes(passes, "hotspot", { 0, 0, 0 }, { 44, 36 }, label)

	return UIWidget.create_definition(passes, node_id, {}, { 44, 36 })
end

blueprints.popup_confirm = UIWidget.create_definition(ButtonPassTemplates.default_button, Components.POPUP_CONFIRM_NAME, {
	original_text = mod:localize("popup_ok"),
})

blueprints.popup_cancel = UIWidget.create_definition(ButtonPassTemplates.default_button, Components.POPUP_CANCEL_NAME, {
	original_text = mod:localize("popup_cancel"),
})

blueprints.popup_input = Components.popup_input_definition()

return blueprints
