-- Conch argument types for the server's console commands. Required on both sides: a type only the server registers
-- leaves the replicated command unresolvable on the client.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Conch = require(ReplicatedStorage.Packages.conch)
local QuestsCore = require(ReplicatedStorage.GlobalShared.Core.QuestsCore)
local EClassesIds = require(ReplicatedStorage.Types.Enums.Data.EClassesIds)
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local EEquipmentIds = require(ReplicatedStorage.Types.Enums.Data.EEquipmentIds)
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local EPotionsIds = require(ReplicatedStorage.Types.Enums.Data.EPotionsIds)
local ERarities = require(ReplicatedStorage.Types.Enums.ERarities)

local args = Conch.args

local enemyNames = {}
for name in EEnemiesIds :: { [string]: number } do
	enemyNames[#enemyNames + 1] = string.lower(name)
end
table.sort(enemyNames)
-- The same, with "all" first: a command that can act on every enemy.
local enemyTargets = table.clone(enemyNames)
table.insert(enemyTargets, 1, "all")

local gunNames = {}
for name in EGunsIds :: { [string]: number } do
	gunNames[#gunNames + 1] = string.lower(name)
end
table.sort(gunNames)
local gunTargets = table.clone(gunNames)
table.insert(gunTargets, 1, "all")

local classTargets = {}
for name in EClassesIds :: { [string]: number } do
	classTargets[#classTargets + 1] = string.lower(name)
end
table.sort(classTargets)
table.insert(classTargets, 1, "all")

-- Every piece of equipment, "all" first.
local equipmentTargets = {}
for name in EEquipmentIds :: { [string]: number } do
	equipmentTargets[#equipmentTargets + 1] = string.lower(name)
end
table.sort(equipmentTargets)
table.insert(equipmentTargets, 1, "all")

local potionNames = {}
for name in EPotionsIds :: { [string]: number } do
	potionNames[#potionNames + 1] = string.lower(name)
end
table.sort(potionNames)
local potionTargets = table.clone(potionNames)
table.insert(potionTargets, 1, "all")

-- What the index can act on: everything, a whole page, or one enemy or recipe (no name is both).
local indexTargets = { "all", "enemies", "potions" }
table.move(enemyNames, 1, #enemyNames, #indexTargets + 1, indexTargets)
table.move(potionNames, 1, #potionNames, #indexTargets + 1, indexTargets)

-- The rarities in ladder order, "random" (a brew's roll) first.
local rarityTargets = { "random" }
for name, rarity in ERarities :: { [string]: number } do
	rarityTargets[rarity + 1] = string.lower(name)
end

-- Every quest board, "all" first.
local questBoardTargets = { "all" }
for _, kind in QuestsCore.BOARDS do
	questBoardTargets[#questBoardTargets + 1] = string.lower(kind)
end

return {
	enemyName = Conch.register_type("enemy_name", args.enum_new(enemyNames, "enemy_name")),
	enemyOrAll = Conch.register_type("enemy_or_all", args.enum_new(enemyTargets, "enemy_or_all")),
	indexTarget = Conch.register_type("index_target", args.enum_new(indexTargets, "index_target")),
	potionOrAll = Conch.register_type("potion_or_all", args.enum_new(potionTargets, "potion_or_all")),
	rarityOrRandom = Conch.register_type("rarity_or_random", args.enum_new(rarityTargets, "rarity_or_random")),
	gunName = Conch.register_type("gun_name", args.enum_new(gunNames, "gun_name")),
	gunOrAll = Conch.register_type("gun_or_all", args.enum_new(gunTargets, "gun_or_all")),
	classOrAll = Conch.register_type("class_or_all", args.enum_new(classTargets, "class_or_all")),
	equipmentOrAll = Conch.register_type("equipment_or_all", args.enum_new(equipmentTargets, "equipment_or_all")),
	questBoardOrAll = Conch.register_type("quest_board_or_all", args.enum_new(questBoardTargets, "quest_board_or_all")),
	pauseTarget = Conch.register_type(
		"pause_target",
		args.enum_new({ "enemies", "spawns", "all", "reset" }, "pause_target")
	),
}
