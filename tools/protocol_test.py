"""Check protocol failure boundaries that normal network stubs cannot exercise."""
from pathlib import Path
import sys

from lua_test_runtime import LuaRuntime

root = Path(__file__).resolve().parents[1] / "scripts/mods/GrandfathersTarot"
lua = LuaRuntime(unpack_returned_tuples=True)
output = lua.execute(r'''
local ROOT=...
local warnings,errors,sends,registered,received={},{},{},{},{}
local mod={ get=function() return true end,
  io_dofile=function(_,path) return dofile(ROOT.."/"..path:match("GrandfathersTarot/scripts/mods/GrandfathersTarot/(.*)")..".lua") end,
  warning=function(_,...) warnings[#warnings+1]={...} end,
  error=function(_,...) errors[#errors+1]={...} end }
local realms
get_mod=function(name) if name=="Realms" then return realms end return mod end
Managers={connection={host=function() return "HOST" end}}
local P=dofile(ROOT.."/core/protocol.lua")
local results={}
local function check(name,condition) results[#results+1]=(condition and "PASS " or "FAIL ")..name end
P.init()
check("protocol failures: missing Realms keeps solo mode and reports unavailability", not P.is_available() and #warnings==1 and not P.send_hello())
realms={network_register=function(_,name,fn) registered[name]=fn;return false,"registration rejected" end}
P.init()
check("protocol failures: all seven RPC registration errors are reported", #errors==7 and not P.is_available())
realms.network_is_available=function() error("native availability failed") end
check("protocol failures: native availability exception fails safely", not P.is_available())
realms.network_is_available=function() return 1 end
check("protocol failures: nonboolean availability is rejected", not P.is_available())
realms.network_is_available=function() return true end
realms.network_register=function(_,name,fn) registered[name]=fn;return true end
realms.network_send=function(owner,name,recipient,...)
  sends[#sends+1]={owner=owner,name=name,recipient=recipient,args={...}}
  return true
end
P.init({on_hello=function(sender,proto,version) received.hello={sender,proto,version} end,
  on_welcome=function(sender,proto,version,ok) received.welcome={sender,proto,version,ok} end,
  on_vote=function(sender,id,option) received.vote={sender,id,option} end,
  on_state=function() received.state=true end})
registered.rw_hello("peer","2","2.0.0")
registered.rw_welcome("host","2","2.0.0","1")
registered.rw_vote("peer","7","3")
check("protocol inputs: handshake/vote numeric strings reach handlers as numbers", received.hello[2]==2 and received.welcome[4]==true and received.vote[2]==7 and received.vote[3]==3)
received={}
registered.rw_hello(nil,2,"2.0.0");registered.rw_hello("peer","x","2.0.0");registered.rw_hello("peer",2,false)
registered.rw_welcome("host",2,false,1);registered.rw_welcome("host","x","2.0.0",1);registered.rw_welcome("host",2,"2.0.0","x")
registered.rw_vote("",1,2);registered.rw_vote("peer","x",2);registered.rw_vote("peer",1,"x")
check("protocol inputs: malformed handshakes/votes do not invoke handlers", next(received)==nil)
cjson={encode=function() return "payload" end,decode=function() return {} end}
Managers.connection.host=function() error("host disconnected") end
registered.rw_state("host","payload")
check("protocol inputs: host lookup exception cannot authorize a sender", received.state==nil)
Managers.connection.host=function() return "HOST" end
registered.rw_state("host","payload")
check("protocol inputs: host identity is case insensitive", received.state==true)
for _,mode in ipairs({"missing","throw","scalar"}) do
  received.state=nil
  if mode=="missing" then cjson=nil
  elseif mode=="throw" then cjson={decode=function() error("bad JSON") end}
  else cjson={decode=function() return 42 end} end
  registered.rw_state("host","payload")
  check("protocol failures: decode "..mode.." drops state without invoking handlers", received.state==nil)
end
for _,mode in ipairs({"missing","throw","scalar"}) do
  if mode=="missing" then cjson=nil
  elseif mode=="throw" then cjson={encode=function() error("encode failed") end}
  else cjson={encode=function() return false end} end
  local before=#sends
  check("protocol failures: encode "..mode.." refuses state and scale sends", not P.send_state({}) and not P.send_scales({{1,100}}) and #sends==before)
end
cjson={encode=function() return "payload" end}
P.send_state({});P.send_state({},"specific")
P.send_welcome("specific",true);P.send_welcome("specific",false);P.send_vote(7,3)
check("protocol sends: state defaults to others and explicit recipient is preserved", sends[1].recipient=="others" and sends[2].recipient=="specific" and sends[2].owner==mod and sends[2].args[1]=="payload")
check("protocol sends: welcome includes protocol/version and boolean acceptance", sends[3].args[1]==2 and sends[3].args[2]=="2.0.0" and sends[3].args[3]==1 and sends[4].args[3]==0)
check("protocol sends: vote routes ballot and option to the host", sends[5].name=="rw_vote" and sends[5].recipient=="host" and sends[5].args[1]==7 and sends[5].args[2]==3)
do
  local saved_encode = cjson.encode
  cjson.encode = function(text) return '"' .. text:gsub('["\\]', 'XX') .. '"' end
  local plain = string.rep("a", 90000)
  local quoted = string.rep('"', 50000)
  local before = #sends
  check("protocol: a plain deck near the raw limit fits the Realms envelope", P.send_waves(plain) == true)
  check("protocol: an escaped deck over the transport limit is refused", P.send_waves(quoted) == false and #sends == before + 1)
  cjson.encode = function() error("JSON unavailable") end
  check("protocol: waves encoding failure does not send a packet", P.send_waves("RW1|x") == false and #sends == before + 1)
  cjson.encode = saved_encode
end
realms.network_send=function() return false,"channel rejected" end
local sent,reason=P.send_hello()
check("protocol failures: direct rejection exposes its reason and debug diagnostic", sent==false and reason=="channel rejected" and #warnings==2)
P.init()
cjson={decode=function() return {{1,100}} end}
local safe=pcall(function()
  registered.rw_hello("peer",2,"2.0.0");registered.rw_welcome("host",2,"2.0.0",1)
  registered.rw_vote("peer",1,2);registered.rw_state("host","payload")
  registered.rw_waves("peer","preset");registered.rw_scale("host","payload")
end)
check("protocol inputs: absent optional handlers safely ignore valid RPCs", safe)
return table.concat(results,"\n")
''', root.as_posix())
print(output)
sys.exit(1 if any(line.startswith("FAIL ") for line in output.splitlines()) else 0)
