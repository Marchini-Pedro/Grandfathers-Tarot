-- The Grandfather's Tarot: card data on top of a wave (catalog/events.lua) -- suit, threat, enemy dots, whisper,
-- cooldown look, rarity, the Plague Tarot palette, rot strength, and the one-time rename of the user's old waves.
--
-- Pure Lua, no engine calls: everything that needs the game (colours of enemies, localization) is passed in,
-- so the whole thing is tested offline. Reference design: the "Grandfather's Tarot" artifact (see docs/04).
local Cards = {}

-- ----------------------------------------------------------------------------------------------- palette
local function hex(text)
	return { tonumber(text:sub(2, 3), 16), tonumber(text:sub(4, 5), 16), tonumber(text:sub(6, 7), 16) }
end

Cards.hex = hex

-- base colours (ground, panel, bone text, muted text, bile, rust, pus yellow, whisper)
Cards.BASE = {
	ground = hex("#0a0c07"),
	panel = hex("#12160c"),
	line = hex("#3a4421"),
	text = hex("#e6dfc3"),
	muted = hex("#98936f"),
	bile = hex("#b7c23a"),
	rust = hex("#c27a2c"),
	pus = hex("#e3cf4a"),
	whisper = hex("#8fa07a"),
	murmur_line = hex("#55603a"),
}

-- the six suits: card, selected card, frame, text, accent (the reference page's exact values)
Cards.SUIT_ORDER = { "plague", "murmur", "rage", "blight", "swarm", "fateful" }

Cards.SUITS = {
	plague = { name = "Plague", card = hex("#1e2413"), hi = hex("#2a3219"), frame = hex("#3a4421"), text = hex("#e6dfc3"), accent = hex("#b7c23a"), whisper = "Something is growing.", icon = "eye" },
	murmur = { name = "Murmur", card = hex("#0b0c0a"), hi = hex("#161a11"), frame = hex("#55603a"), text = hex("#cfcab0"), accent = hex("#9db07f"), whisper = "Do you hear it?", icon = "moon" },
	rage = { name = "Rage", card = hex("#241509"), hi = hex("#34200e"), frame = hex("#6b3a17"), text = hex("#ecd9bf"), accent = hex("#c27a2c"), whisper = "Faster. Faster.", icon = "flame" },
	blight = { name = "Blight", card = hex("#25240c"), hi = hex("#333212"), frame = hex("#5c5a1e"), text = hex("#ebe6bf"), accent = hex("#e3cf4a"), whisper = "The air turns.", icon = "drop" },
	swarm = { name = "Swarm", card = hex("#1b1d17"), hi = hex("#262a1f"), frame = hex("#474c3a"), text = hex("#d9d8c6"), accent = hex("#9aa37a"), whisper = "Too many to count.", icon = "cluster" },
	fateful = { name = "Fateful", card = hex("#17140f"), hi = hex("#231e14"), frame = hex("#8a7a4a"), text = hex("#efe6c9"), accent = hex("#e6dfc3"), whisper = "The last page.", icon = "star" },
}

-- one colour per threat level 1..5 (unfilled diamonds are an outline in the muted colour)
Cards.THREAT_COLORS = { hex("#a7c27c"), hex("#74b22c"), hex("#e3cf4a"), hex("#d98a2e"), hex("#cf4a30") }

-- a card with this weight or less is "rare": pus-yellow outline
Cards.RARE_WEIGHT = 2

Cards.normalize_suit = function (suit)
	return Cards.SUITS[suit] and suit or "plague"
end

Cards.suit = function (suit)
	return Cards.SUITS[Cards.normalize_suit(suit)]
end

Cards.is_rare = function (weight)
	weight = tonumber(weight) or 0

	return weight > 0 and weight <= Cards.RARE_WEIGHT
end

-- ---------------------------------------------------------------------------------------------- cooldown looks
Cards.LOOKS = { "rot", "whisper", "vial" }

local VALID_LOOK = { rot = true, whisper = true, vial = true }

Cards.normalize_look = function (look)
	return VALID_LOOK[look] and look or nil
end

-- The look a card uses: its own choice, else whisper for every Murmur card, else rot.
Cards.look = function (card)
	return Cards.normalize_look(card.look) or (Cards.normalize_suit(card.suit) == "murmur" and "whisper" or "rot")
end

Cards.COOLDOWN_STEP = 30 -- seconds, also the shortest cooldown
Cards.DEFAULT_COOLDOWN = 120

-- Rot strength k = clamp(log(cooldown / 30) / log(longest / 30), 0, 1) (longest in seconds), the longer the cooldown
-- the harder a consumed card rots (reference page `corr()`).
Cards.rot_strength = function (cooldown, longest)
	longest = math.max(Cards.COOLDOWN_STEP * 2, tonumber(longest) or 600)
	cooldown = math.max(Cards.COOLDOWN_STEP, tonumber(cooldown) or Cards.DEFAULT_COOLDOWN)

	local k = math.log(cooldown / Cards.COOLDOWN_STEP) / math.log(longest / Cards.COOLDOWN_STEP)

	return math.max(0, math.min(1, k))
end

-- rot duration = lerp(shortest cooldown's rot, longest cooldown's rot, k)
Cards.rot_duration = function (cooldown, longest, rot_short, rot_long)
	local k = Cards.rot_strength(cooldown, longest)

	return rot_short + (rot_long - rot_short) * k
end

-- Blotch size, flies and drip length of the rot effect for a strength k (reference page).
Cards.rot_sizes = function (k)
	return { blotch = 14 + 52 * k, flies = 3 + math.floor(6 * k + 0.5), drip = 14 + 40 * k }
end

-- "Rot and renewal": the accent colour while the card is in cooldown, p = elapsed / cooldown:
-- grey rgb(74,74,64) -> brown rgb(90,70,49) at 0.35 -> ochre rgb(194,122,44) at 0.7 -> the suit accent.
local ROT_STOPS = { { 0, { 74, 74, 64 } }, { 0.35, { 90, 70, 49 } }, { 0.7, { 194, 122, 44 } } }

Cards.rot_color = function (p, accent)
	p = math.max(0, math.min(1, p or 0))

	local stops = { ROT_STOPS[1], ROT_STOPS[2], ROT_STOPS[3], { 1, accent } }

	for i = 2, #stops do
		if p <= stops[i][1] then
			local a, b = stops[i - 1], stops[i]
			local t = (p - a[1]) / (b[1] - a[1])

			return {
				math.floor(a[2][1] + (b[2][1] - a[2][1]) * t + 0.5),
				math.floor(a[2][2] + (b[2][2] - a[2][2]) * t + 0.5),
				math.floor(a[2][3] + (b[2][3] - a[2][3]) * t + 0.5),
			}
		end
	end

	return { accent[1], accent[2], accent[3] }
end

-- Text opacity of a card in "rot and renewal": 0.5 -> 1. "The murmur returns": card opacity 0.6 -> 1.
Cards.rot_text_alpha = function (p)
	return 0.5 + 0.5 * math.max(0, math.min(1, p or 0))
end

Cards.murmur_card_alpha = function (p)
	return 0.6 + 0.4 * math.max(0, math.min(1, p or 0))
end

-- How much of a whisper (n characters) has appeared at progress p ("letter by letter").
Cards.whisper_letters = function (text, p)
	local n = #text

	return math.max(0, math.min(n, math.floor(math.max(0, math.min(1, p or 0)) * n * 1.15 + 1e-9)))
end

-- ------------------------------------------------------------------------------------------- threat, dots, whisper
local function total_enemies(parts)
	local total = 0

	for i = 1, #(parts or {}) do
		total = total + (parts[i].count or 0)
	end

	return total
end

-- Which kinds of enemy a recipe holds: { elite, special, boss } booleans. Uses Groups.kind (the game's breed tags).
Cards.kinds = function (parts, Groups)
	local found = { elite = false, special = false, boss = false }

	for i = 1, #(parts or {}) do
		local part = parts[i]
		local breeds = part.one_of or { part.breed }

		for j = 1, #breeds do
			local kind = Groups.kind(breeds[j])

			if kind == "elite" then
				found.elite = true
			elseif kind == "special" then
				found.special = true
			elseif kind == "boss" then
				found.boss = true
			end
		end
	end

	return found
end

-- Threat 1..5 by the numbers: base 1 up to 8 enemies, 2 up to 24, 3 up to 60, 4 up to 120, 5 above;
-- +1 with elites, +1 with specials, +2 with a boss; at most 5. Returns the value and the pieces
-- ({ count, base, elite, special, boss }) so the editor can show "Threat N by the numbers".
Cards.threat_auto = function (parts, Groups)
	local count = total_enemies(parts)
	local base = count <= 8 and 1 or count <= 24 and 2 or count <= 60 and 3 or count <= 120 and 4 or 5
	local kinds = Cards.kinds(parts, Groups)
	local value = base + (kinds.elite and 1 or 0) + (kinds.special and 1 or 0) + (kinds.boss and 2 or 0)

	return math.min(5, value), { count = count, base = base, elite = kinds.elite, special = kinds.special, boss = kinds.boss }
end

-- Threat shown on a card: the manual override (1..5) when set, otherwise the automatic one.
Cards.threat = function (parts, override, Groups)
	override = tonumber(override) or 0

	if override >= 1 and override <= 5 then
		return math.floor(override)
	end

	return (Cards.threat_auto(parts, Groups))
end

-- Suit suggestion for a custom card: a boss -> fateful, specials -> blight, more than 60 enemies and no elites -> swarm.
Cards.suggest_suit = function (parts, Groups)
	local kinds = Cards.kinds(parts, Groups)

	if kinds.boss then
		return "fateful"
	elseif kinds.special then
		return "blight"
	elseif total_enemies(parts) > 60 and not kinds.elite then
		return "swarm"
	end

	return nil
end

Cards.MAX_DOTS = 6

-- One coloured dot per enemy kind: the distinct colours of the enemies in the recipe, in order of appearance,
-- from `rgb_of(breed)` (the enemy colours of catalog/colors.lua). Returns a list of { r, g, b }.
Cards.dots = function (parts, rgb_of)
	local list, seen = {}, {}

	for i = 1, #(parts or {}) do
		local breeds = parts[i].one_of or { parts[i].breed }

		for j = 1, #breeds do
			local rgb = rgb_of(breeds[j])

			if rgb then
				local key = rgb[1] .. "," .. rgb[2] .. "," .. rgb[3]

				if not seen[key] and #list < Cards.MAX_DOTS then
					seen[key] = true
					list[#list + 1] = rgb
				end
			end
		end
	end

	return list
end

-- The same dots from a plain list of breed names (what a synced card carries): the HUD of a client has no recipe,
-- only the enemy kinds, and colours them with its own settings (Spidey Sense and so on).
Cards.dots_from_breeds = function (breeds, rgb_of)
	local list, parts = nil, {}

	for i = 1, #(breeds or {}) do
		parts[i] = { breed = breeds[i] }
	end

	list = Cards.dots(parts, rgb_of)

	return list
end

Cards.MAX_WHISPER = 40

Cards.clean_whisper = function (text)
	text = tostring(text or ""):gsub("[%c]", " "):gsub("%s+", " ")
	text = text:gsub("^%s+", ""):gsub("%s+$", "")

	if #text > Cards.MAX_WHISPER then
		text = text:sub(1, Cards.MAX_WHISPER):gsub("%s+$", "")
	end

	return text
end

-- The whisper of a card: its own text, else the line of its suit.
Cards.whisper = function (card)
	local own = Cards.clean_whisper(card.whisper)

	return own ~= "" and own or Cards.suit(card.suit).whisper
end

-- The modifiers of a recipe as one small line, "Purple · Enraged" (distinct, in catalog order).
Cards.modifier_line = function (parts, Groups)
	local present = {}

	for i = 1, #(parts or {}) do
		for j = 1, #(parts[i].mods or {}) do
			present[parts[i].mods[j]] = true
		end
	end

	local names = {}

	for _, modifier in ipairs(Groups.MODIFIERS) do
		if present[modifier.id] then
			names[#names + 1] = modifier.name
		end
	end

	return table.concat(names, " \194\183 ")
end

-- Everything the editor and the HUD show for one card (a wave from Events.get). `rgb_of(breed)` gives enemy colours.
Cards.describe = function (wave, Groups, rgb_of)
	local parts = wave.parts or {}
	local auto = Cards.threat_auto(parts, Groups)
	local suit = Cards.normalize_suit(wave.suit)
	local breeds, seen = {}, {}

	for i = 1, #parts do
		for _, breed in ipairs(parts[i].one_of or { parts[i].breed }) do
			if not seen[breed] and #breeds < 12 then
				seen[breed] = true
				breeds[#breeds + 1] = breed
			end
		end
	end

	return {
		key = wave.key,
		name = wave.name,
		suit = suit,
		threat = Cards.threat(parts, wave.threat_override, Groups),
		threat_auto = auto,
		threat_override = tonumber(wave.threat_override) or 0,
		dots = Cards.dots(parts, rgb_of or function () return nil end),
		breeds = breeds,
		whisper = Cards.whisper({ whisper = wave.whisper, suit = suit }),
		own_whisper = Cards.clean_whisper(wave.whisper) ~= "",
		look = Cards.look({ look = wave.look, suit = suit }),
		weight = tonumber(wave.pct) or 0,
		rare = Cards.is_rare(wave.pct),
		cooldown = tonumber(wave.cooldown) or Cards.DEFAULT_COOLDOWN,
		modifiers = Cards.modifier_line(parts, Groups),
		enabled = wave.enabled == true,
	}
end

-- ------------------------------------------------------------------------------------------- the old names
-- The user's own waves from before the Tarot rebuild, by their old name (normalized: lower case, letters and digits),
-- renamed ONCE (Cards.migrate) to their tarot card. Boss Ambush, Poxbuster Surprise etc. also have standard keys whose
-- default is the same card, see catalog/events.lua. A user's later renames always stay.
Cards.MIGRATION = {
	hordefodder = { name = "The Multitude", suit = "swarm" },
	escalatingmutants = { name = "The Wheel", suit = "plague" },
	bossambush = { name = "The Devil", suit = "fateful" },
	holyshitwelost = { name = "Death", suit = "fateful" },
	poxbustersurprise = { name = "The Tower", suit = "blight" },
	grenadechaos = { name = "Rain of Rot", suit = "blight", look = "vial" },
	dogwave = { name = "The Hunt", suit = "rage" },
	escalatingpussnipers = { name = "The Watching Moon", suit = "murmur" },
	eliteinjection = { name = "The Chariot", suit = "rage" },
}

local function squash(text)
	return (tostring(text or ""):lower():gsub("[^%w]", ""))
end

Cards.squash = squash

-- Renames the user's waves that still carry one of the old names and gives them their suit (and look); runs once
-- (the caller stores a flag). Returns the number of cards renamed. get/set: the mod's settings.
Cards.migrate = function (get_setting, set_setting, Events, Groups)
	local renamed = 0

	for _, key in ipairs(Events.keys()) do
		local wave = Events.get(key, get_setting, Groups)
		local rule = wave and Cards.MIGRATION[squash(wave.name)]

		if rule and wave.parts and #wave.parts > 0 and get_setting("su_" .. key) == nil then
			if rule.name ~= wave.name then
				Events.set_def(set_setting, key, rule.name, wave.parts, Groups)
				renamed = renamed + 1
			end

			set_setting("su_" .. key, rule.suit)

			if rule.look then
				set_setting("cl_" .. key, rule.look)
			end
		end
	end

	return renamed
end

return Cards
