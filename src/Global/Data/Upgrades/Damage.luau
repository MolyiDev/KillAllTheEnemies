-- Every bullet hits harder.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EUpgradesIds = require(ReplicatedStorage.Types.Enums.Data.EUpgradesIds)
local TData = require(ReplicatedStorage.Types.TData)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local data: TData.TUpgrade = {
	Id = EUpgradesIds.Damage,
	Name = "Damage",
	Icon = EIcons.UpgradeDamage,
	Value = 0.1,
	MaxLevel = 5,
	Description = "+%d%% gun damage",
	PercentScale = 100,
}

return table.freeze(data)
