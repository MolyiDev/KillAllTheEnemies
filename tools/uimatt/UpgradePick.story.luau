-- The upgrade pick laid flat with a fixed state, for rur to render beside the designer's Upgrade Selection render
-- (Assets/ui/UIMatt/renders/14_Upgrade_Selection.png, the same renderer and background):
--   rur-native render --headless --offline --rojo <game.project.json without its comments> \
--     --story tools/uimatt/UpgradePick.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 1.5 \
--     --controls '{"Moment": "Rest"}' --dir <out>
-- Moment: Rest (the hand up, the first card under the hand), Backs (face down), Picked (0.25 s after a pick, for the
-- ring and sparks). The cards are parts in the game (Stage); here their canvases are frames at their rests, so this
-- checks the look, not the motion. The HUD's group-owned images 403 offline: swapped for their local PNGs.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local ERarities = require(ReplicatedStorage.Types.Enums.ERarities)

local Pick = StarterPlayer.StarterPlayerScripts.Client.Controllers.UpgradePickController
local Card = require(Pick.Card)
local Screen = require(Pick.Screen)

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
local SPACING = 396
local REST_Y = 30
local HAND = {
	{ Id = 1, Level = 1, Rarity = ERarities.Rare },
	{ Id = 6, Level = 1, Rarity = ERarities.Epic },
	{ Id = 2, Level = 3, Rarity = ERarities.Common },
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
	controls = {
		Moment = { "Rest", "Backs", "Picked" },
	},
	story = function(props)
		local moment = props.controls.Moment()
		local now = os.clock()
		local isPicked = moment == "Picked"
		local screen = {
			IsEnabled = source(true),
			Scale = source(1),
			Clock = source(math.huge),
			PickClock = source(if isPicked then now + 0.25 else math.huge),
			IsUp = source(not isPicked),
			ToggledAt = source(-math.huge),
			Curtain = source(0),
			IsCatching = source(false),
			Round = source(5),
			RerollPrice = source(50),
			CanReroll = source(true),
			RerollAskedAt = source(-math.huge),
			RerollDeniedAt = source(-math.huge),
			SecondsLeft = source(8),
			TickAt = source(-math.huge),
			PickedAt = source(if isPicked then now else -math.huge),
			PickedColor = source(Card.RarityColor(3)),
			PickPoint = Vector2.new(0, 10),
			PickSize = Card.SIZE * 1.22,
		}

		local canvases = {}
		for index, card in HAND do
			local isChosen = isPicked and index == 2
			if isPicked and not isChosen then continue end
			canvases[#canvases + 1] = create("Frame")({
				Name = `Card{index}`,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(
					0.5,
					if isChosen then 0 else (index - 2) * SPACING,
					0.5,
					if isChosen then -10 else REST_Y
				),
				Size = UDim2.fromOffset(Card.CANVAS.X, Card.CANVAS.Y),
				BackgroundTransparency = 1,
				create("UIScale")({ Scale = if isChosen then 1.22 else 1 }),
				Card.Build({
					Key = ({ Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three })[index],
					Id = source(card.Id),
					Level = source(card.Level),
					Rarity = source(card.Rarity),
					IsFaceUp = source(moment ~= "Backs"),
					IsRevealed = source(moment ~= "Backs"),
					Hover = source(if (moment == "Rest" and index == 1) or isChosen then 1 else 0),
					GlareAt = source(-0.3),
					Shade = source(0),
					Flash = source(if isChosen then 0.3 else 0),
				}),
			})
		end

		local root = create("Frame")({
			Name = "Root",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			create("Frame")({
				Name = "Dim",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.new(),
				BackgroundTransparency = 0.6,
				BorderSizePixel = 0,
			}),
			canvases,
			Screen.Pieces(screen, { Reroll = function() end }),
		})
		swapImages(root)
		return root
	end,
}
