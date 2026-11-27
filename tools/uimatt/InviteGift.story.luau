-- The surprise gift's toast on the right of the lobby (InviteGiftController/Toast), for rur to render beside its
-- previews (Assets/ui/lobby/preview/invite_gift):
--   rur-native render --headless --offline --rojo <lobby.project.json without its comments> \
--     --story tools/uimatt/InviteGift.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 2 \
--     --controls '{"Moment": "Rest", "Friend": "Online"}' --dir <out>
-- Moment: Rest, Enter (sliding in), Call (the light crossing INVITE), Invite, Close, Lapse (its time running out 0.6 s
-- in), for `rur-native sequence`.
-- Friend: Online, Offline (a friend not online now), None (no friend could be named).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local Toast = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.InviteGiftController.Toast)

local source = vide.source
local create = vide.create

local ROOT = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/"
local SWAPS = {
	[Icons.Pictures.Gem.Image] = ROOT .. "rendered/Pictures1.png",
	[Icons.Pictures.Potion.Image] = ROOT .. "rendered/Pictures2.png",
	[Icons.Pictures.Pointer.Image] = ROOT .. "rendered/Pictures3.png",
	[Icons.Pictures.UpArrow.Image] = ROOT .. "rendered/Pictures4.png",
	[Icons.Pictures.SurvivorVest.Image] = ROOT .. "rendered/Pictures5.png",
	[Icons.IMAGE] = ROOT .. "hud/Icons.png",
	[Icons.PANEL_TEXTURE] = ROOT .. "hud/PanelTexture.png",
}
-- Offline there are no avatar thumbnails: the head is drawn as the rendered player bust instead.
local HEAD = Icons.Pictures.Player
local MOMENT_AT = 0.2
local FRIENDS = {
	Online = { UserId = 104, Username = "ChapexEZ", IsOnline = true },
	Offline = { UserId = 105, Username = "Madara6777h", IsOnline = false },
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
		Moment = { "Rest", "Enter", "Call", "Invite", "Close", "Lapse" },
		Friend = { "Online", "Offline", "None" },
	},
	story = function(props)
		local moment = props.controls.Moment()
		local start = os.clock()
		local at = start + MOMENT_AT
		local isEnter = moment == "Enter"

		local state = {
			Scale = source(1),
			Now = source(start),
			Friend = source(FRIENDS[props.controls.Friend()]),
			Gems = source(5000),
			ShownAt = source(
				if isEnter
					then math.huge
					elseif moment == "Lapse" then start + MOMENT_AT + 0.6 - Toast.LAPSE_SECONDS
					else start - 5
			),
			GoneAt = source(-math.huge),
			Answer = source(""),
			CallAt = source(-math.huge),
		}
		local motionUntil = start + (if moment == "Lapse" then 2 else 0.1)
		local function stir(seconds: number)
			motionUntil = math.max(motionUntil, os.clock() + seconds)
		end
		local function leave(answer: string)
			state.Answer(answer)
			state.GoneAt(os.clock())
			stir(1)
		end
		local actions = {
			Invite = function()
				leave("Invite")
			end,
			Close = function()
				leave("Close")
			end,
		}

		local step: (() -> ())? = nil
		if isEnter then
			step = function()
				state.ShownAt(os.clock())
				stir(Toast.ARRIVE_SECONDS)
			end
		elseif moment == "Call" then
			step = function()
				state.CallAt(os.clock())
				stir(1)
			end
		elseif moment == "Invite" then
			step = actions.Invite
		elseif moment == "Close" then
			step = actions.Close
		end

		RunService.Heartbeat:Connect(function()
			local now = os.clock()
			if now < motionUntil then state.Now(now) end
			-- Its time run out, it goes as the controller sends it.
			local isUp = state.GoneAt() < state.ShownAt()
			if moment == "Lapse" and isUp and now >= state.ShownAt() + Toast.LAPSE_SECONDS then leave("Aside") end
			if step and now >= at then
				local current = step
				step = nil
				current()
			end
		end)

		local root = create("Frame")({
			Name = "Stage",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(1920, 1080),
		})
		local toast = Toast.Build(state :: any, actions):FindFirstChild("Root") :: Frame
		toast.Parent = root
		swapImages(root)
		return root
	end,
}
