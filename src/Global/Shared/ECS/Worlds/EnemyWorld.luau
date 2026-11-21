local ReplicatedStorage = game:GetService("ReplicatedStorage")
local jecs = require(ReplicatedStorage.Packages.jecs)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
require(ReplicatedStorage.GlobalShared.ECS.Tags) -- Required for the meta (Tags module side-effects)
local jabby = require(ReplicatedStorage.Packages.jabby)

local EnemyWorld = jecs.world()

jabby.register({
	applet = jabby.applets.world,
	name = "Enemy",
	configuration = {
		world = EnemyWorld,
	},
})

-- Deleting a parent deletes its ChildOf children with it.
EnemyWorld:add(jecs.ChildOf, jecs.pair(jecs.OnDeleteTarget, jecs.Delete))

-- An entity's Cleanup callback runs as the component leaves it.
EnemyWorld:removed(Components.Cleanup, function(entity)
	local callback = EnemyWorld:get(entity, Components.Cleanup)
	if callback ~= nil then callback(entity) end
end)

return EnemyWorld
