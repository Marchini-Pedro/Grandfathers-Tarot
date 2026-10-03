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
| 4 | F07 finite numeric imports | Pending |
| 5 | F06 recipient-aware size recovery | Pending |
| 6 | Surviving retired-tuning/unload-reset mutations and final review | Pending |

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
closes the unload-reset mutation gap; retired-tuning coverage is still pending.

Batch 3 sets fixed internal limits of 64 jobs / 8,000 pending entries. Full
admission rejects the whole wave before expanding it; repeat-only jobs consume
slots too. Repeats skip overdue ticks at full capacity or clip to remaining
room. Timed-wave errors log at most once per five seconds. These limits are an
initial operational policy, preserving settings/protocol/serialization, and may
need live tuning. The 32-card supported-max fixture stays bounded through
10,000 updates; repeat-only admission, progress and unload also pass. All six
checks pass on both runtimes: entry 40, total 1,677 assertions each.
