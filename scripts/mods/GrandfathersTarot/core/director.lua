-- Wave director: timer, event selection, vote handling, state sync.
--
-- Host is authoritative. Modes (option "mode"):
--   tarot (default, 2.0.0): "The Grandfather's Tarot". Every cycle the host waits an interval, deals a HAND of X cards
--     (weighted by chance weight, no repeats, only cards that are in the draw and off cooldown), shows it for Y seconds
--     and then picks ONE of the hand with equal chance. The winner is chosen when the hand is dealt and synced with
--     it; clients only animate the roulette and land on the host's card. The picked card stays out of every draw for
--     its full cooldown. One card in the hand = no roulette.
--   random: one pending wave drawn by weight at the start of the countdown.
--   vote: a ballot of N candidates, votes accepted during the whole countdown, the last `vote_duration` seconds are
--     the highlighted "voting" phase.
-- At zero the wave spawns (legacy modes show an "incoming" banner state; tarot keeps the resolved hand in the state
-- for a while so every screen can play the reveal).
--
-- Phases: off | waiting | voting | incoming (legacy) | hand (tarot)
-- Clients only render the last state received from the host and cast votes.
local mod = get_mod("GrandfathersTarot")

local Director = {}

local Events, Groups, Protocol, Execute, Votes, Positions, Presets, Cards, Tuning

local INCOMING_SECONDS = 6
local EMPTY_POOL_RETRY = 20
local SEND_INTERVAL = 1
local TAROT_RETRY = 10 -- seconds until the next try when no card can be dealt
local DRAWN_KEEP = 16 -- seconds a resolved hand stays in the synced state (the reveal and the rot play from it)
local HAND_MAX = 5

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
local last_fired = {} -- wave key -> cd_clock when it was drawn
-- The last fulfilled card: the card whose wave the cycle sent out last (a drawn card, a random wave, a voted wave: not /gt_test and not
-- a fixed timer, and only when the wave really started). { card = { key, name, suit, threat, breeds, whisper, modifiers, rare, cooldown },
-- at = cd_clock when it went out, seq = how many cards have gone out }; the HUD window of the last card shows it.
local last_card = nil
local last_card_seq = 0
local cd_clock = 0 -- seconds of PLAYED time (frozen by /gt_pause, stopped without a living player): cooldowns run on it
local my_vote, my_vote_ballot = nil, nil
local peer_waves = {} -- host: peer id -> that player's enabled waves (pool-ready), see Director.on_waves
local timers = {} -- host: wave key -> { every, remaining, wave } for waves with a fixed timer
local paused = false -- /gt_pause: every clock is frozen
local stopped = false -- /gt_stop: the director does nothing until /gt_start
local timer_check = 0

local view = { phase = "off", mode = "tarot", remaining = 0, ballot_id = 0, chosen = "", cands = {}, version = 0, my_vote = nil, hand = nil, win = 0, hand_seq = 0, drawn = false, drawn_age = 0, hand_seconds = 0 }

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
	Cards = deps.cards
	Director.effects = deps.effects
	Tuning = deps.tuning
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

local warned_waves_size = false

-- Client: tell the host which waves are enabled here. Sent after the handshake and whenever the editor closes.
Director.send_waves = function ()
	if Director.is_host() or client_disabled or not in_mission or not Presets or not Protocol.is_available() then
		return false
	end

	local preset = Presets.enabled_waves(get_setting, Events, Groups)
	local text = Presets.encode(preset)
	local limit = Protocol.MAX_WAVES_TEXT or 90000

	local function fits(value)
		return #value <= limit and (not Protocol.waves_text_fits or Protocol.waves_text_fits(value))
	end

	-- Find the largest prefix that fits after JSON escaping. Zero cards clears a previously shared pool.
	if not fits(text) then
		local all, total = preset.waves, #preset.waves
		local count, low, high = 0, 0, total - 1
		local function prefix(n)
			preset.waves = {}

			for i = 1, n do
				preset.waves[i] = all[i]
			end

			return Presets.encode(preset)
		end

		text = prefix(0)

		while low <= high do
			local middle = math.floor((low + high) / 2)
			local candidate = prefix(middle)

			if fits(candidate) then
				count, text, low = middle, candidate, middle + 1
			else
				high = middle - 1
			end
		end

		if not warned_waves_size then
			warned_waves_size = true
			mod:warning("GrandfathersTarot: only %d of your %d enabled cards fit in one message to the host (limit %d bytes): the others are not part of the pooled draw", count, total, limit)
		end
	end

	return Protocol.send_waves(text) == true
end

local function mark_changed()
	changed = true
	version = version + 1
end

-- ------------------------------------------------------------------------ cooldowns of the cards
-- Seconds left of a card's cooldown: on the host from its own clocks, on a client from the last state (counted
-- down locally, frozen while the host is paused).

local cool_map, cool_map_at = {}, -math.huge
local client_cooldowns = {}

-- { [key] = seconds left } for the cards in the draw that are cooling down, whole seconds, refreshed at most once a
-- second (it is sent with every state).
Director.cooldown_map = function ()
	if cd_clock - cool_map_at < 1 and cool_map_at <= cd_clock then
		return cool_map
	end

	cool_map, cool_map_at = {}, cd_clock

	-- (2026-10-06, a performance pass) only the cards that went out, each read on its own with the draw's rules (enabled, a
	-- chance, something in it, no fixed timer): building the whole draw parsed every card's recipe once a second
	local extra_by_key = nil

	for key, since in pairs(last_fired) do
		local wave = nil

		if type(key) == "string" and key:find(":", 1, true) then
			if not extra_by_key then
				extra_by_key = {}

				for _, extra in ipairs(Director.extra_waves() or {}) do
					extra_by_key[extra.key] = extra
				end
			end

			wave = extra_by_key[key]
		elseif not Events.is_empty_slot(key, get_setting) then
			wave = Events.get(key, get_setting, Groups)
		end

		if wave and wave.enabled and Events.has_content(wave) and (wave.pct or 0) > 0 and not ((wave.timer or 0) > 0) then
			local left = since + (wave.cooldown or 0) - cd_clock

			if left > 0 then
				cool_map[key] = math.ceil(left)
			end
		end
	end

	return cool_map
end

-- Seconds until `key` can be dealt again (0 = ready). `length` (the card's cooldown) is needed on the host.
Director.cooldown_remaining = function (key, length)
	if Director.is_host() then
		local since = last_fired[key]

		if not since then
			return 0
		end

		return math.max(0, since + (tonumber(length) or 0) - cd_clock)
	end

	local entry = client_cooldowns[key]

	if not entry then
		return 0
	end

	local elapsed = (client_state and client_state.paused) and 0 or (now() - client_received_at)

	return math.max(0, entry - elapsed)
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

		if since == nil or cd_clock - since >= entry.cooldown then
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
	local low = math.max(5, number_setting("interval_min", 75))
	local high = math.max(low, number_setting("interval_max", 75))
	-- random: anywhere between the minimum and the maximum; otherwise always the minimum (a fixed time)
	local interval = mod:get("interval_random") ~= true and low or low + math.random() * (high - low)

	if first then
		interval = interval + number_setting("initial_delay", 0)
	end

	return interval
end

-- ------------------------------------------------------------------ the draw (tarot mode)

local start_tarot_cycle

-- Cards that can be dealt now: in the draw (enabled, with enemies, weight above 0, not timed or deleted) and off
-- cooldown. A card that was drawn stays out of EVERY draw for its full cooldown (no fallback to cooling cards).
-- Returns the ready entries, the size of the whole pool and the number of cards that are cooling down.
-- Suits that may be played ONCE per game (2026-10-04: Nightmare, `once` in catalog/cards.lua): when one card of such a suit goes out,
-- every card of that suit leaves the draw (and the vote, and the fixed timers) until the next mission. Director.reset clears it.
local spent_once = {}

local function once_suit(def)
	local suit = Cards.normalize_suit(def and def.suit)

	return Cards.suit(suit).once == true and suit or nil
end

local function spent(def)
	local suit = once_suit(def)

	return suit ~= nil and spent_once[suit] == true
end

Director.spent_once = function (suit) return spent_once[suit] == true end

-- The pool of the draw without the cards of a suit that was already played this game
local function drawable_pool()
	local pool, kept = Events.build_pool(get_setting, Groups, Director.extra_waves()), {}

	for i = 1, #pool do
		if not spent(pool[i].def) then
			kept[#kept + 1] = pool[i]
		end
	end

	return kept
end

local function eligible_cards()
	local pool = drawable_pool()
	local ready, cooling = {}, 0

	for i = 1, #pool do
		local entry = pool[i]
		local since = last_fired[entry.key]

		if since == nil or cd_clock - since >= entry.cooldown then
			ready[#ready + 1] = entry
		else
			cooling = cooling + 1
		end
	end

	return ready, #pool, cooling
end

-- A pool entry as a card (Cards.describe: suit, threat, whisper, look, ...), plus the host-only spawn entry.
local function card_of(entry)
	local def = entry.def
	local card = Cards.describe({
		key = entry.key, name = entry.name, parts = def.parts, suit = def.suit, threat_override = def.threat_override,
		whisper = def.whisper, look = def.look, effects = def.effects, sound = def.sound, pct = entry.raw, cooldown = entry.cooldown, enabled = true,
	}, Groups, nil)

	card.entry = entry

	return card
end

-- Deals the hand: up to `tarot_cards` cards by chance weight without repeats, then the winner by a uniform roll.
-- The winner is decided HERE and travels with the hand; nobody else rolls. Returns false when no card can be dealt.
local function deal(state)
	local ready, pool_size, cooling = eligible_cards()
	local count = math.max(1, math.min(HAND_MAX, math.floor(number_setting("tarot_cards", 4))))
	local picks = {}

	while #picks < count and #ready > 0 do
		local index = weighted_pick(ready)

		if not index then
			break
		end

		picks[#picks + 1] = table.remove(ready, index)
	end

	if #picks == 0 then
		state.cooling = pool_size > 0 and cooling > 0

		return false
	end

	local cards = {}

	for i = 1, #picks do
		cards[i] = card_of(picks[i])
	end

	ballot_seq = ballot_seq + 1
	state.hand = { cards = cards, win = math.random(1, #cards), seq = ballot_seq }
	state.hand_seconds = math.max(0, state.remaining)
	state.drawn = false
	state.drawn_age = 0
	state.empty = false
	state.phase = "hand"
	mark_changed()

	return true
end

-- Writes down the card of the wave that just went out as the last fulfilled card (see last_card above).
local function remember_card(card)
	last_card_seq = last_card_seq + 1
	last_card = {
		card = { key = card.key, name = card.name, suit = card.suit, threat = card.threat, breeds = card.breeds, whisper = card.whisper, modifiers = card.modifiers, rare = card.rare == true, cooldown = card.cooldown },
		at = cd_clock,
		seq = last_card_seq,
	}

	mark_changed()
end

-- A wave goes out. With a sound (2026-10-04) the sound plays first, for everyone, the moment the card is picked, and the wave spawns
-- when the host's sound has ended (never later than ALERT_LONGEST seconds); without one it spawns at once. Returns what
-- Execute.start_wave returns (a held wave counts as started; a failure when it is released is warned).
local ALERT_LONGEST = 20
local held = {}

local function launch(def, key, test)
	local once = not test and once_suit(def)

	if once then
		spent_once[once] = true
	end

	local job = Director.effects and Director.effects.alert and Director.effects.alert(def.sound)

	-- the journal holds the alert now: send the state, so the other players hear it at once
	if def.sound and def.sound ~= "" then
		mark_changed()
	end

	if job and not job.done then
		held[#held + 1] = { def = def, key = key, job = job, age = 0, test = test == true }

		return true
	end

	return Execute.start_wave(def)
end

-- `halted` (paused or stopped): only the waves of a test command (/gt_test, /gt_fulltest) go on
local function release_held(dt, halted)
	for i = #held, 1, -1 do
		local wave = held[i]

		if halted and not wave.test then
			-- held until the cycle runs again
		elseif wave.job.done or (wave.age + dt) >= ALERT_LONGEST then
			wave.age = wave.age + dt
			table.remove(held, i)

			local ok, err = Execute.start_wave(wave.def)

			if not ok then
				mod:warning("GrandfathersTarot: card %s not started after its sound: %s", tostring(wave.key), tostring(err))
			end
		else
			wave.age = wave.age + dt
		end
	end
end

Director.held_count = function () return #held end

-- The wave of the picked card goes out; its cooldown starts now.
local function pick_card(state)
	local card = state.hand.cards[state.hand.win]

	-- a staged draw (/gt_drawtest, /gt_fulltest): no cooldown, no once-per-game; the draw test sends nothing at all
	if state.staged then
		local ok, err = true, nil

		if state.staged.full then
			ok, err = launch(card.entry.def, card.key, true)
		end

		if ok then
			remember_card(card)
		else
			mod:warning("GrandfathersTarot: staged card %s not started: %s", tostring(card.key), tostring(err))
		end

		return card
	end

	local ok, err = launch(card.entry.def, card.key)

	if not ok then
		mod:warning("GrandfathersTarot: card %s not started: %s", tostring(card.key), tostring(err))
	else
		remember_card(card)
	end

	last_fired[card.key] = cd_clock

	return card
end

-- Time to the next pick. `keep_hand`: the hand that was just resolved stays in the state for the reveal.
start_tarot_cycle = function (first, keep_hand, interval)
	interval = interval or random_interval(first)

	local seconds = math.max(5, math.min(30, number_setting("tarot_seconds", 10)))

	host_state = {
		phase = "waiting",
		mode = "tarot",
		remaining = interval,
		-- the hand is dealt this many seconds before the pick (never more than the whole interval)
		hand_window = math.min(seconds, interval),
		hand_seconds = 0,
		ballot_id = ballot_seq,
		chosen = keep_hand and keep_hand.cards[keep_hand.win].name or "",
		cands = {},
		hand = keep_hand,
		drawn = keep_hand ~= nil,
		drawn_age = 0,
	}

	Votes.close()
	mark_changed()
end

local function resolve_tarot()
	local state = host_state

	if state.empty then
		start_tarot_cycle(false, nil, TAROT_RETRY)

		return
	end

	-- a pick without a hand (/gt_skip while waiting) deals one first
	if not state.hand or state.drawn then
		if not deal(state) then
			start_tarot_cycle(false, nil, TAROT_RETRY)
			host_state.empty = true
			host_state.cooling = state.cooling

			return
		end
	end

	pick_card(state)

	-- after a staged draw the cycle goes on where it was (the countdown it had; another mode gets its own state back)
	local staged = state.staged

	if staged then
		local saved = staged.saved

		if saved.mode == "tarot" then
			start_tarot_cycle(false, state.hand, math.max(5, saved.remaining or 5))
		else
			host_state = saved
			mark_changed()
		end

		return
	end

	start_tarot_cycle(false, state.hand)
end

local function tarot_tick(state, dt)
	if state.drawn then
		state.drawn_age = state.drawn_age + dt

		if state.drawn_age >= DRAWN_KEEP then
			state.hand, state.drawn = nil, false
			mark_changed()
		end
	end

	if not state.empty and state.phase == "waiting" and state.remaining <= state.hand_window and not deal(state) then
		-- nothing to deal (no card in the draw, or every card is cooling down): look again soon
		state.empty = true
		state.remaining = TAROT_RETRY
		mark_changed()
	end

	if state.remaining <= 0 then
		resolve_tarot()
	end
end

local function start_cycle(first)
	local setting = mod:get("mode")
	local mode = setting == "vote" and "vote" or setting == "random" and "random" or "tarot"

	if mode == "tarot" then
		start_tarot_cycle(first, nil)

		return
	end

	local pool = drawable_pool()

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
		vote_window = math.min(number_setting("vote_duration", 5), interval),
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
	local ok, err = launch(cand.def, cand.key)

	if not ok then
		mod:warning("GrandfathersTarot: card %s not started: %s", tostring(cand.key), tostring(err))
	else
		local described, card = pcall(card_of, cand)

		if described then
			remember_card(card)
		end
	end

	last_fired[cand.key] = cd_clock
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

	local snap = { fx = Director.effects and Director.effects.snapshot() or nil, p = state.phase, m = state.mode, r = round1(state.remaining), b = state.ballot_id, c = state.chosen, k = k, e = state.empty and 1 or 0, z = paused and 1 or 0 }

	-- the real maximum health of the units whose health is more than the network carries (spawn/tuning.lua, the boss bars)
	if Tuning and Tuning.health_layer_list then
		local ok, list = pcall(Tuning.health_layer_list)

		snap.hl = ok and list or nil
	end

	-- the units with the Boss bar custom mod (spawn/tuning.lua): every machine shows their bars
	if Tuning and Tuning.boss_list then
		local ok, list = pcall(Tuning.boss_list)

		snap.bb = ok and list or nil
	end

	-- the last fulfilled card (any mode): the card, how long ago it went out in played seconds, and which card it was (a number that changes)
	if last_card then
		local c = last_card.card

		snap.lc = { k = c.key, n = c.name, s = c.suit, t = c.threat, b = c.breeds, q = c.whisper, m = c.modifiers, r = c.rare and 1 or 0, c = c.cooldown }
		snap.la = round1(cd_clock - last_card.at)
		snap.ls = last_card.seq
	end

	if state.mode == "tarot" then
		-- the hand (cards, the winner, a number that identifies this hand), whether it is already resolved, the
		-- hand's length in seconds and the cards that are cooling down (seconds left, by key)
		if state.hand then
			local cards = {}

			for i = 1, #state.hand.cards do
				local card = state.hand.cards[i]

				cards[i] = { k = card.key, n = card.name, s = card.suit, t = card.threat, b = card.breeds, q = card.whisper, m = card.modifiers, r = card.rare and 1 or 0, c = card.cooldown }
			end

			snap.h, snap.w, snap.sq = cards, state.hand.win, state.hand.seq
		end

		snap.dn = state.drawn and 1 or 0
			-- seconds since the pick, so a client (or a late joiner) can place the reveal and the rot on the timeline
			snap.da = state.drawn and round1(state.drawn_age or 0) or nil
		snap.y = round1(state.hand_seconds or 0)
		snap.cd = Director.cooldown_map()
		snap.e = state.empty and (state.cooling and 2 or 1) or 0
	end

	return snap
end

-- (2026-10-06, the user: a client saw no reveal outlines and no custom boss bars after waves were started by hand, and saw them
-- after /gt_start) The state goes out only while the card cycle runs. Without it the host still sends what the units and the
-- effects need, once a second: `o = 1`, the effects (reveals, the Blackout), the health layers and the boss bars.
local side_timer = 0

local function side_snapshot()
	local snap = { o = 1, fx = Director.effects and Director.effects.snapshot() or nil }

	if Tuning and Tuning.health_layer_list then
		local ok, list = pcall(Tuning.health_layer_list)

		snap.hl = ok and list or nil
	end

	if Tuning and Tuning.boss_list then
		local ok, list = pcall(Tuning.boss_list)

		snap.bb = ok and list or nil
	end

	return snap
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
local timed_warning_at = -math.huge

local function fire_timed(wave)
	if spent(wave.def) then
		return
	end

	local ok, err = launch(wave.def, wave.key)

	if not ok and clock - timed_warning_at >= 5 then
		timed_warning_at = clock
		mod:warning("GrandfathersTarot: timed card %s not started: %s", tostring(wave.key), tostring(err))
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

		cd_clock = cd_clock + dt
		state.remaining = state.remaining - dt
	end

	if paused then
		-- nothing to resolve
	elseif state.mode == "tarot" then
		tarot_tick(state, dt)
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

			release_held(dt, paused or stopped)

			Execute.update(dt, paused or stopped)

			if stopped or not started or not host_state then
				side_timer = side_timer + dt

				if side_timer >= SEND_INTERVAL and Protocol.is_available() then
					side_timer = 0
					Protocol.send_state(side_snapshot(), "others")
				end
			end
		end
	elseif Tuning then
		-- a client: the sizes the host sent (custom mods) go onto the units as they arrive here
		Tuning.update_client(dt)
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
	last_card, last_card_seq = nil, 0
	cd_clock = 0
	cool_map, cool_map_at = {}, -math.huge
	client_cooldowns = {}
	my_vote, my_vote_ballot = nil, nil
	held = {}
	spent_once = {}
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

-- ------------------------------------------------------- /gt_stop, /gt_pause, /gt_next, anti-snowballing

-- Host. Stops the mod: no countdown, no vote, no fixed timers, queued wave units are dropped (units that are
-- already on the map stay). Clients see the panel disappear. /gt_start (or Director.force_start) starts again.
Director.stop = function ()
	if not Director.is_host() then
		return false, "only the host can stop the draws"
	end

	stopped, paused = true, false
	last_card = nil
	timers, timer_check = {}, 0
	held = {}
	Execute.cancel()
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
		return nil, "only the host can pause the draws"
	end

	if stopped then
		return nil, "the draws are stopped (use /gt_start first)"
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
		return false, "only the host can change the card"
	end

	if stopped then
		return false, "the draws are stopped (use /gt_start first)"
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

	local delay = math.max(0, number_setting("anti_snowball_delay", 25))

	if delay <= 0 then
		return false
	end

	if host_state.phase ~= "incoming" then
		host_state.remaining = host_state.remaining + delay

		-- a hand already on the table stays: its fuse simply gets longer
		if host_state.mode == "tarot" and host_state.phase == "hand" then
			host_state.hand_seconds = math.max(host_state.hand_seconds or 0, host_state.remaining)
		end
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

	-- the sizes (custom mods) of the units that are already out there
	if ok and Tuning then
		pcall(Tuning.send_all, sender)
	end
	if ok and mod.rw and mod.rw.appearance then pcall(mod.rw.appearance.send_all, sender) end
end

-- Client: sizes of units the host spawned (custom mods), see spawn/tuning.lua.
Director.on_scale = function (sender, entries)
	if Director.is_host() or client_disabled or not Tuning then
		return
	end

	Tuning.receive(entries)
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
		mod:warning("GrandfathersTarot: version mismatch with host (host %s, proto %d, local %s, proto %d); disabled", tostring(version_text), proto, Protocol.VERSION, Protocol.PROTO)
	end
end

-- A card of a synced state (a hand card, the last fulfilled card) with every field validated; nil when it is not a table.
local function decode_card(item)
	if type(item) ~= "table" then
		return nil
	end

	local breeds = {}

	if type(item.b) == "table" then
		for j = 1, math.min(#item.b, 8) do
			if type(item.b[j]) == "string" then
				breeds[#breeds + 1] = item.b[j]:sub(1, 48)
			end
		end
	end

	return {
		key = tostring(item.k):sub(1, 64),
		name = tostring(item.n):sub(1, 60),
		suit = Events.normalize_suit(item.s),
		threat = math.max(1, math.min(6, math.floor(tonumber(item.t) or 1))),
		breeds = breeds,
		whisper = tostring(item.q or ""):sub(1, 60),
		modifiers = tostring(item.m or ""):sub(1, 100),
		rare = item.r == 1,
		cooldown = math.max(0, math.min(86400, tonumber(item.c) or 0)),
	}
end

Director.on_state = function (sender, s)
	if type(s) ~= "table" or Director.is_host() or client_disabled then
		return
	end

	if Director.effects then Director.effects.receive(s.fx) end
	if Tuning and Tuning.receive_health_layers then pcall(Tuning.receive_health_layers, s.hl) end
	if Tuning and Tuning.receive_bosses then pcall(Tuning.receive_bosses, s.bb) end

	-- the host runs no card cycle: only the units and the effects (side_snapshot)
	if s.o == 1 then
		return
	end
	local cands = {}

	if type(s.k) == "table" then
		for i = 1, math.min(#s.k, HAND_MAX) do
			local item = s.k[i]

			if type(item) == "table" then
				cands[#cands + 1] = { key = tostring(item.k), name = tostring(item.n), pct = tonumber(item.p) or 0, votes = tonumber(item.v) or 0 }
			end
		end
	end

	-- the tarot hand: every field is validated (sizes, suit, threat), the winner index is kept inside the hand
	local hand

	if type(s.h) == "table" and #s.h > 0 then
		local cards = {}

		for i = 1, math.min(#s.h, HAND_MAX) do
			local card = decode_card(s.h[i])

			if card then
				cards[#cards + 1] = card
			end
		end

		if #cards > 0 then
			hand = { cards = cards, win = math.max(1, math.min(#cards, math.floor(tonumber(s.w) or 1))), seq = tonumber(s.sq) or 0 }
		end
	end

	-- the last fulfilled card: the same card as in the previous message keeps its table (the HUD window compares it), a new one is decoded
	local last

	if s.p ~= "off" and type(s.lc) == "table" then
		local seq = tonumber(s.ls) or 0
		local previous = client_state and client_state.last

		if previous and previous.seq == seq then
			last = previous
		else
			local card = decode_card(s.lc)

			last = card and { card = card, seq = seq } or nil
		end

		if last then
			last.age = math.max(0, math.min(86400, tonumber(s.la) or 0))
		end
	end

	client_state = {
		last = last,
		phase = tostring(s.p),
		mode = tostring(s.m),
		remaining = tonumber(s.r) or 0,
		ballot_id = tonumber(s.b) or 0,
		chosen = tostring(s.c or ""),
		cands = cands,
		empty = (tonumber(s.e) or 0) > 0,
		cooling = s.e == 2,
		paused = s.z == 1,
		hand = hand,
		drawn = s.dn == 1,
		drawn_age = math.max(0, math.min(DRAWN_KEEP * 2, tonumber(s.da) or 0)),
		hand_seconds = tonumber(s.y) or 0,
	}

	client_cooldowns = {}

	if type(s.cd) == "table" then
		for key, left in pairs(s.cd) do
			if type(key) == "string" and tonumber(left) then
				client_cooldowns[key:sub(1, 64)] = tonumber(left)
			end
		end
	end

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
		return false, "voting is off (the draw mode is not Votes)"
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
		view.last, view.last_seq, view.last_age = nil, 0, 0

		return view
	end

	view.phase = source.phase
	view.mode = source.mode
	view.remaining = remaining
	view.ballot_id = source.ballot_id
	view.chosen = source.chosen
	view.cands = source.cands
	view.empty = source.empty
	view.cooling = source.cooling == true
	view.hand = source.hand and source.hand.cards or nil
	view.win = source.hand and source.hand.win or 0
	view.hand_seq = source.hand and source.hand.seq or 0
	view.drawn = source.drawn == true
	-- seconds since the pick: the host's own clock, or the synced age plus the time since it arrived (frozen while paused)
	view.drawn_age = Director.is_host() and (source.drawn_age or 0) or (source.paused and (source.drawn_age or 0) or (source.drawn_age or 0) + (now() - client_received_at))
	view.hand_seconds = source.hand_seconds or 0

	-- the last fulfilled card (nil before the first): its table stays the same until another card goes out (last_seq changes with it);
	-- the age is in played seconds: the host's own clock, a client's synced age plus the time since it arrived (frozen while paused)
	local last = Director.is_host() and last_card or source.last

	view.last = last and last.card or nil
	view.last_seq = last and last.seq or 0
	view.last_age = last and (Director.is_host() and (cd_clock - last.at) or (source.paused and last.age or last.age + (now() - client_received_at))) or 0

	view.paused = Director.is_host() and paused or source.paused == true
	view.version = version
	view.my_vote = my_vote_ballot == source.ballot_id and my_vote or nil

	return view
end

-- ---------------------------------------------------------------- debug helpers

-- `options.close`: the wave appears right in front of the local player (/gt_test_close) instead of hidden near the squad
Director.fire_now = function (key, options)
	if not Director.is_host() then
		return false, "only the host can draw cards"
	end

	-- `key` may be a key ("custom_1") or a wave name ("Mutants Everywhere", "mutants_everywhere")
	local wave, find_error = Events.find(key, get_setting, Groups)

	if not wave then
		return false, find_error
	end

	if not Events.has_content(wave) then
		return false, "that card has no enemies yet (edit it in the Deck or with /gt_custom)"
	end

	local def = Events.spawn_def(wave)

	def.test = true -- explicit test: allowed to use the ring fallback on levels without spawn points
	def.close = options and options.close == true or nil

	-- (2026-10-04) its sound first, then the wave, as in a draw; a test never spends a once-per-game suit
	local ok, err = launch(def, wave.key, true)

	if ok then
		if def.close then
			return true, "spawning right in front of you" .. (Director.held_count() > 0 and " when its sound ends" or "")
		end

		return true, Execute.uses_ring() and "no spawn points on this level (Psykhanium?): spawning on a ring 10-30 m around you, NOT hidden" or nil
	end

	return ok, err
end

-- /gt_drawtest and /gt_fulltest (2026-10-04): a staged draw to test the HUD. Three cards (the named one and two others of the draw)
-- are dealt as a real hand and the named one is picked STAGE_SECONDS later, as if the draw had chosen it: the Spread, the roulette,
-- the banner, the murmur and the Last Card all play. `full`: its sound plays and its wave spawns after it (a test: no cooldown, no
-- once-per-game); otherwise nothing is sent and nothing sounds. The cycle then goes on where it was.
local STAGE_SECONDS = 3

Director.stage_draw = function (key, full)
	if not Director.is_host() then
		return false, "only the host can stage a draw"
	end

	if stopped or not started or not host_state then
		return false, "the draws are not running (use /gt_start in a mission)"
	end

	if paused then
		return false, "the draws are paused (/gt_pause off first)"
	end

	if host_state.staged then
		return false, "a staged draw is already showing"
	end

	local wave, find_error = Events.find(key, get_setting, Groups)

	if not wave then
		return false, find_error
	end

	local pool, target, others = Events.build_pool(get_setting, Groups, Director.extra_waves()), nil, {}

	for i = 1, #pool do
		if pool[i].key == wave.key then
			target = pool[i]
		else
			others[#others + 1] = pool[i]
		end
	end

	-- a card that is out of the draw is shown all the same
	target = target or { key = wave.key, name = wave.name, def = Events.spawn_def(wave), raw = tonumber(wave.pct) or 0, cooldown = tonumber(wave.cooldown) or Cards.DEFAULT_COOLDOWN, pct = tonumber(wave.pct) or 0 }

	if full and not Events.has_content(wave) then
		return false, "that card has no enemies or effects yet"
	end

	local entries = { target }

	while #entries < 3 and #others > 0 do
		entries[#entries + 1] = table.remove(others, math.random(1, #others))
	end

	-- the named card takes a random place in the hand
	local place = math.random(1, #entries)

	entries[1], entries[place] = entries[place], entries[1]

	local cards = {}

	for i = 1, #entries do
		cards[i] = card_of(entries[i])
	end

	ballot_seq = ballot_seq + 1
	host_state = {
		phase = "hand",
		mode = "tarot",
		remaining = STAGE_SECONDS,
		hand_window = STAGE_SECONDS,
		hand_seconds = STAGE_SECONDS,
		ballot_id = ballot_seq,
		chosen = "",
		cands = {},
		hand = { cards = cards, win = place, seq = ballot_seq },
		drawn = false,
		drawn_age = 0,
		staged = { full = full == true, saved = host_state },
	}
	Votes.close()
	mark_changed()

	return true, wave.name
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

-- (number of waves, number of players) received from clients, for /gt_status
-- number of waves currently running on a fixed timer, for /gt_status
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
	local tune = Tuning and Tuning.status() or { tuned = 0, sizes_known = 0, unsent = 0, pending = 0 }

	return string.format(
		"phase=%s mode=%s remaining=%.0fs paused=%s stopped=%s cands=%d host=%s started=%s in_mission=%s disabled=%s | tracked=%d queued=%d jobs=%d stage=%s err=%s | lua heap %.0f MB (guard %d, paused %s) | timed waves: %d | everyone's waves: %s, %d from %d players | custom mods: %d units with attack stats, %d sizes (%d unsent, %d waiting here)",
		state.phase, tostring(state.mode), state.remaining or 0, tostring(paused), tostring(stopped), #(state.cands or {}), tostring(Director.is_host()), tostring(started), tostring(in_mission), tostring(client_disabled),
		exec.tracked, exec.queued, exec.jobs, tostring(exec.stage), tostring(exec.last_error),
		exec.heap_mb or 0, exec.heap_guard_mb or 0, tostring(exec.heap_paused),
		Director.timed_wave_count(), mod:get("pool_all_players") == true and "on" or "off", Director.peer_wave_count(),
		tune.tuned, tune.sizes_known, tune.unsent, tune.pending
	)
end

return Director
