-- Every gold its player earns in the match is paid this much over (RoundService: kills and wave clears), never the
-- gold bought with Robux.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EUpgradesIds = require(ReplicatedStorage.Types.Enums.Data.EUpgradesIds)
local TData = require(ReplicatedStorage.Types.TData)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local data: TData.TUpgrade = {
	Id = EUpgradesIds.Greed,
	Name = "Greed",
	Icon = EIcons.UpgradeGreed,
	Value = 0.1,
	MaxLevel = 5,
	Description = "+%d%% gold",
	PercentScale = 100,
}

return table.freeze(data)
