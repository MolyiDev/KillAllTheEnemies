-- The rules of the run upgrades, pure so both sides agree without being told and the numbers can be checked in lune:
-- what a card adds, how a hand of three is dealt, what a redeal costs. UpgradesService deals and applies them; the
-- client reads the same tables for what a card says.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ERarities = require(ReplicatedStorage.Types.Enums.ERarities)
local TData = require(ReplicatedStorage.Types.TData)

export type TCard = { Id: number, Level: number, Rarity: number }

local UpgradesCore = {}

UpgradesCore.HAND_SIZE = 3
-- Seconds a hand stays up before the server picks: the next wave waits for the pick, so the others are waiting too.
UpgradesCore.AUTO_PICK_SECONDS = 12
-- Seconds the card taken stays on its picker's screen, held up and then dropping away (UpgradePickController's
-- HOLD_SECONDS and LEAVE_SECONDS). The picker is still picking until then: still safe, and still holding the match.
UpgradesCore.SHOW_SECONDS = 1.6
-- Gold the first redeal of a hand costs; each one after costs this much more.
UpgradesCore.REROLL_PRICE = 50
-- Armor never takes off more than this share of a blow.
UpgradesCore.MAX_ARMOR = 0.6

-- A rarer card is the same upgrade with more of it. The rarity is rolled for each card as it is dealt.
UpgradesCore.MULTIPLIERS = table.freeze({
	[ERarities.Common] = 1,
	[ERarities.Rare] = 1.25,
	[ERarities.Epic] = 1.5,
	[ERarities.Legendary] = 2,
	[ERarities.Mythic] = 3,
})
local RARITY_WEIGHTS = table.freeze({
	{ Rarity = ERarities.Common, Weight = 600 },
	{ Rarity = ERarities.Rare, Weight = 250 },
	{ Rarity = ERarities.Epic, Weight = 100 },
	{ Rarity = ERarities.Legendary, Weight = 40 },
	{ Rarity = ERarities.Mythic, Weight = 10 },
})
local RARITY_WEIGHT_TOTAL = 0
for _, entry in RARITY_WEIGHTS do
	RARITY_WEIGHT_TOTAL += entry.Weight
end

-- What a card of `data` at `rarity` adds to its stat.
function UpgradesCore.Amount(data: TData.TUpgrade, rarity: number): number
	return data.Value * (UpgradesCore.MULTIPLIERS[rarity] or 1)
end

-- The card's line: its own amount, as the player reads it.
function UpgradesCore.Describe(data: TData.TUpgrade, rarity: number): string
	return string.format(data.Description, math.floor(UpgradesCore.Amount(data, rarity) * data.PercentScale + 0.5))
end

-- Gold the next redeal of a hand costs, after `rerolls` of it.
function UpgradesCore.RerollPrice(rerolls: number): number
	return UpgradesCore.REROLL_PRICE * (rerolls + 1)
end

-- `roll` is in [0, 1).
function UpgradesCore.RollRarity(roll: number): number
	local pick = roll * RARITY_WEIGHT_TOTAL
	for _, entry in RARITY_WEIGHTS do
		pick -= entry.Weight
		if pick < 0 then return entry.Rarity end
	end

	return ERarities.Common
end

-- A hand of up to HAND_SIZE different upgrades for a player at `levels` (by upgrade id), fewer when fewer are left
-- under their MaxLevel and none when all are there. `shown` is the hand a redeal replaces: its upgrades are not dealt
-- again while enough others are left. A first hand (no `shown`) always holds one the player already has, when there
-- is one to hold, so a hand is never three strangers.
function UpgradesCore.Deal(
	all: { TData.TUpgrade },
	levels: { [number]: number },
	shown: { TCard }?,
	random: Random
): { TCard }
	local pool: { TData.TUpgrade } = {}
	local held: { TData.TUpgrade } = {}
	for _, data in all do
		if (levels[data.Id] or 0) >= data.MaxLevel then continue end
		held[#held + 1] = data
		local wasShown = false
		if shown then
			for _, card in shown do
				if card.Id == data.Id then wasShown = true end
			end
		end
		if not wasShown then pool[#pool + 1] = data end
	end

	local count = math.min(UpgradesCore.HAND_SIZE, #held)
	if #pool < count then pool = held end

	local hand: { TCard } = table.create(count)
	local function take(index: number)
		local data = table.remove(pool, index) :: TData.TUpgrade
		-- Anywhere in the hand, so the kept one is not always the first card.
		table.insert(hand, random:NextInteger(1, #hand + 1), {
			Id = data.Id,
			Level = (levels[data.Id] or 0) + 1,
			Rarity = UpgradesCore.RollRarity(random:NextNumber()),
		})
	end

	if not shown then
		local owned = {}
		for index, data in pool do
			if (levels[data.Id] or 0) > 0 then owned[#owned + 1] = index end
		end
		if #owned > 0 then take(owned[random:NextInteger(1, #owned)]) end
	end

	while #hand < count do
		take(random:NextInteger(1, #pool))
	end

	return hand
end

return UpgradesCore
