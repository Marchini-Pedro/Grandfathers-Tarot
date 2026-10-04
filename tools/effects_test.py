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
check("Med Station recharge is disabled for now: saved charges never run", not start(effect("med_station",4)) and ns.charges==3 and not ns.synced and fs.charges==0)
check("disabled effects stay parsed and encoded but are not allowed", Schema.parse("med_station=2:4").med_station.value==2 and not Schema.allowed({med_station={value=2,players=4}},"miracle").med_station)
systems.health_station_system=nil
check("four beneficial suits including Faith; categories are Healing, Buffs, Items and Game Effects", Schema.beneficial("faith") and Schema.CATEGORIES[2].id=="Buffs" and Schema.CATEGORIES[3].id=="Items" and Schema.CATEGORIES[4].id=="Game Effects" and Schema.definition("cooldown").category=="Buffs" and Schema.definition("blue_stimm").category=="Items" and Schema.definition("revive").category=="Game Effects")
check("summary strips the category, even one of two words", Schema.summary({revive={value=2,players=4}})=="raise the fallen (2 players)" and Schema.summary({ammo={value=50,players=4}})=="refill ammunition (50 percent)")
-- Raise the fallen: only knocked-down players, through the native assisted-state input, at most N, never twice
local states={}
for _,p in ipairs({p1,p2,p3}) do
  local data=p.extensions.unit_data_system
  p.state={state_name="walking"}; p.assist={force_assist=false,in_progress=false}
  data.read_component=function(_,name) if name=="character_state" then return p.state end return p.inventory end
  data.write_component=function(_,name) assert(name=="assisted_state_input");return p.assist end
end
package.preload["scripts/utilities/attack/player_unit_status"]=function() return {
  is_knocked_down=function(c) return c.state_name=="knocked_down" end, is_assisted=function(a) return a.in_progress end } end
check("nobody down: raise the fallen fails without touching anyone", not start(effect("revive",4)) and not p1.assist.force_assist)
p1.state.state_name="knocked_down";p2.state.state_name="knocked_down";p3.state.state_name="netted"
check("raise the fallen lifts at most the configured number of knocked-down players", start(effect("revive",1)) and p1.assist.force_assist and not p2.assist.force_assist and not p3.assist.force_assist)
p1.assist.force_assist=false;p1.assist.in_progress=true
check("a player already being helped is skipped", start(effect("revive",4)) and not p1.assist.force_assist and p2.assist.force_assist and not p3.assist.force_assist)
p1.assist.in_progress=false;p1.state.state_name="walking";p2.state.state_name="walking";p3.state.state_name="walking"
-- Refill ammunition: the native helper with a fraction, a full party reports nothing gained, one failing player is contained
local ammo_calls={}
package.preload["scripts/utilities/ammo"]=function() return { add_to_all_slots=function(u,f) ammo_calls[#ammo_calls+1]={u,f}; if u.ammo_error then error("no weapon system") end return u.ammo_gain or 0 end } end
p1.ammo_gain=5;p3.ammo_error=true
check("refill ammunition uses the native helper with a fraction of the reserve", start(effect("ammo",40)) and ammo_calls[1][2]==0.4 and #ammo_calls==3)
check("one player's ammunition failure is contained and warned", #warnings>0)
p1.ammo_gain=0;p3.ammo_error=nil
check("a party with full ammunition reports the effect as not applied", not start(effect("ammo",100)))
for _,p in ipairs({p1,p2,p3}) do p.extensions.unit_data_system.read_component=function() return p.inventory end end
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
-- two sounds and their volumes (2026-10-04)
local ev1,ev2=Sounds.EVENTS[100],Sounds.EVENTS[200]
check("sound text: the old form is one event at full volume", #Sounds.parse(ev1)==1 and Sounds.parse(ev1)[1].volume==100 and Sounds.encode(Sounds.parse(ev1))==ev1)
check("sound text: two events with volumes round trip, the second kept in order", Sounds.encode(Sounds.parse(ev1.."@40;"..ev2.."@0"))==ev1.."@40;"..ev2.."@0" and Sounds.parse(ev1.."@40;"..ev2)[2].event==ev2)
check("sound text: unknown events are dropped, a third sound is ignored, volumes are clamped", #Sounds.parse("nope@5;"..ev1)==1 and #Sounds.parse(ev1..";"..ev2..";"..ev1)==2 and Sounds.parse(ev1.."@999")[1].volume==100)
check("sound text: a shared card must carry only known events, at most two, volumes up to 100", Sounds.check("") and Sounds.check(ev1.."@50;"..ev2) and not Sounds.check(ev1..";"..ev2..";"..ev1) and not Sounds.check("arbitrary/file") and not Sounds.check(ev1.."@101") and not Sounds.check(string.rep("x",401)))
settings.su_custom_3="miracle";Events.set_def(set,"custom_3","Hymn",{},Groups);settings.fx_custom_3="heal=10:4";settings.snd_custom_3=ev1.."@60;"..ev2
local hymn=Events.get("custom_3",get,Groups)
check("a card reads its two sounds", hymn.sound==ev1.."@60;"..ev2)
local hshared=assert(Presets.decode_wave(Presets.encode_wave(Presets.capture_wave(get,"custom_3",Events,Groups)),Events,Groups))
Presets.apply_wave(hshared,"custom_4",set,Events,Groups)
check("two sounds and their volumes survive Share Card", Events.get("custom_4",get,Groups).sound==ev1.."@60;"..ev2)
-- playback: the first now, the second when the first stops playing (native ids), never longer than twelve seconds
Managers.ui={world=function() return "ui" end}
local playing,ids,sources,params={},0,{},{}
WwiseWorld.trigger_resource_event=function(_,ev,source) ids=ids+1;playing[ids]=true;native_played[#native_played+1]=ev;return ids end
WwiseWorld.is_playing=function(_,id) return playing[id]==true end
WwiseWorld.make_manual_source=function() sources[#sources+1]="s"..#sources;return sources[#sources] end
WwiseWorld.set_source_parameter=function(_,s,name,v) params[#params+1]={s,name,v} end
WwiseWorld.destroy_manual_source=function(_,s) sources.destroyed=(sources.destroyed or 0)+1 end
Vector3.zero=function() return 0 end;Quaternion={identity=function() return 1 end};Application={user_setting=function() return 80 end}
simple=nil;local n0=#native_played
E.preview_sound(ev1..";"..ev2)
check("the first sound plays at once, the second waits", #native_played==n0+1 and native_played[#native_played]==ev1 and E.chain_size()==1)
E.tick_audio(1);check("while the first still plays the second waits", #native_played==n0+1)
playing[ids]=false;E.tick_audio(0.1)
check("the second starts when the first has ended", #native_played==n0+2 and native_played[#native_played]==ev2 and E.chain_size()==0)
E.preview_sound(ev1.."@50")
check("a quieter sound plays through its own source with the sfx volume scaled", #sources>=1 and params[#params][2]=="options_sfx_slider" and params[#params][3]==40)
playing[ids]=false;E.tick_audio(0.1);check("its source is destroyed when it ends", sources.destroyed==1)
n0=#native_played;E.preview_sound(ev1.."@0;"..ev2)
check("a muted sound is skipped and the next one plays", #native_played==n0+1 and native_played[#native_played]==ev2)
n0=#native_played;E.preview_sound(ev1..";"..ev2);E.tick_audio(12.5)
check("a sound that never reports its end lets the next one start after twelve seconds", #native_played==n0+2)
simple={play=function(sound) played[#played+1]=sound end};local p0=#played
E.preview_sound(ev1..";"..ev2);check("SimpleAudio: the second sound follows after a short gap", #played==p0+1)
E.tick_audio(2.6);check("SimpleAudio: ...and plays", #played==p0+2 and played[#played]==ev2)
for i=1,12 do E.preview_sound(ev1..";"..ev2) end;check("the chain is bounded", E.chain_size()<=8)
E.reset();check("reset empties the chain", E.chain_size()==0)
local ok2,t2=start(effect("heal",5),nil,ev1.."@30;"..ev2);E.finish(t2);E.update(0.25)
check("a card's two sounds travel in the audio journal as one text", ok2 and E.snapshot().audio[#E.snapshot().audio][2]==ev1.."@30;"..ev2)
simple=nil
'''

EDITOR = r'''
do
  local EF=mod.rw.groups.Effects
  local PP=mod:io_dofile("RealmsWaves/scripts/mods/RealmsWaves/ui/wave_editor_components").Popup
  local SO=mod:io_dofile("RealmsWaves/scripts/mods/RealmsWaves/catalog/sounds")
  local EV=mod:io_dofile("RealmsWaves/scripts/mods/RealmsWaves/ui/wave_editor_effects")
  local WK=mod:io_dofile("RealmsWaves/scripts/mods/RealmsWaves/ui/workshop")
  local function chip(id) for i,c in ipairs(EV.shelf_layout.chips) do if c.def.id==id then return i,view._widgets_by_name["rw_fxchip_"..i] end end end
  mod.rw.events.set_def(function(id,v) settings[id]=v end,"custom_20","Blessing",mod.rw.groups.parse("2 hounds"),mod.rw.groups)
  settings.su_custom_20="prayer";settings.fx_custom_20="heal=100:4";settings.th_custom_20=6
  view:_open_detail("custom_20")
  local W=view._widgets_by_name
  check("effects UI: the enemy rows, shelf and spawn controls give way to the effect rows and the effect shelf",W.rw_fxrow_1.visible and not W.rw_fxrow_2.visible and W.fx_shelf.visible and W.fx_header.visible and not W.rw_erow_1.visible and not W.shelf_panel.visible and not W.btn_add.visible and W.btn_enemies.content.hotspot_text=="Beneficial Effects")
  check("effects UI: a row names the effect, its group under it and on its edge, the amount in words; no players for a heal",W.rw_fxrow_1.content.label=="Party health" and W.rw_fxrow_1.content.info=="Healing" and W.rw_fxrow_1.content.edge_rgb[1]==98 and W.rw_fxrow_1.content.amount_value=="100 percent" and not W.rw_fxrow_1.content.show_players and W.rw_fxrow_1.content.no_players=="-")
  check("effects UI: the shelf has four groups: Healing, Buffs, Items and Game Effects",W.fx_shelf.content.band_1=="HEALING" and W.fx_shelf.content.band_2=="BUFFS" and W.fx_shelf.content.band_3=="ITEMS" and W.fx_shelf.content.band_4=="GAME EFFECTS")
  local mi,med=chip("med_station")
  check("effects UI: Recharge Med Station is greyed and says it is off for now",med.visible and med.content.hotspot.disabled==true and med.content.chip_label:find("fx_off_for_now",1,true)~=nil)
  view:cb_fx_chip(mi);check("effects UI: a click on the disabled chip changes nothing",not view._wave.effects.med_station)
  view:cb_add();check("effects UI: direct enemy callback cannot open picker",view._screen=="detail" and not view._popup)
  local ci,cleanse=chip("cleanse")
  check("effects UI: a chip is lit when the card holds its effect",select(2,chip("heal")).content.hotspot_on==true and cleanse.content.hotspot_on==false)
  view:cb_fx_chip(ci);check("effects UI: a chip adds its effect at its default, as a new row in catalog order",view._wave.effects.cleanse.value==100 and W.rw_fxrow_2.visible and W.rw_fxrow_2.content.label=="Health and corruption" and select(2,chip("cleanse")).content.hotspot_on)
  view:cb_fx_chip(ci);check("effects UI: a second click takes it off",not view._wave.effects.cleanse and not W.rw_fxrow_2.visible)
  view:cb_fx_step(1,"value",-1);check("effects UI: the amount stepper takes 5 percent off",view._wave.effects.heal.value==95 and W.rw_fxrow_1.content.amount_value=="95 percent")
  view:cb_fx_step(1,"value",1);view:cb_fx_step(1,"value",1);check("effects UI: ...and never goes past the maximum",view._wave.effects.heal.value==100)
  for _=1,30 do view:cb_fx_step(1,"value",-1) end;check("effects UI: ...nor below one step (Remove takes an effect off)",view._wave.effects.heal.value==5)
  view:cb_fx_number(1,"value");PP.set_text(view,"50");PP.commit(view);check("effects UI: a click on the amount opens the box and saves",view._wave.effects.heal.value==50)
  view:cb_fx_number(1,"players");check("effects UI: a heal has no players box",view._popup==nil)
  local bi=chip("blue_stimm");view:cb_fx_chip(bi)
  local brow=nil;for i=1,6 do if W["rw_fxrow_"..i].visible and W["rw_fxrow_"..i].content.label=="Blue Stimm buff" then brow=i end end
  check("effects UI: Blue Stimm has its players stepper (4 players) beside its seconds",brow~=nil and W["rw_fxrow_"..brow].content.show_players and W["rw_fxrow_"..brow].content.players_value=="4 players" and W["rw_fxrow_"..brow].content.amount_value=="15 seconds")
  view:cb_fx_step(brow,"players",-1);check("effects UI: one player fewer",view._wave.effects.blue_stimm.players==3)
  view:cb_fx_number(brow,"players");PP.set_text(view,"2");PP.commit(view);check("effects UI: blue targets configurable in the box",view._wave.effects.blue_stimm.players==2)
  local ri=chip("revive");view:cb_fx_chip(ri)
  check("effects UI: Raise the fallen (Game Effects) arrives as 4 players",view._wave.effects.revive.value==4 and (function() for i=1,6 do if W["rw_fxrow_"..i].content.label=="Raise the fallen" and W["rw_fxrow_"..i].visible then return W["rw_fxrow_"..i].content.amount_value=="4 players" end end end)())
  view:cb_fx_remove(1);check("effects UI: Remove on a row takes its effect off",not view._wave.effects.heal and view._wave.effects.blue_stimm)
  check("effects UI: APOTHEOSIS: a beneficial card's sixth diamond is visible and not edged in Despair's lilac",W.rw_stage_card.style.th_o6.visible and W.rw_stage_card.style.th_h6.color[2]~=0xc7)
  check("effects UI: the beneficial shelf ends above the timer and the action bar",WK.SHELF_Y+EV.shelf_layout.height<=view._definitions.scenegraph_definition.stepper_timer.position[2] and #EV.shelf_layout.chips==11)
  -- the completion sound
  view:cb_sound_picker();check("effects UI: ranked searchable list opens at start, slot 1 open",view._screen=="sounds" and view._offset==0 and view._popup and view._sound_results[1].event=="" and W.rw_snd_slot1.visible and W.rw_snd_slot1.content.hotspot_on and W.rw_snd_search.visible)
  PP.set_text(view,"hound");PP.update(view,{get=function() return nil end,is_null_service=function()return false end})
  check("effects UI: sound search returns related choices",view._sound_results[2].event:find("hound",1,true))
  local first=view._sound_results[2].event
  view:cb_sound_select(2);check("effects UI: Select fills slot 1, saves and stays on the sound screen",view._screen=="sounds" and settings.snd_custom_20==first and not view._popup and W.rw_snd_vol1.visible and not W.rw_snd_vol2.visible)
  check("effects UI: every row but Silence has Preview",view._widgets_by_name.rw_row_2.content.hotspot_mods_text=="snd_preview" and view._widgets_by_name.rw_row_2.content.show_mods==true and view._widgets_by_name.rw_row_1.content.show_mods==false)
  view:cb_row_mods(2);check("effects UI: Preview saves nothing",settings.snd_custom_20==first)
  view:cb_sound_slot(2);check("effects UI: the second slot opens once there is a first",W.rw_snd_slot2.content.hotspot_on)
  view:cb_sound_search();PP.set_text(view,"syringe");PP.update(view,{get=function() return nil end,is_null_service=function()return false end})
  local second=view._sound_results[2].event
  view:cb_sound_select(2);check("effects UI: Select fills slot 2: the card plays two sounds in a row",settings.snd_custom_20==first..";"..second and W.rw_snd_vol2.visible and W.rw_snd_remove2.visible)
  view:cb_sound_volume(2);PP.set_text(view,"40");PP.commit(view)
  check("effects UI: the second sound's volume is saved",settings.snd_custom_20==first..";"..second.."@40" and W.rw_snd_vol2.content.number_text=="40%" and math.abs(W.rw_snd_vol2.style.fill.size[1]-WK.SOUND.track_w*0.4)<1e-6)
  view:cb_sound_remove2();check("effects UI: Remove 2 leaves the first sound",settings.snd_custom_20==first and not W.rw_snd_vol2.visible)
  view:cb_back();check("effects UI: Back returns to the Mirror and hides the sound controls",view._screen=="face" and not W.rw_snd_slot1.visible and not W.rw_snd_vol1.visible)
  check("effects UI: the button under the card says one sound is set",W.rw_sound.content.hotspot_text=="snd_button_one")
  view:cb_sound_picker();view:cb_sound_select(1);check("effects UI: silence clears selection",settings.snd_custom_20=="")
  view:cb_back()
  settings.card_share_icons=false;view:_apply_screen(true);check("effects UI: share icon option hides hotspot",not hotspot_runs(W.rw_stage_card,"hotspot_share"))
  settings.card_share_icons=true;view:_apply_screen(true);W.rw_stage_card.content.hotspot_share.pressed_callback();check("effects UI: stage icon opens Share Card",view._popup~=nil)
  PP.cancel(view)
  settings.su_custom_20="heresy";view:_open_detail("custom_20");view:cb_blackout();PP.set_text(view,"25");PP.commit(view)
  check("effects UI: hostile Blackout saves configurable duration",view._wave.effects.blackout.value==25 and not W.rw_fxrow_1.visible and not W.fx_shelf.visible and W.shelf_panel.visible)
  for i=1,#view._definitions.shelf_layout.chips do
    local c=W["rw_chip_"..i]
    for _,state in ipairs({"rest","hover","pressed","disabled"}) do
      c.content.hotspot.is_hover=state=="hover";c.content.hotspot.is_pressed=state=="pressed";c.content.hotspot.disabled=state=="disabled"
      for _,p in ipairs(c.def.passes) do if p.change_function then p.change_function(c.content,c.style[p.style_id]) end end
    end
    c.content.hotspot.is_hover=false;c.content.hotspot.is_pressed=false;c.content.hotspot.disabled=false
  end
  check("effects UI: shelf cells retain uniform width",W.rw_chip_1.style.hotspot.size[1]==156 and W.rw_chip_2.style.hotspot.size[1]==156)
  check("effects UI: foreground right edge completes shelf",W.rw_chip_1.style.chip_edge_r.size[1]==2 and W.rw_chip_1.style.chip_edge_r.offset[1]+2==156)

  local before=settings.wave_def_wave_small
  view:cb_back();view:cb_bless_deck();PP.set_text(view,"wrong");PP.commit(view)
  check("effects UI: conversion requires explicit typed confirmation",view._popup~=nil and settings.wave_def_wave_small==before)
  PP.set_text(view,"CONSECRATE");PP.commit(view)
  local all,faith=true,0
  for _,std in ipairs(mod.rw.events.STANDARD) do local w=mod.rw.events.get(std.key,function(id)return settings[id] end,mod.rw.groups);if not EF.beneficial(w.suit) or #w.parts~=0 or not EF.has_content(w) then all=false end;if w.suit=="faith" then faith=faith+1 end end
  check("effects UI: twelve standard slots converted (three of each of the four faces, Faith included) and Undo saved",all and faith==3 and type(settings[mod.rw.presets.UNDO_ID])=="string")
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
  -- the switch between hostile and beneficial suits
  settings.su_custom_20="heresy";view:_open_detail("custom_20")
  check("effects UI: on a hostile card the quick face shows the twelve hostile suits, the switch on Enemies",W.rw_suit_12.visible and not W.rw_suit_13.visible and W.btn_kind_hostile.content.hotspot_on)
  view:cb_suit_view("ben")
  check("effects UI: Beneficial shows the four beneficial suits in the first places, hides the hostile ones, the card unchanged",not W.rw_suit_1.visible and W.rw_suit_13.visible and W.rw_suit_16.visible and view._sg.rw_suit_13[1]==WK.suit_pos(1) and settings.su_custom_20=="heresy" and W.btn_kind_ben.content.hotspot_on)
  W.rw_suit_16.content.hotspot.pressed_callback()
  check("effects UI: picking Faith makes the card a blessing: the effect rows appear, the switch follows",settings.su_custom_20=="faith" and W.fx_shelf.visible and W.btn_kind_ben.content.hotspot_on and W.rw_stage_card.content.suit_label=="FAITH")
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
