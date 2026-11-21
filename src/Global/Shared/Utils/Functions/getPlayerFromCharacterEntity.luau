local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local jecs = require(ReplicatedStorage.Packages.jecs)

return function(characterEntity: jecs.Entity<any>): Player?
	local playerEntity = World:parent(characterEntity)
	if not playerEntity then return nil end
	return World:get(playerEntity, Components.Player)
end
