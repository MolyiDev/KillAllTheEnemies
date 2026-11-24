-- The daily screen's DAILY page (UIMatt.md, Daily Rewards): the 28-day streak by week, and claiming today's reward
-- (DailyRewardsService decides; this asks and shows). DailyController owns the screen round it and shows the page
-- (SetShown) and builds it into its gui (BuildPage).
--
-- A claim is shown in the order it is paid: the card winds up while the server is asked, lets go on the answer, and
-- its Gems fly into the HUD's Gems pill (GemPayout), which holds what is still in the air (HeldGems) and takes each slice
-- as it lands.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local vide = require(ReplicatedStorage.Packages.vide)
local NetworkMeta = require(StarterPlayer.StarterPlayerScripts.GlobalClient.NetworkMeta)
local DailyRewardsCore = require(ReplicatedStorage.Shared.Core.DailyRewardsCore)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local GemPayout = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.GemPayout)
local Screen = require(script.Screen)
local Types = require(script.Types)

local ServerNetworkDailyRewards = NetworkMeta.Server.DailyRewards
local ClientNetworkDailyRewards = NetworkMeta.Client.DailyRewards
local source = vide.source
local create = vide.create

local Tune = table.freeze({
	-- The screen is his 1920 x 1080, fitted inside the viewport whole.
	DESIGN = Vector2.new(1920, 1080),
	-- It is drawn this long after it is hidden, for its way out.
	LEAVE_SECONDS = 0.4,
	-- How long the clock keeps ticking after a stamp: the longest gesture is shorter.
	MOTION_SECONDS = 2.4,
	-- While today's reward waits on the screen, the light crosses its card this often.
	CALL_EVERY = 2.6,
	-- A claim has been shown this long after its card has settled, its Gems landed: the beat to take it in.
	SHOWN_AFTER = 0.35,
})

-- A rarity's reveal, for a gun let go.
local REVEALS = table.freeze({
	Epic = "RevealEpic",
	Legendary = "RevealLegendary",
	Mythic = "RevealMythic",
})

local DailyRewardsController = {}

local state: Types.TDailyState = {
	Scale = source(1),
	Now = source(os.clock()),
	CallAt = source(-math.huge),
	IsOpen = source(false),
	ToggledAt = source(-math.huge),
	Day = source(1),
	IsClaimable = source(false),
	OwnedPrizes = source({} :: { [number]: boolean }),
	NextDayAt = source(math.huge),
	SecondsLeft = source(0),
	Week = source(1),
	WeekFrom = source(1),
	WeekAt = source(-math.huge),
	IsPending = source(false),
	PressedAt = source(-math.huge),
	ClaimedDay = source(0),
	ClaimedAt = source(-math.huge),
	ClaimedGems = source(0),
	ClaimedGun = source(0),
	ReadyAt = source(-math.huge),
	Refused = source(0),
	RefusedAt = source(-math.huge),
}

-- The Gems the profile holds that are still in the air, whether they are landing in the pill right now, and whether
-- any are still flying (the page stays drawn for them).
local heldGems = source(0)
local isLanding = source(false)
local isPayingOut = source(false)
-- How many claims have finished showing: the daily screen moves on after each.
local claimsShown = source(0)

-- os.clock until which Now keeps ticking.
local motionUntil = -math.huge
-- The newest State, applied at once unless a claim is waiting on its answer (that State is the claim's own, and is
-- applied with it).
local latest: { Day: number, IsClaimable: boolean, SecondsLeft: number, Owned: { number } }? = nil
-- A claim's let-go, still to come: its moment, and the impact its stamp makes.
local releaseAt = math.huge
local impactAt = math.huge
-- A week's last day claimed: the moment the screen turns to the next week, and that week.
local turnAt = math.huge
local turnWeek = 1
-- When the claim showing now is over, its Gems still to land.
local shownAt = math.huge
local nextCall = math.huge
local payout: GemPayout.TPayout? = nil
local glyphs: { ImageLabel } = {}
local gemsTarget: GuiObject? = nil

-- Whether today's reward waits to be claimed. Reads a vide source.
function DailyRewardsController.IsClaimable(): boolean
	return state.IsClaimable()
end

-- The day of the streak he is on. Reads a vide source.
function DailyRewardsController.Day(): number
	return state.Day()
end

-- Whether a claim's Gems are still flying to the pill: the page is drawn until they have landed. Reads a vide source.
function DailyRewardsController.IsPayingOut(): boolean
	return isPayingOut()
end

-- The Gems a claim paid that are still flying to the HUD's pill: the pill shows that many fewer. Reads a vide source.
function DailyRewardsController.HeldGems(): number
	return heldGems()
end

-- How many claims have finished showing (the card settled, the week turned, the Gems landed). Reads a vide source, so
-- an effect on it runs once each claim is over.
function DailyRewardsController.ClaimsShown(): number
	return claimsShown()
end

-- Whether a claim's Gems are landing in the pill now. Reads a vide source.
function DailyRewardsController.IsLandingGems(): boolean
	return isLanding()
end

-- Where the Gems fly to: the glyph on the HUD's Gems pill.
function DailyRewardsController.SetGemsTarget(glyph: GuiObject)
	gemsTarget = glyph
end

local function stamp(at: Types.Source<number>, moment: number)
	at(moment)
	motionUntil = math.max(motionUntil, moment + Tune.MOTION_SECONDS)
end

-- The week of the next reward: today's, or tomorrow's once today's is claimed, so a finished week shows the one coming
-- (after day 28 the cycle starts over tomorrow, and its week 1 would read as all claimed today).
local function nextWeek(): number
	local day = state.Day()
	if state.IsClaimable() or day == DailyRewardsCore.DAYS then return DailyRewardsCore.WeekOf(day) end
	return DailyRewardsCore.WeekOf(day + 1)
end

local function showWeek(week: number)
	vide.batch(function()
		state.WeekFrom(state.Week())
		state.Week(week)
		stamp(state.WeekAt, os.clock())
	end)
end

-- Puts the page on show or takes it off. Shown, it comes in `delay` seconds from now (a stamp in the future: the
-- other page clears first), on the week of the next reward.
function DailyRewardsController.SetShown(isShown: boolean, delay: number?)
	if state.IsOpen() == isShown then return end
	if not isShown then
		local now = os.clock()
		state.IsOpen(false)
		-- Taken off before it came in: it stays out, rather than showing up to fade.
		stamp(state.ToggledAt, if now < state.ToggledAt() then -math.huge else now)
		return
	end

	local week = nextWeek()
	local at = os.clock() + (delay or 0)
	vide.batch(function()
		state.IsOpen(true)
		stamp(state.ToggledAt, at)
		-- Today's card pings once it has been dealt in, and is called once the page has settled.
		stamp(state.ReadyAt, at)
		nextCall = at + Tune.CALL_EVERY
		state.Week(week)
		state.WeekFrom(week)
		state.WeekAt(-math.huge)
	end)
end

local function refuse(which: number)
	vide.batch(function()
		state.Refused(which)
		stamp(state.RefusedAt, os.clock())
	end)
	SoundsCore.PlayUINamed("UI.UpgradePick", "Denied")
end

local actions: Types.TDailyActions = {
	-- Checked here only to answer at once: the server checks it again.
	Claim = function()
		if state.IsPending() or not state.IsClaimable() then return end
		vide.batch(function()
			state.IsPending(true)
			stamp(state.PressedAt, os.clock())
		end)
		ClientNetworkDailyRewards.Claim.Fire()
	end,
	PickWeek = function(week: number)
		if week == state.Week() then return end
		if week > Screen.LastOpenWeek(state.Day()) then
			refuse(-week)
			return
		end
		showWeek(week)
	end,
	Refuse = refuse,
}

local function apply()
	local current = latest
	if not current then return end
	local owned = {}
	for _, day in current.Owned do
		owned[day] = true
	end

	-- A new day come up while the screen is up (midnight): its card pings, on its own week.
	local isNewlyReady = current.IsClaimable and (not state.IsClaimable() or state.Day() ~= current.Day)
	state.Day(current.Day)
	state.IsClaimable(current.IsClaimable)
	if isNewlyReady and state.IsOpen() then
		stamp(state.ReadyAt, os.clock())
		local week = DailyRewardsCore.WeekOf(current.Day)
		if state.Week() ~= week then showWeek(week) end
	end
	state.OwnedPrizes(owned)
	state.NextDayAt(os.clock() + current.SecondsLeft)
end

-- The answer let go: the burst, its sound, and the Gems into the air.
local function release(now: number)
	releaseAt = math.huge
	impactAt = now + Screen.IMPACT_SECONDS
	local gun = DataCore.Guns.ById[state.ClaimedGun()]
	if gun then
		SoundsCore.PlayUINamed("UI.UpgradePick", REVEALS[gun.Rarity] or "RevealEpic")
	else
		SoundsCore.PlayUINamed("UI.UpgradePick", "PickRare")
	end

	local gems = state.ClaimedGems()
	local slot = (state.ClaimedDay() - 1) % DailyRewardsCore.WEEK + 1
	local glyph = glyphs[slot]
	if gems <= 0 or not payout or not glyph or not state.IsOpen() then
		heldGems(0)
		return
	end

	local from = glyph.AbsolutePosition + glyph.AbsoluteSize / 2
	payout.Burst(from, gems, now, function(owed: number)
		heldGems(owed)
		isLanding(owed > 0)
		SoundsCore.PlayUINamed("UI.UpgradePick", "Tick")
	end)
end

-- Whether the page is on show. Reads a vide source.
function DailyRewardsController.IsShown(): boolean
	return state.IsOpen()
end

-- The page, for the shell to scale and cut (his 1920 x 1080, standing `lift` px under its own place), and the layer
-- its Gems fly in; built once inside the daily screen's vide root.
function DailyRewardsController.BuildPage(lift: () -> number): (Frame, Instance)
	-- Drawn only while it is on show, still leaving, or its Gems are still in the air: hidden, it costs nothing.
	local isDrawn = vide.derive(function(): boolean
		return state.IsOpen() or state.Now() - state.ToggledAt() < Tune.LEAVE_SECONDS or isPayingOut()
	end)
	local built = GemPayout.Build(state.Scale, function(): Vector2?
		local glyph = gemsTarget
		if not glyph or not glyph.Parent then return nil end
		return glyph.AbsolutePosition + glyph.AbsoluteSize / 2
	end)
	payout = built
	local children, cardGlyphs = Screen.Build(state, actions, lift)
	glyphs = cardGlyphs

	return create("Frame")({
		Name = "DailyRewards",
		Size = UDim2.fromOffset(Tune.DESIGN.X, Tune.DESIGN.Y),
		BackgroundTransparency = 1,
		Visible = isDrawn,
		children,
	}),
		built.Layer
end

local function updateScale()
	local viewport = Workspace.CurrentCamera.ViewportSize
	state.Scale(math.max(math.min(viewport.Y / Tune.DESIGN.Y, viewport.X / Tune.DESIGN.X), 0.01))
end

DailyRewardsController.OnStart = function()
	-- Now is written only while something moves, so a screen at rest, open or shut, redraws nothing.
	RunService.PreRender:Connect(function()
		local now = os.clock()
		if now >= releaseAt then release(now) end
		if now >= impactAt then
			impactAt = math.huge
			SoundsCore.PlayUINamed("UI.UpgradePick", "Deal")
		end
		if now >= turnAt then
			turnAt = math.huge
			if state.IsOpen() and state.Week() == turnWeek - 1 then showWeek(turnWeek) end
		end
		if now < motionUntil then state.Now(now) end

		local isUp = state.IsOpen() or now - state.ToggledAt() < Tune.LEAVE_SECONDS
		if isUp then
			local left = math.max(0, math.ceil(state.NextDayAt() - now))
			if left ~= state.SecondsLeft() then state.SecondsLeft(left) end
			-- The call keeps the clock ticking only while its light crosses, so a screen waiting redraws nothing between.
			if now >= nextCall and state.IsClaimable() and not state.IsPending() then
				nextCall = now + Tune.CALL_EVERY
				state.CallAt(now)
				motionUntil = math.max(motionUntil, now + Screen.CALL_SECONDS)
			end
		end

		local current = payout
		local isBusy = current ~= nil and current.Step(now)
		if isBusy ~= isPayingOut() then isPayingOut(isBusy) end
		if now >= shownAt and not isBusy then
			shownAt = math.huge
			claimsShown(claimsShown() + 1)
		end
	end)

	local camera = Workspace.CurrentCamera
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	updateScale()
end

ServerNetworkDailyRewards.State.On(function(day: number, isClaimable: boolean, secondsLeft: number, owned: { number })
	latest = { Day = day, IsClaimable = isClaimable, SecondsLeft = secondsLeft, Owned = owned }
	if state.IsPending() then return end
	vide.batch(apply)
end)

-- Always after the State it changed (DailyRewardsService), so `latest` is the claim's own.
ServerNetworkDailyRewards.Claimed.On(function(day: number, gems: number, gunId: number)
	local now = os.clock()
	vide.batch(function()
		state.IsPending(false)
		apply()
		if day == 0 then
			refuse(state.Day())
			return
		end

		-- The Gems are the profile's already: the pill holds them back until they land.
		heldGems(gems)
		state.ClaimedDay(day)
		state.ClaimedGems(gems)
		state.ClaimedGun(gunId)
		releaseAt = math.max(now, state.PressedAt() + Screen.WIND_UP_SECONDS)
		stamp(state.ClaimedAt, releaseAt)
		motionUntil = math.max(motionUntil, releaseAt + Screen.CLAIM_SECONDS + Tune.MOTION_SECONDS)
		shownAt = releaseAt + Screen.CLAIM_SECONDS + Tune.SHOWN_AFTER
		-- A week's last day: once the card has settled, the screen turns to the week coming, so it reads as going on.
		if day % DailyRewardsCore.WEEK == 0 and day < DailyRewardsCore.DAYS then
			turnAt = releaseAt + Screen.TURN_SECONDS
			turnWeek = DailyRewardsCore.WeekOf(day + 1)
			shownAt = math.max(shownAt, turnAt + Screen.WINK_AFTER_TURN_SECONDS + Tune.SHOWN_AFTER)
		end
	end)
end)

return Ignis.Register(DailyRewardsController)
