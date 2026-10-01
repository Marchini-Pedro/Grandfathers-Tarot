-- Wave definitions and their settings (no mod dependency, so the localization
-- and data files can load it too).
--
-- Built-in ("standard") waves are data below; the user can override name and
-- composition of any wave, and fill 20 custom slots, from the in-game editor.
-- part = { breed = "name", count = n }  or  { one_of = { "a", "b" }, count = n }
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

-- Every wave key: the standard events, then the custom slots.
Events.keys = function ()
	local keys = {}

	for i = 1, #Events.STANDARD do
		keys[#keys + 1] = Events.STANDARD[i].key
	end

	for slot = 1, Events.CUSTOM_SLOTS do
		keys[#keys + 1] = "custom_" .. slot
	end

	return keys
end

Events.DEFAULT_CUSTOM_PCT = 10
Events.DEFAULT_CUSTOM_COOLDOWN = 60
Events.DEFAULT_SPREAD = 3 -- metres around the chosen spawn point
Events.DEFAULT_REPEAT_EVERY = 10 -- seconds between repeat ticks
Events.DEFAULT_REPEAT_FOR = 60 -- seconds the repeats keep coming

-- Settings per wave (all plain values so DMF can persist them):
--   wave_def_<key>  "name<TAB>recipe"   overrides name/composition ("" = default)
--   on_<key>        boolean             enabled (default: standard on, custom off)
--   pct_<key>       number              relative chance weight
--   cd_<key>        number              cooldown seconds
--   sp_<key>        number              spawn spread radius in metres (0 = all at the spawn point)
--   re_<key>        number              repeat every N seconds  (only used by groups with "@rep")
--   rf_<key>        number              keep repeating for N seconds
--   dmin_<key>      number              minimum spawn distance in metres for this wave (0 = use the options)
--   dmax_<key>      number              maximum spawn distance in metres for this wave (0 = use the options)
local DEF_SEPARATOR = "\t"

local function clean_name(name)
	name = tostring(name or ""):gsub("[\t\r\n]", " ")
	name = name:gsub("^%s*(.-)%s*$", "%1")

	return name
end

Events.clean_name = clean_name

-- Resolves one wave from the settings. `get_setting(id)` reads a mod setting.
-- Returns { key, name, parts (nil for an empty custom slot), monster, is_custom, enabled, pct, cooldown, modified, std }.
Events.get = function (key, get_setting, Groups)
	local std = by_key[key]
	local slot = tonumber(tostring(key):match("^custom_(%d+)$"))

	if not std and not (slot and slot >= 1 and slot <= Events.CUSTOM_SLOTS) then
		return nil
	end

	local wave = { key = key, std = std, is_custom = std == nil, monster = std and std.monster or false }

	if std then
		wave.name, wave.parts = std.name, std.parts
	else
		wave.name = "Custom " .. slot
	end

	local override = get_setting("wave_def_" .. key)

	if type(override) == "string" and override ~= "" then
		local name, recipe = override:match("^(.-)" .. DEF_SEPARATOR .. "(.*)$")

		if name and name ~= "" then
			wave.name = name
		end

		if recipe and recipe ~= "" then
			local parts = Groups.parse(recipe)

			if parts then
				wave.parts = parts
			end
		elseif wave.is_custom then
			wave.parts = nil
		end

		wave.modified = true
	elseif wave.is_custom then
		local legacy = get_setting("custom_" .. slot .. "_recipe") -- 1.0.0 setting

		if type(legacy) == "string" and legacy ~= "" then
			wave.parts = Groups.parse(legacy)
		end
	end

	local enabled = get_setting("on_" .. key)

	if enabled == nil then
		enabled = std ~= nil
	end

	wave.enabled = enabled == true
	wave.pct = tonumber(get_setting("pct_" .. key)) or (std and std.default_pct) or Events.DEFAULT_CUSTOM_PCT
	wave.cooldown = tonumber(get_setting("cd_" .. key)) or (std and std.cooldown) or Events.DEFAULT_CUSTOM_COOLDOWN
	wave.spread = tonumber(get_setting("sp_" .. key)) or Events.DEFAULT_SPREAD
	wave.rep_every = tonumber(get_setting("re_" .. key)) or Events.DEFAULT_REPEAT_EVERY
	wave.rep_for = tonumber(get_setting("rf_" .. key)) or Events.DEFAULT_REPEAT_FOR
	wave.dmin = math.max(0, tonumber(get_setting("dmin_" .. key)) or 0)
	wave.dmax = math.max(0, tonumber(get_setting("dmax_" .. key)) or 0)

	return wave
end

-- "Mutants Everywhere!" -> "mutants_everywhere" (lower case, every run of other characters becomes one "_").
Events.normalize_name = function (text)
	text = tostring(text or ""):lower():gsub("[^%w]+", "_")

	return (text:gsub("^_+", ""):gsub("_+$", ""))
end

-- Finds a wave by its key ("custom_2", "wave_small") or by its NAME as shown in the editor,
-- written any way you like: "Mutants Everywhere", "mutants_everywhere", "mutants-everywhere".
-- Order: exact key, exact name, then a unique name that starts with / contains the text.
-- Returns the wave, or nil and a message (unknown, or several waves match).
Events.find = function (query, get_setting, Groups)
	local q = Events.normalize_name(query)

	if q == "" then
		return nil, "no wave name given"
	end

	local waves = {}

	for _, key in ipairs(Events.keys()) do
		waves[#waves + 1] = Events.get(key, get_setting, Groups)
	end

	for i = 1, #waves do
		if Events.normalize_name(waves[i].key) == q then
			return waves[i]
		end
	end

	local function describe(list)
		local names = {}

		for i = 1, #list do
			names[i] = string.format("%s (%s)", list[i].name, list[i].key)
		end

		return table.concat(names, ", ")
	end

	local function pick(matches)
		if #matches == 1 then
			return matches[1]
		elseif #matches > 1 then
			return nil, string.format("several waves match %q: %s. Use the full name or the key.", tostring(query), describe(matches))
		end
	end

	local exact = {}

	for i = 1, #waves do
		if Events.normalize_name(waves[i].name) == q then
			exact[#exact + 1] = waves[i]
		end
	end

	if #exact > 0 then
		return pick(exact)
	end

	-- fuzzy steps only consider waves that have enemies (an empty "Custom 7" slot is never a good guess)
	for _, mode in ipairs({ "prefix", "contains" }) do
		local matches = {}

		for i = 1, #waves do
			local wave = waves[i]

			if wave.parts and #wave.parts > 0 then
				local name = Events.normalize_name(wave.name)
				local hit = mode == "prefix" and name:sub(1, #q) == q or (mode == "contains" and name:find(q, 1, true) ~= nil)

				if hit then
					matches[#matches + 1] = wave
				end
			end
		end

		if #matches > 0 then
			return pick(matches)
		end
	end

	return nil, string.format("no wave named %q (use its name from the wave editor, or a key like custom_1)", tostring(query))
end

-- Writes a wave's name and composition. `parts` may be nil/empty for a custom slot.
Events.set_def = function (set_setting, key, name, parts, Groups)
	set_setting("wave_def_" .. key, clean_name(name) .. DEF_SEPARATOR .. Groups.to_recipe(parts))
end

-- Back to defaults: standard waves return to the built-in definition; custom slots are emptied.
Events.reset = function (set_setting, key)
	local std = by_key[key]

	set_setting("wave_def_" .. key, "")
	set_setting("on_" .. key, std ~= nil)
	set_setting("pct_" .. key, std and std.default_pct or Events.DEFAULT_CUSTOM_PCT)
	set_setting("cd_" .. key, std and std.cooldown or Events.DEFAULT_CUSTOM_COOLDOWN)
	set_setting("sp_" .. key, Events.DEFAULT_SPREAD)
	set_setting("re_" .. key, Events.DEFAULT_REPEAT_EVERY)
	set_setting("rf_" .. key, Events.DEFAULT_REPEAT_FOR)
	set_setting("dmin_" .. key, 0)
	set_setting("dmax_" .. key, 0)
end

-- The definition handed to the spawner (Execute.start_wave) for a resolved wave.
Events.spawn_def = function (wave)
	return {
		key = wave.key,
		name = wave.name,
		parts = wave.parts,
		monster = wave.monster,
		cooldown = wave.cooldown,
		spread = wave.spread,
		rep_every = wave.rep_every,
		rep_for = wave.rep_for,
		dmin = wave.dmin,
		dmax = wave.dmax,
	}
end

-- Builds the list of waves that can be drawn right now (enabled, has enemies, chance > 0),
-- with each chance normalised over that set so it always totals 100.
-- Returns list of { key, name, def, raw, pct, cooldown } and the raw total.
Events.build_pool = function (get_setting, Groups)
	local pool = {}
	local total = 0
	local keys = Events.keys()

	for i = 1, #keys do
		local wave = Events.get(keys[i], get_setting, Groups)

		if wave and wave.enabled and wave.parts and #wave.parts > 0 and wave.pct > 0 then
			local def = Events.spawn_def(wave)

			pool[#pool + 1] = { key = wave.key, name = wave.name, def = def, raw = wave.pct, cooldown = wave.cooldown }
			total = total + wave.pct
		end
	end

	for i = 1, #pool do
		pool[i].pct = total > 0 and pool[i].raw / total * 100 or 0
	end

	return pool, total
end

return Events
