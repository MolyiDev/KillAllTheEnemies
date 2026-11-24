-- The Mutation Lab's rules, the same on both sides and in both places: the energy each enemy kind drops
-- (TData.TEnemyEnergy), what a brew of two kinds takes and makes (Data/Potions), the rarity it comes out at and what
-- that rarity adds, the daily brews, and the potion slots. The lobby brews and equips (MutationService), a match drops
-- the energy and drinks what is equipped as it starts (the Game place's MutationService).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local ShopCore = require(ReplicatedStorage.GlobalShared.Core.ShopCore)
local ERarities = require(ReplicatedStorage.Types.Enums.ERarities)
local TData = require(ReplicatedStorage.Types.TData)
local TProfile = require(ReplicatedStorage.Types.TProfile)

-- What one potion adds for a match: a run upgrade (an EUpgradesIds value) and how much.
export type TEffect = { Upgrade: number, Amount: number }

-- A potion slot as the screen lists it: the free one, the one the pass opens, the one bought with Gems.
export type TSlotKind = "Free" | "Pass" | "Gems"
export type TSlot = { Kind: TSlotKind, IsOpen: boolean }

local PotionsCore = {}

-- Free brews every UTC day; VIP and the Extra Daily Brew pass add one each.
PotionsCore.BREWS_PER_DAY = 2
-- One brew bought with Robux once the day's are used (EProducts.ExtraBrew), and the most one BREW makes at once.
PotionsCore.BREW_ROBUX = 25
PotionsCore.MAX_BATCH = 25
-- The second (or third) slot, bought once for good.
PotionsCore.GEM_SLOT_PRICE = 500000
-- What a potion of each rarity adds, times its upgrades' Value, and how often each comes out of a brew (weights): the
-- run upgrade cards' (UpgradesCore), so a potion reads like a card of its rarity.
PotionsCore.MULTIPLIERS = table.freeze({
	[ERarities.Common] = 1,
	[ERarities.Uncommon] = 1.1,
	[ERarities.Rare] = 1.25,
	[ERarities.Epic] = 1.5,
	[ERarities.Legendary] = 2,
	[ERarities.Mythic] = 3,
})
local RARITY_WEIGHTS = table.freeze({
	{ Rarity = ERarities.Common, Weight = 450 },
	{ Rarity = ERarities.Uncommon, Weight = 250 },
	{ Rarity = ERarities.Rare, Weight = 150 },
	{ Rarity = ERarities.Epic, Weight = 100 },
	{ Rarity = ERarities.Legendary, Weight = 40 },
	{ Rarity = ERarities.Mythic, Weight = 10 },
})
-- The Luck pass multiplies these rarities' weights (ShopCore.Luck).
local LUCKY = table.freeze({
	[ERarities.Epic] = true,
	[ERarities.Legendary] = true,
	[ERarities.Mythic] = true,
})
-- The share of each of its souls a potion gives back when dissolved, by rarity (rounded down).
PotionsCore.REFUNDS = table.freeze({
	[ERarities.Common] = 0.25,
	[ERarities.Uncommon] = 0.3,
	[ERarities.Rare] = 0.4,
	[ERarities.Epic] = 0.5,
	[ERarities.Legendary] = 0.75,
	[ERarities.Mythic] = 1,
})
-- The matches a potion lasts: the best rarity two, every other one.
PotionsCore.MYTHIC_MATCHES = 2

-- A rarity's ERarities key (how a potion saves it), and back.
PotionsCore.RARITY_NAMES = table.freeze((function()
	local names = {}
	for name, rarity in ERarities do
		names[rarity] = name
	end
	return names
end)()) :: { [number]: string }

-- Every kind that drops energy, in data Id order (the lab's cards left to right, the boss last).
PotionsCore.ENERGIES = table.freeze((function()
	local list: { TData.TEnemy } = {}
	for _, enemy in DataCore.Enemies.All do
		if enemy.Energy then list[#list + 1] = enemy end
	end
	return list
end)())

local recipes: { [string]: TData.TPotion } = {}

local function pairKey(a: number, b: number): string
	return if a < b then `{a}:{b}` else `{b}:{a}`
end

for _, potion in DataCore.Potions.All do
	local key = pairKey(potion.Energies[1], potion.Energies[2])
	assert(recipes[key] == nil, `[PotionsCore] two recipes for {key}`)
	recipes[key] = potion
end

-- The recipe two different kinds of energy brew (enemy data Ids, either order), or nil.
function PotionsCore.RecipeOf(a: number, b: number): TData.TPotion?
	if a == b then return nil end
	return recipes[pairKey(a, b)]
end

-- What a potion of `potion` at `rarity` adds, its first energy's upgrade first.
function PotionsCore.Effects(potion: TData.TPotion, rarity: number): { TEffect }
	local scale = PotionsCore.MULTIPLIERS[rarity] or 1
	local effects = table.create(#potion.Energies)
	for index, enemyId in potion.Energies do
		local energy = (DataCore.Enemies.ById[enemyId] :: TData.TEnemy).Energy :: TData.TEnemyEnergy
		local upgrade = DataCore.Upgrades.ById[energy.Upgrade]
		effects[index] = { Upgrade = energy.Upgrade, Amount = upgrade.Value * scale }
	end

	return effects
end

-- An effect's line, as the run upgrade's card words it ("+15% gun damage").
function PotionsCore.Describe(effect: TEffect): string
	local upgrade = DataCore.Upgrades.ById[effect.Upgrade]
	return string.format(upgrade.Description, math.floor(effect.Amount * upgrade.PercentScale + 0.5))
end

function PotionsCore.MatchesOf(rarity: number): number
	return if rarity == ERarities.Mythic then PotionsCore.MYTHIC_MATCHES else 1
end

-- `roll` is in [0, 1); `luck` multiplies the lucky rarities' weights.
function PotionsCore.RollRarity(roll: number, luck: number): number
	local total = 0
	for _, entry in RARITY_WEIGHTS do
		total += entry.Weight * (if LUCKY[entry.Rarity] then luck else 1)
	end

	local pick = roll * total
	for _, entry in RARITY_WEIGHTS do
		pick -= entry.Weight * (if LUCKY[entry.Rarity] then luck else 1)
		if pick < 0 then return entry.Rarity end
	end

	return ERarities.Common
end

-- Each rarity's chance out of a brew, 0 to 1, with `luck`.
function PotionsCore.Chances(luck: number): { [number]: number }
	local total = 0
	for _, entry in RARITY_WEIGHTS do
		total += entry.Weight * (if LUCKY[entry.Rarity] then luck else 1)
	end

	local chances = {}
	for _, entry in RARITY_WEIGHTS do
		chances[entry.Rarity] = entry.Weight * (if LUCKY[entry.Rarity] then luck else 1) / total
	end

	return chances
end

-- The free brews a day for `profile`. The passes add nothing where paid random items are restricted: there a brew a
-- pass gives would be a random prize bought with Robux.
function PotionsCore.BrewsPerDay(profile: TProfile.TProfile, isRandomRestricted: boolean): number
	local count = PotionsCore.BREWS_PER_DAY
	if isRandomRestricted then return count end
	if ShopCore.HasPass(profile, "Vip") then
		count += 1
	end
	if ShopCore.HasPass(profile, "ExtraBrew") then
		count += 1
	end
	return count
end

-- Free brews left on UTC day `today` out of `perDay`.
function PotionsCore.FreeBrewsLeft(mutation: TProfile.TMutation?, today: number, perDay: number): number
	if not mutation or mutation.BrewDay ~= today then return perDay end
	return math.max(perDay - mutation.BrewsUsed, 0)
end

-- Every brew that can go now: the day's free ones left and the bought ones.
function PotionsCore.BrewsLeft(mutation: TProfile.TMutation?, today: number, perDay: number): number
	return PotionsCore.FreeBrewsLeft(mutation, today, perDay) + (if mutation then mutation.BrewsBought or 0 else 0)
end

-- The souls a potion of `potion` at `rarity` gives back when dissolved, in its energies' order (enemy data Ids).
function PotionsCore.Refund(potion: TData.TPotion, rarity: number): { number }
	local share = PotionsCore.REFUNDS[rarity] or 0
	local amounts = table.create(#potion.Energies)
	for index, enemyId in potion.Energies do
		local energy = (DataCore.Enemies.ById[enemyId] :: TData.TEnemy).Energy :: TData.TEnemyEnergy
		amounts[index] = math.floor(energy.Cost * share)
	end

	return amounts
end

-- The slots in the order the screen shows them: the open ones first (free, then the pass's, then the Gems'), then the
-- closed ones (the Gems' before the pass's). So holding the pass, its slot is the second and the Gems' the third.
function PotionsCore.Slots(profile: TProfile.TProfile): { TSlot }
	local hasPass = ShopCore.HasPass(profile, "PotionSlot")
	local mutation = profile.Mutation
	local hasGems = mutation ~= nil and mutation.HasGemSlot == true
	local slots: { TSlot } = { { Kind = "Free", IsOpen = true } }
	if hasPass then table.insert(slots, { Kind = "Pass", IsOpen = true }) end
	if hasGems then table.insert(slots, { Kind = "Gems", IsOpen = true }) end
	if not hasGems then table.insert(slots, { Kind = "Gems", IsOpen = false }) end
	if not hasPass then table.insert(slots, { Kind = "Pass", IsOpen = false }) end
	return slots
end

-- How many potions can be equipped at once.
function PotionsCore.SlotCount(profile: TProfile.TProfile): number
	local count = 1
	if ShopCore.HasPass(profile, "PotionSlot") then
		count += 1
	end
	if profile.Mutation and profile.Mutation.HasGemSlot then
		count += 1
	end
	return count
end

-- A profile's lab before its first energy.
function PotionsCore.Empty(): TProfile.TMutation
	return {
		Energy = {},
		Potions = {},
		Equipped = {},
		NextId = 1,
		BrewDay = 0,
		BrewsUsed = 0,
		Found = {},
		HasGemSlot = false,
	}
end

return table.freeze(PotionsCore)
