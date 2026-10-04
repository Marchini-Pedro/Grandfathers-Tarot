-- Colours for enemy names in the wave editor (and anywhere else an enemy is named).
--
-- Order of preference for a breed:
--   1. the colour the player configured in the Spidey Sense mod for that enemy ("<type>_front_colour",
--      a Color.list name such as "turquoise"), when that mod is installed and the option is on;
--   2. this mod's own palette per enemy (Colors.PALETTE), by kind for the few it does not list.
-- Spidey Sense only knows about some enemies (Crusher, Mauler, Rager, Hound, Trapper, ...), the rest use the palette.
--
-- Pure Lua: everything engine-related (reading settings, the other mod, the Color table) is passed to
-- Colors.init() so it can be tested offline.
local Colors = {}

-- breed -> Spidey Sense enemy type (the prefix of its "<type>_front_colour" setting)
Colors.SPIDEY_TYPE = {
	chaos_ogryn_executor = "crusher",
	renegade_executor = "mauler",
	cultist_berzerker = "rager",
	renegade_berzerker = "rager",
	chaos_hound = "hound",
	chaos_armored_hound = "hound",
	chaos_poxwalker_bomber = "burster",
	cultist_mutant = "mutant",
	renegade_netgunner = "trapper",
	renegade_sniper = "sniper",
	renegade_plasma_gunner = "plasma_gunner",
	renegade_grenadier = "grenadier",
	cultist_grenadier = "toxbomber",
	renegade_flamer = "flamer",
	cultist_flamer = "flamer",
	chaos_plague_ogryn = "plague_ogryn",
	chaos_beast_of_nurgle = "beast_of_nurgle",
	chaos_spawn = "chaos_spawn",
	chaos_daemonhost = "daemonhost",
}

-- Own palette per enemy, {r, g, b}: used when Spidey Sense is off or does not know the enemy.
local FODDER = { 135, 135, 135 } -- weak grey
local GUNNER = { 80, 140, 255 } -- blue
local SHOTGUNNER = { 205, 195, 110 } -- weak yellow
local HOUND = { 255, 235, 40 } -- bright yellow
local FLAMER = { 255, 130, 10 } -- strong orange
local VANGUARD = { 115, 115, 125 } -- weak blackish (kept legible on the dark editor background)
local BOSS = { 255, 50, 50 } -- strong red
local CAPTAIN = { 66, 190, 66 } -- dull green, the colour of a captain's health bar (RecolorBossHealthBars default)
local TWIN = { 218, 186, 126 } -- the colour of the shield bar under a boss health bar (ui_hud_yellow_super_light)

Colors.PALETTE = {
	-- fodder
	chaos_poxwalker = FODDER,
	chaos_newly_infected = FODDER,
	chaos_armored_infected = FODDER,
	chaos_lesser_mutated_poxwalker = FODDER,
	chaos_mutated_poxwalker = FODDER,
	renegade_melee = FODDER,
	cultist_melee = FODDER,
	renegade_rifleman = FODDER,
	renegade_assault = FODDER,
	cultist_assault = FODDER,
	-- shotgunners
	renegade_shocktrooper = SHOTGUNNER,
	cultist_shocktrooper = SHOTGUNNER,
	-- ogryn and scab elites
	chaos_ogryn_executor = { 240, 240, 240 }, -- crusher: bright grey
	renegade_executor = { 185, 185, 185 }, -- mauler: grey
	chaos_ogryn_bulwark = { 85, 85, 95 }, -- blackish
	renegade_vanguard = VANGUARD,
	cultist_vanguard = VANGUARD,
	-- gunners
	renegade_gunner = GUNNER,
	cultist_gunner = GUNNER,
	chaos_ogryn_gunner = GUNNER,
	renegade_plasma_gunner = GUNNER,
	-- specials
	cultist_mutant = { 60, 255, 90 }, -- bright green
	chaos_hound = HOUND,
	chaos_armored_hound = HOUND,
	renegade_flamer = FLAMER,
	cultist_flamer = FLAMER,
	chaos_poxwalker_bomber = { 255, 140, 200 }, -- poxburster: pink
	renegade_netgunner = { 205, 70, 70 }, -- trapper: neutral red
	renegade_grenadier = { 255, 175, 100 }, -- bomber: orangeish
	cultist_grenadier = { 170, 255, 50 }, -- tox bomber: toxic green
	renegade_sniper = { 80, 215, 230 }, -- cyan (the gunners took the blue)
	-- bosses
	chaos_daemonhost = { 202, 62, 255 }, -- purple (also the colour of its health bar)
	renegade_captain = CAPTAIN,
	cultist_captain = CAPTAIN,
	renegade_twin_captain = TWIN,
	renegade_twin_captain_two = TWIN,
	chaos_beast_of_nurgle = BOSS,
	chaos_plague_ogryn = BOSS,
	chaos_spawn = BOSS,
	chaos_ogryn_houndmaster = BOSS,
}

-- Fallback by kind for the enemies without an entry above (the ragers, the radio operator...).
Colors.KIND = {
	special = { 255, 160, 60 },
	boss = BOSS,
	elite = { 235, 205, 90 },
	normal = FODDER,
}
local deps = {}
local cache = {}
local modifier_cache = {}

-- deps = {
--   kind = function (breed) -> "special" | "boss" | "elite" | "normal",
--   option = function (id) -> setting value of this mod,
--   spidey_setting = function (id) -> value of a Spidey Sense setting, or nil when that mod is absent,
--   named = function (name) -> {r, g, b} for a Color.list name, or nil,
-- }
Colors.init = function (new_deps)
	deps = new_deps or {}
	cache = {}
	modifier_cache = {}
end

-- The settings (and the other mod's colours) may change while the editor is closed.
Colors.clear_cache = function ()
	cache = {}
	modifier_cache = {}
end

local function enabled(id)
	local ok, value = pcall(deps.option or function () end, id)

	return not ok or value ~= false
end

local function spidey_colour(breed)
	local kind = Colors.SPIDEY_TYPE[breed]

	if not kind or not deps.spidey_setting or not deps.named or not enabled("colour_spidey") then
		return nil
	end

	local ok, name = pcall(deps.spidey_setting, kind .. "_front_colour")

	if not ok or type(name) ~= "string" or name == "" then
		return nil
	end

	local rgb_ok, rgb = pcall(deps.named, name)

	return rgb_ok and type(rgb) == "table" and rgb or nil
end

-- {r, g, b} for an enemy, or nil when colouring is switched off (or the breed is unknown).
Colors.rgb = function (breed)
	if not breed or not enabled("colour_enemies") then
		return nil
	end

	local cached = cache[breed]

	if cached == nil then
		cached = spidey_colour(breed) or Colors.PALETTE[breed] or Colors.KIND[deps.kind and deps.kind(breed) or "normal"] or Colors.KIND.normal
		cache[breed] = cached
	end

	return cached
end

-- {a, r, g, b} as the UI's text_color tables use it, or nil.
Colors.argb = function (breed)
	local rgb = Colors.rgb(breed)

	return rgb and { 255, rgb[1], rgb[2], rgb[3] } or nil
end

-- The game's inline colour tags (scripts/utilities/ui/text.lua:8-10).
Colors.markup = function (text, rgb)
	if not rgb then
		return text
	end

	return string.format("{#color(%d,%d,%d)}%s{#reset()}", rgb[1], rgb[2], rgb[3], text)
end

-- ---------------------------------------------------------------------------- faction colours
-- Whether an enemy is a Dreg (a cultist) or a Scab (a renegade): the Dregs are putrid, yellow-green like rot and bile; the Scabs are
-- armour, steel grey over black. FACTION is the colour of the word on a row. (The shelf chips were tinted by faction until 2026-10-04;
-- the design page's chips are plain, so the tint is gone.)
Colors.FACTION = {
	dreg = { 192, 200, 72 },
	scab = { 150, 156, 164 },
}

-- {r, g, b} of a faction ("dreg" | "scab"), or nil when colouring is switched off.
Colors.faction_rgb = function (faction)
	if not faction or not enabled("colour_enemies") then
		return nil
	end

	return Colors.FACTION[faction]
end

-- ---------------------------------------------------------------------------- modifier colours
-- Modifiers are coloured like the Improved Havoc Tags mod does: its colour option when it is installed,
-- otherwise ITS default colour (copied from ImprovedHavocTags_data.lua, so the look is the same either way).
-- modifier id (catalog/groups.lua) -> Improved Havoc Tags setting id
Colors.HAVOC_TAG_SETTING = {
	garden = "encroaching_garden",
	enraged = "enraged",
	toll = "enraged", -- The Final Toll turns the enemy enraged: the same red
	corrupted = "enemies_corrupted",
	bolstering = "bolstering_enemies",
	toughened = "tougher_skin",
	fire = "ember",
	parasite = "enemies_parasite_headshot",
	purple_stimm = "stimmed_minions",
	rotten = "rotten_armor",
}

-- its defaults, {r, g, b}
Colors.HAVOC_TAG_DEFAULT = {
	encroaching_garden = { 138, 43, 226 }, -- blue_violet
	enraged = { 255, 54, 36 }, -- ui_red_light
	enemies_corrupted = { 128, 128, 0 }, -- olive
	bolstering_enemies = { 208, 136, 48 }, -- item_rarity_5
	tougher_skin = { 157, 169, 75 }, -- citadel_ogryn_camo
	ember = { 160, 82, 45 }, -- sienna
	enemies_parasite_headshot = { 255, 160, 122 }, -- light_salmon
	stimmed_minions = { 255, 242, 0 }, -- citadel_dorn_yellow
	rotten_armor = { 132, 156, 99 }, -- citadel_nurgling_green
}

-- {r, g, b} for a modifier id, or nil when colouring is switched off. deps.havoc_setting(id) returns the
-- ImprovedHavocTags setting (an {a, r, g, b} table) or nil when that mod is not installed.
Colors.modifier_rgb = function (modifier_id)
	if not modifier_id or not enabled("colour_enemies") then
		return nil
	end

	local cached = modifier_cache[modifier_id]

	if cached == nil then
		local setting = Colors.HAVOC_TAG_SETTING[modifier_id]
		local value

		if setting and deps.havoc_setting then
			local ok, result = pcall(deps.havoc_setting, setting)

			value = ok and type(result) == "table" and result or nil
		end

		if value and type(value[2]) == "number" and type(value[3]) == "number" and type(value[4]) == "number" then
			cached = { value[2], value[3], value[4] }
		else
			cached = setting and Colors.HAVOC_TAG_DEFAULT[setting] or false
		end

		modifier_cache[modifier_id] = cached
	end

	return cached or nil
end

Colors.modifier_argb = function (modifier_id)
	local rgb = Colors.modifier_rgb(modifier_id)

	return rgb and { 255, rgb[1], rgb[2], rgb[3] } or nil
end
return Colors
