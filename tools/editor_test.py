"""Drives the real wave editor view files against stubbed engine classes.

Not a substitute for the game, but it executes the actual view/blueprint/component
code paths (screen switching, row filling, callbacks, popup, persistence) so that
nil-index and logic bugs show up offline.
Run:  python tools/editor_test.py   (needs `lupa`, see CLAUDE.md)
"""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
from lua_test_runtime import LuaRuntime

MODROOT = os.path.abspath(os.path.join(HERE, "..")).replace("\\", "/")
lua = LuaRuntime(unpack_returned_tuples=True)

harness = r'''
local MODROOT, DUMP, UI_DIR, UI_REAL = ...
local BASE = MODROOT .. "/scripts/mods/RealmsWaves"

-- ---- engine stubs ---------------------------------------------------------
function table.clone(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == "table" and table.clone(v) or v end return c end
table.clone_instance = table.clone
function math.clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
unpack = unpack or table.unpack
table.unpack = table.unpack or unpack
-- Test-only callback contract from game reference 419fe18d4. Resolve methods
-- at invocation and preserve nils and multiple returns, with at most five binds.
ferror = error
function callback(target, ...)
  local method = type(target) == "table" and select(1, ...) or nil
  if type(target) ~= "table" and type(target) ~= "function" then error("callback(...) incorrectly called") end
  local offset = type(target) == "table" and 1 or 0
  local bound, count = { ... }, select("#", ...) - offset
  if count > 5 then return nil end
  if type(target) == "function" and count == 0 then return target end
  return function(...)
    local args, n = {}, select("#", ...)
    for i = 1, count do args[i] = bound[i + offset] end
    for i = 1, n do args[count + i] = select(i, ...) end
    if method then return target[method](target, unpack(args, 1, count + n)) end
    return target(unpack(args, 1, count + n))
  end
end

local UIWidget = {}
UIWidget.create_definition = function(passes, node_id, content, size)
  local def = { passes = passes, node_id = node_id, content = {}, style = {}, size = size }
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
  -- the game's text measuring: a fake that gives 24 per line of `renderer.per_line` letters (17 by default), or fails
  ["scripts/utilities/ui/text"] = { text_height = function(renderer, text, style, size, max_extents)
    if renderer.fail then error("no gui") end
    return 24 * math.max(1, math.ceil(#text / (renderer.per_line or 17)))
  end },
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
  self._render_settings = {} -- the real BaseView.init makes it too (base_view.lua:31)
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
mod.io_dofile = function(self, path) return dofile(MODROOT .. "/" .. path:gsub("^RealmsWaves/", "") .. ".lua") end
get_mod = function(name) return mod end
Managers = { ui = { closed = nil, close_view = function(self, n) self.closed = n end } }

mod.rw = {
  events = dofile(BASE .. "/catalog/events.lua"),
  groups = dofile(BASE .. "/catalog/groups.lua"),
  presets = dofile(BASE .. "/catalog/presets.lua"),
  colors = dofile(BASE .. "/catalog/colors.lua"),
  cards = dofile(BASE .. "/catalog/cards.lua"),
}

local results = {}
local function check(name, cond, detail)
  results[#results+1] = (cond and "PASS " or "FAIL ") .. name .. (detail and (" -- " .. tostring(detail)) or "")
  -- a failure is also written at once, so that a later crash of the harness does not hide it
  if not cond then io.stderr:write("FAIL " .. name .. " -- " .. tostring(detail) .. "\n") end
end

-- ---- load the real view ------------------------------------------------------
do
  local function identity(...) return ... end
  local fn=callback(identity, nil, "bound", nil)
  local values={fn("call", nil)}
  check("callback fixture: binds and call-time nils preserve their argument positions", select("#",fn("call",nil))==5 and values[2]=="bound" and values[4]=="call")
  local object={method=function(self,...) return "old",... end}
  local bound=callback(object,"method",nil,3)
  object.method=function(self,...) return "new",self,... end
  local tag,owner,a,b,c=bound(4)
  check("callback fixture: method lookup is dynamic and forwards self/multiple returns", tag=="new" and owner==object and a==nil and b==3 and c==4)
  check("callback fixture: zero binds retain function identity and excess binds are rejected", callback(identity)==identity and callback(identity,1,2,3,4,5,6)==nil and callback(object,"method",1,2,3,4,5,6)==nil and not pcall(callback,false))
end
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

-- the Cauldron (the screen "detail") has its own rows, every other table screen the generic ones
local function row(i) return view._screen == "detail" and view._widgets_by_name["rw_erow_" .. i] or view._widgets_by_name["rw_row_" .. i] end
local function click(widget_name, hotspot) view._widgets_by_name[widget_name].content[hotspot or "hotspot"].pressed_callback() end
local function click_row(i, hotspot) row(i).content[hotspot].pressed_callback() end

-- the Deck: the home screen is a grid of card tiles
local D = view._widgets_by_name
local function tile(i) return view._widgets_by_name["rw_tile_" .. i] end
-- the toggles of a tile act when the button is let go (released_callback: a card held down is being dragged), the Edit pill and the pips when it is pressed
local function click_tile(i, hotspot)
  local hs = tile(i).content[hotspot or "hotspot_top"]
  hs.pressed_callback()
  if hs.released_callback then hs.released_callback() end
end
local function open_card(i) click_tile(i, "hotspot_edit") end
local function blank_tile() return view._widgets_by_name.rw_tile_blank end
local function plain(text) return (text:gsub("{#[^}]*}", "")) end

check("deck: the model has 100 cards (12 standard + 88 custom slots, Events.MAX_CARDS) and the slots are the rest", #view._waves == 100 and mod.rw.events.MAX_CARDS == 100 and mod.rw.events.CUSTOM_SLOTS == 88 and #mod.rw.events.keys() == 100, #view._waves)
check("deck: 12 cards and the blank tile (the empty custom slots are not cards)", #view._deck == 13 and view._deck[13].blank == true and view._deck_free ~= nil and view._deck_free.key == "custom_1", #view._deck)
check("deck: page one shows 12 tiles, the blank tile in slot 13, no more", tile(1).visible and tile(12).visible and not tile(13).visible and not tile(14).visible and blank_tile().visible)
check("deck: the old table is gone (rows, header and panel hidden)", not row(1).visible and not D.list_header.visible and not D.list_panel.visible)
check("deck: tiles sit in a grid of 7 columns (228 wide, 12 apart) from (126, 190)", view._sg.rw_tile_1[1] == 126 and view._sg.rw_tile_1[2] == 190 and view._sg.rw_tile_2[1] == 126 + 240 and view._sg.rw_tile_8[1] == 126 and view._sg.rw_tile_8[2] == 190 + 270 + 12 and view._sg.rw_tile_blank[1] == 126 + 240 * 5 and view._sg.rw_tile_blank[2] == 190 + 282)
check("deck: the grid and the scroll buttons stay on the screen and above the bottom panel", view._sg.rw_tile_7[1] + 228 <= 1815 and view._sg.rw_tile_8[2] + 270 <= 750 and view._sg.scroll_up[1] == 1826 and view._sg.scroll_up[2] == 190)
check("deck: first tile is The Fool, a swarm card, 8 Poxwalker on its first line", tile(1).content.name == "The Fool" and tile(1).content.suit_label == "SWARM" and plain(tile(1).content.comp):find("^8 Poxwalker") ~= nil, plain(tile(1).content.comp))
check("deck: the whisper of the suit stands under the composition, in quotes", tile(1).content.whisper == "\"Too many to count.\"")
check("deck: the swarm mark (four dots) is drawn, no triangles", tile(1).style.icon_c1.visible and tile(1).style.icon_c4.visible and not tile(1).style.icon_t1.visible)
check("deck: ten chance pips, filled up to the card's chance (The Fool 5: five in the accent, opaque, the rest faint in the frame colour; Strength 2: two)", tile(1).style.pip_5.color[1] == 255 and tile(1).style.pip_6.color[1] == 130 and tile(12).style.pip_2.color[1] == 255 and tile(12).style.pip_3.color[1] == 130 and tile(12).style.pip_10.visible)
check("deck: the state line says the card is in the draw, with a glow and its Edit corner", tile(1).content.state_left == "tile_in" and tile(1).content.state_clock == "" and tile(1).style.glow.visible and tile(1).content.edit_label == "tile_edit" and tile(1).alpha_multiplier == 1)
check("deck: threat diamonds (filled to the level, the rest the same diamonds dimmed, never an outline) and one dot per enemy colour", tile(1).style.th_o1.visible and tile(1).style.th_o1.color[1] == 255 and tile(1).style.th_o5.visible and tile(1).style.th_o5.color[1] == 64 and tile(1).style.th_i1 == nil and tile(1).style.dot_1.visible)
check("deck: every shape has a larger faint copy under it (anti-aliasing): the suit mark, the diamonds, the dots", tile(1).style.icon_ch1.visible and tile(1).style.icon_ch1.size[1] > tile(1).style.icon_c1.size[1] and tile(1).style.icon_ch1.color[1] == 77 and tile(1).style.icon_ch1.offset[3] < tile(1).style.icon_c1.offset[3] and tile(1).style.th_h1.visible and tile(1).style.th_h1.size[1] > tile(1).style.th_o1.size[1] and tile(1).style.dot_h1.visible and tile(1).style.dot_h1.size[1] > tile(1).style.dot_1.size[1] and not tile(1).style.dot_h6.visible)
check("deck: the suit mark is 26 units (it was 22) and sits in the top right corner", view._tile_shape ~= nil and tile(1).style.icon_c1.size[1] > 2 * 2.4 * 26 / 24 - 0.01 and tile(1).style.icon_c1.size[1] < 2 * 2.4 * 26 / 24 + 0.01)
check("deck: header 'N in the draw', caption, and the strip has a segment per card in the draw", D.deck_count.content.deck_count == "deck_count:12" and D.deck_caption.content.deck_caption == "deck_caption" and #view._strip_segments == 12 and D.rw_strip.style.seg_12.visible and not D.rw_strip.style.seg_13.visible)

-- 100 cards: the Deck pages through them all, the strip has a segment for each
do
  local Dk = dofile(BASE .. "/ui/deck.lua")
  for i = 1, mod.rw.events.CUSTOM_SLOTS do settings["wave_def_custom_" .. i] = "Card " .. i .. "\t1 hound"; settings["on_custom_" .. i] = true end
  view._offset = 0; view:_reload(); view:_apply_screen()
  check("100 cards: the Deck holds all of them (no blank tile: every slot is used) and the header counts the whole draw", #view._deck == 100 and not blank_tile().visible and D.deck_count.content.deck_count == "deck_count:100", #view._deck)
  check("100 cards: the strip has a segment per card in the draw and stays inside its 1710 units", #view._strip_segments == 100 and (function() local last = D.rw_strip.style.seg_100; return last.visible ~= false and last.offset[1] + last.size[1] <= 1710.01 end)())
  for _ = 1, 20 do click("rw_scroll_down") end
  check("100 cards: scrolling a row at a time reaches the last page: nine cards, ending with Card 88", view._offset == Dk.max_offset(100) and tile(9).visible and plain(tile(9).content.name) == "Card 88" and not tile(10).visible, tostring(view._offset) .. " " .. tostring(tile(9).content.name))
  for _ = 1, 20 do click("rw_scroll_up") end
  check("100 cards: ...and back to the first page", view._offset == 0 and tile(1).content.name == "The Fool")
  for i = 1, mod.rw.events.CUSTOM_SLOTS do settings["wave_def_custom_" .. i] = nil; settings["on_custom_" .. i] = nil end
  view._offset = 0; view:_reload(); view:_apply_screen()
end
check("deck: the strip is as wide as its track (segments and gaps add up to 1710)", (function() local s = view._strip_segments; local last = s[#s]; return math.abs(last.x + last.w - 1710) < 1e-6 end)())
check("deck: buttons: Deck presets (top right) and Import card / Restore defaults at the bottom, no Back, the time steppers", D.btn_presets.visible and D.btn_presets.content.hotspot_text == "btn_presets" and D.btn_wimport.visible and D.btn_default.visible and not D.btn_back.visible and D.stepper_tmin.visible and D.stepper_tmax.visible)
check("deck: nothing of the detail screen shows", not D.btn_rename.visible and not D.btn_delete.visible and not D.stepper_chance.visible)

-- the Deck's arithmetic (ui/deck.lua) ---------------------------------------------------------------------------------------
do
  local DM = dofile(BASE .. "/ui/deck.lua")
  local x1, y1 = DM.tile_pos(1)
  local x7, y7 = DM.tile_pos(7)
  local x8, y8 = DM.tile_pos(8)
  local x14, y14 = DM.tile_pos(14)
  check("deck math: 7 columns, 2 rows, 14 tiles a page; tiles 228 x 270, 12 apart", DM.COLS == 7 and DM.ROWS == 2 and DM.CAPACITY == 14 and DM.TILE_W == 228 and DM.TILE_H == 270 and DM.GAP == 12)
  check("deck math: tile positions (row by row)", x1 == 126 and y1 == 190 and x7 == 126 + 6 * 240 and y7 == 190 and x8 == 126 and y8 == 190 + 282 and x14 == 126 + 6 * 240 and y14 == 190 + 282)
  check("deck math: the grid is centred in the 1710 wide panel at x 105 and ends above the bottom panel (y 750)", x7 + 228 == 1794 and (105 + 1710) - (x7 + 228) == 126 - 105 and y14 + 270 <= 750)
  check("deck math: the strip and its captions sit above the first row (strip y 144, tiles from 190)", DM.STRIP_Y == 144 and DM.STRIP_Y + DM.STRIP_H + 4 + 22 <= DM.Y0)
  check("deck math: the last page starts on a row: max offsets", DM.max_offset(0) == 0 and DM.max_offset(12) == 0 and DM.max_offset(14) == 0 and DM.max_offset(15) == 7 and DM.max_offset(21) == 7 and DM.max_offset(22) == 14 and DM.max_offset(33) == 21)
  check("deck math: offsets are clamped and rounded down to a whole row", DM.clamp_offset(5, 30) == 0 and DM.clamp_offset(9, 30) == 7 and DM.clamp_offset(100, 23) == 14 and DM.clamp_offset(-4, 23) == 0 and DM.clamp_offset(7, 10) == 0)
  check("deck math: chance pips: a level rounded, 0 to 10", DM.pips(0) == 0 and DM.pips(4.4) == 4 and DM.pips(4.5) == 5 and DM.pips(10) == 10 and DM.pips(50) == 10 and DM.pips(nil) == 0 and DM.pips(-3) == 0 and DM.pips("7") == 7)
  check("deck math: states: off, in the draw, resting (an off card never rests)", DM.state({ enabled = false }, 0) == "off" and DM.state({ enabled = true }, 0) == "in" and DM.state({ enabled = true }, 5) == "cooling" and DM.state({ enabled = false }, 50) == "off" and DM.state({ enabled = true }) == "in")
  check("deck math: clock text rounds up to whole seconds", DM.clock_text(75) == "1:15" and DM.clock_text(0) == "0:00" and DM.clock_text(59.2) == "1:00" and DM.clock_text(-5) == "0:00" and DM.clock_text(600) == "10:00")

  local out = {}
  local n = DM.strip_segments({ { weight = 1, key = "a" }, { weight = 1, key = "b" }, { weight = 1, key = "c" }, { weight = 1, key = "d" } }, 1000, out)
  check("strip: equal weights give equal segments, 2 apart, ending exactly at the width", n == 4 and math.abs(out[1].w - 248.5) < 1e-9 and math.abs(out[2].x - 250.5) < 1e-9 and math.abs(out[4].x + out[4].w - 1000) < 1e-9 and out[3].key == "c")
  n = DM.strip_segments({ { weight = 1, key = "a" }, { weight = 3, key = "b" } }, 1000, out)
  check("strip: a weight three times higher is a segment three times wider (trailing entries are dropped)", n == 2 and #out == 2 and math.abs(out[2].w / out[1].w - 3) < 1e-9 and math.abs(out[2].x + out[2].w - 1000) < 1e-9)
  n = DM.strip_segments({ { weight = 1000, key = "big" }, { weight = 1, key = "tiny" }, { weight = 0, key = "zero" } }, 1000, out)
  check("strip: a very light card still gets 3 units, and the total still fits", n == 3 and out[2].w == 3 and out[3].w == 3 and math.abs(out[3].x + out[3].w - 1000) < 1e-9 and out[1].w > 900, out[1].w .. "/" .. out[2].w)
  check("strip: no card in the draw = no segments", DM.strip_segments({}, 1000, out) == 0 and #out == 0)

  local fake_groups = {
    display_name = function(b) return ({ chaos_poxwalker = "Poxwalker", renegade_rifleman = "Rifleman", chaos_hound = "Hound", chaos_spawn = "Chaos Spawn", chaos_beast_of_nurgle = "Beast of Nurgle" })[b] or b end,
    has_repeat = function(parts) for _, p in ipairs(parts) do if p.rep or p.rep_same then return true end end return false end,
  }
  local function tag(text, rgb) return rgb and ("<" .. text .. ">") or text end
  local lines = DM.comp_lines({ { breed = "chaos_poxwalker", count = 8 }, { breed = "renegade_rifleman", count = 2 } }, fake_groups, function() return { 1, 2, 3 } end, tag, { 9, 9, 9 }, "and it repeats", function(n) return "+" .. n .. " more" end)
  check("comp lines: one per group, count and enemy name", #lines == 2 and lines[1] == "<8> <Poxwalker>" and lines[2] == "<2> <Rifleman>", table.concat(lines, "|"))
  lines = DM.comp_lines({ { breed = "chaos_poxwalker", count = 8 } }, fake_groups, nil, nil, nil)
  check("comp lines: plain text without colours", lines[1] == "8 Poxwalker")
  local many = {}
  for i = 1, 6 do many[i] = { breed = "chaos_hound", count = i } end
  lines = DM.comp_lines(many, fake_groups, nil, nil, nil, nil, function(n) return "+" .. n .. " more" end)
  check("comp lines: more than four groups: three lines and '+3 more'", #lines == 4 and lines[4] == "+3 more" and lines[1] == "1 Hound", table.concat(lines, "|"))
  local l1, l2, l3 = DM.layout(1), DM.layout(2), DM.layout(3)
  check("deck math: layout: a one line name leaves room for four lines of enemies, two lines three, three lines one (the cooldown row took one); the divider follows the name", l1.divider_y == 64 and l1.comp_y == 71 and l1.comp_lines == 4 and l1.comp_h == 68 and l2.divider_y == 88 and l2.comp_y == 95 and l2.comp_lines == 3 and l2.comp_h == 51 and l3.divider_y == 112 and l3.comp_lines == 1 and DM.layout(0).comp_lines == 4 and DM.layout(9).comp_lines == 1 and DM.layout(nil).comp_lines == 4)
  check("deck math: layout: the composition ends at the modifier line (146), including with a three-line name and the divider is clear of the name", l1.comp_y + l1.comp_h <= DM.COMP_BOTTOM and l2.comp_y + l2.comp_h <= DM.COMP_BOTTOM and l3.comp_y + l3.comp_h <= DM.COMP_BOTTOM and l1.divider_y >= DM.NAME_Y + DM.NAME_LINE and l2.divider_y >= DM.NAME_Y + 2 * DM.NAME_LINE)
  local more5 = {}
  for i = 1, 6 do more5[i] = { breed = "chaos_hound", count = i } end
  lines = DM.comp_lines(more5, fake_groups, nil, nil, nil, nil, function(n) return "+" .. n .. " more" end, 5)
  check("comp lines: with room for five lines six groups show four and '+2 more'", #lines == 5 and lines[5] == "+2 more" and lines[4] == "4 Hound", table.concat(lines, "|"))
  lines = DM.comp_lines({ more5[1], more5[2], more5[3], more5[4], more5[5] }, fake_groups, nil, nil, nil, nil, function(n) return "+" .. n .. " more" end, 5)
  check("comp lines: exactly five groups fit five lines (no '+N more')", #lines == 5 and lines[5] == "5 Hound", table.concat(lines, "|"))
  lines = DM.comp_lines(more5, fake_groups, nil, nil, nil, nil, function(n) return "+" .. n .. " more" end, 2)
  check("comp lines: with room for two lines (a three line name) one group and '+5 more'", #lines == 2 and lines[1] == "1 Hound" and lines[2] == "+5 more", table.concat(lines, "|"))
  lines = DM.comp_lines({ { breed = "chaos_hound", count = 5, rep = 2 } }, fake_groups, nil, nil, nil, "and it repeats")
  check("comp lines: a group that repeats adds the note when there is room", #lines == 2 and lines[2] == "and it repeats")
  lines = DM.comp_lines({ { one_of = { "chaos_hound", "chaos_spawn" }, count = 1 } }, fake_groups, function() return { 1, 2, 3 } end, tag, { 9, 9, 9 })
  check("comp lines: a random group reads '1 of A / B' (the count is the number of picks; the names are not coloured)", lines[1] == "<1> of Hound / Chaos Spawn", lines[1])
  lines = DM.comp_lines({ { one_of = { "chaos_spawn", "chaos_beast_of_nurgle" }, count = 1 } }, fake_groups, nil, nil, nil)
  check("comp lines: a long random group is cut like any long line", #lines[1] <= DM.COMP_CHARS and lines[1]:sub(-3) == "...", lines[1])
  lines = DM.comp_lines({ { breed = "this_is_a_very_long_enemy_name_indeed", count = 12 } }, fake_groups, nil, nil, nil)
  check("comp lines: a long name is cut so a line fits the tile", #lines[1] <= DM.COMP_CHARS and lines[1]:sub(-3) == "...", lines[1])
end

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
local bg = pass_by_style(tile(1), "bg")
tile(1).content.hotspot_top.is_hover = true; bg.change_function(tile(1).content, tile(1).style.bg)
local hover_col = tile(1).style.bg.color[2]
tile(1).content.hotspot_top.is_hover = false; bg.change_function(tile(1).content, tile(1).style.bg)
check("a tile takes the suit's lighter colour while the pointer is on it (swarm: card #1b1d17, selected #262a1f)", hover_col == 0x26 and tile(1).style.bg.color[2] == 0x1b, hover_col .. " vs " .. tile(1).style.bg.color[2])
check("engine rule: the hotspots of a tile run (hover and click work): the face, the state line, the Edit pill and the ten pips", hotspot_runs(tile(1), "hotspot_top") and hotspot_runs(tile(1), "hotspot_state") and hotspot_runs(tile(1), "hotspot_edit") and hotspot_runs(tile(1), "hotspot_pip1") and hotspot_runs(tile(1), "hotspot_pip10") and hotspot_runs(blank_tile(), "hotspot"))
check("a tile's hotspots do not overlap (a click would reach two of them)", (function()
  local boxes = {}
  for _, p in ipairs(tile(1).def.passes) do if p.pass_type == "hotspot" then boxes[#boxes + 1] = { p.style.offset[1], p.style.offset[2], p.style.size[1], p.style.size[2] } end end
  for i = 1, #boxes do for j = i + 1, #boxes do
    local a, b = boxes[i], boxes[j]
    if a[1] < b[1] + b[3] and b[1] < a[1] + a[3] and a[2] < b[2] + b[4] and b[2] < a[2] + a[4] then return false end
  end end
  return #boxes == 16
end)())
check("the ten pip hotspots are side by side from the left edge of the tile to the right one (no dead strip) and only the pips are quiet when the pointer comes over them", (function()
  local boxes, quiet = {}, 0
  for _, p in ipairs(tile(1).def.passes) do
    if p.pass_type == "hotspot" and p.content_id:find("^hotspot_pip") then
      boxes[#boxes + 1] = { p.style.offset[1], p.style.size[1], p.style.offset[2], p.style.size[2] }
      if p.content.on_hover_sound == nil and p.content.on_pressed_sound ~= nil then quiet = quiet + 1 end
    elseif p.pass_type == "hotspot" and p.content.on_hover_sound == nil then
      return false
    end
  end
  table.sort(boxes, function(a, b) return a[1] < b[1] end)
  if #boxes ~= 10 or quiet ~= 10 or boxes[1][1] ~= 0 then return false end
  for i = 1, 9 do if math.abs(boxes[i][1] + boxes[i][2] - boxes[i + 1][1]) > 1e-9 then return false end end
  return math.abs(boxes[10][1] + boxes[10][2] - 228) < 1e-9 and boxes[1][3] == 217 and boxes[1][4] == 15
end)())
check("every hotspot lies inside the tile; the face stops where the pips start (217), the pips where the cooldown row starts (232) and the row where the state line starts (249)", (function()
  for _, p in ipairs(tile(1).def.passes) do
    if p.pass_type == "hotspot" then
      local x, y, w, h = p.style.offset[1], p.style.offset[2], p.style.size[1], p.style.size[2]
      if x < 0 or y < 0 or x + w > 228 + 1e-9 or y + h > 270 + 1e-9 then return false end
    end
  end
  local top, state = pass_by_style(tile(1), "hotspot_top").style, pass_by_style(tile(1), "hotspot_state").style
  local minus, value, plus = pass_by_style(tile(1), "hotspot_cd_minus").style, pass_by_style(tile(1), "hotspot_cd_value").style, pass_by_style(tile(1), "hotspot_cd_plus").style
  return top.offset[2] + top.size[2] == 217 and state.offset[2] == 249 and minus.offset[2] == 232 and minus.offset[2] + minus.size[2] == 249 and minus.offset[1] == 0 and minus.offset[1] + minus.size[1] == value.offset[1] and value.offset[1] + value.size[1] == plus.offset[1] and plus.offset[1] + plus.size[1] == 228
end)())
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

-- scrolling: a page is two rows of seven cards; 12 cards need none
check("deck: nothing to scroll with 12 cards: both scroll buttons are disabled", view._offset == 0 and view:_max_offset() == 0 and D.rw_scroll_up.content.hotspot.disabled == true and D.rw_scroll_down.content.hotspot.disabled == true)
for i = 1, 10 do settings["wave_def_custom_" .. i] = "Card " .. i .. "\t3 hounds" end
view:_reload(); view:_apply_screen()
check("deck: with ten custom cards there are 22 cards and the blank tile: three rows, two scroll steps", #view._deck == 23 and view:_max_offset() == 14 and D.rw_scroll_down.content.hotspot.disabled == false and D.rw_scroll_up.content.hotspot.disabled == true, view:_max_offset())
click("rw_scroll_down")
check("deck: scrolling moves one row of seven cards", view._offset == 7 and tile(1).content.name == view._deck[8].name, view._offset)
click("rw_scroll_down"); click("rw_scroll_down")
check("deck: ...down to the last page and no further; the blank tile is on it", view._offset == 14 and tile(1).content.name == view._deck[15].name and tile(8).visible and not tile(9).visible and blank_tile().visible and D.rw_scroll_down.content.hotspot.disabled == true, tostring(view._offset))
click("rw_scroll_up"); click("rw_scroll_up"); click("rw_scroll_up")
check("deck: ...and back up to the first page", view._offset == 0 and D.rw_scroll_up.content.hotspot.disabled == true)
local wheel = { get = function(self, name) if name == "scroll_axis" then return { 0, -1 } end return nil end, is_null_service = function() return false end }
view:update(0.01, 0, wheel)
check("deck: the mouse wheel scrolls a row of seven too", view._offset == 7, view._offset)
view._offset = 0
for i = 1, 10 do settings["wave_def_custom_" .. i] = nil end
view:_reload(); view:_apply_screen()

-- a tile toggles its card in and out of the draw
click_tile(2)
check("toggle: clicking a tile puts the card out of the draw: dimmed, no glow, 11 in the draw", settings["on_wave_medium"] == false and tile(2).content.state_left == "tile_off" and tile(2).alpha_multiplier == 0.55 and not tile(2).style.glow.visible and D.deck_count.content.deck_count == "deck_count:11" and #view._strip_segments == 11)
click_tile(2, "hotspot_state")
check("toggle: the left of the state line does the same: back in the draw", settings["on_wave_medium"] == true and tile(2).content.state_left == "tile_in" and tile(2).alpha_multiplier == 1 and D.deck_count.content.deck_count == "deck_count:12" and #view._strip_segments == 12)
-- hovering a tile shows its name over the strip and raises its segment; the Edit corner lights up
tile(3).content.hotspot_top.is_hover = true
view:update(0.01, 0, input_stub_deck or { get = function() return nil end, is_null_service = function() return false end })
check("hover: the caption names the tile under the pointer (no percentage anywhere) and its strip segment is raised", D.deck_hover.content.deck_hover == tile(3).content.name and view._deck_hover == "wave_large" and D.rw_strip.style.seg_3.offset[2] < 0 and D.rw_strip.style.seg_1.offset[2] == 0)
tile(3).content.hotspot_top.is_hover = false; tile(3).content.hotspot_edit.is_hover = true
view:update(0.01, 0, { get = function() return nil end, is_null_service = function() return false end })
check("hover: the Edit corner has its own highlight", tile(3).style.edit_bg.visible and view._deck_hover == "wave_large")
tile(3).content.hotspot_edit.is_hover = false
view:update(0.01, 0, { get = function() return nil end, is_null_service = function() return false end })
check("hover: and everything goes back when the pointer leaves", D.deck_hover.content.deck_hover == "" and not tile(3).style.edit_bg.visible and D.rw_strip.style.seg_3.offset[2] == 0)
-- the pointer on a segment of the strip lights its card, names it, and raises the segment
D.rw_strip.content.hs_3.is_hover = true
view:update(0.01, 0, { get = function() return nil end, is_null_service = function() return false end })
check("strip hover: the card of the segment lights up, its name is over the strip and its segment is raised", tile(3).content.strip_hover == true and tile(2).content.strip_hover == false and D.deck_hover.content.deck_hover == tile(3).content.name and view._deck_hover == "wave_large" and D.rw_strip.style.seg_3.offset[2] < 0)
check("strip hover: the hit area of a segment is the segment (a little taller), segments past the last have none", D.rw_strip.style.hs_3.offset[1] == view._strip_segments[3].x and D.rw_strip.style.hs_3.size[1] == view._strip_segments[3].w and D.rw_strip.style.hs_20.size[1] == 0)
check("strip hover: the tile takes the lighter colour", (function()
  local bgp = pass_by_style(tile(3), "bg")
  bgp.change_function(tile(3).content, tile(3).style.bg)
  return tile(3).style.bg.color[2] == tile(3).content.bg_hi[1]
end)())
D.rw_strip.content.hs_3.is_hover = false
view:update(0.01, 0, { get = function() return nil end, is_null_service = function() return false end })
check("strip hover: and it goes out again", tile(3).content.strip_hover == false and D.deck_hover.content.deck_hover == "" and D.rw_strip.style.seg_3.offset[2] == 0)
-- a resting card, a rare card
mod.rw.director = { cooldown_remaining = function(key, length) return key == "wave_large" and 75 or 0 end }
view:_reload(); view:_apply_screen()
check("cooldown: a card that is resting shows 'Back in' and its clock on its tile", tile(3).content.state_left == "tile_cooling" and tile(3).content.state_clock == "1:15" and tile(3).content.card_state == "cooling", tostring(tile(3).content.state_clock))
check("cooldown: a resting card is still in the draw (it counts in 'N in the draw')", D.deck_count.content.deck_count == "deck_count:12")
mod.rw.director = nil
settings.pct_boss_ambush = 2
view:_reload(); view:_apply_screen()
check("rare: a card with weight 2 or less has the pus-yellow outline and says rare", tile(5).content.suit_label:find("TILE_RARE", 1, true) ~= nil and tile(5).style.border_t.color[2] == 227 and tile(5).style.border_t.color[3] == 207 and tile(5).style.glow.color[1] == 110)
settings.pct_boss_ambush = nil
-- HERESY: the crimson frame, the glow that smoulders, the name on the face
settings.su_boss_ambush = "heresy"
view:_reload(); view:_apply_screen()
check("heresy: the tile has the blood-red frame, a glow that smoulders and its name on the face", tile(5).style.border_t.color[2] == 0xa3 and tile(5).style.border_t.color[3] == 0x20 and tile(5).style.glow.visible and tile(5).style.glow.color[1] == 150 and tile(5).style.glow.color[2] == 0xa3 and tile(5).content.suit_label == "HERESY", tile(5).content.suit_label)
settings.su_boss_ambush = "fester"
view:_reload(); view:_apply_screen()
check("heresy: a card saved with the old suit name fester is drawn as Heresy", tile(5).content.suit_label == "HERESY" and tile(5).style.border_t.color[2] == 0xa3)
settings.su_boss_ambush = "heresy"; settings.pct_boss_ambush = 2
view:_reload(); view:_apply_screen()
check("heresy: rare and Heresy together: the frame stays blood red (not pus yellow) and the label says both", tile(5).style.border_t.color[2] == 0xa3 and tile(5).content.suit_label:find("HERESY", 1, true) ~= nil and tile(5).content.suit_label:find("TILE_RARE", 1, true) ~= nil and tile(5).style.glow.color[2] == 0xa3)
settings.su_boss_ambush = nil; settings.pct_boss_ambush = nil
view:_reload(); view:_apply_screen()

-- the cooldown row of a tile: the value, the minus and the plus, the number box ------------------------------------------------------
do
  local inp = { get = function() return nil end, is_null_service = function() return false end }
  local function upd() view:update(0.01, 0, inp) end
  local function reload() view:_reload(); view:_apply_screen() end
  local function near(a, b) return math.abs(a - b) < 1e-6 end
  local W = view._widgets_by_name
  local PPc = dofile(BASE .. "/ui/wave_editor_components.lua")
  local function type_in(text) view._widgets_by_name.rw_popup_input.content.input_text = text; view:update(0.01, 0, inp) end
  local DMc = dofile(BASE .. "/ui/deck.lua")
  settings.tarot_longest = nil

  -- the arithmetic (shared with the Mirror's stepper)
  check("cooldown math: steps of 30 s from the grid, and from a value off the grid (95 -> 90 + 30 = 120, 100 - 30 = 60), never below 30 and never above the longest", DMc.cooldown_after(120, 1, 600) == 150 and DMc.cooldown_after(120, -1, 600) == 90 and DMc.cooldown_after(95, 1, 600) == 120 and DMc.cooldown_after(100, -1, 600) == 60 and DMc.cooldown_after(30, -1, 600) == 30 and DMc.cooldown_after(600, 1, 600) == 600 and DMc.cooldown_after(590, 1, 600) == 600 and DMc.cooldown_after(120, 3, 600) == 210 and DMc.cooldown_after(nil, 1, 600) == 60 and DMc.cooldown_after(120, 1, 100) == 100 and DMc.cooldown_after(10, -1, 600) == 30)

  -- every tile says it
  check("cooldown: every tile says what its card rests after the pick (The Fool 2:00, The Pilgrims 2:30, The Throng 4:00) under the label", tile(1).content.cd_value == "2:00" and tile(2).content.cd_value == "2:30" and tile(4).content.cd_value == "4:00" and tile(1).content.cd_label == "TILE_CD", tile(1).content.cd_value)
  check("cooldown: the Deck's tiles carry the minus and the plus plates with their glyphs, in the card's own colours (swarm: ash green), and the value", tile(1).style.cd_minus_bg.visible and tile(1).style.cd_plus_bg.visible and tile(1).style.cd_minus_h.visible and tile(1).style.cd_plus_h.visible and tile(1).style.cd_plus_v.visible and tile(1).style.cd_value.visible and tile(1).style.cd_label.visible and tile(1).style.cd_plus_h.color[2] == 0x9a and tile(1).style.cd_plus_h.color[3] == 0xa3 and tile(1).style.cd_value.text_color[2] == 0xd9)
  local mh, ph, pv = tile(1).style.cd_minus_h, tile(1).style.cd_plus_h, tile(1).style.cd_plus_v
  check("cooldown: the glyphs are centred on their plates (a minus 8 x 2; a plus two bars, 8 x 2 and 2 x 8); the plates fill the row (24 x 15)", near(mh.offset[1] + mh.size[1] / 2, 26) and near(mh.offset[2] + mh.size[2] / 2, 240.5) and mh.size[1] == 8 and mh.size[2] == 2 and near(ph.offset[1] + ph.size[1] / 2, 202) and near(pv.offset[2] + pv.size[2] / 2, 240.5) and pv.size[1] == 2 and pv.size[2] == 8 and tile(1).style.cd_minus_bg.size[1] == 24 and tile(1).style.cd_minus_bg.size[2] == 15)
  check("cooldown: the row sits under the pips and above the state line, the label and the value between the plates", tile(1).style.cd_label.offset[1] >= 38 and tile(1).style.cd_value.offset[1] + tile(1).style.cd_value.size[1] <= 190 and tile(1).style.cd_label.offset[2] >= tile(1).style.pip_1.offset[2] + tile(1).style.pip_1.size[2] and tile(1).style.cd_label.offset[2] + tile(1).style.cd_label.size[2] <= tile(1).style.state_left.offset[2])

  -- the plus, the minus
  click_tile(1, "hotspot_cd_plus")
  check("cooldown: a click on the plus adds 30 seconds, saved for the card, and the tile shows it at once", settings.cd_wave_small == 150 and tile(1).content.cd_value == "2:30" and tile(1).content.name == "The Fool", tostring(settings.cd_wave_small))
  click_tile(1, "hotspot_cd_minus"); click_tile(1, "hotspot_cd_minus")
  check("cooldown: the minus takes 30 away (two clicks: 1:30)", settings.cd_wave_small == 90 and tile(1).content.cd_value == "1:30")
  for _ = 1, 10 do click_tile(1, "hotspot_cd_minus") end
  check("cooldown: never below 30 seconds, and the minus is dimmed there (its plate and glyph take the empty colour)", settings.cd_wave_small == 30 and tile(1).content.cd_value == "0:30" and tile(1).style.cd_minus_h.color[2] == tile(1).content.fx.empty[1] and tile(1).style.cd_plus_h.color[2] == 0x9a)
  for _ = 1, 40 do click_tile(1, "hotspot_cd_plus") end
  check("cooldown: never above the longest cooldown option (10 minutes by default), and the plus is dimmed there", settings.cd_wave_small == 600 and tile(1).content.cd_value == "10:00" and tile(1).style.cd_plus_h.color[2] == tile(1).content.fx.empty[1] and tile(1).style.cd_minus_h.color[2] == 0x9a)
  settings.tarot_longest = 4; reload()
  click_tile(1, "hotspot_cd_plus")
  check("cooldown: the limit follows the 'Longest cooldown' option (4 minutes: a longer value is brought back by the next click)", settings.cd_wave_small == 240 and tile(1).content.cd_value == "4:00", tostring(settings.cd_wave_small))
  settings.tarot_longest = nil
  settings.cd_wave_small = 95; reload()
  click_tile(1, "hotspot_cd_plus")
  check("cooldown: a value off the 30 s grid (95) is brought to the grid first (90 + 30 = 120)", settings.cd_wave_small == 120, tostring(settings.cd_wave_small))
  settings.cd_wave_small = nil; reload()
  check("cooldown: a card with no cooldown of its own shows its default (The Fool 2:00)", tile(1).content.cd_value == "2:00")

  -- the pointer on the plus or the minus: the value shows what a click would set, in the accent; going away restores it
  tile(1).content.hotspot_cd_plus.is_hover = true; upd()
  check("cooldown: with the pointer on the plus the value shows 2:30 (what a click would set) in the card's accent, the plate is lit, and the caption names the card", tile(1).content.cd_value == "2:30" and tile(1).content.fx.cd_hover == 1 and tile(1).style.cd_value.text_color[2] == 0x9a and view._deck_hover == "wave_small" and D.deck_hover.content.deck_hover == tile(1).content.name and tile(1).style.cd_plus_bg.color[2] > tile(1).style.cd_minus_bg.color[2])
  tile(1).content.hotspot_cd_plus.is_hover = false; upd()
  check("cooldown: ...and it goes back to 2:00 in the bone colour when the pointer leaves", tile(1).content.cd_value == "2:00" and tile(1).content.fx.cd_hover == 0 and tile(1).style.cd_value.text_color[2] == 0xd9 and view._deck_hover == nil, tostring(view._deck_hover))
  tile(1).content.hotspot_cd_minus.is_hover = true; upd()
  check("cooldown: the minus shows 1:30", tile(1).content.cd_value == "1:30" and tile(1).content.fx.cd_hover == -1)
  tile(1).content.hotspot_cd_minus.is_hover = false; upd()
  settings.cd_wave_small = 30; reload()
  tile(1).content.hotspot_cd_minus.is_hover = true; upd()
  check("cooldown: at the limit nothing is previewed (the minus at 30 s shows 0:30 and does not light)", tile(1).content.cd_value == "0:30" and tile(1).content.fx.cd_hover == 0)
  do
    local original, repaints = view._paint_cooldown, 0
    view._paint_cooldown = function(self, ...) repaints = repaints + 1; return original(self, ...) end
    for _ = 1, 100 do upd() end
    view._paint_cooldown = original
    check("cooldown: stationary hover at the minimum does not repaint every frame", repaints == 0, repaints)
  end
  tile(1).content.hotspot_cd_minus.is_hover = false; upd()
  settings.cd_wave_small = nil; reload()

  -- the value: a number box
  click_tile(1, "hotspot_cd_value")
  check("cooldown: clicking the value opens a number box with the cooldown in seconds (30 to the longest), titled with the card", view._popup ~= nil and view._popup.spec.min == 30 and view._popup.spec.max == 600 and view._popup.spec.value == "120" and view._popup.spec.label == "popup_cooldown_title:The Fool")
  type_in("5000"); PPc.Popup.commit(view)
  check("cooldown: more than the longest is refused and the box stays open", view._popup ~= nil and view._popup.error ~= nil and settings.cd_wave_small == nil)
  type_in("200"); PPc.Popup.commit(view)
  check("cooldown: 200 seconds is accepted (any whole number of seconds, not only the 30 s grid): saved and shown", view._popup == nil and settings.cd_wave_small == 200 and tile(1).content.cd_value == "3:20", tostring(settings.cd_wave_small))
  settings.cd_wave_small = nil; reload()

  -- a right click on the row opens the card, like on the pips
  tile(1).content.hotspot_cd_plus.right_pressed_callback()
  check("cooldown: a right click on the plus opens the card's own screen (as on the pips and the pill)", view._screen == "detail" and view._key == "wave_small" and settings.cd_wave_small == nil)
  view:cb_back()
  tile(1).content.hotspot_cd_value.right_pressed_callback()
  check("cooldown: ...and on the value", view._screen == "detail")
  view:cb_back()

  -- a card out of the draw can still be set; a resting card shows its cooldown (not what is left), a card with a fixed timer has no cooldown to set
  settings.on_wave_medium = false; reload()
  click_tile(2, "hotspot_cd_plus")
  check("cooldown: a card that is out of the draw can be set too (The Pilgrims 2:30 -> 3:00)", settings.cd_wave_medium == 180 and tile(2).content.cd_value == "3:00")
  settings.on_wave_medium = nil; settings.cd_wave_medium = nil
  mod.rw.director = { cooldown_remaining = function(key, length) return key == "wave_large" and 75 or 0 end }
  reload()
  check("cooldown: a resting card (The Procession, 1:15 left) shows its whole cooldown (2:30) in the row and the time left in the state line", tile(3).content.cd_value == "2:30" and tile(3).content.state_clock == "1:15" and tile(3).content.card_state == "cooling")
  click_tile(3, "hotspot_cd_minus")
  check("cooldown: ...and it can be changed while it rests (the new cooldown counts from the next pick)", settings.cd_wave_large == 120 and tile(3).content.cd_value == "2:00" and tile(3).content.state_clock == "1:15")
  settings.cd_wave_large = nil
  mod.rw.director = nil
  settings.ev_wave_small = 60; reload()
  check("cooldown: a card with a fixed timer ignores its cooldown: the row says EVERY 1:00 and has no plates", tile(1).content.cd_label == "TILE_CD_EVERY" and tile(1).content.cd_value == "1:00" and not tile(1).style.cd_minus_bg.visible and not tile(1).style.cd_plus_bg.visible and not tile(1).style.cd_plus_v.visible and not tile(1).style.cd_minus_h.visible)
  click_tile(1, "hotspot_cd_plus"); click_tile(1, "hotspot_cd_value")
  check("cooldown: ...and a click there changes nothing and opens nothing", settings.cd_wave_small == nil and view._popup == nil)
  settings.ev_wave_small = nil; reload()

  -- the page of the Deck: the tile in a slot is the card of that place, whatever the offset
  for i = 1, 14 do settings["wave_def_custom_" .. i] = "Extra " .. i .. "\t1 hound"; settings["on_custom_" .. i] = true end
  view._offset = 7; view:_reload(); view:_apply_screen(true)
  local seventh = view._deck[view._offset + 1]
  click_tile(1, "hotspot_cd_plus")
  check("cooldown: on a scrolled Deck the plus of the first tile belongs to the card in that place (the eighth)", settings["cd_" .. seventh.key] ~= nil and seventh.key ~= "wave_small" and settings.cd_wave_small == nil, seventh.key)
  settings["cd_" .. seventh.key] = nil
  for i = 1, 14 do settings["wave_def_custom_" .. i] = nil; settings["on_custom_" .. i] = nil end
  view._offset = 0; reload()

  -- the stage card of the Cauldron shows the value, without the plates, and its click areas are off
  view:_open_detail("wave_small")
  local stage = W.rw_stage_card
  check("cooldown: the card on the stage shows the cooldown (2:00) but not the plates, and its cooldown click areas are off", stage.content.cd_value == "2:00" and stage.visible and not stage.style.cd_minus_bg.visible and not stage.style.cd_plus_bg.visible and not stage.style.cd_plus_v.visible and stage.content.hotspot_cd_plus.disabled == true and stage.content.hotspot_cd_minus.disabled == true and stage.content.hotspot_cd_value.disabled == true)
  view:cb_back()
  check("cooldown: back on the Deck the plates and the value are there again", view._screen == "list" and tile(1).style.cd_minus_bg.visible and tile(1).content.cd_value == "2:00")

  -- the engine runs the hotspots of the row; they are disabled with the others while a popup is open
  check("engine rule: the hotspots of the cooldown row run (hover and click work)", hotspot_runs(tile(1), "hotspot_cd_minus") and hotspot_runs(tile(1), "hotspot_cd_value") and hotspot_runs(tile(1), "hotspot_cd_plus"))
  click_tile(1, "hotspot_cd_value")
  check("cooldown: while the number box is open the tiles' cooldown click areas are off", view._popup ~= nil and tile(1).content.hotspot_cd_plus.disabled == true and tile(1).content.hotspot_cd_value.disabled == true)
  PPc.Popup.cancel(view)
  check("cooldown: ...and on again when it closes", view._popup == nil and tile(1).content.hotspot_cd_plus.disabled ~= true)
  settings.cd_wave_small = nil
end

-- the chance pips: the chance itself (1 to 10), clickable -------------------------------------------------------------
do
  local inp = { get = function() return nil end, is_null_service = function() return false end }
  local function upd() view:update(0.01, 0, inp) end
  local function reload() view:_reload(); view:_apply_screen() end
  local function filled(w) local n = 0; for k = 1, 10 do if w.style["pip_" .. k].color[1] == 255 then n = n + 1 end end return n end
  local keys = { "wave_small", "wave_medium", "wave_large", "wave_huge", "boss_ambush", "bomber_frenzy", "hound_frenzy", "grenade_legion", "sniper_elite", "elite_squad", "special_pack", "ogryn_brutes" }

  check("pips: a card shows its chance as pips: The Fool (chance 5) five, Strength (2) two, The Procession (4) four, The Throng (3) three", filled(tile(1)) == 5 and filled(tile(12)) == 2 and filled(tile(3)) == 4 and filled(tile(4)) == 3, filled(tile(1)) .. "/" .. filled(tile(12)) .. "/" .. filled(tile(3)) .. "/" .. filled(tile(4)))
  check("rare: a chance of 1 or 2 says rare and has the pus-yellow outline: only Strength (2)", tile(12).content.suit_label:find("TILE_RARE", 1, true) ~= nil and tile(1).content.suit_label:find("TILE_RARE", 1, true) == nil and tile(4).content.suit_label:find("TILE_RARE", 1, true) == nil)

  -- every chance from 1 to 10 shows exactly that many pips (chance 2 used to show one, 3 two, 4 three, 5 four), and more than 10 is 10
  local exact = true
  for n = 1, 10 do
    settings.pct_wave_large = n; reload()
    if filled(tile(3)) ~= n then exact = false end
  end
  check("pips: chance 1, 2, 3 ... 10 show 1, 2, 3 ... 10 pips, whatever the other cards have", exact)
  settings.pct_wave_large = 400; reload()
  check("pips: a stored chance above 10 counts as 10 (ten pips)", filled(tile(3)) == 10)
  settings.pct_wave_large = nil

  -- when every card has the same chance all show it; 1 and 2 are rare
  for _, k in ipairs(keys) do settings["pct_" .. k] = 7 end
  reload()
  local all_seven, none_rare = true, true
  for i = 1, 12 do
    if filled(tile(i)) ~= 7 then all_seven = false end
    if tile(i).content.suit_label:find("TILE_RARE", 1, true) then none_rare = false end
  end
  check("pips: cards that all have chance 7 all show seven pips and none is rare", all_seven and none_rare)
  for _, k in ipairs(keys) do settings["pct_" .. k] = 1 end
  reload()
  check("pips: ...and at chance 1 all of them show one pip and are rare (the number decides, not a comparison)", filled(tile(5)) == 1 and tile(5).content.suit_label:find("TILE_RARE", 1, true) ~= nil)
  for _, k in ipairs(keys) do settings["pct_" .. k] = nil end
  reload()

  -- hovering a pip: it lights up to the pip, the caption says which level
  tile(3).content.hotspot_pip4.is_hover = true; upd()
  check("pips: hovering pip 4 lights pips 1 to 4 and names the level over the strip", filled(tile(3)) == 4 and D.deck_hover.content.deck_hover == "tile_pip_hover:The Procession,4" and tile(3).content.fx.hover_level == 4 and view._deck_hover == "wave_large", D.deck_hover.content.deck_hover)
  check("pips: the whole tile takes the lighter colour while the pointer is on a pip", (function()
    local bgp = pass_by_style(tile(3), "bg")
    bgp.change_function(tile(3).content, tile(3).style.bg)
    return tile(3).style.bg.color[2] == tile(3).content.bg_hi[1]
  end)())
  tile(3).content.hotspot_pip4.is_hover = false; tile(3).content.hotspot_pip10.is_hover = true; upd()
  check("pips: pips past the card's own four that a click would add are lighter than the ones it has", filled(tile(3)) == 10 and tile(3).style.pip_5.color[2] ~= tile(3).style.pip_4.color[2] and tile(3).style.pip_10.color[2] == tile(3).style.pip_5.color[2])
  tile(3).content.hotspot_pip10.is_hover = false; upd()
  check("pips: leaving them brings back the card's own pips and the name over the strip goes away", filled(tile(3)) == 4 and tile(3).content.fx.hover_level == nil and D.deck_hover.content.deck_hover == "" and tile(3).style.pip_8.color[1] == 130)
  tile(3).content.hotspot_pip6.is_hover = true; upd(); tile(3).content.hotspot_pip6.is_hover = false; tile(3).content.hotspot_top.is_hover = true; upd()
  check("pips: moving from a pip to the face keeps the card's name in the caption, pips back to normal", D.deck_hover.content.deck_hover == tile(3).content.name and filled(tile(3)) == 4)
  tile(3).content.hotspot_top.is_hover = false; upd()

  -- clicking a pip sets the card's chance to that number
  tile(3).content.hotspot_pip10.pressed_callback()
  check("pips: a click on pip 10 gives the card chance 10 and it shows all ten", settings.pct_wave_large == 10 and filled(tile(3)) == 10, tostring(settings.pct_wave_large))
  tile(3).content.hotspot_pip1.pressed_callback()
  check("pips: pip 1 gives it chance 1 and it shows one pip", settings.pct_wave_large == 1 and filled(tile(3)) == 1, tostring(settings.pct_wave_large))
  tile(3).content.hotspot_pip7.pressed_callback()
  check("pips: pip 7 gives it chance 7, which shows seven pips", settings.pct_wave_large == 7 and filled(tile(3)) == 7, tostring(settings.pct_wave_large))
  check("pips: the strip follows (the card's segment is 7 of the 50 the cards add up to)", (function() for _, s in ipairs(view._strip_segments) do if s.key == "wave_large" then return math.abs(s.w / 1710 - 7 / 50) < 0.01 end end return false end)())
  check("pips: ...and the caption of the draw still counts every card (12 in the draw)", D.deck_count.content.deck_count == "deck_count:12")

  -- a card out of the draw can have its chance set too, and stays out
  settings.on_wave_huge = false; reload()
  tile(4).content.hotspot_pip10.pressed_callback()
  check("pips: a click on a card that is out of the draw sets its chance but leaves it out", settings.pct_wave_huge == 10 and settings.on_wave_huge == false and tile(4).content.card_state == "off")
  settings.on_wave_huge = nil; settings.pct_wave_huge = nil; settings.pct_wave_large = nil; reload()

  -- a card alone in the draw: the pip is the chance as well
  for _, k in ipairs(keys) do if k ~= "wave_small" then settings["on_" .. k] = false end end
  reload()
  tile(1).content.hotspot_pip3.pressed_callback()
  check("pips: a lone card is no different: pip 3 = chance 3 and three pips", settings.pct_wave_small == 3 and filled(tile(1)) == 3, tostring(settings.pct_wave_small))
  for _, k in ipairs(keys) do settings["on_" .. k] = nil end
  settings.pct_wave_small = nil; reload()

  -- the cards that rest are out of the draw: the share of the others grows (The Fool 5 of 47 = 10.6 percent; with The Pilgrims, The Throng
  -- and The Tower resting (5, 3 and 5) it is 5 of 34 = 14.7 percent), and the strip leaves them out
  view._screen = "list"; reload()
  local fool = view._waves[1]
  local before = view:_share_of(fool)
  mod.rw.director = { cooldown_remaining = function(key) return (key == "wave_medium" or key == "wave_huge" or key == "bomber_frenzy") and 60 or 0 end }
  reload()
  local after = view:_share_of(fool)
  local strip_keys = {}; for _, s in ipairs(view._strip_segments) do strip_keys[s.key] = true end
  check("resting: The Fool has 5 of 47 (10.6 percent) while every card can be drawn", before ~= nil and math.abs(before - 5 / 47 * 100) < 1e-6, tostring(before))
  check("resting: with three cards resting (5, 3 and 5) the others are likelier: 5 of 34 (14.7 percent)", after ~= nil and math.abs(after - 5 / 34 * 100) < 1e-6, tostring(after))
  check("resting: a resting card's share is what it will have when it is back (5 of 39 = 12.8), and the strip leaves it out", math.abs(view:_share_of(view._waves[2]) - 5 / 39 * 100) < 1e-6 and not strip_keys.wave_medium and not strip_keys.wave_huge and strip_keys.wave_small, tostring(view:_share_of(view._waves[2])))
  mod.rw.director = { cooldown_remaining = function() return 0 end }
  reload()
  check("resting: when they are back the shares return", math.abs(view:_share_of(fool) - before) < 1e-6)
  mod.rw.director = nil
  reload()

  -- a right click anywhere on the tile opens the card; the pips and the pill repeat their action on a fast second click, the toggles do not
  for _, hs in ipairs({ "hotspot_top", "hotspot_state", "hotspot_edit", "hotspot_pip1", "hotspot_pip5", "hotspot_pip10" }) do
    if view._screen ~= "list" then click("btn_back") end
    tile(2).content[hs].right_pressed_callback()
    check("right click: " .. hs .. " opens the card (The Pilgrims) in edit mode", view._screen == "detail" and view._key == "wave_medium", tostring(view._screen) .. tostring(view._key))
    click("btn_back")
  end
  check("right click: back on the Deck", view._screen == "list")
  local was_enabled = view._deck[2].enabled
  tile(2).content.hotspot_top.double_click_callback()
  tile(2).content.hotspot_top.released_callback()
  check("double click: a second release does not toggle the card again; pips and Edit still repeat", view._deck[2].enabled == was_enabled and tile(2).content.hotspot_pip4.double_click_callback ~= nil and tile(2).content.hotspot_edit.double_click_callback ~= nil)
  tile(2).content.hotspot_pip4.double_click_callback()
  check("double click: the second click on a pip sets the chance too", settings.pct_wave_medium ~= nil and filled(tile(2)) >= 1)
  settings.pct_wave_medium = nil; reload()
end

-- the number of lines of a name is measured by the game when there is a renderer ---------------------------------------------
do
  local function reload() view:_reload(); view:_apply_screen() end
  check("name lines: without a renderer the number of lines is estimated from the letters (The Fool: 1 line, divider 64)", view._ui_renderer == nil and tile(1).style.divider.offset[2] == 64)
  view._ui_renderer = { per_line = 8 }
  reload()
  check("name lines: with a renderer the game's measuring decides: The Fool (8 letters) one line, The Pilgrims (12) two lines, a long name three at most", tile(1).style.divider.offset[2] == 64 and tile(2).style.divider.offset[2] == 88 and tile(2).style.comp.size[2] == 51 and tile(5).style.divider.offset[2] == 88, tostring(tile(2).style.divider.offset[2]))
  settings.wave_def_custom_1 = "A Name That Is Very Long Indeed\t3 hounds"; settings.on_custom_1 = true
  reload()
  check("name lines: three lines at most, the composition keeps one line clear of modifiers", tile(13).style.divider.offset[2] == 112 and tile(13).style.comp.size[2] == 17, tostring(tile(13).style.divider.offset[2]))
  view._ui_renderer = { fail = true }
  reload()
  check("name lines: when measuring fails the estimate is used (The Fool 1 line, the 31 letter name 2 lines)", tile(1).style.divider.offset[2] == 64 and tile(13).style.divider.offset[2] == 88, tostring(tile(13).style.divider.offset[2]))
  view._ui_renderer = nil
  settings.wave_def_custom_1 = nil; settings.on_custom_1 = nil
  reload()
end

-- the Edit pill, the layout under the name, the colours of the modifiers, the new suits --------------------------------------------
do
  local inp = { get = function() return nil end, is_null_service = function() return false end }
  local function upd() view:update(0.01, 0, inp) end
  local function reload() view:_reload(); view:_apply_screen() end
  local function lines_of(text) local n = 1; for _ in text:gmatch("\n") do n = n + 1 end return n end
  -- the colours read the mod's options like the game does (a later block of this file initialises them the same way)
  mod.rw.colors.init({ kind = mod.rw.groups.kind, option = function(id) return settings[id] end })

  local pill = pass_by_style(tile(1), "hotspot_edit").style
  local edit_bg = tile(1).style.edit_bg
  check("edit pill: the highlight is exactly the pill (46 x 16) and the same box as the click area, in the bottom right corner", edit_bg.size[1] == 46 and edit_bg.size[2] == 16 and edit_bg.offset[1] == pill.offset[1] and edit_bg.offset[2] == pill.offset[2] and pill.size[1] == 46 and pill.size[2] == 16 and pill.offset[1] + 46 == 214 and pill.offset[2] + 16 <= 270)
  check("edit pill: the label is centred in the pill", tile(1).style.edit_label.text_horizontal_alignment == "center" and tile(1).style.edit_label.size[1] == 46 and tile(1).style.edit_label.offset[1] == 168)
  check("edit pill: no highlight at rest", not edit_bg.visible)
  local rest = tile(1).style.edit_label.text_color[2]
  tile(1).content.hotspot_edit.is_hover = true; upd()
  check("edit pill: it lights up (and the label gets brighter) while the pointer is on it", edit_bg.visible and tile(1).style.edit_label.text_color[2] ~= rest)
  tile(1).content.hotspot_edit.is_hover = false; upd()
  check("edit pill: ...and goes out again", not edit_bg.visible and tile(1).style.edit_label.text_color[2] == rest)
  check("state line: the left text and the clock end before the pill starts", tile(1).style.state_left.offset[1] + tile(1).style.state_left.size[1] <= 168 and tile(1).style.state_clock.offset[1] + tile(1).style.state_clock.size[1] <= 168)

  -- under the name: the divider and the composition follow it
  check("layout: a one line name (The Fool): the divider is at 64, the composition from 71 with room for four lines", tile(1).style.divider.offset[2] == 64 and tile(1).style.comp.offset[2] == 71 and tile(1).style.comp.size[2] == 68, tostring(tile(1).style.divider.offset[2]))
  settings.wave_def_custom_1 = "The Endless Plague Ritual\t8 poxwalker"; settings.on_custom_1 = true; reload()
  check("layout: a two line name pushes them down: divider 88, composition from 95 with room for three lines", tile(13).content.name == "The Endless Plague Ritual" and tile(13).style.divider.offset[2] == 88 and tile(13).style.comp.offset[2] == 95 and tile(13).style.comp.size[2] == 51, tostring(tile(13).style.divider.offset[2]))
  settings.wave_def_custom_1 = "Four\t1 hound, 2 poxwalker, 3 mauler, 4 crusher"; reload()
  check("layout: four groups on a one line name all fit (four lines, no '+N more')", lines_of(tile(13).content.comp) == 4 and not tile(13).content.comp:find("tile_more", 1, true), tile(13).content.comp)
  settings.wave_def_custom_1 = "Five\t1 hound, 2 poxwalker, 3 mauler, 4 crusher, 5 sniper"; reload()
  check("layout: five groups on a one line name show three and '+2 more' on four lines", lines_of(tile(13).content.comp) == 4 and tile(13).content.comp:find("tile_more:2", 1, true) ~= nil, tile(13).content.comp)
  settings.wave_def_custom_1 = "Six\t1 hound, 2 poxwalker, 3 mauler, 4 crusher, 5 sniper, 6 rifleman"; reload()
  check("layout: six groups show three and '+3 more' on four lines", lines_of(tile(13).content.comp) == 4 and tile(13).content.comp:find("tile_more:3", 1, true) ~= nil, tile(13).content.comp)
  settings.wave_def_custom_1 = "The Endless Plague Ritual\t1 hound, 2 poxwalker, 3 mauler, 4 crusher, 5 sniper"; reload()
  check("layout: five groups on a two line name show two and '+3 more' on three lines", lines_of(tile(13).content.comp) == 3 and tile(13).content.comp:find("tile_more:3", 1, true) ~= nil, tile(13).content.comp)
  check("layout: the composition ends above the modifier line and the whisper (comp_y + room <= 146 < mods 148 < whisper 166)", tile(13).style.comp.offset[2] + tile(13).style.comp.size[2] <= 146 and tile(13).style.mods.offset[2] >= 146 and tile(13).style.whisper.offset[2] >= tile(13).style.mods.offset[2] + 16)

  -- the modifiers are coloured like Improved Havoc Tags does it
  settings.wave_def_custom_1 = "Rage\t2 mauler[garden+enraged]"; reload()
  check("modifiers: each name has the Improved Havoc Tags colour (garden blue-violet, enraged red), the separator stays plain", tile(13).content.mods:find("{#color(138,43,226)}", 1, true) ~= nil and tile(13).content.mods:find("{#color(255,54,36)}", 1, true) ~= nil and plain(tile(13).content.mods):find(" \194\183 ", 1, true) ~= nil, tile(13).content.mods)
  check("modifiers: ...and the line itself is the plain text of the names", plain(tile(13).content.mods) == "Purple \194\183 Enraged" or plain(tile(13).content.mods):find("Enraged", 1, true) ~= nil, plain(tile(13).content.mods))
  local havoc = mod.rw.colors
  settings.on_custom_1 = false; reload()
  check("modifiers: a card out of the draw is drained of colour, the modifier colours too", tile(13).content.mods:find("{#color(255,54,36)}", 1, true) == nil and tile(13).content.mods:find("{#color(", 1, true) ~= nil, tile(13).content.mods)
  settings.on_custom_1 = true; settings.colour_enemies = false; mod.rw.colors.clear_cache(); reload()
  check("modifiers: with the enemy colours switched off the names are plain text in rust", tile(13).content.mods:find("{#", 1, true) == nil and tile(13).content.mods ~= "" and tile(13).style.mods.visible, tile(13).content.mods)
  settings.colour_enemies = nil; mod.rw.colors.clear_cache()
  settings.wave_def_custom_1 = "Plain\t2 mauler"; reload()
  check("modifiers: a card without any has no line", not tile(13).style.mods.visible and tile(13).content.mods == "")

  -- the Daemonhost's card is purple
  settings.wave_def_custom_1 = "The Host\t1 daemonhost"; reload()
  check("warp: a custom card with a Daemonhost is a Warp card without anyone choosing: its label, the eye in a triangle (4 triangles, a pupil cut in the card's colour)", tile(13).content.suit_label == "WARP" and tile(13).style.icon_t1.visible and tile(13).style.icon_t4.visible and tile(13).style.icon_c1.visible and tile(13).style.icon_th4.visible, tile(13).content.suit_label)
  check("warp: the card is purple (the suit's colours)", tile(13).style.suit_label.text_color[2] == 0xb1 and tile(13).style.suit_label.text_color[3] == 0x84 and tile(13).style.suit_label.text_color[4] == 0xe0)
  settings.su_custom_1 = "snare"; reload()
  check("warp: choosing another suit wins over the default", tile(13).content.suit_label == "SNARE" and tile(13).style.icon_c4.visible)
  settings.su_custom_1 = nil
  -- all twelve suits draw a mark
  local all_marks = true
  local Cards = mod.rw.cards
  for _, suit in ipairs(Cards.SUIT_ORDER) do
    settings.su_custom_1 = suit; reload()
    local any = false
    for k = 1, 4 do if tile(13).style["icon_t" .. k].visible or tile(13).style["icon_c" .. k].visible then any = true end end
    if not any or tile(13).content.suit_label ~= string.upper(Cards.SUITS[suit].name) then all_marks = false end
  end
  check("suits: all twelve suits paint a mark and their name on a tile", all_marks)
  settings.su_custom_1 = nil; settings.wave_def_custom_1 = nil; settings.on_custom_1 = nil; reload()
end

-- cooldown looks on the tiles: rot and renewal, the murmur returns, the vial fills, the ready ping -------------------------
do
  local Cards = mod.rw.cards
  local rem = {}
  mod.rw.director = { cooldown_remaining = function(key, length) return rem[key] or 0 end }
  local inp = { get = function() return nil end, is_null_service = function() return false end }
  local function step(dt, t) view:update(dt, t or 0, inp) end
  local function rgb_of(col) return col[2], col[3], col[4] end
  local function same(col, rgb) return col[2] == rgb[1] and col[3] == rgb[2] and col[4] == rgb[3] end
  local function reload() view:_reload(); view:_apply_screen() end

  -- rot and renewal (the default look): The Procession (swarm), cooldown 150 s
  local C = view._waves[3].cooldown
  rem.wave_large = C
  reload()
  local accent = Cards.SUITS.swarm.accent
  check("rot: a card that has just been drawn is grey: the suit mark, label, glow and pips are rgb(74,74,64)", same(tile(3).style.suit_label.text_color, { 74, 74, 64 }) and same(tile(3).style.icon_c1.color, { 74, 74, 64 }) and same(tile(3).style.glow.color, { 74, 74, 64 }) and same(tile(3).style.pip_1.color, { 74, 74, 64 }) and tile(3).content.card_state == "cooling")
  check("rot: its text is faint (50 percent) and the name, composition and whisper share that", tile(3).style.name.text_color[1] == 128 and tile(3).style.comp.text_color[1] == 128 and tile(3).style.whisper.text_color[1] == 128, tile(3).style.name.text_color[1])
  rem.wave_large = C / 2
  step(0.01)
  local want = Cards.rot_color(0.5, accent)
  check("rot: halfway the colour is on the path between brown and ochre (the reference's rot path)", same(tile(3).style.suit_label.text_color, want) and same(tile(3).style.icon_c1.color, want) and want[1] > 90 and want[1] < 194, table.concat(want, ","))
  check("rot: ...the text has come back to 75 percent and the clock counts down (75 s = 1:15)", tile(3).style.name.text_color[1] == 191 and tile(3).content.state_clock == "1:15", tostring(tile(3).content.state_clock))
  rem.wave_large = C * 0.85
  step(0.01)
  check("rot: the clock follows the director's remaining time", tile(3).content.state_clock == "2:08" and tile(3).content.state_left == "tile_cooling", tile(3).content.state_clock)
  rem.wave_large = C * 0.02
  step(0.01)
  check("rot: nearly back: the colour is almost the suit's own", math.abs(tile(3).style.suit_label.text_color[2] - accent[1]) <= 8 and tile(3).style.name.text_color[1] >= 250)
  rem.wave_large = 0
  step(0.01)
  check("ready: the card is back: it says Ready, its colours are the suit's again and a ring leaves it", tile(3).content.state_left == "tile_ready" and same(tile(3).style.suit_label.text_color, accent) and tile(3).style.name.text_color[1] == 255 and tile(3).style.ping_t.visible and tile(3).style.ping_l.visible and tile(3).content.card_state == "in")
  local ping_alpha = tile(3).style.ping_t.color[1]
  step(0.5)
  check("ready: the ring grows and fades, the name flashes from the suit colour back to the text colour", tile(3).style.ping_t.size[1] > 228 * 0.96 and tile(3).style.ping_t.color[1] < ping_alpha and tile(3).style.name.text_color[2] ~= Cards.SUITS.swarm.text[1], tile(3).style.ping_t.size[1])
  step(0.7)
  check("ready: after 1.1 s the ring is gone and the card is simply in the draw", not tile(3).style.ping_t.visible and tile(3).content.state_left == "tile_in" and tile(3).style.name.text_color[2] == Cards.SUITS.swarm.text[1])
  settings.tarot_ping = false
  rem.wave_large = C; reload(); rem.wave_large = 0; step(0.01)
  check("ready: the ping can be turned off (the card just returns to 'In the draw')", tile(3).content.state_left == "tile_in" and not tile(3).style.ping_t.visible)
  settings.tarot_ping = nil

  -- the murmur returns: the whisper writes itself letter by letter, the card is faint (60 percent) until it is back
  settings.cl_wave_medium = "whisper"
  rem.wave_medium = C
  reload()
  check("murmur: a resting card with this look is faint (60 percent) and its whisper has not started", tile(2).alpha_multiplier == 0.6 and tile(2).content.whisper == "\"", tostring(tile(2).alpha_multiplier) .. " " .. tostring(tile(2).content.whisper))
  rem.wave_medium = C / 2
  step(0.01)
  local text = "Too many to count."
  local letters = Cards.whisper_letters(text, 0.5)
  check("murmur: halfway it has written " .. letters .. " of its " .. #text .. " letters, the quote is still open, the card is at 80 percent", tile(2).content.whisper == "\"" .. text:sub(1, letters) and letters > 8 and letters < #text and math.abs(tile(2).alpha_multiplier - 0.8) < 1e-9, tile(2).content.whisper)
  check("murmur: nothing else of the card changes colour (that is the rot look's job)", same(tile(2).style.suit_label.text_color, Cards.SUITS.swarm.accent))
  rem.wave_medium = C * 0.005
  step(0.01)
  check("murmur: at the end the whisper is whole and closed", tile(2).content.whisper == "\"" .. text .. "\"" and tile(2).alpha_multiplier > 0.99, tile(2).content.whisper)
  rem.wave_medium = 0; step(0.01)
  check("murmur: back: normal opacity and the ring", tile(2).alpha_multiplier == 1 and tile(2).style.ping_t.visible)
  step(1.2)
  settings.cl_wave_medium = nil
  -- a custom whisper with a multi-byte character is never cut in the middle of it
  settings.wh_wave_medium = "Sch\195\182n und gut"; settings.cl_wave_medium = "whisper"
  rem.wave_medium = C * 0.7; reload()
  check("murmur: a whisper with a two-byte letter (o with umlaut) is cut between letters, never inside one", (function()
    for k = 0, 8 do
      local p = k / 8
      rem.wave_medium = C * (1 - p); step(0.01)
      local w = tile(2).content.whisper:gsub("^\"", ""):gsub("\"$", "")
      if w:sub(-1) == "\195" then return false end -- a cut after the first byte of the umlaut is invalid in LuaJIT too
    end
    return true
  end)())
  settings.wh_wave_medium = nil; settings.cl_wave_medium = nil; rem.wave_medium = nil

  -- the vial fills (Rain of Rot has this look by default)
  rem.grenade_legion = view._waves[8].cooldown / 2
  reload()
  local rain = nil
  for i = 1, 14 do if tile(i).visible and tile(i).content.card_key == "grenade_legion" then rain = tile(i) end end
  check("vial: Rain of Rot has the vial look by default, half-way the liquid is half the tile high, in pus yellow, with a top line", rain ~= nil and rain.style.vial.visible and math.abs(rain.style.vial.size[2] - 135) < 1 and math.abs(rain.style.vial.offset[2] - 135) < 1 and same(rain.style.vial.color, Cards.BASE.pus) and rain.style.vial_line.visible and math.abs(rain.style.vial_line.offset[2] - 135) < 1)
  check("vial: three bubbles rise inside the liquid", rain.style.bubble_1.visible and rain.style.bubble_2.visible and rain.style.bubble_3.visible and rain.style.bubble_1.offset[2] > 135 - 12 and rain.style.bubble_1.offset[2] < 270)
  local y1 = rain.style.bubble_1.offset[2]
  step(0.5, 1.5)
  check("vial: the bubbles move with time", rain.style.bubble_1.offset[2] ~= y1)
  rem.grenade_legion = view._waves[8].cooldown * 0.97
  step(0.01, 2)
  check("vial: with only a little liquid there are no bubbles yet", not rain.style.bubble_1.visible and rain.style.vial.visible)
  check("vial: the card keeps its own colours (nothing is greyed)", same(rain.style.suit_label.text_color, Cards.SUITS.blight.accent))
  rem.grenade_legion = nil

  -- a card out of the draw does not rest visibly, and a repaint (a change in the editor) keeps the look
  settings.on_wave_large = false
  rem.wave_large = C / 2
  reload()
  check("off: a card that is out of the draw shows no cooldown look (dimmed, 'Out of the draw')", tile(3).content.state_left == "tile_off" and tile(3).content.card_state == "off" and tile(3).alpha_multiplier == 0.55 and tile(3).content.fx.state == "off")
  settings.on_wave_large = nil
  reload()
  check("off: back in the draw and still resting: the rot look is back with the right colour", tile(3).content.card_state == "cooling" and same(tile(3).style.suit_label.text_color, Cards.rot_color(0.5, accent)))
  rem.wave_large = nil
  mod.rw.director = { cooldown_remaining = function() error("no mission here") end }
  reload(); step(0.01)
  check("hub: a director that cannot answer (the editor also opens in the hub) is read as 'nothing is resting'", tile(3).content.card_state == "in" and tile(3).content.state_left == "tile_in" and tile(1).visible)
  mod.rw.director = nil
  reload()
  check("hub: no director at all is the same", tile(3).content.card_state == "in")
end

-- the card face (the Mirror): suit, threat, whisper, cooldown with its look, and the card on its stage ---------------------------
do
  local W = view._widgets_by_name
  local Cards = mod.rw.cards
  local WK = dofile(BASE .. "/ui/workshop.lua")
  local DEFS = dofile(BASE .. "/ui/wave_editor_definitions.lua")
  local inp = { get = function() return nil end, is_null_service = function() return false end }
  local PPf = dofile(BASE .. "/ui/wave_editor_components.lua")
  local function type_in(text) view._widgets_by_name.rw_popup_input.content.input_text = text; view:update(0.01, 0, inp) end
  local stage = W.rw_stage_card
  local function plate_of(id) for i, sid in ipairs(Cards.SUIT_ORDER) do if sid == id then return W["rw_plate_" .. i] end end end
  local function click_plate(id) plate_of(id).content.hotspot.pressed_callback() end
  local function click_look(kind) for i, k in ipairs({ "rot", "whisper", "vial" }) do if k == kind then W["rw_look_" .. i].content.hotspot.pressed_callback() end end end
  local function look_of(kind) for i, k in ipairs({ "rot", "whisper", "vial" }) do if k == kind then return W["rw_look_" .. i] end end end
  local function near(a, b) return math.abs(a - b) < 1e-6 end

  view:_open_detail("boss_ambush")
  check("face: a card's own screen has the Face tab, not selected, and no Mirror widgets yet", W.btn_face.visible and W.btn_face.content.hotspot_text == "btn_face" and W.btn_face.content.hotspot_on == false and not W.rw_plate_1.visible and not W.whisper_field.visible and not W.mirror_head_1.visible)
  click("btn_face")
  local plates = 0
  for i = 1, 12 do if W["rw_plate_" .. i].visible then plates = plates + 1 end end
  check("face: the Mirror: twelve suit plates, the threat diamonds, the whisper field, the cooldown stepper, three look plates and four headers; Back, the tabs and the stage; nothing of the Cauldron", view._screen == "face" and plates == 12 and W.rw_threat_big.visible and W.whisper_field.visible and W.stepper_cooldown.visible and W.rw_look_1.visible and W.rw_look_3.visible and W.mirror_head_4.visible and W.btn_back.visible and W.btn_face.content.hotspot_on == true and W.btn_enemies.visible and stage.visible and W.stage_plate.visible and not W.shelf_panel.visible and not W.rw_erow_1.visible and not W["rw_chip_1"].visible and not W.rw_suit_1.visible and not W.btn_dreg.visible and not W.rw_threat.visible and not W.list_panel.visible and not W.rw_row_1.visible and not W.bottom_panel.visible)
  check("face: the buttons of the Mirror and the shared ones: Change, Use the suit's line, Automatic for this suit, Reset face, Auto | By hand, the toolbar; the Cauldron's own buttons are hidden", W.btn_whisper_change.visible and W.btn_whisper_suit.visible and W.btn_look_auto.visible and W.btn_reset_face.visible and W.btn_thr_auto.visible and W.btn_thr_hand.visible and W.btn_enabled.visible and W.btn_preview.visible and not W.btn_rename.visible and not W.btn_delete.visible and not W.btn_add.visible and not W.btn_quickface.visible and not W.rw_scroll_up.visible and not W.stepper_chance.visible and not W.stepper_spread.visible)
  check("face: the headers and the title", W.title_text.content.title_text == "view_title_mirror" and W.mirror_head_1.content.head_title == "MIRROR_SUIT" and W.mirror_head_2.content.head_title == "MIRROR_THREAT" and W.mirror_head_3.content.head_title == "MIRROR_WHISPER" and W.mirror_head_4.content.head_title == "MIRROR_COOLDOWN" and W.mirror_head_4.content.head_hint == "mirror_cooldown_hint:10" and W.description_text.content.description_text == "view_desc_face:The Devil")
  check("face: the stage card is this card's tile at 1.4, not clickable, the same widget as on the Cauldron", stage.content.metrics.k == 1.4 and stage.content.name == "The Devil" and stage.content.suit_label == "FATEFUL" and stage.content.hotspot_top.disabled == true)

  -- the suits: all twelve at once, each in its own colours, the card's own lit
  check("suit: twelve plates, each with its name, its line of whisper and its colours; the card's suit (Fateful, a boss) is the selected one, nothing is suggested", plate_of("plague").content.suit_name == "Plague" and plate_of("plague").content.suit_line == "Something is growing." and plate_of("plague").content.suit.accent[1] == 183 and plate_of("warp").content.suit_name == "Warp" and plate_of("warp").content.suit.accent[1] == 0xb1 and plate_of("fateful").content.selected == true and plate_of("rage").content.selected == false and plate_of("fateful").content.sug_label == "" and plate_of("volley").style.icon_c1.visible)
  check("suit: the description of the card's suit stands under the plates, its name in the suit's colour", W.mirror_desc.content.mirror_desc:find("{#color(230,223,201)}Fateful{#reset()}  suit_desc_fateful", 1, true) ~= nil or W.mirror_desc.content.mirror_desc:find("Fateful{#reset()}  suit_desc_fateful", 1, true) ~= nil, W.mirror_desc.content.mirror_desc)
  check("suit: the numbers: a boss alone (1 enemy gives 1, a boss +2) is threat 3", W.mirror_numbers.content.mirror_numbers:find("^face_numbers:3,1,1") ~= nil and W.mirror_numbers.content.mirror_numbers:find("face_boss", 1, true) ~= nil, W.mirror_numbers.content.mirror_numbers)
  click_plate("rage")
  check("suit: clicking Rage writes su_<key>, selects its plate, and the card on the stage, its plate and the buttons follow", settings.su_boss_ambush == "rage" and plate_of("rage").content.selected and not plate_of("fateful").content.selected and stage.content.suit_label == "RAGE" and mod.rw_accent[1] == 0xc2 and W.stage_plate.content.stage.accent[1] == 0xc2)
  check("suit: the numbers now point at the suggested suit (Fateful) that the card no longer has, and the Fateful plate says Suggested", W.mirror_numbers.content.mirror_numbers:find("face_suggest:Fateful", 1, true) ~= nil and plate_of("fateful").content.sug_label == "MIRROR_SUGGESTED", plate_of("fateful").content.sug_label)
  click_plate("fateful")
  check("suit: back on the suggestion there is nothing more to suggest", settings.su_boss_ambush == "fateful" and W.mirror_numbers.content.mirror_numbers:find("face_suggest", 1, true) == nil and plate_of("fateful").content.sug_label == "")

  -- threat
  check("threat: auto at first: the diamonds show the worked-out value (3), Auto is selected, the numbers do not say by hand", W.rw_threat_big.content.threat == 3 and W.btn_thr_auto.content.hotspot_on == true and W.btn_thr_hand.content.hotspot_on == false and W.mirror_numbers.content.mirror_numbers:find("face_override", 1, true) == nil)
  W.rw_threat_big.content.hotspot_t1.pressed_callback()
  check("threat: the first diamond sets 1 by hand (th_<key>); the diamonds, the card and the numbers follow", settings.th_boss_ambush == 1 and W.rw_threat_big.content.threat == 1 and stage.style.th_o2.color[1] == 64 and stage.style.th_o1.color[1] == 255 and W.mirror_numbers.content.mirror_numbers:find("face_override:1", 1, true) ~= nil and W.btn_thr_hand.content.hotspot_on == true)
  W.rw_threat_big.content.hotspot_t5.pressed_callback()
  check("threat: the fifth sets 5, never more", settings.th_boss_ambush == 5 and W.rw_threat_big.content.threat == 5 and stage.style.th_o5.color[1] == 255)
  W.btn_thr_auto.content.hotspot.pressed_callback()
  check("threat: Auto works it out again (3)", settings.th_boss_ambush == 0 and W.rw_threat_big.content.threat == 3 and W.btn_thr_auto.content.hotspot_on == true)
  check("threat: the diamonds are big (26) in a row of 54, Auto and By hand sit beside them", W.rw_threat_big.def.size[1] == 270 and view._sg.btn_thr_auto[1] == WK.LEFT_X + 270 + 12 and view._sg.btn_thr_hand[1] == view._sg.btn_thr_auto[1] + 76 and view._sg.btn_thr_auto[2] == WK.MIRROR.threat_y + 10)

  -- In the hand: the card as the Spread HUD draws it, 1.5 times its size
  local hand = W.rw_hand_card
  check("hand: In the hand shows the card as the Spread draws it (1.5 times: 264 wide): the suit's background and bar, the name, the mark, the threat diamonds and the dots", hand.visible and W.hand_caption.visible and W.hand_caption.content.hand_caption == "HAND_CAPTION" and hand.content.hand_name == "The Devil" and near(hand.style.hand_bg.size[1], 264) and hand.style.hand_bg.size[2] >= 114 - 1e-6 and hand.style.hand_bg.size[2] <= WK.HAND.max_h and hand.style.hand_bg.color[2] == 0x17 and hand.style.hand_bar.color[2] == 0xe6 and hand.style.icon_t1.visible and hand.style.th_o3.visible and hand.style.dot_1.visible and not hand.style.dot_2.visible, tostring(hand.style.hand_bg.size[2]))
  check("hand: threat 3 fills three diamonds (the level's colour), the rest are the same diamonds dimmed; they are 12 wide on a copy of 13.1", hand.style.th_o1.color[1] == 255 and hand.style.th_o3.color[1] == 255 and hand.style.th_o4.color[1] == 64 and near(hand.style.th_o1.size[1], 12) and near(hand.style.th_h1.size[1], 13.1) and near(hand.style.th_o2.offset[1] - hand.style.th_o1.offset[1], 11.2 * 1.5))
  check("hand: the dots stand at the right edge of the card, inside it and clear of the diamonds", hand.style.dot_1.offset[1] + hand.style.dot_1.size[1] <= 264 and hand.style.dot_1.offset[1] > hand.style.th_o5.offset[1] + 12)
  check("hand: it is as high as the lines of the name need: a long name makes it higher, never past its node", (function()
    local short = hand.style.hand_bg.size[2]
    settings.wave_def_custom_1 = "SUPER JUICYED ARMOR WAVE\t4 mauler, 4 crusher, 3 bulwark"; settings.on_custom_1 = true
    view:_reload(); view:_open_detail("custom_1"); click("btn_face")
    local long = hand.style.hand_bg.size[2]
    local ok = long > short and long <= WK.HAND.max_h and hand.content.hand_name == "SUPER JUICYED ARMOR WAVE" and hand.style.hand_bar.size[2] == long and hand.style.dot_3.visible
    settings.wave_def_custom_1 = nil; settings.on_custom_1 = nil
    click("btn_back"); click("btn_back"); view:_reload(); view:_open_detail("boss_ambush"); click("btn_face")
    return ok
  end)(), tostring(hand.style.hand_bg.size[2]))
  click_plate("rage")
  check("hand: a new suit repaints it (Rage: the bar is rust, the card dark brown); and it is gone when the Cauldron is shown", hand.style.hand_bar.color[2] == 0xc2 and hand.style.hand_bg.color[2] == 0x24)
  click_plate("heresy")
  check("hand: Heresy gets its frame in the preview too (two units at 1.5 times = 3, blood red, all four sides); the other suits none", hand.style.hand_edge_t.visible and hand.style.hand_edge_b.visible and hand.style.hand_edge_l.visible and hand.style.hand_edge_r.visible and hand.style.hand_edge_t.size[2] == 3 and hand.style.hand_edge_l.size[1] == 3 and hand.style.hand_edge_t.color[2] == 0xa3 and hand.style.hand_edge_r.offset[1] == hand.style.hand_bg.size[1] - 3 and hand.style.hand_edge_b.offset[2] == hand.style.hand_bg.size[2] - 3)
  click_plate("fateful")
  check("hand: ...and a suit that is not Heresy hides it again", not hand.style.hand_edge_t.visible and not hand.style.hand_edge_l.visible)
  click("btn_enemies")
  check("hand: ...gone on the Cauldron", not hand.visible and not W.hand_caption.visible)
  click("btn_face")

  -- whisper
  check("whisper: the field shows the card's own line in quotes (The Devil has one), Change and Use the suit's line are there", W.whisper_field.content.whisper_text == "\"Something big is listening.\"" and W.whisper_field.content.whisper_own == true and W.btn_whisper_change.content.hotspot_text == "btn_change" and W.btn_whisper_suit.content.hotspot_text == "btn_whisper_suit")
  W.btn_whisper_change.content.hotspot.pressed_callback()
  check("whisper: Change opens a text box limited to 40 characters", view._popup ~= nil and view._popup.spec.max_length == 40 and view._popup.spec.label == "popup_whisper_title:The Devil")
  type_in("Speak")
  check("whisper: the card on the stage shows what is typed while it is typed (nothing committed yet counts as saved, Cancel puts the old line back)", stage.content.whisper == "\"Speak\"" and settings.wh_boss_ambush == "Speak", stage.content.whisper)
  PPf.Popup.cancel(view)
  check("whisper: Cancel restores the old line, on the card and in the settings", stage.content.whisper == "\"Something big is listening.\"" and (settings.wh_boss_ambush == "" or settings.wh_boss_ambush == nil or settings.wh_boss_ambush == "Something big is listening.") and view._popup == nil, stage.content.whisper .. " / " .. tostring(settings.wh_boss_ambush))
  W.btn_whisper_change.content.hotspot.pressed_callback()
  type_in("  Speak,   friend  "); PPf.Popup.commit(view)
  check("whisper: OK keeps it, cleaned (spaces) and stored as wh_<key>; the field and the card show it", settings.wh_boss_ambush == "Speak, friend" and W.whisper_field.content.whisper_text == "\"Speak, friend\"" and stage.content.whisper == "\"Speak, friend\"" and view._popup == nil, tostring(settings.wh_boss_ambush))
  W.whisper_field.content.hotspot.pressed_callback()
  type_in("This line is far too long to fit on the card, so it is cut"); PPf.Popup.commit(view)
  check("whisper: a long line is cut at 40 characters (a click on the field works like Change)", #settings.wh_boss_ambush <= 40 and #settings.wh_boss_ambush >= 30, tostring(settings.wh_boss_ambush))
  W.btn_whisper_suit.content.hotspot.pressed_callback()
  check("whisper: Use the suit's line empties it: the card's built-in line is back (The Devil has one)", settings.wh_boss_ambush == "" and W.whisper_field.content.whisper_text == "\"Something big is listening.\"", W.whisper_field.content.whisper_text)
  click("btn_back"); view:_open_detail("wave_medium"); click("btn_face")
  check("whisper: a card with no line of its own (The Pilgrims) shows the suit's line, dimmer (not its own)", W.whisper_field.content.whisper_text == "\"" .. Cards.SUITS.swarm.whisper .. "\"" and W.whisper_field.content.whisper_own == false and stage.content.whisper == "\"" .. Cards.SUITS.swarm.whisper .. "\"")
  click("btn_back"); view:_open_detail("boss_ambush"); click("btn_face")

  -- the looks of the cooldown
  check("look: three plates; automatic is on (Rot and renewal for Fateful, marked Automatic), the other two are not chosen; the rot plate's last stripe is the suit's colour", look_of("rot").content.hotspot_on == true and look_of("rot").content.look_auto == "LOOK_AUTOMATIC" and look_of("whisper").content.hotspot_on == false and look_of("vial").content.hotspot_on == false and W.btn_look_auto.content.hotspot_on == true and look_of("rot").content.look_name == "look_rot" and look_of("vial").content.look_desc == "look_vial_desc" and look_of("rot").content.accent_rgb[1] == 0xe6)
  click_look("vial")
  check("look: a click on The vial fills chooses it (cl_<key>); Automatic is off, the tag is gone, the card follows", settings.cl_boss_ambush == "vial" and look_of("vial").content.hotspot_on == true and look_of("rot").content.hotspot_on == false and look_of("rot").content.look_auto == "" and W.btn_look_auto.content.hotspot_on == false and stage.content.fx.look == "vial")
  click_look("whisper")
  check("look: ...and the murmur returns", settings.cl_boss_ambush == "whisper" and look_of("whisper").content.hotspot_on == true and stage.content.fx.look == "whisper")
  W.btn_look_auto.content.hotspot.pressed_callback()
  check("look: Automatic for this suit puts the choice back to the suit", settings.cl_boss_ambush == "" and look_of("rot").content.hotspot_on == true and look_of("rot").content.look_auto == "LOOK_AUTOMATIC" and W.btn_look_auto.content.hotspot_on == true)
  click_plate("murmur")
  check("look: ...for a Murmur card automatic is the murmur returns, marked", look_of("whisper").content.hotspot_on == true and look_of("whisper").content.look_auto == "LOOK_AUTOMATIC" and look_of("rot").content.look_auto == "" and look_of("whisper").content.look_sample:find("{#color", 1, true) ~= nil)
  settings.su_boss_ambush = "fateful"; view:_reload(); view:_apply_screen(true)

  -- the cooldown: 30 s steps, 30 s up to the longest option
  check("cooldown: the stepper shows the card's cooldown as a clock (240 s = 4:00) and says it in seconds", W.stepper_cooldown.content.stepper_value == "4:00" and W.stepper_cooldown.content.extra == "mirror_cooldown_extra:240" and W.stepper_cooldown.content.label == "", W.stepper_cooldown.content.stepper_value)
  click("stepper_cooldown", "hotspot_plus")
  check("cooldown: + adds 30 s and writes cd_<key>", settings.cd_boss_ambush == 270 and W.stepper_cooldown.content.stepper_value == "4:30")
  for _ = 1, 30 do click("stepper_cooldown", "hotspot_minus") end
  check("cooldown: never below 30 s", settings.cd_boss_ambush == 30 and W.stepper_cooldown.content.stepper_value == "0:30")
  for _ = 1, 40 do click("stepper_cooldown", "hotspot_plus") end
  check("cooldown: never above the longest cooldown option (10 minutes by default)", settings.cd_boss_ambush == 600 and W.stepper_cooldown.content.stepper_value == "10:00")
  settings.tarot_longest = 4
  click("stepper_cooldown", "hotspot_minus"); click("stepper_cooldown", "hotspot_plus"); click("stepper_cooldown", "hotspot_plus")
  check("cooldown: the limit follows the option (4 minutes), and the header says so", settings.cd_boss_ambush == 240 and W.mirror_head_4.content.head_hint == "mirror_cooldown_hint:4", tostring(settings.cd_boss_ambush))
  click("stepper_cooldown", "hotspot_value")
  check("cooldown: clicking the value opens a number box (30 to the longest)", view._popup ~= nil and view._popup.spec.min == 30 and view._popup.spec.max == 240)
  type_in("1000"); PPf.Popup.commit(view)
  check("cooldown: more than the longest is refused", view._popup ~= nil and view._popup.error ~= nil)
  type_in("90"); PPf.Popup.commit(view)
  check("cooldown: 90 is accepted", view._popup == nil and settings.cd_boss_ambush == 90 and W.stepper_cooldown.content.stepper_value == "1:30")
  settings.tarot_longest = nil
  settings.cd_boss_ambush = 100; view:_reload(); view:_apply_screen(true)
  click("stepper_cooldown", "hotspot_plus")
  check("cooldown: an old value that is not a multiple of 30 (100 s) is rounded to the grid first (90 + 30)", settings.cd_boss_ambush == 120, tostring(settings.cd_boss_ambush))
  settings.cd_boss_ambush = nil; view:_reload(); view:_apply_screen(true)

  -- the stage works here too: In the draw and Preview cooldown
  click("btn_enabled")
  check("toolbar: In the draw switches the card out of the draw on the Mirror too: the stage card dims and the line says so", settings.on_boss_ambush == false and stage.alpha_multiplier == 0.55 and W.stage_stats.content.stage_stats == "stage_stats_off")
  click("btn_enabled")
  click("btn_preview")
  view:update(2.5, 200, inp)
  check("toolbar: Preview cooldown plays the look on the Mirror too", view._preview ~= nil and stage.content.fx.p > 0.45 and stage.content.fx.p < 0.55)
  view:update(3, 203, inp)
  check("toolbar: ...and ends after five seconds", view._preview == nil and stage.content.fx.p == -1)

  -- Reset face: the suit, the threat, the whisper, the look and the cooldown back to their defaults; the enemies stay
  click_plate("snare"); W.rw_threat_big.content.hotspot_t4.pressed_callback(); click_look("vial"); click("stepper_cooldown", "hotspot_plus")
  settings.wh_boss_ambush = "Mine"; view:_reload(); view:_apply_screen(true)
  local parts_before = #view._parts
  click("btn_reset_face")
  check("reset: Reset face puts the suit, threat, whisper, look and cooldown back (cooldown to the card's own 240 s); the enemies stay", (settings.su_boss_ambush == "" or settings.su_boss_ambush == nil) and settings.th_boss_ambush == 0 and settings.wh_boss_ambush == "" and settings.cl_boss_ambush == "" and settings.cd_boss_ambush == 240 and #view._parts == parts_before and plate_of("fateful").content.selected and stage.content.suit_label == "FATEFUL" and W.stepper_cooldown.content.stepper_value == "4:00", tostring(settings.cd_boss_ambush))

  -- a popup locks the Mirror, closing it unlocks it
  click("btn_whisper_change")
  check("popup: while a box is open the plates, looks, diamonds and the field cannot be clicked", W.rw_plate_1.content.hotspot.disabled == true and W.rw_look_1.content.hotspot.disabled == true and W.rw_threat_big.content.hotspot_t1.disabled == true and W.whisper_field.content.hotspot.disabled == true and W.stepper_cooldown.content.hotspot_plus.disabled == true)
  PPf.Popup.cancel(view)
  check("popup: ...and they work again after it", W.rw_plate_1.content.hotspot.disabled == false and W.rw_look_1.content.hotspot.disabled == false and W.rw_threat_big.content.hotspot_t1.disabled == false and W.whisper_field.content.hotspot.disabled == false)

  -- the layout: nothing lies on another, every part is inside the left pane (to x 1240) or the right pane (from 1290), the sections end above the action bar
  local boxes, problems = {}, {}
  for _, w in ipairs(view._widgets) do
    if w.visible ~= false and w.def and w.def.size and w.name ~= "background" then
      local has_hotspot = false
      for _, p in ipairs(w.def.passes) do if p.pass_type == "hotspot" then has_hotspot = true end end
      if has_hotspot then
        local sg = view._sg and view._sg[w.def.node_id or w.name]
        local node = DEFS.scenegraph_definition[w.def.node_id or w.name]
        boxes[#boxes + 1] = { name = w.name, x = (sg or node.position)[1], y = (sg or node.position)[2], w = w.def.size[1], h = w.def.size[2] }
      end
    end
  end
  for i = 1, #boxes do
    local a = boxes[i]
    local header = a.name == "btn_enemies" or a.name == "btn_face" or a.name == "btn_help"
    local right_pane = a.x >= WK.RIGHT_X - 1 and not header
    if a.x < 0 or a.y < 0 or a.x + a.w > 1920 or a.y + a.h > WK.BOTTOM then problems[#problems + 1] = a.name .. " off the screen" end
    if not header and not right_pane and a.x + a.w > WK.LEFT_X + WK.LEFT_W + 0.5 then problems[#problems + 1] = a.name .. " past the left pane" end
    if right_pane and a.x + a.w > WK.RIGHT_X + WK.RIGHT_W + 0.5 then problems[#problems + 1] = a.name .. " past the right pane" end
    for j = i + 1, #boxes do
      local b = boxes[j]
      if a.x < b.x + b.w - 1e-6 and b.x < a.x + a.w - 1e-6 and a.y < b.y + b.h - 1e-6 and b.y < a.y + a.h - 1e-6 then problems[#problems + 1] = a.name .. "/" .. b.name end
    end
  end
  check("layout: on the Mirror no clickable widget lies on another and everything is inside its pane, above y 1014", #problems == 0 and #boxes > 30, #boxes .. " widgets: " .. table.concat(problems, ", "))
  check("layout: the sections end above the action bar and Back is where it is on every screen of a card", WK.MIRROR.bottom + 16 <= view._definitions.under_shelf.actions_y and view._sg.btn_back[1] == 105 and view._sg.btn_back[2] == view._definitions.under_shelf.actions_y and WK.MIRROR.head[1] + 28 <= WK.MIRROR.plate.y0 and WK.plate_pos(12) and select(2, WK.plate_pos(12)) + WK.MIRROR.plate.h <= WK.MIRROR.desc_y and WK.MIRROR.desc_y + WK.MIRROR.desc_h <= WK.MIRROR.head[2] and WK.MIRROR.threat_y + WK.MIRROR.threat_h <= WK.MIRROR.head[3] and WK.MIRROR.whisper_y + WK.MIRROR.whisper_h <= WK.MIRROR.head[4] and WK.MIRROR.cooldown_y + 48 <= WK.MIRROR.look.y and WK.MIRROR.look.y + WK.MIRROR.look.h <= WK.MIRROR.auto_y)

  -- the help text, the tabs, Back
  W.btn_help.content.hotspot.is_hover = true; view:update(0.01, 0, inp)
  check("help: the card face screen has its own help text", W.help_text.content.help_text == "help_face" and dofile(MODROOT .. "/scripts/mods/RealmsWaves/RealmsWaves_localization.lua").help_face ~= nil)
  W.btn_help.content.hotspot.is_hover = false; view:update(0.01, 0, inp)
  click("btn_enemies")
  check("tabs: the Enemies tab goes back to the Cauldron, the Mirror is gone", view._screen == "detail" and W.shelf_panel.visible and not W.rw_plate_1.visible and not W.whisper_field.visible and not W.rw_look_1.visible and not W.stepper_cooldown.visible and not W.mirror_head_1.visible)
  click("btn_face")
  click("btn_back")
  check("face: Back returns to the card's own screen", view._screen == "detail" and not W.rw_plate_1.visible and W.btn_face.content.hotspot_on == false and W.btn_face.visible)
  settings.su_boss_ambush = "rage"
  click("btn_back")
  view:_reload(); view:_apply_screen()
  check("face: the Deck shows the new face (Rage) on the card's tile and none of the Mirror", tile(5).content.suit_label:find("RAGE", 1, true) ~= nil and view._screen == "list" and not W.rw_stage_card.visible and not W.rw_threat_big.visible and not W.rw_look_1.visible)
  settings.su_boss_ambush = nil; settings.wh_boss_ambush = nil; settings.cl_boss_ambush = nil; settings.th_boss_ambush = nil
  view:_reload(); view:_apply_screen()

  -- the suits beyond the first six, and a Daemonhost
  view:_open_detail("boss_ambush"); click("btn_face")
  check("suit: the six newer suits (Volley, Snare, Brute, Dusk, Warp, Heresy) are on the same screen in their own colours, each with its line", plate_of("volley").content.suit.accent[1] == 0x7f and plate_of("snare").content.suit.accent[1] == 0x5f and plate_of("brute").content.suit.accent[1] == 0xcf and plate_of("heresy").content.suit.accent[1] == 0xe5 and plate_of("dusk").content.suit.accent[1] == 0x8e and plate_of("warp").content.suit.accent[1] == 0xb1 and plate_of("dusk").content.suit_line == Cards.SUITS.dusk.whisper)
  click_plate("warp")
  check("suit: clicking Warp writes su_<key> and the card shows it with its mark (an eye in a triangle), and says what it is for", settings.su_boss_ambush == "warp" and plate_of("warp").content.selected and stage.content.suit_label == "WARP" and stage.style.icon_t1.visible and W.mirror_desc.content.mirror_desc:find("suit_desc_warp", 1, true) ~= nil)
  click_plate("snare")
  check("suit: and Snare", settings.su_boss_ambush == "snare" and stage.content.suit_label == "SNARE" and W.mirror_desc.content.mirror_desc:find("suit_desc_snare", 1, true) ~= nil)
  settings.su_boss_ambush = nil; view:_reload(); view:_apply_screen(true)
  click("btn_back"); click("btn_back")

  settings.wave_def_custom_1 = "The Host\t1 daemonhost"; settings.on_custom_1 = true
  view:_reload(); view:_apply_screen()
  view:_open_detail("custom_1"); click("btn_face")
  check("face: a card with a Daemonhost starts as a Warp card (its plate is lit, nothing is suggested)", plate_of("warp").content.selected and W.mirror_numbers.content.mirror_numbers:find("face_suggest", 1, true) == nil and stage.content.suit_label == "WARP", tostring(stage.content.suit_label))
  click_plate("snare")
  check("face: choosing another suit: the numbers suggest Warp and the Warp plate says Suggested", settings.su_custom_1 == "snare" and W.mirror_numbers.content.mirror_numbers:find("face_suggest:Warp", 1, true) ~= nil and plate_of("warp").content.sug_label == "MIRROR_SUGGESTED", W.mirror_numbers.content.mirror_numbers)
  settings.wave_def_custom_1 = nil; settings.on_custom_1 = nil; settings.su_custom_1 = nil
  click("btn_back"); click("btn_back")
  view:_reload(); view:_apply_screen()
end

-- the blank tile makes a card in the first free custom slot
blank_tile().content.hotspot.pressed_callback()
check("blank tile: opens the first free custom slot (empty), its card screen", view._screen == "detail" and view._key == "custom_1" and #view._parts == 0 and view._wave.is_custom)
click("btn_back")
check("blank tile: Back returns to the Deck", view._screen == "list" and blank_tile().visible)

-- open a card with the Edit corner
settings["pct_wave_small"] = 4
open_card(1)
check("detail: screen and title", view._screen == "detail" and view._widgets_by_name.description_text.content.description_text == "view_desc_detail:The Fool")
check("detail: composition rows (a Scab enemy whose name does not say so gets the faction word, a Chaos unit does not)", plain(row(1).content.row_name) == "8 Poxwalker" and plain(row(4).content.row_name) == "2 Rifleman  Scab" and not row(5).visible, plain(row(1).content.row_name) .. " / " .. plain(row(4).content.row_name))
check("detail: the enemy rows are the Cauldron's own (rw_erow_1..5): visible, with a weight, a repeat and the three chips", row(1).visible and row(1) == view._widgets_by_name.rw_erow_1 and row(1).content.stepper_value == "8" and row(1).content.rep_value == "0" and row(1).content.hotspot_action_text == "btn_remove" and not view._widgets_by_name.rw_row_1.visible)
check("detail: buttons visible (the cooldown stepper is not: the cooldown is set on the card face screen)", view._widgets_by_name.btn_rename.visible and view._widgets_by_name.btn_add.visible and not view._widgets_by_name.stepper_cooldown.visible and view._widgets_by_name.stepper_chance.visible and view._widgets_by_name.btn_delete.visible)
check("detail: the chance stepper shows its value (the cooldown is on the Mirror)", view._widgets_by_name.stepper_chance.content.stepper_value == "4" and not view._widgets_by_name.stepper_cooldown.visible)
check("detail: the Deck's widgets are hidden", not tile(1).visible and not blank_tile().visible and not D.rw_strip.visible and not D.deck_count.visible and not D.list_panel.visible and not D.list_header.visible and not D.bottom_panel.visible and D.shelf_panel.visible and D.rw_stage_card.visible and D.stage_plate.visible and view._sg.scroll_up[1] == 1148 and view._sg.scroll_up[2] == 479)

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
check("typing filters the list live", #view._breeds == 2 and row(1).visible and row(2).visible and not row(3).visible and plain(row(1).content.row_name) == "Melee Twin  Scab" and plain(row(2).content.row_name) == "Ranged Twin  Scab", #view._breeds)
check("status text shows the match count and the filter", view._widgets_by_name.description_text.content.description_text:find("picker_status_filtered:2,") ~= nil and view._widgets_by_name.description_text.content.description_text:find("twin") ~= nil)
check("search box open: enemy rows stay clickable, other buttons are locked", row(1).content.hotspot_name.disabled == false and row(1).content.hotspot_action.disabled == false and view._widgets_by_name.btn_back.content.hotspot.disabled == true and view._widgets_by_name.btn_search.content.hotspot.disabled == true and view._widgets_by_name.rw_scroll_down.content.hotspot.disabled == (view._offset >= math.max(0, #view._breeds - 10)), tostring(row(1).content.hotspot_name.disabled))
check("popup buttons: the mod's own (200 x 48), Cancel left of OK on the right of the panel, no overlap, inside the panel (560 to 1360)", view._sg.rw_popup_confirm[1] == 1130 and view._sg.rw_popup_cancel[1] == 910 and view._sg.rw_popup_confirm[2] == 896 and view._sg.rw_popup_cancel[2] == 896 and view._sg.rw_popup_cancel[1] + 200 <= view._sg.rw_popup_confirm[1] and view._sg.rw_popup_confirm[1] + 200 <= 1360 - 30, view._sg.rw_popup_confirm[2])
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
check("typing 'twin two' leaves exactly one row", #view._breeds == 1 and plain(row(1).content.row_name) == "Melee Twin  Scab")
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
check("detail: Mods button on enemy rows", row(1).content.hotspot_mods_text == "btn_mods")
check("engine rule: detail row Mods/stepper/Remove hotspots run (the row has no check box: it is not a table row)", hotspot_runs(row(1), "hotspot_mods") and hotspot_runs(row(1), "hotspot_plus") and hotspot_runs(row(1), "hotspot_action") and pass_by_style(row(1), "same") ~= nil and not pcall(hotspot_runs, row(1), "hotspot_check"))
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
check("back from mods returns to detail with modifiers listed", view._screen == "detail" and (row(1).content.info:gsub("{#[^}]*}", "")) == "Purple, Enraged" and row(1).content.info:find("{#color(138,43,226)}Purple", 1, true) ~= nil and row(1).content.info:find("{#color(255,54,36)}Enraged", 1, true) ~= nil and row(1).content.row_name == "6 Poxwalker", row(1).content.info)
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
view._offset = 0; view:_refresh_rows(); view:_set_interaction_enabled() -- (the list scrolled to the group that was added)

-- custom mods (the Custom button beside Mods) ------------------------------------------------------------------------
do
  local W = view._widgets_by_name
  local inp = { get = function() return nil end, is_null_service = function() return false end }
  local PPt = dofile(BASE .. "/ui/wave_editor_components.lua")
  local function type_in(text) W.rw_popup_input.content.input_text = text; view:update(0.01, 0, inp) end
  local function rgba(c) return table.concat({ c[1], c[2], c[3], c[4] }, ",") end
  check("custom: a Custom button beside Mods on every enemy row, and it runs", row(1).content.hotspot_tune_text == "btn_tune" and hotspot_runs(row(1), "hotspot_tune") and row(2).content.hotspot_tune_text == "btn_tune")
  check("custom: Mods, Custom and the action button sit side by side after the count stepper, inside the row, without overlapping", (function()
    local function box(id) local s = pass_by_style(row(1), id).style; return s.offset[1], s.size[1] end
    local mx, mw = box("hotspot_mods"); local tx, tw = box("hotspot_tune"); local ax, aw = box("hotspot_action")
    local plus = pass_by_style(row(1), "hotspot_plus").style
    return plus.offset[1] + plus.size[1] <= mx and mx + mw <= tx and tx + tw <= ax and ax + aw <= 1710 and mw >= 100 and tw >= 100 and aw >= 100
  end)())
  local n_parts = #view._parts
  click_row(1, "hotspot_tune")
  check("custom: the screen opens for that group with nine rows, Back and its own help text", view._screen == "tune" and view._part_index == 1 and #view:_source() == 9 and row(9).visible and not row(10).visible and W.description_text.content.description_text:find("view_desc_tune", 1, true) ~= nil and W.btn_back.visible and W.help_text.content.help_text == "help_tune")
  check("custom: every row is a value at 100 (unchanged) with - and +, no Reset yet, no Mods/Custom buttons", row(1).content.row_name == "tune_health" and row(7).content.row_name == "tune_mass" and row(1).content.show_stepper and row(1).content.stepper_value == "100" and not row(1).content.show_action and not row(1).content.show_tune and not row(1).content.show_mods and not row(1).content.show_check and row(1).content.info:find("tune_health_info:10,1000", 1, true) ~= nil, row(1).content.info)
  check("custom: the header says the values are percents", W.list_header.content.col_4 == "col_percent")
  local text_colour = rgba(row(1).style.row_name.text_color)
  click_row(1, "hotspot_plus")
  check("custom: + raises the health by 10, saved in the card's recipe as {health=110}, with Reset", view._parts[1].tune and view._parts[1].tune.health == 110 and settings.wave_def_wave_small:find("{health=110}", 1, true) ~= nil and row(1).content.stepper_value == "110" and row(1).content.show_action and row(1).content.hotspot_action_text == "btn_tune_reset", settings.wave_def_wave_small)
  check("custom: a changed value's name is coloured, an unchanged one keeps the text colour", rgba(row(1).style.row_name.text_color) ~= text_colour and rgba(row(2).style.row_name.text_color) == text_colour)
  click_row(2, "hotspot_minus")
  check("custom: - lowers the size by 5; both are kept, in catalog order", view._parts[1].tune.size == 95 and view._parts[1].tune.health == 110 and settings.wave_def_wave_small:find("{health=110 size=95}", 1, true) ~= nil, settings.wave_def_wave_small)
  click_row(6, "hotspot_plus")
  check("custom: the burst steps by 25", view._parts[1].tune.burst == 125)
  click_row(1, "hotspot_value")
  check("custom: clicking the number opens a number box with that value's range (health 10 to 1000)", view._popup ~= nil and view._popup.spec.min == 10 and view._popup.spec.max == 1000 and view._popup.spec.integer == true and view._popup.spec.label:find("^popup_tune_title:tune_health,%d+ Poxwalker$") ~= nil, view._popup and view._popup.spec.label)
  type_in("5000"); PPt.Popup.commit(view)
  check("custom: a number out of range is refused", view._popup ~= nil and view._popup.error ~= nil)
  type_in("250"); PPt.Popup.commit(view)
  check("custom: 250 is accepted", view._popup == nil and view._parts[1].tune.health == 250)
  click_row(3, "hotspot_name")
  check("custom: a click on a row's name opens its number box too (run speed 25 to 300)", view._popup ~= nil and view._popup.spec.min == 25 and view._popup.spec.max == 300)
  PPt.Popup.cancel(view)
  for _ = 1, 100 do click_row(2, "hotspot_minus") end
  check("custom: never below the minimum (size 25)", view._parts[1].tune.size == 25)
  click_row(2, "hotspot_action")
  check("custom: Reset puts it back to 100 and takes it out of the recipe", view._parts[1].tune.size == nil and settings.wave_def_wave_small:find("size", 1, true) == nil and not row(2).content.show_action and row(2).content.stepper_value == "100")
  click("btn_back")
  check("custom: Back returns to the card's screen, the row lists the custom mods in its info column", view._screen == "detail" and plain(row(1).content.info) == "Health 250%, Shots per burst 125%", plain(row(1).content.info))
  check("custom: the group stays one group (the screen never adds or removes groups)", #view._parts == n_parts)

  -- with a modifier too: "Enraged  |  Health 250%, ..."
  click_row(1, "hotspot_mods"); click_row(2, "hotspot_check"); click("btn_back")
  check("custom: next to a modifier the custom mods follow a bar", plain(row(1).content.info) == "Enraged  |  Health 250%, Shots per bu..." and settings.wave_def_wave_small:find("[enraged]{health=250 burst=125}", 1, true) ~= nil, plain(row(1).content.info))
  click_row(1, "hotspot_mods"); click_row(2, "hotspot_check"); click("btn_back")

  -- the picker never adds to a group that has custom mods (and the list shows the group that was added)
  local before = #view._parts
  click("btn_add")
  local pox; for i, b in ipairs(view._breeds) do if b == "chaos_poxwalker" then pox = i end end
  view._offset = math.max(0, pox - 1); view:_refresh_rows()
  click_row(1, "hotspot_action")
  check("custom: adding an enemy that exists with custom mods makes a separate plain group", #view._parts == before + 1 and view._parts[#view._parts].tune == nil and view._parts[1].tune.health == 250, #view._parts)
  table.remove(view._parts, #view._parts); view:_save()
  view._offset = 0; view:_refresh_rows(); view:_set_interaction_enabled()

  -- the card's Deck tile says so
  check("custom: the card's modifier line says Custom", mod.rw.cards.modifier_line(view._parts, mod.rw.groups) == "Custom")

  -- clear everything
  click_row(1, "hotspot_tune"); click_row(1, "hotspot_action"); click_row(6, "hotspot_action"); click("btn_back")
  check("custom: with every value back to 100 the recipe has no braces", view._parts[1].tune == nil and settings.wave_def_wave_small:find("{", 1, true) == nil, settings.wave_def_wave_small)
end

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

check("detail rows show the repeat stepper", row(1).content.rep_value == "0" and hotspot_runs(row(1), "hotspot_rep_plus") and hotspot_runs(row(1), "hotspot_rep_minus") and hotspot_runs(row(1), "hotspot_rep_value"))
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
  check("detail rows have the Same tick box (runs while the repeat controls are shown)", hotspot_runs(row(1), "hotspot_same") and row(1).content.same_selected == false and view._widgets_by_name.list_header.content.col_7 == "col_same")
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
check("list screen: repeat column header cleared, steppers hidden", view._widgets_by_name.list_header.content.col_6 == "" and not S.stepper_spread.visible and not row(1).visible)
open_card(1)

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
view._widgets_by_name.stepper_chance.content.hotspot_plus.pressed_callback()
check("chance +1 in detail (the reset above restored 5)", settings["pct_wave_small"] == 6, settings["pct_wave_small"])
click("btn_enabled")
check("enabled toggled in detail", settings["on_wave_small"] == false and view._widgets_by_name.btn_enabled.content.hotspot_text == "btn_enabled_off")

-- built-in wave cannot lose its last enemy
click_row(1, "hotspot_action")
check("standard wave: cannot remove last but one? (2 parts -> 1)", #view._parts == 1)
click_row(1, "hotspot_action")
check("standard wave: last enemy kept", #view._parts == 1 and echoes[#echoes]:find("msg_need_one_enemy") ~= nil, echoes[#echoes])

-- reset
click("btn_reset")
check("reset restores built-in", view._wave.name == "The Fool" and #view._parts == 4 and settings["on_wave_small"] == true and settings["pct_wave_small"] == 5)

-- back navigation: detail -> list, back key
click("btn_back")
check("back to list", view._screen == "list" and not view._widgets_by_name.btn_rename.visible)
view:_on_back_pressed()
check("back key on list closes view", Managers.ui.closed == "realms_waves_editor")

-- custom slot workflow
blank_tile().content.hotspot.pressed_callback()
check("custom slot detail (empty)", view._screen == "detail" and #view._parts == 0 and view._wave.is_custom and view._widgets_by_name.btn_reset.content.hotspot_text == "btn_reset_clear")
click("btn_add"); view._offset = 0
click_row(3, "hotspot_action")
check("custom: first enemy added", #view._parts == 1 and view._parts[1].count == 1, #view._parts)
click_row(1, "hotspot_plus")
click("btn_enabled")
check("custom: enabled and in pool", settings["on_custom_1"] == true and #mod.rw.events.build_pool(function(id) return settings[id] end, mod.rw.groups) == 13)

-- the Deck's colours, Delete (in the card's own screen), Restore defaults ---------------------------------------------------
do
  local C = mod.rw.colors
  local spidey = { crusher_front_colour = "turquoise" }
  local named = { turquoise = { 64, 224, 208 } }
  C.init({ kind = mod.rw.groups.kind, option = function(id) return settings[id] end, spidey_setting = function(id) return spidey[id] end, named = function(name) return named[name] end })
  local input_stub3 = { get = function() return nil end, is_null_service = function() return false end }

  click("btn_back")
  check("deck: back on the Deck, the custom card with enemies has its tile (after the standard cards)", view._screen == "list" and view._deck[13].key == "custom_1" and tile(13).visible and tile(13).content.name == "Custom 1" and blank_tile().visible)

  -- colours on the tiles
  check("colours: the composition on a tile carries colour tags, the visible text is the plain lines", tile(1).content.comp:find("{#color(", 1, true) ~= nil and plain(tile(1).content.comp):find("^8 Poxwalker\n") ~= nil, plain(tile(1).content.comp))
  settings.colour_enemies = false; view:_refresh_rows()
  check("colours: switched off -> plain text", tile(1).content.comp:find("{#", 1, true) == nil)
  settings.colour_enemies = nil; view:_refresh_rows()
  check("colours: kind palette (poxwalker is normal, hound is special, spawn is boss)", table.concat(C.rgb("chaos_poxwalker"), ",") == "135,135,135" and table.concat(C.rgb("chaos_hound"), ",") == "255,235,40" and table.concat(C.rgb("chaos_spawn"), ",") == "255,50,50")
  check("colours: Spidey Sense colour wins for the enemies it knows (crusher)", table.concat(C.rgb("chaos_ogryn_executor"), ",") == "64,224,208")
  C.clear_cache(); settings.colour_spidey = false
  check("colours: Spidey Sense colours can be switched off", table.concat(C.rgb("chaos_ogryn_executor"), ",") == "240,240,240")
  settings.colour_spidey = nil; C.clear_cache()
  spidey.crusher_front_colour = "no_such_colour"
  check("colours: unknown Spidey Sense colour name falls back to the palette", table.concat(C.rgb("chaos_ogryn_executor"), ",") == "240,240,240")
  spidey.crusher_front_colour = "turquoise"; C.clear_cache()

  open_card(1)
  check("colours: detail rows colour the enemy name", table.concat({ table.unpack(row(1).style.row_name.text_color, 2, 4) }, ",") == "135,135,135", table.concat(row(1).style.row_name.text_color, ","))
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

  -- Delete: the card's own screen has the button, the first click asks, the second one does it
  view:_open_detail("custom_1")
  check("delete: the card's screen has a Delete button", view._widgets_by_name.btn_delete.visible and view._widgets_by_name.btn_delete.content.hotspot_text == "btn_delete")
  click("btn_delete")
  check("delete: the first click only asks 'Sure?'", view._widgets_by_name.btn_delete.content.hotspot_text == "btn_sure" and view._screen == "detail" and settings["on_custom_1"] == true and #view._waves[13].parts == 1)
  click("btn_delete")
  check("delete: the second click empties the custom card and returns to the Deck", view._screen == "list" and settings["on_custom_1"] == false and (view._waves[13].parts == nil or #view._waves[13].parts == 0) and view._deck[13].blank == true and not tile(13).visible)
  -- the confirmation runs out
  settings["wave_def_custom_3"] = "Temp\t3 hounds"; view:_reload(); view:_open_detail("custom_3")
  click("btn_delete")
  check("delete: pending confirmation shown", view._widgets_by_name.btn_delete.content.hotspot_text == "btn_sure")
  view:update(0.01, 100, input_stub3)
  check("delete: the confirmation expires after a few seconds", view._widgets_by_name.btn_delete.content.hotspot_text == "btn_delete" and view._confirm == nil)
  click("btn_back"); settings["wave_def_custom_3"] = ""; view._offset = 0; view:_reload(); view:_apply_screen()

  -- any card can be deleted, the default ones too; Restore defaults brings everything back
  settings["pct_wave_small"] = 33
  settings["wave_def_wave_small"] = "My Small\t4 hounds"; view:_reload(); view:_apply_screen()
  check("delete: a changed standard card shows its new name on its tile", tile(1).content.name == "My Small")
  view:_open_detail("wave_small"); click("btn_delete")
  check("delete: deleting a standard card asks 'Sure?' first too", view._widgets_by_name.btn_delete.content.hotspot_text == "btn_sure" and settings["del_wave_small"] ~= true)
  click("btn_delete")
  check("delete: the second click hides the standard card (it is deleted)", settings["del_wave_small"] == true and tile(1).content.name ~= "My Small" and #view._waves == 99 and view._deleted_count == 1 and view._screen == "list", tostring(tile(1).content.name) .. " " .. #view._waves)
  check("delete: the Deck says how many default cards are deleted", view._widgets_by_name.bottom_title.content.bottom_title == "bottom_list_deleted:1")
  local pool_has = false; for _, e in ipairs(mod.rw.events.build_pool(function(id) return settings[id] end, mod.rw.groups)) do if e.key == "wave_small" then pool_has = true end end
  check("delete: a deleted card is not drawn and not found by /rw_test", not pool_has and select(1, mod.rw.events.find("my_small", function(id) return settings[id] end, mod.rw.groups)) == nil)
  -- Restore defaults
  settings["pct_boss_ambush"] = 99; view:_reload(); view:_apply_screen()
  check("delete: Restore defaults button on the Deck", view._widgets_by_name.btn_default.visible and view._widgets_by_name.btn_default.content.hotspot_text == "btn_default")
  click("btn_default")
  check("delete: first click only asks 'Sure?'", view._widgets_by_name.btn_default.content.hotspot_text == "btn_sure" and settings["del_wave_small"] == true)
  click("btn_default")
  check("delete: second click restores every card to the defaults (deleted ones too, custom ones emptied)", settings["del_wave_small"] == false and settings["wave_def_wave_small"] == "" and settings["pct_wave_small"] == 5 and settings["pct_boss_ambush"] ~= 99 and #view._waves == 100 and tile(1).content.name == "The Fool" and view._widgets_by_name.bottom_title.content.bottom_title == "bottom_list_title", tostring(#view._waves))
  check("delete: the replaced setup is kept for Undo last load", settings.preset_undo ~= nil and settings.preset_undo ~= "")
  settings.preset_undo = nil
  click("btn_default"); view:update(0.01, 500, input_stub3)
  check("delete: an unconfirmed Restore defaults expires", view._widgets_by_name.btn_default.content.hotspot_text == "btn_default" and view._confirm == nil)
  settings["wave_def_custom_1"] = "Custom 1\t3 hounds"; settings["on_custom_1"] = true; view:_reload(); view:_apply_screen(true)

  -- time between waves on the list screen
  local W2 = view._widgets_by_name
  check("time: two steppers at the bottom of the list (minimum, maximum), label says what they are", W2.stepper_tmin.visible and W2.stepper_tmax.visible and W2.stepper_tmin.content.label == "set_interval_min" and W2.stepper_tmin.content.stepper_value == "150" and W2.stepper_tmax.content.stepper_value == "300" and not W2.stepper_chance.visible)
  click("stepper_tmin", "hotspot_plus")
  check("time: + adds 15 s from 150 and writes interval_min", settings.interval_min == 165 and W2.stepper_tmin.content.stepper_value == "165")
  settings.interval_min = 20; view:_apply_screen(true)
  click("stepper_tmin", "hotspot_plus"); check("time: 5 s steps below a minute", settings.interval_min == 25)
  click("stepper_tmin", "hotspot_minus"); click("stepper_tmin", "hotspot_minus"); click("stepper_tmin", "hotspot_minus"); click("stepper_tmin", "hotspot_minus"); click("stepper_tmin", "hotspot_minus"); click("stepper_tmin", "hotspot_minus")
  check("time: never below 5 s", settings.interval_min == 5)
  settings.interval_min = 100; settings.interval_max = 300; view:_apply_screen(true)
  click("stepper_tmax", "hotspot_minus")
  check("time: the maximum steps down by 15 s from 300 -> 285", settings.interval_max == 285)
  settings.interval_max = 105; view:_apply_screen(true)
  for _ = 1, 3 do click("stepper_tmax", "hotspot_minus") end
  check("time: lowering the maximum below the minimum pulls the minimum down with it", settings.interval_max <= settings.interval_min and settings.interval_min == settings.interval_max, settings.interval_min .. "/" .. settings.interval_max)
  settings.interval_min = 100; settings.interval_max = 100; view:_apply_screen(true)
  click("stepper_tmin", "hotspot_plus"); click("stepper_tmin", "hotspot_plus")
  check("time: raising the minimum above the maximum pushes the maximum up with it", settings.interval_min >= 130 and settings.interval_max == settings.interval_min, settings.interval_min .. "/" .. settings.interval_max)
  click("stepper_tmin", "hotspot_value")
  check("time: clicking the value opens a popup (5 to 1800)", view._popup ~= nil and view._popup.spec.min == 5 and view._popup.spec.max == 1800)
  view._widgets_by_name.rw_popup_input.content.input_text = "45"; view:update(0.01, 0, input_stub3)
  local PPtime = dofile(BASE .. "/ui/wave_editor_components.lua"); PPtime.Popup.commit(view)
  check("time: popup writes the minimum", settings.interval_min == 45)
  settings.interval_random = false; view:_apply_screen(true)
  check("time: with random off the minimum is labelled as the fixed time and the maximum says it is not used", W2.stepper_tmin.content.label == "set_interval_fixed" and W2.stepper_tmax.content.extra == "extra_not_random")
  settings.interval_random = nil; settings.interval_min, settings.interval_max = nil, nil; view:_apply_screen(true)

  -- help tooltip in the corner
  check("help: '?' corner button visible on every screen, tooltip hidden by default", W2.btn_help.visible and not W2.help_panel.visible and not W2.help_text.visible and not W2.hint_text.visible)
  W2.btn_help.content.hotspot.is_hover = true; view:update(0.01, 0, input_stub3)
  check("help: hovering the button shows the tooltip with the text of this screen", W2.help_panel.visible and W2.help_text.visible and W2.help_text.content.help_text == "hint_list")
  W2.btn_help.content.hotspot.is_hover = false; view:update(0.01, 0, input_stub3)
  check("help: moving away hides it", not W2.help_panel.visible)
  click("btn_help"); view:update(0.01, 0, input_stub3)
  check("help: a click pins it open, another unpins", W2.help_panel.visible and (function() click("btn_help"); view:update(0.01, 0, input_stub3); return not W2.help_panel.visible end)())
  click("btn_settings")
  W2.btn_help.content.hotspot.is_hover = true; view:update(0.01, 0, input_stub3)
  check("help: every screen has its own help text", W2.help_text.content.help_text == "hint_settings")
  W2.btn_help.content.hotspot.is_hover = false; click("btn_back")
  open_card(1)
  W2.btn_help.content.hotspot.is_hover = true; view:update(0.01, 0, input_stub3)
  check("help: the wave screen explains the fixed timer, distances and sharing", W2.help_text.content.help_text == "help_detail")
  W2.btn_help.content.hotspot.is_hover = false; view:update(0.01, 0, input_stub3); click("btn_back")
  check("names: the Deck's top button is called Deck presets (it holds the whole deck), 'Spreads' is only the HUD's hand", (function() local loc = dofile(MODROOT .. "/scripts/mods/RealmsWaves/RealmsWaves_localization.lua"); local bad = {}; for k, v in pairs(loc) do local en = type(v) == "table" and v.en; if type(en) == "string" and en:find("Spreads", 1, true) then bad[#bad + 1] = k end end; return loc.btn_presets.en == "Deck presets" and #bad == 0, table.concat(bad, ",") end)())
  check("help: texts exist in the localization for every screen", (function() local ok = true; for _, k in ipairs({ "hint_list", "hint_mods", "hint_presets", "hint_settings", "help_detail", "help_picker", "help_preset_view" }) do if not dofile(MODROOT .. "/scripts/mods/RealmsWaves/RealmsWaves_localization.lua")[k] then ok = false end end return ok end)())
  settings["pct_wave_small"] = 5

  -- settings screen
  check("settings: More options button (top right corner) visible on the wave list", view._widgets_by_name.btn_settings.visible and view._widgets_by_name.btn_settings.content.hotspot_text == "btn_settings")
  click("btn_settings")
  check("settings: screen opens with rows, Back only", view._screen == "settings" and row(10).visible and not view._widgets_by_name.btn_settings.visible and view._widgets_by_name.btn_back.visible and not view._widgets_by_name.hint_text.visible and view._widgets_by_name.btn_help.visible)
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
  check("settings: vote mode toggle writes mode=vote, then back to the tarot draw", vote_on and settings.mode == "tarot")
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
  open_card(1)
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
-- fixed timer: a wave that ignores its chance and spawns every N seconds ----------------------------------------------
do
  local W = view._widgets_by_name
  local inp = { get = function() return nil end, is_null_service = function() return false end }
  local PPt = dofile(BASE .. "/ui/wave_editor_components.lua")
  open_card(1)
  check("timer: stepper in the detail screen, off by default", W.stepper_timer.visible and W.stepper_timer.content.stepper_value == "val_off" and W.stepper_timer.content.extra == "extra_timer_off" and W.stepper_timer.content.label == "lbl_timer")
  check("timer: chance row says nothing special while the timer is off", W.stepper_chance.content.extra:find("extra_share") ~= nil)
  click("stepper_timer", "hotspot_plus")
  check("timer: first + from off gives 30 s", settings.ev_wave_small == 30 and W.stepper_timer.content.stepper_value == "30" and W.stepper_timer.content.extra == "extra_timer_on")
  click("stepper_timer", "hotspot_plus"); click("stepper_timer", "hotspot_plus")
  check("timer: steps of 5 s below a minute", settings.ev_wave_small == 40)
  settings.ev_wave_small = 60; view:_reload(); view:_apply_screen(true)
  click("stepper_timer", "hotspot_plus")
  check("timer: 15 s steps from a minute", settings.ev_wave_small == 75)
  settings.ev_wave_small = 300; view:_reload(); view:_apply_screen(true)
  click("stepper_timer", "hotspot_plus")
  check("timer: one minute steps from five minutes", settings.ev_wave_small == 360)
  settings.ev_wave_small = 3600; view:_reload(); view:_apply_screen(true)
  click("stepper_timer", "hotspot_plus")
  check("timer: capped at 3600 s", settings.ev_wave_small == 3600)
  settings.ev_wave_small = 10; view:_reload(); view:_apply_screen(true)
  click("stepper_timer", "hotspot_minus"); click("stepper_timer", "hotspot_minus")
  check("timer: stepping down below 5 s switches it off", settings.ev_wave_small == 0 and W.stepper_timer.content.stepper_value == "val_off")
  click("stepper_timer", "hotspot_value")
  check("timer: clicking the value opens a popup (0 to 3600)", view._popup ~= nil and view._popup.spec.min == 0 and view._popup.spec.max == 3600)
  view._widgets_by_name.rw_popup_input.content.input_text = "3"; view:update(0.01, 0, inp); PPt.Popup.commit(view)
  check("timer: a typed value below 5 becomes 5", settings.ev_wave_small == 5)
  settings.ev_wave_small = 90; view:_reload(); view:_apply_screen(true)
  check("timer: with a timer the chance row says the wave is not drawn", W.stepper_chance.content.extra == "extra_timer_wave")
  click("btn_back")
  check("timer: a card on a fixed timer leaves the draw (12 of the 13 cards with enemies stay), has no strip segment, its tile is still there", D.deck_count.content.deck_count == "deck_count:12" and #view._strip_segments == 12 and tile(1).visible and view._waves[1].timer == 90, D.deck_count.content.deck_count)
  open_card(1); click("btn_reset"); click("btn_back")
  check("timer: Reset to default clears the timer and the card is back in the draw", settings.ev_wave_small == 0 and D.deck_count.content.deck_count == "deck_count:13")
end
-- cooldown column, random groups, colours that survive the cut -------------------------------------------------------
do
  local W = view._widgets_by_name
  settings.colour_enemies = nil; settings.colour_spidey = nil; mod.rw.colors.clear_cache() -- earlier tests may have left the colours switched off
  local inp = { get = function() return nil end, is_null_service = function() return false end }
  local PPc = dofile(BASE .. "/ui/wave_editor_components.lua")
  view._offset = 0; view:_reload(); view:_apply_screen()
  settings["cd_wave_small"] = 90; view:_reload(); view:_apply_screen(true)
  open_card(1)
  check("cooldown: the card's own screen does not show the cooldown stepper (it is on the Mirror; the old column of the list is gone)", not W.stepper_cooldown.visible)
  click("btn_back")
  settings["cd_wave_small"] = nil; view:_reload(); view:_apply_screen(true)

  -- random group, the easy way
  view:_open_detail("custom_1")
  local parts_before = #view._parts
  click("btn_add")
  check("random: the picker has a Random group button, Create only while the mode is on", W.btn_random.visible and not W.btn_random_done.visible and W.btn_random.content.hotspot_text == "btn_random_off")
  click("btn_random")
  check("random: turning it on shows Create group (0) and a hint in the status line", W.btn_random.content.hotspot_text == "btn_random_on" and W.btn_random_done.visible and W.btn_random_done.content.hotspot_text == "btn_random_done:0" and W.description_text.content.description_text:find("picker_random_status", 1, true) ~= nil)
  local first, second = view._breeds[1], view._breeds[2]
  click_row(1, "hotspot_action")
  check("random: clicking an enemy picks it instead of adding it", view._screen == "picker" and #view._parts == parts_before and #view._random_pick == 1 and row(1).content.info:find("^%[picked%]") ~= nil and W.btn_random_done.content.hotspot_text == "btn_random_done:1")
  click_row(1, "hotspot_name")
  check("random: clicking it again unpicks it", #view._random_pick == 0 and row(1).content.info:find("picked", 1, true) == nil)
  click("btn_random_done")
  check("random: Create with fewer than two enemies only says so", view._screen == "picker" and #view._parts == parts_before and view._picker_note == "picker_random_need_two")
  click_row(1, "hotspot_action"); click_row(2, "hotspot_action"); click_row(3, "hotspot_action")
  click("btn_random_done")
  local made = view._parts[#view._parts]
  check("random: Create group adds ONE part '1 random of A / B / C' and returns to the wave", view._screen == "detail" and #view._parts == parts_before + 1 and made.one_of ~= nil and #made.one_of == 3 and made.count == 1 and made.one_of[1] == first and made.one_of[2] == second and view._random_mode == false)
  local last_row = #view._parts
  check("random: the wave's recipe text holds the group (a|b|c)", mod.rw.groups.to_recipe(view._parts):find("|", 1, true) ~= nil and settings["wave_def_custom_1"]:find("|", 1, true) ~= nil)
  check("random: the group's row names each enemy in its own colour", row(last_row).content.row_name:find("{#color(", 1, true) ~= nil and (row(last_row).content.row_name:gsub("{#[^}]*}", "")):find("^1 random of ") ~= nil, row(last_row).content.row_name)
  -- the mode is left again when the picker is left, and a single click on Add enemy starts clean
  click("btn_add"); click("btn_random"); click_row(1, "hotspot_action"); click("btn_back")
  click("btn_add")
  check("random: leaving or re-entering the picker clears the mode and the picks", view._random_mode == false and #view._random_pick == 0 and not W.btn_random_done.visible)
  -- stay mode: the group is added and the picker stays open
  settings.picker_stay = true
  click("btn_random"); click_row(1, "hotspot_action"); click_row(2, "hotspot_action"); click("btn_random_done")
  check("random: with 'stays here after adding' the picker stays open after Create", view._screen == "picker" and view._random_mode == false and view._picker_note == "picker_random_added:2")
  settings.picker_stay = nil
  click("btn_back")

  -- colours survive the cut in the wave edit screen (the Mods column) and the wave list
  local part = view._parts[1]
  part.mods = { "garden", "enraged", "toughened", "rotten" }; view:_save()
  local info = row(1).content.info
  check("cut: modifier names under an enemy keep their colours when the line is cut at 22 characters", (info:gsub("{#[^}]*}", "")) == "Purple, Enraged, Pu..." and info:find("{#color(138,43,226)}Purple", 1, true) ~= nil and info:find("{#color(255,54,36)}Enraged", 1, true) ~= nil and info:find("{#color(157,169,75)}Pu{#reset()}", 1, true) ~= nil, info)
  click("btn_back")
  check("cut: the tile of the card shows its modifiers as one line", tile(13).content.mods:find("Purple", 1, true) ~= nil and tile(13).content.mods:find("Enraged", 1, true) ~= nil, tostring(tile(13).content.mods))
  view._offset = 0
  view:_open_detail("custom_1"); view._parts = {}; for _, p in ipairs(mod.rw.groups.parse("3 hounds")) do view._parts[#view._parts + 1] = p end; view:_save(); click("btn_back")
end
-- tighter steppers and the corner buttons ------------------------------------------------------------------------
do
  local function gap_report(widget, label)
    local minus, value, plus
    for _, p in ipairs(widget.def.passes) do
      local id = p.style_id or p.content_id
      if id == "hotspot_minus" then minus = p.style end
      if id == "hotspot_plus" then plus = p.style end
      if id == "stepper_value" then value = p.style end
    end
    if not (minus and value and plus) then return label .. ": passes not found" end
    -- horizontal distances between the buttons and the value box (offset x, size w)
    local g1 = value.offset[1] - (minus.offset[1] + minus.size[1])
    local g2 = plus.offset[1] - (value.offset[1] + value.size[1])
    if g1 > 8 or g2 > 8 or g1 < 0 or g2 < 0 then return string.format("%s: gaps %d / %d", label, g1, g2) end
  end
  local problems = {}
  for _, name in ipairs({ "stepper_chance", "stepper_cooldown", "stepper_spread", "stepper_dmin", "stepper_timer", "stepper_tmin" }) do
    local p = gap_report(view._widgets_by_name[name], name); if p then problems[#problems + 1] = p end
  end
  local p = gap_report(view._widgets_by_name.rw_row_1, "list/detail row"); if p then problems[#problems + 1] = p end
  check("steppers: the value sits within 8 px of the - and + buttons (was about 12 and 34 px)", #problems == 0, table.concat(problems, "; "))
  local sg = view._definitions.scenegraph_definition
  local function rect(n) return sg[n].position[1], sg[n].position[2], sg[n].size[1], sg[n].size[2] end
  local function hit(a, b) local ax, ay, aw, ah = rect(a); local bx, by, bw, bh = rect(b); return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah end
  check("corner: 'More options' and '?' sit top right, clear of the title, the description and each other", not hit("btn_settings", "title_text") and not hit("btn_settings", "description_text") and not hit("btn_help", "title_text") and not hit("btn_help", "description_text") and not hit("btn_settings", "btn_help") and sg.btn_help.position[1] + sg.btn_help.size[1] <= 1920)
  check("corner: the help tooltip lies inside the screen and below the corner buttons", sg.help_panel.position[2] > sg.btn_help.position[2] + sg.btn_help.size[2] and sg.help_panel.position[1] + sg.help_panel.size[1] <= 1920 and sg.help_panel.position[2] + sg.help_panel.size[2] <= 1080)
  check("corner: the Back button does not overlap the Restore defaults / Import / Deck presets buttons (no click-through)", not hit("btn_back", "btn_default") and not hit("btn_back", "btn_wimport") and not hit("btn_back", "btn_presets"))
  check("deck: the bottom row (Import card, Restore defaults) does not overlap, nor do the header's Deck presets, More options, help, count and title", not hit("btn_wimport", "btn_default") and not hit("btn_presets", "btn_settings") and not hit("btn_presets", "btn_help") and not hit("btn_presets", "deck_count") and not hit("deck_count", "title_text") and not hit("btn_settings", "deck_count") and not hit("btn_presets", "title_text"))
  check("deck: the strip and its captions do not overlap the tiles or the header", not hit("deck_strip", "deck_caption") and not hit("deck_caption", "rw_tile_1") and not hit("deck_strip", "rw_tile_1") and not hit("deck_hover", "rw_tile_1") and not hit("deck_caption", "deck_hover") and not hit("deck_strip", "btn_presets") and not hit("deck_strip", "description_text"))
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
  settings["pct_custom_4"] = 7; settings["dmin_custom_4"] = 40; settings["dmax_custom_4"] = 90
  view:_reload(); view._offset = 0; view:_refresh_rows()
  view:_open_detail("custom_4")
  check("share: custom_4 detail open", view._screen == "detail" and view._key == "custom_4" and W.btn_share.visible, tostring(view._key))
  click("btn_share")
  local shared = view._widgets_by_name.rw_popup_input.content.input_text
  check("share: the popup shows the wave text and copies it", view._popup ~= nil and shared:sub(1, 5) == "RWW1|" and clip_text == shared and view._popup.spec.hint == "popup_share_hint_copied")
  local decoded = P.decode_wave(shared, mod.rw.events, mod.rw.groups)
  check("share: the text decodes to this wave", decoded and decoded.name == "Pack Attack" and decoded.pct == 7 and decoded.dmin == 40 and decoded.dmax == 90 and decoded.recipe:find("hound") ~= nil)
  PPw.Popup.cancel(view)

  -- import over this wave: paste a different wave over the text
  local other = P.encode_wave({ key = "custom_9", name = "Friend Wave", recipe = "6 mutants", enabled = true, pct = 6, cd = 75, sp = 6, re = 10, rf = 60, dmin = 0, dmax = 70 })
  click("btn_share")
  type_into(other)
  PPw.Popup.commit(view)
  check("share: pasting a friend's wave over the text replaces this wave", view._popup == nil and view._wave.name == "Friend Wave" and settings["pct_custom_4"] == 6 and settings["dmax_custom_4"] == 70 and settings["dmin_custom_4"] == 0 and #view._parts == 1 and view._parts[1].breed == "cultist_mutant" and view._parts[1].count == 6, tostring(view._wave.name))
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
  for i = 1, mod.rw.events.CUSTOM_SLOTS do settings["wave_def_custom_" .. i] = nil end
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
  for i = 1, mod.rw.events.CUSTOM_SLOTS do settings["wave_def_custom_" .. i] = "Full " .. i .. "\t1 hound" end
  view:_reload(); view:_refresh_rows(); echoes = {}
  click("btn_wimport")
  check("share: no free custom slot -> a message and no popup", view._popup == nil and echoes[#echoes] == "msg_no_free_slot", tostring(echoes[#echoes]))
  for i = 1, mod.rw.events.CUSTOM_SLOTS do settings["wave_def_custom_" .. i] = nil; settings["on_custom_" .. i] = nil; settings["pct_custom_" .. i] = nil; settings["dmin_custom_" .. i] = nil; settings["dmax_custom_" .. i] = nil; settings["cd_custom_" .. i] = nil; settings["sp_custom_" .. i] = nil; settings["re_custom_" .. i] = nil; settings["rf_custom_" .. i] = nil end
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
    -- on the screens of a card Back is in the action row at the foot of the Cauldron (105, 904): the same widget as the Cauldron's
    -- own Back, so it must not lie on any other widget of the Cauldron
    local back = { 105, view._definitions.under_shelf.actions_y, 180, 44 }
    local function overlaps_back(name)
      local n = sg[name]
      return back[1] < n.position[1] + n.size[1] and n.position[1] < back[1] + back[3] and back[2] < n.position[2] + n.size[2] and n.position[2] < back[2] + back[4]
    end
    local hit = {}
    local cauldron_widgets = { "btn_rename", "btn_text", "btn_add", "btn_enabled", "btn_reset", "btn_delete", "btn_share", "btn_enemies", "btn_face", "btn_dreg", "btn_scab", "btn_thr_auto", "btn_thr_hand", "btn_preview", "btn_quickface", "stepper_chance", "stepper_spread", "stepper_every", "stepper_for", "stepper_dmin", "stepper_dmax", "stepper_timer", "rw_threat", "shelf_panel" }
    for i = 1, 5 do cauldron_widgets[#cauldron_widgets + 1] = "rw_erow_" .. i end
    for i = 1, 12 do cauldron_widgets[#cauldron_widgets + 1] = "rw_suit_" .. i end
    for _, name in ipairs(cauldron_widgets) do
      if overlaps_back(name) then hit[#hit + 1] = name end
    end
    -- the other screens' Back (125, 800) against the buttons of the screens they return to (the Deck, the Deck presets)
    for _, name in ipairs({ "btn_presets", "btn_settings", "btn_wimport", "btn_default", "stepper_tmin", "stepper_tmax" }) do
      if overlaps("btn_back", name) then hit[#hit + 1] = name end
    end
    check("Back does not overlap any button of the screens it returns to (no click-through)", #hit == 0, table.concat(hit, ","))

    -- widgets shown together on one screen must not overlap and must stay inside the bottom panel
    local screens = {
      list = { "btn_wimport", "btn_default", "btn_back", "stepper_tmin", "stepper_tmax" },
      -- (the Mirror has its own layout test, with the rest of its checks)
      -- (the Cauldron has its own layout test, with the rest of its checks)
      picker = { "btn_back", "btn_search", "btn_stay", "btn_random", "btn_random_done" },
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
  check("presets: only Back on the presets screen", view._widgets_by_name.btn_back.visible and not view._widgets_by_name.btn_presets.visible and not view._widgets_by_name.btn_psave.visible and not view._widgets_by_name.hint_text.visible)
  click("btn_back")
  check("presets: back returns to the wave list", view._screen == "list")
  click("btn_presets")
  click_row(2, "hotspot_action")
  check("presets: opening a slot shows its screen and buttons", view._screen == "preset_view" and view._preset_index == 2 and view._widgets_by_name.btn_psave.visible and view._widgets_by_name.btn_pload.visible and view._widgets_by_name.btn_pexport.visible and view._widgets_by_name.btn_pimport.visible)
  check("presets: empty slot has no Clear and no Undo button", not view._widgets_by_name.btn_pclear.visible and not view._widgets_by_name.btn_pundo.visible and note() == "preset_slot_empty_long")
  click("btn_pload"); check("presets: loading an empty slot loads the default waves (a blank preset) and keeps an undo", note() == "preset_loaded_blank:2" and settings.preset_undo ~= nil and settings.preset_undo ~= "")
  click("btn_pundo")
  check("presets: Undo last load after loading a blank slot brings the previous waves back", settings.wave_def_custom_1 ~= "" and settings.on_custom_1 == true and settings.preset_undo == "", tostring(settings.wave_def_custom_1))
  click("btn_pexport"); check("presets: exporting an empty slot only says so", view._popup == nil and note() == "preset_nothing_to_export")
  click("btn_prename"); check("presets: renaming an empty slot asks to save first", view._popup == nil and note() == "preset_save_first")

  -- save the current setup (custom_1 has one enemy and is enabled; make one more visible change)
  settings["pct_wave_small"] = 6
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
  check("presets: load restores the saved setup", settings["pct_wave_small"] == 6 and settings["on_custom_1"] == true and note():find("preset_loaded:Boss Rush,2") ~= nil, tostring(settings["pct_wave_small"]))
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
-- ---- the button family (docs/08-workshop-redesign.md) -----------------------------------------------------------------------
do
  local C = dofile(BASE .. "/ui/wave_editor_components.lua") -- another copy of the module: the accent is shared through the mod object
  local ACC = mod.rw_accent
  local function mix(a, b, t) return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t } end
  local function near(c, rgb, alpha) return c ~= nil and math.abs(c[2] - rgb[1]) < 0.6 and math.abs(c[3] - rgb[2]) < 0.6 and math.abs(c[4] - rgb[3]) < 0.6 and (alpha == nil or c[1] == alpha) end
  local R = C.rgb
  local BILE = { 183, 194, 58 }
  local RUSTC = R.rust
  local function mk(builder, content)
    local passes = {}
    builder(passes)
    local def = UIWidget.create_definition(passes, "t", content or {}, { 400, 100 })
    return { def = def, content = table.clone(def.content), style = table.clone(def.style), visible = true }
  end
  local function paint(w)
    for _, p in ipairs(w.def.passes) do
      if p.change_function and p.style_id then p.change_function(p.content_id and w.content[p.content_id] or w.content, w.style[p.style_id]) end
    end
  end
  local function shown(w, id)
    local p = pass_by_style(w, id)
    if not p then return false end
    return p.visibility_function == nil or p.visibility_function(w.content, w.style[id]) and true or false
  end
  local function types(w) local t = {} for _, p in ipairs(w.def.passes) do t[p.pass_type] = true end return t end
  local function set(w, state)
    local h = w.content.hs
    h.is_hover, h.is_held, h.disabled = state == "hover" or state == "down", state == "down", state == "off"
    paint(w)
  end
  ACC[1], ACC[2], ACC[3] = BILE[1], BILE[2], BILE[3]

  -- standard
  local b = mk(function(p) C.button(p, "hs", { 10, 20, 2 }, { 200, 44 }, { label = "Rename" }) end)
  set(b, "rest")
  check("button: standard at rest: plate fill, dark green frame, bone label, no brackets", near(b.style.hs_fill.color, R.plate, 255) and near(b.style.hs_frame.color, R.frame, 255) and near(b.style.hs_label.text_color, R.text, 255) and not shown(b, "hs_b1") and not shown(b, "hs_b4"))
  set(b, "hover")
  check("button: hover mixes 14 percent of the accent into the plate, lights the frame, brightens the label and draws two corner brackets 4 units outside", near(b.style.hs_fill.color, mix(R.plate, BILE, 0.14), 255) and near(b.style.hs_frame.color, BILE, 255) and near(b.style.hs_label.text_color, R.bright, 255) and shown(b, "hs_b1") and shown(b, "hs_b2") and shown(b, "hs_b3") and shown(b, "hs_b4") and b.style.hs_b1.offset[1] == 6 and b.style.hs_b1.offset[2] == 16 and b.style.hs_b3.offset[1] == 10 + 200 + 4 - 9 and b.style.hs_b3.offset[2] == 20 + 44 + 4 - 2)
  set(b, "down")
  check("button: pressed pulls the brackets in to 1 unit, darkens the fill and lowers the label 2 units", near(b.style.hs_fill.color, mix(R.plate_down, BILE, 0.07), 255) and b.style.hs_b1.offset[1] == 9 and b.style.hs_b1.offset[2] == 19 and b.style.hs_b3.offset[1] == 10 + 200 + 1 - 9 and b.style.hs_label.offset[2] == 22)
  set(b, "rest")
  check("button: back to rest the label is back and the brackets are gone", b.style.hs_label.offset[2] == 20 and not shown(b, "hs_b1"))
  set(b, "off")
  check("button: disabled is a dim plate, a dim frame and a muted label, no brackets, whatever the pointer does", near(b.style.hs_fill.color, R.plate_off, 255) and near(b.style.hs_frame.color, R.frame_off, 255) and near(b.style.hs_label.text_color, R.label_off, 255) and not shown(b, "hs_b1"))
  b.content.hs.is_hover = true; paint(b)
  check("button: a disabled button under the pointer shows no hover", near(b.style.hs_frame.color, R.frame_off, 255) and not shown(b, "hs_b1"))

  -- the accent is one colour for every copy of the module and every button
  ACC[1], ACC[2], ACC[3] = 154, 163, 122
  set(b, "hover")
  check("accent: the buttons follow the accent that was set on the shared table (swarm: the frame turns ash green)", near(b.style.hs_frame.color, { 154, 163, 122 }, 255) and C.accent == mod.rw_accent)
  C.set_accent(BILE)
  check("accent: set_accent changes it in place (bile again)", mod.rw_accent[1] == 183 and mod.rw_accent[2] == 194 and mod.rw_accent[3] == 58)
  set(b, "hover")

  -- primary
  local pb = mk(function(p) C.button(p, "hs", { 0, 0, 2 }, { 200, 44 }, { label = "Import card", role = "primary" }) end)
  set(pb, "rest")
  check("button: primary is filled with the accent, the label is the ground colour", near(pb.style.hs_fill.color, BILE, 255) and near(pb.style.hs_frame.color, BILE, 255) and near(pb.style.hs_label.text_color, R.ground, 255))
  set(pb, "hover")
  local hov = { pb.style.hs_fill.color[2], pb.style.hs_fill.color[3] }
  set(pb, "down")
  local dwn = { pb.style.hs_fill.color[2], pb.style.hs_fill.color[3] }
  check("button: primary is lighter under the pointer and darker when pressed", hov[1] > 183 and hov[2] > 194 and dwn[1] < 183 and dwn[2] < 194 and shown(pb, "hs_b1"))
  set(pb, "off")
  check("button: a disabled primary is a dim olive plate", near(pb.style.hs_fill.color, { 43, 48, 23 }, 255))

  -- danger and its armed "Sure?"
  local db = mk(function(p) C.button(p, "hs", { 0, 0, 2 }, { 200, 44 }, { label = "Delete", role = "danger" }) end)
  set(db, "rest")
  check("button: danger at rest has a rust-tinted frame and rust text, no brackets", near(db.style.hs_frame.color, mix(R.frame, RUSTC, 0.5), 255) and near(db.style.hs_label.text_color, { 226, 164, 104 }, 255) and not shown(db, "hs_b1"))
  set(db, "hover")
  check("button: danger under the pointer lights the frame in rust (not in the accent) and its brackets are rust", near(db.style.hs_frame.color, RUSTC, 255) and near(db.style.hs_b1.color, RUSTC, 255) and shown(db, "hs_b1"))
  db.content.hs_on = true
  set(db, "rest")
  check("button: an armed danger button (Sure?) is solid rust with the ground colour for the label, and keeps its brackets at rest", near(db.style.hs_fill.color, RUSTC, 255) and near(db.style.hs_label.text_color, R.ground, 255) and shown(db, "hs_b1") and shown(db, "hs_b4"))

  -- quiet
  local qb = mk(function(p) C.button(p, "hs", { 0, 0, 2 }, { 80, 36 }, { label = "Edit", role = "quiet" }) end)
  set(qb, "rest")
  check("button: quiet has no frame: a transparent fill and a 1 unit line under the label in the accent", qb.style.hs_fill.color[1] == 0 and qb.style.hs_frame == nil and qb.style.hs_line.size[2] == 1 and qb.style.hs_line.offset[2] == 35 and near(qb.style.hs_label.text_color, BILE, 255) and not shown(qb, "hs_b1"))
  set(qb, "hover")
  check("button: quiet under the pointer washes the accent in (alpha 38) and thickens the line to 2 units", qb.style.hs_fill.color[1] == 38 and qb.style.hs_line.size[2] == 2 and qb.style.hs_line.offset[2] == 34 and near(qb.style.hs_line.color, BILE, 255))

  -- chip with a pip, tab with a bar, icon with a glyph
  local cb = mk(function(p) C.button(p, "hs", { 0, 0, 2 }, { 104, 40 }, { label = "Mods", role = "chip", pip = true }) end)
  set(cb, "rest")
  local dark = cb.style.hs_pip.color[1]
  cb.content.hs_on = true; set(cb, "rest")
  check("button: a chip has no brackets; its pip diamond is dim at rest and lit with the accent when the chip is on, and the frame leans toward the accent", dark == 90 and near(cb.style.hs_pip.color, BILE, 255) and cb.style.hs_pip_h.color[1] == 80 and not shown(cb, "hs_b1") and near(cb.style.hs_frame.color, mix(R.frame, BILE, 0.55), 255) and cb.style.hs_pip.angle == math.pi / 4)
  local tb = mk(function(p) C.button(p, "hs", { 0, 0, 2 }, { 150, 44 }, { label = "Enemies", role = "tab" }) end)
  set(tb, "rest")
  local unselected = shown(tb, "hs_bar")
  tb.content.hs_on = true; set(tb, "rest")
  check("button: a tab shows a 3 unit accent bar on its lower edge only while it is selected, and a lit plate", not unselected and shown(tb, "hs_bar") and tb.style.hs_bar.size[2] == 3 and tb.style.hs_bar.offset[2] == 41 and near(tb.style.hs_fill.color, mix(R.plate, BILE, 0.16), 255) and near(tb.style.hs_label.text_color, R.bright, 255))
  local ib = mk(function(p) C.button(p, "hs", { 0, 0, 2 }, { 44, 36 }, { role = "icon", glyph = "up" }) end)
  set(ib, "hover")
  local tri = pass_by_style(ib, "hs_glyph")
  check("button: an icon button draws a triangle (no letter) with a faint larger copy under it", tri ~= nil and tri.pass_type == "triangle" and pass_by_style(ib, "hs_label") == nil and ib.style.hs_glyph_h.triangle_corners[3][2] < ib.style.hs_glyph.triangle_corners[3][2] and ib.style.hs_glyph_h.color[1] == 77 and near(ib.style.hs_glyph.color, R.bright, 255) and ib.style.hs_glyph.triangle_corners[3][2] < ib.style.hs_glyph.triangle_corners[1][2])

  -- a button hidden by its flag has no hover and no hotspot
  local fb = mk(function(p) C.button(p, "hs", { 0, 0, 2 }, { 100, 40 }, { label = "x", flag = "show_x" }) end, { show_x = false })
  check("button: the visibility flag hides every part, the hotspot included", not shown(fb, "hs_fill") and not shown(fb, "hs_label") and hotspot_runs(fb, "hs") == false)
  fb.content.show_x = true
  check("button: ...and shows them when the flag is on", shown(fb, "hs_fill") and hotspot_runs(fb, "hs"))

  -- diamond check
  local kb = mk(function(p) C.checkbox_passes(p, { 10, 9, 1 }, nil, "show_check", nil, nil, "hot") end, { show_check = true, hot = { is_hover = false }, checkbox_selected = false })
  paint(kb)
  local off_alpha = kb.style.checkbox.color[1]
  kb.content.hot.is_hover = true; paint(kb)
  local hover_alpha = kb.style.checkbox.color[1]
  kb.content.checkbox_selected = true; paint(kb)
  check("check: a diamond (not a square): dim when off, brighter under the pointer, the accent when on, each on a faint larger copy", off_alpha == 80 and hover_alpha == 150 and near(kb.style.checkbox.color, BILE, 255) and kb.style.checkbox_h.size[1] > kb.style.checkbox.size[1] and kb.style.checkbox_h.offset[3] < kb.style.checkbox.offset[3] and kb.style.checkbox.angle == math.pi / 4 and kb.style.checkbox.offset[1] + kb.style.checkbox.size[1] / 2 == 10 + 14)
  kb.content.show_check = false
  check("check: hidden with its flag", not shown(kb, "checkbox"))

  -- stepper: one plate
  local sb = mk(function(p) C.stepper_passes(p, { minus_offset = { 100, 10, 2 }, value_offset = { 146, 10, 2 }, value_size = { 60, 40 }, plus_offset = { 208, 10, 2 } }) end, { stepper_value = "75" })
  paint(sb)
  local plate_ok = sb.style.stepper_value_frame.offset[1] == 100 and sb.style.stepper_value_frame.size[1] == 152 and sb.style.stepper_value_frame.size[2] == 40
  check("stepper: ONE plate from the minus to the plus (frame, fill, two dividers), the three hotspots keep their names", plate_ok and pass_by_style(sb, "stepper_value_div1") ~= nil and pass_by_style(sb, "stepper_value_div2") ~= nil and hotspot_runs(sb, "hotspot_minus") and hotspot_runs(sb, "hotspot_value") and hotspot_runs(sb, "hotspot_plus"))
  check("stepper: the minus is a bar and the plus is two bars (rects, no letters), the value is in the accent", sb.style.stepper_value_minus.size[1] == 14 and sb.style.stepper_value_minus.size[2] == 2 and sb.style.stepper_value_plus_h.size[1] == 14 and sb.style.stepper_value_plus_v.size[2] == 14 and near(sb.style.stepper_value.text_color, BILE, 255))
  check("stepper: nothing lights at rest (cells, underline)", not shown(sb, "stepper_value_hl1") and not shown(sb, "stepper_value_hl2") and not shown(sb, "stepper_value_underline"))
  sb.content.hotspot_plus.is_hover = true; paint(sb)
  check("stepper: the plus cell lights up under the pointer and its sign takes the accent; the minus cell stays dark", shown(sb, "stepper_value_hl2") and not shown(sb, "stepper_value_hl1") and near(sb.style.stepper_value_plus_h.color, BILE, 255) and near(sb.style.stepper_value_minus.color, R.text, 255))
  sb.content.hotspot_plus.is_hover = false; sb.content.hotspot_value.is_hover = true; paint(sb)
  check("stepper: a line under the value while the pointer is on it (a click opens the number box)", shown(sb, "stepper_value_underline"))
  sb.content.hotspot_value.is_hover = false; sb.content.stepper_value_dim = true; paint(sb)
  check("stepper: a dimmed stepper (a value that is not used) has a dim plate and value and lights nothing", near(sb.style.stepper_value_plate.color, R.plate_off, 255) and near(sb.style.stepper_value.text_color, R.label_off, 255) and near(sb.style.stepper_value_minus.color, R.label_off, 255))
  local sb2 = mk(function(p) C.stepper_passes(p, { minus_offset = { 0, 0, 2 }, value_offset = { 46, 0, 2 }, value_size = { 60, 40 }, plus_offset = { 108, 0, 2 } }, nil, { minus = "hotspot_rep_minus", value = "hotspot_rep_value", plus = "hotspot_rep_plus", text = "rep_value" }) end)
  check("stepper: a second stepper in one widget has its own names (rep_value, hotspot_rep_*)", pass_by_style(sb2, "rep_value_frame") ~= nil and hotspot_runs(sb2, "hotspot_rep_plus") and pass_by_style(sb2, "rep_value") ~= nil)

  -- frames
  local fr = mk(function(p) C.frame_passes(p, "frame", 800, 260, 1, { brackets = true }) end)
  paint(fr)
  check("frame: four 1 unit rects around the box in the accent, plus two corner brackets (14 x 3) outside it", fr.style.frame_t.size[1] == 800 and fr.style.frame_t.size[2] == 1 and fr.style.frame_r.offset[1] == 799 and fr.style.frame_k1.offset[1] == -5 and fr.style.frame_k4.offset[1] == 800 + 5 - 3 and near(fr.style.frame_t.color, BILE, 255))

  -- no bitmaps: every button and stepper widget is made of rects, triangles, rotated rects, text and hotspots
  local flat, bad_types = true, {}
  for name, w in pairs(view._widgets_by_name) do
    if w.def and (name:find("^btn_") or name:find("^stepper_") or name:find("^rw_scroll") or name:find("^rw_popup_c") or name:find("^rw_row_")) then
      for t in pairs(types(w)) do
        if not ({ rect = true, text = true, hotspot = true, triangle = true, rotated_rect = true })[t] then flat = false; bad_types[#bad_types + 1] = name .. ":" .. t end
      end
    end
  end
  check("every button, stepper, row and popup button is drawn from rects, triangles, rotated rects and text (no bitmap: nothing blurs at another resolution)", flat, table.concat(bad_types, ","))

  -- every button of the editor lies inside 1920 x 1080 (brackets 4 units outside included)
  local DEFS = dofile(BASE .. "/ui/wave_editor_definitions.lua")
  local outside = {}
  for name, w in pairs(view._widgets_by_name) do
    if w.def and name:find("^btn_") then
      local node = DEFS.scenegraph_definition[name]
      local size = node and node.size
      if not node or node.position[1] - 5 < 0 or node.position[2] - 5 < 0 or node.position[1] + size[1] + 5 > 1920 or node.position[2] + size[2] + 5 > 1080 then outside[#outside + 1] = name end
    end
  end
  check("every button node lies inside the 1920 x 1080 screen with room for its brackets", #outside == 0, table.concat(outside, ","))
  local mismatch = {}
  for name, w in pairs(view._widgets_by_name) do
    local node = w.def and name:find("^btn_") and DEFS.scenegraph_definition[name]
    if node and w.def.size and (w.def.size[1] ~= node.size[1] or w.def.size[2] ~= node.size[2]) then mismatch[#mismatch + 1] = name .. " " .. w.def.size[1] .. "x" .. w.def.size[2] .. " vs node " .. node.size[1] .. "x" .. node.size[2] end
  end
  check("every button is drawn exactly as big as its node (a wider button would cover its neighbour, as More options covered the help icon)", #mismatch == 0, table.concat(mismatch, " | "))
end

-- titles, the accent of a card's screens, and the lit buttons of the screens
do
  local W = view._widgets_by_name
  local function title() return W.title_text.content.title_text end
  -- the page takes the colours of the card's face (the Plague palette it always had when no card is open)
  local function theme_is(label, suit)
    local function is(c, rgb, a) return c[1] == a and c[2] == rgb[1] and c[3] == rgb[2] and c[4] == rgb[3] end
    local function k(rgb, f) return { math.floor(rgb[1] * f + 0.5), math.floor(rgb[2] * f + 0.5), math.floor(rgb[3] * f + 0.5) } end
    local function paint(w, id) pass_by_style(w, id).change_function(w.content, w.style[id]); return w.style[id] end
    local ground = suit and suit.card or { 30, 32, 28 }
    local panel = suit and k(suit.card, 0.65) or { 18, 22, 12 }
    local rowc = suit and k(suit.card, 0.8) or { 24, 30, 16 }
    local frame = suit and suit.frame or { 58, 68, 33 }
    local hi = suit and suit.hi or { 42, 52, 26 }
    local accent = suit and suit.accent or { 183, 194, 58 }
    check("theme (" .. label .. "): the ground, both panels, the title and the bottom title take the card's face", is(paint(W.background, "ground").color, ground, 255) and is(paint(W.list_panel, "list_fill").color, panel, 225) and is(paint(W.bottom_panel, "bottom_fill").color, panel, 225) and is(paint(W.title_text, "title_text").text_color, accent, 255) and is(paint(W.bottom_title, "bottom_title").text_color, accent, 255))
    local r = view._widgets_by_name.rw_row_1
    if r then
      r.content.hotspot_name.is_hover = false
      local at_rest, framed = paint(r, "row_background").color, paint(r, "row_frame").color
      local rest_ok, frame_ok = is(at_rest, rowc, 235), is(framed, frame, 190)
      r.content.hotspot_name.is_hover = true
      local hovered = paint(r, "row_background").color
      local mixed = { math.floor(hi[1] + (accent[1] - hi[1]) * 0.1), math.floor(hi[2] + (accent[2] - hi[2]) * 0.1), math.floor(hi[3] + (accent[3] - hi[3]) * 0.1) }
      r.content.hotspot_name.is_hover = false
      check("theme (" .. label .. "): a row rests on the card's colour, is framed in the suit's frame and warms to the suit's lighter colour under the pointer", rest_ok and frame_ok and hovered[1] == 250 and math.abs(hovered[2] - mixed[1]) <= 1 and math.abs(hovered[3] - mixed[2]) <= 1 and math.abs(hovered[4] - mixed[3]) <= 1, tostring(at_rest[2]) .. "," .. tostring(at_rest[3]) .. "," .. tostring(at_rest[4]))
    end
    local head = paint(W.list_header, "col_1").text_color
    check("theme (" .. label .. "): the column headings are the muted tone with a share of the accent", head[1] == 255 and math.abs(head[2] - (152 + (accent[1] - 152) * 0.2)) <= 1 and math.abs(head[3] - (147 + (accent[2] - 147) * 0.2)) <= 1)
  end
  view._screen = "list"; view._key = nil; view:_reload(); view:_apply_screen()
  check("title: the Deck keeps The Grandfather's Tarot, and the accent is bile", title() == "view_title" and mod.rw_accent[1] == 183 and mod.rw_accent[2] == 194 and mod.rw_accent[3] == 58)
  click("btn_settings")
  check("title: the options screen keeps the Tarot title", title() == "view_title" and mod.rw_accent[1] == 183)
  view:cb_back()
  click("btn_presets")
  check("title: the Deck presets screen keeps the Tarot title", title() == "view_title")
  view:cb_back()
  open_card(1)
  local fool = mod.rw.cards.suit(view._wave.suit).accent
  check("title: a card's own screen is The Grandfather's Cauldron, and the buttons take the card's suit as the accent (The Fool: swarm)", title() == "view_title_cauldron" and mod.rw_accent[1] == fool[1] and mod.rw_accent[2] == fool[2] and mod.rw_accent[3] == fool[3] and fool[1] ~= 183)
  click("btn_add")
  check("title: the enemy picker belongs to the Cauldron, with the suit accent", view._screen == "picker" and title() == "view_title_cauldron" and mod.rw_accent[1] == fool[1])
  view:cb_back()
  click_row(1, "hotspot_mods")
  check("title: the Mods screen is the Cauldron too", view._screen == "mods" and title() == "view_title_cauldron")
  theme_is("Mods, The Fool: swarm", mod.rw.cards.suit(view._wave.suit))
  view:cb_back()
  click_row(1, "hotspot_tune")
  check("title: and the Custom screen", view._screen == "tune" and title() == "view_title_cauldron")
  theme_is("Custom, The Fool: swarm", mod.rw.cards.suit(view._wave.suit))
  view:cb_back()
  click("btn_face")
  check("title: the card face is The Grandfather's Mirror, with the suit accent", view._screen == "face" and title() == "view_title_mirror" and mod.rw_accent[1] == fool[1])
  -- the Mirror changes the suit: the page follows at once (a plate of the twelve: Warp is the eleventh, Heresy the last)
  local fool_key = view._key
  local warp_place = mod.rw.cards.suit_index("warp")
  view:cb_suit_pick(warp_place)
  check("theme: choosing another suit on the card's screen recolours the page at once (Warp)", mod.rw.cards.suit(view._wave.suit) == mod.rw.cards.SUITS.warp and mod.rw_accent[1] == mod.rw.cards.SUITS.warp.accent[1])
  theme_is("Mirror, Warp", mod.rw.cards.SUITS.warp)
  settings["su_" .. fool_key] = nil; view:_reload(); view:_apply_screen(true)
  view:cb_back()
  view:cb_back()
  check("title: back on the Deck the title and the bile accent are back", title() == "view_title" and mod.rw_accent[1] == 183 and mod.rw_accent[2] == 194)
  theme_is("the Deck: the default palette", nil)
  check("theme: set_theme(nil) and the default table agree (Plague's own numbers: ground #1e2413 is not the default ground, the panel factors are)", mod.rw_theme.panel[1] == 18 and mod.rw_theme.row[2] == 30 and mod.rw_theme.frame[3] == 33)

  -- the chips of an enemy row light up when the group has modifiers or custom mods; toggles and the armed Delete
  settings.wave_def_custom_1 = "Chips\t3 crusher[enraged]{health=150}, 2 hound"; settings.on_custom_1 = true
  view:_reload(); view:_apply_screen()
  view:_open_detail("custom_1")
  check("chips: Mods is lit on a group with modifiers, Custom on a group with custom mods, neither on a plain group", row(1).content.hotspot_mods_on == true and row(1).content.hotspot_tune_on == true and row(2).content.hotspot_mods_on == false and row(2).content.hotspot_tune_on == false)
  check("toggle: Enabled is lit while the card is enabled", W.btn_enabled.content.hotspot_on == true)
  click("btn_enabled")
  check("toggle: ...and dark when it is not", W.btn_enabled.content.hotspot_on == false and W.btn_enabled.content.hotspot_text == "btn_enabled_off")
  click("btn_enabled")
  click("btn_delete")
  check("danger: the first click on Delete arms it (Sure?, lit)", W.btn_delete.content.hotspot_on == true and W.btn_delete.content.hotspot_text == "btn_sure")
  view:update(0.01, 10, { get = function() return nil end, is_null_service = function() return false end })
  check("danger: ...and it disarms by itself after a few seconds", W.btn_delete.content.hotspot_on == false and W.btn_delete.content.hotspot_text == "btn_delete")
  view:_open_detail("custom_1")
  click("btn_add")
  check("toggle: the picker's Stay toggle is lit when it is on", W.btn_stay.content.hotspot_on == (settings.picker_stay == true))
  view._screen = "list"; view._key = nil
  settings.wave_def_custom_1 = nil; settings.on_custom_1 = nil
  view:_reload(); view:_apply_screen()
  check("pixel snapping is switched on for the editor (the renderer snaps rects, bitmaps and text to whole device pixels)", view._render_settings.snap_pixel_positions == true)
end

-- ---- Dreg or Scab on the rows of a card and in the picker (docs/08) ---------------------------------------------------------
do
  settings.wave_def_custom_1 = "Mix\t2 gunner, 2 dreg gunner, 1 hound, 1 tox flamer"; settings.on_custom_1 = true
  view._screen = "list"; view._key = nil; view:_reload(); view:_apply_screen()
  view:_open_detail("custom_1")
  check("rows: a Scab gunner says Scab, a Dreg gunner already says Dreg, a hound says nothing, a Tox Flamer says Dreg", plain(row(1).content.row_name) == "2 Gunner  Scab" and plain(row(2).content.row_name) == "2 Dreg Gunner" and plain(row(3).content.row_name) == "1 Hound" and plain(row(4).content.row_name) == "1 Tox Flamer  Dreg", plain(row(1).content.row_name) .. "|" .. plain(row(2).content.row_name) .. "|" .. plain(row(4).content.row_name))
  check("rows: the faction word is in the faction's colour (steel grey for the Scabs, putrid yellow-green for the Dregs)", row(1).content.row_name:find("{#color(150,156,164)}Scab{#reset()}", 1, true) ~= nil and row(4).content.row_name:find("{#color(192,200,72)}Dreg{#reset()}", 1, true) ~= nil, row(1).content.row_name)
  click("btn_add")
  view._filter = "gunner"; view:_apply_screen()
  local names = {}
  for i = 1, 6 do if row(i).visible then names[#names + 1] = plain(row(i).content.row_name) end end
  check("picker: 'gunner' (also finds the shotgunners): the Scab ones say Scab, the Dreg ones already say Dreg, the Reaper is a Chaos ogryn and says nothing", table.concat(names, "|") == "Dreg Gunner|Dreg Shocktrooper|Gunner  Scab|Plasma Gunner  Scab|Reaper|Shocktrooper  Scab", table.concat(names, "|"))
  view._filter = ""; view:cb_back(); view._screen = "list"; view._key = nil
  settings.wave_def_custom_1 = nil; settings.on_custom_1 = nil
  view:_reload(); view:_apply_screen()
end

-- ---- the tile at another scale (docs/08: the card on the stage is 1.4 times the Deck's tile) -----------------------------------
do
  local BP = dofile(BASE .. "/ui/wave_editor_blueprints.lua")
  local K = 1.4
  local def = BP.tile("rw_tile_big", K)
  local big = view:_create_dynamic_widget("rw_tile_big", def)
  local small = view:_create_dynamic_widget("rw_tile_small", BP.tile("rw_tile_small"))
  local Spread = BP.Spread
  view._tile_shape = view._tile_shape or Spread.new_shape(Spread.ICON_TRIS, Spread.ICON_CIRCS)
  view._screen = "list"; view:_reload()
  local wave = view._waves[1]
  view:_paint_tile(big, wave)
  view:_paint_tile(small, wave)
  local function near(a, b) return math.abs(a - b) < 1e-6 end

  check("tile scale: the widget and its content know their scale: 319.2 x 378 for 1.4, 228 x 270 for the Deck's", big.content.metrics.k == K and near(def.size[1], 228 * K) and near(def.size[2], 270 * K) and small.content.metrics.k == 1 and small.def.size[1] == 228 and small.def.size[2] == 270)
  check("tile scale: no argument gives the Deck's tile exactly (the metrics of scale 1: a widget keeps its own copy of them)", small.content.metrics.k == 1 and small.content.metrics.w == 228 and small.content.metrics.pips_x == BP.TILE.pips_x and BP.TILE.w == 228 and BP.TILE.h == 270 and BP.TILE.name[3] == 200 and BP.TILE.pip[1] == 16)
  check("tile scale: fonts follow the scale (name 20 -> 28, text 13 -> 18, labels 12 -> 17), the Deck's stay 20 / 13 / 12", big.style.name.font_size == 28 and big.style.comp.font_size == 18 and big.style.suit_label.font_size == 17 and big.style.state_left.font_size == 17 and small.style.name.font_size == 20 and small.style.comp.font_size == 13 and small.style.suit_label.font_size == 12)
  check("tile scale: the glow, the pips and the hit areas scale, a line stays 1 unit", near(big.style.glow.size[1], 228 * K + 24 * K) and near(big.style.pip_1.size[1], 16 * K) and near(big.style.pip_1.size[2], 7 * K) and near(big.style.pip_2.offset[1] - big.style.pip_1.offset[1], 20 * K) and big.style.border_t.size[2] == 1 and big.style.border_l.size[1] == 1 and near(big.style.border_t.size[1], 228 * K) and big.style.divider.size[2] == 1)
  check("tile scale: the painted shapes scale: threat diamonds 8 -> 11.2 on a copy of 9.4 -> 13.2, dots 9 -> 12.6, the suit mark 26 -> 36.4", near(big.style.th_o1.size[1], 8 * K) and near(big.style.th_h1.size[1], 9.4 * K) and near(big.style.dot_1.size[1], 9 * K) and near(big.style.dot_h1.size[1], 10.2 * K) and big.style.icon_c1.visible and near(big.style.icon_c1.size[1] / small.style.icon_c1.size[1], K))
  check("tile scale: the divider and the composition follow the name at the same proportion", near(big.style.divider.offset[2], small.style.divider.offset[2] * K) and near(big.style.comp.offset[2], small.style.comp.offset[2] * K) and near(big.style.comp.size[2], small.style.comp.size[2] * K))
  check("tile scale: the threat diamonds are 11.2 apart times 1.4 and sit on the row", near(big.style.th_o2.offset[1] - big.style.th_o1.offset[1], (small.style.th_o2.offset[1] - small.style.th_o1.offset[1]) * K) and near(big.style.th_o1.offset[2], small.style.th_o1.offset[2] * K))

  -- everything visible lies inside the tile
  local function inside(w)
    local W, H = w.def.size[1], w.def.size[2]
    local bad = {}
    for _, p in ipairs(w.def.passes) do
      local st = w.style[p.style_id]
      if st and st.visible ~= false and p.pass_type ~= "texture" then
        local o, s = st.offset, st.size
        if p.pass_type == "triangle" then
          for i = 1, 3 do
            local x, y = o[1] + st.triangle_corners[i][1], o[2] + st.triangle_corners[i][2]
            if x < -1 or y < -1 or x > W + 1 or y > H + 1 then bad[#bad + 1] = p.style_id end
          end
        elseif s and (o[1] < -1 or o[2] < -1 or o[1] + s[1] > W + 1 or o[2] + s[2] > H + 1) then
          bad[#bad + 1] = p.style_id .. string.format(" (%.1f,%.1f %.1fx%.1f)", o[1], o[2], s[1], s[2])
        end
      end
    end
    return #bad == 0, table.concat(bad, ", ")
  end
  local ok_big, why_big = inside(big)
  local ok_small, why_small = inside(small)
  check("tile scale: everything drawn lies inside the tile at 1.4 as it does at 1 (the ping and the vial start hidden)", ok_big and ok_small, why_big .. " / " .. why_small)

  -- the hotspots: the ten pips side by side from edge to edge, nothing overlaps, everything inside
  local boxes, pips = {}, {}
  for _, p in ipairs(big.def.passes) do
    if p.pass_type == "hotspot" then
      local b = { p.style.offset[1], p.style.offset[2], p.style.size[1], p.style.size[2] }
      boxes[#boxes + 1] = b
      if p.content_id:find("^hotspot_pip") then pips[#pips + 1] = b end
    end
  end
  table.sort(pips, function(a, b) return a[1] < b[1] end)
  local flush = #pips == 10 and pips[1][1] == 0
  for i = 1, 9 do flush = flush and near(pips[i][1] + pips[i][3], pips[i + 1][1]) end
  flush = flush and near(pips[10][1] + pips[10][3], 228 * K)
  local overlap = false
  for i = 1, #boxes do for j = i + 1, #boxes do
    local a, b = boxes[i], boxes[j]
    if a[1] < b[1] + b[3] - 1e-9 and b[1] < a[1] + a[3] - 1e-9 and a[2] < b[2] + b[4] - 1e-9 and b[2] < a[2] + a[4] - 1e-9 then overlap = true end
  end end
  check("tile scale: 16 hotspots, the ten pips are side by side from edge to edge of the scaled tile, none overlap", #boxes == 16 and flush and not overlap)

  -- the name's lines are measured with the scaled box and font, so a name takes the same number of lines
  local long = "The Magician Of Endless Plague"
  check("tile scale: a name takes the same number of lines at 1.4 as at 1 (the box and the font grow together)", view:_name_lines(long, small.style.name, small.content.metrics) == view:_name_lines(long, big.style.name, big.content.metrics) and view:_name_lines("The Wheel", small.style.name) == 1)

  -- the vial and its bubbles at the scale
  view:_animate_vial(big, big.content.fx, 0.5, 1)
  view:_animate_vial(small, small.content.fx, 0.5, 1)
  check("tile scale: the vial rises through half the scaled tile, the bubbles are 6 -> 8.4", near(big.style.vial.size[2], 378 / 2) and near(big.style.vial.offset[2], 378 / 2) and near(small.style.vial.size[2], 135) and near(big.style.bubble_1.size[1], 6 * K) and near(small.style.bubble_1.size[1], 6))

  -- the ready ping at the scale stays around the tile
  big.content.fx.ping_t = 0
  view:_tick_ping(big, big.content.fx, 0.5)
  check("tile scale: the ready ping is a ring around the scaled tile", big.style.ping_t.visible and big.style.ping_t.size[1] > 228 * K * 0.96 and big.style.ping_l.size[2] > 270 * K * 0.96 and big.style.ping_t.offset[1] < 228 * K / 2)

  -- tidy: the two test widgets are not part of any screen
  for _, name in ipairs({ "rw_tile_big", "rw_tile_small" }) do
    local w = view._widgets_by_name[name]
    for i = #view._widgets, 1, -1 do if view._widgets[i] == w then table.remove(view._widgets, i) end end
    view._widgets_by_name[name] = nil
  end
end

-- ---- the Cauldron: the card's own screen with the shelf, the stage and the quick face (docs/08-workshop-redesign.md) ----------
do
  local W = view._widgets_by_name
  local DEFS = dofile(BASE .. "/ui/wave_editor_definitions.lua")
  local WK = dofile(BASE .. "/ui/workshop.lua")
  local PP_ = dofile(BASE .. "/ui/wave_editor_components.lua")
  local inp = { get = function() return nil end, is_null_service = function() return false end }
  local chips = DEFS.shelf_layout.chips
  local function chip_of(what) for i, c in ipairs(chips) do if c.entry.breed == what or c.entry.label == what then return i end end end
  local function click_chip(what) W["rw_chip_" .. chip_of(what)].content.hotspot.pressed_callback() end
  local function plain_lines(w) return plain(w.content.comp) end
  local function near(a, b) return math.abs(a - b) < 1e-6 end

  for i = 1, mod.rw.events.CUSTOM_SLOTS do settings["wave_def_custom_" .. i] = nil; settings["on_custom_" .. i] = nil end
  settings.wave_def_custom_1 = "The Magician\t3 trapper, 2 flamer, 2 mutant, 2 tox flamer"; settings.on_custom_1 = true; settings.su_custom_1 = "blight"; settings.pct_custom_1 = 10
  settings.shelf_faction = nil
  view._screen = "list"; view._key = nil; view:_reload(); view:_apply_screen()
  view:_open_detail("custom_1")
  local stage = W.rw_stage_card

  -- what is on the screen
  local n_chips = 0
  for i = 1, #chips do if W["rw_chip_" .. i].visible then n_chips = n_chips + 1 end end
  local n_suits = 0
  for i = 1, 12 do if W["rw_suit_" .. i].visible then n_suits = n_suits + 1 end end
  check("cauldron: four enemy rows of five, the shelf with its 30 chips, twelve suit tiles, the threat control, the stage with the card", W.rw_erow_4.visible and not W.rw_erow_5.visible and W.shelf_panel.visible and n_chips == 30 and n_suits == 12 and W.rw_threat.visible and W.stage_plate.visible and stage.visible and W.enemy_header.visible and W.spawn_label.visible)
  check("cauldron: the table of the other screens is gone: no generic rows, no table panel, no bottom panel", not W.rw_row_1.visible and not W.list_panel.visible and not W.list_header.visible and not W.bottom_panel.visible)
  check("cauldron: the settings of the card: the chance under the card, six spawn steppers, no cooldown stepper", W.stepper_chance.visible and W.stepper_spread.visible and W.stepper_every.visible and W.stepper_for.visible and W.stepper_dmin.visible and W.stepper_dmax.visible and W.stepper_timer.visible and not W.stepper_cooldown.visible)
  check("cauldron: the tabs: Enemies is selected, Face is not; the toolbar, the quick face and the shelf's switch are shown", W.btn_enemies.visible and W.btn_enemies.content.hotspot_on == true and W.btn_face.visible and W.btn_face.content.hotspot_on == false and W.btn_preview.visible and W.btn_quickface.visible and W.btn_dreg.visible and W.btn_scab.visible and W.btn_thr_auto.visible and W.btn_thr_hand.visible)

  -- the card on the stage
  check("stage: the card is the Deck's tile at 1.4 times its size, painted from the card being edited", stage.content.metrics.k == 1.4 and near(stage.def.size[1], 319.2) and near(stage.def.size[2], 378) and stage.content.name == "The Magician" and stage.content.suit_label == "BLIGHT" and plain_lines(stage):find("3 Trapper", 1, true) ~= nil and stage.style.name.font_size == 28)
  local pos = view._definitions.scenegraph_definition.rw_stage_card
  check("stage: the card is centred on its plate and sits inside it (22 below the top)", math.abs(pos.position[1] + pos.size[1] / 2 - (WK.PLATE.x + WK.PLATE.w / 2)) < 0.5 and pos.position[2] == WK.PLATE.y + 22 and pos.position[2] + pos.size[2] <= WK.PLATE.y + WK.PLATE.h - 30)
  local locked = true
  for _, id in ipairs(view.TILE_HOTSPOTS) do if stage.content[id].disabled ~= true then locked = false end end
  check("stage: nobody can click the card (every hotspot of the stage tile is disabled)", locked)
  check("stage: the plate takes the suit's colours (blight: card #25240c, frame #5c5a1e, glow in pus yellow)", W.stage_plate.content.stage.card[1] == 0x25 and W.stage_plate.content.stage.frame[1] == 0x5c and W.stage_plate.content.stage.accent[1] == 0xe3)
  check("stage: the line under the card: threat, enemies and the share of the draw", W.stage_stats.content.stage_stats:find("^stage_stats:3,9,") ~= nil, W.stage_stats.content.stage_stats)
  check("stage: the title, the caption and the labels are set", W.stage_caption.content.stage_caption == "STAGE_CAPTION" and W.quick_label.content.quick_label == "QUICK_LABEL" and W.threat_label.content.threat_label == "LBL_THREAT" and W.spawn_label.content.spawn_label == "SPAWN_LABEL")

  -- no widget of the screen lies on another one, everything is inside its pane
  local boxes, problems = {}, {}
  for _, w in ipairs(view._widgets) do
    if w.visible ~= false and w.def and w.def.size and w.name ~= "background" then
      local has_hotspot = false
      for _, p in ipairs(w.def.passes) do if p.pass_type == "hotspot" then has_hotspot = true end end
      if has_hotspot then
        local sg = view._sg and view._sg[w.def.node_id or w.name]
        local node = DEFS.scenegraph_definition[w.def.node_id or w.name]
        local x, y = (sg or node.position)[1], (sg or node.position)[2]
        boxes[#boxes + 1] = { name = w.name, x = x, y = y, w = w.def.size[1], h = w.def.size[2] }
      end
    end
  end
  for i = 1, #boxes do
    local a = boxes[i]
    local right_pane = a.x >= WK.RIGHT_X - 1 and not a.name:find("^btn_enemies") and not a.name:find("^btn_face") and a.name ~= "btn_help"
    local header = a.name == "btn_enemies" or a.name == "btn_face" or a.name == "btn_help"
    if a.x < 0 or a.y < 0 or a.x + a.w > 1920 or a.y + a.h > WK.BOTTOM then problems[#problems + 1] = a.name .. " off the screen" end
    if not header and not right_pane and a.x + a.w > WK.LEFT_X + WK.LEFT_W + 0.5 then problems[#problems + 1] = a.name .. " past the left pane" end
    if right_pane and a.x + a.w > WK.RIGHT_X + WK.RIGHT_W + 0.5 then problems[#problems + 1] = a.name .. " past the right pane" end
    for j = i + 1, #boxes do
      local b = boxes[j]
      if a.x < b.x + b.w - 1e-6 and b.x < a.x + a.w - 1e-6 and a.y < b.y + b.h - 1e-6 and b.y < a.y + a.h - 1e-6 then problems[#problems + 1] = a.name .. "/" .. b.name end
    end
  end
  check("layout: on the Cauldron no clickable widget lies on another, the left pane stops at x 1240, the right pane starts at 1290, nothing goes below y 1014", #problems == 0 and #boxes > 60, #boxes .. " widgets: " .. table.concat(problems, ", "))

  -- the shelf adds enemies, and the card follows
  local before = #view._parts
  click_chip("chaos_hound")
  check("shelf: a click on Hound adds a group of one; the row, the card on the stage and the line under it follow", #view._parts == before + 1 and view._parts[#view._parts].breed == "chaos_hound" and view._parts[#view._parts].count == 1 and plain_lines(stage):find("tile_more:2", 1, true) ~= nil and W.stage_stats.content.stage_stats:find("^stage_stats:3,10,") ~= nil and settings.wave_def_custom_1:find("1 hound", 1, true) ~= nil, W.stage_stats.content.stage_stats)
  check("shelf: the chip is lit now that the card has that enemy; the others are not", W["rw_chip_" .. chip_of("chaos_hound")].content.hotspot_on == true and W["rw_chip_" .. chip_of("chaos_spawn")].content.hotspot_on == false)
  click_chip("chaos_hound")
  check("shelf: a second click makes it two in the same group (no new row)", #view._parts == before + 1 and view._parts[#view._parts].count == 2 and plain_lines(stage):find("tile_more:2", 1, true) ~= nil)
  check("shelf: the new group is on the screen (the list scrolled to its last row), the range says 2 - 5 of 5", view._offset == 0 and W.rw_erow_5.visible and plain(W.rw_erow_5.content.row_name) == "2 Hound" and W.list_range.content.list_range == "list_range:1,5,5", W.list_range.content.list_range)

  -- Dreg or Scab
  check("faction: the switch starts on Scab (renegades) and shows it; the chips have no S or D tag but a tint: steel grey over black for the Scab ones, putrid yellow-green for the Dreg Mutant, none for Chaos units", view._faction == "scab" and W.btn_scab.content.hotspot_on == true and W.btn_dreg.content.hotspot_on == false and W["rw_chip_" .. chip_of("Gunner")].content.tint.frame[1] == 82 and W["rw_chip_" .. chip_of("cultist_mutant")].content.tint.frame[1] == 104 and W["rw_chip_" .. chip_of("chaos_poxwalker")].content.tint == false and W["rw_chip_" .. chip_of("Gunner")].content.chip_tag == nil)
  do
    local gun, pox = W["rw_chip_" .. chip_of("Gunner")], W["rw_chip_" .. chip_of("chaos_poxwalker")]
    local function fill(w) local pass = pass_by_style(w, "chip_fill"); pass.change_function(w.content, w.style.chip_fill); local c = w.style.chip_fill.color; return { c[2], c[3], c[4] } end
    local function label(w) local pass = pass_by_style(w, "chip_label"); pass.change_function(w.content, w.style.chip_label); local c = w.style.chip_label.text_color; return { c[2], c[3], c[4] } end
    check("chips: a Scab chip is near black, a Dreg chip olive-dark, a neutral one the button plate; hovering lights it", fill(gun)[1] < 30 and fill(gun)[3] > fill(gun)[1] and (function() local dreg = W["rw_chip_" .. chip_of("cultist_mutant")]; local f = fill(dreg); return f[2] > f[3] + 15 end)() and fill(pox)[1] == 22 and (function() gun.content.hotspot.is_hover = true; local f = fill(gun); gun.content.hotspot.is_hover = false; return f[1] > 30 end)())
    check("chips: the label of a Scab chip is steel grey, of a Dreg chip putrid yellow (its lit brighter form here: the card has a mutant), of a neutral chip the bone text colour", label(W["rw_chip_" .. chip_of("renegade_executor")])[1] == 170 and label(W["rw_chip_" .. chip_of("renegade_executor")])[3] == 184 and label(W["rw_chip_" .. chip_of("cultist_mutant")])[1] == 238 and label(pox)[1] == 230, table.concat(label(W["rw_chip_" .. chip_of("renegade_executor")]), ",") .. "|" .. table.concat(label(W["rw_chip_" .. chip_of("cultist_mutant")]), ",") .. "|" .. table.concat(label(pox), ","))
    check("chips: the label box is wider than the chip and left aligned, so a label wider than guessed never breaks in two lines", gun.style.chip_label.size[1] >= 2 * (gun.style.hotspot.size[1] - 14) and gun.style.chip_label.text_horizontal_alignment == "left")
    check("chips: a chip is wide enough for its word with the real bold sans (Hound is 3.05 em at 16: 49 units), with the dot before and a margin after", WK.chip_width("Hound") >= WK.CHIP_DOT + 49 + 8 and WK.chip_width("Armored Hound") > WK.chip_width("Hound"))
  end
  click_chip("Gunner")
  check("faction: with Scab chosen the Gunner chip adds the Scab gunner (renegade_gunner), the row says Scab", view._parts[#view._parts].breed == "renegade_gunner" and plain(W["rw_erow_" .. math.min(#view._parts, WK.ROWS)].content.row_name) == "1 Gunner  Scab", view._parts[#view._parts].breed)
  W.btn_dreg.content.hotspot.pressed_callback()
  check("faction: the switch to Dreg is kept in the settings; the chips of the pairs turn Dreg-coloured; the single-faction chips keep theirs", view._faction == "dreg" and settings.shelf_faction == "dreg" and W.btn_dreg.content.hotspot_on == true and W.btn_scab.content.hotspot_on == false and W["rw_chip_" .. chip_of("Gunner")].content.tint.frame[1] == 104 and W["rw_chip_" .. chip_of("renegade_executor")].content.tint.frame[1] == 82)
  click_chip("Gunner")
  check("faction: with Dreg chosen the same chip adds the Dreg gunner, in its own group, and says Dreg Gunner", view._parts[#view._parts].breed == "cultist_gunner" and view._parts[#view._parts - 1].breed == "renegade_gunner", view._parts[#view._parts].breed)
  local count_before = #view._parts
  click_chip("renegade_executor")
  check("faction: a Mauler (Scab only) is added whatever the switch says", view._parts[#view._parts].breed == "renegade_executor" and #view._parts == count_before + 1)
  click_chip("Vanguard")
  check("shelf: the Vanguard is fodder and follows the switch (Dreg now: cultist_vanguard); the Packmaster is on the shelf among the bosses", view._parts[#view._parts].breed == "cultist_vanguard" and chips[chip_of("chaos_ogryn_houndmaster")].group == 4 and chips[chip_of("Vanguard")].group == 1)
  click_chip("chaos_ogryn_houndmaster")
  check("shelf: the Packmaster adds chaos_ogryn_houndmaster", view._parts[#view._parts].breed == "chaos_ogryn_houndmaster" and #view._parts == 10)
  click_chip("chaos_spawn"); click_chip("chaos_beast_of_nurgle")
  check("shelf: twelve groups are the most a card holds: the thirteenth is refused with a message, nothing changes", #view._parts == 12 and (function() local n = #view._parts; click_chip("chaos_daemonhost"); return #view._parts == n and echoes[#echoes]:find("msg_max_groups", 1, true) ~= nil end)(), tostring(#view._parts))
  W.btn_scab.content.hotspot.pressed_callback()
  check("scroll: with twelve groups the rows scroll one at a time, the last row is the last group, the range is right", view._offset == 6 and plain(W.rw_erow_6.content.row_name):find("Beast of Nurgle", 1, true) ~= nil and W.list_range.content.list_range == "list_range:7,12,12" and W.rw_scroll_down.content.hotspot.disabled == true and W.rw_scroll_up.content.hotspot.disabled == false, tostring(view._offset) .. " " .. W.list_range.content.list_range)
  click("rw_scroll_up")
  check("scroll: the up button moves one row, not ten", view._offset == 5 and plain(W.rw_erow_1.content.row_name):find("^1 Chaos Spawn") == nil)
  view._offset = 0; view:_refresh_rows(); view:_set_interaction_enabled()
  click_row(1, "hotspot_action")
  check("rows: Remove takes a group out; the card follows", #view._parts == 11 and plain_lines(stage):find("3 Trapper", 1, true) == nil)
  while #view._parts > 4 do table.remove(view._parts); end
  view:_save()
  check("rows: with four groups again, four rows show", W.rw_erow_4.visible and not W.rw_erow_5.visible and view._offset == 0)
  -- (the first group was removed above: the card is now Flamer, Mutant, Tox Flamer, Hound)

  -- the suits
  click("rw_suit_3") -- rage is the third of the twelve
  check("suit: a click on Rage makes it the card's suit (saved), the stage card, the plate and the buttons turn rust", settings.su_custom_1 == "rage" and stage.content.suit_label == "RAGE" and W.stage_plate.content.stage.accent[1] == 0xc2 and mod.rw_accent[1] == 0xc2 and mod.rw_accent[2] == 0x7a)
  local selected = {}
  for i = 1, 12 do if W["rw_suit_" .. i].content.selected then selected[#selected + 1] = i end end
  check("suit: exactly one tile is selected (Rage, the third), and it stands 4 units higher than its neighbours", #selected == 1 and selected[1] == 3 and view._sg.rw_suit_3[2] == select(2, WK.suit_pos(3)) - 4 and view._sg.rw_suit_4[2] == select(2, WK.suit_pos(4)))
  check("suit: every tile carries its own colours and name, the mark is painted (Rage: a flame of triangles and circles)", W.rw_suit_3.content.suit_name == "RAGE" and W.rw_suit_3.content.suit.accent[1] == 0xc2 and W.rw_suit_1.content.suit.accent[1] == 0xb7 and W.rw_suit_11.content.suit_name == "WARP" and W.rw_suit_12.content.suit_name == "HERESY" and W.rw_suit_3.style.icon_c1.visible and W.rw_suit_3.style.icon_ch1.visible and W.rw_suit_1.style.icon_c1.visible)
  check("suit: the hint diamond marks the suit the enemies suggest (specials: Blight) when it is not the card's own suit", W.rw_suit_4.content.suggested == true and W.rw_suit_3.content.suggested == false)
  click("rw_suit_4")
  check("suit: choosing the suggested suit takes the hint away (it is the card's own now)", settings.su_custom_1 == "blight" and W.rw_suit_4.content.selected == true and W.rw_suit_4.content.suggested == false)

  -- threat
  check("threat: auto at first: the diamonds show the worked-out value, Auto is selected", W.rw_threat.content.threat >= 1 and W.btn_thr_auto.content.hotspot_on == true and W.btn_thr_hand.content.hotspot_on == false)
  local auto_value = W.rw_threat.content.threat
  W.rw_threat.content.hotspot_t5.pressed_callback()
  check("threat: a click on the fifth diamond sets five by hand: saved, shown on the card, By hand is selected", settings.th_custom_1 == 5 and W.rw_threat.content.threat == 5 and W.btn_thr_hand.content.hotspot_on == true and W.btn_thr_auto.content.hotspot_on == false and stage.style.th_o5.color[1] == 255)
  W.btn_thr_auto.content.hotspot.pressed_callback()
  check("threat: Auto works it out again", settings.th_custom_1 == 0 and W.rw_threat.content.threat == auto_value and W.btn_thr_auto.content.hotspot_on == true)
  W.btn_thr_hand.content.hotspot.pressed_callback()
  check("threat: By hand keeps the value that shows now (nothing jumps)", settings.th_custom_1 == auto_value and W.rw_threat.content.threat == auto_value and W.btn_thr_hand.content.hotspot_on == true)
  W.btn_thr_auto.content.hotspot.pressed_callback()

  -- the chance and the toolbar
  local pct = settings.pct_custom_1
  click("stepper_chance", "hotspot_minus")
  check("chance: the stepper under the card changes the chance by one and the line under the card says the share", settings.pct_custom_1 == pct - 1 and W.stepper_chance.content.stepper_value == tostring(pct - 1) and W.stepper_chance.content.extra:find("^extra_share:") ~= nil)
  click("stepper_chance", "hotspot_plus")
  click("stepper_chance", "hotspot_plus")
  check("chance: 10 is the most: plus at 10 stays at 10 (the setting and the number shown)", settings.pct_custom_1 == 10 and W.stepper_chance.content.stepper_value == "10", tostring(settings.pct_custom_1))
  settings.pct_custom_1 = 0; view:_reload(); view:_apply_screen()
  click("stepper_chance", "hotspot_minus")
  check("chance: 0 is the least (never drawn): minus at 0 stays at 0", settings.pct_custom_1 == 0 and W.stepper_chance.content.stepper_value == "0", tostring(settings.pct_custom_1))
  settings.pct_custom_1 = pct; view:_reload(); view:_apply_screen()

  -- the roll switch: only a card with a random group shows it
  check("roll switch: a card without a random group does not show it", not W.btn_keep_pick.visible)
  local saved_def = settings.wave_def_custom_1
  settings.wave_def_custom_1 = "The Magician	3 trapper, 1 hound|mutant@2"
  view:_open_detail("custom_1")
  check("roll switch: with a random group it shows, on by default, with its label", W.btn_keep_pick.visible and W.btn_keep_pick.content.hotspot_on == true and W.btn_keep_pick.content.hotspot_text == "btn_keep_pick_on")
  W.btn_keep_pick.content.hotspot.pressed_callback()
  check("roll switch: a click turns it off (rk_ false), the label follows", settings.rk_custom_1 == false and W.btn_keep_pick.content.hotspot_on == false and W.btn_keep_pick.content.hotspot_text == "btn_keep_pick_off")
  W.btn_keep_pick.content.hotspot.pressed_callback()
  check("roll switch: and on again", settings.rk_custom_1 == true and W.btn_keep_pick.content.hotspot_on == true)
  check("roll switch: it sits on the line of 'How it spawns', inside the pane, clear of the steppers", (function()
    local n = view._definitions.scenegraph_definition.btn_keep_pick.position
    return n[1] + 360 <= WK.LEFT_X + WK.LEFT_W and n[2] + 30 <= view._definitions.under_shelf.row_y[1] and n[2] >= view._definitions.under_shelf.label_y - 12
  end)())
  settings.wave_def_custom_1 = saved_def; settings.rk_custom_1 = nil
  view:_open_detail("custom_1")

  -- the card on the stage: its name renames, its line opens the whisper box (and are underlined under the pointer)
  do
    local st = view._widgets_by_name.rw_stage_card
    local hn, hw = st.style.hotspot_name, st.style.hotspot_whisper
    check("stage: the name and the line in quotes are click areas inside the card, the name above the line, one to three lines of name high", hn.size[1] > 100 and hn.size[2] >= 24 * 1.4 - 1e-6 and hn.size[2] <= 3 * 24 * 1.4 + 1e-6 and hw.size[2] > 20 and hn.offset[2] + hn.size[2] <= hw.offset[2] and hw.offset[2] + hw.size[2] <= st.content.metrics.h)
    check("stage: the Deck's click areas of the card stay off (it is not a button)", (function() for _, id in ipairs(view.TILE_HOTSPOTS) do if st.content[id].disabled ~= true then return false end end return true end)())
    st.content.hotspot_name.is_hover = true
    local ul = pass_by_style(st, "name_ul")
    check("stage: under the pointer the name is underlined in the suit's accent, the line is not", ul.visibility_function(st.content, st.style.name_ul) == true and pass_by_style(st, "whisper_ul").visibility_function(st.content, st.style.whisper_ul) == false and st.style.name_ul.color[2] == st.style.suit_label.text_color[2])
    st.content.hotspot_name.is_hover = false
    st.content.hotspot_name.pressed_callback()
    check("stage: a click on the name opens the rename box with the card's name", view._popup ~= nil and view._popup.spec.label == "popup_rename_title" and view._popup.spec.value == view._wave.name, tostring(view._popup and view._popup.spec.label))
    check("stage: while a box is open the name and the line cannot be clicked", st.content.hotspot_name.disabled == true and st.content.hotspot_whisper.disabled == true)
    view:cb_popup_cancel()
    check("stage: and they can again afterwards", st.content.hotspot_name.disabled == false and st.content.hotspot_whisper.disabled == false)
    st.content.hotspot_whisper.pressed_callback()
    check("stage: a click on the line in quotes opens the whisper box", view._popup ~= nil and view._popup.spec.label:find("popup_whisper_title") == 1, tostring(view._popup and view._popup.spec.label))
    view:cb_popup_cancel()
    -- the plate: a ground tinted with the suit, and rings of its accent around the card that get brighter toward the card
    do
      local plate = view._widgets_by_name.stage_plate
      local function colour(id)
        local pass = pass_by_style(plate, id)
        pass.change_function(plate.content, plate.style[id])
        local c = plate.style[id].color
        return { c[2], c[3], c[4] }, c[1]
      end
      local ground = colour("plate_fill")
      local suit = mod.rw.cards.Cards_unused or mod.rw.cards.SUITS.blight
      local accent = suit.accent
      local last, brighter, all_visible = ground, true, true
      for i = 1, #WK.STAGE_RINGS do
        local disc = colour("ring_d" .. i)
        if disc[1] + disc[2] + disc[3] <= last[1] + last[2] + last[3] then brighter = false end
        last = disc
      end
      local _, alpha_l = colour("ring_l1")
      local line1, line_alpha = colour("ring_l1")
      local disc1 = colour("ring_d1")
      check("stage: the plate is tinted with the suit (blight: its frame colour mixed into the ground, not the flat ground)", ground[1] > 10 + 8 and ground[2] > 12 + 8)
      check("stage: the rings are opaque discs of the suit's accent, each brighter than the one outside it and than the plate", brighter and #WK.STAGE_RINGS >= 4)
      check("stage: the outer ring has a line of the accent on its edge, brighter than the disc inside it, and a faint copy under it", line1[1] > disc1[1] and line1[2] > disc1[2] and line_alpha == 255 and (function() local _, a = colour("ring_h1"); return a == 90 end)())
      local big = WK.STAGE_RINGS[1][1]
      check("stage: the biggest ring stays inside the plate (it is not clipped, the caption above would be drawn over)", (22 + 270 * WK.CARD_SCALE / 2) - big >= 0 and (22 + 270 * WK.CARD_SCALE / 2) + big <= WK.PLATE.h and WK.PLATE.w / 2 - big >= 0)
    end
    click("btn_face")
    check("stage: the same card on the Mirror has the same two click areas", view._widgets_by_name.rw_stage_card.content.hotspot_name.disabled == false and view._widgets_by_name.rw_stage_card.style.hotspot_name.size[1] > 100)
    click("btn_enemies")
  end
  click("btn_enabled")
  check("toolbar: In the draw switches the card out of the draw: the stage card dims, the line says so; and back", settings.on_custom_1 == false and stage.alpha_multiplier == 0.55 and W.btn_enabled.content.hotspot_text == "btn_enabled_off" and W.stage_stats.content.stage_stats == "stage_stats_off")
  click("btn_enabled")
  check("toolbar: ...and back in the draw: full colour again", settings.on_custom_1 == true and stage.alpha_multiplier == 1 and W.btn_enabled.content.hotspot_text == "btn_enabled_on")

  -- the cooldown preview plays the card's look through in five seconds and then paints the card again
  click("btn_preview")
  check("preview: Preview cooldown starts it", view._preview ~= nil and view._preview.t == 0)
  view:update(2.5, 100, inp)
  local mid = stage.content.fx.p
  check("preview: half way through, the look is half way (rot: the colour has left the accent)", mid > 0.45 and mid < 0.55 and view._preview ~= nil, mid)
  view:update(3, 103, inp)
  check("preview: after five seconds it is over and the card is painted as before", view._preview == nil and stage.content.fx.p == -1 and stage.alpha_multiplier == 1)
  settings.cl_custom_1 = "whisper"; view:_reload(); view:_apply_screen(true)
  click("btn_preview"); view:update(2.5, 110, inp)
  check("preview: the murmur look writes the whisper letter by letter and fades the card", stage.content.whisper:find("^\"") ~= nil and #stage.content.whisper < #("\"" .. stage.content.fx.whisper .. "\"") and stage.alpha_multiplier < 1)
  view:update(3, 113, inp)
  settings.cl_custom_1 = "vial"; view:_reload(); view:_apply_screen(true)
  click("btn_preview"); view:update(2.5, 120, inp)
  check("preview: the vial look fills half the card (a liquid with a bright top line)", stage.style.vial.visible and near(stage.style.vial.size[2], 378 * 0.5) and stage.style.vial_line.visible)
  view:update(3, 123, inp)
  settings.cl_custom_1 = nil; view:_reload(); view:_apply_screen(true)

  -- a popup locks the screen's hotspots, closing it unlocks them
  click("btn_rename")
  check("popup: while a box is open the chips, suit tiles, threat diamonds and rows cannot be clicked", W["rw_chip_1"].content.hotspot.disabled == true and W.rw_suit_1.content.hotspot.disabled == true and W.rw_threat.content.hotspot_t1.disabled == true and W.rw_erow_1.content.hotspot_plus.disabled == true)
  PP_.Popup.cancel(view)
  check("popup: ...and they work again after it", W["rw_chip_1"].content.hotspot.disabled == false and W.rw_suit_1.content.hotspot.disabled == false and W.rw_threat.content.hotspot_t1.disabled == false and W.rw_erow_1.content.hotspot_plus.disabled == false)

  -- the tabs
  click("btn_face")
  check("tabs: Face opens the card's face screen (the Mirror) and the Enemies tab is the way back; nothing of the Cauldron stays", view._screen == "face" and W.btn_enemies.visible and W.btn_face.content.hotspot_on == true and W.rw_stage_card.visible and W.btn_preview.visible and W.rw_plate_1.visible and not W.shelf_panel.visible and not W.rw_erow_1.visible and not W.btn_dreg.visible and not W.rw_threat.visible and not W["rw_chip_1"].visible)
  click("btn_enemies")
  check("tabs: Enemies is back on the Cauldron with everything as it was", view._screen == "detail" and W.shelf_panel.visible and W.rw_stage_card.visible and W.btn_enemies.content.hotspot_on == true and W.rw_erow_1.visible)
  click("btn_quickface")
  check("tabs: Whisper and cooldown (the quiet button under the card) opens the face screen too", view._screen == "face")
  click("btn_enemies")

  -- leaving the Cauldron
  view:cb_back()
  check("leaving: the Deck is back, the Cauldron's widgets are hidden and the buttons are bile again", view._screen == "list" and not W.shelf_panel.visible and not W.rw_stage_card.visible and not W.rw_threat.visible and not W["rw_chip_1"].visible and not W.rw_suit_1.visible and mod.rw_accent[1] == 183)
  settings.wave_def_custom_1 = nil; settings.on_custom_1 = nil; settings.su_custom_1 = nil; settings.th_custom_1 = nil; settings.pct_custom_1 = nil; settings.shelf_faction = nil
  view._faction = "scab"
  view:_reload(); view:_apply_screen()
end

-- Persistent Deck order and the actual hold/release path, including cancellation and stale hotspot releases.
do
  local saved_settings = table.clone(settings)
  local DM, Events = dofile(BASE .. "/ui/deck.lua"), mod.rw.events
  local PP = dofile(BASE .. "/ui/wave_editor_components.lua").Popup
  local function reset_deck()
    PP.cancel(view)
    for k in pairs(settings) do settings[k] = nil end
    mod.rw.director = nil
    view._screen = "list"; view._key = nil; view._offset = 0
    view:_reload(); view:_apply_screen()
  end
  reset_deck()
  local keys = Events.keys()
  settings.deck_order = keys[3] .. ",missing," .. keys[3] .. "," .. keys[1]
  local recovered = Events.ordered_keys(function(id) return settings[id] end)
  local seen, complete = {}, #recovered == #keys
  for _, k in ipairs(recovered) do if seen[k] then complete = false end; seen[k] = true end
  check("order: duplicates and deleted keys are ignored; missing/new cards are appended once", complete and recovered[1] == keys[3] and recovered[2] == keys[1])
  settings.deck_order = 42
  check("order: a damaged non-string setting restores the default order", table.concat(Events.ordered_keys(function(id) return settings[id] end), ",") == table.concat(keys, ","))
  settings.deck_order = nil
  local original_pool = mod.rw.events.build_pool(function(id) return settings[id] end, mod.rw.groups)
  local items = {
    {key="a", threat=2, chance=3, enemies=8, suit=12},
    {key="b", threat=1, chance=7, enemies=3, suit=1},
    {key="c", threat=2, chance=3, enemies=8, suit=12},
  }
  for _, mode in ipairs(DM.SORTS) do
    local field = ({ threat="threat", rarity="chance", enemies="enemies", face="suit" })[mode]
    for _, desc in ipairs({false, true}) do
      local sorted = DM.sorted(items, mode, desc)
      local ordered = true
      for i=2,#sorted do if (not desc and sorted[i-1][field] > sorted[i][field]) or (desc and sorted[i-1][field] < sorted[i][field]) then ordered=false end end
      local a,c
      for i,item in ipairs(sorted) do if item.key=="a" then a=i elseif item.key=="c" then c=i end end
      check("sort: " .. mode .. (desc and " descending" or " ascending") .. " is stable and leaves input alone", ordered and a<c and items[1].key=="a")
    end
    reset_deck()
    view:cb_sort(mode)
    check("sort button: " .. mode .. " stores the order and lights only on the Deck", settings.deck_sort==mode and settings.deck_sort_desc==false and tile(1).visible and D["btn_sort_"..mode].content.hotspot_on)
    view:cb_sort(mode)
    check("sort button: a second " .. mode .. " click reverses the direction", settings.deck_sort_desc==true)
  end
  local sorted_pool = mod.rw.events.build_pool(function(id) return settings[id] end, mod.rw.groups)
  local unchanged = #original_pool == #sorted_pool
  for i=1,#original_pool do if original_pool[i].key~=sorted_pool[i].key or original_pool[i].raw~=sorted_pool[i].raw then unchanged=false end end
  check("sort: visual order never changes the director's weights or its default pool ordering", unchanged)
  local saved_order = settings.deck_order
  view:_reload()
  check("order: a reload reads the saved order", view._deck[1].key == settings.deck_order:match("[^,]+"))
  view:cb_sort("bad mode")
  check("sort: an invalid mode does not overwrite the saved order", settings.deck_order==saved_order)

  reset_deck()
  local cursor, held = {146,210}, false
  local inp = {get=function(self,id) if id=="cursor" then return cursor elseif id=="left_hold" then return held end end, is_null_service=function() return false end}
  local function step(dt) view:update(dt or 0.016, 0, inp) end
  local function point(slot)
    local x,y=DM.tile_pos(slot); cursor[1],cursor[2]=x+20,y+20
  end
  local function lift(slot)
    point(slot); held=false; step()
    tile(slot).content.hotspot_top.pressed_callback()
    held=true; step(DM.DRAG_HOLD+0.01)
    check("drag: an actual face press held for the threshold lifts a card", view._drag and view._drag.slot==slot)
  end
  local function order() return table.concat(Events.ordered_keys(function(id) return settings[id] end), ",") end
  local before, a, b = order(), view._deck[1].key, view._deck[2].key
  lift(1); point(2); step(); held=false; step()
  tile(2).content.hotspot_top.released_callback()
  check("drag: dropping swaps just the two cards, persists, and never toggles them", view._deck[1].key==b and view._deck[2].key==a and settings.deck_order~=nil and settings["on_"..a]==nil and settings["on_"..b]==nil and view._drag==nil)
  check("drag: a manual swap clears the selected sort", settings.deck_sort=="" and settings.deck_sort_desc==false)
  before=order(); lift(1); point(2); step(); cursor[1],cursor[2]=1900,1000; held=false; step()
  check("drag: dropping outside the grid after hovering a target cancels, keeping the order", order()==before and view._drag==nil)
  local pos=view._sg.rw_tile_1
  check("drag: cancellation restores the card position and layer", pos[1]==126 and pos[2]==190 and pos[3]==3)
  before=order(); lift(1); point(2); step(); cursor=nil; step()
  check("drag: losing the cursor cancels without using the last hovered target", view._drag==nil and order()==before)
  cursor={146,210}; held=false; step()
  lift(1); point(2); step(); PP.open(view,{label="x",value="",set=function() end})
  step()
  check("drag: opening a popup cancels and restores dimmed targets", view._drag==nil and view._press==nil and tile(2).alpha_multiplier==1)
  PP.cancel(view)
  lift(1); tile(1).content.hotspot_top.right_pressed_callback()
  check("drag: right click switches to the card screen and cancels the drag", view._screen=="detail" and view._drag==nil and view._press==nil)
  view:cb_back(); held=false; step()
  before=order(); lift(1); view:cb_sort("threat")
  check("drag: sorting during a drag cancels it before reusing tile slots", view._drag==nil and settings.deck_sort=="threat")
  reset_deck(); held=false; step()
  for i=1,20 do settings["wave_def_custom_"..i]="Extra "..i.."\t1 hound" end
  view:_reload(); view:_apply_screen()
  before=order(); lift(1); point(2); step(); view:cb_scroll(1)
  held=false; step(); tile(1).content.hotspot_top.released_callback()
  check("drag: scrolling cancels before the visible slots acquire different cards", view._offset>0 and view._drag==nil and order()==before and settings.on_wave_small==nil)
  reset_deck(); held=false; step()
  tile(1).content.hotspot_top.released_callback()
  check("click: an unarmed release cannot toggle a card", settings.on_wave_small==nil)
  tile(1).content.hotspot_top.pressed_callback(); held=false; step(); tile(1).content.hotspot_top.released_callback()
  check("click: a quick press/release toggles once despite update preceding the release callback", settings.on_wave_small==false)
  tile(1).content.hotspot_top.double_click_callback(); step(); tile(1).content.hotspot_top.released_callback()
  check("click: the double-click release leaves the first toggle intact", settings.on_wave_small==false)
  view._render_settings={inverse_scale=0.5}; cursor={292,420}
  local x,y=view:_cursor_point(inp)
  check("drag: cursor coordinates follow UI scaling", x==146 and y==210)
  view._render_settings=nil; reset_deck(); held=false
  lift(1); view:on_exit()
  check("drag: closing the editor discards the drag and armed press", view._drag==nil and view._press==nil)
  reset_deck(); held=false; cursor={1900,1000}
  -- Keep coverage collector allocations out of the heap measurement.
  local hook, mask, count = debug.gethook()
  debug.sethook()
  local jit_was_on = jit and jit.status()
  if jit then jit.off(); jit.flush() end
  for i=1,100 do step() end
  collectgarbage("collect"); collectgarbage("stop")
  local heap_before=collectgarbage("count"); local clock=os.clock()
  for i=1,2000 do step() end
  local seconds=os.clock()-clock
  local bytes=(collectgarbage("count")-heap_before)*1024/2000
  collectgarbage("restart"); if jit_was_on then jit.on() end
  if hook then debug.sethook(hook, mask, count) end
  check("deck: idle updates allocate under 1 byte/frame in the stubbed view", bytes<1,string.format("%.3f bytes/frame; %.3f ms/update (stubbed, interpreted)",bytes,seconds/2))
  for k in pairs(settings) do settings[k]=nil end
  for k,v in pairs(saved_settings) do settings[k]=v end
  view:on_enter()
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

-- DECK_DUMP=<file>: write the tiles of the Deck as JSON (tools/deck_preview.py draws them)
if DUMP and DUMP ~= "" then
  local function esc(s) return (tostring(s):gsub("[%c\"\\]", function(c) if c == "\n" then return "\\n" elseif c == "\"" then return "\\\"" elseif c == "\\" then return "\\\\" else return "" end end)) end
  local function ser(v)
    if type(v) == "table" then
      local parts = {}
      if #v > 0 or next(v) == nil then
        for i = 1, #v do parts[#parts + 1] = ser(v[i]) end
        return "[" .. table.concat(parts, ",") .. "]"
      end
      for k, x in pairs(v) do if type(x) ~= "function" and k ~= "parent" then parts[#parts + 1] = "\"" .. esc(k) .. "\":" .. ser(x) end end
      return "{" .. table.concat(parts, ",") .. "}"
    elseif type(v) == "string" then return "\"" .. esc(v) .. "\""
    elseif type(v) == "number" then return string.format("%.4f", v)
    elseif type(v) == "boolean" then return tostring(v) end
    return "null"
  end
  for i = 1, mod.rw.events.CUSTOM_SLOTS do settings["wave_def_custom_" .. i] = nil; settings["on_custom_" .. i] = nil end
  settings.on_wave_medium = false; settings.pct_boss_ambush = 2
  settings.wave_def_custom_1 = "The Pale Choir\t24 mauler, 3 crusher[enraged], 2 hound, 1 plague ogryn, 4 sniper"; settings.on_custom_1 = true; settings.su_custom_1 = "murmur"; settings.wh_custom_1 = "They were never quiet."; settings.pct_custom_1 = 8
  settings.wave_def_custom_2 = "The Host\t1 daemonhost, 6 poxwalker"; settings.on_custom_2 = true; settings.th_custom_2 = 4 -- warp by default
  -- the new suits and a two line name, so the preview shows them all
  settings.su_wave_huge = "volley"; settings.su_bomber_frenzy = "snare"; settings.su_hound_frenzy = "brute"; settings.su_special_pack = "heresy"; settings.su_sniper_elite = "dusk"
  settings.wave_def_special_pack = "The Magician Of Endless Plague\t"; settings.pct_wave_huge = 4; settings.pct_wave_small = 5
  settings.on_wave_medium = true; settings.cl_wave_medium = "whisper"
  local resting = { wave_large = 75, wave_medium = 90, grenade_legion = 100, hound_frenzy = 20 }
  mod.rw.director = { cooldown_remaining = function(key) return resting[key] or 0 end }
  view._screen = "list"; view._offset = 0; view:_reload(); view:_apply_screen()
  local tiles = {}
  local function dump_widget(w, x, y)
    local passes = {}
    for _, p in ipairs(w.def.passes) do
      local st = w.style[p.style_id]
      if st and st.visible ~= false then
        passes[#passes + 1] = { type = p.pass_type, id = p.style_id, style = st, text = p.value_id and w.content[p.value_id] or nil }
      elseif p.pass_type == "hotspot" and st then
        passes[#passes + 1] = { type = "hotspot", id = p.style_id, style = { offset = st.offset, size = st.size } }
      end
    end
    return { x = x, y = y, alpha = w.alpha_multiplier or 1, passes = passes }
  end
  for i = 1, 14 do
    local w = view._widgets_by_name["rw_tile_" .. i]
    if w and w.visible then tiles[#tiles + 1] = dump_widget(w, view._sg["rw_tile_" .. i][1], view._sg["rw_tile_" .. i][2]) end
  end
  local b = view._widgets_by_name.rw_tile_blank
  if b.visible then tiles[#tiles + 1] = dump_widget(b, view._sg.rw_tile_blank[1], view._sg.rw_tile_blank[2]) end
  local strip = dump_widget(view._widgets_by_name.rw_strip, 105, 144)
  local f = io.open(DUMP, "w")
  f:write(ser({ tiles = tiles, strip = strip, count = view._widgets_by_name.deck_count.content.deck_count, caption = view._widgets_by_name.deck_caption.content.deck_caption, hover = view._widgets_by_name.deck_hover.content.deck_hover }))
  f:close()
end

-- UI_DUMP_DIR=<dir>: write every screen of the editor as JSON (tools/ui_preview.py draws them into PNGs)
if UI_DIR and UI_DIR ~= "" then
  local DEFS = dofile(BASE .. "/ui/wave_editor_definitions.lua")
  -- UI_REAL_TEXT=1: the screens are drawn with the real English strings of the localization file (the tests use the ids), so the
  -- widths of the texts are the ones the player sees
  if UI_REAL and UI_REAL ~= "" then
    local LOC = dofile(BASE .. "/RealmsWaves_localization.lua")
    mod.localize = function(self, id, ...)
      local entry = LOC[id]
      local text = entry and entry.en or id
      local ok, result = pcall(string.format, text, ...)
      return ok and result or text
    end
  end
  local function esc(s) return (tostring(s):gsub("[%c\"\\]", function(c) if c == "\n" then return "\\n" elseif c == "\"" then return "\\\"" elseif c == "\\" then return "\\\\" else return "" end end)) end
  local function ser(v)
    if type(v) == "table" then
      local parts = {}
      if #v > 0 or next(v) == nil then
        for i = 1, #v do parts[#parts + 1] = ser(v[i]) end
        return "[" .. table.concat(parts, ",") .. "]"
      end
      for k, x in pairs(v) do if type(x) ~= "function" and k ~= "parent" then parts[#parts + 1] = "\"" .. esc(k) .. "\":" .. ser(x) end end
      return "{" .. table.concat(parts, ",") .. "}"
    elseif type(v) == "string" then return "\"" .. esc(v) .. "\""
    elseif type(v) == "number" then return string.format("%.4f", v)
    elseif type(v) == "boolean" then return tostring(v) end
    return "null"
  end
  local function dump_screen(name)
    local widgets = {}
    for _, w in ipairs(view._widgets) do
      if w.visible ~= false and w.def and w.name ~= "background" then
        local node_id = w.def.node_id or w.name
        local node = DEFS.scenegraph_definition[node_id]
        local pos = view._sg and view._sg[node_id] or (node and node.position) or { 0, 0, 0 }
        local nsize = node and node.size or { 1920, 1080 }
        local passes = {}
        for _, p in ipairs(w.def.passes) do
          local st = p.style_id and w.style[p.style_id] or p.style -- a pass without a style id uses its own style
          local vis = true
          if p.visibility_function then
            local pc = p.content_id and w.content[p.content_id] or w.content
            if p.content_id and not pc.parent then pc.parent = w.content end
            local ok, res = pcall(p.visibility_function, pc, st or {})
            vis = ok and res and true or false
          end
          if vis and p.pass_type ~= "hotspot" and st and st.visible ~= false then
            if p.change_function then
              local pc = p.content_id and w.content[p.content_id] or w.content
              pcall(p.change_function, pc, st)
            end
            local copy = {}
            for k, v in pairs(st) do copy[k] = v end
            if not copy.size then copy.size = { nsize[1], nsize[2] } end
            if p.pass_type == "text" and not copy.font_size then
              -- the stub of UIFontSettings has no header styles: the title is big, the line under it smaller
              copy.font_size = w.name == "title_text" and 54 or 22
              copy.font_type = w.name == "title_text" and "itc_novarese_bold" or "proxima_nova_bold"
              copy.text_vertical_alignment = "center"
            end
            passes[#passes + 1] = { type = p.pass_type, id = p.style_id, style = copy, text = p.value_id and w.content[p.value_id] or nil, value = p.value }
          end
        end
        -- every node is a child of the screen node (z 80): its layer is added to that
        widgets[#widgets + 1] = { name = w.name, x = pos[1], y = pos[2], z = 80 + (pos[3] or 0), alpha = w.alpha_multiplier or 1, passes = passes }
      end
    end
    local f = io.open(UI_DIR .. "/" .. name .. ".json", "w")
    f:write(ser({ name = name, widgets = widgets }))
    f:close()
  end
  local function hover(widget_name, hotspot_id, on) view._widgets_by_name[widget_name].content[hotspot_id or "hotspot"].is_hover = on end
  local sys_inp = { get = function() return nil end, is_null_service = function() return false end }

  for i = 1, mod.rw.events.CUSTOM_SLOTS do settings["wave_def_custom_" .. i] = nil; settings["on_custom_" .. i] = nil end
  settings.on_wave_medium = true; settings.pct_boss_ambush = 2; settings.pct_wave_small = 5; settings.pct_wave_huge = 4
  settings.wave_def_custom_1 = "The Magician\t3 trapper, 2 flamer, 2 mutant, 2 tox flamer"; settings.on_custom_1 = true; settings.su_custom_1 = "blight"; settings.pct_custom_1 = 6
  settings.wave_def_custom_2 = "Chips\t3 crusher[enraged]{health=150}, 2 hound, 12 poxwalker@3, 4 shocktrooper, 1 plague ogryn"; settings.on_custom_2 = true; settings.su_custom_2 = "rage"
  mod.rw.director = { cooldown_remaining = function() return 0 end }
  view._screen = "list"; view._key = nil; view._offset = 0; view:_reload(); view:_apply_screen()
  hover("btn_presets", "hotspot", true)
  dump_screen("deck")
  hover("btn_presets", "hotspot", false)
  view:_open_detail("custom_1")
  hover("btn_add", "hotspot", true)
  row(1).content.hotspot_name.is_hover = true
  dump_screen("detail")
  hover("btn_add", "hotspot", false); row(1).content.hotspot_name.is_hover = false
  view:_open_detail("custom_2")
  W2 = view._widgets_by_name
  W2.btn_delete.content.hotspot.is_hover = true; W2.btn_delete.content.hotspot.is_held = true
  row(2).content.hotspot_plus.is_hover = true
  dump_screen("detail2")
  W2.btn_delete.content.hotspot.is_hover = false; W2.btn_delete.content.hotspot.is_held = false; row(2).content.hotspot_plus.is_hover = false
  click("btn_add")
  dump_screen("picker")
  view:cb_back()
  click_row(1, "hotspot_mods")
  dump_screen("mods")
  view:cb_back()
  click("btn_face")
  dump_screen("face")
  view:cb_back()
  Popup_ = dofile(BASE .. "/ui/wave_editor_components.lua").Popup
  click("btn_rename")
  dump_screen("popup")
  Popup_.cancel(view)
  view:cb_back()
  click("btn_settings")
  dump_screen("settings")
  view:cb_back()
  click("btn_presets")
  dump_screen("presets")
  view:cb_back()
end

return table.concat(results, "\n")
'''
out = lua.execute(harness, MODROOT, os.environ.get("DECK_DUMP", ""), os.environ.get("UI_DUMP_DIR", "").replace("\\", "/"), os.environ.get("UI_REAL_TEXT", ""))
print(out)
fails = [l for l in out.split("\n") if l.startswith("FAIL")]
print("\nPASS:", len([l for l in out.split("\n") if l.startswith("PASS")]), "FAIL:", len(fails))
sys.exit(1 if fails else 0)
