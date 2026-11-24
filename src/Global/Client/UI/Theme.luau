-- The UI's look in one place, for the arena's HUD and the lobby alike: flat square blocks (UI.md). Corners are square;
-- a block's edge is a lighter tint of its own colour, never black; blocks are opaque, so a readout over a moving arena
-- does not change with what is behind it.
--
-- Text contrast was measured (WCAG): white on defense blue and on boss red is 3.95, so those carry only LARGE letters
-- (keys, initials) and names sit on ink bars; muted on the locked grey is 3.9, so locked faces use white.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ERarities = require(ReplicatedStorage.Types.Enums.ERarities)

local Theme = {}

local SANS = "rbxasset://fonts/families/BuilderSans.json"
local MONO = "rbxasset://fonts/families/RobotoMono.json"
local DISPLAY = "rbxasset://fonts/families/Montserrat.json"

Theme.Color = table.freeze({
	Ink = Color3.fromRGB(15, 17, 21),
	Surface = Color3.fromRGB(28, 31, 38),
	Edge = Color3.fromRGB(62, 68, 82),
	Text = Color3.fromRGB(245, 247, 250),
	Muted = Color3.fromRGB(150, 158, 172),
	Action = Color3.fromRGB(64, 226, 140),
	ActionEdge = Color3.fromRGB(160, 255, 205),
	Gold = Color3.fromRGB(255, 192, 46),
	GoldEdge = Color3.fromRGB(255, 228, 150),
	Gem = Color3.fromRGB(80, 205, 255),
	Xp = Color3.fromRGB(176, 132, 255),
	Defense = Color3.fromRGB(52, 120, 228),
	DefenseEdge = Color3.fromRGB(140, 186, 255),
	Boss = Color3.fromRGB(232, 48, 72),
	BossEdge = Color3.fromRGB(255, 140, 156),
	Locked = Color3.fromRGB(58, 63, 74),
	Health = Color3.fromRGB(72, 214, 110),
	HealthLow = Color3.fromRGB(240, 70, 70),
	Trail = Color3.fromRGB(255, 236, 214),
	Hurt = Color3.fromRGB(255, 26, 36),
})

-- The designer's look (UIMatt.md section 4): text colours as he set them, surfaces sampled from his art at 1080p.
Theme.Palette = table.freeze({
	White = Color3.fromRGB(255, 255, 255),
	Lavender = Color3.fromRGB(185, 169, 217),
	Gold = Color3.fromRGB(255, 193, 59),
	Ink = Color3.fromRGB(13, 10, 28),
	Green = Color3.fromRGB(51, 217, 128),
	Pink = Color3.fromRGB(255, 46, 139),
	Steel = Color3.fromRGB(158, 186, 217),
	-- COMMON: his grey for the lowest rarity.
	Grey = Color3.fromRGB(153, 153, 173),
	-- The lobby's Daily Spins card.
	Violet = Color3.fromRGB(140, 90, 255),
	-- A dark panel's edge, his muted pink.
	EdgePink = Color3.fromRGB(122, 25, 74),
	-- His green slab's deep bottom colour.
	GoBottom = Color3.fromRGB(12, 137, 86),
})

-- The one rarity look (TData.TRarity, keyed as ERarities): every gun, class, piece of equipment, potion and run upgrade
-- card draws its rarity from here, so a rarity reads the same wherever it is met. Its colour, its word, and whether its
-- tag is lettered in ink. His grey COMMON, green UNCOMMON, pink EPIC and gold LEGENDARY; MYTHIC is red, which he did
-- not draw.
Theme.Rarities = table.freeze({
	Common = table.freeze({ Accent = Theme.Palette.Grey, Text = "COMMON", IsInk = true }),
	Uncommon = table.freeze({ Accent = Theme.Palette.Green, Text = "UNCOMMON", IsInk = true }),
	Rare = table.freeze({ Accent = Theme.Palette.Violet, Text = "RARE", IsInk = false }),
	Epic = table.freeze({ Accent = Theme.Palette.Pink, Text = "EPIC", IsInk = false }),
	Legendary = table.freeze({ Accent = Theme.Palette.Gold, Text = "LEGENDARY", IsInk = true }),
	Mythic = table.freeze({ Accent = Color3.fromRGB(230, 60, 72), Text = "MYTHIC", IsInk = false }),
})
-- The same looks by ERarities number, as a card or a potion carries its rarity.
local raritiesByNumber = {}
for name, rarity in ERarities do
	raritiesByNumber[rarity] = Theme.Rarities[name]
end
Theme.RaritiesByNumber = table.freeze(raritiesByNumber)

Theme.Font = table.freeze({
	Medium = Font.new(SANS, Enum.FontWeight.Medium),
	Bold = Font.new(SANS, Enum.FontWeight.Bold),
	Heavy = Font.new(SANS, Enum.FontWeight.ExtraBold),
	-- Titles and headers, as the reference's "NEXT WAVE IN".
	Mono = Font.new(MONO, Enum.FontWeight.Bold),
	-- The designer's two weights (UIMatt.md section 2): Heavy for nearly everything, Bold for captions.
	Display = Font.new(DISPLAY, Enum.FontWeight.Heavy),
	DisplayBold = Font.new(DISPLAY, Enum.FontWeight.Bold),
})

-- A block's edge, in pixels.
Theme.EDGE_THICKNESS = 2
-- Ink round a letter is a share of the letter (UI.md §6: 2 at 32), not a flat pixel count.
Theme.INK_SHARE = 0.07
-- Every size in the HUD is in pixels of a 1080-tall screen; the root's UIScale carries it to the real one.
Theme.DESIGN_HEIGHT = 1080
Theme.MIN_SCALE = 0.6
Theme.MAX_SCALE = 1.3
-- Distance from the screen's edges, and between stacked pieces.
Theme.EDGE = 16
Theme.GAP = 8

return table.freeze(Theme)
