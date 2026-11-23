--!nonstrict
-- What the spins screen's pieces share: each prize's accent, the same scatter for the same piece, his label, and where a
-- moving piece waits while it is not in use.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local SpinsCore = require(ReplicatedStorage.Shared.Core.SpinsCore)

local create = vide.create
local Palette = Theme.Palette
local Font = Theme.Font

-- His card colours: gold for Gems (his coins), blue for XP (his tokens), violet for the jackpot (his booster).
local ACCENTS = table.freeze({
	Gems = Palette.Gold,
	Xp = Color3.fromRGB(89, 191, 255),
	Jackpot = Color3.fromRGB(139, 92, 255),
})

local Parts = {}

-- Where a moving piece waits while it is not in use. Never hidden with Visible: turned visible, a frame is drawn
-- where it was last laid out for a frame or two (UI.md), so a piece left at the end of one flight would flash there at
-- the start of the next.
Parts.PARKED = UDim2.new(0.5, 0, 0.5, 100000)

function Parts.AccentOf(prize: SpinsCore.TPrize): Color3
	if prize.IsJackpot then return ACCENTS.Jackpot end
	return ACCENTS[prize.Kind]
end

-- The same throw for the same piece every time, so two landings read alike: 0 to 1.
function Parts.Scatter(index: number, salt: number): number
	local x = math.sin(index * 12.9898 + salt * 78.233) * 43758.5453
	return x - math.floor(x)
end

function Parts.Label(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		ZIndex = 4,
		props,
	})
end

return Parts
