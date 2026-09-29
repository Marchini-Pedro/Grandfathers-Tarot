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
-- the game's own callback() (binds up to 5 arguments), loaded from the source clone
ferror = error
dofile(MODROOT .. "/../../Darktide-Source-Code/scripts/foundation/utilities/callback.lua")
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
BaseView._set_scenegraph_position = function(self, id, x, y, z) self._sg = self._sg or {}; self._sg[id] = { x, y, z } end
BaseView._create_widget = function(self, name, def, widgets_by_name)
  local w = { name = name, def = def, content = table.clone(def.content), style = table.clone(def.style), visible = true }
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

-- Engine semantics of visibility_function (scripts/managers/ui/ui_widget.lua:411-446): it receives
-- content[content_id] for passes with a content_id (hotspots), the widget content otherwise, and
-- the engine sets pass_content.parent = widget content. A hotspot whose visibility_function
-- returns false is skipped entirely: no hover, no click.
local function pass_visible(w, pass)
  if not pass.visibility_function then return true end
  local pc = pass.content_id and w.content[pass.content_id] or w.content
  if pass.content_id and not pc.parent then pc.parent = w.content end
  return pass.visibility_function(pc, {}) and true or false
end
local function hotspot_runs(w, content_id)
  for _, p in ipairs(w.def.passes) do
    if p.pass_type == "hotspot" and p.content_id == content_id then return pass_visible(w, p) end
  end
  error("no hotspot pass " .. content_id)
end
local function pass_by_style(w, style_id)
  for _, p in ipairs(w.def.passes) do if p.style_id == style_id then return p end end
end
local r1 = row(1)
check("engine rule: list row hotspots run (hover/click work)", hotspot_runs(r1, "hotspot_name") and hotspot_runs(r1, "hotspot_check") and hotspot_runs(r1, "hotspot_minus") and hotspot_runs(r1, "hotspot_value") and hotspot_runs(r1, "hotspot_plus") and hotspot_runs(r1, "hotspot_action"))
check("engine rule: hidden hotspot (Mods) does not run on the list", not hotspot_runs(r1, "hotspot_mods"))
r1.content.hotspot_action.is_hover = true
check("engine rule: Edit button hover layers show while hovered", pass_visible(r1, pass_by_style(r1, "hotspot_action_highlight")) and pass_visible(r1, pass_by_style(r1, "hotspot_action_frame")))
r1.content.hotspot_action.is_hover = false
check("engine rule: no hover layer when not hovered", not pass_visible(r1, pass_by_style(r1, "hotspot_action_highlight")))
local bg = pass_by_style(r1, "row_background")
r1.content.hotspot_name.is_hover = true; bg.change_function(r1.content, r1.style.row_background)
local hover_col = r1.style.row_background.color[2]
r1.content.hotspot_name.is_hover = false; bg.change_function(r1.content, r1.style.row_background)
check("row background highlights on hover", hover_col ~= r1.style.row_background.color[2], hover_col .. " vs " .. r1.style.row_background.color[2])
-- every widget: every visibility/change function runs without error under engine semantics
local bad = {}
for name, w in pairs(view._widgets_by_name) do
  if w.def then
    for _, p in ipairs(w.def.passes) do
      local ok, err = pcall(pass_visible, w, p)
      if not ok then bad[#bad+1] = name .. ":" .. tostring(p.style_id) .. ": " .. tostring(err) end
      if p.change_function then
        local pc = p.content_id and w.content[p.content_id] or w.content
        local ok2, err2 = pcall(p.change_function, pc, w.style[p.style_id] or {})
        if not ok2 then bad[#bad+1] = name .. ":" .. tostring(p.style_id) .. " change: " .. tostring(err2) end
      end
    end
  end
end
check("engine rule: no visibility/change function errors in any widget", #bad == 0, table.concat(bad, " | "))

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

-- enemy search in the picker -----------------------------------------------------------
local input_stub = { get = function() return nil end, is_null_service = function() return false end }
local SP = dofile(BASE .. "/ui/wave_editor_components.lua")
click("btn_add")
local total_breeds = #view._breeds
check("picker: Search button visible, all enemies listed, status shown", view._widgets_by_name.btn_search.visible and total_breeds >= 41 and view._widgets_by_name.description_text.content.description_text:find("picker_status:") ~= nil, total_breeds)
check("picker rows show the enemy kind", row(1).content.info:find("%(") ~= nil, row(1).content.info)
click("btn_search")
check("search popup opens low on the screen so the list stays visible", view._popup ~= nil and view._sg.rw_popup_panel[2] == 700 and view._sg.rw_popup_input[2] == 770, view._sg.rw_popup_panel and view._sg.rw_popup_panel[2])
view._widgets_by_name.rw_popup_input.content.input_text = "twin"
view:update(0.01, 0, input_stub)
check("typing filters the list live", #view._breeds == 2 and row(1).visible and row(2).visible and not row(3).visible and row(1).content.row_name == "Twin Captain One" and row(2).content.row_name == "Twin Captain Two", #view._breeds)
check("status text shows the match count and the filter", view._widgets_by_name.description_text.content.description_text:find("picker_status_filtered:2,") ~= nil and view._widgets_by_name.description_text.content.description_text:find("twin") ~= nil)
check("search box open: enemy rows stay clickable, other buttons are locked", row(1).content.hotspot_name.disabled == false and row(1).content.hotspot_action.disabled == false and view._widgets_by_name.btn_back.content.hotspot.disabled == true and view._widgets_by_name.btn_search.content.hotspot.disabled == true and view._widgets_by_name.rw_scroll_down.content.hotspot.disabled == (view._offset >= math.max(0, #view._breeds - 10)), tostring(row(1).content.hotspot_name.disabled))
check("popup buttons are wide enough for the vanilla ornamental frame (240x56 each, no overlap)", view._sg.rw_popup_confirm[1] == 600 and view._sg.rw_popup_cancel[1] == 870 and view._sg.rw_popup_confirm[2] == 900 and view._sg.rw_popup_cancel[2] == 900, view._sg.rw_popup_confirm[2])
view._widgets_by_name.rw_popup_input.content.input_text = "beastmaster"
view:update(0.01, 0, input_stub)
check("aliases are searched (beastmaster -> Packmaster)", #view._breeds == 1 and row(1).content.row_name == "Packmaster", row(1).content.row_name)
view._widgets_by_name.rw_popup_input.content.input_text = "twin"
view:update(0.01, 0, input_stub)
SP.Popup.commit(view)
check("OK keeps the filter, closes the popup, moves it back to the centre", view._popup == nil and #view._breeds == 2 and view._sg.rw_popup_panel[2] == 400 and view._widgets_by_name.btn_search.content.hotspot_text == "btn_search_active:twin", view._widgets_by_name.btn_search.content.hotspot_text)
-- pick an enemy straight from the filtered list while the search box is still open
click("btn_search")
view._widgets_by_name.rw_popup_input.content.input_text = "twin two"
view:update(0.01, 0, input_stub)
local parts_before_pick = #view._parts
check("typing 'twin two' leaves exactly one row", #view._breeds == 1 and row(1).content.row_name == "Twin Captain Two")
click_row(1, "hotspot_action")
check("clicking a row while the search box is open adds the enemy, closes the box and returns to the detail screen", view._popup == nil and view._screen == "detail" and #view._parts == parts_before_pick + 1 and view._parts[#view._parts].breed == "renegade_twin_captain_two" and view._sg.rw_popup_panel[2] == 400, tostring(view._screen) .. " " .. #view._parts .. " vs " .. parts_before_pick)
click("btn_add")
check("the pick left no half-open state: the picker starts fresh again", view._popup == nil and view._filter == "" and #view._breeds == total_breeds)
click("btn_search")
view._widgets_by_name.rw_popup_input.content.input_text = "twin"
view:update(0.01, 0, input_stub)
SP.Popup.commit(view)
click("btn_search")
-- clicking a row by NAME works too, and the numeric/rename popups still lock everything
view._widgets_by_name.rw_popup_input.content.input_text = "packmaster"
view:update(0.01, 0, input_stub)
click_row(1, "hotspot_name")
check("clicking the row name (not just the button) also picks it while searching", view._popup == nil and view._screen == "detail" and view._parts[#view._parts].breed == "chaos_ogryn_houndmaster")
click("btn_add")
click("btn_search")
view._widgets_by_name.rw_popup_input.content.input_text = "twin"
view:update(0.01, 0, input_stub)
SP.Popup.commit(view)
click("btn_search")
view._widgets_by_name.rw_popup_input.content.input_text = "boss"
view:update(0.01, 0, input_stub)
local boss_matches = #view._breeds
SP.Popup.cancel(view)
check("Cancel undoes the typed filter (back to 'twin')", boss_matches == 9 and #view._breeds == 2 and view._filter == "twin", boss_matches .. "/" .. #view._breeds .. "/" .. tostring(view._filter))
click("btn_search")
view._widgets_by_name.rw_popup_input.content.input_text = ""
view:update(0.01, 0, input_stub)
SP.Popup.commit(view)
check("clearing the search shows every enemy again", #view._breeds == total_breeds and view._widgets_by_name.btn_search.content.hotspot_text == "btn_search")
click("btn_search")
view._widgets_by_name.rw_popup_input.content.input_text = "xyzzy"
view:update(0.01, 0, input_stub)
check("no match -> empty list, no rows", #view._breeds == 0 and not row(1).visible)
SP.Popup.commit(view)
click("btn_back")
click("btn_add")
check("re-entering the picker starts with an empty search", view._filter == "" and #view._breeds == total_breeds)
click("btn_back")
check("back from the picker returns to the detail screen", view._screen == "detail")

-- modifiers screen ---------------------------------------------------------------
check("detail: Mods button on enemy rows", row(1).content.show_mods and row(1).content.hotspot_mods_text == "btn_mods" and not row(1).content.show_share)
check("engine rule: detail row Mods/stepper/Remove hotspots run, checkbox does not", hotspot_runs(row(1), "hotspot_mods") and hotspot_runs(row(1), "hotspot_plus") and hotspot_runs(row(1), "hotspot_action") and not hotspot_runs(row(1), "hotspot_check"))
click_row(1, "hotspot_mods")
check("mods screen opens", view._screen == "mods" and view._widgets_by_name.description_text.content.description_text:find("view_desc_mods") ~= nil and view._widgets_by_name.btn_back.visible)
check("mods screen lists all 9 modifiers with checkboxes", row(9).visible and not row(10).visible and row(1).content.show_check and not row(1).content.show_stepper and not row(1).content.show_action and not row(1).content.show_mods, row(9).content.row_name)
check("mods screen: names, descriptions, havoc note", row(1).content.row_name == "Purple" and row(1).content.info:find("Encroaching Garden") ~= nil and row(1).content.info:find("heals nearby") ~= nil and row(6).content.row_name == "Pus-Hardened Skin" and row(3).content.row_name == "Red" and row(4).content.row_name == "Blight" and row(5).content.row_name == "Orange" and row(5).content.info:find("^Rampaging Enemies") ~= nil and row(9).content.row_name == "Purple Stimm" and row(6).content.info:find("note_havoc_only") ~= nil and row(2).content.info:find("note_havoc_only") == nil)
check("mods screen: nothing ticked yet", not row(1).content.checkbox_selected and not row(2).content.checkbox_selected)
click_row(1, "hotspot_check")
check("tick Garden -> saved in recipe, checkbox on", row(1).content.checkbox_selected and settings["wave_def_wave_small"]:find("%[garden%]") ~= nil, settings["wave_def_wave_small"])
click_row(2, "hotspot_name")
check("click name toggles Enraged too", row(2).content.checkbox_selected and settings["wave_def_wave_small"]:find("%[garden%+enraged%]") ~= nil, settings["wave_def_wave_small"])
check("modifiers stored on the part", #view._parts[1].mods == 2 and view._parts[1].mods[1] == "garden" and view._parts[1].mods[2] == "enraged")
click("btn_back")
check("back from mods returns to detail with modifiers listed", view._screen == "detail" and row(1).content.info == "Purple, Enraged" and row(1).content.row_name == "6 Poxwalker", row(1).content.info)
click_row(1, "hotspot_mods"); click_row(1, "hotspot_check"); click_row(2, "hotspot_check")
check("untick both -> modifiers cleared", view._parts[1].mods == nil and not row(1).content.checkbox_selected)
click("btn_back")
check("cleared modifiers leave no brackets in recipe", settings["wave_def_wave_small"]:find("%[") == nil, settings["wave_def_wave_small"])
-- a part with modifiers is not merged with a plain part when adding the same breed
click_row(1, "hotspot_mods"); click_row(1, "hotspot_check"); click("btn_back")
local n_before = #view._parts
click("btn_add")
local poxwalker_index; for i, b in ipairs(view._breeds) do if b == "chaos_poxwalker" then poxwalker_index = i end end
view._offset = math.max(0, poxwalker_index - 1); view:_refresh_rows()
click_row(1, "hotspot_action")
check("adding a breed that exists with modifiers creates a separate group", #view._parts == n_before + 1, #view._parts .. " vs " .. n_before)
view._parts[1].mods = nil; view:_save()

-- spread radius and repeats -------------------------------------------------------
local S = view._widgets_by_name
check("detail: spread / repeat steppers visible with defaults", S.stepper_spread.visible and S.stepper_every.visible and S.stepper_for.visible and S.stepper_spread.content.stepper_value == "3" and S.stepper_every.content.stepper_value == "10" and S.stepper_for.content.stepper_value == "60", S.stepper_spread.content.stepper_value)
check("detail: repeat stepper says 'off' while no enemy repeats", S.stepper_every.content.extra == "extra_no_repeat", S.stepper_every.content.extra)
check("detail: header shows the repeat column", view._widgets_by_name.list_header.content.col_6 == "col_repeat")
S.stepper_spread.content.hotspot_plus.pressed_callback()
check("spread +1", settings["sp_wave_small"] == 4 and S.stepper_spread.content.stepper_value == "4", settings["sp_wave_small"])
S.stepper_spread.content.hotspot_minus.pressed_callback(); S.stepper_spread.content.hotspot_minus.pressed_callback()
check("spread -2", settings["sp_wave_small"] == 2)
for _ = 1, 3 do S.stepper_spread.content.hotspot_minus.pressed_callback() end
check("spread clamps at 0", settings["sp_wave_small"] == 0 and S.stepper_spread.content.stepper_value == "0")
S.stepper_spread.content.hotspot_value.pressed_callback()
view._widgets_by_name.rw_popup_input.content.input_text = "101"
PopupOwner0 = dofile(BASE .. "/ui/wave_editor_components.lua")
PopupOwner0.Popup.commit(view)
check("spread popup rejects > 100", view._popup ~= nil and view._popup.error ~= nil)
view._widgets_by_name.rw_popup_input.content.input_text = "100"
PopupOwner0.Popup.commit(view)
check("spread popup accepts 100 (the new maximum)", view._popup == nil and settings["sp_wave_small"] == 100 and S.stepper_spread.content.stepper_value == "100")
S.stepper_spread.content.hotspot_plus.pressed_callback()
check("spread stays at 100 (clamped)", settings["sp_wave_small"] == 100)
S.stepper_spread.content.hotspot_minus.pressed_callback()
check("above 10 m the stepper moves in 5 m steps", settings["sp_wave_small"] == 95, settings["sp_wave_small"])
settings["sp_wave_small"] = 12; view:_reload(); view:_apply_screen(true)
S.stepper_spread.content.hotspot_plus.pressed_callback()
check("12 m + click = 17 m (coarse)", settings["sp_wave_small"] == 17, settings["sp_wave_small"])
S.stepper_spread.content.hotspot_minus.pressed_callback(); S.stepper_spread.content.hotspot_minus.pressed_callback()
check("17 -> 12 -> 7 (both clicks start above 10, so both are 5 m steps)", settings["sp_wave_small"] == 7, settings["sp_wave_small"])
settings["sp_wave_small"] = 9; view:_reload(); view:_apply_screen(true)
S.stepper_spread.content.hotspot_plus.pressed_callback()
S.stepper_spread.content.hotspot_plus.pressed_callback()
check("9 -> 10 (fine) -> 15 (coarse)", settings["sp_wave_small"] == 15, settings["sp_wave_small"])
settings["sp_wave_small"] = 12; view:_reload(); view:_apply_screen(true)
S.stepper_every.content.hotspot_plus.pressed_callback()
check("repeat every +1", settings["re_wave_small"] == 11 and S.stepper_every.content.stepper_value == "11", settings["re_wave_small"])
S.stepper_for.content.hotspot_plus.pressed_callback()
check("repeat for +5", settings["rf_wave_small"] == 65 and S.stepper_for.content.stepper_value == "65", settings["rf_wave_small"])
for _ = 1, 20 do S.stepper_every.content.hotspot_minus.pressed_callback() end
check("repeat every clamps at 1", settings["re_wave_small"] == 1)

check("detail rows show the repeat stepper", row(1).content.show_rep and row(1).content.rep_value == "0" and hotspot_runs(row(1), "hotspot_rep_plus") and hotspot_runs(row(1), "hotspot_rep_minus") and hotspot_runs(row(1), "hotspot_rep_value"))
click_row(1, "hotspot_rep_plus")
check("row repeat +1 -> stored as @1", row(1).content.rep_value == "1" and settings["wave_def_wave_small"]:find("@1") ~= nil and view._parts[1].rep == 1, settings["wave_def_wave_small"])
check("repeat stepper text now says seconds", S.stepper_every.content.extra == "extra_seconds", S.stepper_every.content.extra)
click_row(1, "hotspot_rep_value")
view._widgets_by_name.rw_popup_input.content.input_text = "3"
PopupOwner0.Popup.commit(view)
check("row repeat popup sets 3", view._parts[1].rep == 3 and row(1).content.rep_value == "3")
local start_count = view._parts[1].count
for _ = 1, start_count do click_row(1, "hotspot_minus") end
check("initial count may reach 0 while the group repeats", view._parts[1].count == 0 and view._parts[1].rep == 3 and row(1).content.stepper_value == "0", view._parts[1].count)
click_row(1, "hotspot_minus")
check("count stays at 0 (not negative)", view._parts[1].count == 0)
click_row(1, "hotspot_rep_value")
view._widgets_by_name.rw_popup_input.content.input_text = "0"
PopupOwner0.Popup.commit(view)
check("repeat set back to 0 with count 0 -> count restored to 1", view._parts[1].rep == nil and view._parts[1].count == 1)
click_row(1, "hotspot_rep_plus"); click_row(1, "hotspot_plus")
check("wave summary on the list mentions repeats", (function() local w = mod.rw.events.get("wave_small", function(id) return settings[id] end, mod.rw.groups); return mod.rw.groups.summary(w.parts):find("per repeat") ~= nil end)())
click_row(1, "hotspot_rep_minus")
check("repeat -1 back to none", view._parts[1].rep == nil)

-- "Same" tick box: repeat the same amount as the initial spawn ------------------------------------
do
  local p = view._parts[1]
  check("detail rows have the Same tick box (runs while the repeat controls are shown)", row(1).content.show_rep and hotspot_runs(row(1), "hotspot_same") and row(1).content.same_selected == false and view._widgets_by_name.list_header.content.col_7 == "col_same")
  local initial = p.count
  click_row(1, "hotspot_same")
  check("tick: group repeats the same amount (recipe has @=, no number)", view._parts[1].rep_same == true and view._parts[1].rep == nil and settings["wave_def_wave_small"]:find("@=") ~= nil and row(1).content.same_selected == true and row(1).content.rep_value == "=", settings["wave_def_wave_small"])
  check("tick: repeat timing line says seconds (a group now repeats)", S.stepper_every.content.extra == "extra_seconds", S.stepper_every.content.extra)
  check("tick: list summary says 'same amount'", (function() local w = mod.rw.events.get("wave_small", function(id) return settings[id] end, mod.rw.groups); return mod.rw.groups.summary(w.parts):find("same amount on every repeat") ~= nil end)())
  click_row(1, "hotspot_same")
  check("untick: repeating is off again", view._parts[1].rep_same == nil and view._parts[1].rep == nil and row(1).content.same_selected == false and row(1).content.rep_value == "0" and settings["wave_def_wave_small"]:find("@") == nil, settings["wave_def_wave_small"])
  click_row(1, "hotspot_same")
  click_row(1, "hotspot_rep_plus")
  check("using the stepper while ticked leaves 'same' mode and starts from the count (+1)", view._parts[1].rep_same == nil and view._parts[1].rep == initial + 1 and row(1).content.same_selected == false, tostring(view._parts[1].rep) .. " vs " .. tostring(initial + 1))
  click_row(1, "hotspot_same")
  click_row(1, "hotspot_rep_value")
  view._widgets_by_name.rw_popup_input.content.input_text = "4"
  PopupOwner0.Popup.commit(view)
  check("typing a number while ticked replaces 'same' with that number", view._parts[1].rep == 4 and view._parts[1].rep_same == nil)
  click_row(1, "hotspot_same")
  for _ = 1, 100 do click_row(1, "hotspot_minus") end
  check("with Same ticked the initial count cannot go below 1 (a repeat of 0 would do nothing)", view._parts[1].rep_same == true and view._parts[1].count == 1, view._parts[1].count)
  click_row(1, "hotspot_same")
  check("unticked again: the group is back to a plain group", view._parts[1].rep_same == nil and view._parts[1].rep == nil)
end

-- reset restores spread and repeat settings too
click("btn_reset")
check("reset restores spread/repeat defaults", settings["sp_wave_small"] == 3 and settings["re_wave_small"] == 10 and settings["rf_wave_small"] == 60)
click("btn_back")
check("list screen: repeat column header cleared, steppers hidden", view._widgets_by_name.list_header.content.col_6 == "" and not S.stepper_spread.visible and not row(1).content.show_rep)
click_row(1, "hotspot_action")

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
check("chance +1 in detail (the reset above restored 18)", settings["pct_wave_small"] == 19, settings["pct_wave_small"])
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
