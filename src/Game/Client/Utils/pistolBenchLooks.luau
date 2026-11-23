-- What `pistolbench` stands beside the plain tracers (VFX.md sections 1 and 30): the game's own kit, then the looks
-- that lost to it. Each loser is a kit of its own in the place (Assets/effects/pistol/bench), drawn only on the bench,
-- so its counts are here and not in gunFx. Delete this file with the bench.
local gunFx = require(script.Parent.Parent.Parent.GlobalClient.Utils.gunFx)

local ONE = NumberRange.new(1)
local GOLD = Color3.fromRGB(255, 214, 20)

local looks: { { Name: string, Kit: string, Look: gunFx.TLook? } } = {
	{ Name = "Pixels (in game)", Kit = "PistolFx" },
	{
		Name = "Bubble",
		Kit = "PistolFxBubble",
		Look = {
			Light = GOLD,
			Speed = 300,
			Length = 5,
			SpinAxis = Vector3.zAxis,
			SpinSpeed = 0,
			Muzzle = {
				Bloom = ONE,
				Core = ONE,
				RingA = ONE,
				RingB = ONE,
				Bubbles = NumberRange.new(6, 9),
				Puffs = NumberRange.new(1, 2),
			},
			Impact = {
				Wash = ONE,
				Core = ONE,
				RingA = ONE,
				RingB = ONE,
				Bubbles = NumberRange.new(7, 10),
				Puffs = NumberRange.new(2, 3),
			},
			Hit = { Core = ONE, RingA = ONE, Bubbles = NumberRange.new(5, 7) },
		},
	},
	{
		Name = "Spark",
		Kit = "PistolFxSpark",
		Look = {
			Light = GOLD,
			Speed = 340,
			Length = 6,
			SpinAxis = Vector3.zAxis,
			SpinSpeed = 0,
			Muzzle = {
				Bloom = ONE,
				Core = ONE,
				Flash = ONE,
				Tongue = ONE,
				Sparks = NumberRange.new(7, 11),
				Embers = NumberRange.new(2, 4),
				Puffs = NumberRange.new(1, 2),
			},
			Impact = {
				Wash = ONE,
				Core = ONE,
				Flash = ONE,
				Ring = ONE,
				Sparks = NumberRange.new(8, 12),
				Embers = NumberRange.new(3, 5),
				Puffs = NumberRange.new(2, 3),
			},
			Hit = {
				Core = ONE,
				Flash = ONE,
				Ring = ONE,
				Sparks = NumberRange.new(6, 9),
				Embers = NumberRange.new(2, 3),
			},
		},
	},
	{
		Name = "Stars",
		Kit = "PistolFxStars",
		Look = {
			Light = Color3.fromRGB(255, 228, 60),
			Speed = 340,
			Length = 6,
			SpinAxis = Vector3.zAxis,
			SpinSpeed = 40,
			Muzzle = {
				Bloom = ONE,
				Core = ONE,
				Flash = ONE,
				Stars = NumberRange.new(4, 6),
				Embers = NumberRange.new(2, 3),
				Puffs = NumberRange.new(1, 2),
			},
			Impact = {
				Wash = ONE,
				Core = ONE,
				Flash = ONE,
				Ring = ONE,
				Stars = NumberRange.new(6, 9),
				Embers = NumberRange.new(2, 4),
				Puffs = NumberRange.new(2, 3),
			},
			Hit = { Core = ONE, Flash = ONE, Ring = ONE, Stars = NumberRange.new(4, 6) },
		},
	},
	{
		Name = "Studs",
		Kit = "PistolFxStuds",
		Look = {
			Light = GOLD,
			Speed = 320,
			Length = 6,
			SpinAxis = Vector3.yAxis,
			SpinSpeed = 26,
			Muzzle = {
				Bloom = ONE,
				Core = ONE,
				Ring = ONE,
				Pixels = NumberRange.new(5, 8),
				Puffs = NumberRange.new(1, 2),
			},
			Impact = {
				Wash = ONE,
				Core = ONE,
				Frame = ONE,
				Pixels = NumberRange.new(7, 10),
				Puffs = NumberRange.new(2, 3),
			},
			Hit = { Core = ONE, Ring = ONE, Pixels = NumberRange.new(5, 7) },
		},
	},
}

return table.freeze(looks)
