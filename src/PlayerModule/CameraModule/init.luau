--!strict
--[[
	CameraModule - Manages camera controller, occlusion, and transparency.
	Cleaned up: removed VR, VehicleCamera, InvisiCam, LegacyCamera, OrbitalCamera.
--]]

local CameraModule = {}
CameraModule.__index = CameraModule

local PLAYER_CAMERA_PROPERTIES = {
	"CameraMinZoomDistance",
	"CameraMaxZoomDistance",
	"CameraMode",
	"DevCameraOcclusionMode",
	"DevComputerCameraMode",
	"DevTouchCameraMode",
	"DevComputerMovementMode",
	"DevTouchMovementMode",
	"DevEnableMouseLock",
}

local USER_GAME_SETTINGS_PROPERTIES = {
	"ComputerCameraMovementMode",
	"ComputerMovementMode",
	"ControlMode",
	"GamepadCameraSensitivity",
	"MouseSensitivity",
	"RotationType",
	"TouchCameraMovementMode",
	"TouchMovementMode",
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local UserGameSettings = UserSettings():GetService("UserGameSettings")

local CommonUtils = script.Parent:WaitForChild("CommonUtils")
local ConnectionUtil = require(CommonUtils:WaitForChild("ConnectionUtil"))

local CameraUtils = require(script:WaitForChild("CameraUtils"))
local CameraInput = require(script:WaitForChild("CameraInput"))

local ClassicCamera = require(script:WaitForChild("ClassicCamera"))
local Poppercam = require(script:WaitForChild("PopperCam"))
local TransparencyController = require(script:WaitForChild("TransparencyController"))
local MouseLockController = require(script:WaitForChild("MouseLockController"))

local instantiatedCameraControllers = {}
local instantiatedOcclusionModules = {}

if not Players.LocalPlayer then return {} end
assert(Players.LocalPlayer, "Strict typing check")

do
	local PlayerScripts: PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts") :: PlayerScripts
	PlayerScripts:RegisterTouchCameraMovementMode(Enum.TouchCameraMovementMode.Default)
	PlayerScripts:RegisterTouchCameraMovementMode(Enum.TouchCameraMovementMode.Follow)
	PlayerScripts:RegisterTouchCameraMovementMode(Enum.TouchCameraMovementMode.Classic)
	PlayerScripts:RegisterComputerCameraMovementMode(Enum.ComputerCameraMovementMode.Default)
	PlayerScripts:RegisterComputerCameraMovementMode(Enum.ComputerCameraMovementMode.Follow)
	PlayerScripts:RegisterComputerCameraMovementMode(Enum.ComputerCameraMovementMode.Classic)
	PlayerScripts:RegisterComputerCameraMovementMode(Enum.ComputerCameraMovementMode.CameraToggle)
end

type Generic = any
type GenericOptional = any?

type CameraModuleClass = {
	__index: CameraModuleClass,
	new: () -> CameraModule,
	ActivateCameraController: (self: CameraModule) -> (),
	ActivateOcclusionModule: (self: CameraModule, occlusionMode: Enum.DevCameraOcclusionMode) -> (),
	GetCameraMovementModeFromSettings: (
		self: CameraModule
	) -> Enum.ComputerCameraMovementMode | Enum.DevComputerCameraMovementMode,
	OnPreferredInputChanged: (self: CameraModule) -> (),
	OnCameraSubjectChanged: (self: CameraModule) -> (),
	OnCameraTypeChanged: (self: CameraModule, newCameraType: Enum.CameraType) -> (),
	OnCharacterAdded: (self: CameraModule, character: Model, player: Player) -> (),
	OnCharacterRemoving: (self: CameraModule, character: Model, player: Player) -> (),
	OnCurrentCameraChanged: (self: CameraModule) -> (),
	OnLocalPlayerCameraPropertyChanged: (self: CameraModule, propertyName: string) -> (),
	OnPlayerAdded: (self: CameraModule, player: Player) -> (),
	OnPlayerRemoving: (self: CameraModule, player: Player) -> (),
	OnMouseLockToggled: (self: CameraModule) -> (),
	OnUserGameSettingsPropertyChanged: (self: CameraModule, propertyName: string) -> (),
	Update: (self: CameraModule, dt: number) -> (),
}

export type CameraModule = typeof(setmetatable(
	{} :: {
		activeCameraController: GenericOptional,
		activeMouseLockController: GenericOptional,
		activeOcclusionModule: GenericOptional,
		activeTransparencyController: Generic,
		cameraSubjectChangedConn: RBXScriptConnection?,
		cameraTypeChangedConn: RBXScriptConnection?,
		connectionUtil: ConnectionUtil.ConnectionUtil?,
		currentComputerCameraMovementMode: Enum.ComputerCameraMovementMode? | Enum.DevComputerCameraMovementMode?,
		occlusionMode: Enum.DevCameraOcclusionMode?,
	},
	{} :: CameraModuleClass
))

function CameraModule.new()
	local self: CameraModule = setmetatable({
		activeTransparencyController = TransparencyController.new(),
		connectionUtil = ConnectionUtil.new(),
	}, CameraModule)

	self.activeCameraController = nil
	self.activeOcclusionModule = nil
	self.activeMouseLockController = nil
	self.currentComputerCameraMovementMode = nil
	self.cameraSubjectChangedConn = nil
	self.cameraTypeChangedConn = nil

	for _, player in pairs(Players:GetPlayers()) do
		self:OnPlayerAdded(player)
	end

	Players.PlayerAdded:Connect(function(player)
		self:OnPlayerAdded(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:OnPlayerRemoving(player)
	end)

	self.activeTransparencyController:Enable(true)

	self.activeMouseLockController = MouseLockController.new()
	assert(self.activeMouseLockController, "Strict typing check")

	local toggleEvent = self.activeMouseLockController:GetBindableToggleEvent()
	if toggleEvent then toggleEvent:Connect(function()
		self:OnMouseLockToggled()
	end) end

	self:ActivateCameraController()
	self:ActivateOcclusionModule(Players.LocalPlayer.DevCameraOcclusionMode)
	self:OnCurrentCameraChanged()
	RunService:BindToRenderStep("cameraRenderUpdate", Enum.RenderPriority.Camera.Value, function(dt)
		self:Update(dt)
	end)

	for _, propertyName in pairs(PLAYER_CAMERA_PROPERTIES) do
		Players.LocalPlayer:GetPropertyChangedSignal(propertyName):Connect(function()
			self:OnLocalPlayerCameraPropertyChanged(propertyName)
		end)
	end

	for _, propertyName in pairs(USER_GAME_SETTINGS_PROPERTIES) do
		UserGameSettings:GetPropertyChangedSignal(propertyName):Connect(function()
			self:OnUserGameSettingsPropertyChanged(propertyName)
		end)
	end
	game.Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		self:OnCurrentCameraChanged()
	end)
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
		self:OnPreferredInputChanged()
	end)

	return self
end

function CameraModule:GetCameraMovementModeFromSettings(): Enum.ComputerCameraMovementMode | Enum.DevComputerCameraMovementMode
	local cameraMode = Players.LocalPlayer.CameraMode

	if cameraMode == Enum.CameraMode.LockFirstPerson then
		return CameraUtils.ConvertCameraModeEnumToStandard(Enum.ComputerCameraMovementMode.Classic)
	end

	local devMode, userMode
	if UserInputService.PreferredInput == Enum.PreferredInput.Touch then
		devMode = CameraUtils.ConvertCameraModeEnumToStandard(Players.LocalPlayer.DevTouchCameraMode)
		userMode = CameraUtils.ConvertCameraModeEnumToStandard(UserGameSettings.TouchCameraMovementMode)
	else
		devMode = CameraUtils.ConvertCameraModeEnumToStandard(Players.LocalPlayer.DevComputerCameraMode)
		userMode = CameraUtils.ConvertCameraModeEnumToStandard(UserGameSettings.ComputerCameraMovementMode)
	end

	if devMode == Enum.DevComputerCameraMovementMode.UserChoice then return userMode end

	return devMode
end

function CameraModule:ActivateOcclusionModule(occlusionMode: Enum.DevCameraOcclusionMode)
	-- Only Zoom (Poppercam) is supported
	if occlusionMode ~= Enum.DevCameraOcclusionMode.Zoom then occlusionMode = Enum.DevCameraOcclusionMode.Zoom end

	self.occlusionMode = occlusionMode

	if self.activeOcclusionModule and self.activeOcclusionModule:GetOcclusionMode() == occlusionMode then
		if not self.activeOcclusionModule:GetEnabled() then self.activeOcclusionModule:Enable(true) end
		return
	end

	local prevOcclusionModule = self.activeOcclusionModule

	self.activeOcclusionModule = instantiatedOcclusionModules[Poppercam]

	if not self.activeOcclusionModule then
		self.activeOcclusionModule = Poppercam.new()
		if self.activeOcclusionModule then instantiatedOcclusionModules[Poppercam] = self.activeOcclusionModule end
	end

	if self.activeOcclusionModule then
		if prevOcclusionModule and prevOcclusionModule ~= self.activeOcclusionModule then
			prevOcclusionModule:Enable(false)
		end

		for _, player in pairs(Players:GetPlayers()) do
			if player and player.Character then self.activeOcclusionModule:CharacterAdded(player.Character, player) end
		end
		self.activeOcclusionModule:OnCameraSubjectChanged((game.Workspace.CurrentCamera :: Camera).CameraSubject)
		self.activeOcclusionModule:Enable(true)
	end
end

function CameraModule:ActivateCameraController()
	local legacyCameraType = (workspace.CurrentCamera :: Camera).CameraType

	if legacyCameraType == Enum.CameraType.Scriptable then
		if self.activeCameraController then
			self.activeCameraController:Enable(false)
			self.activeCameraController = nil
		end
		return
	end

	local cameraMovementMode = self:GetCameraMovementModeFromSettings()
	local newCameraCreator = ClassicCamera

	local newCameraController
	if not instantiatedCameraControllers[newCameraCreator] then
		newCameraController = newCameraCreator.new()
		instantiatedCameraControllers[newCameraCreator] = newCameraController
	else
		newCameraController = instantiatedCameraControllers[newCameraCreator]
		if newCameraController.Reset and self.activeCameraController ~= newCameraController then
			newCameraController:Reset()
		end
	end

	if self.activeCameraController then
		if self.activeCameraController ~= newCameraController then
			self.activeCameraController:Enable(false)
			self.activeCameraController = newCameraController
			self.activeCameraController:Enable(true)
		elseif not self.activeCameraController:GetEnabled() then
			self.activeCameraController:Enable(true)
		end
	elseif newCameraController ~= nil then
		self.activeCameraController = newCameraController
		assert(self.activeCameraController, "Strict typing check")
		self.activeCameraController:Enable(true)
	end

	if self.activeCameraController then
		self.activeCameraController:SetCameraMovementMode(cameraMovementMode)
		self.activeCameraController:SetCameraType(legacyCameraType)
	end
end

function CameraModule:OnCameraSubjectChanged()
	local camera = workspace.CurrentCamera
	local cameraSubject = if camera then camera.CameraSubject else nil

	if self.activeTransparencyController then self.activeTransparencyController:SetSubject(cameraSubject) end
	if self.activeOcclusionModule then self.activeOcclusionModule:OnCameraSubjectChanged(cameraSubject) end

	self:ActivateCameraController()
end

function CameraModule:OnCameraTypeChanged(newCameraType: Enum.CameraType)
	if newCameraType == Enum.CameraType.Scriptable then
		if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then CameraUtils.restoreMouseBehavior() end
	end
	self:ActivateCameraController()
end

function CameraModule:OnCurrentCameraChanged()
	local currentCamera = game.Workspace.CurrentCamera
	if not currentCamera then return end

	if self.cameraSubjectChangedConn then self.cameraSubjectChangedConn:Disconnect() end
	if self.cameraTypeChangedConn then self.cameraTypeChangedConn:Disconnect() end

	self.cameraSubjectChangedConn = currentCamera:GetPropertyChangedSignal("CameraSubject"):Connect(function()
		self:OnCameraSubjectChanged()
	end)

	self.cameraTypeChangedConn = currentCamera:GetPropertyChangedSignal("CameraType"):Connect(function()
		self:OnCameraTypeChanged(currentCamera.CameraType)
	end)

	self:OnCameraSubjectChanged()
	self:OnCameraTypeChanged(currentCamera.CameraType)
end

function CameraModule:OnLocalPlayerCameraPropertyChanged(propertyName: string)
	if propertyName == "CameraMode" then
		if Players.LocalPlayer.CameraMode == Enum.CameraMode.LockFirstPerson then
			if not self.activeCameraController or self.activeCameraController:GetModuleName() ~= "ClassicCamera" then
				self:ActivateCameraController()
			end
			if self.activeCameraController then self.activeCameraController:UpdateForDistancePropertyChange() end
		elseif Players.LocalPlayer.CameraMode == Enum.CameraMode.Classic then
			self:ActivateCameraController()
		end
	elseif propertyName == "DevComputerCameraMode" or propertyName == "DevTouchCameraMode" then
		self:ActivateCameraController()
	elseif propertyName == "DevCameraOcclusionMode" then
		self:ActivateOcclusionModule(Players.LocalPlayer.DevCameraOcclusionMode)
	elseif propertyName == "CameraMinZoomDistance" or propertyName == "CameraMaxZoomDistance" then
		if self.activeCameraController then self.activeCameraController:UpdateForDistancePropertyChange() end
	end
end

function CameraModule:OnUserGameSettingsPropertyChanged(propertyName: string)
	if propertyName == "ComputerCameraMovementMode" or propertyName == "TouchCameraMovementMode" then
		self:ActivateCameraController()
	end
end

function CameraModule:OnPreferredInputChanged()
	self:ActivateCameraController()
end

function CameraModule:Update(dt)
	if self.activeCameraController then
		self.activeCameraController:UpdateMouseBehavior()

		local newCameraCFrame, newCameraFocus = self.activeCameraController:Update(dt)

		if self.activeOcclusionModule then
			newCameraCFrame, newCameraFocus = self.activeOcclusionModule:Update(dt, newCameraCFrame, newCameraFocus)
		end

		local currentCamera = game.Workspace.CurrentCamera :: Camera
		currentCamera.CFrame = newCameraCFrame
		currentCamera.Focus = newCameraFocus

		if self.activeTransparencyController then self.activeTransparencyController:Update(dt) end
		if CameraInput.getInputEnabled() then CameraInput.resetInputForFrameEnd() end
	end
end

function CameraModule:OnCharacterAdded(char: Model, player: Player)
	if self.activeOcclusionModule then self.activeOcclusionModule:CharacterAdded(char, player) end
end

function CameraModule:OnCharacterRemoving(char, player)
	if self.activeOcclusionModule then self.activeOcclusionModule:CharacterRemoving(char, player) end
end

function CameraModule:OnPlayerAdded(player: Player)
	if self.connectionUtil then
		self.connectionUtil:trackConnection(
			`{player.UserId}CharacterAdded`,
			player.CharacterAdded:Connect(function(char)
				self:OnCharacterAdded(char, player)
			end)
		)
		self.connectionUtil:trackConnection(
			`{player.UserId}CharacterRemoving`,
			player.CharacterRemoving:Connect(function(char)
				self:OnCharacterRemoving(char, player)
			end)
		)
	end
end

function CameraModule:OnPlayerRemoving(player: Player)
	if self.connectionUtil then
		self.connectionUtil:disconnect(`{player.UserId}CharacterAdded`)
		self.connectionUtil:disconnect(`{player.UserId}CharacterRemoving`)
	end
end

function CameraModule:OnMouseLockToggled()
	if self.activeMouseLockController then
		local mouseLocked = self.activeMouseLockController:GetIsMouseLocked()
		local mouseLockOffset = self.activeMouseLockController:GetMouseLockOffset()
		if self.activeCameraController then
			self.activeCameraController:SetIsMouseLocked(mouseLocked)
			self.activeCameraController:SetMouseLockOffset(mouseLockOffset)
		end
	end
end

CameraModule.new()

return {}
