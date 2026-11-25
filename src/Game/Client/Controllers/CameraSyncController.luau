-- Tells the server where this client's camera is, for its cull of the enemy position stream (AOIService). A fixed
-- 20 Hz off elapsed time, not every N frames, which ran at 80 Hz on a 240 Hz client for nothing. It reports the camera
-- as framed (CameraController.AimCFrame), not as rendered: shake and recoil would jitter the server's cull.
-- The point sent is pulled back along the look to AOI_MIN_BEHIND behind the head, which keeps it on the aim ray.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Network = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Network)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)
-- Through PlayerScripts, the copy that runs (see HudController).
local CameraController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.CameraController)

local ClientPlayerSync = Network.Client.PlayerSync

local CAMERA_SYNC_INTERVAL = 1 / 20
local INV_PI = 1 / math.pi
local INV_HALF_PI = 2 / math.pi
-- In first person the cone's apex is the head, so a body beside or just behind the player is outside it until it is
-- already on screen, and then waits a round trip and a subscription tick to be drawn. From this far back the cone
-- holds the player and what stands round them, as a third-person camera does; a camera already further back is left alone.
local AOI_MIN_BEHIND = 12

local CameraSyncController = {}

local elapsed = 0
local selfHead: BasePart? = nil

CameraSyncController.OnStart = function()
	RunService.PreRender:Connect(function(dt: number)
		elapsed += dt
		if elapsed < CAMERA_SYNC_INTERVAL then return end
		elapsed %= CAMERA_SYNC_INTERVAL
		local camera = Workspace.CurrentCamera
		if not camera then return end
		local cameraCFrame = CameraController.AimCFrame
		local look = cameraCFrame.LookVector
		local position = cameraCFrame.Position
		if selfHead then
			local behind = (selfHead.Position - position):Dot(look)
			if behind < AOI_MIN_BEHIND then
				position -= look * (AOI_MIN_BEHIND - behind)
			end
		end
		local pitch = math.asin(math.clamp(-look.Y, -1, 1))
		local yaw = math.atan2(look.X, -look.Z)
		local threshold = math.cos(math.rad(camera.DiagonalFieldOfView) / 2)
		ClientPlayerSync.CameraSync.Fire(
			position.X,
			position.Y,
			position.Z,
			math.floor(yaw * INV_PI * 32767 + 0.5),
			math.floor(pitch * INV_HALF_PI * 32767 + 0.5),
			math.floor(threshold * 65535 + 0.5)
		)
	end)
end

CameraSyncController.OnSelfCharacterAdded = function(character)
	selfHead = character.Head
end :: TCharacterEvents.OnCharacterAdded

CameraSyncController.OnSelfCharacterRemoving = function()
	selfHead = nil
end :: TCharacterEvents.OnCharacterRemoving

return Ignis.Register(CameraSyncController)
