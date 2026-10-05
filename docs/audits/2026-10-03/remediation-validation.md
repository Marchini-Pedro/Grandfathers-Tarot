# Remediation validation — 2026-10-03

This companion checks the approved fixes on `feature/audit-remediation`.
The [original report](report.md) and [original reproduction](reproduction.md)
retain the frozen pre-fix revision. Do not expect their defect probes to pass
against fixed code. Python 3.13.13 and Lupa 2.8 supplied explicit Lua 5.5 and
LuaJIT 2.1.1774896198 runtimes; equivalence to the game's VM remains unverified.
Installed mods, saved presets/profiles and source references are read-only.

## Checks and intended regressions

All six required tools pass on each VM: 30 compilation inputs; 828 logic,
694 editor, 45 entry and 179 HUD assertions, totaling **1,746** per runtime.
The original seven selected mutations now fail their intended behavioral
assertions, including both former survivors. Ten additional mutations also
fail intended assertions. Every mutated harness completes without setup errors.
These 17 selected changes measure these invariants; they are not a coverage
percentage or proof that every possible defect is detected.

| Mutation | Required behavioral assertion |
| --- | --- |
| Remove per-job queue cap | Long-frame repeat queue stays at most 1,000 |
| Permit non-host RPCs | Another client cannot spoof host state/size/welcome |
| Preserve older incoming size | Newest arrival wins, including a full inbox |
| Restore stale drag target | Release outside grid cancels without reorder |
| Break equal-value reset marker | A fresh equal base receives its factor once |
| Remove tuning retirement flag | Captured entry points cannot recreate records/write stats |
| Omit both unload resets | Real pending jobs and director state are torn down |
| Omit event unregistration | 100 generations release strong keys and weak mod references |
| Ignore executor pause flag | Pause freezes real feed/repeat/timeout clocks |
| Reset ownership on stop | Stop retains living-unit tracking and tuning |
| Omit disable cancellation | Disable cancels queued work before subsequent update |
| Remove job limit | Repeat-only jobs admit at most 64 |
| Remove aggregate queue limit | 32 supported timers stay within shared budget |
| Remove finite import checks | Valid-checksum non-finite fields reject atomically |
| Restore broadcast-only scales | A peer rejection retains current-size retry |
| Clear reentrant outbox after send | A synchronous new size survives completion |
| Restore stale snapshot requeue | A failed snapshot returning after retirement stays empty |

The installed Realms `ModNetwork` integration loads the real adapter and
`Protocol`/`Tuning`, injecting only SessionControl rejection. Both VMs record
one attempt before recovery, two total attempts, one successful delivery of
latest size 180, and an empty retry queue. The good peer receives twice;
absolute size application makes that duplicate idempotent. Native packet loss,
acknowledgements, ordering and multiplayer overhead remain unverified.

## Supported maximum pressure measurement

The real entry fixture configures 32 legal five-second timers, 500 percent
multipliers and repeating recipes, with ten existing units blocking the alive
cap. It runs 10,000 updates at 0.016 seconds (160 simulated seconds) and checks
bounds each update. Each measurement uses a fresh seeded VM (`424242`), collects
twice before/after the timed loop and again after `Execute.reset`, and repeats
five times per runtime/mode. Python `perf_counter` times the whole loop,
including assertions and Lua/Python measurement boundaries. Native spawn,
navmesh, network and renderer boundaries are fixtures. The preceding fixture
warms the VM; unrelated fixture-owned objects remain part of the heap baseline.

Normal LuaJIT tracing is enabled for the timed loop. The separate retention
control disables/flushes tracing; the 100-generation ownership diagnostic
temporarily disables tracing in normal runs too and restores its initial mode.
Normal-JIT compiler state can survive reset. These medians/maxima are harness
costs, not game frame times. With five samples, the observed maximum is more
useful than an estimated percentile. This fixture differs from the original
audit measurement; no causal speedup percentage is claimed.

| VM | Mode | n | Loop median/max (ms) | Collected baseline (KiB) | Active median/max (KiB) | Post-reset median (KiB) |
| --- | --- | --- | --- | --- | --- | --- |
| lua55 | normal | 5 | 135.125 / 151.547 | 1178.209 | 2466.461 / 2466.742 | 1178.187 |
| luajit21 | normal | 5 | 49.857 / 50.692 | 1290.052 | 2785.923 / 2799.521 | 1386.810 |
| lua55 | retention | 5 | 130.630 / 178.800 | 1178.209 | 2466.461 / 2466.461 | 1178.187 |
| luajit21 | retention | 5 | 74.680 / 92.166 | 1100.143 | 2498.072 / 2498.072 | 1098.959 |

All 20 samples finish at 16 jobs / 8,000 entries and reset to zero jobs/entries.
The tracing-off collected floor returns near baseline. Native allocations,
process RAM, real rendering and an eight-hour session remain pending under the
[live checklist](live-checklist.md). Saved-configuration hashes and installed
dependency/source hashes are rechecked separately before committing.

## Reproduce after a clone

Use the same read-only reference layout and revisions recorded in the
[baseline](report.md#baseline-and-controls). The editor needs the sibling game
source; the integration needs installed `mods/Realms/core/mod_network.lua`.
Installations/profiles are not modified by these scripts. From the repository
root, extract scripts into a new ignored directory, leaving original audit
outputs untouched:

```powershell
@'
import re
from pathlib import Path
dest=Path('.git/audit/2026-10-03-remediation-repro')
dest.mkdir(parents=True,exist_ok=True)
old=Path('docs/audits/2026-10-03/reproduction.md').read_text(encoding='utf-8')
new=Path('docs/audits/2026-10-03/remediation-validation.md').read_text(encoding='utf-8')
pattern=r'^### Script: ([a-z_]+\.(?:py|lua))\n\n```(?:python|lua)\n(.*?)^```'
for name,code in re.findall(pattern,old,re.M|re.S):
    if name in ('audit.py','logic_probes.lua'):
        (dest/name).write_text(code,encoding='utf-8')
for name,code in re.findall(pattern,new,re.M|re.S):
    (dest/name).write_text(code,encoding='utf-8')
'@ | python -X utf8 -
$diagPath = '.git/audit/2026-10-03-remediation-repro'
python -X utf8 "$diagPath/audit.py" suites
python -X utf8 "$diagPath/contract_probe.py"
python -X utf8 "$diagPath/mutations.py"
python -X utf8 "$diagPath/extra_mutations.py"
python -X utf8 "$diagPath/budget_measure.py"
```

`audit.py` extracts current tracked harnesses without changing them and selects
each VM explicitly. Only the setup prefix of `logic_probes.lua` is reused for
the integration; the old defect probes are not run. Check `suites.json` for
empty `failures` and null `error`, both compile JSON exits and `docs_check.json`
exit zero. Check both contract JSON diagnostics for latest size/retry assertions.
For mutation JSON, require null `error` and the intended assertion from the table;
`extra_mutations.py` additionally asserts `intended_detection`. An exception or
unrelated assertion is never credited. Timing values will vary by machine/load.

The exact integration and mutation/measurement programs used here follow.
They override `dofile` in isolated VMs; no mutant touches tracked runtime/tests.

### Script: contract_probe.py

```python
import json
from audit import OUT, ROOT, execute

setup=(OUT/'logic_probes.lua').read_text().split('reset()\nlocal live=')[0]
code=setup+r'''
local realmstate={}
local realm={io_dofile=function() return {NAME='realms-mod-network'} end,
 persistent_table=function() return realmstate end, info=function() end}
local old_get_mod=get_mod
get_mod=function(name) if name=='Realms' then return realm end return mod end
table.keys=function(t) local out={} for key in pairs(t) do out[#out+1]=key end return out end
unpack=unpack or table.unpack
cjson={null={}}
Network={peer_id=function() return 'host' end}
Managers.connection={is_host=function() return true end,is_client=function() return false end}
mod.get_name=function() return 'GrandfathersTarot' end
mod.is_enabled=function() return true end
mod.pcall=function(self,fn,...) return pcall(fn,...) end
local handlers={}; local attempts,delivered={},{}; local delivered_values={}
local reject=true
local SC={is_available=function() return true end,register_protocol=function() end,
 register_host_handler=function(proto,name,fn) handlers[name]=fn end,register_client_handler=function() end,
 register_disconnect_handler=function() end,register_ready_handler=function() end,
 send_to_clients=function() return true end,send_to_client=function() return true end,
 is_peer_available=function() return true end,ready_peer_ids=function() return {'good','failed'} end,
 send_to_peer=function(peer,proto,name,payload)
   attempts[peer]=(attempts[peer] or 0)+1
   if reject and peer=='failed' then return false,'injected transport rejection' end
   delivered[peer]=(delivered[peer] or 0)+1; delivered_values[peer]=payload.arguments.values[1];return true
 end}
local MN=dofile(MODROOT_REALMS..'/scripts/mods/Realms/core/mod_network.lua')
MN.install(SC); realm.network_is_available=MN.is_available; realm.network_register=MN.register; realm.network_send=MN.send; realm.network_on_peer_joined=MN.on_peer_joined; realm.network_on_peer_left=MN.on_peer_left; cjson.encode=function(list) return 'sizejson:'..tostring(list[1][2]) end; local ActualProtocol=load('core/protocol'); ActualProtocol.init({})
handlers.mod_network_manifest(1,'good',{rpcs={GrandfathersTarot={'rw_scale'}}})
handlers.mod_network_manifest(2,'failed',{rpcs={GrandfathersTarot={'rw_scale'}}})
local broadcast_ok=MN.send(mod,'rw_scale','others',{{1,130}})
AUDIT_EMIT('realms_partial_broadcast',{success=broadcast_ok,attempts=attempts,delivered=delivered})
attempts={};delivered={}
Tuning.reset(); Tuning.init({protocol=ActualProtocol})
local unit={id=77,buffs={stat_buffs=function() return {} end}}
Tuning.apply(unit,{size=130},'chaos_hound'); Tuning.update(1)
local failed_before=attempts.failed or 0; assert(Tuning.status().unsent==1); Tuning.apply(unit,{size=180},'chaos_hound')
reject=false; for i=1,10 do Tuning.update(1) end
assert((delivered.failed or 0)>0 and Tuning.status().unsent==0 and delivered_values.failed=='sizejson:180'); AUDIT_EMIT('scale_retry_contract',{failed_attempts_before=failed_before,failed_attempts_after=attempts.failed or 0,
 failed_deliveries=delivered.failed or 0,good_deliveries=delivered.good or 0,sizes=Tuning.status().sizes_known})
'''
code="local MODROOT_REALMS="+json.dumps(str(ROOT.parent.parent/'mods/Realms').replace('\\','/'))+'\n'+code
for runtime in ('lua55','luajit21'):
    result=execute('logic_test.py',runtime,suffix=code,prefix_only=True)
    (OUT/(runtime+'_contract.json')).write_text(json.dumps(result,indent=2))
    print(json.dumps({k:v for k,v in result.items() if k!='output'}))
```

### Script: mutations.py

```python
import json
from audit import BASE, OUT, execute

cases = [
 ('queue_cap', 'spawn/execute.lua', 'local MAX_QUEUE = 1000', 'local MAX_QUEUE = math.huge', 'logic_test.py'),
 ('host_authority', 'core/protocol.lua', 'local function valid_host_sender(peer_id)\n', 'local function valid_host_sender(peer_id)\n\tif true then return valid_sender(peer_id) end\n', 'logic_test.py'),
 ('old_scale_wins', 'spawn/tuning.lua', 'pending.pct, pending.age = entry.pct, 0', 'pending.pct, pending.age = pending.pct, 0', 'logic_test.py'),
 ('stale_drag_target', 'ui/wave_editor_deck.lua', '-- let go: swap with the tile it is over (the pointer where it was last seen), or go back\n\t\tlocal target = self:_tile_slot_at(x, y)', '-- let go: scratch mutation\n\t\tlocal target = drag.target', 'editor_test.py'),
 ('equal_value_reset', 'spawn/tuning.lua', 'record.recomputed = true', 'record.recomputed = false', 'logic_test.py'),
 ('obsolete_tuning_hook', 'spawn/tuning.lua', 'Tuning.retire = function ()\n\tTuning.dead = true', 'Tuning.retire = function ()\n\tTuning.dead = false', 'logic_test.py'),
 ('omit_unload_reset', 'GrandfathersTarot.lua', '\t\tRW.execute.reset()', '\t\tdo end -- scratch: omit executor reset', 'entry_test.py'),
]
results=[]
for name, relative, original, replacement, suite in cases:
    path=BASE/relative
    code=path.read_text(encoding='utf-8-sig')
    assert code.count(original)==1, (name,code.count(original))
    code=code.replace(original,replacement)
    if name=='omit_unload_reset': code=code.replace('\t\tRW.director.reset()', '\t\tdo end -- scratch: omit director reset')
    mutated={str(path).replace('\\','/'):code}
    for runtime in ('lua55','luajit21'):
        result=execute(suite,runtime,mutations=mutated)
        result['mutation']=name
        (OUT/(runtime+'_mutation_'+name+'.json')).write_text(json.dumps(result,indent=2),encoding='utf-8')
        summary={k:v for k,v in result.items() if k!='output'}
        results.append(summary)
        print(json.dumps(summary),flush=True)
(OUT/'mutations.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
```

### Script: extra_mutations.py

```python
import json
from audit import BASE,OUT,execute
cases=[
 ('event_cleanup','GrandfathersTarot.lua','entry_test.py','reload: 100 generations'),
 ('pause_feed','core/director.lua','entry_test.py','pause: real executor'),
 ('stop_ownership','core/director.lua','entry_test.py','stop: cancel jobs'),
 ('disable_cancel','GrandfathersTarot.lua','entry_test.py','disable: queued work'),
 ('aggregate_jobs','spawn/execute.lua','entry_test.py','aggregate: repeat-only'),
 ('aggregate_pending','spawn/execute.lua','entry_test.py','aggregate: 32 legal'),
 ('nonfinite_import','catalog/presets.lua','logic_test.py','import: non-finite'),
 ('partial_delivery','core/protocol.lua','logic_test.py','delivery: partial direct'),
 ('reentrant_outbox','spawn/tuning.lua','logic_test.py','network: synchronous new size'),
 ('retired_snapshot','spawn/tuning.lua','logic_test.py','retire: a failed snapshot'),
]
results=[]
for name,relative,suite,expected in cases:
 path=BASE/relative;code=path.read_text(encoding='utf-8-sig')
 def replace(old,new):
  global code
  assert code.count(old)==1,(name,old,code.count(old));code=code.replace(old,new)
 if name=='event_cleanup':
  replace('\t\tpcall(RW.event_manager.unregister, RW.event_manager, mod, "event_mission_objective_start")','\t\tdo end')
  replace('\t\tpcall(RW.event_manager.unregister, RW.event_manager, mod, "event_player_died")','\t\tdo end')
 elif name=='pause_feed':replace('Execute.update(dt, paused or stopped)','Execute.update(dt)')
 elif name=='stop_ownership':replace('Execute.cancel()','Execute.reset()')
 elif name=='disable_cancel':
  begin=code.index('mod.on_disabled = function ()');end=code.index('mod.on_enabled = function',begin)
  old=code[begin:end];new=old.replace('RW.director.stop()','do end').replace('RW.execute.cancel()','do end');assert old!=new;replace(old,new)
 elif name=='aggregate_jobs':replace('local MAX_JOBS = 64','local MAX_JOBS = math.huge')
 elif name=='aggregate_pending':replace('local MAX_PENDING = 8000','local MAX_PENDING = math.huge')
 elif name=='nonfinite_import':
  replace('if not value or value ~= value or math.abs(value) == math.huge then','if not value then')
  replace('if not threat or threat ~= threat or math.abs(threat) == math.huge then','if not threat then')
 elif name=='partial_delivery':
  begin=code.index('\tif recipient and recipient ~= "others" then',code.index('Protocol.send_scales ='))
  end=code.index('Protocol.send_waves =',begin)
  code=code[:begin]+'\treturn send(RPC_SCALE, recipient or "others", json)\nend\n\n'+code[end:]
 elif name=='reentrant_outbox':replace('if not send_batches(list) then','local sent_ok = send_batches(list); outbox, outbox_by_id = {}, {}\n\t\t\tif not sent_ok then')
 elif name=='retired_snapshot':
  begin=code.index('\tif not sent and err ~= "target_rpc_unsupported" then')
  end=code.index('\nend\n',begin)
  code=code[:begin]+'\tif not sent and err ~= "target_rpc_unsupported" then\n\t\tfor i = 1, #list do queue_size(list[i][1], list[i][2]) end\n\tend'+code[end:]
 for rt in ('lua55','luajit21'):
  row=execute(suite,rt,mutations={str(path).replace('\\','/'):code})
  result={k:v for k,v in row.items() if k!='output'};result['mutation']=name
  result['intended_detection']=row.get('error') is None and any(expected in f for f in row.get('failures',[]))
  results.append(result)
  (OUT/(rt+'_extra_'+name+'.json')).write_text(json.dumps(row,indent=2),encoding='utf-8')
(OUT/'extra_mutations.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
assert all(r['intended_detection'] for r in results),[(r['mutation'],r['runtime'],r.get('error'),r.get('failures')) for r in results if not r['intended_detection']]
print('extra mutations: 10/10 intended behavioral detections on both runtimes; no setup-error credit')
```

### Script: budget_measure.py

```python
import importlib,json,statistics,time
from audit import OUT,ROOT,harness
src=harness('entry_test.py')
src=src.replace('local bounded=true', "collectgarbage('collect');collectgarbage('collect');local diag_baseline=collectgarbage('count');local diag_start=DIAG_NOW();local bounded=true",1)
src=src.replace('local before_jobs,before_queue=', "local diag_seconds=DIAG_NOW()-diag_start;local diag_loaded=collectgarbage('count');collectgarbage('collect');collectgarbage('collect');DIAG_EMIT('active',{seconds=diag_seconds,baseline_kb=diag_baseline,loaded_kb=diag_loaded,collected_kb=collectgarbage('count'),jobs=RW.execute.status().jobs,queued=RW.execute.status().queued});local before_jobs,before_queue=",1)
needle='RW.execute.reset()\nfor i=1,10 do RW.bypass.track({id=2000+i}) end'
assert src.count(needle)==1
src=src.replace(needle,"RW.execute.reset();collectgarbage('collect');collectgarbage('collect');DIAG_EMIT('reset',{heap_kb=collectgarbage('count'),jobs=RW.execute.status().jobs,queued=RW.execute.status().queued})\nfor i=1,10 do RW.bypass.track({id=2000+i}) end",1)
records=[]
for mode in ('normal','retention'):
 for rt in ('lua55','luajit21'):
  for rep in range(5):
   vm=importlib.import_module('lupa.'+rt).LuaRuntime(unpack_returned_tuples=True)
   vm.execute('math.randomseed(424242)')
   if rt=='luajit21' and mode=='retention':vm.execute('jit.off();jit.flush()')
   data={};vm.globals().DIAG_NOW=time.perf_counter
   vm.globals().DIAG_EMIT=lambda key,value:data.__setitem__(key,dict(value.items()))
   result=vm.execute(src,str(ROOT).replace('\\','/'))
   assert not any(line.startswith('FAIL ') for line in result.splitlines()),result
   records.append({'runtime':rt,'mode':mode,'rep':rep+1,**data})
(OUT/'budget_measure.json').write_text(json.dumps(records,indent=2),encoding='utf-8')
for mode in ('normal','retention'):
 for rt in ('lua55','luajit21'):
  samples=[r for r in records if r['mode']==mode and r['runtime']==rt]
  summary={'runtime':rt,'mode':mode,'n':len(samples),'seconds_median':statistics.median(r['active']['seconds'] for r in samples),'seconds_max':max(r['active']['seconds'] for r in samples),'baseline_kb_median':statistics.median(r['active']['baseline_kb'] for r in samples),'active_collected_kb_median':statistics.median(r['active']['collected_kb'] for r in samples),'active_collected_kb_max':max(r['active']['collected_kb'] for r in samples),'post_reset_kb_median':statistics.median(r['reset']['heap_kb'] for r in samples),'max_jobs':max(r['active']['jobs'] for r in samples),'max_queued':max(r['active']['queued'] for r in samples)}
  print(json.dumps(summary),flush=True)
```
