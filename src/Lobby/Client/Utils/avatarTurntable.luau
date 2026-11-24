--!nonstrict
-- A copy of the player's avatar standing on a stage's floor in a ViewportFrame, turning slowly, and the art behind it
-- (his rings and floor, or a Showcase look): the classes screen's and the equipment page's. A drag turns it and a quick
-- one throws it spinning; a click makes it cheer (a hop, a twirl, Roblox's cheer clip and a ring across the floor). It
-- whirls in each time its stage comes up.
--
-- The avatar is turned on RenderStepped, connected only while its stage is up; its drag listens to the whole screen
-- only while it holds.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")
local vide = require(ReplicatedStorage.Packages.vide)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Showcase = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Showcase)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local avatarClips = require(script.Parent.avatarClips)

local create = vide.create
local derive = vide.derive
local spring = vide.spring
local Palette = Theme.Palette

-- The avatar: the lens, how fast it turns at rest (deg a second) and how fast it settles back to that after a throw or
-- the whirl it makes as the stage comes up, how far a drag turns it, the fastest a drag can throw it, how much of the
-- pointer's speed each move keeps, how long a pointer may rest before letting go and still throw, and how far a press
-- may move before it is a drag. A cheer hops it (px), twirls it (deg) and sends a ring across the floor.
local Turn = table.freeze({
	FOV = 20,
	IDLE_SPIN = 18,
	ENTRY_SPIN = 720,
	SPIN_SETTLE = 0.45,
	DRAG_DEG_PER_PX = 0.5,
	MAX_THROW = 900,
	THROW_SMOOTHING = 0.6,
	THROW_STILL_SECONDS = 0.1,
	CLICK_PX = 6,
	HOP = -26,
	HOP_PERIOD = 0.42,
	HOP_DAMPING = 0.4,
	TWIRL = 540,
	CHEER_FADE = 0.1,
	RING_PERIOD = 0.7,
	RING_GROW = 0.45,
	FLOOR_SEGMENTS = 96,
	AMBIENT = Color3.fromRGB(150, 140, 172),
	LIGHT = Color3.fromRGB(255, 244, 250),
	-- Down and away from the lens, over its left shoulder.
	LIGHT_DIRECTION = Vector3.new(-0.45, -0.6, 0.66),
	-- The area that takes the hand: a share of the frame's width, and the body's height with this much spare.
	GRAB_WIDTH = 0.6,
	GRAB_SPARE = 20,
})

-- His rings and floor, sampled off his art: the outer ring's lavender, and how faint each fill and edge is.
local Colors = table.freeze({
	OUTER_RING = Color3.fromRGB(139, 111, 211),
	OUTER_RING_TRANSPARENCY = 0.74,
	INNER_FILL_TRANSPARENCY = 0.96,
	INNER_EDGE_TRANSPARENCY = 0.72,
	FLOOR_FILL_TRANSPARENCY = 0.9,
	FLOOR_EDGE_TRANSPARENCY = 0.55,
})
local FLOOR_IMAGE = "rbxasset://textures/whiteCircle.png"

-- Where a stage stands its avatar, in px of its screen from the stage's top: the square frame's top and side, where
-- the feet stand in it and how tall the body is; the floor's middle and size and its outline's width; and how far the
-- avatar rises as it comes in.
export type TFrame = {
	ViewTop: number,
	View: number,
	Feet: number,
	Body: number,
	FloorY: number,
	FloorSize: Vector2,
	Edge: number,
	RiseFrom: number,
}

-- The art behind a stage's avatar, in px of its screen from the stage's top, x from its middle: the look
-- (Showcase.LOOKS), his rings' middle and radii, the Showcase look's size, the floor's middle and size, and the edges'
-- width; how far in it is (0 to 1), its size as it grows in, the picked thing's colour, when it was last cheered and
-- whether its stage is up.
export type TArt = {
	Look: string,
	RingsY: number,
	OuterRadius: number,
	InnerRadius: number,
	Diameter: number,
	FloorY: number,
	FloorSize: Vector2,
	Edge: number,
	Shown: () -> number,
	Grown: () -> number,
	Accent: () -> Color3,
	CheeredAt: () -> number,
	IsActive: () -> boolean,
}

export type TSpec = {
	-- The copy to stand (taken by the owner each time its stage comes up), nil for none.
	Avatar: () -> Model?,
	-- Whether its stage is up: it turns only then, and whirls in each time it comes up.
	IsActive: () -> boolean,
	-- 0 to 1 as the avatar comes in.
	Shown: () -> number,
	Frame: TFrame,
	-- Whether a cheer's ring runs across the floor (his rings' floor; every other look ripples its own).
	HasFloorRing: boolean,
}

local avatarTurntable = {}

avatarTurntable.FLOOR_SEGMENTS = Turn.FLOOR_SEGMENTS

-- A straight stroke from `from` to `to`, `width` px thick.
local function stroke(from: Vector2, to: Vector2, width: number): Frame
	local along = to - from
	local middle = (from + to) / 2
	return create("Frame")({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(middle.X, middle.Y),
		Size = UDim2.fromOffset(along.Magnitude + width / 2, width),
		Rotation = math.deg(math.atan2(along.Y, along.X)),
		BackgroundColor3 = Palette.White,
		BorderSizePixel = 0,
	})
end

-- A floor's outline: an ellipse of short strokes `edge` px wide (a UICorner rounds a box into a pill, not an ellipse),
-- drawn opaque in a group that fades as one, so the joins do not double up where two strokes meet.
function avatarTurntable.Ellipse(
	size: Vector2,
	edge: number,
	transparency: () -> number,
	props: { [any]: any }
): CanvasGroup
	local strokes = table.create(Turn.FLOOR_SEGMENTS)
	local radius = (size - Vector2.new(edge, edge)) / 2
	local center = size / 2
	local step = 2 * math.pi / Turn.FLOOR_SEGMENTS
	for index = 1, Turn.FLOOR_SEGMENTS do
		local from = center
			+ Vector2.new(math.cos((index - 1) * step) * radius.X, math.sin((index - 1) * step) * radius.Y)
		local to = center + Vector2.new(math.cos(index * step) * radius.X, math.sin(index * step) * radius.Y)
		strokes[index] = stroke(from, to, edge)
	end

	return create("CanvasGroup")({
		Name = "Outline",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		GroupColor3 = Palette.Pink,
		GroupTransparency = transparency,
		strokes,
		props,
	})
end

-- A circle of `radius` round the rings' middle: a faint pink fill and an edge.
local function circle(radius: number, edgeWidth: number, fill: number, edge: Color3, edgeTransparency: number): Frame
	return create("Frame")({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(2 * radius, 2 * radius),
		BackgroundColor3 = Palette.Pink,
		BackgroundTransparency = fill,
		BorderSizePixel = 0,
		create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
		create("UIStroke")({
			Color = edge,
			Thickness = edgeWidth,
			Transparency = edgeTransparency,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})
end

-- The art behind the avatar: his two rings and his floor, or a Showcase look, which lays its own floor. Returns what
-- goes behind the avatar and what goes over it (a look's particles; nil for his rings and for a look whose particles
-- stay behind).
function avatarTurntable.Art(spec: TArt): ({ Instance }, Frame?)
	if spec.Look ~= "Rings" then
		local back, front = Showcase.Build({
			Look = spec.Look,
			Diameter = spec.Diameter,
			Floor = spec.FloorY - spec.RingsY,
			FloorSize = spec.FloorSize,
			Accent = spec.Accent,
			Shown = spec.Shown,
			CheeredAt = spec.CheeredAt,
			IsActive = spec.IsActive,
		}, {
			Position = UDim2.new(0.5, 0, 0, spec.RingsY),
		}, {
			Position = UDim2.new(0.5, 0, 0, spec.RingsY),
			-- Over the avatar.
			ZIndex = 4,
		})
		return { back }, front
	end

	local shown = spec.Shown
	return {
		create("Frame")({
			Name = "Rings",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, spec.RingsY),
			Size = UDim2.fromOffset(2 * spec.OuterRadius, 2 * spec.OuterRadius),
			BackgroundTransparency = 1,
			create("UIScale")({ Scale = spec.Grown }),
			create("CanvasGroup")({
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				GroupTransparency = function()
					return 1 - shown()
				end,
				circle(spec.OuterRadius - 1, spec.Edge, 1, Colors.OUTER_RING, Colors.OUTER_RING_TRANSPARENCY),
				circle(
					spec.InnerRadius - 1,
					spec.Edge,
					Colors.INNER_FILL_TRANSPARENCY,
					Palette.Pink,
					Colors.INNER_EDGE_TRANSPARENCY
				),
			}),
		}),
		create("Frame")({
			Name = "Floor",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, spec.FloorY),
			Size = UDim2.fromOffset(spec.FloorSize.X, spec.FloorSize.Y),
			BackgroundTransparency = 1,
			create("UIScale")({ Scale = spec.Grown }),
			create("ImageLabel")({
				Name = "Fill",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Image = FLOOR_IMAGE,
				ImageColor3 = Palette.Pink,
				ImageTransparency = function()
					return 1 - (1 - Colors.FLOOR_FILL_TRANSPARENCY) * shown()
				end,
			}),
			avatarTurntable.Ellipse(spec.FloorSize, spec.Edge, function()
				return 1 - (1 - Colors.FLOOR_EDGE_TRANSPARENCY) * shown()
			end, {}),
		}),
	},
		nil
end

-- The track playing `id` on `animator`.
local function load(animator: Animator, id: string, isLooped: boolean): AnimationTrack
	local clip = Instance.new("Animation")
	clip.AnimationId = id
	local track = animator:LoadAnimation(clip)
	track.Looped = isLooped
	return track
end

-- The avatar on the floor, turning. Returns the frame and the cheer.
function avatarTurntable.Build(spec: TSpec): (Frame, () -> ())
	local layout = spec.Frame
	local shown = spec.Shown
	local world = create("WorldModel")({})
	local camera = create("Camera")({ FieldOfView = Turn.FOV })
	local hop, strikeHop = Hand.Kick(Turn.HOP_PERIOD, Turn.HOP_DAMPING)
	local ring, configureRing = spring(function()
		return 1
	end, Turn.RING_PERIOD, 1)
	local isRinging = derive(function(): boolean
		return ring() < 0.995
	end)

	local model: Model? = nil
	local base = CFrame.identity
	local cheer: AnimationTrack? = nil
	local yawDeg = 0
	local spinDeg = Turn.IDLE_SPIN
	local stepper: RBXScriptConnection? = nil
	-- The drag: the pointer's last x and when it moved, how far it has moved in all, its speed, and its listeners
	-- while it holds.
	local dragX: number? = nil
	local dragAt = 0
	local dragMoved = 0
	local dragSpeed = 0
	local dragConnections: { RBXScriptConnection } = {}

	local function place()
		if not model then return end
		model:PivotTo(base * CFrame.Angles(0, math.rad(yawDeg), 0))
	end

	-- Stands `copy` with its feet on the floor, facing the lens, and frames it so its body is layout.Body px tall
	-- with the feet layout.Feet px down the frame.
	local function stand(copy: Model)
		copy:PivotTo(CFrame.identity)
		local box, size = copy:GetBoundingBox()
		local height = math.max(size.Y, 1)
		base = CFrame.new(0, size.Y / 2 - box.Position.Y, 0)
		place()

		local distance = height * layout.View / (2 * layout.Body * math.tan(math.rad(Turn.FOV / 2)))
		local middle = (layout.Feet - layout.View / 2) / layout.Body * height
		camera.CFrame = CFrame.lookAt(Vector3.new(0, middle, -distance), Vector3.new(0, middle, 0))
	end

	local function play(copy: Model)
		local humanoid = copy:FindFirstChildOfClass("Humanoid")
		local animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
		if not animator then return end

		load(animator, avatarClips.IDLE, true):Play(0)
		local cheerTrack = load(animator, avatarClips.CHEER, false)
		cheerTrack.Priority = Enum.AnimationPriority.Action
		cheer = cheerTrack
	end

	local function step(dt: number)
		if dragX then return end
		spinDeg = Turn.IDLE_SPIN + (spinDeg - Turn.IDLE_SPIN) * math.exp(-dt / Turn.SPIN_SETTLE)
		yawDeg = (yawDeg + spinDeg * dt) % 360
		place()
	end

	local function celebrate()
		strikeHop(Turn.HOP)
		spinDeg += Turn.TWIRL
		configureRing({ position = 0, velocity = 0 })
		if cheer then cheer:Play(Turn.CHEER_FADE) end
	end

	local function release()
		for _, connection in dragConnections do
			connection:Disconnect()
		end
		table.clear(dragConnections)
		dragX = nil
	end

	local function drag(moved: InputObject, input: InputObject)
		local isMove = moved.UserInputType == Enum.UserInputType.MouseMovement
			or (moved.UserInputType == Enum.UserInputType.Touch and moved == input)
		if not isMove or not dragX then return end
		local dx = moved.Position.X - dragX
		local now = os.clock()
		local dt = math.max(now - dragAt, 1 / 240)
		dragX = moved.Position.X
		dragAt = now
		dragMoved += math.abs(dx)
		yawDeg = (yawDeg + dx * Turn.DRAG_DEG_PER_PX) % 360
		-- Smoothed, so the throw is the pointer's last few moves and not its last frame.
		dragSpeed = Turn.THROW_SMOOTHING * dragSpeed + (1 - Turn.THROW_SMOOTHING) * dx * Turn.DRAG_DEG_PER_PX / dt
		place()
	end

	local function letGo()
		local wasClick = dragMoved < Turn.CLICK_PX
		-- A drag that stopped before letting go throws nothing.
		local isStill = os.clock() - dragAt > Turn.THROW_STILL_SECONDS
		release()
		if wasClick then
			celebrate()
		else
			spinDeg = if isStill then 0 else math.clamp(dragSpeed, -Turn.MAX_THROW, Turn.MAX_THROW)
		end
	end

	local function grab(input: InputObject)
		local isPointer = input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		if not isPointer or dragX then return end
		dragX = input.Position.X
		dragAt = os.clock()
		dragMoved = 0
		dragSpeed = 0

		-- The whole screen, not the stage: a drag may leave it.
		dragConnections[1] = UserInputService.InputChanged:Connect(function(moved: InputObject)
			drag(moved, input)
		end)
		dragConnections[2] = UserInputService.InputEnded:Connect(function(ended: InputObject)
			if ended.UserInputType == input.UserInputType then letGo() end
		end)
	end

	vide.effect(function()
		local copy = spec.Avatar()
		vide.untrack(function()
			model = copy
			cheer = nil
			if not copy then return end
			local root = copy:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then root.Anchored = true end
			stand(copy)
			copy.Parent = world
			play(copy)
		end)
	end)

	-- Turns while its stage is up, and whirls in as it comes up.
	vide.effect(function()
		local isActive = spec.IsActive()
		vide.untrack(function()
			if isActive and not stepper then
				spinDeg = Turn.ENTRY_SPIN
				stepper = RunService.RenderStepped:Connect(step)
			elseif not isActive and stepper then
				stepper:Disconnect()
				stepper = nil
			end
		end)
	end)

	vide.cleanup(function()
		release()
		if stepper then stepper:Disconnect() end
	end)

	local frame = create("Frame")({
		Name = "Avatar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, layout.ViewTop),
		Size = UDim2.fromOffset(layout.View, layout.View),
		BackgroundTransparency = 1,
		ZIndex = 3,
		-- The ring a cheer sends across his floor; the other looks' floors ripple of their own.
		avatarTurntable.Ellipse(layout.FloorSize, layout.Edge, function()
			return Colors.FLOOR_EDGE_TRANSPARENCY + (1 - Colors.FLOOR_EDGE_TRANSPARENCY) * ring()
		end, {
			Name = "Ring",
			Position = UDim2.fromOffset(layout.View / 2, layout.FloorY - layout.ViewTop),
			Visible = function()
				return spec.HasFloorRing and isRinging()
			end,
			ZIndex = 1,
			create("UIScale")({
				Scale = function()
					return 1 + Turn.RING_GROW * Motion.Out(ring())
				end,
			}),
		}),
		create("ViewportFrame")({
			Name = "View",
			Position = function()
				return UDim2.fromOffset(0, math.round(layout.RiseFrom * (1 - shown()) + hop()))
			end,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BackgroundColor3 = Color3.new(),
			Ambient = Turn.AMBIENT,
			LightColor = Turn.LIGHT,
			LightDirection = Turn.LIGHT_DIRECTION,
			ImageTransparency = function()
				return 1 - shown()
			end,
			CurrentCamera = camera,
			ZIndex = 2,
			camera,
			world,
		}),
		-- Takes the hand over the body: the press is a click or the start of a drag.
		create("TextButton")({
			Name = "Grab",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromOffset(layout.View / 2, layout.Feet + Turn.GRAB_SPARE),
			Size = UDim2.fromOffset(layout.View * Turn.GRAB_WIDTH, layout.Body + 2 * Turn.GRAB_SPARE),
			BackgroundTransparency = 1,
			Text = "",
			ZIndex = 3,
			InputBegan = grab,
		}),
	})

	return frame, celebrate
end

return avatarTurntable
