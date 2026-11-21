--!nonstrict
-- The squad screen (UIMatt.md, In-Game HUD - Squad Open), opened from SQUAD on the top bar: the world dims, the panel
-- rises into place and the rows come in one after another, the local player first. Each row is a teammate's face,
-- name, health and whether they are up or down. Closed by its X, by a click on the dim, or by the top bar icon.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Motion = require(script.Parent.Motion)
local Types = require(script.Parent.Types)

local create = vide.create
local source = vide.source
local spring = vide.spring
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress

-- Design px at 1080. The panel's height follows the rows (a party is four at most, PadsCore).
local Layout = table.freeze({
	WIDTH = 940,
	PAD = 18,
	HEADER = 66,
	COLUMNS = 30,
	ROW = 84,
	ROW_GAP = 8,
	AVATAR = 62,
	CLOSE = 66,
	-- The canvas the panel fades in is this much bigger on every side, so its glow and brackets are not cut.
	MARGIN = 48,
	-- Columns' left edges.
	HEALTH_X = 470,
	STATUS_X = 760,
	BAR_WIDTH = 240,
	CELLS = 10,
})

local Timing = table.freeze({
	OPEN = 0.3,
	CLOSE = 0.18,
	RISE = 26,
	ROW_STAGGER = 0.06,
	ROW_SLIDE = 36,
	DIM = 0.5,
})

-- Each row's colour, in party order, as the designer's four.
local ACCENTS = table.freeze({ Palette.Pink, Palette.Green, Palette.Gold, Palette.Steel })

local Squad = {}

local function label(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		TextXAlignment = Enum.TextXAlignment.Left,
		props,
	})
end

local function healthCells(member: () -> Types.TSquadMember, accent: Color3): Frame
	local share = function(): number
		local value = member()
		local maxHealth = value.MaxHealth()
		return if maxHealth > 0 then math.clamp(value.Health() / maxHealth, 0, 1) else 0
	end

	local cells = table.create(Layout.CELLS)
	for index = 1, Layout.CELLS do
		cells[index] = create("Frame")({
			LayoutOrder = index,
			Size = UDim2.new(1 / Layout.CELLS, -3, 1, 0),
			BackgroundColor3 = Color3.fromRGB(40, 34, 62),
			BorderSizePixel = 0,
			create("Frame")({
				Size = function()
					return UDim2.fromScale(math.clamp(share() * Layout.CELLS - (index - 1), 0, 1), 1)
				end,
				BackgroundColor3 = accent,
				BorderSizePixel = 0,
			}),
		})
	end

	return create("Frame")({
		Name = "Health",
		Position = UDim2.new(0, Layout.HEALTH_X, 0.5, -8),
		Size = UDim2.fromOffset(Layout.BAR_WIDTH, 16),
		BackgroundTransparency = 1,
		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 3),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		cells,
	})
end

local function row(state: Types.THudState, opened: () -> number): (() -> Types.TSquadMember, number) -> Frame
	return function(member: () -> Types.TSquadMember, index: number): Frame
		local accent = ACCENTS[(index - 1) % #ACCENTS + 1]
		local isDown = function()
			local value = member()
			return value.MaxHealth() > 0 and value.Health() <= 0
		end

		-- Each row lands a beat after the one above it.
		local slide = function(): number
			if not state.IsSquadOpen() then return 1 - opened() end
			local delay = Timing.ROW_STAGGER * index
			return 1 - Motion.Decelerate(Progress(state.Now(), state.SquadToggledAt(), Timing.OPEN, delay))
		end

		return create("Frame")({
			Name = `Row{index}`,
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, Layout.ROW),
			BackgroundTransparency = 1,
			Components.Panel({ Stroke = accent, Brackets = 5 }, {
				Name = "Face",
				Position = function()
					return UDim2.fromOffset(math.round(Timing.ROW_SLIDE * slide()), 0)
				end,
				Size = UDim2.fromScale(1, 1),
				create("ImageLabel")({
					Name = "Avatar",
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, 12, 0.5, 0),
					Size = UDim2.fromOffset(Layout.AVATAR, Layout.AVATAR),
					BackgroundColor3 = Palette.Ink,
					BorderSizePixel = 0,
					ZIndex = 2,
					Image = function()
						return `rbxthumb://type=AvatarHeadShot&id={member().UserId}&w=150&h=150`
					end,
					ImageTransparency = function()
						return if isDown() then 0.55 else 0
					end,
					create("UIStroke")({ Color = accent, Thickness = 2 }),
					create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
				}),
				label({
					Name = "Name",
					Position = UDim2.fromOffset(Layout.AVATAR + 28, 12),
					Size = UDim2.fromOffset(Layout.HEALTH_X - Layout.AVATAR - 50, 32),
					TextSize = 28,
					TextTruncate = Enum.TextTruncate.AtEnd,
					ZIndex = 2,
					Text = function()
						return string.upper(member().Name)
					end,
				}),
				create("Frame")({
					Name = "You",
					Position = UDim2.fromOffset(Layout.AVATAR + 28, 50),
					Size = UDim2.fromOffset(0, 20),
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundColor3 = accent,
					BorderSizePixel = 0,
					ZIndex = 2,
					Visible = function()
						return member().IsSelf
					end,
					create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
					create("UIPadding")({ PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
					label({
						Size = UDim2.fromScale(0, 1),
						AutomaticSize = Enum.AutomaticSize.X,
						TextSize = 12,
						TextColor3 = Palette.Ink,
						Text = "YOU",
					}),
				}),
				healthCells(member, accent),
				label({
					Name = "Status",
					Position = UDim2.new(0, Layout.STATUS_X, 0.5, -14),
					Size = UDim2.fromOffset(140, 28),
					TextSize = 24,
					ZIndex = 2,
					TextColor3 = function()
						return if isDown() then Palette.Pink else Palette.Green
					end,
					Text = function()
						return if isDown() then "DOWN" else "ALIVE"
					end,
				}),
			}),
		})
	end
end

local function closeButton(actions: Types.TActions): TextButton
	local isHovered = source(false)
	local scale = spring(function()
		return if isHovered() then 1.08 else 1
	end, 0.17, 0.82)

	local function bar(rotation: number): Frame
		return create("Frame")({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(4, 30),
			Rotation = rotation,
			BackgroundColor3 = Palette.White,
			BorderSizePixel = 0,
			ZIndex = 2,
		})
	end

	return Components.Button({
		Name = "Close",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -(Layout.PAD + Layout.CLOSE / 2), 0, Layout.PAD + Layout.CLOSE / 2),
		Size = UDim2.fromOffset(Layout.CLOSE, Layout.CLOSE),
		BackgroundColor3 = Palette.Pink,
		Activated = actions.CloseSquad,
		MouseEnter = function()
			isHovered(true)
		end,
		MouseLeave = function()
			isHovered(false)
		end,
		create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
		create("UIStroke")({ Color = Color3.fromRGB(255, 120, 180), Thickness = 2 }),
		create("UIScale")({ Scale = scale }),
		bar(45),
		bar(-45),
	}) :: TextButton
end

local function header(state: Types.THudState): Frame
	return create("Frame")({
		Name = "Header",
		Position = UDim2.fromOffset(Layout.PAD, Layout.PAD),
		Size = UDim2.new(1, -(Layout.PAD * 3 + Layout.CLOSE), 0, Layout.HEADER),
		BackgroundColor3 = Palette.White,
		BorderSizePixel = 0,
		create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
		create("UIGradient")({
			Rotation = 90,
			Color = ColorSequence.new(Color3.fromRGB(255, 80, 160), Color3.fromRGB(214, 22, 112)),
		}),
		create("UIShadow")({
			BlurRadius = UDim.new(0, 20),
			Color = Palette.Pink,
			Spread = UDim2.new(),
			Transparency = 0.55,
			ZIndex = -1,
		}),
		Components.Icon("Squad", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 20, 0.5, 0),
			Size = UDim2.fromOffset(36, 36),
			ImageColor3 = Palette.White,
		}),
		label({
			Position = UDim2.fromOffset(68, 0),
			Size = UDim2.fromOffset(170, Layout.HEADER),
			TextSize = 44,
			Text = "SQUAD",
		}),
		label({
			Position = UDim2.fromOffset(240, 0),
			Size = UDim2.new(1, -260, 0, Layout.HEADER),
			TextSize = 20,
			Text = function()
				local seconds = state.RunSeconds()
				return `WAVE {state.Round()}  ·  {seconds // 60}:{string.format("%02d", seconds % 60)}`
			end,
		}),
	})
end

function Squad.Build(state: Types.THudState, actions: Types.TActions): Frame
	-- 0 closed, 1 open: decelerating in, accelerating out (UI.md 5o).
	local opened = function(): number
		local now, at = state.Now(), state.SquadToggledAt()
		if state.IsSquadOpen() then return Motion.Decelerate(Progress(now, at, Timing.OPEN)) end
		return 1 - Motion.Accelerate(Progress(now, at, Timing.CLOSE))
	end

	local height = function(): number
		local rows = math.max(#state.Squad(), 1)
		return Layout.PAD * 2 + Layout.HEADER + 12 + Layout.COLUMNS + rows * (Layout.ROW + Layout.ROW_GAP)
	end

	local listTop = Layout.PAD + Layout.HEADER + 12 + Layout.COLUMNS
	local function column(text: string, x: number): TextLabel
		return label({
			Position = UDim2.fromOffset(x, Layout.PAD + Layout.HEADER + 12),
			Size = UDim2.fromOffset(160, Layout.COLUMNS - 8),
			TextSize = 15,
			TextColor3 = Palette.Lavender,
			ZIndex = 2,
			Text = text,
		})
	end

	return create("Frame")({
		Name = "Squad",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 8,
		Visible = function()
			return opened() > 0.001
		end,
		create("TextButton")({
			Name = "Dim",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			BackgroundTransparency = function()
				return 1 - Timing.DIM * opened()
			end,
			Activated = actions.CloseSquad,
		}),
		create("CanvasGroup")({
			Name = "Canvas",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				return UDim2.new(0.5, 0, 0.45, math.round(Timing.RISE * (1 - opened())))
			end,
			Size = function()
				return UDim2.fromOffset(Layout.WIDTH + Layout.MARGIN * 2, height() + Layout.MARGIN * 2)
			end,
			BackgroundTransparency = 1,
			ZIndex = 2,
			GroupTransparency = function()
				return 1 - opened()
			end,
			Components.Panel({
				Stroke = Palette.Pink,
				Glow = Palette.Pink,
				GlowTransparency = 0.6,
				Brackets = 7,
				-- Wider than half the streak texture: its window starts at the corner so it never runs off the end.
				TexturePhase = Vector2.zero,
			}, {
				Name = "Panel",
				Position = UDim2.fromOffset(Layout.MARGIN, Layout.MARGIN),
				Size = function()
					return UDim2.fromOffset(Layout.WIDTH, height())
				end,
				header(state),
				closeButton(actions),
				column("PLAYER", Layout.PAD + 12),
				column("HEALTH", Layout.PAD + Layout.HEALTH_X),
				column("STATUS", Layout.PAD + Layout.STATUS_X),
				create("Frame")({
					Name = "Rows",
					Position = UDim2.fromOffset(Layout.PAD, listTop),
					Size = UDim2.new(1, -Layout.PAD * 2, 1, -(listTop + Layout.PAD)),
					BackgroundTransparency = 1,
					ZIndex = 2,
					create("UIListLayout")({
						Padding = UDim.new(0, Layout.ROW_GAP),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					vide.indexes(state.Squad, row(state, opened)),
				}),
			}),
		}),
	})
end

return Squad
