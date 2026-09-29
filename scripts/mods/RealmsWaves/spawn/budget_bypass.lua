-- Keeps mod-owned wave units out of the director's limits and counters.
--
-- The game has no per-breed "ignore limit" flag. Every limit reader (hard 145
-- cap in PacingManager.spawn_type_enabled, horde max_active_minions, ambush and
-- trickle thresholds, auto events, terror event trickle) goes through
-- MinionSpawnManager:num_spawned_minions() / :total_allocated_num_enemies(), and
-- aggro challenge rating goes through PacingManager:add_aggroed_minion(). So:
--   * units we spawn are tracked in a set,
--   * both counters are hooked to subtract the tracked count,
--   * add_aggroed_minion is skipped for tracked units (also during our own
--     spawn call, because aggro happens before spawn_minion returns the unit).
-- Host only: on clients these managers do not exist and the hooks never fire.
local mod = get_mod("RealmsWaves")

local Bypass = {}

local tracked = {}
local tracked_count = 0

Bypass.spawning = false

Bypass.track = function (unit)
	if unit ~= nil and not tracked[unit] then
		tracked[unit] = true
		tracked_count = tracked_count + 1
	end
end

Bypass.untrack = function (unit)
	if tracked[unit] then
		tracked[unit] = nil
		tracked_count = tracked_count - 1
	end
end

Bypass.count = function ()
	return tracked_count
end

Bypass.is_tracked = function (unit)
	return tracked[unit] == true
end

Bypass.reset = function ()
	tracked = {}
	tracked_count = 0
	Bypass.spawning = false
end

-- Fallback for units that vanished without unregister_unit being called.
Bypass.purge = function ()
	for unit in pairs(tracked) do
		if not ALIVE[unit] then
			Bypass.untrack(unit)
		end
	end
end

Bypass.begin_spawn = function ()
	Bypass.spawning = true
end

Bypass.end_spawn = function (unit)
	Bypass.spawning = false

	if unit then
		Bypass.track(unit)
	end
end

local function adjusted(value)
	value = value - tracked_count

	return value < 0 and 0 or value
end

local installed = false

Bypass.install = function ()
	if installed then
		return
	end

	installed = true

	mod:hook("PacingManager", "add_aggroed_minion", function (func, self, unit)
		if Bypass.spawning then
			Bypass.track(unit)
		end

		if tracked[unit] then
			return
		end

		return func(self, unit)
	end)

	mod:hook("MinionSpawnManager", "num_spawned_minions", function (func, self)
		return adjusted(func(self))
	end)

	mod:hook("MinionSpawnManager", "total_allocated_num_enemies", function (func, self)
		return adjusted(func(self))
	end)

	mod:hook_safe("MinionSpawnManager", "unregister_unit", function (self, unit)
		Bypass.untrack(unit)
	end)
end

return Bypass
