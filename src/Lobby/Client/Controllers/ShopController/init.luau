-- The shop screen (UIMatt.md, Robux Shop): the featured gun and class bundle, the bundles, the Gem packs and the
-- passes, each bought with a Roblox prompt or given to another player here (Gift). ShopService decides and grants;
-- this shows what it is told (Shop.State) and celebrates what it grants (Shop.Granted), what a gift sent became and
-- what a friend's join by this player's invite paid (Invites.Rewarded): a receipt (Receipt) plays over every lobby screen once Roblox's own dialog has closed, one at a time, and the Gems it
-- paid fly out of its Gems line into the HUD's pill (GemPayout), held back from the pill until they land; as it
-- leaves, the offer's card behind it cheers and its price turns OWNED. The lobby's SHOP card and the pill's + open
-- the shop; while it is up the world is blurred and muffled.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local vide = require(ReplicatedStorage.Packages.vide)
local NetworkMeta = require(StarterPlayer.StarterPlayerScripts.GlobalClient.NetworkMeta)
-- Through PlayerScripts, the copy that runs: requiring the StarterPlayer one would load a second controller.
local BlurController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.BlurController)
local LobbyEnteringController = require(script.Parent.LobbyEnteringController)
local GemPayout = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.GemPayout)
local LoadingGate = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.LoadingGate)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local ShopCore = require(ReplicatedStorage.GlobalShared.Core.ShopCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local Parts = require(script.Parts)
local Receipt = require(script.Receipt)
local Receipts = require(script.Receipts)
local Screen = require(script.Screen)
local Types = require(script.Types)

local ServerNetworkShop = NetworkMeta.Server.Shop
local ClientNetworkShop = NetworkMeta.Client.Shop
local ServerNetworkInvites = NetworkMeta.Server.Invites
local LocalPlayer = Players.LocalPlayer
local Palette = Theme.Palette
local source = vide.source
local create = vide.create

local Tune = table.freeze({
	-- The screen is his 1920 x 1080, fitted inside the viewport whole.
	DESIGN = Vector2.new(1920, 1080),
	-- Above the lobby's HUD, under the settings screen and the Gems pill's own gui.
	DISPLAY_ORDER = 5,
	-- It is drawn this long after it is shut, for its way out.
	LEAVE_SECONDS = 0.45,
	-- How long the clock keeps ticking after a stamp: the longest gesture is shorter.
	MOTION_SECONDS = 2.2,
	-- A tab's glide through the scroll.
	GLIDE_SECONDS = 0.45,
	-- A hero page's arrival (the slide, the chips, the strike) is over by then.
	PAGE_SETTLE = 1.4,
	-- A prompt nobody answered stops holding its price in and lifts its dim.
	PROMPT_TIMEOUT = 120,
	-- While Roblox's dialog is up the screen sinks under this much more black, so the dialog is what is looked at.
	PROMPT_DIM = 0.5,
	PROMPT_DIM_IN = 0.3,
	PROMPT_DIM_OUT = 0.25,
	-- The receipt: over every lobby screen (5) and under the level plate and the Gems pill (LobbyController's Top, 7),
	-- so the Gems it pays fly over its dim into the pill. It waits for Roblox's dialog at most MAX_DIALOG_WAIT after
	-- its grant; its clock ticks this long past CONTINUE's arrival; the light crosses its card every CALL_EVERY while
	-- it waits, ticking for CALL_SECONDS.
	RECEIPT_DISPLAY_ORDER = 6,
	MAX_DIALOG_WAIT = 10,
	RECEIPT_SETTLE = 0.5,
	CALL_EVERY = 2.6,
	-- A line's count ticks this many times as it rolls up.
	ROLL_TICKS = 8,
	CALL_SECONDS = 0.7,
})

-- What a receipt's landing and lines sound like: its weight's reveal, and a line's stamp by what it is.
local REVEALS = table.freeze({ Epic = "RevealEpic", Legendary = "RevealLegendary", Mythic = "RevealMythic" })
local STAMP_SOUND = "PickRare"
local UNLOCK_SOUND = "PickLegendary"

local GIFT_REFUSED = 1

local ShopController = {}

local state: Types.TShopState = {
	Scale = source(1),
	Now = source(os.clock()),
	IsOpen = source(false),
	ToggledAt = source(-math.huge),
	Owned = source({} :: { [string]: boolean }),
	IsRestricted = source(true),
	HasFeatured = source(false),
	FeaturedEndsAt = source(os.time() + ShopCore.FeaturedSecondsLeft(os.time())),
	Clock = source(0),
	Page = source(1),
	PagePrev = source(1),
	PageStep = source(1),
	PageAt = source(-math.huge),
	PageShown = source(0),
	IsHeroHeld = source(false),
	Section = source("Featured" :: ShopCore.TSection),
	SectionAt = source(-math.huge),
	PressedAt = source({} :: { [string]: number }),
	GrantedAt = source({} :: { [string]: number }),
	RefusedAt = source({} :: { [string]: number }),
	IsPrompting = source(false),
	PromptToggledAt = source(-math.huge),
	GiftOffer = source(nil :: string?),
	GiftToggledAt = source(-math.huge),
	GiftPlayers = source({} :: { Types.TGiftPlayer }),
	Message = source(""),
	MessageColor = source(Palette.Gold),
	MessageAt = source(-math.huge),
	Receipt = source(nil :: Types.TReceipt?),
	ReceiptPlan = source(nil :: Types.TReceiptPlan?),
	ReceiptNow = source(os.clock()),
	ReceiptLeftAt = source(math.huge),
	ReceiptCalledAt = source(-math.huge),
}

-- os.clock until which Now keeps ticking, and of the last frame stepped (the hero's page counts the time between).
local motionUntil = -math.huge
local lastStep = os.clock()
-- The scroll and each section's top in it, and a glide in progress.
local scroll: ScrollingFrame? = nil
local sectionTops: { [string]: number } = {}
local glide: { From: number, To: number, At: number }? = nil
-- The pill the Gems fly to, the flight, and the receipt's design root (where its lines' Gems burst from).
local gemsTarget: GuiObject? = nil
local payout: GemPayout.TPayout? = nil
local receiptRoot: GuiObject? = nil
-- Gems granted and not landed yet.
local heldGems = source(0)
local isLandingGems = source(false)
-- The receipts waiting their turn, each with when its grant came in.
local queue: { { Receipt: Types.TReceipt, At: number } } = {}
-- How dim the screen was under the dialog when that last changed, so a turn mid-fade carries on from there.
local promptDimFrom = 0
-- os.clock until which the receipt's clock keeps ticking, and when the light next crosses its card.
local receiptUntil = -math.huge
local nextCall = math.huge
-- The beats of the receipt on show that have played: its landing and ribbon, each line's print and stamp,
-- and how many times each line's count has ticked.
local played = { Slam = false, Ribbon = false }
local printed: { boolean } = {}
local stamped: { boolean } = {}
local ticks: { number } = {}

-- Whether the screen is up. Reads a vide source, so a view that calls it follows it.
function ShopController.IsOpen(): boolean
	return state.IsOpen()
end

-- The Gems the shop paid that have not flown into the HUD's pill yet. Reads a vide source.
function ShopController.HeldGems(): number
	return heldGems()
end

-- Whether the shop's Gems are landing in the pill now. Reads a vide source.
function ShopController.IsLandingGems(): boolean
	return isLandingGems()
end

-- Whether a receipt is on show or waiting its turn, so the lobby opens nothing of its own over it.
function ShopController.HasReceipt(): boolean
	return state.Receipt() ~= nil or #queue > 0
end

-- Where the Gems fly to: the glyph on the lobby HUD's Gems pill.
function ShopController.SetGemsTarget(glyph: GuiObject)
	gemsTarget = glyph
end

local function stir(seconds: number)
	motionUntil = math.max(motionUntil, os.clock() + seconds)
end

-- Stamps `name` in a per-offer stamp table and keeps Now ticking for it.
local function stampOffer(stamps: Types.Source<{ [string]: number }>, name: string, at: number?)
	local copy = table.clone(stamps())
	copy[name] = at or os.clock()
	stamps(copy)
	stir(Tune.MOTION_SECONDS)
end

local function clearOffer(stamps: Types.Source<{ [string]: number }>, name: string)
	if not stamps()[name] then return end
	local copy = table.clone(stamps())
	copy[name] = nil
	stamps(copy)
end

local function say(text: string, color: Color3)
	vide.batch(function()
		state.Message(text)
		state.MessageColor(color)
		state.MessageAt(os.clock())
	end)
	stir(4)
end

-- 0 to 1: how far the screen has sunk under Roblox's dialog. Reads vide sources.
local function promptDim(): number
	local isPrompting = state.IsPrompting()
	local seconds = if isPrompting then Tune.PROMPT_DIM_IN else Tune.PROMPT_DIM_OUT
	local t = Motion.Out(Motion.Progress(state.Now(), state.PromptToggledAt(), seconds))
	return Motion.Lerp(promptDimFrom, if isPrompting then 1 else 0, t)
end

local function setPrompting(isOn: boolean)
	if state.IsPrompting() == isOn then return end
	promptDimFrom = promptDim()
	vide.batch(function()
		state.IsPrompting(isOn)
		state.PromptToggledAt(os.clock())
	end)
	stir(math.max(Tune.PROMPT_DIM_IN, Tune.PROMPT_DIM_OUT) + 0.1)
end

local function refuse(name: string)
	stampOffer(state.RefusedAt, name)
	SoundsCore.PlayUINamed("UI.UpgradePick", "Denied")
end

local function glideTo(section: ShopCore.TSection)
	local frame, top = scroll, sectionTops[section]
	if not frame or not top then return end
	-- CanvasPosition is in the canvas's own unscaled px (UI.md, the scrollbar under a UIScale), as the tops are.
	local most = math.max(frame.CanvasSize.Y.Offset - frame.Size.Y.Offset, 0)
	glide = { From = frame.CanvasPosition.Y, To = math.min(top, most), At = os.clock() }
	stir(Tune.GLIDE_SECONDS + 0.1)
end

function ShopController.Open(section: ShopCore.TSection?)
	if state.IsOpen() then
		if section then glideTo(section) end
		return
	end

	-- The screen opens its scroll on the section it is built on.
	vide.batch(function()
		state.IsOpen(true)
		state.ToggledAt(os.clock())
		state.Section(section or "Featured")
		state.Clock(os.time())
		state.Page(1)
		state.PagePrev(1)
		state.PageAt(-math.huge)
		state.PageShown(0)
		state.IsHeroHeld(false)
	end)
	stir(Tune.MOTION_SECONDS)
	SoundsCore.SetMuffled("Shop", true)
	BlurController.SetBlurred("Shop", true)
end

local function closeGift()
	if not state.GiftOffer() then return end
	vide.batch(function()
		state.GiftOffer(nil)
		state.GiftToggledAt(os.clock())
	end)
	stir(0.5)
end

function ShopController.Close()
	if not state.IsOpen() then return end
	closeGift()
	vide.batch(function()
		state.IsOpen(false)
		state.ToggledAt(os.clock())
	end)
	stir(Tune.MOTION_SECONDS)
	SoundsCore.SetMuffled("Shop", false)
	BlurController.SetBlurred("Shop", false)
end

local function giftPlayers(): { Types.TGiftPlayer }
	local list = {}
	for _, player in Players:GetPlayers() do
		if player == LocalPlayer then continue end
		table.insert(list, { UserId = player.UserId, Name = player.Name, DisplayName = player.DisplayName })
	end
	table.sort(list, function(a, b)
		return string.lower(a.DisplayName) < string.lower(b.DisplayName)
	end)

	return list
end

-- The hero card turns to `page` (wrapped round its pages), sliding the way `step` says.
local function turnTo(page: number, step: number)
	page = (page - 1) % #Parts.HERO + 1
	if page == state.Page() then return end
	vide.batch(function()
		state.PagePrev(state.Page())
		state.Page(page)
		state.PageStep(step)
		state.PageAt(os.clock())
		state.PageShown(0)
	end)
	stir(Tune.PAGE_SETTLE)
end

local actions: Types.TShopActions = {
	Close = ShopController.Close,
	TurnPage = function(step: number)
		turnTo(state.Page() + step, step)
		SoundsCore.PlayClick()
	end,
	PickPage = function(page: number)
		if page == state.Page() then return end
		turnTo(page, if page > state.Page() then 1 else -1)
		SoundsCore.PlayClick()
	end,
	PickSection = function(section: ShopCore.TSection)
		state.SectionAt(os.clock())
		glideTo(section)
		SoundsCore.PlayClick()
	end,
	-- A pass through Roblox's game pass prompt, anything else through its product prompt; the price holds in until the
	-- prompt is answered.
	Buy = function(name: string)
		local offer = ShopCore.ByName[name]
		if not offer then return end
		local id = if offer.GamePassId ~= 0 then offer.GamePassId else offer.ProductId
		if id == 0 or (offer.IsRandomItem and state.IsRestricted()) then
			refuse(name)
			return
		end

		stampOffer(state.PressedAt, name)
		setPrompting(true)
		if offer.GamePassId ~= 0 then
			MarketplaceService:PromptGamePassPurchase(LocalPlayer, offer.GamePassId)
		else
			MarketplaceService:PromptProductPurchase(LocalPlayer, offer.ProductId)
		end
	end,
	OpenGift = function(name: string)
		local offer = ShopCore.ByName[name]
		if not offer or offer.GiftProductId == 0 or (offer.IsRandomItem and state.IsRestricted()) then
			refuse(name)
			return
		end

		vide.batch(function()
			state.GiftPlayers(giftPlayers())
			state.GiftOffer(name)
			state.GiftToggledAt(os.clock())
		end)
		stir(1)
	end,
	CloseGift = closeGift,
	-- The server checks the pick and prompts the gift product; its answer comes back as GiftResult.
	SendGift = function(userId: number)
		local name = state.GiftOffer()
		if not name then return end
		local index = table.find(ShopCore.OFFERS, ShopCore.ByName[name])
		if not index then return end
		closeGift()
		stampOffer(state.PressedAt, name)
		setPrompting(true)
		ClientNetworkShop.Gift.Fire(index, userId)
	end,
	MarkScroll = function(frame: ScrollingFrame, tops: { [ShopCore.TSection]: number })
		scroll = frame
		sectionTops = tops
	end,
	Stir = stir,
}

-- ============================== The receipt ==============================

local function stirReceipt(seconds: number)
	receiptUntil = math.max(receiptUntil, os.clock() + seconds)
end

-- Queues a receipt; the Gems it will fly are held back from the pill from now, the frame the server paid them.
local function enqueue(receipt: Types.TReceipt)
	if #receipt.Rows == 0 then return end
	local gems = Receipts.GemsPaid(receipt)
	if gems > 0 then heldGems(heldGems() + gems) end
	table.insert(queue, { Receipt = receipt, At = os.clock() })
end

-- The receipt for `offer`, granted to this player (`giver` "" when bought) or given by them to `receiver`.
local function receiptOf(offer: ShopCore.TOffer, giver: string, receiver: string?, refund: number): Types.TReceipt
	return Receipts.Build(offer, {
		Giver = giver,
		Receiver = receiver,
		Refund = refund,
		IsRestricted = state.IsRestricted(),
	}, ShopCore.FeaturedGun(os.time()))
end

local function showReceipt(receipt: Types.TReceipt, now: number)
	played.Slam, played.Ribbon = false, false
	table.clear(printed)
	table.clear(stamped)
	table.clear(ticks)
	local plan = Receipts.Plan(receipt, now)
	-- The plan before the receipt: the view is built as the receipt arrives and reads it at once.
	vide.batch(function()
		state.ReceiptNow(now)
		state.ReceiptPlan(plan)
		state.ReceiptLeftAt(math.huge)
		state.ReceiptCalledAt(-math.huge)
		state.Receipt(receipt)
	end)
	nextCall = plan.ButtonAt + Tune.CALL_EVERY
	stirReceipt(plan.ButtonAt - now + Tune.RECEIPT_SETTLE)
	SoundsCore.SetMuffled("Receipt", true)
	BlurController.SetBlurred("Receipt", true)
	SoundsCore.PlayUINamed("UI.UpgradePick", "Open")
end

-- Whether a receipt is up and still revealing (a press lands it all), or over and waiting for CONTINUE.
local function isRevealing(now: number): boolean
	local plan = state.ReceiptPlan()
	return state.Receipt() ~= nil and plan ~= nil and now < plan.ButtonAt
end

local function isWaiting(now: number): boolean
	local plan = state.ReceiptPlan()
	return state.Receipt() ~= nil and plan ~= nil and now >= plan.ButtonAt and state.ReceiptLeftAt() == math.huge
end

local function hurryReceipt(now: number)
	local plan = state.ReceiptPlan()
	if not plan or not isRevealing(now) or plan.HurriedAt < math.huge then return end
	local hurried = Receipts.Hurry(plan, now)
	state.ReceiptPlan(hurried)
	nextCall = hurried.ButtonAt + Tune.CALL_EVERY
	stirReceipt(hurried.ButtonAt - now + Tune.RECEIPT_SETTLE)
end

local function continueReceipt()
	local now = os.clock()
	if not isWaiting(now) then return end
	state.ReceiptLeftAt(now)
	stirReceipt(Receipt.LEAVE_SECONDS + 0.1)
	SoundsCore.SetMuffled("Receipt", false)
	BlurController.SetBlurred("Receipt", false)
end

local receiptActions: Types.TReceiptActions = {
	Press = function()
		local now = os.clock()
		if isRevealing(now) then
			hurryReceipt(now)
		else
			continueReceipt()
		end
	end,
	Continue = continueReceipt,
}

-- A line's Gems burst out of its icon into the pill; what other flights still hold stays held. With no pill or no
-- receipt to fly from, the hold lets go and the pill rolls them up.
local function payGems(receipt: Types.TReceipt, index: number, now: number)
	local gems = receipt.Rows[index].Count or 0
	local flight, root, glyph = payout, receiptRoot, gemsTarget
	if not flight or not root or not glyph or not glyph.Parent then
		heldGems(math.max(heldGems() - gems, 0))
		return
	end

	-- Worked out rather than read off the icon: a hurried line is placed in the same frame, before it is laid out.
	local place = Receipt.Place(#receipt.Rows)
	local from = root.AbsolutePosition + Receipt.IconAt(place, index) * state.Scale()
	local others = heldGems() - gems
	flight.Burst(from, gems, now, function(owed: number)
		heldGems(math.max(others, 0) + owed)
		isLandingGems(owed > 0)
		SoundsCore.PlayUINamed("UI.UpgradePick", "Tick")
	end)
end

-- The receipt's beats due this frame: its sounds, its lines' ticks and Gems, the light's calls while it waits, and its
-- end, when the offer's card behind it cheers. A hurry plays every beat at once, without the lines' sounds.
local function stepReceipt(now: number)
	local receipt, plan = state.Receipt(), state.ReceiptPlan()
	if not receipt or not plan then return end
	local isHurried = plan.HurriedAt <= now

	if not played.Slam and now >= plan.SlamAt then
		played.Slam = true
		SoundsCore.PlayUINamed("UI.UpgradePick", REVEALS[receipt.Tier])
	end
	for index, rowPlan in plan.Rows do
		if stamped[index] then continue end
		local data = receipt.Rows[index]
		local count = data.Count or 0
		if not printed[index] and now >= rowPlan.PrintAt then
			printed[index] = true
			if not isHurried then SoundsCore.PlayUINamed("UI.UpgradePick", "Deal") end
		end
		if now >= rowPlan.StampAt then
			stamped[index] = true
			if not isHurried then
				SoundsCore.PlayUINamed("UI.UpgradePick", if data.Tag then UNLOCK_SOUND else STAMP_SOUND)
			end
			if data.PaysGems and count > 0 then payGems(receipt, index, now) end
		elseif count > 0 and not isHurried and now >= rowPlan.LandAt then
			local tick = math.floor((now - rowPlan.LandAt) / (rowPlan.StampAt - rowPlan.LandAt) * Tune.ROLL_TICKS)
			if tick > (ticks[index] or 0) then
				ticks[index] = tick
				SoundsCore.PlayUINamed("UI.UpgradePick", "Tick")
			end
		end
	end
	if receipt.Ribbon and not played.Ribbon and now >= plan.RibbonAt then
		played.Ribbon = true
		SoundsCore.PlayUINamed("UI.Index", "Unlock")
	end

	local leftAt = state.ReceiptLeftAt()
	if leftAt == math.huge and now >= nextCall then
		nextCall = now + Tune.CALL_EVERY
		state.ReceiptCalledAt(now)
		stirReceipt(Tune.CALL_SECONDS)
	end
	if now < leftAt + Receipt.LEAVE_SECONDS then return end

	-- Gone: the plan stays, so nothing still reading it as the view is taken down finds it missing.
	state.Receipt(nil)
	stampOffer(state.GrantedAt, receipt.Offer, now)
end

-- The next receipt, once the loading screen has lifted (a purchase made outside the game is granted on joining,
-- under it), the one before has gone, Roblox's dialog has closed (or it was waited on long enough) and the lobby is
-- not showing the last run's results.
local function pump(now: number)
	if not LoadingGate.IsLifted then return end
	if state.Receipt() or #queue == 0 or LobbyEnteringController.IsOpen() then return end
	local entry = queue[1]
	if state.IsPrompting() and now - entry.At < Tune.MAX_DIALOG_WAIT then return end
	table.remove(queue, 1)
	showReceipt(entry.Receipt, now)
end

-- A key or a pad button (not a stick) lands the reveal at once; once it is over, a confirming one continues.
local function onInput(input: InputObject, isTaken: boolean)
	-- Typed into chat, or taken by a focused button (AWESOME! answers its own press).
	if isTaken then return end
	local now = os.clock()
	local key = input.KeyCode
	if isRevealing(now) then
		local kind = input.UserInputType
		local isPad = string.sub(kind.Name, 1, 7) == "Gamepad"
		local isStick = key == Enum.KeyCode.Thumbstick1 or key == Enum.KeyCode.Thumbstick2
		if kind == Enum.UserInputType.Keyboard or (isPad and not isStick) then hurryReceipt(now) end
		return
	end

	if
		key == Enum.KeyCode.Return
		or key == Enum.KeyCode.KeypadEnter
		or key == Enum.KeyCode.ButtonA
		or key == Enum.KeyCode.ButtonB
	then
		continueReceipt()
	end
end

local function updateScale()
	local viewport = Workspace.CurrentCamera.ViewportSize
	state.Scale(math.max(math.min(viewport.Y / Tune.DESIGN.Y, viewport.X / Tune.DESIGN.X), 0.01))
end

-- Each frame: the glide, the receipt's turn and beats, a prompt nobody answered, the countdown's second.
local function step(now: number)
	local current = glide
	local frame = scroll
	if current and frame then
		local t = Motion.Progress(now, current.At, Tune.GLIDE_SECONDS)
		frame.CanvasPosition = Vector2.new(0, Motion.Lerp(current.From, current.To, Motion.Decelerate(t)))
		if t >= 1 then glide = nil end
	end

	-- Before its beats: one leaving this frame lets the next in on the frame after, so the view is built again.
	pump(now)
	stepReceipt(now)

	for name, at in state.PressedAt() do
		if now - at > Tune.PROMPT_TIMEOUT then clearOffer(state.PressedAt, name) end
	end
	if state.IsPrompting() and now - state.PromptToggledAt() > Tune.PROMPT_TIMEOUT then setPrompting(false) end

	if state.IsOpen() then
		local second = os.time()
		if second ~= state.Clock() then state.Clock(second) end
	end

	-- The hero's page counts on while it is looked at and nothing is over the shop, and turns on by itself.
	local dt = now - lastStep
	lastStep = now
	local isPaused = state.IsHeroHeld() or state.IsPrompting() or state.GiftOffer() ~= nil or state.Receipt() ~= nil
	if state.IsOpen() and not isPaused then
		local shown = state.PageShown() + dt
		if shown >= Parts.PAGE_SECONDS then
			turnTo(state.Page() + 1, 1)
		else
			state.PageShown(shown)
		end
	end
end

ShopController.OnStart = function()
	local isPayingOut = source(false)
	vide.mount(function()
		-- Drawn only while it is up or still leaving: shut, it costs nothing.
		local isDrawn = vide.derive(function(): boolean
			return state.IsOpen() or state.Now() - state.ToggledAt() < Tune.LEAVE_SECONDS
		end)
		-- Once for both its bindings, which then sit still while Now ticks for the rest of the screen.
		local promptDimmed = vide.derive(promptDim)
		local built = GemPayout.Build(state.Scale, function(): Vector2?
			local glyph = gemsTarget
			if not glyph or not glyph.Parent then return nil end
			return glyph.AbsolutePosition + glyph.AbsoluteSize / 2
		end)
		payout = built

		local receiptFrame = create("Frame")({
			Name = "Root",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(Tune.DESIGN.X, Tune.DESIGN.Y),
			BackgroundTransparency = 1,
			create("UIScale")({ Scale = state.Scale }),
			-- Built once per receipt: one leaves (nil) a frame before the next comes.
			vide.show(state.Receipt, function()
				local pieces = Receipt.Build(state, state.Receipt() :: Types.TReceipt, receiptActions)
				vide.cleanup(function()
					for _, piece in pieces do
						if typeof(piece) == "Instance" then piece:Destroy() end
					end
				end)
				return pieces
			end),
		})
		receiptRoot = receiptFrame

		return {
			create("ScreenGui")({
				Name = "Shop",
				ResetOnSpawn = false,
				IgnoreGuiInset = true,
				ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
				DisplayOrder = Tune.DISPLAY_ORDER,
				Enabled = isDrawn,
				create("Frame")({
					Name = "Root",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(Tune.DESIGN.X, Tune.DESIGN.Y),
					BackgroundTransparency = 1,
					create("UIScale")({ Scale = state.Scale }),
					-- Built only while it is up or leaving: shut, its gun pictures are gone too.
					vide.show(function()
						return state.IsOpen() or state.Now() - state.ToggledAt() < Tune.LEAVE_SECONDS
					end, function()
						local pieces = Screen.Build(state, actions)
						vide.cleanup(function()
							scroll = nil
							glide = nil
							for _, piece in pieces do
								if typeof(piece) == "Instance" then piece:Destroy() end
							end
						end)
						return pieces
					end),
				}),
				-- Over every piece of the screen while Roblox's dialog is up, taking the clicks meant for them.
				create("TextButton")({
					Name = "PromptDim",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(4, 4),
					ZIndex = 2,
					BackgroundColor3 = Color3.new(),
					BorderSizePixel = 0,
					AutoButtonColor = false,
					Text = "",
					BackgroundTransparency = function()
						return 1 - Tune.PROMPT_DIM * promptDimmed()
					end,
					Visible = function()
						return promptDimmed() > 0
					end,
				}),
			}),
			-- The receipt, and the Gems flying into the pill over its dim.
			create("ScreenGui")({
				Name = "Receipt",
				ResetOnSpawn = false,
				IgnoreGuiInset = true,
				ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
				DisplayOrder = Tune.RECEIPT_DISPLAY_ORDER,
				Enabled = function()
					return state.Receipt() ~= nil or isPayingOut()
				end,
				receiptFrame,
				built.Layer,
			}),
		}
	end, LocalPlayer:WaitForChild("PlayerGui"))

	-- Now (and the receipt's own clock) is written only while something moves, so a screen at rest, open or shut,
	-- redraws nothing.
	RunService.PreRender:Connect(function()
		local now = os.clock()
		vide.batch(function()
			step(now)
			if now < motionUntil then state.Now(now) end
			if now < receiptUntil then state.ReceiptNow(now) end
		end)

		local current = payout
		local isBusy = current ~= nil and current.Step(now)
		if isBusy ~= isPayingOut() then isPayingOut(isBusy) end
		if not isBusy and isLandingGems() then isLandingGems(false) end
	end)

	local camera = Workspace.CurrentCamera
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	updateScale()
end

UserInputService.InputBegan:Connect(onInput)

-- A prompt answered: Roblox's dialog is down, so a receipt may play; a no lets the price go at once; a yes waits for
-- the server's Granted.
MarketplaceService.PromptProductPurchaseFinished:Connect(
	function(userId: number, productId: number, isPurchased: boolean)
		if userId ~= LocalPlayer.UserId then return end
		setPrompting(false)
		local entry = ShopCore.ByProduct[productId]
		if entry and not isPurchased then clearOffer(state.PressedAt, entry.Offer.Name) end
	end
)
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, isPurchased: boolean)
	if player ~= LocalPlayer then return end
	setPrompting(false)
	local offer = ShopCore.ByPass[passId]
	if offer and not isPurchased then clearOffer(state.PressedAt, offer.Name) end
end)

ServerNetworkShop.State.On(function(owned: { number }, isRestricted: boolean, secondsLeft: number, hasFeatured: boolean)
	local byName = {}
	for _, index in owned do
		local offer = ShopCore.OFFERS[index]
		if offer then byName[offer.Name] = true end
	end

	vide.batch(function()
		state.Owned(byName)
		state.IsRestricted(isRestricted)
		state.FeaturedEndsAt(os.time() + secondsLeft)
		state.HasFeatured(hasFeatured)
	end)
end)

-- In the same frame as the profile it changed, so the hold puts the pill back before it draws the new Gems. The price
-- lets go now; the card cheers once the receipt has left.
ServerNetworkShop.Granted.On(function(index: number, giver: string, refund: number)
	local offer = ShopCore.OFFERS[index]
	if not offer then return end
	clearOffer(state.PressedAt, offer.Name)
	enqueue(receiptOf(offer, giver, nil, refund))
end)

ServerNetworkShop.GiftResult.On(function(index: number, receiver: string, result: number)
	local offer = ShopCore.OFFERS[index]
	if not offer then return end
	clearOffer(state.PressedAt, offer.Name)
	if result == GIFT_REFUSED then
		-- Refused before Roblox's dialog came up, so nothing will answer it.
		setPrompting(false)
		refuse(offer.Name)
		say(
			if receiver ~= "" then `{string.upper(receiver)} CANNOT TAKE THIS GIFT` else "THEY LEFT THE SERVER",
			Palette.Pink
		)
		return
	end

	enqueue(receiptOf(offer, "", receiver, 0))
end)

-- In the same frame as the profile it paid, as Granted.
ServerNetworkInvites.Rewarded.On(function(name: string, gems: number, friends: number, most: number, isGift: boolean)
	enqueue(Receipts.Invite(name, gems, friends, most, isGift))
end)

return Ignis.Register(ShopController)
