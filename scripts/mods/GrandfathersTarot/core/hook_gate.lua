-- Hooks on busy game functions, on only while their feature has something to do (2026-10-11, the user: "In the middle of a realms
-- game with /gt_stop my tarot randomly goes to 0.1xx"). A hook DMF holds active costs a call of ours every time the game calls the
-- function, and a normal hook's time includes the game's own function under the Mod Performance Monitor: the Twins hook on
-- MinionSpawnManager.spawn_minion billed every horde spawn of the game to the mod, the one on MinionDeathManager.die every death,
-- the health hooks every hit. A switched-off DMF hook calls straight through (no call of ours, no time billed).
--
-- Gate.add(name, obj, methods, wanted): `wanted()` says whether the hook has work; the hook is switched off once it has said no for
-- LINGER seconds (a golden panel or a coloured boss bar gets the frames it needs to put things back), and on again at the next
-- tick it says yes (Gate.refresh: at once, for a caller that has just made work, e.g. a card's enemy spawned).
-- Correctness never depends on a hook being OFF: DMF switches every hook on again (the mod enabled, the dormancy's wake, a hook made
-- late for a class loaded later), and the applied state is forgotten every RESYNC seconds so that it is put right.
local Gate = {}

local INTERVAL = 0.25
local LINGER = 2
local RESYNC = 3

local mod = nil
local entries = {}
local by_name = {}
local timer, resync_timer, clock = 0, 0, 0

Gate.init = function (deps)
	mod = deps.mod
	entries, by_name = {}, {}
	timer, resync_timer, clock = 0, 0, 0
end

-- `obj` a table, or a class name looked up when the hook is switched (CLASS, then _G); `methods` one name or a list
Gate.add = function (name, obj, methods, wanted)
	if not mod or type(wanted) ~= "function" then
		return
	end

	local entry = by_name[name]

	if not entry then
		entry = { name = name, targets = {}, wanted = wanted, applied = nil, quiet_since = nil }
		by_name[name] = entry
		entries[#entries + 1] = entry
	end

	entry.wanted = wanted

	-- (a hook_require callback runs again at every game start: a target already held is not added twice)
	for _, method in ipairs(type(methods) == "table" and methods or { methods }) do
		local held = false

		for _, target in ipairs(entry.targets) do
			if target.obj == obj and target.method == method then held = true end
		end

		if not held then
			entry.targets[#entry.targets + 1] = { obj = obj, method = method }
		end
	end

	-- not known yet: the next tick applies the answer
	entry.applied = nil
end

local function resolve(obj)
	if type(obj) == "table" then
		return obj
	end

	local classes = rawget(_G, "CLASS")

	return (classes and rawget(classes, obj)) or rawget(_G, obj)
end

local function apply(entry, on)
	local all = true

	for _, target in ipairs(entry.targets) do
		local obj = resolve(target.obj)

		-- a class not loaded yet: DMF makes its hook later (active); a later resync switches it
		if obj and type(obj[target.method]) == "function" then
			if on then
				mod:hook_enable(obj, target.method)
			else
				mod:hook_disable(obj, target.method)
			end
		else
			all = false
		end
	end

	-- (not `all and on or nil`: that turns an applied false into nil, and the switch-off was applied again every tick)
	if all then
		entry.applied = on
	else
		entry.applied = nil
	end
end

local function wants(entry)
	local ok, yes = pcall(entry.wanted)

	-- a failing question keeps the hook on (the safe side)
	return not ok or yes == true
end

local function decide(entry)
	if wants(entry) then
		entry.quiet_since = nil

		if entry.applied ~= true then
			apply(entry, true)
		end
	else
		entry.quiet_since = entry.quiet_since or clock

		if entry.applied ~= false and clock - entry.quiet_since >= LINGER then
			apply(entry, false)
		end
	end
end

-- every gate asked now (one name: only that one)
Gate.refresh = function (name)
	if not mod or not mod.hook_enable or not mod.hook_disable then
		return
	end

	if name then
		local entry = by_name[name]

		if entry then decide(entry) end

		return
	end

	for i = 1, #entries do
		decide(entries[i])
	end
end

-- forget what was applied (DMF switched every hook on again): the next tick applies every answer
Gate.resync = function ()
	for i = 1, #entries do
		entries[i].applied = nil
	end
end

-- every frame while the mod is awake (mod.update)
Gate.update = function (dt)
	clock = clock + (dt or 0)
	timer = timer + (dt or 0)
	resync_timer = resync_timer + (dt or 0)

	if timer < INTERVAL then
		return
	end

	timer = 0

	if resync_timer >= RESYNC then
		resync_timer = 0
		Gate.resync()
	end

	Gate.refresh()
end

-- for the suites and /gt_perf-like reports: { name = applied } (true on, false off, nil unknown)
Gate.state = function ()
	local list = {}

	for i = 1, #entries do
		list[entries[i].name] = entries[i].applied
	end

	return list
end

-- the names of the gates held (the suites)
Gate.names = function ()
	local list = {}

	for i = 1, #entries do
		list[i] = entries[i].name
	end

	return list
end

Gate.retire = function ()
	mod, entries, by_name = nil, {}, {}
end

return Gate
