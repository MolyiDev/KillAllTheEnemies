-- Lobby avatars: loaded, and loaded again when one dies. CharacterAutoLoads is false in lobby.project.json, so this is
-- the only thing that loads them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local loadCharacter = require(ServerScriptService.GlobalServer.Utils.loadCharacter)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local getPlayerFromCharacterEntity =
	require(ReplicatedStorage.GlobalShared.Utils.Functions.getPlayerFromCharacterEntity)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local RESPAWN_SECONDS = 3

local CharacterService = {}

local function spawn(player: Player)
	local ok, err = pcall(loadCharacter, player)
	if not ok then warn(`[CharacterService] could not load {player.Name}: {err}`) end
end

CharacterService.OnPlayerConnected = function(player: Player)
	task.spawn(spawn, player)
end :: TPlayerEvents.OnPlayerConnected

CharacterService.OnCharacterAdded = function(character, characterEntity)
	local humanoid = World:get(characterEntity, Components.Humanoid)
	if not humanoid then return end
	humanoid.Died:Once(function()
		local player = getPlayerFromCharacterEntity(characterEntity)
		if not player then return end
		task.delay(RESPAWN_SECONDS, function()
			if player.Character == character then spawn(player) end
		end)
	end)
end :: TCharacterEvents.OnCharacterAdded

return Ignis.Register(CharacterService)
