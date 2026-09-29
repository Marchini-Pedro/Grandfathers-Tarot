-- Host-only wave spawner.
--
-- A wave is expanded into a shuffled queue of breed names and drip-fed a few
-- units at a time (the game's own spawn queue is a 256-entry ring buffer with
-- no overflow guard, so we never hand it more than a couple per tick). Units are
-- spawned directly with MinionSpawnManager:spawn_minion, which has no limit
-- checks, and tracked by spawn/budget_bypass so the director ignores them.
local mod = get_mod("RealmsWaves")

local Execute = {}

local Positions, Bypass, Groups

local FEED_INTERVAL = 0.15
local FEED_BATCH = 2
local CANDIDATE_TTL = 1.5
local JOB_TIMEOUT = 60 -- seconds a wave may stay unfinished (repeating waves add their repeat time)
local MAX_QUEUE = 1000 -- a repeat tick is skipped while this many units are still waiting
local PURGE_INTERVAL = 5

local jobs = {}
local feed_timer = 0
local purge_timer = 0
local clock = 0
local cache = {}
local last_log = {}

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

-- Adds a modifier's buff templates to a freshly spawned unit, the way
-- MutatorBase._add_buffs_on_unit does (S\managers\mutator\mutators\mutator_base.lua:100-135).
-- Server side; minion buffs are synced to clients by the buff extension.
-- Every step is guarded: a buff that errors must never break the wave.
Execute.apply_modifiers = function (unit, mod_ids)
	local buff_extension = ScriptUnit.has_extension(unit, "buff_system")

	if not buff_extension or not mod_ids then
		return
	end

	local t = Managers.time:time("gameplay")

	for i = 1, #mod_ids do
		local modifier = Groups.modifier(mod_ids[i])

		if modifier and modifier.requires_havoc and not in_havoc_mission() then
			warn_once(modifier.name .. " needs a Havoc mission and was skipped")
		elseif modifier then
			for j = 1, #modifier.buffs do
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

Execute.has_authority = function ()
	local state = Managers.state
	local game_session = state and state.game_session

	return state ~= nil and state.minion_spawn ~= nil and game_session ~= nil and game_session:is_server() == true
end

local MULTIPLIER_SETTING = { normal = "mult_normal", boss = "mult_boss", special = "mult_special" }

-- Enemy-type multiplier from the mod options (percent / 100, 0 to 5). A group with random
-- alternatives ("a|b") uses the type of its first alternative.
local function multiplier_for(part)
	local breed = part.one_of and part.one_of[1] or part.breed
	local percent = number_setting(MULTIPLIER_SETTING[Groups.category(breed)], 100)

	return math.max(0, percent) / 100
end

Execute.multiplier_for = multiplier_for

-- Units for one batch: `field` is "count" (the initial spawn) or "rep" (one repeat tick).
-- Each group's number is scaled by its type's multiplier and rounded (half up), so
-- 0 removes that type from the wave and 5 gives five times as many.
local function expand(parts, field)
	local queue = {}
	local cap = number_setting("max_per_wave", 80)

	for i = 1, #parts do
		local part = parts[i]
		local one_of = part.one_of
		local amount = math.floor((part[field] or 0) * multiplier_for(part) + 0.5)

		for _ = 1, amount do
			queue[#queue + 1] = { breed = one_of and one_of[math.random(1, #one_of)] or part.breed, mods = part.mods }
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

	local queue = expand(def.parts, "count")
	local every = tonumber(def.rep_every) or 0
	local rep_for = tonumber(def.rep_for) or 0
	local has_repeat = Groups.has_repeat(def.parts) and every > 0 and rep_for > 0

	if #queue == 0 and not has_repeat then
		return false, (#(def.parts or {}) > 0) and "the enemy type multipliers (mod options) removed every enemy of this wave" or "empty wave"
	end

	-- Repeat ticks happen at every, 2*every, ... up to and including rep_for seconds.
	local rep

	if has_repeat then
		rep = { parts = def.parts, every = every, total = rep_for, clock = 0, next = every, done = every > rep_for }
	end

	jobs[#jobs + 1] = {
		name = def.name,
		monster = def.monster == true,
		spread = tonumber(def.spread) or 0,
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
		if #job.queue <= MAX_QUEUE then
			local batch = expand(rep.parts, "rep")

			for i = 1, #batch do
				table.insert(job.queue, 1, batch[i])
			end
		end

		rep.next = rep.next + rep.every
	end

	if rep.next > rep.total then
		rep.done = true
	end
end

local function candidates_for(monster)
	local kind = monster and "monster" or "normal"
	local entry = cache[kind]

	if entry and clock - entry.at < CANDIDATE_TTL and #entry.list > 0 then
		return entry.list
	end

	local min_d, max_d

	if monster then
		min_d = number_setting("monster_min_distance", 28)
		max_d = number_setting("monster_max_distance", 75)
	else
		min_d = number_setting("min_distance", 22)
		max_d = number_setting("max_distance", 65)
	end

	local list, reason = Positions.candidates(min_d, max_d)

	if not list then
		throttled_log("spawn", reason)

		return nil
	end

	cache[kind] = { at = clock, list = list }

	return list
end

local function spawn_one(breed_name, position, target_unit, mod_ids)
	local spawn_manager = Managers.state.minion_spawn
	local side_system = Managers.state.extension:system("side_system")
	local villains = side_system and side_system:get_side_from_name("villains")

	if not villains then
		return false
	end

	local param = spawn_manager:request_param_table()

	param.optional_aggro_state = "aggroed"
	param.optional_target_unit = target_unit

	Bypass.begin_spawn()

	local ok, unit = pcall(spawn_manager.spawn_minion, spawn_manager, breed_name, position, Unit.world_rotation(target_unit, 1), villains.side_id, param)

	Bypass.end_spawn(ok and unit or nil)

	if not ok then
		mod:error("[spawn] %s failed: %s", tostring(breed_name), tostring(unit))

		return false
	end

	if mod_ids and unit then
		Execute.apply_modifiers(unit, mod_ids)
	end

	return true
end

Execute.update = function (dt)
	clock = clock + dt

	if #jobs == 0 then
		return
	end

	if not Execute.has_authority() then
		jobs = {}

		return
	end

	purge_timer = purge_timer + dt

	if purge_timer >= PURGE_INTERVAL then
		purge_timer = 0

		Bypass.purge()
	end

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

	local list = candidates_for(job.monster)

	if not list then
		return
	end

	local target = Positions.random_player_unit()

	if not target then
		return
	end

	for _ = 1, math.min(FEED_BATCH, room, #job.queue) do
		local entry = job.queue[#job.queue]
		local position = Positions.pick(list)

		job.queue[#job.queue] = nil

		if position then
			position = Positions.spread(position, job.spread)
		end

		if position and spawn_one(entry.breed, position, target, entry.mods) then
			job.spawned = job.spawned + 1
		end
	end
end

Execute.reset = function ()
	jobs = {}
	cache = {}
	feed_timer = 0

	if Bypass then
		Bypass.reset()
	end
end

Execute.status = function ()
	local queued = 0

	for i = 1, #jobs do
		queued = queued + #jobs[i].queue
	end

	return {
		jobs = #jobs,
		queued = queued,
		tracked = Bypass and Bypass.count() or 0,
		stage = Positions and Positions.last_stage,
		last_error = Positions and Positions.last_error,
	}
end

return Execute
