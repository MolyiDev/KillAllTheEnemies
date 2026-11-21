-- The conch command console on the client: its lifecycle, and the open key once the server has granted a role.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Conch = require(ReplicatedStorage.Packages.conch)
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(StarterPlayer.StarterPlayerScripts.GlobalClient.NetworkMeta)
local ConsoleUI = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.ConsoleUI)
-- Registers the server commands' argument types here too, so their replicated commands resolve.
require(ReplicatedStorage.Types.CommandTypes)

local ConsoleController = {}

local OPEN_KEY = Enum.KeyCode.Backquote

local isBound = false

Conch.register_default_commands()
Conch.initiate_default_lifecycle()

-- Bound only for a player the server gave a role, so nobody else ever gets the open key.
NetworkMeta.Server.Console.AccessGranted.On(function()
	if isBound then return end
	isBound = true
	ConsoleUI.bind_to(OPEN_KEY)
end)

return Ignis.Register(ConsoleController)
