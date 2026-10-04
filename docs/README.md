# RealmsWaves: documentation index

For features, installation and commands, start with the [project README](../README.md).
This index covers development references, decisions and verification.

## Current status

The workshop and attack-timing histories, unfinished Deck sorting/drag work and
review fixes were recovered and merged into `main` through
[PR #1](https://github.com/Marchini-Pedro/Grandfathers-Tarot/pull/1) on 2026-10-03.
The old recovery branch has been deleted from GitHub. Offline checks pass on
Lua 5.5 and LuaJIT 2.1; remaining game checks are recorded in the verification
matrix and recovery review. A merge does not establish in-game acceptance.

The runtime version remains `2.0.0`. Workshop build logs use the historical
`2.1.0` milestone label; no new release or version bump accompanied recovery.
The last tagged release is `v1.13.0`.

The [2026-10-03 adversarial audit](audits/2026-10-03/report.md) is now
complete offline: seven reproduced findings, a test/mutation map, measured
Lua lifecycle workloads and an exact live checklist. Approved runtime fixes are
tracked in the [remediation log](audits/2026-10-03/remediation.md); live acceptance
remains pending.

The reusable audit brief was merged into `main` through
[PR #3](https://github.com/Marchini-Pedro/Grandfathers-Tarot/pull/3) at `44e536f`.
[PR #4](https://github.com/Marchini-Pedro/Grandfathers-Tarot/pull/4) merged at
`6d5756d`, retaining the completed audit and six remediation batches.
The [post-merge coverage review](10-ci-and-coverage.md) records the standalone
CI runner, measured Lua module floors, added regressions and remaining limits.
These changes were merged through
[PR #5](https://github.com/Marchini-Pedro/Grandfathers-Tarot/pull/5) at `03785e3`;
the first hosted PR and main runs pass both runtimes. Required merge checks
await owner setup.

Enemy colour experiments were merged through
[PR #7](https://github.com/Marchini-Pedro/Grandfathers-Tarot/pull/7) at `c7cf1da`
after PRs #5 and #6. The [method guide](enemy-appearance.md) distinguishes
usable experiments from advanced prerequisites; in-game acceptance is pending.

[PR #8](https://github.com/Marchini-Pedro/Grandfathers-Tarot/pull/8) merged on
2026-10-03 at `fe957632`. The earlier hand-off remains historical; merge alone
does not establish acceptance of its pending native checks.
Current work is `feature/card-effects-and-ui` for PR #9: three beneficial faces,
native effects, completion audio, appearance controls and compact HUD/editor fixes.
See [the feature guide](12-card-effects-and-ui.md) and current verification log.

## References

| Document | Purpose |
| --- | --- |
| [Card effects and UI (PR #9)](12-card-effects-and-ui.md) | Behavior, native contracts, compatibility and game acceptance |
| [Design and rationale](04-design-and-rationale.md) | Requirements, architecture and protocol decisions |
| [Enemy colour experiments](enemy-appearance.md) | Per-group ARGB/method controls, usable experiments, prerequisites, transport and live acceptance |
| [Enemy appearance research](research/enemy-appearance/findings.md) | Earlier read-only source/mod/public evidence; [experiment plan](research/enemy-appearance/experiments-and-recommendation.md) and [original brief](research/enemy-appearance/research-prompt.md) |
| [Implementation plan](05-implementation-plan.md) | Checklist, reuse map and unfinished work |
| [Verification and open issues](06-verification-and-open-issues.md) | Game test matrix, risks and dated results |
| [Learnings and gaps](07-learnings-and-gaps.md) | Discoveries, failed approaches and actionable gaps |
| [Workshop redesign](08-workshop-redesign.md) | Cauldron/Mirror design and build log |
| [Heresy continuation review](audits/2026-10-03/heresy-review.md) | Branch-wide adversarial findings, fixes, detecting regressions and remaining native checks |
| [Hand-off 2026-10-03](11-handoff-2026-10-03.md) | State of `feature/heresy-card-and-ui-pass`, what is left (CI coverage floors, in-game checks) and a prompt to resume the work |
| [Recovery review](09-recovery-review.md) | Recovered history, fixes, validation and remaining limits |
| [CI and coverage](10-ci-and-coverage.md) | Post-PR #4 measurements, gate policy, local commands and required GitHub checks |
| [Executed audit](audits/2026-10-03/report.md) | Baseline, ranked findings, reproductions, inventory, measurements and live acceptance |
| [Approved remediation](audits/2026-10-03/remediation.md) | Six implementation batches, current results and [runnable validation](audits/2026-10-03/remediation-validation.md) |
| [Adversarial audit prompt](audits/adversarial-audit-prompt.md) | Reusable audit-only brief: risk-based tests, lifecycle/scaling stress, measurements and evidence requirements; not an executed audit |
| [Changelog](CHANGELOG.md) | Change history; [1.x archive](changelog/1.x.md) |
| [TwitchVersus findings](01-findings-twitchversus.md) | Historical TwitchVersus and VersusMode audit |
| [RealmsEvent findings](02-findings-realmsevent.md) | Historical RealmsEvent audit |
| [Realms and game-source findings](03-findings-realms-and-game-source.md) | Network API, authority, spawn chain, positioning and limits |

## Resuming development

1. Read [CLAUDE.md](../CLAUDE.md), then the design, implementation plan and the
   current verification/recovery notes for the area being changed.
2. Reuse the existing audits. Check their reference versions before trusting
   file/line citations; re-check only changed components or unanswered questions.
3. Keep user guidance in the root README, detailed changes in the changelog,
   and findings/results in their existing documents. Update superseded text.
4. Keep every Markdown file under 100 KB; run `python tools/check_docs.py`.

## Historical audit versions

These are the original author's reference snapshots, audited on 2026-09-28.
They are not a list of currently installed or verified versions on every machine.

| Component | Audited reference |
| --- | --- |
| TwitchVersus | 1.0.0, author Rikara |
| RealmsEvent | 2.0.0 |
| VersusMode | 3.3.0 in metadata and entry script; descriptor says 3.0.58 |
| Realms Server | 1.0.0-rc2; requires SoloPlay |
| DTRealmsGhostHost | 0.1.1, author Rikara |
| Darktide source | `0f0cb45991e9305ef4a7b925370792d7d6035f95` (1.12.5); relevant hooks/calls re-checked at `419fe18d4` (1.13.0, 2026-09-29) |

Eduardo's installed Realms metadata reports `1.0.0` as of 2026-10-03; it differs
from the original audit snapshot. The dated adversarial report re-checks the installed network routing, dispatch
and delivery contracts against matching author source. It does not audit the
whole release or its native DLLs.

Historical mod paths are relative to `Content/mods/`; game paths marked `S/`
are relative to `Content/Darktide-Source-Code/scripts/`. References to the
original author's Vortex staging directory describe that machine. Treat staged
mods as read-only references and follow the local install's actual paths.
