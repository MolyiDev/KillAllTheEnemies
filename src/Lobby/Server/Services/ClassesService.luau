-- The classes screen's purchases (TProfile.AbilityLevels, AbilitiesCore): raising a class ability a level with Gems.
-- Every request is answered with the player's levels (Classes.Sync), a refused one too, so the screen waiting on it
-- always hears back.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(ServerScriptService.GlobalServer.NetworkMeta)
local DatabaseService = require(ServerScriptService.GlobalServer.Services.DatabaseService)
local AbilitiesCore = require(ReplicatedStorage.GlobalShared.Core.AbilitiesCore)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local ServerNetworkClasses = NetworkMeta.Server.Classes
local ClientNetworkClasses = NetworkMeta.Client.Classes

local ClassesService = {}

-- Sends every class's ability levels (Classes.Sync).
function ClassesService.Sync(player: Player)
	local profile = DatabaseService.Get(player)
	if not profile then return end

	local classes = table.create(#DataCore.Classes.All)
	for index, class in DataCore.Classes.All do
		classes[index] = { Class = class.Id, Levels = AbilitiesCore.SlotLevels(profile.AbilityLevels, class) }
	end

	ServerNetworkClasses.Sync.Fire(player, classes)
end

ClassesService.OnDataLoaded = function(player: Player)
	ClassesService.Sync(player)
end :: TPlayerEvents.OnDataLoaded

-- No character needed: the levels are the player's own, changed from the menu whatever their body is doing. Each check
-- is made again inside the write, on the profile as it is then.
ClientNetworkClasses.Upgrade.On(function(player: Player, classId: number, slot: number)
	local class = DataCore.Classes.ById[classId]
	local ability = if class then AbilitiesCore.AbilityAt(class, slot) else nil
	local hasUpgraded = class ~= nil
		and ability ~= nil
		and DatabaseService.Update(player, function(profile)
			if not table.find(profile.OwnedClasses, class.Id) then return false end
			local level = AbilitiesCore.LevelOf(profile.AbilityLevels, class, ability)
			local cost = AbilitiesCore.UpgradeCost(level)
			if not cost or profile.Gems < cost then return false end
			profile.Gems -= cost
			local levels = profile.AbilityLevels or {}
			levels[AbilitiesCore.LevelKey(class, ability)] = level + 1
			profile.AbilityLevels = levels
			return true
		end)

	if hasUpgraded then DatabaseService.SaveAsync(player) end
	ClassesService.Sync(player)
end)

return Ignis.Register(ClassesService)
