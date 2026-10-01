# RealmsWaves (Darktide mod)

Read `docs\README.md` first, then `docs\04-design-and-rationale.md` and `docs\05-implementation-plan.md`.

## Standing rules (from the user)
1. **Keep the docs current, continuously.** Every change to code, behaviour, settings, protocol, or a finding must be reflected in `docs\` in the SAME work session, before you report back: update the affected findings/design docs, tick or add items in `docs\05-implementation-plan.md`, and append a dated line to the results log in `docs\06-verification-and-open-issues.md` (what changed, why, what was or was not tested). Add a `docs\CHANGELOG.md` entry per commit. Never leave docs describing old behaviour.
2. **Commit locally after each coherent change** (this folder is its own git repo, branch `main`). Small commits, clear messages, code and docs together. Git is at `C:\Program Files\Git\cmd\git.exe` (may not be on PATH). Repo-local identity is already configured. Do not push anywhere.
3. Do NOT re-audit TwitchVersus, RealmsEvent, VersusMode, Realms or the game source. Their findings are in `docs\01`-`03` with file:line citations. Only re-check when a doc's audited version (see `docs\README.md`) no longer matches the install; then fix the doc in place.
4. Never edit `mods\TwitchVersus` or `mods\RealmsEvent` (Vortex-managed). Copy code from them instead.

## Practical notes
- Game source clone for reference: `..\..\Darktide-Source-Code\scripts\` (relative to this folder).
- Lua for the Darktide Mod Framework (DMF). Lessons learned in-game are in the results log (e.g. never put a bare `%` in DMF localization text; DMF runs all localized strings through `string.format`).
- Offline scripts in `tools\` (run all five after every change): `check_lua.py` (compile), `logic_test.py`, `editor_test.py`, `entry_test.py` (loads the real entry script with stubs), `hud_test.py` (the wave HUD: arithmetic, widget definitions, the element driven through a whole draw, an audit of every pass it would draw, allocation per frame). `hud_preview.py` and `deck_preview.py` (not tests) draw the Spread's shapes and the Deck's tiles into PNGs so they can be looked at without the game (need Pillow; the Deck one reads the JSON that `DECK_DUMP=<file> python tools/editor_test.py` writes).
- Offline checks: Python `lupa` in the session scratchpad (`pip install --target <dir> lupa`); scripts `check_lua.py` (compile all files, Lua 5.5 is stricter than LuaJIT) and `logic_test.py` (stubbed logic tests) are copied to `tools\` in this repo.
- The game's console logs are in `%APPDATA%\Fatshark\MicrosoftStore\Darktide\console_logs`; check the newest one after the user reports a problem.
