-- The maps. Every map is played in the one Game place (EPlaceIds.Game), which places the map its party queued for
-- from ServerStorage.Maps by name. Records are kept per map and party category.
--
-- LIST's order is the map's number on the network (append, never reorder) and the order they are played in: each
-- opens on the player's level and on beating the boss of the map before it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local TProfile = require(ReplicatedStorage.Types.TProfile)

export type TMap = {
	-- Also the map's Model under ServerStorage.Maps in the Game place.
	Name: string,
	DisplayName: string,
	-- What opens it: the player's level, and how many times they were in the run as the boss of the map before it in
	-- LIST fell (TProfile.BossKills). 0 and 0 is always open.
	UnlockLevel: number,
	UnlockBossKills: number,
	-- Its bosses (enemy data ids), taking turns every RoundCore.BOSS_EVERY waves: the principal first, then the filler.
	Bosses: { number },
}

local MapsCore = {}

-- The difficulties a host can pick for a party, in the order the lobby offers them. The index is the difficulty's
-- number on the network (append, never reorder); the name is what travels to the match and is saved.
MapsCore.DIFFICULTIES = table.freeze({ "Normal", "Hard", "Nightmare", "Hell" })
MapsCore.LIST = table.freeze({
	table.freeze({
		Name = "Baseplate",
		DisplayName = "Baseplate",
		UnlockLevel = 0,
		UnlockBossKills = 0,
		Bosses = table.freeze({ EEnemiesIds.TRex, EEnemiesIds.GiantSpider }),
	}),
}) :: { TMap }
-- The map played when nobody came from the lobby (Studio).
MapsCore.DEFAULT = MapsCore.LIST[1].Name

local maps: { [string]: TMap } = {}
local indexes: { [string]: number } = {}
for index, map in MapsCore.LIST do
	maps[map.Name] = map
	indexes[map.Name] = index
end

MapsCore.MAPS = table.freeze(maps)
MapsCore.INDEX = table.freeze(indexes)

-- "Solo" for one, "Squad" for more: records are compared within a category, never across.
function MapsCore.RecordKey(mapName: string, playerCount: number): string
	return `{mapName}:{if playerCount <= 1 then "Solo" else "Squad"}`
end

-- The best completed round on `mapName` in either category.
function MapsCore.BestCompleted(profile: TProfile.TProfile, mapName: string): number
	local best = 0
	for _, category in { "Solo", "Squad" } do
		local record = profile.Records[`{mapName}:{category}`]
		if record then best = math.max(best, record.HighestCompleted) end
	end

	return best
end

-- The map played before `map`, whose boss opens it; nil for the first.
function MapsCore.PreviousOf(map: TMap): TMap?
	local index = indexes[map.Name]
	return if index then MapsCore.LIST[index - 1] else nil
end

-- Whether it asks for anything: the first map is open from the start, and has no unlock to play.
function MapsCore.HasRequirement(map: TMap): boolean
	return map.UnlockLevel > 0 or map.UnlockBossKills > 0
end

-- From the player's level and their boss kills by map name: the client has these (Lobby.MapRecords and Profile.Sync),
-- not the profile.
function MapsCore.IsUnlockedBy(map: TMap, level: number, bossKills: { [string]: number }): boolean
	if level < map.UnlockLevel then return false end
	if map.UnlockBossKills <= 0 then return true end
	local previous = MapsCore.PreviousOf(map)
	return previous == nil or (bossKills[previous.Name] or 0) >= map.UnlockBossKills
end

function MapsCore.IsUnlocked(profile: TProfile.TProfile, mapName: string): boolean
	local map = MapsCore.MAPS[mapName]
	if not map then return false end
	return MapsCore.IsUnlockedBy(map, profile.Level, profile.BossKills or {})
end

-- What a refusal to join a locked map's party says (GDD 8: show the exact requirement).
function MapsCore.RequirementText(map: TMap): string
	local previous = MapsCore.PreviousOf(map)
	if map.UnlockBossKills <= 0 or not previous then return `Reach level {map.UnlockLevel}` end
	return `Reach level {map.UnlockLevel} and beat the boss of {previous.DisplayName} {map.UnlockBossKills} times`
end

return MapsCore
