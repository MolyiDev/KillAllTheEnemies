local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local EPotionsIds = require(ReplicatedStorage.Types.Enums.Data.EPotionsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TPotion = {
	Id = EPotionsIds.UndyingFury,
	Name = "Undying Fury",
	Energies = { EEnemiesIds.Basic, EEnemiesIds.Exploding },
	Description = "Tastes like smoke. Every bullet bites harder, and you keep getting back up.",
}

return table.freeze(data)
