-- A run upgrade taken, on the taker's body once their cards have gone: three rings climb it and a halo pops over the
-- head, in the card's rarity colour (VFX.md 39; the look is Assets/effects/upgrade's). The templates are a place
-- instance, not Rojo: ReplicatedStorage.Effects.UpgradeFx, a Folder a rarity named as ERarities names it. Each body
-- gets copies of its own, destroyed once they are spent.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ERarities = require(ReplicatedStorage.Types.Enums.ERarities)

local upgradeFx = {}

local KIT = "UpgradeFx"

local Tune = table.freeze({
	-- An R6 root's centre over its feet, and the top of its head over the root's centre.
	ROOT_HEIGHT = 3,
	HEAD_TOP = 2.6,
	-- Over the floor, so a flat ring never fights it for depth.
	LIFT = 0.08,
	-- The rings up the body: this many, this long apart. The halo comes as the last one reaches the head (a ring takes
	-- a third of a second up, Assets/effects/upgrade's Climb), and the sound's last hit is baked to it
	-- (Assets/sounds/Review/UpgradeBody, CROWN_MS): move one, rebuild the other.
	CLIMBS = 3,
	CLIMB_EVERY = 0.12,
	CROWN_AT = 0.54,
	RISE = NumberRange.new(16, 20),
	FLECKS = NumberRange.new(8, 11),
	SPOUT = NumberRange.new(9, 12),
	SPARKS = NumberRange.new(7, 9),
	-- A rarer card throws more pixels: this much more each step up from Common (a Mythic 1.8 times a Common's).
	RARITY_STEP = 0.16,
	-- A body's copies go this long after the cast: past the halo and its longest particle.
	LIFE = 2,
})

type TKit = { Feet: Attachment, Chest: Attachment, Crown: Attachment }

-- One body's show: its rarity's templates, its copies of them, its pixel scale and how many rings have gone up.
type TBurst = {
	Root: BasePart,
	Kit: TKit,
	Scale: number,
	StartedAt: number,
	Feet: Attachment,
	Chest: Attachment,
	Crown: Attachment?,
	Climbs: number,
}

local NAMES: { [number]: string } = {}
for name, rarity in ERarities do
	NAMES[rarity] = name
end

local random = Random.new()
local kits: { [number]: TKit } = {}
local hasWarned = false
local bursts: { TBurst } = {}

-- A rarity's templates; nil (said once) while they are not in the place, when a pick draws nothing. A miss is asked
-- again, so templates that reach the client late are still found.
local function kitOf(rarity: number): TKit?
	local found = kits[rarity]
	if found then return found end

	local effects = ReplicatedStorage:FindFirstChild("Effects")
	local folder = if effects then effects:FindFirstChild(KIT) else nil
	local templates = if folder then folder:FindFirstChild(NAMES[rarity] or "Common") else nil
	local feet = if templates then templates:FindFirstChild("Feet") else nil
	local chest = if templates then templates:FindFirstChild("Chest") else nil
	local crown = if templates then templates:FindFirstChild("Crown") else nil
	local isWhole = feet
		and chest
		and crown
		and feet:IsA("Attachment")
		and chest:IsA("Attachment")
		and crown:IsA("Attachment")
	if not isWhole then
		if not hasWarned then
			hasWarned = true
			warn(`[upgradeFx] no ReplicatedStorage.Effects.{KIT}; a pick draws nothing on the body`)
		end
		return nil
	end

	found = { Feet = feet :: Attachment, Chest = chest :: Attachment, Crown = crown :: Attachment }
	kits[rarity] = found
	return found
end

local function emit(attachment: Attachment, layer: string, count: number)
	local emitter = attachment:FindFirstChild(layer)
	if emitter and emitter:IsA("ParticleEmitter") then emitter:Emit(count) end
end

local function count(range: NumberRange, scale: number): number
	return math.round(random:NextInteger(range.Min, range.Max) * scale)
end

-- The body whose root is `root` took an upgrade of `rarity`: the show rides it.
function upgradeFx.Cast(root: BasePart, rarity: number)
	local found = kitOf(rarity)
	if not found then return end
	local scale = 1 + (rarity - 1) * Tune.RARITY_STEP

	local feet = found.Feet:Clone()
	feet.CFrame = CFrame.new(0, Tune.LIFT - Tune.ROOT_HEIGHT, 0)
	feet.Parent = root
	local chest = found.Chest:Clone()
	chest.Parent = root
	emit(feet, "Wash", 1)
	emit(feet, "Frame", 1)
	emit(feet, "Climb", 1)
	emit(feet, "Rise", count(Tune.RISE, scale))
	emit(chest, "Bloom", 1)
	emit(chest, "Core", 1)
	emit(chest, "Flecks", count(Tune.FLECKS, scale))

	bursts[#bursts + 1] = {
		Root = root,
		Kit = found,
		Scale = scale,
		StartedAt = os.clock(),
		Feet = feet,
		Chest = chest,
		Crown = nil,
		Climbs = 1,
	}
end

-- Once a frame: each body's next ring and its halo when their beats come, and the copies of one whose show is spent.
function upgradeFx.Step()
	if #bursts == 0 then return end

	local now = os.clock()
	for index = #bursts, 1, -1 do
		local burst = bursts[index]
		local since = now - burst.StartedAt
		if burst.Climbs < Tune.CLIMBS and since >= burst.Climbs * Tune.CLIMB_EVERY then
			burst.Climbs += 1
			emit(burst.Feet, "Climb", 1)
		end
		if not burst.Crown and since >= Tune.CROWN_AT then
			local crown = burst.Kit.Crown:Clone()
			crown.CFrame = CFrame.new(0, Tune.HEAD_TOP, 0)
			crown.Parent = burst.Root
			emit(crown, "Halo", 1)
			emit(crown, "Core", 1)
			emit(crown, "Spout", count(Tune.SPOUT, burst.Scale))
			emit(crown, "Sparks", count(Tune.SPARKS, burst.Scale))
			burst.Crown = crown
		end

		if since < Tune.LIFE then continue end
		-- A body that left took its copies with it: destroying them again is harmless.
		burst.Feet:Destroy()
		burst.Chest:Destroy()
		if burst.Crown then burst.Crown:Destroy() end
		bursts[index] = bursts[#bursts]
		bursts[#bursts] = nil
	end
end

return upgradeFx
