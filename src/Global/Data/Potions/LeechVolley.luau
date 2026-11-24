local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local EPotionsIds = require(ReplicatedStorage.Types.Enums.Data.EPotionsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TPotion = {
	Id = EPotionsIds.LeechVolley,
	Name = "Leech Volley",
	Energies = { EEnemiesIds.Fast, EEnemiesIds.Slammer },
	Description = "Sour and sharp. A faster gun, and every kill it lands heals you.",
}

return table.freeze(data)
