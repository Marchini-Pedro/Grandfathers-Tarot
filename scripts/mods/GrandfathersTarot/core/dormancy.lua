-- Asleep outside the games the mod can play in (2026-10-07, the user: "Why is Tarot so high in a normal online havoc game? It should
-- be disabled in a normal game"). The cards play in a game this machine hosts (SoloPlay, a Realms server) or as a Realms server's
-- client. In any other game (Fatshark's servers: missions, Havoc, the hub) every hook of the mod is switched off (DMF keeps it in
-- the chain and calls straight through: no call of ours, no cost billed to the mod), its HUD elements are not created
-- (validation_function), and its update does nothing but the editor's sounds. The editor still opens everywhere.
--
-- Two details:
-- - DMF creates a hook that waits for its class (a file the game requires later) as active: the switch-off is applied again a few
--   seconds into the game (CHECKS), not once.
-- - The editor's keybind guard (a hook on DMF's check_keybinds) wraps every mod's keybinds every frame: it is on only while a text
--   box of the editor is open (Dormancy.sync_keybind_guard), awake or asleep.
local Dormancy = {}

local mod, get_mod_fn = nil, nil
local asleep = false
local checks, clock = nil, 0
local guard_obj, guard_on = nil, nil

-- seconds after entering a game at which the answer is looked at again (and the switch-off re-applied)
local CHECKS = { 0, 2, 10, 30 }

Dormancy.init = function (deps)
	mod = deps.mod
	get_mod_fn = deps.get_mod
	guard_obj = deps.keybind_guard
	asleep, checks, clock, guard_on = false, nil, 0, nil
end

-- true when the cards can play in this game: this machine hosts it, or it is the client of a Realms server; true too while the
-- answer is unknown (no session yet)
Dormancy.playable = function ()
	local session = Managers.state and Managers.state.game_session

	if not session then
		return true
	end

	local ok, server = pcall(session.is_server, session)

	if ok and server == true then
		return true
	end

	local realms = get_mod_fn and get_mod_fn("Realms")
	local realms_session = realms and rawget(realms, "_session")
	local is_client = type(realms_session) == "table" and realms_session.is_active_client

	if type(is_client) == "function" then
		local ok_client, client = pcall(is_client)

		return ok_client and client == true
	end

	return false
end

Dormancy.is_asleep = function ()
	return asleep
end

local function sleep()
	asleep = true
	guard_on = nil

	if mod and mod.disable_all_hooks then
		mod:disable_all_hooks()
	end
end

local function wake()
	if not asleep then
		return
	end

	asleep = false
	guard_on = nil

	-- the mod switched off in DMF's options: DMF keeps its hooks off, never switched on from here
	if mod and mod.is_enabled and not mod:is_enabled() then
		return
	end

	if mod and mod.enable_all_hooks then
		mod:enable_all_hooks()
	end
end

Dormancy.wake = wake

-- the answer, applied (asleep: the switch-off once more, for the hooks DMF created since)
local function check()
	if Dormancy.playable() then
		wake()
	else
		sleep()
	end
end

Dormancy.on_enter_gameplay = function ()
	checks, clock = 1, 0
end

-- back to a menu or a loading screen: awake, the next game decides again
Dormancy.on_exit_gameplay = function ()
	checks = nil
	wake()
end

-- DMF switched every hook back on (the mod enabled again in its options): asleep, they go off again
Dormancy.on_enabled = function ()
	guard_on = nil

	if asleep then
		sleep()
	end
end

-- The editor's keybind guard on only while a text box is open (and the mod enabled: DMF keeps a disabled mod's hooks off).
Dormancy.sync_keybind_guard = function (wanted)
	wanted = wanted == true

	if guard_obj == nil or guard_on == wanted or not mod then
		return
	end

	guard_on = wanted

	if wanted then
		if mod.hook_enable then mod:hook_enable(guard_obj, "check_keybinds") end
	elseif mod.hook_disable then
		mod:hook_disable(guard_obj, "check_keybinds")
	end
end

-- the mod unloaded (a reload): nothing of it is held from here
Dormancy.retire = function ()
	mod, get_mod_fn, guard_obj, checks = nil, nil, nil, nil
end

-- every frame (mod.update); returns true while asleep
Dormancy.update = function (dt)
	if checks then
		clock = clock + (dt or 0)

		while checks and clock >= CHECKS[checks] do
			check()
			checks = checks < #CHECKS and checks + 1 or nil
		end
	end

	return asleep
end

return Dormancy
