--!nonstrict
-- One quest on the board (his Quest Card): the scroll in its group's colour, the name and what to do, the bar with its
-- count, the Gems it pays, and CLAIM, IN PROGRESS or CLAIMED.
--
-- A card grows onto its place as the board is dealt; its bar fills from empty once it lands, a light riding the fill's
-- end and the count rolling with it, and a quest that is done turns its bar green and its CLAIM grows in as the fill
-- arrives. A claim winds the card up while the server is asked; on the answer the card flashes, thumps and throws one
-- ring, the light crosses it, CLAIM shrinks away as CLAIMED comes up, and the card goes grey (its Gems are thrown by
-- the controller's payout from the reward's gem).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local QuestsCore = require(ReplicatedStorage.GlobalShared.Core.QuestsCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local Parts = require(script.Parent.Parts)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
local Label = Parts.Label

-- His drawn rects in px at 1080, from the card's top left.
local Layout = table.freeze({
	-- A px shorter than his, so two stand 12 apart: a card's brackets open to 6 px out under the hand.
	SIZE = Vector2.new(1265, 96),
	-- From one card's top to the next one's.
	ROW_STEP = 108,
	-- 3 out, opening 2 under the hand: two quests stand 11 apart, and his 7 + 3 crossed.
	BRACKET_LENGTH = 18,
	TILE = Vector2.new(14, 12),
	TILE_SIZE = 72,
	SCROLL_GLYPH = 44,
	NAME = Vector2.new(107, 17),
	NAME_TEXT = 27,
	DESCRIPTION = Vector2.new(107, 48),
	DESCRIPTION_TEXT = 17,
	BAR = Vector2.new(520, 42),
	BAR_SIZE = Vector2.new(361, 15),
	COUNT_Y = 63,
	COUNT_TEXT = 18,
	GEM = Vector2.new(934, 46),
	GEM_GLYPH = 24,
	REWARD = Vector2.new(956, 36),
	REWARD_TEXT = 24,
	BUTTON = Vector2.new(1074, 19),
	BUTTON_SIZE = Vector2.new(174, 59),
	BUTTON_TEXT = 22,
	PLAQUE = Vector2.new(1076, 21),
	PLAQUE_SIZE = Vector2.new(170, 56),
	PLAQUE_TEXT = 16,
	PLAQUE_CHECK = 15,
})

local Timing = table.freeze({
	-- The bar fills this long after the card lands, over FILL, the light on its end this many px.
	FILL_DELAY = 0.06,
	FILL = 0.7,
	HEAD = 14,
	-- A done quest's CLAIM grows in as its fill arrives.
	CLAIM_IN = 0.3,
	-- The idle light across a CLAIM waiting to be pressed: one crossing every PERIOD, each card a beat after the one above.
	IDLE_PERIOD = 2.6,
	IDLE_CROSS = 0.55,
	IDLE_STAGGER = 0.09,
	-- The press: the card and CLAIM go in while the server is asked.
	WIND_UP = 0.14,
	WIND_CARD = 0.012,
	WIND_BUTTON = 0.07,
	-- The answer: a flash, a thump, one ring, the light across, CLAIM away and CLAIMED in, and the grey coming in.
	FLASH = 0.4,
	THUMP = 0.3,
	THUMP_SIZE = 0.03,
	RING = 0.5,
	RING_REACH = 26,
	SWEEP = 0.5,
	SWAP_OUT = 0.18,
	SWAP_IN_DELAY = 0.1,
	SWAP_IN = 0.3,
	CHECK_PERIOD = 0.3,
	CHECK_DAMPING = 0.45,
	CHECK_POP = 0.45,
	TURN_DELAY = 0.35,
	TURN = 0.45,
	-- A press on a quest still going: the card shakes this many px and goes back.
	SHAKE = 0.42,
	SHAKE_REACH = 9,
	-- The hand over a card opens its brackets and lights its glow.
	GLOW = 0.7,
	GLOW_LIT = 0.3,
})

-- Everything a card's pieces read, derived once a card: what the quest is and how far it has got, and where each of
-- its gestures stands (each 0 to 1 unless it says otherwise). A gesture keyed to the claim reads the clock only once
-- the quest is claimed, so a card at rest is not worked out again on every tick.
type TCardMotion = {
	Quest: () -> QuestsCore.TQuest?,
	Goal: () -> number,
	Progress: () -> number,
	IsDone: () -> boolean,
	IsClaimed: () -> boolean,
	-- Claimed and struck: before its moment a claimed card still shows CLAIM.
	IsShownClaimed: () -> boolean,
	StrikeAt: () -> number,
	-- The bar's fill on its way in, and the share of the bar it shows.
	Fill: () -> number,
	Fraction: () -> number,
	ClaimIn: () -> number,
	-- The idle light's travel across CLAIM (1 at rest).
	Idle: () -> number,
	Wind: () -> number,
	Struck: () -> number,
	Flash: () -> number,
	Thump: () -> number,
	SwapOut: () -> number,
	SwapIn: () -> number,
	-- The card going grey.
	Turn: () -> number,
	-- A Motion.Shake, -1 to 1.
	Shake: () -> number,
	Accent: () -> Color3,
}

local Card = {}

-- The room the panel's rise makes (Parts.Lift) is shared by the board's cards: each grows by a share, its pieces
-- staying in its middle.
local function growth(): number
	return math.floor(Parts.Lift() / QuestsCore.BOARD_SIZE)
end

-- A piece laid at `at` in his card, moved down with the card's middle.
local function inCard(at: Vector2): () -> UDim2
	return function(): UDim2
		return UDim2.fromOffset(at.X, at.Y + math.round(growth() / 2))
	end
end

Card.SIZE = Layout.SIZE
-- The wind-up's length: the controller holds a fast answer's strike until it is over.
Card.WIND_UP = Timing.WIND_UP
-- How long a strike's gestures run, and a bar's fill, for the controller's clock.
Card.STRIKE_SECONDS = Timing.TURN_DELAY + Timing.TURN
Card.FILL_SECONDS = Timing.FILL_DELAY + Timing.FILL

local function motionOf(state: Types.TQuestsState, board: number, slot: number, landsAt: () -> number): TCardMotion
	local view = derive(function(): Types.TBoardView?
		return state.Boards()[board]
	end)
	local quest = derive(function(): QuestsCore.TQuest?
		local current = view()
		return if current then QuestsCore.ById[current.Ids[slot]] else nil
	end)
	local goal = derive(function(): number
		local current = quest()
		return if current then current.Goal else 1
	end)
	local progress = derive(function(): number
		local current = view()
		return if current then math.min(current.Progress[slot] or 0, goal()) else 0
	end)
	local isDone = derive(function(): boolean
		return progress() >= goal()
	end)
	local isClaimed = derive(function(): boolean
		local current = view()
		return current ~= nil and current.Claimed[slot] == true
	end)
	-- -inf for one claimed before the screen saw it.
	local strikeAt = derive(function(): number
		local strikes = state.Strikes()[board]
		return if strikes and strikes[slot] then strikes[slot] else -math.huge
	end)
	local isShownClaimed = derive(function(): boolean
		return isClaimed() and state.Now() >= strikeAt()
	end)
	-- 0 before the strike, then `curve` over `seconds` after `delay`; for a claimed card only.
	local function afterStrike(seconds: number, curve: (number) -> number, delay: number?): () -> number
		return derive(function(): number
			if not isClaimed() then return 0 end
			local now = state.Now()
			-- A cascade's later cards are stamped ahead: nothing of theirs shows before their moment.
			if now < strikeAt() then return 0 end
			return curve(Progress(now, strikeAt(), seconds, delay))
		end)
	end
	local function linear(t: number): number
		return t
	end
	local fill = derive(function(): number
		return Motion.Decelerate(Progress(state.Now(), landsAt(), Timing.FILL, Timing.FILL_DELAY))
	end)
	local turn = afterStrike(Timing.TURN, Motion.Out, Timing.TURN_DELAY)

	return {
		Quest = quest,
		Goal = goal,
		Progress = progress,
		IsDone = isDone,
		IsClaimed = isClaimed,
		IsShownClaimed = isShownClaimed,
		StrikeAt = strikeAt,
		Fill = fill,
		Fraction = derive(function(): number
			return progress() / goal() * fill()
		end),
		ClaimIn = derive(function(): number
			if not isDone() then return 0 end
			return Motion.Decelerate(Progress(state.Now(), landsAt() + Card.FILL_SECONDS, Timing.CLAIM_IN))
		end),
		Idle = derive(function(): number
			if not isDone() or isShownClaimed() or fill() < 1 or state.PendingBoard() ~= 0 then return 1 end
			local phase = (state.Pulse() - Timing.IDLE_STAGGER * slot) % Timing.IDLE_PERIOD
			return math.min(phase / Timing.IDLE_CROSS, 1)
		end),
		Wind = derive(function(): number
			if state.PendingBoard() ~= board then return 0 end
			local pressed = state.PendingSlot()
			-- CLAIM ALL (slot 0) winds up every card it will claim.
			if pressed ~= slot and not (pressed == 0 and isDone() and not isClaimed()) then return 0 end
			return Motion.Out(Progress(state.Now(), state.PressedAt(), Timing.WIND_UP))
		end),
		Struck = afterStrike(Timing.RING, linear),
		Flash = afterStrike(Timing.FLASH, function(t: number): number
			return if t < 1 then 1 - t else 0
		end),
		Thump = afterStrike(Timing.THUMP, Motion.Bump),
		SwapOut = afterStrike(Timing.SWAP_OUT, Motion.Accelerate),
		SwapIn = afterStrike(Timing.SWAP_IN, Motion.Decelerate, Timing.SWAP_IN_DELAY),
		Turn = turn,
		Shake = derive(function(): number
			if state.RefusedSlot() ~= slot or state.Board() ~= board then return 0 end
			local at = state.RefusedAt()
			return Motion.Shake(Progress(state.Now(), at, Timing.SHAKE), at)
		end),
		Accent = derive(function(): Color3
			local current = quest()
			local color = if current then Parts.ACCENTS[current.Group] else Parts.CLAIMED
			return color:Lerp(Parts.CLAIMED, turn())
		end),
	}
end

-- His bar: the track, the fill to the shown share, and the light riding its end while it moves.
local function bar(motion: TCardMotion): Frame
	return create("Frame")({
		Name = "Bar",
		Position = inCard(Layout.BAR),
		Size = UDim2.fromOffset(Layout.BAR_SIZE.X, Layout.BAR_SIZE.Y),
		BackgroundColor3 = Parts.BAR_TRACK,
		BorderSizePixel = 0,
		ZIndex = 4,
		create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		create("Frame")({
			Name = "Fill",
			-- Whole px: a fill written at a curve's every step redraws for each.
			Size = function()
				return UDim2.fromOffset(math.round(Layout.BAR_SIZE.X * motion.Fraction()), Layout.BAR_SIZE.Y)
			end,
			BackgroundColor3 = function()
				if motion.IsShownClaimed() then return Parts.BAR_FULL:Lerp(Parts.BAR_CLAIMED, motion.Turn()) end
				return if motion.Fraction() >= 1 then Parts.BAR_FULL else Parts.BAR_FILLING
			end,
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			create("Frame")({
				Name = "Head",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.new(0, Timing.HEAD, 1, 0),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				Visible = function()
					local t = motion.Fill()
					return t > 0 and t < 1 and motion.Fraction() > 0
				end,
				BackgroundTransparency = function()
					return 0.35 + 0.65 * motion.Fill()
				end,
				create("UIGradient")({
					Transparency = NumberSequence.new(1, 0),
				}),
			}),
		}),
	})
end

-- CLAIM: grows in as a done quest's fill arrives, goes in and white while the server is asked, shrinks away on the
-- strike.
local function claimButton(motion: TCardMotion, press: () -> ()): TextButton
	local hand = Hand.React("Operate")

	return Components.Button({
		Name = "Claim",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = inCard(Layout.BUTTON + Layout.BUTTON_SIZE / 2),
		Size = UDim2.fromOffset(Layout.BUTTON_SIZE.X, Layout.BUTTON_SIZE.Y),
		BackgroundTransparency = 1,
		Visible = function()
			return motion.ClaimIn() > 0 and motion.SwapOut() < 1
		end,
		ZIndex = 7,
		Activated = function()
			hand.Commit()
			press()
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return motion.ClaimIn()
					* (1 - motion.SwapOut())
					* hand.Scale()
					* (1 - Timing.WIND_BUTTON * motion.Wind())
			end,
		}),
		Components.Slab({
			Kind = "Go",
			Marks = true,
			Brackets = hand.Rise,
			GlowTransparency = function()
				return 0.6 - 0.3 * hand.Light()
			end,
		}, {
			Name = "Slab",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 3, 3),
			create("Frame")({
				Name = "Wind",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 3,
				Visible = function()
					return motion.Wind() > 0
				end,
				BackgroundTransparency = function()
					return 1 - 0.35 * motion.Wind()
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
			}),
			Components.Sheen(function(): number
				local glint = hand.Glint()
				return if glint < 1 then glint else motion.Idle()
			end, 3),
			Components.Tracked("CLAIM", Layout.BUTTON_TEXT, 2, Font.Display, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				ZIndex = 4,
			}),
		}),
	}) :: TextButton
end

-- IN PROGRESS, or CLAIMED as the claim comes up in CLAIM's place: one plaque that changes its word.
local function plaque(motion: TCardMotion): Frame
	local checkPop, strikeCheck = Hand.Kick(Timing.CHECK_PERIOD, Timing.CHECK_DAMPING)
	vide.effect(function()
		local isIn = motion.SwapIn() > 0
		vide.untrack(function()
			if isIn then strikeCheck(Timing.CHECK_POP) end
		end)
	end)

	return Parts.Plaque({
		Name = "Plaque",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = inCard(Layout.PLAQUE + Layout.PLAQUE_SIZE / 2),
		Size = UDim2.fromOffset(Layout.PLAQUE_SIZE.X, Layout.PLAQUE_SIZE.Y),
		Visible = function()
			return not motion.IsDone() or motion.IsShownClaimed()
		end,
		ZIndex = 6,
		create("UIScale")({
			Scale = function()
				if not motion.IsShownClaimed() then return 1 end
				return Motion.Lerp(0.5, 1, motion.SwapIn()) + checkPop()
			end,
		}),
		Components.Brackets(nil, 0.6, 14),
		create("Frame")({
			Name = "Word",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, Layout.PLAQUE_TEXT),
			BackgroundTransparency = 1,
			ZIndex = 4,
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 8),
			}),
			Components.Picture(EIcons.Check, {
				LayoutOrder = 1,
				Size = Components.PictureBox(Layout.PLAQUE_CHECK),
				ImageColor3 = Palette.Green,
				Visible = motion.IsShownClaimed,
			}),
			vide.show(motion.IsShownClaimed, function()
				return Components.Tracked("CLAIMED", Layout.PLAQUE_TEXT, 1, Font.Display, {
					LayoutOrder = 2,
					Color = Palette.Green,
				})
			end, function()
				return Components.Tracked("IN PROGRESS", Layout.PLAQUE_TEXT, 1, Font.Display, {
					LayoutOrder = 2,
					Color = Palette.Lavender,
				})
			end),
		}),
	})
end

-- The scroll in its tile, in the card's accent.
local function tile(motion: TCardMotion, hand: Hand.TReaction): Frame
	return create("Frame")({
		Name = "Tile",
		Position = inCard(Layout.TILE),
		Size = UDim2.fromOffset(Layout.TILE_SIZE, Layout.TILE_SIZE),
		BackgroundColor3 = function()
			return Parts.TILE_FACE:Lerp(motion.Accent(), 0.12)
		end,
		BorderSizePixel = 0,
		ZIndex = 4,
		create("UIStroke")({
			Color = motion.Accent,
			Transparency = 0.5,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Components.Picture(EIcons.Scroll, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = Components.PictureBox(Layout.SCROLL_GLYPH),
			ZIndex = 2,
			create("UIScale")({
				Scale = function()
					return 1 + 0.12 * hand.Rise() + 0.25 * motion.Thump()
				end,
			}),
		}),
	})
end

-- One ring off the card as the claim lands.
local function ring(motion: TCardMotion): Frame
	return create("Frame")({
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = function()
			local reach = 2 * math.round(Timing.RING_REACH * Motion.Decelerate(motion.Struck()))
			return UDim2.new(1, reach, 1, reach)
		end,
		BackgroundTransparency = 1,
		Visible = function()
			local t = motion.Struck()
			return t > 0 and t < 1
		end,
		ZIndex = 8,
		create("UICorner")({ CornerRadius = UDim.new(0, 5) }),
		create("UIStroke")({
			Color = Palette.White,
			Thickness = 3,
			Transparency = function()
				return 0.15 + 0.85 * motion.Struck()
			end,
		}),
	})
end

-- `landsAt` is the moment the card has grown onto its place (its bar fills from then); `dealt` its growth, 0 to 1.
function Card.Build(
	state: Types.TQuestsState,
	actions: Types.TQuestsActions,
	board: number,
	slot: number,
	dealt: () -> number,
	landsAt: () -> number
): TextButton
	local motion = motionOf(state, board, slot, landsAt)
	local hand = Hand.React("Operate", function(): boolean
		return not motion.IsShownClaimed()
	end)
	local edge = derive(function(): Color3
		return Parts.EdgeOf(motion.Accent())
	end)

	-- A done quest's CLAIM arriving ticks, so an open counts out loud what waits to be claimed.
	local isClaimUp = derive(function(): boolean
		return motion.ClaimIn() > 0
	end)
	vide.effect(function()
		local isUp = isClaimUp()
		vide.untrack(function()
			if isUp and state.IsOpen() and not motion.IsClaimed() then
				SoundsCore.PlayUINamed("UI.UpgradePick", "Tick")
			end
		end)
	end)

	local function press()
		if motion.IsShownClaimed() then return end
		actions.Claim(slot)
	end

	return Components.Button({
		Name = `Quest{slot}`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			local grow = growth()
			return UDim2.fromOffset(
				Layout.SIZE.X / 2 + math.round(Timing.SHAKE_REACH * motion.Shake()),
				(Layout.SIZE.Y + grow) / 2 + (slot - 1) * (Layout.ROW_STEP + grow)
			)
		end,
		Size = function()
			return UDim2.fromOffset(Layout.SIZE.X, Layout.SIZE.Y + growth())
		end,
		BackgroundTransparency = 1,
		ZIndex = 2 + slot,
		Activated = function()
			if not motion.IsShownClaimed() then hand.Commit() end
			press()
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return Motion.Decelerate(dealt())
					* (1 + Timing.THUMP_SIZE * motion.Thump() - Timing.WIND_CARD * motion.Wind())
			end,
		}),
		Components.Card({
			Accent = edge,
			Glow = motion.Accent,
			GlowTransparency = function()
				return Timing.GLOW - Timing.GLOW_LIT * hand.Light() - 0.3 * motion.Flash()
			end,
			Tint = 0.3,
			Wide = true,
			Brackets = hand.Rise,
			BracketLength = Layout.BRACKET_LENGTH,
			BracketTransparency = function()
				return 0.6 - 0.3 * hand.Light()
			end,
		}, {
			Name = "Card",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 3, 2),
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 3,
				Visible = function()
					return motion.Flash() > 0
				end,
				BackgroundTransparency = function()
					local flash = motion.Flash()
					return 1 - 0.45 * flash * flash
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
			}),
			Components.Sheen(function(): number
				if not motion.IsClaimed() then return 1 end
				return Progress(state.Now(), motion.StrikeAt(), Timing.SWEEP)
			end, 3),
			tile(motion, hand),
			Label({
				Name = "Title",
				Position = inCard(Layout.NAME),
				Size = UDim2.fromOffset(400, Layout.NAME_TEXT),
				TextSize = Layout.NAME_TEXT,
				Text = function()
					local quest = motion.Quest()
					return if quest then quest.Title else ""
				end,
			}),
			Label({
				Name = "Description",
				Position = inCard(Layout.DESCRIPTION),
				Size = UDim2.fromOffset(400, Layout.DESCRIPTION_TEXT),
				FontFace = Font.DisplayBold,
				TextSize = Layout.DESCRIPTION_TEXT,
				TextColor3 = Palette.Lavender,
				Text = function()
					local quest = motion.Quest()
					return if quest then quest.Description else ""
				end,
			}),
			bar(motion),
			Label({
				Name = "Count",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = inCard(Vector2.new(Layout.BAR.X + Layout.BAR_SIZE.X / 2, Layout.COUNT_Y)),
				Size = UDim2.fromOffset(Layout.BAR_SIZE.X, Layout.COUNT_TEXT),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextSize = Layout.COUNT_TEXT,
				Text = function()
					local shown = math.floor(motion.Progress() * motion.Fill() + 0.5)
					return `{Components.Commas(shown)} / {Components.Commas(motion.Goal())}`
				end,
			}),
			Components.Picture(EIcons.Gem, {
				Name = "Gem",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = inCard(Layout.GEM),
				Size = Components.PictureBox(Layout.GEM_GLYPH),
				ZIndex = 4,
				vide.action(function(instance: Instance)
					actions.MarkGem(board, slot, instance :: GuiObject)
				end),
				create("UIScale")({
					Scale = function()
						return 1 + 0.5 * motion.Thump()
					end,
				}),
			}),
			Label({
				Name = "Reward",
				Position = inCard(Layout.REWARD),
				Size = UDim2.fromOffset(160, Layout.REWARD_TEXT),
				TextSize = Layout.REWARD_TEXT,
				TextColor3 = Parts.REWARD_COLORS[board],
				Text = function()
					local quest = motion.Quest()
					return if quest then `+ {Components.Commas(quest.Gems)}` else ""
				end,
			}),
			claimButton(motion, press),
			plaque(motion),
		}),
		ring(motion),
	}) :: TextButton
end

return Card
