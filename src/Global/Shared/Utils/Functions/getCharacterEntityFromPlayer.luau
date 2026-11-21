local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local Tags = require(ReplicatedStorage.GlobalShared.ECS.Tags)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local jecs = require(ReplicatedStorage.Packages.jecs)

local PlayerEntityQuery = World:query(Components.Player):cached()

return function(player: Player): jecs.Entity<any>?
	for entity, p in PlayerEntityQuery do
		if p == player then
			for characterEntity in World:query(jecs.pair(jecs.ChildOf, entity), Tags.Character) do
				return characterEntity
			end
		end
	end

	return nil
end
