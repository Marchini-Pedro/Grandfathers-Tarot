# Reproducing the offline audit

Inputs: target `8c81c1bbfb6107788dafa98f56c6194dcaa80421`, adjacent
1.13.0 source `419fe18d414a618ce0474bd015bab470afb446d6`, and the installed
Realms/DMF files pinned in the [report](report.md). Python 3.13.13, Lupa 2.8
(`lua55` and `luajit21`) and Pillow were already installed. Do not install a
different runtime or replace the source baseline merely to make this run.
The actual game VM is not asserted equivalent. All settings are synthetic.

The original raw outputs are in `.git/audit/2026-10-03/`, intentionally
untracked. The essential diagnostic sources below make the findings reviewable
after a clone, without relying on ignored local scripts. They extract existing
harness prefixes with Python AST, load actual target modules and adapt the
engine boundary only inside each VM. Mutations replace `dofile` input in memory.
They never rewrite production files, tracked tests, profiles or installed mods.
These are audit experiments, not new production regression tests.

Run from the repository root. Extract these fenced script bodies into a **new**
scratch directory so the original evidence is retained:

```powershell
@'
import re
from pathlib import Path
doc=Path('docs/audits/2026-10-03/reproduction.md').read_text(encoding='utf-8')
dest=Path('.git/audit/2026-10-03-repro');dest.mkdir(parents=True,exist_ok=True)
for name,lang,source in re.findall(r'^### Script: ([a-z_]+\.(?:py|lua))\n\n```(python|lua)\n(.*?)^```',doc,re.M|re.S):
    target=dest/name
    if target.exists(): raise RuntimeError('Choose a fresh scratch directory: '+str(target))
    target.write_text(source,encoding='utf-8')
'@ | python -X utf8 -
$diagPath = '.git/audit/2026-10-03-repro'
python -X utf8 "$diagPath/audit.py" baseline
python -X utf8 "$diagPath/audit.py" suites
python -X utf8 "$diagPath/audit.py" probes
python -X utf8 "$diagPath/reload_probe.py"
python -X utf8 "$diagPath/mutations.py"
python -X utf8 "$diagPath/contract_probe.py"
python -X utf8 "$diagPath/followup_probes.py"
python -X utf8 "$diagPath/benchmarks.py"
python -X utf8 "$diagPath/hud_stress.py"
python -X utf8 "$diagPath/selection_probe.py"
python -X utf8 "$diagPath/edge_probe.py"
python -X utf8 "$diagPath/ui_short.py"
python -X utf8 "$diagPath/previews.py"
```

Run measurement commands sequentially with no simultaneous test process.
Inspect the JSON `error` and `failures` fields, not just the Python exit code:
diagnostic runners preserve VM errors as evidence. `audit.py suites` adapts
only the imported Lupa engine and writes the complete assertion output. Normal
timings leave JIT enabled; retention controls disable/flush it explicitly.
Python high-resolution wall time is used by `benchmarks.py`, `hud_stress.py`
and `ui_short.py`; the initial editor-cycle observations used `os.clock` and
are not the five-sample benchmark.

Expected observations at the frozen revision:

| Script/output | Essential observation |
| --- | --- |
| `reload_probe.py` | 100 obsolete mod keys in both events; removing only those registrations releases all obsolete weak references |
| `followup_probes.py` | Actual DMF disable spawns two hounds; stop changes recomputed factor 2 → 1; last-standard-group removal is refused |
| `logic_probes.lua` | Pause spawns ten hounds with frozen director time; blocked legal repeats accumulate 192,000 entries; all mission/mixed-fault teardown counters zero |
| `benchmarks.py` | 992 jobs / 992,000 entries after 10,000 updates at dt 0.016 in max-legal fixture; collected repeat pressure clears on teardown |
| `contract_probe.py` | Actual Realms broadcast returns true after one peer rejects; size cadence never retries that peer after recovery |
| `edge_probe.py` | Checksummed NaN chance is accepted/applied on LuaJIT and excludes its card; Lua 5.5 rejects; finite boundaries clamp |
| `mutations.py` | Five behavioral detections, two survivors; no syntax/setup-error detection credit |
| Editor/HUD scripts | Weak fixture views/elements zero after close/release; native lifetimes are not included |

The replay prefixes intentionally reflect the frozen tests. Entry reload uses
the real EventManager but models DMF's hook/view removal; it does not drive a
native open editor, packages or queued units through the actual reload loader.
The contract probe loads actual ModNetwork with a synthetic SessionControl
rejection. Native delivery/order cannot be inferred from that fault injection.
See [measurements](measurements.md) for all L1–L8 limits.

Preview adaptations are scratch-only: fractional 4/3 scale for 1440p, integer
image dimensions, no final downsample for native-sized 4K output, and correction
of two dump-only button labels cached before the harness switches to real
English text. They use actual dumped widgets with proxy Windows fonts; no
native texture/material/clip or interactive-input acceptance is implied.

## Embedded diagnostic sources

### Script: audit.py

```python
"""Isolated audit runner; never writes runtime, settings or tracked tests."""
import ast
import contextlib
import hashlib
import importlib
import io
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
BASE = ROOT / 'scripts/mods/RealmsWaves'

def command(*args, cwd=ROOT):
    p = subprocess.run(args, cwd=cwd, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=120)
    return {'command': list(args), 'exit': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr}

def hashes(path):
    return {str(p.relative_to(path)).replace('\\', '/'): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in path.rglob('*') if p.is_file() and '.git' not in p.relative_to(path).parts}

def baseline():
    tracked = command('git', 'ls-files')['stdout'].splitlines()
    source = ROOT.parent.parent / 'Darktide-Source-Code'
    data = {'target': str(ROOT), 'created_local': '2026-10-03 America/Sao_Paulo',
            'target_revision': command('git', 'rev-parse', 'HEAD'), 'target_status': command('git', 'status', '--porcelain=v1', '--branch'),
            'tracked_hashes': {p: hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in tracked},
            'python': sys.version, 'platform': platform.platform(), 'lupa': importlib.import_module('lupa').__version__,
            'source_revision': command('git', 'rev-parse', 'HEAD', cwd=source),
            'source_status': command('git', 'status', '--short', '--branch', cwd=source),
            'source_latest': command('git', 'ls-remote', 'origin', 'HEAD', cwd=source),
            'references': {}}
    for name, path in [('BetterInventory', ROOT.parent/'BetterInventory'), ('supplied', ROOT.parent/'RealmsWaves_updated')]:
        data['references'][name] = {'revision': command('git', 'rev-parse', 'HEAD', cwd=path),
                                    'status': command('git', 'status', '--porcelain=v1', cwd=path),
                                    'tracked_hashes': {p: hashlib.sha256((path/p).read_bytes()).hexdigest() for p in command('git','ls-files',cwd=path)['stdout'].splitlines()}}
    for name in ('Realms', 'SoloPlay', 'dmf', 'RealmsWaves'):
        path = ROOT.parent.parent/'mods'/name
        data['references']['installed_'+name] = {'path':str(path), 'hashes':hashes(path)}
        if (path/'info.json').exists():
            data['references']['installed_'+name]['metadata'] = json.loads((path/'info.json').read_text(encoding='utf-8-sig'))
    data['load_order'] = (ROOT.parent.parent/'mods/mod_load_order.txt').read_text(encoding='utf-8-sig')
    for runtime in ('lua55','luajit21'):
        vm=importlib.import_module('lupa.'+runtime).LuaRuntime()
        data[runtime]={'version':vm.eval('_VERSION'), 'jit':vm.eval('jit and jit.version or nil'), 'gc_kb':vm.eval("collectgarbage('count')")}
    data['hardware']=command('powershell','-NoProfile','-Command', "Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors | ConvertTo-Json; Get-CimInstance Win32_ComputerSystem | Select-Object TotalPhysicalMemory | ConvertTo-Json")
    (OUT/'baseline.json').write_text(json.dumps(data,indent=2,ensure_ascii=False),encoding='utf-8')
    print('baseline captured:', data['target_revision']['stdout'].strip())

def harness(name):
    src=(ROOT/'tools'/name).read_text(encoding='utf-8-sig')
    tree=ast.parse(src)
    return next(ast.literal_eval(node.value) for node in tree.body if isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='harness' for t in node.targets))

def execute(name, runtime='luajit21', suffix='', mutations=None, previews=False, prefix_only=False):
    vm=importlib.import_module('lupa.'+runtime).LuaRuntime(unpack_returned_tuples=True)
    program=harness(name)
    diagnostics={}
    def convert(value):
        if hasattr(value,'items'):
            return {str(k):convert(v) for k,v in value.items()}
        return value
    vm.globals().AUDIT_EMIT=lambda key,value:diagnostics.__setitem__(key,convert(value))
    vm.globals().AUDIT_NOW=time.perf_counter
    if mutations:
        vm.globals().AUDIT_SOURCE=lambda path:mutations.get(str(path).replace('\\','/'))
        vm.execute("local real=dofile; dofile=function(path) local src=AUDIT_SOURCE(path); if src then local fn,err=(loadstring or load)(src,'@'..path); assert(fn,err); return fn() end; return real(path) end")
    if prefix_only:
        marker = '-- ---- groups.parse' if name=='logic_test.py' else '-- guard: the view may only override'
        program = program[:program.index(marker)]+'\n'+suffix+'\nreturn table.concat(results, "\\n")'
    elif suffix:
        pos=program.rfind('return table.concat(results')
        assert pos>=0
        program=program[:pos]+'\ndo\n'+suffix+'\nend\n'+program[pos:]
    if name=='logic_test.py':
        args=(str(BASE).replace('\\','/'),)
    elif name=='editor_test.py':
        dump_dir=OUT/'widgets'
        if previews: dump_dir.mkdir(exist_ok=True)
        args=(str(ROOT).replace('\\','/'),'',str(dump_dir).replace('\\','/') if previews else '', '1' if previews else '')
    else:
        args=(str(ROOT).replace('\\','/'),)
    started=time.perf_counter()
    try:
        result=vm.execute(program,*args)
        lines=result.splitlines()
        return {'runtime':runtime,'script':name,'seconds':time.perf_counter()-started,
                'passes':sum(l.startswith('PASS ') for l in lines), 'failures':[l for l in lines if l.startswith('FAIL ')],
                'output':result,'diagnostics':diagnostics,'error':None}
    except Exception as error:
        return {'runtime':runtime,'script':name,'seconds':time.perf_counter()-started,'error':str(error),'diagnostics':diagnostics}

def suites():
    summaries=[]
    for runtime in ('lua55','luajit21'):
        for name in ('logic_test.py','editor_test.py','entry_test.py','hud_test.py'):
            result=execute(name,runtime,previews=runtime=='lua55' and name=='editor_test.py')
            (OUT/(runtime+'_'+name+'.json')).write_text(json.dumps(result,indent=2),encoding='utf-8')
            summary={k:v for k,v in result.items() if k!='output'}
            summaries.append(summary)
            print(json.dumps(summary))
        bootstrap="import sys,runpy; from lupa."+runtime+" import LuaRuntime; import lupa; lupa.LuaRuntime=LuaRuntime; runpy.run_path(sys.argv[1],run_name='__main__')"
        result=command(sys.executable,'-X','utf8','-c',bootstrap,'tools/check_lua.py')
        (OUT/(runtime+'_compile.json')).write_text(json.dumps(result,indent=2),encoding='utf-8')
        print(runtime,'compile',result['exit'],result['stdout'].splitlines()[-1:])
    result=command(sys.executable,'-X','utf8','tools/check_docs.py')
    (OUT/'docs_check.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    (OUT/'suites.json').write_text(json.dumps(summaries,indent=2),encoding='utf-8')

def probes(only=None):
    for source, suite in [('logic_probes.lua','logic_test.py'),('editor_probes.lua','editor_test.py')]:
        if only and only != source: continue
        code=(OUT/source).read_text(encoding='utf-8')
        for runtime in ('lua55','luajit21'):
            result=execute(suite,runtime,suffix=code,prefix_only=True)
            (OUT/(runtime+'_'+source+'.json')).write_text(json.dumps(result,indent=2),encoding='utf-8')
            print(json.dumps({k:v for k,v in result.items() if k not in ('output','diagnostics')}))

if __name__=='__main__':
    {'baseline':baseline,'suites':suites,'probes':probes,'logic':lambda:probes('logic_probes.lua')}[sys.argv[1]]()
```

### Script: logic_probes.lua

```lua
local Presets=load('catalog/presets')
local Cards=load('catalog/cards')
local hooks={}
mod.hook=function(self,cls,method,fn) hooks[tostring(cls)..'.'..method]=fn end
mod.hook_safe=function(self,cls,method,fn) hooks[tostring(cls)..'.'..method..'!']=fn end
mod.hook_require=function() end
mod.is_enabled=function() return false end
mod.command=function() end
ALIVE=setmetatable({}, {__index=function() return true end})
Vector3=function(x,y,z) return {x=x,y=y,z=z} end
Unit={world_rotation=function() return 'rot' end,set_local_scale=function(u,node,v) u.size=v.x end}
ScriptUnit={has_extension=function(u,system) return type(u)=='table' and system=='buff_system' and u.buffs or nil end}
local P={is_available=function() return false end, send_state=function() return false end,
 send_scales=function() return false end,send_hello=function() return false end,
 send_waves=function() return false end,PROTO=2,VERSION='2.0.0'}
local Bypass=load('spawn/budget_bypass'); Bypass.install()
local Tuning=load('spawn/tuning'); Tuning.init({protocol=P}); Tuning.install()
local Execute=load('spawn/execute')
local spawned_count=0
Managers.state.extension={system=function() return {get_side_from_name=function() return {side_id=2} end} end}
Managers.state.unit_spawner={game_object_id=function(self,u) return u.id end}
Managers.state.minion_spawn={request_param_table=function() return {} end,
 spawn_minion=function(self,breed,pos,rot,side,param)
  spawned_count=spawned_count+1
  local stats={melee_attack_speed=1, ranged_attack_speed=1}
  local buffs={stat_buffs=function() return stats end}
  return {breed=breed,id=spawned_count,buffs=buffs}
 end}
local Positions={player_units=function() return {'player'} end,random_player_unit=function() return 'player' end,
 candidates=function() return {'point'} end,pick=function() return 'point' end,spread=function(p) return p end}
Execute.init({positions=Positions,bypass=Bypass,groups=Groups,tuning=Tuning})
local Director=load('core/director')
Director.init({events=Events,groups=Groups,protocol=P,execute=Execute,votes=Votes,positions=Positions,presets=Presets,cards=Cards,tuning=Tuning})
local function get(id) return settings[id] end
local function set(id,v) settings[id]=v end
local function reset()
 for k in pairs(settings) do settings[k]=nil end
 settings.max_alive=1000; settings.max_per_wave=500
 settings.mode='random'; settings.interval_random=false; settings.initial_delay=600; settings.interval_min=600
 is_server=true; spawned_count=0
 Director.on_enter_gameplay(); Director.on_mission_started(); Director.update(0.01)
end
reset()
local live={id=100,buffs={stat_buffs=function(self) return self.stats end,stats={melee_attack_speed=1}}}
Bypass.track(live); Tuning.apply(live,{gap=50,size=130},'chaos_hound')
local before=Tuning.status(); local tracked_before=Bypass.count(); local stop_ok=Director.stop()
AUDIT_EMIT('stop_ownership',{stop_ok=stop_ok,alive=ALIVE[live],tracked_before=tracked_before,tracked_after=Bypass.count(),
 tuned_before=before.tuned,tuned_after=Tuning.status().tuned,sizes_before=before.sizes_known,sizes_after=Tuning.status().sizes_known})

reset()
Execute.start_wave({name='paused_repeat',parts=Groups.parse('2 hounds@2'),rep_every=1,rep_for=10})
Director.pause(true); local countdown=Director.view().remaining
for i=1,20 do Director.update(0.2) end
AUDIT_EMIT('pause_repeat',{paused=Director.is_paused(),countdown_before=countdown,countdown_after=Director.view().remaining,spawned=spawned_count,jobs=Execute.status().jobs})

reset()
local actual_entry=load('RealmsWaves')
mod.rw.director=Director; Execute.start_wave({name='disabled',parts=Groups.parse('2 hounds')})
mod.update(0.2)
AUDIT_EMIT('disabled_update',{is_enabled=mod:is_enabled(),spawned=spawned_count,on_disabled_exists=type(mod.on_disabled)=='function'})

reset()
Events.set_def(set,'wave_small','Empty Standard',{},Groups)
local empty=Events.get('wave_small',get,Groups)
AUDIT_EMIT('empty_standard',{stored=settings.wave_def_wave_small,parts=#empty.parts,enemies=Groups.total_count(empty.parts),pool=#Events.build_pool(get,Groups)})

-- Aggregate pressure with legal fixed timers; hold all spawning at the legal alive limit.
reset()
settings.mult_normal=500; settings.mult_special=500; settings.max_alive=10
for i=1,10 do Bypass.track({id=i}) end
for _,key in ipairs(Events.keys()) do
 Events.set_def(set,key,key,Groups.parse('60 hounds@60, 60 poxwalkers@60'),Groups)
 settings['on_'..key]=true; settings['ev_'..key]=5; settings['re_'..key]=1; settings['rf_'..key]=3600
end
local start_heap=collectgarbage('count'); local peak=0; local checkpoints={}
for i=1,30 do
 Director.update(1)
 local status=Execute.status(); peak=math.max(peak,status.queued)
 if i==1 or i==10 or i==30 then checkpoints[i]={jobs=status.jobs,queued=status.queued,heap_kb=collectgarbage('count')} end
end
AUDIT_EMIT('aggregate_jobs',{waves=#Events.keys(),per_job_cap=1000,seconds=30,start_heap_kb=start_heap,checkpoints=checkpoints})
Director.on_exit_gameplay(); collectgarbage('collect')
AUDIT_EMIT('aggregate_cleanup',{jobs=Execute.status().jobs,queued=Execute.status().queued,tracked=Bypass.count(),heap_kb=collectgarbage('count')})

-- Malformed state behavior and session-order rollback are separate from authority.
reset(); is_server=false
local malformed_ok,malformed_err=pcall(Director.on_state,'host_peer',{p='waiting',m='vote',k={false}})
Director.on_state('host_peer',{p='waiting',m='random',r=10,b=2,k={}})
Director.on_state('host_peer',{p='waiting',m='random',r=99,b=1,k={}})
AUDIT_EMIT('state_order',{malformed_ok=malformed_ok,malformed_error=tostring(malformed_err),ballot_after_older=Director.view().ballot_id,remaining_after_older=Director.view().remaining})
Director.on_exit_gameplay()

-- Repeated valid or invalid imports use only isolated settings.
is_server=true
for k in pairs(settings) do settings[k]=nil end
local small=Presets.encode({name='small',waves={}})
for _,key in ipairs(Events.keys()) do Events.set_def(set,key,key,Groups.parse('60 hounds, 60 poxwalkers'),Groups) end
local large=Presets.encode(Presets.capture(get,Events,Groups))
local warm=Presets.decode(large,Events,Groups)
collectgarbage('collect'); local preset_start=collectgarbage('count')
local count,invalid=0,0
for i=1,1000 do
 local decoded=Presets.decode(i%2==0 and small or large,Events,Groups)
 Presets.apply(decoded,set,Events,Groups); count=count+1
 if not Presets.decode(large:sub(1,-2),Events,Groups) then invalid=invalid+1 end
end
collectgarbage('collect')
AUDIT_EMIT('L6_presets',{cycles=count,invalid_rejected=invalid,small_bytes=#small,large_bytes=#large,start_heap_kb=preset_start,end_heap_kb=collectgarbage('count'),settings_keys=(function() local n=0 for _ in pairs(settings) do n=n+1 end return n end)()})

-- Thirty enter/start/end/abort/rejoin transitions with queued work and late data.
reset(); local lifecycle_ok=true
for i=1,30 do
 Director.on_enter_gameplay(); Director.on_mission_started(); Director.update(0.1)
 Execute.start_wave({name='transition',parts=Groups.parse('60 hounds@2'),rep_every=1,rep_for=60})
 Director.on_peer_left('peer_'..i); Director.on_exit_gameplay()
 local status=Execute.status(); lifecycle_ok=lifecycle_ok and status.jobs==0 and status.queued==0 and status.tracked==0 and Director.view().phase=='off'
end
AUDIT_EMIT('L7_missions',{transitions=30,cleanup=lifecycle_ok,tuning_pending=Tuning.status().pending})

-- Accelerated selection/update workload. Logs do not retain per-cycle state.
reset(); settings.initial_delay=0; settings.interval_min=5; settings.interval_max=5; settings.mode='tarot'
settings.tarot_default_cooldown=30
Director.on_enter_gameplay(); Director.on_mission_started()
for i=1,10000 do Director.update(0.016); Director.view() end
AUDIT_EMIT('L4_updates',{iterations=10000,jobs=Execute.status().jobs,queued=Execute.status().queued,tracked=Bypass.count(),cooldowns=(function() local n=0 for _ in pairs(Director.cooldown_map()) do n=n+1 end return n end)()})
Director.on_exit_gameplay(); collectgarbage('collect')

-- Latest-arrival wins does not imply transport sequence protection.
Tuning.receive({{id=999,pct=180}}); Tuning.receive({{id=999,pct=120}})
Managers.state.unit_spawner={unit_exists=function() return true end,unit=function() return live end}
Tuning.update_client(0.1)
AUDIT_EMIT('scale_order',{applied=live.size,pending=Tuning.status().pending})
Tuning.reset()

-- Fixed seeds for mixed life-cycle/fault orders, including missing handles.
for _,seed in ipairs({12345,49374,424242}) do
 math.randomseed(seed); reset()
 local operations={}
 for i=1,1000 do
  local op=math.random(1,10);operations[i]=op
  if op==1 then Execute.start_wave({name='mixed',parts=Groups.parse('2 hounds@1'),rep_every=1,rep_for=10})
  elseif op==2 then Director.pause(math.random(0,1)==1)
  elseif op==3 then Director.on_exit_gameplay(); Director.on_enter_gameplay(); Director.on_mission_started()
  elseif op==4 then Director.on_peer_left('peer')
  elseif op==5 then Director.stop(); Director.force_start()
  elseif op==6 then Tuning.receive({{id=math.random(1,100),pct=math.random(25,300)}})
  elseif op==7 then Director.update(0.2)
  elseif op==8 then
   local owned=Bypass.units(1);if owned[1] then ALIVE[owned[1]]=false;Bypass.untrack(owned[1]);Tuning.update(1) end
  elseif op==9 then Director.on_state('host_peer',{p='waiting',m='random',r=99,b=1,k={}})
  else Presets.apply(Presets.decode(small,Events,Groups),set,Events,Groups);Director.on_peer_left('peer') end
 end
 Director.on_exit_gameplay()
 AUDIT_EMIT('L8_seed_'..seed,{operations=1000,sequence=operations,jobs=Execute.status().jobs,tracked=Bypass.count(),pending=Tuning.status().pending})
end
```

### Script: editor_probes.lua

```lua
local Events,Groups,Presets=mod.rw.events,mod.rw.groups,mod.rw.presets
local function count(t) local n=0 for _ in pairs(t or {}) do n=n+1 end return n end
local function fresh()
 local instance=setmetatable({},View); View.init(instance,{})
 instance.view_name='realms_waves_editor'; instance:_on_view_requirements_complete()
 return instance
end
view=fresh()
view:_open_detail('wave_small')
local before=#view._parts
view._parts={}; view:_save()
AUDIT_EMIT('empty_standard_ui',{before=before,after=#view._parts,enemies=Groups.total_count(view._parts),stored=settings.wave_def_wave_small})
view:on_exit(); view=nil
for k in pairs(settings) do settings[k]=nil end
local weak=setmetatable({},{__mode='k'})
local function cycle(repetitions,edit,navigate)
 for i=1,repetitions do
  local instance=fresh(); weak[instance]=true
  if edit then instance:_open_detail('custom_1'); instance._parts=Groups.parse('2 hounds'); instance:_save(); instance:cb_back() end
  if navigate then
   instance:_open_detail('wave_small'); instance:cb_face(); instance:cb_back()
   instance._screen='picker'; instance:_apply_screen(); instance:cb_back()
   instance._screen='mods'; instance._part_index=1; instance:_apply_screen(); instance:cb_back()
   instance._screen='tune'; instance._part_index=1; instance:_apply_screen(); instance:cb_back()
   local popup=dofile(BASE..'/ui/wave_editor_components.lua').Popup
   popup.open(instance,{label='scratch',value='x',set=function() end}); popup.cancel(instance)
   instance:cb_back(); instance:cb_scroll(1); instance:cb_scroll(-1)
  end
  instance:on_exit()
 end
end
for _,kind in ipairs({'unchanged','edited','navigation'}) do
 for _,n in ipairs({100,1000}) do
  cycle(5,kind=='edited',kind=='navigation'); collectgarbage('collect')
  local before=collectgarbage('count'); local started=os.clock()
  cycle(n,kind=='edited',kind=='navigation')
  local loaded=collectgarbage('count'); collectgarbage('collect'); collectgarbage('collect')
  AUDIT_EMIT('L1_L2_'..kind..'_'..n,{cycles=n,seconds=os.clock()-started,start_kb=before,load_kb=loaded,retained_kb=collectgarbage('count')-before,weak_views=count(weak),text_active=mod.rw.text_input_active==true})
 end
end

-- Five batches make retention slope and timing variability visible.
if jit then jit.off(); jit.flush() end
for batch=1,5 do
 collectgarbage('collect'); local before=collectgarbage('count'); local started=os.clock()
 cycle(100,false,true); local load=collectgarbage('count'); collectgarbage('collect')
 AUDIT_EMIT('retention_batch_'..batch,{cycles=100,seconds=os.clock()-started,start_kb=before,load_kb=load,after_kb=collectgarbage('count'),weak_views=count(weak)})
end
if jit then jit.on() end
```

### Script: reload_probe.py

```python
import json
from audit import OUT, ROOT, harness
import importlib

program=harness('entry_test.py')
program=program[:program.index('local dmf_hooks = {}')]
program += r'''
-- Real game EventManager, rather than the test's overwrite-by-event-name stub.
class=function(name) local c={}; c.__index=c; return c end
table.is_empty=function(t) return next(t)==nil end
local E=dofile(MODROOT..'/../../Darktide-Source-Code/scripts/managers/event/event_manager.lua')
local manager=setmetatable({},E); E.init(manager); Managers.event=manager
local prototype=mod
local helper_names={'hook','hook_safe','hook_require','register_hud_element','add_require_path','register_view','command','get','set','echo','warning','error','localize','io_dofile'}
local active
get_mod=function(name) if name=='DMF' then return dmf_mod elseif name=='Realms' then return nil else return active end end
local weak=setmetatable({},{__mode='k'})
local function count(t) local n=0 for _ in pairs(t or {}) do n=n+1 end return n end
local baseline
for i=1,100 do
 active={}; for _,key in ipairs(helper_names) do active[key]=prototype[key] end
 dofile(BASE..'/RealmsWaves.lua'); active.on_all_mods_loaded()
 weak[active]=true
 active.on_unload()
 -- DMF on_reload restores the engine hook originals and removes custom views.
 hooks={}; views={}; commands={}; hook_requires={}
 active=nil
 collectgarbage('collect'); collectgarbage('collect')
 if i==1 then baseline=collectgarbage('count') end
 if i==1 or i==25 or i==50 or i==100 then
  AUDIT_EMIT('reload_'..i,{cycles=i,objective_registrations=count(manager._events.event_mission_objective_start),death_registrations=count(manager._events.event_player_died),retained_mods=count(weak),heap_kb=collectgarbage('count'),growth_kb=collectgarbage('count')-baseline})
 end
end
-- Counterfactual control changes only scratch cleanup and confirms the retaining owner.
for object in pairs(manager._events.event_mission_objective_start) do manager:unregister(object,'event_mission_objective_start') end
for object in pairs(manager._events.event_player_died) do manager:unregister(object,'event_player_died') end
collectgarbage('collect'); collectgarbage('collect')
AUDIT_EMIT('unregister_control',{retained_mods=count(weak),heap_kb=collectgarbage('count')})
return true
'''
for runtime in ('lua55','luajit21'):
    vm=importlib.import_module('lupa.'+runtime).LuaRuntime(unpack_returned_tuples=True)
    if runtime=='luajit21': vm.execute('jit.off(); jit.flush()')
    diagnostics={}
    vm.globals().AUDIT_EMIT=lambda key,value:diagnostics.__setitem__(key,dict(value.items()))
    try:
        vm.execute(program,str(ROOT).replace('\\','/'))
        result={'runtime':runtime,'jit':'off for retention','diagnostics':diagnostics,'error':None}
    except Exception as e: result={'runtime':runtime,'diagnostics':diagnostics,'error':str(e)}
    (OUT/(runtime+'_reload.json')).write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result),flush=True)
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
 ('omit_unload_reset', 'RealmsWaves.lua', '\t\tRW.execute.reset()', '\t\tdo end -- scratch: omit executor reset', 'entry_test.py'),
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
mod.get_name=function() return 'RealmsWaves' end
mod.is_enabled=function() return true end
mod.pcall=function(self,fn,...) return pcall(fn,...) end
local handlers={}; local attempts,delivered={},{}
local reject=true
local SC={is_available=function() return true end,register_protocol=function() end,
 register_host_handler=function(proto,name,fn) handlers[name]=fn end,register_client_handler=function() end,
 register_disconnect_handler=function() end,register_ready_handler=function() end,
 send_to_clients=function() return true end,send_to_client=function() return true end,
 is_peer_available=function() return true end,ready_peer_ids=function() return {'good','failed'} end,
 send_to_peer=function(peer,proto,name,payload)
   attempts[peer]=(attempts[peer] or 0)+1
   if reject and peer=='failed' then return false,'injected transport rejection' end
   delivered[peer]=(delivered[peer] or 0)+1; return true
 end}
local MN=dofile(MODROOT_REALMS..'/scripts/mods/Realms/core/mod_network.lua')
MN.install(SC); MN.register(mod,'rw_scales',function() end)
handlers.mod_network_manifest(1,'good',{rpcs={RealmsWaves={'rw_scales'}}})
handlers.mod_network_manifest(2,'failed',{rpcs={RealmsWaves={'rw_scales'}}})
local broadcast_ok=MN.send(mod,'rw_scales','others',{{1,130}})
AUDIT_EMIT('realms_partial_broadcast',{success=broadcast_ok,attempts=attempts,delivered=delivered})
attempts={};delivered={}
Tuning.reset(); Tuning.init({protocol={is_available=function() return true end,
 send_scales=function(entries,peer) return MN.send(mod,'rw_scales',peer or 'others',entries) end}})
local unit={id=77,buffs={stat_buffs=function() return {} end}}
Tuning.apply(unit,{size=130},'chaos_hound'); Tuning.update(1)
local failed_before=attempts.failed or 0
reject=false; for i=1,10 do Tuning.update(1) end
AUDIT_EMIT('scale_retry_contract',{failed_attempts_before=failed_before,failed_attempts_after=attempts.failed or 0,
 failed_deliveries=delivered.failed or 0,good_deliveries=delivered.good or 0,sizes=Tuning.status().sizes_known})
'''
code="local MODROOT_REALMS="+json.dumps(str(ROOT.parent.parent/'mods/Realms').replace('\\','/'))+'\n'+code
for runtime in ('lua55','luajit21'):
    result=execute('logic_test.py',runtime,suffix=code,prefix_only=True)
    (OUT/(runtime+'_contract.json')).write_text(json.dumps(result,indent=2))
    print(json.dumps({k:v for k,v in result.items() if k!='output'}))
```

### Script: followup_probes.py

```python
import json
from audit import OUT,ROOT,execute
setup=(OUT/'logic_probes.lua').read_text().split('reset()\nlocal live=')[0]
logic=setup+r'''
reset()
local live={id=100,buffs={stats={melee_attack_speed=1},stat_buffs=function(self) return self.stats end}}
Bypass.track(live);Tuning.apply(live,{gap=50,size=130},'chaos_hound')
local initial=live.buffs.stats.melee_attack_speed
live.buffs.stats.melee_attack_speed=1;hooks['MinionBuffExtension._update_stat_buffs_and_keywords!'](live.buffs)
local before_stop=live.buffs.stats.melee_attack_speed
Director.stop();live.buffs.stats.melee_attack_speed=1;hooks['MinionBuffExtension._update_stat_buffs_and_keywords!'](live.buffs)
AUDIT_EMIT('stop_stat_recompute',{initial=initial,before_stop=before_stop,after_stop=live.buffs.stats.melee_attack_speed,alive=ALIVE[live]})
reset();local entry=load('RealmsWaves');mod.rw.director=Director
local enabled=true;mod.is_enabled=function() return enabled end
mod.get_name=function() return 'RealmsWaves' end
mod.get_internal_data=function() return false end
mod.disable_all_hooks=function() end;mod.enable_all_hooks=function() end
local dmf={mods={RealmsWaves=mod},mods_unloading_order={'RealmsWaves'},get=function() return nil end,set=function() end,
 safe_call_nr=function(owner,label,fn,...) return fn(...) end,
 set_internal_data=function(owner,key,v) if key=='is_enabled' then enabled=v end end,
 inject_hud_elements=function() end,remove_injected_hud_elements=function() end}
get_mod=function(name) if name=='DMF' then return dmf end return mod end
dofile(REF_DMF..'/modules/core/events.lua');dofile(REF_DMF..'/modules/core/toggling.lua')
Execute.start_wave({name='disabled_dmf',parts=Groups.parse('2 hounds')})
dmf.set_mod_state(mod,false,false);dmf.mods_update_event(.2)
AUDIT_EMIT('actual_dmf_disable',{enabled=mod:is_enabled(),spawned=spawned_count,on_disabled_exists=type(mod.on_disabled)=='function'})
'''
logic='local REF_DMF='+json.dumps(str(ROOT.parent.parent/'mods/dmf/scripts/mods/dmf').replace('\\','/'))+'\n'+logic
editor=(OUT/'editor_probes.lua').read_text().split('view=fresh()')[0]+r'''
view=fresh();view:_open_detail('wave_small');view._parts=Groups.parse('1 hound');view:_save()
local before=#view._parts;view:_remove_part(1)
AUDIT_EMIT('standard_last_group_guard',{before=before,after=#view._parts,enemies=Groups.total_count(view._parts)})
view:on_exit()
'''
for runtime in ('lua55','luajit21'):
 for label,suite,code in [('contracts','logic_test.py',logic),('editor_guard','editor_test.py',editor)]:
  r=execute(suite,runtime,suffix=code,prefix_only=True)
  (OUT/(runtime+'_'+label+'_followup.json')).write_text(json.dumps(r,indent=2))
  print(json.dumps({k:v for k,v in r.items() if k!='output'}))
r=execute('editor_test.py','lua55',previews=True)
(OUT/'lua55_real_text_preview.json').write_text(json.dumps(r,indent=2))
print('real text preview:',r.get('error'),r.get('failures'))
```

### Script: benchmarks.py

```python
import json
from audit import OUT, execute
setup=(OUT/'logic_probes.lua').read_text().split('reset()\nlocal live=')[0]
code=setup+r'''
local Deck=load('ui/deck')
local function count(t) local n=0 for _ in pairs(t) do n=n+1 end return n end
for _,n in ipairs({10,32,100,1000,10000}) do
 local items={}
 for i=1,n do items[i]={key=tostring(i),threat=i%5,chance=i%10,enemies=i%60,suit=i%12} end
 local warm=Deck.sorted(items,'threat',false)
 local operations=n<=100 and 1000 or (n<=1000 and 100 or 10)
 for rep=1,5 do
  collectgarbage('collect'); local before=collectgarbage('count'); local t=AUDIT_NOW()
  for i=1,operations do local sorted=Deck.sorted(items,'threat',false); assert(#sorted==n and items[1].key=='1') end
  local elapsed=AUDIT_NOW()-t; local load=collectgarbage('count');collectgarbage('collect')
  AUDIT_EMIT('L5_sort_'..n..'_'..rep,{n=n,operations=operations,seconds=elapsed,baseline_kb=before,load_kb=load,after_kb=collectgarbage('count')})
 end
end
for _,kind in ipairs({'representative','max_legal'}) do
 for _,n in ipairs({1000,10000}) do
  for rep=1,5 do
   math.randomseed(424242+rep);reset(); settings.initial_delay=0;settings.interval_min=5;settings.mode='tarot'
   if kind=='max_legal' then
    settings.max_alive=10;settings.mult_normal=500;settings.mult_special=500
    for i=1,10 do Bypass.track({id=i}) end
    for _,key in ipairs(Events.keys()) do
     Events.set_def(set,key,key,Groups.parse('60 hounds@60, 60 poxwalkers@60'),Groups)
     settings['on_'..key]=true;settings['ev_'..key]=5;settings['re_'..key]=1;settings['rf_'..key]=3600
    end
   end
   Director.on_enter_gameplay();Director.on_mission_started()
   collectgarbage('collect');local before=collectgarbage('count');local t=AUDIT_NOW()
   for i=1,n do Director.update(0.016);Director.view() end
   local seconds=AUDIT_NOW()-t;local state=Execute.status();local loaded=collectgarbage('count')
   Director.on_exit_gameplay();collectgarbage('collect');collectgarbage('collect')
   AUDIT_EMIT('L4_'..kind..'_'..n..'_'..rep,{iterations=n,simulated_seconds=n*.016,seconds=seconds,
    active_jobs=state.jobs,active_queued=state.queued,active_tracked=state.tracked,baseline_kb=before,load_kb=loaded,
    after_kb=collectgarbage('count'),cleanup_jobs=Execute.status().jobs,cleanup_tracked=Bypass.count()})
  end
 end
end
-- Retention diagnostics use tracing disabled, after JIT timing above.
if jit then jit.off();jit.flush() end
for rep=1,5 do
 reset();settings.max_alive=10;settings.mult_normal=500;settings.mult_special=500
 for _,key in ipairs(Events.keys()) do
  Events.set_def(set,key,key,Groups.parse('60 hounds@60, 60 poxwalkers@60'),Groups)
  settings['on_'..key]=true;settings['ev_'..key]=5;settings['re_'..key]=1;settings['rf_'..key]=3600
 end
 for i=1,10 do Bypass.track({id=i}) end
 collectgarbage('collect');local before=collectgarbage('count')
 for i=1,30 do Director.update(1) end
 collectgarbage('collect');local active=collectgarbage('count');local st=Execute.status()
 Director.on_exit_gameplay();collectgarbage('collect');collectgarbage('collect')
 AUDIT_EMIT('L4_retention_'..rep,{baseline_kb=before,active_collected_kb=active,after_kb=collectgarbage('count'),jobs=st.jobs,queued=st.queued})
end
reset()
local small=Presets.encode({name='small',waves={}})
for _,key in ipairs(Events.keys()) do Events.set_def(set,key,key,Groups.parse('60 hounds, 60 poxwalkers'),Groups) end
local large=Presets.encode(Presets.capture(get,Events,Groups))
local function switch(n)
 for i=1,n do
  local decoded=assert(Presets.decode(i%2==0 and small or large,Events,Groups))
  Presets.apply(decoded,set,Events,Groups)
  assert(not Presets.decode(large:sub(1,-2),Events,Groups))
 end
end
switch(10);collectgarbage('collect')
for _,n in ipairs({100,1000}) do
 for rep=1,5 do
  collectgarbage('collect');local before=collectgarbage('count');local t=os.clock()
  switch(n);local seconds=os.clock()-t;local loaded=collectgarbage('count');collectgarbage('collect')
  AUDIT_EMIT('L6_'..n..'_'..rep,{switches=n,seconds=seconds,baseline_kb=before,load_kb=loaded,
   after_kb=collectgarbage('count'),keys=count(settings),small_bytes=#small,large_bytes=#large})
 end
end
if jit then jit.on() end
'''
for runtime in ('lua55','luajit21'):
    result=execute('logic_test.py',runtime,suffix=code,prefix_only=True)
    (OUT/(runtime+'_benchmarks.json')).write_text(json.dumps(result,indent=2))
    print(json.dumps({k:v for k,v in result.items() if k not in ('output','diagnostics')}))
```

### Script: hud_stress.py

```python
import json
from audit import OUT,execute
code=r'''
-- Base draw performs native rendering in game; avoid the harness draw-history allocation.
HudElementBase.draw=function() end
local weak=setmetatable({},{__mode='k'})
for _,kind in ipairs({'hand','roulette','reveal','rot','max_rot','legacy','off'}) do
 for _,n in ipairs({1000,10000}) do
  for rep=1,5 do
   settings.tarot_scale=nil;settings.tarot_opacity=nil
   if kind=='max_rot' then settings.tarot_scale=200;settings.tarot_opacity=10 end
   local el=new_element();weak[el]=true;local render_settings={}
   current_view=view_of({remaining=9.5,hand_seq=100+rep})
   if kind=='legacy' then current_view={phase='waiting',mode='random',remaining=30,ballot_id=1,cands={{name='Hound Frenzy',pct=20,votes=0}},version=1}
   elseif kind=='off' then current_view={phase='off'}
   elseif kind=='reveal' or kind=='rot' or kind=='max_rot' then current_view.phase='waiting';current_view.drawn=true;current_view.hand_seconds=0 end
   if kind=='max_rot' then current_view.hand[5]=card('fifth','The Watching Moon','murmur',5,{},'',{},false,3600) end
   local function step(i)
    if kind=='roulette' then current_view.remaining=9.5-(i%600)/60
    elseif kind=='reveal' then current_view.drawn_age=.05+(i%100)/100*1.4
    elseif kind=='rot' or kind=='max_rot' then current_view.drawn_age=1.7+(i%100)/100*1.8 end
    frame(el);Element.draw(el,.016,0,nil,render_settings,nil)
   end
   for i=1,100 do step(i) end
   collectgarbage('collect');local before=collectgarbage('count');local t=AUDIT_NOW()
   for i=1,n do step(i); if i%100==0 then local problems=audit(el);assert(#problems==0,table.concat(problems,';')) end end
   local seconds=AUDIT_NOW()-t;local loaded=collectgarbage('count')
   el=nil;collectgarbage('collect');collectgarbage('collect')
   local owned=0;for _ in pairs(weak) do owned=owned+1 end
   AUDIT_EMIT('HUD_'..kind..'_'..n..'_'..rep,{iterations=n,seconds=seconds,baseline_kb=before,load_kb=loaded,after_kb=collectgarbage('count'),retained_elements=owned})
  end
 end
end
'''
for runtime in ('lua55','luajit21'):
    r=execute('hud_test.py',runtime,suffix=code)
    (OUT/(runtime+'_hud_stress.json')).write_text(json.dumps(r,indent=2))
    print(json.dumps({k:v for k,v in r.items() if k not in ('output','diagnostics')}))
```

### Script: selection_probe.py

```python
import json
from audit import OUT,execute
setup=(OUT/'logic_probes.lua').read_text().split('reset()\nlocal live=')[0]
code=setup+r'''
reset();math.randomseed(424242)
for _,key in ipairs(Events.keys()) do settings['on_'..key]=false end
settings.on_wave_small=true;settings.pct_wave_small=10
settings.on_wave_medium=true;settings.pct_wave_medium=1
local pool,counts,total=Director.simulate(20000)
AUDIT_EMIT('weighted_selection',{seed=424242,samples=20000,raw_total=total,counts=counts,expected_small=10/11})
assert(math.abs(counts.wave_small/20000-10/11)<.02)
for key in pairs(settings) do settings[key]=nil end
settings.mode='tarot';settings.tarot_cards=5;settings.tarot_default_cooldown=0
settings.initial_delay=0;settings.interval_min=5;settings.interval_max=5;settings.interval_random=false
Director.on_enter_gameplay();Director.on_mission_started();Director.update(.01)
local view=Director.view();local seen={};local unique=true
for _,card in ipairs(view.hand or {}) do if seen[card.key] then unique=false end;seen[card.key]=true end
AUDIT_EMIT('tarot_deal',{cards=#(view.hand or {}),unique=unique,winner=view.win})
assert(#view.hand==5 and unique and view.win>=1 and view.win<=5)
'''
for rt in ('lua55','luajit21'):
 r=execute('logic_test.py',rt,suffix=code,prefix_only=True)
 (OUT/(rt+'_selection.json')).write_text(json.dumps(r,indent=2))
 print(json.dumps({k:v for k,v in r.items() if k!='output'}))
```

### Script: edge_probe.py

```python
import json
from audit import OUT,execute
setup=(OUT/'logic_probes.lua').read_text().split('reset()\nlocal live=')[0]
code=setup+r'''
reset();local cases={
 '999999999999999999999999999999999999999 hounds',
 '60 hounds, 60 poxwalkers, 1 crusher',
 '1 hound{gap=99999999999999999999999999999999999999}',
 '1 hound{size=-1}', '0 hound@60', '1 hound{size=nan}', '1 hound{size=inf}',
 '1 hound{size=300}', '1 hound{size=301}', '1 hound{gap=25}',
 '1 hound{health=1e309}'}
for i,text in ipairs(cases) do
 local ok,parts,err=pcall(Groups.parse,text)
 AUDIT_EMIT('recipe_'..i,{text=text,call_ok=ok,accepted=parts~=nil and type(parts)=='table',
  result=type(parts)=='table' and Groups.to_recipe(parts) or tostring(err or parts)})
end
Events.set_def(set,'wave_small','snapshot',Groups.parse('1 hound'),Groups)
local saved=Presets.capture(get,Events,Groups);local encoded=Presets.encode(saved);assert(#saved.waves>0)
Events.set_def(set,'wave_small','changed',Groups.parse('1 hound{size=130}'),Groups)
assert(Presets.encode(saved)==encoded)
AUDIT_EMIT('independent_snapshot',{unchanged=true})
local holes={waves={[1]=saved.waves[1],[3]=saved.waves[2]}}
local sparse=Presets.encode(holes);local result,problem=Presets.decode(sparse,Events,Groups)
AUDIT_EMIT('sparse_private_preset',{accepted=result~=nil,error=tostring(problem),length=#holes.waves})
for i,value in ipairs({math.huge,-math.huge,0/0,9007199254740992,-9007199254740992}) do
 local waves=Presets.capture(get,Events,Groups);waves.waves[1].pct=value
 local text=Presets.encode(waves);local decoded,err=Presets.decode(text,Events,Groups)
 AUDIT_EMIT('numeric_preset_'..i,{input=tostring(value),accepted=decoded~=nil,
  pct=decoded and tostring(decoded.waves[1].pct) or '',error=tostring(err)})
 if value~=value and decoded then
  Presets.apply(decoded,set,Events,Groups)
  local chance=Events.get('wave_small',get,Groups).pct;local contains=false
  for _,entry in ipairs(Events.build_pool(get,Groups)) do if entry.key=='wave_small' then contains=true end end
  AUDIT_EMIT('nonfinite_import_effect',{chance=tostring(chance),finite=chance==chance,pool_contains=contains,text=text})
 end
end
'''
for rt in ('lua55','luajit21'):
 r=execute('logic_test.py',rt,suffix=code,prefix_only=True)
 (OUT/(rt+'_edges.json')).write_text(json.dumps(r,indent=2))
 print(rt,'error',r.get('error'),'cases',len(r.get('diagnostics',{})))
```

### Script: ui_short.py

```python
import json
from audit import OUT,execute
code=(OUT/'editor_probes.lua').read_text().split("for _,kind in ipairs({'unchanged'")[0]
code+=r'''
cycle(10,false,true)
for rep=1,5 do
 collectgarbage('collect');local before=collectgarbage('count');local t=AUDIT_NOW()
 cycle(100,false,true);local elapsed=AUDIT_NOW()-t;local active=collectgarbage('count');collectgarbage('collect')
 AUDIT_EMIT('normal_'..rep,{cycles=100,seconds=elapsed,baseline_kb=before,active_kb=active,after_kb=collectgarbage('count'),weak_views=count(weak)})
end
if jit then jit.off();jit.flush() end
cycle(10,false,true)
for rep=1,5 do
 collectgarbage('collect');local before=collectgarbage('count');local t=AUDIT_NOW()
 cycle(100,false,true);local elapsed=AUDIT_NOW()-t;local active=collectgarbage('count');collectgarbage('collect')
 AUDIT_EMIT('retention_'..rep,{cycles=100,seconds=elapsed,baseline_kb=before,active_kb=active,after_kb=collectgarbage('count'),weak_views=count(weak)})
end
'''
for rt in ('lua55','luajit21'):
 r=execute('editor_test.py',rt,suffix=code,prefix_only=True)
 (OUT/(rt+'_ui_short.json')).write_text(json.dumps(r,indent=2))
 print(rt,'error',r.get('error'),'samples',len(r.get('diagnostics',{})),flush=True)
```

### Script: previews.py

```python
import json,sys
from pathlib import Path
from PIL import Image, ImageDraw
from audit import ROOT,OUT
program=(ROOT/'tools/ui_preview.py').read_text(encoding='utf-8')
program=program.replace('int(sys.argv[i + 1])','float(sys.argv[i + 1])')
program=program.replace('(W * SCALE, H * SCALE)','(round(W * SCALE), round(H * SCALE))')
program=program.replace('result = result.resize((W, H), Image.LANCZOS)','result = result')
program=program.replace('W, H = 1920, 1080', '''
# Dump-only constant button labels were cached before UI_REAL_TEXT switches on.
for widget in data['widgets']:
    for entry in widget['passes']:
        if entry.get('text') == 'popup_ok': entry['text'] = 'OK'
        if entry.get('text') == 'popup_cancel': entry['text'] = 'Cancel'
W, H = 1920, 1080''')
program=program.replace('if wrap and total > S(h) + 1:', 'if wrap and total > S(h) + 1:\n        OVERFLOWS.append({"text":text,"x":x,"y":y,"w":w,"h":h,"lines":len(lines)})')
folder=OUT/'previews';folder.mkdir(exist_ok=True)
records={}
for width,scale in [(1920,1),(2560,4/3),(3840,2)]:
    thumbs=[]
    for source in sorted((OUT/'widgets').glob('*.json')):
        dest=folder/(source.stem+'_'+str(width)+'.png')
        sys.argv=['ui_preview.py',str(source),str(dest),'--scale',str(scale)]
        scope={'__name__':'__main__','OVERFLOWS':[]};exec(compile(program,'scratch_ui_preview.py','exec'),scope)
        records[dest.name]={'size':Image.open(dest).size,'text_overflow':scope['OVERFLOWS']}
        thumb=Image.open(dest).resize((640,360));ImageDraw.Draw(thumb).text((5,5),source.stem,fill='white');thumbs.append(thumb)
    sheet=Image.new('RGB',(1920,360*((len(thumbs)+2)//3)))
    for i,thumb in enumerate(thumbs):sheet.paste(thumb,((i%3)*640,(i//3)*360))
    sheet.save(folder/('contact_'+str(width)+'.png'))
(folder/'geometry.json').write_text(json.dumps(records,indent=2))
print('previews',len(records),'wrapped-text overflow markers',sum(len(r['text_overflow']) for r in records.values()))
```

