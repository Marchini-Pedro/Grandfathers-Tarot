"""Loads the real entry script (RealmsWaves.lua) against stubbed DMF/engine pieces and checks what it
installs at load: the DMF keybind-suppression hook, the bypass hooks, the unload behaviour.
Run:  python tools/entry_test.py   (needs `lupa`, see CLAUDE.md)
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
local require_callbacks = {}
mod.hook_require = function(self, path, fn) hook_requires[#hook_requires + 1] = path;require_callbacks[#require_callbacks+1]=fn end
mod.register_hud_element = function() end
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
check("entry: the four budget-bypass hooks and the custom-mods hooks (stat recompute on both buff classes, melee attack start, burster explosion) are installed", table.concat(names, ",") == "BtChaosPoxwalkerExplodeAction.enter,BtMeleeAttackAction._start_attack_anim,BuffExtensionBase._update_stat_buffs_and_keywords,MinionBuffExtension._reset_stat_buffs,MinionBuffExtension._update_stat_buffs_and_keywords,MinionSpawnManager.num_spawned_minions,MinionSpawnManager.total_allocated_num_enemies,MinionSpawnManager.unregister_unit,PacingManager.add_aggroed_minion", table.concat(names, ","))
check("entry: MinionAttack is hooked through hook_require (it may load after the mod)", #hook_requires == 1 and hook_requires[1] == "scripts/utilities/minion_attack", table.concat(hook_requires, ","))
check("entry: editor view registered under its name with the right class", #views == 1 and views[1].view_name == "realms_waves_editor" and views[1].view_settings.class == "RealmsWavesView")
check("entry: /rw_test_close is registered too", type(commands.rw_test_close) == "function")
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
  hooks, views, commands, hook_requires, require_callbacks = {}, {}, {}, {}, {}
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
hooks, views, commands, hook_requires, require_callbacks = {}, {}, {}, {}, {}
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
