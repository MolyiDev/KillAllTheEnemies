-- The quest boards (QuestsCore) in the lobby: each player's daily and weekly board told to their screen (Quests.State)
-- and claiming what is finished, one quest or a whole board. Progress is counted in the Game place
-- (QuestProgressService); here it is only read and paid.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(ServerScriptService.GlobalServer.NetworkMeta)
local DatabaseService = require(ServerScriptService.GlobalServer.Services.DatabaseService)
local QuestsCore = require(ReplicatedStorage.GlobalShared.Core.QuestsCore)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)
local TProfile = require(ReplicatedStorage.Types.TProfile)

local ServerNetworkQuests = NetworkMeta.Server.Quests
local ClientNetworkQuests = NetworkMeta.Client.Quests

-- A second past the reset, so a clock a hair behind the server's still reads the new period.
local ROLLOVER_MARGIN = 1

local QuestsService = {}

local function wire(board: TProfile.TQuestBoard, kind: QuestsCore.TBoardKind, now: number)
	local ids = table.create(#board.Names)
	for index, name in board.Names do
		local quest = QuestsCore.ByName[name]
		ids[index] = if quest then quest.Id else 0
	end

	return {
		Ids = ids,
		Progress = board.Progress,
		Claimed = board.Claimed,
		SecondsLeft = QuestsCore.SecondsLeft(kind, now),
	}
end

local function send(player: Player, profile: TProfile.TProfile)
	local now = os.time()
	local daily = QuestsCore.Current(profile.Quests, "Daily", player.UserId, now)
	local weekly = QuestsCore.Current(profile.Quests, "Weekly", player.UserId, now)
	ServerNetworkQuests.State.Fire(player, wire(daily, "Daily", now), wire(weekly, "Weekly", now))
end

-- At every daily reset (a weekly one is always one too) a new board comes up, so everybody is told.
local function rollOver()
	for _, player in Players:GetPlayers() do
		local profile = DatabaseService.Get(player)
		if profile then send(player, profile) end
	end

	task.delay(QuestsCore.SecondsLeft("Daily", os.time()) + ROLLOVER_MARGIN, rollOver)
end

-- Claims every slot of `kind` that `pick` lets through and is finished, inside one write; the board is the current
-- period's, dealt now if the saved one is a past one's. Returns the slots claimed and the Gems paid.
local function claim(player: Player, kind: QuestsCore.TBoardKind, pick: (slot: number) -> boolean): ({ number }, number)
	local now = os.time()
	local slots = {}
	local gems = 0
	local hasClaimed = DatabaseService.Update(player, function(profile)
		local board = QuestsCore.Current(profile.Quests, kind, player.UserId, now)
		local count = 0
		for slot, name in board.Names do
			if not pick(slot) or not QuestsCore.IsReady(board, slot) then continue end
			local quest = QuestsCore.ByName[name]
			board.Claimed[slot] = true
			gems += quest.Gems
			count += 1
			slots[count] = slot
		end
		if count == 0 then return false end
		profile.Gems += gems
		profile.Quests[kind] = board
		return true
	end)

	if not hasClaimed then return {}, 0 end
	return slots, gems
end

local function answer(player: Player, board: number, slots: { number }, gems: number)
	-- The write sent the new State (OnProfileChanged); a refused one sends the State as it stands, so the screen
	-- waiting on an answer is put right.
	if #slots > 0 then
		DatabaseService.SaveAsync(player)
	else
		local profile = DatabaseService.Get(player)
		if profile then send(player, profile) end
	end
	ServerNetworkQuests.Claimed.Fire(player, board, slots, gems)
end

local function kindOf(board: number): QuestsCore.TBoardKind?
	return QuestsCore.BOARDS[board]
end

QuestsService.OnStart = function()
	task.delay(QuestsCore.SecondsLeft("Daily", os.time()) + ROLLOVER_MARGIN, rollOver)
end

QuestsService.OnDataLoaded = function(player: Player)
	local profile = DatabaseService.Get(player)
	if profile then send(player, profile) end
end :: TPlayerEvents.OnDataLoaded

-- A claim made, or Gems spent anywhere, changes what the screen shows.
DatabaseService.OnProfileChanged:Connect(send)

-- The claims need no character: the boards are the player's own, claimed from the menu whatever their body is doing.
-- Whether a quest is finished is worked out again inside the write, on the profile as it is then.
ClientNetworkQuests.Claim.On(function(player: Player, board: number, slot: number)
	local kind = kindOf(board)
	if not kind then return end
	local slots, gems = claim(player, kind, function(index: number): boolean
		return index == slot
	end)
	answer(player, board, slots, gems)
end)

ClientNetworkQuests.ClaimAll.On(function(player: Player, board: number)
	local kind = kindOf(board)
	if not kind then return end
	local slots, gems = claim(player, kind, function(): boolean
		return true
	end)
	answer(player, board, slots, gems)
end)

return Ignis.Register(QuestsService)
