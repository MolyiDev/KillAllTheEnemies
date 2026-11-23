-- Solid pieces thrown off what a blow lands on (a wall's stud bricks, a gun's casing, an enemy's own bricks): pooled
-- GlobalClient/Utils/motorParts that fall, bounce twice and sink through the floor. The engine simulates none of it: Step
-- works out where each piece is and writes its joint. An owner makes its own pool, which is its cap, and steps it once
-- a frame.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local motorParts = require(script.Parent.motorParts)
local sightCast = require(ReplicatedStorage.GlobalShared.Utils.sightCast)

local thrownPieces = {}

local Tune = table.freeze({
	-- Nothing is thrown further than this from the camera.
	RANGE = 120,
	-- A toy's floaty fall, two bounces, then the piece sinks through the floor by its whole size.
	GRAVITY = 85,
	BOUNCE = 0.42,
	FRICTION = 0.55,
	BOUNCES = 2,
	LIFE = 1.1,
	SINK_SPEED = 4,
	SINK_MARGIN = 0.3,
	SPIN_MIN = 7,
	SPIN_MAX = 16,
	STEP_MAX = 1 / 20,
	-- How far over a landing point the floor is looked for again, and how far down.
	FLOOR_LOOK_UP = 2,
	FLOOR_SEARCH = 40,
})

-- Its floor is minus infinity over a drop.
type TPiece = {
	Mover: motorParts.TMover,
	Position: Vector3,
	Velocity: Vector3,
	-- It turns about Axis from the pose a turn of Angle about it gives: a random axis and angle are a random pose.
	Axis: Vector3,
	Angle: number,
	Spin: number,
	Floor: number,
	Half: number,
	Extent: number,
	Born: number,
	Bounces: number,
	SinkUntil: number,
}

export type TPool = {
	Parts: motorParts.TPool,
	Pieces: { TPiece },
	Limit: number,
	LastStep: number,
	-- The pool's own clock: real seconds, run at the scale each Step is given.
	Clock: number,
	-- What a piece coming down looks for its floor in; nil is Workspace.Arena. A bench sets its own while it stands.
	FloorParams: RaycastParams?,
	-- Called where a piece bounces on its floor, with how many times it has (1 the first time).
	Landed: ((position: Vector3, bounces: number) -> ())?,
}

local random = Random.new()

-- A pool of at most `limit` pieces, their parts under a Folder `name` in Workspace.
function thrownPieces.NewPool(name: string, limit: number): TPool
	return {
		Parts = motorParts.NewPool(name, limit),
		Pieces = {},
		Limit = limit,
		LastStep = os.clock(),
		Clock = 0,
		FloorParams = nil,
		Landed = nil,
	}
end

-- How high the floor is under `position`, or minus infinity over a drop.
function thrownPieces.FloorUnder(position: Vector3, params: RaycastParams?): number
	local result = sightCast(position, Vector3.new(0, -Tune.FLOOR_SEARCH, 0), params)
	return if result then result.Position.Y else -math.huge
end

-- How many of `wanted` pieces may be thrown `distance` studs from the camera: none far off, fewer as the pool fills,
-- so a storm keeps the pieces it has instead of churning them.
function thrownPieces.Allowed(pool: TPool, wanted: number, distance: number): number
	if wanted == 0 or distance > Tune.RANGE then return 0 end
	local limit = pool.Limit
	return math.min(wanted, math.ceil(wanted * (limit - #pool.Pieces) / limit))
end

-- Throws a copy of `template` (in `color`, or its own) from `position` over a floor at height `floor`; nothing when
-- the pool is out.
function thrownPieces.Throw(
	pool: TPool,
	template: BasePart,
	color: Color3?,
	position: Vector3,
	velocity: Vector3,
	floor: number
)
	local mover = motorParts.Take(pool.Parts, template)
	if not mover then return end
	if color then mover.Part.Color = color end

	local axis = random:NextUnitVector()
	local angle = random:NextNumber(0, math.pi * 2)
	mover.Joint.Transform = CFrame.fromAxisAngle(axis, angle) + position
	local size = mover.Size
	local pieces = pool.Pieces
	pieces[#pieces + 1] = {
		Mover = mover,
		Position = position,
		Velocity = velocity,
		Axis = axis,
		Angle = angle,
		Spin = random:NextNumber(Tune.SPIN_MIN, Tune.SPIN_MAX),
		Floor = floor,
		Half = size.Y / 2,
		Extent = size.Magnitude,
		Born = pool.Clock,
		Bounces = 0,
		SinkUntil = 0,
	}
end

local function remove(pool: TPool, index: number)
	local pieces = pool.Pieces
	motorParts.Release(pool.Parts, pieces[index].Mover)
	pieces[index] = pieces[#pieces]
	pieces[#pieces] = nil
end

-- A piece has come down to its floor: look again right under it (the floor it was thrown over may be a slope's other
-- height), and bounce only when that is where it is. True when it bounced.
local function touchDown(
	piece: TPiece,
	position: Vector3,
	velocity: Vector3,
	params: RaycastParams?
): (Vector3, Vector3, boolean)
	local floor = thrownPieces.FloorUnder(position + Vector3.new(0, Tune.FLOOR_LOOK_UP, 0), params)
	if floor < piece.Floor - 0.05 then
		piece.Floor = floor
		return position, velocity, false
	end

	piece.Floor = floor
	piece.Bounces += 1
	piece.Spin *= 0.5
	return Vector3.new(position.X, floor + piece.Half, position.Z),
		Vector3.new(velocity.X * Tune.FRICTION, -velocity.Y * Tune.BOUNCE, velocity.Z * Tune.FRICTION),
		true
end

-- `timeScale` runs the pieces slower (a match's clock: 0 holds them where they are); nil is real time.
function thrownPieces.Step(pool: TPool, timeScale: number?)
	local realNow = os.clock()
	local dt = math.min(realNow - pool.LastStep, Tune.STEP_MAX) * (timeScale or 1)
	pool.LastStep = realNow
	pool.Clock += dt
	local now = pool.Clock
	local pieces = pool.Pieces
	if #pieces == 0 then return end

	local params = pool.FloorParams
	local landed = pool.Landed
	local fall = Vector3.new(0, Tune.GRAVITY * dt, 0)
	local sink = Vector3.new(0, Tune.SINK_SPEED * dt, 0)
	for index = #pieces, 1, -1 do
		local piece = pieces[index]
		local position = piece.Position
		if piece.SinkUntil > 0 then
			if now >= piece.SinkUntil then
				remove(pool, index)
				continue
			end
			position -= sink
		else
			local velocity = piece.Velocity - fall
			position += velocity * dt
			if velocity.Y < 0 and position.Y - piece.Half <= piece.Floor then
				local isBounce
				position, velocity, isBounce = touchDown(piece, position, velocity, params)
				if isBounce and landed then landed(position, piece.Bounces) end
			end
			piece.Velocity = velocity

			if piece.Bounces >= Tune.BOUNCES or now - piece.Born >= Tune.LIFE then
				-- Fell off the map: by now it is far under the view.
				if piece.Floor == -math.huge then
					remove(pool, index)
					continue
				end
				-- Down by its whole size, so even tumbled on a slope it is under before it goes.
				piece.SinkUntil = now + (piece.Extent + Tune.SINK_MARGIN) / Tune.SINK_SPEED
				piece.Spin *= 0.3
			end
		end

		piece.Position = position
		local angle = piece.Angle + piece.Spin * dt
		piece.Angle = angle
		piece.Mover.Joint.Transform = CFrame.fromAxisAngle(piece.Axis, angle) + position
	end
end

return thrownPieces
