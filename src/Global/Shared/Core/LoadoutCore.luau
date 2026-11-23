-- The loadout's rules, the same on both sides: one gun a tier, the starters owned by everybody, a gun's level and what
-- the next one costs and adds. The profile keeps guns by Name (TProfile.Loadout); the wire carries their Ids.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local TData = require(ReplicatedStorage.Types.TData)

local Tune = table.freeze({
	-- Each level past the first adds this share of the gun's base damage.
	DAMAGE_PER_LEVEL = 0.1,
	-- The first upgrade costs this share of the gun's price, each one after it GROWTH times the one before; a starter
	-- is priced as STARTER_PRICE. Rounded to ROUND_TO Gems.
	UPGRADE_SHARE = 0.12,
	UPGRADE_GROWTH = 1.5,
	STARTER_PRICE = 500,
	ROUND_TO = 25,
})

local LoadoutCore = {}

LoadoutCore.TIERS = 4
LoadoutCore.MAX_LEVEL = 5

-- Each tier's guns, its starter first and the rest cheapest first: the order the screen deals them in.
LoadoutCore.ByTier = {} :: { [number]: { TData.TGun } }
-- Each tier's free gun, the one it holds until another is equipped.
LoadoutCore.Starters = {} :: { [number]: TData.TGun }
LoadoutCore.ByName = {} :: { [string]: TData.TGun }

for tier = 1, LoadoutCore.TIERS do
	LoadoutCore.ByTier[tier] = {}
end
for _, gun in DataCore.Guns.All do
	LoadoutCore.ByName[gun.Name] = gun
	table.insert(LoadoutCore.ByTier[gun.Tier], gun)
	if gun.Price == 0 then LoadoutCore.Starters[gun.Tier] = gun end
end
for _, guns in LoadoutCore.ByTier do
	table.sort(guns, function(a: TData.TGun, b: TData.TGun): boolean
		if a.Price ~= b.Price then return a.Price < b.Price end
		return a.Id < b.Id
	end)
end
table.freeze(LoadoutCore.ByTier)
table.freeze(LoadoutCore.Starters)
table.freeze(LoadoutCore.ByName)

-- A gun's level, nil when it is not owned. `owned` is the profile's Name -> level; a starter nobody upgraded is not in
-- it and is level 1.
function LoadoutCore.LevelOf(owned: { [string]: number }, gun: TData.TGun): number?
	local level = owned[gun.Name]
	if level then return level end
	return if gun.Price == 0 then 1 else nil
end

-- The gun a tier holds. `equipped` is the profile's tier ("1".."4") -> Name; a tier never picked holds its starter.
function LoadoutCore.EquippedOf(equipped: { [string]: string }, tier: number): TData.TGun
	local name = equipped[tostring(tier)]
	local gun = if name then LoadoutCore.ByName[name] else nil
	return if gun and gun.Tier == tier then gun else LoadoutCore.Starters[tier]
end

-- Gems from `level` to the next one of something bought for `price` Gems (0: free, priced as a starter). The class
-- abilities level on the same curve (AbilitiesCore).
function LoadoutCore.LevelCost(price: number, level: number): number
	local base = if price > 0 then price else Tune.STARTER_PRICE
	local cost = base * Tune.UPGRADE_SHARE * Tune.UPGRADE_GROWTH ^ (level - 1)
	return math.max(Tune.ROUND_TO, math.round(cost / Tune.ROUND_TO) * Tune.ROUND_TO)
end

-- Gems from `level` to the next one, nil at the top.
function LoadoutCore.UpgradeCost(gun: TData.TGun, level: number): number?
	if level >= LoadoutCore.MAX_LEVEL then return nil end
	return LoadoutCore.LevelCost(gun.Price, level)
end

-- A whole shot's damage at `level`.
function LoadoutCore.Damage(gun: TData.TGun, level: number): number
	return gun.Damage * (1 + Tune.DAMAGE_PER_LEVEL * (level - 1))
end

function LoadoutCore.DamagePerSecond(gun: TData.TGun, level: number): number
	return LoadoutCore.Damage(gun, level) / gun.FireInterval
end

-- Shots a minute.
function LoadoutCore.FireRate(gun: TData.TGun): number
	return 60 / gun.FireInterval
end

return table.freeze(LoadoutCore)
