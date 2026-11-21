-- Same-count repeat / kill / idle-residency diagnosis. Test only.
local R=game:GetService("ReplicatedStorage")
local RS=game:GetService("RunService")
local H=game:GetService("HttpService")
local W=workspace
local ready=R:WaitForChild("BallarcFinalBenchReady")
local clientReady=false
ready.OnServerEvent:Connect(function(_,topic) if topic=="ready" then clientReady=true end end)
task.wait(3)
local C=require(R.GlobalShared.ECS.Components)
local Tags=require(R.GlobalShared.ECS.Tags)
local EW=require(R.GlobalShared.ECS.Worlds.EnemyWorld)
local World=require(R.GlobalShared.ECS.Worlds.World)
local TC=require(R.Shared.Core.TimeCore)
local GC=require(R.Shared.Core.GeneratorCore)
local ES=require(game.ServerScriptService.Server.Services.EnemiesService)
local GP=require(game.ServerScriptService.Server.Services.GameplayService)
local Network=require(game.ServerScriptService.GlobalServer.Network)
local Ids=require(R.Types.Enums.Data.EEnemiesIds)
local chars=World:query(C.Model,Tags.Character,Tags.Alive):cached()
local pe,pm
local began=os.clock()
repeat
 for e,m in chars do pe,pm=e,m;break end
 if clientReady and pe and GP.IsGameRunning and next(GC.Grid.Grid) then break end
 if os.clock()-began>100 then error("pool benchmark startup timed out") end
 task.wait(1)
until false
GP.StartGame=function() end;GP.IsGameRunning=false
TC.ResetAllPauses();TC.SetWeaponsPaused(true)
World:add(pe,Tags.GodMode);pm.PrimaryPart.Anchored=true
local origin=pm.PrimaryPart.Position
W:SetAttribute("BallarcFinalCameraX",origin.X);W:SetAttribute("BallarcFinalCameraY",origin.Y);W:SetAttribute("BallarcFinalCameraZ",origin.Z)
local function log(v) v.label="__LABEL__";print("[BALLARC_POOL_SERVER] "..H:JSONEncode(v)) end
local function populate(kind)
 local ids={}
 for i=1,3000 do
  local x=origin.X+((i-1)%55-27)*3
  local z=origin.Z+(math.floor((i-1)/55)-27)*3
  local cell=GC.Grid:GetCellFromWorldPos(vector.create(x,0,z))
  local y=if cell then cell.Height+1 else origin.Y
  local id,e=ES.Spawn(if kind=="mixed" and i%2==0 then Ids.Bee else Ids.Slime,vector.create(x,y,z),1e9,0)
  if kind=="mixed" and i%4>=2 then EW:add(e,Tags.Charmed) end
  if string.find("__LABEL__","static",1,true) and kind=="ground" then EW:add(e,Tags.Stunned) end
  ids[#ids+1]=id
  if i%50==0 then RS.Heartbeat:Wait() end
 end
 return ids
end
local function sample(name)
 W:SetAttribute("BallarcFinalCapture",false);W:SetAttribute("BallarcFinalPhase",name.."-settle")
 task.wait(6)
 W:SetAttribute("BallarcFinalPhase",name);W:SetAttribute("BallarcFinalCapture",true)
 task.wait(10)
 W:SetAttribute("BallarcFinalCapture",false);log({phase="result",name=name,enemies=ES.GetCount()});task.wait(1)
end
ES.ClearAll();W:SetAttribute("BallarcFinalPhase","pool-setup")
local ids=populate("ground");sample("pool-ground-first")
-- Exercise real client KilledMultiple visuals with killer ID 0; no reward writes.
for _,player in game:GetService("Players"):GetPlayers() do Network.Server.Enemies.KilledMultiple.Fire(player,0,ids,1,0) end
ES.ClearAll();task.wait(3)
ids=populate("ground");sample("pool-ground-after-kills")
ES.ClearAll();task.wait(1);populate("mixed");sample("pool-mixed")
ES.ClearAll();task.wait(1);populate("ground");sample("pool-ground-after-mixed")
W:SetAttribute("BallarcDetachIdle",true);sample("pool-ground-detached-1")
sample("pool-ground-detached-2")
W:SetAttribute("BallarcDetachIdle",false);sample("pool-ground-restored")
ES.ClearAll();W:SetAttribute("BallarcFinalPhase","done");log({phase="done"})
