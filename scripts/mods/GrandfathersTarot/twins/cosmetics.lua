-- Twins: what a player sees and hears of the purple stimm (merged from SoloPlayPurpleStimms on 2026-10-07): the colour of the
-- stimmed enemies (eyes and body) and the smoke burst when an enemy splits. Loaded by every player who has the mod (host and
-- guests alike), it only reads that player's own settings and only changes their own game:
--   * the purple buff template is the game's own on every machine; the host only sends "add buff X", and each machine starts the
--     buff's effects from its local template, which this file recolors;
--   * the split burst reaches guests as "play explosion X" (the host's create_explosion sends the template's name), and every
--     machine, host included, plays it through Explosion.create_husk_explosion, which is hooked here.
-- Nothing is sent over the network, so a guest's settings never depend on the host's. Setting ids carry the "tw_" prefix.
local mod = get_mod("GrandfathersTarot")

local PURPLE_BUFF = "mutator_stimmed_minion_purple"
local EXPLOSION_NAME = "purple_stimmed_explosion"
-- There is deliberately NO smoke colour option. The game has no way to recolor this burst that can be relied on: its stim smoke is
-- four fixed-colour particles, and the one place that recolors a smoke particle (green_stimmed.lua) asks a particle for a named
-- material "cloud" through World.set_particles_material_vector3. The cloud names of the burst particle are not in the scripts, and
-- asking a particle for a cloud it does not have is not a Lua error: the engine dereferences a null pointer and the game crashes.

local cosmetics = {}

-- The game reads value[1..3] (0..1) every time a stimmed enemy's eye effects and body tint start. install_color points all of them
-- at this one table, so editing it recolors every enemy stimmed from then on (enemies that are already purple keep their colour).
local DEFAULT_COLOR = { 0.75, 0, 0.75 }
local purple_color = { DEFAULT_COLOR[1], DEFAULT_COLOR[2], DEFAULT_COLOR[3] }
local COLOR_IDS = { tw_color_custom = true, tw_color_r = true, tw_color_g = true, tw_color_b = true }

local function channel(setting_id, default)
	local value = tonumber(mod:get(setting_id)) or default

	return math.max(0, math.min(255, value)) / 255
end

function cosmetics.apply_color()
	if mod:get("tw_color_custom") then
		purple_color[1] = channel("tw_color_r", 191)
		purple_color[2] = channel("tw_color_g", 0)
		purple_color[3] = channel("tw_color_b", 191)
	else
		purple_color[1], purple_color[2], purple_color[3] = DEFAULT_COLOR[1], DEFAULT_COLOR[2], DEFAULT_COLOR[3]
	end
end

-- returns true when the buff was found and its tints now share the editable colour table
function cosmetics.install_color()
	local loaded, BuffTemplates = pcall(require, "scripts/settings/buff/buff_templates")
	local template = loaded and BuffTemplates and BuffTemplates[PURPLE_BUFF]
	local minion_effects = template and template.minion_effects

	if not minion_effects then
		return false
	end

	if minion_effects.material_vector then
		minion_effects.material_vector.value = purple_color
	end

	for _, node_effect in ipairs(minion_effects.node_effects or {}) do
		local material_variables = node_effect.vfx and node_effect.vfx.material_variables

		for _, material_variable in ipairs(material_variables or {}) do
			material_variable.value = purple_color
		end
	end

	cosmetics.apply_color()

	return true
end

local explosion_variants = {}

-- a copy of the game's explosion template without the particle and/or the sound (the game's own table is never modified)
local function explosion_variant(original, keep_vfx, keep_sfx)
	local key = (keep_vfx and "v" or "-") .. (keep_sfx and "s" or "-")
	local variant = explosion_variants[key]

	if variant and variant.__source == original then
		return variant
	end

	variant = {}

	for field, value in pairs(original) do
		variant[field] = value
	end

	variant.__source = original
	variant.vfx = keep_vfx and original.vfx or nil
	variant.sfx = keep_sfx and original.sfx or nil
	explosion_variants[key] = variant

	return variant
end

-- Explosion.create_husk_explosion plays an explosion's effects and sounds on this machine. The host's own playback, the host's
-- prediction and a guest's rpc_trigger_husk_explosion all go through it, so one hook gives every player their own settings.
function cosmetics.install_smoke()
	mod:hook_require("scripts/utilities/attack/explosion", function (Explosion)
		mod:hook(Explosion, "create_husk_explosion", function (func, world, physics_world, wwise_world, attacking_owner_unit_or_nil, explosion_template, position, rotation, radius_variables, charge_level)
			if not explosion_template or explosion_template.name ~= EXPLOSION_NAME then
				return func(world, physics_world, wwise_world, attacking_owner_unit_or_nil, explosion_template, position, rotation, radius_variables, charge_level)
			end

			local smoke = mod:get("tw_smoke_enabled") ~= false
			local sound = mod:get("tw_smoke_sound") ~= false
			local template = explosion_template

			if not smoke or not sound then
				template = explosion_variant(explosion_template, smoke, sound)
			end

			return func(world, physics_world, wwise_world, attacking_owner_unit_or_nil, template, position, rotation, radius_variables, charge_level)
		end)
	end)
end

-- Plays the split burst two metres in front of the local player, through the same hook as a real split (/gt_twins_smoke).
-- Returns true, or false and a reason.
function cosmetics.play_test()
	local player = Managers.player and Managers.player:local_player(1)
	local unit = player and player.player_unit

	if not unit or not Unit.alive(unit) then
		return false, "no player unit yet (join the hub or a mission first)"
	end

	local ok, error_message = pcall(function ()
		local Explosion = require("scripts/utilities/attack/explosion")
		local ExplosionTemplates = require("scripts/settings/damage/explosion_templates")
		local world = Managers.world:world("level_world")
		local physics_world = World.physics_world(world)
		local wwise_world = Managers.world:wwise_world(world)
		local rotation = Unit.local_rotation(unit, 1)
		-- Unit.world_position, not POSITION_LOOKUP: for a player unit the lookup is not a plain Vector3
		local position = Unit.world_position(unit, 1) + Quaternion.forward(rotation) * 2

		Explosion.create_husk_explosion(world, physics_world, wwise_world, nil, ExplosionTemplates.purple_stimmed_explosion, position, Quaternion.look(Vector3.up()), Vector3(0.2, 0.1, 0.2), 1)
	end)

	if not ok then
		return false, tostring(error_message)
	end

	return true
end

-- returns true when the setting was one of this file's
function cosmetics.on_setting_changed(id)
	if COLOR_IDS[id] then
		cosmetics.apply_color()

		return true
	end

	return false
end

return cosmetics
