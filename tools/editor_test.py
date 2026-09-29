"""Drives the real wave editor view files against stubbed engine classes.

Not a substitute for the game, but it executes the actual view/blueprint/component
code paths (screen switching, row filling, callbacks, popup, persistence) so that
nil-index and logic bugs show up offline.
Run:  python tools/editor_test.py   (needs `lupa`, see CLAUDE.md)
"""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.environ.get("PYLIBS", r"C:\Users\ayko4\AppData\Local\Temp\claude\c--XboxGames-Warhammer-40-000--Darktide-Content\9da40c72-f459-4d9d-ab4b-3023fa21e2f5\scratchpad\pylibs"))
from lupa import LuaRuntime

MODROOT = os.path.abspath(os.path.join(HERE, "..")).replace("\\", "/")
lua = LuaRuntime(unpack_returned_tuples=True)

harness = r'''
local MODROOT = ...
local BASE = MODROOT .. "/scripts/mods/RealmsWaves"

-- ---- engine stubs ---------------------------------------------------------
function table.clone(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == "table" and table.clone(v) or v end return c end
table.clone_instance = table.clone
function math.clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function callback(obj, name, ...) local args = { ... } return function(...) return obj[name](obj, unpack(args), ...) end end
unpack = unpack or table.unpack

local UIWidget = {}
UIWidget.create_definition = function(passes, node_id, content, size)
  local def = { passes = passes, node_id = node_id, content = {}, style = {} }
  for _, pass in ipairs(passes) do
    if pass.content_id then def.content[pass.content_id] = table.clone(pass.content or {}) end
    if pass.value_id then def.content[pass.value_id] = pass.value or "" end
    if pass.style_id then def.style[pass.style_id] = table.clone(pass.style or {}) end
    if pass.style and pass.style.text_color == nil and pass.pass_type == "text" then def.style[pass.style_id].text_color = { 255, 255, 255, 255 } end
  end
  for k, v in pairs(content or {}) do def.content[k] = v end
  return def
end

local stubs = {
  ["scripts/managers/ui/ui_widget"] = UIWidget,
  ["scripts/managers/ui/ui_font_settings"] = { header_1 = {}, header_5 = {} },
  ["scripts/ui/pass_templates/text_input_pass_templates"] = { simple_input_field = {
    { pass_type = "hotspot", content_id = "hotspot", style = {} }, { style_id = "limit_text", style = {} },
    { style_id = "focused", style = {} }, { style_id = "display_text", style = {} } } },
  ["scripts/settings/ui/ui_sound_events"] = { default_mouse_hover = "h", default_click = "c" },
  ["scripts/ui/pass_templates/button_pass_templates"] = { default_button = { { pass_type = "hotspot", content_id = "hotspot", style = {} } } },
  ["scripts/ui/view_elements/view_element_input_legend/view_element_input_legend"] = {},
}
local real_require = require
require = function(path) return stubs[path] or real_require(path) end

-- BaseView / class
-- Mirrors the REAL BaseView flow (scripts/ui/views/base_view.lua): init only stores things;
-- _on_view_requirements_complete calls self:_create_widgets(definitions, widgets, widgets_by_name)
-- to build the STATIC widgets, then on_enter. A view that overrides _create_widgets (or any
-- other BaseView method) breaks this exactly as it broke in the game.
local BASEVIEW_NAMES = { "init", "_create_ui_renderer", "dialogue_system", "_is_event_registered", "_register_event", "_unregister_event", "_unregister_events", "_on_view_load_complete", "is_view_requirements_complete", "_on_view_requirements_complete", "loading", "widgets_by_name", "_create_scenegraph", "_create_widgets", "_create_widget", "_unregister_widget_name", "get_time", "has_widget", "trigger_widget_pressed", "widget_hotspot_content", "_create_sequence_animator", "_is_animation_active", "_is_animation_completed", "_start_animation", "_stop_animation", "_complete_animation", "entered", "on_enter", "supports_changeable_context", "character_level", "on_exit", "destroy", "set_can_exit", "can_exit", "allow_close_hotkey", "on_resolution_modified", "trigger_resolution_update", "_set_scenegraph_position", "render_scale", "set_render_scale", "_set_scenegraph_size", "_scenegraph_size", "_scenegraph_position", "_scenegraph_world_position", "_update_element_position", "_force_update_scenegraph", "_update_animations", "update", "post_update", "_handle_input", "using_cursor_navigation", "_on_navigation_input_changed", "is_using_input", "draw", "set_local_player_id", "trigger_on_enter_animation", "trigger_on_exit_animation", "triggered_on_enter_animation", "triggered_on_exit_animation", "on_enter_animation_done", "on_exit_animation_done", "_draw_widgets", "_localize", "_localized_input_text", "_text_size", "_play_sound", "_stop_sound", "_set_sound_parameter", "_add_element", "_remove_element", "_element_reference_name", "_element", "_on_resolution_modified_elements", "_draw_elements", "_update_elements", "_player", "_player_viewport", "input_enable", "input_disable" }
local BaseView = {}
BaseView.init = function(self, defs, settings)
  self._definitions = defs
  self._settings = settings
  self._widgets, self._widgets_by_name = {}, {}
end
BaseView._create_widgets = function(self, definitions, widgets, widgets_by_name)
  widgets, widgets_by_name = widgets or {}, widgets_by_name or {}
  for name, def in pairs(definitions.widget_definitions) do
    local w = self:_create_widget(name, def, widgets_by_name)
    widgets[#widgets + 1] = w
  end
  return widgets, widgets_by_name
end
BaseView._on_view_requirements_complete = function(self)
  self:_create_widgets(self._definitions, self._widgets, self._widgets_by_name)
  self:on_enter()
end
BaseView.on_enter = function() end
BaseView.on_exit = function() end
BaseView.update = function() end
BaseView._add_element = function() return { add_entry = function() end } end
BaseView._set_scenegraph_position = function() end
BaseView._create_widget = function(self, name, def, widgets_by_name)
  local w = { name = name, content = table.clone(def.content), style = table.clone(def.style), visible = true }
  ;(widgets_by_name or self._widgets_by_name)[name] = w
  return w
end
function class(name, parent)
  local c = { super = BaseView, __name = name }
  c.__index = c
  setmetatable(c, { __index = BaseView })
  return c
end

-- ---- mod stub ---------------------------------------------------------------
local settings, echoes = {}, {}
local mod = {}
mod.get = function(self, id) return settings[id] end
mod.set = function(self, id, v) settings[id] = v end
mod.echo = function(self, fmt, ...) echoes[#echoes+1] = string.format(fmt, ...) end
mod.error = function(self, fmt, ...) echoes[#echoes+1] = "ERROR " .. string.format(fmt, ...) end
mod.localize = function(self, id, ...) local a = { ... } for i = 1, #a do a[i] = tostring(a[i]) end return id .. (#a > 0 and (":" .. table.concat(a, ",")) or "") end
mod.io_dofile = function(self, path) return dofile(MODROOT .. "/../" .. path .. ".lua") end
get_mod = function(name) return mod end
Managers = { ui = { closed = nil, close_view = function(self, n) self.closed = n end } }

mod.rw = {
  events = dofile(BASE .. "/catalog/events.lua"),
  groups = dofile(BASE .. "/catalog/groups.lua"),
}

local results = {}
local function check(name, cond, detail) results[#results+1] = (cond and "PASS " or "FAIL ") .. name .. (detail and (" -- " .. tostring(detail)) or "") end

-- ---- load the real view ------------------------------------------------------
local View = dofile(BASE .. "/ui/wave_editor_view.lua")
local view = setmetatable({}, View)
View.init(view, {})
view.view_name = "realms_waves_editor"

-- guard: the view may only override init/on_enter/on_exit/update of BaseView
local allowed = { init = true, on_enter = true, on_exit = true, update = true }
local clashes = {}
for _, name in ipairs(BASEVIEW_NAMES) do
  if rawget(View, name) ~= nil and not allowed[name] then clashes[#clashes + 1] = name end
end
check("view overrides no BaseView method except init/on_enter/on_exit/update", #clashes == 0, table.concat(clashes, ","))

view:_on_view_requirements_complete() -- same entry point the engine uses
check("static widgets exist after BaseView creates them", view._widgets_by_name.title_text ~= nil and view._widgets_by_name.list_header ~= nil and view._widgets_by_name.rw_popup_panel ~= nil)
check("title text filled", view._widgets_by_name.title_text.content.title_text == "view_title")

local function row(i) return view._widgets_by_name["rw_row_" .. i] end
local function click(widget_name, hotspot) view._widgets_by_name[widget_name].content[hotspot or "hotspot"].pressed_callback() end
local function click_row(i, hotspot) row(i).content[hotspot].pressed_callback() end

-- list screen
check("list: 32 waves (12 standard + 20 custom)", #view._waves == 32, #view._waves)
check("list: first row is Small Wave", row(1).content.row_name == "Small Wave" and row(1).visible, row(1).content.row_name)
check("list: composition summary", row(1).content.info:find("8 Poxwalker") ~= nil, row(1).content.info)
check("list: row flags", row(1).content.show_check and row(1).content.show_stepper and row(1).content.show_share and row(1).content.show_action)
check("list: share shown", row(1).content.share == "18.0%", row(1).content.share)
check("list: 10 rows visible", row(10).visible and view._offset == 0)
check("list: buttons hidden", not view._widgets_by_name.btn_back.visible and not view._widgets_by_name.stepper_chance.visible)

-- scrolling
click("rw_scroll_down"); check("scroll down moves offset", view._offset == 1)
click("rw_scroll_up"); check("scroll up returns", view._offset == 0)
view._offset = 25; view:_refresh_rows()
check("last page shows custom slots", row(1).content.row_name:find("Custom") ~= nil and row(1).content.info == "row_empty_slot", row(1).content.row_name)
view._offset = 0; view:_refresh_rows()

-- checkbox toggles enabled, stepper changes chance
click_row(2, "hotspot_check")
check("toggle enabled off", settings["on_wave_medium"] == false and row(2).content.checkbox_selected == false)
click_row(2, "hotspot_check")
check("toggle enabled on", settings["on_wave_medium"] == true and row(2).content.checkbox_selected == true)
click_row(1, "hotspot_plus")
check("chance +1", settings["pct_wave_small"] == 19 and row(1).content.stepper_value == "19", settings["pct_wave_small"])
click_row(1, "hotspot_minus"); click_row(1, "hotspot_minus")
check("chance -2", settings["pct_wave_small"] == 17)

-- open detail
click_row(1, "hotspot_action")
check("detail: screen and title", view._screen == "detail" and view._widgets_by_name.description_text.content.description_text == "view_desc_detail:Small Wave")
check("detail: composition rows", row(1).content.row_name == "8 Poxwalker" and row(4).content.row_name == "2 Rifleman" and not row(5).visible, row(1).content.row_name)
check("detail: row flags", not row(1).content.show_check and row(1).content.show_stepper and not row(1).content.show_share and row(1).content.show_action)
check("detail: buttons visible", view._widgets_by_name.btn_rename.visible and view._widgets_by_name.btn_add.visible and view._widgets_by_name.stepper_cooldown.visible)
check("detail: steppers show values", view._widgets_by_name.stepper_chance.content.stepper_value == "17" and view._widgets_by_name.stepper_cooldown.content.stepper_value == "60")

-- count stepper writes an override
click_row(1, "hotspot_plus")
check("count +1 saved", settings["wave_def_wave_small"] ~= nil and row(1).content.row_name == "9 Poxwalker", settings["wave_def_wave_small"])
click_row(1, "hotspot_minus"); click_row(1, "hotspot_minus"); click_row(1, "hotspot_minus")
check("count -3", row(1).content.row_name == "6 Poxwalker")

-- remove a part
click_row(4, "hotspot_action")
check("remove part", not row(4).visible and #view._parts == 3)

-- add enemy via picker
click("btn_add")
check("picker: screen and rows", view._screen == "picker" and #view._breeds >= 38 and row(1).content.show_action and not row(1).content.show_stepper)
local first_breed = view._breeds[1]
click_row(1, "hotspot_action")
check("picker add returns to detail", view._screen == "detail" and #view._parts == 4, view._screen)
local found = false; for _, p in ipairs(view._parts) do if p.breed == first_breed then found = true end end
check("picker: breed added", found, first_breed)

-- rename via popup
click("btn_rename")
check("rename popup opens", view._popup ~= nil and view._widgets_by_name.rw_popup_panel.visible)
check("popup locks hotspots", row(1).content.hotspot_name.disabled == true and view._widgets_by_name.btn_add.content.hotspot.disabled == true)
view._widgets_by_name.rw_popup_input.content.input_text = "  Mob\tRush "
Components = nil
local PopupOwner = dofile(BASE .. "/ui/wave_editor_components.lua")
PopupOwner.Popup.commit(view)
check("rename saved and cleaned", settings["wave_def_wave_small"]:match("^Mob Rush\t") ~= nil and view._wave.name == "Mob Rush", settings["wave_def_wave_small"])
check("popup closed", view._popup == nil and not view._widgets_by_name.rw_popup_panel.visible and row(1).content.hotspot_name.disabled == false)

-- edit as text: validation error keeps popup open, valid text applies
click("btn_text")
view._widgets_by_name.rw_popup_input.content.input_text = "5 unicorns"
PopupOwner.Popup.commit(view)
check("recipe validation error keeps popup", view._popup ~= nil and view._popup.error ~= nil, view._popup and view._popup.error)
view._widgets_by_name.rw_popup_input.content.input_text = "3 hounds, 1 plague ogryn|chaos spawn"
PopupOwner.Popup.commit(view)
check("recipe applied", view._popup == nil and #view._parts == 2 and view._parts[2].one_of ~= nil and row(2).content.row_name:find("random of") ~= nil, row(2).content.row_name)

-- numeric popup on count with range check
click_row(1, "hotspot_value")
view._widgets_by_name.rw_popup_input.content.input_text = "0"
PopupOwner.Popup.commit(view)
check("count popup rejects 0", view._popup ~= nil and view._popup.error ~= nil)
view._widgets_by_name.rw_popup_input.content.input_text = "12"
PopupOwner.Popup.commit(view)
check("count popup accepts 12", view._popup == nil and view._parts[1].count == 12 and row(1).content.row_name == "12 Hound", row(1).content.row_name)
PopupOwner.Popup.cancel(view)

-- chance/cooldown steppers and enabled toggle in detail
view._widgets_by_name.stepper_cooldown.content.hotspot_plus.pressed_callback()
check("cooldown +5", settings["cd_wave_small"] == 65 and view._widgets_by_name.stepper_cooldown.content.stepper_value == "65", settings["cd_wave_small"])
view._widgets_by_name.stepper_chance.content.hotspot_plus.pressed_callback()
check("chance +1 in detail", settings["pct_wave_small"] == 18)
click("btn_enabled")
check("enabled toggled in detail", settings["on_wave_small"] == false and view._widgets_by_name.btn_enabled.content.hotspot_text == "btn_enabled_off")

-- built-in wave cannot lose its last enemy
click_row(1, "hotspot_action")
check("standard wave: cannot remove last but one? (2 parts -> 1)", #view._parts == 1)
click_row(1, "hotspot_action")
check("standard wave: last enemy kept", #view._parts == 1 and echoes[#echoes]:find("msg_need_one_enemy") ~= nil, echoes[#echoes])

-- reset
click("btn_reset")
check("reset restores built-in", view._wave.name == "Small Wave" and #view._parts == 4 and settings["on_wave_small"] == true and settings["pct_wave_small"] == 18)

-- back navigation: detail -> list, back key
click("btn_back")
check("back to list", view._screen == "list" and not view._widgets_by_name.btn_rename.visible)
view:_on_back_pressed()
check("back key on list closes view", Managers.ui.closed == "realms_waves_editor")

-- custom slot workflow
view._offset = 12; view:_refresh_rows()
click_row(1, "hotspot_action")
check("custom slot detail (empty)", view._screen == "detail" and #view._parts == 0 and view._wave.is_custom and view._widgets_by_name.btn_reset.content.hotspot_text == "btn_reset_clear")
click("btn_add"); view._offset = 0
click_row(3, "hotspot_action")
check("custom: first enemy added", #view._parts == 1 and view._parts[1].count == 1, #view._parts)
click_row(1, "hotspot_plus")
click("btn_enabled")
check("custom: enabled and in pool", settings["on_custom_1"] == true and #mod.rw.events.build_pool(function(id) return settings[id] end, mod.rw.groups) == 13)

local errors = {}
for _, e in ipairs(echoes) do if e:find("^ERROR") then errors[#errors+1] = e end end
check("no errors logged by guarded callbacks", #errors == 0, table.concat(errors, " | "))

return table.concat(results, "\n")
'''
out = lua.execute(harness, MODROOT)
print(out)
fails = [l for l in out.split("\n") if l.startswith("FAIL")]
print("\nPASS:", len([l for l in out.split("\n") if l.startswith("PASS")]), "FAIL:", len(fails))
sys.exit(1 if fails else 0)
