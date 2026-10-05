"""Loads the real entry script (RealmsWaves.lua) against stubbed DMF/engine pieces and checks what it
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
local BASE = MODROOT .. "/scripts/mods/RealmsWaves"

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
mod.io_dofile = function(self, path) return dofile(MODROOT .. "/" .. path:gsub("^RealmsWaves/", "") .. ".lua") end
get_mod = function(name)
  if name == "DMF" then return dmf_mod end
  if name == "Realms" then return nil end
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

dofile(BASE .. "/RealmsWaves.lua")
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
check("entry: rw_stop, rw_pause and rw_next are registered", type(commands.rw_stop) == "function" and type(commands.rw_pause) == "function" and type(commands.rw_next) == "function")
local echoed = {}
mod.echo = function(self, fmt, ...) echoed[#echoed + 1] = string.format(fmt, ...) end
commands.rw_stop(); commands.rw_pause("on"); commands.rw_next()
check("entry: the commands answer in chat (a client or a stopped host gets a reason, never an error)", #echoed == 3 and echoed[1]:find("RealmsWaves") ~= nil, table.concat(echoed, " | "))

-- the animation probe: registered, and in a game without any wave unit (or without the engine's Unit table) it only says so
echoed = {}
check("entry: /rw_anim and /rw_tune are registered", type(commands.rw_anim) == "function" and type(commands.rw_tune) == "function")
echoed = {}
local tune_ok = pcall(commands.rw_tune)
check("entry: /rw_tune with nothing tuned answers instead of failing", tune_ok and #echoed == 1 and echoed[1]:find("No living unit", 1, true) ~= nil, table.concat(echoed, " | "))
echoed = {}
local anim_ok, anim_err = pcall(commands.rw_anim)
check("entry: /rw_anim without the engine table (this harness has none) answers instead of failing", anim_ok and #echoed == 2 and echoed[1]:find("Unit functions about animation", 1, true) ~= nil and echoed[2]:find("cannot be looked at", 1, true) ~= nil, anim_ok and table.concat(echoed, " | ") or anim_err)

-- Console/keybind adapters: validate user inputs and forward the intended state.
do
  local saved_ui=Managers.ui
  Managers.ui=nil;mod.open_editor()
  local opened,closed=0,0
  Managers.ui={view_instance=function() return opened>closed and {} or nil end,
    open_view=function(_,name) if name=="realms_waves_editor" then opened=opened+1 end end,
    close_view=function(_,name) if name=="realms_waves_editor" then closed=closed+1 end end}
  commands.rw_editor();commands.rw_editor()
  check("editor command: opens then closes the registered view, absent UI is safe", opened==1 and closed==1)
  Managers.ui=saved_ui
  local original_vote=RW.director.local_vote
  local options={}
  RW.director.local_vote=function(option) options[#options+1]=option;return false,"no ballot" end
  for i=1,5 do mod["vote_"..i]() end
  commands.rw_vote("3");commands.rw_vote("invalid")
  check("vote inputs: all five keys and console number forward the selected option", table.concat(options,",")=="1,2,3,4,5,3,0")
  RW.director.local_vote=original_vote
  local original_pause=RW.director.pause
  local arguments={}
  RW.director.pause=function(value) arguments[#arguments+1]=tostring(value);return value,"client" end
  commands.rw_pause("on");commands.rw_pause("off");commands.rw_pause();commands.rw_pause("toggle")
  check("pause command: on/off forward booleans, omitted/unknown arguments toggle", table.concat(arguments,",")=="true,false,nil,nil")
  RW.director.pause=original_pause
  local original_start=RW.director.force_start
  RW.director.force_start=function() return true end;echoed={};commands.rw_start()
  check("start command: successful host start is reported", echoed[1]:find("cycle started",1,true)~=nil)
  RW.director.force_start=function() return false end;echoed={};commands.rw_start()
  check("start command: rejected client start explains the authority requirement", echoed[1]:find("host in a mission only",1,true)~=nil)
  RW.director.force_start=original_start
  local original_next=RW.director.next_wave
  RW.director.next_wave=function() return true end;echoed={};commands.rw_next()
  check("next command: successful redraw is reported", echoed[1]:find("new wave drawn",1,true)~=nil)
  RW.director.next_wave=original_next
  echoed={};commands.rw_test()
  check("test command: empty input lists usage and existing waves", #echoed==1 and echoed[1]:find("hound_frenzy",1,true)~=nil)
  local original_fire=RW.director.fire_now
  local query
  RW.director.fire_now=function(text) query=text;return true,"queued note" end
  echoed={};commands.rw_test("Mutants","Everywhere")
  check("test command: joins multiword names and reports successful queueing", query=="Mutants Everywhere" and echoed[1]:find("queued note",1,true)~=nil)
  RW.director.fire_now=function() return false,"host only" end;echoed={};commands.rw_test("hound_frenzy")
  check("test command: rejected wave reports the director reason", echoed[1]:find("host only",1,true)~=nil)
  RW.director.fire_now=original_fire
  -- the deck holds 100 cards: 88 custom slots (it was 20, so 21 used to be the first invalid one)
  for _,slot in ipairs({"x","0",tostring(RW.events.CUSTOM_SLOTS+1),"1.5"}) do
    local before=stored.wave_def_custom_3;echoed={};commands.rw_custom(slot,"1 hound")
    check("custom command: invalid slot "..slot.." makes no settings writes", stored.wave_def_custom_3==before and echoed[1]:find("slot must be",1,true)~=nil)
  end
  do
    local top=tostring(RW.events.CUSTOM_SLOTS);echoed={};commands.rw_custom(top,"2","hounds")
    check("custom command: the last slot ("..top..") is valid and the message of a wrong slot names the range", RW.events.CUSTOM_SLOTS==88 and stored["wave_def_custom_"..top]~=nil and stored["on_custom_"..top]==true)
    stored["wave_def_custom_"..top],stored["on_custom_"..top]=nil,nil
    echoed={};commands.rw_custom("0","1 hound")
    check("custom command: ...which is 1-88", echoed[1]:find("1-88",1,true)~=nil, echoed[1])
  end
  local old_def,old_on=stored.wave_def_custom_3,stored.on_custom_3
  commands.rw_custom("3","2","hounds")
  local wave=RW.events.get("custom_3",function(id) return stored[id] end,RW.groups)
  check("custom command: valid recipe persists normalized enemies and enables the slot", wave.parts[1].breed=="chaos_hound" and wave.parts[1].count==2 and stored.on_custom_3==true)
  local saved_def=stored.wave_def_custom_3;echoed={};commands.rw_custom("3","2 unicorns")
  check("custom command: invalid breed leaves the previous recipe intact", stored.wave_def_custom_3==saved_def and #echoed==1)
  echoed={};commands.rw_custom("3")
  check("custom command: absent recipe reports the current slot without mutation", stored.wave_def_custom_3==saved_def and echoed[1]:find("custom_3",1,true)~=nil)
  stored.wave_def_custom_3,stored.on_custom_3=old_def,old_on
  local original_simulate=RW.director.simulate
  local iterations
  RW.director.simulate=function(n) iterations=n;return {},{},0 end
  for _,case in ipairs({{"0",1},{"100001",100000},{"invalid",1000}}) do
    echoed={};commands.rw_roll(case[1])
    check("roll command: "..case[1].." clamps/defaults the workload", iterations==case[2] and echoed[1]:find("no event enabled",1,true)~=nil)
  end
  RW.director.simulate=original_simulate
  local original_probe,original_describe=RW.tuning.probe,RW.tuning.describe
  RW.tuning.probe=function() error("probe failed") end
  RW.tuning.describe=function() error("stats failed") end
  echoed={};commands.rw_anim();commands.rw_tune()
  check("diagnostic commands: native probe errors return chat diagnostics", #echoed==2 and echoed[1]:find("probe failed",1,true)~=nil and echoed[2]:find("stats failed",1,true)~=nil)
  local info_count=0;mod.info=function() info_count=info_count+1 end
  RW.tuning.probe=function() return {"animation"} end
  RW.tuning.describe=function() return {"stats"} end
  commands.rw_anim();commands.rw_tune()
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
check("entry: the four budget-bypass hooks and the custom-mods hooks (stat recompute on both buff classes, melee attack start, burster explosion, the summoners: no summon while destroyed, no patrol, aggroed summons; the On Fire burn per player) are installed", table.concat(names, ",") == "BtChaosPoxwalkerExplodeAction.enter,BtMeleeAttackAction._start_attack_anim,BtSummonMinionsAction._patrol_setup,BtSummonMinionsAction._summon_minions,BtSummonMinionsAction.leave,BuffExtensionBase._update_stat_buffs_and_keywords,MinionBuffExtension._reset_stat_buffs,MinionBuffExtension._update_stat_buffs_and_keywords,MinionSpawnManager.num_spawned_minions,MinionSpawnManager.total_allocated_num_enemies,MinionSpawnManager.unregister_unit,PacingManager.add_aggroed_minion,PlayerUnitBuffExtension.add_internally_controlled_buff,PlayerUnitMoodExtension._remove_mood", table.concat(names, ","))
check("entry: MinionAttack is hooked through hook_require (it may load after the mod)", #hook_requires == 3 and (function() local seen = {} for _, p in ipairs(hook_requires) do seen[p] = true end return seen["scripts/utilities/minion_attack"] and seen["scripts/extension_systems/buff/minion_buff_extension"] and seen["scripts/settings/buff/buff_templates"] end)(), table.concat(hook_requires, ","))
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
  T.apply(enemy, { burn = 50 }, "renegade_flamer")
  check("on fire: the group's setting is kept for its enemies (50 percent)", T.fire_share(enemy) == 0.5)
  templates.common_minion_on_fire.interval_func({}, { unit = enemy })
  templates.hit_by_common_enemy_flame.interval_func({}, { unit = scaled_player, is_server = true })
  check("on fire: a player that enemy set on fire burns at half the power level", T.burn_share(scaled_player) == 0.5 and #hits == 1 and hits[1][1] == scaled_player and hits[1][2] == 200 and game_burns == 1)
  T.apply(enemy, { burn = 0 }, "renegade_flamer")
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
  HEALTH_ALIVE = saved.HEALTH_ALIVE
  Managers.state.difficulty = saved.difficulty
  T.dead = was_dead
end
check("entry: editor view registered under its name with the right class", #views == 1 and views[1].view_name == "realms_waves_editor" and views[1].view_settings.class == "RealmsWavesView")
check("entry: /rw_test_close is registered too", type(commands.rw_test_close) == "function")
check("entry: /rw_drawtest and /rw_fulltest are registered (a staged draw to test the HUD, with or without the sound and the wave)", type(commands.rw_drawtest) == "function" and type(commands.rw_fulltest) == "function")
do
  local before = #echoed
  commands.rw_drawtest(); commands.rw_fulltest("  ")
  local usage = echoed[before + 1] and echoed[before + 2] and echoed[before + 1]:find("usage /rw_drawtest", 1, true) and echoed[before + 2]:find("usage /rw_fulltest", 1, true)
  commands.rw_drawtest("The", "Fool")
  check("entry: /rw_drawtest and /rw_fulltest say how to use them without a name, and pass a name on (refused here: no running cycle)", usage ~= nil and #echoed == before + 3 and echoed[#echoed]:find("RealmsWaves:", 1, true) ~= nil, echoed[#echoed])
end
check("entry: three HUD elements are registered, the Spread, the Nightmare's dread (full screen, not HUD-scaled) and the window of the last card (own node, so custom_hud moves it on its own)", #hud_elements == 3 and hud_elements[1].class_name == "HudElementRealmsWavesPanel" and hud_elements[2].class_name == "HudElementRealmsWavesDread" and hud_elements[2].use_hud_scale == false and hud_elements[3].class_name == "HudElementRealmsWavesLast" and hud_elements[3].filename:find("hud_element_last_card$") ~= nil and hud_elements[3].use_hud_scale == true, #hud_elements)
check("entry: commands registered (rw_test, rw_editor, rw_status, rw_custom, rw_roll, rw_start, rw_skip, rw_vote)", commands.rw_test and commands.rw_editor and commands.rw_status and commands.rw_custom and commands.rw_roll and commands.rw_start and commands.rw_skip and commands.rw_vote ~= nil)
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
  dofile(BASE .. "/RealmsWaves.lua"); mod.on_all_mods_loaded()
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
local missing_ok = pcall(function() dofile(BASE .. "/RealmsWaves.lua"); mod.on_all_mods_loaded();mod.on_unload() end)
check("reload: missing event manager is safe at initialization and unload", missing_ok)
dofile(BASE .. "/RealmsWaves.lua");mod.on_all_mods_loaded()
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
    local stats={melee_attack_speed=1};local unit={id=#spawned+1,buffs={stat_buffs=function() return stats end},stats=stats}
    spawned[#spawned+1]=unit;return unit
  end},
}
dofile(BASE .. "/RealmsWaves.lua");mod.on_all_mods_loaded()
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
for _,h in ipairs(hooks) do if h.obj=="MinionBuffExtension" and h.method=="_reset_stat_buffs" then h.fn(living.buffs) end end
for _,h in ipairs(hooks) do if h.obj=="MinionBuffExtension" and h.method=="_update_stat_buffs_and_keywords" then h.fn(living.buffs) end end
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
dofile(BASE .. "/RealmsWaves.lua");mod.on_all_mods_loaded();RW=mod.rw
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

return table.concat(results, "\n")
'''
out = lua.execute(harness, MODROOT)
print(out)
fails = [l for l in out.split("\n") if l.startswith("FAIL")]
print("\nPASS:", len([l for l in out.split("\n") if l.startswith("PASS")]), "FAIL:", len(fails))
sys.exit(1 if fails else 0)
