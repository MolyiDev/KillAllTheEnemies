-- Each kill of his own heals the killer.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EUpgradesIds = require(ReplicatedStorage.Types.Enums.Data.EUpgradesIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TUpgrade = {
	Id = EUpgradesIds.Lifesteal,
	Name = "Lifesteal",
	Icon = "HealAll",
	Value = 2,
	MaxLevel = 4,
	Description = "Every kill heals %d health",
	PercentScale = 1,
}

return table.freeze(data)
