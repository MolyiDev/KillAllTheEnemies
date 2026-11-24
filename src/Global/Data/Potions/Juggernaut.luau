local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local EPotionsIds = require(ReplicatedStorage.Types.Enums.Data.EPotionsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TPotion = {
	Id = EPotionsIds.Juggernaut,
	Name = "Juggernaut",
	Energies = { EEnemiesIds.Exploding, EEnemiesIds.Heavy },
	Description = "Heavy as a brick. Hit harder, take less: walk straight through them.",
}

return table.freeze(data)
