--!nonstrict
-- The top of the results (UIMatt.md, Lobby Entering › Level Up Container and XP Breakdown Container), on his drawn
-- rects at 1080 with x from the screen's middle: the rank badge, the level panel with the Xp the run earned and its
-- bar, and under them a chip for each source of that Xp.
--
-- The badge is stamped down and the panel drops in; the chips are dealt, then each pours its Xp into the bar in turn:
-- it lights and a light crosses it, the bar fills and +XP counts with it. A level crossed punches LV and the badge,
-- flashes the bar back to the start and throws a ring and a burst of motes off the badge.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local spring = vide.spring
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress

-- His drawn rects in px at 1080: the badge's and the panel's corners (x from the screen's middle); inside the panel
-- LV, the Xp earned's right edge, the bar; the chips' row.
local Layout = table.freeze({
	TOP = 38,
	BADGE_X = -400,
	BADGE_SIZE = Vector2.new(130, 128),
	BADGE_GLYPH = 70,
	PANEL_X = -254,
	PANEL_SIZE = Vector2.new(654, 128),
	LV = Vector2.new(24, 16),
	LV_TEXT = 48,
	RANK_TEXT = 21,
	RANK_GAP = 16,
	GAINED_RIGHT = 630,
	GAINED_Y = 20,
	GAINED_TEXT = 40,
	BAR = Vector2.new(24, 80),
	BAR_SIZE = Vector2.new(606, 24),
	BAR_TEXT = 15,
	CHIPS_Y = 187,
	CHIP_HEIGHT = 36,
	CHIP_GAP = 10,
	CHIP_PADDING = 14,
	CHIP_TEXT = 16,
	-- The room round a piece inside the group that fades it, for its glow and brackets (a CanvasGroup clips).
	MARGIN = 40,
})

local Timing = table.freeze({
	-- The panel drops into place as the badge is stamped on.
	PANEL_DELAY = 0.08,
	PANEL = 0.45,
	PANEL_DROP = 30,
	BADGE_DELAY = 0.2,
	BADGE = 0.32,
	BADGE_SCALE = 0.55,
	BADGE_FLASH = 0.45,
	-- The chips are dealt one after another, then pour in turn: each takes POUR_BASE and a share of POUR_SPAN by the
	-- share of the Xp it carries, POUR_GAP apart.
	CHIPS_DELAY = 0.75,
	CHIP_STAGGER = 0.08,
	CHIP = 0.34,
	CHIP_RISE = 14,
	POUR_AFTER = 0.3,
	POUR_BASE = 0.45,
	POUR_SPAN = 1.1,
	POUR_GAP = 0.12,
	POUR_SHEEN = 0.5,
	POUR_SWELL = 0.06,
	-- A level crossed.
	PUNCH_PERIOD = 0.28,
	PUNCH = 0.22,
	FLASH_PERIOD = 0.32,
	RING = 0.6,
	RING_REACH = 46,
	MOTES = 0.8,
})

-- His bar's colours: the green fill lighter at its top, the dark track.
local Colors = table.freeze({
	FILL_TOP = Color3.fromRGB(120, 240, 172),
	TRACK = Color3.fromRGB(40, 36, 64),
	CHIP_EDGE = Color3.fromRGB(28, 120, 74),
})

-- The rank shown by LV, from the level it starts at.
local RANKS = table.freeze({
	{ From = 1, Name = "PRIVATE" },
	{ From = 10, Name = "CORPORAL" },
	{ From = 20, Name = "SERGEANT" },
	{ From = 35, Name = "LIEUTENANT" },
	{ From = 50, Name = "CAPTAIN" },
	{ From = 70, Name = "MAJOR" },
	{ From = 90, Name = "COLONEL" },
	{ From = 120, Name = "GENERAL" },
})

type TMote = { Direction: Vector2, Start: Vector2, Reach: number, Size: number, Delay: number }

-- The burst a level throws off the badge: the same picture every time. Each starts just outside the badge's edge and
-- leaves along the line from its middle.
local MOTES: { TMote } = table.create(14)
do
	local random = Random.new(23)
	local half = Layout.BADGE_SIZE / 2
	for index = 1, 14 do
		local angle = (index + random:NextNumber(-0.35, 0.35)) / 14 * 2 * math.pi
		local direction = Vector2.new(math.cos(angle), math.sin(angle))
		local toEdge =
			math.min(half.X / math.max(math.abs(direction.X), 1e-3), half.Y / math.max(math.abs(direction.Y), 1e-3))
		MOTES[index] = table.freeze({
			Direction = direction,
			Start = direction * (toEdge + 6),
			Reach = random:NextNumber(50, 95),
			Size = random:NextInteger(4, 8),
			Delay = random:NextNumber(0, 0.06),
		})
	end

	table.freeze(MOTES)
end

-- One chip: its word and the Xp it carries, and when it pours (seconds after the screen went up).
type TPour = { Word: string, Amount: number, At: number, Seconds: number }

local Header = {}

function Header.RankName(level: number): string
	local name = RANKS[1].Name
	for _, rank in RANKS do
		if level >= rank.From then name = rank.Name end
	end

	return name
end

local function label(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
		props,
	})
end

-- The chips of the record, in his order, each with its slot in the pour.
local function pours(state: Types.TState): { TPour }
	local record = state.Record()
	if not record then return {} end
	local sources = {
		{ Word = "WAVES", Amount = record.XpWaves },
		{ Word = "BOSSES", Amount = record.XpBosses },
	}
	local total = 0
	for _, entry in sources do
		total += entry.Amount
	end

	local list = {}
	local count = 0
	for _, entry in sources do
		if entry.Amount > 0 then
			count += 1
		end
	end

	local at = Timing.CHIPS_DELAY + count * Timing.CHIP_STAGGER + Timing.POUR_AFTER
	for _, entry in sources do
		if entry.Amount <= 0 then continue end
		local seconds = Timing.POUR_BASE + Timing.POUR_SPAN * entry.Amount / total
		list[#list + 1] = { Word = entry.Word, Amount = entry.Amount, At = at, Seconds = seconds }
		at += seconds + Timing.POUR_GAP
	end

	return list
end

-- A steady pour that eases on and off.
local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

-- Xp formatted as he writes it: "+1,725".
local function plus(value: number): string
	return `+{Components.Commas(math.round(value))}`
end

local function chip(clock: Types.TClock, pour: TPour, index: number): Frame
	local dealAt = Timing.CHIPS_DELAY + (index - 1) * Timing.CHIP_STAGGER
	local dealt = function(): number
		return clock.Since(dealAt, Timing.CHIP)
	end
	local poured = function(): number
		return clock.Since(pour.At, pour.Seconds)
	end
	-- 1 while it pours, easing off after.
	local lit = function(): number
		local t = poured()
		if t <= 0 then return 0 end
		if t < 1 then return 1 end
		return 1 - clock.Since(pour.At + pour.Seconds, 0.3)
	end
	local words = `{pour.Word}   {plus(pour.Amount)}`

	return create("Frame")({
		Name = pour.Word,
		LayoutOrder = index,
		Size = UDim2.fromOffset(0, Layout.CHIP_HEIGHT),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		-- Unseen, the chip's words and padding: the holder's width. The chip hangs off a pin at the holder's middle
		-- because an automatic size counts its children's swell but not its grandchildren's (measured), so its swell
		-- never shoves the next chip along.
		label({
			Name = "Width",
			Size = UDim2.fromOffset(0, Layout.CHIP_HEIGHT),
			AutomaticSize = Enum.AutomaticSize.X,
			TextSize = Layout.CHIP_TEXT,
			TextTransparency = 1,
			Text = words,
			create("UIPadding")({
				PaddingLeft = UDim.new(0, Layout.CHIP_PADDING),
				PaddingRight = UDim.new(0, Layout.CHIP_PADDING),
			}),
		}),
		create("Frame")({
			Name = "Middle",
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(),
			BackgroundTransparency = 1,
			create("Frame")({
				Name = "Chip",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = function()
					return UDim2.fromOffset(0, math.round(Timing.CHIP_RISE * (1 - Motion.Decelerate(dealt()))))
				end,
				Size = UDim2.fromOffset(0, Layout.CHIP_HEIGHT),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = function()
					return Palette.Ink:Lerp(Palette.Green, 0.18 * lit())
				end,
				BackgroundTransparency = function()
					return 1 - Motion.Out(dealt()) * 0.85
				end,
				BorderSizePixel = 0,
				ClipsDescendants = true,
				create("UIStroke")({
					Color = function()
						return Colors.CHIP_EDGE:Lerp(Palette.Green, lit())
					end,
					Thickness = 2,
					Transparency = function()
						return 1 - Motion.Out(dealt())
					end,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				}),
				create("UIPadding")({
					PaddingLeft = UDim.new(0, Layout.CHIP_PADDING),
					PaddingRight = UDim.new(0, Layout.CHIP_PADDING),
				}),
				create("UIScale")({
					Scale = function()
						return 1 + Timing.POUR_SWELL * Motion.Bump(poured())
					end,
				}),
				label({
					Size = UDim2.fromScale(0, 1),
					AutomaticSize = Enum.AutomaticSize.X,
					TextSize = Layout.CHIP_TEXT,
					TextColor3 = function()
						return Palette.Green:Lerp(Palette.White, 0.5 * Motion.Bump(poured()))
					end,
					TextTransparency = function()
						return 1 - Motion.Out(dealt())
					end,
					Text = words,
				}),
				Components.Sheen(function()
					return clock.Since(pour.At, Timing.POUR_SHEEN)
				end, 5),
			}),
		}),
	})
end

function Header.Build(state: Types.TState, clock: Types.TClock): Frame
	local list = derive(function()
		return pours(state)
	end)
	-- The Xp poured so far, and where the bar stands: level and share of the next.
	local gained = derive(function(): number
		local sum = 0
		for _, pour in list() do
			sum += pour.Amount * smooth(clock.Since(pour.At, pour.Seconds))
		end
		return sum
	end)
	local value = derive(function(): number
		local record = state.Record()
		if not record then return 1 end
		return record.LevelBefore + (record.XpBefore + gained()) / 100
	end)
	local level = derive(function(): number
		return math.floor(value() + 1e-6)
	end)
	local levelText = derive(function(): string
		return `LV {level()}`
	end)
	local fillPx = derive(function(): number
		return math.round((value() - level()) * Layout.BAR_SIZE.X)
	end)
	local isPouring = derive(function(): boolean
		for _, pour in list() do
			local t = clock.Since(pour.At, pour.Seconds)
			if t > 0 and t < 1 then return true end
		end
		return false
	end)

	-- A level crossed: LV and the badge punch, the bar flashes, a ring and motes leave the badge.
	local punch, strikePunch = Hand.Kick(Timing.PUNCH_PERIOD, 0.35)
	local flash, strikeFlash = Hand.Kick(Timing.FLASH_PERIOD, 1)
	local ring, configureRing = spring(function()
		return 1
	end, Timing.RING, 1)
	local levelUpAt = vide.source(-math.huge)
	local lastLevel: number? = nil
	vide.effect(function()
		local current = level()
		vide.untrack(function()
			if lastLevel and current > lastLevel and state.IsOpen() then
				strikePunch(1)
				strikeFlash(1)
				configureRing({ position = 0, velocity = 0 })
				levelUpAt(state.Now())
			end
			lastLevel = current
		end)
	end)

	local isRinging = derive(function(): boolean
		return ring() < 0.995
	end)

	local dropped = function(): number
		return Motion.Decelerate(clock.Since(Timing.PANEL_DELAY, Timing.PANEL))
	end
	local stamped = function(): number
		return Motion.Decelerate(clock.Since(Timing.BADGE_DELAY, Timing.BADGE))
	end
	-- 1 as the badge lands, falling away.
	local badgeFlash = function(): number
		if not state.IsOpen() then return 0 end
		local left = 1 - Progress(clock.Elapsed(), Timing.BADGE_DELAY + Timing.BADGE * 0.6, Timing.BADGE_FLASH)
		return math.max(left * left, flash())
	end

	local motes = table.create(#MOTES)
	for index, mote in MOTES do
		local life = function(): number
			return Progress(state.Now(), levelUpAt(), Timing.MOTES, mote.Delay)
		end
		motes[index] = create("Frame")({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				local t = life()
				local where = mote.Start + mote.Direction * mote.Reach * (1 - (1 - t) ^ 3)
				return UDim2.new(0.5, math.round(where.X), 0.5, math.round(where.Y + 18 * t * t))
			end,
			Size = UDim2.fromOffset(mote.Size, mote.Size),
			BackgroundColor3 = if index % 3 == 0 then Palette.White else Palette.Gold,
			BorderSizePixel = 0,
			Visible = function()
				local t = life()
				return t > 0 and t < 1
			end,
			BackgroundTransparency = function()
				local t = life()
				return 1 - math.min(t / 0.08, 1) * (1 - t) ^ 1.5
			end,
		})
	end

	local margin = Layout.MARGIN
	local function group(name: string, x: number, size: Vector2, child: Instance): CanvasGroup
		return create("CanvasGroup")({
			Name = name,
			Position = function()
				local drop = Timing.PANEL_DROP * (1 - dropped())
				return UDim2.new(0.5, x - margin, 0, Layout.TOP - margin - math.round(drop))
			end,
			Size = UDim2.fromOffset(size.X + 2 * margin, size.Y + 2 * margin),
			BackgroundTransparency = 1,
			GroupTransparency = function()
				if not state.IsOpen() then return 1 - clock.Shown() end
				return 1 - Motion.Out(clock.Since(Timing.PANEL_DELAY, Timing.PANEL * 0.7))
			end,
			create("Frame")({
				Name = "Holder",
				Position = UDim2.fromOffset(margin, margin),
				Size = UDim2.fromOffset(size.X, size.Y),
				BackgroundTransparency = 1,
				child,
			}),
		})
	end

	local badge = Components.Card({
		Accent = Palette.Gold,
		Tint = 0.5,
		Edge = 3,
		Marks = true,
		Brackets = 5,
		GlowTransparency = function()
			return Motion.Lerp(0.6, 0.2, badgeFlash())
		end,
	}, {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		create("UIScale")({
			Scale = function()
				return 1 + Timing.BADGE_SCALE * (1 - stamped()) + Timing.PUNCH * punch()
			end,
		}),
		Components.Icon("Rank", {
			Name = "Rank",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = Components.GlyphBox(Layout.BADGE_GLYPH),
			ImageColor3 = function()
				return Palette.Gold:Lerp(Palette.White, 0.8 * badgeFlash())
			end,
			ZIndex = 4,
		}),
		create("Frame")({
			Name = "Flash",
			Position = UDim2.fromOffset(3, 3),
			Size = UDim2.new(1, -6, 1, -6),
			BackgroundColor3 = Palette.White,
			BorderSizePixel = 0,
			ZIndex = 5,
			Visible = function()
				return badgeFlash() > 0.01
			end,
			BackgroundTransparency = function()
				return 1 - 0.6 * badgeFlash()
			end,
		}),
	})

	local panel = Components.Panel({ Brackets = 5, Wide = true }, {
		Name = "Panel",
		Size = UDim2.fromScale(1, 1),
		create("Frame")({
			Name = "Level",
			Position = UDim2.fromOffset(Layout.LV.X, Layout.LV.Y),
			Size = UDim2.fromOffset(400, Layout.LV_TEXT),
			BackgroundTransparency = 1,
			ZIndex = 4,
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, Layout.RANK_GAP),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			-- The holder takes its width from an unseen copy. The LV that punches hangs off a pin at its middle, because
			-- an automatic size counts its children's swell but not its grandchildren's (measured), so the punch never
			-- shoves the rank along.
			create("Frame")({
				LayoutOrder = 1,
				Size = UDim2.fromOffset(0, Layout.LV_TEXT),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 1,
				label({
					Name = "Width",
					Size = UDim2.fromOffset(0, Layout.LV_TEXT),
					AutomaticSize = Enum.AutomaticSize.X,
					TextSize = Layout.LV_TEXT,
					TextTransparency = 1,
					Text = levelText,
				}),
				create("Frame")({
					Name = "Middle",
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.new(),
					BackgroundTransparency = 1,
					label({
						Name = "LV",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Size = UDim2.fromOffset(0, Layout.LV_TEXT),
						AutomaticSize = Enum.AutomaticSize.X,
						TextSize = Layout.LV_TEXT,
						Text = levelText,
						create("UIScale")({
							Scale = function()
								return 1 + Timing.PUNCH * punch()
							end,
						}),
					}),
				}),
			}),
			label({
				Name = "Rank",
				LayoutOrder = 2,
				Size = UDim2.fromOffset(0, Layout.RANK_TEXT),
				AutomaticSize = Enum.AutomaticSize.X,
				TextSize = Layout.RANK_TEXT,
				TextColor3 = Palette.Gold,
				Text = function()
					return Header.RankName(level())
				end,
			}),
		}),
		label({
			Name = "Gained",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromOffset(Layout.GAINED_RIGHT, Layout.GAINED_Y),
			Size = UDim2.fromOffset(320, Layout.GAINED_TEXT),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextSize = Layout.GAINED_TEXT,
			TextColor3 = Palette.Green,
			Text = function()
				return `{plus(gained())} XP`
			end,
			create("UIScale")({
				Scale = function()
					return if isPouring() then 1 + Timing.POUR_SWELL * 0.6 else 1
				end,
			}),
		}),
		create("Frame")({
			Name = "Track",
			Position = UDim2.fromOffset(Layout.BAR.X, Layout.BAR.Y),
			Size = UDim2.fromOffset(Layout.BAR_SIZE.X, Layout.BAR_SIZE.Y),
			BackgroundColor3 = Colors.TRACK,
			BorderSizePixel = 0,
			ZIndex = 4,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			create("Frame")({
				Name = "Fill",
				Size = function()
					return UDim2.new(0, fillPx(), 1, 0)
				end,
				BackgroundColor3 = Colors.FILL_TOP,
				BorderSizePixel = 0,
				Visible = function()
					return fillPx() > 0
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
				create("UIGradient")({
					Rotation = 90,
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Palette.White),
						ColorSequenceKeypoint.new(0.45, Color3.new(0.8, 0.9, 0.82)),
						ColorSequenceKeypoint.new(1, Color3.new(0.68, 0.86, 0.72)),
					}),
				}),
				-- The light at the fill's end while it pours.
				create("Frame")({
					Name = "Head",
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.fromScale(1, 0),
					Size = function()
						return UDim2.new(0, math.min(40, fillPx()), 1, 0)
					end,
					BackgroundColor3 = Palette.White,
					BorderSizePixel = 0,
					Visible = isPouring,
					create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
					create("UIGradient")({ Transparency = NumberSequence.new(1, 0.15) }),
				}),
			}),
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 2,
				Visible = function()
					return flash() > 0.01
				end,
				BackgroundTransparency = function()
					return 1 - 0.85 * flash()
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			}),
			label({
				Name = "Count",
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
				FontFace = Font.DisplayBold,
				TextSize = Layout.BAR_TEXT,
				ZIndex = 3,
				Text = function()
					return `{math.floor((value() - level()) * 100 + 1e-6)} / 100 XP`
				end,
				Components.Ink(Layout.BAR_TEXT),
			}),
		}),
	})

	return create("Frame")({
		Name = "Header",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		group("PanelGroup", Layout.PANEL_X, Layout.PANEL_SIZE, panel),
		group("BadgeGroup", Layout.BADGE_X, Layout.BADGE_SIZE, badge),
		-- Over the badge's middle: the ring and the motes a level throws.
		create("Frame")({
			Name = "Burst",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(
				0.5,
				Layout.BADGE_X + Layout.BADGE_SIZE.X / 2,
				0,
				Layout.TOP + Layout.BADGE_SIZE.Y / 2
			),
			Size = UDim2.fromOffset(Layout.BADGE_SIZE.X, Layout.BADGE_SIZE.Y),
			BackgroundTransparency = 1,
			ZIndex = 3,
			create("Frame")({
				Name = "Ring",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = function()
					local grow = math.round(Timing.RING_REACH * Motion.Out(ring()))
					return UDim2.new(1, 2 * grow, 1, 2 * grow)
				end,
				BackgroundTransparency = 1,
				Visible = isRinging,
				create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
				create("UIStroke")({
					Color = Palette.Gold,
					Thickness = 3,
					Transparency = ring,
					LineJoinMode = Enum.LineJoinMode.Miter,
				}),
			}),
			motes,
		}),
		create("CanvasGroup")({
			Name = "Chips",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, Layout.CHIPS_Y - Layout.MARGIN),
			Size = UDim2.new(1, 0, 0, Layout.CHIP_HEIGHT + 2 * Layout.MARGIN),
			BackgroundTransparency = 1,
			GroupTransparency = function()
				return if state.IsOpen() then 0 else 1 - clock.Shown()
			end,
			create("Frame")({
				Name = "Row",
				Position = UDim2.fromOffset(0, Layout.MARGIN),
				Size = UDim2.new(1, 0, 0, Layout.CHIP_HEIGHT),
				BackgroundTransparency = 1,
				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					Padding = UDim.new(0, Layout.CHIP_GAP),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				-- Rebuilt with each record: its chips are a new list.
				vide.values(list, function(pour: TPour, index: () -> number)
					return chip(clock, pour, vide.untrack(index))
				end),
			}),
		}),
	})
end

return Header
