-- The HUD's images, made by tools/uimatt/icons.py (Assets/ui/hud) and uploaded by group 34796361; its --upload writes
-- the ids here. The icons are one white atlas, tinted where they are drawn; a name in Cells is a cell in Icons.json.
local Icons = {}

Icons.IMAGE = "rbxassetid://103233382553940"
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
})
-- icons.py fits each glyph's longer side to this much of its cell.
Icons.GLYPH_SHARE = 116 / 128

return table.freeze(Icons)
