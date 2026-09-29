-- Recipe parser and breed catalog for waves.
--   recipe text: "5 trappers, 5 mutants, 10 hounds"
--   random pick: "1 plague ogryn|beast of nurgle|chaos spawn"  (one of the alternatives per unit)
-- Alias table adapted from TwitchVersus catalog/groups.lua. Pure data/logic, no mod dependency.
--
-- parts = { { breed = "name", count = n }  or  { one_of = { "a", "b" }, count = n }, ... }
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
	return part.one_of and table.concat(part.one_of, "|") or part.breed
end

-- Returns parts on success, or nil and an error message.
Groups.parse = function (recipe)
	if type(recipe) ~= "string" or recipe:match("^%s*$") then
		return nil, "the recipe is empty. Write something like: 5 trappers, 5 mutants, 10 hounds"
	end

	local text = " " .. recipe .. " "

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

		fields[#fields + 1] = part.count .. " " .. table.concat(names, "|")
	end

	return table.concat(fields, ", ")
end

-- Short human text for a part: "8 Poxwalker" / "1 random of Plague Ogryn / Chaos Spawn".
Groups.describe_part = function (part)
	if part.one_of then
		local names = {}

		for i = 1, #part.one_of do
			names[i] = Groups.display_name(part.one_of[i])
		end

		return string.format("%d random of %s", part.count, table.concat(names, " / "))
	end

	return string.format("%d %s", part.count, Groups.display_name(part.breed))
end

Groups.total_count = function (parts)
	local total = 0

	for i = 1, #(parts or {}) do
		total = total + parts[i].count
	end

	return total
end

Groups.summary = function (parts, max_chars)
	local pieces = {}

	for i = 1, #(parts or {}) do
		pieces[i] = Groups.describe_part(parts[i])
	end

	local text = table.concat(pieces, ", ")

	if max_chars and #text > max_chars then
		text = text:sub(1, max_chars - 3) .. "..."
	end

	return text
end

return Groups
