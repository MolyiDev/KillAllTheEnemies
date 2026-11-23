--!nonstrict
-- The squad's tags (UIMatt.md, Lobby Entering › Player Container › Player Head Tag): over each one's head on the stage
-- (Stage), the name with MVP on the one with the most kills, the class, and the run's kills counting up. Each tag
-- follows its head on the screen (TMember.HeadAt) and is drawn smaller the farther the head is.
--
-- A tag drops in once its body has landed, its kills count up, and the MVP's badge is stamped on.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local TextService = game:GetService("TextService")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local Scrim = require(script.Parent.Scrim)
local Types = require(script.Parent.Types)

local create = vide.create
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress

local Layout = table.freeze({
	-- The tag: its box (it hangs from its bottom middle) and its rows, at the size it is drawn REF_DEPTH studs away.
	TAG = Vector2.new(440, 98),
	NAME_TEXT = 32,
	MVP = Vector2.new(79, 30),
	MVP_TEXT = 15,
	MVP_GAP = 10,
	CLASS_Y = 42,
	CLASS_TEXT = 14,
	KILLS_Y = 66,
	KILLS_TEXT = 22,
	SKULL = 20,
	KILLS_GAP = 8,
	REF_DEPTH = 17,
	-- The soft shadow under a tag: how far it reaches past the writing (its widest row, and the tag's height), its fade
	-- and how dark its middle is.
	SCRIM_REACH = Vector2.new(50, 31),
	SCRIM_FEATHER = 64,
	SCRIM_STRENGTH = 0.6,
	MIN_SCALE = 0.6,
	MAX_SCALE = 1.15,
})

local Timing = table.freeze({
	SQUAD_DELAY = 0.45,
	STAGGER = 0.24,
	WAIT_AT_MOST = 2,
	-- After the body steps on: it falls for Stage's DROP, then the tag drops in.
	TAG_DELAY = 0.5,
	TAG = 0.38,
	TAG_DROP = 18,
	KILLS_DELAY = 0.3,
	KILLS = 0.8,
	MVP_DELAY = 0.5,
	MVP = 0.28,
	MVP_SCALE = 0.7,
	MVP_FLASH = 0.4,
})

local Squad = {}

-- When `member` steps on, in seconds after the screen went up: its turn, or as its avatar arrives if that is later.
-- One whose avatar is slow to come steps on without it after a while, and drops in when it arrives.
function Squad.ArriveAt(state: Types.TState, member: Types.TMember): number
	local turn = Timing.SQUAD_DELAY + member.Order * Timing.STAGGER
	return math.max(turn, math.min(member.LoadedAt() - state.ToggledAt(), turn + Timing.WAIT_AT_MOST))
end

local function label(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
		props,
	})
end

-- How wide `member`'s tag's writing is, in the tag's own px (its widest row), for its shadow. Measured once from the
-- text: the labels' own sizes come back under the tag's UIScale, which follows the head every frame.
local function measureInfo(member: Types.TMember, className: string)
	local params = Instance.new("GetTextBoundsParams")
	params.Font = Font.Display
	local function width(text: string, size: number): number
		params.Text = text
		params.Size = size
		local isMeasured, bounds = pcall(TextService.GetTextBoundsAsync, TextService, params)
		return if isMeasured then bounds.X else 0
	end

	local name = width(string.upper(member.Name), Layout.NAME_TEXT)
	local top = name + if member.IsMvp then Layout.MVP.X + Layout.MVP_GAP else 0
	local skull = Components.GlyphBox(Layout.SKULL).X.Offset
	local kills = skull + Layout.KILLS_GAP + width(Components.Commas(member.Kills), Layout.KILLS_TEXT)
	member.InfoWidth(math.ceil(math.max(top, width(className, Layout.CLASS_TEXT), kills)))
end

local function tag(state: Types.TState, clock: Types.TClock, member: Types.TMember): CanvasGroup
	local class = DataCore.Classes.ById[member.ClassId]
	local className = if class then string.upper(class.Name) else ""
	local at = function(): number
		return Squad.ArriveAt(state, member) + Timing.TAG_DELAY
	end
	local dropped = function(): number
		return clock.Since(at(), Timing.TAG)
	end
	local counted = function(): number
		return Motion.Out(clock.Since(at() + Timing.KILLS_DELAY, Timing.KILLS))
	end
	local stamped = function(): number
		return Motion.Decelerate(clock.Since(at() + Timing.MVP_DELAY, Timing.MVP))
	end
	local mvpFlash = function(): number
		if not state.IsOpen() then return 0 end
		local left = 1 - Progress(clock.Elapsed(), at() + Timing.MVP_DELAY + Timing.MVP * 0.6, Timing.MVP_FLASH)
		return left * left
	end
	task.spawn(measureInfo, member, className)

	return create("CanvasGroup")({
		Name = "Tag",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(Layout.TAG.X, Layout.TAG.Y),
		BackgroundTransparency = 1,
		ZIndex = 5,
		GroupTransparency = function()
			if not state.IsOpen() then return 1 - clock.Shown() end
			return 1 - Motion.Out(dropped())
		end,
		create("Frame")({
			Name = "Top",
			Size = UDim2.new(1, 0, 0, Layout.NAME_TEXT + 4),
			BackgroundTransparency = 1,
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, Layout.MVP_GAP),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			if member.IsMvp
				then create("Frame")({
					Name = "Mvp",
					LayoutOrder = 1,
					Size = UDim2.fromOffset(Layout.MVP.X, Layout.MVP.Y),
					BackgroundTransparency = 1,
					create("Frame")({
						Name = "Face",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromScale(1, 1),
						BorderSizePixel = 0,
						BackgroundColor3 = function()
							return Palette.Gold:Lerp(Palette.White, mvpFlash())
						end,
						BackgroundTransparency = function()
							return 1 - Motion.Out(clock.Since(at() + Timing.MVP_DELAY, Timing.MVP * 0.5))
						end,
						create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
						create("UIScale")({
							Scale = function()
								return 1 + Timing.MVP_SCALE * (1 - stamped())
							end,
						}),
						create("UIListLayout")({
							FillDirection = Enum.FillDirection.Horizontal,
							HorizontalAlignment = Enum.HorizontalAlignment.Center,
							VerticalAlignment = Enum.VerticalAlignment.Center,
							Padding = UDim.new(0, 5),
							SortOrder = Enum.SortOrder.LayoutOrder,
						}),
						Components.Icon("Star", {
							LayoutOrder = 1,
							Size = Components.GlyphBox(13),
							ImageColor3 = Palette.Ink,
						}),
						label({
							LayoutOrder = 2,
							Size = UDim2.fromOffset(0, Layout.MVP_TEXT),
							AutomaticSize = Enum.AutomaticSize.X,
							TextSize = Layout.MVP_TEXT,
							TextColor3 = Palette.Ink,
							Text = "MVP",
						}),
					}),
				})
				else nil,
			label({
				Name = "Name",
				LayoutOrder = 2,
				Size = UDim2.fromOffset(0, Layout.NAME_TEXT),
				AutomaticSize = Enum.AutomaticSize.X,
				TextSize = Layout.NAME_TEXT,
				Text = string.upper(member.Name),
				Components.Ink(Layout.NAME_TEXT),
			}),
		}),
		label({
			Name = "Class",
			Position = UDim2.fromOffset(0, Layout.CLASS_Y),
			Size = UDim2.new(1, 0, 0, Layout.CLASS_TEXT),
			TextSize = Layout.CLASS_TEXT,
			TextColor3 = if member.IsMvp then Palette.Gold else Palette.Grey,
			Text = className,
			Components.Ink(Layout.CLASS_TEXT),
		}),
		create("Frame")({
			Name = "Kills",
			Position = UDim2.fromOffset(0, Layout.KILLS_Y),
			Size = UDim2.new(1, 0, 0, Layout.KILLS_TEXT + 2),
			BackgroundTransparency = 1,
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, Layout.KILLS_GAP),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Components.Icon("Skull", {
				LayoutOrder = 1,
				Size = Components.GlyphBox(Layout.SKULL),
				ImageColor3 = Palette.Pink,
			}),
			label({
				LayoutOrder = 2,
				Size = UDim2.fromOffset(0, Layout.KILLS_TEXT),
				AutomaticSize = Enum.AutomaticSize.X,
				TextSize = Layout.KILLS_TEXT,
				TextColor3 = Palette.Pink,
				Text = function()
					return Components.Commas(math.round(member.Kills * counted()))
				end,
				Components.Ink(Layout.KILLS_TEXT),
			}),
		}),
	})
end

-- Where `member`'s tag hangs (from its bottom middle) as it drops in over the head, drawn smaller the farther the
-- head is: one holder for the tag and one for its shadow, which go in two layers so no shadow lies over a tag.
local function over(
	state: Types.TState,
	clock: Types.TClock,
	member: Types.TMember,
	name: string,
	child: Instance
): Frame
	local dropped = function(): number
		return clock.Since(Squad.ArriveAt(state, member) + Timing.TAG_DELAY, Timing.TAG)
	end

	return create("Frame")({
		Name = `{name}{member.Order}`,
		Position = function()
			local at = member.HeadAt()
			local drop = Timing.TAG_DROP * (1 - Motion.Decelerate(dropped()))
			return UDim2.fromOffset(math.round(at.X), math.round(at.Y - drop))
		end,
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		Visible = function()
			return member.HeadAt().Z > 0
		end,
		-- Nearer ones over farther ones.
		ZIndex = function()
			return math.clamp(100 - math.round(member.HeadAt().Z), 1, 100)
		end,
		create("UIScale")({
			Scale = function()
				local depth = math.max(member.HeadAt().Z, 1)
				return math.clamp(Layout.REF_DEPTH / depth, Layout.MIN_SCALE, Layout.MAX_SCALE)
			end,
		}),
		child,
	})
end

local function shadow(state: Types.TState, clock: Types.TClock, member: Types.TMember): CanvasGroup
	local size = function(): Vector2
		return Vector2.new(member.InfoWidth(), Layout.TAG.Y) + 2 * Layout.SCRIM_REACH
	end

	return Scrim(size, Layout.SCRIM_FEATHER, Layout.SCRIM_STRENGTH, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(0, -Layout.TAG.Y / 2),
		GroupTransparency = function()
			if not state.IsOpen() then return 1 - clock.Shown() end
			return 1 - Motion.Out(clock.Since(Squad.ArriveAt(state, member) + Timing.TAG_DELAY, Timing.TAG))
		end,
	})
end

local function layer(name: string, zIndex: number, children: () -> { Instance }): Frame
	return create("Frame")({
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = zIndex,
		children,
	})
end

function Squad.Build(state: Types.TState, clock: Types.TClock): Frame
	return create("Frame")({
		Name = "Squad",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 1,
		layer(
			"Shadows",
			1,
			vide.values(state.Members, function(member: Types.TMember)
				return over(state, clock, member, "Shadow", shadow(state, clock, member))
			end)
		),
		layer(
			"Tags",
			2,
			vide.values(state.Members, function(member: Types.TMember)
				return over(state, clock, member, "Tag", tag(state, clock, member))
			end)
		),
	})
end

function Squad.Arrange(squad: { { UserId: number, Kills: number } }): ({ number }, { number }, number?)
	local order = table.create(#squad)
	for index in squad do
		order[index] = index
	end
	table.sort(order, function(a: number, b: number): boolean
		if squad[a].Kills ~= squad[b].Kills then return squad[a].Kills > squad[b].Kills end
		return squad[a].UserId < squad[b].UserId
	end)

	local slots = table.create(#squad)
	local turns = table.create(#squad)
	for rank, index in order do
		slots[index] = rank
		-- The MVP steps on last: everyone else in the order they stand, then the front.
		turns[index] = if rank == 1 then #squad - 1 else rank - 2
	end

	return slots, turns, order[1]
end

return Squad
