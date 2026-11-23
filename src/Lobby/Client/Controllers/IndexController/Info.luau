--!nonstrict
-- The enemy info panel (his right panel): the picked enemy walking on a stage in its own rig, then its page and
-- attacks as tags, its name, what it does, the maps it comes on and three numbers. His TRACK ENEMY is left out, and the
-- stage takes its room.
--
-- The stage answers the hand: a drag turns the enemy and a quick one throws it spinning, and a click makes it attack
-- (an unknown one shakes its head). A newly picked enemy swings in from the side. Between picks it sways and comes
-- back to face you, sprung, on RenderStepped, connected only while the screen is up.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local Parts = require(script.Parent.Parts)
local Picture = require(script.Parent.Picture)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local source = vide.source
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
local Label = Parts.Label
local ENEMIES = DataCore.Enemies.ById

-- His drawn rects in px at 1080, from the panel's top left. Everything under the stage is his, moved down the 96 px
-- TRACK ENEMY left, which the stage grew into.
local Layout = table.freeze({
	PANEL_RIGHT = 40,
	PANEL_Y = 190,
	SIZE = Vector2.new(440, 850),
	MARGIN = 48,
	BRACKETS = 5,
	STAGE = Vector2.new(24, 24),
	STAGE_SIZE = Vector2.new(392, 396),
	STAGE_BRACKETS = 6,
	-- Inside the stage: the rings' middle and radii, the floor's middle and size, the enemy's box and middle, the "?".
	RINGS = Vector2.new(196, 176),
	OUTER_RADIUS = 122,
	INNER_RADIUS = 86,
	FLOOR = Vector2.new(196, 352),
	FLOOR_SIZE = Vector2.new(250, 45),
	ENEMY = Vector2.new(196, 205),
	ENEMY_BOX = 340,
	MYSTERY_TEXT = 120,
	-- The tags: their row, height, side padding, gap and letters.
	TAGS = Vector2.new(24, 444),
	TAG_HEIGHT = 30,
	TAG_PAD = 10,
	TAG_GAP = 10,
	TAG_TEXT = 16,
	NAME = Vector2.new(24, 486),
	NAME_SIZE = Vector2.new(392, 56),
	DESCRIPTION = Vector2.new(24, 552),
	DESCRIPTION_SIZE = Vector2.new(392, 66),
	DESCRIPTION_TEXT = 19,
	-- The stat boxes: each column's left, each row's top, their size; inside one the caption and the value.
	STAT_XS = { 24, 226 },
	STAT_YS = { 646, 742 },
	STAT_SIZE = Vector2.new(190, 84),
	STAT_LABEL = Vector2.new(16, 15),
	STAT_LABEL_TEXT = 14,
	STAT_VALUE = Vector2.new(16, 38),
	STAT_VALUE_TEXT = 30,
})

local Timing = table.freeze({
	PANEL_DELAY = 0.1,
	PANEL_SLIDE = 40,
	-- The stage grows in from this share of its size.
	STAGE_DELAY = 0.08,
	STAGE_FROM = 0.9,
	-- The numbers run up from nothing as the panel settles, and again for each pick.
	COUNT_DELAY = 0.3,
	ROLL = 0.5,
	-- A new pick: its words slide in, and the enemy rises onto the floor from a little smaller as it swings in.
	PICK = 0.28,
	PICK_SLIDE = 16,
	RISE = 0.42,
	RISE_FROM = 26,
	GROW_FROM = 0.86,
	-- A reveal on the stage: it flashes and throws a ring, once the enemy starts coming through.
	FLASH = 0.5,
	BURST = 0.7,
	BURST_REACH = 40,
	-- A click: the body hops (px) and a ring runs out across the floor.
	HOP = -18,
	HOP_PERIOD = 0.4,
	HOP_DAMPING = 0.4,
	FLOOR_RING = 0.6,
	FLOOR_RING_GROW = 0.5,
})

-- The enemy's turn on the stage, in degrees and seconds: its sway, the spring that brings it home to face you after a
-- throw, a pick's swing in, a drag's turn per px and the fastest throw, how much of the pointer's speed each move
-- keeps, how long a pointer may rest before letting go and still throw, how far a press may move before it is a drag,
-- and an unknown one's shake of the head.
local Turn = table.freeze({
	SWAY = 14,
	SWAY_PERIOD = 6,
	HOME_PERIOD = 0.9,
	HOME_DAMPING = 0.45,
	SWING_IN = -150,
	DRAG_DEG_PER_PX = 0.5,
	MAX_THROW = 1100,
	THROW_SMOOTHING = 0.6,
	THROW_STILL_SECONDS = 0.1,
	CLICK_PX = 6,
	SHAKE = 520,
	-- A frame longer than this is stepped as this long, so a hitch does not fling the spring.
	MAX_STEP = 1 / 30,
})
local HOME_STIFFNESS = (2 * math.pi / Turn.HOME_PERIOD) ^ 2
local HOME_FRICTION = 2 * Turn.HOME_DAMPING * 2 * math.pi / Turn.HOME_PERIOD

-- What an unknown enemy's panel says.
local UNKNOWN_DESCRIPTION = "Kill one in a run to discover it."

local Info = {}

-- A number that rolls up from 0 for each pick and each open, to `target`.
local function rolled(state: Types.TIndexState, actions: Types.TIndexActions, target: () -> number): () -> number
	local at = derive(function(): number
		return math.max(state.ToggledAt() + Timing.COUNT_DELAY, state.SelectedAt())
	end)
	vide.effect(function()
		at()
		vide.untrack(function()
			actions.Stir(Timing.COUNT_DELAY + Timing.ROLL)
		end)
	end)

	return derive(function(): number
		return target() * Motion.Out(Progress(state.Now(), at(), Timing.ROLL))
	end)
end

-- One of his four stat boxes: its caption and its value.
local function statBox(column: number, row: number, caption: string, value: () -> string, color: () -> Color3): Frame
	return create("Frame")({
		Name = caption,
		Position = UDim2.fromOffset(Layout.STAT_XS[column], Layout.STAT_YS[row]),
		Size = UDim2.fromOffset(Layout.STAT_SIZE.X, Layout.STAT_SIZE.Y),
		BackgroundColor3 = Parts.STAT_EDGE,
		BorderSizePixel = 0,
		ZIndex = 4,
		create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		create("Frame")({
			Name = "Face",
			Position = UDim2.fromOffset(1, 1),
			Size = UDim2.new(1, -2, 1, -2),
			BackgroundColor3 = Parts.STAT_FACE,
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
		}),
		Label({
			Position = UDim2.fromOffset(Layout.STAT_LABEL.X, Layout.STAT_LABEL.Y),
			Size = UDim2.fromOffset(Layout.STAT_SIZE.X - 24, Layout.STAT_LABEL_TEXT),
			FontFace = Font.DisplayBold,
			TextSize = Layout.STAT_LABEL_TEXT,
			TextColor3 = Palette.Lavender,
			Text = caption,
			ZIndex = 5,
		}),
		Label({
			Position = UDim2.fromOffset(Layout.STAT_VALUE.X, Layout.STAT_VALUE.Y),
			Size = UDim2.fromOffset(Layout.STAT_SIZE.X - 24, Layout.STAT_VALUE_TEXT),
			TextScaled = true,
			TextColor3 = color,
			Text = value,
			ZIndex = 5,
			create("UITextSizeConstraint")({ MaxTextSize = Layout.STAT_VALUE_TEXT }),
		}),
	})
end

-- A tag: filled in its colour (lettered in ink), or outlined in it.
local function tag(word: string, color: Color3, isFilled: boolean, order: number, fade: () -> number): Frame
	return create("Frame")({
		Name = word,
		LayoutOrder = order,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, Layout.TAG_HEIGHT),
		BackgroundColor3 = color,
		BackgroundTransparency = if isFilled then 0 else 1,
		BorderSizePixel = 0,
		ZIndex = 4,
		create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		if isFilled
			then nil
			else create("UIStroke")({
				Color = color,
				Thickness = 1.5,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		create("UIPadding")({
			PaddingLeft = UDim.new(0, Layout.TAG_PAD),
			PaddingRight = UDim.new(0, Layout.TAG_PAD),
		}),
		Label({
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			TextYAlignment = Enum.TextYAlignment.Center,
			TextSize = Layout.TAG_TEXT,
			TextColor3 = if isFilled then Palette.Ink else color,
			TextTransparency = fade,
			Text = word,
			ZIndex = 5,
		}),
	})
end

-- The stage: the picked enemy on its floor between his rings, turning to the hand.
local function stage(
	state: Types.TIndexState,
	actions: Types.TIndexActions,
	elapsed: () -> number,
	enemy: () -> any,
	known: () -> number
): Frame
	-- It grows in from nearly its size, and shrinks away whole as the screen shuts: it is not under the panel's fade.
	local stageScale = derive(function(): number
		if not state.IsOpen() then return 1 - Motion.Accelerate(Progress(elapsed(), 0, Parts.Timing.CLOSE)) end
		local grown = Progress(elapsed(), Timing.STAGE_DELAY, Parts.Timing.SLIDE)
		return Motion.Lerp(Timing.STAGE_FROM, 1, Motion.Decelerate(grown))
	end)
	local stageFade = Parts.Faded(state, elapsed, Timing.STAGE_DELAY)
	local lit = Parts.Lit(known)
	local burned = Parts.Burned(known)
	local accent = derive(function(): Color3
		return Parts.LOCKED:Lerp(Parts.Threat(enemy()).Accent, lit())
	end)
	-- The moment the enemy on the stage last came on: the open, or the pick of another.
	local cameAt = derive(function(): number
		return math.max(state.ToggledAt() + Timing.STAGE_DELAY, state.SelectedAt())
	end)
	local risen = derive(function(): number
		if not state.IsOpen() then return 1 end
		return Progress(state.Now(), cameAt(), Timing.RISE)
	end)
	local sinceLit = Parts.SinceLit(state, state.Selected)
	local flash = Parts.Fading(sinceLit, Timing.FLASH)
	local burst = Parts.Over(sinceLit, Timing.BURST, 1)
	local hop, strikeHop = Hand.Kick(Timing.HOP_PERIOD, Timing.HOP_DAMPING)
	local floorRing = derive(function(): number
		return Progress(state.Now(), state.PokedAt(), Timing.FLOOR_RING)
	end)

	-- The turn: written every frame while the screen is up, read by the picture. It starts facing you; the pick's swing
	-- below turns it away to come in, the first one included.
	local yaw = source(0)
	local yawDeg = 0
	local velocity = 0
	local clock = 0
	local stepper: RBXScriptConnection? = nil
	local dragX: number? = nil
	local dragAt = 0
	local dragMoved = 0
	local dragSpeed = 0
	local dragConnections: { RBXScriptConnection } = {}

	-- Sprung toward the nearest whole turn plus the sway: a throw spins it on, and it settles facing you whichever
	-- turn it comes to rest on.
	local function step(dt: number)
		clock += dt
		if dragX then return end
		local seconds = math.min(dt, Turn.MAX_STEP)
		local sway = Turn.SWAY * math.sin(2 * math.pi * clock / Turn.SWAY_PERIOD)
		local home = math.round((yawDeg - sway) / 360) * 360 + sway
		velocity += (HOME_STIFFNESS * (home - yawDeg) - HOME_FRICTION * velocity) * seconds
		yawDeg += velocity * seconds
		yaw(yawDeg)
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
		yawDeg += dx * Turn.DRAG_DEG_PER_PX
		-- Smoothed, so the throw is the pointer's last few moves and not its last frame.
		dragSpeed = Turn.THROW_SMOOTHING * dragSpeed + (1 - Turn.THROW_SMOOTHING) * dx * Turn.DRAG_DEG_PER_PX / dt
		yaw(yawDeg)
	end

	local function poke()
		strikeHop(Timing.HOP)
		if lit() < 1 then
			velocity += Turn.SHAKE
		end
		actions.Poke()
	end

	local function letGo()
		local wasClick = dragMoved < Turn.CLICK_PX
		-- A drag that stopped before letting go throws nothing.
		local isStill = os.clock() - dragAt > Turn.THROW_STILL_SECONDS
		release()
		if wasClick then
			poke()
		else
			velocity = if isStill then 0 else math.clamp(dragSpeed, -Turn.MAX_THROW, Turn.MAX_THROW)
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

	-- Each pick swings in from the side.
	vide.effect(function()
		state.SelectedAt()
		vide.untrack(function()
			yawDeg += Turn.SWING_IN
			velocity = 0
		end)
	end)
	vide.effect(function()
		local isOpen = state.IsOpen()
		vide.untrack(function()
			if isOpen and not stepper then
				stepper = RunService.RenderStepped:Connect(step)
			elseif not isOpen and stepper then
				stepper:Disconnect()
				stepper = nil
				release()
			end
		end)
	end)
	vide.cleanup(function()
		release()
		if stepper then stepper:Disconnect() end
	end)

	local function circle(radius: number, edgeFade: number, fill: number): Frame
		return create("Frame")({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.RINGS.X, Layout.RINGS.Y),
			Size = UDim2.fromOffset(2 * radius, 2 * radius),
			BackgroundColor3 = accent,
			BackgroundTransparency = fill,
			BorderSizePixel = 0,
			ZIndex = 2,
			create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
			create("UIStroke")({ Color = accent, Thickness = 1.5, Transparency = edgeFade }),
			create("UIScale")({
				Scale = function()
					return Motion.Lerp(Timing.STAGE_FROM, 1, Motion.Decelerate(risen()))
				end,
			}),
		})
	end

	return Components.Card({
		Accent = function()
			return Parts.EdgeOf(accent())
		end,
		Glow = function()
			return accent():Lerp(Palette.White, flash())
		end,
		GlowTransparency = function()
			return 0.65 - 0.35 * flash()
		end,
		Tint = 0.4,
		Tall = true,
		Brackets = Layout.STAGE_BRACKETS,
		BracketLength = 22,
	}, {
		Name = "Stage",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(Layout.STAGE.X + Layout.STAGE_SIZE.X / 2, Layout.STAGE.Y + Layout.STAGE_SIZE.Y / 2),
		Size = UDim2.fromOffset(Layout.STAGE_SIZE.X, Layout.STAGE_SIZE.Y),
		ZIndex = 3,
		create("UIScale")({ Scale = stageScale }),
		circle(Layout.OUTER_RADIUS, 0.72, 1),
		circle(Layout.INNER_RADIUS, 0.78, 0.94),
		create("ImageLabel")({
			Name = "Floor",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.FLOOR.X, Layout.FLOOR.Y),
			Size = UDim2.fromOffset(Layout.FLOOR_SIZE.X, Layout.FLOOR_SIZE.Y),
			BackgroundTransparency = 1,
			Image = Icons.IMAGE,
			ImageRectOffset = Icons.FLOOR_OFFSET,
			ImageRectSize = Icons.FLOOR_SIZE,
			ImageColor3 = accent,
			ImageTransparency = Icons.FLOOR_TRANSPARENCY,
			ZIndex = 2,
		}),
		-- The ring a click sends across the floor.
		create("ImageLabel")({
			Name = "FloorRing",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.FLOOR.X, Layout.FLOOR.Y),
			Size = UDim2.fromOffset(Layout.FLOOR_SIZE.X, Layout.FLOOR_SIZE.Y),
			BackgroundTransparency = 1,
			Image = Icons.IMAGE,
			ImageRectOffset = Icons.FLOOR_OFFSET,
			ImageRectSize = Icons.FLOOR_SIZE,
			ImageColor3 = accent,
			ImageTransparency = function()
				return Icons.FLOOR_TRANSPARENCY + (1 - Icons.FLOOR_TRANSPARENCY) * floorRing()
			end,
			Visible = function()
				return floorRing() < 1
			end,
			ZIndex = 2,
			create("UIScale")({
				Scale = function()
					return 1 + Timing.FLOOR_RING_GROW * Motion.Out(floorRing())
				end,
			}),
		}),
		Picture.Build(enemy, {
			Burned = burned,
			Lit = lit,
			Yaw = yaw,
			Poke = function()
				-- An unknown enemy shakes its head rather than showing its attack.
				return if lit() >= 1 then state.PokedAt() else -math.huge
			end,
			Transparency = function()
				return math.max(stageFade(), 1 - Motion.Out(risen()))
			end,
		}, {
			Name = "Enemy",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				local rise = Timing.RISE_FROM * (1 - Motion.Decelerate(risen()))
				return UDim2.fromOffset(Layout.ENEMY.X, Layout.ENEMY.Y + math.round(rise + hop()))
			end,
			Size = UDim2.fromOffset(Layout.ENEMY_BOX, Layout.ENEMY_BOX),
			ZIndex = 3,
			create("UIScale")({
				Scale = function()
					return Motion.Lerp(Timing.GROW_FROM, 1, Motion.Decelerate(risen()))
				end,
			}),
		}),
		Label({
			Name = "Mystery",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.RINGS.X, Layout.RINGS.Y),
			Size = UDim2.fromOffset(Layout.MYSTERY_TEXT, Layout.MYSTERY_TEXT),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextSize = Layout.MYSTERY_TEXT,
			TextColor3 = Palette.Lavender,
			TextTransparency = function()
				return 0.4 + 0.6 * burned()
			end,
			Visible = function()
				return burned() < 1
			end,
			Text = "?",
			ZIndex = 4,
		}),
		create("Frame")({
			Name = "Flash",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Palette.White,
			BorderSizePixel = 0,
			ZIndex = 6,
			Visible = function()
				return flash() > 0.01
			end,
			BackgroundTransparency = function()
				return 1 - 0.6 * flash()
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		}),
		Parts.Burst(burst, Timing.BURST_REACH, accent, UDim.new(0, 4), {
			Size = UDim2.fromScale(1, 1),
			ZIndex = 6,
		}),
		-- Takes the hand over the whole stage: the press is a click or the start of a drag.
		create("TextButton")({
			Name = "Grab",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			ZIndex = 7,
			InputBegan = grab,
		}),
	})
end

function Info.Build(state: Types.TIndexState, actions: Types.TIndexActions, elapsed: () -> number): Frame
	local away = Parts.Away(state, elapsed, Timing.PANEL_DELAY)
	local faded = Parts.Faded(state, elapsed, Timing.PANEL_DELAY)
	local enemy = derive(function()
		return ENEMIES[state.Selected()]
	end)
	local known = Parts.Known(state, state.Selected)
	local lit = Parts.Lit(known)
	-- The words show the enemy once it starts coming through its silhouette.
	local isKnown = derive(function(): boolean
		return lit() > 0
	end)
	local threat = derive(function()
		return Parts.Threat(enemy())
	end)
	local picked = derive(function(): number
		return Progress(state.Now(), state.SelectedAt(), Timing.PICK)
	end)
	local pickSlide = function(): number
		return math.round(Timing.PICK_SLIDE * (1 - Motion.Decelerate(picked())))
	end
	local pickFade = function(): number
		return 1 - Motion.Out(picked())
	end
	local kills = rolled(state, actions, function(): number
		return state.Kills()[state.Selected()] or 0
	end)
	local health = rolled(state, actions, function(): number
		return enemy().BaseMaxHealth
	end)

	-- Rebuilt for each pick and as the enemy becomes known: a row's tags are laid out once.
	local tags = derive(function()
		local current = enemy()
		local isShown = isKnown()
		return vide.untrack(function()
			local category = Parts.CATEGORIES[Parts.CategoryOf(current)]
			local row = {
				tag(if current.IsBoss then "BOSS" else "MONSTER", category.Accent, true, 1, pickFade),
			}
			if isShown then
				for index, word in Parts.AttackWords(current) do
					row[index + 1] = tag(word, Parts.Threat(current).Accent, false, index + 1, pickFade)
				end
			end
			vide.cleanup(function()
				for _, item in row do
					item:Destroy()
				end
			end)
			return row
		end)
	end)

	local margin = Layout.MARGIN
	local size = Layout.SIZE

	-- The panel and what is written on it fade as one picture in a group with room for its shadow. The stage is not in
	-- it: it holds the enemy's picture and turns every frame, and a group redraws its whole canvas for every frame of
	-- that. It grows in on its own instead.
	return create("Frame")({
		Name = "Info",
		AnchorPoint = Vector2.new(1, 0),
		Position = function()
			return UDim2.new(1, -Layout.PANEL_RIGHT + math.round(Timing.PANEL_SLIDE * away()), 0, Layout.PANEL_Y)
		end,
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		ZIndex = 2,
		create("CanvasGroup")({
			Name = "Chrome",
			Position = UDim2.fromOffset(-margin, -margin),
			Size = UDim2.new(1, 2 * margin, 1, 2 * margin),
			BackgroundTransparency = 1,
			GroupTransparency = faded,
			Components.Panel({ Brackets = Layout.BRACKETS, Tall = true }, {
				Name = "Panel",
				Position = UDim2.fromOffset(margin, margin),
				Size = UDim2.fromOffset(size.X, size.Y),
				create("Frame")({
					Name = "Tags",
					Position = function()
						return UDim2.fromOffset(Layout.TAGS.X + pickSlide(), Layout.TAGS.Y)
					end,
					Size = UDim2.fromOffset(Layout.NAME_SIZE.X, Layout.TAG_HEIGHT),
					BackgroundTransparency = 1,
					ZIndex = 4,
					create("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, Layout.TAG_GAP),
					}),
					tags,
				}),
				Label({
					Name = "Name",
					Position = function()
						return UDim2.fromOffset(Layout.NAME.X + pickSlide(), Layout.NAME.Y)
					end,
					Size = UDim2.fromOffset(Layout.NAME_SIZE.X, Layout.NAME_SIZE.Y),
					TextScaled = true,
					TextYAlignment = Enum.TextYAlignment.Center,
					TextTransparency = pickFade,
					Text = function()
						return if isKnown() then string.upper(enemy().Name) else Parts.UNKNOWN
					end,
					create("UITextSizeConstraint")({ MaxTextSize = Layout.NAME_SIZE.Y }),
				}),
				Label({
					Name = "Description",
					Position = function()
						return UDim2.fromOffset(Layout.DESCRIPTION.X + pickSlide(), Layout.DESCRIPTION.Y)
					end,
					Size = UDim2.fromOffset(Layout.DESCRIPTION_SIZE.X, Layout.DESCRIPTION_SIZE.Y),
					FontFace = Font.DisplayBold,
					TextSize = Layout.DESCRIPTION_TEXT,
					TextWrapped = true,
					TextColor3 = Palette.Lavender,
					TextTransparency = pickFade,
					Text = function()
						return if isKnown() then enemy().Description else UNKNOWN_DESCRIPTION
					end,
				}),
				statBox(1, 1, "DEFEATED", function()
					return Components.Commas(if isKnown() then math.round(kills()) else 0)
				end, function()
					return Palette.White
				end),
				statBox(2, 1, "FOUND IN", function()
					return Parts.MapsText(enemy())
				end, function()
					return Palette.White
				end),
				statBox(1, 2, "HEALTH", function()
					return if isKnown() then Components.Commas(math.round(health())) else Parts.UNKNOWN
				end, function()
					return Palette.Pink
				end),
				statBox(2, 2, "THREAT", function()
					return if isKnown() then threat().Word else Parts.UNKNOWN
				end, function()
					return if isKnown() then threat().Accent else Palette.Lavender
				end),
			}),
		}),
		stage(state, actions, elapsed, enemy, known),
	})
end

return Info
