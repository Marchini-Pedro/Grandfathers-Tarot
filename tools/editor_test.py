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
  presets = dofile(BASE .. "/catalog/presets.lua"),
  colors = dofile(BASE .. "/catalog/colors.lua"),
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
check("list: row flags (an unchanged standard wave has no action button)", row(1).content.show_check and row(1).content.show_stepper and row(1).content.show_share and not row(1).content.show_action)
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
view._waves[1].modified = true; view:_refresh_rows() -- a changed standard wave shows its Reset button
check("engine rule: list row hotspots run (hover/click work)", hotspot_runs(r1, "hotspot_name") and hotspot_runs(r1, "hotspot_check") and hotspot_runs(r1, "hotspot_minus") and hotspot_runs(r1, "hotspot_value") and hotspot_runs(r1, "hotspot_plus") and hotspot_runs(r1, "hotspot_action"))
check("engine rule: hidden hotspot (Mods) does not run on the list", not hotspot_runs(r1, "hotspot_mods"))
r1.content.hotspot_action.is_hover = true
check("engine rule: action button hover layers show while hovered", pass_visible(r1, pass_by_style(r1, "hotspot_action_highlight")) and pass_visible(r1, pass_by_style(r1, "hotspot_action_frame")))
r1.content.hotspot_action.is_hover = false
check("engine rule: no hover layer when not hovered", not pass_visible(r1, pass_by_style(r1, "hotspot_action_highlight")))
view._waves[1].modified = nil; view:_refresh_rows()
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

-- open detail (click the row)
click_row(1, "hotspot_name")
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

-- typing must not trigger keybinds: the popup raises a flag the entry script's DMF hook reads ----------
do
  local PP = dofile(BASE .. "/ui/wave_editor_components.lua")
  mod.rw.text_input_active = false
  check("no popup open -> keybinds are not suppressed", mod.rw.text_input_active == false)
  click("btn_rename")
  check("rename popup open -> keybinds suppressed while typing", view._popup ~= nil and mod.rw.text_input_active == true)
  PP.Popup.cancel(view)
  check("popup cancelled -> keybinds work again", mod.rw.text_input_active == false)
  click("btn_text")
  check("recipe (text) popup suppresses keybinds", mod.rw.text_input_active == true)
  PP.Popup.commit(view) -- text unchanged: closes without touching the wave
  check("popup confirmed -> keybinds work again", mod.rw.text_input_active == false and view._popup == nil)
  click_row(1, "hotspot_value")
  check("number popup suppresses keybinds too", mod.rw.text_input_active == true)
  PP.Popup.cancel(view)
end

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

-- typing on the picker screen opens the search box by itself ------------------------------------------------
do
  local strokes = {}
  Keyboard = { keystrokes = function() return strokes end }
  local function frame() view:update(0.01, 0, input_stub) end

  frame()
  strokes = { "b" }
  frame()
  check("auto-search: typing on the detail screen does nothing", view._popup == nil)
  strokes = {}

  click("btn_add")
  check("auto-search: picker screen suspends keybinds even with no box open", view._popup == nil and mod.rw.text_input_active == true)
  strokes = { 27, 8, " " } -- special keys (numbers) and a leading space are not text
  frame()
  check("auto-search: special keys and a leading space do not open the box", view._popup == nil)
  strokes = { "\n" }
  frame()
  check("auto-search: control characters do not open the box", view._popup == nil)
  strokes = { "t", "w" }
  frame()
  check("auto-search: typing opens the search box (empty, filter untouched until the widget reads the keys)", view._popup ~= nil and view._popup.spec.value == "" and view._sg.rw_popup_panel[2] == 700 and mod.rw.text_input_active == true)
  strokes = {}
  frame()
  check("auto-search: if the input widget missed the first keys they are filled in next frame, and the list filters", view._widgets_by_name.rw_popup_input.content.input_text == "tw" and view._filter == "tw" and #view._breeds >= 2, tostring(view._widgets_by_name.rw_popup_input.content.input_text) .. "/" .. tostring(view._filter))
  local popup_before = view._popup
  strokes = { "i" }
  frame()
  check("auto-search: typing while the box is open does not reopen or reset it", view._popup == popup_before and view._widgets_by_name.rw_popup_input.content.input_text == "tw")
  strokes = {}

  -- widget that DID read the keys itself: nothing is typed twice
  SP.Popup.cancel(view)
  strokes = { "x" }
  frame()
  view._widgets_by_name.rw_popup_input.content.input_text = "x" -- what the real widget does in the same frame
  strokes = {}
  frame()
  check("auto-search: keys the widget already took are not typed a second time", view._widgets_by_name.rw_popup_input.content.input_text == "x" and view._auto_typed == nil)
  SP.Popup.cancel(view)
  check("auto-search: the box closing on the picker screen keeps keybinds suspended", mod.rw.text_input_active == true)
  view._filter = ""
  click("btn_back")
  check("auto-search: back to the wave editor releases the keybinds", view._screen == "detail" and mod.rw.text_input_active == false)
end

-- stay in the picker after adding, or go back ---------------------------------------------------------------
do
  settings.picker_stay = nil
  click("btn_add")
  check("stay toggle: visible in the picker only, default is 'back to wave'", view._widgets_by_name.btn_stay.visible and view._widgets_by_name.btn_stay.content.hotspot_text == "btn_stay_off")
  click("btn_back")
  check("stay toggle: hidden outside the picker", not view._widgets_by_name.btn_stay.visible)
  click("btn_add")
  click("btn_stay")
  check("stay toggle: click flips the setting and the label", settings.picker_stay == true and view._widgets_by_name.btn_stay.content.hotspot_text == "btn_stay_on" and view._screen == "picker")

  local parts_n = #view._parts
  local breed = view._breeds[1]
  local before = 0; for _, p in ipairs(view._parts) do if p.breed == breed and not p.mods then before = p.count end end
  click_row(1, "hotspot_action")
  check("stay: adding keeps the picker open and adds the enemy", view._screen == "picker" and #view._parts >= parts_n and view._widgets_by_name.btn_stay.visible)
  local after = 0; for _, p in ipairs(view._parts) do if p.breed == breed and not p.mods then after = p.count end end
  check("stay: enemy count went up by one", after == before + 1, before .. " -> " .. after)
  check("stay: a note says what was added", view._widgets_by_name.bottom_title.content.bottom_title:find("picker_added:") ~= nil and view._widgets_by_name.description_text.content.description_text:find("picker_added:") ~= nil, view._widgets_by_name.bottom_title.content.bottom_title)
  local second = view._breeds[2]
  click_row(2, "hotspot_name")
  local has_second = false; for _, p in ipairs(view._parts) do if p.breed == second then has_second = true end end
  check("stay: several different enemies can be added in a row", view._screen == "picker" and has_second)

  -- with the search box open the box stays open too, filter kept
  click("btn_search")
  view._widgets_by_name.rw_popup_input.content.input_text = "twin"
  view:update(0.01, 0, input_stub)
  click_row(1, "hotspot_action")
  check("stay: adding from a filtered list keeps the search box and the filter", view._screen == "picker" and view._popup ~= nil and view._filter == "twin" and #view._breeds == 2)
  click_row(2, "hotspot_action")
  check("stay: ...and can add again", view._popup ~= nil and view._screen == "picker")
  SP.Popup.commit(view)
  view._filter = ""
  click("btn_add")
  check("stay: picker note is cleared when the picker is entered fresh", view._picker_note == nil)
  click("btn_back")

  -- back to wave mode
  click("btn_add")
  click("btn_stay")
  check("back mode: toggle off again", settings.picker_stay == false and view._widgets_by_name.btn_stay.content.hotspot_text == "btn_stay_off")
  click_row(1, "hotspot_action")
  check("back mode: adding returns to the wave", view._screen == "detail" and view._picker_note == nil)
  settings.picker_stay = nil
end

-- modifiers screen ---------------------------------------------------------------
check("detail: Mods button on enemy rows", row(1).content.show_mods and row(1).content.hotspot_mods_text == "btn_mods" and not row(1).content.show_share)
check("engine rule: detail row Mods/stepper/Remove hotspots run, checkbox does not", hotspot_runs(row(1), "hotspot_mods") and hotspot_runs(row(1), "hotspot_plus") and hotspot_runs(row(1), "hotspot_action") and not hotspot_runs(row(1), "hotspot_check"))
click_row(1, "hotspot_mods")
check("mods screen opens", view._screen == "mods" and view._widgets_by_name.description_text.content.description_text:find("view_desc_mods") ~= nil and view._widgets_by_name.btn_back.visible)
do
  -- the description column fits two lines of about 75 characters (Orange, the longest that fitted in game, is 138)
  local longest, which = 0, nil
  for i = 1, 10 do local n = #row(i).content.info; if n > longest then longest, which = n, row(i).content.row_name end end
  check("mods screen: every description fits the two-line column (<= 138 characters)", longest <= 138, tostring(which) .. " " .. longest)
end
check("mods screen lists all 10 modifiers with checkboxes", row(10).visible and #view:_source() == 10 and row(1).content.show_check and not row(1).content.show_stepper and not row(1).content.show_action and not row(1).content.show_mods, row(10).content.row_name)
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
click_row(1, "hotspot_name")

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

-- row actions (Delete / Create / Reset), colours, settings screen ------------------------------------------------
do
  local C = mod.rw.colors
  local spidey = { crusher_front_colour = "turquoise" }
  local named = { turquoise = { 64, 224, 208 } }
  C.init({ kind = mod.rw.groups.kind, option = function(id) return settings[id] end, spidey_setting = function(id) return spidey[id] end, named = function(name) return named[name] end })
  local input_stub3 = { get = function() return nil end, is_null_service = function() return false end }

  click("btn_back")
  check("list: unchanged standard wave shows no action button", not row(1).content.show_action)

  -- colours
  local plain = view._widgets_by_name.rw_row_1.content.info:gsub("{#[^}]*}", "")
  check("colours: list summary carries colour tags, visible text unchanged", row(1).content.info:find("{#color(", 1, true) ~= nil and plain == mod.rw.groups.summary(view._waves[1].parts, 95), plain)
  settings.colour_enemies = false; view:_refresh_rows()
  check("colours: switched off -> plain text", row(1).content.info:find("{#", 1, true) == nil)
  settings.colour_enemies = nil; view:_refresh_rows()
  check("colours: kind palette (poxwalker is normal, hound is special, spawn is boss)", table.concat(C.rgb("chaos_poxwalker"), ",") == "200,215,200" and table.concat(C.rgb("chaos_hound"), ",") == "255,160,60" and table.concat(C.rgb("chaos_spawn"), ",") == "240,90,90")
  check("colours: Spidey Sense colour wins for the enemies it knows (crusher)", table.concat(C.rgb("chaos_ogryn_executor"), ",") == "64,224,208")
  C.clear_cache(); settings.colour_spidey = false
  check("colours: Spidey Sense colours can be switched off", table.concat(C.rgb("chaos_ogryn_executor"), ",") == "235,205,90")
  settings.colour_spidey = nil; C.clear_cache()
  spidey.crusher_front_colour = "no_such_colour"
  check("colours: unknown Spidey Sense colour name falls back to the palette", table.concat(C.rgb("chaos_ogryn_executor"), ",") == "235,205,90")
  spidey.crusher_front_colour = "turquoise"; C.clear_cache()

  click_row(1, "hotspot_name")
  check("colours: detail rows colour the enemy name", table.concat({ table.unpack(row(1).style.row_name.text_color, 2, 4) }, ",") == "200,215,200", table.concat(row(1).style.row_name.text_color, ","))
  click("btn_back"); click("btn_add")
  local crusher_row
  for off = 0, #view._breeds - 1, 10 do
    view._offset = off; view:_refresh_rows()
    for i = 1, 10 do if row(i).visible and row(i).content.row_name == "Crusher" then crusher_row = i; break end end
    if crusher_row then break end
  end
  check("colours: picker colours enemy names (crusher uses the Spidey Sense colour)", crusher_row ~= nil and table.concat({ table.unpack(row(crusher_row).style.row_name.text_color, 2, 4) }, ",") == "64,224,208", tostring(crusher_row))
  view._offset = 0
  click("btn_back"); click("btn_back")

  -- Delete / Create / Reset
  view._offset = 12; view:_refresh_rows()
  check("actions: custom slot with enemies shows Delete, empty slots show Create", row(1).content.hotspot_action_text == "btn_delete" and row(2).content.hotspot_action_text == "btn_create" and row(1).content.show_action, row(1).content.hotspot_action_text .. "/" .. row(2).content.hotspot_action_text)
  click_row(1, "hotspot_action")
  check("actions: first click on Delete only asks 'Sure?'", row(1).content.hotspot_action_text == "btn_sure" and view._screen == "list")
  check("actions: the custom wave is still there", #view._waves[13].parts == 1 and settings["on_custom_1"] == true)
  click_row(1, "hotspot_action")
  check("actions: second click deletes it (slot emptied, wave off)", (view._waves[13].parts == nil or #view._waves[13].parts == 0) and settings["on_custom_1"] == false and row(1).content.hotspot_action_text == "btn_create")
  -- the confirmation runs out
  settings["wave_def_custom_3"] = "Temp\t3 hounds"; view:_reload(); view:_refresh_rows()
  click_row(3, "hotspot_action")
  check("actions: pending confirmation shown", row(3).content.hotspot_action_text == "btn_sure")
  view:update(0.01, 100, input_stub3)
  check("actions: the confirmation expires after a few seconds", row(3).content.hotspot_action_text == "btn_delete" and view._confirm == nil)
  view._confirm = nil; settings["wave_def_custom_3"] = ""; view._offset = 0; view:_reload(); view:_refresh_rows()

  -- standard wave: Reset only when changed
  settings["pct_wave_small"] = 33
  settings["wave_def_wave_small"] = "My Small\t4 hounds"; view:_reload(); view:_refresh_rows()
  check("actions: a changed standard wave shows Reset", row(1).content.show_action and row(1).content.hotspot_action_text == "btn_reset")
  click_row(1, "hotspot_action"); click_row(1, "hotspot_action")
  check("actions: Reset (after Sure?) restores the built-in wave", settings["wave_def_wave_small"] == "" and settings["pct_wave_small"] == 18 and row(1).content.row_name == "Small Wave" and not row(1).content.show_action)
  settings["pct_wave_small"] = 18

  -- settings screen
  check("settings: button visible on the wave list", view._widgets_by_name.btn_settings.visible)
  click("btn_settings")
  check("settings: screen opens with rows, Back only", view._screen == "settings" and row(10).visible and not view._widgets_by_name.btn_settings.visible and view._widgets_by_name.btn_back.visible and view._widgets_by_name.hint_text.visible)
  -- the screen has 11 rows (capacity 10): scroll just enough to bring the wanted row into view
  local function find_row(id)
    for idx, it in ipairs(view._settings_rows) do
      if it.id == id then
        view._offset = idx > 10 and idx - 10 or 0
        view:_refresh_rows(); view:_set_interaction_enabled()
        return idx - view._offset, it
      end
    end
  end
  local ri, rit = find_row("interval_random")
  check("settings: random-time toggle defaults on", rit and rit.on == true and row(ri).content.show_check and row(ri).content.checkbox_selected)
  local mi, mit = find_row("interval_min")
  check("settings: minimum time row shows the minimum label while random is on", mit.label == "set_interval_min" and row(mi).content.show_stepper and row(mi).content.stepper_value == "150")
  click_row(mi, "hotspot_plus")
  check("settings: stepper adds 5 seconds and writes the setting", settings.interval_min == 155 and row(mi).content.stepper_value == "155", tostring(settings.interval_min))
  click_row(mi, "hotspot_minus"); click_row(mi, "hotspot_minus")
  check("settings: stepper goes down", settings.interval_min == 145)
  settings.interval_min = 5; view:_reload_settings(); view:_apply_screen(true)
  click_row(mi, "hotspot_minus")
  check("settings: stepper stops at the minimum (5 seconds)", settings.interval_min == 5)
  click_row(ri, "hotspot_check")
  check("settings: random off -> minimum row becomes the fixed time, maximum row muted", settings.interval_random == false and view:_item_at(mi).label == "set_interval_fixed" and view:_item_at(find_row("interval_max")).muted == true)
  click_row(ri, "hotspot_name")
  check("settings: clicking the row name toggles too", settings.interval_random == true and view:_item_at(find_row("interval_max")).muted == false)
  local mx = find_row("interval_max")
  click_row(mx, "hotspot_value")
  check("settings: clicking a number opens a popup limited to its range", view._popup ~= nil and view._popup.spec.min == 5 and view._popup.spec.max == 1800)
  view._widgets_by_name.rw_popup_input.content.input_text = "40"; view:update(0.01, 0, input_stub3)
  local PPs = dofile(BASE .. "/ui/wave_editor_components.lua"); PPs.Popup.commit(view)
  check("settings: popup writes the number", settings.interval_max == 40 and row(mx).content.stepper_value == "40")
  local vi = find_row("vote_duration")
  click_row(vi, "hotspot_plus"); check("settings: vote window steps by 5", settings.vote_duration == 30)
  local pi = find_row("hud_show_percent"); click_row(pi, "hotspot_check")
  check("settings: percent toggle writes hud_show_percent", settings.hud_show_percent == false)
  click_row(pi, "hotspot_check"); check("settings: ...and back on", settings.hud_show_percent == true)
  local di = find_row("mode"); click_row(di, "hotspot_check")
  local vote_on = settings.mode == "vote"
  click_row(di, "hotspot_check")
  check("settings: vote mode toggle writes mode=vote, then random", vote_on and settings.mode == "random")
  local ci = find_row("colour_enemies"); click_row(ci, "hotspot_check")
  check("settings: colour toggle mutes the Spidey Sense row", settings.colour_enemies == false and view:_item_at(find_row("colour_spidey")).muted == true)
  click_row(ci, "hotspot_check")
  local longest, which = 0, nil
  for i = 1, #view._settings_rows do local n = #view._settings_rows[i].info; if n > longest then longest, which = n, view._settings_rows[i].id end end
  check("settings: every description fits two lines (<= 138 characters)", longest <= 138, tostring(which) .. " " .. longest)
  click("btn_back")
  check("settings: back to the wave list", view._screen == "list" and view._widgets_by_name.btn_settings.visible)
  settings.interval_min, settings.interval_max, settings.vote_duration, settings.interval_random = nil, nil, nil, nil
  -- the presets tests below expect the custom wave from the custom-slot workflow (deleted above)
  settings["wave_def_custom_1"] = "Custom 1\t3 hounds"; settings["on_custom_1"] = true; view:_reload(); view:_apply_screen(true)
end

-- per-wave spawn distances in the detail screen ------------------------------------------------------------------
do
  local input_stub4 = { get = function() return nil end, is_null_service = function() return false end }
  local W = view._widgets_by_name
  click_row(1, "hotspot_name")
  check("distance: both steppers shown in the detail screen, auto by default", W.stepper_dmin.visible and W.stepper_dmax.visible and W.stepper_dmin.content.stepper_value == "val_auto" and W.stepper_dmin.content.extra == "extra_dist_auto:22" and W.stepper_dmax.content.extra == "extra_dist_auto:65", W.stepper_dmin.content.extra .. "/" .. W.stepper_dmax.content.extra)
  click("stepper_dmin", "hotspot_plus")
  check("distance: + sets 5 m and the label says it is this wave's own value", settings.dmin_wave_small == 5 and W.stepper_dmin.content.stepper_value == "5" and W.stepper_dmin.content.extra == "extra_dist_own")
  click("stepper_dmin", "hotspot_value")
  check("distance: clicking the value opens a popup (0 to 200)", view._popup ~= nil and view._popup.spec.min == 0 and view._popup.spec.max == 200)
  view._widgets_by_name.rw_popup_input.content.input_text = "45"; view:update(0.01, 0, input_stub4)
  local PP4 = dofile(BASE .. "/ui/wave_editor_components.lua"); PP4.Popup.commit(view)
  check("distance: popup sets the minimum", settings.dmin_wave_small == 45 and W.stepper_dmin.content.stepper_value == "45")
  click("stepper_dmax", "hotspot_plus"); click("stepper_dmax", "hotspot_plus")
  check("distance: maximum steps by 5", settings.dmax_wave_small == 10)
  click("stepper_dmin", "hotspot_minus")
  check("distance: minus steps back", settings.dmin_wave_small == 40)
  settings.dmin_wave_small = 0; view:_reload(); view:_apply_screen(true); click("stepper_dmin", "hotspot_minus")
  check("distance: cannot go below 0 (auto)", settings.dmin_wave_small == 0 and W.stepper_dmin.content.stepper_value == "val_auto")
  click("btn_reset")
  check("distance: Reset to default puts both back to auto", settings.dmin_wave_small == 0 and settings.dmax_wave_small == 0 and W.stepper_dmax.content.stepper_value == "val_auto")
  click("btn_back")
  check("distance: steppers hidden again on the list", not W.stepper_dmin.visible and not W.stepper_dmax.visible and view._screen == "list")
end
-- sharing one wave ------------------------------------------------------------------------------------------------
do
  local P = mod.rw.presets
  local PPw = dofile(BASE .. "/ui/wave_editor_components.lua")
  local W = view._widgets_by_name
  local inp = { get = function() return nil end, is_null_service = function() return false end }
  local clip_text
  Clipboard = { get = function() return clip_text end, put = function(t) clip_text = t; return true end }
  local function type_into(text) view._widgets_by_name.rw_popup_input.content.input_text = text; view:update(0.01, 0, inp) end

  check("share: Share only in the detail screen, Import wave only on the list", W.btn_wimport.visible and not W.btn_share.visible)
  -- a custom wave to share
  settings["wave_def_custom_4"] = "Pack Attack\t4 hounds, 2 scab rager[enraged]"; settings["on_custom_4"] = true
  settings["pct_custom_4"] = 33; settings["dmin_custom_4"] = 40; settings["dmax_custom_4"] = 90
  view:_reload(); view._offset = 0; view:_refresh_rows()
  view._offset = 3; view:_refresh_rows()
  click_row(1, "hotspot_name") -- 4th wave of the 3-offset list is... find it by key instead
  if view._key ~= "custom_4" then
    click("btn_back"); view._offset = 0; view:_open_detail("custom_4")
  end
  check("share: custom_4 detail open", view._screen == "detail" and view._key == "custom_4" and W.btn_share.visible, tostring(view._key))
  click("btn_share")
  local shared = view._widgets_by_name.rw_popup_input.content.input_text
  check("share: the popup shows the wave text and copies it", view._popup ~= nil and shared:sub(1, 5) == "RWW1|" and clip_text == shared and view._popup.spec.hint == "popup_share_hint_copied")
  local decoded = P.decode_wave(shared, mod.rw.events, mod.rw.groups)
  check("share: the text decodes to this wave", decoded and decoded.name == "Pack Attack" and decoded.pct == 33 and decoded.dmin == 40 and decoded.dmax == 90 and decoded.recipe:find("hound") ~= nil)
  PPw.Popup.cancel(view)

  -- import over this wave: paste a different wave over the text
  local other = P.encode_wave({ key = "custom_9", name = "Friend Wave", recipe = "6 mutants", enabled = true, pct = 12, cd = 75, sp = 6, re = 10, rf = 60, dmin = 0, dmax = 70 })
  click("btn_share")
  type_into(other)
  PPw.Popup.commit(view)
  check("share: pasting a friend's wave over the text replaces this wave", view._popup == nil and view._wave.name == "Friend Wave" and settings["pct_custom_4"] == 12 and settings["dmax_custom_4"] == 70 and settings["dmin_custom_4"] == 0 and #view._parts == 1 and view._parts[1].breed == "cultist_mutant" and view._parts[1].count == 6, tostring(view._wave.name))
  click("btn_share"); type_into("RW1|a preset|0|0000"); PPw.Popup.commit(view)
  check("share: a whole preset pasted here is refused with a pointer to the Presets screen", view._popup ~= nil and tostring(view._popup.error):find("Presets screen") ~= nil, tostring(view._popup and view._popup.error))
  PPw.Popup.cancel(view)
  click("btn_share"); type_into(other:sub(1, 30) .. "x" .. other:sub(31)); PPw.Popup.commit(view)
  check("share: an altered wave text is refused and changes nothing", view._popup ~= nil and view._popup.error ~= nil and view._wave.name == "Friend Wave")
  PPw.Popup.cancel(view)
  click("btn_share"); PPw.Popup.commit(view)
  check("share: OK on the unchanged text just closes", view._popup == nil and view._wave.name == "Friend Wave")

  -- import from the list into the first free custom slot
  click("btn_back")
  for i = 1, 20 do settings["wave_def_custom_" .. i] = nil end
  settings["wave_def_custom_1"] = "Taken\t2 hounds"; settings["wave_def_custom_2"] = "Taken\t2 hounds"
  view:_reload(); view._offset = 0; view:_refresh_rows()
  clip_text = P.encode_wave({ key = "custom_5", name = "From Clipboard", recipe = "3 crushers[purple]", enabled = true, pct = 20, cd = 60, sp = 3, re = 10, rf = 60, dmin = 25, dmax = 0 })
  click("btn_wimport")
  check("share: Import wave prefills a wave from the clipboard and names the target slot", view._popup ~= nil and view._popup.spec.hint == "popup_wimport_hint_filled:Custom 3" and view._widgets_by_name.rw_popup_input.content.input_text == clip_text, tostring(view._popup and view._popup.spec.hint))
  PPw.Popup.commit(view)
  check("share: OK imports into the first free custom slot and opens it", view._screen == "detail" and view._key == "custom_3" and view._wave.name == "From Clipboard" and settings["on_custom_3"] == true and settings["dmin_custom_3"] == 25 and #view._parts == 1, tostring(view._key))
  check("share: the other slots were not touched", settings["wave_def_custom_1"] == "Taken\t2 hounds" and settings["wave_def_custom_4"] == nil or settings["wave_def_custom_4"] == "")
  click("btn_back")
  click("btn_wimport")
  type_into("RWW1|garbage"); PPw.Popup.commit(view)
  check("share: a bad paste keeps the import box open with the reason", view._popup ~= nil and view._popup.error ~= nil)
  PPw.Popup.cancel(view)
  -- no free slot
  for i = 1, 20 do settings["wave_def_custom_" .. i] = "Full " .. i .. "\t1 hound" end
  view:_reload(); view:_refresh_rows(); echoes = {}
  click("btn_wimport")
  check("share: no free custom slot -> a message and no popup", view._popup == nil and echoes[#echoes] == "msg_no_free_slot", tostring(echoes[#echoes]))
  for i = 1, 20 do settings["wave_def_custom_" .. i] = nil; settings["on_custom_" .. i] = nil; settings["pct_custom_" .. i] = nil; settings["dmin_custom_" .. i] = nil; settings["dmax_custom_" .. i] = nil; settings["cd_custom_" .. i] = nil; settings["sp_custom_" .. i] = nil; settings["re_custom_" .. i] = nil; settings["rf_custom_" .. i] = nil end
  settings["wave_def_custom_1"] = "Custom 1\t3 hounds"; settings["on_custom_1"] = true
  view:_reload(); view._offset = 0; view:_apply_screen()
end
-- presets ----------------------------------------------------------------------------------------------------
do
  local PP = dofile(BASE .. "/ui/wave_editor_components.lua")
  local P = mod.rw.presets
  local function getter(id) return settings[id] end
  local input_stub2 = { get = function() return nil end, is_null_service = function() return false end }
  local clip_text, clip_fail = nil, false
  Clipboard = {
    get = function() return clip_text end,
    put = function(text) if clip_fail then return false end clip_text = text; return true end,
  }
  local function note() return view._widgets_by_name.bottom_title.content.bottom_title end
  local function type_into_popup(text) view._widgets_by_name.rw_popup_input.content.input_text = text; view:update(0.01, 0, input_stub2) end

  -- Back is drawn (and its hotspot handled) before the buttons of the screen it returns to. A button of the
  -- destination screen at the same spot would receive the same click in the same frame (click-through), e.g.
  -- Back on a wave's screen opening the presets page. So Back must not overlap any destination button.
  do
    local sg = view._definitions.scenegraph_definition
    local function overlaps(a, b)
      local ax, ay, aw, ah = sg[a].position[1], sg[a].position[2], sg[a].size[1], sg[a].size[2]
      local bx, by, bw, bh = sg[b].position[1], sg[b].position[2], sg[b].size[1], sg[b].size[2]
      return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
    end
    local hit = {}
    for _, name in ipairs({ "btn_presets", "btn_rename", "btn_text", "btn_add", "btn_enabled", "btn_reset", "stepper_chance", "stepper_cooldown", "stepper_spread", "stepper_every", "stepper_for", "btn_search", "btn_stay" }) do
      if overlaps("btn_back", name) then hit[#hit + 1] = name end
    end
    check("Back does not overlap any button of the screens it returns to (no click-through)", #hit == 0, table.concat(hit, ","))

    -- widgets shown together on one screen must not overlap and must stay inside the bottom panel
    local screens = {
      list = { "btn_presets", "btn_settings", "btn_wimport", "btn_back" },
      detail = { "btn_back", "btn_rename", "btn_text", "btn_add", "btn_enabled", "btn_reset", "stepper_chance", "stepper_cooldown", "stepper_spread", "stepper_every", "stepper_for", "stepper_dmin", "stepper_dmax", "btn_share" },
      picker = { "btn_back", "btn_search", "btn_stay" },
      preset_view = { "btn_back", "btn_pload", "btn_psave", "btn_prename", "btn_pexport", "btn_pimport", "btn_pundo", "btn_pclear" },
    }
    local problems = {}
    local panel = sg.bottom_panel
    for screen, names in pairs(screens) do
      for i = 1, #names do
        local n = sg[names[i]]
        if n.position[2] < panel.position[2] or n.position[2] + n.size[2] > panel.position[2] + panel.size[2] or n.position[1] + n.size[1] > panel.position[1] + panel.size[1] then
          problems[#problems + 1] = screen .. ":" .. names[i] .. " outside the panel"
        end
        for j = i + 1, #names do
          if overlaps(names[i], names[j]) then problems[#problems + 1] = screen .. ":" .. names[i] .. "/" .. names[j] end
        end
      end
    end
    check("layout: widgets of one screen never overlap and stay inside the bottom panel", #problems == 0, table.concat(problems, ", "))
    check("layout: the bottom panel ends above the input legend (y <= 1030)", panel.position[2] + panel.size[2] <= 1030)
  end

  click("btn_back")
  check("presets: Presets button only on the wave list", view._screen == "list" and view._widgets_by_name.btn_presets.visible and not view._widgets_by_name.btn_pload.visible)
  click("btn_presets")
  check("presets: screen lists exactly 5 slots, all empty", view._screen == "presets" and row(5).visible and not row(6).visible and row(1).content.info == "preset_slot_empty" and row(1).content.row_name == "1. Preset 1")
  check("presets: only Back on the presets screen", view._widgets_by_name.btn_back.visible and not view._widgets_by_name.btn_presets.visible and not view._widgets_by_name.btn_psave.visible and view._widgets_by_name.hint_text.visible)
  click("btn_back")
  check("presets: back returns to the wave list", view._screen == "list")
  click("btn_presets")
  click_row(2, "hotspot_action")
  check("presets: opening a slot shows its screen and buttons", view._screen == "preset_view" and view._preset_index == 2 and view._widgets_by_name.btn_psave.visible and view._widgets_by_name.btn_pload.visible and view._widgets_by_name.btn_pexport.visible and view._widgets_by_name.btn_pimport.visible)
  check("presets: empty slot has no Clear and no Undo button", not view._widgets_by_name.btn_pclear.visible and not view._widgets_by_name.btn_pundo.visible and note() == "preset_slot_empty_long")
  click("btn_pload"); check("presets: loading an empty slot only says so", note() == "preset_nothing_to_load" and settings.preset_undo == nil)
  click("btn_pexport"); check("presets: exporting an empty slot only says so", view._popup == nil and note() == "preset_nothing_to_export")
  click("btn_prename"); check("presets: renaming an empty slot asks to save first", view._popup == nil and note() == "preset_save_first")

  -- save the current setup (custom_1 has one enemy and is enabled; make one more visible change)
  settings["pct_wave_small"] = 33
  click("btn_psave")
  local saved = P.read(getter, "preset_2", mod.rw.events, mod.rw.groups)
  check("presets: save stores the changed waves under the default name", saved and saved.name == "Preset 2" and #saved.waves == 2 and note():find("preset_saved:Preset 2,2") ~= nil, saved and #saved.waves)
  check("presets: the open screen lists them and offers Clear", row(2).visible and not row(3).visible and view._widgets_by_name.btn_pclear.visible)

  click("btn_prename")
  check("presets: rename opens a popup limited to 24 characters", view._popup ~= nil and view._popup.spec.max_length == 24)
  type_into_popup("Boss   Rush")
  PP.Popup.commit(view)
  check("presets: renamed", P.read(getter, "preset_2", mod.rw.events, mod.rw.groups).name == "Boss Rush" and view._preset_slots[2].name == "Boss Rush" and view._widgets_by_name.description_text.content.description_text:find("Boss Rush") ~= nil)

  -- overwrite the setup, then load the preset: everything comes back, and Undo returns the overwritten setup
  settings["pct_wave_small"] = 1; settings["on_custom_1"] = false
  click("btn_pload")
  check("presets: load restores the saved setup", settings["pct_wave_small"] == 33 and settings["on_custom_1"] == true and note():find("preset_loaded:Boss Rush,2") ~= nil, tostring(settings["pct_wave_small"]))
  check("presets: load kept the replaced setup for undo, and the Undo button appears", settings.preset_undo ~= nil and settings.preset_undo ~= "" and view._widgets_by_name.btn_pundo.visible)
  click("btn_pundo")
  check("presets: undo brings the replaced setup back and consumes the backup", settings["pct_wave_small"] == 1 and settings["on_custom_1"] == false and settings.preset_undo == "" and not view._widgets_by_name.btn_pundo.visible and note() == "preset_undone")
  click("btn_pundo"); check("presets: a second undo says there is nothing to undo", note() == "preset_nothing_to_undo")

  -- export: text in the popup and on the clipboard
  click("btn_pexport")
  local exported = view._widgets_by_name.rw_popup_input.content.input_text
  check("presets: export shows the text and copies it", view._popup ~= nil and exported:sub(1, 4) == "RW1|" and clip_text == exported and view._popup.spec.hint == "popup_export_hint_copied")
  PP.Popup.cancel(view)
  clip_fail = true; click("btn_pexport")
  check("presets: when the clipboard is unavailable the hint says to copy by hand", view._popup ~= nil and view._popup.spec.hint == "popup_export_hint")
  PP.Popup.cancel(view); clip_fail = false

  -- import into slot 4: clipboard prefill + OK, without typing anything
  click("btn_back"); click_row(4, "hotspot_action")
  clip_text = exported
  click("btn_pimport")
  check("presets: import prefills a preset found on the clipboard", view._popup ~= nil and view._widgets_by_name.rw_popup_input.content.input_text == exported and view._popup.spec.hint == "popup_import_hint_filled:4")
  PP.Popup.commit(view)
  local imported = P.read(getter, "preset_4", mod.rw.events, mod.rw.groups)
  check("presets: OK on the prefilled text still imports it (unchanged text is not treated as a cancel)", view._popup == nil and imported and imported.name == "Boss Rush" and #imported.waves == 2 and note():find("preset_imported:Boss Rush,2") ~= nil, tostring(note()))
  click("btn_back")
  check("presets: the list shows both slots", row(2).content.row_name == "2. Boss Rush" and row(4).content.row_name == "4. Boss Rush" and row(2).content.info:find("preset_slot_info:2") ~= nil and row(3).content.info == "preset_slot_empty")

  -- import: nothing on the clipboard, bad text keeps the popup open, good text imports
  click_row(3, "hotspot_action")
  clip_text = "just some other text"
  click("btn_pimport")
  check("presets: no preset on the clipboard -> empty box with the plain hint", view._widgets_by_name.rw_popup_input.content.input_text == "" and view._popup.spec.hint == "popup_import_hint:3")
  type_into_popup("RW1|nonsense")
  PP.Popup.commit(view)
  check("presets: a bad paste keeps the box open with an error and changes nothing", view._popup ~= nil and view._popup.error ~= nil and P.read(getter, "preset_3", mod.rw.events, mod.rw.groups) == nil, tostring(view._popup and view._popup.error))
  type_into_popup(exported)
  PP.Popup.commit(view)
  check("presets: a good paste imports", view._popup == nil and P.read(getter, "preset_3", mod.rw.events, mod.rw.groups) ~= nil)
  PP.Popup.cancel(view)

  -- clear
  click("btn_pclear")
  check("presets: clear empties the slot", P.read(getter, "preset_3", mod.rw.events, mod.rw.groups) == nil and settings.preset_3 == "" and not view._widgets_by_name.btn_pclear.visible and note() == "preset_cleared")

  -- a damaged slot is shown, can be cleared, and loading it is refused
  settings.preset_5 = "garbage"
  click("btn_back"); click_row(5, "hotspot_action")
  check("presets: damaged slot is flagged, offers Clear, will not load", row == row and view._widgets_by_name.btn_pclear.visible and view._preset_slots[5].problem ~= nil)
  click("btn_pload")
  check("presets: loading a damaged slot changes nothing", note() == "preset_nothing_to_load" and settings.preset_undo == "")
  click("btn_pclear")

  -- back navigation and the keybind flag are unaffected
  view:_on_back_pressed()
  check("presets: back key goes preset -> presets -> list", view._screen == "presets")
  view:_on_back_pressed()
  check("presets: ...and then to the wave list, keybinds not suppressed", view._screen == "list" and mod.rw.text_input_active == false)
  click("btn_add") -- no-op guard: Add is a detail-only button
  check("presets: detail-only buttons stay hidden on the list", not view._widgets_by_name.btn_add.visible)
  settings.pct_wave_small = 18; settings.on_custom_1 = true
end
-- last: closing the whole editor while a popup is open must release the keybinds
do
  local PP = dofile(BASE .. "/ui/wave_editor_components.lua")
  PP.Popup.open(view, { label = "x", value = "1", numeric = true, min = 0, max = 9, integer = true, set = function() end })
  check("a popup is open and keybinds are suppressed", mod.rw.text_input_active == true)
  view:on_exit()
  check("closing the whole editor while a popup is open releases the keybinds", mod.rw.text_input_active == false and view._popup == nil)
end

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
