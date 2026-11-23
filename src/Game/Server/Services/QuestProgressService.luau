-- Counts what a run does toward each player's quests (QuestsCore) and writes it into their boards. A kill comes
-- dozens of times a second and a profile write clones the whole profile, so the counts gather in memory and are
-- written every FLUSH_SECONDS, and once more as the player leaves.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local DatabaseService = require(ServerScriptService.GlobalServer.Services.DatabaseService)
local EnemiesService = require(script.Parent.EnemiesService)
local RoundService = require(script.Parent.RoundService)
local QuestsCore = require(ReplicatedStorage.GlobalShared.Core.QuestsCore)
local TData = require(ReplicatedStorage.Types.TData)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local FLUSH_SECONDS = 3

-- Per player: metric -> enemy data Id (0 for an event about no body) -> amount (a BestWave's is its high mark).
type TPending = { [QuestsCore.TMetric]: { [number]: number } }

local QuestProgressService = {}

local pending: { [Player]: TPending } = {}
local nextFlushAt = 0

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
end

-- The same for everybody in the match: what the squad does together (a wave, a boss) counts for each of them.
function QuestProgressService.AddForAll(metric: QuestsCore.TMetric, amount: number, enemyId: number?)
	for _, player in Players:GetPlayers() do
		QuestProgressService.Add(player, metric, amount, enemyId)
	end
end

-- Writes what `player` has gathered into their boards, dealing a board for the new period first when one has turned.
-- Kept when the profile is not open, so it goes in with the next flush.
local function flush(player: Player)
	local counts = pending[player]
	if not counts then return end
	local now = os.time()
	local isWritten = DatabaseService.Update(player, function(profile)
		local hasMoved = false
		for _, kind in QuestsCore.BOARDS do
			local board = QuestsCore.Current(profile.Quests, kind, player.UserId, now)
			local isMoved = false
			for metric, byEnemy in counts do
				for enemyId, amount in byEnemy do
					if QuestsCore.Apply(board, metric, enemyId, amount) then isMoved = true end
				end
			end
			if not isMoved then continue end
			profile.Quests[kind] = board
			hasMoved = true
		end

		return hasMoved
	end)

	-- Written, or nothing it counted moves a quest (every one it counts for is claimed or full): either way it is spent.
	if isWritten or DatabaseService.Get(player) then pending[player] = nil end
end

QuestProgressService.OnPlayerDisconnected = function(player: Player)
	flush(player)
	pending[player] = nil
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
