# Heresy branch adversarial continuation review

Reviewed 2026-10-03 at the user's request to audit, fix actionable gaps, resume
the hand-off and open a PR. The reusable audit brief informed the evidence
standard; its default audit-only boundary is superseded by the explicit request
to fix this branch. This is a review of the new branch changes, not a repeat of
the earlier whole-project audit.

## Baseline and scope

- Remote hand-off: `a95ee8b`, `feature/heresy-card-and-ui-pass`; comparison base
  current main `1290abc`. All 13 branch commits, including merge `56062d3`, were
  inspected through their resulting diff: 39 files, 2,415 added / 252 removed
  lines. The working tree started clean in a separate worktree. Older checkouts,
  the supplied copy and installed mods were preserved.
- Main's later documentation-only commit was merged at `e3c0c46`. Additive
  README/changelog conflicts were resolved with both the feature history and
  PR #7's actual merged status intact.
- Python 3.13.13; pinned Lupa 2.8; `lua55` and `luajit21`; Pillow 12.2.0 for
  widget previews. The runner disables JIT tracing for source-line collection
  and suspends hooks during existing allocation probes. Uninstrumented checks
  and mutation experiments run separately.
- Narrow unanswered source questions were checked against local game reference
  `419fe18d414a618ce0474bd015bab470afb446d6`: boss initialization, health fields
  and the spawn call. Installed Realms 1.0.0's
  `protocol/mod_network_protocol.lua:9, 148-170` checks the **encoded** 96 KiB
  envelope. This is source-contract evidence, not live transport evidence.
- No game session, native renderer, networking session, process-memory soak or
  new dependency-wide audit was run. The target tests load this worktree's Lua
  files and repository-owned engine fixtures.

Both initial full runners passed every behavior harness: 2,092 printed
assertions each, 34 compiled Lua inputs. Their coverage gates failed, with
scores 81.93% on Lua 5.5 / 78.70% on LuaJIT. The hand-off correctly identified
two uninventoried HUD modules and Face's 81.98/82 failure, but omitted editor
definitions' LuaJIT 77.98/79 failure.

## Confirmed findings and repairs

All findings below are confirmed by source traces and stubbed execution.
Severity describes the tested failure, not a claim of a reproduced game crash.
Regression assertions are in the existing harnesses and remain runnable from a
standalone checkout.

| ID | Severity | Trigger, observed failure and minimal repair | Regression evidence |
| --- | --- | --- | --- |
| H1 | Medium | A boss has initial health at or above normal because Havoc adds health, then custom health lowers it. The game leaves `_is_weakened` **nil**, while the fixture supplied `false`. `Tuning.set_exact_health` skipped the correction for nil. Correct the fixture and write the boss flag whenever the boss extension exists. | Existing 80% + 50% Havoc assertion fails with the corrected nil fixture; it passes after the guard repair. Untuned bosses retain nil. |
| H2 | Medium | A native health-field write throws after a unit disappears. The previous code changed local `_health` first, leaving authoritative local health inconsistent with the replicated value. Perform the native write before committing local health and the boss flag. | Fault-injected setter rejection must leave local health unchanged. Existing missing-object, missing-manager and unrelated tuning checks remain active. |
| H3 | High | A test target disappears while its facing rotation is read. Argument evaluation occurred outside `pcall` after `Bypass.begin_spawn`, so the error escaped with the spawn bypass still active. Put rotation evaluation and the native spawn inside the same protected call; always release the bypass. | A close-wave fixture returns no facing rotation and makes the fallback rotation throw. Before repair the assertion fails; after repair the wave produces no unit, contains the error and clears `Bypass.spawning`. |
| H4 | Medium | A large legal preset contains many quotes/backslashes in names. A 50,000-byte quoted string passes the raw 90,000-byte check but expands beyond Realms' encoded 96 KiB cap. Earlier trimming could also leave an unshareable first card, so failed sends preserved an obsolete host pool. Check encoded-string size with 1 KiB envelope headroom, and find the largest fitting prefix by bounded binary search. Send a valid empty preset if no card fits. | Protocol tests reject escaped overflow and encoding failure while accepting plain text at the raw limit. Director tests trim a quote-heavy 100-card deck, preserve sealed preset parsing/order, and clear a previous pool when the first card exceeds a 50-byte fixture limit. |
| H5 | Medium | Stop after a card was drawn. The host hides its window after dropping `host_state`, but the final client snapshot retained `lc`; client age then kept increasing. Clear the host's last card before sending stop and ignore last-card fields in off snapshots. | Deliver the actual final stop snapshot to a client and require no last card; also deliver an older-style off snapshot that still contains `lc`. |
| H6 | Low | With a three-line tile name, composition ends at y=153 while modifiers start at y=148. The prior test allowed seven units of overflow. Keep composition inside its actual available height: four, three or one lines for one, two or three name lines. | Tighten the geometry invariant to y<=146 and verify the painted long-name tile. Existing summary counts and popup/drag/input checks still run. |
| H7 | Low | Stationary hover on a cooldown control at its limit paints every frame: raw pointer direction stays -1/+1 while the clamped preview is zero. Separate cached pointer direction from effective preview direction; timed cards have no preview. | Count repaint calls across 100 unchanged frames at the minimum: 100 before, zero after. This is avoided work/allocation, not a frame-time benchmark or leak claim. |
| H8 | Low | Refresh fails while a good last-card widget is visible. Clearing the cached card alone leaves partially repainted content visible. Hide the widget on refresh failure and rebuild on the next good card. | Start from a visible good card, feed a malformed card, require hidden content and one error, then require recovery with a good card. |
| H9 | Low | A valid long modifier list wraps under the last card, but its box and panel reserved only one line. Use the existing wrap estimator with a conservative uppercase width and up to eight lines; grow the panel to the resulting height within a 320-unit node. Existing name estimates retain their three-line default. | A 96-byte list of twelve modifiers requires six lines of room and must fit inside the panel. Restoring the single-line height fails this assertion on both VMs. |

Source references in the repaired tree:

- [Health correction](../../../scripts/mods/RealmsWaves/spawn/tuning.lua),
  `set_exact_health:214`, synchronized write:238, boss flag:245.
- [Spawn protection](../../../scripts/mods/RealmsWaves/spawn/execute.lua),
  `spawn_one:597`, protected facing/spawn:625.
- [Wave transport](../../../scripts/mods/RealmsWaves/core/protocol.lua),
  encoded budget:39, `waves_text_fits:417`, send validation:427;
  [director](../../../scripts/mods/RealmsWaves/core/director.lua), trimming:159,
  stop cleanup:958, off-snapshot validation:1175.
- [Tile geometry](../../../scripts/mods/RealmsWaves/ui/deck.lua), `layout:226`;
  [cooldown painting](../../../scripts/mods/RealmsWaves/ui/wave_editor_deck.lua),
  pointer cache:326, update comparison:859.
- [Last-card refresh](../../../scripts/mods/RealmsWaves/ui/hud_element_last_card.lua),
  modifier height:270, failure cleanup:358.

## Risk-to-test map and reviewed inventory

| Reviewed change | Invariant and evidence | Remaining boundary |
| --- | --- | --- |
| Exact health / spawn execution | Original Havoc arithmetic tests now model nil boss flags; rejected writes and vanished facing targets fail closed; unmodified groups keep native health. | Actual damage, boss bar naming on host/clients, Havoc and other hook combinations. |
| 100 cards / presets / protocol | 100 keys, slots 88/89, order, draw, timers, import/export, pooled count, sealed truncation, escaped overflow and empty pool updates. Existing queue/live-unit caps remain unchanged. | Native RPC framing, delivery/rejection timing and large saved-profile latency. |
| Last-card director / HUD / entry settings | Tarot/random success, rejected start, test exclusion, mission reset, table reuse, field validation, stop, pause, options, Custom HUD sample, font fallback and error recovery. | Actual HUD rendering, modifier wrapping, native event order and multiplayer aging when no hero is alive. |
| HERESY / card themes | Alias migration through saved settings, imports and wire cards; special frame/glow/banner; shared theme updates/restoration; shape pass audits. | Native fonts/materials and visibility at different UI scales. |
| Shelf / cooldown / Deck | Six rows, smaller chips, retained faction controls; numeric input bounds, fixed-timer display, hover, right-click, page offset, popup suppression, geometry and stationary-hover work. Existing drag-cancellation tests remain. | Real cursor/controller timing, 1080p/1440p/4K readability and engine frame time. |

The reviewed runtime diff includes the entry script, settings and localization;
catalog `cards`, `events`, `presets`; core `director`, `protocol`; spawn `execute`,
`positions`, `tuning`; UI `deck`, both new last-card files, `hud_element_waves`,
`spread`, all seven changed editor files, `workshop` and `workshop_blueprints`.
The four original changed harnesses and all ten changed documentation files
were also reviewed. Existing appearance integration is retained through main's
merge and its 79-assertion suite. Unchanged project modules remain covered by
the full runner; the earlier whole-project audit is preserved separately.

The new checks reproduce actual failures before repair. Nine isolated reverse
mutations restore the nil guard, premature local health write, unprotected
facing call, raw-only send guard, off-snapshot retention, overflowing composition,
repaint comparison, stale-HUD cleanup and single-line modifier height. Each mutant must compile and fail its
named behavior assertion on both runtimes; syntax errors are not detections.
Raw scratch outputs live under ignored `test-results/audit/`. To reproduce
without those outputs, reverse the specific repaired source change and run
the corresponding tracked harness with `RW_LUA_RUNTIME=lua55` and `luajit21`.

Source-line floors are proxies, including delimiters/declarations. The new HUD
floors are 86 and 77 from the lower measured VM score. Face becomes 81 and
editor definitions 77 because these source edits changed the denominator and
LuaJIT declaration events. Behavior assertions were strengthened; none were
removed to get a passing gate. The aggregate 78 floor and every other existing
floor remain unchanged. Final measured results are in
[the coverage review](../../10-ci-and-coverage.md).

## Verification and remaining work

Run from the repository root:

```powershell
python -m pip install -r tools/requirements-test.txt
python tools/run_tests.py --runtime lua55 --output-dir test-results/lua55 --timeout-seconds 280
python tools/run_tests.py --runtime luajit21 --output-dir test-results/luajit21 --timeout-seconds 280
```

Both full runners pass 2,104 assertions, 34 compilation inputs and all module
coverage gates: Lua 5.5 81.97% / LuaJIT 2.1 78.75%. All nine compiling reverse mutations
are detected on both runtimes (18/18). Markdown/link/whitespace checks and real
widget previews complete the offline acceptance evidence. The largest-prefix search
needs at most seven prefix probes for 100 cards, plus the original encode;
existing 64-job / 8,000-entry queue caps still bound spawning. No throughput,
native memory-retention or end-to-end multiplayer performance claim is made.

Publish a draft PR and keep the branch unmerged. Game matrix rows 114-121 and
the [enemy appearance checks](../../enemy-appearance.md) remain pending.
Add stop-after-draw on both peers, quote-heavy pooled decks, long tile names
with modifiers, limit-hover stability, vanished targets and recovery after
HUD errors to those live checks. Follow the existing multi-match/soak checklist
for native resources. Repository administration remains an owner task; this
identity has push/write permission and no admin/maintain permission.
