-- Standard wave events (pure data, no mod dependency so the localization and
-- data files can load it too) plus the pool builder that turns settings into
-- normalised percentages.
--
-- part  = { breed = "name", count = n }  or  { one_of = { "a", "b" }, count = n }
-- monster = true uses the monster distance range.
-- default_pct values sum to 100 across the standard events.
local Events = {}

Events.CUSTOM_SLOTS = 20

Events.STANDARD = {
	{
		key = "wave_small", name = "Small Wave", default_pct = 18, cooldown = 60,
		parts = {
			{ breed = "chaos_poxwalker", count = 8 },
			{ breed = "renegade_melee", count = 6 },
			{ breed = "cultist_melee", count = 4 },
			{ breed = "renegade_rifleman", count = 2 },
		},
	},
	{
		key = "wave_medium", name = "Medium Wave", default_pct = 14, cooldown = 90,
		parts = {
			{ breed = "chaos_poxwalker", count = 12 },
			{ breed = "renegade_melee", count = 10 },
			{ breed = "cultist_melee", count = 8 },
			{ breed = "renegade_rifleman", count = 5 },
			{ breed = "chaos_mutated_poxwalker", count = 2 },
		},
	},
	{
		key = "wave_large", name = "Large Wave", default_pct = 8, cooldown = 150,
		parts = {
			{ breed = "chaos_poxwalker", count = 16 },
			{ breed = "renegade_melee", count = 14 },
			{ breed = "cultist_melee", count = 12 },
			{ breed = "renegade_rifleman", count = 8 },
			{ breed = "renegade_assault", count = 6 },
			{ breed = "chaos_mutated_poxwalker", count = 4 },
		},
	},
	{
		key = "wave_huge", name = "Huge Wave", default_pct = 4, cooldown = 240,
		parts = {
			{ breed = "chaos_poxwalker", count = 20 },
			{ breed = "renegade_melee", count = 18 },
			{ breed = "cultist_melee", count = 16 },
			{ breed = "renegade_rifleman", count = 10 },
			{ breed = "renegade_assault", count = 8 },
			{ breed = "chaos_mutated_poxwalker", count = 6 },
			{ breed = "renegade_shocktrooper", count = 4 },
		},
	},
	{
		key = "boss_ambush", name = "Boss Ambush", default_pct = 8, cooldown = 240, monster = true,
		parts = {
			{ one_of = { "chaos_plague_ogryn", "chaos_beast_of_nurgle", "chaos_spawn" }, count = 1 },
		},
	},
	{
		key = "bomber_frenzy", name = "Bomber Frenzy", default_pct = 9, cooldown = 120,
		parts = {
			{ breed = "chaos_poxwalker_bomber", count = 12 },
		},
	},
	{
		key = "hound_frenzy", name = "Hound Frenzy", default_pct = 9, cooldown = 150,
		parts = {
			{ breed = "chaos_hound", count = 10 },
		},
	},
	{
		key = "grenade_legion", name = "Grenade Legion", default_pct = 8, cooldown = 120,
		parts = {
			{ breed = "cultist_grenadier", count = 6 },
			{ breed = "renegade_grenadier", count = 6 },
		},
	},
	{
		key = "sniper_elite", name = "Sniper Elite", default_pct = 6, cooldown = 180,
		parts = {
			{ breed = "renegade_sniper", count = 5 },
		},
	},
	{
		key = "elite_squad", name = "Elite Squad", default_pct = 8, cooldown = 150,
		parts = {
			{ breed = "renegade_executor", count = 3 },
			{ breed = "renegade_gunner", count = 3 },
			{ breed = "cultist_shocktrooper", count = 3 },
			{ breed = "cultist_berzerker", count = 3 },
		},
	},
	{
		key = "special_pack", name = "Special Pack", default_pct = 6, cooldown = 150,
		parts = {
			{ breed = "renegade_netgunner", count = 3 },
			{ breed = "renegade_flamer", count = 2 },
			{ breed = "cultist_mutant", count = 2 },
			{ breed = "cultist_flamer", count = 2 },
		},
	},
	{
		key = "ogryn_brutes", name = "Ogryn Brutes", default_pct = 2, cooldown = 300, monster = true,
		parts = {
			{ breed = "chaos_ogryn_executor", count = 3 },
			{ breed = "chaos_ogryn_bulwark", count = 2 },
			{ breed = "chaos_ogryn_gunner", count = 2 },
		},
	},
}

local by_key = {}

for i = 1, #Events.STANDARD do
	by_key[Events.STANDARD[i].key] = Events.STANDARD[i]
end

Events.get_standard = function (key)
	return by_key[key]
end

local function clip(text, limit)
	if #text <= limit then
		return text
	end

	return text:sub(1, limit - 1) .. "..."
end

-- Builds the list of events that are currently enabled, with their percentage
-- normalised over the enabled set so it always totals 100.
-- `get_setting(id)` reads a mod setting; `Groups` is catalog/groups.
-- Returns list of { key, name, def, raw, pct, cooldown } and the raw total.
Events.build_pool = function (get_setting, Groups)
	local pool = {}
	local total = 0

	for i = 1, #Events.STANDARD do
		local def = Events.STANDARD[i]
		local raw = tonumber(get_setting("pct_" .. def.key))

		if raw == nil then
			raw = def.default_pct
		end

		if raw > 0 then
			pool[#pool + 1] = { key = def.key, name = def.name, def = def, raw = raw, cooldown = def.cooldown }
			total = total + raw
		end
	end

	for slot = 1, Events.CUSTOM_SLOTS do
		local raw = tonumber(get_setting("custom_" .. slot .. "_pct")) or 0
		local recipe = get_setting("custom_" .. slot .. "_recipe")

		if raw > 0 and type(recipe) == "string" and recipe ~= "" then
			local parts = Groups.parse(recipe)

			if parts then
				local def = { key = "custom_" .. slot, name = "Custom " .. slot .. ": " .. clip(recipe, 28), parts = parts, cooldown = 60 }

				pool[#pool + 1] = { key = def.key, name = def.name, def = def, raw = raw, cooldown = def.cooldown }
				total = total + raw
			end
		end
	end

	for i = 1, #pool do
		pool[i].pct = total > 0 and pool[i].raw / total * 100 or 0
	end

	return pool, total
end

return Events
