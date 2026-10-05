return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`GrandfathersTarot` encountered an error loading the Darktide Mod Framework.")

		new_mod("GrandfathersTarot", {
			mod_script       = "GrandfathersTarot/scripts/mods/GrandfathersTarot/GrandfathersTarot",
			mod_data         = "GrandfathersTarot/scripts/mods/GrandfathersTarot/GrandfathersTarot_data",
			mod_localization = "GrandfathersTarot/scripts/mods/GrandfathersTarot/GrandfathersTarot_localization",
		})
	end,
	packages = {},
	load_after = {
		"Realms",
	},
}
