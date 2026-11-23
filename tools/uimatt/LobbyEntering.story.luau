-- The lobby's results with a fixed state, for rur to render beside the designer's Lobby Entering render
-- (Assets/ui/UIMatt/renders/18_Lobby_Entering.png, the same renderer and background):
--   rur-native render --headless --offline --rojo <lobby.project.json without its comments> \
--     --story tools/uimatt/LobbyEntering.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 1.5 \
--     --controls '{"Moment": "Rest", "Squad": 2}' --dir <out>
-- Moment: Rest (everything landed, his numbers), Open (the screen going up 0.2 s in, for `rur-native sequence`).
-- Squad: 1 to 4. The stage behind is a still of the elevator (stage.png) with block bodies standing in for avatars.
-- rur reads the project file as plain JSON, so strip its comments into a copy first. The group-owned images 403
-- offline, so they are swapped for the local PNGs they were made from.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Controller = StarterPlayer.StarterPlayerScripts.Client.Controllers.LobbyEnteringController
local Header = require(Controller.Header)
local Squad = require(Controller.Squad)
local Stats = require(Controller.Stats)

local source = vide.source
local create = vide.create
local Progress = Motion.Progress

local ROOT = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/hud/"
local SWAPS = {
	[Icons.IMAGE] = ROOT .. "Icons.png",
	[Icons.PANEL_TEXTURE] = ROOT .. "PanelTexture.png",
}
local MOMENT_AT = 0.2
-- A clock at rest, far past every gesture.
local REST_NOW = 1000

local NAMES = { "RENKAMENS", "TURBOTACO", "NITRONANA", "BLOCKHEAD" }
local KILLS = { 1012, 1001, 640, 233 }

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

-- Where each slot's tag goes over the stage render (stage.png, ror's render of the elevator with block bodies on
-- Stage's spots, from Stage's camera): x, y in px and the head's distance (studs), worked out from the same camera.
local HEADS = {
	Vector3.new(869, 435, 16.9),
	Vector3.new(573, 474, 19.9),
	Vector3.new(1192, 474, 19.9),
	Vector3.new(283, 471, 15.9),
}
local STAGE = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/lobby/preview/entering/stage.png"

local ACTIONS = {
	Close = function() end,
}

return {
	vide = vide,
	controls = {
		Moment = { "Rest", "Open" },
		Squad = 2,
	},
	story = function(props)
		local moment = props.controls.Moment()
		local size = math.clamp(math.floor(props.controls.Squad()), 1, 4)
		local isRest = moment == "Rest"

		local squad = table.create(size)
		for index = 1, size do
			squad[index] = { UserId = index, Name = NAMES[index], ClassId = 1, Kills = KILLS[index] }
		end

		local slots, turns, mvp = Squad.Arrange(squad)
		local members = table.create(size)
		for index, entry in squad do
			members[index] = {
				UserId = entry.UserId,
				Name = entry.Name,
				ClassId = entry.ClassId,
				Kills = entry.Kills,
				IsMvp = index == mvp,
				Slot = slots[index],
				Order = turns[index],
				Avatar = source(nil),
				LoadedAt = source(-math.huge),
				HeadAt = source(HEADS[slots[index]]),
				InfoWidth = source(0),
			}
		end

		-- His numbers where ours have the same thing: wave 21, 2,013 kills, 13:40, 7,505 Gems of 16,365, LV 8.
		local state = {
			Scale = source(1),
			Width = source(1920),
			Now = source(if isRest then REST_NOW else os.clock()),
			IsOpen = source(true),
			ToggledAt = source(if isRest then 0 else os.clock() + MOMENT_AT),
			Record = source({
				MapName = "PirateCove",
				Wave = 21,
				BestWaveBefore = 18,
				Seconds = 820,
				BestSecondsBefore = 700,
				Gems = 7505,
				Kills = 1001,
				SquadKills = 2013,
				LevelBefore = 8,
				XpBefore = 30,
				XpWaves = 76,
				XpBosses = 4,
				Squad = squad,
			}),
			Members = source(members),
			TotalGems = source(16365),
		}

		if not isRest then RunService.Heartbeat:Connect(function()
			state.Now(os.clock())
		end) end

		local elapsed = vide.derive(function(): number
			return state.Now() - state.ToggledAt()
		end)
		local clock = {
			Elapsed = elapsed,
			Shown = function(): number
				return Motion.Out(Progress(elapsed(), 0, 0.35))
			end,
			Since = function(delay: number, seconds: number): number
				return Progress(elapsed(), delay, seconds)
			end,
		}

		local root = create("Frame")({
			Name = "Root",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			create("ImageLabel")({
				Name = "Stage",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Image = STAGE,
				ZIndex = 0,
			}),
			create("Frame")({
				Name = "Dim",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.new(),
				BackgroundTransparency = 0.85,
				BorderSizePixel = 0,
				ZIndex = 0,
			}),
			Squad.Build(state, clock),
			Header.Build(state, clock),
			Stats.Build(state, clock, ACTIONS),
		})
		swapImages(root)
		return root
	end,
}
