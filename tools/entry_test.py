"""Loads the real entry script (GrandfathersTarot.lua) against stubbed DMF/engine pieces and checks what it
installs at load: the DMF keybind-suppression hook, the bypass hooks, the unload behaviour.
Run:  python tools/entry_test.py   (needs `lupa`, see CLAUDE.md)
"""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
from lua_test_runtime import LuaRuntime

MODROOT = os.path.abspath(os.path.join(HERE, "..")).replace("\\", "/")
lua = LuaRuntime(unpack_returned_tuples=True)

harness = r'''
local MODROOT = ...
local BASE = MODROOT .. "/scripts/mods/GrandfathersTarot"

package.preload["scripts/settings/ui/ui_sound_events"] = function() return { system_menu_enter = "a", system_menu_exit = "b" } end
package.preload["scripts/settings/wwise_game_sync/wwise_game_sync_settings"] = function() return { state_groups = { options = { ingame_menu = "x" } } } end
package.preload["scripts/managers/main_path/utilities/spawn_point_queries"] = function() return {} end
package.preload["scripts/utilities/nav_queries"] = function() return {} end
package.preload["scripts/utilities/fixed_frame"] = function() return { get_latest_fixed_time = function() return 1 end } end

local hooks, commands, views = {}, {}, {}
local dmf_calls = {}
local dmf_mod = { check_keybinds = function(...) dmf_calls[#dmf_calls + 1] = { ... }; return "ran" end }
local mod = {}
mod.hook = function(self, obj, method, fn) hooks[#hooks + 1] = { obj = obj, method = method, fn = fn, safe = false } end
mod.hook_safe = function(self, obj, method, fn) hooks[#hooks + 1] = { obj = obj, method = method, fn = fn, safe = true } end
local hook_requires = {}
local require_callbacks, require_by_path = {}, {}
mod.hook_require = function(self, path, fn) hook_requires[#hook_requires + 1] = path;require_callbacks[#require_callbacks+1]=fn;require_by_path[path]=fn end
local hud_elements = {}
mod.register_hud_element = function(self, spec) hud_elements[#hud_elements + 1] = spec end
mod.add_require_path = function() end
mod.register_view = function(self, def) views[#views + 1] = def end
mod.command = function(self, name, desc, fn) commands[name] = fn end
mod.get = function() return nil end
local stored = {}
mod.set = function(self, id, value) stored[id] = value end
mod.echo = function() end
mod.warning = function() end
mod.error = function() end
mod.localize = function(self, id) return id end
mod.io_dofile = function(self, path) return dofile(MODROOT .. "/" .. path:gsub("^GrandfathersTarot/", "") .. ".lua") end
get_mod = function(name)
  if name == "DMF" then return dmf_mod end
  if name == "Realms" then return REALMS_STUB end
  return mod
end
local registered_events = {}
local function event_manager()
  return { _events = {},
    register = function(self, owner, name, method)
      registered_events[name] = method
      self._events[name] = self._events[name] or setmetatable({}, {__mode="v"})
      self._events[name][owner] = method
    end,
    unregister = function(self, owner, name)
      if self._events[name] then self._events[name][owner] = nil end
    end }
end
Managers = { event = event_manager() }

local results = {}
local function check(name, cond, detail) results[#results+1] = (cond and "PASS " or "FAIL ") .. name .. (detail and (" -- " .. tostring(detail)) or "") end

dofile(BASE .. "/GrandfathersTarot.lua")
mod.on_all_mods_loaded()
local RW = mod.rw

local dmf_hooks = {}
for _, h in ipairs(hooks) do if h.obj == dmf_mod then dmf_hooks[#dmf_hooks + 1] = h end end
check("entry: exactly one hook on DMF's check_keybinds, a normal (not safe) hook", #dmf_hooks == 1 and dmf_hooks[1].method == "check_keybinds" and dmf_hooks[1].safe == false, #dmf_hooks)
local hook = dmf_hooks[1].fn
local original = dmf_mod.check_keybinds

check("keybinds: normal play (no text box) -> DMF's check runs and its result is returned", (function() dmf_calls = {}; local r = hook(original, "arg1", "arg2"); return r == "ran" and #dmf_calls == 1 and dmf_calls[1][1] == "arg1" and dmf_calls[1][2] == "arg2" end)())
RW.text_input_active = true
check("keybinds: while a popup text box is open -> DMF's check is skipped (typing 'i' opens nothing)", (function() dmf_calls = {}; local r = hook(original); return r == nil and #dmf_calls == 0 end)())
RW.text_input_active = false
check("keybinds: popup closed -> keybinds work again", (function() dmf_calls = {}; hook(original); return #dmf_calls == 1 end)())

check("entry: the one-time tarot rename ran and its flag is stored", stored.tarot_migrated == true and RW.cards ~= nil and type(RW.cards.migrate) == "function")
-- player deaths feed the anti-snowball option; the new console commands exist
check("entry: the player-death event is registered for anti-snowballing", registered_events.event_player_died == "_on_player_died" and type(mod._on_player_died) == "function")
local forwarded = 0
local real_on_died = RW.director.on_player_died
RW.director.on_player_died = function() forwarded = forwarded + 1 end
mod._on_player_died()
check("entry: a death is forwarded to the director", forwarded == 1)
RW.director.on_player_died = real_on_died
check("entry: rw_stop, rw_pause and rw_next are registered", type(commands.gt_stop) == "function" and type(commands.gt_pause) == "function" and type(commands.gt_next) == "function")
local echoed = {}
mod.echo = function(self, fmt, ...) echoed[#echoed + 1] = string.format(fmt, ...) end
commands.gt_stop(); commands.gt_pause("on"); commands.gt_next()
check("entry: the commands answer in chat (a client or a stopped host gets a reason, never an error)", #echoed == 3 and echoed[1]:find("GrandfathersTarot") ~= nil, table.concat(echoed, " | "))

-- the animation probe: registered, and in a game without any wave unit (or without the engine's Unit table) it only says so
echoed = {}
check("entry: /gt_anim and /gt_tune are registered", type(commands.gt_anim) == "function" and type(commands.gt_tune) == "function")
echoed = {}
local tune_ok = pcall(commands.gt_tune)
check("entry: /gt_tune with nothing tuned answers instead of failing", tune_ok and #echoed == 1 and echoed[1]:find("No living unit", 1, true) ~= nil, table.concat(echoed, " | "))
echoed = {}
local anim_ok, anim_err = pcall(commands.gt_anim)
check("entry: /gt_anim without the engine table (this harness has none) answers instead of failing", anim_ok and #echoed == 2 and echoed[1]:find("Unit functions about animation", 1, true) ~= nil and echoed[2]:find("cannot be looked at", 1, true) ~= nil, anim_ok and table.concat(echoed, " | ") or anim_err)

-- Console/keybind adapters: validate user inputs and forward the intended state.
do
  local saved_ui=Managers.ui
  Managers.ui=nil;mod.open_editor()
  local opened,closed=0,0
  Managers.ui={view_instance=function() return opened>closed and {} or nil end,
    open_view=function(_,name) if name=="realms_waves_editor" then opened=opened+1 end end,
    close_view=function(_,name) if name=="realms_waves_editor" then closed=closed+1 end end}
  commands.gt_editor();commands.gt_editor()
  check("editor command: opens then closes the registered view, absent UI is safe", opened==1 and closed==1)
  Managers.ui=saved_ui
  local original_vote=RW.director.local_vote
  local options={}
  RW.director.local_vote=function(option) options[#options+1]=option;return false,"no ballot" end
  for i=1,5 do mod["vote_"..i]() end
  commands.gt_vote("3");commands.gt_vote("invalid")
  check("vote inputs: all five keys and console number forward the selected option", table.concat(options,",")=="1,2,3,4,5,3,0")
  RW.director.local_vote=original_vote
  local original_pause=RW.director.pause
  local arguments={}
  RW.director.pause=function(value) arguments[#arguments+1]=tostring(value);return value,"client" end
  commands.gt_pause("on");commands.gt_pause("off");commands.gt_pause();commands.gt_pause("toggle")
  check("pause command: on/off forward booleans, omitted/unknown arguments toggle", table.concat(arguments,",")=="true,false,nil,nil")
  RW.director.pause=original_pause
  local original_start=RW.director.force_start
  RW.director.force_start=function() return true end;echoed={};commands.gt_start()
  check("start command: successful host start is reported", echoed[1]:find("cycle started",1,true)~=nil)
  RW.director.force_start=function() return false end;echoed={};commands.gt_start()
  check("start command: rejected client start explains the authority requirement", echoed[1]:find("host in a mission only",1,true)~=nil)
  RW.director.force_start=original_start
  local original_next=RW.director.next_wave
  RW.director.next_wave=function() return true end;echoed={};commands.gt_next()
  check("next command: successful redraw is reported", echoed[1]:find("new card drawn",1,true)~=nil)
  RW.director.next_wave=original_next
  echoed={};commands.gt_test()
  check("test command: empty input lists usage and existing waves", #echoed==1 and echoed[1]:find("hound_frenzy",1,true)~=nil)
  local original_fire=RW.director.fire_now
  local query
  RW.director.fire_now=function(text) query=text;return true,"queued note" end
  echoed={};commands.gt_test("Mutants","Everywhere")
  check("test command: joins multiword names and reports successful queueing", query=="Mutants Everywhere" and echoed[1]:find("queued note",1,true)~=nil)
  RW.director.fire_now=function() return false,"host only" end;echoed={};commands.gt_test("hound_frenzy")
  check("test command: rejected wave reports the director reason", echoed[1]:find("host only",1,true)~=nil)
  RW.director.fire_now=original_fire
  -- the deck holds 150 cards: 138 custom slots (20 until 2.1, 88 until 2026-10-11)
  for _,slot in ipairs({"x","0",tostring(RW.events.CUSTOM_SLOTS+1),"1.5"}) do
    local before=stored.wave_def_custom_3;echoed={};commands.gt_custom(slot,"1 hound")
    check("custom command: invalid slot "..slot.." makes no settings writes", stored.wave_def_custom_3==before and echoed[1]:find("slot must be",1,true)~=nil)
  end
  do
    local top=tostring(RW.events.CUSTOM_SLOTS);echoed={};commands.gt_custom(top,"2","hounds")
    check("custom command: the last slot ("..top..") is valid and the message of a wrong slot names the range", RW.events.CUSTOM_SLOTS==138 and stored["wave_def_custom_"..top]~=nil and stored["on_custom_"..top]==true)
    stored["wave_def_custom_"..top],stored["on_custom_"..top]=nil,nil
    echoed={};commands.gt_custom("0","1 hound")
    check("custom command: ...which is 1-138", echoed[1]:find("1-138",1,true)~=nil, echoed[1])
  end
  local old_def,old_on=stored.wave_def_custom_3,stored.on_custom_3
  commands.gt_custom("3","2","hounds")
  local wave=RW.events.get("custom_3",function(id) return stored[id] end,RW.groups)
  check("custom command: valid recipe persists normalized enemies and enables the slot", wave.parts[1].breed=="chaos_hound" and wave.parts[1].count==2 and stored.on_custom_3==true)
  local saved_def=stored.wave_def_custom_3;echoed={};commands.gt_custom("3","2 unicorns")
  check("custom command: invalid breed leaves the previous recipe intact", stored.wave_def_custom_3==saved_def and #echoed==1)
  echoed={};commands.gt_custom("3")
  check("custom command: absent recipe reports the current slot without mutation", stored.wave_def_custom_3==saved_def and echoed[1]:find("custom_3",1,true)~=nil)
  stored.wave_def_custom_3,stored.on_custom_3=old_def,old_on
  local original_simulate=RW.director.simulate
  local iterations
  RW.director.simulate=function(n) iterations=n;return {},{},0 end
  for _,case in ipairs({{"0",1},{"100001",100000},{"invalid",1000}}) do
    echoed={};commands.gt_roll(case[1])
    check("roll command: "..case[1].." clamps/defaults the workload", iterations==case[2] and echoed[1]:find("no event enabled",1,true)~=nil)
  end
  RW.director.simulate=original_simulate
  local original_probe,original_describe=RW.tuning.probe,RW.tuning.describe
  RW.tuning.probe=function() error("probe failed") end
  RW.tuning.describe=function() error("stats failed") end
  echoed={};commands.gt_anim();commands.gt_tune()
  check("diagnostic commands: native probe errors return chat diagnostics", #echoed==2 and echoed[1]:find("probe failed",1,true)~=nil and echoed[2]:find("stats failed",1,true)~=nil)
  local info_count=0;mod.info=function() info_count=info_count+1 end
  RW.tuning.probe=function() return {"animation"} end
  RW.tuning.describe=function() return {"stats"} end
  commands.gt_anim();commands.gt_tune()
  check("diagnostic commands: successful lines also reach the console log", info_count==2)
  RW.tuning.probe,RW.tuning.describe=original_probe,original_describe;mod.info=nil
  local original_update=RW.director.update
  local deltas={};RW.director.update=function(dt) deltas[#deltas+1]=dt end
  mod.update(0.1);mod.update(mod,0.2);mod.update()
  check("update adapter: dot/colon calls preserve dt and missing dt is ignored", #deltas==2 and deltas[1]==0.1 and deltas[2]==0.2)
  local original_error=mod.error;local errors=0;mod.error=function() errors=errors+1 end
  RW.director.update=function() error("director failed") end
  mod.update(0.1);mod.update(0.1)
  check("update adapter: repeated director exceptions log once without escaping", errors==1 and RW.update_failed==true)
  mod.error=original_error;RW.director.update=original_update;RW.update_failed=nil
end

RW.text_input_active = true
local subscription_owner = Managers.event
Managers.event = event_manager() -- unload must release the original manager
mod.on_unload()
check("unload: the flag is cleared and this instance's hook becomes a pass-through (stale hooks after a reload never block keys)", RW.dead == true and RW.text_input_active == false and (function() dmf_calls = {}; RW.text_input_active = true; hook(original); return #dmf_calls == 1 end)())
check("unload: both subscriptions are removed from their original manager", next(subscription_owner._events.event_mission_objective_start) == nil and next(subscription_owner._events.event_player_died) == nil)
local obsolete_calls = 0
RW.director.on_mission_started = function() obsolete_calls = obsolete_calls + 1 end
RW.director.on_player_died = function() obsolete_calls = obsolete_calls + 1 end
RW.director.update = function() obsolete_calls = obsolete_calls + 1 end
mod._on_mission_objective_start(); mod._on_player_died(); mod.update(1)
check("unload: captured objective, death and update callbacks are inert", obsolete_calls == 0)

-- bypass hooks installed by the entry (string class names, DMF delays them until the class exists)
local names = {}
for _, h in ipairs(hooks) do if type(h.obj) == "string" then names[#names + 1] = h.obj .. "." .. h.method end end
table.sort(names)
-- (2026-10-17) the gated hooks on classes that load after the mod are no longer made by name: they go through their files
check("entry: the four budget-bypass hooks and the custom-mods hooks still made by class name (burster explosion, the summoners: no summon while destroyed, no patrol, aggroed summons; the On Fire burn per player and its look; the net and pounce leave) are installed", table.concat(names, ",") == "BtChaosHoundLeapAction.leave,BtChaosPoxwalkerExplodeAction.enter,BtShootNetAction.leave,BtSummonMinionsAction._patrol_setup,BtSummonMinionsAction._summon_minions,BtSummonMinionsAction.leave,MinionBuffExtension._start_fx,MinionBuffExtension._stop_fx,MinionSpawnManager.num_spawned_minions,MinionSpawnManager.total_allocated_num_enemies,MinionSpawnManager.unregister_unit,PacingManager.add_aggroed_minion,PacingManager.set_minion_listening_for_player_deaths,PlayerUnitBuffExtension.add_internally_controlled_buff,SummonedMinionsExtension.can_summon_minions", table.concat(names, ","))
local GATED_FILES = {
  dread = { "scripts/extension_systems/mood/player_unit_mood_extension" },
  golden = { "scripts/ui/hud/elements/personal_player_panel/hud_element_personal_player_panel", "scripts/ui/hud/elements/team_player_panel/hud_element_team_player_panel" },
  charge = { "scripts/extension_systems/behavior/nodes/actions/bt_mutant_charger_charge_action" },
  health_writes = { "scripts/extension_systems/health/health_extension" },
  melee_attack = { "scripts/extension_systems/behavior/nodes/actions/bt_melee_attack_action" },
  spray = { "scripts/extension_systems/behavior/nodes/actions/bt_shoot_liquid_beam_action" },
  net = { "scripts/extension_systems/behavior/nodes/actions/bt_shoot_net_action" },
  leap = { "scripts/extension_systems/behavior/nodes/actions/bt_chaos_hound_leap_action" },
}
check("entry: MinionAttack and every gated class that loads after the mod are hooked through hook_require", #hook_requires == 13 and (function()
  local seen = {} for _, p in ipairs(hook_requires) do seen[p] = true end
  for _, paths in pairs(GATED_FILES) do for _, p in ipairs(paths) do if not seen[p] then return false end end end
  return seen["scripts/utilities/minion_attack"] and seen["scripts/extension_systems/buff/minion_buff_extension"] and seen["scripts/settings/buff/buff_templates"] and seen["scripts/ui/hud/elements/boss_health/hud_element_boss_health"]
end)(), table.concat(hook_requires, ","))
check("entry: not one hook on the player panels' base class (the game never makes one; class() copied its methods before any hook)", (function() for _, h in ipairs(hooks) do if h.obj == "HudElementPlayerPanelBase" then return false end end return true end)())
do
  -- (2026-10-04: "Attempting to rehook active hook [start_shooting]" at every game start) DMF runs a hook_require callback again
  -- each time the game loads the file; the same table is hooked once, a new table is hooked again
  local tuning, was_dead = mod.rw.tuning, mod.rw.tuning.dead
  tuning.dead = false
  local attack, other = {}, {}
  local before = #hooks
  require_by_path["scripts/utilities/minion_attack"](attack); require_by_path["scripts/utilities/minion_attack"](attack)
  local once = #hooks - before
  require_by_path["scripts/utilities/minion_attack"](other)
  check("entry: a file loaded again does not hook the same table twice (start_shooting once; a new table again)", once == 1 and hooks[#hooks].method == "start_shooting" and #hooks - before == 2, once)
  tuning.dead = was_dead
end
do
  -- the summoners (2026-10-04): a summoner being destroyed never summons; a wave's summoner leads no patrol and fights
  local T = mod.rw.tuning
  local was_dead = T.dead
  T.dead = false
  local function find(method) for _, h in ipairs(hooks) do if h.obj == "BtSummonMinionsAction" and h.method == method then return h.fn end end end
  local called, got = 0, nil
  local function original(self, unit, breed, bb, scratchpad, action_data, t, reason, destroy) called = called + 1; got = scratchpad.summoned_success end
  local leave = find("leave")
  local pad = { summoned_success = false }
  leave(original, {}, "u", {}, {}, pad, {}, 1, "aborted", true)
  local pad2 = { summoned_success = false }
  leave(original, {}, "u", {}, {}, pad2, {}, 1, "aborted", false)
  check("summoners: a summoner being destroyed (despawn, mission cleanup) does not summon in its leave; one that only leaves the action still does", called == 2 and pad.summoned_success == true and pad2.summoned_success == false)
  local mine, theirs = { name = "mine" }, { name = "theirs" }
  local real_tracked = mod.rw.bypass.is_tracked
  mod.rw.bypass.is_tracked = function(u) return u == mine end
  local patrols = 0
  local patrol = find("_patrol_setup")
  patrol(function() patrols = patrols + 1 end, {}, mine); patrol(function() patrols = patrols + 1 end, {}, theirs)
  check("summoners: a wave's summoner sets up no patrol; the game's own still does", patrols == 1)
  local aggroed, retargeted = {}, {}
  local function perception(u) return { aggro_state = function() return "passive" end, aggro = function() aggroed[u] = true end, force_new_target_attempt = function() retargeted[u] = true end } end
  local hound1, hound2 = { h = 1 }, { h = 2 }
  local saved_su, saved_unit = ScriptUnit, Unit
  ScriptUnit = { has_extension = function(u, name) if name == "perception_system" then return perception(u) end return nil end }
  Unit = Unit or {}
  local after = nil
  for _, h in ipairs(hooks) do if h.obj == "BtSummonMinionsAction" and h.method == "_summon_minions" then after = h.fn end end
  after({}, mine, {}, {}, { summoned_minions_extension = { summoned_minions = function() return { hound1, hound2 } end } })
  after({}, theirs, {}, {}, { summoned_minions_extension = { summoned_minions = function() return { hound1 } end } })
  check("summoners: what a wave's summoner summons comes in aggroed (with a target), and so does it; the game's own are left alone", aggroed[hound1] and aggroed[hound2] and aggroed[mine] and retargeted[hound2] and not aggroed[theirs])
  aggroed = {}
  HEALTH_ALIVE = HEALTH_ALIVE or {}
  local unit_alive = Unit.alive
  Unit.alive = function() return true end
  HEALTH_ALIVE[mine] = true
  T.watch_summoner(mine, "chaos_ogryn_houndmaster"); T.watch_summoner(theirs, "renegade_gunner")
  T.update(0.5)
  local early = aggroed[mine]
  T.update(0.6)
  check("summoners: a wave's Packmaster is watched (a gunner is not) and made to fight again once a second", T.summoner_count() >= 1 and not early and aggroed[mine] == true)
  local broken = { name = "broken" }
  HEALTH_ALIVE[broken] = true
  T.watch_summoner(broken, "chaos_ogryn_houndmaster")
  ScriptUnit.has_extension = function(u, name) if u == broken then error("extension gone") end if name == "perception_system" then return perception(u) end return nil end
  T.update(1.1)
  check("summoners: one that cannot be made to fight is contained (warned), the others still are", T.summoner_count() >= 1)
  HEALTH_ALIVE[broken] = nil
  HEALTH_ALIVE[mine] = nil; T.update(1.1)
  check("summoners: a dead summoner is no longer watched", T.summoner_count() == 0)
  Unit.alive = unit_alive
  ScriptUnit, Unit = saved_su, saved_unit
  mod.rw.bypass.is_tracked = real_tracked
  T.dead = was_dead
end
do
  -- On Fire damage (2026-10-04): a group's burn share scales the burn of the players its enemies set on fire; the game's own otherwise
  local T = mod.rw.tuning
  local was_dead = T.dead
  T.dead = false
  local enemy, scaled_player, plain_player = { name = "enemy" }, { name = "p1" }, { name = "p2" }
  local hits, game_burns = {}, 0
  local templates = {
    common_minion_on_fire = { interval_func = function(td, tc)
      T.on_player_buff_added({ _unit = scaled_player }, "hit_by_common_enemy_flame")
      T.on_player_buff_added({ _unit = scaled_player }, "something_else")
    end },
    hit_by_common_enemy_flame = { interval_func = function() game_burns = game_burns + 1 end },
  }
  check("on fire: the burn templates are wrapped once", T.wrap_fire_templates(templates) == true and T.wrap_fire_templates(templates) == false)
  local saved = { HEALTH_ALIVE = HEALTH_ALIVE, preload = {}, difficulty = Managers.state and Managers.state.difficulty }
  HEALTH_ALIVE = { [scaled_player] = true, [plain_player] = true }
  package.preload["scripts/utilities/attack/attack"] = function() return { execute = function(unit, profile, k1, power) hits[#hits + 1] = { unit, power } end } end
  package.preload["scripts/settings/damage/damage_profile_templates"] = function() return { horde_flame_impact = "flame" } end
  package.preload["scripts/settings/difficulty/minion_difficulty_settings"] = function() return { power_level = { chaos_engulfed_enemy_fire_attack = "table" } } end
  Managers.state = Managers.state or {}
  Managers.state.difficulty = { get_table_entry_by_challenge = function() return 400 end }
  -- an enemy without a share: the game's own burn
  templates.common_minion_on_fire.interval_func({}, { unit = { name = "other" } })
  templates.hit_by_common_enemy_flame.interval_func({}, { unit = plain_player })
  check("on fire: an enemy of a group without a setting leaves the game's burn untouched", game_burns == 1 and #hits == 0 and T.burn_share(scaled_player) == nil)
  T.mark_fire(enemy, { burn = 50 })
  check("on fire: the group's setting is kept for its enemies (50 percent)", T.fire_share(enemy) == 0.5)
  local plain_enemy = { name = "plain" }
  T.mark_fire(plain_enemy, nil); T.mark_fire(nil, nil)
  check("on fire: a wave's enemy whose group sets nothing burns at the default, 35 percent", T.fire_share(plain_enemy) == 0.35 and T.BURN_DEFAULT == 35)
  templates.common_minion_on_fire.interval_func({}, { unit = enemy })
  templates.hit_by_common_enemy_flame.interval_func({}, { unit = scaled_player, is_server = true })
  check("on fire: a player that enemy set on fire burns at half the power level", T.burn_share(scaled_player) == 0.5 and #hits == 1 and hits[1][1] == scaled_player and hits[1][2] == 200 and game_burns == 1)
  T.mark_fire(enemy, { burn = 0 })
  templates.common_minion_on_fire.interval_func({}, { unit = enemy })
  templates.hit_by_common_enemy_flame.interval_func({}, { unit = scaled_player })
  check("on fire: at 0 the burn does no damage at all", #hits == 1 and game_burns == 1)
  -- the hooks as registered: the templates file loaded (again) is wrapped once; the player buff hook marks the player
  local fresh = { common_minion_on_fire = { interval_func = function() error("boom") end }, hit_by_common_enemy_flame = { interval_func = function() end } }
  require_by_path["scripts/settings/buff/buff_templates"](fresh)
  check("on fire: the registered hook wraps the templates when the game loads them", fresh.common_minion_on_fire.__rw_wrapped == true)
  check("on fire: an enemy interval that fails still clears its share (the error goes on to the game)", not pcall(fresh.common_minion_on_fire.interval_func, {}, { unit = enemy }) and (function() T.on_player_buff_added({ _unit = plain_player }, "hit_by_common_enemy_flame"); return T.burn_share(plain_player) == nil end)())
  local buff_hook
  for _, h in ipairs(hooks) do if h.obj == "PlayerUnitBuffExtension" then buff_hook = h.fn end end
  buff_hook({ _unit = plain_player }, "hit_by_common_enemy_flame")
  check("on fire: the player buff hook only marks while a scaled enemy burns", T.burn_share(plain_player) == nil)
  T.dead = true
  templates.hit_by_common_enemy_flame.interval_func({}, { unit = scaled_player })
  check("on fire: a retired mod gives the burn back to the game", game_burns == 2)
  T.dead = false
  -- the On Fire look kept on while the enemy lives (2026-10-05: it lasted 1 s after the spawn)
  local saved_unit_table = Unit
  Unit = Unit or {}
  local saved_world, saved_unit_world, saved_set_v3, saved_v3 = World, Unit.world, Unit.set_vector3_for_materials, Vector3
  local clock, written = 10, {}
  World = { time = function() return clock end }
  Unit.world = function() return "world" end
  Unit.set_vector3_for_materials = function(unit, key, value, children) written[#written + 1] = { unit = unit, key = key, v = value, children = children } end
  Vector3 = function(x, y, z) return { x = x, y = y, z = z } end
  package.loaded["scripts/settings/ailments/ailment_settings"] = { effect_templates = { burning = { offset_time = 1.2, duration = 2 } } }
  local start_fx, stop_fx, health_hooks, boss_hooks = nil, nil, {}, {}
  -- the health writes are hooked on HealthExtension's file when the game loads it (2026-10-17)
  -- (the mod was unloaded above, which retires the gate: it is live again for this block, as the tuning is)
  local HealthClass = { add_damage = function() end, add_heal = function() end, set_health_instant = function() end }
  RW.hook_gate.init({ mod = mod })
  require_by_path["scripts/extension_systems/health/health_extension"](HealthClass)
  RW.hook_gate.retire()
  for _, h in ipairs(hooks) do
    if h.obj == "MinionBuffExtension" and h.method == "_start_fx" then start_fx = h.fn end
    if h.obj == "MinionBuffExtension" and h.method == "_stop_fx" then stop_fx = h.fn end
    if h.obj == HealthClass and h.safe then health_hooks[#health_hooks + 1] = h.fn end
  end
  local burning, other_buff = { name = "burning enemy" }, { name = "enraged enemy" }
  HEALTH_ALIVE[burning], HEALTH_ALIVE[other_buff] = true, true
  start_fx({ _unit = burning }, 1, { name = "common_minion_on_fire" })
  start_fx({ _unit = burning }, 2, { name = "common_minion_on_fire" })
  start_fx({ _unit = other_buff }, 1, { name = "havoc_enraged" })
  start_fx({}, 1, { name = "common_minion_on_fire" }); start_fx({ _unit = other_buff }, 1, nil)
  check("on fire look: an On Fire enemy is kept burning (once), no other buff", T.glow_count() == 1)
  clock = 10.3; T.update_glow(0.3)
  check("on fire look: nothing is written before half a second", #written == 0)
  clock = 13; T.update_glow(0.3)
  check("on fire look: its burning look runs on: the same start, the end 3 s ahead of now, on the whole unit", #written == 1 and written[1].unit == burning and written[1].key == "offset_time_duration" and written[1].v.x == 1.2 and written[1].v.y == 10 and written[1].v.z == 6 and written[1].children == true)
  stop_fx({ _unit = burning }, 1, { name = "common_minion_on_fire" })
  clock = 14; T.update_glow(0.6)
  check("on fire look: when the buff ends it is left to fade", T.glow_count() == 0 and #written == 1)
  start_fx({ _unit = burning }, 1, { name = "common_minion_on_fire" })
  HEALTH_ALIVE[burning] = nil; T.update_glow(0.6)
  check("on fire look: a dead enemy is let go (its look fades as the game's own)", T.glow_count() == 0 and #written == 1)
  HEALTH_ALIVE[burning] = true
  World = nil
  start_fx({ _unit = burning }, 1, { name = "common_minion_on_fire" })
  World = { time = function() error("no world") end }
  local echo_before = #echoed
  T.update_glow(0.6)
  check("on fire look: a unit whose look cannot be written is let go, said once", T.glow_count() == 0)
  World = { time = function() return clock end }
  T.dead = true
  start_fx({ _unit = burning }, 1, { name = "common_minion_on_fire" })
  check("on fire look: a retired mod keeps nothing burning", T.glow_count() == 0)
  T.dead = false
  start_fx({ _unit = burning }, 1, { name = "common_minion_on_fire" })
  T.reset()
  check("on fire look: a reset lets every enemy go", T.glow_count() == 0)
  -- the divided health and the boss bars, as registered
  for _, fn in ipairs(health_hooks) do fn({ _health = 10 }) end
  check("divided health: the three health writes of the game are followed (a unit within the limit is left alone)", #health_hooks == 3)
  local bars = { update = function() end }
  require_by_path["scripts/ui/hud/elements/boss_health/hud_element_boss_health"](bars)
  require_by_path["scripts/ui/hud/elements/boss_health/hud_element_boss_health"](bars)
  for _, h in ipairs(hooks) do if h.obj == bars and h.method == "update" then boss_hooks[#boss_hooks + 1] = h.fn end end
  local went_through = boss_hooks[1] and boss_hooks[1](function(self, dt) return dt end, { _active_targets_array = {} }, 0.5)
  check("boss bar: its update is hooked once per loaded class, and the game's update still runs", #boss_hooks == 1 and went_through == 0.5)
  World, Unit.world, Unit.set_vector3_for_materials, Vector3 = saved_world, saved_unit_world, saved_set_v3, saved_v3
  Unit = saved_unit_table
  package.loaded["scripts/settings/ailments/ailment_settings"] = nil
  HEALTH_ALIVE = saved.HEALTH_ALIVE
  Managers.state.difficulty = saved.difficulty
  T.dead = was_dead
end
-- the rename (2026-10-05): RealmsWaves became The Grandfather's Tarot; its saved settings are copied once, the commands are /gt_
do
  local RW = mod.rw
  local saved_get, saved_set, saved_app = mod.get, mod.set, Application
  local store = {}
  mod.get = function(self, id) return store[id] end
  mod.set = function(self, id, v) store[id] = v end
  Application = { user_setting = function(k) if k == "mods_settings" then return { RealmsWaves = { wave_def_custom_1 = "The Fool", mode = "vote", hud_scale = 120 }, Other = { x = 1 } } end end }
  check("rename: the first load copies every saved setting of RealmsWaves (decks, presets, options), only those", RW.migrate_old_settings() == 3 and store.mode == "vote" and store.wave_def_custom_1 == "The Fool" and store.hud_scale == 120 and store.x == nil and store.gt_settings_migrated == true)
  store.mode = "tarot"
  check("rename: it happens once (a setting changed afterwards stays)", RW.migrate_old_settings() == 0 and store.mode == "tarot")
  store = {}; Application = { user_setting = function() return nil end }
  check("rename: nothing saved under the old name copies nothing and is marked done", RW.migrate_old_settings() == 0 and store.gt_settings_migrated == true)
  store = {}; Application = nil
  check("rename: no settings store at all is not an error", RW.migrate_old_settings() == 0)
  mod.get, mod.set, Application = saved_get, saved_set, saved_app
  local old = {}
  for name in pairs(commands) do if not name:find("^gt_") then old[#old + 1] = name end end
  check("rename: every command is /gt_ (none left as /rw_)", #old == 0 and commands.gt_editor ~= nil, table.concat(old, ","))
  local L = dofile(BASE .. "/GrandfathersTarot_localization.lua")
  check("rename: the menu title is The Grandfather's Tarot in the Nurgle colours, each section header coloured", L.mod_name.en:find("The Grandfather's ", 1, true) and L.mod_name.en:find("Tarot", 1, true) and L.mod_name.en:find("{#color(128,160,52)}", 1, true) and L.group_timing.en:find("^{#color%(") and L.group_timing.en:find("Timing and voting{#reset()}", 1, true) and L.group_spread.en:find("^{#color%(") and L.view_title_cauldron.en == "The Grandfather's Workshop")
end
check("entry: editor view registered under its name with the right class", #views == 1 and views[1].view_name == "realms_waves_editor" and views[1].view_settings.class == "GrandfathersTarotView")
check("entry: /gt_test_close is registered too", type(commands.gt_test_close) == "function")
check("entry: /gt_drawtest and /gt_fulltest are registered (a staged draw to test the HUD, with or without the sound and the wave)", type(commands.gt_drawtest) == "function" and type(commands.gt_fulltest) == "function")
do
  local before = #echoed
  commands.gt_drawtest(); commands.gt_fulltest("  ")
  local usage = echoed[before + 1] and echoed[before + 2] and echoed[before + 1]:find("usage /gt_drawtest", 1, true) and echoed[before + 2]:find("usage /gt_fulltest", 1, true)
  commands.gt_drawtest("The", "Fool")
  check("entry: /gt_drawtest and /gt_fulltest say how to use them without a name, and pass a name on (refused here: no running cycle)", usage ~= nil and #echoed == before + 3 and echoed[#echoed]:find("GrandfathersTarot:", 1, true) ~= nil, echoed[#echoed])
end
check("entry: four HUD elements are registered, the Spread, the Nightmare's dread and Dream's sky (full screen, not HUD-scaled) and the window of the last card (own node, so custom_hud moves it on its own)", #hud_elements == 4 and hud_elements[1].class_name == "HudElementGrandfathersTarotPanel" and hud_elements[2].class_name == "HudElementGrandfathersTarotDread" and hud_elements[2].use_hud_scale == false and hud_elements[3].class_name == "HudElementGrandfathersTarotDream" and hud_elements[3].use_hud_scale == false and hud_elements[3].filename:find("hud_element_dream$") ~= nil and hud_elements[4].class_name == "HudElementGrandfathersTarotLast" and hud_elements[4].filename:find("hud_element_last_card$") ~= nil and hud_elements[4].use_hud_scale == true, #hud_elements)
check("entry: commands registered (rw_test, rw_editor, rw_status, rw_custom, rw_roll, rw_start, rw_skip, rw_vote)", commands.gt_test and commands.gt_editor and commands.gt_status and commands.gt_custom and commands.gt_roll and commands.gt_start and commands.gt_skip and commands.gt_vote ~= nil)
-- Instant rescue's golden health (2026-10-05): the player panels draw their health in the overshield colour while a charge is armed
-- and the player has more than one wound left; the colour is swapped only for the draw
do
  local golden = {}
  -- (2026-10-17) hooked on the two panel files when the game loads them (not by name, and not the base class)
  -- (the mod was unloaded above, which retires the gate: it is live again for this block)
  local Personal, Team = { _draw_health_bar = function() end }, { _draw_health_bar = function() end }
  RW.hook_gate.init({ mod = mod })
  require_by_path[GATED_FILES.golden[1]](Personal)
  require_by_path[GATED_FILES.golden[2]](Team)
  for _, h in ipairs(hooks) do if h.method == "_draw_health_bar" then golden[#golden + 1] = h end end
  local RW = mod.rw
  local saved_effects, saved_settings, saved_dead = RW.effects, package.loaded["scripts/settings/ui/ui_hud_settings"], RW.dead
  RW.dead = nil
  local charges = 1
  RW.effects = { team_rescues = function() return charges end }
  local Settings = { color_tint_main_1 = "white", color_tint_10 = "gold" }
  package.loaded["scripts/settings/ui/ui_hud_settings"] = Settings
  local seen
  local function draw(self, x) seen = Settings.color_tint_main_1; return x end
  local three = { _health_max_fraction = 1, _health_max_wounds = 3 }
  check("golden health: the two player panel classes the game makes are hooked, on their own tables, as normal hooks", #golden == 2 and golden[1].obj == Personal and golden[2].obj == Team and not golden[1].safe and not golden[2].safe)
  check("golden health: and both are held by the gate", (function() for _, n in ipairs(RW.hook_gate.names()) do if n == "golden" then return true end end return false end)())
  RW.hook_gate.retire()
  local fn = golden[1].fn
  fn(draw, three, 1)
  check("golden health: a charge armed and three wounds left: the health is drawn gold, the colour is put back after", seen == "gold" and Settings.color_tint_main_1 == "white")
  fn(draw, { _health_max_fraction = 1 / 3, _health_max_wounds = 3 }, 1)
  check("golden health: one wound left: the usual colour", seen == "white")
  fn(draw, { _health_max_fraction = 2 / 3, _health_max_wounds = 3 }, 1)
  check("golden health: two wounds left (corruption took one): gold", seen == "gold")
  for _, state in ipairs({ "_dead", "_knocked_down", "_hogtied" }) do
    local panel = { _health_max_fraction = 1, _health_max_wounds = 3 }
    panel[state] = true
    fn(draw, panel, 1)
    check("golden health: none on a player " .. state:sub(2), seen == "white")
  end
  charges = 0
  fn(draw, three, 1)
  check("golden health: no charge armed: the usual colour", seen == "white")
  charges = 1
  local ok = pcall(fn, function() error("draw failed") end, three)
  check("golden health: an error in the game's draw is passed on and the colour is still put back", not ok and Settings.color_tint_main_1 == "white")
  RW.effects = nil
  fn(draw, three, 1)
  check("golden health: without the effects module: the usual colour", seen == "white")
  RW.dead = true
  fn(draw, three, 1)
  check("golden health: a retired mod draws the usual colour", seen == "white")
  RW.effects, package.loaded["scripts/settings/ui/ui_hud_settings"], RW.dead = saved_effects, saved_settings, saved_dead
end
check("entry: keybind functions exist (open_editor, vote_1..vote_5)", type(mod.open_editor) == "function" and type(mod.vote_1) == "function" and type(mod.vote_5) == "function")

-- Retain strong object keys just as game EventManager does. DMF-owned registries
-- are released between generations, so weak-reference survival detects event ownership.
local helpers = {"hook","hook_safe","hook_require","register_hud_element","add_require_path","register_view","command","get","set","echo","warning","error","localize","io_dofile"}
local prototype = mod
local tracing = jit and jit.status()
if jit then jit.off(); jit.flush() end -- ownership check excludes compiler traces
local weak = setmetatable({}, {__mode="k"})
local manager = event_manager()
Managers.event = manager
for i=1,100 do
  mod = {}; for _,key in ipairs(helpers) do mod[key] = prototype[key] end
  dofile(BASE .. "/GrandfathersTarot.lua"); mod.on_all_mods_loaded()
  weak[mod] = true
  if i % 2 == 0 then Managers.event = nil end
  mod.on_unload(); mod.on_unload()
  Managers.event = manager
  hooks, views, commands, hook_requires, require_callbacks, require_by_path = {}, {}, {}, {}, {}, {}
end
mod = nil
collectgarbage("collect"); collectgarbage("collect")
check("reload: 100 generations release strong event keys and obsolete weak mod references", next(weak) == nil and next(manager._events.event_mission_objective_start) == nil and next(manager._events.event_player_died) == nil)
mod = {}; for _,key in ipairs(helpers) do mod[key] = prototype[key] end
Managers.event = nil
local missing_ok = pcall(function() dofile(BASE .. "/GrandfathersTarot.lua"); mod.on_all_mods_loaded();mod.on_unload() end)
check("reload: missing event manager is safe at initialization and unload", missing_ok)
dofile(BASE .. "/GrandfathersTarot.lua");mod.on_all_mods_loaded()
Managers.event=event_manager()
mod.on_game_state_changed("enter","GameplayStateRun")
check("reload: a manager that appears after initialization registers on gameplay entry", Managers.event._events.event_mission_objective_start[mod]~=nil and Managers.event._events.event_player_died[mod]~=nil)
mod.on_unload()
if tracing then jit.on() end

-- Real entry + director + executor + tuning, with only native minion/position
-- boundaries faked. DMF disables hooks before on_disabled and still sends updates.
mod = {}; for _,key in ipairs(helpers) do mod[key] = prototype[key] end
local settings = {max_alive=10,max_per_wave=500,initial_delay=600,interval_min=600,interval_random=false,mode="random"}
local enabled, server = true, true
mod.get = function(self,id) return settings[id] end
mod.set = function(self,id,value) settings[id] = value end
mod.is_enabled = function() return enabled end
hooks, views, commands, hook_requires, require_callbacks, require_by_path = {}, {}, {}, {}, {}, {}
Managers.event = event_manager()
local spawned, dead = {}, {}
ALIVE = setmetatable({}, {__index=function(_,unit) return not dead[unit] end})
Vector3 = function(x,y,z) return {x=x,y=y,z=z} end
Unit = {world_rotation=function() return "rot" end,alive=function(unit) return not dead[unit] end,set_local_scale=function(unit,node,v) unit.size=v.x end}
ScriptUnit = {has_extension=function(unit,system) return system=="buff_system" and unit.buffs or nil end}
Managers.state = {
  game_session={is_server=function() return server end},
  game_mode={game_mode=function() return {name=function() return "coop_complete_objective" end} end},
  main_path={is_main_path_ready=function() return true end},
  extension={system=function() return {get_side_from_name=function() return {side_id=2} end} end},
  unit_spawner={game_object_id=function(self,unit) return unit.id end},
  minion_spawn={request_param_table=function() return {} end,spawn_minion=function()
    local stats={melee_attack_speed=1};local unit={id=#spawned+1,buffs={stat_buffs=function() return stats end,_update_stat_buffs_and_keywords=function() end,_reset_stat_buffs=function() end},stats=stats}
    spawned[#spawned+1]=unit;return unit
  end},
}
dofile(BASE .. "/GrandfathersTarot.lua");mod.on_all_mods_loaded()
RW=mod.rw
local positions={player_units=function() return {"player"} end,random_player_unit=function() return "player" end,candidates=function() return {"point"} end,pick=function() return "point" end,spread=function(p) return p end}
RW.execute.init({positions=positions,bypass=RW.bypass,groups=RW.groups,tuning=RW.tuning})
RW.director.init({events=RW.events,groups=RW.groups,protocol=RW.protocol,execute=RW.execute,votes=RW.votes,positions=positions,presets=RW.presets,cards=RW.cards,tuning=RW.tuning})
mod.on_game_state_changed("enter","GameplayStateRun");mod._on_mission_objective_start();mod.update(0.01)
RW.execute.start_wave({name="pause",parts=RW.groups.parse("2 hounds@2"),rep_every=1,rep_for=10})
RW.director.pause(true);local remaining=RW.director.view().remaining
for i=1,200 do mod.update(1) end
check("pause: real executor freezes feed, repeat and timeout clocks", #spawned==0 and RW.execute.status().queued==2 and RW.execute.status().jobs==1 and RW.director.view().remaining==remaining)
RW.director.pause(false);mod.update(0.2)
check("resume: initial work continues without catching up paused repeats", #spawned==2 and RW.execute.status().queued==0)
mod.update(1)
check("resume: exactly the next repeat becomes due", #spawned==4)
local living=spawned[1]
RW.tuning.apply(living,{gap=50,size=130},"chaos_hound")
RW.director.stop()
check("stop: cancel jobs but retain live accounting, tuning and size snapshot", RW.execute.status().jobs==0 and RW.bypass.count()==4 and RW.tuning.status().tuned==1 and RW.tuning.status().sizes_known==1)
living.stats.melee_attack_speed=1
-- (2026-10-06) the recompute is watched on the tuned unit's own buff extension, as the game calls it (self:...)
living.buffs:_reset_stat_buffs(); living.buffs:_update_stat_buffs_and_keywords()
check("stop: native buff recompute still reasserts the factor", living.stats.melee_attack_speed==2)
RW.director.force_start();RW.execute.start_wave({name="cap",parts=RW.groups.parse("60 hounds")})
for i=1,20 do mod.update(0.2) end
check("restart: surviving units count against the combined alive cap", #spawned==10 and RW.bypass.count()==10)
enabled=false;mod.on_disabled(false)
local disabled_stats=living.stats.melee_attack_speed
for i=1,20 do mod.update(1) end
RW.execute.update(1)
check("disable: queued work is cancelled and DMF updates cannot spawn", #spawned==10 and RW.execute.status().jobs==0 and RW.director.is_stopped())
check("disable: explicit commands cannot admit a new spawn job", not RW.execute.start_wave({parts=RW.groups.parse("1 hound")}) and RW.execute.status().jobs==0)
check("disable: surviving ownership is retained without tuning writes", RW.bypass.count()==10 and RW.tuning.status().tuned==1 and living.stats.melee_attack_speed==disabled_stats)
dead[living]=true;mod.update(1)
check("disable: vanished owned units are pruned", RW.bypass.count()==9)
enabled=true;mod.on_enabled(false);mod.update(1)
check("enable: no stale replay and host waits for explicit start", #spawned==10 and RW.director.is_stopped() and RW.tuning.status().tuned==0)
server=false;RW.director.on_enter_gameplay()
RW.director.on_state("host",{p="waiting",m="random",r=99,b=1,k={}})
RW.tuning.receive({{id=999,pct=130}})
enabled=false;mod.on_disabled(false);enabled=true;mod.on_enabled(false)
check("enable: client discards stale presentation and pending sizes before re-handshake", RW.director.view().phase=="off" and RW.tuning.status().pending==0)
server=true;RW.director.on_enter_gameplay()
RW.director.force_start();RW.execute.start_wave({parts=RW.groups.parse("2 hounds@1"),rep_every=1,rep_for=10})
mod.update(0.2)
mod.on_unload()
check("unload: real pending jobs and director state are torn down", RW.execute.status().jobs==0 and RW.execute.status().queued==0 and RW.director.view().phase=="off" and RW.bypass.count()==0 and RW.tuning.status().sizes_known==0)

-- The audit's 32 legal timer fixture exercises aggregate limits with real owners.
dofile(BASE .. "/GrandfathersTarot.lua");mod.on_all_mods_loaded();RW=mod.rw
RW.execute.init({positions=positions,bypass=RW.bypass,groups=RW.groups,tuning=RW.tuning})
RW.director.init({events=RW.events,groups=RW.groups,protocol=RW.protocol,execute=RW.execute,votes=RW.votes,positions=positions,presets=RW.presets,cards=RW.cards,tuning=RW.tuning})
settings.mult_normal=500;settings.mult_special=500
for _,key in ipairs(RW.events.keys()) do
  RW.events.set_def(function(id,value) settings[id]=value end,key,key,RW.groups.parse("60 hounds@60, 60 poxwalkers@60"),RW.groups)
  settings["on_"..key]=true;settings["ev_"..key]=5;settings["re_"..key]=1;settings["rf_"..key]=3600
end
mod.on_game_state_changed("enter","GameplayStateRun");mod._on_mission_objective_start();mod.update(0.01)
for i=1,10 do RW.bypass.track({id=1000+i}) end
local bounded=true
for i=1,10000 do
  mod.update(0.016)
  local status=RW.execute.status()
  bounded=bounded and status.jobs<=64 and status.queued<=8000
end
check("aggregate: 32 legal timers stay within 64 jobs / 8000 pending over 10000 updates", bounded and RW.execute.status().queued==8000)
local before_jobs,before_queue=RW.execute.status().jobs,RW.execute.status().queued
local admitted=RW.execute.start_wave({parts=RW.groups.parse("1 hound")})
check("aggregate: admission rejects a full budget atomically", not admitted and RW.execute.status().jobs==before_jobs and RW.execute.status().queued==before_queue)
RW.execute.reset()
for i=1,10 do RW.bypass.track({id=2000+i}) end
for i=1,14 do RW.execute.start_wave({parts=RW.groups.parse("60 hounds, 60 poxwalkers")}) end
RW.execute.start_wave({parts=RW.groups.parse("60 hounds")})
RW.execute.start_wave({parts=RW.groups.parse("44 hounds@60, 36 poxwalkers@60"),rep_every=1,rep_for=30})
local partial_admitted=RW.execute.start_wave({parts=RW.groups.parse("60 hounds, 60 poxwalkers")})
check("aggregate: insufficient partial admission room rejects the whole initial batch", not partial_admitted and RW.execute.status().queued==7700)
-- (2026-10-11) a card's repeats run from its first enemy: one of repeats only runs them from the start (the one above has not spawned)
RW.execute.start_wave({parts=RW.groups.parse("0 hounds@60, 0 poxwalkers@60"),rep_every=1,rep_for=30})
RW.execute.update(1)
check("aggregate: repeat clips to remaining shared capacity without overshoot", RW.execute.status().queued==8000)
RW.execute.reset()
local accepted=0
for i=1,65 do if RW.execute.start_wave({parts=RW.groups.parse("0 hounds@1"),rep_every=1,rep_for=60}) then accepted=accepted+1 end end
check("aggregate: repeat-only jobs cannot evade the 64-job limit", accepted==64 and RW.execute.status().jobs==64)
for i=1,20 do RW.execute.update(1) end
check("aggregate: bounded repeat-only jobs still make progress", RW.execute.status().tracked>0 and RW.execute.status().queued<=8000)
mod.on_unload()
check("aggregate: unload releases both budgets and all owned units", RW.execute.status().jobs==0 and RW.execute.status().queued==0 and RW.bypass.count()==0)
local installed_hooks=#hooks
require_callbacks[#require_callbacks]({})
check("retire: delayed hook-require callback cannot install new hooks after unload", #hooks==installed_hooks)
check("retire: captured executor cannot admit work after unload", not RW.execute.start_wave({parts=RW.groups.parse("1 hound")}) and RW.execute.status().jobs==0)

-- (2026-10-07) asleep in a game the cards cannot play in (core/dormancy.lua: "Tarot should be disabled in a normal online game")
do
  mod = {}; for _,key in ipairs(helpers) do mod[key] = prototype[key] end
  local toggles, guard = {}, {}
  local on = true
  local saved_state, saved_event, saved_mod = Managers.state, Managers.event, mod
  mod.is_enabled = function() return on end
  mod.disable_all_hooks = function() toggles[#toggles + 1] = "off" end
  mod.enable_all_hooks = function() toggles[#toggles + 1] = "on" end
  mod.hook_enable = function(self, obj, method) guard[#guard + 1] = (obj == dmf_mod and method or "?") .. ":on" end
  mod.hook_disable = function(self, obj, method) guard[#guard + 1] = (obj == dmf_mod and method or "?") .. ":off" end
  hooks, views, commands, hook_requires, require_callbacks, require_by_path, hud_elements = {}, {}, {}, {}, {}, {}, {}
  Managers.event = event_manager()
  local server = false
  Managers.state = { game_session = { is_server = function() return server end } }
  dofile(BASE .. "/GrandfathersTarot.lua"); mod.on_all_mods_loaded()
  local RW = mod.rw
  local D = RW.dormancy
  local valid = 0
  for _, spec in ipairs(hud_elements) do if type(spec.validation_function) == "function" then valid = valid + 1 end end
  check("sleep: every HUD element of the mod has a validation function", #hud_elements == 4 and valid == 4, #hud_elements .. "/" .. valid)
  local director_updates = 0
  local real_update = RW.director.update
  RW.director.update = function(...) director_updates = director_updates + 1 end
  local audio = 0
  local real_audio = RW.effects.tick_audio
  RW.effects.tick_audio = function() audio = audio + 1 end

  -- an official game (Fatshark's server: not ours to host, no Realms session)
  mod.update(0.016)
  check("sleep: the keybind guard is off while no text box is open", guard[#guard] == "check_keybinds:off" and #guard == 1, table.concat(guard, ","))
  mod.on_game_state_changed("enter", "GameplayStateRun")
  mod.update(0.016)
  check("sleep: an official game puts every hook to sleep", D.is_asleep() and toggles[#toggles] == "off" and #toggles == 1, table.concat(toggles, ","))
  check("sleep: the HUD elements are not created there", hud_elements[1].validation_function() == false and hud_elements[4].validation_function() == false)
  local before = director_updates
  for _ = 1, 20 do mod.update(0.1) end
  check("sleep: the director does not run, the editor's sounds still do", director_updates == before and audio >= 20, director_updates .. " " .. audio)
  check("sleep: the switch-off is applied again a few seconds in (hooks DMF creates late)", #toggles == 2 and toggles[2] == "off", table.concat(toggles, ","))
  for _ = 1, 400 do mod.update(0.1) end
  check("sleep: ...at 2, 10 and 30 s, then never again", #toggles == 4, #toggles)
  RW.text_input_active = true; mod.update(0.016)
  check("sleep: a text box of the editor turns the keybind guard on, even asleep", guard[#guard] == "check_keybinds:on", table.concat(guard, ","))
  RW.text_input_active = false; mod.update(0.016)
  check("sleep: ...and off again when it closes", guard[#guard] == "check_keybinds:off")

  -- back to the menu: awake; a SoloPlay or Realms game this machine hosts stays awake
  mod.on_game_state_changed("exit", "GameplayStateRun")
  check("sleep: leaving the game wakes the hooks", not D.is_asleep() and toggles[#toggles] == "on")
  server = true
  local n = #toggles
  mod.on_game_state_changed("enter", "GameplayStateRun"); for _ = 1, 400 do mod.update(0.1) end
  check("sleep: a game this machine hosts stays awake (no toggle), the director runs", not D.is_asleep() and #toggles == n and director_updates > before and hud_elements[1].validation_function() == true)

  -- the client of a Realms server stays awake; Realms there but no session of its own: asleep
  server = false
  REALMS_STUB = { _session = { is_active_client = function() return true end } }
  check("sleep: a Realms server's client can play", D.playable() == true)
  REALMS_STUB = { _session = { is_active_client = function() return false end } }
  check("sleep: Realms installed, an official game: cannot", D.playable() == false)
  REALMS_STUB = { _session = { is_active_client = function() error("boom") end } }
  check("sleep: a failing Realms answer counts as no", D.playable() == false)
  REALMS_STUB = nil
  Managers.state = {}
  check("sleep: no session yet: awake (unknown)", D.playable() == true)
  Managers.state = { game_session = { is_server = function() return false end } }

  -- the mod switched off in DMF's options: never woken from here; switched on again: asleep again
  mod.on_game_state_changed("enter", "GameplayStateRun"); mod.update(0.016)
  check("sleep: asleep again in the next official game", D.is_asleep())
  on = false; n = #toggles
  D.on_exit_gameplay()
  check("sleep: leaving while the mod is off in DMF does not switch its hooks on", #toggles == n and not D.is_asleep())
  on = true
  mod.on_game_state_changed("enter", "GameplayStateRun"); mod.update(0.016)
  n = #toggles
  mod.on_disabled(); mod.on_enabled(false)
  check("sleep: DMF enabling the mod again (all hooks on) is followed by the switch-off", D.is_asleep() and #toggles == n + 1 and toggles[#toggles] == "off", table.concat(toggles, ","))
  RW.director.update, RW.effects.tick_audio = real_update, real_audio
  mod.on_unload()
  check("sleep: unload releases the module (nothing of the mod held)", RW.dormancy == nil and D.is_asleep() ~= nil)
  Managers.state, Managers.event, REALMS_STUB, mod = saved_state, saved_event, nil, saved_mod
end

-- (2026-10-11) Options > Update default cards: a held button at the very top, it rewrites the default cards and says how many
do
  local data = dofile(BASE .. "/GrandfathersTarot_data.lua")
  local top = data.options.widgets[1]
  check("update defaults: the first widget of the options is the held button 'Update default cards'", top.setting_id == "update_default_cards" and top.type == "button" and top.button_trigger == "held" and top.function_name == "update_default_cards")
  local versioned = io.open(BASE .. "/catalog/version.lua"):read("*a")
  check("version: the mod is v1.1", versioned:find('return "1.1"', 1, true) ~= nil)
  mod = {}; for _,key in ipairs(helpers) do mod[key] = prototype[key] end
  local saved_mod = mod
  hooks, views, commands, hook_requires, require_callbacks, require_by_path, hud_elements = {}, {}, {}, {}, {}, {}, {}
  dofile(BASE .. "/GrandfathersTarot.lua"); mod.on_all_mods_loaded()
  local RW = mod.rw
  local store, notes = {}, {}
  local real_get, real_set, real_notify = mod.get, mod.set, mod.notify
  mod.get = function(self, id) return store[id] end
  mod.set = function(self, id, value) store[id] = value end
  mod.notify = function(self, text) notes[#notes + 1] = text end
  -- as DMF's localize: the text is formatted inside it with the arguments given (a %d without its number fails there; seen in game
  -- 2026-10-11 on a fresh preset: "bad argument #2 to '?' (value expected)")
  local real_localize, bad_format = mod.localize, 0
  mod.localize = function(self, id, ...)
    local text = id:find("^update_default_cards_") and id .. " %d" or id
    local ok, out = pcall(string.format, text, ...)
    if not ok then bad_format = bad_format + 1; return "<" .. id .. ">" end
    return out
  end
  store.wave_def_custom_1 = "Mine\t2 hounds"
  mod.update_default_cards()
  check("update defaults: the button writes the default cards, keeps the player's own one and says so", store.wave_def_custom_1 == "Mine\t2 hounds" and type(store.gt_default_slots) == "string" and #notes == 1 and notes[1]:find("update_default_cards_done %d+") ~= nil and notes[1]:find("update_default_cards_moved 1", 1, true) ~= nil, notes[1])
  check("update defaults: its message passes every number to localize (DMF formats the text there)", bad_format == 0, bad_format)
  -- a fresh preset: no card at all (the case of the error in game)
  for k in pairs(store) do store[k] = nil end
  mod.update_default_cards()
  check("update defaults: on an empty deck every default card goes to its own slot and the message is whole", bad_format == 0 and #notes == 2 and notes[2]:find("update_default_cards_done %d+") ~= nil and notes[2]:find("moved", 1, true) == nil, notes[2])
  mod.localize = real_localize
  RW.events.update_defaults = function() error("broken") end
  local reported, real_error = 0, mod.error
  mod.error = function() reported = reported + 1 end
  local raised = not pcall(mod.update_default_cards)
  check("update defaults: a failure is reported, never raised", reported == 1 and not raised and #notes == 2)
  mod.get, mod.set, mod.notify, mod.error = real_get, real_set, real_notify, real_error
  mod.on_unload()
  mod = saved_mod
end

-- (2026-10-11, a performance pass) the busy hooks are on only while their feature has work (core/hook_gate.lua)
do
  local Gate = dofile(BASE .. "/core/hook_gate.lua")
  local log = {}
  local fake = {
    hook_enable = function(self, obj, method) log[#log + 1] = (obj.label or "?") .. "." .. method .. ":on" end,
    hook_disable = function(self, obj, method) log[#log + 1] = (obj.label or "?") .. "." .. method .. ":off" end,
  }
  local f = function() end
  local Health = { label = "Health", add_damage = f, add_heal = f }
  local Death = { label = "Death", die = f }
  local saved_class = rawget(_G, "CLASS")
  CLASS = { HealthExtension = Health }
  Gate.init({ mod = fake })
  local divided, claims = false, false
  Gate.add("health", "HealthExtension", { "add_damage", "add_heal" }, function() return divided end)
  Gate.add("die", Death, "die", function() return claims end)
  local Broken = { label = "Broken", run = f }
  Gate.add("broken", Broken, "run", function() error("boom") end)
  Gate.add("later", "NotLoadedYet", "run", function() return false end)
  Gate.add("die", Death, "die", function() return claims end) -- a hook_require callback run again at the next game start
  local function count(entry) local n = 0 for _, l in ipairs(log) do if l == entry then n = n + 1 end end return n end

  Gate.update(0.1)
  check("gate: nothing is switched before its first tick (0.25 s)", #log == 0, #log)
  Gate.update(0.2)
  check("gate: a hook with no work is NOT switched off at once (LINGER)", count("Health.add_damage:off") == 0 and count("Death.die:off") == 0, table.concat(log, ","))
  check("gate: a failing question keeps its hook on (the safe side)", count("Broken.run:on") == 1 and Gate.state().broken == true, table.concat(log, ","))
  for _ = 1, 10 do Gate.update(0.25) end
  check("gate: ...switched off after 2 s with no work, each method", count("Health.add_damage:off") == 1 and count("Health.add_heal:off") == 1, table.concat(log, ","))
  check("gate: a class not loaded yet is left alone (no toggle)", count("Later.run:off") == 0 and count("Later.run:on") == 0 and Gate.state().health == false)
  check("gate: a target added twice is held once (one toggle)", count("Death.die:off") == 1, table.concat(log, ","))
  local n = #log
  for _ = 1, 4 do Gate.update(0.25) end
  -- (a resync may fall in this second: each target once at most, never once a tick)
  local per = {}
  for i = n + 1, #log do per[log[i]] = (per[log[i]] or 0) + 1 end
  local most = 0
  for _, c in pairs(per) do most = math.max(most, c) end
  check("gate: an answer already applied is not applied again every tick", most <= 1, most)
  divided = true
  Gate.refresh("health")
  check("gate: refresh(name) switches that hook on at once (a divided unit just spawned)", log[#log] == "Health.add_heal:on" and log[#log - 1] == "Health.add_damage:on", table.concat(log, ","))
  divided = false; claims = true
  Gate.refresh()
  check("gate: refresh() asks every gate", count("Death.die:on") == 1 and Gate.state().die == true, table.concat(log, ","))
  for _ = 1, 6 do Gate.update(0.25) end
  check("gate: work again within LINGER keeps the hook on (no flicker)", Gate.state().health == true)
  divided = true; Gate.update(0.25)
  for _ = 1, 4 do Gate.update(0.25) end
  divided = false
  n = #log
  Gate.resync()
  Gate.update(0.25)
  check("gate: resync (DMF switched every hook on again) applies every answer again", #log > n, table.concat(log, ",", n + 1))
  n = #log
  for _ = 1, 14 do Gate.update(0.25) end
  check("gate: and every 3 s by itself (a hook DMF created late is put right)", #log > n)
  -- (2026-10-17, console log: "(hook_disable): trying to toggle hook that doesn't exist: _leap / _draw_health_bar") a class named
  -- before it loads has its mod:hook delayed by DMF to its first instance; the class appears in CLASS before that, so it is never
  -- switched by the gate (it stays on), whatever loads later
  CLASS.NotLoadedYet = { label = "Later", run = f }
  for _ = 1, 14 do Gate.update(0.25) end
  check("gate: a class that was not loaded when it was gated is never switched, even once it loads (DMF may not have made its hook)", count("Later.run:off") == 0 and count("Later.run:on") == 0, table.concat(log, ","))
  check("gate: ...and it does not hold its gate's answer back (the gate still settles on its answer)", Gate.state().later == false, tostring(Gate.state().later))
  -- a gate with a pending target and a live one: the live one is switched once, not at every tick
  local Live = { label = "Live", run = f }
  local infos = {}
  fake.info = function(self, fmt, ...) infos[#infos + 1] = string.format(fmt, ...) end
  Gate.add("mixed", "AlsoNotLoaded", "run", function() return false end)
  Gate.add("mixed", Live, "run", function() return false end)
  check("gate: a class gated by name before it loads is said once in the log", #infos == 1 and infos[1]:find("AlsoNotLoaded", 1, true) ~= nil, infos[1])
  CLASS.AlsoNotLoaded = { label = "AlsoLater", run = f }
  for _ = 1, 10 do Gate.update(0.25) end
  local before_live = count("Live.run:off")
  for _ = 1, 4 do Gate.update(0.25) end
  -- (a resync may fall in this second: once at most, never once a tick)
  check("gate: in a gate with a pending target, the live one is switched off and then left alone", before_live >= 1 and count("Live.run:off") - before_live <= 1 and count("AlsoLater.run:off") == 0 and count("AlsoLater.run:on") == 0, table.concat(log, ","))
  fake.info = nil
  -- a loaded class without the method (a game update renamed it): never switched, its gate's answer stays unknown
  local Renamed = { label = "Renamed", other = f }
  Gate.add("renamed", Renamed, "gone", function() return false end)
  for _ = 1, 10 do Gate.update(0.25) end
  check("gate: a loaded class without the gated method is not switched and its answer stays unknown", count("Renamed.gone:off") == 0 and Gate.state().renamed == nil)

  -- Gate.hook_file: the hooks are made on the file's own table when the game loads it, and only then gated
  local made, required = {}, {}
  fake.hook = function(self, obj, method, fn) made[#made + 1] = { obj = obj, method = method, fn = fn, safe = false } end
  fake.hook_safe = function(self, obj, method, fn) made[#made + 1] = { obj = obj, method = method, fn = fn, safe = true } end
  fake.hook_require = function(self, path, fn) required[path] = fn end
  local pounce = function() end
  local seen_ok = Gate.hook_file("pounce", "scripts/x/pounce", { { "_leap", pounce }, { "leave", pounce, safe = true } }, function() return false end)
  check("hook_file: registered through hook_require, nothing hooked or gated before the file loads", seen_ok == true and type(required["scripts/x/pounce"]) == "function" and #made == 0 and Gate.state().pounce == nil)
  local Leap = { label = "Leap", _leap = f, leave = f }
  required["scripts/x/pounce"](Leap)
  check("hook_file: on load, a normal and a safe hook are made on that very table, in order", #made == 2 and made[1].obj == Leap and made[1].method == "_leap" and not made[1].safe and made[2].obj == Leap and made[2].method == "leave" and made[2].safe)
  for _ = 1, 10 do Gate.update(0.25) end
  check("hook_file: the gate switches those hooks (they exist)", count("Leap._leap:off") >= 1 and count("Leap.leave:off") >= 1 and Gate.state().pounce == false, table.concat(log, ","))
  required["scripts/x/pounce"](Leap)
  check("hook_file: the same table loaded again (every game start) is not hooked again", #made == 2)
  local Leap2 = { label = "Leap2", _leap = f, leave = f }
  required["scripts/x/pounce"](Leap2)
  check("hook_file: a new table is hooked and gated too", #made == 4 and made[3].obj == Leap2)
  required["scripts/x/pounce"]("not a table")
  check("hook_file: a file that returns no table is ignored", #made == 4)
  fake.hook_require = nil
  check("hook_file: without hook_require it says so (the caller hooks by name)", Gate.hook_file("x", "p", { { "run", f } }, function() return true end) == false)
  fake.hook_require = function(self, path, fn) required[path] = fn end
  check("hook_file: a question that is not a function is refused", Gate.hook_file("x", "p", { { "run", f } }, nil) == false)
  Gate.hook_file("late", "scripts/x/late", { { "run", f } }, function() return false end)
  Gate.retire()
  local n_made = #made
  required["scripts/x/late"]({ run = f })
  check("hook_file: a file loaded after an unload hooks nothing", #made == n_made)
  Gate.init({ mod = fake })
  required["scripts/x/late"]({ run = f })
  check("hook_file: the callback works again only once the gate is live again for the same mod", #made == n_made + 1)
  Gate.init({ mod = { hook_enable = f, hook_disable = f } })
  required["scripts/x/late"]({ run = f })
  check("hook_file: a gate live for ANOTHER mod (a DMF reload made a new one) never runs the old callback", #made == n_made + 1)
  Gate.init({ mod = fake })
  fake.hook, fake.hook_safe, fake.hook_require = nil, nil, nil
  Gate.retire()
  n = #log
  Gate.refresh(); Gate.update(1)
  check("gate: retired (an unload) it switches nothing", #log == n and next(Gate.state()) == nil)
  local Old = { hook_enable = nil }
  Gate.init({ mod = Old }); Gate.add("x", Death, "die", function() return true end); Gate.refresh()
  check("gate: a DMF without hook_enable: nothing happens, nothing breaks", true)
  CLASS = saved_class
end

-- the gates the mod sets up at load (their names; each hook's question is the module's own)
do
  mod = {}; for _,key in ipairs(helpers) do mod[key] = prototype[key] end
  local saved_mod = mod
  hooks, views, commands, hook_requires, require_callbacks, require_by_path, hud_elements = {}, {}, {}, {}, {}, {}, {}
  dofile(BASE .. "/GrandfathersTarot.lua"); mod.on_all_mods_loaded()
  local RW = mod.rw
  -- the classes that load after the mod are gated when the game loads their files (2026-10-17)
  local f = function() end
  local loaded = {}
  for _, paths in pairs(GATED_FILES) do
    for _, path in ipairs(paths) do
      local class = { _remove_mood = f, _draw_health_bar = f, _update_charging = f, _update_charged_past = f, _update_grabbed_target = f, add_damage = f, add_heal = f, set_health_instant = f, _start_attack_anim = f, run = f, _leap = f }
      loaded[#loaded + 1] = class
      require_by_path[path](class)
    end
  end
  local by_name_before_load = 0
  for _, h in ipairs(hooks) do if h.obj == "PlayerUnitMoodExtension" or h.obj == "HudElementPersonalPlayerPanel" or h.obj == "HealthExtension" or h.obj == "BtChaosHoundLeapAction" and h.method == "_leap" then by_name_before_load = by_name_before_load + 1 end end
  check("gate: no gated hook on a late class is made by its name any more", by_name_before_load == 0)
  local names = RW.hook_gate and RW.hook_gate.names() or {}
  local have = {}
  for _, name in ipairs(names) do have[name] = true end
  local missing = {}
  for _, name in ipairs({ "bypass", "dread", "golden", "health_writes", "melee_attack", "spray", "net", "leap", "charge" }) do
    if not have[name] then missing[#missing + 1] = name end
  end
  check("gate: the main file loads the gate first and every busy hook is registered with it", #missing == 0, table.concat(missing, ","))
  mod.on_unload()
  mod = saved_mod
end

-- (2026-10-17, console log) the game destroys the EventManager before the mods unload when it shuts down: reading a method of the
-- destroyed object raises, and the unload must not ("on_unload: Cannot access property "unregister" on destroyed object")
do
  mod = {}; for _,key in ipairs(helpers) do mod[key] = prototype[key] end
  local saved_mod = mod
  hooks, views, commands, hook_requires, require_callbacks, require_by_path, hud_elements = {}, {}, {}, {}, {}, {}, {}
  Managers.event = event_manager()
  dofile(BASE .. "/GrandfathersTarot.lua"); mod.on_all_mods_loaded()
  local RW = mod.rw
  local destroyed = setmetatable({}, { __index = function(_, key) error('Cannot access property "' .. tostring(key) .. '" on destroyed object of type EventManager') end })
  RW.event_manager = destroyed
  Managers.event = destroyed
  local ok, err = pcall(mod.on_unload)
  check("unload: a destroyed EventManager (the game shutting down) does not make the unload fail", ok, err)
  check("unload: ...and the dead manager is let go", RW.event_manager == nil)
  local half = event_manager()
  half.unregister = function(self, owner, name) if name == "event_mission_objective_start" then error("broken") end self._events[name] = nil end
  half._events.event_player_died = true
  RW.event_manager = half
  pcall(mod.on_unload)
  check("unload: one subscription that cannot be removed does not keep the other", half._events.event_player_died == nil)
  Managers.event = event_manager()
  mod = saved_mod
end

return table.concat(results, "\n")
'''
out = lua.execute(harness, MODROOT)
print(out)
fails = [l for l in out.split("\n") if l.startswith("FAIL")]
print("\nPASS:", len([l for l in out.split("\n") if l.startswith("PASS")]), "FAIL:", len(fails))
sys.exit(1 if fails else 0)
