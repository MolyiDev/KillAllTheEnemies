-- Added to the health a resting body gets back each second.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EUpgradesIds = require(ReplicatedStorage.Types.Enums.Data.EUpgradesIds)
local TData = require(ReplicatedStorage.Types.TData)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local data: TData.TUpgrade = {
	Id = EUpgradesIds.Regeneration,
	Name = "Regeneration",
	Icon = EIcons.UpgradeRegeneration,
	Value = 2,
	MaxLevel = 4,
	Description = "Heal %d more health a second",
	PercentScale = 1,
}

return table.freeze(data)
