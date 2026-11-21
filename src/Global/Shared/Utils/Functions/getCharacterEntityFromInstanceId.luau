local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldRef = require(ReplicatedStorage.GlobalShared.ECS.References.WorldRef)
local jecs = require(ReplicatedStorage.Packages.jecs)

return function(instanceId: number): jecs.Entity<any>?
	return WorldRef:Search(instanceId)
end
