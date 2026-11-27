-- The board over a pad (LobbyController/Party/Board), drawn flat at its laid-out size for rur:
--   rur-native render --headless --offline --rojo <lobby.project.json without its comments> \
--     --story tools/uimatt/Board.story.luau --viewport 600x420 --scale 1 --background 40,40,60 --time 2 \
--     --controls '{"Moment": "Waiting"}' --dir <out>
-- Moment: Waiting (Baseplate on Nightmare, 2 of 4, 11 s), Full (4 of 4, 3 s), Going (teleporting), Join (a third
-- player stepping on 0.2 s in), for `rur-native sequence`.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local PadsCore = require(ReplicatedStorage.Shared.Core.PadsCore)
local Parts = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.LobbyController.Party.Parts)
local Board = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.LobbyController.Party.Board)

local source = vide.source
local create = vide.create
local EPhase = PadsCore.EPhase

local ROOT = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/"
local SWAPS = {
	[Icons.Pictures.Gem.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures1.png",
	[Icons.Pictures.Potion.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures2.png",
	[Icons.Pictures.Pointer.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures3.png",
	[Icons.Pictures.UpArrow.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures4.png",
	[Icons.Pictures.SurvivorVest.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures5.png",
	[Icons.IMAGE] = ROOT .. "hud/Icons.png",
	[Icons.PANEL_TEXTURE] = ROOT .. "hud/PanelTexture.png",
}

local function swapImages(root: Instance)
	local function swap(instance: Instance)
		if not (instance:IsA("ImageLabel") or instance:IsA("ImageButton")) then return end
		local image = instance :: ImageLabel
		local function apply()
			local path = SWAPS[image.Image]
			if path then image.Image = path end
		end
		apply()
		image:GetPropertyChangedSignal("Image"):Connect(apply)
	end

	for _, instance in root:GetDescendants() do
		swap(instance)
	end
	root.DescendantAdded:Connect(swap)
end

return {
	vide = vide,
	controls = {
		Moment = { "Waiting", "Full", "Going", "Join" },
	},
	story = function(props)
		local moment = props.controls.Moment()
		local start = os.clock()
		local part = Instance.new("Part")
		part.Size = Vector3.new(12, 1, 12)
		local pad = {
			Index = 1,
			Part = part,
			Phase = source(if moment == "Going" then EPhase.Teleporting else EPhase.Open),
			Count = source(if moment == "Full" then 4 else 2),
			MaxPlayers = source(4),
			Map = source(1),
			Difficulty = source(3),
			IsFriendsOnly = source(false),
			Seconds = source(if moment == "Full" then 3 else 11),
		}
		RunService.Heartbeat:Connect(function()
			if moment == "Join" and os.clock() >= start + 0.2 and pad.Count() == 2 then pad.Count(3) end
		end)

		local gui = Board.Build({ Pads = { pad }, CurrentPad = source(0) } :: any)[1]
		-- The billboard's Root, in a frame the board's own size, so it fits it at 1.
		local board = gui:FindFirstChild("Root") :: Frame
		local root = create("Frame")({
			Name = "Stage",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(600, 420),
			create("Frame")({
				Name = "Box",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(440, 340),
				BackgroundTransparency = 1,
			}),
		})
		board.Parent = root:FindFirstChild("Box")
		swapImages(root)
		return root
	end,
}
