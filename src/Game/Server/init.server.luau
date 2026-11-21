-- Game place server entry point: the match services, then the shared ones, then ignite.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)

local Ignis = require(ReplicatedStorage.Packages.Ignis)

Ignis.LoadDescendants(script.Services)
Ignis.LoadDescendants(script.Parent.GlobalServer.Services)
Ignis.LoadDescendants(ReplicatedStorage.GlobalShared.Core)
Ignis.LoadDescendants(ReplicatedStorage.GlobalShared.Modding)
Ignis.LoadDescendants(ReplicatedStorage.Shared.Core)

Ignis.Ignite()
