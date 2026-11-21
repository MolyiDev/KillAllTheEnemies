-- The client's view of the run and its rounds: tells the server it has loaded, and mirrors every beat as state and
-- signals for the HUD to hang off. Draws nothing itself (HudController does).
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Network = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Network)
local RoundCore = require(ReplicatedStorage.Shared.Core.RoundCore)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)

local ServerNetworkGame = Network.Server.Game
local ServerNetworkRounds = Network.Server.Rounds
local ServerNetworkEnemies = Network.Server.Enemies
local ServerNetworkEconomy = Network.Server.Economy
local ClientNetworkGame = Network.Client.Game
local ClientNetworkRounds = Network.Client.Rounds

local MatchController = {}

-- Votes to skip the rest of the preparation, or the wave once it has run RoundCore.SKIP_AFTER_SECONDS.
MatchController.SKIP_KEY = Enum.KeyCode.N

MatchController.IsRunning = false
-- The run is over and the party is on its way back (MatchEnded). ReturnAt is the os.clock it leaves at.
MatchController.IsEnded = false
MatchController.ReturnAt = 0
MatchController.RoundsCleared = 0
MatchController.Round = 0
MatchController.IsPreparing = false
MatchController.IsBossRound = false
-- TimeCore.GameClock the preparation ends at, and the one the wave being fought can be skipped from.
MatchController.PrepareEndsAt = 0
MatchController.SkipOpensAt = 0
MatchController.Votes = 0
MatchController.VotesNeeded = 0
-- Bodies still to kill in the rounds being fought.
MatchController.Remaining = 0
MatchController.Gold = 0
-- What this run has earned so far, for the results screen.
MatchController.RunGold = 0
MatchController.RunGems = 0
MatchController.BossDataId = 0
MatchController.BossHealth = 0
MatchController.BossMaxHealth = 0
-- The revive product on offer after a clear while down, or 0.
MatchController.ReviveProductId = 0

-- Fired on every change of the above.
MatchController.OnChanged = Signal.new()
-- (roundsCleared, secondsUntilReturn)
MatchController.OnMatchEnded = Signal.new()
-- (position, amount): Gold the local player already earned, to draw as coins.
MatchController.OnCoins = Signal.new()

function MatchController.VoteStart()
	ClientNetworkRounds.VoteStart.Fire()
end

function MatchController.SetAutoSkip(isOn: boolean)
	ClientNetworkRounds.SetAutoSkip.Fire(isOn)
end

local function changed()
	MatchController.OnChanged:Fire()
end

ServerNetworkGame.MatchStarted.On(function()
	MatchController.IsRunning = true
	changed()
end)

ServerNetworkGame.MatchEnded.On(function(roundsCleared: number, seconds: number)
	MatchController.IsRunning = false
	MatchController.IsPreparing = false
	MatchController.IsEnded = true
	MatchController.RoundsCleared = roundsCleared
	MatchController.ReturnAt = os.clock() + seconds
	changed()
	MatchController.OnMatchEnded:Fire(roundsCleared, seconds)
end)

ServerNetworkRounds.Preparing.On(function(round: number, seconds: number, isBoss: boolean)
	MatchController.Round = round
	MatchController.IsPreparing = true
	MatchController.IsBossRound = isBoss
	MatchController.PrepareEndsAt = TimeCore.GameClock + seconds
	changed()
end)

ServerNetworkRounds.Started.On(function(round: number, bodies: number)
	MatchController.Round = round
	MatchController.IsPreparing = false
	MatchController.SkipOpensAt = TimeCore.GameClock + RoundCore.SKIP_AFTER_SECONDS
	MatchController.Remaining = bodies
	MatchController.ReviveProductId = 0
	changed()
end)

ServerNetworkRounds.Remaining.On(function(remaining: number)
	MatchController.Remaining = remaining
	changed()
end)

-- Only the newest round's clear empties the count: an older one skipped past clears with the newer still open.
ServerNetworkRounds.Cleared.On(function(round: number)
	if round ~= MatchController.Round then return end
	MatchController.Remaining = 0
	changed()
end)

ServerNetworkRounds.Votes.On(function(votes: number, needed: number)
	MatchController.Votes = votes
	MatchController.VotesNeeded = needed
	changed()
end)

-- The XP is saved for the lobby's level and not shown here.
ServerNetworkRounds.Rewards.On(function(_, _, gems: number, _)
	MatchController.RunGems += gems
end)

ServerNetworkRounds.ReviveOffer.On(function(productId: number)
	MatchController.ReviveProductId = productId
	changed()
end)

ServerNetworkEnemies.BossHealth.On(function(dataId: number, health: number, maxHealth: number)
	MatchController.BossDataId = dataId
	MatchController.BossHealth = health
	MatchController.BossMaxHealth = maxHealth
	changed()
end)

ServerNetworkEconomy.Gold.On(function(gold: number)
	-- Earned is every rise; a fall is spending.
	if gold > MatchController.Gold then
		MatchController.RunGold += gold - MatchController.Gold
	end
	MatchController.Gold = gold
	changed()
end)

ServerNetworkEconomy.Coins.On(function(position: Vector3, amount: number)
	MatchController.OnCoins:Fire(position, amount)
end)

MatchController.OnStart = function()
	ContextActionService:BindAction("VoteStart", function(_, state)
		if state == Enum.UserInputState.Begin then MatchController.VoteStart() end
		return Enum.ContextActionResult.Sink
	end, false, MatchController.SKIP_KEY)
	-- Last thing on start: every module's network listeners were connected when it loaded.
	ClientNetworkGame.GameLoaded.Fire()
end

return Ignis.Register(MatchController)
