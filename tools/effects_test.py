"""Card effects, native API contracts, lifecycle and real editor integration."""
import ast
import os
from pathlib import Path
from lua_test_runtime import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
BASE = (ROOT / "scripts/mods/RealmsWaves").as_posix()

RUNTIME = r'''
local BASE = ...
local function check(name, value) assert(value, name); print("PASS effects: " .. name) end
local server, enabled, simple = true, true, nil
local settings, warnings, played, native_played, party, systems = {}, {}, {}, {}, {}, {}
local mod = { rw = {} }
function mod:io_dofile(path) return dofile(BASE .. "/" .. path:match("RealmsWaves/scripts/mods/RealmsWaves/(.*)") .. ".lua") end
function mod:get(id) return settings[id] end
function mod:set(id, v) settings[id] = v end
function mod:is_enabled() return enabled end
function mod:warning(fmt, ...) warnings[#warnings + 1] = string.format(fmt, ...) end
get_mod = function(name) if name == "SimpleAudio" then return simple end; return mod end
Unit = { alive = function(u) return u and u.alive ~= false end, world_position = function(u) return u.position or 0 end }
Vector3 = { distance_squared = function(a,b) return (a-b)^2 end }
HEALTH_ALIVE = {}
ScriptUnit = { has_extension = function(u,name) return u.extensions and u.extensions[name] end }
Managers = { state = { game_session = { is_server = function() return server end },
  unit_spawner = { game_object_id = function(_,u) return u.id end },
  extension = { system = function(_,name) return systems[name] end } },
  player = { players = function() return party end }, ui = { world = function() return "ui" end }, world = { wwise_world = function() return "wwise" end } }
WwiseWorld = { trigger_resource_event = function(_,event) native_played[#native_played+1] = event end }
package.preload["scripts/utilities/fixed_frame"] = function() return { get_latest_fixed_time = function() return 3 end } end
local gifts = {}
package.preload["scripts/utilities/pocketable"] = function() return {
  item_from_name = function(name) return {name=name} end,
  equip_pocketable = function(t,is_server,u,pickup,item,slot,wield)
    assert(t==3 and is_server and pickup==nil and not wield and u.inventory[slot]=="not_equipped")
    gifts[#gifts+1] = {u,item.name,slot}; u.inventory[slot] = item.name
  end } end
local Schema = dofile(BASE .. "/catalog/effects.lua")
local Groups = dofile(BASE .. "/catalog/groups.lua")
local Events = dofile(BASE .. "/catalog/events.lua")
local Presets = dofile(BASE .. "/catalog/presets.lua")
local Sounds = dofile(BASE .. "/catalog/sounds.lua")
local E = dofile(BASE .. "/core/effects.lua")
mod.rw = { groups=Groups, events=Events, effects=E }
local event = Sounds.EVENTS[100]
check("verified sound whitelist and missing values", Sounds.valid(event) and not Sounds.valid(nil) and not Sounds.valid("arbitrary/file"))
check("library has broad native choices", #Sounds.EVENTS > 2000)
local ranked = Sounds.search("", {parts=Groups.parse("2 hounds")}, Groups)
check("empty search prioritizes the card enemy", ranked[1].score>0 and ranked[1].event:find("hound",1,true))
check("literal search ignores patterns", #Sounds.search("[", {parts={}}, Groups)==0)
check("case insensitive sound search", #Sounds.search("HOUND",{parts={}},Groups)==#Sounds.search("hound",{parts={}},Groups))
local blessing = Sounds.search("",{parts={},effects={blue_stimm={value=15}}},Groups)
check("effect sounds rank first", blessing[1].score>0 and blessing[1].event:find("syringe",1,true))
local outage=Sounds.search("",{parts={},effects={blackout={value=15}}},Groups)
check("Blackout sound ranking",outage[1].score>0)
for id, term in pairs({med_crate="heal",med_station="medicae",cooldown="play_ability",reveal="precision_stance"}) do
  local found=Sounds.search("",{parts={},effects={[id]={value=1}}},Groups)
  check("sound ranking for "..id,found[1].score>0 and found[1].event:find(term,1,true))
end

for _, def in ipairs(Schema.ORDER) do
  local text=def.id .. "=999999:4"
  local value=assert(Schema.parse(text))[def.id]
  check("bounded value and stable round trip " .. def.id, value.value==def.max and Schema.encode(Schema.parse(Schema.encode({[def.id]=value})))==def.id.."="..def.max..":4")
end
for _, bad in ipairs({"heal=3:0","heal=3:4;heal=5:4","heal=-1:4","bad=1:4","heal=NaN:4","heal=5:4;",string.rep("x",513)}) do check("reject malformed effects "..bad:sub(1,30), Schema.parse(bad)==nil) end
check("empty and nil configurations", next(Schema.parse(""))==nil and next(Schema.parse(nil))==nil)
check("finite numeric settings", not Schema.number(0/0,100) and not Schema.number(math.huge,100) and Schema.number(-5,100)==0)
check("disabled zero values omitted", Schema.encode({heal={value=0,players=4}})=="")
check("suits separate beneficial and hostile effects", not Schema.allowed({heal={},blackout={}},"prayer").blackout and not Schema.allowed({heal={},blackout={}},"heresy").heal)
local function get(id) return settings[id] end
local function set(id,v) settings[id]=v end
for _, suit in ipairs({"prayer","miracle","grace"}) do
  settings.su_custom_1=suit; Events.set_def(set,"custom_1","Blessing",Groups.parse("2 hounds"),Groups); settings.fx_custom_1="heal=50:4;blackout=20:4";settings.snd_custom_1=event
  local w=Events.get("custom_1",get,Groups)
  check(suit.." masks enemies and hostile effects", #w.parts==0 and not w.monster and not w.effects.blackout and w.effects.heal.value==50)
  check(suit.." eligible without enemies", Events.has_content(w) and #Events.spawn_def(w).parts==0)
  local captured=Presets.capture_wave(get,"custom_1",Events,Groups)
  local shared=assert(Presets.decode_wave(Presets.encode_wave(captured),Events,Groups))
  Presets.apply_wave(shared,"custom_2",set,Events,Groups)
  local copy=Events.get("custom_2",get,Groups)
  check(suit.." shares and imports effects and sound", copy.suit==suit and copy.sound==event and copy.effects.heal.value==50 and #copy.parts==0)
end
settings.wave_def_custom_1=nil;settings.fx_custom_1="heal=50:4"
check("effect-only custom slot bypasses empty-slot shortcut", not Events.is_empty_slot("custom_1",get))
settings.ev_custom_1=10;settings.on_custom_1=true
local timed=Events.timed_waves(get,Groups)
check("benefits work with fixed timers", #timed>0)
Events.reset(set,"custom_1")
check("reset removes new fields", settings.fx_custom_1=="" and settings.snd_custom_1=="")

local function player(id,local_unit)
  local u={id=id,alive=true,position=id,extensions={},inventory={slot_pocketable="not_equipped",slot_pocketable_small="not_equipped"}}
  local health={heals={}}
  function health:max_health() return 200 end
  function health:add_heal(amount,kind) self.heals[#self.heals+1]={amount,kind} end
  u.extensions.health_system=health
  u.extensions.unit_data_system={read_component=function() return u.inventory end}
  u.extensions.visual_loadout_system={}
  local ability={restored=0,_is_local_unit=local_unit}
  function ability:restore_ability_resource_percentage(kind,amount,ignore) assert(self._is_local_unit,"husk mutation"); assert(kind=="combat_ability" and ignore);self.restored=self.restored+amount end
  u.extensions.ability_system=ability
  local buff={_buffs_by_index={},next=0,removed=0}
  function buff:add_externally_controlled_buff(name,t) assert(name=="syringe_speed_boost_buff" and t==3);self.next=self.next+1;self._buffs_by_index[self.next]={extra=0,add_duration=function(b,n) b.extra=b.extra+n end};return 4,self.next,7 end
  function buff:has_running_buff_with_index(index,component) assert(component==7);return self._buffs_by_index[index]~=nil end
  function buff:remove_externally_controlled_buff(index,component) assert(component==7 and self._buffs_by_index[index]);self._buffs_by_index[index]=nil;self.removed=self.removed+1 end
  u.extensions.buff_system=buff
  party[tostring(id)]={player_unit=u}; return u
end
local p1,p2,p3,p4=player(1,true),player(2,false),player(3,false),player(4,false)
p4.alive=false
local function start(values,suit,sound) return E.start({suit=suit or "prayer",parts={},effects=values,sound=sound}) end
local function effect(id,value,players) return {[id]={value=value,players=players or 4}} end
server=false
check("clients cannot apply gameplay", not start(effect("heal",100)))
check("rejected client did not heal", #p1.extensions.health_system.heals==0)
server=true
check("party healing accepted", start(effect("heal",25)))
check("heals living remote players through native API", p1.extensions.health_system.heals[1][1]==50 and #p2.extensions.health_system.heals==1 and #p4.extensions.health_system.heals==0)
check("corruption healing accepted", start(effect("cleanse",50)))
check("corruption uses native permanent-corruption healing then ordinary heal", p3.extensions.health_system.heals[2][2]=="buff_corruption_healing" and p3.extensions.health_system.heals[3][2]=="buff")
check("cooldown accepted without husk mutation", start(effect("cooldown",100)) and p1.extensions.ability_system.restored==1 and p2.extensions.ability_system.restored==0)
local snapshot=E.snapshot()
local client=dofile(BASE .. "/core/effects.lua")
server=false;client.receive(snapshot)
check("late join does not replay instantaneous grants", p1.extensions.ability_system.restored==1)
server=true;start(effect("cooldown",50));snapshot=E.snapshot()
p1.extensions.ability_system._is_local_unit=false;p2.extensions.ability_system._is_local_unit=true
server=false;client.receive(snapshot);client.receive(snapshot)
check("remote player applies host grant once", p2.extensions.ability_system.restored==0.5)
client.receive({sequence=0,grant_sequence=0,grants={}})
server=true
p1.extensions.ability_system._is_local_unit=true;p2.extensions.ability_system._is_local_unit=false
p1.inventory.slot_pocketable_small="grim"
check("stimm item accepted", start(effect("green_stimm",1)))
check("items preserve occupied slots and use stable eligible order", #gifts==1 and gifts[1][1]==p2 and p1.inventory.slot_pocketable_small=="grim")
check("yellow stim uses remaining empty slot", start(effect("yellow_stimm",4)) and #gifts==2 and gifts[2][1]==p3)
check("full inventory fails gracefully", not start(effect("green_stimm",4)))
check("medcrate independent large slot", start(effect("med_crate",2)) and #gifts==4)
local far,near={alive=true,position=100},{alive=true,position=2}
local function station(charges)
  return {charges=charges,battery_in_slot=function() return true end,charge_amount=function(s) return s.charges end,max_amount_charges=function() return 4 end,set_charge_amount=function(s,n) s.charges=n end,sync_charge_amount=function(s) s.synced=true end}
end
local fs,ns=station(0),station(3)
systems.health_station_system={_unit_to_extension_map={[far]=fs,[near]=ns}}
check("nearest station recharged", start(effect("med_station",4)) and ns.charges==4 and ns.synced and fs.charges==0)
systems.health_station_system=nil;check("missing station contained", not start(effect("med_station",1)))
check("blue stimm accepted", start(effect("blue_stimm",4,2)))
check("blue duration adjusts native 15-second template", p1.extensions.buff_system._buffs_by_index[1].extra==-11 and p2.extensions.buff_system._buffs_by_index[1].extra==-11 and p3.extensions.buff_system.next==0)
p2.alive=false;E.update(1,true)
check("despawned buff target is pruned safely", p2.extensions.buff_system.removed==0)
p1.extensions.buff_system._buffs_by_index[1]=nil;E.update(4,true)
check("native expiry is never removed twice", p1.extensions.buff_system.removed==0)
p2.alive=true;start(effect("blue_stimm",30,1));E.cancel()
check("stop removes only owned active native buffs", p1.extensions.buff_system.removed==1)
local l1,l2={alive=true},{alive=true}
local function light(on) return {on=on,is_enabled=function(s) return s.on end,set_enabled=function(s,on,hotjoin) assert(hotjoin==false);s.on=on end} end
local a,b=light(true),light(false)
systems.light_controller_system={_unit_to_extension_map={[l1]=a,[l2]=b}}
check("blackout uses level controller", start(effect("blackout",2),"heresy") and not a.on and not b.on)
E.update(1);start(effect("blackout",3),"heresy")
local l3,c={alive=true},light(true);systems.light_controller_system._unit_to_extension_map[l3]=c
E.update(1);check("streamed lights join overlapping outage", not a.on and not c.on)
E.update(2.25,true);check("outage expires during scheduler pause and restores initial states", a.on and not b.on and c.on)
start(effect("blackout",30),"heresy");E.cancel();check("stop restores lighting", a.on and not b.on)
systems.light_controller_system=nil;check("missing light controller fails gracefully", not start(effect("blackout",1),"plague"))
local specialist={id=50,alive=true,extensions={unit_data_system={breed=function() return {tags={special=true}} end}}}
local grunt={id=51,alive=true,extensions={unit_data_system={breed=function() return {tags={special=false}} end}}}
local original={smart_tag={priority=10}}
local se,ge={settings=original},{settings=original}
local outline={_unit_extension_data={[specialist]=se,[grunt]=ge},adds=0,removes=0}
function outline:add_outline(u,key) assert(key=="rw_guidance");self.adds=self.adds+1 end
function outline:remove_outline(u,key) assert(key=="rw_guidance");self.removes=self.removes+1 end
systems.outline_system=outline
check("guidance accepted",start(effect("reveal",2)))
E.update(0.25);E.update(0.25)
check("specialists only and no duplicate stacks", outline.adds==1 and se.settings~=original and ge.settings==original and se.settings.rw_guidance.material_layers[2]=="minion_outline_reversed_depth")
se.settings.other_mod={};E.cancel()
check("guidance cleanup preserves tags and other mods", se.settings.smart_tag==original.smart_tag and se.settings.other_mod and not se.settings.rw_guidance and outline.removes==1)
se.settings=original;start(effect("reveal",1));E.update(0.25);E.update(1)
check("unchanged settings map restored after duration", se.settings==original)
start(effect("reveal",1));E.update(0.25);specialist.alive=false;E.update(0.25);E.cancel()
check("dead specialist cleanup avoids native removal", not se.settings.rw_guidance)
E.reset();specialist.alive=true;client.reset()
start(effect("reveal",1));snapshot=E.snapshot();server=false;client.receive(snapshot);client.update(2);client.receive(snapshot)
check("duplicate active-guidance snapshot does not extend or revive duration",client.snapshot().reveal==0)
server=true;E.cancel();local stopped_snapshot=E.snapshot();server=false;client.receive(stopped_snapshot);client.receive(snapshot)
check("older guidance revision cannot undo stop",client.snapshot().reveal==0)
server=true
E.reset();simple={play=function(sound) played[#played+1]=sound end}
local ok,ticket=start(effect("heal",100),nil,event)
check("sounding card tracks completion", ok and ticket)
local enemy={alive=true};E.add_unit(ticket,enemy);E.update(0.25)
check("no sound before scheduling finishes", #played==0)
E.finish(ticket);E.update(0.25);check("living enemies delay completion", #played==0)
enemy.alive=false;E.update(0.25);E.update(0.25)
check("fulfilled wave sounds exactly once", #played==1 and E.snapshot().sequence==1)
ok,ticket=start(effect("reveal",2),nil,event);E.finish(ticket);E.update(1)
check("timed benefit waits for effect expiry", #played==1)
E.update(1.1);check("timed completion sounds at expiry", #played==2)
ok,ticket=start(effect("heal",100),nil,event);E.finish(ticket,true);E.update(0.25)
check("failed spawn ticket suppresses sound", #played==2)
ok,ticket=start(effect("heal",100),nil,event);E.cancel();E.update(1)
check("cancelled cards stay silent", #played==2)
for i=1,64 do check("sounding card budget admission "..i,start(effect("heal",1),nil,event)) end
check("bounded completion tracking rejects 65th card", not start(effect("heal",1),nil,event))
check("silent cards do not consume audio budget", start(effect("heal",1)))
E.reset();for i=1,10 do ok,ticket=start(effect("heal",1),nil,event);E.finish(ticket);E.update(0.25) end
check("audio history bounded", #E.snapshot().audio==8)
client.reset();server=false;local before=#played;client.receive(E.snapshot())
check("late join audio baseline silent", #played==before)
server=true;ok,ticket=start(effect("heal",1),nil,event);E.finish(ticket);E.update(0.25);snapshot=E.snapshot();before=#played
server=false;client.receive(snapshot);client.receive(snapshot)
check("duplicate snapshots never repeat sound", #played==before+1)
client.receive({sequence=0,reveal=300});client.update(0.25)
check("stale snapshot cannot revive guidance", client.snapshot().reveal==0)
client.receive({sequence=0/0});client.receive(false);client.receive({sequence=999,audio={{999,"arbitrary/file"}}})
check("malformed/unverified client sound ignored", #played==before+1)
server=true;settings.card_sounds=false;E.preview_sound(event);check("audio option mutes preview",#played==before+1)
settings.card_sounds=nil;simple=nil;E.preview_sound(event);check("native fallback needs no SimpleAudio",native_played[#native_played]==event)
simple={play=function() error("missing bank") end};E.preview_sound(event);check("optional audio failure contained",#warnings>0)
simple={is_enabled=function() return false end,play=function() error("disabled") end};before=#native_played;E.preview_sound(event);check("disabled SimpleAudio uses native backend",#native_played==before+1)
local X=dofile(BASE .. "/spawn/execute.lua")
Managers.state.minion_spawn={}
X.init({positions={},bypass={count=function()return 0 end,purge=function()end,reset=function()end},groups=Groups,effects=E})
E.reset();simple={play=function(sound)played[#played+1]=sound end};before=#played
local hostile_recipe=Groups.parse("3 hounds")
check("executor: malicious enemy recipe on beneficial face is masked",X.start_wave({suit="prayer",parts=hostile_recipe,effects=effect("heal",10),sound=event}) and X.status().queued==0)
X.update(0.25);X.update(0.25)
check("executor: real empty-queue completion reaches audio",#played==before+1 and X.status().jobs==0)
X.start_wave({suit="prayer",parts={},effects=effect("reveal",30),sound=event});X.cancel();X.update(1)
check("executor: stop cancels pending timed audio",#played==before+1)
enabled=false;check("executor: disabled admission rejected",not X.start_wave({suit="prayer",parts={},effects=effect("heal",10)}));enabled=true
X.reset();mod.rw.dead=true;check("executor: captured retired executor inert",not X.start_wave({parts=hostile_recipe}));mod.rw.dead=nil
local old_heal=p2.extensions.health_system.add_heal;p2.extensions.health_system.add_heal=function()error("disconnected player")end
before=#p3.extensions.health_system.heals;check("one player failure does not abort remaining party",start(effect("heal",10)) and #p3.extensions.health_system.heals==before+1)
p2.extensions.health_system.add_heal=old_heal
Managers.ui=nil;simple=nil;E.preview_sound(event);E.reset();check("reset clears audio and grant sessions",E.snapshot().sequence==0 and E.snapshot().grant_sequence==0)
'''

EDITOR = r'''
do
  local EF=mod.rw.groups.Effects
  local PP=mod:io_dofile("RealmsWaves/scripts/mods/RealmsWaves/ui/wave_editor_components").Popup
  local SO=mod:io_dofile("RealmsWaves/scripts/mods/RealmsWaves/catalog/sounds")
  mod.rw.events.set_def(function(id,v) settings[id]=v end,"custom_20","Blessing",mod.rw.groups.parse("2 hounds"),mod.rw.groups)
  settings.su_custom_20="prayer";settings.fx_custom_20="heal=100:4";settings.th_custom_20=6
  view:_open_detail("custom_20")
  local W=view._widgets_by_name
  check("effects UI: enemies and spawn controls replaced",W.rw_effect_1.visible and not W.rw_erow_1.visible and not W.shelf_panel.visible and not W.btn_add.visible and W.btn_enemies.content.hotspot_text=="Beneficial Effects")
  view:cb_add();check("effects UI: direct enemy callback cannot open picker",view._screen=="detail" and not view._popup)
  view:cb_effect_toggle(2);check("effects UI: checkbox persists effect",view._wave.effects.cleanse.value==100)
  view:cb_effect_amount(1);PP.set_text(view,"50");PP.commit(view);check("effects UI: amount popup saves value",view._wave.effects.heal.value==50)
  view:cb_effect_toggle(9);view:cb_effect_players(9);PP.set_text(view,"2");PP.commit(view);check("effects UI: blue targets configurable",view._wave.effects.blue_stimm.players==2)
  view:cb_effect_toggle(1);check("effects UI: toggling removes effect",not view._wave.effects.heal)
  check("effects UI: DESPAIR sixth diamond visible",W.rw_stage_card.style.th_o6.visible and W.rw_stage_card.style.th_h6.color[2]==0xc7)
  view:cb_sound_picker();check("effects UI: ranked searchable list opens at start",view._screen=="sounds" and view._offset==0 and view._popup and view._sound_results[1].event=="")
  PP.set_text(view,"hound");PP.update(view,{get=function() return nil end,is_null_service=function()return false end})
  check("effects UI: sound search returns related choices",view._sound_results[2].event:find("hound",1,true))
  view:cb_sound_select(2);check("effects UI: selection saves and returns to Mirror",view._screen=="face" and SO.valid(settings.snd_custom_20) and not view._popup)
  view:cb_sound_picker();view:cb_sound_select(1);check("effects UI: silence clears selection",settings.snd_custom_20=="")
  settings.card_share_icons=false;view:_apply_screen(true);check("effects UI: share icon option hides hotspot",not hotspot_runs(W.rw_stage_card,"hotspot_share"))
  settings.card_share_icons=true;view:_apply_screen(true);W.rw_stage_card.content.hotspot_share.pressed_callback();check("effects UI: stage icon opens Share Card",view._popup~=nil)
  PP.cancel(view)
  settings.su_custom_20="heresy";view:_open_detail("custom_20");view:cb_blackout();PP.set_text(view,"25");PP.commit(view)
  check("effects UI: hostile Blackout saves configurable duration",view._wave.effects.blackout.value==25 and not W.rw_effect_1.visible and W.shelf_panel.visible)
  for i=1,#view._definitions.shelf_layout.chips do
    local chip=W["rw_chip_"..i]
    for _,state in ipairs({"rest","hover","pressed","disabled"}) do
      chip.content.hotspot.is_hover=state=="hover";chip.content.hotspot.is_pressed=state=="pressed";chip.content.hotspot.disabled=state=="disabled"
      for _,p in ipairs(chip.def.passes) do if p.change_function then p.change_function(chip.content,chip.style[p.style_id]) end end
    end
    chip.content.hotspot.is_hover=false;chip.content.hotspot.is_pressed=false;chip.content.hotspot.disabled=false
  end
  check("effects UI: shelf cells retain uniform width",W.rw_chip_1.style.hotspot.size[1]==156 and W.rw_chip_2.style.hotspot.size[1]==156)
  check("effects UI: foreground right edge completes shelf",W.rw_chip_1.style.chip_edge_r.size[1]==2 and W.rw_chip_1.style.chip_edge_r.offset[1]+2==156)

  local before=settings.wave_def_wave_small
  view:cb_back();view:cb_bless_deck();PP.set_text(view,"wrong");PP.commit(view)
  check("effects UI: conversion requires explicit typed confirmation",view._popup~=nil and settings.wave_def_wave_small==before)
  PP.set_text(view,"CONSECRATE");PP.commit(view)
  local all=true
  for _,std in ipairs(mod.rw.events.STANDARD) do local w=mod.rw.events.get(std.key,function(id)return settings[id] end,mod.rw.groups);if not EF.beneficial(w.suit) or #w.parts~=0 or not EF.has_content(w) then all=false end end
  check("effects UI: twelve standard slots converted and Undo saved",all and type(settings[mod.rw.presets.UNDO_ID])=="string")
  view:_open_detail("custom_20")
  local stage=W.stage_plate
  local palette=true
  for _,p in ipairs(stage.def.passes) do
    if p.change_function then p.change_function(stage.content,stage.style[p.style_id]) end
    local col=stage.style[p.style_id].color
    if p.style_id:find("^ring_") and col and col[2]>math.max(stage.content.stage.frame[1],stage.content.stage.accent[1],30)+1 then palette=false end
  end
  check("effects UI: rings stay within suit palette",palette)
  local sounds=view._definitions.scenegraph_definition.rw_sound.position
  local chance=view._definitions.scenegraph_definition.stepper_chance.position
  check("effects UI: completion buttons clear chance row",sounds[2]>=chance[2]+W.stepper_chance.style.hotspot_minus.size[2])
  view:on_exit()
end
'''


def original_harness(name):
    tree = ast.parse((ROOT / "tools" / name).read_text(encoding="utf-8"))
    return next(ast.literal_eval(n.value) for n in tree.body if isinstance(n, ast.Assign)
                and any(isinstance(t, ast.Name) and t.id == "harness" for t in n.targets))


if __name__ == "__main__":
    runtime = LuaRuntime(unpack_returned_tuples=True)
    runtime.execute(RUNTIME, BASE)
    runtime.execute("io.flush()")  # LuaJIT/Python use separate stdout buffers; keep each assertion on its own line.
    harness = original_harness("editor_test.py").replace('return table.concat(results, "\\n")', EDITOR + '\nreturn table.concat(results, "\\n")')
    output = LuaRuntime(unpack_returned_tuples=True).execute(harness, ROOT.as_posix(), "", "", "")
    for line in output.splitlines():
        if line.startswith(("PASS effects UI:", "FAIL")):
            print(line)
    assert not any(line.startswith("FAIL") for line in output.splitlines()), "Effects editor regression"
