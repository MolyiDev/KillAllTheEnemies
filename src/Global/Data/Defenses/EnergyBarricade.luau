local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EDefensesIds = require(ReplicatedStorage.Types.Enums.Data.EDefensesIds)
local TData = require(ReplicatedStorage.Types.TData)

-- GDD 15: an obstacle with health. Enemies route around it, and attack it when it is their nearest target.
local data: TData.TDefense = {
	Id = EDefensesIds.EnergyBarricade,
	Name = "Energy Barricade",
	Kind = "Barricade",
	ModelName = "EnergyBarricade",
	Cost = 35,
	UpgradeCosts = { 60, 120 },
	Footprint = Vector2.new(8, 2),
	MaxHealth = 400,
	MaxPerPlayer = 6,
}

return table.freeze(data)
