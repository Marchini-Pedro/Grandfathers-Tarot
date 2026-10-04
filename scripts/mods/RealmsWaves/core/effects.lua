-- Native gameplay effects run on the host. Guidance (Buffs: reveal Specialists) and completion audio render locally.
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
-- Completion audio: a card's text holds one or two sounds, each with a volume (catalog/sounds.lua). The second starts when the first
-- ends (WwiseWorld.is_playing); nothing waits longer than CHAIN_LONGEST, and a sound without an id lets the next follow after
-- CHAIN_GAP seconds.
-- Where it plays (2026-10-04 fix: no card sound was heard): almost every event of the list is a 3D game sound, and an event triggered
-- without a source plays at the world's origin, far from the listener, so nothing was heard. Each sound now plays on an auto source on
-- the local player's unit, in the level's own sound world (where the listener is), as the game plays the player's own sounds
-- (player_unit_fx_extension.lua). Without a player unit (a menu) it falls back to the UI world with no source (2D events only).
-- Volume below 100 sets the game's sfx volume parameter on that source: EXPERIMENTAL (no per-sound volume exists). Volume 0 never plays.
local CHAIN_GAP, CHAIN_LONGEST = 2.5, 12
local chain, audio_clock = {}, 0
local function listener_unit()
	local manager = Managers.player
	local player = manager and (manager.local_player_safe and manager:local_player_safe(1) or manager:local_player(1))
	local unit = player and player.player_unit
	return unit and Unit.alive(unit) and unit or nil
end
-- A voice line ("loc_..." from the game's dialogues) is a streamed file, played as the game plays the local player's own lines: the
-- 2D player voice route on a source (scripts/settings/dialogue/wwise_vo_routing_settings.lua, dialogue_extension.lua play_event)
local VO_EVENT, VO_SOURCE = "wwise/events/vo/play_sfx_es_player_vo_2d", "es_player_vo_2d"
local function voice_line(event) return event:sub(1, 4) == "loc_" end
local function fire(wwise, event, source)
	if voice_line(event) then
		return WwiseWorld.trigger_resource_external_event(wwise, VO_EVENT, VO_SOURCE, "wwise/externals/" .. event, 4, source)
	end
	if source then return WwiseWorld.trigger_resource_event(wwise, event, source) end
	return WwiseWorld.trigger_resource_event(wwise, event)
end
local function trigger(event, volume)
	if not Managers.world then return nil end
	local unit = listener_unit()
	local level = unit and Managers.world:has_world("level_world") and Managers.world:world("level_world")
	if level then
		local wwise = Managers.world:wwise_world(level)
		local source = WwiseWorld.make_auto_source(wwise, unit)
		if volume < 100 then
			local sfx = Application and Application.user_setting and Application.user_setting("sound_settings", "options_sfx_slider") or 100
			pcall(WwiseWorld.set_source_parameter, wwise, source, "options_sfx_slider", sfx * volume / 100)
		end
		return fire(wwise, event, source), wwise
	end
	local world = Managers.ui and Managers.ui:world()
	if not world then return nil end
	local wwise = Managers.world:wwise_world(world)
	return fire(wwise, event, voice_line(event) and WwiseWorld.make_manual_source(wwise, Vector3.zero(), Quaternion.identity()) or nil), wwise
end
local function start_entry(list, index)
	local entry = list[index]
	if not entry then return end
	if entry.volume <= 0 then return start_entry(list, index + 1) end
	local ok, id, wwise = pcall(trigger, entry.event, entry.volume)
	if not ok then warn("sound unavailable: " .. tostring(id)); id, wwise = nil, nil end
	if list[index + 1] then
		chain[#chain + 1] = { list = list, next = index + 1, id = id, wwise = wwise, started = audio_clock }
		if #chain > 8 then table.remove(chain, 1) end
	end
end
local function play(text)
	if mod:get("card_sounds") == false then return end
	local list = Sounds.parse(text)
	if #list > 0 then start_entry(list, 1) end
end
Effects.preview_sound = play
-- Every frame, everywhere (the editor's preview plays in the hub too): the second sounds of the chain.
Effects.tick_audio = function (dt)
	audio_clock = audio_clock + math.max(0, tonumber(dt) or 0)
	for i = #chain, 1, -1 do
		local item = chain[i]
		local age, done = audio_clock - item.started, false
		if age >= CHAIN_LONGEST then done = true
		elseif item.id and item.wwise then
			local ok, playing = pcall(WwiseWorld.is_playing, item.wwise, item.id)
			done = not ok or not playing
		else done = age >= CHAIN_GAP end
		if done then
			table.remove(chain, i)
			start_entry(item.list, item.next)
		end
	end
end
Effects.chain_size = function () return #chain end
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
-- Raise the fallen: a knocked-down player is helped up the way a Veteran's shout and the servo skull do it (the native assisted
-- state input, written on the host: scripts/extension_systems/ability/utilities/shout_ability.lua). Only knocked-down players,
-- never the netted, pounced or dead; at most `count` of them, in the party's stable order.
local function revive(list, count)
	local Status = require("scripts/utilities/attack/player_unit_status")
	local raised = 0
	for _, player in ipairs(list) do
		if raised >= count then break end
		local data = ext(player.unit, "unit_data_system")
		local state = data and data:read_component("character_state")
		if state and Status.is_knocked_down(state) then
			local input = data:write_component("assisted_state_input")
			if input and not Status.is_assisted(input) then
				input.force_assist = true
				raised = raised + 1
			end
		end
	end
	return raised > 0, "nobody is knocked down"
end
-- Refill ammunition: `percent` of every weapon's reserve, through the native helper the Veteran's coherency talents use on the host
-- (scripts/utilities/ammo.lua Ammo.add_to_all_slots). A full reserve stays full; weapons without ammunition are skipped.
local function refill(list, percent)
	local Ammo = require("scripts/utilities/ammo")
	local gained = 0
	for _, player in ipairs(list) do
		if ext(player.unit, "unit_data_system") and ext(player.unit, "visual_loadout_system") then
			local ok, amount = pcall(Ammo.add_to_all_slots, player.unit, percent / 100)
			if ok then gained = gained + (tonumber(amount) or 0) else warn(tostring(amount)) end
		end
	end
	return gained > 0, "everyone's ammunition is already full"
end
local function apply(id, effect, list)
	if id == "blackout" then return blackout(effect.value) end
	if id == "revive" then return revive(list, effect.value) end
	if id == "ammo" then return refill(list, effect.value) end
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
	if Sounds.has(def.sound) and #tickets >= 64 then return false, "64 unfinished sounding cards are already tracked" end
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
	if not Sounds.has(def.sound) then return true end
	local ticket = { sound = Sounds.encode(Sounds.parse(def.sound)), units = {}, expires = clock + duration, created = clock }
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
Effects.reset = function () Effects.cancel(); chain = {}; clock, sequence, received, audio = 0, 0, nil, {}; grants, grant_sequence, grant_received = {}, 0, nil; revision, received_revision, received_time = 0, nil, nil end
return Effects
