-- Selected wave units only. No custom buff/effect/item/network lookup names.
local mod = get_mod("RealmsWaves")
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

local function extension(unit, name)
	return ScriptUnit.has_extension(unit, name)
end

local function is_host()
	local session = Managers.state and Managers.state.game_session
	return session and session:is_server() == true
end

local function warn(message)
	if not warned[message] then
		warned[message] = true
		mod:warning("RealmsWaves appearance: %s", message)
	end
end

local function count(map)
	local n = 0
	for _ in pairs(map) do n = n + 1 end
	return n
end

local function targets(unit, explicit)
	local list, seen = { unit }, { [unit] = true }
	local loadout = extension(unit, "visual_loadout_system")
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
	local buffs = extension(unit, "buff_system")
	local effect = buffs and buffs._current_material_vector_effect
	local value = effect and effect.material_vector_name == "stimmed_color" and effect.value
	return value and value[1] or 0, value and value[2] or 0, value and value[3] or 0
end

local function restore(record)
	if record.outline then
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
	elseif record.written then
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

local function apply_record(record)
	local unit, config = record.unit, record.config
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
		local buffs = extension(unit, "buff_system")
		if not buffs or not buffs:has_keyword("stimmed") then
			if record.written then restore(record); record.written = nil end
			return
		end
	end
	local r, g, b = Schema.rgb(config)
	if config.method == "outline" then
		if record.outline or config.a == 0 then return end
		local ext = extension(unit, "outline_system")
		local manager = Managers.state and Managers.state.extension
		if not ext or not manager then return end
		local system, previous, owned = manager:system("outline_system"), ext.settings, {}
		for key, value in pairs(previous) do owned[key] = value end
		owned[OUTLINE] = { priority = 2, color = { r, g, b }, material_layers = { "minion_outline", "minion_outline_reversed_depth" }, visibility_check = function (target) return alive(target) end }
		ext.settings = owned
		record.outline = { ext = ext, system = system, previous = previous, owned = owned }
		system:add_outline(unit, OUTLINE)
		return
	end
	local list, loadout = targets(unit, true)
	if not loadout then return end -- extensions/loadout can finish after spawn
	local nr, ng, nb = normal_colour(unit)
	local stamp = tostring(nr) .. ":" .. tostring(ng) .. ":" .. tostring(nb)
	local changed = record.stamp ~= stamp
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

Appearance.init = function (deps)
	Schema, Protocol = deps.schema, deps.protocol
end
Appearance.epoch = function () return salt .. ":" .. generation end

Appearance.apply = function (unit, config, breed, remote)
	config = Schema.copy(config)
	if retired or not config or not alive(unit) then return end
	if config.method == "none" then remove(unit); return end
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
				list[#list + 1] = { id, clear and "none" or c.method, c.a, c.r, c.g, c.b, record.breed }
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

Appearance.update = function (dt)
	if retired then return end
	clock, cadence, renewal = clock + dt, cadence + dt, renewal + dt
	if cadence < 0.25 then return end
	cadence = 0
	local spawner = Managers.state and Managers.state.unit_spawner
	for id, waiting in pairs(pending) do
		local ok, unit = pcall(function () return spawner and spawner:unit_exists(id) and spawner:unit(id) end)
		if ok and unit then
			local got, data, breed = pcall(function ()
				local data = alive(unit) and extension(unit, "unit_data_system")
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
		else
			local ok, err = pcall(apply_record, record)
			if not ok then warn("application failed: " .. tostring(err)) end
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
	records, pending = {}, {}
	clock, cadence, renewal = 0, 0, 0
	generation = generation + 1
end
Appearance.retire = function () Appearance.reset(true); retired = true end
Appearance.status = function () return { selected = count(records), pending = count(pending) } end

return Appearance
