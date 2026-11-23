-- The lobby's index screen with a fixed state, for rur to render beside the designer's Index render
-- (Assets/ui/UIMatt/renders/04_Index.png, the same renderer and background):
--   rur-native render --headless --offline --rojo <lobby.project.json without its comments> \
--     --story tools/uimatt/Index.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 2 \
--     --controls '{"Moment": "Rest"}' --dir <out>
-- Moment: Rest (three monsters found, the Basic Zombie picked), Enter (the screen opening 0.2 s in), Reveal (two
-- monsters found in a run revealed one after the other), Unknown (an enemy not found yet picked), Bosses (the boss page
-- picked 0.2 s in), for `rur-native sequence`. The group-owned images 403 offline, so they are swapped for the local
-- PNGs they were made from. The enemy rigs live in the places, not on disk, so the pictures come out empty here:
-- judge them in a playtest.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local Screen = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.IndexController.Screen)

local source = vide.source
local create = vide.create

local ROOT = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/hud/"
local SWAPS = {
	[Icons.IMAGE] = ROOT .. "Icons.png",
	[Icons.PANEL_TEXTURE] = ROOT .. "PanelTexture.png",
}
local MOMENT_AT = 0.2
local REVEAL_DELAY = 0.75
local REVEAL_STAGGER = 0.5

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
		Moment = { "Rest", "Enter", "Reveal", "Unknown", "Bosses" },
	},
	story = function(props)
		local moment = props.controls.Moment()
		local at = os.clock() + MOMENT_AT
		local isReveal = moment == "Reveal"
		local kills = {
			[EEnemiesIds.Basic] = 1284,
			[EEnemiesIds.Fast] = 342,
			[EEnemiesIds.Exploding] = 97,
		}
		local revealAt = {}
		local unread = {}
		if isReveal then
			kills[EEnemiesIds.Heavy] = 12
			kills[EEnemiesIds.Slammer] = 0
			revealAt[EEnemiesIds.Heavy] = at + REVEAL_DELAY
			revealAt[EEnemiesIds.Slammer] = at + REVEAL_DELAY + REVEAL_STAGGER
			unread[EEnemiesIds.Heavy] = true
			unread[EEnemiesIds.Slammer] = true
		end
		local selected = EEnemiesIds.Basic
		if isReveal then selected = EEnemiesIds.Heavy end
		if moment == "Unknown" then selected = EEnemiesIds.Slammer end
		if moment == "Bosses" then selected = EEnemiesIds.ZombieKing end

		local state = {
			Scale = source(1),
			Now = source(os.clock()),
			IsOpen = source(true),
			ToggledAt = source(if moment == "Enter" or isReveal then at else -math.huge),
			Category = source(if moment == "Bosses" then 2 else 1),
			CategoryAt = source(if moment == "Bosses" then at else -math.huge),
			Selected = source(selected),
			SelectedAt = source(if moment == "Bosses" then at else -math.huge),
			Kills = source(kills),
			Hidden = source({}),
			RevealAt = source(revealAt),
			Unread = source(unread),
			PokedAt = source(-math.huge),
		}

		RunService.Heartbeat:Connect(function()
			state.Now(os.clock())
		end)

		local root = create("Frame")({
			Name = "Root",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(1920, 1080),
			Screen.Build(state, {
				Close = noop,
				PickCategory = noop,
				Select = noop,
				Poke = noop,
				Stir = noop,
			}),
		})
		swapImages(root)
		return root
	end,
}
