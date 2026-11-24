local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local EPotionsIds = require(ReplicatedStorage.Types.Enums.Data.EPotionsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TPotion = {
	Id = EPotionsIds.BoneWard,
	Name = "Bone Ward",
	Energies = { EEnemiesIds.Heavy, EEnemiesIds.Slammer },
	Description = "Chalky and strong. Less damage taken, and kills patch you up.",
}

return table.freeze(data)
