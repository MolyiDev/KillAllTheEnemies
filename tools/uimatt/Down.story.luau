-- Being down on the HUD (HudController/Down) with a fixed state, for rur:
--   rur-native sequence --headless --offline --rojo <game.project.json without its comments> \
--     --story tools/uimatt/Down.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 \
--     --controls '{"Moment": "Enter"}' --from 0 --duration 4.5 --fps 30 --dir <out>
-- Moment: Rest (down a while, watching a squadmate), Enter (the down from its first frame), Revived (the rebuild
-- starting REVIVED_AT in), Wipe (the down ending without a revive). A press is `--actions` clicking `Revive`.
-- rur reads the project file as plain JSON, so strip its comments into a copy first. The HUD's group-owned images 403
-- offline, so they are swapped for the local PNGs they were made from.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local Down = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.HudController.Down)

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
-- How long before the story starts the player went down, at rest (long past every entrance).
local DOWN_AGO = 20
local REVIVED_AT = 0.5
local STOOD_AFTER = 1.6

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

return {
	vide = vide,
	controls = {
		Moment = { "Rest", "Enter", "Revived", "Wipe" },
	},
	story = function(props)
		local moment = props.controls.Moment()
		local startedAt = os.clock()
		local down = {
			Clock = source(startedAt),
			At = source(if moment == "Enter" then startedAt else startedAt - DOWN_AGO),
			SwitchedAt = source(-math.huge),
			RebuildAt = source(-math.huge),
			StoodAt = source(-math.huge),
			IsRebuilding = source(false),
			Watched = source("ChapexEZ"),
			WatchedHealth = source(64),
			WatchedMax = source(100),
		}
		local state = {
			Down = down,
			IsDown = source(true),
			CanQuickRevive = true,
			Downed = source(table.freeze({})),
			Scale = source(1),
		}
		local actions = {
			QuickRevive = function() end,
			Spectate = function()
				down.SwitchedAt(down.Clock())
			end,
		}

		RunService.Heartbeat:Connect(function()
			local now = os.clock()
			local t = now - startedAt
			if moment == "Revived" and t >= REVIVED_AT and not down.IsRebuilding() then
				down.RebuildAt(now)
				down.IsRebuilding(true)
				down.Watched("")
			end
			if moment == "Revived" and t >= REVIVED_AT + STOOD_AFTER and down.StoodAt() < down.At() then
				down.StoodAt(now)
			end
			if moment == "Wipe" and t >= REVIVED_AT then state.IsDown(false) end
			down.Clock(now)
		end)

		local root = create("Frame")({
			Name = "Root",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Down.Build(state, actions),
		})
		swapImages(root)
		return root
	end,
}
