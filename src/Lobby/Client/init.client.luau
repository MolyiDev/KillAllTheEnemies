-- Lobby place client entry point.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ignis = require(ReplicatedStorage.Packages.Ignis)

Ignis.LoadDescendants(script.Parent:WaitForChild("GlobalClient").Controllers)
Ignis.LoadDescendants(script.Controllers)
Ignis.LoadDescendants(ReplicatedStorage.GlobalShared.Core)
Ignis.LoadDescendants(ReplicatedStorage.GlobalShared.Modding)
Ignis.LoadDescendants(ReplicatedStorage.Shared.Core)

Ignis.Ignite()
