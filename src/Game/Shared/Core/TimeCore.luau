-- The match's clocks, on both sides. Everything that times a fight reads these rather than os.clock, so a
-- pause or an enemy freeze holds every timer at once without each system knowing why it stopped.
--
--   GameClock   advances with TimeScale: everything in the match.
--   EnemyClock  advances with TimeScale * EnemyTimeScale: what enemies do (wind-ups, staleness on the client).
--
-- The server's scale is set through TimeService, which mirrors it to every client.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Signal = require(ReplicatedStorage.Packages.Signal)

local TimeCore = {}

-- The place's gravity at full speed. The client scales Workspace.Gravity with the clock (TimeController), so anything
-- that integrates its own fall on the game clock reads this instead.
TimeCore.GRAVITY = Workspace.Gravity

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
-- Held by an upgrade pick (UpgradesService): eased to a stop, and back to the scale asked for once let go.
TimeCore.IsHeld = false
-- Held by a boss's intro (BossIntroService): stopped at once, since an ease would let a blow land, and no blow lands
-- on a character until it lets go (CharacterService).
TimeCore.IsCutscene = false
TimeCore.GameClock = 0
TimeCore.EnemyClock = 0

-- (timeScale), every frame of an ease.
TimeCore.OnTimeScaleChange = Signal.new()
-- (enemyTimeScale)
TimeCore.OnEnemyTimeScaleChange = Signal.new()

local enemyFreezeRemaining = 0
-- The scale asked for, which a manual pause or a hold keeps at 0 without forgetting.
local underlyingTimeScale = 1
-- An ease in flight: from, to, its length and how far through it is (real seconds).
local easeFrom = 1
local easeTo = 1
local easeSeconds = 0
local easeElapsed = 0
local isEasing = false

local function apply(value: number)
	TimeCore.TimeScale = value
	TimeCore.IsPaused = value <= 0.01
	TimeCore.OnTimeScaleChange:Fire(value)
end

-- Eases TimeScale to `target` over `seconds` of real time (0 at once). Slowing, it falls away fast and creeps the
-- last of the way, so the world is seen almost stopped before it stops; speeding up, it creeps off the mark and
-- catches up. Either way the time spent near a standstill is what reads as slow motion. The client is moved with
-- this alone: the server says where to and how long.
function TimeCore.TweenTimeScale(target: number, seconds: number)
	if seconds <= 0 or target == TimeCore.TimeScale then
		isEasing = false
		apply(target)
		return
	end

	easeFrom = TimeCore.TimeScale
	easeTo = target
	easeSeconds = seconds
	easeElapsed = 0
	isEasing = true
end

-- Where the server's scale is headed: what it was asked for, unless a pause or a hold keeps it at 0.
function TimeCore.GetTargetTimeScale(): number
	return if TimeCore.IsManualPaused or TimeCore.IsHeld or TimeCore.IsCutscene then 0 else underlyingTimeScale
end

function TimeCore.SetTimeScale(value: number)
	underlyingTimeScale = value
	TimeCore.TweenTimeScale(TimeCore.GetTargetTimeScale(), 0)
end

function TimeCore.SetManualPause(isPaused: boolean)
	TimeCore.IsManualPaused = isPaused
	TimeCore.TweenTimeScale(TimeCore.GetTargetTimeScale(), 0)
end

function TimeCore.SetHeld(isHeld: boolean, seconds: number)
	TimeCore.IsHeld = isHeld
	TimeCore.TweenTimeScale(TimeCore.GetTargetTimeScale(), seconds)
end

function TimeCore.SetCutscene(isCutscene: boolean)
	TimeCore.IsCutscene = isCutscene
	TimeCore.TweenTimeScale(TimeCore.GetTargetTimeScale(), 0)
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
	TimeCore.IsCutscene = false
	TimeCore.GameClock = 0
	TimeCore.EnemyClock = 0
	TimeCore.SetEnemyTimeScale(if TimeCore.IsEnemiesManualPaused then 0 else 1)
	TimeCore.SetTimeScale(1)
end

RunService.Heartbeat:Connect(function(dt: number)
	if isEasing then
		easeElapsed += dt
		local t = math.min(easeElapsed / easeSeconds, 1)
		local curve = if easeTo < easeFrom then 1 - (1 - t) * (1 - t) else t * t
		-- Landed on the number itself: a + (b - a) * 1 can come out a hair off b, and 1 is tested for exactly.
		if t >= 1 then isEasing = false end
		apply(if t >= 1 then easeTo else easeFrom + (easeTo - easeFrom) * curve)
	end

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
