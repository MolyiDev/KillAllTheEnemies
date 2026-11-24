local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local EPotionsIds = require(ReplicatedStorage.Types.Enums.Data.EPotionsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TPotion = {
	Id = EPotionsIds.Bloodroot,
	Name = "Bloodroot",
	Energies = { EEnemiesIds.Basic, EEnemiesIds.Slammer },
	Description = "Earthy and warm. Kills feed you, and you mend on your own between them.",
}

return table.freeze(data)
