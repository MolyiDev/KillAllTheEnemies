-- The daily screen's SPIN page (UIMatt.md, Daily Spins): the reel, the free spins left today and SPIN, which sells an
-- extra spin for Robux once they are used (SpinsService decides each spin and what it lands on; this asks and shows).
-- DailyController owns the screen round it and shows the page (SetShown) and builds it into its gui (BuildPage).
--
-- A prize is shown in the order it is paid: the server tells the prize in the same frame as the profile it paid, so
-- the HUD's Gems and XP are held back by what is still to land (HeldGems, HeldXp) before they are drawn, and let
-- through a slice per piece as the prize flies into them (Payout). Selling a spin is a random item for Robux, so it is offered only where PolicyService
-- allows paid random items.
local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local vide = require(ReplicatedStorage.Packages.vide)
local NetworkMeta = require(StarterPlayer.StarterPlayerScripts.GlobalClient.NetworkMeta)
-- Through PlayerScripts, the copy that runs: requiring the StarterPlayer one would load a second controller.
local ProfileController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.ProfileController)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local SpinsCore = require(ReplicatedStorage.Shared.Core.SpinsCore)
local EProducts = require(ReplicatedStorage.Types.Enums.EProducts)
local Payout = require(script.Payout)
local Reel = require(script.Reel)
local ReelMotion = require(script.ReelMotion)
local Screen = require(script.Screen)
local Types = require(script.Types)

local ServerNetworkSpins = NetworkMeta.Server.Spins
local ClientNetworkSpins = NetworkMeta.Client.Spins
local LocalPlayer = Players.LocalPlayer
local source = vide.source
local create = vide.create

local Tune = table.freeze({
	-- The screen is his 1920 x 1080, fitted inside the viewport whole.
	DESIGN = Vector2.new(1920, 1080),
	-- How long the clock keeps ticking after a stamp: the longest gesture of an open is shorter.
	MOTION_SECONDS = 1.8,
	-- The prize sets off this long after the reel has landed.
	PAY_DELAY = 0.35,
	-- SPIN wobbles this long after the page starts coming in: once it has risen into place.
	BECKON_DELAY = 0.5,
	-- And this long after a spin's prize has landed, while another spin waits.
	AFTER_SPIN_BECKON_DELAY = 0.15,
	-- A spin the server never answered is given up after this long.
	ANSWER_TIMEOUT = 6,
	DAY_SECONDS = 86400,
	-- The gem on the HUD's Gems counter the prize flies into (LobbyController's Hud.Layout, px of its 1080-tall root:
	-- its pill 154 left of the middle, the glyph 55 into it, 44 down from the screen's top) until the HUD hands over
	-- the glyph itself (SetGemsTarget).
	PILL_X = -154 + 55,
	PILL_Y = 44,
})

local SpinsController = {}

local state: Types.TSpinsState = {
	Scale = source(1),
	Now = source(os.clock()),
	IsOpen = source(false),
	ToggledAt = source(-math.huge),
	FreeLeft = source(0),
	FreePerDay = source(SpinsCore.FREE_PER_DAY),
	Bought = source(0),
	SecondsLeft = source(0),
	CanBuy = source(false),
	Mode = source("None" :: Types.TMode),
	Rest = source(4),
	Spin = source(nil :: Types.TSpin?),
	PillAt = source(Vector2.zero),
	BarAt = source(Vector2.zero),
	BarLength = source(0),
	RefusedAt = source(-math.huge),
	BeckonAt = source(-math.huge),
}

-- What the HUD is held back by, and whether Gems are landing in its pill now (from the first piece to the last).
local heldGems = source(0)
local heldXp = source(0)
local isLandingGems = source(false)
-- The glyph on the HUD's Gems pill and the level plate's bar, handed over by the HUD as it is built.
local gemsTarget: GuiObject? = nil
local xpTarget: GuiObject? = nil
-- The layer the prize flies in, his 1920 x 1080 scaled into the middle of the screen (BuildPage).
local flightLayer: Frame? = nil

-- os.clock until which Now keeps ticking.
local motionUntil = -math.huge
-- os.clock the next UTC day starts at.
local dayEndsAt = math.huge
-- A purchase prompted and not finished: when its spin arrives, it is spun at once.
local isAwaitingPurchase = false
-- How many of the current prize's pieces have landed, and whether its landing has been heard.
local piecesLanded = 0
local hasLandSounded = false
local random = Random.new()

-- Whether the reel is turning or its prize still landing: the page holds the screen until it is done. Reads a vide
-- source.
function SpinsController.IsSpinning(): boolean
	return state.Mode() == "Busy"
end

-- The free spins left today. Reads a vide source.
function SpinsController.FreeLeft(): number
	return state.FreeLeft()
end

-- The free spins a day, the passes' included. Reads a vide source.
function SpinsController.FreePerDay(): number
	return state.FreePerDay()
end

-- Whether SPIN would spin now (a free or bought spin is left, the reel at rest). Reads a vide source.
function SpinsController.CanSpin(): boolean
	return state.Mode() == "Spin"
end

-- The Gems and the XP (percents of a level) the server has paid that have not flown into the HUD yet: the HUD shows
-- the profile's numbers less these. Read vide sources.
function SpinsController.HeldGems(): number
	return heldGems()
end

function SpinsController.HeldXp(): number
	return heldXp()
end

-- Whether a prize's Gems are landing in the pill now. Reads a vide source.
function SpinsController.IsLandingGems(): boolean
	return isLandingGems()
end

-- Where the Gems fly to: the glyph on the HUD's Gems pill.
function SpinsController.SetGemsTarget(glyph: GuiObject)
	gemsTarget = glyph
end

-- Where the XP flies to: the level plate's bar, its fill growing from the left.
function SpinsController.SetXpTarget(bar: GuiObject)
	xpTarget = bar
end

local function stir(seconds: number)
	motionUntil = math.max(motionUntil, os.clock() + seconds)
end

local function release(gems: number, xp: number)
	if heldGems() ~= gems then heldGems(gems) end
	if heldXp() ~= xp then heldXp(xp) end
end

-- Where the screen's 1920 x 1080 starts, in the space AbsolutePosition is in: the flights' own layer once it is built,
-- so a target's AbsolutePosition less this is right whatever Roblox's inset does to either gui (UI.md, "AbsolutePosition
-- is always measured from under the topbar"); worked out from the viewport before.
local function screenOrigin(): Vector2
	local layer = flightLayer
	if layer and layer.Parent then return layer.AbsolutePosition end
	return Workspace.CurrentCamera.ViewportSize / 2 - Tune.DESIGN * state.Scale() / 2
end

-- The pill's glyph in the screen's 1920 x 1080, where it stands now.
local function aimAtPill()
	local glyph = gemsTarget
	if not glyph or not glyph.Parent then return end
	state.PillAt((glyph.AbsolutePosition + glyph.AbsoluteSize / 2 - screenOrigin()) / state.Scale())
end

-- The level bar's left end and length in the screen's 1920 x 1080, read as a prize sets off. Its place and size follow
-- the screen's width (Hud's level plate), and the HUD is laid out again only after a resize is heard, so it is never
-- read then.
local function aimAtBar()
	local bar = xpTarget
	if not bar or not bar.Parent then return end
	local scale = state.Scale()
	local size = bar.AbsoluteSize
	state.BarAt((bar.AbsolutePosition + Vector2.new(0, size.Y / 2) - screenOrigin()) / scale)
	state.BarLength(size.X / scale)
end

local function updateMode()
	local mode: Types.TMode
	if state.Spin() then
		mode = "Busy"
	elseif state.FreeLeft() > 0 or state.Bought() > 0 then
		mode = "Spin"
	elseif state.CanBuy() and EProducts.ExtraSpin ~= 0 then
		mode = "Buy"
	else
		mode = "None"
	end
	if state.Mode() ~= mode then state.Mode(mode) end
end

-- Ends the spin where it would have ended: on its slot, with all of its prize let through.
local function finish()
	local spin = state.Spin()
	if not spin then return end
	vide.batch(function()
		if spin.Slot then state.Rest(spin.Slot) end
		state.Spin(nil)
		updateMode()
	end)
	release(0, 0)
	isLandingGems(false)
end

local function startSpin()
	local now = os.clock()
	vide.batch(function()
		state.Spin({ StartAt = now, From = state.Rest() })
		updateMode()
	end)
	piecesLanded = 0
	hasLandSounded = false
	stir(Tune.ANSWER_TIMEOUT)
	SoundsCore.PlayUINamed("UI.UpgradePick", "Reroll")
	ClientNetworkSpins.Spin.Fire()
end

local function refuse()
	state.RefusedAt(os.clock())
	stir(1)
	SoundsCore.PlayUINamed("UI.UpgradePick", "Denied")
end

-- SPIN wobbles once at `at` to be pressed, when a spin waits for it.
local function beckon(at: number)
	if state.Mode() ~= "Spin" then return end
	state.BeckonAt(at)
	motionUntil = math.max(motionUntil, at + Tune.MOTION_SECONDS)
end

-- Puts the page on show or takes it off. Shown, it comes in `delay` seconds from now (a stamp in the future: the
-- other page clears first). Taken off, a spin still turning ends where it would have.
function SpinsController.SetShown(isShown: boolean, delay: number?)
	if state.IsOpen() == isShown then return end
	local now = os.clock()
	if isShown then
		local at = now + (delay or 0)
		vide.batch(function()
			state.IsOpen(true)
			state.ToggledAt(at)
			beckon(at + Tune.BECKON_DELAY)
		end)
		motionUntil = math.max(motionUntil, at + Tune.MOTION_SECONDS)
		return
	end

	finish()
	vide.batch(function()
		state.IsOpen(false)
		-- Taken off before it came in: it stays out, rather than showing up to fade.
		state.ToggledAt(if now < state.ToggledAt() then -math.huge else now)
	end)
	stir(Tune.MOTION_SECONDS)
	isAwaitingPurchase = false
end

local actions: Types.TSpinsActions = {
	-- Checked here first only to answer at once: the server checks it again.
	Spin = function()
		local mode = state.Mode()
		if mode == "Spin" then
			startSpin()
		elseif mode == "Buy" then
			isAwaitingPurchase = true
			MarketplaceService:PromptProductPurchase(LocalPlayer, EProducts.ExtraSpin)
		elseif mode == "None" then
			refuse()
		end
	end,
}

-- The server's answer to the spin turning now: where it stops, and the prize held back from the HUD until it lands.
local function land(prize: number)
	local spin = state.Spin()
	if not spin or spin.BrakeAt then
		-- Shut before the answer came: the reel is put on the prize, which the HUD already shows.
		if prize > 0 then
			local slot = state.Rest() + 1
			while SpinsCore.PrizeAt(slot) ~= prize do
				slot += 1
			end
			state.Rest(slot)
		end
		return
	end

	local now = os.clock()
	local planned = ReelMotion.Plan(spin, prize, now, random:NextNumber(-1, 1))
	local landAt = planned.LandAt :: number
	local doneAt = landAt + Reel.LAND_SECONDS
	if prize > 0 then
		local data = SpinsCore.PRIZES[prize]
		planned.PayAt = landAt + Tune.PAY_DELAY
		planned.Pieces = Payout.Count(data)
		aimAtPill()
		aimAtBar()
		if data.Kind == "Gems" then
			heldGems(data.Amount)
		else
			heldXp(data.Amount)
			-- The profile has it already. Over a level the pieces fill the old level's bar to its end.
			local before = (ProfileController.Xp - data.Amount) / 100
			planned.BarFrom = if before < 0 then before + 1 else before
			planned.BarTo = if before < 0 then 1 else ProfileController.Xp / 100
		end
		doneAt = math.max(doneAt, planned.PayAt + Payout.SECONDS)
	end

	state.Spin(planned)
	motionUntil = math.max(motionUntil, doneAt + 0.2)
end

-- Each frame a spin is turning: its landing heard, its pieces paid as they land, and its end.
local function stepSpin(now: number)
	local spin = state.Spin()
	if not spin then return end

	if not spin.BrakeAt then
		if now - spin.StartAt > Tune.ANSWER_TIMEOUT then land(0) end
		return
	end

	local landAt = spin.LandAt :: number
	if not hasLandSounded and now >= landAt then
		hasLandSounded = true
		local prize = if spin.Prize and spin.Prize > 0 then SpinsCore.PRIZES[spin.Prize] else nil
		if not prize then
			SoundsCore.PlayUINamed("UI.UpgradePick", "Denied")
		elseif prize.IsJackpot then
			SoundsCore.PlayUINamed("UI.UpgradePick", "RevealMythic")
		elseif prize.Amount >= 100 or prize.Kind == "Xp" and prize.Amount >= 50 then
			SoundsCore.PlayUINamed("UI.UpgradePick", "RevealLegendary")
		else
			SoundsCore.PlayUINamed("UI.UpgradePick", "RevealEpic")
		end
	end

	local payAt = spin.PayAt
	local pieces = spin.Pieces
	if payAt and pieces and now >= payAt then
		local landed = piecesLanded
		while landed < pieces and now - payAt >= Payout.ArriveAt(landed + 1, pieces) do
			landed += 1
		end
		if landed > piecesLanded then
			piecesLanded = landed
			local prize = SpinsCore.PRIZES[spin.Prize :: number]
			local left = prize.Amount - math.floor(prize.Amount * landed / pieces)
			if prize.Kind == "Gems" then
				release(left, heldXp())
				isLandingGems(landed < pieces)
			else
				release(heldGems(), left)
			end
			SoundsCore.PlayUINamed("UI.UpgradePick", "Tick")
		end
	end

	local doneAt = landAt + Reel.LAND_SECONDS
	if payAt then doneAt = math.max(doneAt, payAt + Payout.SECONDS) end
	if now < doneAt then return end
	finish()
	beckon(now + Tune.AFTER_SPIN_BECKON_DELAY)
end

-- Whether the page is on show. Reads a vide source.
function SpinsController.IsShown(): boolean
	return state.IsOpen()
end

-- The page, for the shell to scale and cut (his 1920 x 1080, standing `lift` px under its own place), the layer its
-- prize flies in (scaled whole into the middle of the screen), and the jackpot's shake in px; built once inside the
-- daily screen's vide root.
function SpinsController.BuildPage(lift: () -> number): (Frame, Frame, () -> number)
	-- Drawn only while it is on show or still leaving: hidden, the page costs nothing.
	local isDrawn = vide.derive(function(): boolean
		return state.IsOpen() or state.Now() - state.ToggledAt() < Screen.LEAVE_SECONDS + 0.05
	end)
	local page, flights, shake = Screen.Build(state, actions, lift)
	flightLayer = create("Frame")({
		Name = "SpinsFlights",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(Tune.DESIGN.X, Tune.DESIGN.Y),
		BackgroundTransparency = 1,
		Visible = isDrawn,
		create("UIScale")({ Scale = state.Scale }),
		flights,
	})

	return create("Frame")({
		Name = "Spins",
		Size = UDim2.fromOffset(Tune.DESIGN.X, Tune.DESIGN.Y),
		BackgroundTransparency = 1,
		Visible = isDrawn,
		page,
	}),
		flightLayer :: Frame,
		shake
end

local function updateSecondsLeft(now: number)
	-- Nothing to count down until the server has said when the day ends.
	if dayEndsAt == math.huge then return end
	if now >= dayEndsAt then
		-- A new UTC day: the free spins are back (the server says so too, a second later).
		dayEndsAt += Tune.DAY_SECONDS
		state.FreeLeft(state.FreePerDay())
		updateMode()
	end
	local left = math.max(math.ceil(dayEndsAt - now), 0)
	if left ~= state.SecondsLeft() then state.SecondsLeft(left) end
end

-- The screen's fit, and where the HUD's pill is in its 1920 x 1080: the HUD is scaled by the height under Roblox's top
-- bar (Theme's clamp), the screen by whichever side fits, from its middle.
local function updateScale()
	local viewport = Workspace.CurrentCamera.ViewportSize
	local inset = GuiService:GetGuiInset().Y
	local scale = math.max(math.min(viewport.Y / Tune.DESIGN.Y, viewport.X / Tune.DESIGN.X), 0.01)
	local hud = math.clamp((viewport.Y - inset) / Theme.DESIGN_HEIGHT, Theme.MIN_SCALE, Theme.MAX_SCALE)
	local origin = viewport / 2 - Tune.DESIGN * scale / 2
	local pill = Vector2.new(viewport.X / 2 + Tune.PILL_X * hud, Tune.PILL_Y * hud)
	vide.batch(function()
		state.Scale(scale)
		state.PillAt((pill - origin) / scale)
		aimAtPill()
	end)
end

SpinsController.OnStart = function()
	task.spawn(function()
		local ok, policy = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, LocalPlayer)
		if not ok or policy.ArePaidRandomItemsRestricted then return end
		state.CanBuy(true)
		updateMode()
	end)

	-- Now is written only while something moves, so a screen at rest, open or shut, redraws nothing.
	RunService.PreRender:Connect(function()
		local now = os.clock()
		vide.batch(function()
			if now < motionUntil then state.Now(now) end
			stepSpin(now)
			updateSecondsLeft(now)
		end)
	end)

	local camera = Workspace.CurrentCamera
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(updateScale)
	updateScale()
end

ServerNetworkSpins.State.On(function(free: number, bought: number, secondsLeft: number, perDay: number)
	dayEndsAt = os.clock() + secondsLeft
	vide.batch(function()
		state.FreeLeft(free)
		state.FreePerDay(perDay)
		state.Bought(bought)
		updateMode()
	end)

	-- A spin just bought is spun as it arrives.
	if isAwaitingPurchase and bought > 0 and state.IsOpen() and not state.Spin() then
		isAwaitingPurchase = false
		startSpin()
	end
end)

ServerNetworkSpins.Landed.On(function(prize: number)
	vide.batch(function()
		land(prize)
	end)
end)

MarketplaceService.PromptProductPurchaseFinished:Connect(
	function(userId: number, productId: number, isPurchased: boolean)
		if userId ~= LocalPlayer.UserId or productId ~= EProducts.ExtraSpin then return end
		if not isPurchased then isAwaitingPurchase = false end
	end
)

return Ignis.Register(SpinsController)
