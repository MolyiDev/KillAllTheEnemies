-- Temporary test-only LocalScript in StarterPlayerScripts. Never publish.
local R=game:GetService("ReplicatedStorage")
local RS=game:GetService("RunService")
local H=game:GetService("HttpService")
local P=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local W=workspace
task.wait(5)
local C=require(R.GlobalShared.ECS.Components)
local EW=require(R.GlobalShared.ECS.Worlds.EnemyWorld)
local TC=require(R.Shared.Core.TimeCore)
local controller=require(P.LocalPlayer.PlayerScripts.Client.Controllers.Actor.EnemiesController)
local settings=require(P.LocalPlayer.PlayerScripts.GlobalClient.Controllers.SettingsController)
local enums=require(R.Types.Enums.Settings.ESettings)
local visual=require(R.Types.Enums.Settings.ESettingsVisual)
local ready=R:WaitForChild("BallarcFinalBenchReady")
local q=EW:query(C.CFrame,C.Model,C.Bone,C.WalkAnimation):cached()
local away=false
local ownershipTarget=0
local detached={}
W:GetAttributeChangedSignal("BallarcDetachIdle"):Connect(function()
 if W:GetAttribute("BallarcDetachIdle") then
  local active={};for _,_,model in q do active[model]=true end
  for _,model in W.Enemies:GetChildren() do
   if model:IsA("Model") and not active[model] then detached[#detached+1]=model;model.Parent=nil end
  end
 else
  for _,model in detached do model.Parent=W.Enemies end
  table.clear(detached)
 end
end)
ready.OnClientEvent:Connect(function(topic,phase,target)
 if topic=="restart-pending-effects" then
  controller.OnGameRestarting()
  task.delay(1,function()
   local remaining=0
   for _,v in W.Temporal:GetChildren() do
    if v.Name=="Slime" and v:IsA("Attachment") then remaining+=1 end
   end
   print("[BALLARC_PENDING_EFFECTS] "..H:JSONEncode({passed=remaining==0,remainingDeathAttachments=remaining}))
   ready:FireServer("pending-effects-complete")
  end)
  return
 end
 if topic=="ownership-reset" then
  local a=controller.AuditOwnership
  a.adds=0;a.removes=0;a.addMs=0;a.removeMs=0;a.firstAdd=0;a.readySeconds=0;a.phase=phase
  ownershipTarget=target
  ready:FireServer("ownership-ready",phase)
  return
 end
 if topic~="smoke" then return end
 task.spawn(function()
  local results={}
  local function check(name,fn)
   local ok,err=pcall(fn);results[name]={passed=ok,error=if ok then nil else tostring(err)}
  end
  check("freeze-resume",function()
   TC.SetEnemiesPaused(true);task.wait(0.2)
   local frozen={}
   for e,cf,_,_,track in q do assert(not track.IsPlaying);frozen[e]=cf end
   task.wait(0.25)
   for e,cf,_,bone in q do
    assert(cf==frozen[e],"frozen CFrame moved")
    assert((bone.Transform.Position-cf.Position).Magnitude<0.01,"frozen bone reset")
   end
   TC.SetEnemiesPaused(false);task.wait(0.35)
   local played=0;for _,_,_,_,track in q do if track.IsPlaying then played+=1 end end
   assert(played>0,"tracks did not resume")
  end)
  TC.ResetAllPauses()
  check("manual-pause-resume",function()
   TC.ToggleManualPause();task.wait(0.3)
   for _,cf,_,bone,track in q do
    assert(not track.IsPlaying,"paused track playing")
    assert((bone.Transform.Position-cf.Position).Magnitude<0.01,"paused bone reset")
   end
   TC.ToggleManualPause();task.wait(0.3)
  end)
  TC.ResetAllPauses()
  check("camera-hide-reenter",function()
   away=true;task.wait(0.5)
   for _,cf in q do assert(cf.Position.X==2^24,"enemy remained visible behind camera") end
   away=false;task.wait(0.6)
   local visible=0;for _,cf in q do if cf.Position.X~=2^24 then visible+=1 end end
   assert(visible>0,"enemies did not reenter view")
  end)
  away=false
  check("client-restart-cleanup",function()
   controller.OnGameRestarting()
   local count=0;for _ in q do count+=1 end;assert(count==0,"restart retained live rigs")
  end)
  print("[BALLARC_SMOKE_CLIENT] "..H:JSONEncode(results))
  ready:FireServer("smoke-complete",results)
 end)
end)
local frames,updates={},{}
local phase="boot"
local lostFocus=false
local packets,bytes,rows=0,0,0
local function forceRange()
 settings.OnNumberChanged:Fire(enums.Visual,visual.AnimationDistance,1000)
 settings.OnNumberChanged:Fire(enums.Visual,visual.RenderDistance,1000)
end
forceRange()
for _,v in game:GetDescendants() do
 local props=if v:IsA("ImageLabel") or v:IsA("ImageButton") then {"Image"}
  elseif v:IsA("Sound") then {"SoundId"}
  elseif v:IsA("Decal") or v:IsA("Texture") then {"Texture"}
  elseif v:IsA("MeshPart") then {"MeshId","TextureID"}
  elseif v:IsA("SpecialMesh") then {"MeshId","TextureId"}
  elseif v:IsA("ShirtGraphic") then {"Graphic"}
  elseif v:IsA("Shirt") then {"ShirtTemplate"}
  elseif v:IsA("Pants") then {"PantsTemplate"}
  else {}
 for _,prop in props do
  local value=v[prop]
  if value=="rbxassetid://" or string.find(value,"203785492",1,true) then
   print("[BALLARC_BAD_ASSET] "..v:GetFullName().." "..prop.." "..value)
  end
 end
end
local function percentile(a,p) table.sort(a);return a[math.max(1,math.ceil(#a*p))] or 0 end
local function flush()
 if #frames==0 then return end
 local total,visible,animated=0,0,0
 local activeModels={}
 for _,cf,model,_,track in q do
  activeModels[model]=true
  total+=1;if cf.Position.X~=2^24 then visible+=1 end;if track.IsPlaying then animated+=1 end
 end
 local unique=0;for _ in activeModels do unique+=1 end
 local retained,idle,idlePlaying=0,0,0
 for _,model in W.Enemies:GetChildren() do
  if not model:IsA("Model") then continue end
  retained+=1
  if not activeModels[model] then
   idle+=1
   local ac=model:FindFirstChildOfClass("AnimationController")
   local animator=ac and ac:FindFirstChildOfClass("Animator")
   if animator then idlePlaying+=#animator:GetPlayingAnimationTracks() end
  end
 end
 local cam=W.CurrentCamera
 print("[BALLARC_FINAL_CLIENT] "..H:JSONEncode({label="__LABEL__",phase=phase,frames=#frames,medianMs=percentile(frames,0.5),p95Ms=percentile(frames,0.95),p99Ms=percentile(frames,0.99),maxMs=frames[#frames],updateMedianMs=percentile(updates,0.5),resident=total,visible=visible,animated=animated,uniqueActiveModels=unique,retainedModels=retained,idleModels=idle,detachedModels=#detached,idlePlayingTracks=idlePlaying,pools=controller.AuditPools and controller.AuditPools(),ownership=controller.AuditOwnership,packets=packets,bytes=bytes,rows=rows,focusLost=lostFocus,paused=TC.IsPaused,enemyScale=TC.EnemyTimeScale,viewport={cam.ViewportSize.X,cam.ViewportSize.Y}}))
end
UIS.WindowFocusReleased:Connect(function() lostFocus=true end)
R.Events.UpdateEnemies.OnClientEvent:Connect(function(b)
 if W:GetAttribute("BallarcFinalCapture") then packets+=1;bytes+=buffer.len(b);rows+=buffer.readu16(b,0) end
end)
RS:BindToRenderStep("BallarcFinalCamera",Enum.RenderPriority.Last.Value+1,function()
 local x=W:GetAttribute("BallarcFinalCameraX");if not x then return end
 local p=Vector3.new(x,W:GetAttribute("BallarcFinalCameraY"),W:GetAttribute("BallarcFinalCameraZ"))
 local cam=W.CurrentCamera
 cam.CameraType=Enum.CameraType.Scriptable;cam.FieldOfView=80
 cam.CFrame=if away then CFrame.lookAt(p+Vector3.new(0,210,0),p+Vector3.new(0,420,0),Vector3.new(0,0,-1)) else CFrame.lookAt(p+Vector3.new(0,210,0),p,Vector3.new(0,0,-1))
end)
RS.PreRender:Connect(function(dt)
 local ownership=controller.AuditOwnership
 if ownership and ownershipTarget>0 and ownership.adds==ownershipTarget and ownership.readySeconds==0 then
  ownership.readySeconds=os.clock()-ownership.firstAdd
 end
 local nextPhase=W:GetAttribute("BallarcFinalPhase") or "boot"
 local capture=W:GetAttribute("BallarcFinalCapture")
 if nextPhase~=phase or not capture and #frames>0 then
  flush();frames,updates={},{};packets,bytes,rows=0,0,0;lostFocus=false;phase=nextPhase;forceRange()
 end
 if capture then frames[#frames+1]=dt*1000;updates[#updates+1]=controller.AuditUpdate.lastMs end
end)
-- Repeat until server has finished requiring services and installed its listener.
task.spawn(function() while W:GetAttribute("BallarcFinalPhase")==nil do ready:FireServer("ready");task.wait(1) end end)
