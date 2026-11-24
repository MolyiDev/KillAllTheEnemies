--!nonstrict
-- The Mutation Lab on his 1920 x 1080 (UIMatt.md, Monster Mutation): the lobby dimmed, his panel with the MUTATE |
-- POTIONS tabs, the brews left, the page on show (Mutate, Potions) and EXIT. The HUD's pills stay up over it. Pieces
-- arrive staged by what the screen is for: the panel and its page, the tabs, EXIT last.
--
-- The panel is raised to just under the top bar, its bottom staying put: everything on it, and what flies and shows
-- over it, is laid in his rects in a layer raised with its top (`lift`); the pages keep their bottom rows in place and
-- grow into the room themselves (Mutate, Potions).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Notice = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Notice)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Brew = require(script.Parent.Brew)
local Flight = require(script.Parent.Flight)
local Mutate = require(script.Parent.Mutate)
local Parts = require(script.Parent.Parts)
local Potions = require(script.Parent.Potions)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)
local ERarities = require(ReplicatedStorage.Types.Enums.ERarities)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Progress = Motion.Progress
local Label = Parts.Label

-- His drawn rects in px at 1080, from the screen's top left. The tabs are his size; the second stands 24 off the first
-- (the bracket check for a 240 px Take tab), where he set them 13 apart.
local Layout = table.freeze({
	DESIGN = Vector2.new(1920, 1080),
	TABS = { Vector2.new(328, 194), Vector2.new(592, 194) },
	TAB_SIZE = Vector2.new(240, 60),
	TAB_TEXT = 26,
	TAB_GLYPH = 30,
	TAB_GAP = 12,
	TAB_BRACKET_LENGTH = 14,
	BADGE = 30,
	BREWS_RIGHT = 1592,
	BREWS_Y = 213,
	BREWS_TEXT = 21,
	BREWS_GLYPH = 26,
	RULE_Y = 278,
	TOAST_Y = 146,
	TOAST_TEXT = 22,
	-- The souls a dissolve gave back, rising over the MUTATE tab.
	GAINED_TEXT = 24,
	GAINED_RISE = 34,
})

local Timing = table.freeze({
	-- His lobby screens dim the world this much (UIMatt.md section 2: 0.7 transparent).
	DIM = 0.3,
	PANEL_DELAY = 0,
	PANEL_RISE = 30,
	TABS_DELAY = 0.08,
	TABS_STAGGER = 0.05,
	TABS_DROP = 20,
	EXIT_DELAY = 0.28,
	-- The page going fades this fast; the page coming deals in on its own (Parts.Dealt).
	PAGE_PERIOD = 0.12,
	PICK_PERIOD = 0.22,
	PICK_DAMPING = 0.75,
	-- A refusal's line over the panel, and how long it stays.
	TOAST = 2.4,
	-- A Legendary's or Mythic's landing lights the whole view in its colour.
	SCREEN_FLASH = 0.6,
	-- How long the souls given back stay over the MUTATE tab.
	GAINED = 1.6,
})

local Screen = {}

Screen.DESIGN = Layout.DESIGN

-- One tab: his dark plate under the hand, its word and glyph over the glider. Returns its pieces and its hand's scale,
-- for the glider to ride.
local function tab(
	state: Types.TLabState,
	actions: Types.TLabActions,
	elapsed: () -> number,
	index: number
): ({ Instance }, () -> number)
	local drop = Parts.Away(state, elapsed, Timing.TABS_DELAY + Timing.TABS_STAGGER * (index - 1))
	local isPicked = derive(function(): boolean
		return state.Tab() == index
	end)
	local hand = Hand.React("Take", function(): boolean
		return not isPicked()
	end)
	local picked = Hand.Spring(function(): number
		return if state.Tab() == index then 1 else 0
	end, Timing.PICK_PERIOD)
	-- A potion landing on POTIONS, or a soul on MUTATE, punches its glyph.
	local landed = derive(function(): number
		return Progress(state.Now(), state.LandedAt()[index] or -math.huge, 0.35)
	end)
	local at = Layout.TABS[index]
	local position = derive(function(): UDim2
		return UDim2.fromOffset(
			at.X + Layout.TAB_SIZE.X / 2,
			at.Y + Layout.TAB_SIZE.Y / 2 - math.round(Timing.TABS_DROP * drop())
		)
	end)
	local scale = derive(function(): number
		return (1 - drop()) * hand.Scale()
	end)
	local ink = function(): Color3
		return Palette.Lavender:Lerp(Palette.White, math.clamp(picked(), 0, 1))
	end

	local word = create("Frame")({
		Name = `Tab{index}Word`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(Layout.TAB_SIZE.X, Layout.TAB_SIZE.Y),
		BackgroundTransparency = 1,
		ZIndex = 6,
		create("UIScale")({ Scale = scale }),
		create("Frame")({
			Name = "Row",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, Layout.TAB_GAP),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			create("Frame")({
				Name = "GlyphBox",
				LayoutOrder = 1,
				Size = UDim2.fromOffset(Layout.TAB_GLYPH, Layout.TAB_GLYPH),
				BackgroundTransparency = 1,
				Components.Picture(if index == 1 then EIcons.Flask else EIcons.PotionBottle, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = Components.PictureBox(Layout.TAB_GLYPH),
					ImageColor3 = if index == 1 then nil else ink,
					create("UIScale")({
						Scale = function()
							return 1 + 0.12 * hand.Rise() + 0.45 * (1 - Motion.Decelerate(landed()))
						end,
					}),
				}),
			}),
			Label({
				LayoutOrder = 2,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Layout.TAB_TEXT),
				TextSize = Layout.TAB_TEXT,
				TextColor3 = ink,
				Text = if index == 1 then "MUTATE" else "POTIONS",
			}),
		}),
	})

	local button = Components.Button({
		Name = `Tab{index}`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(Layout.TAB_SIZE.X, Layout.TAB_SIZE.Y),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Interactable = Parts.Uncovered(state),
		Activated = function()
			if state.Tab() == index then return end
			hand.Commit()
			actions.PickTab(index)
		end,
		hand.Events,
		create("UIScale")({ Scale = scale }),
		Components.Panel({
			Glow = function()
				return Color3.new():Lerp(Palette.Pink, hand.Light())
			end,
			GlowTransparency = function()
				return 0.6 - 0.3 * hand.Light()
			end,
		}, {
			Name = "Plate",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 3, 2),
			Components.Sheen(hand.Glint, 3),
			create("Frame")({
				Name = "BracketsHolder",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Components.Brackets(hand.Rise, function()
					return 0.6 - 0.3 * hand.Light()
				end, Layout.TAB_BRACKET_LENGTH, isPicked),
			}),
		}),
	}) :: TextButton

	return { button, word }, hand.Scale
end

-- His pink slab under the tab on show, gliding from one to the other, riding the scale of the tab it lies on.
local function glider(state: Types.TLabState, elapsed: () -> number, scales: { () -> number }): Frame
	local drop = Parts.Away(state, elapsed, Timing.TABS_DELAY)
	local x = Hand.Spring(function(): number
		return Layout.TABS[state.Tab()].X
	end, Timing.PICK_PERIOD, Timing.PICK_DAMPING)

	return Components.Slab({ Kind = "Pink", Marks = true }, {
		Name = "Glider",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(
				math.round(x()) + Layout.TAB_SIZE.X / 2,
				Layout.TABS[1].Y + Layout.TAB_SIZE.Y / 2 - math.round(Timing.TABS_DROP * drop())
			)
		end,
		Size = UDim2.fromOffset(Layout.TAB_SIZE.X + 2, Layout.TAB_SIZE.Y + 2),
		ZIndex = 5,
		create("UIScale")({
			Scale = function()
				return (1 - drop()) * scales[state.Tab()]()
			end,
		}),
	})
end

local function brewsLeft(state: Types.TLabState, elapsed: () -> number): Frame
	local faded = Parts.Faded(state, elapsed, Timing.TABS_DELAY)
	local text = derive(function(): string
		local left = state.BrewsLeft()
		if left > 0 then return if left == 1 then "1 BREW LEFT" else `{left} BREWS LEFT` end
		local seconds = math.max(math.ceil(state.BrewsBackAt() - state.Clock()), 0)
		local hours = seconds // 3600
		local minutes = (seconds % 3600) // 60
		return if hours > 0 then `NEW BREWS IN {hours}H {minutes}M` else `NEW BREWS IN {math.max(minutes, 1)}M`
	end)

	return create("Frame")({
		Name = "BrewsLeft",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromOffset(Layout.BREWS_RIGHT, Layout.BREWS_Y - 3),
		Size = UDim2.fromOffset(520, Layout.BREWS_GLYPH),
		BackgroundTransparency = 1,
		ZIndex = 4,
		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Components.Picture(EIcons.Flask, {
			LayoutOrder = 1,
			Size = Components.PictureBox(Layout.BREWS_GLYPH),
			ImageTransparency = faded,
		}),
		Label({
			LayoutOrder = 2,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, Layout.BREWS_TEXT),
			TextSize = Layout.BREWS_TEXT,
			TextColor3 = function()
				return if state.BrewsLeft() > 0 then Palette.Gold else Palette.Lavender
			end,
			TextTransparency = faded,
			Text = text,
		}),
	})
end

-- The souls a dissolve gave back, rising over the MUTATE tab as the last of them lands, then fading.
local function gained(state: Types.TLabState): Frame
	local t = derive(function(): number
		return Progress(state.Now(), state.GainedAt(), Timing.GAINED)
	end)
	local faded = derive(function(): number
		return Progress(t(), 0.7, 0.3)
	end)
	local at = Layout.TABS[1] + Vector2.new(Layout.TAB_SIZE.X / 2, -6)

	return create("Frame")({
		Name = "Gained",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = function()
			return UDim2.fromOffset(at.X, at.Y - math.round(Layout.GAINED_RISE * Motion.Decelerate(t())))
		end,
		Size = UDim2.fromOffset(300, Layout.GAINED_TEXT),
		BackgroundTransparency = 1,
		ZIndex = 21,
		Visible = function()
			local now = t()
			return now > 0 and now < 1
		end,
		create("UIScale")({
			Scale = function()
				return 1 + 0.4 * (1 - Motion.Decelerate(math.clamp(t() * 5, 0, 1)))
			end,
		}),
		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Components.Picture(EIcons.Soul, {
			LayoutOrder = 1,
			Size = Components.PictureBox(Layout.GAINED_TEXT + 4),
			ImageTransparency = faded,
		}),
		Label({
			LayoutOrder = 2,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, Layout.GAINED_TEXT),
			TextSize = Layout.GAINED_TEXT,
			TextColor3 = Palette.Gold,
			TextTransparency = faded,
			Text = state.Gained,
		}),
	})
end

-- A Legendary or a Mythic landing lights the whole view in its colour, once.
local function screenFlash(state: Types.TLabState): Frame
	local flash = derive(function(): number
		local times = Brew.Times(state)
		local shown = state.Shown()
		if not times or not shown or shown.Rarity < ERarities.Legendary then return 1 end
		local t = Progress(state.Now(), times.LandAt, Timing.SCREEN_FLASH)
		if t <= 0 or t >= 1 then return 1 end
		return 0.55 + 0.45 * Motion.Out(t)
	end)

	return create("Frame")({
		Name = "ScreenFlash",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(4, 4),
		BorderSizePixel = 0,
		BackgroundColor3 = function()
			local shown = state.Shown()
			return if shown then Parts.Rarity(shown.Rarity).Accent else Palette.White
		end,
		BackgroundTransparency = flash,
		Visible = function()
			return flash() < 1
		end,
		ZIndex = 1,
	})
end

local function toast(state: Types.TLabState): TextLabel
	local shown = derive(function(): number
		local since = state.Now() - state.RefusedAt()
		if since < 0 or since > Timing.TOAST then return 0 end
		return math.min(since / 0.12, 1, (Timing.TOAST - since) / 0.3)
	end)

	return Label({
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(Layout.DESIGN.X / 2, Layout.TOAST_Y - math.round(8 * (1 - shown())))
		end,
		Size = UDim2.fromOffset(900, Layout.TOAST_TEXT),
		TextSize = Layout.TOAST_TEXT,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Palette.Pink,
		TextTransparency = function()
			return 1 - shown()
		end,
		Text = state.RefusedText,
		Visible = function()
			return shown() > 0
		end,
		ZIndex = 8,
	})
end

-- One page, faded through a group only while it fades, and out of the hit test while it is gone.
local function page(
	state: Types.TLabState,
	index: number,
	panelShown: () -> number,
	content: (shown: () -> number) -> { Instance }
)
	local onShow = Hand.Spring(function(): number
		return if state.Tab() == index then 1 else 0
	end, Timing.PAGE_PERIOD)
	local shown = derive(function(): number
		return math.clamp(onShow(), 0, 1) * panelShown()
	end)

	return create("Frame")({
		Name = if index == 1 then "MutatePage" else "PotionsPage",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Visible = function()
			return shown() > 0.01
		end,
		Components.FadeGroup("Page", shown, { Size = UDim2.fromScale(1, 1), ZIndex = 1 }, content(shown)),
	})
end

function Screen.Build(state: Types.TLabState, actions: Types.TLabActions): { any }
	local elapsed = Parts.Elapsed(state)
	local dimFaded = Parts.Faded(state, elapsed, 0)
	local panelAway = Parts.Away(state, elapsed, Timing.PANEL_DELAY)
	local panelFaded = Parts.Faded(state, elapsed, Timing.PANEL_DELAY)
	local panelShown = derive(function(): number
		return 1 - panelFaded()
	end)
	local tabOne, scaleOne = tab(state, actions, elapsed, 1)
	local tabTwo, scaleTwo = tab(state, actions, elapsed, 2)
	local badgeAt = Layout.TABS[2] + Vector2.new(Layout.TAB_SIZE.X, 0)
	local panel = Parts.PANEL

	return {
		create("TextButton")({
			Name = "Dim",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(4, 4),
			BackgroundColor3 = Color3.new(),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			BackgroundTransparency = function()
				return 1 - Timing.DIM * (1 - dimFaded())
			end,
		}),
		screenFlash(state),
		create("Frame")({
			Name = "Lab",
			Position = function()
				return UDim2.fromOffset(0, math.round(Timing.PANEL_RISE * panelAway()) - Parts.Lift())
			end,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Components.FadeGroup("Panel", panelShown, { Size = UDim2.fromScale(1, 1) }, {
				Components.Panel({ Brackets = true, Wide = true, Tall = true }, {
					Name = "Panel",
					Position = UDim2.fromOffset(panel.Min.X, panel.Min.Y),
					Size = function()
						return UDim2.fromOffset(panel.Width, panel.Height + Parts.Lift())
					end,
					ZIndex = 1,
				}),
				create("Frame")({
					Name = "Rule",
					Position = UDim2.fromOffset(Parts.LEFT, Layout.RULE_Y),
					Size = UDim2.fromOffset(Parts.RIGHT - Parts.LEFT, 1),
					BackgroundColor3 = Parts.RULE,
					BorderSizePixel = 0,
					ZIndex = 2,
				}),
				brewsLeft(state, elapsed),
				-- Everything on the panel leaves with it (UI.md, "A screen's life").
				page(state, 1, function()
					return 1
				end, function()
					return Mutate.Build(state, actions)
				end),
				page(state, 2, function()
					return 1
				end, function()
					return Potions.Build(state, actions, panelShown)
				end),
				tabOne,
				tabTwo,
				glider(state, elapsed, { scaleOne, scaleTwo }),
				Notice.Build({
					Kind = "New",
					Size = Layout.BADGE,
					Count = function()
						return if state.IsOpen() then state.Unseen() else 0
					end,
				}, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(badgeAt.X, badgeAt.Y),
					ZIndex = 9,
				}),
			}),
		}),
		-- In the panel's raised layer, over EXIT as they always stood.
		create("Frame")({
			Name = "Over",
			Position = function()
				return UDim2.fromOffset(0, -Parts.Lift())
			end,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 8,
			Flight.Build(state),
			gained(state),
			toast(state),
		}),
		Components.Exit(
			Parts.Away(state, elapsed, Timing.EXIT_DELAY),
			actions.Close,
			{ Interactable = Parts.Uncovered(state) }
		),
	}
end

return Screen
