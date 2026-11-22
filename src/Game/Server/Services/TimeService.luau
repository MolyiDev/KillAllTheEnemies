-- The match's clock for everybody. Every change to the server's TimeCore scale goes through here and is mirrored to
-- every client (TimeController), eased the same way, so a pause, a pick's hold or the console's time scale slows
-- both sides at once.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
})

local TimeService = {}

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

-- A new run: the clocks start over at full speed.
function TimeService.Reset()
	TimeCore.Reset()
	sync(0)
end

TimeService.OnPlayerConnected = function(player: Player)
	ServerNetworkGame.TimeScale.Fire(player, TimeCore.GetTargetTimeScale(), 0, TimeCore.EnemyTimeScale)
end :: TPlayerEvents.OnPlayerConnected

return Ignis.Register(TimeService)
