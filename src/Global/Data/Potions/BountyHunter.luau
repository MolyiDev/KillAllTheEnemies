local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local EPotionsIds = require(ReplicatedStorage.Types.Enums.Data.EPotionsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TPotion = {
	Id = EPotionsIds.BountyHunter,
	Name = "Bounty Hunter",
	Energies = { EEnemiesIds.Exploding, EEnemiesIds.TRex },
	Description = "Bitter, then golden. Every bullet hurts more, and every kill pays more.",
}

return table.freeze(data)
