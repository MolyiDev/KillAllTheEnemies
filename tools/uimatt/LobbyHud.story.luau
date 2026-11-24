-- The lobby's HUD with a fixed state, for rur to render beside the designer's Lobby HUD render
-- (Assets/ui/UIMatt/renders/01_Lobby_HUD.png, the same renderer and background):
--   rur-native render --headless --offline --rojo <lobby.project.json without its comments> \
--     --story tools/uimatt/LobbyHud.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 1.5 \
--     --controls '{"Moment": "Rest"}' --dir <out>
-- Moment: Rest (everything landed, his numbers: LV 9 at 62%, 48,250), Enter (the lobby opening 0.2 s in: the pieces
-- slide in, then the bar and the Gems roll up), LevelUp (the bar rolling from 90% over into the next level), Gems (a
-- gain rolling in and landing), Fed (Gems flown in landing a slice at a time, then the last), Spend (Gems paid out, the
-- count rolling down), Dock (the classes or weapons page opening: the Gems counter glides into his coin slot), PlayCall
-- (the light crossing PLAY), Play (PLAY pressed: the launch), PlayRefused (no pad free: PLAY shakes), Waiting (every
-- button's Notice up: 2 quests, 6 discoveries, a gun and an ability to pay for; the call every 1.2 s from 0.3 s),
-- NoticesArrive (all four popping in at 0.2 s), CountUp (the index's count 5 to 6 at 0.2 s), NoticesClear (all four
-- going at 0.2 s), for `rur-native sequence`.
-- The HUD's root starts under Roblox's top bar strip, as in the game: the strip is drawn (Studio's 58 px, the taller one,
-- and the unibar's 208 x 58 corner, UI.md "The top-left corner is the PLATFORM'S"), since the top row stands in it.
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
	[Icons.Pictures.Gem.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures1.png",
	[Icons.Pictures.Potion.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures2.png",
	[Icons.Pictures.Pointer.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures3.png",
	[Icons.Pictures.UpArrow.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures4.png",
	[Icons.Pictures.SurvivorVest.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures5.png",
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
		Moment = {
			"Rest",
			"Enter",
			"LevelUp",
			"Gems",
			"Fed",
			"Spend",
			"Dock",
			"PlayCall",
			"Play",
			"PlayRefused",
			"Waiting",
			"NoticesArrive",
			"CountUp",
			"NoticesClear",
		},
	},
	story = function(props)
		local moment = props.controls.Moment()
		local at = os.clock() + MOMENT_AT
		local shown = LEVEL + XP / 100
		local isMoving = moment ~= "Rest"
		-- Each Notice moment's counts before and after its moment: quests, discoveries, weapons, classes.
		local notices = ({
			Waiting = { { 2, 6, 1, 1 }, { 2, 6, 1, 1 } },
			NoticesArrive = { { 0, 0, 0, 0 }, { 2, 6, 1, 1 } },
			CountUp = { { 2, 5, 1, 1 }, { 2, 6, 1, 1 } },
			NoticesClear = { { 2, 6, 1, 1 }, { 0, 0, 0, 0 } },
		})[moment] or { { 0, 0, 0, 0 }, { 0, 0, 0, 0 } }
		local before, after = notices[1], notices[2]

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
			IsDailyWaiting = source(false),
			QuestsReady = source(before[1]),
			IndexCount = source(before[2]),
			CanUpgradeWeapons = source(before[3] > 0),
			CanUpgradeClasses = source(before[4] > 0),
			CanBrew = source(before[1] > 0),
			CallAt = source(-math.huge),
			PlayAt = source(if moment == "Play" then at else -math.huge),
			PlayRefusedAt = source(if moment == "PlayRefused" then at else -math.huge),
			PlayCallAt = source(if moment == "PlayCall" then at else -math.huge),
			HeldKey = source(nil),
			IsCovered = source(false),
			CoveredAt = source(-math.huge),
			IsPlateCovered = source(false),
			PlateCoveredAt = source(-math.huge),
			IsBare = source(false),
			BareAt = source(-math.huge),
			TopInset = source(TOP_BAR),
			TopbarRoom = source(0),
			Scale = source(1),
			PageScale = source(1),
		}

		local landed = 0
		local nextCall = if moment == "Waiting" then at + 0.1 else math.huge
		if isMoving then
			RunService.Heartbeat:Connect(function()
				local now = os.clock()
				state.Now(now)
				if now >= at and state.IndexCount() ~= after[2] then
					state.QuestsReady(after[1])
					state.IndexCount(after[2])
					state.CanUpgradeWeapons(after[3] > 0)
					state.CanUpgradeClasses(after[4] > 0)
					state.CanBrew(after[1] > 0)
				end
				if now >= nextCall then
					nextCall = now + 1.2
					state.CallAt(now)
				end
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
				Hud.Build(state, { InviteFriends = noop, MarkGemsGlyph = noop, Play = noop }),
			}),
			Hud.BuildTop(state, { InviteFriends = noop, MarkGemsGlyph = noop, MarkXpBar = noop }),
		})
		state.TopbarRoom(root.AbsoluteSize.X / 2 - UNIBAR)
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			state.TopbarRoom(root.AbsoluteSize.X / 2 - UNIBAR)
		end)
		swapImages(root)
		return root
	end,
}
