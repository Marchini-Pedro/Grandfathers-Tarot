-- /gt_perf [seconds]: where the mod's update spends its time IN GAME (2026-10-19, the user: "it's still spiking" after /gt_stop with
-- no card enemy alive). Mod Performance Monitor only sees the whole `event update`; this times its parts for a while: each part is
-- wrapped by a timer for the session and put back afterwards (nothing is wrapped otherwise, so it costs nothing when unused).
--
-- For every part: the time a second, the slowest call, the calls over 1 ms, and how many calls had the Lua garbage collector run
-- inside them (the heap shrank during the call) with their time. The monitor bills a GC step to whichever mod allocated when it
-- ran, so a part that is slow only when the GC ran inside it is the GC's cost, not the part's own.
local Perf = {}

local SLOW_MS = 1
local DEFAULT_SECONDS = 30
local MAX_SECONDS = 600

local mod = nil
local now, timer_name = nil, nil
local session = nil

-- a millisecond clock: QueryPerformanceCounter through the ffi DMF hands mods (Mods.lua.ffi), else os.clock (1 ms steps)
local function make_timer()
	local lua = rawget(_G, "Mods") and rawget(_G, "Mods").lua
	local ffi = type(lua) == "table" and lua.ffi or nil

	if type(ffi) == "table" and ffi.cdef and ffi.new then
		-- (another mod may have declared these already: then cdef raises and the declarations are there)
		pcall(ffi.cdef, "int QueryPerformanceCounter(int64_t *c); int QueryPerformanceFrequency(int64_t *f);")

		local ok, clock = pcall(function ()
			local C = ffi.C
			local counter, frequency = ffi.new("int64_t[1]"), ffi.new("int64_t[1]")

			C.QueryPerformanceFrequency(frequency)

			local per_ms = tonumber(frequency[0]) / 1000

			if not (per_ms > 0) then
				error("no frequency")
			end

			return function ()
				C.QueryPerformanceCounter(counter)

				return tonumber(counter[0]) / per_ms
			end
		end)

		if ok and clock then
			return clock, "QueryPerformanceCounter"
		end
	end

	return function () return os.clock() * 1000 end, "os.clock (1 ms steps)"
end

Perf.init = function (deps)
	mod = deps.mod
	now, timer_name = make_timer()
end

Perf.running = function ()
	return session ~= nil
end

local function stat(label)
	local entry = session.stats[label]

	if not entry then
		entry = { label = label, calls = 0, ms = 0, max = 0, slow = 0, gc = 0, gc_ms = 0 }
		session.stats[label] = entry
		session.order[#session.order + 1] = entry
	end

	return entry
end

local function record(entry, before_kb, started, ...)
	local ms = now() - started

	entry.calls = entry.calls + 1
	entry.ms = entry.ms + ms

	if ms > entry.max then
		entry.max = ms
	end

	if ms >= SLOW_MS then
		entry.slow = entry.slow + 1
	end

	if collectgarbage("count") < before_kb then
		entry.gc = entry.gc + 1
		entry.gc_ms = entry.gc_ms + ms
	end

	return ...
end

-- runs fn(...) timed under `label` while a session runs (the entry script's whole update goes through here)
Perf.measure = function (label, fn, ...)
	if not session then
		return fn(...)
	end

	local entry = stat(label)

	return record(entry, collectgarbage("count"), now(), fn(...))
end

-- { label, table, method }: the parts of the update, by the module tables they are called through (each caller looks the method up
-- on the table at the call, so a wrapper put there is the one called)
local function targets(rw)
	return {
		{ "dormancy.update", rw.dormancy, "update" },
		{ "hook_gate.update", rw.hook_gate, "update" },
		{ "effects.tick_audio", rw.effects, "tick_audio" },
		{ "effects.update", rw.effects, "update" },
		{ "director.update (all)", rw.director, "update" },
		{ "execute.update (all)", rw.execute, "update" },
		{ "tuning.update (all)", rw.tuning, "update" },
		{ "tuning.update_client", rw.tuning, "update_client" },
		{ "tuning.update_bosses", rw.tuning, "update_bosses" },
		{ "tuning.update_glow", rw.tuning, "update_glow" },
		{ "twins.update", rw.twins, "update" },
		{ "bypass.purge", rw.bypass, "purge" },
		{ "appearance.update", rw.appearance, "update" },
		{ "appearance.send_all", rw.appearance, "send_all" },
		{ "protocol.send_state", rw.protocol, "send_state" },
		{ "protocol.send_scales", rw.protocol, "send_scales" },
		{ "events.build_pool", rw.events, "build_pool" },
	}
end

local function unwrap()
	if not session then
		return
	end

	for i = #session.wrapped, 1, -1 do
		local w = session.wrapped[i]

		-- only our own wrapper is taken out (a hot reload may have put a new function there meanwhile)
		if w.tbl[w.method] == w.wrapper then
			w.tbl[w.method] = w.original
		end
	end

	session.wrapped = {}
end

local function report()
	local s = session
	local seconds = math.max(s.elapsed, 0.001)
	local lines = {}

	table.sort(s.order, function (a, b) return a.ms > b.ms end)

	lines[#lines + 1] = string.format("GrandfathersTarot /gt_perf: %.0f s, %d frames, timer %s, Lua heap %.0f MB", s.elapsed, s.frames, timer_name, collectgarbage("count") / 1024)

	for i = 1, #s.order do
		local e = s.order[i]

		if e.calls > 0 then
			lines[#lines + 1] = string.format("%s: %.2f ms/s, %.4f ms/frame, max %.2f ms, %d over %d ms, GC inside %d (%.1f ms)", e.label, e.ms / seconds, e.ms / math.max(1, s.frames), e.max, e.slow, SLOW_MS, e.gc, e.gc_ms)
		end
	end

	return lines
end

-- Ends the session (the parts are put back) and prints the report; `quiet` (an unload): no report.
Perf.stop = function (quiet)
	if not session then
		return nil
	end

	unwrap()

	local lines = not quiet and report() or nil

	session = nil

	if lines and mod then
		for i = 1, #lines do
			if mod.info then mod:info("%s", lines[i]) end
		end

		-- the chat gets the header and the six heaviest parts; the console log has every line
		for i = 1, math.min(7, #lines) do
			mod:echo("%s", lines[i])
		end
	end

	return lines
end

Perf.start = function (rw, seconds)
	if not mod or not now then
		return false, "not ready"
	end

	if session then
		Perf.stop(true)
	end

	seconds = math.max(1, math.min(MAX_SECONDS, math.floor(tonumber(seconds) or DEFAULT_SECONDS)))
	session = { seconds = seconds, elapsed = 0, frames = 0, stats = {}, order = {}, wrapped = {} }

	for _, target in ipairs(targets(rw or {})) do
		local label, tbl, method = target[1], target[2], target[3]
		local original = type(tbl) == "table" and tbl[method]

		if type(original) == "function" then
			local entry = stat(label)
			local wrapper = function (...)
				return record(entry, collectgarbage("count"), now(), original(...))
			end

			tbl[method] = wrapper
			session.wrapped[#session.wrapped + 1] = { tbl = tbl, method = method, original = original, wrapper = wrapper }
		end
	end

	return true, seconds
end

-- every frame from the entry script's update: counts the frames and ends the session when its time is up
Perf.update = function (dt)
	if not session then
		return
	end

	session.frames = session.frames + 1
	session.elapsed = session.elapsed + (tonumber(dt) or 0)

	if session.elapsed >= session.seconds then
		Perf.stop()
	end
end

return Perf
