-- Shared recipe/UI/network schema. No runtime resources or vanilla lookups are registered.
local Appearance = {}

Appearance.METHODS = {
	{ id = "none", name = "Default appearance", info = "Leave the enemy's normal appearance alone.", available = true },
	{ id = "natural_stimm", name = "Natural stimm", info = "Supported enemies use their normal stim action and gameplay buffs. Colour starts when the stim buff activates.", available = true },
	{ id = "applied_stimm", name = "Applied stimm colour", info = "Visual-only stimmed_color on the spawned enemy. Coverage depends on its materials; black switches this tint off.", available = true },
	{ id = "slot_stimm", name = "Explicit body / equipment stimm", info = "Compare the same tint with explicit writes to loadout slots and attachments. Visual-only; this is a coverage experiment.", available = true },
	{ id = "surface", name = "Per-material surface override (unavailable)", info = "Unavailable: first verify a surface colour parameter, its default and supported enemy materials. No guessed parameter is applied.", available = false },
	{ id = "private_shader", name = "Private material / shader patch (unavailable)", info = "Unavailable: needs compatible compiled assets, a loader and verified restoration. No native patch is installed by this option.", available = false },
	{ id = "shadow", name = "Shadow fog (experimental)", info = "The Daemonhost's dark fog follows the enemy until it dies. Its size and look are the game's own effect; A at 0 turns it off. Colour channels do nothing here.", available = true },
	{ id = "outline", name = "Outline", info = "Visual-only coloured outline. Stock tag outlines can take priority. This colours the outline, not the enemy's surface.", available = true },
}

local methods = {}
for _, method in ipairs(Appearance.METHODS) do methods[method.id] = method end
Appearance.method = function (id) return methods[id] end
Appearance.DEFAULT = { method = "none", a = 255, r = 128, g = 0, b = 255 }
Appearance.CHANNELS = { "a", "r", "g", "b" }

Appearance.channel = function (value)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return nil end
	return math.max(0, math.min(255, math.floor(value + 0.5)))
end

Appearance.copy = function (value)
	if type(value) ~= "table" or not methods[value.method] then return nil end
	local result = { method = value.method, outline = value.outline == true, protect = value.protect == true }
	for _, key in ipairs(Appearance.CHANNELS) do
		result[key] = Appearance.channel(value[key])
		if result[key] == nil then return nil end
	end
	return result
end

Appearance.hex = function (value)
	return string.format("%02X%02X%02X%02X", value.a, value.r, value.g, value.b)
end

Appearance.recipe = function (value)
	value = Appearance.copy(value)
	return value and ("<" .. value.method .. (value.outline and "+outline" or "") .. (value.protect and "!" or "") .. ":" .. Appearance.hex(value) .. ">") or ""
end

Appearance.parse = function (text)
	local token, hex = text:match("^([%w_+!]+):(%x%x%x%x%x%x%x%x)$")
	if not token then return nil, "invalid appearance" end
	local id, outline, protect = token, false, false
	if id:sub(-1) == "!" then id, protect = id:sub(1, -2), true end
	if id:sub(-8) == "+outline" then id, outline = id:sub(1, -9), true end
	if not methods[id] then return nil, "invalid appearance; use <applied_stimm:FF8000FF> (eight ARGB hex digits)" end
	return { method = id, outline = outline, protect = protect, a = tonumber(hex:sub(1, 2), 16), r = tonumber(hex:sub(3, 4), 16), g = tonumber(hex:sub(5, 6), 16), b = tonumber(hex:sub(7, 8), 16) }
end

-- The known shader and outline APIs take RGB. A is explicitly tint strength, never promised mesh opacity.
Appearance.rgb = function (value)
	local strength = value.a / (255 * 255)
	return value.r * strength, value.g * strength, value.b * strength
end

return Appearance
