-- The quests' rules, the same in every place (the Game place counts progress, the lobby shows the boards and pays the
-- claims): two boards, Daily (a UTC day) and Weekly (a UTC week from Monday), of one quest from each group. A board is
-- dealt from the player's UserId and the period, so every server deals the same one; the profile keeps it by Name
-- (TProfile.Quests) and the wire carries Ids. Progress is capped at the goal and pays nothing until it is claimed.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local TProfile = require(ReplicatedStorage.Types.TProfile)

-- What a quest counts. Kills (by the player, of `Enemy` when it names one), Bosses (defeated with the player in the
-- match, of `Enemy` when it names one), Waves (cleared with the player in the match), BestWave (the highest wave
-- cleared in one run: a high mark, not a sum), Runs (runs started), Abilities and Ultimates (cast), Defenses (placed).
export type TMetric = "Kills" | "Bosses" | "Waves" | "BestWave" | "Runs" | "Abilities" | "Ultimates" | "Defenses"
-- A board holds one quest of each group, in GROUPS order. A group is also the card's colour on the screen.
export type TGroup = "Slay" | "Hunt" | "Survive" | "Boss" | "Skill"

export type TQuest = {
	-- On the wire (u8). Never reused.
	Id: number,
	-- The saved key. Never renamed.
	Name: string,
	Title: string,
	Description: string,
	Metric: TMetric,
	Goal: number,
	Gems: number,
	Group: TGroup,
	Enemy: number?,
}

export type TBoardKind = "Daily" | "Weekly"

local QuestsCore = {}

QuestsCore.DAY_SECONDS = 86400
QuestsCore.WEEK_DAYS = 7
-- UTC day 0 (1970-01-01) was a Thursday: three days on, a week from Monday starts.
local MONDAY_SHIFT = 3

QuestsCore.GROUPS = table.freeze({ "Slay", "Hunt", "Survive", "Boss", "Skill" } :: { TGroup })
QuestsCore.BOARD_SIZE = #QuestsCore.GROUPS
QuestsCore.BOARDS = table.freeze({ "Daily", "Weekly" } :: { TBoardKind })
-- The board on the wire (u8).
QuestsCore.BoardIndex = table.freeze({ Daily = 1, Weekly = 2 })

local Pools: { [TBoardKind]: { TQuest } } = {
	Daily = {
		{
			Id = 1,
			Name = "ZombieSlayer",
			Title = "ZOMBIE SLAYER",
			Description = "Kill 150 zombies",
			Metric = "Kills",
			Goal = 150,
			Gems = 40,
			Group = "Slay",
		},
		{
			Id = 2,
			Name = "CrowdControl",
			Title = "CROWD CONTROL",
			Description = "Kill 400 zombies",
			Metric = "Kills",
			Goal = 400,
			Gems = 70,
			Group = "Slay",
		},
		{
			Id = 3,
			Name = "SpeedBump",
			Title = "SPEED BUMP",
			Description = "Kill 40 Fast Zombies",
			Metric = "Kills",
			Goal = 40,
			Gems = 50,
			Group = "Hunt",
			Enemy = EEnemiesIds.Fast,
		},
		{
			Id = 4,
			Name = "BigGame",
			Title = "BIG GAME",
			Description = "Kill 20 Heavy Zombies",
			Metric = "Kills",
			Goal = 20,
			Gems = 50,
			Group = "Hunt",
			Enemy = EEnemiesIds.Heavy,
		},
		{
			Id = 5,
			Name = "BombSquad",
			Title = "BOMB SQUAD",
			Description = "Kill 25 Exploding Zombies",
			Metric = "Kills",
			Goal = 25,
			Gems = 50,
			Group = "Hunt",
			Enemy = EEnemiesIds.Exploding,
		},
		{
			Id = 6,
			Name = "Grounded",
			Title = "GROUNDED",
			Description = "Kill 15 AoE Zombies",
			Metric = "Kills",
			Goal = 15,
			Gems = 50,
			Group = "Hunt",
			Enemy = EEnemiesIds.Slammer,
		},
		{
			Id = 7,
			Name = "Survivor",
			Title = "SURVIVOR",
			Description = "Clear wave 10",
			Metric = "BestWave",
			Goal = 10,
			Gems = 60,
			Group = "Survive",
		},
		{
			Id = 8,
			Name = "WaveRider",
			Title = "WAVE RIDER",
			Description = "Clear 20 waves",
			Metric = "Waves",
			Goal = 20,
			Gems = 50,
			Group = "Survive",
		},
		{
			Id = 9,
			Name = "Regular",
			Title = "REGULAR",
			Description = "Play 3 matches",
			Metric = "Runs",
			Goal = 3,
			Gems = 40,
			Group = "Survive",
		},
		{
			Id = 10,
			Name = "ChampionsFall",
			Title = "CHAMPION'S FALL",
			Description = "Defeat the Zombie King",
			Metric = "Bosses",
			Goal = 1,
			Gems = 100,
			Group = "Boss",
			Enemy = EEnemiesIds.ZombieKing,
		},
		{
			Id = 11,
			Name = "FaceTheBoss",
			Title = "FACE THE BOSS",
			Description = "Clear wave 15",
			Metric = "BestWave",
			Goal = 15,
			Gems = 90,
			Group = "Boss",
		},
		{
			Id = 12,
			Name = "AbilityAce",
			Title = "ABILITY ACE",
			Description = "Use 20 abilities",
			Metric = "Abilities",
			Goal = 20,
			Gems = 40,
			Group = "Skill",
		},
		{
			Id = 13,
			Name = "Unleashed",
			Title = "UNLEASHED",
			Description = "Fire your ultimate 2 times",
			Metric = "Ultimates",
			Goal = 2,
			Gems = 50,
			Group = "Skill",
		},
		{
			Id = 14,
			Name = "Engineer",
			Title = "ENGINEER",
			Description = "Place 6 defenses",
			Metric = "Defenses",
			Goal = 6,
			Gems = 40,
			Group = "Skill",
		},
	},
	Weekly = {
		{
			Id = 101,
			Name = "Exterminator",
			Title = "EXTERMINATOR",
			Description = "Kill 3,000 zombies",
			Metric = "Kills",
			Goal = 3000,
			Gems = 300,
			Group = "Slay",
		},
		{
			Id = 102,
			Name = "HordeBreaker",
			Title = "HORDE BREAKER",
			Description = "Kill 6,000 zombies",
			Metric = "Kills",
			Goal = 6000,
			Gems = 500,
			Group = "Slay",
		},
		{
			Id = 103,
			Name = "RoadBlock",
			Title = "ROAD BLOCK",
			Description = "Kill 400 Fast Zombies",
			Metric = "Kills",
			Goal = 400,
			Gems = 300,
			Group = "Hunt",
			Enemy = EEnemiesIds.Fast,
		},
		{
			Id = 104,
			Name = "TitanTamer",
			Title = "TITAN TAMER",
			Description = "Kill 200 Heavy Zombies",
			Metric = "Kills",
			Goal = 200,
			Gems = 350,
			Group = "Hunt",
			Enemy = EEnemiesIds.Heavy,
		},
		{
			Id = 105,
			Name = "Demolition",
			Title = "DEMOLITION",
			Description = "Kill 250 Exploding Zombies",
			Metric = "Kills",
			Goal = 250,
			Gems = 300,
			Group = "Hunt",
			Enemy = EEnemiesIds.Exploding,
		},
		{
			Id = 106,
			Name = "Aftershock",
			Title = "AFTERSHOCK",
			Description = "Kill 150 AoE Zombies",
			Metric = "Kills",
			Goal = 150,
			Gems = 350,
			Group = "Hunt",
			Enemy = EEnemiesIds.Slammer,
		},
		{
			Id = 107,
			Name = "Marathon",
			Title = "MARATHON",
			Description = "Play 15 matches",
			Metric = "Runs",
			Goal = 15,
			Gems = 300,
			Group = "Survive",
		},
		{
			Id = 108,
			Name = "WaveBreaker",
			Title = "WAVE BREAKER",
			Description = "Clear 150 waves",
			Metric = "Waves",
			Goal = 150,
			Gems = 400,
			Group = "Survive",
		},
		{
			Id = 109,
			Name = "IronWill",
			Title = "IRON WILL",
			Description = "Clear wave 25",
			Metric = "BestWave",
			Goal = 25,
			Gems = 400,
			Group = "Survive",
		},
		{
			Id = 110,
			Name = "BossHunter",
			Title = "BOSS HUNTER",
			Description = "Defeat the Zombie King 3 times",
			Metric = "Bosses",
			Goal = 3,
			Gems = 600,
			Group = "Boss",
			Enemy = EEnemiesIds.ZombieKing,
		},
		{
			Id = 111,
			Name = "DoubleTrouble",
			Title = "DOUBLE TROUBLE",
			Description = "Clear wave 30",
			Metric = "BestWave",
			Goal = 30,
			Gems = 600,
			Group = "Boss",
		},
		{
			Id = 112,
			Name = "PowerUser",
			Title = "POWER USER",
			Description = "Use 150 abilities",
			Metric = "Abilities",
			Goal = 150,
			Gems = 300,
			Group = "Skill",
		},
		{
			Id = 113,
			Name = "Overcharged",
			Title = "OVERCHARGED",
			Description = "Fire your ultimate 15 times",
			Metric = "Ultimates",
			Goal = 15,
			Gems = 350,
			Group = "Skill",
		},
		{
			Id = 114,
			Name = "Fortifier",
			Title = "FORTIFIER",
			Description = "Place 40 defenses",
			Metric = "Defenses",
			Goal = 40,
			Gems = 300,
			Group = "Skill",
		},
	},
}

QuestsCore.ById = {} :: { [number]: TQuest }
QuestsCore.ByName = {} :: { [string]: TQuest }
-- Each board's quests of each group, in pool order: the deal picks from these.
local byGroup: { [TBoardKind]: { [TGroup]: { TQuest } } } = {}

for kind, pool in Pools do
	local groups = {}
	for _, group in QuestsCore.GROUPS do
		groups[group] = {}
	end
	for _, quest in pool do
		table.freeze(quest)
		if QuestsCore.ById[quest.Id] or QuestsCore.ByName[quest.Name] then
			warn(`[QuestsCore] {quest.Name} reuses an Id or a Name`)
		end
		QuestsCore.ById[quest.Id] = quest
		QuestsCore.ByName[quest.Name] = quest
		table.insert(groups[quest.Group], quest)
	end
	for _, group in QuestsCore.GROUPS do
		if #groups[group] == 0 then warn(`[QuestsCore] the {kind} board has no {group} quest`) end
	end
	byGroup[kind] = groups
end
table.freeze(QuestsCore.ById)
table.freeze(QuestsCore.ByName)

-- The period a board of `kind` is in at `time` (os.time()): the UTC day, or the UTC week from Monday.
function QuestsCore.Period(kind: TBoardKind, time: number): number
	local day = time // QuestsCore.DAY_SECONDS
	if kind == "Daily" then return day end
	return (day + MONDAY_SHIFT) // QuestsCore.WEEK_DAYS
end

-- Seconds from `time` until a board of `kind` is dealt again.
function QuestsCore.SecondsLeft(kind: TBoardKind, time: number): number
	local period = QuestsCore.Period(kind, time)
	local ends = if kind == "Daily"
		then (period + 1) * QuestsCore.DAY_SECONDS
		else ((period + 1) * QuestsCore.WEEK_DAYS - MONDAY_SHIFT) * QuestsCore.DAY_SECONDS
	return ends - time
end

-- Park-Miller: deterministic in every place, and its products stay inside a double's exact integers.
local MODULUS = 2147483647
local function nextSeed(seed: number): number
	return seed * 48271 % MODULUS
end

-- A fresh board of `kind` for `userId` in `period`: the same in every place and on every server.
function QuestsCore.Deal(kind: TBoardKind, userId: number, period: number): TProfile.TQuestBoard
	local seed = ((math.abs(userId) % 1000003) * 7919 + period * 104729 + QuestsCore.BoardIndex[kind] * 13) % MODULUS
	if seed == 0 then seed = 1 end
	-- A few turns first, so neighbouring days do not start from neighbouring seeds.
	for _ = 1, 4 do
		seed = nextSeed(seed)
	end

	local names = table.create(QuestsCore.BOARD_SIZE)
	local progress = table.create(QuestsCore.BOARD_SIZE)
	local claimed = table.create(QuestsCore.BOARD_SIZE)
	for index, group in QuestsCore.GROUPS do
		seed = nextSeed(seed)
		local choices = byGroup[kind][group]
		names[index] = choices[seed % #choices + 1].Name
		progress[index] = 0
		claimed[index] = false
	end

	return { Period = period, Names = names, Progress = progress, Claimed = claimed }
end

-- The board of `kind` as it stands at `time`: the saved one if it is this period's, else a fresh deal (not saved).
function QuestsCore.Current(
	quests: { Daily: TProfile.TQuestBoard?, Weekly: TProfile.TQuestBoard? },
	kind: TBoardKind,
	userId: number,
	time: number
): TProfile.TQuestBoard
	local period = QuestsCore.Period(kind, time)
	local board = quests[kind]
	if board and board.Period == period then return board end
	return QuestsCore.Deal(kind, userId, period)
end

-- Whether a quest counts this event (`enemyId` 0 for an event about no body).
function QuestsCore.Counts(quest: TQuest, metric: TMetric, enemyId: number): boolean
	if quest.Metric ~= metric then return false end
	return quest.Enemy == nil or quest.Enemy == enemyId
end

-- Adds `amount` of `metric` to every quest on `board` it counts for (a BestWave raises its mark to `amount`), in place.
-- Returns whether anything moved.
function QuestsCore.Apply(board: TProfile.TQuestBoard, metric: TMetric, enemyId: number, amount: number): boolean
	local hasMoved = false
	for index, name in board.Names do
		local quest = QuestsCore.ByName[name]
		if not quest or board.Claimed[index] or not QuestsCore.Counts(quest, metric, enemyId) then continue end
		local before = board.Progress[index] or 0
		local after = if metric == "BestWave" then math.max(before, amount) else before + amount
		after = math.min(after, quest.Goal)
		if after == before then continue end
		board.Progress[index] = after
		hasMoved = true
	end

	return hasMoved
end

-- Whether the quest in `slot` is done and not claimed yet.
function QuestsCore.IsReady(board: TProfile.TQuestBoard, slot: number): boolean
	local quest = QuestsCore.ByName[board.Names[slot]]
	if not quest or board.Claimed[slot] then return false end
	return (board.Progress[slot] or 0) >= quest.Goal
end

return table.freeze(QuestsCore)
