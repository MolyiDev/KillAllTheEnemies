-- Covers the screen when this client is teleported (a pad's party into a run, a run back to the lobby): the loading
-- screen's squares close in over the game, its title deals in over where the player is going, and a still copy of it
-- becomes the teleport GUI that the next place's LoadingScreen.client picks up, so the place change reads as one
-- screen. Every teleport is started by the server, so the cover goes up on Player.OnTeleport.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local TeleportService = game:GetService("TeleportService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local LoadingScreen = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.LoadingScreen)
local EPlaceIds = require(ReplicatedStorage.Types.Enums.EPlaceIds)

local Player = Players.LocalPlayer

local TeleportCoverController = {}

-- LoadingScreen.client's: over every screen the places draw, only the console's over it.
local DISPLAY_ORDER = 50_000

local gui: ScreenGui? = nil
local screen: LoadingScreen.TLoadingScreen? = nil

local function screenGui(name: string): ScreenGui
	local made = Instance.new("ScreenGui")
	made.Name = name
	made.DisplayOrder = DISPLAY_ORDER
	made.IgnoreGuiInset = true
	made.ScreenInsets = Enum.ScreenInsets.None
	made.ResetOnSpawn = false
	made.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	return made
end

-- What the teleport shows if it leaves before the cover is up: the screen's flat base rather than Roblox's default.
local function plainGui(): ScreenGui
	local plain = screenGui("LoadingPlain")
	local base = Instance.new("Frame")
	base.Name = "Base"
	base.Size = UDim2.fromScale(1, 1)
	base.BackgroundColor3 = LoadingScreen.BASE
	base.BorderSizePixel = 0
	base.Parent = plain
	return plain
end

-- Puts the cover up over the game with `words` over the bar, and hands the teleport a still copy once its title is
-- up. A cover already up stays as it is.
function TeleportCoverController.Cover(words: string)
	if screen then return end
	local made = screenGui("TeleportCover")
	made.Parent = Player:WaitForChild("PlayerGui")
	local current = LoadingScreen.new(made, { Mode = "Cover", Text = words })
	gui = made
	screen = current
	task.spawn(function()
		current.WaitReady()
		if screen ~= current then return end
		local snapshot = current.Snapshot()
		if snapshot then TeleportService:SetTeleportGui(snapshot) end
	end)
end

-- A teleport that did not happen hands the game back: the cover leaves the way every loading screen does.
function TeleportCoverController.Uncover()
	local current = screen
	local made = gui
	if not current or not made then return end
	screen = nil
	gui = nil
	TeleportService:SetTeleportGui(plainGui())
	current.Leave(nil, function()
		made:Destroy()
	end)
end

local function wordsFor(placeId: number): string
	return if placeId == EPlaceIds.Lobby then "RETURNING TO THE LOBBY" else "ENTERING THE RUN"
end

TeleportCoverController.OnStart = function()
	TeleportService:SetTeleportGui(plainGui())
	Player.OnTeleport:Connect(function(teleportState: Enum.TeleportState, placeId: number)
		if teleportState == Enum.TeleportState.RequestedFromServer or teleportState == Enum.TeleportState.Started then
			TeleportCoverController.Cover(wordsFor(placeId))
		elseif teleportState == Enum.TeleportState.Failed then
			TeleportCoverController.Uncover()
		end
	end)
end

return Ignis.Register(TeleportCoverController)
