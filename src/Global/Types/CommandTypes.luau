-- Conch argument types for the server's console commands. Required on both sides: a type only the server registers
-- leaves the replicated command unresolvable on the client.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Conch = require(ReplicatedStorage.Packages.conch)
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)

local args = Conch.args

local enemyNames = {}
for name in EEnemiesIds :: { [string]: number } do
	enemyNames[#enemyNames + 1] = string.lower(name)
end
table.sort(enemyNames)

local gunNames = {}
for name in EGunsIds :: { [string]: number } do
	gunNames[#gunNames + 1] = string.lower(name)
end
table.sort(gunNames)

return {
	enemyName = Conch.register_type("enemy_name", args.enum_new(enemyNames, "enemy_name")),
	gunName = Conch.register_type("gun_name", args.enum_new(gunNames, "gun_name")),
	pauseTarget = Conch.register_type(
		"pause_target",
		args.enum_new({ "enemies", "spawns", "all", "reset" }, "pause_target")
	),
}
