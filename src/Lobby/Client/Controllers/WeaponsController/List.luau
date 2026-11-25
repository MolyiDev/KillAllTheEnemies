--!nonstrict
-- The weapon list (his left panel): the tier on show, its guns owned and not, each as his card with the gun's own model
-- on it. A tier's cards are dealt in when the screen opens and when the tier is picked, and swept away as another is.
-- Within a tier the cards glide to their places, so a gun bought crosses from NOT OWNED into OWNED; the picked card's
-- brackets close round it and the green tick glides to the card its tier holds.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Notice = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Notice)
local ItemCard = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.ItemCard)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local LoadoutCore = require(ReplicatedStorage.GlobalShared.Core.LoadoutCore)
local Parts = require(script.Parent.Parts)
local panelTop = require(script.Parent.Parent.Parent.Utils.panelTop)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local spring = vide.spring
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
local Label = Parts.Label
local GUNS = DataCore.Guns.ById

-- His drawn rects in px at 1080, from the panel's top left.
local Layout = table.freeze({
	PANEL = Vector2.new(40, 190),
	SIZE = Vector2.new(440, 850),
	-- The room round the panel inside the group that fades it, for its shadow and brackets.
	MARGIN = 48,
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
	-- A section: its word and the cards under it.
	SECTION_X = 24,
	SECTION_TEXT = 17,
	OWNED_Y = 84,
	-- From a section's word to its first row, and from a section's last row to the next word. 40, not his 32: a card's
	-- brackets under the hand reach 12 px up toward the word.
	ROWS_DROP = 40,
	SECTION_GAP = 30,
	-- 18 apart across and 19 down (his 16): a card grows its brackets 12 px out across and 13 down under a press, and at
	-- his they crossed the next card's.
	CARD_XS = { 22, 160, 298 },
	CARD = Vector2.new(120, 150),
	ROW_STEP = 169,
	-- The gun's box inside a card.
	GUN_BOX = 92,
})
-- The corner badges' middles on a card: the upgrade Notice top left; the lock and the equipped tick (which glides
-- between cards) top right.
local NOTICE = ItemCard.TopLeft()
local TICK = ItemCard.TopRight(Layout.CARD.X)

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
	POP_PERIOD = 0.26,
	POP_DAMPING = 0.58,
	POP = 0.16,
})

local List = {}

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

	return { Places = places, Locked = #locked, LockedY = lockedY }
end

-- One gun's card, and how much the hand and the purchase's pop grow it, which the tick on it takes too.
local function card(
	state: Types.TWeaponsState,
	actions: Types.TWeaponsActions,
	gun,
	place: () -> Vector2,
	dealt: () -> number
): (TextButton, () -> number)
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
	local grown = function(): number
		return hand.Scale() + pop()
	end
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

	return ItemCard.Build({
		Name = gun.Name,
		Size = Layout.CARD,
		Position = function()
			local at = place()
			return UDim2.fromOffset(math.round(at.X), math.round(at.Y))
		end,
		Hand = hand,
		Accent = accent,
		Title = string.upper(gun.Name),
		Lit = unlocked,
		IsSelected = isSelected,
		Grown = function()
			return Motion.Decelerate(dealt())
		end,
		-- The light crosses it as it is dealt.
		Sheen = dealt,
		Pop = pop,
		Flash = flash,
		Ring = ring,
		Picture = Parts.Gun(function()
			return gun.Id
		end, {
			Tint = tint,
			Transparency = function()
				return Parts.LOCKED_TRANSPARENCY * (1 - unlocked())
			end,
		}, {
			Name = "Gun",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(Layout.GUN_BOX, Layout.GUN_BOX),
		}),
		Children = {
			-- Where his gold badge stood: placed by its middle.
			Notice.Build({ Kind = "Upgrade", Size = ItemCard.BADGE, IsShown = canUpgrade }, {
				Name = "CanUpgrade",
				Position = UDim2.fromOffset(NOTICE.X, NOTICE.Y),
				ZIndex = 5,
			}),
			-- Gone the frame the purchase lands, under the card's flash.
			ItemCard.Chip(Components.Commas(gun.Price), Palette.Gold, false, EIcons.Gem, {
				Name = "Price",
				Visible = function()
					return level() == nil
				end,
			}),
			-- Thrown off as the purchase lands: up, turning, growing and fading as one picture.
			create("CanvasGroup")({
				Name = "Lock",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = function()
					return UDim2.fromOffset(TICK.X, TICK.Y - math.round(Timing.LOCK_RISE * Motion.Out(thrown())))
				end,
				Size = UDim2.fromOffset(ItemCard.BADGE, ItemCard.BADGE),
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
				Parts.Badge("Lock", ItemCard.BADGE, {}),
			}),
		},
		Activated = function()
			actions.Select(gun.Id)
		end,
	}),
		grown
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
	local scales = {}
	for order, gun in guns do
		local target = derive(function(): Vector2
			return arranged().Places[gun.Id]
		end)
		local glide = spring(target, Timing.GLIDE_PERIOD, Timing.GLIDE_DAMPING)
		children[order], scales[gun.Id] = card(state, actions, gun, glide, dealt(order))
	end

	local whole = dealt(1)
	local sectionsFade = derive(function(): number
		return 1 - Motion.Out(whole())
	end)

	-- The tick on the card the tier holds, one piece gliding between cards.
	local equippedGun = derive(function(): number
		return state.Equipped()[tier] or LoadoutCore.Starters[tier].Id
	end)
	local tickTarget = derive(function(): Vector2
		return arranged().Places[equippedGun()] or Vector2.zero
	end)
	local tick = spring(tickTarget, Timing.GLIDE_PERIOD, Timing.GLIDE_DAMPING)
	local equippedScale = function(): number
		local grown = scales[equippedGun()]
		return if grown then grown() else 1
	end
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
		children,
		Parts.Badge("Check", ItemCard.BADGE, {
			Name = "Equipped",
			AnchorPoint = Vector2.new(0.5, 0.5),
			-- On the corner of the card it lies on as that card grows and presses under the hand.
			Position = function()
				local at = tick()
				local grown = equippedScale()
				return UDim2.fromOffset(
					math.round(at.X + grown * (TICK.X - Layout.CARD.X / 2)),
					math.round(at.Y + grown * (TICK.Y - Layout.CARD.Y / 2))
				)
			end,
			Visible = function()
				return whole() > 0.6
			end,
			ZIndex = 4,
			create("UIScale")({
				Scale = function()
					return Motion.Decelerate(whole()) * (1 + tickPop()) * equippedScale()
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
	-- Raised to just under the top bar, its bottom staying put: the cards ride up with the top.
	local lift = panelTop.Lift(Layout.PANEL.Y)
	local size = function(): UDim2
		return UDim2.fromOffset(Layout.SIZE.X, Layout.SIZE.Y + lift())
	end

	-- The panel and its header fade as one picture in a group with room for its shadow. The cards are not in it:
	-- they carry the guns' own pictures and move under the hand, and a group redraws its whole canvas whenever
	-- anything in it changes; they grow in and shrink away on their own instead.
	return create("Frame")({
		Name = "List",
		Position = function()
			return UDim2.fromOffset(Layout.PANEL.X - math.round(Timing.PANEL_SLIDE * away()), Layout.PANEL.Y - lift())
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
				Components.Picture(EIcons.Rifle, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(Layout.RIFLE.X, Layout.RIFLE.Y),
					Size = Components.PictureBox(Layout.RIFLE_GLYPH),
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
