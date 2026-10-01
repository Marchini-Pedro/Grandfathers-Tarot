-- Colours for enemy names in the wave editor (and anywhere else an enemy is named).
--
-- Order of preference for a breed:
--   1. the colour the player configured in the Spidey Sense mod for that enemy ("<type>_front_colour",
--      a Color.list name such as "turquoise"), when that mod is installed and the option is on;
--   2. this mod's own palette by enemy kind (special / boss / elite / normal).
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

-- own palette by kind, {r, g, b}
Colors.KIND = {
	special = { 255, 160, 60 },
	boss = { 240, 90, 90 },
	elite = { 235, 205, 90 },
	normal = { 200, 215, 200 },
}

local deps = {}
local cache = {}

-- deps = {
--   kind = function (breed) -> "special" | "boss" | "elite" | "normal",
--   option = function (id) -> setting value of this mod,
--   spidey_setting = function (id) -> value of a Spidey Sense setting, or nil when that mod is absent,
--   named = function (name) -> {r, g, b} for a Color.list name, or nil,
-- }
Colors.init = function (new_deps)
	deps = new_deps or {}
	cache = {}
end

-- The settings (and the other mod's colours) may change while the editor is closed.
Colors.clear_cache = function ()
	cache = {}
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
		cached = spidey_colour(breed) or Colors.KIND[deps.kind and deps.kind(breed) or "normal"] or Colors.KIND.normal
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

return Colors
