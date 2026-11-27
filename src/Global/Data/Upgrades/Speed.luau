-- The body walks faster by the sum, capped at UpgradesCore.MAX_SPEED: TimeController writes the WalkSpeed.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EUpgradesIds = require(ReplicatedStorage.Types.Enums.Data.EUpgradesIds)
local TData = require(ReplicatedStorage.Types.TData)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local data: TData.TUpgrade = {
	Id = EUpgradesIds.Speed,
	Name = "Speed",
	Icon = EIcons.UpgradeSpeed,
	Value = 0.05,
	MaxLevel = 5,
	Description = "Move %d%% faster",
	PercentScale = 100,
}

return table.freeze(data)
