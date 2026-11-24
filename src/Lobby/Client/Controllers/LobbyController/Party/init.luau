--!nonstrict
-- The host's party screen on a 1920 x 1080 (GDD 3: form a party, select an eligible map), in the lobby screens' look:
-- the lobby dimmed, his panel under the spins' header (the pink glyph, CREATE PARTY, the time left to pick), the map
-- (Map) and the choices beside it (Picks), the party read back in chips (CONFIG), and CREATE. The panel rises in and its
-- pieces are dealt onto it; the pad's EXIT (Exit, under it) sinks it away, and CREATE sends it off upward with a flash
-- and a ring. The queue
-- that follows (Queue) and the board over each pad (Board) are its siblings.
-- Nothing is decided here: CREATE sends the picks and the server checks every one of them again.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local MapsCore = require(ReplicatedStorage.GlobalShared.Core.MapsCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local Map = require(script.Map)
local Parts = require(script.Parts)
local Picks = require(script.Picks)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local source = vide.source
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
local Timing = Parts.Timing
local Label = Parts.Label

-- Px at 1080, from the panel's top left unless said otherwise.
local Layout = table.freeze({
	DESIGN = Vector2.new(1920, 1080),
	-- The panel, from the screen's top left.
	PANEL = Vector2.new(310, 174),
	SIZE = Vector2.new(1300, 732),
	-- The spins' header: the glyph's middle and longer side, the title, the rule under it all.
	GLYPH = Vector2.new(48.5, 48),
	GLYPH_SIZE = 30,
	TITLE = Vector2.new(81, 26),
	TITLE_TEXT = 44,
	-- The time left to pick, as the daily rewards' streak: its right end (where the rule ends), middle and letter
	-- height, and the stopwatch just left of it.
	CLOCK_RIGHT = 1269,
	CLOCK_Y = 48,
	CLOCK_TEXT = 20,
	STOPWATCH_GLYPH = 22,
	STOPWATCH_GAP = 10,
	RULE = Vector2.new(31, 96),
	RULE_WIDTH = 1238,
	-- The rule over the footer, the party read back and CREATE.
	FOOTER_RULE = 600,
	CONFIG_LABEL = Vector2.new(31, 620),
	CONFIG_LABEL_TEXT = 16,
	CHIPS = Vector2.new(31, 646),
	CHIP_HEIGHT = 44,
	CHIP_TEXT = 18,
	CHIP_PAD = 16,
	CHIP_GAP = 10,
	CREATE = Vector2.new(887, 622),
	CREATE_SIZE = Vector2.new(382, 82),
	CREATE_TEXT = 31,
	CREATE_TRACKING = 3,
	CREATE_ARROW = 24,
	-- Room round the panel inside the group that fades it, for the glow, the brackets and CREATE's ring.
	MARGIN = 120,
})

local Gesture = table.freeze({
	DIM = 0.3,
	TITLE_DELAY = 0.06,
	TITLE = 0.32,
	TITLE_SLIDE = 22,
	RULE_DELAY = 0.1,
	RULE = 0.45,
	CHIPS_DELAY = 0.32,
	CHIPS_STAGGER = 0.04,
	CREATE_DELAY = 0.36,
	-- A chip whose word changes punches and flashes.
	CHIP_PUNCH = 0.14,
	CHIP_PERIOD = 0.3,
	CHIP_DAMPING = 0.5,
	CHIP_FLASH = 0.35,
	CHIP_FLASH_PEAK = 0.3,
	-- CREATE: its idle light, how far it goes in while the server is asked, its share of a button's reach (it is wide),
	-- the flash and the one ring as it goes through, the shake of a refusal.
	SHEEN = 0.7,
	CREATE_REACH = 1 / 2,
	CREATE_WIND = 0.03,
	FLASH = 0.35,
	FLASH_PEAK = 0.65,
	RING = 0.5,
	RING_GROW = 70,
	REFUSED = 0.35,
	REFUSED_SHAKE = 7,
	PENDING = 1.5,
	-- The time left to pick: in its last seconds every second punches it and warms it to pink, and the last few tick.
	HURRY_SECONDS = 10,
	TICK_SECONDS = 5,
	CLOCK_PUNCH = 0.22,
	CLOCK_PERIOD = 0.3,
	CLOCK_DAMPING = 0.5,
	-- A shut this soon after CREATE is the party going up, not the host walking off.
	LAUNCH_WINDOW = 5,
})

local Party = {}

-- How long the screen keeps the clock ticking after it opens or shuts, or after a pick.
Party.SETTLE_SECONDS = Timing.SETTLED
-- How long the light takes to cross CREATE, how long after the open it first crosses it, and how often after that.
Party.SHEEN_SECONDS = Gesture.SHEEN
Party.FIRST_CALL_SECONDS = 0.5
Party.CALL_SECONDS = 2.6

-- His lavender rule at `y`, `width()` px long, a whole screen pixel tall at any scale: one design px under 1080 thins
-- to nothing.
local function rule(state: Types.TLobbyState, name: string, y: number, width: () -> number): Frame
	return create("Frame")({
		Name = name,
		Position = UDim2.fromOffset(Layout.RULE.X, y),
		Size = function()
			return UDim2.fromOffset(math.round(width()), math.max(1, 1 / state.PageScale()))
		end,
		BackgroundColor3 = Parts.RULE,
		BackgroundTransparency = Parts.RULE_TRANSPARENCY,
		BorderSizePixel = 0,
		ZIndex = 4,
	})
end

-- The time the host has left to pick (PadsCore.CHOOSE_SECONDS, run by the server), as the quests' reset clock.
-- Right-aligned at CLOCK_RIGHT but punched from its centre: an unseen copy gives the holder the text's width, and the
-- seen label hangs centred off a zero-size pin, so its swell never resizes the holder.
local function clock(state: Types.TLobbyState): Frame
	local seconds = derive(function(): number
		local pad = state.Pads[state.CurrentPad()]
		return if pad then pad.Seconds() else -1
	end)
	local punch, strikePunch = Hand.Kick(Gesture.CLOCK_PERIOD, Gesture.CLOCK_DAMPING)
	Parts.OnChange(seconds, function(current: number)
		if current < 0 or current > Gesture.HURRY_SECONDS then return end
		strikePunch(Gesture.CLOCK_PUNCH)
		if current > 0 and current <= Gesture.TICK_SECONDS then SoundsCore.PlayUINamed("UI", "CountdownTick") end
	end)
	local color = derive(function(): Color3
		local current = seconds()
		if current < 0 or current > Gesture.HURRY_SECONDS then return Palette.Gold end
		return Palette.Pink:Lerp(Palette.Gold, current / Gesture.HURRY_SECONDS)
	end)
	local text = derive(function(): string
		return `CLOSES IN {math.max(seconds(), 0)}s`
	end)

	return create("Frame")({
		Name = "Clock",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromOffset(Layout.CLOCK_RIGHT, Layout.CLOCK_Y),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, Layout.CLOCK_TEXT),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Visible = function()
			return seconds() >= 0
		end,
		Label({
			Name = "Width",
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, Layout.CLOCK_TEXT),
			TextSize = Layout.CLOCK_TEXT,
			TextTransparency = 1,
			Text = text,
		}),
		create("Frame")({
			Name = "Pin",
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(),
			BackgroundTransparency = 1,
			Label({
				Name = "Text",
				AnchorPoint = Vector2.new(0.5, 0.5),
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Layout.CLOCK_TEXT),
				TextSize = Layout.CLOCK_TEXT,
				TextColor3 = color,
				Text = text,
				create("UIScale")({
					Scale = function()
						return 1 + punch()
					end,
				}),
				Components.Picture(EIcons.Stopwatch, {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(0, -Layout.STOPWATCH_GAP, 0.5, 0),
					Size = Components.PictureBox(Layout.STOPWATCH_GLYPH),
					ZIndex = 4,
				}),
			}),
		}),
	})
end

local function header(state: Types.TLobbyState, elapsed: () -> number): { Instance }
	local away = derive(function(): number
		if not state.IsChoosing() then return 0 end
		return 1 - Motion.Decelerate(Progress(elapsed(), Gesture.TITLE_DELAY, Gesture.TITLE))
	end)
	local drawn = derive(function(): number
		if not state.IsChoosing() then return 1 end
		return Motion.Decelerate(Progress(elapsed(), Gesture.RULE_DELAY, Gesture.RULE))
	end)

	return {
		create("Frame")({
			Name = "Title",
			Position = function()
				return UDim2.fromOffset(-math.round(Gesture.TITLE_SLIDE * away()), 0)
			end,
			Size = UDim2.fromOffset(600, Layout.RULE.Y),
			BackgroundTransparency = 1,
			ZIndex = 4,
			Components.Picture(EIcons.Friends, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(Layout.GLYPH.X, Layout.GLYPH.Y),
				Size = Components.PictureBox(Layout.GLYPH_SIZE),
				ZIndex = 4,
			}),
			Label({
				Position = UDim2.fromOffset(Layout.TITLE.X, Layout.TITLE.Y),
				Size = UDim2.fromOffset(520, Layout.TITLE_TEXT),
				TextSize = Layout.TITLE_TEXT,
				Text = "CREATE PARTY",
			}),
		}),
		clock(state),
		rule(state, "Rule", Layout.RULE.Y, function()
			return Layout.RULE_WIDTH * drawn()
		end),
	}
end

-- One pick read back on a plaque: it punches and flashes as its word changes. The row lays out a slot sized by a hidden
-- copy of the word, and the plaque stands in it by its middle, so it grows and punches from there.
local function chip(state: Types.TLobbyState, elapsed: () -> number, order: number, color: any, text: () -> string)
	local dealt = Parts.Dealt(state, elapsed, Gesture.CHIPS_DELAY + Gesture.CHIPS_STAGGER * (order - 1))
	local punch, strikePunch = Hand.Kick(Gesture.CHIP_PERIOD, Gesture.CHIP_DAMPING)
	local changedAt = source(-math.huge)
	local flash = Parts.Since(state, changedAt, Gesture.CHIP_FLASH)
	local word = derive(text)
	Parts.OnChange(word, function()
		strikePunch(Gesture.CHIP_PUNCH)
		changedAt(os.clock())
	end)

	-- The word's width as drawn, read off a hidden copy: a slot sized by children sized by it would never settle.
	local wordWidth = source(0)

	return create("Frame")({
		Name = `Chip{order}`,
		LayoutOrder = order,
		Size = function()
			return UDim2.fromOffset(wordWidth() + 2 * Layout.CHIP_PAD, Layout.CHIP_HEIGHT)
		end,
		BackgroundTransparency = 1,
		ZIndex = 4,
		Label({
			Name = "Measure",
			Size = UDim2.fromOffset(600, Layout.CHIP_HEIGHT),
			TextSize = Layout.CHIP_TEXT,
			TextTransparency = 1,
			Text = word,
			vide.changed("TextBounds", function(bounds: Vector2)
				wordWidth(math.ceil(bounds.X))
			end),
		}),
		Parts.Plaque({
			Name = "Plaque",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 4,
			create("UIScale")({
				Scale = function()
					return dealt() * (1 + punch())
				end,
			}),
			create("Frame")({
				Name = "Flash",
				Position = UDim2.fromOffset(2, 2),
				Size = UDim2.new(1, -4, 1, -4),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				Visible = function()
					return flash() < 1
				end,
				BackgroundTransparency = function()
					return 1 - Gesture.CHIP_FLASH_PEAK * (1 - flash())
				end,
				ZIndex = 5,
			}),
			Label({
				Name = "Word",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextSize = Layout.CHIP_TEXT,
				TextColor3 = color,
				ZIndex = 6,
				Text = word,
				create("UIPadding")({ PaddingTop = UDim.new(0, 2) }),
			}),
		}),
	})
end

local function readBack(state: Types.TLobbyState, elapsed: () -> number): { Instance }
	local function picked(): MapsCore.TMap
		return Parts.PickedMap(state)
	end

	return {
		Label({
			Name = "ConfigLabel",
			Position = UDim2.fromOffset(Layout.CONFIG_LABEL.X, Layout.CONFIG_LABEL.Y),
			Size = UDim2.fromOffset(400, Layout.CONFIG_LABEL_TEXT),
			FontFace = Font.DisplayBold,
			TextSize = Layout.CONFIG_LABEL_TEXT,
			TextColor3 = Palette.Lavender,
			Text = "CONFIG",
		}),
		create("Frame")({
			Name = "Chips",
			Position = UDim2.fromOffset(Layout.CHIPS.X, Layout.CHIPS.Y),
			Size = UDim2.fromOffset(Layout.CREATE.X - Layout.CHIPS.X - 20, Layout.CHIP_HEIGHT),
			BackgroundTransparency = 1,
			ZIndex = 4,
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, Layout.CHIP_GAP),
			}),
			chip(state, elapsed, 1, function()
				return Parts.AccentOf(picked())
			end, function()
				return string.upper(picked().DisplayName)
			end),
			chip(state, elapsed, 2, function()
				return Parts.DIFFICULTY_COLORS[state.PickDifficulty()] or Palette.Green
			end, function()
				return string.upper(state.PickDifficulty())
			end),
			chip(state, elapsed, 3, Palette.White, function()
				return Parts.PARTY_NAMES[state.PickPlayers()] or `{state.PickPlayers()} PLAYERS`
			end),
			chip(state, elapsed, 4, Palette.White, function()
				return if state.PickFriendsOnly() then "FRIENDS" else "PUBLIC"
			end),
		}),
	}
end

-- CREATE: his green slab, grey on a locked map. Its light crosses it every few seconds while the screen waits on it; it
-- goes in while the server is asked, and flashes and throws one ring as the press goes through.
local function createButton(state: Types.TLobbyState, actions: Types.TLobbyActions, elapsed: () -> number): { Instance }
	local isLive = derive(function(): boolean
		return not Parts.IsLocked(state, Parts.PickedMap(state))
	end)
	local hand = Hand.React("Operate", isLive)
	local dealt = Parts.Dealt(state, elapsed, Gesture.CREATE_DELAY)
	-- Asked and not answered yet. The server answers by moving the pad on, so a press it turned down is let go after a
	-- while rather than holding CREATE in.
	local isPending = derive(function(): boolean
		local at = state.CreatedAt()
		return state.IsChoosing() and at >= state.ChoosingAt() and state.Now() - at < Gesture.PENDING
	end)
	local idle = derive(function(): number
		if not isLive() or isPending() then return 1 end
		return Progress(state.Now(), state.PartyCallAt(), Gesture.SHEEN)
	end)
	local flash = Parts.Since(state, state.CreatedAt, Gesture.FLASH)
	local ringed = Parts.Since(state, state.CreatedAt, Gesture.RING)
	local refused = Parts.Since(state, state.PartyRefusedAt, Gesture.REFUSED)
	local shake = derive(function(): number
		return math.round(Gesture.REFUSED_SHAKE * Motion.Shake(refused(), state.PartyRefusedAt()))
	end)
	local textColor = function(): Color3
		return if isLive() then Palette.White else Palette.Lavender
	end
	local size = Layout.CREATE_SIZE
	local center = Layout.CREATE + size / 2

	local button = Components.Button({
		Name = "Create",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(center.X + shake(), center.Y)
		end,
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Activated = function()
			if isPending() then return end
			hand.Commit()
			actions.StartParty()
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				local handScale = 1 + (hand.Scale() - 1) * Gesture.CREATE_REACH
				local wind = if isPending() then 1 - Gesture.CREATE_WIND else 1
				return dealt() * handScale * wind
			end,
		}),
		Components.Slab({
			Kind = function()
				return if isLive() then "Go" else "Off"
			end,
			Marks = true,
			Brackets = true,
			GlowTransparency = function()
				return 0.6 - 0.3 * hand.Light()
			end,
		}, {
			Name = "Slab",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 3, 3),
			Components.Sheen(Hand.Sheen(hand, idle), 3),
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				Visible = function()
					return flash() < 1
				end,
				BackgroundTransparency = function()
					return 1 - Gesture.FLASH_PEAK * (1 - Motion.Out(flash()))
				end,
				ZIndex = 5,
				create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
			}),
			create("Frame")({
				Name = "Word",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Layout.CREATE_TEXT),
				BackgroundTransparency = 1,
				ZIndex = 6,
				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 14),
				}),
				Components.Picture(EIcons.Lock, {
					LayoutOrder = 1,
					Size = Components.PictureBox(Layout.CREATE_ARROW),
					Visible = function()
						return not isLive()
					end,
					ZIndex = 6,
				}),
				Components.Tracked("CREATE", Layout.CREATE_TEXT, Layout.CREATE_TRACKING, Font.Display, {
					LayoutOrder = 2,
					Color = textColor,
					ZIndex = 6,
				}),
				-- The arrow leans on toward where the party goes under the hand.
				create("Frame")({
					LayoutOrder = 3,
					Size = UDim2.fromOffset(Layout.CREATE_ARROW + 8, Layout.CREATE_ARROW),
					BackgroundTransparency = 1,
					Visible = isLive,
					Components.Picture(EIcons.Arrow, {
						AnchorPoint = Vector2.new(0, 0.5),
						Position = function()
							return UDim2.new(0, math.round(6 * hand.Rise()), 0.5, 0)
						end,
						Size = Components.PictureBox(Layout.CREATE_ARROW),
						ImageColor3 = textColor,
						ZIndex = 6,
					}),
				}),
			}),
		}),
	}) :: TextButton

	-- One ring, growing off the slab by pixels at one weight as the press goes through.
	local ring = create("Frame")({
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center.X, center.Y),
		Size = function()
			local grow = math.round(Gesture.RING_GROW * Motion.Decelerate(ringed()))
			return UDim2.fromOffset(size.X + 2 * grow, size.Y + 2 * grow)
		end,
		BackgroundTransparency = 1,
		ZIndex = 3,
		create("UICorner")({ CornerRadius = UDim.new(0, 8) }),
		create("UIStroke")({
			Color = Palette.Green,
			Thickness = 3,
			Transparency = ringed,
		}),
	})

	return { button, ring }
end

function Party.Build(state: Types.TLobbyState, actions: Types.TLobbyActions): ScreenGui
	local elapsed = Parts.Elapsed(state)
	-- Shut by the party going up rather than by the host leaving: it lifts away rather than sinking.
	local isLaunch = derive(function(): boolean
		if state.IsChoosing() then return false end
		local since = state.ChoosingAt() - state.CreatedAt()
		return since >= 0 and since < Gesture.LAUNCH_WINDOW
	end)
	local exitSeconds = function(): number
		return if isLaunch() then Timing.LAUNCH else Timing.CLOSE
	end
	-- How much of the screen is there, 0 to 1: its fade, on the clock both ways.
	local shown = derive(function(): number
		if state.IsChoosing() then return Motion.Out(Progress(elapsed(), 0, Timing.FADE)) end
		return 1 - Progress(elapsed(), 0, exitSeconds())
	end)
	-- How far under its place the panel is, in px (over it as it lifts away).
	local drop = derive(function(): number
		if state.IsChoosing() then return Timing.RISE * (1 - Motion.Decelerate(Progress(elapsed(), 0, Timing.OPEN))) end
		local t = Motion.Accelerate(Progress(elapsed(), 0, exitSeconds()))
		return if isLaunch() then -Timing.LAUNCH_RISE * t else Timing.SINK * t
	end)
	local isDrawn = derive(function(): boolean
		return shown() > 0
	end)
	local margin = Layout.MARGIN

	return create("ScreenGui")({
		Name = "Party",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		-- Over the lobby's screen, under the Gems counter and the settings.
		DisplayOrder = 5,
		Enabled = isDrawn,
		create("Frame")({
			Name = "Root",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(Layout.DESIGN.X, Layout.DESIGN.Y),
			BackgroundTransparency = 1,
			create("UIScale")({ Scale = state.PageScale }),
			-- Past the screen's edges whatever its shape. A click on it does nothing: leaving the pad is the pad's EXIT's.
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
				BackgroundTransparency = function()
					return 1 - Gesture.DIM * shown()
				end,
			}),
			create("Frame")({
				Name = "Window",
				Position = function()
					return UDim2.fromOffset(Layout.PANEL.X, Layout.PANEL.Y + math.round(drop()))
				end,
				Size = UDim2.fromOffset(Layout.SIZE.X, Layout.SIZE.Y),
				BackgroundTransparency = 1,
				ZIndex = 2,
				Components.FadeGroup("Chrome", shown, {
					Position = UDim2.fromOffset(-margin, -margin),
					Size = UDim2.new(1, 2 * margin, 1, 2 * margin),
				}, {
					Components.Panel({ Brackets = true, TexturePhase = Vector2.zero, Wide = true, Tall = true }, {
						Name = "Panel",
						Position = UDim2.fromOffset(margin, margin),
						Size = UDim2.new(1, -2 * margin, 1, -2 * margin),
						header(state, elapsed),
						Map.Build(state, actions, elapsed),
						Picks.Build(state, actions, elapsed),
						rule(state, "FooterRule", Layout.FOOTER_RULE, function()
							return Layout.RULE_WIDTH
						end),
						readBack(state, elapsed),
						createButton(state, actions, elapsed),
					}),
				}),
			}),
		}),
	})
end

return Party
