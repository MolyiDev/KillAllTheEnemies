-- The client's half of the character id handshake (GlobalServer CharacterIdsService): map each id the
-- server announces to the local entity for that player's rig, then answer CharacterReady so the server can
-- register it. The rig may replicate after the announcement, so the mapping waits for it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Network = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Network)
local CharacterCore = require(ReplicatedStorage.GlobalShared.Core.CharacterCore)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local getCharacterEntityFromPlayer =
	require(ReplicatedStorage.GlobalShared.Utils.Functions.getCharacterEntityFromPlayer)

local ServerNetworkCharacters = Network.Server.Characters
local ClientNetworkCharacters = Network.Client.Characters

-- Matches the server's ACK_TIMEOUT: past it the server has stopped waiting, so this stops too.
local MAP_TIMEOUT_SECONDS = 5

local CharacterController = {}

local LocalPlayer = Players.LocalPlayer

function CharacterController.GetLocalCharacterId(): number?
	local entity = getCharacterEntityFromPlayer(LocalPlayer)
	return if entity then World:get(entity, Components.InstanceId) else nil
end

ServerNetworkCharacters.Added.On(function(player: Player, instanceId: number)
	local deadline = os.clock() + MAP_TIMEOUT_SECONDS
	local entity = getCharacterEntityFromPlayer(player)

	while not entity or World:get(entity, Components.Model) ~= player.Character do
		if os.clock() > deadline or not player.Parent then return end
		task.wait()
		entity = getCharacterEntityFromPlayer(player)
	end

	CharacterCore.AddCharacter(entity, instanceId)
	ClientNetworkCharacters.CharacterReady.Fire(instanceId)
end)

ServerNetworkCharacters.Removed.On(function(instanceId: number)
	CharacterCore.RemoveCharacter(instanceId)
end)

return Ignis.Register(CharacterController)
