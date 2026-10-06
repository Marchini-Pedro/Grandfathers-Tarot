"""Enemy colour schema, lifecycle, peer validation and actual editor interactions.

Reuses the editor's existing engine stubs without changing the CI agent's harness.
Run: python tools/appearance_test.py. Optional UI_DUMP_DIR writes colour screens.
"""
import ast
import importlib
import os
from pathlib import Path
os.environ.setdefault("RW_LUA_RUNTIME", os.environ.get("LUA_RUNTIME", "lua55"))
try:
    from lua_test_runtime import LuaRuntime
except ModuleNotFoundError as error:
    if error.name != "lua_test_runtime":
        raise
    LuaRuntime = importlib.import_module("lupa." + os.environ["RW_LUA_RUNTIME"]).LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
BASE = (ROOT / "scripts/mods/GrandfathersTarot").as_posix()

RUNTIME = r'''
local BASE = ...
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1; print("PASS appearance: " .. label) end
local server, warnings, writes, sent, rpcs, packets = true, {}, {}, {}, {}, {}
local mod = { rw = {} }
function mod:io_dofile(path) return dofile(BASE .. "/" .. path:match("GrandfathersTarot/scripts/mods/GrandfathersTarot/(.*)") .. ".lua") end
function mod:warning(fmt, ...) warnings[#warnings + 1] = string.format(fmt, ...) end
mod.error = mod.warning
function mod:get() return false end
local realms = { network_is_available = function() return true end,
  network_register = function(_, name, fn) rpcs[name] = fn; return true end,
  network_send = function(_, name, peer, ...) sent[#sent + 1] = {name, peer, ...}; return true end,
  network_on_peer_joined = function(_, fn) realms_join = fn end,
  network_on_peer_left = function(_, fn) realms_left = fn end }
get_mod = function(name) return name == "Realms" and realms or mod end
local packet_number = 0
cjson = { encode = function(value) packet_number = packet_number + 1; local key = tostring(packet_number); packets[key] = value; return key end,
  decode = function(key) return packets[key] end }
local Schema = dofile(BASE .. "/catalog/appearance.lua")
local Groups = dofile(BASE .. "/catalog/groups.lua")
local purple = { method="applied_stimm", a=255, r=128, g=0, b=255 }
for _, method in ipairs(Schema.METHODS) do
  local value = Schema.copy(purple); value.method = method.id
  local parts = assert(Groups.parse("2 crushers{size=130}" .. Schema.recipe(value) .. "@2, 1 crusher"))
  check("recipe round trip " .. method.id, #parts == 2 and Schema.recipe(Groups.parse(Groups.to_recipe(parts))[1].appearance) == Schema.recipe(value))
end
for _, flags in ipairs({{outline=true}, {protect=true}, {outline=true,protect=true}}) do
  local value=Schema.copy(purple); value.outline=flags.outline; value.protect=flags.protect
  local parts=assert(Groups.parse("2 crushers[enraged]{size=130}"..Schema.recipe(value).."@2 + 1 hound"))
  local reopened=assert(Groups.parse(Groups.to_recipe(parts)))
  check("flagged recipe preserves suffix and enemy separators",#reopened==2 and reopened[1].count==2 and reopened[1].rep==2 and Schema.recipe(reopened[1].appearance)==Schema.recipe(value) and not reopened[2].appearance)
end
check("differently coloured groups stay separate", #Groups.parse("1 hound<applied_stimm:FFFF0000>, 1 hound<applied_stimm:FF00FF00>") == 2)
check("identical colours merge", Groups.parse("1 hound<applied_stimm:FFFF0000>, 1 hound<applied_stimm:FFFF0000>")[1].count == 2)
for _, text in ipairs({"<bad:FFFFFFFF>","<applied_stimm:FFFF>","<applied_stimm:ZZFFFFFF>","<applied_stimm:FFFFFFFFF>"}) do
  check("invalid recipe " .. text, Groups.parse("1 hound" .. text) == nil)
end
check("copy rejects NaN", not Schema.copy({method="outline",a=0/0,r=0,g=0,b=0}))
check("copy rejects infinity", not Schema.copy({method="outline",a=math.huge,r=0,g=0,b=0}))
check("copy clamps channels", Schema.copy({method="outline",a=999,r=-1,g=0.6,b=0}).g == 1)
local r,g,b = Schema.rgb({a=0,r=255,g=255,b=255})
check("zero strength is zero RGB", r==0 and g==0 and b==0)

Vector3 = function(r,g,b) return {r,g,b} end
BLACKBOARDS = {}
package.preload["scripts/extension_systems/blackboard/utilities/blackboard"] = function() return {
  has_component = function(bb, key) return bb[key] ~= nil end, write_component = function(bb,key) return bb[key] end } end
package.preload["scripts/settings/breed/breed_actions"] = function() return {chaos_ogryn_executor={use_stim={}}} end
local units = {}
Unit = { alive = function(u) return u.alive == true end,
  set_vector3_for_materials = function(u, key, value, recursive)
    assert(key=="stimmed_color" and recursive==true); if u.fail then error("setter failure") end
    writes[#writes+1] = {u,value}; u.colour = value
  end }
ScriptUnit = { has_extension = function(u, name) return u.extensions[name] end }
local outlines = {}
local outline_system = { add_outline = function(_,u,name) outlines[u] = (outlines[u] or 0)+1 end,
  remove_outline = function(_,u,name) outlines[u] = (outlines[u] or 0)-1 end }
Managers = { connection={host=function() return "host" end}, state={
  game_session={is_server=function() return server end},
  unit_spawner={game_object_id=function(_,u) return u.id end, unit_exists=function(_,id) return units[id]~=nil end, unit=function(_,id) return units[id] end},
  extension={system=function() return outline_system end} } }
local shared_settings = { tag = {color={1,0,0}} }
local function unit(id, breed)
  local u = {id=id,breed=breed or "chaos_hound",alive=true,extensions={}}
  local loadout = {slots={}}
  function loadout:slot_items() return self.slots end
  function loadout:slot_unit(name) local s=self.slots[name]; return s.unit,s.attachments end
  u.extensions.visual_loadout_system=loadout
  u.extensions.unit_data_system={breed=function() return {name=u.breed} end}
  u.extensions.buff_system={stat_buffs={damage=1},has_keyword=function() return u.stimmed==true end}
  u.extensions.outline_system={settings=shared_settings}
  units[id]=u; return u
end
local A = dofile(BASE .. "/spawn/appearance.lua")
local P = dofile(BASE .. "/core/protocol.lua")
mod.rw.appearance=A
A.init({schema=Schema,protocol=P})
local received={}
P.init({on_appearance=function(_,entries) received=entries; A.receive(entries) end,on_welcome=function() end})
local treated, control = unit(1), unit(2)
A.apply(treated,purple,treated.breed); A.update(0.25)
check("visual tint only touches selected unit", treated.colour[1]==128/255 and treated.colour[3]==1 and not control.colour)
check("visual tint leaves stats alone", treated.extensions.buff_system.stat_buffs.damage==1)
local before=#writes; A.update(0.25)
check("stable tint is not rewritten every tick", #writes==before)
treated.extensions.buff_system._current_material_vector_effect={material_vector_name="stimmed_color",value={0.2,0.3,0.4}}
A.update(0.25); A.reset()
check("cleanup restores current buff material vector", treated.colour[1]==0.2 and treated.colour[3]==0.4)
local child, attachment = unit(3), unit(4)
treated.extensions.visual_loadout_system.slots.body={unit=child,attachments={attachment}}
local slots=Schema.copy(purple); slots.method="slot_stimm"
A.apply(treated,slots,treated.breed); A.update(0.25)
check("explicit slots and attachments written", child.colour[3]==1 and attachment.colour[3]==1)
treated.extensions.visual_loadout_system.slots.body.attachments={}
A.update(0.25)
check("detached attachment is restored", attachment.colour[3]==0.4)
treated.alive=false; A.update(0.25)
check("death prunes ownership and restores surviving children", A.status().selected==0 and child.colour[3]==0)
treated.alive=true
local outline=Schema.copy(purple); outline.method="outline"
A.apply(treated,outline,treated.breed); A.update(1)
check("outline has one balanced stack and private settings", outlines[treated]==1 and treated.extensions.outline_system.settings~=shared_settings and not shared_settings.rw_selected_colour)
treated.extensions.outline_system.settings.other_mod={}
A.reset()
check("outline removal preserves another mod's addition", outlines[treated]==0 and treated.extensions.outline_system.settings.other_mod and not treated.extensions.outline_system.settings.rw_selected_colour)
local safe_hooks={}
local require_hooks=0
function mod:hook_require(path,fn) check("native tint hook path",path=="scripts/extension_systems/buff/minion_buff_extension");local class={};local h=mod.hook_safe;mod.hook_safe=function(...) require_hooks=require_hooks+1;return h(...) end;fn(class);fn(class);mod.hook_safe=h;check("the buff class loaded twice is hooked once (no DMF rehook warning)",require_hooks==2);fn({}) end
function mod:hook_safe(class,name,fn) safe_hooks[name]=fn end
A.install()
local combined=Schema.copy(purple);combined.outline=true;combined.protect=true
local encoded=Schema.recipe(combined)
check("simultaneous outline/protected tint recipe",Schema.parse(encoded:sub(2,-2)).outline and Schema.parse(encoded:sub(2,-2)).protect)
A.apply(treated,combined,treated.breed);A.update(0.25)
local selected=treated.extensions.outline_system.settings.rw_selected_colour
check("ordinary outline: one layer, priority 2, manual tags keep precedence",#selected.material_layers==1 and selected.material_layers[1]=="minion_outline" and selected.priority==2 and treated.extensions.outline_system.settings.tag==shared_settings.tag)
check("independent outline and tint coexist",outlines[treated]==1 and treated.colour[3]==1)
-- line of sight (2026-10-04: the outline was seen through walls): the outline's visibility_check casts a ray from the local camera to
-- the spine, then the head (static geometry only), unless a player tagged the enemy; each enemy at most every 0.15 s
do
  local vis = selected.visibility_check
  local saved = { system = Managers.state.extension.system, player = Managers.player, camera = Managers.state.camera, world = Managers.world, time = Managers.time, V = Vector3, has_node = Unit.has_node, node = Unit.node, pos = Unit.world_position }
  local now, tagged, walls, filters, rays = 0, {}, {}, {}, 0
  Managers.state.extension.system = function(_, name) if name == "smart_tag_system" then return { is_unit_tagged = function(_, u) return tagged[u] == true end } end return outline_system end
  Managers.player = { local_player_safe = function() return { viewport_name = "player1" } end }
  Managers.state.camera = { camera_position = function() return 0 end }
  Managers.world = { world = function() return "level" end }
  Managers.time = { has_timer = function() return true end, time = function() return now end }
  World = { physics_world = function() return "physics" end }
  PhysicsWorld = { raycast = function(_, from, dir, dist, mode, key, filter)
    rays = rays + 1; filters[#filters + 1] = filter
    local wall = walls[current_node]
    if wall == "error" then error("physics gone") end
    if wall then return true, nil, wall end
    return false
  end }
  Vector3 = setmetatable({ distance = function(a, b) return math.abs(b - a) end, normalize = function(v) return v >= 0 and 1 or -1 end }, { __call = saved.V })
  Unit.has_node = function(u, name) return u.nodes == nil or u.nodes[name] == true end
  Unit.node = function(u, name) current_node = name; return name end
  Unit.world_position = function(u, node) current_node = node; return 10 end
  local enemy = unit(900, "renegade_gunner")
  check("line of sight: is the outline's visibility check", type(vis) == "function")
  check("line of sight: a clear view shows the outline, the ray uses the minions' static line-of-sight filter", vis(enemy) == true and filters[#filters] == "filter_minion_line_of_sight_check")
  now = 1; walls.j_spine = 4; walls.j_head = 4
  check("line of sight: a wall between the camera and the enemy hides it", vis(enemy) == false)
  local before = rays; walls.j_spine, walls.j_head = nil, nil
  check("line of sight: asked again within 0.15 s the answer is kept (no new ray)", vis(enemy) == false and rays == before)
  now = 1.2
  check("line of sight: after 0.15 s it is cast again (the wall is gone: shown)", vis(enemy) == true and rays > before)
  now = 2; walls.j_spine = 4
  check("line of sight: the spine behind cover but the head in view still shows it", vis(enemy) == true)
  now = 3; walls.j_spine, walls.j_head = 9.8, 9.8
  check("line of sight: a hit at the enemy itself (within 0.4) is not a wall", vis(enemy) == true)
  now = 4; walls.j_spine, walls.j_head = 4, 4; tagged[enemy] = true; before = rays
  check("line of sight: a tagged enemy shows through walls, no ray needed", vis(enemy) == true and rays == before)
  tagged[enemy] = nil; now = 5
  local odd = unit(901, "chaos_hound"); odd.nodes = { root_point = true }; walls.root_point = nil
  check("line of sight: an enemy without spine or head nodes is cast to its root", vis(odd) == true)
  enemy.alive = false; now = 6
  check("line of sight: a dead enemy has no outline", vis(enemy) == false)
  enemy.alive = true; now = 7; walls.j_spine = "error"; local w0 = #warnings
  check("line of sight: a failing ray hides the outline and warns once", vis(enemy) == false and #warnings == w0 + 1)
  now = 8; vis(enemy); check("line of sight: ...only once", #warnings == w0 + 1)
  walls.j_spine = nil; Managers.state.camera = { camera_position = function() return nil end }; now = 9
  check("line of sight: no camera (no local player view) hides it", vis(enemy) == false)
  Managers.state.extension.system, Managers.player, Managers.state.camera, Managers.world, Managers.time = saved.system, saved.player, saved.camera, saved.world, saved.time
  Vector3, Unit.has_node, Unit.node, Unit.world_position = saved.V, saved.has_node, saved.node, saved.pos
end
treated.extensions.buff_system._current_material_vector_effect={material_vector_name="stimmed_color",value={0.2,0.3,0.4}}
A.update(0.25);check("protected tint survives native buff colour",treated.colour[3]==1)
treated.colour={0,0,0};safe_hooks._start_material_vector_effect({_unit=treated})
check("native buff start reapplies protected tint",treated.colour[3]==1)
treated.colour={0,0,0};safe_hooks._stop_material_vector_effect({_unit=treated})
check("native buff stop reapplies protected tint",treated.colour[3]==1)

A.reset();combined.protect=false;A.apply(treated,combined,treated.breed);treated.extensions.buff_system._current_material_vector_effect.value={0.2,0.3,0.8};A.update(0.25)
check("unprotected tint yields to native buff",treated.colour[3]==0.8 and outlines[treated]==1)
A.reset();treated.extensions.buff_system._current_material_vector_effect.value={0.2,0.3,0.4}
local natural=Schema.copy(purple); natural.method="natural_stimm"
treated.breed="chaos_ogryn_executor"
BLACKBOARDS[treated]={stim={can_use_stim=false,currently_using_stim=false}}
treated.colour=nil
A.apply(treated,natural,treated.breed)
check("natural stim arms server permission before colouring", BLACKBOARDS[treated].stim.can_use_stim and not treated.colour)
treated.stimmed=true; A.update(0.25)
check("natural colour follows real keyword activation", treated.colour[3]==1)
A.reset()
check("unconsumed natural permission restored", not BLACKBOARDS[treated].stim.can_use_stim)
treated.stimmed=true; A.apply(treated,natural,treated.breed); treated.stimmed=false; A.update(0.25)
check("expired vanilla stim restores its current buff colour", treated.colour[3]==0.4)
A.reset()
control.stimmed=true; before=#writes; A.apply(control,natural,control.breed); A.update(0.25)
check("unsupported natural breed is not coloured despite keyword", #writes==before)
A.reset(); control.stimmed=false
BLACKBOARDS[treated]={}; before=#writes; A.apply(treated,natural,treated.breed); A.update(0.25)
check("missing natural stim component produces no material write", #writes==before)
A.reset(); BLACKBOARDS[treated]={stim={can_use_stim=false,currently_using_stim=false}}
local loadout=treated.extensions.visual_loadout_system
treated.extensions.visual_loadout_system=nil; before=#writes; A.apply(treated,purple,treated.breed)
check("incomplete visual loadout waits without native write", #writes==before)
treated.extensions.visual_loadout_system=loadout; A.update(0.25)
check("finished visual loadout receives the colour", treated.colour[3]==1)
local default=Schema.copy(purple); default.method="none"; A.apply(treated,default,treated.breed)
check("default method immediately removes selected tint", A.status().selected==0 and treated.colour[3]==0.4)
treated.extensions.outline_system.settings=shared_settings
A.apply(treated,outline,treated.breed); A.reset()
check("unchanged outline settings restore original shared map", treated.extensions.outline_system.settings==shared_settings)
outline.a=0; before=outlines[treated]; A.apply(treated,outline,treated.breed); A.update(0.25)
check("zero-strength outline adds no native stack", outlines[treated]==before)
A.reset()
BLACKBOARDS[treated].stim.can_use_stim=false; server=false; treated.stimmed=false
A.apply(treated,natural,treated.breed,true)
check("client never arms natural AI", not BLACKBOARDS[treated].stim.can_use_stim)
A.reset(); server=true
local unavailable=Schema.copy(purple); unavailable.method="surface"
A.apply(treated,unavailable,treated.breed)
check("prerequisite methods perform no native operation", A.status().selected==0)
local broken=unit(5); broken.fail=true
A.apply(broken,purple,broken.breed); A.apply(control,purple,control.breed); A.update(0.25)
check("native setter failure does not abort other units", control.colour[3]==1 and #warnings>0)
A.reset(); broken.alive=false
-- the skin effects (2026-10-05): the game's ailment look held at one moment, only once the engine has the effect's textures
do
  local saved_set, saved_world, saved_app, saved_World, saved_settings = Unit.set_vector3_for_materials, Unit.world, Application, World, package.loaded["scripts/settings/ailments/ailment_settings"]
  local mats, textures, perms, now, loaded = {}, {}, {}, 50, false
  Unit.set_vector3_for_materials = function(u, key, value) if u.skin_fail then error("material failure") end mats[#mats + 1] = { u = u, key = key, v = value } end
  Unit.set_texture_for_materials = function(u, slot, res) textures[#textures + 1] = { u, slot, res } end
  Unit.set_permutation_for_materials = function(u, name, on) perms[#perms + 1] = { u, name, on } end
  Unit.world = function() return "world" end
  World = { time = function() return now end }
  Application = { can_get_resource = function(kind, res) return loaded and kind == "texture" end }
  package.loaded["scripts/settings/ailments/ailment_settings"] = { effect_templates = { burning = { offset_time = 1.5, duration = 2, material_textures = { { slot = "burn_mask", resource = "tex/burn" } } } } }
  local burnt = Schema.copy(purple); burnt.method = "skin_burnt"; burnt.a = 128
  local skin_unit = unit(40)
  A.apply(skin_unit, burnt, skin_unit.breed)
  check("skin: nothing is written while the engine does not have the effect's textures (it waits)", #textures == 0 and #mats == 0 and A._skinned() == 0)
  loaded = true
  A.update(0.25)
  check("skin: once they are there the textures and the burn permutation are set and the look is held", #textures == 1 and textures[1][3] == "tex/burn" and perms[1][2] == "HAVE_BURN" and A._skinned() == 1 and mats[#mats].key == "offset_time_duration")
  local held = mats[#mats].v
  -- (2026-10-06, a performance pass) held ten times a second, the moment centred on the phase (half a step, 0.05 s, ahead)
  check("skin: A picks the moment: the start is put half the duration (A 128 of 255) before now, half a step ahead", math.abs(held[2] - (50 - 2 * 128 / 255 + 0.05)) < 1e-9 and held[1] == 1.5 and held[3] == 3)
  local writes = #mats
  now = 60; A.update(0.01)
  check("skin: not written again within a step (no engine write per enemy per frame)", #mats == writes)
  A.update(0.1)
  check("skin: every tenth of a second the moment is held (the start follows the clock)", math.abs(mats[#mats].v[2] - (60 - 2 * 128 / 255 + 0.05)) < 1e-9)
  local other = Schema.copy(purple); other.method = "skin_warp"
  A.apply(control, other, control.breed)
  check("skin: an effect the game has no template for leaves the enemy alone", A._skinned() == 1)
  skin_unit.alive = false; A.update(0.1)
  check("skin: a dead enemy is let go", A._skinned() == 0)
  skin_unit.alive = true
  A.apply(skin_unit, burnt, skin_unit.breed); A.update(0.01)
  skin_unit.skin_fail = true; A.update(0.1)
  check("skin: a failing write lets the enemy go and says so", A._skinned() == 0 and #warnings > 0)
  skin_unit.skin_fail = false
  A.reset()
  A.apply(skin_unit, burnt, skin_unit.breed); A.update(0.01)
  local before = #mats
  A.reset()
  check("skin: a reset ends the look (the effect is put out of time)", #mats == before + 1 and mats[#mats].v[2] < -1000 and A._skinned() == 0)
  Unit.set_vector3_for_materials, Unit.world, Application, World = saved_set, saved_world, saved_app, saved_World
  package.loaded["scripts/settings/ailments/ailment_settings"] = saved_settings
  Unit.set_texture_for_materials, Unit.set_permutation_for_materials = nil, nil
end
rpcs.rw_hello("new",2,"2.0.0",1); rpcs.rw_hello("old",2,"2.0.0")
sent={}; A.apply(treated,purple,treated.breed); A.send_all()
check("only capable peer gets appearance RPC", #sent==1 and sent[1][1]=="rw_appearance" and sent[1][2]=="new")
local packet=sent[1][3]; A.reset(); server=false
rpcs.rw_welcome("host",2,"2.0.0",1,packets[packet].epoch)
rpcs.rw_appearance("other_client",packet)
check("another client cannot send colours", #received==0)
rpcs.rw_appearance("host",packet); A.update(0.25)
check("authenticated colour packet applies", A.status().selected==1)
A.update(10); rpcs.rw_appearance("host",packet); A.update(0.25); A.update(10)
check("renewal keeps remote colour leased", A.status().selected==1)
A.update(15)
check("silent host lease restores visuals", A.status().selected==0)
P.clear_appearance_session(); received={}; rpcs.rw_appearance("host",packet)
check("mission reset rejects stale packet", #received==0)
packets.query={request=true}; local messages=#sent
rpcs.rw_appearance("other_client","query")
check("only host can request handshake refresh", #sent==messages)
rpcs.rw_appearance("host","query")
check("host refresh works before epoch is known", sent[#sent][1]=="rw_hello" and sent[#sent][5]==1)
local epoch="fresh"
rpcs.rw_welcome("host",2,"2.0.0",1,epoch)
packets.bad={epoch=epoch,entries={{1,"outline",0/0,0,0,0,"chaos_hound"},{1,"outline",255,256,0,0,"chaos_hound"},{1.5,"outline",255,0,0,0,"chaos_hound"},{1,"private_shader",255,0,0,0,"chaos_hound"},{1,"outline",255,0,0,0,"bad/breed"}}}
rpcs.rw_appearance("host","bad")
check("malformed fields and unavailable methods rejected", #received==0)
packets.many={epoch=epoch,entries={}}
for i=1,1000 do packets.many.entries[i]={i,"applied_stimm",255,128,0,255,"chaos_hound"} end
rpcs.rw_appearance("host","many")
check("one packet is capped at 200 units", #received==200)
A.reset(); A.receive({{id=9999,breed="chaos_hound",config=purple}}); A.update(1)
check("missing unit waits for spawn", A.status().pending==1)
local later=unit(9999); A.update(0.25)
check("unit arriving after packet gets its colour", later.colour[3]==1 and A.status().pending==0)
A.reset(); A.receive({{id=2,breed="chaos_ogryn_executor",config=purple}}); A.update(0.25)
check("reused ID of a different breed rejected", A.status().selected==0 and A.status().pending==0)
for i=1,1000 do A.receive({{id=10000+i,breed="chaos_hound",config=purple}}) end
check("pending queue capped at 600", A.status().pending==600)
A.update(20); check("missing IDs expire", A.status().pending==0)
server=true; A.apply(treated,combined,treated.breed); local previous=A.epoch(); A.reset(true)
local removal=packets[sent[#sent][3]].entries[1]
check("removal packets clear independent outline and protection",removal[2]=="none" and removal[8]==false and removal[9]==false)

check("reset advances epoch and sends removal", A.epoch()~=previous and packets[sent[#sent][3]].entries[1][2]=="none")
for i=20000,20999 do local u=unit(i); A.apply(u,purple,u.breed) end
check("host selected-unit registry capped at 600", A.status().selected==600)
local batches=0
A.init({schema=Schema,protocol={send_appearances=function() batches=batches+1; A.reset() end}})
A.send_all()
check("synchronous reset aborts remaining snapshot batches", batches==1 and A.status().selected==0)
A.retire(); A.apply(treated,purple,treated.breed); A.update(1)
check("retired runtime is inert", A.status().selected==0)
P.retire(); received={}; rpcs.rw_appearance("host",packet)
check("captured retired protocol handler is inert", #received==0)
return checks
'''

EDITOR = r'''
settings.wave_def_custom_20="Colour test\t2 crusher, 1 crusher<applied_stimm:FFFF0000>"
settings.del_custom_20=false
view:_open_detail("custom_20")
click_row(1,"hotspot_tune")
check("colour: entry button visible and enabled", view._widgets_by_name.btn_appearance.visible and not view._widgets_by_name.btn_appearance.content.hotspot.disabled)
click("btn_appearance")
check("colour: sliders and method are visible; rows hidden", view._screen=="appearance" and view._widgets_by_name.rw_colour_a.visible and not row(1).visible)
local outline_node=view._definitions.scenegraph_definition.rw_colour_outline
local protect_node=view._definitions.scenegraph_definition.rw_colour_protect
check("colour: toggle rows clear the explanation and Back button",outline_node.position[2]>=835 and protect_node.position[2]>=outline_node.position[2]+outline_node.size[2] and protect_node.position[2]+protect_node.size[2]<=970)
click("rw_colour_method")
check("colour: dropdown disables slider interaction", view._widgets_by_name.rw_colour_choice_1.visible and view._widgets_by_name.rw_colour_r.content.hotspot.disabled)
click("rw_colour_choice_3")
check("colour: method persists and dropdown closes", view._parts[1].appearance.method=="applied_stimm" and not view._colour_menu)
click("rw_colour_outline");click("rw_colour_protect")
check("colour: independent outline/protection toggles persist",view._parts[1].appearance.outline and view._parts[1].appearance.protect)
view:cb_back();view:cb_back();view:_open_detail("custom_20")
check("colour: reopening retains both flags and the second enemy row",#view._parts==2 and view._parts[1].appearance.outline and view._parts[1].appearance.protect and not view._parts[2].appearance.outline)
click_row(1,"hotspot_tune");click("btn_appearance")
click("rw_colour_outline");click("rw_colour_protect")
check("colour: both toggles can return to defaults",not view._parts[1].appearance.outline and not view._parts[1].appearance.protect)

click("rw_colour_r")
view._render_settings={inverse_scale=0.5}
local hold=true
view:_update_colour({get=function(_,name) if name=="cursor" then return {1370,0} elseif name=="left_hold" then return hold end end})
check("colour: scaled drag reaches midpoint", view._parts[1].appearance.r==128)
hold=false
view:_update_colour({get=function(_,name) if name=="cursor" then return {2130,0} elseif name=="left_hold" then return hold end end})
check("colour: release saves exact slider endpoint", view._parts[1].appearance.r==255 and view._colour_drag==nil)
click("rw_colour_b","number")
local popup=PopupOwner.Popup
check("colour: exact entry disables slider and dropdown", view._popup and view._widgets_by_name.rw_colour_b.content.hotspot.disabled and view._widgets_by_name.rw_colour_method.content.hotspot.disabled)
popup.set_text(view,"77"); popup.commit(view)
check("colour: number entry saved and interaction restored", view._parts[1].appearance.b==77 and not view._widgets_by_name.rw_colour_b.content.hotspot.disabled)
view:cb_back(); view:cb_back(); view:_open_detail("custom_20")
check("colour: reopening preserves values and untreated row", view._parts[1].appearance.b==77 and #view._parts==2 and view._parts[2].appearance.r==255)
view._part_index=2; view:_set_colour_channel("b",77)
check("colour: merging identical colours keeps the edited group selected", #view._parts==1 and view._parts[1].count==3 and view._part_index==1 and view._parts[1].appearance.b==77)
click_row(1,"hotspot_tune"); click("btn_appearance"); click("rw_colour_method"); click("rw_colour_choice_5")
check("colour: surface prerequisite is explicit", view._parts[1].appearance.method~="surface" and view._widgets_by_name.rw_colour_choice_5.content.hotspot.disabled and view._colour_menu)
view:cb_back()
check("colour: Back closes dropdown before leaving screen", view._screen=="appearance" and not view._colour_menu)
view:cb_back(); check("colour: Back returns to Custom", view._screen=="tune")
view:cb_back(); view:on_exit()
'''

ENTRY = r'''
enabled,server=true,true
settings.mult_normal,settings.mult_special=100,100
settings.max_alive,settings.max_per_wave=10,10
dofile(BASE .. "/GrandfathersTarot.lua"); mod.on_all_mods_loaded(); RW=mod.rw
local native_extension=ScriptUnit.has_extension
ScriptUnit.has_extension=function(unit,name)
  if name=="visual_loadout_system" then return {slot_items=function() return {} end,slot_unit=function() end} end
  return native_extension(unit,name)
end
Unit.set_vector3_for_materials=function(unit,name,value,recursive) assert(name=="stimmed_color" and recursive); unit.stim_colour=value end
RW.execute.init({positions=positions,bypass=RW.bypass,groups=RW.groups,tuning=RW.tuning,appearance=RW.appearance})
mod.on_game_state_changed("enter","GameplayStateRun"); mod._on_mission_objective_start()
local start=#spawned
RW.execute.start_wave({name="colour integration",parts=RW.groups.parse("1 hound<applied_stimm:FF8000FF>@1,1 hound"),rep_every=1,rep_for=3})
mod.update(0.2)
local colours,ordinary=0,0
for i=start+1,#spawned do if spawned[i].stim_colour then colours=colours+1 else ordinary=ordinary+1 end end
check("colour: real entry/executor colours exactly the selected spawn", colours==1 and ordinary==1 and RW.appearance.status().selected==1)
mod.update(1.1)
check("colour: repeating spawn inherits colour method and ARGB", #spawned==start+3 and spawned[#spawned].stim_colour.z==1 and RW.appearance.status().selected==2)
RW.director.stop(); mod.update(0.25)
check("colour: stop keeps living visual ownership", RW.appearance.status().selected==2)
mod.on_disabled()
check("colour: disable clears ownership and restores surviving spawns", RW.appearance.status().selected==0 and spawned[#spawned].stim_colour.z==0)
mod.on_enabled(false)
check("colour: re-enable does not replay stale colours", RW.appearance.status().selected==0)
mod.on_unload()
check("colour: unload retires entry-owned appearance instance", RW.appearance.status().selected==0)
'''

def original_harness(name):
    source = (ROOT / "tools" / name).read_text(encoding="utf-8")
    tree = ast.parse(source)
    return next(ast.literal_eval(n.value) for n in tree.body if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "harness" for t in n.targets))

def editor_harness():
    harness = original_harness("editor_test.py")
    harness = harness.replace('return table.concat(results, "\\n")', EDITOR + '\nreturn table.concat(results, "\\n")')
    # Use the existing dump serializer and real widgets for both colour layouts.
    return harness.replace('  dump_screen("mods")', '''  dump_screen("mods")
  view:cb_back(); click_row(1,"hotspot_tune"); click("btn_appearance")
  click("rw_colour_method"); click("rw_colour_choice_3")
  dump_screen("appearance")
  click("rw_colour_method"); dump_screen("appearance_dropdown"); view:cb_back()
  view:cb_back(); view:cb_back(); click_row(1,"hotspot_mods")''')

if __name__ == "__main__":
    from lua_test_runtime import with_version
    checks = LuaRuntime(unpack_returned_tuples=True).execute(with_version(RUNTIME), BASE)
    output = LuaRuntime(unpack_returned_tuples=True).execute(editor_harness(), ROOT.as_posix(), "", os.environ.get("UI_DUMP_DIR", "").replace("\\", "/"), os.environ.get("UI_REAL_TEXT", ""))
    failures = [line for line in output.splitlines() if line.startswith("FAIL")]
    for line in output.splitlines():
        if line.startswith("FAIL") or line.startswith("PASS colour:"):
            print(line)
    assert not failures, "Editor regression/colour checks failed"
    entry = original_harness("entry_test.py").replace('return table.concat(results, "\\n")', ENTRY + '\nreturn table.concat(results, "\\n")')
    entry_output = LuaRuntime(unpack_returned_tuples=True).execute(entry, ROOT.as_posix())
    for line in entry_output.splitlines():
        if line.startswith("FAIL") or line.startswith("PASS colour:"):
            print(line)
    assert not any(line.startswith("FAIL") for line in entry_output.splitlines()), "Entry/colour lifecycle checks failed"
    print(f"PASS: {checks} schema/runtime/protocol checks; editor and entry regression/colour checks passed")
