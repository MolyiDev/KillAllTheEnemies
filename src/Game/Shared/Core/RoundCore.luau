-- How big, how hard and how rewarding each round is (GDD 5, 14). Pure functions of the round number and the party,
-- so RoundService and any client readout agree without being told, and the numbers can be checked in lune. Every
-- number here is a first pass for playtesting, not the tuning sheet the GDD asks for.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TData = require(ReplicatedStorage.Types.TData)

local RoundCore = {}

local Tune = table.freeze({
	BASE_COUNT = 8,
	COUNT_PER_ROUND = 4,
	-- Each extra player adds this share of a solo round (GDD 7: scale pressure for party size).
	COUNT_PER_EXTRA_PLAYER = 0.5,
	HEALTH_PER_ROUND = 0.08,
	DAMAGE_PER_ROUND = 0.04,
	SPEED_PER_ROUND = 0.01,
	MAX_SPEED_SCALE = 1.4,
	-- Rewards for a cleared round.
	ROUND_GOLD = 25,
	ROUND_GOLD_PER_ROUND = 5,
	ROUND_GEMS = 2,
	BOSS_ROUND_GEMS = 20,
	-- XP is a percentage of a level (GDD 5: percentage-based XP).
	ROUND_XP_PERCENT = 4,
	-- Kill Gold grows slowly with the round so late rounds keep paying for late prices.
	KILL_GOLD_PER_ROUND = 0.05,
	SKIP_AFTER_SECONDS = 5,
	FAST_START_ROUNDS = 5,
})

RoundCore.BOSS_EVERY = 15
RoundCore.PREPARE_SECONDS = 5
-- With this many bodies or fewer left to kill, nothing still to come, they are shown to everyone and outlined.
RoundCore.LAST_SHOWN = 2
-- Spawns are metered so a round pours in rather than appearing at once; the client attaches up to eight rigs a
-- frame (EnemiesController), so this never outruns it.
RoundCore.SPAWNS_PER_SECOND = 20

function RoundCore.IsBossRound(round: number): boolean
	return round > 0 and round % RoundCore.BOSS_EVERY == 0
end

-- Seconds `round` must run before everyone's vote can skip it (no boss up); the next opens beside it (GDD 21). The
-- opening waves can be skipped the moment they start, so a party that wants a fast start waits out only the
-- countdown.
function RoundCore.GetSkipAfterSeconds(round: number): number
	return if round <= Tune.FAST_START_ROUNDS then 0 else Tune.SKIP_AFTER_SECONDS
end

-- Ordinary bodies in `round`. A boss round has these and its boss on top.
function RoundCore.GetCount(round: number, playerCount: number): number
	local solo = Tune.BASE_COUNT + Tune.COUNT_PER_ROUND * (round - 1)
	local party = 1 + Tune.COUNT_PER_EXTRA_PLAYER * math.max(playerCount - 1, 0)
	return math.floor(solo * party + 0.5)
end

-- (health, damage, speed) multipliers for a body spawned in `round`. A boss also scales with the party, since it
-- is the one body everyone shoots at.
function RoundCore.GetScales(round: number): (number, number, number)
	local step = round - 1
	local speed = math.min(1 + Tune.SPEED_PER_ROUND * step, Tune.MAX_SPEED_SCALE)
	return 1 + Tune.HEALTH_PER_ROUND * step, 1 + Tune.DAMAGE_PER_ROUND * step, speed
end

function RoundCore.GetBossHealthScale(round: number, playerCount: number): number
	return (1 + Tune.HEALTH_PER_ROUND * (round - 1)) * (1 + 0.75 * math.max(playerCount - 1, 0))
end

function RoundCore.GetKillGold(enemyData: TData.TEnemy, round: number): number
	return math.floor(enemyData.GoldDrop * (1 + Tune.KILL_GOLD_PER_ROUND * (round - 1)) + 0.5)
end

-- (gold, gems, xpPercent) every player present earns for clearing `round`.
function RoundCore.GetClearRewards(round: number): (number, number, number)
	local gems = if RoundCore.IsBossRound(round) then Tune.BOSS_ROUND_GEMS else Tune.ROUND_GEMS
	return Tune.ROUND_GOLD + Tune.ROUND_GOLD_PER_ROUND * (round - 1), gems, Tune.ROUND_XP_PERCENT
end

-- Whether `enemyData` comes on `mapName` (TEnemy.Maps).
function RoundCore.IsOnMap(enemyData: TData.TEnemy, mapName: string): boolean
	local maps = enemyData.Maps
	return maps == nil or table.find(maps, mapName) ~= nil
end

-- Every ordinary type that can appear in `round` on `mapName` into `out` (cleared first), with its weight summed into
-- the return.
function RoundCore.GetPool(round: number, mapName: string, all: { TData.TEnemy }, out: { TData.TEnemy }): number
	table.clear(out)
	local totalWeight = 0
	for _, enemyData in all do
		if enemyData.IsBoss or enemyData.IntroRound > round or enemyData.SpawnWeight <= 0 then continue end
		if not RoundCore.IsOnMap(enemyData, mapName) then continue end
		out[#out + 1] = enemyData
		totalWeight += enemyData.SpawnWeight
	end

	return totalWeight
end

-- The boss for `round` on `mapName`: the boss whose IntroRound is the highest at or under it, so a roster can rotate.
function RoundCore.GetBoss(round: number, mapName: string, all: { TData.TEnemy }): TData.TEnemy?
	local best: TData.TEnemy? = nil
	for _, enemyData in all do
		if not enemyData.IsBoss or enemyData.IntroRound > round then continue end
		if not RoundCore.IsOnMap(enemyData, mapName) then continue end
		if not best or enemyData.IntroRound > best.IntroRound then best = enemyData end
	end

	return best
end

-- One weighted draw from a pool built by GetPool. `roll` is in [0, 1).
function RoundCore.Draw(pool: { TData.TEnemy }, totalWeight: number, roll: number): TData.TEnemy?
	local pick = roll * totalWeight
	for _, enemyData in pool do
		pick -= enemyData.SpawnWeight
		if pick < 0 then return enemyData end
	end

	return pool[#pool]
end

return RoundCore
