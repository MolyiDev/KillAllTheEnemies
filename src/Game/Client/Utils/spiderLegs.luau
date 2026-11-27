--!native
-- A spider rig's legs stood and walked by IK (TEnemy.HasLegIK): every blade planted on the floor where it stands, and
-- stepped onto a new spot ahead of the body when the body has carried it too far, in two groups that take turns (the
-- front and third legs of one side with the second and rear of the other). The body rides the feet: raised, pitched
-- and rolled to their heights. EnemiesController steps it after the Animator and its blends, over its Idle; the
-- weight hands the legs back to the clips for every other move, whose first and last frames are this stance.
--
-- Bones (Models.md section 16): `Thorax` > `Coxa{n}_{side}` > `Femur` > `Tibia` > `Metatarsus` > `Tarsus` > `Tip`, every
-- rest rotation the identity, so a bone's Transform is a turn in Root's axes about its own pivot. A leg is solved as
-- the clip tools solve it (Assets/models/Bosses/Spider/anim/spider_death.py, solve_leg): the coxa yaws it toward its
-- target, the knee bends on the law of cosines between the femur and the rigid lower leg (tibia to tip at rest), the
-- femur aims the chain.
local Workspace = game:GetService("Workspace")

local spiderLegs = {}

local Tune = table.freeze({
	-- At the rig's size as put in the place (its scale multiplies them): how far a foot may trail its spot before its
	-- group steps (a share of the stride), the stride, and a step's arc.
	STRIDE = 6,
	TRIGGER_SHARE = 0.5,
	ARC = 1.6,
	-- Standing still, a foot this far off its rest spot steps home, so the body ends in the stance every clip starts in.
	SETTLE = 0.25,
	-- A step lasts half a stride at the body's speed, within these (seconds).
	STEP_MIN = 0.07,
	STEP_MAX = 0.3,
	-- The body's run is read smoothed over this long, and a jump further than this in one frame (a snap, a respawn)
	-- puts every foot down on its spot.
	VELOCITY_SMOOTHING = 0.15,
	TELEPORT = 8,
	-- The floor is looked for this far over and under a foot's new spot.
	PROBE_UP = 6,
	PROBE_DOWN = 14,
	-- The body rides its feet: this share of their mean height, pitched and rolled to them at most this far (radians).
	RIDE = 0.8,
	TILT_MAX = 0.35,
	-- A step landing dips the body this much (a share of the arc) and lets it back up.
	LAND_DIP = 0.12,
	LAND_SECONDS = 0.18,
})

local SIDES = { "L", "R" }
-- The two groups: legs 1 and 3 of one side with 2 and 4 of the other.
local GROUP_OF = { L = { 1, 2, 1, 2 }, R = { 2, 1, 2, 1 } }

type TLeg = {
	Coxa: Bone,
	Femur: Bone,
	Tibia: Bone,
	Metatarsus: Bone,
	Tarsus: Bone,
	Group: number,
	IsFront: boolean,
	Side: number,
	-- Rest pivots and tip in Root's space, and the tip's spot on the floor under the body.
	C: Vector3,
	F: Vector3,
	K: Vector3,
	Tip: Vector3,
	Home: Vector3,
	-- Where its blade is (world), how far it trails its spot (startSteps), and its step when in the air.
	Foot: Vector3,
	Trail: number,
	IsStepping: boolean,
	StepFrom: Vector3,
	StepAt: number,
	StepSeconds: number,
	StepFloor: number,
}

export type TLegs = {
	Root: Bone,
	-- Root's frame with no Transform: the rig is never moved, so read once.
	RootRest: CFrame,
	Thorax: Bone,
	ThoraxRest: CFrame,
	Legs: { TLeg },
	Scale: number,
	-- The stance's length (front tips to rear) and width (side to side), what the body pitches and rolls over.
	Length: number,
	Width: number,
	Clock: number,
	Velocity: Vector3,
	LastRoot: Vector3?,
	IsPlanted: boolean,
	-- The group in the air (0: none), when a group last landed (the dip), which, and how many landings so far (the
	-- boss's footfalls count them).
	Stepping: number,
	LandedAt: number,
	LandedGroup: number,
	Landings: number,
	Weight: number,
	-- The thorax turn written last frame and the clip's pose under it, so a frame where no clip rewrote it is not
	-- turned twice.
	ThoraxWritten: CFrame?,
	ThoraxBase: CFrame?,
}

local probeParams = RaycastParams.new()
probeParams.FilterType = Enum.RaycastFilterType.Include
-- The arena the floor is probed in, found once (and again if it is replaced).
local probedArena: Instance? = nil

-- ============================== Maths ==============================

-- `v` turned `angle` radians about the unit `axis`, right-handed (Rodrigues).
local function turn(v: Vector3, axis: Vector3, angle: number): Vector3
	local c, s = math.cos(angle), math.sin(angle)
	return v * c + axis:Cross(v) * s + axis * (axis:Dot(v) * (1 - c))
end

-- The turn about `axis` as a CFrame (columns are the turned basis): no dependence on any constructor's handedness.
local function rotation(axis: Vector3, angle: number): CFrame
	return CFrame.fromMatrix(
		Vector3.zero,
		turn(Vector3.xAxis, axis, angle),
		turn(Vector3.yAxis, axis, angle),
		turn(Vector3.zAxis, axis, angle)
	)
end

-- The least turn taking direction `from` onto direction `to`.
local function align(from: Vector3, to: Vector3): CFrame
	local a, b = from.Unit, to.Unit
	local cross = a:Cross(b)
	local sine = cross.Magnitude
	if sine < 1e-6 then return CFrame.identity end
	return rotation(cross / sine, math.atan2(sine, a:Dot(b)))
end

-- The leg's (coxa, femur, tibia) Transforms that put its tip on `target` (Root's rest space, the thorax's deform taken
-- off).
local function solve(leg: TLeg, target: Vector3): (CFrame, CFrame, CFrame)
	local C, F, K, tip = leg.C, leg.F, leg.K, leg.Tip
	local yaw = math.atan2(target.X - C.X, target.Z - C.Z) - math.atan2(tip.X - C.X, tip.Z - C.Z)
	local coxa = rotation(Vector3.yAxis, yaw)
	local F1 = C + coxa:VectorToWorldSpace(F - C)
	local K1 = C + coxa:VectorToWorldSpace(K - C)
	local P1 = C + coxa:VectorToWorldSpace(tip - C)

	local u, v = F1 - K1, P1 - K1
	local cross = u:Cross(v)
	local sine = cross.Magnitude
	if sine < 1e-6 then return coxa, CFrame.identity, CFrame.identity end
	local normal = cross / sine
	local upper, lower = u.Magnitude, v.Magnitude
	local reach = math.clamp((target - F1).Magnitude, math.abs(upper - lower) + 1e-3, upper + lower - 1e-3)
	local was = math.atan2(sine, u:Dot(v))
	local bend = math.acos(math.clamp((upper * upper + lower * lower - reach * reach) / (2 * upper * lower), -1, 1))
	local knee = rotation(normal, bend - was)
	local P2 = K1 + knee:VectorToWorldSpace(v)
	local aim = align(P2 - F1, target - F1)

	-- Each bone's turn against its parent's: the femur's is aim after the coxa, the tibia's the knee after both.
	local femur = coxa:Inverse() * aim * coxa
	local tibia = coxa:Inverse() * knee * coxa
	return coxa, femur, tibia
end

-- ============================== Rig ==============================

local function child(parent: Instance, name: string): Bone?
	local found = parent:FindFirstChild(name)
	return if found and found:IsA("Bone") then found else nil
end

-- The legs of `model`, or nil when it is not a spider rig.
function spiderLegs.New(model: Model, mesh: BasePart, root: Bone): TLegs?
	local thorax = child(root, "Thorax")
	if not thorax then return nil end
	local thoraxAt = thorax.CFrame.Position
	local legs: { TLeg } = {}
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, side in SIDES do
		for n = 1, 4 do
			local coxa = child(thorax, `Coxa{n}_{side}`)
			local femur = coxa and child(coxa, `Femur{n}_{side}`)
			local tibia = femur and child(femur, `Tibia{n}_{side}`)
			local metatarsus = tibia and child(tibia, `Metatarsus{n}_{side}`)
			local tarsus = metatarsus and child(metatarsus, `Tarsus{n}_{side}`)
			local tip = tarsus and child(tarsus, `Tip{n}_{side}`)
			if not coxa or not femur or not tibia or not metatarsus or not tarsus or not tip then return nil end
			local C = thoraxAt + coxa.CFrame.Position
			local F = C + femur.CFrame.Position
			local K = F + tibia.CFrame.Position
			local tipAt = K + metatarsus.CFrame.Position + tarsus.CFrame.Position + tip.CFrame.Position
			minX, maxX = math.min(minX, tipAt.X), math.max(maxX, tipAt.X)
			minZ, maxZ = math.min(minZ, tipAt.Z), math.max(maxZ, tipAt.Z)
			table.insert(legs, {
				Coxa = coxa,
				Femur = femur,
				Tibia = tibia,
				Metatarsus = metatarsus,
				Tarsus = tarsus,
				Group = GROUP_OF[side][n],
				IsFront = n <= 2,
				Side = if side == "L" then 1 else -1,
				C = C,
				F = F,
				K = K,
				Tip = tipAt,
				Home = Vector3.new(tipAt.X, 0, tipAt.Z),
				Foot = Vector3.zero,
				Trail = 0,
				IsStepping = false,
				StepFrom = Vector3.zero,
				StepAt = 0,
				StepSeconds = 0,
				StepFloor = 0,
			})
		end
	end

	return {
		Root = root,
		RootRest = mesh.CFrame * root.CFrame,
		Thorax = thorax,
		ThoraxRest = CFrame.new(thoraxAt),
		Legs = legs,
		Scale = model:GetScale(),
		Length = math.max(maxZ - minZ, 1e-3),
		Width = math.max(maxX - minX, 1e-3),
		Clock = 0,
		Velocity = Vector3.zero,
		LastRoot = nil,
		IsPlanted = false,
		Stepping = 0,
		LandedAt = -math.huge,
		LandedGroup = 0,
		Landings = 0,
		Weight = 0,
		ThoraxWritten = nil,
		ThoraxBase = nil,
	}
end

-- The floor under (x, z) near height `y`, or `y` itself where there is none.
local function floorAt(rig: TLegs, x: number, y: number, z: number): number
	if not probedArena or not probedArena.Parent then
		probedArena = Workspace:FindFirstChild("Arena")
		if not probedArena then return y end
		probeParams.FilterDescendantsInstances = { probedArena }
	end
	local up = Tune.PROBE_UP * rig.Scale
	local hit = Workspace:Raycast(
		Vector3.new(x, y + up, z),
		Vector3.new(0, -(up + Tune.PROBE_DOWN * rig.Scale), 0),
		probeParams
	)
	return if hit then hit.Position.Y else y
end

-- Where a leg's blade wants to be: its rest spot under the body, led by the body's run.
local function spotOf(rig: TLegs, leg: TLeg, body: CFrame, lead: number): Vector3
	local velocity = rig.Velocity
	return body:PointToWorldSpace(leg.Home) + Vector3.new(velocity.X, 0, velocity.Z) * lead
end

local function plantAll(rig: TLegs, body: CFrame)
	for _, leg in rig.Legs do
		local spot = spotOf(rig, leg, body, 0)
		leg.Foot = Vector3.new(spot.X, floorAt(rig, spot.X, body.Position.Y, spot.Z), spot.Z)
		leg.IsStepping = false
	end
	rig.Stepping = 0
	rig.IsPlanted = true
end

-- Lifts the group whose feet trail their spots the most, when any is past its trigger; standing still, any foot off
-- its rest spot steps home.
local function startSteps(rig: TLegs, body: CFrame, speed: number)
	if rig.Stepping ~= 0 then return end
	local scale = rig.Scale
	local stride = Tune.STRIDE * scale
	local isStill = speed < 0.5 * scale
	local stepSeconds = math.clamp(stride * 0.5 / math.max(speed, 1e-3), Tune.STEP_MIN, Tune.STEP_MAX)
	local lead = if isStill then 0 else stepSeconds
	local trigger = if isStill then Tune.SETTLE * scale else stride * Tune.TRIGGER_SHARE
	local worstOne, worstTwo = 0, 0
	for _, leg in rig.Legs do
		local spot = spotOf(rig, leg, body, lead)
		local trail = Vector3.new(leg.Foot.X - spot.X, 0, leg.Foot.Z - spot.Z).Magnitude
		leg.Trail = trail
		if leg.Group == 1 then
			worstOne = math.max(worstOne, trail)
		else
			worstTwo = math.max(worstTwo, trail)
		end
	end
	local group = if worstOne >= worstTwo then 1 else 2
	if math.max(worstOne, worstTwo) < trigger then return end

	rig.Stepping = group
	for _, leg in rig.Legs do
		if leg.Group ~= group or leg.Trail < trigger * 0.3 then continue end
		local spot = spotOf(rig, leg, body, lead)
		leg.IsStepping = true
		leg.StepFrom = leg.Foot
		leg.StepAt = rig.Clock
		leg.StepSeconds = stepSeconds
		leg.StepFloor = floorAt(rig, spot.X, body.Position.Y, spot.Z)
	end
end

-- Each foot in the air moved along its arc to its spot (which moves with the body), and put down at the end.
local function moveFeet(rig: TLegs, body: CFrame)
	local arc = Tune.ARC * rig.Scale
	local stillStepping = false
	for _, leg in rig.Legs do
		if not leg.IsStepping then continue end
		local u = math.min((rig.Clock - leg.StepAt) / leg.StepSeconds, 1)
		local left = leg.StepSeconds * (1 - u)
		local spot = spotOf(rig, leg, body, left)
		local landing = Vector3.new(spot.X, leg.StepFloor, spot.Z)
		local eased = u * u * (3 - 2 * u)
		leg.Foot = leg.StepFrom:Lerp(landing, eased) + Vector3.new(0, arc * math.sin(math.pi * u), 0)
		if u >= 1 then
			leg.IsStepping = false
			leg.Foot = landing
		else
			stillStepping = true
		end
	end

	if rig.Stepping ~= 0 and not stillStepping then
		rig.LandedGroup = rig.Stepping
		rig.Landings += 1
		rig.Stepping = 0
		rig.LandedAt = rig.Clock
	end
end

-- The thorax raised, pitched and rolled to its feet, and dipped as a group lands: in Root's axes about its pivot.
-- Sums over the eight legs, each half of them on one side of the pitch or the roll.
local function ride(rig: TLegs, rootWorld: CFrame): CFrame
	local front, rear, left, right = 0, 0, 0, 0
	for _, leg in rig.Legs do
		local height = rootWorld:PointToObjectSpace(leg.Foot).Y
		if leg.IsStepping then height = math.min(height, 0) end
		if leg.IsFront then
			front += height
		else
			rear += height
		end
		if leg.Side > 0 then
			left += height
		else
			right += height
		end
	end

	local half = #rig.Legs / 2
	local rise = Tune.RIDE * (front + rear) / (2 * half)
	local pitch = math.clamp(-math.atan2((front - rear) / half, rig.Length * 0.6), -Tune.TILT_MAX, Tune.TILT_MAX)
	local roll = math.clamp(math.atan2((left - right) / half, rig.Width), -Tune.TILT_MAX, Tune.TILT_MAX)
	local since = (rig.Clock - rig.LandedAt) / Tune.LAND_SECONDS
	local dip = if since < 1 then -Tune.LAND_DIP * Tune.ARC * rig.Scale * math.sin(math.pi * since) else 0
	return CFrame.new(0, rise + dip, 0) * CFrame.Angles(pitch, 0, roll)
end

-- One frame. `dt`: the body's clip time this frame (0 holds the feet where they are); `weight`: 1 to stand and walk
-- the legs here, 0 to leave them to the clips, eased between by the caller.
function spiderLegs.Step(rig: TLegs, dt: number, weight: number)
	rig.Weight = weight
	local rootWorld = rig.RootRest * rig.Root.Transform
	local at = rootWorld.Position
	local last = rig.LastRoot
	rig.LastRoot = at
	rig.Clock += dt

	if not rig.IsPlanted or (last and (at - last).Magnitude > Tune.TELEPORT * rig.Scale) then
		plantAll(rig, rootWorld)
	end
	if dt > 0 and last then
		local blend = 1 - math.exp(-dt / Tune.VELOCITY_SMOOTHING)
		rig.Velocity += ((at - last) / dt - rig.Velocity) * blend
	end
	local speed = Vector3.new(rig.Velocity.X, 0, rig.Velocity.Z).Magnitude
	if dt > 0 then
		startSteps(rig, rootWorld, speed)
		moveFeet(rig, rootWorld)
	end
	if weight <= 0 then return end

	-- The thorax: the clip's pose (or what was under last frame's write, when no clip rewrote it) with the ride on top.
	local thorax = rig.Thorax
	local current = thorax.Transform
	local base = if current == rig.ThoraxWritten then rig.ThoraxBase or current else current
	local ridden = base:Lerp(ride(rig, rootWorld) * base, weight)
	rig.ThoraxBase = base
	rig.ThoraxWritten = ridden
	thorax.Transform = ridden

	-- Targets go into Root's rest space through the thorax's deform, so the legs follow its pose.
	local rest = rig.ThoraxRest
	local deform = rootWorld * rest * ridden * rest:Inverse()
	for _, leg in rig.Legs do
		local target = deform:PointToObjectSpace(leg.Foot)
		local coxa, femur, tibia = solve(leg, target)
		if weight >= 1 then
			leg.Coxa.Transform = coxa
			leg.Femur.Transform = femur
			leg.Tibia.Transform = tibia
			leg.Metatarsus.Transform = CFrame.identity
			leg.Tarsus.Transform = CFrame.identity
		else
			leg.Coxa.Transform = leg.Coxa.Transform:Lerp(coxa, weight)
			leg.Femur.Transform = leg.Femur.Transform:Lerp(femur, weight)
			leg.Tibia.Transform = leg.Tibia.Transform:Lerp(tibia, weight)
			leg.Metatarsus.Transform = leg.Metatarsus.Transform:Lerp(CFrame.identity, weight)
			leg.Tarsus.Transform = leg.Tarsus.Transform:Lerp(CFrame.identity, weight)
		end
	end
end

-- Where each leg of group `group` has its blade now (world), for its footfalls.
function spiderLegs.FeetOf(rig: TLegs, group: number, into: { Vector3 }): { Vector3 }
	table.clear(into)
	for _, leg in rig.Legs do
		if leg.Group == group then table.insert(into, leg.Foot) end
	end

	return into
end

-- The rig let go to its clips for good (out of the animated set): every foot put down again when it comes back.
function spiderLegs.Release(rig: TLegs)
	rig.IsPlanted = false
	rig.LastRoot = nil
	rig.ThoraxWritten = nil
	rig.ThoraxBase = nil
end

return spiderLegs
