# GrandfathersTarot adversarial audit — 2026-10-03

Offline audit of `8c81c1bbfb6107788dafa98f56c6194dcaa80421`, dated in
America/Sao_Paulo. **Seven findings were reproduced at this frozen revision.**
The existing checks pass, but they miss event-manager retention, disabled
spawning, stop/pause ownership boundaries, aggregate queue pressure and Realms
partial-delivery semantics. Game rendering, multiplayer and the eight-hour
session remain pending. This is an offline report, not release acceptance.

After review, the user authorized code changes. The separate
[remediation log](remediation.md) records implemented fixes and current checks;
findings, line references and diagnostic expectations below retain the pre-fix baseline.

Companions: [inventory and test map](inventory-and-tests.md),
[measurements](measurements.md), [reproduction scripts](reproduction.md),
[live acceptance](live-checklist.md).

## Baseline and controls

| Component | Frozen reference |
| --- | --- |
| Target | `mod_creations/Grandfathers-Tarot`, clean `docs/adversarial-audit-brief`; full revision above |
| Main / origin main | `3e6be468fe6ea7524b5acb4b31ac282f7c9bed0c`; target adds documentation only |
| Game log | `console-2026-10-03-16.14.09-5cf701ea-0cd1-4bd5-a3c8-efcf921d2868.log`: `1.13.0-b806782`, svn `138291` |
| Local game source | clean `419fe18d414a618ce0474bd015bab470afb446d6`, 1.13.0 |
| Published comparison | `7e662fcda16219d775b84af50322be2e9cd9d62e`, 1.13.1; fetched separately, baseline unchanged |
| Installed Realms | metadata `1.0.0`; relevant files byte-match author revision `a4564b7dda7c6fdbd92eb633c1931b1a51a749ae` |
| Installed DMF | no reliable installed version label established; events, toggling and loader byte-match `fc08c1cb772f86248c7ae9e957543e801a0dbf64` |
| SoloPlay | installed metadata `2.6.9`; no wholesale dependency audit |
| BetterInventory | `dccb06d8e542f7ce79ab847d5c742ad0c01c2ae5`; read-only, pre-existing untracked investigations preserved |
| Supplied recovery copy | `6b95382b30dee027eea2fa496f7e8d362756f4ce`; read-only |
| Runtime | Python 3.13.13, Lupa 2.8; Lua 5.5 and LuaJIT `2.1.1774896198` / Lua 5.1 |
| Hardware | Ryzen 7 7800X3D, 8 cores / 16 threads; 33,514,549,248 bytes physical RAM; game log RTX 5090, driver 61047 |

The game's LuaJIT build and native allocator equivalence to Lupa are unknown.
Do not convert these heap or timing numbers into game frame-time predictions.

`baseline.json` in `.git/audit/2026-10-03/` contains full tracked SHA-256
manifests, initial dirty states, dependency manifests, load order and hardware.
Installed GrandfathersTarot differs in 14 of the 30 compared runtime/descriptor files
and lacks 16. Its live results cannot accept this checkout. RealmsEvent and
other wave/spawner mods occur in the saved load order and require controlled
compatibility sessions.

All experiments use fresh VMs, synthetic settings and fake unit handles. Real
presets/profiles are never applied or modified. A supplementary, read-only
saved-config capture records windowed 1920×1200, English, installed mode
`random`, max alive 120, max per wave 80, intervals 150–300. It was captured
after the first synthetic runs and **was not an input to measurements**;
missing newer settings do not establish their runtime defaults. Full saved
configuration hash: `7e902a9b66c811218d7650d285522363a3fc6ae7d1471a47823ac1e017655977`.

## Ranked findings

P1 = address before acceptance because ownership or operational bounds break;
P2 = meaningful behavior/delivery defect. Confidence describes the tested
mechanism, not its frequency in a native session. All target line references
below are at the frozen target revision; engine references are at local 1.13.0.

| ID | Priority | Status / confidence | Finding |
| --- | --- | --- | --- |
| F01 | P1 | confirmed / high | Reload leaves old mod objects registered in the game event manager |
| F02 | P1 | confirmed / high | Disabling the mod leaves its update-driven spawner running |
| F03 | P1 | confirmed / high | Stop discards ownership and maintenance of enemies left alive |
| F04 | P1 | confirmed / high | Per-job cap allows a costly aggregate backlog under legal settings |
| F05 | P2 | confirmed / high | Pause freezes director clocks but feeds pending and repeating spawns |
| F06 | P2 | confirmed under send-rejection injection / high for contract, medium for live impact | Broadcast success discards size updates rejected by an individual peer |
| F07 | P2 | confirmed on LuaJIT / high | A checksummed preset can import NaN as a numeric setting |

### F01 — event registrations retain every unloaded generation

**Path:** [entry](../../../scripts/mods/GrandfathersTarot/GrandfathersTarot.lua),
registration lines 126/129, unload 179–199. Engine
`scripts/managers/event/event_manager.lua:10–20,23–43`; `StateGame` creates
`Managers.event` at `scripts/game_states/state_game.lua:172`.

**Trigger:** reload the mod repeatedly while the same game event manager lives.
Expected: each unloaded instance relinquishes its two subscriptions. Observed:
100 load/unload cycles retain 100 old mod instances, 100 objective subscriptions
and 100 death subscriptions, on both runtimes. LuaJIT collected heap grows
from 703.23 KiB after the first cycle to 28,277.11 KiB after the hundredth;
unregistering those objects in a scratch control leaves zero retained instances
and 427.13 KiB. Lua 5.5 agrees: 754.84 → 31,506.73 KiB, then zero retained
instances and 446.51 KiB.

**Root cause:** `register` stores `events[object] = callback_name` in a table
with weak **values**. The mod is a strong key; the callback name is a string.
`on_unload` never unregisters it. Retiring hooks and clearing unit tables do
not release this owner. The test's event-name-to-method map overwrites earlier
registrations and hides the lifetime. Weak-value tables do not weaken keys;
see the [Lua 5.1 weak-table contract](https://www.lua.org/manual/5.1/manual.html#2.10.2).

**Guards challenged:** `RW.dead`, bypass/tuning retirement, resets, two full
collections, and removal of scratch hook/view/command registries. None removes
the event keys. The actual DMF loader unloads hooks, contrary to the runtime
comment claiming hooks cannot be removed; hook-chain accumulation is not the
demonstrated retaining owner. The player-death dead guard suppresses its
behavior, but the objective callback also lacks that guard.

**Impact:** sustained Lua retention and obsolete subscriptions during reloads.
The measured hundreds of KiB per generation do **not** explain the historical
hundreds-of-MB crash by themselves. Native memory and real reload frequency
remain unmeasured.

**Minimal fix proposed:** unregister both events in unload, using the manager
that owns the registrations and tolerating a missing/destroyed manager. Keep
retirement as defense for already captured callbacks. **Regression:** real
EventManager, 100 generations, zero obsolete registrations/weak references
after unload; trigger an obsolete objective callback and verify no mutation.
Reproduce with `reload_probe.py` in the companion.

### F02 — disabled mod continues spawning

**Path:** entry `mod.update` at 226–242; descriptor data `is_togglable` at 41.
Installed DMF `modules/core/events.lua:42–50` and
`modules/core/toggling.lua:10–23`.

**Trigger:** queue two hounds in an active host mission, disable GrandfathersTarot
through DMF, then update 0.2 seconds. Expected: no additional wave units while
disabled. Observed: two units spawn while `mod:is_enabled()` is false; there
is no `on_disabled` handler. Reproduced through the actual installed DMF event
and toggle functions as well as the actual target entry callback, on both VMs.

**Root cause:** DMF disables hooks and removes HUD injection, but delivers
`update` to every mod. Entry and director never check the enabled state.
The visible HUD can disappear while spawn jobs keep running. Realms dispatch
does gate its callbacks on enabled state; that gate does not cover local updates.

**Guards challenged:** host/mission checks, DMF hook disabling, HUD removal and
Realms owner gating. None terminates the local job feeder.

**Impact:** enemies continue arriving after an explicit disable, with bypass
hooks disabled and different accounting. **Minimal fix proposed:** an explicit
disable lifecycle policy and enabled-state gate at the update owner. Cancel
pending work and define safe ownership of surviving units together with F03.
Do not merely hide the HUD. **Regression:** drive actual DMF disable/enable
around queued repeats; zero disabled spawns; enabling does not replay stale work.
Reproduce with `followup_probes.py` (`actual_dmf_disable`).

### F03 — stop drops live-unit ownership and stat maintenance

**Path:** `core/director.lua:873–891`, `spawn/execute.lua:714–727`,
`spawn/budget_bypass.lua:76–80`, `spawn/tuning.lua:901–909`.

**Trigger:** track a living hound, apply gap 50 / size 130, stop the director,
then let its native buff recompute run. Expected: stop scheduling work while
enemies explicitly left alive retain accounting and tuning. Observed: tracked,
tuned and known-size counts all fall from one to zero while the unit remains
alive. Attack-speed factor 2 is reasserted before stop, but a recompute after
stop remains at 1. Both runtimes agree.

**Root cause:** stop calls full `Execute.reset`, which clears bypass and tuning
ownership. That reset is appropriate at mission teardown; stop explicitly
leaves units alive. Recompute hooks look up the now-empty ownership map.

**Guards challenged:** alive checks, stat reset marker, retirement guards and
the stopped host-update branch. They cannot recover forgotten records.

**Impact:** restarting can admit another alive-cap budget while old wave
enemies survive; engine counter subtraction changes; later joins lose the
size snapshot. Source tracing also shows sized bursters lose their explosion
scaling lookup. Only stat recomputation/ownership loss were directly injected;
native cap/explosion consequences remain live checks.

**Minimal fix proposed:** distinguish cancellation of pending jobs/timers from
destruction of mission-owned unit records. Preserve maintenance and dead-unit
pruning while stopped; reserve full reset for mission teardown. **Regression:**
stop/restart with living tuned units, correct combined cap, maintained factors
and size snapshot, then despawn and verify all ownership releases. Reproduce
with `logic_probes.lua` and `followup_probes.py` (`stop_stat_recompute`).

### F04 — aggregate queue pressure escapes the per-job bound

**Path:** `spawn/execute.lua:23,305–400,614–661`;
`core/director.lua` fixed-timer update 638–680.

**Trigger:** all 32 local cards use legal five-second fixed timers, recipes
`60 hounds@60, 60 poxwalkers@60`, 500 percent normal/special multipliers,
one-second repeats lasting 3,600 seconds, per-wave limit 500, alive limit 10
held full. Expected: a bounded aggregate pending-work budget with backpressure.
Observed: at 30 simulated seconds, 192 jobs / 192,000 queued entries; at
160 seconds, 992 jobs / 992,000 entries. Five repetitions of each update size
agree on those counts.

**Root cause:** `MAX_QUEUE = 1000` applies to each job. New job admission has
no global job/queue bound. Repeats allocate before the feeder's heap guard.
The guard may stop admitting new work later, but cannot make existing repeat
expansion an aggregate budget. Spawn caps limit living units, not pending work.

**Guards challenged:** per-wave clipping, per-job cap, fixed-timer minimum,
repeat duration, job timeout, alive cap and heap guard. Each remains intact
in the reproduction. This is **not a demonstrated infinite-lifetime leak**:
durations/timeouts bound a job's lifetime, and full teardown releases the queue.

**Impact:** significant avoidable Lua pressure and update work at supported
settings. With tracing disabled, 30 seconds of blocked repeats retain
32,241.62 KiB active heap versus 444.16 KiB warm LuaJIT baseline; teardown
returns to 442.21 KiB in all five batches. Normal-JIT 160-second runs end with
up to 255,997.20 KiB sampled heap including transient/compiler allocations.
That endpoint is not a continuous peak measurement or a game heap prediction.

**Minimal fix proposed:** bound total jobs and pending entries at admission
and repeat expansion, with explicit skip/backpressure behavior; check capacity
before constructing large batches. Reuse existing queue accounting instead of
adding a scheduler framework. Exact aggregate limit is a remediation policy
choice. **Regression:** the 32-card fixture holds a declared global bound and
keeps progress/teardown correct under failed position queries and a full alive
cap. Reproduce with `benchmarks.py`; see measurement controls.

### F05 — pause still feeds queued and repeating work

**Path:** `core/director.lua:704–716,762–785,905–925`;
`spawn/execute.lua:614–711`.

**Trigger:** queue `2 hounds@2`, repeating each second for ten seconds, pause,
then run twenty updates of 0.2 seconds. Expected, from the command's promise:
wave clocks freeze and no additional units arrive. Observed: director
remaining time stays 1,199.99, but ten hounds spawn and a repeat job survives.

**Root cause:** host update respects pause, but `Director.update` still calls
`Execute.update`. The executor advances job age, repeats and the feeder.
**Guards challenged:** pause flag, frozen cooldown/fixed-timer clocks and host
authority. Existing pause checks use an executor stub that does no work.

**Impact:** a misleading control and continued pressure during a requested
pause. **Minimal fix proposed:** gate job clocks/repeats/feeding while preserving
live-unit maintenance, pruning and necessary replication. **Regression:** pause
with pending and repeat jobs over several repeat periods; no new spawns or
elapsed job clock; resume continues once without a catch-up burst. Reproduce
with `logic_probes.lua` (`pause_repeat`).

### F06 — partial broadcast failure loses a size retry

**Path:** `spawn/tuning.lua:639–715`, `core/protocol.lua:91–110,247–255`;
installed Realms `core/mod_network.lua:281–321,580–603`.

**Trigger:** two capable peers; reject one `SessionControl.send_to_peer` call,
allow the other, then recover the rejected peer. Expected from the documented
retry claim: retry the current size for the rejected recipient. Observed with
the **actual installed ModNetwork module**: broadcast returns true, successful
peer receives one update, failed peer has one attempt / zero deliveries; ten
later send cadences make no further attempt. Both runtimes agree.

**Root cause:** Realms broadcasts log individual failures and return true.
GrandfathersTarot interprets that as delivery success and clears its outbox. Existing
tests model a whole-call false return, which is a different contract.

**Guards challenged:** capability manifests, ready-peer checks, pcall,
deduplication, cadence retries and late-join `send_all`. Successful whole-call
retry tests remain useful; joining/hello may repair a missed size, but recovery
alone does not trigger that snapshot. Incapable peers being skipped is expected.

**Impact:** model sizes can diverge after a peer-specific send rejection.
Native occurrence/frequency is unverified: the test injects the lower-layer
documented rejection, rather than proving a live network drop returns false.
SessionControl's false returns cover unavailable sessions/channels and encoding
rejection. Its frame sender invokes native RPCs and returns true without a
delivery acknowledgement; ordinary packet loss has not been shown to produce
a peer-specific false result. Do not infer that accepted RPCs guarantee delivery.

**Minimal fix proposed:** recipient-aware recovery using existing Realms peer
callbacks/direct sends and bounded current-size snapshots. A direct-send
false result can retain retry state without changing protocol 2. Review cost
before choosing periodic full snapshots. **Regression:** actual ModNetwork
with one capable rejected recipient and one successful recipient; recovery
eventually delivers the current size without indefinite queue growth.
Reproduce with `contract_probe.py`.

### F07 — LuaJIT accepts a non-finite preset field

**Path:** `catalog/presets.lua:113–119,343–383,443–479`;
`catalog/events.lua:315,540–550`.

**Trigger:** paste this deliberately constructed, correctly checksummed text
into preset import on the LuaJIT runtime:

```text
RW1|Preset|1|wave_small~changed~1~nan~120~3~10~60~1 hound{size=130}~0~0~0~0~swarm~0~~~1|a6a3
```

Expected: reject the invalid numeric field before any settings change.
Observed: decode succeeds, apply writes chance `nan`, `Events.get` preserves
NaN, and the enabled `wave_small` is excluded from the draw because its chance
is not greater than zero. Lua 5.5 rejects the same input as a bad pct value.
Positive/negative infinity also decode and clamp on LuaJIT; very large finite
numbers clamp on both runtimes. Recipe tune text separately rejects `nan`/`inf`.

**Root cause:** preset numeric validation checks `tonumber` success, then rounds
and clamps. LuaJIT recognizes non-finite strings; NaN survives these operations.
**Guards challenged:** checksum, field count, known key, valid recipe, numeric
conversion and range clamp. A checksum detects accidental changes, not numeric
validity or authenticity. Modal numeric controls reject this input, but preset
import is a separate reachable path. The defect is malformed-import robustness,
not a demonstrated non-host authority bypass.

**Impact:** an accepted setup can contain an invalid numeric setting and
silently suppress a card. Similar numeric fields need the same finite-value
policy; further HUD/cooldown effects are not claimed as reproduced.
**Minimal fix proposed:** validate finiteness before rounding/clamping all
imported numeric fields and reject the import atomically; retain clamping of
large finite values and existing serialization. **Regression:** the exact
sealed text above and non-finite values in each numeric field are rejected on
both VMs with no settings writes; finite boundary imports still work.
Reproduce with `edge_probe.py` (`nonfinite_import_effect`).

## Challenges that did not establish a defect

| Status | Challenge and result | Remaining evidence |
| --- | --- | --- |
| not reproduced | Delete the last standard-card enemy. The real `_remove_part` guard leaves one group; forcing private `_parts = {}` tested an unsupported state and restored defaults | None for this allegation; custom empty slots have separate intended semantics |
| not reproduced in tested envelope | Native equal-value buff-reset collision, compounded factors, stale drag release and shared explosion-template restoration | Existing assertions detect deliberate regressions; native hook dispatch/animations still need live checks |
| unverified | Deliver an older host state after a newer one: ballot 2/time 10 rolls back to ballot 1/time 99. Older scale 120 after 180 applies 1.2 | Realms uses framed native mechanism RPCs; reliable ordering/session-generation behavior is not established by the script source. Injected reordering alone is not a reachable transport bug |
| confirmed robustness gap; low priority | Authorized host state with `k = {false}` raises in `Director.on_state` around 1037 | Normal sender builds valid candidates; non-host messages are rejected. Define the intended hostile/mixed-host shape envelope before adding schema work |
| suspected preview issue | Mirror hand-name proxy line height slightly exceeds its 31.5-unit box at 1440p/4K | Native font metrics/clipping. Proxy-font marker is insufficient for a UI defect |
| unverified | Native/process retention over ten missions and eight hours | Run the live checklist; accelerated Lua cycles do not replace elapsed-time/native measurements |

## Source, architecture and reuse conclusions

The catalog/core/spawn/UI split gives useful ownership boundaries. Pure model
helpers, stable order, bounded widget counts, reusable HUD scratch tables and
host validation are worth keeping. No measured need for a new framework,
dependency, protocol version, serialization format or general-purpose event bus
was established. Maintenance failures concentrate at **lifecycle ownership**
and **dependency return contracts**, not module count.

The callback flow is single-threaded Lua with synchronous local Realms
dispatch. That permits reentrancy but does not by itself imply a thread race or
deadlock. Existing synchronous-handshake tests pass. Native managers, hook
ordering across other mods and transport behavior remain external boundaries.
Status output reports jobs, total queued work, tracked units and tuning counts;
retain these existing observability tools for live validation.

BetterInventory patterns were selectively checked at its pinned revision:

| Candidate | Evidence / benefit | Cost and recommendation |
| --- | --- | --- |
| Explicit release by owner | `BetterInventory_runtime_lifecycle.lua:297–349` clears callbacks, pending presentation closures and owned views | Apply the small release discipline to subscriptions (F01); do not import the full inventory lifecycle layer |
| Generation identity + weak registries | same module, generation token near top and `adopt_inventory` / `adopt_managed_grid` | Useful only where views really survive reload; GrandfathersTarot already has retired-instance flags. Prove native surviving-view need first |
| Repeated-close and abnormal-destroy review | `tests/test_view_lifecycle_memory.py:27–60` traces close/destroy/disable cleanup | That file contains source-string assertions, not a behavioral retention soak. Reuse the scenarios with real ownership/weak-reference assertions |
| Sorting/native-grid integrations | inventory session and managed-grid code | GrandfathersTarot owns a fixed card grid and already tests sorting/drag. Copying inventory adapters would add unrelated cost |

No tracked repository-wide LICENSE was located in BetterInventory. Its README
credits Inventory2D permission with attribution; that is not established blanket
permission to copy all BetterInventory code. No code/assets were copied into
GrandfathersTarot. Prefer independent application of these patterns; verify provenance
and permission before any literal reuse.

Relevant primary contracts were refreshed, not unrelated historical audits:

- [Realms author source](https://github.com/deluxghost/darktide-mods/blob/a4564b7dda7c6fdbd92eb633c1931b1a51a749ae/Realms/scripts/mods/Realms/core/mod_network.lua)
  supports synchronous dispatch, owner-enabled gates, peer capabilities and
  broadcast return semantics; checked files match the installed bytes.
- [DMF loader](https://github.com/Darktide-Mod-Framework/Darktide-Mod-Framework/blob/fc08c1cb772f86248c7ae9e957543e801a0dbf64/dmf/scripts/mods/dmf/dmf_loader.lua),
  [events](https://github.com/Darktide-Mod-Framework/Darktide-Mod-Framework/blob/fc08c1cb772f86248c7ae9e957543e801a0dbf64/dmf/scripts/mods/dmf/modules/core/events.lua)
  and [toggling](https://github.com/Darktide-Mod-Framework/Darktide-Mod-Framework/blob/fc08c1cb772f86248c7ae9e957543e801a0dbf64/dmf/scripts/mods/dmf/modules/core/toggling.lua)
  match the installed files. This establishes those contracts, not a complete
  installed-DMF release identity.
- [Game EventManager](https://github.com/Aussiemon/Darktide-Source-Code/blob/419fe18d414a618ce0474bd015bab470afb446d6/scripts/managers/event/event_manager.lua)
  and buff/attack consumers were checked against the matching local source.
- The [1.13.1 comparison](https://github.com/Aussiemon/Darktide-Source-Code/commit/7e662fcda16219d775b84af50322be2e9cd9d62e)
  changes nine files, +24/−7. No audited hook signature changed in this delta.
  Survival pickup source, wizard tuning/hazards, training-ground danger
  validation and Havoc `activate_on_load` flags changed. The Havoc flags justify
  repeating modifier/recompute live checks after updating the game; this
  limited diff does not establish complete future compatibility.
- [LuaJIT compatibility](https://luajit.org/extensions.html) and the Lua manual
  informed runtime/GC controls; Lupa's build is not asserted to be the game VM.

## Remediation review gate

Recommended coherent batches, **proposals only**:

1. `feature/audit-event-cleanup`: F01 subscription release; real event-manager
   reload regression; obsolete callback assertions.
2. `feature/audit-control-lifecycle`: F02/F03/F05, one explicit policy for
   disable, pause, stop, resume and mission teardown, with live-unit ownership
   preserved where units survive. Add detecting tests before changing behavior.
3. `feature/audit-aggregate-budget`: F04 aggregate admission/repeat budget,
   backpressure and pressure/teardown regression. Agree on the numeric policy.
4. `feature/audit-import-validation`: F07 finite numeric import validation and
   both-runtime atomic rejection regressions, preserving serialization.
5. `feature/audit-scale-recovery`: F06 recipient-aware delivery recovery and
   actual Realms contract regression, keeping protocol 2.
6. Strengthen the two surviving-mutation checks; review state schema/order only
   after its required transport/compatibility evidence. No speculative API rewrite.

After findings are reviewed/approved, create feature branches from then-current
`main`, make the smallest root-cause fixes, run all six checks and both Lua
runtimes, and update the live matrix. Installation, publication and merging
are separate later actions. `CLAUDE.md` requires the user's in-game confirmation
before merge; no such acceptance is claimed here.

## Completion and limits

All 29 Lua files and the descriptor are inventoried with responsibility,
ownership and scoped review evidence. Every L1–L8 workload has a result or an
explicit limitation in the measurement companion. Five of seven mutations are
behaviorally detected on both VMs; two survive. The normal checks still pass:
30 compiled sources and 1,655 assertions per runtime. Essential scripts and
observations are preserved in Markdown; raw logs, hashes and 27 widget previews
remain in `.git/audit/2026-10-03/`.

Tracked runtime, tests, configuration and read-only references were unchanged
through the audit; final SHA-256 comparison and documentation/link checks are
recorded with the measurements. Only Markdown documentation is changed.
The offline audit deliverable is complete within the stated envelope. Production
remediation and native/live acceptance remain open.
