-- What a blow sounds and looks like on an enemy body: one shared palette for every type, tiered by how hard the blow
-- was (a hit, a kill, an overkill, and a wipe layer over the top), since a round is one kind of creature dying hundreds
-- of times and the eye and ear have to be told how hard, not what. A type that names its own clips (TEnemy.Sounds)
-- speaks on top. A burst is glowing pixels of the body's skin and stud pieces in its own colours knocked off it
-- (TEnemy.Colors; the pieces are GlobalClient/Utils/thrownPieces). Its look is authored on templates at
-- ReplicatedStorage.Effects.EnemyFx, a place instance, not Rojo, made by Assets/effects/enemy (its README.md).
--
-- Every entry point is an event already capped upstream (EnemiesController's per-body hit debounce, one cry per
-- volley, the bursts' own cap a frame), so the cross-module call is paid a handful of times a frame, never per body.
-- Up to 255 bodies are hit at once: nothing here makes a light or a Highlight, and the piece pool is the budget.
-- No --!native: this is engine calls end to end.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local thrownPieces = require(script.Parent.Parent.Parent.GlobalClient.Utils.thrownPieces)
local TData = require(ReplicatedStorage.Types.TData)

local Effects = ReplicatedStorage:WaitForChild("Effects")

local HIT_VOICES_EACH = 3
local KILL_VOICES_EACH = 3
local MASS_VOICES_EACH = 2
local HIT_GROUP = "Enemies"
local KILL_GROUP = "Enemies.Kills"
local DEATH_SOUND_VOLUME_SCALE = 0.6
-- Kills on one frame past which the gore stops saying how big the moment was and a wipe layer plays over it, once.
local MASS_KILL_BIG = 8
local MASS_KILL_HUGE = 18

local KIT = "EnemyFx"
local ONE = NumberRange.new(1)
local WHITE = Color3.new(1, 1, 1)

local Tune = table.freeze({
	-- Copies of each burst template, taken in turn. A copy is recoloured and resized to the body it is thrown on,
	-- which does the same to what still flies from its last throw: in a mixed crowd under heavy fire, a few pixels
	-- changing colour mid-flight.
	SLOTS = 12,
	-- Bursts a frame. Hits are the flood and capped apart, so a volley's hits never starve the kills it caused: past a
	-- handful they stack inside one blast where nobody can tell which were skipped.
	MAX_HIT_BURSTS_PER_FRAME = 4,
	MAX_KILL_BURSTS_PER_FRAME = 4,
	MAX_END_BURSTS_PER_FRAME = 6,
	BURST_RANGE = 250,
	-- Stud pieces in the air at once, over the whole crowd. A burst throws fewer as this fills
	-- (thrownPieces.Allowed), so a wave dying together keeps the pieces it has instead of churning them.
	PIECE_PARTS = 96,
	-- The height the templates and piece counts are sized for (the R6 zombie), and the step a burst's scale is
	-- rounded to, so a crowd of one size never rewrites a Size sequence.
	REFERENCE_HEIGHT = 5,
	SCALE_STEP = 0.25,
	-- A blow's burst sits this share of the body's half width toward where the blow came from (the side the shooter
	-- sees), and leans this much back that way off straight up.
	SURFACE_SHARE = 0.7,
	SPRAY_LEAN = 0.45,
	-- A blow's pieces start within this of its burst, and are the skin's colour this often, else the top's.
	PIECE_JITTER = 0.4,
	BLOW_SKIN_CHANCE = 0.5,
	-- A body coming apart throws its pieces from within this share of its half width round its middle.
	WHOLE_SPREAD = 0.5,
	-- An R6 body by height: legs to here, head from here; between them a piece is the top's, or an arm's skin this
	-- often. A body coming apart throws each slice in what it wears.
	LEGS_SHARE = 0.4,
	HEAD_SHARE = 0.8,
	ARM_CHANCE = 0.3,
	-- A piece is thrown at least this share of its tier's Side, so none drops straight down through the body.
	SIDE_LEAST = 0.3,
	-- Pixels are born white-hot for this share of their life, then the skin's colour, this far toward white; a puff
	-- is paler, since it is paint and not light.
	HOT = Color3.fromRGB(255, 248, 215),
	HOT_SHARE = 0.12,
	PIXEL_LIGHTEN = 0.25,
	PUFF_LIGHTEN = 0.5,
	NO_COLORS = Color3.fromRGB(150, 150, 150),
})

-- One rung of the ladder: which template it throws and how many of each layer (a range, so no two bursts match; an
-- emitter has no burst count of its own), and its stud pieces: how many off a REFERENCE_HEIGHT body and how fast,
-- studs a second (Side any way across the floor, Out away from where the blow came from, Lift up). IsWhole takes a
-- piece from every slice of the body instead of from where the blow landed. Everything else is on the templates.
type TTier = {
	Burst: string,
	Layers: { [string]: NumberRange },
	Pieces: NumberRange,
	Side: number,
	Out: NumberRange,
	Lift: NumberRange,
	IsWhole: boolean,
}

local HIT_LAYERS = table.freeze({ Core = ONE, Pixels = NumberRange.new(6, 9) })
local TIERS: { [string]: TTier } = table.freeze({
	Hit = table.freeze({
		Burst = "Hit",
		Layers = HIT_LAYERS,
		Pieces = NumberRange.new(2, 3),
		Side = 9,
		Out = NumberRange.new(-2, 6),
		Lift = NumberRange.new(11, 17),
		IsWhole = false,
	}),
	-- The killing blow's light is a hit's (a kill that outshines a hit reads as the effect scaling with the health
	-- left); what says it killed is the body falling and more of it coming off.
	Kill = table.freeze({
		Burst = "Hit",
		Layers = HIT_LAYERS,
		Pieces = NumberRange.new(5, 6),
		Side = 11,
		Out = NumberRange.new(0, 9),
		Lift = NumberRange.new(12, 20),
		IsWhole = false,
	}),
	Overkill = table.freeze({
		Burst = "Overkill",
		Layers = table.freeze({
			Bloom = ONE,
			Core = ONE,
			Frame = ONE,
			Pixels = NumberRange.new(16, 22),
			Flecks = NumberRange.new(6, 9),
			Puffs = NumberRange.new(4, 6),
		}),
		Pieces = NumberRange.new(13, 16),
		Side = 16,
		Out = NumberRange.new(2, 10),
		Lift = NumberRange.new(10, 26),
		IsWhole = true,
	}),
	Vanish = table.freeze({
		Burst = "Vanish",
		Layers = table.freeze({ Puffs = NumberRange.new(7, 9), Pixels = NumberRange.new(5, 7) }),
		Pieces = NumberRange.new(4, 5),
		Side = 5,
		Out = NumberRange.new(0, 0),
		Lift = NumberRange.new(2, 9),
		IsWhole = true,
	}),
})

-- One copy of a template under Workspace.Terrain (where an attachment's CFrame is its world CFrame, so there is no
-- host part to move): its emitters in the pool's layer order, and what it was last sized and coloured for.
type TBurst = {
	Attachment: Attachment,
	Emitters: { ParticleEmitter },
	Pixels: ParticleEmitter?,
	Puffs: ParticleEmitter?,
	Scale: number,
	Look: TBodyLook?,
}

-- Copies of one template, taken in turn, made on their first use. Its layers are parallel arrays (name, fewest and
-- most thrown), so a burst is a plain loop of Emit calls with nothing looked up by name. Sizes holds each layer's
-- Size sequence at each body scale, built the first time a body of that scale is hit: a copy that changes scale
-- writes a sequence it already has.
type TBurstPool = {
	Template: Attachment,
	Names: { string },
	Least: { number },
	Most: { number },
	Sizes: { [number]: { NumberSequence } },
	Slots: { TBurst },
	Next: number,
}

-- The kit's templates, found once.
type TKit = { Bricks: { BasePart }, Pools: { [string]: TBurstPool } }

-- A type's body as its bursts draw it: its colours (TEnemy.Colors) and its scale against REFERENCE_HEIGHT.
type TBodyLook = {
	Pixels: ColorSequence,
	Puffs: ColorSequence,
	Skin: Color3,
	Top: Color3,
	Legs: Color3,
	Scale: number,
}

local EnemyImpacts = {}

-- Levels are baked onto each Sound at the gain its take was mixed at, so the balance inside a tier lives in the tree.
local hitPools = SoundsCore.CreateVariantPools(HIT_GROUP, "Hit", HIT_VOICES_EACH)
local killPools = SoundsCore.CreateVariantPools(KILL_GROUP, "Kill", KILL_VOICES_EACH)
local overkillPools = SoundsCore.CreateVariantPools(KILL_GROUP, "Overkill", MASS_VOICES_EACH)
local killBigPools = SoundsCore.CreateVariantPools(KILL_GROUP, "KillBig", MASS_VOICES_EACH)
local killHugePools = SoundsCore.CreateVariantPools(KILL_GROUP, "KillHuge", MASS_VOICES_EACH)

local killsThisFrame = 0
local massKillTier = 0
local hitBursts = 0
local killBursts = 0
local endBursts = 0

local random = Random.new()
local pieces = thrownPieces.NewPool("EnemyPieces", Tune.PIECE_PARTS)
-- Read once a frame (BeginFrame): every burst asks how far it is.
local cameraPosition = Vector3.zero
local kit: TKit? = nil
local hasWarned = false
local looks: { [number]: TBodyLook } = {}

-- A type's own Hit plays positionally instead of the palette; nil back means its clip is not in the tree yet, so the
-- palette still answers rather than silence. `heardFrom` is where the palette fades from: the body, or the camera for
-- the player's own blow, which is the answer to their shot and must not thin out with range.
function EnemyImpacts.PlayHit(enemyData: TData.TEnemy?, position: Vector3, heardFrom: Vector3)
	local sounds = if enemyData then enemyData.Sounds else nil
	if sounds and sounds.Hit and SoundsCore.PlayWorldNamed(sounds.Group, sounds.Hit, position) then return end

	SoundsCore.PlayPooledRandom(hitPools, heardFrom)
end

-- The gore plays under a type's own death cry, not instead of it: the cry says what died, the gore what the blow did.
-- An overkill has its own, bigger take in place of the kill's.
function EnemyImpacts.PlayDeath(enemyData: TData.TEnemy?, position: Vector3, heardFrom: Vector3, isOverkill: boolean)
	local sounds = if enemyData then enemyData.Sounds else nil
	if sounds and sounds.Death then
		SoundsCore.PlayWorldNamed(sounds.Group, sounds.Death, position, DEATH_SOUND_VOLUME_SCALE)
	end

	SoundsCore.PlayPooledRandom(if isOverkill and #overkillPools > 0 then overkillPools else killPools, heardFrom)
end

-- `count` is how many the server said died, not how many cries played (a volley gets one). Each threshold plays its
-- layer once a frame: there is no voice limiter to swallow a layer fired per kill past it.
function EnemyImpacts.AddKills(count: number, position: Vector3)
	killsThisFrame += count
	if massKillTier < 2 and killsThisFrame >= MASS_KILL_HUGE then
		massKillTier = 2
		SoundsCore.PlayPooledRandom(killHugePools, position)
	elseif massKillTier < 1 and killsThisFrame > MASS_KILL_BIG then
		massKillTier = 1
		SoundsCore.PlayPooledRandom(killBigPools, position)
	end
end

local function emitterNamed(parent: Instance, name: string): ParticleEmitter?
	local child = parent:FindFirstChild(name)
	return if child and child:IsA("ParticleEmitter") then child else nil
end

local function newPool(template: Attachment, layers: { [string]: NumberRange }): TBurstPool
	local names, least, most, sizes = {}, {}, {}, {}
	for name, count in layers do
		local emitter = emitterNamed(template, name)
		if not emitter then continue end
		local index = #names + 1
		names[index] = name
		least[index] = count.Min
		most[index] = count.Max
		sizes[index] = emitter.Size
	end

	return {
		Template = template,
		Names = names,
		Least = least,
		Most = most,
		Sizes = { [1] = sizes },
		Slots = {},
		Next = 1,
	}
end

-- The kit's templates; nil (said once) while they are not in the place: the bursts are then not drawn, and the game
-- runs without them rather than broken before the art lands. A miss is asked again, so templates that reach the
-- client late are still found.
local function kitOf(): TKit?
	if kit then return kit end

	local templates = Effects:FindFirstChild(KIT)
	if not templates then
		if not hasWarned then
			hasWarned = true
			warn(`[EnemyImpacts] no ReplicatedStorage.Effects.{KIT}; enemy bursts are not drawn`)
		end
		return nil
	end

	local bricks = {}
	local debris = templates:FindFirstChild("Debris")
	if debris then
		for _, child in debris:GetChildren() do
			if child:IsA("BasePart") then bricks[#bricks + 1] = child end
		end
	end

	-- Two tiers may throw one template (a kill's light is a hit's): it is one pool.
	local pools = {}
	for _, tier in TIERS do
		local template = templates:FindFirstChild(tier.Burst)
		if pools[tier.Burst] or not template or not template:IsA("Attachment") then continue end
		pools[tier.Burst] = newPool(template, tier.Layers)
	end

	local found = { Bricks = bricks, Pools = pools }
	kit = found
	return found
end

-- `height` is the body's (its aim shape's): a type's is the same every time, so its scale is worked out once.
local function lookOf(enemyData: TData.TEnemy, height: number): TBodyLook
	local known = looks[enemyData.Id]
	if known then return known end

	local colors = enemyData.Colors
	local skin = if colors then colors.Skin else Tune.NO_COLORS
	local lit = skin:Lerp(WHITE, Tune.PIXEL_LIGHTEN)
	local look = {
		Pixels = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Tune.HOT),
			ColorSequenceKeypoint.new(Tune.HOT_SHARE, lit),
			ColorSequenceKeypoint.new(1, lit),
		}),
		Puffs = ColorSequence.new(skin:Lerp(WHITE, Tune.PUFF_LIGHTEN)),
		Skin = skin,
		Top = if colors then colors.Top else Tune.NO_COLORS,
		Legs = if colors then colors.Legs else Tune.NO_COLORS,
		Scale = math.max(math.round(height / Tune.REFERENCE_HEIGHT / Tune.SCALE_STEP), 1) * Tune.SCALE_STEP,
	}
	looks[enemyData.Id] = look
	return look
end

local function newBurst(pool: TBurstPool): TBurst
	local attachment = pool.Template:Clone()
	local emitters = table.create(#pool.Names)
	for index, name in pool.Names do
		emitters[index] = emitterNamed(attachment, name) :: ParticleEmitter
	end

	local burst = {
		Attachment = attachment,
		Emitters = emitters,
		Pixels = emitterNamed(attachment, "Pixels"),
		Puffs = emitterNamed(attachment, "Puffs"),
		Scale = 1,
		Look = nil,
	}
	attachment.Parent = Workspace.Terrain
	return burst
end

-- Every layer's Size at `scale`, kept on the pool.
local function sizesAt(pool: TBurstPool, scale: number): { NumberSequence }
	local known = pool.Sizes[scale]
	if known then return known end

	local base = pool.Sizes[1]
	local sizes = table.create(#base)
	for index, sequence in base do
		local keypoints = sequence.Keypoints
		local scaled = table.create(#keypoints)
		for i, key in keypoints do
			scaled[i] = NumberSequenceKeypoint.new(key.Time, key.Value * scale, key.Envelope * scale)
		end
		sizes[index] = NumberSequence.new(scaled)
	end

	pool.Sizes[scale] = sizes
	return sizes
end

-- Throws the pool's next copy at `frame` (+Y is the way its layers fly), sized and coloured for the body. A copy
-- writes its sizes and colours only when the body differs from its last one's.
local function fire(pool: TBurstPool, look: TBodyLook, frame: CFrame)
	local slot = pool.Next
	pool.Next = slot % Tune.SLOTS + 1
	local burst = pool.Slots[slot]
	if not burst then
		burst = newBurst(pool)
		pool.Slots[slot] = burst
	end

	local emitters = burst.Emitters
	if burst.Scale ~= look.Scale then
		burst.Scale = look.Scale
		local sizes = sizesAt(pool, look.Scale)
		for i, emitter in emitters do
			emitter.Size = sizes[i]
		end
	end
	if burst.Look ~= look then
		burst.Look = look
		if burst.Pixels then burst.Pixels.Color = look.Pixels end
		if burst.Puffs then burst.Puffs.Color = look.Puffs end
	end

	burst.Attachment.CFrame = frame
	local least, most = pool.Least, pool.Most
	for i, emitter in emitters do
		local low, high = least[i], most[i]
		emitter:Emit(if low == high then low else random:NextInteger(low, high))
	end
end

-- A frame at `position` with +Y on `up`.
local function facing(position: Vector3, up: Vector3): CFrame
	local side = if math.abs(up.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	return CFrame.fromMatrix(position, side:Cross(up).Unit, up)
end

-- What the body wears at `share` of its height.
local function colorAt(look: TBodyLook, share: number): Color3
	if share < Tune.LEGS_SHARE then return look.Legs end
	if share > Tune.HEAD_SHARE or random:NextNumber() < Tune.ARM_CHANCE then return look.Skin end
	return look.Top
end

-- One burst of `tier` on a body, and its pieces: `chest` and `aim` are the body's aim point and shape
-- (EnemiesCore.AimShape: chest height, height, half width), `from` where the blow came from when somebody dealt it.
local function burstOn(tier: TTier, enemyData: TData.TEnemy, chest: Vector3, aim: vector, from: Vector3?)
	local found = kitOf()
	if not found then return end
	local distance = (cameraPosition - chest).Magnitude
	if distance > Tune.BURST_RANGE then return end

	local look = lookOf(enemyData, aim.y)
	local flat = if from then Vector3.new(chest.X - from.X, 0, chest.Z - from.Z) else Vector3.zero
	local away = if flat.Magnitude > 0.1 then flat.Unit else nil
	-- A body going whole bursts from its middle, its ring flat like the floor's studs. A blow bursts on the side it
	-- came from and fountains up and back that way, where whoever dealt it sees it instead of the body's back.
	local frame = CFrame.new(chest)
	if away and not tier.IsWhole then
		local up = (Vector3.yAxis - away * Tune.SPRAY_LEAN).Unit
		frame = facing(chest - away * (aim.z * Tune.SURFACE_SHARE), up)
	end
	local pool = found.Pools[tier.Burst]
	if pool then fire(pool, look, frame) end

	local bricks = found.Bricks
	local wanted = math.round(random:NextInteger(tier.Pieces.Min, tier.Pieces.Max) * look.Scale)
	local count = thrownPieces.Allowed(pieces, wanted, distance)
	if count == 0 or #bricks == 0 then return end

	-- The body stands on its floor, so no piece looks for one until it comes down.
	local feet = chest.Y - aim.x
	local origin = frame.Position
	local spread = aim.z * Tune.WHOLE_SPREAD
	local side, out, lift = tier.Side, tier.Out, tier.Lift
	for i = 1, count do
		local position, color
		if tier.IsWhole then
			-- A piece from each slice of the body, bottom to top.
			local share = (i - random:NextNumber()) / count
			position = Vector3.new(
				chest.X + random:NextNumber(-spread, spread),
				feet + share * aim.y,
				chest.Z + random:NextNumber(-spread, spread)
			)
			color = colorAt(look, share)
		else
			position = origin + random:NextUnitVector() * Tune.PIECE_JITTER
			color = if random:NextNumber() < Tune.BLOW_SKIN_CHANCE then look.Skin else look.Top
		end

		local turn = random:NextNumber(0, math.pi * 2)
		local velocity = Vector3.new(math.cos(turn), 0, math.sin(turn))
				* random:NextNumber(side * Tune.SIDE_LEAST, side)
			+ Vector3.new(0, random:NextNumber(lift.Min, lift.Max), 0)
		if away then
			velocity += away * random:NextNumber(out.Min, out.Max)
		end
		thrownPieces.Throw(pieces, bricks[random:NextInteger(1, #bricks)], color, position, velocity, feet)
	end
end

-- A blow that landed: a white-hot pixel, pixels of the body's skin and a few of its stud pieces knocked off.
function EnemyImpacts.EmitHit(enemyData: TData.TEnemy, chest: Vector3, aim: vector, from: Vector3?)
	if hitBursts >= Tune.MAX_HIT_BURSTS_PER_FRAME then return end
	hitBursts += 1
	burstOn(TIERS.Hit, enemyData, chest, aim, from)
end

-- The killing blow: a hit's light, and more of the body coming off as it falls.
function EnemyImpacts.EmitKill(enemyData: TData.TEnemy, chest: Vector3, aim: vector, from: Vector3?)
	if killBursts >= Tune.MAX_KILL_BURSTS_PER_FRAME then return end
	killBursts += 1
	burstOn(TIERS.Kill, enemyData, chest, aim, from)
end

-- A blow worth several times the body's health: the whole body comes apart in pieces under a flash and a square
-- shockwave. It stands in for the killing blow's burst and for the vanish.
function EnemyImpacts.EmitOverkill(enemyData: TData.TEnemy, chest: Vector3, aim: vector, from: Vector3?)
	if endBursts >= Tune.MAX_END_BURSTS_PER_FRAME then return end
	endBursts += 1
	burstOn(TIERS.Overkill, enemyData, chest, aim, from)
end

-- A body that goes on the spot (blown up, or past the corpse cap): puffs hide that it popped out of the world, and a
-- few of its pieces drop where it stood.
function EnemyImpacts.EmitVanish(enemyData: TData.TEnemy, chest: Vector3, aim: vector)
	if endBursts >= Tune.MAX_END_BURSTS_PER_FRAME then return end
	endBursts += 1
	burstOn(TIERS.Vanish, enemyData, chest, aim, nil)
end

-- At the top of the frame, so a kill arriving between steps counts toward the frame it is drawn in. Moves the
-- pieces in the air too.
function EnemyImpacts.BeginFrame()
	killsThisFrame = 0
	massKillTier = 0
	hitBursts = 0
	killBursts = 0
	endBursts = 0
	cameraPosition = Workspace.CurrentCamera.CFrame.Position
	thrownPieces.Step(pieces)
end

return EnemyImpacts
