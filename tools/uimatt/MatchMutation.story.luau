-- The Mutation Lab's part of a match (Game MutationController: the potions drunk as the run starts, then the souls
-- kills drop), run whole on a loopback client while MatchMutation.harness.luau fires the real Mutation events from the
-- server, for Assets/ui/hud/preview/mutation:
--   rur-native sequence --headless --offline --rojo <game.project.json without its comments> --mode play \
--     --run-context loopback --server-harness tools/uimatt/MatchMutation.harness.luau --all-layers true \
--     --story tools/uimatt/MatchMutation.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 \
--     --from 0 --to 15 --fps 60 --dir <out>
-- The controller mounts its own ScreenGui in PlayerGui (drawn by --all-layers); the story's frame is an empty stage.
-- The group-owned images 403 offline, so they are swapped for the local PNGs they were made from.
local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local MutationController = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.MutationController)

local LocalPlayer = Players.LocalPlayer

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

local function swapImages(root: Instance)
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
	story = function()
		swapImages(LocalPlayer:WaitForChild("PlayerGui"))
		MutationController.OnStart()

		local root = Instance.new("Frame")
		root.Name = "Stage"
		root.BackgroundTransparency = 1
		root.Size = UDim2.fromOffset(1920, 1080)
		return root
	end,
}
