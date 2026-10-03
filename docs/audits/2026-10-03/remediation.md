# Approved audit remediation

The user authorized systematic implementation after the final audit review on
2026-10-03. Branch `feature/audit-remediation` starts from current `main`
`3e6be468fe6ea7524b5acb4b31ac282f7c9bed0c` and carries the audit documentation.
The [report](report.md) and its embedded diagnostics describe the frozen
pre-fix revision; their observations are historical, not expected post-fix
behavior. Replay those experiments against that revision. New verification is
kept separately under `.git/audit/2026-10-03-remediation/`.

| Batch | Scope | Status |
| --- | --- | --- |
| 1 | F01 event owner cleanup | Implemented; offline checks pass |
| 2 | F02/F03/F05 disable, stop, pause and living units | Implemented; offline checks pass |
| 3 | F04 aggregate admission/repeat budget | Implemented; offline checks pass |
| 4 | F07 finite numeric imports | Implemented; offline checks pass |
| 5 | F06 recipient-aware size recovery | Implemented; offline and primary-contract checks pass |
| 6 | Surviving retired-tuning/unload-reset mutations and final review | Implemented; all selected mutations detected on both runtimes |

Batch 1 unregisters both mission events using the stored original manager,
clears that reference, and protects captured objective/death/update callbacks.
The entry fixture preserves EventManager's strong object keys and weak values;
100 load/unload generations leave no obsolete event keys or weak mod references.
Replaced/missing managers and repeated unload are safe. All six checks pass on
Lua 5.5 and LuaJIT 2.1: 30 compilation inputs and 1,659 assertions each.

No installed mods, saved profiles or read-only sources are changed. Public
APIs, options, protocol 2 and serialization remain compatible. Native rendering,
multiplayer and the [eight-hour live procedure](live-checklist.md) remain pending;
no merge or installation is implied by these commits.

Batch 2 freezes queued repeat/feed/timeout clocks during pause while maintaining
existing units. Stop cancels pending jobs/cache, preserves living ownership and
continues tuning/pruning without active jobs. Disable cancels work and performs
liveness cleanup; DMF suspends hooks and stat maintenance until re-enable. Hosts
explicitly use `/rw_start`; clients clear stale presentation/inbox and handshake.
The real entry fixture checks a 200-second pause, exact resume tick, live stat
recompute, combined alive cap, disable/enable and pending-work unload. All six
checks pass on both runtimes: entry 35, total 1,672 assertions each. This also
closes the unload-reset mutation gap; batch 6 closes retired-tuning coverage.

Batch 3 sets fixed internal limits of 64 jobs / 8,000 pending entries. Full
admission rejects the whole wave before expanding it; repeat-only jobs consume
slots too. Repeats skip overdue ticks at full capacity or clip to remaining
room. Timed-wave errors log at most once per five seconds. These limits are an
initial operational policy, preserving settings/protocol/serialization, and may
need live tuning. The 32-card supported-max fixture stays bounded through
10,000 updates; repeat-only admission, progress and unload also pass. All six
checks pass on both runtimes: entry 40, total 1,677 assertions each.

Batch 4 rejects non-finite supplied values in all nine numeric preset/card
fields before rounding/clamping, including optional threat. Absent/empty legacy
threat remains zero; huge finite numbers clamp and round-trip. Forty-five
valid-checksum field/value combinations test both import formats and zero
settings writes, plus the exact audit text and a finite extreme. All six checks
pass on both runtimes: logic 811, total 1,724 assertions each.

Batch 5 uses direct Realms sends for at most 16 known peers and aggregates
recipient failures into the existing retry. Unsupported RPCs are skipped;
compatible hello/peer refresh rearms them. Successful peers may receive
idempotent duplicates, trading a small retry cost for avoiding per-peer queues.
Pending ids and failed late-join snapshots coalesce at admission. Detaching the
outbox before synchronous sends preserves new values queued by callbacks.
Refresh after enable removes peers missed while disabled. All six checks pass
on both runtimes: logic 822, total 1,735 assertions each.

A separate installed-ModNetwork integration loads the real adapter and tuning,
with only SessionControl rejection injected: the failed recipient has one
initial attempt, a second attempt after recovery, and receives latest size 180;
its retry queue clears. Both runtimes agree. The good peer receives twice,
which is harmless for absolute-size updates. Raw integration results are
`lua55_contract.json` / `luajit21_contract.json` in the separate remediation
scratch directory. Native packet-loss acknowledgements, transport ordering and
live overhead are still unverified.

Batch 6 releases every tuning owner/queue and protocol handler/peer reference,
blocks captured entry points and delayed hook registration, and rejects work
from a retired executor. Gameplay entry attaches an event manager that appeared
late or safely replaces the original owner. A failed snapshot returning after
synchronous retirement cannot recreate outgoing work. Client state skips
malformed candidate entries and caps iteration at the existing five-card bound.
Additional aggregate tests reject a 500-entry initial batch with only 300 slots
free, then clip a repeat to exactly 8,000. Unload clears pending jobs and units.

Final required checks pass on Lua 5.5 and LuaJIT 2.1: 30 compilation inputs;
828 logic, 694 editor, 45 entry and 179 HUD assertions (**1,746 each**).
All seven original mutations now fail intended assertions, including both
former survivors; ten additional mutations detect the new behavior. No harness
error or unrelated failure is counted. The
[validation companion](remediation-validation.md) preserves exact scripts,
commands, mutation assertions and five-sample timing/heap measurements.

The supported-max 32-timer workload finishes at 16 jobs / 8,000 entries in all
20 samples (five per runtime/mode), then resets to zero. Tracing-off collected
heap returns near its warm baseline. Normal-JIT residual heap includes compiler
state. These are synthetic Lua costs; no game frame-time or process-memory
improvement is claimed. The original L1–L8 audit evidence remains archived at
its baseline rather than being overwritten with post-fix results.

Final scope verification allows exactly seven affected Lua modules and two
tracked test harnesses. Descriptor/options/serialization definitions, remaining
runtime/tests, load order, saved configuration, installed mods and read-only
source repositories retain their baseline hashes/revisions/state. Documentation
links, embedded scripts and size checks pass. The unrelated enemy-appearance
research prompt remains outside these commits.

All confirmed audit fixes and both coverage gaps are complete within the
offline envelope. Live installation, host/client and mixed-mod sessions, native
input/rendering, tuned enemies and eight hours / ten consecutive missions still
require the [live checklist](live-checklist.md) and user confirmation before merge.
