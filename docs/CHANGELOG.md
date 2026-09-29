# Changelog

Newest first. One entry per commit (see also the results log in `06-verification-and-open-issues.md`).

## 1.2.1
- **Fix (editor rows had no hover and their buttons did nothing):** the engine calls `visibility_function(pass_content, style)` with `content[content_id]` for passes that have a `content_id` (all hotspots), not the widget content (`ui_widget.lua:411-446`). The row's flagged hotspots (checkbox, `-`, value, `+`, Edit, Mods) looked up their `show_*` flag on the hotspot's own table, got nil, and the engine skipped them entirely. Unflagged ones (row name, bottom buttons) worked, which is what the user saw. The flag is now read from `content.parent` (set by the engine to the widget content).
- Rows now highlight while hovered, and the clickable area of a row is name + composition.
- Test: `editor_test.py` emulates the engine's rule (67 checks): flagged hotspots must run when their flag is on and not when off, hover layers appear on hover, and every visibility/change function of every widget is executed.

## 1.2.0
- **Modifiers (new):** force Havoc-style conditions onto a group of enemies even when the mission did not load them (e.g. Garden only mission + `3 crushers[enraged]`). Eight modifiers: Encroaching Garden, Enraged, Final Toll (enrages at half health), Corrupted, Bolstering, Toughened Skin (Havoc missions only), On Fire, Head Parasite. Implemented as the vanilla buff templates added to each unit right after it spawns (same call the mutators use), guarded per buff so a failing buff never breaks a wave. Failures are always logged once ("RealmsWaves: modifier ... failed"), not only in debug mode.
- **Recipe syntax:** `3 crushers[enraged+garden]`; separators inside brackets can be `+`, `,`, `;`, spaces or "and"; works with random picks (`1 plague ogryn|chaos spawn[garden]`). Same breed with different modifiers stays separate groups. `/rw_custom` and "Edit as text" accept it.
- **Editor:** each enemy row on the detail screen has a **Mods** button that opens a modifier screen (checkbox, name, what it does, Havoc-only note). Composition summaries show modifiers in brackets.
- **Tests:** logic 62 -> parser modifiers + the first offline coverage of the spawner (`execute.lua`: wave expansion, modifier buffs in catalog order, Havoc gating, contained buff errors, `max_per_wave`, `one_of`); editor 60 (Mods screen flow).
- Not offered (need their mutator loaded or are visual-only): Sticky Poxburster (`havoc_sticky_poxburster` queries the mutator manager), purple stimmed (same), Rotten Armor (visual override lives in the mutator), Warp Rift (mutator not present in the audited source).

## 1.1.2
- **Fix (crash on opening the wave editor):** `RealmsWavesView` defined a method named `_create_widgets`, which shadows `BaseView._create_widgets`, the method BaseView itself calls to build the static widgets before `on_enter`. `title_text` (and every other static widget) was therefore nil: `wave_editor_view.lua:290: attempt to index field 'title_text' (a nil value)`. Renamed to `_create_editor_widgets`. The offline editor test now mirrors the real BaseView flow (`_on_view_requirements_complete` -> `_create_widgets` -> `on_enter`) and fails if the view overrides any BaseView method other than init/on_enter/on_exit/update (48 checks).

## 1.1.1
- **Fix:** Havoc "stimmed minions" now apply to wave units. The budget bypass skipped `PacingManager.add_aggroed_minion`, which is also where the `minion_aggroed` event is sent; the hook now re-sends it for tracked units. Offline tests added (`logic_test.py`, 9 bypass checks).
- Docs: audited how Havoc mutators affect wave units and verified that the Garden and Enraged buffs work without their mutator loaded (doc 03).

## 1.1.0 (unreleased, in progress)
User-requested iteration after the first in-game test.
- **Percent display:** HUD shows `52.1%` instead of `52.100000000000001%` (HUD formats with `%.1f`, trailing `.0` trimmed).
- **Minimum time between waves is now 5 s** (was 30 s). The countdown is no longer stretched to `vote_duration + 5`; the highlighted voting window is `min(vote_duration, interval)`, so with a 5 s interval the whole countdown is the voting phase.
- **Wave editor** (new): keybind (default F6, rebindable in mod options) or `/rw_editor`. Lists all 32 waves (12 built-in + 20 custom slots) with their composition; per wave: enable, chance weight, cooldown, rename, edit enemies (count stepper, remove, add from a picker, or edit as text), reset. Custom slots are built here. Replaces the per-wave sliders in the DMF options menu.
- **Per-wave settings** are now `wave_def_<key>` (name + recipe), `on_<key>`, `pct_<key>`, `cd_<key>`. The 1.0.0 `custom_N_recipe` is still read; the 1.0.0 `pct_*`/`custom_N_pct` sliders were removed from the options menu (existing `pct_<key>` values are kept).
- **Recipe syntax** extended: `1 plague ogryn|chaos spawn` picks one alternative per unit (this is how "Boss Ambush" is represented). Limits raised: 60 per breed, 120 total, 12 different enemies per wave.
- **Custom HUD integration:** the wave panel is a real-sized scenegraph node (`HudElementRealmsWavesPanel|panel`) so the `custom_hud` mod's edit mode can move it; a sample panel is shown while that edit mode is open. The `hud_x` / `hud_y` options were removed.
- **Fix:** localization strings no longer contain a bare `%` (DMF formats every localized string; 74 errors in the first launch). Unit labels use the word "percent".
- **Repo:** this folder is now a local git repository (branch `main`). Test tooling in `tools/` (`check_lua.py`, `logic_test.py`, `editor_test.py`).
- **Docs rule:** `CLAUDE.md` now requires docs + changelog + results log to be updated with every change, and a local commit after each coherent change.

## 1.0.0
- Initial implementation: random/vote wave director, hidden-from-all-players spawn positions, director-limit bypass, Realms RPC sync (`rw_hello`, `rw_welcome`, `rw_state`, `rw_vote`), synced HUD panel, 12 built-in waves, 20 custom slots via `/rw_custom`.
