-- The HUD's and the lobby's images, made by tools/uimatt/icons.py (Assets/ui/hud) and uploaded by group 34796361; its
-- --upload writes the ids here. The icons are one white atlas, tinted where they are drawn; a name in Cells is a cell in Icons.json.
local Icons = {}

Icons.IMAGE = "rbxassetid://128300076561529"
Icons.CELL_SIZE = Vector2.new(128, 128)

-- The streaks on every panel's face: white, 1 px per design px. Its alpha is stretched to full range, so it is drawn
-- at PEAK (icons.py's TEXTURE_PEAK) to put the real strength back.
Icons.PANEL_TEXTURE = "rbxassetid://137723133621453"
Icons.PANEL_TEXTURE_SIZE = 1024
Icons.PANEL_TEXTURE_PEAK = 0.16

Icons.Cells = table.freeze({
	Squad = Vector2.new(0, 0),
	Settings = Vector2.new(128, 0),
	Boss = Vector2.new(256, 0),
	Barricade = Vector2.new(384, 0),
	HealAll = Vector2.new(0, 128),
	NukeAll = Vector2.new(128, 128),
	Skip = Vector2.new(256, 128),
	Coins = Vector2.new(384, 128),
	Health = Vector2.new(0, 256),
	Shotgun = Vector2.new(128, 256),
	Airstrike = Vector2.new(256, 256),
	Pack = Vector2.new(384, 256),
	Skull = Vector2.new(0, 384),
	Stopwatch = Vector2.new(128, 384),
	Gem = Vector2.new(256, 384),
	Robux = Vector2.new(384, 384),
	Advert = Vector2.new(0, 512),
	Arrow = Vector2.new(128, 512),
	Replay = Vector2.new(256, 512),
	Revive = Vector2.new(384, 512),
	Reset = Vector2.new(0, 640),
	Pencil = Vector2.new(128, 640),
	Warning = Vector2.new(256, 640),
	Music = Vector2.new(384, 640),
	Camera = Vector2.new(0, 768),
	Profile = Vector2.new(128, 768),
	-- The lobby's.
	Rank = Vector2.new(256, 768),
	Bolt = Vector2.new(384, 768),
	Shop = Vector2.new(0, 896),
	Gift = Vector2.new(128, 896),
	Spin = Vector2.new(256, 896),
	Friends = Vector2.new(384, 896),
	Rifle = Vector2.new(512, 0),
	Helmet = Vector2.new(640, 0),
	-- The weapons screen's.
	Check = Vector2.new(768, 0),
	Lock = Vector2.new(896, 0),
	Star = Vector2.new(512, 128),
	-- The quests screen's.
	Scroll = Vector2.new(640, 128),
	-- The spins screen's.
	Dice = Vector2.new(768, 128),
	Pointer = Vector2.new(896, 128),
	-- The codes button and screen's, drawn (icons.py's ticket()).
	Ticket = Vector2.new(512, 256),
	-- The index screen's MONSTERS card (BOSSES' is Boss).
	Zombie = Vector2.new(640, 256),
})
-- The weapons screen's stage floor (icons.py's floor()): his ellipse at 1:1, its ring opaque and its fill at a
-- quarter, so FLOOR_TRANSPARENCY puts both at his strengths.
Icons.FLOOR_OFFSET = Vector2.new(512, 936)
Icons.FLOOR_SIZE = Vector2.new(470, 84)
Icons.FLOOR_TRANSPARENCY = 0.55

-- The art behind a thing on show (Showcase, icons.py's showcase()): white drawings, tinted where they are drawn.
Icons.SHOWCASE = "rbxassetid://130717967552271"
Icons.ShowcaseCells = table.freeze({
	Rays = table.freeze({ Offset = Vector2.new(0, 0), Size = Vector2.new(512, 512) }),
	Dots = table.freeze({ Offset = Vector2.new(512, 0), Size = Vector2.new(512, 512) }),
	Reticle = table.freeze({ Offset = Vector2.new(0, 512), Size = Vector2.new(512, 512) }),
	Glow = table.freeze({ Offset = Vector2.new(512, 512), Size = Vector2.new(256, 256) }),
	Pulse = table.freeze({ Offset = Vector2.new(512, 768), Size = Vector2.new(256, 256) }),
	Beam = table.freeze({ Offset = Vector2.new(768, 512), Size = Vector2.new(256, 512) }),
})
-- The floors under it (icons.py's showcase_floor()): ellipses at the stages' floor shape, seen in perspective.
Icons.SHOWCASE_FLOOR = "rbxassetid://130779767541614"
Icons.ShowcaseFloorCells = table.freeze({
	Pad = table.freeze({ Offset = Vector2.new(0, 0), Size = Vector2.new(1024, 184) }),
	Dots = table.freeze({ Offset = Vector2.new(0, 192), Size = Vector2.new(1024, 184) }),
	Reticle = table.freeze({ Offset = Vector2.new(0, 384), Size = Vector2.new(1024, 184) }),
	Ring = table.freeze({ Offset = Vector2.new(0, 576), Size = Vector2.new(1024, 184) }),
	Glow = table.freeze({ Offset = Vector2.new(0, 768), Size = Vector2.new(1024, 184) }),
})

-- icons.py fits each glyph's longer side to this much of its cell.
Icons.GLYPH_SHARE = 116 / 128

-- BEGIN Pictures (Assets/ui/rendered/build.py writes this block)
-- The rendered icons: full colour, never tinted. key.py leaves a margin round each, so its longer side fills
-- PICTURE_SHARE of its cell.
Icons.PICTURE_CELL_SIZE = Vector2.new(256, 256)
Icons.PICTURE_SHARE = 0.88
Icons.Pictures = table.freeze({
	Gem = table.freeze({ Image = "rbxassetid://121967489305929", Offset = Vector2.new(0, 0) }),
	GemPile = table.freeze({ Image = "rbxassetid://121967489305929", Offset = Vector2.new(256, 0) }),
	GoldCoin = table.freeze({ Image = "rbxassetid://121967489305929", Offset = Vector2.new(512, 0) }),
	GoldSack = table.freeze({ Image = "rbxassetid://121967489305929", Offset = Vector2.new(768, 0) }),
	Rank = table.freeze({ Image = "rbxassetid://121967489305929", Offset = Vector2.new(0, 256) }),
	ShoppingBag = table.freeze({ Image = "rbxassetid://121967489305929", Offset = Vector2.new(256, 256) }),
	GiftBox = table.freeze({ Image = "rbxassetid://121967489305929", Offset = Vector2.new(512, 256) }),
	PrizeWheel = table.freeze({ Image = "rbxassetid://121967489305929", Offset = Vector2.new(768, 256) }),
	Scroll = table.freeze({ Image = "rbxassetid://121967489305929", Offset = Vector2.new(0, 512) }),
	MonsterBook = table.freeze({ Image = "rbxassetid://121967489305929", Offset = Vector2.new(256, 512) }),
	AddFriend = table.freeze({ Image = "rbxassetid://121967489305929", Offset = Vector2.new(512, 512) }),
	Squad = table.freeze({ Image = "rbxassetid://121967489305929", Offset = Vector2.new(768, 512) }),
	Ticket = table.freeze({ Image = "rbxassetid://121967489305929", Offset = Vector2.new(0, 768) }),
	Gear = table.freeze({ Image = "rbxassetid://121967489305929", Offset = Vector2.new(256, 768) }),
	Rifle = table.freeze({ Image = "rbxassetid://121967489305929", Offset = Vector2.new(512, 768) }),
	Helmet = table.freeze({ Image = "rbxassetid://121967489305929", Offset = Vector2.new(768, 768) }),
	ClassHuman = table.freeze({ Image = "rbxassetid://103977304531430", Offset = Vector2.new(0, 0) }),
	Zombie = table.freeze({ Image = "rbxassetid://103977304531430", Offset = Vector2.new(256, 0) }),
	ZombieKing = table.freeze({ Image = "rbxassetid://103977304531430", Offset = Vector2.new(512, 0) }),
	Bomb = table.freeze({ Image = "rbxassetid://103977304531430", Offset = Vector2.new(768, 0) }),
	Potion = table.freeze({ Image = "rbxassetid://103977304531430", Offset = Vector2.new(0, 256) }),
	UpgradeDamage = table.freeze({ Image = "rbxassetid://103977304531430", Offset = Vector2.new(256, 256) }),
	UpgradeFireRate = table.freeze({ Image = "rbxassetid://103977304531430", Offset = Vector2.new(512, 256) }),
	UpgradeRegeneration = table.freeze({ Image = "rbxassetid://103977304531430", Offset = Vector2.new(768, 256) }),
	UpgradeArmor = table.freeze({ Image = "rbxassetid://103977304531430", Offset = Vector2.new(0, 512) }),
	UpgradeGreed = table.freeze({ Image = "rbxassetid://103977304531430", Offset = Vector2.new(256, 512) }),
	UpgradeLifesteal = table.freeze({ Image = "rbxassetid://103977304531430", Offset = Vector2.new(512, 512) }),
	Skull = table.freeze({ Image = "rbxassetid://103977304531430", Offset = Vector2.new(768, 512) }),
	Stopwatch = table.freeze({ Image = "rbxassetid://103977304531430", Offset = Vector2.new(0, 768) }),
	Star = table.freeze({ Image = "rbxassetid://103977304531430", Offset = Vector2.new(256, 768) }),
	Check = table.freeze({ Image = "rbxassetid://103977304531430", Offset = Vector2.new(512, 768) }),
	Lock = table.freeze({ Image = "rbxassetid://103977304531430", Offset = Vector2.new(768, 768) }),
	Arrow = table.freeze({ Image = "rbxassetid://120452785674769", Offset = Vector2.new(0, 0) }),
	Replay = table.freeze({ Image = "rbxassetid://120452785674769", Offset = Vector2.new(256, 0) }),
	Skip = table.freeze({ Image = "rbxassetid://120452785674769", Offset = Vector2.new(512, 0) }),
	Pencil = table.freeze({ Image = "rbxassetid://120452785674769", Offset = Vector2.new(768, 0) }),
	Warning = table.freeze({ Image = "rbxassetid://120452785674769", Offset = Vector2.new(0, 256) }),
	Music = table.freeze({ Image = "rbxassetid://120452785674769", Offset = Vector2.new(256, 256) }),
	Camera = table.freeze({ Image = "rbxassetid://120452785674769", Offset = Vector2.new(512, 256) }),
	Player = table.freeze({ Image = "rbxassetid://120452785674769", Offset = Vector2.new(768, 256) }),
	Friends = table.freeze({ Image = "rbxassetid://120452785674769", Offset = Vector2.new(0, 512) }),
	Advert = table.freeze({ Image = "rbxassetid://120452785674769", Offset = Vector2.new(256, 512) }),
	Revive = table.freeze({ Image = "rbxassetid://120452785674769", Offset = Vector2.new(512, 512) }),
	Dice = table.freeze({ Image = "rbxassetid://120452785674769", Offset = Vector2.new(768, 512) }),
	Pointer = table.freeze({ Image = "rbxassetid://120452785674769", Offset = Vector2.new(0, 768) }),
	Chart = table.freeze({ Image = "rbxassetid://120452785674769", Offset = Vector2.new(256, 768) }),
	Magnifier = table.freeze({ Image = "rbxassetid://120452785674769", Offset = Vector2.new(512, 768) }),
	Trophy = table.freeze({ Image = "rbxassetid://120452785674769", Offset = Vector2.new(768, 768) }),
	UpArrow = table.freeze({ Image = "rbxassetid://97937910191948", Offset = Vector2.new(0, 0) }),
	Exclamation = table.freeze({ Image = "rbxassetid://97937910191948", Offset = Vector2.new(256, 0) }),
	ArrowUp = table.freeze({ Image = "rbxassetid://97937910191948", Offset = Vector2.new(512, 0) }),
	LockShackle = table.freeze({ Image = "rbxassetid://97937910191948", Offset = Vector2.new(768, 0) }),
	LockBody = table.freeze({ Image = "rbxassetid://97937910191948", Offset = Vector2.new(0, 256) }),
	Crown = table.freeze({ Image = "rbxassetid://97937910191948", Offset = Vector2.new(256, 256) }),
	Clover = table.freeze({ Image = "rbxassetid://97937910191948", Offset = Vector2.new(512, 256) }),
	GemHeap = table.freeze({ Image = "rbxassetid://97937910191948", Offset = Vector2.new(768, 256) }),
	GemChest = table.freeze({ Image = "rbxassetid://97937910191948", Offset = Vector2.new(0, 512) }),
	GemTrio = table.freeze({ Image = "rbxassetid://97937910191948", Offset = Vector2.new(256, 512) }),
	GemPouch = table.freeze({ Image = "rbxassetid://97937910191948", Offset = Vector2.new(512, 512) }),
	GemVault = table.freeze({ Image = "rbxassetid://97937910191948", Offset = Vector2.new(768, 512) }),
	GemDouble = table.freeze({ Image = "rbxassetid://97937910191948", Offset = Vector2.new(0, 768) }),
	XpWings = table.freeze({ Image = "rbxassetid://97937910191948", Offset = Vector2.new(256, 768) }),
	SpinPlus = table.freeze({ Image = "rbxassetid://97937910191948", Offset = Vector2.new(512, 768) }),
	StarterCrate = table.freeze({ Image = "rbxassetid://97937910191948", Offset = Vector2.new(768, 768) }),
	ArsenalCase = table.freeze({ Image = "rbxassetid://92269913666603", Offset = Vector2.new(0, 0) }),
	SurvivorVest = table.freeze({ Image = "rbxassetid://92269913666603", Offset = Vector2.new(256, 0) }),
	Flask = table.freeze({ Image = "rbxassetid://92269913666603", Offset = Vector2.new(512, 0) }),
	PotionBottle = table.freeze({ Image = "rbxassetid://92269913666603", Offset = Vector2.new(768, 0) }),
	PotionRack = table.freeze({ Image = "rbxassetid://92269913666603", Offset = Vector2.new(0, 256) }),
	Cauldron = table.freeze({ Image = "rbxassetid://92269913666603", Offset = Vector2.new(256, 256) }),
	EnergyBolt = table.freeze({ Image = "rbxassetid://92269913666603", Offset = Vector2.new(512, 256) }),
	Soul = table.freeze({ Image = "rbxassetid://92269913666603", Offset = Vector2.new(768, 256) }),
	HudScreen = table.freeze({ Image = "rbxassetid://92269913666603", Offset = Vector2.new(0, 512) }),
	InviteGift = table.freeze({ Image = "rbxassetid://92269913666603", Offset = Vector2.new(256, 512) }),
	UpgradeHaste = table.freeze({ Image = "rbxassetid://92269913666603", Offset = Vector2.new(512, 512) }),
	UpgradeDiscount = table.freeze({ Image = "rbxassetid://92269913666603", Offset = Vector2.new(768, 512) }),
	UpgradeSpeed = table.freeze({ Image = "rbxassetid://92269913666603", Offset = Vector2.new(0, 768) }),
	UpgradeOvercharge = table.freeze({ Image = "rbxassetid://92269913666603", Offset = Vector2.new(256, 768) }),
})
-- END Pictures

return table.freeze(Icons)
