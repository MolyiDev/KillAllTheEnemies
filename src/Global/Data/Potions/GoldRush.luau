local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local EPotionsIds = require(ReplicatedStorage.Types.Enums.Data.EPotionsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TPotion = {
	Id = EPotionsIds.GoldRush,
	Name = "Gold Rush",
	Energies = { EEnemiesIds.Fast, EEnemiesIds.ZombieKing },
	Description = "Bubbles like a jackpot. More shots, and more Gold for each kill.",
}

return table.freeze(data)
