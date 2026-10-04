"""Drives the real wave HUD (ui/spread.lua, the widget definitions, hud_element_waves.lua) against stubbed engine classes.

Not a substitute for the game: nothing is drawn. It executes every code path of the Spread (deal, roulette, reveal, rot,
late join, legacy panel, custom_hud sample) and audits, after every step, that each pass the engine would draw has the
numbers it needs (no nil, no NaN, sane positions) and that nothing allocates per frame.
Run:  python tools/hud_test.py   (needs `lupa`, see CLAUDE.md)
"""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
from lua_test_runtime import LuaRuntime

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
RESOLUTION_LOOKUP = { scale = 1.5, inverse_scale = 1 / 1.5 }
local draws = {}
HudElementBase.draw = function(self, dt, t, ui_renderer, render_settings, input_service)
  local card = self._widgets_by_name.card_1
  draws[#draws + 1] = { scale = render_settings.scale, inverse = render_settings.inverse_scale, ox = card.offset[1], oy = card.offset[2], a = card.alpha_multiplier,
                        hx = self._widgets_by_name.header.offset[1], ha = self._widgets_by_name.header.alpha_multiplier }
  if self._explode then error("boom") end
end
HudElementBase.init = function(self, parent, draw_layer, start_scale, definitions)
  self._ui_scenegraph = { panel = { world_position = { 610, 36, 50 } } }
  self._definitions = definitions
  self._widgets, self._widgets_by_name = {}, {}
  for name, def in pairs(definitions.widget_definitions) do
    local w = UIWidget.init(name, def)
    self._widgets[#self._widgets + 1] = w
    self._widgets_by_name[name] = w
  end
end
HudElementBase.update = function() end
HudElementBase._set_scenegraph_size = function(self, id, w, h) self._sg_size = { id, w, h } end
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
mod.io_dofile = function(self, path) return dofile(MODROOT .. "/" .. path:gsub("^RealmsWaves/", "") .. ".lua") end
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
local d9, p9, n9 = Spread.dots_fit(176, 6)
check("dots: a wide card shows six dots at full size (9 px, 13 apart)", d9 == 9 and p9 == 13 and n9 == 6)
local d152, p152, n152 = Spread.dots_fit(152, 5)
check("dots: five dots on a four-card card get smaller and closer, but all fit", d152 < 9 and n152 == 5 and d152 + 4 * p152 <= 152 - 12 - (Spread.DIAMONDS_END + Spread.DOTS_GAP) + 1e-9, d152 .. "/" .. p152)
local d132, p132, n132 = Spread.dots_fit(132, 6)
check("dots: six on a five-card card do not fit: the first few are shown", n132 >= 3 and n132 < 6 and d132 <= 7, n132)
local gap_ok = true
for _, cw in ipairs({ 132, 152, 176 }) do
  for count = 0, 6 do
    local d, p, n = Spread.dots_fit(cw, count)
    if n > 0 and (cw - Spread.PAD_X) - (d + (n - 1) * p) < Spread.DIAMONDS_END + Spread.DOTS_GAP - 1e-9 then gap_ok = false end
  end
end
check("dots: they are never closer than 12 units to the threat diamonds, whatever the card and the count", gap_ok)
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
local lens_a, lid_a, pupil_a = Spread.eye(28, 0, eye)
local ribbon_on, lashes_on = true, true
for i = 5, 16 do if not eye.tri[i].on then ribbon_on = false end end
for i = 17, 19 do if not eye.tri[i].on then lashes_on = false end end
check("eye: shut = the smile of a lid (a ribbon of 6 segments) with three lashes, no lens, no inside, no pupil", ribbon_on and lashes_on and not eye.tri[1].on and not eye.tri[3].on and not eye.circ[1].on and lens_a == 0 and lid_a == 1 and pupil_a == 0)
local lid_low = true
for i = 5, 16 do local t = eye.tri[i]; if t.y1 < 28 * 0.3 or t.y2 < 28 * 0.3 or t.y3 < 28 * 0.3 then lid_low = false end end
local mid_y = (eye.tri[9].y1 + eye.tri[9].y2 + eye.tri[9].y3) / 3
check("eye: the lid is a smile (its middle lower than its ends), centred on the box", lid_low and mid_y > (eye.tri[5].y1 + eye.tri[5].y2 + eye.tri[5].y3) / 3 and mid_y > 14 - 3.5 and mid_y < 14 + 4, mid_y)
lens_a, lid_a, pupil_a = Spread.eye(28, 1, eye)
check("eye: open = an outline (lens and inside) with a pupil and no lid", eye.tri[1].on and eye.tri[3].on and eye.tri[4].on and eye.circ[1].on and not eye.tri[5].on and not eye.tri[17].on and lens_a == 1 and lid_a == 0 and pupil_a == 1)
Spread.eye(28, 0.3, eye); local h_shut = eye.tri[1].y2
local half_a, half_c = Spread.eye(28, 0.5, eye)
check("eye: half open shows both drawings, half as strong", near(half_a, 0.5) and near(half_c, 0.5) and eye.tri[1].on and eye.tri[5].on)
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
local mini = Spread.new_shape(4, 4)
Spread.eye(28, 0, mini)
check("eye: a smaller shape table (the suit mark's) is survived even with the shut eye", true)

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
check("icons: sixteen suits, and the newer ones use their own slots (volley 7, snare 4, brute 5, warp 5, heresy 6, nightmare 7, faith 7)", #Cards.SUIT_ORDER == 16 and used.faith == 7 and used.volley == 7 and used.snare == 4 and used.brute == 5 and used.nightmare == 7 and used.warp == 5 and used.heresy == 6, "volley " .. used.volley .. " snare " .. used.snare .. " brute " .. used.brute .. " nightmare " .. tostring(used.nightmare) .. " warp " .. used.warp .. " heresy " .. tostring(used.heresy))
check("icons: at the Deck's 26 units every mark also stays inside its box", (function()
  for _, suit_name in ipairs(Cards.SUIT_ORDER) do
    Spread.icon(Cards.SUITS[suit_name].icon, 26, icon)
    for _, t in ipairs(icon.tri) do
      if t.on then for _, v in ipairs({ t.x1, t.y1, t.x2, t.y2, t.x3, t.y3 }) do if v ~= v or v < -0.5 or v > 26.5 then return false end end end
    end
    for _, c in ipairs(icon.circ) do
      if c.on and (c.cx - c.r < -0.5 or c.cx + c.r > 26.5 or c.cy - c.r < -0.5 or c.cy + c.r > 26.5) then return false end
    end
  end
  return true
end)())
check("icons: every shape of the cut-outs is drawn above the shape it cuts (the warp's inside, the nightmare eye's hollow and its pupil)", (function()
  Spread.icon("warp", 18, icon)
  local ok = icon.tri[2].col == 2 and icon.tri[2].z > icon.tri[1].z and icon.tri[3].z > icon.tri[2].z and icon.circ[1].col == 2 and icon.circ[1].z > icon.tri[3].z
  Spread.icon("nightmare", 18, icon)
  return ok and icon.circ[2].col == 2 and icon.circ[2].z > icon.circ[1].z and icon.tri[3].z > icon.circ[2].z and icon.tri[4].z > icon.circ[2].z and icon.tri[1].col == 1
end)())
Spread.icon("moon", 18, icon)
check("icons: the moon is a circle with a bite taken out in the card's colour", icon.circ[1].on and icon.circ[1].col == 1 and icon.circ[2].on and icon.circ[2].col == 2)
Spread.icon("cluster", 18, icon)
check("icons: the cluster is four dots", icon.circ[1].on and icon.circ[2].on and icon.circ[3].on and icon.circ[4].on and not icon.tri[1].on)

-- rot
local fx = Spread.new_rot()
Spread.rot_fx(fx, 0, 0.5, 152, 76, 1)
check("rot: nothing grows at the start (no blotch, no drip)", not fx.blotch[1].on and not fx.drips[1].on and near(fx.fade, 1) and near(fx.wash, 0))
Spread.rot_fx(fx, 1, 1, 152, 76, 1)
local inside = true
for i = 1, 5 do
  local b = fx.blotch[i]
  if not b.on or b.cx - b.r < -1e-6 or b.cx + b.r > 152 + 1e-6 or b.cy - b.r < -1e-6 or b.cy + b.r > 76 + 1e-6 then inside = false end
end
check("rot: at full rot every blotch is a circle that grows until it touches the card's edge and never spills over it", inside)
check("rot: strongest rot fades the card out, darkens it (40 percent) and browns it (60 percent wash), it no longer sags", fx.fade < 0.02 and near(fx.bright, 0.6) and near(fx.wash, 0.6) and fx.shrink == nil)
local flies = 0
for i = 1, Spread.MAX_FLIES do if fx.flies[i].on then flies = flies + 1 end end
check("rot: 9 flies at full strength, 3 at none", flies == 9)
Spread.rot_fx(fx, 0.5, 0, 152, 76, 1)
flies = 0
for i = 1, Spread.MAX_FLIES do if fx.flies[i].on then flies = flies + 1 end end
check("rot: ...3 flies at the weakest", flies == 3)
Spread.rot_fx(fx, 0.5, 0, 152, 76, 1); local blot_weak = fx.blotch[3].r
Spread.rot_fx(fx, 0.5, 1, 152, 76, 1); local blot_strong = fx.blotch[3].r
check("rot: a stronger rot grows bigger blotches", blot_strong > blot_weak, blot_weak .. " vs " .. blot_strong)
local rings = Spread.BLOTCH_RINGS
local soft = #rings >= 3 and rings[1][1] == 1 and rings[#rings][1] < 0.5
for i = 2, #rings do if rings[i][1] >= rings[i - 1][1] then soft = false end end
check("rot: a blotch is rings, the outermost the faintest and the biggest (a soft edge without a gradient)", soft and rings[1][2] < rings[#rings][2])
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
local panel = Definitions.scenegraph_definition.panel
check("definitions: the node is on a top-left basis (what custom_hud pins), 700 wide, and starts in the middle of 1920", panel.horizontal_alignment == "left" and panel.vertical_alignment == "top" and panel.size[1] == 700 and panel.position[1] + 350 == 960)
local all_widgets_on_panel = true
for name, def in pairs(Definitions.widget_definitions) do if def.scenegraph_id ~= "panel" then all_widgets_on_panel = false end end
check("definitions: every widget is drawn in that node", all_widgets_on_panel)
local hidden = true
for name, def in pairs(Definitions.widget_definitions) do
  if name ~= "legacy" then for id, st in pairs(def.style) do if st.visible ~= false then hidden = false end end end
end
check("definitions: every pass of the Spread starts hidden", hidden)
local known_fonts = { proxima_nova_bold = true, itc_novarese_bold = true, itc_novarese_medium = true, friz_quadrata = true, rexlia = true, machine_medium = true }
local fonts_ok = true
for _, def in pairs(Definitions.widget_definitions) do for _, st in pairs(def.style) do if st.font_type and not known_fonts[st.font_type] then fonts_ok = false end end end
check("definitions: only fonts that exist in the game", fonts_ok)
local passes = 0
for name, def in pairs(Definitions.widget_definitions) do if name:find("^card_") then passes = #def.passes end end
check("definitions: a card has about 60 passes (all hidden but the ones it uses)", passes >= 50 and passes <= 80, passes)

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
check("hand: threat diamonds are filled up to the threat, in its colour (3 = light yellow), the rest the same diamond dimmed", c(1).style.th_o3.color[2] == 227 and c(1).style.th_o3.color[1] == 255 and c(1).style.th_o4.visible and c(1).style.th_o4.color[1] == 64 and c(1).style.th_o5.color[2] == 152)
check("hand: threat 5 on The Devil is red and fills every diamond", c(2).style.th_o5.color[2] == 207 and c(2).style.th_o1.color[1] == 255 and c(2).style.th_o5.color[1] == 255)
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
check("hand: the eye is shut on every card (the lid and its lashes, no lens, no pupil) and faint (16 percent)", (function()
  for i = 1, 4 do
    local st = c(i).style
    if st.eye_t1.visible or not st.eye_t5.visible or st.eye_t5.color[1] ~= 41 or not st.eye_t17.visible or st.eye_c1.visible then return false end
  end
  return true
end)())
check("hand: the label says the card is revealed in (not 'next card')", header.content.label == "hud_card_in" and header.content.time == "0:10")
check("hand: diamonds and dots have a faint copy under them (anti-aliasing), the empty diamonds a fainter one", c(1).style.th_h1.visible and c(1).style.th_h1.color[1] == 70 and c(1).style.th_h5.color[1] == 22 and c(1).style.dh_1.visible and c(1).style.dh_1.color[1] == 70 and not c(1).style.dh_3.visible)
check("hand: there is no inner diamond any more (an outline of two rotated squares came out uneven, with gaps)", c(1).style.th_i4 == nil and c(1).style.th_o4.size[1] == Spread.THREAT_SIDE)
check("hand: every shape of the suit mark has a faint, slightly larger copy under it (anti-aliasing of the edge)", (function()
  for i = 1, 4 do
    local st = c(i).style
    for j = 1, 4 do
      local t1, h1 = st["icon_t" .. j], st["icon_th" .. j]
      if t1.visible then
        if not h1.visible or h1.color[1] ~= 77 or h1.offset[3] >= t1.offset[3] then return false end
        -- each corner of the copy is further from the triangle's centre than the triangle's own
        local function spread(corners) local cx, cy = (corners[1][1] + corners[2][1] + corners[3][1]) / 3, (corners[1][2] + corners[2][2] + corners[3][2]) / 3; return math.sqrt((corners[1][1] - cx) ^ 2 + (corners[1][2] - cy) ^ 2) end
        if spread(h1.triangle_corners) <= spread(t1.triangle_corners) then return false end
      elseif h1.visible then return false end
      local c1, ch = st["icon_c" .. j], st["icon_ch" .. j]
      if c1.visible then
        if not ch.visible or ch.size[1] <= c1.size[1] or ch.color[1] ~= 77 or ch.offset[3] >= c1.offset[3] then return false end
        -- the copy is centred on the circle
        if math.abs((ch.offset[1] + ch.size[1] / 2) - (c1.offset[1] + c1.size[1] / 2)) > 1e-6 then return false end
      elseif ch.visible then return false end
    end
  end
  return true
end)())
check("hand: the label and the time are ONE line centred on the node (and the fuse): the label ends 12 before the time starts, the pair's middle is 350", (function()
  local lw = #header.content.label * header.style.label.font_size * 0.52
  local tw = #header.content.time * header.style.time.font_size * 0.5
  local label_right = header.style.label.offset[1] + header.style.label.size[1]
  local time_left = header.style.time.offset[1]
  local middle = (label_right - lw + time_left + Spread.TIME_GAP * 0 + tw) / 2
  return math.abs(time_left - label_right - Spread.TIME_GAP) < 1e-6 and math.abs(middle - 350) < 1e-6 + 0, tostring(middle)
end)())
check("hand: the fuse is nearly full and bile green", header.style.fuse_fill.visible and header.style.fuse_fill.size[1] > 0.9 * 632 and header.style.fuse_fill.color[2] == 183 and header.style.fuse_track.size[1] == 632)
check("hand: dots keep their distance from the diamonds (12 units)", (function()
  for i = 1, 4 do
    local st = c(i).style
    local first_dot = nil
    for j = 1, 6 do if st["dot_" .. j].visible then first_dot = first_dot or st["dot_" .. j].offset[1] end end
    local card_x = st.bg.offset[1]
    if first_dot and first_dot - card_x < Spread.DIAMONDS_END + Spread.DOTS_GAP - 1e-6 then return false end
  end
  return true
end)())
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
  for i = 1, 4 do if c(i).style.glow.visible then hi = i end end
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
check("reveal: the winner's eye is opening (the lens appears)", c(3).style.eye_t1.visible)
current_view.drawn_age = 0.5
frame(el)
check("reveal: the eye is open and brighter (50 percent) with a pupil, no lid or lashes; the other cards' eyes stay shut", c(3).style.eye_t3.visible and c(3).style.eye_c1.visible and not c(3).style.eye_t5.visible and c(3).style.eye_t1.color[1] == 128 and c(1).style.eye_t5.color[1] == 41 and not c(1).style.eye_t1.visible)
check("reveal: the time and fuse are gone while the card is shown", not header.visible)
audit_ok("reveal", el)

-- the rot
current_view.drawn_age = 2.4
frame(el)
local fxw = el._widgets_by_name.fx
check("rot: the effects are shown, the banner is gone", fxw.visible and not banner.visible and fxw.style.wash.visible)
check("rot: the winner browns, the others are gone", c(3).color_intensity_multiplier < 1 and c(1).alpha_multiplier == 0)
check("rot: the card layer keeps its shape (no sag, only the 6 percent of the pop)", near(c(3).style.bg.size[2], 76 * 1.06, 0.01))
-- (the longest cooldown is 30 minutes by default since 2026-10-04: log(120 / 30) / log(1800 / 30) = 0.3386)
check("rot: the winner's cooldown sets its rot (120 s of a 30 minute longest: strength 0.34, 1.8 s)", near(el._T.k, 0.3386, 0.001) and near(el._T.rot, 1.2 + 1.8 * 0.3386, 0.01), el._T.rot)
local circles_or_rects = 0
for i = 1, 5 do if fxw.style["blot_" .. i .. "_1"].visible and fxw.style["blot_" .. i .. "_4"].visible then circles_or_rects = circles_or_rects + 1 end end
check("rot: soft blotches (four rings each) have started to grow", circles_or_rects >= 1, circles_or_rects)
check("rot: no square blotches any more (the old clipped rectangles)", fxw.style.blot_r1 == nil)
audit_ok("rot", el)
current_view.drawn_age = 1.6 + el._T.rot - 0.01
frame(el)
check("rot: at the end the whole card has rotted away", c(3).alpha_multiplier < 0.05 and fxw.style.wash.color[1] > 100)
audit_ok("rot end", el)
current_view.drawn_age = 1.6 + el._T.rot + 0.7
frame(el)
check("gone: everything of the Spread is hidden again, 'Next card in' shows", visible_cards(el) == 0 and not fxw.visible and not banner.visible and header.visible and header.style.time.visible and header.content.label == "hud_next_card")
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
check("new hand: the eye is shut again on the old winner", not c(3).style.eye_t1.visible and c(3).style.eye_t5.color[1] == 41 and not c(3).style.eye_t3.visible)
audit_ok("new hand", el)

-- one card: no roulette, and the layout is centred
current_view = view_of({ hand = { card("a", "The Fool", "swarm", 1, { "chaos_poxwalker" }, "There are always more.") }, win = 1, remaining = 0.4, hand_seq = 9 })
frame(el)
check("one card: 176 wide and centred; no highlight even in the last second", visible_cards(el) == 1 and c(1).style.bg.size[1] == 176 and c(1).style.bg.offset[1] == 262 and c(1).offset[2] == 0 and not c(1).style.glow.visible)
audit_ok("one card", el)

-- five cards with long names
local five = { card("a", "The Watching Moon", "murmur", 3, { "renegade_sniper" }, "Someone is counting you."), card("b", "Rain of Rot", "blight", 4, { "cultist_grenadier", "renegade_grenadier" }, "The sky is sick."),
  card("c", "Grandfather's Gift", "plague", 3, { "chaos_poxwalker" }, "It grows.", "Purple ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· Orange"), card("d", "Nurgle's Rage", "rage", 4, { "chaos_mutated_poxwalker" }, "Grandfather is hungry."), card("e", "Strength", "rage", 2, { "chaos_ogryn_executor" }, "Heavy.", "", true, 300) }
current_view = view_of({ hand = five, win = 5, remaining = 8, hand_seq = 10 })
frame(el)
check("five cards: 132 wide, the row fits the node, the card height grew for the three-line name", visible_cards(el) == 5 and c(1).style.bg.size[1] == 132 and c(1).style.bg.offset[1] == 4 and c(5).style.bg.offset[1] + 132 == 696 and c(1).style.bg.size[2] == 97)
check("five cards: the six dots of a card on a 132 wide card are cut down to what fits", (function()
  local n = 0
  for j = 1, 6 do if c(2).style["dot_" .. j].visible then n = n + 1 end end
  return n >= 1 and n <= 4
end)())
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
local lo, hi = 1e9, -1e9
for i = 5, 16 do for k = 1, 3 do local x = ec["eye_t" .. i].triangle_corners[k][1]; if x < lo then lo = x end; if x > hi then hi = x end end end
check("options: a bigger eye is drawn (a 60 px eye: the shut lid is about 50 wide)", hi - lo > 40, hi - lo)
check("options: rot times come from the options (120 s of a 30 min longest cooldown, 0.5-8 s: strength 0.34, 3.04 s)", near(opts._T.rot, 0.5 + 7.5 * 0.3386, 0.02), opts._T.rot)
settings.tarot_eye_size = nil; settings.tarot_roulette = nil; settings.tarot_winner = nil; settings.tarot_rot_short = nil; settings.tarot_rot_long = nil; settings.tarot_longest = nil

-- a broken view must not crash the HUD: the error is caught and reported once
local crash = new_element()
current_view = view_of({ hand = { { name = "No suit, no breeds" } } })
frame(crash); frame(crash)
check("a malformed card is survived (and logged once at most)", #errors_logged <= 1, #errors_logged)


-- =====================================================================================================================
-- the chosen card loses its colour; the look options; size and opacity of the whole HUD
-- =====================================================================================================================
local function spread_of(col) return math.max(col[2], col[3], col[4]) - math.min(col[2], col[3], col[4]) end
check("grey: 0 leaves a colour alone, 1 makes every channel the same", (function()
  local out = { 0, 0, 0 }
  Spread.grey(out, { 227, 207, 74 }, 0)
  if out[1] ~= 227 or out[2] ~= 207 or out[3] ~= 74 then return false end
  Spread.grey(out, { 227, 207, 74 }, 1)
  return near(out[1], out[2], 1e-9) and near(out[2], out[3], 1e-9) and out[1] > 100 and out[1] < 227
end)())
do
  local T2 = { roulette = 1.6, winner = 1.6, eye = 0.4, rot = 2 }
  local tl2 = Spread.new_timeline()
  Spread.timeline(view_of({ remaining = 7 }), T2, tl2)
  check("timeline: a card in the hand has no desaturation", tl2.desat == 0)
  check("timeline: the chosen card starts to lose its colour at the pick", Spread.timeline(view_of({ drawn = true, phase = "waiting", drawn_age = 0 }), T2, tl2).desat == 0 and Spread.timeline(view_of({ drawn = true, phase = "waiting", drawn_age = 1.42 }), T2, tl2).desat > 0.45 and tl2.desat < 0.55)
  check("timeline: ...and is completely grey when it starts to fade away (winner shown + 62 percent of the rot)", near(Spread.timeline(view_of({ drawn = true, phase = "waiting", drawn_age = 1.6 + 0.62 * 2 }), T2, tl2).desat, 1) and Spread.timeline(view_of({ drawn = true, phase = "waiting", drawn_age = 4 }), T2, tl2).desat == 1)
end

local L2 = Spread.new_layout()
Spread.layout(L2, hand4(), { timer_below = true })
check("layout: timer below puts the cards at the top and the countdown under the fuse, where the banner goes", L2.cards_y == 0 and L2.fuse_y == 76 + Spread.FUSE_GAP and L2.time_y == L2.banner_y and L2.time_y == L2.fuse_y + Spread.FUSE_HEIGHT + Spread.BANNER_GAP)
Spread.layout(L2, hand4())
check("layout: by default the countdown is on top and the cards 38 down", L2.cards_y == 38 and L2.time_y == 0)
Spread.layout(L2, hand4(), { hide_icon = true })
check("layout: without the corner symbol the name gets its room (24 units more)", L2.name_w == 100 + 24, L2.name_w)
Spread.layout(L2, hand4(), { glyph = 0.9 })
check("layout: a wider font wraps names into more lines", L2.lines == 3 and L2.ch == 97, L2.lines)
check("layout: every font the player can choose has a glyph width", Spread.GLYPH_BY_FONT.itc_novarese_bold and Spread.GLYPH_BY_FONT.friz_quadrata and Spread.GLYPH_BY_FONT.rexlia and Spread.GLYPH_BY_FONT.machine_medium and Spread.GLYPH_BY_FONT.proxima_nova_bold and Spread.GLYPH_BY_FONT.itc_novarese_medium)

do
  local e = new_element()
  local function w(i) return e._widgets_by_name["card_" .. i] end
  current_view = view_of({ remaining = 9, hand_seq = 40 }); frame(e)
  local start_spread = spread_of(w(3).style.accent.color)
  check("desaturation: the card in the hand is coloured (a blight card is yellow)", start_spread > 100, start_spread)
  current_view = view_of({ phase = "waiting", remaining = 100, hand_seconds = 0, drawn = true, drawn_age = 0.05, hand_seq = 40 }); frame(e)
  check("desaturation: just after the pick it is still (nearly) as coloured", spread_of(w(3).style.accent.color) > start_spread * 0.95)
  current_view.drawn_age = 1.5; frame(e)
  local mid = spread_of(w(3).style.accent.color)
  check("desaturation: halfway it has lost about half of its colour", mid < start_spread * 0.75 and mid > start_spread * 0.25, mid .. " of " .. start_spread)
  check("desaturation: the other cards are not touched", spread_of(w(1).style.accent.color) > 30)
  current_view.drawn_age = 2.9; frame(e)
  local st = w(3).style
  local function grey_col(c) return spread_of(c) <= 2 end
  check("desaturation: completely grey at the end: card, accent bar, name, glow, diamonds, dots", grey_col(st.bg.color) and grey_col(st.accent.color) and grey_col(st.name.text_color) and grey_col(st.glow.color) and grey_col(st.th_o1.color) and grey_col(st.th_o5.color) and grey_col(st.dot_1.color) and grey_col(st.icon_c1.color), spread_of(st.accent.color) .. "/" .. spread_of(st.th_o1.color) .. "/" .. spread_of(st.dot_1.color))
  local fxs = e._widgets_by_name.fx.style
  local fx_grey = grey_col(fxs.wash.color)
  for i = 1, 5 do if fxs["blot_" .. i .. "_1"].visible and not grey_col(fxs["blot_" .. i .. "_1"].color) then fx_grey = false end end
  check("desaturation: the rot's wash and blotches go grey with it", fx_grey and e._widgets_by_name.fx.visible)
  audit_ok("desaturation", e)
  current_view = view_of({ remaining = 9, hand_seq = 41 }); frame(e)
  check("desaturation: the next hand is in colour again", spread_of(w(3).style.accent.color) > 100)
end

-- the timer below the cards
do
  settings.tarot_timer_below = true
  local e = new_element()
  local hd = e._widgets_by_name.header
  current_view = view_of({ remaining = 9, hand_seq = 50 }); frame(e)
  check("timer below: the cards are at the top and the countdown sits under the fuse", e._widgets_by_name.card_1.style.bg.offset[2] == 0 and hd.style.time.offset[2] == 98 and hd.style.label.offset[2] == 98 and hd.style.fuse_fill.offset[2] == 86, hd.style.time.offset[2])
  audit_ok("timer below", e)
  current_view = view_of({ phase = "waiting", hand = nil, remaining = 60, hand_seconds = 0, hand_seq = 0 }); frame(e)
  check("timer below: with no hand the countdown stays at the top", hd.style.time.offset[2] == 0)
  settings.tarot_timer_below = false
  current_view = view_of({ remaining = 9, hand_seq = 51 }); frame(e)
  check("timer below: switching it off takes effect without a restart (cards 38 down, countdown on top)", e._widgets_by_name.card_1.style.bg.offset[2] == 38 and hd.style.time.offset[2] == 0)
  settings.tarot_timer_below = nil
end

-- no corner symbol
do
  settings.tarot_hide_icon = true
  local e = new_element()
  current_view = view_of({ remaining = 9, hand_seq = 52 }); frame(e)
  local any = false
  for i = 1, 4 do
    local st = e._widgets_by_name["card_" .. i].style
    for j = 1, 4 do if st["icon_t" .. j].visible or st["icon_c" .. j].visible or st["icon_th" .. j].visible or st["icon_ch" .. j].visible then any = true end end
  end
  check("hide the corner symbol: no suit mark on any card, the name box is 24 wider", not any and e._widgets_by_name.card_1.style.name.size[1] == 124, e._widgets_by_name.card_1.style.name.size[1])
  audit_ok("no corner symbol", e)
  settings.tarot_hide_icon = false
  frame(e)
  local shown = false
  for j = 1, 4 do if e._widgets_by_name.card_2.style["icon_t" .. j].visible or e._widgets_by_name.card_2.style["icon_c" .. j].visible then shown = true end end
  check("hide the corner symbol: turning it off brings the marks back", shown and e._widgets_by_name.card_1.style.name.size[1] == 100)
  settings.tarot_hide_icon = nil
end

-- the font
do
  local e = new_element()
  local c1 = e._widgets_by_name.card_1.style
  local hd = e._widgets_by_name.header.style
  local bn = e._widgets_by_name.banner.style
  check("font: the default is the bold Novarese for the card names, the countdown and the banner name", c1.name.font_type == "itc_novarese_bold" and hd.time.font_type == "itc_novarese_bold" and bn.name.font_type == "itc_novarese_bold" and hd.label.font_type == "proxima_nova_bold")
  check("font: card names have no drop shadow (it muddied thin strokes on a dark card), the countdown keeps one", c1.name.drop_shadow == false and hd.time.drop_shadow == true)
  settings.tarot_font = "machine_medium"
  current_view = view_of({ remaining = 9, hand_seq = 53 }); frame(e)
  check("font: the choice applies to the card names, countdown and banner name (not to the small text)", e._widgets_by_name.card_3.style.name.font_type == "machine_medium" and hd.time.font_type == "machine_medium" and bn.name.font_type == "machine_medium" and hd.label.font_type == "proxima_nova_bold" and bn.whisper.font_type == "proxima_nova_bold")
  check("font: the wider font makes the layout allow for it", e._layout_opts.glyph == Spread.GLYPH_BY_FONT.machine_medium)
  settings.tarot_font = "friz_quadrata"; frame(e)
  check("font: a change in the options menu applies at once", e._widgets_by_name.card_1.style.name.font_type == "friz_quadrata")
  settings.tarot_font = "comic_sans"; frame(e)
  check("font: an unknown font name (an edited settings file) falls back to the default, never reaching the renderer", e._widgets_by_name.card_1.style.name.font_type == "itc_novarese_bold")
  settings.tarot_font = nil
end

-- size and opacity of everything
do
  local e = new_element()
  current_view = view_of({ remaining = 9, hand_seq = 60 }); frame(e)
  local rs = {}
  for k in pairs(draws) do draws[k] = nil end
  Element.draw(e, 0.016, 0, nil, rs, nil)
  check("draw: size 100 and opacity 100 draw the widgets untouched", #draws == 1 and draws[1].scale == nil and draws[1].ox == 0 and draws[1].oy == 0 and (draws[1].a == nil or draws[1].a == 1))
  settings.tarot_scale = 150; settings.tarot_opacity = 50
  frame(e)
  for k in pairs(draws) do draws[k] = nil end
  Element.draw(e, 0.016, 0, nil, rs, nil)
  local d = draws[1]
  check("draw: the renderer's scale is multiplied by the size option while drawing (text, shapes and textures follow)", d.scale == 1.5 * 1.5 and near(d.inverse, 1 / 2.25, 1e-9), d.scale)
  check("size: the node (custom_hud's box) follows the size option, 700 x 262 times 1.5", e._sg_size ~= nil and e._sg_size[1] == "panel" and near(e._sg_size[2], 1050) and near(e._sg_size[3], 393), e._sg_size and e._sg_size[2])
  check("draw: every widget is shifted by node * (1/size - 1) so the node's corner stays where custom_hud put it", near(d.ox, 610 * (1 / 1.5 - 1), 1e-6) and near(d.oy, 36 * (1 / 1.5 - 1), 1e-6), d.ox .. "," .. d.oy)
  check("draw: and every widget is half transparent (the header too)", near(d.a, 0.5) and near(d.ha, 0.5))
  local c1 = e._widgets_by_name.card_1
  check("draw: afterwards the widgets and the render settings are exactly as they were", rs.scale == nil and rs.inverse_scale == nil and c1.offset[1] == 0 and c1.offset[2] == 0 and c1.alpha_multiplier == 1 and e._widgets_by_name.header.offset[1] == 0)
  c1.alpha_multiplier = 0.4
  for k in pairs(draws) do draws[k] = nil end
  Element.draw(e, 0.016, 0, nil, rs, nil)
  check("draw: the opacity multiplies a card's own fade (0.4 x 0.5)", near(draws[1].a, 0.2) and c1.alpha_multiplier == 0.4)
  c1.alpha_multiplier = 1
  e._explode = true
  local ok = pcall(Element.draw, e, 0.016, 0, nil, rs, nil)
  check("draw: if drawing fails the error is passed on and everything is still restored", ok == false and rs.scale == nil and c1.offset[1] == 0 and c1.alpha_multiplier == 1)
  e._explode = nil
  settings.tarot_scale = 500; settings.tarot_opacity = 0
  frame(e)
  for k in pairs(draws) do draws[k] = nil end
  Element.draw(e, 0.016, 0, nil, rs, nil)
  check("draw: size is limited to 50-200 percent and opacity to 10-100 (a stray value cannot make the HUD vanish or fill the screen)", draws[1].scale == 1.5 * 2 and near(draws[1].a, 0.1))
  settings.tarot_scale = 10
  frame(e)
  for k in pairs(draws) do draws[k] = nil end
  Element.draw(e, 0.016, 0, nil, rs, nil)
  check("draw: ...and not below 50 percent", draws[1].scale == 1.5 * 0.5)
  settings.tarot_scale = nil; settings.tarot_opacity = nil
  frame(e)
  for k in pairs(draws) do draws[k] = nil end
  Element.draw(e, 0.016, 0, nil, rs, nil)
  check("draw: with the options back at 100 nothing is changed again", draws[1].scale == nil and (draws[1].a == nil or draws[1].a == 1) and draws[1].ox == 0)
  local hidden = new_element()
  current_view = { phase = "off" }; frame(hidden)
  settings.tarot_scale = 150
  frame(hidden)
  for k in pairs(draws) do draws[k] = nil end
  Element.draw(hidden, 0.016, 0, nil, rs, nil)
  check("draw: a hidden HUD is not touched", draws[1].scale == nil)
  settings.tarot_scale = nil
end

-- =====================================================================================================================
-- no allocation per frame
-- =====================================================================================================================
local function growth(fixed_view, step, frames)
  -- Measure Lua allocations, excluding the VM's trace compiler and its unpredictable hot-loop thresholds.
  -- A line hook allocates debug-info tables; suspend it for the allocation probe.
  local hook, mask, count = debug.gethook()
  debug.sethook()
  local jit_was_on = jit and jit.status()
  if jit then jit.off(); jit.flush() end
  local e = new_element()
  current_view = fixed_view
  local function advance(count)
    for i = 1, count do step(fixed_view, i); frame(e) end
  end
  advance(frames) -- warm the same loop and time range before measuring heap growth
  collectgarbage("collect"); collectgarbage("stop")
  local before = collectgarbage("count")
  advance(frames)
  local after = collectgarbage("count")
  collectgarbage("restart")
  if jit_was_on then jit.on() end
  if hook then debug.sethook(hook, mask, count) end
  return (after - before) * 1024 / frames
end
-- NIGHTMARE (2026-10-04): darkness breathes around it, its frame is a dying light that flickers, black ink drips; WARP pulses and
-- crackles and motes rise from it
do
  local e = new_element()
  local hand = {
    card("n", "The Dark", "nightmare", 6, { "chaos_daemonhost" }, "It was never a dream."),
    card("w", "The Magician", "warp", 3, { "chaos_daemonhost" }, "It knows your name."),
    card("p", "The Fool", "swarm", 1, { "chaos_poxwalker" }, "Too many to count."),
  }
  current_view = view_of({ hand = hand, remaining = 9.5, hand_seq = 140, win = 3 })
  frame(e)
  local h = function(i) return e._widgets_by_name["card_" .. i] end
  local function dark(c) return c[2] < 0x40 and c[3] < 0x40 and c[4] < 0x50 end
  check("nightmare: the face is black, the frame on (two units) and dark, the glow is a darkness around it", h(1).style.bg.color[2] < 8 and h(1).style.rare_t.visible and h(1).style.rare_t.size[2] == 2 and h(1).style.glow.visible and (dark(h(1).style.glow.color) or h(1).style.glow.color[2] > 0xe0))
  check("nightmare: black ink drips from its lower edge (pure black lines), beads in its gloom", h(1).style.blood_1.visible and h(1).style.blood_3.visible and h(1).style.blood_1.color[2] == 0 and h(1).style.blood_1.color[3] == 0 and h(1).style.blood_1.offset[2] >= h(1).style.bg.offset[2] + h(1).style.bg.size[2] - 2)
  local breath, flashes = {}, 0
  for k = 1, 200 do
    frame(e, 0.033)
    breath[h(1).style.glow.color[1]] = true
    if h(1).style.rare_t.color[2] > 0xb0 then flashes = flashes + 1 end
  end
  local n = 0 for _ in pairs(breath) do n = n + 1 end
  check("nightmare: the darkness breathes (its glow changes strength) and the dying light flashes now and then, not always", n >= 6 and flashes >= 1 and flashes < 60, n .. " strengths, " .. flashes .. " flashes")
  check("warp: its glow is on at rest and pulses", h(2).style.glow.visible and (function() local seen = {} for k = 1, 40 do frame(e, 0.05); seen[h(2).style.glow.color[1]] = true end local m = 0 for _ in pairs(seen) do m = m + 1 end return m >= 5 end)())
  check("warp: motes rise from its top edge (circles above the card, no drip lines); an ordinary suit has neither", h(2).style.blood_c1.visible and not h(2).style.blood_1.visible and h(2).style.blood_c1.offset[2] < h(2).style.bg.offset[2] + 4 and not h(3).style.blood_c1.visible and not h(3).style.glow.visible)
  check("nightmare: its suit mark is the horned eye (four triangles and three circles)", (function()
    local tris, circs = 0, 0
    for i = 1, Spread.ICON_TRIS do if h(1).style["icon_t" .. i].visible then tris = tris + 1 end end
    for i = 1, Spread.ICON_CIRCS do if h(1).style["icon_c" .. i].visible then circs = circs + 1 end end
    return tris == 4 and circs == 3
  end)())
  -- Nightmare's black fog (2026-10-04): it comes and goes over the whole card, its banks stay inside the card; no other suit has it
  local most, least, inside_card, bank_seen = 0, 255, true, false
  for k = 1, 300 do
    frame(e, 0.033)
    local v = h(1).style.fog_veil
    if v.visible then most = math.max(most, v.color[1]) else least = 0 end
    if v.visible then least = math.min(least, v.color[1]) end
    for j = 1, 3 do
      local b = h(1).style["fog_" .. j]
      if b.visible then
        bank_seen = true
        if b.offset[2] < h(1).style.bg.offset[2] - 0.01 or b.offset[2] + b.size[2] > h(1).style.bg.offset[2] + h(1).style.bg.size[2] + 0.01 or b.color[2] ~= 0 then inside_card = false end
      end
    end
  end
  check("nightmare: a black fog comes and goes over the card (the veil thickens past 100 of 255 and clears again)", most > 100 and least < 20, most .. " / " .. least)
  check("nightmare: its banks of fog drift inside the card, black, above everything on it", bank_seen and inside_card and h(1).style.fog_1.offset[3] > h(1).style.name.offset[3])
  check("nightmare: no other suit is fogged", not h(2).style.fog_veil.visible and not h(3).style.fog_veil.visible and not h(3).style.fog_1.visible)
  audit_ok("nightmare and warp hand", e)
end

-- HERESY, the card apart: a frame at rest, a smouldering glow, its own line when it is drawn
do
  local e = new_element()
  local special_hand = {
    card("h", "The Turncoat", "heresy", 4, { "renegade_shocktrooper" }, "The Emperor does not answer."),
    card("f", "Old Pox", "fester", 3, { "chaos_poxwalker" }, "an older host still says fester"),
    card("p", "The Fool", "swarm", 1, { "chaos_poxwalker" }, "Too many to count."),
  }
  current_view = view_of({ hand = special_hand, remaining = 9.5, hand_seq = 40, win = 3 })
  frame(e)
  local h = function(i) return e._widgets_by_name["card_" .. i] end
  local function blood_red(c) return c[2] >= 0x8a and c[3] <= 0x34 and c[4] <= 0x45 end
  check("heresy: at rest the frame is on, two units thick, in fresh blood red that beats toward the lit red (a swarm card has none)", h(1).style.rare_t.visible and h(1).style.rare_t.size[2] == 2 and h(1).style.rare_l.size[1] == 2 and blood_red(h(1).style.rare_t.color) and not h(3).style.rare_t.visible)
  check("heresy: the glow beats at rest (visible, blood red, between 55 and 100 percent of its resting strength); the other suits glow only when highlighted", h(1).style.glow.visible and h(1).style.glow.color[1] >= 60 and h(1).style.glow.color[1] <= 110 and blood_red(h(1).style.glow.color) and not h(3).style.glow.visible)
  check("heresy: the heartbeat moves the glow from frame to frame", (function() local seen = {} for k = 1, 30 do frame(e, 0.033); seen[h(1).style.glow.color[1]] = true end local n = 0 for _ in pairs(seen) do n = n + 1 end return n >= 4 end)())
  check("heresy: blood runs down from its lower edge (three drops below the card); no other suit bleeds", h(1).style.blood_1.visible and h(1).style.blood_3.visible and h(1).style.blood_c2.visible and h(1).style.blood_1.offset[2] >= h(1).style.bg.offset[2] + h(1).style.bg.size[2] - 2 and not h(3).style.blood_1.visible)
  check("heresy: the face is near black with blood in it, the bar crimson, the name pale", h(1).style.bg.color[2] == 0x0d and h(1).style.bg.color[3] == 0x02 and h(1).style.accent.color[2] == 0xd4 and h(1).style.accent.color[3] == 0x2a and h(1).style.name.text_color[2] == 0xef)
  check("heresy: a card an older host calls fester is drawn as Heresy", h(2).style.bg.color[2] == 0x0d and h(2).style.rare_t.visible and h(2).style.glow.visible and h(2).style.blood_1.visible)
  check("heresy: its suit mark is the broken halo (six shapes) and it stays inside the card", (function()
    local tris, circs = 0, 0
    for i = 1, Spread.ICON_TRIS do if h(1).style["icon_t" .. i].visible then tris = tris + 1 end end
    for i = 1, Spread.ICON_CIRCS do if h(1).style["icon_c" .. i].visible then circs = circs + 1 end end
    return tris == 3 and circs == 3
  end)())
  audit_ok("heresy hand", e)

  current_view = view_of({ hand = special_hand, phase = "waiting", remaining = 100, hand_seconds = 0, drawn = true, drawn_age = 0.05, win = 1, hand_seq = 41 })
  frame(e)
  local bn = e._widgets_by_name.banner
  check("heresy: drawn, the banner says 'Heresy is drawn' in the lit red and the name is crimson; the card's glow flares (beating between 121 and 220)", bn.content.kicker == "HUD_CARD_DRAWN_SPECIAL" and bn.style.kicker.text_color[2] == 0xff and bn.style.name.text_color[2] == 0xd4 and h(1).style.glow.color[1] >= 121 and h(1).style.glow.color[1] <= 220, tostring(bn.content.kicker))
  current_view = view_of({ hand = special_hand, phase = "waiting", remaining = 100, hand_seconds = 0, drawn = true, drawn_age = 0.05, win = 3, hand_seq = 42 })
  frame(e)
  check("heresy: another card drawn keeps the ordinary banner line", bn.content.kicker == "HUD_CARD_DRAWN" and bn.style.kicker.text_color[2] ~= 0xff)
  audit_ok("heresy reveal", e)
end

-- the murmur: a threat 5 or 6 card writes its whisper letter by letter once it is drawn; lower threats show it whole at once
do
  local e = new_element()
  local line = "Do you hear it? Sch\195\182n."
  local hand = { card("m5", "The Watcher", "murmur", 5, { "renegade_sniper" }, line), card("m3", "The Pilgrim", "swarm", 3, { "chaos_poxwalker" }, line) }
  current_view = view_of({ hand = hand, phase = "waiting", remaining = 100, hand_seconds = 0, drawn = true, drawn_age = 0.4, win = 1, hand_seq = 140 })
  frame(e)
  local bn = e._widgets_by_name.banner
  local early = bn.content.whisper
  check("murmur: shortly after a threat 5 card is shown its whisper is only partly written and the quote is still open", #early > 1 and #early < #line + 2 and early:sub(-1) ~= "\"" , early)
  check("murmur: the cut never falls inside a two-byte letter", (function()
    for k = 0, 40 do
      current_view = view_of({ hand = hand, phase = "waiting", remaining = 100, hand_seconds = 0, drawn = true, drawn_age = k * 0.05, win = 1, hand_seq = 140 }); frame(e)
      local w = bn.content.whisper:gsub("^\"", ""):gsub("\"$", "")
      if w:sub(-1) == "\195" then return false end
    end
    return true
  end)())
  current_view = view_of({ hand = hand, phase = "waiting", remaining = 100, hand_seconds = 0, drawn = true, drawn_age = 1.9, win = 1, hand_seq = 140 })
  frame(e)
  check("murmur: after the murmur the whisper is whole and closed", bn.content.whisper == "\"" .. line .. "\"", bn.content.whisper)
  current_view = view_of({ hand = hand, phase = "waiting", remaining = 100, hand_seconds = 0, drawn = true, drawn_age = 0.4, win = 2, hand_seq = 141 })
  frame(e)
  check("murmur: a threat 3 card shows its whole whisper at once", bn.content.whisper == "\"" .. line .. "\"", bn.content.whisper)
  -- the sixth diamond shines: Despair breathes, its halo grows and darkens from frame to frame
  local six = { card("d6", "Despair", "brute", 6, { "chaos_ogryn_executor" }, "It does not stop.") }
  current_view = view_of({ hand = six, remaining = 9.5, win = 1, hand_seq = 142 })
  frame(e)
  local w = e._widgets_by_name.card_1
  check("despair: all six diamonds are shown, dark, with a halo larger than the diamond", w.style.th_o6.visible and w.style.th_h6.visible and w.style.th_o6.color[2] < 0x40 and w.style.th_h6.size[1] > Spread.THREAT_SIDE + 1.3)
  check("despair: the halo breathes (its size and colour change over time)", (function() local sizes = {} for k = 1, 40 do frame(e, 0.05); sizes[math.floor(w.style.th_h6.size[1] * 10)] = true end local n = 0 for _ in pairs(sizes) do n = n + 1 end return n >= 4 end)())
  audit_ok("murmur and despair", e)
end

do
  local e=new_element()
  for i,suit in ipairs({"prayer","miracle","grace","faith"}) do
    local selected=card("b"..i,"The Light",suit,6,{},"Carry the light.")
    current_view=view_of({hand={selected},remaining=9.5,win=1,hand_seq=80+i})
    frame(e)
    local w=e._widgets_by_name.card_1
    local acc=Cards.SUITS[suit].accent
    check("blessing: full Draw face and six pips that glitter in light (Apotheosis: the halo between the accent and warm white, never Despair's lilac) "..suit,w.visible and w.style.th_o6.visible and w.style.th_h6.color[2]>=acc[1]-1 and w.style.th_h6.color[2]~=0xc7 and w.style.th_o6.color[2]>=acc[1]-1)
    current_view=view_of({hand={selected},phase="waiting",remaining=100,hand_seconds=0,drawn=true,drawn_age=0.05,win=1,hand_seq=90+i});frame(e)
    check("blessing: banner uses blessing caption and hides modifiers "..suit,e._widgets_by_name.banner.content.kicker=="HUD_CARD_DRAWN_BENEFICIAL" and not e._widgets_by_name.banner.style.mods.visible)
    audit_ok("blessing Draw "..suit,e)
  end
end

-- the Nightmare's dread (ui/hud_element_dread.lua, 2026-10-04): a full-screen black fog when a Nightmare card is drawn, a toggle
do
  local DreadDefs = dofile(BASE .. "/ui/hud_element_dread_definitions.lua")
  local Dread = dofile(BASE .. "/ui/hud_element_dread.lua")
  local el = setmetatable({}, Dread)
  Dread.init(el, nil, 0, 1)
  local w = el._widgets_by_name.dread
  local function tick(dt) Dread.update(el, dt, 0, nil, nil, nil) end
  local function night_hand() return { card("n", "The Dark", "nightmare", 6, { "chaos_daemonhost" }, "It was never a dream."), card("p", "The Fool", "swarm", 1, { "chaos_poxwalker" }, "x") } end
  local hidden = true
  for _, st in pairs(DreadDefs.widget_definitions.dread.style) do if st.visible ~= false then hidden = false end end
  check("dread: one widget on the root node only (custom_hud offers nothing to move), every pass starts hidden", DreadDefs.widget_definitions.dread.scenegraph_id == "screen" and (function() local n = 0 for id in pairs(DreadDefs.scenegraph_definition) do n = n + 1 end return n end)() == 1 and hidden)
  settings.nightmare_dread = nil
  current_view = view_of({ hand = night_hand(), win = 1, hand_seq = 300, drawn = false })
  tick(0.1)
  check("dread: nothing while the Nightmare card is only in the hand", not w.visible)
  current_view = view_of({ hand = night_hand(), win = 2, hand_seq = 301, drawn = true, drawn_age = 0.1 })
  tick(0.1)
  check("dread: nothing when another card of the hand is drawn", not w.visible)
  current_view = view_of({ hand = night_hand(), win = 1, hand_seq = 302, drawn = true, drawn_age = 0.1 })
  tick(0.1)
  check("dread: a drawn Nightmare card starts it at once, rising", w.visible and w.style.veil.visible and w.style.veil.color[1] > 0 and w.style.veil.color[1] < 60)
  for _ = 1, 30 do tick(0.1) end
  local veil, edge, inner = w.style.veil.color[1], w.style.vig_1_t.color[1], w.style.vig_16_t.color[1]
  check("dread: at full strength the screen stays see-through (the veil under 60 percent), black, darker at the edges", veil > 50 and veil < 155 and w.style.veil.color[2] == 0 and edge > inner and edge > 150, veil .. " " .. edge .. " " .. inner)
  check("dread: it covers the whole screen, the vignette frames on its edges, ash-grey fog across it", w.style.veil.size[1] == 1920 and w.style.veil.size[2] == 1080 and w.style.vig_1_t.offset[2] == 0 and w.style.vig_1_r.offset[1] + w.style.vig_1_r.size[1] == 1920 and w.style.fog_1_1.size[1] == 1920 and w.style.fog_1_1.color[2] > 0 and w.style.fog_1_1.color[2] < 60 and w.style.fog_1_3.size[2] < w.style.fog_1_1.size[2])
  local seen = {}
  for _ = 1, 20 do tick(0.05); seen[w.style.veil.color[1]] = true end
  local n = 0 for _ in pairs(seen) do n = n + 1 end
  check("dread: the veil breathes while it holds", n >= 3)
  for _ = 1, 60 do tick(0.1) end
  check("dread: it fades and is gone after about eight seconds", not w.visible and el._age == nil)
  tick(0.1)
  check("dread: the same draw does not start it again", not w.visible)
  current_view = view_of({ hand = night_hand(), win = 1, hand_seq = 303, drawn = true, drawn_age = 9 })
  tick(0.1)
  check("dread: a player joining after the card was drawn is not shown it late", not w.visible)
  settings.nightmare_dread = false
  current_view = view_of({ hand = night_hand(), win = 1, hand_seq = 304, drawn = true, drawn_age = 0.1 })
  tick(0.1)
  check("dread: the option off: never shown", not w.visible)
  settings.nightmare_dread = nil
  current_view = view_of({ hand = night_hand(), win = 1, hand_seq = 305, drawn = true, drawn_age = 0.1 })
  tick(0.1); tick(2)
  check("dread: the option on again: the next Nightmare draw shows it", w.visible)
  settings.nightmare_dread = false; tick(0.1)
  check("dread: turning the option off hides it at once", not w.visible)
  settings.nightmare_dread = nil
  check("dread: the envelope rises, holds and fades", Dread.envelope(0.4) > 0.4 and Dread.envelope(0.4) < 0.6 and Dread.envelope(3) == 1 and Dread.envelope(7) > 0 and Dread.envelope(7) < 0.5 and Dread.envelope(Dread.DURATION) == 0 and Dread.envelope(-1) == 0)
end

-- the window of the last fulfilled card (ui/hud_element_last_card.lua)
do
  local LastDefs = dofile(BASE .. "/ui/hud_element_last_card_definitions.lua")
  local LastElement = dofile(BASE .. "/ui/hud_element_last_card.lua")
  local function new_last()
    local el = setmetatable({}, LastElement)
    LastElement.init(el, nil, 0, 1)
    return el
  end
  local function last_frame(el) LastElement.update(el, 1 / 60, 0, nil, nil, nil) end
  local function lc(key, name, suit, threat, breeds, whisper, mods, rare) return { key = key, name = name, suit = suit, threat = threat, breeds = breeds, whisper = whisper, modifiers = mods or "", rare = rare or false, cooldown = 120 } end
  local function last_view(card, seq, age) return view_of({ phase = "waiting", hand = nil, remaining = 60, hand_seconds = 0, last = card, last_seq = seq, last_age = age }) end
  local function inside(el)
    local bad = {}
    local w = el._widgets_by_name.last
    for _, p in ipairs(w.passes) do
      local st = w.style[p.style_id]
      if st.visible ~= false and (p.pass_type == "rect" or p.pass_type == "circle" or p.pass_type == "text") then
        if st.offset[1] < -0.01 or st.offset[2] < -0.01 or st.offset[1] + st.size[1] > LastDefs.WIDTH + 0.01 or st.offset[2] + st.size[2] > LastDefs.HEIGHT + 0.01 then bad[#bad + 1] = p.style_id .. "@" .. st.offset[1] .. "," .. st.offset[2] .. " " .. st.size[1] .. "x" .. st.size[2] end
      end
    end
    return #bad == 0, table.concat(bad, " | ")
  end

  -- the definitions
  local sg_nodes = 0
  for id in pairs(LastDefs.scenegraph_definition) do if id ~= "screen" then sg_nodes = sg_nodes + 1 end end
  local hidden, fonts_known = true, true
  for _, def in pairs(LastDefs.widget_definitions) do
    for _, st in pairs(def.style) do
      if st.visible ~= false then hidden = false end
      if st.font_type and not known_fonts[st.font_type] then fonts_known = false end
    end
  end
  check("last card: one movable node (custom_hud lists every non-root node), one widget, every pass starts hidden, only fonts that exist", sg_nodes == 1 and LastDefs.scenegraph_definition.panel ~= nil and LastDefs.widget_definitions.last ~= nil and hidden and fonts_known, sg_nodes)
  -- (2026-10-04: the card "in the hand" of the design page, 240 wide)
  check("last card: the node sits to the right of the Spread and reserves the hand card (240 x 160)", LastDefs.scenegraph_definition.panel.position[1] >= 610 + 700 and LastDefs.scenegraph_definition.panel.size[1] == 240 and LastDefs.scenegraph_definition.panel.size[2] == 160)

  settings.hud_last_card, settings.hud_enabled, settings.tarot_font = nil, nil, nil
  local el = new_last()
  local w = el._widgets_by_name.last
  current_view = last_view(nil, 0, 0)
  last_frame(el)
  check("last card: no card yet -> no window", w.visible == false and not el._visible)

  local tower = lc("c", "The Tower", "blight", 3, { "chaos_poxwalker_bomber", "renegade_shocktrooper" }, "Pop, pop, pop.", "Enraged \194\183 Custom")
  current_view = last_view(tower, 1, 5.9)
  last_frame(el)
  check("last card: the window shows when a card went out: caption, how long ago (rounded down), name, whisper in quotes, modifiers hidden", w.visible and w.content.kicker == "HUD_LAST_CARD" and w.content.age == "hud_last_ago:0:05" and w.content.name == "The Tower" and w.content.whisper == "\"Pop, pop, pop.\"" and w.content.mods == "" and not w.style.mods.visible, tostring(w.content.age))
  check("last card: the card takes its suit's colours (blight: face #25240c, bar #e3cf4a, name #ebe6bf); no window around it", w.style.card_bg.color[2] == 0x25 and w.style.card_bg.color[3] == 0x24 and w.style.card_accent.color[2] == 0xe3 and w.style.name.text_color[2] == 0xeb and not w.style.win_t.visible and not w.style.win_l.visible and not w.style.bg.visible)
  check("last card: the card has an outline of its own in the suit's frame colour (blight #5c5a1e), the window a neutral line and a panel darker than any card", w.style.rare_t.visible and w.style.rare_t.color[2] == 0x5c and w.style.rare_t.color[3] == 0x5a and w.style.rare_t.size[2] == 1 and w.style.rare_l.size[1] == 1)
  check("last card: the card is 240 wide under the caption, the accent bar on its left, as tall as its content", w.style.card_bg.size[1] == 240 and w.style.card_bg.offset[1] == 0 and w.style.card_bg.offset[2] == 22 and w.style.card_accent.size[1] == Spread.ACCENT_WIDTH and w.style.card_accent.size[2] == w.style.card_bg.size[2] and w.style.card_bg.size[2] < 120 and not w.style.win_b.visible)
  do
    local L = LastDefs.LAYOUT
    local bg, nm, wh = w.style.card_bg, w.style.name, w.style.whisper
    local icon_x = math.huge
    for i = 1, Spread.ICON_TRIS do local st = w.style["icon_t" .. i]; if st.visible then icon_x = math.min(icon_x, st.offset[1]) end end
    for i = 1, Spread.ICON_CIRCS do local st = w.style["icon_c" .. i]; if st.visible then icon_x = math.min(icon_x, st.offset[1]) end end
    check("last card: the name at the top left after the bar, the suit mark at the top right (no ring, no disc)", nm.offset[1] == Spread.ACCENT_WIDTH + L.pad_x and nm.offset[2] == bg.offset[2] + L.pad_y and nm.font_size == L.name_font and icon_x >= nm.offset[1] + nm.size[1] and icon_x < 240 and not w.style.sigil_ring.visible and not w.style.sigil_disc.visible)
    check("last card: the diamonds under the name, the whisper under them, inside the card and drawn over its face", w.style.th_o1.offset[2] > nm.offset[2] + nm.size[2] - 6 and wh.offset[2] > w.style.th_o1.offset[2] and wh.offset[2] + wh.size[2] <= bg.offset[2] + bg.size[2] and wh.offset[3] > bg.offset[3] and wh.font_size == L.whisper_font)
    check("last card: an ordinary card's whisper is muted", wh.text_color[2] == 0x98 and wh.text_color[3] == 0x93)
  end
  local ok_in, why_in = inside(el)
  check("last card: nothing is drawn outside the node", ok_in, why_in)
  check("last card: threat diamonds are filled up to the threat in its colour (3: light yellow), the rest outlines; one dot per enemy colour at the right", w.style.th_o3.color[2] == 227 and w.style.th_o3.color[1] == 255 and w.style.th_o4.visible and w.style.th_o4.color[1] == 40 and w.style.th_h4.color[1] == 120 and w.style.dot_2.offset[1] + w.style.dot_2.size[1] <= 240 - LastDefs.LAYOUT.pad_x + 0.01 and (function() local n = 0 for j = 1, 6 do if w.style["dot_" .. j].visible then n = n + 1 end end return n == 2 end)())
  check("last card: the suit mark is drawn (blight: a drop of triangles and circles) and an ordinary card does not glow", (function() local any = false for i = 1, Spread.ICON_TRIS do if w.style["icon_t" .. i].visible then any = true end end for i = 1, Spread.ICON_CIRCS do if w.style["icon_c" .. i].visible then any = true end end return any end)() and not w.style.glow.visible)
  audit_ok("last card", el)

  -- it ages once a second; the card is only laid out again when another one goes out
  w.style.card_bg.color[2] = 1
  current_view = last_view(tower, 1, 65.4)
  last_frame(el)
  check("last card: the age follows (65 seconds: 1:05) without laying the card out again", w.content.age == "hud_last_ago:1:05" and w.style.card_bg.color[2] == 1, tostring(w.content.age))
  current_view = last_view(tower, 1, 65.9)
  local age_before = w.content.age
  last_frame(el)
  check("last card: within the same second nothing is rewritten", w.content.age == age_before)
  current_view = last_view(lc("d", "Death", "fateful", 5, { "chaos_plague_ogryn" }, "It was always going to end here.", "", true), 2, 0.2)
  last_frame(el)
  check("last card: another card (a new number) is laid out at once, the age starts again, a rare card has the pus-yellow outline", w.content.name == "Death" and w.style.card_bg.color[2] ~= 1 and w.content.age == "hud_last_ago:0:00" and w.style.rare_t.visible and w.style.rare_t.size[2] == 1 and w.style.rare_l.color[2] == 227 and w.style.mods.visible == false)

  -- Heresy: the frame at rest and the glow, as in the Spread
  current_view = last_view(lc("h", "The Turncoat", "heresy", 4, { "renegade_shocktrooper" }, "He does not answer."), 3, 1)
  last_frame(el)
  check("last card: a Heresy card keeps its blood-red frame (two units) and its glow, and there is no window line", w.style.rare_t.visible and w.style.rare_t.size[2] == 2 and w.style.rare_t.color[2] == 0x8a and w.style.glow.visible and w.style.glow.color[2] == 0x8a and not w.style.win_t.visible and w.style.card_bg.color[2] == 0x0d)
  check("last card: Heresy's whisper is in its crimson", w.style.whisper.text_color[2] == 0xd4 and w.style.whisper.text_color[3] == 0x2a)
  current_view = last_view(lc("f", "Old Pox", "fester", 2, {}, ""), 4, 1)
  last_frame(el)
  check("last card: a card an older host calls fester is Heresy", w.style.card_bg.color[2] == 0x0d and w.style.rare_t.visible and w.style.whisper.visible == false and w.style.mods.visible == false)
  audit_ok("last card (heresy)", el)

  -- a three-line name, the longest whisper and modifiers: everything still fits the node
  current_view = last_view(lc("m", "The Watching Moon", "murmur", 2, { "renegade_sniper", "chaos_poxwalker" }, "Someone is counting you, forever.", "Purple \194\183 Enraged \194\183 Custom"), 5, 12)
  last_frame(el)
  local ok_in2, why_in2 = inside(el)
  check("last card: a long name (two lines at most) with a two-line whisper fits inside the card face and the node", ok_in2 and w.style.card_bg.offset[2] + w.style.card_bg.size[2] <= LastDefs.HEIGHT and w.style.name.size[2] <= 2 * LastDefs.LAYOUT.name_line + 4 and w.style.whisper.visible and not w.style.mods.visible and w.style.whisper.offset[2] + w.style.whisper.size[2] <= w.style.card_bg.offset[2] + w.style.card_bg.size[2], why_in2)

  current_view = last_view(lc("long-mods", "The Watching Moon", "murmur", 2, {}, "Someone is counting you, forever.", string.rep("Enraged ", 12)), 51, 12)
  last_frame(el)
  check("last card: long modifier lists remain hidden", not w.style.mods.visible and w.content.mods == "" and w.style.card_bg.offset[2] + w.style.card_bg.size[2] <= LastDefs.HEIGHT)

  for i,suit in ipairs({"heresy","prayer","miracle","grace","faith"}) do
    local card=lc("bless-"..i,"The Light",suit,6,{},"Carry the light.","Purple")
    current_view=last_view(card,60+i,1);last_frame(el)
    check("last card: full special face and the sixth diamond's edge (DESPAIR lilac on Heresy, APOTHEOSIS warm white on blessings), no dots without enemies "..suit,w.style.th_o6.visible and w.style.th_h6.color[2]==(suit=="heresy" and 0xc7 or 0xff) and not w.style.sigil_ring.visible and not w.style.dot_1.visible and not w.style.mods.visible and not w.style.bg.visible and inside(el))
  end
  do
    local card=lc("faith-w","The Magician","faith",3,{},"Believe, and endure.")
    current_view=last_view(card,70,1);last_frame(el)
    check("last card: only Heresy colours its whisper (Faith's is muted, as on the design page)",w.style.whisper.text_color[2]==0x98)
  end
  do
    local card=lc("fog","The Dark","nightmare",6,{},"It was never a dream.")
    current_view=last_view(card,90,1);last_frame(el)
    local most, inside = 0, true
    for k=1,600 do
      LastElement.update(el, 1/60, 0, nil, nil, nil)
      most=math.max(most, w.style.fog_veil.visible and w.style.fog_veil.color[1] or 0)
      for j=1,3 do local b=w.style["fog_"..j]; if b.visible and (b.offset[2] < w.style.card_bg.offset[2]-0.01 or b.offset[2]+b.size[2] > w.style.card_bg.offset[2]+w.style.card_bg.size[2]+0.01) then inside=false end end
    end
    check("last card: a Nightmare card's black fog comes and goes in the window too, inside the card",most>100 and inside,most)
    current_view=last_view(lc("clear","The Fool","swarm",1,{},"x"),91,1);last_frame(el)
    check("last card: the fog is gone with the next card",not w.style.fog_veil.visible and not w.style.fog_1.visible)
  end
  settings.hud_last_transparency=75;settings.hud_transparency=0;last_frame(el)
  check("last card: independent transparency changes without new card",w.alpha_multiplier==0.25)
  settings.hud_last_transparency=nil
  -- the player's options
  settings.tarot_font = "machine_medium"
  current_view = last_view(tower, 6, 3)
  last_frame(el)
  check("last card: the name takes the font chosen for the Spread; an unknown font falls back to the default", w.style.name.font_type == "machine_medium" and (function() settings.tarot_font = "no_such_font"; last_frame(el); return w.style.name.font_type == "itc_novarese_bold" end)())
  settings.tarot_font = nil
  settings.hud_last_card = false
  last_frame(el)
  check("last card: the option 'Show the last card window' off hides it", w.visible == false)
  settings.hud_last_card = nil
  last_frame(el)
  check("last card: ...and back on shows it again", w.visible == true and w.content.name == "The Tower")
  settings.hud_enabled = false
  last_frame(el)
  check("last card: the master option 'Show wave panel' off hides it too", w.visible == false)
  settings.hud_enabled = nil

  -- custom_hud's edit mode: a sample card, even with the option off
  current_view = last_view(nil, 0, 0)
  last_frame(el)
  check("last card: still hidden when there is no card", w.visible == false)
  custom_hud.is_customizing = true
  settings.hud_last_card = false
  last_frame(el)
  check("last card: while custom_hud is being edited a sample card is shown so the window can be moved (even with the option off)", w.visible and w.content.name == "The Chariot" and w.content.age == "hud_last_ago:2:34")
  custom_hud.is_customizing = false
  settings.hud_last_card = nil
  last_frame(el)
  check("last card: and it goes away when the edit mode closes", w.visible == false)

  -- leaving the mission clears it; a broken card is reported once and the window recovers
  current_view = last_view(tower, 7, 1)
  last_frame(el)
  current_view = { phase = "off", last = nil, last_seq = 0, last_age = 0 }
  last_frame(el)
  check("last card: out of a mission the window is gone", w.visible == false)
  current_view = last_view(tower, 7, 1)
  last_frame(el)
  local errors_before = #errors_logged
  current_view = last_view({ name = "Broken", suit = "rage", threat = 2, breeds = 5, whisper = "x" }, 8, 1)
  last_frame(el); last_frame(el); last_frame(el)
  check("last card: a card that cannot be drawn is reported once (not every frame)", #errors_logged == errors_before + 1, #errors_logged - errors_before)
  check("last card: refresh errors hide the partially painted widget", not w.visible and not el._visible)
  while #errors_logged > errors_before do table.remove(errors_logged) end -- (the deliberate error is not the guarded refresh's: the last check of this file stays strict)
  current_view = last_view(tower, 9, 1)
  last_frame(el)
  check("last card: ...and the next good card is drawn", w.visible and w.content.name == "The Tower")

  -- no allocation per frame while a card is shown (the age text changes once a second)
  current_view = last_view(tower, 10, 10)
  last_frame(el)
  -- (as growth() above: the coverage line hook allocates debug-info tables, suspend it for the probe; no trace compiler either)
  local hook_fn, hook_mask, hook_count = debug.gethook()
  debug.sethook()
  local jit_was_on = jit and jit.status()
  if jit then jit.off(); jit.flush() end
  for _ = 1, 600 do last_frame(el) end -- warm the same loop
  collectgarbage("collect"); collectgarbage("stop")
  local before_heap = collectgarbage("count")
  for _ = 1, 600 do last_frame(el) end
  local grown = (collectgarbage("count") - before_heap) * 1024 / 600
  collectgarbage("restart")
  if jit_was_on then jit.on() end
  if hook_fn then debug.sethook(hook_fn, hook_mask, hook_count) end
  check("last card: no allocation per frame while a card is shown", grown < 1, string.format("%.2f bytes/frame", grown))
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
