-- The gun each player wears on their back (TProfile.Loadout.Shown) to everybody (Loadout.Worn), as their profile loads
-- and when it changes, and everybody else's to a player who just loaded. Only the lobby wears it; every client draws it
-- (BackGunController). The lobby's weapons screen changes it (LoadoutService).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(ServerScriptService.GlobalServer.NetworkMeta)
local DatabaseService = require(ServerScriptService.GlobalServer.Services.DatabaseService)
local LoadoutCore = require(ReplicatedStorage.GlobalShared.Core.LoadoutCore)
local TData = require(ReplicatedStorage.Types.TData)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)
local TProfile = require(ReplicatedStorage.Types.TProfile)

local ServerNetworkLoadout = NetworkMeta.Server.Loadout

local BackGunService = {}

-- Each loaded player's gun Id as everybody last heard it, 0 for none.
local sent: { [Player]: number } = {}

-- The gun `profile` wears, nil for none. A gun no longer owned, or no longer in the data, is not worn.
function BackGunService.ShownOf(profile: TProfile.TProfile): TData.TGun?
	local name = profile.Loadout.Shown
	local gun = if name then LoadoutCore.ByName[name] else nil
	if not gun or not LoadoutCore.LevelOf(profile.Loadout.Owned, gun) then return nil end
	return gun
end

local function broadcast(player: Player, profile: TProfile.TProfile)
	local gun = BackGunService.ShownOf(profile)
	local gunId = if gun then gun.Id else 0
	if sent[player] == gunId then return end
	sent[player] = gunId
	ServerNetworkLoadout.Worn.FireAll(player, gunId)
end

BackGunService.OnDataLoaded = function(player: Player)
	local profile = DatabaseService.Get(player)
	if not profile then return end
	-- Nobody has drawn a gun for a player who just loaded, so wearing none needs no word.
	sent[player] = 0
	broadcast(player, profile)
	for other, gunId in sent do
		if other ~= player and gunId ~= 0 and other.Parent == Players then
			ServerNetworkLoadout.Worn.Fire(player, other, gunId)
		end
	end
end :: TPlayerEvents.OnDataLoaded

BackGunService.OnPlayerDisconnected = function(player: Player)
	sent[player] = nil
end :: TPlayerEvents.OnPlayerDisconnected

DatabaseService.OnProfileChanged:Connect(function(player: Player, profile: TProfile.TProfile)
	-- A write before the profile is announced is told by OnDataLoaded.
	if sent[player] == nil then return end
	broadcast(player, profile)
end)

return Ignis.Register(BackGunService)
