local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local EPotionsIds = require(ReplicatedStorage.Types.Enums.Data.EPotionsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TPotion = {
	Id = EPotionsIds.TriggerStorm,
	Name = "Trigger Storm",
	Energies = { EEnemiesIds.Fast, EEnemiesIds.Exploding },
	Description = "Crackles on the tongue. Faster shots that hit harder: pure firepower.",
}

return table.freeze(data)
