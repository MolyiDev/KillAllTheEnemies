-- A bought HEALTH level as it is seen on the buyer's body, in the house look (VFX.md 30): two beats, both riding the
-- body. On the buy a ring snaps open under the feet, one fat square ring runs up the body, the chest goes white-hot
-- and throws a fountain of green pixels straight up. Half a second later, as the HUD's bar takes its new cells, a
-- halo pops open over the head.
-- HealthController says who and steps it. The look is on templates at ReplicatedStorage.Effects.HealthUpFx, a place
-- instance, not Rojo, made by Assets/effects/health (its README.md). One body a purchase: each gets copies of its
-- own, destroyed when they are spent.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local healthUpFx = {}

local KIT = "HealthUpFx"

local Tune = table.freeze({
	-- An R6 root's centre over its feet, and the top of its head over the root's centre.
	ROOT_HEIGHT = 3,
	HEAD_TOP = 2.6,
	-- Over the floor, so a flat ring never fights it for depth.
	LIFT = 0.08,
	FOUNTAIN = NumberRange.new(14, 18),
	FLECKS = NumberRange.new(8, 11),
	SPARKS = NumberRange.new(7, 9),
	-- The halo's beat after the buy: when the bought kit lands in the HUD's bar (HudController/HealthUpgrade's
	-- Timing.LAND) and the cue's second hit.
	CROWN_AT = 0.5,
	-- A body's copies go this long after the buy: past the halo and its longest particle.
	LIFE = 2,
})

-- One body's burst: its copies of the templates, and when the halo is still to go.
type TBurst = {
	Root: BasePart,
	Feet: Attachment,
	Chest: Attachment,
	Crown: Attachment?,
	CrownAt: number,
	EndsAt: number,
}

type TKit = { Feet: Attachment, Chest: Attachment, Crown: Attachment }

local random = Random.new()
local kit: TKit? = nil
local hasWarned = false
local bursts: { TBurst } = {}

-- The kit's templates; nil (said once) while they are not in the place, when a level draws nothing. A miss is asked
-- again, so templates that reach the client late are still found.
local function kitOf(): TKit?
	if kit then return kit end

	local effects = ReplicatedStorage:FindFirstChild("Effects")
	local templates = if effects then effects:FindFirstChild(KIT) else nil
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
			warn(`[healthUpFx] no ReplicatedStorage.Effects.{KIT}; a HEALTH level draws nothing on the body`)
		end
		return nil
	end

	local found = { Feet = feet :: Attachment, Chest = chest :: Attachment, Crown = crown :: Attachment }
	kit = found
	return found
end

local function emit(attachment: Attachment, layer: string, count: number)
	local emitter = attachment:FindFirstChild(layer)
	if emitter and emitter:IsA("ParticleEmitter") then emitter:Emit(count) end
end

-- The body whose root is `root` took a HEALTH level: the burst rides it.
function healthUpFx.Cast(root: BasePart)
	local found = kitOf()
	if not found then return end

	local feet = found.Feet:Clone()
	feet.CFrame = CFrame.new(0, Tune.LIFT - Tune.ROOT_HEIGHT, 0)
	feet.Parent = root
	local chest = found.Chest:Clone()
	chest.Parent = root
	emit(feet, "Wash", 1)
	emit(feet, "Frame", 1)
	emit(feet, "Surge", 1)
	emit(chest, "Bloom", 1)
	emit(chest, "Core", 1)
	emit(chest, "Fountain", random:NextInteger(Tune.FOUNTAIN.Min, Tune.FOUNTAIN.Max))
	emit(chest, "Flecks", random:NextInteger(Tune.FLECKS.Min, Tune.FLECKS.Max))

	local now = os.clock()
	bursts[#bursts + 1] = {
		Root = root,
		Feet = feet,
		Chest = chest,
		Crown = nil,
		CrownAt = now + Tune.CROWN_AT,
		EndsAt = now + Tune.LIFE,
	}
end

-- Once a frame: the halo of each body whose beat has come, and the copies of one whose burst is spent.
function healthUpFx.Step()
	if #bursts == 0 then return end

	local now = os.clock()
	for index = #bursts, 1, -1 do
		local burst = bursts[index]
		if not burst.Crown and now >= burst.CrownAt and kit then
			local crown = kit.Crown:Clone()
			crown.CFrame = CFrame.new(0, Tune.HEAD_TOP, 0)
			crown.Parent = burst.Root
			emit(crown, "Halo", 1)
			emit(crown, "Core", 1)
			emit(crown, "Sparks", random:NextInteger(Tune.SPARKS.Min, Tune.SPARKS.Max))
			burst.Crown = crown
		end

		if now < burst.EndsAt then continue end
		-- A body that left took its copies with it: destroying them again is harmless.
		burst.Feet:Destroy()
		burst.Chest:Destroy()
		if burst.Crown then burst.Crown:Destroy() end
		bursts[index] = bursts[#bursts]
		bursts[#bursts] = nil
	end
end

return healthUpFx
