import sys, os
sys.path.insert(0, os.environ.get("PYLIBS", r"C:\Users\ayko4\AppData\Local\Temp\claude\c--XboxGames-Warhammer-40-000--Darktide-Content\9da40c72-f459-4d9d-ab4b-3023fa21e2f5\scratchpad\pylibs"))
from lupa import LuaRuntime

ROOT = r"C:\XboxGames\Warhammer 40,000- Darktide\Content\mods\RealmsWaves\scripts\mods\RealmsWaves"
lua = LuaRuntime(unpack_returned_tuples=True)

harness = r'''
local ROOT = ...
math.randomseed(12345)

-- ---- stubs ---------------------------------------------------------------
local settings = {}
local echoes = {}
local mod = {}
mod.get = function(self, id) return settings[id] end
mod.set = function(self, id, v) settings[id] = v end
mod.echo = function(self, fmt, ...) echoes[#echoes+1] = string.format(fmt, ...) end
mod.warning = function(self, fmt, ...) echoes[#echoes+1] = "WARN " .. string.format(fmt, ...) end
mod.error = mod.warning
mod.localize = function(self, id, ...) if select("#", ...) > 0 then return id .. ":" .. table.concat({...}, ",") end return id end
mod.io_dofile = function(self, path) return dofile(ROOT .. "/../../../" .. path .. ".lua") end
get_mod = function(name) return mod end

local is_server = true
local mission_name = "coop_complete_objective"
Managers = {
  state = {
    game_session = { is_server = function() return is_server end },
    game_mode = { game_mode = function() return { name = function() return mission_name end } end },
    main_path = { is_main_path_ready = function() return true end },
  },
  time = nil,
}

local function load(rel) return dofile(ROOT .. "/" .. rel .. ".lua") end

local Groups = load("catalog/groups")
local Events = load("catalog/events")
local Votes = load("core/votes")

local results = {}
local function check(name, cond, detail)
  results[#results+1] = (cond and "PASS " or "FAIL ") .. name .. (detail and (" -- " .. tostring(detail)) or "")
end

-- ---- groups.parse --------------------------------------------------------
local parts, err = Groups.parse("5 trappers, 5 mutants, 10 hounds")
check("parse basic", parts and #parts == 3 and parts[1].breed == "renegade_netgunner" and parts[1].count == 5 and parts[3].count == 10, err)
parts = Groups.parse("hound x3 and 2 snipers; 4 scab")
check("parse varied", parts and #parts == 3, parts and #parts)
local p2, e2 = Groups.parse("5 unicorns")
check("parse unknown", p2 == nil and e2 ~= nil, e2)
local p3 = Groups.parse("100 poxwalkers")
check("parse cap 60/breed", p3 and p3[1].count == Groups.MAX_BREED_COUNT, p3 and p3[1].count)
local p4 = Groups.parse("60 hounds, 60 poxwalkers, 60 scabs")
local tot = 0; for i = 1, #p4 do tot = tot + p4[i].count end
check("parse cap 120 total", tot == Groups.MAX_TOTAL, tot)
local p5, e5 = Groups.parse("")
check("parse empty", p5 == nil and e5 ~= nil)
local p6 = Groups.parse("1 plague ogryn|chaos spawn|beast of nurgle, 4 hounds")
check("parse one_of", p6 and #p6 == 2 and p6[1].one_of and #p6[1].one_of == 3 and p6[1].count == 1 and p6[2].breed == "chaos_hound")
local rt = Groups.parse(Groups.to_recipe(p6))
check("recipe roundtrip", rt and #rt == 2 and rt[1].one_of and rt[1].one_of[2] == "chaos_spawn" and rt[2].count == 4, Groups.to_recipe(p6))
check("describe/summary", Groups.summary(p6):find("random of") ~= nil and Groups.display_name("renegade_netgunner") == "Trapper", Groups.summary(p6))
check("breed list sorted & known", #Groups.breed_list() >= 38 and Groups.is_known("chaos_hound"))
-- every breed in every standard wave must be a known breed
local unknown = {}
for i = 1, #Events.STANDARD do
  for _, part in ipairs(Events.STANDARD[i].parts) do
    local names = part.one_of or { part.breed }
    for _, b in ipairs(names) do if not Groups.is_known(b) then unknown[#unknown+1] = b end end
  end
end
check("standard waves use known breeds", #unknown == 0, table.concat(unknown, ","))

-- ---- events.build_pool ---------------------------------------------------
local pool, total = Events.build_pool(function(id) return settings[id] end, Groups)
local sum = 0; for i = 1, #pool do sum = sum + pool[i].pct end
check("default pool 12 events", #pool == 12, #pool)
check("default raw total 100", math.abs(total - 100) < 1e-9, total)
check("pct sums to 100", math.abs(sum - 100) < 1e-6, sum)

local get = function(id) return settings[id] end
local set = function(id, v) settings[id] = v end

-- a custom slot is empty and disabled by default
local w3 = Events.get("custom_3", get, Groups)
check("custom slot default empty/disabled", w3 and w3.is_custom and w3.parts == nil and w3.enabled == false and w3.name == "Custom 3", w3 and w3.name)
check("unknown key -> nil", Events.get("nope", get, Groups) == nil and Events.get("custom_99", get, Groups) == nil)

-- fill it through the same API the editor uses
Events.set_def(set, "custom_3", "  Dog\tpack  ", Groups.parse("4 hounds, 2 mutants"), Groups)
set("on_custom_3", true)
w3 = Events.get("custom_3", get, Groups)
check("custom set_def: name cleaned, parts saved", w3.name == "Dog pack" and #w3.parts == 2 and w3.parts[1].count == 4 and w3.modified, w3.name)

settings["pct_wave_small"] = 0
settings["pct_wave_medium"] = 50
settings["pct_custom_3"] = 25
pool, total = Events.build_pool(get, Groups)
sum = 0; local has_custom = false
for i = 1, #pool do sum = sum + pool[i].pct; if pool[i].key == "custom_3" then has_custom = true end end
check("custom included, small excluded", has_custom and #pool == 12 and pool[#pool].name == "Dog pack", #pool)
check("renormalised to 100", math.abs(sum - 100) < 1e-6, sum)

-- overriding a standard wave keeps it standard; reset restores it
local before = Events.get("wave_small", get, Groups)
Events.set_def(set, "wave_small", "Tiny Rush", Groups.parse("3 poxwalkers"), Groups)
local after = Events.get("wave_small", get, Groups)
check("standard override", after.name == "Tiny Rush" and #after.parts == 1 and after.modified and not after.is_custom and before.name == "Small Wave")
Events.reset(set, "wave_small")
after = Events.get("wave_small", get, Groups)
check("standard reset", after.name == "Small Wave" and #after.parts == 4 and not after.modified and after.enabled and after.pct == 18, after.name)

-- disabling, cooldown override, empty custom
set("on_wave_large", false); set("cd_wave_large", 5)
local wl = Events.get("wave_large", get, Groups)
check("enabled flag and cooldown override", wl.enabled == false and wl.cooldown == 5)
local pool_no_large = Events.build_pool(get, Groups)
local has_large = false; for i = 1, #pool_no_large do if pool_no_large[i].key == "wave_large" then has_large = true end end
check("disabled wave not in pool", not has_large)
Events.reset(set, "custom_3")
check("custom reset -> empty & disabled", Events.get("custom_3", get, Groups).parts == nil and Events.get("custom_3", get, Groups).enabled == false)

-- legacy 1.0.0 recipe setting still read
settings["custom_4_recipe"] = "2 snipers"
check("legacy custom recipe", Events.get("custom_4", get, Groups).parts ~= nil)
for _, k in ipairs({ "pct_wave_small", "pct_wave_medium", "pct_custom_3", "on_wave_large", "cd_wave_large", "custom_4_recipe" }) do settings[k] = nil end
for _, k in ipairs({ "wave_def_wave_small", "wave_def_custom_3", "on_wave_small", "pct_wave_small", "cd_wave_small", "on_custom_3", "cd_custom_3", "pct_custom_3" }) do settings[k] = nil end

-- ---- votes ---------------------------------------------------------------
Votes.open(7, 3)
check("vote ok", Votes.cast(7, "a", 2) and Votes.cast(7, "b", 2) and Votes.cast(7, "c", 1))
check("vote wrong ballot rejected", not Votes.cast(6, "d", 1))
check("vote bad option rejected", not Votes.cast(7, "d", 4) and not Votes.cast(7, "d", 0))
check("vote winner", Votes.winner() == 2)
Votes.cast(7, "b", 3) -- change vote
local c = Votes.counts()
check("vote change", c[2] == 1 and c[3] == 1 and c[1] == 1)
Votes.open(8, 2)
check("no votes -> nil", Votes.winner() == nil)

-- ---- director ------------------------------------------------------------
local started_waves = {}
local Positions = { player_units = function() return { "p1" } end }
local Execute = {
  has_authority = function() return true end,
  start_wave = function(def) started_waves[#started_waves+1] = def.name; return true end,
  update = function() end, reset = function() end,
  status = function() return { tracked = 0, queued = 0, jobs = 0 } end,
}
local sent = {}
local Protocol = {
  PROTO = 1, VERSION = "1.0.0",
  is_available = function() return true end,
  send_state = function(state, rcpt) sent[#sent+1] = { state = state, rcpt = rcpt } return true end,
  send_hello = function() sent.hello = (sent.hello or 0) + 1 end,
  send_welcome = function(peer, ok) sent.welcome = { peer, ok } end,
  send_vote = function(b, o) sent.vote = { b, o } end,
}
local Director = load("core/director")
Director.init({ events = Events, groups = Groups, protocol = Protocol, execute = Execute, votes = Votes, positions = Positions })

-- random mode
settings.mode = "random"; settings.interval_min = 100; settings.interval_max = 100; settings.initial_delay = 0; settings.vote_duration = 25
Director.on_enter_gameplay()
Director.on_mission_started()
Director.update(0.1)
local v = Director.view()
check("random: waiting with 1 pending", v.phase == "waiting" and #v.cands == 1 and v.mode == "random", v.phase)
check("random: broadcast sent to others", #sent >= 1 and sent[#sent].rcpt == "others" and sent[#sent].state.p == "waiting")
Director.update(50); Director.update(50.5)
v = Director.view()
check("random: incoming after countdown", v.phase == "incoming" and #started_waves == 1, v.phase)
Director.update(6.5)
v = Director.view()
check("random: new cycle after incoming", v.phase == "waiting", v.phase)

-- vote mode
settings.mode = "vote"; settings.ballot_size = 3
Director.on_exit_gameplay(); started_waves = {}
Director.on_enter_gameplay(); Director.on_mission_started(); Director.update(0.1)
v = Director.view()
check("vote: 3 candidates shown while waiting", v.phase == "waiting" and #v.cands == 3, #v.cands)
local distinct = {}; for i = 1, #v.cands do distinct[v.cands[i].key] = true end
local n = 0; for _ in pairs(distinct) do n = n + 1 end
check("vote: candidates distinct", n == 3, n)
local want = v.cands[2].name
Director.update(70)  -- 100 - 25 = 75 -> should be in voting phase at <=25 left
Director.update(6)
v = Director.view()
check("vote: voting phase in final window", v.phase == "voting", v.phase)
check("vote: local vote accepted", Director.local_vote(2) == true)
Director.on_vote("peer_x", v.ballot_id, 2)
Director.on_vote("peer_y", v.ballot_id, 1)
v = Director.view()
check("vote: counts", v.cands[2].votes == 2 and v.cands[1].votes == 1, v.cands[2].votes)
check("vote: my_vote highlight", v.my_vote == 2)
Director.update(25)
v = Director.view()
check("vote: winner fired", v.phase == "incoming" and #started_waves == 1, started_waves[1])
check("vote: fired wave is the 2-vote option", started_waves[1] == want, tostring(started_waves[1]) .. " vs " .. tostring(want))
-- no-vote fallback skip
settings.novote_fallback = "skip"
Director.update(7)  -- back to waiting
Director.update(80); Director.update(30)
v = Director.view()
check("vote: nobody voted + skip -> no wave", v.phase == "incoming" and #started_waves == 1, #started_waves)
settings.novote_fallback = "random"

-- short intervals: 5 s countdown, vote window capped by the interval
settings.mode = "vote"; settings.interval_min = 5; settings.interval_max = 5; settings.initial_delay = 0; settings.vote_duration = 25
Director.on_exit_gameplay(); started_waves = {}
Director.on_enter_gameplay(); Director.on_mission_started(); Director.update(0.1)
v = Director.view()
check("5s interval: countdown ~5s, already in voting phase", v.remaining > 4 and v.remaining <= 5.01 and (v.phase == "voting"), v.phase .. " " .. tostring(v.remaining))
Director.update(6)
v = Director.view()
check("5s interval: resolves and fires", v.phase == "incoming" and #started_waves == 1, v.phase)
settings.interval_min = 100; settings.interval_max = 100

-- client side
is_server = false
Director.on_exit_gameplay(); Director.on_enter_gameplay()
check("client: hello sent on enter", (sent.hello or 0) >= 1)
Director.on_state("host_peer", { p = "voting", m = "vote", r = 12.0, b = 5, c = "", k = { { k = "a", n = "Alpha", p = 40.0, v = 1 }, { k = "b", n = "Beta", p = 60.0, v = 0 } }, e = 0 })
v = Director.view()
check("client: renders synced state", v.phase == "voting" and #v.cands == 2 and v.cands[1].name == "Alpha", v.phase)
check("client: local vote sends rpc", Director.local_vote(2) == true and sent.vote and sent.vote[1] == 5 and sent.vote[2] == 2)
Director.on_welcome("host_peer", 1, "9.9.9", false)
v = Director.view()
check("client: version mismatch disables", v.phase == "off", v.phase)
is_server = true

-- hub: nothing runs
mission_name = "hub"
Director.on_exit_gameplay(); started_waves = {}
Director.on_enter_gameplay(); Director.on_mission_started(); Director.update(1); Director.update(500)
check("hub: no cycle, view off", Director.view().phase == "off" and #started_waves == 0, Director.view().phase)
mission_name = "coop_complete_objective"

-- budget bypass hooks -------------------------------------------------------
local hooks = {}
mod.hook = function(self, cls, method, fn) hooks[cls .. "." .. method] = fn end
mod.hook_safe = function(self, cls, method, fn) hooks[cls .. "." .. method .. "!"] = fn end
local events = {}
Managers.event = { trigger = function(self, name, unit) events[#events+1] = name .. ":" .. tostring(unit) end }
ALIVE = {}
local Bypass = load("spawn/budget_bypass")
Bypass.install()
local pacing_calls = {}
local orig_add = function(self, unit) pacing_calls[#pacing_calls+1] = unit end
local add_hook = hooks["PacingManager.add_aggroed_minion"]
local pacing_self = { _should_send_aggro_event = true }

add_hook(orig_add, pacing_self, "vanilla_unit")
check("bypass: untracked unit reaches vanilla add_aggroed_minion", #pacing_calls == 1 and #events == 0)

Bypass.begin_spawn(); add_hook(orig_add, pacing_self, "wave_1"); Bypass.end_spawn("wave_1")
check("bypass: wave unit skips pacing counters", #pacing_calls == 1, #pacing_calls)
check("bypass: wave unit still fires minion_aggroed (stimmed minions)", events[1] == "minion_aggroed:wave_1", events[1])
add_hook(orig_add, pacing_self, "wave_1")
check("bypass: later aggro of tracked unit also fires event, not counters", #pacing_calls == 1 and #events == 2)
add_hook(orig_add, { _should_send_aggro_event = false }, "wave_1")
check("bypass: no event when pacing does not send it", #events == 2)

Bypass.track("wave_2")
local num = hooks["MinionSpawnManager.num_spawned_minions"](function() return 10 end, {})
local alloc = hooks["MinionSpawnManager.total_allocated_num_enemies"](function() return 12 end, {})
check("bypass: counters subtract tracked units", Bypass.count() == 2 and num == 8 and alloc == 10, tostring(num) .. "/" .. tostring(alloc))
check("bypass: counters never negative", hooks["MinionSpawnManager.num_spawned_minions"](function() return 1 end, {}) == 0)
hooks["MinionSpawnManager.unregister_unit!"]({}, "wave_1")
check("bypass: unregister_unit untracks", Bypass.count() == 1 and not Bypass.is_tracked("wave_1"))
Bypass.reset()
check("bypass: reset clears", Bypass.count() == 0)

-- simulate weights
Director.on_exit_gameplay()
local pool2, counts, tot2 = Director.simulate(20000)
local maxerr = 0
for i = 1, #pool2 do
  local got = counts[pool2[i].key] / 20000 * 100
  maxerr = math.max(maxerr, math.abs(got - pool2[i].pct))
end
check("simulate 20000 rolls within 1.2 pct points", maxerr < 1.2, string.format("max err %.2f", maxerr))

return table.concat(results, "\n") .. "\n--- echoes ---\n" .. table.concat(echoes, "\n")
'''
out = lua.execute(harness, ROOT.replace("\\", "/"))
print(out)
fails = [l for l in out.split("\n") if l.startswith("FAIL")]
print("\nFAILURES:", len(fails))
sys.exit(1 if fails else 0)

