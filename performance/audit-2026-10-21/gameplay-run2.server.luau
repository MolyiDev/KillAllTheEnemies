-- Temporary instrumentation and controlled enemy-load scene in the actual Survivors game.
local R=game:GetService("ReplicatedStorage")
local RS=game:GetService("RunService")
local H=game:GetService("HttpService")
local W=workspace
task.wait(3)
local C=require(R.GlobalShared.ECS.Components)
local Tags=require(R.GlobalShared.ECS.Tags)
local EW=require(R.GlobalShared.ECS.Worlds.EnemyWorld)
local World=require(R.GlobalShared.ECS.Worlds.World)
local EC=require(R.Shared.Core.EnemiesCore)
local TC=require(R.Shared.Core.TimeCore)
local GC=require(R.Shared.Core.GeneratorCore)
local ES=require(game.ServerScriptService.Server.Services.EnemiesService)
local GP=require(game.ServerScriptService.Server.Services.GameplayService)
local AOI=require(game.ServerScriptService.Server.Services.AOIService)
local S=require(R.GlobalShared.Utils.SpatialHash)
local EP=require(R.Shared.Packers.EnemyPacker)
local EIds=require(R.Types.Enums.Data.EEnemiesIds)
local direct=require(script.GroundDirect)
local groundQuery=EW:query(C.Position,C.Velocity,C.Radius,C.Force,C.MovementSpeed,C.ClimbGrace,C.ExplosionRadius):without(Tags.Flying,Tags.Telegraphing,Tags.Stunned,Tags.Charmed):cached()
local charQuery=World:query(C.Model,C.InstanceId,Tags.Character,Tags.Alive):cached()
local stats={}
local capture=false
local function add(key,amount) if capture then stats[key]=(stats[key] or 0)+amount end end
local function log(data) print("[BALLARC_GAME_SERVER] "..H:JSONEncode(data)) end
local function count(q) local n=0;for _ in q do n+=1 end;return n end
local oldRecords,oldBuckets,oldFiltered=S.PackRecords,S.PackBuckets,EP.PackFiltered
local cachedRecords,cachedBuckets
S.PackRecords=function(...)
	if W:GetAttribute("BallarcAuditSerial") and cachedRecords then return cachedRecords end
	local t=os.clock();local b=oldRecords(...);add("packMs",(os.clock()-t)*1000);add("packRecordCalls",1);cachedRecords=b;return b
end
S.PackBuckets=function(...)
	if W:GetAttribute("BallarcAuditSerial") and cachedBuckets then return cachedBuckets end
	local t=os.clock();local b=oldBuckets(...);add("packMs",(os.clock()-t)*1000);cachedBuckets=b;return b
end
EP.PackFiltered=function(...)
	local t=os.clock();local b=oldFiltered(...);add("filterMs",(os.clock()-t)*1000)
	if b then add("positionBytes",buffer.len(b));add("positionPackets",1);add("positionRecords",buffer.readu16(b,0)) end
	return b
end
local mainActor=game.ServerScriptService.Server.Actors.EnemiesActor
local hb={}
RS.Heartbeat:Connect(function(dt) if capture then hb[#hb+1]=dt*1000 end end)
local t0=os.clock()
while not GP.IsGameRunning or count(charQuery)==0 or next(GC.Grid.Grid)==nil do
	log({phase="boot",waited=os.clock()-t0,placeId=game.PlaceId,running=GP.IsGameRunning,characters=count(charQuery),gridPopulated=next(GC.Grid.Grid)~=nil,paused=TC.IsPaused})
	if os.clock()-t0>90 then log({phase="aborted",reason="normal game startup did not finish"});return end
	task.wait(5)
end
log({phase="ready",placeId=game.PlaceId,placeVersion=game.PlaceVersion,enemies=ES.GetCount(),characters=count(charQuery),positionTransport=R.Events.UpdateEnemies.ClassName})
-- Hold progression/spawning and weapons while measuring the real movement/render pipeline.
GP.StartGame=function() end
GP.IsGameRunning=false
TC.ResetAllPauses()
TC.SetWeaponsPaused(true)
local playerEntity,playerModel,playerId
for e,m,id in charQuery do playerEntity,playerModel,playerId=e,m,id;break end
World:add(playerEntity,Tags.GodMode)
playerModel.PrimaryPart.Anchored=true
local origin=playerModel.PrimaryPart.Position
W:SetAttribute("BallarcAuditCameraX",origin.X)
W:SetAttribute("BallarcAuditCameraY",origin.Y)
W:SetAttribute("BallarcAuditCameraZ",origin.Z)
local localActor={SendMessage=function(_,topic,a,b)
	if topic=="Damage" then return end -- GodMode denies damage in baseline too; no thorns loadout.
	if topic=="Telegraph" then ES.StartTelegraph(a) end
end}
local accumulator=0
RS.Heartbeat:Connect(function(dt)
	if not W:GetAttribute("BallarcAuditSerial") or TC.IsPaused then return end
	accumulator+=dt
	if accumulator<TC.FIXED_DT then return end
	accumulator=0
	local targets={[playerId]=vector.create(origin.X,origin.Y,origin.Z)}
	local t=os.clock()
	local out=direct(localActor,targets,{}, {},EC.EnemiesSpatialHash.FineBuckets,EC.EnemiesSpatialHash.Records,TC.FIXED_DT,GC.Grid,groundQuery)
	add("directComputeMs",(os.clock()-t)*1000);add("directTicks",1)
	local ids,positions={},{}
	t=os.clock()
	for entity,info in out do
		if not EW:contains(entity) then continue end
		EW:set(entity,C.Position,info.pos);EW:set(entity,C.Velocity,info.velocity);EW:set(entity,C.ClimbGrace,info.climbGrace)
		EC.EnemiesSpatialHash:Update(entity,info.pos)
		ids[#ids+1]=EW:get(entity,C.InstanceId);positions[#positions+1]=info.pos
	end
	add("directCommitMs",(os.clock()-t)*1000)
	for player,state in AOI.playerAOIStates do
		local b=EP.PackFiltered(ids,positions,state.camX,state.camY,state.camZ,state.lookX,state.lookY,state.lookZ,state.thresholdSq,state.renderDistanceSq)
		if b then R.Events.UpdateEnemies:FireClient(player,b) end
	end
end)
local function quantile(a,f) table.sort(a);return a[math.max(1,math.ceil(#a*f))] end
local function run(n,mode)
 GP.IsGameRunning=false
 W:SetAttribute("BallarcAuditReuse",mode=="reuse")
	capture=false
	W:SetAttribute("BallarcAuditCapture",false)
	W:SetAttribute("BallarcAuditSerial",false)
	W:SetAttribute("BallarcAuditPhase",`{n}-{mode}-setup`)
	ES.ClearAll()
	local width=math.ceil(math.sqrt(n))
	for i=1,n do
		local x=origin.X+(((i-1)%width)-(width-1)/2)*3
		local z=origin.Z+(math.floor((i-1)/width)-(width-1)/2)*3
		local cell=GC.Grid:GetCellFromWorldPos(vector.create(x,0,z))
		local y=if cell then cell.Height+1 else origin.Y
		ES.Spawn(EIds.Slime,vector.create(x,y,z),1e9,0)
		if i%50==0 then RS.Heartbeat:Wait() end
	end
	W:SetAttribute("BallarcAuditSerial",mode=="direct")
	W:SetAttribute("BallarcAuditPhase",`{n}-{mode}-settle`)
	task.wait(8)
	stats={};hb={}
	W:SetAttribute("BallarcAuditPhase",`{n}-{mode}`)
	W:SetAttribute("BallarcAuditCapture",true)
	capture=true
	local began=os.clock()
	task.wait(7)
	local seconds=os.clock()-began
	capture=false
	W:SetAttribute("BallarcAuditCapture",false)
	log({phase="result",name=`{n}-{mode}`,seconds=seconds,enemies=ES.GetCount(),matchingGround=count(groundQuery),paused=TC.IsPaused,enemyTimeScale=TC.EnemyTimeScale,heartbeatMedianMs=quantile(hb,0.5),heartbeatP95Ms=quantile(hb,0.95),heartbeatP99Ms=quantile(hb,0.99),metrics=stats})
	task.wait(1)
end
for _,n in {500,1500,3000} do run(n,"parallel");run(n,"reuse") end
W:SetAttribute("BallarcAuditSerial",false)
W:SetAttribute("BallarcAuditPhase","done")
log({phase="done"})

