-- What a Robux purchase's receipt shows (the card that drops and the lines it prints), read off the catalog for an
-- offer granted, received or sent as a gift, and when each of its beats plays. Plain functions: the controller owns
-- the queue and the clock, Receipt draws.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local LoadoutCore = require(ReplicatedStorage.GlobalShared.Core.LoadoutCore)
local ShopCore = require(ReplicatedStorage.GlobalShared.Core.ShopCore)
local Parts = require(script.Parent.Parts)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local Palette = Theme.Palette
local GEM = Color3.fromRGB(89, 191, 255)

-- Seconds. The charge (the dim falls, the light gathers) and the drop make the landing; the tab and the name follow
-- it; the lines print a little after, the gaps closing (each SHRINK of the last, not under FLOOR) so they rattle out
-- faster toward the end; a count rolls a little longer for each digit.
local Timing = table.freeze({
	CHARGE = 0.3,
	DROP = 0.16,
	TAB = 0.1,
	NAME = 0.2,
	ROWS = 0.62,
	STAGGER = 0.4,
	STAGGER_FLOOR = 0.2,
	STAGGER_SHRINK = 0.9,
	SLIDE = 0.24,
	ROLL = 0.32,
	ROLL_PER_DIGIT = 0.06,
	RIBBON_AFTER = 0.22,
	FINALE_AFTER = 0.25,
	BUTTON_AFTER = 0.35,
	-- A press lands everything at once, the lines still to come rippling down this far apart (all in one frame, their
	-- rings and flashes stacked into one blur); CONTINUE comes in HURRIED_BUTTON after the last.
	HURRIED_RIPPLE = 0.04,
	HURRIED_BUTTON = 0.12,
})

-- How hard it lands, by the price: the reveal sound of that rarity.
local TIERS = table.freeze({
	{ Below = 300, Tier = "Epic" },
	{ Below = 800, Tier = "Legendary" },
})
local TOP_TIER = "Mythic"

-- What a pass gives, a line each.
local PERKS: { [string]: { Types.TReceiptRow } } = table.freeze({
	DoubleGems = {
		{ Count = 2, Prefix = "", Suffix = "x", Text = "GEMS FROM EVERY RUN", Accent = GEM, Picture = EIcons.Gem },
	},
	DoubleXp = {
		{
			Count = 2,
			Prefix = "",
			Suffix = "x",
			Text = "XP FROM EVERY RUN",
			Accent = Palette.Violet,
			Picture = EIcons.Rank,
		},
	},
	ExtraSpin = {
		{ Count = 1, Text = "FREE DAILY SPIN, EVERY DAY", Accent = Palette.Green, Picture = EIcons.PrizeWheel },
	},
	Luck = {
		{
			Count = 2,
			Prefix = "",
			Suffix = "x",
			Text = "LUCK ON SPINS AND BREWS",
			Accent = Palette.Green,
			Picture = EIcons.Clover,
		},
	},
	PotionSlot = {
		{ Count = 1, Text = "POTION SLOT IN THE LAB", Accent = Palette.Pink, Picture = EIcons.PotionBottle },
	},
	ExtraBrew = {
		{ Count = 1, Text = "FREE DAILY BREW, EVERY DAY", Accent = Palette.Violet, Picture = EIcons.Cauldron },
	},
})

local Receipts = {}

Receipts.Timing = Timing

-- Who a receipt is for: Giver is who gave it to this player ("" for none), Receiver who this player gave it to (nil
-- for none). Refund is the Gems the server paid in place of what this player held already (a gun owned, a pass held:
-- Shop.Granted's). IsRestricted hides what paid random items give.
export type TContext = {
	Giver: string,
	Receiver: string?,
	Refund: number,
	IsRestricted: boolean,
}

local function tierOf(robux: number): string
	for _, step in TIERS do
		if robux < step.Below then return step.Tier end
	end

	return TOP_TIER
end

local function gemsRow(amount: number, paysGems: boolean): Types.TReceiptRow
	return { Count = amount, Text = "GEMS", Accent = GEM, Picture = EIcons.Gem, PaysGems = paysGems }
end

local function gunRow(name: string): Types.TReceiptRow
	local data = LoadoutCore.ByName[name]
	local rarity = Parts.RARITIES[if data then data.Rarity else "Common"]
	return {
		Text = string.upper(name),
		Accent = rarity.Accent,
		Gun = name,
		Tag = { Text = rarity.Text, Color = rarity.Accent, IsInk = rarity.IsInk },
	}
end

local function vipRows(isRestricted: boolean): { Types.TReceiptRow }
	local gold = Palette.Gold
	local rows: { Types.TReceiptRow } = {
		{ Text = "VIP TAG IN CHAT AND OVER YOUR HEAD", Accent = gold, Picture = EIcons.Crown },
		{
			Count = math.floor(ShopCore.VIP_GEMS * 100),
			Suffix = "%",
			Text = "MORE GEMS FROM EVERY RUN",
			Accent = GEM,
			Picture = EIcons.Gem,
		},
	}
	if isRestricted then return rows end
	table.insert(
		rows,
		{ Count = 1, Text = "MORE FREE DAILY SPIN", Accent = Palette.Green, Picture = EIcons.PrizeWheel }
	)
	table.insert(
		rows,
		{ Count = 1, Text = "MORE DAILY BREW IN THE LAB", Accent = Palette.Violet, Picture = EIcons.Cauldron }
	)
	return rows
end

-- What `offer` gave, a line each, in its card's order. A gift's Gems go to the receiver, so none fly here.
local function contentRows(offer: ShopCore.TOffer, context: TContext, featuredGun: string): { Types.TReceiptRow }
	local paysGems = context.Receiver == nil
	-- A pass or bundle given to a player who held it is paid whole as its Robux in Gems (ShopService's grant), which
	-- no gun's price refunded beside a bundle's contents comes to.
	if offer.GamePassId ~= 0 and context.Refund == ShopCore.RobuxToGems(offer.Robux) then
		return { gemsRow(context.Refund, paysGems) }
	end
	if offer.Section == "Passes" then
		if offer.Name == "Vip" then return vipRows(context.IsRestricted) end
		return PERKS[offer.Name] or {}
	end

	local rows: { Types.TReceiptRow } = {}
	for _, content in offer.Contents do
		if content.Kind == "Gems" then
			table.insert(rows, gemsRow(content.Amount :: number, paysGems))
		elseif content.Kind == "Gun" then
			table.insert(rows, gunRow(content.Name :: string))
		elseif content.Kind == "FeaturedGun" then
			table.insert(rows, gunRow(featuredGun))
		elseif content.Kind == "Class" then
			local class = DataCore.Classes.ById[content.ClassId :: number]
			table.insert(rows, {
				Text = `{string.upper(if class then class.Name else "Human")} CLASS`,
				Accent = Palette.Pink,
				Picture = if class then class.Icon else EIcons.ClassHuman,
				Tag = { Text = "CLASS", Color = Palette.Pink, IsInk = false },
			})
		end
	end

	if context.Refund > 0 then
		table.insert(rows, {
			Count = context.Refund,
			Text = "GEMS FOR GUNS YOU OWN",
			Accent = GEM,
			Picture = EIcons.Gem,
			PaysGems = paysGems,
		})
	end

	-- A Gem pack's bonus over the smallest one, as its card words it.
	if offer.Section == "Gems" then
		local bonus = ShopCore.GemsBonus(offer)
		if bonus > 0.05 then
			table.insert(rows, {
				Count = math.floor(bonus * 100),
				Suffix = "%",
				Text = "MORE THAN THE SMALLEST PACK",
				Accent = Palette.Gold,
				Picture = EIcons.ArrowUp,
				IsTinted = true,
			})
		end
	end

	return rows
end

-- The receipt for `offer` (`featuredGun` is the gun on show when it was paid for).
function Receipts.Build(offer: ShopCore.TOffer, context: TContext, featuredGun: string): Types.TReceipt
	local look = Parts.LOOKS[offer.Name]
	local isPass = offer.Section == "Passes"
	local tab = "THANK YOU!"
	if context.Receiver then
		tab = if context.Receiver ~= "" then `GIFT TO {string.upper(context.Receiver)}` else "GIFT SENT!"
	elseif context.Giver ~= "" then
		tab = `FROM {string.upper(context.Giver)}`
	end

	local receipt: Types.TReceipt = {
		Offer = offer.Name,
		Tab = tab,
		Name = if offer.Subtitle then `{offer.Title} {offer.Subtitle}` else offer.Title,
		Accent = if look then look.Accent else Palette.Pink,
		Picture = if look then look.Picture else nil,
		Art = if look then look.Art else "Orbit",
		ArtAccent = if look then look.Accent else Palette.Pink,
		Rows = contentRows(offer, context, featuredGun),
		Tier = tierOf(offer.Robux),
	}

	if offer.Section == "Gems" then
		receipt.Name = "GEM PACK"
	elseif offer.Rarity then
		-- The featured gun: its own model on the card, in the weapons stage's look of its rarity.
		local data = LoadoutCore.ByName[featuredGun]
		receipt.Name = string.upper(featuredGun)
		receipt.Gun = featuredGun
		receipt.ArtAccent = Parts.RARITIES[if data then data.Rarity else offer.Rarity].Accent
		-- Gold on the pink card, as the gold pass wears pink.
		receipt.Ribbon = "NEW"
		receipt.RibbonColor = Palette.Gold
		receipt.RibbonIsInk = true
	end

	-- A pass is for good; the gold one wears a pink ribbon, so the ribbon never vanishes into its card's edge.
	if isPass and context.Refund == 0 then
		local isGold = receipt.Accent == Palette.Gold
		receipt.Ribbon = "FOREVER"
		receipt.RibbonColor = if isGold then Palette.Pink else Palette.Gold
		receipt.RibbonIsInk = not isGold
	end

	return receipt
end

-- The receipt for a friend's first join by this player's invite (Invites.Rewarded): `name` is the friend's, and
-- `friends` of the most there can be have paid now. The surprise gift's (`isGift`) lands as hard as anything sold.
function Receipts.Invite(name: string, gems: number, friends: number, most: number, isGift: boolean): Types.TReceipt
	return {
		Offer = "",
		Tab = if isGift then "GIFT UNLOCKED!" else "FRIEND JOINED!",
		Name = string.upper(name),
		Accent = Palette.Green,
		Picture = if isGift then EIcons.InviteGift else EIcons.AddFriend,
		Art = "Rays",
		-- The lobby's INVITE FRIENDS card glows pink; the gift's box is tied in gold.
		ArtAccent = if isGift then Palette.Gold else Palette.Pink,
		Tier = if isGift then TOP_TIER else "Legendary",
		Rows = {
			gemsRow(gems, true),
			{
				Count = friends,
				Prefix = "",
				Suffix = ` / {most}`,
				Text = "FRIENDS INVITED",
				Accent = Palette.Green,
				Picture = EIcons.AddFriend,
			},
		},
	}
end

-- How long a count rolls up: a little longer for every digit.
function Receipts.RollSeconds(count: number): number
	return Timing.ROLL + Timing.ROLL_PER_DIGIT * math.floor(math.log10(math.max(1, count)))
end

-- The beats of `receipt` shown at `at`.
function Receipts.Plan(receipt: Types.TReceipt, at: number): Types.TReceiptPlan
	local slamAt = at + Timing.CHARGE + Timing.DROP
	local rows = table.create(#receipt.Rows)
	local printAt = slamAt + Timing.ROWS
	local stagger = Timing.STAGGER
	local lastDone = printAt
	for index, row in receipt.Rows do
		local landAt = printAt + Timing.SLIDE
		local count = row.Count or 0
		local stampAt = landAt + if count > 0 then Receipts.RollSeconds(count) else 0
		rows[index] = { PrintAt = printAt, LandAt = landAt, StampAt = stampAt }
		lastDone = math.max(lastDone, stampAt)
		printAt += stagger
		stagger = math.max(Timing.STAGGER_FLOOR, stagger * Timing.STAGGER_SHRINK)
	end

	local ribbonAt = if receipt.Ribbon then lastDone + Timing.RIBBON_AFTER else lastDone
	local finaleAt = ribbonAt + Timing.FINALE_AFTER
	return {
		At = at,
		SlamAt = slamAt,
		TabAt = slamAt + Timing.TAB,
		NameAt = slamAt + Timing.NAME,
		Rows = rows,
		RibbonAt = ribbonAt,
		FinaleAt = finaleAt,
		ButtonAt = finaleAt + Timing.BUTTON_AFTER,
		HurriedAt = math.huge,
	}
end

-- `plan` with everything still to come landed at `now`, the lines still to stamp rippling down after it, and CONTINUE
-- a beat after the last.
function Receipts.Hurry(plan: Types.TReceiptPlan, now: number): Types.TReceiptPlan
	local rows = table.create(#plan.Rows)
	local nextAt, last = now, now
	for index, row in plan.Rows do
		if row.StampAt <= now then
			rows[index] = row
			continue
		end
		local at = nextAt
		nextAt += Timing.HURRIED_RIPPLE
		last = at
		rows[index] = {
			PrintAt = math.min(row.PrintAt, at),
			LandAt = math.min(row.LandAt, at),
			StampAt = at,
		}
	end

	return {
		At = plan.At,
		SlamAt = math.min(plan.SlamAt, now),
		TabAt = math.min(plan.TabAt, now),
		NameAt = math.min(plan.NameAt, now),
		Rows = rows,
		RibbonAt = math.min(plan.RibbonAt, now),
		FinaleAt = math.min(plan.FinaleAt, now),
		ButtonAt = math.min(plan.ButtonAt, last + Timing.HURRIED_BUTTON),
		HurriedAt = math.min(plan.HurriedAt, now),
	}
end

-- The Gems a receipt flies into the pill.
function Receipts.GemsPaid(receipt: Types.TReceipt): number
	local gems = 0
	for _, row in receipt.Rows do
		if row.PaysGems then
			gems += row.Count or 0
		end
	end

	return gems
end

return table.freeze(Receipts)
