--!nonstrict
-- The info panel (his right panel): the picked gun's rarity, name, level as stars and three numbers, and what the next
-- step costs. Its big slab buys the gun or raises it; the bottom one equips it. TRY takes the gun to the shooting
-- range; SHOW wears it on the back, and reads HIDE on the gun worn.
--
-- One set of pieces for every state: a gun not owned prices its purchase where an owned one prices its next level,
-- and the slabs change colour and word rather than being swapped.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local LoadoutCore = require(ReplicatedStorage.GlobalShared.Core.LoadoutCore)
local Parts = require(script.Parent.Parts)
local panelTop = require(script.Parent.Parent.Parent.Utils.panelTop)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local source = vide.source
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
local Label = Parts.Label
local GUNS = DataCore.Guns.ById

-- His drawn rects in px at 1080, from the panel's top left.
local Layout = table.freeze({
	PANEL_RIGHT = 40,
	PANEL_Y = 190,
	SIZE = Vector2.new(440, 850),
	MARGIN = 48,
	TAG = Vector2.new(24, 24),
	TAG_HEIGHT = 31,
	TAG_PAD = 22,
	TAG_GAP = 17,
	TAG_TEXT = 17,
	NAME = Vector2.new(24, 66),
	NAME_SIZE = Vector2.new(392, 56),
	STAR_X = 35,
	STAR_STEP = 32,
	STAR_Y = 144,
	STAR = 23,
	STAT_XS = { 24, 158, 292 },
	STAT_Y = 176,
	STAT_SIZE = Vector2.new(122, 87),
	STAT_LABEL = Vector2.new(14, 14),
	STAT_LABEL_TEXT = 15,
	STAT_VALUE = Vector2.new(14, 36),
	STAT_VALUE_TEXT = 36,
	STAT_BONUS_DROP = 12,
	STAT_BONUS_TEXT = 17,
	HEADER_GLYPH = Vector2.new(35, 303),
	HEADER_GLYPH_SIZE = 20,
	HEADER_WORD = Vector2.new(56, 289),
	HEADER_TEXT = 29,
	HEADER_RIGHT = 416,
	HEADER_RIGHT_Y = 294,
	HEADER_RIGHT_TEXT = 18,
	HEADER_RULE = Vector2.new(24, 328),
	RULE_WIDTH = 392,
	COST = Vector2.new(24, 346),
	COST_SIZE = Vector2.new(392, 96),
	TILE = Vector2.new(12, 12),
	TILE_SIZE = 72,
	TILE_GLYPH = 40,
	COST_VALUE = Vector2.new(100, 10),
	COST_VALUE_TEXT = 40,
	COST_CURRENCY_Y = 26,
	COST_CURRENCY_TEXT = 17,
	BALANCE = Vector2.new(100, 60),
	BALANCE_TEXT = 14,
	ACTION = Vector2.new(23, 463),
	SLAB_SIZE = Vector2.new(394, 78),
	SLAB_TEXT = 30,
	EQUIP_TEXT = 33,
	SLAB_GLYPH = 30,
	TRY = Vector2.new(24, 666),
	-- A px narrower each than his, 18 apart (his 16): under a press one's brackets reach 11 px out, and his crossed.
	SHOW = Vector2.new(229, 666),
	SMALL_SIZE = Vector2.new(187, 64),
	SMALL_TEXT = 25,
	EQUIP = Vector2.new(23, 749),
})

local Timing = table.freeze({
	PANEL_DELAY = 0.1,
	PANEL_SLIDE = 40,
	BUTTONS_DELAY = 0.24,
	BUTTONS_STAGGER = 0.05,
	-- The numbers run up from nothing as the panel settles, and roll to a new gun's or level's.
	COUNT_DELAY = 0.3,
	ROLL = 0.4,
	-- The stars light one after another on the open.
	STAR_DELAY = 0.32,
	STAR_STAGGER = 0.06,
	STAR = 0.22,
	-- A new pick: its name and tag slide in.
	PICK = 0.28,
	PICK_SLIDE = 16,
	-- A level bought: its star is struck in on the purchase's overshoot and throws one gold ring.
	STAR_POP_PERIOD = 0.26,
	STAR_POP_DAMPING = 0.58,
	STAR_POP = 0.35,
	STAR_RING = 0.5,
	STAR_RING_REACH = 16,
	-- A press refused: the cost block shakes (Motion.Shake) and its numbers flash pink.
	JOLT = 7,
	JOLT_SECONDS = 0.16,
	REFUSED = 0.5,
	-- The equip slab turning green: its tick grows in.
	TICK_POP = 0.5,
	-- SHOW answered: the word rolls over (up into HIDE, down into SHOW), the button kicks, its edge flashes and throws
	-- one ring, and a glint crosses it. Putting a gun on hits harder than taking it off.
	WORD_ROLL = 0.34,
	SHOW_KICK_PERIOD = 0.28,
	SHOW_KICK_DAMPING = 0.45,
	SHOW_KICK = 0.16,
	HIDE_KICK = 0.08,
	SHOW_FLASH = 0.55,
	SHOW_RING = 0.5,
	SHOW_RING_REACH = 18,
	SHOW_GLINT = 0.4,
})

-- His colours that are not in the Palette: the stat boxes, the cost block and its tile, TRY and SHOW's edge.
local STAT_FACE = Color3.fromRGB(29, 25, 47)
local STAT_EDGE = Color3.fromRGB(54, 47, 73)
local COST_EDGE = Color3.fromRGB(90, 70, 46)
local COST_FACE = Color3.fromRGB(28, 23, 45)
local TILE_FACE = Color3.fromRGB(54, 41, 44)
local SMALL_EDGE = Color3.fromRGB(150, 28, 92)
local STAR_OFF = Color3.fromRGB(61, 57, 76)
-- The panel is raised to just under the top bar, its bottom staying put: what is written on it rides up with the top,
-- and so does the button under the cost; TRY, SHOW and EQUIP keep their place.
local lift = panelTop.Lift(Layout.PANEL_Y)

local Info = {}

-- The middle of the star for `level`, in his 1920 x 1080: Flight pours a level's Gems into it.
function Info.StarAt(level: number): Vector2
	return Vector2.new(
		1920 - Layout.PANEL_RIGHT - Layout.SIZE.X + Layout.STAR_X + Layout.STAR_STEP * (level - 1),
		Layout.PANEL_Y - lift() + Layout.STAR_Y
	)
end

-- A number as he prints a stat: whole past 100, else to one place, with no trailing ".0".
local function stat(value: number): string
	if value >= 100 then return tostring(math.round(value)) end
	local tenths = math.round(value * 10) / 10
	return if tenths == math.floor(tenths) then tostring(math.floor(tenths)) else string.format("%.1f", tenths)
end

-- A number that rolls to `target` whenever it changes, and up from 0 each time the screen opens.
local function rolled(state: Types.TWeaponsState, actions: Types.TWeaponsActions, target: () -> number): () -> number
	local from, to, at = source(0), source(0), source(-math.huge)
	local lastOpen = -math.huge
	vide.effect(function()
		local value = target()
		local opened = state.ToggledAt()
		local isOpen = state.IsOpen()
		vide.untrack(function()
			local now = os.clock()
			local current = Motion.Lerp(from(), to(), Motion.Out(Progress(now, at(), Timing.ROLL)))
			if isOpen and opened ~= lastOpen then
				lastOpen = opened
				from(0)
				at(opened + Timing.COUNT_DELAY)
			else
				from(current)
				at(now)
			end
			to(value)
			actions.Stir(Timing.COUNT_DELAY + Timing.ROLL)
		end)
	end)

	return derive(function(): number
		return Motion.Lerp(from(), to(), Motion.Out(Progress(state.Now(), at(), Timing.ROLL)))
	end)
end

-- One of his three stat boxes: its caption, its number and what the next level adds.
local function statBox(
	state: Types.TWeaponsState,
	actions: Types.TWeaponsActions,
	index: number,
	caption: string,
	value: () -> number,
	bonus: (() -> number?)?
): Frame
	local shown = rolled(state, actions, value)
	local text = derive(function(): string
		return stat(shown())
	end)

	return create("Frame")({
		Name = caption,
		Position = UDim2.fromOffset(Layout.STAT_XS[index], Layout.STAT_Y),
		Size = UDim2.fromOffset(Layout.STAT_SIZE.X, Layout.STAT_SIZE.Y),
		BackgroundColor3 = STAT_EDGE,
		BorderSizePixel = 0,
		ZIndex = 4,
		create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		create("Frame")({
			Name = "Face",
			Position = UDim2.fromOffset(1, 1),
			Size = UDim2.new(1, -2, 1, -2),
			BackgroundColor3 = STAT_FACE,
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
		}),
		Label({
			Position = UDim2.fromOffset(Layout.STAT_LABEL.X, Layout.STAT_LABEL.Y),
			Size = UDim2.fromOffset(Layout.STAT_SIZE.X - 20, Layout.STAT_LABEL_TEXT),
			FontFace = Font.DisplayBold,
			TextSize = Layout.STAT_LABEL_TEXT,
			TextColor3 = Palette.Lavender,
			Text = caption,
			ZIndex = 5,
		}),
		create("Frame")({
			Name = "Row",
			Position = UDim2.fromOffset(Layout.STAT_VALUE.X, Layout.STAT_VALUE.Y),
			Size = UDim2.fromOffset(Layout.STAT_SIZE.X - 16, Layout.STAT_VALUE_TEXT),
			BackgroundTransparency = 1,
			ZIndex = 5,
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 4),
			}),
			Label({
				LayoutOrder = 1,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Layout.STAT_VALUE_TEXT),
				TextSize = Layout.STAT_VALUE_TEXT,
				Text = text,
				ZIndex = 5,
			}),
			if bonus
				then Label({
					LayoutOrder = 2,
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromOffset(0, Layout.STAT_BONUS_TEXT + Layout.STAT_BONUS_DROP / 2),
					TextSize = Layout.STAT_BONUS_TEXT,
					TextColor3 = Palette.Green,
					Text = function()
						local amount = bonus()
						return if amount then `+{stat(amount)}` else ""
					end,
					ZIndex = 5,
				})
				else nil,
		}),
	})
end

-- His slab with a picture and a spaced-out word, both changing with `look` ({ Kind, Picture, Word }).
local function slab(
	look: () -> { Kind: string, Picture: string?, Word: string },
	hand: Hand.TReaction,
	textSize: number,
	extra: { [any]: any },
	props: { [any]: any }
): TextButton
	return Components.Button({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(Layout.SLAB_SIZE.X, Layout.SLAB_SIZE.Y),
		BackgroundTransparency = 1,
		ZIndex = 5,
		hand.Events,
		Components.Slab({
			Kind = function()
				return look().Kind
			end,
			Marks = true,
			Brackets = hand.Rise,
			GlowTransparency = function()
				return 0.6 - 0.3 * hand.Light()
			end,
		}, {
			Name = "Slab",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			create("UIScale")({ Scale = hand.Scale }),
			Hand.WashLayer(hand, 3, 3),
			Components.Sheen(hand.Glint, 3),
			-- Rebuilt when the word changes: a word's letters are laid out once.
			create("Frame")({
				Name = "Words",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 4,
				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 12),
				}),
				extra.Picture,
				derive(function()
					local word = look().Word
					return vide.untrack(function()
						local row = Components.Tracked(word, textSize, 2, Font.Display, { LayoutOrder = 2, ZIndex = 4 })
						vide.cleanup(function()
							row:Destroy()
						end)
						return row
					end)
				end),
			}),
			extra.Over,
		}),
		props,
	}) :: TextButton
end

function Info.Build(state: Types.TWeaponsState, actions: Types.TWeaponsActions, elapsed: () -> number): Frame
	local away = Parts.Away(state, elapsed, Timing.PANEL_DELAY)
	local faded = Parts.Faded(state, elapsed, Timing.PANEL_DELAY)
	local gun = derive(function()
		return GUNS[state.Selected()]
	end)
	local rarity = derive(function()
		return Parts.RARITIES[gun().Rarity]
	end)
	local level = derive(function(): number?
		return state.Levels()[gun().Id]
	end)
	local cost = derive(function(): number?
		local current = level()
		if not current then return gun().Price end
		return LoadoutCore.UpgradeCost(gun(), current)
	end)
	local canPay = derive(function(): boolean
		local price = cost()
		return price ~= nil and state.Gems() >= price and state.Pending() == nil
	end)
	-- Loadout.Sync names every tier's gun, a starter too.
	local isEquipped = derive(function(): boolean
		local current = gun()
		return state.Equipped()[current.Tier] == current.Id
	end)
	local picked = derive(function(): number
		return Progress(state.Now(), state.SelectedAt(), Timing.PICK)
	end)
	local pickSlide = function(): number
		return math.round(Timing.PICK_SLIDE * (1 - Motion.Decelerate(picked())))
	end
	local pickFade = function(): number
		return 1 - Motion.Out(picked())
	end
	local refused = derive(function(): number
		return Motion.Fade(state.Now(), state.RefusedAt(), Timing.REFUSED)
	end)
	local jolt = function(): number
		local at = state.RefusedAt()
		return Timing.JOLT * Motion.Shake(Progress(state.Now(), at, Timing.JOLT_SECONDS), at)
	end

	-- The stars: lit up to the level, each lighting in turn on the open; the one a level just bought is struck in.
	local stars = table.create(LoadoutCore.MAX_LEVEL)
	for index = 1, LoadoutCore.MAX_LEVEL do
		local lit = derive(function(): number
			local current = level() or 0
			if index > current then return 0 end
			if not state.IsOpen() then return 1 end
			return Progress(elapsed(), Timing.STAR_DELAY + Timing.STAR_STAGGER * (index - 1), Timing.STAR)
		end)
		local isStruck = derive(function(): boolean
			return state.UpgradedGun() == state.Selected()
				and level() == index
				and state.Now() >= state.UpgradedAt()
				and state.Now() < state.UpgradedAt() + Timing.STAR_RING
		end)
		local pop, strike = Hand.Kick(Timing.STAR_POP_PERIOD, Timing.STAR_POP_DAMPING)
		vide.effect(function()
			if not isStruck() then return end
			vide.untrack(function()
				strike(Timing.STAR_POP)
			end)
		end)
		local ring = derive(function(): number
			if not isStruck() then return 1 end
			return Progress(state.Now(), state.UpgradedAt(), Timing.STAR_RING)
		end)

		stars[index] = create("Frame")({
			Name = `Star{index}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.STAR_X + Layout.STAR_STEP * (index - 1), Layout.STAR_Y),
			Size = UDim2.fromOffset(Layout.STAR, Layout.STAR),
			BackgroundTransparency = 1,
			ZIndex = 4,
			create("Frame")({
				Name = "Ring",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = function()
					local grow = math.round(Timing.STAR_RING_REACH * Motion.Out(ring()))
					return UDim2.new(1, 2 * grow, 1, 2 * grow)
				end,
				BackgroundTransparency = 1,
				Visible = function()
					return ring() < 1
				end,
				create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
				create("UIStroke")({ Color = Palette.Gold, Thickness = 2, Transparency = ring }),
			}),
			Components.Picture(EIcons.Star, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = Components.PictureBox(Layout.STAR),
				ImageColor3 = function()
					return STAR_OFF:Lerp(Palette.White, lit())
				end,
				ZIndex = 4,
				create("UIScale")({
					Scale = function()
						return 1 + 0.25 * Motion.Bump(lit()) + pop()
					end,
				}),
			}),
		})
	end

	-- What the next level adds, nil when there is none to show.
	local function nextBonus(of: (gun: any, level: number) -> number): () -> number?
		return function(): number?
			local current = level()
			if not current or current >= LoadoutCore.MAX_LEVEL then return nil end
			return of(gun(), current + 1) - of(gun(), current)
		end
	end

	local actionHand = Hand.React("Operate", canPay)
	local actionLook = derive(function()
		local current = level()
		if not current then return { Kind = if canPay() then "Gold" else "Off", Picture = EIcons.Gem, Word = "BUY" } end
		if current >= LoadoutCore.MAX_LEVEL then return { Kind = "Off", Word = "MAXED" } end
		return { Kind = if canPay() then "Gold" else "Off", Picture = EIcons.Rank, Word = "UPGRADE" }
	end)
	local equipHand = Hand.React("Operate", function()
		return level() ~= nil and not isEquipped() and state.Pending() == nil
	end)
	local equipLook = derive(function()
		if not level() then return { Kind = "Off", Picture = EIcons.Lock, Word = "LOCKED" } end
		if isEquipped() then return { Kind = "Go", Picture = EIcons.Check, Word = "EQUIPPED" } end
		return { Kind = "Violet", Word = "EQUIP" }
	end)
	local tickPop, strikeTick = Hand.Kick(0.26, 0.58)
	vide.effect(function()
		state.EquippedAt()
		vide.untrack(function()
			if math.abs(os.clock() - state.EquippedAt()) < 0.1 then strikeTick(Timing.TICK_POP) end
		end)
	end)

	-- The picture sits in a slot of the words' list, which places it by its corner: it swells inside the slot instead.
	local function slabPicture(look: () -> { Picture: string? }, size: number, pop: (() -> number)?): Frame
		return create("Frame")({
			Name = "Picture",
			LayoutOrder = 1,
			Size = Components.PictureBox(size),
			BackgroundTransparency = 1,
			Visible = function()
				return look().Picture ~= nil
			end,
			ZIndex = 4,
			Components.Picture(function()
				return look().Picture or EIcons.Rank
			end, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 1),
				create("UIScale")({
					Scale = function()
						return 1 + (if pop then pop() else 0)
					end,
				}),
			}),
		})
	end

	local function small(word: string, at: Vector2, grow: UIScale, activate: (() -> ())?): TextButton
		local hand = Hand.React("Operate")
		return Components.Button({
			Name = word,
			grow,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(at.X + Layout.SMALL_SIZE.X / 2, at.Y + Layout.SMALL_SIZE.Y / 2),
			Size = UDim2.fromOffset(Layout.SMALL_SIZE.X, Layout.SMALL_SIZE.Y),
			BackgroundTransparency = 1,
			ZIndex = 5,
			Activated = function()
				hand.Commit()
				if activate then activate() end
			end,
			hand.Events,
			Components.Panel({
				Stroke = SMALL_EDGE,
				Brackets = hand.Rise,
			}, {
				Name = "Face",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 1),
				create("UIScale")({ Scale = hand.Scale }),
				Hand.WashLayer(hand, 3, 2),
				Components.Tracked(word, Layout.SMALL_TEXT, 2, Font.Display, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Color = Palette.Lavender,
					ZIndex = 4,
				}),
			}),
		}) :: TextButton
	end

	-- SHOW, or HIDE on the gun worn. Both words are on it, one in its window and the other parked above or below it, so
	-- the answer rolls one out as the other comes in rather than swapping them. Only the gun the answer was for rolls:
	-- picking another gun just reads its word.
	local function showButton(at: Vector2, grow: UIScale): TextButton
		local hand = Hand.React("Operate", function()
			return level() ~= nil and state.Pending() == nil
		end)
		local isWorn = derive(function(): boolean
			return state.Shown() == gun().Id
		end)
		local isAnswered = derive(function(): boolean
			return state.ShownFor() == state.Selected()
		end)
		local swapped = derive(function(): number
			if not isAnswered() then return 1 end
			return Progress(state.Now(), state.ShownAt(), Timing.WORD_ROLL)
		end)
		local flash = derive(function(): number
			if not isAnswered() then return 0 end
			return Motion.Fade(state.Now(), state.ShownAt(), Timing.SHOW_FLASH)
		end)
		local ring = derive(function(): number
			if not isAnswered() then return 1 end
			return Progress(state.Now(), state.ShownAt(), Timing.SHOW_RING)
		end)
		local sweep = derive(function(): number
			if not isAnswered() then return 1 end
			return Progress(state.Now(), state.ShownAt(), Timing.SHOW_GLINT)
		end)
		local kick, strikeKick = Hand.Kick(Timing.SHOW_KICK_PERIOD, Timing.SHOW_KICK_DAMPING)
		vide.effect(function()
			state.ShownAt()
			vide.untrack(function()
				if os.clock() - state.ShownAt() > 0.1 then return end
				strikeKick(if state.Shown() ~= 0 then Timing.SHOW_KICK else Timing.HIDE_KICK)
			end)
		end)
		-- What the edge and the ring flash in: green as a gun goes on, the words' lavender as it comes off.
		local flashColor = function(): Color3
			return if isWorn() then Palette.Green else Palette.Lavender
		end

		-- A word's place in the window: 0 in it, 1 a whole button below, -1 one above.
		local function wordAt(isHide: boolean): () -> UDim2
			return function()
				local t = swapped()
				local isCurrent = isHide == isWorn()
				-- Into HIDE the words go up, into SHOW down: the new one comes from the far side and sails a touch past,
				-- the old one a whole button ahead of it, so the two never overlap.
				local from = if isWorn() then 1 else -1
				local along = from * (1 - Motion.OutBack(t))
				if not isCurrent then
					along -= from
				end
				return UDim2.new(0.5, 0, 0.5, math.round(along * Layout.SMALL_SIZE.Y))
			end
		end

		local function word(text: string, isHide: boolean): Frame
			return Components.Tracked(text, Layout.SMALL_TEXT, 2, Font.Display, {
				Name = text,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = wordAt(isHide),
				Color = function()
					return Palette.Lavender:Lerp(Palette.White, flash())
				end,
				ZIndex = 4,
			})
		end

		return Components.Button({
			Name = "Show",
			grow,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(at.X + Layout.SMALL_SIZE.X / 2, at.Y + Layout.SMALL_SIZE.Y / 2),
			Size = UDim2.fromOffset(Layout.SMALL_SIZE.X, Layout.SMALL_SIZE.Y),
			BackgroundTransparency = 1,
			ZIndex = 5,
			Activated = function()
				hand.Commit()
				actions.Show()
			end,
			hand.Events,
			-- The one ring, round the button's own rect; at rest it is back at the rect, so it shows from there.
			create("Frame")({
				Name = "Ring",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = function()
					local t = ring()
					local grown = if t < 1 then math.round(Timing.SHOW_RING_REACH * Motion.Out(t)) else 0
					return UDim2.new(1, 2 * grown, 1, 2 * grown)
				end,
				BackgroundTransparency = 1,
				Visible = function()
					return ring() < 1
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
				create("UIStroke")({ Color = flashColor, Thickness = 2, Transparency = ring }),
			}),
			Components.Panel({
				Stroke = function()
					return SMALL_EDGE:Lerp(flashColor(), flash())
				end,
				Brackets = hand.Rise,
			}, {
				Name = "Face",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 1),
				create("UIScale")({
					Scale = function()
						return hand.Scale() + kick()
					end,
				}),
				Hand.WashLayer(hand, 3, 2),
				Components.Sheen(Hand.Sheen(hand, sweep), 3),
				create("Frame")({
					Name = "Window",
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					ClipsDescendants = true,
					ZIndex = 4,
					word("SHOW", false),
					word("HIDE", true),
				}),
			}),
		}) :: TextButton
	end

	-- A button growing onto its size after the panel lands, in turn down the panel.
	local function grown(order: number): UIScale
		local hidden = Parts.Away(state, elapsed, Timing.BUTTONS_DELAY + Timing.BUTTONS_STAGGER * (order - 1))
		return create("UIScale")({
			Scale = function()
				return 1 - hidden()
			end,
		})
	end

	local margin = Layout.MARGIN
	local size = function(): UDim2
		return UDim2.fromOffset(Layout.SIZE.X, Layout.SIZE.Y + lift())
	end

	-- The panel and what is written on it fade as one picture in a group with room for its shadow. The buttons are not
	-- in it: they move under the hand, and a group redraws its whole canvas for every frame of that. They grow in on
	-- their own instead.
	return create("Frame")({
		Name = "Info",
		AnchorPoint = Vector2.new(1, 0),
		Position = function()
			return UDim2.new(
				1,
				-Layout.PANEL_RIGHT + math.round(Timing.PANEL_SLIDE * away()),
				0,
				Layout.PANEL_Y - lift()
			)
		end,
		Size = size,
		BackgroundTransparency = 1,
		ZIndex = 2,
		create("CanvasGroup")({
			Name = "Chrome",
			Position = UDim2.fromOffset(-margin, -margin),
			Size = UDim2.new(1, 2 * margin, 1, 2 * margin),
			BackgroundTransparency = 1,
			GroupTransparency = faded,
			Components.Panel({ Brackets = true, Tall = true }, {
				Name = "Panel",
				Position = UDim2.fromOffset(margin, margin),
				Size = size,
				create("Frame")({
					Name = "Tags",
					Position = function()
						return UDim2.fromOffset(Layout.TAG.X + pickSlide(), Layout.TAG.Y)
					end,
					Size = UDim2.fromOffset(Layout.NAME_SIZE.X, Layout.TAG_HEIGHT),
					BackgroundTransparency = 1,
					ZIndex = 4,
					create("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, Layout.TAG_GAP),
					}),
					create("Frame")({
						Name = "Rarity",
						LayoutOrder = 1,
						AutomaticSize = Enum.AutomaticSize.X,
						Size = UDim2.fromOffset(0, Layout.TAG_HEIGHT),
						BackgroundColor3 = function()
							return rarity().Accent
						end,
						BorderSizePixel = 0,
						ZIndex = 4,
						create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
						create("UIPadding")({
							PaddingLeft = UDim.new(0, Layout.TAG_PAD),
							PaddingRight = UDim.new(0, Layout.TAG_PAD),
						}),
						Label({
							AutomaticSize = Enum.AutomaticSize.X,
							Size = UDim2.fromScale(0, 1),
							TextYAlignment = Enum.TextYAlignment.Center,
							TextSize = Layout.TAG_TEXT,
							TextColor3 = function()
								return if rarity().IsInk then Palette.Ink else Palette.White
							end,
							TextTransparency = pickFade,
							Text = function()
								return rarity().Text
							end,
							ZIndex = 5,
						}),
					}),
					Label({
						Name = "Type",
						LayoutOrder = 2,
						AutomaticSize = Enum.AutomaticSize.X,
						Size = UDim2.fromOffset(0, Layout.TAG_TEXT),
						TextSize = Layout.TAG_TEXT,
						TextColor3 = function()
							return rarity().Accent
						end,
						TextTransparency = pickFade,
						Text = function()
							return string.upper(gun().Hold)
						end,
					}),
				}),
				Label({
					Name = "Name",
					Position = function()
						return UDim2.fromOffset(Layout.NAME.X + pickSlide(), Layout.NAME.Y)
					end,
					Size = UDim2.fromOffset(Layout.NAME_SIZE.X, Layout.NAME_SIZE.Y),
					TextScaled = true,
					TextYAlignment = Enum.TextYAlignment.Center,
					TextTransparency = pickFade,
					Text = function()
						return string.upper(gun().Name)
					end,
					create("UITextSizeConstraint")({ MaxTextSize = Layout.NAME_SIZE.Y }),
				}),
				stars,
				statBox(state, actions, 1, "DMG / SEC", function()
					return LoadoutCore.DamagePerSecond(gun(), level() or 1)
				end, nextBonus(LoadoutCore.DamagePerSecond)),
				statBox(state, actions, 2, "DAMAGE", function()
					return LoadoutCore.Damage(gun(), level() or 1)
				end, nextBonus(LoadoutCore.Damage)),
				statBox(state, actions, 3, "FIRE RATE", function()
					return LoadoutCore.FireRate(gun())
				end),
				Components.Picture(EIcons.Rank, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(Layout.HEADER_GLYPH.X, Layout.HEADER_GLYPH.Y),
					Size = Components.PictureBox(Layout.HEADER_GLYPH_SIZE),
					ZIndex = 4,
				}),
				Label({
					Name = "Header",
					Position = UDim2.fromOffset(Layout.HEADER_WORD.X, Layout.HEADER_WORD.Y),
					Size = UDim2.fromOffset(240, Layout.HEADER_TEXT),
					TextSize = Layout.HEADER_TEXT,
					TextColor3 = Palette.Gold,
					Text = function()
						return if level() then "UPGRADE" else "UNLOCK"
					end,
				}),
				Label({
					Name = "Level",
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.fromOffset(Layout.HEADER_RIGHT, Layout.HEADER_RIGHT_Y),
					Size = UDim2.fromOffset(200, Layout.HEADER_RIGHT_TEXT),
					TextXAlignment = Enum.TextXAlignment.Right,
					FontFace = Font.DisplayBold,
					TextSize = Layout.HEADER_RIGHT_TEXT,
					Text = function()
						local current = level()
						if not current then return "LOCKED" end
						if current >= LoadoutCore.MAX_LEVEL then return `LV {current}  MAX` end
						return `LV {current}  →  {current + 1}`
					end,
				}),
				create("Frame")({
					Name = "Rule",
					Position = UDim2.fromOffset(Layout.HEADER_RULE.X, Layout.HEADER_RULE.Y),
					Size = UDim2.fromOffset(Layout.RULE_WIDTH, 1),
					BackgroundColor3 = Parts.RULE,
					BorderSizePixel = 0,
					ZIndex = 4,
				}),
				create("Frame")({
					Name = "Cost",
					Position = function()
						return UDim2.fromOffset(Layout.COST.X + math.round(jolt()), Layout.COST.Y)
					end,
					Size = UDim2.fromOffset(Layout.COST_SIZE.X, Layout.COST_SIZE.Y),
					BackgroundColor3 = COST_EDGE,
					BorderSizePixel = 0,
					ZIndex = 4,
					create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
					create("Frame")({
						Name = "Face",
						Position = UDim2.fromOffset(1, 1),
						Size = UDim2.new(1, -2, 1, -2),
						BackgroundColor3 = COST_FACE,
						BorderSizePixel = 0,
						create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
					}),
					create("Frame")({
						Name = "Tile",
						Position = UDim2.fromOffset(Layout.TILE.X, Layout.TILE.Y),
						Size = UDim2.fromOffset(Layout.TILE_SIZE, Layout.TILE_SIZE),
						BackgroundColor3 = Parts.GOLD_EDGE,
						BorderSizePixel = 0,
						ZIndex = 2,
						create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
						create("Frame")({
							Position = UDim2.fromOffset(2, 2),
							Size = UDim2.new(1, -4, 1, -4),
							BackgroundColor3 = TILE_FACE,
							BorderSizePixel = 0,
							create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
						}),
						Components.Picture(EIcons.Gem, {
							AnchorPoint = Vector2.new(0.5, 0.5),
							Position = UDim2.fromScale(0.5, 0.5),
							Size = Components.PictureBox(Layout.TILE_GLYPH),
							ZIndex = 3,
						}),
					}),
					create("Frame")({
						Name = "Price",
						Position = UDim2.fromOffset(Layout.COST_VALUE.X, Layout.COST_VALUE.Y),
						Size = UDim2.fromOffset(280, Layout.COST_VALUE_TEXT),
						BackgroundTransparency = 1,
						ZIndex = 3,
						create("UIListLayout")({
							FillDirection = Enum.FillDirection.Horizontal,
							VerticalAlignment = Enum.VerticalAlignment.Bottom,
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0, 8),
						}),
						Label({
							LayoutOrder = 1,
							AutomaticSize = Enum.AutomaticSize.X,
							Size = UDim2.fromOffset(0, Layout.COST_VALUE_TEXT),
							TextSize = Layout.COST_VALUE_TEXT,
							TextColor3 = function()
								return Palette.Gold:Lerp(Palette.Pink, refused())
							end,
							Text = function()
								local price = cost()
								return if price then Components.Commas(price) else "MAX"
							end,
							ZIndex = 3,
						}),
						Label({
							LayoutOrder = 2,
							AutomaticSize = Enum.AutomaticSize.X,
							Size = UDim2.fromOffset(0, Layout.COST_CURRENCY_TEXT + 6),
							TextSize = Layout.COST_CURRENCY_TEXT,
							TextColor3 = Palette.Gold,
							Text = function()
								return if cost() then "GEMS" else ""
							end,
							ZIndex = 3,
						}),
					}),
					Label({
						Name = "Balance",
						Position = UDim2.fromOffset(Layout.BALANCE.X, Layout.BALANCE.Y),
						Size = UDim2.fromOffset(280, Layout.BALANCE_TEXT),
						FontFace = Font.DisplayBold,
						TextSize = Layout.BALANCE_TEXT,
						TextColor3 = function()
							return Palette.Lavender:Lerp(Palette.Pink, refused())
						end,
						Text = function()
							if not cost() then return `LEVEL {LoadoutCore.MAX_LEVEL} OF {LoadoutCore.MAX_LEVEL}` end
							return `YOU HAVE {Components.Commas(state.Gems())}`
						end,
						ZIndex = 3,
					}),
				}),
			}),
		}),
		-- His rect, so the bottom buttons keep their place as the panel grows over them.
		create("Frame")({
			Name = "Buttons",
			Position = function()
				return UDim2.fromOffset(0, lift())
			end,
			Size = UDim2.fromOffset(Layout.SIZE.X, Layout.SIZE.Y),
			BackgroundTransparency = 1,
			ZIndex = 2,
			slab(actionLook, actionHand, Layout.SLAB_TEXT, {
				Picture = slabPicture(actionLook, Layout.SLAB_GLYPH),
			}, {
				Name = "Action",
				grown(1),
				-- Under the cost it pays, so it rides up with what is written on the panel.
				Position = function()
					return UDim2.fromOffset(
						Layout.ACTION.X + Layout.SLAB_SIZE.X / 2,
						Layout.ACTION.Y + Layout.SLAB_SIZE.Y / 2 - lift()
					)
				end,
				Activated = function()
					actionHand.Commit()
					if level() then
						actions.Upgrade()
					else
						actions.Buy()
					end
				end,
			}),
			small("TRY", Layout.TRY, grown(2), actions.Try),
			showButton(Layout.SHOW, grown(3)),
			slab(equipLook, equipHand, Layout.EQUIP_TEXT, {
				Picture = slabPicture(equipLook, Layout.SLAB_GLYPH, tickPop),
			}, {
				Name = "Equip",
				grown(4),
				Position = UDim2.fromOffset(
					Layout.EQUIP.X + Layout.SLAB_SIZE.X / 2,
					Layout.EQUIP.Y + Layout.SLAB_SIZE.Y / 2
				),
				Activated = function()
					equipHand.Commit()
					actions.Equip()
				end,
			}),
		}),
	})
end

return Info
