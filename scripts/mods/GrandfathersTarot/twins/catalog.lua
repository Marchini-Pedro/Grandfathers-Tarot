-- Pure data (merged from SoloPlayPurpleStimms on 2026-10-07): every enemy Twins can configure. Loaded (via mod:io_dofile) by the options menu, the
-- localization file and the runtime script, so it must not touch any game global.
--
-- Fields
--   id         breed name
--   name       English fallback; the game's own localized breed name is used when it resolves
--   loc        the game's localization key for the breed name
--   boss       true for bosses/captains (own dropdown, master toggle, non-despawning buff variant)
--   stim       true when the breed's behavior tree has a stim animation (breed_actions define stim_buffs)
--   enabled    whether the breed is affected by default
--   chance     default chance in percent
--   spawnable  true when it is offered in the "enemy spawned on death" dropdowns
--   twin1, twin2, twins_buff  the default twins and their stim ("default": the game's own); the author's choices (2026-10-08)
local catalog = {}

local function _entry(id, name, options)
	options = options or {}

	return {
		id = id,
		name = name,
		loc = options.loc or ("loc_breed_display_name_" .. id),
		boss = options.boss or false,
		stim = options.stim or false,
		enabled = options.enabled or false,
		chance = options.chance or 50,
		spawnable = options.spawnable or false,
		hidden = options.hidden or false,
		twin1 = options.twin1 or "default",
		twin2 = options.twin2 or "default",
		twins_buff = options.twins_buff or "default",
	}
end

-- Defaults follow the game (havoc_mutator_local_settings.lua, mutator_stimmed_minions.breed_chances):
-- only the two captains are ever stimmed, at 20%. Every other boss is off until you turn it on, except the Daemonhost (30%, with
-- the Poxburster: the author's defaults, 2026-10-08).
catalog.bosses = {
	_entry("chaos_beast_of_nurgle", "Beast of Nurgle", { boss = true, chance = 100, spawnable = true }),
	_entry("chaos_plague_ogryn", "Plague Ogryn", { boss = true, chance = 100, spawnable = true, loc = "loc_breed_display_name_chaos_plage_ogryn" }),
	_entry("chaos_spawn", "Chaos Spawn", { boss = true, chance = 100, spawnable = true }),
	_entry("chaos_daemonhost", "Daemonhost", { boss = true, enabled = true, chance = 30, spawnable = true }),
	_entry("chaos_ogryn_houndmaster", "Ogryn Houndmaster", { boss = true, chance = 100 }),
	_entry("cultist_captain", "Cultist Captain", { boss = true, stim = true, chance = 20, enabled = true }),
	_entry("renegade_captain", "Renegade Captain", { boss = true, stim = true, chance = 20, enabled = true }),
	_entry("renegade_twin_captain", "Renegade Twin Captain", { boss = true, chance = 100 }),
	_entry("renegade_twin_captain_two", "Renegade Twin Captain (Second)", { boss = true, chance = 100 }),
}

-- Ordered: horde, specials, elites, everything else. "stim" marks a stim animation; "enabled"/"chance"
-- are the game's own stimmed-minions breed_chances (breeds it does not list are off, at 30%).
catalog.enemies = {
	-- horde
	_entry("chaos_poxwalker", "Poxwalker", { spawnable = true }),
	_entry("chaos_newly_infected", "Newly Infected", { spawnable = true }),
	_entry("chaos_armored_infected", "Armoured Infected", { spawnable = true, loc = "loc_chaos_armored_infected_breed_name" }),
	_entry("chaos_mutated_poxwalker", "Mutated Poxwalker", { spawnable = true }),
	_entry("chaos_lesser_mutated_poxwalker", "Lesser Mutated Poxwalker", { spawnable = true }),
	-- specials
	_entry("chaos_hound", "Pox Hound", { spawnable = true }),
	_entry("chaos_armored_hound", "Armoured Pox Hound", { spawnable = true }),
	_entry("chaos_poxwalker_bomber", "Poxburster", { enabled = true, spawnable = true, twin1 = "chaos_poxwalker_bomber", twin2 = "chaos_poxwalker_bomber", twins_buff = "never" }),
	_entry("cultist_flamer", "Cultist Flamer", { spawnable = true }),
	_entry("renegade_flamer", "Renegade Flamer", { spawnable = true }),
	_entry("cultist_grenadier", "Cultist Grenadier", { spawnable = true }),
	_entry("renegade_grenadier", "Renegade Grenadier", { spawnable = true }),
	_entry("cultist_mutant", "Mutant", { spawnable = true }),
	_entry("renegade_netgunner", "Trapper", { spawnable = true }),
	_entry("renegade_sniper", "Sniper", { spawnable = true }),
	-- elites
	_entry("chaos_ogryn_bulwark", "Bulwark", { stim = true, enabled = true, chance = 30, spawnable = true }),
	_entry("chaos_ogryn_executor", "Crusher", { stim = true, enabled = true, chance = 30, spawnable = true }),
	_entry("chaos_ogryn_gunner", "Reaper", { stim = true, chance = 30, spawnable = true }),
	_entry("cultist_berzerker", "Cultist Berzerker", { stim = true, enabled = true, chance = 40, spawnable = true }),
	_entry("cultist_gunner", "Cultist Gunner", { stim = true, chance = 30, spawnable = true }),
	_entry("cultist_shocktrooper", "Cultist Shocktrooper", { stim = true, enabled = true, chance = 30, spawnable = true }),
	_entry("renegade_berzerker", "Renegade Berzerker", { stim = true, enabled = true, chance = 40, spawnable = true }),
	_entry("renegade_executor", "Renegade Executor", { stim = true, enabled = true, chance = 30, spawnable = true }),
	_entry("renegade_gunner", "Renegade Gunner", { stim = true, chance = 30, spawnable = true }),
	_entry("renegade_plasma_gunner", "Renegade Plasma Gunner", { stim = true, enabled = true, chance = 30, spawnable = true }),
	_entry("renegade_shocktrooper", "Renegade Shocktrooper", { stim = true, enabled = true, chance = 30, spawnable = true }),
	_entry("renegade_radio_operator", "Renegade Radio Operator"),
	-- everything else
	_entry("cultist_assault", "Cultist Assault", { stim = true, enabled = true, chance = 50, spawnable = true }),
	_entry("cultist_melee", "Cultist Bruiser", { stim = true, enabled = true, chance = 30, spawnable = true }),
	_entry("cultist_vanguard", "Cultist Vanguard", { stim = true, chance = 30, spawnable = true }),
	_entry("renegade_assault", "Renegade Assault", { stim = true, enabled = true, chance = 30, spawnable = true }),
	_entry("renegade_melee", "Renegade Bruiser", { stim = true, enabled = true, chance = 30, spawnable = true }),
	_entry("renegade_rifleman", "Renegade Rifleman", { stim = true, enabled = true, chance = 50, spawnable = true }),
	_entry("renegade_vanguard", "Renegade Vanguard", { stim = true, chance = 30, spawnable = true }),
	_entry("cultist_ritualist", "Ritualist"),
}

-- Spawnable but not configurable: only reachable through the game's default twin rules.
catalog.extra_spawnable = {
	_entry("chaos_hound_mutator", "Pox Hound (Mutator)", { spawnable = true, hidden = true }),
}

-- The game's own purple-stim split rules (mutator_buff_templates.lua, TWIN_SPLIT_BREED_LIST): the
-- breed that a dying enemy is split into, twice. Used when a twin slot is set to "Default".
catalog.default_twins = {
	chaos_beast_of_nurgle = "chaos_ogryn_bulwark",
	chaos_daemonhost = "chaos_spawn",
	chaos_hound = "chaos_hound_mutator",
	chaos_ogryn_bulwark = "renegade_berzerker",
	chaos_ogryn_executor = "renegade_executor",
	chaos_ogryn_gunner = "renegade_gunner",
	chaos_plague_ogryn = "chaos_ogryn_executor",
	chaos_poxwalker_bomber = "renegade_executor",
	chaos_spawn = "cultist_mutant",
	cultist_assault = "chaos_newly_infected",
	cultist_berzerker = "cultist_melee",
	cultist_flamer = "cultist_shocktrooper",
	cultist_grenadier = "renegade_gunner",
	cultist_gunner = "cultist_assault",
	cultist_melee = "chaos_poxwalker",
	cultist_mutant = "cultist_berzerker",
	cultist_shocktrooper = "cultist_assault",
	renegade_assault = "chaos_newly_infected",
	renegade_berzerker = "renegade_melee",
	renegade_captain = "chaos_daemonhost",
	renegade_executor = "renegade_melee",
	renegade_flamer = "renegade_shocktrooper",
	renegade_grenadier = "renegade_gunner",
	renegade_gunner = "renegade_rifleman",
	renegade_melee = "chaos_newly_infected",
	renegade_netgunner = "renegade_berzerker",
	renegade_rifleman = "chaos_newly_infected",
	renegade_shocktrooper = "renegade_assault",
	renegade_sniper = "renegade_gunner",
}

-- lookups and the twin dropdown values, derived once
catalog.by_id = {}
catalog.twin_choices = {
	"default",
	"none",
}

local function _index(list)
	for i = 1, #list do
		local entry = list[i]

		catalog.by_id[entry.id] = entry

		if entry.spawnable then
			catalog.twin_choices[#catalog.twin_choices + 1] = entry.id
		end
	end
end

_index(catalog.bosses)
_index(catalog.enemies)
_index(catalog.extra_spawnable)

return catalog
