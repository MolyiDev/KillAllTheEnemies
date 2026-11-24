--!nonstrict
-- The squad screen (UIMatt.md, In-Game HUD - Squad Open), opened from SQUAD on the top bar: the run's scoreboard, one
-- row a player, the local player first. The world dims, the panel rises into place, the header catches the light, and
-- the rows deal in one after another, each counting its numbers up as it lands. While it is up a kill pops its number,
-- a death stings it, the Gold rolls, and a row lights up under the hand. Closed by its X, by a click on the dim, or by
-- the top bar icon. CONTRABAND and its hint are drawn as he drew them and do nothing: there is no contraband yet.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local source = vide.source
local spring = vide.spring
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
local Lerp = Motion.Lerp

-- His drawn rects in px at 1080, from the panel's top left corner unless said otherwise. The panel's height follows
-- the rows (a party is four at most, PadsCore), and his four make his 560.
local Layout = table.freeze({
	WIDTH = 1240,
	-- The screen's share down which the panel's middle sits.
	CENTER_Y = 0.4168,
	HEADER = Vector2.new(23, 23),
	HEADER_SIZE = Vector2.new(1114, 75),
	CLOSE = Vector2.new(1147, 27),
	CLOSE_SIZE = 66,
	-- The X: each bar's length and weight.
	CLOSE_BAR = Vector2.new(23, 2),
	-- From the header's corner: the glyph's middle and longer side, then each line's corner and letter height.
	ICON = Vector2.new(43.5, 37),
	ICON_SIZE = 35,
	TITLE = Vector2.new(73, 17),
	TITLE_SIZE = 41,
	INFO = Vector2.new(221, 29),
	INFO_SIZE = 20,
	HINT = Vector2.new(908, 31),
	HINT_SIZE = 15,
	COLUMNS_Y = 118,
	COLUMNS_SIZE = 15,
	-- Where each column's words and numbers start.
	PLAYER_X = 40,
	KILLS_X = 660,
	DEATHS_X = 770,
	CASH_X = 900,
	CONTRABAND_X = 1030,
	ROWS = Vector2.new(24, 150),
	ROW_SIZE = Vector2.new(1191, 84),
	ROW_PITCH = 96,
	ROWS_BOTTOM = 38,
	-- From a row's corner.
	AVATAR = Vector2.new(13, 12),
	AVATAR_SIZE = 60,
	NAME = Vector2.new(92, 17),
	NAME_SIZE = 27,
	TAG = Vector2.new(92, 48),
	TAG_HEIGHT = 22,
	TAG_SIZE = 13,
	NUMBER_Y = 25,
	NUMBER_SIZE = 34,
	CASH_Y = 26,
	CASH_SIZE = 32,
	CONTRABAND_Y = 33,
	CONTRABAND_SIZE = 17,
	-- The local player's row wears a bar this wide down its left edge.
	OWN_BAR = 5,
	-- The room round the panel and round a row inside the group that fades it, for the glow and the brackets (a
	-- CanvasGroup clips).
	MARGIN = 48,
	ROW_MARGIN = 28,
})

local Timing = table.freeze({
	-- The panel decelerates up into place and accelerates down out of it, the exit the faster. Its fade runs on the
	-- clock, not on the move: a decelerate is nearly done in a quarter of its time, and a fade tied to it reads as
	-- a pop.
	OPEN = 0.34,
	FADE = 0.27,
	RISE = 26,
	CLOSE = 0.2,
	SINK = 14,
	DIM = 0.5,
	-- The header's words slide out from behind its left end, its hint in from the right, and the light crosses it.
	TITLE_DELAY = 0.06,
	TITLE = 0.32,
	TITLE_SLIDE = 22,
	SHEEN_DELAY = 0.14,
	SHEEN = 0.7,
	COLUMNS_DELAY = 0.16,
	COLUMNS = 0.25,
	-- Each row is dealt in from the right a beat after the one above it, the light crosses it as it lands, and its
	-- numbers count up from nothing.
	ROW_DELAY = 0.12,
	ROW_STAGGER = 0.07,
	ROW = 0.4,
	ROW_FADE = 0.3,
	ROW_SLIDE = 44,
	ROW_SHEEN_DELAY = 0.2,
	ROW_SHEEN = 0.6,
	COUNT_DELAY = 0.12,
	COUNT = 0.55,
	-- Every gesture of an open or a shut is over by now, four rows and their counts included.
	SETTLED = 1.2,
	-- A kill: the number swells and falls straight back, and the row's glow flares.
	KILL = 0.26,
	KILL_SCALE = 0.2,
	KILL_GLOW = 0.4,
	-- A death: the number goes white and falls back to its pink. A colour, not a kick.
	DEATH = 0.55,
	-- Under the hand a row's glow comes up and its brackets open.
	HOVER_GLOW = 0.45,
})

-- Each row's colour in party order, as his four, and how far its face warms toward it at the bottom.
local ACCENTS = table.freeze({
	table.freeze({ Color = Palette.Pink, Tint = 0.38 }),
	table.freeze({ Color = Palette.Green, Tint = 0.17 }),
	table.freeze({ Color = Palette.Gold, Tint = 0.17 }),
	table.freeze({ Color = Palette.Steel, Tint = 0.2 }),
})
-- A class's tag and the frame round its player's face: his SURVIVOR grey, the only class there is.
local TAG_COLOR = Color3.fromRGB(153, 153, 173)
local ROW_GLOW = 0.7

local Squad = {}

local function label(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
		props,
	})
end

-- A player's face in his frame: the class colour round an ink square that warms toward it at the bottom, and four
-- small brackets standing off it.
local function avatar(member: () -> Types.TSquadMember): Frame
	return create("Frame")({
		Name = "Avatar",
		Position = UDim2.fromOffset(Layout.AVATAR.X, Layout.AVATAR.Y),
		Size = UDim2.fromOffset(Layout.AVATAR_SIZE, Layout.AVATAR_SIZE),
		BackgroundColor3 = TAG_COLOR,
		BorderSizePixel = 0,
		ZIndex = 2,
		create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
		create("Frame")({
			Name = "Face",
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			Components.Gradient({
				{ 0, Palette.Ink },
				{ 0.4, Palette.Ink:Lerp(TAG_COLOR, 0.1) },
				{ 0.6, Palette.Ink:Lerp(TAG_COLOR, 0.2) },
				{ 1, Palette.Ink:Lerp(TAG_COLOR, 0.55) },
			}),
			create("ImageLabel")({
				Name = "Head",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Image = function()
					return `rbxthumb://type=AvatarHeadShot&id={member().UserId}&w=150&h=150`
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			}),
		}),
		Components.Brackets(nil, 0.7, 22),
	})
end

local function classTag(member: () -> Types.TSquadMember): Frame
	return create("Frame")({
		Name = "Class",
		Position = UDim2.fromOffset(Layout.TAG.X, Layout.TAG.Y),
		Size = UDim2.fromOffset(0, Layout.TAG_HEIGHT),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = TAG_COLOR,
		BorderSizePixel = 0,
		ZIndex = 2,
		create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
		create("UIPadding")({ PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 10) }),
		label({
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			TextSize = Layout.TAG_SIZE,
			TextColor3 = Palette.Ink,
			Text = function()
				return string.upper(member().ClassName())
			end,
		}),
	})
end

-- One player's row. `elapsed` is the seconds since the screen was opened or shut, `shown` how much of the screen is
-- there (0 to 1).
local function row(
	state: Types.THudState,
	elapsed: () -> number,
	shown: () -> number
): (() -> Types.TSquadMember, number) -> CanvasGroup
	return function(member: () -> Types.TSquadMember, index: number): CanvasGroup
		local accent = ACCENTS[(index - 1) % #ACCENTS + 1]
		local delay = Timing.ROW_DELAY + Timing.ROW_STAGGER * (index - 1)
		local isHovered = source(false)
		local hover = spring(function()
			return if isHovered() then 1 else 0
		end, 0.2, 0.9)

		-- 0 to 1 as the row's own gestures run after the screen opens; all done while it shuts.
		local function since(after: number, seconds: number): number
			if not state.IsSquadOpen() then return 1 end
			return Progress(elapsed(), delay + after, seconds)
		end

		local counted = function(): number
			return Motion.Out(since(Timing.COUNT_DELAY, Timing.COUNT))
		end
		-- 1 falling to 0 after a kill and after a death. Derived, so that once they are back at 0 the HUD's clock,
		-- which ticks for every coin that lands, redraws nothing here.
		local killed = derive(function(): number
			return Motion.Fade(state.Now(), member().KilledAt(), Timing.KILL)
		end)
		local stung = derive(function(): number
			return Motion.Fade(state.Now(), member().DiedAt(), Timing.DEATH)
		end)

		return create("CanvasGroup")({
			Name = `Row{index}`,
			Position = function()
				local slide = Timing.ROW_SLIDE * (1 - Motion.Decelerate(since(0, Timing.ROW)))
				return UDim2.fromOffset(
					math.round(slide) - Layout.ROW_MARGIN,
					(index - 1) * Layout.ROW_PITCH - Layout.ROW_MARGIN
				)
			end,
			Size = UDim2.fromOffset(
				Layout.ROW_SIZE.X + Layout.ROW_MARGIN * 2,
				Layout.ROW_SIZE.Y + Layout.ROW_MARGIN * 2
			),
			BackgroundTransparency = 1,
			GroupTransparency = function()
				if not state.IsSquadOpen() then return 1 - shown() end
				return 1 - Motion.Out(since(0, Timing.ROW_FADE))
			end,
			Components.Card({
				Accent = accent.Color,
				Tint = accent.Tint,
				Edge = 2,
				Wide = true,
				GlowTransparency = function()
					local lit = killed()
					return Lerp(Lerp(ROW_GLOW, Timing.HOVER_GLOW, hover()), Timing.KILL_GLOW, lit * lit)
				end,
			}, {
				Name = "Face",
				Position = UDim2.fromOffset(Layout.ROW_MARGIN, Layout.ROW_MARGIN),
				Size = UDim2.fromOffset(Layout.ROW_SIZE.X, Layout.ROW_SIZE.Y),
				MouseEnter = function()
					isHovered(true)
				end,
				MouseLeave = function()
					isHovered(false)
				end,
				Components.Brackets(hover, 0.65, 20),
				if index == 1
					then create("Frame")({
						Name = "Own",
						Size = UDim2.new(0, Layout.OWN_BAR, 1, 0),
						BackgroundTransparency = 1,
						ClipsDescendants = true,
						ZIndex = 2,
						create("Frame")({
							Size = UDim2.new(0, Layout.OWN_BAR * 2, 1, 0),
							BackgroundColor3 = accent.Color,
							BorderSizePixel = 0,
							create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
						}),
					})
					else nil,
				avatar(member),
				label({
					Name = "Name",
					Position = UDim2.fromOffset(Layout.NAME.X, Layout.NAME.Y),
					Size = UDim2.fromOffset(Layout.KILLS_X - Layout.ROWS.X - Layout.NAME.X - 24, Layout.NAME_SIZE),
					TextSize = Layout.NAME_SIZE,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Text = function()
						return string.upper(member().Name)
					end,
				}),
				classTag(member),
				label({
					Name = "Kills",
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.fromOffset(
						Layout.KILLS_X - Layout.ROWS.X,
						Layout.NUMBER_Y + Layout.NUMBER_SIZE / 2
					),
					Size = UDim2.fromOffset(100, Layout.NUMBER_SIZE),
					TextSize = Layout.NUMBER_SIZE,
					Text = function()
						return Components.Commas(math.round(member().Kills() * counted()))
					end,
					create("UIScale")({
						Scale = function()
							local swell = killed()
							return 1 + Timing.KILL_SCALE * swell * swell
						end,
					}),
				}),
				label({
					Name = "Deaths",
					Position = UDim2.fromOffset(Layout.DEATHS_X - Layout.ROWS.X, Layout.NUMBER_Y),
					Size = UDim2.fromOffset(100, Layout.NUMBER_SIZE),
					TextSize = Layout.NUMBER_SIZE,
					TextColor3 = function()
						local sting = stung()
						return Palette.Pink:Lerp(Palette.White, sting * sting)
					end,
					Text = function()
						return tostring(math.round(member().Deaths() * counted()))
					end,
				}),
				label({
					Name = "Cash",
					Position = UDim2.fromOffset(Layout.CASH_X - Layout.ROWS.X, Layout.CASH_Y),
					Size = UDim2.fromOffset(126, Layout.CASH_SIZE),
					TextSize = Layout.CASH_SIZE,
					TextColor3 = Palette.Gold,
					Text = function()
						return `${Components.Commas(math.round(member().Cash() * counted()))}`
					end,
				}),
				label({
					Name = "Contraband",
					Position = UDim2.fromOffset(Layout.CONTRABAND_X - Layout.ROWS.X, Layout.CONTRABAND_Y),
					Size = UDim2.fromOffset(170, Layout.CONTRABAND_SIZE),
					TextSize = Layout.CONTRABAND_SIZE,
					TextColor3 = Palette.Lavender,
					Text = "NONE YET",
				}),
				create("Frame")({
					Name = "SheenWindow",
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					ClipsDescendants = true,
					ZIndex = 3,
					Components.Sheen(function()
						return since(Timing.ROW_SHEEN_DELAY, Timing.ROW_SHEEN)
					end, 3),
				}),
			}),
		})
	end
end

-- His pink square with a thin white X. Under the hand it grows a little and the X turns a quarter; pressed, it dips.
local function closeButton(actions: Types.TActions): TextButton
	local isHovered = source(false)
	local isPressed = source(false)
	local hover = spring(function()
		return if isHovered() then 1 else 0
	end, 0.22, 0.85)
	local scale = spring(function()
		return if isPressed() then 0.93 elseif isHovered() then 1.06 else 1
	end, 0.16, 0.85)

	local function bar(rotation: number): Frame
		return create("Frame")({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(Layout.CLOSE_BAR.X, Layout.CLOSE_BAR.Y),
			Rotation = function()
				return rotation + 90 * hover()
			end,
			BackgroundColor3 = Palette.White,
			BorderSizePixel = 0,
			ZIndex = 2,
		})
	end

	return Components.Button({
		Name = "Close",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(Layout.CLOSE.X + Layout.CLOSE_SIZE / 2, Layout.CLOSE.Y + Layout.CLOSE_SIZE / 2),
		Size = UDim2.fromOffset(Layout.CLOSE_SIZE, Layout.CLOSE_SIZE),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Activated = actions.CloseSquad,
		MouseEnter = function()
			isHovered(true)
		end,
		MouseLeave = function()
			isHovered(false)
			isPressed(false)
		end,
		MouseButton1Down = function()
			isPressed(true)
		end,
		MouseButton1Up = function()
			isPressed(false)
		end,
		create("UIScale")({ Scale = scale }),
		Components.Slab({
			Kind = "Pink",
			GlowTransparency = function()
				return Lerp(0.6, 0.4, hover())
			end,
		}, {
			Name = "Face",
			Size = UDim2.fromScale(1, 1),
			bar(45),
			bar(-45),
		}),
	}) :: TextButton
end

-- His pink bar across the top: the glyph, SQUAD, the wave and the run's clock, and the hint at its right end.
local function header(state: Types.THudState, elapsed: () -> number): Frame
	-- 1 to 0 as the words arrive; 0 while the screen shuts.
	local away = function(): number
		if not state.IsSquadOpen() then return 0 end
		return 1 - Motion.Decelerate(Progress(elapsed(), Timing.TITLE_DELAY, Timing.TITLE))
	end

	return Components.Slab({ Kind = "Pink", GlowTransparency = 0.45 }, {
		Name = "Header",
		Position = UDim2.fromOffset(Layout.HEADER.X, Layout.HEADER.Y),
		Size = UDim2.fromOffset(Layout.HEADER_SIZE.X, Layout.HEADER_SIZE.Y),
		ZIndex = 2,
		create("Frame")({
			Name = "Words",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 2,
			create("Frame")({
				Name = "Title",
				Position = function()
					return UDim2.fromOffset(-math.round(Timing.TITLE_SLIDE * away()), 0)
				end,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Components.Picture(EIcons.Squad, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(Layout.ICON.X, Layout.ICON.Y),
					Size = Components.PictureBox(Layout.ICON_SIZE),
				}),
				label({
					Position = UDim2.fromOffset(Layout.TITLE.X, Layout.TITLE.Y),
					Size = UDim2.fromOffset(150, Layout.TITLE_SIZE),
					TextSize = Layout.TITLE_SIZE,
					Text = "SQUAD",
				}),
				label({
					Position = UDim2.fromOffset(Layout.INFO.X, Layout.INFO.Y),
					Size = UDim2.fromOffset(400, Layout.INFO_SIZE),
					TextSize = Layout.INFO_SIZE,
					Text = function()
						local seconds = state.RunSeconds()
						return `WAVE {state.Round()}  ·  {seconds // 60}:{string.format("%02d", seconds % 60)}`
					end,
				}),
			}),
			label({
				Name = "Hint",
				Position = function()
					return UDim2.fromOffset(Layout.HINT.X + math.round(Timing.TITLE_SLIDE * away()), Layout.HINT.Y)
				end,
				Size = UDim2.fromOffset(200, Layout.HINT_SIZE),
				TextSize = Layout.HINT_SIZE,
				TextTransparency = 0.1,
				Text = "HOVER YOURS TO DROP",
			}),
			Components.Sheen(function()
				if not state.IsSquadOpen() then return 1 end
				return Progress(elapsed(), Timing.SHEEN_DELAY, Timing.SHEEN)
			end, 3),
		}),
	})
end

function Squad.Build(state: Types.THudState, actions: Types.TActions): Frame
	-- Seconds since the screen was opened or shut, held once every gesture is over: the HUD's clock ticks for other
	-- pieces too, and held, nothing below is worked out again for them.
	local elapsed = derive(function(): number
		return math.min(state.Now() - state.SquadToggledAt(), Timing.SETTLED)
	end)
	-- How much of the screen is there, 0 to 1: its fade, on the clock both ways.
	local shown = function(): number
		if state.IsSquadOpen() then return Motion.Out(Progress(elapsed(), 0, Timing.FADE)) end
		return 1 - Progress(elapsed(), 0, Timing.CLOSE)
	end
	-- How far under its place the panel is, in px.
	local drop = function(): number
		if state.IsSquadOpen() then
			return Timing.RISE * (1 - Motion.Decelerate(Progress(elapsed(), 0, Timing.OPEN)))
		end
		return Timing.SINK * Motion.Accelerate(Progress(elapsed(), 0, Timing.CLOSE))
	end
	local height = function(): number
		local rows = math.max(#state.Squad(), 1)
		return Layout.ROWS.Y + rows * Layout.ROW_PITCH - (Layout.ROW_PITCH - Layout.ROW_SIZE.Y) + Layout.ROWS_BOTTOM
	end

	local function column(text: string, x: number): TextLabel
		return label({
			Position = UDim2.fromOffset(x, Layout.COLUMNS_Y),
			Size = UDim2.fromOffset(160, Layout.COLUMNS_SIZE),
			TextSize = Layout.COLUMNS_SIZE,
			TextColor3 = Palette.Lavender,
			TextTransparency = function()
				if not state.IsSquadOpen() then return 0 end
				return 1 - Motion.Out(Progress(elapsed(), Timing.COLUMNS_DELAY, Timing.COLUMNS))
			end,
			Text = text,
		})
	end

	return create("Frame")({
		Name = "Squad",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 8,
		Visible = function()
			return shown() > 0.001
		end,
		create("TextButton")({
			Name = "Dim",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			BackgroundTransparency = function()
				return 1 - Timing.DIM * shown()
			end,
			Activated = actions.CloseSquad,
		}),
		create("Frame")({
			Name = "Window",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				return UDim2.new(0.5, 0, Layout.CENTER_Y, math.round(drop()))
			end,
			Size = function()
				return UDim2.fromOffset(Layout.WIDTH, height())
			end,
			BackgroundTransparency = 1,
			ZIndex = 2,
			-- A press on the panel stops here. A Frame lets it through to the dim, which would shut the screen.
			create("TextButton")({
				Name = "Sink",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Text = "",
			}),
			create("CanvasGroup")({
				Name = "Chrome",
				Position = UDim2.fromOffset(-Layout.MARGIN, -Layout.MARGIN),
				Size = UDim2.new(1, Layout.MARGIN * 2, 1, Layout.MARGIN * 2),
				BackgroundTransparency = 1,
				GroupTransparency = function()
					return 1 - shown()
				end,
				-- Longer than the streak texture: its window starts at the corner and it is tiled across.
				Components.Panel({ Brackets = true, TexturePhase = Vector2.zero, Wide = true, Tall = true }, {
					Name = "Panel",
					Position = UDim2.fromOffset(Layout.MARGIN, Layout.MARGIN),
					Size = UDim2.new(1, -Layout.MARGIN * 2, 1, -Layout.MARGIN * 2),
					header(state, elapsed),
					closeButton(actions),
					column("PLAYER", Layout.PLAYER_X),
					column("KILLS", Layout.KILLS_X),
					column("DEATHS", Layout.DEATHS_X),
					column("CASH", Layout.CASH_X),
					column("CONTRABAND", Layout.CONTRABAND_X),
				}),
			}),
			create("Frame")({
				Name = "Rows",
				Position = UDim2.fromOffset(Layout.ROWS.X, Layout.ROWS.Y),
				Size = UDim2.fromOffset(Layout.ROW_SIZE.X, 0),
				BackgroundTransparency = 1,
				ZIndex = 2,
				vide.indexes(state.Squad, row(state, elapsed, shown)),
			}),
		}),
	})
end

return Squad
