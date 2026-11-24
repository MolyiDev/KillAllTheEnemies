local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local EPotionsIds = require(ReplicatedStorage.Types.Enums.Data.EPotionsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TPotion = {
	Id = EPotionsIds.IronHide,
	Name = "Iron Hide",
	Energies = { EEnemiesIds.Basic, EEnemiesIds.Heavy },
	Description = "Thick as mud. Blows glance off you, and what gets through heals over.",
}

return table.freeze(data)
