-- Counts what a run does toward each player's quests (QuestsCore) and writes it into their boards. A kill comes
-- dozens of times a second and a profile write clones the whole profile, so the counts gather in memory and are
-- written every FLUSH_SECONDS, and once more as the player leaves. A count that finishes a quest is written at once, and
-- the player told (Quests.Completed), so the notice lands on the kill that did it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(ServerScriptService.GlobalServer.NetworkMeta)
local DatabaseService = require(ServerScriptService.GlobalServer.Services.DatabaseService)
local EnemiesService = require(script.Parent.EnemiesService)
local RoundService = require(script.Parent.RoundService)
local QuestsCore = require(ReplicatedStorage.GlobalShared.Core.QuestsCore)
local TData = require(ReplicatedStorage.Types.TData)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)
local TProfile = require(ReplicatedStorage.Types.TProfile)

local ServerNetworkQuests = NetworkMeta.Server.Quests

local FLUSH_SECONDS = 3

-- Per player: metric -> enemy data Id (0 for an event about no body) -> amount (a BestWave's is its high mark).
type TPending = { [QuestsCore.TMetric]: { [number]: number } }
-- A quest still short of its goal, and how much more it needs since the last write (a BestWave's, the mark to reach).
type TWatch = { Quest: QuestsCore.TQuest, Left: number }

local QuestProgressService = {}

local pending: { [Player]: TPending } = {}
-- Per player: the quests a count could finish, from the last write. Only a hint to write early: the write itself
-- decides what finished.
local watched: { [Player]: { TWatch } } = {}
local nextFlushAt = 0

-- The quests on both boards of `profile` that are short of their goal and not claimed.
local function watchList(player: Player, profile: TProfile.TProfile): { TWatch }
	local now = os.time()
	local list = {}
	local count = 0
	for _, kind in QuestsCore.BOARDS do
		local board = QuestsCore.Current(profile.Quests, kind, player.UserId, now)
		for slot, name in board.Names do
			local quest = QuestsCore.ByName[name]
			if not quest or board.Claimed[slot] then continue end
			local progress = board.Progress[slot] or 0
			if progress >= quest.Goal then continue end
			count += 1
			list[count] =
				{ Quest = quest, Left = if quest.Metric == "BestWave" then quest.Goal else quest.Goal - progress }
		end
	end

	return list
end

-- Counts `amount` of `metric` for `player`; `enemyId` is the body it was about, for the quests that name one.
function QuestProgressService.Add(player: Player, metric: QuestsCore.TMetric, amount: number, enemyId: number?)
	if amount <= 0 or not player.Parent then return end
	local counts = pending[player]
	if not counts then
		counts = {}
		pending[player] = counts
	end
	local byEnemy = counts[metric]
	if not byEnemy then
		byEnemy = {}
		counts[metric] = byEnemy
	end

	local key = enemyId or 0
	local before = byEnemy[key] or 0
	byEnemy[key] = if metric == "BestWave" then math.max(before, amount) else before + amount

	local list = watched[player]
	if not list then
		local profile = DatabaseService.Get(player)
		if not profile then return end
		list = watchList(player, profile)
		watched[player] = list
	end
	-- Hoisted: this runs on every kill, and a call into another module costs a lookup each time.
	local isCounted = QuestsCore.Counts

	for _, watch in list do
		if watch.Left <= 0 or not isCounted(watch.Quest, metric, key) then continue end
		if metric ~= "BestWave" then
			watch.Left -= amount
		elseif amount >= watch.Left then
			watch.Left = 0
		end
		-- Finished: written on the next frame instead of at the next flush.
		if watch.Left <= 0 then nextFlushAt = 0 end
	end
end

-- The same for everybody in the match: what the squad does together (a wave, a boss) counts for each of them.
function QuestProgressService.AddForAll(metric: QuestsCore.TMetric, amount: number, enemyId: number?)
	for _, player in Players:GetPlayers() do
		QuestProgressService.Add(player, metric, amount, enemyId)
	end
end

-- After a write: the watch list again from the profile as written, and the player told of every quest the write
-- finished (`finished`: board index and quest Id pairs, empty unless it was written).
local function announce(player: Player, finished: { { number } })
	local profile = DatabaseService.Get(player)
	if profile then watched[player] = watchList(player, profile) end
	for _, pair in finished do
		ServerNetworkQuests.Completed.Fire(player, pair[1], pair[2])
	end
end

-- Fills every unclaimed quest on `player`'s boards (`kind`, or both for nil) to its goal, as if played: the console's
-- way to see the notice. Returns how many it finished.
function QuestProgressService.Complete(player: Player, kind: QuestsCore.TBoardKind?): number
	local now = os.time()
	local finished = {}
	local isWritten = DatabaseService.Update(player, function(profile)
		for _, boardKind in QuestsCore.BOARDS do
			if kind and boardKind ~= kind then continue end
			local board = QuestsCore.Current(profile.Quests, boardKind, player.UserId, now)
			for slot, name in board.Names do
				local quest = QuestsCore.ByName[name]
				if not quest or QuestsCore.IsReady(board, slot) or board.Claimed[slot] then continue end
				board.Progress[slot] = quest.Goal
				table.insert(finished, { QuestsCore.BoardIndex[boardKind], quest.Id })
			end
			profile.Quests[boardKind] = board
		end

		return #finished > 0
	end)
	if not isWritten then return 0 end

	announce(player, finished)

	return #finished
end

-- Writes what `player` has gathered into their boards, dealing a board for the new period first when one has turned.
-- Kept when the profile is not open, so it goes in with the next flush.
local function flush(player: Player)
	local counts = pending[player]
	if not counts then return end
	local now = os.time()
	-- The quests the write finishes, as (board index, quest Id) pairs.
	local finished = {}
	local isWritten = DatabaseService.Update(player, function(profile)
		local hasMoved = false
		for _, kind in QuestsCore.BOARDS do
			local board = QuestsCore.Current(profile.Quests, kind, player.UserId, now)
			local wasReady = table.create(QuestsCore.BOARD_SIZE)
			for slot in board.Names do
				wasReady[slot] = QuestsCore.IsReady(board, slot)
			end

			local isMoved = false
			for metric, byEnemy in counts do
				for enemyId, amount in byEnemy do
					if QuestsCore.Apply(board, metric, enemyId, amount) then isMoved = true end
				end
			end
			if not isMoved then continue end
			profile.Quests[kind] = board
			hasMoved = true

			for slot, name in board.Names do
				if wasReady[slot] or not QuestsCore.IsReady(board, slot) then continue end
				table.insert(finished, { QuestsCore.BoardIndex[kind], QuestsCore.ByName[name].Id })
			end
		end

		return hasMoved
	end)

	-- Written, or nothing it counted moves a quest (every one it counts for is claimed or full): either way it is spent.
	if isWritten or DatabaseService.Get(player) then pending[player] = nil end
	announce(player, finished)
end

QuestProgressService.OnPlayerDisconnected = function(player: Player)
	flush(player)
	pending[player] = nil
	watched[player] = nil
end :: TPlayerEvents.OnPlayerDisconnected

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now < nextFlushAt or next(pending) == nil then return end
	nextFlushAt = now + FLUSH_SECONDS
	for player in pending do
		flush(player)
	end
end)

EnemiesService.OnEnemyDied:Connect(function(_, enemyData: TData.TEnemy, killer: Player?)
	if killer then QuestProgressService.Add(killer, "Kills", 1, enemyData.Id) end
	if enemyData.IsBoss then QuestProgressService.AddForAll("Bosses", 1, enemyData.Id) end
end)

RoundService.OnRoundCleared:Connect(function(round: number)
	QuestProgressService.AddForAll("Waves", 1)
	QuestProgressService.AddForAll("BestWave", round)
end)

-- A run starts on wave 1, PLAY AGAIN included; a revive picks the run up where it was and starts no wave 1.
RoundService.OnRoundStarted:Connect(function(round: number)
	if round == 1 then QuestProgressService.AddForAll("Runs", 1) end
end)

return Ignis.Register(QuestProgressService)
