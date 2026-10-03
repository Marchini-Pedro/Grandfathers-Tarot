# RealmsWaves: adversarial audit prompt

Reusable brief, prepared 2026-10-03. Invoke it explicitly when ready to run the
audit; merely reading or maintaining this document does not start one.

## Objective and boundaries

Perform a complete, evidence-backed adversarial audit of the current RealmsWaves
project. Determine whether its features, tests, lifecycle management, performance,
UI and Realms integration hold up under normal use and hostile edge cases.
Challenge claims of correctness and efficiency, including claims in existing
documentation and tests. Look for the reachable failure path and then try to
disprove your own finding by tracing the surrounding guards.

**This task is audit-only.** Do not modify production code, tracked tests,
configuration, dependencies or installed mods. Do not deploy, release or merge
fixes. You may run existing checks and write Markdown audit documents. If needed,
create isolated diagnostic scripts, fixtures and fault-injection experiments in
untracked scratch space such as `.git/audit/`; never install them in the game or
alter real saved profiles. Propose minimal fixes and regression tests for later
authorization. Do not interpret an audit request as permission to implement them.

Keep changes focused on RealmsWaves. BetterInventory and the original supplied
copy are read-only references. Follow `CLAUDE.md` and preserve unrelated local
changes, logs, presets and investigation artifacts. Progress with available
evidence; request only information actually needed to resolve a remaining gap.

## 1. Establish a reproducible baseline

Read `README.md`, `CLAUDE.md`, `docs/README.md`, the design/implementation documents,
verification matrix and recovery review. Treat historical audit conclusions as
leads to verify, not proof about the current revision.

| Reference | Location relative to the RealmsWaves repository |
| --- | --- |
| Target checkout | `.` (the `Grandfathers-Tarot` repository; internal mod name `RealmsWaves`) |
| BetterInventory | `../BetterInventory` |
| Supplied recovery copy | `../RealmsWaves_updated` (preserve unchanged) |
| Game source | `../../Darktide-Source-Code` |
| Installed mods / Realms / DMF | `../../mods/` (read-only) |

Resolve these paths against the actual checkout and record any substitutions.

Record target commit, branch, dirty state, runtime/version metadata, game build,
game-source commit, installed Realms/DMF/SoloPlay versions and relevant optional
mods. Confirm tests load this checkout rather than the installed mod or supplied
copy. Record Python/Lupa versions, Lua runtime, JIT/GC settings and test commands.
Keep the baseline fixed while collecting measurements.

The user reports Realms is up to date. Verify the installed build against the
author's current release metadata and relevant source/API; do not assume a version
label establishes compatibility. Historical references used Realms 1.0.0-rc2,
while the subsequent local metadata reported 1.0.0. Recheck actual contracts.

Check whether the game-source checkout matches the installed game and latest
available reference. Fetch/read updated references separately if necessary;
do not silently replace the measured baseline. Distinguish installed release,
latest published release and development HEAD. Document unavailable references
and version mismatches instead of filling gaps with assumptions.

Map every runtime module to its responsibility, hot paths and lifecycle. List
the reviewed files and any excluded area with a reason. Prioritize likely damage
and high-frequency work, but finish the inventory rather than sampling a few files.

## 2. Use an adversarial evidence standard

- Label results **confirmed**, **suspected**, **not reproduced**, or **unverified**.
  Keep severity, confidence and test/execution status separate.
  Failure to reproduce a suspected defect does not prove its absence.
- Give exact source revision and file/line references. For confirmed defects,
  provide a reachable trigger, reproduction, expected/observed result, root cause,
  impact and proposed regression test. Explain why existing guards do not prevent it.
- Distinguish actual failures from unsupported configurations, intentional limits,
  design tradeoffs and speculative optimization opportunities.
- Test failure paths and teardown, not only construction and successful operation.
  Include malformed/nil data, boundary sizes, exhausted budgets, stale references,
  interruption and reordered callbacks where they can really occur.
- Use current primary sources for external facts: author repositories/release
  notes, DMF/Realms documentation, matching game source and Lua/LuaJIT manuals.
  Cite links, relevant commits/versions and access dates. Validate every applicable
  external-contract claim; use source traces and experiments for local code claims.
  Web research cannot establish that this checkout has no leak or UI defect.
- Separate static analysis, stubbed execution, source-contract checks, offline
  widget previews and real-game observations. A passing stub or screenshot cannot
  establish engine behavior, real rendering or end-to-end multiplayer correctness.

## 3. Audit whether tests detect real regressions

Run the existing compile, logic, editor, entry, HUD and documentation checks.
Use LuaJIT 2.1 for engine-relevant behavior and the existing stricter Lua runtime
for portability; disclose harness adaptations and semantic differences.
Verify the game's actual LuaJIT build before assuming equivalence with Lupa.

Build a risk-to-test map: **feature/path → invariant → existing assertion → failure
it detects → missing scenario → offline or live evidence needed**. Report line
coverage if available, but never use assertion counts or a coverage percentage
as the quality verdict. Identify important paths with no effective assertion.

Examine whether stubs model class-method copying, hook dispatch, native input
timing, asynchronous delivery and manager availability. A manually called hook
does not prove the engine invokes it. Inspect production call chains and
source contracts as well as harness assertions.

Challenge high-risk tests with isolated mutations or fault injection: remove a
queue cap, accept a non-host message, deliver an obsolete callback, restore the
stale drag target, apply an older scale update after a newer one, omit teardown,
or reproduce an equal-value stat recompute. Record which assertions fail.
If a mutation survives, identify the coverage gap; do not modify tracked code.
Count a mutation as detected only when the mutated program remains valid and the
intended behavior assertion fails; syntax errors or unrelated harness failures
do not demonstrate meaningful coverage.

Exercise state transitions with deterministic seeds when useful, recording
the operation sequence needed to reproduce a failure. Prefer existing tools
and small scratch experiments over introducing a new testing framework.

## 4. Stress lifecycle, scale and long sessions

Use these as starting workloads, adjusting to actual supported limits. Test
documented maximums and their rejection boundaries first. Large unsupported
inputs are robustness/scaling experiments, not evidence of supported capacity.

| ID | Scenario and starting workload | Required observations |
| --- | --- | --- |
| L1 | Open/close the Deck 100 and 1,000 times, unchanged and after editing | Widget/view ownership, duplicate registration, callback retention, latency and post-cleanup heap trend |
| L2 | Cycle Deck → Cauldron → Mirror → picker/modifier/custom-stat screens → Deck 100 and 1,000 times; include modal cancellation and scrolling | Stale state, input focus, drag cancellation, widget reuse, draw passes and retained resources |
| L3 | Exercise Ctrl+Shift+R lifecycle in an isolated harness for 100 cycles; collect real reload evidence where feasible with editor open/closed, pending work and an active mission | Old-generation hooks/callbacks, duplicate RPC/HUD registration, persistent tables, teardown and resumed state |
| L4 | Run 1,000 and 10,000 draw/cooldown/repeat/update cycles at representative and maximum legal load | Card/effect reinstantiation, idle/draw allocations, queue bounds, normalization, late timers and long-lived references |
| L5 | Explore 10, 100, 1,000 and 10,000 wave definitions where representable; measure legal maximums separately | Sort/search/import/draw/save cost, stable ties, comparator allocations, pagination, payload bounds and rejection of excess data |
| L6 | Switch/load presets or supported profiles 100 and 1,000 times; alternate small/large/deleted/reordered data and invalid imports | Cache invalidation, independent saved snapshots, undo/order state, aliasing, serialization bounds and retained memory |
| L7 | Simulate at least 30 mission start/end/abort/rejoin transitions; specify and execute an eight-hour multi-match live soak if the environment permits | Per-match cleanup, old unit/peer references, timer drift, queue release, process/Lua memory trends and degraded frame time |
| L8 | Combine reload, preset change, rapid navigation, queued spawns, late RPCs and unit despawn in varied orders | Session/generation isolation, reentrancy, safe cancellation and exactly-once or idempotent effects where required |

For each workload, record preconditions, operation count, seed/timing, relevant
configuration, invariants, actual outcome and evidence location. Use isolated
settings and synthetic inventories; do not overwrite the user's saved presets.
Check the cleanup state after each phase, not just whether the loop completed.

Determine what "profile" means in the current implementation: wave preset,
DMF settings, operative scope or another supported feature. Test actual ownership
and limits; do not invent a profile system or assume thousands of cards are accepted.

An accelerated harness is not an eight-hour game soak. If live execution is
unavailable, finish offline work and provide an exact live procedure and data
capture plan. Mark those results pending; never extrapolate them as completed.

## 5. Measure performance and memory correctly

Trace view construction/rebuild, sorting, search, card painting, HUD update/draw,
director selection, spawn-position search, repeat expansion, stat hooks and RPC
encode/decode/retry paths. Derive their complexity and bounds in terms of cards,
widgets, groups, units, repeat jobs and peers. Look for repeated linear scans,
quadratic queue operations, per-comparison/per-frame allocations and work that
continues after a feature or view is inactive.

For retained resources, map **allocator → owner → bound → invalidation → teardown**.
Include tables/strings/closures, native widgets/materials/userdata, caches,
RPC subscriptions, persistent state, live/dead units and captured view references.
Verify every teardown path, including exception, disable, restart and reload.

Distinguish:

- temporary allocation/churn and GC pauses;
- retained Lua heap after cleanup and collection;
- bounded caches/high-water plateaus versus growth proportional to cycles;
- native/renderer allocations and overall process private bytes/working set;
- legitimate live wave/card state versus obsolete state still reachable.

Take a warm baseline, sample during load, then after teardown and a documented
quiescent/GC point. Repeat batches to estimate retained growth per cycle and
inspect the references responsible. Forced collection is diagnostic, not a fix,
and test logs/fixtures must not themselves create the measured retention.

Benchmark with disclosed hardware, game/build, workload, mod combination,
host/client role, clock source, repetitions and JIT/GC mode. Separate cold from
warm behavior. Prefer at least five repeat runs for short benchmarks; report
median, tails such as p95/p99 when enough samples exist, maximum, sample count,
allocation rate and peak/retained heap. Include a baseline/control and raw results.

LuaJIT compiler traces can affect heap measurements. If tracing is disabled for
isolation, also assess execution with normal JIT settings and label the difference.
Stubbed microseconds per update and `collectgarbage('count')` are not engine frame
time, whole-process RAM or native allocation measurements.

Do not conclude "high performance" or "no leaks" from one stable run. State the
tested envelope, measurement sensitivity and remaining uncertainty. Compare
reuse/buffering with simpler allocation only when evidence warrants it; pooling
can retain excessive memory or stale state. Propose the smallest measurable improvement.

## 6. Probe concurrency, authority and Realms contracts

Map callback/RPC ordering and ownership rather than assuming single-threaded Lua
eliminates races. Test synchronous reentrancy, delayed/reordered/duplicate delivery,
lost or rejected sends, stale generations and callbacks after teardown.

Cover host/client differences, host loopback, absent managers during loading,
late join, disconnect/rejoin, peer crash, mission restart, mixed mod versions and
peers without RealmsWaves. Check host-role changes only where Realms supports them;
document unsupported transitions and their required failure behavior.

Review RPC sender authorization, argument/schema validation, size/count bounds,
session identity, update ordering, deduplication, retries, deadlines and backpressure.
Do not invent transport sequence guarantees; read the matching Realms implementation.
Exercise "unit exists but handle is unavailable", dead/reused unit identifiers,
updates after despawn, partial batch failures and retrying the latest live state.

Check repeat/fixed timers, long frame stalls, elapsed-time jumps, zero/extreme
settings, empty pools, full queues and aborted position searches. Verify expensive
work has a bounded exit and all-job bounds as well as per-job caps.

For freezes, distinguish a true deadlock from an infinite loop, retry livelock,
unbounded backlog, blocking native call or rendering stall. Require a viable
execution path and logs/stacks or targeted reproduction before attributing an
engine deadlock. Static suspicion alone remains unverified.

## 7. Review UI and feature coherence

Test Deck sorting/order persistence, page-local swaps, press/hold/release,
double-click, right-click, outside-window release, missing cursor, wheel/page
changes mid-drag, modal interruption and screen/reload cancellation. Verify
position/layer/opacity restoration and that slot reuse cannot mutate the wrong card.

Inspect focus, keyboard/controller navigation, text-entry keybind suppression,
hitboxes, overlapping passes, clipping, resolution/DPI/UI scale, localization,
long/empty/duplicate names, rich-text tokens and invalid imported values. Cover
1080p, 1440p and 4K where feasible. Generate real-widget offline previews for
relevant screens and explicitly reserve fonts/materials/native input for live checks.

Trace complete player workflows: create/edit/share/import/delete/undo/load/sort,
tarot draw/vote/cooldown, pause/stop/resume/advance and fixed/repeating waves.
Check probability/weight semantics, disabled cards, empty decks, stable ordering,
random-group repeat behavior and persistence versus temporary display state.

Verify spawn/director accounting applies only to tracked wave units, including
death/despawn and mission teardown. Check custom stats against native buffs,
repeated recomputes and unmodified enemies of the same breed: no compounded
multipliers or unintended shared-template mutation. Include boss multi-hit chains,
gunner fire/burst consumers, scaled explosions and their visible danger zones.

Check labels, units, defaults, help, commands and README against behavior. Recheck
the known limits around custom boss-health naming, client size replication and
"Time between attacks" versus animation playback speed. Distinguish clearer
wording from a gameplay-design change requiring a separate decision.

## 8. Assess architecture and selective BetterInventory reuse

Evaluate separation of model, director/spawning, protocol and view code;
ownership/lifecycle boundaries; LuaJIT compatibility; defensive validation at
boundaries; error observability; dependency ordering; hook scope and idempotence;
configuration validation and persistence. Review engine consumers and subclasses,
not just the function where the mod writes a value.

Include Lua-specific hazards: array holes and length semantics, unordered or
mutated iteration, table aliasing, nil/false return contracts (including successful
`pcall` with a rejected result), numeric extremes and closure/metatable retention.

Recommend changes only for a demonstrated failure, maintenance burden or measured
cost. Prefer existing modules, simple data flow and native/framework primitives.
Do not prescribe a framework, large rewrite, universal pool or new abstraction
merely to conform to a named design pattern.

Inspect BetterInventory's current source for applicable patterns, such as generation
checks, lifecycle cleanup, cache invalidation, deferred/coalesced work, bounded
queues, view adoption after reload and mutation-sensitive tests. Treat these as
candidates to verify; its passing tests do not establish suitability here.

For each candidate, report **source file/function and commit → problem it solves
→ required assumptions → RealmsWaves fit → smallest adaptation → costs/limits**.
Include useful patterns already implemented and patterns unsuitable for reuse.
Check provenance/license before proposing copied code. Keep BetterInventory unchanged.

## 9. Deliver a reviewable report

Create one dated report at `docs/audits/YYYY-MM-DD/report.md` with linked evidence.
Split measurements or coverage tables into companion files only when readability
or the 100 KB Markdown limit requires it. Keep raw logs/traces in scratch space
unless there is a deliberate reason to version a small, sanitized artifact.
Make findings reproducible from documented commands, inputs/seeds and evidence
excerpts; critical evidence must not exist only in an inaccessible scratch link.

The report must include:

1. **Scope and baseline:** exact revisions, reviewed/excluded areas, environment,
   commands and which experiments actually ran.
2. **Ranked findings:** identifier, severity, confidence/status, source/evidence,
   trigger/repro, expected/observed behavior, root cause, impact, minimal proposed
   fix, detecting regression test and any live verification needed.
3. **Risk-to-test map:** meaningful covered invariants, surviving mutations and
   test gaps, with offline/live limitations.
4. **Performance/lifecycle results:** workloads, controls, bounds, timings,
   retained-memory trends and evidence distinguishing churn from retention.
5. **UI/coherence and reuse conclusions:** concrete workflow inconsistencies,
   applicable BetterInventory patterns and justified simplifications.
6. **Remaining checks and remediation order:** confirmed defects first, then
   evidence gaps and measured improvements; dependencies and precise game checks.

Update the existing implementation plan, verification log, learnings and relevant
design/audit documents in place. Link the report from `docs/README.md`; keep the
player README concise and change it only for verified guidance or known limits.
Deduplicate related findings and avoid copying the same history into every file.

Before reporting completion, check documentation size, links, revision references
and consistency. Confirm no tracked runtime/test/configuration files changed.
Summarize the strongest findings, what was tested and what remains unverified.
An audit may be complete as a documented investigation while live acceptance
remains pending; never present that as proof of bug-free, leak-free operation.
