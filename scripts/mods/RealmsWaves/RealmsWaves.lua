-- RealmsWaves: random enemy waves for Realms (LAN) sessions.
-- Architecture and rationale: docs/04-design-and-rationale.md.
-- Host = authority (spawning, timing, tally). Clients render and vote.
local mod = get_mod("RealmsWaves")

local BASE = "RealmsWaves/scripts/mods/RealmsWaves"
local EDITOR_VIEW = "realms_waves_editor"

mod.rw = {}

local RW = mod.rw

-- Registered at load so DMF injects it whenever the HUD is built.
pcall(function ()
	mod:register_hud_element({
		class_name = "HudElementRealmsWavesPanel",
		filename = BASE .. "/ui/hud_element_waves",
		use_hud_scale = true,
		visibility_groups = { "alive", "dead", "communication_wheel", "tactical_overlay" },
	})
end)

mod.on_all_mods_loaded = function ()
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
			mod:echo("RealmsWaves 2.0: %d of your waves were renamed to their tarot cards.", renamed)
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
	RW.execute = mod:io_dofile(BASE .. "/spawn/execute")
	RW.protocol = mod:io_dofile(BASE .. "/core/protocol")
	RW.director = mod:io_dofile(BASE .. "/core/director")

	RW.execute.init({ positions = RW.positions, bypass = RW.bypass, groups = RW.groups })
	RW.director.init({
		events = RW.events,
		groups = RW.groups,
		protocol = RW.protocol,
		execute = RW.execute,
		votes = RW.votes,
		positions = RW.positions,
		presets = RW.presets,
		cards = RW.cards,
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
		on_peer_joined = Director.on_peer_joined,
		on_peer_left = Director.on_peer_left,
	})

	-- Same "first objective started" signal RealmsEvent uses to begin its rolls.
	Managers.event:register(mod, "event_mission_objective_start", "_on_mission_objective_start")

	-- fired by PlayerDeath.die (utilities/player_death.lua:45) on the host: used by the anti-snowball option
	Managers.event:register(mod, "event_player_died", "_on_player_died")

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
			class = "RealmsWavesView",
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
end

-- Toggle the wave editor (keybind in the mod options, or /rw_editor).
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

-- On a mod reload (or game exit): stop this instance's hooks from acting (DMF cannot remove
-- them) and release everything it holds, so reloads do not stack behaviour or pin memory.
mod.on_unload = function ()
	-- the keybind-suppression hook of this instance stays in DMF's chain after a reload: never let it block
	RW.dead = true
	RW.text_input_active = false

	if RW.bypass then
		RW.bypass.retire()
	end

	if RW.execute then
		RW.execute.reset()
	end

	if RW.director then
		RW.director.reset()
	end
end

mod._on_mission_objective_start = function ()
	if RW.director then
		RW.director.on_mission_started()
	end
end

mod._on_player_died = function ()
	if RW.director and not RW.dead then
		pcall(RW.director.on_player_died)
	end
end

mod.on_game_state_changed = function (status, state_name)
	if state_name ~= "GameplayStateRun" or not RW.director then
		return
	end

	if status == "enter" then
		RW.director.on_enter_gameplay()
	else
		RW.director.on_exit_gameplay()
	end
end

-- DMF calls mod.update(dt); accept the method-call form as well.
mod.update = function (...)
	local first, second = ...
	local dt = type(first) == "number" and first or second

	if RW.director and dt then
		local ok, err = pcall(RW.director.update, dt)

		if not ok and not RW.update_failed then
			RW.update_failed = true

			mod:error("[update] failed: %s", tostring(err))
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
		mod:echo("RealmsWaves: %s", reason)
	end
end

mod.vote_1 = function () vote(1) end
mod.vote_2 = function () vote(2) end
mod.vote_3 = function () vote(3) end
mod.vote_4 = function () vote(4) end
mod.vote_5 = function () vote(5) end

-- ------------------------------------------------------------------- commands

mod:command("rw_status", "RealmsWaves: print director state and spawn counters", function ()
	mod:echo(RW.director.status())

	local spawn_manager = Managers.state and Managers.state.minion_spawn

	if spawn_manager then
		mod:echo("RealmsWaves: director sees %d spawned / %d allocated (tracked wave units are hidden from both)", spawn_manager:num_spawned_minions(), spawn_manager:total_allocated_num_enemies())
	end
end)

mod:command("rw_start", "RealmsWaves: (host) start the wave cycle now (also after /rw_stop), e.g. after a hot reload", function ()
	mod:echo("RealmsWaves: %s", RW.director.force_start() and "cycle started" or "not started (host in a mission only)")
end)

mod:command("rw_stop", "RealmsWaves: (host) stop the mod: no countdown, vote or timed waves until /rw_start (units already spawned stay)", function ()
	local ok, why = RW.director.stop()

	mod:echo("RealmsWaves: %s", ok and "stopped. Use /rw_start to start again" or tostring(why))
end)

mod:command("rw_pause", "RealmsWaves: (host) freeze / release every wave timer: /rw_pause [on|off]", function (arg)
	local on

	if arg == "on" then
		on = true
	elseif arg == "off" then
		on = false
	end

	local state, why = RW.director.pause(on)

	mod:echo("RealmsWaves: %s", state == nil and tostring(why) or (state and "paused: all wave timers are frozen" or "released: the timers run again"))
end)

mod:command("rw_next", "RealmsWaves: (host) drop the current wave WITHOUT spawning it and start a new one (new draw, full timer)", function ()
	local ok, why = RW.director.next_wave()

	mod:echo("RealmsWaves: %s", ok and "new wave drawn" or tostring(why))
end)

mod:command("rw_skip", "RealmsWaves: (host) skip the countdown and resolve the current wave now", function ()
	RW.director.skip()
end)

-- /rw_test <wave key or wave name>: "custom_1", "hound_frenzy", or a name from the editor
-- ("Mutants Everywhere" can be typed mutants_everywhere or with spaces).
mod:command("rw_test", "RealmsWaves: (host) spawn a wave now: /rw_test <wave key or wave name>, e.g. /rw_test mutants_everywhere", function (...)
	local query = table.concat({ ... }, " ")

	if query:match("^%s*$") then
		local names = {}

		for _, key in ipairs(RW.events.keys()) do
			local wave = RW.events.get(key, function (id) return mod:get(id) end, RW.groups)

			if wave and wave.parts and #wave.parts > 0 then
				names[#names + 1] = string.format("%s (%s)", wave.name, wave.key)
			end
		end

		mod:echo("RealmsWaves: usage /rw_test <wave name or key>. Waves: %s", table.concat(names, ", "))

		return
	end

	local ok, note = RW.director.fire_now(query)

	if ok then
		mod:echo("RealmsWaves: wave \"%s\" queued%s", query, note and (" - " .. note) or "")
	else
		mod:echo("RealmsWaves: %s", tostring(note))
	end
end)

mod:command("rw_vote", "RealmsWaves: cast a vote from the console: /rw_vote <option number>", function (option)
	vote(tonumber(option) or 0)
end)

mod:command("rw_roll", "RealmsWaves: simulate N weighted rolls to check the percentages: /rw_roll [n]", function (n)
	n = math.max(1, math.min(100000, tonumber(n) or 1000))

	local pool, counts, total = RW.director.simulate(n)

	if #pool == 0 then
		mod:echo("RealmsWaves: no event enabled")

		return
	end

	mod:echo("RealmsWaves: %d rolls over %d enabled events (raw weight total %.1f)", n, #pool, total)

	for i = 1, #pool do
		mod:echo("  %s: expected %.1f%%, got %.1f%%", pool[i].key, pool[i].pct, counts[pool[i].key] / n * 100)
	end
end)

mod:command("rw_custom", "RealmsWaves: set a custom wave: /rw_custom <slot 1-20> <recipe, e.g. 5 trappers, 5 mutants, 10 hounds>", function (slot, ...)
	slot = tonumber(slot)

	if not slot or slot < 1 or slot > RW.events.CUSTOM_SLOTS or slot ~= math.floor(slot) then
		mod:echo("RealmsWaves: slot must be 1-%d", RW.events.CUSTOM_SLOTS)

		return
	end

	local key = "custom_" .. slot
	local recipe = table.concat({ ... }, " ")
	local wave = RW.events.get(key, function (id) return mod:get(id) end, RW.groups)

	if recipe == "" then
		mod:echo("RealmsWaves: %s = %q, %s, chance %s, %s", key, wave.name, wave.parts and RW.groups.summary(wave.parts) or "(empty)", tostring(wave.pct), wave.enabled and "enabled" or "disabled")

		return
	end

	local parts, err = RW.groups.parse(recipe)

	if not parts then
		mod:echo("RealmsWaves: %s", err)

		return
	end

	RW.events.set_def(function (id, value) mod:set(id, value) end, key, wave.name, parts, RW.groups)
	mod:set("on_" .. key, true)
	mod:echo("RealmsWaves: %s saved and enabled: %s (chance %s; change name, chance and more in the wave editor, /rw_editor)", key, RW.groups.summary(parts), tostring(wave.pct))
end)

mod:command("rw_editor", "RealmsWaves: open the wave editor (same as the editor keybind)", function ()
	mod.open_editor()
end)
