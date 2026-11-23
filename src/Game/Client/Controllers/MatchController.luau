-- The client's view of the run and its rounds: tells the server it has loaded, and mirrors every beat as state and
-- signals for the HUD to hang off. Draws nothing itself (HudController does).
local AdService = game:GetService("AdService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Network = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Network)
-- Through PlayerScripts, the copy that runs: requiring the StarterPlayer one would load a second controller.
local DamageNumbersController =
	require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.DamageNumbersController)
local MusicController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.MusicController)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local MapsCore = require(ReplicatedStorage.GlobalShared.Core.MapsCore)
local RoundCore = require(ReplicatedStorage.Shared.Core.RoundCore)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)
local NetworkTypes = require(ReplicatedStorage.Types.NetworkTypes)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local ServerNetworkGame = Network.Server.Game
local ServerNetworkRounds = Network.Server.Rounds
local ServerNetworkEnemies = Network.Server.Enemies
local ServerNetworkEconomy = Network.Server.Economy
local ClientNetworkGame = Network.Client.Game
local ClientNetworkRounds = Network.Client.Rounds

-- What the results show, as the server sent it (Game.MatchEnded), and what has happened on them since.
export type TResults = {
	Wave: number,
	IsNewBest: boolean,
	SquadKills: number,
	SecondsSurvived: number,
	-- The run's Gems as it ended.
	Gems: number,
	-- The product that doubles them, 0 with nothing to double or once it is done.
	DoubleProductId: number,
	-- An ad that pays the doubling can be shown to this player right now.
	CanWatchAd: boolean,
	-- The Gems a doubling bought on these results added, and the os.clock they arrived.
	Doubled: number,
	DoubledAt: number,
	-- The countdown to the lobby: the os.clock it runs out at, or the seconds left on it while it waits for a
	-- purchase.
	ReturnAt: number,
	ReturnSeconds: number,
	IsReturnHeld: boolean,
	-- The seconds the countdown started with.
	ReturnTotal: number,
	-- PLAY AGAIN's count, and whether the local player is in it.
	Votes: number,
	VotesNeeded: number,
	HasVoted: boolean,
}

export type TScore = { ClassId: number, Kills: number, Deaths: number, Gold: number }

local MatchController = {}

-- Votes to skip the rest of the preparation, or the wave once it has run RoundCore.GetSkipAfterSeconds.
MatchController.SKIP_KEY = Enum.KeyCode.N

-- The fight's track: silent while a wave is prepared, in with the first fight and at its peak by the first boss.
local TENSION_FIRST = 0.15
local TENSION_PEAK = 0.6

MatchController.IsRunning = false
-- The map this match is played on (a MapsCore name), from MatchStarted.
MatchController.MapName = MapsCore.DEFAULT
-- Everybody is down and the run is held under the results (MatchEnded), until a revive resumes it or it starts over.
MatchController.IsEnded = false
MatchController.Results = nil :: TResults?
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
MatchController.BossDataId = 0
MatchController.BossHealth = 0
MatchController.BossMaxHealth = 0
-- The two who have taken the most health off it (UserId 0 for nobody) and how much.
MatchController.BossFirstId = 0
MatchController.BossFirstDamage = 0
MatchController.BossSecondId = 0
MatchController.BossSecondDamage = 0
-- os.clock of the last wave done (MarkWaveDone), for the HUD's green edge.
MatchController.WaveDoneAt = -math.huge
-- The revive product on offer after a clear while down, or 0.
MatchController.ReviveProductId = 0
-- Each player's line on the squad screen, once the server has sent one.
MatchController.Scores = {} :: { [Player]: TScore }

-- Fired on every change of the above.
MatchController.OnChanged = Signal.new()
-- (position, amount): Gold the local player already earned, to draw as coins.
MatchController.OnCoins = Signal.new()
-- (buyer, where it was set off, bodies alive as it started): NUKE ALL was used. The kills follow as the blast rolls
-- out (EnemiesCore.NUKE_SPEED).
MatchController.OnNukedAll = Signal.new()
-- (buyer): HEAL ALL was used.
MatchController.OnHealedAll = Signal.new()
-- (buyer, amount): a Gold pack was bought. The buyer's Gold already holds it.
MatchController.OnGoldBought = Signal.new()

-- The newest round MarkWaveDone has greeted.
local waveDoneRound = 0

-- A wave is done for the player: its upgrade cards were dealt, or it was cleared. The cards come on the wave's kill
-- count and the clear when its last body is gone, which a skipped wave can hold back, so whichever comes first
-- greets it (the HUD's green edge and the cue) and the other is not a second greeting.
function MatchController.MarkWaveDone(round: number)
	if round <= waveDoneRound then return end
	waveDoneRound = round
	MatchController.WaveDoneAt = os.clock()
	SoundsCore.PlayUINamed("UI", "WaveDone")
end

function MatchController.VoteStart()
	ClientNetworkRounds.VoteStart.Fire()
end

function MatchController.SetAutoSkip(isOn: boolean)
	ClientNetworkRounds.SetAutoSkip.Fire(isOn)
end

-- PLAY AGAIN on the results. The count comes back from the server.
function MatchController.VotePlayAgain()
	local results = MatchController.Results
	if not results or results.HasVoted then return end
	results.HasVoted = true
	ClientNetworkGame.VotePlayAgain.Fire()
	MatchController.OnChanged:Fire()
end

function MatchController.LeaveToLobby()
	if MatchController.Results then ClientNetworkGame.LeaveToLobby.Fire() end
end

-- WATCH AD on the results: the server shows the ad, and its reward arrives as a doubling (GemsDoubled).
function MatchController.WatchAd()
	local results = MatchController.Results
	if not results or not results.CanWatchAd then return end
	results.CanWatchAd = false
	ClientNetworkGame.WatchAd.Fire()
	MatchController.OnChanged:Fire()
end

-- A purchase prompt opened from the results is up, or was closed: the countdown waits for it.
function MatchController.SetBuying(isBuying: boolean)
	if MatchController.Results then ClientNetworkGame.SetBuying.Fire(isBuying) end
end

local function changed()
	MatchController.OnChanged:Fire()
end

-- Asks whether an ad can be shown for `results`' doubling. One answer is good for one ad. Yields.
local function checkAd(results: TResults)
	local ok, answer = pcall(function()
		return AdService:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
	end)
	if MatchController.Results ~= results or results.DoubleProductId == 0 then return end
	results.CanWatchAd = ok and answer.AdAvailabilityResult == Enum.AdAvailabilityResult.IsAvailable
	changed()
end

-- The server's clock stops under the results and runs again after them, and this side's follows it (TimeController),
-- so a countdown or a skip that was running when the squad fell picks up where it was.
local function leaveResults()
	MatchController.IsRunning = true
	MatchController.IsEnded = false
	MatchController.Results = nil
end

ServerNetworkGame.MatchStarted.On(function(mapIndex: number)
	local map = MapsCore.LIST[mapIndex]
	MatchController.MapName = if map then map.Name else MapsCore.DEFAULT
	leaveResults()
	changed()
end)

ServerNetworkGame.MatchEnded.On(function(results: NetworkTypes.Server_Game_Results)
	MatchController.IsRunning = false
	MatchController.IsEnded = true
	MatchController.ReviveProductId = results.ReviveProductId
	MatchController.Results = {
		Wave = results.Wave,
		IsNewBest = results.IsNewBest,
		SquadKills = results.SquadKills,
		SecondsSurvived = results.SecondsSurvived,
		Gems = results.Gems,
		DoubleProductId = results.DoubleProductId,
		CanWatchAd = false,
		Doubled = 0,
		DoubledAt = -math.huge,
		ReturnAt = os.clock() + results.ReturnSeconds,
		ReturnSeconds = results.ReturnSeconds,
		IsReturnHeld = false,
		ReturnTotal = results.ReturnSeconds,
		Votes = 0,
		VotesNeeded = 0,
		HasVoted = false,
	}
	MusicController.SetLevel("Tension", 0)
	changed()
	if results.DoubleProductId ~= 0 then task.spawn(checkAd, MatchController.Results) end
end)

ServerNetworkGame.MatchResumed.On(function()
	leaveResults()
	MatchController.ReviveProductId = 0
	changed()
end)

ServerNetworkGame.PlayAgainVotes.On(function(votes: number, needed: number)
	local results = MatchController.Results
	if not results then return end
	results.Votes = votes
	results.VotesNeeded = needed
	changed()
end)

ServerNetworkGame.ReturnTimer.On(function(seconds: number, isHeld: boolean)
	local results = MatchController.Results
	if not results then return end
	results.ReturnAt = os.clock() + seconds
	results.ReturnSeconds = seconds
	results.IsReturnHeld = isHeld
	changed()
end)

ServerNetworkGame.GemsDoubled.On(function(gems: number)
	local results = MatchController.Results
	if not results then return end
	results.Doubled = gems
	results.DoubledAt = os.clock()
	results.DoubleProductId = 0
	changed()
end)

ServerNetworkGame.NukedAll.On(function(buyer: Player, origin: Vector3, bodies: number)
	MatchController.OnNukedAll:Fire(buyer, origin, bodies)
end)

ServerNetworkGame.HealedAll.On(function(buyer: Player)
	MatchController.OnHealedAll:Fire(buyer)
end)

ServerNetworkGame.GoldBought.On(function(buyer: Player, amount: number)
	MatchController.OnGoldBought:Fire(buyer, amount)
end)

ServerNetworkGame.Score.On(function(player: Player, classId: number, kills: number, deaths: number, gold: number)
	MatchController.Scores[player] = { ClassId = classId, Kills = kills, Deaths = deaths, Gold = gold }
	changed()
end)

ServerNetworkRounds.Preparing.On(function(round: number, seconds: number, isBoss: boolean)
	MatchController.Round = round
	MatchController.IsPreparing = true
	MatchController.IsBossRound = isBoss
	MatchController.PrepareEndsAt = TimeCore.GameClock + seconds
	MusicController.SetLevel("Tension", 0)
	changed()
end)

ServerNetworkRounds.Started.On(function(round: number, bodies: number)
	-- A new run counts its waves from 1 again.
	if round == 1 then waveDoneRound = 0 end
	MatchController.Round = round
	MatchController.IsPreparing = false
	MatchController.SkipOpensAt = TimeCore.GameClock + RoundCore.GetSkipAfterSeconds(round)
	MatchController.Remaining = bodies
	MatchController.ReviveProductId = 0
	local climb = math.min(1, (round - 1) / (RoundCore.BOSS_EVERY - 1))
	MusicController.SetLevel("Tension", TENSION_FIRST + (TENSION_PEAK - TENSION_FIRST) * climb)
	changed()
end)

ServerNetworkRounds.Remaining.On(function(remaining: number)
	MatchController.Remaining = remaining
	changed()
end)

-- Only the newest round's clear empties the count: an older one skipped past clears with the newer still open.
ServerNetworkRounds.Cleared.On(function(round: number)
	MatchController.MarkWaveDone(round)
	if round ~= MatchController.Round then return end
	MatchController.Remaining = 0
	changed()
end)

ServerNetworkRounds.Votes.On(function(votes: number, needed: number)
	MatchController.Votes = votes
	MatchController.VotesNeeded = needed
	changed()
end)

-- Nothing here shows them (the Gems come with the results, the XP is the lobby's), but an event nobody listens to
-- keeps every payload it is sent.
ServerNetworkRounds.Rewards.On(function() end)

ServerNetworkRounds.ReviveOffer.On(function(productId: number)
	MatchController.ReviveProductId = productId
	changed()
end)

ServerNetworkEnemies.BossHealth.On(
	function(
		dataId: number,
		health: number,
		maxHealth: number,
		firstId: number,
		firstDamage: number,
		secondId: number,
		secondDamage: number
	)
		MatchController.BossDataId = dataId
		MatchController.BossHealth = health
		MatchController.BossMaxHealth = maxHealth
		MatchController.BossFirstId = firstId
		MatchController.BossFirstDamage = firstDamage
		MatchController.BossSecondId = secondId
		MatchController.BossSecondDamage = secondDamage
		changed()
	end
)

ServerNetworkEconomy.Gold.On(function(gold: number)
	MatchController.Gold = gold
	changed()
end)

ServerNetworkEconomy.Coins.On(function(position: Vector3, amount: number)
	MatchController.OnCoins:Fire(position, amount)
	DamageNumbersController.ShowGold(position, amount)
end)

MatchController.OnPlayerDisconnected = function(player: Player)
	MatchController.Scores[player] = nil
end :: TPlayerEvents.OnPlayerDisconnected

MatchController.OnStart = function()
	ContextActionService:BindAction("VoteStart", function(_, state)
		if state == Enum.UserInputState.Begin then MatchController.VoteStart() end
		return Enum.ContextActionResult.Sink
	end, false, MatchController.SKIP_KEY)
	-- Last thing on start: every module's network listeners were connected when it loaded.
	ClientNetworkGame.GameLoaded.Fire()
end

return Ignis.Register(MatchController)
