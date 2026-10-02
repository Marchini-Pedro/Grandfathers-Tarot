-- Presets: five named snapshots of the whole wave setup (every wave's name, composition, enabled,
-- chance weight, cooldown, spread and repeat settings), plus text import/export so setups can be shared.
--
-- A preset only stores the waves that DIFFER from the built-in defaults, so it stays short. Applying
-- one first resets every wave to its default and then writes the stored ones, i.e. the result is exactly
-- the setup that was saved, not a mix with what was there before.
--
-- Storage (DMF settings, plain strings): preset_1 .. preset_5, and preset_undo (the setup that was active
-- right before the last "load", so a load can be undone). "" = empty slot.
--
-- Text format (one line, safe to paste into chat):
--   RW1|<name>|<wave count>|<wave>|<wave>...|<check>
--   wave = key~name~enabled(1/0)~chance~cooldown~spread~repeat_every~repeat_for~recipe~min_distance~max_distance
--   ~fixed_timer_seconds (0 = off; see events.lua "ev_") ~deleted(1/0, a standard wave the player removed)
--   ~suit ~threat_override(0-5) ~whisper(text) ~cooldown_look(rot|whisper|vial or empty)   (the tarot card data)
--   (texts exported before 1.8.0 have no distance fields (9 fields), before 1.11.0 no timer (11 fields): the missing
--   values import as 0 = use the options / no timer)
-- Every free-text field has %, |, ~ and control characters percent-encoded (%7C ...). <check> is 4 hex digits
-- computed from everything before it, so text that was cut short or altered while being copied (chat clients
-- love to wrap lines) is refused instead of half-imported.
--
-- Pure Lua (no engine calls); Events and Groups are passed in so it can be tested offline.
local Presets = {}

Presets.COUNT = 5
Presets.MAX_NAME = 24
Presets.PREFIX = "RW1"
Presets.WAVE_PREFIX = "RWW1" -- one wave on its own
Presets.UNDO_ID = "preset_undo"

-- inclusive ranges, the same as the editor's steppers/popups
local SUITS = {
	plague = true, murmur = true, rage = true, blight = true, swarm = true, fateful = true,
	volley = true, snare = true, brute = true, fester = true, dusk = true, warp = true,
}
local LOOKS = { rot = true, whisper = true, vial = true }
local MAX_WHISPER = 40 -- same limit as Cards.MAX_WHISPER

-- a whisper as stored: no control characters, single spaces, at most MAX_WHISPER characters
local function clean_whisper(text)
	text = tostring(text or ""):gsub("[%c]", " "):gsub("%s+", " ")
	text = text:gsub("^%s+", ""):gsub("%s+$", "")

	if #text > MAX_WHISPER then
		text = text:sub(1, MAX_WHISPER):gsub("%s+$", "")
	end

	return text
end

local RANGES = {
	pct = { 0, 10 },
	cd = { 0, 3600 },
	sp = { 0, 100 },
	re = { 1, 600 },
	rf = { 0, 3600 },
	dmin = { 0, 200 },
	dmax = { 0, 200 },
	timer = { 0, 3600 },
}

local function no_settings()
	return nil
end

local function escape(text)
	return (tostring(text or ""):gsub("[%%|~%c]", function (char)
		return string.format("%%%02X", char:byte())
	end))
end

local function unescape(text)
	return (text:gsub("%%(%x%x)", function (hex)
		return string.char(tonumber(hex, 16))
	end))
end

-- plain split that keeps empty fields
local function split(text, separator)
	local fields = {}
	local start = 1

	while true do
		local at = text:find(separator, start, true)

		if not at then
			fields[#fields + 1] = text:sub(start)

			return fields
		end

		fields[#fields + 1] = text:sub(start, at - 1)
		start = at + #separator
	end
end

-- 4 hex digits over the text before the last "|"
local function checksum(text)
	local sum = 0

	for i = 1, #text do
		sum = (sum + text:byte(i) * (i % 251 + 1)) % 65521
	end

	return string.format("%04x", sum)
end

-- Appends the check field to a body ("RW1|name|n|waves...").
Presets.seal = function (body)
	return body .. "|" .. checksum(body)
end

local function clamp(value, range)
	return math.max(range[1], math.min(range[2], value))
end

local function whole(value)
	return math.floor((tonumber(value) or 0) + 0.5)
end

local function trim(text)
	return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

Presets.clean_name = function (name, fallback)
	name = trim(tostring(name or ""):gsub("[%c]", " "):gsub("%s+", " "))

	if #name > Presets.MAX_NAME then
		name = trim(name:sub(1, Presets.MAX_NAME))
	end

	return name ~= "" and name or fallback or ""
end

Presets.default_name = function (index)
	return "Preset " .. tostring(index)
end

local function recipe_of(wave, Groups)
	return wave.parts and #wave.parts > 0 and Groups.to_recipe(wave.parts) or ""
end

local function same_wave(a, b)
	return a.name == b.name and a.recipe == b.recipe and a.enabled == b.enabled and a.pct == b.pct and a.cd == b.cd and a.sp == b.sp and a.re == b.re and a.rf == b.rf and a.dmin == b.dmin and a.dmax == b.dmax and a.timer == b.timer and a.deleted == b.deleted and a.suit == b.suit and a.thr == b.thr and a.whisper == b.whisper and a.look == b.look
end

-- A wave as stored in a preset.
local function snapshot(key, wave, Groups)
	return {
		key = key,
		name = wave.name,
		recipe = recipe_of(wave, Groups),
		enabled = wave.enabled == true,
		pct = whole(wave.pct),
		cd = whole(wave.cooldown),
		sp = whole(wave.spread),
		re = whole(wave.rep_every),
		rf = whole(wave.rep_for),
		dmin = whole(wave.dmin),
		dmax = whole(wave.dmax),
		timer = whole(wave.timer),
		deleted = wave.deleted == true,
		suit = SUITS[wave.suit] and wave.suit or "plague",
		thr = math.max(0, math.min(5, whole(wave.threat_override))),
		whisper = clean_whisper(wave.whisper),
		look = LOOKS[wave.look] and wave.look or "",
	}
end

local function default_snapshot(key, Events, Groups)
	local wave = Events.get(key, no_settings, Groups)

	return wave and snapshot(key, wave, Groups) or nil
end

-- Reads the current setup (`get_setting(id)` reads a mod setting). Returns a preset without a name:
-- { waves = { {key, name, recipe, enabled, pct, cd, sp, re, rf}, ... } } holding only changed waves.
Presets.capture = function (get_setting, Events, Groups)
	local waves = {}

	for _, key in ipairs(Events.keys()) do
		local current = Events.get(key, get_setting, Groups)
		local now = current and snapshot(key, current, Groups)
		local default = now and default_snapshot(key, Events, Groups)

		if now and default and not same_wave(now, default) then
			waves[#waves + 1] = now
		end
	end

	return { waves = waves }
end

-- Writes one stored wave onto `key` (the wave goes back to its defaults first, so nothing of the old
-- settings survives). The key does not have to be the wave's own key: that is how a wave shared by a
-- friend lands in whichever slot you chose.
Presets.apply_wave = function (wave, key, set_setting, Events, Groups)
	Events.reset(set_setting, key)

	local default = default_snapshot(key, Events, Groups)
	local name = wave.name ~= "" and wave.name or (default and default.name) or key

	if default and (name ~= default.name or wave.recipe ~= default.recipe) then
		local parts = wave.recipe ~= "" and Groups.parse(wave.recipe) or nil

		Events.set_def(set_setting, key, name, parts or {}, Groups)
	end

	set_setting("on_" .. key, wave.enabled == true)
	set_setting("pct_" .. key, wave.pct)
	set_setting("cd_" .. key, wave.cd)
	set_setting("sp_" .. key, wave.sp)
	set_setting("re_" .. key, wave.re)
	set_setting("rf_" .. key, wave.rf)
	set_setting("dmin_" .. key, wave.dmin or 0)
	set_setting("dmax_" .. key, wave.dmax or 0)
	set_setting("ev_" .. key, wave.timer or 0)
	set_setting("del_" .. key, wave.deleted == true)
	-- tarot data; a text from before the Tarot (no suit) leaves the card's own defaults
	set_setting("su_" .. key, wave.suit or "")
	set_setting("th_" .. key, wave.thr or 0)
	set_setting("wh_" .. key, wave.whisper or "")
	set_setting("cl_" .. key, wave.look or "")
end

-- Writes a preset over the current setup: every wave goes back to its default first.
-- Returns the number of waves that were written from the preset.
Presets.apply = function (preset, set_setting, Events, Groups)
	local stored = {}

	for _, wave in ipairs(preset.waves or {}) do
		stored[wave.key] = wave
	end

	local written = 0

	for _, key in ipairs(Events.keys()) do
		if stored[key] then
			Presets.apply_wave(stored[key], key, set_setting, Events, Groups)

			written = written + 1
		else
			Events.reset(set_setting, key)
		end
	end

	return written
end

-- The current state of ONE wave (for sharing it on its own).
Presets.capture_wave = function (get_setting, key, Events, Groups)
	local current = Events.get(key, get_setting, Groups)

	return current and snapshot(key, current, Groups) or nil
end

-- Every enabled wave that has enemies and a chance above 0, as full snapshots (not only the changed ones):
-- what a client tells the host so its waves can join the draw. { name, waves }.
Presets.enabled_waves = function (get_setting, Events, Groups)
	local waves = {}

	for _, key in ipairs(Events.keys()) do
		local wave = Events.get(key, get_setting, Groups)

		-- timed waves run on the host's own clock for that player only, they never join someone else's draw
		if wave and wave.enabled and wave.parts and #wave.parts > 0 and wave.pct > 0 and not (wave.timer > 0) then
			waves[#waves + 1] = snapshot(key, wave, Groups)
		end
	end

	return { name = "waves", waves = waves }
end

-- A decoded preset as wave-likes the draw can use (Events.build_pool's `extra`). `owner` (a peer id) goes
-- into each key so waves of different players never collide. At most `limit` waves (default 40).
Presets.pool_waves = function (preset, owner, Events, Groups, limit)
	local list = {}

	for i, wave in ipairs(preset.waves or {}) do
		if i > (limit or 40) then
			break
		end

		local parts = wave.recipe ~= "" and Groups.parse(wave.recipe) or nil

		if parts and #parts > 0 and wave.enabled and wave.pct > 0 and not ((wave.timer or 0) > 0) then
			local standard = Events.get_standard(wave.key)

			list[#list + 1] = {
				key = tostring(owner) .. ":" .. wave.key,
				name = wave.name ~= "" and wave.name or wave.key,
				parts = parts,
				enabled = true,
				pct = wave.pct,
				cooldown = wave.cd,
				spread = wave.sp,
				rep_every = wave.re,
				rep_for = wave.rf,
				dmin = wave.dmin or 0,
				dmax = wave.dmax or 0,
				monster = standard and standard.monster or false,
				suit = wave.suit or (standard and standard.suit) or "plague",
				threat_override = wave.thr or 0,
				whisper = wave.whisper or (standard and standard.whisper) or "",
				look = wave.look or "",
				owner = owner,
			}
		end
	end

	return list
end
-- ------------------------------------------------------------------- text format

local function wave_text(wave)
	return table.concat({
		wave.key,
		escape(wave.name),
		wave.enabled and "1" or "0",
		tostring(wave.pct),
		tostring(wave.cd),
		tostring(wave.sp),
		tostring(wave.re),
		tostring(wave.rf),
		escape(wave.recipe),
		tostring(wave.dmin or 0),
		tostring(wave.dmax or 0),
		tostring(wave.timer or 0),
		wave.deleted and "1" or "0",
		wave.suit or "",
		tostring(wave.thr or 0),
		escape(wave.whisper or ""),
		wave.look or "",
	}, "~")
end

-- One wave from its "key~name~..." text. Returns the wave, or nil and a message. The recipe is parsed here
-- so a wave that cannot be built is refused.
local function parse_wave(text, Groups)
	local parts = split(text, "~")

	if #parts ~= 9 and #parts ~= 11 and #parts ~= 12 and #parts ~= 13 and #parts ~= 17 then
		return nil, "a wave in the text is damaged"
	end

	local recipe = unescape(parts[9])
	local name = trim(unescape(parts[2]):gsub("[%c]", " "))
	local label = name ~= "" and name or parts[1]

	if recipe ~= "" then
		local parsed, err = Groups.parse(recipe)

		if not parsed then
			return nil, string.format("wave %s: %s", label, tostring(err))
		end
	end

	-- 9 fields = exported before the per-wave distances existed: both 0 (use the options)
	parts[10], parts[11], parts[12] = parts[10] or "0", parts[11] or "0", parts[12] or "0"

	local numbers = {}

	-- fields 4-8 are chance, cooldown, spread, repeat every, repeat for; 10-11 the distances (9 is the recipe)
	for _, field in ipairs({ { "pct", 4 }, { "cd", 5 }, { "sp", 6 }, { "re", 7 }, { "rf", 8 }, { "dmin", 10 }, { "dmax", 11 }, { "timer", 12 } }) do
		local id = field[1]
		local value = tonumber(parts[field[2]])

		if not value then
			return nil, string.format("wave %s has a bad %s value", label, id)
		end

		numbers[id] = clamp(whole(value), RANGES[id])
	end

	return {
		key = parts[1],
		name = name,
		recipe = recipe,
		enabled = parts[3] == "1",
		pct = numbers.pct,
		cd = numbers.cd,
		sp = numbers.sp,
		re = numbers.re,
		rf = numbers.rf,
		dmin = numbers.dmin,
		dmax = numbers.dmax,
		timer = numbers.timer,
		deleted = parts[13] == "1",
		-- 17 fields = with the tarot data; an unknown suit from a friend becomes plague, an unknown look is dropped
		suit = parts[14] ~= nil and (SUITS[parts[14]] and parts[14] or (parts[14] ~= "" and "plague" or nil)) or nil,
		thr = math.max(0, math.min(5, whole(tonumber(parts[15]) or 0))),
		whisper = clean_whisper(unescape(parts[16] or "")),
		look = LOOKS[parts[17]] and parts[17] or "",
	}
end

-- Splits a sealed text into its fields after checking the prefix and the check field.
-- Returns the fields without the check field, or nil and a message.
local function open_text(text, prefix, what)
	text = trim(text)

	if text == "" then
		return nil, "nothing to import (paste the text a friend exported)"
	end

	local fields = split(text, "|")

	if fields[1] ~= prefix then
		return nil, string.format("this is not a RealmsWaves %s (it should start with %s|)", what, prefix)
	end

	local last_bar = text:match("^.*()|")
	local check = last_bar and text:sub(last_bar + 1)

	if not last_bar or #fields < 3 or check ~= checksum(text:sub(1, last_bar - 1)) then
		return nil, string.format("the %s text is incomplete or was changed (copy it again in full, without adding spaces or line breaks)", what)
	end

	fields[#fields] = nil

	return fields
end

Presets.encode = function (preset)
	local fields = { Presets.PREFIX, escape(Presets.clean_name(preset.name, "Preset")), tostring(#(preset.waves or {})) }

	for _, wave in ipairs(preset.waves or {}) do
		fields[#fields + 1] = wave_text(wave)
	end

	return Presets.seal(table.concat(fields, "|"))
end

-- Returns { name, waves, skipped } or nil and a message. Nothing is applied here; every wave's recipe is
-- parsed so a bad import is refused as a whole and never leaves half a setup behind.
-- `skipped` counts waves with a key this version does not know (dropped, not an error).
Presets.decode = function (text, Events, Groups)
	local fields, problem = open_text(text, Presets.PREFIX, "preset")

	if not fields then
		return nil, problem
	end

	local expected = tonumber(fields[3])

	if #fields < 3 or not expected or expected < 0 or expected % 1 ~= 0 or #fields - 3 ~= expected then
		return nil, "the preset text is damaged (wave count does not match)"
	end

	local preset = { name = Presets.clean_name(unescape(fields[2]), "Preset"), waves = {}, skipped = 0 }
	local seen = {}

	for i = 4, #fields do
		local wave, err = parse_wave(fields[i], Groups)

		if not wave then
			return nil, err
		end

		local default = default_snapshot(wave.key, Events, Groups)

		if not default then
			preset.skipped = preset.skipped + 1
		elseif not seen[wave.key] then
			seen[wave.key] = true
			wave.name = wave.name ~= "" and wave.name or default.name
			preset.waves[#preset.waves + 1] = wave
		end
	end

	return preset
end

-- ONE wave as a sealed text: RWW1|<wave>|<check> (the same wave format as inside a preset).
Presets.encode_wave = function (wave)
	return Presets.seal(Presets.WAVE_PREFIX .. "|" .. wave_text(wave))
end

-- Returns the wave (its `key` is the exporter's; the caller decides where it goes) or nil and a message.
Presets.decode_wave = function (text, Events, Groups)
	if trim(text):sub(1, #Presets.PREFIX + 1) == Presets.PREFIX .. "|" then
		return nil, "this is a whole preset, not a single wave: import it on the Presets screen"
	end

	local fields, problem = open_text(text, Presets.WAVE_PREFIX, "wave")

	if not fields then
		return nil, problem
	end

	if #fields ~= 2 then
		return nil, "the wave text is damaged"
	end

	return parse_wave(fields[2], Groups)
end

-- ---------------------------------------------------------------------- slots

Presets.slot_id = function (index)
	return "preset_" .. tostring(index)
end

-- Returns the preset in a slot, or nil (empty slot) and, when the stored text is broken, a message.
Presets.read = function (get_setting, id, Events, Groups)
	local text = get_setting(id)

	if type(text) ~= "string" or text == "" then
		return nil
	end

	local preset, err = Presets.decode(text, Events, Groups)

	if not preset then
		return nil, err
	end

	return preset
end

Presets.write = function (set_setting, id, preset)
	set_setting(id, Presets.encode(preset))
end

Presets.clear = function (set_setting, id)
	set_setting(id, "")
end

return Presets
