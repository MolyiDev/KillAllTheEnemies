-- HEAL ALL as it is seen on a character, in the house look (VFX.md 30 and 36): on the body first, a white-hot heart
-- in a green bloom, three square rings climbing it from the feet and green pixels floating up off it; on the floor
-- only a pool of light and a ring snapping open under the feet. Whoever bought it also throws one wide ring out along
-- the floor, toward the rest of the squad.
-- ItemsController says who and steps it. The look is on templates at ReplicatedStorage.Effects.HealFx, a place
-- instance, not Rojo, made by Assets/effects/items (its README.md). A handful of bodies at most, once a purchase:
-- each gets copies of its own, destroyed when they are spent.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local healFx = {}

local KIT = "HealFx"

local Tune = table.freeze({
	-- An R6 root's centre over its feet.
	ROOT_HEIGHT = 3,
	-- Over the floor, so a flat ring never fights it for depth.
	LIFT = 0.08,
	FLECKS = NumberRange.new(9, 12),
	MOTES = NumberRange.new(16, 20),
	-- The rings up the body: how many, and the beat between them.
	RISES = 3,
	RISE_GAP = 0.11,
	-- A body's copies go this long after it was healed: past the longest particle's life.
	LIFE = 2,
})

-- One body being healed: its copies of the templates, the rings still to climb it and when the next one goes.
type THeal = {
	Feet: Attachment,
	Heart: Attachment,
	Cast: Attachment?,
	Rise: ParticleEmitter?,
	RisesLeft: number,
	NextRiseAt: number,
	EndsAt: number,
}

type TKit = { Feet: Attachment, Heart: Attachment, Cast: Attachment? }

local random = Random.new()
local kit: TKit? = nil
local hasWarned = false
local heals: { THeal } = {}

-- The kit's templates; nil (said once) while they are not in the place, when a heal draws nothing. A miss is asked
-- again, so templates that reach the client late are still found.
local function kitOf(): TKit?
	if kit then return kit end

	local effects = ReplicatedStorage:FindFirstChild("Effects")
	local templates = if effects then effects:FindFirstChild(KIT) else nil
	local feet = if templates then templates:FindFirstChild("Feet") else nil
	local heart = if templates then templates:FindFirstChild("Heart") else nil
	if not feet or not heart or not feet:IsA("Attachment") or not heart:IsA("Attachment") then
		if not hasWarned then
			hasWarned = true
			warn(`[healFx] no ReplicatedStorage.Effects.{KIT}; a heal draws nothing`)
		end
		return nil
	end

	local cast = (templates :: Instance):FindFirstChild("Cast")
	local found = { Feet = feet, Heart = heart, Cast = if cast and cast:IsA("Attachment") then cast else nil }
	kit = found
	return found
end

local function emit(attachment: Attachment, layer: string, count: number)
	local emitter = attachment:FindFirstChild(layer)
	if emitter and emitter:IsA("ParticleEmitter") then emitter:Emit(count) end
end

-- Heals the body whose root is `root`: the burst rides it. `isCaster` is whoever bought the heal.
function healFx.Cast(root: BasePart, isCaster: boolean)
	local found = kitOf()
	if not found then return end

	local feet = found.Feet:Clone()
	feet.CFrame = CFrame.new(0, Tune.LIFT - Tune.ROOT_HEIGHT, 0)
	feet.Parent = root
	local heart = found.Heart:Clone()
	heart.Parent = root
	emit(feet, "Wash", 1)
	emit(feet, "Frame", 1)
	emit(heart, "Bloom", 1)
	emit(heart, "Core", 1)
	emit(heart, "Flecks", random:NextInteger(Tune.FLECKS.Min, Tune.FLECKS.Max))
	emit(heart, "Motes", random:NextInteger(Tune.MOTES.Min, Tune.MOTES.Max))

	-- Left on the floor where it was thrown: the ring goes out from there, not along with the body.
	local cast: Attachment? = nil
	if isCaster and found.Cast then
		local thrown = found.Cast:Clone()
		thrown.CFrame = CFrame.new(root.Position + Vector3.new(0, Tune.LIFT - Tune.ROOT_HEIGHT, 0))
		thrown.Parent = Workspace.Terrain
		emit(thrown, "Wash", 1)
		emit(thrown, "Wave", 1)
		cast = thrown
	end

	local now = os.clock()
	local rise = feet:FindFirstChild("Rise")
	heals[#heals + 1] = {
		Feet = feet,
		Heart = heart,
		Cast = cast,
		Rise = if rise and rise:IsA("ParticleEmitter") then rise else nil,
		RisesLeft = Tune.RISES,
		NextRiseAt = now,
		EndsAt = now + Tune.LIFE,
	}
end

-- Once a frame: the rings climbing each body in turn, and the copies of one whose burst is spent.
function healFx.Step()
	if #heals == 0 then return end

	local now = os.clock()
	for index = #heals, 1, -1 do
		local heal = heals[index]
		if heal.RisesLeft > 0 and now >= heal.NextRiseAt then
			heal.RisesLeft -= 1
			heal.NextRiseAt = now + Tune.RISE_GAP
			if heal.Rise then heal.Rise:Emit(1) end
		end

		if now < heal.EndsAt then continue end
		-- A body that left took its copies with it: destroying them again is harmless.
		heal.Feet:Destroy()
		heal.Heart:Destroy()
		if heal.Cast then heal.Cast:Destroy() end
		heals[index] = heals[#heals]
		heals[#heals] = nil
	end
end

return healFx
