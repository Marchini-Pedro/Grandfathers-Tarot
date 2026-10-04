-- Native gameplay effects run on the host. Guidance and completion audio render locally.
local mod = get_mod("RealmsWaves")
local Schema = mod:io_dofile("RealmsWaves/scripts/mods/RealmsWaves/catalog/effects")
local Sounds = mod:io_dofile("RealmsWaves/scripts/mods/RealmsWaves/catalog/sounds")
local Effects = {}
local clock, cadence, reveal_until, blackout_until = 0, 0, 0, 0
local lights, buffs, outlines, tickets, audio = {}, {}, {}, {}, {}
local sequence, received, warned = 0, nil, {}
local grants, grant_sequence, grant_received = {}, 0, nil
local revision, received_revision, received_time = 0, nil, nil
local REVEAL = "rw_guidance"
local function alive(unit) return unit and Unit.alive(unit) and (not HEALTH_ALIVE or HEALTH_ALIVE[unit] ~= false) end
local function ext(unit, name) return alive(unit) and ScriptUnit.has_extension(unit, name) end
local function host()
	local session = Managers.state and Managers.state.game_session
	return session and session:is_server() == true
end
local function warn(message)
	if not warned[message] then warned[message] = true; mod:warning("RealmsWaves card effects: %s", message) end
end
local function system(name)
	return Managers.state and Managers.state.extension and Managers.state.extension:system(name)
end
local function players()
	local list = {}
	local manager = Managers.player
	for id, player in pairs(manager and manager:players() or {}) do
		if alive(player.player_unit) and ext(player.player_unit, "health_system") then list[#list + 1] = { id = tostring(id), unit = player.player_unit } end
	end
	table.sort(list, function (a, b) return a.id < b.id end)
	return list
end
local function game_time() return require("scripts/utilities/fixed_frame").get_latest_fixed_time() end
local function play(event)
	if not Sounds.valid(event) or mod:get("card_sounds") == false then return end
	local ok, err = pcall(function ()
		local simple = get_mod("SimpleAudio")
		if simple and simple.play and (not simple.is_enabled or simple:is_enabled()) then return simple.play(event) end
		local world = Managers.ui and Managers.ui:world()
		if not world or not Managers.world then return end
		local wwise = Managers.world:wwise_world(world)
		return WwiseWorld.trigger_resource_event(wwise, event)
	end)
	if not ok then warn("sound unavailable: " .. tostring(err)) end
end
Effects.preview_sound = play
local function restore_lights()
	for unit, saved in pairs(lights) do
		if alive(unit) then pcall(saved.extension.set_enabled, saved.extension, saved.enabled, false) end
	end
	lights, blackout_until = {}, 0
end
local function blackout(seconds)
	local controller = system("light_controller_system")
	if not controller then return false, "this level has no light controller" end
	local changed = false
	for unit, extension in pairs(controller._unit_to_extension_map or {}) do
		if alive(unit) and extension.is_enabled and extension.set_enabled then
			if not lights[unit] then lights[unit] = { extension = extension, enabled = extension:is_enabled() } end
			if extension:is_enabled() then extension:set_enabled(false, false) end
			changed = true
		end
	end
	if changed then blackout_until = math.max(blackout_until, clock + seconds) end
	return changed, "this level has no controllable lights"
end
local ITEMS = {
	green_stimm = { "content/items/pocketable/syringe_corruption_pocketable", "slot_pocketable_small" },
	yellow_stimm = { "content/items/pocketable/syringe_ability_boost_pocketable", "slot_pocketable_small" },
	med_crate = { "content/items/pocketable/med_crate_pocketable", "slot_pocketable" },
}
local function give(unit, id)
	local data, loadout = ext(unit, "unit_data_system"), ext(unit, "visual_loadout_system")
	local inventory = data and data:read_component("inventory")
	local item, slot = ITEMS[id][1], ITEMS[id][2]
	if not loadout or not inventory or inventory[slot] ~= "not_equipped" then return false end
	local Pocketable = require("scripts/utilities/pocketable")
	local native_item = Pocketable.item_from_name(item)
	if not native_item or native_item.name ~= item then return false end
	Pocketable.equip_pocketable(game_time(), true, unit, nil, native_item, slot, false)
	return true
end
local function recharge(list, charges)
	local stations, nearest, distance = system("health_station_system"), nil, math.huge
	for unit, extension in pairs(stations and stations._unit_to_extension_map or {}) do
		if alive(unit) and extension:battery_in_slot() and extension:charge_amount() < extension:max_amount_charges() then
			for _, player in ipairs(list) do
				local d = Vector3.distance_squared(Unit.world_position(unit, 1), Unit.world_position(player.unit, 1))
				if d < distance then nearest, distance = extension, d end
			end
		end
	end
	if not nearest then return false, "no rechargeable Med Station near the party" end
	nearest:set_charge_amount(math.min(nearest:max_amount_charges(), nearest:charge_amount() + charges))
	nearest:sync_charge_amount()
	return true
end
local function apply(id, effect, list)
	if id == "blackout" then return blackout(effect.value) end
	if id == "reveal" then reveal_until = math.max(reveal_until, clock + effect.value); return true end
	if id == "med_station" then return recharge(list, effect.value) end
	if id == "cooldown" then
		local targets, spawner = {}, Managers.state.unit_spawner
		for _, player in ipairs(list) do
			local ability = ext(player.unit, "ability_system")
			if ability and ability._is_local_unit and ability.restore_ability_resource_percentage then
				local ok, err = pcall(ability.restore_ability_resource_percentage, ability, "combat_ability", effect.value / 100, true)
				if not ok then warn(tostring(err)) end
			elseif ability and spawner then
				local object = spawner:game_object_id(player.unit)
				if object then targets[#targets + 1] = object end
			end
		end
		grant_sequence = grant_sequence + 1
		grants[#grants + 1] = { grant_sequence, effect.value, targets }
		if #grants > 64 then table.remove(grants, 1) end
		return #list > 0, "no living players for ability restoration"
	end
	local count = 0
	for _, player in ipairs(list) do
		local unit = player.unit
		local ok, err = pcall(function ()
			if id == "heal" or id == "cleanse" then
				local health = ext(unit, "health_system")
				if not health then return end
				local amount = health:max_health() * effect.value / 100
				if id == "cleanse" then health:add_heal(amount, "buff_corruption_healing") end
				health:add_heal(amount, "buff")
				count = count + 1
			elseif ITEMS[id] then
				if count < effect.value and give(unit, id) then count = count + 1 end
			elseif id == "blue_stimm" and count < effect.players then
				local buff = ext(unit, "buff_system")
				if buff and #buffs < 256 then
					local _, index, component = buff:add_externally_controlled_buff("syringe_speed_boost_buff", game_time())
					if index then
						local instance = buff._buffs_by_index and buff._buffs_by_index[index]
						buffs[#buffs + 1] = { unit = unit, extension = buff, index = index, component = component, expires = clock + effect.value }
						if not instance or not instance.add_duration then error("native Blue Stimm duration is unavailable") end
						instance:add_duration(effect.value - 15)
						count = count + 1
					end
				end
			end
		end)
		if not ok then warn(tostring(err)) end
	end
	return count > 0, "no eligible players or empty inventory slots for " .. id
end
Effects.start = function (def)
	if not host() then return false, "card effects require host authority" end
	if Sounds.valid(def.sound) and #tickets >= 64 then return false, "64 unfinished sounding cards are already tracked" end
	local values = Schema.allowed(Schema.parse(Schema.encode(def.effects)) or {}, def.suit)
	local list, duration, success = players(), 0, false
	for _, entry in ipairs(Schema.ORDER) do
		local effect = values[entry.id]
		if effect then
			local ok, applied, err = pcall(apply, entry.id, effect, list)
			if ok and applied then
				success = true
				if entry.unit == "seconds" then duration = math.max(duration, effect.value) end
			else warn(tostring(err or applied or "effect unavailable")) end
		end
	end
	if not success and not (def.parts and #def.parts > 0) then return false, "no card effects could be applied" end
	revision = revision + 1
	if not Sounds.valid(def.sound) then return true end
	local ticket = { sound = Sounds.valid(def.sound) and def.sound or "", units = {}, expires = clock + duration, created = clock }
	tickets[#tickets + 1] = ticket
	return true, ticket
end
Effects.add_unit = function (ticket, unit) if ticket and alive(unit) then ticket.units[unit] = true end end
Effects.finish = function (ticket, failed) if ticket then ticket.done, ticket.failed = true, ticket.failed or failed == true end end
local function remove_outline(unit, record)
	if alive(unit) then pcall(record.system.remove_outline, record.system, unit, REVEAL) end
	if record.extension.settings == record.owned then
		record.owned[REVEAL] = nil
		local unchanged = true
		for key, value in pairs(record.owned) do if record.previous[key] ~= value then unchanged = false end end
		for key, value in pairs(record.previous) do if record.owned[key] ~= value then unchanged = false end end
		if unchanged then record.extension.settings = record.previous end
	end
	outlines[unit] = nil
end
local function update_reveal()
	if reveal_until <= clock then
		for unit, record in pairs(outlines) do remove_outline(unit, record) end
		return
	end
	local outline = system("outline_system")
	if not outline then return end
	local count = 0
	for _ in pairs(outlines) do count = count + 1 end
	for unit, extension in pairs(outline._unit_extension_data or {}) do
		local data = ext(unit, "unit_data_system")
		local breed = data and data:breed()
		if alive(unit) and breed and breed.tags and breed.tags.special and not outlines[unit] and count < 600 then
			local previous, owned = extension.settings, {}
			for key, value in pairs(extension.settings) do owned[key] = value end
			owned[REVEAL] = { priority = 3, color = { 0.31, 0.61, 0.64 }, material_layers = { "minion_outline", "minion_outline_reversed_depth" }, visibility_check = alive }
			extension.settings = owned
			outlines[unit] = { extension = extension, owned = owned, previous = previous, system = outline }
			outline:add_outline(unit, REVEAL)
			count = count + 1
		end
	end
	for unit, record in pairs(outlines) do if not alive(unit) then remove_outline(unit, record) end end
end
Effects.update = function (dt, paused)
	-- Native buffs continue while the wave scheduler is paused. Timed effects follow the same clock.
	clock = clock + math.max(0, dt)
	cadence = cadence + dt
	if cadence < 0.25 then return end
	cadence = 0
	if blackout_until > 0 then
		if clock >= blackout_until then restore_lights() else blackout(blackout_until - clock) end
	end
	for i = #buffs, 1, -1 do
		local buff = buffs[i]
		if clock >= buff.expires or not alive(buff.unit) then
			if alive(buff.unit) and buff.extension:has_running_buff_with_index(buff.index, buff.component) then pcall(buff.extension.remove_externally_controlled_buff, buff.extension, buff.index, buff.component) end
			table.remove(buffs, i)
		end
	end
	update_reveal()
	if not host() then return end
	for i = #tickets, 1, -1 do
		local ticket = tickets[i]
		for unit in pairs(ticket.units) do if not alive(unit) then ticket.units[unit] = nil end end
		if (ticket.done and not next(ticket.units) and clock >= ticket.expires) or clock - ticket.created > 3600 then
			table.remove(tickets, i)
			if not ticket.failed and ticket.done and ticket.sound ~= "" and clock - ticket.created <= 3600 then
				sequence = sequence + 1
				revision = revision + 1
				audio[#audio + 1] = { sequence, ticket.sound }
				if #audio > 8 then table.remove(audio, 1) end
				play(ticket.sound)
			end
		end
	end
end
Effects.snapshot = function () return { revision = revision, time = clock, reveal = math.max(0, reveal_until - clock), sequence = sequence, audio = audio, grants = grants, grant_sequence = grant_sequence } end
Effects.receive = function (state)
	if host() or type(state) ~= "table" then return end
	local seq = Schema.number(state.sequence, 2147483647)
	if not seq or (received and seq < received) then return end
	local rev, time = Schema.number(state.revision, 2147483647), state.time
	if rev then
		if type(time) ~= "number" or time ~= time or time < 0 or time > 1e12 then return end
		if received_revision and (rev < received_revision or (rev == received_revision and time <= received_time)) then return end
		received_revision, received_time = rev, time
	end
	local grant_seq = Schema.number(state.grant_sequence, 2147483647)
	if grant_seq then
		if grant_received and grant_seq > grant_received and type(state.grants) == "table" then
			local list, spawner = players(), Managers.state.unit_spawner
			for i = 1, math.min(64, #state.grants) do
				local entry = state.grants[i]
				if type(entry) == "table" and type(entry[1]) == "number" and entry[1] > grant_received and entry[1] <= grant_seq and type(entry[3]) == "table" then
					local amount = Schema.number(entry[2], 100)
					for _, player in ipairs(list) do
						local ability = ext(player.unit, "ability_system")
						if amount and ability and ability._is_local_unit and spawner then
							for j = 1, math.min(4, #entry[3]) do
								if entry[3][j] == spawner:game_object_id(player.unit) then
									local ok, err = pcall(ability.restore_ability_resource_percentage, ability, "combat_ability", amount / 100, true)
									if not ok then warn(tostring(err)) end
									break
								end
							end
						end
					end
				end
			end
		end
		grant_received = math.max(grant_received or grant_seq, grant_seq)
	end
	reveal_until = clock + (Schema.number(state.reveal, 300) or 0)
	if received and seq > received and type(state.audio) == "table" then
		for i = 1, math.min(8, #state.audio) do
			local entry = state.audio[i]
			if type(entry) == "table" and type(entry[1]) == "number" and entry[1] > received and entry[1] <= seq then play(entry[2]) end
		end
	end
	received = math.max(received or seq, seq)
end
Effects.cancel = function ()
	revision = revision + 1
	restore_lights()
	reveal_until = 0
	for unit, record in pairs(outlines) do remove_outline(unit, record) end
	for _, buff in ipairs(buffs) do if alive(buff.unit) and buff.extension:has_running_buff_with_index(buff.index, buff.component) then pcall(buff.extension.remove_externally_controlled_buff, buff.extension, buff.index, buff.component) end end
	buffs, tickets = {}, {}
end
Effects.reset = function () Effects.cancel(); clock, sequence, received, audio = 0, 0, nil, {}; grants, grant_sequence, grant_received = {}, 0, nil; revision, received_revision, received_time = 0, nil, nil end
return Effects
