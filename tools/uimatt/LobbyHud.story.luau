-- The lobby's HUD with a fixed state, for rur to render beside the designer's Lobby HUD render
-- (Assets/ui/UIMatt/renders/01_Lobby_HUD.png, the same renderer and background):
--   rur-native render --headless --offline --rojo <lobby.project.json without its comments> \
--     --story tools/uimatt/LobbyHud.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 1.5 \
--     --controls '{"Moment": "Rest"}' --dir <out>
-- Moment: Rest (everything landed, his numbers: LV 9 at 62%, 48,250), Enter (the lobby opening 0.2 s in: the pieces
-- slide in, then the bar and the Gems roll up), LevelUp (the bar rolling from 90% over into the next level), Gems (a
-- gain rolling in and landing), Fed (Gems flown in landing a slice at a time, then the last), Spend (Gems paid out, the
-- count rolling down), Dock (the classes or weapons page opening: the Gems counter glides into his coin slot), for
-- `rur-native sequence`.
-- The HUD's root starts under Roblox's top bar strip, as in the game: the strip is drawn (Studio's 58 px, the taller one,
-- and the unibar's 208 x 58 corner, UI.md "The top-left corner is the PLATFORM'S"), since the Gems counter stands in it.
-- rur reads the project file as plain JSON, so strip its comments into a copy first. The group-owned images 403
-- offline, so they are swapped for the local PNGs they were made from.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local Hud = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.LobbyController.Hud)

local source = vide.source
local create = vide.create

local ROOT = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/hud/"
local SWAPS = {
	[Icons.IMAGE] = ROOT .. "Icons.png",
	[Icons.PANEL_TEXTURE] = ROOT .. "PanelTexture.png",
}
local MOMENT_AT = 0.2
local TOP_BAR = 58
local UNIBAR = 208
local LEVEL = 9
local XP = 62
local GEMS = 48250
-- Fed: this many Gems land in SLICES slices, one every SLICE_SECONDS.
local FED = 600
local SLICES = 12
local SLICE_SECONDS = 0.07

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

local function noop() end

return {
	vide = vide,
	controls = {
		Moment = { "Rest", "Enter", "LevelUp", "Gems", "Fed", "Spend", "Dock" },
	},
	story = function(props)
		local moment = props.controls.Moment()
		local at = os.clock() + MOMENT_AT
		local shown = LEVEL + XP / 100
		local isMoving = moment ~= "Rest"

		local state = {
			Now = source(os.clock()),
			EnteredAt = source(if moment == "Enter" then at else -math.huge),
			XpFrom = source(if moment == "Enter" then LEVEL elseif moment == "LevelUp" then LEVEL + 0.9 else shown),
			XpTo = source(if moment == "LevelUp" then LEVEL + 1.3 else shown),
			XpAt = source(if moment == "Enter" then at + 0.55 elseif moment == "LevelUp" then at else -math.huge),
			GemsFrom = source(
				if moment == "Enter"
					then 0
					elseif moment == "Gems" then GEMS - 750
					elseif moment == "Fed" then GEMS - FED
					elseif moment == "Spend" then GEMS + 1200
					else GEMS
			),
			GemsTo = source(if moment == "Fed" then GEMS - FED else GEMS),
			GemsAt = source(
				if moment == "Enter" then at + 0.55 elseif moment == "Gems" or moment == "Spend" then at else -math.huge
			),
			GemsHeld = source(0),
			IsGemsFed = source(false),
			GemGlintAt = source(-math.huge),
			IsGemsDocked = source(false),
			IsDailyReady = source(false),
			IsIndexNew = source(false),
			CallAt = source(-math.huge),
			HeldKey = source(nil),
			IsCovered = source(false),
			CoveredAt = source(-math.huge),
			IsBare = source(false),
			BareAt = source(-math.huge),
			TopInset = source(TOP_BAR),
			Scale = source(1),
		}

		local landed = 0
		if isMoving then
			RunService.Heartbeat:Connect(function()
				local now = os.clock()
				state.Now(now)
				if moment == "Dock" and now >= at and not state.IsGemsDocked() then state.IsGemsDocked(true) end
				if moment ~= "Fed" then return end
				-- As init's holdGems: each landing snaps the count to what has landed.
				local due = math.clamp(math.floor((now - at) / SLICE_SECONDS) + 1, 0, SLICES)
				if due > 0 and not state.IsGemsFed() and landed == 0 then state.IsGemsFed(true) end
				if due == landed then return end
				landed = due
				local shown = GEMS - FED + math.round(FED * due / SLICES)
				state.GemsFrom(shown)
				state.GemsTo(shown)
				if due == SLICES then state.IsGemsFed(false) end
			end)
		end

		local root = create("Frame")({
			Name = "Screen",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			create("Frame")({
				Name = "TopBar",
				Size = UDim2.new(1, 0, 0, TOP_BAR),
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = 0.75,
				BorderSizePixel = 0,
				create("Frame")({
					Name = "Unibar",
					Size = UDim2.fromOffset(UNIBAR, TOP_BAR),
					BackgroundColor3 = Color3.fromRGB(150, 30, 30),
					BackgroundTransparency = 0.4,
					BorderSizePixel = 0,
				}),
			}),
			create("Frame")({
				Name = "Root",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(0, TOP_BAR),
				Size = UDim2.new(1, 0, 1, -TOP_BAR),
				Hud.Build(state, { InviteFriends = noop, MarkGemsGlyph = noop }),
			}),
			Hud.BuildGems(state, { InviteFriends = noop, MarkGemsGlyph = noop }),
		})
		swapImages(root)
		return root
	end,
}
