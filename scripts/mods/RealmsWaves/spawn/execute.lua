-- Host-only wave spawner.
--
-- A wave is expanded into a shuffled queue of breed names and drip-fed a few
-- units at a time (the game's own spawn queue is a 256-entry ring buffer with
-- no overflow guard, so we never hand it more than a couple per tick). Units are
-- spawned directly with MinionSpawnManager:spawn_minion, which has no limit
-- checks, and tracked by spawn/budget_bypass so the director ignores them.
local mod = get_mod("RealmsWaves")

-- NOT a global: it must be required (using it bare raised "attempt to index global 'FixedFrame'"
-- after the first modifier was applied to a unit)
local FixedFrame = require("scripts/utilities/fixed_frame")

local Execute = {}

local Positions, Bypass, Groups, Tuning, Appearance, Effects

local FEED_INTERVAL = 0.15
local FEED_BATCH = 2
local CLOSE_SPREAD = 2 -- a wave in front of the player (/rw_test_close) never scatters wider than this, whatever its own radius
local CANDIDATE_TTL = 1.5
local FAILED_SEARCH_TTL = 1.5 -- do not repeat a failed hidden-position search more often than this
local JOB_TIMEOUT = 60 -- seconds a wave may stay unfinished (repeating waves add their repeat time)
local MAX_QUEUE = 1000 -- a repeat tick is skipped while this many units are still waiting
local MAX_JOBS = 64
local MAX_PENDING = 8000 -- aggregate entries; independent of the alive-unit cap
local PURGE_INTERVAL = 5

local jobs = {}
local feed_timer = 0
local purge_timer = 0
local clock = 0
local cache = {}
local last_log = {}

local function queued_count()
	local count = 0

	for i = 1, #jobs do
		count = count + #jobs[i].queue
	end

	return count
end

local function number_setting(id, fallback)
	local value = tonumber(mod:get(id))

	if not value or value ~= value then
		return fallback
	end

	return value
end

local function throttled_log(channel, message)
	if not mod:get("debug") then
		return
	end

	if last_log[channel] and clock - last_log[channel] < 5 then
		return
	end

	last_log[channel] = clock

	mod:echo("RealmsWaves [%s] %s", channel, tostring(message))
end

Execute.init = function (deps)
	Positions = deps.positions
	Bypass = deps.bypass
	Groups = deps.groups
	Tuning = deps.tuning
	Appearance = deps.appearance
	Effects = deps.effects
end

local warned = {}

-- Modifier problems are always logged (once per distinct message), not only in debug mode.
local function warn_once(message)
	if not warned[message] then
		warned[message] = true

		mod:warning("RealmsWaves: %s", message)
	end
end

local function in_havoc_mission()
	local manager = Managers.state and Managers.state.game_mode
	local game_mode = manager and manager:game_mode()

	return game_mode ~= nil and game_mode:extension("havoc") ~= nil
end

-- ---------------------------------------------------------- modifier setup steps ("prepare")
-- Purple stimm: the buff's death effect needs Managers.state.mutator:mutator("mutator_stimmed_minions_purple")
-- (it queues the two split-off enemies through that mutator's add_split_spawn). No mutator template with
-- that name exists in the game, so nobody loads it. We create the mutator class ourselves (with the values
-- the mutator manager already holds) and register it in the manager's table, where the manager also calls
-- its update() every frame. The manager is rebuilt each mission, so this happens once per mission.
-- Returns true when the mutator is available, otherwise false and a reason (the buff is then NOT added,
-- because without it the buff would raise an error when the enemy dies).
local PURPLE_MUTATOR_NAME = "mutator_stimmed_minions_purple"
local PURPLE_MUTATOR_CLASS = "scripts/managers/mutator/mutators/mutator_purple_stimmed"

local function ensure_purple_stimm()
	local manager = Managers.state and Managers.state.mutator

	if not manager then
		return false, "no mutator manager (not in a mission)"
	end

	local mutators = manager:all_activated_mutators()

	if mutators[PURPLE_MUTATOR_NAME] then
		return true
	end

	local class_ok, class = pcall(require, PURPLE_MUTATOR_CLASS)

	if not class_ok or type(class) ~= "table" then
		return false, "could not load " .. PURPLE_MUTATOR_CLASS .. ": " .. tostring(class)
	end

	local new_ok, instance = pcall(function ()
		return class:new(manager._is_server, manager._network_event_delegate, {}, manager._nav_world, manager._world, manager._level_seed)
	end)

	if not new_ok or not instance then
		return false, "could not create the split spawner: " .. tostring(instance)
	end

	mutators[PURPLE_MUTATOR_NAME] = instance

	return true
end

local PREPARE_STEPS = { purple_stimm = ensure_purple_stimm }

Execute.ensure_purple_stimm = ensure_purple_stimm

-- Adds a modifier's buff templates to a freshly spawned unit, the way
-- MutatorBase._add_buffs_on_unit does (S\managers\mutator\mutators\mutator_base.lua:100-135).
-- Server side; minion buffs are synced to clients by the buff extension.
-- Every step is guarded: a buff that errors must never break the wave.
-- `breed_name` (optional) lets a modifier that only suits some breeds (`only_breeds`) skip the others.
Execute.apply_modifiers = function (unit, mod_ids, breed_name)
	local buff_extension = ScriptUnit.has_extension(unit, "buff_system")

	if not buff_extension or not mod_ids then
		return
	end

	local t = Managers.time:time("gameplay")

	for i = 1, #mod_ids do
		local modifier = Groups.modifier(mod_ids[i])

		if modifier and modifier.requires_havoc and not in_havoc_mission() then
			warn_once(modifier.name .. " needs a Havoc mission and was skipped")
		elseif modifier and modifier.only_breeds and breed_name and not modifier.only_breeds[breed_name] then
			warn_once(string.format("%s only works on %s, skipped on %s", modifier.name, Groups.only_breeds_text(modifier), Groups.display_name(breed_name)))
		elseif modifier and modifier.skip_if_present and modifier.buffs[1] and buff_extension.has_buff_using_buff_template and select(2, pcall(buff_extension.has_buff_using_buff_template, buff_extension, modifier.buffs[1])) == true then
			-- the mission's own mutator already gave it (a second copy would double its effects)
		elseif modifier and modifier.prepare and not PREPARE_STEPS[modifier.prepare] then
			warn_once(modifier.name .. " has an unknown setup step and was skipped")
		elseif modifier then
			local ready, why = true, nil

			if modifier.prepare then
				local step_ok, first, second = pcall(PREPARE_STEPS[modifier.prepare])

				ready = step_ok and first == true
				why = step_ok and second or first
			end

			if not ready then
				warn_once(string.format("%s was skipped, its setup failed: %s", modifier.name, tostring(why)))
			end

			for j = 1, ready and #modifier.buffs or 0 do
				local buff_name = modifier.buffs[j]
				local ok, err = pcall(function ()
					if buff_extension.is_valid_target and not buff_extension:is_valid_target(buff_name) then
						return
					end

					buff_extension:add_internally_controlled_buff(buff_name, t)
				end)

				if not ok then
					warn_once(string.format("modifier %s (buff %s) failed: %s", modifier.name, buff_name, tostring(err)))
				end
			end
		end
	end

	pcall(buff_extension._update_stat_buffs_and_keywords, buff_extension, FixedFrame.get_latest_fixed_time())
end

-- ------------------------------------------------------------------- Lua memory guard
-- The game's Lua heap is a fixed 1 GB ("Not enough memory reserved for heap 'lua_heap'").
-- Every spawned minion adds Lua-side state, and other mods and hot reloads eat into the same
-- heap, so a big wave can be the last straw. Above the configured size the mod stops spawning
-- (units stay queued, new waves are refused) and, at most every 15 s, forces a full garbage
-- collection first, since much of a high reading is garbage that has not been collected yet.
local GC_COOLDOWN = 15
local last_full_gc = -math.huge
local heap_paused = false

local function heap_mb()
	return collectgarbage("count") / 1024
end

Execute.heap_mb = heap_mb

-- true while spawning must pause because the Lua heap is above the guard
local function over_heap_guard()
	local limit = number_setting("heap_guard_mb", 800)
	local mb = heap_mb()

	if mb <= limit then
		heap_paused = false

		return false
	end

	if clock - last_full_gc >= GC_COOLDOWN then
		last_full_gc = clock
		collectgarbage("collect")
		mb = heap_mb()

		if mb <= limit then
			heap_paused = false

			return false
		end
	end

	if not heap_paused then
		heap_paused = true

		mod:warning("RealmsWaves: wave spawning paused, the Lua heap is %.0f MB (guard %d MB, hard limit 1024 MB). It resumes when memory drops; raise or lower the guard in the mod options.", mb, limit)
	end

	return true
end

Execute.over_heap_guard = over_heap_guard

Execute.has_authority = function ()
	if (mod.rw and mod.rw.dead) or (mod.is_enabled and not mod:is_enabled()) then
		return false
	end

	local state = Managers.state
	local game_session = state and state.game_session

	return state ~= nil and state.minion_spawn ~= nil and game_session ~= nil and game_session:is_server() == true
end

local MULTIPLIER_SETTING = { normal = "mult_normal", boss = "mult_boss", special = "mult_special" }

-- Enemy-type multiplier from the mod options, in percent (0 to 500). A group with random
-- alternatives ("a|b") uses the type of its first alternative.
local function percent_for(part)
	local breed = part.one_of and part.one_of[1] or part.breed

	return math.max(0, number_setting(MULTIPLIER_SETTING[Groups.category(breed)], 100))
end

Execute.percent_for = percent_for

-- Scaled number of units, ALWAYS rounded down: 1 unit stays 1 until 200 percent (then 2),
-- 13 units at 150 percent is 19 (19.5 rounded down). The product is taken before dividing by
-- 100 (so 20 x 115 / 100 is exactly 23) and a tiny epsilon guards against float noise such as
-- 22.999999999999996.
local function scaled_amount(base, percent)
	return math.floor(base * percent / 100 + 1e-9)
end

Execute.scaled_amount = scaled_amount

-- The enemy of one unit of a group. A random group ("a|b|c") rolls for every unit, unless `picks` is given (the card keeps its first
-- roll, see def.keep_pick): then the group rolls ONCE, the first time a unit of it is needed, and every unit of it, in the first
-- batch and in every repeat tick, is that enemy.
local function breed_of(part, picks)
	local one_of = part.one_of

	if not one_of then
		return part.breed
	end

	if picks then
		local chosen = picks[part]

		if not chosen then
			chosen = one_of[math.random(1, #one_of)]
			picks[part] = chosen
		end

		return chosen
	end

	return one_of[math.random(1, #one_of)]
end

-- Units for one batch: `field` is "count" (the initial spawn) or "rep" (one repeat tick).
-- Each group's number is scaled by its type's multiplier (rounded down, see scaled_amount),
-- so 0 removes that type from the wave and 500 gives five times as many.
local function expand(parts, field, picks)
	local queue = {}
	local cap = number_setting("max_per_wave", 80)

	for i = 1, #parts do
		local part = parts[i]
		local base = field == "rep" and Groups.repeat_amount(part) or (part[field] or 0)
		local amount = scaled_amount(base, percent_for(part))

		for _ = 1, amount do
			queue[#queue + 1] = { breed = breed_of(part, picks), mods = part.mods, tune = part.tune, appearance = part.appearance }
		end
	end

	for i = #queue, 2, -1 do
		local j = math.random(1, i)

		queue[i], queue[j] = queue[j], queue[i]
	end

	while #queue > cap do
		queue[#queue] = nil
	end

	return queue
end

Execute.start_wave = function (def)
	if not Execute.has_authority() then
		return false, "no spawn authority"
	end

	if Groups.Effects.beneficial(def.suit) then def.parts = {} end
	def.parts = def.parts or {}
	local room = MAX_PENDING - queued_count()
	local needed = 0

	for i = 1, #def.parts do
		local part = def.parts[i]
		needed = needed + scaled_amount(part.count or 0, percent_for(part))
	end

	needed = math.min(needed, number_setting("max_per_wave", 80))

	-- Refuse the whole new wave before allocating its queue. Repeat-only jobs
	-- also need a job slot and some aggregate capacity to make eventual progress.
	if #jobs >= MAX_JOBS or room <= 0 or needed > room then
		return false, "pending-wave budget is full (64 jobs / 8000 units); wave skipped"
	end

	if over_heap_guard() then
		return false, string.format("the Lua memory guard refused this wave (heap %.0f MB is above the %d MB guard)", heap_mb(), number_setting("heap_guard_mb", 800))
	end

	-- a card keeps the first roll of its random groups unless it says not to (def.keep_pick == false)
	local picks = def.keep_pick ~= false and {} or nil
	local queue = expand(def.parts, "count", picks)
	local every = tonumber(def.rep_every) or 0
	local rep_for = tonumber(def.rep_for) or 0
	local has_repeat = Groups.has_repeat(def.parts) and every > 0 and rep_for > 0

	if #queue == 0 and not has_repeat and Groups.Effects.encode(def.effects) == "" then
		return false, (#(def.parts or {}) > 0) and "the enemy type multipliers (mod options) removed every enemy of this wave" or "empty wave"
	end

	-- Repeat ticks happen at every, 2*every, ... up to and including rep_for seconds.
	local rep

	if has_repeat then
		rep = { parts = def.parts, picks = picks, every = every, total = rep_for, clock = 0, next = every, done = every > rep_for }
	end

	if Effects then
		local ok, result = Effects.start(def)
		if not ok then return false, result end
	end

	jobs[#jobs + 1] = {
		name = def.name,
		test = def.test == true, -- explicit /rw_test: may fall back to a ring around the player where no hidden points exist
		close = def.close == true, -- /rw_test_close: right in front of the local player, facing them (no hidden points, no ring)
		monster = def.monster == true,
		spread = tonumber(def.spread) or 0,
		dmin = math.max(0, tonumber(def.dmin) or 0),
		dmax = math.max(0, tonumber(def.dmax) or 0),
		queue = queue,
		spawned = 0,
		age = 0,
		timeout = JOB_TIMEOUT + (has_repeat and rep_for or 0),
		rep = rep,
	}

	return true
end

-- Queues the units of every repeat tick that is due (a job can catch up several ticks in one frame).
local function run_repeats(job, dt)
	local rep = job.rep

	if not rep or rep.done then
		return
	end

	rep.clock = rep.clock + dt

	while rep.next <= rep.total and rep.clock >= rep.next do
		local room = math.min(MAX_QUEUE - #job.queue, MAX_PENDING - queued_count())

		if room <= 0 then
			-- Drop missed ticks in one step during a long frame; a full queue needs no more expansion work.
			rep.next = rep.next + (math.floor((math.min(rep.clock, rep.total) - rep.next) / rep.every) + 1) * rep.every

			break
		else
			local batch = expand(rep.parts, "rep", rep.picks)

			while #batch > room do
				batch[#batch] = nil
			end

			-- Reuse the batch as a new stack: pending older units stay at its end and are popped first.
			for i = 1, math.floor(#batch / 2) do
				local j = #batch - i + 1

				batch[i], batch[j] = batch[j], batch[i]
			end

			for i = 1, #job.queue do
				batch[#batch + 1] = job.queue[i]
			end

			job.queue = batch
		end

		rep.next = rep.next + rep.every
	end

	if rep.next > rep.total then
		rep.done = true
	end
end

-- Levels without a main path (Psykhanium, hub-like places) cannot give hidden spawn points.
local NO_MAIN_PATH = { ["main path not ready"] = true, ["no nav spawn points"] = true, ["no spawn groups"] = true }
local TEST_RING_MIN, TEST_RING_MAX = 10, 30
local NOTIFY_AFTER = 4 -- seconds a wave may wait for a spawn position before the reason is reported

-- Plain-language reason for a failed position search (shown to the user).
local function explain(reason)
	if NO_MAIN_PATH[reason] then
		return "this level has no spawn points (hub, Psykhanium...). Waves need a mission"
	elseif reason == "no hidden points near players" then
		return "no spot hidden from every player was found near the squad (open ground? try moving, or lower the minimum spawn distance in the options)"
	elseif reason == "hidden points exist but none within distance limits" then
		return "hidden spots exist but none inside the minimum/maximum spawn distance (see the options)"
	end

	return tostring(reason)
end

-- True on levels where waves can only use the test ring (no main path).
Execute.uses_ring = function ()
	local main_path = Managers.state and Managers.state.main_path

	return not (main_path and main_path.is_main_path_ready and main_path:is_main_path_ready())
end

-- Returns the candidate list for a job, or nil. Sets job.reason when it fails.
local function candidates_for(job)
	-- in front of the player: where they look right now, so never cached
	if job.close and Positions.close_candidates then
		local list, reason = Positions.close_candidates()

		job.reason = (not list) and reason or nil

		if not list then
			throttled_log("spawn", reason)
		end

		return list
	end

	-- waves with their own spawn distances must not share cached positions with the others
	local key = (job.test and "test_" or "") .. (job.monster and "monster" or "normal") .. ":" .. job.dmin .. ":" .. job.dmax
	local entry = cache[key]

	if entry and entry.list and clock - entry.at < CANDIDATE_TTL and #entry.list > 0 then
		job.reason = nil

		return entry.list
	end

	-- A failed search (no hidden point near the players) is remembered too. Without this the
	-- full occlusion query (up to ~27 nav groups, hundreds of points) reran on EVERY feed tick
	-- (every 0.15 s) for as long as the wave waited: a steady stream of garbage.
	if entry and not entry.list and clock - entry.at < FAILED_SEARCH_TTL then
		job.reason = entry.reason

		return nil
	end

	local min_d, max_d

	if job.monster then
		min_d = number_setting("monster_min_distance", 28)
		max_d = number_setting("monster_max_distance", 75)
	else
		min_d = number_setting("min_distance", 22)
		max_d = number_setting("max_distance", 65)
	end

	-- this wave's own distances (0 = keep the options' value)
	if job.dmin > 0 then
		min_d = job.dmin
	end

	if job.dmax > 0 then
		max_d = job.dmax
	end

	if max_d <= min_d then
		if job.dmax > 0 and job.dmin == 0 then
			min_d = math.max(0, max_d - 10)
		else
			max_d = min_d + 10
		end
	end

	local list, reason = Positions.candidates(min_d, max_d)

	if not list and job.test and NO_MAIN_PATH[reason] and Positions.test_candidates then
		list, reason = Positions.test_candidates(TEST_RING_MIN, TEST_RING_MAX)
	end

	if not list then
		throttled_log("spawn", reason)

		cache[key] = { at = clock, list = false, reason = reason }
		job.reason = reason

		return nil
	end

	cache[key] = { at = clock, list = list }
	job.reason = nil

	return list
end

-- Tells the user (once per wave) why nothing is spawning. Explicit /rw_test waves get a chat echo,
-- waves drawn by the director a log warning.
local function notify_stuck(job, text)
	if job.notified then
		return
	end

	job.notified = true

	if job.test then
		mod:echo("RealmsWaves: wave \"%s\" is not spawning: %s", tostring(job.name), text)
	else
		mod:warning("RealmsWaves: wave \"%s\" is not spawning: %s", tostring(job.name), text)
	end
end

-- The twin captains' toughness template (`twin_captain_one`) has `start_depleted = true`: their void
-- shield is created DOWN and the game raises it after spawning with `optional_init_toughness`
-- (auto_event.lua:845-883, minion_spawn_manager.lua:211-218; the toxic-gas-twins mutator calls
-- set_toughness_damage(0, true) itself). Spawning them without it leaves them shield-less.
local shield_init_cache = {}

local function needs_shield_init(breed_name)
	local cached = shield_init_cache[breed_name]

	if cached ~= nil then
		return cached
	end

	local ok, Breeds = pcall(require, "scripts/settings/breed/breeds")
	local breed = ok and type(Breeds) == "table" and Breeds[breed_name] or nil
	local template = breed and breed.toughness_template or nil
	local result = template ~= nil and template.start_depleted == true

	if breed then
		shield_init_cache[breed_name] = result
	end

	return result
end

-- Returns true, or false and a reason. `tune` = the group's custom mods (Groups.TUNE, percent), see spawn/tuning.lua.
-- `appearance` = the group's enemy colour experiments (spawn/appearance.lua); `face_target` (a wave in front of the player): the unit
-- looks at the target instead of looking where the target looks
local function spawn_one(breed_name, position, target_unit, mod_ids, tune, appearance, face_target)
	local spawn_manager = Managers.state.minion_spawn
	local side_system = Managers.state.extension:system("side_system")
	local villains = side_system and side_system:get_side_from_name("villains")

	if not villains then
		return false, "this level has no enemy side (villains), so no enemies can be spawned here"
	end

	local param = spawn_manager:request_param_table()

	param.optional_aggro_state = "aggroed"
	param.optional_target_unit = target_unit

	if needs_shield_init(breed_name) then
		param.optional_init_toughness = true
	end

	-- custom mods: the health is a spawn parameter (a multiplier of the normal health)
	local health = Tuning and Tuning.health_modifier(tune, breed_name)

	if health then
		param.optional_health_modifier = health
	end

	Bypass.begin_spawn()

	local ok, unit = pcall(function ()
		local rotation = face_target and Positions and Positions.rotation_towards and Positions.rotation_towards(position, target_unit) or nil

		return spawn_manager:spawn_minion(breed_name, position, rotation or Unit.world_rotation(target_unit, 1), villains.side_id, param)
	end)

	Bypass.end_spawn(ok and unit or nil)

	if not ok then
		mod:error("[spawn] %s failed: %s", tostring(breed_name), tostring(unit))

		return false, string.format("spawning %s failed: %s", tostring(breed_name), tostring(unit))
	end

	if not unit then return false, "native spawn returned no unit" end

	if mod_ids and unit then
		Execute.apply_modifiers(unit, mod_ids, breed_name)

		-- On Fire: the burn of this group (Tuning.BURN_DEFAULT percent unless the group sets it)
		for i = 1, #mod_ids do
			if mod_ids[i] == "fire" and Tuning and Tuning.mark_fire then
				Tuning.mark_fire(unit, tune)
			end
		end
	end

	-- after the modifiers, so a custom attack speed or hit mass is relative to what Enraged and the like already did
	if tune and unit and Tuning then
		Tuning.apply(unit, tune, breed_name)
	end
	if appearance and unit and Appearance then Appearance.apply(unit, appearance, breed_name) end
	-- a summoner (the Packmaster) is kept fighting (spawn/tuning.lua)
	if Tuning and Tuning.watch_summoner then Tuning.watch_summoner(unit, breed_name) end

	return true, unit
end

Execute.update = function (dt, paused)
	if mod.is_enabled and not mod:is_enabled() then
		Execute.cancel()
		Bypass.purge()

		return
	end

	if Effects then Effects.update(dt, paused) end

	-- custom mods: keep the written stats on top, send new sizes (cheap when nothing is tuned)
	if Tuning then
		Tuning.update(dt)
	end

	purge_timer = purge_timer + dt

	if purge_timer >= PURGE_INTERVAL then
		purge_timer = 0

		Bypass.purge()
	end

	if #jobs == 0 or paused then
		return
	end

	if not Execute.has_authority() then
		Execute.cancel()

		return
	end

	clock = clock + dt

	for i = #jobs, 1, -1 do
		local job = jobs[i]

		job.age = job.age + dt
		run_repeats(job, dt)

		if job.age > job.timeout or (#job.queue == 0 and (not job.rep or job.rep.done)) then
			table.remove(jobs, i)
		end
	end

	feed_timer = feed_timer - dt

	if feed_timer > 0 or #jobs == 0 then
		return
	end

	feed_timer = FEED_INTERVAL

	if over_heap_guard() then
		return
	end

	local room = number_setting("max_alive", 120) - Bypass.count()

	if room <= 0 then
		return
	end

	-- oldest job that still has units waiting (a repeating job may be idle between ticks)
	local job

	for i = 1, #jobs do
		if #jobs[i].queue > 0 then
			job = jobs[i]

			break
		end
	end

	if not job then
		return
	end

	local list = candidates_for(job)

	if not list then
		job.stuck_since = job.stuck_since or clock

		if clock - job.stuck_since >= NOTIFY_AFTER then
			notify_stuck(job, explain(job.reason))
		end

		return
	end

	job.stuck_since = nil

	local target = job.close and Positions.local_player_unit and Positions.local_player_unit() or Positions.random_player_unit()

	if not target then
		return
	end

	for _ = 1, math.min(FEED_BATCH, room, #job.queue) do
		local entry = job.queue[#job.queue]
		local position = Positions.pick(list)

		job.queue[#job.queue] = nil

		if position then
			position = Positions.spread(position, job.close and math.min(job.spread, CLOSE_SPREAD) or job.spread)
		end

		local ok, why

		if position then
			ok, why = spawn_one(entry.breed, position, target, entry.mods, entry.tune, entry.appearance, job.close)
		end

		if ok then
			job.spawned = job.spawned + 1
		end
		if not ok and why then
			job.failed = (job.failed or 0) + 1

			if job.failed >= 3 then
				notify_stuck(job, why)
			end
		end
	end
end

-- Scheduling cancellation leaves living units owned until mission teardown.
Execute.cancel = function ()
	if Effects then Effects.cancel() end
	jobs = {}
	cache = {}
	feed_timer = 0
	last_full_gc = -math.huge
	heap_paused = false
end

Execute.reset = function ()
	if Effects then Effects.reset() end
	Execute.cancel()
	purge_timer = 0

	if Bypass then
		Bypass.reset()
	end

	if Tuning then
		Tuning.reset()
	end
end

Execute.status = function ()
	return {
		jobs = #jobs,
		queued = queued_count(),
		job_limit = MAX_JOBS,
		queue_limit = MAX_PENDING,
		tracked = Bypass and Bypass.count() or 0,
		heap_mb = heap_mb(),
		heap_guard_mb = number_setting("heap_guard_mb", 800),
		heap_paused = heap_paused,
		stage = Positions and Positions.last_stage,
		last_error = Positions and Positions.last_error,
	}
end

return Execute
