-- The lobby-to-match handoff, both ends.
--
-- The teleport data a client carries is only a one-time token, because anything in it is the client's to edit.
-- The real payload is written by the lobby server to a MemoryStore sorted map under that token, read by the
-- match server once and deleted, so a replayed token finds nothing.
local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TJoinData = require(ReplicatedStorage.Types.TJoinData)

local JoinDataMap = MemoryStoreService:GetSortedMap("LobbyTeleportData")
-- Long enough for a slow teleport, short enough that an abandoned token does not linger.
local EXPIRATION_SECONDS = 120

local JoinData = {}

-- Lobby side. Yields; errors propagate so the caller's pcall treats a failed store as a failed teleport.
function JoinData.StoreAsync(token: string, message: TJoinData.TMessage)
	JoinDataMap:SetAsync(token, message, EXPIRATION_SECONDS)
end

-- Match side. Yields. The token a player arrived with, or nil for a join that did not come from a pad
-- (Studio, a friend following, a server browser).
function JoinData.GetToken(player: Player): string?
	local joinData = player:GetJoinData() :: TJoinData.TJoin
	local teleportData = joinData and joinData.TeleportData
	if type(teleportData) ~= "table" or type(teleportData.SecureToken) ~= "string" then return nil end
	return teleportData.SecureToken
end

-- Match side. Yields. Reads and deletes; nil when the token is unknown, expired or the store failed.
function JoinData.TakeAsync(token: string): TJoinData.TMessage?
	local ok, message = pcall(JoinDataMap.GetAsync, JoinDataMap, token)
	if not ok then
		warn("[JoinData] GetAsync failed:", message)
		return nil
	end

	if message == nil then return nil end
	local removed, err = pcall(JoinDataMap.RemoveAsync, JoinDataMap, token)
	if not removed then warn("[JoinData] RemoveAsync failed:", err) end
	return message
end

return JoinData
