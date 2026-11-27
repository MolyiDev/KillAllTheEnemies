-- The ultimate needs its kills divided by one plus the sum (UpgradesCore.ChargeKills), on both sides.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EUpgradesIds = require(ReplicatedStorage.Types.Enums.Data.EUpgradesIds)
local TData = require(ReplicatedStorage.Types.TData)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local data: TData.TUpgrade = {
	Id = EUpgradesIds.Overcharge,
	Name = "Overcharge",
	Icon = EIcons.UpgradeOvercharge,
	Value = 0.1,
	MaxLevel = 5,
	Description = "Ultimate charges %d%% faster",
	PercentScale = 100,
}

return table.freeze(data)
