-- Custom mods of an enemy group (catalog/groups.lua, Groups.TUNE): health, size, run speed, time between attacks, gunner
-- fire rate, shots per burst, hit mass, explosion and damage-over-time taken, in percent of the normal value. Host only, applied to a unit right after it
-- spawned; nothing here adds a breed or a buff template (see docs/03, "Enemy variants without new breeds"): every
-- one is a value the game itself already reads.
--
--   health  a spawn parameter (`optional_health_modifier`, read when the unit's health is created: Execute passes it)
--   speed   `navigation_extension:add_movement_modifier(m)`: the game's own way to slow or hasten a minion (it multiplies
--           whatever maximum speed the current action asks for, and is synced to the other players by the game)
--   mass    `health_extension:set_hit_mass(...)`: what the Enraged buff does to its unit (also synced by the game)
--   gap, fire, burst
--           the unit's `stat_buffs` (`melee_attack_speed`, `ranged_attack_speed`, `minion_num_shots_modifier`), which the
--           attack actions read when an attack starts. `gap` is the TIME between attacks: the game's stat is a speed, so
--           the factor written is 100 / value (gap 50 writes 2, gap 200 writes 0.5). What the game does with
--           `melee_attack_speed` is only to cut the END of a melee attack short (it ends at duration / speed, never
--           before the last hit plus 0.27 s); it does not speed the animation, and for a chained sweep attack (Plague
--           Ogryn, Chaos Spawn) it measured the first hit instead of the last, so a high value dropped the rest of the
--           chain. `fix_attack_end` below repairs that for our units. The buff system rewrites a stat when a buff that touches it
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
	gap = { "melee_attack_speed" },
	fire = { "ranged_attack_speed" },
	burst = { "minion_num_shots_modifier" },
	explosion = { "damage_taken_from_explosions" },
	dot = { "damage_taken_from_burning", "damage_taken_from_toxin", "damage_taken_from_bleeding" },
}

local STAT_IDS = { "gap", "fire", "burst", "explosion", "dot" }
-- custom mods that are a TIME while the stat they write is a speed: the factor is 100 / value
local INVERSE = { gap = true }
local ATTACK_END_OFFSET = 0.26666666666666666 -- the game's ATTACK_SPEED_THRESHOLD_FRAME_OFFSET (bt_melee_attack_action.lua:118)
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

-- the factor a custom mod writes into its stat (nil = nothing to write)
local function factor_for(id, value)
	value = tonumber(value)

	if value == nil or value ~= value or value == 100 then
		return nil
	end

	if INVERSE[id] then
		if value <= 0 then
			return nil
		end

		return 100 / value
	end

	return value / 100
end

Tuning.factor_for = factor_for

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
		local factor = factor_for(id, tune[id])

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

-- The record of a tuned unit (nil for every other unit).
local function record_of(unit)
	local buffs = unit ~= nil and ScriptUnit.has_extension(unit, "buff_system") or nil

	return buffs and tuned_by_extension[buffs] or nil
end

-- Called after every melee attack has started (BtMeleeAttackAction._start_attack_anim). The game ends such an attack at
-- max(duration / melee_attack_speed, T + 0.27 s) where T is the end of the FIRST hit of a chained sweep (see the header):
-- with a high speed a chain stops after one hit. For a unit with a custom time between attacks T is made the end of the
-- LAST hit, and an attack is only ever lengthened by this, never shortened.
Tuning.fix_attack_end = function (self, unit, breed, target_unit, t, spawn_component, scratchpad, action_data)
	if Tuning.dead or type(scratchpad) ~= "table" or not scratchpad.melee_attack_speed then
		return
	end

	local ok, err = pcall(function ()
		local record = record_of(unit)

		if not record or not record.mult.melee_attack_speed then
			return
		end

		local list = scratchpad.attack_sweep_timings

		if scratchpad.attack_type ~= "sweep" or type(list) ~= "table" then
			return
		end

		local last = list[#list]
		local stop = type(last) == "table" and last[2] or list[2]
		local durations = action_data and action_data.attack_anim_durations
		local base = durations and durations[scratchpad.attack_event]

		if type(stop) ~= "number" or type(base) ~= "number" or type(t) ~= "number" then
			return
		end

		local wanted = t + math.max(base / scratchpad.melee_attack_speed, stop + ATTACK_END_OFFSET)

		if type(scratchpad.attack_duration) == "number" and wanted > scratchpad.attack_duration then
			scratchpad.attack_duration = wanted
		end
	end)

	if not ok then
		warn_once(string.format("the end of a melee attack could not be corrected: %s", tostring(err)))
	end
end

Tuning.install = function ()
	if installed or not mod.hook_safe then
		return
	end

	installed = true

	mod:hook_safe("BtMeleeAttackAction", "_start_attack_anim", function (...)
		Tuning.fix_attack_end(...)
	end)

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

		-- a peer that left or a network that fails is not our business: skip the rest, never break the frame
		local ok, err = pcall(Protocol.send_scales, batch, recipient)

		if not ok then
			warn_once(string.format("sizes could not be sent to the other players: %s", tostring(err)))

			return
		end

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

-- ------------------------------------------------------------------------------------ the animation probe
-- "Animation attack speed" (how fast the swing itself plays, per unit) was asked for, but no script of the game does it:
-- a minion's animation is steered by events and by the variables its state machine lists (in practice the two that blend
-- the locomotion). Whether a state machine has a variable that scales attacks, or the engine a call that sets a unit's
-- animation speed, can only be seen in the running game, so /rw_anim reports both and the feature is built on the answer
-- (docs/07-learnings-and-gaps.md).
Tuning.ANIM_CANDIDATES = {
	"attack_speed", "anim_speed", "animation_speed", "attack_anim_speed", "anim_attack_speed", "melee_speed", "speed_scale",
	"time_scale", "playback_speed", "anim_playback_speed", "speed",
	"anim_move_speed", "moving_attack_fwd_speed", -- controls: the variables the breeds list, they should be found
}

local ENGINE_WORDS = { "anim", "speed", "time", "scale", "rate" }

-- the name of the breed of a unit ("?" when it cannot be read)
local function breed_name(unit)
	local ok, name = pcall(function ()
		local data = ScriptUnit.has_extension(unit, "unit_data_system")
		local breed = data and data:breed()

		return breed and breed.name
	end)

	return ok and name or "?"
end

-- Returns a list of text lines: the functions of the engine's Unit table that mention animation, speed, time, scale or
-- rate, then for each given unit (one per breed) which of the candidate variables its animation state machine has.
Tuning.probe = function (units)
	local lines = {}
	local found = {}

	if type(Unit) == "table" then
		for key, value in pairs(Unit) do
			if type(key) == "string" and type(value) == "function" then
				local lower = key:lower()

				for i = 1, #ENGINE_WORDS do
					if lower:find(ENGINE_WORDS[i], 1, true) then
						found[#found + 1] = key

						break
					end
				end
			end
		end
	end

	table.sort(found)
	lines[#lines + 1] = string.format("Unit functions about animation, speed, time, scale or rate (%d): %s", #found, table.concat(found, ", "))

	local seen = {}
	local breeds = 0
	local can_look = type(Unit) == "table" and type(Unit.animation_find_variable) == "function"

	for _, unit in ipairs(can_look and units or {}) do
		local name = breed_name(unit)

		if not seen[name] and alive(unit) then
			seen[name] = true
			breeds = breeds + 1

			local have = {}

			for i = 1, #Tuning.ANIM_CANDIDATES do
				local candidate = Tuning.ANIM_CANDIDATES[i]
				local ok, index = pcall(Unit.animation_find_variable, unit, candidate)

				if ok and index ~= nil then
					local detail = candidate

					if Unit.animation_get_variable_min_max then
						local got, low, high = pcall(Unit.animation_get_variable_min_max, unit, index)

						if got and low ~= nil then
							detail = string.format("%s (%s to %s)", candidate, tostring(low), tostring(high))
						end
					end

					have[#have + 1] = detail
				end
			end

			lines[#lines + 1] = string.format("%s has animation variables: %s", name, #have > 0 and table.concat(have, ", ") or "none of the candidates")
		end
	end

	if not can_look then
		lines[#lines + 1] = "This game has no Unit.animation_find_variable, so the variables of a unit cannot be looked at."
	elseif breeds == 0 then
		lines[#lines + 1] = "No wave unit is alive to look at: spawn one first (/rw_test <wave>) and run this again close to it."
	end

	return lines
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
