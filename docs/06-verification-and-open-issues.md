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

## Test tooling (in `tools/`, needs Python `lupa`; set env `PYLIBS` to the folder installed with `pip install --target`)
- `check_lua.py`: compiles every Lua file (Lua 5.5 via lupa; stricter than LuaJIT).
- `logic_test.py` (52 checks): recipe parser (incl. `a|b`, caps, round trip), wave settings API (`Events.get/set_def/reset/build_pool`, legacy recipe), votes, director state machine (random, vote, 5 s interval, hub, client, version mismatch), 20,000-roll weight simulation.
- `editor_test.py` (45 checks): loads the REAL editor view/blueprint/component files against stubbed engine classes (fake `BaseView`, `UIWidget.create_definition`, text-input template) and clicks through list, scroll, toggle, chance stepper, detail, count stepper, remove, picker, rename popup, recipe popup with validation, numeric popup with range check, cooldown, enabled, reset, back navigation, custom-slot workflow. It cannot prove the engine renders or accepts the passes; it does catch nil-index/logic bugs.

## Resolved during implementation
- Unverified #3 (counter coverage): grep of the game source (commit `0f0cb45`) shows every reader of the enemy counts goes through `MinionSpawnManager:num_spawned_minions()` or `:total_allocated_num_enemies()` (terror_event_manager.lua:435, pacing_manager.lua:449, horde_pacing.lua:79 and :516, auto_event.lua:509 and :689, server_metrics_manager.lua:178); the private field `_num_spawned_minions` is only touched inside minion_spawn_manager.lua. So hooking those two methods is complete for this version.
- `SpawnPointQueries.group_from_position(nav_world, nav_spawn_points, position, above, below)` takes `nav_world` FIRST (spawn_point_queries.lua:265), unlike `occluded_positions_in_group(nav_world, nav_spawn_points, group, positions)`. `get_occluded_positions` filters by distance to EVERY player (max distance must be satisfied for all players), which is why RealmsWaves does its own nearest-player filtering.
- DMF hooks by class-name string are queued until the class exists (`hooks.lua` delayed hooks), so hooking `PacingManager` / `MinionSpawnManager` at load is safe.
- Aggro happens inside `spawn_network_unit`, before `spawn_minion` returns the unit, so the bypass uses a "spawning" flag (`Bypass.begin_spawn/end_spawn`) to catch the unit in `add_aggroed_minion`.

## Known trade-offs of the bypass
- Skipping `PacingManager.add_aggroed_minion` for wave units also skips `side_system:add_aggroed_minion`, so wave units are absent from the side's aggroed lists. Those lists feed music intensity (`wwise_state_group_*`) and terror-event queries (`TerrorEventQueries.num_aggroed_minions_in_level`). Effect: wave units do not raise the combat music intensity or count for scripted "N enemies aggroed" conditions. Accepted; revisit if it looks wrong in play.
- Positions use `side.valid_player_units` (includes bots). LOS is hidden from bots too, which is harmless.

## Results log
(Append dated entries: what was tested, result, fixes.)

- 2026-09-28: Audit complete, docs written.
- 2026-09-28: Implementation written (all files in `docs/05`). Static: all 14 Lua files compile under Lua 5.5 (lupa). Offline logic tests pass (34 checks): recipe parser (aliases, caps 24/breed and 60 total, errors), pool normalisation to 100 with custom slots, vote tally (change vote, wrong ballot, ties), director state machine in random and vote modes (countdown, voting window, winner fires the 2-vote option, no-vote skip, new cycle after incoming, hub does nothing), client rendering of a synced state, version-mismatch disable, and a 20,000-roll simulation within 0.3 percentage points of the configured chances. **NOT tested in the game**: spawning, position search, budget hooks, Realms RPC delivery, HUD rendering, keybinds. Test matrix above is still "not run".
- 2026-09-28 (first in-game launch, log `console-2026-09-28-22.51.21-*.log` in `%APPDATA%\Fatshark\MicrosoftStore\Darktide\console_logs`): mod loaded (`Init DMF mod 'RealmsWaves'`), all 4 hooks installed (PacingManager.add_aggroed_minion, MinionSpawnManager.num_spawned_minions / total_allocated_num_enemies / unregister_unit). 74 errors `(localize) "%": invalid option '%' to 'format'`: DMF runs every localized string through `string.format`, so a literal `%` in a localization string is an error (a lone `%` unit label, plus `100%)` in a group title and `(%)` in HUD labels). Fixed by using the word "percent". Lesson: never put a bare `%` in DMF localization text (use `%%` only in strings that are always formatted with args, like the HUD lines). The one stack traceback in that log is a game backend promise error, unrelated to the mod.
- 2026-09-28 (user feedback after testing, changes in 1.1.0): (a) HUD percentages showed `52.100000000000001%` -> now formatted with `%.1f`; (b) minimum interval 30 s -> 5 s; (c) the options-menu numeric widget showed `<unit_percent>` because that localization key was broken by the `%` bug -> the per-wave sliders were removed from the options menu anyway; (d) custom waves had options but no interface -> wave editor built; (e) panel not movable in `custom_hud` -> real-sized node. Verified offline only: `logic_test.py` 52/52, `editor_test.py` 45/45, `check_lua.py` 18 files. Still needs in-game verification (matrix rows 10-16).
- 2026-09-28: discovered the user has purged RealmsEvent and TwitchVersus from `mods\` (only empty Vortex marker folders remain). Their files are still in Vortex staging at `%APPDATA%\Vortex\warhammer40kdarktide\mods\<mod folder>\mods\<mod>\...` (e.g. `RealmsEvent 1338 1.1.0 ...\mods\RealmsEvent\scripts\mods\RealmsEvent\v2\view\`). Read them there if a future task needs them; do not restore them into `mods\`.
