-- Every blow taken is cut by the sum, capped at UpgradesCore.MAX_ARMOR.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EUpgradesIds = require(ReplicatedStorage.Types.Enums.Data.EUpgradesIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TUpgrade = {
	Id = EUpgradesIds.Armor,
	Name = "Armor",
	Icon = "Barricade",
	Value = 0.06,
	MaxLevel = 5,
	Description = "Take %d%% less damage",
	PercentScale = 100,
}

return table.freeze(data)
