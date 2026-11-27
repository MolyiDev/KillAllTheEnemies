-- Developer product ids (GDD 19). 0 means not created yet: its offer is hidden and its handler never runs.
return table.freeze({
	-- Back up on the results, once the whole squad is down: the held run goes on (67 Robux).
	Revive = 3734217095,
	-- A downed player back up now during a run, bought by them (their down plate) or by a squadmate (the chip by the
	-- boss bar), 9 Robux.
	QuickRevive = 3736735611,
	-- CHARGE NOW under the HUD's ultimate: its meter full at once during a run, 19 Robux.
	ChargeUltimate = 3736778238,
	-- The results' DOUBLE YOUR GEMS, by how many Gems the run earned (Shared/Utils/doubleGems): 11, 22 and 33 Robux.
	DoubleGemsSmall = 3734217097,
	DoubleGemsMedium = 3734217103,
	DoubleGemsLarge = 3734217105,
	-- The HUD's money packs: 1,000 and 99,999 run Gold.
	GoldPackSmall = 3734121483,
	GoldPackLarge = 3734121486,
	-- The lobby's daily spins once the free ones are used: one, three or five more, cheaper a spin the more
	-- (SpinsCore.PRODUCTS, SpinsCore.PRICES).
	ExtraSpin = 3734872550,
	ExtraSpin3 = 3735766103,
	ExtraSpin5 = 3735766115,
	-- The Mutation Lab's BREW once the brews are used up: one, three, five or ten more, kept until brewed, cheaper a
	-- brew the more (PotionsCore.BREW_PRODUCTS, PotionsCore.BREW_PRICES).
	ExtraBrew = 3735423324,
	ExtraBrew3 = 3735766124,
	ExtraBrew5 = 3735766137,
	ExtraBrew10 = 3735766152,
	-- The HUD's buy-all items: heal and revive the whole squad, kill every enemy alive.
	HealAll = 3734121481,
	NukeAll = 3734121479,
	-- The lobby's shop (ShopCore.OFFERS): Gem packs, the featured gun by its rarity, and a gift copy of every offer
	-- (the same price, granted to the player picked in the gift list; a game pass cannot be bought for somebody else).
	GemsSmall = 3735378619,
	GemsMedium = 3735378711,
	GemsLarge = 3735378727,
	GemsHuge = 3735378746,
	GemsMega = 3735378761,
	FeaturedLegendary = 3735378778,
	FeaturedMythic = 3735378796,
	GiftGemsSmall = 3735378878,
	GiftGemsMedium = 3735378902,
	GiftGemsLarge = 3735378923,
	GiftGemsHuge = 3735378944,
	GiftGemsMega = 3735378953,
	GiftFeaturedLegendary = 3735379037,
	GiftFeaturedMythic = 3735379054,
	GiftSurvivorBundle = 3735379080,
	GiftStarterPack = 3735379100,
	GiftArsenalBundle = 3735379120,
	GiftDoubleGems = 3735379234,
	GiftDoubleXp = 3735379262,
	GiftExtraSpin = 3735379280,
	GiftVip = 3735379313,
	GiftLuck = 3735379332,
	GiftPotionSlot = 3735413162,
	GiftExtraBrew = 3735413177,
})
