-- Game place client entry point.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)

local Ignis = require(ReplicatedStorage.Packages.Ignis)

Ignis.LoadDescendants(script.Parent:WaitForChild("GlobalClient").Controllers)
Ignis.LoadDescendants(script.Controllers)
Ignis.LoadDescendants(ReplicatedStorage.GlobalShared.Core)
Ignis.LoadDescendants(ReplicatedStorage.GlobalShared.Modding)
Ignis.LoadDescendants(ReplicatedStorage.Shared.Core)

Ignis.Ignite()
