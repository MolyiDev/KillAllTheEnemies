-- Three head tags with fixed figures, for rur to render beside the designer's Player Head Tag render
-- (Assets/ui/UIMatt/renders/13_Player_Head_Tag.png, the same renderer and background), at his places and size:
--   rur-native render --headless --offline --rojo <lobby.project.json without its comments> \
--     --story tools/uimatt/HeadTag.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 1.5 --dir <out>
-- In the game each is drawn in a BillboardGui, scaled to it. The group-owned images 403 offline, so they are swapped
-- for the local PNGs they were made from.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local Tag = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.HeadTagController.Tag)

local source = vide.source
local create = vide.create

local ROOT = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/hud/"
local SWAPS = {
	[Icons.IMAGE] = ROOT .. "Icons.png",
	[Icons.PANEL_TEXTURE] = ROOT .. "PanelTexture.png",
}
-- His three tags' corners, and their figures.
local TAGS = {
	{ At = Vector2.new(156, 296), Name = "Renkamens", Level = 9, Trophies = 21, Deaths = 7 },
	{ At = Vector2.new(736, 296), Name = "TurboTaco", Level = 24, Trophies = 88, Deaths = 31 },
	{ At = Vector2.new(1316, 296), Name = "NitroNana", Level = 57, Trophies = 240, Deaths = 64 },
}

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
	story = function()
		local room = (Tag.BOX.X - 448) / 2
		local tags = {}
		for index, spec in TAGS do
			tags[index] = create("Frame")({
				Position = UDim2.fromOffset(spec.At.X - room, spec.At.Y - room),
				Size = UDim2.fromOffset(Tag.BOX.X, Tag.BOX.Y),
				BackgroundTransparency = 1,
				Tag.Build(
					spec.Name,
					source({ Level = spec.Level, ClassId = 1, Trophies = spec.Trophies, Deaths = spec.Deaths })
				),
			})
		end

		local root = create("Frame")({
			Name = "Root",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			tags,
		})
		swapImages(root)
		return root
	end,
}
