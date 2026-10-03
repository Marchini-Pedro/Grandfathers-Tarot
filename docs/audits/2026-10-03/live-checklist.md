# Pending live acceptance

This procedure is not an installation authorization or a completed game test.
See the [report](report.md) and the repository's [merge rule](../../../CLAUDE.md).
Apply approved fixes first, verify the exact installed revision on each peer,
and obtain the user's in-game confirmation before merge. A merge, tagged
version or successful offline suite does not close these checks.

## Identity and controls

1. Record UTC and São Paulo timestamps, full tested commit, dirty diff and
   SHA-256 manifest of the 29 Lua files plus descriptor in both the checkout
   and installed copy. Compare every file, including missing/extra files.
   Today the installed copy differs in 14 files and lacks 16, so it is unsuitable
   as acceptance evidence for this checkout.
2. Record game build from the new console log, matching decompiled-source
   revision, Realms/SoloPlay metadata and installed file hashes, DMF hashes,
   load order, hardware, drivers, resolution, render scale, VSync/FPS cap,
   upscaling/frame generation, graphics and all relevant mod settings.
   Lupa LuaJIT identity cannot stand in for the game's build.
3. Preserve real presets/profiles. Use a deliberately named synthetic setup;
   save and hash the original settings beforehand and restore it afterward.
   Arrange any install/change as a separately authorized action.
4. Obtain a baseline with identical render settings and map/difficulty where
   feasible: game + DMF + Realms/SoloPlay, then RealmsWaves enabled at moderate
   load. Add overlapping wave/spawner mods individually, then the normal load
   order. Record mismatched controls (map RNG, players, difficulty, native
   allocation, background applications); do not claim a causal delta from an
   uncontrolled comparison.

## Functional sessions

| Session / trigger | Capture and acceptance |
| --- | --- |
| Host only, matching installed manifest | Start each mode; weighted draw, unique tarot hand, cooldown exhaustion, fixed timer exclusion, no-vote fallback, one-vote-per-peer and anti-snowball rules behave as displayed |
| Matching host + one client, then full squad | Same manifests; vote changes, sender authority, countdown and hand/winner agree; only host spawns; normal units retain engine pacing behavior |
| Client without RealmsWaves | Session remains usable; client presentation limits are recorded; do not expect size/HUD/vote behavior it cannot implement |
| Mixed mod/version session | Rejected protocol/version handshake is explicit and safe; unsupported peers do not spoil capable peer updates; no shared-template/network lookup changes |
| Late join during hand/reveal/rot and sized units | Stage/age synchronized without replay; existing live sizes delivered; capture per-peer `/rw_status` and screenshots |
| Disconnect/rejoin during ballot and repeat work | Left peer's vote/inventory removed; reconnect takes current state; no stale ballot, scale or old-session handle mutation |
| Missing network/manager during transition | No frame-breaking error; retry is bounded; resumed network delivers current size after a failed send. Observe actual Realms transport return/ordering rather than assuming a dropped packet produces false |
| Pause with pending initial/repeat work | After approved F05 fix, no new units or repeat/job-clock advancement for at least three repeat periods; live maintenance continues; resume makes progress without overdue burst |
| Stop with living tuned enemies, then restart | After F03 fix, surviving units remain counted/tuned/sized; pending work is cancelled; combined live units respect the cap; despawn releases records |
| DMF disable then enable during queued work | After F02 fix, no disabled spawning, hidden HUD correct, no stale replay; check hook/counter behavior and defined live-unit policy |
| Reload 1/10/30 times with editor closed/open, active popup/drag, queued repeat and live units | After F01 fix, obsolete event registration count is zero; old callbacks inert; no duplicate controls/HUD/views. Capture current manager identity; compare collected Lua floor across batches |
| Complete/abort/retry mission, return to hub and rejoin | At least 30 transitions across sessions: no owned pending jobs, peer inventories or stale handles after teardown; keep legitimate still-live resources separate |
| Maximum legal fixed/repeat settings | After F04 fix, jobs and aggregate pending entries stay inside the approved budget while alive cap is full; status remains responsive and teardown clears work |

Do not fabricate a malicious native network peer to test authority. Use the
offline contract fixture for malformed messages; normal multiplayer captures
should establish how actual sender/channel data are routed.

## UI and tuned enemies

- Test 1920×1080, 2560×1440 and 3840×2160 at recorded engine UI scales. Walk
  Deck → Cauldron → shelf/picker/search → Mods → Custom → Mirror → Spreads →
  More options and back, including all five preset slots, all twenty custom
  slots, delete/undo/load/import/export and reordered cards.
- Use real mouse input: hold-to-drag, valid swap, release beyond grid/window,
  lost focus, scroll mid-drag, screen change, fast second click, page change
  and popup cancellation. Reopen/reload and verify saved ordering.
- Verify first typed character, Enter/Esc, numeric rejection, focus handoff,
  null/disabled input and game/mod key suppression. Include a long card name,
  whisper, localized fallback, non-ASCII text and native fonts. Inspect the
  Mirror hand-name box that the proxy renderer flagged at 1440p/4K.
- Capture screenshots/video of active and hidden HUD, one/five cards, long
  names, roulette/reveal/rot, scaling/opacity and custom_hud editing. Confirm
  clipping, material layering, text metrics and hit areas; Pillow previews
  cannot accept those.
- With controlled enemies, verify health, movement, hit mass, gap 25/50/100/250,
  gunner fire 25/100 and burst 100/500 with/without Havoc recomputes. Log
  `/rw_tune` and actual shots; check equal-value resets and compounded buffs.
- Check Chaos Spawn/Plague Ogryn multi-hit chains retain their last hit at
  extreme gap settings. Check normal and sized bursters' blast radii on host
  and client and restore shared templates after an error/reload. Check
  boss-health names on clients as well as host; host-only naming remains a
  known presentation limit. Attack animation playback speed is not an API
  promised by this mod.

## Eight-hour / ten-consecutive-mission run

Target at least eight elapsed hours and ten consecutive missions in one process.
Do not replace this with accelerated updates or ten separate game launches.
Record failures/aborts and the actual count; if eight hours yields fewer than
ten missions, extend or mark the unmet target. Begin with a 10-minute warm
baseline. Hold graphics/load order/settings fixed during measured phases;
record any necessary change as a new phase.

Use a CSV with one row per 10-second interval and explicit boundary rows:

```text
utc,sao_paulo,elapsed_s,commit,game_build,phase,mission_id,mission_index,
event,frame_count,frame_ms_p50,frame_ms_p95,frame_ms_p99,frame_ms_max,
lua_heap_kib,lua_heap_resolution_kib,lua_heap_source,lua_gc_kind,
working_set_bytes,private_bytes,cpu_seconds,
rw_jobs,rw_queued,rw_tracked,rw_tuned,rw_unsent,rw_pending,error
```

Frame statistics must come from timestamped per-frame capture (for example a
separately selected/pinned PresentMon capture), with sampling tool/version and
overhead recorded. Prefer presented/frame-time measures with frame generation
configuration explicit. A one-second FPS sample cannot establish p99 frame
time. Reuse `/rw_status` for counters and coarse heap observations: its heap is
rounded to whole MiB despite the displayed MB label. If converting it to KiB,
record resolution 1,024 KiB and source `rw_status`; the conversion adds no
precision. Use already installed telemetry for finer samples, recording its
version and precision. If unavailable, mark precise collected Lua floors as
unmeasured. Do not add measurement code to production as part of this audit.
Record whether each heap value is naturally sampled, post-collection, or forced
diagnostic collection. Do not force GC every sample.

For process memory, this read-only PowerShell capture can run in another
terminal. Resolve the game PID explicitly; do not measure Python or the shell.
Stop with Ctrl+C. The timezone id is Windows' São Paulo timezone.

```powershell
$gamePid = (Get-Process -Name Darktide | Select-Object -First 1).Id
$captureCsv = Join-Path $PWD 'darktide-process-samples.csv'
while ($true) {
    $processSample = Get-Process -Id $gamePid -ErrorAction Stop
    $stamp = [DateTimeOffset]::UtcNow
    [pscustomobject]@{
        utc = $stamp.ToString('o')
        sao_paulo = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId(
            $stamp, 'E. South America Standard Time').ToString('o')
        pid = $gamePid
        working_set_bytes = $processSample.WorkingSet64
        private_bytes = $processSample.PrivateMemorySize64
        cpu_seconds = $processSample.TotalProcessorTime.TotalSeconds
    } | Export-Csv -LiteralPath $captureCsv -Append -NoTypeInformation
    Start-Sleep -Seconds 10
}
```

Add timestamped records immediately before mission entry, after spawn/hand
bursts, pause/stop/disable/reload, last enemy death, mission completion/abort,
hub arrival and before the next mission. At those boundaries capture console
log sections, status counts, Lua floor after an idle interval and process
memory. Mark natural asset-cache plateaus, temporary allocation churn and
still-live units separately from monotonically retained resources. Repeat
short functional workloads at least five times; report sample count, median,
p95/p99 only with sufficient frame samples, maxima and mission-boundary trends.

Acceptance requires no crashes or repeated update/hook errors, the corrected
invariants above, bounded post-teardown Lua ownership and explained memory
plateaus. Process memory may retain native caches; increasing working set
alone is not a Lua leak. Establish a frame-time budget against the controlled
baseline before classifying a performance regression. Do not invent numeric
native thresholds from Lupa timings. Archive commands, raw captures, manifests
and user confirmation beside the final verification results.
