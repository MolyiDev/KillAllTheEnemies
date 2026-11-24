-- The lobby's party screen with fixed picks, for rur to render beside the other lobby screens' previews
-- (Assets/ui/party/preview):
--   rur-native render --headless --offline --rojo <lobby.project.json without its comments> \
--     --story tools/uimatt/Party.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 2 \
--     --controls '{"Moment": "Rest"}' --dir <out>
-- Moment: Rest (open and settled: Pirate Cove, Normal, a party of 4, public), Enter (opening 0.2 s in), Map (the next
-- map picked 0.2 s in), Back (the map before), Dot (the last map picked by its dot), Size (a party of 2 picked), Grow
-- (from 1 to 4), Difficulty (Hell picked), Access (friends picked), Create (CREATE pressed and the party going up),
-- Close (the X), for `rur-native sequence`. The group-owned images 403
-- offline, so they are swapped for the local PNGs they were made from.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local MapsCore = require(ReplicatedStorage.GlobalShared.Core.MapsCore)
local PadsCore = require(ReplicatedStorage.Shared.Core.PadsCore)
local Party = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.LobbyController.Party)
local PadExit = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.LobbyController.Party.Exit)
local Parts = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.LobbyController.Party.Parts)

local source = vide.source
local create = vide.create

local ROOT = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/"
local SWAPS = {
	[Icons.Pictures.Gem.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures1.png",
	[Icons.Pictures.Potion.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures2.png",
	[Icons.Pictures.Pointer.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures3.png",
	[Icons.Pictures.UpArrow.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures4.png",
	[Icons.Pictures.SurvivorVest.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures5.png",
	[Icons.IMAGE] = ROOT .. "hud/Icons.png",
	[Icons.PANEL_TEXTURE] = ROOT .. "hud/PanelTexture.png",
	[Parts.PICTURES.PirateCove] = ROOT .. "party/maps/PirateCove.png",
	[Parts.PICTURES.GrassLands] = ROOT .. "party/maps/GrassLands.png",
}
local MOMENT_AT = 0.2
-- The server's answer to CREATE: the pad moves on and the screen shuts.
local ANSWER = 0.12

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

local function noop() end

return {
	vide = vide,
	controls = {
		-- The screen's UIScale: 1 at 1080, 0.667 at 720.
		Scale = { "1", "0.833", "0.667" },
		Moment = {
			"Rest",
			"Enter",
			"Map",
			"Back",
			"Dot",
			"Size",
			"Grow",
			"Difficulty",
			"Access",
			"Create",
			"Close",
			"Hurry",
		},
	},
	story = function(props)
		local moment = props.controls.Moment()
		local start = os.clock()
		local at = start + MOMENT_AT

		local state = {
			Scale = source(tonumber(props.controls.Scale()) or 1),
			PageScale = source(tonumber(props.controls.Scale()) or 1),
			CurrentPad = source(2),
			-- The host's time left to pick, counted down on the story's clock below.
			Pads = {
				[2] = {
					Seconds = source(if moment == "Hurry" then 8 else 24),
					Phase = source(PadsCore.EPhase.Choosing),
				},
			},
			IsChoosing = source(true),
			ChoosingAt = source(if moment == "Enter" then at else -math.huge),
			BestByMap = source({ PirateCove = 23, GrassLands = 8 }),
			PickPlayers = source(if moment == "Grow" then 1 else 4),
			PickDifficulty = source(MapsCore.DIFFICULTIES[1]),
			PickMap = source(1),
			PickFriendsOnly = source(false),
			MapAt = source(-math.huge),
			MapStep = source(1),
			MapFrom = source(1),
			DifficultyAt = source(-math.huge),
			DifficultyFrom = source(MapsCore.DIFFICULTIES[1]),
			PlayersAt = source(-math.huge),
			PlayersFrom = source(4),
			AccessAt = source(-math.huge),
			CreatedAt = source(-math.huge),
			PartyRefusedAt = source(-math.huge),
			PartyCallAt = source(-math.huge),
			Now = source(start),
		}

		local function setMap(index: number, step: number)
			state.MapFrom(state.PickMap())
			state.PickMap(index)
			state.MapAt(os.clock())
			state.MapStep(step)
		end

		local actions = {
			Leave = function()
				state.IsChoosing(false)
				state.ChoosingAt(os.clock())
			end,
			StartParty = function()
				state.CreatedAt(os.clock())
			end,
			PickDifficulty = function(difficulty: string)
				state.DifficultyFrom(state.PickDifficulty())
				state.PickDifficulty(difficulty)
				state.DifficultyAt(os.clock())
			end,
			Stir = noop,
			PickMap = function(index: number)
				setMap(index, if index < state.PickMap() then -1 else 1)
			end,
			StepMap = function(step: number)
				setMap((state.PickMap() - 1 + step) % #MapsCore.LIST + 1, step)
			end,
			PickPlayers = function(count: number)
				state.PlayersFrom(state.PickPlayers())
				state.PickPlayers(count)
				state.PlayersAt(os.clock())
			end,
			PickFriendsOnly = function(isFriendsOnly: boolean)
				state.PickFriendsOnly(isFriendsOnly)
				state.AccessAt(os.clock())
			end,
		}

		local pickEndsAt = start + (if moment == "Hurry" then 7.5 else 23.5)
		local isDone = false
		local isAnswered = false
		RunService.Heartbeat:Connect(function()
			local now = os.clock()
			state.Now(now)
			local left = math.ceil(math.max(pickEndsAt - now, 0))
			if left ~= state.Pads[2].Seconds() then state.Pads[2].Seconds(left) end
			if now < at then return end
			if not isDone then
				isDone = true
				if moment == "Map" then actions.StepMap(1) end
				if moment == "Back" then actions.StepMap(-1) end
				if moment == "Dot" then actions.PickMap(#MapsCore.LIST) end
				if moment == "Difficulty" then actions.PickDifficulty("Hell") end
				if moment == "Size" then actions.PickPlayers(2) end
				if moment == "Grow" then actions.PickPlayers(4) end
				if moment == "Access" then actions.PickFriendsOnly(true) end
				if moment == "Create" then actions.StartParty() end
				if moment == "Close" then
					actions.Leave()
					state.CurrentPad(0)
				end
			end
			if moment == "Create" and not isAnswered and now >= at + ANSWER then
				isAnswered = true
				actions.Leave()
			end
		end)

		local gui = Party.Build(state, actions)
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
