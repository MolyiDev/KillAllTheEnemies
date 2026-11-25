-- The daily screen's SPIN page (UIMatt.md, Daily Spins): the reels, the free spins left today and SPIN, which turns as
-- many reels as its count menu says (held to the spins left while any are) and sells that many for Robux once they are
-- used (SpinsService decides each spin and what it lands on; this asks and shows). DailyController owns the screen
-- round it and shows the page (SetShown) and builds it into its gui (BuildShape, BuildPage).
--
-- A prize is shown in the order it is paid: the server tells the prizes in the same frame as the profile it paid, so
-- the HUD's Gems and XP are held back by what is still to land (HeldGems, HeldXp) before they are drawn, and let
-- through a slice per piece as each reel's prize flies into them (Payout). Selling spins is selling a random item for
-- Robux, so it is offered only where PolicyService allows paid random items.
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
local Payout = require(script.Payout)
local Reel = require(script.Reel)
local ReelMotion = require(script.ReelMotion)
local Screen = require(script.Screen)
local Shape = require(script.Shape)
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
	-- A batch's reels are thrown this far apart, top first, and land at least this far apart, the last one a beat later
	-- still, so the eye follows them down.
	THROW_STAGGER = 0.07,
	LAND_STAGGER = 0.32,
	LAST_PAUSE = 0.22,
	-- Where each reel rests before its first spin: apart, so the reels do not read as copies.
	RESTS = { 4, 2, 6, 3, 5 },
	-- Pieces landing tick no closer than this.
	TICK_GAP = 0.03,
	-- Spins bought turn once Roblox's dialog is closed, or this long after they arrived if it never says so (the
	-- shop's receipt waits as long).
	MAX_DIALOG_WAIT = 10,
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
	Count = source(1),
	IsMenuOpen = source(false),
	MenuAt = source(-math.huge),
	Reels = source(1),
	ReelsAt = source(-math.huge),
	Batch = source(1),
	Price = source(0),
	Rests = source(table.clone(Tune.RESTS)),
	Spins = source({} :: { Types.TSpin }),
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
-- The spins bought and not arrived yet: when they arrive, that many are spun at once (0: none awaited).
local awaitedSpins = 0
-- Whether Roblox's purchase dialog is still up (its confirmation not yet pressed), and when the spins it sold arrived.
local isPrompting = false
local grantedAt = math.huge
-- How many of each reel's prize pieces have landed, and whether its landing has been heard.
local piecesLanded: { number } = {}
local hasLandSounded: { boolean } = {}
-- The last tick of a piece landing.
local lastPayTickAt = -math.huge
local random = Random.new()

-- Whether the reels are turning or their prizes still landing: the page holds the screen until they are done. Reads a
-- vide source.
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

-- Whether SPIN would spin now (a free or bought spin is left, the reels at rest). Reads a vide source.
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

-- The most spins `count` can be sold as: the count itself, or the biggest pack under it on sale here (0: none).
local function packFor(count: number): number
	for index = #SpinsCore.COUNTS, 1, -1 do
		local pack = SpinsCore.COUNTS[index]
		if pack <= count and (SpinsCore.PRODUCTS[pack] or 0) ~= 0 then return pack end
	end
	return 0
end

-- What SPIN does now and for how many, how many reels stand on the page, and the price when it sells.
local function updateMode()
	local spinning = #state.Spins()
	local left = state.FreeLeft() + state.Bought()
	local pack = if state.CanBuy() then packFor(state.Count()) else 0
	local mode: Types.TMode
	local batch
	if spinning > 0 then
		mode = "Busy"
		batch = spinning
	elseif left > 0 then
		mode = "Spin"
		batch = math.min(state.Count(), left)
	elseif pack > 0 then
		mode = "Buy"
		batch = pack
	else
		mode = "None"
		batch = state.Count()
	end

	if state.Mode() ~= mode then state.Mode(mode) end
	if state.Batch() ~= batch then state.Batch(batch) end
	local price = if mode == "Buy" then SpinsCore.PRICES[batch] else 0
	if state.Price() ~= price then state.Price(price) end
	-- The stamp first: the shape reads it as the count changes. The clock runs on for the new reels' deal.
	if state.Reels() ~= batch then
		state.ReelsAt(os.clock())
		state.Reels(batch)
		stir(Shape.SECONDS + Reel.DEAL_SECONDS)
	end
end

-- Ends the spins where they would have ended: each reel on its slot, with all of its prize let through.
local function finish()
	local spins = state.Spins()
	if #spins == 0 then return end
	vide.batch(function()
		local rests = table.clone(state.Rests())
		for index, spin in spins do
			if spin.Slot then rests[index] = spin.Slot end
		end
		state.Rests(rests)
		state.Spins({})
		updateMode()
	end)
	release(0, 0)
	isLandingGems(false)
end

-- Throws `count` reels, top first.
local function startSpin(count: number)
	local now = os.clock()
	local rests = state.Rests()
	local spins = table.create(count)
	for index = 1, count do
		spins[index] = { StartAt = now + (index - 1) * Tune.THROW_STAGGER, From = rests[index] }
		piecesLanded[index] = 0
		hasLandSounded[index] = false
	end
	vide.batch(function()
		state.Spins(spins)
		updateMode()
	end)
	stir(Tune.ANSWER_TIMEOUT)
	SoundsCore.PlayUINamed("UI.UpgradePick", "Reroll")
	ClientNetworkSpins.Spin.Fire(count)
end

-- Spins just bought turn once they have arrived and Roblox's dialog is down, as the shop's receipt waits for it: they
-- never start under the dialog's confirmation.
local function spinBought(now: number)
	if awaitedSpins == 0 or grantedAt == math.huge then return end
	if isPrompting and now - grantedAt < Tune.MAX_DIALOG_WAIT then return end
	if not state.IsOpen() or state.Mode() ~= "Spin" then return end
	awaitedSpins = 0
	isPrompting = false
	startSpin(state.Batch())
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
		state.IsMenuOpen(false)
	end)
	stir(Tune.MOTION_SECONDS)
	awaitedSpins = 0
end

local function setMenu(isOpen: boolean)
	if state.IsMenuOpen() == isOpen then return end
	vide.batch(function()
		state.IsMenuOpen(isOpen)
		state.MenuAt(os.clock())
	end)
	stir(0.6)
end

local actions: Types.TSpinsActions = {
	-- Checked here first only to answer at once: the server checks it again.
	Spin = function()
		setMenu(false)
		local mode = state.Mode()
		if mode == "Spin" then
			startSpin(state.Batch())
		elseif mode == "Buy" then
			awaitedSpins = state.Batch()
			isPrompting = true
			grantedAt = math.huge
			MarketplaceService:PromptProductPurchase(LocalPlayer, SpinsCore.PRODUCTS[awaitedSpins])
		elseif mode == "None" then
			refuse()
		end
	end,
	SetMenu = function(isOpen: boolean)
		setMenu(isOpen)
		SoundsCore.PlayClick()
	end,
	PickCount = function(count: number)
		setMenu(false)
		vide.batch(function()
			state.Count(count)
			if #state.Spins() == 0 then updateMode() end
		end)
		stir(0.6)
		SoundsCore.PlayUINamed("UI.UpgradePick", "Deal")
	end,
}

-- The server's answer to the reels turning now: where each stops, one after another down the page, and the prizes held
-- back from the HUD until each lands.
local function land(prizes: { number })
	local spins = state.Spins()
	if #spins == 0 or spins[1].BrakeAt then
		-- Shut before the answer came: each reel is put on its prize, which the HUD already shows.
		local rests = table.clone(state.Rests())
		for index, prize in prizes do
			if prize <= 0 or not rests[index] then continue end
			local slot = rests[index] + 1
			while SpinsCore.PrizeAt(slot) ~= prize do
				slot += 1
			end
			rests[index] = slot
		end
		state.Rests(rests)
		return
	end

	-- The profile has every prize already: the XP before them all is where the first XP prize's fill starts.
	local gems, xp = 0, 0
	for _, prize in prizes do
		local data = SpinsCore.PRIZES[prize]
		if not data then continue end
		if data.Kind == "Gems" then
			gems += data.Amount
		else
			xp += data.Amount
		end
	end
	local xpAt = ProfileController.Xp - xp
	aimAtPill()
	aimAtBar()

	local now = os.clock()
	local planned = table.create(#spins)
	local lastLanding = -math.huge
	local doneAt = now
	for index, spin in spins do
		local prize = prizes[index] or 0
		local gap = if index > 1 and index == #spins then Tune.LAND_STAGGER + Tune.LAST_PAUSE else Tune.LAND_STAGGER
		local plan = ReelMotion.PlanAfter(spin, prize, now, random:NextNumber(-1, 1), lastLanding + gap)
		local landAt = plan.LandAt :: number
		lastLanding = landAt
		doneAt = math.max(doneAt, landAt + Reel.LAND_SECONDS)
		local data = SpinsCore.PRIZES[prize]
		if prize > 0 and data then
			plan.PayAt = landAt + Tune.PAY_DELAY
			plan.Pieces = Payout.Count(data)
			if data.Kind == "Xp" then
				-- Over a level the pieces fill the old level's bar to its end.
				local start = xpAt % 100
				plan.BarFrom = start / 100
				plan.BarTo = math.min(start + data.Amount, 100) / 100
				xpAt += data.Amount
			end
			doneAt = math.max(doneAt, (plan.PayAt :: number) + Payout.SECONDS)
		end
		planned[index] = plan
	end

	release(gems, xp)
	state.Spins(planned)
	motionUntil = math.max(motionUntil, doneAt + 0.2)
end

-- What each reel still holds back of its prize at `now`, and whether Gems are landing in the pill; a tick for each
-- piece landed (no closer than TICK_GAP, with five streams at once).
local function pay(spins: { Types.TSpin }, now: number)
	local gems, xp = 0, 0
	local isLanding = false
	local hasTicked = false
	for index, spin in spins do
		local prize = if spin.Prize and spin.Prize > 0 then SpinsCore.PRIZES[spin.Prize] else nil
		local payAt = spin.PayAt
		local pieces = spin.Pieces
		if not prize or not payAt or not pieces then continue end
		local landed = piecesLanded[index] or 0
		while now >= payAt and landed < pieces and now - payAt >= Payout.ArriveAt(landed + 1, pieces) do
			landed += 1
		end
		if landed > (piecesLanded[index] or 0) then
			piecesLanded[index] = landed
			hasTicked = true
		end
		local left = prize.Amount - math.floor(prize.Amount * landed / pieces)
		if prize.Kind == "Gems" then
			gems += left
			isLanding = isLanding or (landed > 0 and landed < pieces)
		else
			xp += left
		end
	end

	release(gems, xp)
	if isLandingGems() ~= isLanding then isLandingGems(isLanding) end
	if hasTicked and now - lastPayTickAt >= Tune.TICK_GAP then
		lastPayTickAt = now
		SoundsCore.PlayUINamed("UI.UpgradePick", "Tick")
	end
end

-- A reel's landing heard, in the voice of what it landed on.
local function soundLanding(spin: Types.TSpin)
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

-- Each frame the reels are turning: each landing heard, the pieces paid as they land, and the end once every reel has
-- landed and paid.
local function stepSpin(now: number)
	local spins = state.Spins()
	if #spins == 0 then return end

	if not spins[1].BrakeAt then
		if now - spins[1].StartAt > Tune.ANSWER_TIMEOUT then land({}) end
		return
	end

	local doneAt = now
	for index, spin in spins do
		local landAt = spin.LandAt :: number
		if not hasLandSounded[index] and now >= landAt then
			hasLandSounded[index] = true
			soundLanding(spin)
		end
		doneAt = math.max(doneAt, landAt + Reel.LAND_SECONDS)
		if spin.PayAt then doneAt = math.max(doneAt, spin.PayAt + Payout.SECONDS) end
	end
	pay(spins, now)

	if now < doneAt then return end
	finish()
	beckon(now + Tune.AFTER_SPIN_BECKON_DELAY)
end

-- Whether the page is on show. Reads a vide source.
function SpinsController.IsShown(): boolean
	return state.IsOpen()
end

-- The page's shape for the reels it draws (Shape): the shell's panel takes it too. Built once inside the daily screen's
-- vide root, before the page.
function SpinsController.BuildShape(): () -> Shape.TShape
	return Shape.Build(state)
end

-- The page, for the shell to scale and cut (his 1920 x 1080, standing `lift` px under its own place, laid out by
-- `shape`), the layer its prizes fly in (scaled whole into the middle of the screen), and the jackpot's shake in px;
-- built once inside the daily screen's vide root.
function SpinsController.BuildPage(lift: () -> number, shape: () -> Shape.TShape): (Frame, Frame, () -> number)
	-- Drawn only while it is on show or still leaving: hidden, the page costs nothing.
	local isDrawn = vide.derive(function(): boolean
		return state.IsOpen() or state.Now() - state.ToggledAt() < Screen.LEAVE_SECONDS + 0.05
	end)
	local page, flights, shake = Screen.Build(state, actions, lift, shape)
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
			if awaitedSpins > 0 then spinBought(now) end
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

	if awaitedSpins > 0 and grantedAt == math.huge and free + bought >= awaitedSpins then
		grantedAt = os.clock()
		spinBought(grantedAt)
	end
end)

ServerNetworkSpins.Landed.On(function(prizes: { number })
	vide.batch(function()
		land(prizes)
	end)
end)

-- Roblox's dialog is down (its confirmation pressed, or the purchase let go): the spins bought may turn now.
MarketplaceService.PromptProductPurchaseFinished:Connect(
	function(userId: number, productId: number, isPurchased: boolean)
		if userId ~= LocalPlayer.UserId or productId ~= SpinsCore.PRODUCTS[awaitedSpins] then return end
		isPrompting = false
		if not isPurchased then
			awaitedSpins = 0
			return
		end
		spinBought(os.clock())
	end
)

return Ignis.Register(SpinsController)
