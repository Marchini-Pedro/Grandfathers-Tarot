-- Twins (2026-10-07, the user: "merge the entire SoloPlayPurpleStimms into Tarot and rename it to Twins"). Everything the
-- SoloPlayPurpleStimms mod did, now part of The Grandfather's Tarot, its settings under the "tw_" prefix:
--   * the "Twins" condition for SoloPlay (Havoc conditions and normal mission conditions): stimmed enemies use the purple stim and
--     split into two other enemies when they die, per boss and enemy as set in the mod options (chance, the two enemies, whether
--     they carry the stimm again), with the loop check, Don't Re-Stim and Hide From Guests;
--   * the stimm colour and the split smoke (twins/cosmetics.lua), per player;
--   * and, new, the Twins modifier of a card's row: that row's enemies split into the row's OWN twins (catalog/groups.lua
--     part.twins: two enemies or none, each splitting again or not and keeping the row's mods or not, up to 5 generations), spawned
--     by the mod itself (Execute.spawn_twin), not through the game's queue.
--
-- Nothing custom is networked: the buff is the game's own purple buff, the condition travels as the game's own stimmed condition.
-- This file runs at mod load, before gameplay classes are safe to require, so every class is patched through hook_require.
local mod = get_mod("GrandfathersTarot")

local BASE = "GrandfathersTarot/scripts/mods/GrandfathersTarot"

local Twins = {}

-- The condition id keeps its original name so a selection already saved in SoloPlay's settings still resolves.
local CIRCUMSTANCE_NAME = "rift_warp_01"
local PURPLE_MUTATOR_NAME = "mutator_stimmed_minions_purple"
local TRIGGER_MUTATOR_NAME = "mutator_stimmed_minions_purple_trigger"
local PURPLE_BUFF = "mutator_stimmed_minion_purple"
local PURPLE_BUFFS = { PURPLE_BUFF }
local MODIFIER_ID = "purple_stimm" -- the Twins modifier of a card's row (catalog/groups.lua)
-- What other players see: the custom condition never leaves the host; it travels as the game's own stimmed condition.
local CARRIER_CIRCUMSTANCE = "mutator_stimmed_minions"
local CARRIER_MUTATOR = "mutator_stimmed_minions"
-- MutatorPurpleStimmed keeps a 256 slot ring buffer; stop feeding it long before it wraps. The card rows' own queue too.
local SPAWN_QUEUE_LIMIT = 48
-- a card row's twin waiting for room (Max card enemies alive) is dropped after this long
local TWIN_WAIT = 10
local TWINS_PER_UPDATE = 4
Twins.MAX_GENERATIONS = 5

local catalog, cosmetics = nil, nil
local Execute, Positions = nil, nil
local installed = false

Twins.init = function (deps)
	Execute = deps.execute
	Positions = deps.positions
end

Twins.is_installed = function ()
	return installed
end

Twins.catalog = function ()
	return catalog
end

-- ####################################################################################################
-- ##### Settings ######################################################################################
-- ####################################################################################################

-- per breed: { enabled, chance (percent), twin1, twin2 ("default" | "none" | breed), twins_buff ("default" | "always" | "never") }.
-- The defaults are the game's own: see twins/catalog.lua.
local config_cache = {}

local function default_config(entry)
	return { enabled = entry.enabled, chance = entry.chance, twin1 = entry.twin1 or "default", twin2 = entry.twin2 or "default", twins_buff = entry.twins_buff or "default" }
end

local function config_of(breed_name)
	local cached = config_cache[breed_name]

	if cached then
		return cached
	end

	local entry = catalog and catalog.by_id[breed_name]

	if not entry then
		return nil
	end

	local config = default_config(entry)
	local saved = mod:get("tw_cfg_" .. breed_name)

	if type(saved) == "table" then
		for key in pairs(config) do
			if saved[key] ~= nil then
				config[key] = saved[key]
			end
		end

		-- earlier versions stored an on/off toggle called twins_stimmed
		if saved.twins_buff == nil and saved.twins_stimmed == false then
			config.twins_buff = "never"
		end
	end

	config_cache[breed_name] = config

	return config
end

local function save_config(breed_name)
	local config = config_cache[breed_name]

	if config then
		mod:set("tw_cfg_" .. breed_name, config, false)
	end
end

-- probability (0..1) that a spawned/aggroed enemy of this breed gets the purple stim under the condition
local function affect_chance(breed_name)
	local entry = catalog.by_id[breed_name]
	local config = entry and config_of(breed_name)

	if not config or not config.enabled then
		return 0
	end

	local chance = (config.chance or 0) / 100

	if entry.boss then
		if not mod:get("tw_bosses_enabled") then
			return 0
		end

		chance = chance * ((mod:get("tw_bosses_chance") or 100) / 100)
	end

	return chance
end

-- the two breeds a dying enemy of this breed is split into (nil = nothing in that slot)
local function twin_breed(breed_name, config, slot)
	local choice = slot == 1 and config.twin1 or config.twin2

	if choice == "none" then
		return nil
	end

	if choice == "default" or not catalog.by_id[choice] then
		return catalog.default_twins[breed_name]
	end

	return choice
end

-- can a spawned enemy of this breed split again?
local function has_split_rule(breed_name)
	local config = config_of(breed_name)

	if not config then
		return catalog.default_twins[breed_name] ~= nil
	end

	return twin_breed(breed_name, config, 1) ~= nil or twin_breed(breed_name, config, 2) ~= nil
end

-- does the enemy spawned as `twin` carry the purple stimm?  default: like the game, only when it can split again
local function twin_gets_buff(config, twin)
	if config.twins_buff == "always" then
		return true
	elseif config.twins_buff == "never" then
		return false
	end

	return has_split_rule(twin)
end

-- the breeds a dying enemy of this breed passes the buff (and so the chain) on to
local function chain_children(breed_name)
	local config = config_of(breed_name)
	local children = {}

	if not config then
		return children
	end

	for slot = 1, 2 do
		local twin = twin_breed(breed_name, config, slot)

		if twin and twin_gets_buff(config, twin) and has_split_rule(twin) then
			children[#children + 1] = twin
		end
	end

	return children
end

-- Infinite spawn loop check: a path start -> ... -> start through chain_children means each death keeps producing stimmed enemies
-- that split again, forever. Returns the path, or nil.
local function find_loop(start_breed)
	local path, visited = { start_breed }, { [start_breed] = true }

	local function search(breed_name)
		for _, child in ipairs(chain_children(breed_name)) do
			if child == start_breed then
				return true
			end

			if not visited[child] then
				visited[child] = true
				path[#path + 1] = child

				if search(child) then
					return true
				end

				path[#path] = nil
			end
		end

		return false
	end

	if search(start_breed) then
		path[#path + 1] = start_breed

		return path
	end

	return nil
end

local function loop_check_enabled()
	return mod:get("tw_loop_check") ~= false
end

-- ####################################################################################################
-- ##### Options menu (one set of widgets per dropdown, values swapped on selection) #################
-- ####################################################################################################

local WIDGET_IDS = {
	boss = { enabled = "tw_boss_enabled", chance = "tw_boss_chance", twin1 = "tw_boss_twin1", twin2 = "tw_boss_twin2", twins_buff = "tw_boss_twins_buff" },
	enemy = { enabled = "tw_enemy_enabled", chance = "tw_enemy_chance", twin1 = "tw_enemy_twin1", twin2 = "tw_enemy_twin2", twins_buff = "tw_enemy_twins_buff" },
}

local function lists()
	return { boss = catalog.bosses, enemy = catalog.enemies }
end

local function selected_breed(kind)
	local selected = mod:get("tw_" .. kind .. "_selector")

	if selected and catalog.by_id[selected] then
		return selected
	end

	return lists()[kind][1].id
end

local function push_to_widgets(kind, breed_name)
	local config = config_of(breed_name)

	if not config then
		return
	end

	for field, widget_id in pairs(WIDGET_IDS[kind]) do
		mod:set(widget_id, config[field], false)
	end
end

local last_loop_warning

-- GrandfathersTarot.lua's mod.on_setting_changed passes every change here; true when it was one of Twins'
Twins.on_setting_changed = function (id)
	if not installed or type(id) ~= "string" or id:sub(1, 3) ~= "tw_" then
		return false
	end

	if cosmetics.on_setting_changed(id) then
		return true
	end

	if id == "tw_boss_selector" or id == "tw_enemy_selector" then
		local kind = id == "tw_boss_selector" and "boss" or "enemy"
		local breed_name = selected_breed(kind)

		push_to_widgets(kind, breed_name)

		local entry = catalog.by_id[breed_name]

		if kind == "enemy" and entry and not entry.stim then
			mod:notify(mod:localize("tw_warning_no_stim_animation", mod:localize("tw_twin_" .. breed_name)))
		end

		return true
	end

	for kind, ids in pairs(WIDGET_IDS) do
		for field, widget_id in pairs(ids) do
			if widget_id == id then
				local breed_name = selected_breed(kind)
				local config = config_of(breed_name)

				if config then
					config[field] = mod:get(id)
					save_config(breed_name)

					-- a new edge in the spawn graph is the only way to create a loop, and it starts here
					if field == "twin1" or field == "twin2" or field == "twins_buff" then
						local loop = find_loop(breed_name)

						if not loop then
							last_loop_warning = nil
						else
							local names = {}

							for i = 1, #loop do
								names[i] = mod:localize("tw_twin_" .. loop[i])
							end

							local path = table.concat(names, " -> ")
							local check_on = loop_check_enabled()
							local splits_into_itself = #loop == 2
							local splits_into_two = splits_into_itself and twin_breed(breed_name, config, 1) == breed_name and twin_breed(breed_name, config, 2) == breed_name
							local suffix = check_on and "_prevented" or "_unchecked"
							local message_key = splits_into_two and "tw_warning_self_split_two" or splits_into_itself and "tw_warning_self_split_one" or "tw_warning_spawn_loop"
							local warning_key = path .. (check_on and "|on" or "|off") .. "|" .. message_key

							-- editing the second slot of the same loop does not repeat the warning
							if warning_key ~= last_loop_warning then
								last_loop_warning = warning_key
								mod:notify(mod:localize(message_key .. suffix, splits_into_itself and names[1] or path, names[1]))
							end
						end
					end
				end

				return true
			end
		end
	end

	return true
end

-- the widgets keep whatever was shown last; bring them in line with the stored per-breed values
Twins.on_all_mods_loaded = function ()
	if not installed then
		return
	end

	cosmetics.apply_color()

	for kind in pairs(lists()) do
		local selected = selected_breed(kind)

		if mod:get("tw_" .. kind .. "_selector") ~= selected then
			mod:set("tw_" .. kind .. "_selector", selected, false)
		end

		push_to_widgets(kind, selected)
	end
end

-- Options > Twins: Reset everything to default. The defaults are the game's own: every Twins widget's default_value (the data
-- file) and catalog.lua per boss and enemy (the per-breed settings are only stored when they differ, so clearing them is the reset).
local function widget_defaults()
	local data = mod:io_dofile(BASE .. "/GrandfathersTarot_data")
	local defaults = {}

	local function walk(widgets)
		for _, widget in ipairs(widgets or {}) do
			if widget.sub_widgets then
				walk(widget.sub_widgets)
			elseif widget.default_value ~= nil and widget.type ~= "button" and type(widget.setting_id) == "string" and widget.setting_id:sub(1, 3) == "tw_" then
				defaults[widget.setting_id] = widget.default_value
			end
		end
	end

	walk(data and data.options and data.options.widgets)

	return defaults
end

Twins.reset_to_defaults = function ()
	if not installed then
		return
	end

	for setting_id, value in pairs(widget_defaults()) do
		mod:set(setting_id, value, false)
	end

	for breed_name in pairs(catalog.by_id) do
		mod:set("tw_cfg_" .. breed_name, nil, false)
	end

	config_cache = {}
	last_loop_warning = nil
	cosmetics.apply_color()

	for kind in pairs(lists()) do
		push_to_widgets(kind, selected_breed(kind))
	end

	mod:notify(mod:localize("tw_reset_done"))
end

-- ####################################################################################################
-- ##### The card rows' own twins (part.twins of catalog/groups.lua) ##################################
-- ####################################################################################################

-- a card's enemy with the Twins modifier: { breed, cfg = part.twins, gen = its generation (1 = the card's own), row = the row's
-- settings for twins that keep them }. Weak: a despawned unit is forgotten.
local claims = setmetatable({}, { __mode = "k" })
-- twins waiting to be spawned: { entry, position (Vector3Box), rotation (QuaternionBox), target, age }
local queue = {}

-- Called by Execute.spawn_one for every enemy spawned with the Twins modifier.
Twins.claim = function (unit, breed_name, extra)
	if not installed or not unit then
		return
	end

	extra = extra or {}
	claims[unit] = {
		breed = breed_name,
		cfg = extra.twins or {},
		gen = math.max(1, tonumber(extra.twin_gen) or 1),
		row = { mods = extra.mods, tune = extra.tune, appearance = extra.appearance, nodogs = extra.nodogs, noshield = extra.noshield, leaves = extra.leaves, boss_name = extra.boss_name, boss_colour = extra.boss_colour },
	}
end

Twins.is_claimed = function (unit)
	return claims[unit] ~= nil
end

local INVISIBLE_KEYWORDS = { "invisible", "unperceivable" }

-- a player the twins can go for: alive and not invisible (a Zealot's or Psyker's stealth)
local function visible_player(unit)
	if not unit or not ALIVE[unit] then
		return false
	end

	local buffs = ScriptUnit.has_extension(unit, "buff_system")

	if buffs and buffs.has_keyword then
		for i = 1, #INVISIBLE_KEYWORDS do
			local ok, has = pcall(buffs.has_keyword, buffs, INVISIBLE_KEYWORDS[i])

			if ok and has then
				return false
			end
		end
	end

	return true
end

-- Who the twins go for (2026-10-07, the user: "what if its target goes invisible?"): the dying enemy's target while it is alive
-- and seen; otherwise the nearest player who is seen; otherwise the nearest living player (the twins come, and look for whoever
-- they can see). nil only when no player lives.
local function pick_target(target, position)
	if visible_player(target) then
		return target
	end

	local players = Positions and Positions.player_units and Positions.player_units() or {}
	local best_seen, best_seen_d, best_any, best_any_d = nil, math.huge, nil, math.huge

	for i = 1, #players do
		local unit = players[i]

		if ALIVE[unit] then
			local ok, at = pcall(Unit.world_position, unit, 1)
			local d = (ok and position) and Vector3.distance_squared(at, position) or 0

			if d < best_any_d then best_any, best_any_d = unit, d end
			if d < best_seen_d and visible_player(unit) then best_seen, best_seen_d = unit, d end
		end
	end

	return best_seen or best_any
end

Twins.pick_target = pick_target

-- the enemy of a row's twin slot: "none" nothing, a breed that one, nil (or anything unknown) the game's own split of `breed_name`
local function row_twin(cfg, slot, breed_name)
	local choice = cfg[slot == 1 and "a" or "b"]

	if choice == "none" then
		return nil
	end

	if choice and catalog.by_id[choice] then
		return choice
	end

	return catalog.default_twins[breed_name]
end

Twins.row_twin = row_twin

local function without_twins_mod(mods)
	local kept = {}

	for i = 1, #(mods or {}) do
		if mods[i] ~= MODIFIER_ID then kept[#kept + 1] = mods[i] end
	end

	return #kept > 0 and kept or nil
end

-- The queue entry of one twin of a card's row: its enemy, the row's settings when the slot keeps them (Twins taken off), and the
-- Twins modifier with the same row settings, one generation on, when the slot splits again and the generations allow it.
Twins.twin_entry = function (claim, slot)
	local cfg = claim.cfg or {}
	local breed = row_twin(cfg, slot, claim.breed)

	if not breed then
		return nil
	end

	local entry = { breed = breed }
	local row = claim.row or {}

	if cfg[slot == 1 and "ka" or "kb"] then
		entry.mods, entry.tune, entry.appearance = without_twins_mod(row.mods), row.tune, row.appearance
		entry.nodogs, entry.noshield, entry.leaves, entry.boss_name, entry.boss_colour = row.nodogs, row.noshield, row.leaves, row.boss_name, row.boss_colour
	end

	local limit = math.max(1, math.min(Twins.MAX_GENERATIONS, tonumber(cfg.gen) or 1))

	if cfg[slot == 1 and "sa" or "sb"] and claim.gen < limit then
		local mods = {}

		for i = 1, #(entry.mods or {}) do mods[i] = entry.mods[i] end

		mods[#mods + 1] = MODIFIER_ID
		entry.mods = mods
		entry.twins = cfg
		entry.twin_gen = claim.gen + 1
	end

	return entry
end

-- The burst when an enemy splits: the game's purple_stimmed_explosion (a particle, a gas grenade sound, a tiny push). Every machine
-- that plays it applies its own smoke settings (twins/cosmetics.lua).
local function play_split_explosion(world, physics_world, unit)
	local Explosion = require("scripts/utilities/attack/explosion")
	local ExplosionTemplates = require("scripts/settings/damage/explosion_templates")

	Explosion.create_explosion(world, physics_world, POSITION_LOOKUP[unit], Quaternion.look(Vector3.up()), unit, ExplosionTemplates.purple_stimmed_explosion, 0, 1, nil)
end

-- a card row's enemy died: its twins are queued (spawned by Twins.update, host only)
local function split_claimed(unit, claim, blackboard)
	local rotation = Unit.local_rotation(unit, 1)
	local right = Quaternion.right(rotation)
	local base = Unit.world_position(unit, 1)
	local target = pick_target(blackboard.perception and blackboard.perception.target_unit, base)

	if not target then
		return
	end

	local any = false

	for slot = 1, 2 do
		local entry = Twins.twin_entry(claim, slot)

		if entry and #queue < SPAWN_QUEUE_LIMIT then
			local position = slot % 2 == 0 and base + right or base - right

			queue[#queue + 1] = { entry = entry, position = Vector3Box(position), rotation = QuaternionBox(rotation), target = target, age = 0 }
			any = true
		end
	end

	if any and blackboard.spawn then
		pcall(play_split_explosion, blackboard.spawn.world, blackboard.spawn.physics_world, unit)
	end
end

-- Spawns the queued twins of the card rows (host; Execute.update calls it every frame). A twin waits while the card enemies are at
-- their limit (Max card enemies alive), at most TWIN_WAIT seconds.
Twins.update = function (dt)
	if #queue == 0 or not Execute or not Execute.spawn_twin then
		return
	end

	local nav_mesh = Managers.state and Managers.state.nav_mesh
	local nav_world = nav_mesh and nav_mesh.nav_world and nav_mesh:nav_world()
	local nav_ok, NavQueries = pcall(require, "scripts/utilities/nav_queries")

	if not nav_ok then
		nav_world = nil
	end
	local done = 0
	local i = 1

	while i <= #queue and done < TWINS_PER_UPDATE do
		local item = queue[i]

		item.age = item.age + (dt or 0)

		local position = item.position:unbox()

		if nav_world then
			local ok, snapped = pcall(NavQueries.position_on_mesh_with_outside_position, nav_world, nil, position, 1, 1, 1)

			position = ok and snapped or nil
		end

		local target = pick_target(item.target, position)
		local spawned, why = false, "no place on the navmesh"

		if position and target then
			spawned, why = Execute.spawn_twin(item.entry, position, target)
		end

		if spawned or why ~= "full" or item.age > TWIN_WAIT then
			table.remove(queue, i)
			done = done + 1
		else
			i = i + 1
		end
	end
end

Twins.reset = function ()
	queue = {}
end

Twins.queued = function ()
	return #queue
end

-- ####################################################################################################
-- ##### Purple buff: death effect, boss variant ######################################################
-- ####################################################################################################

-- units that went through MinionDeathManager.die, i.e. were really killed and not just deleted
local killed_units = setmetatable({}, { __mode = "k" })

-- the mutator manager of this mission says the Twins condition is on (set when the condition loaded its mutators). Only then do
-- the condition's chances apply: a card's Twins row creates the purple mutator too (Execute's "purple_stimm" step), and that alone
-- must not turn every enemy of the mission purple.
local function condition_active()
	local mutator_manager = Managers.state and Managers.state.mutator

	return mutator_manager ~= nil and rawget(mutator_manager, "__tw_condition") == true and mutator_manager:mutator(PURPLE_MUTATOR_NAME) ~= nil
end

-- The death effect (replaces the game's stop_func): a card row's enemy splits into its row's twins; any other purple enemy (the
-- condition, the game) splits by the per-breed settings, through the purple mutator's queue.
--
-- The buff has the despawn_on_death keyword, so a real kill despawns the enemy straight away and the effect runs while the buff
-- extension is being destroyed. Deleting units instead (minion_spawn:delete_units, mission cleanup) takes the same path, and running
-- the effect there crashes the engine (access violation). Only run it for units MinionDeathManager.die saw.
local function purple_stop_func(template_data, template_context, extension_destroyed)
	local unit = template_context.unit
	local was_killed = killed_units[unit]

	killed_units[unit] = nil

	if extension_destroyed and not was_killed then
		claims[unit] = nil

		return
	end

	if not Unit.alive(unit) then
		return
	end

	local blackboard = BLACKBOARDS[unit]

	if not blackboard then
		return
	end

	local claim = claims[unit]

	if claim then
		claims[unit] = nil

		local ok, err = pcall(split_claimed, unit, claim, blackboard)

		if not ok then
			mod:warning("GrandfathersTarot: Twins split failed: %s", tostring(err))
		end

		return
	end

	local mutator_manager = Managers.state and Managers.state.mutator
	local purple_mutator = mutator_manager and mutator_manager:mutator(PURPLE_MUTATOR_NAME)

	if not purple_mutator then
		return
	end

	local breed_name = ScriptUnit.extension(unit, "unit_data_system"):breed_name()
	local config = config_of(breed_name)
	local target_unit = blackboard.perception.target_unit

	if not config or not ALIVE[target_unit] then
		return
	end

	local rotation = Unit.local_rotation(unit, 1)
	local right = Quaternion.right(rotation)
	local base_position = Unit.world_position(unit, 1)
	local check_loops = loop_check_enabled()

	for slot = 1, 2 do
		local twin = twin_breed(breed_name, config, slot)

		if twin and purple_mutator._spawn_queue_size < SPAWN_QUEUE_LIMIT then
			local position = slot % 2 == 0 and base_position + right or base_position + -right
			local buff_to_add = twin_gets_buff(config, twin) and PURPLE_BUFF or nil

			-- loop check: a twin that sits on a spawn loop is spawned plain, which ends the chain
			if buff_to_add and check_loops and find_loop(twin) then
				buff_to_add = nil
			end

			purple_mutator:add_split_spawn(position, rotation, twin, buff_to_add, target_unit)

			local spawn_component = blackboard.spawn

			play_split_explosion(spawn_component.world, spawn_component.physics_world, unit)
		end
	end
end

local function install_buffs()
	local loaded, BuffTemplates = pcall(require, "scripts/settings/buff/buff_templates")
	local template = loaded and BuffTemplates and BuffTemplates[PURPLE_BUFF]

	if not template then
		mod:warning("GrandfathersTarot: '%s' buff not found; Twins is disabled", PURPLE_BUFF)

		return false
	end

	-- The buff has no stack limit, so an enemy that uses a stim while already purple gets two instances. Both start the same
	-- "stimmed_color" material vector effect but the extension only ref-counts it once, so the second stop crashed.
	template.max_stacks = template.max_stacks or 1
	template.max_stacks_cap = template.max_stacks_cap or 1
	template.stop_func = purple_stop_func

	return true
end

-- ####################################################################################################
-- ##### Install ######################################################################################
-- ####################################################################################################

local function unit_catalog_entry(unit)
	local data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
	local breed_name = data_extension and data_extension:breed_name()

	return breed_name and catalog.by_id[breed_name] or nil
end

-- puts the instance back to the class method and passes the results (or the error) of pcall on
local function finish_die(buff_extension, ok, ...)
	buff_extension.has_keyword = nil

	if not ok then
		error((...), 0)
	end

	return ...
end

local function has_purple_buff(unit)
	local buff_extension = ScriptUnit.has_extension(unit, "buff_system")

	return buff_extension ~= nil and buff_extension.current_stacks ~= nil and buff_extension:current_stacks(PURPLE_BUFF) > 0
end

local function install_hooks(BuffSettings)
	local DESPAWN_ON_DEATH = BuffSettings.keywords.despawn_on_death

	mod:hook_require("scripts/managers/minion/minion_death_manager", function (MinionDeathManager)
		mod:hook(MinionDeathManager, "die", function (func, self, unit, ...)
			killed_units[unit] = true

			-- The purple buff has despawn_on_death: die despawns the enemy instead of killing it, which skips the normal death
			-- handling (objectives, pacing, kill credit). Fine for a common enemy (the game's own design), but a boss must die
			-- normally: for the duration of this call the boss's buff extension denies having that keyword.
			local entry = unit_catalog_entry(unit)
			local buff_extension = entry and entry.boss and ScriptUnit.has_extension(unit, "buff_system")

			if not buff_extension then
				return func(self, unit, ...)
			end

			local has_keyword = buff_extension.has_keyword

			buff_extension.has_keyword = function (extension, keyword)
				if keyword == DESPAWN_ON_DEATH then
					return false
				end

				return has_keyword(extension, keyword)
			end

			return finish_die(buff_extension, pcall(func, self, unit, ...))
		end)
	end)

	-- (the crash guard of _stop_material_vector_effect lives in spawn/appearance.lua: one hook per mod per method)

	-- enemies with a stim animation: under the condition the stim action picks the purple buff
	mod:hook_require("scripts/extension_systems/behavior/nodes/actions/bt_use_stim_action", function (BtUseStimAction)
		mod:hook(BtUseStimAction, "run", function (func, self, unit, breed, blackboard, scratchpad, action_data, dt, t)
			if not condition_active() then
				return func(self, unit, breed, blackboard, scratchpad, action_data, dt, t)
			end

			-- Don't Re-Stim: an enemy that already carries the purple stimm skips the stim action (and the flag is cleared, or
			-- the behavior tree would pick the action again every frame)
			if mod:get("tw_no_restim") and has_purple_buff(unit) then
				local Blackboard = require("scripts/extension_systems/blackboard/utilities/blackboard")

				Blackboard.write_component(blackboard, "stim").can_use_stim = false

				return "done"
			end

			local original_stim_buffs = action_data.stim_buffs

			action_data.stim_buffs = PURPLE_BUFFS

			local ok, result = pcall(func, self, unit, breed, blackboard, scratchpad, action_data, dt, t)

			action_data.stim_buffs = original_stim_buffs

			if not ok then
				error(result, 0)
			end

			return result
		end)
	end)

	-- enemies without a stim animation: under the condition, the chance is rolled once when they spawn. The split-off enemies of the
	-- purple mutator's queue, and the card's own enemies (they have their own modifiers), are left alone.
	local spawning_twin = false

	-- The purple mutator spawns the split-off enemies in its update; that window is marked by wrapping the update of that one
	-- mutator INSTANCE (the game reloads mutator classes on a mission restart, and DMF refuses a second hook on the new class).
	local function watch_twin_spawns(purple_mutator)
		if not purple_mutator or rawget(purple_mutator, "__tw_watched") then
			return
		end

		local update = purple_mutator.update

		purple_mutator.update = function (self, dt, t)
			spawning_twin = true

			local ok, error_message = pcall(update, self, dt, t)

			spawning_twin = false

			if not ok then
				error(error_message, 0)
			end
		end
		purple_mutator.__tw_watched = true
	end

	Twins.watch_twin_spawns = watch_twin_spawns

	local function buff_on_spawn(unit)
		local entry = unit_catalog_entry(unit)

		if not entry or entry.stim then
			return
		end

		local chance = affect_chance(entry.id)

		if chance <= 0 or math.random() >= chance then
			return
		end

		local buff_extension = ScriptUnit.has_extension(unit, "buff_system")

		if not buff_extension then
			return
		end

		local t = Managers.time:time("gameplay")

		buff_extension:add_internally_controlled_buff(PURPLE_BUFF, t, "owner_unit", unit)
		buff_extension:_update_stat_buffs_and_keywords(t)
	end

	mod:hook_require("scripts/managers/minion/minion_spawn_manager", function (MinionSpawnManager)
		mod:hook(MinionSpawnManager, "spawn_minion", function (func, self, breed_name, position, rotation, side_id, optional_param_table)
			local unit = func(self, breed_name, position, rotation, side_id, optional_param_table)
			local card_unit = Execute and Execute.is_spawning and Execute.is_spawning()

			if unit and not spawning_twin and not card_unit and condition_active() then
				pcall(buff_on_spawn, unit)
			end

			return unit
		end)
	end)
end

-- ----------------------------------------------------------------------- the condition (SoloPlay)

-- string.split-like, but keeps empty fields
local function split(text, separator)
	local parts, start = {}, 1

	while true do
		local index = string.find(text, separator, start, true)

		if not index then
			parts[#parts + 1] = string.sub(text, start)

			return parts
		end

		parts[#parts + 1] = string.sub(text, start, index - 1)
		start = index + #separator
	end
end

-- Havoc data: "mission;rank;theme;faction;circumstance:circumstance;modifiers;challenge;resistance". Swaps this condition for the
-- carrier in the circumstance list (field 5) and drops a duplicate. Returns the new string and whether Twins was in it.
local function carry_havoc_data(havoc_data)
	if type(havoc_data) ~= "string" then
		return havoc_data, false
	end

	local fields = split(havoc_data, ";")

	if not fields[5] then
		return havoc_data, false
	end

	local circumstances, seen, found = {}, {}, false

	for _, name in ipairs(split(fields[5], ":")) do
		if name == CIRCUMSTANCE_NAME then
			found = true
			name = CARRIER_CIRCUMSTANCE
		end

		if name ~= "" and not seen[name] then
			seen[name] = true
			circumstances[#circumstances + 1] = name
		end
	end

	if not found then
		return havoc_data, false
	end

	fields[5] = table.concat(circumstances, ":")

	return table.concat(fields, ";"), true
end

Twins.carry_havoc_data = carry_havoc_data

-- Hide From Guests: on (default) = the swap happens; off = the condition keeps its real name (players without the mod error on it)
local function guest_safe()
	return mod:get("tw_guest_safe") ~= false
end

-- Twins is remembered on the mission context itself (MARK): the mechanism manager keeps that table, so a restart from it (e.g.
-- TrueSoloQoL's) still knows. Every mechanism change sets pending from the context it is given; the mutator manager consumes it.
local MARK = "__purple_stimms"
local pending = false

local function install_condition(solo_play)
	local CircumstanceTemplates = require("scripts/settings/circumstance/circumstance_templates")
	local HavocCircumstanceTemplate = require("scripts/settings/circumstance/templates/havoc_circumstance_template")
	local MutatorTemplates = require("scripts/settings/mutator/mutator_templates")

	mod:add_global_localize_strings({
		loc_purple_stimms_twins_title = { en = "Twins" },
		loc_purple_stimms_twins_description = { en = "Stimmed enemies use the purple stim and split into two on death." },
	})

	-- chances are read live from the settings: MutatorStimmedMinions looks up breed_chances[breed] on every aggro
	local breed_chances = setmetatable({}, {
		__index = function (_, breed_name)
			local entry = catalog.by_id[breed_name]

			if entry and entry.stim then
				local chance = affect_chance(breed_name)

				if chance > 0 then
					return chance
				end
			end

			return nil
		end,
	})

	MutatorTemplates[TRIGGER_MUTATOR_NAME] = MutatorTemplates[TRIGGER_MUTATOR_NAME] or {
		name = TRIGGER_MUTATOR_NAME,
		class = "scripts/managers/mutator/mutators/mutator_stimmed_minions",
		breed_chances = breed_chances,
	}

	MutatorTemplates[PURPLE_MUTATOR_NAME] = MutatorTemplates[PURPLE_MUTATOR_NAME] or {
		name = PURPLE_MUTATOR_NAME,
		class = "scripts/managers/mutator/mutators/mutator_purple_stimmed",
	}

	local circumstance = CircumstanceTemplates[CIRCUMSTANCE_NAME] or {
		name = CIRCUMSTANCE_NAME,
		theme_tag = "default",
		mutators = { TRIGGER_MUTATOR_NAME, PURPLE_MUTATOR_NAME },
		mission_overrides = {},
		ui = {
			description = "loc_purple_stimms_twins_description",
			display_name = "loc_purple_stimms_twins_title",
			icon = "content/ui/materials/icons/circumstances/placeholder",
		},
	}

	CircumstanceTemplates[CIRCUMSTANCE_NAME] = circumstance
	-- SoloPlaySettings lists everything in HavocCircumstanceTemplate in the Havoc condition dropdowns
	HavocCircumstanceTemplate[CIRCUMSTANCE_NAME] = circumstance

	-- NetworkLookup tables are built before mods load and error on unknown keys
	local lookup = NetworkLookup and NetworkLookup.circumstance_templates

	if lookup and not rawget(lookup, CIRCUMSTANCE_NAME) then
		local index = #lookup + 1

		lookup[index] = CIRCUMSTANCE_NAME
		lookup[CIRCUMSTANCE_NAME] = index
	end

	-- SoloPlay builds every mission context in these two functions; the original is kept on SoloPlay's mod table so a reload does
	-- not stack wrappers (the key is the one SoloPlayPurpleStimms used, so its wrap and this one never stack either)
	local function wrap(function_name, carry)
		local original = solo_play["__purple_stimms_original_" .. function_name] or solo_play[function_name]

		if type(original) ~= "function" then
			mod:warning("GrandfathersTarot: SoloPlay.%s not found; guests without the mod would error on the Twins condition", function_name)

			return
		end

		solo_play["__purple_stimms_original_" .. function_name] = original
		solo_play[function_name] = function (...)
			local context = original(...)

			if type(context) == "table" then
				context[MARK] = guest_safe() and carry(context) or nil
			end

			return context
		end
	end

	wrap("gen_normal_mission_context", function (context)
		if context.circumstance_name == CIRCUMSTANCE_NAME then
			context.circumstance_name = CARRIER_CIRCUMSTANCE

			return true
		end

		return false
	end)
	wrap("gen_havoc_mission_context", function (context)
		local havoc_data, purple = carry_havoc_data(context.havoc_data)

		context.havoc_data = havoc_data

		return purple
	end)

	mod:hook_require("scripts/managers/mechanism/mechanism_manager", function (MechanismManager)
		mod:hook(MechanismManager, "change_mechanism", function (func, self, mechanism_name, context)
			pending = type(context) == "table" and context[MARK] == true

			return func(self, mechanism_name, context)
		end)
	end)

	-- The mission loads the carrier condition on every machine. On the host this hook then points that mutator at the live per-enemy
	-- chances and adds the purple mutator that splits enemies; guests only load the vanilla mutator, which does nothing on a client.
	mod:hook_require("scripts/managers/mutator/mutator_manager", function (MutatorManager)
		mod:hook(MutatorManager, "_load_mutators", function (func, self, circumstance_name)
			if not pending or not self._is_server then
				func(self, circumstance_name)

				-- Hide From Guests off: the game loaded the condition's own mutators, purple one included
				if self._is_server and self._mutators[PURPLE_MUTATOR_NAME] then
					self.__tw_condition = true
					Twins.watch_twin_spawns(self._mutators[PURPLE_MUTATOR_NAME])
				end

				return
			end

			local carrier_template = MutatorTemplates[CARRIER_MUTATOR]
			local original_chances = carrier_template and carrier_template.breed_chances

			if carrier_template then
				carrier_template.breed_chances = breed_chances
			end

			local ok, error_message = pcall(func, self, circumstance_name)

			if carrier_template then
				carrier_template.breed_chances = original_chances
			end

			if not ok then
				error(error_message, 0)
			end

			if self._mutators[CARRIER_MUTATOR] then
				local purple_template = MutatorTemplates[PURPLE_MUTATOR_NAME]
				local purple_class = require(purple_template.class)

				self._mutators[PURPLE_MUTATOR_NAME] = purple_class:new(self._is_server, self._network_event_delegate, purple_template, self._nav_world, self._world, self._level_seed)
				self.__tw_condition = true
				Twins.watch_twin_spawns(self._mutators[PURPLE_MUTATOR_NAME])
				pending = false
			end
		end)
	end)
end

-- Installs everything (GrandfathersTarot.lua, at load). Returns true, or false and a reason.
Twins.install = function ()
	if installed then
		return true
	end

	-- the old mod still loaded: it would patch the same buff and condition; Twins stays off until it is removed
	if get_mod("SoloPlayPurpleStimms") then
		return false, "SoloPlayPurpleStimms is still loaded: it is part of The Grandfather's Tarot now (Twins). Remove it from mod_load_order.txt."
	end

	catalog = mod:io_dofile(BASE .. "/twins/catalog")
	cosmetics = mod:io_dofile(BASE .. "/twins/cosmetics")

	if not catalog or not cosmetics then
		return false, "the Twins files could not be loaded"
	end

	local BuffSettings = require("scripts/settings/buff/buff_settings")

	cosmetics.install_color()
	cosmetics.install_smoke()

	if not install_buffs() then
		return false, "the purple stimm buff was not found"
	end

	install_hooks(BuffSettings)
	installed = true

	local solo_play = get_mod("SoloPlay")

	if solo_play and solo_play:is_enabled() then
		install_condition(solo_play)
	else
		mod:warning("GrandfathersTarot: SoloPlay is missing or disabled: the Twins condition is not offered (the Twins modifier of cards still works)")
	end

	mod:command("gt_twins_smoke", mod:localize("tw_smoke_command"), function ()
		local ok, reason = cosmetics.play_test()

		if not ok then
			mod:echo("gt_twins_smoke: " .. tostring(reason))
		end
	end)

	return true
end

return Twins
