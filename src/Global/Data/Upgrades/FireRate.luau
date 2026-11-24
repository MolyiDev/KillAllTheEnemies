-- The gun cycles faster, on both sides: the server shortens its interval and the client its trigger.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EUpgradesIds = require(ReplicatedStorage.Types.Enums.Data.EUpgradesIds)
local TData = require(ReplicatedStorage.Types.TData)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local data: TData.TUpgrade = {
	Id = EUpgradesIds.FireRate,
	Name = "Fire Rate",
	Icon = EIcons.UpgradeFireRate,
	Value = 0.08,
	MaxLevel = 5,
	Description = "Shoot %d%% faster",
	PercentScale = 100,
}

return table.freeze(data)
