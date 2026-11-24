--!nonstrict
-- The codes screen, in the lobby panels' look (UIMatt.md: he drew no codes screen, so it wears the
-- Spins and Daily Rewards header and his Display Name field): the field (Field), the line under it that hints, refuses
-- or cheers, and REDEEM. A code that pays grows the panel and deals what it paid into the room (Rewards). The world
-- dims, the panel rises into place, the header slides in, the rule draws out and the field, the line and REDEEM come up
-- one after another, and EXIT under it last. Closed by EXIT or a click on the dim.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Field = require(script.Field)
local Rewards = require(script.Rewards)
local Types = require(script.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress

-- Px at 1080, from the panel's top left unless said otherwise.
local Layout = table.freeze({
	-- The panel, from the screen's top left, and its height before and after a code has paid.
	PANEL = Vector2.new(530, 339),
	WIDTH = 860,
	HEIGHT = 402,
	GROWN = 614,
	-- The header, as the spins screen draws it: the glyph's middle and longer side, the title, and the rule under it.
	GLYPH = Vector2.new(48.5, 48),
	GLYPH_SIZE = 32,
	TITLE = Vector2.new(84, 26),
	TITLE_TEXT = 44,
	RULE = Vector2.new(31, 96),
	RULE_WIDTH = 798,
	-- The field's middle, the line's, REDEEM's corner and size.
	FIELD_Y = 174,
	MESSAGE_Y = 246,
	MESSAGE_TEXT = 20,
	BUTTON = Vector2.new(239, 280),
	BUTTON_SIZE = Vector2.new(382, 82),
	BUTTON_GLYPH = 30,
	BUTTON_TEXT = 31,
	BUTTON_TRACKING = 3,
	BUTTON_GAP = 14,
	-- The rule over the rewards and the cards' middle, once the panel has grown.
	REWARDS_RULE_Y = 392,
	REWARDS_Y = 496,
	-- The room round a piece inside the group that fades it, for glows, brackets and the ring (a CanvasGroup clips).
	MARGIN = 48,
})

local Timing = table.freeze({
	-- The panel decelerates up into place and accelerates down out of it, the exit the faster; its fade runs on the
	-- clock, not on the move.
	OPEN = 0.34,
	FADE = 0.27,
	RISE = 26,
	CLOSE = 0.2,
	SINK = 14,
	-- His lobby modals dim the world this much (UIMatt.md section 2: 0.7 transparent).
	DIM = 0.3,
	-- Every gesture of an open is over by now.
	SETTLED = 1.4,
	TITLE_DELAY = 0.06,
	TITLE = 0.32,
	TITLE_SLIDE = 22,
	RULE_DELAY = 0.1,
	RULE = 0.45,
	-- The field, the line and REDEEM come up a beat apart.
	FIELD_DELAY = 0.12,
	MESSAGE_DELAY = 0.2,
	BUTTON_DELAY = 0.26,
	EXIT_DELAY = 0.32,
	PIECE = 0.36,
	PIECE_FADE = 0.28,
	PIECE_RISE = 18,
	-- REDEEM catches the light as the open lands.
	SHEEN_DELAY = 0.5,
	SHEEN = 0.6,
	-- The panel grows for the rewards as they are dealt, a little ahead of the first card.
	GROW_LEAD = 0.12,
	GROW = 0.4,
	-- A new line under the field lands from a little big.
	MESSAGE_POP = 0.24,
	MESSAGE_GROW = 0.22,
	-- While the code is checked the ticket on REDEEM rattles; at a redeem it turns a whole way round.
	RATTLE_RATE = 7,
	RATTLE_DEG = 12,
	TURN_PERIOD = 0.5,
	TURN_DAMPING = 0.75,
})

-- The rules' lavender, the refusal's red.
local RULE_COLOR = Color3.fromRGB(140, 111, 210)
local RULE_TRANSPARENCY = 0.55
local RED = Color3.fromRGB(255, 72, 88)
local MESSAGE_COLORS = table.freeze({
	Hint = Palette.Lavender,
	Bad = RED,
	Good = Palette.Green,
})

local CodesUI = {}

CodesUI.LEAVE_SECONDS = Timing.CLOSE
CodesUI.COUNTED_SECONDS = Rewards.COUNTED_SECONDS
CodesUI.DEAL_STAGGER = Rewards.DEAL_STAGGER

local function label(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 2,
		props,
	})
end

-- A thin rule `width` px long that draws itself out from its left end as `drawn` runs 0 to 1.
local function rule(position: UDim2, width: number, drawn: () -> number): Frame
	return create("Frame")({
		Name = "Rule",
		Position = position,
		Size = function()
			return UDim2.fromOffset(math.round(width * Motion.Decelerate(drawn())), 1)
		end,
		BackgroundColor3 = RULE_COLOR,
		BackgroundTransparency = RULE_TRANSPARENCY,
		BorderSizePixel = 0,
		ZIndex = 2,
	})
end

-- REDEEM: his green slab with the ticket, grey with nothing typed. It rattles its ticket while the code is checked and
-- spins it round when the code pays.
local function redeemButton(state: Types.TCodesState, actions: Types.TCodesActions, landed: () -> number): TextButton
	local isLive = derive(function(): boolean
		return state.Text() ~= "" and state.Status() ~= "Checking"
	end)
	local hand = Hand.React("Operate", isLive)
	local turn, strikeTurn = Hand.Kick(Timing.TURN_PERIOD, Timing.TURN_DAMPING)
	vide.effect(function()
		local isRedeemed = state.Status() == "Redeemed"
		vide.untrack(function()
			if isRedeemed then strikeTurn(-360) end
		end)
	end)
	local rattle = derive(function(): number
		if state.Status() ~= "Checking" then return 0 end
		return Timing.RATTLE_DEG * math.sin((state.Now() - state.AskedAt()) * 2 * math.pi * Timing.RATTLE_RATE)
	end)

	return Components.Button({
		Name = "Redeem",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(Layout.BUTTON_SIZE.X, Layout.BUTTON_SIZE.Y),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Activated = function()
			hand.Commit()
			actions.Redeem()
		end,
		hand.Events,
		create("UIScale")({ Scale = hand.Scale }),
		Components.Slab({
			Kind = function()
				return if state.Text() ~= "" then "Go" else "Off"
			end,
			Marks = true,
			Brackets = true,
			GlowTransparency = function()
				return 0.6 - 0.3 * hand.Light()
			end,
		}, {
			Name = "Slab",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 4, 3),
			Components.Sheen(Hand.Sheen(hand, landed), 4),
			create("Frame")({
				Name = "Content",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 5,
				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, Layout.BUTTON_GAP),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				Components.Picture(EIcons.Ticket, {
					Name = "Ticket",
					LayoutOrder = 1,
					Size = Components.PictureBox(Layout.BUTTON_GLYPH),
					Rotation = function()
						return rattle() + turn()
					end,
					ZIndex = 5,
				}),
				Components.Tracked("REDEEM", Layout.BUTTON_TEXT, Layout.BUTTON_TRACKING, Font.Display, {
					Name = "Word",
					LayoutOrder = 2,
					ZIndex = 5,
				}),
			}),
		}),
	}) :: TextButton
end

-- The screen, built once. Returns its pieces and the Gems and XP cards' glyphs, where a code's Gems and XP fly from.
function CodesUI.Build(state: Types.TCodesState, actions: Types.TCodesActions): ({ Instance }, ImageLabel, ImageLabel)
	-- Seconds since the screen was opened or shut, held once every gesture is over, so the clock ticking for a later
	-- gesture works none of the open out again.
	local elapsed = derive(function(): number
		return math.min(state.Now() - state.ToggledAt(), Timing.SETTLED)
	end)
	local shown = derive(function(): number
		if state.IsOpen() then return Motion.Out(Progress(elapsed(), 0, Timing.FADE)) end
		return 1 - Progress(elapsed(), 0, Timing.CLOSE)
	end)
	local drop = derive(function(): number
		if state.IsOpen() then return Timing.RISE * (1 - Motion.Decelerate(Progress(elapsed(), 0, Timing.OPEN))) end
		return Timing.SINK * Motion.Accelerate(Progress(elapsed(), 0, Timing.CLOSE))
	end)
	-- 0 to 1 as a piece's own gesture runs after the screen opens; all done while it shuts.
	local function since(delay: number, seconds: number): () -> number
		return derive(function(): number
			if not state.IsOpen() then return 1 end
			return Progress(elapsed(), delay, seconds)
		end)
	end
	-- How far a piece still has to rise, 1 to 0, and how transparent it is: in on its own, out with the screen.
	local function arrival(delay: number): (() -> number, () -> number)
		local moved = since(delay, Timing.PIECE)
		local faded = since(delay, Timing.PIECE_FADE)
		return function(): number
			return 1 - Motion.Decelerate(moved())
		end, function(): number
			if not state.IsOpen() then return 1 - shown() end
			return 1 - Motion.Out(faded())
		end
	end

	local away = derive(function(): number
		if not state.IsOpen() then return 0 end
		return 1 - Motion.Decelerate(Progress(elapsed(), Timing.TITLE_DELAY, Timing.TITLE))
	end)
	-- 0 to 1 as the panel grows for the rewards; 1 for as long as they are shown.
	local grown = derive(function(): number
		if state.RewardsAt() == -math.huge then return 0 end
		return Motion.Decelerate(Progress(state.Now(), state.RewardsAt() - Timing.GROW_LEAD, Timing.GROW))
	end)
	-- The window rises half of what the panel grows, so it stays centred and the grown panel clears the lobby's
	-- bottom buttons.
	local lift = function(): number
		return (Layout.GROWN - Layout.HEIGHT) / 2 * grown()
	end
	local height = function(): number
		return Layout.HEIGHT + math.round((Layout.GROWN - Layout.HEIGHT) * grown())
	end

	local fieldAway, fieldFaded = arrival(Timing.FIELD_DELAY)
	local messageAway, messageFaded = arrival(Timing.MESSAGE_DELAY)
	local buttonAway, buttonFaded = arrival(Timing.BUTTON_DELAY)
	local buttonLanded = since(Timing.SHEEN_DELAY, Timing.SHEEN)
	-- How far EXIT still has to come, 1 to 0, rising in last; it shrinks away as the screen shuts. It is on the screen,
	-- not on the panel, so it holds still as the panel grows.
	local exitGone = derive(function(): number
		if state.IsOpen() then return 1 - Motion.Decelerate(Progress(elapsed(), Timing.EXIT_DELAY, Timing.PIECE)) end
		return Motion.Accelerate(Progress(elapsed(), 0, Timing.CLOSE))
	end)
	local messagePop = derive(function(): number
		return 1 - Motion.Out(Progress(state.Now(), state.MessageAt(), Timing.MESSAGE_POP))
	end)

	local corner = Layout.PANEL
	local cards, gemGlyph, xpGlyph =
		Rewards.Build(state, Vector2.new(corner.X + Layout.WIDTH / 2, corner.Y + Layout.REWARDS_Y), shown)

	local chrome = create("CanvasGroup")({
		Name = "Chrome",
		Position = UDim2.fromOffset(corner.X - Layout.MARGIN, corner.Y - Layout.MARGIN),
		Size = UDim2.fromOffset(Layout.WIDTH + 2 * Layout.MARGIN, Layout.GROWN + 2 * Layout.MARGIN),
		BackgroundTransparency = 1,
		GroupTransparency = function()
			return 1 - shown()
		end,
		Components.Panel({ Brackets = true, TexturePhase = Vector2.zero, Wide = true, Tall = true }, {
			Name = "Panel",
			Position = UDim2.fromOffset(Layout.MARGIN, Layout.MARGIN),
			Size = function()
				return UDim2.fromOffset(Layout.WIDTH, height())
			end,
			create("Frame")({
				Name = "Header",
				Size = UDim2.new(1, 0, 0, Layout.RULE.Y),
				BackgroundTransparency = 1,
				ClipsDescendants = true,
				ZIndex = 2,
				create("Frame")({
					Name = "Title",
					Position = function()
						return UDim2.fromOffset(-math.round(Timing.TITLE_SLIDE * away()), 0)
					end,
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Components.Picture(EIcons.Ticket, {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromOffset(Layout.GLYPH.X, Layout.GLYPH.Y),
						Size = Components.PictureBox(Layout.GLYPH_SIZE),
						ImageTransparency = away,
						ZIndex = 2,
					}),
					label({
						Position = UDim2.fromOffset(Layout.TITLE.X, Layout.TITLE.Y),
						Size = UDim2.fromOffset(400, Layout.TITLE_TEXT),
						TextSize = Layout.TITLE_TEXT,
						TextTransparency = away,
						Text = "CODES",
					}),
				}),
			}),
			rule(
				UDim2.fromOffset(Layout.RULE.X, Layout.RULE.Y),
				Layout.RULE_WIDTH,
				since(Timing.RULE_DELAY, Timing.RULE)
			),
			-- Drawn out as the panel grows for the rewards.
			rule(UDim2.fromOffset(Layout.RULE.X, Layout.REWARDS_RULE_Y), Layout.RULE_WIDTH, grown),
		}),
	})

	local fieldGroup = create("CanvasGroup")({
		Name = "FieldGroup",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(
				corner.X + Layout.WIDTH / 2,
				corner.Y + Layout.FIELD_Y + math.round(Timing.PIECE_RISE * fieldAway())
			)
		end,
		Size = UDim2.fromOffset(Field.SIZE.X + 2 * Layout.MARGIN, Field.SIZE.Y + 2 * Layout.MARGIN),
		BackgroundTransparency = 1,
		GroupTransparency = fieldFaded,
		ZIndex = 3,
		Field.Ring(state),
		Field.Build(state, actions),
	})

	local message = label({
		Name = "Message",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(
				corner.X + Layout.WIDTH / 2,
				corner.Y + Layout.MESSAGE_Y + math.round(Timing.PIECE_RISE * messageAway())
			)
		end,
		Size = UDim2.fromOffset(Layout.WIDTH - 80, Layout.MESSAGE_TEXT),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextSize = Layout.MESSAGE_TEXT,
		Text = state.Message,
		TextColor3 = function()
			return MESSAGE_COLORS[state.MessageKind()]
		end,
		TextTransparency = function()
			return math.max(messageFaded(), messagePop() * 0.8)
		end,
		ZIndex = 3,
		create("UIScale")({
			Scale = function()
				return 1 + Timing.MESSAGE_GROW * messagePop()
			end,
		}),
	})

	local buttonGroup = create("CanvasGroup")({
		Name = "ButtonGroup",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(
				corner.X + Layout.BUTTON.X + Layout.BUTTON_SIZE.X / 2,
				corner.Y + Layout.BUTTON.Y + Layout.BUTTON_SIZE.Y / 2 + math.round(Timing.PIECE_RISE * buttonAway())
			)
		end,
		Size = UDim2.fromOffset(Layout.BUTTON_SIZE.X + 2 * Layout.MARGIN, Layout.BUTTON_SIZE.Y + 2 * Layout.MARGIN),
		BackgroundTransparency = 1,
		GroupTransparency = buttonFaded,
		ZIndex = 4,
		redeemButton(state, actions, buttonLanded),
	})

	return {
		-- Modal: in first person the engine holds the mouse at the centre unless a visible button says otherwise.
		create("TextButton")({
			Name = "Dim",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Modal = true,
			Text = "",
			BackgroundTransparency = function()
				return 1 - Timing.DIM * shown()
			end,
			Activated = actions.Close,
		}),
		create("Frame")({
			Name = "Root",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(1920, 1080),
			BackgroundTransparency = 1,
			ZIndex = 2,
			create("UIScale")({ Scale = state.Scale }),
			create("Frame")({
				Name = "Window",
				Position = function()
					return UDim2.fromOffset(0, math.round(drop() - lift()))
				end,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				-- A press on the panel stops here. A Frame lets it through to the dim, which would shut the screen.
				create("TextButton")({
					Name = "Sink",
					Position = UDim2.fromOffset(corner.X, corner.Y),
					Size = function()
						return UDim2.fromOffset(Layout.WIDTH, height())
					end,
					BackgroundTransparency = 1,
					AutoButtonColor = false,
					Text = "",
				}),
				chrome,
				fieldGroup,
				message,
				buttonGroup,
				cards,
			}),
			Components.Exit(exitGone, actions.Close),
		}),
	},
		gemGlyph,
		xpGlyph
end

return CodesUI
