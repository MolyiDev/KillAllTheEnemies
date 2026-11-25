--!nonstrict
-- The weapons screen on his 1920 x 1080: the lobby dimmed as his lobby screens dim it, the four tier tabs, the list
-- (List), the stage (Stage), the info panel (Info) and the Gems flying between them (Flight). The HUD's Gems pill stays
-- up over it as the screen's balance. Pieces arrive staged by what the screen is for: the list, then the stage and the
-- gun, the info, the tabs, and the bottom row last.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local ItemCard = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.ItemCard)
local Notice = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Notice)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local LoadoutCore = require(ReplicatedStorage.GlobalShared.Core.LoadoutCore)
local Flight = require(script.Parent.Flight)
local Info = require(script.Parent.Info)
local List = require(script.Parent.List)
local Parts = require(script.Parent.Parts)
local Stage = require(script.Parent.Stage)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Label = Parts.Label
local GUNS = DataCore.Guns.ById

-- His drawn rects in px at 1080, from the screen's top left.
local Layout = table.freeze({
	-- The tabs: the first one's top left, the step between them and their size, and the gun's box inside one.
	TAB = Vector2.new(629, 40),
	TAB_STEP = 174,
	TAB_SIZE = Vector2.new(140, 112),
	TAB_GUN_BOX = 66,
	-- The chevrons between two tabs: their middle past a tab's right edge.
	CHEVRON = Vector2.new(17, 56),
	CHEVRON_TEXT = 22,
})

local Timing = table.freeze({
	-- His lobby screens dim the world this much (UIMatt.md section 2: 0.7 transparent).
	DIM = 0.3,
	TABS_DELAY = 0.14,
	TABS_STAGGER = 0.05,
	TABS_DROP = 24,
	-- The gun a tier holds changing pops its picture.
	HELD_POP_PERIOD = 0.26,
	HELD_POP_DAMPING = 0.58,
	HELD_POP = 0.18,
})

-- The upgrade Notice's middle on a tab.
local NOTICE = ItemCard.TopLeft()

local Screen = {}

-- How long a purchase's Gems are in the air: the controller holds the purchase's answer until they land.
Screen.FLIGHT_SECONDS = Flight.SECONDS

local function tab(state: Types.TWeaponsState, actions: Types.TWeaponsActions, elapsed: () -> number, tier: number)
	local delay = Timing.TABS_DELAY + Timing.TABS_STAGGER * (tier - 1)
	local away = Parts.Away(state, elapsed, delay)
	local hand = Hand.React("Take")
	local isPicked = derive(function(): boolean
		return state.Tier() == tier
	end)
	local held = derive(function(): number
		return state.Equipped()[tier] or LoadoutCore.Starters[tier].Id
	end)
	-- The tab wears the rarity of the gun it holds, as that gun's card in the list does.
	local accent = derive(function(): Color3
		return Parts.RARITIES[GUNS[held()].Rarity].Accent
	end)
	local offer = derive(function(): boolean
		return Parts.HasOffer(state, LoadoutCore.ByTier[tier])
	end)
	local pop, strikePop = Hand.Kick(Timing.HELD_POP_PERIOD, Timing.HELD_POP_DAMPING)
	local last = nil
	vide.effect(function()
		local current = held()
		vide.untrack(function()
			if last and current ~= last then strikePop(Timing.HELD_POP) end
			last = current
		end)
	end)
	local left = Layout.TAB.X + Layout.TAB_STEP * (tier - 1)

	-- It grows in from nothing rather than fading under a group: the hand moves its wash, sheen and brackets, and a
	-- group redraws its whole canvas for every frame of that.
	return ItemCard.Build({
		Name = `Tier{tier}`,
		Size = Layout.TAB_SIZE,
		Position = function()
			return UDim2.fromOffset(
				left + Layout.TAB_SIZE.X / 2,
				Layout.TAB.Y + Layout.TAB_SIZE.Y / 2 - math.round(Timing.TABS_DROP * away())
			)
		end,
		Hand = hand,
		Accent = accent,
		Title = `TIER {tier}`,
		IsSelected = isPicked,
		Grown = function()
			return 1 - away()
		end,
		Picture = Parts.Gun(held, {}, {
			Name = "Gun",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(Layout.TAB_GUN_BOX, Layout.TAB_GUN_BOX),
			create("UIScale")({
				Scale = function()
					return 1 + pop()
				end,
			}),
		}),
		Children = {
			-- Where his gold badge stood: placed by its middle.
			Notice.Build({ Kind = "Upgrade", Size = ItemCard.BADGE, IsShown = offer }, {
				Position = UDim2.fromOffset(NOTICE.X, NOTICE.Y),
				ZIndex = 5,
			}),
		},
		Activated = function()
			actions.PickTier(tier)
		end,
	})
end

local function tabs(state: Types.TWeaponsState, actions: Types.TWeaponsActions, elapsed: () -> number): { Instance }
	local children = {}
	for tier = 1, LoadoutCore.TIERS do
		children[tier] = tab(state, actions, elapsed, tier)
	end

	-- His pink chevrons from each tab to the next.
	local chevronsFaded = Parts.Faded(state, elapsed, Timing.TABS_DELAY + Timing.TABS_STAGGER * 2)
	for gap = 1, LoadoutCore.TIERS - 1 do
		local right = Layout.TAB.X + Layout.TAB_STEP * (gap - 1) + Layout.TAB_SIZE.X
		table.insert(
			children,
			Label({
				Name = `Chevron{gap}`,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(right + Layout.CHEVRON.X, Layout.TAB.Y + Layout.CHEVRON.Y),
				Size = UDim2.fromOffset(30, Layout.CHEVRON_TEXT),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextSize = Layout.CHEVRON_TEXT,
				TextColor3 = Palette.Pink,
				TextTransparency = chevronsFaded,
				Text = "»",
			})
		)
	end

	return children
end

function Screen.Build(state: Types.TWeaponsState, actions: Types.TWeaponsActions): { any }
	local elapsed = Parts.Elapsed(state)
	local dimFaded = Parts.Faded(state, elapsed, 0)

	return {
		-- Past the screen's edges whatever its shape, and it takes the clicks the pieces do not: this is a page, so a
		-- click on nothing shuts nothing.
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
		tabs(state, actions, elapsed),
		List.Build(state, actions, elapsed),
		Stage.Build(state, actions, elapsed),
		Info.Build(state, actions, elapsed),
		Flight.Build(state),
	}
end

return Screen
