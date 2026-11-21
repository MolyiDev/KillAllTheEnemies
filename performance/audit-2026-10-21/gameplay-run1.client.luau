local R=game:GetService("ReplicatedStorage")
local RS=game:GetService("RunService")
local H=game:GetService("HttpService")
local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local W=workspace
task.wait(5)
local C=require(R.GlobalShared.ECS.Components)
local EW=require(R.GlobalShared.ECS.Worlds.EnemyWorld)
local TC=require(R.Shared.Core.TimeCore)
local controller=require(Players.LocalPlayer.PlayerScripts.Client.Controllers.Actor.EnemiesController)
local q=EW:query(C.CFrame,C.Model,C.Bone):cached()
local phase=""
local frameTimes,updateTimes={},{}
local records,bytes,packets=0,0,0
local lostFocus=false
UIS.WindowFocusReleased:Connect(function() lostFocus=true end)
R.Events.UpdateEnemies.OnClientEvent:Connect(function(b)
	if not W:GetAttribute("BallarcAuditCapture") then return end
	bytes+=buffer.len(b);packets+=1;records+=buffer.readu16(b,0)
end)
local function percentile(a,f) table.sort(a);return a[math.max(1,math.ceil(#a*f))] end
local function log()
	if #frameTimes==0 then return end
	local alive,visible=0,0
	for _,cf in q do alive+=1;if cf.Position.X~=2^24 then visible+=1 end end
	local camera=W.CurrentCamera
	print("[BALLARC_GAME_CLIENT] "..H:JSONEncode({phase=phase,frames=#frameTimes,frameMedianMs=percentile(frameTimes,0.5),frameP95Ms=percentile(frameTimes,0.95),frameP99Ms=percentile(frameTimes,0.99),updateMedianMs=percentile(updateTimes,0.5),updateP95Ms=percentile(updateTimes,0.95),residentEnemies=alive,visibleEnemies=visible,positionPackets=packets,positionBytes=bytes,positionRecords=records,viewport={camera.ViewportSize.X,camera.ViewportSize.Y},focusLostDuringSample=lostFocus,paused=TC.IsPaused,enemyScale=TC.EnemyTimeScale,limitation="Focus not forced; frame-rate caps and background throttling can floor frame times"}))
end
RS:BindToRenderStep("BallarcGameplayAuditCamera",Enum.RenderPriority.Last.Value+1,function()
	local x=W:GetAttribute("BallarcAuditCameraX")
	if x==nil then return end
	local y,z=W:GetAttribute("BallarcAuditCameraY"),W:GetAttribute("BallarcAuditCameraZ")
	local p=Vector3.new(x,y,z)
	local camera=W.CurrentCamera
	camera.CameraType=Enum.CameraType.Scriptable
	camera.FieldOfView=80
	camera.CFrame=CFrame.lookAt(p+Vector3.new(0,210,0),p,Vector3.new(0,0,-1))
end)
RS.PreRender:Connect(function(dt)
	local nowPhase=W:GetAttribute("BallarcAuditPhase") or "boot"
	local capture=W:GetAttribute("BallarcAuditCapture")
	if phase~=nowPhase or (not capture and #frameTimes>0) then
		log();frameTimes={};updateTimes={};packets,bytes,records=0,0,0;lostFocus=false;phase=nowPhase
	end
	if not capture then return end
	frameTimes[#frameTimes+1]=dt*1000
	local audit=controller.AuditUpdate
	if audit then updateTimes[#updateTimes+1]=audit.lastMs end
end)
print("[BALLARC_GAME_CLIENT] actual Survivors client probe ready")

