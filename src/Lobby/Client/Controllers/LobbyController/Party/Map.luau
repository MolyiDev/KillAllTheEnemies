--!nonstrict
-- The party screen's map: the showcase (the picked map's picture, its name and the player's best wave on it, with
-- arrows either side) and the dots under it, one a map, the picked one drawn out long. A pick is a carousel: the old
-- picture slides out the way it was turned and the new one in behind it, its name a beat after, and a light crosses
-- the showcase as it lands.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local MapsCore = require(ReplicatedStorage.GlobalShared.Core.MapsCore)
local Parts = require(script.Parent.Parts)
local Types = require(script.Parent.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local spring = vide.spring
local Palette = Theme.Palette
local Label = Parts.Label

-- Px at 1080 from the panel's top left.
local Layout = table.freeze({
	HEADER = Vector2.new(31, 118),
	-- 16:9 inside its 3 px edge, as the pictures are.
	SHOWCASE = Vector2.new(31, 156),
	SHOWCASE_SIZE = Vector2.new(700, 394),
	EDGE = 3,
	INSET = 24,
	NAME_TEXT = 58,
	INITIALS_TEXT = 210,
	CHIP = Vector2.new(196, 42),
	CHIP_GLYPH = 20,
	CHIP_TEXT = 18,
	LOCK_GLYPH = 56,
	LOCK_TEXT = 20,
	ARROW = 56,
	ARROW_INSET = 16,
	ARROW_GLYPH = 24,
	-- The dots, as the portfolio draws its slides' (8 px, 28 px picked, 8 px apart) at this screen's size.
	DOTS_Y = 574,
	DOT = 10,
	DOT_PICKED = 36,
	DOT_GAP = 10,
	DOT_HIT = Vector2.new(30, 30),
})

local Timing = table.freeze({
	SHOWCASE_DELAY = 0.06,
	DOTS_DELAY = 0.2,
	DOTS_STAGGER = 0.04,
	-- The carousel: the pictures cross over this long, the name a beat behind and a shorter way.
	SLIDE = 0.45,
	NAME_DELAY = 0.06,
	NAME_PX = 34,
	ACCENT_PERIOD = 0.3,
	-- The light crosses the showcase as a pick lands, and as the open settles.
	SHEEN = 0.6,
	SHEEN_DELAY = 0.16,
	OPEN_SHEEN_DELAY = 0.45,
	-- The best wave's number punches when the map changes it.
	PUNCH_PERIOD = 0.3,
	PUNCH_DAMPING = 0.5,
	PUNCH = 0.25,
	-- A dot draws out and goes white as the portfolio's do: 250 ms on the standard curve.
	DOT = 0.25,
	DOT_HOVER_PERIOD = 0.12,
	DOT_HOVER = 0.3,
	DOT_DIM = 0.55,
})

local Map = {}

-- The player's best wave on the picked map, on his dark plaque at the showcase's top right; it punches as a pick
-- changes it.
local function bestChip(best: () -> number): Frame
	local punch, strikePunch = Hand.Kick(Timing.PUNCH_PERIOD, Timing.PUNCH_DAMPING)
	Parts.OnChange(best, function()
		strikePunch(Timing.PUNCH)
	end)

	return Parts.Plaque({
		Name = "Best",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Layout.INSET + 8, 0, Layout.INSET - 8),
		Size = UDim2.fromOffset(Layout.CHIP.X, Layout.CHIP.Y),
		ZIndex = 7,
		Components.Picture(EIcons.Star, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(26, Layout.CHIP.Y / 2),
			Size = Components.PictureBox(Layout.CHIP_GLYPH),
			ZIndex = 8,
		}),
		-- Placed by its middle, so its punch grows from there.
		Label({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 21, 0.5, 1),
			Size = UDim2.new(1, -56, 0, Layout.CHIP_TEXT),
			TextSize = Layout.CHIP_TEXT,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			Text = function()
				return `BEST WAVE {best()}`
			end,
			ZIndex = 8,
			create("UIScale")({
				Scale = function()
					return 1 + punch()
				end,
			}),
		}),
	})
end

-- His dark arrow button at one end of the showcase: `step` -1 points back, 1 on. The glyph leans the way it goes under
-- the hand.
local function arrow(actions: Types.TLobbyActions, step: number): TextButton
	local hand = Hand.React("Operate")
	local size = Layout.ARROW
	local x = if step < 0 then Layout.ARROW_INSET + size / 2 else Layout.SHOWCASE_SIZE.X - Layout.ARROW_INSET - size / 2

	return Components.Button({
		Name = if step < 0 then "Back" else "On",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, Layout.SHOWCASE_SIZE.Y / 2),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		ZIndex = 8,
		Visible = #MapsCore.LIST > 1,
		Activated = function()
			hand.Commit()
			actions.StepMap(step)
		end,
		hand.Events,
		create("UIScale")({ Scale = hand.Scale }),
		Parts.Plaque({
			Name = "Plaque",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 8,
			Components.Brackets(hand.Rise, function()
				return 0.6 - 0.3 * hand.Light()
			end, 12),
			Hand.WashLayer(hand, 9, 2),
			Components.Picture(EIcons.Arrow, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = function()
					return UDim2.new(0.5, math.round(step * 4 * hand.Rise()), 0.5, 0)
				end,
				Size = Components.PictureBox(Layout.ARROW_GLYPH),
				Rotation = if step < 0 then 180 else 0,
				ImageColor3 = Palette.White,
				ZIndex = 10,
			}),
		}),
	}) :: TextButton
end

-- One map's picture filling the window, at `x()` px across it.
local function picture(index: () -> number, x: () -> number): Frame
	local map = derive(function(): MapsCore.TMap
		return MapsCore.LIST[index()] or MapsCore.LIST[1]
	end)

	return Parts.Picture(map, Layout.INITIALS_TEXT / 100, {
		Position = function()
			return UDim2.fromOffset(x(), 0)
		end,
	})
end

local function showcase(state: Types.TLobbyState, actions: Types.TLobbyActions, elapsed: () -> number): Frame
	local size = Layout.SHOWCASE_SIZE
	local window = size - Vector2.new(2 * Layout.EDGE, 2 * Layout.EDGE)
	local dealt = Parts.Dealt(state, elapsed, Timing.SHOWCASE_DELAY)
	local picked = derive(function()
		return Parts.PickedMap(state)
	end)
	local isLocked = derive(function(): boolean
		return Parts.IsLocked(state, picked())
	end)
	local accent = spring(function(): Color3
		return if isLocked() then Parts.LOCKED else Parts.AccentOf(picked())
	end, Timing.ACCENT_PERIOD, 1)
	local slid = Parts.Since(state, state.MapAt, Timing.SLIDE)
	local named = Parts.Since(state, state.MapAt, Timing.SLIDE, Timing.NAME_DELAY)
	-- The new picture comes in from the side it was turned to and the old one goes out the other way, both on one
	-- decelerating curve, so they meet edge to edge the whole way.
	local travel = derive(function(): number
		return Motion.Decelerate(slid())
	end)
	local comingX = derive(function(): number
		return math.round(state.MapStep() * window.X * (1 - travel()))
	end)
	local goingX = derive(function(): number
		return math.round(-state.MapStep() * window.X * travel())
	end)
	local nameX = derive(function(): number
		return math.round(state.MapStep() * Timing.NAME_PX * (1 - Motion.Decelerate(named())))
	end)
	local swept = Parts.Since(state, state.MapAt, Timing.SHEEN, Timing.SHEEN_DELAY)
	local openSwept = derive(function(): number
		if not state.IsChoosing() then return 1 end
		return Motion.Progress(elapsed(), Timing.OPEN_SHEEN_DELAY, Timing.SHEEN)
	end)
	local best = derive(function(): number
		return Parts.BestOf(state, picked())
	end)

	return Components.Card({
		Accent = accent,
		Tint = 0.4,
		GlowTransparency = 0.72,
		Tall = true,
		Brackets = true,
	}, {
		Name = "Showcase",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(Layout.SHOWCASE.X + size.X / 2, Layout.SHOWCASE.Y + size.Y / 2),
		Size = UDim2.fromOffset(size.X, size.Y),
		ZIndex = 3,
		create("UIScale")({
			Scale = function()
				return 0.9 + 0.1 * dealt()
			end,
		}),
		create("Frame")({
			Name = "Window",
			Position = UDim2.fromOffset(Layout.EDGE, Layout.EDGE),
			Size = UDim2.fromOffset(window.X, window.Y),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 4,
			picture(state.MapFrom, goingX),
			picture(state.PickMap, comingX),
			Parts.Shade(),
			Label({
				Name = "Name",
				AnchorPoint = Vector2.new(0, 1),
				Position = function()
					return UDim2.new(0, Layout.INSET + nameX(), 1, -Layout.INSET + 6)
				end,
				Size = UDim2.fromOffset(window.X - 2 * Layout.INSET, Layout.NAME_TEXT),
				TextSize = Layout.NAME_TEXT,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextTransparency = function()
					return 1 - Motion.Out(named())
				end,
				ZIndex = 7,
				Text = function()
					return string.upper(picked().DisplayName)
				end,
			}),
			bestChip(best),
			create("Frame")({
				Name = "Locked",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.new(),
				BackgroundTransparency = 0.35,
				BorderSizePixel = 0,
				Visible = isLocked,
				ZIndex = 8,
				Components.Picture(EIcons.Lock, {
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 0.5, 4),
					Size = Components.PictureBox(Layout.LOCK_GLYPH),
					ZIndex = 9,
				}),
				Label({
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0.5, 18),
					Size = UDim2.new(1, -2 * Layout.INSET, 0, Layout.LOCK_TEXT),
					TextXAlignment = Enum.TextXAlignment.Center,
					TextSize = Layout.LOCK_TEXT,
					TextColor3 = Palette.Lavender,
					ZIndex = 9,
					Text = function()
						return string.upper(MapsCore.RequirementText(picked()))
					end,
				}),
			}),
		}),
		Components.Sheen(function(): number
			return math.min(swept(), openSwept())
		end, 9),
		arrow(actions, -1),
		arrow(actions, 1),
	})
end

-- The dots under the showcase, as the portfolio's: the picked one long and white, the rest short and dim, each drawing
-- out or in over 250 ms on the standard curve, the row centred on the showcase as their widths change. A dot is a
-- button: it picks its map.
local function dots(state: Types.TLobbyState, actions: Types.TLobbyActions, elapsed: () -> number): { Instance }
	local count = #MapsCore.LIST
	local changed = Parts.Since(state, state.MapAt, Timing.DOT)
	-- How picked each dot is, 0 to 1, as one list: the row's centring reads every width.
	local shares = derive(function(): { number }
		local t = Parts.Standard(changed())
		local from, to = state.MapFrom(), state.PickMap()
		local list = table.create(count)
		for index = 1, count do
			local was = if index == from then 1 else 0
			local is = if index == to then 1 else 0
			list[index] = was + (is - was) * t
		end
		return list
	end)
	-- Each dot's middle, in px from the panel's left.
	local centers = derive(function(): { number }
		local list = shares()
		local total = Layout.DOT_GAP * (count - 1)
		for _, share in list do
			total += Layout.DOT + (Layout.DOT_PICKED - Layout.DOT) * share
		end

		local middles = table.create(count)
		local x = Layout.SHOWCASE.X + Layout.SHOWCASE_SIZE.X / 2 - total / 2
		for index, share in list do
			local width = Layout.DOT + (Layout.DOT_PICKED - Layout.DOT) * share
			middles[index] = x + width / 2
			x += width + Layout.DOT_GAP
		end
		return middles
	end)

	local pieces = table.create(count)
	for index = 1, count do
		local dealt = Parts.Dealt(state, elapsed, Timing.DOTS_DELAY + Timing.DOTS_STAGGER * (index - 1))
		local events, isHovered = Hand.Track()
		local hover = Hand.Spring(function(): number
			return if isHovered() and state.PickMap() ~= index then 1 else 0
		end, Timing.DOT_HOVER_PERIOD)
		local share = function(): number
			return shares()[index]
		end
		pieces[index] = Components.Button({
			Name = `Dot{index}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				return UDim2.fromOffset(math.round(centers()[index]), Layout.DOTS_Y)
			end,
			Size = UDim2.fromOffset(Layout.DOT_HIT.X, Layout.DOT_HIT.Y),
			BackgroundTransparency = 1,
			ZIndex = 4,
			Activated = function()
				actions.PickMap(index)
			end,
			events,
			create("Frame")({
				Name = "Dot",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = function()
					local width = Layout.DOT + (Layout.DOT_PICKED - Layout.DOT) * share()
					return UDim2.fromOffset(math.round(width), Layout.DOT)
				end,
				BackgroundColor3 = Palette.White,
				BackgroundTransparency = function()
					local dim = Timing.DOT_DIM * (1 - share())
					return dim * (1 - hover())
				end,
				BorderSizePixel = 0,
				ZIndex = 4,
				create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
				create("UIScale")({
					Scale = function()
						return dealt() * (1 + Timing.DOT_HOVER * hover())
					end,
				}),
			}),
		})
	end

	return pieces
end

function Map.Build(state: Types.TLobbyState, actions: Types.TLobbyActions, elapsed: () -> number): { Instance }
	return {
		Parts.Header({
			At = Layout.HEADER,
			Width = Layout.SHOWCASE_SIZE.X,
			Picture = EIcons.Star,
			Word = "MAP",
		}),
		showcase(state, actions, elapsed),
		dots(state, actions, elapsed),
	}
end

return Map
