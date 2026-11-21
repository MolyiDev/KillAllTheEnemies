-- Temporary test-only Script in ServerScriptService. Never publish.
local R=game:GetService("ReplicatedStorage")
local RS=game:GetService("RunService")
local H=game:GetService("HttpService")
local Stats=game:GetService("Stats")
local STR=game:GetService("SharedTableRegistry")
local W=workspace
local ready=R:WaitForChild("BallarcBenchReady")
local ST=STR:GetSharedTable("BallarcBench");ST.workerUs=0;ST.workerJobs=0
local clientReady,smokeDone,checkDone=false,false,nil
ready.OnServerEvent:Connect(function(_,topic,payload)
 if topic=="ready" then clientReady=true elseif topic=="smoke-complete" then smokeDone=true
 elseif topic=="check-complete" then checkDone=payload
 elseif topic=="freeze" then require(R.Shared.Core.TimeCore).SetEnemiesPaused(payload) end
end)
task.wait(3)
local C=require(R.GlobalShared.ECS.Components)
local Tags=require(R.GlobalShared.ECS.Tags)
local EW=require(R.GlobalShared.ECS.Worlds.EnemyWorld)
local World=require(R.GlobalShared.ECS.Worlds.World)
local TC=require(R.Shared.Core.TimeCore)
local GC=require(R.Shared.Core.GeneratorCore)
local ES=require(game.ServerScriptService.Server.Services.EnemiesService)
local AOI=require(game.ServerScriptService.Server.Services.AOIService)
local GP=require(game.ServerScriptService.Server.Services.GameplayService)
local EP=require(R.Shared.Packers.EnemyPacker)
local Net=require(game.ServerScriptService.GlobalServer.Network)
local EIds=require(R.Types.Enums.Data.EEnemiesIds)
local characters=World:query(C.Model,C.InstanceId,Tags.Character,Tags.Alive):cached()
local enemies=EW:query(C.Position,C.InstanceId):cached()
shared.BallarcBench={commitMs=0,commitRows=0}
local metrics,hb,hbt,kbps={},{},{},{}
local capture=false
local function add(k,v) if capture then metrics[k]=(metrics[k] or 0)+v end end
local function log(v) v.label="__LABEL__";print("[BALLARC_BENCH_SERVER] "..H:JSONEncode(v)) end
local function percentile(a,p) local c=table.clone(a);table.sort(c);return c[math.max(1,math.ceil(#c*p))] or 0 end
local function mean(a) local s=0;for _,v in a do s+=v end;return if #a>0 then s/#a else 0 end
local originalFilter=EP.PackFiltered
EP.PackFiltered=function(...)
 local t=os.clock();local b=originalFilter(...);add("filterMs",(os.clock()-t)*1000)
 if b then
  add("packets",1);add("bytes",buffer.len(b))
  if EP.DELTA_POSITIONS then add("absRows",buffer.readu16(b,0));add("deltaRows",buffer.readu16(b,2))
  else add("absRows",buffer.readu16(b,0)) end
 end
 return b
end
local originalTick=AOI.Tick
AOI.Tick=function(...) local t=os.clock();originalTick(...);add("aoiTickMs",(os.clock()-t)*1000) end
local E=Net.Server.Enemies
for _,name in {"Added","Removed","Damaged","DamagedMultiple","Killed","KilledMultiple"} do
 local ev=E[name];local fire,fireList=ev.Fire,ev.FireList
 ev.Fire=function(...) add(name.."Events",1);return fire(...) end
 if fireList then ev.FireList=function(list,...) add(name.."Events",#list);return fireList(list,...) end end
end
RS.Heartbeat:Connect(function(dt) if capture then hb[#hb+1]=dt*1000;hbt[#hbt+1]=Stats.HeartbeatTime*1000 end end)
task.spawn(function() while true do task.wait(0.5) if capture then kbps[#kbps+1]=Stats.DataSendKbps end end end)
local began=os.clock()
local pe,pm
repeat
 for e,m in characters do pe,pm=e,m;break end
 if clientReady and pe and GP.IsGameRunning and next(GC.Grid.Grid) then break end
 if os.clock()-began>120 then log({phase="abort",clientReady=clientReady,running=GP.IsGameRunning,character=pe~=nil});return end
 task.wait(1)
until false
GP.StartGame=function() end
GP.IsGameRunning=false
TC.ResetAllPauses()
TC.SetWeaponsPaused(true)
World:add(pe,Tags.GodMode)
pm.PrimaryPart.Anchored=true
local origin=pm.PrimaryPart.Position
W:SetAttribute("BallarcBenchCameraX",origin.X)
W:SetAttribute("BallarcBenchCameraY",origin.Y)
W:SetAttribute("BallarcBenchCameraZ",origin.Z)
log({phase="ready",placeId=game.PlaceId,flags="__FLAGS__"})
local function distribution()
 local near,mid,far,total=0,0,0,0
 for _,p in enemies do
  local dx,dz=p.x-origin.X,p.z-origin.Z;local d=dx*dx+dz*dz
  total+=1;if d<=3600 then near+=1 elseif d<=22500 then mid+=1 else far+=1 end
 end
 return {near=near,mid=mid,far=far,total=total}
end
local N=tonumber("__COUNT__") or 8000
for _,kind in {"bees","charm","mixed"} do
 capture=false
 W:SetAttribute("BallarcBenchCapture",false)
 W:SetAttribute("BallarcBenchPhase",N.."-"..kind.."-setup")
 ES.ClearAll()
 task.wait(1)
 local rng=Random.new(42)
 for i=1,N do
  local a=rng:NextNumber()*math.pi*2
  local r0,r1=20,320
  local r=math.sqrt(rng:NextNumber()*(r1^2-r0^2)+r0^2)
  local x,z=origin.X+math.cos(a)*r,origin.Z+math.sin(a)*r
  local cell=GC.Grid:GetCellFromWorldPos(vector.create(x,0,z))
  local y=if cell then cell.Height+1 else origin.Y
  local isBee=kind=="bees" or kind=="mixed" and i%2==0
  local _,e=ES.Spawn(if isBee then EIds.Bee else EIds.Slime,vector.create(x,y,z),1e9,0)
  local charmed=kind=="charm" and i%2==0 or kind=="mixed" and i%4>=2
  -- Like the Charm pickup: the grabber is the inflictor, so charmed hits deal real damage.
  if charmed and e then EW:add(e,Tags.Charmed);EW:set(e,C.DebuffInflictor,pe) end
  if i%100==0 then RS.Heartbeat:Wait() end
 end
 W:SetAttribute("BallarcBenchSpin",kind=="spin")
 task.wait(6)
 TC.ResetAllPauses();TC.SetWeaponsPaused(true)
 metrics,hb,hbt,kbps={},{},{},{}
 shared.BallarcBench.commitMs=0;shared.BallarcBench.commitRows=0
 ST.workerUs=0;ST.workerJobs=0
 local startDist=distribution()
 W:SetAttribute("BallarcBenchPhase",N.."-"..kind)
 W:SetAttribute("BallarcBenchSpin",kind=="spin")
 W:SetAttribute("BallarcBenchCapture",true)
 capture=true
 local t=os.clock();task.wait(10);local seconds=os.clock()-t
 capture=false;W:SetAttribute("BallarcBenchCapture",false);W:SetAttribute("BallarcBenchSpin",false)
 metrics.commitMs=shared.BallarcBench.commitMs;metrics.commitRows=shared.BallarcBench.commitRows
 metrics.workerMs=(ST.workerUs or 0)/1000;metrics.workerJobs=ST.workerJobs or 0
 log({phase="result",name=N.."-"..kind,enemies=ES.GetCount(),seconds=seconds,
  heartbeatDtMedianMs=percentile(hb,0.5),heartbeatDtP95Ms=percentile(hb,0.95),
  heartbeatTimeMedianMs=percentile(hbt,0.5),heartbeatTimeP95Ms=percentile(hbt,0.95),heartbeatTimeMeanMs=mean(hbt),
  sendKbpsMean=mean(kbps),startDist=startDist,endDist=distribution(),metrics=metrics})
 -- Exactness: freeze, let tiered frozen sends land, then compare every in-view client position.
 TC.SetEnemiesPaused(true)
 task.wait(1.5)
 local rows={}
 -- Only ids this player was actually sent recently: the client's EnemyClock-based age is
 -- not meaningful here, and off-screen enemies legitimately keep their last position.
 local st;for _,v in AOI.playerAOIStates do st=v end
 for _,p,id in enemies do
  local sent=st and st.sentAt[id]
  if sent and TC.GameClock-sent<0.5 then rows[#rows+1]={id,p.x,p.y,p.z} end
 end
 local buf=buffer.create(#rows*14)
 for i,row in rows do local o=(i-1)*14;buffer.writeu16(buf,o,row[1]);buffer.writef32(buf,o+2,row[2]);buffer.writef32(buf,o+6,row[3]);buffer.writef32(buf,o+10,row[4]) end
 checkDone=nil
 ready:FireAllClients("check",buf)
 local t2=os.clock();while not checkDone and os.clock()-t2<10 do task.wait(0.1) end
 if checkDone and checkDone.badIds then
  local detail={}
  for _,id in checkDone.badIds do
   local e=require(R.GlobalShared.ECS.References.EnemyWorldRef):Search(id)
   local st;for _,v in AOI.playerAOIStates do st=v end
   local pos=e and EW:get(e,C.Position)
   detail[#detail+1]={id=id,flying=e and EW:has(e,Tags.Flying),charmed=e and EW:has(e,Tags.Charmed),stunned=e and EW:has(e,Tags.Stunned),telegraphing=e and EW:has(e,Tags.Telegraphing),
    known=st and st.knownEnemies[id],sentAge=st and st.sentAt[id] and TC.GameClock-st.sentAt[id],
    camDist=st and pos and math.sqrt((pos.x-st.camX)^2+(pos.y-st.camY)^2+(pos.z-st.camZ)^2),
    inFrustum=st and pos and (function() local vx,vy,vz=pos.x-st.camX,pos.y-st.camY,pos.z-st.camZ;local d=vx*vx+vy*vy+vz*vz;local dot=vx*st.lookX+vy*st.lookY+vz*st.lookZ;return dot>0 and dot*dot>st.thresholdSq*d end)()}
  end
  checkDone.serverDetail=detail
 end
 log({phase="check",name=N.."-"..kind,result=checkDone})
 TC.SetEnemiesPaused(false)
 task.wait(0.5)
end
W:SetAttribute("BallarcBenchPhase","done")
log({phase="done"})
if string.find("__LABEL__","smoke",1,true) then
 ES.ClearAll()
 for i=1,40 do
  local a=i/40*math.pi*2
  local r=if i%2==0 then 30 else 200
  ES.Spawn(if i%3==0 then EIds.Bee else EIds.Slime,vector.create(origin.X+math.cos(a)*r,origin.Y,origin.Z+math.sin(a)*r),1e9,0)
 end
 task.wait(1)
 ready:FireAllClients("smoke")
 local t=os.clock();while not smokeDone and os.clock()-t<40 do task.wait(0.25) end
 log({phase="smoke-done",clientResponded=smokeDone})
end
