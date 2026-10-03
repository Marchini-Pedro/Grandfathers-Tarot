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
| 2 | F02/F03/F05 disable, stop, pause and living units | Pending |
| 3 | F04 aggregate admission/repeat budget | Pending |
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
