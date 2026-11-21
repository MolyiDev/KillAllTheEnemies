-- Side-by-side baseline/native copies of the actual packers. Never publish.
local R=game:GetService("ReplicatedStorage")
local H=game:GetService("HttpService")
task.wait(6)
local GP=require(game.ServerScriptService.Server.Services.GameplayService)
GP.IsGameRunning=false;GP.StartGame=function() end
require(R.Shared.Core.TimeCore).SetWeaponsPaused(true)
local eb=require(script.EntityBase)
local en=require(script.EntityNative)
local pb=require(script.EnemyBase)
local pn=require(script.EnemyNative)
local function same(a,b) assert(buffer.tostring(a)==buffer.tostring(b),"native packet bytes changed") end
for _,n in {50,1500,3000} do
 local ids,positions,entities={},{},{}
 for i=1,n do
  local p=vector.create((i%55)*2-55,i%7,math.floor(i/55)*2-55)
  ids[i]=i;positions[i]=p;entities[i]={pos=p,velocity=vector.create(i%3,0,i%5),climbGrace=0.15}
 end
 local packed=eb.PackServer(entities)
 same(packed,en.PackServer(entities))
 local ppacked=pb.Pack(ids,positions);same(ppacked,pn.Pack(ids,positions))
 local count=if n==50 then 1000 else 100
 local beforeMap,afterMap={},{}
 local beforePos,afterPos={},{}
 local beforeTimes,afterTimes={},{}
 local touched={}
 local skip={}
 local function run(round,kind,fn)
  fn() -- warm exact buffers/maps and code before measuring
  local t=os.clock();for _=1,count do fn() end
  print("[BALLARC_PACKING_KERNEL] "..H:JSONEncode({n=n,round=round,kind=kind,msPerCall=(os.clock()-t)*1000/count,iterations=count}))
 end
 for round=1,4 do
  local variants=if round%2==1 then {"before","native"} else {"native","before"}
  for _,variant in variants do
   local e=if variant=="before" then eb else en
   local p=if variant=="before" then pb else pn
   local map=if variant=="before" then beforeMap else afterMap
   local pos=if variant=="before" then beforePos else afterPos
   local stamps=if variant=="before" then beforeTimes else afterTimes
   run(round,variant.."-entity-pack",function() e.PackServer(entities) end)
   run(round,variant.."-entity-unpack",function() table.clear(touched);e.UnpackServerInto(packed,map,touched) end)
   run(round,variant.."-position-filter",function() p.PackFiltered(ids,positions,0,210,0,0,-1,0,0.3,1e6) end)
   run(round,variant.."-position-unpack",function() p.UnpackInto(ppacked,pos,skip,stamps,0) end)
  end
 end
 same(pb.PackFiltered(ids,positions,0,210,0,0,-1,0,0.3,1e6),pn.PackFiltered(ids,positions,0,210,0,0,-1,0,0.3,1e6))
 for id,info in beforeMap do
  assert(info.pos==afterMap[id].pos and info.velocity==afterMap[id].velocity and info.climbGrace==afterMap[id].climbGrace)
 end
 for id,pos in beforePos do assert(pos==afterPos[id] and beforeTimes[id]==afterTimes[id]) end
end
print("[BALLARC_PACKING_KERNEL] done: byte equality and decoded equality passed")
