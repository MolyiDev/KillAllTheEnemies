--!nonstrict
-- The weapon list (his left panel): the tier on show, its guns owned and not, each as his card with the gun's own model
-- on it. A tier's cards are dealt in when the screen opens and when the tier is picked, and swept away as another is.
-- Within a tier the cards glide to their places, so a gun bought crosses from NOT OWNED into OWNED; the white ring
-- glides to the picked card and the green tick to the card its tier holds.
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
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local spring = vide.spring
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
local Label = Parts.Label
local GUNS = DataCore.Guns.ById
-- His price chip's face, darker than the cost block's tile.
local CHIP_FACE = Color3.fromRGB(26, 20, 34)

-- His drawn rects in px at 1080, from the panel's top left.
local Layout = table.freeze({
	PANEL = Vector2.new(40, 190),
	SIZE = Vector2.new(440, 850),
	-- The room round the panel inside the group that fades it, for its shadow and brackets.
	MARGIN = 48,
	BRACKETS = 5,
	-- The header: the rifle's middle and longer side, the tier, the count's right edge, the rule.
	RIFLE = Vector2.new(35, 39),
	RIFLE_GLYPH = 19,
	TITLE = Vector2.new(56, 24),
	TITLE_TEXT = 29,
	COUNT_RIGHT = 419,
	COUNT_Y = 30,
	COUNT_TEXT = 18,
	RULE = Vector2.new(24, 64),
	RULE_WIDTH = 392,
	-- A section: its word, its count badge, and the cards under it.
	SECTION_X = 24,
	SECTION_TEXT = 17,
	BADGE_DROP = -4,
	BADGE = 26,
	BADGE_TEXT = 16,
	OWNED_BADGE_X = 106,
	LOCKED_BADGE_X = 150,
	OWNED_Y = 84,
	-- From a section's word to its first row, and from a section's last row to the next word.
	ROWS_DROP = 32,
	SECTION_GAP = 30,
	CARD_XS = { 24, 160, 296 },
	CARD = Vector2.new(120, 150),
	ROW_STEP = 166,
	-- Inside a card: the gun's box and middle, the rule over the name band, the name, the corner badges.
	GUN_BOX = 92,
	GUN = Vector2.new(60, 62),
	CARD_RULE = Vector2.new(12, 117),
	CARD_RULE_WIDTH = 96,
	NAME_Y = 126,
	NAME_TEXT = 15,
	CORNER_BADGE = 24,
	CORNER_LEFT = Vector2.new(8, 8),
	CORNER_RIGHT = Vector2.new(88, 8),
	CHIP_HEIGHT = 26,
	CHIP_TEXT = 14,
	CHIP_GEM = 15,
	CARD_BRACKETS = 6,
	RING = 5,
})

local Timing = table.freeze({
	-- The panel arrives first: picking a gun is what the screen is for.
	PANEL_DELAY = 0,
	PANEL_SLIDE = 40,
	-- Its cards grow onto their places one after another as it settles, and as a tier is picked.
	DEAL_DELAY = 0.12,
	DEAL_STAGGER = 0.035,
	DEAL = 0.3,
	-- A tier picked: the old cards shrink away first.
	SWEEP = 0.12,
	-- The header's tier slides in as it changes.
	TITLE = 0.25,
	TITLE_SLIDE = 14,
	-- A card or a badge gliding to a new place.
	GLIDE_PERIOD = 0.32,
	GLIDE_DAMPING = 0.82,
	-- A purchase landing on its card: the colour floods in, the lock is thrown off, the card flashes and throws one
	-- ring, and pops on the purchase's overshoot (UI.md 5c: the one flourish the screen keeps).
	UNLOCK = 0.4,
	-- It stays in its place this long after the Gems land, then glides into OWNED.
	HOLD = 0.5,
	LOCK_THROW = 0.35,
	LOCK_RISE = 18,
	FLASH = 0.45,
	RING = 0.5,
	RING_REACH = 24,
	POP_PERIOD = 0.26,
	POP_DAMPING = 0.58,
	POP = 0.16,
	-- A count changing punches its badge.
	COUNT_PERIOD = 0.3,
	COUNT_DAMPING = 0.5,
	COUNT_PUNCH = 0.3,
	HOVER_BRACKETS = 4,
})

local List = {}

-- A section's count, punched as it changes and gone while it is zero. A group, so its edge, face and number fade as
-- one: faded layer by layer, the edge shows through the face.
local function countBadge(kind: string, count: () -> number, at: () -> Vector2, faded: () -> number): CanvasGroup
	local punch, strike = Hand.Kick(Timing.COUNT_PERIOD, Timing.COUNT_DAMPING)
	local last = nil
	vide.effect(function()
		local current = count()
		vide.untrack(function()
			if last and current ~= last then strike(Timing.COUNT_PUNCH) end
			last = current
		end)
	end)

	local isOwned = kind == "Owned"
	local face = if isOwned
		then create("Frame")({
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Palette.Green,
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		})
		else Components.Plaque({ Size = UDim2.fromScale(1, 1) })

	return create("CanvasGroup")({
		Name = kind .. "Count",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			local position = at()
			return UDim2.fromOffset(position.X + Layout.BADGE / 2, position.Y + Layout.BADGE / 2)
		end,
		Size = UDim2.fromOffset(Layout.BADGE, Layout.BADGE),
		BackgroundTransparency = 1,
		GroupTransparency = faded,
		Visible = function()
			return count() > 0
		end,
		ZIndex = 4,
		create("UIScale")({
			Scale = function()
				return 1 + punch()
			end,
		}),
		face,
		Label({
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextSize = Layout.BADGE_TEXT,
			TextColor3 = if isOwned then Palette.Ink else Palette.White,
			Text = function()
				return tostring(count())
			end,
			ZIndex = 5,
		}),
	})
end

-- The price on a card not owned: his dark chip with a gold edge, a gem and the price.
local function priceChip(gun, props: { [any]: any }): Frame
	return create("Frame")({
		Name = "Price",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, Layout.CHIP_HEIGHT),
		BackgroundColor3 = Parts.GOLD_EDGE,
		BorderSizePixel = 0,
		create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		create("Frame")({
			Name = "Face",
			AutomaticSize = Enum.AutomaticSize.X,
			Position = UDim2.fromOffset(1, 1),
			Size = UDim2.fromOffset(0, Layout.CHIP_HEIGHT - 2),
			BackgroundColor3 = CHIP_FACE,
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
			create("UIPadding")({ PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 6) }),
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 4),
			}),
			Components.Icon("Gem", {
				LayoutOrder = 1,
				Size = Components.GlyphBox(Layout.CHIP_GEM),
				ImageColor3 = Palette.Gold,
			}),
			Label({
				LayoutOrder = 2,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Layout.CHIP_TEXT),
				TextSize = Layout.CHIP_TEXT,
				TextColor3 = Palette.Gold,
				Text = Components.Commas(gun.Price),
			}),
		}),
		props,
	})
end

-- Where each of a tier's guns stands in the panel, its centre, owned first and then the rest, each in its tier's order;
-- and where each section's word starts. `held` (a gun Id, 0 for none) is kept where it was: a gun just bought unlocks
-- in its place before it moves.
local function arrange(guns, levels: { [number]: number }, held: number)
	local owned, locked = {}, {}
	for _, gun in guns do
		table.insert(if levels[gun.Id] and gun.Id ~= held then owned else locked, gun)
	end

	local places = {}
	local function place(list, top: number): number
		for index, gun in list do
			local column = (index - 1) % 3 + 1
			local row = (index - 1) // 3
			places[gun.Id] =
				Vector2.new(Layout.CARD_XS[column] + Layout.CARD.X / 2, top + row * Layout.ROW_STEP + Layout.CARD.Y / 2)
		end
		local rows = math.max(1, math.ceil(#list / 3))
		return top + (rows - 1) * Layout.ROW_STEP + Layout.CARD.Y
	end

	local ownedBottom = place(owned, Layout.OWNED_Y + Layout.ROWS_DROP)
	local lockedY = ownedBottom + Layout.SECTION_GAP
	place(locked, lockedY + Layout.ROWS_DROP)

	return { Places = places, Owned = #owned, Locked = #locked, LockedY = lockedY }
end

-- One gun's card.
local function card(
	state: Types.TWeaponsState,
	actions: Types.TWeaponsActions,
	gun,
	place: () -> Vector2,
	dealt: () -> number
): TextButton
	local rarity = Parts.RARITIES[gun.Rarity]
	local accent = rarity.Accent
	local hand = Hand.React("Take")
	local level = derive(function(): number?
		return state.Levels()[gun.Id]
	end)
	local isSelected = derive(function(): boolean
		return state.Selected() == gun.Id
	end)
	-- 0 to 1 as a purchase lands on this card; 1 once it is owned, 0 while it is not.
	local unlocked = derive(function(): number
		if state.BoughtGun() == gun.Id then
			local t = Progress(state.Now(), state.BoughtAt(), Timing.UNLOCK)
			if t < 1 then return t end
		end
		return if level() then 1 else 0
	end)
	local isLockShown = derive(function(): boolean
		if state.BoughtGun() == gun.Id and state.Now() < state.BoughtAt() + Timing.LOCK_THROW then return true end
		return level() == nil
	end)
	local thrown = derive(function(): number
		if state.BoughtGun() ~= gun.Id then return 0 end
		return Progress(state.Now(), state.BoughtAt(), Timing.LOCK_THROW)
	end)
	local flash = derive(function(): number
		if state.BoughtGun() ~= gun.Id then return 0 end
		return Motion.Fade(state.Now(), state.BoughtAt(), Timing.FLASH)
			* (if state.Now() >= state.BoughtAt() then 1 else 0)
	end)
	local ring = derive(function(): number
		if state.BoughtGun() ~= gun.Id then return 1 end
		return Progress(state.Now(), state.BoughtAt(), Timing.RING)
	end)
	local canUpgrade = derive(function(): boolean
		local current = level()
		if not current then return false end
		local cost = LoadoutCore.UpgradeCost(gun, current)
		return cost ~= nil and state.Gems() >= cost
	end)

	-- The purchase's pop, struck the frame the Gems land.
	local pop, strikePop = Hand.Kick(Timing.POP_PERIOD, Timing.POP_DAMPING)
	local hasLanded = derive(function(): boolean
		return state.BoughtGun() == gun.Id and state.Now() >= state.BoughtAt()
	end)
	vide.effect(function()
		if not hasLanded() then return end
		vide.untrack(function()
			if Progress(state.Now(), state.BoughtAt(), Timing.UNLOCK) < 0.5 then strikePop(Timing.POP) end
		end)
	end)

	local tint = derive(function(): Color3
		return Parts.LOCKED_TINT:Lerp(Palette.White, Motion.Out(unlocked()))
	end)

	return Components.Button({
		Name = gun.Name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			local at = place()
			return UDim2.fromOffset(math.round(at.X), math.round(at.Y))
		end,
		Size = UDim2.fromOffset(Layout.CARD.X, Layout.CARD.Y),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Activated = function()
			hand.Commit()
			actions.Select(gun.Id)
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return Motion.Decelerate(dealt()) * (hand.Scale() + pop())
			end,
		}),
		-- The purchase's one ring, the card's own outline grown off it.
		create("Frame")({
			Name = "Burst",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = function()
				local grow = math.round(Timing.RING_REACH * Motion.Out(ring()))
				return UDim2.new(1, 2 * grow, 1, 2 * grow)
			end,
			BackgroundTransparency = 1,
			Visible = function()
				return ring() < 1
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
			create("UIStroke")({ Color = accent, Thickness = 3, Transparency = ring }),
		}),
		Components.Card({
			Accent = Parts.EdgeOf(accent),
			Glow = accent,
			GlowTransparency = function()
				return 0.7 - 0.35 * math.max(hand.Light(), flash())
			end,
			Tint = 0.35,
			Marks = true,
			Brackets = function()
				return Layout.CARD_BRACKETS + Timing.HOVER_BRACKETS * hand.Rise()
			end,
			BracketLength = 20,
			BracketTransparency = function()
				return if isSelected() then 1 else 0.6 - 0.3 * hand.Light()
			end,
		}, {
			Name = "Card",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 3, 2),
			Components.Sheen(hand.Glint, 3),
			Parts.Gun(function()
				return gun.Id
			end, {
				Tint = tint,
				Transparency = function()
					return Parts.LOCKED_TRANSPARENCY * (1 - unlocked())
				end,
			}, {
				Name = "Gun",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(Layout.GUN.X, Layout.GUN.Y),
				Size = UDim2.fromOffset(Layout.GUN_BOX, Layout.GUN_BOX),
				ZIndex = 4,
				create("UIScale")({
					Scale = function()
						return 1 + 0.08 * hand.Rise()
					end,
				}),
			}),
			create("Frame")({
				Name = "Rule",
				Position = UDim2.fromOffset(Layout.CARD_RULE.X, Layout.CARD_RULE.Y),
				Size = UDim2.fromOffset(Layout.CARD_RULE_WIDTH, 2),
				BackgroundColor3 = accent,
				BackgroundTransparency = 0.6,
				BorderSizePixel = 0,
				ZIndex = 4,
			}),
			Label({
				Name = "Name",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromOffset(Layout.CARD.X / 2, Layout.NAME_Y),
				Size = UDim2.fromOffset(Layout.CARD.X - 12, Layout.NAME_TEXT),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextScaled = true,
				TextColor3 = function()
					return Palette.Lavender:Lerp(Palette.White, unlocked())
				end,
				Text = string.upper(gun.Name),
				create("UITextSizeConstraint")({ MaxTextSize = Layout.NAME_TEXT }),
			}),
			Parts.Badge("Upgrade", Layout.CORNER_BADGE, {
				Name = "CanUpgrade",
				Position = UDim2.fromOffset(Layout.CORNER_LEFT.X, Layout.CORNER_LEFT.Y),
				Visible = canUpgrade,
				ZIndex = 5,
			}),
			-- Gone the frame the purchase lands, under the card's flash.
			priceChip(gun, {
				Position = UDim2.fromOffset(Layout.CORNER_LEFT.X, Layout.CORNER_LEFT.Y),
				Visible = function()
					return level() == nil
				end,
				ZIndex = 5,
			}),
			-- Thrown off as the purchase lands: up, turning, growing and fading as one picture.
			create("CanvasGroup")({
				Name = "Lock",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = function()
					return UDim2.fromOffset(
						Layout.CORNER_RIGHT.X + Layout.CORNER_BADGE / 2,
						Layout.CORNER_RIGHT.Y
							+ Layout.CORNER_BADGE / 2
							- math.round(Timing.LOCK_RISE * Motion.Out(thrown()))
					)
				end,
				Size = UDim2.fromOffset(Layout.CORNER_BADGE, Layout.CORNER_BADGE),
				Rotation = function()
					return 25 * Motion.Out(thrown())
				end,
				BackgroundTransparency = 1,
				GroupTransparency = thrown,
				Visible = isLockShown,
				ZIndex = 6,
				create("UIScale")({
					Scale = function()
						return 1 + 0.5 * Motion.Out(thrown())
					end,
				}),
				Parts.Badge("Lock", Layout.CORNER_BADGE, {}),
			}),
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 7,
				Visible = function()
					return flash() > 0.01
				end,
				BackgroundTransparency = function()
					return 1 - 0.75 * flash()
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			}),
		}),
	}) :: TextButton
end

-- One tier's cards, its two sections' words and counts, the ring and the tick, for vide.switch: grown in when the tier
-- comes up and shrunk away when another does.
local function tierPage(
	state: Types.TWeaponsState,
	actions: Types.TWeaponsActions,
	tier: number,
	present: () -> boolean
)
	local guns = LoadoutCore.ByTier[tier]
	-- Only a page whose tier has the purchase reads the clock for it.
	local held = derive(function(): number
		local bought = GUNS[state.BoughtGun()]
		if not bought or bought.Tier ~= tier then return 0 end
		return if state.Now() < state.BoughtAt() + Timing.HOLD then bought.Id else 0
	end)
	local arranged = derive(function()
		return arrange(guns, state.Levels(), held())
	end)
	-- When this page's cards start growing in: the later of the open and the pick of the tier.
	local builtAt = os.clock()
	actions.Stir(Timing.DEAL_DELAY + Timing.DEAL * 3)
	local function dealt(order: number): () -> number
		return derive(function(): number
			if not present() then return 1 - Motion.Accelerate(Progress(state.Now(), state.TierAt(), Timing.SWEEP)) end
			-- The cards are not under the panel's fade (List.Build), so they shrink away with the shut on their own.
			if not state.IsOpen() then
				return 1 - Motion.Accelerate(Progress(state.Now(), state.ToggledAt(), Parts.Timing.CLOSE))
			end
			local from = math.max(state.ToggledAt() + Timing.DEAL_DELAY, builtAt + Timing.SWEEP)
			return Progress(state.Now(), from, Timing.DEAL, Timing.DEAL_STAGGER * (order - 1))
		end)
	end

	local children = {}
	local glides = {}
	for order, gun in guns do
		local target = derive(function(): Vector2
			return arranged().Places[gun.Id]
		end)
		local glide = spring(target, Timing.GLIDE_PERIOD, Timing.GLIDE_DAMPING)
		glides[gun.Id] = glide
		children[order] = card(state, actions, gun, glide, dealt(order))
	end

	local whole = dealt(1)
	local sectionsFade = derive(function(): number
		return 1 - Motion.Out(whole())
	end)

	-- The ring on the picked card and the tick on the one the tier holds, each one piece gliding between cards.
	local selectedAt = derive(function(): Vector2?
		local glide = glides[state.Selected()]
		return if glide then glide() else nil
	end)
	local equippedGun = derive(function(): number
		return state.Equipped()[tier] or LoadoutCore.Starters[tier].Id
	end)
	local tickTarget = derive(function(): Vector2
		return arranged().Places[equippedGun()] or Vector2.zero
	end)
	local tick = spring(tickTarget, Timing.GLIDE_PERIOD, Timing.GLIDE_DAMPING)
	local tickPop, strikeTick = Hand.Kick(0.3, 0.5)
	vide.effect(function()
		state.EquippedAt()
		vide.untrack(function()
			if state.Now() - state.EquippedAt() < 1 then strikeTick(0.35) end
		end)
	end)

	local page = create("Frame")({
		Name = `Tier{tier}`,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Label({
			Name = "Owned",
			Position = UDim2.fromOffset(Layout.SECTION_X, Layout.OWNED_Y),
			Size = UDim2.fromOffset(200, Layout.SECTION_TEXT),
			TextSize = Layout.SECTION_TEXT,
			TextColor3 = Palette.Lavender,
			TextTransparency = sectionsFade,
			Text = "OWNED",
		}),
		countBadge("Owned", function()
			return arranged().Owned
		end, function()
			return Vector2.new(Layout.OWNED_BADGE_X, Layout.OWNED_Y + Layout.BADGE_DROP)
		end, sectionsFade),
		Label({
			Name = "NotOwned",
			Position = function()
				return UDim2.fromOffset(Layout.SECTION_X, arranged().LockedY)
			end,
			Size = UDim2.fromOffset(200, Layout.SECTION_TEXT),
			TextSize = Layout.SECTION_TEXT,
			TextColor3 = Palette.Lavender,
			TextTransparency = sectionsFade,
			Text = "NOT OWNED",
			Visible = function()
				return arranged().Locked > 0
			end,
		}),
		countBadge("Locked", function()
			return arranged().Locked
		end, function()
			return Vector2.new(Layout.LOCKED_BADGE_X, arranged().LockedY + Layout.BADGE_DROP)
		end, sectionsFade),
		children,
		Parts.Ring(Layout.RING, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				local at = selectedAt() or Vector2.zero
				return UDim2.fromOffset(math.round(at.X), math.round(at.Y))
			end,
			Size = UDim2.fromOffset(Layout.CARD.X, Layout.CARD.Y),
			Visible = function()
				return selectedAt() ~= nil and whole() > 0.5
			end,
			ZIndex = 2,
		}),
		Parts.Badge("Check", Layout.CORNER_BADGE, {
			Name = "Equipped",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				local at = tick()
				return UDim2.fromOffset(
					math.round(at.X - Layout.CARD.X / 2 + Layout.CORNER_RIGHT.X + Layout.CORNER_BADGE / 2),
					math.round(at.Y - Layout.CARD.Y / 2 + Layout.CORNER_RIGHT.Y + Layout.CORNER_BADGE / 2)
				)
			end,
			Visible = function()
				return whole() > 0.6
			end,
			ZIndex = 4,
			create("UIScale")({
				Scale = function()
					return Motion.Decelerate(whole()) * (1 + tickPop())
				end,
			}),
		}),
	})
	vide.cleanup(function()
		page:Destroy()
	end)

	return page, Timing.SWEEP + 0.02
end

function List.Build(state: Types.TWeaponsState, actions: Types.TWeaponsActions, elapsed: () -> number): Frame
	local away = Parts.Away(state, elapsed, Timing.PANEL_DELAY)
	local faded = Parts.Faded(state, elapsed, Timing.PANEL_DELAY)
	local titleIn = derive(function(): number
		return Progress(state.Now(), state.TierAt(), Timing.TITLE)
	end)
	local total = derive(function(): number
		return #LoadoutCore.ByTier[state.Tier()]
	end)
	local owned = derive(function(): number
		local count = 0
		local levels = state.Levels()
		for _, gun in LoadoutCore.ByTier[state.Tier()] do
			if levels[gun.Id] then
				count += 1
			end
		end
		return count
	end)

	local pages = {}
	for tier = 1, LoadoutCore.TIERS do
		pages[tier] = function(present)
			return tierPage(state, actions, tier, present)
		end
	end
	local margin = Layout.MARGIN

	-- The panel and its header fade as one picture in a group with room for its shadow. The cards are not in it:
	-- they carry the guns' own pictures and move under the hand, and a group redraws its whole canvas whenever
	-- anything in it changes; they grow in and shrink away on their own instead.
	return create("Frame")({
		Name = "List",
		Position = function()
			return UDim2.fromOffset(Layout.PANEL.X - math.round(Timing.PANEL_SLIDE * away()), Layout.PANEL.Y)
		end,
		Size = UDim2.fromOffset(Layout.SIZE.X, Layout.SIZE.Y),
		BackgroundTransparency = 1,
		ZIndex = 2,
		create("CanvasGroup")({
			Name = "Chrome",
			Position = UDim2.fromOffset(-margin, -margin),
			Size = UDim2.new(1, 2 * margin, 1, 2 * margin),
			BackgroundTransparency = 1,
			GroupTransparency = faded,
			Components.Panel({ Brackets = Layout.BRACKETS, Tall = true }, {
				Name = "Panel",
				Position = UDim2.fromOffset(margin, margin),
				Size = UDim2.fromOffset(Layout.SIZE.X, Layout.SIZE.Y),
				Components.Icon("Rifle", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(Layout.RIFLE.X, Layout.RIFLE.Y),
					Size = Components.GlyphBox(Layout.RIFLE_GLYPH),
					ImageColor3 = Palette.Pink,
					ZIndex = 4,
				}),
				Label({
					Name = "Tier",
					Position = function()
						return UDim2.fromOffset(
							Layout.TITLE.X + math.round(Timing.TITLE_SLIDE * (1 - Motion.Decelerate(titleIn()))),
							Layout.TITLE.Y
						)
					end,
					Size = UDim2.fromOffset(240, Layout.TITLE_TEXT),
					TextSize = Layout.TITLE_TEXT,
					TextTransparency = function()
						return 1 - Motion.Out(titleIn())
					end,
					Text = function()
						return `TIER {state.Tier()}`
					end,
				}),
				Label({
					Name = "Count",
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.fromOffset(Layout.COUNT_RIGHT, Layout.COUNT_Y),
					Size = UDim2.fromOffset(200, Layout.COUNT_TEXT),
					TextXAlignment = Enum.TextXAlignment.Right,
					FontFace = Font.DisplayBold,
					TextSize = Layout.COUNT_TEXT,
					TextColor3 = Palette.Gold,
					Text = function()
						return `{owned()} / {total()} OWNED`
					end,
				}),
				create("Frame")({
					Name = "Rule",
					Position = UDim2.fromOffset(Layout.RULE.X, Layout.RULE.Y),
					Size = UDim2.fromOffset(Layout.RULE_WIDTH, 1),
					BackgroundColor3 = Parts.RULE,
					BorderSizePixel = 0,
					ZIndex = 4,
				}),
			}),
		}),
		create("Frame")({
			Name = "Cards",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 2,
			vide.switch(state.Tier)(pages),
		}),
	})
end

return List
