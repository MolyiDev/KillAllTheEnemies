--!nonstrict
-- The loading screen both places draw on joining (LoadingScreen.client in ReplicatedFirst): KILL ALL THE MONSTERS
-- dealt in letter by letter and a bar that fills with the load, over a deep backdrop with a few pixels rising through
-- it. Leaving, the content shrinks away and the backdrop breaks into squares that open from the middle. Its one sound
-- is that exit. It also covers a teleport out (TeleportCoverController) and picks up the still copy of that cover the
-- teleport carries in, so a place change reads as one screen. This file owns the state, the clock, the bar's reading and the API; each piece draws itself from the
-- state (Backdrop, Title, Bar), so a story can hold any moment still.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")
local vide = require(ReplicatedStorage.Packages.vide)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Backdrop = require(script.Backdrop)
local Bar = require(script.Bar)
local Title = require(script.Title)
local Types = require(script.Types)

local create = vide.create
local source = vide.source
local derive = vide.derive
local Palette = Theme.Palette
local Progress = Motion.Progress

export type TOptions = {
	Mode: Types.TMode?,
	-- The words over the bar to start with.
	Text: string?,
	-- An arrival's teleport copy: it stays over the screen until the screen has drawn its own title and bar under it.
	Arriving: ScreenGui?,
}

export type TLoadingScreen = {
	-- A stage of the load, filling the bar from `fromShare` to `toShare`. With no progress reported it creeps toward
	-- the end and never reaches it, so a long wait still moves.
	SetPhase: (text: string, fromShare: number, toShare: number) -> (),
	-- How far through the current stage, 0 to 1.
	SetProgress: (share: number) -> (),
	-- Fills the bar and pays it off. Yields until the payoff has held, or the screen leaves.
	Complete: () -> (),
	-- Shows the skip prompt; any key, click, tap or button then calls `onSkip` once.
	ShowSkip: (onSkip: () -> ()) -> (),
	-- Starts the way out: `onLifted` as the backdrop's squares start opening, `onGone` once it is destroyed. Only
	-- the first call counts.
	Leave: (onLifted: (() -> ())?, onGone: (() -> ())?) -> (),
	IsLeaving: () -> boolean,
	-- Yields until a cover has closed and its title and bar are up (or the screen leaves, or it gives up).
	WaitReady: () -> (),
	-- A still copy of the screen for `TeleportService:SetTeleportGui`, named SNAPSHOT_NAME; nil drawn into a frame.
	Snapshot: () -> ScreenGui?,
	-- Tears it down at once, wherever it is (a bench re-running).
	Destroy: () -> (),
}

local LoadingScreen = {}

-- What the arriving place's LoadingScreen.client looks for, to open as an arrival rather than a join.
LoadingScreen.SNAPSHOT_NAME = "LoadingSnapshot"
-- The flat colour under everything.
LoadingScreen.BASE = Backdrop.BASE

local Tune = table.freeze({
	-- Text lays out from the font's real measure once it is in; past this it lays out on a guess.
	FONT_WAIT_SECONDS = 1.5,
	-- A stage with no progress reported creeps toward this share of itself, on this time constant.
	CREEP_SHARE = 0.92,
	CREEP_SECONDS = 3.5,
	-- The reading chases what is loaded at this rate (1/s), and once complete never slower than COMPLETE_SPEED a
	-- second, so a load that finished early still fills rather than jumping.
	FOLLOW_RATE = 4.5,
	COMPLETE_SPEED = 0.9,
	PAYOFF_SHARE = 0.995,
	-- How long the payoff holds before Complete returns, and the most it waits for a bar that never fills.
	HOLD_SECONDS = 0.6,
	COMPLETE_CAP_SECONDS = 10,
	-- The way out: the bar closes, then the title shrinks and fades, while the backdrop's squares start opening.
	CONTENT_SECONDS = 0.28,
	CONTENT_STAGGER = 0.05,
	CONTENT_TO = 0.82,
	DESIGN = Vector2.new(1920, 1080),
	SKIP_SIZE = 18,
	SKIP_FROM_BOTTOM = 46,
	SKIP_SECONDS = 0.4,
	SKIP_BREATH = 2.4,
	READY_CAP_SECONDS = 5,
	-- The teleport copy goes this many frames after the screen has drawn its own title under it.
	ARRIVING_FRAMES = 2,
})

-- The content all up: an arrival starts this far into it, as its teleport copy was frozen.
local UP_SECONDS = math.max(Title.LANDED_AT, Bar.UP_AT)
-- What a snapshot leaves out: everything that moves, and the squares, hidden by then.
local UNFROZEN = table.freeze({ Motes = true, Squares = true, Skip = true })

local NEVER = math.huge

local function isSkipInput(input: InputObject): boolean
	local kind = input.UserInputType
	return kind == Enum.UserInputType.Keyboard
		or kind == Enum.UserInputType.MouseButton1
		or kind == Enum.UserInputType.MouseButton2
		or kind == Enum.UserInputType.Touch
		or string.sub(kind.Name, 1, 7) == "Gamepad"
end

-- Types.TClock. Every piece fades its own parts on the way out: a CanvasGroup made for it draws nothing for its first
-- frames, and the content blinked out.
local function clockOf(state: Types.TState): Types.TClock
	-- 0 to 1 through a piece's way out; 0 without reading the clock until the screen leaves.
	local function out(order: number): number
		local leaveAt = state.LeaveAt()
		if leaveAt == NEVER then return 0 end
		return Progress(state.Now(), leaveAt + order * Tune.CONTENT_STAGGER, Tune.CONTENT_SECONDS)
	end

	return {
		-- An infinite age makes NaN of any curve that does more than clamp it, and a NaN position or transparency draws.
		Since = function(at: number): number
			if at == NEVER then return -1 end
			return math.max(-1, state.Now() - at)
		end,
		Opacity = function(order: number): number
			local t = out(order)
			return 1 - t * t * (3 - 2 * t)
		end,
		Close = function(order: number): number
			return 1 - Motion.Accelerate(out(order))
		end,
		Content = function(order: number): number
			return 1 - (1 - Tune.CONTENT_TO) * Motion.Accelerate(out(order))
		end,
		Cover = derive(function(): number
			local leaveAt = state.LeaveAt()
			if leaveAt == NEVER then return 1 end
			return 1 - Motion.Out(Progress(state.Now(), leaveAt, Backdrop.SQUARES_AT))
		end),
	}
end

local function skipCaption(state: Types.TState, clock: Types.TClock): TextLabel
	return create("TextLabel")({
		Name = "Skip",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -Tune.SKIP_FROM_BOTTOM),
		Size = UDim2.fromOffset(0, Tune.SKIP_SIZE),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		FontFace = Theme.Font.DisplayBold,
		TextSize = Tune.SKIP_SIZE,
		TextColor3 = Palette.Lavender,
		Text = if state.IsTouch then "TAP TO SKIP" else "PRESS ANY KEY TO SKIP",
		ZIndex = 8,
		TextTransparency = function()
			if state.SkipAt() == NEVER then return 1 end
			local now = state.Now()
			local appear = Motion.Out(Progress(now, state.SkipAt(), Tune.SKIP_SECONDS))
			local gone = 1 - Progress(now, state.PaidAt(), Tune.SKIP_SECONDS)
			local breath = 0.8 + 0.2 * math.cos(2 * math.pi * clock.Since(state.SkipAt()) / Tune.SKIP_BREATH)
			return 1 - 0.75 * appear * gone * breath * clock.Opacity(0)
		end,
	})
end

-- Draws into `parent` (a ScreenGui, or a story's frame), covering it.
function LoadingScreen.new(parent: Instance, options: TOptions?): TLoadingScreen
	local settings = options or {}
	local mode: Types.TMode = settings.Mode or "Join"
	local shownAt = os.clock()
	local state: Types.TState = {
		Mode = mode,
		Now = source(shownAt),
		Scale = source(1),
		Width = source(Tune.DESIGN.X),
		Height = source(Tune.DESIGN.Y),
		ShownAt = source(shownAt),
		CoveredAt = if mode == "Cover" then shownAt + Backdrop.COVER_SECONDS else shownAt,
		BeganAt = source(NEVER),
		Metrics = source(nil),
		Phase = source(settings.Text or "LOADING"),
		Reading = source(0),
		PaidAt = source(NEVER),
		SkipAt = source(NEVER),
		LeaveAt = source(NEVER),
		IsTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled,
	}
	-- Everything reactive is made inside the root: the script calling this is no vide scope, and a derive made
	-- outside one errors.
	local destroyRoot, rootFrame = vide.root(function()
		local clock = clockOf(state)
		local content = create("Frame")({
			Name = "Content",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Title.Build(state, clock),
			Bar.Build(state, clock),
		})
		return create("Frame")({
			Name = "Loading",
			-- Held on the middle: a screen whose size is still settling as it goes up grows from there.
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
			Size = function()
				local scale = state.Scale()
				return UDim2.fromScale(1 / scale, 1 / scale)
			end,
			-- Over anything the place puts up meanwhile (the lobby's HUD, a screen), and swallowing the hand.
			Active = true,
			ZIndex = 100,
			create("UIScale")({ Scale = state.Scale }),
			Backdrop.Build(state, clock.Cover),
			content,
			skipCaption(state, clock),
		})
	end)
	rootFrame.Parent = parent

	-- What the stepper keeps: the stage being filled and what is loaded in all.
	local stage = { From = 0, To = 1, Start = shownAt, Share = nil :: number? }
	local target = 0
	local isComplete = false
	local isGone = false
	local onLifted: (() -> ())? = nil
	local onGone: (() -> ())? = nil
	local hasLifted = false
	local connections: { RBXScriptConnection } = {}

	local function layout()
		local size = (parent :: GuiBase2d).AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then return end
		local scale = math.min(size.Y / Tune.DESIGN.Y, size.X / Tune.DESIGN.X)
		state.Scale(scale)
		state.Width(size.X / scale)
		state.Height(size.Y / scale)
	end

	local function teardown()
		if isGone then return end
		isGone = true
		for _, connection in connections do
			connection:Disconnect()
		end
		destroyRoot()
		rootFrame:Destroy()
	end

	-- The bar's reading chases what is loaded; full and complete, it pays off.
	local function stepReading(now: number, dt: number)
		local creep = Tune.CREEP_SHARE * (1 - math.exp(-(now - stage.Start) / Tune.CREEP_SECONDS))
		local within = stage.Share or creep
		target = math.max(target, if isComplete then 1 else stage.From + (stage.To - stage.From) * within)
		if now < state.BeganAt() + Bar.FILLS_AT then return end

		local shown = state.Reading()
		local gain = (target - shown) * (1 - math.exp(-Tune.FOLLOW_RATE * dt))
		if isComplete then gain = math.max(gain, Tune.COMPLETE_SPEED * dt) end
		local reading = math.min(target, shown + gain)
		if reading ~= shown then state.Reading(reading) end

		if isComplete and state.PaidAt() == NEVER and reading >= Tune.PAYOFF_SHARE then state.PaidAt(now) end
	end

	local function stepLeave(now: number)
		local leaveAt = state.LeaveAt()
		if now < leaveAt + Backdrop.SQUARES_AT then return end
		if not hasLifted then
			hasLifted = true
			if onLifted then task.spawn(onLifted) end
		end
		if now < leaveAt + Backdrop.EXIT_SECONDS then return end
		teardown()
		if onGone then task.spawn(onGone) end
	end

	local function step(dt: number)
		local now = os.clock()
		vide.batch(function()
			state.Now(now)
			-- A cover's bar stays empty: the place it goes to fills it.
			if mode ~= "Cover" then stepReading(now, dt) end
		end)
		stepLeave(now)
	end

	-- The teleport copy goes once the screen has drawn its own title and bar under it, a few frames after they are
	-- made.
	local function dropArriving(arriving: ScreenGui)
		for _ = 1, Tune.ARRIVING_FRAMES do
			RunService.Heartbeat:Wait()
		end
		arriving:Destroy()
	end

	-- What the measure unlocks: the content, once a cover has closed, and already up on an arrival.
	local function begin(metrics: Types.TMetrics)
		if state.Metrics() or isGone then return end
		local now = os.clock()
		local beganAt = if mode == "Cover"
			then math.max(now, state.CoveredAt)
			elseif mode == "Arrive" then now - UP_SECONDS
			else now
		vide.batch(function()
			state.Metrics(metrics)
			state.BeganAt(beganAt)
		end)
		if settings.Arriving then task.spawn(dropArriving, settings.Arriving) end
	end

	local screen = {} :: TLoadingScreen

	function screen.SetPhase(text: string, fromShare: number, toShare: number)
		if isComplete then return end
		stage.From = fromShare
		stage.To = toShare
		stage.Start = os.clock()
		stage.Share = nil
		if text ~= state.Phase() then state.Phase(text) end
	end

	function screen.SetProgress(share: number)
		stage.Share = math.clamp(share, 0, 1)
	end

	function screen.Complete()
		isComplete = true
		local waited = 0
		while not isGone and state.LeaveAt() == NEVER and waited < Tune.COMPLETE_CAP_SECONDS do
			if os.clock() - state.PaidAt() >= Tune.HOLD_SECONDS then return end
			waited += task.wait()
		end
	end

	function screen.ShowSkip(onSkip: () -> ())
		if isGone or state.LeaveAt() ~= NEVER or state.SkipAt() ~= NEVER then return end
		state.SkipAt(os.clock())
		local isSkipped = false
		table.insert(
			connections,
			UserInputService.InputBegan:Connect(function(input: InputObject)
				if isSkipped or state.LeaveAt() ~= NEVER or not isSkipInput(input) then return end
				isSkipped = true
				onSkip()
			end)
		)
	end

	function screen.Leave(lifted: (() -> ())?, gone: (() -> ())?)
		if isGone or state.LeaveAt() ~= NEVER then return end
		-- A teleport copy still up would hide the way out.
		if settings.Arriving then settings.Arriving:Destroy() end
		onLifted = lifted
		onGone = gone
		state.LeaveAt(os.clock())
	end

	function screen.IsLeaving(): boolean
		return state.LeaveAt() ~= NEVER
	end

	function screen.WaitReady()
		local waited = 0
		while not isGone and state.LeaveAt() == NEVER and waited < Tune.READY_CAP_SECONDS do
			if os.clock() >= state.BeganAt() + UP_SECONDS then return end
			waited += task.wait()
		end
	end

	function screen.Snapshot(): ScreenGui?
		if isGone or not parent:IsA("ScreenGui") then return nil end
		local copy = parent:Clone()
		copy.Name = LoadingScreen.SNAPSHOT_NAME
		-- Over the arriving place's own screen, which draws under it until it can take over.
		copy.DisplayOrder = parent.DisplayOrder + 1
		for _, descendant in copy:GetDescendants() do
			if UNFROZEN[descendant.Name] then descendant:Destroy() end
		end
		local phase = copy:FindFirstChild("Phase", true)
		if phase and phase:IsA("TextLabel") then phase.Text = (string.gsub(phase.Text, "%.*$", "...")) end
		return copy
	end

	screen.Destroy = teardown

	if parent:IsA("GuiBase2d") then
		table.insert(connections, parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
		layout()
	end
	table.insert(connections, RunService.Heartbeat:Connect(step))

	local isMeasured = false
	task.spawn(function()
		local ok, measured = pcall(Title.Measure)
		if isMeasured then return end
		isMeasured = true
		begin(if ok then measured else Title.Guess())
	end)
	task.delay(Tune.FONT_WAIT_SECONDS, function()
		if isMeasured then return end
		isMeasured = true
		begin(Title.Guess())
	end)

	return screen
end

return LoadingScreen
