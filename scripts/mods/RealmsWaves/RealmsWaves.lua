-- RealmsWaves: random enemy waves for Realms (LAN) sessions.
-- Architecture and rationale: docs/04-design-and-rationale.md.
-- Host = authority (spawning, timing, tally). Clients render and vote.
local mod = get_mod("RealmsWaves")

local BASE = "RealmsWaves/scripts/mods/RealmsWaves"

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
	RW.votes = mod:io_dofile(BASE .. "/core/votes")
	RW.positions = mod:io_dofile(BASE .. "/spawn/positions")
	RW.bypass = mod:io_dofile(BASE .. "/spawn/budget_bypass")
	RW.execute = mod:io_dofile(BASE .. "/spawn/execute")
	RW.protocol = mod:io_dofile(BASE .. "/core/protocol")
	RW.director = mod:io_dofile(BASE .. "/core/director")

	RW.execute.init({ positions = RW.positions, bypass = RW.bypass })
	RW.director.init({
		events = RW.events,
		groups = RW.groups,
		protocol = RW.protocol,
		execute = RW.execute,
		votes = RW.votes,
		positions = RW.positions,
	})

	RW.bypass.install()

	local Director = RW.director

	RW.protocol.init({
		on_hello = Director.on_hello,
		on_welcome = Director.on_welcome,
		on_state = Director.on_state,
		on_vote = Director.on_vote,
		on_peer_joined = Director.on_peer_joined,
		on_peer_left = Director.on_peer_left,
	})

	-- Same "first objective started" signal RealmsEvent uses to begin its rolls.
	Managers.event:register(mod, "event_mission_objective_start", "_on_mission_objective_start")
end

mod._on_mission_objective_start = function ()
	if RW.director then
		RW.director.on_mission_started()
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

mod:command("rw_start", "RealmsWaves: (host) start the wave cycle now, e.g. after a hot reload", function ()
	mod:echo("RealmsWaves: %s", RW.director.force_start() and "cycle started" or "not started (host in a mission only)")
end)

mod:command("rw_skip", "RealmsWaves: (host) skip the countdown and resolve the current wave now", function ()
	RW.director.skip()
end)

mod:command("rw_test", "RealmsWaves: (host) spawn a wave now: /rw_test <event key or custom_N>", function (key)
	if not key then
		local keys = {}

		for i = 1, #RW.events.STANDARD do
			keys[#keys + 1] = RW.events.STANDARD[i].key
		end

		mod:echo("RealmsWaves: usage /rw_test <key>. Keys: %s, custom_1..custom_%d", table.concat(keys, ", "), RW.events.CUSTOM_SLOTS)

		return
	end

	local ok, err = RW.director.fire_now(key)

	mod:echo("RealmsWaves: %s", ok and ("wave " .. key .. " queued") or tostring(err))
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

	local recipe = table.concat({ ... }, " ")

	if recipe == "" then
		mod:echo("RealmsWaves: custom_%d = %q (chance %s%%)", slot, tostring(mod:get("custom_" .. slot .. "_recipe") or ""), tostring(mod:get("custom_" .. slot .. "_pct") or 0))

		return
	end

	local parts, err = RW.groups.parse(recipe)

	if not parts then
		mod:echo("RealmsWaves: %s", err)

		return
	end

	mod:set("custom_" .. slot .. "_recipe", recipe)

	local summary = {}

	for i = 1, #parts do
		summary[#summary + 1] = parts[i].count .. " " .. parts[i].breed
	end

	mod:echo("RealmsWaves: custom_%d saved: %s. Set its chance in the mod options (0 = disabled).", slot, table.concat(summary, ", "))
end)
