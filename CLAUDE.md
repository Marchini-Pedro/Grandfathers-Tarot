# RealmsWaves (Darktide mod)

Read `docs\README.md` first, then `docs\04-design-and-rationale.md` and `docs\05-implementation-plan.md`.

- Do NOT re-audit TwitchVersus, RealmsEvent, VersusMode, Realms or the game source. Their findings are in `docs\01`-`03` with file:line citations. Only re-check when a doc's audited version (see `docs\README.md`) no longer matches the install; then fix the doc in place.
- Never edit `mods\TwitchVersus` or `mods\RealmsEvent` (Vortex-managed). Copy code from them instead.
- Keep `docs\05` checkboxes and `docs\06` results log current as work proceeds.
- Game source clone for reference: `..\..\Darktide-Source-Code\scripts\` (relative to this folder).
- Lua for the Darktide Mod Framework (DMF). Match the style of RealmsEvent (tabs/spaces as in the source file you copy from).
