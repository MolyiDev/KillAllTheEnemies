-- What `bulletbench` stands beside the game's bullet, the Comet (VFX.md 1 and 34): the styles that lost to it, at
-- ReplicatedStorage.Effects.BulletStyles (Assets/effects/bullets), each drawn in every gun's own hue. Their numbers are
-- here and not in gunFx's LOOKS. Delete this file with the bench.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local gunFx = require(script.Parent.Parent.Parent.GlobalClient.Utils.gunFx)

local bulletBenchStyles = {}

bulletBenchStyles.STYLES = table.freeze({ "Dart", "Bolt", "Pixel", "Train", "Spiral", "Gate" })

-- How long the Dart's streak ran behind it, by kit, as the game drew it before the Comet.
local DART_LENGTH = table.freeze({ PistolFx = 6, RifleFx = 9, SniperFx = 22, MinigunFx = 5, ShotgunFx = 3.5 })
-- Radians a second a Spiral's pixels circle: about six turns, so a 60 stud shot shows one.
local ORBIT_SPEED = 40

-- The style's bullet for `kit`, or nil while the styles are not in the place.
local function bulletOf(kit: string, style: string): Instance?
	local effects = ReplicatedStorage:FindFirstChild("Effects")
	if not effects then return nil end
	local styles = effects:FindFirstChild("BulletStyles")
	if not styles then return nil end
	local folder = styles:FindFirstChild(style)
	if not folder then return nil end
	return folder:FindFirstChild(kit)
end

-- Draws the kit `name` as `kit` with its bullet in `style`. False while the style is not in the place.
function bulletBenchStyles.Use(kit: string, style: string, name: string): boolean
	local bullet = bulletOf(kit, style)
	if not bullet then return false end

	gunFx.SetBullet(name, kit, bullet, { Length = DART_LENGTH[kit], OrbitSpeed = ORBIT_SPEED })
	return true
end

return bulletBenchStyles
