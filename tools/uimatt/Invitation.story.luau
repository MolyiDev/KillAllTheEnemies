-- A party's invite, as the player it was sent to sees it over the lobby, for rur to render beside the party's previews
-- (Assets/ui/party/preview):
--   rur-native render --headless --offline --rojo <lobby.project.json without its comments> \
--     --story tools/uimatt/Invitation.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 2 \
--     --controls '{"Moment": "Rest"}' --dir <out>
-- Moment: Rest (12 s left), Enter (sliding in), Call (the light crossing JOIN), Hurry (the last seconds), Join, Decline,
-- for `rur-native sequence`. Seconds are counted on the story's own clock, as the lobby counts the server's.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local PadsCore = require(ReplicatedStorage.Shared.Core.PadsCore)
local Parts = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.LobbyController.Party.Parts)
local Invitation = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.LobbyController.Party.Invitation)

local source = vide.source
local create = vide.create
local EPhase = PadsCore.EPhase

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
-- Offline there are no avatar thumbnails: the head is drawn as the rendered player bust instead.
local HEAD = Icons.Pictures.Player
local MOMENT_AT = 0.2

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
		Moment = { "Rest", "Enter", "Call", "Hurry", "Join", "Decline" },
	},
	story = function(props)
		local moment = props.controls.Moment()
		local start = os.clock()
		local at = start + MOMENT_AT
		local isEnter = moment == "Enter"
		local endsAt = start + (if moment == "Hurry" then 4.05 else 12.4)

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
		local invitation = { Pad = 1, UserId = 104, DisplayName = "Madara6777h", EndsAt = endsAt }
		local state = {
			Scale = source(1),
			PageScale = source(1),
			Pads = { pad },
			Now = source(start),
			Invitation = source(invitation),
			InvitationAt = source(if isEnter then math.huge else start - 5),
			InvitationGoneAt = source(-math.huge),
			InvitationAnswer = source(""),
			InvitationSeconds = source(math.ceil(endsAt - start)),
			InvitationCallAt = source(-math.huge),
		}
		local motionUntil = start + 0.1
		local actions = {}
		actions.Stir = function(seconds: number)
			motionUntil = math.max(motionUntil, os.clock() + seconds)
		end
		actions.AnswerInvitation = function(isJoining: boolean)
			state.InvitationAnswer(if isJoining then "Join" else "Decline")
			state.InvitationGoneAt(os.clock())
			actions.Stir(1)
		end

		local steps = {}
		if isEnter then
			steps[1] = function()
				state.InvitationAt(os.clock())
				actions.Stir(Invitation.ARRIVE_SECONDS)
			end
		elseif moment == "Call" then
			steps[1] = function()
				state.InvitationCallAt(os.clock())
				actions.Stir(1)
			end
		elseif moment == "Join" then
			steps[1] = function()
				actions.AnswerInvitation(true)
			end
		elseif moment == "Decline" then
			steps[1] = function()
				actions.AnswerInvitation(false)
			end
		end

		local done = 0
		RunService.Heartbeat:Connect(function()
			local now = os.clock()
			if now < motionUntil then state.Now(now) end
			local left = math.ceil(math.max(endsAt - now, 0))
			if left ~= state.InvitationSeconds() then state.InvitationSeconds(left) end
			local nextStep = steps[done + 1]
			if nextStep and now >= at + 0.6 * done then
				done += 1
				nextStep()
			end
		end)

		local root = create("Frame")({
			Name = "Stage",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(1920, 1080),
		})
		local card = Invitation.Build(state, actions):FindFirstChild("Root") :: Frame
		card.Parent = root
		swapImages(root)
		return root
	end,
}
