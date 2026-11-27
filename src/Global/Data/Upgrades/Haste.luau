-- Every ability's cooldown is divided by one plus the sum (UpgradesCore.Cooldown), on both sides.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EUpgradesIds = require(ReplicatedStorage.Types.Enums.Data.EUpgradesIds)
local TData = require(ReplicatedStorage.Types.TData)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local data: TData.TUpgrade = {
	Id = EUpgradesIds.Haste,
	Name = "Haste",
	Icon = EIcons.UpgradeHaste,
	Value = 0.08,
	MaxLevel = 5,
	Description = "Abilities recharge %d%% faster",
	PercentScale = 100,
}

return table.freeze(data)
