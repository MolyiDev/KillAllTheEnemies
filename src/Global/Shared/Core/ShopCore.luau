-- The shop's catalog and its rules, the same on both sides (ShopService grants, ShopController shows): every offer,
-- what it holds and costs, the featured gun of the moment, and what the passes add. A pass or a bundle is kept in the
-- profile by its Name (TProfile.Entitlements), whether it was bought here, on the game's page, or given.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LoadoutCore = require(ReplicatedStorage.GlobalShared.Core.LoadoutCore)
local EClassesIds = require(ReplicatedStorage.Types.Enums.Data.EClassesIds)
local EGamePasses = require(ReplicatedStorage.Types.Enums.EGamePasses)
local EProducts = require(ReplicatedStorage.Types.Enums.EProducts)
local TProfile = require(ReplicatedStorage.Types.TProfile)

-- One thing an offer gives. "FeaturedGun" is the gun on show when it is paid for (ShopCore.FeaturedGun).
export type TContent = {
	Kind: "Gems" | "Gun" | "Class" | "FeaturedGun",
	Amount: number?,
	Name: string?,
	ClassId: number?,
}

export type TSection = "Featured" | "Bundles" | "Gems" | "Passes"

export type TOffer = {
	Name: string,
	Section: TSection,
	-- The words on its card, his two lines for a featured one (the second in the accent).
	Title: string,
	Subtitle: string?,
	-- What the store page and the pass's row say.
	Description: string,
	Robux: number,
	-- A developer product to buy it for oneself, 0 for a pass.
	ProductId: number,
	-- A game pass, 0 for a product. Owned for good once bought.
	GamePassId: number,
	-- The developer product that buys it for somebody else.
	GiftProductId: number,
	Contents: { TContent },
	-- A paid random item (the daily spins): never offered where PolicyService restricts them.
	IsRandomItem: boolean?,
	-- The featured gun's rarity this product sells.
	Rarity: string?,
}

local ShopCore = {}

-- The featured gun changes every three days, through the guns at the top of the ladder.
ShopCore.FEATURED_SECONDS = 3 * 86400
ShopCore.FEATURED_GUNS = table.freeze({
	"Sandan Gun",
	"Lavaforge",
	"UFO Bullpup",
	"Corrupted Runes AK",
	"Hacker Drum",
})

-- Gems a Robux buys in the smallest pack: what a bundle's saving is measured against.
local BASE_GEMS_PER_ROBUX = 1000 / 99

-- What VIP adds to the Gems a run pays.
ShopCore.VIP_GEMS = 0.1
-- What the Luck pass multiplies a lucky prize's weight by (SpinsCore.PRIZES' IsLucky).
ShopCore.LUCK = 2

local function gems(amount: number): TContent
	return { Kind = "Gems", Amount = amount }
end

local function gun(name: string): TContent
	assert(LoadoutCore.ByName[name], `ShopCore: no gun named {name}`)
	return { Kind = "Gun", Name = name }
end

local function pass(name: string, title: string, robux: number, description: string, isRandom: boolean?): TOffer
	return {
		Name = name,
		Section = "Passes",
		Title = title,
		Description = description,
		Robux = robux,
		ProductId = 0,
		GamePassId = (EGamePasses :: any)[name],
		GiftProductId = (EProducts :: any)[`Gift{name}`],
		Contents = {},
		IsRandomItem = isRandom,
	}
end

local function commas(value: number): string
	local text = tostring(math.floor(value))
	while true do
		local next, count = string.gsub(text, "^(-?%d+)(%d%d%d)", "%1,%2")
		text = next
		if count == 0 then return text end
	end
end

local function gemPack(name: string, amount: number, robux: number): TOffer
	return {
		Name = name,
		Section = "Gems",
		Title = `{commas(amount)} GEMS`,
		Description = `{commas(amount)} Gems to spend in the lobby on guns, abilities and more.`,
		Robux = robux,
		ProductId = (EProducts :: any)[name],
		GamePassId = 0,
		GiftProductId = (EProducts :: any)[`Gift{name}`],
		Contents = { gems(amount) },
	}
end

-- In the order the screen shows them, section by section.
ShopCore.OFFERS = table.freeze({
	{
		Name = "FeaturedLegendary",
		Section = "Featured",
		Title = "FEATURED",
		Description = "The featured Legendary gun (it changes every 3 days), yours for good, plus 2,500 Gems.",
		Robux = 799,
		ProductId = EProducts.FeaturedLegendary,
		GamePassId = 0,
		GiftProductId = EProducts.GiftFeaturedLegendary,
		Contents = { { Kind = "FeaturedGun" }, gems(2500) },
		Rarity = "Legendary",
	},
	{
		Name = "FeaturedMythic",
		Section = "Featured",
		Title = "FEATURED",
		Description = "The featured Mythic gun (it changes every 3 days), yours for good, plus 5,000 Gems.",
		Robux = 1499,
		ProductId = EProducts.FeaturedMythic,
		GamePassId = 0,
		GiftProductId = EProducts.GiftFeaturedMythic,
		Contents = { { Kind = "FeaturedGun" }, gems(5000) },
		Rarity = "Mythic",
	},
	{
		Name = "SurvivorBundle",
		Section = "Featured",
		Title = "SURVIVOR",
		Subtitle = "BUNDLE",
		Description = "Grants the following:\n- Human class\n- Sandan Gun (Legendary sniper)\n- 15,000 Gems",
		Robux = 899,
		ProductId = 0,
		GamePassId = EGamePasses.SurvivorBundle,
		GiftProductId = EProducts.GiftSurvivorBundle,
		Contents = { { Kind = "Class", ClassId = EClassesIds.Human }, gun("Sandan Gun"), gems(15000) },
	},
	{
		Name = "StarterPack",
		Section = "Bundles",
		Title = "STARTER PACK",
		Description = "Grants the following, once:\n- Desert Eagle\n- 5,000 Gems",
		Robux = 99,
		ProductId = 0,
		GamePassId = EGamePasses.StarterPack,
		GiftProductId = EProducts.GiftStarterPack,
		Contents = { gun("Desert Eagle"), gems(5000) },
	},
	{
		Name = "ArsenalBundle",
		Section = "Bundles",
		Title = "ARSENAL BUNDLE",
		Description = "Grants the following:\n- AWP Printstream\n- AWP The Prince\n- RPG Bazooka\n- Hacker Drum",
		Robux = 1199,
		ProductId = 0,
		GamePassId = EGamePasses.ArsenalBundle,
		GiftProductId = EProducts.GiftArsenalBundle,
		Contents = { gun("AWP Printstream"), gun("AWP The Prince"), gun("RPG Bazooka"), gun("Hacker Drum") },
	},
	gemPack("GemsSmall", 1000, 99),
	gemPack("GemsMedium", 5500, 449),
	gemPack("GemsLarge", 12000, 899),
	gemPack("GemsHuge", 30000, 1999),
	gemPack("GemsMega", 80000, 4499),
	pass(
		"Vip",
		"VIP",
		499,
		"A VIP tag over your head and in chat, 10% more Gems from every run, one more free daily spin and one more daily brew in the Mutation Lab."
	),
	pass("DoubleGems", "DOUBLE GEMS", 359, "Permanently double every Gem a run pays."),
	pass("DoubleXp", "DOUBLE XP", 249, "Permanently double every XP a run pays, so you level up twice as fast."),
	pass("ExtraSpin", "EXTRA DAILY SPIN", 149, "One more free daily spin, every day.", true),
	pass(
		"Luck",
		"2X LUCK",
		299,
		"Twice the luck on the daily spins and in the Mutation Lab: the best prizes and potions come up twice as often.",
		true
	),
	pass(
		"PotionSlot",
		"3RD POTION SLOT",
		399,
		"One more potion slot in the Mutation Lab: drink one more potion every match."
	),
	pass("ExtraBrew", "EXTRA DAILY BREW", 199, "One more free brew in the Mutation Lab, every day.", true),
} :: { TOffer })

ShopCore.ByName = {} :: { [string]: TOffer }
-- A developer product's offer, and whether it is the gift copy.
ShopCore.ByProduct = {} :: { [number]: { Offer: TOffer, IsGift: boolean } }
ShopCore.ByPass = {} :: { [number]: TOffer }
for _, offer in ShopCore.OFFERS do
	ShopCore.ByName[offer.Name] = offer
	if offer.ProductId ~= 0 then ShopCore.ByProduct[offer.ProductId] = { Offer = offer, IsGift = false } end
	if offer.GiftProductId ~= 0 then ShopCore.ByProduct[offer.GiftProductId] = { Offer = offer, IsGift = true } end
	if offer.GamePassId ~= 0 then ShopCore.ByPass[offer.GamePassId] = offer end
end
table.freeze(ShopCore.ByName)
table.freeze(ShopCore.ByProduct)
table.freeze(ShopCore.ByPass)

-- The gun on show at `now` (os.time), and the seconds until the next one.
function ShopCore.FeaturedGun(now: number): string
	local turn = math.floor(now / ShopCore.FEATURED_SECONDS)
	return ShopCore.FEATURED_GUNS[turn % #ShopCore.FEATURED_GUNS + 1]
end

function ShopCore.FeaturedSecondsLeft(now: number): number
	return ShopCore.FEATURED_SECONDS - now % ShopCore.FEATURED_SECONDS
end

-- The product that sells the gun on show at `now`: the one of its rarity.
function ShopCore.FeaturedOffer(now: number): TOffer
	local gunData = LoadoutCore.ByName[ShopCore.FeaturedGun(now)]
	for _, offer in ShopCore.OFFERS do
		if offer.Rarity == gunData.Rarity then return offer end
	end

	return ShopCore.ByName.FeaturedLegendary
end

-- Whether a game pass or a one-time bundle is in the profile.
function ShopCore.HasPass(profile: TProfile.TProfile, name: string): boolean
	return profile.Entitlements[name] == true
end

-- Whether `offer` cannot be bought again by this profile: a pass held, or the featured gun owned.
function ShopCore.IsOwned(profile: TProfile.TProfile, offer: TOffer, now: number): boolean
	if offer.GamePassId ~= 0 then return ShopCore.HasPass(profile, offer.Name) end
	if offer.Rarity then return profile.Loadout.Owned[ShopCore.FeaturedGun(now)] ~= nil end
	return false
end

-- Everything an offer gives, counted in Gems (a gun at its price). A class has no price yet.
function ShopCore.GemsWorth(offer: TOffer, now: number): number
	local worth = 0
	for _, content in offer.Contents do
		if content.Kind == "Gems" then
			worth += content.Amount :: number
		elseif content.Kind == "Gun" then
			worth += LoadoutCore.ByName[content.Name :: string].Price
		elseif content.Kind == "FeaturedGun" then
			worth += LoadoutCore.ByName[ShopCore.FeaturedGun(now)].Price
		end
	end

	return worth
end

-- How much cheaper an offer is than its worth in the smallest Gem pack, 0 to 1. A Gem pack's is its bonus over that
-- pack instead (negative here, so the screen words it as a bonus).
function ShopCore.Saving(offer: TOffer, now: number): number
	local worthRobux = ShopCore.GemsWorth(offer, now) / BASE_GEMS_PER_ROBUX
	if worthRobux <= 0 then return 0 end
	return 1 - offer.Robux / worthRobux
end

-- The share more Gems than the smallest pack gives for the same Robux.
function ShopCore.GemsBonus(offer: TOffer): number
	local amount = offer.Contents[1].Amount :: number
	return amount / (offer.Robux * BASE_GEMS_PER_ROBUX) - 1
end

-- What `robux` buys in the smallest Gem pack: a gift that cannot be held is paid as this.
function ShopCore.RobuxToGems(robux: number): number
	return math.floor(robux * BASE_GEMS_PER_ROBUX)
end

-- What the Gems a run pays are multiplied by.
function ShopCore.RunGemsScale(profile: TProfile.TProfile): number
	local scale = if ShopCore.HasPass(profile, "DoubleGems") then 2 else 1
	if ShopCore.HasPass(profile, "Vip") then
		scale += ShopCore.VIP_GEMS * scale
	end
	return scale
end

function ShopCore.RunXpScale(profile: TProfile.TProfile): number
	return if ShopCore.HasPass(profile, "DoubleXp") then 2 else 1
end

-- The free daily spins the passes add. Nothing where paid random items are restricted: there a pass's spin would be
-- a random prize bought with Robux.
function ShopCore.ExtraFreeSpins(profile: TProfile.TProfile, isRandomRestricted: boolean): number
	if isRandomRestricted then return 0 end
	local extra = 0
	if ShopCore.HasPass(profile, "ExtraSpin") then
		extra += 1
	end
	if ShopCore.HasPass(profile, "Vip") then
		extra += 1
	end
	return extra
end

function ShopCore.Luck(profile: TProfile.TProfile, isRandomRestricted: boolean): number
	if isRandomRestricted or not ShopCore.HasPass(profile, "Luck") then return 1 end
	return ShopCore.LUCK
end

return table.freeze(ShopCore)
