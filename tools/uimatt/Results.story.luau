-- The results with a fixed state, for rur to render beside the designer's Round Results render
-- (Assets/ui/UIMatt/renders/19_Round_Results.png, the same renderer and background):
--   rur-native render --headless --offline --rojo <game.project.json without its comments> \
--     --story tools/uimatt/Results.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 1.5 \
--     --controls '{"Moment": "Rest"}' --dir <out>
-- Moment: Rest (everything landed, his numbers), Open (the screen going up, 0.2 s in), Doubled (a doubling bought on
-- a screen at rest), Voted (the local player's PLAY AGAIN vote), Last (the countdown's last seconds), Empty (a run
-- that earned nothing, no record), for `rur-native sequence`.
-- rur reads the project file as plain JSON, so strip its comments into a copy first. The HUD's group-owned images 403
-- offline, so they are swapped for the local PNGs they were made from.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)

local AvatarPose = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.AvatarPose)
local Results = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.HudController.Results)

local source = vide.source
local create = vide.create

local ROOT = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/hud/"
local SWAPS = {
	[Icons.Pictures.Gem.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures1.png",
	[Icons.Pictures.Potion.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures2.png",
	[Icons.Pictures.Pointer.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures3.png",
	[Icons.Pictures.UpArrow.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures4.png",
	[Icons.Pictures.SurvivorVest.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures5.png",
	[Icons.IMAGE] = ROOT .. "Icons.png",
	[Icons.PANEL_TEXTURE] = ROOT .. "PanelTexture.png",
}
local MOMENT_AT = 0.2
-- A clock at which nothing that repeats (the heart, the lights asking) is in the picture.
local REST_CLOCK = 1

local function swapImages(root: Instance)
	local function swap(instance: Instance)
		if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
			local path = SWAPS[instance.Image]
			if path then instance.Image = path end
		end
	end

	for _, instance in root:GetDescendants() do
		swap(instance)
	end
	root.DescendantAdded:Connect(swap)
end

-- A stand-in for the player's avatar: an R6 body of plain blocks facing down -Z, a visor on its face so the front
-- shows, with its arms folded as the HUD folds the real one.
local function avatar(): Model
	local model = Instance.new("Model")
	local function block(name: string, size: Vector3, at: Vector3, color: Color3): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Position = at
		part.Color = color
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = true
		part.Parent = model
		return part
	end

	local skin, shirt, trousers =
		Color3.fromRGB(255, 214, 120), Color3.fromRGB(60, 200, 110), Color3.fromRGB(60, 110, 255)
	block("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), shirt).Transparency = 1
	block("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), shirt)
	block("Right Arm", Vector3.new(1, 2, 1), Vector3.new(1.5, 3, 0), skin)
	block("Left Arm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 3, 0), skin)
	block("Right Leg", Vector3.new(1, 2, 1), Vector3.new(0.5, 1, 0), trousers)
	block("Left Leg", Vector3.new(1, 2, 1), Vector3.new(-0.5, 1, 0), trousers)
	local head = block("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 4.6, 0), skin)
	local visor = Instance.new("Accessory")
	local handle = block("Handle", Vector3.new(0.9, 0.3, 0.2), Vector3.new(0, 4.75, -0.6), Color3.fromRGB(30, 30, 50))
	local weld = Instance.new("Weld")
	weld.Part0 = handle
	weld.Part1 = head
	weld.Parent = handle
	handle.Parent = visor
	visor.Parent = model

	AvatarPose.Apply(model, AvatarPose.CROSSED)
	return model
end

local function noop() end

local ACTIONS = {
	Revive = noop,
	PlayAgain = noop,
	LeaveToLobby = noop,
	WatchAd = noop,
	DoubleGems = noop,
}

return {
	vide = vide,
	controls = {
		Moment = { "Rest", "Open", "Doubled", "Voted", "Last", "Empty" },
	},
	story = function(props)
		local moment = props.controls.Moment()
		local startedAt = os.clock()
		local at = startedAt + MOMENT_AT
		local isEmpty = moment == "Empty"
		-- His numbers: wave 21, 2,013 kills, 13:40, 7.6K Gems of 16,365, 0/2 voted, 20 seconds.
		local results = {
			IsOpen = source(true),
			ToggledAt = source(if moment == "Open" or isEmpty then at else -math.huge),
			Clock = source(if moment == "Rest" then math.huge else os.clock()),
			Beat = source(if moment == "Rest" then REST_CLOCK else os.clock()),
			Wave = source(if isEmpty then 1 else 21),
			IsNewBest = source(not isEmpty),
			SquadKills = source(if isEmpty then 7 else 2013),
			Seconds = source(if isEmpty then 41 else 820),
			Gems = source(if isEmpty then 0 else 7550),
			TotalGems = source(if isEmpty then 120 else 16365),
			DoubleRobux = source(if isEmpty then 0 else 33),
			CanWatchAd = source(moment == "Rest"),
			Avatar = source(avatar()),
			Doubled = source(0),
			DoubledAt = source(-math.huge),
			CanRevive = source(true),
			ReturnIn = source(20),
			ReturnShare = source(if moment == "Rest" then 0.655 else 1),
			ReturnTickAt = source(-math.huge),
			IsReturnHeld = source(false),
			Votes = source(0),
			VotesNeeded = source(2),
			HasVoted = source(false),
			VotesAt = source(-math.huge),
		}

		if moment == "Doubled" then
			task.delay(MOMENT_AT, function()
				results.Doubled(7550)
				results.DoubledAt(os.clock())
				results.DoubleRobux(0)
			end)
		elseif moment == "Voted" then
			task.delay(MOMENT_AT, function()
				results.HasVoted(true)
				results.Votes(1)
				results.VotesAt(os.clock())
			end)
		end

		if moment ~= "Rest" then
			local total = if moment == "Last" then 6 else 20
			RunService.Heartbeat:Connect(function()
				local now = os.clock()
				local left = math.max(total - (now - startedAt), 0)
				local whole = math.ceil(left)
				if whole ~= results.ReturnIn() then results.ReturnTickAt(now) end
				results.ReturnIn(whole)
				results.ReturnShare(left / 20)
				results.Clock(now)
				results.Beat(now)
			end)
		end

		local root = create("Frame")({
			Name = "Root",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Results.Build({ Results = results }, ACTIONS),
		})
		swapImages(root)
		return root
	end,
}
