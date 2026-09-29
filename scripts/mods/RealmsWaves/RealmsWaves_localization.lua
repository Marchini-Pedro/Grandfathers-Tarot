local mod = get_mod("RealmsWaves")

local BASE = "RealmsWaves/scripts/mods/RealmsWaves/"

local localization = {
	mod_name = { en = "Realms Waves" },
	mod_description = {
		en = "Random enemy waves for Realms (LAN) sessions. Waves spawn near the squad but out of sight, ignore the director's spawn limits, and are picked at random or by an in-game vote. Everything is synced to all players' HUD. Host needs the mod; clients need it to see the HUD and vote.",
	},

	mode = { en = "Wave selection mode" },
	mode_random = { en = "Random (host rolls)" },
	mode_vote = { en = "Vote (players choose)" },

	group_timing = { en = "Timing and voting" },
	initial_delay = { en = "Extra delay before the first wave" },
	interval_min = { en = "Minimum time between waves" },
	interval_max = { en = "Maximum time between waves" },
	vote_duration = { en = "Final vote window (highlighted)" },
	ballot_size = { en = "Candidates on a ballot" },
	novote_fallback = { en = "If nobody votes" },
	fallback_random = { en = "Pick a candidate at random" },
	fallback_skip = { en = "Skip this wave" },

	group_spawn = { en = "Spawning" },
	max_per_wave = { en = "Max enemies per wave" },
	max_alive = { en = "Max wave enemies alive at once" },
	min_distance = { en = "Min spawn distance from nearest player" },
	max_distance = { en = "Max spawn distance from nearest player" },
	monster_min_distance = { en = "Monster min spawn distance" },
	monster_max_distance = { en = "Monster max spawn distance" },

	group_events = { en = "Standard waves: chance (relative, normalised to a total of 100 percent)" },
	group_custom = { en = "Custom waves: chance (set recipe with /rw_custom)" },

	group_controls = { en = "Vote keys" },
	vote_1_bind = { en = "Vote for option 1" },
	vote_2_bind = { en = "Vote for option 2" },
	vote_3_bind = { en = "Vote for option 3" },
	vote_4_bind = { en = "Vote for option 4" },
	vote_5_bind = { en = "Vote for option 5" },

	group_hud = { en = "HUD and debug" },
	hud_enabled = { en = "Show wave panel" },
	hud_x = { en = "Panel position X (percent of screen)" },
	hud_y = { en = "Panel position Y (percent of screen)" },
	debug = { en = "Debug logging" },

	unit_seconds = { en = "s" },
	unit_meters = { en = "m" },
	unit_enemies = { en = "enemies" },
	unit_options = { en = "options" },
	-- DMF passes localized strings through string.format, so a lone "%" is an error.
	unit_percent = { en = "percent" },

	hud_wave_in = { en = "Next wave in %s" },
	hud_wave_in_vote = { en = "Next wave in %s. Vote: %s" },
	hud_vote_now = { en = "VOTE NOW: %s left. %s" },
	hud_incoming = { en = "WAVE INCOMING: %s" },
	hud_no_votes = { en = "No votes, wave skipped" },
	hud_empty = { en = "Waves: no event enabled (set chances in mod options)" },
	hud_line = { en = "%s  %s (%s%%)" },
	hud_line_votes = { en = "%s  %s (%s%%)  [%d]" },
	vote_cast = { en = "Voted %d: %s" },
}

-- Per-event option titles (setting ids), generated from the catalog.
local ok, Events = pcall(mod.io_dofile, mod, BASE .. "catalog/events")

if ok and type(Events) == "table" then
	for i = 1, #Events.STANDARD do
		local def = Events.STANDARD[i]

		localization["pct_" .. def.key] = { en = def.name }
	end

	for slot = 1, Events.CUSTOM_SLOTS do
		localization["custom_" .. slot .. "_pct"] = { en = "Custom wave " .. slot }
	end
end

return localization
