-- The invite list over the queue, for rur to render beside the party's previews (Assets/ui/party/preview):
--   rur-native render --headless --offline --rojo <lobby.project.json without its comments> \
--     --story tools/uimatt/Invite.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 2 \
--     --controls '{"Moment": "Rest"}' --dir <out>
-- Moment: Rest (eight players, one of each answer), Enter (the list rising over the queue), Send (INVITE pressed on a
-- card, the server's SENT, then the player landing on the pad), Declined (a SENT card turned down), Empty (nobody else
-- in the server), Leave (EXIT going back to the queue), for `rur-native sequence`.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local PadsCore = require(ReplicatedStorage.Shared.Core.PadsCore)
local Parts = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.LobbyController.Party.Parts)
local Queue = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.LobbyController.Party.Queue)
local Invite = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.LobbyController.Party.Invite)
local PadExit = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.LobbyController.Party.Exit)

local source = vide.source
local create = vide.create
local EPhase = PadsCore.EPhase
local EInvite = PadsCore.EInvite

local ROOT = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/"
local SWAPS = {
	[Icons.Pictures.Gem.Image] = ROOT .. "rendered/Pictures1.png",
	[Icons.Pictures.Potion.Image] = ROOT .. "rendered/Pictures2.png",
	[Icons.Pictures.Pointer.Image] = ROOT .. "rendered/Pictures3.png",
	[Icons.Pictures.UpArrow.Image] = ROOT .. "rendered/Pictures4.png",
	[Icons.Pictures.SurvivorVest.Image] = ROOT .. "rendered/Pictures5.png",
	[Icons.IMAGE] = ROOT .. "hud/Icons.png",
	[Icons.PANEL_TEXTURE] = ROOT .. "hud/PanelTexture.png",
	[Parts.PICTURES.PirateCove] = ROOT .. "party/maps/PirateCove.png",
	[Parts.PICTURES.GrassLands] = ROOT .. "party/maps/GrassLands.png",
}
-- Offline there are no avatar thumbnails: each head is drawn as the rendered player bust instead.
local HEAD = Icons.Pictures.Player
local MOMENT_AT = 0.2
local PLAYERS = {
	{ UserId = 101, Name = "BananaLordAK47", DisplayName = "BananaLord" },
	{ UserId = 102, Name = "Fartshot24345", DisplayName = "Fartshot" },
	{ UserId = 103, Name = "Jzal11", DisplayName = "Jzal" },
	{ UserId = 104, Name = "Madara6777h", DisplayName = "Madara" },
	{ UserId = 105, Name = "cn_1105157883", DisplayName = "cn" },
	{ UserId = 106, Name = "matthew_mz07", DisplayName = "matthew" },
	{ UserId = 107, Name = "NightOwlRex", DisplayName = "NightOwl" },
	{ UserId = 108, Name = "PixelPaladin", DisplayName = "PixelPaladin" },
}

local function swapImages(root: Instance)
	local function swap(instance: Instance)
		if not (instance:IsA("ImageLabel") or instance:IsA("ImageButton")) then return end
		local image = instance :: ImageLabel
		local function apply()
			if string.find(image.Image, "rbxthumb://", 1, true) then
				image.Image = SWAPS[HEAD.Image] or HEAD.Image
				image.ImageRectOffset = HEAD.Offset
				image.ImageRectSize = Icons.PICTURE_CELL_SIZE
				return
			end
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
		Moment = { "Rest", "Enter", "Send", "Declined", "Empty", "Leave" },
	},
	story = function(props)
		local moment = props.controls.Moment()
		local start = os.clock()
		local at = start + MOMENT_AT
		local isEnter = moment == "Enter"

		local pad = {
			Index = 1,
			Phase = source(EPhase.Open),
			Count = source(2),
			MaxPlayers = source(4),
			Map = source(1),
			Difficulty = source(2),
			IsFriendsOnly = source(false),
			Seconds = source(12),
		}
		local results = {}
		local onPad = {}
		if moment == "Rest" or moment == "Leave" then
			results[102] = { Result = EInvite.Sent, At = start }
			results[104] = { Result = EInvite.Declined, At = start }
			results[106] = { Result = EInvite.Locked, At = start }
			onPad[103] = 1
			onPad[105] = 2
		elseif moment == "Declined" then
			results[102] = { Result = EInvite.Sent, At = start }
		end
		local state = {
			Scale = source(1),
			PageScale = source(1),
			Pads = { pad },
			CurrentPad = source(1),
			IsChoosing = source(false),
			CreatedAt = source(-math.huge),
			Now = source(start),
			IsInviteOpen = source(not isEnter),
			InviteAt = source(-math.huge),
			InvitePlayers = source(if moment == "Empty" then {} else PLAYERS),
			InviteResults = source(results),
			InviteOnPad = source(onPad),
			UnlockMap = source(0),
			UnlockAt = source(-math.huge),
		}
		local motionUntil = start + 0.1
		local actions = {}
		actions.Stir = function(seconds: number)
			motionUntil = math.max(motionUntil, os.clock() + seconds)
		end
		actions.CloseInvite = function()
			state.IsInviteOpen(false)
			state.InviteAt(os.clock())
			actions.Stir(1.6)
		end
		actions.Leave = actions.CloseInvite
		actions.OpenInvite = function() end
		actions.InviteFriends = function() end
		actions.InvitePlayer = function(userId: number)
			local next = table.clone(state.InviteResults())
			next[userId] = { Result = EInvite.Sent, At = os.clock() }
			state.InviteResults(next)
			actions.Stir(1.6)
		end
		local function answer(userId: number, result: number?)
			local next = table.clone(state.InviteResults())
			next[userId] = if result then { Result = result, At = os.clock() } else nil
			state.InviteResults(next)
			actions.Stir(1.6)
		end

		local steps = {}
		if isEnter then
			steps[1] = function()
				state.InviteAt(os.clock())
				state.IsInviteOpen(true)
				actions.Stir(1.6)
			end
		elseif moment == "Send" then
			steps[1] = function()
				actions.InvitePlayer(101)
			end
			steps[2] = function()
				answer(101, EInvite.Joined)
				pad.Count(3)
			end
		elseif moment == "Declined" then
			steps[1] = function()
				answer(102, EInvite.Declined)
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
			local nextStep = steps[done + 1]
			if nextStep and now >= at + 0.7 * done then
				done += 1
				nextStep()
			end
		end)

		local root = create("Frame")({
			Name = "Stage",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(1920, 1080),
		})
		local queue = Queue.Build(state, actions):FindFirstChild("Root") :: Frame
		queue.Parent = root
		local invite = Invite.Build(state, actions):FindFirstChild("Root") :: Frame
		invite.ZIndex = 2
		invite.Parent = root
		local exit = PadExit.Build(state, actions):FindFirstChild("Root") :: Frame
		exit.ZIndex = 3
		exit.Parent = root
		swapImages(root)
		return root
	end,
}
