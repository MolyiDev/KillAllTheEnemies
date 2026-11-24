-- The daily spins' rules, the same on both sides (SpinsService decides, SpinsController shows): two free spins a UTC
-- day, more bought one at a time with Robux (EProducts.ExtraSpin), each landing on one of seven prizes drawn by weight.
-- The reel shows the seven in this order, over and over; the server draws which one it stops on.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TProfile = require(ReplicatedStorage.Types.TProfile)

-- A prize: Gems, or XP as a share of a level in percent (the profile's Xp), and how often it is drawn against the
-- others. `IsJackpot` is the rare one, drawn in his violet and celebrated harder. `IsLucky`: the Luck pass multiplies
-- its weight (ShopCore.Luck).
export type TPrize = {
	Kind: "Gems" | "Xp",
	Amount: number,
	Weight: number,
	IsJackpot: boolean?,
	IsLucky: boolean?,
}

local SpinsCore = {}

SpinsCore.FREE_PER_DAY = 2
-- What an extra spin costs, as set on the product itself.
SpinsCore.ROBUX = 25

-- The reel's order, left to right as it rests (his seven cards: the violet one first, the blue ones fourth and last).
-- Weights are percent.
SpinsCore.PRIZES = table.freeze({
	table.freeze({ Kind = "Gems", Amount = 1000, Weight = 2, IsJackpot = true, IsLucky = true }),
	table.freeze({ Kind = "Gems", Amount = 60, Weight = 22 }),
	table.freeze({ Kind = "Gems", Amount = 100, Weight = 14 }),
	table.freeze({ Kind = "Xp", Amount = 50, Weight = 8, IsLucky = true }),
	table.freeze({ Kind = "Gems", Amount = 150, Weight = 8, IsLucky = true }),
	table.freeze({ Kind = "Gems", Amount = 25, Weight = 28 }),
	table.freeze({ Kind = "Xp", Amount = 25, Weight = 18 }),
} :: { TPrize })

-- Free spins left on UTC day `today` for a player with `spins` (nil: never spun), out of `perDay` (FREE_PER_DAY plus
-- what the passes add).
function SpinsCore.FreeLeft(spins: TProfile.TSpins?, today: number, perDay: number): number
	if not spins or spins.Day ~= today then return perDay end
	return math.max(perDay - spins.Used, 0)
end

-- A prize's index in PRIZES, drawn by weight, a lucky prize's multiplied by `luck`.
function SpinsCore.Draw(random: Random, luck: number): number
	local total = 0
	for _, prize in SpinsCore.PRIZES do
		total += prize.Weight * (if prize.IsLucky then luck else 1)
	end

	local roll = random:NextNumber() * total
	for index, prize in SpinsCore.PRIZES do
		roll -= prize.Weight * (if prize.IsLucky then luck else 1)
		if roll < 0 then return index end
	end

	return #SpinsCore.PRIZES
end

-- The prize the reel's slot `slot` holds: the seven repeat along the reel, slot 1 holding the first.
function SpinsCore.PrizeAt(slot: number): number
	return (slot - 1) % #SpinsCore.PRIZES + 1
end

return table.freeze(SpinsCore)
