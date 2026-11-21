-- Mirrors the part of a player's profile the HUD and menus show to their client (Profile.Sync), once it loads and
-- after every change. One event with the whole summary rather than one per field: it changes a few times a run.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(ServerScriptService.GlobalServer.NetworkMeta)
local DatabaseService = require(script.Parent.DatabaseService)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)
local TProfile = require(ReplicatedStorage.Types.TProfile)

local ServerNetworkProfile = NetworkMeta.Server.Profile

local ProfileSyncService = {}

local function send(player: Player, profile: TProfile.TProfile)
	ServerNetworkProfile.Sync.Fire(player, profile.Gems, profile.Settings.IsAutoSkip, profile.Level, profile.Xp)
end

ProfileSyncService.OnDataLoaded = function(player: Player)
	local profile = DatabaseService.Get(player)
	if profile then send(player, profile) end
end :: TPlayerEvents.OnDataLoaded

DatabaseService.OnProfileChanged:Connect(send)

return Ignis.Register(ProfileSyncService)
