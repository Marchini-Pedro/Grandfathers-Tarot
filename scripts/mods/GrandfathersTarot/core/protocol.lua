-- Realms mod-network layer (adapted from RealmsEvent v2/core/protocol.lua).
--
-- Rules from the Realms docs, all followed here:
--   * get_mod("Realms") and register RPCs in on_all_mods_loaded,
--   * dot-call the Realms API (a colon call shifts `realms` into the mod slot),
--   * validate every received argument,
--   * host -> clients uses "others" (no local loopback to filter out).
--
-- RPCs (prefix rw_):
--   rw_hello   client -> host   proto, version
--   rw_welcome host -> client   proto, version, ok(1/0)
--   rw_state   host -> others   state json (phase, mode, remaining, ballot, candidates; tarot mode: the hand, its winner,
--                               the cards on cooldown)
--   rw_vote    client -> host   ballot_id, option
--   rw_waves   client -> host   the client's enabled waves as one preset text ("RW1|...", catalog/presets.lua);
--                               used only when the host has "use everyone's waves" on
--   rw_scale   host -> others   sizes of spawned units (custom mods, spawn/tuning.lua): a json list of
--                               [network id, percent] (at most 200 a message)
local mod = get_mod("GrandfathersTarot")

local Protocol = {}

-- 2 / 2.0.0: the synced state carries the tarot hand (h, w, sq, dn, y, cd); the handshake refuses older peers
Protocol.PROTO = 2
-- 2.2.0 (2026-10-06): the host's state also goes out while no card cycle runs (`o = 1`: effects, boss bars, health layers)
Protocol.VERSION = get_mod("GrandfathersTarot"):io_dofile("GrandfathersTarot/scripts/mods/GrandfathersTarot/catalog/version")

local RPC_HELLO = "rw_hello"
local RPC_WELCOME = "rw_welcome"
local RPC_STATE = "rw_state"
local RPC_VOTE = "rw_vote"
local RPC_WAVES = "rw_waves"
local RPC_SCALE = "rw_scale"
local RPC_APPEARANCE = "rw_appearance"
local appearance_peers, appearance_epoch = {}, nil
local AppearanceSchema = mod:io_dofile("GrandfathersTarot/scripts/mods/GrandfathersTarot/catalog/appearance")
local MAX_SCALES = 200
Protocol.MIN_SCALE, Protocol.MAX_SCALE = 25, 300 -- percent (the range of the custom mod "size")
local MAX_WAVES_TEXT = 90000 -- raw preset bytes; transport escaping is checked separately
local MAX_WAVES_JSON = 96 * 1024 - 1024 -- reserve 1 KiB for Realms request/delivery envelopes

Protocol.MAX_WAVES_TEXT = MAX_WAVES_TEXT

local _realms = nil
local _handlers = {}
local peers, scale_unsupported = {}, {}
local MAX_PEERS = 16 -- native sessions have three remote players; keep the registry bounded
local retired = false

local function valid_sender(peer_id)
	return type(peer_id) == "string" and peer_id ~= ""
end

local function remember_peer(peer_id)
	if not valid_sender(peer_id) then
		return false
	end

	peer_id = peer_id:lower()

	if not peers[peer_id] then
		local count = 0

		for _ in pairs(peers) do count = count + 1 end

		if count >= MAX_PEERS then return false end
	end

	peers[peer_id] = true
	scale_unsupported[peer_id] = nil

	return true
end

local function on_peer_joined(peer_id)
	if retired then return end

	if remember_peer(peer_id) and _handlers.on_peer_joined then
		_handlers.on_peer_joined(peer_id)
	end
end

local function on_peer_left(peer_id)
	if retired then return end

	if valid_sender(peer_id) then
		peers[peer_id:lower()], scale_unsupported[peer_id:lower()] = nil, nil
		appearance_peers[peer_id:lower()] = nil
	end

	if _handlers.on_peer_left then _handlers.on_peer_left(peer_id) end
end

-- Realms replays its current peers when this callback is registered. Refresh
-- after enable to discard disconnects/capability changes missed while disabled.
Protocol.refresh_peers = function ()
	if retired then return end

	local previous = peers
	peers, scale_unsupported = {}, {}

	if _realms and _realms.network_on_peer_joined then
		_realms.network_on_peer_joined(mod, on_peer_joined)
	end

	for peer in pairs(previous) do
		if not peers[peer] then appearance_peers[peer] = nil end
		if not peers[peer] and _handlers.on_peer_left then _handlers.on_peer_left(peer) end
	end
end

-- Realms can relay client RPCs to other clients. Only the session's host may send state, welcome or unit sizes.
local function valid_host_sender(peer_id)
	local connection = Managers.connection

	if not valid_sender(peer_id) or not connection or not connection.host then
		return false
	end

	local ok, host = pcall(connection.host, connection)

	return ok and type(host) == "string" and host:lower() == peer_id:lower()
end

local function encode(value)
	if type(cjson) ~= "table" or type(cjson.encode) ~= "function" then
		return nil
	end

	local ok, result = pcall(cjson.encode, value)

	return ok and type(result) == "string" and result or nil
end

local function decode(text)
	if type(text) ~= "string" or type(cjson) ~= "table" then
		return nil
	end

	local ok, result = pcall(cjson.decode, text)

	return ok and type(result) == "table" and result or nil
end

Protocol.is_available = function ()
	if not _realms or type(_realms.network_is_available) ~= "function" then
		return false
	end

	local ok, available = pcall(_realms.network_is_available)

	return ok and available == true
end

local function send(rpc_name, recipient, ...)
	if not Protocol.is_available() then
		return false, "Realms network unavailable"
	end

	local ok, sent, send_error = pcall(_realms.network_send, mod, rpc_name, recipient, ...)

	if not ok then
		send_error, sent = sent, false
	end

	if not sent and mod:get("debug") then
		mod:warning("GrandfathersTarot: send %s failed: %s", rpc_name, tostring(send_error))
	end

	return sent, send_error
end

local function on_hello(sender, proto, version, appearance_capability)
	proto = tonumber(proto)

	if retired or not valid_sender(sender) or not proto or type(version) ~= "string" then
		return
	end

	if proto == Protocol.PROTO and version == Protocol.VERSION then
		if remember_peer(sender) then appearance_peers[sender:lower()] = appearance_capability == 1 or nil end
	end

	if _handlers.on_hello then
		_handlers.on_hello(sender, proto, version)
	end
end

local function on_welcome(sender, proto, version, ok, epoch)
	proto, ok = tonumber(proto), tonumber(ok)

	if retired or not valid_host_sender(sender) or not proto or not ok or type(version) ~= "string" then
		return
	end

	appearance_epoch = ok == 1 and proto == Protocol.PROTO and version == Protocol.VERSION and type(epoch) == "string" and epoch ~= "" and #epoch <= 64 and epoch or nil
	if _handlers.on_welcome then
		_handlers.on_welcome(sender, proto, version, ok == 1)
	end
end

local function on_state(sender, state_json)
	local state = not retired and valid_host_sender(sender) and decode(state_json)

	if state and _handlers.on_state then
		_handlers.on_state(sender, state)
	end
end

local function on_vote(sender, ballot_id, option)
	ballot_id, option = tonumber(ballot_id), tonumber(option)

	if retired or not valid_sender(sender) or not ballot_id or not option then
		return
	end

	if _handlers.on_vote then
		_handlers.on_vote(sender, ballot_id, option)
	end
end

local function on_waves(sender, text)
	if retired or not valid_sender(sender) or type(text) ~= "string" or #text > MAX_WAVES_TEXT then
		return
	end

	if _handlers.on_waves then
		_handlers.on_waves(sender, text)
	end
end

-- every entry is checked: a whole network id and a size in percent, clamped to the allowed range
local function on_scale(sender, text)
	local list = not retired and valid_host_sender(sender) and decode(text)

	if not list then
		return
	end

	local entries = {}

	for i = 1, math.min(#list, MAX_SCALES) do
		local item = list[i]
		local id = type(item) == "table" and tonumber(item[1]) or nil
		local pct = type(item) == "table" and tonumber(item[2]) or nil

		if id and pct and id == id and pct == pct and id >= 0 and id <= 4294967295 and id == math.floor(id) then
			entries[#entries + 1] = { id = id, pct = math.max(Protocol.MIN_SCALE, math.min(Protocol.MAX_SCALE, pct)) }
		end
	end

	if #entries > 0 and _handlers.on_scale then
		_handlers.on_scale(sender, entries)
	end
end

local function on_appearance(sender, text)
	if retired or not valid_host_sender(sender) or type(text) ~= "string" or #text > 32768 then return end
	local packet = decode(text)
	-- A host entering later, re-enabling or reloading asks capable clients to repeat the normal version handshake.
	if packet and packet.request == true then Protocol.send_hello(); return end
	if not appearance_epoch or not packet or packet.epoch ~= appearance_epoch or type(packet.entries) ~= "table" then return end
	local entries = {}
	for i = 1, math.min(#packet.entries, MAX_SCALES) do
		local item = packet.entries[i]
		if type(item) == "table" then
			local id, method, breed = item[1], AppearanceSchema.method(item[2]), item[7]
			local valid = type(id) == "number" and id == id and id >= 0 and id <= 4294967295 and id == math.floor(id)
			valid = valid and method and method.available and type(breed) == "string" and #breed <= 80 and breed:match("^[%w_]+$")
			for j = 3, 6 do
				local value = item[j]
				valid = valid and type(value) == "number" and value == value and value >= 0 and value <= 255 and value == math.floor(value)
			end
			valid = valid and (item[8] == nil or type(item[8]) == "boolean") and (item[9] == nil or type(item[9]) == "boolean")
			if valid then entries[#entries + 1] = { id = id, breed = breed, config = { method = item[2], a = item[3], r = item[4], g = item[5], b = item[6], outline = item[8] == true, protect = item[9] == true } } end
		end
	end
	if #entries > 0 and _handlers.on_appearance then _handlers.on_appearance(sender, entries) end
end

Protocol.clear_appearance_session = function () appearance_epoch = nil end
Protocol.request_appearance_sync = function ()
	local json = encode({ request = true })
	return json and send(RPC_APPEARANCE, "others", json) or false
end

-- Optional appearance capability extends hello/welcome without changing the existing HUD protocol.
Protocol.send_appearances = function (epoch, list, recipient)
	local json = encode({ epoch = epoch, entries = list })
	if not json then return false end
	local success = true
	for peer in pairs(appearance_peers) do
		if not recipient or recipient == "others" or recipient:lower() == peer then
			local sent, err = send(RPC_APPEARANCE, peer, json)
			if err == "target_rpc_unsupported" then appearance_peers[peer] = nil else success = sent and success end
		end
	end
	return success
end

-- handlers also include on_appearance.
Protocol.init = function (handlers)
	retired = false
	_handlers = handlers or {}
	_realms = get_mod("Realms")
	peers, scale_unsupported = {}, {}
	appearance_peers, appearance_epoch = {}, nil

	if not _realms then
		mod:warning("GrandfathersTarot: Realms mod not found, network features disabled (solo host only)")

		return
	end

	local rpcs = {
		{ RPC_HELLO, on_hello },
		{ RPC_WELCOME, on_welcome },
		{ RPC_STATE, on_state },
		{ RPC_VOTE, on_vote },
		{ RPC_WAVES, on_waves },
		{ RPC_SCALE, on_scale },
		{ RPC_APPEARANCE, on_appearance },
	}

	for i = 1, #rpcs do
		local registered, register_error = _realms.network_register(mod, rpcs[i][1], rpcs[i][2])

		if not registered then
			mod:error("GrandfathersTarot: register %s failed: %s", rpcs[i][1], tostring(register_error))
		end
	end

	-- Registered after the RPCs, as the Realms docs require.
	Protocol.refresh_peers()

	if _realms.network_on_peer_left then
		_realms.network_on_peer_left(mod, on_peer_left)
	end
end

Protocol.retire = function ()
	retired = true
	_handlers, peers, scale_unsupported = {}, {}, {}
	appearance_peers, appearance_epoch = {}, nil
	_realms = nil
end

Protocol.send_hello = function ()
	return send(RPC_HELLO, "host", Protocol.PROTO, Protocol.VERSION, 1)
end

Protocol.send_welcome = function (peer_id, ok)
	local epoch = mod.rw and mod.rw.appearance and mod.rw.appearance.epoch()
	return send(RPC_WELCOME, peer_id, Protocol.PROTO, Protocol.VERSION, ok and 1 or 0, epoch or "")
end

-- recipient: "others" (default) or a peer id
Protocol.send_state = function (state, recipient)
	local json = encode(state)

	if not json then
		return false, "state encode failed"
	end

	return send(RPC_STATE, recipient or "others", json)
end

Protocol.send_vote = function (ballot_id, option)
	return send(RPC_VOTE, "host", ballot_id, option)
end

-- list = { { network id, percent }, ... }; recipient: "others" (default) or a peer id
Protocol.send_scales = function (list, recipient)
	if type(list) ~= "table" or #list == 0 then
		return false, "nothing to send"
	end

	local json = encode(list)

	if not json then
		return false, "scale encode failed"
	end

	if recipient and recipient ~= "others" then
		return send(RPC_SCALE, recipient, json)
	end

	if next(peers) == nil then
		return send(RPC_SCALE, "others", json)
	end

	-- Realms broadcast returns true after individual rejections. Direct sends
	-- expose those failures to Tuning's existing bounded, current-size retry.
	local recipients = {}
	for peer in pairs(peers) do recipients[#recipients + 1] = peer end
	table.sort(recipients)
	local success, first_error = true, nil

	for i = 1, #recipients do
		local peer = recipients[i]

		if peers[peer] and not scale_unsupported[peer] then
			local sent, err = send(RPC_SCALE, peer, json)

			if not sent then
				if err == "target_rpc_unsupported" then
					if peers[peer] then scale_unsupported[peer] = true end
				else
					success, first_error = false, first_error or err
				end
			end
		end
	end

	return success, first_error
end

-- Realms caps the encoded envelope, so quotes/backslashes in legal card names also count.
Protocol.waves_text_fits = function (text)
	if type(text) ~= "string" or #text > MAX_WAVES_TEXT then
		return false
	end

	local json = encode(text)

	return json ~= nil and #json <= MAX_WAVES_JSON
end

Protocol.send_waves = function (text)
	if not Protocol.waves_text_fits(text) then
		return false, "waves text too long"
	end

	return send(RPC_WAVES, "host", text)
end

return Protocol
