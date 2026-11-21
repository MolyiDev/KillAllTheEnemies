-- Lobby place server entry point.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ignis = require(ReplicatedStorage.Packages.Ignis)

Ignis.LoadDescendants(script.Services)
Ignis.LoadDescendants(script.Parent.GlobalServer.Services)
Ignis.LoadDescendants(ReplicatedStorage.GlobalShared.Core)
Ignis.LoadDescendants(ReplicatedStorage.GlobalShared.Modding)
Ignis.LoadDescendants(ReplicatedStorage.Shared.Core)

Ignis.Ignite()
