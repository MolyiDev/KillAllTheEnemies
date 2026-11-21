local ReplicatedStorage = game:GetService("ReplicatedStorage")
local jecs = require(ReplicatedStorage.Packages.jecs)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
require(ReplicatedStorage.GlobalShared.ECS.Tags) -- Required for the meta (Tags module side-effects)
local jabby = require(ReplicatedStorage.Packages.jabby)

local World = jecs.world()

jabby.register({
	applet = jabby.applets.world,
	name = "Default",
	configuration = {
		world = World,
	},
})

-- Deleting a parent deletes its ChildOf children with it.
World:add(jecs.ChildOf, jecs.pair(jecs.OnDeleteTarget, jecs.Delete))

-- An entity's Cleanup callback runs as the component leaves it.
World:removed(Components.Cleanup, function(entity)
	local callback = World:get(entity, Components.Cleanup)
	if callback ~= nil then callback(entity) end
end)

return World
