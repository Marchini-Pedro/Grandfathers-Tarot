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
--   (texts exported before 1.8.0 have no distance fields, 9 instead of 11: they import with distances 0 = use the options)
-- Every free-text field has %, |, ~ and control characters percent-encoded (%7C ...). <check> is 4 hex digits
-- computed from everything before it, so text that was cut short or altered while being copied (chat clients
-- love to wrap lines) is refused instead of half-imported.
--
-- Pure Lua (no engine calls); Events and Groups are passed in so it can be tested offline.
local Presets = {}

Presets.COUNT = 5
Presets.MAX_NAME = 24
Presets.PREFIX = "RW1"
Presets.UNDO_ID = "preset_undo"

-- inclusive ranges, the same as the editor's steppers/popups
local RANGES = {
	pct = { 0, 1000 },
	cd = { 0, 3600 },
	sp = { 0, 100 },
	re = { 1, 600 },
	rf = { 0, 3600 },
	dmin = { 0, 200 },
	dmax = { 0, 200 },
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
	return a.name == b.name and a.recipe == b.recipe and a.enabled == b.enabled and a.pct == b.pct and a.cd == b.cd and a.sp == b.sp and a.re == b.re and a.rf == b.rf and a.dmin == b.dmin and a.dmax == b.dmax
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

-- Writes a preset over the current setup: every wave goes back to its default first.
-- Returns the number of waves that were written from the preset.
Presets.apply = function (preset, set_setting, Events, Groups)
	local stored = {}

	for _, wave in ipairs(preset.waves or {}) do
		stored[wave.key] = wave
	end

	local written = 0

	for _, key in ipairs(Events.keys()) do
		Events.reset(set_setting, key)

		local wave = stored[key]

		if wave then
			local default = default_snapshot(key, Events, Groups)

			if default and (wave.name ~= default.name or wave.recipe ~= default.recipe) then
				local parts = wave.recipe ~= "" and Groups.parse(wave.recipe) or nil

				Events.set_def(set_setting, key, wave.name, parts or {}, Groups)
			end

			set_setting("on_" .. key, wave.enabled == true)
			set_setting("pct_" .. key, wave.pct)
			set_setting("cd_" .. key, wave.cd)
			set_setting("sp_" .. key, wave.sp)
			set_setting("re_" .. key, wave.re)
			set_setting("rf_" .. key, wave.rf)
			set_setting("dmin_" .. key, wave.dmin or 0)
			set_setting("dmax_" .. key, wave.dmax or 0)

			written = written + 1
		end
	end

	return written
end

-- ------------------------------------------------------------------- text format

Presets.encode = function (preset)
	local fields = { Presets.PREFIX, escape(Presets.clean_name(preset.name, "Preset")), tostring(#(preset.waves or {})) }

	for _, wave in ipairs(preset.waves or {}) do
		fields[#fields + 1] = table.concat({
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
		}, "~")
	end

	return Presets.seal(table.concat(fields, "|"))
end

-- Returns { name, waves, skipped } or nil and a message. Nothing is applied here; every wave's recipe is
-- parsed so a bad import is refused as a whole and never leaves half a setup behind.
-- `skipped` counts waves with a key this version does not know (dropped, not an error).
Presets.decode = function (text, Events, Groups)
	text = trim(text)

	if text == "" then
		return nil, "nothing to import (paste the text a friend exported)"
	end

	local fields = split(text, "|")

	if fields[1] ~= Presets.PREFIX then
		return nil, "this is not a RealmsWaves preset (it should start with " .. Presets.PREFIX .. "|)"
	end

	local last_bar = text:match("^.*()|")
	local check = last_bar and text:sub(last_bar + 1)

	if not last_bar or #fields < 4 or check ~= checksum(text:sub(1, last_bar - 1)) then
		return nil, "the preset text is incomplete or was changed (copy it again in full, without adding spaces or line breaks)"
	end

	fields[#fields] = nil

	local expected = tonumber(fields[3])

	if not expected or expected < 0 or expected % 1 ~= 0 or #fields - 3 ~= expected then
		return nil, "the preset text is damaged (wave count does not match)"
	end

	local preset = { name = Presets.clean_name(unescape(fields[2]), "Preset"), waves = {}, skipped = 0 }
	local seen = {}

	for i = 4, #fields do
		local parts = split(fields[i], "~")

		if #parts ~= 9 and #parts ~= 11 then
			return nil, string.format("wave %d of the preset text is damaged", i - 3)
		end

		local key = parts[1]
		local default = default_snapshot(key, Events, Groups)

		if not default then
			preset.skipped = preset.skipped + 1
		elseif not seen[key] then
			seen[key] = true

			local recipe = unescape(parts[9])
			local name = trim(unescape(parts[2]):gsub("[%c]", " "))

			if recipe ~= "" then
				local parsed, err = Groups.parse(recipe)

				if not parsed then
					return nil, string.format("wave %s: %s", name ~= "" and name or key, tostring(err))
				end
			end

			local numbers = {}

			-- 9 fields = exported before the per-wave distances existed: both 0 (use the options)
			parts[10], parts[11] = parts[10] or "0", parts[11] or "0"

			-- fields 4-8 are chance, cooldown, spread, repeat every, repeat for; 10-11 the distances (9 is the recipe)
			for _, field in ipairs({ { "pct", 4 }, { "cd", 5 }, { "sp", 6 }, { "re", 7 }, { "rf", 8 }, { "dmin", 10 }, { "dmax", 11 } }) do
				local id = field[1]
				local value = tonumber(parts[field[2]])

				if not value then
					return nil, string.format("wave %s has a bad %s value", name ~= "" and name or key, id)
				end

				numbers[id] = clamp(whole(value), RANGES[id])
			end

			preset.waves[#preset.waves + 1] = {
				key = key,
				name = name ~= "" and name or default.name,
				recipe = recipe,
				enabled = parts[3] == "1",
				pct = numbers.pct,
				cd = numbers.cd,
				sp = numbers.sp,
				re = numbers.re,
				rf = numbers.rf,
				dmin = numbers.dmin,
				dmax = numbers.dmax,
			}
		end
	end

	return preset
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
