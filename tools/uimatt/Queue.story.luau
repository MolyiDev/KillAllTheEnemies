-- The lobby's queue screen on a pad, for rur to render beside the party screen's previews (Assets/ui/party/preview):
--   rur-native render --headless --offline --rojo <lobby.project.json without its comments> \
--     --story tools/uimatt/Queue.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 2 \
--     --controls '{"Moment": "Rest"}' --dir <out>
-- Moment: Rest (Baseplate on Hard, friends only, 2 of 4 on, 12 s left), Enter (coming up 0.2 s in, after a
-- CREATE), Tick (the countdown running from 6 s), Join (a third and then a fourth player stepping on, the clock dropping
-- to 3 s), Teleport (the last seconds and the party going), Leave (EXIT), for `rur-native sequence`. Seconds are
-- counted on the story's own clock, as the lobby counts the server's.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local PadsCore = require(ReplicatedStorage.Shared.Core.PadsCore)
local Parts = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.LobbyController.Party.Parts)
local Queue = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.LobbyController.Party.Queue)
local PadExit = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.LobbyController.Party.Exit)

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
local MOMENT_AT = 0.2

local function swapImages(root: Instance)
	-- On every change of Image too: a picture that follows a pick changes its id rather than being made again.
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
		Moment = { "Rest", "Enter", "Created", "Tick", "Join", "Teleport", "Leave" },
	},
	story = function(props)
		local moment = props.controls.Moment()
		local start = os.clock()
		local at = start + MOMENT_AT
		local isEnter = moment == "Enter"
		local isCreated = moment == "Created"
		local endsAt = start
			+ (if moment == "Tick" then 6.05 elseif moment == "Teleport" then 2.05 else 12.4)
			+ (if isEnter then 10 else 0)

		local pad = {
			Index = 1,
			Phase = source(EPhase.Open),
			Count = source(2),
			MaxPlayers = source(4),
			Map = source(1),
			Difficulty = source(2),
			IsFriendsOnly = source(true),
			Seconds = source(math.ceil(endsAt - start)),
		}
		local state = {
			Scale = source(1),
			PageScale = source(1),
			Pads = { pad },
			CurrentPad = source(if isEnter then 0 else 1),
			IsChoosing = source(isCreated),
			CreatedAt = source(if isEnter then at - 0.1 else -math.huge),
			Now = source(start),
		}
		-- The lobby writes Now only while a gesture has asked for it (LobbyController's stir), so the story does too.
		local motionUntil = start + 0.1
		local actions = {
			Leave = function()
				state.CurrentPad(0)
			end,
			Stir = function(seconds: number)
				motionUntil = math.max(motionUntil, os.clock() + seconds)
			end,
		}

		local steps = {}
		if isEnter then
			steps[1] = function()
				state.CurrentPad(1)
			end
		elseif isCreated then
			-- CREATE, and the server's answer a few frames later: the pad open and the host no longer choosing.
			steps[1] = function()
				state.CreatedAt(os.clock())
			end
			steps[2] = function()
				state.IsChoosing(false)
			end
		elseif moment == "Join" then
			steps[1] = function()
				pad.Count(3)
			end
			steps[2] = function()
				pad.Count(4)
				endsAt = math.min(endsAt, os.clock() + PadsCore.FULL_COUNTDOWN_SECONDS)
			end
		elseif moment == "Leave" then
			steps[1] = function()
				actions.Leave()
			end
		end

		local done = 0
		RunService.Heartbeat:Connect(function()
			local now = os.clock()
			if now < motionUntil then state.Now(now) end
			if pad.Phase() == EPhase.Open then
				local left = math.ceil(math.max(endsAt - now, 0))
				if left ~= pad.Seconds() then pad.Seconds(left) end
				if left == 0 and moment == "Teleport" then pad.Phase(EPhase.Teleporting) end
			end
			local nextStep = steps[done + 1]
			if nextStep and now >= at + (if isCreated then 0.1 else 0.6) * done then
				done += 1
				nextStep()
			end
		end)

		local gui = Queue.Build(state, actions)
		local root = create("Frame")({
			Name = "Stage",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(1920, 1080),
		})
		local screen = gui:FindFirstChild("Root") :: Frame
		screen.Parent = root
		local exit = PadExit.Build(state, actions):FindFirstChild("Root") :: Frame
		exit.ZIndex = 2
		exit.Parent = root
		swapImages(root)
		return root
	end,
}
