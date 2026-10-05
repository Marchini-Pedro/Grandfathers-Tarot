# 05. Implementation plan and status

## Enemy appearance experiments — `feature/enemy-appearance` (2026-10-03)

- [x] Isolate the feature in its own worktree from up-to-date `main` (`6d5756d`); preserve the CI/coverage checkout.
- [x] Per-group method dropdown, ARGB sliders, numeric entry and input-colour swatch under Custom.
- [x] Recipe/preset persistence and group identity; carry selected appearance through initial and repeated spawns.
- [x] Natural stimm with existing supported actions and gameplay buffs; applied/explicit-slot visual-only stimm and private-map local outline.
- [x] Show surface/private-shader prerequisites honestly; selecting them applies no guessed effect.
- [x] Optional host-authorized Realms transport, mission tokens, bounded pending IDs, late-join snapshots, renewal and cleanup/retirement.
- [x] Update design, user guidance and reusable research references in this worktree.
- [x] Focused schema/runtime/protocol, editor and actual spawn/cleanup checks on Lua 5.5 and LuaJIT 2.1; render/inspect the real-English panel and dropdown.
- [x] Integrate committed CI work into this feature branch only; discover/instrument the appearance harness and assign measured floors to all three new modules, preserving existing thresholds.
- [x] Fetch origin, pull `main` in a separate worktree and synchronize the feature with `06c2b3a` after merged PRs #5 and #6.
- [x] Publish the enemy appearance branch as [PR #7](https://github.com/Marchini-Pedro/Grandfathers-Tarot/pull/7).
- [x] Verify both hosted runtime checks on the published PR at `0103281`; download reports matching the local counts/scores.
- [ ] In-game acceptance: visuals/LOD/equipment, natural action/buffs, tags/other mods, cleanup, host/client joins/leave/reload and performance.
- [ ] Verify a surface colour property/type/default/coverage before implementing the surface method.
- [ ] Build compatible private assets and verify isolation/restoration before implementing shader/material patching.
- [x] GitHub records PR #7 merged by `EduardoKenji` at `c7cf1da`; record the actual merge while keeping the unverified in-game checks above open.

Details and live checklist: [Enemy colour experiments](enemy-appearance.md).

- [x] Analyze the PR #9 black/near-black stimm scenario: trace native zero reset,
  verify grey recipe/flag/strength support on both VMs and document coexistence
  plus the shared tint/outline colour limitation.
- [ ] Native black/charcoal proof: compare matched controls and nonzero grey
  candidates in varied lighting/LODs; select a preset only if its stimm shape
  remains readable. No black preset or new material path is implemented by
  this analysis. [Procedure](enemy-appearance.md#black--near-black-stimm-feasibility-2026-10-03).

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
- [x] 4. The Deck screen, cooldown looks, custom card builder
  - [x] 4a. The Deck: tiles, strip, toggle, Edit, blank tile, paging, Delete in the card's screen, palette (`ui/deck.lua`, `ui/wave_editor_deck.lua`, offline only)
  - [x] 4b. Cooldown looks on the tiles (rot and renewal, the murmur returns, the vial fills, ready ping option `tarot_ping`; offline only)
  - [x] 4d. Deck polish after the user's first look (2.0.0): relative chance pips and rarity, clickable pips, right click to edit, the Edit pill, anti-aliasing copies, dimmed filled diamonds, coloured modifiers, tighter tile layout, six new suits incl. the purple Warp for the Daemonhost (offline only)
  - [x] 4c. Card builder screen ("Card face"): suit with suggestion, threat auto/override with "Threat N by the numbers", whisper, look, cooldown, live preview (`ui/wave_editor_face.lua`; offline only)
- [x] 5. Mod options (the last one, `tarot_default_cooldown`, in 2.0.0 step 5; all others were added with their steps)
- [x] 6. Per-group health and size multipliers, done as "custom mods" on the user's request (health, size, run speed, time between attacks (first called melee attack speed), gunner fire rate, shots per burst, hit mass, explosion and damage-over-time taken; `spawn/tuning.lua`, `ui/wave_editor_tune.lua`, RPC `rw_scale`). Recovered from `feature/attack-timing` and merged into `main` through PR #1 on 2026-10-03: the rename to Time between attacks, the chained-attack fix and the `/rw_anim` probe; "Animation attack speed" waits for the probe's answer. The brief's one-crusher test in the game has NOT been done: matrix rows 91-96.

### 2.1.0: the Workshop redesign (historical milestone; spec: `08-workshop-redesign.md`; recovered into `main` through PR #1)
- [x] 0. Design page, the user's answers, spec and plan (doc 08)
- [x] 1. Button family (standard, primary, danger, quiet, chip, stepper, diamond check, tabs, icon), popup buttons and frame, pixel snapping, the suit accent; titles (Cauldron, Mirror) came with it (offline only)
- [x] 2. The shelf data (Packmaster, vanguards as fodder, Dreg / Scab) and the faction word on rows and in the picker (offline only); the titles are done
- [x] 3. The tile at any scale (`blueprints.tile(node, k)`, metrics in the content; offline only); the stage plate comes with the Cauldron
- [x] 4. The Cauldron: rows, shelf, spawn block, action bar, stage with the 1.4 times card, quick face, tabs, cooldown preview (offline only)
- [x] 5. The Mirror: suit plates, threat diamonds and sum, whisper field with a live box, cooldown stepper, three look plates, Reset face, the shared stage, "In the hand" (offline only; the look plates' pictures are static)
- [x] 6. Preview tool for any screen (`tools/ui_preview.py`), tests (editor 623, logic 0 failures, entry 14, hud 179), docs (CHANGELOG, 04, 05, 06, 07, 08, README, CLAUDE.md)
- [ ] In-game verification (matrix rows from 97 in doc 06)

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
    core\protocol.lua                    Realms RPCs: rw_hello, rw_welcome, rw_state, rw_vote, rw_waves, rw_scale (sizes of units, 2.0.0)
    core\director.lua                    timer, draw/ballot, vote handling, state sync, HUD view(), debug helpers
    core\votes.lua                       tally (one vote per peer, ties random)
    catalog\events.lua                   12 standard waves (tarot names since 2.0.0) + build_pool() normalisation
    catalog\cards.lua                    2.0.0: palette, suits, threat, dots, whisper, cooldown looks, rot formulas, migration
    catalog\groups.lua                   recipe parser ("5 trappers, 5 mutants")
    spawn\positions.lua                  hidden-from-all-players candidate points near players
    spawn\execute.lua                    drip-feed spawner (2 per 0.15 s), direct spawn_minion, caps
    spawn\budget_bypass.lua              tracked-unit set + hooks that hide them from director counters
    spawn\tuning.lua                     2.0.0: custom mods of a group on spawned units (health, size, speed, time between attacks, fire rate, burst, hit mass, explosion and damage taken)
    ui\hud_element_waves.lua (+ _definitions)   synced HUD: the old text panel (legacy modes) and, in 2.0.0, The Spread
    ui\spread.lua                        2.0.0: the arithmetic of the Spread (layout, timeline, roulette, eye, icons, rot), pure Lua
    ui\wave_editor_face.lua              2.0.0: the card face screen (the card builder): suit, threat, whisper, look, cooldown, preview
    ui\wave_editor_tune.lua              2.0.0: the custom mods screen of one enemy group (the Custom button beside Mods)
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

## Recovery review (2026-10-03)
- [x] Preserve remote baseline, 25 unpublished commits and eight uncommitted files on `feature/workshop-recovery` (now merged into `main`).
- [x] Complete sorting/drag behavior, review runtime and multiplayer edge cases, run offline checks, and synchronize the feature branch (2026-10-03). See `09-recovery-review.md`.

- [x] Complete persistent sorting and drag-to-swap, cancel stale interactions, and cover them with meaningful regression/mutation checks (2026-10-03).

- [x] Review repeat CPU/memory bounds, duplicate/deferred scale delivery, failed sends, host authority and stat recompute ordering; fix and add real-path regression tests (2026-10-03).

- [x] Confirm PR #1 merged into `main` at `64f76f3` and synchronize local `main`; remote recovery branch deleted (2026-10-03).
- [x] Add player-facing README, compact the technical index, and define ongoing README maintenance in CLAUDE.md (2026-10-03).
- [ ] Complete the remaining in-game/multiplayer and actual CPU/process RAM checks listed in doc 09; merge status does not close these checks.

- [x] Prepare the reusable audit-only adversarial brief in `audits/adversarial-audit-prompt.md`, covering the user's test/performance/lifecycle/UI/Realms/reuse questions (2026-10-03).
- [x] Execute the offline adversarial audit after explicit request; [dated report](audits/2026-10-03/report.md), full inventory/test map, embedded diagnostics and L1–L8 results/limits are available.
- [x] Review the audit and receive authorization for all concrete remediation batches (2026-10-03).
- [x] F01: release both mission event subscriptions from their original manager; detect 100 obsolete generations with an owner-faithful EventManager fixture and guard captured callbacks. Native reload remains pending.
- [x] F02/F03/F05: pause freezes job/feed clocks; stop preserves living units; disable cancels work and re-enable requires host start/client resync. Real-collaborator regressions pass; live checks remain pending.
- [x] F04: cap aggregate work at 64 jobs / 8,000 entries; refuse full admissions before allocation and skip/clip repeat ticks to available room. Supported-max regression passes.
- [x] F07: reject non-finite numeric preset/card fields atomically on both runtimes; preserve finite clamps and legacy optional threat.
- [x] F06: expose direct-send peer failures to the existing bounded current-size retry; coalesce failed late-join snapshots and preserve reentrant updates. Actual Realms contract fixture passes.
- [x] Close the two surviving mutation gaps (retired tuning hooks and unload resets); add retirement/reentrancy, late-manager and partial aggregate-room regressions. All 17 selected mutations fail their intended assertions on both runtimes.
- [x] Synchronize PR #4 with the PR #3 merge at `44e536f`; retain completed audit/remediation records when resolving the three documentation conflicts. Required checks pass on both runtimes.
- [ ] Run the [live acceptance checklist](audits/2026-10-03/live-checklist.md), including verified installed revisions and eight hours / ten consecutive missions; record user in-game acceptance separately from the completed PR #4 merge.

The audit stage changed Markdown only. Approved fixes are implemented in six
batches on `feature/audit-remediation`, created from `main` at `3e6be46` and
synchronized with the audit-brief merge at `44e536f`, then merged into `main`
through PR #4 at `6d5756d`.
Public APIs/settings, protocol 2 and serialization remain compatible. See the
[remediation results](audits/2026-10-03/remediation.md) and reproducible validation.
Installation, publication and merging remain separate; game confirmation is pending.

## 2.1 batch: `feature/heresy-card-and-ui-pass` (2026-10-03, from `main` at `6d5756d`)

Ten changes the user asked for in one list. Everything below is implemented and tested offline (Lua 5.5 and LuaJIT 2.1) and committed on the branch; none is merged or played. In-game checks: `06` rows 114-121.

- [x] Adversarial spawn review: nil weakened flags, native health-write rejection and target destruction during facing are repaired with regressions.
- [x] Custom health 1:1 with the config under Havoc (`Tuning.set_exact_health`); the game's "Weakened" name kept for bosses below normal health.
- [x] The Mods and Custom pages (and every card screen) in the colours of the card's face (`Components.set_theme`).
- [x] Smaller shelf chips now that the D/S tags are gone; the freed room is a sixth enemy row in the Cauldron.
- [x] The Deck's top button renamed "Deck presets".
- [x] `/rw_test_close <wave>`: the wave in front of the player.
- [x] Fester replaced by HERESY (special colours, frame, glow, mark, banner line; `fester` stays an alias).
- [x] 100 cards (88 custom slots), the waves message trims instead of failing.
- [x] A HUD window for the last fulfilled card (own element, synced, option, Custom HUD sample).
- [x] A cooldown row on every Deck tile (`-` / `+` / number box / hover preview).
- [x] Merge `main` (PRs #5-#7) into the branch (`56062d3`), resolving one code and three documentation conflicts; `Events.is_empty_slot` keeps the draw cheap with 88 slots.
- [x] Synchronize with current `main` at `1290abc` (documentation only); preserve accurate PR #7 status.
- [x] Adversarial review of all branch changes; repair nine reproduced health/spawn/network/HUD/layout gaps, including long modifier wrapping, strengthen regressions and detect nine reverse mutations on both VMs ([review](audits/2026-10-03/heresy-review.md)).
- [x] Complete CI coverage inventory and justified source-proxy floor exceptions on both runtimes; 2,104 assertions each and all 34 module gates pass ([coverage](10-ci-and-coverage.md)).
- [x] Publish the continuation in draft [PR #8](https://github.com/Marchini-Pedro/Grandfathers-Tarot/pull/8); both first hosted runtime checks pass at `a163552`, 2,104 assertions each.
- [ ] GitHub: admin permission for EduardoKenji remains an owner task. The authenticated identity has write/push access and neither admin nor maintain; no settings were changed.
- [x] User merged PR #8 at `fe957632` on 2026-10-03. Rows 114–121 remain the native acceptance record; merge does not prove those tests ran.

## Post-PR #4 test coverage (2026-10-03)

- [x] Remove the editor harness's sibling game-source dependency; retain callback binding, nil, dynamic-method and return-value contracts in a test-only fixture.
- [x] Select Lua 5.5/LuaJIT 2.1 explicitly with a shared test runtime; suspend coverage hooks during allocation probes without weakening assertions.
- [x] Add hidden-position, explicit-test ring, native-query failure, command-input and protocol serialization/availability regressions. Six selected regressions are detected on both runtimes.
- [x] Add repository-owned CI, measured module floors and fail-closed coverage reports; verify a standalone checkout on both runtimes. See [CI and coverage](10-ci-and-coverage.md).
- [x] Publish `feature/ci-coverage` and open [PR #5](https://github.com/Marchini-Pedro/Grandfathers-Tarot/pull/5) with owner-side merge enforcement instructions; merged by the user at `03785e3`.
- [x] Verify the first hosted PR run at `fd56262`: both runtimes pass 1,837 assertions and all coverage floors; downloaded artifact scores match the local baseline.
- [x] Verify both jobs on the first `main` run at `03785e3` and synchronize local `main` after the PR #5 merge.
- [ ] Have the repository owner require `Offline verification (lua55)` and `Offline verification (luajit21)` for merges to `main` after the first hosted run.

## PR #9: card effects and compact UI (2026-10-03)

- [x] Branch from current main after confirming the PR #8 merge.
- [x] Shared compact shelf cells and complete vector repeat/shelf borders.
- [x] Compact full Last Card, independent transparency, no Draw/Last modifier labels.
- [x] Share Card wording and per-card share glyph option.
- [x] Native timed Blackout with overlap, streaming and state restoration.
- [x] Depth-tested ordinary outlines, independent outline/tint, protection toggle;
  disable unsupported material methods with actual prerequisites.
- [x] Prayer/Miracle/Grace palettes, sigils and effect panel; six manual pips;
  Consecrate standard slots with confirmation and preset Undo.
- [x] All nine requested beneficial effects; native restrictions, occupied slots,
  owning-peer ability grants and no enemy spawning on beneficial faces.
- [x] Content-ranked/searchable completion sound library and optional SimpleAudio.
- [x] Targeted schema, native-contract, lifecycle, network, HUD and editor regressions.
- [x] Final Lua 5.5/LuaJIT suites: 2,321 assertions each, all 38 module gates,
  unchanged existing floors and inspected real-widget previews.
- [x] Publish [draft PR #9](https://github.com/Marchini-Pedro/Grandfathers-Tarot/pull/9); both jobs on the
  [first hosted branch run](https://github.com/Marchini-Pedro/Grandfathers-Tarot/actions/runs/37170104362) pass at `9f9082b`.
  Downloaded artifacts match local counts, scores and module gates.
- [x] Give hosted instrumented harnesses the same 280-second allowance used
  locally; preserve the ten-minute job limit and every coverage/assertion gate.
- [ ] Native acceptance of [the new game checklist](12-card-effects-and-ui.md).
  Keep the feature branch open until the user's confirmation.

## Cauldron redesign (`feature/cauldron-redesign`, 2026-10-04)

Spec and checks: [13-cauldron-redesign.md](13-cauldron-redesign.md).

- [x] Heresy crimson palette, heartbeat glow and frame (HUD, Deck, stage) and blood drops (HUD).
- [x] Faith, the fourth beneficial suit (palette, mark, whisper, description, Consecrate).
- [x] Threat 6 named Despair or Apotheosis with its own edge, and a shine (HUD, Deck, stage).
- [x] One cooldown look (rot and renewal) everywhere; the Mirror shows it, nothing to choose.
- [x] Murmur: threat 5 and 6 whispers come back letter by letter when drawn.
- [x] Hostile / beneficial suit switch on the quick face and the Mirror (replaces Auto | By hand).
- [x] Compact row steppers and chips.
- [x] Beneficial rows and a four-group effect shelf; Guidance renamed Buffs, Prayer renamed Items, Game Effects added.
- [x] Raise the fallen and Refill ammunition (host, native helpers); Recharge Med Station disabled for now.
- [x] Completion sound: Preview per row, Search button, two sounds in a row, a volume each (experimental).
- [x] Tests for all of the above on both runtimes; real-widget previews inspected.
- [x] Second to fourth rounds (design-page shelves and card text, Deck search, Last Card; sound fix, outline line of sight, 30 minute
  cooldown; voice lines in the sound list) and their tests, 2026-10-04.
- [x] Fifth round (2026-10-04): movable see-through search box, the card sound at the draw holding the wave, the stimm buffs and
  items, Raise the fallen 1+1, grenades, Ammo Crates, Nightmare replacing Dusk (once per game), Warp's effect; tests.
- [x] Sixth round (2026-10-04): the rehook warning fixed, sound-first /rw_test, /rw_drawtest and /rw_fulltest, Nightmare's fog on
  the card and its dread on the screen (option), the Draw HUD below boss bars (option); tests.
- [x] Eighth round (2026-10-04): hogtied rescue with teleport, Instant rescue, Damage dealt, boss-bar opacity and swap, fog slider.
- [x] Ninth round (2026-10-04): client outlines and grants, the teleport after the rescue, Nightmare darkness 0 to 100 and the grey
  world, the boss health network cap, chat-safe texts, On Fire damage; tests.
- [x] Tenth round (2026-10-05): boss health without a limit in bars with "xN", the On Fire look kept on, On Fire damage 35 by
  default, the Deck's scroll and the last screen remembered; tests.
- [ ] Enemy shadow (the Daemonhost fog particle on other enemies): found, waiting for the user's decision.
- [ ] Game acceptance of the [checklist](13-cauldron-redesign.md#in-game-checks-before-merge); merge only after the user confirms.
