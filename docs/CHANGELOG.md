# Changelog

Newest first. One entry per commit (see also the results log in `06-verification-and-open-issues.md`).

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
