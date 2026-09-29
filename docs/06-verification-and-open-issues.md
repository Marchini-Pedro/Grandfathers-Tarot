# 06. Verification, risks, open issues

## Test matrix
| # | Test | Expect | Status |
|---|---|---|---|
| 1 | Load with only RealmsWaves enabled (originals off); check `%APPDATA%\Fatshark\Darktide\console_logs` | No errors; mod listed | not run |
| 2 | Solo (SoloPlay / Realms local host): `/rw_test <event>` in a mission | Units appear out of sight, aggro, near players | not run |
| 3 | `/rw_status` before/after wave | Adjusted `total_allocated_num_enemies` and aggroed challenge rating exclude tracked units; hordes and specials still trigger normally | not run |
| 4 | Two-instance Realms LAN (host + client) | Same HUD countdown/ballot on both; client vote counted; same result | not run |
| 5 | Client without the mod joins | Host unaffected; client just sees enemies | not run |
| 6 | Percents not summing to 100; `/rw_roll 1000` | Normalised; frequencies within tolerance | not run |
| 7 | Hub / prologue | No spawning, no errors | not run |
| 8 | Leave mission; hot reload (`ctrl+shift+r`) | State cleared; state survives reload sanely | not run |
| 9 | Ghost host present (DTRealmsGhostHost) | Waves still spawn near guests | not run |
| 10 | Open the wave editor (F6 / `/rw_editor`) in a mission and in the hub | View opens, no errors in console log; list shows 32 waves with compositions | not run |
| 11 | Editor: edit a built-in wave (count stepper, remove, add from picker, rename, edit as text, reset) | Values persist across closing/reopening the editor and restarting the game; next draw uses them | not run |
| 12 | Editor: build a custom wave in a slot, enable it, `/rw_test custom_1` | Spawns the composition; appears on ballots | not run |
| 13 | Editor popup: type text/numbers, Enter, Esc, mouse click on OK/Cancel | Input accepted/rejected as designed; hotspots locked while open | not run |
| 14 | `custom_hud` edit mode: find and drag `HudElementRealmsWavesPanel|panel`; sample panel visible | Panel moves, position persists, sample text shows while editing | not run |
| 15 | Interval min 5 s, vote mode | Whole countdown is the voting phase; wave fires after 5 s | not run |
| 16 | HUD percentages | Show `52.1%` style values, no long decimals | not run |
| 17 | Editor opens without crashing (1.1.2 fix), all screens reachable (list, detail, picker, mods, popups) | No errors in the console log | not run |
| 18 | Custom wave `3 crushers[enraged+garden]`, `/rw_test custom_1`, normal mission | Crushers spawn with garden head effect and enraged colour/speed; console has no modifier warnings | not run |
| 19 | Same in a Havoc mission that has only Garden | Enraged crushers still enrage; Garden ones heal neighbours | not run |
| 20 | `[toughened]` in a normal mission | Skipped, one console warning "needs a Havoc mission"; in Havoc it applies | not run |
| 21 | Havoc order with stimmed minions | Wave units are sometimes stimmed (1.1.1 fix) | not run |
| 22 | Client view of modifier effects | Client sees the buff visuals on modified units | not run |
| 23 | Editor rows: hover highlight, click checkbox / `-` / `+` / value / Edit / Mods / Remove | Everything highlights on hover and responds (1.2.1 fix) | not run |
| 24 | Spread radius 0 vs 3 vs 10 with `/rw_test hound_frenzy` | Radius 0 stacks on one spot; 3 and 10 spread the pack; units not in players' view | not run |
| 25 | `5 crushers@2`, repeat every 10 for 35, `/rw_test custom_1` | 5 at once, +2 at 10/20/30 s, none after; also try with a second wave running, and `max_alive` low | not run |
| 26 | Recipe text with `@`: `3 crushers[enraged]@2` in "Edit as text" | Accepted, shown as "(+2 per repeat)" in the list | not run |

## Known risks
- Hooks on `PacingManager.add_aggroed_minion` and the two `MinionSpawnManager` counters must tolerate clients (nil managers) and hot reload.
- Engine query errors: use `get_occluded_positions` / `occluded_positions_in_group` inside pcall (RealmsEvent avoided `get_random_occluded_position`).
- Very large waves: unit/network object limits are real. Mitigation: per-wave and alive caps, drip-feed, queue < ~200.
- Ballot/vote state can go stale if the host leaves mid-vote: clear state on game-state exit and peer-left.
- Host is the only driver; if host has no living humans (ghost host alone), skip and retry.

## Unverified assumptions (check before relying)
1. Whether the shooting-range mission counts as `is_hub` for `BreedLoader` (breed packages).
2. Whether `Managers.connection.combined_hash` mismatches with mods that alter network lookups.
3. (RESOLVED, see below) counter coverage.
4. Whether `mod:hook` on `PacingManager.add_aggroed_minion` is reached for aggro through `MinionPerceptionExtension:aggro()` (call at `minion_perception_extension.lua:349`) in all paths (spawn-time aggro at :133-146).
5. Realms native DLL behaviour (not analysed).
6. `VersusMode.lua` was sampled by grep only, not read fully.

- 2026-09-29 (user report): editor opened, but rows showed no hover highlight and (by the user's description) only the row name and the bottom buttons responded. Root cause and fix in CHANGELOG 1.2.1: `visibility_function` receives the hotspot's own content for passes with a `content_id`; flags must be read via `content.parent`. Lesson: when a UI element is "dead", check what table each pass callback receives (`S\managers\ui\ui_widget.lua:411-446`); tests must emulate that, not just call functions with the widget content. In-game re-check pending.
- 2026-09-29: 1.2.0 modifiers implemented and tested offline (see CHANGELOG). Found while auditing buffs: `havoc_toughened_skin` errors outside Havoc (unguarded `extension("havoc")`), hence the Havoc-only gate. Offline only; in-game rows 17-22 pending.
- 2026-09-29: first in-game open of the wave editor CRASHED (log `console-2026-09-29-00.46.55-a45d7909-*.log`): `wave_editor_view.lua:290: attempt to index field 'title_text' (a nil value)` in `_apply_screen` <- `on_enter`. Cause: my `_create_widgets` override shadowed `BaseView._create_widgets` (`S\ui\views\base_view.lua:140-156`, called from `_on_view_requirements_complete` :110-123 to build the static widgets). Fixed in 1.1.2 (renamed `_create_editor_widgets`). Lesson: RealmsEvent avoided this by naming its helpers `_create_row_widgets` etc.; my offline stub had created static widgets itself, hiding the bug. The stub now mirrors the real flow and a guard test lists every BaseView method name (`BASEVIEW_NAMES` in `tools/editor_test.py`, 79 names from base_view.lua) and fails on any accidental override. Lesson for tests: stubs must reproduce the framework's call flow, not shortcut it.

## Test tooling (in `tools/`, needs Python `lupa`; set env `PYLIBS` to the folder installed with `pip install --target`)
- `check_lua.py`: compiles every Lua file (Lua 5.5 via lupa; stricter than LuaJIT).
- Known limitation (1.3.0): spread offsets are not re-checked for line of sight; only the base point is hidden. A large radius can place a unit in view. Also, `Positions.spread` relies on `NavQueries.position_on_mesh(world, pos, 2, 2)` and `ray_can_go(world, a, b, nil, 2, 2)` with no traverse logic (`S\utilities\nav_queries.lua:7-25, 91+`); untested in the game.
- `logic_test.py` (111 checks; was 62 in 1.2.0): recipe parser (incl. `a|b`, caps, round trip, modifiers `[a+b]`), wave settings API (`Events.get/set_def/reset/build_pool`, legacy recipe), votes, director state machine (random, vote, 5 s interval, hub, client, version mismatch), budget-bypass hooks, the spawner `execute.lua` with stubbed game APIs (expansion, modifier buffs, Havoc gating, contained buff errors, caps, `one_of`), 20,000-roll weight simulation.
- `editor_test.py` (89 checks; loads the game's real `callback()` from the source clone, mirrors the real BaseView flow and guards against overriding BaseView methods): loads the REAL editor view/blueprint/component files against stubbed engine classes (fake `BaseView`, `UIWidget.create_definition`, text-input template) and clicks through list, scroll, toggle, chance stepper, detail, count stepper, remove, picker, rename popup, recipe popup with validation, numeric popup with range check, cooldown, enabled, reset, back navigation, custom-slot workflow. It cannot prove the engine renders or accepts the passes; it does catch nil-index/logic bugs.

## Resolved during implementation
- Unverified #3 (counter coverage): grep of the game source (commit `0f0cb45`) shows every reader of the enemy counts goes through `MinionSpawnManager:num_spawned_minions()` or `:total_allocated_num_enemies()` (terror_event_manager.lua:435, pacing_manager.lua:449, horde_pacing.lua:79 and :516, auto_event.lua:509 and :689, server_metrics_manager.lua:178); the private field `_num_spawned_minions` is only touched inside minion_spawn_manager.lua. So hooking those two methods is complete for this version.
- `SpawnPointQueries.group_from_position(nav_world, nav_spawn_points, position, above, below)` takes `nav_world` FIRST (spawn_point_queries.lua:265), unlike `occluded_positions_in_group(nav_world, nav_spawn_points, group, positions)`. `get_occluded_positions` filters by distance to EVERY player (max distance must be satisfied for all players), which is why RealmsWaves does its own nearest-player filtering.
- DMF hooks by class-name string are queued until the class exists (`hooks.lua` delayed hooks), so hooking `PacingManager` / `MinionSpawnManager` at load is safe.
- Aggro happens inside `spawn_network_unit`, before `spawn_minion` returns the unit, so the bypass uses a "spawning" flag (`Bypass.begin_spawn/end_spawn`) to catch the unit in `add_aggroed_minion`.

## Known trade-offs of the bypass
- **Stimmed minions Havoc condition does not apply to wave units** (found 2026-09-28): the bypass skips `PacingManager.add_aggroed_minion`, which is also where the `minion_aggroed` event that `MutatorStimmedMinions` listens for is fired. Details in doc 03, "Havoc conditions / mutators vs. wave units". FIXED in 1.1.1 (hook re-sends `minion_aggroed` for tracked units); offline test `bypass:*` in `logic_test.py`; in-game check still pending (needs a Havoc order with stimmed minions).
- Skipping `PacingManager.add_aggroed_minion` for wave units also skips `side_system:add_aggroed_minion`, so wave units are absent from the side's aggroed lists. Those lists feed music intensity (`wwise_state_group_*`) and terror-event queries (`TerrorEventQueries.num_aggroed_minions_in_level`). Effect: wave units do not raise the combat music intensity or count for scripted "N enemies aggroed" conditions. Accepted; revisit if it looks wrong in play.
- Positions use `side.valid_player_units` (includes bots). LOS is hidden from bots too, which is harmless.

## Results log
(Append dated entries: what was tested, result, fixes.)

- 2026-09-28: Audit complete, docs written.
- 2026-09-28: Implementation written (all files in `docs/05`). Static: all 14 Lua files compile under Lua 5.5 (lupa). Offline logic tests pass (34 checks): recipe parser (aliases, caps 24/breed and 60 total, errors), pool normalisation to 100 with custom slots, vote tally (change vote, wrong ballot, ties), director state machine in random and vote modes (countdown, voting window, winner fires the 2-vote option, no-vote skip, new cycle after incoming, hub does nothing), client rendering of a synced state, version-mismatch disable, and a 20,000-roll simulation within 0.3 percentage points of the configured chances. **NOT tested in the game**: spawning, position search, budget hooks, Realms RPC delivery, HUD rendering, keybinds. Test matrix above is still "not run".
- 2026-09-28 (first in-game launch, log `console-2026-09-28-22.51.21-*.log` in `%APPDATA%\Fatshark\MicrosoftStore\Darktide\console_logs`): mod loaded (`Init DMF mod 'RealmsWaves'`), all 4 hooks installed (PacingManager.add_aggroed_minion, MinionSpawnManager.num_spawned_minions / total_allocated_num_enemies / unregister_unit). 74 errors `(localize) "%": invalid option '%' to 'format'`: DMF runs every localized string through `string.format`, so a literal `%` in a localization string is an error (a lone `%` unit label, plus `100%)` in a group title and `(%)` in HUD labels). Fixed by using the word "percent". Lesson: never put a bare `%` in DMF localization text (use `%%` only in strings that are always formatted with args, like the HUD lines). The one stack traceback in that log is a game backend promise error, unrelated to the mod.
- 2026-09-28 (user feedback after testing, changes in 1.1.0): (a) HUD percentages showed `52.100000000000001%` -> now formatted with `%.1f`; (b) minimum interval 30 s -> 5 s; (c) the options-menu numeric widget showed `<unit_percent>` because that localization key was broken by the `%` bug -> the per-wave sliders were removed from the options menu anyway; (d) custom waves had options but no interface -> wave editor built; (e) panel not movable in `custom_hud` -> real-sized node. Verified offline only: `logic_test.py` 52/52, `editor_test.py` 45/45, `check_lua.py` 18 files. Still needs in-game verification (matrix rows 10-16).
- 2026-09-28: discovered the user has purged RealmsEvent and TwitchVersus from `mods\` (only empty Vortex marker folders remain). Their files are still in Vortex staging at `%APPDATA%\Vortex\warhammer40kdarktide\mods\<mod folder>\mods\<mod>\...` (e.g. `RealmsEvent 1338 1.1.0 ...\mods\RealmsEvent\scripts\mods\RealmsEvent\v2\view\`). Read them there if a future task needs them; do not restore them into `mods\`.
