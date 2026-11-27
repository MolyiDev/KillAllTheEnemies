-- Every ability's gold price is cut by the sum, capped at UpgradesCore.MAX_DISCOUNT (UpgradesCore.Cost), on both sides.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EUpgradesIds = require(ReplicatedStorage.Types.Enums.Data.EUpgradesIds)
local TData = require(ReplicatedStorage.Types.TData)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local data: TData.TUpgrade = {
	Id = EUpgradesIds.Discount,
	Name = "Discount",
	Icon = EIcons.UpgradeDiscount,
	Value = 0.08,
	MaxLevel = 5,
	Description = "Abilities cost %d%% less gold",
	PercentScale = 100,
}

return table.freeze(data)
