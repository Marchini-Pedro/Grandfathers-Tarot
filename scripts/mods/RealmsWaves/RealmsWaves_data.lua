local mod = get_mod("RealmsWaves")

local function numeric(id, default, min, max, unit, step)
	return {
		setting_id = id,
		type = "numeric",
		default_value = default,
		range = { min, max },
		decimals_number = 0,
		step_size_value = step,
		unit_text = unit,
	}
end

local function keybind(id, function_name, default)
	return {
		setting_id = id,
		type = "keybind",
		default_value = default,
		keybind_trigger = "pressed",
		keybind_type = "function_call",
		function_name = function_name,
	}
end

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "mode",
				type = "dropdown",
				default_value = "random",
				options = {
					{ text = "mode_random", value = "random" },
					{ text = "mode_vote", value = "vote" },
				},
			},
			{
				setting_id = "group_timing",
				type = "group",
				sub_widgets = {
					numeric("initial_delay", 45, 0, 600, "unit_seconds"),
					numeric("interval_min", 150, 5, 1800, "unit_seconds"),
					numeric("interval_max", 300, 5, 1800, "unit_seconds"),
					numeric("vote_duration", 25, 5, 120, "unit_seconds"),
					numeric("ballot_size", 3, 2, 5, "unit_options"),
					{
						setting_id = "novote_fallback",
						type = "dropdown",
						default_value = "random",
						options = {
							{ text = "fallback_random", value = "random" },
							{ text = "fallback_skip", value = "skip" },
						},
					},
				},
			},
			{
				setting_id = "group_spawn",
				type = "group",
				sub_widgets = {
					numeric("max_per_wave", 80, 1, 500, "unit_enemies"),
					numeric("max_alive", 120, 10, 1000, "unit_enemies"),
					numeric("heap_guard_mb", 800, 300, 1000, "unit_megabytes", 10),
					numeric("min_distance", 22, 8, 100, "unit_meters"),
					numeric("max_distance", 65, 20, 200, "unit_meters"),
					numeric("monster_min_distance", 28, 8, 100, "unit_meters"),
					numeric("monster_max_distance", 75, 20, 200, "unit_meters"),
				},
			},
			{
				setting_id = "group_multipliers",
				type = "group",
				sub_widgets = {
					numeric("mult_normal", 100, 0, 500, "unit_percent", 5),
					numeric("mult_boss", 100, 0, 500, "unit_percent", 5),
					numeric("mult_special", 100, 0, 500, "unit_percent", 5),
				},
			},
			{
				setting_id = "group_controls",
				type = "group",
				sub_widgets = {
					keybind("open_editor_bind", "open_editor", { "f6" }),
					keybind("vote_1_bind", "vote_1", { "f1" }),
					keybind("vote_2_bind", "vote_2", { "f2" }),
					keybind("vote_3_bind", "vote_3", { "f3" }),
					keybind("vote_4_bind", "vote_4", {}),
					keybind("vote_5_bind", "vote_5", {}),
				},
			},
			{
				setting_id = "group_hud",
				type = "group",
				sub_widgets = {
					{ setting_id = "hud_enabled", type = "checkbox", default_value = true },
					{ setting_id = "debug", type = "checkbox", default_value = false },
				},
			},
		},
	},
}
