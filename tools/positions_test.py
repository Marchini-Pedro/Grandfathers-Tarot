"""Exercise real spawn-position selection with bounded engine query fixtures."""
from pathlib import Path
import sys

from lua_test_runtime import LuaRuntime

root = Path(__file__).resolve().parents[1] / "scripts/mods/RealmsWaves"
lua = LuaRuntime(unpack_returned_tuples=True)
output = lua.execute(r'''
local ROOT = ...
math.randomseed(4321)
get_mod = function() return {} end
local V = {}
V.__add = function(a, b) return setmetatable({ x=a.x+b.x, y=a.y+b.y, z=a.z+b.z }, V) end
Vector3 = setmetatable({ distance = function(a, b)
  return math.sqrt((a.x-b.x)^2 + (a.y-b.y)^2 + (a.z-b.z)^2)
end }, { __call = function(_, x, y, z) return setmetatable({x=x,y=y,z=z}, V) end })
local function point(x, z) return Vector3(x, 0, z or 0) end
Vector3Box = function(p)
  local copy = Vector3(p.x, p.y, p.z)
  return { unbox=function() return Vector3(copy.x, copy.y, copy.z) end }
end
Unit = { world_position=function(unit) return unit.pos end }
local units, points, groups, ready, nav_world, spawn_points, count_mode, query_mode, group_mode
local queried, all_positions, scans, snaps, rays, snap_mode, ray_mode
local queries = {
  group_from_position = function(_, _, pos)
    scans=scans+1
    if group_mode == "none" then return nil end
    return math.floor(pos.x / 1000)*10+5
  end,
  occluded_positions_in_group = function(_, _, group, positions)
    assert(not queried[group], "a spawn group must be queried at most once")
    queried[group]=true; all_positions=positions
    if query_mode == "throw" then error("native occlusion failed") end
    if query_mode == "nil" then return nil end
    return points
  end,
}
local nav = {
  position_on_mesh=function(_, pos)
    snaps=snaps+1
    if snap_mode == "throw" then error("native snap failed") end
    if snap_mode == "nil" then return nil end
    return Vector3(pos.x,pos.y,pos.z+0.5)
  end,
  ray_can_go=function()
    rays=rays+1
    if ray_mode == "throw" then error("native ray failed") end
    return ray_mode ~= "blocked"
  end,
}
package.preload["scripts/managers/main_path/utilities/spawn_point_queries"] = function() return queries end
package.preload["scripts/utilities/nav_queries"] = function() return nav end
GwNavSpawnPoints = { get_count=function()
  if count_mode == "throw" then error("native group count failed") end
  if count_mode == "nil" then return nil end
  return groups
end }
local side = {get_side_from_name=function() return { valid_player_units=units } end}
local state = {
  extension={ system=function() return side end },
  nav_mesh={ nav_world=function() return nav_world end },
  main_path={ is_main_path_ready=function() return ready end,
              nav_spawn_points=function() return spawn_points end },
}
Managers={state=state}
local function reset()
  Managers.state=state
  units={ {pos=point(0)} }; points={point(30)}; groups=40; ready=true
  nav_world="world"; spawn_points="points"; count_mode=nil; query_mode=nil; group_mode=nil
  queried={}; all_positions=nil; scans=0; snaps=0; rays=0; snap_mode=nil; ray_mode=nil
end
reset()
local Pos = dofile(ROOT .. "/spawn/positions.lua")
local results={}
local function check(name, condition)
  results[#results+1]=(condition and "PASS " or "FAIL ")..name
end
local function reason(expected)
  local list, err=Pos.candidates(20,60)
  return list==nil and err==expected
end
Managers.state=nil
check("positions: client or absent mission state rejects hidden-position queries", reason("main path not ready") and #Pos.player_units()==0)
reset();ready=false
check("positions: main-path loading never falls back to a visible position", reason("main path not ready"))
reset();nav_world=nil
check("positions: missing nav world rejects selection", reason("no nav spawn points"))
reset();spawn_points=nil
check("positions: missing spawn-point handle rejects selection", reason("no nav spawn points"))
for _, mode in ipairs({"throw","nil","zero"}) do
  reset();count_mode=mode;if mode=="zero" then groups=0 end
  check("positions: group count "..mode.." fails safely", reason("no spawn groups"))
end
reset();units={}
check("positions: all players dead or disconnected rejects both paths", reason("no living players") and Pos.random_player_unit()==nil and select(2,Pos.test_candidates(20,60))=="no living players")
reset();state.extension=nil
check("positions: missing side system has no living targets", reason("no living players"))
state.extension={system=function() return side end}
reset();group_mode="none"
check("positions: players outside every spawn group retry later", reason("no hidden points near players"))
for _, mode in ipairs({"throw","nil","empty"}) do
  reset();query_mode=mode;if mode=="empty" then points={} end
  check("positions: occlusion "..mode.." never supplies visible candidates", reason("no hidden points near players"))
  if mode=="throw" then check("positions: native occlusion error remains diagnostic", Pos.last_error:find("native occlusion failed",1,true)~=nil) end
end
reset();points={point(20),point(60),point(61),point(30,12)}
local list=Pos.candidates(20,60)
local valid=#list>0
for _, box in ipairs(list) do
  local p=box:unbox(); valid=valid and (p.x==20 or p.x==60) and p.z==0
end
check("positions: distance boundaries are inclusive and vertical limit is strict", valid and Pos.last_stage==1)
points[1].x=999
check("positions: accepted candidates own boxed coordinates", list[1]:unbox().x==20)
check("positions: pick unwraps a candidate and tolerates empty input", Pos.pick(list)~=nil and Pos.pick(nil)==nil and Pos.pick({})==nil)
reset();units={{pos=point(0)},{pos=point(30)}};points={point(31)}
check("positions: distance is measured to the nearest of ALL living players", reason("hidden points exist but none within distance limits") and #all_positions==2)
reset();points={point(15)};list=Pos.candidates(20,60)
check("positions: second stage widens hidden-point distance", list~=nil and Pos.last_stage==2 and list[1]:unbox().x==15)
reset();points={point(10)};list=Pos.candidates(20,60)
check("positions: third stage relaxes hidden-point distance", list~=nil and Pos.last_stage==3 and list[1]:unbox().x==10)
reset();points={point(1),point(200),point(30,13)}
check("positions: no acceptable hidden point returns a retry reason", reason("hidden points exist but none within distance limits"))
reset();units={{pos=point(0)},{pos=point(1000)},{pos=point(2000)},{pos=point(3000)}}
list=Pos.candidates(20,60)
local group_count=0;for _ in pairs(queried) do group_count=group_count+1 end
check("positions: scan at most three players but occlusion sees all four", scans==3 and #all_positions==4 and group_count<=27)
check("positions: random target belongs to the living side", (function() local unit=Pos.random_player_unit();for _,u in ipairs(units) do if u==unit then return true end end end)())
reset();points={};for i=1,80 do points[i]=point(30) end
list=Pos.candidates(20,60);group_count=0;for _ in pairs(queried) do group_count=group_count+1 end
check("positions: raw query stops at 160 accumulated points and returns at most 24", group_count==2 and #list==24)
reset();nav_world=nil
check("positions: explicit test ring needs nav mesh", select(2,Pos.test_candidates(20,60))=="no nav mesh on this level")
reset();list=Pos.test_candidates(20,60)
valid=#list==16
for _,box in ipairs(list) do local p=box:unbox();local d=math.sqrt(p.x*p.x+p.y*p.y);valid=valid and d>=20 and d<=60 and p.z==0.5 end
check("positions: explicit test ring is bounded, snapped and reachable", valid and snaps==16 and rays==16)
for _, mode in ipairs({"throw","nil"}) do
  reset();snap_mode=mode
  check("positions: test ring snap "..mode.." exhausts only 80 attempts", select(2,Pos.test_candidates(20,60))=="no walkable ground within reach of the player" and snaps==80 and rays==0)
end
for _, mode in ipairs({"throw","blocked"}) do
  reset();ray_mode=mode
  check("positions: test ring ray "..mode.." has no unreachable candidates", Pos.test_candidates(20,60)==nil and snaps==80 and rays==80)
end
reset();local origin=point(50)
check("positions: tiny spread is an identity", Pos.spread(origin,0.2)==origin and snaps==0)
for _, mode in ipairs({"throw","nil"}) do
  reset();snap_mode=mode
  check("positions: large spread snap "..mode.." preserves original point after ten attempts", Pos.spread(origin,25)==origin and snaps==10)
end
for _, mode in ipairs({"throw","blocked"}) do
  reset();ray_mode=mode
  check("positions: small spread ray "..mode.." preserves original point after five attempts", Pos.spread(origin,5)==origin and snaps==5 and rays==5)
end
return table.concat(results,"\n")
''', root.as_posix())
print(output)
sys.exit(1 if any(line.startswith("FAIL ") for line in output.splitlines()) else 0)
