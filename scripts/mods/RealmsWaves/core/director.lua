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

local Events, Groups, Protocol, Execute, Votes, Positions, Presets

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
local peer_waves = {} -- host: peer id -> that player's enabled waves (pool-ready), see Director.on_waves
local timers = {} -- host: wave key -> { every, remaining, wave } for waves with a fixed timer
local paused = false -- /rw_pause: every clock is frozen
local stopped = false -- /rw_stop: the director does nothing until /rw_start
local timer_check = 0

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
	Presets = deps.presets
end

-- ------------------------------------------------------- everyone's waves (host + clients)

-- Waves of the other players, when the host switched "use everyone's waves" on (nil = host's own only).
Director.extra_waves = function ()
	if mod:get("pool_all_players") ~= true then
		return nil
	end

	local extra = {}

	for _, waves in pairs(peer_waves) do
		for i = 1, #waves do
			extra[#extra + 1] = waves[i]
		end
	end

	table.sort(extra, function (a, b)
		return a.key < b.key
	end)

	return extra
end

-- Host: a client told us its enabled waves (one preset text). Invalid text is ignored as a whole.
Director.on_waves = function (sender, text)
	if not Director.is_host() or not Presets then
		return
	end

	local preset = Presets.decode(text, Events, Groups)

	if preset then
		peer_waves[sender] = Presets.pool_waves(preset, sender, Events, Groups)
	end
end

-- Client: tell the host which waves are enabled here. Sent after the handshake and whenever the editor closes.
Director.send_waves = function ()
	if Director.is_host() or client_disabled or not in_mission or not Presets or not Protocol.is_available() then
		return false
	end

	local text = Presets.encode(Presets.enabled_waves(get_setting, Events, Groups))

	return Protocol.send_waves(text) == true
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
	local pool = Events.build_pool(get_setting, Groups, Director.extra_waves())

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

	return { p = state.phase, m = state.mode, r = round1(state.remaining), b = state.ballot_id, c = state.chosen, k = k, e = state.empty and 1 or 0, z = paused and 1 or 0 }
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

-- --------------------------------------------------------------- fixed-timer waves

-- A wave with a fixed timer ("ev_<key>" seconds, set in the wave editor) ignores its chance and cooldown and
-- never takes part in the draw or the vote: it spawns every N seconds on its own clock, whatever the other
-- waves do. The clocks start with the mission's first cycle and only run while a player is alive.
local function fire_timed(wave)
	local ok, err = Execute.start_wave(wave.def)

	if not ok then
		mod:warning("RealmsWaves: timed wave %s not started: %s", tostring(wave.key), tostring(err))
	end
end

local function update_timed_waves(dt)
	-- the waves are re-read once a second: they can be enabled, edited or given another timer while playing
	timer_check = timer_check - dt

	if timer_check <= 0 then
		timer_check = 1

		local live = {}
		local list = Events.timed_waves(get_setting, Groups)

		for i = 1, #list do
			local wave = list[i]
			local timer = timers[wave.key]

			live[wave.key] = true

			if not timer then
				timers[wave.key] = { every = wave.every, remaining = wave.every, wave = wave }
			else
				-- a changed period never leaves the clock waiting longer than the new period (only when it CHANGED:
				-- a delay pushed on by anti-snowballing may legitimately exceed the period)
				if timer.every ~= wave.every then
					timer.remaining = math.min(timer.remaining, wave.every)
				end

				timer.every = wave.every
				timer.wave = wave
			end
		end

		for key in pairs(timers) do
			if not live[key] then
				timers[key] = nil
			end
		end
	end

	for _, timer in pairs(timers) do
		timer.remaining = timer.remaining - dt

		if timer.remaining <= 0 then
			timer.remaining = timer.every

			fire_timed(timer.wave)
		end
	end
end

local function host_update(dt)
	if stopped then
		return
	end

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

	-- paused: every clock stands still (the countdown, the vote window, the fixed timers); the state is
	-- still re-sent once a second so late joiners and the HUD keep the frozen time
	if not paused then
		update_timed_waves(dt)

		state.remaining = state.remaining - dt
	end

	if paused then
		-- nothing to resolve
	elseif state.phase == "incoming" then
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
	paused, stopped = false, false
	peer_waves = {}
	timers, timer_check = {}, 0
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
	stopped, paused = false, false

	if started then
		start_cycle(true)
	end

	return started
end

Director.skip = function ()
	if host_state and host_state.phase ~= "incoming" and not stopped then
		host_state.remaining = 0
		paused = false
	end
end

-- ------------------------------------------------------- /rw_stop, /rw_pause, /rw_next, anti-snowballing

-- Host. Stops the mod: no countdown, no vote, no fixed timers, queued wave units are dropped (units that are
-- already on the map stay). Clients see the panel disappear. /rw_start (or Director.force_start) starts again.
Director.stop = function ()
	if not Director.is_host() then
		return false, "only the host can stop the waves"
	end

	stopped, paused = true, false
	timers, timer_check = {}, 0
	Execute.reset()
	Votes.close()

	if host_state then
		host_state.phase, host_state.cands, host_state.empty = "off", {}, false
		mark_changed()

		if Protocol.is_available() then
			Protocol.send_state(snapshot(), "others")
		end
	end

	host_state = nil

	return true
end

Director.is_stopped = function ()
	return stopped
end

Director.is_paused = function ()
	return paused
end

-- Host. Freezes (or with `on` false / a second call releases) every clock: the countdown to the next wave,
-- the vote window and the fixed timers. Returns the new state.
Director.pause = function (on)
	if not Director.is_host() then
		return nil, "only the host can pause the waves"
	end

	if stopped then
		return nil, "the waves are stopped (use /rw_start first)"
	end

	if on == nil then
		on = not paused
	end

	paused = on == true
	mark_changed()

	return paused
end

-- Host. Throws the current wave (and its vote) away WITHOUT spawning it and starts a fresh cycle: a new draw,
-- a new ballot and a full new timer. Also leaves the pause.
Director.next_wave = function ()
	if not Director.is_host() then
		return false, "only the host can change the wave"
	end

	if stopped then
		return false, "the waves are stopped (use /rw_start first)"
	end

	if not started then
		return false, "no cycle is running yet (mission not started)"
	end

	paused = false
	start_cycle(false)

	return true
end

-- Anti-snowballing (host, options "anti_snowball" + "anti_snowball_delay"): whenever a player dies the
-- running wave timers are pushed back by the configured number of seconds, so a team that just lost someone
-- gets a breather instead of the next wave. Delays the countdown to the next wave and every fixed timer.
Director.on_player_died = function ()
	if not Director.is_host() or stopped or mod:get("anti_snowball") ~= true or not host_state then
		return false
	end

	local delay = math.max(0, number_setting("anti_snowball_delay", 30))

	if delay <= 0 then
		return false
	end

	if host_state.phase ~= "incoming" then
		host_state.remaining = host_state.remaining + delay
	end

	for _, timer in pairs(timers) do
		timer.remaining = timer.remaining + delay
	end

	mark_changed()
	mod:echo("%s", mod:localize("msg_anti_snowball", math.floor(delay)))

	return true
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

	if ok then
		Director.send_waves()
	end

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
		paused = s.z == 1,
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
		peer_waves[peer_id] = nil
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
		-- a paused host keeps sending the frozen time: do not count down locally
		remaining = source and (source.paused and source.remaining or math.max(0, source.remaining - (now() - client_received_at))) or 0
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
	view.paused = Director.is_host() and paused or source.paused == true
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

-- (number of waves, number of players) received from clients, for /rw_status
-- number of waves currently running on a fixed timer, for /rw_status
Director.timed_wave_count = function ()
	local count = 0

	for _ in pairs(timers) do
		count = count + 1
	end

	return count
end

Director.peer_wave_count = function ()
	local waves, players = 0, 0

	for _, list in pairs(peer_waves) do
		waves = waves + #list
		players = players + 1
	end

	return waves, players
end

Director.status = function ()
	local state = Director.view()
	local exec = Execute.status()

	return string.format(
		"phase=%s mode=%s remaining=%.0fs paused=%s stopped=%s cands=%d host=%s started=%s in_mission=%s disabled=%s | tracked=%d queued=%d jobs=%d stage=%s err=%s | lua heap %.0f MB (guard %d, paused %s) | timed waves: %d | everyone's waves: %s, %d from %d players",
		state.phase, tostring(state.mode), state.remaining or 0, tostring(paused), tostring(stopped), #(state.cands or {}), tostring(Director.is_host()), tostring(started), tostring(in_mission), tostring(client_disabled),
		exec.tracked, exec.queued, exec.jobs, tostring(exec.stage), tostring(exec.last_error),
		exec.heap_mb or 0, exec.heap_guard_mb or 0, tostring(exec.heap_paused),
		Director.timed_wave_count(), mod:get("pool_all_players") == true and "on" or "off", Director.peer_wave_count()
	)
end

return Director
