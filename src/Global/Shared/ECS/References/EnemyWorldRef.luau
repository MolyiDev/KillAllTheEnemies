local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EnemyWorld = require(ReplicatedStorage.GlobalShared.ECS.Worlds.EnemyWorld)
local References = require(script.Parent)

return References.new(EnemyWorld)
