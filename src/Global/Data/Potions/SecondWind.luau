local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local EPotionsIds = require(ReplicatedStorage.Types.Enums.Data.EPotionsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TPotion = {
	Id = EPotionsIds.SecondWind,
	Name = "Second Wind",
	Energies = { EEnemiesIds.Basic, EEnemiesIds.Fast },
	Description = "Fizzy and bright. Your wounds close while your trigger finger speeds up.",
}

return table.freeze(data)
