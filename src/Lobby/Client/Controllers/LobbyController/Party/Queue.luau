--!nonstrict
-- The queue on a 1920 x 1080, for everyone on a pad once its party is picked, in the lobby screens' look: the rest of
-- the HUD gone, the party's map at the top with its difficulty and a slot a player (lit as each one steps on), and at
-- the bottom what the pad is doing and the countdown, over the pad's EXIT (Exit). The server runs the countdown (15 s,
-- 3 once the pad is full); this counts down what it was told.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local MapsCore = require(ReplicatedStorage.GlobalShared.Core.MapsCore)
local PadsCore = require(ReplicatedStorage.Shared.Core.PadsCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
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
local EPhase = PadsCore.EPhase

-- Px at 1080 from the screen's top left; each piece by its middle.
local Layout = table.freeze({
	DESIGN = Vector2.new(1920, 1080),
	-- The map, 16:9 inside its edge, as the pictures are.
	CARD = Vector2.new(960, 196),
	CARD_SIZE = Vector2.new(456, 262),
	EDGE = 3,
	INSET = 18,
	NAME_TEXT = 36,
	INITIALS_SCALE = 1.3,
	TAG = Vector2.new(124, 30),
	TAG_TEXT = 16,
	ACCESS_CHIP = Vector2.new(150, 34),
	ACCESS_TEXT = 15,
	-- The slots under it.
	SLOTS_Y = 378,
	SLOT = 64,
	SLOT_GAP = 14,
	SLOT_GLYPH = 32,
	PLUS_TEXT = 30,
	COUNT_Y = 432,
	COUNT_TEXT = 20,
	-- The bottom: what the pad is doing, the clock and its bar.
	-- On a plaque: its middle, height and room either side of the word. Up enough to clear the clock's top (818).
	STATUS_Y = 790,
	STATUS_TEXT = 22,
	STATUS_HEIGHT = 30,
	STATUS_PAD = 16,
	CLOCK = Vector2.new(960, 874),
	CLOCK_SIZE = Vector2.new(240, 112),
	CLOCK_TEXT = 64,
	BAR = Vector2.new(176, 6),
	BAR_BOTTOM = 18,
	-- Room round a group for its glows, brackets and rings (a CanvasGroup clips).
	MARGIN = 90,
})

local Timing = table.freeze({
	FADE = 0.27,
	SLIDE = 0.42,
	TRAVEL = 36,
	CLOSE = 0.22,
	-- The host's party screen lifts away first.
	AFTER_CREATE = 0.22,
	SLOTS_DELAY = 0.12,
	SLOTS_STAGGER = 0.05,
	CLOCK_DELAY = 0.06,
	DEAL = 0.36,
	SETTLED = 1.6,
	-- A player stepping on: his slot pops, flashes and throws one ring.
	JOIN = 0.32,
	JOIN_FLASH = 0.35,
	JOIN_RING = 0.45,
	JOIN_RING_GROW = 22,
	-- Each second the number punches; in the last few it punches harder, ticks, and the clock throws a ring.
	TICK_PERIOD = 0.3,
	TICK_DAMPING = 0.5,
	TICK = 0.16,
	TICK_LATE = 0.32,
	LATE_SECONDS = 3,
	TICK_SOUND_SECONDS = 5,
	RING = 0.5,
	RING_GROW = 40,
	-- The clock flashes as the pad fills or the party goes.
	FLASH = 0.4,
	FLASH_PEAK = 0.5,
	-- The punch as the pad fills or the party goes.
	MOMENT_PUNCH = 0.4,
})

local Queue = {}

local function currentPad(state: Types.TLobbyState): Types.TPadView?
	return state.Pads[state.CurrentPad()]
end

-- One player's place on the party: lit while the party holds him, popping in with a flash and a ring as he steps on,
-- a dim plus while it waits.
local function slot(
	state: Types.TLobbyState,
	view: () -> { [string]: any },
	index: number,
	count: () -> number,
	dealt: () -> number
): { Instance }
	local filled = derive(function(): boolean
		return index <= view().Count
	end)
	local filledAt = source(-math.huge)
	Parts.OnChange(filled, function(isFilled: boolean)
		if isFilled then filledAt(os.clock()) end
	end)
	local popped = Parts.Since(state, filledAt, Timing.JOIN)
	local flashed = Parts.Since(state, filledAt, Timing.JOIN_FLASH)
	local ringed = Parts.Since(state, filledAt, Timing.JOIN_RING)
	local center = function(): UDim2
		local total = count() * Layout.SLOT + (count() - 1) * Layout.SLOT_GAP
		local x = Layout.CARD.X - total / 2 + (index - 1) * (Layout.SLOT + Layout.SLOT_GAP) + Layout.SLOT / 2
		return UDim2.fromOffset(math.round(x), Layout.SLOTS_Y)
	end

	local tile = create("Frame")({
		Name = `Slot{index}`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = center,
		Size = UDim2.fromOffset(Layout.SLOT, Layout.SLOT),
		BackgroundTransparency = 1,
		Visible = function()
			return index <= count()
		end,
		ZIndex = 4,
		create("UIScale")({
			Scale = function()
				local pop = if filled() then 0.7 + 0.3 * Motion.OutBack(popped()) else 1
				return dealt() * pop
			end,
		}),
		-- Waiting: his dark plaque with a dim plus.
		Parts.Plaque({
			Name = "Empty",
			Size = UDim2.fromScale(1, 1),
			Visible = function()
				return not filled()
			end,
			ZIndex = 4,
			Label({
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextSize = Layout.PLUS_TEXT,
				TextColor3 = Palette.Lavender,
				TextTransparency = 0.45,
				Text = "+",
				ZIndex = 5,
			}),
		}),
		Components.Slab({ Kind = "Pink", Marks = true }, {
			Name = "Filled",
			Size = UDim2.fromScale(1, 1),
			Visible = filled,
			ZIndex = 4,
			Components.Picture(EIcons.Player, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = Components.PictureBox(Layout.SLOT_GLYPH),
				ZIndex = 6,
			}),
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				Visible = function()
					return flashed() < 1
				end,
				BackgroundTransparency = function()
					return 1 - 0.7 * (1 - Motion.Out(flashed()))
				end,
				ZIndex = 7,
				create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
			}),
		}),
	})

	local ring = create("Frame")({
		Name = `SlotRing{index}`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = center,
		Size = function()
			local grow = math.round(Timing.JOIN_RING_GROW * Motion.Decelerate(ringed()))
			return UDim2.fromOffset(Layout.SLOT + 2 * grow, Layout.SLOT + 2 * grow)
		end,
		BackgroundTransparency = 1,
		ZIndex = 3,
		create("UICorner")({ CornerRadius = UDim.new(0, 6) }),
		create("UIStroke")({ Color = Palette.Pink, Thickness = 2, Transparency = ringed }),
	})

	return { tile, ring }
end

-- The party's map: its picture, name and difficulty, and FRIENDS ONLY when it is.
local function mapCard(view: () -> { [string]: any }): Frame
	local size = Layout.CARD_SIZE
	local map = derive(function(): MapsCore.TMap
		return MapsCore.LIST[view().Map] or MapsCore.LIST[1]
	end)
	local difficulty = derive(function(): string
		return MapsCore.DIFFICULTIES[view().Difficulty] or MapsCore.DIFFICULTIES[1]
	end)

	return Components.Card({
		Accent = function()
			return Parts.AccentOf(map())
		end,
		Tint = 0.4,
		GlowTransparency = 0.7,
		Tall = true,
		Brackets = true,
	}, {
		Name = "Map",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(Layout.CARD.X, Layout.CARD.Y),
		Size = UDim2.fromOffset(size.X, size.Y),
		ZIndex = 3,
		create("Frame")({
			Name = "Window",
			Position = UDim2.fromOffset(Layout.EDGE, Layout.EDGE),
			Size = UDim2.new(1, -2 * Layout.EDGE, 1, -2 * Layout.EDGE),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 4,
			Parts.Picture(map, Layout.INITIALS_SCALE, {}),
			Parts.Shade(),
			Parts.DifficultyTag(difficulty, Layout.TAG_TEXT, {
				Position = UDim2.fromOffset(Layout.INSET - 4, Layout.INSET - 4),
				Size = UDim2.fromOffset(Layout.TAG.X, Layout.TAG.Y),
			}),
			Parts.Plaque({
				Name = "FriendsOnly",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -Layout.INSET + 4, 0, Layout.INSET - 4),
				Size = UDim2.fromOffset(Layout.ACCESS_CHIP.X, Layout.ACCESS_CHIP.Y),
				Visible = function()
					return view().IsFriendsOnly
				end,
				ZIndex = 6,
				Components.Picture(EIcons.Friends, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(22, Layout.ACCESS_CHIP.Y / 2),
					Size = Components.PictureBox(18),
					ZIndex = 7,
				}),
				Label({
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(0.5, 16, 0.5, 1),
					Size = UDim2.new(1, -44, 0, Layout.ACCESS_TEXT),
					TextXAlignment = Enum.TextXAlignment.Center,
					TextYAlignment = Enum.TextYAlignment.Center,
					TextSize = Layout.ACCESS_TEXT,
					ZIndex = 7,
					Text = "FRIENDS ONLY",
				}),
			}),
			Label({
				Name = "Name",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, Layout.INSET, 1, -Layout.INSET + 4),
				Size = UDim2.new(1, -2 * Layout.INSET, 0, Layout.NAME_TEXT),
				TextSize = Layout.NAME_TEXT,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 7,
				Text = function()
					return string.upper(map().DisplayName)
				end,
			}),
		}),
	})
end

-- The clock: the seconds left on his dark panel, punching each second and harder in the last few, a bar draining
-- under them, a flash as the pad fills or the party goes.
local function clock(
	state: Types.TLobbyState,
	actions: Types.TLobbyActions,
	view: () -> { [string]: any },
	dealt: () -> number
): { Instance }
	local punch, strikePunch = Hand.Kick(Timing.TICK_PERIOD, Timing.TICK_DAMPING)
	local flashAt = source(-math.huge)
	local ringAt = source(-math.huge)
	local flashed = Parts.Since(state, flashAt, Timing.FLASH)
	local ringed = Parts.Since(state, ringAt, Timing.RING)
	local isFull = derive(function(): boolean
		return view().Count >= view().MaxPlayers
	end)
	local isGoing = derive(function(): boolean
		return view().Phase == EPhase.Teleporting
	end)
	local seconds = derive(function(): number
		return view().Seconds
	end)

	local hot = function(): Color3
		return if isFull() or isGoing() then Palette.Gold else Palette.Pink
	end

	Parts.OnChange(seconds, function(current: number)
		if current < 0 then return end
		local isLate = current <= Timing.LATE_SECONDS
		strikePunch(if isLate then Timing.TICK_LATE else Timing.TICK)
		if isLate and current > 0 then ringAt(os.clock()) end
		if current > 0 and current <= Timing.TICK_SOUND_SECONDS then SoundsCore.PlayUINamed("UI", "CountdownTick") end
		actions.Stir(Timing.RING)
	end)
	-- The pad filling, or the party going: a flash, a ring and a harder punch.
	local function strikeMoment(isNow: boolean)
		if not isNow then return end
		flashAt(os.clock())
		ringAt(os.clock())
		strikePunch(Timing.MOMENT_PUNCH)
		actions.Stir(Timing.FLASH + 0.1)
	end
	Parts.OnChange(isFull, strikeMoment)
	Parts.OnChange(isGoing, strikeMoment)
	local share = Parts.CountdownShare(seconds, isFull, isGoing)
	local size = Layout.CLOCK_SIZE

	local panel = Components.Panel({ Brackets = true }, {
		Name = "Clock",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(Layout.CLOCK.X, Layout.CLOCK.Y),
		Size = UDim2.fromOffset(size.X, size.Y),
		ZIndex = 3,
		create("UIScale")({ Scale = dealt }),
		Label({
			Name = "Seconds",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, -8),
			Size = UDim2.fromOffset(size.X, Layout.CLOCK_TEXT),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextSize = Layout.CLOCK_TEXT,
			TextColor3 = function()
				return if isFull() or isGoing() then Palette.Gold else Palette.White
			end,
			ZIndex = 5,
			Text = function()
				return if isGoing() then "GO" else `{math.max(seconds(), 0)}s`
			end,
			create("UIScale")({
				Scale = function()
					return 1 + punch()
				end,
			}),
		}),
		Parts.CountdownBar(share, Layout.BAR, hot, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -Layout.BAR_BOTTOM),
		}),
		create("Frame")({
			Name = "Flash",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Palette.White,
			BorderSizePixel = 0,
			Visible = function()
				return flashed() < 1
			end,
			BackgroundTransparency = function()
				return 1 - Timing.FLASH_PEAK * (1 - Motion.Out(flashed()))
			end,
			ZIndex = 7,
			create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
		}),
	})

	-- One ring off the clock, growing by pixels at one weight.
	local ring = create("Frame")({
		Name = "ClockRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(Layout.CLOCK.X, Layout.CLOCK.Y),
		Size = function()
			local grow = math.round(Timing.RING_GROW * Motion.Decelerate(ringed()))
			return UDim2.fromOffset(size.X + 2 * grow, size.Y + 2 * grow)
		end,
		BackgroundTransparency = 1,
		ZIndex = 2,
		create("UICorner")({ CornerRadius = UDim.new(0, 6) }),
		create("UIStroke")({ Color = hot, Thickness = 2, Transparency = ringed }),
	})

	return { panel, ring }
end

-- What the pad is doing, on his dark plaque: bare gold is lost on the pad's lit yellow glow behind it. The plaque is
-- sized by a hidden copy of the word, as the party screen's chips are.
local function status(view: () -> { [string]: any }): Frame
	local word = derive(function(): string
		local current = view()
		if current.Phase == EPhase.Teleporting then return "TELEPORTING" end
		if current.Count >= current.MaxPlayers then return "PARTY FULL" end
		return "WAITING FOR PLAYERS"
	end)
	local wordWidth = source(0)

	return Parts.Plaque({
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(Layout.CLOCK.X, Layout.STATUS_Y),
		Size = function()
			return UDim2.fromOffset(wordWidth() + 2 * Layout.STATUS_PAD, Layout.STATUS_HEIGHT)
		end,
		ZIndex = 4,
		Label({
			Name = "Measure",
			Size = UDim2.fromOffset(600, Layout.STATUS_TEXT),
			TextSize = Layout.STATUS_TEXT,
			TextTransparency = 1,
			Text = word,
			vide.changed("TextBounds", function(bounds: Vector2)
				wordWidth(math.ceil(bounds.X))
			end),
		}),
		Label({
			Name = "Word",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 0, 0, Layout.STATUS_TEXT),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextSize = Layout.STATUS_TEXT,
			TextColor3 = Palette.Gold,
			ZIndex = 6,
			Text = word,
			create("UIPadding")({ PaddingTop = UDim.new(0, 2) }),
		}),
	})
end

function Queue.Build(state: Types.TLobbyState, actions: Types.TLobbyActions): ScreenGui
	local isQueued = derive(function(): boolean
		return currentPad(state) ~= nil and not state.IsChoosing()
	end)
	-- What the pad last said while this player was on it: kept as the screen leaves, when he is on no pad.
	local view = source({
		Phase = EPhase.Open,
		Count = 0,
		MaxPlayers = PadsCore.DEFAULT_PLAYERS,
		Map = 1,
		Difficulty = 1,
		IsFriendsOnly = false,
		Seconds = -1,
	})
	vide.effect(function()
		local pad = currentPad(state)
		if not pad then return end
		local current = {
			Phase = pad.Phase(),
			Count = pad.Count(),
			MaxPlayers = pad.MaxPlayers(),
			Map = pad.Map(),
			Difficulty = pad.Difficulty(),
			IsFriendsOnly = pad.IsFriendsOnly(),
			Seconds = pad.Seconds(),
		}
		vide.untrack(function()
			local last = view()
			for key, value in current do
				if last[key] ~= value then
					view(current)
					return
				end
			end
		end)
	end)

	-- When it came up or went: after the party screen has lifted away for a host who just made the party.
	local toggledAt = source(-math.huge)
	local isShown = source(false)
	vide.effect(function()
		local queued = isQueued()
		vide.untrack(function()
			if queued == isShown() then return end
			local now = os.clock()
			local isAfterCreate = queued and now - state.CreatedAt() < 2
			isShown(queued)
			toggledAt(now + (if isAfterCreate then Timing.AFTER_CREATE else 0))
			actions.Stir(Timing.SETTLED + Timing.AFTER_CREATE)
		end)
	end)
	local elapsed = derive(function(): number
		return math.min(state.Now() - toggledAt(), Timing.SETTLED)
	end)
	local shown = derive(function(): number
		if isShown() then return Motion.Out(Progress(elapsed(), 0, Timing.FADE)) end
		return 1 - Progress(elapsed(), 0, Timing.CLOSE)
	end)
	local away = derive(function(): number
		if isShown() then return 1 - Motion.Decelerate(Progress(elapsed(), 0, Timing.SLIDE)) end
		return Motion.Accelerate(Progress(elapsed(), 0, Timing.CLOSE))
	end)
	local function dealt(delay: number): () -> number
		return derive(function(): number
			if not isShown() then return 1 end
			return Motion.Decelerate(Progress(elapsed(), delay, Timing.DEAL))
		end)
	end
	local count = derive(function(): number
		return view().MaxPlayers
	end)

	local slots = {}
	for index = 1, PadsCore.MAX_PLAYERS do
		slots[index] = slot(state, view, index, count, dealt(Timing.SLOTS_DELAY + Timing.SLOTS_STAGGER * (index - 1)))
	end

	local margin = Layout.MARGIN
	-- Half the screen, fading as one while it comes and goes and travelling `direction` px times `away`.
	local function group(name: string, direction: number, children: { any }): { Instance }
		return Components.FadeGroup(name, shown, {
			Position = function()
				return UDim2.fromOffset(-margin, -margin + math.round(direction * Timing.TRAVEL * away()))
			end,
			Size = UDim2.fromOffset(Layout.DESIGN.X + 2 * margin, Layout.DESIGN.Y + 2 * margin),
		}, {
			create("Frame")({
				Name = "Design",
				Position = UDim2.fromOffset(margin, margin),
				Size = UDim2.fromOffset(Layout.DESIGN.X, Layout.DESIGN.Y),
				BackgroundTransparency = 1,
				children,
			}),
		})
	end

	return create("ScreenGui")({
		Name = "Queue",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
		Enabled = derive(function(): boolean
			return shown() > 0
		end),
		create("Frame")({
			Name = "Root",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(Layout.DESIGN.X, Layout.DESIGN.Y),
			BackgroundTransparency = 1,
			create("UIScale")({ Scale = state.PageScale }),
			group("Top", -1, {
				mapCard(view),
				slots,
				Label({
					Name = "Count",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(Layout.CARD.X, Layout.COUNT_Y),
					Size = UDim2.fromOffset(400, Layout.COUNT_TEXT),
					TextXAlignment = Enum.TextXAlignment.Center,
					TextYAlignment = Enum.TextYAlignment.Center,
					TextSize = Layout.COUNT_TEXT,
					TextColor3 = Palette.Lavender,
					Text = function()
						return `{view().Count} / {view().MaxPlayers} PLAYERS`
					end,
				}),
			}),
			group("Bottom", 1, {
				status(view),
				clock(state, actions, view, dealt(Timing.CLOCK_DELAY)),
			}),
		}),
	})
end

return Queue
