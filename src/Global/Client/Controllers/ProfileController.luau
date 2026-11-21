-- The client's copy of the part of its profile the server mirrors (Profile.Sync), for menus and the HUD. Read
-- only: every change is a request to the server, which answers with a new Sync.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Signal = require(ReplicatedStorage.Packages.Signal)
local NetworkMeta = require(StarterPlayer.StarterPlayerScripts.GlobalClient.NetworkMeta)

local ServerNetworkProfile = NetworkMeta.Server.Profile

local ProfileController = {}

ProfileController.IsLoaded = false
ProfileController.Gems = 0
ProfileController.IsAutoSkip = false
ProfileController.Level = 1
ProfileController.Xp = 0

-- Fired after every Sync.
ProfileController.OnChanged = Signal.new()

ServerNetworkProfile.Sync.On(function(gems: number, isAutoSkip: boolean, level: number, xp: number)
	ProfileController.IsLoaded = true
	ProfileController.Gems = gems
	ProfileController.IsAutoSkip = isAutoSkip
	ProfileController.Level = level
	ProfileController.Xp = xp
	ProfileController.OnChanged:Fire()
end)

return Ignis.Register(ProfileController)
