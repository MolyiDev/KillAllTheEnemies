-- Temporary test-only Script in ServerScriptService. Never publish.
local R=game:GetService("ReplicatedStorage")
local RS=game:GetService("RunService")
local H=game:GetService("HttpService")
local W=workspace
local ready=R:WaitForChild("BallarcFinalBenchReady")
local clientReady=false
local smokeDone=false
local effectsDone=false
ready.OnServerEvent:Connect(function(_,topic)
 if topic=="ready" then clientReady=true elseif topic=="smoke-complete" then smokeDone=true
 elseif topic=="pending-effects-complete" then effectsDone=true end
end)
task.wait(3)
local C=require(R.GlobalShared.ECS.Components)
local Tags=require(R.GlobalShared.ECS.Tags)
local EW=require(R.GlobalShared.ECS.Worlds.EnemyWorld)
local World=require(R.GlobalShared.ECS.Worlds.World)
local TC=require(R.Shared.Core.TimeCore)
local GC=require(R.Shared.Core.GeneratorCore)
local ES=require(game.ServerScriptService.Server.Services.EnemiesService)
local GP=require(game.ServerScriptService.Server.Services.GameplayService)
local S=require(R.GlobalShared.Utils.SpatialHash)
local EP=require(R.Shared.Packers.EnemyPacker)
local EIds=require(R.Types.Enums.Data.EEnemiesIds)
local characters=World:query(C.Model,C.InstanceId,Tags.Character,Tags.Alive):cached()
local metrics,hb={},{}
local capture=false
local function add(k,v) if capture then metrics[k]=(metrics[k] or 0)+v end end
local function log(v) v.label="__LABEL__";print("[BALLARC_FINAL_SERVER] "..H:JSONEncode(v)) end
local function percentile(a,p) table.sort(a);return a[math.max(1,math.ceil(#a*p))] or 0 end
local originalRecords,originalBuckets,originalFilter=S.PackRecords,S.PackBuckets,EP.PackFiltered
S.PackRecords=function(...)
 local t=os.clock();local b=originalRecords(...);add("packMs",(os.clock()-t)*1000);add("packCalls",1);return b
end
S.PackBuckets=function(...)
 local t=os.clock();local b=originalBuckets(...);add("packMs",(os.clock()-t)*1000);return b
end
EP.PackFiltered=function(...)
 local t=os.clock();local b=originalFilter(...);add("filterMs",(os.clock()-t)*1000)
 if b then add("packets",1);add("bytes",buffer.len(b));add("rows",buffer.readu16(b,0)) end
 return b
end
RS.Heartbeat:Connect(function(dt) if capture then hb[#hb+1]=dt*1000 end end)
local began=os.clock()
local pe,pm
repeat
 for e,m in characters do pe,pm=e,m;break end
 if clientReady and pe and GP.IsGameRunning and next(GC.Grid.Grid) then break end
 if os.clock()-began>100 then log({phase="abort",clientReady=clientReady,running=GP.IsGameRunning,character=pe~=nil});return end
 task.wait(1)
until false
GP.StartGame=function() end
GP.IsGameRunning=false
TC.ResetAllPauses()
TC.SetWeaponsPaused(true)
World:add(pe,Tags.GodMode)
pm.PrimaryPart.Anchored=true
local origin=pm.PrimaryPart.Position
W:SetAttribute("BallarcFinalCameraX",origin.X)
W:SetAttribute("BallarcFinalCameraY",origin.Y)
W:SetAttribute("BallarcFinalCameraZ",origin.Z)
log({phase="ready",placeId=game.PlaceId,version=game.PlaceVersion})
local scenarios=if string.find("__LABEL__","final",1,true)
 then {{1500,"ground"},{3000,"ground"},{1500,"mixed"},{3000,"mixed"}}
 else {{1500,"ground"},{3000,"ground"},{3000,"ground-repeat"},{1500,"mixed"},{3000,"mixed"},{3000,"ground-after-mixed"}}
for _,spec in scenarios do
 local n,kind=spec[1],spec[2]
 capture=false
 W:SetAttribute("BallarcFinalCapture",false)
 W:SetAttribute("BallarcFinalPhase",n.."-"..kind.."-setup")
 ES.ClearAll()
 local width=math.ceil(math.sqrt(n))
 for i=1,n do
  local x=origin.X+((i-1)%width-(width-1)/2)*3
  local z=origin.Z+(math.floor((i-1)/width)-(width-1)/2)*3
  local cell=GC.Grid:GetCellFromWorldPos(vector.create(x,0,z))
  local y=if cell then cell.Height+1 else origin.Y
  local _,e=ES.Spawn(if kind=="mixed" and i%2==0 then EIds.Bee else EIds.Slime,vector.create(x,y,z),1e9,0)
  if kind=="mixed" then
   if i%4>=2 then EW:add(e,Tags.Charmed) end
   if math.floor(i/4)%2==1 then EW:set(e,C.LastHitEffectTime,0) end
   if math.floor(i/8)%2==1 then EW:set(e,C.Yaw,0) end
   if math.floor(i/16)%2==1 then EW:set(e,C.Pitch,0) end
  end
  if i%50==0 then RS.Heartbeat:Wait() end
 end
 task.wait(6)
 TC.ResetAllPauses();TC.SetWeaponsPaused(true)
 metrics,hb={},{}
 W:SetAttribute("BallarcFinalPhase",n.."-"..kind)
 W:SetAttribute("BallarcFinalCapture",true)
 capture=true
 local t=os.clock();task.wait(10);local seconds=os.clock()-t
 capture=false;W:SetAttribute("BallarcFinalCapture",false)
 log({phase="result",name=n.."-"..kind,enemies=ES.GetCount(),seconds=seconds,paused=TC.IsPaused,enemyScale=TC.EnemyTimeScale,heartbeatMedianMs=percentile(hb,0.5),heartbeatP95Ms=percentile(hb,0.95),metrics=metrics})
 task.wait(1)
end
W:SetAttribute("BallarcFinalPhase","done")
log({phase="done"})
if string.find("__LABEL__","after",1,true) then
 ES.ClearAll()
 local entities={}
 for i=1,12 do
  local _,e=ES.Spawn(if i%2==0 then EIds.Bee else EIds.Slime,vector.create(origin.X+(i-6)*3,origin.Y,origin.Z),1e9,0)
  if i%4>=2 then EW:add(e,Tags.Charmed) end
  entities[#entities+1]=e
 end
 task.wait(1)
 TC.SetEnemiesPaused(true)
 local positions={};for _,e in entities do positions[e]=EW:get(e,C.Position) end
 task.wait(0.35)
 local frozen=true;for _,e in entities do if EW:get(e,C.Position)~=positions[e] then frozen=false end end
 TC.SetEnemiesPaused(false)
 local e=entities[1]
 local revision=EW:get(e,C.MovementRevision)
 local p=EW:get(e,C.Position)+vector.create(3,0,0)
 ES.Recycle(e,p,1e9,0)
 EW:add(e,Tags.Stunned)
 local packer=require(R.Shared.Packers.EntityPacker)
 local stale=packer.PackServer({[e]={pos=p+vector.create(1,0,0),velocity=vector.zero,climbGrace=0}})
 game.ServerScriptService.Server.Actors.EnemiesActor:SendMessage("Receive",stale,-1,1)
 task.wait(0.25)
 log({phase="smoke",serverFreeze=frozen,recycleRevisionChanged=EW:get(e,C.MovementRevision)~=revision,recycleAndStaleReplyPositionHeld=EW:get(e,C.Position)==p})
 EW:remove(e,Tags.Stunned)
 ready:FireAllClients("smoke")
 local t=os.clock();while not smokeDone and os.clock()-t<15 do task.wait(0.25) end
 ES.ClearAll();log({phase="smoke-done",clientResponded=smokeDone})
 local ids={}
 for i=1,12 do
  local id=ES.Spawn(EIds.Slime,vector.create(origin.X+(i-6)*3,origin.Y,origin.Z),1e9,0)
  ids[#ids+1]=id
 end
 task.wait(0.5)
 local network=require(game.ServerScriptService.GlobalServer.Network)
 for _,player in game:GetService("Players"):GetPlayers() do network.Server.Enemies.KilledMultiple.Fire(player,0,ids,1,0) end
 ES.ClearAll();task.wait(0.05);ready:FireAllClients("restart-pending-effects")
 local t=os.clock();while not effectsDone and os.clock()-t<5 do task.wait(0.2) end
 log({phase="effects-done",clientResponded=effectsDone})
end
