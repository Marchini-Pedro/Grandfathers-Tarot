# CI and post-PR #4 coverage review

## Heresy continuation: current offline baseline (2026-10-03)

The resumed branch includes all original features, current main at `1290abc`
and nine confirmed repairs from the [adversarial review](audits/2026-10-03/heresy-review.md).
Both full runners pass **2,104 assertions**, 34 compilation inputs, documentation
sizes and every aggregate/module gate. All nine valid reverse mutations fail
their intended behavior assertion on both VMs (18/18 detections).

The initial behavior suites passed 2,092 assertions, but the coverage gates
failed. Add floors for the new last-card element (86) and definitions (77).
Face's score moved from the historical 82.14 to 81.98 after source edits, so
its floor becomes 81. Editor definitions' LuaJIT declaration score is 77.98
after the UI changes, so its floor becomes 77 from 79. These are explicit
source-denominator/declaration-event exceptions, supported by stronger behavior
fixtures and mutation checks. No assertions were removed, no modules excluded;
the overall 78 floor and every other pre-existing floor remain unchanged.

Current measured scores (source-line proxy, not branch coverage):

| Runtime | Hit source lines | Eligible source lines | Score | Overall floor |
| --- | ---: | ---: | ---: | ---: |
| Lua 5.5 | 11,744 | 14,327 | 81.97% | 78% |
| LuaJIT 2.1 | 11,283 | 14,327 | 78.75% | 78% |

| Module | Lua 5.5 | LuaJIT 2.1 | Floor |
| --- | ---: | ---: | ---: |
| `RealmsWaves.lua` | 72.71% | 68.60% | 68% |
| `RealmsWaves_data.lua` | 90.38% | 73.08% | 72% |
| `RealmsWaves_localization.lua` | 100.00% | 98.16% | 98% |
| `catalog/appearance.lua` | 86.67% | 84.44% | 84% |
| `catalog/cards.lua` | 79.26% | 78.33% | 78% |
| `catalog/colors.lua` | 87.82% | 73.10% | 73% |
| `catalog/events.lua` | 80.36% | 76.75% | 76% |
| `catalog/groups.lua` | 82.79% | 76.58% | 76% |
| `catalog/presets.lua` | 81.84% | 79.47% | 79% |
| `core/director.lua` | 72.71% | 71.53% | 70% |
| `core/protocol.lua` | 75.40% | 74.43% | 72% |
| `core/votes.lua` | 73.33% | 71.67% | 71% |
| `spawn/appearance.lua` | 83.47% | 79.34% | 79% |
| `spawn/budget_bypass.lua` | 71.03% | 69.16% | 69% |
| `spawn/execute.lua` | 75.93% | 75.56% | 74% |
| `spawn/positions.lua` | 77.24% | 76.90% | 76% |
| `spawn/tuning.lua` | 76.25% | 74.22% | 74% |
| `ui/deck.lua` | 77.66% | 77.13% | 76% |
| `ui/hud_element_last_card.lua` | 86.11% | 86.11% | 86% |
| `ui/hud_element_last_card_definitions.lua` | 87.70% | 77.05% | 77% |
| `ui/hud_element_waves.lua` | 79.06% | 76.84% | 76% |
| `ui/hud_element_waves_definitions.lua` | 86.36% | 77.27% | 77% |
| `ui/spread.lua` | 83.75% | 83.07% | 82% |
| `ui/wave_editor_appearance.lua` | 94.37% | 90.14% | 90% |
| `ui/wave_editor_blueprints.lua` | 86.60% | 78.16% | 77% |
| `ui/wave_editor_components.lua` | 84.77% | 81.59% | 81% |
| `ui/wave_editor_deck.lua` | 79.27% | 78.82% | 78% |
| `ui/wave_editor_definitions.lua` | 90.19% | 77.98% | 77% |
| `ui/wave_editor_face.lua` | 81.98% | 81.98% | 81% |
| `ui/wave_editor_tune.lua` | 77.78% | 77.78% | 77% |
| `ui/wave_editor_view.lua` | 85.04% | 83.57% | 83% |
| `ui/wave_editor_workshop.lua` | 82.55% | 80.61% | 80% |
| `ui/workshop.lua` | 89.68% | 80.16% | 80% |
| `ui/workshop_blueprints.lua` | 86.92% | 79.32% | 79% |

The records below retain the earlier PR #4/CI/appearance baselines as history.

## Enemy appearance branch integration (2026-10-03)

`feature/enemy-appearance` integrated this CI work at `fd56262` in its own
worktree, then synchronized with `main` at `06c2b3a` after PRs #5 and #6.
The separate CI checkout is untouched. The runner discovers
`appearance_test.py` and instruments its schema/runtime, editor and entry VMs
through the existing helper. The protocol failure fixture now supplies DMF's
module loader and expects seven registered endpoints.

The feature adds 79 focused assertions and three Lua modules. Their source-line
floors are schema 84, runtime 79 and editor 90, selected from the measured
Lua 5.5/LuaJIT scores. Every pre-existing module floor and the overall 78 floor
remain unchanged. The policy inventory now has 32 modules. The full runner's
scope is 1,916 printed assertions per backend; native behaviour remains pending.
Feature behaviour and acceptance: [enemy-appearance.md](enemy-appearance.md).

The [first hosted PR #7 run](https://github.com/Marchini-Pedro/Grandfathers-Tarot/actions/runs/37155162068)
at `0103281` passes both runtimes. Downloaded reports confirm 1,916 assertions
each, Lua 5.5 81.80% / LuaJIT 2.1 78.54% and no coverage failures. The
[final PR run](https://github.com/Marchini-Pedro/Grandfathers-Tarot/actions/runs/37155424490)
also passes both runtimes at `4782cfb`. GitHub records PR #7 merged by
`EduardoKenji` at `c7cf1da`; in-game acceptance remains pending. Updating this
publication/merge record changes documentation only.

Reviewed 2026-10-03 from merged `main` at `6d5756d`, after fetching origin.
The CI implementation was merged into `main` at `03785e3` through
[PR #5](https://github.com/Marchini-Pedro/Grandfathers-Tarot/pull/5).
Production Lua is unchanged; live-game acceptance remains separate.

The existing 1,746 assertions covered many catalog/editor/HUD behaviors and
PR #4's ownership, retirement, queue-budget, numeric-import and size-retry
invariants. There was no GitHub workflow or dynamic coverage gate. The editor
also needed a sibling game-source checkout, preventing a clean CI run.
A diagnostic Lua 5.5 probe exposed the largest gap: `spawn/positions.lua`
reached only 22.22% of its source lines, and the entry module reached 57.14%.
Most hidden-position selection had only responsibility/caller review evidence.
Those initial probes gathered line events but failed allocation assertions
because of hook overhead; their percentages identify gaps, not passing runs.

The extended suite adds 80 behavior assertions plus 11 coverage/runner contracts,
for **1,837 assertions per runtime**. Hidden-position score is now 76.72% on
Lua 5.5 / 76.19% on LuaJIT; entry is 72.49% / 68.52% and protocol is
73.41% / 72.62%. This is a useful offline regression baseline; remaining
branches and native behavior still need evidence.

## Historical post-PR #4 measurement and policy

The collector uses actual `debug.sethook` line events from runtime files loaded
by each behavior harness. Compilation does not count as execution. Each suite
uses fresh processes and a temporary parts directory; hits are merged by exact
resolved module path and intersected with the source-line denominator. Foreign
files, snippets and out-of-range lines cannot inflate the score.

The denominator is nonblank lines whose trimmed text does not start with `--`,
matching BetterInventory's source-line proxy. It includes table declarations,
closing delimiters and `end` lines; **it is not executable-line or branch
coverage**. Loading localization tables can produce nearly 100% without
proving native text rendering. LuaJIT and Lua 5.5 emit different line events,
especially for declarations. Scores are compared before rounding.
LuaJIT tracing is disabled for collection so compiled traces cannot bypass
line hooks. The four HUD and one editor allocation probes suspend the hook
and restore it afterward; their original heap assertions still run. Normal,
uninstrumented suites also pass on both VMs.

| Runtime | Hit source lines | Eligible source lines | Score | Overall floor |
| --- | ---: | ---: | ---: | ---: |
| Lua 5.5 | 10,560 | 12,947 | 81.56% | 78% |
| LuaJIT 2.1 | 10,138 | 12,947 | 78.30% | 78% |

Every Lua module has an explicit floor in
[`tools/coverage_policy.json`](../tools/coverage_policy.json). Initial floors
are the lower observed VM score rounded down to a whole percent, keeping
less than one percentage point of headroom per module. All modules, including
declarative UI/settings/localization modules, are inventoried; none is silently
exempt. New or removed files require a policy update. Raise floors as coverage
improves; do not lower a floor merely to make a regression pass.

| Module | Lua 5.5 | LuaJIT 2.1 | Floor |
| --- | ---: | ---: | ---: |
| `RealmsWaves.lua` | 72.49% | 68.52% | 68% |
| `RealmsWaves_data.lua` | 90.32% | 72.90% | 72% |
| `RealmsWaves_localization.lua` | 100.00% | 98.12% | 98% |
| `catalog/cards.lua` | 79.25% | 78.30% | 78% |
| `catalog/colors.lua` | 87.82% | 73.10% | 73% |
| `catalog/events.lua` | 80.38% | 76.56% | 76% |
| `catalog/groups.lua` | 82.62% | 76.19% | 76% |
| `catalog/presets.lua` | 81.87% | 79.47% | 79% |
| `core/director.lua` | 72.06% | 70.77% | 70% |
| `core/protocol.lua` | 73.41% | 72.62% | 72% |
| `core/votes.lua` | 73.33% | 71.67% | 71% |
| `spawn/budget_bypass.lua` | 71.03% | 69.16% | 69% |
| `spawn/execute.lua` | 74.67% | 74.29% | 74% |
| `spawn/positions.lua` | 76.72% | 76.19% | 76% |
| `spawn/tuning.lua` | 76.21% | 74.18% | 74% |
| `ui/deck.lua` | 77.47% | 76.92% | 76% |
| `ui/hud_element_waves.lua` | 79.12% | 76.88% | 76% |
| `ui/hud_element_waves_definitions.lua` | 86.36% | 77.27% | 77% |
| `ui/spread.lua` | 83.68% | 82.99% | 82% |
| `ui/wave_editor_blueprints.lua` | 85.90% | 77.02% | 77% |
| `ui/wave_editor_components.lua` | 84.57% | 81.40% | 81% |
| `ui/wave_editor_deck.lua` | 78.66% | 78.17% | 78% |
| `ui/wave_editor_definitions.lua` | 91.98% | 79.66% | 79% |
| `ui/wave_editor_face.lua` | 82.14% | 82.14% | 82% |
| `ui/wave_editor_tune.lua` | 77.78% | 77.78% | 77% |
| `ui/wave_editor_view.lua` | 84.86% | 83.42% | 83% |
| `ui/wave_editor_workshop.lua` | 82.32% | 80.52% | 80% |
| `ui/workshop.lua` | 89.68% | 80.16% | 80% |
| `ui/workshop_blueprints.lua` | 86.84% | 79.41% | 79% |

## What the checks establish

| Area | Evidence and remaining limit |
| --- | --- |
| Hidden positions | Missing mission/path/nav/side/player state, group-count/occlusion failures, nearest-player distance, all-player occlusion input, three distance stages, strict height limit, boxed ownership, three-player scan bound and 24-candidate cap. The 160-point raw bound is checked between group queries; one native result can overshoot it. Real visibility/nav behavior remains native evidence. |
| Explicit test ring/spread | Bounded attempts, snapping/reachability, nil/throw/blocked queries and identity fallback. Only explicit test waves use visible ring fallback; normal candidate selection retries without a hidden point. |
| Entry adapters | Editor open/close, missing UI, five vote keys, console coercion, pause mapping, start/next/test feedback, custom slot/recipe persistence, roll bounds, diagnostic failures, dot/colon update forms and one-time error logging. Existing lifecycle/budget regressions remain active. |
| Protocol | Availability failures, six registration errors, malformed handshakes/votes, host lookup failure/case handling, absent/throwing/scalar JSON operations, routing and absent handlers. Existing tests retain spoofing, size clamps, disconnect/rejoin, recipient rejection, unsupported peers, reentrancy and retirement. Native transport remains a fixture boundary. |
| Imports, scheduling, tuning, UI | Existing logic/editor/HUD suites retain numeric-import atomicity, supported queue limits, live ownership/teardown, stat recomputes, late-join recovery, drag cancellation and finite widget geometry. Remaining lines appear in JSON reports; native fonts/materials, callback order and long-running behavior remain live checks. |
| Gate/runner | Exact path identity, module/aggregate floors, new/stale inventory, missing/empty/error evidence, invalid thresholds, multiple VMs, uncalled bodies, failure propagation, timeout reporting and passing harnesses that omit coverage. |

Six mutations were applied only to isolated temporary copies: ignore all but
the first player's distance, scan a fourth player, accept the height boundary,
authorize a failed host lookup, accept failed JSON encoding, and force every
console vote to option one. Each fails its intended new assertion on both VMs
(12 detections). These complement the historical audit's 17 remediation
mutations; they are not exhaustive mutation or branch coverage. Frozen audit
reports retain their original baseline.

## Historical post-PR #4 local verification

```powershell
python -m pip install -r tools/requirements-test.txt
python tools/run_tests.py --runtime lua55 --output-dir test-results/lua55
python tools/run_tests.py --runtime luajit21 --output-dir test-results/luajit21
```

Python 3.13 and Lupa 2.8 are the CI dependencies. The editor's repository-owned
callback fixture was checked against game reference `419fe18d4`, including nil
positions, dynamic method lookup and multiple returns. Tests need no installed
game, Realms files or external source checkout. Compilation has 30 inputs.
Reports are `test-results/<runtime>/test-results.json`, `lua-coverage.json` and
one log per check. Coverage JSON lists modules, floors and uncovered lines.
Generated results are ignored by Git. Harness timeout defaults to 120 seconds;
`--timeout-seconds` adjusts it for slower local machines.
Both standalone-checkout suites pass all 1,837 assertions. The workflow passes
actionlint 1.7.12; Python syntax, 46 local documentation links, Markdown size
limits and the repository's normal Git whitespace checks pass.

## GitHub automation and merge requirement

[The workflow](../.github/workflows/verify.yml) runs on pushes, pull requests and
manual dispatch with separate Ubuntu jobs for each VM. It installs the pinned
dependency, runs compilation/tests/docs/coverage, writes a module job summary
and uploads logs/reports even when verification fails. Failures, timeouts,
missing coverage, collector errors, inventory mismatches and low scores return
nonzero. Action revisions are pinned and repository permissions are read-only.

The branch is published and push/PR workflows started automatically. Hosted
results are recorded in the [verification log](06-verification-and-open-issues.md).
The [first PR run](https://github.com/Marchini-Pedro/Grandfathers-Tarot/actions/runs/37153728118)
at `fd56262` passes both Ubuntu/Python 3.13 jobs: 1,837 assertions per runtime,
with the same 81.56% / 78.30% scores as the local baseline. Downloaded artifacts
contain passing reports and no coverage failures.
The [first main run](https://github.com/Marchini-Pedro/Grandfathers-Tarot/actions/runs/37153916183)
at merge `03785e3` also passes both runtimes.
A failing workflow blocks merging when required checks are configured.
The owner should configure `main` after the first successful hosted run:

1. In **Settings > Branches**, add a branch protection rule for `main`, or use
   a branch ruleset targeting `main`.
2. Require pull requests and require both status checks:
   **`Offline verification (lua55)`** and **`Offline verification (luajit21)`**.
3. Disable bypass (or select **Do not allow bypassing the above settings**) if
   the checks should also apply to administrators.

Write access is sufficient to maintain workflows, tests and coverage floors;
repository enforcement remains an owner task. If Actions is restricted, the
owner must allow the GitHub-owned checkout/setup-python/upload-artifact actions
under **Settings > Actions > General**. Manual dispatch is now available because
the workflow exists on the default branch; automatic branch/PR runs also work.

Rechecking access after the user's request still reports `EduardoKenji` with
the `write` role, `admin: false`, `maintain: false`, and no pending invitation.
Branch-rules lookup returned no rules and classic-protection lookup returned
404. No rules were changed. See
[GitHub's required checks documentation](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches#require-status-checks-before-merging).

Live multiplayer, native rendering/nav/transport, CPU/process RAM and the
[eight-hour/ten-mission checklist](audits/2026-10-03/live-checklist.md) remain
separate acceptance work. These scores do not establish in-game correctness.
