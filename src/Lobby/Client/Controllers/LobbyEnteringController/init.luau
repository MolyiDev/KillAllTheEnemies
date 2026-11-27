-- The results of the last run, back in the lobby (UIMatt.md, Lobby Entering): the server sends the run the profile
-- holds as it loads (Results.Show), whether the player came back from it or walked out of it and came in again, and
-- LOBBY drops it (Results.Dismiss). The camera goes to the elevator in the map (Stage), where the squad stands with
-- their tags over their heads (Squad); Header and Stats are over it. This owns the state, loads the squad's avatars,
-- cuts to black and back across each jump of the camera, and drives the stage and the clock.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local vide = require(ReplicatedStorage.Packages.vide)
local NetworkMeta = require(StarterPlayer.StarterPlayerScripts.GlobalClient.NetworkMeta)
-- Through PlayerScripts, the copy that runs: requiring the StarterPlayer one would load a second controller.
local ProfileController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.ProfileController)
local LoadingGate = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.LoadingGate)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Header = require(script.Header)
local Squad = require(script.Squad)
local Stage = require(script.Stage)
local Stats = require(script.Stats)
local Types = require(script.Types)
local TProfile = require(ReplicatedStorage.Types.TProfile)

local ServerNetworkResults = NetworkMeta.Server.Results
local ClientNetworkResults = NetworkMeta.Client.Results

local LocalPlayer = Players.LocalPlayer
local create = vide.create
local source = vide.source
local Progress = Motion.Progress

local Timing = table.freeze({
	FADE = 0.35,
	CLOSE = 0.22,
	-- A light dim over the stage, so the panels lift off it.
	DIM = 0.15,
	-- The cut across a jump of the camera: in from black as the screen opens; as it closes, to black by the end of
	-- CLOSE (the camera goes back to the player there), then out of it.
	CUT_OPEN = 0.5,
	CUT_CLOSE = 0.35,
})
local RENDER_STEP = "LobbyEnteringStage"

local LobbyEnteringController = {}

local state: Types.TState = {
	Scale = source(1),
	Width = source(Theme.DESIGN_HEIGHT * 16 / 9),
	Now = source(os.clock()),
	IsOpen = source(false),
	ToggledAt = source(-math.huge),
	Record = source(nil :: TProfile.TMatchRecord?),
	Members = source({} :: { Types.TMember }),
	TotalGems = source(0),
}

-- Whether the results are up, for the lobby's screen to step aside (LobbyController's cover).
LobbyEnteringController.IsOpen = state.IsOpen

-- Counts the records shown: an avatar that loads for one already gone is thrown away.
local generation = 0
local isStaged = false

local function elapsed(): number
	return state.Now() - state.ToggledAt()
end

local clock: Types.TClock = {
	Elapsed = elapsed,
	Shown = function(): number
		if state.IsOpen() then return Motion.Out(Progress(elapsed(), 0, Timing.FADE)) end
		return 1 - Progress(elapsed(), 0, Timing.CLOSE)
	end,
	Since = function(delay: number, seconds: number): number
		if not state.IsOpen() then return 1 end
		return Progress(elapsed(), delay, seconds)
	end,
}

-- How see-through the black of the cut is now.
local function cut(): number
	local since = elapsed()
	if state.IsOpen() then return Motion.Out(Progress(since, 0.05, Timing.CUT_OPEN)) end
	if since < Timing.CLOSE then return 1 - since / Timing.CLOSE end
	return Motion.Out(Progress(since, Timing.CLOSE, Timing.CUT_CLOSE))
end

local function arriveAt(member: Types.TMember): number
	return Squad.ArriveAt(state, member)
end

-- One frame of the stage, after the camera's own controllers. Once the close has gone to black, the camera goes back
-- and the stage stops.
local function stepStage(dt: number)
	vide.batch(function()
		state.Now(os.clock())
		if not state.IsOpen() and elapsed() >= Timing.CLOSE then
			isStaged = false
			RunService:UnbindFromRenderStep(RENDER_STEP)
			Stage.End()
			return
		end
		Stage.Step(state, clock, dt, arriveAt)
	end)
end

-- Into the elevator, once its parts are here.
local function stage(shownGeneration: number)
	Stage.StreamInAsync()
	if shownGeneration ~= generation or not state.IsOpen() then return end
	if isStaged then RunService:UnbindFromRenderStep(RENDER_STEP) end
	isStaged = Stage.Begin()
	if isStaged then RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Camera.Value + 2, stepStage) end
end

local function clearAvatars()
	for _, member in state.Members() do
		local avatar = member.Avatar()
		if avatar then avatar:Destroy() end
	end
end

-- Builds `member`'s avatar as it spawns (GlobalServer.Utils.loadCharacter), or the default avatar for an account that
-- has none (Studio's test players). Yields on the web, so spawned.
local function loadAvatar(member: Types.TMember, shownGeneration: number)
	local fetched, description = false, nil
	if member.UserId > 0 then
		fetched, description = pcall(Players.GetHumanoidDescriptionFromUserIdAsync, Players, member.UserId)
	end
	if not fetched then description = Instance.new("HumanoidDescription") end

	-- R6, as the lobby loads its players.
	local built, model =
		pcall(Players.CreateHumanoidModelFromDescriptionAsync, Players, description, Enum.HumanoidRigType.R6)
	if shownGeneration ~= generation then
		if built and model then model:Destroy() end
		return
	end

	if not built or not model then
		warn(`[LobbyEnteringController] no avatar for {member.Name}: {model}`)
		member.LoadedAt(os.clock())
		return
	end

	for _, child in model:GetDescendants() do
		if child:IsA("LuaSourceContainer") then child:Destroy() end
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end

	vide.batch(function()
		member.Avatar(model)
		member.LoadedAt(os.clock())
	end)
end

local function show(record: TProfile.TMatchRecord)
	generation += 1
	clearAvatars()

	local slots, turns, mvp = Squad.Arrange(record.Squad)
	local members = table.create(#record.Squad)
	for index, entry in record.Squad do
		members[index] = {
			UserId = entry.UserId,
			Name = entry.Name,
			ClassId = entry.ClassId,
			Kills = entry.Kills,
			IsMvp = index == mvp,
			Slot = slots[index],
			Order = turns[index],
			Avatar = source(nil :: Model?),
			LoadedAt = source(math.huge),
			HeadAt = source(Vector3.new(0, 0, -1)),
			InfoWidth = source(0),
		}
	end

	local now = os.clock()
	vide.batch(function()
		state.Record(record)
		state.Members(members)
		state.TotalGems(ProfileController.Gems)
		state.IsOpen(true)
		state.ToggledAt(now)
		state.Now(now)
	end)

	task.spawn(stage, generation)
	for _, member in members do
		task.spawn(loadAvatar, member, generation)
	end
end

local actions: Types.TActions = {
	Close = function()
		if not state.IsOpen() then return end
		ClientNetworkResults.Dismiss.Fire()
		local now = os.clock()
		vide.batch(function()
			state.IsOpen(false)
			state.ToggledAt(now)
		end)

		-- Once it has gone, the avatars go with it.
		local closedGeneration = generation
		task.delay(Timing.CLOSE + Timing.CUT_CLOSE + 0.05, function()
			if closedGeneration ~= generation or state.IsOpen() then return end
			clearAvatars()
			state.Members({})
		end)
	end,
}

local function update()
	local viewport = Workspace.CurrentCamera.ViewportSize
	local scale = math.clamp(viewport.Y / Theme.DESIGN_HEIGHT, Theme.MIN_SCALE, Theme.MAX_SCALE)
	state.Scale(scale)
	state.Width(viewport.X / scale)

	local now = os.clock()
	if state.IsOpen() or now - state.ToggledAt() < Timing.CLOSE + Timing.CUT_CLOSE + 0.1 then state.Now(now) end
end

-- Sent as the profile loads, while the loading screen still covers the lobby: held until it lifts, so the cut in
-- and the squad's arrival are seen.
ServerNetworkResults.Show.On(function(record: TProfile.TMatchRecord)
	LoadingGate.OnLifted(function()
		show(record)
	end)
end)

LobbyEnteringController.OnStart = function()
	ProfileController.OnChanged:Connect(function()
		state.TotalGems(ProfileController.Gems)
	end)

	update()
	vide.mount(function()
		return create("ScreenGui")({
			Name = "LobbyEntering",
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			-- Over the lobby's HUD and its screens.
			DisplayOrder = 5,
			Enabled = function()
				return clock.Shown() > 0.001 or cut() < 0.999
			end,
			-- A button, so a press on the dim stops here instead of reaching the lobby under it.
			create("TextButton")({
				Name = "Dim",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.new(),
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = "",
				BackgroundTransparency = function()
					return 1 - Timing.DIM * clock.Shown()
				end,
			}),
			-- Scaled from a 1080-tall design, as the HUD is.
			create("Frame")({
				Name = "Root",
				BackgroundTransparency = 1,
				Size = function()
					local scale = state.Scale()
					return UDim2.fromScale(1 / scale, 1 / scale)
				end,
				ZIndex = 2,
				create("UIScale")({ Scale = state.Scale }),
				Squad.Build(state, clock),
				Header.Build(state, clock),
				Stats.Build(state, clock, actions),
			}),
			create("Frame")({
				Name = "Cut",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.new(),
				BorderSizePixel = 0,
				ZIndex = 10,
				Interactable = false,
				BackgroundTransparency = cut,
				Visible = function()
					return cut() < 0.999
				end,
			}),
		})
	end, LocalPlayer:WaitForChild("PlayerGui"))

	RunService.Heartbeat:Connect(function()
		vide.batch(update)
	end)
end

return Ignis.Register(LobbyEnteringController)
