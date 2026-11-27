--!nonstrict
-- A party's invite, as the player it was sent to sees it, on the right of the lobby over whatever is up: a pink card
-- under PARTY INVITE, the inviter's head and name, the party's map, difficulty and room, the time left draining under
-- them, and DECLINE | JOIN. It slides in from the right edge with one flash and one ring, its pieces dealt onto it, and
-- calls in light on JOIN while it waits. JOIN sends it off with a flash, swelling as it fades (the server then puts the
-- player on the pad); DECLINE and running out slide it back out. Nothing is decided here: JOIN asks the server.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local MapsCore = require(ReplicatedStorage.GlobalShared.Core.MapsCore)
local PadsCore = require(ReplicatedStorage.Shared.Core.PadsCore)
local Parts = require(script.Parent.Parts)
local Types = require(script.Parent.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
local Label = Parts.Label

-- Px at 1080: the card from the screen's top left, the rest from the card's.
local Layout = table.freeze({
	CARD = Vector2.new(1440, 400),
	SIZE = Vector2.new(440, 252),
	-- PARTY INVITE, his flat tag over the top edge.
	TAG = Vector2.new(20, -15),
	TAG_HEIGHT = 30,
	TAG_TEXT = 17,
	TAG_PAD = 12,
	HEAD = Vector2.new(22, 32),
	HEAD_SIZE = 92,
	NAME = Vector2.new(132, 36),
	NAME_TEXT = 30,
	SAYS = Vector2.new(132, 72),
	SAYS_TEXT = 15,
	CHIPS = Vector2.new(132, 96),
	CHIP_HEIGHT = 28,
	CHIP_TEXT = 14,
	CHIP_PAD = 10,
	CHIP_GAP = 8,
	BAR = Vector2.new(22, 146),
	BAR_SIZE = Vector2.new(396, 6),
	-- DECLINE | JOIN: 20 apart, past the bracket check's 18.5 for a 228 px Operate slab beside a 150 px one.
	DECLINE = Vector2.new(22, 172),
	DECLINE_SIZE = Vector2.new(150, 58),
	JOIN = Vector2.new(192, 172),
	JOIN_SIZE = Vector2.new(226, 58),
	BUTTON_TEXT = 24,
	ARROW = 20,
	-- Room round the card inside the group that fades it, for its glow, brackets and ring.
	MARGIN = 70,
})

local Gesture = table.freeze({
	-- In: from TRAVEL px out to the right, decelerating, then one flash and one ring as it lands; the head, the words
	-- and the chips dealt onto it, the buttons growing from FROM.
	IN = 0.42,
	TRAVEL = 140,
	LAND = 0.3,
	-- A flash over the whole face is squared and short (UI.md, "PLAY in his MENU's place"): longer, the card reads pale.
	FLASH = 0.2,
	FLASH_PEAK = 0.6,
	RING = 0.5,
	RING_GROW = 34,
	HEAD_DELAY = 0.12,
	WORDS_DELAY = 0.18,
	CHIPS_DELAY = 0.24,
	CHIPS_STAGGER = 0.05,
	BUTTONS_DELAY = 0.3,
	DEAL = 0.32,
	FROM = 0.6,
	SLIDE = 18,
	-- Out: JOIN swells it as it fades; DECLINE and running out slide it back to the right.
	JOINED = 0.3,
	JOINED_SWELL = 0.08,
	OUT = 0.24,
	-- The last seconds warm the bar to pink.
	HURRY_SECONDS = 5,
	CALL = 0.7,
})

local Invitation = {}

-- How far in it is (0 to 1), how far right of its place it stands, and how much it has swelled leaving by JOIN.
local function motionOf(state: Types.TLobbyState): (() -> number, () -> number, () -> number, () -> number)
	local elapsed = derive(function(): number
		return state.Now() - state.InvitationAt()
	end)
	local left = derive(function(): number
		return state.Now() - state.InvitationGoneAt()
	end)
	local isJoined = derive(function(): boolean
		return state.InvitationAnswer() == "Join"
	end)
	local isUp = derive(function(): boolean
		return state.InvitationGoneAt() < state.InvitationAt()
	end)
	local shown = derive(function(): number
		if isUp() then return Motion.Out(Progress(elapsed(), 0, Gesture.IN)) end
		return 1 - Progress(left(), 0, if isJoined() then Gesture.JOINED else Gesture.OUT)
	end)
	local away = derive(function(): number
		if isUp() then return 1 - Motion.Decelerate(Progress(elapsed(), 0, Gesture.IN)) end
		if isJoined() then return 0 end
		return Motion.Accelerate(Progress(left(), 0, Gesture.OUT))
	end)
	local swell = derive(function(): number
		if isUp() or not isJoined() then return 0 end
		return Gesture.JOINED_SWELL * Motion.Decelerate(Progress(left(), 0, Gesture.JOINED))
	end)

	return shown, away, swell, elapsed
end

-- How far a piece has come onto the card, 0 to 1, `delay` after it started sliding in.
local function dealtOf(elapsed: () -> number, delay: number): () -> number
	return derive(function(): number
		return Motion.Decelerate(Progress(elapsed(), delay, Gesture.DEAL))
	end)
end

-- One fact about the party on his dark plaque, in `color`, sized by a hidden copy of its word as the party screen's
-- chips are.
local function chip(state: Types.TLobbyState, order: number, color: any, text: () -> string, dealt: () -> number): Frame
	local width = vide.source(0)
	return create("Frame")({
		Name = `Chip{order}`,
		LayoutOrder = order,
		Size = function()
			return UDim2.fromOffset(width() + 2 * Layout.CHIP_PAD, Layout.CHIP_HEIGHT)
		end,
		BackgroundTransparency = 1,
		ZIndex = 5,
		Label({
			Name = "Measure",
			Size = UDim2.fromOffset(300, Layout.CHIP_TEXT),
			TextSize = Layout.CHIP_TEXT,
			TextTransparency = 1,
			Text = text,
			-- TextBounds is in screen px, under the root's UIScale; the width is in design px.
			vide.changed("TextBounds", function(bounds: Vector2)
				width(math.ceil(bounds.X / math.max(vide.untrack(state.PageScale), 0.01)))
			end),
		}),
		Parts.Plaque({
			Name = "Plaque",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 5,
			create("UIScale")({
				Scale = function()
					return Gesture.FROM + (1 - Gesture.FROM) * dealt()
				end,
			}),
			Label({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextSize = Layout.CHIP_TEXT,
				TextColor3 = color,
				ZIndex = 7,
				Text = text,
				create("UIPadding")({ PaddingTop = UDim.new(0, 2) }),
			}),
		}),
	})
end

-- A button on the card: a slab of `kind` with its word, growing in on its turn.
local function button(
	spec: {
		Name: string,
		Kind: string,
		Word: string,
		At: Vector2,
		Size: Vector2,
		Arrow: boolean,
		Sheen: (() -> number)?,
		OnPress: () -> (),
	},
	dealt: () -> number,
	isLive: () -> boolean
): TextButton
	local hand = Hand.React("Operate")
	local center = spec.At + spec.Size / 2

	return Components.Button({
		Name = spec.Name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center.X, center.Y),
		Size = UDim2.fromOffset(spec.Size.X, spec.Size.Y),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Interactable = isLive,
		Activated = function()
			hand.Commit()
			spec.OnPress()
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return (Gesture.FROM + (1 - Gesture.FROM) * dealt()) * hand.Scale()
			end,
		}),
		Components.Slab({
			Kind = spec.Kind,
			Marks = true,
			Brackets = hand.Rise,
			GlowTransparency = function()
				return 0.6 - 0.3 * hand.Light()
			end,
		}, {
			Name = "Slab",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 5,
			Hand.WashLayer(hand, 3, 3),
			Components.Sheen(
				if spec.Sheen then Hand.Sheen(hand, spec.Sheen) else hand.Glint,
				3,
				spec.Size.X / spec.Size.Y
			),
			create("Frame")({
				Name = "Word",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Layout.BUTTON_TEXT),
				BackgroundTransparency = 1,
				ZIndex = 6,
				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 10),
				}),
				Components.Tracked(spec.Word, Layout.BUTTON_TEXT, 2, Font.Display, { LayoutOrder = 1, ZIndex = 6 }),
				-- The arrow leans on toward the party under the hand.
				if spec.Arrow
					then create("Frame")({
						LayoutOrder = 2,
						Size = UDim2.fromOffset(Layout.ARROW + 6, Layout.ARROW),
						BackgroundTransparency = 1,
						Components.Picture(EIcons.Arrow, {
							AnchorPoint = Vector2.new(0, 0.5),
							Position = function()
								return UDim2.new(0, math.round(5 * hand.Rise()), 0.5, 0)
							end,
							Size = Components.PictureBox(Layout.ARROW),
							ZIndex = 6,
						}),
					})
					else nil,
			}),
		}),
	}) :: TextButton
end

function Invitation.Build(state: Types.TLobbyState, actions: Types.TLobbyActions): ScreenGui
	local shown, away, swell, elapsed = motionOf(state)
	local isUp = derive(function(): boolean
		return state.InvitationGoneAt() < state.InvitationAt()
	end)
	local isDrawn = derive(function(): boolean
		return state.Invitation() ~= nil and shown() > 0
	end)
	local pad = function(): Types.TPadView?
		local current = state.Invitation()
		return if current then state.Pads[current.Pad] else nil
	end
	local map = derive(function(): MapsCore.TMap
		local current = pad()
		return (if current then MapsCore.LIST[current.Map()] else nil) or MapsCore.LIST[1]
	end)
	local difficulty = derive(function(): string
		local current = pad()
		return (if current then MapsCore.DIFFICULTIES[current.Difficulty()] else nil) or MapsCore.DIFFICULTIES[1]
	end)
	local seconds = derive(function(): number
		return state.InvitationSeconds()
	end)
	local share = Hand.Spring(function(): number
		return math.clamp(seconds() / PadsCore.INVITE_SECONDS, 0, 1)
	end, Parts.Timing.BAR_PERIOD)
	local barColor = derive(function(): Color3
		local left = seconds()
		if left > Gesture.HURRY_SECONDS then return Palette.Gold end
		return Palette.Pink:Lerp(Palette.Gold, math.max(left, 0) / Gesture.HURRY_SECONDS)
	end)
	-- 1 (no flash) until it lands: Progress reads 0 before its start, which would flash the whole slide in.
	local landed = derive(function(): number
		local t = elapsed()
		return if t < Gesture.LAND then 1 else Progress(t, Gesture.LAND, Gesture.FLASH)
	end)
	local ringed = derive(function(): number
		return Progress(elapsed(), Gesture.LAND, Gesture.RING)
	end)
	local joinFlash = derive(function(): number
		if state.InvitationAnswer() ~= "Join" then return 1 end
		return Progress(state.Now(), state.InvitationGoneAt(), Gesture.FLASH)
	end)
	local call = Parts.Since(state, state.InvitationCallAt, Gesture.CALL)
	local size = Layout.SIZE
	local margin = Layout.MARGIN
	local tagWidth = vide.source(0)
	local headDealt = dealtOf(elapsed, Gesture.HEAD_DELAY)
	local wordsDealt = dealtOf(elapsed, Gesture.WORDS_DELAY)

	local cardFrame = Components.Card({
		Accent = Palette.Pink,
		Tint = 0.3,
		Marks = true,
		Brackets = true,
		GlowTransparency = function()
			return 0.65 - 0.25 * Motion.Bump(call())
		end,
	}, {
		Name = "Card",
		Position = UDim2.fromOffset(margin, margin),
		Size = UDim2.fromOffset(size.X, size.Y),
		ZIndex = 3,
		-- PARTY INVITE: his flat tag in the accent, over the top edge.
		create("Frame")({
			Name = "Tag",
			Position = UDim2.fromOffset(Layout.TAG.X, Layout.TAG.Y),
			Size = function()
				return UDim2.fromOffset(tagWidth() + 2 * Layout.TAG_PAD, Layout.TAG_HEIGHT)
			end,
			BackgroundColor3 = Palette.Pink,
			BorderSizePixel = 0,
			ZIndex = 6,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			create("UIScale")({ Scale = headDealt }),
			Label({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, 1),
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Layout.TAG_TEXT),
				TextSize = Layout.TAG_TEXT,
				TextYAlignment = Enum.TextYAlignment.Center,
				ZIndex = 7,
				Text = "PARTY INVITE",
				-- TextBounds is in screen px, under the root's UIScale; the width is in design px.
				vide.changed("TextBounds", function(bounds: Vector2)
					tagWidth(math.ceil(bounds.X / math.max(vide.untrack(state.PageScale), 0.01)))
				end),
			}),
		}),
		create("Frame")({
			Name = "Head",
			Position = UDim2.fromOffset(Layout.HEAD.X, Layout.HEAD.Y),
			Size = UDim2.fromOffset(Layout.HEAD_SIZE, Layout.HEAD_SIZE),
			BackgroundColor3 = Parts.PLAQUE_FACE,
			BorderSizePixel = 0,
			ZIndex = 5,
			create("UIScale")({
				Scale = function()
					return Gesture.FROM + (1 - Gesture.FROM) * headDealt()
				end,
			}),
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			create("UIStroke")({
				Color = Palette.Pink,
				Thickness = 1.5,
				Transparency = 0.3,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
			create("ImageLabel")({
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 6,
				Image = function()
					local current = state.Invitation()
					local id = if current then current.UserId else 0
					return `rbxthumb://type=AvatarHeadShot&id={id}&w=150&h=150`
				end,
			}),
		}),
		create("Frame")({
			Name = "Words",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 5,
			Position = function()
				return UDim2.fromOffset(math.round(Gesture.SLIDE * (1 - wordsDealt())), 0)
			end,
			Label({
				Name = "Name",
				Position = UDim2.fromOffset(Layout.NAME.X, Layout.NAME.Y),
				Size = UDim2.fromOffset(size.X - Layout.NAME.X - 22, Layout.NAME_TEXT),
				TextSize = Layout.NAME_TEXT,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 6,
				Text = function()
					local current = state.Invitation()
					return if current then current.DisplayName else ""
				end,
			}),
			Label({
				Name = "Says",
				Position = UDim2.fromOffset(Layout.SAYS.X, Layout.SAYS.Y),
				Size = UDim2.fromOffset(size.X - Layout.SAYS.X - 22, Layout.SAYS_TEXT),
				FontFace = Font.DisplayBold,
				TextSize = Layout.SAYS_TEXT,
				TextColor3 = Palette.Lavender,
				ZIndex = 6,
				Text = "invited you to their party",
			}),
		}),
		create("Frame")({
			Name = "Chips",
			Position = UDim2.fromOffset(Layout.CHIPS.X, Layout.CHIPS.Y),
			Size = UDim2.fromOffset(size.X - Layout.CHIPS.X - 22, Layout.CHIP_HEIGHT),
			BackgroundTransparency = 1,
			ZIndex = 5,
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, Layout.CHIP_GAP),
			}),
			chip(state, 1, function()
				return Parts.AccentOf(map())
			end, function()
				return string.upper(map().DisplayName)
			end, dealtOf(elapsed, Gesture.CHIPS_DELAY)),
			chip(state, 2, function()
				return Parts.DIFFICULTY_COLORS[difficulty()] or Palette.Green
			end, function()
				return string.upper(difficulty())
			end, dealtOf(elapsed, Gesture.CHIPS_DELAY + Gesture.CHIPS_STAGGER)),
			chip(state, 3, Palette.White, function()
				local current = pad()
				if not current then return "" end
				return `{current.Count()}/{current.MaxPlayers()}`
			end, dealtOf(elapsed, Gesture.CHIPS_DELAY + 2 * Gesture.CHIPS_STAGGER)),
		}),
		Parts.CountdownBar(share, Layout.BAR_SIZE, barColor, {
			Position = UDim2.fromOffset(Layout.BAR.X, Layout.BAR.Y),
			ZIndex = 5,
		}),
		button({
			Name = "Decline",
			Kind = "Red",
			Word = "DECLINE",
			At = Layout.DECLINE,
			Size = Layout.DECLINE_SIZE,
			Arrow = false,
			OnPress = function()
				actions.AnswerInvitation(false)
			end,
		}, dealtOf(elapsed, Gesture.BUTTONS_DELAY), isUp),
		button({
			Name = "Join",
			Kind = "Go",
			Word = "JOIN",
			At = Layout.JOIN,
			Size = Layout.JOIN_SIZE,
			Arrow = true,
			Sheen = function()
				local t = call()
				return if t > 0 and t < 1 then t else 1
			end,
			OnPress = function()
				actions.AnswerInvitation(true)
			end,
		}, dealtOf(elapsed, Gesture.BUTTONS_DELAY + Gesture.CHIPS_STAGGER), isUp),
		-- Landing, and JOIN going through: one white flash over the whole card.
		create("Frame")({
			Name = "Flash",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Palette.White,
			BorderSizePixel = 0,
			Visible = function()
				return landed() < 1 or joinFlash() < 1
			end,
			BackgroundTransparency = function()
				local t = math.min(landed(), joinFlash())
				return 1 - Gesture.FLASH_PEAK * (1 - t) * (1 - t)
			end,
			ZIndex = 9,
			create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
		}),
	})

	-- One ring as it lands, growing off the card by pixels at one weight.
	local ring = create("Frame")({
		Name = "Ring",
		Position = function()
			local grow = math.round(Gesture.RING_GROW * Motion.Decelerate(ringed()))
			return UDim2.fromOffset(margin - grow, margin - grow)
		end,
		Size = function()
			local grow = math.round(Gesture.RING_GROW * Motion.Decelerate(ringed()))
			return UDim2.fromOffset(size.X + 2 * grow, size.Y + 2 * grow)
		end,
		BackgroundTransparency = 1,
		Visible = function()
			return ringed() > 0 and ringed() < 1
		end,
		ZIndex = 2,
		create("UICorner")({ CornerRadius = UDim.new(0, 6) }),
		create("UIStroke")({ Color = Palette.Pink, Thickness = 2, Transparency = ringed }),
	})

	return create("ScreenGui")({
		Name = "Invitation",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		-- Over every lobby screen (5) and its dim, beside the Gems counter (7): it is the one thing that cannot wait.
		DisplayOrder = 8,
		Enabled = isDrawn,
		create("Frame")({
			Name = "Root",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(1920, 1080),
			BackgroundTransparency = 1,
			create("UIScale")({ Scale = state.PageScale }),
			create("Frame")({
				Name = "Holder",
				Position = function()
					return UDim2.fromOffset(
						Layout.CARD.X - margin + math.round(Gesture.TRAVEL * away()),
						Layout.CARD.Y - margin
					)
				end,
				Size = UDim2.fromOffset(size.X + 2 * margin, size.Y + 2 * margin),
				BackgroundTransparency = 1,
				Interactable = isUp,
				create("UIScale")({
					Scale = function()
						return 1 + swell()
					end,
				}),
				Components.FadeGroup("Content", shown, { Size = UDim2.fromScale(1, 1) }, {
					cardFrame,
					ring,
				}),
			}),
		}),
	})
end

-- Seconds every gesture of its arrival takes, and its leaving: the controller keeps the clock ticking this long.
Invitation.ARRIVE_SECONDS = Gesture.BUTTONS_DELAY + Gesture.DEAL + 0.4
Invitation.LEAVE_SECONDS = math.max(Gesture.OUT, Gesture.JOINED, Gesture.FLASH)
Invitation.CALL_SECONDS = Gesture.CALL

return Invitation
