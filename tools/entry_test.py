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
mod.hook_require = function(self, path, fn) hook_requires[#hook_requires + 1] = path end
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
check("entry: the four budget-bypass hooks and the custom-mods hooks (stat recompute on both buff classes, melee attack start, burster explosion) are installed", table.concat(names, ",") == "BtChaosPoxwalkerExplodeAction.enter,BtMeleeAttackAction._start_attack_anim,BuffExtensionBase._update_stat_buffs_and_keywords,HudElementBossHealth.event_boss_encounter_start,MinionBuffExtension._reset_stat_buffs,MinionBuffExtension._update_stat_buffs_and_keywords,MinionSpawnManager.num_spawned_minions,MinionSpawnManager.total_allocated_num_enemies,MinionSpawnManager.unregister_unit,PacingManager.add_aggroed_minion", table.concat(names, ","))
check("entry: MinionAttack is hooked through hook_require (it may load after the mod)", #hook_requires == 1 and hook_requires[1] == "scripts/utilities/minion_attack", table.concat(hook_requires, ","))
check("entry: editor view registered under its name with the right class", #views == 1 and views[1].view_name == "realms_waves_editor" and views[1].view_settings.class == "RealmsWavesView")
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
  hooks, views, commands, hook_requires = {}, {}, {}, {}
end
mod = nil
collectgarbage("collect"); collectgarbage("collect")
check("reload: 100 generations release strong event keys and obsolete weak mod references", next(weak) == nil and next(manager._events.event_mission_objective_start) == nil and next(manager._events.event_player_died) == nil)
mod = {}; for _,key in ipairs(helpers) do mod[key] = prototype[key] end
Managers.event = nil
local missing_ok = pcall(function() dofile(BASE .. "/RealmsWaves.lua"); mod.on_all_mods_loaded(); mod.on_unload() end)
check("reload: missing event manager is safe at initialization and unload", missing_ok)
if tracing then jit.on() end

return table.concat(results, "\n")
'''
out = lua.execute(harness, MODROOT)
print(out)
fails = [l for l in out.split("\n") if l.startswith("FAIL")]
print("\nPASS:", len([l for l in out.split("\n") if l.startswith("PASS")]), "FAIL:", len(fails))
sys.exit(1 if fails else 0)
