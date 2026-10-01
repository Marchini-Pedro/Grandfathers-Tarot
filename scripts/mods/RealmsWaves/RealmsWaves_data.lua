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

local function decimal(id, default, min, max, unit)
	return {
		setting_id = id,
		type = "numeric",
		default_value = default,
		range = { min, max },
		decimals_number = 1,
		step_size_value = 0.1,
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
				default_value = "tarot",
				options = {
					{ text = "mode_tarot", value = "tarot" },
					{ text = "mode_random", value = "random" },
					{ text = "mode_vote", value = "vote" },
				},
			},
			{
				setting_id = "group_timing",
				type = "group",
				sub_widgets = {
					numeric("tarot_cards", 4, 1, 5),
					numeric("tarot_seconds", 10, 5, 30, "unit_seconds"),
					numeric("tarot_default_cooldown", 120, 30, 1800, "unit_seconds", 30),
					numeric("initial_delay", 45, 0, 600, "unit_seconds"),
					{ setting_id = "interval_random", type = "checkbox", default_value = true },
					{ setting_id = "pool_all_players", type = "checkbox", default_value = false },
					{ setting_id = "anti_snowball", type = "checkbox", default_value = false },
					numeric("anti_snowball_delay", 30, 5, 120, "unit_seconds"),
					numeric("interval_min", 150, 5, 1800, "unit_seconds"),
					numeric("interval_max", 300, 5, 1800, "unit_seconds"),
					numeric("vote_duration", 25, 5, 120, "unit_seconds"),
					numeric("ballot_size", 3, 2, 5),
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
					numeric("max_per_wave", 80, 1, 500),
					numeric("max_alive", 120, 10, 1000),
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
				setting_id = "group_spread",
					type = "group",
					sub_widgets = {
						numeric("tarot_scale", 100, 50, 200, "unit_percent", 5),
						numeric("tarot_opacity", 100, 10, 100, "unit_percent", 5),
						{ setting_id = "tarot_timer_below", type = "checkbox", default_value = false },
						{ setting_id = "tarot_hide_icon", type = "checkbox", default_value = false },
						{ setting_id = "tarot_ping", type = "checkbox", default_value = true },
						{
							setting_id = "tarot_font",
							type = "dropdown",
							default_value = "itc_novarese_bold",
							options = {
								{ text = "font_novarese_bold", value = "itc_novarese_bold" },
								{ text = "font_novarese", value = "itc_novarese_medium" },
								{ text = "font_friz", value = "friz_quadrata" },
								{ text = "font_proxima", value = "proxima_nova_bold" },
								{ text = "font_rexlia", value = "rexlia" },
								{ text = "font_machine", value = "machine_medium" },
							},
						},
						decimal("tarot_roulette", 1.6, 0.4, 4, "unit_seconds"),
						decimal("tarot_winner", 1.6, 0.6, 5, "unit_seconds"),
						decimal("tarot_eye_open", 0.4, 0.1, 1.5, "unit_seconds"),
						numeric("tarot_eye_size", 28, 10, 80, "unit_pixels"),
						decimal("tarot_rot_short", 1.2, 0.4, 4, "unit_seconds"),
						decimal("tarot_rot_long", 3.0, 0.8, 8, "unit_seconds"),
						numeric("tarot_longest", 10, 2, 30, "unit_minutes"),
					},
				},
				{
					setting_id = "group_hud",
				type = "group",
				sub_widgets = {
					{ setting_id = "hud_enabled", type = "checkbox", default_value = true },
					{ setting_id = "hud_show_percent", type = "checkbox", default_value = true },
					{ setting_id = "colour_enemies", type = "checkbox", default_value = true },
					{ setting_id = "colour_spidey", type = "checkbox", default_value = true },
					{ setting_id = "debug", type = "checkbox", default_value = false },
				},
			},
		},
	},
}
