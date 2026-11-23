--!nonstrict
-- The middle of the screen: his stage (two rings and a floor) with the picked gun's own model turning gently on it,
-- the skin plate and its swatch, and EXIT. There is one skin a gun so far: the plate and the swatch show it, as he drew
-- them. The gun turns in as it is picked, and turns once more round as it is bought, raised or put on the back, the
-- stage throwing one ring out of its middle.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Parts = require(script.Parent.Parts)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
local Label = Parts.Label

-- His drawn rects in px at 1080, from the screen's top left.
local Layout = table.freeze({
	-- The stage: its middle and the two rings' diameters, the floor's middle and size.
	STAGE = Vector2.new(960, 500),
	OUTER = 600,
	INNER = 440,
	FLOOR = Vector2.new(960, 742),
	FLOOR_SIZE = Vector2.new(470, 84),
	-- The gun's box, round the middle of his gun.
	GUN = Vector2.new(960, 530),
	GUN_BOX = 470,
	PLATE = Vector2.new(740, 800),
	PLATE_SIZE = Vector2.new(440, 64),
	SKIN_WORD = Vector2.new(24, 24),
	SKIN_WORD_TEXT = 16,
	SKIN_NAME = Vector2.new(80, 17),
	SKIN_NAME_TEXT = 29,
	SKIN_COUNT_RIGHT = 419,
	SKIN_COUNT_Y = 21,
	SKIN_COUNT_TEXT = 22,
	SWATCH = Vector2.new(926, 880),
	SWATCH_SIZE = 69,
	SWATCH_GUN = 58,
	SWATCH_BADGE = Vector2.new(41, 9),
	SWATCH_BADGE_SIZE = 19,
	EXIT = Vector2.new(809, 969),
	EXIT_SIZE = Vector2.new(302, 72),
	EXIT_TEXT = 32,
})

-- His stage's colours, sampled off the art.
local OUTER_RING = Color3.fromRGB(139, 111, 211)
local OUTER_TRANSPARENCY = 0.75
local INNER_RING_TRANSPARENCY = 0.72
local INNER_FILL_TRANSPARENCY = 0.96

local Timing = table.freeze({
	STAGE_DELAY = 0.06,
	-- The rings grow onto their size from this share of it.
	RINGS_FROM = 0.9,
	-- The gun's idle sway: degrees each way and seconds a swing.
	SWAY = 16,
	SWAY_PERIOD = 7,
	-- A gun coming on: it turns in from half way round, from a little smaller.
	TURN_IN = 0.6,
	TURN_IN_FROM = -150,
	GROW_FROM = 0.82,
	-- A gun bought, raised or put on the back: a whole turn, a pop, and one ring out of the stage.
	SPIN = 0.9,
	POP_PERIOD = 0.26,
	POP_DAMPING = 0.58,
	POP = 0.12,
	BURST = 0.6,
	BURST_REACH = 90,
	GLOW = 0.6,
	-- The plate, the swatch and EXIT rise in last, under everything.
	BOTTOM_DELAYS = { 0.2, 0.24, 0.28 },
	RISE = 24,
})

local Stage = {}

-- The middle of the gun on the stage, in his 1920 x 1080: Flight pours a purchase's Gems into it.
Stage.GUN_AT = Layout.GUN

-- A circle, or an ellipse, `size` px across: its outline and its fill.
local function round(name: string, size: Vector2, ring: Color3, ringFade: any, fill: Color3, fillFade: any): Frame
	return create("Frame")({
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = fill,
		BackgroundTransparency = fillFade,
		BorderSizePixel = 0,
		create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
		create("UIStroke")({ Color = ring, Thickness = 1.5, Transparency = ringFade }),
	})
end

function Stage.Build(state: Types.TWeaponsState, actions: Types.TWeaponsActions, elapsed: () -> number): { Instance }
	local stageFade = Parts.Faded(state, elapsed, Timing.STAGE_DELAY)
	local stageIn = Parts.Since(state, elapsed, Timing.STAGE_DELAY, Parts.Timing.SLIDE)
	local shown = function(alpha: number): () -> number
		return function(): number
			return alpha + (1 - alpha) * stageFade()
		end
	end

	-- The moment the gun on the stage last came on: the open, or the pick of another.
	local cameAt = derive(function(): number
		return math.max(state.ToggledAt() + Timing.STAGE_DELAY, state.SelectedAt())
	end)
	local turnedIn = derive(function(): number
		if not state.IsOpen() then return 1 end
		return Progress(state.Now(), cameAt(), Timing.TURN_IN)
	end)
	-- The last purchase or level of the gun on show, and its colour.
	local paidAt = derive(function(): number
		local selected = state.Selected()
		local bought = if state.BoughtGun() == selected then state.BoughtAt() else -math.huge
		local raised = if state.UpgradedGun() == selected then state.UpgradedAt() else -math.huge
		return math.max(bought, raised)
	end)
	local isUpgrade = derive(function(): boolean
		return state.UpgradedGun() == state.Selected() and state.UpgradedAt() >= paidAt()
	end)
	-- When the gun on show last went on the back. Taking it off is the button's moment only.
	local wornAt = derive(function(): number
		local selected = state.Selected()
		if state.ShownFor() ~= selected or state.Shown() ~= selected then return -math.huge end
		return state.ShownAt()
	end)
	local isWorn = derive(function(): boolean
		return wornAt() > paidAt()
	end)
	local cheeredAt = derive(function(): number
		return math.max(paidAt(), wornAt())
	end)
	local spun = derive(function(): number
		return Progress(state.Now(), cheeredAt(), Timing.SPIN)
	end)
	local burst = derive(function(): number
		return Progress(state.Now(), cheeredAt(), Timing.BURST)
	end)
	local glow = derive(function(): number
		if state.Now() < cheeredAt() then return 0 end
		return Motion.Fade(state.Now(), cheeredAt(), Timing.GLOW)
	end)
	local pop, strikePop = Hand.Kick(Timing.POP_PERIOD, Timing.POP_DAMPING)
	local hasLanded = derive(function(): boolean
		return state.Now() >= cheeredAt() and state.Now() < cheeredAt() + Timing.SPIN
	end)
	vide.effect(function()
		if not hasLanded() then return end
		vide.untrack(function()
			strikePop(Timing.POP)
		end)
	end)
	local burstColor = function(): Color3
		if isWorn() then return Palette.Green end
		return if isUpgrade() then Palette.Gold else Palette.Pink
	end

	local yaw = function(): number
		local sway = Timing.SWAY * math.sin(2 * math.pi * state.StageClock() / Timing.SWAY_PERIOD)
		local turn = Timing.TURN_IN_FROM * (1 - Motion.Decelerate(turnedIn()))
		local spin = 360 * Motion.Decelerate(spun())
		return sway + turn + spin
	end

	local exitHand = Hand.React("Operate")
	local plateAway = Parts.Away(state, elapsed, Timing.BOTTOM_DELAYS[1])
	local plateFade = Parts.Faded(state, elapsed, Timing.BOTTOM_DELAYS[1])
	-- The swatch and EXIT grow in rather than fading under a group: the swatch holds a gun's picture and EXIT
	-- moves under the hand, and a group redraws its whole canvas for every frame of either.
	local swatchAway = Parts.Away(state, elapsed, Timing.BOTTOM_DELAYS[2])
	local exitAway = Parts.Away(state, elapsed, Timing.BOTTOM_DELAYS[3])

	local stage = create("Frame")({
		Name = "Stage",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(Layout.STAGE.X, Layout.STAGE.Y),
		Size = UDim2.fromOffset(Layout.OUTER, Layout.OUTER),
		BackgroundTransparency = 1,
		create("UIScale")({
			Scale = function()
				return Motion.Lerp(Timing.RINGS_FROM, 1, Motion.Decelerate(stageIn()))
			end,
		}),
		round("Outer", Vector2.new(Layout.OUTER, Layout.OUTER), OUTER_RING, shown(OUTER_TRANSPARENCY), OUTER_RING, 1),
		round(
			"Inner",
			Vector2.new(Layout.INNER, Layout.INNER),
			Palette.Pink,
			shown(INNER_RING_TRANSPARENCY),
			Palette.Pink,
			function()
				local base = INNER_FILL_TRANSPARENCY + (1 - INNER_FILL_TRANSPARENCY) * stageFade()
				return base - 0.12 * glow()
			end
		),
		-- The one ring a purchase throws out of the stage's middle.
		create("Frame")({
			Name = "Burst",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = function()
				local diameter = Layout.INNER + 2 * math.round(Timing.BURST_REACH * Motion.Out(burst()))
				return UDim2.fromOffset(diameter, diameter)
			end,
			BackgroundTransparency = 1,
			Visible = function()
				return burst() > 0 and burst() < 1
			end,
			create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
			create("UIStroke")({ Color = burstColor, Thickness = 3, Transparency = burst }),
		}),
	})

	local floor = create("Frame")({
		Name = "Floor",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(Layout.FLOOR.X, Layout.FLOOR.Y),
		Size = UDim2.fromOffset(Layout.FLOOR_SIZE.X, Layout.FLOOR_SIZE.Y),
		BackgroundTransparency = 1,
		create("UIScale")({
			Scale = function()
				return Motion.Lerp(Timing.RINGS_FROM, 1, Motion.Decelerate(stageIn()))
			end,
		}),
		create("ImageLabel")({
			Name = "Ellipse",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = Icons.IMAGE,
			ImageRectOffset = Icons.FLOOR_OFFSET,
			ImageRectSize = Icons.FLOOR_SIZE,
			ImageColor3 = Palette.Pink,
			ImageTransparency = function()
				local base = Icons.FLOOR_TRANSPARENCY + (1 - Icons.FLOOR_TRANSPARENCY) * stageFade()
				return base - 0.3 * glow()
			end,
		}),
	})

	local gun = Parts.Gun(state.Selected, {
		Yaw = yaw,
		Transparency = function()
			return math.max(stageFade(), 1 - Motion.Out(turnedIn()))
		end,
	}, {
		Name = "Gun",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(Layout.GUN.X, Layout.GUN.Y),
		Size = UDim2.fromOffset(Layout.GUN_BOX, Layout.GUN_BOX),
		ZIndex = 2,
		create("UIScale")({
			Scale = function()
				return Motion.Lerp(Timing.GROW_FROM, 1, Motion.Decelerate(turnedIn())) + pop()
			end,
		}),
	})

	-- A Panel is many layers, so the plate fades as one picture under a group with room for its shadow.
	local plateGroup = create("CanvasGroup")({
		Name = "Skin",
		Position = function()
			return UDim2.fromOffset(Layout.PLATE.X - 48, Layout.PLATE.Y - 48 + math.round(Timing.RISE * plateAway()))
		end,
		Size = UDim2.fromOffset(Layout.PLATE_SIZE.X + 96, Layout.PLATE_SIZE.Y + 96),
		BackgroundTransparency = 1,
		GroupTransparency = plateFade,
		ZIndex = 3,
		Components.Panel({ Brackets = 5 }, {
			Name = "Plate",
			Position = UDim2.fromOffset(48, 48),
			Size = UDim2.fromOffset(Layout.PLATE_SIZE.X, Layout.PLATE_SIZE.Y),
			Label({
				Position = UDim2.fromOffset(Layout.SKIN_WORD.X, Layout.SKIN_WORD.Y),
				Size = UDim2.fromOffset(60, Layout.SKIN_WORD_TEXT),
				TextSize = Layout.SKIN_WORD_TEXT,
				TextColor3 = Palette.Lavender,
				Text = "SKIN",
			}),
			Label({
				Position = UDim2.fromOffset(Layout.SKIN_NAME.X, Layout.SKIN_NAME.Y),
				Size = UDim2.fromOffset(240, Layout.SKIN_NAME_TEXT),
				TextSize = Layout.SKIN_NAME_TEXT,
				Text = "DEFAULT",
			}),
			Label({
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromOffset(Layout.SKIN_COUNT_RIGHT, Layout.SKIN_COUNT_Y),
				Size = UDim2.fromOffset(100, Layout.SKIN_COUNT_TEXT),
				TextXAlignment = Enum.TextXAlignment.Right,
				TextSize = Layout.SKIN_COUNT_TEXT,
				Text = "1 / 1",
			}),
		}),
	})

	local swatchAccent = Palette.Pink
	local swatch = create("Frame")({
		Name = "Swatch",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(
				Layout.SWATCH.X + Layout.SWATCH_SIZE / 2,
				Layout.SWATCH.Y + Layout.SWATCH_SIZE / 2 + math.round(Timing.RISE * swatchAway())
			)
		end,
		Size = UDim2.fromOffset(Layout.SWATCH_SIZE, Layout.SWATCH_SIZE),
		BackgroundTransparency = 1,
		ZIndex = 3,
		create("UIScale")({
			Scale = function()
				return 1 - swatchAway()
			end,
		}),
		Parts.Ring(5, {
			Size = UDim2.fromScale(1, 1),
		}),
		Components.Card({ Accent = Parts.EdgeOf(swatchAccent), Glow = swatchAccent, Tint = 0.4, Edge = 3 }, {
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
			Parts.Gun(state.Selected, {}, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.55),
				Size = UDim2.fromOffset(Layout.SWATCH_GUN, Layout.SWATCH_GUN),
				ZIndex = 4,
			}),
			Parts.Badge("Check", Layout.SWATCH_BADGE_SIZE, {
				Position = UDim2.fromOffset(Layout.SWATCH_BADGE.X, Layout.SWATCH_BADGE.Y),
				ZIndex = 5,
			}),
		}),
	})

	local exit = Components.Button({
		Name = "Exit",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(
				Layout.EXIT.X + Layout.EXIT_SIZE.X / 2,
				Layout.EXIT.Y + Layout.EXIT_SIZE.Y / 2 + math.round(Timing.RISE * exitAway())
			)
		end,
		Size = UDim2.fromOffset(Layout.EXIT_SIZE.X, Layout.EXIT_SIZE.Y),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Activated = function()
			exitHand.Commit()
			actions.Close()
		end,
		exitHand.Events,
		create("UIScale")({
			Scale = function()
				return (1 - exitAway()) * exitHand.Scale()
			end,
		}),
		Components.Slab({
			Kind = "Pink",
			Marks = true,
			Brackets = function()
				return 5 + 3 * exitHand.Rise()
			end,
			GlowTransparency = function()
				return 0.6 - 0.3 * exitHand.Light()
			end,
		}, {
			Name = "Slab",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(exitHand, 3, 3),
			Components.Sheen(exitHand.Glint, 3),
			Components.Tracked("EXIT", Layout.EXIT_TEXT, 2, Font.Display, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				ZIndex = 4,
			}),
		}),
	})

	return { stage, floor, gun, plateGroup, swatch, exit }
end

return Stage
