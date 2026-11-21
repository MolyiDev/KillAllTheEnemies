local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local Tags = require(ReplicatedStorage.GlobalShared.ECS.Tags)
local EnemyWorld = require(ReplicatedStorage.GlobalShared.ECS.Worlds.EnemyWorld)
local Parallel = require(ServerScriptService.Server.Actors.EnemiesActor.Parallel)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)

local EnemiesQuery = EnemyWorld:query(
	Components.Position,
	Components.Velocity,
	Components.Radius,
	Components.Force,
	Components.MovementSpeed,
	Components.ClimbGrace,
	Components.ExplosionRadius
)
	:without(Tags.Flying, Tags.Telegraphing, Tags.Stunned, Tags.Charmed)
	:cached()

local WORKERS = 16
local parallel = Parallel(WORKERS)

local heartbeat = 0
-- Serial dispatch: the heavy enemy math runs in parallel inside Worker actors
-- (via actor:SendMessage). This callback only builds char positions and
-- partitions, and the frozen-state branch needs serial context for FireClient.
RunService.Heartbeat:Connect(function(dt)
	if workspace:GetAttribute("BallarcAuditSerial") then return end
	if TimeCore.IsPaused then return end
	-- During TimeStop freeze (EnemyTimeScale = 0) accumulate raw dt so the
	-- per-player position pulse keeps firing - `parallel` skips the worker
	-- dispatch in that case and just re-sends positions so a player rotating
	-- their camera mid-freeze still sees enemies that re-enter their frustum.
	-- Outside freeze, gate on enemy-scaled dt so slow-mo accumulates correctly.
	local effDt = if TimeCore.EnemyTimeScale > 0 then TimeCore.GetEnemyDeltaTime(dt) else dt
	heartbeat += effDt
	if heartbeat < TimeCore.FIXED_DT then return end
	heartbeat = 0

	parallel(EnemiesQuery)
end)

return nil

