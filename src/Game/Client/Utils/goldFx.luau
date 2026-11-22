-- A bought Gold pack as it is seen on the buyer, in the house look (VFX.md 30 and 38): a white-hot heart in a gold
-- bloom, a fountain of gold pixels thrown over the head that falls back, a fat square ring thrown out along the
-- floor and gold stud bricks bouncing out of the body; then, as the last of the pack's coins lands
-- (CoinFlight.Shower.LAST), a second smaller strike on the body. The coins themselves are CoinsController's.
-- ItemsController says who and steps it. The look is on templates at ReplicatedStorage.Effects.GoldFx, a place
-- instance, not Rojo, made by Assets/effects/items (its README.md). Once a purchase: each buyer gets copies of his
-- own, destroyed when they are spent.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local thrownPieces = require(script.Parent.Parent.Parent.GlobalClient.Utils.thrownPieces)
local CoinFlight = require(script.Parent.coinFlight)

local goldFx = {}

local KIT = "GoldFx"

local Tune = table.freeze({
	-- An R6 root's centre over its feet, and the chest over the root.
	ROOT_HEIGHT = 3,
	CHEST = Vector3.new(0, 1, 0),
	-- Over the floor, so a flat ring never fights it for depth.
	LIFT = 0.08,
	-- What the burst throws, a layer: a plain pack's, then a big one's.
	FOUNTAIN = NumberRange.new(22, 28),
	FOUNTAIN_BIG = NumberRange.new(40, 48),
	FLECKS = NumberRange.new(10, 14),
	FLECKS_BIG = NumberRange.new(18, 24),
	-- The big pack's fountain comes again this long after the first, so it is a jet and not one puff.
	SECOND_FOUNTAIN_SECONDS = 0.16,
	-- The closing strike.
	SPRAY = NumberRange.new(12, 16),
	SPRAY_BIG = NumberRange.new(20, 26),
	-- Gold bricks out of the body: how many, thrown out and up at these speeds (studs a second), and the most in the
	-- air at once over every buyer.
	BRICKS = NumberRange.new(5, 7),
	BRICKS_BIG = NumberRange.new(12, 15),
	BRICK_OUT = NumberRange.new(5, 15),
	BRICK_UP = NumberRange.new(16, 30),
	PIECE_PARTS = 32,
	-- The light the burst throws on the world, a blink; only near the camera, where it is seen to land.
	LIGHT_COLOR = Color3.fromRGB(255, 214, 120),
	LIGHT_RANGE = 26,
	LIGHT_BRIGHTNESS = 5,
	LIGHT_SECONDS = 0.08,
	LIGHT_REACH = 90,
	-- A buyer's copies go this long after the purchase: past the strike's longest particle.
	LIFE = CoinFlight.Shower.LAST + 1.4,
})

-- One purchase being drawn: the buyer's copies of the templates and the beats still to come (os.clock, 0 once done).
type TCast = {
	Feet: Attachment,
	Heart: Attachment,
	Light: PointLight?,
	IsBig: boolean,
	LightOffAt: number,
	SecondAt: number,
	StrikeAt: number,
	EndsAt: number,
}

type TKit = { Feet: Attachment, Heart: Attachment, Bricks: { BasePart } }

local random = Random.new()
local pieces = thrownPieces.NewPool("GoldPieces", Tune.PIECE_PARTS)
local kit: TKit? = nil
local hasWarned = false
local casts: { TCast } = {}

-- The kit's templates; nil (said once) while they are not in the place, when a pack draws nothing here. A miss is
-- asked again, so templates that reach the client late are still found.
local function kitOf(): TKit?
	if kit then return kit end

	local effects = ReplicatedStorage:FindFirstChild("Effects")
	local templates = if effects then effects:FindFirstChild(KIT) else nil
	local feet = if templates then templates:FindFirstChild("Feet") else nil
	local heart = if templates then templates:FindFirstChild("Heart") else nil
	if not feet or not heart or not feet:IsA("Attachment") or not heart:IsA("Attachment") then
		if not hasWarned then
			hasWarned = true
			warn(`[goldFx] no ReplicatedStorage.Effects.{KIT}; a Gold pack draws only its coins`)
		end
		return nil
	end

	local bricks = {}
	local debris = (templates :: Instance):FindFirstChild("Debris")
	if debris then
		for _, child in debris:GetChildren() do
			if child:IsA("BasePart") then bricks[#bricks + 1] = child end
		end
	end

	local found = { Feet = feet, Heart = heart, Bricks = bricks }
	kit = found
	return found
end

local function emit(attachment: Attachment, layer: string, count: number)
	local emitter = attachment:FindFirstChild(layer)
	if emitter and emitter:IsA("ParticleEmitter") then emitter:Emit(count) end
end

local function roll(range: NumberRange): number
	return random:NextInteger(range.Min, range.Max)
end

-- Gold bricks out of the chest all round, landing on the floor under the buyer.
local function throwBricks(found: TKit, root: BasePart, isBig: boolean)
	local bricks = found.Bricks
	if #bricks == 0 then return end
	local chest = root.Position + Tune.CHEST
	local distance = (Workspace.CurrentCamera.CFrame.Position - chest).Magnitude
	local count = thrownPieces.Allowed(pieces, roll(if isBig then Tune.BRICKS_BIG else Tune.BRICKS), distance)
	if count == 0 then return end

	local floor = thrownPieces.FloorUnder(chest, pieces.FloorParams)
	local turn = random:NextNumber(0, math.pi * 2)
	for i = 1, count do
		local angle = turn + (i + random:NextNumber(-0.4, 0.4)) / count * math.pi * 2
		local out = random:NextNumber(Tune.BRICK_OUT.Min, Tune.BRICK_OUT.Max)
		local velocity = Vector3.new(
			math.cos(angle) * out,
			random:NextNumber(Tune.BRICK_UP.Min, Tune.BRICK_UP.Max),
			math.sin(angle) * out
		)
		thrownPieces.Throw(pieces, bricks[random:NextInteger(1, #bricks)], nil, chest, velocity, floor)
	end
end

-- The buyer whose root is `root` has his pack: the burst rides him, and the strike follows on the last coin's beat.
function goldFx.Cast(root: BasePart, isBig: boolean)
	local found = kitOf()
	if not found then return end

	local feet = found.Feet:Clone()
	feet.CFrame = CFrame.new(0, Tune.LIFT - Tune.ROOT_HEIGHT, 0)
	feet.Parent = root
	local heart = found.Heart:Clone()
	heart.CFrame = CFrame.new(Tune.CHEST)
	heart.Parent = root
	emit(feet, "Wash", 1)
	emit(feet, if isBig then "ShockBig" else "Shock", 1)
	emit(heart, "Bloom", 1)
	emit(heart, "Core", 1)
	emit(heart, "Fountain", roll(if isBig then Tune.FOUNTAIN_BIG else Tune.FOUNTAIN))
	emit(heart, "Flecks", roll(if isBig then Tune.FLECKS_BIG else Tune.FLECKS))
	throwBricks(found, root, isBig)

	local now = os.clock()
	local light: PointLight? = nil
	if (Workspace.CurrentCamera.CFrame.Position - root.Position).Magnitude <= Tune.LIGHT_REACH then
		local made = Instance.new("PointLight")
		made.Color = Tune.LIGHT_COLOR
		made.Range = Tune.LIGHT_RANGE
		made.Brightness = Tune.LIGHT_BRIGHTNESS
		made.Shadows = false
		made.Parent = heart
		light = made
	end

	casts[#casts + 1] = {
		Feet = feet,
		Heart = heart,
		Light = light,
		IsBig = isBig,
		LightOffAt = now + Tune.LIGHT_SECONDS,
		SecondAt = if isBig then now + Tune.SECOND_FOUNTAIN_SECONDS else 0,
		StrikeAt = now + CoinFlight.Shower.LAST,
		EndsAt = now + Tune.LIFE,
	}
end

-- Once a frame: the bricks in the air, each purchase's beats as they come, and the copies of one that is spent.
function goldFx.Step()
	thrownPieces.Step(pieces)
	if #casts == 0 then return end

	local now = os.clock()
	for index = #casts, 1, -1 do
		local cast = casts[index]
		local light = cast.Light
		if light and now >= cast.LightOffAt then
			cast.Light = nil
			light:Destroy()
		end

		if cast.SecondAt > 0 and now >= cast.SecondAt then
			cast.SecondAt = 0
			emit(cast.Heart, "Fountain", roll(Tune.FOUNTAIN))
		end

		if cast.StrikeAt > 0 and now >= cast.StrikeAt then
			cast.StrikeAt = 0
			emit(cast.Feet, "Echo", 1)
			emit(cast.Heart, "Pop", 1)
			emit(cast.Heart, "Spray", roll(if cast.IsBig then Tune.SPRAY_BIG else Tune.SPRAY))
		end

		if now < cast.EndsAt then continue end
		-- A body that left took its copies with it: destroying them again is harmless.
		cast.Feet:Destroy()
		cast.Heart:Destroy()
		casts[index] = casts[#casts]
		casts[#casts] = nil
	end
end

return goldFx
