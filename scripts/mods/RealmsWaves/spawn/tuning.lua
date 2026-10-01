-- Custom mods of an enemy group (catalog/groups.lua, Groups.TUNE): health, size, run speed, melee attack speed, gunner
-- fire rate, shots per burst and hit mass, in percent of the normal value. Host only, applied to a unit right after it
-- spawned; nothing here adds a breed or a buff template (see docs/03, "Enemy variants without new breeds"): every
-- one is a value the game itself already reads.
--
--   health  a spawn parameter (`optional_health_modifier`, read when the unit's health is created: Execute passes it)
--   speed   `navigation_extension:add_movement_modifier(m)`: the game's own way to slow or hasten a minion (it multiplies
--           whatever maximum speed the current action asks for, and is synced to the other players by the game)
--   mass    `health_extension:set_hit_mass(...)`: what the Enraged buff does to its unit (also synced by the game)
--   melee, fire, burst
--           the unit's `stat_buffs` (`melee_attack_speed`, `ranged_attack_speed`, `minion_num_shots_modifier`), which the
--           attack actions read when an attack starts. The buff system rewrites a stat when a buff that touches it
--           changes (a bleed or a brittleness debuff from a player, the Enraged modifier), so the written value is
--           checked a few times a second and put back on top (`reassert`).
--   size    `Unit.set_local_scale(unit, 1, ...)`, what the game's own Rampaging buff does. The game only runs it on every
--           player's machine because that buff is synced; ours is not, so the host also sends the unit's network id and
--           the size to the other players (RPC rw_scale) and each machine that has this mod applies it when the unit
--           exists there. A player without the mod sees the normal size.
local mod = get_mod("RealmsWaves")

local Tuning = {}

local Protocol

local UPDATE_INTERVAL = 0.25 -- seconds between two checks of the written stats
local SEND_INTERVAL = 0.3 -- seconds between two batches of new sizes sent to the other players
local SEND_BATCH = 100
local PENDING_TIMEOUT = 20 -- seconds a client waits for a unit to exist before it gives up
local MAX_PENDING = 600

-- custom mod -> the stats of the unit it writes (explosion and dot take their share of the damage: 50 = half damage)
Tuning.STAT_KEYS = {
	melee = { "melee_attack_speed" },
	fire = { "ranged_attack_speed" },
	burst = { "minion_num_shots_modifier" },
	explosion = { "damage_taken_from_explosions" },
	dot = { "damage_taken_from_burning", "damage_taken_from_toxin", "damage_taken_from_bleeding" },
}

local STAT_IDS = { "melee", "fire", "burst", "explosion", "dot" }
-- stats where the written value is a share of the damage taken (the game adds `value - 1` to the damage modifiers)
local DAMAGE_STAT = { explosion = true, dot = true }

local tuned_by_extension = {} -- host: buff extension -> record (for the hook below)
Tuning.dead = false

local tuned = {} -- host: { unit, mult = { [stat] = factor }, last = { [stat] = value written } }
local scaled = {} -- host: network id -> { unit, pct }
local outbox = {} -- host: sizes not sent yet, { id, pct }
local inbox = {} -- client: sizes waiting for their unit, { id, pct, age }
local timer, send_timer = 0, 0
local warned = {}

Tuning.init = function (deps)
	Protocol = deps and deps.protocol or nil
end

local function warn_once(message)
	if not warned[message] then
		warned[message] = true

		mod:warning("RealmsWaves: %s", message)
	end
end

local function alive(unit)
	if unit == nil then
		return false
	end

	if Unit and Unit.alive then
		local ok, result = pcall(Unit.alive, unit)

		return ok and result == true
	end

	return true
end

local function percent_of(value)
	value = tonumber(value)

	if not value or value ~= value or value == 100 then
		return nil
	end

	return value / 100
end

-- ------------------------------------------------------------------------------------------------- size
local function set_scale(unit, pct)
	local factor = pct / 100

	Unit.set_local_scale(unit, 1, Vector3(factor, factor, factor))
end

local function network_id(unit)
	local spawner = Managers.state and Managers.state.unit_spawner

	if not spawner or not spawner.game_object_id then
		return nil
	end

	local ok, id = pcall(spawner.game_object_id, spawner, unit)

	return ok and tonumber(id) or nil
end

-- ------------------------------------------------------------------------------------------ the host
-- The health of the unit is not set here: it is a spawn parameter, see Tuning.health_modifier.
Tuning.health_modifier = function (tune)
	return tune and percent_of(tune.health) or nil
end

-- Applies the custom mods `tune` ({ speed = 120, ... }, percent) to a unit that has just spawned. Every step is guarded:
-- a step that fails is logged once and never breaks the wave or the other steps.
Tuning.apply = function (unit, tune, breed_name)
	if not unit or not tune then
		return
	end

	local label = tostring(breed_name or "enemy")

	-- hit mass: relative to what the unit has now (an Enraged modifier added before this has already raised it)
	local mass = percent_of(tune.mass)

	if mass then
		local ok, err = pcall(function ()
			local health = ScriptUnit.has_extension(unit, "health_system")

			if not health or not health.hit_mass or not health.set_hit_mass then
				error("no health extension")
			end

			health:set_hit_mass(health:hit_mass() * mass)
		end)

		if not ok then
			warn_once(string.format("hit mass of %s was not changed: %s", label, tostring(err)))
		end
	end

	-- run speed
	local speed = percent_of(tune.speed)

	if speed then
		local ok, err = pcall(function ()
			local navigation = ScriptUnit.has_extension(unit, "navigation_system")

			if not navigation or not navigation.add_movement_modifier then
				error("no navigation extension")
			end

			navigation:add_movement_modifier(speed)
		end)

		if not ok then
			warn_once(string.format("run speed of %s was not changed: %s", label, tostring(err)))
		end
	end

	-- attack speeds and the burst size: stat buffs, kept on top by Tuning.update
	local record

	for i = 1, #STAT_IDS do
		local id = STAT_IDS[i]
		local factor = tune[id] ~= nil and tonumber(tune[id]) ~= 100 and tonumber(tune[id]) / 100 or nil

		if factor then
			local ok, err = pcall(function ()
				local buffs = ScriptUnit.has_extension(unit, "buff_system")

				if not buffs or not buffs.stat_buffs then
					error("no buff extension")
				end

				local stat_buffs = buffs:stat_buffs()
				local keys = Tuning.STAT_KEYS[id]

				record = record or { unit = unit, ext = buffs, mult = {}, last = {} }

				for k = 1, #keys do
					local value = (stat_buffs[keys[k]] or 1) * factor

					stat_buffs[keys[k]] = value
					record.mult[keys[k]] = factor
					record.last[keys[k]] = value
				end

				tuned_by_extension[buffs] = record
			end)

			if not ok then
				warn_once(string.format("%s of %s was not changed: %s", id, label, tostring(err)))
			end
		end
	end

	if record then
		tuned[#tuned + 1] = record
	end

	-- size
	local size = tonumber(tune.size)

	if size and size ~= 100 and size == size then
		local ok, err = pcall(function ()
			set_scale(unit, size)

			local id = network_id(unit)

			if id then
				scaled[id] = { unit = unit, pct = size }
				outbox[#outbox + 1] = { id, size }
			end
		end)

		if not ok then
			warn_once(string.format("size of %s was not changed: %s", label, tostring(err)))
		end
	end
end

-- Puts our factor on top of every stat of the record that the buff system rewrote since we wrote it.
local function reassert_record(record, buffs)
	local stat_buffs = buffs:stat_buffs()

	for key, factor in pairs(record.mult) do
		local now = stat_buffs[key] or 1

		if now ~= record.last[key] then
			local value = now * factor

			stat_buffs[key] = value
			record.last[key] = value
		end
	end
end

-- The buff system recomputes a unit's stats every frame while a buff that touches them is on it (a mission's global
-- modifier, Enraged, a debuff of a player): every recompute drops our factor, and the attack that starts in between
-- would read the plain value. So the factor is put back right after each recompute, by a hook (once per game start).
local installed = false

Tuning.install = function ()
	if installed or not mod.hook_safe then
		return
	end

	installed = true

	mod:hook_safe("BuffExtensionBase", "_update_stat_buffs_and_keywords", function (self)
		if Tuning.dead then
			return
		end

		local record = tuned_by_extension[self]

		if record then
			reassert_record(record, self)
		end
	end)
end

Tuning.retire = function ()
	Tuning.dead = true
	tuned_by_extension = {}
end

-- A stat of a tuned unit that the buff system has rewritten since we wrote it gets our factor on top again
-- (a fallback for the hook above).
local function reassert()
	for i = #tuned, 1, -1 do
		local record = tuned[i]

		if not alive(record.unit) then
			tuned_by_extension[record.ext] = nil
			tuned[i] = tuned[#tuned]
			tuned[#tuned] = nil
		else
			local buffs = ScriptUnit.has_extension(record.unit, "buff_system")

			if buffs and buffs.stat_buffs then
				reassert_record(record, buffs)
			end
		end
	end

	for id, entry in pairs(scaled) do
		if not alive(entry.unit) then
			scaled[id] = nil
		end
	end
end

local function send_batches(list, recipient)
	if not Protocol or not Protocol.send_scales or not Protocol.is_available() then
		return
	end

	local from = 1

	while from <= #list do
		local batch = {}

		for i = from, math.min(from + SEND_BATCH - 1, #list) do
			batch[#batch + 1] = list[i]
		end

		Protocol.send_scales(batch, recipient)
		from = from + SEND_BATCH
	end
end

-- Host, every frame (cheap: two counters until something is due).
Tuning.update = function (dt)
	timer = timer + dt
	send_timer = send_timer + dt

	if timer >= UPDATE_INTERVAL then
		timer = 0

		if #tuned > 0 or next(scaled) ~= nil then
			reassert()
		end
	end

	if send_timer >= SEND_INTERVAL then
		send_timer = 0

		if #outbox > 0 then
			local list = outbox

			outbox = {}
			send_batches(list)
		end
	end
end

-- Host: a player joined late; tell it the size of every living unit that has one.
Tuning.send_all = function (peer_id)
	local list = {}

	for id, entry in pairs(scaled) do
		if alive(entry.unit) then
			list[#list + 1] = { id, entry.pct }
		end
	end

	send_batches(list, peer_id)
end

-- ----------------------------------------------------------------------------------------- the clients
-- `entries` = { { id = network id, pct = percent }, ... }, already validated by the protocol.
Tuning.receive = function (entries)
	for i = 1, #(entries or {}) do
		if #inbox >= MAX_PENDING then
			break
		end

		local entry = entries[i]

		inbox[#inbox + 1] = { id = entry.id, pct = entry.pct, age = 0 }
	end
end

-- A client, every frame: puts the sizes on the units that have arrived here by now.
Tuning.update_client = function (dt)
	if #inbox == 0 then
		return
	end

	local spawner = Managers.state and Managers.state.unit_spawner

	if not spawner then
		return
	end

	for i = #inbox, 1, -1 do
		local entry = inbox[i]
		local ok, exists = pcall(spawner.unit_exists, spawner, entry.id)

		entry.age = entry.age + dt

		if ok and exists then
			local got, unit = pcall(spawner.unit, spawner, entry.id)

			if got and unit and alive(unit) then
				local applied, err = pcall(set_scale, unit, entry.pct)

				if not applied then
					warn_once(string.format("a size sent by the host could not be applied: %s", tostring(err)))
				end
			end

			table.remove(inbox, i)
		elseif entry.age > PENDING_TIMEOUT then
			table.remove(inbox, i)
		end
	end
end

Tuning.status = function ()
	return { tuned = #tuned, sizes_known = (function () local n = 0 for _ in pairs(scaled) do n = n + 1 end return n end)(), unsent = #outbox, pending = #inbox }
end

Tuning.reset = function ()
	tuned, scaled, outbox, inbox = {}, {}, {}, {}
	tuned_by_extension = {}
	timer, send_timer = 0, 0
end

return Tuning
