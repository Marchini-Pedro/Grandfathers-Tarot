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

-- the suits: card, selected card, frame, text, accent. The first six are the reference page's exact values; the next four
-- (volley, snare, brute, dusk) are the same kind of colours (dark, desaturated, one accent), "warp" is the purple one, the
-- Daemonhost's own card (Cards.suggest_suit gives it to every card that holds a Daemonhost), and HERESY, the last hostile one, is the
-- one card that is not just another suit (it replaced "fester"): black and blood, crimson all the way through (since 2026-10-04: the
-- gilded accent became crimson), `special = true`, and every place that draws a card gives it what no other suit has: a frame at
-- rest, a glow that beats like a heart, a line of its own when it is drawn. The four BENEFICIAL suits follow (catalog/effects.lua):
-- Prayer, Miracle, Grace and Faith (the Order of the Sacred Rose, added 2026-10-04: the only pink in the deck).
-- (2026-10-04: Dusk is gone; NIGHTMARE, the darkest card, comes after Heresy: ... Warp, Heresy, Nightmare)
-- (2026-10-05: DREAM, the fifth beneficial suit and Nightmare's opposite, comes last)
Cards.SUIT_ORDER = { "plague", "murmur", "rage", "blight", "swarm", "fateful", "volley", "snare", "brute", "warp", "heresy", "nightmare", "prayer", "miracle", "grace", "faith", "dream" }
Cards.HOSTILE_COUNT = 12 -- the first twelve of SUIT_ORDER are hostile, the rest (five since Dream) beneficial

-- Names a suit used to have: cards saved, presets, shared texts and the hands other players sync may still say them (Fester became
-- Heresy). Catalog/events.lua keeps the same list for the settings.
Cards.SUIT_ALIAS = { fester = "heresy", dusk = "murmur" } -- (Dusk's cards became Murmur, the other night suit, on 2026-10-04)

Cards.SUITS = {
	plague = { name = "Plague", card = hex("#1e2413"), hi = hex("#2a3219"), frame = hex("#3a4421"), text = hex("#e6dfc3"), accent = hex("#b7c23a"), whisper = "Something is growing.", icon = "eye" },
	murmur = { name = "Murmur", card = hex("#0b0c0a"), hi = hex("#161a11"), frame = hex("#55603a"), text = hex("#cfcab0"), accent = hex("#9db07f"), whisper = "Do you hear it?", icon = "moon" },
	rage = { name = "Rage", card = hex("#241509"), hi = hex("#34200e"), frame = hex("#6b3a17"), text = hex("#ecd9bf"), accent = hex("#c27a2c"), whisper = "Faster. Faster.", icon = "flame" },
	blight = { name = "Blight", card = hex("#25240c"), hi = hex("#333212"), frame = hex("#5c5a1e"), text = hex("#ebe6bf"), accent = hex("#e3cf4a"), whisper = "The air turns.", icon = "drop" },
	swarm = { name = "Swarm", card = hex("#1b1d17"), hi = hex("#262a1f"), frame = hex("#474c3a"), text = hex("#d9d8c6"), accent = hex("#9aa37a"), whisper = "Too many to count.", icon = "cluster" },
	fateful = { name = "Fateful", card = hex("#17140f"), hi = hex("#231e14"), frame = hex("#8a7a4a"), text = hex("#efe6c9"), accent = hex("#e6dfc3"), whisper = "The last page.", icon = "star" },
	volley = { name = "Volley", card = hex("#121a1d"), hi = hex("#1b2a30"), frame = hex("#3d5963"), text = hex("#d5dfe0"), accent = hex("#7fb2c2"), whisper = "Something is aiming at you.", icon = "crosshair" },
	snare = { name = "Entrapment", card = hex("#0f1b18"), hi = hex("#17302a"), frame = hex("#2f5f55"), text = hex("#d3e1db"), accent = hex("#5fbfa5"), whisper = "You cannot run from this.", icon = "links" },
	brute = { name = "Brute", card = hex("#241311"), hi = hex("#35201b"), frame = hex("#74352b"), text = hex("#efdcd4"), accent = hex("#cf5c45"), whisper = "It does not stop for walls.", icon = "plate" },
	-- WARP lives too (2026-10-04): its glow pulses and crackles and motes of the warp rise from it (`motes`; `lit` is the crackle)
	warp = { name = "Warp", card = hex("#1a1127"), hi = hex("#281a3b"), frame = hex("#5e408f"), text = hex("#e9dff5"), accent = hex("#b184e0"), lit = hex("#ead6ff"), motes = true, whisper = "It knows your name.", icon = "warp" },
	-- HERESY: near black with blood in it, a frame the colour of fresh blood, a crimson accent; `lit` is the brighter red of its words on
	-- a dark ground, `blood` the deep red of its heartbeat glow and of the drops the HUD lets fall from it
	heresy = { name = "Heresy", special = true, card = hex("#0d0204"), hi = hex("#1f060a"), frame = hex("#8a0f1c"), text = hex("#efd3cc"), accent = hex("#d42a3a"), lit = hex("#ff3344"), blood = hex("#5a0610"), whisper = "He does not answer.", icon = "heresy" },
	-- NIGHTMARE (2026-10-04, the user: "like Heresy but all black, nightmarish, very dark and gloomy, super dangerous"): black on black,
	-- an ash accent, a horned eye. `gloom` is the darkness its glow breathes, `lit` the dying light that flickers in its frame, `ink`
	-- the black that drips from it. `once`: one Nightmare card per game (core/director.lua takes them all out of the draw after one).
	nightmare = { name = "Nightmare", special = true, once = true, card = hex("#030304"), hi = hex("#0b0a0f"), frame = hex("#2b2735"), text = hex("#d6d1df"), accent = hex("#9b93ad"), lit = hex("#f2eefa"), gloom = hex("#120e1a"), ink = hex("#000000"), fog = true, whisper = "It was never a dream.", icon = "nightmare" },
	prayer = { name = "Prayer", beneficial = true, special = true, card = hex("#0b2023"), hi = hex("#17363b"), frame = hex("#4F9CA3"), text = hex("#dcf1ed"), accent = hex("#4F9CA3"), whisper = "The faithful are not forsaken.", icon = "prayer" },
	miracle = { name = "Miracle", beneficial = true, special = true, card = hex("#231b0b"), hi = hex("#392d13"), frame = hex("#D8B45A"), text = hex("#fff2cf"), accent = hex("#D8B45A"), whisper = "A light in the darkest hour.", icon = "miracle" },
	grace = { name = "Grace", beneficial = true, special = true, card = hex("#1b2229"), hi = hex("#2c3540"), frame = hex("#E8EEF4"), text = hex("#f8fafc"), accent = hex("#E8EEF4"), whisper = "Rise, and carry the light.", icon = "grace" },
	-- FAITH: the Order of the Sacred Rose, a wine-rose card with a sacred rose pink (no other suit is pink), a rose in a ring
	faith = { name = "Faith", beneficial = true, special = true, card = hex("#220f1c"), hi = hex("#391a2e"), frame = hex("#c25a8c"), text = hex("#ffe4ef"), accent = hex("#f08cb8"), whisper = "Believe, and endure.", icon = "faith" },
	-- DREAM (2026-10-05, the user: "the opposite of Nightmare: full of colours, something positive, cloudy, heavenly, dreamy; go hard"):
	-- the brightest card of the deck, a twilight lavender with a sky-blue accent, a pastel pink frame that turns through a rainbow
	-- (`rainbow`), clouds in every colour on its face (ui/aura.lua) and a sky that opens over the screen when it is drawn
	-- (ui/hud_element_dream.lua). `lit` is the sunlight of its stars. A cloud with a star.
	dream = { name = "Dream", beneficial = true, special = true, rainbow = true, card = hex("#2b2560"), hi = hex("#3b3380"), frame = hex("#ffb3e6"), text = hex("#fffaff"), accent = hex("#9fe8ff"), lit = hex("#fff4b8"), whisper = "Sleep now, and wake whole.", icon = "dream" },
}

-- every suit knows its own id (the HUD and the aura of a card go from the suit to its effects)
for id, def in pairs(Cards.SUITS) do
	def.id = id
end

-- one colour per threat level 1..6 (unfilled diamonds are an outline in the muted colour)
Cards.THREAT_COLORS = { hex("#a7c27c"), hex("#74b22c"), hex("#e3cf4a"), hex("#d98a2e"), hex("#cf4a30"), hex("#16131f") }
Cards.THREAT_MAX = 6
Cards.DESPAIR_EDGE = hex("#c7b8e0")
-- the sixth diamond of a BENEFICIAL card is not Despair: it is Apotheosis, the suit's accent edged in a warm white light
Cards.APOTHEOSIS_EDGE = hex("#fff6dc")
Cards.threat_edge = function (suit)
	local face = type(suit) == "table" and suit or Cards.suit(suit)

	return face.beneficial and Cards.APOTHEOSIS_EDGE or Cards.DESPAIR_EDGE
end
-- The name of a threat level, nil below 6: level 6 is DESPAIR on a hostile card and APOTHEOSIS on a beneficial one.
Cards.threat_name = function (level, suit)
	if tonumber(level) ~= 6 then
		return nil
	end

	local face = type(suit) == "table" and suit or Cards.suit(suit)

	return face.beneficial and "Apotheosis" or "Despair"
end
-- The strong shine of the sixth diamond (HUD, Deck tile, editor): a pulse 0..1 at time t. Despair breathes slowly and darkly,
-- Apotheosis glitters faster; both stay above 0.35 so the diamond never fades away.
Cards.six_shine = function (t, suit)
	local face = type(suit) == "table" and suit or Cards.suit(suit)
	local speed = face.beneficial and 3.4 or 2.1
	local wave = 0.5 + 0.5 * math.sin((tonumber(t) or 0) * speed)

	return 0.35 + 0.65 * wave * wave
end
-- The heartbeat of a Heresy card (a double beat, then rest, about 70 per minute): 0..1 at time t.
Cards.heartbeat = function (t)
	local p = ((tonumber(t) or 0) % 0.86) / 0.86
	local function beat(centre, width)
		local d = (p - centre) / width

		return math.exp(-d * d)
	end

	return math.min(1, beat(0.08, 0.06) + 0.7 * beat(0.28, 0.07))
end
-- Nightmare's dread at time t: a slow breath of darkness (0..1, one every 3.3 s) and, now and then, a flash like a dying light (0, or
-- 0.6 to 1 for a ninth of a second: a flash is always plain to see).
Cards.dread = function (t)
	t = tonumber(t) or 0
	local h = (math.sin(math.floor(t * 9) * 12.9898) * 43758.5453) % 1

	return 0.5 + 0.5 * math.sin(t * 1.9), h > 0.94 and 0.6 + 0.4 * (h - 0.94) / 0.06 or 0
end
-- Nightmare's black fog (2026-10-04, the user: "a black fog that comes and goes, it needs to be very special"), over everything on
-- its card: at time t the veil over the whole card (0..1: mostly clear, then a slow surge of darkness every 7.4 s) and, for band i
-- (1..FOG_BANDS), where the middle of that bank of fog is (0..1 down the card; the banks drift down and come back from the top) and
-- how thick it is (0..1, thickest when the veil is).
Cards.FOG_BANDS = 3
Cards.fog = function (t, i)
	t = tonumber(t) or 0

	local surge = 0.5 + 0.5 * math.sin(t * 0.85)
	local veil = surge * surge * surge

	if not i then
		return veil
	end

	return (t * (0.05 + 0.02 * i) + i * 0.37) % 1.3 - 0.15, math.min(1, veil * 1.4) * (0.65 + 0.35 * math.sin(t * 1.3 + i * 2.1))
end
-- The warp at time t: an uneven pulse (0..1) and a crackle (0 or 1, about one beat in eight at 14 per second).
Cards.warp_pulse = function (t)
	t = tonumber(t) or 0
	local h = (math.sin(math.floor(t * 14) * 78.233) * 12543.873) % 1

	return 0.5 + 0.5 * math.sin(t * 2.7 + math.sin(t * 0.9) * 1.6), h > 0.88 and 1 or 0
end
Cards.threat_color = function (level, suit)
	local face = type(suit) == "table" and suit or Cards.suit(suit)
	return face.beneficial and face.accent or Cards.THREAT_COLORS[level]
end

-- a card with this weight or less is "rare": pus-yellow outline (the old, absolute rule: only used where no deck is known)
Cards.RARE_WEIGHT = 2

-- the place of a suit in Cards.SUIT_ORDER (1 to 16; an unknown suit is plague, 1; an old name counts as its new one)
Cards.suit_index = function (suit)
	local wanted = Cards.normalize_suit(suit)

	for i = 1, #Cards.SUIT_ORDER do
		if Cards.SUIT_ORDER[i] == wanted then
			return i
		end
	end

	return 1
end

Cards.normalize_suit = function (suit)
	suit = Cards.SUIT_ALIAS[suit] or suit

	return Cards.SUITS[suit] and suit or "plague"
end

-- True for the suit that is a card apart (Heresy): the places that draw a card give it its own frame and glow.
Cards.is_special = function (suit)
	return Cards.suit(suit).special == true
end

Cards.suit = function (suit)
	return Cards.SUITS[Cards.normalize_suit(suit)]
end

Cards.is_rare = function (weight)
	weight = tonumber(weight) or 0

	return weight > 0 and weight <= Cards.RARE_WEIGHT
end

-- ---------------------------------------------------------------------------------------------- chance
-- The chance of a card is a whole number from 1 to 10 (0 = never drawn) and the ten pips of a tile show exactly that number.
-- It is NOT relative to the other cards: how likely a card is in a draw is its chance over the chances of the cards that
-- can be drawn at that moment (the cards that rest after a pick leave the draw, so the others become likelier).
Cards.LEVELS = 10
Cards.MAX_CHANCE = 10

-- the pips of a chance: 0 for none, else the number rounded and kept between 1 and 10 (the extra arguments of the old,
-- relative version are ignored)
Cards.level = function (weight)
	weight = tonumber(weight) or 0

	if weight <= 0 then
		return 0
	end

	return math.max(1, math.min(Cards.LEVELS, math.floor(weight + 0.5)))
end

-- A card is "rare" when its chance is 1 or 2 (Cards.RARE_WEIGHT).
Cards.is_rare_level = function (level)
	level = tonumber(level) or 0

	return level >= 1 and level <= Cards.RARE_WEIGHT
end

-- The chance a click on pip `level` sets: the level itself (kept between 1 and 10)
Cards.weight_for_level = function (level)
	return math.max(1, math.min(Cards.LEVELS, math.floor((tonumber(level) or 1) + 0.5)))
end

-- Share of the draw in percent of a card with chance `weight`, among cards whose chances add up to `total` (the card itself
-- is part of the total); nil when it cannot be drawn.
Cards.share = function (weight, total)
	weight, total = tonumber(weight) or 0, tonumber(total) or 0

	if weight <= 0 or total <= 0 then
		return nil
	end

	return weight / total * 100
end

-- ---------------------------------------------------------------------------------------------- cooldown looks
Cards.LOOKS = { "rot", "whisper", "vial" }

local VALID_LOOK = { rot = true, whisper = true, vial = true }

Cards.normalize_look = function (look)
	return VALID_LOOK[look] and look or nil
end

-- The look a card uses. Since 2026-10-04 every card rots and renews (the user removed the choice of look): a saved look (cl_ setting,
-- presets, shared cards) is still read and kept, so old texts load, but it no longer changes anything. The murmur lives on as the
-- way a threat 5 or 6 card shows its whisper when it is drawn (Cards.murmurs).
Cards.look = function (card)
	return "rot"
end

-- True when a card of this threat murmurs its whisper letter by letter when it is drawn and chosen (threat 5 and 6).
Cards.MURMUR_THREAT = 5
Cards.murmurs = function (threat)
	return (tonumber(threat) or 0) >= Cards.MURMUR_THREAT
end

Cards.COOLDOWN_STEP = 30 -- seconds, also the shortest cooldown
Cards.DEFAULT_COOLDOWN = 120

-- Rot strength k = clamp(log(cooldown / 30) / log(longest / 30), 0, 1) (longest in seconds), the longer the cooldown
-- the harder a consumed card rots (reference page `corr()`).
Cards.rot_strength = function (cooldown, longest)
	longest = math.max(Cards.COOLDOWN_STEP * 2, tonumber(longest) or 1800)
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

-- The first n bytes of a text, cut back to the start of a letter (a two-byte letter is never cut in half).
Cards.utf8_cut = function (text, n)
	if n >= #text then
		return text
	end

	local cut = n

	while cut > 0 do
		local byte = text:byte(cut + 1)

		if byte and byte >= 0x80 and byte < 0xC0 then
			cut = cut - 1
		else
			break
		end
	end

	return text:sub(1, cut)
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

	if override >= 1 and override <= 6 then
		return math.floor(override)
	end

	return (Cards.threat_auto(parts, Groups))
end

-- True when a recipe holds the given breed (also as one of the picks of a random group).
Cards.has_breed = function (parts, breed)
	for i = 1, #(parts or {}) do
		local part = parts[i]

		if part.breed == breed then
			return true
		end

		for j = 1, #(part.one_of or {}) do
			if part.one_of[j] == breed then
				return true
			end
		end
	end

	return false
end

Cards.DAEMONHOST = "chaos_daemonhost"

-- Suit suggestion for a custom card: a Daemonhost -> warp, a boss -> fateful, specials -> blight, more than 60 enemies and
-- no elites -> swarm.
Cards.suggest_suit = function (parts, Groups)
	if Cards.has_breed(parts, Cards.DAEMONHOST) then
		return "warp"
	end

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

-- The modifiers of a recipe as one small line, "Purple · Enraged" (distinct, in catalog order). `paint(name, id)` (optional)
-- returns the name of one modifier dressed up (the editor passes colour tags in the Improved Havoc Tags colour of the
-- modifier); the separators stay plain.
Cards.modifier_line = function (parts, Groups, paint)
	local present = {}

	for i = 1, #(parts or {}) do
		for j = 1, #(parts[i].mods or {}) do
			present[parts[i].mods[j]] = true
		end
	end

	local names = {}

	for _, modifier in ipairs(Groups.MODIFIERS) do
		if present[modifier.id] then
			names[#names + 1] = paint and paint(modifier.name, modifier.id) or modifier.name
		end
	end

	-- custom mods (health, size, speed...) of any group: one more word, so a card that has them says so
	if Groups.has_tune and Groups.has_tune(parts) then
		names[#names + 1] = paint and paint("Custom", "custom") or "Custom"
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
		-- a beneficial card's dots are the colours of its effects' groups
		dots = (Cards.suit(suit).beneficial and Groups and Groups.Effects and wave.effects) and Groups.Effects.dots(wave.effects) or Cards.dots(parts, rgb_of or function () return nil end),
		breeds = breeds,
		whisper = Cards.whisper({ whisper = wave.whisper, suit = suit }),
		own_whisper = Cards.clean_whisper(wave.whisper) ~= "",
		effects = wave.effects,
		sound = wave.sound,
		look = Cards.look({ look = wave.look, suit = suit }),
		weight = tonumber(wave.pct) or 0,
		level = Cards.level(wave.pct),
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
