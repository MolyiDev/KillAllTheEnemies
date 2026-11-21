-- The match's clocks, on both sides. Everything that times a fight reads these rather than os.clock, so a
-- pause or an enemy freeze holds every timer at once without each system knowing why it stopped.
--
--   GameClock   advances with TimeScale: everything in the match.
--   EnemyClock  advances with TimeScale * EnemyTimeScale: what enemies do (wind-ups, staleness on the client).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Signal = require(ReplicatedStorage.Packages.Signal)

local TimeCore = {}

-- The movement update's step. 10 Hz is what the position packets are sized for; the client interpolates between them
-- (RENDER_DT).
TimeCore.FIXED_DT = 1 / 10
-- Exponential follow rate of the client's rendered CFrame toward the latest packet, ~250 ms time constant.
TimeCore.RENDER_DT = 4

TimeCore.TimeScale = 1
TimeCore.EnemyTimeScale = 1
TimeCore.IsPaused = false
-- Held from the console: the whole match, or the enemies alone. They outlive a new run's Reset.
TimeCore.IsManualPaused = false
TimeCore.IsEnemiesManualPaused = false
TimeCore.GameClock = 0
TimeCore.EnemyClock = 0

-- (timeScale)
TimeCore.OnTimeScaleChange = Signal.new()
-- (enemyTimeScale)
TimeCore.OnEnemyTimeScaleChange = Signal.new()

local enemyFreezeRemaining = 0
-- The scale asked for, which a manual pause holds at 0 without forgetting.
local underlyingTimeScale = 1

function TimeCore.SetTimeScale(value: number)
	underlyingTimeScale = value
	local actualValue = if TimeCore.IsManualPaused then 0 else value
	TimeCore.TimeScale = actualValue
	TimeCore.IsPaused = actualValue <= 0.01
	TimeCore.OnTimeScaleChange:Fire(actualValue)
end

function TimeCore.SetManualPause(isPaused: boolean)
	TimeCore.IsManualPaused = isPaused
	TimeCore.SetTimeScale(underlyingTimeScale)
end

function TimeCore.SetEnemyTimeScale(value: number)
	if TimeCore.EnemyTimeScale == value then return end
	TimeCore.EnemyTimeScale = value
	TimeCore.OnEnemyTimeScaleChange:Fire(value)
end

-- Holds every enemy for `duration` seconds of game time. Overlapping freezes keep the longer one.
function TimeCore.FreezeEnemies(duration: number)
	enemyFreezeRemaining = math.max(enemyFreezeRemaining, duration)
	TimeCore.SetEnemyTimeScale(0)
end

function TimeCore.SetEnemiesPaused(isPaused: boolean)
	TimeCore.IsEnemiesManualPaused = isPaused
	TimeCore.SetEnemyTimeScale(if isPaused or enemyFreezeRemaining > 0 then 0 else 1)
end

function TimeCore.GetDeltaTime(dt: number): number
	return dt * TimeCore.TimeScale
end

function TimeCore.GetEnemyDeltaTime(dt: number): number
	return dt * TimeCore.TimeScale * TimeCore.EnemyTimeScale
end

function TimeCore.Reset()
	enemyFreezeRemaining = 0
	TimeCore.GameClock = 0
	TimeCore.EnemyClock = 0
	TimeCore.SetEnemyTimeScale(if TimeCore.IsEnemiesManualPaused then 0 else 1)
	TimeCore.SetTimeScale(1)
end

RunService.Heartbeat:Connect(function(dt: number)
	local scaledDt = dt * TimeCore.TimeScale
	TimeCore.GameClock += scaledDt
	TimeCore.EnemyClock += scaledDt * TimeCore.EnemyTimeScale

	if enemyFreezeRemaining <= 0 or TimeCore.IsPaused then return end
	enemyFreezeRemaining -= scaledDt
	if enemyFreezeRemaining > 0 then return end
	enemyFreezeRemaining = 0
	if not TimeCore.IsEnemiesManualPaused then TimeCore.SetEnemyTimeScale(1) end
end)

return TimeCore
