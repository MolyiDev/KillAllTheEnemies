local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local getCharacterEntityFromPlayer = require(script.Parent.getCharacterEntityFromPlayer)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)

return function(player: Player): number?
	local character = getCharacterEntityFromPlayer(player)
	if not character then return nil end
	return World:get(character, Components.InstanceId)
end
