-- Finds spawn points that are near the players but hidden from ALL of them.
--
-- Uses the engine's per-group occlusion query (the same call the game's own
-- specials pacing ends up in) with every living player position, then filters by
-- distance to the NEAREST player. It never falls back to a visible point:
-- when nothing hidden is found the caller retries later.
-- (RealmsEvent avoided get_random_occluded_position because its C query errored
-- in this environment; occluded_positions_in_group is the path both existing
-- mods proved to work.)
--
-- Vector3 values are only valid for the frame they were created in, so
-- candidates are stored boxed and unboxed on use.
local mod = get_mod("GrandfathersTarot")

local SpawnPointQueries = require("scripts/managers/main_path/utilities/spawn_point_queries")
local NavQueries = require("scripts/utilities/nav_queries")

local Positions = {}

local GROUP_SPAN = 4 -- groups scanned on each side of a player's group
local MAX_PLAYERS_SCANNED = 3
local MAX_RAW_POINTS = 160
local MAX_CANDIDATES = 24
local ALLOWED_Z_DIFF = 12

-- {min multiplier, max multiplier}: tight, widened, relaxed
local STAGES = {
	{ 1, 1 },
	{ 0.7, 1.4 },
	{ 0.45, 2.2 },
}

Positions.last_error = nil
Positions.last_stage = nil

local function living_player_units()
	local extension = Managers.state and Managers.state.extension
	local side_system = extension and extension:system("side_system")
	local side = side_system and side_system:get_side_from_name("heroes")

	return side and side.valid_player_units or {}
end

Positions.player_units = living_player_units

Positions.random_player_unit = function ()
	local units = living_player_units()

	if #units == 0 then
		return nil
	end

	return units[math.random(1, #units)]
end

local function gather_raw(nav_world, nav_spawn_points, num_groups, player_positions)
	local raw = {}
	local scanned = {}
	local order = {}

	for i = 1, #player_positions do
		order[i] = i
	end

	for i = #order, 2, -1 do
		local j = math.random(1, i)

		order[i], order[j] = order[j], order[i]
	end

	for n = 1, math.min(#order, MAX_PLAYERS_SCANNED) do
		local position = player_positions[order[n]]
		local group_index = SpawnPointQueries.group_from_position(nav_world, nav_spawn_points, position, 3, 3)

		if group_index then
			for offset = 0, GROUP_SPAN do
				for sign = 1, (offset == 0 and 1 or 2) do
					local group = group_index + (sign == 1 and offset or -offset)

					if group >= 1 and group <= num_groups and not scanned[group] then
						scanned[group] = true

						local ok, points = pcall(SpawnPointQueries.occluded_positions_in_group, nav_world, nav_spawn_points, group, player_positions)

						if ok and points then
							for i = 1, #points do
								raw[#raw + 1] = Vector3Box(points[i])
							end
						elseif not ok then
							Positions.last_error = tostring(points)
						end

						if #raw >= MAX_RAW_POINTS then
							return raw
						end
					end
				end
			end
		end
	end

	return raw
end

local function filter(raw, player_positions, min_d, max_d)
	local result = {}

	for i = 1, #raw do
		local point = raw[i]:unbox()
		local nearest, nearest_dz = math.huge, 0

		for j = 1, #player_positions do
			local player_position = player_positions[j]
			local distance = Vector3.distance(point, player_position)

			if distance < nearest then
				nearest = distance
				nearest_dz = math.abs(point.z - player_position.z)
			end
		end

		if nearest >= min_d and nearest <= max_d and nearest_dz < ALLOWED_Z_DIFF then
			result[#result + 1] = raw[i]

			if #result >= MAX_CANDIDATES then
				break
			end
		end
	end

	return result
end

-- Returns a list of boxed positions, or nil plus a reason string.
Positions.candidates = function (min_d, max_d)
	local state = Managers.state
	local nav_mesh = state and state.nav_mesh
	local main_path = state and state.main_path

	if not nav_mesh or not main_path or not main_path:is_main_path_ready() then
		return nil, "main path not ready"
	end

	local nav_world = nav_mesh:nav_world()
	local nav_spawn_points = main_path:nav_spawn_points()

	if not nav_world or not nav_spawn_points then
		return nil, "no nav spawn points"
	end

	local ok_count, num_groups = pcall(GwNavSpawnPoints.get_count, nav_spawn_points)

	if not ok_count or not num_groups or num_groups == 0 then
		return nil, "no spawn groups"
	end

	local units = living_player_units()
	local player_positions = {}

	for i = 1, #units do
		player_positions[#player_positions + 1] = Unit.world_position(units[i], 1)
	end

	if #player_positions == 0 then
		return nil, "no living players"
	end

	local raw = gather_raw(nav_world, nav_spawn_points, num_groups, player_positions)

	if #raw == 0 then
		return nil, "no hidden points near players"
	end

	for stage = 1, #STAGES do
		local result = filter(raw, player_positions, min_d * STAGES[stage][1], max_d * STAGES[stage][2])

		if #result > 0 then
			Positions.last_stage = stage

			return result
		end
	end

	return nil, "hidden points exist but none within distance limits"
end

-- Test fallback for levels WITHOUT a main path (Psykhanium, hub-like places), where hidden spawn
-- points cannot be computed at all. Only used for explicit /gt_test waves: random walkable points
-- on a ring min_d..max_d metres around a random living player (NOT hidden, they can be in view).
-- Returns a list of boxed positions, or nil and a reason.
Positions.test_candidates = function (min_d, max_d)
	local nav_mesh = Managers.state and Managers.state.nav_mesh
	local nav_world = nav_mesh and nav_mesh:nav_world()

	if not nav_world then
		return nil, "no nav mesh on this level"
	end

	local units = living_player_units()

	if #units == 0 then
		return nil, "no living players"
	end

	local origin = Unit.world_position(units[math.random(1, #units)], 1)
	local list = {}

	for _ = 1, 80 do
		local angle = math.random() * math.pi * 2
		local distance = min_d + math.random() * (max_d - min_d)
		local candidate = origin + Vector3(math.cos(angle) * distance, math.sin(angle) * distance, 0)
		local ok, snapped = pcall(NavQueries.position_on_mesh, nav_world, candidate, 3, 3)

		if ok and snapped then
			local can_ok, can_go = pcall(NavQueries.ray_can_go, nav_world, origin, snapped, nil, 3, 3)

			if can_ok and can_go then
				list[#list + 1] = Vector3Box(snapped)
			end
		end

		if #list >= 16 then
			break
		end
	end

	if #list == 0 then
		return nil, "no walkable ground within reach of the player"
	end

	return list
end

-- ---------------------------------------------------------------------------------- right in front of the player
-- /gt_test_close: the wave appears right in front of the player who typed the command (the local player), where they are looking, on
-- open walkable ground, 3.5 to 8 metres ahead over a 70 degree arc; with a wall in the way, closer (1.5 to 3.5 m). Not hidden, not near
-- the other players: it is a test, to look at the units at once.
Positions.CLOSE_NEAR, Positions.CLOSE_FAR, Positions.CLOSE_NEAREST, Positions.CLOSE_ARC = 3.5, 8, 1.5, math.rad(70)

local function unit_alive(unit)
	if not unit then
		return false
	end

	local ok, alive = pcall(Unit.alive, unit)

	return ok and alive == true
end

-- The unit of the player at this machine (the host who typed the command); another living hero when that one has no unit or is dead.
Positions.local_player_unit = function ()
	local ok, unit = pcall(function ()
		local player = Managers.player and Managers.player:local_player(1)

		return player and player.player_unit
	end)

	if ok and unit_alive(unit) then
		return unit
	end

	return Positions.random_player_unit()
end

-- The horizontal direction a unit looks in as a unit vector (x, y): the first person camera of the player, else the body; nil when
-- neither can be read or the player looks straight up or down.
local function look_direction(unit)
	local function read(rotation_of)
		local ok, x, y = pcall(function ()
			local forward = Quaternion.forward(rotation_of())

			return forward.x, forward.y
		end)

		if not ok or type(x) ~= "number" or type(y) ~= "number" then
			return nil
		end

		local length = math.sqrt(x * x + y * y)

		if length < 0.01 then
			return nil
		end

		return x / length, y / length
	end

	local x, y = read(function ()
		local first_person = ScriptUnit.has_extension(unit, "first_person_system")

		return first_person:extrapolated_rotation()
	end)

	if x then
		return x, y
	end

	return read(function ()
		return Unit.world_rotation(unit, 1)
	end)
end

-- Boxed walkable points right in front of the local player, or nil and a reason. Not cached: the player moves and turns.
Positions.close_candidates = function ()
	local nav_mesh = Managers.state and Managers.state.nav_mesh
	local nav_world = nav_mesh and nav_mesh:nav_world()

	if not nav_world then
		return nil, "no nav mesh on this level"
	end

	local unit = Positions.local_player_unit()
	local ok_position, origin = pcall(function ()
		return unit and Unit.world_position(unit, 1)
	end)

	if not ok_position or not origin then
		return nil, "no living players"
	end

	local dx, dy = look_direction(unit)

	if not dx then
		dx, dy = 0, 1
	end

	for stage = 1, 2 do
		local near, far = Positions.CLOSE_NEAR, Positions.CLOSE_FAR

		if stage == 2 then
			near, far = Positions.CLOSE_NEAREST, Positions.CLOSE_NEAR
		end

		local list = {}

		for _ = 1, 40 do
			local angle = (math.random() - 0.5) * Positions.CLOSE_ARC
			local distance = near + math.random() * (far - near)
			local c, s = math.cos(angle), math.sin(angle)
			local candidate = origin + Vector3((dx * c - dy * s) * distance, (dx * s + dy * c) * distance, 0)
			local ok, snapped = pcall(NavQueries.position_on_mesh, nav_world, candidate, 3, 3)

			if ok and snapped then
				local can_ok, can_go = pcall(NavQueries.ray_can_go, nav_world, origin, snapped, nil, 3, 3)

				if can_ok and can_go then
					list[#list + 1] = Vector3Box(snapped)
				end
			end

			if #list >= 16 then
				break
			end
		end

		if #list > 0 then
			return list
		end
	end

	return nil, "no walkable ground right in front of you (a wall?): turn towards open ground"
end

-- The rotation that makes a unit at `position` face `unit` (flat), or nil: what appears in front of the player looks at the player.
Positions.rotation_towards = function (position, unit)
	local ok, rotation = pcall(function ()
		local to = Unit.world_position(unit, 1) - position
		local x, y = to.x, to.y
		local length = math.sqrt(x * x + y * y)

		if length < 0.01 then
			return nil
		end

		return Quaternion.look(Vector3(x / length, y / length, 0))
	end)

	return ok and rotation or nil
end

-- Random point within `radius` metres of `position`, on the nav mesh and reachable
-- in a straight line from `position` (no wall in between). Falls back to `position`.
-- Uniform over the disc (sqrt of the random radius). Used so a wave does not stack
-- every unit on the exact same spot.
Positions.spread = function (position, radius)
	if not radius or radius < 0.25 then
		return position
	end

	local nav_mesh = Managers.state and Managers.state.nav_mesh
	local nav_world = nav_mesh and nav_mesh:nav_world()

	if not nav_world then
		return position
	end

	-- a big disc often lands on walls or off the mesh, so give large radii more tries
	for _ = 1, radius > 20 and 10 or 5 do
		local angle = math.random() * math.pi * 2
		local distance = radius * math.sqrt(math.random())
		local candidate = position + Vector3(math.cos(angle) * distance, math.sin(angle) * distance, 0)
		local ok, snapped = pcall(NavQueries.position_on_mesh, nav_world, candidate, 2, 2)

		if ok and snapped then
			local can_ok, can_go = pcall(NavQueries.ray_can_go, nav_world, position, snapped, nil, 2, 2)

			if can_ok and can_go then
				return snapped
			end
		end
	end

	return position
end

Positions.pick = function (candidates)
	if not candidates or #candidates == 0 then
		return nil
	end

	return candidates[math.random(1, #candidates)]:unbox()
end

return Positions
