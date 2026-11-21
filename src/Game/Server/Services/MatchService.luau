-- The run, start to finish: wait for the party, run rounds until everybody is down, send them back to the lobby.
-- The first round waits for every player the pad sent (JoinData) to be loaded and known to every client, or until
-- WAIT_FOR_PARTY_SECONDS. A join with no token (Studio, a follow) is a party of one on the easy map. The first
-- arrival's token picks the map (arenaMap), so every map is played in this one place.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Network = require(ServerScriptService.GlobalServer.Network)
local PurchasesService = require(ServerScriptService.GlobalServer.Services.PurchasesService)
local JoinData = require(ServerScriptService.GlobalServer.Utils.JoinData)
local CharacterService = require(script.Parent.CharacterService)
local DefenseService = require(script.Parent.DefenseService)
local EconomyService = require(script.Parent.EconomyService)
local EnemiesService = require(script.Parent.EnemiesService)
local EnemyAttacksService = require(script.Parent.EnemyAttacksService)
local EnemyMovementService = require(script.Parent.EnemyMovementService)
local RoundService = require(script.Parent.RoundService)
local WeaponService = require(script.Parent.WeaponService)
local arenaMap = require(ServerScriptService.Server.Utils.arenaMap)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local MapsCore = require(ReplicatedStorage.GlobalShared.Core.MapsCore)
local ArenaCore = require(ReplicatedStorage.Shared.Core.ArenaCore)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)
local getCharacterIdFromPlayer = require(ReplicatedStorage.GlobalShared.Utils.Functions.getCharacterIdFromPlayer)
local EPlaceIds = require(ReplicatedStorage.Types.Enums.EPlaceIds)
local EProducts = require(ReplicatedStorage.Types.Enums.EProducts)
local TJoinData = require(ReplicatedStorage.Types.TJoinData)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local ServerNetworkGame = Network.Server.Game
local ServerNetworkEnemies = Network.Server.Enemies
local ServerNetworkRounds = Network.Server.Rounds
local ClientNetworkGame = Network.Client.Game

local Tune = table.freeze({
	WAIT_FOR_PARTY_SECONDS = 15,
	-- Once the whole party is in, a beat before the first round so nobody spawns into a fight.
	ALL_JOINED_SECONDS = 3,
	RETURN_TO_LOBBY_SECONDS = 8,
	RETURN_RETRIES = 3,
	RETURN_RETRY_SECONDS = 2,
})

local EMatchState = table.freeze({
	Waiting = 0,
	Running = 1,
	Ended = 2,
})

local MatchService = {}

MatchService.EMatchState = EMatchState
MatchService.State = EMatchState.Waiting
MatchService.SupposedPlayers = 0
MatchService.MapName = MapsCore.DEFAULT

local isArenaPlaced = false
local isArenaBaked = false
local isWaitOver = false
local waitThread: thread? = nil
local loadedPlayers: { [Player]: boolean } = {}
local fetchedPlayers: { [Player]: boolean } = {}
local dataPlayers: { [Player]: boolean } = {}
local readyPlayers: { [Player]: boolean } = {}
local takenTokens: { [string]: TJoinData.TMessage } = {}
local teleportTries: { [Player]: number } = {}

local function getAllEnemyIds(): { number }
	local ids = table.create(#DataCore.Enemies.All)
	for i, enemyData in DataCore.Enemies.All do
		ids[i] = enemyData.Id
	end

	return ids
end

local function startMatch()
	MatchService.State = EMatchState.Running
	if waitThread and coroutine.running() ~= waitThread then task.cancel(waitThread) end
	waitThread = nil

	local players = Players:GetPlayers()
	RoundService.RecordKey = MapsCore.RecordKey(MatchService.MapName, #players)
	TimeCore.Reset()
	EconomyService.ResetRun()
	WeaponService.ResetRun()

	ServerNetworkEnemies.TypesForMatch.FireAll(getAllEnemyIds())
	ServerNetworkGame.MatchStarted.FireAll()
	EnemyMovementService.IsRunning = true
	RoundService.Begin()
end

local function tryStart()
	if MatchService.State ~= EMatchState.Waiting or not isArenaBaked then return end
	local present = 0
	for _, player in Players:GetPlayers() do
		-- Everyone here must have loaded, had his token read and profile opened, and have a character every client
		-- knows.
		if not loadedPlayers[player] or not fetchedPlayers[player] or not dataPlayers[player] then return end
		if not readyPlayers[player] then return end
		present += 1
	end

	if present == 0 then return end

	-- Before the timeout, the whole party; after it, whoever made it.
	if not isWaitOver and present < math.max(MatchService.SupposedPlayers, 1) then return end
	if isWaitOver then
		startMatch()
		return
	end

	if waitThread then task.cancel(waitThread) end
	waitThread = task.delay(Tune.ALL_JOINED_SECONDS, startMatch)
end

local function resetRun()
	RoundService.Stop()
	EnemyMovementService.IsRunning = false
	EnemyAttacksService.Reset()
	EnemiesService.ClearAll()
	DefenseService.ClearAll()
end

-- Studio's loop, and the fallback when there is no lobby: clear the arena, bring everyone back, play again.
function MatchService.Restart()
	resetRun()
	MatchService.State = EMatchState.Waiting

	-- Only a character still standing with an id counts as ready; the revived register again through
	-- OnCharacterReady, which calls tryStart.
	for player in readyPlayers do
		if not getCharacterIdFromPlayer(player) or not CharacterService.IsAlive(player) then
			readyPlayers[player] = nil
		end
	end

	CharacterService.ReviveDead()
	isWaitOver = true
	tryStart()
end

-- One player at a time, so one who cannot be teleported does not hold back the rest.
local function teleportToLobby(player: Player)
	if not player.Parent then return end
	local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, EPlaceIds.Lobby, { player })
	if not ok then warn(`[MatchService] return of {player.Name} to the lobby failed: {err}`) end
end

local function returnToLobby()
	local players = Players:GetPlayers()
	if #players == 0 then return end

	-- Studio cannot teleport, and a place with no lobby yet has nowhere to go: run it again instead.
	if RunService:IsStudio() or EPlaceIds.Lobby == 0 then
		MatchService.Restart()
		return
	end

	for _, player in players do
		task.spawn(teleportToLobby, player)
	end
end

local function endMatch()
	if MatchService.State ~= EMatchState.Running then return end
	MatchService.State = EMatchState.Ended
	local roundsCleared = RoundService.LastCleared
	resetRun()
	ServerNetworkGame.MatchEnded.FireAll(roundsCleared, Tune.RETURN_TO_LOBBY_SECONDS)
	task.delay(Tune.RETURN_TO_LOBBY_SECONDS, returnToLobby)
end

local function checkWiped()
	if MatchService.State ~= EMatchState.Running then return end
	if CharacterService.CountAlive() > 0 then return end
	endMatch()
end

-- Yields while it bakes.
local function placeArena()
	if isArenaPlaced then return end
	isArenaPlaced = true
	arenaMap.Place(MatchService.MapName)
	ArenaCore.Bake()
	isArenaBaked = true
	tryStart()
end

MatchService.OnStart = function()
	waitThread = task.delay(Tune.WAIT_FOR_PARTY_SECONDS, function()
		waitThread = nil
		isWaitOver = true
		-- A token nobody could read (expired, or the store failed) plays the default map.
		task.spawn(placeArena)
		tryStart()
	end)
end

MatchService.OnPlayerConnected = function(player: Player)
	local token = JoinData.GetToken(player)
	if token then
		-- A party shares one token; the first of them to arrive reads it for all. A second arrival reading it at the
		-- same time finds it deleted, so only a read message places the map, never a missing one.
		local message = takenTokens[token] or JoinData.TakeAsync(token)
		if message then
			takenTokens[token] = message
			MatchService.SupposedPlayers = math.max(MatchService.SupposedPlayers, message.SupposedPlayers)
			if MapsCore.MAPS[message.MapName] and not isArenaPlaced then MatchService.MapName = message.MapName end
			task.spawn(placeArena)
		end
	else
		task.spawn(placeArena)
	end

	if not player.Parent then return end
	fetchedPlayers[player] = true
	tryStart()
end :: TPlayerEvents.OnPlayerConnected

-- Their profile is open. A late joiner into a running match is caught up on the round.
MatchService.OnDataLoaded = function(player: Player)
	dataPlayers[player] = true
	if MatchService.State == EMatchState.Running then
		ServerNetworkEnemies.TypesForMatch.Fire(player, getAllEnemyIds())
		ServerNetworkGame.MatchStarted.Fire(player)
		ServerNetworkRounds.Started.Fire(player, RoundService.Round, 0)
	end

	tryStart()
end :: TPlayerEvents.OnDataLoaded

MatchService.OnPlayerDisconnected = function(player: Player)
	loadedPlayers[player] = nil
	fetchedPlayers[player] = nil
	dataPlayers[player] = nil
	readyPlayers[player] = nil
	teleportTries[player] = nil
	-- Leaving can be what makes the rest of the party "everyone", or what leaves nobody standing.
	task.defer(tryStart)
	task.defer(checkWiped)
end :: TPlayerEvents.OnPlayerDisconnected

CharacterService.OnCharacterReady:Connect(function(_, player: Player)
	readyPlayers[player] = true
	tryStart()
end)

CharacterService.OnCharacterDied:Connect(checkWiped)

-- After a clear, every player who is down is offered a revive for the next round.
RoundService.OnRoundCleared:Connect(function()
	for _, player in Players:GetPlayers() do
		if EProducts.Revive ~= 0 and not CharacterService.IsAlive(player) then
			ServerNetworkRounds.ReviveOffer.Fire(player, EProducts.Revive)
		end
	end
end)

-- Charged only when it can be fulfilled: a running match, and he is down.
PurchasesService.Register(EProducts.Revive, function(player: Player)
	if MatchService.State ~= EMatchState.Running or CharacterService.IsAlive(player) then return false, nil end
	return true, function()
		CharacterService.Spawn(player)
	end
end)

-- The client's listeners are up. Nothing to validate: it only gates the start for this player.
ClientNetworkGame.GameLoaded.On(function(player: Player)
	loadedPlayers[player] = true
	tryStart()
end)

-- A teleport can fail after the call returns (the lobby busy, a flaky hop). A run that is over has nothing to keep
-- the player for, so it tries again, a few times, a moment later.
TeleportService.TeleportInitFailed:Connect(function(player: Player, result: Enum.TeleportResult, message: string)
	warn(`[MatchService] teleport of {player.Name} failed: {result.Name} {message}`)
	if MatchService.State ~= EMatchState.Ended then return end
	local tries = (teleportTries[player] or 0) + 1
	teleportTries[player] = tries
	if tries > Tune.RETURN_RETRIES then return end
	task.delay(Tune.RETURN_RETRY_SECONDS, teleportToLobby, player)
end)

return Ignis.Register(MatchService)
