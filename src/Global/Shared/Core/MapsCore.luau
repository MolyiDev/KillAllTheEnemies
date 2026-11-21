-- The maps. Every map is played in the one Game place (EPlaceIds.Game), which places the map its party queued for
-- from ServerStorage.Maps by name. Records are kept per map and party category.
--
-- LIST's order is the map's number on the network: append, never reorder.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TProfile = require(ReplicatedStorage.Types.TProfile)

export type TMap = {
	-- Also the map's Model under ServerStorage.Maps in the Game place.
	Name: string,
	DisplayName: string,
	Difficulty: string,
	-- The record that opens it: HighestCompleted on `UnlockRecordMap` at least `UnlockRound`. 0 is always open.
	UnlockRound: number,
	UnlockRecordMap: string?,
}

local MapsCore = {}

MapsCore.DEFAULT = "Baseplate"
-- In the order the lobby offers them.
MapsCore.DIFFICULTIES = table.freeze({ "Normal" })
MapsCore.LIST = table.freeze({
	table.freeze({ Name = "PirateCove", DisplayName = "Pirate Cove", Difficulty = "Normal", UnlockRound = 0 }),
	table.freeze({ Name = "GrassLands", DisplayName = "Grass Lands", Difficulty = "Normal", UnlockRound = 0 }),
	table.freeze({ Name = "Baseplate", DisplayName = "Baseplate", Difficulty = "Normal", UnlockRound = 0 }),
}) :: { TMap }

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

-- From each map's best completed round, by map name: the client has these (Lobby.MapRecords), not the profile.
function MapsCore.IsUnlockedBy(map: TMap, bestByMap: { [string]: number }): boolean
	if map.UnlockRound <= 0 then return true end
	return (bestByMap[map.UnlockRecordMap or map.Name] or 0) >= map.UnlockRound
end

function MapsCore.IsUnlocked(profile: TProfile.TProfile, mapName: string): boolean
	local map = MapsCore.MAPS[mapName]
	if not map then return false end
	if map.UnlockRound <= 0 then return true end
	return MapsCore.BestCompleted(profile, map.UnlockRecordMap or mapName) >= map.UnlockRound
end

-- What the matchmaking shows on a locked map (GDD 8: show the exact requirement).
function MapsCore.RequirementText(map: TMap): string
	local recordMap = MapsCore.MAPS[map.UnlockRecordMap or map.Name]
	local recordName = if recordMap then recordMap.DisplayName else map.Name
	return `Clear wave {map.UnlockRound} on {recordName}`
end

return MapsCore
