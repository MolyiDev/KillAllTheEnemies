--!nonstrict
-- What stands round the upgrade cards on the screen (UIMatt.md, Upgrade Selection): his title and its line, REROLL,
-- the auto-pick count, and the pick's ring and sparks. His rects in px at 1080, placed from the screen's MIDDLE as the
-- cards are (Stage), so the two stay together on any screen. The cards themselves are not here: they are parts in
-- the world, which this ScreenGui draws over, so nothing in it may cover where a card can be except what is thrown
-- over the chosen one.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)

local create = vide.create
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress

local Screen = {}

local Layout = table.freeze({
	-- Tops, from the top of his 1080 screen.
	TITLE_TOP = 204,
	TITLE_TEXT = 73,
	SUBTITLE_TOP = 285,
	SUBTITLE_TEXT = 22,
	REROLL_TOP = 832,
	REROLL = Vector2.new(308, 72),
	REROLL_TEXT = 22,
	DICE = 20,
	DICE_GAP = 12,
	AUTO_TOP = 926,
	AUTO_TEXT = 20,
	MIDDLE = 540,
	-- The room round REROLL inside the group that fades it, for its shadow and brackets (a CanvasGroup clips).
	MARGIN = 40,
})

local Timing = table.freeze({
	-- The header comes down into place piece by piece and goes up out of it together.
	IN = 0.32,
	OUT = 0.18,
	RISE = 16,
	STAGGER = 0.07,
	-- The count's tick, REROLL's dip as it is asked and its knock when the Gold is short.
	TICK = 0.3,
	PRESS = 0.2,
	JOLT = 0.3,
	-- The pick: one ring off the card's rim, and sparks thrown from it that slow, hang and shrink away.
	RING = 0.55,
	RING_GROW = 150,
	SPARKS = 0.8,
})

local Sparks = table.freeze({
	COUNT = 22,
	SPEED_MIN = 520,
	SPEED_MAX = 1150,
	DRAG = 5.5,
	SIZE_MIN = 9,
	SIZE_MAX = 19,
	-- They fall a little as they hang (px a second squared).
	FALL = 260,
})

-- How long the clock must run for each kind of gesture stamped on the state, so the controller can stop it after.
Screen.Seconds = table.freeze({
	HEADER = Timing.IN + 3 * Timing.STAGGER,
	GESTURE = math.max(Timing.PRESS, Timing.JOLT),
	TICK = Timing.TICK,
	PICK = math.max(Timing.RING, Timing.SPARKS),
})

-- What the screen is told (UpgradePickController writes them). Stamps are os.clock.
export type TScreenState = {
	-- Nothing is up: the whole ScreenGui is off, so its pieces at rest cost nothing.
	IsEnabled: vide.Source<boolean>,
	Scale: vide.Source<number>,
	-- os.clock while anything here is moving or counting, math.huge otherwise: every gesture reads as finished.
	Clock: vide.Source<number>,
	-- The same while a pick's ring and sparks are out: their own clock, so the count's tick does not run them.
	PickClock: vide.Source<number>,
	-- The header (title, line, REROLL, the count) is up, and when it last went up or came down.
	IsUp: vide.Source<boolean>,
	ToggledAt: vide.Source<number>,
	-- The black over the HUD as the pick opens and closes, 0 to 1 opaque.
	Curtain: vide.Source<number>,
	-- A hand is being picked from: clicks stop here instead of firing the gun.
	IsCatching: vide.Source<boolean>,
	-- The wave whose clear earned the hand; 0 for one that no wave did.
	Round: vide.Source<number>,
	RerollPrice: vide.Source<number>,
	CanReroll: vide.Source<boolean>,
	RerollAskedAt: vide.Source<number>,
	RerollDeniedAt: vide.Source<number>,
	-- Whole seconds until the server picks, and when that last ticked.
	SecondsLeft: vide.Source<number>,
	TickAt: vide.Source<number>,
	-- A card was taken: when, its rarity's colour, and where its middle and its drawn size are as it is held up
	-- (design px from the screen's middle, y up).
	PickedAt: vide.Source<number>,
	PickedColor: vide.Source<Color3>,
	PickPoint: Vector2,
	PickSize: Vector2,
}

export type TActions = {
	Reroll: () -> (),
}

local function text(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		props,
	})
end

-- 0 to 1 as a piece of the header comes in `delay` after the rest, 1 to 0 as it leaves.
local function presence(state: TScreenState, delay: number): () -> number
	return function(): number
		if state.IsUp() then return Progress(state.Clock(), state.ToggledAt(), Timing.IN, delay) end
		return 1 - Progress(state.Clock(), state.ToggledAt(), Timing.OUT)
	end
end

-- Where a piece of the header stands: `top` px from the top of his screen, dropping into place and lifting out.
local function headerPosition(state: TScreenState, shown: () -> number, top: number): () -> UDim2
	return function(): UDim2
		local t = shown()
		local rise = if state.IsUp() then Timing.RISE * (1 - Motion.Decelerate(t)) else Timing.RISE * (1 - t)
		return UDim2.new(0.5, 0, 0.5, top - Layout.MIDDLE - math.round(rise))
	end
end

local function header(state: TScreenState): { TextLabel }
	local title = presence(state, 0)
	local subtitle = presence(state, Timing.STAGGER)
	local auto = presence(state, 3 * Timing.STAGGER)
	return {
		text({
			Name = "Title",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = headerPosition(state, title, Layout.TITLE_TOP),
			Size = UDim2.fromOffset(900, Layout.TITLE_TEXT),
			TextSize = Layout.TITLE_TEXT,
			Text = "PICK AN UPGRADE",
			TextTransparency = function()
				return 1 - title()
			end,
		}),
		text({
			Name = "Subtitle",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = headerPosition(state, subtitle, Layout.SUBTITLE_TOP),
			Size = UDim2.fromOffset(900, Layout.SUBTITLE_TEXT),
			FontFace = Font.DisplayBold,
			TextSize = Layout.SUBTITLE_TEXT,
			TextColor3 = Palette.Gold,
			Text = function()
				local round = state.Round()
				return if round > 0 then `WAVE {round} CLEARED  ·  CHOOSE ONE` else "CHOOSE ONE"
			end,
			TextTransparency = function()
				return 1 - subtitle()
			end,
		}),
		text({
			Name = "AutoPick",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = headerPosition(state, auto, Layout.AUTO_TOP),
			Size = UDim2.fromOffset(400, Layout.AUTO_TEXT),
			TextSize = Layout.AUTO_TEXT,
			TextColor3 = Palette.Lavender,
			Text = function()
				return `AUTO-PICK IN {state.SecondsLeft()}`
			end,
			TextTransparency = function()
				return 1 - auto()
			end,
			create("UIScale")({
				Scale = function()
					return 1 + 0.14 * Motion.Fade(state.Clock(), state.TickAt(), Timing.TICK) ^ 2
				end,
			}),
		}),
	}
end

-- His dice: a lavender tile with four pips.
local function dice(): Frame
	local pips = table.create(4)
	for index = 0, 3 do
		pips[index + 1] = create("Frame")({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.3 + 0.4 * (index % 2), 0.3 + 0.4 * (index // 2)),
			Size = UDim2.fromOffset(4, 4),
			BackgroundColor3 = Palette.Ink,
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
		})
	end

	return create("Frame")({
		Name = "Dice",
		Size = UDim2.fromOffset(Layout.DICE, Layout.DICE),
		BackgroundColor3 = Palette.Lavender,
		BorderSizePixel = 0,
		create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
		pips,
	})
end

-- REROLL: his dark panel with the price of the next hand. Under the hand it lifts; pressed it sinks; short of Gold
-- it is dimmed and a press knocks it sideways.
local function reroll(state: TScreenState, actions: TActions): CanvasGroup
	local shown = presence(state, 2 * Timing.STAGGER)
	local hand = Hand.React("Operate", state.CanReroll)
	local ink = function(): number
		return if state.CanReroll() then 0 else 0.55
	end

	return create("CanvasGroup")({
		Name = "Reroll",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = headerPosition(state, shown, Layout.REROLL_TOP - Layout.MARGIN),
		Size = UDim2.fromOffset(Layout.REROLL.X + 2 * Layout.MARGIN, Layout.REROLL.Y + 2 * Layout.MARGIN),
		BackgroundTransparency = 1,
		GroupTransparency = function()
			return 1 - shown()
		end,
		Components.Button({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(Layout.REROLL.X, Layout.REROLL.Y),
			BackgroundTransparency = 1,
			Position = function()
				local at = state.RerollDeniedAt()
				local jolt = 8 * Motion.Shake(Progress(state.Clock(), at, Timing.JOLT), at)
				return UDim2.new(0.5, math.round(jolt), 0.5, 0)
			end,
			Activated = function()
				hand.Commit()
				actions.Reroll()
			end,
			hand.Events,
			create("UIScale")({
				Scale = function()
					local press = Motion.Bump(Progress(state.Clock(), state.RerollAskedAt(), Timing.PRESS))
					return hand.Scale() - 0.05 * press
				end,
			}),
			Components.Panel({
				Brackets = hand.Rise,
				Stroke = function()
					return Palette.EdgePink:Lerp(Palette.Pink, hand.Light())
				end,
				-- His dark drop shadow at rest, warming to a pink glow under the hand.
				Glow = function()
					return Color3.new():Lerp(Palette.Pink, hand.Light())
				end,
				GlowTransparency = function()
					return 0.6 - 0.15 * hand.Light()
				end,
			}, {
				Size = UDim2.fromScale(1, 1),
				Hand.WashLayer(hand, 2, 3),
				Components.Sheen(hand.Glint, 4),
				create("Frame")({
					Name = "Label",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(0, Layout.DICE),
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundTransparency = 1,
					ZIndex = 3,
					create("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, Layout.DICE_GAP),
					}),
					create("CanvasGroup")({
						Size = UDim2.fromOffset(Layout.DICE, Layout.DICE),
						BackgroundTransparency = 1,
						GroupTransparency = ink,
						dice(),
					}),
					text({
						Size = UDim2.fromOffset(0, Layout.REROLL_TEXT),
						AutomaticSize = Enum.AutomaticSize.X,
						TextSize = Layout.REROLL_TEXT,
						TextColor3 = Palette.Lavender,
						TextTransparency = ink,
						Text = function()
							return `REROLL   ${Components.Commas(state.RerollPrice())}`
						end,
					}),
				}),
			}),
		}),
	})
end

-- The pick's ring: one outline off the chosen card's rim, growing by px at one weight and thinning out.
local function ring(state: TScreenState): Frame
	local travel = function(): number
		return Progress(state.PickClock(), state.PickedAt(), Timing.RING)
	end

	return create("Frame")({
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, state.PickPoint.X, 0.5, -state.PickPoint.Y),
		BackgroundTransparency = 1,
		Size = function()
			local grown = 2 * math.round(Timing.RING_GROW * Motion.Decelerate(travel()))
			return UDim2.fromOffset(state.PickSize.X + grown, state.PickSize.Y + grown)
		end,
		create("UICorner")({ CornerRadius = UDim.new(0, 6) }),
		create("UIStroke")({
			Thickness = 3,
			Color = state.PickedColor,
			Transparency = function()
				local t = travel()
				return if t <= 0 then 1 else t
			end,
		}),
	})
end

-- The pick's sparks: squares thrown from the chosen card's rim (never from inside it, where its own flash is), that
-- lose their speed, hang, and shrink to nothing rather than blink out.
local function sparks(state: TScreenState): { Frame }
	local random = Random.new(41)
	local half = state.PickSize / 2
	local pieces = table.create(Sparks.COUNT)
	for index = 1, Sparks.COUNT do
		local angle = (index + random:NextNumber(-0.35, 0.35)) / Sparks.COUNT * 2 * math.pi
		local direction = Vector2.new(math.cos(angle), math.sin(angle))
		-- Where the ray from the middle leaves the card's rect.
		local reach =
			math.min(half.X / math.max(math.abs(direction.X), 1e-3), half.Y / math.max(math.abs(direction.Y), 1e-3))
		local start = direction * reach
		local speed = random:NextNumber(Sparks.SPEED_MIN, Sparks.SPEED_MAX)
		local side = random:NextInteger(Sparks.SIZE_MIN, Sparks.SIZE_MAX)
		local life = random:NextNumber(0.6, 1) * Timing.SPARKS
		local isWhite = index % 3 == 0
		local age = function(): number
			return math.clamp(state.PickClock() - state.PickedAt(), 0, life)
		end

		pieces[index] = create("Frame")({
			Name = "Spark",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BorderSizePixel = 0,
			BackgroundColor3 = if isWhite then Palette.White else state.PickedColor,
			Position = function()
				local t = age()
				local flown = speed * (1 - math.exp(-Sparks.DRAG * t)) / Sparks.DRAG
				local at = start + direction * flown
				return UDim2.new(
					0.5,
					math.round(state.PickPoint.X + at.X),
					0.5,
					math.round(-state.PickPoint.Y + at.Y + 0.5 * Sparks.FALL * t * t)
				)
			end,
			Size = function()
				local t = age() / life
				local shrunk = math.round(side * (1 - t * t))
				return UDim2.fromOffset(shrunk, shrunk)
			end,
			BackgroundTransparency = function()
				local t = age()
				return if t <= 0 or t >= life then 1 else 0
			end,
		})
	end

	return pieces
end

-- Everything placed in his 1080 px, for the ScreenGui's scaled root (and for a bench to draw without one).
function Screen.Pieces(state: TScreenState, actions: TActions): { any }
	return { header(state), reroll(state, actions), ring(state), sparks(state) }
end

-- The pick's ScreenGui. Over the HUD, under the crosshair and the console.
function Screen.Build(state: TScreenState, actions: TActions): ScreenGui
	return create("ScreenGui")({
		Name = "UpgradePick",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10,
		Enabled = state.IsEnabled,
		create("Frame")({
			Name = "Curtain",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(),
			BorderSizePixel = 0,
			BackgroundTransparency = function()
				return 1 - state.Curtain()
			end,
		}),
		-- An active button over the whole screen: a click on a card (which is in the world, under it) is a click on
		-- this, so the gun's trigger sees it as the UI's. Modal: in first person the engine holds the mouse at the centre
		-- unless a visible button says otherwise (CameraController.SetMouseFreed covers the Shift lock).
		create("TextButton")({
			Name = "Catch",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			Modal = true,
			Visible = state.IsCatching,
		}),
		create("Frame")({
			Name = "Root",
			BackgroundTransparency = 1,
			Size = function()
				local scale = state.Scale()
				return UDim2.fromScale(1 / scale, 1 / scale)
			end,
			create("UIScale")({ Scale = state.Scale }),
			Screen.Pieces(state, actions),
		}),
	})
end

return Screen
