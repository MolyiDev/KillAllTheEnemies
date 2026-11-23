-- The daily rewards screen (UIMatt.md, Daily Rewards): the 28-day streak by week, and claiming today's reward
-- (DailyRewardsService decides; this asks and shows). The lobby's DAILY REWARDS card opens it. While it is up the world
-- behind is blurred and heard under water.
--
-- A claim is shown in the order it is paid: the card winds up while the server is asked, lets go on the answer, and
-- its Gems fly into the HUD's Gems pill (GemPayout), which holds what is still in the air (HeldGems) and takes each slice
-- as it lands.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local vide = require(ReplicatedStorage.Packages.vide)
local NetworkMeta = require(StarterPlayer.StarterPlayerScripts.GlobalClient.NetworkMeta)
-- Through PlayerScripts, the copy that runs: requiring the StarterPlayer one would load a second controller.
local BlurController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.BlurController)
local DailyRewardsCore = require(ReplicatedStorage.Shared.Core.DailyRewardsCore)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local GemPayout = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.GemPayout)
local Screen = require(script.Screen)
local Types = require(script.Types)

local ServerNetworkDailyRewards = NetworkMeta.Server.DailyRewards
local ClientNetworkDailyRewards = NetworkMeta.Client.DailyRewards
local LocalPlayer = Players.LocalPlayer
local source = vide.source
local create = vide.create

local Tune = table.freeze({
	-- The screen is his 1920 x 1080, fitted inside the viewport whole.
	DESIGN = Vector2.new(1920, 1080),
	-- Above the lobby's HUD, under the settings screen.
	DISPLAY_ORDER = 5,
	-- It is drawn this long after it is shut, for its way out.
	LEAVE_SECONDS = 0.4,
	-- How long the clock keeps ticking after a stamp: the longest gesture is shorter.
	MOTION_SECONDS = 2.4,
	-- While today's reward waits on the screen, the light crosses its card this often.
	CALL_EVERY = 2.6,
})

-- A rarity's reveal, for a gun let go.
local REVEALS = table.freeze({
	Epic = "RevealEpic",
	Legendary = "RevealLegendary",
	BlackMarket = "RevealMythic",
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

-- The Gems the profile holds that are still in the air, and whether they are landing in the pill right now.
local heldGems = source(0)
local isLanding = source(false)

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
local nextCall = math.huge
local payout: GemPayout.TPayout? = nil
local glyphs: { ImageLabel } = {}
local gemsTarget: GuiObject? = nil

-- Whether the screen is up. Reads a vide source, so a view that calls it follows it.
function DailyRewardsController.IsOpen(): boolean
	return state.IsOpen()
end

-- Whether today's reward waits to be claimed. Reads a vide source.
function DailyRewardsController.IsClaimable(): boolean
	return state.IsClaimable()
end

-- The Gems a claim paid that are still flying to the HUD's pill: the pill shows that many fewer. Reads a vide source.
function DailyRewardsController.HeldGems(): number
	return heldGems()
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

function DailyRewardsController.Open()
	if state.IsOpen() then return end
	local week = nextWeek()
	local now = os.clock()
	vide.batch(function()
		state.IsOpen(true)
		stamp(state.ToggledAt, now)
		-- Today's card pings once it has been dealt in, and is called once the screen has settled.
		stamp(state.ReadyAt, now)
		nextCall = now + Tune.CALL_EVERY
		state.Week(week)
		state.WeekFrom(week)
		state.WeekAt(-math.huge)
	end)
	SoundsCore.SetMuffled("DailyRewards", true)
	BlurController.SetBlurred("DailyRewards", true)
	SoundsCore.PlayUINamed("UI", "MenuIn")
end

function DailyRewardsController.Close()
	if not state.IsOpen() then return end
	state.IsOpen(false)
	stamp(state.ToggledAt, os.clock())
	SoundsCore.SetMuffled("DailyRewards", false)
	BlurController.SetBlurred("DailyRewards", false)
	SoundsCore.PlayUINamed("UI", "MenuOut")
end

local function refuse(which: number)
	vide.batch(function()
		state.Refused(which)
		stamp(state.RefusedAt, os.clock())
	end)
	SoundsCore.PlayUINamed("UI.UpgradePick", "Denied")
end

local actions: Types.TDailyActions = {
	Close = DailyRewardsController.Close,
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

local function updateScale()
	local viewport = Workspace.CurrentCamera.ViewportSize
	state.Scale(math.max(math.min(viewport.Y / Tune.DESIGN.Y, viewport.X / Tune.DESIGN.X), 0.01))
end

DailyRewardsController.OnStart = function()
	local isPayingOut = source(false)
	vide.mount(function()
		-- Drawn only while it is up, still leaving, or its Gems are still in the air: shut, it costs nothing.
		local isDrawn = vide.derive(function(): boolean
			return state.IsOpen() or state.Now() - state.ToggledAt() < Tune.LEAVE_SECONDS or isPayingOut()
		end)
		local built = GemPayout.Build(state.Scale, function(): Vector2?
			local glyph = gemsTarget
			if not glyph or not glyph.Parent then return nil end
			return glyph.AbsolutePosition + glyph.AbsoluteSize / 2
		end)
		payout = built
		local children, cardGlyphs = Screen.Build(state, actions)
		glyphs = cardGlyphs

		return create("ScreenGui")({
			Name = "DailyRewards",
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			DisplayOrder = Tune.DISPLAY_ORDER,
			Enabled = isDrawn,
			children,
			built.Layer,
		})
	end, LocalPlayer:WaitForChild("PlayerGui"))

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
		-- A week's last day: once the card has settled, the screen turns to the week coming, so it reads as going on.
		if day % DailyRewardsCore.WEEK == 0 and day < DailyRewardsCore.DAYS then
			turnAt = releaseAt + Screen.TURN_SECONDS
			turnWeek = DailyRewardsCore.WeekOf(day + 1)
		end
	end)
end)

return Ignis.Register(DailyRewardsController)
