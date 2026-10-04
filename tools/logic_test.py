import sys, os
from lua_test_runtime import LuaRuntime

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "scripts", "mods", "RealmsWaves")
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
mod.io_dofile = function(self, path) return dofile(ROOT .. "/../../../" .. path:gsub("^RealmsWaves/", "") .. ".lua") end
get_mod = function(name) return mod end

local is_server = true
local mission_name = "coop_complete_objective"
Managers = {
  connection = { host = function() return "host_peer" end },
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
check("display names: Packmaster, Ranged Twin (plasma pistol) and Melee Twin (power sword)", Groups.display_name("chaos_ogryn_houndmaster") == "Packmaster" and Groups.display_name("renegade_twin_captain") == "Ranged Twin" and Groups.display_name("renegade_twin_captain_two") == "Melee Twin", Groups.display_name("renegade_twin_captain"))
check("the new twin names and every old name parse to the right breed", (function() local function b(name) local p = Groups.parse("1 " .. name); return p and p[1].breed end return b("ranged twin") == "renegade_twin_captain" and b("melee twin") == "renegade_twin_captain_two" and b("twin captain one") == "renegade_twin_captain" and b("twin captain two") == "renegade_twin_captain_two" and b("male twin") == "renegade_twin_captain" and b("female twin") == "renegade_twin_captain_two" end)())
check("both twins are in the picker list", (function() local n = 0 for _, b in ipairs(Groups.breed_list()) do if b:find("^renegade_twin_captain") then n = n + 1 end end return n == 2 end)())
check("recipe roundtrip for twins/packmaster", Groups.to_recipe(Groups.parse("1 twin one, 2 packmaster")) == "1 ranged twin, 2 packmaster")

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

-- factions and the shelf (docs/08) ----------------------------------------------------------------------------------------
do
  local dregs, scabs, chaos, other = 0, 0, 0, {}
  for _, b in ipairs(Groups.breed_list()) do
    local f = Groups.faction(b)
    if b:find("^cultist_") and f == "dreg" then dregs = dregs + 1
    elseif b:find("^renegade_") and f == "scab" then scabs = scabs + 1
    elseif b:find("^chaos_") and f == nil then chaos = chaos + 1
    else other[#other + 1] = b end
  end
  check("factions: every cultist breed is a Dreg, every renegade a Scab, every Chaos unit neither", #other == 0 and dregs >= 9 and scabs >= 15 and chaos >= 12 and dregs + scabs + chaos == #Groups.breed_list(), table.concat(other, ","))
  check("factions: no breed, nil and junk have none", Groups.faction(nil) == nil and Groups.faction("") == nil and Groups.faction(42) == nil and Groups.faction("whatever") == nil)
  check("faction word: Gunner is the Scab one and says so; a name that says it already adds nothing; Tox Flamer says Dreg; Chaos units say nothing", Groups.faction_suffix("renegade_gunner") == "Scab" and Groups.faction_suffix("cultist_gunner") == nil and Groups.faction_suffix("renegade_melee") == nil and Groups.faction_suffix("cultist_melee") == nil and Groups.faction_suffix("cultist_flamer") == "Dreg" and Groups.faction_suffix("renegade_flamer") == "Scab" and Groups.faction_suffix("cultist_berzerker") == "Dreg" and Groups.faction_suffix("renegade_berzerker") == nil and Groups.faction_suffix("chaos_hound") == nil and Groups.faction_suffix("cultist_mutant") == "Dreg")
  check("factions: the faction word never doubles a faction already in the name (Scab Rager, Dreg Shocktrooper)", (function() for _, b in ipairs(Groups.breed_list()) do local n = Groups.display_name(b) if Groups.faction_suffix(b) and (n:find("Dreg") or n:find("Scab")) then return false end end return true end)())

  -- the shelf
  local seen, problems, count = {}, {}, 0
  local KIND_OF_GROUP = { fodder = "normal", elite = "elite", special = "special", boss = "boss" }
  for _, group in ipairs(Groups.SHELF) do
    for _, entry in ipairs(group.entries) do
      count = count + 1
      local list = entry.breed and { entry.breed } or { entry.dreg, entry.scab }
      if not entry.breed and (not entry.dreg or not entry.scab or not entry.label) then problems[#problems + 1] = "incomplete pair " .. tostring(entry.label) end
      for _, b in ipairs(list) do
        if not Groups.is_known(b) then problems[#problems + 1] = "unknown " .. tostring(b)
        elseif Groups.kind(b) ~= KIND_OF_GROUP[group.id] then problems[#problems + 1] = b .. " is " .. Groups.kind(b) .. " in " .. group.id end
        if seen[b] then problems[#problems + 1] = "twice " .. b end
        seen[b] = true
      end
      if not entry.breed and (Groups.faction(entry.dreg) ~= "dreg" or Groups.faction(entry.scab) ~= "scab") then problems[#problems + 1] = "faction mismatch " .. entry.label end
    end
  end
  check("shelf: four groups (fodder, elite, special, boss), every breed known, in the group of its kind, none twice, each pair a Dreg and a Scab", #Groups.SHELF == 4 and #problems == 0 and count == 30, table.concat(problems, ", ") .. " / " .. count)
  check("shelf: the Packmaster (the houndmaster) is among the bosses", seen.chaos_ogryn_houndmaster == true and Groups.SHELF[4].entries[5].breed == "chaos_ogryn_houndmaster")
  check("shelf: both vanguards are fodder, as a Dreg / Scab pair", (function() for _, e in ipairs(Groups.SHELF[1].entries) do if e.dreg == "cultist_vanguard" and e.scab == "renegade_vanguard" then return true end end return false end)())
  check("shelf: the vanguards count as normal enemies, not elites, for the threat and the multipliers", Groups.kind("cultist_vanguard") == "normal" and Groups.kind("renegade_vanguard") == "normal" and Groups.category("renegade_vanguard") == "normal")
  local gunner = Groups.SHELF[2].entries[2]
  check("shelf: a role both factions have adds the Dreg or the Scab one by the switch, a unit with one faction ignores it", Groups.shelf_breed(gunner, "dreg") == "cultist_gunner" and Groups.shelf_breed(gunner, "scab") == "renegade_gunner" and Groups.shelf_breed(Groups.SHELF[2].entries[4], "dreg") == "renegade_executor" and Groups.shelf_breed(Groups.SHELF[1].entries[1], "scab") == "chaos_poxwalker")
  check("shelf: the tag a chip shows: the switch for a pair, the unit's own for a Mauler (Scab) or a Mutant (Dreg), none for a Poxwalker", Groups.shelf_faction(gunner, "dreg") == "dreg" and Groups.shelf_faction(gunner, "scab") == "scab" and Groups.shelf_faction(Groups.SHELF[2].entries[4], "dreg") == "scab" and Groups.shelf_faction(Groups.SHELF[3].entries[1], "scab") == "dreg" and Groups.shelf_faction(Groups.SHELF[1].entries[1], "dreg") == nil)
  check("shelf: labels: the role for a pair, the enemy's own name otherwise", Groups.shelf_label(gunner) == "Gunner" and Groups.shelf_label(Groups.SHELF[2].entries[4]) == "Mauler" and Groups.shelf_label(Groups.SHELF[4].entries[5]) == "Packmaster")
  check("shelf: 'houndmaster' still finds the Packmaster (the old names parse)", Groups.parse("1 houndmaster")[1].breed == "chaos_ogryn_houndmaster")
end

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

-- Reset face (the Mirror): only the face goes back, the enemies, the chance and the rest stay
do
  local st = {}
  local g, s = function(id) return st[id] end, function(id, v) st[id] = v end
  s("wave_def_wave_small", "The Fool\t3 hounds"); s("pct_wave_small", 9); s("su_wave_small", "rage"); s("th_wave_small", 4); s("wh_wave_small", "Mine"); s("cl_wave_small", "vial"); s("cd_wave_small", 300)
  Events.reset_face(s, "wave_small")
  local w = Events.get("wave_small", g, Groups)
  check("reset face: suit, threat, whisper, look and cooldown go back to the card's defaults (The Fool: swarm, 120 s)", w.suit == "swarm" and w.threat_override == 0 and st.wh_wave_small == "" and st.cl_wave_small == "" and w.cooldown == 120, tostring(w.suit) .. "/" .. tostring(w.cooldown))
  check("reset face: the enemies, the chance and the name stay", st.wave_def_wave_small == "The Fool\t3 hounds" and st.pct_wave_small == 9 and w.name == "The Fool")
  s("wave_def_custom_1", "Mine\t2 hounds"); s("su_custom_1", "rage"); s("cd_custom_1", 400); s("th_custom_1", 2)
  Events.reset_face(s, "custom_1")
  check("reset face: a custom card goes back to plague (or its suggestion) and the default cooldown option; its enemies stay", st.su_custom_1 == "" and st.cd_custom_1 == nil and st.th_custom_1 == 0 and st.wave_def_custom_1 == "Mine\t2 hounds")
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
local lo, hi = math.huge, 0; for _, e in ipairs(Events.STANDARD) do lo = math.min(lo, e.default_pct); hi = math.max(hi, e.default_pct) end
check("default weights are on the 1-10 scale of the weight pips", lo >= 1 and hi <= 10, lo .. ".." .. hi)
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
check("standard override", after.name == "Tiny Rush" and #after.parts == 1 and after.modified and not after.is_custom and before.name == "The Fool")
Events.reset(set, "wave_small")
after = Events.get("wave_small", get, Groups)
check("standard reset", after.name == "The Fool" and #after.parts == 4 and not after.modified and after.enabled and after.pct == 5, after.name)

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
  update = function() end, reset = function() end, cancel = function() end,
  status = function() return { tracked = 0, queued = 0, jobs = 0 } end,
}
local sent = {}
local Protocol = {
  PROTO = 2, VERSION = "2.0.0",
  is_available = function() return true end,
  send_state = function(state, rcpt) sent[#sent+1] = { state = state, rcpt = rcpt } return true end,
  send_hello = function() sent.hello = (sent.hello or 0) + 1 end,
  send_welcome = function(peer, ok) sent.welcome = { peer, ok } end,
  send_vote = function(b, o) sent.vote = { b, o } end,
  send_waves = function(text) sent.waves = text; sent.waves_count = (sent.waves_count or 0) + 1; return true end,
}
local Director = load("core/director")
local PresetsMod = load("catalog/presets")
local CardsMod = load("catalog/cards")
Director.init({ events = Events, groups = Groups, protocol = Protocol, execute = Execute, votes = Votes, positions = Positions, presets = PresetsMod, cards = CardsMod })

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
  local friend_text = peer_text({ w("custom_1", "Friend Special", "4 hounds", 500), w("wave_small", "The Fool", "8 poxwalker, 6 scab, 4 dreg, 2 rifleman", 5) })
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
  check("pool: a wave identical to one of the host's counts once (the host's wins)", names["The Fool"] == 1, tostring(names["The Fool"]))
  -- name collisions get a suffix
  local clash = Events.build_pool(function(id) return settings[id] end, Groups, { { key = "x:1", name = "The Fool", parts = Groups.parse("5 mutants"), enabled = true, pct = 5, cooldown = 0, spread = 3, rep_every = 10, rep_for = 60, dmin = 0, dmax = 0 } })
  local suffixed; for _, e in ipairs(clash) do if e.key == "x:1" then suffixed = e.name end end
  check("pool: a friend's wave with an already used name gets '(2)'", suffixed == "The Fool (2)", tostring(suffixed))
  -- the spawn definition of a friend's wave is complete
  local friend; for _, e in ipairs(pool) do if e.name == "Friend Special" then friend = e end end
  check("pool: the friend's wave carries a full spawn definition (its chance of 500 counts as the most a chance can be, 10)", friend and friend.def.parts and friend.def.parts[1].breed == "chaos_hound" and friend.def.parts[1].count == 4 and friend.def.cooldown == 0 and friend.def.spread == 3 and friend.raw == 10)

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

-- the card's sound is an ALERT (2026-10-04): it plays the moment the card is picked and the wave spawns when it ends; NIGHTMARE is
-- played once per game ---------------------------------------------------------------------------------------------------------------
do
  local keys = Events.keys()
  local Snd = load("catalog/sounds")
  local function only(list) for _, k in ipairs(keys) do settings["on_" .. k] = false end for _, e in ipairs(list) do settings["on_" .. e[1]] = true; settings["pct_" .. e[1]] = 5; settings["cd_" .. e[1]] = 0 end end
  local function start()
    started_waves = {}; started_defs = {}
    Director.on_exit_gameplay(); Director.on_enter_gameplay(); Director.on_mission_started(); Director.update(0.01)
  end
  local function skip() Director.skip(); Director.update(0.01) end
  local alerts, job = {}, nil
  Director.effects = { snapshot = function() return nil end, receive = function() end, alert = function(text) alerts[#alerts + 1] = text; if Snd.has(text) then job = { done = false }; return job end return nil end }
  is_server = true
  settings.tarot_cards = 1; settings.tarot_seconds = 10; settings.interval_min = 100; settings.interval_max = 100; settings.interval_random = false; settings.initial_delay = 0
  only({ { "wave_medium" } })
  local event = Snd.EVENTS[100]
  settings.snd_wave_medium = event
  start(); skip()
  check("alert: the picked card's sound plays at once and its wave waits for it", alerts[#alerts] == event and #started_waves == 0 and Director.held_count() == 1 and Director.view().last ~= nil)
  Director.update(5)
  check("alert: while the sound plays the wave still waits", #started_waves == 0 and Director.held_count() == 1)
  job.done = true; Director.update(0.1)
  check("alert: the wave spawns when the sound has ended", #started_waves == 1 and Director.held_count() == 0)
  Director.update(31); skip(); Director.update(19) -- (a card rests at least 30 s after it is drawn)
  check("alert: a sound that never ends holds its wave at most 20 seconds", #started_waves == 1 and Director.held_count() == 1)
  Director.update(1.5)
  check("alert: ...then the wave goes anyway", #started_waves == 2 and Director.held_count() == 0)
  Director.update(31); skip(); Director.pause(true); job.done = true; Director.update(2)
  check("alert: a paused game keeps the wave held even when the sound is over", #started_waves == 2 and Director.held_count() == 1)
  Director.pause(false); Director.update(0.1)
  check("alert: ...and lets it go on resume", #started_waves == 3)
  Director.update(31); skip()
  check("alert: stop drops a held wave (it never spawns)", Director.held_count() == 1 and Director.stop() == true and Director.held_count() == 0 and (function() Director.update(30); return #started_waves == 3 end)())
  settings.snd_wave_medium = nil
  start(); skip()
  check("alert: a card without a sound spawns at once", #started_waves == 1 and Director.held_count() == 0)

  -- Nightmare: one card per game; all its cards leave the draw once one went out, until the next mission
  only({ { "wave_medium" }, { "wave_small" } })
  settings.su_wave_medium = "nightmare"; settings.su_wave_small = "swarm"
  settings.on_wave_small = false
  start(); skip()
  check("nightmare: a Nightmare card can be drawn and its wave goes out", started_waves[1] ~= nil and Director.spent_once("nightmare") == true)
  skip(); Director.update(0.01)
  check("nightmare: with only Nightmare cards in the deck nothing else is dealt after it (the draw is empty)", #started_waves == 1)
  settings.on_wave_small = true
  for _ = 1, 6 do Director.update(31); skip() end
  local only_swarm = true
  for i = 2, #started_defs do if started_defs[i].suit == "nightmare" then only_swarm = false end end
  check("nightmare: the other cards keep coming, never a Nightmare again this game", #started_waves >= 4 and only_swarm, #started_waves)
  start()
  check("nightmare: the next mission has its Nightmare back", Director.spent_once("nightmare") == false)
  settings.mode = "random"; settings.on_wave_small = false; start(); Director.update(150)
  check("nightmare: the random mode fires it once too, then marks it spent", #started_waves == 1 and Director.spent_once("nightmare") == true)
  Director.update(150)
  check("nightmare: ...and finds nothing else to send", #started_waves == 1)
  settings.mode = nil
  for _, k in ipairs(keys) do settings["on_" .. k] = nil; settings["pct_" .. k] = nil; settings["cd_" .. k] = nil end
  settings.su_wave_medium, settings.su_wave_small = nil, nil
  settings.tarot_cards, settings.tarot_seconds, settings.interval_min, settings.interval_max, settings.interval_random, settings.initial_delay = nil, nil, nil, nil, nil, nil
  Director.effects = nil
  Director.on_exit_gameplay(); started_waves = {}; started_defs = {}
end

-- /rw_test plays the card's sound first; /rw_drawtest and /rw_fulltest stage a draw (2026-10-04) -----------------------------------
do
  local keys = Events.keys()
  local Snd = load("catalog/sounds")
  local function only(list) for _, k in ipairs(keys) do settings["on_" .. k] = false end for _, e in ipairs(list) do settings["on_" .. e] = true; settings["pct_" .. e] = 5; settings["cd_" .. e] = 0 end end
  local function start()
    started_waves = {}; started_defs = {}
    Director.on_exit_gameplay(); Director.on_enter_gameplay(); Director.on_mission_started(); Director.update(0.01)
  end
  local alerts, job = {}, nil
  Director.effects = { snapshot = function() return nil end, receive = function() end, alert = function(text) alerts[#alerts + 1] = text; if Snd.has(text) then job = { done = false }; return job end return nil end }
  is_server = true
  settings.tarot_cards = 3; settings.tarot_seconds = 10; settings.interval_min = 100; settings.interval_max = 100; settings.interval_random = false; settings.initial_delay = 0
  only({ "wave_small", "wave_medium", "wave_large", "wave_huge" })
  local event = Snd.EVENTS[100]
  settings.snd_wave_medium = event; settings.su_wave_medium = "nightmare"
  start()

  -- /rw_test: the sound first, then the wave; a test spends no once-per-game suit and is released even when the cycle is stopped
  local ok, note = Director.fire_now("wave_medium")
  check("rw_test: the card's sound plays first and its wave waits for it", ok and alerts[#alerts] == event and #started_waves == 0 and Director.held_count() == 1)
  job.done = true; Director.update(0.1)
  check("rw_test: the wave spawns when the sound ends; a test does not use up Nightmare", #started_waves == 1 and Director.spent_once("nightmare") == false)
  local ok2, note2 = Director.fire_now("wave_medium", { close = true })
  check("rw_test_close: the same, and it says it waits for the sound", ok2 and tostring(note2):find("when its sound ends", 1, true) ~= nil and #started_waves == 1)
  Director.pause(true); job.done = true; Director.update(0.1)
  check("rw_test: a test wave goes out even while the waves are paused", #started_waves == 2)
  Director.pause(false)

  -- /rw_drawtest: three cards, the named one picked 3 s later; nothing sent, nothing heard, no cooldown
  started_waves = {}; local alerts_before = #alerts
  Director.update(10)
  local remaining_before = Director.view().remaining
  local okd, name = Director.stage_draw("wave_medium", false)
  local v = Director.view()
  check("drawtest: a hand of three is dealt with the named card in it", okd and v.hand ~= nil and #v.hand == 3 and v.phase == "hand", tostring(name))
  local named_in_hand = false
  for _, c in ipairs(v.hand or {}) do if c.key == "wave_medium" then named_in_hand = true end end
  check("drawtest: the named card is one of them, and the winner", named_in_hand and v.hand[v.win].key == "wave_medium")
  check("drawtest: a second staged draw waits for the first", not Director.stage_draw("wave_small", false))
  Director.update(1.5)
  check("drawtest: not picked before 3 s", Director.view().drawn ~= true)
  Director.update(1.6)
  v = Director.view()
  check("drawtest: after 3 s it is drawn as in play (the Spread shows it, the Last Card holds it)", v.drawn == true and v.hand[v.win].key == "wave_medium" and v.last ~= nil and v.last.key == "wave_medium")
  check("drawtest: no sound, no wave, no cooldown, Nightmare not spent", #alerts == alerts_before and #started_waves == 0 and Director.held_count() == 0 and (Director.cooldown_map().wave_medium or 0) == 0 and Director.spent_once("nightmare") == false)
  check("drawtest: the countdown goes on where it was", math.abs(Director.view().remaining - remaining_before) < 4, Director.view().remaining .. " vs " .. remaining_before)

  -- /rw_fulltest: the same draw, then the sound and the wave
  Director.update(5)
  local okf = Director.stage_draw("wave_medium", true)
  Director.update(3.1)
  check("fulltest: picked after 3 s, its sound plays at once and the wave waits for it", okf and alerts[#alerts] == event and #started_waves == 0 and Director.held_count() == 1 and Director.view().last.key == "wave_medium")
  job.done = true; Director.update(0.1)
  check("fulltest: then the wave spawns; still no cooldown and no Nightmare spent", #started_waves == 1 and (Director.cooldown_map().wave_medium or 0) == 0 and Director.spent_once("nightmare") == false)

  check("stage: an unknown card is refused with the finder's message", not Director.stage_draw("no such card at all", false))
  Director.pause(true)
  check("stage: refused while the waves are paused", not Director.stage_draw("wave_medium", false))
  Director.pause(false)
  is_server = false
  check("stage: only the host can stage a draw", not Director.stage_draw("wave_medium", false))
  is_server = true
  Director.stop()
  check("stage: refused while the waves are stopped", not Director.stage_draw("wave_medium", false))

  -- in the vote mode the staged draw shows, then the vote goes on with its own state
  settings.mode = "vote"; start(); Director.update(1)
  local ballot = Director.view().ballot_id
  check("stage (vote mode): the draw shows as a hand", Director.stage_draw("wave_medium", false) and Director.view().mode == "tarot")
  Director.update(3.1)
  check("stage (vote mode): after the pick the vote's own state comes back", Director.view().mode == "vote")
  settings.mode = nil

  for _, k in ipairs(keys) do settings["on_" .. k] = nil; settings["pct_" .. k] = nil; settings["cd_" .. k] = nil end
  settings.snd_wave_medium, settings.su_wave_medium = nil, nil
  settings.tarot_cards, settings.tarot_seconds, settings.interval_min, settings.interval_max, settings.interval_random, settings.initial_delay = nil, nil, nil, nil, nil, nil
  Director.effects = nil
  Director.on_exit_gameplay(); started_waves = {}; started_defs = {}
end

-- the last fulfilled card: remembered by the host when a wave of the cycle goes out, synced to the clients, shown by the HUD window -------
do
  local keys = Events.keys()
  local function only(list) for _, k in ipairs(keys) do settings["on_" .. k] = false end for _, e in ipairs(list) do settings["on_" .. e[1]] = true; settings["pct_" .. e[1]] = e[2] or 5; settings["cd_" .. e[1]] = e[3] or 0 end end
  local function clean()
    for _, k in ipairs(keys) do settings["on_" .. k] = nil; settings["pct_" .. k] = nil; settings["cd_" .. k] = nil end
    settings.mode, settings.tarot_cards, settings.tarot_seconds, settings.interval_min, settings.interval_max, settings.interval_random, settings.initial_delay = nil, nil, nil, nil, nil, nil, nil
  end
  local function start()
    started_waves = {}; started_defs = {}
    Director.on_exit_gameplay(); Director.on_enter_gameplay(); Director.on_mission_started(); Director.update(0.01)
    return Director.view()
  end
  local function skip() Director.skip(); Director.update(0.01) end -- /rw_skip sets the countdown to zero, the pick happens on the next tick
  is_server = true
  settings.tarot_cards = 1; settings.tarot_seconds = 10; settings.interval_min = 100; settings.interval_max = 100; settings.interval_random = false; settings.initial_delay = 0
  only({ { "wave_medium", 5, 0 } })
  local v = start()
  check("last card: before the first card goes out there is none (and the age is 0)", v.last == nil and v.last_seq == 0 and v.last_age == 0)
  skip()
  v = Director.view()
  local first_card = v.last
  check("last card: the card whose wave went out is the last one (its name, suit, threat, a first number, age 0)", first_card ~= nil and first_card.name == started_waves[#started_waves] and first_card.key == "wave_medium" and first_card.suit == "swarm" and first_card.threat >= 1 and first_card.threat <= 5 and #first_card.breeds >= 1 and v.last_seq == 1 and v.last_age == 0, started_waves[#started_waves])
  Director.update(30)
  check("last card: its age counts the played seconds", math.abs(Director.view().last_age - 30) < 0.01 and Director.view().last == first_card, Director.view().last_age)
  Director.pause(true)
  Director.update(25)
  check("last card: a paused game does not age it", math.abs(Director.view().last_age - 30) < 0.01)
  Director.pause(false)
  skip()
  v = Director.view()
  check("last card: the next card replaces it (a new number, a new table, age 0 again)", v.last_seq == 2 and v.last ~= first_card and v.last_age == 0 and v.last.key == "wave_medium")

  -- a wave that did not start is not a fulfilled card
  local real_start = Execute.start_wave
  Execute.start_wave = function() return false, "pending-wave budget is full" end
  skip()
  check("last card: a wave that could not start does not change it", Director.view().last_seq == 2)
  Execute.start_wave = real_start

  -- not a test wave, not a fixed timer
  local seq = Director.view().last_seq
  Director.fire_now("wave_small")
  Director.fire_now("wave_small", { close = true })
  check("last card: /rw_test and /rw_test_close do not change it", Director.view().last_seq == seq)

  -- sync: the host's state carries it, a client shows it
  Director.update(2)
  local state
  for i = #sent, 1, -1 do if sent[i].state and sent[i].state.lc then state = sent[i].state break end end
  check("sync: the state carries the last card (name, suit, a number, its age in played seconds)", state ~= nil and state.lc.n == Director.view().last.name and state.lc.s == "swarm" and state.ls == seq and type(state.la) == "number" and state.la >= 2, state and tostring(state.la))
  local wire = { lc = state.lc, la = state.la, ls = state.ls }
  -- stop while the last card is visible; deliver the final snapshot to a client
  check("last card: the host stops and hides its card", Director.stop() == true and Director.view().last == nil)
  local stopped_wire = sent[#sent].state
  is_server = false
  Director.on_state("host_peer", stopped_wire)
  check("last card: the client also hides the last card after the host stops", Director.view().last == nil)
  stopped_wire.lc, stopped_wire.la, stopped_wire.ls = wire.lc, wire.la, wire.ls
  Director.on_state("host_peer", stopped_wire)
  check("last card: off snapshots from older hosts cannot retain a last card", Director.view().last == nil)
  is_server = true

  is_server = false
  Director.on_exit_gameplay(); Director.on_enter_gameplay()
  Director.on_state("host_peer", { p = "waiting", m = "tarot", r = 50.0, b = 1, k = {}, z = 0, lc = wire.lc, la = wire.la, ls = wire.ls })
  local cv = Director.view()
  local client_card = cv.last
  check("sync: a client shows the last card (the fields, the number, the age the host sent)", client_card ~= nil and client_card.name == wire.lc.n and client_card.suit == "swarm" and client_card.threat == wire.lc.t and cv.last_seq == wire.ls and cv.last_age >= wire.la and cv.last_age < wire.la + 5, cv.last and cv.last.name)
  Director.on_state("host_peer", { p = "waiting", m = "tarot", r = 49.0, b = 1, k = {}, z = 0, lc = wire.lc, la = wire.la + 1, ls = wire.ls })
  check("sync: the same card in the next message keeps its table (the window does not rebuild) and gets the new age", Director.view().last == client_card and Director.view().last_age >= wire.la + 1)
  Director.on_state("host_peer", { p = "waiting", m = "tarot", r = 48.0, b = 1, k = {}, z = 0, lc = { k = "custom_2", n = "Other", s = "rage", t = 3, b = { "chaos_hound" }, q = "x", m = "", r = 0, c = 90 }, la = 0, ls = wire.ls + 1 })
  check("sync: another card (a new number) replaces it", Director.view().last ~= client_card and Director.view().last.name == "Other" and Director.view().last_seq == wire.ls + 1 and Director.view().last.suit == "rage")
  Director.on_state("host_peer", { p = "waiting", m = "tarot", r = 47.0, b = 1, k = {}, z = 0, lc = { k = "old", n = "Old Pox", s = "fester", t = 2, b = {} }, la = 1, ls = 99 })
  check("sync: a host that still says fester sends a Heresy card", Director.view().last and Director.view().last.suit == "heresy")
  Director.on_state("host_peer", { p = "waiting", m = "tarot", r = 46.0, b = 1, k = {}, z = 0, lc = "junk", la = "x", ls = {} })
  check("sync: junk instead of a card shows no last card and breaks nothing", Director.view().last == nil and Director.view().last_seq == 0)
  Director.on_state("host_peer", { p = "waiting", m = "tarot", r = 45.0, b = 1, k = {}, z = 0, lc = { k = "a", n = "A", s = "rage", t = 99, b = { 5, "ok" }, q = 12, c = -4 }, la = -50, ls = 5 })
  local clean_card = Director.view().last
  check("sync: every field is validated (threat 99 -> 6, a non-string enemy dropped, the whisper a string, the age never negative)", clean_card and clean_card.threat == 6 and #clean_card.breeds == 1 and clean_card.whisper == "12" and clean_card.cooldown == 0 and Director.view().last_age >= 0)
  Director.on_state("host_peer", { p = "waiting", m = "tarot", r = 44.0, b = 1, k = {} })
  check("sync: a host without the feature (an older version) sends none: no last card", Director.view().last == nil)
  Director.on_exit_gameplay()
  check("last card: out of a mission the view has none (a stale card is never shown)", Director.view().last == nil and Director.view().last_seq == 0 and Director.view().last_age == 0)

  -- the other modes: a random wave and a voted wave are fulfilled cards too
  is_server = true
  settings.mode = "random"
  only({ { "wave_small", 5, 0 } })
  v = start()
  Director.update(50); Director.update(50.5)
  v = Director.view()
  check("last card: in the random mode the wave that came is the last card", v.phase == "incoming" and v.last ~= nil and v.last.name == started_waves[1] and v.last_seq == 1, tostring(started_waves[1]))
  Director.on_exit_gameplay()
  check("last card: a new mission starts without one (the previous mission's card is gone)", (function() started_waves = {}; Director.on_enter_gameplay(); Director.on_mission_started(); Director.update(0.01); return Director.view().last == nil and Director.view().last_seq == 0 end)())
  Director.on_exit_gameplay()
  clean()
  started_waves = {}; started_defs = {}
end

-- 100 cards: the deck, and the message that tells the host which cards a client has ----------------------------------------------
do
  local Presets = PresetsMod
  local keys = Events.keys()
  local function get(id) return settings[id] end
  local function w(key, name, recipe, pct) return { key = key, name = name, recipe = recipe, enabled = true, pct = pct, cd = 0, sp = 3, re = 10, rf = 60, dmin = 0, dmax = 0 } end
  check("cards: a deck holds 100 cards: the 12 standard ones and 88 custom slots, every key valid and unique", Events.MAX_CARDS == 100 and Events.CUSTOM_SLOTS == 88 and #keys == 100 and (function() local seen = {} for _, k in ipairs(keys) do if seen[k] then return false end seen[k] = true end return seen.custom_88 == true and not seen.custom_89 end)())
  check("cards: slot 88 is a card, slot 89 and slot 0 are not", Events.get("custom_88", get, Groups) ~= nil and Events.get("custom_89", get, Groups) == nil and Events.get("custom_0", get, Groups) == nil)
  check("cards: the Deck's odds strip has a segment for every card that can be in the draw", load("ui/deck").STRIP_MAX == Events.MAX_CARDS)
  check("cards: the order of the Deck keeps all 100 (a saved order that lacks the new slots gets them in their usual place)", (function() local ordered = Events.ordered_keys(function(id) return id == "deck_order" and "custom_3,wave_small,custom_3,gone" or nil end); return #ordered == 100 and ordered[1] == "custom_3" and ordered[2] == "wave_small" and ordered[100] == "custom_88" end)())

  -- a client with many cards: one message to the host; when they do not all fit, the first cards that do
  local big = "3 crusher[enraged+purple+blight]{health=150 size=130 speed=120 gap=40 fire=200 burst=300 mass=250}, 2 mauler[red]{health=80 size=90}, 4 rager[orange+toughened], 3 gunner[fire]{fire=120}, 2 hound, 5 poxwalker@3, 2 mutant|trapper|flamer[parasite], 1 plague ogryn, 2 sniper, 3 bomber, 2 burster, 1 chaos spawn"
  check("cards: the big recipe of the tests parses to the twelve groups a card holds", #Groups.parse(big) == 12, #Groups.parse(big))
  for i = 1, Events.CUSTOM_SLOTS do settings["wave_def_custom_" .. i] = "Card " .. i .. "\t" .. big; settings["on_custom_" .. i] = true; settings["pct_custom_" .. i] = 5 end
  local full = #Presets.encode(Presets.enabled_waves(get, Events, Groups))
  local saved_limit = Protocol.MAX_WAVES_TEXT
  is_server = false
  Director.on_exit_gameplay(); Director.on_enter_gameplay()
  Director.on_welcome("host_peer", 1, "1.0.0", true)
  local decoded = sent.waves and Presets.decode(sent.waves, Events, Groups)
  check("cards: with room (the real limit) a client sends all of its cards, 100 of them, in one message", decoded ~= nil and #decoded.waves == 100 and #sent.waves == full and full < 90000, tostring(full) .. " " .. tostring(decoded and #decoded.waves))

  Protocol.MAX_WAVES_TEXT = 20000
  local echo_mark = #echoes
  sent.waves, sent.waves_count = nil, nil
  check("cards: the premise of the next test: the cards are more than the message can hold", full > 20000, full)
  local ok_sent = Director.send_waves()
  local text = sent.waves
  local trimmed = text and Presets.decode(text, Events, Groups)
  check("cards: 100 big cards do not fit in one message: the first cards that fit are sent, an intact preset under the limit, not nothing", ok_sent == true and text ~= nil and #text <= 20000 and trimmed ~= nil and #trimmed.waves >= 10 and #trimmed.waves < 100 and trimmed.waves[1].key == "wave_small" and trimmed.waves[#trimmed.waves].key == keys[#trimmed.waves], text and #text)
  Director.send_waves(); Director.send_waves()
  local said = 0; for i = echo_mark + 1, #echoes do if echoes[i]:find("enabled cards fit in one message", 1, true) then said = said + 1 end end
  check("cards: ...and it is said once, not at every send", said == 1, said)
  Protocol.MAX_WAVES_TEXT = 50
  sent.waves = nil
  Director.send_waves()
  local one = sent.waves and Presets.decode(sent.waves, Events, Groups)
  check("cards: if no card fits, send an empty valid deck to clear the host's previous pool", one ~= nil and #one.waves == 0 and #sent.waves <= 50, one and #one.waves)
  Protocol.MAX_WAVES_TEXT = saved_limit
  do
    local saved_fits = Protocol.waves_text_fits
    Protocol.waves_text_fits = function(text)
      local escaped = text:gsub('["\\]', 'XX')
      return #text <= (Protocol.MAX_WAVES_TEXT or 90000) and #escaped + 2 <= 96 * 1024 - 1024
    end
    for _, k in ipairs(keys) do settings["wave_def_" .. k] = string.rep('"', 750) .. "\t" .. big; settings["on_" .. k] = true end
    local full_text = Presets.encode(Presets.enabled_waves(get, Events, Groups))
    local sent_ok = Director.send_waves()
    local escaped_deck = sent.waves and Presets.decode(sent.waves, Events, Groups)
    check("cards: quote-heavy decks fit after transport escaping, not just as raw text", sent_ok and Protocol.waves_text_fits(sent.waves) and escaped_deck ~= nil and #escaped_deck.waves > 0 and #escaped_deck.waves < 100 and not Protocol.waves_text_fits(full_text))
    Protocol.waves_text_fits = saved_fits
    for _, k in ipairs(keys) do if not k:find("^custom_") then settings["wave_def_" .. k] = nil end end
  end

  -- the host takes up to 100 cards of one player
  is_server = true
  Director.on_exit_gameplay(); Director.on_enter_gameplay()
  is_server = true
  for _, k in ipairs(keys) do settings["on_" .. k] = false end
  settings.pool_all_players = true
  local many = {}; for i = 1, 100 do many[i] = w(keys[i], "P" .. i, "1 hound", 5) end
  Director.on_waves("peer_d", Presets.encode({ name = "waves", waves = many }))
  check("cards: the host takes all 100 cards of one player into the pool (the limit was 40)", #Director.extra_waves() == 100, #Director.extra_waves())
  local more = {}; for i = 1, 150 do more[i] = w(keys[(i - 1) % 100 + 1], "Q" .. i, "1 hound", 5) end
  Director.on_waves("peer_e", Presets.encode({ name = "waves", waves = more }))
  check("cards: a second player never adds more than 100 of their own", #Director.extra_waves() <= 200, #Director.extra_waves())

  for i = 1, Events.CUSTOM_SLOTS do settings["wave_def_custom_" .. i] = nil; settings["on_custom_" .. i] = nil; settings["pct_custom_" .. i] = nil end
  for _, k in ipairs(keys) do settings["on_" .. k] = nil end
  settings.pool_all_players = nil
  Director.on_exit_gameplay(); started_waves = {}; started_defs = {}
end
-- protocol layer: RPCs registered, rw_waves send/receive validation ------------------------------------------------
do
  local registered, sent_rpcs = {}, {}
  local joined, left
  local realms = {
    network_is_available = function() return true end,
    network_register = function(m, name, handler) registered[name] = handler; return true end,
    network_send = function(m, name, recipient, ...) sent_rpcs[#sent_rpcs + 1] = { name = name, recipient = recipient, args = { ... }, mod = m }; return true end,
    network_on_peer_joined = function(m,fn) joined=fn end, network_on_peer_left = function(m,fn) left=fn end,
  }
  local real_get_mod = get_mod
  get_mod = function(name) if name == "Realms" then return realms end return real_get_mod(name) end
  cjson = { encode = function(v) return "{json}" end, decode = function(t) return { p = "waiting" } end }
  local P = load("core/protocol")
  local received = {}
  P.init({ on_waves = function(sender, text) received[#received + 1] = { sender, text } end, on_vote = function() end })
  local names = {}; for name in pairs(registered) do names[#names + 1] = name end; table.sort(names)
  check("protocol: seven RPCs registered (appearance, hello, scale, state, vote, waves, welcome)", table.concat(names, ",") == "rw_appearance,rw_hello,rw_scale,rw_state,rw_vote,rw_waves,rw_welcome", table.concat(names, ","))
  check("protocol: send_waves goes to the host with the text as one argument (dot call: mod first)", P.send_waves("RW1|x") == true and sent_rpcs[#sent_rpcs].name == "rw_waves" and sent_rpcs[#sent_rpcs].recipient == "host" and sent_rpcs[#sent_rpcs].args[1] == "RW1|x" and sent_rpcs[#sent_rpcs].mod == mod)
  local n = #sent_rpcs
  check("protocol: a text over the size limit is not sent", P.send_waves(string.rep("x", P.MAX_WAVES_TEXT + 1)) == false and #sent_rpcs == n and P.send_waves(42) == false)
  check("protocol: a text of exactly the limit (90000) is still sent", P.send_waves(string.rep("x", P.MAX_WAVES_TEXT)) == true and P.MAX_WAVES_TEXT == 90000)
  registered.rw_waves("peer_a", "RW1|ok")
  registered.rw_waves("", "RW1|no sender"); registered.rw_waves(nil, "x"); registered.rw_waves("peer_a", 42); registered.rw_waves("peer_a", string.rep("y", P.MAX_WAVES_TEXT + 1))
  check("protocol: received waves are validated (sender, type, size) before the handler runs", #received == 1 and received[1][1] == "peer_a" and received[1][2] == "RW1|ok", #received)

  -- rw_scale: sizes of units (custom mods)
  local scales = {}
  P.init({ on_waves = function() end, on_vote = function() end, on_scale = function(sender, entries) scales[#scales + 1] = { sender, entries } end })
  local next_decode
  cjson.decode = function() return next_decode end
  next_decode = { { 12, 150 }, { 13.5, 120 }, { -1, 120 }, { 14, 9999 }, { 15, 1 }, "x", { "a", 100 }, { 16, 0 / 0 } }
  registered.rw_scale("host_peer", "[...]")
  check("protocol: received sizes are checked: whole ids only, sizes clamped to 25-300 percent, junk dropped", #scales == 1 and #scales[1][2] == 3 and scales[1][2][1].id == 12 and scales[1][2][1].pct == 150 and scales[1][2][2].id == 14 and scales[1][2][2].pct == 300 and scales[1][2][3].pct == 25, scales[1] and #scales[1][2] or 0)
  registered.rw_scale("", "[...]"); registered.rw_scale(nil, "[...]")
  next_decode = { "nothing", { -5, 100 } }; registered.rw_scale("host_peer", "[...]")
  check("protocol: no sender or nothing valid: the handler does not run", #scales == 1)
  local many = {}; for i = 1, 450 do many[i] = { i, 120 } end
  next_decode = many; registered.rw_scale("host_peer", "[...]")
  check("protocol: at most 200 sizes are taken from one message", #scales == 2 and #scales[2][2] == 200)
  cjson.encode = function(v) return "list:" .. #v end
  local before = #sent_rpcs
  check("protocol: send_scales sends one json argument to the others (or to one peer); nothing for an empty list", P.send_scales({ { 1, 120 }, { 2, 130 } }) == true and sent_rpcs[#sent_rpcs].name == "rw_scale" and sent_rpcs[#sent_rpcs].recipient == "others" and sent_rpcs[#sent_rpcs].args[1] == "list:2" and P.send_scales({ { 3, 120 } }, "peer_b") == true and sent_rpcs[#sent_rpcs].recipient == "peer_b" and P.send_scales({}) == false and #sent_rpcs == before + 2)
  local calls = 0
  P.init({ on_state=function() calls=calls+1 end, on_welcome=function() calls=calls+1 end, on_scale=function() calls=calls+1 end })
  registered.rw_state("other_client", "x"); registered.rw_welcome("other_client", 2, "2.0.0", 1); registered.rw_scale("other_client", "x")
  check("protocol: another client cannot spoof host state, a welcome or unit sizes", calls==0)
  registered.rw_state("host_peer", "x"); registered.rw_welcome("host_peer", 2, "2.0.0", 1); registered.rw_scale("host_peer", "x")
  check("protocol: authenticated host messages still arrive", calls==3)
  local connection=Managers.connection; Managers.connection=nil
  registered.rw_state("host_peer", "x"); registered.rw_welcome("host_peer", 2, "2.0.0", 1); registered.rw_scale("host_peer", "x")
  check("protocol: no session connection means no host messages are accepted", calls==3)
  Managers.connection=connection
  realms.network_send=function() error("connection closed during send") end
  local send_ok, sent, why=pcall(P.send_hello)
  check("protocol: a disconnect during any RPC send returns a failure without raising", send_ok and sent==false and tostring(why):find("connection closed",1,true))

  -- Match Realms' asymmetric contract: broadcast is true despite one rejected
  -- peer, while a direct send exposes false. Use the real protocol and tuning.
  local attempts, deliveries, payloads = {}, {}, {}
  local reject, capable = true, false
  cjson.encode=function(list)
    local key="sizes:"..(#payloads+1);local copy={}
    for i,item in ipairs(list) do copy[i]={item[1],item[2]} end
    payloads[#payloads+1]=copy;payloads[key]=copy;return key
  end
  realms.network_send=function(m,name,recipient,json)
    if recipient=="others" then
      realms.network_send(m,name,"good",json)
      realms.network_send(m,name,"failed",json)
      if capable then realms.network_send(m,name,"unsupported",json) end
      return true -- actual Realms broadcast hides individual rejection
    end
    attempts[recipient]=(attempts[recipient] or 0)+1
    if recipient=="unsupported" and not capable then return false,"target_rpc_unsupported" end
    if recipient=="failed" and reject then return false,"channel unavailable" end
    deliveries[recipient]=payloads[json];return true
  end
  joined("good");joined("failed");joined("unsupported")
  local native_unit,native_su,native_vector,native_spawner=Unit,ScriptUnit,Vector3,Managers.state.unit_spawner
  Unit={alive=function() return true end,set_local_scale=function() end}
  Vector3=function(x,y,z) return {x=x,y=y,z=z} end
  ScriptUnit={has_extension=function() return nil end}
  Managers.state.unit_spawner={game_object_id=function(self,unit) return unit.id end}
  local tuner=load("spawn/tuning");tuner.init({protocol=P})
  local unit={id=77}
  tuner.apply(unit,{size=130});tuner.update(0.3)
  check("delivery: partial direct rejection retains current-size retry while good peer is served", tuner.status().unsent==1 and deliveries.good[1][2]==130 and deliveries.failed==nil)
  local unsupported_attempts=attempts.unsupported
  tuner.apply(unit,{size=180});tuner.update(0.3)
  check("delivery: retries coalesce to latest size and unsupported peers are skipped", tuner.status().unsent==1 and deliveries.good[1][2]==180 and attempts.unsupported==unsupported_attempts)
  reject=false;tuner.update(0.3)
  check("delivery: recovered recipient receives latest size and retry clears", deliveries.failed and deliveries.failed[1][2]==180 and tuner.status().unsent==0)
  reject=true
  for i=1,100 do tuner.send_all("failed") end
  check("delivery: rejected late-join snapshots coalesce instead of growing", tuner.status().unsent==1)
  left("failed");tuner.update(0.3)
  check("delivery: disconnect removes failed recipient from retries", tuner.status().unsent==0)
  capable=true;registered.rw_hello("unsupported",2,"2.0.0")
  tuner.apply(unit,{size=150});tuner.update(0.3)
  check("delivery: compatible hello rearms previously unsupported recipient", deliveries.unsupported[1][2]==150)
  realms.network_on_peer_joined=function(m,fn) joined=fn;fn("good") end
  P.refresh_peers();attempts={}
  P.send_scales({{77,150}})
  check("delivery: refresh discards peers missed while disabled and replays current peers", attempts.good==1 and attempts.unsupported==nil and attempts.failed==nil)
  for i=1,30 do joined("synthetic_"..i) end
  attempts={};P.send_scales({{77,150}})
  local peer_count=0;for _ in pairs(attempts) do peer_count=peer_count+1 end
  check("delivery: recipient registry is bounded at 16", peer_count==16)
  P.refresh_peers();joined("zz_gone")
  local gone_attempts=0
  realms.network_send=function(m,name,recipient)
    if recipient=="good" then left("zz_gone") end
    if recipient=="zz_gone" then gone_attempts=gone_attempts+1 end
    return true
  end
  check("delivery: synchronous disconnect during fanout skips removed recipient", P.send_scales({{77,150}})==true and gone_attempts==0)
  local before_retire=calls
  P.retire();registered.rw_state("host_peer","x");registered.rw_hello("late",2,"2.0.0");joined("late")
  check("protocol: captured RPC/peer callbacks and sends are inert after retire", calls==before_retire and not P.is_available() and P.send_scales({{77,150}})==false)
  Unit,ScriptUnit,Vector3,Managers.state.unit_spawner=native_unit,native_su,native_vector,native_spawner
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
  local fe_old = Presets.decode_wave(Presets.seal("RWW1|custom_1~A~1~10~60~3~10~60~3 hounds~0~0~0~0~fester~0~~"), Events, Groups)
  local fe_new = Presets.decode_wave(Presets.seal("RWW1|custom_1~A~1~10~60~3~10~60~3 hounds~0~0~0~0~heresy~0~~"), Events, Groups)
  local fe_bad = Presets.decode_wave(Presets.seal("RWW1|custom_1~A~1~10~60~3~10~60~3 hounds~0~0~0~0~bogus~0~~"), Events, Groups)
  check("heresy: a shared card or an old preset that says fester arrives as Heresy, heresy as heresy, an unknown suit as plague", fe_old and fe_old.suit == "heresy" and fe_new and fe_new.suit == "heresy" and fe_bad and fe_bad.suit == "plague", fe_old and tostring(fe_old.suit))
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
-- /rw_stop, /rw_pause, /rw_next, anti-snowballing ------------------------------------------------------------------
do
  settings.mode = "random"; settings.interval_min = 100; settings.interval_max = 100; settings.initial_delay = 0; settings.vote_duration = 25
  settings.wave_def_custom_1 = "Pulse\t2 hounds"; settings.on_custom_1 = true; settings.ev_custom_1 = 30
  local function fresh()
    started_waves = {}; started_defs = {}
    Director.on_exit_gameplay(); Director.on_enter_gameplay(); Director.on_mission_started(); Director.update(0.01)
    return Director.view()
  end
  local function pulses() local n = 0; for _, nme in ipairs(started_waves) do if nme == "Pulse" then n = n + 1 end end return n end

  -- pause
  local v = fresh()
  local r0 = v.remaining
  Director.update(10)
  local r1 = Director.view().remaining
  check("pause: the countdown runs normally first", r0 - r1 > 9.9 and r0 - r1 < 10.1, r0 - r1)
  check("pause: /rw_pause returns the new state", Director.pause() == true and Director.is_paused() == true)
  Director.update(40)
  v = Director.view()
  check("pause: the countdown stands still while paused", math.abs(v.remaining - r1) < 0.01 and v.paused == true, v.remaining)
  Director.update(50)
  check("pause: nothing fires while paused (not the draw, not the fixed timer)", #started_waves == 0, #started_waves)
  check("pause: the synced state says paused (z=1) so clients freeze their countdown", sent[#sent].state.z == 1 or (Director.update(1.5) == nil and sent[#sent].state.z == 1))
  check("pause: a second call (or 'off') releases it", Director.pause() == false and Director.pause(true) == true and Director.pause(false) == false)
  Director.update(5)
  check("pause: the clocks run again after the release", r1 - Director.view().remaining > 4.9)
  -- clients freeze their own interpolation
  is_server = false
  Director.on_exit_gameplay(); Director.on_enter_gameplay()
  Director.on_state("host_peer", { p = "waiting", m = "random", r = 50.0, b = 1, c = "", k = {}, e = 0, z = 1 })
  local cv = Director.view()
  check("pause: a client shows the frozen time and the paused flag", cv.paused == true and math.abs(cv.remaining - 50) < 0.01)
  Director.on_state("host_peer", { p = "waiting", m = "random", r = 50.0, b = 1, c = "", k = {}, e = 0, z = 0 })
  check("pause: ...and not paused afterwards", Director.view().paused == false)
  is_server = true
  check("pause: a client cannot pause", (function() is_server = false; local ok, why = Director.pause(); is_server = true; return ok == nil and why:find("only the host") ~= nil end)())

  -- next
  v = fresh()
  local first_ballot = v.ballot_id
  Director.update(30)
  check("next: only the host and only with a running cycle", (function() is_server = false; local ok = Director.next_wave(); is_server = true; return ok == false end)())
  local before_waves = #started_waves
  check("next: /rw_next draws a new wave and a full new timer, spawning nothing for the dropped one", Director.next_wave() == true and Director.view().ballot_id ~= first_ballot and Director.view().remaining > 99 and #started_waves == before_waves and Director.view().phase == "waiting", Director.view().remaining)
  Director.pause(true)
  Director.next_wave()
  check("next: leaves the pause", Director.is_paused() == false)

  -- stop
  v = fresh()
  Director.update(10)
  check("stop: /rw_stop works for the host", Director.stop() == true and Director.is_stopped() == true)
  check("stop: the panel is gone (phase off) and the host sends an 'off' state to the others", Director.view().phase == "off" and sent[#sent].state.p == "off")
  started_waves = {}
  Director.update(200); Director.update(200)
  check("stop: no wave, no vote, no fixed timer while stopped", #started_waves == 0 and Director.timed_wave_count() == 0)
  check("stop: pause/next/skip are refused with a reason while stopped", select(1, Director.pause()) == nil and Director.next_wave() == false)
  check("stop: /rw_start starts it again", Director.force_start() == true and Director.is_stopped() == false and Director.view().phase == "waiting")
  check("stop: a client cannot stop", (function() is_server = false; local ok = Director.stop(); is_server = true; return ok == false end)())

  -- anti-snowballing
  v = fresh()
  Director.update(5)
  local rem = Director.view().remaining
  settings.anti_snowball = nil
  check("anti-snowball: off by default -> a death changes nothing", Director.on_player_died() == false and math.abs(Director.view().remaining - rem) < 0.01)
  settings.anti_snowball = true; settings.anti_snowball_delay = 30
  Director.update(1) -- lets the fixed timer register
  rem = Director.view().remaining
  check("anti-snowball: on -> a death delays the countdown by the slider's seconds", Director.on_player_died() == true and math.abs(Director.view().remaining - (rem + 30)) < 0.01, Director.view().remaining - rem)
  settings.anti_snowball_delay = 5
  rem = Director.view().remaining
  Director.on_player_died()
  check("anti-snowball: the slider value is used (5 s)", math.abs(Director.view().remaining - (rem + 5)) < 0.01)
  -- the fixed timer is pushed back too: it was due 30 s after the start (about 7 s in), +30 +5 -> not before ~65 s
  for _ = 1, 50 do Director.update(1) end
  check("anti-snowball: fixed timers are delayed as well (nothing fired after 56 s although the period is 30 s)", pulses() == 0, pulses())
  for _ = 1, 15 do Director.update(1) end
  check("anti-snowball: ...and they come after the delay", pulses() >= 1, pulses())
  Director.pause(true)
  rem = Director.view().remaining
  Director.on_player_died()
  check("anti-snowball: while paused the delay still adds up", Director.view().remaining > rem)
  Director.pause(false)
  is_server = false
  check("anti-snowball: a client does nothing", Director.on_player_died() == false)
  is_server = true
  check("anti-snowball: an incoming banner is not extended (the wave already fired)", (function()
    fresh(); Director.update(101)
    local phase = Director.view().phase
    local remaining = Director.view().remaining
    Director.on_player_died()
    return phase == "incoming" and math.abs(Director.view().remaining - remaining) < 0.01
  end)())
  Director.stop()
  check("anti-snowball: nothing while stopped", Director.on_player_died() == false)
  Director.force_start()
  settings.anti_snowball, settings.anti_snowball_delay = nil, nil
  settings.wave_def_custom_1, settings.on_custom_1, settings.ev_custom_1 = nil, nil, nil
  settings.interval_min, settings.interval_max = 100, 100
  Director.on_exit_gameplay(); started_waves = {}; started_defs = {}
end

-- deleted standard waves (del_<key>) -------------------------------------------------------------------------------
do
  local Presets = PresetsMod
  local store = {}
  local function g(id) return store[id] end
  local function s(id, v) store[id] = v end
  local wave = Events.get("wave_small", g, Groups)
  check("deleted: a standard wave is not deleted by default", wave.deleted == false and wave.enabled == true)
  store.del_wave_small = true
  wave = Events.get("wave_small", g, Groups)
  check("deleted: a deleted wave reads as deleted and disabled", wave.deleted == true and wave.enabled == false)
  local in_pool = false; for _, e in ipairs(Events.build_pool(g, Groups)) do if e.key == "wave_small" then in_pool = true end end
  local timed_ok = true; store.ev_wave_small = 30; for _, tw in ipairs(Events.timed_waves(g, Groups)) do if tw.key == "wave_small" then timed_ok = false end end
  check("deleted: never in the draw and never timed", not in_pool and timed_ok)
  check("deleted: Events.find does not find it any more", select(1, Events.find("small_wave", g, Groups)) == nil)
  check("deleted: custom slots cannot be 'deleted' (that is emptying the slot)", (function() store.del_custom_1 = true; return Events.get("custom_1", g, Groups).deleted == false end)())
  store.del_custom_1 = nil
  local cap = Presets.capture(g, Events, Groups)
  local cw; for _, w2 in ipairs(cap.waves) do if w2.key == "wave_small" then cw = w2 end end
  check("deleted: presets capture it", cw and cw.deleted == true)
  cap.name = "D"
  local back = Presets.decode(Presets.encode(cap), Events, Groups)
  local bw; for _, w2 in ipairs(back.waves) do if w2.key == "wave_small" then bw = w2 end end
  check("deleted: presets round trip it", bw and bw.deleted == true)
  local applied = {}
  Presets.apply(back, function(id, v) applied[id] = v end, Events, Groups)
  check("deleted: loading a preset deletes it again, and waves not in the preset come back", applied.del_wave_small == true and applied.del_wave_large == false)
  Presets.apply({ waves = {} }, s, Events, Groups)
  check("deleted: restoring the defaults (empty preset) brings every deleted wave back", store.del_wave_small == false and Events.get("wave_small", g, Groups).enabled == true)
  local sent_waves = Presets.enabled_waves(function(id) return id == "del_wave_small" and true or nil end, Events, Groups)
  local has_small = false; for _, w2 in ipairs(sent_waves.waves) do if w2.key == "wave_small" then has_small = true end end
  check("deleted: a client does not send its deleted waves to the host", not has_small)
  local old12 = Presets.decode_wave(Presets.seal("RWW1|custom_1~A~1~10~60~3~10~60~3 hounds~0~0~0"), Events, Groups)
  check("deleted: texts without the deleted field (12 fields) still import", old12 and old12.deleted == false)
end

-- modifier colours like Improved Havoc Tags -------------------------------------------------------------------------
do
  local Colors = load("catalog/colors")
  local tags_settings = nil -- nil = Improved Havoc Tags not installed
  Colors.init({ kind = Groups.kind, option = function(id) return settings[id] end, havoc_setting = function(id) return tags_settings and tags_settings[id] or nil end })
  local function rgb(id) local c = Colors.modifier_rgb(id); return c and table.concat(c, ",") end
  check("modifier colours: without the mod, ITS defaults (purple/garden blue-violet, enraged red, orange, rotten green...)", rgb("garden") == "138,43,226" and rgb("enraged") == "255,54,36" and rgb("bolstering") == "208,136,48" and rgb("rotten") == "132,156,99" and rgb("corrupted") == "128,128,0" and rgb("toughened") == "157,169,75" and rgb("fire") == "160,82,45" and rgb("parasite") == "255,160,122" and rgb("purple_stimm") == "255,242,0", rgb("garden"))
  check("modifier colours: Final Toll uses the enraged red", rgb("toll") == "255,54,36")
  check("markup: a colour wraps the text in the game's tags; no colour leaves it plain (the card lines use both)", Colors.markup("95%", { 1, 2, 3 }) == "{#color(1,2,3)}95%{#reset()}" and Colors.markup("Party health", nil) == "Party health")
  check("modifier colours: every modifier of the catalog has a colour", (function() for _, m in ipairs(Groups.MODIFIERS) do if not Colors.modifier_rgb(m.id) then return false end end return true end)())
  tags_settings = { encroaching_garden = { 255, 1, 2, 3 }, enraged = "old string value", rotten_armor = { 255, 9 } }
  Colors.clear_cache()
  check("modifier colours: with the mod its colour option wins", rgb("garden") == "1,2,3")
  check("modifier colours: a broken value (string / short table) falls back to its default", rgb("enraged") == "255,54,36" and rgb("rotten") == "132,156,99")
  check("modifier colours: unknown modifier -> no colour", Colors.modifier_rgb("nope") == nil and Colors.modifier_rgb(nil) == nil)
  settings.colour_enemies = false; Colors.clear_cache()
  check("modifier colours: switched off with 'Colour enemy names'", Colors.modifier_rgb("garden") == nil)
  settings.colour_enemies = nil
  check("modifier colours: argb form for UI text colours", (function() Colors.clear_cache(); local a = Colors.modifier_argb("garden"); return a[1] == 255 and a[2] == 1 and a[3] == 2 and a[4] == 3 end)())
  -- the summary paints enemy and modifier names separately, and the visible text never changes
  Colors.init({ kind = Groups.kind, option = function(id) return settings[id] end, havoc_setting = function() return nil end, spidey_setting = function() return nil end, named = function() return nil end })
  local painter = { part = function(part) return Colors.rgb(part.breed) end, mod = function(id) return Colors.modifier_rgb(id) end, markup = Colors.markup }
  local parts = Groups.parse("3 crushers[garden+enraged]@2, 5 hounds, 2 scab rager[rotten], 1 plague ogryn|chaos spawn")
  local mismatches = {}
  for max = 4, 140 do
    local plain = Groups.summary(parts, max)
    local painted = Groups.summary(parts, max, painter)
    local visible = painted:gsub("{#[^}]*}", "")
    if visible ~= plain then mismatches[#mismatches + 1] = max .. ": [" .. visible .. "] vs [" .. plain .. "]"; if #mismatches > 2 then break end end
  end
  check("modifier colours: painted summary (enemy + modifier segments) has exactly the plain visible text at every length", #mismatches == 0, table.concat(mismatches, " | "))
  local text = Groups.summary(parts, 200, painter)
  check("modifier colours: modifier names carry their own colour tags", text:find("{#color(138,43,226)}Purple{#reset()}", 1, true) ~= nil and text:find("{#color(255,54,36)}Enraged{#reset()}", 1, true) ~= nil and text:find("{#color(132,156,99)}Rotten Armor{#reset()}", 1, true) ~= nil, text)
  check("modifier colours: the enemy part keeps the enemy's colour around them", text:find("{#color(240,240,240)}3 Crusher{#reset()}{#color(240,240,240)} [{#reset()}", 1, true) ~= nil and text:find("{#color(240,240,240)}]", 1, true) ~= nil)
  local head, mods, tail = Groups.describe_part_pieces(parts[1])
  check("modifier colours: describe_part is unchanged by the refactor", head == "3 Crusher" and #mods == 2 and mods[1].id == "garden" and tail == " (+2 per repeat)" and Groups.describe_part(parts[1], true) == "3 Crusher [Purple, Enraged] (+2 per repeat)" and Groups.describe_part(parts[2]) == "5 Hound")
end
-- The tarot draw: hand, winner, cooldowns, sync ------------------------------------------------------------------------
do
  local keys = Events.keys()
  local function reset_settings()
    for _, k in ipairs(keys) do settings["on_" .. k] = nil; settings["pct_" .. k] = nil; settings["cd_" .. k] = nil end
    settings.mode = nil; settings.tarot_cards = 3; settings.tarot_seconds = 10
    settings.interval_min = 100; settings.interval_max = 100; settings.interval_random = false; settings.initial_delay = 0
  end
  -- only these waves are in the draw: { { key, weight, cooldown }, ... }
  local function only(list)
    for _, k in ipairs(keys) do settings["on_" .. k] = false end
    for _, e in ipairs(list) do settings["on_" .. e[1]] = true; settings["pct_" .. e[1]] = e[2] or 5; settings["cd_" .. e[1]] = e[3] or 0 end
  end
  local function start()
    started_waves = {}; started_defs = {}
    Director.on_exit_gameplay(); Director.on_enter_gameplay(); Director.on_mission_started(); Director.update(0.01)
    return Director.view()
  end
  local function key_of_def(def) return def.key end
  reset_settings()

  -- the cycle: wait, deal, pick
  only({ { "wave_small", 5, 0 }, { "wave_medium", 5, 0 }, { "wave_large", 5, 0 }, { "wave_huge", 5, 0 }, { "boss_ambush", 5, 0 } })
  local v = start()
  check("tarot: the default mode is the tarot draw; the first state is a countdown without a hand", v.mode == "tarot" and v.phase == "waiting" and v.hand == nil and v.remaining > 99 and not v.drawn, tostring(v.mode) .. "/" .. tostring(v.phase))
  Director.update(85)
  check("tarot: the hand is NOT dealt before the last 'seconds before the pick'", Director.view().phase == "waiting" and Director.view().hand == nil)
  Director.update(6)
  v = Director.view()
  check("tarot: the hand is dealt 10 s before the pick (3 cards, all different)", v.phase == "hand" and #v.hand == 3 and v.hand[1].key ~= v.hand[2].key and v.hand[2].key ~= v.hand[3].key and v.hand[1].key ~= v.hand[3].key and v.hand_seconds > 8 and v.hand_seconds < 10, tostring(v.hand and #v.hand))
  check("tarot: the winner is chosen when the hand is dealt (1..3) and synced with it", v.win >= 1 and v.win <= 3 and sent[#sent].state.w == v.win and #sent[#sent].state.h == 3 and sent[#sent].state.sq == v.hand_seq and sent[#sent].state.p == "hand")
  local c1 = sent[#sent].state.h[1]
  check("tarot: a synced card carries name, suit, threat, enemies, whisper, rare flag (no percentage)", c1.k and c1.n and Events.SUITS[c1.s] and c1.t >= 1 and c1.t <= 5 and type(c1.b) == "table" and #c1.b >= 1 and type(c1.q) == "string" and c1.q ~= "" and (c1.r == 0 or c1.r == 1) and c1.p == nil)
  local winner = v.hand[v.win].key
  local seq = v.hand_seq
  Director.update(8)
  check("tarot: nothing is spawned before the pick", #started_defs == 0)
  Director.update(1.5)
  v = Director.view()
  check("tarot: at the pick exactly the winner's wave is spawned", #started_defs == 1 and started_defs[1].key == winner, tostring(started_defs[1] and started_defs[1].key) .. " vs " .. winner)
  check("tarot: the resolved hand stays in the state for the reveal (drawn), the next interval already runs", v.phase == "waiting" and v.drawn == true and #v.hand == 3 and v.hand_seq == seq and v.remaining > 95 and v.chosen ~= "", v.remaining)
  check("tarot: the synced state says drawn (dn=1) and still holds the winner", sent[#sent].state.dn == 1 or (Director.update(1.1) == nil and sent[#sent].state.dn == 1))
  check("tarot: the resolved hand carries its age (da) and every card its cooldown (c)", (function() local st = sent[#sent].state; return type(st.da) == "number" and st.da >= 0 and st.da < 3 and type(st.h[1].c) == "number" end)(), tostring(sent[#sent].state.da))
  check("tarot: the host's own view has the age too, and it grows", Director.view().drawn_age >= 0 and Director.view().drawn == true)
  Director.update(17)
  check("tarot: the resolved hand is dropped after 16 s", Director.view().hand == nil and not Director.view().drawn)

  -- one card = no roulette; weights; uniform winner
  only({ { "wave_small", 5, 0 } })
  v = start(); Director.update(95)
  check("tarot: a single card in the pool makes a hand of one (no roulette: the winner is card 1)", #Director.view().hand == 1 and Director.view().win == 1)
  settings.tarot_cards = 5
  only({ { "wave_small", 5, 0 }, { "wave_medium", 5, 0 } })
  v = start(); Director.update(95)
  check("tarot: fewer cards than asked for -> a smaller hand (2 of 5)", #Director.view().hand == 2)
  settings.tarot_cards = 1
  only({ { "wave_small", 5, 0 }, { "wave_medium", 5, 0 }, { "wave_large", 5, 0 } })
  v = start(); Director.update(95)
  check("tarot: 'cards drawn' = 1 deals one card", #Director.view().hand == 1)
  settings.tarot_cards = 9
  only({ { "wave_small", 5, 0 }, { "wave_medium", 5, 0 }, { "wave_large", 5, 0 }, { "wave_huge", 5, 0 }, { "boss_ambush", 5, 0 }, { "bomber_frenzy", 5, 0 }, { "hound_frenzy", 5, 0 } })
  v = start(); Director.update(95)
  check("tarot: never more than 5 cards, whatever the option says", #Director.view().hand == 5)

  -- chance weights decide who is DEALT, the final pick among the hand is uniform
  settings.tarot_cards = 2; settings.tarot_seconds = 5; settings.interval_min = 5; settings.interval_max = 5
  only({ { "wave_small", 10, 0 }, { "wave_medium", 1, 0 }, { "wave_large", 1, 0 } })
  v = start()
  local dealt, wins, hands, bad_hand = { wave_small = 0, wave_medium = 0, wave_large = 0 }, { wave_small = 0, wave_medium = 0, wave_large = 0 }, 0, false
  local seen_seq = {}
  for _ = 1, 3000 do
    Director.update(0.5)
    local view_now = Director.view()
    if view_now.phase == "hand" and not seen_seq[view_now.hand_seq] then
      seen_seq[view_now.hand_seq] = true
      hands = hands + 1
      if #view_now.hand ~= 2 or view_now.hand[1].key == view_now.hand[2].key then bad_hand = true end
      for _, cd in ipairs(view_now.hand) do dealt[cd.key] = dealt[cd.key] + 1 end
      wins[view_now.hand[view_now.win].key] = wins[view_now.hand[view_now.win].key] + 1
    end
  end
  check("tarot: hands are always 2 different cards (a card never twice in one hand)", hands > 250 and not bad_hand, hands)
  check("tarot: the heavy card is dealt into almost every hand (weights drive the deal)", dealt.wave_small / hands > 0.93, dealt.wave_small / hands)
  check("tarot: but it wins only about half the time, not 83 percent (the pick among the hand is uniform)", wins.wave_small / hands > 0.40 and wins.wave_small / hands < 0.58, wins.wave_small / hands)
  check("tarot: the light cards win too, roughly equally", wins.wave_medium > 0.1 * hands and wins.wave_large > 0.1 * hands and math.abs(wins.wave_medium - wins.wave_large) < 0.12 * hands, wins.wave_medium .. "/" .. wins.wave_large)

  -- cooldown: a drawn card is out of EVERY draw for its full cooldown
  settings.tarot_cards = 5; settings.tarot_seconds = 10; settings.interval_min = 100; settings.interval_max = 100
  only({ { "wave_small", 5, 1000 }, { "wave_medium", 5, 1000 } })
  v = start(); Director.update(95)
  v = Director.view()
  local first_keys = { v.hand[1].key, v.hand[2].key }
  Director.update(6)
  local fired_key = started_defs[1] and started_defs[1].key
  check("cooldown: the first hand holds both cards, one is picked", #v.hand == 2 and fired_key ~= nil)
  check("cooldown: the picked card is listed as cooling down with its seconds left (synced as cd)", (function() local m = sent[#sent].state.cd; return type(m) == "table" and m[fired_key] and m[fired_key] > 990 and m[fired_key] <= 1000 end)(), tostring(sent[#sent].state.cd and sent[#sent].state.cd[fired_key]))
  Director.update(95)
  v = Director.view()
  local other = fired_key == "wave_small" and "wave_medium" or "wave_small"
  check("cooldown: the next hand has ONLY the other card (the picked one stays out)", v.phase == "hand" and #v.hand == 1 and v.hand[1].key == other, v.hand and v.hand[1] and v.hand[1].key)
  Director.update(11)
  Director.update(95)
  v = Director.view()
  check("cooldown: with every card cooling down nothing is dealt: the state says so (e=2: all cooling) and it tries again soon", v.phase == "waiting" and v.empty == true and v.cooling == true and sent[#sent].state.e == 2 and v.remaining <= 10.5, tostring(v.empty) .. "/" .. tostring(v.cooling) .. "/" .. v.remaining)
  Director.update(1100)
  Director.update(95)
  check("cooldown: after the full cooldown the cards are dealt again", Director.view().hand ~= nil and #Director.view().hand >= 1, Director.view().hand and #Director.view().hand)
  check("cooldown: the host can read how long is left", (function() local ok = Director.cooldown_remaining("wave_small", 1000); return type(ok) == "number" end)())
  -- /rw_pause freezes the cooldown clock too
  only({ { "wave_small", 5, 100 } })
  v = start(); Director.update(95); Director.update(6)
  Director.pause(true); Director.update(500)
  check("cooldown: the clock does not run while paused", Director.cooldown_remaining("wave_small", 100) > 90, Director.cooldown_remaining("wave_small", 100))
  Director.pause(false)
  Director.update(95)
  check("cooldown: ...so the card is still out when the countdown resumes and dealt again only after its cooldown", Director.view().hand == nil or Director.view().empty or Director.view().drawn == true)

  -- the cards that rest leave the draw, so the others become likelier: a card is dealt by its chance over the chances of the cards
  -- that can be dealt now (hands of ONE card here: three cards with chances 8, 2 and 2 that rest for ages after their pick)
  settings.tarot_cards = 1; settings.tarot_seconds = 10; settings.interval_min = 100; settings.interval_max = 100
  only({ { "wave_small", 8, 100000 }, { "wave_medium", 2, 100000 }, { "wave_large", 2, 100000 } })
  do
    local first_a, then_b, first_b, then_a = 0, 0, 0, 0
    local function hand_key() local hv = Director.view(); return hv.hand and hv.hand[1] and hv.hand[1].key end

    for _ = 1, 1500 do
      start(); Director.update(95)
      local first = hand_key()
      Director.update(6) -- the pick: its cooldown starts
      Director.update(95)
      local second = hand_key()

      if first == "wave_small" then first_a = first_a + 1; if second == "wave_medium" then then_b = then_b + 1 end end
      if first == "wave_medium" then first_b = first_b + 1; if second == "wave_small" then then_a = then_a + 1 end end
    end

    check("draw share: the first hand is by chance, 8 of 12 for the heavy card", first_a > 0.60 * 1500 and first_a < 0.73 * 1500, first_a)
    check("draw share: with the heavy card resting the other two share the draw 50/50 (it was 2 of 12 each)", first_a > 500 and math.abs(then_b / first_a - 0.5) < 0.06, then_b / math.max(1, first_a))
    check("draw share: with a light card resting the heavy one gets 8 of 10 (80 percent, not 8 of 12 = 67)", first_b > 150 and math.abs(then_a / first_b - 0.8) < 0.07, then_a / math.max(1, first_b))
  end
  settings.tarot_cards = 3

  -- empty pool, skip, next, short intervals, anti-snowball
  only({})
  v = start(); Director.update(95)
  check("tarot: nothing in the draw -> an empty state (e=1), no hand, no wave", Director.view().empty == true and Director.view().hand == nil and Director.view().cooling == false and #started_defs == 0 and sent[#sent].state.e == 1)
  only({ { "wave_small", 5, 0 }, { "wave_medium", 5, 0 } })
  v = start()
  Director.skip()
  Director.update(0.1)
  check("tarot: /rw_skip while waiting deals a hand and picks at once", #started_defs == 1 and Director.view().drawn == true and #Director.view().hand == 2)
  Director.update(20)
  local before_next = #started_defs
  Director.next_wave()
  v = Director.view()
  check("tarot: /rw_next throws the hand away without spawning and starts a full new interval", #started_defs == before_next and v.hand == nil and not v.drawn and v.remaining > 99 and v.phase == "waiting")
  settings.interval_min = 6; settings.interval_max = 6
  v = start()
  check("tarot: an interval shorter than 'seconds before the pick' deals at once (the hand is as long as the interval)", Director.view().phase == "hand" and Director.view().hand_seconds <= 6, Director.view().phase)
  settings.interval_min = 100; settings.interval_max = 100
  settings.anti_snowball = true; settings.anti_snowball_delay = 30
  v = start(); Director.update(95)
  local secs = Director.view().hand_seconds
  Director.on_player_died()
  check("tarot: anti-snowballing with a hand on the table delays the pick and lengthens the fuse", Director.view().remaining > 30 and Director.view().hand_seconds > secs and Director.view().phase == "hand", Director.view().hand_seconds)
  settings.anti_snowball = nil; settings.anti_snowball_delay = nil

  -- the client side: validation and cooldown countdown
  is_server = false
  Director.on_exit_gameplay(); Director.on_enter_gameplay()
  Director.on_state("host_peer", { p = "hand", m = "tarot", r = 8.0, b = 3, c = "", k = {}, e = 0, z = 0, sq = 7, w = 2, dn = 0, y = 10,
    h = { { k = "a", n = "The Devil", s = "fateful", t = 5, b = { "chaos_plague_ogryn", 42, "chaos_spawn" }, q = "Something big.", m = "Purple", r = 1 }, { k = "b", n = "Bogus", s = "nonsense", t = 99, b = {}, q = 12, r = 0 } },
    cd = { wave_small = 30, junk = "x" } })
  local cv = Director.view()
  check("client: the tarot hand is rendered from the synced state (winner, sequence, cards)", cv.mode == "tarot" and cv.phase == "hand" and #cv.hand == 2 and cv.win == 2 and cv.hand_seq == 7 and cv.hand[1].name == "The Devil" and cv.hand[1].suit == "fateful" and cv.hand[1].rare == true and cv.hand[1].modifiers == "Purple", tostring(cv.win))
  check("client: every field is validated (unknown suit -> plague, threat capped at 6, non-string enemies dropped, whisper made a string)", cv.hand[2].suit == "plague" and cv.hand[2].threat == 6 and #cv.hand[1].breeds == 2 and cv.hand[2].whisper == "12")
  Director.on_exit_gameplay(); Director.on_enter_gameplay()
  Director.on_state("host_peer", { p = "hand", m = "tarot", r = 8.0, b = 3, c = "", k = {}, e = 0, z = 0, sq = 1, w = 1, dn = 0, y = 10,
    h = { { k = "a", n = "Old", s = "fester", t = 2, b = {} }, { k = "b", n = "New", s = "heresy", t = 2, b = {} } } })
  local hv = Director.view()
  check("client: a host that still says fester (an older version) gets the Heresy card, and heresy arrives as heresy", hv.hand and #hv.hand == 2 and hv.hand[1].suit == "heresy" and hv.hand[2].suit == "heresy", hv.hand and tostring(hv.hand[1].suit))
  Director.on_state("host_peer", { p = "hand", m = "tarot", r = 8.0, b = 3, k = {}, sq = 8, w = 9, h = { { k = "a", n = "x", s = "rage", t = 1, b = {} }, 5, "junk" } })
  check("client: a winner index outside the hand is pulled inside it, junk cards are skipped", Director.view().win == 1 and #Director.view().hand == 1)
  local many = {}; for i = 1, 9 do many[i] = { k = "k" .. i, n = "N" .. i, s = "swarm", t = 1, b = {} } end
  Director.on_state("host_peer", { p = "hand", m = "tarot", r = 8.0, b = 3, k = {}, sq = 9, w = 3, h = many })
  check("client: at most 5 cards are accepted", #Director.view().hand == 5)
  Director.on_state("host_peer", { p = "waiting", m = "tarot", r = 50.0, b = 3, k = {}, sq = 0, dn = 1, y = 10, cd = { wave_small = 30, junk = "x", [5] = 3 } })
  check("client: the cooldown map is read (numbers by string keys only) and no hand means no hand", Director.view().hand == nil and Director.cooldown_remaining("wave_small") > 29 and Director.cooldown_remaining("junk") == 0 and Director.cooldown_remaining("nothing") == 0)
  Director.update(10)
  check("client: cooldowns count down locally between states", math.abs(Director.cooldown_remaining("wave_small") - 20) < 0.5, Director.cooldown_remaining("wave_small"))
  Director.on_state("host_peer", { p = "waiting", m = "tarot", r = 50.0, b = 3, k = {}, z = 1, cd = { wave_small = 30 } })
  Director.update(10)
  check("client: a paused host freezes them", math.abs(Director.cooldown_remaining("wave_small") - 30) < 0.5, Director.cooldown_remaining("wave_small"))
  -- the age of a resolved hand and the card cooldown travel with the state (the HUD places its timeline from them)
  Director.on_state("host_peer", { p = "waiting", m = "tarot", r = 90.0, b = 3, k = {}, sq = 21, w = 1, dn = 1, da = 3.5, y = 0, z = 0,
    h = { { k = "a", n = "A", s = "rage", t = 2, b = {}, c = 240 }, { k = "b", n = "B", s = "rage", t = 2, b = {}, c = 1e9 }, { k = "c", n = "C", s = "rage", t = 2, b = {} } } })
  local drawn_view = Director.view()
  check("client: a resolved hand carries its age (seconds since the pick) and counts it up locally", drawn_view.drawn == true and drawn_view.drawn_age >= 3.5 and drawn_view.drawn_age < 3.6, drawn_view.drawn_age)
  Director.update(2)
  check("client: ...it keeps counting between states", math.abs(Director.view().drawn_age - 5.5) < 0.2, Director.view().drawn_age)
  check("client: a card's cooldown is read, capped (a day) and 0 when missing", drawn_view.hand[1].cooldown == 240 and drawn_view.hand[2].cooldown == 86400 and drawn_view.hand[3].cooldown == 0)
  Director.on_state("host_peer", { p = "waiting", m = "tarot", r = 90.0, b = 3, k = {}, sq = 22, w = 1, dn = 1, da = 999, z = 1, h = { { k = "a", n = "A", s = "rage", t = 2, b = {} } } })
  Director.update(5)
  check("client: the age is capped and a paused host freezes it", Director.view().drawn_age == 32, Director.view().drawn_age)
  Director.on_state("host_peer", { p = "waiting", m = "tarot", r = 90.0, b = 3, k = {}, sq = 23, w = 1, dn = 1, da = 4, z = 1, h = { { k = "a", n = "A", s = "rage", t = 2, b = {} } } })
  Director.update(5)
  check("client: a paused host's age does not run", math.abs(Director.view().drawn_age - 4) < 0.01, Director.view().drawn_age)  is_server = true

  -- rarity is the number: a chance of 1 or 2 is rare, anything higher is not
  settings.tarot_cards = 3; settings.tarot_seconds = 10; settings.interval_min = 100; settings.interval_max = 100
  only({ { "wave_small", 1, 0 }, { "wave_medium", 10, 0 }, { "wave_large", 10, 0 } })
  v = start(); Director.update(95)
  local flags = {}
  for _, cd in ipairs(sent[#sent].state.h) do flags[cd.k] = cd.r end
  check("rarity: in a hand dealt from weights 1, 10 and 10 only the lightest card is rare (synced r)", flags.wave_small == 1 and flags.wave_medium == 0 and flags.wave_large == 0, tostring(flags.wave_small) .. tostring(flags.wave_medium))
  only({ { "wave_small", 18, 0 }, { "wave_medium", 18, 0 }, { "wave_large", 18, 0 } })
  v = start(); Director.update(95)
  local any_rare = false
  for _, cd in ipairs(sent[#sent].state.h) do if cd.r == 1 then any_rare = true end end
  check("rarity: a chance above 2 is not rare, however the others are (chances 18 count as 10)", not any_rare)
  only({ { "wave_small", 1, 0 }, { "wave_medium", 1, 0 }, { "wave_large", 1, 0 } })
  v = start(); Director.update(95)
  any_rare = false
  for _, cd in ipairs(sent[#sent].state.h) do if cd.r == 1 then any_rare = true end end
  check("rarity: a chance of 1 is rare for every card that has it, even when all of them do (it is the number, not a comparison)", any_rare)
  only({ { "wave_small", 50, 0 }, { "wave_medium", 40, 0 }, { "wave_large", 30, 0 }, { "wave_huge", 20, 0 }, { "boss_ambush", 1, 0 } })
  settings.tarot_cards = 5
  v = start(); Director.update(95)
  local rare_keys = {}
  for _, cd in ipairs(sent[#sent].state.h) do if cd.r == 1 then rare_keys[#rare_keys + 1] = cd.k end end
  check("rarity: with chances 50 (counted as 10) down to 1 only the card with a chance of 1 is rare", #rare_keys == 1 and rare_keys[1] == "boss_ambush", table.concat(rare_keys, ","))
  settings.tarot_cards = 3

  -- legacy modes still work next to the tarot
  settings.mode = "random"
  only({ { "wave_small", 5, 0 } })
  v = start()
  check("legacy: random mode is unchanged (one pending wave, no hand)", v.mode == "random" and #v.cands == 1 and v.hand == nil)
  settings.mode = "vote"; settings.ballot_size = 3
  only({ { "wave_small", 5, 0 }, { "wave_medium", 5, 0 }, { "wave_large", 5, 0 } })
  v = start()
  check("legacy: vote mode is unchanged (a ballot of 3, no hand)", v.mode == "vote" and #v.cands == 3 and v.hand == nil)
  settings.mode = "tarot"
  v = start()
  check("tarot: 'tarot' selected explicitly", v.mode == "tarot" and #v.cands == 0)
  settings.mode = "something odd"
  check("tarot: an unknown mode value means tarot", start().mode == "tarot")
  reset_settings(); settings.ballot_size = nil
  settings.interval_min = 100; settings.interval_max = 100
  Director.on_exit_gameplay(); started_waves = {}; started_defs = {}
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
  check("find: built-in wave by its displayed name", found("The Fool") == "wave_small" and found("the hunt") == "hound_frenzy" and found("hound_frenzy") == "hound_frenzy" and found("Rain of Rot") == "grenade_legion")
  check("find: unique prefix", found("mutants_ever") == "custom_2" and found("the_dev") == "boss_ambush" and found("the_watch") == "sniper_elite")
  check("find: unique substring", found("everywhere") == "custom_2")
  local amb2_key, amb2_err = found("the")
  check("find: a substring shared by two waves (The Fool, The Pilgrims: 'the_p' is no prefix of both, 'the' is) is ambiguous", amb2_key == nil and amb2_err:find("The Fool") ~= nil and amb2_err:find("The Pilgrims") ~= nil, amb2_err)
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
  local cok, cnote = Director.fire_now("dog party", { close = true })
  check("director.fire_now with close: the wave is marked close (and still a test), and the answer says where it spawns", cok and started_defs[#started_defs].close == true and started_defs[#started_defs].test == true and cnote == "spawning right in front of you", tostring(cnote))
  ring_level = true
  local _, cnote2 = Director.fire_now("dog party", { close = true })
  check("director.fire_now with close never talks about the ring, even on a level without spawn points", cnote2 == "spawning right in front of you", tostring(cnote2))
  ring_level = false
  Director.fire_now("dog party")
  check("director.fire_now without options is not close", started_defs[#started_defs].close == nil)
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
mod.hook_safe = function(self, cls, method, fn) hooks[(type(cls) == "table" and (cls._name or "table") or cls) .. "." .. method .. "!"] = fn end
local hook_requires = {}
mod.hook_require = function(self, path, fn) hook_requires[path] = fn end
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
    local unit = { breed = breed, buffs = make_buff_ext(breed), aggro = param.optional_aggro_state, init_toughness = param.optional_init_toughness, side = side_id, spawn_flag = Bypass.spawning, pos = pos, rot = rot, target = param.optional_target_unit }
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
local CS = { calls = 0, fail = false, reason = nil } -- /rw_test_close stub state (one local: the harness chunk is near Lua's limit of 200)
local StubPositions = {
  -- /rw_test_close: the local player's own spot, no cache, facing them
  close_candidates = function() CS.calls = CS.calls + 1; if CS.fail then return nil, CS.reason end return { "front" } end,
  local_player_unit = function() return "me" end,
  rotation_towards = function(position, unit) return "faces:" .. tostring(unit) end,
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
do
  local fault = { rotation = Unit.world_rotation, facing = StubPositions.rotation_towards }
  Unit.world_rotation = function() error("target unit despawned") end
  StubPositions.rotation_towards = function() return nil end
  fault.ok = pcall(run_wave, { name = "gone target", close = true, parts = Groups.parse("1 hound") })
  check("execute: a despawn during close-wave facing is contained and releases the spawn bypass", fault.ok and not Bypass.spawning and #spawned == 0)
  Unit.world_rotation, StubPositions.rotation_towards = fault.rotation, fault.facing
  Execute.cancel(); Bypass.reset()
end
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

-- /rw_test_close: right in front of the local player, facing them
do
  Execute.reset(); Bypass.reset()
  CS.calls, cand_calls, ring_calls, spread_calls = 0, 0, 0, {}
  run_wave({ name = "t", test = true, close = true, spread = 6, parts = Groups.parse("3 hounds") })
  check("close: the units come from the close candidates, never from the hidden-point search or the ring", #spawned == 3 and CS.calls >= 1 and cand_calls == 0 and ring_calls == 0, #spawned .. " " .. CS.calls .. " " .. cand_calls)
  check("close: the units face the local player and aggro on them (a random player is not used)", spawned[1].rot == "faces:me" and spawned[1].target == "me" and spawned[1].pos == "pos+2", tostring(spawned[1].rot) .. " " .. tostring(spawned[1].pos))
  local capped = #spread_calls == 3
  for _, r in ipairs(spread_calls) do if r ~= 2 then capped = false end end
  check("close: a wave's own spread (6) is capped at 2 m so the units stay in front of the player", capped)
  spread_calls = {}
  run_wave({ name = "t", test = true, close = true, spread = 1, parts = Groups.parse("1 hound") })
  check("close: a smaller spread than the cap is kept", spread_calls[1] == 1)
  CS.calls, cand_calls = 0, 0
  run_wave({ name = "t", test = true, spread = 6, parts = Groups.parse("2 hounds") })
  check("close: an ordinary test wave is untouched (hidden-point search, random player, the player's rotation)", CS.calls == 0 and cand_calls >= 1 and spawned[1].rot == "rot" and spawned[1].target == "player")

  -- no walkable ground in front of the player: nothing spawns, the reason is said once, spawning resumes when the way is clear
  Execute.reset(); Bypass.reset()
  CS.fail, CS.reason = true, "no walkable ground right in front of you (a wall?): turn towards open ground"
  local before = #echoes
  spawned = {}
  Execute.start_wave({ name = "Wall", test = true, close = true, parts = Groups.parse("4 hounds") })
  for _ = 1, 30 do Execute.update(0.2) end
  local said = 0; for i = before + 1, #echoes do if echoes[i]:find("Wall", 1, true) and echoes[i]:find("turn towards open ground", 1, true) then said = said + 1 end end
  check("close: with a wall in front nothing spawns and the reason is echoed exactly once", #spawned == 0 and said == 1, #spawned .. " " .. said)
  CS.fail = false
  for _ = 1, 30 do Execute.update(0.2) end
  check("close: ...and the wave spawns by itself once there is room", #spawned == 4, #spawned)
  Execute.reset(); Bypass.reset()

  -- the local player is gone mid-wave: no unit, nothing spawns, nothing breaks
  local saved_local, saved_random = StubPositions.local_player_unit, StubPositions.random_player_unit
  StubPositions.local_player_unit = function() return nil end
  StubPositions.random_player_unit = function() return nil end
  CS.fail, CS.reason = true, "no living players"
  spawned = {}
  local ok_gone = Execute.start_wave({ name = "t", test = true, close = true, parts = Groups.parse("2 hounds") })
  for _ = 1, 10 do Execute.update(0.2) end
  check("close: with no local player unit the wave waits quietly (no crash, nothing spawned)", ok_gone and #spawned == 0)
  StubPositions.local_player_unit, StubPositions.random_player_unit = saved_local, saved_random
  CS.fail = false
  for _ = 1, 20 do Execute.update(0.2) end
  check("close: ...and goes on when the player is back", #spawned == 2, #spawned)
  Execute.reset(); Bypass.reset()
end

-- custom mods on spawned units (spawn/tuning.lua) against stubbed extensions ---------------------------------------------
do
  local Tuning = load("spawn/tuning")
  local sent_scales = {}
  local fake_protocol = { is_available = function() return true end, send_scales = function(list, recipient) sent_scales[#sent_scales + 1] = { list = list, recipient = recipient }; return true end }
  Tuning.init({ protocol = fake_protocol })
  local dead, scales_set, next_gid = {}, {}, 100
  local saved_su, saved_unit, saved_v3, saved_spawner = ScriptUnit, Unit, Vector3, Managers.state.unit_spawner
  ScriptUnit = {
    has_extension = function(unit, sys) if sys == "buff_system" then return unit.buffs end return unit.ext and unit.ext[sys] end,
    extension = function(unit, sys) local ext = unit.ext and unit.ext[sys]; if not ext then error("no extension " .. tostring(sys)) end return ext end,
  }
  Unit = {
    world_rotation = function() return "rot" end,
    alive = function(unit) return not dead[unit] end,
    set_local_scale = function(unit, node, v) scales_set[#scales_set + 1] = { unit = unit, node = node, x = v.x, y = v.y, z = v.z } end,
  }
  Vector3 = function(x, y, z) return { x = x, y = y, z = z } end
  Managers.state.unit_spawner = { game_object_id = function(self, unit) return unit.gid end }
  -- health: the game ADDS the Havoc / mission share to the spawn parameter (minion_spawn_manager.lua:137-165)
  local saved_difficulty, saved_gamesession = Managers.state.difficulty, GameSession
  local normal_hp = { chaos_plague_ogryn = 1000, chaos_beast_of_nurgle = 2000, chaos_poxwalker = 100 }
  Managers.state.difficulty = { get_minion_max_health = function(self, breed) return normal_hp[breed] or 400 end }
  local synced_health = {}
  GameSession = { set_game_object_field = function(session, id, field, value) synced_health[#synced_health + 1] = { session = session, id = id, field = field, value = value } end }
  local havoc_extra = 0
  local no_game_object = nil -- a breed whose units come without a game object
  local boss_breeds = {}
  local function make_unit(breed, param)
    local unit = { breed = breed, gid = next_gid, health_mod = param.optional_health_modifier, buffs = make_buff_ext(breed) }
    next_gid = next_gid + 1
    unit.buffs.stats = {}
    unit.buffs.stat_buffs = function(self) return self.stats end
    unit.ext = {
      health_system = {
        mass = 2, hit_mass = function(self) return self.mass end, set_hit_mass = function(self, v) self.mass = v end,
        _health = (normal_hp[breed] or 400) * ((param.optional_health_modifier or 1) + havoc_extra),
        max_health = function(self) return self._health end,
        _game_session = breed ~= no_game_object and "session" or nil, _game_object_id = breed ~= no_game_object and unit.gid or nil,
      },
      navigation_system = { mods = {}, add_movement_modifier = function(self, m) self.mods[#self.mods + 1] = m; return #self.mods end },
      unit_data_system = { breed = function() return { name = breed } end },
    }
    if breed == "chaos_hound" then unit.ext.navigation_system = nil end -- a unit without navigation: that step fails alone
    -- bosses: the game marks one spawned with less than its normal health as weakened (boss_extension.lua:61-66)
    if breed == "chaos_plague_ogryn" or breed == "chaos_beast_of_nurgle" then
      unit.ext.boss_system = { _is_weakened = unit.ext.health_system._health < normal_hp[breed] and true or nil }
      unit.ext.unit_data_system = { breed = function() return boss_breeds[breed] end }
      boss_breeds[breed] = boss_breeds[breed] or { name = breed }
    end
    return unit
  end
  local saved_spawn = minion_spawn.spawn_minion
  minion_spawn.spawn_minion = function(self, breed, pos, rot, side_id, param)
    local unit = make_unit(breed, param)
    spawned[#spawned + 1] = unit
    return unit
  end
  Execute.init({ positions = StubPositions, bypass = Bypass, groups = Groups, tuning = Tuning })
  Bypass.reset(); Tuning.reset()

  run_wave({ name = "t", parts = Groups.parse("2 crushers[enraged]{health=150 size=130 speed=120 gap=40 fire=200 burst=300 mass=250}, 1 poxwalker") })
  local crushers, plain = {}, nil
  for _, u in ipairs(spawned) do if u.breed == "chaos_ogryn_executor" then crushers[#crushers + 1] = u else plain = u end end
  local c = crushers[1]
  check("tuning: health is a spawn parameter (x1.5); a group without custom mods gets none", #crushers == 2 and c.health_mod == 1.5 and crushers[2].health_mod == 1.5 and plain and plain.health_mod == nil)
  check("tuning: hit mass is multiplied (2 -> 5) and the run speed gets a movement modifier of 1.2", c.ext.health_system.mass == 5 and #c.ext.navigation_system.mods == 1 and c.ext.navigation_system.mods[1] == 1.2 and plain.ext.health_system.mass == 2 and #plain.ext.navigation_system.mods == 0)
  check("tuning: time between attacks 40 writes melee_attack_speed x2.5 (100 / 40), the fire rate and the burst size go to the stat buffs", c.buffs.stats.melee_attack_speed == 2.5 and c.buffs.stats.ranged_attack_speed == 2 and c.buffs.stats.minion_num_shots_modifier == 3 and plain.buffs.stats.melee_attack_speed == nil)
  check("tuning: the modifiers are added first (Enraged), the custom mods after", c.buffs.added[1] == "havoc_enraged_enemies")
  local scaled_c = 0; for _, s in ipairs(scales_set) do if s.unit == c and s.node == 1 and math.abs(s.x - 1.3) < 1e-9 and s.x == s.z then scaled_c = scaled_c + 1 end end
  check("tuning: the size is the unit's root scale (node 1, 1.3 on every axis); nothing for the plain unit", scaled_c == 1 and (function() for _, s in ipairs(scales_set) do if s.unit == plain then return false end end return true end)())

  -- the buff system rewrites a stat (a debuff changed): our factor goes back on top, once
  c.buffs.stats.melee_attack_speed = 1.2
  Tuning.update(0.3)
  check("tuning: a stat the buff system rewrote gets the factor again (1.2 x 2.5 = 3)", math.abs(c.buffs.stats.melee_attack_speed - 3.0) < 1e-9 and c.buffs.stats.ranged_attack_speed == 2)
  Tuning.update(0.3); Tuning.update(0.3)
  check("tuning: ...and is not multiplied again while nothing changes", math.abs(c.buffs.stats.melee_attack_speed - 3.0) < 1e-9)
  local sent_ids, sent_count = {}, 0
  for _, batch in ipairs(sent_scales) do if batch.recipient == nil then for _, e in ipairs(batch.list) do sent_ids[e[1]] = e[2]; sent_count = sent_count + 1 end end end
  check("tuning: the new sizes are sent to the other players, [network id, percent] for every tuned unit (the batches depend on how the spawns fall into the frames)", #sent_scales >= 1 and sent_scales[1].recipient == nil and sent_count == 2 and sent_ids[crushers[1].gid] == 130 and sent_ids[crushers[2].gid] == 130)
  local sends = #sent_scales
  Tuning.update(0.3)
  check("tuning: a size is sent once", #sent_scales == sends)
  dead[crushers[2]] = true
  Tuning.update(0.3)
  check("tuning: dead units are dropped", Tuning.status().tuned == 1 and Tuning.status().sizes_known == 1, Tuning.status().tuned)
  Tuning.send_all("late_peer")
  check("tuning: a player who joins late gets the size of every living unit that has one", sent_scales[#sent_scales].recipient == "late_peer" and #sent_scales[#sent_scales].list == 1 and sent_scales[#sent_scales].list[1][1] == c.gid)

  -- the buff system recomputes the stats every frame while a buff touches them: a hook puts the factor back at once
  Tuning.install()
  local stat_hook = hooks["BuffExtensionBase._update_stat_buffs_and_keywords!"]
  check("tuning: a hook on the buff system's stat recompute is installed", stat_hook ~= nil)
  c.buffs.stats.melee_attack_speed = 1.2 -- a recompute dropped our factor (a mission-wide modifier did it)
  stat_hook(c.buffs, 5)
  check("tuning: right after a recompute the factor is back on top (1.2 x 2.5), once", math.abs(c.buffs.stats.melee_attack_speed - 3.0) < 1e-9)
  stat_hook(c.buffs, 5)
  check("tuning: ...and a second call without a recompute changes nothing", math.abs(c.buffs.stats.melee_attack_speed - 3.0) < 1e-9)
  stat_hook({ stat_buffs = function() return {} end }, 5)
  check("tuning: the hook ignores units that are not tuned", true)

  -- the game's real recompute (buff_extension_base.lua:318-354, buff.lua:689-733), reduced: the stats listed in
  -- _modified_stats go back to their base value, then every buff is added (additive: +, multiplicative: *).
  -- The user's console log of 2026-10-02: under Havoc the gunner read speed 1.3 and 2.25 shots, never our factor.
  local BASE_STAT = { ranged_attack_speed = 1, minion_num_shots_modifier = 1, melee_attack_speed = 1 }
  local MULTIPLICATIVE = { minion_num_shots_modifier = true }
  local function sim_unit(buff_list)
    local ext = { buff_list = buff_list, recomputes = 0 }
    local stats = setmetatable({ _modified_stats = {} }, { __index = function(s, k) local v = BASE_STAT[k]; s[k] = v; return v end })
    ext.stat_buffs = function(self) return stats end
    ext.recompute = function(self)
      self.recomputes = self.recomputes + 1
      for key in pairs(stats._modified_stats) do stats[key] = BASE_STAT[key] end
      for key in pairs(stats._modified_stats) do stats._modified_stats[key] = nil end
      local reset_hook=hooks["MinionBuffExtension._reset_stat_buffs!"]
      if reset_hook then reset_hook(self) end
      for _, buff in ipairs(self.buff_list) do
        for key, value in pairs(buff) do
          if MULTIPLICATIVE[key] then stats[key] = stats[key] * value else stats[key] = stats[key] + value end
          stats._modified_stats[key] = true
        end
      end
    end
    return { buffs = ext }, ext, stats
  end
  local HAVOC_RANGED = { ranged_attack_speed = 0.3, minion_num_shots_modifier = 2.25 } -- havoc_ranged_attack_speed_05
  local minion_hook = hooks["MinionBuffExtension._update_stat_buffs_and_keywords!"]
  check("recompute: the subclass MinionBuffExtension is hooked too (the game's class() copies the parent's methods into it)", minion_hook ~= nil)

  local g_unit, g_ext, g_stats = sim_unit({ HAVOC_RANGED })
  g_ext:recompute()
  check("recompute: the model reproduces the log (a Havoc unit reads 1.3 and 2.25)", math.abs(g_stats.ranged_attack_speed - 1.3) < 1e-9 and math.abs(g_stats.minion_num_shots_modifier - 2.25) < 1e-9)
  Tuning.apply(g_unit, { fire = 25, burst = 500 }, "renegade_gunner")
  g_ext:recompute()
  check("recompute: without the hook the factor is lost at once (what the user saw)", math.abs(g_stats.ranged_attack_speed - 1.3) < 1e-9)
  minion_hook(g_ext, 5)
  check("recompute: right after the hook the unit reads Havoc x ours (1.3 x 0.25, 2.25 x 5)", math.abs(g_stats.ranged_attack_speed - 0.325) < 1e-9 and math.abs(g_stats.minion_num_shots_modifier - 11.25) < 1e-9, tostring(g_stats.ranged_attack_speed) .. "/" .. tostring(g_stats.minion_num_shots_modifier))
  for _ = 1, 5 do g_ext:recompute(); minion_hook(g_ext, 5) end
  check("recompute: every frame for a while gives the same value, nothing compounds", math.abs(g_stats.ranged_attack_speed - 0.325) < 1e-9 and math.abs(g_stats.minion_num_shots_modifier - 11.25) < 1e-9)
  stat_hook(g_ext, 5)
  minion_hook(g_ext, 5)
  check("recompute: both hooks in a row (a unit that reaches both) change nothing the second time", math.abs(g_stats.ranged_attack_speed - 0.325) < 1e-9 and math.abs(g_stats.minion_num_shots_modifier - 11.25) < 1e-9)
  g_ext.buff_list = {}
  g_ext:recompute(); minion_hook(g_ext, 5)
  check("recompute: the Havoc buff leaving the unit leaves our factor on the base value", math.abs(g_stats.ranged_attack_speed - 0.25) < 1e-9 and math.abs(g_stats.minion_num_shots_modifier - 5) < 1e-9, tostring(g_stats.ranged_attack_speed))

  -- a buff that arrives AFTER the stats were written (a debuff from a player, an Enraged modifier): the key was listed as
  -- modified, so the recompute starts from the base value and the factor is applied once, not on top of a buff twice
  local late_unit, late_ext, late_stats = sim_unit({})
  Tuning.apply(late_unit, { fire = 200, burst = 300 }, "renegade_gunner")
  check("recompute: written on a unit with no buff, the stats read x2 and x3", late_stats.ranged_attack_speed == 2 and late_stats.minion_num_shots_modifier == 3)
  late_ext.buff_list = { HAVOC_RANGED }
  late_ext:recompute(); minion_hook(late_ext, 5)
  check("recompute: a buff that arrives later is added to the base, then the factor once (1.3 x 2, 2.25 x 3)", math.abs(late_stats.ranged_attack_speed - 2.6) < 1e-9 and math.abs(late_stats.minion_num_shots_modifier - 6.75) < 1e-9, tostring(late_stats.ranged_attack_speed) .. "/" .. tostring(late_stats.minion_num_shots_modifier))
  Tuning.update(0.3)
  check("recompute: the fallback timer leaves a correct value alone", math.abs(late_stats.ranged_attack_speed - 2.6) < 1e-9)
  local equal_unit,equal_ext,equal_stats=sim_unit({})
  Tuning.apply(equal_unit,{fire=200},"renegade_gunner")
  equal_ext.buff_list={{ranged_attack_speed=1}}
  equal_ext:recompute(); minion_hook(equal_ext,5)
  check("recompute: a fresh base equal to the last tuned value still gets its factor", equal_stats.ranged_attack_speed==4)
  stat_hook(equal_ext,5); minion_hook(equal_ext,5)
  check("recompute: a reset notification is consumed once across both hooks", equal_stats.ranged_attack_speed==4)

  -- a stat table without _modified_stats (a stub, or a game that changes) is still written
  local plain_unit = { buffs = { stats = {} } }
  plain_unit.buffs.stat_buffs = function(self) return self.stats end
  Tuning.apply(plain_unit, { fire = 50 }, "renegade_gunner")
  check("recompute: a stat table without _modified_stats is written all the same", plain_unit.buffs.stats.ranged_attack_speed == 0.5)

  -- the factor a custom mod writes: a TIME (gap) is inverted into the game's speed, the others are plain percents
  check("tuning: factor_for, gap is a time (40 -> x2.5, 200 -> x0.5), the others a share, 100 or nonsense is nothing", Tuning.factor_for("gap", 40) == 2.5 and Tuning.factor_for("gap", 200) == 0.5 and Tuning.factor_for("gap", 100) == nil and Tuning.factor_for("gap", 0) == nil and Tuning.factor_for("gap", "x") == nil and Tuning.factor_for("fire", 200) == 2 and Tuning.factor_for("explosion", 0) == 0 and Tuning.factor_for("dot", nil) == nil)

  -- the melee attack that has just started (BtMeleeAttackAction._start_attack_anim, bt_melee_attack_action.lua:259-271):
  -- the game ends it at t + max(duration / speed, T + 0.2667) with T = the stop of the FIRST hit of a chained sweep
  local fix = hooks["BtMeleeAttackAction._start_attack_anim!"]
  check("tuning: a hook after the start of every melee attack is installed", fix ~= nil)
  local COMBO = { { 1.0962962962962963, 1.2148148148148148 }, { 1.8074074074074074, 1.9259259259259258 }, { 2.696296296296296, 2.8444444444444446 } }
  local PLAGUE = { attack_anim_durations = { attack_sword_combo = 3.5555555555555554, attack_swing = 1.6 } }
  local function game_end(t0, base, speed, timings)
    local first = type(timings[1]) == "table" and timings[1][2] or timings[1]
    return t0 + math.max(base / speed, first + 0.26666666666666666)
  end
  local function pad(speed, timings, event, base, kind)
    return { melee_attack_speed = speed, attack_type = kind or "sweep", attack_sweep_timings = timings, attack_event = event, attack_duration = game_end(10, base, speed, timings) }
  end
  local p1 = pad(2.5, COMBO, "attack_sword_combo", 3.5555555555555554)
  check("chain: at x2.5 the game's own end of the Plague Ogryn combo is before its second hit (the bug the user saw)", p1.attack_duration - 10 < COMBO[2][1], p1.attack_duration - 10)
  fix(nil, c, nil, nil, 10, nil, p1, PLAGUE)
  check("chain: for a unit with a custom time between attacks the attack lasts until the LAST hit plus 0.27 s", math.abs((p1.attack_duration - 10) - (2.8444444444444446 + 0.26666666666666666)) < 1e-9, p1.attack_duration - 10)
  check("chain: ...so every hit of the combo is inside it", p1.attack_duration - 10 > COMBO[1][2] and p1.attack_duration - 10 > COMBO[2][2] and p1.attack_duration - 10 > COMBO[3][2])
  local p2 = pad(2.5, COMBO, "attack_sword_combo", 3.5555555555555554)
  local untouched = p2.attack_duration
  fix(nil, plain, nil, nil, 10, nil, p2, PLAGUE)
  check("chain: a unit without custom mods is left alone (the game's own behaviour, also under Havoc)", p2.attack_duration == untouched)
  local fire_only = nil
  run_wave({ name = "t", parts = Groups.parse("1 mauler{fire=150}") })
  for _, u in ipairs(spawned) do if u.breed == "renegade_executor" then fire_only = u end end
  local p3 = pad(2.5, COMBO, "attack_sword_combo", 3.5555555555555554)
  untouched = p3.attack_duration
  fix(nil, fire_only, nil, nil, 10, nil, p3, PLAGUE)
  check("chain: a tuned unit without a custom time between attacks is left alone too", p3.attack_duration == untouched)
  local slow = nil
  run_wave({ name = "t", parts = Groups.parse("1 crusher{gap=200}") })
  for _, u in ipairs(spawned) do if u.breed == "chaos_ogryn_executor" then slow = u end end
  local p4 = pad(0.5, COMBO, "attack_sword_combo", 3.5555555555555554)
  untouched = p4.attack_duration
  fix(nil, slow, nil, nil, 10, nil, p4, PLAGUE)
  check("chain: a LONGER time between attacks (x0.5) is never shortened by the correction (7.1 s stays 7.1 s)", p4.attack_duration == untouched and math.abs(p4.attack_duration - 10 - 7.111111111111111) < 1e-9, p4.attack_duration)
  local single = pad(2.5, { 0.5, 0.8 }, "attack_swing", 1.6)
  fix(nil, c, nil, nil, 10, nil, single, PLAGUE)
  check("chain: a single sweep is kept until its sweep has stopped (0.8 + 0.27), the game used its start (0.5 + 0.27)", math.abs((single.attack_duration - 10) - 1.0666666666666667) < 1e-9, single.attack_duration - 10)
  local oobb = { melee_attack_speed = 2.5, attack_type = "oobb", attack_timings = { 0.5, 1.0 }, attack_event = "attack_swing", attack_duration = 11 }
  fix(nil, c, nil, nil, 10, nil, oobb, PLAGUE)
  check("chain: attacks that are not sweeps are left alone (the game already waits for their last timing)", oobb.attack_duration == 11)
  local calm = pad(1, COMBO, "attack_sword_combo", 3.5555555555555554); calm.melee_attack_speed = nil
  untouched = calm.attack_duration
  fix(nil, c, nil, nil, 10, nil, calm, PLAGUE)
  check("chain: a unit whose attack speed stat is 1 (the game stores nothing) is left alone", calm.attack_duration == untouched)

  -- things that can go wrong in a real match must never break an attack
  local logged_before = #echoes
  local ok_all = pcall(function ()
    fix(nil, c, nil, nil, 10, nil, nil, PLAGUE)                                        -- no scratchpad
    fix(nil, c, nil, nil, 10, nil, pad(2.5, COMBO, "attack_sword_combo", 1), nil)      -- no action data
    fix(nil, c, nil, nil, 10, nil, pad(2.5, COMBO, "unknown_event", 1), PLAGUE)        -- an event the action does not list
    fix(nil, c, nil, nil, nil, nil, pad(2.5, COMBO, "attack_sword_combo", 1), PLAGUE)  -- no time
    fix(nil, nil, nil, nil, 10, nil, pad(2.5, COMBO, "attack_sword_combo", 1), PLAGUE) -- the unit is gone
    fix(nil, { dead = true, buffs = nil }, nil, nil, 10, nil, pad(2.5, COMBO, "attack_sword_combo", 1), PLAGUE) -- no buff extension any more
    fix(nil, c, nil, nil, 10, nil, { melee_attack_speed = 2.5, attack_type = "sweep", attack_sweep_timings = { "bad" }, attack_event = "attack_sword_combo", attack_duration = 11 }, PLAGUE) -- damaged timings
    fix(nil, c, nil, nil, 10, nil, { melee_attack_speed = 2.5, attack_type = "sweep", attack_sweep_timings = {}, attack_event = "attack_sword_combo", attack_duration = 11 }, PLAGUE)  -- an empty list
  end)
  check("chain: missing or damaged data (no scratchpad, no action data, an unknown event, no time, a gone unit, bad timings) never raises", ok_all)
  check("chain: ...and does not even log", #echoes == logged_before)
  Tuning.dead = true
  local p5 = pad(2.5, COMBO, "attack_sword_combo", 3.5555555555555554)
  untouched = p5.attack_duration
  fix(nil, c, nil, nil, 10, nil, p5, PLAGUE)
  check("chain: after a reload (the old instance is retired) the stale hook does nothing", p5.attack_duration == untouched)
  Tuning.dead = false
  fix = nil

  -- explosion and damage over time taken: a share of the damage, 0 = none
  run_wave({ name = "t", parts = Groups.parse("1 crusher{explosion=50 dot=25}, 1 mauler{explosion=0}") })
  local ex, ex0
  for _, u in ipairs(spawned) do if u.breed == "chaos_ogryn_executor" then ex = u else ex0 = u end end
  check("tuning: explosion 50 halves the damage taken from explosions; dot 25 sets burning, toxin and bleeding to a quarter", ex and ex.buffs.stats.damage_taken_from_explosions == 0.5 and ex.buffs.stats.damage_taken_from_burning == 0.25 and ex.buffs.stats.damage_taken_from_toxin == 0.25 and ex.buffs.stats.damage_taken_from_bleeding == 0.25 and ex.buffs.stats.melee_attack_speed == nil)
  check("tuning: 0 means no damage at all from that source (and is kept, it is not 'unchanged')", ex0 and ex0.buffs.stats.damage_taken_from_explosions == 0 and Groups.parse("1 crusher{explosion=0}")[1].tune.explosion == 0)

  -- a step that fails (no navigation on this unit) is logged once and does not stop the others
  local before = #echoes
  run_wave({ name = "t", parts = Groups.parse("2 hounds{speed=150 mass=200}") })
  local logged = 0; for i = before + 1, #echoes do if echoes[i]:find("run speed of chaos_hound was not changed", 1, true) then logged = logged + 1 end end
  check("tuning: a missing extension only skips that step (hit mass still changed) and is logged once", #spawned == 2 and spawned[1].ext.health_system.mass == 4 and logged == 1, logged)
  check("tuning: health_modifier is nil for 100 or nothing", Tuning.health_modifier({ health = 100 }) == nil and Tuning.health_modifier(nil) == nil and Tuning.health_modifier({ health = 250 }) == 2.5)

  -- health is exact: the game adds the Havoc / mission share to the spawn parameter, the player's number must come out as it is, and
  -- the game's own "weakened" word for a boss with less than its normal health stays
  local function run_hp(recipe, extra)
    havoc_extra = extra or 0
    synced_health = {}
    run_wave({ name = "t", parts = Groups.parse(recipe) })
    havoc_extra = 0
  end
  local function first(breed) for _, u in ipairs(spawned) do if u.breed == breed then return u end end end

  run_hp("1 plague ogryn{health=50}, 1 beast of nurgle{health=150}, 2 poxwalker{health=50}")
  local ogryn, beast = first("chaos_plague_ogryn"), first("chaos_beast_of_nurgle")
  check("health: a boss at 50 percent has half its normal health (500 of 1000), a boss at 150 one and a half (3000 of 2000), a poxwalker half", ogryn.ext.health_system._health == 500 and beast.ext.health_system._health == 3000 and first("chaos_poxwalker").ext.health_system._health == 50)
  check("weakened: the game's own mark stays: a boss with less than its normal health is weakened, one with more is not", ogryn.ext.boss_system._is_weakened == true and not beast.ext.boss_system._is_weakened)
  check("weakened: nothing hooks the boss health bar any more (the 'Weakened' name is the game's), and the old helpers are gone", hooks["HudElementBossHealth.event_boss_encounter_start"] == nil and Tuning.is_health_tuned == nil)
  check("health: when the game already made the exact number nothing is written to the game object", #synced_health == 0)

  run_hp("1 plague ogryn{health=50}", 0.3)
  ogryn = first("chaos_plague_ogryn")
  check("health: Havoc's +30 percent no longer changes the number: 50 percent is 500 (not 800); the extension and the synced field agree", ogryn.ext.health_system._health == 500 and #synced_health == 1 and synced_health[1].field == "health" and synced_health[1].value == 500 and synced_health[1].id == ogryn.gid and synced_health[1].session == "session", #synced_health)
  check("weakened: that boss is weakened (500 < 1000)", ogryn.ext.boss_system._is_weakened == true)

  run_hp("1 plague ogryn{health=80}", 0.5)
  ogryn = first("chaos_plague_ogryn")
  check("weakened: the mark is read again from the exact health (the game had made it from 1.3x: not weakened; 80 percent is weakened)", ogryn.ext.health_system._health == 800 and ogryn.ext.boss_system._is_weakened == true)

  run_hp("1 plague ogryn{health=150}", -0.6)
  ogryn = first("chaos_plague_ogryn")
  check("weakened: a modifier that LOWERED the health (the game made 0.9x: weakened) does not keep the mark once the exact 150 percent is set", ogryn.ext.health_system._health == 1500 and not ogryn.ext.boss_system._is_weakened)

  run_hp("1 plague ogryn, 2 poxwalkers", 0.3)
  ogryn = first("chaos_plague_ogryn")
  check("health: a group without custom health keeps Havoc's share untouched (1.3x), nothing is written", ogryn.ext.health_system._health == 1300 and #synced_health == 0 and ogryn.ext.boss_system._is_weakened == nil)

  run_hp("1 plague ogryn{health=100}", 0.3)
  check("health: 100 percent is 'unchanged' too, Havoc's share stays", first("chaos_plague_ogryn").ext.health_system._health == 1300 and #synced_health == 0)

  -- a unit whose game object does not exist yet, or without a health extension, or a game without a difficulty manager: logged once, the
  -- other steps (hit mass) still happen and the wave goes on
  local before = #echoes
  no_game_object = "chaos_spawn"
  run_hp("2 chaos spawn{health=50 mass=200}", 0.3)
  no_game_object = nil
  local logged = 0; for i = before + 1, #echoes do if echoes[i]:find("the exact health of chaos_spawn was not set", 1, true) and echoes[i]:find("the unit has no game object yet", 1, true) then logged = logged + 1 end end
  check("health: a unit without a game object is logged once, its hit mass is still changed and the wave goes on", #spawned == 2 and logged == 1 and first("chaos_spawn").ext.health_system.mass == 4, logged)
  check("health: ...and its health was not half-written (the extension keeps the value the game made)", math.abs(first("chaos_spawn").ext.health_system._health - 320) < 1e-6 and #synced_health == 0)

  before = #echoes
  local saved_diff = Managers.state.difficulty
  Managers.state.difficulty = nil
  run_hp("1 hound{health=50}")
  Managers.state.difficulty = saved_diff
  logged = 0; for i = before + 1, #echoes do if echoes[i]:find("the exact health of chaos_hound was not set", 1, true) and echoes[i]:find("no difficulty manager", 1, true) then logged = logged + 1 end end
  check("health: no difficulty manager (a hub, a hot reload in a menu) is logged and the spawn parameter's own health stays", #spawned == 1 and logged == 1 and first("chaos_hound").health_mod == 0.5)

  local exact_unit = { ext = { unit_data_system = { breed = function() return { name = "chaos_poxwalker" } end } } }
  check("health: a unit without a health extension raises (the caller logs it)", not pcall(Tuning.set_exact_health, exact_unit, "chaos_poxwalker", 0.5))
  local pox = { ext = { health_system = { _health = 100, max_health = function(self) return self._health end, _game_session = "s", _game_object_id = 7 }, unit_data_system = { breed = function() return { name = "chaos_poxwalker" } end } } }
  synced_health = {}
  check("health: an extreme factor never gives a unit less than 1 health, and the real breed of the unit decides the normal health", Tuning.set_exact_health(pox, "other_breed_name", 0.0001) == 1 and pox.ext.health_system._health == 1 and synced_health[1].value == 1)
  check("health: exact already -> returns the health, writes nothing", (function() synced_health = {}; return Tuning.set_exact_health(pox, "x", 0.01) == 1 and #synced_health == 0 end)())

  do
    local saved_set = GameSession.set_game_object_field
    GameSession.set_game_object_field = function() error("unit despawned during sync") end
    local hp = pox.ext.health_system._health
    check("health: a rejected native write leaves local health unchanged", not pcall(Tuning.set_exact_health, pox, "chaos_poxwalker", 0.5) and pox.ext.health_system._health == hp)
    GameSession.set_game_object_field = saved_set
  end

  -- ----------------------------------------------------------------------------- the burster's explosion follows its size
  do
    local normal_template = { name = "poxwalker_bomber", radius = 6, min_radius = 3, close_radius = 3, min_close_radius = 1, damage_profile = { id = "profile" }, vfx = { "fx" }, scalable_radius = true }
    local mild_template = { name = "poxwalker_bomber_mild", radius = 3, min_radius = 1.5, close_radius = 1.5, min_close_radius = 0.5, damage_profile = { id = "mild" } }
    local function burster_action() return { explode_position_node = "j_spine2", explosion_template = normal_template, explosion_template_mild = mild_template } end
    local seen
    local function original(self, unit, breed, blackboard, scratchpad, action_data, t)
      seen = { normal = action_data.explosion_template, mild = action_data.explosion_template_mild, unit = unit, t = t }
      return "boom"
    end
    local enter = hooks["BtChaosPoxwalkerExplodeAction.enter"]
    check("burster: a hook around the explosion action's enter is installed", enter ~= nil)

    run_wave({ name = "t", parts = Groups.parse("1 burster{size=200}, 1 burster{size=50}, 1 burster, 1 burster{health=150}") })
    -- which is which: by the size that was put on it (the order the wave spawns them in is not part of what is tested)
    local big, small, plain_b, healthy
    for _, u in ipairs(spawned) do
      if u.breed == "chaos_poxwalker_bomber" then
        local size
        for _, s in ipairs(scales_set) do if s.unit == u then size = s.x end end
        if size == 2 then big = u elseif size == 0.5 then small = u elseif u.health_mod == 1.5 then healthy = u else plain_b = u end
      end
    end
    check("burster: the four bursters were spawned (a size 200 one, a size 50 one, a plain one, a one with only health)", big and small and plain_b and healthy)

    local action = burster_action()
    local result = enter(original, "node", big, nil, nil, nil, action, 7)
    check("burster: at size 200 the blast is made with every radius doubled (6 m -> 12, 3 -> 6, close 3 -> 6, 1 -> 2) and the other fields unchanged", result == "boom" and seen.normal.radius == 12 and seen.normal.min_radius == 6 and seen.normal.close_radius == 6 and seen.normal.min_close_radius == 2 and seen.normal.name == "poxwalker_bomber" and seen.normal.damage_profile == normal_template.damage_profile and seen.normal.vfx == normal_template.vfx and seen.normal.scalable_radius == true, seen and seen.normal.radius)
    check("burster: the mild blast (a burster that dies by itself) is doubled too, and the arguments reach the game's function unchanged", seen.mild.radius == 6 and seen.mild.min_radius == 3 and seen.mild.close_radius == 3 and seen.mild.min_close_radius == 1 and seen.unit == big and seen.t == 7)
    check("burster: afterwards the action has its own templates back and the shared ones were never touched", action.explosion_template == normal_template and action.explosion_template_mild == mild_template and normal_template.radius == 6 and mild_template.radius == 3)
    enter(original, "node", small, nil, nil, nil, action, 7)
    check("burster: at size 50 the blast is half (3 m)", seen.normal.radius == 3 and seen.normal.close_radius == 1.5 and seen.mild.radius == 1.5)
    enter(original, "node", plain_b, nil, nil, nil, action, 7)
    check("burster: a burster without a custom size blasts with the game's own templates", seen.normal == normal_template and seen.mild == mild_template)
    enter(original, "node", healthy, nil, nil, nil, action, 7)
    check("burster: so does one with only other custom mods", seen.normal == normal_template)
    enter(original, "node", { name = "not ours" }, nil, nil, nil, action, 7)
    check("burster: and a unit that is not a wave unit at all", seen.normal == normal_template)

    local raised_ok, raised = pcall(enter, function() error("explosion failed") end, "node", big, nil, nil, nil, action, 7)
    check("burster: an error inside the game's explosion still reaches the game, and the templates are restored", raised_ok == false and tostring(raised):find("explosion failed", 1, true) ~= nil and action.explosion_template == normal_template and action.explosion_template_mild == mild_template)
    local nil_ok, nil_result = pcall(enter, function() return "plain" end, "node", big, nil, nil, nil, nil, 7)
    check("burster: no action data (damaged call) is handed to the game's function as it is, nothing raised by the hook", nil_ok and nil_result == "plain")
    local lerp_action = { explosion_template = { name = "lerped", radius = { 4, 8 }, min_radius = { 1, 2 }, close_radius = 2, label = "x" }, explosion_template_mild = nil }
    enter(original, "node", big, nil, nil, nil, lerp_action, 7)
    check("burster: a radius that is a table of two values (a template that lerps) is scaled entry by entry, a missing mild template stays missing", seen.normal.radius[1] == 8 and seen.normal.radius[2] == 16 and seen.normal.min_radius[2] == 4 and seen.normal.close_radius == 4 and seen.normal.label == "x" and seen.mild == nil and lerp_action.explosion_template.radius[1] == 4)
    check("burster: scaled_template of nothing or of nonsense returns it as it is", Tuning.scaled_template(nil, 2) == nil and Tuning.scaled_template("x", 2) == "x" and Tuning.scaled_template({ radius = 5 }, "bad").radius == 5 and Tuning.scaled_template({ radius = 5 }, -3).radius == 5 and Tuning.scaled_template({ radius = 5 }, 0).radius == 5)

    dead[big] = true
    Tuning.update(0.3)
    enter(original, "node", big, nil, nil, nil, action, 7)
    check("burster: a unit that is gone is forgotten (no growth over a long mission)", seen.normal == normal_template and Tuning.status().tuned >= 0)
    Tuning.dead = true
    enter(original, "node", small, nil, nil, nil, action, 7)
    check("burster: after a reload (the old instance is retired) the stale hook leaves the game's templates alone", seen.normal == normal_template)
    Tuning.dead = false
    Tuning.reset()
    enter(original, "node", small, nil, nil, nil, action, 7)
    check("burster: a mission restart forgets every size", seen.normal == normal_template)
  end

  -- ------------------------------------------------------------------ what a tuned shooter read (/rw_tune and the log)
  do
    local infos = {}
    mod.info = function(self, fmt, ...) infos[#infos + 1] = string.format(fmt, ...) end
    local install_shooting = hook_requires["scripts/utilities/minion_attack"]
    check("shooting: a hook on MinionAttack is registered through hook_require (the module may load after the mod)", install_shooting ~= nil)
    local fake_module = { _name = "MinionAttack" }
    install_shooting(fake_module)
    local shooting = hooks["MinionAttack.start_shooting!"]
    check("shooting: it hooks start_shooting after it ran", shooting ~= nil)

    Tuning.reset()
    run_wave({ name = "t", parts = Groups.parse("1 rifleman{fire=25 burst=500}, 1 scab{fire=200}, 1 hound") })
    local rifle, scab, hound
    for _, u in ipairs(spawned) do
      if u.breed == "renegade_rifleman" then rifle = u elseif u.breed == "renegade_melee" then scab = u elseif u.breed == "chaos_hound" then hound = u end
    end
    check("shooting: the shooters were spawned with their stats written (rifleman fire x0.25, burst x5)", rifle and rifle.buffs.stats.ranged_attack_speed == 0.25 and rifle.buffs.stats.minion_num_shots_modifier == 5, rifle and tostring(rifle.buffs.stats.ranged_attack_speed))
    local apply_lines = 0
    for _, l in ipairs(infos) do if l:find("custom stats written on renegade_rifleman: minion_num_shots_modifier x5.00 (stat now 5", 1, true) and l:find("ranged_attack_speed x0.25 (stat now 0.25)", 1, true) then apply_lines = apply_lines + 1 end end
    check("apply: the units written to the log show what was written and what the stat says right after", apply_lines == 1 and #infos == 2, #infos)
    infos = {}
    local hostile_ok = pcall(function ()
      shooting(rifle, nil, 10, {})
      shooting(rifle, { shoot_attack_speed = "x" }, nil, nil)
      shooting(nil, {}, 10, {})
    end)
    check("shooting: damaged arguments never raise", hostile_ok)
    for i = 1, 5 do
      shooting(rifle, { shoot_attack_speed = 0.25, num_shots = 15, next_shoot_timing = 12 }, 10, {})
    end
    check("shooting: only the first three starts of a breed are written to the log", #infos == 3 and infos[3]:find("renegade_rifleman started shooting: speed x0.25, 15 shots, first shot in 2", 1, true) ~= nil, #infos)
    shooting(hound, { shoot_attack_speed = 1, num_shots = 3, next_shoot_timing = 12 }, 10, {})
    shooting({ name = "not ours" }, { shoot_attack_speed = 1 }, 10, {})
    check("shooting: a unit with no custom stats, or one that is not a wave unit, is not logged", #infos == 3)
    local lines = Tuning.describe()
    local all = table.concat(lines, " | ")
    check("describe: one line per tuned breed with what was written, what the stat says now and what the last shot read", all:find("renegade_rifleman: ", 1, true) ~= nil and all:find("ranged_attack_speed written x0.25, now 0.25", 1, true) ~= nil and all:find("minion_num_shots_modifier written x5.00, now 5", 1, true) ~= nil and all:find("last shooting start: speed x0.25, 15 shots, first shot in 2", 1, true) ~= nil, all)
    check("describe: a tuned unit that has not shot yet says so", (function() for _, l in ipairs(lines) do if l:find("renegade_melee", 1, true) and l:find("has not started shooting", 1, true) then return true end end return false end)(), all)
    check("describe: a unit with no custom stat (the hound) has no line", not all:find("chaos_hound", 1, true))
    dead[rifle] = true
    dead[scab] = true
    Tuning.update(0.3)
    check("describe: with nothing alive it says so instead of printing nothing", Tuning.describe()[1]:find("No living unit", 1, true) ~= nil)
    mod.info = nil
    local quiet_ok = pcall(shooting, rifle, { shoot_attack_speed = 1 }, 10, {})
    check("shooting: a game without mod:info (or one that raises) is no problem", quiet_ok)
    Tuning.reset()
  end

  -- ------------------------------------------------------------------------- what can happen in a real match
  -- (players joining late, a player gone, a mission restarting, a game without the mod, damaged or doubled messages)
  do
    local before_units = Tuning.status().sizes_known
    local crowd = {}
    for i = 1, 250 do
      local u = { gid = 5000 + i, buffs = make_buff_ext("x") }
      u.buffs.stats = {}
      u.buffs.stat_buffs = function(self) return self.stats end
      crowd[i] = u
      Tuning.apply(u, { size = 150 }, "crowd")
    end
    sent_scales = {}
    Tuning.update(0.3)
    local flushed = 0
    for _, s in ipairs(sent_scales) do flushed = flushed + #s.list end
    check("join: 250 new sizes leave in batches of at most 100 (three messages), none lost", #sent_scales == 3 and flushed == 250 and #sent_scales[1].list == 100 and #sent_scales[3].list == 50, #sent_scales)
    sent_scales = {}
    Tuning.send_all("joiner")
    local to_joiner, per_message_ok = 0, true
    for _, s in ipairs(sent_scales) do
      to_joiner = to_joiner + #s.list
      if s.recipient ~= "joiner" or #s.list > 100 then per_message_ok = false end
    end
    check("join: a player who joins in the middle of a big fight gets every living size, only him, in batches of at most 100", per_message_ok and to_joiner == Tuning.status().sizes_known and to_joiner >= 250 and #sent_scales == math.ceil(to_joiner / 100), to_joiner)
    for i = 1, 100 do dead[crowd[i]] = true end
    sent_scales = {}
    Tuning.send_all("joiner_two")
    local after_deaths = 0
    for _, s in ipairs(sent_scales) do after_deaths = after_deaths + #s.list end
    check("join: units that died before he arrived are not sent", after_deaths == to_joiner - 100, after_deaths)
    Tuning.update(0.3)
    check("join: ...and the host forgets them (no growth over a long mission)", Tuning.status().sizes_known == to_joiner - 100, Tuning.status().sizes_known)

    -- a peer that left, or a network that fails, while sizes are going out
    local warning_start = #echoes
    fake_protocol.send_scales = function() error("peer is gone") end
    local failed_ok = pcall(Tuning.send_all, "crashed_player")
    Tuning.apply(crowd[200], { size = 120 }, "crowd")
    local update_ok = pcall(function () Tuning.update(0.3); Tuning.update(0.3) end)
    check("leave: a send to a player who crashed or left raises nothing (not in send_all, not in the host's update)", failed_ok and update_ok)
    local warned_send = 0
    for i=warning_start+1,#echoes do if echoes[i]:find("sizes could not be sent", 1, true) then warned_send = warned_send + 1 end end
    check("leave: ...and it is logged once, not every frame", warned_send == 1, warned_send)
    fake_protocol.send_scales = function(list, recipient) sent_scales[#sent_scales + 1] = { list = list, recipient = recipient }; return true end
    sent_scales = {}
    Tuning.send_all("next_joiner")
    check("leave: the next player is served normally afterwards", #sent_scales >= 1 and sent_scales[1].recipient == "next_joiner")
    fake_protocol.is_available = function() return false end
    sent_scales = {}
    Tuning.apply(crowd[201], { size = 130 }, "crowd")
    local quiet_ok = pcall(function () Tuning.update(0.3); Tuning.send_all("anyone") end)
    check("mods: without the Realms network (nobody to tell) nothing is sent and nothing fails", quiet_ok and #sent_scales == 0)
    check("network: pending live sizes survive a temporary outage", Tuning.status().unsent>0)
    fake_protocol.is_available = function() return true end
    Tuning.update(0.3)
    check("network: a recovered connection flushes pending sizes", Tuning.status().unsent==0 and #sent_scales>0)
    fake_protocol.send_scales=function() return false,"peer disconnected" end
    Tuning.apply(crowd[201],{size=125},"crowd"); Tuning.update(0.3)
    check("network: a returned send failure retains the size for retry", Tuning.status().unsent==1)
    fake_protocol.send_scales=function(list,recipient) sent_scales[#sent_scales+1]={list=list,recipient=recipient}; return true end
    Tuning.update(0.3)
    check("network: retries send the latest live value and clear the queue", Tuning.status().unsent==0 and sent_scales[#sent_scales].list[1][2]==125)
    local reentered=false
    fake_protocol.send_scales=function(list)
      sent_scales[#sent_scales+1]={list=list}
      if not reentered then reentered=true;Tuning.apply(crowd[201],{size=180},"crowd") end
      return true
    end
    Tuning.apply(crowd[201],{size=130},"crowd");Tuning.update(0.3)
    check("network: synchronous new size survives completion of the previous send", Tuning.status().unsent==1)
    Tuning.update(0.3)
    check("network: next cadence delivers reentrant latest value once", Tuning.status().unsent==0 and sent_scales[#sent_scales].list[1][2]==180)

    -- a unit that died: the stat hook and the end-of-attack hook no longer know it
    local gone = crowd[1]
    Tuning.apply(gone, { gap = 50 }, "crowd")
    dead[gone] = true
    Tuning.update(0.3)
    gone.buffs.stats.melee_attack_speed = 1.2
    stat_hook(gone.buffs, 5)
    check("leave: a dead unit's record is dropped, the stat hook leaves its stats alone (and nothing leaks)", gone.buffs.stats.melee_attack_speed == 1.2)
    check("leave: the mission restarting (Tuning.reset) forgets everything the host knew", (function() Tuning.reset(); local s = Tuning.status(); return s.tuned == 0 and s.sizes_known == 0 and s.unsent == 0 and s.pending == 0 end)())
  end

  -- the client side with a damaged or unlucky world
  do
    local saved_spawner2 = Managers.state.unit_spawner
    Managers.state.unit_spawner = nil
    Tuning.reset()
    Tuning.receive({ { id = 1, pct = 120 } })
    local nil_ok = pcall(Tuning.update_client, 1)
    check("client: before the game's unit spawner exists nothing fails and the size waits", nil_ok and Tuning.status().pending == 1)
    Managers.state.unit_spawner = { unit_exists = function() error("session is closing") end, unit = function() error("session is closing") end }
    local raising_ok = pcall(Tuning.update_client, 1)
    check("client: a spawner that raises (the session is closing) is contained and the size waits", raising_ok and Tuning.status().pending == 1)
    Tuning.update_client(25)
    check("client: ...and gives up after 20 s", Tuning.status().pending == 0)
    local flood = {}
    for i = 1, 1000 do flood[i] = { id = i, pct = 110 } end
    Tuning.receive(flood)
    check("client: a flood of sizes (a broken or hostile host) is capped at 600 waiting entries", Tuning.status().pending == 600, Tuning.status().pending)
    Tuning.reset()
    local present2, applied2 = { [9] = { name = "u9" } }, {}
    Managers.state.unit_spawner = { unit_exists = function(self, id) return present2[id] ~= nil end, unit = function(self, id) return present2[id] end }
    local saved_set_scale = Unit.set_local_scale
    Unit.set_local_scale = function(unit, node, v) applied2[#applied2 + 1] = v.x end
    Tuning.receive({ { id = 9, pct = 150 } })
    Tuning.receive({ { id = 9, pct = 150 } }) -- the host answered two hellos: the same size twice
    Tuning.update_client(0.1)
    check("client: duplicate sizes use one pending entry and one application", #applied2 == 1 and applied2[1] == 1.5 and Tuning.status().pending == 0)
    Tuning.receive({{id=9,pct=150}}); Tuning.receive({{id=9,pct=120}})
    Tuning.update_client(0.1)
    check("client: the newest received size wins, never the first message replayed in reverse", applied2[#applied2]==1.2 and Tuning.status().pending==0)
    local saved_lookup=Managers.state.unit_spawner.unit
    Managers.state.unit_spawner.unit=function() return nil end
    Tuning.receive({{id=9,pct=130}}); Tuning.update_client(0.1)
    check("client: existence before the unit handle arrives keeps the size pending", Tuning.status().pending==1)
    Managers.state.unit_spawner.unit=saved_lookup
    Tuning.update_client(0.1)
    check("client: the deferred size is applied once the handle arrives", applied2[#applied2]==1.3 and Tuning.status().pending==0)
    Tuning.receive(flood); Tuning.receive({{id=9,pct=180}})
    Tuning.update_client(0.1)
    check("client: an existing unit's newest size is accepted even with a full pending queue", applied2[#applied2]==1.8 and Tuning.status().pending==599)
    Unit.set_local_scale = saved_set_scale
    Managers.state.unit_spawner = saved_spawner2
    Tuning.reset()
  end

  -- the handshake of a player who joins: the director gives a late player the sizes, only when versions agree
  do
    local welcomed, sent_all = {}, {}
    local P3 = {
      PROTO = 2, VERSION = "2.0.0", is_available = function() return true end, send_state = function() return true end, send_hello = function() end,
      send_welcome = function(peer, ok) welcomed[#welcomed + 1] = { peer, ok } end, send_waves = function() return true end,
    }
    local fake_tuning = { send_all = function(peer) sent_all[#sent_all + 1] = peer end, receive = function() end, update_client = function() end, status = function() return { tuned = 0, sizes_known = 0, unsent = 0, pending = 0 } end }
    local D3 = load("core/director")
    D3.init({ events = Events, groups = Groups, protocol = P3, execute = Execute, votes = Votes, positions = Positions, presets = PresetsMod, cards = CardsMod, tuning = fake_tuning })
    is_server = true
    D3.on_hello("late_peer", 2, "2.0.0")
    check("handshake: a player with the same version is welcomed and gets the sizes of the units already out there", #welcomed == 1 and welcomed[1][2] == true and sent_all[1] == "late_peer")
    D3.on_hello("old_peer", 1, "1.0.0")
    check("handshake: a player with another version (older mod) is refused and gets no sizes", welcomed[2][2] == false and #sent_all == 1)
    fake_tuning.send_all = function() error("peer is gone") end
    local hello_ok = pcall(D3.on_hello, "flaky_peer", 2, "2.0.0")
    check("handshake: a player who drops while he is being served cannot break the host", hello_ok and welcomed[3] and welcomed[3][2] == true)
    is_server = false
    sent_all = {}
    fake_tuning.send_all = function(peer) sent_all[#sent_all + 1] = peer end
    D3.on_hello("someone", 2, "2.0.0")
    check("handshake: a non-host never answers a hello", #sent_all == 0 and #welcomed == 3)
    local got = 0
    fake_tuning.receive = function() got = got + 1 end
    D3.on_welcome("host_peer", 2, "9.9.9", false)
    D3.on_scale("host_peer", { { id = 1, pct = 120 } })
    check("handshake: a client that refused the host's version (the mod is disabled there) takes no sizes", got == 0)
    D3.on_welcome("host_peer", 2, "2.0.0", true)
    D3.on_scale("host_peer", { { id = 1, pct = 120 } })
    check("handshake: ...and takes them after a good welcome", got == 1)
    local D4 = load("core/director")
    D4.init({ events = Events, groups = Groups, protocol = P3, execute = Execute, votes = Votes, positions = Positions, presets = PresetsMod, cards = CardsMod })
    is_server = true
    local no_tuning_ok = pcall(D4.on_hello, "peer", 2, "2.0.0")
    is_server = false
    local no_tuning_scale = pcall(D4.on_scale, "host_peer", { { id = 1, pct = 120 } })
    is_server = true
    check("mods: a director built without the custom-mods module (an older install) still welcomes and ignores sizes", no_tuning_ok and no_tuning_scale)
  end

  -- the animation probe (/rw_anim): which engine functions and which animation variables exist, never an error
  do
    local function probe_unit(breed, vars, dead_unit)
      local u = { breed = breed, vars = vars or {}, is_dead = dead_unit }
      u.ext = { unit_data_system = { breed = function() return { name = breed } end } }
      return u
    end
    local saved_unit_table = Unit
    Unit = {
      animation_event = function() end, animation_set_variable = function() end, set_local_scale = function() end, world_position = function() end,
      animation_find_variable = function(unit, name) return unit.vars[name] end,
      animation_get_variable_min_max = function(unit, index) return 0.5, 2.5 end,
      alive = function(unit) return not unit.is_dead end,
      set_data = "not a function",
    }
    local crusher = probe_unit("chaos_ogryn_executor", { anim_move_speed = 3, attack_speed = 7 })
    local crusher2 = probe_unit("chaos_ogryn_executor", { anim_move_speed = 3 })
    local hound = probe_unit("chaos_hound", {})
    local gone = probe_unit("renegade_executor", { anim_move_speed = 1 }, true)
    local lines = Tuning.probe({ crusher, crusher2, hound, gone })
    local all = table.concat(lines, "\n")
    check("probe: the engine's functions about animation, speed, time, scale or rate are listed (sorted), others and non-functions are not", lines[1]:find("(5): animation_event, animation_find_variable, animation_get_variable_min_max, animation_set_variable, set_local_scale", 1, true) ~= nil, lines[1])
    check("probe: world_position and a non-function are not listed", not lines[1]:find("world_position", 1, true) and not lines[1]:find("set_data", 1, true))
    check("probe: a unit's candidate variables are listed with their range, the control variable included", all:find("chaos_ogryn_executor has animation variables: attack_speed (0.5 to 2.5), anim_move_speed (0.5 to 2.5)", 1, true) ~= nil, all)
    check("probe: one line per breed (the second crusher adds none)", select(2, all:gsub("chaos_ogryn_executor has", "")) == 1)
    check("probe: a breed with none of them says so", all:find("chaos_hound has animation variables: none of the candidates", 1, true) ~= nil)
    check("probe: a unit that is gone is skipped", all:find("renegade_executor", 1, true) == nil and #lines == 3, #lines)
    check("probe: no unit alive gives the hint", Tuning.probe({})[2]:find("spawn one first", 1, true) ~= nil and Tuning.probe(nil)[2]:find("spawn one first", 1, true) ~= nil)
    Unit.animation_find_variable = function() error("engine quirk") end
    local quirk_ok, quirk_lines = pcall(Tuning.probe, { crusher })
    check("probe: an engine call that raises is contained (that unit just has none)", quirk_ok and quirk_lines[2]:find("none of the candidates", 1, true) ~= nil)
    Unit = nil
    local no_engine_ok, no_engine = pcall(Tuning.probe, { crusher })
    check("probe: without the engine's Unit table it still answers (0 functions, and says the units cannot be looked at)", no_engine_ok and no_engine[1]:find("(0)", 1, true) ~= nil and no_engine[2]:find("cannot be looked at", 1, true) ~= nil, no_engine_ok and no_engine[2] or no_engine)
    Unit = saved_unit_table
  end

  -- a client puts the sizes on units when they exist there
  local present = {}
  Managers.state.unit_spawner = {
    unit_exists = function(self, id) return present[id] ~= nil end,
    unit = function(self, id) return present[id] end,
  }
  scales_set = {}
  Tuning.reset()
  Tuning.receive({ { id = 7, pct = 150 }, { id = 8, pct = 80 } })
  Tuning.update_client(1)
  check("tuning, client: nothing happens while the unit has not arrived", #scales_set == 0 and Tuning.status().pending == 2)
  local u7 = { name = "u7" }; present[7] = u7
  Tuning.update_client(1)
  check("tuning, client: the size goes on the unit as soon as it exists here", #scales_set == 1 and scales_set[1].unit == u7 and scales_set[1].x == 1.5 and Tuning.status().pending == 1)
  Tuning.update_client(25)
  check("tuning, client: a size whose unit never comes is dropped after 20 s", Tuning.status().pending == 0)

  -- the director hands sizes to Tuning on a client only
  local received = 0
  local D2 = load("core/director")
  D2.init({ events = Events, groups = Groups, protocol = Protocol, execute = Execute, votes = Votes, positions = Positions, presets = PresetsMod, cards = CardsMod, tuning = { receive = function() received = received + 1 end, update_client = function() end } })
  is_server = false; D2.on_scale("host", { { id = 1, pct = 120 } })
  is_server = true; D2.on_scale("peer", { { id = 1, pct = 120 } })
  check("director: sizes from the host reach Tuning on a client, never on the host", received == 1)

  -- A captured tuner can be reached after unload. Retirement must both release
  -- its existing records and prevent a late callback from repopulating them.
  Managers.state.unit_spawner.game_object_id=function(self,unit) return unit.gid end
  local old_stats={melee_attack_speed=1}
  local obsolete={gid=999,buffs={stat_buffs=function() return old_stats end}}
  local old_apply,old_receive=Tuning.apply,Tuning.receive
  Tuning.apply(obsolete,{gap=50,size=130})
  Tuning.receive({{id=999,pct=130}})
  local owned_status=Tuning.status()
  Tuning.retire()
  local retired_status=Tuning.status()
  check("retire: tuning releases all unit records and incoming/outgoing work", owned_status.tuned>0 and owned_status.sizes_known==1 and owned_status.unsent==1 and owned_status.pending==1 and retired_status.tuned==0 and retired_status.sizes_known==0 and retired_status.unsent==0 and retired_status.pending==0)
  old_stats.melee_attack_speed=1
  local scales_before=#scales_set
  old_apply(obsolete,{gap=50,size=130});old_receive({{id=999,pct=130}})
  Tuning.update(1);Tuning.update_client(1);stat_hook(obsolete.buffs,1)
  check("retire: obsolete apply/receive/update/stat hooks cannot repopulate records or change a unit", old_stats.melee_attack_speed==1 and #scales_set==scales_before and Tuning.status().tuned==0 and Tuning.status().pending==0)
  local snapshot_tuner=load("spawn/tuning")
  local snapshot_calls=0
  snapshot_tuner.init({protocol={is_available=function() return true end,send_scales=function() snapshot_calls=snapshot_calls+1;snapshot_tuner.retire();return false,"retired during send" end}})
  snapshot_tuner.apply(obsolete,{size=130})
  snapshot_tuner.send_all("peer")
  check("retire: a failed snapshot completing after synchronous retirement cannot recreate outgoing work", snapshot_calls==1 and snapshot_tuner.status().unsent==0 and snapshot_tuner.status().sizes_known==0)
  ScriptUnit, Unit, Vector3, Managers.state.unit_spawner = saved_su, saved_unit, saved_v3, saved_spawner
  Managers.state.difficulty, GameSession = saved_difficulty, saved_gamesession
  minion_spawn.spawn_minion = saved_spawn
  Execute.init({ positions = StubPositions, bypass = Bypass, groups = Groups })
  Tuning.reset(); Bypass.reset()
end

-- custom mods ("tuning") in the recipe ----------------------------------------------------------------------------------
do
  local parts = Groups.parse("3 crushers[enraged]{health=150 size=130}@2, 2 hounds")
  check("tune: '{health=150 size=130}' after the modifiers is read into part.tune (the repeat still works)", parts and parts[1].tune and parts[1].tune.health == 150 and parts[1].tune.size == 130 and parts[1].mods[1] == "enraged" and parts[1].rep == 2 and parts[1].count == 3 and parts[2].tune == nil, parts and parts[1].tune and Groups.tune_recipe(parts[1].tune))
  local again = Groups.parse(Groups.to_recipe(parts))
  check("tune: written back as text it reads back the same (to_recipe / parse)", Groups.to_recipe(parts) == "3 crusher[enraged]{health=150 size=130}@2, 2 hound" and again[1].tune.health == 150 and again[1].tune.size == 130 and again[1].rep == 2, Groups.to_recipe(parts))
  parts = Groups.parse("1 crusher {hp 200, run speed 120%, time between attacks=40; fire:200 / shots per burst 300 & hit mass 250}")
  local tune = parts and parts[1].tune or {}
  check("tune: names have aliases (hp, run speed, shots per burst...), separators can be spaces, commas, =, : and a % may follow the number", tune.health == 200 and tune.speed == 120 and tune.gap == 40 and tune.fire == 200 and tune.burst == 300 and tune.mass == 250, Groups.tune_recipe(tune))
  -- the setting was called "melee attack speed" (200 = twice as fast); it is the time between attacks now (50 = half the wait)
  parts = Groups.parse("2 crushers{melee=200}, 1 mauler{melee attack speed 125%}, 1 hound{attack speed=400}, 1 dreg{melee=100}, 1 scab{melee=0}")
  check("tune: an old recipe's melee=200 is read as gap=50 (the same behaviour), 125 as 80, 400 as 25, 100 as nothing, 0 as the longest time", parts[1].tune.gap == 50 and parts[2].tune.gap == 80 and parts[3].tune.gap == 25 and parts[4].tune == nil and parts[5].tune.gap == 400, parts and parts[1] and Groups.tune_recipe(parts[1].tune))
  check("tune: ...and it is written back with the new name", Groups.to_recipe(parts):find("crusher{gap=50}", 1, true) ~= nil and Groups.to_recipe(parts):find("melee", 1, true) == nil, Groups.to_recipe(parts))
  parts = Groups.parse("1 crusher{gap=40}, 1 mauler{time between attacks 150}, 1 hound{attack delay=60 gap=70}")
  check("tune: the new names (gap, time between attacks, attack delay) are the number as it is, the last one wins", parts[1].tune.gap == 40 and parts[2].tune.gap == 150 and parts[3].tune.gap == 70)
  check("tune: its readable name is 'Time between attacks'", Groups.tune_text({ gap = 50 }) == "Time between attacks 50%")
  parts = Groups.parse("1 crusher{size=999 health=1 speed=100}")
  check("tune: values are clamped to their range (size 300 at most, health 10 at least) and 100 is the same as nothing", parts[1].tune.size == 300 and parts[1].tune.health == 10 and parts[1].tune.speed == nil)
  parts = Groups.parse("1 crusher{}, 1 hound{speed=100}")
  check("tune: empty braces or only 100s leave no custom mods", parts[1].tune == nil and parts[2].tune == nil)
  local bad, err = Groups.parse("1 crusher{toughness=150}")
  check("tune: an unknown name is refused with the list of valid ones", bad == nil and err:find("toughness", 1, true) ~= nil and err:find("health", 1, true) ~= nil, err)
  bad, err = Groups.parse("1 crusher{health}")
  check("tune: a name without a number is refused", bad == nil and err:find("needs a number", 1, true) ~= nil, err)
  parts = Groups.parse("2 crushers{size=150}, 3 crushers, 1 crusher{size=150}")
  check("tune: groups of the same enemy with different custom mods stay apart, equal ones merge", #parts == 2 and parts[1].count == 3 and parts[1].tune.size == 150 and parts[2].count == 3 and parts[2].tune == nil)
  parts = Groups.parse("1 plague ogryn|chaos spawn[garden]{health=300}")
  check("tune: works on a random group too", parts[1].one_of and #parts[1].one_of == 2 and parts[1].tune.health == 300 and parts[1].mods[1] == "garden")
  check("tune: the readable text lists the changed ones in catalog order", Groups.tune_text({ mass = 200, health = 150 }) == "Health 150%, Hit mass 200%" and Groups.tune_text(nil) == "" and Groups.tune_text({ size = 100 }) == "")
  check("tune: has_tune, copy_tune, clamp_tune", Groups.has_tune(Groups.parse("1 hound, 1 crusher{mass=200}")) and not Groups.has_tune(Groups.parse("1 hound")) and Groups.copy_tune(nil) == nil and Groups.copy_tune({ size = 120 }).size == 120 and Groups.clamp_tune("burst", 1000) == 500 and Groups.clamp_tune("gap", 26.4) == 26 and Groups.clamp_tune("gap", 1000) == 400 and Groups.clamp_tune("gap", 5) == 25)
  check("tune: nine custom mods, each with a range around 100 and a step", (function()
    if #Groups.TUNE ~= 9 then return false end
    for _, def in ipairs(Groups.TUNE) do if not (def.min < 100 and def.max > 100 and def.step > 0 and def.name ~= "") then return false end end
    return true
  end)())
  check("tune: a card with custom mods says 'Custom' in its modifier line", CardsMod.modifier_line(Groups.parse("2 crushers[enraged]{size=120}"), Groups) == "Enraged \194\183 Custom" and CardsMod.modifier_line(Groups.parse("2 hounds{speed=150}"), Groups) == "Custom" and CardsMod.modifier_line(Groups.parse("2 hounds"), Groups) == "")
end

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
  set("pct_boss_ambush", 9); set("cd_boss_ambush", 90); set("on_hound_frenzy", false)
  Events.set_def(set, "custom_3", "Weird | Name ~ 100%", Groups.parse("3 crushers[rotten+enraged]@2, 1 plague ogryn|chaos spawn"), Groups)
  set("on_custom_3", true); set("pct_custom_3", 6); set("sp_custom_3", 12); set("re_custom_3", 7); set("rf_custom_3", 42)
  local cap = Presets.capture(get, Events, Groups)
  local keys = {}; for _, w in ipairs(cap.waves) do keys[w.key] = w end
  check("presets: capture holds exactly the changed waves", #cap.waves == 4 and keys.wave_small and keys.boss_ambush and keys.hound_frenzy and keys.custom_3, #cap.waves)
  check("presets: chance-only change keeps the default name/recipe", keys.boss_ambush.pct == 9 and keys.boss_ambush.cd == 90 and keys.boss_ambush.name == Events.get("boss_ambush", function() return nil end, Groups).name)

  cap.name = "  My   Setup " .. string.rep("x", 40)
  local text = Presets.encode(cap)
  check("presets: text is one line starting with RW1|, no raw separators inside names", text:sub(1, 4) == "RW1|" and not text:find("[\r\n\t]") and select(2, text:gsub("|", "")) == 3 + #cap.waves, text:sub(1, 60))
  local back, err = Presets.decode(text, Events, Groups)
  check("presets: decode accepts what encode wrote", back ~= nil and #back.waves == #cap.waves and back.skipped == 0, tostring(err))
  check("presets: name is trimmed to 24 characters", back and #back.name <= 24 and back.name:sub(1, 8) == "My Setup", back and back.name)
  local dk = {}; for _, w in ipairs(back.waves) do dk[w.key] = w end
  check("presets: awkward characters in a wave name survive (| ~ %)", dk.custom_3.name == "Weird | Name ~ 100%", dk.custom_3.name)
  check("presets: values round trip", dk.custom_3.enabled == true and dk.custom_3.pct == 6 and dk.custom_3.sp == 12 and dk.custom_3.re == 7 and dk.custom_3.rf == 42 and dk.hound_frenzy.enabled == false, tostring(dk.custom_3.recipe))

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
  check("presets: out-of-range numbers are clamped to the editor's limits (a chance is 0 to 10)", wild and wild.waves[1].pct == 10 and wild.waves[1].cd == 0 and wild.waves[1].sp == 100 and wild.waves[1].re == 1 and wild.waves[1].rf == 3600, wild and wild.waves[1].pct)
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
  store.on_custom_6 = true; store.pct_custom_6 = 7; store.cd_custom_6 = 99; store.sp_custom_6 = 14; store.re_custom_6 = 8; store.rf_custom_6 = 44; store.dmin_custom_6 = 30; store.dmax_custom_6 = 110
  local snap = Presets.capture_wave(g, "custom_6", Events, Groups)
  check("wave share: capture_wave reads one wave", snap and snap.key == "custom_6" and snap.pct == 7 and snap.dmin == 30 and snap.dmax == 110)
  local text = Presets.encode_wave(snap)
  check("wave share: text is one line starting with RWW1|", text:sub(1, 5) == "RWW1|" and not text:find("[\r\n\t]") and select(2, text:gsub("|", "")) == 2, text:sub(1, 40))
  local wave, err = Presets.decode_wave(text, Events, Groups)
  check("wave share: round trip keeps name (with | ~ %), values and recipe", wave and wave.name == "Odd | Name ~ 50%" and wave.pct == 7 and wave.cd == 99 and wave.sp == 14 and wave.re == 8 and wave.rf == 44 and wave.dmin == 30 and wave.dmax == 110 and wave.enabled == true and wave.recipe == snap.recipe, tostring(err))
  -- applying it onto ANOTHER key replaces that wave completely
  local target = {}
  local function tg(id) return target[id] end
  local function ts(id, v) target[id] = v end
  Events.set_def(ts, "custom_2", "Old", Groups.parse("9 hounds"), Groups); target.pct_custom_2 = 5; target.dmin_custom_2 = 77
  Presets.apply_wave(wave, "custom_2", ts, Events, Groups)
  local now = Presets.capture_wave(tg, "custom_2", Events, Groups)
  check("wave share: apply_wave onto another key replaces every setting of that wave", now.name == wave.name and now.recipe == wave.recipe and now.pct == 7 and now.dmin == 30 and now.dmax == 110 and now.key == "custom_2")
  check("wave share: the source wave is untouched by applying elsewhere", Presets.capture_wave(g, "custom_6", Events, Groups).name == "Odd | Name ~ 50%")
  -- a standard wave can be overwritten too, and a standard wave shared keeps its built-in name when unchanged
  local std = Presets.capture_wave(function() return nil end, "wave_small", Events, Groups)
  local std_text = Presets.encode_wave(std)
  local std_back = Presets.decode_wave(std_text, Events, Groups)
  Presets.apply_wave(std_back, "wave_large", ts, Events, Groups)
  check("wave share: a standard wave applied onto another standard wave", Presets.capture_wave(tg, "wave_large", Events, Groups).name == "The Fool")
  local function bad(t) local w, e = Presets.decode_wave(t, Events, Groups); return w == nil and type(e) == "string" and e end
  check("wave share: empty text refused", bad("  ") ~= false)
  check("wave share: a whole preset is refused with a pointer to the Presets screen", (bad(Presets.encode({ name = "x", waves = {} })) or ""):find("Presets screen") ~= nil)
  check("wave share: wrong prefix refused", (bad("hello") or ""):find("RWW1") ~= nil)
  check("wave share: altered/cut text refused", (bad(text:sub(1, #text - 5)) or ""):find("incomplete or was changed") ~= nil and (bad(text:sub(1, 20) .. " " .. text:sub(21)) or ""):find("incomplete or was changed") ~= nil)
  check("wave share: unknown enemy in the recipe refused with the parser's message", (bad(Presets.seal("RWW1|custom_1~A~1~10~60~3~10~60~unicorns~0~0")) or ""):find("unicorns") ~= nil)
  check("wave share: damaged wave refused", bad(Presets.seal("RWW1|custom_1~A~1~10")) ~= false and bad(Presets.seal("RWW1|a|b")) ~= false)
  local w2 = Presets.decode_wave(Presets.seal("RWW1|custom_1~~1~99999~-5~500~0~99999~3 hounds~9999~-1"), Events, Groups)
  check("wave share: numbers clamped to the editor's limits, empty name allowed", w2 and w2.pct == 10 and w2.cd == 0 and w2.sp == 100 and w2.re == 1 and w2.rf == 3600 and w2.dmin == 200 and w2.dmax == 0 and w2.name == "")
  local old = Presets.decode_wave(Presets.seal("RWW1|custom_1~Old~1~10~60~3~10~60~3 hounds"), Events, Groups)
  check("wave share: 9-field wave text (no distances) imports with distances 0", old and old.dmin == 0 and old.dmax == 0)
  -- a text with an unknown key still imports (the key is only the exporter's)
  local fk = Presets.decode_wave(Presets.seal("RWW1|future_wave~F~1~10~60~3~10~60~3 hounds~0~0"), Events, Groups)
  check("wave share: the exporter's key does not matter (unknown keys are fine)", fk and fk.key == "future_wave")
  -- the roll switch (rk_): default on, travels with the card
  local rk = {}
  local function rg(id) return rk[id] end
  local function rs(id, v) rk[id] = v end
  check("roll switch: a card keeps the roll of its random groups by default, and the definition for the spawner says so", Events.get("custom_1", rg, Groups).keep_pick == true and Events.spawn_def(Events.get("custom_1", rg, Groups)).keep_pick == true)
  rk.rk_custom_1 = false
  check("roll switch: turned off it reads as off and reaches the spawner; Reset puts it back on", Events.get("custom_1", rg, Groups).keep_pick == false and Events.spawn_def(Events.get("custom_1", rg, Groups)).keep_pick == false and (function() Events.reset(rs, "custom_1"); return Events.get("custom_1", rg, Groups).keep_pick == true end)())
  Events.set_def(rs, "custom_5", "Roll", Groups.parse("1 hound|mutant@2"), Groups); rk.on_custom_5 = true; rk.rk_custom_5 = false
  local rsnap = Presets.capture_wave(rg, "custom_5", Events, Groups)
  check("roll switch: it is part of a shared card (RWW1 text) and the card is 'changed' because of it", rsnap.keep == false and Presets.decode_wave(Presets.encode_wave(rsnap), Events, Groups).keep == false)
  local on_snap = Presets.capture_wave(function(id) if id == "rk_custom_5" then return nil end return rk[id] end, "custom_5", Events, Groups)
  check("roll switch: a card with the switch on round trips as on", on_snap.keep == true and Presets.decode_wave(Presets.encode_wave(on_snap), Events, Groups).keep == true)
  local old17 = Presets.decode_wave(Presets.seal("RWW1|custom_1~A~1~10~60~3~10~60~3 hounds~0~0~0~0~rage~2~Hi~vial"), Events, Groups)
  check("roll switch: a card text from before the switch (17 fields) imports with it on", old17 and old17.keep == true and old17.suit == "rage")
  local target = {}
  Presets.apply_wave(Presets.decode_wave(Presets.encode_wave(rsnap), Events, Groups), "custom_2", function(id, v) target[id] = v end, Events, Groups)
  check("roll switch: applying a card writes rk_ to the slot", target.rk_custom_2 == false)
  local pool = Presets.pool_waves({ waves = { Presets.decode_wave(Presets.encode_wave(rsnap), Events, Groups) } }, "peer_z", Events, Groups)
  check("roll switch: a friend's card in the draw keeps its switch", pool[1] and pool[1].keep_pick == false)
end
-- enemy name colours without Spidey Sense: the palette asked for ------------------------------------------------------
do
  local Colors = load("catalog/colors")
  Colors.init({ kind = Groups.kind, option = function(id) return settings[id] end, spidey_setting = function() return nil end, named = function() return nil end })
  local function rgb(b) return Colors.rgb(b) end
  local function lum(b) local c = rgb(b); return 0.3 * c[1] + 0.59 * c[2] + 0.11 * c[3] end
  local function same(a, b) local x, y = rgb(a), rgb(b); return x[1] == y[1] and x[2] == y[2] and x[3] == y[3] end
  local all = true
  for _, breed in ipairs(Groups.breed_list()) do local c = rgb(breed); if not (c and c[1] and c[2] and c[3]) then all = false end end
  check("palette: every enemy of the catalog has a colour", all)
  for _, b in ipairs({ "chaos_newly_infected", "renegade_melee", "cultist_melee", "renegade_rifleman", "chaos_mutated_poxwalker" }) do
    check("palette: fodder (" .. b .. ") shares the poxwalker's weak grey", same(b, "chaos_poxwalker"))
  end
  check("palette: crusher bright grey > mauler grey > fodder weak grey", lum("chaos_ogryn_executor") > lum("renegade_executor") and lum("renegade_executor") > lum("chaos_poxwalker") and math.abs(rgb("chaos_ogryn_executor")[1] - rgb("chaos_ogryn_executor")[3]) < 10)
  check("palette: shocktroopers/shotgunners weak yellow (r,g high, b low)", same("renegade_shocktrooper", "cultist_shocktrooper") and rgb("renegade_shocktrooper")[1] > 180 and rgb("renegade_shocktrooper")[3] < 140)
  check("palette: hounds bright yellow, brighter than the shotgunners", same("chaos_hound", "chaos_armored_hound") and rgb("chaos_hound")[3] < 60 and lum("chaos_hound") > lum("renegade_shocktrooper"))
  check("palette: mutant bright green", rgb("cultist_mutant")[2] > 220 and rgb("cultist_mutant")[1] < 120 and rgb("cultist_mutant")[3] < 140)
  check("palette: tox bomber toxic green (lime), different from the mutant", rgb("cultist_grenadier")[2] > 220 and rgb("cultist_grenadier")[1] > 120 and not same("cultist_grenadier", "cultist_mutant"))
  check("palette: daemonhost purple", rgb("chaos_daemonhost")[1] > 150 and rgb("chaos_daemonhost")[3] > 200 and rgb("chaos_daemonhost")[2] < 100)
  check("palette: captains dull green (the colour of their health bar)", same("renegade_captain", "cultist_captain") and rgb("renegade_captain")[2] > rgb("renegade_captain")[1] and rgb("renegade_captain")[2] > rgb("renegade_captain")[3])
  check("palette: twins use the colour of the shield bar of the boss health bar (218,186,126)", same("renegade_twin_captain", "renegade_twin_captain_two") and table.concat(rgb("renegade_twin_captain"), ",") == "218,186,126")
  check("palette: vanguards weak blackish, bulwark blackish (darker), both darker than the fodder", same("renegade_vanguard", "cultist_vanguard") and lum("chaos_ogryn_bulwark") < lum("renegade_vanguard") and lum("renegade_vanguard") < lum("chaos_poxwalker"))
  check("palette: flamers strong orange", same("renegade_flamer", "cultist_flamer") and rgb("renegade_flamer")[1] > 240 and rgb("renegade_flamer")[2] > 90 and rgb("renegade_flamer")[2] < 170 and rgb("renegade_flamer")[3] < 60)
  check("palette: poxburster pinkish", rgb("chaos_poxwalker_bomber")[1] > 230 and rgb("chaos_poxwalker_bomber")[3] > 150 and rgb("chaos_poxwalker_bomber")[2] < 180)
  check("palette: trapper neutral red (duller than the boss red)", rgb("renegade_netgunner")[1] > 180 and rgb("renegade_netgunner")[2] < 100 and lum("renegade_netgunner") < lum("chaos_spawn") + 60 and not same("renegade_netgunner", "chaos_spawn"))
  for _, b in ipairs({ "chaos_beast_of_nurgle", "chaos_plague_ogryn", "chaos_spawn", "chaos_ogryn_houndmaster" }) do
    check("palette: boss " .. b .. " strong red", same(b, "chaos_spawn") and rgb(b)[1] > 240 and rgb(b)[2] < 80 and rgb(b)[3] < 80)
  end
  check("palette: all gunners blue (and the sniper no longer blue)", same("renegade_gunner", "cultist_gunner") and same("renegade_gunner", "chaos_ogryn_gunner") and same("renegade_gunner", "renegade_plasma_gunner") and rgb("renegade_gunner")[3] > 220 and rgb("renegade_gunner")[1] < 120 and rgb("renegade_gunner")[2] < 180 and not same("renegade_sniper", "renegade_gunner"))
  check("palette: bomber orangeish, not the flamer's orange", rgb("renegade_grenadier")[1] > 240 and rgb("renegade_grenadier")[2] > 140 and not same("renegade_grenadier", "renegade_flamer"))
  check("palette: Spidey Sense off in the options gives the palette even when it knows the enemy", (function()
    Colors.init({ kind = Groups.kind, option = function(id) if id == "colour_spidey" then return false end end, spidey_setting = function() return "red" end, named = function() return { 1, 2, 3 } end })
    return table.concat(Colors.rgb("chaos_ogryn_executor"), ",") == "240,240,240"
  end)())
  check("palette: Spidey Sense on and knowing the enemy wins, otherwise the palette", (function()
    Colors.init({ kind = Groups.kind, option = function() end, spidey_setting = function() return "red" end, named = function() return { 1, 2, 3 } end })
    return table.concat(Colors.rgb("chaos_ogryn_executor"), ",") == "1,2,3" and table.concat(Colors.rgb("chaos_twin_nobody") or {}, ",") ~= "1,2,3" and table.concat(Colors.rgb("renegade_twin_captain"), ",") == "218,186,126"
  end)())
end
-- random groups are coloured per enemy, and colours survive the cut -----------------------------------------------------
do
  local Colors = load("catalog/colors")
  Colors.init({ kind = Groups.kind, option = function() end, havoc_setting = function() return nil end })
  local painter = { part = function(p) return Colors.rgb(p.breed) end, breed = function(b) return Colors.rgb(b) end, mod = function(id) return Colors.modifier_rgb(id) end, markup = Colors.markup }
  local parts, perr = Groups.parse("2 plague ogryn|beast of nurgle|chaos spawn|packmaster, 4 crushers[purple+enraged+toughened+rotten]")
  check("random: the test recipe parses", parts ~= nil, perr)
  parts = parts or {}
  local text = Groups.summary(parts, 300, painter)
  check("random: every enemy of a random group has its own colour tag, the words around them none", text:find("2 random of {#color(255,50,50)}Plague Ogryn{#reset()} / {#color(255,50,50)}Beast of Nurgle{#reset()}", 1, true) ~= nil, text)
  local mixed = Groups.summary(Groups.parse("1 hound|crusher"), 200, painter)
  check("random: mixed enemies get different colours", mixed:find("{#color(255,235,40)}Hound{#reset()}", 1, true) ~= nil and mixed:find("{#color(240,240,240)}Crusher{#reset()}", 1, true) ~= nil, mixed)
  local seg = Groups.paint_part_segments(parts[1], painter, false)
  check("random: the row name of a random group is built from the same segments", Groups.render_segments(seg, nil, painter.markup):gsub("{#[^}]*}", "") == "2 random of Plague Ogryn / Beast of Nurgle / Chaos Spawn / Packmaster")
  -- a cut keeps the colours of what is left (the old code lost the modifier colours of a cut piece)
  local mismatches, lost = {}, {}
  for max = 4, 160 do
    local plain = Groups.summary(parts, max)
    local painted = Groups.summary(parts, max, painter)
    if painted:gsub("{#[^}]*}", "") ~= plain then mismatches[#mismatches + 1] = max end
  end
  check("random: the painted text equals the plain text at every length", #mismatches == 0, table.concat(mismatches, ","))
  local cut = Groups.summary(parts, 100, painter)
  check("cut: a modifier name that is still visible after the cut keeps its colour", cut:find("{#color(138,43,226)}Purple{#reset()}", 1, true) ~= nil and cut:find("{#color(255,54,36)}Enraged{#reset()}", 1, true) ~= nil and cut:sub(-3) == "...", cut)
  local segs = { { text = "Purple", rgb = { 1, 2, 3 } }, { text = ", " }, { text = "Red", rgb = { 4, 5, 6 } }, { text = ", " }, { text = "Pus-Hardened Skin", rgb = { 7, 8, 9 } } }
  local cut40 = Groups.render_segments(segs, 20, painter.markup)
  check("cut: render_segments keeps the colours of the visible part and the ellipsis is plain", cut40:gsub("{#[^}]*}", "") == "Purple, Red, Pus-..." and cut40:find("{#color(4,5,6)}Red{#reset()}", 1, true) ~= nil and cut40:find("{#color(7,8,9)}Pus-{#reset()}", 1, true) ~= nil, cut40)
  check("cut: nothing is cut when the text fits", Groups.render_segments(segs, 100, painter.markup):gsub("{#[^}]*}", "") == "Purple, Red, Pus-Hardened Skin")
end
-- The Grandfather's Tarot: card data (catalog/cards.lua) --------------------------------------------------------------
do
  local Cards = load("catalog/cards")
  local Presets = PresetsMod
  local function rec(r) return Groups.parse(r) end
  -- the palette is the reference page's, exactly
  check("tarot: sixteen suits in order (the six of the reference, then volley, snare, brute, warp, heresy, NIGHTMARE last of the hostile twelve, then the four beneficial ones ending with Faith), every colour a 3-number rgb", #Cards.SUIT_ORDER == 16 and Cards.HOSTILE_COUNT == 12 and Cards.SUIT_ORDER[16] == "faith" and Cards.SUITS.faith.beneficial and Cards.SUIT_ORDER[7] == "volley" and Cards.SUIT_ORDER[10] == "warp" and Cards.SUIT_ORDER[11] == "heresy" and Cards.SUIT_ORDER[12] == "nightmare" and (function() for _, id in ipairs(Cards.SUIT_ORDER) do local s = Cards.SUITS[id]; for _, k in ipairs({ "card", "hi", "frame", "text", "accent" }) do if not (s[k] and #s[k] == 3) then return false end end end return true end)())
  check("tarot: plague suit values from the palette", table.concat(Cards.SUITS.plague.card, ",") == "30,36,19" and table.concat(Cards.SUITS.plague.accent, ",") == "183,194,58" and table.concat(Cards.SUITS.fateful.frame, ",") == "138,122,74" and table.concat(Cards.SUITS.murmur.frame, ",") == "85,96,58")
  check("tarot: threat colours 1..5", table.concat(Cards.THREAT_COLORS[1], ",") == "167,194,124" and table.concat(Cards.THREAT_COLORS[3], ",") == "227,207,74" and table.concat(Cards.THREAT_COLORS[5], ",") == "207,74,48")
  check("tarot: the suit ids of the catalog and of the card module are the same set", (function() for id in pairs(Events.SUITS) do if not Cards.SUITS[id] then return false end end for id in pairs(Cards.SUITS) do if not Events.SUITS[id] then return false end end return true end)())
  check("suits: the new ones are known everywhere a suit is validated (Events.SUITS, presets) and every suit of the order is valid", (function()
    for _, id in ipairs(Cards.SUIT_ORDER) do if not Events.SUITS[id] then return false end end
    local n = 0
    for _ in pairs(Events.SUITS) do n = n + 1 end
    return n == #Cards.SUIT_ORDER
  end)())
  check("suits: the new ones have their own whisper, name and mark", Cards.SUITS.volley.whisper == "Something is aiming at you." and Cards.SUITS.snare.whisper == "You cannot run from this." and Cards.SUITS.brute.whisper == "It does not stop for walls." and Cards.SUITS.heresy.whisper == "He does not answer." and Cards.SUITS.heresy.name == "Heresy" and Cards.SUITS.heresy.icon == "heresy" and Cards.SUITS.fester == nil and Cards.SUITS.dusk == nil and Cards.SUITS.nightmare.whisper == "It was never a dream." and Cards.SUITS.warp.whisper == "It knows your name." and Cards.SUITS.warp.name == "Warp" and Cards.SUITS.warp.icon == "warp" and Cards.SUITS.volley.icon == "crosshair")

  -- NIGHTMARE replaced Dusk (2026-10-04): black on black, special, once per game; a saved Dusk card becomes Murmur everywhere
  check("nightmare: black on black (card and ink near black), an ash accent, a pale light, special and once per game, its own mark", Cards.SUITS.nightmare.card[1] < 8 and Cards.SUITS.nightmare.ink[1] == 0 and Cards.SUITS.nightmare.special and Cards.SUITS.nightmare.once and not Cards.SUITS.heresy.once and Cards.SUITS.nightmare.icon == "nightmare" and Cards.SUITS.nightmare.lit[1] > 0xe0 and Cards.SUITS.nightmare.gloom ~= nil)
  check("nightmare: a saved Dusk card is Murmur (cards, settings and presets)", Cards.normalize_suit("dusk") == "murmur" and Events.normalize_suit("dusk") == "murmur" and Events.SUITS.dusk == nil and Events.SUITS.nightmare == true)
  check("dread: the breath stays in 0..1 and the dying light flashes rarely (a few beats in a hundred), never below 0", (function()
    local flashes, low, high = 0, 1, 0
    for i = 0, 899 do local b, f = Cards.dread(i / 9); low, high = math.min(low, b), math.max(high, b); if f > 0 then flashes = flashes + 1 end; if f < 0 or f > 1 then return false end end
    return low >= 0 and high <= 1 and high - low > 0.9 and flashes > 5 and flashes < 120
  end)())
  check("warp: an uneven pulse in 0..1 and a crackle of 0 or 1 about one beat in eight", (function()
    local crackles = 0
    for i = 0, 1399 do local p, c = Cards.warp_pulse(i / 14); if p < 0 or p > 1 or (c ~= 0 and c ~= 1) then return false end; crackles = crackles + c end
    return crackles > 80 and crackles < 300 and Cards.SUITS.warp.motes and Cards.SUITS.warp.lit ~= nil
  end)())

  -- HERESY replaced Fester: the one card that is special; the old name stays an alias everywhere it may still be written
  do
    local plain_sets_equal = true
    for from, to in pairs(Cards.SUIT_ALIAS) do if Events.SUIT_ALIAS[from] ~= to then plain_sets_equal = false end end
    for from, to in pairs(Events.SUIT_ALIAS) do if Cards.SUIT_ALIAS[from] ~= to then plain_sets_equal = false end end
    check("heresy: Heresy, Nightmare and the blessings are special; its palette is its own (near-black red face, fresh blood frame, crimson accent, a lit red for words, a deep blood for the heartbeat)", Cards.SUITS.heresy.special == true and (function() local n = 0 for _, def in pairs(Cards.SUITS) do if def.special then n = n + 1 end end return n end)() == 6 and #Cards.SUITS.heresy.lit == 3 and #Cards.SUITS.heresy.blood == 3 and Cards.SUITS.heresy.frame[1] == 0x8a and Cards.SUITS.heresy.accent[1] == 0xd4 and Cards.SUITS.heresy.accent[2] == 0x2a)
    check("faith: a pink no other suit has (the accent's red is high and its blue above its green)", (function() local a = Cards.SUITS.faith.accent; if not (a[1] > 200 and a[3] > a[2]) then return false end for id, def in pairs(Cards.SUITS) do if id ~= "faith" and def.accent[1] > 200 and def.accent[3] > def.accent[2] + 20 then return false end end return true end)())
    check("threat six: Despair on a hostile card, Apotheosis on a beneficial one, nothing below six; the edges differ", Cards.threat_name(6, "plague") == "Despair" and Cards.threat_name(6, "faith") == "Apotheosis" and Cards.threat_name(5, "faith") == nil and Cards.threat_edge("heresy") == Cards.DESPAIR_EDGE and Cards.threat_edge("miracle") == Cards.APOTHEOSIS_EDGE)
    check("threat six: the shine never fades below 0.35 and stays within 0..1; the heartbeat stays within 0..1 and beats", (function() local lo, hi, beat_lo, beat_hi = 1, 0, 1, 0 for i = 0, 400 do local t = i / 37; for _, s in ipairs({ "plague", "grace" }) do local v = Cards.six_shine(t, s); lo, hi = math.min(lo, v), math.max(hi, v) end local b = Cards.heartbeat(t); beat_lo, beat_hi = math.min(beat_lo, b), math.max(beat_hi, b) end return lo >= 0.35 and hi <= 1 and hi > 0.9 and beat_lo >= 0 and beat_lo < 0.05 and beat_hi > 0.9 and beat_hi <= 1 end)())
    check("heresy: Cards.is_special says it for Heresy and for its old name, not for the others or for nothing", Cards.is_special("heresy") and Cards.is_special("fester") and not Cards.is_special("warp") and not Cards.is_special(nil) and not Cards.is_special("nonsense"))
    check("heresy: the old name is an alias in the card module and in the catalog (the same list), an unknown name is plague", Cards.normalize_suit("fester") == "heresy" and Events.normalize_suit("fester") == "heresy" and Cards.normalize_suit("heresy") == "heresy" and Events.normalize_suit("heresy") == "heresy" and Events.normalize_suit("nonsense") == "plague" and Events.normalize_suit(nil) == "plague" and Cards.suit_index("fester") == 11 and Cards.suit_index("heresy") == 11 and plain_sets_equal)
    local function getter(id) return settings[id] end
    settings.wave_def_custom_5 = "Mine\t3 hounds"; settings.su_custom_5 = "fester"
    check("heresy: a card saved with suit fester is a Heresy card now", Events.get("custom_5", getter, Groups).suit == "heresy")
    settings.su_custom_5 = "heresy"
    check("heresy: and one saved as heresy stays one", Events.get("custom_5", getter, Groups).suit == "heresy")
    settings.wave_def_custom_5 = nil; settings.su_custom_5 = nil
  end
  check("suits: every whisper fits the 40 letters of a whisper", (function() for _, id in ipairs(Cards.SUIT_ORDER) do if #Cards.SUITS[id].whisper > Cards.MAX_WHISPER then return false end end return true end)())
  check("suits: every suit has its own accent colour and its own mark", (function()
    local accents, icons = {}, {}
    for _, id in ipairs(Cards.SUIT_ORDER) do
      local a = table.concat(Cards.SUITS[id].accent, ",")
      if accents[a] or icons[Cards.SUITS[id].icon] then return false end
      accents[a], icons[Cards.SUITS[id].icon] = true, true
    end
    return true
  end)())
  check("suits: warp is purple (blue and red above green, red below blue)", (function() local a = Cards.SUITS.warp.accent; return a[3] > a[2] and a[1] > a[2] and a[3] > a[1] end)())
  check("suits: a card with a Daemonhost is suggested the warp suit, also as one of the picks of a random group", Cards.suggest_suit({ { breed = "chaos_daemonhost", count = 1 } }, Groups) == "warp" and Cards.suggest_suit({ { one_of = { "chaos_poxwalker", "chaos_daemonhost" }, count = 1 } }, Groups) == "warp" and Cards.suggest_suit({ { breed = "chaos_poxwalker", count = 3 } }, Groups) ~= "warp")
  check("suits: warp wins over the boss rule (a Daemonhost is classed as a monster by the game)", Cards.suggest_suit({ { breed = "chaos_daemonhost", count = 1 }, { breed = "chaos_beast_of_nurgle", count = 1 } }, Groups) == "warp")
  check("suits: a custom card with a Daemonhost is a warp card until the player chooses another suit", (function()
    local settings = { wave_def_custom_1 = "Host\t1 daemonhost" }
    local function get(id) return settings[id] end
    local wave = Events.get("custom_1", get, Groups)
    local plain = Events.get("custom_2", function(id) if id == "wave_def_custom_2" then return "Pox\t3 poxwalker" end return nil end, Groups)
    settings.su_custom_1 = "snare"
    local chosen = Events.get("custom_1", get, Groups)
    return wave.suit == "warp" and plain.suit == "plague" and chosen.suit == "snare"
  end)())
  check("suits: the modifier line can dress each name up (colour tags), the separators stay plain", (function()
    local parts = { { breed = "chaos_poxwalker", count = 2, mods = { "enraged", "purple_stimm" } } }
    local plain = Cards.modifier_line(parts, Groups)
    local dressed = Cards.modifier_line(parts, Groups, function(name, id) return "[" .. id .. ":" .. name .. "]" end)
    return plain ~= "" and dressed:find("%[enraged:", 1) ~= nil and dressed:find(" \194\183 ", 1, true) ~= nil and Cards.modifier_line(parts, Groups, nil) == plain
  end)())
  check("tarot: every suit has its line from the brief", Cards.SUITS.plague.whisper == "Something is growing." and Cards.SUITS.murmur.whisper == "Do you hear it?" and Cards.SUITS.rage.whisper == "Faster. Faster." and Cards.SUITS.blight.whisper == "The air turns." and Cards.SUITS.swarm.whisper == "Too many to count." and Cards.SUITS.fateful.whisper == "The last page.")
  -- threat by the numbers
  local function th(r) return (Cards.threat_auto(rec(r), Groups)) end
  check("threat: base 1 up to 8 enemies, 2 up to 24, 3 up to 60, 4 up to 120, 5 above (fodder only)", th("8 poxwalker") == 1 and th("9 poxwalker") == 2 and th("24 poxwalker") == 2 and th("25 poxwalker") == 3 and th("30 poxwalker, 30 scab") == 3 and th("30 poxwalker, 30 scab, 1 dreg") == 4 and th("60 poxwalker, 60 scab") == 4 and (Cards.threat_auto({ { breed = "chaos_poxwalker", count = 121 } }, Groups)) == 5, th("8 poxwalker") .. th("9 poxwalker") .. th("25 poxwalker"))
  check("threat: +1 with elites, +1 with specials, +2 with a boss, never above 5", th("3 crushers") == 2 and th("5 hounds") == 2 and th("1 plague ogryn") == 3 and th("5 hounds, 3 crushers") == 3 and th("8 poxwalker, 1 plague ogryn, 1 hound, 1 crusher") == 5 and th("60 poxwalker, 40 scab, 1 plague ogryn") == 5, th("3 crushers") .. th("5 hounds") .. th("1 plague ogryn"))
  local _, parts_info = Cards.threat_auto(rec("30 poxwalker, 3 crushers, 2 hounds"), Groups)
  check("threat: the explanation pieces for 'Threat N by the numbers'", parts_info.count == 35 and parts_info.base == 3 and parts_info.elite and parts_info.special and not parts_info.boss)
  check("threat: a manual override wins, 0 means automatic, junk is ignored", Cards.threat(rec("3 crushers"), 4, Groups) == 4 and Cards.threat(rec("3 crushers"), 0, Groups) == 2 and Cards.threat(rec("3 crushers"), 9, Groups) == 2 and Cards.threat(rec("3 crushers"), nil, Groups) == 2)
  check("threat: a random group counts its kinds (a boss in the group is a boss)", th("1 plague ogryn|chaos spawn") == 3 and th("1 hound|crusher") == 3)
  -- suit suggestion
  check("suggest: boss -> fateful, specials -> blight, more than 60 and no elites -> swarm, else none", Cards.suggest_suit(rec("1 plague ogryn"), Groups) == "fateful" and Cards.suggest_suit(rec("5 hounds"), Groups) == "blight" and Cards.suggest_suit(rec("40 poxwalker, 30 scab"), Groups) == "swarm" and Cards.suggest_suit(rec("40 poxwalker, 30 scab, 1 crusher"), Groups) == nil and Cards.suggest_suit(rec("5 poxwalker"), Groups) == nil and Cards.suggest_suit(rec("1 plague ogryn, 5 hounds"), Groups) == "fateful")
  -- dots: one per enemy colour
  local Colors = load("catalog/colors")
  Colors.init({ kind = Groups.kind, option = function() end })
  local function rgb_of(b) return Colors.rgb(b) end
  local d1 = Cards.dots(rec("30 poxwalker, 30 scab, 30 dreg"), rgb_of)
  check("dots: the three fodder breeds share one colour -> one dot", #d1 == 1 and table.concat(d1[1], ",") == "135,135,135")
  local d2 = Cards.dots(rec("6 tox bomber, 6 bomber"), rgb_of)
  check("dots: two kinds -> two dots, in order of appearance", #d2 == 2 and table.concat(d2[1], ",") == "170,255,50" and table.concat(d2[2], ",") == "255,175,100")
  local d3 = Cards.dots(rec("1 plague ogryn|beast of nurgle|chaos spawn|packmaster"), rgb_of)
  check("dots: a random group of bosses -> one boss-red dot", #d3 == 1 and table.concat(d3[1], ",") == "255,50,50")
  check("dots: at most 6", #Cards.dots(rec("1 hound, 1 crusher, 1 mauler, 1 mutant, 1 trapper, 1 bomber, 1 tox bomber, 1 sniper"), rgb_of) == 6)
  check("dots: enemies without a colour are skipped", #Cards.dots(rec("3 hounds"), function() return nil end) == 0)
  -- whisper, look, rarity
  check("whisper: own text, else the suit's line; cleaned and cut at 40", Cards.whisper({ whisper = "It grows.", suit = "swarm" }) == "It grows." and Cards.whisper({ whisper = "", suit = "swarm" }) == "Too many to count." and Cards.whisper({ whisper = "   ", suit = "rage" }) == "Faster. Faster." and #Cards.clean_whisper(string.rep("ab ", 30)) <= 40 and Cards.clean_whisper("a\n\tb") == "a b" and Cards.whisper({ suit = "nope" }) == "Something is growing.")
  check("look: every card rots and renews, whatever its suit or its saved look (the saved look still parses, for old texts)", Cards.look({ suit = "murmur" }) == "rot" and Cards.look({ suit = "rage" }) == "rot" and Cards.look({ suit = "blight", look = "vial" }) == "rot" and Cards.look({ suit = "murmur", look = "whisper" }) == "rot" and Cards.normalize_look("vial") == "vial" and Cards.normalize_look("nonsense") == nil)
  check("murmur: threat 5 and 6 murmur their whisper when drawn, lower threats do not", Cards.murmurs(5) and Cards.murmurs(6) and not Cards.murmurs(4) and not Cards.murmurs(nil))
  check("chance: the pips are the number itself, 1 to 10 (a fraction rounds, 0 or less is none, above 10 is 10)", (function() for w = 1, 10 do if Cards.level(w) ~= w then return false end end return true end)() and Cards.level(0) == 0 and Cards.level(-3) == 0 and Cards.level(4.4) == 4 and Cards.level(4.5) == 5 and Cards.level(0.2) == 1 and Cards.level(40) == 10 and Cards.level(nil) == 0)
  check("chance: chance 2 shows 2 pips, 3 shows 3, 4 shows 4 and 5 shows 5 (never one fewer, whatever the other cards have)", Cards.level(2, 2, 5) == 2 and Cards.level(3, 2, 5) == 3 and Cards.level(4, 2, 5) == 4 and Cards.level(5, 2, 5) == 5)
  check("chance: rare is a chance of 1 or 2", Cards.is_rare_level(1) and Cards.is_rare_level(2) and not Cards.is_rare_level(3) and not Cards.is_rare_level(0) and not Cards.is_rare_level(nil))
  check("chance: a click on a pip sets that number (kept between 1 and 10)", (function() for k = 1, 10 do if Cards.weight_for_level(k) ~= k then return false end end return true end)() and Cards.weight_for_level(0) == 1 and Cards.weight_for_level(99) == 10 and Cards.weight_for_level(nil) == 1)
  check("chance: the most a chance can be is 10 (Cards.MAX_CHANCE, Events.MAX_PCT)", Cards.MAX_CHANCE == 10 and Events.MAX_PCT == 10)
  check("chance: the share is the chance over the total of the cards that can be drawn; none when it cannot be drawn", math.abs(Cards.share(2, 10) - 20) < 1e-9 and math.abs(Cards.share(10, 10) - 100) < 1e-9 and Cards.share(0, 10) == nil and Cards.share(3, 0) == nil and Cards.share(nil, 10) == nil)
  check("chance: the share grows when other cards leave the draw (a resting card): 3 of 12 is 25 percent, 3 of 9 is 33", math.abs(Cards.share(3, 12) - 25) < 1e-9 and math.abs(Cards.share(3, 9) - 100 / 3) < 1e-9)
  check("describe: the card has its chance as its level and is rare at 1 or 2", (function()
    local g = { kind = function() return "normal" end, MODIFIERS = {} }
    local one = Cards.describe({ key = "x", name = "X", parts = {}, pct = 1, cooldown = 120, enabled = true }, g)
    local two = Cards.describe({ key = "x", name = "X", parts = {}, pct = 2, cooldown = 120, enabled = true }, g)
    local five = Cards.describe({ key = "x", name = "X", parts = {}, pct = 5, cooldown = 120, enabled = true }, g)
    return one.level == 1 and one.rare == true and two.level == 2 and two.rare == true and five.level == 5 and five.rare == false
  end)())
  check("rare: weight 1-2 is rare, 0 and 3+ are not", Cards.is_rare(1) and Cards.is_rare(2) and not Cards.is_rare(3) and not Cards.is_rare(0) and not Cards.is_rare(nil))
  check("events: a stored chance above 10 reads as 10, below 0 as 0, nothing stored is the card's default", (function()
    local st = { pct_wave_small = 400, pct_wave_medium = -5, pct_custom_1 = 7 }
    local g = function(id) return st[id] end
    return Events.get("wave_small", g, Groups).pct == 10 and Events.get("wave_medium", g, Groups).pct == 0 and Events.get("wave_large", g, Groups).pct == 4 and Events.get("custom_1", g, Groups).pct == 7 and Events.get("custom_2", g, Groups).pct == 10
  end)())
  check("suit: an unknown suit falls back to plague", Cards.normalize_suit("nonsense") == "plague" and Cards.normalize_suit(nil) == "plague" and Cards.normalize_suit("rage") == "rage")
  -- rot formulas of the reference page
  check("rot: strength is 0 at 30 s, 1 at the longest cooldown, clamped, and grows with the cooldown", Cards.rot_strength(30, 600) == 0 and math.abs(Cards.rot_strength(600, 600) - 1) < 1e-9 and Cards.rot_strength(5000, 600) == 1 and Cards.rot_strength(120, 600) > 0.4 and Cards.rot_strength(120, 600) < 0.5 and Cards.rot_strength(240, 600) > Cards.rot_strength(120, 600), Cards.rot_strength(120, 600))
  check("rot: duration lerps from the shortest to the longest rot (1.2 s at 30 s, 3.0 s at the longest)", math.abs(Cards.rot_duration(30, 600, 1.2, 3) - 1.2) < 1e-9 and math.abs(Cards.rot_duration(600, 600, 1.2, 3) - 3) < 1e-9)
  local sz = Cards.rot_sizes(1)
  check("rot: blotch 14 + 52k, flies 3 + round(6k), drips 14 + 40k", Cards.rot_sizes(0).blotch == 14 and sz.blotch == 66 and Cards.rot_sizes(0).flies == 3 and sz.flies == 9 and sz.drip == 54 and Cards.rot_sizes(0).drip == 14)
  check("rot and renewal: grey -> brown -> ochre -> the suit accent at p 0, 0.35, 0.7, 1; the text opacity goes 0.5 -> 1", table.concat(Cards.rot_color(0, { 183, 194, 58 }), ",") == "74,74,64" and table.concat(Cards.rot_color(0.35, { 183, 194, 58 }), ",") == "90,70,49" and table.concat(Cards.rot_color(0.7, { 183, 194, 58 }), ",") == "194,122,44" and table.concat(Cards.rot_color(1, { 183, 194, 58 }), ",") == "183,194,58" and Cards.rot_text_alpha(0) == 0.5 and Cards.rot_text_alpha(1) == 1)
  check("murmur returns: the card opacity goes 0.6 -> 1 and the whisper appears letter by letter", Cards.murmur_card_alpha(0) == 0.6 and Cards.murmur_card_alpha(1) == 1 and Cards.whisper_letters("Do you hear it?", 0) == 0 and Cards.whisper_letters("Do you hear it?", 1) == 15 and Cards.whisper_letters("Do you hear it?", 0.5) > 0 and Cards.whisper_letters("Do you hear it?", 0.5) < 15)
  -- the default cards
  local function def(key) return Events.get(key, function() return nil end, Groups) end
  check("defaults: the standard waves are tarot cards under their old keys", def("boss_ambush").name == "The Devil" and def("boss_ambush").suit == "fateful" and def("bomber_frenzy").name == "The Tower" and def("hound_frenzy").name == "The Hunt" and def("hound_frenzy").suit == "rage" and def("grenade_legion").name == "Rain of Rot" and def("sniper_elite").name == "The Watching Moon" and def("sniper_elite").suit == "murmur" and def("elite_squad").name == "The Chariot" and def("wave_small").name == "The Fool" and def("wave_small").suit == "swarm")
  check("defaults: Rain of Rot still carries its old vial look in its settings, but it rots like every other card", def("grenade_legion").look == "vial" and (function() local n = 0; for _, k in ipairs(Events.keys()) do if def(k).look == "vial" then n = n + 1 end end return n end)() == 1 and Cards.look({ suit = def("grenade_legion").suit, look = def("grenade_legion").look }) == "rot")
  check("defaults: every default card has a valid suit, a cooldown of at least 30 s (multiples of 30) and a weight 1-10", (function() for _, e in ipairs(Events.STANDARD) do if not Events.SUITS[e.suit] or e.cooldown < 30 or e.cooldown % 30 ~= 0 or e.default_pct < 1 or e.default_pct > 10 then return false end end return true end)())
  check("defaults: a custom card is a plague card with a 120 s cooldown and weight 10", def("custom_1").suit == "plague" and def("custom_1").cooldown == 120 and def("custom_1").threat_override == 0 and def("custom_1").whisper == "" and def("custom_1").look == "")
  check("defaults: one default per name (no two default cards share a name)", (function() local seen = {}; for _, e in ipairs(Events.STANDARD) do if seen[e.name] then return false end seen[e.name] = true end return true end)())
  -- stored values and describe()
  local st = { su_custom_1 = "murmur", th_custom_1 = 5, wh_custom_1 = "Listen.", cl_custom_1 = "rot", wave_def_custom_1 = "The Pale Choir\t24 poxwalker, 2 crushers[rotten]", on_custom_1 = true, pct_custom_1 = 2 }
  local w1 = Events.get("custom_1", function(id) return st[id] end, Groups)
  check("settings: suit, threat override, whisper and look are read from su_/th_/wh_/cl_", w1.suit == "murmur" and w1.threat_override == 5 and w1.whisper == "Listen." and w1.look == "rot")
  local card = Cards.describe(w1, Groups, rgb_of)
  check("describe: a custom card gets name, suit, threat, dots, whisper, look, rarity, modifier line", card.name == "The Pale Choir" and card.suit == "murmur" and card.threat == 5 and card.threat_auto == 4 and card.whisper == "Listen." and card.own_whisper and card.look == "rot" and card.rare and card.weight == 2 and card.modifiers == "Rotten Armor" and #card.dots == 2 and card.breeds[1] == "chaos_poxwalker" and card.enabled, card.threat_auto)
  st.su_custom_1 = "bogus"; st.th_custom_1 = 99; st.cl_custom_1 = "x"; st.wh_custom_1 = nil
  local w2 = Events.get("custom_1", function(id) return st[id] end, Groups)
  check("settings: junk values fall back (suit plague, threat 6 at most, no look, no whisper)", w2.suit == "plague" and w2.threat_override == 6 and w2.look == "" and w2.whisper == "")
  local sets = {}
  Events.reset(function(id, v) sets[id] = v end, "custom_1")
  check("settings: reset clears the card data", sets.su_custom_1 == "" and sets.th_custom_1 == 0 and sets.wh_custom_1 == "" and sets.cl_custom_1 == "")
  -- sharing and spreads carry the card data
  local store = { su_custom_2 = "rage", th_custom_2 = 2, wh_custom_2 = "Run | now ~ 100%", cl_custom_2 = "vial", wave_def_custom_2 = "Chase\t5 hounds", on_custom_2 = true, cd_custom_2 = 180 }
  local function g(id) return store[id] end
  local snap = Presets.capture_wave(g, "custom_2", Events, Groups)
  check("share: the snapshot holds suit, threat override, whisper, look", snap.suit == "rage" and snap.thr == 2 and snap.whisper == "Run | now ~ 100%" and snap.look == "vial" and snap.cd == 180)
  local text = Presets.encode_wave(snap)
  local back = Presets.decode_wave(text, Events, Groups)
  check("share: a wave text round trip keeps them, awkward characters included", back and back.suit == "rage" and back.thr == 2 and back.whisper == "Run | now ~ 100%" and back.look == "vial" and back.cd == 180, text)
  local target = {}
  Presets.apply_wave(back, "custom_9", function(id, v) target[id] = v end, Events, Groups)
  check("share: applying writes them onto the chosen slot", target.su_custom_9 == "rage" and target.th_custom_9 == 2 and target.wh_custom_9 == "Run | now ~ 100%" and target.cl_custom_9 == "vial" and target.cd_custom_9 == 180)
  local unknown = Presets.decode_wave(Presets.seal("RWW1|custom_1~A~1~10~120~3~10~60~3 hounds~0~0~0~0~chaos~9~ok~sparkle"), Events, Groups)
  check("share: an unknown suit from a friend becomes plague, a threat above 6 is capped, an unknown look is dropped", unknown and unknown.suit == "plague" and unknown.thr == 6 and unknown.look == "" and unknown.whisper == "ok")
  local older = Presets.decode_wave(Presets.seal("RWW1|custom_1~A~1~10~60~3~10~60~3 hounds~0~0~0~0"), Events, Groups)
  check("share: a text from before the tarot (13 fields) imports and keeps the card's own suit (suit nil)", older and older.suit == nil and older.thr == 0 and older.whisper == "" and older.look == "")
  local tw = {}
  Presets.apply_wave(older, "hound_frenzy", function(id, v) tw[id] = v end, Events, Groups)
  check("share: ...and applying it does not overwrite the suit with a default", tw.su_hound_frenzy == "")
  local long = Presets.decode_wave(Presets.seal("RWW1|custom_1~A~1~10~120~3~10~60~3 hounds~0~0~0~0~swarm~0~" .. string.rep("x", 90) .. "~rot"), Events, Groups)
  check("share: a whisper longer than 40 characters is cut", long and #long.whisper <= 40)
  local cap = Presets.capture(g, Events, Groups)
  cap.name = "Spread"
  local pb = Presets.decode(Presets.encode(cap), Events, Groups)
  local pw; for _, w in ipairs(pb.waves) do if w.key == "custom_2" then pw = w end end
  check("spread: a preset carries suit, threat override, whisper, look, cooldown", pw and pw.suit == "rage" and pw.thr == 2 and pw.look == "vial" and pw.whisper == "Run | now ~ 100%" and pw.cd == 180)
  -- the one-time rename of the user's old waves
  local mig = {}
  local function mg(id) return mig[id] end
  local function ms(id, v) mig[id] = v end
  Events.set_def(ms, "custom_1", "Horde Fodder", rec("30 poxwalker, 30 scab, 30 dreg"), Groups); mig.on_custom_1 = true
  Events.set_def(ms, "custom_2", "HOLY SHIT WE LOST", rec("5 shocktrooper, 10 crusher"), Groups)
  Events.set_def(ms, "grenade_legion", "Grenade chaos", rec("6 tox bomber, 6 bomber"), Groups)
  Events.set_def(ms, "custom_3", "My Own Name", rec("3 hounds"), Groups)
  Events.set_def(ms, "custom_4", "Dog wave", rec("5 hounds"), Groups); mig.su_custom_4 = "blight" -- the user already chose a suit: left alone
  local renamed = Cards.migrate(mg, ms, Events, Groups)
  check("migration: the old names become their tarot cards with the right suit", renamed == 3 and Events.get("custom_1", mg, Groups).name == "The Multitude" and mig.su_custom_1 == "swarm" and Events.get("custom_2", mg, Groups).name == "Death" and mig.su_custom_2 == "fateful" and Events.get("grenade_legion", mg, Groups).name == "Rain of Rot" and mig.su_grenade_legion == "blight" and mig.cl_grenade_legion == "vial", tostring(renamed))
  check("migration: a name the user chose and a card whose suit the user already set are left alone", Events.get("custom_3", mg, Groups).name == "My Own Name" and mig.su_custom_3 == nil and Events.get("custom_4", mg, Groups).name == "Dog wave" and mig.su_custom_4 == "blight")
  check("migration: recipes and settings are kept", #Events.get("custom_1", mg, Groups).parts == 3 and Events.get("custom_1", mg, Groups).enabled == true)
  check("migration: running it again changes nothing (the suits are set now)", Cards.migrate(mg, ms, Events, Groups) == 0)
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

-- a random group rolls ONCE and keeps its enemy on every repeat (the card's switch, default on); with the switch off every unit rolls
do
  local function breeds_of_wave(def)
    run_timed(def, 45, 0.25)
    local seen, n = {}, 0
    for _, u in ipairs(spawned) do if not seen[u.breed] then seen[u.breed] = true; n = n + 1 end end
    return n, #spawned, seen
  end
  local random_parts = function() return Groups.parse("2 hound|mutant|trapper@3") end
  local always_one, total_ok, variety = true, true, {}
  for _ = 1, 40 do
    local n, units, seen = breeds_of_wave({ name = "t", parts = random_parts(), rep_every = 10, rep_for = 35, keep_pick = true })
    if n ~= 1 then always_one = false end
    if units ~= 2 + 3 * 3 then total_ok = false end
    for b in pairs(seen) do variety[b] = true end
  end
  local kinds = 0; for _ in pairs(variety) do kinds = kinds + 1 end
  check("roll once: with the switch on a random group is ONE enemy in the first spawn and in every repeat (40 waves of 11 units)", always_one and total_ok)
  check("roll once: ...and the roll still varies from wave to wave (all three enemies came up)", kinds == 3, kinds)
  local mixed = 0
  for _ = 1, 40 do
    local n = breeds_of_wave({ name = "t", parts = random_parts(), rep_every = 10, rep_for = 35, keep_pick = false })
    if n > 1 then mixed = mixed + 1 end
  end
  check("roll once: with the switch off every unit rolls (a wave of 11 units almost always has more than one enemy)", mixed >= 35, mixed)
  local n_default = breeds_of_wave({ name = "t", parts = random_parts(), rep_every = 10, rep_for = 35 })
  check("roll once: a definition without the switch (an older caller) keeps the roll too", n_default == 1, n_default)
  -- two random groups roll separately; a plain group is untouched
  local parts = Groups.parse("1 hound|mutant@2, 1 sniper|trapper@2, 2 crusher@1")
  run_timed({ name = "t", parts = parts, rep_every = 10, rep_for = 25, keep_pick = true }, 40, 0.25)
  local groups_seen = { a = {}, b = {}, plain = 0 }
  for _, u in ipairs(spawned) do
    if u.breed == "chaos_hound" or u.breed == "cultist_mutant" then groups_seen.a[u.breed] = true
    elseif u.breed == "renegade_sniper" or u.breed == "chaos_poxwalker_bomber" or u.breed == "renegade_netgunner" or u.breed == "cultist_trapper" then groups_seen.b[u.breed] = true
    else groups_seen.plain = groups_seen.plain + 1 end
  end
  local na, nb = 0, 0; for _ in pairs(groups_seen.a) do na = na + 1 end; for _ in pairs(groups_seen.b) do nb = nb + 1 end
  check("roll once: each random group keeps its own roll (one enemy each), the plain group is spawned as written", na == 1 and nb == 1 and groups_seen.plain == 2 + 2 * 1, tostring(na) .. "/" .. tostring(nb) .. "/" .. tostring(groups_seen.plain))
  Execute.reset()
end

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
    local want = math.floor(base * percent / 100)
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

do
  local saved_per,saved_special=settings.max_per_wave,settings.mult_special
  settings.max_per_wave=500; settings.mult_special=500; cand_fail=true
  Execute.reset()
  Execute.start_wave({name="backlog",parts=Groups.parse("60 hounds@60"),rep_every=1,rep_for=3600})
  Execute.update(1800)
  check("repeat: a long frame and blocked positions never queue over 1000 units", Execute.status().queued==1000,Execute.status().queued)
  Execute.update(1)
  check("repeat: a full queue skips further ticks without growing", Execute.status().queued==1000)
  Execute.reset(); cand_fail=false
  settings.max_per_wave=saved_per; settings.mult_special=saved_special
end
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
  check("localization: the enemy count column is the 'Brood' (it was 'Weight', which is not what it is: the card's chance has its own name)", loc.col_count.en == "Brood" and loc.popup_count_title.en == "Brood of %s" and loc.col_chance.en == "Chance" and loc.popup_chance_title.en:find("0 to 10", 1, true) ~= nil)
  check("localization: multiplier and search strings exist", loc.mult_normal and loc.mult_boss and loc.mult_special and loc.group_multipliers and loc.btn_search and loc.popup_search_hint and loc.picker_status and loc.unit_percent.en == "pct")
  -- DMF option rows: the title column holds about 27 characters on one line, the value column about 8
  -- (value + unit, e.g. "1000 pct"); longer text wraps into several lines and overlaps the next row.
  local titles = { "initial_delay", "interval_min", "interval_max", "vote_duration", "ballot_size", "novote_fallback", "max_per_wave", "max_alive", "heap_guard_mb", "min_distance", "max_distance", "monster_min_distance", "monster_max_distance", "mult_normal", "mult_boss", "mult_special", "open_editor_bind", "vote_1_bind", "vote_2_bind", "vote_3_bind", "vote_4_bind", "vote_5_bind", "hud_enabled", "hud_show_percent", "colour_enemies", "colour_spidey", "interval_random", "debug", "fallback_random", "fallback_skip", "tarot_cards", "tarot_seconds", "tarot_default_cooldown", "tarot_roulette", "tarot_winner", "tarot_eye_open", "tarot_eye_size", "tarot_rot_short", "tarot_rot_long", "tarot_longest", "group_spread", "mode_tarot", "mode_random", "mode_vote", "tarot_scale", "tarot_opacity", "tarot_timer_below", "tarot_hide_icon", "tarot_ping", "tarot_font", "font_novarese_bold", "font_novarese", "font_friz", "font_proxima", "font_rexlia", "font_machine" }
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
  -- the look options of the Spread: size, opacity, timer below, corner symbol, font
  local sc, op, tb, hi, ft = find("tarot_scale", all), find("tarot_opacity", all), find("tarot_timer_below", all), find("tarot_hide_icon", all), find("tarot_font", all)
  check("options: HUD size 50-200 pct (default 100) and opacity 10-100 pct (default 100), in steps of 5", sc and op and sc.range[1] == 50 and sc.range[2] == 200 and sc.default_value == 100 and sc.step_size_value == 5 and op.range[1] == 10 and op.range[2] == 100 and op.default_value == 100 and op.step_size_value == 5 and sc.unit_text == "unit_percent")
  check("options: timer below and hide the corner symbol are checkboxes, off by default", tb and hi and tb.type == "checkbox" and hi.type == "checkbox" and tb.default_value == false and hi.default_value == false)
  local font_ok = ft ~= nil and ft.type == "dropdown" and ft.default_value == "itc_novarese_bold" and #ft.options >= 5
  local valid_fonts = { itc_novarese_bold = true, itc_novarese_medium = true, friz_quadrata = true, proxima_nova_bold = true, rexlia = true, machine_medium = true }
  local default_listed = false
  for _, o in ipairs(ft and ft.options or {}) do
    if not valid_fonts[o.value] or not loc[o.text] then font_ok = false end
    if o.value == ft.default_value then default_listed = true end
  end
  check("options: the font dropdown lists only fonts that exist in the game, with a label each, and offers its default", font_ok and default_listed)
  local spread_group = find("group_spread", all)
  local spread_ids = {}
  for _, w in ipairs(spread_group and spread_group.sub_widgets or {}) do spread_ids[w.setting_id] = true end
  check("options: the look options sit in the group 'The Spread (your screen)'", spread_ids.tarot_scale and spread_ids.tarot_opacity and spread_ids.tarot_timer_below and spread_ids.tarot_hide_icon and spread_ids.tarot_ping and spread_ids.tarot_font and spread_ids.tarot_roulette)
  -- the window of the last card
  do
    local hl, hud_group = find("hud_last_card", all), find("group_hud", all)
    local listed = false
    for _, w in ipairs(hud_group and hud_group.sub_widgets or {}) do if w.setting_id == "hud_last_card" then listed = true end end
    check("options: 'Last card' (the window of the last fulfilled card) is a checkbox, on by default, in the HUD group, with its texts (the age text takes one %s)", hl and hl.type == "checkbox" and hl.default_value == true and listed and loc.hud_last_card and loc.hud_last_card_description and loc.hud_last_ago and select(2, loc.hud_last_ago.en:gsub("%%s", "")) == 1 and not loc.hud_last_ago.en:find("%%[^s]"))
  end
  -- the default cooldown of a card of your own
  do
    local dc = find("tarot_default_cooldown", all)
    local timing = find("group_timing", all)
    local listed = false
    for _, w in ipairs(timing.sub_widgets) do if w.setting_id == "tarot_default_cooldown" then listed = true end end
    check("options: 'Default card cooldown' is 30-1800 s in 30 s steps, default 120, with the timing options", dc and dc.type == "numeric" and dc.range[1] == 30 and dc.range[2] == 1800 and dc.step_size_value == 30 and dc.default_value == 120 and listed and loc.tarot_default_cooldown.en == "Default card cooldown")
    local function getter(id) return settings[id] end
    local function cd() return Events.get("custom_5", getter, Groups).cooldown end
    settings.wave_def_custom_5 = "Mine\t3 hounds"; settings.cd_custom_5 = nil; settings.tarot_default_cooldown = nil; settings.tarot_longest = nil
    check("default cooldown: a card of your own with no cooldown set rests 120 s", cd() == 120, cd())
    settings.tarot_default_cooldown = 180
    check("default cooldown: the option sets it", cd() == 180)
    settings.tarot_default_cooldown = 45
    check("default cooldown: rounded to the 30 s grid (45 -> 60)", cd() == 60, cd())
    settings.tarot_default_cooldown = 5
    check("default cooldown: never below 30 s", cd() == 30)
    settings.tarot_default_cooldown = 3600
    check("default cooldown: never above the longest cooldown option (30 minutes by default and at most)", cd() == 1800, cd())
    settings.tarot_longest = 10
    settings.tarot_default_cooldown = 1800
    check("default cooldown: a player's shorter longest cooldown (10 minutes) still caps it", cd() == 600, cd())
    settings.tarot_longest = nil
    settings.tarot_longest = 30
    check("default cooldown: ...which follows that option", cd() == 1800)
    settings.tarot_longest = 4
    check("default cooldown: ...also when it is short (4 minutes)", cd() == 240)
    settings.tarot_longest = nil
    settings.cd_custom_5 = 90
    check("default cooldown: a cooldown set on the card itself always wins", cd() == 90)
    settings.tarot_default_cooldown = 300
    check("default cooldown: a standard card keeps its own cooldown (The Fool 120 s)", Events.get("wave_small", getter, Groups).cooldown == 120)
    Events.reset(function(id, value) settings[id] = value end, "custom_5")
    check("default cooldown: a custom slot that is reset goes back to the option (cd_ cleared)", settings.cd_custom_5 == nil and cd() == 300, tostring(settings.cd_custom_5))
    Events.reset(function(id, value) settings[id] = value end, "wave_small")
    check("default cooldown: resetting a standard card restores its own cooldown", settings.cd_wave_small == 120)
    settings.tarot_default_cooldown = nil; settings.wave_def_custom_5 = nil; settings.cd_custom_5 = nil; settings.cd_wave_small = nil
  end
  -- text next to the detail-screen steppers: node width minus 440 px, about 10 px per character
  local fits = { extra_dist_auto = 10, extra_dist_own = 10, extra_timer_off = 14, extra_timer_on = 14, extra_timer_wave = 42, extra_timer_ignored = 36, val_off = 4, val_auto = 4, share_timer = 12 }
  local cramped = {}
  for id, limit in pairs(fits) do if not loc[id] or #(loc[id].en:gsub("%%s", "00")) > limit then cramped[#cramped + 1] = id end end
  check("localization: texts beside the steppers fit their space", #cramped == 0, table.concat(cramped, ","))
  -- the Custom screen: a row name is one line (about 26 characters), the explanation two lines (about 138, like a modifier's)
  local tune_long = {}
  for _, def in ipairs(Groups.TUNE) do
    local name, info = loc["tune_" .. def.id], loc["tune_" .. def.id .. "_info"]
    if not name or not info then
      tune_long[#tune_long + 1] = def.id .. "(missing)"
    else
      local shown = info.en:gsub("%%d", tostring(def.min), 1):gsub("%%d", tostring(def.max), 1)
      if #name.en > 26 then tune_long[#tune_long + 1] = def.id .. " name(" .. #name.en .. ")" end
      if #shown > 138 then tune_long[#tune_long + 1] = def.id .. " info(" .. #shown .. ")" end
      if name.en ~= def.name then tune_long[#tune_long + 1] = def.id .. " name differs from Groups.TUNE" end
    end
  end
  check("localization: every custom mod has a name and an explanation that fit their row, and the same name as the catalog", #tune_long == 0, table.concat(tune_long, ","))
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
  check("spread: points stay inside the radius and are nav-snapped", max_r <= 5.0001 and all_snapped and moved >= 490, string.format("max %.2f moved %d", max_r, moved))
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

-- /rw_test_close: Positions.close_candidates / local_player_unit / rotation_towards with stubbed nav queries and players ----------
do
  local atan2 = math.atan2 or math.atan
  local V = {}
  V.__add = function(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, V) end
  V.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, V) end
  local saved = { v3 = Vector3, box = Vector3Box, q = Quaternion, unit = Unit, su = ScriptUnit, player = Managers.player, nav_mesh = Managers.state.nav_mesh, ext = Managers.state.extension }
  Vector3 = function(x, y, z) return setmetatable({ x = x, y = y, z = z }, V) end
  Vector3Box = function(v) return { unbox = function() return v end } end
  local look_args = {}
  Quaternion = { forward = function(rot) return rot.forward end, look = function(direction) look_args[#look_args + 1] = direction; return { look = direction } end }
  local dead, broken = {}, {}
  Unit = {
    alive = function(u) return not dead[u] end,
    world_position = function(u) if broken[u] then error("unit destroyed") end return u.pos end,
    world_rotation = function(u) return u.body end,
  }
  ScriptUnit = { has_extension = function(u, sys) return sys == "first_person_system" and u.fp or nil end }
  local function hero(forward_body, forward_look)
    local u = { pos = Vector3(0, 0, 5), body = { forward = forward_body } }
    if forward_look then u.fp = { extrapolated_rotation = function() return { forward = forward_look } end } end
    return u
  end
  local me, other = hero(Vector3(0, 1, 0.4), Vector3(1, 0, -0.3)), hero(Vector3(0, 1, 0))
  other.pos = Vector3(50, 50, 5)
  local heroes = { me, other }
  local local_unit = me
  Managers.player = { local_player = function(self, i) return local_unit and { player_unit = local_unit } or nil end }
  Managers.state.extension = { system = function() return { get_side_from_name = function() return { valid_player_units = heroes } end } end }
  Managers.state.nav_mesh = { nav_world = function() return "world" end }
  local nav = require("scripts/utilities/nav_queries")
  local saved_nav = { snap = nav.position_on_mesh, ray = nav.ray_can_go }
  local blocked = function() return false end
  nav.position_on_mesh = function(world, pos, above, below) if blocked(pos) then return nil end return Vector3(pos.x, pos.y, pos.z + 0.5) end
  nav.ray_can_go = function(world, a, b) return not blocked(b) end
  local Pos = load("spawn/positions")
  local function dist(p) return math.sqrt(p.x ^ 2 + p.y ^ 2) end
  local function all(list, fn) for i = 1, #list do if not fn(list[i]:unbox()) then return false end end return true end

  local list = Pos.close_candidates()
  check("close: points right in front of the player: 3.5 to 8 m away, inside a 70 degree arc round the camera's direction (+x), snapped to the mesh", list and #list >= 1 and #list <= 16 and all(list, function(p) local a = atan2(p.y, p.x); return dist(p) >= 3.49 and dist(p) <= 8.01 and math.abs(a) <= math.rad(35) + 1e-6 and p.z == 5.5 end), list and #list)
  check("close: the camera wins over the body (the body looks +y, the camera +x: no point lies behind the camera)", list and all(list, function(p) return p.x > 0 end))
  check("close: pick unboxes a candidate", (function() local p = Pos.pick(list); return type(p) == "table" and p.z == 5.5 end)())

  me.fp = nil
  list = Pos.close_candidates()
  check("close: without a first person view the body's direction is used (+y)", list and #list >= 1 and all(list, function(p) return p.y > 0 and math.abs(atan2(p.x, p.y)) <= math.rad(35) + 1e-6 end))
  me.fp = { extrapolated_rotation = function() return { forward = Vector3(0, 0, 1) } end }
  list = Pos.close_candidates()
  check("close: a camera looking straight up has no horizontal direction: the body decides", list and all(list, function(p) return p.y > 0 end))
  me.fp = { extrapolated_rotation = function() error("no camera yet") end }
  list = Pos.close_candidates()
  check("close: a camera that cannot be read falls back to the body", list and #list >= 1 and all(list, function(p) return p.y > 0 end))
  me.fp = nil; me.body = { forward = Vector3(0, 0, -1) }
  list = Pos.close_candidates()
  check("close: when nothing gives a direction the wave goes in front along +y, never nowhere", list and #list >= 1 and all(list, function(p) return p.y > 0 end))
  me.body = { forward = Vector3(0, 1, 0.4) }; me.fp = { extrapolated_rotation = function() return { forward = Vector3(1, 0, -0.3) } end }

  -- a wall in the way: only the near stage (1.5 to 3.5 m) is open
  blocked = function(p) return dist(p) > 3.5 end
  list = Pos.close_candidates()
  check("close: with a wall 3.5 m ahead the points come closer (1.5 to 3.5 m)", list and #list >= 1 and all(list, function(p) return dist(p) >= 1.49 and dist(p) <= 3.51 end), list and #list)
  blocked = function() return true end
  local none, reason = Pos.close_candidates()
  check("close: walls everywhere -> no points and a reason that says what to do", none == nil and type(reason) == "string" and reason:find("no walkable ground right in front of you", 1, true) ~= nil, tostring(reason))
  blocked = function() return false end

  Managers.state.nav_mesh = nil
  local _, nav_reason = Pos.close_candidates()
  check("close: no nav mesh (a hub) -> a reason, no error", nav_reason == "no nav mesh on this level")
  Managers.state.nav_mesh = { nav_world = function() return "world" end }

  -- who is "the player": the local one, else any living hero, else nobody; a unit that disappears mid-call is not an error
  check("close: the local player's unit is the one", Pos.local_player_unit() == me)
  dead[me] = true
  heroes = { other }
  check("close: a dead local player -> another living hero (the one of the hero side list)", Pos.local_player_unit() == other)
  local_unit = nil
  check("close: no local player at all (dedicated host) -> a living hero", Pos.local_player_unit() == other)
  heroes = {}
  check("close: nobody alive -> nil, and the search says so", Pos.local_player_unit() == nil and select(2, Pos.close_candidates()) == "no living players")
  dead[me] = nil; local_unit = me; heroes = { me, other }
  broken[me] = true
  local gone, gone_reason = Pos.close_candidates()
  check("close: a unit destroyed in the middle of the search is a reason, not an error", gone == nil and gone_reason == "no living players", tostring(gone_reason))
  broken[me] = nil
  local saved_manager = Managers.player
  Managers.player = nil
  local picked = Pos.local_player_unit()
  check("close: no player manager (a menu) is handled: a living hero", picked == me or picked == other)
  Managers.player = saved_manager

  -- facing the player
  look_args = {}
  local rot = Pos.rotation_towards(Vector3(10, 0, 5), me)
  check("close: a unit at +10 x faces the player: a flat unit direction towards -x (z is left out)", rot and look_args[1] and math.abs(look_args[1].x + 1) < 1e-9 and look_args[1].y == 0 and look_args[1].z == 0)
  check("close: standing on the player gives no rotation (the unit keeps its own)", Pos.rotation_towards(Vector3(0, 0, 5), me) == nil)
  broken[me] = true
  check("close: a player that is gone gives no rotation and no error", Pos.rotation_towards(Vector3(3, 3, 5), me) == nil)
  broken[me] = nil

  nav.position_on_mesh, nav.ray_can_go = saved_nav.snap, saved_nav.ray
  Vector3, Vector3Box, Quaternion, Unit, ScriptUnit = saved.v3, saved.box, saved.q, saved.unit, saved.su
  Managers.player, Managers.state.nav_mesh, Managers.state.extension = saved.player, saved.nav_mesh, saved.ext
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

-- Finite validation is shared by full preset and single-card imports. A correct
-- checksum must never make NaN/infinity valid or allow partial settings writes.
do
  is_server=false;Director.on_enter_gameplay()
  local accepted=pcall(Director.on_state,"host_peer",{p="waiting",m="vote",r=10,b=1,k={false,{k="valid",n="Valid",p=10,v=0}}})
  check("state: malformed authorized-host candidate is skipped without losing valid items", accepted and #Director.view().cands==1 and Director.view().cands[1].key=="valid")
  local many={};for i=1,100 do many[i]={k="k"..i,n="N",p=10,v=0} end
  Director.on_state("host_peer",{p="waiting",m="vote",r=10,b=1,k=many})
  check("state: candidates remain within the supported five-item bound and non-table state is ignored", #Director.view().cands==5 and pcall(Director.on_state,"host_peer",false))
  Director.on_exit_gameplay();is_server=true
end

do
  local fields={"wave_small","changed","1","10","120","3","10","60","1 hound{size=130}","0","0","0","0","swarm","0","","","1"}
  for _,index in ipairs({4,5,6,7,8,10,11,12,15}) do
    local original=fields[index]
    for _,value in ipairs({"nan","-nan","inf","-inf","1e309"}) do
      fields[index]=value
      local body=table.concat(fields,"~")
      local decoded=PresetsMod.decode(PresetsMod.seal("RW1|Preset|1|"..body),Events,Groups)
      local writes=0
      if decoded then PresetsMod.apply(decoded,function() writes=writes+1 end,Events,Groups) end
      local card=PresetsMod.decode_wave(PresetsMod.seal("RWW1|"..body),Events,Groups)
      check("import: non-finite field "..index.." "..value.." rejects preset/card atomically", decoded==nil and card==nil and writes==0)
    end
    fields[index]=original
  end
  local bad="RW1|Preset|1|wave_small~changed~1~nan~120~3~10~60~1 hound{size=130}~0~0~0~0~swarm~0~~~1|a6a3"
  check("import: exact audit NaN preset is rejected", PresetsMod.decode(bad,Events,Groups)==nil)
  fields[4]="1e300"
  local finite=PresetsMod.decode(PresetsMod.seal("RW1|Preset|1|"..table.concat(fields,"~")),Events,Groups)
  check("import: very large finite values still clamp and round-trip", finite~=nil and finite.waves[1].pct<math.huge and PresetsMod.decode(PresetsMod.encode(finite),Events,Groups)~=nil)
end

return table.concat(results, "\n") .. "\n--- echoes ---\n" .. table.concat(echoes, "\n")
'''
out = lua.execute(harness, ROOT.replace("\\", "/"))
print(out)
fails = [l for l in out.split("\n") if l.startswith("FAIL")]
print("\nFAILURES:", len(fails))
sys.exit(1 if fails else 0)

