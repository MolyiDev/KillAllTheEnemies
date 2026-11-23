--!nonstrict
-- The classes screen's stage (UIMatt.md, Classes › Stage Container), on his drawn rects at 1080 with x from the
-- screen's middle: the class's name and rarity tag, his two rings, the floor, and the player's own avatar standing on
-- it, turning slowly. A drag turns it and a quick one throws it spinning; a click makes it cheer.
--
-- The avatar is turned on RenderStepped, connected only while the screen is up; its drag listens to the whole
-- screen only while it holds.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")
local vide = require(ReplicatedStorage.Packages.vide)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local avatarClips = require(script.Parent.Parent.Parent.Parent.Utils.avatarClips)
local TData = require(ReplicatedStorage.Types.TData)
local Types = require(script.Parent.Parent.Types)

local create = vide.create
local derive = vide.derive
local spring = vide.spring
local Palette = Theme.Palette
local Font = Theme.Font

-- His drawn rects: the name's top, the tag, the rings' middle and radii, the floor; and the avatar's frame: its top
-- and side, where the feet stand in it and how tall the body is.
local Layout = table.freeze({
	NAME_Y = 216,
	NAME_TEXT = 92,
	TAG = Vector2.new(-60, 312),
	TAG_SIZE = Vector2.new(120, 34),
	TAG_TEXT = 17,
	RINGS_Y = 560,
	OUTER_RADIUS = 260,
	INNER_RADIUS = 190,
	FLOOR_Y = 830,
	FLOOR_SIZE = Vector2.new(461, 84),
	EDGE = 2,
	VIEW_TOP = 330,
	VIEW = 520,
	FEET = 500,
	BODY = 400,
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

-- The pieces' way in: the rings and the floor grow from this share of their size, the name drops and the avatar
-- rises this far (px), and the tag stamps down from this much bigger.
local Arrive = table.freeze({
	RINGS_FROM = 0.82,
	NAME_FROM = 40,
	AVATAR_FROM = 40,
	STAMP = 0.4,
})

-- The avatar: the lens, how fast it turns at rest (deg a second) and how fast it settles back to that after a throw or
-- the whirl it makes as the screen opens, how far a drag turns it, the fastest a drag can throw it, how much of the
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
})
local FLOOR_IMAGE = "rbxasset://textures/whiteCircle.png"

-- How far in each piece is, 0 to 1: the rings and floor, the name, the tag, the avatar.
export type TShown = {
	Rings: () -> number,
	Name: () -> number,
	Tag: () -> number,
	Body: () -> number,
}

local Stage = {}

local function label(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		ZIndex = 4,
		props,
	})
end

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

-- The floor's outline: an ellipse of short strokes (a UICorner rounds a box into a pill, not an ellipse), drawn opaque
-- in a group that fades as one, so the joins do not double up where two strokes meet.
local function ellipseOutline(size: Vector2, transparency: () -> number, props: { [any]: any }): CanvasGroup
	local strokes = table.create(Turn.FLOOR_SEGMENTS)
	local radius = (size - Vector2.new(Layout.EDGE, Layout.EDGE)) / 2
	local center = size / 2
	local step = 2 * math.pi / Turn.FLOOR_SEGMENTS
	for index = 1, Turn.FLOOR_SEGMENTS do
		local from = center
			+ Vector2.new(math.cos((index - 1) * step) * radius.X, math.sin((index - 1) * step) * radius.Y)
		local to = center + Vector2.new(math.cos(index * step) * radius.X, math.sin(index * step) * radius.Y)
		strokes[index] = stroke(from, to, Layout.EDGE)
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
local function circle(radius: number, fill: number, edge: Color3, edgeTransparency: number): Frame
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
			Thickness = Layout.EDGE,
			Transparency = edgeTransparency,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})
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
local function avatar(state: Types.TLobbyState, shown: () -> number): (Frame, () -> ())
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

	-- Stands `copy` with its feet on the floor, facing the lens, and frames it so its body is Layout.BODY px tall
	-- with the feet Layout.FEET px down the frame.
	local function stand(copy: Model)
		copy:PivotTo(CFrame.identity)
		local box, size = copy:GetBoundingBox()
		local height = math.max(size.Y, 1)
		base = CFrame.new(0, size.Y / 2 - box.Position.Y, 0)
		place()

		local distance = height * Layout.VIEW / (2 * Layout.BODY * math.tan(math.rad(Turn.FOV / 2)))
		local middle = (Layout.FEET - Layout.VIEW / 2) / Layout.BODY * height
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
		local copy = state.Avatar()
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

	-- Turns while the screen is up, and whirls in as it opens.
	vide.effect(function()
		local isOpen = state.IsClassesOpen()
		vide.untrack(function()
			if isOpen and not stepper then
				spinDeg = Turn.ENTRY_SPIN
				stepper = RunService.RenderStepped:Connect(step)
			elseif not isOpen and stepper then
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
		Position = UDim2.new(0.5, 0, 0, Layout.VIEW_TOP),
		Size = UDim2.fromOffset(Layout.VIEW, Layout.VIEW),
		BackgroundTransparency = 1,
		ZIndex = 3,
		-- The ring a cheer sends across the floor.
		ellipseOutline(Layout.FLOOR_SIZE, function()
			return Colors.FLOOR_EDGE_TRANSPARENCY + (1 - Colors.FLOOR_EDGE_TRANSPARENCY) * ring()
		end, {
			Name = "Ring",
			Position = UDim2.fromOffset(Layout.VIEW / 2, Layout.FLOOR_Y - Layout.VIEW_TOP),
			Visible = isRinging,
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
				return UDim2.fromOffset(0, math.round(Arrive.AVATAR_FROM * (1 - shown()) + hop()))
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
			Position = UDim2.fromOffset(Layout.VIEW / 2, Layout.FEET + Layout.GRAB_SPARE),
			Size = UDim2.fromOffset(Layout.VIEW * Layout.GRAB_WIDTH, Layout.BODY + 2 * Layout.GRAB_SPARE),
			BackgroundTransparency = 1,
			Text = "",
			ZIndex = 3,
			InputBegan = grab,
		}),
	})

	return frame, celebrate
end

-- The stage for `class`, its pieces as far in as `shown` says. Returns the stage and the avatar's cheer, which the
-- class's card calls too.
function Stage.Build(state: Types.TLobbyState, class: TData.TClass, shown: TShown): (Frame, () -> ())
	local view, celebrate = avatar(state, shown.Body)
	local grown = function(): number
		return Arrive.RINGS_FROM + (1 - Arrive.RINGS_FROM) * shown.Rings()
	end

	local stage = create("Frame")({
		Name = "Stage",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		create("Frame")({
			Name = "Rings",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, Layout.RINGS_Y),
			Size = UDim2.fromOffset(2 * Layout.OUTER_RADIUS, 2 * Layout.OUTER_RADIUS),
			BackgroundTransparency = 1,
			create("UIScale")({ Scale = grown }),
			create("CanvasGroup")({
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				GroupTransparency = function()
					return 1 - shown.Rings()
				end,
				circle(Layout.OUTER_RADIUS - 1, 1, Colors.OUTER_RING, Colors.OUTER_RING_TRANSPARENCY),
				circle(
					Layout.INNER_RADIUS - 1,
					Colors.INNER_FILL_TRANSPARENCY,
					Palette.Pink,
					Colors.INNER_EDGE_TRANSPARENCY
				),
			}),
		}),
		create("Frame")({
			Name = "Floor",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, Layout.FLOOR_Y),
			Size = UDim2.fromOffset(Layout.FLOOR_SIZE.X, Layout.FLOOR_SIZE.Y),
			BackgroundTransparency = 1,
			create("UIScale")({ Scale = grown }),
			create("ImageLabel")({
				Name = "Fill",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Image = FLOOR_IMAGE,
				ImageColor3 = Palette.Pink,
				ImageTransparency = function()
					return 1 - (1 - Colors.FLOOR_FILL_TRANSPARENCY) * shown.Rings()
				end,
			}),
			ellipseOutline(Layout.FLOOR_SIZE, function()
				return 1 - (1 - Colors.FLOOR_EDGE_TRANSPARENCY) * shown.Rings()
			end, {}),
		}),
		view,
		label({
			Name = "ClassName",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = function()
				return UDim2.new(0.5, 0, 0, Layout.NAME_Y - math.round(Arrive.NAME_FROM * (1 - shown.Name())))
			end,
			Size = UDim2.fromOffset(Layout.VIEW + 180, Layout.NAME_TEXT),
			TextSize = Layout.NAME_TEXT,
			TextTransparency = function()
				return 1 - shown.Name()
			end,
			Text = string.upper(class.Name),
		}),
		create("Frame")({
			Name = "Rarity",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, Layout.TAG.X + Layout.TAG_SIZE.X / 2, 0, Layout.TAG.Y + Layout.TAG_SIZE.Y / 2),
			Size = UDim2.fromOffset(Layout.TAG_SIZE.X, Layout.TAG_SIZE.Y),
			BackgroundColor3 = Palette.Grey,
			BackgroundTransparency = function()
				return 1 - shown.Tag()
			end,
			BorderSizePixel = 0,
			ZIndex = 4,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			create("UIScale")({
				Scale = function()
					return 1 + Arrive.STAMP * (1 - shown.Tag())
				end,
			}),
			label({
				Size = UDim2.fromScale(1, 1),
				TextYAlignment = Enum.TextYAlignment.Center,
				TextSize = Layout.TAG_TEXT,
				TextColor3 = Palette.Ink,
				TextTransparency = function()
					return 1 - shown.Tag()
				end,
				Text = "COMMON",
			}),
		}),
	})

	return stage, celebrate
end

return Stage
