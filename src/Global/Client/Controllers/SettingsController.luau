-- The player's settings on this client, in both places: the values the settings screen shows (UI/SettingsUI), what
-- each one does here (the sound buses, the camera's shake), and the screen's opening and shutting. A change is
-- applied at once and sent to SettingsService to be saved; the saved values arrive once the profile loads.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local vide = require(ReplicatedStorage.Packages.vide)
local NetworkMeta = require(StarterPlayer.StarterPlayerScripts.GlobalClient.NetworkMeta)
local CameraController = require(script.Parent.CameraController)
local SettingsCore = require(ReplicatedStorage.GlobalShared.Core.SettingsCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local SettingsUI = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.SettingsUI)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local ESettings = require(ReplicatedStorage.Types.Enums.ESettings)
local ESoundGroups = require(ReplicatedStorage.Types.Enums.Sounds.ESoundGroups)
local Types = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.SettingsUI.Types)

local ServerNetworkSettings = NetworkMeta.Server.Settings
local ClientNetworkSettings = NetworkMeta.Client.Settings
local LocalPlayer = Players.LocalPlayer
local source = vide.source
local create = vide.create

local Tune = table.freeze({
	-- How long Now keeps ticking after anything starts a timed gesture: the longest one is shorter.
	MOTION_SECONDS = 1.6,
	-- The panel is 1040 px of a 1080-tall design; on a screen narrower than this many design px it is fitted to the
	-- width instead.
	DESIGN_WIDTH = 1120,
	-- Longer than the screen's way out (SettingsUI): it is drawn this long after it is shut.
	LEAVE_SECONDS = 0.5,
	-- Above the HUD and the lobby's screens.
	DISPLAY_ORDER = 10,
	-- RESET ALL sends each changed row home this long after the one above it.
	RESET_STAGGER = 0.05,
	-- The menu sounds slider is heard as it moves: one click each time it crosses this many percent.
	TICK_PERCENT = 10,
})

-- The buses each slider turns, and the level each bus has in the place: a slider is a share of that.
local BUSES: { [number]: { string } } = {
	[ESettings.MusicVolume] = { ESoundGroups.Music },
	[ESettings.SoundEffectsVolume] = { ESoundGroups.Effects, ESoundGroups.Ambient },
	[ESettings.MenuSoundsVolume] = { ESoundGroups.UI },
}
local busLevels: { [SoundGroup]: number } = {}
local busesById: { [number]: { SoundGroup } } = {}
for id, names in BUSES do
	local groups = table.create(#names)
	for _, name in names do
		local group = SoundService:FindFirstChild(name)
		if not group or not group:IsA("SoundGroup") then continue end
		busLevels[group] = group.Volume
		table.insert(groups, group)
	end

	busesById[id] = groups
end

local function volumeRow(id: number, text: string): Types.TVolumeRow
	local default = SettingsCore.Volumes[id].Default
	return {
		Id = id,
		Label = text,
		Default = default,
		Value = source(default),
		IsDragging = source(false),
		ResetAt = source(-math.huge),
	}
end

local function toggleRow(id: number, text: string, description: string): Types.TToggleRow
	local default = SettingsCore.Toggles[id].Default
	return {
		Id = id,
		Label = text,
		Description = description,
		Default = default,
		IsOn = source(default),
		ChangedAt = source(-math.huge),
		ResetAt = source(-math.huge),
	}
end

local state: Types.TSettingsState = {
	Scale = source(1),
	Now = source(os.clock()),
	IsOpen = source(false),
	ToggledAt = source(-math.huge),
	IsConfirmOpen = source(false),
	ConfirmToggledAt = source(-math.huge),
	Volumes = {
		volumeRow(ESettings.MusicVolume, "MUSIC"),
		volumeRow(ESettings.SoundEffectsVolume, "SOUND EFFECTS"),
		volumeRow(ESettings.MenuSoundsVolume, "MENU SOUNDS"),
	},
	Toggles = {
		toggleRow(ESettings.IsCameraShakeReduced, "REDUCE CAMERA SHAKE", "No camera shake; weapon kick stays"),
		toggleRow(ESettings.IsDragFireToAim, "DRAG FIRE TO AIM", "Drag the fire button to look around"),
	},
	SavedAt = source(-math.huge),
}

-- os.clock until which Now keeps ticking.
local motionUntil = -math.huge
-- The value each slider had when the hand took its knob.
local draggedFrom: { [Types.TVolumeRow]: number } = {}

local SettingsController = {}

-- Whether the screen is up. Reads a vide source, so a view that calls it follows it.
function SettingsController.IsOpen(): boolean
	return state.IsOpen()
end

-- Stamps a gesture's start and keeps Now ticking for it. `at` may be a moment still to come.
local function stamp(at: Types.Source<number>, moment: number)
	at(moment)
	motionUntil = math.max(motionUntil, moment + Tune.MOTION_SECONDS)
end

local function setConfirmOpen(isOpen: boolean)
	if state.IsConfirmOpen() == isOpen then return end
	state.IsConfirmOpen(isOpen)
	stamp(state.ConfirmToggledAt, os.clock())
end

function SettingsController.Open()
	if state.IsOpen() then return end
	state.IsOpen(true)
	CameraController.IsMouseFreed = true
	stamp(state.ToggledAt, os.clock())
end

function SettingsController.Close()
	if not state.IsOpen() then return end
	setConfirmOpen(false)
	state.IsOpen(false)
	CameraController.IsMouseFreed = false
	stamp(state.ToggledAt, os.clock())
end

local function applyVolume(row: Types.TVolumeRow)
	local share = row.Value() / SettingsCore.MAX_VOLUME
	for _, group in busesById[row.Id] do
		group.Volume = busLevels[group] * share
	end
end

local function applyToggle(row: Types.TToggleRow)
	-- Drag Fire To Aim is kept and saved here; nothing reads it until there is a touch fire button.
	if row.Id == ESettings.IsCameraShakeReduced then CameraController.ShakeMultiplier = if row.IsOn() then 0 else 1 end
end

-- The hint's flash: a change was just sent to be saved.
local function markSaved(now: number)
	stamp(state.SavedAt, now)
end

local function setVolume(row: Types.TVolumeRow, percent: number)
	row.Value(percent)
	applyVolume(row)
	ClientNetworkSettings.SetVolume.Fire(row.Id, percent)
end

local function setToggle(row: Types.TToggleRow, isOn: boolean)
	row.IsOn(isOn)
	applyToggle(row)
	ClientNetworkSettings.SetToggle.Fire(row.Id, isOn)
end

local actions: Types.TActions = {
	Close = SettingsController.Close,
	DragVolume = function(row: Types.TVolumeRow, percent: number)
		local before = row.Value()
		if not row.IsDragging() then
			row.IsDragging(true)
			draggedFrom[row] = before
		end
		if percent == before then return end
		row.Value(percent)
		applyVolume(row)
		if row.Id ~= ESettings.MenuSoundsVolume then return end
		if percent // Tune.TICK_PERCENT ~= before // Tune.TICK_PERCENT then SoundsCore.PlayClick() end
	end,
	ReleaseVolume = function(row: Types.TVolumeRow)
		row.IsDragging(false)
		-- A knob put back where it was picked up changed nothing.
		if row.Value() == draggedFrom[row] then return end
		ClientNetworkSettings.SetVolume.Fire(row.Id, row.Value())
		markSaved(os.clock())
	end,
	ResetVolume = function(row: Types.TVolumeRow)
		local now = os.clock()
		setVolume(row, row.Default)
		stamp(row.ResetAt, now)
		markSaved(now)
	end,
	SetToggle = function(row: Types.TToggleRow, isOn: boolean)
		local now = os.clock()
		setToggle(row, isOn)
		stamp(row.ChangedAt, now)
		markSaved(now)
	end,
	ResetToggle = function(row: Types.TToggleRow)
		local now = os.clock()
		setToggle(row, row.Default)
		stamp(row.ResetAt, now)
		markSaved(now)
	end,
	AskResetAll = function()
		setConfirmOpen(true)
	end,
	CancelResetAll = function()
		setConfirmOpen(false)
	end,
	-- Every changed row goes home, each a beat after the one above it. One event: the server clears them together.
	ConfirmResetAll = function()
		local now = os.clock()
		local at = now
		for _, row in state.Volumes do
			if row.Value() == row.Default then continue end
			row.Value(row.Default)
			applyVolume(row)
			stamp(row.ResetAt, at)
			at += Tune.RESET_STAGGER
		end
		for _, row in state.Toggles do
			if row.IsOn() == row.Default then continue end
			row.IsOn(row.Default)
			applyToggle(row)
			stamp(row.ResetAt, at)
			at += Tune.RESET_STAGGER
		end

		ClientNetworkSettings.ResetAll.Fire()
		setConfirmOpen(false)
		markSaved(now)
	end,
}

local function updateScale()
	local viewport = Workspace.CurrentCamera.ViewportSize
	state.Scale(math.max(math.min(viewport.Y / Theme.DESIGN_HEIGHT, viewport.X / Tune.DESIGN_WIDTH), 0.01))
end

SettingsController.OnStart = function()
	vide.mount(function()
		-- Drawn only while it is up or still leaving: shut, the screen costs nothing.
		local isDrawn = vide.derive(function(): boolean
			return state.IsOpen() or state.Now() - state.ToggledAt() < Tune.LEAVE_SECONDS
		end)

		return create("ScreenGui")({
			Name = "Settings",
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			DisplayOrder = Tune.DISPLAY_ORDER,
			Enabled = isDrawn,
			-- Scaled from a 1080-tall design: the root is sized 1 / scale so that after its UIScale it fills the
			-- screen.
			create("Frame")({
				Name = "Root",
				BackgroundTransparency = 1,
				Size = function()
					local scale = state.Scale()
					return UDim2.fromScale(1 / scale, 1 / scale)
				end,
				create("UIScale")({ Scale = state.Scale }),
				SettingsUI.Build(state, actions),
			}),
		})
	end, LocalPlayer:WaitForChild("PlayerGui"))

	-- Now is written only while something moves, so a screen at rest, open or shut, redraws nothing.
	RunService.PreRender:Connect(function()
		local now = os.clock()
		if now < motionUntil then state.Now(now) end
	end)

	local camera = Workspace.CurrentCamera
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	updateScale()
end

-- The saved values. A slider under the hand keeps the hand's value: it is sent when it is let go.
ServerNetworkSettings.Sync.On(
	function(music: number, effects: number, menu: number, isShakeReduced: boolean, isDragFire: boolean)
		local volumes = { music, effects, menu }
		local toggles = { isShakeReduced, isDragFire }
		vide.batch(function()
			for index, row in state.Volumes do
				if row.IsDragging() then continue end
				row.Value(volumes[index])
				applyVolume(row)
			end
			for index, row in state.Toggles do
				row.IsOn(toggles[index])
				applyToggle(row)
			end
		end)
	end
)

return Ignis.Register(SettingsController)
