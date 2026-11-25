-- The daily screen (UIMatt.md, Daily Spins: his DAILY | SPIN tabbed modal): the daily rewards (DailyRewardsController)
-- and the daily spins (SpinsController) as two pages of one screen, opened from the top bar's Daily button. This owns
-- the screen round them (Shell), which page is on show, and the gui both pages are built into; each page owns its
-- own state, network and gestures. While it is up the world behind is blurred and heard under water. Today's reward
-- claimed and shown, it moves on to SPIN by itself while a spin waits there.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local vide = require(ReplicatedStorage.Packages.vide)
-- Through PlayerScripts, the copy that runs: requiring the StarterPlayer one would load a second controller.
local BlurController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.BlurController)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local DailyRewardsController = require(script.Parent.DailyRewardsController)
local SpinsController = require(script.Parent.SpinsController)
local Shell = require(script.Shell)
local Types = require(script.Types)

local LocalPlayer = Players.LocalPlayer
local source = vide.source
local create = vide.create

local Tune = table.freeze({
	-- The screen is his 1920 x 1080, fitted inside the viewport whole.
	DESIGN = Vector2.new(1920, 1080),
	-- Above the lobby's HUD, under the Gems counter (6) and the settings screen.
	DISPLAY_ORDER = 5,
	-- How long the clock keeps ticking after a stamp: the longest gesture is shorter.
	MOTION_SECONDS = 1.8,
	-- A page picked comes in this long after the other starts to leave, so the two do not stand on each other.
	SWITCH_DELAY = 0.15,
	-- A tab whose page has something waiting, off show, catches the light this often.
	CALL_EVERY = 2.6,
})

-- The pages, by tab.
local DAILY = 1
local SPIN = 2

local DailyController = {}

local state: Types.TDailyScreenState = {
	Scale = source(1),
	Now = source(os.clock()),
	IsOpen = source(false),
	ToggledAt = source(-math.huge),
	Tab = source(DAILY),
	TabAt = source(-math.huge),
	CallAt = source(-math.huge),
	Refused = source(0),
	RefusedAt = source(-math.huge),
}

-- os.clock until which Now keeps ticking.
local motionUntil = -math.huge
local nextCall = math.huge

-- Whether the screen is up. Reads a vide source, so a view that calls it follows it.
function DailyController.IsOpen(): boolean
	return state.IsOpen()
end

-- How many things wait on the screen: today's reward and each free spin left. Reads vide sources.
function DailyController.Waiting(): number
	return (if DailyRewardsController.IsClaimable() then 1 else 0) + SpinsController.FreeLeft()
end

local function stamp(at: Types.Source<number>, moment: number)
	at(moment)
	motionUntil = math.max(motionUntil, moment + Tune.MOTION_SECONDS)
end

-- Each page on show or off as the screen and its tab say; a page picked comes in `delay` seconds after the other
-- starts to leave.
local function showPages(delay: number?)
	local isOpen = state.IsOpen()
	local tab = state.Tab()
	-- The page leaving first, so the one coming is not stamped behind it.
	if tab == DAILY then
		SpinsController.SetShown(false)
		DailyRewardsController.SetShown(isOpen, delay)
	else
		DailyRewardsController.SetShown(false)
		SpinsController.SetShown(isOpen, delay)
	end
end

-- Whether `tab`'s page has something waiting: today's reward, a free spin. Reads vide sources.
local function isWaiting(tab: number): boolean
	if tab == DAILY then return DailyRewardsController.IsClaimable() end
	return SpinsController.FreeLeft() > 0
end

-- The page that has something waiting: today's reward first, then a free spin; DAILY when nothing does.
local function waitingTab(): number
	if isWaiting(DAILY) then return DAILY end
	if isWaiting(SPIN) then return SPIN end
	return DAILY
end

-- Opens on `tab`, or on the page with something waiting.
function DailyController.Open(tab: number?)
	if state.IsOpen() then return end
	local now = os.clock()
	vide.batch(function()
		state.IsOpen(true)
		state.Tab(tab or waitingTab())
		stamp(state.ToggledAt, now)
		state.TabAt(-math.huge)
	end)
	nextCall = now + Tune.CALL_EVERY
	showPages()
	SoundsCore.SetMuffled("Daily", true)
	BlurController.SetBlurred("Daily", true)
	SoundsCore.PlayUINamed("UI", "MenuIn")
end

function DailyController.Close()
	if not state.IsOpen() then return end
	vide.batch(function()
		state.IsOpen(false)
		stamp(state.ToggledAt, os.clock())
	end)
	showPages()
	SoundsCore.SetMuffled("Daily", false)
	BlurController.SetBlurred("Daily", false)
	SoundsCore.PlayUINamed("UI", "MenuOut")
end

local function pickTab(tab: number)
	if tab == state.Tab() or not state.IsOpen() then return end
	-- The reel holds the SPIN page until its prize has landed.
	if SpinsController.IsSpinning() then
		vide.batch(function()
			state.Refused(tab)
			stamp(state.RefusedAt, os.clock())
		end)
		SoundsCore.PlayUINamed("UI.UpgradePick", "Denied")
		return
	end

	vide.batch(function()
		state.Tab(tab)
		stamp(state.TabAt, os.clock())
	end)
	showPages(Tune.SWITCH_DELAY)
end

-- Today's reward shown: on to SPIN while a spin waits there and the screen is still on the reward.
local function moveOnToSpin()
	if not state.IsOpen() or state.Tab() ~= DAILY or not SpinsController.CanSpin() then return end
	pickTab(SPIN)
end

local actions: Types.TDailyScreenActions = {
	Close = DailyController.Close,
	PickTab = pickTab,
}

local function updateScale()
	local viewport = Workspace.CurrentCamera.ViewportSize
	state.Scale(math.max(math.min(viewport.Y / Tune.DESIGN.Y, viewport.X / Tune.DESIGN.X), 0.01))
end

DailyController.OnStart = function()
	vide.mount(function()
		vide.effect(function()
			if DailyRewardsController.ClaimsShown() == 0 then return end
			vide.untrack(moveOnToSpin)
		end)

		local morph = Shell.Morph(state)
		local spinShape = SpinsController.BuildShape()
		local spinPanel = vide.derive(function(): Vector2
			local shape = spinShape()
			return Vector2.new(shape.Top, shape.Height)
		end)
		local top = Shell.Top(morph, spinPanel)
		local rewardsPage, rewardsFlights =
			DailyRewardsController.BuildPage(Shell.Lift(top, DAILY, DailyRewardsController.IsShown))
		local spinsPage, spinsFlights, shake =
			SpinsController.BuildPage(Shell.Lift(top, SPIN, SpinsController.IsShown), spinShape)
		local back, middle, front = Shell.Build(state, actions, {
			Day = DailyRewardsController.Day,
			FreePerDay = SpinsController.FreePerDay,
			IsWaiting = isWaiting,
			IsSpinning = SpinsController.IsSpinning,
			Shake = shake,
			SpinShape = spinPanel,
		}, morph, top, { rewardsPage, spinsPage })
		-- Drawn only while it is up, still leaving, or a reward's Gems are still in the air: shut, it costs nothing.
		local isDrawn = vide.derive(function(): boolean
			return state.IsOpen()
				or state.Now() - state.ToggledAt() < Shell.LEAVE_SECONDS + 0.05
				or DailyRewardsController.IsPayingOut()
		end)

		-- One full-screen layer each, stacked by ZIndex (siblings drawn by ZIndex, not by order): the dim and the panel,
		-- the pages on it, the header over them, the flights over all.
		local function layer(name: string, zIndex: number, children: { Instance }): Frame
			return create("Frame")({
				Name = name,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = zIndex,
				children,
			})
		end

		return create("ScreenGui")({
			Name = "Daily",
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			DisplayOrder = Tune.DISPLAY_ORDER,
			Enabled = isDrawn,
			layer("Back", 1, back),
			layer("Pages", 2, middle),
			layer("Front", 3, front),
			layer("Flights", 4, { spinsFlights, rewardsFlights }),
		})
	end, LocalPlayer:WaitForChild("PlayerGui"))

	-- Now is written only while something moves, so a screen at rest, open or shut, redraws nothing.
	RunService.PreRender:Connect(function()
		local now = os.clock()
		if state.IsOpen() and now >= nextCall then
			nextCall = now + Tune.CALL_EVERY
			-- The call keeps the clock ticking only while its light crosses.
			if isWaiting(if state.Tab() == DAILY then SPIN else DAILY) then
				state.CallAt(now)
				motionUntil = math.max(motionUntil, now + Shell.CALL_SECONDS)
			end
		end
		if now < motionUntil then state.Now(now) end
	end)

	local camera = Workspace.CurrentCamera
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	updateScale()
end

return Ignis.Register(DailyController)
