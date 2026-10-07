-- Native gameplay effects run on the host. Guidance (Buffs: reveal Specialists, reveal Elites), the Blackout's lights and completion
-- audio render locally, on every machine.
local mod = get_mod("GrandfathersTarot")
local Schema = mod:io_dofile("GrandfathersTarot/scripts/mods/GrandfathersTarot/catalog/effects")
local Sounds = mod:io_dofile("GrandfathersTarot/scripts/mods/GrandfathersTarot/catalog/sounds")
local Effects = {}
local clock, cadence, reveal_until, blackout_until = 0, 0, 0, 0
local reveal_elites_until = 0
local lights, buffs, outlines, audio = {}, {}, {}, {}
local sequence, received, warned = 0, nil, {}
local grants, grant_sequence, grant_received = {}, 0, nil
local rescues_left = 0 -- Instant rescue: how many of the next players to go down are helped up at once (host)
local received_rescues = 0 -- a client: the host's rescues_left (the golden health bars)
-- Raise the fallen: rescued players waiting to be brought back once they stand (host); BRING_WAIT seconds at most
local pending_bring, BRING_WAIT = {}, 15
local revision, received_revision, received_time = 0, nil, nil
local REVEAL = "rw_guidance"
local function alive(unit) return unit and Unit.alive(unit) and (not HEALTH_ALIVE or HEALTH_ALIVE[unit] ~= false) end
local function ext(unit, name) return alive(unit) and ScriptUnit.has_extension(unit, name) end
-- The player units this machine controls (a client applies the host's grants to them): its local player through the player manager
-- (2026-10-04: the party list a client builds may miss its own unit), else the party's units whose ability is local.
local function own_players()
	local manager = Managers.player
	local find = manager and (manager.local_player_safe or manager.local_player)
	local ok, player = pcall(function () return find and find(manager, 1) end)
	if ok and player and alive(player.player_unit) and ScriptUnit.has_extension(player.player_unit, "ability_system") then
		return { { id = "local", unit = player.player_unit } }
	end
	local list = {}
	for id, other in pairs(manager and manager:players() or {}) do
		if alive(other.player_unit) then list[#list + 1] = { id = tostring(id), unit = other.player_unit } end
	end
	table.sort(list, function (a, b) return a.id < b.id end)
	return list
end
local function host()
	local session = Managers.state and Managers.state.game_session
	return session and session:is_server() == true
end
local function warn(message)
	if not warned[message] then warned[message] = true; mod:warning("GrandfathersTarot card effects: %s", message) end
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
local CHAIN_GAP, CHAIN_LONGEST, CHAIN_MIN = 2.5, 12, 0.3
local chain, audio_clock = {}, 0
local previews = {} -- the editor's previews still playing: { wwise world, playing id } (Stop all sound previews)
local function listener_unit()
	local manager = Managers.player
	local find = manager and (manager.local_player_safe or manager.local_player)
	local player = find and find(manager, 1)
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
-- `job` (an alert, see Effects.alert) is marked done when the last sound of the list has ended
local function start_entry(list, index, job)
	local entry = list[index]
	if not entry then
		if job then job.done = true end
		return
	end
	if entry.volume <= 0 then return start_entry(list, index + 1, job) end
	local ok, id, wwise = pcall(trigger, entry.event, entry.volume)
	if not ok then warn("sound unavailable: " .. tostring(id)); id, wwise = nil, nil end
	-- (2026-10-05: the syringe sounds stayed silent) Wwise answers 0 when it cannot start an event, usually because the sound is
	-- only loaded with the item that uses it (the stimm syringes): a preview says so instead of staying silent
	if job and job.preview and ok and (id == nil or id == 0) and mod.localize and mod.echo then
		mod:echo("%s", mod:localize("snd_not_loaded", tostring(entry.event):match("[^/]+$") or tostring(entry.event)))
	end
	if job and job.preview and id and wwise then
		previews[#previews + 1] = { wwise, id }
		if #previews > 32 then table.remove(previews, 1) end
	end
	if list[index + 1] or job then
		chain[#chain + 1] = { list = list, next = index + 1, id = id, wwise = wwise, started = audio_clock, job = job }
		if #chain > 8 then table.remove(chain, 1) end
	end
end
-- Plays a card's sound text; returns the job { done } of the whole list (nil when muted or silent)
local function play(text, preview)
	if mod:get("card_sounds") == false then return nil end
	local list = Sounds.parse(text)
	if #list == 0 then return nil end
	local job = { done = false, preview = preview == true }
	start_entry(list, 1, job)
	return job
end
Effects.preview_sound = function (text) return play(text, true) end
-- (2026-10-05, the user: a "stop all sound previews" button) stops every preview still playing, and the second sounds they wait
-- to start; a card's real sound at a draw is not a preview and keeps playing. Returns how many were stopped.
Effects.stop_previews = function ()
	local stopped = 0
	for _, item in ipairs(previews) do
		if pcall(WwiseWorld.stop_event, item[1], item[2]) then stopped = stopped + 1 end
	end
	previews = {}
	for i = #chain, 1, -1 do
		if chain[i].job and chain[i].job.preview then chain[i].job.done = true; table.remove(chain, i) end
	end
	return stopped
end
-- Every frame, everywhere (the editor's preview plays in the hub too): the second sounds of the chain.
Effects.tick_audio = function (dt)
	audio_clock = audio_clock + math.max(0, tonumber(dt) or 0)
	for i = #chain, 1, -1 do
		local item = chain[i]
		local age, done = audio_clock - item.started, false
		if age >= CHAIN_LONGEST then done = true
		elseif item.id and item.wwise then
			-- (a sound may not report itself as playing on its first frame: never done before CHAIN_MIN)
			local ok, playing = pcall(WwiseWorld.is_playing, item.wwise, item.id)
			done = age >= CHAIN_MIN and (not ok or not playing)
		else done = age >= CHAIN_GAP end
		if done then
			table.remove(chain, i)
			start_entry(item.list, item.next, item.job)
		end
	end
end
Effects.chain_size = function () return #chain end
-- (2026-10-06, a client crashed during a Blackout: the game's rpc_light_controller_set_enabled reached a level light that has no
-- light controller extension on that machine, and LightControllerSystem indexes it without a check) The lights are switched
-- "deterministically", the way level flow does it: no RPC is sent. Every machine darkens its own lights for the time the host's
-- state gives (Effects.snapshot `blackout`); a client runs Effects.update too.
local function restore_lights()
	for unit, saved in pairs(lights) do
		if alive(unit) then pcall(saved.extension.set_enabled, saved.extension, saved.enabled, true) end
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
			if extension:is_enabled() then extension:set_enabled(false, true) end
			changed = true
		end
	end
	if changed then blackout_until = math.max(blackout_until, clock + seconds) end
	return changed, "this level has no controllable lights"
end
local ITEMS = {
	green_stimm = { "content/items/pocketable/syringe_corruption_pocketable", "slot_pocketable_small" },
	yellow_stimm = { "content/items/pocketable/syringe_ability_boost_pocketable", "slot_pocketable_small" },
	blue_stimm_item = { "content/items/pocketable/syringe_speed_boost_pocketable", "slot_pocketable_small" },
	red_stimm_item = { "content/items/pocketable/syringe_power_boost_pocketable", "slot_pocketable_small" },
	med_crate = { "content/items/pocketable/med_crate_pocketable", "slot_pocketable" },
	ammo_crate = { "content/items/pocketable/ammo_cache_pocketable", "slot_pocketable" },
}
-- the stimm buffs (scripts/settings/buff/syringe_buff_templates.lua, 15 s each natively; the card's seconds replace that)
local STIMM_BUFFS = { yellow_stimm_buff = "syringe_ability_boost_buff", blue_stimm = "syringe_speed_boost_buff", red_stimm_buff = "syringe_power_boost_buff" }
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
-- Raise the fallen (2026-10-04, second version, the user: "rescue one hogtied player and teleport them to the nearest alive player";
-- the downed revive is gone, Instant rescue does that). The hogtied player is freed by the native assist with force_assist: the
-- hogtied state's Assist (character_states/utilities/assist.lua) only completes an assist it has started, from an interaction or
-- force_assist; writing `success` alone did nothing (the first version's bug, seen in game). The player is then brought to the
-- nearest living player who is up: the host moves its own player and the bots (PlayerMovement.teleport); a remote human's own game
-- does it from the effects journal (a "teleport" grant, below), since a human's movement is theirs. Never a player already being
-- helped; `count` (1) of them, in the party's stable order.
local function state_of(unit)
	local data = ext(unit, "unit_data_system")
	return data, data and data:read_component("character_state")
end
local function nearest_standing(list, unit, Status)
	local best, best_d = nil, math.huge
	for _, other in ipairs(list) do
		local _, state = state_of(other.unit)
		if other.unit ~= unit and state and not Status.is_hogtied(state) and not Status.is_knocked_down(state) and not (Status.is_disabled and Status.is_disabled(state)) then
			local d = Vector3.distance_squared(Unit.world_position(other.unit, 1), Unit.world_position(unit, 1))
			if d < best_d then best, best_d = other.unit, d end
		end
	end
	return best
end
local function bring(unit, position)
	local spawn = Managers.state.player_unit_spawn
	local player = spawn and spawn:owner(unit)
	if not player then return false end
	if not player.remote or not player:is_human_controlled() then
		require("scripts/utilities/player_movement").teleport(player, position)
		return true
	end
	local object = Managers.state.unit_spawner and Managers.state.unit_spawner:game_object_id(unit)
	if not object then return false end
	-- (old peers read a grant as an ability restore of entry[2] percent: 0, harmless)
	grant_sequence = grant_sequence + 1
	grants[#grants + 1] = { grant_sequence, 0, { object }, "teleport", { position.x, position.y, position.z } }
	if #grants > 64 then table.remove(grants, 1) end
	return true
end
Effects.bring = bring
local function revive(list, count)
	local Status = require("scripts/utilities/attack/player_unit_status")
	local freed = 0
	for _, player in ipairs(list) do
		local data, state = state_of(player.unit)
		local input = state and data:write_component("assisted_state_input")
		if freed < count and input and not Status.is_assisted(input) and Status.is_hogtied(state) then
			input.force_assist = true
			freed = freed + 1
			if #pending_bring < 8 then pending_bring[#pending_bring + 1] = { unit = player.unit, until_t = clock + BRING_WAIT } end
		end
	end
	return freed > 0, "nobody is hogtied"
end
-- Every quarter second on the host: a rescued player who stands again is brought to the nearest standing player (their position now)
local function bring_pending(list)
	local Status = require("scripts/utilities/attack/player_unit_status")
	for i = #pending_bring, 1, -1 do
		local item = pending_bring[i]
		local _, state = state_of(item.unit)
		if not state or clock > item.until_t then
			table.remove(pending_bring, i)
		elseif not Status.is_hogtied(state) and not Status.is_knocked_down(state) then
			table.remove(pending_bring, i)
			local near = nearest_standing(list, item.unit, Status)
			if near then
				local ok, err = pcall(bring, item.unit, Unit.world_position(near, 1))
				if not ok then warn("the rescued player was not brought back: " .. tostring(err)) end
			end
		end
	end
end
Effects.pending_bring = function () return #pending_bring end
-- Instant rescue: the next players to go down are helped up at once (checked every quarter second on the host, Effects.update)
local function instant_rescue(list)
	local Status = require("scripts/utilities/attack/player_unit_status")
	for _, player in ipairs(list) do
		if rescues_left <= 0 then return end
		local data, state = state_of(player.unit)
		local input = state and Status.is_knocked_down(state) and data:write_component("assisted_state_input")
		if input and not Status.is_assisted(input) and not input.force_assist then
			input.force_assist = true
			rescues_left = rescues_left - 1
		end
	end
end
Effects.rescues_left = function () return rescues_left end
-- Instant rescue charges armed for the team, on any machine (the host's own count, or the one it sent)
Effects.team_rescues = function () if host() then return rescues_left end return received_rescues end
-- Replenish grenades: `charges` grenade charges for every living player, on the host as the grenade pickup does it
-- (scripts/extension_systems/interaction/interactions/grenade_interaction.lua: restore_ability_charge("grenade_ability")). A player
-- without a grenade ability, or whose grenades are full, gets nothing.
local function grenades(list, charges)
	local given = 0
	for _, player in ipairs(list) do
		local ability = ext(player.unit, "ability_system")
		if ability and ability.restore_ability_charge and (not ability.ability_is_equipped or ability:ability_is_equipped("grenade_ability")) then
			local ok, _, restored = pcall(ability.restore_ability_charge, ability, "grenade_ability", charges)
			if ok then given = given + (tonumber(restored) or charges) else warn(tostring(_)) end
		end
	end
	return given > 0, "nobody has a grenade ability to replenish"
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
	if id == "grenades" then return grenades(list, effect.value) end
	if id == "instant_rescue" then rescues_left = math.min(4, rescues_left + effect.value); return true end
	if id == "reveal" then reveal_until = math.max(reveal_until, clock + effect.value); return true end
	if id == "reveal_elites" then reveal_elites_until = math.max(reveal_elites_until, clock + effect.value); return true end
	if id == "med_station" then return recharge(list, effect.value) end
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
			elseif STIMM_BUFFS[id] and count < effect.players then
				local buff = ext(unit, "buff_system")
				if buff and #buffs < 256 then
					local _, index, component = buff:add_externally_controlled_buff(STIMM_BUFFS[id], game_time())
					if index then
						local instance = buff._buffs_by_index and buff._buffs_by_index[index]
						buffs[#buffs + 1] = { unit = unit, extension = buff, index = index, component = component, expires = clock + effect.value }
						if not instance or not instance.add_duration then error("native stimm buff duration is unavailable") end
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
	return true
end
-- The card's sound as an ALERT (2026-10-04, the user: "the sound should play the moment the card is selected during the draw, like an
-- alert; once it finishes playing, the wave should spawn"). It replaces the old completion sound (played when the wave's enemies were
-- all dead). The host plays it at once and writes it in the audio journal, so every player hears it with the next state; the returned
-- job { done } says when the host's sound has ended (the director holds the wave until then). nil: no sound to wait for (none set, or
-- the host muted card sounds: the others still hear it).
Effects.alert = function (text)
	if not host() or not Sounds.has(text) then return nil end
	sequence = sequence + 1
	revision = revision + 1
	audio[#audio + 1] = { sequence, Sounds.encode(Sounds.parse(text)) }
	if #audio > 8 then table.remove(audio, 1) end
	return play(text)
end
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
-- Reveal Specialists (teal) and Reveal Elites (amber, 2026-10-06): each kind is outlined while its own time runs
local REVEAL_COLOURS = { special = { 0.31, 0.61, 0.64 }, elite = { 0.86, 0.56, 0.16 } }
local function reveal_kind(tags)
	if not tags then return nil end
	if tags.special then return reveal_until > clock and "special" or nil end
	if tags.elite then return reveal_elites_until > clock and "elite" or nil end
	return nil
end
local breed_tags = setmetatable({}, { __mode = "k" }) -- unit -> its breed's tags (false: none), read once
local function update_reveal()
	if reveal_until <= clock and reveal_elites_until <= clock then
		for unit, record in pairs(outlines) do remove_outline(unit, record) end
		return
	end
	for unit, record in pairs(outlines) do
		if record.kind == "special" and reveal_until <= clock or record.kind == "elite" and reveal_elites_until <= clock then remove_outline(unit, record) end
	end
	local outline = system("outline_system")
	if not outline then return end
	local count = 0
	for _ in pairs(outlines) do count = count + 1 end
	for unit, extension in pairs(outline._unit_extension_data or {}) do
		-- (2026-10-06, a performance pass) a unit's breed never changes: its tags are read once (this runs four times a second
		-- over every enemy while a reveal lasts), and an outlined one is skipped before anything is read
		local kind = nil
		if not outlines[unit] and count < 600 and alive(unit) then
			local tags = breed_tags[unit]
			if tags == nil then
				local data = ext(unit, "unit_data_system")
				local breed = data and data:breed()
				tags = breed and breed.tags or false
				-- (only once its breed could be read: a unit whose data is not there yet is asked again)
				if data then breed_tags[unit] = tags end
			end
			kind = reveal_kind(tags)
		end
		if kind then
			local previous, owned = extension.settings, {}
			for key, value in pairs(extension.settings) do owned[key] = value end
			owned[REVEAL] = { priority = 3, color = REVEAL_COLOURS[kind], material_layers = { "minion_outline", "minion_outline_reversed_depth" }, visibility_check = alive }
			extension.settings = owned
			outlines[unit] = { extension = extension, owned = owned, previous = previous, system = outline, kind = kind }
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
	if rescues_left > 0 and host() then
		local ok, err = pcall(instant_rescue, players())
		if not ok then warn("instant rescue: " .. tostring(err)) end
	end
	if #pending_bring > 0 and host() then
		local ok, err = pcall(bring_pending, players())
		if not ok then warn("raise the fallen: " .. tostring(err)) end
	end
end
Effects.snapshot = function () return { revision = revision, time = clock, reveal = math.max(0, reveal_until - clock), reveal_elites = math.max(0, reveal_elites_until - clock), blackout = math.max(0, blackout_until - clock), sequence = sequence, audio = audio, grants = grants, grant_sequence = grant_sequence, rescue = rescues_left } end
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
			local list, spawner = own_players(), Managers.state.unit_spawner
			for i = 1, math.min(64, #state.grants) do
				local entry = state.grants[i]
				if type(entry) == "table" and entry[4] == "teleport" and type(entry[1]) == "number" and entry[1] > grant_received and entry[1] <= grant_seq and type(entry[3]) == "table" and type(entry[5]) == "table" then
					-- Raise the fallen: this player's own game brings them to the others
					local p = entry[5]
					for _, player in ipairs(list) do
						local ability = ext(player.unit, "ability_system")
						if ability and ability._is_local_unit and spawner and entry[3][1] == spawner:game_object_id(player.unit) and type(p[1]) == "number" and type(p[2]) == "number" and type(p[3]) == "number" then
							local owner = Managers.state.player_unit_spawn and Managers.state.player_unit_spawn:owner(player.unit)
							local ok, err = pcall(function () require("scripts/utilities/player_movement").teleport(owner, Vector3(p[1], p[2], p[3])) end)
							if not ok then warn(tostring(err)) elseif mod.info then mod:info("GrandfathersTarot card effects: brought back to the others (Raise the fallen)") end
						end
					end
				end
			end
		end
		grant_received = math.max(grant_received or grant_seq, grant_seq)
	end
	reveal_until = clock + (Schema.number(state.reveal, 300) or 0)
	reveal_elites_until = clock + (Schema.number(state.reveal_elites, 300) or 0)
	-- the Blackout: this machine darkens its own lights (Effects.update) until the host's time is up
	local dark = Schema.number(state.blackout, 3600) or 0
	if dark > 0 then blackout_until = clock + dark elseif blackout_until > 0 then restore_lights() end
	received_rescues = Schema.number(state.rescue, 4) or 0
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
	reveal_until, reveal_elites_until = 0, 0
	for unit, record in pairs(outlines) do remove_outline(unit, record) end
	for _, buff in ipairs(buffs) do if alive(buff.unit) and buff.extension:has_running_buff_with_index(buff.index, buff.component) then pcall(buff.extension.remove_externally_controlled_buff, buff.extension, buff.index, buff.component) end end
	buffs = {}
	rescues_left, received_rescues = 0, 0
	pending_bring = {}
end
Effects.reset = function () Effects.cancel(); chain = {}; clock, sequence, received, audio = 0, 0, nil, {}; grants, grant_sequence, grant_received = {}, 0, nil; revision, received_revision, received_time = 0, nil, nil end
return Effects
