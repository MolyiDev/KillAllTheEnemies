-- The shop screen's state and actions, shared by the controller and its views.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ShopCore = require(ReplicatedStorage.GlobalShared.Core.ShopCore)

export type Source<T> = (() -> T) & ((value: T) -> T)

-- A player in this server the gift list offers.
export type TGiftPlayer = {
	UserId: number,
	Name: string,
	DisplayName: string,
}

-- One line of a receipt. `Count` rolls up from 0 between `Prefix` ("+" when nil) and `Suffix`, then `Text` in the
-- accent; a line with no count is `Text` alone, in white. Its icon is `Gun` (the gun's own model) or `Picture`.
export type TReceiptRow = {
	Count: number?,
	Prefix: string?,
	Suffix: string?,
	Text: string,
	Accent: Color3,
	Picture: string?,
	-- Tinted by the accent: a white-plastic mark.
	IsTinted: boolean?,
	Gun: string?,
	-- A flat tag at the line's right end (a gun's rarity, CLASS).
	Tag: { Text: string, Color: Color3, IsInk: boolean }?,
	-- Its Gems fly on into the HUD's pill once it has rolled up.
	PaysGems: boolean?,
}

-- What a receipt shows: the card that drops (its tab of thanks over its top edge, its name, its picture standing in
-- a Showcase look) and the lines it prints, a ribbon on a pass bought for good, and how hard it lands.
export type TReceipt = {
	-- The offer's Name: its card in the shop cheers once the receipt has left.
	Offer: string,
	Tab: string,
	Name: string,
	Accent: Color3,
	Picture: string?,
	Gun: string?,
	Art: string,
	ArtAccent: Color3,
	Rows: { TReceiptRow },
	Ribbon: string?,
	RibbonColor: Color3?,
	RibbonIsInk: boolean?,
	-- The landing's weight by the price: "Epic", "Legendary" or "Mythic" (its reveal sound).
	Tier: string,
}

-- When each beat of a receipt plays, in os.clock. Replaced whole (never changed in place) when a press hurries it.
export type TReceiptRowPlan = {
	-- It starts sliding out from under the card, lands home (its count starts rolling), and stamps.
	PrintAt: number,
	LandAt: number,
	StampAt: number,
}

export type TReceiptPlan = {
	At: number,
	SlamAt: number,
	TabAt: number,
	NameAt: number,
	Rows: { TReceiptRowPlan },
	RibbonAt: number,
	FinaleAt: number,
	ButtonAt: number,
	-- When a press landed everything at once; math.huge if none did.
	HurriedAt: number,
}

export type TShopState = {
	-- Screen px per design px.
	Scale: Source<number>,
	-- os.clock, written only while something moves.
	Now: Source<number>,
	IsOpen: Source<boolean>,
	ToggledAt: Source<number>,
	-- The passes and bundles this player holds, by offer Name (Shop.State).
	Owned: Source<{ [string]: boolean }>,
	IsRestricted: Source<boolean>,
	-- Whether this player owns the featured gun of the moment.
	HasFeatured: Source<boolean>,
	-- os.time of the next featured gun, and the whole seconds the screen's countdown reads (ticked once a second while
	-- the screen is up).
	FeaturedEndsAt: Source<number>,
	Clock: Source<number>,
	-- The section the scroll is in: the lit tab.
	Section: Source<ShopCore.TSection>,
	SectionAt: Source<number>,
	-- Per offer Name, os.clock stamps: the price pressed (a prompt is up), the offer granted (the card cheers), a buy
	-- refused (the price shakes).
	PressedAt: Source<{ [string]: number }>,
	GrantedAt: Source<{ [string]: number }>,
	RefusedAt: Source<{ [string]: number }>,
	-- Whether a Robux dialog this screen asked for is up, and when that last changed: the screen dims under it.
	IsPrompting: Source<boolean>,
	PromptToggledAt: Source<number>,
	-- The gift list: the offer it gifts (nil while shut), when it opened or shut, and who it offers.
	GiftOffer: Source<string?>,
	GiftToggledAt: Source<number>,
	GiftPlayers: Source<{ TGiftPlayer }>,
	-- The line under the title (a gift sent, refused or received), its colour and when it changed.
	Message: Source<string>,
	MessageColor: Source<Color3>,
	MessageAt: Source<number>,
	-- The receipt on show (nil while none is), its beats, and its own clock (os.clock, written only while it moves),
	-- so the shop behind it redraws nothing while it plays. Left: when CONTINUE was pressed, math.huge while it is
	-- up. Called: the last time the light crossed its card while it waits.
	Receipt: Source<TReceipt?>,
	ReceiptPlan: Source<TReceiptPlan?>,
	ReceiptNow: Source<number>,
	ReceiptLeftAt: Source<number>,
	ReceiptCalledAt: Source<number>,
}

export type TReceiptActions = {
	-- A press during the reveal lands it all at once; once it is over, it continues.
	Press: () -> (),
	Continue: () -> (),
}

export type TShopActions = {
	Close: () -> (),
	PickSection: (section: ShopCore.TSection) -> (),
	Buy: (name: string) -> (),
	OpenGift: (name: string) -> (),
	CloseGift: () -> (),
	SendGift: (userId: number) -> (),
	-- The views hand over what the controller moves: the scroll and each section's top in it.
	MarkScroll: (frame: ScrollingFrame, tops: { [ShopCore.TSection]: number }) -> (),
	Stir: (seconds: number) -> (),
}

return nil
