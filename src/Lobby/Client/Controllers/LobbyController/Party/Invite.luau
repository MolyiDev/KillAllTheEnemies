--!nonstrict
-- The invite list over the queue, opened by an open place's body on the pad (Ghosts) or an empty slot of the queue: the
-- party screen's panel and header (the add-friend glyph, INVITE PLAYERS, the party's count), and every other player in
-- this server as a card (their head, their names, what an invite to them stands at). A card is pressed to invite; it
-- flashes, throws one ring and stamps its new word as the server answers, and turns gold as they land on the pad. It
-- rises in as the party screen does and sinks away; the pad's EXIT, over its dim, and a click on the dim shut it.
-- Nothing is decided here: a press sends the invite, and the server answers what came of it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Scrollbar = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Scrollbar)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local PadsCore = require(ReplicatedStorage.Shared.Core.PadsCore)
local Parts = require(script.Parent.Parts)
local Types = require(script.Parent.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local source = vide.source
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
local Label = Parts.Label
local EInvite = PadsCore.EInvite

-- Px at 1080, from the panel's top left unless said otherwise.
local Layout = table.freeze({
	-- The panel, from the screen's top left: it ends by 940, clear of EXIT.
	PANEL = Vector2.new(470, 150),
	SIZE = Vector2.new(980, 700),
	-- The party screen's header: the glyph's middle and longer side, the title, the rule under it all.
	GLYPH = Vector2.new(48.5, 48),
	GLYPH_SIZE = 32,
	TITLE = Vector2.new(81, 26),
	TITLE_TEXT = 44,
	COUNT_RIGHT = 949,
	COUNT_Y = 48,
	COUNT_TEXT = 22,
	COUNT_GLYPH = 26,
	RULE = Vector2.new(31, 96),
	RULE_WIDTH = 918,
	SECTION = Vector2.new(31, 116),
	SECTION_TEXT = 16,
	-- The cards' window and the cards in it. The padding leaves a card's brackets their reach at the peak of a press
	-- (UI.md, "Brackets, picked and side by side": 12.5 down a 246 px Operate card), and so do the gaps (18.5).
	WINDOW = Vector2.new(15, 140),
	WINDOW_SIZE = Vector2.new(934, 542),
	WINDOW_PAD = 14,
	CARD = Vector2.new(210, 246),
	CARD_GAP = 22,
	COLUMNS = 4,
	SCROLLBAR_X = 965,
	-- Inside a card.
	HEAD = 120,
	HEAD_Y = 16,
	NAME_Y = 146,
	NAME_TEXT = 22,
	USER_Y = 172,
	USER_TEXT = 14,
	SLAB = Vector2.new(178, 38),
	SLAB_Y = 192,
	SLAB_TEXT = 18,
	SLAB_GLYPH = 20,
	-- Nobody else here: the friends picture, the words and the Roblox invite.
	EMPTY_Y = 330,
	EMPTY_GLYPH = 84,
	EMPTY_TEXT = 28,
	EMPTY_SUB = 17,
	FRIENDS = Vector2.new(300, 64),
	FRIENDS_TEXT = 24,
	-- Room round the panel inside the group that fades it, for the glow and the brackets.
	MARGIN = 120,
})

local Gesture = table.freeze({
	DIM = 0.3,
	-- The cards in view as it opens are dealt in one after another, growing from FROM.
	CARDS_DELAY = 0.1,
	CARDS_STAGGER = 0.035,
	DEALT_CARDS = 8,
	FROM = 0.6,
	-- A card whose state changes: one flash, one ring, a punch, its head hops (or shakes, turned down), its word
	-- stamps down from STAMP.
	FLASH = 0.2,
	FLASH_PEAK = 0.55,
	RING = 0.5,
	RING_GROW = 26,
	PUNCH = 0.06,
	PUNCH_PERIOD = 0.32,
	PUNCH_DAMPING = 0.45,
	HOP = 0.4,
	HOP_PX = 14,
	SHAKE = 0.4,
	SHAKE_PX = 8,
	STAMP = 1.35,
	STAMP_SECONDS = 0.22,
	-- The head grows a little with the card's rise.
	HEAD_RISE = 0.06,
})

-- What an invite to a player stands at, and how its card says it: the slab's kind, its word and glyph, the card's
-- accent, and whether it can be pressed.
type TLook = { Kind: string, Word: string, Glyph: string?, Accent: Color3, IsLive: boolean }
local LOOKS: { [string]: TLook } = table.freeze({
	Invite = { Kind = "Go", Word = "INVITE", Glyph = nil, Accent = Palette.Violet, IsLive = true },
	Sent = { Kind = "Steel", Word = "SENT", Glyph = EIcons.Check, Accent = Palette.Steel, IsLive = false },
	Joined = { Kind = "Gold", Word = "IN PARTY", Glyph = EIcons.Check, Accent = Palette.Gold, IsLive = false },
	Declined = { Kind = "Red", Word = "DECLINED", Glyph = nil, Accent = Color3.fromRGB(230, 60, 72), IsLive = false },
	InParty = { Kind = "Off", Word = "IN A PARTY", Glyph = nil, Accent = Parts.LOCKED, IsLive = false },
	Locked = { Kind = "Off", Word = "LOCKED", Glyph = EIcons.Lock, Accent = Parts.LOCKED, IsLive = false },
	Full = { Kind = "Off", Word = "PARTY FULL", Glyph = nil, Accent = Parts.LOCKED, IsLive = false },
	Away = { Kind = "Off", Word = "NOT READY", Glyph = nil, Accent = Parts.LOCKED, IsLive = false },
})
-- The server's answers (Lobby.InviteAnswered) by the look they show.
local ANSWERS = table.freeze({
	[EInvite.Sent] = "Sent",
	[EInvite.Joined] = "Joined",
	[EInvite.Declined] = "Declined",
	[EInvite.InParty] = "InParty",
	[EInvite.Locked] = "Locked",
	[EInvite.Full] = "Full",
	[EInvite.Away] = "Away",
})

local Invite = {}

-- What an invite to `player` stands at now: where they stand first (this party, another), then the party's room, then
-- what the server last answered.
local function statusOf(state: Types.TLobbyState, player: Types.TInvitePlayer): string
	local here = state.CurrentPad()
	local onPad = state.InviteOnPad()[player.UserId] or 0
	if onPad ~= 0 then return if onPad == here then "Joined" else "InParty" end
	local pad = state.Pads[here]
	if pad and pad.Count() >= pad.MaxPlayers() then return "Full" end
	-- JOINED shows as soon as the server says so, before the body is seen on the pad.
	local answer = state.InviteResults()[player.UserId]
	return if answer then ANSWERS[answer.Result] or "Invite" else "Invite"
end

-- How far in it is (0 to 1), how far under its place the panel is (it sinks as it leaves), and the seconds since it
-- opened or shut, held once every gesture is over.
local function motionOf(state: Types.TLobbyState): (() -> number, () -> number, () -> number)
	local timing = Parts.Timing
	local elapsed = derive(function(): number
		return math.min(state.Now() - state.InviteAt(), timing.SETTLED)
	end)
	local shown = derive(function(): number
		if state.IsInviteOpen() then return Motion.Out(Progress(elapsed(), 0, timing.FADE)) end
		return 1 - Progress(elapsed(), 0, timing.CLOSE)
	end)
	local drop = derive(function(): number
		if state.IsInviteOpen() then
			return timing.RISE * (1 - Motion.Decelerate(Progress(elapsed(), 0, timing.OPEN)))
		end
		return timing.SINK * Motion.Accelerate(Progress(elapsed(), 0, timing.CLOSE))
	end)

	return shown, drop, elapsed
end

-- The word on a card's slab and the glyph before it, stamped down as it changes.
local function slabWord(state: Types.TLobbyState, look: () -> TLook, changedAt: () -> number): Frame
	local stamped = Parts.Since(state, changedAt, Gesture.STAMP_SECONDS)
	local glyph = derive(function(): string?
		return look().Glyph
	end)

	return create("Frame")({
		Name = "Word",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, Layout.SLAB_TEXT),
		BackgroundTransparency = 1,
		ZIndex = 6,
		create("UIScale")({
			Scale = function()
				return Gesture.STAMP + (1 - Gesture.STAMP) * Motion.Decelerate(stamped())
			end,
		}),
		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),
		Components.Picture(function()
			return glyph() or EIcons.Check
		end, {
			LayoutOrder = 1,
			Size = Components.PictureBox(Layout.SLAB_GLYPH),
			Visible = function()
				return glyph() ~= nil
			end,
			ZIndex = 6,
		}),
		Label({
			LayoutOrder = 2,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, Layout.SLAB_TEXT),
			TextSize = Layout.SLAB_TEXT,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextColor3 = function()
				return if look().Kind == "Off" then Palette.Lavender else Palette.White
			end,
			ZIndex = 6,
			Text = function()
				return look().Word
			end,
		}),
	})
end

-- One player's card: their head, their display and user names, and the slab saying what an invite to them stands at.
-- Pressed while it says INVITE, it sends one.
local function card(
	state: Types.TLobbyState,
	actions: Types.TLobbyActions,
	player: Types.TInvitePlayer,
	order: number,
	elapsed: () -> number
): TextButton
	local status = derive(function(): string
		return statusOf(state, player)
	end)
	local look = derive(function(): TLook
		return LOOKS[status()]
	end)
	local isLive = derive(function(): boolean
		return look().IsLive
	end)
	local hand = Hand.React("Operate", isLive)
	local dealt = derive(function(): number
		if not state.IsInviteOpen() or order > Gesture.DEALT_CARDS then return 1 end
		local delay = Gesture.CARDS_DELAY + Gesture.CARDS_STAGGER * (order - 1)
		return Motion.Decelerate(Progress(elapsed(), delay, Parts.Timing.DEAL))
	end)

	local changedAt = source(-math.huge)
	local punch, strikePunch = Hand.Kick(Gesture.PUNCH_PERIOD, Gesture.PUNCH_DAMPING)
	Parts.OnChange(status, function()
		changedAt(os.clock())
		strikePunch(Gesture.PUNCH)
		actions.Stir(Gesture.RING + 0.1)
	end)
	local flashed = Parts.Since(state, changedAt, Gesture.FLASH)
	local ringed = Parts.Since(state, changedAt, Gesture.RING)
	local moved = Parts.Since(state, changedAt, math.max(Gesture.HOP, Gesture.SHAKE))
	-- Turned down, the head shakes; any other change, it hops.
	local headOffset = derive(function(): Vector2
		local t = moved()
		if status() == "Declined" then
			return Vector2.new(math.round(Gesture.SHAKE_PX * Motion.Shake(t, changedAt())), 0)
		end
		return Vector2.new(0, -math.round(Gesture.HOP_PX * Motion.Bump(t)))
	end)
	local accent = derive(function(): Color3
		return look().Accent
	end)
	local size = Layout.CARD

	return Components.Button({
		Name = player.Name,
		LayoutOrder = order,
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Activated = function()
			if not isLive() then return end
			hand.Commit()
			actions.InvitePlayer(player.UserId)
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return (Gesture.FROM + (1 - Gesture.FROM) * dealt()) * hand.Scale() * (1 + punch())
			end,
		}),
		Components.Card({
			Accent = accent,
			Tint = 0.35,
			Marks = true,
			Brackets = hand.Rise,
			GlowTransparency = function()
				return 0.75 - 0.3 * hand.Light()
			end,
		}, {
			Name = "Card",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
			Hand.WashLayer(hand, 4, 3),
			create("Frame")({
				Name = "Head",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = function()
					local offset = headOffset()
					return UDim2.fromOffset(size.X / 2 + offset.X, Layout.HEAD_Y + offset.Y)
				end,
				Size = UDim2.fromOffset(Layout.HEAD, Layout.HEAD),
				BackgroundColor3 = Parts.PLAQUE_FACE,
				BorderSizePixel = 0,
				ZIndex = 5,
				create("UIScale")({
					Scale = function()
						return 1 + Gesture.HEAD_RISE * hand.Rise()
					end,
				}),
				create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
				create("UIStroke")({
					Color = accent,
					Transparency = 0.35,
					Thickness = 1.5,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				}),
				create("ImageLabel")({
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Image = `rbxthumb://type=AvatarHeadShot&id={player.UserId}&w=150&h=150`,
					ZIndex = 6,
				}),
			}),
			Label({
				Name = "DisplayName",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromOffset(size.X / 2, Layout.NAME_Y),
				Size = UDim2.fromOffset(size.X - 24, Layout.NAME_TEXT),
				TextSize = Layout.NAME_TEXT,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 6,
				Text = player.DisplayName,
			}),
			Label({
				Name = "UserName",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromOffset(size.X / 2, Layout.USER_Y),
				Size = UDim2.fromOffset(size.X - 24, Layout.USER_TEXT),
				FontFace = Font.DisplayBold,
				TextSize = Layout.USER_TEXT,
				TextColor3 = Palette.Lavender,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 6,
				Text = `@{player.Name}`,
			}),
			Components.Slab({
				Kind = function()
					return look().Kind
				end,
				Marks = true,
			}, {
				Name = "State",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromOffset(size.X / 2, Layout.SLAB_Y),
				Size = UDim2.fromOffset(Layout.SLAB.X, Layout.SLAB.Y),
				ZIndex = 5,
				Components.Sheen(hand.Glint, 5, Layout.SLAB.X / Layout.SLAB.Y),
				slabWord(state, look, changedAt),
			}),
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				Visible = function()
					return flashed() < 1
				end,
				-- Squared and short: a longer flash reads as a pale, dead card.
				BackgroundTransparency = function()
					local t = flashed()
					return 1 - Gesture.FLASH_PEAK * (1 - t) * (1 - t)
				end,
				ZIndex = 8,
				create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
			}),
		}),
		-- One ring, growing off the card by pixels at one weight, in its new colour.
		create("Frame")({
			Name = "Ring",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = function()
				local grow = math.round(Gesture.RING_GROW * Motion.Decelerate(ringed()))
				return UDim2.new(1, 2 * grow, 1, 2 * grow)
			end,
			BackgroundTransparency = 1,
			Visible = function()
				return ringed() < 1
			end,
			ZIndex = 2,
			create("UICorner")({ CornerRadius = UDim.new(0, 6) }),
			create("UIStroke")({ Color = accent, Thickness = 2, Transparency = ringed }),
		}),
	}) :: TextButton
end

local function header(state: Types.TLobbyState): { Instance }
	local pad = function(): Types.TPadView?
		return state.Pads[state.CurrentPad()]
	end
	local count = derive(function(): string
		local current = pad()
		if not current then return "" end
		return `{current.Count()} / {current.MaxPlayers()}`
	end)
	local punch, strikePunch = Hand.Kick(0.3, 0.5)
	Parts.OnChange(count, function()
		strikePunch(0.22)
	end)

	return {
		Components.Picture(EIcons.AddFriend, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.GLYPH.X, Layout.GLYPH.Y),
			Size = Components.PictureBox(Layout.GLYPH_SIZE),
			ZIndex = 4,
		}),
		Label({
			Name = "Title",
			Position = UDim2.fromOffset(Layout.TITLE.X, Layout.TITLE.Y),
			Size = UDim2.fromOffset(600, Layout.TITLE_TEXT),
			TextSize = Layout.TITLE_TEXT,
			Text = "INVITE PLAYERS",
		}),
		-- The party's count, punched as it changes: what an invite is for.
		create("Frame")({
			Name = "Party",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromOffset(Layout.COUNT_RIGHT, Layout.COUNT_Y),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, Layout.COUNT_TEXT),
			BackgroundTransparency = 1,
			ZIndex = 4,
			create("UIScale")({
				Scale = function()
					return 1 + punch()
				end,
			}),
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 10),
			}),
			Components.Picture(EIcons.Friends, {
				LayoutOrder = 1,
				Size = Components.PictureBox(Layout.COUNT_GLYPH),
				ZIndex = 4,
			}),
			Label({
				LayoutOrder = 2,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Layout.COUNT_TEXT),
				FontFace = Font.DisplayBold,
				TextSize = Layout.COUNT_TEXT,
				TextColor3 = Palette.Lavender,
				Text = "PARTY",
			}),
			Label({
				LayoutOrder = 3,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Layout.COUNT_TEXT),
				TextSize = Layout.COUNT_TEXT,
				TextColor3 = Palette.Gold,
				Text = count,
			}),
		}),
		create("Frame")({
			Name = "Rule",
			Position = UDim2.fromOffset(Layout.RULE.X, Layout.RULE.Y),
			Size = function()
				return UDim2.fromOffset(Layout.RULE_WIDTH, math.max(1, 1 / state.PageScale()))
			end,
			BackgroundColor3 = Parts.RULE,
			BackgroundTransparency = Parts.RULE_TRANSPARENCY,
			BorderSizePixel = 0,
			ZIndex = 4,
		}),
		Label({
			Name = "Section",
			Position = UDim2.fromOffset(Layout.SECTION.X, Layout.SECTION.Y),
			Size = UDim2.fromOffset(600, Layout.SECTION_TEXT),
			FontFace = Font.DisplayBold,
			TextSize = Layout.SECTION_TEXT,
			TextColor3 = Palette.Lavender,
			Text = function()
				local players = #state.InvitePlayers()
				return if players > 0 then `IN THIS SERVER  ·  {players}` else "IN THIS SERVER"
			end,
		}),
	}
end

-- Nobody else in the server: the friends picture, the words, and Roblox's own invite to bring friends in.
local function empty(state: Types.TLobbyState, actions: Types.TLobbyActions): Frame
	local hand = Hand.React("Operate")
	local isEmpty = derive(function(): boolean
		return #state.InvitePlayers() == 0
	end)
	local friends = Layout.FRIENDS

	return create("Frame")({
		Name = "Empty",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = isEmpty,
		ZIndex = 4,
		Components.Picture(EIcons.Friends, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.SIZE.X / 2, Layout.EMPTY_Y - 70),
			Size = Components.PictureBox(Layout.EMPTY_GLYPH),
			ZIndex = 4,
		}),
		Label({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(Layout.SIZE.X / 2, Layout.EMPTY_Y),
			Size = UDim2.fromOffset(700, Layout.EMPTY_TEXT),
			TextSize = Layout.EMPTY_TEXT,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "NOBODY ELSE IS HERE YET",
		}),
		Label({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(Layout.SIZE.X / 2, Layout.EMPTY_Y + 42),
			Size = UDim2.fromOffset(700, Layout.EMPTY_SUB),
			FontFace = Font.DisplayBold,
			TextSize = Layout.EMPTY_SUB,
			TextColor3 = Palette.Lavender,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "Bring your Roblox friends in to fill the party.",
		}),
		Components.Button({
			Name = "InviteFriends",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.SIZE.X / 2, Layout.EMPTY_Y + 120),
			Size = UDim2.fromOffset(friends.X, friends.Y),
			BackgroundTransparency = 1,
			ZIndex = 4,
			Activated = function()
				hand.Commit()
				actions.InviteFriends()
			end,
			hand.Events,
			create("UIScale")({ Scale = hand.Scale }),
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
				Components.Sheen(hand.Glint, 3, friends.X / friends.Y),
				Components.Tracked("INVITE FRIENDS", Layout.FRIENDS_TEXT, 2, Font.Display, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
				}),
			}),
		}),
	})
end

function Invite.Build(state: Types.TLobbyState, actions: Types.TLobbyActions): ScreenGui
	local shown, drop, elapsed = motionOf(state)
	local isDrawn = derive(function(): boolean
		return shown() > 0
	end)
	local margin = Layout.MARGIN
	local window = Layout.WINDOW_SIZE
	local cell = Layout.CARD

	-- Sized from the cards rather than automatically: the scrollbar reads the canvas in its own px.
	local list = create("ScrollingFrame")({
		Name = "Players",
		Position = UDim2.fromOffset(Layout.WINDOW.X, Layout.WINDOW.Y),
		Size = UDim2.fromOffset(window.X, window.Y),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = function()
			local rows = math.ceil(#state.InvitePlayers() / Layout.COLUMNS)
			local height = rows * cell.Y + math.max(rows - 1, 0) * Layout.CARD_GAP
			return UDim2.fromOffset(0, height + 2 * Layout.WINDOW_PAD)
		end,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 0,
		ZIndex = 3,
		create("UIPadding")({
			PaddingTop = UDim.new(0, Layout.WINDOW_PAD),
			PaddingBottom = UDim.new(0, Layout.WINDOW_PAD),
			PaddingLeft = UDim.new(0, Layout.WINDOW_PAD),
		}),
		create("UIGridLayout")({
			CellSize = UDim2.fromOffset(cell.X, cell.Y),
			CellPadding = UDim2.fromOffset(Layout.CARD_GAP, Layout.CARD_GAP),
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		vide.values(state.InvitePlayers, function(player: Types.TInvitePlayer, index: () -> number)
			return card(state, actions, player, vide.untrack(index), elapsed)
		end),
	}) :: ScrollingFrame

	return create("ScreenGui")({
		Name = "Invite",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		-- Over the queue (5), under the pad's EXIT (7), which stands over its dim and shuts it.
		DisplayOrder = 6,
		Enabled = isDrawn,
		create("Frame")({
			Name = "Root",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(1920, 1080),
			BackgroundTransparency = 1,
			create("UIScale")({ Scale = state.PageScale }),
			-- Past the screen's edges whatever its shape. Leaving, it is only a picture and takes no presses.
			create("TextButton")({
				Name = "Dim",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(4, 4),
				BackgroundColor3 = Color3.new(),
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Modal = true,
				Text = "",
				Interactable = state.IsInviteOpen,
				BackgroundTransparency = function()
					return 1 - Gesture.DIM * shown()
				end,
				Activated = actions.CloseInvite,
			}),
			create("Frame")({
				Name = "Window",
				Position = function()
					return UDim2.fromOffset(Layout.PANEL.X, Layout.PANEL.Y + math.round(drop()))
				end,
				Size = UDim2.fromOffset(Layout.SIZE.X, Layout.SIZE.Y),
				BackgroundTransparency = 1,
				Interactable = state.IsInviteOpen,
				ZIndex = 2,
				Components.FadeGroup("Chrome", shown, {
					Position = UDim2.fromOffset(-margin, -margin),
					Size = UDim2.new(1, 2 * margin, 1, 2 * margin),
				}, {
					Components.Panel({ Brackets = true, Tall = true }, {
						Name = "Panel",
						Position = UDim2.fromOffset(margin, margin),
						Size = UDim2.new(1, -2 * margin, 1, -2 * margin),
						header(state),
						list,
						Scrollbar.Build(list, { Length = window.Y - 2 * Layout.WINDOW_PAD }, {
							AnchorPoint = Vector2.new(0.5, 0),
							Position = UDim2.fromOffset(Layout.SCROLLBAR_X, Layout.WINDOW.Y + Layout.WINDOW_PAD),
							ZIndex = 4,
						}),
						empty(state, actions),
					}),
				}),
			}),
		}),
	})
end

-- Seconds the panel takes to leave, and every gesture of its open: the controller keeps the clock ticking this long.
Invite.SETTLE_SECONDS = Parts.Timing.SETTLED
return Invite
