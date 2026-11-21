-- Spawn/removal overhead of Workspace-resident vs detached idle model pools.
local R=game:GetService("ReplicatedStorage")
local RS=game:GetService("RunService")
local H=game:GetService("HttpService")
local W=workspace
local ready=R:WaitForChild("BallarcFinalBenchReady")
local clientReady=false
local ack=""
ready.OnServerEvent:Connect(function(_,topic,phase)
 if topic=="ready" then clientReady=true elseif topic=="ownership-ready" then ack=phase end
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
local Network=require(game.ServerScriptService.GlobalServer.Network)
local Ids=require(R.Types.Enums.Data.EEnemiesIds)
local chars=World:query(C.Model,Tags.Character,Tags.Alive):cached()
local pe,pm
local began=os.clock()
repeat
 for e,m in chars do pe,pm=e,m;break end
 if clientReady and pe and GP.IsGameRunning and next(GC.Grid.Grid) then break end
 if os.clock()-began>100 then error("ownership benchmark startup timed out") end
 task.wait(1)
until false
GP.StartGame=function() end;GP.IsGameRunning=false
TC.ResetAllPauses();TC.SetWeaponsPaused(true)
World:add(pe,Tags.GodMode);pm.PrimaryPart.Anchored=true
local origin=pm.PrimaryPart.Position
W:SetAttribute("BallarcFinalCameraX",origin.X);W:SetAttribute("BallarcFinalCameraY",origin.Y);W:SetAttribute("BallarcFinalCameraZ",origin.Z)
local function reset(name,n)
 W:SetAttribute("BallarcFinalCapture",false)
 ack="";ready:FireAllClients("ownership-reset",name,n)
 local t=os.clock();while ack~=name and os.clock()-t<5 do task.wait(0.05) end
 assert(ack==name,"client did not acknowledge ownership phase")
 W:SetAttribute("BallarcFinalPhase",name);W:SetAttribute("BallarcFinalCapture",true)
end
local function finish()
 task.wait(3);W:SetAttribute("BallarcFinalCapture",false);task.wait(0.25)
end
ES.ClearAll();W:SetAttribute("BallarcFinalPhase","ownership-setup");task.wait(1)
for rep,n in {50,50,3000,3000,50} do
 reset(n.."-spawn-"..rep,n)
 local ids={}
 local width=math.ceil(math.sqrt(n))
 for i=1,n do
  local x=origin.X+((i-1)%width-(width-1)/2)*3
  local z=origin.Z+(math.floor((i-1)/width)-(width-1)/2)*3
  local cell=GC.Grid:GetCellFromWorldPos(vector.create(x,0,z))
  local id,e=ES.Spawn(Ids.Slime,vector.create(x,if cell then cell.Height+1 else origin.Y,z),1e9,0)
  EW:add(e,Tags.Stunned);ids[#ids+1]=id
  if n>100 and i%50==0 then RS.Heartbeat:Wait() end
 end
 finish()
 reset(n.."-remove-"..rep,0)
 if rep==4 then
  for _,player in game:GetService("Players"):GetPlayers() do Network.Server.Enemies.KilledMultiple.Fire(player,0,ids,1,0) end
 end
 ES.ClearAll();finish()
end
W:SetAttribute("BallarcFinalPhase","done")
print("[BALLARC_OWNERSHIP_SERVER] "..H:JSONEncode({phase="done",label="__LABEL__"}))
