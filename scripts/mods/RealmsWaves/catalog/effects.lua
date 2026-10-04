-- Bounded card effects shared by the editor, presets and host runtime.
local Effects = {}
Effects.SUITS = { prayer = true, miracle = true, grace = true }
Effects.ORDER = {
	{ id = "heal", name = "Healing: party health", max = 100, default = 100, unit = "percent", category = "Healing" },
	{ id = "cleanse", name = "Healing: health and corruption", max = 100, default = 100, unit = "percent", category = "Healing" },
	{ id = "green_stimm", name = "Healing: give Green Stimm", max = 4, default = 4, unit = "players", category = "Healing" },
	{ id = "med_crate", name = "Healing: give Med Crates", max = 4, default = 4, unit = "players", category = "Healing" },
	{ id = "med_station", name = "Healing: recharge nearest Med Station", max = 4, default = 1, unit = "charges", category = "Healing" },
	{ id = "cooldown", name = "Guidance: restore combat abilities", max = 100, default = 100, unit = "percent", category = "Guidance" },
	{ id = "reveal", name = "Guidance: reveal Specialists", max = 300, default = 15, unit = "seconds", category = "Guidance" },
	{ id = "yellow_stimm", name = "Prayer: give Yellow Stimm", max = 4, default = 4, unit = "players", category = "Prayer" },
	{ id = "blue_stimm", name = "Prayer: Blue Stimm buff", max = 300, default = 15, unit = "seconds", category = "Prayer", targets = true },
	{ id = "blackout", name = "Blackout: power interruption", max = 300, default = 15, unit = "seconds", hostile = true },
}
local defs = {}
for _, def in ipairs(Effects.ORDER) do defs[def.id] = def end
Effects.definition = function (id) return defs[id] end
Effects.beneficial = function (suit) return Effects.SUITS[suit] == true end
Effects.number = function (value, max)
	value = tonumber(value)
	if not value or value ~= value or math.abs(value) == math.huge then return nil end
	return math.max(0, math.min(max, math.floor(value + 0.5)))
end
Effects.parse = function (text)
	if text == nil or text == "" then return {} end
	if type(text) ~= "string" or #text > 512 then return nil, "invalid card effects" end
	local result, seen = {}, {}
	for entry in (text .. ";"):gmatch("(.-);") do
		local id, raw, targets = entry:match("^([%w_]+)=(%d+):(%d+)$")
		local def = defs[id]
		local value = def and Effects.number(raw, def.max)
		local players = Effects.number(targets, 4)
		if not value or not players or players < 1 or seen[id] then return nil, "invalid card effect: " .. entry end
		seen[id] = true
		result[id] = { value = value, players = players }
	end
	return result
end
Effects.encode = function (values)
	local text = {}
	for _, def in ipairs(Effects.ORDER) do
		local effect = values and values[def.id]
		local value = effect and Effects.number(effect.value, def.max)
		local players = effect and Effects.number(effect.players or 4, 4)
		if value and value > 0 and players and players > 0 then text[#text + 1] = def.id .. "=" .. value .. ":" .. players end
	end
	return table.concat(text, ";")
end
Effects.allowed = function (values, suit)
	local result = {}
	for _, def in ipairs(Effects.ORDER) do
		if values and values[def.id] and (Effects.beneficial(suit) ~= (def.hostile == true)) then result[def.id] = values[def.id] end
	end
	return result
end
Effects.summary = function (values, max_lines, max_chars)
	local text = {}
	for _, def in ipairs(Effects.ORDER) do
		local effect = values and values[def.id]
		if effect and effect.value > 0 then
			local line = def.name:gsub("^%w+: ", "") .. " (" .. effect.value .. " " .. def.unit .. ")"
			if max_chars and #line > max_chars then line = line:sub(1, max_chars - 3) .. "..." end
			text[#text + 1] = line
		end
	end
	if max_lines and #text > max_lines then
		local extra = #text - max_lines + 1
		while #text >= max_lines do table.remove(text) end
		text[#text + 1] = "+" .. extra .. " effects"
	end
	return table.concat(text, "\n")
end
Effects.has_content = function (wave)
	if Effects.beneficial(wave.suit) then return Effects.encode(Effects.allowed(wave.effects, wave.suit)) ~= "" end
	return (wave.parts and #wave.parts > 0) or (wave.effects and wave.effects.blackout and wave.effects.blackout.value > 0) or false
end
return Effects
