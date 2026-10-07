-- Selected wave units only. No custom buff/effect/item/network lookup names.
local mod = get_mod("GrandfathersTarot")
local Appearance = {}
local Schema, Protocol
local records, pending = {}, {}
local clock, cadence, renewal = 0, 0, 0
local generation, salt = 0, tostring(math.random(1, 2147483647))
local warned, retired = {}, false
local MAX_UNITS, LEASE, WAIT = 600, 15, 20
local OUTLINE = "rw_selected_colour"

local function alive(unit)
	return unit ~= nil and Unit.alive(unit) and (not HEALTH_ALIVE or HEALTH_ALIVE[unit] ~= false)
end

local function is_host()
	local session = Managers.state and Managers.state.game_session
	return session and session:is_server() == true
end

local function warn(message)
	if not warned[message] then
		warned[message] = true
		mod:warning("GrandfathersTarot appearance: %s", message)
	end
end

local function count(map)
	local n = 0
	for _ in pairs(map) do n = n + 1 end
	return n
end

local function targets(unit, explicit)
	local list, seen = { unit }, { [unit] = true }
	local loadout = ScriptUnit.has_extension(unit, "visual_loadout_system")
	if explicit and loadout then
		for slot_name in pairs(loadout:slot_items()) do
			local slot, attachments = loadout:slot_unit(slot_name)
			if slot and alive(slot) and not seen[slot] then list[#list + 1], seen[slot] = slot, true end
			for _, attachment in ipairs(attachments or {}) do
				if alive(attachment) and not seen[attachment] then list[#list + 1], seen[attachment] = attachment, true end
			end
		end
	end
	return list, loadout
end

local function normal_colour(unit)
	local buffs = ScriptUnit.has_extension(unit, "buff_system")
	local effect = buffs and buffs._current_material_vector_effect
	local value = effect and effect.material_vector_name == "stimmed_color" and effect.value
	return value and value[1] or 0, value and value[2] or 0, value and value[3] or 0
end

-- Dark skin (2026-10-05, the user: "let's try the dark skin effect"): the game's ailment skin looks (Ailment.play_ailment_effect_template:
-- a mask and a colour ramp texture on the materials, the HAVE_BURN permutation, and offset_time_duration = offset, start, duration)
-- held at one moment of the effect: every frame the start is put `phase` seconds before now, so the shader keeps showing that
-- moment. A picks the phase (0 = the start of the effect, 255 = its end). Nothing is written while the engine does not have the
-- textures (an unloaded texture can crash the engine). No colour ramp of the game is black: which look reads
-- darkest is what this experiment is for.
local SKINS = { skin_burnt = "burning", skin_warp = "warpfire", skin_bruise = "broker_brittleness" }
local skinned = {}

-- (2026-10-05, in game: "Package reference ... does not exist") these textures are not packages of their own: the game writes them
-- when the weapon or enemy that causes the ailment is in the mission, so they are only used when the engine already has them
-- (Application.can_get_resource). Otherwise the look waits (checked again every quarter second) and says why once.
local function skin_template(method)
	local Settings = require("scripts/settings/ailments/ailment_settings")
	local template = Settings.effect_templates and Settings.effect_templates[SKINS[method]]
	if not template then return nil end
	for _, texture in pairs(template.material_textures or {}) do
		local ok, has = pcall(function () return Application.can_get_resource("texture", texture.resource) end)
		if not (ok and has) then
			warn(method .. ": its textures are not loaded in this mission yet (the game loads them with what causes that effect); it waits")
			return nil
		end
	end
	return template
end

-- (2026-10-06, a performance pass) held SKIN_STEP at a time, not every frame: the moment shown is centred on the phase, so it moves
-- by at most half a step (0.05 s of an effect of 2 to 4.5 s) instead of an engine write per skinned enemy per frame
local SKIN_STEP = 0.1
local skin_timer = 0

local function skin_time(record)
	local template, unit = record.skin, record.unit
	local now = World.time(Unit.world(unit))
	local phase = template.duration * record.config.a / 255
	local lead = math.min(SKIN_STEP / 2, phase)
	Unit.set_vector3_for_materials(unit, "offset_time_duration", Vector3(template.offset_time, now - phase + lead, template.duration + 1), true)
end

local function apply_skin(record)
	if not record.skin then
		local template = skin_template(record.config.method)
		if not template then return end
		for _, texture in pairs(template.material_textures or {}) do
			Unit.set_texture_for_materials(record.unit, texture.slot, texture.resource, true)
		end
		Unit.set_permutation_for_materials(record.unit, "HAVE_BURN", true, true)
		record.skin = template
		skinned[record.unit] = record
	end
	skin_time(record)
end

local function stop_skin(record)
	skinned[record.unit] = nil
	local template = record.skin
	record.skin = nil
	if template and alive(record.unit) then
		-- the effect long over: the skin is the enemy's own again
		Unit.set_vector3_for_materials(record.unit, "offset_time_duration", Vector3(template.offset_time, -100000, 0.01), true)
	end
end

Appearance._skinned = function () local n = 0; for _ in pairs(skinned) do n = n + 1 end return n end

local function restore(record, keep_outline)
	if record.skin and not keep_outline then
		local ok, err = pcall(stop_skin, record)
		if not ok then warn("dark skin removal failed: " .. tostring(err)) end
	end
	if record.outline and not keep_outline then
		local outline = record.outline
		if alive(record.unit) then
			local ok, err = pcall(outline.system.remove_outline, outline.system, record.unit, OUTLINE)
			if not ok then warn("outline removal failed: " .. tostring(err)) end
		end
		-- Remove just our key. Preserve changes another mod made to the local settings map.
		if outline.ext.settings == outline.owned then
			outline.owned[OUTLINE] = nil
			local unchanged = true
			for key, value in pairs(outline.owned) do if outline.previous[key] ~= value then unchanged = false end end
			for key, value in pairs(outline.previous) do if outline.owned[key] ~= value then unchanged = false end end
			if unchanged then outline.ext.settings = outline.previous end
		end
	end
	if record.written then
		local r, g, b = 0, 0, 0
		if alive(record.unit) then r, g, b = normal_colour(record.unit) end
		for unit in pairs(record.written) do
			if alive(unit) then
				local ok, err = pcall(Unit.set_vector3_for_materials, unit, "stimmed_color", Vector3(r, g, b), true)
				if not ok then warn("material restoration failed: " .. tostring(err)) end
			end
		end
	end
end

local function remove(unit)
	local record = records[unit]
	if record then
		local ok, err = pcall(restore, record)
		if not ok then warn("restoration failed: " .. tostring(err)) end
		records[unit] = nil
	end
end

-- Line of sight for the coloured outline (2026-10-04: the user saw it through walls). The outline material layers draw through
-- geometry, so the outline's visibility_check (the outline system asks it every frame) hides it unless the local camera sees the
-- enemy's torso or head through the level's static geometry (the minions' own line-of-sight collision filter), or a player has
-- tagged the enemy (a tag shows it anyway, like the game's own tag outline). Each enemy is ray-cast at most every LOS_EVERY seconds;
-- the answer is kept in a weak table of reused entries (no allocation per frame).
local LOS_EVERY, LOS_FILTER = 0.15, "filter_minion_line_of_sight_check"
local LOS_NODES = { "j_spine", "j_head" }
local sight = setmetatable({}, { __mode = "k" })

local function ray_clear(physics, from, target, node_name)
	if not Unit.has_node(target, node_name) then return false end
	local to = Unit.world_position(target, Unit.node(target, node_name))
	local distance = Vector3.distance(from, to)
	if distance < 0.5 then return true end
	local hit, _, hit_distance = PhysicsWorld.raycast(physics, from, Vector3.normalize(to - from), distance, "closest", "collision_filter", LOS_FILTER)
	return not hit or (hit_distance ~= nil and hit_distance >= distance - 0.4)
end

local function look(target)
	local tags = Managers.state.extension:system("smart_tag_system")
	if tags and tags:is_unit_tagged(target) then return true end
	local manager = Managers.player
	local find = manager and (manager.local_player_safe or manager.local_player)
	local player = find and find(manager, 1)
	local world = Managers.world:world("level_world")
	local camera = player and Managers.state.camera and Managers.state.camera:camera_position(player.viewport_name)
	if not camera or not world then return false end
	local physics = World.physics_world(world)
	for i = 1, #LOS_NODES do
		if ray_clear(physics, camera, target, LOS_NODES[i]) then return true end
	end
	return not Unit.has_node(target, LOS_NODES[1]) and not Unit.has_node(target, LOS_NODES[2]) and ray_clear(physics, camera, target, "root_point")
end

local function in_sight(target)
	if not alive(target) then return false end
	local now = Managers.time and Managers.time:has_timer("main") and Managers.time:time("main") or 0
	local entry = sight[target]
	if entry and now - entry[1] < LOS_EVERY and now >= entry[1] then return entry[2] end
	local ok, visible = pcall(look, target)
	if not ok then warn("outline line of sight failed: " .. tostring(visible)); visible = false end
	entry = entry or {}
	entry[1], entry[2] = now, visible == true
	sight[target] = entry
	return entry[2]
end

Appearance._in_sight = in_sight

local function apply_record(record)
	local unit, config = record.unit, record.config
	local r, g, b = Schema.rgb(config)
	if (config.method == "outline" or config.outline) and not record.outline and config.a > 0 then
		local ext = ScriptUnit.has_extension(unit, "outline_system")
		local manager = Managers.state and Managers.state.extension
		if ext and manager then
			local system, previous, owned = manager:system("outline_system"), ext.settings, {}
			for key, value in pairs(previous) do owned[key] = value end
			-- Hidden behind walls unless tagged (in_sight); the game's higher-priority manual smart tag keeps its own outline.
			owned[OUTLINE] = { priority = 2, color = { r, g, b }, material_layers = { "minion_outline" }, visibility_check = in_sight }
			ext.settings = owned
			record.outline = { ext = ext, system = system, previous = previous, owned = owned }
			system:add_outline(unit, OUTLINE)
		end
	end
	if config.method == "outline" or config.method == "none" then return end
	if SKINS[config.method] then return apply_skin(record) end
	if config.method == "natural_stimm" then
		local actions = require("scripts/settings/breed/breed_actions")[record.breed]
		if not actions or not actions.use_stim then
			warn(record.breed .. " does not support the natural stim action; it keeps its normal appearance")
			return
		end
		if is_host() and not record.armed then
			local blackboard = BLACKBOARDS and BLACKBOARDS[unit]
			if blackboard then
				local Blackboard = require("scripts/extension_systems/blackboard/utilities/blackboard")
				if Blackboard.has_component(blackboard, "stim") then
					local stim = Blackboard.write_component(blackboard, "stim")
					record.stim, record.previous_can_stim = stim, stim.can_use_stim
					stim.can_use_stim = true
				else
					warn(record.breed .. " does not support the natural stim action; it keeps its normal appearance")
				end
				record.armed = true
			end
		end
		local buffs = ScriptUnit.has_extension(unit, "buff_system")
		if not buffs or not buffs:has_keyword("stimmed") then
			if record.written then restore(record, true); record.written = nil end
			return
		end
	end
	local list, loadout = targets(unit, true)
	if not loadout then return end -- extensions/loadout can finish after spawn
	local nr, ng, nb = normal_colour(unit)
	local stamp = tostring(nr) .. ":" .. tostring(ng) .. ":" .. tostring(nb)
	local changed = record.stamp ~= stamp
	if not config.protect and record.written and (nr ~= 0 or ng ~= 0 or nb ~= 0) then r, g, b = nr, ng, nb end
	record.written = record.written or {}
	local current = {}
	for _, target in ipairs(list) do current[target] = true end
	for old in pairs(record.written) do
		if not current[old] then
			if alive(old) then Unit.set_vector3_for_materials(old, "stimmed_color", Vector3(nr, ng, nb), true) end
			record.written[old] = nil
		end
	end
	for _, target in ipairs(list) do
		if changed or not record.written[target] then
			-- Root mode retries recursion when new loadout units appear; slot mode writes each one explicitly.
			local write_unit = config.method == "slot_stimm" and target or unit
			Unit.set_vector3_for_materials(write_unit, "stimmed_color", Vector3(r, g, b), true)
			record.written[target] = true
		end
	end
	record.stamp = stamp
end

Appearance.init = function (deps) Schema, Protocol = deps.schema, deps.protocol end

Appearance.install = function ()
	if not mod.hook_require then return end
	local function refresh(self)
		local record = records[self._unit]
		if retired or not record then return end
		-- an unprotected colour follows the stimm's: looked at on the next quarter second, not after STABLE_CHECK
		if not record.config.protect then record.next_check = 0; return end
		record.stamp = nil
		local ok, err = pcall(apply_record, record)
		if not ok then warn("protected colour update failed: " .. tostring(err)) end
	end
	-- (once per class table: DMF runs this again whenever the game loads the file again, and a second hook_safe warns)
	local hooked = setmetatable({}, { __mode = "k" })
	mod:hook_require("scripts/extension_systems/buff/minion_buff_extension", function (class)
		if retired or hooked[class] then return end
		hooked[class] = true
		for _, name in ipairs({ "_start_material_vector_effect", "_stop_material_vector_effect" }) do mod:hook_safe(class, name, refresh) end
	end)
end
Appearance.epoch = function () return salt .. ":" .. generation end

Appearance.apply = function (unit, config, breed, remote)
	config = Schema.copy(config)
	if retired or not config or not alive(unit) then return end
	if config.method == "none" and not config.outline then remove(unit); return end
	if not Schema.method(config.method).available then warn(Schema.method(config.method).info); return end
	if not records[unit] and count(records) >= MAX_UNITS then warn("selected-unit limit reached (600)"); return end
	local record = records[unit]
	if record and Schema.recipe(record.config) == Schema.recipe(config) then record.expires = remote and clock + LEASE or nil; return end
	remove(unit)
	record = { unit = unit, config = config, breed = breed, expires = remote and clock + LEASE or nil, created = clock }
	records[unit] = record
	local ok, err = pcall(apply_record, record)
	if not ok then warn("application failed: " .. tostring(err)) end
	renewal = 5 -- send next maintenance tick, after game object initialization
end

Appearance.send_all = function (recipient, clear)
	if retired or not is_host() or not Protocol then return end
	local spawner = Managers.state and Managers.state.unit_spawner
	if not spawner then return end
	local list, epoch = {}, Appearance.epoch()
	for unit, record in pairs(records) do
		if alive(unit) then
			local ok, id = pcall(spawner.game_object_id, spawner, unit)
			if ok and id then
				local c = record.config
				list[#list + 1] = { id, clear and "none" or c.method, c.a, c.r, c.g, c.b, record.breed, not clear and c.outline == true, not clear and c.protect == true }
			end
		end
	end
	-- A synchronous send may disable/reload this module. Snapshot first, then abandon the remaining batches.
	for first = 1, #list, 200 do
		if retired or Appearance.epoch() ~= epoch then return end
		local batch = {}
		for i = first, math.min(first + 199, #list) do batch[#batch + 1] = list[i] end
		Protocol.send_appearances(epoch, batch, recipient)
	end
end

Appearance.receive = function (entries)
	if retired or is_host() then return end
	for _, entry in ipairs(entries) do
		if pending[entry.id] or count(pending) < MAX_UNITS then
			local existing = pending[entry.id]
			pending[entry.id] = { entry = entry, created = existing and existing.created or clock }
		end
	end
end

local STABLE_CHECK = 2

local function count_of(list)
	local n = 0
	for _ in pairs(list or {}) do n = n + 1 end
	return n
end

Appearance.update = function (dt)
	if retired then return end
	clock, cadence, renewal = clock + dt, cadence + dt, renewal + dt
	-- the dark skins are held still, SKIN_STEP at a time (the moment must not drift)
	skin_timer = skin_timer + dt
	if skin_timer >= SKIN_STEP then
		skin_timer = 0
		for unit, record in pairs(skinned) do
			if not alive(unit) then
				skinned[unit] = nil
			else
				local ok, err = pcall(skin_time, record)
				if not ok then skinned[unit] = nil; warn("dark skin failed: " .. tostring(err)) end
			end
		end
	end
	if cadence < 0.25 then return end
	cadence = 0
	local spawner = Managers.state and Managers.state.unit_spawner
	for id, waiting in pairs(pending) do
		local ok, unit = pcall(function () return spawner and spawner:unit_exists(id) and spawner:unit(id) end)
		if ok and unit then
			local got, data, breed = pcall(function ()
				local data = alive(unit) and ScriptUnit.has_extension(unit, "unit_data_system")
				return data, data and data:breed()
			end)
			if got and breed and breed.name == waiting.entry.breed then
				Appearance.apply(unit, waiting.entry.config, waiting.entry.breed, true)
				pending[id] = nil
			elseif not alive(unit) or (got and data and breed) then pending[id] = nil end
		end
		if clock - waiting.created >= WAIT then pending[id] = nil end
	end
	for unit, record in pairs(records) do
		if not alive(unit) or (record.expires and record.expires <= clock) then
			remove(unit)
		elseif (record.next_check or 0) <= clock then
			-- (2026-10-06, a performance pass) a colour written and unchanged since the last look is looked at again every
			-- STABLE_CHECK seconds, not four times a second (a stimm's colour change comes at once through the hook below)
			local stamp, written = record.stamp, count_of(record.written)
			local ok, err = pcall(apply_record, record)
			if not ok then warn("application failed: " .. tostring(err)) end
			local stable = ok and written > 0 and record.stamp == stamp and count_of(record.written) == written
			record.next_check = stable and clock + STABLE_CHECK or 0
		end
	end
	if is_host() and renewal >= 5 then renewal = 0; Appearance.send_all() end
end

Appearance.reset = function (send_clear)
	if send_clear then pcall(Appearance.send_all, nil, true) end
	for unit, record in pairs(records) do
		-- Cancel only an unconsumed stim permission we armed. Consumed vanilla buffs keep their lifecycle.
		if record.stim and record.stim.can_use_stim == true and not record.stim.currently_using_stim then
			record.stim.can_use_stim = record.previous_can_stim
		end
		remove(unit)
	end
	records, pending, skinned = {}, {}, {}
	clock, cadence, renewal, skin_timer = 0, 0, 0, 0
	generation = generation + 1
end
Appearance.retire = function () Appearance.reset(true); retired = true end
Appearance.status = function () return { selected = count(records), pending = count(pending) } end

return Appearance
