-- What both sides agree on about a shot: where each pellet goes for a seed, how a ray meets an enemy's aim shape, and
-- the tuning every gun shares. The server decides hits with these; the client draws the same pellets.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local LoadoutCore = require(ReplicatedStorage.GlobalShared.Core.LoadoutCore)
local TData = require(ReplicatedStorage.Types.TData)

local EPSILON = 1e-6
-- A lean toward one end this small, as a share of the gun's length, is no lean: a model of one mesh, or of meshes on
-- one centre, weighs the same both ways, and the engine's float noise would pick an end differently for each copy
-- and scale (a picture facing back while the hand holds it right). The nearest real lean is 3.4e-4 (Starter Rifle).
local TIE_LEAN = 1e-4

-- One step of the run's weapon upgrade: the gun, its Gold, and the word on the upgrade card.
export type TLadderStep = {
	Gun: number,
	Price: number,
	Label: string,
}

local GunsCore = {}

-- The Gold of each step of the run's weapon upgrades, one step per loadout tier. Every run starts on the first; each
-- buy moves one step on.
GunsCore.LADDER_PRICES = table.freeze({ 0, 150, 450, 1000 })

-- Step `index` of a ladder, holding `gun`.
function GunsCore.LadderStep(gun: TData.TGun, index: number): TLadderStep
	return table.freeze({ Gun = gun.Id, Price = GunsCore.LADDER_PRICES[index], Label = string.upper(gun.Name) })
end

-- A player's run ladder (the HUD's weapon card, WeaponService's upgrade): the gun each lobby loadout tier holds, in
-- tier order. `equipped` is the profile's Loadout.Equipped, where a tier never picked holds its starter.
-- Each step is a step up only while every gun kills faster than the cheaper guns of its tier and every gun of the
-- tiers below, measured rather than read off damage a second: run tools/lune/guns.luau after changing a gun.
function GunsCore.Ladder(equipped: { [string]: string }): { TLadderStep }
	local ladder = table.create(#GunsCore.LADDER_PRICES)
	for tier in GunsCore.LADDER_PRICES do
		ladder[tier] = GunsCore.LadderStep(LoadoutCore.EquippedOf(equipped, tier), tier)
	end

	return table.freeze(ladder)
end

-- The ladder of a loadout never touched: what the client shows until the server sends its own.
GunsCore.STARTER_LADDER = GunsCore.Ladder({})

GunsCore.Tune = table.freeze({
	-- The head's centre over the root on an R6 body: where the server shoots from, so where sight is tested from.
	EYE_HEIGHT = 1.5,
	-- What a blast does to everything in its radius but the body it hit, as a share of the pellet's damage.
	SPLASH_SHARE = 0.75,
	-- A shotgun's pellet count is the data's; past this a shot is refused as malformed data, not drawn.
	MAX_PELLETS = 24,
	-- The camera kick, degrees: from a gun's damage when it names none.
	KICK_BASE_DEG = 0.35,
	KICK_PER_DAMAGE_DEG = 0.03,
	KICK_MIN_DEG = 0.4,
	KICK_MAX_DEG = 3.5,
})

local byName: { [string]: TData.TGun } = {}
for _, gun in DataCore.Guns.All do
	byName[gun.Name] = gun
end

-- The gun a Tool was built from: tools are named after their gun (buildGunTool).
function GunsCore.FromToolName(name: string): TData.TGun?
	return byName[name]
end

-- A model sits in the folder named for its gun's rarity: ReplicatedStorage.Models.Guns.<Rarity>.<ModelName>.
function GunsCore.GetModel(gun: TData.TGun): Model?
	local models = ReplicatedStorage:FindFirstChild("Models")
	local guns = if models then models:FindFirstChild("Guns") else nil
	local folder = if guns then guns:FindFirstChild(gun.Rarity) else nil
	local model = if folder then folder:FindFirstChild(gun.ModelName) else nil
	return if model and model:IsA("Model") then model else nil
end

-- A gun model's frame: X out of the barrel, Y up, at the model's centre. The models are the old Game place's as they
-- were (no handle, any orientation), so the barrel is found from the parts: the biggest part's long axis, pointing
-- away from where most of the volume sits (the stock). A gun this reads wrongly is fixed in its data (IsFlipped,
-- PitchDeg).
function GunsCore.FindAxes(model: Model, gun: TData.TGun): CFrame
	local parts = {}
	local biggest: BasePart? = nil
	local biggestVolume = 0
	for _, descendant in model:GetDescendants() do
		if not descendant:IsA("BasePart") then continue end
		parts[#parts + 1] = descendant
		local size = descendant.Size
		local volume = size.X * size.Y * size.Z
		if volume > biggestVolume or not biggest then
			biggest = descendant
			biggestVolume = volume
		end
	end

	local pivot = model:GetPivot()
	if not biggest then return pivot end

	local size = biggest.Size
	local side = Vector3.xAxis
	if size.Y > size.X and size.Y >= size.Z then
		side = Vector3.yAxis
	elseif size.Z > size.X and size.Z > size.Y then
		side = Vector3.zAxis
	end

	local axis = biggest.CFrame:VectorToWorldSpace(side)
	local center = model:GetBoundingBox().Position
	local total, weighted = 0, 0
	for _, part in parts do
		local volume = part.Size.X * part.Size.Y * part.Size.Z
		total += volume
		weighted += volume * (part.Position - center):Dot(axis)
	end

	-- The heavier end is the stock, so the barrel points the other way. A tie keeps the biggest part's own axis.
	local isStockAlongAxis = total > 0 and weighted / total > TIE_LEAN * size:Dot(side)
	local forward = if isStockAlongAxis then -axis else axis
	if gun.IsFlipped then forward = -forward end

	local up = pivot.UpVector
	if math.abs(up:Dot(forward)) > 0.9 then up = pivot.LookVector end
	up = (up - forward * up:Dot(forward)).Unit

	local frame = CFrame.fromMatrix(center, forward, up, forward:Cross(up))
	return if gun.PitchDeg then frame * CFrame.Angles(0, 0, math.rad(gun.PitchDeg)) else frame
end

-- Degrees the camera kicks for one shot of `gun`.
function GunsCore.KickDeg(gun: TData.TGun): number
	local tune = GunsCore.Tune
	return gun.RecoilDeg
		or math.clamp(tune.KICK_BASE_DEG + gun.Damage * tune.KICK_PER_DAMAGE_DEG, tune.KICK_MIN_DEG, tune.KICK_MAX_DEG)
end

-- The `count` pellets of the shot seeded `seed` into `out[1..count]`: `direction` turned a random way by up to
-- `spreadDeg`, thick in the middle of the cone and thin at its rim (the angle is drawn evenly, not the disc's area):
-- evenly over the disc, a shotgun put too few pellets on the body aimed at past 35 studs and killed slower than the
-- pistol (tools/lune/guns.luau). One generator a shot, drawn in pellet order, so the same seed gives the same pattern
-- on every machine.
function GunsCore.PelletDirections(direction: Vector3, seed: number, spreadDeg: number, count: number, out: { Vector3 })
	local unit = direction.Unit
	if spreadDeg <= 0 then
		for pellet = 1, count do
			out[pellet] = unit
		end
		return
	end

	local random = Random.new(seed)
	local maxCone = math.rad(spreadDeg)
	local side = if math.abs(unit.Y) < 0.99 then unit:Cross(Vector3.yAxis).Unit else unit:Cross(Vector3.xAxis).Unit
	for pellet = 1, count do
		local turn = random:NextNumber(0, math.pi * 2)
		local cone = maxCone * random:NextNumber()
		local axis = CFrame.fromAxisAngle(unit, turn):VectorToWorldSpace(side)
		out[pellet] = CFrame.fromAxisAngle(axis, cone):VectorToWorldSpace(unit)
	end
end

-- Distance along `unit` from `origin` to an upright cylinder (centre x/z, `radius`, from `floorY` up `height`), or nil
-- when the ray misses it. Its side, and its top for a ray coming down onto it.
local function rayCylinder(
	origin: Vector3,
	unit: Vector3,
	centerX: number,
	centerZ: number,
	radius: number,
	floorY: number,
	height: number
): number?
	local fx = origin.X - centerX
	local fz = origin.Z - centerZ
	local dx, dy, dz = unit.X, unit.Y, unit.Z
	local topY = floorY + height
	local a = dx * dx + dz * dz
	local c = fx * fx + fz * fz - radius * radius
	local best: number? = nil

	if a > EPSILON then
		local b = 2 * (fx * dx + fz * dz)
		local discriminant = b * b - 4 * a * c
		if discriminant >= 0 then
			local root = math.sqrt(discriminant)
			local t = (-b - root) / (2 * a)
			if t < 0 then t = (-b + root) / (2 * a) end
			local y = origin.Y + dy * t
			if t >= 0 and y >= floorY and y <= topY then best = t end
		end
	end

	if dy < -EPSILON and origin.Y > topY then
		local t = (topY - origin.Y) / dy
		local hx = fx + dx * t
		local hz = fz + dz * t
		if hx * hx + hz * hz <= radius * radius and (best == nil or t < best) then best = t end
	end

	return best
end

GunsCore.RayCylinder = rayCylinder

-- The bodies a shot can hit, gathered once a shot (each side from its own source) so every pellet tests plain arrays:
-- no ECS read and no call into another module per pellet per body.
export type TBodies = {
	Count: number,
	X: { number },
	Z: { number },
	FloorY: { number },
	Radius: { number },
	Height: { number },
}

function GunsCore.NewBodies(): TBodies
	return { Count = 0, X = {}, Z = {}, FloorY = {}, Radius = {}, Height = {} }
end

function GunsCore.AddBody(bodies: TBodies, feet: Vector3, radius: number, height: number)
	local index = bodies.Count + 1
	bodies.Count = index
	bodies.X[index] = feet.X
	bodies.Z[index] = feet.Z
	bodies.FloorY[index] = feet.Y
	bodies.Radius[index] = radius
	bodies.Height[index] = height
end

-- The nearest body the ray meets within `length` (each widened by `pad`) and further than `beyond`: its index and
-- distance, or 0 and `length`. `beyond` is -1 for the first body, then the last hit's distance for a bullet that
-- goes on through it (TGun.Pierce).
function GunsCore.CastBodies(
	bodies: TBodies,
	origin: Vector3,
	unit: Vector3,
	length: number,
	pad: number,
	beyond: number
): (number, number)
	local xs, zs, floors, radii, heights = bodies.X, bodies.Z, bodies.FloorY, bodies.Radius, bodies.Height
	local best, bestDistance = 0, length
	for index = 1, bodies.Count do
		local t = rayCylinder(origin, unit, xs[index], zs[index], radii[index] + pad, floors[index], heights[index])
		if t and t < bestDistance and t > beyond then
			best, bestDistance = index, t
		end
	end

	return best, bestDistance
end

return table.freeze(GunsCore)
