local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local EPotionsIds = require(ReplicatedStorage.Types.Enums.Data.EPotionsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TPotion = {
	Id = EPotionsIds.VampiresKiss,
	Name = "Vampire's Kiss",
	Energies = { EEnemiesIds.Exploding, EEnemiesIds.Slammer },
	Description = "Dark and sweet. Harder hits, and every kill puts health back.",
}

return table.freeze(data)
