-- Bounded card effects shared by the editor, presets and host runtime.
local Effects = {}
Effects.SUITS = { prayer = true, miracle = true, grace = true, faith = true }
-- The four groups of the editor's shelf (2026-10-04: Guidance became Buffs, Prayer became Items, and Game Effects is new), in order,
-- with the colour of their dot. `short` is the name on the shelf chip and on the card line.
Effects.CATEGORIES = {
	{ id = "Healing", rgb = { 98, 200, 106 } },
	{ id = "Buffs", rgb = { 108, 180, 255 } },
	{ id = "Items", rgb = { 227, 207, 74 } },
	{ id = "Game Effects", rgb = { 240, 221, 170 } },
}
-- `disabled`: the effect is shown greyed out and never runs (Recharge Med Station, off until it works: user, 2026-10-04); a saved value
-- is kept but ignored.
Effects.ORDER = {
	{ id = "heal", name = "Healing: party health", short = "Party health", max = 100, default = 100, unit = "percent", category = "Healing" },
	{ id = "cleanse", name = "Healing: health and corruption", short = "Health and corruption", max = 100, default = 100, unit = "percent", category = "Healing" },
	{ id = "green_stimm", name = "Healing: give Green Stimm", short = "Green Stimm", max = 4, default = 4, unit = "players", category = "Healing" },
	{ id = "med_crate", name = "Healing: give Med Crates", short = "Med Crates", max = 4, default = 4, unit = "players", category = "Healing" },
	{ id = "med_station", name = "Healing: recharge nearest Med Station", short = "Med Station", max = 4, default = 1, unit = "charges", category = "Healing", disabled = true },
	-- (2026-10-04: the three stimm buffs are Buffs, the three stimm items are Items; the id blue_stimm stays the Blue Stimm buff so saved
	-- cards keep it)
	{ id = "cooldown", name = "Buffs: restore combat abilities", short = "Combat abilities", max = 100, default = 100, unit = "percent", category = "Buffs" },
	{ id = "reveal", name = "Buffs: reveal Specialists", short = "Reveal Specialists", max = 300, default = 15, unit = "seconds", category = "Buffs" },
	{ id = "yellow_stimm_buff", name = "Buffs: Yellow Stimm buff", short = "Yellow Stimm buff", max = 300, default = 15, unit = "seconds", category = "Buffs", targets = true },
	{ id = "blue_stimm", name = "Buffs: Blue Stimm buff", short = "Blue Stimm buff", max = 300, default = 15, unit = "seconds", category = "Buffs", targets = true },
	{ id = "red_stimm_buff", name = "Buffs: Red Stimm buff", short = "Red Stimm buff", max = 300, default = 15, unit = "seconds", category = "Buffs", targets = true },
	{ id = "yellow_stimm", name = "Items: give Yellow Stimm", short = "Yellow Stimm item", max = 4, default = 4, unit = "players", category = "Items" },
	{ id = "blue_stimm_item", name = "Items: give Blue Stimm", short = "Blue Stimm item", max = 4, default = 4, unit = "players", category = "Items" },
	{ id = "red_stimm_item", name = "Items: give Red Stimm", short = "Red Stimm item", max = 4, default = 4, unit = "players", category = "Items" },
	-- Raise the fallen (2026-10-04): one knocked-down player and one hogtied one, no amount to choose
	{ id = "revive", name = "Game Effects: raise the fallen", short = "Raise the fallen", max = 1, default = 1, unit = "players", category = "Game Effects", fixed = true },
	{ id = "ammo", name = "Game Effects: refill ammunition", short = "Refill ammunition", max = 100, default = 100, unit = "percent", category = "Game Effects" },
	{ id = "grenades", name = "Game Effects: replenish grenades", short = "Replenish grenades", max = 6, default = 2, unit = "grenades", category = "Game Effects" },
	{ id = "ammo_crate", name = "Game Effects: give Ammo Crates", short = "Ammo Crates", max = 4, default = 4, unit = "players", category = "Game Effects" },
	{ id = "blackout", name = "Blackout: power interruption", short = "Blackout", max = 300, default = 15, unit = "seconds", hostile = true },
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
		if values and values[def.id] and not def.disabled and (Effects.beneficial(suit) ~= (def.hostile == true)) then result[def.id] = values[def.id] end
	end
	return result
end
local category_rgb = {}
for _, category in ipairs(Effects.CATEGORIES) do category_rgb[category.id] = category.rgb end
Effects.category_rgb = function (id) return category_rgb[id] end
-- The amount in front of an effect's name, as the card shows it: "95%", "15s", "4"
Effects.lead = function (def, value)
	if def.fixed then return "1+1" end -- (Raise the fallen: one downed and one hogtied)
	return def.unit == "percent" and (value .. "%") or def.unit == "seconds" and (value .. "s") or tostring(value)
end
-- The card's lines (2026-10-04, the design page): "95% Party health", the amount in the bone colour and the name in its group's colour
-- when `markup(text, rgb)` is given (the game's colour tags), "+N more" when they do not fit in `max_lines`.
Effects.summary = function (values, max_lines, max_chars, markup, text_rgb)
	local text = {}
	for _, def in ipairs(Effects.ORDER) do
		local effect = values and values[def.id]
		if effect and effect.value > 0 and not def.hostile then
			local lead, name = Effects.lead(def, effect.value), def.short
			if max_chars and #lead + 1 + #name > max_chars then name = name:sub(1, math.max(1, max_chars - #lead - 4)) .. "..." end
			text[#text + 1] = markup and (markup(lead, text_rgb) .. " " .. markup(name, category_rgb[def.category])) or (lead .. " " .. name)
		end
	end
	if max_lines and #text > max_lines then
		local extra = #text - max_lines + 1
		while #text >= max_lines do table.remove(text) end
		text[#text + 1] = "+" .. extra .. " more"
	end
	return table.concat(text, "\n")
end
-- One dot per group the card's effects belong to, in the order of the groups (the card's dots, like an enemy card's)
Effects.dots = function (values)
	local list = {}
	for _, category in ipairs(Effects.CATEGORIES) do
		for _, def in ipairs(Effects.ORDER) do
			local effect = values and values[def.id]
			if def.category == category.id and effect and effect.value > 0 then list[#list + 1] = category.rgb; break end
		end
	end
	return list
end
Effects.has_content = function (wave)
	if Effects.beneficial(wave.suit) then return Effects.encode(Effects.allowed(wave.effects, wave.suit)) ~= "" end
	return (wave.parts and #wave.parts > 0) or (wave.effects and wave.effects.blackout and wave.effects.blackout.value > 0) or false
end
return Effects
