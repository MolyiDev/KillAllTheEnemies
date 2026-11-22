-- The upgrade cards as things in the world: each is a thin part held in front of the camera with its face (Card) on a
-- SurfaceGui, so a card can really turn over, lean under the hand and come toward the eye. A body is told where to
-- be in the SCREEN's terms (design px from the screen's middle, and a zoom) and rides two springs there, one for
-- where it is and one for how it is turned; the stage works out the part's place behind the lens from them, so a card
-- lands on the designer's rect at any field of view and any screen.
--
-- The dim behind them is a part too, and the only one the world can hide: a ScreenGui always draws over the world, so
-- a dim on the screen would dim the cards. The cards draw over everything in the world (AlwaysOnTop); the dim stands
-- just past the lens and is depth-tested, so it is always under them.
local Workspace = game:GetService("Workspace")

local Stage = {}
Stage.__index = Stage

local Tune = table.freeze({
	-- Studs from the lens to a card at zoom 1, and to the dim. A card's look does not depend on its depth (its size
	-- is worked out from it); the dim's is just past the near plane, so nothing but the viewmodel is in front of it.
	DEPTH = 6,
	DIM_DEPTH = 0.8,
	DIM_OVERSIZE = 1.5,
	THICKNESS = 0.02,
	-- The springs never take a step longer than this, or a hitch would throw a card off the screen.
	MAX_STEP = 1 / 120,
	MAX_FRAME = 1 / 15,
	-- A card at rest breathes: each of its three turns swings this far (rad), at these rates (rad a second), and it
	-- bobs this many design px. Off clean ratios of each other, and each card a phase apart, so nothing lines up.
	SWAY = Vector3.new(0.022, 0.034, 0.014),
	SWAY_RATE = Vector3.new(1.3, 0.9, 1.7),
	SWAY_BOB = 5,
	SWAY_PHASE = 2.1,
})

-- A card in the world. Point is (design px right of the screen's middle, design px above it, zoom); Turn is (pitch,
-- yaw, roll) in rad: a positive yaw sends the right edge away, a negative pitch the top edge. Past a quarter turn of
-- yaw the card is face down, and the stage turns the part the other half so its one SurfaceGui still faces the eye.
export type TBody = {
	Part: Part,
	Index: number,
	Rest: Vector2,
	Point: Vector3,
	PointVelocity: Vector3,
	PointTarget: Vector3,
	PointFrequency: number,
	PointDamping: number,
	Turn: Vector3,
	TurnVelocity: Vector3,
	TurnTarget: Vector3,
	TurnFrequency: number,
	TurnDamping: number,
	-- How much of the rest sway it has, 0 to 1.
	Sway: number,
	IsShown: boolean,
	IsFaceUp: boolean,
}

export type TStage = typeof(setmetatable(
	{} :: {
		Bodies: { TBody },
		Dim: Part,
		CardSize: Vector2,
		CanvasSize: Vector2,
		-- The last layout: real px a design px is, and the viewport's middle.
		Scale: number,
		Middle: Vector2,
		-- The sizes last written to the parts.
		PartSize: Vector3,
		DimSize: Vector3,
	},
	Stage
))

local function newPart(name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, Tune.THICKNESS)
	return part
end

-- A stage of cards at `rests` (design px from the screen's middle, y up). `cardSize` is a card's drawn rect and
-- `canvasSize` the whole canvas its SurfaceGui draws, both in design px.
function Stage.new(rests: { Vector2 }, cardSize: Vector2, canvasSize: Vector2): TStage
	local bodies = table.create(#rests)
	for index, rest in rests do
		bodies[index] = {
			Part = newPart(`UpgradeCard{index}`),
			Index = index,
			Rest = rest,
			Point = Vector3.new(rest.X, rest.Y, 1),
			PointVelocity = Vector3.zero,
			PointTarget = Vector3.new(rest.X, rest.Y, 1),
			PointFrequency = 3,
			PointDamping = 0.7,
			Turn = Vector3.zero,
			TurnVelocity = Vector3.zero,
			TurnTarget = Vector3.zero,
			TurnFrequency = 3,
			TurnDamping = 0.3,
			Sway = 0,
			IsShown = false,
			IsFaceUp = true,
		}
	end

	return setmetatable({
		Bodies = bodies,
		Dim = newPart("UpgradeDim"),
		CardSize = cardSize,
		CanvasSize = canvasSize,
		Scale = 1,
		Middle = Vector2.zero,
		PartSize = Vector3.zero,
		DimSize = Vector3.zero,
	}, Stage)
end

-- Puts the parts in the world (under the camera, which nothing else lists) or takes them out of it.
function Stage.SetParent(self: TStage, parent: Instance?)
	self.Dim.Parent = parent
	for _, body in self.Bodies do
		body.Part.Parent = parent
	end
end

-- Which card's REST rect `pointer` (raw viewport px) is on, and where on it: (index, u, v), u and v from -1 at the
-- left and bottom edges to 1 at the right and top; nil off every card. The rest rect, not where the card is drawn:
-- a card that leans away from the hand must not lose it. `grown` widens the rect of the card `held` already has.
function Stage.Hit(self: TStage, pointer: Vector2, held: number?, grown: number): (number?, number, number)
	local scale = self.Scale
	local half = self.CardSize * (0.5 * scale)
	for index, body in self.Bodies do
		if not body.IsShown then continue end
		local reach = if index == held then grown else 1
		local u = (pointer.X - self.Middle.X - body.Rest.X * scale) / half.X
		local v = (self.Middle.Y - body.Rest.Y * scale - pointer.Y) / half.Y
		if math.abs(u) <= reach and math.abs(v) <= reach then return index, u, v end
	end

	return nil, 0, 0
end

-- Moves every body a frame along its springs and writes its part. `scale` is the HUD's (real px a design px).
function Stage.Step(self: TStage, dt: number, now: number, scale: number)
	local camera = Workspace.CurrentCamera
	local viewport = camera.ViewportSize
	local cameraCFrame = camera.CFrame
	-- Studs a real px is at one stud of depth.
	local studsPerPx = 2 * math.tan(math.rad(camera.FieldOfView) / 2) / viewport.Y
	self.Scale = scale
	self.Middle = viewport / 2

	-- Sizes change only with the screen or the lens: written when they do, not every frame.
	local dimSize = viewport * (studsPerPx * Tune.DIM_DEPTH * Tune.DIM_OVERSIZE)
	local dim = Vector3.new(dimSize.X, dimSize.Y, Tune.THICKNESS)
	if dim ~= self.DimSize then
		self.DimSize = dim
		self.Dim.Size = dim
	end
	self.Dim.CFrame = cameraCFrame * CFrame.new(0, 0, -Tune.DIM_DEPTH)

	local frame = math.min(dt, Tune.MAX_FRAME)
	local steps = math.max(math.ceil(frame / Tune.MAX_STEP), 1)
	local step = frame / steps
	local partSize = self.CanvasSize * (scale * studsPerPx * Tune.DEPTH)
	local size = Vector3.new(partSize.X, partSize.Y, Tune.THICKNESS)
	if size ~= self.PartSize then
		self.PartSize = size
		for _, body in self.Bodies do
			body.Part.Size = size
		end
	end

	for _, body in self.Bodies do
		if not body.IsShown then continue end
		local pointOmega = body.PointFrequency * 2 * math.pi
		local turnOmega = body.TurnFrequency * 2 * math.pi
		local point, pointVelocity = body.Point, body.PointVelocity
		local turn, turnVelocity = body.Turn, body.TurnVelocity
		for _ = 1, steps do
			pointVelocity += ((body.PointTarget - point) * (pointOmega * pointOmega) - pointVelocity * (2 * body.PointDamping * pointOmega)) * step
			point += pointVelocity * step
			turnVelocity += ((body.TurnTarget - turn) * (turnOmega * turnOmega) - turnVelocity * (2 * body.TurnDamping * turnOmega)) * step
			turn += turnVelocity * step
		end
		body.Point, body.PointVelocity = point, pointVelocity
		body.Turn, body.TurnVelocity = turn, turnVelocity

		local phase = now + body.Index * Tune.SWAY_PHASE
		local sway = body.Sway
		local pitch = turn.X + sway * Tune.SWAY.X * math.sin(phase * Tune.SWAY_RATE.X)
		local yaw = turn.Y + sway * Tune.SWAY.Y * math.sin(phase * Tune.SWAY_RATE.Y)
		local roll = turn.Z + sway * Tune.SWAY.Z * math.sin(phase * Tune.SWAY_RATE.Z)
		local bob = sway * Tune.SWAY_BOB * math.sin(phase * Tune.SWAY_RATE.X + 1)

		local isFaceUp = math.cos(yaw) >= 0
		body.IsFaceUp = isFaceUp
		if not isFaceUp then
			yaw += math.pi
		end

		-- A card nearer the eye is bigger by exactly its zoom; its middle stays on its px whatever the zoom.
		local depth = Tune.DEPTH / math.max(point.Z, 0.05)
		local perPx = scale * studsPerPx * depth
		body.Part.CFrame = cameraCFrame
			* CFrame.new(point.X * perPx, (point.Y + bob) * perPx, -depth)
			* CFrame.Angles(0, 0, roll)
			* CFrame.Angles(pitch, 0, 0)
			* CFrame.Angles(0, yaw, 0)
	end
end

return Stage
