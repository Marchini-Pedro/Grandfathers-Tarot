"""Drives the real wave HUD (ui/spread.lua, the widget definitions, hud_element_waves.lua) against stubbed engine classes.

Not a substitute for the game: nothing is drawn. It executes every code path of the Spread (deal, roulette, reveal, rot,
late join, legacy panel, custom_hud sample) and audits, after every step, that each pass the engine would draw has the
numbers it needs (no nil, no NaN, sane positions) and that nothing allocates per frame.
Run:  python tools/hud_test.py   (needs `lupa`, see CLAUDE.md)
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
function math.clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
unpack = unpack or table.unpack

-- Mirrors UIWidget.add_definition_pass / UIWidget.init (scripts/managers/ui/ui_widget.lua:31-238)
local DEFAULT_STYLE = {
  rect = { color = { 255, 255, 255, 255 }, offset = { 0, 0, 0 } },
  circle = { color = { 255, 255, 255, 255 }, offset = { 0, 0, 0 } },
  triangle = { color = { 255, 255, 255, 255 }, offset = { 0, 0, 0 } },
  rotated_rect = { angle = 0, color = { 255, 255, 255, 255 }, offset = { 0, 0, 0 }, pivot = {} },
}
local UIWidget = {}
UIWidget.create_definition = function(passes, scenegraph_id, content_overrides, size)
  local def = { passes = {}, content = {}, style = {}, scenegraph_id = scenegraph_id, size = size }
  for i, p in ipairs(passes) do
    local style_id = p.style_id or ("style_id_" .. i)
    local default = DEFAULT_STYLE[p.pass_type]
    local st = p.style
    if default then
      st = table.clone(default)
      for k, v in pairs(p.style or {}) do st[k] = v end
    end
    def.style[style_id] = st
    if p.pass_type == "text" then def.content[p.value_id] = p.value or "" end
    def.passes[i] = { pass_type = p.pass_type, style_id = style_id, value_id = p.value_id }
  end
  return def
end
UIWidget.init = function(name, def)
  return { visible = true, name = name, passes = def.passes, content = table.clone(def.content), style = table.clone(def.style),
           scenegraph_id = def.scenegraph_id, offset = { 0, 0, 0 }, animations = {} }
end

local HudElementBase = {}
HudElementBase.__index = HudElementBase
HudElementBase.init = function(self, parent, draw_layer, start_scale, definitions)
  self._definitions = definitions
  self._widgets, self._widgets_by_name = {}, {}
  for name, def in pairs(definitions.widget_definitions) do
    local w = UIWidget.init(name, def)
    self._widgets[#self._widgets + 1] = w
    self._widgets_by_name[name] = w
  end
end
HudElementBase.update = function() end
function class(name, parent)
  local c = { __name = name }
  c.__index = c
  c.super = parent and HudElementBase or nil
  setmetatable(c, { __index = c.super })
  return c
end

local stubs = {
  ["scripts/managers/ui/ui_widget"] = UIWidget,
  ["scripts/settings/ui/ui_workspace_settings"] = { screen = { size = { 1920, 1080 }, position = { 0, 0, 0 } } },
}
local real_require = require
require = function(path) return stubs[path] or real_require(path) end

-- ---- mod stub ---------------------------------------------------------------
local settings, errors_logged = {}, {}
local customizing = false
local mod = {}
mod.get = function(self, id) return settings[id] end
mod.set = function(self, id, v) settings[id] = v end
mod.is_enabled = function() return true end
mod.error = function(self, fmt, ...) errors_logged[#errors_logged + 1] = string.format(fmt, ...) end
mod.localize = function(self, id, ...) local a = { ... } for i = 1, #a do a[i] = tostring(a[i]) end return id .. (#a > 0 and (":" .. table.concat(a, ",")) or "") end
mod.io_dofile = function(self, path) return dofile(MODROOT .. "/../" .. path .. ".lua") end
local custom_hud = { is_customizing = false }
get_mod = function(name) if name == "custom_hud" then return custom_hud end return mod end

local current_view = { phase = "off" }
mod.rw = {
  cards = dofile(BASE .. "/catalog/cards.lua"),
  colors = dofile(BASE .. "/catalog/colors.lua"),
  director = { view = function() return current_view end },
}
local Cards = mod.rw.cards

local results = {}
local function check(name, cond, detail) results[#results + 1] = (cond and "PASS " or "FAIL ") .. name .. (detail ~= nil and (" -- " .. tostring(detail)) or "") end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

local Definitions = dofile(BASE .. "/ui/hud_element_waves_definitions.lua")
local Spread = Definitions.Spread
local Element = dofile(BASE .. "/ui/hud_element_waves.lua")

-- ---- audit: what the engine would draw ------------------------------------
local function finite(v) return type(v) == "number" and v == v and v > -1e9 and v < 1e9 end
local function audit(el)
  local problems, drawn = {}, 0
  for name, w in pairs(el._widgets_by_name) do
    if w.visible then
      for _, p in ipairs(w.passes) do
        local st = w.style[p.style_id]
        if st.visible ~= false then
          drawn = drawn + 1
          local where = name .. "." .. p.style_id
          local t = p.pass_type
          local function num(label, v) if not finite(v) then problems[#problems + 1] = where .. " " .. label .. "=" .. tostring(v) end end
          num("offset1", st.offset and st.offset[1]); num("offset2", st.offset and st.offset[2]); num("offset3", st.offset and st.offset[3])
          if t == "rect" or t == "circle" or t == "rotated_rect" or t == "text" then
            num("size1", st.size and st.size[1]); num("size2", st.size and st.size[2])
            if st.size and (st.size[1] < 0 or st.size[2] < 0) then problems[#problems + 1] = where .. " negative size" end
          end
          if t == "triangle" then
            for k = 1, 3 do num("corner" .. k .. "x", st.triangle_corners[k][1]); num("corner" .. k .. "y", st.triangle_corners[k][2]) end
          end
          if t == "rotated_rect" then num("angle", st.angle); num("pivot1", st.pivot[1]); num("pivot2", st.pivot[2]) end
          local color = t == "text" and st.text_color or st.color
          for k = 1, 4 do
            if not finite(color[k]) or color[k] < 0 or color[k] > 255 then problems[#problems + 1] = where .. " color" .. k .. "=" .. tostring(color[k]) end
          end
          if t == "text" then
            if type(st.font_type) ~= "string" or not (st.font_size > 0) then problems[#problems + 1] = where .. " font" end
            if type(w.content[p.value_id]) ~= "string" then problems[#problems + 1] = where .. " text content" end
          end
          -- nothing wanders far outside the node (700 x 262): flies and drips may leave it a little
          if (t == "rect" or t == "circle") and st.offset and st.size then
            if st.offset[1] < -40 or st.offset[1] + st.size[1] > 740 or st.offset[2] < -60 or st.offset[2] + st.size[2] > 340 then
              problems[#problems + 1] = where .. " outside the node at " .. st.offset[1] .. "," .. st.offset[2] .. " size " .. st.size[1] .. "x" .. st.size[2]
            end
          end
        end
      end
    end
  end
  return problems, drawn
end
local function audit_ok(name, el)
  local problems, drawn = audit(el)
  check(name .. ": every drawn pass is well formed (" .. drawn .. " passes)", #problems == 0, table.concat(problems, " | "))
end

local function new_element()
  local el = setmetatable({}, Element)
  Element.init(el, nil, 0, 1)
  return el
end
local function frame(el, dt) Element.update(el, dt or 1 / 60, 0, nil, nil, nil) end

local function visible_cards(el)
  local n = 0
  for i = 1, 5 do if el._widgets_by_name["card_" .. i].visible then n = n + 1 end end
  return n
end
local function card(key, name, suit, threat, breeds, whisper, mods, rare, cooldown)
  return { key = key, name = name, suit = suit, threat = threat, breeds = breeds, whisper = whisper, modifiers = mods or "", rare = rare or false, cooldown = cooldown or 120 }
end
local function hand4()
  return {
    card("a", "The Multitude", "swarm", 3, { "chaos_poxwalker", "renegade_rifleman", "renegade_shocktrooper" }, "Too many to count."),
    card("b", "The Devil", "fateful", 5, { "chaos_beast_of_nurgle" }, "Something big is listening."),
    card("c", "The Tower", "blight", 3, { "chaos_poxwalker_bomber" }, "Pop, pop, pop."),
    card("d", "Death", "fateful", 5, { "renegade_shocktrooper", "chaos_ogryn_executor", "renegade_executor", "chaos_plague_ogryn" }, "It was always going to end here.", "Enraged", true, 300),
  }
end
local function view_of(fields)
  local v = { phase = "hand", mode = "tarot", remaining = 10, hand_seconds = 10, hand = hand4(), win = 3, hand_seq = 1, drawn = false, drawn_age = 0,
              version = 0, cands = {}, paused = false, empty = false, cooling = false }
  for k, x in pairs(fields or {}) do v[k] = x end
  return v
end

-- =====================================================================================================================
-- pure arithmetic (ui/spread.lua)
-- =====================================================================================================================
check("sizes: card width 176 up to three cards, 152 for four, 132 for five", Spread.card_width(1) == 176 and Spread.card_width(3) == 176 and Spread.card_width(4) == 152 and Spread.card_width(5) == 132)
check("wrap: a short name is one line", Spread.wrap_lines("Death", 80, 18) == 1)
check("wrap: a long name wraps (at most 3 lines)", Spread.wrap_lines("The Watching Moon", 80, 18) == 3 and Spread.wrap_lines("A very long name that goes on and on and on forever", 80, 18) == 3)
check("wrap: an overlong word is broken", Spread.wrap_lines("Supercalifragilisticexpialidocious", 80, 18) >= 3)

local layout = Spread.new_layout()
Spread.layout(layout, hand4())
check("layout: four cards are 152 wide, 8 px apart, centred in the 700 px node", layout.cw == 152 and layout.total_w == 632 and layout.x0 == 34 and layout.x[2] == 194 and layout.x[4] == 514)
check("layout: the minimum card height is 76", layout.ch == 76 and layout.fuse_y == Spread.CARDS_Y + 76 + Spread.FUSE_GAP)
Spread.layout(layout, { card("a", "The Watching Moon", "murmur", 3, {}, "") , card("b", "x", "rage", 1, {}, ""), card("c", "y", "rage", 1, {}, ""), card("d", "z", "rage", 1, {}, ""), card("e", "w", "rage", 1, {}, "") })
check("layout: five cards are 132 wide and the card grows with a three-line name", layout.cw == 132 and layout.total_w == 692 and layout.x0 == 4 and layout.lines == 3 and layout.ch == 97, layout.ch)
Spread.layout(layout, { card("a", "The Fool", "swarm", 1, {}, "") })
check("layout: one card is 176 wide and centred", layout.cw == 176 and layout.x0 == 262)
check("time text: always rounded up", Spread.time_text(65) == "1:05" and Spread.time_text(64.1) == "1:05" and Spread.time_text(0) == "0:00" and Spread.time_text(-3) == "0:00")

-- the roulette lands on the winner for every hand size and winner, and never goes backwards by more than a lap
local landed, monotone = true, true
for count = 2, 5 do
  for win = 1, count do
    if Spread.roulette_index(count, win, 1) ~= win then landed = false end
    local steps = 0
    local last = Spread.roulette_index(count, win, 0)
    for k = 1, 200 do
      local now = Spread.roulette_index(count, win, k / 200)
      if now ~= last then
        steps = steps + 1
        if now ~= last % count + 1 then monotone = false end -- one card at a time, always forward
        last = now
      end
    end
    if steps ~= 3 * count then monotone = false end
  end
end
check("roulette: lands on the winner for 2-5 cards and every winner", landed)
check("roulette: moves one card at a time, forward, 3 laps in all", monotone)
check("roulette: one card is always card 1", Spread.roulette_index(1, 1, 0.5) == 1)

local T = { roulette = 1.6, winner = 1.6, eye = 0.4, rot = 2 }
local tl = Spread.new_timeline()
local function tline(fields) return Spread.timeline(view_of(fields), T, tl) end
check("timeline: no hand = waiting", Spread.timeline({ phase = "waiting", remaining = 50 }, T, tl).stage == "waiting" and tl.count == 0)
check("timeline: a dealt hand burns its fuse", tline({ remaining = 7.5 }).stage == "hand" and near(tl.fuse, 0.75) and not tl.urgent)
check("timeline: the last 5 seconds are urgent", tline({ remaining = 4 }).urgent == true and tline({ remaining = 0 }).urgent == false)
check("timeline: the roulette starts 1.6 s before the pick", tline({ remaining = 1.7 }).stage == "hand" and tline({ remaining = 1.5 }).stage == "roulette" and tl.hi >= 1 and tl.hi <= 4)
check("timeline: the roulette has landed when the time is up", tline({ remaining = 0 }).stage == "roulette" and tl.hi == 3)
check("timeline: one card has no roulette", Spread.timeline(view_of({ remaining = 0.5, hand = { card("a", "The Fool", "swarm", 1, {}, "") }, win = 1 }), T, tl).stage == "hand")
check("timeline: a hand shorter than the roulette uses all of its time", Spread.timeline(view_of({ remaining = 0.9, hand_seconds = 1 }), T, tl).stage == "roulette")
check("timeline: reveal after the pick (winner shown 1.6 s), the eye opens in 0.4 s", tline({ drawn = true, phase = "waiting", drawn_age = 0.2 }).stage == "reveal" and near(tl.eye, 0.5) and tl.hi == 3 and near(tl.pop, 1))
check("timeline: the others fade to 28 percent", near(tline({ drawn = true, phase = "waiting", drawn_age = 0.35 }).lose, 0.28) and tline({ drawn = true, phase = "waiting", drawn_age = 0 }).lose == 1)
check("timeline: then the rot, for as long as asked", tline({ drawn = true, phase = "waiting", drawn_age = 2.6 }).stage == "rot" and near(tl.rot_p, 0.5) and near(tl.lose, 0))
check("timeline: then gone", tline({ drawn = true, phase = "waiting", drawn_age = 1.6 + 2 + 0.6 }).stage == "waiting" and tl.count == 0)

-- eye
local eye = Spread.new_shape(Spread.EYE_TRIS, Spread.EYE_CIRCS)
local pupil, lashes = Spread.eye(28, 0, eye)
check("eye: shut = a thin sliver with three lashes and no inside or pupil", eye.tri[1].on and eye.tri[2].on and not eye.tri[3].on and not eye.circ[1].on and eye.tri[5].on and eye.tri[6].on and eye.tri[7].on and lashes == 1 and pupil == 0)
pupil, lashes = Spread.eye(28, 1, eye)
check("eye: open = an outline (lens and inside) with a pupil and no lashes", eye.tri[1].on and eye.tri[3].on and eye.tri[4].on and eye.circ[1].on and not eye.tri[5].on and lashes == 0 and pupil == 1)
Spread.eye(28, 0.3, eye); local h_shut = eye.tri[1].y1
Spread.eye(28, 1, eye)
check("eye: the lens grows as it opens", eye.tri[1].y2 < h_shut and eye.tri[2].y3 > 14)
local fits = true
for _, size in ipairs({ 10, 28, 80 }) do
  for _, open in ipairs({ 0, 0.5, 1 }) do
    Spread.eye(size, open, eye)
    for _, t in ipairs(eye.tri) do
      if t.on then for _, v in ipairs({ t.x1, t.y1, t.x2, t.y2, t.x3, t.y3 }) do if v ~= v or v < -0.5 or v > size + 0.5 then fits = false end end end
    end
    if eye.circ[1].on and (eye.circ[1].cx - eye.circ[1].r < -0.5 or eye.circ[1].cx + eye.circ[1].r > size + 0.5) then fits = false end
  end
end
check("eye: stays inside its box at every size (10-80) and opening", fits)

-- suit icons
local icon = Spread.new_shape(Spread.ICON_TRIS, Spread.ICON_CIRCS)
local icons_ok, used = true, {}
for _, suit_name in ipairs(Cards.SUIT_ORDER) do
  Spread.icon(Cards.SUITS[suit_name].icon, 18, icon)
  local n = 0
  for _, t in ipairs(icon.tri) do
    if t.on then
      n = n + 1
      for _, v in ipairs({ t.x1, t.y1, t.x2, t.y2, t.x3, t.y3 }) do if v ~= v or v < -0.5 or v > 18.5 then icons_ok = false end end
    end
  end
  for _, c in ipairs(icon.circ) do
    if c.on then
      n = n + 1
      if c.cx - c.r < -0.5 or c.cx + c.r > 18.5 or c.cy - c.r < -0.5 or c.cy + c.r > 18.5 then icons_ok = false end
    end
  end
  used[suit_name] = n
  if n == 0 then icons_ok = false end
end
check("icons: every suit mark draws something and stays inside its 18 px box", icons_ok, "plague " .. used.plague .. " murmur " .. used.murmur .. " rage " .. used.rage .. " blight " .. used.blight .. " swarm " .. used.swarm .. " fateful " .. used.fateful)
Spread.icon("moon", 18, icon)
check("icons: the moon is a circle with a bite taken out in the card's colour", icon.circ[1].on and icon.circ[1].col == 1 and icon.circ[2].on and icon.circ[2].col == 2)
Spread.icon("cluster", 18, icon)
check("icons: the cluster is four dots", icon.circ[1].on and icon.circ[2].on and icon.circ[3].on and icon.circ[4].on and not icon.tri[1].on)

-- rot
local fx = Spread.new_rot()
Spread.rot_fx(fx, 0, 0.5, 152, 76, 1)
check("rot: nothing grows at the start (no blotch, no drip)", not fx.blotch[1].circle and not fx.blotch[1].rect and not fx.drips[1].on and near(fx.shrink, 1) and near(fx.fade, 1) and near(fx.wash, 0))
Spread.rot_fx(fx, 1, 1, 152, 76, 1)
local inside = true
for i = 1, 5 do
  local b = fx.blotch[i]
  if b.rect and (b.x0 < 0 or b.y0 < 0 or b.x1 > 152 or b.y1 > 76 * fx.shrink + 1e-6 or b.x1 <= b.x0 or b.y1 <= b.y0) then inside = false end
  if b.circle and (b.cx - b.r < -1e-6 or b.cx + b.r > 152 + 1e-6 or b.cy - b.r < -1e-6 or b.cy + b.r > 76 * fx.shrink + 1e-6) then inside = false end
  if not (b.circle or b.rect) then inside = false end
end
check("rot: at full rot every blotch is on the card and never spills over its edge (circle that fits, else a clipped square)", inside)
check("rot: strongest rot sags the card by 30.8 percent, fades it, browns it", near(fx.shrink, 1 - 0.22 * 1.4) and fx.fade < 0.02 and near(fx.bright, 0.6) and near(fx.wash, 0.55))
local flies = 0
for i = 1, Spread.MAX_FLIES do if fx.flies[i].on then flies = flies + 1 end end
check("rot: 9 flies at full strength, 3 at none", flies == 9)
Spread.rot_fx(fx, 0.5, 0, 152, 76, 1)
flies = 0
for i = 1, Spread.MAX_FLIES do if fx.flies[i].on then flies = flies + 1 end end
check("rot: ...3 flies at the weakest", flies == 3)
Spread.rot_fx(fx, 0.5, 0, 152, 76, 1); local blot_weak = fx.blotch[3].circle and fx.blotch[3].r or 0
Spread.rot_fx(fx, 0.5, 1, 152, 76, 1); local blot_strong = (fx.blotch[3].circle and fx.blotch[3].r) or 99
check("rot: a stronger rot grows bigger blotches", blot_strong > blot_weak, blot_weak .. " vs " .. blot_strong)
local finite_all = true
for _, time in ipairs({ 0, 0.3, 1, 7.7 }) do
  Spread.rot_fx(fx, 0.5, 0.5, 132, 97, time)
  for i = 1, Spread.DRIPS do if fx.drips[i].y ~= fx.drips[i].y or fx.drips[i].alpha < 0 or fx.drips[i].alpha > 1 then finite_all = false end end
  for i = 1, Spread.MAX_FLIES do if fx.flies[i].x ~= fx.flies[i].x then finite_all = false end end
end
check("rot: drips and flies are always finite, drip opacity within 0..1", finite_all)

-- =====================================================================================================================
-- definitions
-- =====================================================================================================================
local names = {}
for name in pairs(Definitions.widget_definitions) do names[name] = true end
check("definitions: widgets legacy, header, fx, banner, card_1..5", names.legacy and names.header and names.fx and names.banner and names.card_1 and names.card_5)
local nodes = 0
for name, node in pairs(Definitions.scenegraph_definition) do if name ~= "screen" then nodes = nodes + 1 end end
check("definitions: exactly ONE movable node (custom_hud lists every non-root node)", nodes == 1 and Definitions.scenegraph_definition.panel ~= nil)
check("definitions: the node is top-centre and 700 wide", Definitions.scenegraph_definition.panel.horizontal_alignment == "center" and Definitions.scenegraph_definition.panel.size[1] == 700)
local all_widgets_on_panel = true
for name, def in pairs(Definitions.widget_definitions) do if def.scenegraph_id ~= "panel" then all_widgets_on_panel = false end end
check("definitions: every widget is drawn in that node", all_widgets_on_panel)
local hidden = true
for name, def in pairs(Definitions.widget_definitions) do
  if name ~= "legacy" then for id, st in pairs(def.style) do if st.visible ~= false then hidden = false end end end
end
check("definitions: every pass of the Spread starts hidden", hidden)
local known_fonts = { proxima_nova_bold = true, itc_novarese_medium = true, machine_medium = true }
local fonts_ok = true
for _, def in pairs(Definitions.widget_definitions) do for _, st in pairs(def.style) do if st.font_type and not known_fonts[st.font_type] then fonts_ok = false end end end
check("definitions: only fonts that exist in the game", fonts_ok)
local passes = 0
for name, def in pairs(Definitions.widget_definitions) do if name:find("^card_") then passes = #def.passes end end
check("definitions: a card has about 50 passes (all hidden but the ones it uses)", passes >= 40 and passes <= 60, passes)

-- =====================================================================================================================
-- the element: a whole hand, step by step
-- =====================================================================================================================
local el = new_element()
check("element: nothing is drawn before the director says so", (function() current_view = { phase = "off" } frame(el) return visible_cards(el) == 0 and not el._widgets_by_name.header.visible end)())

current_view = view_of({ phase = "waiting", hand = nil, remaining = 83, hand_seconds = 0 })
frame(el)
local header = el._widgets_by_name.header
check("waiting: only 'Next card in 1:23', no cards, no fuse", header.visible and header.content.label == "hud_next_card" and header.content.time == "1:23" and visible_cards(el) == 0 and header.style.fuse_track.visible == false)
check("waiting: the legacy lines stay hidden", el._widgets_by_name.legacy.visible == false and not el._widgets_by_name.banner.visible and not el._widgets_by_name.fx.visible)
audit_ok("waiting", el)

current_view = view_of({ remaining = 9.5 })
frame(el)
local c = function(i) return el._widgets_by_name["card_" .. i] end
check("hand: four cards visible, the fifth hidden", visible_cards(el) == 4 and c(1).visible and c(4).visible and not c(5).visible)
check("hand: card geometry follows the layout (152 wide, 8 px apart, 38 px down)", c(1).style.bg.offset[1] == 34 and c(2).style.bg.offset[1] == 194 and c(1).style.bg.offset[2] == 38 and c(1).style.bg.size[1] == 152 and c(1).style.bg.size[2] == 76)
check("hand: the name is on the card", c(1).content.name == "The Multitude" and c(4).content.name == "Death")
check("hand: the card takes its suit's colours (swarm card, accent bar, name text)", c(1).style.bg.color[2] == 27 and c(1).style.bg.color[3] == 29 and c(1).style.accent.color[2] == 154 and c(1).style.name.text_color[2] == 217)
check("hand: threat diamonds are filled up to the threat, in its colour (3 = light yellow), the rest empty", c(1).style.th_o3.color[2] == 227 and c(1).style.th_i3.visible == false and c(1).style.th_i4.visible == true and c(1).style.th_o5.color[2] == 152)
check("hand: threat 5 on The Devil is red and fills every diamond", c(2).style.th_o5.color[2] == 207 and c(2).style.th_i1.visible == false and c(2).style.th_i5.visible == false)
check("hand: one dot per enemy colour (3 fodder-like kinds with 2 colours, 4 kinds with 4)", (function()
  local n1, n4 = 0, 0
  for j = 1, 6 do if c(1).style["dot_" .. j].visible then n1 = n1 + 1 end if c(4).style["dot_" .. j].visible then n4 = n4 + 1 end end
  return n1 == 2 and n4 == 4
end)(), "")
check("hand: only the rare card (Death) has the pus-yellow outline", c(4).style.rare_t.visible and c(4).style.rare_l.color[2] == 227 and not c(1).style.rare_t.visible)
check("hand: every card shows its suit mark", (function()
  for i = 1, 4 do
    local any = false
    for j = 1, 4 do if c(i).style["icon_t" .. j].visible or c(i).style["icon_c" .. j].visible then any = true end end
    if not any then return false end
  end
  return true
end)())
check("hand: the eye is shut on every card and faint (16 percent)", (function()
  for i = 1, 4 do
    local st = c(i).style
    if not st.eye_t1.visible or st.eye_t1.color[1] ~= 41 or st.eye_t3.visible or st.eye_c1.visible or not st.eye_t5.visible then return false end
  end
  return true
end)())
check("hand: the fuse is nearly full and bile green", header.style.fuse_fill.visible and header.style.fuse_fill.size[1] > 0.9 * 632 and header.style.fuse_fill.color[2] == 183 and header.style.fuse_track.size[1] == 632)
check("hand: nothing is highlighted, no banner", c(1).offset[2] == 0 and c(3).offset[2] == 0 and not el._widgets_by_name.banner.visible)
audit_ok("hand", el)

current_view = view_of({ remaining = 4.2 })
frame(el)
check("hand: the last 5 seconds turn the fuse and the time rust", header.style.fuse_fill.color[2] == 194 and header.style.time.text_color[2] == 194)
current_view = view_of({ remaining = 4.2, paused = true })
frame(el)
check("hand: a paused game says so", header.content.time:find("hud_paused") ~= nil)

-- the roulette
current_view = view_of({ remaining = 1.5, win = 3 })
frame(el)
local seen, last_hi = {}, nil
local win_hi = nil
for step = 0, 90 do
  current_view.remaining = 1.5 - step / 60
  if current_view.remaining < 0 then current_view.remaining = 0 end
  frame(el)
  local hi = 0
  for i = 1, 4 do if c(i).style.glow_1.visible then hi = i end end
  seen[#seen + 1] = hi
  win_hi = hi
end
local raised = 0
for i = 1, 4 do if c(i).offset[2] == -5 then raised = raised + 1 end end
check("roulette: it lands on the host's winner (card 3), which is raised and glowing", win_hi == 3 and c(3).offset[2] == -5 and raised == 1 and c(3).style.bg.color[2] == 0x33, win_hi)
check("roulette: the highlighted card uses the suit's lighter colour", c(3).style.bg.color[2] == 0x33 and c(3).style.bg.color[3] == 0x32 and c(1).style.bg.color[2] == 27)
check("roulette: while it ran, the highlight moved across cards", (function() local d = {} for _, h in ipairs(seen) do d[h] = true end return d[1] or d[2] or d[4] end)())
audit_ok("roulette", el)

-- the pick: reveal
current_view = view_of({ phase = "waiting", remaining = 120, hand_seconds = 0, drawn = true, drawn_age = 0.05, win = 3 })
frame(el)
local banner = el._widgets_by_name.banner
check("reveal: the banner appears with 'THE CARD IS DRAWN', the name, the whisper (in quotes) and nothing for no modifiers", banner.visible and banner.content.kicker == "HUD_CARD_DRAWN" and banner.content.name == "The Tower" and banner.content.whisper == "\"Pop, pop, pop.\"" and banner.style.mods.visible == false)
check("reveal: the banner name has the suit's accent colour", banner.style.name.text_color[2] == 227 and banner.style.name.text_color[3] == 207)
current_view.drawn_age = 0.3
for _ = 1, 30 do frame(el) end
check("reveal: the winner rises (6 px), the others fall away to the rim of invisible", c(3).offset[2] < -4 and c(1).alpha_multiplier < 0.7 and c(1).offset[2] > 3, c(1).alpha_multiplier)
check("reveal: the winner is larger (the card layer grows 6 percent)", c(3).style.bg.size[1] > 152.5 and c(3).style.bg.size[1] < 162)
check("reveal: the winner's eye is opening (inside and pupil appear)", c(3).style.eye_t3.visible or c(3).style.eye_t1.color[1] > 41)
current_view.drawn_age = 0.5
frame(el)
check("reveal: the eye is open and brighter (50 percent) with a pupil, no lashes", c(3).style.eye_t3.visible and c(3).style.eye_c1.visible and not c(3).style.eye_t5.visible and c(3).style.eye_t1.color[1] == 128 and c(1).style.eye_t1.color[1] == 41)
check("reveal: the time and fuse are fading out", header.alpha_multiplier < 0.01)
audit_ok("reveal", el)

-- the rot
current_view.drawn_age = 2.4
frame(el)
local fxw = el._widgets_by_name.fx
check("rot: the effects are shown, the banner is gone", fxw.visible and not banner.visible and fxw.style.wash.visible)
check("rot: the winner browns, the others are gone", c(3).color_intensity_multiplier < 1 and c(1).alpha_multiplier == 0)
check("rot: the card sags from its top edge", c(3).style.bg.size[2] < 76 * 1.06)
check("rot: the winner's cooldown sets its rot (120 s: strength 0.46, 2.0 s)", near(el._T.k, 0.4627, 0.001) and near(el._T.rot, 1.2 + 1.8 * 0.4627, 0.01), el._T.rot)
local circles_or_rects = 0
for i = 1, 5 do if fxw.style["blot_c" .. i].visible or fxw.style["blot_r" .. i].visible then circles_or_rects = circles_or_rects + 1 end end
check("rot: blotches have started to grow", circles_or_rects >= 1, circles_or_rects)
audit_ok("rot", el)
current_view.drawn_age = 1.6 + el._T.rot - 0.01
frame(el)
check("rot: at the end the whole card has rotted away", c(3).alpha_multiplier < 0.05 and fxw.style.wash.color[1] > 100)
audit_ok("rot end", el)
current_view.drawn_age = 1.6 + el._T.rot + 0.7
frame(el)
check("gone: everything of the Spread is hidden again, the time shows", visible_cards(el) == 0 and not fxw.visible and not banner.visible and header.alpha_multiplier == 1 and header.style.time.visible)
audit_ok("gone", el)

-- a late joiner: the hand is already being eaten by rot
local late = new_element()
current_view = view_of({ phase = "waiting", remaining = 100, hand_seconds = 0, drawn = true, drawn_age = 3.6, win = 4, hand_seq = 7 })
frame(late)
check("late join: straight into the rot, with the same winner", late._stage == "rot" and late._widgets_by_name.fx.visible and late._widgets_by_name["card_4"].alpha_multiplier < 1 and late._widgets_by_name["card_4"].offset[2] == -6, late._stage)
audit_ok("late join", late)

-- a new hand after the old one: same element, new number
current_view = view_of({ remaining = 9, hand_seq = 8 })
frame(el)
check("new hand: the cards are back, resting, with fresh text", visible_cards(el) == 4 and c(1).alpha_multiplier == 1 and c(1).offset[2] == 0 and c(3).color_intensity_multiplier == 1 and c(3).offset[2] == 0 and not fxw.visible)
check("new hand: the eye is shut again on the old winner", c(3).style.eye_t1.color[1] == 41 and not c(3).style.eye_t3.visible)
audit_ok("new hand", el)

-- one card: no roulette, and the layout is centred
current_view = view_of({ hand = { card("a", "The Fool", "swarm", 1, { "chaos_poxwalker" }, "There are always more.") }, win = 1, remaining = 0.4, hand_seq = 9 })
frame(el)
check("one card: 176 wide and centred; no highlight even in the last second", visible_cards(el) == 1 and c(1).style.bg.size[1] == 176 and c(1).style.bg.offset[1] == 262 and c(1).offset[2] == 0 and not c(1).style.glow_1.visible)
audit_ok("one card", el)

-- five cards with long names
local five = { card("a", "The Watching Moon", "murmur", 3, { "renegade_sniper" }, "Someone is counting you."), card("b", "Rain of Rot", "blight", 4, { "cultist_grenadier", "renegade_grenadier" }, "The sky is sick."),
  card("c", "Grandfather's Gift", "plague", 3, { "chaos_poxwalker" }, "It grows.", "Purple · Orange"), card("d", "Nurgle's Rage", "rage", 4, { "chaos_mutated_poxwalker" }, "Grandfather is hungry."), card("e", "Strength", "rage", 2, { "chaos_ogryn_executor" }, "Heavy.", "", true, 300) }
current_view = view_of({ hand = five, win = 5, remaining = 8, hand_seq = 10 })
frame(el)
check("five cards: 132 wide, the row fits the node, the card height grew for the three-line name", visible_cards(el) == 5 and c(1).style.bg.size[1] == 132 and c(1).style.bg.offset[1] == 4 and c(5).style.bg.offset[1] + 132 == 696 and c(1).style.bg.size[2] == 97)
check("five cards: the plague mark is an eye (card 3), the murmur mark a moon (card 1)", c(3).style.icon_t1.visible and c(1).style.icon_c1.visible)
audit_ok("five cards", el)
current_view = view_of({ hand = five, phase = "waiting", remaining = 100, hand_seconds = 0, drawn = true, drawn_age = 2.2, win = 5, hand_seq = 10 })
frame(el)
audit_ok("five cards, rot", el)

-- empty states
current_view = view_of({ phase = "waiting", hand = nil, remaining = 9, empty = true, cooling = false, hand_seconds = 0, hand_seq = 0 })
frame(el)
check("empty: nothing in the draw says so (no countdown)", header.style.status.visible and header.content.status == "hud_empty_tarot" and not header.style.time.visible and visible_cards(el) == 0)
current_view = view_of({ phase = "waiting", hand = nil, remaining = 9, empty = true, cooling = true, hand_seconds = 0, hand_seq = 0 })
frame(el)
check("empty: every card cooling down says so", header.content.status == "hud_all_cooling")
audit_ok("empty", el)

-- legacy modes
current_view = { phase = "waiting", mode = "random", remaining = 30, ballot_id = 1, chosen = "", cands = { { name = "Hound Frenzy", pct = 20, votes = 0 } }, version = 1 }
frame(el)
local legacy = el._widgets_by_name.legacy
check("legacy random: the old panel is shown, the Spread is hidden", legacy.visible and legacy.content.line_0:find("hud_wave_in") ~= nil and visible_cards(el) == 0 and not header.visible)
check("legacy random: the candidate line is shown", legacy.content.line_1:find("Hound Frenzy") ~= nil)
current_view = { phase = "voting", mode = "vote", remaining = 20, ballot_id = 2, chosen = "", cands = { { name = "A", pct = 20, votes = 1 }, { name = "B", pct = 10, votes = 0 } }, version = 2, my_vote = 1 }
frame(el)
check("legacy vote: lines for the candidates and the keys", legacy.content.line_0:find("hud_vote_now") ~= nil and legacy.content.line_1:find("A") ~= nil and legacy.content.line_3 ~= "")
audit_ok("legacy", el)
current_view = view_of({ remaining = 9, hand_seq = 11 })
frame(el)
check("legacy -> tarot: the panel is hidden and the hand is set up again", not legacy.visible and visible_cards(el) == 4)
current_view = { phase = "off" }
frame(el)
check("off: everything is hidden again", visible_cards(el) == 0 and not header.visible and not legacy.visible)

-- custom_hud's edit mode shows a sample so there is something to drag
custom_hud.is_customizing = true
local sample = new_element()
current_view = { phase = "off" }
frame(sample)
check("custom_hud: the edit mode shows a sample hand (four cards) even when nothing runs", visible_cards(sample) == 4 and sample._widgets_by_name.header.visible)
audit_ok("sample", sample)
settings.mode = "vote"
local sample2 = new_element()
frame(sample2)
check("custom_hud: ...or the old sample panel in the legacy modes", sample2._widgets_by_name.legacy.visible and visible_cards(sample2) == 0)
settings.mode = nil
custom_hud.is_customizing = false
settings.hud_enabled = false
frame(el); current_view = view_of({ remaining = 9, hand_seq = 12 }); frame(el)
check("option: 'Show wave panel' off hides it", visible_cards(el) == 0)
settings.hud_enabled = nil

-- the player's own timeline options
settings.tarot_eye_size = 60; settings.tarot_roulette = 3; settings.tarot_winner = 4; settings.tarot_rot_short = 0.5; settings.tarot_rot_long = 8; settings.tarot_longest = 30
local opts = new_element()
current_view = view_of({ remaining = 2.5, hand_seq = 20 })
frame(opts)
check("options: roulette 3 s starts the roulette earlier", opts._timeline.stage == "roulette")
local ec = opts._widgets_by_name.card_1.style
check("options: a bigger eye is drawn (60 px lens)", ec.eye_t1.triangle_corners[3][1] - ec.eye_t1.triangle_corners[1][1] > 40)
check("options: rot times come from the options (120 s of a 30 min longest cooldown, 0.5-8 s: strength 0.34, 3.04 s)", near(opts._T.rot, 0.5 + 7.5 * 0.3386, 0.02), opts._T.rot)
settings.tarot_eye_size = nil; settings.tarot_roulette = nil; settings.tarot_winner = nil; settings.tarot_rot_short = nil; settings.tarot_rot_long = nil; settings.tarot_longest = nil

-- a broken view must not crash the HUD: the error is caught and reported once
local crash = new_element()
current_view = view_of({ hand = { { name = "No suit, no breeds" } } })
frame(crash); frame(crash)
check("a malformed card is survived (and logged once at most)", #errors_logged <= 1, #errors_logged)

-- =====================================================================================================================
-- no allocation per frame
-- =====================================================================================================================
local function growth(fixed_view, step, frames)
  local e = new_element()
  current_view = fixed_view
  for i = 1, 30 do step(fixed_view, i); frame(e) end -- warm-up: strings, caches
  collectgarbage("collect"); collectgarbage("stop")
  local before = collectgarbage("count")
  for i = 1, frames do step(fixed_view, i); frame(e) end
  local after = collectgarbage("count")
  collectgarbage("restart")
  return (after - before) * 1024 / frames
end
local per_frame_hand = growth(view_of({ remaining = 9.5, hand_seq = 30 }), function(v, i) end, 600)
check("no allocation per frame while a hand is shown (idle)", per_frame_hand < 1, string.format("%.2f bytes/frame", per_frame_hand))
local per_frame_run = growth(view_of({ remaining = 9.5, hand_seq = 31 }), function(v, i) v.remaining = math.max(0, 9.5 - i / 60 / 3) end, 600)
check("almost no allocation per frame while the fuse burns and the roulette runs (the time text changes once a second)", per_frame_run < 64, string.format("%.2f bytes/frame", per_frame_run))
local per_frame_reveal = growth(view_of({ phase = "waiting", remaining = 100, hand_seconds = 0, drawn = true, drawn_age = 0.05, hand_seq = 32 }), function(v, i) v.drawn_age = 0.05 + (i % 100) / 100 * 1.4 end, 600)
check("no allocation per frame during the reveal", per_frame_reveal < 1, string.format("%.2f bytes/frame", per_frame_reveal))
local per_frame_rot = growth(view_of({ phase = "waiting", remaining = 100, hand_seconds = 0, drawn = true, drawn_age = 1.7, hand_seq = 33 }), function(v, i) v.drawn_age = 1.7 + (i % 100) / 100 * 1.8 end, 600)
check("no allocation per frame during the rot (blotches, flies, drips)", per_frame_rot < 1, string.format("%.2f bytes/frame", per_frame_rot))
check("no errors logged by the guarded refresh", #errors_logged <= 1, table.concat(errors_logged, " | "))

return table.concat(results, "\n")
'''
out = lua.execute(harness, MODROOT)
print(out)
fails = [l for l in out.split("\n") if l.startswith("FAIL")]
print("\nPASS:", len([l for l in out.split("\n") if l.startswith("PASS")]), "FAIL:", len(fails))
sys.exit(1 if fails else 0)
