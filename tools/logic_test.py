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
-- FixedFrame is a module (require), NOT a global in the game: provide it only through require so bare use fails here too
package.preload["scripts/utilities/fixed_frame"] = function() return { get_latest_fixed_time = function() return 1 end } end

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
-- modifiers in recipes -------------------------------------------------------
local m1 = Groups.parse("3 crushers[enraged+garden], 2 hounds")
check("parse modifiers", m1 and #m1 == 2 and m1[1].breed == "chaos_ogryn_executor" and m1[1].count == 3 and #m1[1].mods == 2 and m1[1].mods[1] == "garden" and m1[1].mods[2] == "enraged" and m1[2].mods == nil, m1 and table.concat(m1[1].mods or {}, ","))
local m2 = Groups.parse("3 crushers [ enraged and garden ], 4 hounds[toll, fire]; 1 plague ogryn|chaos spawn[bolstering]")
check("parse modifiers: separators, spaces, 'and', one_of", m2 and #m2 == 3 and #m2[1].mods == 2 and m2[2].mods[1] == "toll" and m2[2].mods[2] == "fire" and m2[3].one_of and m2[3].mods[1] == "bolstering")
check("modifier recipe roundtrip", Groups.to_recipe(m1) == "3 crusher[garden+enraged], 2 hound", Groups.to_recipe(m1))
local rt2 = Groups.parse(Groups.to_recipe(m2))
check("modifier roundtrip keeps parts", rt2 and #rt2 == 3 and rt2[1].mods[2] == "enraged" and rt2[3].one_of ~= nil and rt2[3].mods[1] == "bolstering")
local mbad, mbad_err = Groups.parse("3 crushers[gargle]")
check("unknown modifier rejected with list", mbad == nil and mbad_err:find("gargle") and mbad_err:find("garden"), mbad_err)
local mempty = Groups.parse("3 crushers[]")
check("empty brackets ok", mempty and mempty[1].mods == nil)
local mdup = Groups.parse("2 crushers[enraged], 3 crushers[enraged], 1 crusher")
check("same breed+mods merge, different mods stay apart", mdup and #mdup == 2 and mdup[1].count == 5 and mdup[2].count == 1)
check("describe with mods", Groups.describe_part(m1[1], true) == "3 Crusher [Purple, Enraged]" and Groups.describe_part(m1[1]) == "3 Crusher" and Groups.describe_mods(m1[2]) == "", Groups.describe_part(m1[1], true))
local mnames_ok = true
for _, md in ipairs(Groups.MODIFIERS) do if Groups.modifier_id(md.id) ~= md.id or #md.buffs == 0 or not md.description then mnames_ok = false end end
check("every modifier resolves and has buffs/description", mnames_ok)

-- modifier renames (1.5.1): new colour names, old names still work --------------------------
do
  local function id(word) return Groups.modifier_id(word) end
  local function name_of(mid) return Groups.modifier(mid).name end
  check("names: Purple / Red / Blight / Orange / Pus-Hardened Skin, others unchanged", name_of("garden") == "Purple" and name_of("toll") == "Red" and name_of("corrupted") == "Blight" and name_of("bolstering") == "Orange" and name_of("toughened") == "Pus-Hardened Skin" and name_of("enraged") == "Enraged" and name_of("fire") == "On Fire" and name_of("parasite") == "Head Parasite")
  check("new names resolve", id("purple") == "garden" and id("Red") == "toll" and id("blight") == "corrupted" and id("Orange") == "bolstering" and id("Pus-Hardened Skin") == "toughened" and id("pus hardened") == "toughened")
  check("old names still resolve (saved recipes keep working)", id("garden") == "garden" and id("encroaching garden") == "garden" and id("final toll") == "toll" and id("toll") == "toll" and id("corrupted") == "corrupted" and id("bolstering") == "bolstering" and id("toughened skin") == "toughened" and id("tough") == "toughened")
  check("extra names: The Final Toll, Rampaging Enemies", id("the final toll") == "toll" and id("Rampaging Enemies") == "bolstering" and id("rampaging") == "bolstering")
  check("purple (garden) and purple stimm are different modifiers", id("purple") == "garden" and id("purple stimm") == "purple_stimm" and id("Purple Stimmed") == "purple_stimm" and id("purple_stimm") == "purple_stimm" and id("splitting") == "purple_stimm")
  local d = function(mid) return Groups.modifier(mid).description end
  check("descriptions: prefixed as requested and otherwise unchanged", d("garden") == "Encroaching Garden. Extra health, resists impact, and heals nearby enemies." and d("toll") == "The Final Toll. Becomes enraged once it drops below half health (the vanilla Final Toll)." and d("bolstering") == "Rampaging Enemies. Slightly bigger and tougher (takes less damage). When it dies, enemies within 4 m get another stack, up to 5." and d("toughened") == "Tougher skin against ranged damage." and d("corrupted") == "Nurgle-corrupted: leaves corruption behind when it dies.", d("bolstering"))
  local m = Groups.parse("3 crushers[Purple+Red+Orange], 2 hounds[final toll, garden], 1 sniper[pus-hardened skin+blight]")
  check("recipes accept the new names and store canonical ids", m and m[1].mods[1] == "garden" and m[1].mods[2] == "toll" and m[1].mods[3] == "bolstering" and m[2].mods[1] == "garden" and m[2].mods[2] == "toll" and m[3].mods[1] == "corrupted" and m[3].mods[2] == "toughened", m and table.concat(m[1].mods, ","))
  check("describe shows the new names", Groups.describe_mods(m[1]) == "Purple, Red, Orange" and Groups.describe_mods(m[3]) == "Blight, Pus-Hardened Skin", Groups.describe_mods(m[1]))
  check("recipe written back uses ids (unchanged format)", Groups.to_recipe(m) == "3 crusher[garden+toll+bolstering], 2 hound[garden+toll], 1 sniper[corrupted+toughened]", Groups.to_recipe(m))
  local _, e = Groups.parse("1 hound[gargle]")
  check("error message lists ids with the colour names", e:find("garden/purple") and e:find("toll/red") and e:find("bolstering/orange") and e:find("purple_stimm") and e:find("toughened/pus%-hardened skin"), e)
end

-- "same amount on every repeat" (@= / @same) ------------------------------------------------
do
  local s1 = Groups.parse("5 crushers[enraged]@=, 2 hounds@same, 3 snipers@2, 4 poxwalkers")
  check("parse @= and @same", s1 and #s1 == 4 and s1[1].rep_same == true and s1[1].rep == nil and s1[1].count == 5 and s1[1].mods[1] == "enraged" and s1[2].rep_same == true and s1[3].rep == 2 and s1[3].rep_same == nil and s1[4].rep_same == nil)
  check("recipe roundtrip keeps @=", Groups.to_recipe(s1) == "5 crusher[enraged]@=, 2 hound@=, 3 sniper@2, 4 poxwalker", Groups.to_recipe(s1))
  local s2 = Groups.parse(Groups.to_recipe(s1))
  check("roundtrip parse keeps same flags", s2 and s2[1].rep_same and s2[2].rep_same and s2[3].rep == 2 and not s2[4].rep_same)
  check("has_repeat is true for a same-amount group", Groups.has_repeat(Groups.parse("3 hounds@=")) and not Groups.has_repeat(Groups.parse("3 hounds")))
  check("repeat_amount: same = the count, otherwise rep", Groups.repeat_amount(s1[1]) == 5 and Groups.repeat_amount(s1[3]) == 2 and Groups.repeat_amount(s1[4]) == 0)
  check("describe mentions the same-amount repeat", Groups.describe_part(s1[1], true) == "5 Crusher [Enraged] (same amount on every repeat)", Groups.describe_part(s1[1], true))
  check("a same-amount group with count 0 is dropped (nothing to repeat)", Groups.parse("0 hounds@=, 2 snipers") and #Groups.parse("0 hounds@=, 2 snipers") == 1)
  check("same and number on the same breed merge sensibly", (function() local m = Groups.parse("2 hounds@=, 3 hounds@1"); return #m == 1 and m[1].count == 5 and m[1].rep_same == true and m[1].rep == 1 end)())
end

-- twins and packmaster -------------------------------------------------------
local tw = Groups.parse("1 twin captain one, 1 twin captain two, 2 packmasters, 1 beastmaster, 1 female twin, 1 twin one")
check("twins are two separate breeds", tw and tw[1].breed == "renegade_twin_captain" and tw[2].breed == "renegade_twin_captain_two", tw and (tw[1].breed .. "/" .. tw[2].breed))
check("packmaster and old beastmaster/houndmaster names resolve to the same breed", tw[3].breed == "chaos_ogryn_houndmaster" and #tw == 3 and tw[3].count == 3, tw and tw[3].count)
check("aliases: female twin -> twin two, twin one -> twin one", tw[2].count == 2 and tw[1].count == 2, tw[1].count .. "/" .. tw[2].count)
check("display names: Packmaster, Twin Captain One/Two", Groups.display_name("chaos_ogryn_houndmaster") == "Packmaster" and Groups.display_name("renegade_twin_captain") == "Twin Captain One" and Groups.display_name("renegade_twin_captain_two") == "Twin Captain Two", Groups.display_name("renegade_twin_captain"))
check("both twins are in the picker list", (function() local n = 0 for _, b in ipairs(Groups.breed_list()) do if b:find("^renegade_twin_captain") then n = n + 1 end end return n == 2 end)())
check("recipe roundtrip for twins/packmaster", Groups.to_recipe(Groups.parse("1 twin one, 2 packmaster")) == "1 twin captain one, 2 packmaster")

-- kinds / categories / search --------------------------------------------------
check("kinds from the game's tags", Groups.kind("chaos_hound") == "special" and Groups.kind("chaos_ogryn_executor") == "elite" and Groups.kind("chaos_plague_ogryn") == "boss" and Groups.kind("renegade_twin_captain") == "boss" and Groups.kind("renegade_twin_captain_two") == "boss" and Groups.kind("cultist_captain") == "boss" and Groups.kind("chaos_ogryn_houndmaster") == "boss" and Groups.kind("chaos_poxwalker") == "normal" and Groups.kind("renegade_melee") == "normal")
check("multiplier categories: elite counts as normal", Groups.category("chaos_ogryn_executor") == "normal" and Groups.category("chaos_poxwalker") == "normal" and Groups.category("chaos_hound") == "special" and Groups.category("chaos_spawn") == "boss")
do
  local counts = { special = 0, boss = 0, elite = 0, normal = 0 }
  for _, b in ipairs(Groups.breed_list()) do counts[Groups.kind(b)] = counts[Groups.kind(b)] + 1 end
  check("every breed has a kind: 10 specials, 9 bosses, 12 elites, rest normal", counts.special == 10 and counts.boss == 9 and counts.elite == 12 and counts.normal == #Groups.breed_list() - 31, counts.special .. "/" .. counts.boss .. "/" .. counts.elite .. "/" .. counts.normal)
end
local function ids(list) return table.concat(list, ",") end
check("search: empty query = every breed", #Groups.search("") == #Groups.breed_list() and #Groups.search("   ") == #Groups.breed_list())
check("search: 'twin' finds both twins", #Groups.search("twin") == 2 and Groups.search("twin")[1]:find("twin_captain") ~= nil, ids(Groups.search("twin")))
check("search: 'twin two' finds only the second twin", #Groups.search("twin two") == 1 and Groups.search("twin two")[1] == "renegade_twin_captain_two", ids(Groups.search("twin two")))
check("search: old alias 'beastmaster' and new name 'packmaster' find the packmaster", ids(Groups.search("beastmaster")) == "chaos_ogryn_houndmaster" and ids(Groups.search("packmaster")) == "chaos_ogryn_houndmaster", ids(Groups.search("beastmaster")))
check("search: by kind words", #Groups.search("boss") == 9 and #Groups.search("special") == 10 and #Groups.search("elite") == 12 and #Groups.search("monster") == 9)
check("search: by breed id fragment and case-insensitive", ids(Groups.search("PLAGUE")) == "chaos_plague_ogryn" and #Groups.search("ogryn") >= 5)
check("search: all words must match (ogryn AND boss = plague ogryn + packmaster)", #Groups.search("ogryn boss") == 2 and #Groups.search("hound special") == 2, #Groups.search("ogryn boss") .. "/" .. #Groups.search("hound special"))
check("search: no match -> empty list", #Groups.search("xyzzy") == 0)

-- repeats ("@N") ------------------------------------------------------------
local r1 = Groups.parse("5 crushers[enraged]@2, 3 hounds, 0 snipers@4")
check("parse repeat: count, rep, mods", r1 and #r1 == 3 and r1[1].count == 5 and r1[1].rep == 2 and r1[1].mods[1] == "enraged" and r1[2].rep == nil and r1[3].count == 0 and r1[3].rep == 4, r1 and (tostring(r1[1].rep) .. "/" .. tostring(r1[3] and r1[3].rep)))
check("repeat recipe roundtrip", Groups.to_recipe(r1) == "5 crusher[enraged]@2, 3 hound, 0 sniper@4", Groups.to_recipe(r1))
local r2 = Groups.parse(Groups.to_recipe(r1))
check("repeat roundtrip keeps values", r2 and #r2 == 3 and r2[1].rep == 2 and r2[3].count == 0 and r2[3].rep == 4)
check("0 count without repeat is dropped", Groups.parse("0 hounds, 2 snipers") and #Groups.parse("0 hounds, 2 snipers") == 1)
local r3 = Groups.parse("1 plague ogryn|chaos spawn@3")
check("one_of with repeat", r3 and r3[1].one_of and r3[1].rep == 3 and r3[1].count == 1)
check("has_repeat / describe", Groups.has_repeat(r1) and not Groups.has_repeat(Groups.parse("3 hounds")) and Groups.describe_part(r1[1], true) == "5 Crusher [Enraged] (+2 per repeat)", Groups.describe_part(r1[1], true))
check("total_count counts initial units only", Groups.total_count(r1) == 8, Groups.total_count(r1))
local w_def = Events.get("wave_small", function(id) return nil end, Groups)
check("wave defaults: spread 3, repeat every 10 for 60", w_def.spread == 3 and w_def.rep_every == 10 and w_def.rep_for == 60)
local sd = Events.spawn_def(w_def)
check("spawn_def carries spread and repeat settings", sd.spread == 3 and sd.rep_every == 10 and sd.rep_for == 60 and sd.parts == w_def.parts)
do
  local st = {}
  local g, s = function(id) return st[id] end, function(id, v) st[id] = v end
  s("sp_wave_small", 8); s("re_wave_small", 5); s("rf_wave_small", 20)
  local w = Events.get("wave_small", g, Groups)
  check("wave spread/repeat settings are read", w.spread == 8 and w.rep_every == 5 and w.rep_for == 20)
  Events.reset(s, "wave_small")
  w = Events.get("wave_small", g, Groups)
  check("reset restores spread/repeat defaults", w.spread == 3 and w.rep_every == 10 and w.rep_for == 60)
end

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
local started_defs = {}
local ring_level = false
local Positions = { player_units = function() return { "p1" } end }
local Execute = {
  has_authority = function() return true end,
  start_wave = function(def) started_waves[#started_waves+1] = def.name; started_defs[#started_defs+1] = def; return true end,
  uses_ring = function() return ring_level end,
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
  send_waves = function(text) sent.waves = text; sent.waves_count = (sent.waves_count or 0) + 1; return true end,
}
local Director = load("core/director")
local PresetsMod = load("catalog/presets")
Director.init({ events = Events, groups = Groups, protocol = Protocol, execute = Execute, votes = Votes, positions = Positions, presets = PresetsMod })

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

-- time between waves: random between min and max, or fixed (the minimum)
do
  local function first_remaining()
    Director.on_exit_gameplay(); Director.on_enter_gameplay(); Director.on_mission_started(); Director.update(0.001)
    return Director.view().remaining
  end
  settings.interval_min = 15; settings.interval_max = 40
  local seen_min, seen_max, in_range = math.huge, -math.huge, true
  settings.interval_random = nil -- default: random
  for _ = 1, 200 do
    local r = first_remaining()
    seen_min, seen_max = math.min(seen_min, r), math.max(seen_max, r)
    if r < 14.99 or r > 40.01 then in_range = false end
  end
  check("interval: random (default) stays between the minimum and the maximum and actually varies", in_range and seen_max - seen_min > 5, seen_min .. ".." .. seen_max)
  settings.interval_random = false
  local fixed = {}
  for _ = 1, 20 do fixed[#fixed + 1] = first_remaining() end
  local all_fixed = true; for _, r in ipairs(fixed) do if math.abs(r - 15) > 0.01 then all_fixed = false end end
  check("interval: random off -> always exactly the minimum (15 s)", all_fixed, fixed[1])
  settings.interval_random = true
  check("interval: random on again varies", (function() local a, b = first_remaining(), first_remaining(); local c = first_remaining(); return a ~= b or b ~= c end)())
  settings.interval_random = nil
  settings.interval_min = 100; settings.interval_max = 100
  Director.on_exit_gameplay(); started_waves = {}
end

-- painted summary: the visible text is identical to the plain one at every length
do
  local recipes = { "8 poxwalkers, 2 rifleman", "5 crushers[purple+enraged]@2, 1 plague ogryn|chaos spawn, 3 hounds", "1 twin captain one" , "3 scab rager[rotten]" }
  local mismatches = {}
  for _, recipe in ipairs(recipes) do
    local parts = Groups.parse(recipe)
    for max = 4, 130 do -- (below 4 the plain version itself cuts a negative length)
      local plain = Groups.summary(parts, max)
      local painted = Groups.summary(parts, max, function(text, part) return "{#color(1,2,3)}" .. text .. "{#reset()}" end)
      local visible = painted:gsub("{#[^}]*}", "")
      if visible ~= plain then mismatches[#mismatches + 1] = recipe:sub(1, 12) .. "@" .. max .. ": [" .. visible .. "] vs [" .. plain .. "]"; if #mismatches > 3 then break end end
    end
  end
  check("summary: painted text equals the plain text at every length (colour tags never count)", #mismatches == 0, table.concat(mismatches, " | "))
  check("summary: unpainted behaviour is unchanged (no argument)", Groups.summary(Groups.parse("3 hounds"), 95) == "3 Hound")
end

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

-- everyone's waves: clients tell the host their enabled waves, the host merges them into the draw ------------------
do
  local Presets = PresetsMod
  local keys = Events.keys()
  local function disable_all_host_waves() for _, k in ipairs(keys) do settings["on_" .. k] = false end end
  local function restore_host_waves() for _, k in ipairs(keys) do settings["on_" .. k] = nil end end
  local function peer_text(waves) return Presets.encode({ name = "waves", waves = waves }) end
  local function w(key, name, recipe, pct) return { key = key, name = name, recipe = recipe, enabled = true, pct = pct, cd = 0, sp = 3, re = 10, rf = 60, dmin = 0, dmax = 0 } end

  -- client side: sends after the handshake only
  is_server = false
  sent.waves, sent.waves_count = nil, nil
  Director.on_exit_gameplay(); Director.on_enter_gameplay()
  Director.on_welcome("host_peer", 1, "9.9.9", false)
  check("pool: a client whose handshake failed sends nothing", sent.waves == nil)
  client_ok = nil
  Director.on_welcome("host_peer", 1, "1.0.0", true)
  local decoded = sent.waves and Presets.decode(sent.waves, Events, Groups)
  local enabled_count = 0; for _, k in ipairs(keys) do local wv = Events.get(k, function(id) return settings[id] end, Groups); if wv.enabled and wv.parts and #wv.parts > 0 and wv.pct > 0 then enabled_count = enabled_count + 1 end end
  check("pool: after a good handshake the client sends its enabled waves as one preset text", decoded ~= nil and #decoded.waves == enabled_count and enabled_count >= 12, decoded and #decoded.waves or tostring(sent.waves))
  local all_enabled = true; for _, wv in ipairs(decoded.waves) do if not wv.enabled or wv.pct <= 0 or wv.recipe == "" then all_enabled = false end end
  check("pool: only enabled waves with enemies and a chance are sent (full snapshots, not only the changed ones)", all_enabled)
  settings.on_custom_1 = true
  check("pool: send_waves works on a client and returns true", Director.send_waves() == true)
  settings.on_custom_1 = nil

  -- host side
  is_server = true
  check("pool: a host never sends its waves to itself", Director.send_waves() == false)
  Director.on_exit_gameplay(); Director.on_enter_gameplay()
  local friend_text = peer_text({ w("custom_1", "Friend Special", "4 hounds", 500), w("wave_small", "Small Wave", "8 poxwalker, 4 dreg, 2 rifleman", 18) })
  settings.pool_all_players = nil
  Director.on_waves("peer_a", friend_text)
  check("pool: option off (default) -> the host's own waves only", Director.extra_waves() == nil)
  settings.pool_all_players = true
  local extra = Director.extra_waves()
  check("pool: option on -> the friend's waves are available", extra ~= nil and #extra >= 1 and extra[1].key:find("^peer_a:") ~= nil, extra and #extra)
  local pool = Events.build_pool(function(id) return settings[id] end, Groups, extra)
  local names = {}; for _, e in ipairs(pool) do names[e.name] = (names[e.name] or 0) + 1 end
  local total = 0; for _, e in ipairs(pool) do total = total + e.pct end
  check("pool: the friend's special wave joins the host's pool and the chances still total 100", names["Friend Special"] == 1 and math.abs(total - 100) < 1e-6, total)
  check("pool: a wave identical to one of the host's counts once (the host's wins)", names["Small Wave"] == 1, tostring(names["Small Wave"]))
  -- name collisions get a suffix
  local clash = Events.build_pool(function(id) return settings[id] end, Groups, { { key = "x:1", name = "Small Wave", parts = Groups.parse("5 mutants"), enabled = true, pct = 5, cooldown = 0, spread = 3, rep_every = 10, rep_for = 60, dmin = 0, dmax = 0 } })
  local suffixed; for _, e in ipairs(clash) do if e.key == "x:1" then suffixed = e.name end end
  check("pool: a friend's wave with an already used name gets '(2)'", suffixed == "Small Wave (2)", tostring(suffixed))
  -- the spawn definition of a friend's wave is complete
  local friend; for _, e in ipairs(pool) do if e.name == "Friend Special" then friend = e end end
  check("pool: the friend's wave carries a full spawn definition", friend and friend.def.parts and friend.def.parts[1].breed == "chaos_hound" and friend.def.parts[1].count == 4 and friend.def.cooldown == 0 and friend.def.spread == 3 and friend.raw == 500)

  -- a full cycle where only the friend's wave exists: it is drawn and spawned
  disable_all_host_waves()
  local friend_text = peer_text({ w("custom_1", "Friend Special", "4 hounds", 500) })
  settings.mode = "random"; settings.interval_min = 100; settings.interval_max = 100; settings.initial_delay = 0
  Director.on_exit_gameplay(); started_waves = {}; started_defs = {}
  Director.on_enter_gameplay()
  Director.on_waves("peer_a", friend_text)
  Director.on_mission_started(); Director.update(0.1)
  local view_now = Director.view()
  check("pool: with no host waves the friend's wave is the next wave", view_now.phase == "waiting" and #view_now.cands == 1 and view_now.cands[1].name == "Friend Special" and view_now.cands[1].pct == 100, view_now.phase .. "/" .. #view_now.cands)
  Director.update(50); Director.update(50.5)
  check("pool: and it spawns with the friend's composition", #started_defs == 1 and started_defs[1].name == "Friend Special" and started_defs[1].parts[1].breed == "chaos_hound", #started_defs)
  -- option off: nothing to draw
  settings.pool_all_players = false
  Director.on_exit_gameplay(); Director.on_enter_gameplay(); Director.on_waves("peer_a", friend_text); Director.on_mission_started(); Director.update(0.1)
  check("pool: option off -> the friend's wave is not drawn (empty pool)", Director.view().empty == true)
  settings.pool_all_players = true

  -- housekeeping: bad text ignored, peers leaving, mission end, non-hosts ignore it
  Director.on_exit_gameplay(); Director.on_enter_gameplay()
  Director.on_waves("peer_b", "garbage"); Director.on_waves("peer_b", friend_text:sub(1, 30))
  check("pool: damaged text from a peer is ignored", Director.extra_waves() ~= nil and #Director.extra_waves() == 0)
  Director.on_waves("peer_a", friend_text)
  Director.on_waves("peer_b", peer_text({ w("custom_2", "Second Friend", "2 mutants", 40) }))
  check("pool: two peers both count", #Director.extra_waves() == 2)
  Director.on_peer_left("peer_b")
  check("pool: a peer leaving takes its waves out of the draw", #Director.extra_waves() == 1 and Director.extra_waves()[1].key:find("^peer_a:") ~= nil)
  Director.on_exit_gameplay(); Director.on_enter_gameplay()
  check("pool: ending the mission forgets them", #Director.extra_waves() == 0)
  is_server = false
  Director.on_waves("peer_a", friend_text)
  is_server = true
  check("pool: a client ignores received waves", #Director.extra_waves() == 0)
  local huge = {}; for i = 1, 60 do huge[i] = w("custom_" .. ((i - 1) % 20 + 1), "N" .. i, "1 hound", 5) end
  Director.on_waves("peer_c", peer_text(huge))
  check("pool: at most 40 waves per player are accepted", #Director.extra_waves() <= 20)
  restore_host_waves(); settings.pool_all_players = nil
  settings.interval_min = 100; settings.interval_max = 100
  Director.on_exit_gameplay(); started_waves = {}; started_defs = {}
end
-- protocol layer: RPCs registered, rw_waves send/receive validation ------------------------------------------------
do
  local registered, sent_rpcs = {}, {}
  local realms = {
    network_is_available = function() return true end,
    network_register = function(m, name, handler) registered[name] = handler; return true end,
    network_send = function(m, name, recipient, ...) sent_rpcs[#sent_rpcs + 1] = { name = name, recipient = recipient, args = { ... }, mod = m }; return true end,
    network_on_peer_joined = function() end, network_on_peer_left = function() end,
  }
  local real_get_mod = get_mod
  get_mod = function(name) if name == "Realms" then return realms end return real_get_mod(name) end
  cjson = { encode = function(v) return "{json}" end, decode = function(t) return { p = "waiting" } end }
  local P = load("core/protocol")
  local received = {}
  P.init({ on_waves = function(sender, text) received[#received + 1] = { sender, text } end, on_vote = function() end })
  local names = {}; for name in pairs(registered) do names[#names + 1] = name end; table.sort(names)
  check("protocol: five RPCs registered (hello, state, vote, waves, welcome)", table.concat(names, ",") == "rw_hello,rw_state,rw_vote,rw_waves,rw_welcome", table.concat(names, ","))
  check("protocol: send_waves goes to the host with the text as one argument (dot call: mod first)", P.send_waves("RW1|x") == true and sent_rpcs[#sent_rpcs].name == "rw_waves" and sent_rpcs[#sent_rpcs].recipient == "host" and sent_rpcs[#sent_rpcs].args[1] == "RW1|x" and sent_rpcs[#sent_rpcs].mod == mod)
  local n = #sent_rpcs
  check("protocol: a text over the size limit is not sent", P.send_waves(string.rep("x", 60001)) == false and #sent_rpcs == n and P.send_waves(42) == false)
  registered.rw_waves("peer_a", "RW1|ok")
  registered.rw_waves("", "RW1|no sender"); registered.rw_waves(nil, "x"); registered.rw_waves("peer_a", 42); registered.rw_waves("peer_a", string.rep("y", 60001))
  check("protocol: received waves are validated (sender, type, size) before the handler runs", #received == 1 and received[1][1] == "peer_a" and received[1][2] == "RW1|ok", #received)
  get_mod = real_get_mod; cjson = nil
end
-- fixed-timer waves: ignore the chance, run on their own clock, independent of the draw -----------------------------
do
  local Presets = PresetsMod
  local store = {}
  local function g(id) return store[id] end
  local function s(id, v) store[id] = v end
  local wave = Events.get("custom_1", g, Groups)
  check("timer: default is off (0)", wave.timer == 0)
  store.ev_custom_1 = 1
  check("timer: a value below 5 seconds is raised to 5 (never a 1 second flood)", Events.get("custom_1", g, Groups).timer == 5)
  store.ev_custom_1 = 45; Events.set_def(s, "custom_1", "Pulse", Groups.parse("2 hounds"), Groups); store.on_custom_1 = true
  wave = Events.get("custom_1", g, Groups)
  check("timer: stored value is read and reaches the spawn definition", wave.timer == 45 and Events.spawn_def(wave).timer == 45)
  local pool = Events.build_pool(g, Groups)
  local in_pool = false; for _, e in ipairs(pool) do if e.key == "custom_1" then in_pool = true end end
  check("timer: a timed wave is not in the draw pool (its chance is ignored)", not in_pool)
  local total = 0; for _, e in ipairs(pool) do total = total + e.pct end
  check("timer: the chances of the other waves still total 100", math.abs(total - 100) < 1e-6, total)
  local timed = Events.timed_waves(g, Groups)
  check("timer: timed_waves lists it with its period", #timed == 1 and timed[1].key == "custom_1" and timed[1].every == 45 and timed[1].def.parts[1].breed == "chaos_hound", #timed)
  store.on_custom_1 = false
  check("timer: a disabled wave does not run", #Events.timed_waves(g, Groups) == 0)
  store.on_custom_1 = true; store.wave_def_custom_1 = ""
  check("timer: an empty wave does not run", #Events.timed_waves(g, Groups) == 0)
  store.wave_def_custom_1 = "Pulse\t2 hounds"
  Events.reset(s, "custom_1")
  check("timer: reset turns it off", store.ev_custom_1 == 0)

  -- presets and wave sharing carry it
  store.ev_custom_2 = 60; Events.set_def(s, "custom_2", "Beat", Groups.parse("3 mutants"), Groups); store.on_custom_2 = true
  local cap = Presets.capture(g, Events, Groups)
  local beat; for _, w2 in ipairs(cap.waves) do if w2.key == "custom_2" then beat = w2 end end
  check("timer: presets capture it", beat and beat.timer == 60)
  cap.name = "T"
  local back = Presets.decode(Presets.encode(cap), Events, Groups)
  local back_beat; for _, w2 in ipairs(back.waves) do if w2.key == "custom_2" then back_beat = w2 end end
  check("timer: presets round trip it", back_beat and back_beat.timer == 60)
  local applied = {}
  Presets.apply(back, function(id, v) applied[id] = v end, Events, Groups)
  check("timer: applying a preset writes it (and 0 for the others)", applied.ev_custom_2 == 60 and applied.ev_wave_small == 0)
  local one = Presets.decode_wave(Presets.encode_wave(Presets.capture_wave(g, "custom_2", Events, Groups)), Events, Groups)
  check("timer: a shared single wave carries it", one and one.timer == 60)
  local old11 = Presets.decode_wave(Presets.seal("RWW1|custom_1~A~1~10~60~3~10~60~3 hounds~0~0"), Events, Groups)
  local old9 = Presets.decode_wave(Presets.seal("RWW1|custom_1~A~1~10~60~3~10~60~3 hounds"), Events, Groups)
  check("timer: texts from before 1.11.0 (9 or 11 fields) import with no timer", old11 and old11.timer == 0 and old9 and old9.timer == 0)
  local clamp = Presets.decode_wave(Presets.seal("RWW1|custom_1~A~1~10~60~3~10~60~3 hounds~0~0~99999"), Events, Groups)
  check("timer: out-of-range timer clamped to 3600, bad value refused", clamp and clamp.timer == 3600 and Presets.decode_wave(Presets.seal("RWW1|custom_1~A~1~10~60~3~10~60~3 hounds~0~0~soon"), Events, Groups) == nil)
  local sent_text = Presets.enabled_waves(g, Events, Groups)
  local sends_timed = false; for _, w2 in ipairs(sent_text.waves) do if w2.key == "custom_2" then sends_timed = true end end
  check("timer: a client does not offer its timed waves to the host's draw", not sends_timed)
  check("timer: ...and the host never merges a timed wave from a peer", #Presets.pool_waves({ waves = { { key = "custom_2", name = "Beat", recipe = "3 mutants", enabled = true, pct = 10, cd = 0, sp = 3, re = 10, rf = 60, dmin = 0, dmax = 0, timer = 60 } } }, "p", Events, Groups) == 0)
end

do
  -- the director: own clock, independent of the draw
  settings.mode = "random"; settings.interval_min = 1000; settings.interval_max = 1000; settings.initial_delay = 0; settings.vote_duration = 25
  settings.wave_def_custom_1 = "Pulse\t2 hounds"; settings.on_custom_1 = true; settings.ev_custom_1 = 20
  started_waves = {}; started_defs = {}
  Director.on_exit_gameplay(); Director.on_enter_gameplay(); Director.on_mission_started(); Director.update(0.01)
  local v = Director.view()
  local on_ballot = false; for _, cand in ipairs(v.cands) do if cand.key == "custom_1" then on_ballot = true end end
  check("timer: the timed wave is never the 'next wave' of the draw", v.phase == "waiting" and not on_ballot)
  local function count_pulse() local n = 0; for _, nme in ipairs(started_waves) do if nme == "Pulse" then n = n + 1 end end return n end
  for _ = 1, 19 do Director.update(1) end
  check("timer: nothing before its period is over", count_pulse() == 0, count_pulse())
  Director.update(1.5)
  check("timer: spawns once after 20 s", count_pulse() == 1 and started_defs[#started_defs].parts[1].breed == "chaos_hound", count_pulse())
  for _ = 1, 20 do Director.update(1) end
  check("timer: and again after another 20 s (the draw has not fired: its interval is 1000 s)", count_pulse() == 2 and #started_waves == 2, count_pulse() .. "/" .. #started_waves)
  settings.ev_custom_1 = 5
  for _ = 1, 8 do Director.update(1) end
  check("timer: a shorter period (5 s) takes effect without waiting out the old 20 s", count_pulse() >= 3, count_pulse())
  local before = count_pulse()
  settings.on_custom_1 = false
  for _ = 1, 30 do Director.update(1) end
  check("timer: disabling the wave stops it (at most the spawn that was already due)", count_pulse() - before <= 1, count_pulse() - before)
  local stopped = count_pulse()
  for _ = 1, 30 do Director.update(1) end
  check("timer: ...for good", count_pulse() == stopped)
  check("timer: /rw_status counts timed waves", Director.timed_wave_count() == 0)
  settings.on_custom_1 = true; settings.ev_custom_1 = 20
  for _ = 1, 2 do Director.update(1) end
  check("timer: re-enabled -> running again", Director.timed_wave_count() == 1)
  -- no living player: the clock stops
  local players = Positions.player_units
  Positions.player_units = function() return {} end
  local n_before = count_pulse()
  for _ = 1, 60 do Director.update(1) end
  check("timer: the clock does not run without a living player", count_pulse() == n_before)
  Positions.player_units = players
  Director.on_exit_gameplay()
  check("timer: the mission ending clears the clocks", Director.timed_wave_count() == 0)
  settings.wave_def_custom_1, settings.on_custom_1, settings.ev_custom_1 = nil, nil, nil
  settings.interval_min, settings.interval_max = 100, 100
  started_waves = {}; started_defs = {}
end
-- /rw_test by name ------------------------------------------------------------------
do
  local get = function(id) return settings[id] end
  local set = function(id, v) settings[id] = v end
  Events.set_def(set, "custom_2", "Mutants Everywhere!", Groups.parse("6 mutants"), Groups)
  Events.set_def(set, "custom_5", "Mutant Ambush", Groups.parse("2 mutants, 1 sniper"), Groups)
  local function found(q) local w, err = Events.find(q, get, Groups) return w and w.key or nil, err end
  check("find: normalize_name", Events.normalize_name("  Mutants Everywhere! ") == "mutants_everywhere" and Events.normalize_name("mutants-everywhere") == "mutants_everywhere" and Events.normalize_name("__A  b__") == "a_b")
  check("find: by key", found("custom_2") == "custom_2" and found("hound_frenzy") == "hound_frenzy" and found("CUSTOM_2") == "custom_2")
  check("find: renamed custom wave by name with underscores", found("mutants_everywhere") == "custom_2")
  check("find: by name with spaces, any case, punctuation", found("Mutants Everywhere") == "custom_2" and found("MUTANTS everywhere!") == "custom_2" and found("mutants-everywhere") == "custom_2")
  check("find: built-in wave by its displayed name", found("Small Wave") == "wave_small" and found("hound_frenzy") == "hound_frenzy" and found("hound frenzy") == "hound_frenzy")
  check("find: unique prefix", found("mutants_ever") == "custom_2" and found("boss") == "boss_ambush")
  check("find: unique substring", found("everywhere") == "custom_2")
  local amb2_key, amb2_err = found("ambush")
  check("find: a substring shared by two waves (Boss Ambush, Mutant Ambush) is ambiguous", amb2_key == nil and amb2_err:find("Boss Ambush") ~= nil and amb2_err:find("Mutant Ambush") ~= nil, amb2_err)
  local amb_key, amb_err = found("mutant")
  check("find: ambiguous text is refused and lists the candidates", amb_key == nil and amb_err:find("several waves match") and amb_err:find("Mutants Everywhere") and amb_err:find("Mutant Ambush"), amb_err)
  local unk_key, unk_err = found("no_such_wave")
  check("find: unknown name gives a helpful message", unk_key == nil and unk_err:find("no wave named") ~= nil, unk_err)
  check("find: empty query is refused", found("   ") == nil and select(2, found("")) ~= nil)
  check("find: an empty custom slot is found by key or exact name but never guessed", found("custom_9") == "custom_9" and found("Custom 9") == "custom_9" and found("cust") == nil)
  -- renaming: the old default name stops matching, the new one matches
  Events.set_def(set, "custom_2", "Dog Party", Groups.parse("6 hounds"), Groups)
  check("find: after a rename the new name works and the old one does not", found("dog_party") == "custom_2" and found("mutants_everywhere") == nil)
  -- through the director (what /rw_test calls)
  Director.on_exit_gameplay(); Director.on_enter_gameplay()
  started_waves = {}
  local fok, ferr = Director.fire_now("dog party")
  check("director.fire_now accepts a wave name", fok and started_waves[1] == "Dog Party", tostring(ferr) .. " / " .. tostring(started_waves[1]))
  check("director.fire_now marks the wave as an explicit test (ring fallback allowed)", started_defs[#started_defs].test == true and ferr == nil, tostring(ferr))
  ring_level = true
  local rok, rnote = Director.fire_now("dog party")
  check("director.fire_now warns when the level has no spawn points (ring used)", rok and type(rnote) == "string" and rnote:find("ring") ~= nil, tostring(rnote))
  ring_level = false
  local fok2, ferr2 = Director.fire_now("nope")
  check("director.fire_now reports an unknown name", fok2 == false and ferr2:find("no wave named") ~= nil, ferr2)
  Events.reset(set, "custom_2"); Events.reset(set, "custom_5")
  for _, k in ipairs({ "wave_def_custom_2", "wave_def_custom_5", "on_custom_2", "on_custom_5" }) do settings[k] = nil end
end

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

-- Execute (spawner) with modifiers, against stubbed game APIs -----------------
local Execute = load("spawn/execute")
local havoc_present = false
local buff_log = {}
local function make_buff_ext(unit_name)
  local ext = { added = {} }
  ext.is_valid_target = function(self, name) return name ~= "invalid_buff" end
  ext.add_internally_controlled_buff = function(self, name, t)
    if name == "havoc_bolstering" then error("boom") end
    self.added[#self.added + 1] = name
  end
  ext._update_stat_buffs_and_keywords = function(self) self.updated = true end
  return ext
end
ScriptUnit = { has_extension = function(unit, sys) return sys == "buff_system" and unit.buffs or nil end }
Unit = { world_rotation = function() return "rot" end }
local spawned = {}
local minion_spawn = {
  request_param_table = function() return {} end,
  spawn_minion = function(self, breed, pos, rot, side_id, param)
    local unit = { breed = breed, buffs = make_buff_ext(breed), aggro = param.optional_aggro_state, init_toughness = param.optional_init_toughness, side = side_id, spawn_flag = Bypass.spawning }
    spawned[#spawned + 1] = unit
    return unit
  end,
}
local saved_state = { minion_spawn = Managers.state.minion_spawn, extension = Managers.state.extension, game_mode = Managers.state.game_mode }
local saved_time = Managers.time
Managers.state.minion_spawn = minion_spawn
Managers.state.extension = { system = function() return { get_side_from_name = function() return { side_id = 2 } end } end }
Managers.state.game_mode = { game_mode = function() return { name = function() return "coop_complete_objective" end, extension = function(self, n) return (n == "havoc" and havoc_present) and {} or nil end } end }
Managers.time = { time = function() return 5 end }
local spread_calls = {}
local cand_calls, cand_fail = 0, false
local cand_reason, ring_fail, ring_calls = "no hidden points near players", false, 0
local last_range = nil
local StubPositions = {
  candidates = function(min_d, max_d) cand_calls = cand_calls + 1; last_range = { min_d, max_d }; if cand_fail then return nil, cand_reason end return { "a", "b" } end,
  test_candidates = function() ring_calls = ring_calls + 1; if ring_fail then return nil, "no walkable ground within reach of the player" end return { "ring" } end,
  pick = function(list) return "pos" end,
  random_player_unit = function() return "player" end,
  spread = function(position, radius) spread_calls[#spread_calls + 1] = radius; return position .. "+" .. tostring(radius) end,
}
Bypass.reset()
Execute.init({ positions = StubPositions, bypass = Bypass, groups = Groups })
settings.max_per_wave = nil; settings.max_alive = nil

local function run_wave(def)
  spawned = {}
  local ok, err = Execute.start_wave(def)
  for _ = 1, 20 do Execute.update(0.2) end
  return ok, err
end

local ok_wave = run_wave({ name = "t", parts = Groups.parse("3 crushers[enraged+garden], 2 hounds") })
local crushers, hounds = {}, {}
for _, u in ipairs(spawned) do if u.breed == "chaos_ogryn_executor" then crushers[#crushers+1] = u else hounds[#hounds+1] = u end end
check("execute: wave spawns all units", ok_wave and #spawned == 5 and #crushers == 3 and #hounds == 2, #spawned)
local all_buffed = #crushers == 3
for _, u in ipairs(crushers) do
  if not (#u.buffs.added == 2 and u.buffs.added[1] == "havoc_encroaching_garden" and u.buffs.added[2] == "havoc_enraged_enemies" and u.buffs.updated) then all_buffed = false end
end
check("execute: crushers get garden + enraged buffs (catalog order)", all_buffed, table.concat(crushers[1] and crushers[1].buffs.added or {}, ","))
local hounds_clean = true; for _, u in ipairs(hounds) do if #u.buffs.added ~= 0 then hounds_clean = false end end
check("execute: hounds get no buffs", hounds_clean)
check("execute: units aggroed, villain side, tracked by bypass", spawned[1].aggro == "aggroed" and spawned[1].side == 2 and spawned[1].spawn_flag == true and Bypass.count() == 5, Bypass.count())

-- Havoc-only modifier is skipped outside Havoc, applied inside it
run_wave({ name = "t", parts = Groups.parse("2 crushers[toughened]") })
check("execute: toughened skipped outside Havoc", #spawned == 2 and #spawned[1].buffs.added == 0)
havoc_present = true
run_wave({ name = "t", parts = Groups.parse("2 crushers[toughened]") })
check("execute: toughened applied in Havoc", #spawned == 2 and spawned[1].buffs.added[1] == "havoc_toughened_skin")
havoc_present = false

-- a buff that errors must not break the wave or the other modifiers
run_wave({ name = "t", parts = Groups.parse("2 crushers[bolstering+fire]") })
check("execute: erroring buff is contained, other modifier still applied", #spawned == 2 and #spawned[1].buffs.added == 1 and spawned[1].buffs.added[1] == "common_minion_on_fire" and spawned[1].buffs.updated)
local warned_boom = false; for _, e in ipairs(echoes) do if e:find("Orange") and e:find("boom") then warned_boom = true end end
check("execute: buff failure is logged", warned_boom)

-- caps and one_of
settings.max_per_wave = 4
run_wave({ name = "t", parts = Groups.parse("10 hounds") })
check("execute: max_per_wave caps the wave", #spawned == 4, #spawned)
settings.max_per_wave = nil
run_wave({ name = "t", parts = Groups.parse("6 plague ogryn|chaos spawn|beast of nurgle[garden]") })
local seen = {}; for _, u in ipairs(spawned) do seen[u.breed] = true end
local allowed_only = true; for b in pairs(seen) do if b ~= "chaos_plague_ogryn" and b ~= "chaos_spawn" and b ~= "chaos_beast_of_nurgle" then allowed_only = false end end
check("execute: one_of picks only listed breeds, keeps modifiers", #spawned == 6 and allowed_only and spawned[1].buffs.added[1] == "havoc_encroaching_garden")

-- spread: every unit is placed through Positions.spread with the wave's radius
spread_calls = {}
run_wave({ name = "t", spread = 6, parts = Groups.parse("4 hounds") })
local all_spread = #spread_calls == 4
for _, r in ipairs(spread_calls) do if r ~= 6 then all_spread = false end end
check("execute: each unit goes through Positions.spread with the wave radius", all_spread, #spread_calls)
spread_calls = {}
run_wave({ name = "t", parts = Groups.parse("2 hounds") })
check("execute: no spread configured -> radius 0", #spread_calls == 2 and spread_calls[1] == 0)

-- Presets: capture / encode / decode / apply / slots ---------------------------------------------------------
do
  local Presets = load("catalog/presets")
  local store = {}
  local function get(id) return store[id] end
  local function set(id, v) store[id] = v end
  local function state() return Presets.encode(Presets.capture(get, Events, Groups)) end

  check("presets: a fresh setup captures nothing (only changed waves are stored)", #Presets.capture(get, Events, Groups).waves == 0)

  -- build a setup: rename + new composition on a standard wave, chance/cooldown on another, a custom wave
  Events.set_def(set, "wave_small", "My Small", Groups.parse("4 hounds, 2 scab rager"), Groups)
  set("pct_boss_ambush", 40); set("cd_boss_ambush", 90); set("on_hound_frenzy", false)
  Events.set_def(set, "custom_3", "Weird | Name ~ 100%", Groups.parse("3 crushers[rotten+enraged]@2, 1 plague ogryn|chaos spawn"), Groups)
  set("on_custom_3", true); set("pct_custom_3", 25); set("sp_custom_3", 12); set("re_custom_3", 7); set("rf_custom_3", 42)
  local cap = Presets.capture(get, Events, Groups)
  local keys = {}; for _, w in ipairs(cap.waves) do keys[w.key] = w end
  check("presets: capture holds exactly the changed waves", #cap.waves == 4 and keys.wave_small and keys.boss_ambush and keys.hound_frenzy and keys.custom_3, #cap.waves)
  check("presets: chance-only change keeps the default name/recipe", keys.boss_ambush.pct == 40 and keys.boss_ambush.cd == 90 and keys.boss_ambush.name == Events.get("boss_ambush", function() return nil end, Groups).name)

  cap.name = "  My   Setup " .. string.rep("x", 40)
  local text = Presets.encode(cap)
  check("presets: text is one line starting with RW1|, no raw separators inside names", text:sub(1, 4) == "RW1|" and not text:find("[\r\n\t]") and select(2, text:gsub("|", "")) == 3 + #cap.waves, text:sub(1, 60))
  local back, err = Presets.decode(text, Events, Groups)
  check("presets: decode accepts what encode wrote", back ~= nil and #back.waves == #cap.waves and back.skipped == 0, tostring(err))
  check("presets: name is trimmed to 24 characters", back and #back.name <= 24 and back.name:sub(1, 8) == "My Setup", back and back.name)
  local dk = {}; for _, w in ipairs(back.waves) do dk[w.key] = w end
  check("presets: awkward characters in a wave name survive (| ~ %)", dk.custom_3.name == "Weird | Name ~ 100%", dk.custom_3.name)
  check("presets: values round trip", dk.custom_3.enabled == true and dk.custom_3.pct == 25 and dk.custom_3.sp == 12 and dk.custom_3.re == 7 and dk.custom_3.rf == 42 and dk.hound_frenzy.enabled == false, tostring(dk.custom_3.recipe))

  -- applying it to a different, messy setup gives exactly the saved setup
  local before = state()
  local other = {}
  local function oget(id) return other[id] end
  local function oset(id, v) other[id] = v end
  Events.set_def(oset, "custom_1", "Junk", Groups.parse("9 hounds"), Groups)
  oset("on_custom_1", true); oset("pct_wave_medium", 77); oset("on_boss_ambush", false)
  local written = Presets.apply(back, oset, Events, Groups)
  check("presets: apply writes the stored waves", written == 4, written)
  local applied = Presets.encode({ name = "X", waves = Presets.capture(oget, Events, Groups).waves })
  local applied_named = applied
  local expected = Presets.encode({ name = "X", waves = back.waves })
  check("presets: after apply the setup equals the saved one, the leftovers (custom_1, pct_wave_medium, boss_ambush off) are gone", applied_named == expected, applied:sub(1, 200))
  check("presets: apply does not turn untouched standard waves into overrides", other["wave_def_wave_large"] == "" and other["wave_def_boss_ambush"] == "", tostring(other["wave_def_boss_ambush"]))

  -- damaged / hostile text is refused as a whole
  local function bad(t) local p, e = Presets.decode(t, Events, Groups); return p == nil and type(e) == "string" and e end
  check("presets: empty text refused", bad("   "))
  check("presets: wrong prefix refused", bad("hello world") and bad(Presets.seal("RW2|x|0")))
  local cut = text:sub(1, #text - 15)
  check("presets: text cut short is detected by the check field", (bad(cut) or ""):find("incomplete") ~= nil, bad(cut))
  check("presets: text with a space or a wrapped line added is refused", (bad(text:sub(1, 30) .. " " .. text:sub(31)) or ""):find("changed") ~= nil and (bad(text:sub(1, 40) .. "\n" .. text:sub(41)) or ""):find("changed") ~= nil)
  check("presets: leading/trailing whitespace around the text is fine (paste artifacts)", Presets.decode("  \n" .. text .. " \r\n", Events, Groups) ~= nil)
  check("presets: an unknown enemy in a recipe is refused with the parser's message", (bad(Presets.seal("RW1|x|1|custom_1~A~1~10~60~3~10~60~unicorns")) or ""):find("unicorns") ~= nil, bad(Presets.seal("RW1|x|1|custom_1~A~1~10~60~3~10~60~unicorns")))
  check("presets: wrong field count refused", bad(Presets.seal("RW1|x|1|custom_1~A~1~10")) ~= false)
  check("presets: non-numeric value refused", bad(Presets.seal("RW1|x|1|custom_1~A~1~lots~60~3~10~60~3 hounds")) ~= false)
  local wild = Presets.decode(Presets.seal("RW1|x|1|custom_1~A~1~99999~-5~500~0~99999~3 hounds"), Events, Groups)
  check("presets: out-of-range numbers are clamped to the editor's limits", wild and wild.waves[1].pct == 1000 and wild.waves[1].cd == 0 and wild.waves[1].sp == 100 and wild.waves[1].re == 1 and wild.waves[1].rf == 3600, wild and wild.waves[1].pct)
  local unk = Presets.decode(Presets.seal("RW1|x|2|custom_1~A~1~10~60~3~10~60~3 hounds|future_wave~B~1~10~60~3~10~60~2 hounds"), Events, Groups)
  check("presets: waves of an unknown key are skipped, the rest imported", unk and #unk.waves == 1 and unk.skipped == 1)
  check("presets: bad text never touches the settings (decode has no side effects)", state() == before)

  -- slots
  Presets.write(set, Presets.slot_id(2), back)
  local read = Presets.read(get, Presets.slot_id(2), Events, Groups)
  check("presets: slot round trip", read and read.name == back.name and #read.waves == 4)
  check("presets: empty slot reads as nil", Presets.read(get, Presets.slot_id(3), Events, Groups) == nil)
  store.preset_4 = "garbage"
  local nothing, problem = Presets.read(get, "preset_4", Events, Groups)
  check("presets: a damaged slot reads as nil with a message", nothing == nil and type(problem) == "string")
  Presets.clear(set, Presets.slot_id(2))
  check("presets: cleared slot is empty", Presets.read(get, Presets.slot_id(2), Events, Groups) == nil and Presets.COUNT == 5)
end
-- Rotten Armor: only Maulers, Ragers, Crushers; not doubled when the mission already applied it
do
  check("rotten: parses with its names and aliases", Groups.modifier_id("rotten") == "rotten" and Groups.modifier_id("Rotten Armor") == "rotten" and Groups.modifier_id("rotten armour") == "rotten")
  local rp, rerr = Groups.parse("2 crushers[rotten], 1 mauler[rotten+enraged], 1 scab rager[rotten]")
  check("rotten: recipe accepted", rp ~= nil and #rp == 3, tostring(rerr))
  Execute.reset(); echoes = {}
  run_wave({ name = "t", parts = Groups.parse("2 crushers[rotten], 1 mauler[rotten], 1 scab rager[rotten], 1 rager[rotten], 2 hounds[rotten]") })
  local got, hound_buffs = 0, 0
  for _, u in ipairs(spawned) do
    if u.breed == "chaos_hound" then hound_buffs = hound_buffs + #u.buffs.added
    elseif u.buffs.added[1] == "mutator_rotten_armor" then got = got + 1 end
  end
  check("rotten: eligible breeds get the buff, others do not", got == 4 and hound_buffs == 0, got .. "/" .. hound_buffs)
  local said = false; for _, e in ipairs(echoes) do if e:find("Rotten Armor only works on Crusher, Scab Mauler, Scab Rager", 1, true) and e:find("skipped on Hound", 1, true) then said = true end end
  check("rotten: skipping an unsuited breed is logged in plain words", said, table.concat(echoes, " | "))
  -- the mission already gave it: no second copy
  local orig_make = make_buff_ext
  local pre = { renegade_executor = true }
  Execute.reset(); echoes = {}
  local orig_spawn = minion_spawn.spawn_minion
  minion_spawn.spawn_minion = function(self, breed, ...)
    local unit = orig_spawn(self, breed, ...)
    unit.buffs.has_buff_using_buff_template = function(ext, name) return name == "mutator_rotten_armor" end
    return unit
  end
  run_wave({ name = "t", parts = Groups.parse("2 maulers[rotten]") })
  minion_spawn.spawn_minion = orig_spawn
  local doubled = false; for _, u in ipairs(spawned) do if #u.buffs.added > 0 then doubled = true end end
  check("rotten: not added again when the unit already has it", #spawned == 2 and not doubled)
end
-- per-wave spawn distances: 0 = the options, otherwise this wave's own value
do
  local function range_for(def)
    Execute.reset(); last_range = nil
    def.name = "dist"; def.parts = Groups.parse("1 hound")
    run_wave(def)
    return last_range
  end
  settings.min_distance, settings.max_distance, settings.monster_min_distance, settings.monster_max_distance = 22, 65, 28, 75
  local r = range_for({})
  check("distance: no own values -> the options (22-65 m)", r and r[1] == 22 and r[2] == 65, r and (r[1] .. "-" .. r[2]))
  r = range_for({ monster = true })
  check("distance: monster waves use the monster options (28-75 m)", r and r[1] == 28 and r[2] == 75)
  r = range_for({ dmin = 40, dmax = 90 })
  check("distance: a wave's own min and max replace the options", r and r[1] == 40 and r[2] == 90, r and (r[1] .. "-" .. r[2]))
  r = range_for({ dmin = 40 })
  check("distance: only a minimum set -> the option maximum stays", r and r[1] == 40 and r[2] == 65)
  r = range_for({ dmax = 30 })
  check("distance: only a maximum set -> the option minimum stays (22-30)", r and r[1] == 22 and r[2] == 30, r and (r[1] .. "-" .. r[2]))
  r = range_for({ dmin = 80 })
  check("distance: a minimum above the option maximum pushes the maximum up (never an empty range)", r and r[1] == 80 and r[2] > 80, r and (r[1] .. "-" .. r[2]))
  r = range_for({ dmax = 15 })
  check("distance: a maximum below the option minimum pulls the minimum down", r and r[2] == 15 and r[1] < 15, r and (r[1] .. "-" .. r[2]))
  -- cached positions of a wave with other distances are not reused
  Execute.reset(); last_range = nil; cand_calls = 0
  run_wave({ name = "a", parts = Groups.parse("1 hound") })
  local first_calls = cand_calls
  run_wave({ name = "b", parts = Groups.parse("1 hound"), dmin = 60, dmax = 100 })
  check("distance: positions cached for other distances are not reused", last_range and last_range[1] == 60 and cand_calls > first_calls)
  -- through the catalog
  local store = {}
  local function g(id) return store[id] end
  local function s(id, v) store[id] = v end
  local wave = Events.get("wave_small", g, Groups)
  check("distance: default is 0/0 (use the options)", wave.dmin == 0 and wave.dmax == 0)
  store.dmin_wave_small = 35; store.dmax_wave_small = 120
  wave = Events.get("wave_small", g, Groups)
  local sdef = Events.spawn_def(wave)
  check("distance: stored values reach the spawn definition", sdef.dmin == 35 and sdef.dmax == 120)
  Events.reset(s, "wave_small")
  check("distance: reset puts them back to 0", store.dmin_wave_small == 0 and store.dmax_wave_small == 0)
  -- presets
  local Presets = load("catalog/presets")
  store.dmin_custom_2 = 30; store.dmax_custom_2 = 80; store.wave_def_custom_2 = "Far\t3 hounds"; store.on_custom_2 = true
  local cap = Presets.capture(g, Events, Groups)
  local far; for _, w in ipairs(cap.waves) do if w.key == "custom_2" then far = w end end
  check("distance: presets capture them", far and far.dmin == 30 and far.dmax == 80)
  cap.name = "D"
  local back = Presets.decode(Presets.encode(cap), Events, Groups)
  local back_far; for _, w in ipairs(back.waves) do if w.key == "custom_2" then back_far = w end end
  check("distance: presets round trip them", back_far and back_far.dmin == 30 and back_far.dmax == 80)
  local applied = {}
  Presets.apply(back, function(id, v) applied[id] = v end, Events, Groups)
  check("distance: applying a preset writes them", applied.dmin_custom_2 == 30 and applied.dmax_custom_2 == 80 and applied.dmin_wave_small == 0)
  local old = Presets.decode(Presets.seal("RW1|old|1|custom_1~A~1~10~60~3~10~60~3 hounds"), Events, Groups)
  check("distance: a preset exported before 1.8.0 (9 fields) still imports, distances 0", old and old.waves[1].dmin == 0 and old.waves[1].dmax == 0)
  local clamped = Presets.decode(Presets.seal("RW1|x|1|custom_1~A~1~10~60~3~10~60~3 hounds~9999~-5"), Events, Groups)
  check("distance: out-of-range distances are clamped (0-200)", clamped and clamped.waves[1].dmin == 200 and clamped.waves[1].dmax == 0)
  check("distance: a non-numeric distance is refused", Presets.decode(Presets.seal("RW1|x|1|custom_1~A~1~10~60~3~10~60~3 hounds~far~5"), Events, Groups) == nil)
end
-- sharing ONE wave (RWW1 text) ---------------------------------------------------------------------------------
do
  local Presets = load("catalog/presets")
  local store = {}
  local function g(id) return store[id] end
  local function s(id, v) store[id] = v end
  Events.set_def(s, "custom_6", "Odd | Name ~ 50%", Groups.parse("3 crushers[purple+enraged]@2, 1 plague ogryn|chaos spawn"), Groups)
  store.on_custom_6 = true; store.pct_custom_6 = 21; store.cd_custom_6 = 99; store.sp_custom_6 = 14; store.re_custom_6 = 8; store.rf_custom_6 = 44; store.dmin_custom_6 = 30; store.dmax_custom_6 = 110
  local snap = Presets.capture_wave(g, "custom_6", Events, Groups)
  check("wave share: capture_wave reads one wave", snap and snap.key == "custom_6" and snap.pct == 21 and snap.dmin == 30 and snap.dmax == 110)
  local text = Presets.encode_wave(snap)
  check("wave share: text is one line starting with RWW1|", text:sub(1, 5) == "RWW1|" and not text:find("[\r\n\t]") and select(2, text:gsub("|", "")) == 2, text:sub(1, 40))
  local wave, err = Presets.decode_wave(text, Events, Groups)
  check("wave share: round trip keeps name (with | ~ %), values and recipe", wave and wave.name == "Odd | Name ~ 50%" and wave.pct == 21 and wave.cd == 99 and wave.sp == 14 and wave.re == 8 and wave.rf == 44 and wave.dmin == 30 and wave.dmax == 110 and wave.enabled == true and wave.recipe == snap.recipe, tostring(err))
  -- applying it onto ANOTHER key replaces that wave completely
  local target = {}
  local function tg(id) return target[id] end
  local function ts(id, v) target[id] = v end
  Events.set_def(ts, "custom_2", "Old", Groups.parse("9 hounds"), Groups); target.pct_custom_2 = 5; target.dmin_custom_2 = 77
  Presets.apply_wave(wave, "custom_2", ts, Events, Groups)
  local now = Presets.capture_wave(tg, "custom_2", Events, Groups)
  check("wave share: apply_wave onto another key replaces every setting of that wave", now.name == wave.name and now.recipe == wave.recipe and now.pct == 21 and now.dmin == 30 and now.dmax == 110 and now.key == "custom_2")
  check("wave share: the source wave is untouched by applying elsewhere", Presets.capture_wave(g, "custom_6", Events, Groups).name == "Odd | Name ~ 50%")
  -- a standard wave can be overwritten too, and a standard wave shared keeps its built-in name when unchanged
  local std = Presets.capture_wave(function() return nil end, "wave_small", Events, Groups)
  local std_text = Presets.encode_wave(std)
  local std_back = Presets.decode_wave(std_text, Events, Groups)
  Presets.apply_wave(std_back, "wave_large", ts, Events, Groups)
  check("wave share: a standard wave applied onto another standard wave", Presets.capture_wave(tg, "wave_large", Events, Groups).name == "Small Wave")
  local function bad(t) local w, e = Presets.decode_wave(t, Events, Groups); return w == nil and type(e) == "string" and e end
  check("wave share: empty text refused", bad("  ") ~= false)
  check("wave share: a whole preset is refused with a pointer to the Presets screen", (bad(Presets.encode({ name = "x", waves = {} })) or ""):find("Presets screen") ~= nil)
  check("wave share: wrong prefix refused", (bad("hello") or ""):find("RWW1") ~= nil)
  check("wave share: altered/cut text refused", (bad(text:sub(1, #text - 5)) or ""):find("incomplete or was changed") ~= nil and (bad(text:sub(1, 20) .. " " .. text:sub(21)) or ""):find("incomplete or was changed") ~= nil)
  check("wave share: unknown enemy in the recipe refused with the parser's message", (bad(Presets.seal("RWW1|custom_1~A~1~10~60~3~10~60~unicorns~0~0")) or ""):find("unicorns") ~= nil)
  check("wave share: damaged wave refused", bad(Presets.seal("RWW1|custom_1~A~1~10")) ~= false and bad(Presets.seal("RWW1|a|b")) ~= false)
  local w2 = Presets.decode_wave(Presets.seal("RWW1|custom_1~~1~99999~-5~500~0~99999~3 hounds~9999~-1"), Events, Groups)
  check("wave share: numbers clamped to the editor's limits, empty name allowed", w2 and w2.pct == 1000 and w2.cd == 0 and w2.sp == 100 and w2.re == 1 and w2.rf == 3600 and w2.dmin == 200 and w2.dmax == 0 and w2.name == "")
  local old = Presets.decode_wave(Presets.seal("RWW1|custom_1~Old~1~10~60~3~10~60~3 hounds"), Events, Groups)
  check("wave share: 9-field wave text (no distances) imports with distances 0", old and old.dmin == 0 and old.dmax == 0)
  -- a text with an unknown key still imports (the key is only the exporter's)
  local fk = Presets.decode_wave(Presets.seal("RWW1|future_wave~F~1~10~60~3~10~60~3 hounds~0~0"), Events, Groups)
  check("wave share: the exporter's key does not matter (unknown keys are fine)", fk and fk.key == "future_wave")
end
-- twin captains: the shield starts down (toughness template start_depleted) and must be raised via optional_init_toughness
do
  package.preload["scripts/settings/breed/breeds"] = function()
    return {
      renegade_twin_captain = { toughness_template = { start_depleted = true } },
      renegade_twin_captain_two = { toughness_template = { start_depleted = true } },
      renegade_captain = { toughness_template = { start_depleted = nil } },
      chaos_hound = {},
    }
  end
  Execute.reset()
  run_wave({ name = "twins", parts = Groups.parse("1 twin captain one, 1 twin captain two, 1 hound, 1 captain") })
  local by = {}
  for _, u in ipairs(spawned) do by[u.breed] = u.init_toughness end
  check("twins: both twin captains are spawned with optional_init_toughness (shield up)", by.renegade_twin_captain == true and by.renegade_twin_captain_two == true, tostring(by.renegade_twin_captain) .. "/" .. tostring(by.renegade_twin_captain_two))
  check("twins: other breeds never get it", by.chaos_hound == nil and by.renegade_captain == nil)
  package.preload["scripts/settings/breed/breeds"] = nil
  package.loaded["scripts/settings/breed/breeds"] = nil
end

-- levels without a main path (Psykhanium): only explicit /rw_test waves use the ring fallback ---------
do
  local function recent(pattern) for _, e in ipairs(echoes) do if e:find(pattern, 1, true) then return e end end return nil end
  cand_fail, cand_reason = true, "main path not ready"

  Execute.reset(); echoes = {}; ring_calls = 0
  run_wave({ name = "ringtest", test = true, parts = Groups.parse("3 hounds") })
  check("psykhanium: /rw_test wave spawns via the ring fallback when there is no main path", #spawned == 3 and ring_calls >= 1, #spawned)
  check("psykhanium: no failure message when the ring worked", recent("not spawning") == nil, tostring(recent("not spawning")))

  Execute.reset(); echoes = {}; ring_calls = 0
  run_wave({ name = "drawn", parts = Groups.parse("3 hounds") }); for _ = 1, 30 do Execute.update(0.2) end
  check("psykhanium: a director-drawn wave never uses the ring", #spawned == 0 and ring_calls == 0)
  local warn = recent("not spawning")
  check("psykhanium: a stuck director wave logs a plain-language warning (once)", warn ~= nil and warn:find("WARN") == 1 and warn:find("Waves need a mission", 1, true) ~= nil, tostring(warn))
  local count = 0; for _, e in ipairs(echoes) do if e:find("not spawning", 1, true) then count = count + 1 end end
  check("psykhanium: the warning is only shown once per wave", count == 1, count)

  ring_fail = true
  Execute.reset(); echoes = {}
  run_wave({ name = "ringfail", test = true, parts = Groups.parse("3 hounds") }); for _ = 1, 30 do Execute.update(0.2) end
  local echo = recent("not spawning")
  check("psykhanium: /rw_test with no walkable ground tells the user in chat", #spawned == 0 and echo ~= nil and echo:find("WARN") == nil and echo:find("no walkable ground") ~= nil, tostring(echo))
  ring_fail = false

  -- a hidden-point failure on a real level is NOT replaced by the ring (never spawn in view)
  cand_reason = "no hidden points near players"
  Execute.reset(); echoes = {}; ring_calls = 0
  run_wave({ name = "nohidden", test = true, parts = Groups.parse("3 hounds") }); for _ = 1, 30 do Execute.update(0.2) end
  check("test wave on a real level: 'no hidden points' still waits, ring not used", #spawned == 0 and ring_calls == 0 and recent("hidden from every player") ~= nil, tostring(recent("not spawning")))
  cand_fail = false

  local saved_path = Managers.state.main_path
  Managers.state.main_path = { is_main_path_ready = function() return false end }
  check("uses_ring: true without a ready main path", Execute.uses_ring() == true)
  Managers.state.main_path = { is_main_path_ready = function() return true end }
  check("uses_ring: false on a normal mission", Execute.uses_ring() == false)
  Managers.state.main_path = saved_path
  Execute.reset(); echoes = {}
end

-- repeats: "5 crushers@2", every 10 s for 35 s -> initial 5, ticks at 10/20/30 -> 3 x 2 more
local function run_timed(def, seconds, step)
  Execute.reset()
  spawned = {}
  Bypass.reset()
  local ok, err = Execute.start_wave(def)
  local timeline = {}
  local t = 0
  while t < seconds do
    Execute.update(step)
    t = t + step
    timeline[#timeline + 1] = { t = t, n = #spawned }
  end
  return ok, err, timeline
end
local function count_at(timeline, sec) local n = 0 for _, p in ipairs(timeline) do if p.t <= sec + 1e-9 then n = p.n end end return n end

local rep_ok, _, tl = run_timed({ name = "t", parts = Groups.parse("5 crushers@2"), rep_every = 10, rep_for = 35 }, 45, 0.25)
check("repeat: wave starts", rep_ok)
check("repeat: initial 5 spawn immediately", count_at(tl, 3) == 5, count_at(tl, 3))
check("repeat: nothing extra before the first tick", count_at(tl, 9) == 5, count_at(tl, 9))
check("repeat: +2 after the first tick (10 s)", count_at(tl, 13) == 7, count_at(tl, 13))
check("repeat: +2 after the second tick (20 s)", count_at(tl, 23) == 9, count_at(tl, 23))
check("repeat: +2 after the third tick (30 s), none after 'for' ends (35 s)", count_at(tl, 33) == 11 and count_at(tl, 44) == 11, count_at(tl, 33) .. "/" .. count_at(tl, 44))
check("repeat: finished job is removed", Execute.status().jobs == 0, Execute.status().jobs)

local _, _, tl2 = run_timed({ name = "t", parts = Groups.parse("0 hounds@3, 2 snipers"), rep_every = 5, rep_for = 10 }, 20, 0.25)
check("repeat: only-repeat group starts at 0 and repeats (2 snipers + 2 ticks x 3 hounds)", count_at(tl2, 3) == 2 and count_at(tl2, 20) == 8, count_at(tl2, 3) .. "/" .. count_at(tl2, 20))
local ok3 = Execute.start_wave({ name = "t", parts = Groups.parse("0 hounds@3"), rep_every = 0, rep_for = 10 })
check("repeat: repeat-only wave with every = 0 is an empty wave", not ok3)
local _, _, tl3 = run_timed({ name = "t", parts = Groups.parse("3 hounds@2"), rep_every = 30, rep_for = 10 }, 40, 0.25)
check("repeat: every longer than 'for' -> no repeat ticks", count_at(tl3, 40) == 3, count_at(tl3, 40))
local _, _, tl4 = run_timed({ name = "t", parts = Groups.parse("3 hounds@2"), rep_every = 10, rep_for = 60 }, 25, 0.25)
Execute.reset()
check("repeat: reset drops a running repeating wave", Execute.status().jobs == 0)
settings.max_alive = 4
-- the engine's ALIVE table says every spawned unit is alive (Bypass.purge would otherwise untrack them)
local saved_alive = ALIVE
ALIVE = setmetatable({}, { __index = function() return true end })
local _, _, tl5 = run_timed({ name = "t", parts = Groups.parse("6 hounds"), rep_every = 10, rep_for = 60 }, 6, 0.25)
check("max_alive still limits spawns of a wave", count_at(tl5, 6) == 4, count_at(tl5, 6))
ALIVE = saved_alive
settings.max_alive = nil

-- "same amount" repeats through the spawner -----------------------------------------------
do
  local _, _, tls = run_timed({ name = "t", parts = Groups.parse("3 crushers@="), rep_every = 10, rep_for = 25 }, 35, 0.25)
  check("same-amount repeat: 3 at once, then +3 at 10 s and +3 at 20 s (9 total), none after 'for'", count_at(tls, 3) == 3 and count_at(tls, 13) == 6 and count_at(tls, 23) == 9 and count_at(tls, 34) == 9, count_at(tls, 3) .. "/" .. count_at(tls, 13) .. "/" .. count_at(tls, 23) .. "/" .. count_at(tls, 34))
  local _, _, tlt = run_timed({ name = "t", parts = Groups.parse("1 mutant@10"), rep_every = 10, rep_for = 25 }, 35, 0.25)
  check("numeric repeat is additive, not cumulative: 1 mutant@10 gives 1, then +10, +10 (21 total)", count_at(tlt, 3) == 1 and count_at(tlt, 13) == 11 and count_at(tlt, 23) == 21, count_at(tlt, 3) .. "/" .. count_at(tlt, 13) .. "/" .. count_at(tlt, 23))
  settings.mult_normal = 200
  local _, _, tlm2 = run_timed({ name = "t", parts = Groups.parse("3 poxwalkers@="), rep_every = 10, rep_for = 10 }, 20, 0.25)
  check("multipliers scale the same-amount repeat too (3 x2 = 6 at once, +6 on the tick)", count_at(tlm2, 3) == 6 and count_at(tlm2, 15) == 12, count_at(tlm2, 3) .. "/" .. count_at(tlm2, 15))
  settings.mult_normal = 100
end

-- purple stimm: the split spawner is created on demand, and skipped safely when it cannot be ---
do
  local PURPLE_CLASS = "scripts/managers/mutator/mutators/mutator_purple_stimmed"
  local created, mutator_table = {}, {}
  local FakeClass = {}
  FakeClass.new = function(self, is_server, delegate, template, nav_world, world, seed)
    local inst = { args = { is_server, delegate, template, nav_world, world, seed } }
    created[#created + 1] = inst
    return inst
  end
  package.loaded[PURPLE_CLASS] = nil
  package.preload[PURPLE_CLASS] = function() return FakeClass end
  Execute.reset(); Bypass.reset()
  local saved_mutator = Managers.state.mutator
  Managers.state.mutator = { _is_server = true, _network_event_delegate = "delegate", _nav_world = "nav", _world = "world", _level_seed = 42, all_activated_mutators = function() return mutator_table end }
  local function buffs_of(u) return table.concat(u.buffs.added, ",") end

  run_wave({ name = "t", parts = Groups.parse("3 crushers[purple_stimm]") })
  local all_purple = #spawned == 3
  for _, u in ipairs(spawned) do if buffs_of(u) ~= "mutator_stimmed_minion_purple" then all_purple = false end end
  check("purple stimm: every unit gets the buff", all_purple, #spawned .. " " .. (spawned[1] and buffs_of(spawned[1]) or ""))
  check("purple stimm: the split spawner was created ONCE and registered under the name the buff looks up", #created == 1 and mutator_table.mutator_stimmed_minions_purple == created[1], #created)
  check("purple stimm: it was built from the mutator manager's own values", created[1].args[1] == true and created[1].args[2] == "delegate" and created[1].args[4] == "nav" and created[1].args[5] == "world" and created[1].args[6] == 42 and type(created[1].args[3]) == "table")
  run_wave({ name = "t", parts = Groups.parse("2 hounds[purple stimm]") })
  check("purple stimm: a second wave reuses the same spawner", #created == 1 and #spawned == 2 and buffs_of(spawned[1]) == "mutator_stimmed_minion_purple")
  for k in pairs(mutator_table) do mutator_table[k] = nil end
  run_wave({ name = "t", parts = Groups.parse("1 hound[purple_stimm]") })
  check("purple stimm: a new mission (fresh mutator manager table) creates it again", #created == 2 and mutator_table.mutator_stimmed_minions_purple == created[2])
  run_wave({ name = "t", parts = Groups.parse("1 crusher[purple_stimm+enraged]") })
  check("purple stimm combines with other modifiers (catalog order: enraged first)", #spawned == 1 and buffs_of(spawned[1]) == "havoc_enraged_enemies,mutator_stimmed_minion_purple", buffs_of(spawned[1]))

  -- failure paths: the buff must NOT be added (it would error when the enemy dies)
  local function skipped(label, expect_text)
    check("purple stimm: " .. label .. " -> no buff, wave still spawns", #spawned == 1 and #spawned[1].buffs.added == 0, #spawned)
    local logged = false
    for _, e in ipairs(echoes) do if e:find("Purple Stimm was skipped") and e:find(expect_text, 1, true) then logged = true end end
    check("purple stimm: " .. label .. " -> reason logged", logged, expect_text)
  end
  Managers.state.mutator = nil
  run_wave({ name = "t", parts = Groups.parse("1 hound[purple_stimm]") })
  skipped("no mutator manager", "no mutator manager")
  Managers.state.mutator = { _is_server = true, _nav_world = "nav", _world = "world", _level_seed = 1, all_activated_mutators = function() return mutator_table end }
  for k in pairs(mutator_table) do mutator_table[k] = nil end
  FakeClass.new = function() error("kaboom") end
  run_wave({ name = "t", parts = Groups.parse("1 hound[purple_stimm]") })
  skipped("constructor raises an error", "kaboom")
  check("purple stimm: nothing registered after a failed constructor", mutator_table.mutator_stimmed_minions_purple == nil)
  package.loaded[PURPLE_CLASS] = nil
  package.preload[PURPLE_CLASS] = function() error("class file missing") end
  run_wave({ name = "t", parts = Groups.parse("1 hound[purple_stimm]") })
  skipped("class cannot be loaded", "could not load")

  Managers.state.mutator = saved_mutator
  package.loaded[PURPLE_CLASS] = nil
  package.preload[PURPLE_CLASS] = nil
end

-- type multipliers (mod options, 0-500 percent) ------------------------------------
local function breed_counts()
  local c = {}
  for _, u in ipairs(spawned) do c[u.breed] = (c[u.breed] or 0) + 1 end
  return c
end
-- runs long enough (40 s of simulated time) for any test wave to finish spawning
local function run_long(def)
  local saved = ALIVE
  ALIVE = setmetatable({}, { __index = function() return true end })
  spawned = {}
  Bypass.reset()
  local ok, err = Execute.start_wave(def)
  for _ = 1, 200 do Execute.update(0.2) end
  ALIVE = saved
  return ok, err
end
local mix = "10 poxwalkers, 4 crushers, 3 hounds, 2 plague ogryn, 1 twin one"
Execute.reset()
run_long({ name = "t", parts = Groups.parse(mix) })
local base = breed_counts()
check("multipliers default to 100 percent (unchanged wave)", base.chaos_poxwalker == 10 and base.chaos_ogryn_executor == 4 and base.chaos_hound == 3 and base.chaos_plague_ogryn == 2 and base.renegade_twin_captain == 1)
settings.mult_normal = 200; settings.mult_boss = 0; settings.mult_special = 500
Execute.reset(); run_long({ name = "t", parts = Groups.parse(mix) })
local c2 = breed_counts()
check("normal 200 percent doubles poxwalkers and elite crushers", c2.chaos_poxwalker == 20 and c2.chaos_ogryn_executor == 8, tostring(c2.chaos_poxwalker) .. "/" .. tostring(c2.chaos_ogryn_executor))
check("boss 0 percent removes plague ogryns and the twin", c2.chaos_plague_ogryn == nil and c2.renegade_twin_captain == nil)
check("special 500 percent gives 5x hounds", c2.chaos_hound == 15, c2.chaos_hound)
settings.mult_normal = 50; settings.mult_boss = 300; settings.mult_special = 100
Execute.reset(); run_long({ name = "t", parts = Groups.parse("5 poxwalkers, 1 crusher, 2 plague ogryn, 1 twin one, 1 twin two") })
local c3 = breed_counts()
check("50 percent rounds DOWN (5 -> 2, 1 -> 0)", c3.chaos_poxwalker == 2 and c3.chaos_ogryn_executor == nil, tostring(c3.chaos_poxwalker) .. "/" .. tostring(c3.chaos_ogryn_executor))
check("boss 300 percent: 2 -> 6 plague ogryns, each twin x3", c3.chaos_plague_ogryn == 6 and c3.renegade_twin_captain == 3 and c3.renegade_twin_captain_two == 3)
settings.mult_normal = 30
Execute.reset(); run_long({ name = "t", parts = Groups.parse("4 poxwalkers, 3 poxwalkers[fire]") })
check("30 percent rounds down: 4 -> 1 (1.2), 3 -> 0 (0.9)", (breed_counts().chaos_poxwalker or 0) == 1, breed_counts().chaos_poxwalker)

-- rounding is always DOWN: the exact cases from the user ------------------------------------
do
  local sa = Execute.scaled_amount
  check("1 unit stays 1 at 190 percent", sa(1, 190) == 1, sa(1, 190))
  check("1 unit becomes 2 at exactly 200 percent", sa(1, 200) == 2, sa(1, 200))
  check("1 unit is still 2 at 299 percent", sa(1, 299) == 2, sa(1, 299))
  check("1 unit becomes 3 at 300 percent, 5 at 500 percent", sa(1, 300) == 3 and sa(1, 500) == 5)
  check("13 units at 150 percent = 19 (19.5 rounded down, not 20)", sa(13, 150) == 19, sa(13, 150))
  check("0 percent removes everything, 100 percent is unchanged", sa(7, 0) == 0 and sa(7, 100) == 7 and sa(1, 0) == 0)
  check("just below a whole number stays below: 3 x 199 = 5 (5.97), 3 x 200 = 6", sa(3, 199) == 5 and sa(3, 200) == 6)
  check("float trap: 20 x 115 percent is exactly 23, 3 x 110 is 3 (3.3), 7 x 130 is 9 (9.1)", sa(20, 115) == 23 and sa(3, 110) == 3 and sa(7, 130) == 9, sa(20, 115) .. "/" .. sa(3, 110) .. "/" .. sa(7, 130))
  local exact = true
  for base = 0, 60 do for percent = 0, 500, 5 do
    local want = (base * percent) // 100
    if sa(base, percent) ~= want then exact = false end
  end end
  check("scaled_amount equals integer floor(base * percent / 100) for every base 0-60 and every slider step", exact)
  -- through the real spawner
  settings.mult_normal = 150; settings.mult_boss, settings.mult_special = 100, 100
  Execute.reset(); run_long({ name = "t", parts = Groups.parse("13 poxwalkers") })
  check("spawner: 13 poxwalkers at 150 percent spawn 19 units", #spawned == 19, #spawned)
  settings.mult_normal = 190
  Execute.reset(); run_long({ name = "t", parts = Groups.parse("1 poxwalker, 1 crusher") })
  check("spawner: 1 unit at 190 percent stays 1 each (2 units total)", #spawned == 2, #spawned)
  settings.mult_normal = 299
  Execute.reset(); run_long({ name = "t", parts = Groups.parse("1 poxwalker") })
  check("spawner: 1 unit at 299 percent is 2 units", #spawned == 2, #spawned)
  settings.mult_normal = 200
  Execute.reset(); run_long({ name = "t", parts = Groups.parse("1 poxwalker") })
  check("spawner: 1 unit at 200 percent is 2 units", #spawned == 2, #spawned)
  settings.mult_normal = 30
end
settings.mult_normal, settings.mult_boss, settings.mult_special = 0, 0, 0
local all_zero_ok, all_zero_err = Execute.start_wave({ name = "t", parts = Groups.parse(mix) })
check("all types at 0 percent -> wave refused with a clear reason", not all_zero_ok and all_zero_err:find("multipliers") ~= nil, all_zero_err)
settings.mult_normal, settings.mult_boss, settings.mult_special = 100, 100, 100
settings.mult_normal = 200
local _, _, tlm = run_timed({ name = "t", parts = Groups.parse("2 poxwalkers@1"), rep_every = 5, rep_for = 10 }, 15, 0.25)
check("repeat ticks are multiplied too (2 x2 initial + 2 ticks x (1 x2))", count_at(tlm, 15) == 8, count_at(tlm, 15))
settings.mult_normal = 100; settings.mult_boss = 200
Execute.reset(); run_long({ name = "t", parts = Groups.parse("3 plague ogryn|chaos spawn") })
check("one_of group uses its first alternative's type (boss x2)", #spawned == 6, #spawned)
settings.mult_boss = 100
-- higher limits (max_per_wave 500, max_alive 1000)
settings.max_per_wave = 500; settings.max_alive = 1000; settings.mult_normal = 500
local saved_alive2 = ALIVE
ALIVE = setmetatable({}, { __index = function() return true end })
Execute.reset(); run_long({ name = "t", parts = Groups.parse("60 poxwalkers, 40 scabs") })
Execute.reset()
local big_ok = Execute.start_wave({ name = "t", parts = Groups.parse("60 poxwalkers, 40 scabs") })
local big_queued = Execute.status().queued
check("a 500 percent wave of 100 units queues 500 (max_per_wave 500)", big_ok and big_queued == 500, big_queued)
settings.max_per_wave = 300
Execute.reset()
Execute.start_wave({ name = "t", parts = Groups.parse("60 poxwalkers, 40 scabs") })
check("max_per_wave still caps a multiplied wave", Execute.status().queued == 300, Execute.status().queued)
Execute.reset()
ALIVE = saved_alive2
settings.max_per_wave, settings.max_alive, settings.mult_normal = nil, nil, nil

-- failed position searches are throttled (memory: the query used to rerun every 0.15 s) ----
do
  Execute.reset(); Bypass.reset()
  cand_fail = true; cand_calls = 0
  spawned = {}
  Execute.start_wave({ name = "t", parts = Groups.parse("6 hounds") })
  for _ = 1, 15 do Execute.update(0.2) end -- 3 s of simulated time
  check("failed hidden-position search is not repeated every feed tick (<= 3 queries in 3 s, was ~20)", cand_calls <= 3 and #spawned == 0, cand_calls)
  cand_fail = false
  for _ = 1, 30 do Execute.update(0.2) end
  check("spawning resumes once positions are found again", #spawned == 6, #spawned)
  Execute.reset(); Bypass.reset()
end

-- Lua memory guard (the game's Lua heap is a hard 1 GB) ---------------------------------
do
  local real_cg = collectgarbage
  local fake_mb, after_gc_mb, full_gcs = 500, 500, 0
  collectgarbage = function(opt)
    if opt == "count" then return fake_mb * 1024 end
    if opt == "collect" then full_gcs = full_gcs + 1; fake_mb = after_gc_mb; return 0 end
    return real_cg(opt)
  end
  settings.heap_guard_mb = nil
  Execute.reset(); Bypass.reset(); spawned = {}
  local ok_low = Execute.start_wave({ name = "t", parts = Groups.parse("4 hounds") })
  for _ = 1, 15 do Execute.update(0.2) end
  check("guard: normal heap (500 MB < 800 guard) spawns normally", ok_low and #spawned == 4 and full_gcs == 0, #spawned .. "/" .. full_gcs)

  Execute.reset(); Bypass.reset(); spawned = {}
  local ok_run = Execute.start_wave({ name = "t", parts = Groups.parse("6 hounds") })
  fake_mb, after_gc_mb, full_gcs = 900, 900, 0
  for _ = 1, 30 do Execute.update(0.2) end
  check("guard: heap above the guard pauses a running wave (units stay queued)", ok_run and #spawned == 0 and Execute.status().queued == 6, #spawned .. "/" .. Execute.status().queued)
  check("guard: full GC is tried, but at most once per 15 s (6 s simulated -> 1)", full_gcs == 1, full_gcs)
  check("guard: status reports heap and pause", Execute.status().heap_paused == true and math.abs(Execute.status().heap_mb - 900) < 0.5 and Execute.status().heap_guard_mb == 800)
  local ok_new, err_new = Execute.start_wave({ name = "t2", parts = Groups.parse("2 hounds") })
  check("guard: a NEW wave is refused with a clear message while over the guard", not ok_new and err_new:find("memory guard") ~= nil, err_new)
  local warned_pause = 0; for _, e in ipairs(echoes) do if e:find("wave spawning paused") then warned_pause = warned_pause + 1 end end
  check("guard: the pause is logged once, not every tick", warned_pause == 1, warned_pause)
  fake_mb, after_gc_mb = 600, 600
  for _ = 1, 30 do Execute.update(0.2) end
  check("guard: spawning resumes when memory drops", #spawned == 6 and Execute.status().heap_paused == false, #spawned)

  -- a forced full GC that frees enough lets spawning continue at once
  Execute.reset(); Bypass.reset(); spawned = {}; full_gcs = 0
  fake_mb, after_gc_mb = 900, 500
  Execute.start_wave({ name = "t", parts = Groups.parse("4 hounds") })
  for _ = 1, 30 do Execute.update(0.2) end
  check("guard: if a full GC brings the heap under the guard the wave is not blocked", #spawned == 4 and full_gcs >= 1, #spawned .. "/" .. full_gcs)

  -- the guard is configurable
  settings.heap_guard_mb = 1000
  Execute.reset(); Bypass.reset(); spawned = {}
  fake_mb, after_gc_mb = 900, 900
  local ok_hi = Execute.start_wave({ name = "t", parts = Groups.parse("2 hounds") })
  for _ = 1, 15 do Execute.update(0.2) end
  check("guard: raising it to 1000 MB lets a 900 MB heap spawn", ok_hi and #spawned == 2, #spawned)
  settings.heap_guard_mb = nil
  collectgarbage = real_cg
  Execute.reset(); Bypass.reset()
end

-- retired hooks (after a mod reload) act as pass-throughs -----------------------------------
do
  local saved_hooks = hooks
  hooks = {}
  local B2 = load("spawn/budget_bypass")
  B2.install()
  local calls = {}
  local orig = function(self, unit) calls[#calls + 1] = unit end
  local ps = { _should_send_aggro_event = true }
  B2.track("a"); B2.track("b")
  check("hooks: a live instance counts tracked units", hooks["MinionSpawnManager.num_spawned_minions"](function() return 10 end, {}) == 8)
  B2.retire()
  check("retire: tracked set is released and the flag is set", B2.count() == 0 and B2.dead == true)
  hooks["PacingManager.add_aggroed_minion"](orig, ps, "a")
  check("retire: add_aggroed_minion passes straight through (pacing sees the unit)", #calls == 1 and calls[1] == "a")
  check("retire: counters are the untouched engine values", hooks["MinionSpawnManager.num_spawned_minions"](function() return 10 end, {}) == 10 and hooks["MinionSpawnManager.total_allocated_num_enemies"](function() return 12 end, {}) == 12)
  B2.spawning = true
  hooks["PacingManager.add_aggroed_minion"](orig, ps, "c")
  check("retire: the 'spawning' flag no longer diverts units", #calls == 2 and B2.count() == 0)
  hooks = saved_hooks
end

-- options data: limits and the three multiplier sliders ----------------------------------
do
  local data = dofile(ROOT .. "/RealmsWaves_data.lua")
  local function find(id, widgets)
    for _, w in ipairs(widgets) do
      if w.setting_id == id then return w end
      if w.sub_widgets then local r = find(id, w.sub_widgets) if r then return r end end
    end
  end
  local all = data.options.widgets
  local mp, ma = find("max_per_wave", all), find("max_alive", all)
  check("options: max enemies per wave 1-500, max alive 10-1000", mp.range[1] == 1 and mp.range[2] == 500 and ma.range[1] == 10 and ma.range[2] == 1000, mp.range[2] .. "/" .. ma.range[2])
  check("options: defaults unchanged (80 per wave, 120 alive)", mp.default_value == 80 and ma.default_value == 120)
  local ok = true
  for _, id in ipairs({ "mult_normal", "mult_boss", "mult_special" }) do
    local w = find(id, all)
    if not (w and w.type == "numeric" and w.range[1] == 0 and w.range[2] == 500 and w.default_value == 100) then ok = false end
  end
  check("options: three multiplier sliders, 0-500, default 100", ok)
  check("options: multiplier sliders sit in their own group", find("group_multipliers", all) ~= nil and #find("group_multipliers", all).sub_widgets == 3)
  local loc = dofile(ROOT .. "/RealmsWaves_localization.lua")
  local bare = {}
  for key, entry in pairs(loc) do
    local text = entry.en
    -- walk the string: "%%", "%s" and "%d" are valid format sequences; any other "%" breaks DMF's string.format
    local i, bad = 1, false
    while i <= #text do
      if text:sub(i, i) == "%" then
        local nxt = text:sub(i + 1, i + 1)
        if nxt == "%" or nxt == "s" or nxt == "d" then i = i + 2 else bad = true; break end
      else
        i = i + 1
      end
    end
    if bad then bare[#bare + 1] = key end
  end
  check("localization: no stray % in any string (DMF formats every string)", #bare == 0, table.concat(bare, ","))
  check("localization: 'count' words are now 'weight'", loc.col_count.en == "Weight" and loc.popup_count_title.en == "Weight of %s")
  check("localization: multiplier and search strings exist", loc.mult_normal and loc.mult_boss and loc.mult_special and loc.group_multipliers and loc.btn_search and loc.popup_search_hint and loc.picker_status and loc.unit_percent.en == "pct")
  -- DMF option rows: the title column holds about 27 characters on one line, the value column about 8
  -- (value + unit, e.g. "1000 pct"); longer text wraps into several lines and overlaps the next row.
  local titles = { "initial_delay", "interval_min", "interval_max", "vote_duration", "ballot_size", "novote_fallback", "max_per_wave", "max_alive", "heap_guard_mb", "min_distance", "max_distance", "monster_min_distance", "monster_max_distance", "mult_normal", "mult_boss", "mult_special", "open_editor_bind", "vote_1_bind", "vote_2_bind", "vote_3_bind", "vote_4_bind", "vote_5_bind", "hud_enabled", "hud_show_percent", "colour_enemies", "colour_spidey", "interval_random", "debug", "fallback_random", "fallback_skip" }
  local long = {}
  for _, id in ipairs(titles) do
    local text = loc[id] and loc[id].en
    if not text then long[#long + 1] = id .. "(missing)" elseif #text > 27 then long[#long + 1] = id .. "(" .. #text .. ")" end
  end
  check("localization: every option title fits one line (<= 27 characters)", #long == 0, table.concat(long, ","))
  local wide = {}
  for id, entry in pairs(loc) do
    if id:find("^unit_") and #entry.en > 3 then wide[#wide + 1] = id .. "=" .. entry.en end
  end
  check("localization: unit labels are short (<= 3 characters) so value and unit stay on one line", #wide == 0, table.concat(wide, ","))
  -- text next to the detail-screen steppers: node width minus 440 px, about 10 px per character
  local fits = { extra_dist_auto = 10, extra_dist_own = 10, extra_timer_off = 14, extra_timer_on = 14, extra_timer_wave = 42, extra_timer_ignored = 36, val_off = 4, val_auto = 4, share_timer = 12 }
  local cramped = {}
  for id, limit in pairs(fits) do if not loc[id] or #(loc[id].en:gsub("%%s", "00")) > limit then cramped[#cramped + 1] = id end end
  check("localization: texts beside the steppers fit their space", #cramped == 0, table.concat(cramped, ","))
end

-- Positions.spread with stubbed nav queries -----------------------------------------
do
  local V = {}
  V.__add = function(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, V) end
  local saved_vector3 = Vector3
  Vector3 = function(x, y, z) return setmetatable({ x = x, y = y, z = z }, V) end
  local nav = { snap_ok = true, ray_ok = true, calls = 0 }
  nav.position_on_mesh = function(world, pos, above, below) nav.calls = nav.calls + 1; if nav.snap_ok then return Vector3(pos.x, pos.y, pos.z + 0.5) end return nil end
  nav.ray_can_go = function(world, a, b, logic, above, below) return nav.ray_ok end
  package.preload["scripts/managers/main_path/utilities/spawn_point_queries"] = function() return {} end
  package.preload["scripts/utilities/nav_queries"] = function() return nav end
  local saved_nav_mesh = Managers.state.nav_mesh
  Managers.state.nav_mesh = { nav_world = function() return "world" end }
  local Pos = load("spawn/positions")
  local origin = Vector3(100, 200, 10)

  check("spread: radius 0 returns the same point", Pos.spread(origin, 0) == origin and Pos.spread(origin, nil) == origin)
  local max_r, moved, all_snapped = 0, 0, true
  for _ = 1, 500 do
    local p = Pos.spread(origin, 5)
    local d = math.sqrt((p.x - 100) ^ 2 + (p.y - 200) ^ 2)
    if d > max_r then max_r = d end
    if d > 0.01 then moved = moved + 1 end
    if p.z ~= 10.5 then all_snapped = false end
  end
  check("spread: points stay inside the radius and are nav-snapped", max_r <= 5.0001 and all_snapped and moved == 500, string.format("max %.2f moved %d", max_r, moved))
  local inner = 0
  for _ = 1, 2000 do local p = Pos.spread(origin, 10); if math.sqrt((p.x - 100) ^ 2 + (p.y - 200) ^ 2) < 5 then inner = inner + 1 end end
  check("spread: uniform over the disc (about a quarter of points within half the radius)", inner > 400 and inner < 600, inner)
  nav.snap_ok = false
  check("spread: falls back to the original point when nothing snaps", Pos.spread(origin, 5) == origin)
  nav.snap_ok = true; nav.ray_ok = false
  check("spread: falls back when a wall blocks the straight line", Pos.spread(origin, 5) == origin)
  nav.ray_ok = true
  Managers.state.nav_mesh = nil
  check("spread: no nav mesh -> original point", Pos.spread(origin, 5) == origin)
  Managers.state.nav_mesh = saved_nav_mesh
  Vector3 = saved_vector3
end

Managers.state.minion_spawn, Managers.state.extension, Managers.state.game_mode = saved_state.minion_spawn, saved_state.extension, saved_state.game_mode
Managers.time = saved_time
Bypass.reset()

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

