-- Wave definitions and their settings (no mod dependency, so the localization
-- and data files can load it too).
--
-- Built-in ("standard") waves are data below; the user can override name and
-- composition of any wave, and fill 20 custom slots, from the in-game editor.
-- part = { breed = "name", count = n }  or  { one_of = { "a", "b" }, count = n }
-- monster = true uses the monster distance range.
-- The standard waves are tarot cards (names, suits and whispers: catalog/cards.lua); their keys never change, so saved
-- settings keep working. default_pct is the card's chance on the 1-10 scale of the editor's chance pips.
local Events = {}

Events.CUSTOM_SLOTS = 20

Events.STANDARD = {
	{
		key = "wave_small", name = "The Fool", default_pct = 5, cooldown = 120, suit = "swarm",
		parts = {
			{ breed = "chaos_poxwalker", count = 8 },
			{ breed = "renegade_melee", count = 6 },
			{ breed = "cultist_melee", count = 4 },
			{ breed = "renegade_rifleman", count = 2 },
		},
	},
	{
		key = "wave_medium", name = "The Pilgrims", default_pct = 5, cooldown = 150, suit = "swarm",
		parts = {
			{ breed = "chaos_poxwalker", count = 12 },
			{ breed = "renegade_melee", count = 10 },
			{ breed = "cultist_melee", count = 8 },
			{ breed = "renegade_rifleman", count = 5 },
			{ breed = "chaos_mutated_poxwalker", count = 2 },
		},
	},
	{
		key = "wave_large", name = "The Procession", default_pct = 4, cooldown = 150, suit = "swarm",
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
		key = "wave_huge", name = "The Throng", default_pct = 3, cooldown = 240, suit = "swarm", whisper = "There are always more.",
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
		key = "boss_ambush", name = "The Devil", default_pct = 4, cooldown = 240, monster = true, suit = "fateful", whisper = "Something big is listening.",
		parts = {
			{ one_of = { "chaos_plague_ogryn", "chaos_beast_of_nurgle", "chaos_spawn" }, count = 1 },
		},
	},
	{
		key = "bomber_frenzy", name = "The Tower", default_pct = 5, cooldown = 150, suit = "blight", whisper = "Pop, pop, pop.",
		parts = {
			{ breed = "chaos_poxwalker_bomber", count = 12 },
		},
	},
	{
		key = "hound_frenzy", name = "The Hunt", default_pct = 5, cooldown = 150, suit = "rage", whisper = "Hear them running.",
		parts = {
			{ breed = "chaos_hound", count = 10 },
		},
	},
	{
		key = "grenade_legion", name = "Rain of Rot", default_pct = 4, cooldown = 180, suit = "blight", look = "vial", whisper = "The sky is sick.",
		parts = {
			{ breed = "cultist_grenadier", count = 6 },
			{ breed = "renegade_grenadier", count = 6 },
		},
	},
	{
		key = "sniper_elite", name = "The Watching Moon", default_pct = 3, cooldown = 180, suit = "murmur", whisper = "Someone is counting you.",
		parts = {
			{ breed = "renegade_sniper", count = 5 },
		},
	},
	{
		key = "elite_squad", name = "The Chariot", default_pct = 4, cooldown = 150, suit = "rage",
		parts = {
			{ breed = "renegade_executor", count = 3 },
			{ breed = "renegade_gunner", count = 3 },
			{ breed = "cultist_shocktrooper", count = 3 },
			{ breed = "cultist_berzerker", count = 3 },
		},
	},
	{
		key = "special_pack", name = "The Magician", default_pct = 3, cooldown = 150, suit = "blight",
		parts = {
			{ breed = "renegade_netgunner", count = 3 },
			{ breed = "renegade_flamer", count = 2 },
			{ breed = "cultist_mutant", count = 2 },
			{ breed = "cultist_flamer", count = 2 },
		},
	},
	{
		key = "ogryn_brutes", name = "Strength", default_pct = 2, cooldown = 300, monster = true, suit = "rage",
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
Events.MAX_PCT = 10 -- the most a card's chance can be (older settings above it count as 10)
Events.DEFAULT_CUSTOM_COOLDOWN = 120

-- The cooldown of a card of your own that has none set: the option "Default card cooldown" (default 120 s), in 30 s
-- steps from 30 s up to the longest cooldown option (10 minutes by default).
Events.default_cooldown = function (get_setting)
	local value = tonumber(get_setting("tarot_default_cooldown")) or Events.DEFAULT_CUSTOM_COOLDOWN
	local longest = math.max(2, tonumber(get_setting("tarot_longest")) or 10) * 60

	return math.max(30, math.min(longest, math.floor(value / 30 + 0.5) * 30))
end
Events.DEFAULT_SPREAD = 3 -- metres around the chosen spawn point
Events.DEFAULT_REPEAT_EVERY = 10 -- seconds between repeat ticks
Events.DEFAULT_REPEAT_FOR = 60 -- seconds the repeats keep coming

-- the suits of the Tarot (visuals: catalog/cards.lua) and the cooldown looks
Events.SUITS = {
	plague = true, murmur = true, rage = true, blight = true, swarm = true, fateful = true,
	volley = true, snare = true, brute = true, fester = true, dusk = true, warp = true,
}
Events.LOOKS = { rot = true, whisper = true, vial = true }

-- Settings per wave (all plain values so DMF can persist them):
--   wave_def_<key>  "name<TAB>recipe"   overrides name/composition ("" = default)
--   on_<key>        boolean             enabled (default: standard on, custom off)
--   pct_<key>       number              chance of the card, 0 to 10 (the ten pips; shown as a share of the cards that can be drawn)
--   cd_<key>        number              cooldown seconds
--   sp_<key>        number              spawn spread radius in metres (0 = all at the spawn point)
--   re_<key>        number              repeat every N seconds  (only used by groups with "@rep")
--   rf_<key>        number              keep repeating for N seconds
--   rk_<key>        boolean             a random group ("a|b") rolls once and keeps its enemy on every repeat (default on; false = a new
--                                       roll for every unit)
--   dmin_<key>      number              minimum spawn distance in metres for this wave (0 = use the options)
--   dmax_<key>      number              maximum spawn distance in metres for this wave (0 = use the options)
--   del_<key>       boolean             a STANDARD wave the player deleted: hidden in the editor, never drawn or timed.
--                                       "Restore defaults" (Events.reset on every key) brings it back.
--   su_<key>        string              suit of the card (see Events.SUITS; "" = the default: the card's own, "warp" for a
--                                       custom card that holds a Daemonhost, else plague)
--   th_<key>        number              threat override 1-5 (0 = automatic, see Cards.threat_auto)
--   wh_<key>        string              whisper text ("" = the line of the suit)
--   cl_<key>        string              cooldown look (rot, whisper, vial; "" = automatic: whisper for Murmur cards, else rot)
--   ev_<key>        number              FIXED TIMER: seconds between automatic spawns of this wave (0 = off). A wave with a
--                                       timer ignores its chance weight and cooldown and never takes part in the draw:
--                                       it runs on its own clock, independent of the other waves.
local DEF_SEPARATOR = "\t"

-- the Daemonhost's own card is purple (suit "warp"): a card that holds one gets it unless the player chose a suit
local function has_daemonhost(parts)
	for i = 1, #(parts or {}) do
		local part = parts[i]

		if part.breed == "chaos_daemonhost" then
			return true
		end

		for j = 1, #(part.one_of or {}) do
			if part.one_of[j] == "chaos_daemonhost" then
				return true
			end
		end
	end

	return false
end

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

	-- only standard waves can be deleted (a custom wave is deleted by emptying its slot, Events.reset)
	wave.deleted = std ~= nil and get_setting("del_" .. key) == true

	if wave.deleted then
		wave.enabled = false
	end
	wave.pct = math.max(0, math.min(Events.MAX_PCT, tonumber(get_setting("pct_" .. key)) or (std and std.default_pct) or Events.DEFAULT_CUSTOM_PCT))
	wave.cooldown = tonumber(get_setting("cd_" .. key)) or (std and std.cooldown) or Events.default_cooldown(get_setting)
	wave.spread = tonumber(get_setting("sp_" .. key)) or Events.DEFAULT_SPREAD
	wave.rep_every = tonumber(get_setting("re_" .. key)) or Events.DEFAULT_REPEAT_EVERY
	wave.rep_for = tonumber(get_setting("rf_" .. key)) or Events.DEFAULT_REPEAT_FOR
	wave.keep_pick = get_setting("rk_" .. key) ~= false
	wave.dmin = math.max(0, tonumber(get_setting("dmin_" .. key)) or 0)
	wave.dmax = math.max(0, tonumber(get_setting("dmax_" .. key)) or 0)

	-- tarot card data: suit (unknown -> plague), threat override, whisper, cooldown look
	local suit = get_setting("su_" .. key)

	if type(suit) ~= "string" or suit == "" then
		suit = std and std.suit or has_daemonhost(wave.parts) and "warp" or "plague"
	end

	wave.suit = Events.SUITS[suit] and suit or "plague"
	wave.threat_override = math.max(0, math.min(5, math.floor(tonumber(get_setting("th_" .. key)) or 0)))

	local whisper = get_setting("wh_" .. key)

	wave.whisper = type(whisper) == "string" and whisper ~= "" and whisper or (std and std.whisper or "")

	local look = get_setting("cl_" .. key)

	if type(look) ~= "string" or look == "" then
		look = std and std.look or ""
	end

	wave.look = Events.LOOKS[look] and look or ""
	-- 0 = off; anything else is at least 5 seconds (a 1 second timer would only flood the map)
	wave.timer = math.max(0, tonumber(get_setting("ev_" .. key)) or 0)

	if wave.timer > 0 and wave.timer < 5 then
		wave.timer = 5
	end

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
		local candidate = Events.get(key, get_setting, Groups)

		if not candidate.deleted then
			waves[#waves + 1] = candidate
		end
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
	set_setting("cd_" .. key, std and std.cooldown or nil) -- a custom card goes back to the default cooldown option
	set_setting("sp_" .. key, Events.DEFAULT_SPREAD)
	set_setting("re_" .. key, Events.DEFAULT_REPEAT_EVERY)
	set_setting("rf_" .. key, Events.DEFAULT_REPEAT_FOR)
	set_setting("rk_" .. key, true)
	set_setting("dmin_" .. key, 0)
	set_setting("dmax_" .. key, 0)
	set_setting("su_" .. key, "")
	set_setting("th_" .. key, 0)
	set_setting("wh_" .. key, "")
	set_setting("cl_" .. key, "")
	set_setting("ev_" .. key, 0)
	set_setting("del_" .. key, false)
end

-- Back to the defaults of a card's face only (Reset face on the card face screen): the suit the card would have without a choice,
-- the threat worked out from the enemies, the suit's own whisper, the look the suit gives, the default cooldown. The enemies and
-- everything else stay.
Events.reset_face = function (set_setting, key)
	local std = by_key[key]

	set_setting("su_" .. key, "")
	set_setting("th_" .. key, 0)
	set_setting("wh_" .. key, "")
	set_setting("cl_" .. key, "")
	set_setting("cd_" .. key, std and std.cooldown or nil)
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
		keep_pick = wave.keep_pick,
		dmin = wave.dmin,
		dmax = wave.dmax,
		timer = wave.timer,
		suit = wave.suit,
		threat_override = wave.threat_override,
		whisper = wave.whisper,
		look = wave.look,
	}
end

-- Waves that run on a fixed timer: enabled, with enemies and a timer above 0 seconds.
-- Returns a list of { key, name, def, every } (seconds). Chance weight and cooldown play no part.
Events.timed_waves = function (get_setting, Groups)
	local list = {}
	local keys = Events.keys()

	for i = 1, #keys do
		local wave = Events.get(keys[i], get_setting, Groups)

		if wave and wave.enabled and wave.parts and #wave.parts > 0 and wave.timer > 0 then
			list[#list + 1] = { key = wave.key, name = wave.name, def = Events.spawn_def(wave), every = wave.timer }
		end
	end

	return list
end

-- Builds the list of waves that can be drawn right now (enabled, has enemies, chance > 0),
-- with each chance normalised over that set so it always totals 100.
-- `extra` (optional): waves of other players (see Presets.pool_waves) that join the draw. A wave whose
-- composition is identical to one already in the pool is not added twice (the host's own wins), and a
-- name that is already taken gets " (2)", " (3)"... so a ballot never shows two identical lines.
-- Returns list of { key, name, def, raw, pct, cooldown } and the raw total.
Events.build_pool = function (get_setting, Groups, extra)
	local pool = {}
	local total = 0
	local keys = Events.keys()

	for i = 1, #keys do
		local wave = Events.get(keys[i], get_setting, Groups)

		-- a wave with a fixed timer runs on its own clock (Events.timed_waves), it is never drawn
		if wave and wave.enabled and wave.parts and #wave.parts > 0 and wave.pct > 0 and not (wave.timer > 0) then
			local def = Events.spawn_def(wave)

			pool[#pool + 1] = { key = wave.key, name = wave.name, def = def, raw = wave.pct, cooldown = wave.cooldown }
			total = total + wave.pct
		end
	end

	if extra then
		local recipes, names = {}, {}

		for i = 1, #pool do
			recipes[Groups.to_recipe(pool[i].def.parts)] = true
			names[pool[i].name] = 1
		end

		for i = 1, #extra do
			local wave = extra[i]

			if wave.enabled and wave.parts and #wave.parts > 0 and wave.pct > 0 then
				local recipe = Groups.to_recipe(wave.parts)

				if not recipes[recipe] then
					recipes[recipe] = true

					local name = wave.name
					local used = names[name]

					names[name] = (used or 0) + 1

					if used then
						name = string.format("%s (%d)", name, used + 1)
					end

					local raw = math.min(Events.MAX_PCT, wave.pct)

					pool[#pool + 1] = { key = wave.key, name = name, def = Events.spawn_def(wave), raw = raw, cooldown = wave.cooldown, owner = wave.owner }
					total = total + raw
				end
			end
		end
	end

	for i = 1, #pool do
		pool[i].pct = total > 0 and pool[i].raw / total * 100 or 0
	end

	return pool, total
end
return Events
