"""Card effects, native API contracts, lifecycle and real editor integration."""
import ast
import os
from pathlib import Path
from lua_test_runtime import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
BASE = (ROOT / "scripts/mods/GrandfathersTarot").as_posix()

RUNTIME = r'''
local BASE = ...
local function check(name, value) assert(value, name); print("PASS effects: " .. name) end
local server, enabled, simple, local_player = true, true, nil, nil
local settings, warnings, played, native_played, party, systems = {}, {}, {}, {}, {}, {}
local mod = { rw = {} }
function mod:io_dofile(path) return dofile(BASE .. "/" .. path:match("GrandfathersTarot/scripts/mods/GrandfathersTarot/(.*)") .. ".lua") end
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
  player = { players = function() return party end, local_player_safe = function() return local_player end }, ui = { world = function() return "ui" end },
  world = { wwise_world = function(_, world) return "wwise:" .. tostring(world) end, has_world = function(_, name) return name == "level_world" end, world = function(_, name) return name end } }
-- every sound the native player starts is heard: `played` (and `native_played`, with where it played in `heard_in`)
local heard_in = {}
local function hear(wwise, event, source) played[#played+1] = event; native_played[#native_played+1] = event; heard_in[#heard_in+1] = { wwise, source } end
WwiseWorld = { trigger_resource_event = function(wwise, event, source) hear(wwise, event, source) end,
  trigger_resource_external_event = function(wwise, route, es, file, format, source) hear(wwise, file, source); heard_in[#heard_in].route, heard_in[#heard_in].es, heard_in[#heard_in].format = route, es, format end,
  make_auto_source = function(_, unit) return "auto:" .. tostring(unit and unit.name) end,
  make_manual_source = function() return "manual" end }
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
-- (a term can match voice lines too: "smart_tag" talk ranks with the precision stance for Reveal)
for id, terms in pairs({med_crate={"heal"},med_station={"healthstation"},reveal_elites={"precision_stance","smart_tag"},reveal={"precision_stance","smart_tag"}}) do
  local found=Sounds.search("",{parts={},effects={[id]={value=1}}},Groups)
  local hit=false
  for _, term in ipairs(terms) do if found[1].event:find(term,1,true) then hit=true end end
  check("sound ranking for "..id,found[1].score>0 and hit)
end
-- the list (2026-10-04): no weapon sounds and no silent VO routes; the voice lines of enemies and players are in it
local weapon, routes, enemy_lines, player_lines = 0, 0, 0, 0
for _, event in ipairs(Sounds.EVENTS) do
  if event:find("^wwise/events/weapon/") then weapon = weapon + 1 end
  if event:find("^wwise/events/vo/play_sfx_es_") then routes = routes + 1 end
  if event:find("^loc_enemy_") then enemy_lines = enemy_lines + 1 end
  if event:find("^loc_veteran_") or event:find("^loc_zealot_") or event:find("^loc_ogryn_") then player_lines = player_lines + 1 end
end
check("sound list: no weapon sounds, no silent VO routes, enemy and player voice lines", weapon == 0 and routes == 0 and enemy_lines > 1000 and player_lines > 1000)
check("sound list: a voice line is a valid sound and survives encode", Sounds.valid("loc_enemy_cultist_berzerker_a__assault_01") and Sounds.encode(Sounds.parse("loc_enemy_cultist_berzerker_a__assault_01@50")) == "loc_enemy_cultist_berzerker_a__assault_01@50")
check("sound list: attack and impact sounds are gone, vocalisations stay", not Sounds.valid("wwise/events/weapon/play_axe_swing_light") and Sounds.valid("wwise/events/minions/play_cultist_captain__melee_attack_charged_vce"))

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
Events.reset(set,"custom_1",true)
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
  ability.grenades=0
  function ability:ability_is_equipped(kind) return kind=="grenade_ability" and not self.no_grenade end
  function ability:restore_ability_charge(kind,n) assert(kind=="grenade_ability");local room=math.max(0,(self.grenade_room or 3)-self.grenades);local got=math.min(room,n);self.grenades=self.grenades+got;return n,got end
  function ability:restore_ability_resource_percentage(kind,amount,ignore) assert(self._is_local_unit,"husk mutation"); assert(kind=="combat_ability" and ignore);self.restored=self.restored+amount end
  u.extensions.ability_system=ability
  local buff={_buffs_by_index={},next=0,removed=0}
  function buff:add_externally_controlled_buff(name,t) assert((name=="syringe_speed_boost_buff" or name=="syringe_ability_boost_buff" or name=="syringe_power_boost_buff") and t==3);self.names=self.names or {};self.names[#self.names+1]=name;self.next=self.next+1;self._buffs_by_index[self.next]={extra=0,add_duration=function(b,n) b.extra=b.extra+n end};return 4,self.next,7 end
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
-- (2026-10-06) Combat abilities is retired (it never reached the clients' own abilities); Reveal Elites took its place
check("Combat abilities is retired: a saved card that has it loads without it", (function() local v=Schema.parse("cooldown=100:4;heal=5:4"); return v and v.cooldown==nil and v.heal.value==5 and Schema.encode(v)=="heal=5:4" end)())
check("Reveal Elites accepted", start(effect("reveal_elites",5)))
local snapshot=E.snapshot()
check("Reveal Elites: its time travels in the host's state", snapshot.reveal_elites==5)
local client=dofile(BASE .. "/core/effects.lua")
server=false;client.receive(snapshot)
check("Reveal Elites: a client takes the host's time", client.snapshot().reveal_elites==5)
server=true;E.cancel()
check("Reveal Elites: stop ends it", E.snapshot().reveal_elites==0)
p1.inventory.slot_pocketable_small="grim"
check("stimm item accepted", start(effect("green_stimm",1)))
check("items preserve occupied slots and use stable eligible order", #gifts==1 and gifts[1][1]==p2 and p1.inventory.slot_pocketable_small=="grim")
check("yellow stim uses remaining empty slot", start(effect("yellow_stimm",4)) and #gifts==2 and gifts[2][1]==p3)
check("full inventory fails gracefully", not start(effect("green_stimm",4)))
check("medcrate independent large slot", start(effect("med_crate",2)) and #gifts==4)
-- (2026-10-04) the Blue and Red Stimm items, the Ammo Crate: the same native equip, their own items and slots
for _,p in ipairs({p1,p2,p3}) do p.inventory.slot_pocketable_small="not_equipped";p.inventory.slot_pocketable="not_equipped" end
check("blue stimm item: the native celerity syringe into an empty small slot", start(effect("blue_stimm_item",1)) and gifts[#gifts][2]=="content/items/pocketable/syringe_speed_boost_pocketable" and gifts[#gifts][3]=="slot_pocketable_small")
check("red stimm item: the native combat syringe", start(effect("red_stimm_item",1)) and gifts[#gifts][2]=="content/items/pocketable/syringe_power_boost_pocketable")
local before_crates=#gifts
check("ammo crate: the native ammo cache into the large slot, as many players as set", start(effect("ammo_crate",2)) and #gifts==before_crates+2 and gifts[#gifts][2]=="content/items/pocketable/ammo_cache_pocketable" and gifts[#gifts][3]=="slot_pocketable")
check("ammo crate: a party whose large slots are full gets none and the effect reports it", start(effect("ammo_crate",4)) and not start(effect("ammo_crate",4)))
-- replenish grenades: the native charge restore on the host, for every living player with a grenade ability
p2.extensions.ability_system.no_grenade=true;p3.extensions.ability_system.grenade_room=1
check("grenades: each living player with a grenade ability gets the charges (capped by what the native ability takes)", start(effect("grenades",2)) and p1.extensions.ability_system.grenades==2 and p2.extensions.ability_system.grenades==0 and p3.extensions.ability_system.grenades==1)
p1.extensions.ability_system.grenade_room=2
check("grenades: when every pouch is full the effect reports nothing given", not start(effect("grenades",2)))
p2.extensions.ability_system.no_grenade=nil;p1.extensions.ability_system.restore_ability_charge=function() error("no ability") end
check("grenades: one failing player is contained (warned) and the others still get theirs", start(effect("grenades",1)) and p2.extensions.ability_system.grenades==1)
p1.extensions.ability_system.restore_ability_charge=nil
local far,near={alive=true,position=100},{alive=true,position=2}
local function station(charges)
  return {charges=charges,battery_in_slot=function() return true end,charge_amount=function(s) return s.charges end,max_amount_charges=function() return 4 end,set_charge_amount=function(s,n) s.charges=n end,sync_charge_amount=function(s) s.synced=true end}
end
local fs,ns=station(0),station(3)
systems.health_station_system={_unit_to_extension_map={[far]=fs,[near]=ns}}
check("Med Station recharge is disabled for now: saved charges never run", not start(effect("med_station",4)) and ns.charges==3 and not ns.synced and fs.charges==0)
check("disabled effects stay parsed and encoded but are not allowed", Schema.parse("med_station=2:4").med_station.value==2 and not Schema.allowed({med_station={value=2,players=4}},"miracle").med_station)
systems.health_station_system=nil
check("four beneficial suits including Faith; categories are Healing, Buffs, Items and Game Effects", Schema.beneficial("faith") and Schema.CATEGORIES[2].id=="Buffs" and Schema.CATEGORIES[3].id=="Items" and Schema.CATEGORIES[4].id=="Game Effects" and Schema.definition("reveal_elites").category=="Buffs" and Schema.definition("cooldown")==nil and Schema.definition("blue_stimm").category=="Buffs" and Schema.definition("blue_stimm_item").category=="Items" and Schema.definition("revive").category=="Game Effects")
-- the card's lines (2026-10-04, the design page): the amount first, then the short name
check("summary: amount then name", Schema.summary({revive={value=2,players=4}})=="1 Raise the fallen" and Schema.summary({ammo={value=50,players=4}})=="50% Refill ammunition" and Schema.summary({reveal={value=15,players=4}})=="15s Reveal Specialists")
local tags = {}
local marked = Schema.summary({heal={value=95,players=4},reveal={value=15,players=4}}, nil, nil, function (text, rgb) tags[#tags + 1] = text .. "=" .. table.concat(rgb, ","); return "<" .. text .. ">" end, {1,2,3})
check("summary: colour tags, the amount in the text colour and the name in its group's", marked == "<95%> <Party health>\n<15s> <Reveal Specialists>" and tags[1] == "95%=1,2,3" and tags[2] == "Party health=98,200,106" and tags[4] == "Reveal Specialists=108,180,255", marked)
check("summary: hostile Blackout is not a line; a name cut to the characters; +N more", Schema.summary({blackout={value=15,players=4}}) == "" and Schema.summary({cleanse={value=100,players=4}}, nil, 14) == "100% Health..." and Schema.summary({heal={value=5,players=4},cleanse={value=5,players=4},reveal={value=5,players=4}}, 2) == "5% Party health\n+2 more")
local dots = Schema.dots({heal={value=5,players=4},cleanse={value=5,players=4},ammo={value=5,players=4},blackout={value=5,players=4}})
check("dots: one per group of the card's effects, in group order", #dots == 2 and dots[1][1] == 98 and dots[2][1] == 240 and #Schema.dots(nil) == 0)
-- Raise the fallen (2026-10-04, second version): ONE hogtied player is rescued by the native assist (force_assist; `success` alone
-- did nothing in game) and brought to the nearest standing player: the host moves its own player and bots, a remote human's own game
-- does it from a "teleport" grant. Downed players are left to Instant rescue.
for _,p in ipairs({p1,p2,p3}) do
  local data=p.extensions.unit_data_system
  p.state={state_name="walking"}; p.assist={force_assist=false,in_progress=false,success=false}; p.hog={hogtie=true}
  data.read_component=function(_,name) if name=="character_state" then return p.state end return p.inventory end
  data.write_component=function(_,name) if name=="hogtied_state_input" then return p.hog end assert(name=="assisted_state_input");return p.assist end
end
package.preload["scripts/utilities/attack/player_unit_status"]=function() return {
  is_knocked_down=function(c) return c.state_name=="knocked_down" end, is_hogtied=function(c) return c.state_name=="hogtied" end,
  is_disabled=function(c) return c.state_name=="netted" end, is_assisted=function(a) return a.in_progress end } end
local moved={}
package.preload["scripts/utilities/player_movement"]=function() return { teleport=function(player,pos) moved[#moved+1]={player,pos} end } end
local owners={}
Managers.state.player_unit_spawn={owner=function(_,u) return owners[u] end}
local function owner(u,remote,human) owners[u]={unit=u,remote=remote,is_human_controlled=function() return human end} end
owner(p1,false,true);owner(p2,true,true);owner(p3,false,false)
local real_distance, real_wp, real_v3 = Vector3.distance_squared, Unit.world_position, Vector3
Unit.world_position=function(u) return {x=u.position or 0,y=0,z=0} end
Vector3.distance_squared=function(a,b) return (a.x-b.x)^2 end
check("raise the fallen: its amount is fixed (one hogtied player), whatever a card text says", Schema.definition("revive").fixed and Schema.parse("revive=4:4").revive.value==1)
check("nobody hogtied: raise the fallen fails without touching anyone", not start(effect("revive",1)) and not p1.assist.force_assist and #moved==0)
p1.state.state_name="knocked_down";p2.state.state_name="knocked_down"
check("raise the fallen leaves a downed player alone (Instant rescue does that)", not start(effect("revive",1)) and not p1.assist.force_assist and not p2.assist.force_assist)
p1.state.state_name="hogtied";p2.state.state_name="walking";p3.state.state_name="hogtied"
p1.position,p2.position,p3.position=0,50,3
check("raise the fallen rescues ONE hogtied player with the native forced assist (the second stays tied)", start(effect("revive",1)) and p1.assist.force_assist and not p3.assist.force_assist)
E.update(0.3)
check("...not while the rescue is still going on (a teleport during the hogtied state did not stick in game)", #moved==0 and E.pending_bring()==1)
p1.state.state_name="walking";E.update(0.3)
check("...and once the player stands, the host brings its own player to the nearest standing player (p2; p3 is tied too)", #moved==1 and moved[1][1]==owners[p1] and moved[1][2].x==50 and E.pending_bring()==0)
p1.assist.force_assist=false;p1.state.state_name="walking";p3.state.state_name="walking"
p2.state.state_name="hogtied";p2.position=10;p1.position=40;p3.position=12
Managers.state.unit_spawner.game_object_id=function(_,u) return u.id end
local before_grants=#E.snapshot().grants
check("a remote human is rescued too", start(effect("revive",1)) and p2.assist.force_assist)
p2.state.state_name="walking";E.update(0.3)
check("...and once up, brought by a teleport grant to the nearest standing player (p3 at 12, not p1 at 40)", #moved==1 and #E.snapshot().grants==before_grants+1 and E.snapshot().grants[#E.snapshot().grants][4]=="teleport" and E.snapshot().grants[#E.snapshot().grants][5][1]==12 and E.snapshot().grants[#E.snapshot().grants][2]==0)
p2.assist.force_assist=false;p2.state.state_name="hogtied"
p2.assist.in_progress=true
check("a hogtied player someone is already helping is skipped", not start(effect("revive",1)) and not p2.assist.force_assist)
p2.assist.in_progress=false;p1.state.state_name="netted";p3.state.state_name="knocked_down"
check("with nobody standing the rescue still happens", start(effect("revive",1)) and p2.assist.force_assist)
p2.state.state_name="walking";E.update(0.3)
check("...without a teleport (nobody to bring them to)", #moved==1 and #E.snapshot().grants==before_grants+1 and E.pending_bring()==0)
p2.state.state_name="hogtied";start(effect("revive",1));E.update(16)
check("a rescue that never finishes is given up after 15 seconds", E.pending_bring()==0 and #moved==1)
p2.assist.force_assist=false;p1.state.state_name="walking";p2.state.state_name="walking";p3.state.state_name="walking"
-- Instant rescue: the next N players who go down are helped up at once, checked every quarter second; nothing for those already up
check("instant rescue: armed with its count, at most four", start(effect("instant_rescue",2)) and E.rescues_left()==2 and start(effect("instant_rescue",4)) and E.rescues_left()==4)
E.cancel();check("instant rescue: stop disarms it", E.rescues_left()==0)
start(effect("instant_rescue",1));E.update(0.3)
check("instant rescue: nobody down, nothing happens, still armed", E.rescues_left()==1 and not p1.assist.force_assist)
p2.state.state_name="knocked_down";p3.state.state_name="knocked_down";E.update(0.3)
check("instant rescue: the first player to go down is helped up at once (native forced assist), the count is used up", p2.assist.force_assist and not p3.assist.force_assist and E.rescues_left()==0)
p2.assist.force_assist=false;E.update(0.3)
check("instant rescue: used up, the next down player is not helped", not p3.assist.force_assist)
p2.state.state_name="walking";start(effect("instant_rescue",1));p3.assist.in_progress=true;E.update(0.3)
check("instant rescue: a player someone is already helping is skipped and the rescue stays armed", not p3.assist.force_assist and E.rescues_left()==1)
p3.assist.in_progress=false;server=false;E.update(0.3);server=true
check("instant rescue: only the host acts", not p3.assist.force_assist)
E.update(0.3);check("instant rescue: the host helps the down player up", p3.assist.force_assist and E.rescues_left()==0)
E.reset();check("instant rescue: reset disarms it", E.rescues_left()==0)
p2.state.state_name="walking";p3.state.state_name="walking";p3.assist.force_assist=false
-- a client brings its own player when the host's teleport grant reaches it; old grants are not replayed; another player's grant is ignored
do
  local cl=dofile(BASE .. "/core/effects.lua")
  server=false;moved={}
  p1.extensions.ability_system._is_local_unit=false;p2.extensions.ability_system._is_local_unit=true
  Vector3=setmetatable({distance_squared=Vector3.distance_squared},{__call=function(_,x,y,z) return {x=x,y=y,z=z} end})
  cl.receive({sequence=E.snapshot().sequence,grant_sequence=1,grants={}})
  cl.receive({sequence=E.snapshot().sequence,grant_sequence=2,grants={{2,0,{p2.id},"teleport",{7,8,9}}}})
  check("teleport grant: the remote player's own game brings them to the place the host chose", #moved==1 and moved[1][1]==owners[p2] and moved[1][2].x==7 and moved[1][2].z==9)
  cl.receive({sequence=E.snapshot().sequence,grant_sequence=2,grants={{2,0,{p2.id},"teleport",{7,8,9}}}})
  cl.receive({sequence=E.snapshot().sequence,grant_sequence=3,grants={{3,0,{p1.id},"teleport",{1,1,1}},{4,0,{p2.id},"teleport",{"x",1,1}}}})
  check("teleport grant: never twice, never for another player, never with a broken place", #moved==1)
  p1.extensions.ability_system._is_local_unit=true;p2.extensions.ability_system._is_local_unit=false
  server=true
  Vector3=real_v3
end
Vector3.distance_squared, Unit.world_position = real_distance, real_wp
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
-- (2026-10-04) the Yellow and Red Stimm buffs: the native concentration and combat syringe buffs, their seconds, their players
check("yellow stimm buff: the native concentration buff for the set players and seconds", start(effect("yellow_stimm_buff",20,1)) and p1.extensions.buff_system.names[#p1.extensions.buff_system.names]=="syringe_ability_boost_buff" and p1.extensions.buff_system._buffs_by_index[p1.extensions.buff_system.next].extra==5)
check("red stimm buff: the native combat buff", start(effect("red_stimm_buff",15,1)) and p1.extensions.buff_system.names[#p1.extensions.buff_system.names]=="syringe_power_boost_buff")
E.cancel()
local l1,l2={alive=true},{alive=true}
local function light(on) return {on=on,is_enabled=function(s) return s.on end,set_enabled=function(s,on,deterministic) assert(deterministic==true,"the lights are switched without an RPC");s.on=on end} end
local a,b=light(true),light(false)
systems.light_controller_system={_unit_to_extension_map={[l1]=a,[l2]=b}}
check("blackout uses level controller", start(effect("blackout",2),"heresy") and not a.on and not b.on)
E.update(1);start(effect("blackout",3),"heresy")
local l3,c={alive=true},light(true);systems.light_controller_system._unit_to_extension_map[l3]=c
E.update(1);check("streamed lights join overlapping outage", not a.on and not c.on)
E.update(2.25,true);check("outage expires during scheduler pause and restores initial states", a.on and not b.on and c.on)
start(effect("blackout",30),"heresy");E.cancel();check("stop restores lighting", a.on and not b.on)
-- (2026-10-06, a client crashed in a Blackout: the game's light RPC reached a light without its extension there) every machine
-- darkens its own lights for the host's time
start(effect("blackout",5),"heresy");local dark=E.snapshot();E.cancel()
check("blackout: the host's state carries its time", dark.blackout==5 and a.on and c.on)
server=false;client.reset();client.receive(dark);client.update(0.25)
check("blackout: a client darkens its own lights from the host's state", not a.on and not c.on and not b.on)
client.update(6)
check("blackout: ...and lights them again when the time is up", a.on and c.on and not b.on)
client.receive(dark);client.update(0.25);client.receive({sequence=dark.sequence,revision=dark.revision,time=dark.time+1,blackout=0})
check("blackout: a host state without it lights them at once", a.on and c.on and not b.on)
client.reset();server=true
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
-- Reveal Elites (2026-10-06): the Elites in amber, the Specialists left to Reveal Specialists
local elite={id=52,alive=true,extensions={unit_data_system={breed=function() return {tags={elite=true}} end}}}
local ee={settings=original};outline._unit_extension_data[elite]=ee
E.reset();se.settings=original;start(effect("reveal_elites",1));E.update(0.25)
check("Reveal Elites: Elites only, in amber", ee.settings.rw_guidance and ee.settings.rw_guidance.color[1]==0.86 and not se.settings.rw_guidance and not ge.settings.rw_guidance)
start(effect("reveal",1));E.update(0.25)
check("Reveal Elites: both reveals at once, each in its colour", se.settings.rw_guidance and se.settings.rw_guidance.color[1]==0.31 and ee.settings.rw_guidance.color[1]==0.86)
E.update(1)
check("Reveal Elites: the outlines go when the time is up", ee.settings==original and not se.settings.rw_guidance)
outline._unit_extension_data[elite]=nil;E.reset()
-- (2026-10-06, a performance pass) a unit's breed is read once, not at every scan of a reveal
local calls=0
local counted={id=53,alive=true,extensions={unit_data_system={breed=function() calls=calls+1; return {tags={}} end}}}
outline._unit_extension_data[counted]={settings=original}
start(effect("reveal",5));for _=1,8 do E.update(0.25) end
check("reveal: a unit's breed is read once, not four times a second", calls==1, calls)
outline._unit_extension_data[counted]=nil;E.reset()
-- the card's sound is an ALERT at the draw (2026-10-04): no completion ticket, no sound when the wave ends
E.reset()
local ok,ticket=start(effect("heal",100),nil,event)
check("a card's effects start without a completion ticket", ok and ticket==nil and E.add_unit==nil and E.finish==nil)
E.update(5);check("nothing sounds when the wave's effects start or end", #played==0)
local before=#played
local job=E.alert(event)
check("alert: the host plays the card's sound at once and journals it for the other players", job~=nil and not job.done and #played==before+1 and E.snapshot().sequence==1 and E.snapshot().audio[1][2]==event)
E.tick_audio(1);check("alert: not over while its sound may still play", not job.done)
E.tick_audio(2);check("alert: over when its sound has ended (a sound without an id: after the gap)", job.done)
check("alert: no sound, no alert (the wave goes at once), nothing journaled", E.alert("")==nil and E.alert(nil)==nil and E.alert("arbitrary/file")==nil and E.snapshot().sequence==1)
settings.card_sounds=false;local muted=E.alert(event)
check("alert: a host who muted card sounds hears nothing and does not hold the wave; the others still get it", muted==nil and E.snapshot().sequence==2 and #played==before+1);settings.card_sounds=nil
server=false;check("alert: only the host raises one", E.alert(event)==nil);server=true
for i=1,10 do E.alert(event) end
check("audio history bounded", #E.snapshot().audio==8)
client.reset();server=false;before=#played;client.receive(E.snapshot())
check("late join audio baseline silent", #played==before)
server=true;E.alert(event);snapshot=E.snapshot();before=#played
server=false;client.receive(snapshot);client.receive(snapshot)
check("duplicate snapshots never repeat sound (a client hears the alert once)", #played==before+1)
client.receive({sequence=0,reveal=300});client.update(0.25)
check("stale snapshot cannot revive guidance", client.snapshot().reveal==0)
client.receive({sequence=0/0});client.receive(false);client.receive({sequence=999,audio={{999,"arbitrary/file"}}})
check("malformed/unverified client sound ignored", #played==before+1)
server=true;settings.card_sounds=false;E.preview_sound(event);check("audio option mutes preview",#played==before+1)
settings.card_sounds=nil;E.preview_sound(event);check("no local player (a menu): the sound plays in the UI world without a source",native_played[#native_played]==event and heard_in[#heard_in][1]=="wwise:ui" and heard_in[#heard_in][2]==nil)
-- (2026-10-04: a 3D event triggered without a source played at the world's origin and nobody heard it)
local_player={player_unit={name="me"}};E.preview_sound(event)
check("with a local player the sound plays in the level's sound world on an auto source on the player",native_played[#native_played]==event and heard_in[#heard_in][1]=="wwise:level_world" and heard_in[#heard_in][2]=="auto:me")
local line="loc_enemy_cultist_berzerker_a__assault_01";E.preview_sound(line)
check("a voice line streams its file through the 2D player voice route on the player's source",native_played[#native_played]=="wwise/externals/"..line and heard_in[#heard_in].route=="wwise/events/vo/play_sfx_es_player_vo_2d" and heard_in[#heard_in].es=="es_player_vo_2d" and heard_in[#heard_in].format==4 and heard_in[#heard_in][2]=="auto:me")
local_player.player_unit.alive=false;E.preview_sound(event);check("a dead player unit falls back to the UI world",heard_in[#heard_in][1]=="wwise:ui");local_player=nil
local real_trigger=WwiseWorld.trigger_resource_event;WwiseWorld.trigger_resource_event=function() error("missing bank") end
E.preview_sound(event);check("optional audio failure contained",#warnings>0);WwiseWorld.trigger_resource_event=real_trigger
local X=dofile(BASE .. "/spawn/execute.lua")
Managers.state.minion_spawn={}
X.init({positions={},bypass={count=function()return 0 end,purge=function()end,reset=function()end},groups=Groups,effects=E})
E.reset();before=#played
local hostile_recipe=Groups.parse("3 hounds")
check("executor: malicious enemy recipe on beneficial face is masked",X.start_wave({suit="prayer",parts=hostile_recipe,effects=effect("heal",10),sound=event}) and X.status().queued==0)
X.update(0.25);X.update(0.25)
check("executor: a wave that ends plays nothing (its sound was the draw's alert)",#played==before and X.status().jobs==0)
X.start_wave({suit="prayer",parts={},effects=effect("reveal",30),sound=event});X.cancel();X.update(1)
check("executor: stop leaves no job and no sound",#played==before and X.status().jobs==0)
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
WwiseWorld.trigger_resource_event=function(_,ev,source) ids=ids+1;playing[ids]=true;native_played[#native_played+1]=ev;played[#played+1]=ev;return ids end
WwiseWorld.is_playing=function(_,id) return playing[id]==true end
WwiseWorld.make_manual_source=function() sources[#sources+1]="s"..#sources;return sources[#sources] end
WwiseWorld.set_source_parameter=function(_,s,name,v) params[#params+1]={s,name,v} end
WwiseWorld.destroy_manual_source=function(_,s) sources.destroyed=(sources.destroyed or 0)+1 end
Vector3.zero=function() return 0 end;Quaternion={identity=function() return 1 end};Application={user_setting=function() return 80 end}
simple=nil;E.tick_audio(13);local n0=#native_played -- (flush the sounds the checks above left in the chain)
E.preview_sound(ev1..";"..ev2)
check("the first sound plays at once, the second waits", #native_played==n0+1 and native_played[#native_played]==ev1 and E.chain_size()==1)
E.tick_audio(1);check("while the first still plays the second waits", #native_played==n0+1)
playing[ids]=false;E.tick_audio(0.1)
check("the second starts when the first has ended (and is followed until it ends too)", #native_played==n0+2 and native_played[#native_played]==ev2 and E.chain_size()==1)
playing[ids]=false;E.tick_audio(0.4);check("...then the chain is empty", E.chain_size()==0)
local_player={player_unit={name="me"}};E.preview_sound(ev1.."@50")
check("a quieter sound sets the sfx volume, scaled, on the player's auto source", params[#params][1]=="auto:me" and params[#params][2]=="options_sfx_slider" and params[#params][3]==40 and #sources==0)
n0=#params;E.preview_sound(ev1);check("full volume sets no parameter", #params==n0);local_player=nil
n0=#native_played;E.preview_sound(ev1.."@0;"..ev2)
check("a muted sound is skipped and the next one plays", #native_played==n0+1 and native_played[#native_played]==ev2)
n0=#native_played;E.preview_sound(ev1..";"..ev2);E.tick_audio(12.5)
check("a sound that never reports its end lets the next one start after twelve seconds", #native_played==n0+2)
E.tick_audio(13)
server=true;local aj=E.alert(ev1..";"..ev2)
playing[ids]=false;E.tick_audio(0.1);check("alert: a sound is never over before 0.3 s (it may not report itself on its first frame)", not aj.done)
E.tick_audio(0.3);check("alert of two sounds: the second starts when the first has ended, the alert goes on", not aj.done and native_played[#native_played]==ev2)
playing[ids]=false;E.tick_audio(0.4);check("alert of two sounds: over when the second has ended", aj.done)
local with_id=WwiseWorld.trigger_resource_event;WwiseWorld.trigger_resource_event=function(_,ev) played[#played+1]=ev end;local p0=#played
E.preview_sound(ev1..";"..ev2);check("a sound without a playing id: the second follows after a short gap", #played==p0+1)
E.tick_audio(2.6);check("...and plays", #played==p0+2 and played[#played]==ev2);WwiseWorld.trigger_resource_event=with_id
for i=1,12 do E.preview_sound(ev1..";"..ev2) end;check("the chain is bounded", E.chain_size()<=8)
E.reset();check("reset empties the chain", E.chain_size()==0)
E.alert(ev1.."@30;"..ev2)
check("a card's two sounds travel in the audio journal as one text", E.snapshot().audio[#E.snapshot().audio][2]==ev1.."@30;"..ev2)
simple=nil
'''

EDITOR = r'''
do
  local EF=mod.rw.groups.Effects
  local PP=mod:io_dofile("GrandfathersTarot/scripts/mods/GrandfathersTarot/ui/wave_editor_components").Popup
  local SO=mod:io_dofile("GrandfathersTarot/scripts/mods/GrandfathersTarot/catalog/sounds")
  local EV=mod:io_dofile("GrandfathersTarot/scripts/mods/GrandfathersTarot/ui/wave_editor_effects")
  local WK=mod:io_dofile("GrandfathersTarot/scripts/mods/GrandfathersTarot/ui/workshop")
  -- a row reads "100%  Party health" (the amount in colour tags first): its name and its amount without the tags
  local function plain_label(w) return (w.content.label:gsub("{#[^}]*}","")) end
  local function row_name(w) return (plain_label(w):gsub("^%S+%s+","")) end
  local function row_lead(w) return plain_label(w):match("^(%S+)") end
  local function chip(id) for i,c in ipairs(EV.shelf_layout.chips) do if c.def.id==id then return i,view._widgets_by_name["rw_fxchip_"..i] end end end
  mod.rw.events.set_def(function(id,v) settings[id]=v end,"custom_20","Blessing",mod.rw.groups.parse("2 hounds"),mod.rw.groups)
  settings.su_custom_20="prayer";settings.fx_custom_20="heal=100:4";settings.th_custom_20=6
  view:_open_detail("custom_20")
  local W=view._widgets_by_name
  check("effects UI: the enemy rows, shelf and spawn controls give way to the effect rows and the effect shelf",W.rw_fxrow_1.visible and not W.rw_fxrow_2.visible and W.fx_shelf.visible and W.fx_header.visible and not W.rw_erow_1.visible and not W.shelf_panel.visible and not W.btn_add.visible and W.btn_enemies.content.hotspot_text=="Beneficial Effects")
  check("effects UI: a row names the effect, its group under it and on its edge, the amount in words; no players for a heal",row_name(W.rw_fxrow_1)=="Party health" and row_lead(W.rw_fxrow_1)=="100%" and W.rw_fxrow_1.content.info=="Healing" and W.rw_fxrow_1.content.edge_rgb[1]==98 and W.rw_fxrow_1.content.amount_value=="100 percent" and not W.rw_fxrow_1.content.show_players and W.rw_fxrow_1.content.no_players=="-")
  check("effects UI: the shelf has four groups: Healing, Buffs, Items and Game Effects",W.fx_shelf.content.band_1=="HEALING" and W.fx_shelf.content.band_2=="BUFFS" and W.fx_shelf.content.band_3=="ITEMS" and W.fx_shelf.content.band_4=="GAME EFFECTS")
  local mi,med=chip("med_station")
  check("effects UI: Recharge Med Station is greyed and says it is off for now",med.visible and med.content.hotspot.disabled==true and med.content.chip_label:find("fx_off_for_now",1,true)~=nil)
  view:cb_fx_chip(mi);check("effects UI: a click on the disabled chip changes nothing",not view._wave.effects.med_station)
  view:cb_add();check("effects UI: direct enemy callback cannot open picker",view._screen=="detail" and not view._popup)
  local ci,cleanse=chip("cleanse")
  check("effects UI: a chip is lit when the card holds its effect",select(2,chip("heal")).content.hotspot_on==true and cleanse.content.hotspot_on==false)
  view:cb_fx_chip(ci);check("effects UI: a chip adds its effect at its default, as a new row in catalog order",view._wave.effects.cleanse.value==100 and W.rw_fxrow_2.visible and row_name(W.rw_fxrow_2)=="Health and corruption" and select(2,chip("cleanse")).content.hotspot_on)
  view:cb_fx_chip(ci);check("effects UI: a second click takes it off",not view._wave.effects.cleanse and not W.rw_fxrow_2.visible)
  view:cb_fx_step(1,"value",-1);check("effects UI: the amount stepper takes 5 percent off",view._wave.effects.heal.value==95 and W.rw_fxrow_1.content.amount_value=="95 percent")
  view:cb_fx_step(1,"value",1);view:cb_fx_step(1,"value",1);check("effects UI: ...and never goes past the maximum",view._wave.effects.heal.value==100)
  for _=1,30 do view:cb_fx_step(1,"value",-1) end;check("effects UI: ...nor below one step (Remove takes an effect off)",view._wave.effects.heal.value==5)
  view:cb_fx_number(1,"value");PP.set_text(view,"50");PP.commit(view);check("effects UI: a click on the amount opens the box and saves",view._wave.effects.heal.value==50)
  view:cb_fx_number(1,"players");check("effects UI: a heal has no players box",view._popup==nil)
  local bi=chip("blue_stimm");view:cb_fx_chip(bi)
  local brow=nil;for i=1,6 do if W["rw_fxrow_"..i].visible and row_name(W["rw_fxrow_"..i])=="Blue Stimm buff" then brow=i end end
  check("effects UI: Blue Stimm has its players stepper (4 players) beside its seconds",brow~=nil and W["rw_fxrow_"..brow].content.show_players and W["rw_fxrow_"..brow].content.players_value=="4 players" and W["rw_fxrow_"..brow].content.amount_value=="15 seconds")
  view:cb_fx_step(brow,"players",-1);check("effects UI: one player fewer",view._wave.effects.blue_stimm.players==3)
  view:cb_fx_number(brow,"players");PP.set_text(view,"2");PP.commit(view);check("effects UI: blue targets configurable in the box",view._wave.effects.blue_stimm.players==2)
  local ri=chip("revive");view:cb_fx_chip(ri)
  check("effects UI: Raise the fallen (Game Effects) arrives as one hogtied player brought back, with no amount to step",view._wave.effects.revive.value==1 and (function() for i=1,6 do local w=W["rw_fxrow_"..i]; if row_name(w)=="Raise the fallen" and w.visible then return w.content.amount_value=="fx_fixed_revive" and row_lead(w)=="1" and w.content.amount_plus.disabled and w.content.amount_value_hotspot.disabled end end end)())
  do
    local row;for i=1,6 do if row_name(W["rw_fxrow_"..i])=="Raise the fallen" and W["rw_fxrow_"..i].visible then row=i end end
    view:cb_fx_step(row,"value",1);view:cb_fx_number(row,"value")
    check("effects UI: its stepper and its number box do nothing",view._wave.effects.revive.value==1 and view._popup==nil)
  end
  check("effects UI: the stimm buffs are in Buffs and the stimm items in Items, the new Game Effects there too",(function() local col={} for _,c in ipairs(EV.shelf_layout.chips) do col[c.def.id]=EV.shelf_layout.bands[c.column].id end return col.yellow_stimm_buff=="Buffs" and col.blue_stimm=="Buffs" and col.red_stimm_buff=="Buffs" and col.yellow_stimm=="Items" and col.blue_stimm_item=="Items" and col.red_stimm_item=="Items" and col.grenades=="Game Effects" and col.ammo_crate=="Game Effects" end)())
  view:cb_fx_remove(1);check("effects UI: Remove on a row takes its effect off",not view._wave.effects.heal and view._wave.effects.blue_stimm)
  check("effects UI: APOTHEOSIS: a beneficial card's sixth diamond is visible and not edged in Despair's lilac",W.rw_stage_card.style.th_o6.visible and W.rw_stage_card.style.th_h6.color[2]~=0xc7)
  check("effects UI: the beneficial shelf ends above the timer and the action bar",WK.SHELF_Y+EV.shelf_layout.height<=view._definitions.scenegraph_definition.stepper_timer.position[2] and #EV.shelf_layout.chips==18)
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
  -- (2026-10-04, the design page) chips as wide as their labels in four columns, a one unit outline, a lit diamond on the effect chips
  local hi,heal_chip=chip("heal");local _,cleanse_chip=chip("cleanse")
  check("effects UI: chips are as wide as their labels (a longer name, a wider chip)",cleanse_chip.style.hotspot.size[1]>heal_chip.style.hotspot.size[1])
  check("effects UI: a chip has a one unit outline and no second frame",W.rw_chip_1.style.chip_frame.size[1]==W.rw_chip_1.style.hotspot.size[1] and W.rw_chip_1.style.chip_fill.offset[1]==1 and W.rw_chip_1.style.chip_edge_r==nil and W.rw_chip_1.style.chip_line_r.size[1]==1 and W.rw_chip_1.style.chip_line_r.offset[1]==W.rw_chip_1.style.chip_frame.size[1]-1 and W.rw_chip_1.style.chip_line_r.offset[3]>W.rw_chip_1.style.chip_fill.offset[3])
  check("effects UI: the effect chips have a diamond at the right end, the enemy chips none",heal_chip.style.chip_pip~=nil and heal_chip.style.chip_pip.offset[1]>heal_chip.style.hotspot.size[1]-24 and W.rw_chip_1.style.chip_pip==nil)
  check("effects UI: the effect shelf is four columns, one per group, each chip inside its column",(function() local bands=EV.shelf_layout.bands;if #bands~=4 then return false end;for _,c in ipairs(EV.shelf_layout.chips) do local b=bands[c.column];if c.x<b.x-0.5 or c.x+c.w>b.x+b.w+0.5 then return false end end;return bands[1].x<bands[2].x and bands[3].x<bands[4].x end)())

  local before=settings.wave_def_wave_small
  -- the Deck's Search (2026-10-04, in place of Consecrate 12 cards): the cards whose name, suit, enemy or effect hold the text
  view:cb_back();view._deck_query=nil;view:_build_deck()
  local total=#view._deck
  check("deck search: the button is on the Deck in Consecrate's place and says Search cards",W.rw_deck_search.visible and W.rw_deck_search.content.hotspot_text=="btn_deck_search" and view.cb_bless_deck==nil)
  local function typed(text) PP.set_text(view,text);view._popup.spec.on_change(text) end -- (the popup reports typing in its frame update)
  view:cb_deck_search();typed("hound")
  local holds,blank=true,false
  for _,w in ipairs(view._deck) do if w.blank then blank=true end end
  check("deck search: typing filters the Deck as it is typed (enemy names count), the blank card is hidden",view._popup~=nil and #view._deck>0 and #view._deck<total and not blank,#view._deck.."/"..total)
  PP.commit(view)
  check("deck search: OK keeps the search, the button says it and is lit",view._deck_query=="hound" and W.rw_deck_search.content.hotspot_text=="btn_search_active:hound" and W.rw_deck_search.content.hotspot_on==true)
  view:cb_deck_search();typed("blackout")
  local found=false;for _,w in ipairs(view._deck) do if w.key=="custom_20" then found=true end end
  check("deck search: an effect's name finds the card that holds it (Blackout on the Heresy card)",found)
  typed("HERESY");found=false;for _,w in ipairs(view._deck) do if w.key=="custom_20" then found=true end end
  check("deck search: a suit's name finds its cards, whatever the case",found)
  typed("zzzz nothing");check("deck search: nothing matches -> an empty Deck",#view._deck==0)
  PP.cancel(view);check("deck search: Escape puts the search back as it was",view._deck_query=="hound" and #view._deck<total)
  view:cb_deck_search();typed("   ");PP.commit(view)
  check("deck search: an empty search shows every card again, the blank one too",#view._deck==total and W.rw_deck_search.content.hotspot_text=="btn_deck_search")
  view._screen="detail";view:cb_deck_search();check("deck search: does nothing off the Deck",view._popup==nil);view._screen="list"
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
