local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local EPotionsIds = require(ReplicatedStorage.Types.Enums.Data.EPotionsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TPotion = {
	Id = EPotionsIds.SteelRush,
	Name = "Steel Rush",
	Energies = { EEnemiesIds.Fast, EEnemiesIds.Heavy },
	Description = "Cold and quick. Shoot faster while your skin turns to plate.",
}

return table.freeze(data)
