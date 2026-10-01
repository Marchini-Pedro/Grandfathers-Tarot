# 05. Implementation plan and status

Update the checkboxes as work proceeds. Original approved plan copy: `C:\Users\ayko4\.claude\plans\pasted-content-id-fdf1-i-have-valiant-parasol.md` (may not persist; this file is the durable one).

## Checklist
- [x] 1. Docs (`docs\*`) and `CLAUDE.md` written from the research (2026-09-28)
- [x] 1b. Memory pointer saved (project memory -> `docs\README.md`)
- [x] 2. Scaffold: `RealmsWaves.mod`, entry, localization, `mod_load_order.txt` line appended (after `Realms`)
- [x] 3. `core/protocol.lua`, `core/director.lua` (handshake folded into director: `on_hello`/`on_welcome`), debug commands
- [x] 4. `spawn/positions.lua`, `spawn/execute.lua`, `spawn/budget_bypass.lua` written
- [x] 5. `catalog/events.lua`, `catalog/groups.lua`, percent normalisation, options (`RealmsWaves_data.lua`)
- [x] 6. `core/votes.lua` + keybind voting
- [x] 7. `ui/hud_element_waves.lua` (+ definitions) + state sync
- [x] 8a. Static checks: all files compile; offline logic tests pass (see `06`)
- [ ] 8b. **In-game verification (not done):** solo host, then two-instance Realms LAN. Follow the matrix in `06` and log results there.

### Iteration 1.1.0 (after the first in-game test) — see `CHANGELOG.md`
- [x] Percent formatting on the HUD (`%.1f`, trimmed)
- [x] Minimum interval 5 s (options range, director no longer pads to vote_duration + 5, vote window capped)
- [x] Data layer for editable waves: `catalog/events.lua` (`Events.get/set_def/reset/keys/build_pool`), `catalog/groups.lua` (parse with `a|b`, `to_recipe`, `describe_part`, `summary`, `breed_list`, `display_name`)
- [x] Wave editor view: `ui/wave_editor_{components,definitions,blueprints,view}.lua`, registered in `RealmsWaves.lua`, keybind `open_editor_bind` (default F6), `/rw_editor`
- [x] `/rw_custom` rewritten on the new data layer; `wave_def_/on_/pct_/cd_` settings; DMF wave sliders removed
- [x] HUD panel reshaped for `custom_hud` (real-size node, sample in edit mode); `hud_x/hud_y` removed
- [x] Local git repo + `tools/` test scripts; `CLAUDE.md` docs/commit rules
- [ ] In-game verification of all of the above (editor opening and every screen, popup input, HUD dragging in custom_hud, 5 s waves)

### Iteration 1.1.1 - 1.2.0 (see `CHANGELOG.md`)
- [x] 1.1.1 stimmed-minions gap fixed in the budget bypass (re-send `minion_aggroed`)
- [x] 1.1.2 editor crash fixed (`_create_widgets` shadowing); test stub mirrors real BaseView flow
- [x] 1.2.0 modifiers: `Groups.MODIFIERS` + `[a+b]` recipe syntax, `Execute.apply_modifiers`, Mods button + modifier screen in the editor, offline tests (62 logic incl. spawner, 60 editor)
- [ ] In-game verification: editor opens (crash fix), modifier screen, Garden/Enraged on 3 crushers in a normal mission and a Havoc mission, Toughened Skin skipped in a normal mission (console shows one warning), stimmed minions in a Havoc order

### Iteration 1.2.1 - 1.3.0
- [x] 1.2.1 editor row hotspots fixed (visibility_function receives hotspot content), row hover highlight
- [x] 1.3.0 spread radius (`Positions.spread`, `sp_<key>`), repeating waves (`@N`, `re_/rf_<key>`, `Execute.run_repeats`), editor steppers and per-row repeat stepper, tests (logic 111, editor 89)
- [ ] In-game verification: hover/click on rows and detail (1.2.1); spread looks right and units are not in view; `5 crushers@2` with repeat every 10 for 35 s behaves as designed

### Iteration 1.3.1 - 1.4.0
- [x] 1.3.1 Twins (2 breeds), Packmaster rename, spread max 100 m
- [x] 1.4.0 type multipliers (`mult_normal/boss/special`), picker search, "Weight" wording, limits 500 / 1000, tests (147 logic, 106 editor)
- [ ] In-game verification (rows 27-31 in doc 06)

### Iteration 1.5.x - 1.6.0
- [x] 1.5.4 Psykhanium `/rw_test` ring fallback + visible failure reasons; picker auto-search; stay/back toggle
- [x] 1.5.5 twin shield (`optional_init_toughness`), 1.5.6 Rotten Armor modifier, 1.5.7 `FixedFrame` require fix, 1.5.8 description length
- [x] 1.6.0 presets: 5 named slots (`preset_1..5`, `preset_undo`), text import/export (`catalog/presets.lua`, format `RW1|...|check`), Presets screens in the wave editor, tests (logic + 30 editor checks)
- [ ] In-game verification (rows 42-48 in doc 06)

### 2.0.0: The Grandfather's Tarot (spec: the pasted brief of 2026-10-01, reference page https://claude.ai/artifact/3MAB8UZa1yPtPgkYt7Rbuu)
- [x] 0. UI primitive feasibility (report in doc 06, results log 2026-10-01)
- [x] 1. Card data model: `catalog/cards.lua`, `su_/th_/wh_/cl_` settings, tarot names for the standard waves, one-time rename, sharing format
- [x] 2. Draw director (hand, winner, cooldown exclusion, sync, legacy modes kept): `core/director.lua`, protocol 2 / 2.0.0, options `mode` (default tarot), `tarot_cards`, `tarot_seconds`
- [x] 3. The Spread HUD: `ui/spread.lua`, widgets, element, the `The Spread (your screen)` options, `tools/hud_test.py` (offline only; the shapes are unseen)
- [ ] 4. The Deck screen, cooldown looks, custom card builder
  - [x] 4a. The Deck: tiles, strip, toggle, Edit, blank tile, paging, Delete in the card's screen, palette (`ui/deck.lua`, `ui/wave_editor_deck.lua`, offline only)
  - [x] 4b. Cooldown looks on the tiles (rot and renewal, the murmur returns, the vial fills, ready ping option `tarot_ping`; offline only)
  - [ ] 4c. Card builder screen: suit with suggestion, threat auto/override with "Threat N by the numbers", whisper, look
- [ ] 5. Mod options
- [ ] 6. Optional: per-group health and size multipliers

Deviations from the original plan (all deliberate):
- No separate `handshake.lua`: hello/welcome live in `core/director.lua` (the handshake is just a version check).
- `rw_state` is ONE JSON argument, and host -> clients uses `"others"` (Realms docs' own example) so there is no loopback to filter.
- Votes are accepted during the whole countdown, not only the final window; the last `vote_duration` seconds are the highlighted "voting" phase.
- Ballot candidates are drawn at cycle start and shown during the countdown, so the HUD shows "next possible waves" from the beginning.
- DMF has no text-input widget, so custom recipes are set with `/rw_custom <slot> <recipe>`; each slot's chance is a numeric option (0 = disabled).
- Wave content and spawn locations are new data/code, not lifted wholesale from the originals (see "Reuse" below for what was actually reused).

## Files (as built)
```
mods\RealmsWaves\
  RealmsWaves.mod                        load_after = {"Realms"}
  CLAUDE.md
  docs\                                  (this folder)
  scripts\mods\RealmsWaves\   (catalog\presets.lua added in 1.6.0: preset slots + text format)
    RealmsWaves.lua                      entry: module loading, hooks, HUD registration, keybind fns, /rw_* commands
    RealmsWaves_data.lua                 options (built from catalog/events)
    RealmsWaves_localization.lua         strings (+ per-event titles generated from the catalog)
    core\protocol.lua                    Realms RPCs: rw_hello, rw_welcome, rw_state, rw_vote
    core\director.lua                    timer, draw/ballot, vote handling, state sync, HUD view(), debug helpers
    core\votes.lua                       tally (one vote per peer, ties random)
    catalog\events.lua                   12 standard waves (tarot names since 2.0.0) + build_pool() normalisation
    catalog\cards.lua                    2.0.0: palette, suits, threat, dots, whisper, cooldown looks, rot formulas, migration
    catalog\groups.lua                   recipe parser ("5 trappers, 5 mutants")
    spawn\positions.lua                  hidden-from-all-players candidate points near players
    spawn\execute.lua                    drip-feed spawner (2 per 0.15 s), direct spawn_minion, caps
    spawn\budget_bypass.lua              tracked-unit set + hooks that hide them from director counters
    ui\hud_element_waves.lua (+ _definitions)   synced HUD: the old text panel (legacy modes) and, in 2.0.0, The Spread
    ui\spread.lua                        2.0.0: the arithmetic of the Spread (layout, timeline, roulette, eye, icons, rot), pure Lua
    ui\deck.lua                          2.0.0: the arithmetic of the Deck (grid, paging, pips, strip, state, composition lines), pure Lua
    ui\wave_editor_deck.lua              2.0.0: the Deck screen's methods (tiles, strip, hover, toggle, edit, new card)
```
`RealmsWaves` was appended to `mods\mod_load_order.txt` (last line). The originals (TwitchVersus, RealmsEvent) were NOT disabled: the user should disable them while using RealmsWaves.

Test tooling (outside the repo, scratchpad only): Python `lupa` (Lua 5.5, not LuaJIT) installed with `pip --target` into the session scratchpad; `check_lua.py` compiles every file, `logic_test.py` runs the stubbed logic tests; `editor_test.py`, `entry_test.py` and (2.0.0) `hud_test.py` drive the real view, entry script and HUD with stubbed engine classes (all in `tools\`, run all five after every change). They are easy to recreate; Lua 5.5 is stricter than LuaJIT (e.g. assigning to a `for` variable), which is a useful extra check.

## Reuse (what was actually reused vs rewritten)
- Reused as pattern/code: RealmsEvent's protocol rules (dot-calls, argument validation, availability guard, `cjson`, `mod:get("debug")`), its "first objective started" trigger, `is_server()` authority check, `mod.update` signature handling, `SpawnPointQueries.occluded_positions_in_group` path, spawn param table (`optional_aggro_state`, `optional_target_unit`, rotation from the target unit); TwitchVersus's breed alias table and recipe rules, drip-feed rate, HUD element structure, NOT_A_MISSION hub check, dropdown/keybind/group option shapes.
- Rewritten: director/scheduler, protocol (4 RPCs), position search (all players, distance to nearest, no visible fallback), budget bypass (new), HUD panel.

## Original reuse map (planning-time)
| Need | Source (relative to `mods\`) |
|---|---|
| Realms RPC layer, host guard, loopback drop, peer join/leave | `RealmsEvent\scripts\mods\RealmsEvent\v2\core\protocol.lua`; `v2\util\shared.lua:111`; `v2\core\runtime.lua:177-215` |
| Version handshake | `RealmsEvent\...\v2\core\consistency.lua` (keep hello/welcome + `disable()`; drop event-key intersection) |
| Recipe parser + 20 slots | `TwitchVersus\scripts\mods\TwitchVersus\catalog\groups.lua` (`Groups.parse` :332) |
| Wave tiers, `group_mix` shape | `TwitchVersus\...\catalog\events.lua` (`wave()` :131) |
| Spawn queue, drip-feed, breed replacement | `TwitchVersus\...\spawn\execute.lua` (`spawn_at` :362, `resolve_breed` :314, `drain_job` :395) |
| Position escalation | `TwitchVersus\...\spawn\positions.lua` (`Positions.escalate` :1032, anchor :254-295); strip probe tooling; remove the `unoccluded` last resort |
| 5 spawn events | `RealmsEvent\...\v2\events\{boss_ambush,bomber_frenzy,hound_frenzy,grenade_legion,sniper_elite}.lua` -> catalog data |
| Weighted roulette | `RealmsEvent\...\v2\core\scheduler.lua:149` |
| Flat-string settings persistence | `RealmsEvent\...\v2\core\event_pool.lua:102-186` |
| HUD element registration and drawing | `TwitchVersus.lua:1702`; `TwitchVersus\...\ui\hud_element_banner*.lua` |

Strip out: all of `transport/`, `logic/vote.lua`, Twitch options groups, `tv_*` commands, non-spawn RealmsEvent events, `Rewards.refund` paths.

## Protocol and options
See `04-design-and-rationale.md`.

## Debug commands (planned)
`/rw_test <event>` spawn now; `/rw_status` state + counters (raw vs adjusted `total_allocated_num_enemies`, tracked count, aggroed challenge rating); `/rw_roll <n>` n-roll simulation of the weights; `/rw_vote <n>` cast vote from console.
