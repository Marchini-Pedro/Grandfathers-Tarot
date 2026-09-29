return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`RealmsWaves` encountered an error loading the Darktide Mod Framework.")

		new_mod("RealmsWaves", {
			mod_script       = "RealmsWaves/scripts/mods/RealmsWaves/RealmsWaves",
			mod_data         = "RealmsWaves/scripts/mods/RealmsWaves/RealmsWaves_data",
			mod_localization = "RealmsWaves/scripts/mods/RealmsWaves/RealmsWaves_localization",
		})
	end,
	packages = {},
	load_after = {
		"Realms",
	},
}
