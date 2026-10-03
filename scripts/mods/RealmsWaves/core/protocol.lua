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
local mod = get_mod("RealmsWaves")

local Protocol = {}

-- 2 / 2.0.0: the synced state carries the tarot hand (h, w, sq, dn, y, cd); the handshake refuses older peers
Protocol.PROTO = 2
Protocol.VERSION = "2.0.0"

local RPC_HELLO = "rw_hello"
local RPC_WELCOME = "rw_welcome"
local RPC_STATE = "rw_state"
local RPC_VOTE = "rw_vote"
local RPC_WAVES = "rw_waves"
local RPC_SCALE = "rw_scale"
local MAX_SCALES = 200
Protocol.MIN_SCALE, Protocol.MAX_SCALE = 25, 300 -- percent (the range of the custom mod "size")
local MAX_WAVES_TEXT = 60000 -- the Realms limit is 96 KiB per message; a full setup is about 15 KB

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
		mod:warning("RealmsWaves: send %s failed: %s", rpc_name, tostring(send_error))
	end

	return sent, send_error
end

local function on_hello(sender, proto, version)
	proto = tonumber(proto)

	if retired or not valid_sender(sender) or not proto or type(version) ~= "string" then
		return
	end

	if proto == Protocol.PROTO and version == Protocol.VERSION then
		remember_peer(sender)
	end

	if _handlers.on_hello then
		_handlers.on_hello(sender, proto, version)
	end
end

local function on_welcome(sender, proto, version, ok)
	proto, ok = tonumber(proto), tonumber(ok)

	if retired or not valid_host_sender(sender) or not proto or not ok or type(version) ~= "string" then
		return
	end

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

-- handlers: { on_hello, on_welcome, on_state, on_vote, on_waves, on_scale, on_peer_joined, on_peer_left }
Protocol.init = function (handlers)
	retired = false
	_handlers = handlers or {}
	_realms = get_mod("Realms")
	peers, scale_unsupported = {}, {}

	if not _realms then
		mod:warning("RealmsWaves: Realms mod not found, network features disabled (solo host only)")

		return
	end

	local rpcs = {
		{ RPC_HELLO, on_hello },
		{ RPC_WELCOME, on_welcome },
		{ RPC_STATE, on_state },
		{ RPC_VOTE, on_vote },
		{ RPC_WAVES, on_waves },
		{ RPC_SCALE, on_scale },
	}

	for i = 1, #rpcs do
		local registered, register_error = _realms.network_register(mod, rpcs[i][1], rpcs[i][2])

		if not registered then
			mod:error("RealmsWaves: register %s failed: %s", rpcs[i][1], tostring(register_error))
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
	_realms = nil
end

Protocol.send_hello = function ()
	return send(RPC_HELLO, "host", Protocol.PROTO, Protocol.VERSION)
end

Protocol.send_welcome = function (peer_id, ok)
	return send(RPC_WELCOME, peer_id, Protocol.PROTO, Protocol.VERSION, ok and 1 or 0)
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

Protocol.send_waves = function (text)
	if type(text) ~= "string" or #text > MAX_WAVES_TEXT then
		return false, "waves text too long"
	end

	return send(RPC_WAVES, "host", text)
end

return Protocol
