-- GrandfathersTarot: random enemy waves for Realms (LAN) sessions.
-- Architecture and rationale: docs/04-design-and-rationale.md.
-- Host = authority (spawning, timing, tally). Clients render and vote.
local mod = get_mod("GrandfathersTarot")

local BASE = "GrandfathersTarot/scripts/mods/GrandfathersTarot"
local EDITOR_VIEW = "realms_waves_editor"

mod.rw = {}

local RW = mod.rw

-- The mod was called "RealmsWaves" until 2026-10-05 and DMF keeps a mod's settings under its name: the first time The
-- Grandfather's Tarot loads, every saved setting of the old name (the decks, cards, presets and options) is copied over, and the
-- old ones are left as they were. Keys are the same in both. Custom keybinds take effect from the next start of the game.
local OLD_NAME = "RealmsWaves"

RW.migrate_old_settings = function ()
	if mod:get("gt_settings_migrated") == true then
		return 0
	end

	local ok, all = pcall(function () return Application.user_setting("mods_settings") end)
	local old = ok and type(all) == "table" and all[OLD_NAME]
	local copied = 0

	if type(old) == "table" then
		for key, value in pairs(old) do
			mod:set(key, value)
			copied = copied + 1
		end
	end

	mod:set("gt_settings_migrated", true)

	if copied > 0 and mod.info then
		mod:info("GrandfathersTarot: %d settings of RealmsWaves copied (decks, presets, options)", copied)
	end

	return copied
end

do
	local ok, err = pcall(RW.migrate_old_settings)

	if not ok then
		mod:error("GrandfathersTarot: the settings of RealmsWaves could not be copied: %s", tostring(err))
	end
end

local function release_events()
	if RW.event_manager then
		pcall(RW.event_manager.unregister, RW.event_manager, mod, "event_mission_objective_start")
		pcall(RW.event_manager.unregister, RW.event_manager, mod, "event_player_died")
		RW.event_manager = nil
	end
end

local function register_events()
	local manager = Managers.event

	if manager and manager ~= RW.event_manager then
		release_events()
		RW.event_manager = manager
		manager:register(mod, "event_mission_objective_start", "_on_mission_objective_start")
		manager:register(mod, "event_player_died", "_on_player_died")
	end
end

-- Registered at load so DMF injects it whenever the HUD is built.
pcall(function ()
	mod:register_hud_element({
		class_name = "HudElementGrandfathersTarotPanel",
		filename = BASE .. "/ui/hud_element_waves",
		use_hud_scale = true,
		visibility_groups = { "alive", "dead", "communication_wheel", "tactical_overlay" },
	})
end)

-- The Nightmare's dread: a full-screen overlay when a Nightmare card is drawn (ui/hud_element_dread.lua). Not scaled with the HUD: it
-- covers the screen whatever the HUD scale.
pcall(function ()
	mod:register_hud_element({
		class_name = "HudElementGrandfathersTarotDread",
		filename = BASE .. "/ui/hud_element_dread",
		use_hud_scale = false,
		visibility_groups = { "alive", "dead", "communication_wheel", "tactical_overlay" },
	})
end)

-- Dream's sky: a full-screen overlay of light and clouds when a Dream card is drawn (ui/hud_element_dream.lua), Nightmare's opposite.
pcall(function ()
	mod:register_hud_element({
		class_name = "HudElementGrandfathersTarotDream",
		filename = BASE .. "/ui/hud_element_dream",
		use_hud_scale = false,
		visibility_groups = { "alive", "dead", "communication_wheel", "tactical_overlay" },
	})
end)

-- The window of the last fulfilled card: its own element, so custom_hud moves it on its own.
pcall(function ()
	mod:register_hud_element({
		class_name = "HudElementGrandfathersTarotLast",
		filename = BASE .. "/ui/hud_element_last_card",
		use_hud_scale = true,
		visibility_groups = { "alive", "dead", "communication_wheel", "tactical_overlay" },
	})
end)

-- The Nightmare's grey world (ui/hud_element_dread.lua): the game drops the "last wound" mood every frame when the player is not on
-- their last wound; while the dread lasts it is kept on.
pcall(function ()
	mod:hook("PlayerUnitMoodExtension", "_remove_mood", function (func, self, t, mood_type, ...)
		if mood_type == "last_wound" and RW.dread_active then
			return
		end

		return func(self, t, mood_type, ...)
	end)
end)

-- Instant rescue's golden health (2026-10-05, the user: "while the team has a charge of Instant rescue and a player more than one
-- wound, their health is golden, like golden toughness"): the player panels (own and team) draw their health segments in the
-- game's overshield toughness colour (UIHudSettings.color_tint_10) while a charge is armed and the panel's player has more than
-- one wound left. The colour the panel normally uses is swapped only for the draw. Each panel class is hooked (class() copies the
-- base's methods into a subclass, so a hook on the base does not reach it).
RW.golden_health = function (panel)
	local effects = RW.effects
	local charges = effects and effects.team_rescues and effects.team_rescues() or 0

	if charges <= 0 or panel._dead or panel._knocked_down or panel._hogtied then
		return false
	end

	-- wounds left = the segments corruption (permanent damage) has not taken, as the game counts them (Health.calculate_num_segments);
	-- the health still in them does not matter (2026-10-05: a player low on health with three wounds lost the gold)
	local wounds = (panel._health_max_fraction or 1) * (panel._health_max_wounds or 1)

	return wounds > 1 + 1e-6
end

local function golden_draw(func, self, ...)
	local golden = not RW.dead and select(2, pcall(RW.golden_health, self)) == true

	if not golden then
		return func(self, ...)
	end

	local Settings = require("scripts/settings/ui/ui_hud_settings")
	local normal = Settings.color_tint_main_1

	Settings.color_tint_main_1 = Settings.color_tint_10 or normal

	local ok, err = pcall(func, self, ...)

	Settings.color_tint_main_1 = normal

	if not ok then
		error(err)
	end
end

for _, name in ipairs({ "HudElementPlayerPanelBase", "HudElementPersonalPlayerPanel", "HudElementTeamPlayerPanel" }) do
	pcall(function ()
		mod:hook(name, "_draw_health_bar", golden_draw)
	end)
end

mod.on_all_mods_loaded = function ()
	-- once (2026-10-04): the longest card cooldown becomes 30 minutes for players who kept the old default of 10 saved; afterwards
	-- the option is theirs again
	-- once (2026-10-04): the Nightmare darkness option changed scale (30 is the old full strength): a saved 100 becomes 30
	if mod:get("nightmare_dark_v2_done") ~= true then
		if tonumber(mod:get("nightmare_fog_strength")) == 100 then mod:set("nightmare_fog_strength", 30) end
		mod:set("nightmare_dark_v2_done", true)
	end

	if mod:get("tarot_longest_30_done") ~= true then
		if (tonumber(mod:get("tarot_longest")) or 10) < 30 then mod:set("tarot_longest", 30) end
		mod:set("tarot_longest_30_done", true)
	end

	RW.events = mod:io_dofile(BASE .. "/catalog/events")
	RW.groups = mod:io_dofile(BASE .. "/catalog/groups")
	RW.presets = mod:io_dofile(BASE .. "/catalog/presets")
	RW.colors = mod:io_dofile(BASE .. "/catalog/colors")
	RW.cards = mod:io_dofile(BASE .. "/catalog/cards")

	-- 2.0.0: the waves became tarot cards. Waves the user had named in the old way are renamed ONCE (and get their suit);
	-- the flag is stored first so a failure can never repeat it. A later rename by the user always stays.
	if mod:get("tarot_migrated") ~= true then
		mod:set("tarot_migrated", true)

		local ok, renamed = pcall(RW.cards.migrate, function (id) return mod:get(id) end, function (id, value) mod:set(id, value) end, RW.events, RW.groups)

		if ok and renamed and renamed > 0 then
			mod:echo("GrandfathersTarot 2.0: %d of your waves were renamed to their tarot cards.", renamed)
		end
	end

	-- Enemy name colours: the player's Spidey Sense colours when that mod is installed, else our palette by kind.
	RW.colors.init({
		kind = RW.groups.kind,
		option = function (id)
			return mod:get(id)
		end,
		spidey_setting = function (id)
			local spidey = get_mod("Spidey Sense")

			return spidey and spidey:get(id) or nil
		end,
		-- Improved Havoc Tags' colour options (nil when that mod is not installed: its defaults are used)
		havoc_setting = function (id)
			local tags = get_mod("ImprovedHavocTags")

			return tags and tags:get(id) or nil
		end,
		named = function (name)
			local make = Color and Color[name]

			if type(make) ~= "function" then
				return nil
			end

			local rgba = make(255, true)

			return rgba and { rgba[2], rgba[3], rgba[4] } or nil
		end,
	})
	RW.votes = mod:io_dofile(BASE .. "/core/votes")
	RW.positions = mod:io_dofile(BASE .. "/spawn/positions")
	RW.bypass = mod:io_dofile(BASE .. "/spawn/budget_bypass")
	RW.effects = mod:io_dofile(BASE .. "/core/effects")
	RW.sounds = mod:io_dofile(BASE .. "/catalog/sounds")
	RW.execute = mod:io_dofile(BASE .. "/spawn/execute")
	RW.tuning = mod:io_dofile(BASE .. "/spawn/tuning")
	RW.protocol = mod:io_dofile(BASE .. "/core/protocol")
	RW.appearance = mod:io_dofile(BASE .. "/spawn/appearance")
	RW.director = mod:io_dofile(BASE .. "/core/director")

	RW.tuning.init({ protocol = RW.protocol })
	RW.tuning.install()
	RW.appearance.init({ schema = RW.groups.Appearance, protocol = RW.protocol })
	RW.appearance.install()
	RW.execute.init({ positions = RW.positions, bypass = RW.bypass, groups = RW.groups, tuning = RW.tuning, appearance = RW.appearance, effects = RW.effects })
	RW.director.init({
		events = RW.events,
		groups = RW.groups,
		protocol = RW.protocol,
		execute = RW.execute,
		votes = RW.votes,
		positions = RW.positions,
		presets = RW.presets,
		cards = RW.cards,
		effects = RW.effects,
		tuning = RW.tuning,
	})

	RW.bypass.install()

	-- Typing in the editor's text boxes must not trigger any mod's keybind (e.g. "i" opening the
	-- inventory through hub_hotkey_menus, F-keys, this mod's own vote/editor keys). DMF evaluates all
	-- keybinds from the raw keyboard in dmf.check_keybinds() every frame, without any notion of text
	-- input, so skip that call while one of the editor's popups is open (flag set by the popup).
	local dmf_mod = get_mod("DMF")

	if dmf_mod and type(dmf_mod.check_keybinds) == "function" then
		mod:hook(dmf_mod, "check_keybinds", function (func, ...)
			if RW.text_input_active and not RW.dead then
				return
			end

			return func(...)
		end)
	end

	local Director = RW.director

	RW.protocol.init({
		on_hello = Director.on_hello,
		on_welcome = Director.on_welcome,
		on_state = Director.on_state,
		on_vote = Director.on_vote,
		on_waves = Director.on_waves,
		on_scale = Director.on_scale,
		on_appearance = function (_, entries)
			if not RW.dead and not RW.disabled and not Director.is_host() then RW.appearance.receive(entries) end
		end,
		on_peer_joined = Director.on_peer_joined,
		on_peer_left = Director.on_peer_left,
	})

	-- Same "first objective started" signal RealmsEvent uses to begin its rolls.
	register_events()

	-- Wave editor view (structure copied from RealmsEvent's editor registration).
	local UISoundEvents = require("scripts/settings/ui/ui_sound_events")
	local WwiseGameSyncSettings = require("scripts/settings/wwise_game_sync/wwise_game_sync_settings")

	mod:add_require_path(BASE .. "/ui/wave_editor_view")
	mod:register_view({
		view_name = EDITOR_VIEW,
		view_settings = {
			package = { "packages/ui/views/inventory_view/inventory_view" },
			init_view_function = function ()
				return true
			end,
			state_bound = true,
			path = BASE .. "/ui/wave_editor_view",
			class = "GrandfathersTarotView",
			disable_game_world = false,
			load_always = true,
			load_in_hub = true,
			game_world_blur = 1.1,
			enter_sound_events = { UISoundEvents.system_menu_enter },
			exit_sound_events = { UISoundEvents.system_menu_exit },
			wwise_states = { options = WwiseGameSyncSettings.state_groups.options.ingame_menu },
		},
		view_transitions = {},
		view_options = {
			close_all = false,
			close_previous = false,
			close_transition_time = nil,
			transition_time = nil,
		},
	})
	if RW.director.is_host() then RW.protocol.request_appearance_sync() end
end

-- Toggle the wave editor (keybind in the mod options, or /gt_editor).
mod.open_editor = function ()
	if not Managers.ui then
		return
	end

	if Managers.ui:view_instance(EDITOR_VIEW) then
		Managers.ui:close_view(EDITOR_VIEW)
	else
		Managers.ui:open_view(EDITOR_VIEW, nil, nil, nil, nil, {})
	end
end

-- Release subscriptions from their original owner; DMF removes hooks on reload.
-- Retirement also protects callbacks already captured by an in-flight dispatch.
mod.on_unload = function ()
	if RW.appearance then RW.appearance.retire() end
	RW.dead = true
	RW.text_input_active = false

	release_events()

	if RW.bypass then
		RW.bypass.retire()
	end

	if RW.tuning then
		RW.tuning.retire()
	end

	if RW.protocol then
		RW.protocol.retire()
	end

	if RW.execute then
		RW.execute.reset()
	end

	if RW.director then
		RW.director.reset()
	end
end

mod._on_mission_objective_start = function ()
	if RW.director and not RW.dead and not RW.disabled then
		RW.director.on_mission_started()
	end
end

mod._on_player_died = function ()
	if RW.director and not RW.dead and not RW.disabled then
		pcall(RW.director.on_player_died)
	end
end

mod.on_game_state_changed = function (status, state_name)
	if state_name ~= "GameplayStateRun" or not RW.director or RW.dead then
		return
	end

	if status == "enter" then
		if RW.appearance then RW.appearance.reset() end
		if RW.protocol then RW.protocol.clear_appearance_session() end
		register_events()
		RW.director.on_enter_gameplay()
		if RW.director.is_host() then RW.protocol.request_appearance_sync() end
	else
		if RW.appearance then RW.appearance.reset() end
		if RW.protocol then RW.protocol.clear_appearance_session() end
		RW.director.on_exit_gameplay()
	end
end

-- Disable cancels future work. Living units remain owned for re-enable; DMF
-- suspends their hooks while disabled. The host explicitly restarts with /gt_start.
mod.on_disabled = function ()
	if RW.dead then
		return
	end

	if RW.appearance then RW.appearance.reset(true) end
	if RW.protocol then RW.protocol.clear_appearance_session() end
	RW.disabled = true
	RW.text_input_active = false

	if RW.director then
		RW.director.stop()
	end

	if RW.execute then
		RW.execute.cancel()
	end

	if Managers.ui and Managers.ui.view_instance and Managers.ui.close_view then
		pcall(function ()
			if Managers.ui:view_instance(EDITOR_VIEW) then
				Managers.ui:close_view(EDITOR_VIEW)
			end
		end)
	end
end

mod.on_enabled = function (initial_call)
	if RW.dead then
		return
	end

	local was_disabled = RW.disabled
	RW.disabled = false

	if not initial_call and was_disabled and RW.director then
		if RW.director.is_host() then
			RW.director.stop()
		else
			-- Discard stale client state and re-handshake if already in a mission.
			RW.director.on_enter_gameplay()
		end

		RW.protocol.refresh_peers()
		if RW.director.is_host() then
			-- Refresh appearance epochs on clients after host disable/re-enable.
			RW.protocol.request_appearance_sync()
		end
	end
end

-- DMF calls mod.update(dt); accept the method-call form as well.
mod.update = function (...)
	local first, second = ...
	local dt = type(first) == "number" and first or second

	if RW.dead then
		return
	end

	if mod.is_enabled and not mod:is_enabled() then
		if not RW.disabled then
			mod.on_disabled()
		end

		if RW.bypass then
			RW.bypass.purge()
		end

		return
	end

	-- the second completion sound of a card follows the first everywhere, also in the editor's preview in the hub
	-- a client runs the effects update itself (the host's runs in the executor): the Specialists' outlines of a reveal are drawn by
	-- it on every machine (2026-10-04: they showed only for the host)
	if RW.effects and RW.effects.update and dt and RW.director and RW.director.is_host and not RW.director.is_host() then
		pcall(RW.effects.update, dt, false)
	end

	if RW.effects and RW.effects.tick_audio and dt then
		pcall(RW.effects.tick_audio, dt)
	end

	if RW.director and not RW.dead and dt then
		local ok, err = pcall(RW.director.update, dt)

		if not ok and not RW.update_failed then
			RW.update_failed = true

			mod:error("[update] failed: %s", tostring(err))
		end
		if RW.appearance then
			local applied, appearance_error = pcall(RW.appearance.update, dt)
			if not applied then mod:error("[appearance] %s", tostring(appearance_error)) end
		end
	end
end

-- ------------------------------------------------------------------ vote keys

local function vote(option)
	if not RW.director then
		return
	end

	local ok, reason = RW.director.local_vote(option)

	if not ok and reason then
		mod:echo("GrandfathersTarot: %s", reason)
	end
end

mod.vote_1 = function () vote(1) end
mod.vote_2 = function () vote(2) end
mod.vote_3 = function () vote(3) end
mod.vote_4 = function () vote(4) end
mod.vote_5 = function () vote(5) end

-- ------------------------------------------------------------------- commands

mod:command("gt_status", "GrandfathersTarot: print director state and spawn counters", function ()
	mod:echo(RW.director.status())

	local spawn_manager = Managers.state and Managers.state.minion_spawn

	if spawn_manager then
		mod:echo("GrandfathersTarot: director sees %d spawned / %d allocated (tracked wave units are hidden from both)", spawn_manager:num_spawned_minions(), spawn_manager:total_allocated_num_enemies())
	end
end)

-- /gt_anim: what the engine and the nearby wave units offer for the speed of an animation (see Tuning.probe)
mod:command("gt_anim", "GrandfathersTarot: report what the game offers to change an enemy's animation speed (spawn a wave first, then run this near it); the text is also in the console log", function ()
	local units = RW.bypass and RW.bypass.units(40) or {}
	local ok, lines = pcall(RW.tuning.probe, units)

	if not ok then
		mod:echo("GrandfathersTarot: the probe failed: %s", tostring(lines))

		return
	end

	for _, line in ipairs(lines) do
		mod:echo("GrandfathersTarot: %s", line)

		if mod.info then
			mod:info("GrandfathersTarot: %s", line)
		end
	end
end)

-- /gt_tune: what the custom stats of the living wave units are right now (for finding out why one does nothing)
mod:command("gt_tune", "GrandfathersTarot: report the custom stats (time between attacks, fire rate, burst...) of the wave units alive: what was written, what the stat says now, what the last shot read; also in the console log", function ()
	local ok, lines = pcall(RW.tuning.describe)

	if not ok then
		mod:echo("GrandfathersTarot: /gt_tune failed: %s", tostring(lines))

		return
	end

	for _, line in ipairs(lines) do
		mod:echo("GrandfathersTarot: %s", line)

		if mod.info then
			mod:info("GrandfathersTarot: %s", line)
		end
	end
end)

mod:command("gt_start", "GrandfathersTarot: (host) start the wave cycle now (also after /gt_stop), e.g. after a hot reload", function ()
	mod:echo("GrandfathersTarot: %s", RW.director.force_start() and "cycle started" or "not started (host in a mission only)")
end)

mod:command("gt_stop", "GrandfathersTarot: (host) stop the mod: no countdown, vote or timed waves until /gt_start (units already spawned stay)", function ()
	local ok, why = RW.director.stop()

	mod:echo("GrandfathersTarot: %s", ok and "stopped. Use /gt_start to start again" or tostring(why))
end)

mod:command("gt_pause", "GrandfathersTarot: (host) freeze / release every wave timer: /gt_pause [on|off]", function (arg)
	local on

	if arg == "on" then
		on = true
	elseif arg == "off" then
		on = false
	end

	local state, why = RW.director.pause(on)

	mod:echo("GrandfathersTarot: %s", state == nil and tostring(why) or (state and "paused: all wave timers are frozen" or "released: the timers run again"))
end)

mod:command("gt_next", "GrandfathersTarot: (host) drop the current wave WITHOUT spawning it and start a new one (new draw, full timer)", function ()
	local ok, why = RW.director.next_wave()

	mod:echo("GrandfathersTarot: %s", ok and "new wave drawn" or tostring(why))
end)

mod:command("gt_skip", "GrandfathersTarot: (host) skip the countdown and resolve the current wave now", function ()
	RW.director.skip()
end)

-- /gt_test <wave key or wave name>: "custom_1", "hound_frenzy", or a name from the editor
-- ("Mutants Everywhere" can be typed mutants_everywhere or with spaces). /gt_test_close is the same wave right in front of you.
local function test_command(close, ...)
	local query = table.concat({ ... }, " ")
	local command = close and "gt_test_close" or "gt_test"

	if query:match("^%s*$") then
		local names = {}

		for _, key in ipairs(RW.events.keys()) do
			local wave = RW.events.get(key, function (id) return mod:get(id) end, RW.groups)

			if wave and wave.parts and #wave.parts > 0 then
				names[#names + 1] = string.format("%s (%s)", wave.name, wave.key)
			end
		end

		mod:echo("GrandfathersTarot: usage /%s <wave name or key>. Waves: %s", command, table.concat(names, ", "))

		return
	end

	local ok, note = RW.director.fire_now(query, { close = close })

	if ok then
		mod:echo("GrandfathersTarot: wave \"%s\" queued%s", query, note and (" - " .. note) or "")
	else
		mod:echo("GrandfathersTarot: %s", tostring(note))
	end
end

mod:command("gt_test", "GrandfathersTarot: (host) a wave now (its sound first, then the enemies): /gt_test <wave key or wave name>, e.g. /gt_test mutants_everywhere", function (...)
	test_command(false, ...)
end)

mod:command("gt_test_close", "GrandfathersTarot: (host) spawn a wave right in front of you, facing you: /gt_test_close <wave key or wave name>, e.g. /gt_test_close the_devil", function (...)
	test_command(true, ...)
end)

-- /gt_drawtest and /gt_fulltest: a staged draw of three cards that picks the named one after 3 seconds (core/director.lua)
local function stage_command(full, ...)
	local query = table.concat({ ... }, " ")
	local command = full and "gt_fulltest" or "gt_drawtest"

	if query:match("^%s*$") then
		mod:echo("GrandfathersTarot: usage /%s <card name or key>", command)

		return
	end

	local ok, note = RW.director.stage_draw(query, full)

	if ok then
		mod:echo("GrandfathersTarot: staged draw: \"%s\" is picked in 3 s%s", tostring(note), full and " (its sound plays, then its wave spawns)" or " (no sound, no enemies)")
	else
		mod:echo("GrandfathersTarot: %s", tostring(note))
	end
end

mod:command("gt_drawtest", "GrandfathersTarot: (host) a fake draw of three cards that picks the named card after 3 s, to see the HUD; no sound, no enemies: /gt_drawtest <card name or key>", function (...)
	stage_command(false, ...)
end)

mod:command("gt_fulltest", "GrandfathersTarot: (host) the same fake draw, then the card's sound and its wave, as in play: /gt_fulltest <card name or key>", function (...)
	stage_command(true, ...)
end)

mod:command("gt_vote", "GrandfathersTarot: cast a vote from the console: /gt_vote <option number>", function (option)
	vote(tonumber(option) or 0)
end)

mod:command("gt_roll", "GrandfathersTarot: simulate N weighted rolls to check the percentages: /gt_roll [n]", function (n)
	n = math.max(1, math.min(100000, tonumber(n) or 1000))

	local pool, counts, total = RW.director.simulate(n)

	if #pool == 0 then
		mod:echo("GrandfathersTarot: no event enabled")

		return
	end

	mod:echo("GrandfathersTarot: %d rolls over %d enabled events (raw weight total %.1f)", n, #pool, total)

	for i = 1, #pool do
		mod:echo("  %s: expected %.1f%%, got %.1f%%", pool[i].key, pool[i].pct, counts[pool[i].key] / n * 100)
	end
end)

mod:command("gt_custom", "GrandfathersTarot: set a custom wave: /gt_custom <slot number of a custom card, 1 to 88> <recipe, e.g. 5 trappers, 5 mutants, 10 hounds>", function (slot, ...)
	slot = tonumber(slot)

	if not slot or slot < 1 or slot > RW.events.CUSTOM_SLOTS or slot ~= math.floor(slot) then
		mod:echo("GrandfathersTarot: slot must be 1-%d", RW.events.CUSTOM_SLOTS)

		return
	end

	local key = "custom_" .. slot
	local recipe = table.concat({ ... }, " ")
	local wave = RW.events.get(key, function (id) return mod:get(id) end, RW.groups)

	if recipe == "" then
		mod:echo("GrandfathersTarot: %s = %q, %s, chance %s, %s", key, wave.name, wave.parts and RW.groups.summary(wave.parts) or "(empty)", tostring(wave.pct), wave.enabled and "enabled" or "disabled")

		return
	end

	local parts, err = RW.groups.parse(recipe)

	if not parts then
		mod:echo("GrandfathersTarot: %s", err)

		return
	end

	RW.events.set_def(function (id, value) mod:set(id, value) end, key, wave.name, parts, RW.groups)
	mod:set("on_" .. key, true)
	mod:echo("GrandfathersTarot: %s saved and enabled: %s (chance %s; change name, chance and more in the wave editor, /gt_editor)", key, RW.groups.summary(parts), tostring(wave.pct))
end)

mod:command("gt_editor", "GrandfathersTarot: open the wave editor (same as the editor keybind)", function ()
	mod.open_editor()
end)
