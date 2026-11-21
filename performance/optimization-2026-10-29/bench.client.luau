-- Temporary test-only LocalScript in StarterPlayerScripts. Never publish.
local R=game:GetService("ReplicatedStorage")
local RS=game:GetService("RunService")
local H=game:GetService("HttpService")
local P=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local Stats=game:GetService("Stats")
local W=workspace
task.wait(5)
local C=require(R.GlobalShared.ECS.Components)
local EW=require(R.GlobalShared.ECS.Worlds.EnemyWorld)
local TC=require(R.Shared.Core.TimeCore)
local controller=require(P.LocalPlayer.PlayerScripts.Client.Controllers.Actor.EnemiesController)
local ready=R:WaitForChild("BallarcBenchReady")
local q=EW:query(C.CFrame,C.Model,C.Bone,C.WalkAnimation,C.InstanceId):cached()
local away=false
local function log(tag,v) v.label="__LABEL__";print("["..tag.."] "..H:JSONEncode(v)) end
ready.OnClientEvent:Connect(function(topic,payload)
 if topic=="check" then
  local positions,lastUpdate=controller.BenchPositions,controller.BenchLastUpdate
  local n=buffer.len(payload)//14
  local checked,bad,maxErr,resident=0,0,0,0
  local badIds,badRows={},{}
  local residentIds={}
  for _,_,_,_,_,id in q do residentIds[id]=true;resident+=1 end
  for i=0,n-1 do
   local o=i*14;local id=buffer.readu16(payload,o)
   local lu=lastUpdate[id]
   if residentIds[id] and lu then
    local p=positions[id]
    local e=math.max(math.abs(p.X-buffer.readf32(payload,o+2)),math.abs(p.Y-buffer.readf32(payload,o+6)),math.abs(p.Z-buffer.readf32(payload,o+10)))
    checked+=1;if e>maxErr then maxErr=e end
    if e>0.04 then bad+=1;if #badIds<10 then badIds[#badIds+1]=id;badRows[#badRows+1]={id=id,err=e,age=TC.EnemyClock-lu,client={p.X,p.Y,p.Z},server={buffer.readf32(payload,o+2),buffer.readf32(payload,o+6),buffer.readf32(payload,o+10)}} end end
   end
  end
  ready:FireServer("check-complete",{checked=checked,bad=bad,maxErr=maxErr,resident=resident,serverEnemies=n,badIds=badIds,badRows=badRows})
  return
 end
 if topic~="smoke" then return end
 task.spawn(function()
  local results={}
  local function check(name,fn) local ok,err=pcall(fn);results[name]={passed=ok,error=if ok then nil else tostring(err)} end
  local function counts() local res,vis=0,0;for _,cf in q do res+=1;if cf.Position.X~=2^24 then vis+=1 end end;return res,vis end
  check("freeze-resume",function()
   -- TimeStop freezes both peers; mirror that.
   ready:FireServer("freeze",true);TC.SetEnemiesPaused(true);task.wait(0.6)
   local frozen={}
   for e,cf,_,_,track in q do assert(not track.IsPlaying,"track playing while frozen");frozen[e]=cf end
   task.wait(0.6)
   local moved={}
   for e,cf,_,bone,_,id in q do
    if cf~=frozen[e] then moved[#moved+1]={id=id,from={frozen[e].Position.X,frozen[e].Position.Y,frozen[e].Position.Z},to={cf.Position.X,cf.Position.Y,cf.Position.Z}} end
    assert((bone.Transform.Position-cf.Position).Magnitude<0.01,"frozen bone reset")
   end
   assert(#moved==0,"frozen CFrame moved "..H:JSONEncode(moved))
   ready:FireServer("freeze",false);TC.SetEnemiesPaused(false);task.wait(0.5)
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
   away=true;task.wait(1.3)
   local shown={}
   for _,cf,_,_,_,id in q do
    if cf.Position.X~=2^24 then
     local tp=controller.BenchPositions[id];local lu=controller.BenchLastUpdate[id]
     shown[#shown+1]={id=id,cf={cf.Position.X,cf.Position.Y,cf.Position.Z},target=tp and {tp.X,tp.Y,tp.Z},age=lu and TC.EnemyClock-lu,paused=TC.IsPaused}
    end
   end
   assert(#shown==0,"enemy remained visible behind camera "..H:JSONEncode(shown))
   away=false;task.wait(1)
   local _,vis=counts();assert(vis>0,"enemies did not reenter view")
  end)
  check("release-and-return",function()
   local before=counts()
   away=true;task.wait(4.5)
   local during=counts()
   away=false;task.wait(1.5)
   local after,vis=counts()
   results.releaseCounts={before=before,during=during,after=after,visibleAfter=vis}
   assert(vis>0,"enemies did not come back after release")
  end)
  check("client-restart-cleanup",function()
   controller.OnGameRestarting()
   local count=0;for _ in q do count+=1 end;assert(count==0,"restart retained live rigs")
  end)
  log("BALLARC_BENCH_SMOKE",results)
  ready:FireServer("smoke-complete",results)
 end)
end)
local frames,updates,kbps={},{},{}
local phase="boot"
local lostFocus=false
local packets,bytes=0,0
local function percentile(a,p) table.sort(a);return a[math.max(1,math.ceil(#a*p))] or 0 end
local function mean(a) local s=0;for _,v in a do s+=v end;return if #a>0 then s/#a else 0 end
local function flush()
 if #frames==0 then return end
 local total,visible,animated=0,0,0
 for _,cf,_,_,track in q do
  total+=1;if cf.Position.X~=2^24 then visible+=1 end;if track.IsPlaying then animated+=1 end
 end
 local cam=W.CurrentCamera
 log("BALLARC_BENCH_CLIENT",{phase=phase,frames=#frames,medianMs=percentile(frames,0.5),p95Ms=percentile(frames,0.95),p99Ms=percentile(frames,0.99),
  updateMedianMs=percentile(updates,0.5),updateP95Ms=percentile(updates,0.95),updateMeanMs=mean(updates),
  resident=total,visible=visible,animated=animated,packets=packets,bytes=bytes,receiveKbpsMean=mean(kbps),
  focusLost=lostFocus,viewport={cam.ViewportSize.X,cam.ViewportSize.Y}})
end
UIS.WindowFocusReleased:Connect(function() lostFocus=true end)
R.Events.UpdateEnemies.OnClientEvent:Connect(function(b)
 if W:GetAttribute("BallarcBenchCapture") then packets+=1;bytes+=buffer.len(b) end
end)
task.spawn(function() while true do task.wait(0.5) if W:GetAttribute("BallarcBenchCapture") then kbps[#kbps+1]=Stats.DataReceiveKbps end end end)
RS:BindToRenderStep("BallarcBenchCamera",Enum.RenderPriority.Last.Value+1,function()
 local x=W:GetAttribute("BallarcBenchCameraX");if not x then return end
 local p=Vector3.new(x,W:GetAttribute("BallarcBenchCameraY"),W:GetAttribute("BallarcBenchCameraZ"))
 local cam=W.CurrentCamera
 cam.CameraType=Enum.CameraType.Scriptable;cam.FieldOfView=90
 local eye=p+Vector3.new(0,22,32)
 cam.CFrame=if away then CFrame.lookAt(p+Vector3.new(0,3000,0),p+Vector3.new(0,3100,1)) else CFrame.lookAt(eye,p+Vector3.new(0,0,-40))
end)
RS.PreRender:Connect(function(dt)
 local nextPhase=W:GetAttribute("BallarcBenchPhase") or "boot"
 local capture=W:GetAttribute("BallarcBenchCapture")
 if nextPhase~=phase or not capture and #frames>0 then
  flush();frames,updates,kbps={},{},{};packets,bytes=0,0;lostFocus=false;phase=nextPhase
 end
 if capture then frames[#frames+1]=dt*1000;updates[#updates+1]=controller.BenchUpdateMs or 0 end
end)
task.spawn(function() while W:GetAttribute("BallarcBenchPhase")==nil do ready:FireServer("ready");task.wait(1) end end)
