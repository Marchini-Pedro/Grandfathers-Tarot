"""Twins (twins/twins.lua, twins/cosmetics.lua; merged from SoloPlayPurpleStimms 2026-10-07): the condition, the options menu,
the card rows' own twins, the hooks and the per-player smoke and colour, against bounded engine fixtures."""
from pathlib import Path
import sys

from lua_test_runtime import LuaRuntime

root = Path(__file__).resolve().parents[1] / "scripts/mods/GrandfathersTarot"
lua = LuaRuntime(unpack_returned_tuples=True)
output = lua.execute(r'''
local ROOT = ...
local results = {}
local function check(name, condition, detail)
  results[#results + 1] = (condition and "PASS " or "FAIL ") .. name .. (condition and "" or (" -- " .. tostring(detail)))
end

-- ---------------------------------------------------------------- engine fixtures
local V = {}
V.__index = V
local function vec(x, y, z) return setmetatable({ x = x, y = y, z = z }, V) end
V.__add = function (a, b) return vec(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function (a, b) return vec(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__unm = function (a) return vec(-a.x, -a.y, -a.z) end
V.__mul = function (a, b)
  if type(a) == "number" then a, b = b, a end
  return vec(a.x * b, a.y * b, a.z * b)
end
Vector3 = setmetatable({
  up = function () return vec(0, 0, 1) end,
  distance_squared = function (a, b) return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2 end,
}, { __call = function (_, x, y, z) return vec(x, y, z) end })
Vector3Box = function (p) local c = vec(p.x, p.y, p.z) return { unbox = function () return vec(c.x, c.y, c.z) end } end
QuaternionBox = function (q) return { unbox = function () return q end } end
Quaternion = {
  right = function () return vec(1, 0, 0) end,
  forward = function () return vec(0, 1, 0) end,
  look = function () return "look" end,
}
ALIVE, BLACKBOARDS, POSITION_LOOKUP = {}, {}, {}
local positions, extensions = {}, {}
Unit = {
  alive = function (unit) return ALIVE[unit] == true end,
  world_position = function (unit) return positions[unit] or vec(0, 0, 0) end,
  local_rotation = function () return "rot" end,
}
ScriptUnit = {
  has_extension = function (unit, name) return extensions[unit] and extensions[unit][name] end,
  extension = function (unit, name) return extensions[unit][name] end,
}
World = { physics_world = function () return "physics" end }
NetworkLookup = { circumstance_templates = { "default", default = 1 } }

local function breed_unit(name, at)
  local unit = { name = name }
  ALIVE[unit] = true
  positions[unit] = at or vec(0, 0, 0)
  POSITION_LOOKUP[unit] = positions[unit]
  extensions[unit] = { unit_data_system = { breed_name = function () return name end } }
  return unit
end

-- the game's buff extension: its methods live on the class (the die hook sets and clears an instance has_keyword)
local BuffClass = {
  has_keyword = function (self, keyword) return self.keywords[keyword] == true end,
  current_stacks = function (self) return self.stacks or 0 end,
  add_internally_controlled_buff = function (self, buff) self.added[#self.added + 1] = buff end,
  _update_stat_buffs_and_keywords = function () end,
}
local function buffs_of(unit, keywords, stacks)
  local ext = setmetatable({ added = {}, keywords = keywords, stacks = stacks }, { __index = BuffClass })
  extensions[unit].buff_system = ext
  return ext
end

-- the game files Twins requires
local purple_template = {
  minion_effects = {
    material_vector = { name = "stimmed_color", value = { 1, 1, 1 } },
    node_effects = { { vfx = { material_variables = { { value = { 1, 1, 1 } }, { value = { 1, 1, 1 } } } } }, { vfx = {} } },
  },
}
local buff_templates = { mutator_stimmed_minion_purple = purple_template }
local explosions, husk_calls = {}, {}
local Explosion = {
  create_explosion = function (world, physics_world, position, rotation, unit, template) explosions[#explosions + 1] = { template = template, unit = unit } end,
  create_husk_explosion = function (world, physics_world, wwise_world, owner, template, position) husk_calls[#husk_calls + 1] = { template = template, position = position } end,
}
local purple_explosion = { name = "purple_stimmed_explosion", vfx = { "smoke" }, sfx = { "gas" }, radius = 1 }
local mutator_templates = { mutator_stimmed_minions = { name = "mutator_stimmed_minions", breed_chances = { vanilla = 0.2 } } }
local circumstance_templates, havoc_circumstances = {}, {}
local snap_mode = "ok"
local new_purple
local PurpleClass = { new = function (_, is_server) new_purple = { is_server = is_server, _spawn_queue_size = 0, update = function () end } return new_purple end }
local stim_component = {}
local fixtures = {
  ["scripts/settings/buff/buff_templates"] = function () return buff_templates end,
  ["scripts/settings/buff/buff_settings"] = function () return { keywords = { despawn_on_death = "despawn_on_death" } } end,
  ["scripts/utilities/attack/explosion"] = function () return Explosion end,
  ["scripts/settings/damage/explosion_templates"] = function () return { purple_stimmed_explosion = purple_explosion } end,
  ["scripts/settings/circumstance/circumstance_templates"] = function () return circumstance_templates end,
  ["scripts/settings/circumstance/templates/havoc_circumstance_template"] = function () return havoc_circumstances end,
  ["scripts/settings/mutator/mutator_templates"] = function () return mutator_templates end,
  ["scripts/managers/mutator/mutators/mutator_purple_stimmed"] = function () return PurpleClass end,
  ["scripts/extension_systems/blackboard/utilities/blackboard"] = function () return { write_component = function () return stim_component end } end,
  ["scripts/utilities/nav_queries"] = function ()
    return { position_on_mesh_with_outside_position = function (_, _, position)
      if snap_mode == "throw" then error("native snap failed") end
      if snap_mode == "nil" then return nil end
      return position
    end }
  end,
}
for path, loader in pairs(fixtures) do package.preload[path] = loader end

-- ---------------------------------------------------------------- the mod
local settings, notes, warnings, echoes, commands, sets = {}, {}, {}, {}, {}, {}
local hook_requires, hooks = {}, {}
local mod = {}
function mod:get(id) return settings[id] end
function mod:set(id, value) settings[id] = value; sets[#sets + 1] = id end
function mod:localize(key, ...) local args = { ... } local text = key for i = 1, select("#", ...) do text = text .. "|" .. tostring(args[i]) end return text end
function mod:notify(text) notes[#notes + 1] = text end
function mod:warning(format, ...) warnings[#warnings + 1] = string.format(format, ...) end
function mod:echo(text) echoes[#echoes + 1] = text end
function mod:command(name, _, fn) commands[name] = fn end
function mod:add_global_localize_strings(strings) mod.global_strings = strings end
function mod:io_dofile(path) return dofile(ROOT .. path:gsub("^GrandfathersTarot/scripts/mods/GrandfathersTarot", "") .. ".lua") end
function mod:hook_require(path, fn) hook_requires[#hook_requires + 1] = { path = path, fn = fn } end
function mod:hook(class, name, fn)
  local original = class[name]
  hooks[name] = fn
  class[name] = function (...) return fn(original, ...) end
end

local solo_play = { enabled = true }
function solo_play:is_enabled() return self.enabled end
solo_play.gen_normal_mission_context = function (circumstance) return { circumstance_name = circumstance } end
solo_play.gen_havoc_mission_context = function (data) return { havoc_data = data } end
local old_mod, solo_present = nil, true
get_mod = function (name)
  if name == "GrandfathersTarot" then return mod end
  if name == "SoloPlay" then return solo_present and solo_play or nil end
  if name == "SoloPlayPurpleStimms" then return old_mod end
end

local function fresh_twins()
  hook_requires = {}
  return dofile(ROOT .. "/twins/twins.lua")
end

-- the classes the game would load, each run through the hook_require callbacks registered for its path
local classes = {}
local function load_classes()
  for _, entry in ipairs(hook_requires) do
    classes[entry.path] = classes[entry.path] or {}
    entry.fn(classes[entry.path])
  end
end

Managers = { state = {}, time = { time = function () return 12 end } }

-- ---------------------------------------------------------------- install: refusals
old_mod = {}
local T0 = fresh_twins()
local ok0, why0 = T0.install()
check("install: refused while SoloPlayPurpleStimms is still loaded, with the reason", ok0 == false and why0:find("SoloPlayPurpleStimms") ~= nil, why0)
check("install: nothing runs while not installed", not T0.is_installed() and T0.on_setting_changed("tw_loop_check") == false and T0.reset_to_defaults() == nil and T0.on_all_mods_loaded() == nil)
local unclaimed = {}
T0.claim(unclaimed, "renegade_executor", {})
check("install: a claim is ignored while not installed", not T0.is_claimed(unclaimed))
old_mod = nil

buff_templates.mutator_stimmed_minion_purple = nil
local T1 = fresh_twins()
local ok1, why1 = T1.install()
check("install: without the purple buff Twins stays off and says why", ok1 == false and why1:find("buff") ~= nil and warnings[#warnings]:find("not found") ~= nil, why1)
buff_templates.mutator_stimmed_minion_purple = purple_template

solo_present = false
local T2 = fresh_twins()
local ok2 = T2.install()
check("install: without SoloPlay the card rows' Twins still work and the missing condition is said once", ok2 == true and T2.is_installed() and warnings[#warnings]:find("SoloPlay is missing") ~= nil)
check("install: a second install is a no-op", T2.install() == true)
solo_present = true

-- ---------------------------------------------------------------- install: the real one
local spawned, spawn_answer, spawning_card = {}, true, false
local Exec = {
  spawn_twin = function (entry, position, target)
    if spawn_answer == "full" then return false, "full" end
    spawned[#spawned + 1] = { entry = entry, position = position, target = target }
    return spawn_answer
  end,
  is_spawning = function () return spawning_card end,
}
local players = {}
local Pos = { player_units = function () return players end }
local Twins = fresh_twins()
classes["scripts/utilities/attack/explosion"] = Explosion
Twins.init({ execute = Exec, positions = Pos })
check("install: installs with SoloPlay", Twins.install() == true and Twins.is_installed())
load_classes()
local catalog = Twins.catalog()
check("install: the catalog is loaded, its defaults the author's (Daemonhost on at 30%, Poxburster splits into Poxbursters, never stimmed)",
  catalog.by_id.chaos_daemonhost.enabled == true and catalog.by_id.chaos_daemonhost.chance == 30
  and catalog.by_id.chaos_poxwalker_bomber.twin1 == "chaos_poxwalker_bomber" and catalog.by_id.chaos_poxwalker_bomber.twins_buff == "never")
check("install: the purple buff's death effect is Twins' and stacks once", type(purple_template.stop_func) == "function" and purple_template.max_stacks == 1 and purple_template.max_stacks_cap == 1)
check("install: the condition is offered under its old id (SoloPlay and Havoc lists, network lookup)", circumstance_templates.rift_warp_01 ~= nil and havoc_circumstances.rift_warp_01 == circumstance_templates.rift_warp_01 and NetworkLookup.circumstance_templates.rift_warp_01 == 2)
check("install: the condition's names are global strings", mod.global_strings.loc_purple_stimms_twins_title.en == "Twins")
check("install: the trigger and purple mutators are registered", mutator_templates.mutator_stimmed_minions_purple_trigger ~= nil and mutator_templates.mutator_stimmed_minions_purple ~= nil)
check("install: the smoke command is /gt_twins_smoke", type(commands.gt_twins_smoke) == "function")

-- ---------------------------------------------------------------- cosmetics
check("colour: every tint of the buff shares one table, the game's purple by default",
  purple_template.minion_effects.material_vector.value == purple_template.minion_effects.node_effects[1].vfx.material_variables[2].value
  and math.abs(purple_template.minion_effects.material_vector.value[1] - 0.75) < 1e-9)
settings.tw_color_custom, settings.tw_color_r, settings.tw_color_g, settings.tw_color_b = true, 255, 300, -5
check("colour: a colour setting is Twins' and recolors (each channel clamped to 0-255)", Twins.on_setting_changed("tw_color_r") == true
  and purple_template.minion_effects.material_vector.value[1] == 1 and purple_template.minion_effects.material_vector.value[2] == 1 and purple_template.minion_effects.material_vector.value[3] == 0)
settings.tw_color_custom = false
Twins.on_setting_changed("tw_color_custom")
check("colour: custom off gives the game's purple back", math.abs(purple_template.minion_effects.material_vector.value[3] - 0.75) < 1e-9)

local Husk = classes["scripts/utilities/attack/explosion"]
Husk.create_husk_explosion("w", "p", "ww", nil, { name = "other" }, "pos")
check("smoke: another explosion goes through untouched", husk_calls[#husk_calls].template.name == "other")
settings.tw_smoke_enabled, settings.tw_smoke_sound = nil, nil
Husk.create_husk_explosion("w", "p", "ww", nil, purple_explosion, "pos")
check("smoke: with smoke and sound on (default) the game's own burst plays", husk_calls[#husk_calls].template == purple_explosion)
settings.tw_smoke_enabled = false
Husk.create_husk_explosion("w", "p", "ww", nil, purple_explosion, "pos")
local quiet = husk_calls[#husk_calls].template
check("smoke: smoke off plays a copy without the particle, the game's table untouched", quiet ~= purple_explosion and quiet.vfx == nil and quiet.sfx == purple_explosion.sfx and purple_explosion.vfx ~= nil)
Husk.create_husk_explosion("w", "p", "ww", nil, purple_explosion, "pos")
check("smoke: the copy is made once", husk_calls[#husk_calls].template == quiet)
settings.tw_smoke_enabled, settings.tw_smoke_sound = true, false
Husk.create_husk_explosion("w", "p", "ww", nil, purple_explosion, "pos")
check("smoke: sound off keeps the particle and drops the sound", husk_calls[#husk_calls].template.sfx == nil and husk_calls[#husk_calls].template.vfx ~= nil)
settings.tw_smoke_sound = nil

Managers.player = { local_player = function () return nil end }
commands.gt_twins_smoke()
check("smoke test: without a player unit it says so", echoes[#echoes]:find("no player unit") ~= nil, echoes[#echoes])
local me = breed_unit("player", vec(5, 5, 0))
Managers.player = { local_player = function () return { player_unit = me } end }
Managers.world = { world = function () return "level" end, wwise_world = function () return "wwise" end }
local before = #husk_calls
commands.gt_twins_smoke()
check("smoke test: plays the burst two metres in front of the player", #husk_calls == before + 1 and husk_calls[#husk_calls].position.y == 7)
Managers.world = { world = function () error("no level world") end }
local echoed = #echoes
commands.gt_twins_smoke()
check("smoke test: an engine error is reported, not thrown", #echoes == echoed + 1 and echoes[#echoes]:find("no level world") ~= nil)

-- ---------------------------------------------------------------- the options menu
check("options: a setting that is not Twins' is not taken", Twins.on_setting_changed("max_alive") == false and Twins.on_setting_changed(nil) == false)
settings.tw_boss_selector = "chaos_daemonhost"
Twins.on_setting_changed("tw_boss_selector")
check("options: choosing a boss shows its values (the author's Daemonhost)", settings.tw_boss_enabled == true and settings.tw_boss_chance == 30 and settings.tw_boss_twin1 == "default")
settings.tw_enemy_selector = "chaos_poxwalker_bomber"
local noted = #notes
Twins.on_setting_changed("tw_enemy_selector")
check("options: an enemy without a stim animation warns that it is only rolled when it spawns", #notes == noted + 1 and notes[#notes]:find("tw_warning_no_stim_animation") ~= nil and settings.tw_enemy_twins_buff == "never")
settings.tw_enemy_selector = "not_a_breed"
Twins.on_setting_changed("tw_enemy_selector")
check("options: an unknown selection falls back to the first enemy", settings.tw_enemy_enabled == catalog.by_id[catalog.enemies[1].id].enabled)

settings.tw_enemy_selector = "renegade_executor"
Twins.on_setting_changed("tw_enemy_selector")
settings.tw_enemy_chance = 70
Twins.on_setting_changed("tw_enemy_chance")
check("options: a change is stored for the selected enemy only", type(settings.tw_cfg_renegade_executor) == "table" and settings.tw_cfg_renegade_executor.chance == 70)
local chances = mutator_templates.mutator_stimmed_minions_purple_trigger.breed_chances
check("condition: the stim chance is read live (70% -> 0.7)", math.abs(chances.renegade_executor - 0.7) < 1e-9)
check("condition: an enemy that is off or unknown has no chance", chances.renegade_gunner == nil and chances.nobody == nil)
settings.tw_bosses_enabled, settings.tw_bosses_chance = true, 50
check("condition: a captain's chance is scaled by the bosses' chance (20% x 50%)", math.abs(chances.renegade_captain - 0.1) < 1e-9)
settings.tw_bosses_enabled = false
check("condition: bosses off means no boss is stimmed", chances.renegade_captain == nil)
settings.tw_bosses_enabled, settings.tw_bosses_chance = true, 100

settings.tw_loop_check = true
settings.tw_enemy_twin1, settings.tw_enemy_twins_buff = "renegade_executor", "always"
noted = #notes
Twins.on_setting_changed("tw_enemy_twin1")
check("loops: an enemy splitting into itself, stimmed again (it can split), warns (the check stops it)", #notes == noted + 1 and notes[#notes]:find("tw_warning_self_split_one_prevented") ~= nil, notes[#notes])
Twins.on_setting_changed("tw_enemy_twins_buff")
check("loops: the same loop does not warn twice", #notes == noted + 1)
settings.tw_enemy_twin2 = "renegade_executor"
Twins.on_setting_changed("tw_enemy_twin2")
check("loops: both twins itself has its own warning", notes[#notes]:find("tw_warning_self_split_two_prevented") ~= nil, notes[#notes])
settings.tw_loop_check = false
Twins.on_setting_changed("tw_enemy_twin2")
check("loops: with the check off the warning says the loop is not stopped", notes[#notes]:find("_unchecked") ~= nil, notes[#notes])
settings.tw_loop_check = true
settings.tw_enemy_twin1, settings.tw_enemy_twin2 = "renegade_melee", "none"
Twins.on_setting_changed("tw_enemy_twin1")
Twins.on_setting_changed("tw_enemy_twin2")
settings.tw_enemy_selector = "renegade_melee"
Twins.on_setting_changed("tw_enemy_selector")
settings.tw_enemy_twin1, settings.tw_enemy_twins_buff = "renegade_executor", "always"
Twins.on_setting_changed("tw_enemy_twins_buff")
Twins.on_setting_changed("tw_enemy_twin1")
check("loops: a loop through two enemies names the path", notes[#notes]:find("tw_warning_spawn_loop_prevented") ~= nil and notes[#notes]:find("renegade_melee") ~= nil, notes[#notes])
settings.tw_enemy_twin1 = "none"
Twins.on_setting_changed("tw_enemy_twin1")
noted = #notes
settings.tw_enemy_twin1 = "renegade_executor"
Twins.on_setting_changed("tw_enemy_twin1")
check("loops: a loop broken and made again warns again", #notes == noted + 1)

settings.tw_cfg_cultist_gunner = { twins_stimmed = false }
settings.tw_enemy_selector = "cultist_gunner"
Twins.on_setting_changed("tw_enemy_selector")
check("options: an old on/off 'twins stimmed' reads as Never", settings.tw_enemy_twins_buff == "never")
check("options: another tw_ setting is still Twins'", Twins.on_setting_changed("tw_guest_safe") == true)

settings.tw_boss_selector = "nobody"
Twins.on_all_mods_loaded()
check("options: at load an unknown selection is put back on the first boss", settings.tw_boss_selector == catalog.bosses[1].id)

settings.tw_guest_safe, settings.tw_no_restim = true, false
noted = #notes
Twins.reset_to_defaults()
check("reset: the options return to the defaults (Hide from guests off, Don't re-stim on: the author's)", settings.tw_guest_safe == false and settings.tw_no_restim == true and settings.tw_loop_check == true)
check("reset: every per-enemy value is cleared and it says so", settings.tw_cfg_renegade_executor == nil and settings.tw_cfg_renegade_gunner == nil and notes[#notes] == "tw_reset_done")
check("reset: the selected enemy's widgets show the defaults again", settings.tw_enemy_twins_buff == "default")

-- ---------------------------------------------------------------- the card rows' own twins
local claim = { breed = "chaos_poxwalker_bomber", gen = 1, cfg = {}, row = { mods = { "enraged", "purple_stimm" }, tune = { health = 2 }, boss_name = 3 } }
local e1 = Twins.twin_entry(claim, 1)
check("rows: an untouched twin is the game's split, a plain enemy", e1.breed == "renegade_executor" and e1.mods == nil and e1.tune == nil and e1.twins == nil)
claim.cfg = { a = "chaos_poxwalker_bomber", ka = true, b = "none" }
e1 = Twins.twin_entry(claim, 1)
check("rows: 'keeps this row's mods' carries the modifiers (Twins taken off), stats and boss bar", e1.breed == "chaos_poxwalker_bomber" and #e1.mods == 1 and e1.mods[1] == "enraged" and e1.tune.health == 2 and e1.boss_name == 3)
check("rows: 'none' spawns nothing", Twins.twin_entry(claim, 2) == nil)
claim.cfg = { a = "chaos_poxwalker_bomber", sa = true, gen = 3 }
e1 = Twins.twin_entry(claim, 1)
check("rows: 'splits again' gives the twin Twins, one generation on, same settings", e1.mods[1] == "purple_stimm" and e1.twin_gen == 2 and e1.twins == claim.cfg)
claim.gen = 3
check("rows: the last generation does not split again", Twins.twin_entry(claim, 1).twins == nil)
claim.cfg = { a = "not_a_breed" }
check("rows: an unknown twin falls back to the game's split", Twins.twin_entry(claim, 1).breed == "renegade_executor" and Twins.row_twin({}, 2, "chaos_daemonhost") == "chaos_spawn")

-- who the twins go for
local p_near, p_far = breed_unit("near", vec(1, 0, 0)), breed_unit("far", vec(50, 0, 0))
buffs_of(p_near, {})
buffs_of(p_far, {})
players = { p_near, p_far }
local hidden = breed_unit("hidden", vec(0, 0, 0))
buffs_of(hidden, { invisible = true })
check("target: the dying enemy's target while it is alive and seen", Twins.pick_target(p_far, vec(0, 0, 0)) == p_far)
check("target: an invisible target is swapped for the nearest player who is seen", Twins.pick_target(hidden, vec(0, 0, 0)) == p_near)
extensions[p_near].buff_system.has_keyword = function (_, k) return k == "unperceivable" end
check("target: a player in stealth is passed over for one who is seen", Twins.pick_target(nil, vec(0, 0, 0)) == p_far)
extensions[p_far].buff_system.has_keyword = function (_, k) return k == "invisible" end
check("target: when every player is hidden, the nearest one", Twins.pick_target(nil, vec(0, 0, 0)) == p_near)
extensions[p_far].buff_system.has_keyword = function () error("broken buff extension") end
check("target: a buff extension error counts as seen", Twins.pick_target(nil, vec(0, 0, 0)) == p_far)
ALIVE[p_near], ALIVE[p_far] = nil, nil
check("target: nobody alive, nobody to go for", Twins.pick_target(nil, vec(0, 0, 0)) == nil)
ALIVE[p_near], ALIVE[p_far] = true, true
buffs_of(p_near, {})
buffs_of(p_far, {})

-- the death effect
local died = {}
-- the die hook wraps whatever the class had when it was hooked: hook one with a recorder
local death_class = { die = function (self, unit) died[#died + 1] = unit; if unit.explode then error("die exploded") end return "dead" end }
for _, entry in ipairs(hook_requires) do
  if entry.path == "scripts/managers/minion/minion_death_manager" then entry.fn(death_class) end
end

local function kill(unit)
  BLACKBOARDS[unit] = BLACKBOARDS[unit] or { perception = { target_unit = p_near }, spawn = { world = "w", physics_world = "p" } }
  death_class:die(unit)
  purple_template.stop_func({}, { unit = unit }, true)
end

local card = breed_unit("chaos_poxwalker_bomber", vec(10, 0, 0))
Twins.claim(card, "chaos_poxwalker_bomber", { twins = { a = "chaos_poxwalker_bomber", b = "renegade_melee" }, mods = { "purple_stimm" } })
check("rows: a card's Twins enemy is claimed", Twins.is_claimed(card))
local explosions_before = #explosions
kill(card)
check("rows: a card's enemy that dies queues its two twins and bursts", Twins.queued() == 2 and #explosions == explosions_before + 1 and not Twins.is_claimed(card))

local deleted = breed_unit("chaos_poxwalker_bomber")
Twins.claim(deleted, "chaos_poxwalker_bomber", { twins = {} })
purple_template.stop_func({}, { unit = deleted }, true)
check("rows: a deleted (not killed) enemy does not split, and is forgotten", Twins.queued() == 2 and not Twins.is_claimed(deleted))

local gone = breed_unit("chaos_poxwalker_bomber")
Twins.claim(gone, "chaos_poxwalker_bomber", {})
death_class:die(gone)
ALIVE[gone] = nil
purple_template.stop_func({}, { unit = gone }, true)
check("rows: an enemy already gone does not split", Twins.queued() == 2)
local blind = breed_unit("chaos_poxwalker_bomber")
death_class:die(blind)
purple_template.stop_func({}, { unit = blind }, false)
check("rows: without a blackboard nothing splits", Twins.queued() == 2)

local lonely = breed_unit("chaos_poxwalker_bomber", vec(0, 0, 0))
Twins.claim(lonely, "chaos_poxwalker_bomber", {})
ALIVE[p_near], ALIVE[p_far] = nil, nil
kill(lonely)
check("rows: with no player alive the twins are not queued", Twins.queued() == 2)
ALIVE[p_near], ALIVE[p_far] = true, true

local broken = breed_unit("chaos_poxwalker_bomber")
Twins.claim(broken, "chaos_poxwalker_bomber", {})
BLACKBOARDS[broken] = { perception = { target_unit = p_near } }
local saved_rotation = Unit.local_rotation
Unit.local_rotation = function () error("no rotation") end
local warned = #warnings
kill(broken)
Unit.local_rotation = saved_rotation
check("rows: a failing split is a warning, not a crash", #warnings == warned + 1 and warnings[#warnings]:find("split failed") ~= nil)

-- spawning the queue
Managers.state = { nav_mesh = { nav_world = function () return "nav" end } }
spawn_answer = true
Twins.update(0.1)
check("rows: the queued twins spawn on the navmesh, going for the target", #spawned == 2 and Twins.queued() == 0 and spawned[1].target == p_near and spawned[1].entry.breed == "chaos_poxwalker_bomber" and spawned[2].entry.breed == "renegade_melee")
for i = 1, 6 do
  local unit = breed_unit("chaos_poxwalker_bomber", vec(i, 0, 0))
  Twins.claim(unit, "chaos_poxwalker_bomber", {})
  kill(unit)
end
spawned = {}
Twins.update(0.1)
check("rows: at most 4 twins spawn per update", #spawned == 4 and Twins.queued() == 8)
spawn_answer = "full"
Twins.update(4)
check("rows: a twin waits while the card enemies are at their limit", Twins.queued() == 8)
Twins.update(7)
check("rows: after 10 s of waiting it is dropped", Twins.queued() == 4)
snap_mode = "nil"
spawn_answer = true
Twins.update(0.1)
check("rows: a twin with no place on the navmesh is dropped", Twins.queued() == 0)
snap_mode = "ok"
for i = 1, 30 do
  local unit = breed_unit("chaos_poxwalker_bomber", vec(i, 0, 0))
  Twins.claim(unit, "chaos_poxwalker_bomber", {})
  kill(unit)
end
check("rows: the queue is capped at 48", Twins.queued() == 48)
Twins.reset()
check("rows: a reset empties the queue", Twins.queued() == 0)
Twins.update(0.1)

-- the condition's own splits: the purple mutator's queue, only while the condition is on
local split_calls = {}
local purple_mutator = { _spawn_queue_size = 0, add_split_spawn = function (self, position, rotation, breed, buff, target) split_calls[#split_calls + 1] = { breed = breed, buff = buff, target = target } end }
Managers.state.mutator = { mutator = function (self, name) return name == "mutator_stimmed_minions_purple" and purple_mutator or nil end, _is_server = true }
local plain = breed_unit("renegade_executor", vec(3, 0, 0))
kill(plain)
check("condition: a purple enemy that is not a card's splits by its settings through the game's queue", #split_calls == 2 and split_calls[1].breed == "renegade_melee" and split_calls[1].target == p_near)
check("condition: a twin that can split again keeps the stimm (the game's rule)", split_calls[1].buff == "mutator_stimmed_minion_purple")
settings.tw_cfg_renegade_executor = { twin1 = "renegade_executor", twin2 = "none", twins_buff = "always" }
Twins.reset_to_defaults()
settings.tw_cfg_renegade_executor = { twin1 = "renegade_executor", twin2 = "none", twins_buff = "always" }
split_calls = {}
kill(breed_unit("renegade_executor"))
check("condition: the loop check spawns a looping twin plain", #split_calls == 1 and split_calls[1].buff == nil)
local no_target = breed_unit("renegade_executor")
BLACKBOARDS[no_target] = { perception = { target_unit = nil }, spawn = {} }
split_calls = {}
kill(no_target)
check("condition: without a living target the game's rule spawns nothing", #split_calls == 0)
local no_config = breed_unit("not_a_breed")
split_calls = {}
kill(no_config)
check("condition: an enemy Twins does not know does not split", #split_calls == 0)
Managers.state.mutator = { mutator = function () return nil end }
kill(breed_unit("renegade_executor"))
check("condition: no purple mutator, no split", #split_calls == 0)

-- the boss fix in die
local boss = breed_unit("chaos_daemonhost")
local boss_buffs = buffs_of(boss, { despawn_on_death = true, other = true })
local seen_in_die
local inner = { die = function (self, unit) seen_in_die = { unit = unit, despawn = extensions[unit].buff_system:has_keyword("despawn_on_death"), other = extensions[unit].buff_system:has_keyword("other") } if unit.explode then error("die exploded") end return "dead" end }
for _, entry in ipairs(hook_requires) do
  if entry.path == "scripts/managers/minion/minion_death_manager" then entry.fn(inner) end
end
local result = inner:die(boss)
check("die: a boss with the stimm dies normally (its despawn keyword is hidden for the call), other keywords still read", result == "dead" and seen_in_die.despawn == false and seen_in_die.other == true)
check("die: the keyword is the class's again afterwards", rawget(boss_buffs, "has_keyword") == nil)
boss.explode = true
local ok_die, err_die = pcall(inner.die, inner, boss)
check("die: an error in die is passed on, the keyword put back", not ok_die and tostring(err_die):find("die exploded") ~= nil and rawget(boss_buffs, "has_keyword") == nil)
local grunt = breed_unit("renegade_melee")
buffs_of(grunt, {})
check("die: an enemy that is not a boss goes straight through", inner:die(grunt) == "dead" and seen_in_die.unit == grunt)

-- the stim action
local stim_class = { run = function (self, unit, breed, blackboard, scratchpad, action_data) if action_data.explode then error("stim exploded") end return action_data.stim_buffs end }
for _, entry in ipairs(hook_requires) do
  if entry.path:find("bt_use_stim_action") then entry.fn(stim_class) end
end
local action = { stim_buffs = { "green" } }
Managers.state.mutator = { mutator = function () return purple_mutator end }
check("stim: without the condition the game's own stim", stim_class:run(grunt, nil, {}, {}, action)[1] == "green")
Managers.state.mutator = setmetatable({ __tw_condition = true }, { __index = { mutator = function () return purple_mutator end } })
check("stim: under the condition the stim is the purple one, and the game's list is put back", stim_class:run(grunt, nil, {}, {}, action)[1] == "mutator_stimmed_minion_purple" and action.stim_buffs[1] == "green")
settings.tw_no_restim = true
buffs_of(grunt, {}, 1)
check("stim: Don't re-stim skips an enemy already purple and clears its stim flag", stim_class:run(grunt, nil, {}, {}, action) == "done" and stim_component.can_use_stim == false)
settings.tw_no_restim = false
action.explode = true
local ok_stim, err_stim = pcall(stim_class.run, stim_class, grunt, nil, {}, {}, action)
check("stim: an error is passed on, the list put back", not ok_stim and tostring(err_stim):find("stim exploded") ~= nil and action.stim_buffs[1] == "green")

-- rolled at spawn (enemies without a stim animation)
local spawn_class = { spawn_minion = function (self, breed_name) local unit = breed_unit(breed_name) buffs_of(unit, {}) return unit end }
for _, entry in ipairs(hook_requires) do
  if entry.path == "scripts/managers/minion/minion_spawn_manager" then entry.fn(spawn_class) end
end
local real_random = math.random
math.random = function () return 0 end
local bomber = spawn_class:spawn_minion("chaos_poxwalker_bomber")
check("spawn: under the condition an enemy without a stim animation rolls its chance at spawn", extensions[bomber].buff_system.added[1] == "mutator_stimmed_minion_purple")
spawning_card = true
local card_bomber = spawn_class:spawn_minion("chaos_poxwalker_bomber")
check("spawn: a card's own enemy is left alone (it has its own modifiers)", #extensions[card_bomber].buff_system.added == 0)
spawning_card = false
check("spawn: an enemy with a stim animation is left to the stim action", #extensions[spawn_class:spawn_minion("renegade_executor")].buff_system.added == 0)
local watched = { update = function (self) self.inner = spawn_class:spawn_minion("chaos_poxwalker_bomber") end }
Twins.watch_twin_spawns(watched)
Twins.watch_twin_spawns(watched)
watched:update(0, 0)
check("spawn: a split-off twin of the game's queue is not rolled again", #extensions[watched.inner].buff_system.added == 0)
local failing = { update = function () error("mutator update failed") end }
Twins.watch_twin_spawns(failing)
check("spawn: an error in the purple mutator's update is passed on", not pcall(failing.update, failing, 0, 0))
Managers.state.mutator = { mutator = function () return purple_mutator end }
check("spawn: without the condition nobody is rolled (a card's Twins row alone does not turn the mission purple)", #extensions[spawn_class:spawn_minion("chaos_poxwalker_bomber")].buff_system.added == 0)
math.random = real_random

-- ---------------------------------------------------------------- the condition through SoloPlay
settings.tw_guest_safe = true
local context = solo_play.gen_normal_mission_context("rift_warp_01")
check("condition: with Hide from guests a normal mission carries it as the game's stimmed condition", context.circumstance_name == "mutator_stimmed_minions" and context.__purple_stimms == true)
check("condition: another condition is left alone", solo_play.gen_normal_mission_context("default").__purple_stimms == nil)
local havoc = solo_play.gen_havoc_mission_context("m;1;t;f;rift_warp_01:mutator_stimmed_minions:;mods;c;r")
check("condition: in Havoc data it is swapped in field 5, without a duplicate", havoc.havoc_data == "m;1;t;f;mutator_stimmed_minions;mods;c;r" and havoc.__purple_stimms == true, havoc.havoc_data)
check("condition: Havoc data without it, or malformed, is kept", Twins.carry_havoc_data("a;b;c;d;x:y") == "a;b;c;d;x:y" and Twins.carry_havoc_data("short") == "short" and Twins.carry_havoc_data(nil) == nil)
settings.tw_guest_safe = false
local open = solo_play.gen_normal_mission_context("rift_warp_01")
check("condition: Hide from guests off keeps its real name (the author's default)", open.circumstance_name == "rift_warp_01" and open.__purple_stimms == nil)
local T3 = fresh_twins()
T3.init({ execute = Exec, positions = Pos })
T3.install()
check("condition: a second install does not wrap SoloPlay twice", solo_play.gen_normal_mission_context("default").circumstance_name == "default")
solo_play.__purple_stimms_original_gen_havoc_mission_context = nil
solo_play.gen_havoc_mission_context = nil
local T4 = fresh_twins()
warned = #warnings
T4.install()
check("condition: a SoloPlay without the function warns", #warnings > warned and warnings[#warnings]:find("gen_havoc_mission_context") ~= nil)

local mechanism = { change_mechanism = function (self, name, ctx) return name end }
local mutators = { _load_mutators = function (self, circumstance)
  if self.explode then error("load failed") end
  self.seen_chances = mutator_templates.mutator_stimmed_minions.breed_chances
  self._mutators = self.loaded or {}
end }
for _, entry in ipairs(hook_requires) do
  if entry.path == "scripts/managers/mechanism/mechanism_manager" then entry.fn(mechanism) end
  if entry.path == "scripts/managers/mutator/mutator_manager" then entry.fn(mutators) end
end
mechanism:change_mechanism("adventure", { __purple_stimms = true })
local host = setmetatable({ _is_server = true, loaded = { mutator_stimmed_minions = {} } }, { __index = mutators })
host:_load_mutators("mutator_stimmed_minions")
check("condition: the host's carrier reads Twins' chances while it loads, the game's afterwards", host.seen_chances ~= mutator_templates.mutator_stimmed_minions.breed_chances and mutator_templates.mutator_stimmed_minions.breed_chances.vanilla == 0.2)
check("condition: the host adds the purple mutator and marks the condition on", host._mutators.mutator_stimmed_minions_purple == new_purple and rawget(host, "__tw_condition") == true and rawget(new_purple, "__tw_watched") == true)
mechanism:change_mechanism("adventure", { __purple_stimms = true })
local failing_host = setmetatable({ _is_server = true, explode = true }, { __index = mutators })
check("condition: an error while loading is passed on and the chances put back", not pcall(failing_host._load_mutators, failing_host, "x") and mutator_templates.mutator_stimmed_minions.breed_chances.vanilla == 0.2)
mechanism:change_mechanism("adventure", { })
local plain_host = setmetatable({ _is_server = true, loaded = { mutator_stimmed_minions_purple = { update = function () end } } }, { __index = mutators })
plain_host:_load_mutators("rift_warp_01")
check("condition: with Hide from guests off the game's own load still marks the condition on", rawget(plain_host, "__tw_condition") == true)
local mission = setmetatable({ _is_server = true, loaded = {} }, { __index = mutators })
mission:_load_mutators("default")
check("condition: a mission without it is not marked", rawget(mission, "__tw_condition") == nil)
mechanism:change_mechanism("adventure", { __purple_stimms = true })
local guest = setmetatable({ _is_server = false, loaded = { mutator_stimmed_minions = {} } }, { __index = mutators })
guest:_load_mutators("mutator_stimmed_minions")
check("condition: a guest only loads the game's own condition", guest._mutators.mutator_stimmed_minions_purple == nil and rawget(guest, "__tw_condition") == nil)

return table.concat(results, "\n") .. "\n--- warnings ---\n" .. table.concat(warnings, "\n")
''', root.as_posix())
print(output)
fails = [line for line in output.split("\n") if line.startswith("FAIL")]
print("\nFAILURES:", len(fails))
sys.exit(1 if fails else 0)
