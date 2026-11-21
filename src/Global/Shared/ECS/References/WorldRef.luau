local ReplicatedStorage = game:GetService("ReplicatedStorage")
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local References = require(script.Parent)

return References.new(World)
