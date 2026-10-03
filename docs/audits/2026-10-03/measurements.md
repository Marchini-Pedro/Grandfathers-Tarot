# Lifecycle, scaling, timing and memory evidence

See [report](report.md) for findings and frozen identities, and
[reproduction](reproduction.md) for runnable diagnostic sources. Raw JSON,
full assertion logs, operation sequences, hash manifests and widget PNGs
remain under `.git/audit/2026-10-03/`.

## Controls and meaning of measurements

Fresh isolated VMs, synthetic inventories/settings and fake native unit handles;
real target modules, real engine callback/EventManager where specified. A fake
spawn creates a small Lua record, not a native minion. No native resource,
renderer, frame time or Darktide process RAM was measured. Lupa process RAM
would not answer the game-memory question, so it is not substituted.

Timing tables use five sequential repetitions, Python `perf_counter`, warm
helper/editor loops where stated, normal JIT enabled for LuaJIT timing, natural
GC during activity, then explicit collections for diagnostics. Representative
director repetitions use seeds 424243–424247; runtime RNG streams differ.
Max-legal director runs accumulate blocked work from 32 fixed-timer cards;
ten fake live units occupy the cap after the first feeder batch. No claim that
those fixtures have identical native cost or complete per-frame distributions.
The reported tail is the maximum of five batch samples, not a statistically
meaningful p95/p99. Endpoint heap samples are not continuous peaks.

Allocation churn (loaded heap), still-owned active queues/units, JIT compilation
retention and post-teardown collected Lua heap are kept separate. Tracing-off
controls answer Lua ownership, not normal-JIT speed. The fixed 1 GiB game heap
observed historically is not established as Lupa's allocator limit. Timing
overheads include the harness loop and periodic valid-pass inspections; no
causal comparison to native game frame time is made.

## L1–L8 schedule and limits

| Workload | Executed evidence | Result / explicit limitation |
| --- | --- | --- |
| L1–L2 editor | 100 and 1,000 unchanged, edited and navigation open/close cycles per runtime; detail/Mirror/picker/Mods/Custom/back, scrolling and modal cancellation; five extra 100-navigation timing and tracing-off batches | Weak views zero and text flag cleared. Initial 1,000-cycle timings are single observations; short timing claims use the five-repetition table below. Native BaseView destruction/material/input mocked |
| L3 reload | 100 actual entry load/unload generations with persistent real 1.13.0 EventManager, hook/view/command registry removal, two collections | F01 retention; unregister control releases owners. Native editor-open/closed/package states and queued live work through the actual loader are not modeled; those reload combinations remain live checks |
| L4 sustained updates | 1,000 / 10,000 director/view updates, representative and max legal load, five repetitions each; dt 0.016. HUD update/draw: both sizes, five repetitions, hand/roulette/reveal/rot/max-five-card-scaled-rot/legacy/off | Aggregate pressure F04; all full teardown counters zero. HUD visible-pass invariants and weak elements pass; native base draw is no-op. Initial normal run also exercises cooldown bookkeeping |
| L5 scaling | Supported 32 definitions in max fixture, twenty custom slots, five preset slots, parser rejection/clipping boundaries; Deck sorting 10/32/100/1,000/10,000 synthetic records, five repetitions | More than 32 is a pure sorting-helper robustness experiment, not supported catalog/UI/wave capacity. No 10,000-wave engine stress claim |
| L6 persistence | Initial 1,000 small/large alternations and 1,000 truncated imports; warm five × 100 and five × 1,000 alternations/rejections per runtime; snapshot/deleted/order/Undo functional checks | No increasing warmed collected-heap trend; real DMF save I/O not exercised. Deleted/reordered/invalid data coverage is partly existing assertions, not every lifecycle combination. NaN import F07 separately confirmed on LuaJIT |
| L7 missions | 30 simulated enter/start/end/abort-or-rejoin-style cleanup transitions with queued repeat work and peer departure | jobs/queued/tracked/pending zero, phase off. Sequence uses shared exit/re-entry paths; no real game-state/native mission transition claim |
| L8 combined faults | Seeds 12345/49374/424242, 1,000 operations each per runtime: queue/repeat, pause, exit/re-enter/start, peer leave, stop/restart, scales, update, despawn, late state and preset apply. Operation sequences retained in JSON | All terminal jobs/tracked/pending zero. Real navigation and actual mod-generation reload are exercised separately by L1–L3, not jointly in this fixture; missing-native-manager/transport combinations retain existing functional or live evidence |
| Elapsed-time soak | No game run | Eight hours / ten consecutive missions remains pending; exact capture procedure in [live checklist](live-checklist.md) |

## Normal-runtime timing

Milliseconds per batch, **median / maximum**, n=5 for each cell. These are
synthetic Lua timings, not game frame times.

| Workload | Operations per batch | Lua 5.5 ms | LuaJIT 2.1 ms |
| --- | ---: | ---: | ---: |
| Director representative | 1,000 | 6.870 / 8.636 | 4.446 / 6.890 |
| Director representative | 10,000 | 61.873 / 67.199 | 30.735 / 32.804 |
| Director max legal | 1,000 | 36.793 / 38.345 | 18.960 / 24.833 |
| Director max legal | 10,000 | 1128.071 / 1188.456 | 561.156 / 591.249 |
| Deck sort 10 records | 1,000 sorts | 6.062 / 6.183 | 1.905 / 2.242 |
| Deck sort 32 records | 1,000 sorts | 25.789 / 26.239 | 7.599 / 7.850 |
| Deck sort 100 records | 1,000 sorts | 117.853 / 119.953 | 35.036 / 40.341 |
| Deck sort 1,000 records | 100 sorts | 207.247 / 208.171 | 63.350 / 73.459 |
| Deck sort 10,000 records | 10 sorts | 317.915 / 325.076 | 91.359 / 92.070 |
| HUD hand update/draw | 10,000 | 35.762 / 35.885 | 4.185 / 4.877 |
| HUD roulette update/draw | 10,000 | 42.527 / 42.977 | 5.582 / 6.877 |
| HUD reveal update/draw | 10,000 | 161.537 / 164.509 | 22.588 / 24.578 |
| HUD rot update/draw | 10,000 | 215.080 / 218.826 | 26.637 / 26.990 |
| HUD max_rot update/draw | 10,000 | 240.470 / 252.930 | 29.425 / 29.636 |
| HUD legacy update/draw | 10,000 | 10.197 / 11.043 | 0.635 / 0.650 |
| HUD off update/draw | 10,000 | 7.874 / 7.937 | 0.435 / 0.648 |
| Editor navigation/open/close | 100 cycles | 2577.171 / 3157.848 | 987.417 / 1006.954 |

HUD uses real definitions/element arithmetic, a no-op base draw instead of the
test's growing draw-history array, reused render settings and geometry inspection
each hundred frames. The max case has five cards, scale 200 and opacity 10.
The 1,000-frame raw samples are retained too; no errors or retained weak HUD
elements occurred. Sorting checks preserve input order and output length;
stable tie behavior comes from the existing editor assertions. Do not divide
these batches into a claim about p99 per-frame native behavior.

Initial 1,000-cycle editor observations on LuaJIT: unchanged 7.36 seconds,
edited 7.86 seconds, navigation 10.44 seconds; Lua 5.5: 19.35 / 20.62 / 23.81
seconds. These observations are not five-repetition speed comparisons.

## Collected retention and active pressure

| Experiment | LuaJIT evidence | Interpretation |
| --- | --- | --- |
| Reload 1 → 25 → 50 → 100 | 703.23 → 7,387.77 → 14,350.88 → 28,277.11 KiB; old mod keys grow 1/25/50/100 | F01 retaining owner demonstrated; tracing disabled. One 100-cycle series, not five independent reload-memory estimates |
| Reload unregister control | zero old mod keys; 427.13 KiB | Removing event owner releases objects; neither native OOM cause nor game process-memory measurement |
| Repeat 30-second active, five tracing-off batches | warm 444.16 KiB, active collected 32,241.62 KiB, teardown 442.21 KiB in each batch; 192 jobs / 192,000 entries | Bounded-by-lifetime aggregate pressure F04; full teardown does release it |
| Max legal 160 simulated seconds, normal JIT | 992 jobs / 992,000 entries; largest endpoint sample 255,997.20 KiB over five runs | Active backlog plus transient/compiler allocations. No continuous-peak claim |
| Warm preset switching, tracing disabled | baseline 518.80 KiB; after 520.08 KiB in all 100/1,000 batches; 498 synthetic setting keys | Fixed owned settings/diagnostic overhead, no per-switch accumulation |
| Initial editor navigation tracing-off batches | collected baseline approximately 1,252 KiB and after approximately 1,252.5 KiB; weak views zero | Small fixed diagnostic overhead/plateau. Normal JIT initial growth drops when compiler traces are flushed |

Lua 5.5 independently shows reload growth (754.84 → 31,506.73 KiB), zero
weak owners after unregister, and stable repeat teardown (warm 428.47, active
29,397.77, after approximately 426.78 KiB). Initial preset-switch growth was
confounded by first-time setting population, so warmed repetitions were used
for the conclusion. Short retention tables should not compare unrelated VM
fixtures' absolute floors as if they shared an allocator baseline.

## UI previews and coherence

Twenty-seven previews were generated from actual dumped widgets: Deck,
Cauldron variants, picker, Mods, Mirror, popup, settings and presets at
1920×1080, 2560×1440 and 3840×2160. Resolution contact sheets and the Mirror
were inspected; node/pass invariants are also covered by editor/HUD assertions.
Actual English localization is used, with two cached dump-only popup labels
corrected in the renderer. All three use the same 1920×1080 logical layout;
pixel/font rounding changes with resolution.

No broad overlap was confirmed in these snapshots. A one-line Mirror hand
name in a 31.5-unit box receives a proxy-font overflow marker at 1440p/4K;
its font line-height heuristic is not the native text metric. This is a live
check candidate, not an accepted UI defect. Tune screen behavior is tested in
editor cycles/assertions; the existing dump tool does not emit a tune PNG.
Native fonts/materials, screen clipping, accessibility, IME and real input
timing are explicitly pending. Card/slot workflows are coherent in the offline
model, but pause/stop/disable semantics conflict with player expectations until
the reported control-lifecycle findings are fixed.

## Boundary, selection and test evidence

Normal suites on each runtime: 30 compiled inputs; logic 764, editor 694,
entry 18 and HUD 179 assertions, total 1,655. Existing suites pass. Five of
seven isolated mutations cause the intended behavioral assertion failures;
retired-tuning and unload-reset removal survive. See the complete
[risk-to-test map](inventory-and-tests.md).

With seed 424242 and 20,000 shared-helper weighted selections at weights 10:1,
Lua 5.5 selected the larger weight 18,222 times (91.11 percent); LuaJIT 18,115
(90.575 percent), versus expected 90.909 percent. Both satisfy the declared
two-percentage-point envelope. A five-card tarot hand has five distinct keys
and a winner in range. This does not prove fairness of every mode/session.

Eleven boundary recipes were tested per runtime: huge breed counts clip to 60,
total 121 clips to 120, size 301 clips to 300, huge gap clips to 400;
negative/NaN/infinity tune syntax is rejected. Independent preset snapshot
text stays unchanged after later edits. Sparse private preset arrays serialize
only their contiguous prefix and are outside the validated snapshot shape.
Finite numeric extremes clamp; checksummed NaN accepted on LuaJIT is F07.
Normal Lua 5.5 alone would hide this validation divergence.

## Verification and diagnostic caveats

Initial diagnostic failures were recorded and corrected **in scratch only**:
missing command stub; invalid tune id; replacing the whole RW table instead
of the captured entry table; a fixed timer below its legal five-second minimum;
calling the wrong simulation helper; empty snapshot used in a sparse-array
probe. No setup failure counts as a finding or mutation kill. The empty-standard
claim was withdrawn after tracing the last-group guard. Windows lacks Python
tzdata here; the São Paulo date was verified using Windows TimeZoneInfo
(`E. South America Standard Time`) rather than adding a dependency.

Final repository checks, reference hashes, Markdown link/revision verification
and documentation sizes are recorded in `final_verification.json` and
`integrity.json`. Only Markdown is permitted in the tracked diff. Native/live
acceptance is pending as specified in the [live checklist](live-checklist.md).
