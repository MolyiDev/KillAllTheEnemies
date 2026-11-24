local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local EPotionsIds = require(ReplicatedStorage.Types.Enums.Data.EPotionsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TPotion = {
	Id = EPotionsIds.GoldenPulse,
	Name = "Golden Pulse",
	Energies = { EEnemiesIds.Basic, EEnemiesIds.ZombieKing },
	Description = "Glitters going down. You heal as you fight, and the horde pays better.",
}

return table.freeze(data)
