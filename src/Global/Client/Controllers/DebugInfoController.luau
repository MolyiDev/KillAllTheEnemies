-- The debug readout's numbers (UI/DebugInfoUI), in both places, up while the settings' DEBUG INFO is on: FPS, ping,
-- the body's speed, tracers and particles here, and whatever a place counts of its own (Track). Sampled a few times a
-- second while it is up and not at all while it is down; a value that shows the same is not written again.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local vide = require(ReplicatedStorage.Packages.vide)
local fxBudget = require(script.Parent.Parent.Utils.fxBudget)
local tracers = require(script.Parent.Parent.Utils.tracers)
local DebugInfoUI = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.DebugInfoUI)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local UiFade = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.UiFade)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)

local LocalPlayer = Players.LocalPlayer
local source = vide.source
local create = vide.create
local Palette = Theme.Palette

local Tune = table.freeze({
	SAMPLE_SECONDS = 0.25,
	-- FPS is the frames counted over this long: a quarter second at 60 is 15 frames, too few to read steadily.
	FPS_SECONDS = 0.5,
	GOOD_FPS = 55,
	OKAY_FPS = 30,
	GOOD_PING_MS = 120,
	OKAY_PING_MS = 250,
	-- Under every other gui, the floating numbers (-3) included: anything else drawn there covers it.
	DISPLAY_ORDER = -4,
	-- Design px the column keeps over a phone's jump button.
	JUMP_GAP = 10,
})
local BAD = Color3.fromRGB(230, 60, 72)

type TSpec = {
	Name: string,
	-- One decimal; nil for a whole number.
	IsTenths: boolean?,
	-- The colour a value earns; nil for plain white.
	Grade: ((number) -> Color3)?,
}

local function fpsGrade(fps: number): Color3
	if fps >= Tune.GOOD_FPS then return Palette.Green end
	if fps >= Tune.OKAY_FPS then return Palette.Gold end
	return BAD
end

local function pingGrade(ms: number): Color3
	if ms <= Tune.GOOD_PING_MS then return Palette.Green end
	if ms <= Tune.OKAY_PING_MS then return Palette.Gold end
	return BAD
end

-- Top to bottom, FPS last, nearest the corner.
local SPECS: { TSpec } = {
	{ Name = "ENEMIES" },
	{ Name = "PROJECTILES" },
	{ Name = "COINS" },
	{ Name = "PARTICLES" },
	{ Name = "SPEED", IsTenths = true },
	{ Name = "PING", Grade = pingGrade },
	{ Name = "FPS", Grade = fpsGrade },
}

type TCounted = { Line: DebugInfoUI.TLine, Spec: TSpec, Readers: { () -> number } }

local lines: { DebugInfoUI.TLine } = table.create(#SPECS)
-- Each line with its spec and what it adds up, in SPECS' order and by name.
local counted: { TCounted } = table.create(#SPECS)
local countedByName: { [string]: TCounted } = {}
for index, spec in SPECS do
	local data = {
		Name = spec.Name,
		Value = source("0"),
		Color = source(if spec.Grade then spec.Grade(0) else Palette.White),
		IsUsed = source(false),
	}
	lines[index] = data
	counted[index] = { Line = data, Spec = spec, Readers = {} }
	countedByName[spec.Name] = counted[index]
end

local state: DebugInfoUI.TDebugInfoState = {
	Scale = source(1),
	Now = source(os.clock()),
	IsShown = source(false),
	ToggledAt = source(-math.huge),
	Lift = source(0),
	Clear = source(0),
	Lines = lines,
}

local isShown = false
-- os.clock until which Now keeps ticking.
local motionUntil = -math.huge
local nextSampleAt = -math.huge
-- Frames counted since fpsFrom, and the last whole count's rate. Counted while the column is down too (one add a
-- frame), so it shows a real number the moment it is up.
local frames = 0
local fpsFrom = os.clock()
local fps = 0
local selfRoot: BasePart? = nil
-- A place's own screen over the world that every UI gives way to (the match's upgrade cards).
local isCovered = source(false)

local DebugInfoController = {}

function DebugInfoController.SetShown(shown: boolean)
	if isShown == shown then return end
	isShown = shown
	local now = os.clock()
	vide.batch(function()
		state.IsShown(shown)
		state.ToggledAt(now)
	end)
	motionUntil = now + DebugInfoUI.SettleSeconds(#lines)
	nextSampleAt = -math.huge
end

-- Adds `read` to the line `name` (one of SPECS'): a line counts the sum of what it is given, and is drawn only once
-- something gives it a count.
function DebugInfoController.Track(name: string, read: () -> number)
	local entry = countedByName[name]
	assert(entry, `DebugInfoController.Track: no line {name}`)
	table.insert(entry.Readers, read)
	entry.Line.IsUsed(true)
end

-- Keeps `px` (design px off the screen's right edge) for the place's own corner: the column stands left of it.
function DebugInfoController.SetClear(px: number)
	state.Clear(px)
end

-- Hides the column while `covered`, as the HUD is.
function DebugInfoController.SetCovered(covered: boolean)
	isCovered(covered)
end

-- Design px the column must rise to stand over the jump button, 0 with none in its way.
local function jumpLift(): number
	if not UserInputService.TouchEnabled then return 0 end
	local touchGui = LocalPlayer.PlayerGui:FindFirstChild("TouchGui") :: ScreenGui?
	if not touchGui or not touchGui.Enabled then return 0 end
	local jump = touchGui:FindFirstChild("JumpButton", true) :: GuiObject?
	if not jump or not jump.Visible then return 0 end

	local scale = state.Scale()
	local viewport = Workspace.CurrentCamera.ViewportSize
	local inset = if touchGui.IgnoreGuiInset then 0 else GuiService:GetGuiInset().Y
	local jumpTop = jump.AbsolutePosition.Y + inset
	local jumpRight = jump.AbsolutePosition.X + jump.AbsoluteSize.X
	return DebugInfoUI.LiftOver(jumpTop, jumpRight, viewport, scale, Tune.JUMP_GAP, state.Clear())
end

local function sample()
	vide.batch(function()
		for _, entry in counted do
			local readers = entry.Readers
			if #readers == 0 then continue end
			local value = 0
			for _, read in readers do
				value += read()
			end
			local spec, data = entry.Spec, entry.Line
			data.Value(if spec.IsTenths then string.format("%.1f", value) else tostring(math.round(value)))
			if spec.Grade then data.Color(spec.Grade(value)) end
		end
		state.Lift(jumpLift())
	end)
end

local function update()
	local now = os.clock()
	if now < motionUntil then state.Now(now) end

	frames += 1
	local elapsed = now - fpsFrom
	if elapsed >= Tune.FPS_SECONDS then
		fps = frames / elapsed
		frames = 0
		fpsFrom = now
	end

	if not isShown or isCovered() or now < nextSampleAt then return end
	nextSampleAt = now + Tune.SAMPLE_SECONDS
	sample()
end

local function updateScale()
	local viewport = Workspace.CurrentCamera.ViewportSize
	state.Scale(math.clamp(viewport.Y / Theme.DESIGN_HEIGHT, Theme.MIN_SCALE, Theme.MAX_SCALE))
end

-- The body's speed over the ground, studs a second.
local function readSpeed(): number
	local root = selfRoot
	if not root then return 0 end
	local velocity = root.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

DebugInfoController.OnStart = function()
	-- What every place counts; the rest is the place's own (Track).
	DebugInfoController.Track("FPS", function(): number
		return fps
	end)
	DebugInfoController.Track("PING", function(): number
		return LocalPlayer:GetNetworkPing() * 1000
	end)
	DebugInfoController.Track("SPEED", readSpeed)
	DebugInfoController.Track("PROJECTILES", tracers.Flying)
	DebugInfoController.Track("PARTICLES", fxBudget.Alive)

	vide.mount(function()
		-- Drawn only while it is up or still folding away, and not given way to a cutscene or a place's cover: down, it
		-- costs nothing.
		local isDrawn = vide.derive(function(): boolean
			if not UiFade.IsUp() or isCovered() then return false end
			return state.IsShown() or state.Now() < state.ToggledAt() + DebugInfoUI.LeaveSeconds(#lines)
		end)

		return create("ScreenGui")({
			Name = "DebugInfo",
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			DisplayOrder = Tune.DISPLAY_ORDER,
			Enabled = isDrawn,
			UiFade.Group({
				create("Frame")({
					Name = "Root",
					BackgroundTransparency = 1,
					Size = function()
						local scale = state.Scale()
						return UDim2.fromScale(1 / scale, 1 / scale)
					end,
					create("UIScale")({ Scale = state.Scale }),
					DebugInfoUI.Build(state),
				}),
			}),
		})
	end, LocalPlayer:WaitForChild("PlayerGui"))

	RunService.Heartbeat:Connect(update)

	local camera = Workspace.CurrentCamera
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	updateScale()
end

DebugInfoController.OnSelfCharacterAdded = function(character)
	selfRoot = character.HumanoidRootPart
end :: TCharacterEvents.OnCharacterAdded

DebugInfoController.OnSelfCharacterRemoving = function()
	selfRoot = nil
end :: TCharacterEvents.OnCharacterRemoving

return Ignis.Register(DebugInfoController)
