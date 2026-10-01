-- Recipe parser and breed catalog for waves.
--   recipe text: "5 trappers, 5 mutants, 10 hounds"
--   random pick: "1 plague ogryn|beast of nurgle|chaos spawn"  (one of the alternatives per unit)
-- Alias table adapted from TwitchVersus catalog/groups.lua. Pure data/logic, no mod dependency.
--
--   repeat:      "5 crushers@2" = 5 at once, then 2 more on every repeat tick (see the wave's
--                repeat-every / repeat-for settings). "0 crushers@2" = only the repeats.
--   modifiers:   "3 crushers[enraged+garden]"  (order: count name[mods]{custom}@repeat)
--   custom mods: "3 crushers{health=150 size=130}"  numbers changed on the units of the group when they spawn, in percent
--                of the normal value (100 = unchanged), see Groups.TUNE
--
-- parts = { { breed = "name", count = n, rep = r, mods = { ids }, tune = { health = 150, ... } }  or
--           { one_of = { "a", "b" }, ... }, ... }
local Groups = {}

Groups.MAX_PARTS = 12
Groups.MAX_BREED_COUNT = 60
Groups.MAX_TOTAL = 120

-- The first alias of each breed is its display name.
local ALIASES = {
	chaos_armored_hound = { "armored hound", "armoured hound", "tank hound" },
	chaos_hound = { "hound", "dog", "pox hound" },
	chaos_poxwalker_bomber = { "burster", "poxburster", "pox burster", "pox bomber" },
	cultist_flamer = { "tox flamer", "dreg flamer" },
	cultist_grenadier = { "tox bomber", "dreg bomber", "tox grenadier" },
	cultist_mutant = { "mutant", "mutie", "charger" },
	renegade_flamer = { "flamer", "scab flamer" },
	renegade_grenadier = { "bomber", "grenadier", "scab bomber" },
	renegade_netgunner = { "trapper", "netgunner", "net gunner" },
	renegade_sniper = { "sniper", "scab sniper" },
	chaos_ogryn_bulwark = { "bulwark", "shield ogryn" },
	chaos_ogryn_executor = { "crusher", "ogryn crusher" },
	chaos_ogryn_gunner = { "reaper", "reaper ogryn" },
	cultist_berzerker = { "rager", "berzerker", "berserker", "tox rager" },
	cultist_gunner = { "dreg gunner", "tox gunner" },
	cultist_shocktrooper = { "dreg shocktrooper", "dreg shotgunner" },
	renegade_berzerker = { "scab rager", "scab berzerker" },
	renegade_executor = { "mauler", "scab mauler" },
	renegade_gunner = { "gunner", "scab gunner" },
	renegade_plasma_gunner = { "plasma gunner", "plasma" },
	renegade_radio_operator = { "radio operator", "radio" },
	renegade_shocktrooper = { "shocktrooper", "shotgunner" },
	chaos_beast_of_nurgle = { "beast of nurgle", "beast", "slug" },
	chaos_daemonhost = { "daemonhost", "daemon host" },
	chaos_ogryn_houndmaster = { "packmaster", "pack master", "beastmaster", "houndmaster", "hound master" },
	chaos_plague_ogryn = { "plague ogryn", "plague", "pogryn" },
	chaos_spawn = { "chaos spawn", "spawn" },
	-- the Twins are two separate breeds (male / female); the game's monster pacing links them
	-- (shared health, "empowered_twin"), a wave spawns each one on its own
	-- renegade_twin_captain spawns with a plasma pistol (spawn_inventory_slot = slot_plasma_pistol), the second twin
	-- with a power sword (slot_power_sword): ranged and melee. The old names stay valid in recipes.
	renegade_twin_captain = { "ranged twin", "twin captain one", "twin one", "male twin", "twin captain" },
	renegade_twin_captain_two = { "melee twin", "twin captain two", "twin two", "female twin" },
	cultist_captain = { "dreg captain", "tox captain" },
	renegade_captain = { "captain", "scab captain" },
	chaos_armored_infected = { "armored infected", "armoured infected" },
	chaos_lesser_mutated_poxwalker = { "lesser mutated poxwalker", "lesser poxwalker" },
	chaos_mutated_poxwalker = { "mutated poxwalker", "big poxwalker" },
	chaos_newly_infected = { "newly infected", "infected" },
	chaos_poxwalker = { "poxwalker", "pox walker", "zombie", "walker" },
	cultist_assault = { "dreg assault" },
	cultist_melee = { "dreg", "dreg melee" },
	cultist_vanguard = { "dreg vanguard" },
	renegade_assault = { "scab assault" },
	renegade_melee = { "scab", "scab melee" },
	renegade_rifleman = { "rifleman", "scab rifleman", "shooter" },
	renegade_vanguard = { "scab vanguard" },
}

-- Modifiers: Havoc-style conditions that can be forced onto a group of enemies
-- even if the mission did not load them. Each one is a list of vanilla buff
-- templates (S\settings\buff\havoc_buff_templates.lua / mutator_buff_templates.lua)
-- added to the unit right after it spawns, the same way the mutators do.
-- Only buffs that are self-contained were audited in; see docs/03 ("Havoc conditions").
--   requires_havoc: the buff reads the Havoc game-mode extension and errors without it.
-- Recipe syntax: "3 crushers[enraged+garden]".
--   prepare: name of a setup step Execute runs before the buff is added (see spawn/execute.lua);
--            if it fails the modifier is skipped instead of risking an error later.
-- Display names follow the Havoc colour naming; the ids and the old names stay valid in recipes.
Groups.MODIFIERS = {
	{
		id = "garden", name = "Purple", buffs = { "havoc_encroaching_garden" },
		aliases = { "purple", "garden", "encroaching garden", "gardens embrace" },
		description = "Encroaching Garden. Extra health, resists impact, and heals nearby enemies.",
	},
	{
		id = "enraged", name = "Enraged", buffs = { "havoc_enraged_enemies" },
		aliases = { "enraged", "enrage", "rage" },
		description = "Enraged from the start: faster melee, no stagger, more hit mass, faster movement.",
	},
	{
		id = "toll", name = "Red", buffs = { "havoc_enraged_enemies_trigger" },
		aliases = { "red", "toll", "final toll", "the final toll", "enraged at half" },
		description = "The Final Toll. Becomes enraged once it drops below half health (the vanilla Final Toll).",
	},
	{
		id = "corrupted", name = "Blight", buffs = { "havoc_corrupted_enemies" },
		aliases = { "blight", "corrupted", "corruption" },
		description = "Nurgle-corrupted: leaves corruption behind when it dies.",
	},
	{
		id = "bolstering", name = "Orange", buffs = { "havoc_bolstering" },
		aliases = { "orange", "rampaging", "rampaging enemies", "bolstering", "bolstered", "bolster" },
		description = "Rampaging Enemies. Slightly bigger and tougher (takes less damage). When it dies, enemies within 4 m get another stack, up to 5.",
	},
	{
		id = "toughened", name = "Pus-Hardened Skin", buffs = { "havoc_toughened_skin" }, requires_havoc = true,
		aliases = { "pus hardened skin", "pus hardened", "pushardened", "toughened", "tough", "toughened skin", "tough skin" },
		description = "Tougher skin against ranged damage.",
	},
	{
		id = "fire", name = "On Fire", buffs = { "common_minion_on_fire" },
		aliases = { "fire", "burning", "on fire" },
		description = "Burning: sets players next to it on fire.",
	},
	{
		id = "parasite", name = "Head Parasite", buffs = { "headshot_parasite_enemies" },
		aliases = { "parasite", "head parasite", "infested" },
		description = "Nurgle parasite: tougher, faster, immune to suppression. Its visuals may be missing.",
	},
	{
		-- buff mutator_stimmed_minion_purple (mutator_buff_templates.lua:326). When the enemy dies it
		-- bursts and splits into two weaker enemies (a fixed breed table), which are stimmed again if
		-- that breed splits further. The death effect calls
		-- Managers.state.mutator:mutator("mutator_stimmed_minions_purple"):add_split_spawn(...), but that
		-- mutator has no template in the game, so Execute creates the class itself ("purple_stimm" prepare step).
		id = "purple_stimm", name = "Purple Stimm", buffs = { "mutator_stimmed_minion_purple" }, prepare = "purple_stimm",
		aliases = { "purple stimm", "purple stimmed", "purple stim", "stimmed purple", "purple split", "splitting" },
		description = "Purple stimmed: when it dies it bursts and splits into two weaker enemies, which can split again. The split enemies are extra units.",
	},
	{
		-- buff mutator_rotten_armor (havoc_buff_templates.lua:684-772, thresholds/armor overrides in
		-- havoc_mutator_local_settings.lua:461-526). Damage taken x0.25 at full health, x0.5 below 90%, x0.75
		-- below 75%, x1 below 50%, x1.25 below 25%; head and limbs count as "disgustingly resilient" armor
		-- (armor.lua:40-46); slower animation; toxic puddle on death. The game only ever gives it to these three
		-- breeds (breed_chances), which are also the only ones with rotten armor models.
		id = "rotten", name = "Rotten Armor", buffs = { "mutator_rotten_armor" }, skip_if_present = true,
		only_breeds = { renegade_executor = "Scab Mauler", renegade_berzerker = "Scab Rager", chaos_ogryn_executor = "Crusher" },
		aliases = { "rotten", "rotten armor", "rotten armour", "rotting", "rotten armored" },
		description = "Scab Mauler, Scab Rager, Crusher only. Takes 1/4 damage at full health, rising as it is hurt. Toxic puddle on death. No rotten model.",
	},
}

local modifier_by_id = {}
local modifier_alias = {}
local modifier_order = {}

local function normalize_word(word)
	return (tostring(word or ""):lower():gsub("[^%a]", ""))
end

for index, modifier in ipairs(Groups.MODIFIERS) do
	modifier_by_id[modifier.id] = modifier
	modifier_order[modifier.id] = index
	modifier_alias[normalize_word(modifier.id)] = modifier.id

	for _, alias in ipairs(modifier.aliases) do
		modifier_alias[normalize_word(alias)] = modifier.id
	end
end

Groups.modifier = function (id)
	return modifier_by_id[id]
end

-- "Mauler, Rager and Crusher" for a modifier with `only_breeds`
Groups.only_breeds_text = function (modifier)
	local names = {}

	for _, name in pairs(modifier.only_breeds or {}) do
		names[#names + 1] = name
	end

	table.sort(names)

	return table.concat(names, ", ")
end

Groups.modifier_id = function (word)
	return modifier_alias[normalize_word(word)]
end

-- for error messages: "garden/purple, enraged, toll/red, ..." (id, and the display name when different)
do
	local names = {}

	for index, modifier in ipairs(Groups.MODIFIERS) do
		local display = normalize_word(modifier.name) ~= normalize_word(modifier.id) and ("/" .. modifier.name:lower()) or ""

		names[index] = modifier.id .. display
	end

	Groups.MODIFIER_IDS = table.concat(names, ", ")
end

-- Custom mods ("tuning"): numbers changed on every unit of a group right after it spawns, in PERCENT of the normal value
-- (100 = unchanged). They are stored in `part.tune` (only the ones that differ from 100) and written in the recipe as
-- "{health=150 size=130}" after the modifiers. How each one is applied is in spawn/tuning.lua.
--   health   the unit's maximum health (a spawn parameter of the game, so every player sees the right bar)
--   size     the size of the model (`Unit.set_local_scale`, also sent to the other players that have this mod)
--   speed    run speed (a movement modifier of the navigation: how fast it walks, trots or runs after you)
--   gap      time between attacks, in percent of the normal time (50 = half the wait, 200 = twice): it writes the game's own
--            `melee_attack_speed` stat as 100 / value, which ends a melee attack early (see spawn/tuning.lua). It used to
--            be called "melee attack speed" with the number the other way round (200 = twice as fast); recipes written
--            with the old names (`melee=200`) are read as the new setting (`gap=50`, the `legacy` field below)
--   fire     gunner fire rate (the time between two shots: the game's own `ranged_attack_speed` stat)
--   burst    shots per burst (the game's `minion_num_shots_modifier`, a fraction rounds up to one more shot)
--   explosion / dot  the share of explosion damage / of burning, toxin and bleeding damage the unit takes (50 = half,
--            0 = none): the game's `damage_taken_from_*` stats
--   mass     hit mass (how much of a player's attack one hit of it soaks up, which decides how many enemies one swing can
--            cut through: the unit's own `hit_mass`)
Groups.TUNE = {
	{ id = "health", name = "Health", min = 10, max = 1000, step = 10, aliases = { "health", "hp", "life" } },
	{ id = "size", name = "Size", min = 25, max = 300, step = 5, aliases = { "size", "scale" } },
	{ id = "speed", name = "Run speed", min = 25, max = 300, step = 5, aliases = { "speed", "run", "run speed", "runspeed", "move speed", "movement" } },
	{ id = "gap", name = "Time between attacks", min = 25, max = 400, step = 5, aliases = { "gap", "time between attacks", "attack gap", "attack time", "attack delay", "attack interval" }, legacy = { "melee", "melee speed", "melee attack speed", "melee attack", "attack speed" } },
	{ id = "fire", name = "Gunner fire rate", min = 25, max = 400, step = 5, aliases = { "fire", "fire rate", "firerate", "gunner fire rate", "ranged", "ranged speed", "ranged attack speed" } },
	{ id = "burst", name = "Shots per burst", min = 25, max = 500, step = 25, aliases = { "burst", "shots", "shots per burst", "burst size" } },
	{ id = "mass", name = "Hit mass", min = 10, max = 1000, step = 10, aliases = { "mass", "hit mass", "hitmass" } },
	{ id = "explosion", name = "Explosion damage taken", min = 0, max = 300, step = 5, aliases = { "explosion", "explosions", "explosion damage", "blast" } },
	{ id = "dot", name = "Damage over time taken", min = 0, max = 300, step = 5, aliases = { "dot", "dot damage", "damage over time", "burn", "burning", "toxin" } },
}

local tune_by_id = {}
local tune_alias = {}
local tune_legacy = {} -- old names whose number was a SPEED while the setting that replaced them is a time
local tune_ids = {}

for index, def in ipairs(Groups.TUNE) do
	tune_by_id[def.id] = def
	tune_ids[index] = def.id
	tune_alias[normalize_word(def.id)] = def.id

	for _, alias in ipairs(def.aliases) do
		tune_alias[normalize_word(alias)] = def.id
	end

	for _, alias in ipairs(def.legacy or {}) do
		tune_alias[normalize_word(alias)] = def.id
		tune_legacy[normalize_word(alias)] = true
	end
end

Groups.TUNE_IDS = table.concat(tune_ids, ", ")

Groups.tune_def = function (id)
	return tune_by_id[id]
end

-- the value in percent clamped to the allowed range of that setting (and rounded to a whole number)
Groups.clamp_tune = function (id, value)
	local def = tune_by_id[id]

	value = math.floor((tonumber(value) or 100) + 0.5)

	if not def then
		return value
	end

	return math.max(def.min, math.min(def.max, value))
end

-- A copy of a part's custom mods (nil when it has none).
Groups.copy_tune = function (tune)
	if not tune or next(tune) == nil then
		return nil
	end

	local copy = {}

	for id, value in pairs(tune) do
		copy[id] = value
	end

	return copy
end

-- "health=150 size=130": the ones that differ from 100, in catalog order ("" for none).
Groups.tune_recipe = function (tune)
	local fields = {}

	for _, def in ipairs(Groups.TUNE) do
		local value = tune and tune[def.id]

		if value and value ~= 100 then
			fields[#fields + 1] = def.id .. "=" .. value
		end
	end

	return table.concat(fields, " ")
end

-- "Health 150%, Size 130%": for the rows of the editor ("" for none).
Groups.tune_text = function (tune)
	local fields = {}

	for _, def in ipairs(Groups.TUNE) do
		local value = tune and tune[def.id]

		if value and value ~= 100 then
			fields[#fields + 1] = def.name .. " " .. value .. "%"
		end
	end

	return table.concat(fields, ", ")
end

-- true when at least one group of the recipe has custom mods
Groups.has_tune = function (parts)
	for i = 1, #(parts or {}) do
		if parts[i].tune and next(parts[i].tune) ~= nil then
			return true
		end
	end

	return false
end

-- Reads the inside of "{...}": pairs of a name and a number, separated by spaces (commas and the like count as spaces):
-- "health=150 size 130", "run speed 120%". Returns the table, nil for nothing to change, or nil and an error text.
local function parse_tune(inner)
	local rest = inner:gsub("[,;/%+&]+", " ")
	local tune = {}
	local pos = 1

	while true do
		local start = rest:find("%S", pos)

		if not start then
			break
		end

		local _, stop, name, number = rest:find("^(%a[%a ]-)%s*[=:]?%s*(%d+%.?%d*)%s*%%?", start)

		if not stop then
			return nil, string.format("%q needs a number, like health=150. Custom mods: %s", rest:sub(start):match("^%S+"), Groups.TUNE_IDS)
		end

		local id = tune_alias[normalize_word(name)]

		if not id then
			return nil, string.format("%q is not a custom mod I know. Valid ones: %s", (name:gsub("%s+$", "")), Groups.TUNE_IDS)
		end

		local amount = tonumber(number)

		if tune_legacy[normalize_word(name)] then
			-- an old name: its number was a speed, the setting is a time now (200 percent as fast = half the time)
			amount = amount > 0 and 10000 / amount or tune_by_id[id].max
		end

		local value = Groups.clamp_tune(id, amount)

		tune[id] = value ~= 100 and value or nil
		pos = stop + 1
	end

	return next(tune) ~= nil and tune or nil
end

Groups.parse_tune = parse_tune

-- Kinds, from the game's own breed tags (S\settings\breed\breeds\...\<breed>_breed.lua):
--   special = tags.special;  boss = tags.monster / tags.captain / tags.cultist_captain (includes the
--   twins, daemonhost, packmaster);  elite = tags.elite;  everything else is normal (horde/roamer).
-- The wave multiplier sliders group them as: normal + elite, boss, special.
local KIND_LISTS = {
	special = {
		"chaos_armored_hound", "chaos_hound", "chaos_poxwalker_bomber", "cultist_flamer", "cultist_grenadier",
		"cultist_mutant", "renegade_flamer", "renegade_grenadier", "renegade_netgunner", "renegade_sniper",
	},
	boss = {
		"chaos_beast_of_nurgle", "chaos_daemonhost", "chaos_ogryn_houndmaster", "chaos_plague_ogryn", "chaos_spawn",
		"renegade_twin_captain", "renegade_twin_captain_two", "cultist_captain", "renegade_captain",
	},
	elite = {
		"chaos_ogryn_bulwark", "chaos_ogryn_executor", "chaos_ogryn_gunner", "cultist_berzerker", "cultist_gunner",
		"cultist_shocktrooper", "renegade_berzerker", "renegade_executor", "renegade_gunner", "renegade_plasma_gunner",
		"renegade_radio_operator", "renegade_shocktrooper",
	},
}

local kind_of = {}

for kind, list in pairs(KIND_LISTS) do
	for i = 1, #list do
		kind_of[list[i]] = kind
	end
end

-- "special" | "boss" | "elite" | "normal"
Groups.kind = function (breed_name)
	return kind_of[breed_name] or "normal"
end

-- Multiplier group of a breed: "special" | "boss" | "normal" (normal covers elites too).
Groups.category = function (breed_name)
	local kind = kind_of[breed_name]

	if kind == "special" or kind == "boss" then
		return kind
	end

	return "normal"
end

local function normalize(word)
	word = tostring(word or ""):lower()
	word = word:gsub("[_%-%.]", " ")
	word = word:gsub("[^%a%s]", "")
	word = word:gsub("%s+", " ")

	return (word:gsub("^%s*(.-)%s*$", "%1"))
end

local alias_map = {}
local sorted_breeds = {}
local sample_aliases = "trapper, hound, mutant, burster, rager, mauler, crusher, bulwark, reaper, sniper, poxwalker, scab, dreg"

for breed_name, list in pairs(ALIASES) do
	alias_map[normalize(breed_name)] = breed_name

	for i = 1, #list do
		alias_map[normalize(list[i])] = breed_name
	end

	sorted_breeds[#sorted_breeds + 1] = breed_name
end

table.sort(sorted_breeds, function (a, b)
	return ALIASES[a][1] < ALIASES[b][1]
end)

local function title_case(text)
	local result = text:gsub("(%a)([%w]*)", function (first, rest)
		return first:upper() .. rest
	end)

	return (result:gsub(" Of ", " of "))
end

-- "renegade_netgunner" -> "Trapper"
Groups.display_name = function (breed_name)
	local list = ALIASES[breed_name]

	return list and title_case(list[1]) or tostring(breed_name)
end

-- Alias used when writing a breed back into recipe text.
Groups.recipe_name = function (breed_name)
	local list = ALIASES[breed_name]

	return list and list[1] or tostring(breed_name)
end

-- All spawnable breeds, sorted by display name.
Groups.breed_list = function ()
	local copy = {}

	for i = 1, #sorted_breeds do
		copy[i] = sorted_breeds[i]
	end

	return copy
end

-- Search text per breed: id, every alias, and its kind words ("boss monster captain", "special", "elite", "horde").
local search_text = {}

for _, breed_name in ipairs(sorted_breeds) do
	local words = { normalize(breed_name) }

	for _, alias in ipairs(ALIASES[breed_name]) do
		words[#words + 1] = normalize(alias)
	end

	local kind = kind_of[breed_name]

	words[#words + 1] = kind == "boss" and "boss monster captain" or kind or "normal horde"
	search_text[breed_name] = table.concat(words, " ")
end

-- Breeds matching every word of `query` (in the id, an alias, or the kind), sorted like breed_list().
-- Empty query = all breeds.
Groups.search = function (query)
	local tokens = {}

	for word in normalize(query):gmatch("%S+") do
		tokens[#tokens + 1] = word
	end

	if #tokens == 0 then
		return Groups.breed_list()
	end

	local result = {}

	for _, breed_name in ipairs(sorted_breeds) do
		local text = search_text[breed_name]
		local matches = true

		for i = 1, #tokens do
			if not text:find(tokens[i], 1, true) then
				matches = false

				break
			end
		end

		if matches then
			result[#result + 1] = breed_name
		end
	end

	return result
end

Groups.is_known = function (breed_name)
	return ALIASES[breed_name] ~= nil
end

local function lookup(name)
	local key = normalize(name)

	if alias_map[key] then
		return alias_map[key]
	end

	local without_es = key:match("^(.-)es$")

	if without_es and alias_map[without_es] then
		return alias_map[without_es]
	end

	local without_s = key:match("^(.-)s$")

	if without_s and alias_map[without_s] then
		return alias_map[without_s]
	end
end

local function split_count(field)
	local count, name = field:match("^(%d+)%s*[xX%*]?%s*(.+)$")

	if count then
		return tonumber(count), name
	end

	name, count = field:match("^(.-)%s*[xX%*]%s*(%d+)$")

	if count then
		return tonumber(count), name
	end

	name, count = field:match("^(.-)%s+(%d+)$")

	if count then
		return tonumber(count), name
	end

	return 1, field
end

local function part_key(part)
	local key = part.one_of and table.concat(part.one_of, "|") or part.breed

	if part.mods then
		key = key .. "[" .. table.concat(part.mods, "+") .. "]"
	end

	if part.tune then
		key = key .. "{" .. Groups.tune_recipe(part.tune) .. "}"
	end

	return key
end

-- Splits "enraged|garden" into canonical, de-duplicated modifier ids (in catalog order).
local function parse_modifiers(inner)
	local seen, ids = {}, {}

	local function add(id)
		if not seen[id] then
			seen[id] = true
			ids[#ids + 1] = id
		end
	end

	for raw_piece in inner:gmatch("[^|]+") do
		local piece = raw_piece:gsub("^%s*(.-)%s*$", "%1")

		if piece ~= "" then
			-- whole piece first ("final toll", "pus-hardened skin"), then word by word so the
			-- old style "[enraged garden]" (separated by spaces only) keeps working
			local id = modifier_alias[normalize_word(piece)]

			if id then
				add(id)
			else
				for word in piece:gmatch("%S+") do
					local word_id = modifier_alias[normalize_word(word)]

					if not word_id then
						return nil, string.format("%q is not a modifier I know. Valid modifiers: %s", piece, Groups.MODIFIER_IDS)
					end

					add(word_id)
				end
			end
		end
	end

	table.sort(ids, function (a, b)
		return modifier_order[a] < modifier_order[b]
	end)

	return #ids > 0 and ids or nil
end

-- Returns parts on success, or nil and an error message.
Groups.parse = function (recipe)
	if type(recipe) ~= "string" or recipe:match("^%s*$") then
		return nil, "the recipe is empty. Write something like: 5 trappers, 5 mutants, 10 hounds"
	end

	local text = " " .. recipe .. " "

	-- protect the modifier list in [...] from the separator handling below:
	-- "[enraged, garden]" / "[enraged and garden]" -> "[enraged|garden]"
	text = text:gsub("%[(.-)%]", function (inner)
		-- separators inside the brackets: , ; / + & and the word "and". Spaces are NOT separators
		-- (modifier names such as "final toll" contain them); parse_modifiers handles space-only lists.
		inner = inner:gsub("%s+[aA][nN][dD]%s+", "+")
		inner = inner:gsub("%s*[,;/%+&]+%s*", "|")

		return "[" .. inner .. "]"
	end)

	-- the same for the custom mods in {...}: their separators are spaces ("{health=150 size=130}")
	text = text:gsub("{(.-)}", function (inner)
		inner = inner:gsub("%s+[aA][nN][dD]%s+", " ")
		inner = inner:gsub("[,;/%+&]+", " ")

		return "{" .. inner .. "}"
	end)

	text = text:gsub("%s+[aA][nN][dD]%s+", ",")
	text = text:gsub("[\n\r;/%+&]", ",")

	local parts, by_key, total = {}, {}, 0

	for raw_field in text:gmatch("[^,]+") do
		local field = raw_field:gsub("^%s*(.-)%s*$", "%1")

		if field ~= "" then
			local count, name = split_count(field)

			name = name:gsub("^%s*(.-)%s*$", "%1")

			if name == "" or name:match("^%d+$") then
				return nil, string.format("%q is a number with no enemy after it. Write it as \"5 trappers\"", field)
			end

			-- trailing "@N": units added on every repeat tick; "@=" / "@same": the same number as
			-- the initial spawn on every tick
			local rep, rep_same
			local without_rep, rep_text = name:match("^(.-)%s*@%s*(%d+)%s*$")

			if without_rep then
				name = without_rep
				rep = math.min(tonumber(rep_text), Groups.MAX_BREED_COUNT)
			else
				local same_base = name:match("^(.-)%s*@%s*=%s*$") or name:match("^(.-)%s*@%s*[sS][aA][mM][eE]%s*$")

				if same_base then
					name = same_base
					rep_same = true
				end
			end

			-- custom mods "{health=150}" come after the modifiers: "crusher[enraged]{health=150}"
			local tune
			local without_tune, tune_inner = name:match("^(.-)%s*{(.-)}%s*$")

			if without_tune then
				local tune_err

				tune, tune_err = parse_tune(tune_inner)

				if tune_err then
					return nil, tune_err
				end

				name = without_tune
			end

			local mods
			local base, inner = name:match("^(.-)%s*%[(.-)%]%s*$")

			if base then
				local err

				mods, err = parse_modifiers(inner)

				if err then
					return nil, err
				end

				name = base
			end

			local new_part

			if name:find("|", 1, true) then
				local alternatives = {}

				for alt in name:gmatch("[^|]+") do
					local breed_name = lookup(alt)

					if not breed_name then
						return nil, string.format("%q is not an enemy I know. Valid names include: %s", alt, sample_aliases)
					end

					alternatives[#alternatives + 1] = breed_name
				end

				if #alternatives == 1 then
					new_part = { breed = alternatives[1], count = 0 }
				elseif #alternatives > 1 then
					new_part = { one_of = alternatives, count = 0 }
				end
			else
				local breed_name = lookup(name)

				if not breed_name then
					return nil, string.format("%q is not an enemy I know. Valid names include: %s", name, sample_aliases)
				end

				new_part = { breed = breed_name, count = 0 }
			end

			if new_part then
				new_part.mods = mods
				new_part.tune = tune

				local key = part_key(new_part)
				local part = by_key[key]

				if not part then
					if #parts >= Groups.MAX_PARTS then
						break
					end

					part = new_part
					by_key[key] = part
					parts[#parts + 1] = part
				end

				local room = math.max(0, Groups.MAX_TOTAL - total)
				local add = math.min(count, Groups.MAX_BREED_COUNT - part.count, room)

				if add > 0 then
					part.count = part.count + add
					total = total + add
				end

				if rep and rep > 0 then
					part.rep = math.min((part.rep or 0) + rep, Groups.MAX_BREED_COUNT)
				end

				if rep_same then
					part.rep_same = true
				end
			end
		end
	end

	local result = {}

	for i = 1, #parts do
		if parts[i].count > 0 or (parts[i].rep or 0) > 0 then -- (a "same" group with count 0 repeats nothing)
			result[#result + 1] = parts[i]
		end
	end

	if #result == 0 then
		return nil, "nothing in the recipe looks like an enemy"
	end

	return result
end

-- parts -> recipe text that Groups.parse reads back to the same parts.
Groups.to_recipe = function (parts)
	local fields = {}

	for i = 1, #(parts or {}) do
		local part = parts[i]
		local names = {}

		if part.one_of then
			for j = 1, #part.one_of do
				names[j] = Groups.recipe_name(part.one_of[j])
			end
		else
			names[1] = Groups.recipe_name(part.breed)
		end

		local field = part.count .. " " .. table.concat(names, "|")

		if part.mods and #part.mods > 0 then
			field = field .. "[" .. table.concat(part.mods, "+") .. "]"
		end

		local tune_text = Groups.tune_recipe(part.tune)

		if tune_text ~= "" then
			field = field .. "{" .. tune_text .. "}"
		end

		if part.rep_same then
			field = field .. "@="
		elseif (part.rep or 0) > 0 then
			field = field .. "@" .. part.rep
		end

		fields[#fields + 1] = field
	end

	return table.concat(fields, ", ")
end

-- "Enraged, Garden" for a part's modifiers ("" when none).
Groups.describe_mods = function (part)
	local names = {}

	for i = 1, #(part.mods or {}) do
		local modifier = modifier_by_id[part.mods[i]]

		names[i] = modifier and modifier.name or tostring(part.mods[i])
	end

	return table.concat(names, ", ")
end

-- The three pieces of a part's text: head "8 Poxwalker" (or "1 random of A / B"), the modifiers as a list of
-- { id, name } and the repeat note " (+2 per repeat)" / " (same amount on every repeat)" ("" for none).
Groups.describe_part_pieces = function (part)
	local head

	if part.one_of then
		local names = {}

		for i = 1, #part.one_of do
			names[i] = Groups.display_name(part.one_of[i])
		end

		head = string.format("%d random of %s", part.count, table.concat(names, " / "))
	else
		head = string.format("%d %s", part.count, Groups.display_name(part.breed))
	end

	local modifiers = {}

	for i = 1, #(part.mods or {}) do
		local modifier = modifier_by_id[part.mods[i]]

		modifiers[i] = { id = part.mods[i], name = modifier and modifier.name or tostring(part.mods[i]) }
	end

	local tail = ""

	if part.rep_same then
		tail = " (same amount on every repeat)"
	elseif (part.rep or 0) > 0 then
		tail = string.format(" (+%d per repeat)", part.rep)
	end

	return head, modifiers, tail
end

-- Short human text for a part: "8 Poxwalker" / "1 random of Plague Ogryn / Chaos Spawn".
-- With `with_mods` the modifiers follow in brackets: "3 Crusher [Enraged]".
Groups.describe_part = function (part, with_mods)
	local head, modifiers, tail = Groups.describe_part_pieces(part)
	local text = head

	if with_mods and #modifiers > 0 then
		text = text .. " [" .. Groups.describe_mods(part) .. "]"
	end

	if with_mods then
		text = text .. tail
	end

	return text
end
-- units a group adds on one repeat tick, before the type multiplier
Groups.repeat_amount = function (part)
	if part.rep_same then
		return part.count or 0
	end

	return part.rep or 0
end

-- true when at least one enemy group repeats
Groups.has_repeat = function (parts)
	for i = 1, #(parts or {}) do
		if Groups.repeat_amount(parts[i]) > 0 then
			return true
		end
	end

	return false
end

Groups.total_count = function (parts)
	local total = 0

	for i = 1, #(parts or {}) do
		total = total + parts[i].count
	end

	return total
end

-- The text of a part as segments { text, kind, breed, mod } so each piece can get its own colour:
-- kind "base" (the enemy colour of the whole part), "breed" (one enemy of a random group), "mod" (a modifier
-- name) or "plain". The concatenated texts equal Groups.describe_part(part, with_mods).
Groups.part_segments = function (part, with_mods)
	local segments = {}

	local function add(text, kind, breed, mod_id)
		segments[#segments + 1] = { text = text, kind = kind, breed = breed, mod = mod_id }
	end

	if part.one_of then
		add(string.format("%d random of ", part.count), "plain")

		for i = 1, #part.one_of do
			if i > 1 then
				add(" / ", "plain")
			end

			add(Groups.display_name(part.one_of[i]), "breed", part.one_of[i])
		end
	else
		add(string.format("%d %s", part.count, Groups.display_name(part.breed)), "base")
	end

	if with_mods then
		local _, modifiers, tail = Groups.describe_part_pieces(part)

		if #modifiers > 0 then
			add(" [", "base")

			for i = 1, #modifiers do
				if i > 1 then
					add(", ", "base")
				end

				add(modifiers[i].name, "mod", nil, modifiers[i].id)
			end

			add("]", "base")
		end

		if tail ~= "" then
			add(tail, "base")
		end
	end

	return segments
end

-- Appends the part's segments to `list` with their colour `rgb` resolved through the painter table.
Groups.paint_part_segments = function (part, painter, with_mods, list)
	list = list or {}

	local base = painter.part and painter.part(part)
	local segments = Groups.part_segments(part, with_mods)

	for i = 1, #segments do
		local segment = segments[i]
		local rgb

		if segment.kind == "base" then
			rgb = base
		elseif segment.kind == "breed" then
			rgb = painter.breed and painter.breed(segment.breed) or nil
		elseif segment.kind == "mod" then
			rgb = painter.mod and painter.mod(segment.mod) or base
		end

		list[#list + 1] = { text = segment.text, rgb = rgb }
	end

	return list
end

-- Joins coloured segments { text, rgb } into one string, cut to `max_chars` VISIBLE characters ("..." when cut, the
-- same rule as Groups.summary: the first max_chars - 3 characters). markup(text, rgb) wraps a coloured piece.
Groups.render_segments = function (segments, max_chars, markup)
	local total = 0

	for i = 1, #segments do
		total = total + #segments[i].text
	end

	local cut = max_chars and total > max_chars
	local budget = cut and (max_chars - 3) or math.huge
	local out = {}

	for i = 1, #segments do
		if budget <= 0 then
			break
		end

		local text = segments[i].text

		if #text > budget then
			text = text:sub(1, budget)
		end

		budget = budget - #text
		out[#out + 1] = segments[i].rgb and markup(text, segments[i].rgb) or text
	end

	return table.concat(out) .. (cut and "..." or "")
end
-- "4 Hound, 2 Scab Rager [Enraged]" shortened to `max_chars` visible characters (with "...").
-- `paint` (optional) is function (text, part) -> text wrapped in colour tags; the tags never count
-- towards the length, so the visible text is identical to the plain summary.
Groups.summary = function (parts, max_chars, paint)
	local pieces = {}

	for i = 1, #(parts or {}) do
		pieces[i] = Groups.describe_part(parts[i], true)
	end

	local text = table.concat(pieces, ", ")
	local cut = max_chars and #text > max_chars

	if not paint then
		return cut and (text:sub(1, max_chars - 3) .. "...") or text
	end

	-- A painter TABLE { part = function (part) -> rgb, breed = function (breed) -> rgb, mod = function (id) -> rgb,
	-- markup = function (text, rgb) } colours the enemy names, each enemy of a random group and each modifier
	-- name separately (colours survive the cut: the segments are cut, not the finished text).
	if type(paint) == "table" then
		local segments = {}

		for i = 1, #parts do
			if i > 1 then
				segments[#segments + 1] = { text = ", " }
			end

			segments = Groups.paint_part_segments(parts[i], paint, true, segments)
		end

		return Groups.render_segments(segments, max_chars, paint.markup)
	end

	local out = {}
	local budget = cut and (max_chars - 3) or math.huge

	for i = 1, #pieces do
		local piece = pieces[i]
		local separator = i > 1 and ", " or ""

		if #separator + #piece > budget then
			local room = budget - #separator

			if room > 0 then
				out[#out + 1] = separator .. paint(piece:sub(1, room), parts[i])
			elseif #separator > 0 and budget > 0 then
				out[#out + 1] = separator:sub(1, budget)
			end

			break
		end

		out[#out + 1] = separator .. paint(piece, parts[i])
		budget = budget - #separator - #piece
	end

	return table.concat(out) .. (cut and "..." or "")
end

return Groups
