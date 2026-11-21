--!native
-- A killed body's fall on the client with no physics parts: the rig is one skinned MeshPart, so the ragdoll is the
-- torso's four corners and four limb ends, turned back into bone transforms (EnemiesController). It collides with the
-- floor only, and the moment the torso box reaches it the body is settled.

local ITERATIONS = 4
-- Fraction of a foot-to-torso error fixed per iteration: under 1 lets the legs give a little as the body lands.
local LEG_RIGIDITY = 0.8
-- How hard an arm is pulled back toward hanging along the torso, per iteration. Low: the arms flail.
local ARM_STIFFNESS = 0.04
local GROUND_FRICTION = 0.6
local AIR_DAMPING = 0.4
-- Give up on a body that never reaches a floor (off a ledge into the water, out of the map).
local MAX_TIME = 2.5

local abs = math.abs
local max = math.max

local Ragdoll = {}

-- The rest pose's shape, measured once per rig template, all in model space at rest.
export type TRig = {
	TorsoCenter: Vector3,
	-- Torso box half sizes (right, up, back).
	HalfSize: Vector3,
	-- Height of the top of the head over the torso centre.
	HeadTop: number,
	-- Limbs: the joint on the torso, the length to the end, and whether it holds the body up.
	Joints: { Vector3 },
	Lengths: { number },
	IsLeg: { boolean },
	-- Joints relative to TorsoCenter, in the torso's own axes (rest axes are the model's).
	JointOffsets: { Vector3 },
	-- A leg's rest distance from its foot to each of the four torso corners.
	CornerDistances: { { number } },
}

export type TBody = {
	rig: TRig,
	-- 1..4 torso corners (-x+y, +x+y, -x-y, +x-y); 4 + i the end of limb i.
	points: { Vector3 },
	velocities: { Vector3 },
	isGrounded: { boolean },
	floorY: number,
	elapsed: number,
	isSettled: boolean,
	-- Settled by reaching a floor, rather than by running out of time over nothing.
	hasLanded: boolean,
	-- The torso frame as of the last step, kept so the caller reads it without rebuilding it.
	center: Vector3,
	right: Vector3,
	up: Vector3,
	back: Vector3,
}

local CORNER_SIGNS = table.freeze({
	Vector3.new(-1, 1, 0),
	Vector3.new(1, 1, 0),
	Vector3.new(-1, -1, 0),
	Vector3.new(1, -1, 0),
})

local function restCorner(rig: TRig, i: number): Vector3
	local sign, half = CORNER_SIGNS[i], rig.HalfSize
	return rig.TorsoCenter + Vector3.new(sign.X * half.X, sign.Y * half.Y, 0)
end

function Ragdoll.NewRig(torsoCenter: Vector3, halfSize: Vector3, headTop: number): TRig
	return {
		TorsoCenter = torsoCenter,
		HalfSize = halfSize,
		HeadTop = headTop,
		Joints = {},
		Lengths = {},
		IsLeg = {},
		JointOffsets = {},
		CornerDistances = {},
	}
end

-- Every limb end is tied to all four torso corners at its rest distances; a leg holds them nearly rigid, so the body
-- topples over planted feet as one plank and lands flat. With free hips it folds onto its heels and lands sitting up
-- (tools/lune/ragdoll.luau measured both).
function Ragdoll.AddLimb(rig: TRig, joint: Vector3, length: number, isLeg: boolean): number
	local i = #rig.Joints + 1
	rig.Joints[i] = joint
	rig.Lengths[i] = length
	rig.IsLeg[i] = isLeg
	rig.JointOffsets[i] = joint - rig.TorsoCenter
	local tip = joint - Vector3.new(0, length, 0)
	local distances = table.create(4)

	for k = 1, 4 do
		distances[k] = (tip - restCorner(rig, k)).Magnitude
	end

	rig.CornerDistances[i] = distances
	return i
end

-- Recomputes the torso's centre and orthonormal axes from its four corners.
local function updateFrame(body: TBody)
	local p = body.points
	local p1, p2, p3, p4 = p[1], p[2], p[3], p[4]
	local right = ((p2 - p1) + (p4 - p3)).Unit
	local upRaw = (p1 + p2) - (p3 + p4)
	local up = (upRaw - right * upRaw:Dot(right)).Unit
	body.center = (p1 + p2 + p3 + p4) * 0.25
	body.right = right
	body.up = up
	body.back = right:Cross(up)
end

local function jointAt(body: TBody, offset: Vector3): Vector3
	return body.center + body.right * offset.X + body.up * offset.Y + body.back * offset.Z
end

-- `torso` and `limbs` map the rest pose to the body as it is posed now (the last rendered frame), so the fall picks
-- up exactly where the clip left it. `velocity` moves the whole body; `topVelocity` is added at the shoulders only,
-- which is what tips it over.
function Ragdoll.Start(
	rig: TRig,
	torso: CFrame,
	limbs: { CFrame },
	velocity: Vector3,
	topVelocity: Vector3,
	floorY: number
): TBody
	local count = 4 + #rig.Joints
	local points = table.create(count)
	local velocities = table.create(count)
	local isGrounded = table.create(count, false)

	for i, sign in CORNER_SIGNS do
		points[i] = torso * restCorner(rig, i)
		velocities[i] = if sign.Y > 0 then velocity + topVelocity else velocity
	end

	for i, joint in rig.Joints do
		points[4 + i] = limbs[i] * (joint - Vector3.new(0, rig.Lengths[i], 0))
		velocities[4 + i] = velocity
	end

	local body: TBody = {
		rig = rig,
		points = points,
		velocities = velocities,
		isGrounded = isGrounded,
		floorY = floorY,
		elapsed = 0,
		isSettled = false,
		hasLanded = false,
		center = Vector3.zero,
		right = Vector3.xAxis,
		up = Vector3.yAxis,
		back = Vector3.zAxis,
	}
	updateFrame(body)
	return body
end

-- Moves both ends toward `length` apart, `share` of the way.
local function solveDistance(points: { Vector3 }, a: number, b: number, length: number, share: number)
	local pa, pb = points[a], points[b]
	local d = pb - pa
	local dist = d.Magnitude
	if dist < 1e-6 then return end
	local correction = d * ((dist - length) / dist * 0.5 * share)
	points[a] = pa + correction
	points[b] = pb - correction
end

-- One step. Returns true on the step the torso reached the floor (or the body gave up), after which it is never
-- stepped again.
function Ragdoll.Step(body: TBody, dt: number, gravity: number): boolean
	if body.isSettled then return true end
	body.elapsed += dt

	local rig = body.rig
	local points = body.points
	local velocities = body.velocities
	local isGrounded = body.isGrounded
	local floorY = body.floorY
	local count = #points
	local half = rig.HalfSize
	local gravityStep = Vector3.new(0, -gravity * dt, 0)
	local damping = max(0, 1 - AIR_DAMPING * dt)

	local previous = table.clone(points)
	for i = 1, count do
		local v = (velocities[i] + gravityStep) * damping
		velocities[i] = v
		points[i] += v * dt
	end

	local width, height = half.X * 2, half.Y * 2
	local thickness = half.Z
	local diagonal = math.sqrt(width * width + height * height)

	for _ = 1, ITERATIONS do
		-- The torso: four edges and both diagonals, so it cannot shear or fold.
		solveDistance(points, 1, 2, width, 1)
		solveDistance(points, 3, 4, width, 1)
		solveDistance(points, 1, 3, height, 1)
		solveDistance(points, 2, 4, height, 1)
		solveDistance(points, 1, 4, diagonal, 1)
		solveDistance(points, 2, 3, diagonal, 1)

		for i, distances in rig.CornerDistances do
			local index = 4 + i
			if rig.IsLeg[i] then
				for k = 1, 4 do
					solveDistance(points, k, index, distances[k], LEG_RIGIDITY)
				end
			else
				-- An arm moves only its own end: it is light, and it must not drag the body around.
				updateFrame(body)
				local length = rig.Lengths[i]
				local joint = jointAt(body, rig.JointOffsets[i])
				local tip = points[index]
				local d = tip - joint
				local dist = d.Magnitude
				if dist > 1e-6 then
					tip -= d * ((dist - length) / dist)
				end

				tip += (joint - body.up * length - tip) * ARM_STIFFNESS
				points[index] = tip
			end
		end

		-- A limb end is the centre of the limb's end face, so a limb lying flat rests half its thickness up: the floor
		-- is raised under it by how far the limb leans over. Without this the legs prop the body up off its back.
		updateFrame(body)
		for i, offset in rig.JointOffsets do
			local index = 4 + i
			local tip = points[index]
			local axis = jointAt(body, offset) - tip
			local lean = if axis.Magnitude > 1e-6 then math.sqrt(max(0, 1 - axis.Unit.Y ^ 2)) else 0
			local restY = floorY + thickness * lean
			if tip.Y < restY then
				points[index] = Vector3.new(tip.X, restY, tip.Z)
				isGrounded[index] = true
			end
		end
	end

	updateFrame(body)

	-- The torso box's lowest point. Touching the floor ends the fall: the body is lifted out of the floor and settled.
	local right, up, back = body.right, body.up, body.back
	local lowest = body.center.Y - (abs(right.Y) * half.X + abs(up.Y) * half.Y + abs(back.Y) * half.Z)
	local isTouching = lowest <= floorY
	if isTouching then
		local lift = Vector3.new(0, floorY - lowest, 0)
		for i = 1, count do
			points[i] += lift
		end
		body.center += lift
	end

	local inverseDt = 1 / dt
	for i = 1, count do
		local v = (points[i] - previous[i]) * inverseDt
		if isGrounded[i] and points[i].Y <= floorY + thickness + 1e-3 then
			v = Vector3.new(v.X * (1 - GROUND_FRICTION), max(v.Y, 0), v.Z * (1 - GROUND_FRICTION))
		end
		velocities[i] = v
	end

	body.hasLanded = isTouching
	if isTouching or body.elapsed >= MAX_TIME then body.isSettled = true end
	return body.isSettled
end

-- Rest -> world for the torso (and Root, and the head, which ride it): world point = M * rest point, the form
-- EnemiesController's bone formula takes.
function Ragdoll.TorsoFrame(body: TBody): CFrame
	return CFrame.fromMatrix(body.center, body.right, body.up, body.back) * CFrame.new(-body.rig.TorsoCenter)
end

-- Rest -> world for limb i. The limb's long axis follows its end; its twist follows the torso's back axis.
function Ragdoll.LimbFrame(body: TBody, i: number): CFrame
	local rig = body.rig
	local joint = jointAt(body, rig.JointOffsets[i])
	local up = joint - body.points[4 + i]
	up = if up.Magnitude > 1e-6 then up.Unit else body.up
	local back = body.back - up * body.back:Dot(up)
	back = if back.Magnitude > 1e-3 then back.Unit else body.right:Cross(up).Unit
	return CFrame.fromMatrix(joint, up:Cross(back), up, back) * CFrame.new(-rig.Joints[i])
end

-- The highest point of the body, for how far it has to sink to be out of sight.
function Ragdoll.TopY(body: TBody): number
	local top = body.center.Y + abs(body.up.Y) * body.rig.HeadTop
	for _, point in body.points do
		top = max(top, point.Y)
	end

	return top
end

function Ragdoll.Center(body: TBody): Vector3
	return body.center
end

function Ragdoll.SetFloor(body: TBody, floorY: number)
	body.floorY = floorY
end

return Ragdoll
