--!nonstrict
-- The weapons screen on his 1920 x 1080: the lobby dimmed as his lobby screens dim it, the four tier tabs, the list
-- (List), the stage (Stage), the info panel (Info) and the Gems flying between them (Flight). The HUD's Gems pill stays
-- up over it as the screen's balance. Pieces arrive staged by what the screen is for: the list, then the stage and the
-- gun, the info, the tabs, and the bottom row last.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
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
	-- The tabs: the first one's top left, the step between them and their size; inside one the gun's box and middle,
	-- the rule, the word and the corner badges.
	TAB = Vector2.new(629, 40),
	TAB_STEP = 174,
	TAB_SIZE = Vector2.new(140, 112),
	TAB_GUN = Vector2.new(70, 45),
	TAB_GUN_BOX = 66,
	TAB_RULE = Vector2.new(12, 78),
	TAB_RULE_WIDTH = 116,
	TAB_WORD_Y = 86,
	TAB_WORD_TEXT = 16,
	TAB_BADGE = 23,
	TAB_BADGE_LEFT = Vector2.new(9, 8),
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
})

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
	local edge = derive(function(): Color3
		return Parts.EdgeOf(accent())
	end)
	local offer = derive(function(): boolean
		return Parts.HasOffer(state, LoadoutCore.ByTier[tier])
	end)
	-- The gun a tier holds changing pops its picture.
	local pop, strikePop = Hand.Kick(0.26, 0.58)
	local last = nil
	vide.effect(function()
		local current = held()
		vide.untrack(function()
			if last and current ~= last then strikePop(0.18) end
			last = current
		end)
	end)
	local left = Layout.TAB.X + Layout.TAB_STEP * (tier - 1)

	return Components.Button({
		Name = `Tier{tier}`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(
				left + Layout.TAB_SIZE.X / 2,
				Layout.TAB.Y + Layout.TAB_SIZE.Y / 2 - math.round(Timing.TABS_DROP * away())
			)
		end,
		Size = UDim2.fromOffset(Layout.TAB_SIZE.X, Layout.TAB_SIZE.Y),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Activated = function()
			hand.Commit()
			actions.PickTier(tier)
		end,
		hand.Events,
		-- It grows in from nothing rather than fading under a group: the hand moves its wash, sheen and brackets, and
		-- a group redraws its whole canvas for every frame of that.
		create("UIScale")({
			Scale = function()
				return (1 - away()) * hand.Scale()
			end,
		}),
		Components.Card({
			Accent = edge,
			Glow = accent,
			GlowTransparency = function()
				return 0.7 - 0.35 * hand.Light()
			end,
			Tint = 0.35,
			Marks = true,
			Brackets = hand.Rise,
			BracketLength = 20,
			BracketTransparency = function()
				return 0.6 - 0.3 * hand.Light()
			end,
			BracketsClosed = isPicked,
		}, {
			Name = "Card",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 3, 2),
			Components.Sheen(hand.Glint, 3),
			Parts.Gun(held, {}, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(Layout.TAB_GUN.X, Layout.TAB_GUN.Y),
				Size = UDim2.fromOffset(Layout.TAB_GUN_BOX, Layout.TAB_GUN_BOX),
				ZIndex = 4,
				create("UIScale")({
					Scale = function()
						return 1 + 0.1 * hand.Rise() + pop()
					end,
				}),
			}),
			create("Frame")({
				Name = "Rule",
				Position = UDim2.fromOffset(Layout.TAB_RULE.X, Layout.TAB_RULE.Y),
				Size = UDim2.fromOffset(Layout.TAB_RULE_WIDTH, 2),
				BackgroundColor3 = accent,
				BackgroundTransparency = 0.6,
				BorderSizePixel = 0,
				ZIndex = 4,
			}),
			Label({
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromOffset(Layout.TAB_SIZE.X / 2, Layout.TAB_WORD_Y),
				Size = UDim2.fromOffset(Layout.TAB_SIZE.X, Layout.TAB_WORD_TEXT),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextSize = Layout.TAB_WORD_TEXT,
				Text = `TIER {tier}`,
			}),
			-- Where his gold badge stood: placed by its middle.
			Notice.Build({ Kind = "Upgrade", Size = Layout.TAB_BADGE, IsShown = offer }, {
				Position = UDim2.fromOffset(
					Layout.TAB_BADGE_LEFT.X + Layout.TAB_BADGE / 2,
					Layout.TAB_BADGE_LEFT.Y + Layout.TAB_BADGE / 2
				),
				ZIndex = 5,
			}),
		}),
	}) :: TextButton
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
