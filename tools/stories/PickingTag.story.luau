-- The tag over a teammate who is picking an upgrade (UpgradePickController/PickingTag), through one pick: it comes up
-- at SHOWN_AT, the card is taken at PICKED_AT, the pick is over at ENDED_AT. For rur to render:
--   rur-native render --headless --offline --rojo <game.project.json without its comments> \
--     --story tools/stories/PickingTag.story.luau --viewport 640x520 --scale 1 --time 2.1 --dir <out>
-- A loop over --time gives the motion. The billboard is laid flat into the story, its Root at the billboard's size.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local PickingTag = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.UpgradePickController.PickingTag)
local Card = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.UpgradePickController.Card)
local ERarities = require(ReplicatedStorage.Types.Enums.ERarities)

local create = vide.create
local source = vide.source

local SHOWN_AT = 0.1
local PICKED_AT = 2
-- The show is SHOW_SECONDS; the word that it is over lands a network beat later.
local ENDED_AT = 3.7
local RARITIES = {
	Common = ERarities.Common,
	Rare = ERarities.Rare,
	Epic = ERarities.Epic,
	Legendary = ERarities.Legendary,
	Mythic = ERarities.Mythic,
}

return {
	vide = vide,
	controls = {
		Rarity = { "Epic", "Common", "Rare", "Legendary", "Mythic" },
		Unit = { 3, 1, 2 },
	},
	story = function(props)
		local unit = props.controls.Unit()
		local rarity = RARITIES[props.controls.Rarity()]
		local tag: PickingTag.TTagState = {
			Adornee = source(nil),
			Clock = source(0),
			ShownAt = source(-math.huge),
			PickedAt = source(-math.huge),
			PickedColor = source(Card.RarityColor(rarity)),
			EndedAt = source(math.huge),
		}

		local clock = 0
		RunService.Heartbeat:Connect(function(dt: number)
			clock += dt
			if clock >= SHOWN_AT and tag.ShownAt() < 0 then tag.ShownAt(SHOWN_AT) end
			if clock >= PICKED_AT and tag.PickedAt() < 0 then tag.PickedAt(PICKED_AT) end
			if clock >= ENDED_AT and tag.EndedAt() == math.huge then tag.EndedAt(ENDED_AT) end
			tag.Clock(clock)
		end)

		local billboard = PickingTag.Build(tag, function()
			return unit
		end)
		local root = billboard:FindFirstChild("Root") :: Frame
		local size = billboard.Size
		root.Parent = nil

		return create("Frame")({
			Name = "Stage",
			BackgroundColor3 = Color3.fromRGB(96, 158, 84),
			Size = UDim2.fromOffset(640, 520),
			create("Frame")({
				Name = "Billboard",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = size,
				BackgroundTransparency = 1,
				root,
			}),
		})
	end,
}
