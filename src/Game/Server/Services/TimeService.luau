-- The match's clock for everybody. Every change to the server's TimeCore scale goes through here and is mirrored to
-- every client (TimeController), eased the same way, so a pause, a pick's hold or the console's time scale slows
-- both sides at once.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Network = require(ServerScriptService.GlobalServer.Network)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local ServerNetworkGame = Network.Server.Game

local Tune = table.freeze({
	-- A hold drains the match to a stop over this long, and lets it run up again over this long (real seconds).
	HOLD_SECONDS = 0.8,
	RELEASE_SECONDS = 0.5,
	-- A beat of slow motion: down to this share of the speed in SLOW_IN, held SLOW_HOLD, back over SLOW_OUT (real
	-- seconds). The match runs about 0.7 s of game time behind real time after it.
	SLOW_SCALE = 0.25,
	SLOW_IN_SECONDS = 0.08,
	SLOW_HOLD_SECONDS = 0.5,
	SLOW_OUT_SECONDS = 0.6,
})

local TimeService = {}

-- The os.clock the slow motion lets go at, 0 for none.
local slowEndsAt = 0

local function sync(seconds: number)
	ServerNetworkGame.TimeScale.FireAll(TimeCore.GetTargetTimeScale(), seconds, TimeCore.EnemyTimeScale)
end

function TimeService.SetTimeScale(value: number)
	TimeCore.SetTimeScale(value)
	sync(0)
end

function TimeService.SetManualPause(isPaused: boolean)
	TimeCore.SetManualPause(isPaused)
	sync(0)
end

function TimeService.SetEnemiesPaused(isPaused: boolean)
	TimeCore.SetEnemiesPaused(isPaused)
	sync(0)
end

-- Eases the whole match to a stop, or back to the scale it was asked for (UpgradesService, while everybody picks).
function TimeService.SetHeld(isHeld: boolean)
	if TimeCore.IsHeld == isHeld then return end
	local seconds = if isHeld then Tune.HOLD_SECONDS else Tune.RELEASE_SECONDS
	TimeCore.SetHeld(isHeld, seconds)
	sync(seconds)
end

-- Stops the whole match at once for a boss's intro, or lets it go at once (BossIntroService).
function TimeService.SetCutscene(isCutscene: boolean)
	if TimeCore.IsCutscene == isCutscene then return end
	TimeCore.SetCutscene(isCutscene)
	sync(0)
end

-- A beat of slow motion for everybody (a boss falling, BossService). Another one while it holds holds it longer.
function TimeService.SlowMotion()
	slowEndsAt = os.clock() + Tune.SLOW_IN_SECONDS + Tune.SLOW_HOLD_SECONDS
	TimeCore.SetSlowScale(Tune.SLOW_SCALE, Tune.SLOW_IN_SECONDS)
	sync(Tune.SLOW_IN_SECONDS)
end

-- A new run: the clocks start over at full speed.
function TimeService.Reset()
	slowEndsAt = 0
	TimeCore.Reset()
	sync(0)
end

RunService.Heartbeat:Connect(function()
	if slowEndsAt == 0 or os.clock() < slowEndsAt then return end
	slowEndsAt = 0
	TimeCore.SetSlowScale(1, Tune.SLOW_OUT_SECONDS)
	sync(Tune.SLOW_OUT_SECONDS)
end)

TimeService.OnPlayerConnected = function(player: Player)
	ServerNetworkGame.TimeScale.Fire(player, TimeCore.GetTargetTimeScale(), 0, TimeCore.EnemyTimeScale)
end :: TPlayerEvents.OnPlayerConnected

return Ignis.Register(TimeService)
