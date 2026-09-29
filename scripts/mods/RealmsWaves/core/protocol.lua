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
--   rw_state   host -> others   state json (phase, mode, remaining, ballot, candidates)
--   rw_vote    client -> host   ballot_id, option
local mod = get_mod("RealmsWaves")

local Protocol = {}

Protocol.PROTO = 1
Protocol.VERSION = "1.0.0"

local RPC_HELLO = "rw_hello"
local RPC_WELCOME = "rw_welcome"
local RPC_STATE = "rw_state"
local RPC_VOTE = "rw_vote"

local _realms = nil
local _handlers = {}

local function valid_sender(peer_id)
	return type(peer_id) == "string" and peer_id ~= ""
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

	local sent, send_error = _realms.network_send(mod, rpc_name, recipient, ...)

	if not sent and mod:get("debug") then
		mod:warning("RealmsWaves: send %s failed: %s", rpc_name, tostring(send_error))
	end

	return sent, send_error
end

local function on_hello(sender, proto, version)
	proto = tonumber(proto)

	if not valid_sender(sender) or not proto or type(version) ~= "string" then
		return
	end

	if _handlers.on_hello then
		_handlers.on_hello(sender, proto, version)
	end
end

local function on_welcome(sender, proto, version, ok)
	proto, ok = tonumber(proto), tonumber(ok)

	if not valid_sender(sender) or not proto or not ok or type(version) ~= "string" then
		return
	end

	if _handlers.on_welcome then
		_handlers.on_welcome(sender, proto, version, ok == 1)
	end
end

local function on_state(sender, state_json)
	local state = valid_sender(sender) and decode(state_json)

	if state and _handlers.on_state then
		_handlers.on_state(sender, state)
	end
end

local function on_vote(sender, ballot_id, option)
	ballot_id, option = tonumber(ballot_id), tonumber(option)

	if not valid_sender(sender) or not ballot_id or not option then
		return
	end

	if _handlers.on_vote then
		_handlers.on_vote(sender, ballot_id, option)
	end
end

-- handlers: { on_hello, on_welcome, on_state, on_vote, on_peer_joined, on_peer_left }
Protocol.init = function (handlers)
	_handlers = handlers or {}
	_realms = get_mod("Realms")

	if not _realms then
		mod:warning("RealmsWaves: Realms mod not found, network features disabled (solo host only)")

		return
	end

	local rpcs = {
		{ RPC_HELLO, on_hello },
		{ RPC_WELCOME, on_welcome },
		{ RPC_STATE, on_state },
		{ RPC_VOTE, on_vote },
	}

	for i = 1, #rpcs do
		local registered, register_error = _realms.network_register(mod, rpcs[i][1], rpcs[i][2])

		if not registered then
			mod:error("RealmsWaves: register %s failed: %s", rpcs[i][1], tostring(register_error))
		end
	end

	-- Registered after the RPCs, as the Realms docs require.
	if _handlers.on_peer_joined then
		_realms.network_on_peer_joined(mod, _handlers.on_peer_joined)
	end

	if _handlers.on_peer_left then
		_realms.network_on_peer_left(mod, _handlers.on_peer_left)
	end
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

return Protocol
