--!nonstrict
-- The board over each pad once its party is made, in the lobby screens' look: the party's map (its picture, name and
-- difficulty) with how many are on it, and under it how long until it leaves, what it is doing, and a bar draining
-- with the time. Sized in studs, so it is a sign in the world that shrinks with distance; laid out in px (BOX) and
-- fitted to however big the billboard is drawn, as the head tags are. Every motion on it is a spring, so a board
-- costs the lobby's clock nothing.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local MapsCore = require(ReplicatedStorage.GlobalShared.Core.MapsCore)
local PadsCore = require(ReplicatedStorage.Shared.Core.PadsCore)
local Parts = require(script.Parent.Parts)
local Types = require(script.Parent.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local source = vide.source
local Palette = Theme.Palette
local Label = Parts.Label
local EPhase = PadsCore.EPhase

-- Px of the board as it is laid out.
local Layout = table.freeze({
	BOX = Vector2.new(440, 340),
	CARD_HEIGHT = 250,
	EDGE = 3,
	INSET = 16,
	NAME_TEXT = 34,
	INITIALS_SCALE = 1.3,
	TAG = Vector2.new(118, 28),
	TAG_TEXT = 15,
	COUNT = Vector2.new(100, 36),
	COUNT_TEXT = 20,
	COUNT_GLYPH = 20,
	PLATE_TOP = 262,
	PLATE_HEIGHT = 78,
	SECONDS_X = 74,
	SECONDS_TEXT = 40,
	STATUS_RIGHT = 20,
	STATUS_TEXT = 17,
	BAR = Vector2.new(400, 5),
	BAR_BOTTOM = 10,
})

local Tune = table.freeze({
	-- The board in studs, at BOX's ratio, how far over the pad's top its middle floats, and how far away it is drawn.
	WIDTH_STUDS = 8,
	RISE_STUDS = 8.5,
	MAX_DISTANCE_STUDS = 160,
	-- It grows in from its middle as the party is made and shrinks away as it leaves.
	SHOW_PERIOD = 0.35,
	-- A change of count or a second punches its readout, harder in the last few seconds.
	PUNCH_PERIOD = 0.3,
	PUNCH_DAMPING = 0.5,
	COUNT_PUNCH = 0.3,
	TICK = 0.14,
	TICK_LATE = 0.3,
	LATE_SECONDS = 3,
})

local Board = {}

-- A punch on every change of `value`, by `strength(value)`.
local function punchOn(value: () -> any, strength: (any) -> number): () -> number
	local punch, strike = Hand.Kick(Tune.PUNCH_PERIOD, Tune.PUNCH_DAMPING)
	Parts.OnChange(value, function(current)
		strike(strength(current))
	end)
	return punch
end

local function card(pad: Types.TPadView, map: () -> MapsCore.TMap, difficulty: () -> string): Frame
	local count = derive(function(): string
		return `{pad.Count()}/{pad.MaxPlayers()}`
	end)
	local countPunch = punchOn(count, function()
		return Tune.COUNT_PUNCH
	end)

	return Components.Card({
		Accent = function()
			return Parts.AccentOf(map())
		end,
		Tint = 0.4,
		GlowTransparency = 0.7,
		Tall = true,
	}, {
		Name = "Map",
		Size = UDim2.fromOffset(Layout.BOX.X, Layout.CARD_HEIGHT),
		ZIndex = 2,
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
				Name = "Count",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -Layout.INSET + 4, 0, Layout.INSET - 4),
				Size = UDim2.fromOffset(Layout.COUNT.X, Layout.COUNT.Y),
				ZIndex = 6,
				Components.Picture(EIcons.Player, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(24, Layout.COUNT.Y / 2),
					Size = Components.PictureBox(Layout.COUNT_GLYPH),
					ZIndex = 7,
				}),
				Label({
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(0.5, 14, 0.5, 1),
					Size = UDim2.new(1, -44, 0, Layout.COUNT_TEXT),
					TextXAlignment = Enum.TextXAlignment.Center,
					TextYAlignment = Enum.TextYAlignment.Center,
					TextSize = Layout.COUNT_TEXT,
					ZIndex = 7,
					Text = count,
					create("UIScale")({
						Scale = function()
							return 1 + countPunch()
						end,
					}),
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

local function plate(pad: Types.TPadView): Frame
	local isFull = derive(function(): boolean
		return pad.Count() >= pad.MaxPlayers()
	end)
	local isGoing = derive(function(): boolean
		return pad.Phase() == EPhase.Teleporting
	end)
	local seconds = derive(function(): number
		return math.max(pad.Seconds(), 0)
	end)
	local tick = punchOn(seconds, function(current: number): number
		return if current <= Tune.LATE_SECONDS then Tune.TICK_LATE else Tune.TICK
	end)
	local hot = function(): Color3
		return if isFull() or isGoing() then Palette.Gold else Palette.Pink
	end
	local share = Parts.CountdownShare(seconds, isFull, isGoing)

	return Components.Panel({}, {
		Name = "Plate",
		Position = UDim2.fromOffset(0, Layout.PLATE_TOP),
		Size = UDim2.fromOffset(Layout.BOX.X, Layout.PLATE_HEIGHT),
		ZIndex = 2,
		Label({
			Name = "Seconds",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, Layout.SECONDS_X, 0.5, -4),
			Size = UDim2.fromOffset(120, Layout.SECONDS_TEXT),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextSize = Layout.SECONDS_TEXT,
			TextColor3 = function()
				return if isFull() or isGoing() then Palette.Gold else Palette.White
			end,
			Text = function()
				return if isGoing() then "GO" else `{seconds()}s`
			end,
			create("UIScale")({
				Scale = function()
					return 1 + tick()
				end,
			}),
		}),
		Label({
			Name = "Status",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -Layout.STATUS_RIGHT, 0.5, -4),
			Size = UDim2.fromOffset(260, Layout.STATUS_TEXT),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextSize = Layout.STATUS_TEXT,
			TextColor3 = Palette.Gold,
			Text = function()
				if isGoing() then return "TELEPORTING" end
				return if isFull() then "PARTY FULL" else "WAITING FOR PLAYERS"
			end,
		}),
		Parts.CountdownBar(share, Layout.BAR, hot, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -Layout.BAR_BOTTOM),
		}),
	})
end

local function board(state: Types.TLobbyState, pad: Types.TPadView): BillboardGui
	local box = Layout.BOX
	local map = derive(function(): MapsCore.TMap
		return MapsCore.LIST[pad.Map()] or MapsCore.LIST[1]
	end)
	local difficulty = derive(function(): string
		return MapsCore.DIFFICULTIES[pad.Difficulty()] or MapsCore.DIFFICULTIES[1]
	end)
	-- Not over the pad this player stands on: his queue screen already says all of it, and the board would hang in
	-- front of his camera.
	local isMade = derive(function(): boolean
		if state.CurrentPad() == pad.Index then return false end
		local phase = pad.Phase()
		return phase == EPhase.Open or phase == EPhase.Teleporting
	end)
	local shown = Hand.Spring(function(): number
		return if isMade() then 1 else 0
	end, Tune.SHOW_PERIOD)
	local scale = source(1)

	return create("BillboardGui")({
		Name = `PadBoard{pad.Index}`,
		Adornee = pad.Part,
		Size = UDim2.fromScale(Tune.WIDTH_STUDS, Tune.WIDTH_STUDS * box.Y / box.X),
		StudsOffsetWorldSpace = Vector3.new(0, pad.Part.Size.Y / 2 + Tune.RISE_STUDS, 0),
		MaxDistance = Tune.MAX_DISTANCE_STUDS,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Enabled = derive(function(): boolean
			return shown() > 0.01
		end),
		-- The board is laid out in px; this fits it to however big the billboard is drawn.
		create("Frame")({
			Name = "Root",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			vide.changed("AbsoluteSize", function(size: Vector2)
				scale(size.X / box.X)
			end),
			create("Frame")({
				Name = "Board",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(box.X, box.Y),
				BackgroundTransparency = 1,
				create("UIScale")({
					Scale = function()
						return scale() * math.clamp(shown(), 0, 1)
					end,
				}),
				card(pad, map, difficulty),
				plate(pad),
			}),
		}),
	})
end

function Board.Build(state: Types.TLobbyState): { BillboardGui }
	local boards = table.create(#state.Pads)
	for index, pad in state.Pads do
		boards[index] = board(state, pad)
	end

	return boards
end

return Board
