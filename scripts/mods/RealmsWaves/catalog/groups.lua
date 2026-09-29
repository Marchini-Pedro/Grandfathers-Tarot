-- Recipe parser for custom waves: "5 trappers, 5 mutants, 10 hounds".
-- Adapted from TwitchVersus catalog/groups.lua (alias table and parsing rules),
-- reduced to what RealmsWaves needs. Pure data/logic, no mod dependency.
local Groups = {}

Groups.MAX_PARTS = 8
Groups.MAX_BREED_COUNT = 24
Groups.MAX_TOTAL = 60

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
	chaos_ogryn_houndmaster = { "beastmaster", "houndmaster", "packmaster" },
	chaos_plague_ogryn = { "plague ogryn", "plague", "pogryn" },
	chaos_spawn = { "chaos spawn", "spawn" },
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

local function normalize(word)
	word = tostring(word or ""):lower()
	word = word:gsub("[_%-%.]", " ")
	word = word:gsub("[^%a%s]", "")
	word = word:gsub("%s+", " ")

	return (word:gsub("^%s*(.-)%s*$", "%1"))
end

local alias_map = {}
local sample_aliases = "trapper, hound, mutant, burster, rager, mauler, crusher, bulwark, reaper, sniper, poxwalker, scab, dreg"

for breed_name, list in pairs(ALIASES) do
	alias_map[normalize(breed_name)] = breed_name

	for i = 1, #list do
		alias_map[normalize(list[i])] = breed_name
	end
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

-- Returns parts = { {breed, count}, ... } on success, or nil and an error message.
Groups.parse = function (recipe)
	if type(recipe) ~= "string" or recipe:match("^%s*$") then
		return nil, "the recipe is empty. Write something like: 5 trappers, 5 mutants, 10 hounds"
	end

	local text = " " .. recipe .. " "

	text = text:gsub("%s+[aA][nN][dD]%s+", ",")
	text = text:gsub("[\n\r;/%+&]", ",")

	local parts, by_breed, total = {}, {}, 0

	for raw_field in text:gmatch("[^,]+") do
		local field = raw_field:gsub("^%s*(.-)%s*$", "%1")

		if field ~= "" then
			local count, name = split_count(field)

			name = name:gsub("^%s*(.-)%s*$", "%1")

			if name == "" or name:match("^%d+$") then
				return nil, string.format("%q is a number with no enemy after it. Write it as \"5 trappers\"", field)
			end

			local breed_name = lookup(name)

			if not breed_name then
				return nil, string.format("%q is not an enemy I know. Valid names include: %s", name, sample_aliases)
			end

			local part = by_breed[breed_name]

			if not part then
				if #parts >= Groups.MAX_PARTS then
					break
				end

				part = { breed = breed_name, count = 0 }
				by_breed[breed_name] = part
				parts[#parts + 1] = part
			end

			local room = math.max(0, Groups.MAX_TOTAL - total)
			local add = math.min(count, Groups.MAX_BREED_COUNT - part.count, room)

			if add > 0 then
				part.count = part.count + add
				total = total + add
			end
		end
	end

	local result = {}

	for i = 1, #parts do
		if parts[i].count > 0 then
			result[#result + 1] = parts[i]
		end
	end

	if #result == 0 then
		return nil, "nothing in the recipe looks like an enemy"
	end

	return result
end

return Groups
