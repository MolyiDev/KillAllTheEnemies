--!nonstrict
-- A daily or weekly quest finished in the match (Quests.Completed): its card slides in under the Gold packs, its bar
-- fills, COMPLETE is stamped on it, and its band says the Gems wait in the lobby. One card at a time (init queues them);
-- every gesture runs off state.Quest.At and its own Clock, written only while a card is up. The card is the lobby
-- quest card's sibling: the group's accent, the scroll tile, the bar, the dark plaque with the green check.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local QuestLook = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.QuestLook)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local QuestsCore = require(ReplicatedStorage.GlobalShared.Core.QuestsCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress

-- In px at 1080: the card's place (the Gold packs' left edge, 22 under the second pack, whose brackets reach 13 px
-- out under the hand) and size, and its pieces from its top left.
local Layout = table.freeze({
	LEFT = 40,
	TOP = 887,
	SIZE = Vector2.new(392, 108),
	BAND = 30,
	TILE = Vector2.new(12, 11),
	TILE_SIZE = 56,
	SCROLL = 38,
	KICKER = Vector2.new(80, 12),
	KICKER_TEXT = 13,
	TITLE = Vector2.new(80, 27),
	TITLE_SIZE = Vector2.new(174, 22),
	BAR = Vector2.new(80, 57),
	BAR_SIZE = Vector2.new(172, 9),
	PLAQUE = Vector2.new(321, 39),
	PLAQUE_SIZE = Vector2.new(118, 32),
	PLAQUE_TEXT = 13,
	PLAQUE_CHECK = 13,
	BAND_PAD = 14,
	BAND_TEXT = 14,
	GEM = 22,
	REWARD_TEXT = 19,
})

-- Seconds from the card's start. It slides in from off the screen's left, decelerating; its bar fills from empty; as
-- the fill arrives COMPLETE is stamped (the card flashes, thumps and throws one ring, the light crosses it, the plaque
-- grows in with its check popping, the Gems pop); then the band catches the light every CALL_EVERY until it slides
-- back out, accelerating.
local Timing = table.freeze({
	SLIDE = 0.42,
	FILL_AT = 0.34,
	FILL = 0.66,
	HEAD = 12,
	STRIKE = 1.06,
	FLASH = 0.4,
	THUMP = 0.3,
	THUMP_SIZE = 0.035,
	RING = 0.5,
	RING_REACH = 26,
	SWEEP = 0.55,
	STAMP_IN = 0.28,
	CHECK_PERIOD = 0.3,
	CHECK_DAMPING = 0.45,
	CHECK_POP = 0.45,
	GEM_DELAY = 0.12,
	GEM_POP = 0.32,
	CALL_AT = 1.9,
	CALL_EVERY = 2.2,
	CALL_CROSS = 0.6,
	LEAVE = 0.3,
	-- Past the strike, how long a card stays: shorter while another waits behind it.
	HOLD = 4.4,
	SHORT_HOLD = 2.6,
})
-- Off the screen's left, glow included.
local AWAY = Layout.LEFT + Layout.SIZE.X + 48
-- COMPLETE's sound, by board: Daily, Weekly (Assets/sounds/Review/QuestToast).
local STRIKE_SOUNDS = table.freeze({ "StampDaily", "StampWeekly" })
local KICKERS = table.freeze({ "DAILY QUEST", "WEEKLY QUEST" })
-- The glow's transparency on the way in, and brighter once the quest is stamped COMPLETE.
local GLOW = 0.7
local GLOW_DONE = 0.5

local QuestToast = {}

QuestToast.HOLD = Timing.HOLD
QuestToast.SHORT_HOLD = Timing.SHORT_HOLD

-- A card's whole life, for one held `hold` seconds past its strike: init runs its clock this long.
function QuestToast.Seconds(hold: number): number
	return Timing.STRIKE + hold + Timing.LEAVE
end

local function label(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 4,
		props,
	})
end

local function linear(t: number): number
	return t
end

-- 1 the moment it starts, falling to 0 as `t` runs out, and 0 before and after: a flash.
local function fadeOut(t: number): number
	return if t > 0 and t < 1 then 1 - t else 0
end

-- `picture` in a still square `side` px in a list: a list places its children by their top left, so a picture that
-- pops is centred in a holder the list places, and grows from its own middle.
local function centred(order: number, side: number, picture: ImageLabel): Frame
	return create("Frame")({
		LayoutOrder = order,
		Size = UDim2.fromOffset(side, side),
		BackgroundTransparency = 1,
		ZIndex = 5,
		picture,
	})
end

function QuestToast.Build(state: Types.THudState): Frame
	local notice = state.Quest
	local quest = derive(function(): QuestsCore.TQuest?
		return QuestsCore.ById[notice.Id()]
	end)
	local board = derive(function(): number
		return math.clamp(notice.Board(), 1, #KICKERS)
	end)
	local accent = derive(function(): Color3
		local current = quest()
		return if current then QuestLook.ACCENTS[current.Group] else Palette.Grey
	end)
	local edge = derive(function(): Color3
		return QuestLook.EdgeOf(accent())
	end)

	-- Seconds into the card, held at its end so a card gone reads as gone.
	local elapsed = derive(function(): number
		return math.clamp(notice.Clock() - notice.At(), 0, QuestToast.Seconds(notice.Hold()))
	end)
	local leaveAt = derive(function(): number
		return Timing.STRIKE + notice.Hold()
	end)
	-- How far off its place it is, 1 to 0 and back to 1.
	local away = derive(function(): number
		local t = elapsed()
		if t >= leaveAt() then return Motion.Accelerate(Progress(t, leaveAt(), Timing.LEAVE)) end
		return 1 - Motion.Decelerate(Progress(t, 0, Timing.SLIDE))
	end)
	local fill = derive(function(): number
		return Motion.Decelerate(Progress(elapsed(), Timing.FILL_AT, Timing.FILL))
	end)
	local isStruck = derive(function(): boolean
		return elapsed() >= Timing.STRIKE
	end)
	-- `curve` of the stamp's progress over `seconds`, from `delay` after it.
	local function afterStrike(seconds: number, curve: (number) -> number, delay: number?): () -> number
		return derive(function(): number
			return curve(Progress(elapsed(), Timing.STRIKE, seconds, delay))
		end)
	end
	local flash = afterStrike(Timing.FLASH, fadeOut)
	local thump = afterStrike(Timing.THUMP, Motion.Bump)
	local struck = afterStrike(Timing.RING, linear)
	local sweep = afterStrike(Timing.SWEEP, linear)
	local stampIn = afterStrike(Timing.STAMP_IN, Motion.Decelerate)
	local gemPop = afterStrike(Timing.GEM_POP, Motion.Bump, Timing.GEM_DELAY)
	-- The band's light: a crossing every CALL_EVERY once the stamp has settled, none on the way out.
	local call = derive(function(): number
		local t = elapsed() - Timing.CALL_AT
		if t < 0 or elapsed() >= leaveAt() then return 1 end
		return math.min((t % Timing.CALL_EVERY) / Timing.CALL_CROSS, 1)
	end)

	local checkPop, strikeCheck = Hand.Kick(Timing.CHECK_PERIOD, Timing.CHECK_DAMPING)
	-- The card coming in deals, as the upgrade pick's cards do; the stamp lands with its board's sound.
	local isShown = derive(function(): boolean
		return notice.Id() ~= 0 and elapsed() > 0
	end)
	vide.effect(function()
		local shown = isShown()
		vide.untrack(function()
			if shown then SoundsCore.PlayUINamed("UI.UpgradePick", "Deal") end
		end)
	end)
	vide.effect(function()
		local isOn = isStruck()
		vide.untrack(function()
			if not isOn or notice.Id() == 0 then return end
			strikeCheck(Timing.CHECK_POP)
			SoundsCore.PlayUINamed("UI.Quest", STRIKE_SOUNDS[board()])
		end)
	end)

	local bar = create("Frame")({
		Name = "Bar",
		Position = UDim2.fromOffset(Layout.BAR.X, Layout.BAR.Y),
		Size = UDim2.fromOffset(Layout.BAR_SIZE.X, Layout.BAR_SIZE.Y),
		BackgroundColor3 = QuestLook.BAR_TRACK,
		BorderSizePixel = 0,
		ZIndex = 4,
		create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		create("Frame")({
			Name = "Fill",
			-- Whole px: a fill written at a curve's every step redraws for each.
			Size = function()
				return UDim2.fromOffset(math.round(Layout.BAR_SIZE.X * fill()), Layout.BAR_SIZE.Y)
			end,
			BackgroundColor3 = function()
				return if fill() >= 1 then QuestLook.BAR_FULL else QuestLook.BAR_FILLING
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
					local t = fill()
					return t > 0 and t < 1
				end,
				BackgroundTransparency = function()
					return 0.35 + 0.65 * fill()
				end,
				create("UIGradient")({ Transparency = NumberSequence.new(1, 0) }),
			}),
		}),
	})

	-- COMPLETE in his dark plaque, the lobby's CLAIMED plaque's sibling: grown in from half its size as it is stamped.
	local plaque = create("Frame")({
		Name = "Plaque",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(Layout.PLAQUE.X, Layout.PLAQUE.Y),
		Size = UDim2.fromOffset(Layout.PLAQUE_SIZE.X, Layout.PLAQUE_SIZE.Y),
		BackgroundColor3 = QuestLook.PLAQUE_EDGE,
		BorderSizePixel = 0,
		Visible = isStruck,
		ZIndex = 6,
		create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
		create("UIGradient")({
			Rotation = 90,
			Color = ColorSequence.new(Palette.White, Color3.new(0.8, 0.8, 0.8)),
		}),
		create("UIScale")({
			Scale = function()
				return Motion.Lerp(0.5, 1, stampIn()) + checkPop()
			end,
		}),
		create("Frame")({
			Name = "Face",
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			BackgroundColor3 = QuestLook.PLAQUE_FACE,
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
		}),
		Components.Brackets(nil, 0.6, 12),
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
				Padding = UDim.new(0, 6),
			}),
			centred(
				1,
				Layout.PLAQUE_CHECK,
				Components.Picture(EIcons.Check, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = Components.PictureBox(Layout.PLAQUE_CHECK),
					ImageColor3 = Palette.Green,
					create("UIScale")({
						Scale = function()
							return 1 + 2 * checkPop()
						end,
					}),
				})
			),
			Components.Tracked("COMPLETE", Layout.PLAQUE_TEXT, 1, Font.Display, {
				LayoutOrder = 2,
				Color = Palette.Green,
			}),
		}),
	})

	-- The Gems waiting in the lobby, on the right of the band.
	local reward = create("Frame")({
		Name = "Reward",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -Layout.BAND_PAD, 1, -Layout.BAND / 2),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, Layout.GEM),
		BackgroundTransparency = 1,
		ZIndex = 4,
		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 5),
		}),
		centred(
			1,
			Layout.GEM,
			Components.Picture(EIcons.Gem, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = Components.PictureBox(Layout.GEM),
				ZIndex = 5,
				create("UIScale")({
					Scale = function()
						return 1 + 0.5 * gemPop()
					end,
				}),
			})
		),
		label({
			LayoutOrder = 2,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, Layout.REWARD_TEXT),
			TextSize = Layout.REWARD_TEXT,
			TextColor3 = function()
				return QuestLook.REWARD_COLORS[board()]
			end,
			Text = function()
				local current = quest()
				return if current then `+ {Components.Commas(current.Gems)}` else ""
			end,
		}),
	})

	return create("Frame")({
		Name = "QuestToast",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			local x = Layout.LEFT + Layout.SIZE.X / 2 - math.round(AWAY * away())
			return UDim2.fromOffset(x, Layout.TOP + Layout.SIZE.Y / 2)
		end,
		Size = UDim2.fromOffset(Layout.SIZE.X, Layout.SIZE.Y),
		BackgroundTransparency = 1,
		Visible = isShown,
		create("UIScale")({
			Scale = function()
				return 1 + Timing.THUMP_SIZE * thump()
			end,
		}),
		Components.Card({
			Accent = edge,
			Glow = accent,
			GlowTransparency = function()
				return (if isStruck() then GLOW_DONE else GLOW) - 0.3 * flash()
			end,
			Tint = 0.3,
			Band = Layout.BAND,
		}, {
			Name = "Card",
			Size = UDim2.fromScale(1, 1),
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 7,
				Visible = function()
					return flash() > 0
				end,
				BackgroundTransparency = function()
					local t = flash()
					return 1 - 0.45 * t * t
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
			}),
			Components.Sheen(sweep, 7, Layout.SIZE.X / Layout.SIZE.Y),
			create("Frame")({
				Name = "Tile",
				Position = UDim2.fromOffset(Layout.TILE.X, Layout.TILE.Y),
				Size = UDim2.fromOffset(Layout.TILE_SIZE, Layout.TILE_SIZE),
				BackgroundColor3 = function()
					return QuestLook.TILE_FACE:Lerp(accent(), 0.12)
				end,
				BorderSizePixel = 0,
				ZIndex = 4,
				create("UIStroke")({
					Color = accent,
					Transparency = 0.5,
					Thickness = 1,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				}),
				Components.Picture(EIcons.Scroll, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = Components.PictureBox(Layout.SCROLL),
					ZIndex = 2,
					create("UIScale")({
						Scale = function()
							return 1 + 0.25 * thump()
						end,
					}),
				}),
			}),
			label({
				Name = "Kicker",
				Position = UDim2.fromOffset(Layout.KICKER.X, Layout.KICKER.Y),
				Size = UDim2.fromOffset(Layout.TITLE_SIZE.X, Layout.KICKER_TEXT),
				TextSize = Layout.KICKER_TEXT,
				TextColor3 = function()
					return QuestLook.REWARD_COLORS[board()]
				end,
				Text = function()
					return KICKERS[board()]
				end,
			}),
			label({
				Name = "Title",
				Position = UDim2.fromOffset(Layout.TITLE.X, Layout.TITLE.Y),
				Size = UDim2.fromOffset(Layout.TITLE_SIZE.X, Layout.TITLE_SIZE.Y),
				TextScaled = true,
				Text = function()
					local current = quest()
					return if current then current.Title else ""
				end,
				create("UITextSizeConstraint")({ MaxTextSize = Layout.TITLE_SIZE.Y }),
			}),
			bar,
			plaque,
			-- The band says where the reward waits; the light crosses it now and then while the card is up.
			create("Frame")({
				Name = "BandLight",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, Layout.BAND),
				BackgroundTransparency = 1,
				ClipsDescendants = true,
				ZIndex = 5,
				Components.Sheen(call, 5, Layout.SIZE.X / Layout.BAND),
			}),
			Components.Tracked("CLAIM IN LOBBY", Layout.BAND_TEXT, 1, Font.Display, {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, Layout.BAND_PAD, 1, -Layout.BAND / 2),
				ZIndex = 4,
			}),
			reward,
		}),
		-- One ring off the card as COMPLETE lands.
		create("Frame")({
			Name = "Ring",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = function()
				local reach = 2 * math.round(Timing.RING_REACH * Motion.Decelerate(struck()))
				return UDim2.new(1, reach, 1, reach)
			end,
			BackgroundTransparency = 1,
			Visible = function()
				local t = struck()
				return t > 0 and t < 1
			end,
			ZIndex = 8,
			create("UICorner")({ CornerRadius = UDim.new(0, 5) }),
			create("UIStroke")({
				Color = Palette.White,
				Thickness = 3,
				Transparency = function()
					return 0.15 + 0.85 * struck()
				end,
			}),
		}),
	})
end

return QuestToast
