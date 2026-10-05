# Changelog

## 2026-10-05 - Cooldown beside the chance, a clickable card preview, Deck search on typing (polishing)
- The Workshop has the card's cooldown stepper beside its chance; the card on the stage takes clicks on its chance pips and its cooldown minus, plus and value.
- Typing on the Deck opens its search; a dragged search box (Deck, enemy picker) keeps its place for the game session.
- A sound preview the game cannot start says so in chat (the stimm syringe sounds are loaded only with their item).
- The skin effects are renamed Burning effect, Soulblaze debuff effect (Warp), Bruised effect (gray purple).
- Editor, effects, entry and appearance tests pass; the full runners were not run.
- The Mutant's run while carrying a grabbed player follows its run speed too (`_update_grabbed_target`, the third direct-velocity step).

## 2026-10-05 - The Mutant's charge follows its run speed (feature/enemy-shadow)
- A group's run speed now also scales the Mutant's charge (its direct-velocity phases; the navigating phase already was).
- Dark skin seen in game: the textures load, but lowering A only fades the effect out; none of the looks gets close to dark.
- Lua suites not run (the user's choice).

## 2026-10-05 - Dark skin experiments, draw buttons on the Deck (feature/enemy-shadow)
- Three experimental appearance methods, "Dark skin: burnt / warp / bruised": the game's ailment skin looks held still on the enemy; A picks the moment of the effect shown (to find the darkest). Textures load as packages first.
- The Deck has four buttons: add / remove the beneficial cards, add / remove the enemy cards from the draw.
- Lua suites not run (the user's choice); not yet tested in game.

## 2026-10-05 - Golden health, Stop all sound previews; shadow fog removed (feature/enemy-shadow)
- While the team has an Instant rescue charge, a player with more than one wound left has golden health bars (the game's overshield toughness colour), on every player's HUD (the charge count is sent with the effects state).
- The card sound screen has a "Stop all sound previews" button (a card's real sound at a draw is not stopped).
- The shadow fog is removed: tested in game, its performance cost was too high.
- Lua suites not run (the user's choice); not yet tested in game.
## 2026-10-05 - Twin voice lines and the stimm use sound (feature/twin-voice-lines)
- Completion sounds: the twins' mission and darkness voice lines (122) and `play_syringe_stab_self` (the stimm use sound) plus `play_syringe_heal_husk_charge_cancel`; 9,558 sounds in all.
- Not tested: the Lua runners were skipped at the user's request; not yet heard in game.

## 2026-10-05 - The Grandfather's Tarot (feature/cauldron-redesign)
- The mod is renamed The Grandfather's Tarot (folders, files, DMF id); commands are /gt_...; the Cauldron is the Workshop.
- Saved decks, presets and options are copied once from the old RealmsWaves settings.
- The mod menu title and section headers are in the Nurgle palette.

## 2026-10-05 - Boss health in bars, On Fire that lasts, the editor's memory (feature/cauldron-redesign)
- No boss health limit: health above what the network carries is sent divided; boss bars show it in bars with "xN".
- On Fire enemies keep their burning look while alive; On Fire damage is 35 percent by default.
- The Deck keeps its scroll; the editor key reopens the screen that was left.
- Both runners pass every gate (Lua 5.5 82.20% / LuaJIT 2.1 79.13%). Not yet tested in game.

## 2026-10-04 - Clients, Nightmare darkness, teleport, boss health, imports, On Fire damage (feature/cauldron-redesign)
- Clients run the effects update (Specialist outlines) and apply combat ability grants to their own player, with a log line.
- Raise the fallen teleports the rescued player once they stand.
- Nightmare darkness: 30 = the old look, 100 = almost black (a saved 100 becomes 30 once); every player sees a grey world while it lasts.
- A custom boss health is capped at what the network carries (clients showed 0).
- Card and preset texts survive chat apps (empty fields as ".", escapes); older texts still import.
- On Fire damage (0 to 300 percent) beside the modifier on the Mods screen.
- The 2.x changelog entries moved to changelog/2.x.md (100 KB rule).
- Both runners pass every gate (Lua 5.5 82.28% / LuaJIT 2.1 79.17%). Not yet tested in game.

## 2026-10-04 - Rescues, Damage dealt, boss-bar options (feature/cauldron-redesign)
- Raise the fallen rescues one hogtied player (now working) and brings them to the nearest standing player; the downed revive is gone. New Instant rescue.
- Custom mods: Damage dealt (snipers and any enemy).
- Options: Nightmare card darkness; Draw HUD opacity while a boss is up; boss bars below the Draw HUD.
- Both runners pass every gate (Lua 5.5 82.32% / LuaJIT 2.1 79.19%). Not yet tested in game.

## 2026-10-04 - Restart crash and the idle Packmaster (feature/cauldron-redesign)
- Fixed a crash on Restart and an error on a despawn key: a summoner destroyed mid-summon no longer summons.
- A wave's Packmaster no longer stands idle: no patrol, aggroed hounds, re-aggroed when it loses its target.
- Both runners pass every gate (Lua 5.5 82.32% / LuaJIT 2.1 79.17%). Not yet tested in game.

## 2026-10-04 - Test commands, rehook warning, Nightmare's fog and dread, Draw HUD below boss bars (feature/cauldron-redesign)
- Fixed "Attempting to rehook active hook [start_shooting]" at game start (each loaded table is hooked once).
- /rw_test and /rw_test_close play the card's sound first; new /rw_drawtest (a staged draw, HUD only) and /rw_fulltest (with sound and wave).
- Nightmare: a black fog comes and goes over its card everywhere; when drawn, a see-through black fog darkens the whole screen (option "Nightmare's dread on screen").
- The Draw HUD slides below the boss health bars while a boss is up (option "Move the Draw HUD below boss bars").
- Tests for all of it; both runners pass every gate (Lua 5.5 82.36% / LuaJIT 2.1 79.20%). Not yet tested in game.

## 2026-10-04 - Card sound at the draw, new beneficial effects, Nightmare, Warp's effect (feature/cauldron-redesign)
- The card's sound plays for everyone the moment the card is drawn and its wave spawns when the sound ends (at most 20 s); the completion sound is gone.
- The search box can be dragged and is see-through over the list it filters.
- Raise the fallen raises one downed and frees one hogtied player; Yellow/Blue/Red Stimm buffs and items; Replenish grenades; Ammo Crates.
- Nightmare replaces Dusk after Heresy: black, a breathing darkness, a flickering dying light, black ink; once per game. Warp's glow pulses and motes rise from it.
- Tests for all of it (two defects found and fixed); both runners pass every gate (Lua 5.5 82.44% / LuaJIT 2.1 79.26%). Not yet tested in game.

## 2026-10-04 - Cauldron redesign: tests brought up to date (feature/cauldron-redesign)
- Logic, effects, editor, HUD and appearance tests follow the redesign rounds (30 minute cooldown, native and voice line audio, card lines and dots, column shelves, Deck search, the hand-card Last Card, 13 line-of-sight checks); fixes found on the way: a tolerant local player lookup, a trimmed Deck search, the health station ranking, the dead faction tint removed.
- Both runners pass every gate (Lua 5.5 82.42% / LuaJIT 2.1 79.21%). Doc 06's results log moved to docs/06-results-log.md (100 KB rule).

## 2026-10-04 - Sound list: voice lines in, weapon and impact sounds out (feature/cauldron-redesign)
- The completion sound list drops weapon, attack and impact sounds and adds 2,312 enemy and 5,458 player voice lines, played through the game's 2D player voice route. Lua suites not run (user's choice); not yet tested in game.

## 2026-10-04 - Cauldron redesign, third round: sound, outline line of sight, cooldown (feature/cauldron-redesign)
- Sound: card sounds and their previews play on the local player in the level's sound world (they played at the world's origin, out of hearing).
- Enemy colour outline: hidden behind walls unless the enemy is in view of the camera or tagged by a player.
- Longest card cooldown defaults to 30 minutes (a saved lower value is raised once); the Face screen's cooldown stepper fits "30:00"; stepper edges are one unit.
- Lua suites not run or updated (user's choice). Not yet tested in game.

## 2026-10-04 - Cauldron redesign, second round: design-page shelves, card text, Deck search, Last Card (feature/cauldron-redesign)
- Editor: the enemy and effect shelves are four columns with chips as wide as their labels and one unit outlines (no faction tint); effect chips show a lit diamond when on the card. Beneficial card text reads `95% Party health` with the amount in bone and the name in its group's colour, and its dots are its groups' colours; effect rows lead with the amount; the stage line counts effects. The quick face is two rows of six.
- Deck: Search cards replaces Consecrate 12 cards (filters by name, suit, enemy or effect as you type).
- HUD: the Last Card window is rebuilt as the design page's hand card (accent bar, name and mark, diamonds and dots, whisper inside).
- Lua suites deliberately not run or updated this round (user's choice); the out-of-date expectations are listed in docs/13. Not yet tested in game.

## 2026-10-04 - Cauldron redesign: Faith, crimson Heresy, one cooldown look, beneficial shelf, two sounds (feature/cauldron-redesign)
- Catalog: Heresy becomes crimson (accent `#D42A3A`, darker card and frame, a blood colour); Faith, the Order of the Sacred Rose, is the fourth beneficial suit; level 6 is named Despair or Apotheosis with its own edge; every card rots and renews; threat 5 and 6 murmur. Effects are grouped Healing, Buffs, Items and Game Effects; Raise the fallen and Refill ammunition are new host effects; Recharge Med Station is disabled for now.
- Audio: a card holds up to two sounds with a volume each (old one-sound texts unchanged); the second follows the first; volume below 100 is an experiment.
- HUD: Heresy's glow and frame beat like a heart and blood runs from it; the sixth diamond shines (dark for Despair, light for Apotheosis); the drawn card's whisper murmurs at threat 5 and 6. The Deck and the stage card share the heartbeat and the shine.
- Editor: the hostile / beneficial suit switch replaces Auto | By hand; compact row steppers and chips; the beneficial Cauldron has effect rows and a four-group shelf; the Mirror shows one look; the sound screen has Preview, Search, two slots and volume sliders.
- Removed the dead code of the removed choices (murmur/vial looks, Automatic for this suit, Auto | By hand).
- Full runners pass 2,382 assertions each and every module gate (Lua 5.5 82.34% / LuaJIT 2.1 79.15%); docs 13 (new), 05, 06, 07, README. Not yet tested in game.

## 2026-10-03 - Analyze black and near-black enemy stimm (PR #9 follow-up)
- Trace native zero reset and verify nonzero greys, recipes, flags and strength on both Lua runtimes. Actual black rendering and the darkest readable grey remain unverified.
- Document a matched-control charcoal experiment, reuse of existing methods, tint ownership and the shared outline colour limitation. Update design/plan/results/learnings and current limits; no production option or shader asset is added.
- Full offline runners pass 2,321 assertions each and every coverage gate (Lua 5.5 82.37% / LuaJIT 2.1 79.13%); documentation sizes and new guide links pass. Native rendering remains pending.

## 2026-10-03 - Confirm corrected PR #9 checks
- Both corrected hosted branch and [PR runs](https://github.com/Marchini-Pedro/Grandfathers-Tarot/actions/runs/37170808353) at `7b74e39` pass with the 280-second harness allowance. Downloaded branch artifacts match 2,321 assertions each, all 38 module gates and Lua 5.5 82.37% / LuaJIT 2.1 79.13%.
- Record the resolved CI timeout; production Lua, tests and floors are unchanged. The PR remains a draft pending native acceptance.

## 2026-10-03 - Align hosted verification timeout with local runs (PR #9)
- The first branch run passes, but the parallel PR run times out in Lua 5.5 logic at 120 seconds on a slower runner. Keep missing coverage fail-closed and distinguish termination from a behavior assertion failure.
- CI and documented contributor commands explicitly allow 280 seconds per harness, matching the passing local invocation. Keep the ten-minute job limit, every assertion and all coverage floors; production Lua is unchanged.

## 2026-10-03 - Publish draft PR #9 and confirm hosted verification
- Push the four coherent implementation/verification commits and open [draft PR #9](https://github.com/Marchini-Pedro/Grandfathers-Tarot/pull/9). GitHub reports no merge conflicts.
- Both jobs on the [first hosted branch run](https://github.com/Marchini-Pedro/Grandfathers-Tarot/actions/runs/37170104362) at `9f9082b` pass; downloaded artifacts match local module scores, all gates and 2,321 assertions each (Lua 5.5 82.37% / LuaJIT 2.1 79.13%).
- Update current publication status and preserve the native acceptance checklist. Documentation only; no installed mod changes, repository settings or main merge.

## 2026-10-03 - Verify the complete card-effects branch (PR #9)
- Both final runners pass 2,321 assertions, 39 Lua compilation inputs and all 38 source-line gates: Lua 5.5 82.37% / LuaJIT 2.1 79.13%. No existing coverage floor was lowered; inventory all four new modules.
- Add native-effect lifecycle, authority, late-join, snapshot ordering, cancellation, audio, recipe and real-editor regression checks. Keep HUD allocation checks and inspect actual-widget previews, including the corrected appearance overlap.
- Update README/design/plan/results/learnings, method/feature guides, coverage tables and the superseded PR #8 hand-off. Native game and multiplayer acceptance remain pending; installed mods are unchanged.

## 2026-10-03 - Compact and theme the card editor and HUD (PR #9)
- Normalize all shelf cells at the shared sizing rule and draw complete foreground shelf/repeat borders. Share HERESY and beneficial button palettes; fix the stage ring's ARGB/RGB mix and compact the 15-face controls.
- Last Card becomes a compact full face with sigil, name, flavor and pips, an independent transparency slider and no large outer panel. Draw/Last Card omit modifier labels; level 6 uses DESPAIR's near-black/pale edge treatment.
- Rename Share Card and add tiny toggleable card sigils. Replace beneficial enemy controls with effects, add ranked sound search, and allow six manual pips plus confirmed Consecrate/Undo for the standard slots. Inspect real-widget previews and retain HUD allocation checks.

## 2026-10-03 - Add beneficial effects, Blackout and completion audio (PR #9)
- Prayer, Miracle and Grace reuse the tarot catalog and mask enemy recipes in catalog reads, pooling and execution. Add healing/corruption, items, Med Station recharge, combat ability grants, guidance and timed Blue Stimm, plus hostile Blackout.
- Native APIs retain their restrictions; bounded ownership restores streamed lighting states, buffs and outlines on expiry/cancel/reset. Host-authenticated revision/time snapshots deduplicate grants, audio and temporary reveal state.
- Extend sealed shared-card text only when effects/audio are present; legacy formats remain readable. Rank/search 2,685 native event names; use optional SimpleAudio or native Wwise and wait for queues, living units and timed effects before sounding completion.

## 2026-10-03 - Combine enemy outlines with protected tints (PR #9)
- Ordinary outlines use the depth-tested native layer; manual tags retain through-wall precedence. Independent outline and tint protection flags survive recipes, peer validation, saving/reopening and removal packets.
- Share native material-effect callbacks, retain buff/stat behavior, and disable unavailable surface/shader methods with their actual prerequisites. Place the new switches below the explanation and above Back.
- Extend native-hook, recipe, cleanup and real-editor regressions; inspect the revised appearance PNG. Native colours, tag precedence and other-mod interaction remain game checks.

## 2026-10-03 - Publish the reviewed Heresy continuation
- Push the completed continuation and open draft [PR #8](https://github.com/Marchini-Pedro/Grandfathers-Tarot/pull/8) against main as requested. GitHub reports no merge conflicts; the branch remains unmerged pending game acceptance.
- First hosted PR run at `a163552` passes both runtimes: 2,104 assertions each, all coverage gates and Lua 5.5 81.97% / LuaJIT 2.1 78.75%. Downloaded reports confirm the counts/scores. Update current README/plan/hand-off status and preserve native checks.

## 2026-10-03 - Complete dual-runtime coverage and continuation hand-off
- Inventory both new HUD modules and document the measured source-proxy floor exceptions for Face/editor definitions. Preserve the overall floor and all other existing floors.
- Both complete runners pass 2,104 assertions, 34 Lua compile inputs and every coverage gate: Lua 5.5 81.97% / LuaJIT 2.1 78.75%. Nine reverse mutations are detected on both runtimes (18/18).
- Update the current hand-off, coverage table and results log; native acceptance remains pending and the feature stays unmerged.

## 2026-10-03 - Reserve wrapped modifier space in the last-card window
- Long modifier lists receive up to eight lines using the existing wrap helper with a conservative uppercase width. The panel grows with its content inside a 320-unit node; short cards keep their compact panel. Existing name wrapping retains its three-line default.
- A valid 96-byte modifier fixture reproduces the old one-line overflow. The ninth reverse mutation detects the regression on both VMs; a real-widget preview with English caption and substituted Windows fonts was inspected. Native font metrics remain an in-game check.

## 2026-10-03 - Repair pooled decks and last-card/UI lifecycle
- Count JSON escaping against Realms' 96 KiB envelope, keep 1 KiB of envelope headroom, and send the largest fitting prefix of enabled cards. An unshareable first card sends an empty sealed preset to clear stale host pools.
- Stop clears the last card on host and clients, including old off snapshots carrying `lc`. Failed HUD refresh hides partial content and recovers on the next good card.
- Three-line tile names get one composition line before modifiers; one/two-line names keep four/three. Cache pointer direction separately from clamped cooldown previews: a stationary limit hover repaints zero times over 100 frames instead of 100.
- [Branch review](audits/2026-10-03/heresy-review.md) records eight confirmed findings, reproductions, strengthened fixtures, sixteen detected reverse mutations and native acceptance limits. No installed mod changes.

## 2026-10-03 - Correct exact health and contain vanished spawn targets
- Match the game's nil weakened flag for initially normal bosses and refresh it after exact custom health. Commit local health only after the replicated field write succeeds.
- Protect facing evaluation and the native spawn together so target destruction cannot leave the budget bypass active. Realistic nil/native-failure fixtures reproduce these defects; focused checks and all eight reverse mutations detect the intended behavior failures on both VMs. Offline only.

## 2026-10-03 - Synchronize the Heresy branch with current main
- Merge main at `1290abc`; preserve the branch features and the accurate merged status of enemy appearance PR #7. Resolve additive README/changelog conflicts. Existing audit fixes remain unstaged. Both baseline behavior suites passed; their coverage failures are recorded for remediation.

## 2026-10-03 - Merge `main` (PRs #5, #6, #7) into `feature/heresy-card-and-ui-pass` (`56062d3`)
- One code conflict (`spawn/execute.lua`: `spawn_one` takes both `appearance` from PR #7 and `face_target` from `/rw_test_close`) and three additive documentation conflicts; the old README bullet about host-local "Weakened" naming is replaced by the exact-health bullet.
- PR #5's entry test treated slot 21 as the first invalid custom slot; it now uses `CUSTOM_SLOTS + 1` (89) and checks slot 88. The last-card window's allocation probe suspends the coverage line hook like `growth()` does.
- `Events.is_empty_slot` (two settings) lets the draw (`build_pool`) and the fixed timers (`timed_waves`) skip the empty custom slots instead of reading ~25 settings each, and the slot key strings are built once: with 88 slots the draw, the once-a-second cooldown map and the timers walked all of them. Same results; `logic_test` under the CI runner's coverage hook: 245 s before, 77 s after (main alone: 81 s; the runner's default timeout is 120 s).
- Open, written in [11-handoff-2026-10-03.md](11-handoff-2026-10-03.md): the coverage policy needs floors for the two new HUD files and `ui/wave_editor_face.lua` is 0.02 percent under its floor; the LuaJIT run of the runner has not been done since the merge.

## 2026-10-03 - Every card shows its cooldown and changes it in the Deck (`341093e`, branch `feature/heresy-card-and-ui-pass`)
- Each Deck tile has a cooldown row under the chance pips: `[-] COOLDOWN 2:30 [+]` in the card's own colours. A click takes 30 s (shortest 30 s, longest the "Longest cooldown" option), the value opens the number box, the pointer on a plate previews the new value, a right click opens the card, a plate at its limit is dimmed. Cards with a fixed timer say EVERY and have no plates; the stage card shows the value without plates. The Mirror keeps its stepper and shares `Deck.cooldown_after`.
- To make room the lower part of the tile moved up 18 units and the composition lost one line (four lines for a one-line name, three for two, two for three). Offline only: layout tests follow the new numbers; hover/click behaviour is in `06` row 121.

## 2026-10-03 - A HUD window shows the last fulfilled card (`06b0112`, `37b4d59`)
- New HUD element `HudElementRealmsWavesLast` (own node, so Custom HUD moves it separately; default right of the Spread): "LAST CARD", how long ago, the card as the Spread draws it, its whisper and modifiers. It stays until the next card goes out. Option "Last card" (on by default); a sample shows while Custom HUD is edited.
- The director remembers the card whose wave really started (tarot pick, random wave, voted wave; not `/rw_test`, not fixed timers) and syncs it (`lc`, `la`, `ls` in the state, decoded with the same validator as the hand, `decode_card`). `Director.view()` gains `last`, `last_seq`, `last_age`.

## 2026-10-03 - A deck holds up to 100 cards (`e16bd3c`)
- `Events.MAX_CARDS = 100`; the custom slots are the rest (88, keys `custom_1`...`custom_88`; it was 20). The Deck's odds strip has 100 segments, the host takes up to 100 cards per player in the pooled draw (it was 40), `/rw_custom` takes slots 1-88.
- The client-to-host waves message limit is 90000 bytes (it was 60000; Realms allows 96 KiB); a client whose enabled cards do not fit sends the first ones that do and logs it once. 100 cards of twelve groups with modifiers and custom mods measured 34 KB.

## 2026-10-03 - Fester becomes HERESY (`c8b955b`)
- The Fester suit is replaced by Heresy, the last of the twelve and the only `special` one: black red face, blood-red frame, gilded accent, a broken-halo-and-blade mark, the whisper "He does not answer.". It has a frame at rest and a smouldering glow on the Spread, the Deck tile, the Cauldron's stage card and the Mirror's hand preview, and the banner says "Heresy is drawn".
- `fester` stays an alias (`Cards.SUIT_ALIAS`, `Events.SUIT_ALIAS`): saved cards, presets, shared texts and hands synced by an older host become Heresy.

## 2026-10-03 - `/rw_test_close <wave>` (`d1c35a0`)
- Spawns the wave 3.5 to 8 m in front of the player who typed it (where the camera looks, on walkable ground, closer if a wall is in the way), spread at most 2 m, facing and aggroed on the player. Host only. `/rw_test` is unchanged.

## 2026-10-03 - Deck presets (`d19a314`)
- The Deck's top button, "Spreads", is called "Deck presets": it holds the five whole-deck slots. "Spread" now only means the HUD's hand.

## 2026-10-03 - Card pages take the colours of the card's face; tighter shelf chips (`af83310`)
- The Mods and Custom pages (and the picker, Cauldron and Mirror) took only their buttons from the suit; now the ground, panels, rows, frames, titles and headings do too (`Components.set_theme`, one shared table that the static widgets read every frame). The Deck, options and presets keep the default palette.
- With the D/S tags gone the shelf chips are smaller (height 30, pitch 36); the room that freed is a sixth enemy row in the Cauldron.

## 2026-10-03 - Custom health is exact and the game's "Weakened" name is back (`d8e57bf`)
- `MinionSpawnManager.spawn_minion` adds the Havoc / mission health modifier to the custom health spawn parameter, and mods such as Ultra Havoc rewrite that modifier, so a boss set to 50 percent was 50 percent plus Havoc's share. `Tuning.set_exact_health` now sets maximum health to exactly normal health x the player's percent right after the spawn (the extension's `_health` and the game object's `health` field) and re-reads the boss's weakened mark.
- The workaround that cleared the mark and hooked the boss health bar (`b5a41c5`) is removed: a boss with less than its normal health is "Weakened" again, the game's own word.
## 2026-10-03 - Record PR #7 merge status
- Record GitHub's PR #7 merge by `EduardoKenji` at `c7cf1da` and refresh local main after final PR/push checks pass on Lua 5.5 and LuaJIT 2.1.
- Correct current open/unmerged guidance in the README, index, method guide, plan and CI log; preserve historical publication records and pending native acceptance. This is a documentation-only follow-up with size/whitespace checks; runtime, tests and workflow match the verified PR head.

## 2026-10-03 - Record enemy appearance PR publication
- Push `feature/enemy-appearance` and open [PR #7](https://github.com/Marchini-Pedro/Grandfathers-Tarot/pull/7) against main after PRs #5 and #6, as requested. Record the publication in the README, index, method guide, plan and verification log.
- Verify the first hosted PR run at `0103281` and download reports: 1,916 assertions per runtime, 81.80% Lua 5.5 / 78.54% LuaJIT source-line scores and no coverage failures; the results match local runs.
- Keep native/multiplayer/performance acceptance pending and the feature unmerged; publication does not change installed mods.

## 2026-10-03 - Synchronize enemy appearance with merged CI work
- Fetch origin and fast-forward `main` to `06c2b3a` in a dedicated worktree after PRs #5 and #6; merge that main history into `feature/enemy-appearance` while preserving the other agent's checkout.
- Resolve the changelog conflict by retaining both feature and CI publication entries; update branch status to distinguish CI already on main from appearance pending review and game acceptance. Runtime, test code and CI configuration are unchanged by this synchronization.
- Rerun both aggregate checks: 1,916 assertions per runtime and all gates pass; Lua 5.5 source-line score 81.80%, LuaJIT 2.1 78.54%. Native acceptance remains pending.

## 2026-10-03 - Integrate CI verification into the enemy appearance branch
- Merge CI commits through `fd56262` into `feature/enemy-appearance` only; preserve the CI checkout and `main`. Resolve README/changelog conflicts with both histories and the aggregate runner.
- Instrument/discover the appearance harness with the existing CI helper; report all focused checks and extend readiness/default/unsupported-stim cases to 79 assertions. Update the protocol failure fixture for DMF schema loading and the seventh endpoint.
- Assign measured floors to the three new modules (schema 84, runtime 79, editor 90) without changing existing thresholds or the overall 78 floor. Full suite: 1,916 printed assertions per backend; native acceptance remains pending.

## 2026-10-03 - Exercise enemy colour persistence and lifecycle
- Add `tools/appearance_test.py`: 71 focused schema/runtime/protocol/editor/entry assertions plus reused editor/entry regressions, passing on Lua 5.5 and LuaJIT 2.1.
- Cover colour merging, scaled drag/exact input, initial/repeated selected spawns, vanilla stim permission, outline isolation, detach/death/restoration, failed setters, capability/host/token validation, leases, late units, queue bounds and synchronous reset during snapshot sending.
- Reuse the CI runtime/coverage helper when available; retain standalone execution from the feature's original base. Emit real-widget colour/dropdown previews through the existing serializer. Native rendering and multiplayer acceptance remain pending.

## 2026-10-03 - Add per-group enemy colour experiments
- Add ARGB sliders/numeric entry/swatch and a method dropdown under Custom; preserve appearance in recipes, grouping, copies and repeated spawns.
- Implement natural stimm using supported vanilla actions/buffs, visual-only applied/explicit-slot stimm and private-map local outlines. Surface/private shader choices display their prerequisites and perform no operation.
- Add optional host-authorized appearance replication with capability, mission token, late-join snapshots, bounded queues/renewal and cleanup. Keep HUD protocol/version 2 / 2.0.0. Preserve concurrent CI work in a separate worktree; native acceptance remains pending.
- Document the implementation, advanced gates and restoration limits; preserve the earlier read-only research reports. Baseline regression checks pass, with the RPC inventory assertion updated for the appearance endpoint.

## 2026-10-03 - Record CI merge and verify hosted checks
- Publish `feature/ci-coverage` as PR #5 and document the owner's steps to require both runtime checks and pull requests for `main`.
- Record the first successful hosted PR run and downloaded reports: 1,837 assertions per runtime, 81.56% Lua 5.5 / 78.30% LuaJIT source-line scores, and no coverage failures. PR #5 was merged by the user at `03785e3`; both checks also pass on main. Merge enforcement awaits owner setup and game acceptance remains separate.

## 2026-10-03 - Add CI and enforce measured Lua coverage floors
- Add GitHub Actions on pushes, pull requests and manual dispatch, with Lua 5.5/LuaJIT 2.1 jobs, pinned action revisions, read-only repository permissions and uploaded logs/JSON reports.
- Run compilation, discovered behavior harnesses, 11 coverage/runner contracts and documentation size checks through `tools/run_tests.py`. Require a 78% overall source-line execution score and explicit floors for all 29 Lua modules; missing evidence, collector errors, unknown/stale modules, failures and timeouts fail the job.
- Record the post-PR #4 review and standalone-checkout validation: 1,837 assertions per runtime, 81.56% Lua 5.5 and 78.30% LuaJIT source-line scores. Required merge checks remain a repository-owner setting; game acceptance is separate.

## 2026-10-03 - Extend post-PR #4 behavior coverage and isolate harnesses
- Add 80 behavior assertions: hidden-position selection and retry/failure boundaries, console/keybind adapters, protocol availability/serialization failures, and the editor callback fixture contract.
- Select Lua 5.5 or LuaJIT 2.1 through one shared runtime and pin Lupa 2.8. Remove the machine-specific default Python path and the sibling game-source dependency; preserve explicit `PYLIBS` support.
- Keep allocation assertions active while suspending line-hook allocations during heap probes. All 1,826 behavior assertions pass per runtime; six representative mutations fail their intended assertions on both runtimes. Runtime Lua and game acceptance status are unchanged.

## 2026-10-03 - Synchronize remediation with the merged audit brief
- Merge `main` at `44e536f` into the existing PR #4 branch. Resolve the three documentation conflicts by retaining completed audit/remediation status, history and links.
- Update current PR status without changing runtime/tests or the frozen audit baseline. All six required checks pass on Lua 5.5 and LuaJIT 2.1 (1,746 assertions each); live acceptance remains pending.

## 2026-10-03 - Close retirement coverage and complete remediation review
- Release all tuning/protocol owners and guard captured callbacks, delayed hook registration and executors; retry missing/replaced event managers on gameplay entry.
- Preserve current live records when a failed snapshot returns after synchronous teardown. Skip malformed host candidate entries within the existing five-card bound.
- Add partial-budget and retirement regressions; all six checks pass on both runtimes (1,746 assertions each). All 17 selected mutations fail intended behavioral assertions; supported-max work stays bounded in five repetitions per runtime/mode. Saved data and read-only references remain unchanged; native acceptance is pending.

## 2026-10-03 - Recover recipient-specific size failures (F06)
- Fan out sizes through direct Realms sends with a bounded peer registry, propagate failures into current-size retry, skip unsupported RPCs and refresh peers after enable.
- Coalesce failed late-join snapshots and protect new updates during synchronous sends. Actual installed ModNetwork plus real Protocol/Tuning reproduces rejection/recovery on both runtimes.
- All six checks pass (1,735 assertions each); native rejection frequency and multiplayer overhead remain pending.

## 2026-10-03 - Reject non-finite imported numbers (F07)
- Validate all nine numeric fields in preset/card imports before rounding/clamping; retain finite clamps and legacy absent/empty threat.
- Add valid-checksum NaN/infinity/overflow and atomic-write regressions on both runtimes. All six checks pass (1,724 assertions each); native paste workflow remains pending.

## 2026-10-03 - Bound aggregate pending work (F04)
- Cap execution at 64 jobs / 8,000 pending units; reject initial waves before allocation when they cannot fit and skip/clip repeats against shared capacity. Throttle timed-wave failure warnings.
- Add supported 32-timer, atomic-admission, repeat-only and teardown regressions. All six checks pass on both runtimes (1,677 assertions each); native budget tuning remains pending.

## 2026-10-03 - Remediate pause, stop and disable (F02/F03/F05)
- Separate scheduling cancellation from mission teardown; preserve living-unit accounting/tuning while stopped and freeze queued clocks while paused.
- Cancel disabled work, retain/prune living ownership, and resync clients on re-enable; hosts explicitly restart.
- Drive real entry/director/executor/tuning through cap/recompute/control/unload regressions. All six checks pass on both runtimes (1,672 assertions each); native checks remain pending.

## 2026-10-03 - Remediate event ownership (F01)
- Unregister both mission events from their original manager at unload; guard captured callbacks and missing managers.
- Add an owner-faithful 100-generation entry regression. All six checks pass on both runtimes (1,659 assertions each); native acceptance remains pending.

## 2026-10-03 - Execute the offline adversarial audit (documentation only)
- Record the frozen baseline, complete 29-file/descriptor inventory, risk-to-test map, five detected mutations and two survivors, L1–L8 results/limits, measurements and real-widget previews.
- Report seven reproduced lifecycle, control, aggregate-pressure, delivery and numeric-import defects; preserve runnable isolated diagnostics in Markdown and an exact native/multiplayer/eight-hour acceptance checklist.
- Update current guidance, plan, verification, learnings and source/recovery notes. Runtime, tracked tests, configuration, interfaces and read-only references remain unchanged; fixes await the agreed review gate.
- Final review corrects descriptor line count and live heap precision, and clarifies the injected rejection/native-delivery distinction. Subsequent authorization starts a separate remediation branch; this report preserves the pre-fix baseline.

## 2026-10-03 - Prepare an adversarial audit brief
- Add an audit-only prompt covering meaningful test adequacy, repeated UI/reload/preset/mission lifecycles, wave-count scaling, Lua/native/process memory, Realms authority and asynchronous ordering, UI/coherence and selective BetterInventory reuse.
- Require reproducible baselines, primary-source checks, fault-injection evidence, honest offline/live limits and ranked proposed fixes. Link the brief from the documentation index and CLAUDE.md; the audit has not been executed.

## 2026-10-03 - Refresh README and documentation maintenance
- Add a concise root README with current features, installation, controls and known limits; keep the docs README as a technical index instead of duplicating release history.
- Require same-session README review for user-visible changes in CLAUDE.md, with source checks, links to detailed docs and removal of superseded text.
- Correct current recovery/plan status after PR #1 merged into main; distinguish the runtime version, historical workshop milestone and pending in-game verification. Mark installed Realms 1.0.0 as different from the historical audit snapshot.

## 2026-10-03 - Recover unpublished workshop work
- Preserve 25 local commits after remote main and the eight-file unfinished Deck sorting/drag changes on `feature/workshop-recovery`.
- Recovery provenance and review status: `09-recovery-review.md`. Validation pending; no in-game claim.

Newest first. One entry per commit (see also the results log in `06-verification-and-open-issues.md`).

## Older versions
The 2.1.0 and 2.0.0 steps are in [changelog/2.x.md](changelog/2.x.md) (split out on 2026-10-04, 100 KB rule). Everything from 1.13.0 down to 1.0.0 is in [changelog/1.x.md](changelog/1.x.md) (split out on 2026-10-02 to keep every .md file under 100 KB; the rule and the check are in `CLAUDE.md` and `tools/check_docs.py`).

## 2026-10-03 - Validate the actual checkout on Lua 5.5 and LuaJIT
- Compile and logic checks resolve this checkout; DMF file loads in every harness resolve independently of the directory name.
- Harness integer division, UTF-8 check and unpack alias now work under LuaJIT 2.1 too. Allocation checks warm the measured loop; LuaJIT trace compilation is disabled only during heap measurement to remove unpredictable compiler allocations.
- All six checks pass on both runtimes: 30 compiled files, 650 editor, 14 entry, 179 HUD; logic has zero failures.


## 2026-10-03 - Integrate the second unpublished feature branch
- Preserve nine attack-timing commits through c7141cb alongside the workshop history. Resolve shared tuning, entry and logic tests while retaining custom boss naming and multi-batch scale validation.
- Includes gap terminology and safe boss combos, burster radius scaling, gunner diagnostics, minion stat hooks with modified-stat bookkeeping, and guarded size sends. Offline validation below; no merge into main.

## 2026-10-03 - Complete and harden Deck sorting and dragging
- Persistent ascending/descending sorts by threat, chance (rarity), enemy count and face; manual swaps clear the active sort. Hidden/deleted keys remain in the saved order and new keys append safely. Sort tie-breakers reuse one table instead of allocating in each comparison.
- Only an actual face/state press arms a toggle or drag. Double-click releases never undo the first toggle; drops outside the grid or with no cursor cancel. Scrolling, sorting, popups, screen changes and closing restore positions/layers/opacity before reusing slots.
- 44 additional editor checks cover persistence, all sorts, stable ties, draw independence, releases and cancellation. Reintroducing the outside-drop, scroll or double-click bugs fails the regression checks. Stubbed idle updates remain below 1 byte/frame.

## 2026-10-03 - Bound repeat work and harden multiplayer tuning
- Repeat queues are capped at 1000 pending units per job, including partial repeat batches. Reuse each batch for linear-time prepending instead of repeated front inserts; skip overdue ticks in one step when full.
- Client scale queues coalesce by unit id: newest arrival wins, duplicates do not consume capacity, full queues still accept updates to an existing entry, and a unit id that exists before its handle arrives waits/retries. Completed entries use constant-time removal.
- Failed sends return safely and retry at the next 0.3 s cadence. Retries keep only current live unit sizes, removing duplicates/dead units. RPC state, welcome and sizes are accepted only from the session host; wire protocol stays version 2.
- Track actual minion stat resets so a new base equal to the previous tuned value still gets the multiplier exactly once. Multiple post-hooks remain idempotent. Regression/mutation checks cover the queue cap, latest scale and equal-value recompute.
