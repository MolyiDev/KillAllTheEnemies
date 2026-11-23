-- Characters' network ids, in both places. A character is given an InstanceId and every client is told
-- (Characters.Added); it is registered (CharacterCore.AddCharacter) only once every client has acknowledged it
-- (CharacterReady): registered sooner, a kill credit, a shot or a damage target could name an id some client cannot
-- map yet. The client's half is CharacterController.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Network = require(ServerScriptService.GlobalServer.Network)
local CharacterCore = require(ReplicatedStorage.GlobalShared.Core.CharacterCore)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local Tags = require(ReplicatedStorage.GlobalShared.ECS.Tags)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local IdGenerator = require(ReplicatedStorage.GlobalShared.Utils.IdGenerator)
local getPlayerFromCharacterEntity =
	require(ReplicatedStorage.GlobalShared.Utils.Functions.getPlayerFromCharacterEntity)
local EGenerator = require(ReplicatedStorage.Types.Enums.EGenerator)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local ServerNetworkCharacters = Network.Server.Characters
local ClientNetworkCharacters = Network.Client.Characters

-- Ids 1..1000; 0 is reserved on the wire for "nobody" (a kill credited to no one).
local IdEntityGen = IdGenerator.new(EGenerator.CharacterEntities, 0, 1000)

-- Matches CharacterController's MAP_TIMEOUT_SECONDS: past it the clients have stopped trying too.
local ACK_TIMEOUT_SECONDS = 5

type TPendingAck = { remaining: number, acked: { [Player]: boolean }, signal: Signal.Signal<> }

local CharacterIdsService = {}

-- (characterEntity, player) once the id is registered on every side.
CharacterIdsService.OnCharacterReady = Signal.new()

local pendingAcks: { [number]: TPendingAck } = {}

local function releaseAck(instanceId: number)
	local pending = pendingAcks[instanceId]
	if not pending then return end
	pendingAcks[instanceId] = nil
	pending.signal:Fire()
end

CharacterIdsService.OnPlayerConnected = function(player: Player)
	-- Late joiners learn the characters that already exist.
	for characterEntity, instanceId in World:query(Components.InstanceId):with(Tags.Character) do
		local owner = getPlayerFromCharacterEntity(characterEntity)
		if owner and owner ~= player then ServerNetworkCharacters.Added.Fire(player, owner, instanceId) end
	end
end :: TPlayerEvents.OnPlayerConnected

CharacterIdsService.OnPlayerDisconnected = function(player: Player)
	-- Every handshake still waiting on this player stops waiting for them.
	for instanceId, pending in pendingAcks do
		if pending.acked[player] then continue end
		pending.acked[player] = true
		pending.remaining -= 1
		if pending.remaining <= 0 then releaseAck(instanceId) end
	end
end :: TPlayerEvents.OnPlayerDisconnected

CharacterIdsService.OnCharacterAdded = function(character, characterEntity)
	task.defer(function()
		local player = getPlayerFromCharacterEntity(characterEntity)
		if not player or player.Character ~= character then return end

		local instanceId = IdEntityGen:Generate()
		while CharacterCore.GetCharacterByInstanceId(instanceId) do
			instanceId = IdEntityGen:Generate()
		end

		local players = Players:GetPlayers()
		local pending: TPendingAck = { remaining = #players, acked = {}, signal = Signal.new() }
		pendingAcks[instanceId] = pending
		ServerNetworkCharacters.Added.FireAll(player, instanceId)
		task.delay(ACK_TIMEOUT_SECONDS, releaseAck, instanceId)
		pending.signal:Wait()
		pending.signal:Destroy()

		-- The rig may have been replaced or removed while the clients answered.
		if player.Character ~= character or not World:contains(characterEntity) then return end
		CharacterCore.AddCharacter(characterEntity, instanceId)
		CharacterIdsService.OnCharacterReady:Fire(characterEntity, player)
	end)
end :: TCharacterEvents.OnCharacterAdded

CharacterIdsService.OnCharacterRemoving = function(_, characterEntity)
	local instanceId = World:get(characterEntity, Components.InstanceId)
	if not instanceId then return end
	CharacterCore.RemoveCharacter(instanceId)
	ServerNetworkCharacters.Removed.FireAll(instanceId)
end :: TCharacterEvents.OnCharacterRemoving

-- Deduped per player, so a client spamming CharacterReady cannot count for anyone else.
ClientNetworkCharacters.CharacterReady.On(function(player: Player, instanceId: number)
	local pending = pendingAcks[instanceId]
	if not pending or pending.acked[player] then return end
	pending.acked[player] = true
	pending.remaining -= 1
	if pending.remaining <= 0 then releaseAck(instanceId) end
end)

return Ignis.Register(CharacterIdsService)
