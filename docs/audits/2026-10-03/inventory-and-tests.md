# Source inventory and test effectiveness

See [report](report.md) for baseline revisions and findings. All paths in the
inventory are relative to `scripts/mods/GrandfathersTarot/`, except the descriptor.
Every file was included in compilation, responsibility/caller/ownership review
and the appropriate existing harness. Review is scoped: visual declarations
were checked through widget construction, geometry and pass assertions, not
native rendering; engine-facing code was traced through the relevant guards,
callers and teardown, with the remaining live evidence below. This is not a
claim that every statement was dynamically executed.

## Complete inventory

| File | Lines | Responsibility / callers | Ownership, hot paths and review evidence |
| --- | ---: | --- | --- |
| `GrandfathersTarot.lua` | 432 | DMF entry, commands, module wiring | Owns RW generation, event subscriptions, HUD/view registrations; update/unload/disable traced; F01/F02 |
| `GrandfathersTarot_data.lua` | 159 | DMF options | Defaults and ranges, togglable state; compare editor ranges and synthetic legal maxima |
| `GrandfathersTarot_localization.lua` | 451 | UI/DMF English text | Static strings, formatting/percent conventions; real-text previews; other locales use fallback, native localization pending |
| `catalog/cards.lua` | 479 | Tarot model, UI and migration | Pure descriptors/suit/threat/chance, capped dots/whispers; migration and snapshot tests |
| `catalog/colors.lua` | 279 | Enemy/modifier/faction colors | Breed/modifier caches, optional-mod callbacks; reset on view entry; bounded recognized inputs in supported flow |
| `catalog/events.lua` | 587 | Catalog/settings → wave/pool | 12 standards + 20 customs; stable order, deleted-key filtering, clamped chance, timer exclusion; logic/editor |
| `catalog/groups.lua` | 1219 | Recipe, aliases, enemy shelf/search | 12 parts, 60 per part/breed limit, 120 initial total; parser/copy/serialization/clamping; static breed/modifier/tune data |
| `catalog/presets.lua` | 535 | Capture/apply/import/share | Five slot ids; independent textual snapshots, validation/checksum, unknown/duplicate keys; L6, NaN import F07 |
| `core/director.lua` | 1310 | Entry/protocol → mission scheduler/HUD | Host/client state, peer inventories, cooldowns/timers; authority/start/stop/pause/rejoin; F03–F05 |
| `core/protocol.lua` | 268 | Realms network adapter | Six RPC registrations, host validation, payload gates, pcall; sender routing, local reentrancy, F06 |
| `core/votes.lua` | 87 | Director ballot tally | One current vote per peer, close/peer removal; reused count table must be read immediately; tie/no-vote tests |
| `spawn/budget_bypass.lua` | 165 | Executor ↔ engine counters | Tracked-unit owner, spawn flag, purge/unregister/retire; hook scopes and Havoc aggro event; F03 |
| `spawn/execute.lua` | 749 | Director → queued spawning | Jobs, pending entries, position cache, feed/repeat clocks; caps/rejection/timeout/heap guard/authority; F03–F05 |
| `spawn/positions.lua` | 277 | Executor hidden/ring/spread positions | Query-local lists, at most 3 scanned players / 160 raw / 24 candidates; failure exits, mesh calls guarded; geometry native pending |
| `spawn/tuning.lua` | 910 | Spawn/protocol → stats/sizes/hooks | Unit/extension maps, outbox/inbox, reassert timer, retire/reset; native buff consumers, combo/shot/template tests; F03/F06 |
| `ui/deck.lua` | 276 | Editor deck arithmetic | Stable copied sorts, swaps, page bounds, fixed 14-tile capacity; L5 helper experiment beyond 32 labeled unsupported |
| `ui/spread.lua` | 627 | HUD/editor shared arithmetic | Five-card maximum, preallocated timeline/shapes/rot state, clamped geometry; HUD pass/retention checks |
| `ui/hud_element_waves_definitions.lua` | 245 | HUD widget factory | Finite static pass count; defaults matched to UIWidget stub; all passes inspected by HUD assertions |
| `ui/hud_element_waves.lua` | 1244 | Game HUD lifecycle/update/draw | Widget/timeline/options/scratch owner; signature-driven updates, off/disabled early hide, draw-state restoration; L4 |
| `ui/wave_editor_definitions.lua` | 441 | BaseView scenegraph and constants | Static 1920×1080 geometry, button/row/tab placement; node/pass geometry tests and resolution previews |
| `ui/wave_editor_blueprints.lua` | 533 | Editor widget/pass factory | Fixed tiles/rows/hotspots; shared blueprint data cloned into widgets; callback content-parent contract |
| `ui/wave_editor_components.lua` | 970 | Shared styles/widgets/modal editing | Popup spec callbacks capture view; commit/cancel clears spec/text flag; numeric/type limits; L1/L2 and focus tests |
| `ui/wave_editor_view.lua` | 2396 | BaseView lifecycle, model, workflows | Dynamic widgets/callbacks, selection/preset/undo state; on-exit cancellation, active-screen work; L1/L2/L6, last-group guard |
| `ui/wave_editor_deck.lua` | 1167 | Deck rendering, sorting and dragging | View-owned tile FX/drag/press, current cursor release, persistent key order; stale drag mutation detected |
| `ui/wave_editor_face.lua` | 155 | Mirror callbacks | Immediate face settings, whisper cancel restoration, cooldown inputs; no independent resource owner |
| `ui/wave_editor_tune.lua` | 97 | Custom-stat callbacks | Copies/clamps tune table, removes unchanged values, modal validation; no independent lifetime |
| `ui/wave_editor_workshop.lua` | 855 | Cauldron/Mirror painting/callbacks | View-owned stage, shelf and row FX; refresh/update routes scoped to current screens; editor/workflow previews |
| `ui/workshop.lua` | 188 | Layout/geometry helpers | Pure calculations, shared stage/shelf/hand dimensions; editor geometry assertions |
| `ui/workshop_blueprints.lua` | 617 | Workshop passes | Finite rows/chips/stage/hand, hit-area definitions; engine-default and visible-pass review |
| root `GrandfathersTarot.mod` | 15 | DMF descriptor | Load after Realms, static module paths; no new game packages; compilation/path review |

Total: **29 Lua files + descriptor**, 30 compilation inputs. Root README,
CLAUDE, docs index/design/plan/verification/recovery/history were read as claims
to verify, not substitutes for evidence. `source_inventory.json` retains the
function/hook/limit index for the full tree.

## Resource ownership trace

| Allocator → owner | Bound | Invalidation | Teardown/result |
| --- | --- | --- | --- |
| Entry registrations → game EventManager | One mod key per event per generation; generations accumulate | None at target unload | Missing unregister: F01; explicit scratch unregister releases all obsolete generations |
| Spawn batches → Execute jobs/queues | 500 initial per wave; 1,000 queued per job | Feed, timeout, repeat completion | Full mission reset works; aggregate lacks a budget (F04); stop uses too much teardown (F03) |
| Spawned handle → bypass tracked set | Alive cap while ownership intact | Engine unregister hook; purge while jobs active | Mission reset/retire clear; stop loses live owners. With no jobs, periodic purge does not run; native unregister delivery is a remaining contract check |
| Tuned unit/ext → Tuning records/maps | Live owned units; inbox 600; message scale batch 200 | Dead-unit reassert, inbox dedup/age/apply | Reset releases; stop clears prematurely; late-join snapshot depends on surviving ownership |
| Candidate query → Execute cache | Finite distance/test/monster combinations from active jobs; TTL controls reuse, not key eviction | Entry refreshed after success/failure TTL | Reset clears. No measured cache leak; repeatedly changing distance pairs may retain old cache keys until reset, robustness/live workload not measured |
| Widget creation → editor view callbacks/popup/FX | Fixed tiles/rows/shelf; 32 supported cards, 5 preset slots | Screen changes, drag end, popup cancel | 100/1,000 cycles weak views zero; actual BaseView/native destruction not modeled |
| HUD init → element widget/layout/timeline scratch | Five cards and finite FX arrays | Hand/signature/stage changes; early hide when off | Weak elements zero after fixture release; native materials/package lifetimes unmeasured |
| RPC/wave input → protocol/peer inventories | 60,000-byte wave text, known keys, disconnect removal | Registration replacement by mod name/RPC, peer leave, mission reset | Realms persistent registration tables replace this owner's callbacks; no evidence of per-reload RPC-name accumulation |
| Optional colors → Colors caches | Supported known breeds/modifier ids | `clear_cache` on editor entry | No demonstrated owner accumulation; arbitrary private helper keys outside supported flow not acceptance evidence |

## Risk-to-test map

Each row links path → invariant → existing assertion → detected regression →
missing scenario → required evidence. “Pass” describes its specific assertion.

| Path / invariant | Existing assertion/evidence | Regression detection | Missing scenario / next evidence |
| --- | --- | --- | --- |
| Groups parser: valid bounded independent recipe | Logic limits/aliases/tune serialization; 11 new numeric/boundary recipes | Huge counts/size clamp, excess total clips, negative/NaN/inf tune syntax rejected | Sparse private tables are outside parsed recipe shape; no exhaustive fuzz claim |
| Presets: atomic decode/apply, independent snapshot | Logic `share: the snapshot holds suit...`; editor Undo last load and five slots | Existing checksum/truncation/unknown-key tests pass | L6 loops cover small/large/truncated; deleted/reordered history is functional-test evidence, not every stress iteration; real save backend pending |
| Preset numeric fields: finite imported values | Both-runtime boundary probe, copied snapshot remains unchanged after edits | Existing tests miss correctly checksummed NaN; F07 reproduced on LuaJIT | Reject each non-finite field atomically; sparse private tables encode only the contiguous prefix, not a supported UI shape |
| Events/Deck: stable persistent order | Editor `order: duplicates and deleted keys are ignored`; `a reload reads the saved order` | Stale-drag mutation fails outside-grid cancellation | Native draw/input release ordering, lost focus/window and scrolling require live checks |
| Director selection: weights/cooldown/timer exclusion | Logic tarot no repeats/cooldown, fixed timers; 20,000 seeded weighted samples | Existing deterministic selection checks pass | Statistical check tests the shared weighted helper, not full long-session outcomes; hand winner uniform roll verified by source, not a fairness theorem |
| Votes: one current vote per current ballot | Logic stale ballot, change/remove peer, tie/no-vote behavior | Existing assertions pass | Native host departure/rejoin and mixed peers pending |
| Execute repeat: per-job pending bound | `repeat: ... never queue over 1000 units` | Removing cap fails two intended assertions on both VMs | Existing assertions do not bound total jobs/entries: F04 fixture is required |
| Bypass: owned live-unit accounting | Logic `later aggro ... event, not counters`; reset/retire checks | Existing assertions pass | Stop while units live, actual engine cap on restart: F03 and live check |
| Positions: missing managers/failed queries exit safely | Logic hidden-point limits, ring fallback, failed-query tests | Existing assertions pass | Mesh/occlusion truth and post-spread visibility cannot be proved with stubs |
| Protocol: only authenticated host controls host messages | `another client cannot spoof host state, a welcome or unit sizes` | Permitting non-host sender fails intended authority assertion | Real native peer identity/channel behavior pending; client-to-others route source checked |
| Entry: old generation releases registrations | Entry unload assertion only tests keybind flag/hook pass-through | Omitting execute/director unload resets survives | Real EventManager owner/weak refs: F01. Real queued work at unload required in future regression |
| Entry disable: no updates feed disabled spawns | No existing behavioral assertion | Actual DMF disable probe reproduces F02 | Regression must drive disable/enable, hooks and jobs together |
| Director pause: clocks/feed freeze coherently | Existing countdown/cooldown pause assertions | Executor is stubbed; no intended feeder assertion | Real Execute repeat/job fixture reproduces F05 |
| Director stop: live ownership survives scheduling stop | Existing stop/HUD phase assertions | No live-unit maintenance assertion | F03 recompute and combined-cap regression |
| Tuning scale: dedup/latest arrival/deferred handle | `newest received size wins`; missing-handle/full-inbox checks | Restore first pending pct fails intended newest-value assertions | Transport order/session generations unverified; latest arrival is not sequence protection |
| Tuning delivery: current live sizes retry failures | Whole-call false-return retry checks | Existing whole-call failure mutation from recovery was effective | Actual Realms returns true for partial rejection: F06; peer-specific recovery fixture required |
| Tuning recompute: equal numeric reset gets factor once | `a fresh base equal to the last tuned value still gets its factor` | Breaking reset marker fails this and idempotence assertions | Actual game subclass/DMF dispatch and gunner/boss animations pending |
| Tuning shared data: normal templates restored on errors | `burster: ... shared ones were never touched`; error restoration | Existing assertions pass | Native nested/reentrant multi-mod hooks and visual blast radius pending |
| Tuning retired instance: obsolete callbacks do nothing | Logic has no detecting retired-tuning assertion | Removing `Tuning.dead = true` in retire survives | Invoke captured old hooks after retire; inspect owner behavior, not just flag text |
| HUD: valid visible passes, restored renderer state | 179 checks incl. `drawing fails ... everything is still restored` | Existing geometry/state assertions pass | Native clipping/material/font/input; HUD L4 adds 1,000/10,000-cycle valid-pass checks |
| UI modal: cancel/exit restores input ownership | Whisper cancellation/auto-search/editor flag tests | Existing assertions pass | Native null input, IME, game locale and raw-DMF keybindings live checks |

## Isolated mutation results

Mutations replace source only in each VM's `dofile`; production and tracked
tests remain byte-identical. Each variant compiles and completes its suite.
No setup exception counts as detection. Results agree across both runtimes.

| Mutation | Suite | Intended assertion failures | Result |
| --- | --- | ---: | --- |
| Remove per-job queue cap (`MAX_QUEUE = math.huge`) | logic | 2: long-frame 1,000 cap, full-queue skipped ticks | detected; queue reaches 540,300 |
| Accept non-host as valid host sender | logic | 3 incl. client spoof and missing session | detected; authority assertion fails |
| Keep first pending size rather than newest | logic | 2: newest wins, full pending queue update | detected |
| Restore stale hovered drag target at release | editor | 1: release outside grid cancels | detected |
| Clear rather than set equal-value recompute marker | logic | 2: collision factor, consumed once | detected |
| Do not mark tuning generation dead on retire | logic | 0 | survives; coverage gap |
| Omit execute/director resets from entry unload | entry | 0 | survives; coverage gap |

Detection rate is **5/7 selected mutations**, not a coverage percentage or
proof of all behavior. Tests detect several real classes of regression, yet
1,655 passing assertions do not cover these cross-owner lifecycle failures.

## Exclusions and remaining evidence

Read-only sources are limited to changed/relevant contracts: Realms network
routing/framing, DMF events/toggle/reload, game events/buff/attack/UI consumers,
and selected BetterInventory lifecycle files. No wholesale re-audit of
TwitchVersus, RealmsEvent, SoloPlay, DMF native code or BetterInventory was
performed. BetterInventory's source-string test is not promoted to measured
behavior. No assets, native DLLs, game files, packages or actual saved data were
changed. Native threading/deadlock analysis, exact VM allocator limits,
multiplayer transport ordering, resource loading and live clipping remain
outside the harness; [live acceptance](live-checklist.md) gives concrete checks.
