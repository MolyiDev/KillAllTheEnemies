--!nonstrict
-- The surprise gift's toast on the right of the lobby, a sibling of a party's invite card: a green card under
-- SURPRISE GIFT, the friend's head and name, INVITE and what their first join pays, and an X on its corner. It slides in
-- from the right edge with one flash and one ring, its pieces dealt onto it, the Gems stamping down last; while it waits
-- the light crosses INVITE and its time drains along its bottom. INVITE lifts it away with a flash, swelling as it
-- fades; the X, its time running out and standing aside slide it back out. Nothing is decided here: the controller
-- sends the invite.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
-- The party invite card's bar track.
local BAR_TRACK = Color3.fromRGB(58, 50, 86)

-- Px at 1080: the card from the screen's top left, the rest from the card's. Its size and place are the reference's
-- prompt measured on a 1080 screenshot (392 x 97, its right edge 38 px in, its top just under the middle).
local Layout = table.freeze({
	CARD = Vector2.new(1490, 530),
	SIZE = Vector2.new(392, 100),
	-- SURPRISE GIFT, his flat tag over the top edge.
	TAG = Vector2.new(12, -12),
	TAG_HEIGHT = 24,
	TAG_TEXT = 14,
	TAG_PAD = 10,
	HEAD = Vector2.new(14, 14),
	HEAD_SIZE = 72,
	-- The gift's own picture stands in for a head when no friend is named. A friend online now wears a green dot on the
	-- head's bottom right corner, as the reference's does.
	GIFT_PICTURE = 64,
	ONLINE = 14,
	-- "Invite @name to play!", shrinking to fit before the X.
	LINE = Vector2.new(98, 16),
	LINE_TEXT = 17,
	LINE_MIN_TEXT = 11,
	INVITE = Vector2.new(98, 48),
	INVITE_SIZE = Vector2.new(116, 36),
	BUTTON_TEXT = 17,
	ARROW = 14,
	-- What it pays, after INVITE (19 px clear of its brackets under the hand): the gem's middle and longest side, then
	-- the count.
	GEM = Vector2.new(248, 66),
	GEM_SIZE = 30,
	COUNT = Vector2.new(268, 66),
	COUNT_TEXT = 24,
	-- Its time, draining along the bottom under INVITE: clear of INVITE's brackets open under the hand (84 + 4 + 2 = 90).
	BAR = Vector2.new(14, 93),
	BAR_SIZE = Vector2.new(364, 3),
	-- The X inside the card's top right corner, the squad screen's at the toast's size: each bar's length and weight.
	CLOSE = Vector2.new(368, 24),
	CLOSE_SIZE = 28,
	CLOSE_BAR = Vector2.new(11, 2),
	-- Room round the card inside the group that fades it, for its glow, brackets and ring.
	MARGIN = 60,
})

local Gesture = table.freeze({
	-- In: from TRAVEL px out to the right, decelerating, then one flash and one ring as it lands; the head, the words
	-- and INVITE dealt onto it growing from FROM; the Gems last: the gem grows in from nothing and the count stamps down
	-- from STAMP_FROM, both punched as it lands.
	IN = 0.42,
	TRAVEL = 140,
	LAND = 0.3,
	FLASH = 0.2,
	FLASH_PEAK = 0.6,
	RING = 0.5,
	RING_GROW = 26,
	HEAD_DELAY = 0.12,
	WORDS_DELAY = 0.18,
	INVITE_DELAY = 0.28,
	GEMS_DELAY = 0.42,
	DEAL = 0.32,
	FROM = 0.6,
	SLIDE = 18,
	STAMP = 0.14,
	STAMP_FROM = 1.7,
	-- The count is all in this share of the way through its stamp; the gem punches PUNCH as it lands, the count less.
	STAMP_FADE = 0.4,
	PUNCH = 0.18,
	COUNT_PUNCH = 0.09,
	PUNCH_SECONDS = 0.3,
	-- The count lands gold and cools to white.
	STAMP_GLOW = 0.45,
	-- Out: INVITE swells it as it fades; the X and standing aside slide it back to the right.
	INVITED = 0.3,
	INVITED_SWELL = 0.08,
	OUT = 0.24,
	CALL = 0.7,
	-- It is up this long, then goes by itself: an offer that is not always there is one to take while it is. Its bar
	-- warms from gold to pink over the last HURRY seconds.
	LAPSE = 8,
	HURRY = 3,
})

local Toast = {}

-- Every gesture of its arrival is over by then, and its leaving; a call's light crosses in CALL_SECONDS.
Toast.ARRIVE_SECONDS = Gesture.GEMS_DELAY + Gesture.STAMP + Gesture.PUNCH_SECONDS + 0.2
Toast.LEAVE_SECONDS = math.max(Gesture.OUT, Gesture.INVITED, Gesture.FLASH)
Toast.CALL_SECONDS = Gesture.CALL
-- The Gems' count lands this long after it starts coming in: the controller sounds the stamp then.
Toast.STAMP_SECONDS = Gesture.GEMS_DELAY + Gesture.STAMP
Toast.LAPSE_SECONDS = Gesture.LAPSE

local function label(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		ZIndex = 4,
		props,
	})
end

-- His dark key badge: an ink face in a thin edge of `edge`.
local function plaque(edge: Color3, props: { [any]: any }): Frame
	return create("Frame")({
		BackgroundColor3 = edge,
		BorderSizePixel = 0,
		create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
		create("Frame")({
			Name = "Face",
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			BackgroundColor3 = Palette.Ink,
			BorderSizePixel = 0,
			ZIndex = props.ZIndex,
			create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
		}),
		props,
	})
end

-- How far it is in (0 to 1), how far right of its place it stands, how much it has swelled leaving by INVITE, and the
-- seconds since it came in.
local function motionOf(state: Types.TToastState): (() -> number, () -> number, () -> number, () -> number)
	local elapsed = derive(function(): number
		return state.Now() - state.ShownAt()
	end)
	local left = derive(function(): number
		return state.Now() - state.GoneAt()
	end)
	local isInvited = derive(function(): boolean
		return state.Answer() == "Invite"
	end)
	local isUp = derive(function(): boolean
		return state.GoneAt() < state.ShownAt()
	end)
	local shown = derive(function(): number
		if isUp() then return Motion.Out(Progress(elapsed(), 0, Gesture.IN)) end
		return 1 - Progress(left(), 0, if isInvited() then Gesture.INVITED else Gesture.OUT)
	end)
	local away = derive(function(): number
		if isUp() then return 1 - Motion.Decelerate(Progress(elapsed(), 0, Gesture.IN)) end
		if isInvited() then return 0 end
		return Motion.Accelerate(Progress(left(), 0, Gesture.OUT))
	end)
	local swell = derive(function(): number
		if isUp() or not isInvited() then return 0 end
		return Gesture.INVITED_SWELL * Motion.Decelerate(Progress(left(), 0, Gesture.INVITED))
	end)

	return shown, away, swell, elapsed
end

-- How far a piece has come onto the card, 0 to 1, `delay` after it started sliding in.
local function dealtOf(elapsed: () -> number, delay: number): () -> number
	return derive(function(): number
		return Motion.Decelerate(Progress(elapsed(), delay, Gesture.DEAL))
	end)
end

-- INVITE: the green slab with its arrow leaning on under the hand, the light crossing it on each call.
local function inviteButton(state: Types.TToastState, actions: Types.TToastActions, elapsed, isUp): TextButton
	local hand = Hand.React("Operate")
	local size = Layout.INVITE_SIZE
	local center = Layout.INVITE + size / 2
	local dealt = dealtOf(elapsed, Gesture.INVITE_DELAY)
	local call = derive(function(): number
		local t = Progress(state.Now(), state.CallAt(), Gesture.CALL)
		return if t > 0 and t < 1 then t else 1
	end)

	return Components.Button({
		Name = "Invite",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center.X, center.Y),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Interactable = isUp,
		Activated = function()
			hand.Commit()
			actions.Invite()
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return (Gesture.FROM + (1 - Gesture.FROM) * dealt()) * hand.Scale()
			end,
		}),
		Components.Slab({
			Kind = "Go",
			Marks = true,
			Brackets = hand.Rise,
			GlowTransparency = function()
				return 0.6 - 0.3 * math.max(hand.Light(), Motion.Bump(call()))
			end,
		}, {
			Name = "Slab",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 5,
			Hand.WashLayer(hand, 3, 3),
			Components.Sheen(Hand.Sheen(hand, call), 3, size.X / size.Y),
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
					Padding = UDim.new(0, 8),
				}),
				Components.Tracked("INVITE", Layout.BUTTON_TEXT, 2, Font.Display, { LayoutOrder = 1, ZIndex = 6 }),
				create("Frame")({
					LayoutOrder = 2,
					Size = UDim2.fromOffset(Layout.ARROW + 5, Layout.ARROW),
					BackgroundTransparency = 1,
					Components.Picture(EIcons.Arrow, {
						AnchorPoint = Vector2.new(0, 0.5),
						Position = function()
							return UDim2.new(0, math.round(5 * hand.Rise()), 0.5, 0)
						end,
						Size = Components.PictureBox(Layout.ARROW),
						ZIndex = 6,
					}),
				}),
			}),
		}),
	}) :: TextButton
end

-- Its time left, draining along the bottom: the party invite card's bar, gold warming to pink at the end.
local function timeBar(elapsed: () -> number): Frame
	local size = Layout.BAR_SIZE
	local left = derive(function(): number
		return math.clamp(1 - elapsed() / Gesture.LAPSE, 0, 1)
	end)

	return create("Frame")({
		Name = "Track",
		Position = UDim2.fromOffset(Layout.BAR.X, Layout.BAR.Y),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = BAR_TRACK,
		BorderSizePixel = 0,
		ZIndex = 4,
		create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
		create("Frame")({
			Name = "Fill",
			Size = function()
				return UDim2.fromOffset(math.round(size.X * left()), size.Y)
			end,
			BackgroundColor3 = function()
				local hurry = Gesture.HURRY / Gesture.LAPSE
				return Palette.Pink:Lerp(Palette.Gold, math.min(left() / hurry, 1))
			end,
			BorderSizePixel = 0,
			ZIndex = 5,
			create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
		}),
	})
end

-- The X inside the card's top right corner, as the squad screen's: his pink slab with a thin white X that turns a
-- quarter under the hand, the slab growing a little and dipping on a press.
local function closeButton(actions: Types.TToastActions, elapsed, isUp): TextButton
	local hand = Hand.React("Operate")
	local dealt = dealtOf(elapsed, Gesture.INVITE_DELAY)
	local size = Layout.CLOSE_SIZE

	local function bar(rotation: number): Frame
		return create("Frame")({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(Layout.CLOSE_BAR.X, Layout.CLOSE_BAR.Y),
			Rotation = function()
				return rotation + 90 * hand.Rise()
			end,
			BackgroundColor3 = Palette.White,
			BorderSizePixel = 0,
			ZIndex = 11,
		})
	end

	return Components.Button({
		Name = "Close",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(Layout.CLOSE.X, Layout.CLOSE.Y),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		ZIndex = 10,
		Interactable = isUp,
		Activated = function()
			hand.Commit()
			actions.Close()
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return math.max(dealt() * hand.Scale(), 0.01)
			end,
		}),
		Components.Slab({
			Kind = "Pink",
			GlowTransparency = function()
				return 0.6 - 0.2 * hand.Light()
			end,
		}, {
			Name = "Face",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 10,
			bar(45),
			bar(-45),
		}),
	}) :: TextButton
end

function Toast.Build(state: Types.TToastState, actions: Types.TToastActions): ScreenGui
	local shown, away, swell, elapsed = motionOf(state)
	local isUp = derive(function(): boolean
		return state.GoneAt() < state.ShownAt()
	end)
	-- 1 (no flash) until it lands: Progress reads 0 before its start, which would flash the whole slide in.
	local landed = derive(function(): number
		local t = elapsed()
		return if t < Gesture.LAND then 1 else Progress(t, Gesture.LAND, Gesture.FLASH)
	end)
	local ringed = derive(function(): number
		return Progress(elapsed(), Gesture.LAND, Gesture.RING)
	end)
	local invitedFlash = derive(function(): number
		if state.Answer() ~= "Invite" then return 1 end
		return Progress(state.Now(), state.GoneAt(), Gesture.FLASH)
	end)
	local call = derive(function(): number
		return Progress(state.Now(), state.CallAt(), Gesture.CALL)
	end)
	-- The Gems' stamp: -1 before it starts, then 0 to 1 as it comes down; the punch as it lands.
	local stamp = derive(function(): number
		local t = elapsed()
		if t < Gesture.GEMS_DELAY then return -1 end
		return Progress(t, Gesture.GEMS_DELAY, Gesture.STAMP)
	end)
	local punch = derive(function(): number
		return Motion.Bump((elapsed() - Gesture.GEMS_DELAY - Gesture.STAMP) / Gesture.PUNCH_SECONDS)
	end)
	local stampGlow = derive(function(): number
		return Progress(elapsed(), Gesture.GEMS_DELAY + Gesture.STAMP, Gesture.STAMP_GLOW)
	end)
	local friend = state.Friend
	local size = Layout.SIZE
	local margin = Layout.MARGIN
	local tagWidth = vide.source(0)
	local headDealt = dealtOf(elapsed, Gesture.HEAD_DELAY)
	local wordsDealt = dealtOf(elapsed, Gesture.WORDS_DELAY)

	local cardFrame = Components.Card({
		Accent = Palette.Green,
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
		-- SURPRISE GIFT: his flat tag in the accent, over the top edge, ink on the green.
		create("Frame")({
			Name = "Tag",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(Layout.TAG.X, Layout.TAG.Y + Layout.TAG_HEIGHT / 2),
			Size = function()
				return UDim2.fromOffset(tagWidth() + 2 * Layout.TAG_PAD, Layout.TAG_HEIGHT)
			end,
			BackgroundColor3 = Palette.Green,
			BorderSizePixel = 0,
			ZIndex = 6,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			create("UIScale")({ Scale = headDealt }),
			label({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, 1),
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Layout.TAG_TEXT),
				TextSize = Layout.TAG_TEXT,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextColor3 = Palette.Ink,
				ZIndex = 7,
				Text = "SURPRISE GIFT",
				-- TextBounds is in screen px, under the root's UIScale; the width is in design px.
				vide.changed("TextBounds", function(bounds: Vector2)
					tagWidth(math.ceil(bounds.X / math.max(vide.untrack(state.Scale), 0.01)))
				end),
			}),
		}),
		plaque(Palette.Green, {
			Name = "Head",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.HEAD.X + Layout.HEAD_SIZE / 2, Layout.HEAD.Y + Layout.HEAD_SIZE / 2),
			Size = UDim2.fromOffset(Layout.HEAD_SIZE, Layout.HEAD_SIZE),
			ZIndex = 5,
			create("UIScale")({
				Scale = function()
					return Gesture.FROM + (1 - Gesture.FROM) * headDealt()
				end,
			}),
			create("ImageLabel")({
				Name = "Headshot",
				Position = UDim2.fromOffset(2, 2),
				Size = UDim2.new(1, -4, 1, -4),
				BackgroundTransparency = 1,
				ZIndex = 6,
				Visible = function()
					return friend() ~= nil
				end,
				Image = function()
					local current = friend()
					local id = if current then current.UserId else 0
					return `rbxthumb://type=AvatarHeadShot&id={id}&w=150&h=150`
				end,
			}),
			Components.Picture(EIcons.InviteGift, {
				Name = "Gift",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = Components.PictureBox(Layout.GIFT_PICTURE),
				ZIndex = 6,
				Visible = function()
					return friend() == nil
				end,
			}),
			create("Frame")({
				Name = "Online",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(1, -Layout.ONLINE / 2, 1, -Layout.ONLINE / 2),
				Size = UDim2.fromOffset(Layout.ONLINE, Layout.ONLINE),
				BackgroundColor3 = Palette.Green,
				BorderSizePixel = 0,
				ZIndex = 7,
				Visible = function()
					local current = friend()
					return current ~= nil and current.IsOnline
				end,
				create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
				create("UIStroke")({ Color = Palette.Ink, Thickness = 2 }),
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
			label({
				Name = "Line",
				Position = UDim2.fromOffset(Layout.LINE.X, Layout.LINE.Y),
				Size = UDim2.fromOffset(Layout.CLOSE.X - Layout.CLOSE_SIZE / 2 - 8 - Layout.LINE.X, Layout.LINE_TEXT),
				TextScaled = true,
				ZIndex = 6,
				Text = function()
					local current = friend()
					return if current then `Invite @{current.Username} to play!` else "Invite a friend to play!"
				end,
				create("UITextSizeConstraint")({
					MaxTextSize = Layout.LINE_TEXT,
					MinTextSize = Layout.LINE_MIN_TEXT,
				}),
			}),
		}),
		inviteButton(state, actions, elapsed, isUp),
		timeBar(elapsed),
		-- What the friend's first join pays: the gem grows in from nothing, the count stamps down, both punched.
		Components.Picture(EIcons.Gem, {
			Name = "Gem",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.GEM.X, Layout.GEM.Y),
			Size = Components.PictureBox(Layout.GEM_SIZE),
			ZIndex = 6,
			create("UIScale")({
				Scale = function()
					local t = stamp()
					if t < 0 then return 0.01 end
					return math.max(Motion.Decelerate(t) + Gesture.PUNCH * punch(), 0.01)
				end,
			}),
		}),
		label({
			Name = "Count",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(Layout.COUNT.X, Layout.COUNT.Y),
			Size = UDim2.fromOffset(size.X - Layout.COUNT.X - 14, Layout.COUNT_TEXT),
			TextSize = Layout.COUNT_TEXT,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextScaled = true,
			ZIndex = 6,
			Text = function()
				return `+{Components.Commas(state.Gems())}`
			end,
			TextColor3 = function()
				return Palette.Gold:Lerp(Palette.White, stampGlow())
			end,
			TextTransparency = function()
				local t = stamp()
				return if t < 0 then 1 else 1 - math.min(t / Gesture.STAMP_FADE, 1)
			end,
			create("UITextSizeConstraint")({ MaxTextSize = Layout.COUNT_TEXT }),
			create("UIScale")({
				Scale = function()
					local t = stamp()
					if t < 0 then return Gesture.STAMP_FROM end
					return Gesture.STAMP_FROM - (Gesture.STAMP_FROM - 1) * t * t + Gesture.COUNT_PUNCH * punch()
				end,
			}),
		}),
		closeButton(actions, elapsed, isUp),
		-- Landing, and INVITE going through: one white flash over the whole card.
		create("Frame")({
			Name = "Flash",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Palette.White,
			BorderSizePixel = 0,
			Visible = function()
				return landed() < 1 or invitedFlash() < 1
			end,
			BackgroundTransparency = function()
				local t = math.min(landed(), invitedFlash())
				return 1 - Gesture.FLASH_PEAK * (1 - t) * (1 - t)
			end,
			ZIndex = 9,
			create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
		}),
	})

	-- One ring as it lands, growing off the card by pixels at one weight.
	local ring = create("Frame")({
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
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
		create("UIStroke")({ Color = Palette.Green, Thickness = 2, Transparency = ringed }),
	})

	return create("ScreenGui")({
		Name = "InviteGift",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		-- Over the lobby's HUD, under its screens (5): it stands aside while one is up.
		DisplayOrder = 4,
		Enabled = function()
			return shown() > 0
		end,
		create("Frame")({
			Name = "Root",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(1920, 1080),
			BackgroundTransparency = 1,
			create("UIScale")({ Scale = state.Scale }),
			create("Frame")({
				Name = "Holder",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = function()
					return UDim2.fromOffset(
						Layout.CARD.X + size.X / 2 + math.round(Gesture.TRAVEL * away()),
						Layout.CARD.Y + size.Y / 2
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

return Toast
