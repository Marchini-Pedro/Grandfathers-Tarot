-- Custom mods of an enemy group (catalog/groups.lua, Groups.TUNE): health, size, run speed, time between attacks, gunner
-- fire rate, shots per burst, hit mass, explosion and damage-over-time taken, in percent of the normal value. Host only, applied to a unit right after it
-- spawned; nothing here adds a breed or a buff template (see docs/03, "Enemy variants without new breeds"): every
-- one is a value the game itself already reads.
--
--   health  a spawn parameter (`optional_health_modifier`, read when the unit's health is created: Execute passes it), then made
--           exact right after the spawn: the game ADDS the Havoc / mission health modifier to the parameter (see set_exact_health)
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
--           chain. `fix_attack_end` below repairs that for our units. The buff system recomputes a stat every frame while a
--           buff that touches it is on the unit (a mission's Havoc modifier, the Enraged modifier, a debuff of a player):
--           it first resets the stats listed in `stat_buffs._modified_stats` to their base value, then adds every buff. So
--           the value is written WITH its key in `_modified_stats` (otherwise the next recompute adds the buff on top of our
--           value and our factor is applied twice or lost), and is put back on top right after every recompute by a hook on
--           `_update_stat_buffs_and_keywords` of BuffExtensionBase AND of MinionBuffExtension (the game's `class()` copies the
--           parent's methods into a subclass when it is created, so a hook on the parent does not reach the subclass), and
--           by a check a few times a second (`reassert`) as a fallback.
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
	damage = { "damage" }, -- (the damage it deals: utilities/attack/damage_calculation.lua adds attacker_stat_buffs.damage - 1)
}

local STAT_IDS = { "gap", "fire", "burst", "explosion", "dot", "damage" }
-- custom mods that are a TIME while the stat they write is a speed: the factor is 100 / value
local INVERSE = { gap = true }
local ATTACK_END_OFFSET = 0.26666666666666666 -- the game's ATTACK_SPEED_THRESHOLD_FRAME_OFFSET (bt_melee_attack_action.lua:118)
-- stats where the written value is a share of the damage taken (the game adds `value - 1` to the damage modifiers)
local DAMAGE_STAT = { explosion = true, dot = true }

local tuned_by_extension = {} -- host: buff extension -> record (for the hook below)
Tuning.dead = false
local fire_share = setmetatable({}, { __mode = "k" }) -- the On Fire burn: enemy -> its group's share (see "On Fire damage" below)

local tuned = {} -- host: { unit, mult = { [stat] = factor }, last = { [stat] = value written } }
local scaled = {} -- host: network id -> { unit, pct }
local sized = {} -- host: unit -> size in percent (what the explosion of a burster reads, see explosion_enter)
local last_shot = setmetatable({}, { __mode = "k" }) -- host: unit -> what its last shooting start read (see /rw_tune)
local shoot_logged = {} -- breed name -> how many shooting starts were written to the log
local apply_logged = {} -- breed name -> how many tuned units were written to the log
local outbox = {} -- host: sizes not sent yet, { id, pct }
local outbox_by_id = {}
local inbox = {} -- client: sizes waiting for their unit, { id, pct, age }
local inbox_by_id = {} -- one pending value per unit; a later message replaces the earlier one
local timer, send_timer = 0, 0
local warned = {}

local function queue_size(id, pct)
	local entry = outbox_by_id[id]

	if entry then
		entry[2] = pct
	else
		entry = { id, pct }
		outbox[#outbox + 1] = entry
		outbox_by_id[id] = entry
	end
end

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
local function factor_for_size(factor)
	factor = tonumber(factor)

	if not factor or factor ~= factor or factor <= 0 then
		return 1
	end

	return factor
end

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

-- Writes a stat of a unit and lists it among the stats the buff system resets before each recompute (see the header):
-- without that entry the next recompute would add the buffs on top of our value instead of on top of the base value.
local function write_stat(stat_buffs, key, value)
	stat_buffs[key] = value

	local modified = stat_buffs._modified_stats

	if type(modified) == "table" then
		modified[key] = true
	end
end

-- ------------------------------------------------------------------------------------------ the host
-- The health of the unit is not set here: it is a spawn parameter, see Tuning.health_modifier.
Tuning.health_modifier = function (tune, breed_name)
	local factor = tune and percent_of(tune.health) or nil

	-- (the spawn parameter never more than the network can carry, see Tuning.network_health_max: the game object is created with
	-- it; set_exact_health raises the health to the wanted value right after, and only a scaled copy goes on the network)
	if factor and breed_name then
		local ok, base = pcall(function () return tonumber(Tuning.normal_health(breed_name)) end)
		local cap = Tuning.network_health_max()

		if ok and base and base > 0 and cap and base * factor > cap then
			factor = cap / base
		end
	end

	return factor
end

-- The most health the game can send to the other players (2026-10-04: a Chaos Spawn at 350 percent showed 0 or a wrong number in
-- the boss bar of the clients, who read the unit's maximum from the game object's "health" field). The game itself caps one hit's
-- damage at NetworkConstants.health_large.max (damage_taken_calculation.lua), the type of that field; a larger value does not
-- reach the clients intact.
Tuning.network_health_max = function ()
	local ok, constants = pcall(require, "scripts/network_lookup/network_constants")
	local info = ok and type(constants) == "table" and constants.health_large

	return info and tonumber(info.max) or nil
end

-- The health the player asked for is NOT what the game builds from the spawn parameter: MinionSpawnManager.spawn_minion adds the
-- Havoc / mission modifier of the breed to it, `(optional_health_modifier or 1) + additional` (minion_spawn_manager.lua:137-165), and the
-- mods that rewrite that modifier (Ultra Havoc and the like, `get_minion_health_modifier`) make it bigger or smaller still. A boss set
-- to 50 percent came out at 50 percent PLUS the Havoc share, so the config was never 1:1. Right after the spawn the unit's maximum
-- health is therefore set to exactly its normal health x the player's percent: the same two writes the game's own
-- HealthExtension.init makes (the extension's `_health` and the game object's "health" field, which is what the other players read).
-- A boss with less health than normal stays "weakened" for the game (its bar says "Weakened <name>", the pacing counts a fifth of a
-- boss: boss_extension.lua:61-66, hud_element_boss_health.lua:132-141, pacing_manager.lua:853-858): that is the game's own word for
-- "less health than normal" and it is kept. Only the boss's mark is re-read, because the game made it from the health BEFORE this fix.
local HEALTH_EPSILON = 0.01

-- The normal maximum health of a breed on this mission's difficulty (what the game compares a boss against to call it weakened).
local function normal_health(breed_name)
	return Tuning.normal_health(breed_name)
end

Tuning.normal_health = function (breed_name)
	local difficulty = Managers.state and Managers.state.difficulty

	if not difficulty or not difficulty.get_minion_max_health then
		error("no difficulty manager")
	end

	return difficulty:get_minion_max_health(breed_name)
end

-- Sets the maximum health of a freshly spawned unit to normal health x `factor`. Returns the requested health, including when the unit
-- already had exactly that. Errors (caller guards them) when the unit has no readable health.
Tuning.set_exact_health = function (unit, breed_name, factor)
	local health = ScriptUnit.has_extension(unit, "health_system")

	if not health or type(health.max_health) ~= "function" then
		error("no health extension")
	end

	local ok_breed, breed = pcall(function ()
		return ScriptUnit.extension(unit, "unit_data_system"):breed()
	end)
	local name = ok_breed and type(breed) == "table" and breed.name or breed_name
	local base = tonumber(normal_health(name))

	if not base or base ~= base or base <= 0 then
		error("no normal health for " .. tostring(name))
	end

	local wanted = math.max(1, base * factor)
	local cap = Tuning.network_health_max()

	if math.abs(health:max_health() - wanted) > HEALTH_EPSILON or (cap and wanted > cap) then
		if not health._game_session or not health._game_object_id then
			error("the unit has no game object yet")
		end

		Tuning.fit_network(unit, health, wanted)
	end

	-- the game made the boss's "weakened" mark from the health it had BEFORE this fix: read it again with the same rule
	local boss = ScriptUnit.has_extension(unit, "boss_system")

	if boss then
		boss._is_weakened = wanted < base
	end

	return wanted
end

-- ------------------------------------------------------------------------------------------ health above the network's limit
-- (2026-10-05, the user: "remove the health limit; put x2, x3 beside the bar, a boss with several bars") The game object's
-- "health" and "damage" fields cannot carry more than NetworkConstants.health_large.max. A unit with more health keeps its real
-- health on the host (the extension's `_health` and `_damage`: every hit, heal and death works on them) while the network gets
-- the same numbers divided by `k` (the smallest whole number that makes them fit): the share of health left that the other
-- players read is exact. Their boss bar learns the real maximum from the host's state (Director snapshot `hl`) and shows the
-- health in bars of the network's limit with "xN" for the full bars still behind the one shown (Tuning.layer_boss_targets).
local NET_MARGIN = 0.98
local net_scale = setmetatable({}, { __mode = "k" }) -- host: health extension -> { unit, k, max }
local true_max_by_id = {} -- a client: game object id -> real maximum health (from the host)

local function write_net_damage(health)
	local entry = net_scale[health]
	local k = entry and entry.k or 1
	local damage = math.max(0, math.min(tonumber(health._damage) or 0, health._health))

	GameSession.set_game_object_field(health._game_session, health._game_object_id, "damage", damage / k)
end

-- Host: gives the unit `max` health: the network first, divided as much as it needs (a write the game refuses leaves the unit as
-- it was), then the extension. Returns `k`.
Tuning.fit_network = function (unit, health, max)
	max = tonumber(max) or tonumber(health._health) or 1

	local cap = Tuning.network_health_max()
	local k = 1

	if cap and cap > 0 and max > cap * NET_MARGIN then
		k = math.ceil(max / (cap * NET_MARGIN))
	end

	GameSession.set_game_object_field(health._game_session, health._game_object_id, "health", max / k)

	if k > 1 or net_scale[health] then
		local damage = math.max(0, math.min(tonumber(health._damage) or 0, max))

		GameSession.set_game_object_field(health._game_session, health._game_object_id, "damage", damage / k)
	end

	health._health = max
	net_scale[health] = k > 1 and { unit = unit, k = k, max = max } or nil

	return k
end

-- Host, after the game wrote a hit, a heal or an instant health (HealthExtension): the network gets the divided damage instead
Tuning.after_health_write = function (health)
	if not Tuning.dead and net_scale[health] then
		local ok, err = pcall(write_net_damage, health)

		if not ok then
			warn_once("the health of a strong enemy could not be sent: " .. tostring(err))
		end
	end
end

Tuning.network_scale = function (health)
	local entry = net_scale[health]

	return entry and entry.k or 1
end

-- Host, for the state sent to the other players: { { game object id, real maximum }, ... } of the living divided units (16 at most)
Tuning.health_layer_list = function ()
	local spawner = Managers.state and Managers.state.unit_spawner
	local list = {}

	if not spawner then
		return nil
	end

	for health, entry in pairs(net_scale) do
		if not alive(entry.unit) then
			net_scale[health] = nil
		elseif #list < 16 then
			local ok, id = pcall(spawner.game_object_id, spawner, entry.unit)

			if ok and id then
				list[#list + 1] = { id, math.floor(entry.max + 0.5) }
			end
		end
	end

	return #list > 0 and list or nil
end

-- A client: the list the host sent (replaces the last one; nothing = no divided unit)
Tuning.receive_health_layers = function (list)
	local map = {}

	if type(list) == "table" then
		for i = 1, math.min(#list, 16) do
			local item = list[i]
			local id = type(item) == "table" and tonumber(item[1])
			local max = type(item) == "table" and tonumber(item[2])

			if id and max and max == max and max > 0 and max < 1e12 then
				map[math.floor(id)] = max
			end
		end
	end

	true_max_by_id = map
end

-- The real maximum health of a divided unit (host: its own record; a client: what the host sent), nil for any other unit
Tuning.true_max_health = function (unit, health)
	local entry = health and net_scale[health]

	if entry then
		return entry.max
	end

	local spawner = Managers.state and Managers.state.unit_spawner
	local ok, id = false, nil

	if spawner and next(true_max_by_id) ~= nil then
		ok, id = pcall(spawner.game_object_id, spawner, unit)
	end

	return ok and id and true_max_by_id[id] or nil
end

-- Health in bars of `size`: how many full bars are still behind the one shown, and how full the one shown is (0..1). The first
-- bars are full ones; the last bar holds what is left over (450k in bars of 130k: x3, and the last of them not full).
Tuning.health_layers = function (max, current, size)
	max, current, size = tonumber(max), math.max(0, tonumber(current) or 0), tonumber(size)

	if not max or max <= 0 then
		return 0, 0
	end

	if not size or size <= 0 or max <= size then
		return 0, math.max(0, math.min(1, current / max))
	end

	local bars = math.ceil(max / size)
	local lost = math.max(0, max - current)
	local index = math.min(bars - 1, math.floor(lost / size))

	if index < bars - 1 then
		return bars - 1 - index, math.max(0, math.min(1, 1 - (lost - index * size) / size))
	end

	return 0, math.max(0, math.min(1, current / (max - (bars - 1) * size)))
end

-- The boss bars (HudElementBossHealth.update, every machine): a divided unit's bar shows the bar it is on and "xN" beside its name
local function layered_proxy(target, real)
	return setmetatable({
		current_health_percent = function ()
			return target._rw_fraction or real:current_health_percent()
		end,
	}, {
		__index = function (_, key)
			local value = real[key]

			if type(value) == "function" then
				return function (_, ...)
					return value(real, ...)
				end
			end

			return value
		end,
	})
end

local function fresh_bar_logic(element, target)
	local ok, Logic = pcall(require, "scripts/ui/hud/elements/hud_health_bar_logic")
	local ok_settings, Settings = pcall(require, "scripts/ui/hud/elements/boss_health/hud_element_boss_health_settings")

	if ok and ok_settings and Logic and Logic.new then
		target.health_bar_logic = Logic:new(Settings)
	end

	element._force_update = true
end

Tuning.layer_boss_targets = function (element)
	local size = Tuning.network_health_max()

	for _, target in ipairs(element._active_targets_array or {}) do
		local real = target._rw_health or target.health_extension
		local max = real and size and Tuning.true_max_health(target.unit, real)

		if max and max > size then
			if not target._rw_health then
				target._rw_health = real
				target._rw_name = target.localized_display_name
				target.health_extension = layered_proxy(target, real)

				-- a client compared the divided maximum with the normal health and called the boss "Weakened": read it again
				local boss, breed = target.boss_extension, target.breed

				if real:max_health() < max and boss and breed and not breed.ignore_weakened_boss_name then
					pcall(function ()
						if not (boss.is_empowered and boss:is_empowered()) and max >= Tuning.normal_health(breed.name) then
							target._rw_name = " " .. Localize(boss:display_name())
						end
					end)
				end
			end

			local behind, fraction = Tuning.health_layers(max, real:current_health_percent() * max, size)

			target._rw_fraction = fraction

			if target._rw_behind ~= behind then
				if target._rw_behind then
					fresh_bar_logic(element, target)
				end

				target._rw_behind = behind
				target.localized_display_name = behind > 0 and string.format("%s  x%d", target._rw_name or "", behind) or target._rw_name
			end
		end
	end
end

Tuning.boss_bar_update = function (func, self, ...)
	if not Tuning.dead then
		local ok, err = pcall(Tuning.layer_boss_targets, self)

		if not ok then
			warn_once("the boss bar could not show its bars: " .. tostring(err))
		end
	end

	return func(self, ...)
end

-- --------------------------------------------------------------------------------------------- the On Fire look, kept on
-- (2026-10-05, the user: "the burning only lasts 1 s when the monster spawns; make it last while it is alive") The modifier's
-- burning look is the game's ailment effect "burning": the buff starts it once (MinionBuffExtension._start_fx ->
-- Ailment.play_ailment_effect_template) and the material shows it for its duration (2 s) from its start time. Every machine
-- keeps the duration ahead of the clock while the unit lives (the same material value, the start unchanged); once it dies or
-- the buff ends it fades as the game's own does, GLOW_TAIL seconds later. Any On Fire enemy, the game's Havoc ones included.
local glowing = setmetatable({}, { __mode = "k" }) -- unit -> { since = world time the look started }
local glow_timer, GLOW_STEP, GLOW_TAIL = 0, 0.5, 3
Tuning.GLOW_TEMPLATE = "common_minion_on_fire"

local function world_time(unit)
	return World.time(Unit.world(unit))
end

Tuning.on_minion_fx = function (self, template, started)
	local unit = self and self._unit

	if Tuning.dead or not unit or type(template) ~= "table" or template.name ~= Tuning.GLOW_TEMPLATE then
		return
	end

	if not started then
		glowing[unit] = nil
	elseif not glowing[unit] then
		local ok, t = pcall(world_time, unit)

		glowing[unit] = { since = ok and t or nil }
	end
end

local function keep_glow(unit, entry)
	local Settings = require("scripts/settings/ailments/ailment_settings")
	local template = Settings.effect_templates and Settings.effect_templates.burning
	local t = world_time(unit)

	entry.since = entry.since or t
	Unit.set_vector3_for_materials(unit, "offset_time_duration", Vector3(template and template.offset_time or 1.2, entry.since, t - entry.since + GLOW_TAIL), true)
end

Tuning.update_glow = function (dt)
	if next(glowing) == nil then
		glow_timer = 0

		return
	end

	glow_timer = glow_timer + (dt or 0)

	if glow_timer < GLOW_STEP then
		return
	end

	glow_timer = 0

	for unit, entry in pairs(glowing) do
		if not alive(unit) or (HEALTH_ALIVE and not HEALTH_ALIVE[unit]) then
			glowing[unit] = nil
		else
			local ok, err = pcall(keep_glow, unit, entry)

			if not ok then
				glowing[unit] = nil
				warn_once("the On Fire look could not be kept on: " .. tostring(err))
			end
		end
	end
end

Tuning.glow_count = function ()
	local n = 0

	for _ in pairs(glowing) do
		n = n + 1
	end

	return n
end

-- Applies the custom mods `tune` ({ speed = 120, ... }, percent) to a unit that has just spawned. Every step is guarded:
-- a step that fails is logged once and never breaks the wave or the other steps.
Tuning.apply = function (unit, tune, breed_name)
	if Tuning.dead or not unit or not tune then
		return
	end

	local label = tostring(breed_name or "enemy")

	-- health: the spawn parameter already went in, make it exact (see set_exact_health above)
	local health_factor = Tuning.health_modifier(tune)

	if health_factor then
		local ok, err = pcall(Tuning.set_exact_health, unit, breed_name, health_factor)

		if not ok then
			warn_once(string.format("the exact health of %s was not set: %s", label, tostring(err)))
		end
	end

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

					write_stat(stat_buffs, keys[k], value)
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

		-- the first three units of a breed are written to the log: what was written and what the stats say right after
		if (apply_logged[label] or 0) < 3 and mod.info then
			apply_logged[label] = (apply_logged[label] or 0) + 1

			local parts = {}

			for key, factor in pairs(record.mult) do
				parts[#parts + 1] = string.format("%s x%.2f (stat now %s)", key, factor, tostring(record.ext:stat_buffs()[key]))
			end

			table.sort(parts)
			pcall(mod.info, mod, "RealmsWaves: custom stats written on %s: %s", label, table.concat(parts, ", "))
		end
	end

	-- size
	local size = tonumber(tune.size)

	if size and size ~= 100 and size == size then
		local ok, err = pcall(function ()
			set_scale(unit, size)

			sized[unit] = size

			local id = network_id(unit)

			if id then
				scaled[id] = { unit = unit, pct = size }
				queue_size(id, size)
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

		if record.recomputed or now ~= record.last[key] then
			local value = now * factor

			write_stat(stat_buffs, key, value)
			record.last[key] = value
		end
	end

	record.recomputed = nil
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

-- The explosion of a burster. The game builds it from fixed templates (radius 6 m, 3 m close), so a bigger model got the
-- bigger danger zone (the model's own effect scales with it) but the same blast. For a unit with a custom size the
-- templates of the action are swapped for copies with every radius multiplied by the size, for the one call that makes
-- the explosion (it is synchronous: Explosion.create_explosion runs inside enter), and put back at once.
-- the name of the breed of a unit ("?" when it cannot be read)
local function breed_name(unit)
	local ok, name = pcall(function ()
		local data = ScriptUnit.has_extension(unit, "unit_data_system")
		local breed = data and data:breed()

		return breed and breed.name
	end)

	return ok and name or "?"
end

local RADIUS_KEYS = { "radius", "min_radius", "close_radius", "min_close_radius" }

local function scaled_template(template, factor)
	if type(template) ~= "table" then
		return template
	end

	local copy = {}

	for key, value in pairs(template) do
		copy[key] = value
	end

	for i = 1, #RADIUS_KEYS do
		local key = RADIUS_KEYS[i]
		local value = template[key]

		if type(value) == "number" then
			copy[key] = value * factor_for_size(factor)
		elseif type(value) == "table" then
			local list = {}

			for index, entry in pairs(value) do
				list[index] = type(entry) == "number" and entry * factor_for_size(factor) or entry
			end

			copy[key] = list
		end
	end

	return copy
end

Tuning.scaled_template = scaled_template

Tuning.explosion_enter = function (func, self, unit, breed, blackboard, scratchpad, action_data, t)
	local pct = not Tuning.dead and unit ~= nil and sized[unit] or nil

	if not pct or type(action_data) ~= "table" then
		return func(self, unit, breed, blackboard, scratchpad, action_data, t)
	end

	local normal, mild = action_data.explosion_template, action_data.explosion_template_mild
	local ok, err = pcall(function ()
		action_data.explosion_template = scaled_template(normal, pct / 100)
		action_data.explosion_template_mild = scaled_template(mild, pct / 100)
	end)

	if not ok then
		action_data.explosion_template, action_data.explosion_template_mild = normal, mild
		warn_once(string.format("the explosion could not be scaled: %s", tostring(err)))

		return func(self, unit, breed, blackboard, scratchpad, action_data, t)
	end

	local done, result = pcall(func, self, unit, breed, blackboard, scratchpad, action_data, t)

	action_data.explosion_template, action_data.explosion_template_mild = normal, mild

	if not done then
		error(result, 0)
	end

	return result
end

-- What a tuned unit read when it started shooting (MinionAttack.start_shooting, after it ran): the first three of every
-- breed go to the log, the last of each unit is kept for /rw_tune.
Tuning.on_start_shooting = function (unit, scratchpad, t, action_data)
	if Tuning.dead or type(scratchpad) ~= "table" then
		return
	end

	pcall(function ()
		local record = record_of(unit)

		if not record then
			return
		end

		local wait = type(scratchpad.next_shoot_timing) == "number" and type(t) == "number" and scratchpad.next_shoot_timing - t or nil

		last_shot[unit] = { speed = scratchpad.shoot_attack_speed, shots = scratchpad.num_shots, wait = wait }

		local name = breed_name(unit)

		if (shoot_logged[name] or 0) < 3 then
			shoot_logged[name] = (shoot_logged[name] or 0) + 1

			if mod.info then
				mod:info("RealmsWaves: %s started shooting: speed x%s, %s shots, first shot in %s s", name, tostring(scratchpad.shoot_attack_speed), tostring(scratchpad.num_shots), tostring(wait))
			end
		end
	end)
end

-- ------------------------------------------------------------------------------------------------------------- summoners
-- (2026-10-04, the user's crash on Restart and an error on a despawn key, and a Packmaster of a wave that "was not moving, no aggro")
--
-- 1. The game's summon action summons in its `leave` even when the unit is being DESTROYED (despawned, the mission torn down):
--    BtSummonMinionsAction.leave calls _summon_minions when the summon had not happened yet. During a mission's cleanup that spawns
--    a minion with no camera left (crash: camera_manager.lua "bad argument #1 to 'camera'"), and on a despawn it fails in
--    flood_fill_from_position. A unit being destroyed now never summons (any summoner, the mod's or the game's).
-- 2. The Packmaster (chaos_ogryn_houndmaster) is made for the game's hound mutator: it summons its hounds PASSIVE and leads them on
--    a patrol, and its tree puts the summon before combat. Spawned alone by a wave it could stand in its patrol and idle. For a
--    summoner of a wave (Bypass-tracked): no patrol setup, its summoned minions are aggroed, and once a second it is made to fight
--    again if it lost its aggro or its target (MinionPerceptionExtension.aggro, force_new_target_attempt).
Tuning.SUMMONERS = { chaos_ogryn_houndmaster = true, renegade_radio_operator = true }
local summoners = setmetatable({}, { __mode = "k" })
local summoner_timer = 0

local function ours(unit)
	local bypass = mod.rw and mod.rw.bypass

	return unit ~= nil and bypass ~= nil and bypass.is_tracked ~= nil and bypass.is_tracked(unit) == true
end

-- aggroed, with a living target (a new one is asked for when it has none)
local function engage(unit)
	local perception = ScriptUnit.has_extension(unit, "perception_system")

	if not perception or not perception.aggro then
		return false
	end

	if perception:aggro_state() ~= "aggroed" then
		perception:aggro()
	end

	local blackboard = BLACKBOARDS and BLACKBOARDS[unit]
	local target = blackboard and blackboard.perception and blackboard.perception.target_unit

	if (not target or not (HEALTH_ALIVE and HEALTH_ALIVE[target])) and perception.force_new_target_attempt then
		perception:force_new_target_attempt()
	end

	return true
end

Tuning.engage = engage

Tuning.summon_leave = function (func, self, unit, breed, blackboard, scratchpad, action_data, t, reason, destroy)
	if destroy and type(scratchpad) == "table" then
		scratchpad.summoned_success = true
	end

	return func(self, unit, breed, blackboard, scratchpad, action_data, t, reason, destroy)
end

Tuning.patrol_setup = function (func, self, unit, ...)
	if ours(unit) then
		return
	end

	return func(self, unit, ...)
end

Tuning.after_summon = function (self, unit, breed, blackboard, scratchpad)
	if Tuning.dead or not ours(unit) or type(scratchpad) ~= "table" then
		return
	end

	local extension = scratchpad.summoned_minions_extension
	local ok, minions = pcall(function () return extension and extension:summoned_minions() or {} end)

	for _, minion in ipairs(ok and minions or {}) do
		pcall(engage, minion)
	end

	pcall(engage, unit)
end

-- ------------------------------------------------------------------------------------------------------------- On Fire damage
-- (2026-10-04, the user: "its damage is too high, let me set it beside the modifier") The game's On Fire modifier
-- (common_minion_on_fire, havoc_buff_templates.lua) puts players within 1 m of the enemy on fire every half second
-- (hit_by_common_enemy_flame, whose interval hurts them by Attack.execute with a power level). A group's `burn` (percent, set on
-- the Mods screen) scales that power level for the players its enemies set on fire: the minion's interval marks the players it
-- burns with its share (the player buff extension's add_internally_controlled_buff, seen while the minion's interval runs), and
-- the player's burn uses the share it was given last (for 1.5 s). 0 = the burn does no damage. The host decides damage.
local burn_share = setmetatable({}, { __mode = "k" }) -- player -> { share, time }
local burning_share = nil -- the share of the enemy whose interval is running now
local BURN_FRESH = 1.5

local function now()
	return Managers.time and Managers.time.has_timer and Managers.time:has_timer("gameplay") and Managers.time:time("gameplay") or os.clock()
end

Tuning.fire_share = function (unit)
	return fire_share[unit]
end

-- A wave's enemy given the On Fire modifier (execute.lua): its burn's share, the group's `burn` or Tuning.BURN_DEFAULT percent
-- (2026-10-05, the user: "make the default 35%"). The game's own On Fire enemies (Havoc) keep the game's damage.
Tuning.BURN_DEFAULT = 35

Tuning.mark_fire = function (unit, tune)
	if Tuning.dead or not unit then
		return
	end

	local burn = tonumber(tune and tune.burn) or Tuning.BURN_DEFAULT

	fire_share[unit] = math.max(0, burn) / 100
end

-- the share of the burn a player is under now (nil: the game's own damage)
Tuning.burn_share = function (player_unit)
	local mark = burn_share[player_unit]

	if mark and now() - mark[2] <= BURN_FRESH then
		return mark[1]
	end

	return nil
end

Tuning.wrap_fire_templates = function (templates)
	local minion, burn = templates and templates.common_minion_on_fire, templates and templates.hit_by_common_enemy_flame

	if not minion or not burn or minion.__rw_wrapped then
		return false
	end

	minion.__rw_wrapped = true

	local minion_interval, burn_interval = minion.interval_func, burn.interval_func

	minion.interval_func = function (template_data, template_context, ...)
		burning_share = fire_share[template_context and template_context.unit]

		local ok, err = pcall(minion_interval, template_data, template_context, ...)

		burning_share = nil

		if not ok then
			error(err)
		end
	end

	burn.interval_func = function (template_data, template_context, ...)
		local share = not Tuning.dead and template_context and Tuning.burn_share(template_context.unit)

		if not share then
			return burn_interval(template_data, template_context, ...)
		end

		if share <= 0 then
			return
		end

		-- the game's own burn (minion_buff_templates.lua hit_by_common_enemy_flame) with the power level scaled
		local unit = template_context.unit

		if HEALTH_ALIVE[unit] then
			local Attack = require("scripts/utilities/attack/attack")
			local DamageProfileTemplates = require("scripts/settings/damage/damage_profile_templates")
			local MinionDifficultySettings = require("scripts/settings/difficulty/minion_difficulty_settings")
			local power_level = Managers.state.difficulty:get_table_entry_by_challenge(MinionDifficultySettings.power_level.chaos_engulfed_enemy_fire_attack)
			local owner = template_context.is_server and template_context.owner_unit or nil

			Attack.execute(unit, DamageProfileTemplates.horde_flame_impact, "power_level", power_level * share, "damage_type", "burning", "attacking_unit", owner)
		end
	end

	return true
end

-- a player buff extension is given the burn while a scaled enemy's interval runs: the player keeps that enemy's share
Tuning.on_player_buff_added = function (self, template_name)
	if burning_share and template_name == "hit_by_common_enemy_flame" and self and self._unit then
		local mark = burn_share[self._unit] or {}

		mark[1], mark[2] = burning_share, now()
		burn_share[self._unit] = mark
	end
end

-- a summoner a wave spawned (execute.lua spawn_one)
Tuning.watch_summoner = function (unit, breed_name)
	if unit and Tuning.SUMMONERS[breed_name] then
		summoners[unit] = true
	end
end

Tuning.summoner_count = function ()
	local n = 0

	for _ in pairs(summoners) do n = n + 1 end

	return n
end

local function keep_summoners(dt)
	summoner_timer = summoner_timer + dt

	if summoner_timer < 1 then
		return
	end

	summoner_timer = 0

	for unit in pairs(summoners) do
		if not (HEALTH_ALIVE and HEALTH_ALIVE[unit]) or not Unit.alive(unit) then
			summoners[unit] = nil
		else
			local ok, err = pcall(engage, unit)

			if not ok then
				warn_once("a summoner was not kept fighting: " .. tostring(err))
			end
		end
	end
end

Tuning.install = function ()
	if installed or not mod.hook_safe then
		return
	end

	installed = true

	if mod.hook then
		mod:hook("BtChaosPoxwalkerExplodeAction", "enter", function (func, ...)
			return Tuning.explosion_enter(func, ...)
		end)
		mod:hook("BtSummonMinionsAction", "leave", function (...)
			return Tuning.summon_leave(...)
		end)
		mod:hook("BtSummonMinionsAction", "_patrol_setup", function (...)
			return Tuning.patrol_setup(...)
		end)
	end

	mod:hook_safe("BtSummonMinionsAction", "_summon_minions", function (...)
		Tuning.after_summon(...)
	end)

	-- On Fire damage: the burn templates are wrapped once; the player buff extension tells which player an enemy set on fire
	if mod.hook_require then
		mod:hook_require("scripts/settings/buff/buff_templates", function (templates)
			if not Tuning.dead then
				pcall(Tuning.wrap_fire_templates, templates)
			end
		end)
	end

	mod:hook_safe("PlayerUnitBuffExtension", "add_internally_controlled_buff", function (self, template_name)
		Tuning.on_player_buff_added(self, template_name)
	end)

	-- the On Fire look kept on (every machine)
	mod:hook_safe("MinionBuffExtension", "_start_fx", function (self, index, template)
		Tuning.on_minion_fx(self, template, true)
	end)
	mod:hook_safe("MinionBuffExtension", "_stop_fx", function (self, index, template)
		Tuning.on_minion_fx(self, template, false)
	end)

	-- health above the network's limit: the divided damage goes on the network after every write of the game (host)
	for _, method in ipairs({ "add_damage", "add_heal", "set_health_instant" }) do
		mod:hook_safe("HealthExtension", method, function (self)
			Tuning.after_health_write(self)
		end)
	end

	-- ...and the boss bars show it in bars (every machine)
	if mod.hook_require and mod.hook then
		local hooked_bars = setmetatable({}, { __mode = "k" })

		mod:hook_require("scripts/ui/hud/elements/boss_health/hud_element_boss_health", function (HudElementBossHealth)
			if Tuning.dead or type(HudElementBossHealth) ~= "table" or hooked_bars[HudElementBossHealth] then return end

			hooked_bars[HudElementBossHealth] = true
			mod:hook(HudElementBossHealth, "update", function (func, self, ...)
				return Tuning.boss_bar_update(func, self, ...)
			end)
		end)
	end

	if mod.hook_require then
		-- DMF runs this every time the game loads the file again (at every game start): the same table is hooked once only, or DMF
		-- warns "Attempting to rehook active hook [start_shooting]" (seen 2026-10-04)
		local hooked_attack = setmetatable({}, { __mode = "k" })

		mod:hook_require("scripts/utilities/minion_attack", function (MinionAttack)
			if Tuning.dead or hooked_attack[MinionAttack] then return end

			hooked_attack[MinionAttack] = true
			mod:hook_safe(MinionAttack, "start_shooting", function (...)
				Tuning.on_start_shooting(...)
			end)
		end)
	end

	mod:hook_safe("BtMeleeAttackAction", "_start_attack_anim", function (...)
		Tuning.fix_attack_end(...)
	end)

	-- the unit's own class is the one that matters: the game's class() copies the methods of the parent into the subclass
	-- when it is created, so MinionBuffExtension keeps calling its own copy and the hook on BuffExtensionBase may never
	-- see a minion (the console log of 2026-10-02 showed exactly that: the factor was gone at every burst under Havoc).
	-- Both are hooked; putting the factor back is idempotent, so a unit that reaches both is not touched twice.
	local function after_recompute(self)
		if Tuning.dead then
			return
		end

		local record = tuned_by_extension[self]

		if record then
			reassert_record(record, self)
		end
	end

	mod:hook_safe("BuffExtensionBase", "_update_stat_buffs_and_keywords", after_recompute)
	mod:hook_safe("MinionBuffExtension", "_update_stat_buffs_and_keywords", after_recompute)
	mod:hook_safe("MinionBuffExtension", "_reset_stat_buffs", function (self)
		local record = not Tuning.dead and tuned_by_extension[self]

		if record then
			-- A fresh engine value may equal the last tuned value numerically. It still needs our factor once.
			record.recomputed = true
		end
	end)
end

Tuning.retire = function ()
	Tuning.dead = true
	Tuning.reset()
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

	for unit in pairs(sized) do
		if not alive(unit) then
			sized[unit] = nil
		end
	end
end

local function send_batches(list, recipient)
	if not Protocol or not Protocol.send_scales or not Protocol.is_available() then
		return false
	end

	local from = 1

	while from <= #list do
		local batch = {}

		for i = from, math.min(from + SEND_BATCH - 1, #list) do
			batch[#batch + 1] = list[i]
		end

		-- a peer that left or a network that fails is not our business: skip the rest, never break the frame
		local ok, sent, err = pcall(Protocol.send_scales, batch, recipient)

		if not ok or sent ~= true then
			err = not ok and sent or err
			warn_once(string.format("sizes could not be sent to the other players: %s", tostring(err)))

			return false, err
		end

		from = from + SEND_BATCH
	end

	return true
end

-- Host, every frame (cheap: two counters until something is due).
Tuning.update = function (dt)
	if Tuning.dead then return end

	Tuning.update_glow(dt)

	keep_summoners(dt)

	timer = timer + dt
	send_timer = send_timer + dt

	if timer >= UPDATE_INTERVAL then
		timer = 0

		if #tuned > 0 or next(scaled) ~= nil or next(sized) ~= nil then
			reassert()
		end
	end

	if send_timer >= SEND_INTERVAL then
		send_timer = 0

		if #outbox > 0 then
			local pending = outbox
			outbox, outbox_by_id = {}, {} -- preserve new sizes queued by synchronous callbacks
			local list, seen = {}, {}

			for i = 1, #pending do
				local item = pending[i]
				local entry = scaled[item[1]]

				if entry and alive(entry.unit) and not seen[item[1]] then
					seen[item[1]] = true
					item[2] = entry.pct
					list[#list + 1] = item
				end
			end

			-- Retry failures next cadence. Prune dead units and duplicates so an outage cannot grow the queue forever.
			if not send_batches(list) then
				for i = 1, #list do
					local id = list[i][1]
					local entry = scaled[id]

					if entry and alive(entry.unit) then queue_size(id, entry.pct) end
				end
			end
		end
	end
end

-- Host: a player joined late; tell it the size of every living unit that has one.
Tuning.send_all = function (peer_id)
	if Tuning.dead then return end

	local list = {}

	for id, entry in pairs(scaled) do
		if alive(entry.unit) then
			list[#list + 1] = { id, entry.pct }
		end
	end

	local sent, err = send_batches(list, peer_id)

	if not sent and err ~= "target_rpc_unsupported" then
		for i = 1, #list do
			local id = list[i][1]
			local entry = scaled[id]

			if entry and alive(entry.unit) then queue_size(id, entry.pct) end
		end
	end
end

-- ----------------------------------------------------------------------------------------- the clients
-- `entries` = { { id = network id, pct = percent }, ... }, already validated by the protocol.
Tuning.receive = function (entries)
	if Tuning.dead then return end

	for i = 1, #(entries or {}) do
		local entry = entries[i]
		local pending = inbox_by_id[entry.id]

		if pending then
			pending.pct, pending.age = entry.pct, 0
		elseif #inbox < MAX_PENDING then
			pending = { id = entry.id, pct = entry.pct, age = 0 }
			inbox[#inbox + 1] = pending
			inbox_by_id[entry.id] = pending
		end
	end
end

-- A client, every frame: puts the sizes on the units that have arrived here by now.
Tuning.update_client = function (dt)
	if Tuning.dead then
		return
	end

	Tuning.update_glow(dt)

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
		local done = false

		if ok and exists then
			local got, unit = pcall(spawner.unit, spawner, entry.id)

			if got and unit and alive(unit) then
				local applied, err = pcall(set_scale, unit, entry.pct)
				done = applied

				if not applied then
					warn_once(string.format("a size sent by the host could not be applied: %s", tostring(err)))
				end
			elseif got and unit then
				done = true -- dead unit: there is nothing left to resize
			end
		end

		if done or entry.age > PENDING_TIMEOUT then
			inbox_by_id[entry.id] = nil
			inbox[i] = inbox[#inbox]
			inbox[#inbox] = nil
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

-- Lines for /rw_tune: every living tuned unit (one per breed), what was written and what its stats say now.
Tuning.describe = function ()
	local lines = {}
	local seen = {}

	for i = 1, #tuned do
		local record = tuned[i]
		local unit = record.unit
		local name = breed_name(unit)

		if not seen[name] and alive(unit) then
			seen[name] = true

			local parts = {}
			local buffs = ScriptUnit.has_extension(unit, "buff_system")
			local stats = buffs and buffs.stat_buffs and buffs:stat_buffs() or {}

			for key, factor in pairs(record.mult) do
				parts[#parts + 1] = string.format("%s written x%.2f, now %s", key, factor, tostring(stats[key]))
			end

			table.sort(parts)

			local shot = last_shot[unit]

			lines[#lines + 1] = string.format("%s: %s%s", name, table.concat(parts, "; "), shot and string.format("; last shooting start: speed x%s, %s shots, first shot in %s s", tostring(shot.speed), tostring(shot.shots), tostring(shot.wait)) or "; has not started shooting")
		end
	end

	if #lines == 0 then
		lines[1] = "No living unit with a custom stat (time between attacks, fire rate, burst, explosion, damage over time) right now."
	end

	return lines
end

Tuning.status = function ()
	return { tuned = #tuned, sizes_known = (function () local n = 0 for _ in pairs(scaled) do n = n + 1 end return n end)(), unsent = #outbox, pending = #inbox }
end

Tuning.reset = function ()
	tuned, scaled, outbox, inbox = {}, {}, {}, {}
	outbox_by_id = {}
	inbox_by_id = {}
	sized = {}
	tuned_by_extension = {}
	timer, send_timer = 0, 0
	true_max_by_id = {}
	glowing = setmetatable({}, { __mode = "k" })
	glow_timer = 0
end

return Tuning
