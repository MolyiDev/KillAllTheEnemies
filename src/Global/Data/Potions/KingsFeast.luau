local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local EPotionsIds = require(ReplicatedStorage.Types.Enums.Data.EPotionsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TPotion = {
	Id = EPotionsIds.KingsFeast,
	Name = "King's Feast",
	Energies = { EEnemiesIds.Slammer, EEnemiesIds.ZombieKing },
	Description = "The Zombie King's own cup. Kills heal you and fill your pockets.",
}

return table.freeze(data)
