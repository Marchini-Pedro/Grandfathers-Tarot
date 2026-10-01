-- Wave director: timer, event selection, vote handling, state sync.
--
-- Host is authoritative. Each cycle it draws the next wave (random mode: one
-- pending wave; vote mode: a ballot of N candidates, all visible from the start
-- of the countdown so players see "the next possible waves"). Votes are accepted
-- during the whole countdown; the last `vote_duration` seconds are the highlighted
-- "voting" phase. At zero the wave spawns and an "incoming" banner state is shown.
--
-- Phases: off | waiting | voting | incoming
-- Clients only render the last state received from the host and cast votes.
local mod = get_mod("RealmsWaves")

local Director = {}

local Events, Groups, Protocol, Execute, Votes, Positions

local INCOMING_SECONDS = 6
local EMPTY_POOL_RETRY = 20
local SEND_INTERVAL = 1

local host_state = nil
local client_state = nil
local client_received_at = 0
local client_disabled = false

local clock = 0
local send_timer = 0
local changed = true
local version = 0
local started = false
local in_mission = false
local gameplay_active = false
local start_signal = false
local recheck_timer = 0
local ballot_seq = 0
local last_fired = {}
local my_vote, my_vote_ballot = nil, nil

local view = { phase = "off", mode = "random", remaining = 0, ballot_id = 0, chosen = "", cands = {}, version = 0, my_vote = nil }

local function number_setting(id, fallback)
	local value = tonumber(mod:get(id))

	if not value or value ~= value then
		return fallback
	end

	return value
end

local function get_setting(id)
	return mod:get(id)
end

local function now()
	local time_manager = Managers.time

	if time_manager then
		local ok, t = pcall(time_manager.time, time_manager, "main")

		if ok and type(t) == "number" then
			return t
		end
	end

	return clock
end

Director.is_host = function ()
	local game_session = Managers.state and Managers.state.game_session

	return game_session ~= nil and game_session:is_server() == true
end

Director.init = function (deps)
	Events = deps.events
	Groups = deps.groups
	Protocol = deps.protocol
	Execute = deps.execute
	Votes = deps.votes
	Positions = deps.positions
end

local function mark_changed()
	changed = true
	version = version + 1
end

-- ---------------------------------------------------------------- selection

local function weighted_pick(list)
	local total = 0

	for i = 1, #list do
		total = total + list[i].raw
	end

	if total <= 0 then
		return nil
	end

	local roll = math.random() * total

	for i = 1, #list do
		roll = roll - list[i].raw

		if roll <= 0 then
			return i
		end
	end

	return #list
end

-- Draws up to n distinct entries by weight, preferring events that are off cooldown.
local function draw(pool, n)
	local fresh, cooling = {}, {}

	for i = 1, #pool do
		local entry = pool[i]
		local since = last_fired[entry.key]

		if since == nil or clock - since >= entry.cooldown then
			fresh[#fresh + 1] = entry
		else
			cooling[#cooling + 1] = entry
		end
	end

	local picks = {}

	local function take_from(list)
		while #picks < n and #list > 0 do
			local index = weighted_pick(list)

			if not index then
				return
			end

			picks[#picks + 1] = table.remove(list, index)
		end
	end

	take_from(fresh)
	take_from(cooling)

	return picks
end

local function round1(value)
	return math.floor(value * 10 + 0.5) / 10
end

local function random_interval(first)
	local low = math.max(5, number_setting("interval_min", 150))
	local high = math.max(low, number_setting("interval_max", 300))
	-- random: anywhere between the minimum and the maximum; otherwise always the minimum (a fixed time)
	local interval = mod:get("interval_random") == false and low or low + math.random() * (high - low)

	if first then
		interval = interval + number_setting("initial_delay", 45)
	end

	return interval
end

local function start_cycle(first)
	local mode = mod:get("mode") == "vote" and "vote" or "random"
	local pool = Events.build_pool(get_setting, Groups)

	ballot_seq = ballot_seq + 1

	if #pool == 0 then
		host_state = { phase = "waiting", mode = mode, remaining = EMPTY_POOL_RETRY, ballot_id = ballot_seq, chosen = "", cands = {}, empty = true }
		Votes.close()
		mark_changed()

		return
	end

	local count = mode == "vote" and math.max(2, math.min(5, number_setting("ballot_size", 3))) or 1
	local picks = draw(pool, count)
	local cands = {}

	for i = 1, #picks do
		cands[i] = { key = picks[i].key, name = picks[i].name, pct = round1(picks[i].pct), votes = 0, def = picks[i].def, raw = picks[i].raw }
	end

	local interval = random_interval(first)

	host_state = {
		phase = "waiting",
		mode = mode,
		remaining = interval,
		-- the highlighted voting window can never be longer than the whole countdown
		vote_window = math.min(number_setting("vote_duration", 25), interval),
		ballot_id = ballot_seq,
		chosen = "",
		cands = cands,
	}

	if mode == "vote" then
		Votes.open(ballot_seq, #cands)
	else
		Votes.close()
	end

	mark_changed()
end

local function fire(cand)
	local ok, err = Execute.start_wave(cand.def)

	if not ok then
		mod:warning("RealmsWaves: wave %s not started: %s", tostring(cand.key), tostring(err))
	end

	last_fired[cand.key] = clock
	host_state.phase = "incoming"
	host_state.remaining = INCOMING_SECONDS
	host_state.chosen = cand.name
	host_state.cands = {}
	Votes.close()
	mark_changed()
end

local function resolve()
	local state = host_state
	local cands = state.cands

	if state.empty or #cands == 0 then
		start_cycle(false)

		return
	end

	local index = 1

	if state.mode == "vote" then
		index = Votes.winner()

		if not index then
			if mod:get("novote_fallback") == "skip" then
				state.phase = "incoming"
				state.remaining = INCOMING_SECONDS
				state.chosen = mod:localize("hud_no_votes")
				state.cands = {}
				Votes.close()
				mark_changed()

				return
			end

			index = weighted_pick(cands) or 1
		end
	end

	fire(cands[index])
end

-- ----------------------------------------------------------------- host tick

local function refresh_votes()
	local state = host_state

	if state and state.mode == "vote" and #state.cands > 0 then
		local counts = Votes.counts()

		for i = 1, #state.cands do
			state.cands[i].votes = counts[i] or 0
		end
	end
end

local function snapshot()
	refresh_votes()

	local state = host_state
	local k = {}

	for i = 1, #state.cands do
		local cand = state.cands[i]

		k[i] = { k = cand.key, n = cand.name, p = cand.pct, v = cand.votes }
	end

	return { p = state.phase, m = state.mode, r = round1(state.remaining), b = state.ballot_id, c = state.chosen, k = k, e = state.empty and 1 or 0 }
end

local function broadcast()
	if host_state and Protocol.is_available() then
		Protocol.send_state(snapshot(), "others")
	end
end

local function try_start()
	local main_path = Managers.state and Managers.state.main_path

	if start_signal and not started and main_path and main_path:is_main_path_ready() then
		started = true

		start_cycle(true)
	end
end

local function host_update(dt)
	if not started then
		try_start()
	end

	if not started or not host_state then
		return
	end

	local state = host_state

	if #Positions.player_units() == 0 then
		return
	end

	state.remaining = state.remaining - dt

	if state.phase == "incoming" then
		if state.remaining <= 0 then
			start_cycle(false)
		end
	else
		if state.phase == "waiting" and state.mode == "vote" and #state.cands > 0 and state.remaining <= (state.vote_window or 25) then
			state.phase = "voting"
			mark_changed()
		end

		if state.remaining <= 0 then
			resolve()
		end
	end

	send_timer = send_timer + dt

	if changed or send_timer >= SEND_INTERVAL then
		changed = false
		send_timer = 0

		refresh_votes()
		broadcast()
	end
end

local live_mission

-- The game-mode manager may not exist yet when GameplayStateRun is entered, so
-- the "is this a real mission" answer is re-checked once a second until it is yes.
local function recheck_mission(dt)
	recheck_timer = recheck_timer + dt

	if recheck_timer < 1 then
		return
	end

	recheck_timer = 0

	if live_mission() then
		in_mission = true

		if not Director.is_host() then
			Protocol.send_hello()
		end
	end
end

Director.update = function (dt)
	clock = clock + dt

	if gameplay_active and not in_mission then
		recheck_mission(dt)
	end

	if not in_mission or client_disabled then
		return
	end

	if Director.is_host() then
		if Execute.has_authority() then
			host_update(dt)
			Execute.update(dt)
		end
	end
end

-- ------------------------------------------------------------------ lifecycle

Director.reset = function ()
	host_state, client_state = nil, nil
	started = false
	start_signal = false
	changed = true
	send_timer = 0
	last_fired = {}
	my_vote, my_vote_ballot = nil, nil
	Votes.close()
	Execute.reset()
end

local NOT_A_MISSION = { hub = true, prologue_hub = true }

live_mission = function ()
	local manager = Managers.state and Managers.state.game_mode
	local game_mode = manager and manager:game_mode()
	local name = game_mode and game_mode:name()

	return name ~= nil and not NOT_A_MISSION[name]
end

Director.on_enter_gameplay = function ()
	Director.reset()
	client_disabled = false
	gameplay_active = true
	in_mission = false
	recheck_timer = 1 -- check on the next update

	if live_mission() then
		in_mission = true

		if not Director.is_host() then
			Protocol.send_hello()
		end
	end
end

Director.on_exit_gameplay = function ()
	Director.reset()
	gameplay_active = false
	in_mission = false
end

-- First objective of the mission activated (same trigger RealmsEvent uses).
-- The cycle starts on the next host update once the main path is ready.
Director.on_mission_started = function ()
	start_signal = true
end

Director.force_start = function ()
	if not Director.is_host() then
		return false
	end

	in_mission = live_mission()
	started = in_mission
	start_signal = in_mission

	if started then
		start_cycle(true)
	end

	return started
end

Director.skip = function ()
	if host_state and host_state.phase ~= "incoming" then
		host_state.remaining = 0
	end
end

-- -------------------------------------------------------------- network events

Director.on_hello = function (sender, proto, version_text)
	if not Director.is_host() then
		return
	end

	local ok = proto == Protocol.PROTO and version_text == Protocol.VERSION

	Protocol.send_welcome(sender, ok)

	if ok and host_state then
		Protocol.send_state(snapshot(), sender)
	end
end

Director.on_welcome = function (sender, proto, version_text, ok)
	if Director.is_host() then
		return
	end

	client_disabled = not ok

	if not ok then
		mod:warning("RealmsWaves: version mismatch with host (host %s, proto %d, local %s, proto %d); disabled", tostring(version_text), proto, Protocol.VERSION, Protocol.PROTO)
	end
end

Director.on_state = function (sender, s)
	if Director.is_host() or client_disabled then
		return
	end

	local cands = {}

	if type(s.k) == "table" then
		for i = 1, #s.k do
			local item = s.k[i]

			cands[i] = { key = tostring(item.k), name = tostring(item.n), pct = tonumber(item.p) or 0, votes = tonumber(item.v) or 0 }
		end
	end

	client_state = {
		phase = tostring(s.p),
		mode = tostring(s.m),
		remaining = tonumber(s.r) or 0,
		ballot_id = tonumber(s.b) or 0,
		chosen = tostring(s.c or ""),
		cands = cands,
		empty = s.e == 1,
	}

	client_received_at = now()

	mark_changed()
end

Director.on_vote = function (sender, ballot_id, option)
	if not Director.is_host() or not host_state or host_state.phase == "incoming" then
		return
	end

	if Votes.cast(ballot_id, sender, option) then
		mark_changed()
	end
end

Director.on_peer_joined = function (peer_id)
	if Director.is_host() then
		if host_state then
			Protocol.send_state(snapshot(), peer_id)
		end
	elseif in_mission then
		Protocol.send_hello()
	end
end

Director.on_peer_left = function (peer_id)
	if Director.is_host() then
		Votes.remove_peer(peer_id)
		mark_changed()
	end
end

-- ------------------------------------------------------------- local player vote

Director.local_vote = function (option)
	local state = Director.view()

	if state.phase ~= "waiting" and state.phase ~= "voting" then
		return false, "no vote is open"
	end

	if state.mode ~= "vote" then
		return false, "voting is off (mode is random)"
	end

	local cand = state.cands[option]

	if not cand then
		return false, "no such option"
	end

	my_vote, my_vote_ballot = option, state.ballot_id

	if Director.is_host() then
		if Votes.cast(state.ballot_id, "host", option) then
			mark_changed()
		end
	else
		Protocol.send_vote(state.ballot_id, option)
	end

	mod:echo(mod:localize("vote_cast", option, cand.name))

	return true
end

-- --------------------------------------------------------------------- HUD view

-- Returns a shared table (no per-frame allocation). Valid for one frame.
Director.view = function ()
	local source, remaining

	if Director.is_host() then
		source = host_state

		if source then
			refresh_votes()
		end

		remaining = source and source.remaining or 0
	else
		source = client_state
		remaining = source and math.max(0, source.remaining - (now() - client_received_at)) or 0
	end

	if not source or client_disabled or not in_mission then
		view.phase = "off"
		view.cands = view.cands

		return view
	end

	view.phase = source.phase
	view.mode = source.mode
	view.remaining = remaining
	view.ballot_id = source.ballot_id
	view.chosen = source.chosen
	view.cands = source.cands
	view.empty = source.empty
	view.version = version
	view.my_vote = my_vote_ballot == source.ballot_id and my_vote or nil

	return view
end

-- ---------------------------------------------------------------- debug helpers

Director.fire_now = function (key)
	if not Director.is_host() then
		return false, "only the host can start waves"
	end

	-- `key` may be a key ("custom_1") or a wave name ("Mutants Everywhere", "mutants_everywhere")
	local wave, find_error = Events.find(key, get_setting, Groups)

	if not wave then
		return false, find_error
	end

	if not wave.parts or #wave.parts == 0 then
		return false, "that wave has no enemies yet (edit it in the wave editor or with /rw_custom)"
	end

	local def = Events.spawn_def(wave)

	def.test = true -- explicit test: allowed to use the ring fallback on levels without spawn points

	local ok, err = Execute.start_wave(def)

	if ok then
		return true, Execute.uses_ring() and "no spawn points on this level (Psykhanium?): spawning on a ring 10-30 m around you, NOT hidden" or nil
	end

	return ok, err
end

Director.simulate = function (rolls)
	local pool, total = Events.build_pool(get_setting, Groups)
	local counts = {}

	for i = 1, #pool do
		counts[pool[i].key] = 0
	end

	for _ = 1, rolls do
		local index = weighted_pick(pool)

		if index then
			counts[pool[index].key] = counts[pool[index].key] + 1
		end
	end

	return pool, counts, total
end

Director.status = function ()
	local state = Director.view()
	local exec = Execute.status()

	return string.format(
		"phase=%s mode=%s remaining=%.0fs cands=%d host=%s started=%s in_mission=%s disabled=%s | tracked=%d queued=%d jobs=%d stage=%s err=%s | lua heap %.0f MB (guard %d, paused %s)",
		state.phase, tostring(state.mode), state.remaining or 0, #(state.cands or {}), tostring(Director.is_host()), tostring(started), tostring(in_mission), tostring(client_disabled),
		exec.tracked, exec.queued, exec.jobs, tostring(exec.stage), tostring(exec.last_error),
		exec.heap_mb or 0, exec.heap_guard_mb or 0, tostring(exec.heap_paused)
	)
end

return Director
