-- BALLARC_BENCH probe (server): injected into ServerScriptService by run.py, never in src. Never publish.
-- Holds the run, then for each arm respawns the same seeded crowd and tells the client which arm to time.
local R = game:GetService("ReplicatedStorage")
local RS = game:GetService("RunService")
local H = game:GetService("HttpService")
local W = workspace
local ready = Instance.new("RemoteEvent")
ready.Name = "BallarcBenchReady"
ready.Parent = R
local clientReady = false
ready.OnServerEvent:Connect(function() clientReady = true end)
task.wait(3)
local C = require(R.GlobalShared.ECS.Components)
local Tags = require(R.GlobalShared.ECS.Tags)
local World = require(R.GlobalShared.ECS.Worlds.World)
local TC = require(R.Shared.Core.TimeCore)
local GC = require(R.Shared.Core.GeneratorCore)
local ES = require(game.ServerScriptService.Server.Services.EnemiesService)
local GP = require(game.ServerScriptService.Server.Services.GameplayService)
local EIds = require(R.Types.Enums.Data.EEnemiesIds)
local characters = World:query(C.Model, C.InstanceId, Tags.Character, Tags.Alive):cached()
local function log(v) v.label = "__LABEL__"; print("[BALLARC_BENCH_SERVER] " .. H:JSONEncode(v)) end
local began = os.clock()
local pe, pm
repeat
	for e, m in characters do pe, pm = e, m; break end
	if pe and GP.IsGameRunning and next(GC.Grid.Grid) and clientReady then break end
	if os.clock() - began > 90 then log({ phase = "abort", character = pe ~= nil, running = GP.IsGameRunning, grid = next(GC.Grid.Grid) ~= nil, client = clientReady }); return end
	task.wait(1)
until false
GP.StartGame = function() end
GP.IsGameRunning = false
TC.ResetAllPauses()
TC.SetWeaponsPaused(true)
World:add(pe, Tags.GodMode)
pm.PrimaryPart.Anchored = true
local origin = pm.PrimaryPart.Position
log({ phase = "ready" })
local arms = H:JSONDecode('__ARMS__')
local N = tonumber("__COUNT__") or 1200
local kinds = { EIds.Slime, EIds.Skeleton, EIds.Fungus, EIds.Bee }
for _, arm in arms do
	W:SetAttribute("BallarcBenchCapture", false)
	W:SetAttribute("BallarcBenchArm", H:JSONEncode(arm))
	ES.ClearAll()
	task.wait(1)
	local rng = Random.new(7)
	for i = 1, arm.n or N do
		local a = rng:NextNumber() * math.pi * 2
		local r0, r1 = 15, arm.outer or 160
		local r = math.sqrt(rng:NextNumber() * (r1 ^ 2 - r0 ^ 2) + r0 ^ 2)
		local x, z = origin.X + math.cos(a) * r, origin.Z + math.sin(a) * r
		local cell = GC.Grid:GetCellFromWorldPos(vector.create(x, 0, z))
		local y = if cell then cell.Height + 1 else origin.Y
		ES.Spawn(kinds[i % #kinds + 1], vector.create(x, y, z), nil, 0)
		if i % 100 == 0 then RS.Heartbeat:Wait() end
	end
	task.wait(arm.walk and 30 or 3)
	TC.ResetAllPauses(); TC.SetWeaponsPaused(not arm.fight)
	W:SetAttribute("BallarcBenchCapture", true)
	task.wait(arm.seconds or 6)
	W:SetAttribute("BallarcBenchCapture", false)
	task.wait(0.5)
	log({ phase = "arm-done", arm = arm, enemies = ES.GetCount() })
end
W:SetAttribute("BallarcBenchArm", "done")
log({ phase = "done" })
