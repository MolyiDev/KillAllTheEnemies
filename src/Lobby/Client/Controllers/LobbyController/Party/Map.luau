--!nonstrict
-- The party screen's map: the showcase (the picked map's page: its picture, the player's best wave on it, and, while
-- it is not open, a veil with the padlock and what it asks for; its name, and arrows either side) and the path under
-- it, one point a map in the order they are played, joined by a track that runs as far as the maps opened. The path
-- shows the maps reached, the next one, and a '?' past them (Parts.PathCount), whose page is all '?'. A pick is a
-- carousel: the old page slides out the way it was turned and the new one in behind it, its name a beat after, and a
-- light crosses the showcase as it lands. A map opened since its last visit plays its unlock (Parts.Unlock) as it
-- comes up, and the path grows a point past it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Ribbon = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Ribbon)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local MapsCore = require(ReplicatedStorage.GlobalShared.Core.MapsCore)
local Parts = require(script.Parent.Parts)
local padlock = require(script.Parent.Parent.Parent.Parent.Utils.padlock)
local Types = require(script.Parent.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local spring = vide.spring
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
local Label = Parts.Label
local Unlock = Parts.Unlock

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
	ARROW = 56,
	ARROW_INSET = 16,
	ARROW_GLYPH = 24,
	-- Under the veil, from the window's top: the padlock's (or the '?''s) middle and longer side, and the requirements'
	-- rows.
	LOCK_Y = 118,
	LOCK = 92,
	MYSTERY_TEXT = 100,
	ROWS_Y = 196,
	ROW = Vector2.new(470, 42),
	ROW_GAP = 8,
	ROW_GLYPH = 24,
	ROW_TEXT = 17,
	ROW_CHECK = 20,
	-- NEW across the showcase's top left corner.
	RIBBON_ALONG = 92,
	RIBBON_THICKNESS = 28,
	RIBBON_TEXT = 17,
	-- The path: its points' middles STEP apart, centred under the showcase as it grows, the track between them.
	PATH_Y = 574,
	PATH_STEP = 170,
	NODE = 28,
	NODE_TEXT = 17,
	NODE_GLYPH = 16,
	NODE_HIT = Vector2.new(44, 40),
	TRACK = 4,
	TRACK_GAP = 10,
})

local Timing = table.freeze({
	SHOWCASE_DELAY = 0.06,
	PATH_DELAY = 0.2,
	PATH_STAGGER = 0.05,
	-- The carousel: the pictures cross over this long, the name a beat behind and a shorter way.
	SLIDE = 0.45,
	NAME_DELAY = 0.06,
	NAME_PX = 34,
	ACCENT_PERIOD = 0.3,
	-- The light crosses the showcase as a pick lands, and as the open settles.
	SHEEN = 0.6,
	SHEEN_DELAY = 0.16,
	OPEN_SHEEN_DELAY = 0.45,
	-- The showcase's pop as it comes out from under the veil.
	POP_PERIOD = 0.32,
	POP_DAMPING = 0.5,
	-- An arrow with no map past it shrinks away.
	ARROW_PERIOD = 0.18,
	-- A row ticked off: its edge goes green, it flashes, and its check grows in from CHECK_FROM over the number.
	ROW_FLASH_PEAK = 0.45,
	CHECK_FROM = 0.6,
	-- A point on the path: the picked one grows, under the hand one lifts, and one lighting punches.
	NODE_PICKED = 0.14,
	NODE_PERIOD = 0.2,
	NODE_PUNCH = 0.3,
	NODE_PUNCH_PERIOD = 0.3,
	NODE_PUNCH_DAMPING = 0.45,
	NODE_RING_REACH = 18,
	-- The path re-centres as it grows, a new point growing in and a '?' turning into a padlock.
	PATH_PERIOD = 0.42,
	MYSTERY_PERIOD = 0.25,
})

local Map = {}

-- How long the showcase takes to turn to a map: an unlock waits for the picture to land.
Map.SLIDE_SECONDS = Timing.SLIDE

-- The player's best wave on the page's map, on his dark plaque at its top right; '?' on the '?'.
local function bestChip(state: Types.TLobbyState, map: () -> MapsCore.TMap?): Frame
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
		Label({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 21, 0.5, 1),
			Size = UDim2.new(1, -56, 0, Layout.CHIP_TEXT),
			TextSize = Layout.CHIP_TEXT,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			Text = function()
				local shown = map()
				return `BEST WAVE {if shown then Parts.BestOf(state, shown) else "?"}`
			end,
			ZIndex = 8,
		}),
	})
end

-- His dark arrow button at one end of the showcase: `step` -1 points back, 1 on. The glyph leans the way it goes under
-- the hand. The path has ends: past the last map there is no arrow, and it shrinks away. Dead while an unlock holds.
local function arrow(
	state: Types.TLobbyState,
	actions: Types.TLobbyActions,
	pathCount: () -> number,
	step: number
): TextButton
	local hasMap = derive(function(): boolean
		local index = state.PickMap() + step
		return index >= 1 and index <= pathCount()
	end)
	local isLive = derive(function(): boolean
		return hasMap() and not Parts.IsHeld(state)
	end)
	local hand = Hand.React("Operate", isLive)
	local present = Hand.Spring(function(): number
		return if hasMap() then 1 else 0
	end, Timing.ARROW_PERIOD)
	local size = Layout.ARROW
	local x = if step < 0 then Layout.ARROW_INSET + size / 2 else Layout.SHOWCASE_SIZE.X - Layout.ARROW_INSET - size / 2

	return Components.Button({
		Name = if step < 0 then "Back" else "On",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, Layout.SHOWCASE_SIZE.Y / 2),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		ZIndex = 11,
		Interactable = isLive,
		Visible = derive(function(): boolean
			return present() > 0.01
		end),
		Activated = function()
			hand.Commit()
			actions.StepMap(step)
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return hand.Scale() * math.clamp(present(), 0, 1)
			end,
		}),
		Parts.Plaque({
			Name = "Plaque",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 11,
			Components.Brackets(hand.Rise, function()
				return 0.6 - 0.3 * hand.Light()
			end, 12),
			Hand.WashLayer(hand, 12, 2),
			Components.Picture(EIcons.Arrow, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = function()
					return UDim2.new(0.5, math.round(step * 4 * hand.Rise()), 0.5, 0)
				end,
				Size = Components.PictureBox(Layout.ARROW_GLYPH),
				Rotation = if step < 0 then 180 else 0,
				ImageColor3 = Palette.White,
				ZIndex = 13,
			}),
		}),
	}) :: TextButton
end

-- One of what a locked map asks for, on his dark plaque: its picture, its words, and how far along the player is, which
-- becomes a check once it is met; all '?' on the '?'. In an unlock it is ticked off at `stampAt` seconds in: its edge
-- goes green, it flashes, and the check grows in over the number. `slot` 1 is the level, 2 the boss.
local function row(
	state: Types.TLobbyState,
	index: () -> number,
	map: () -> MapsCore.TMap?,
	slot: number,
	stampAt: number
): Frame
	local previous = derive(function(): MapsCore.TMap?
		local shown = map()
		return if shown then MapsCore.PreviousOf(shown) else nil
	end)
	local isAsked = derive(function(): boolean
		local shown = map()
		if not shown then return true end
		if slot == 1 then return shown.UnlockLevel > 0 end
		return shown.UnlockBossKills > 0 and previous() ~= nil
	end)
	local have = derive(function(): number
		if slot == 1 then return state.Level() end
		local before = previous()
		return if before then state.BossKills()[before.Name] or 0 else 0
	end)
	local need = derive(function(): number
		local shown = map()
		if not shown then return math.huge end
		return if slot == 1 then shown.UnlockLevel else shown.UnlockBossKills
	end)
	-- How ticked off it is, 0 to 1: stamped in its turn during an unlock, at once otherwise.
	local ticked = derive(function(): number
		if not map() then return 0 end
		local unlocking = Parts.Unlocking(state, index())
		if unlocking then return Progress(unlocking, stampAt, Unlock.ROW_STAMP) end
		return if have() >= need() then 1 else 0
	end)
	local flash = derive(function(): number
		local t = ticked()
		return if t > 0 and t < 1 then 1 - Motion.Out(t) else 0
	end)
	local text = derive(function(): string
		local shown = map()
		if slot == 1 then return if shown then `REACH LEVEL {need()}` else "REACH LEVEL ?" end
		local before = previous()
		return `BEAT THE BOSS OF {if before then string.upper(before.DisplayName) else "???"}`
	end)
	local size = Layout.ROW
	local windowWidth = Layout.SHOWCASE_SIZE.X - 2 * Layout.EDGE

	return Parts.Plaque({
		Name = `Row{slot}`,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(windowWidth / 2, Layout.ROWS_Y + (slot - 1) * (size.Y + Layout.ROW_GAP)),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = function()
			return Parts.PLAQUE_EDGE:Lerp(Palette.Green, ticked())
		end,
		Visible = isAsked,
		ZIndex = 9,
		create("Frame")({
			Name = "Flash",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Palette.White,
			BorderSizePixel = 0,
			Visible = function()
				return flash() > 0
			end,
			BackgroundTransparency = function()
				return 1 - Timing.ROW_FLASH_PEAK * flash()
			end,
			ZIndex = 12,
			create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
		}),
		Components.Picture(if slot == 1 then EIcons.Rank else EIcons.ZombieKing, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(26, size.Y / 2),
			Size = Components.PictureBox(Layout.ROW_GLYPH),
			ZIndex = 10,
		}),
		Label({
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 50, 0.5, 1),
			Size = UDim2.new(1, -130, 0, Layout.ROW_TEXT),
			TextYAlignment = Enum.TextYAlignment.Center,
			TextSize = Layout.ROW_TEXT,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 10,
			Text = text,
		}),
		-- How far along, until the check takes its place.
		Label({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -18, 0.5, 1),
			Size = UDim2.fromOffset(80, Layout.ROW_TEXT),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextYAlignment = Enum.TextYAlignment.Center,
			FontFace = Font.DisplayBold,
			TextSize = Layout.ROW_TEXT,
			TextColor3 = Palette.Lavender,
			TextTransparency = function()
				return Motion.Out(ticked())
			end,
			ZIndex = 10,
			Text = function()
				if not map() then return "? / ?" end
				return `{math.min(have(), need())} / {need()}`
			end,
		}),
		Components.Picture(EIcons.Check, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -32, 0.5, 0),
			Size = Components.PictureBox(Layout.ROW_CHECK),
			ImageColor3 = Palette.Green,
			ImageTransparency = function()
				return 1 - Motion.Out(ticked())
			end,
			ZIndex = 11,
			create("UIScale")({
				Scale = function()
					return Timing.CHECK_FROM + (1 - Timing.CHECK_FROM) * Motion.Decelerate(ticked())
				end,
			}),
		}),
	})
end

-- What stands over a page's map not open yet: the dark, the padlock (a big '?' on the '?'), and what it asks for. In
-- an unlock the rows are ticked off, the padlock strains and opens, and the dark lifts with the rows on it.
local function veil(
	state: Types.TLobbyState,
	index: () -> number,
	map: () -> MapsCore.TMap?,
	opened: () -> number
): { Instance }
	local windowWidth = Layout.SHOWCASE_SIZE.X - 2 * Layout.EDGE
	local unlocking = function(): number?
		return Parts.Unlocking(state, index())
	end
	-- The padlock stands while the map is shut and until it has blown away in an unlock.
	local isLockUp = derive(function(): boolean
		if not map() then return false end
		local seconds = unlocking()
		if seconds then return seconds < Unlock.LOCK + padlock.SECONDS end
		return opened() < 1
	end)
	local strain = function(): number
		local seconds = unlocking()
		if not seconds then return 0 end
		return Unlock.STRAIN_DEGREES_1 * Motion.Swing(Progress(seconds, Unlock.STRAIN_1, Unlock.STRAIN))
			+ Unlock.STRAIN_DEGREES_2 * Motion.Swing(Progress(seconds, Unlock.STRAIN_2, Unlock.STRAIN))
	end
	local shown = derive(function(): number
		return 1 - opened()
	end)

	return {
		create("Frame")({
			Name = "Veil",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(),
			BackgroundTransparency = function()
				return 1 - 0.65 * shown()
			end,
			BorderSizePixel = 0,
			Visible = derive(function(): boolean
				return shown() > 0
			end),
			ZIndex = 8,
		}),
		Components.FadeGroup("Asks", shown, {
			Size = UDim2.fromScale(1, 1),
			ZIndex = 9,
		}, {
			row(state, index, map, 1, Unlock.ROWS),
			row(state, index, map, 2, Unlock.ROWS + Unlock.ROW_STAGGER),
		}),
		Label({
			Name = "Mystery",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(windowWidth / 2, Layout.LOCK_Y),
			Size = UDim2.fromOffset(200, Layout.MYSTERY_TEXT),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextSize = Layout.MYSTERY_TEXT,
			TextColor3 = Palette.Lavender,
			Visible = derive(function(): boolean
				return map() == nil
			end),
			ZIndex = 10,
			Text = "?",
		}),
		create("Frame")({
			Name = "LockHolder",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Visible = isLockUp,
			ZIndex = 10,
			padlock.Build({
				Unlocking = function(): number
					local seconds = unlocking()
					return if seconds then math.max(seconds - Unlock.LOCK, 0) else 0
				end,
				Turn = strain,
				At = Vector2.new(windowWidth / 2, Layout.LOCK_Y),
				Longest = Layout.LOCK,
				ZIndex = 10,
			}),
		}),
	}
end

-- One map's page filling the window at `x()` px across it: its picture, its best wave, and its veil while it is not
-- open, so all of it slides as one in the carousel.
local function page(state: Types.TLobbyState, pathCount: () -> number, index: () -> number, x: () -> number): Frame
	local map = derive(function(): MapsCore.TMap?
		return Parts.ShownMap(index(), pathCount())
	end)
	local opened = derive(function(): number
		return Parts.Opened(state, index())
	end)

	return create("Frame")({
		Name = "Page",
		Position = function()
			return UDim2.fromOffset(x(), 0)
		end,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parts.Picture(map, Layout.INITIALS_TEXT / 100, {}),
		Parts.Shade(),
		bestChip(state, map),
		veil(state, index, map, opened),
	})
end

local function showcase(
	state: Types.TLobbyState,
	actions: Types.TLobbyActions,
	pathCount: () -> number,
	elapsed: () -> number
): { Instance }
	local size = Layout.SHOWCASE_SIZE
	local window = size - Vector2.new(2 * Layout.EDGE, 2 * Layout.EDGE)
	local center = Layout.SHOWCASE + size / 2
	local dealt = Parts.Dealt(state, elapsed, Timing.SHOWCASE_DELAY)
	local picked = derive(function()
		return Parts.PickedMap(state)
	end)
	local opened = derive(function(): number
		return Parts.Opened(state, state.PickMap())
	end)
	local unlocking = function(): number?
		return Parts.Unlocking(state, state.PickMap())
	end
	-- The picture's colour: his locked grey, warming to the map's own as it comes out from under the veil.
	local accent = spring(function(): Color3
		return Parts.LOCKED:Lerp(Parts.AccentOf(picked()), opened())
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
	-- The release: as the shackle clicks, the picture flashes, throws one ring, pops and catches the light.
	local released = derive(function(): number
		local seconds = unlocking()
		return if seconds then seconds - Unlock.RELEASE else math.huge
	end)
	local flash = derive(function(): number
		return Progress(released(), 0, Unlock.FLASH)
	end)
	local ringed = derive(function(): number
		return Progress(released(), 0, Unlock.RING)
	end)
	local unlockSwept = derive(function(): number
		return Progress(released(), 0, Timing.SHEEN)
	end)
	local pop, strikePop = Hand.Kick(Timing.POP_PERIOD, Timing.POP_DAMPING)
	Parts.OnChange(
		derive(function(): boolean
			return released() >= 0 and released() < Unlock.FLASH
		end),
		function(isReleasing: boolean)
			if isReleasing then strikePop(Unlock.POP) end
		end
	)
	local shownName = derive(function(): string
		local shown = Parts.ShownMap(state.PickMap(), pathCount())
		return if shown then string.upper(shown.DisplayName) else "???"
	end)

	local card = Components.Card({
		Accent = accent,
		Tint = 0.4,
		-- Its glow flares with the flash.
		GlowTransparency = function()
			local t = flash()
			return if t > 0 then 0.72 - 0.4 * (1 - t) else 0.72
		end,
		Tall = true,
		Brackets = true,
	}, {
		Name = "Showcase",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center.X, center.Y),
		Size = UDim2.fromOffset(size.X, size.Y),
		ZIndex = 3,
		create("UIScale")({
			Scale = function()
				return (0.9 + 0.1 * dealt()) * (1 + pop())
			end,
		}),
		create("Frame")({
			Name = "Window",
			Position = UDim2.fromOffset(Layout.EDGE, Layout.EDGE),
			Size = UDim2.fromOffset(window.X, window.Y),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 4,
			page(state, pathCount, state.MapFrom, goingX),
			page(state, pathCount, state.PickMap, comingX),
			-- Over the pages, so it follows them a beat later: dimmed, as under the veil, while the map is not open.
			Label({
				Name = "Name",
				AnchorPoint = Vector2.new(0, 1),
				Position = function()
					return UDim2.new(0, Layout.INSET + nameX(), 1, -Layout.INSET + 6)
				end,
				Size = UDim2.fromOffset(window.X - 2 * Layout.INSET, Layout.NAME_TEXT),
				TextSize = Layout.NAME_TEXT,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextColor3 = function()
					return Parts.SHUT_NAME:Lerp(Palette.White, opened())
				end,
				TextTransparency = function()
					return 1 - Motion.Out(named())
				end,
				ZIndex = 7,
				Text = shownName,
			}),
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				Visible = derive(function(): boolean
					local t = flash()
					return t > 0 and t < 1
				end),
				BackgroundTransparency = function()
					return 1 - Unlock.FLASH_PEAK * (1 - Motion.Out(flash()))
				end,
				ZIndex = 14,
			}),
		}),
		Components.Sheen(function(): number
			return math.min(swept(), openSwept(), unlockSwept())
		end, 15),
		arrow(state, actions, pathCount, -1),
		arrow(state, actions, pathCount, 1),
		-- NEW on the map opened this visit, from the moment its unlock lands.
		Ribbon.Build({
			Corner = "TopLeft",
			Text = "NEW",
			Color = Palette.Pink,
			IsShown = function()
				if state.UnlockMap() ~= state.PickMap() then return false end
				local seconds = unlocking()
				return seconds == nil or seconds >= Unlock.RIBBON
			end,
			Along = Layout.RIBBON_ALONG,
			Thickness = Layout.RIBBON_THICKNESS,
			TextSize = Layout.RIBBON_TEXT,
			ZIndex = 16,
		}),
	})

	-- One ring off the showcase as it comes out, growing by pixels at one weight in the map's colour.
	local ring = create("Frame")({
		Name = "UnlockRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center.X, center.Y),
		Size = function()
			local grow = math.round(Unlock.RING_REACH * Motion.Decelerate(ringed()))
			return UDim2.fromOffset(size.X + 2 * grow, size.Y + 2 * grow)
		end,
		BackgroundTransparency = 1,
		Visible = derive(function(): boolean
			local t = ringed()
			return t > 0 and t < 1
		end),
		ZIndex = 2,
		create("UICorner")({ CornerRadius = UDim.new(0, 6) }),
		create("UIStroke")({
			Color = function()
				return Parts.AccentOf(picked())
			end,
			Thickness = 3,
			Transparency = ringed,
		}),
	})

	return { card, ring }
end

-- The middle of point `index` of a path of `count`, in px from the panel's left: the path is centred under the showcase.
local function pointX(index: number, count: number): number
	return Layout.SHOWCASE.X + Layout.SHOWCASE_SIZE.X / 2 + (index - (count + 1) / 2) * Layout.PATH_STEP
end

-- How far map `index`'s point is lit and the track into it has run, 0 to 1 each: as it opens, or in its unlock on
-- their beats. Nothing for the '?' past the last map.
local function pathShares(state: Types.TLobbyState, index: number): (() -> number, () -> number)
	local run = derive(function(): number
		local seconds = Parts.Unlocking(state, index)
		if seconds then return Parts.Standard(Progress(seconds, Unlock.TRACK, Unlock.TRACK_RUN)) end
		return Parts.Opened(state, index)
	end)
	local lit = derive(function(): number
		local seconds = Parts.Unlocking(state, index)
		if seconds then return if seconds >= Unlock.TRACK + Unlock.TRACK_RUN then 1 else 0 end
		return Parts.Opened(state, index)
	end)

	return lit, run
end

-- Where a point is on the path and how much of it is there, 0 to 1: it glides as the path re-centres and grows in as
-- the path reaches it.
type TPlace = { X: () -> number, Present: () -> number }

-- The track from point `index - 1` to point `index`: his dark bar track, filled in the map's colour as far as it has
-- run, drawn out as both its ends are there.
local function track(index: number, from: TPlace, to: TPlace, run: () -> number, dealt: () -> number): Frame
	local map = MapsCore.LIST[index]
	local left = function(): number
		return from.X() + Layout.NODE / 2 + Layout.TRACK_GAP
	end
	local length = derive(function(): number
		local full = to.X() - Layout.NODE / 2 - Layout.TRACK_GAP - left()
		return math.max(full * dealt() * math.clamp(math.min(from.Present(), to.Present()), 0, 1), 0)
	end)

	return create("Frame")({
		Name = `Track{index}`,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = function()
			return UDim2.fromOffset(math.round(left()), Layout.PATH_Y)
		end,
		Size = function()
			return UDim2.fromOffset(math.round(length()), Layout.TRACK)
		end,
		BackgroundColor3 = Parts.BAR_TRACK,
		BorderSizePixel = 0,
		Visible = derive(function(): boolean
			return length() >= 1
		end),
		ZIndex = 4,
		create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
		create("Frame")({
			Name = "Fill",
			Size = function()
				return UDim2.fromOffset(math.round(length() * run()), Layout.TRACK)
			end,
			BackgroundColor3 = if map then Parts.AccentOf(map) else Parts.LOCKED,
			BorderSizePixel = 0,
			Visible = derive(function(): boolean
				return run() > 0
			end),
			ZIndex = 5,
			create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
		}),
	})
end

-- Point `index` on the path: his dark plaque with the map's number, edged in its colour once it is open, the padlock
-- while it is not, or '?' at the path's end. The picked one grows and closes its brackets round it. A button: it picks
-- its map. Lighting in an unlock it punches and throws one ring, and so does a '?' turning into the next map.
local function point(
	state: Types.TLobbyState,
	actions: Types.TLobbyActions,
	pathCount: () -> number,
	index: number,
	place: TPlace,
	lit: () -> number,
	dealt: () -> number
): { Instance }
	local map = MapsCore.LIST[index]
	local accent = if map then Parts.AccentOf(map) else Parts.LOCKED
	local isPicked = derive(function(): boolean
		return state.PickMap() == index
	end)
	local isMystery = derive(function(): boolean
		return index >= pathCount()
	end)
	local isLive = derive(function(): boolean
		return not isPicked() and not Parts.IsHeld(state) and place.Present() > 0.5
	end)
	local hand = Hand.React("Take", isLive)
	local grown = Hand.Spring(function(): number
		return if isPicked() then 1 else 0
	end, Timing.NODE_PERIOD)
	-- 1 while it is the '?', crossing to the padlock as the path reaches past it.
	local mystery = Hand.Spring(function(): number
		return if isMystery() then 1 else 0
	end, Timing.MYSTERY_PERIOD)
	local punch, strikePunch = Hand.Kick(Timing.NODE_PUNCH_PERIOD, Timing.NODE_PUNCH_DAMPING)
	local litAt = vide.source(-math.huge)
	local function light()
		strikePunch(Timing.NODE_PUNCH)
		litAt(os.clock())
	end
	Parts.OnChange(lit, function(current: number, last: number)
		if last < 1 and current >= 1 and Parts.Unlocking(state, index) then light() end
	end)
	Parts.OnChange(isMystery, function(current: boolean)
		if not current and Parts.Unlocking(state, state.UnlockMap()) then light() end
	end)
	local ringed = Parts.Since(state, litAt, Unlock.NODE_RING)
	local present = function(): number
		return math.clamp(place.Present(), 0, 1)
	end

	local button = Components.Button({
		Name = `Point{index}`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(math.round(place.X()), Layout.PATH_Y)
		end,
		Size = UDim2.fromOffset(Layout.NODE_HIT.X, Layout.NODE_HIT.Y),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Interactable = isLive,
		Visible = derive(function(): boolean
			return place.Present() > 0.01
		end),
		Activated = function()
			hand.Commit()
			actions.PickMap(index)
		end,
		hand.Events,
		Parts.Plaque({
			Name = "Plaque",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(Layout.NODE, Layout.NODE),
			BackgroundColor3 = function()
				return Parts.PLAQUE_EDGE:Lerp(accent, lit())
			end,
			ZIndex = 5,
			create("UIScale")({
				Scale = function()
					return dealt() * present() * (hand.Scale() + Timing.NODE_PICKED * grown() + punch())
				end,
			}),
			Components.Brackets(hand.Rise, function()
				return 0.6 - 0.3 * hand.Light()
			end, 8, isPicked),
			Hand.WashLayer(hand, 6, 2),
			Label({
				Name = "Number",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, 1),
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextSize = Layout.NODE_TEXT,
				TextTransparency = function()
					return 1 - lit()
				end,
				ZIndex = 7,
				Text = tostring(index),
			}),
			Label({
				Name = "Mystery",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, 1),
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextSize = Layout.NODE_TEXT,
				TextColor3 = Palette.Lavender,
				TextTransparency = function()
					return 1 - math.clamp(mystery(), 0, 1)
				end,
				ZIndex = 7,
				Text = "?",
			}),
			Components.Picture(EIcons.Lock, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = Components.PictureBox(Layout.NODE_GLYPH),
				ImageTransparency = function()
					return 1 - (1 - lit()) * (1 - math.clamp(mystery(), 0, 1))
				end,
				Visible = derive(function(): boolean
					return lit() < 1 and mystery() < 0.99
				end),
				ZIndex = 7,
			}),
		}),
	})

	local ring = create("Frame")({
		Name = `PointRing{index}`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(math.round(place.X()), Layout.PATH_Y)
		end,
		Size = function()
			local grow = math.round(Timing.NODE_RING_REACH * Motion.Decelerate(ringed()))
			return UDim2.fromOffset(Layout.NODE + 2 * grow, Layout.NODE + 2 * grow)
		end,
		BackgroundTransparency = 1,
		Visible = derive(function(): boolean
			local t = ringed()
			return t > 0 and t < 1
		end),
		ZIndex = 4,
		create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
		create("UIStroke")({
			Color = accent,
			Thickness = 2,
			Transparency = ringed,
		}),
	})

	return { button, ring }
end

-- The path under the showcase, in the order the maps are played: a point for every map reached, the next one and the
-- '?' (one more than there are maps, so the '?' is there past the last), a track between each, dealt in from the
-- first. As it grows it re-centres, the new point growing in at its end.
local function path(
	state: Types.TLobbyState,
	actions: Types.TLobbyActions,
	count: () -> number,
	elapsed: () -> number
): { any }
	local pieces = {}
	local places: { TPlace } = {}
	for index = 1, #MapsCore.LIST + 1 do
		local dealt = Parts.Dealt(state, elapsed, Timing.PATH_DELAY + Timing.PATH_STAGGER * (index - 1))
		local lit, run = pathShares(state, index)
		places[index] = {
			X = Hand.Spring(function(): number
				return pointX(math.min(index, count()), count())
			end, Timing.PATH_PERIOD),
			Present = Hand.Spring(function(): number
				return if index <= count() then 1 else 0
			end, Timing.PATH_PERIOD),
		}
		if index > 1 then pieces[#pieces + 1] = track(index, places[index - 1], places[index], run, dealt) end
		pieces[#pieces + 1] = point(state, actions, count, index, places[index], lit, dealt)
	end

	return pieces
end

function Map.Build(state: Types.TLobbyState, actions: Types.TLobbyActions, elapsed: () -> number): { any }
	-- Worked out once for the showcase and the path: every page, arrow and point reads it.
	local pathCount = derive(function(): number
		return Parts.PathCount(state)
	end)

	return {
		Parts.Header({
			At = Layout.HEADER,
			Width = Layout.SHOWCASE_SIZE.X,
			Picture = EIcons.Star,
			Word = "MAP",
		}),
		showcase(state, actions, pathCount, elapsed),
		path(state, actions, pathCount, elapsed),
	}
end

return Map
