-- The loading screen on joining either place (GlobalClient.UI.LoadingScreen draws it). It covers Roblox's default
-- screen at once, fills the bar with the icons and the UI's sounds (LOADING), then creeps while the place gets ready
-- (LoadingGate: the lobby's profile, a run's start), pays off and lifts off the world. A teleport in carries the still
-- copy of the cover the last place drew (TeleportCoverController): it goes up first and the screen opens under it as
-- an arrival, so the place change shows one unbroken screen.
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local TeleportService = game:GetService("TeleportService")

local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

-- LoadingScreen's Backdrop.BASE: this cover goes up before any module can be required.
local BASE = Color3.fromRGB(22, 16, 44)
local SKIP_AFTER_SECONDS = 2
-- The assets fill the bar this far, within this budget; the place's readiness fills the rest.
local ASSETS_SHARE = 0.65
local ASSETS_SECONDS = 15
-- Past this, the screen pays off and lifts whatever the place says.
local READY_CAP_SECONDS = 60

-- The first cover, made by hand: vide and the UI's modules have not replicated yet. Up before the default screen goes,
-- so the join shows no gap; the real screen draws over it in the same colour and then it goes.
local gui = Instance.new("ScreenGui")
gui.Name = "Loading"
-- Over every screen the places draw; only the console's goes over it.
gui.DisplayOrder = 50_000
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.None
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local firstCover = Instance.new("Frame")
firstCover.Name = "FirstCover"
firstCover.Size = UDim2.fromScale(1, 1)
firstCover.BackgroundColor3 = BASE
firstCover.BorderSizePixel = 0
firstCover.Parent = gui
gui.Parent = PlayerGui
local arriving = TeleportService:GetArrivingTeleportGui()
if arriving then arriving.Parent = PlayerGui end
ReplicatedFirst:RemoveDefaultLoadingScreen()

if not game:IsLoaded() then game.Loaded:Wait() end

local UI = StarterPlayer:WaitForChild("StarterPlayerScripts"):WaitForChild("GlobalClient"):WaitForChild("UI")
local Icons = require(UI:WaitForChild("Icons"))
local LoadingGate = require(UI:WaitForChild("LoadingGate"))
local LoadingScreen = require(UI:WaitForChild("LoadingScreen"))
local preloadAssets = require(UI.Parent:WaitForChild("Utils"):WaitForChild("preloadAssets"))

-- Only a cover's copy is an arrival; the plain base a teleport carries when it left first is the first cover's colour.
local isArrival = arriving ~= nil and arriving.Name == LoadingScreen.SNAPSHOT_NAME
local ok, screen = pcall(LoadingScreen.new, gui, {
	Mode = if isArrival then "Arrive" else "Join",
	Arriving = if isArrival then arriving else nil,
})
if not ok then
	-- A screen that cannot be drawn must not hold the world under its cover.
	warn(`[LoadingScreen] {screen}`)
	gui:Destroy()
	if arriving then arriving:Destroy() end
	LoadingGate.MarkLifted()
	return
end
firstCover:Destroy()
if arriving and not isArrival then arriving:Destroy() end
screen.SetPhase("LOADING", 0, ASSETS_SHARE)

-- Every image the UI draws from (Icons' atlases, the panel texture and the showcase art), and the UI's sounds and the
-- music.
local assets: { Instance } = {}
local seen: { [string]: boolean } = {}

local function addImages(value: any)
	if type(value) == "table" then
		for _, inner in value do
			addImages(inner)
		end
		return
	end
	if type(value) ~= "string" or string.sub(value, 1, 13) ~= "rbxassetid://" or seen[value] then return end
	seen[value] = true
	-- On a label, never the bare id (preloadAssets says why).
	local label = Instance.new("ImageLabel")
	label.Image = value
	table.insert(assets, label)
end

addImages(Icons)
local sounds = ReplicatedStorage:WaitForChild("Sounds")
for _, name in { "UI", "Music" } do
	local folder = sounds:FindFirstChild(name)
	if not folder then continue end
	for _, sound in folder:GetDescendants() do
		if sound:IsA("Sound") then table.insert(assets, sound) end
	end
end

local function leave()
	screen.Leave(LoadingGate.MarkLifted, function()
		gui:Destroy()
	end)
end

task.delay(SKIP_AFTER_SECONDS, function()
	if screen.IsLeaving() then return end
	screen.ShowSkip(leave)
end)

local completed, failedCount = preloadAssets(assets, ASSETS_SECONDS, screen.IsLeaving, screen.SetProgress)
if not completed and not screen.IsLeaving() then warn("[LoadingScreen] Preload ran out of time; continuing") end
if failedCount > 0 then warn(`[LoadingScreen] {failedCount} asset requests failed`) end
if screen.IsLeaving() then return end
LoadingGate.MarkLoaded()

LoadingGate.OnWaiting(function(text: string)
	if not LoadingGate.IsReady then screen.SetPhase(text, ASSETS_SHARE, 1) end
end)
local waited = 0
while not LoadingGate.IsReady and not screen.IsLeaving() and waited < READY_CAP_SECONDS do
	waited += task.wait()
end
if screen.IsLeaving() then return end
if not LoadingGate.IsReady then warn("[LoadingScreen] The place never said it was ready; lifting anyway") end

screen.Complete()
leave()
