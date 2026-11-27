--!nonstrict
-- HEAL ALL and NUKE ALL, side by side under the skip block (UIMatt.md, Usable Items), on his drawn rects. The one the moment calls for
-- asks to be bought: it leaves its slot for a spot beside the pair, grows, breathes and catches the light until the
-- moment passes (init decides which: the nuke over a big crowd, the heal at low health, the nuke first).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local EProducts = require(ReplicatedStorage.Types.Enums.EProducts)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Types = require(script.Parent.Types)

local create = vide.create
local spring = vide.spring
local Palette = Theme.Palette
local Font = Theme.Font

-- His drawn rects at 1080: the pair's left edge from the screen's right and its top, a card, the gap, the glyph and
-- the label; and where a prompted card goes (its centre, from the pair's top-left), clear of the skip block above and
-- the abilities below.
local RIGHT = 244
local TOP = 176
local CARD = Vector2.new(100, 96)
-- 18, not his 8: under a press a card's brackets reach 11 px out, and at his HEAL ALL's crossed NUKE's.
local GAP = 18
local GLYPH = Vector2.new(47, 40)
-- The picture's longer side.
local PICTURE_SIZE = 54
local LABEL_Y = 82
local LABEL_TEXT = 13
local SPOT = Vector2.new(-112, 122)
-- A prompted card's size, its breath (share and beats a second) and how often the light runs across it.
local GROWN = 1.65
local BREATH = 0.035
local BREATH_HZ = 1.2
local SHEEN_EVERY = 2.2
local SHEEN_SECONDS = 0.7
-- The move out to the spot: a little past and back, the one flourish here.
local PROMPT_SPRING = 0.42
local PROMPT_DAMPING = 0.68
-- Under the hand: how much the glyph grows with the card's rise.
local GLYPH_RISE = 0.12

local Items = {}

type TItem = {
	Name: string,
	Picture: string,
	Label: string,
	Accent: Color3,
	Home: Vector2,
	IsPrompted: () -> boolean,
	ProductId: number,
}

local function card(state: Types.THudState, actions: Types.TActions, item: TItem): TextButton
	local hand = Hand.React("Take")
	local emphasis, configure = spring(function()
		return if item.IsPrompted() then 1 else 0
	end, PROMPT_SPRING, PROMPT_DAMPING)
	-- Pinned on each change of target, or a spring heading back to 0 never settles (UI.md 5g).
	vide.effect(function()
		item.IsPrompted()
		vide.untrack(function()
			configure({ position = emphasis() })
		end)
	end)

	local wave = function(): number
		local e = emphasis()
		if e < 0.01 then return 0 end
		return math.sin(state.Breath() * math.pi * 2 * BREATH_HZ) * math.clamp(e, 0, 1)
	end

	local sheenAt = function(): number
		local now = state.Breath()
		return Motion.Progress(now % SHEEN_EVERY, 0, SHEEN_SECONDS)
	end

	return Components.Button({
		Name = item.Name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(CARD.X, CARD.Y),
		BackgroundTransparency = 1,
		Position = function()
			local at = item.Home:Lerp(SPOT, emphasis())
			return UDim2.fromOffset(math.round(at.X), math.round(at.Y))
		end,
		ZIndex = function()
			return if emphasis() > 0.05 then 3 else 1
		end,
		Activated = function()
			hand.Commit()
			actions.BuyProduct(item.ProductId)
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return (1 + (GROWN - 1) * emphasis() + BREATH * wave()) * hand.Scale()
			end,
		}),
		Components.Card({
			Accent = item.Accent,
			Tint = 0.45,
			Marks = true,
			GlowTransparency = function()
				local e = math.clamp(emphasis(), 0, 1)
				return 0.7 - math.max(0.4 * e + 0.12 * wave(), 0.4 * hand.Light())
			end,
			Brackets = hand.Rise,
			BracketTransparency = function()
				return 0.65 - 0.35 * hand.Light()
			end,
		}, {
			Name = "Face",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 4, 3),
		}),
		-- The light running across a card that is asking, cut at the card's edges (the face's brackets stand outside
		-- it, so the face itself cannot clip).
		create("Frame")({
			Name = "SheenWindow",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 3,
			Components.Sheen(
				Hand.Sheen(hand, function()
					return if emphasis() > 0.5 then sheenAt() else 0
				end),
				3
			),
		}),
		Components.Picture(item.Picture, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(GLYPH.X, GLYPH.Y),
			Size = Components.PictureBox(PICTURE_SIZE),
			ZIndex = 2,
			create("UIScale")({
				Scale = function()
					return 1 + 0.06 * wave() + GLYPH_RISE * hand.Rise()
				end,
			}),
		}),
		create("TextLabel")({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, LABEL_Y),
			Size = UDim2.new(1, -8, 0, LABEL_TEXT),
			BackgroundTransparency = 1,
			FontFace = Font.Display,
			TextSize = LABEL_TEXT,
			TextColor3 = Palette.White,
			Text = item.Label,
			ZIndex = 2,
		}),
	}) :: TextButton
end

function Items.Build(state: Types.THudState, actions: Types.TActions): Frame
	return create("Frame")({
		Name = "Items",
		Position = UDim2.new(1, -RIGHT, 0, TOP),
		Size = UDim2.fromOffset(CARD.X * 2 + GAP, CARD.Y),
		BackgroundTransparency = 1,
		Visible = function()
			local phase = state.Phase()
			return phase == "Preparing" or phase == "Fighting"
		end,
		card(state, actions, {
			Name = "HealAll",
			Picture = EIcons.Potion,
			Label = "HEAL ALL",
			Accent = Palette.Green,
			Home = CARD / 2,
			IsPrompted = state.IsHealPrompted,
			ProductId = EProducts.HealAll,
		}),
		card(state, actions, {
			Name = "NukeAll",
			Picture = EIcons.Bomb,
			Label = "NUKE ALL",
			Accent = Palette.Gold,
			Home = Vector2.new(CARD.X * 1.5 + GAP, CARD.Y / 2),
			IsPrompted = state.IsNukePrompted,
			ProductId = EProducts.NukeAll,
		}),
	})
end

return Items
