-- Host-only wave spawner.
--
-- A wave is expanded into a shuffled queue of breed names and drip-fed a few
-- units at a time (the game's own spawn queue is a 256-entry ring buffer with
-- no overflow guard, so we never hand it more than a couple per tick). Units are
-- spawned directly with MinionSpawnManager:spawn_minion, which has no limit
-- checks, and tracked by spawn/budget_bypass so the director ignores them.
local mod = get_mod("RealmsWaves")

local Execute = {}

local Positions, Bypass

local FEED_INTERVAL = 0.15
local FEED_BATCH = 2
local CANDIDATE_TTL = 1.5
local JOB_TIMEOUT = 60
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
end

Execute.has_authority = function ()
	local state = Managers.state
	local game_session = state and state.game_session

	return state ~= nil and state.minion_spawn ~= nil and game_session ~= nil and game_session:is_server() == true
end

local function expand(def)
	local queue = {}
	local cap = number_setting("max_per_wave", 80)

	for i = 1, #def.parts do
		local part = def.parts[i]
		local one_of = part.one_of

		for _ = 1, part.count do
			queue[#queue + 1] = one_of and one_of[math.random(1, #one_of)] or part.breed
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

	local queue = expand(def)

	if #queue == 0 then
		return false, "empty wave"
	end

	jobs[#jobs + 1] = {
		name = def.name,
		monster = def.monster == true,
		queue = queue,
		total = #queue,
		spawned = 0,
		age = 0,
	}

	return true
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

local function spawn_one(breed_name, position, target_unit)
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
		jobs[i].age = jobs[i].age + dt

		if jobs[i].age > JOB_TIMEOUT or #jobs[i].queue == 0 then
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

	local job = jobs[1]
	local list = candidates_for(job.monster)

	if not list then
		return
	end

	local target = Positions.random_player_unit()

	if not target then
		return
	end

	for _ = 1, math.min(FEED_BATCH, room, #job.queue) do
		local breed_name = job.queue[#job.queue]
		local position = Positions.pick(list)

		job.queue[#job.queue] = nil

		if position and spawn_one(breed_name, position, target) then
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
