local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Fluid = require(ReplicatedStorage.Packages.Fluid)
local CursorUI = require(StarterPlayer.StarterPlayerScripts.Client.UI.CursorUI)
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local HapticsController = require(script.Parent.Parent.Parent.GlobalClient.Controllers.HapticsController)
local InputTypeController = require(script.Parent.Parent.Parent.GlobalClient.Controllers.InputTypeController)
local SettingsController = require(script.Parent.Parent.Parent.GlobalClient.Controllers.SettingsController)
local KeybindsCore = require(ReplicatedStorage.GlobalShared.Core.KeybindsCore)
local Network = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Network)
local EKeybinds = require(ReplicatedStorage.Types.Enums.Settings.EKeybinds)
local ESettings = require(ReplicatedStorage.Types.Enums.Settings.ESettings)
local ESettingsGeneral = require(ReplicatedStorage.Types.Enums.Settings.ESettingsGeneral)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)
local TCharacter = require(ReplicatedStorage.Types.TCharacter)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Camera = Workspace.CurrentCamera
Camera.FieldOfView = 90

local asin = math.asin
local atan2 = math.atan2
local clamp = math.clamp
local cos = math.cos
local floor = math.floor
local rad = math.rad

local INV_PI = 1 / math.pi
local INV_HALF_PI = 2 / math.pi
local ClientPlayerSync = Network.Client.PlayerSync
local cameraSyncElapsed = 0
local CAMERA_SYNC_INTERVAL = 1 / 20 -- seconds; independent of display refresh rate

local CameraController = {}
CameraController.MouseActive = true
CameraController.AutoRotate = true
CameraController.CursorActive = true
CameraController.CameraLocked = false
-- Global scalar on every active shake's magnitude (e.g. dial all shakes down).
CameraController.ShakeMultiplier = 1
local UI: CursorUI.CursorUIReturn

Fluid.mount(function()
	UI = CursorUI()
	return UI.UI
end, PlayerGui)

function CameraController.HideMouse()
	InputTypeController.SetMouseSuppressed(true)
	CameraController.MouseActive = false
end

function CameraController.ShowMouse()
	InputTypeController.SetMouseSuppressed(false)
	CameraController.MouseActive = true
end

function CameraController.ToggleMouse()
	if CameraController.MouseActive then
		CameraController.HideMouse()
	else
		CameraController.ShowMouse()
	end
end

function CameraController.ShowCursor()
	UI.Appear()
	CameraController.CursorActive = true
end

function CameraController.HideCursor()
	UI.Disappear()
	CameraController.CursorActive = false
end

function CameraController.ToggleCursor()
	if CameraController.CursorActive then
		CameraController.HideCursor()
	else
		CameraController.ShowCursor()
	end
end

function CameraController.LockCamera()
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	CameraController.CameraLocked = true
end

function CameraController.UnlockCamera()
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	CameraController.CameraLocked = false
end

function CameraController.ToggleCameraLock()
	if CameraController.CameraLocked then
		CameraController.UnlockCamera()
	else
		CameraController.LockCamera()
	end
end

-- Layered Perlin-noise camera shake. Each Shake() call is an independent impulse
-- that fades over its own duration; computeShakeOffset sums the live ones into a
-- single local-space CFrame offset applied to the camera each PreRender.
type ShakeInstance = {
	Magnitude: number,
	Roughness: number,
	Duration: number,
	FadeOut: number,
	PosInf: Vector3,
	RotInf: Vector3,
	StartTime: number,
	Seed: number,
}

local SHAKE_DEFAULT_POS = Vector3.new(0.5, 0.5, 0.5)
local SHAKE_DEFAULT_ROT = Vector3.new(0.05, 0.05, 0.05)

local accumulatedTime = 0
local activeShakes: { ShakeInstance } = {}

local screenShakeEnabled = SettingsController.GetBool(ESettings.General, ESettingsGeneral.ScreenShake)
SettingsController.OnBoolChanged:Connect(function(category: number, key: string, value: boolean)
	if category ~= ESettings.General or key ~= ESettingsGeneral.ScreenShake then return end
	screenShakeEnabled = value
	-- Drop any in-flight shakes so toggling off stops the camera mid-shake.
	if not value then table.clear(activeShakes) end
end)

local function computeShakeOffset(): CFrame
	local now = accumulatedTime
	local totalPos = Vector3.zero
	local totalRot = Vector3.zero
	local multiplier = CameraController.ShakeMultiplier

	for i = #activeShakes, 1, -1 do
		local shake = activeShakes[i]
		local elapsed = now - shake.StartTime

		if elapsed >= shake.Duration then
			table.remove(activeShakes, i)
			continue
		end

		local alpha = 1 - (elapsed / shake.Duration)
		local currentMag = shake.Magnitude * alpha * multiplier

		local freq = 4 / math.max(shake.Roughness, 0.01)
		local t = now * freq
		local seed = shake.Seed
		local rotInf = shake.RotInf
		local posInf = shake.PosInf

		local rX = math.noise(t, seed, 1) * 2
		local rY = math.noise(t, seed, 2) * 2
		local rZ = math.noise(t, seed, 3) * 2

		local pX = math.noise(t, seed, 4) * 2
		local pY = math.noise(t, seed, 5) * 2
		local pZ = math.noise(t, seed, 6) * 2

		totalRot += Vector3.new(rX, rY, rZ) * rotInf * currentMag
		totalPos += Vector3.new(pX, pY, pZ) * posInf * currentMag
	end

	return CFrame.new(totalPos) * CFrame.Angles(rad(totalRot.X), rad(totalRot.Y), rad(totalRot.Z))
end

-- Kicks off one shake impulse. Drives both the visual shake (gated by the Screen
-- Shake setting) and a controller / phone rumble (gated by the Vibration setting),
-- so a single call gives whichever feedback the player has turned on.
function CameraController.Shake(
	magnitude: number,
	roughness: number,
	duration: number,
	positionInfluence: Vector3?,
	rotationInfluence: Vector3?,
	fadeOut: number?
)
	HapticsController.Vibrate(clamp(magnitude / 10, 0.1, 1), if duration < 0.35 then duration else 0.35)

	if not screenShakeEnabled then return end
	activeShakes[#activeShakes + 1] = {
		Magnitude = magnitude,
		Roughness = roughness,
		Duration = duration,
		FadeOut = fadeOut or 0,
		PosInf = positionInfluence or SHAKE_DEFAULT_POS,
		RotInf = rotationInfluence or SHAKE_DEFAULT_ROT,
		StartTime = accumulatedTime,
		Seed = math.random() * 1000,
	}
end

local connection: RBXScriptConnection

CameraController.OnSelfCharacterAdded = function(character)
	character.Humanoid.AutoRotate = false
	CameraController.HideMouse()
	CameraController.ShowCursor()
	CameraController.LockCamera()

	connection = RunService.PreRender:Connect(function(dt: number)
		if not CameraController.AutoRotate then return end
		debug.profilebegin("CameraController")
		accumulatedTime += dt

		local baseCF = Camera.CFrame * CFrame.new(Vector3.new(3, 0.5, 0))
		-- Shake rides on top as a local-space offset. The camera sync below reads
		-- baseCF (pre-shake) so the replicated aim / FOV cull doesn't jitter.
		if #activeShakes > 0 then
			Camera.CFrame = baseCF * computeShakeOffset()
		else
			Camera.CFrame = baseCF
		end

		cameraSyncElapsed += dt
		if cameraSyncElapsed >= CAMERA_SYNC_INTERVAL then
			cameraSyncElapsed %= CAMERA_SYNC_INTERVAL
			local look = baseCF.LookVector
			local camPos = baseCF.Position
			local pitch = asin(clamp(-look.Y, -1, 1))
			local yaw = atan2(look.X, -look.Z)
			local fovThreshold = cos(rad(Camera.DiagonalFieldOfView) / 2)
			ClientPlayerSync.CameraSync.Fire(
				camPos.X,
				camPos.Y,
				camPos.Z,
				floor(yaw * INV_PI * 32767 + 0.5),
				floor(pitch * INV_HALF_PI * 32767 + 0.5),
				floor(fovThreshold * 65535 + 0.5)
			)
		end
		debug.profileend()
	end)
end :: TCharacterEvents.OnCharacterAdded

CameraController.OnSelfCharacterRemoving = function()
	connection:Disconnect()
end :: TCharacterEvents.OnCharacterRemoving

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if not KeybindsCore.IsBound(InputTypeController.GetPlatform(), EKeybinds.UnlockMouse, input.KeyCode) then return end

	CameraController.ToggleMouse()
	CameraController.ToggleCameraLock()
	CameraController.ToggleCursor()
end)

local function freecamEnabled()
	local character = Player.Character :: TCharacter.TCharacter
	if not character then return end

	CameraController.AutoRotate = false
	task.wait()

	CameraController.LockCamera()
end

local function freecamDisabled()
	local character = Player.Character :: TCharacter.TCharacter
	if not character then return end

	CameraController.AutoRotate = true
end

local Freecam = PlayerGui:WaitForChild("Freecam", 5)
if Freecam then
	local FreecamScript = Freecam:WaitForChild("FreecamScript", 5) :: LocalScript

	if FreecamScript then
		FreecamScript.AttributeChanged:Connect(function(attribute)
			if attribute ~= "FreecamEnabled" then return end
			local isFreecamEnabled = Freecam:GetAttribute(attribute)

			if isFreecamEnabled then
				freecamEnabled()
			else
				freecamDisabled()
			end
		end)
	end
end

return Ignis.Register(CameraController)
