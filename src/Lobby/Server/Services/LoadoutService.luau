-- The weapons screen's purchases (TProfile.Loadout, LoadoutCore): buying a gun with Gems, putting an owned one in its
-- tier, raising one a level, and wearing one on the back (BackGunService tells everybody). Every request is answered with the player's whole loadout (Loadout.Sync), a refused
-- one too, so the screen waiting on it always hears back.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(ServerScriptService.GlobalServer.NetworkMeta)
local BackGunService = require(script.Parent.BackGunService)
local DatabaseService = require(ServerScriptService.GlobalServer.Services.DatabaseService)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local LoadoutCore = require(ReplicatedStorage.GlobalShared.Core.LoadoutCore)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local ServerNetworkLoadout = NetworkMeta.Server.Loadout
local ClientNetworkLoadout = NetworkMeta.Client.Loadout

local LoadoutService = {}

-- Sends the player's whole loadout (Loadout.Sync): after each of the screen's requests, and after anything else that
-- gives him a gun.
function LoadoutService.Sync(player: Player)
	local profile = DatabaseService.Get(player)
	if not profile then return end

	local owned, levels = {}, {}
	local count = 0
	for _, gun in DataCore.Guns.All do
		local level = LoadoutCore.LevelOf(profile.Loadout.Owned, gun)
		if not level then continue end
		count += 1
		owned[count] = gun.Id
		levels[count] = level
	end

	local equipped = table.create(LoadoutCore.TIERS)
	for tier = 1, LoadoutCore.TIERS do
		equipped[tier] = LoadoutCore.EquippedOf(profile.Loadout.Equipped, tier).Id
	end

	local shown = BackGunService.ShownOf(profile)
	ServerNetworkLoadout.Sync.Fire(player, owned, levels, equipped, if shown then shown.Id else 0)
end

LoadoutService.OnDataLoaded = function(player: Player)
	LoadoutService.Sync(player)
end :: TPlayerEvents.OnDataLoaded

-- The handlers need no character: the loadout is the player's own, changed from the menu whatever his body is doing.
-- Each check is made again inside the write, on the profile as it is then.
ClientNetworkLoadout.Buy.On(function(player: Player, gunId: number)
	local gun = DataCore.Guns.ById[gunId]
	local hasBought = gun ~= nil
		and DatabaseService.Update(player, function(profile)
			if LoadoutCore.LevelOf(profile.Loadout.Owned, gun) then return false end
			if profile.Gems < gun.Price then return false end
			profile.Gems -= gun.Price
			profile.Loadout.Owned[gun.Name] = 1
			profile.Loadout.Equipped[tostring(gun.Tier)] = gun.Name
			return true
		end)

	if hasBought then DatabaseService.SaveAsync(player) end
	LoadoutService.Sync(player)
end)

ClientNetworkLoadout.Equip.On(function(player: Player, gunId: number)
	local gun = DataCore.Guns.ById[gunId]
	if gun then
		DatabaseService.Update(player, function(profile)
			if not LoadoutCore.LevelOf(profile.Loadout.Owned, gun) then return false end
			local tier = tostring(gun.Tier)
			if LoadoutCore.EquippedOf(profile.Loadout.Equipped, gun.Tier) == gun then return false end
			-- A starter is what an empty tier holds, so putting one back is clearing the tier.
			profile.Loadout.Equipped[tier] = if gun.Price == 0 then nil else gun.Name
			return true
		end)
	end

	LoadoutService.Sync(player)
end)

ClientNetworkLoadout.Upgrade.On(function(player: Player, gunId: number)
	local gun = DataCore.Guns.ById[gunId]
	local hasUpgraded = gun ~= nil
		and DatabaseService.Update(player, function(profile)
			local level = LoadoutCore.LevelOf(profile.Loadout.Owned, gun)
			if not level then return false end
			local cost = LoadoutCore.UpgradeCost(gun, level)
			if not cost or profile.Gems < cost then return false end
			profile.Gems -= cost
			profile.Loadout.Owned[gun.Name] = level + 1
			return true
		end)

	if hasUpgraded then DatabaseService.SaveAsync(player) end
	LoadoutService.Sync(player)
end)

-- 0 takes the gun off the back. Not saved at once: it is a look, and the next save carries it.
ClientNetworkLoadout.Show.On(function(player: Player, gunId: number)
	local gun = DataCore.Guns.ById[gunId]
	if gun or gunId == 0 then
		DatabaseService.Update(player, function(profile)
			if gun and not LoadoutCore.LevelOf(profile.Loadout.Owned, gun) then return false end
			local name = if gun then gun.Name else nil
			if profile.Loadout.Shown == name then return false end
			profile.Loadout.Shown = name
			return true
		end)
	end

	LoadoutService.Sync(player)
end)

return Ignis.Register(LoadoutService)
