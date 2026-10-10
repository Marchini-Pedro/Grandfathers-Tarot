local mod = get_mod("GrandfathersTarot")

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

-- Twins (2026-10-07, merged from SoloPlayPurpleStimms): one dropdown picks the boss / enemy and one set of widgets edits it; the
-- values are stored per breed and swapped into the widgets when the dropdown changes (twins/twins.lua, Twins.on_setting_changed)
local twins_catalog = mod:io_dofile("GrandfathersTarot/scripts/mods/GrandfathersTarot/twins/catalog")

local function twins_breed_widgets(kind, list)
	local selector, twin_options = {}, {}

	for i = 1, #list do
		selector[i] = { text = "tw_" .. kind .. "_" .. list[i].id, value = list[i].id }
	end

	for i = 1, #twins_catalog.twin_choices do
		local id = twins_catalog.twin_choices[i]

		twin_options[i] = { text = "tw_twin_" .. id, value = id }
	end

	return {
		{ setting_id = "tw_" .. kind .. "_selector", type = "dropdown", tooltip = "tw_" .. kind .. "_selector_tooltip", default_value = list[1].id, options = selector },
		{ setting_id = "tw_" .. kind .. "_enabled", type = "checkbox", tooltip = "tw_enabled_tooltip", default_value = false },
		{ setting_id = "tw_" .. kind .. "_chance", type = "numeric", tooltip = "tw_" .. kind .. "_chance_tooltip", default_value = 50, range = { 0, 100 }, unit_text = "unit_percent" },
		{ setting_id = "tw_" .. kind .. "_twin1", type = "dropdown", tooltip = "tw_" .. kind .. "_twin_tooltip", default_value = "default", options = twin_options },
		{ setting_id = "tw_" .. kind .. "_twin2", type = "dropdown", tooltip = "tw_" .. kind .. "_twin_tooltip", default_value = "default", options = twin_options },
		{
			setting_id = "tw_" .. kind .. "_twins_buff",
			type = "dropdown",
			tooltip = "tw_twins_buff_tooltip",
			default_value = "default",
			options = {
				{ text = "tw_twins_buff_default", value = "default" },
				{ text = "tw_twins_buff_always", value = "always" },
				{ text = "tw_twins_buff_never", value = "never" },
			},
		},
	}
end

local function twins_bosses()
	local widgets = {
		{ setting_id = "tw_bosses_enabled", type = "checkbox", tooltip = "tw_bosses_enabled_tooltip", default_value = true },
		{ setting_id = "tw_bosses_chance", type = "numeric", tooltip = "tw_bosses_chance_tooltip", default_value = 100, range = { 0, 100 }, unit_text = "unit_percent" },
	}

	for _, widget in ipairs(twins_breed_widgets("boss", twins_catalog.bosses)) do
		widgets[#widgets + 1] = widget
	end

	return widgets
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
					numeric("tarot_cards", 3, 1, 5),
					numeric("tarot_seconds", 30, 5, 30, "unit_seconds"),
					numeric("tarot_default_cooldown", 120, 30, 1800, "unit_seconds", 30),
					numeric("cooldown_reset_pct", 90, 0, 100, "unit_percent", 5),
					{ setting_id = "nightmare_repeat", type = "checkbox", default_value = true },
					numeric("initial_delay", 0, 0, 600, "unit_seconds"),
					{ setting_id = "interval_random", type = "checkbox", default_value = false },
					{ setting_id = "pool_all_players", type = "checkbox", default_value = false },
					{ setting_id = "anti_snowball", type = "checkbox", default_value = true },
					numeric("anti_snowball_delay", 25, 5, 120, "unit_seconds"),
					numeric("interval_min", 75, 5, 1800, "unit_seconds"),
					numeric("interval_max", 195, 5, 1800, "unit_seconds"),
					numeric("vote_duration", 5, 5, 120, "unit_seconds"),
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
					numeric("max_per_wave", 200, 1, 500),
					numeric("max_alive", 400, 10, 1000),
					numeric("heap_guard_mb", 960, 300, 1000, "unit_megabytes", 10),
					numeric("min_distance", 15, 8, 100, "unit_meters"),
					numeric("max_distance", 100, 20, 200, "unit_meters"),
					numeric("monster_min_distance", 30, 8, 100, "unit_meters"),
					numeric("monster_max_distance", 120, 20, 200, "unit_meters"),
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
					keybind("open_editor_bind", "open_editor", { "num -" }),
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
						{ setting_id = "tarot_timer_below", type = "checkbox", default_value = true },
						{ setting_id = "tarot_hide_icon", type = "checkbox", default_value = false },
						{ setting_id = "tarot_ping", type = "checkbox", default_value = false },
						{
							setting_id = "tarot_font",
							type = "dropdown",
							default_value = "itc_novarese_medium",
							options = {
								{ text = "font_novarese_bold", value = "itc_novarese_bold" },
								{ text = "font_novarese", value = "itc_novarese_medium" },
								{ text = "font_friz", value = "friz_quadrata" },
								{ text = "font_proxima", value = "proxima_nova_bold" },
								{ text = "font_rexlia", value = "rexlia" },
								{ text = "font_machine", value = "machine_medium" },
							},
						},
						decimal("tarot_roulette", 2.1, 0.4, 4, "unit_seconds"),
						decimal("tarot_winner", 3, 0.6, 5, "unit_seconds"),
						decimal("tarot_eye_open", 1.2, 0.1, 1.5, "unit_seconds"),
						numeric("tarot_eye_size", 22, 10, 80, "unit_pixels"),
						decimal("tarot_rot_short", 1.2, 0.4, 4, "unit_seconds"),
						decimal("tarot_rot_long", 6, 0.8, 8, "unit_seconds"),
						numeric("tarot_longest", 30, 2, 30, "unit_minutes"),
					},
				},
				{
					setting_id = "group_hud",
				type = "group",
				sub_widgets = {
					{ setting_id = "hud_enabled", type = "checkbox", default_value = true },
					{ setting_id = "hud_last_card", type = "checkbox", default_value = true },
					{ setting_id = "hud_avoid_boss_bars", type = "checkbox", default_value = true },
					{ setting_id = "hud_boss_bars_below", type = "checkbox", default_value = false },
					numeric("hud_boss_opacity", 65, 10, 100, "unit_percent", 5),
					numeric("hud_last_transparency", 25, 0, 100, "unit_percent", 5),
					{ setting_id = "card_share_icons", type = "checkbox", default_value = true },
					{ setting_id = "card_sounds", type = "checkbox", default_value = true },
					{ setting_id = "nightmare_dread", type = "checkbox", default_value = true },
					{ setting_id = "card_auras", type = "checkbox", default_value = true },
					{ setting_id = "deck_card_effects", type = "checkbox", default_value = true },
					numeric("dream_sky_strength", 50, 0, 150, "unit_percent", 5),
					numeric("nightmare_fog_strength", 70, 0, 100, "unit_percent", 5),
					{ setting_id = "hud_show_percent", type = "checkbox", default_value = false },
					{ setting_id = "colour_enemies", type = "checkbox", default_value = true },
					{ setting_id = "colour_spidey", type = "checkbox", default_value = false },
					{ setting_id = "debug", type = "checkbox", default_value = false },
				},
			},
			-- Twins (2026-10-07, merged from SoloPlayPurpleStimms)
			{
				setting_id = "group_twins",
				type = "group",
				sub_widgets = {
					{ setting_id = "tw_guest_safe", type = "checkbox", tooltip = "tw_guest_safe_tooltip", default_value = false },
					{ setting_id = "tw_no_restim", type = "checkbox", tooltip = "tw_no_restim_tooltip", default_value = true },
					{ setting_id = "tw_loop_check", type = "checkbox", tooltip = "tw_loop_check_tooltip", default_value = true },
					{ setting_id = "tw_color_custom", type = "checkbox", tooltip = "tw_color_custom_tooltip", default_value = false },
					{ setting_id = "tw_color_r", type = "numeric", tooltip = "tw_color_channel_tooltip", default_value = 191, range = { 0, 255 } },
					{ setting_id = "tw_color_g", type = "numeric", tooltip = "tw_color_channel_tooltip", default_value = 0, range = { 0, 255 } },
					{ setting_id = "tw_color_b", type = "numeric", tooltip = "tw_color_channel_tooltip", default_value = 191, range = { 0, 255 } },
					{ setting_id = "tw_smoke_enabled", type = "checkbox", tooltip = "tw_smoke_enabled_tooltip", default_value = true },
					{ setting_id = "tw_smoke_sound", type = "checkbox", tooltip = "tw_smoke_sound_tooltip", default_value = true },
				},
			},
			{ setting_id = "group_twins_bosses", type = "group", sub_widgets = twins_bosses() },
			{ setting_id = "group_twins_enemies", type = "group", sub_widgets = twins_breed_widgets("enemy", twins_catalog.enemies) },
			{
				setting_id = "group_twins_reset",
				type = "group",
				sub_widgets = {
					{
						setting_id = "tw_reset_defaults",
						type = "button",
						button_text = "tw_reset_defaults_button",
						-- destructive: the button has to be held, the framework shows the progress
						button_trigger = "held",
						button_hold_duration = 1.5,
						tooltip = "tw_reset_defaults_tooltip",
						function_name = "tw_reset_to_defaults",
					},
				},
			},
		},
	},
}
