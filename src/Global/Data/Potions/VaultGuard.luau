local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local EPotionsIds = require(ReplicatedStorage.Types.Enums.Data.EPotionsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TPotion = {
	Id = EPotionsIds.VaultGuard,
	Name = "Vault Guard",
	Energies = { EEnemiesIds.Heavy, EEnemiesIds.ZombieKing },
	Description = "Tastes of old coins. Armored up, with a bigger cut of every kill.",
}

return table.freeze(data)
