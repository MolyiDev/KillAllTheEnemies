-- A quest's colours, the same wherever one is drawn (the lobby's quests screen, the match's notice of one finished):
-- the card's accent by its group and its edge, its bar, the reward's colour by board and the scroll tile's face.
local StarterPlayer = game:GetService("StarterPlayer")
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)

local Palette = Theme.Palette
-- A card's edge is its accent this much darker; the glow is the accent itself.
local EDGE_SHARE = 0.85

local function edgeOf(accent: Color3): Color3
	return Color3.new(accent.R * EDGE_SHARE, accent.G * EDGE_SHARE, accent.B * EDGE_SHARE)
end

return table.freeze({
	EdgeOf = edgeOf,
	-- His green, steel, violet, pink and gold cards, by QuestsCore group.
	ACCENTS = table.freeze({
		Slay = Palette.Green,
		Hunt = Palette.Steel,
		Survive = Palette.Violet,
		Boss = Palette.Pink,
		Skill = Palette.Gold,
	}),
	-- His bars: pink while it fills, green once it is full, a deep green once it is claimed, on a dark lavender track.
	BAR_FILLING = Color3.fromRGB(251, 47, 142),
	BAR_FULL = Color3.fromRGB(52, 224, 131),
	BAR_CLAIMED = Color3.fromRGB(38, 130, 89),
	BAR_TRACK = Color3.fromRGB(58, 50, 86),
	-- By QuestsCore.BoardIndex: his gold Daily, his blue Weekly.
	REWARD_COLORS = table.freeze({ Palette.Gold, Color3.fromRGB(89, 191, 255) }),
	-- A card's scroll tile: the card's dark face, warmed toward its accent where it is drawn.
	TILE_FACE = Color3.fromRGB(19, 19, 40),
	-- His dark plaque (IN PROGRESS, CLAIMED): a dim pink edge round an ink face.
	PLAQUE_EDGE = Color3.fromRGB(116, 26, 72),
	PLAQUE_FACE = Color3.fromRGB(10, 7, 21),
})
