--!nonstrict
-- The card a thing is picked from (a gun, a piece of equipment, an ability, an enemy, a recipe) and the lobby rail's
-- buttons: one look and one feel everywhere (UI.md "One card"). His accent card with its name on a dark band at the
-- bottom, an accent rule along the band's top, the picture above it, a badge in each top corner.
--
-- Under the hand the picture rises and grows, the rule stretches and lights and the glow lifts; a press pops the
-- picture. Picked, the brackets close into an outline, the glow brightens, the band flares and settles warmed toward
-- the accent, and the rule burns at full. A gain (bought, put on, discovered) is the caller's Flash, Ring and Pop: a white flash, one ring
-- of the accent off the card's outline and a pop of the card, the same on every screen.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(script.Parent.Components)
local Hand = require(script.Parent.Hand)
local Motion = require(script.Parent.Motion)
local Theme = require(script.Parent.Theme)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font

-- One value each, in px at 1080, whatever the card's size: the band, its rule and title, the corner badges' inset and
-- side, the brackets' legs.
local Look = table.freeze({
	EDGE = 3,
	-- The edge is the accent this much darker; the face warms this far toward it at the bottom.
	EDGE_SHARE = 0.85,
	TINT = 0.35,
	BAND = 28,
	-- The rule stands RULE_INSET in from each side at rest and reaches the edge under the hand and picked.
	RULE_INSET = 10,
	RULE_HEIGHT = 2,
	TITLE_TEXT = 15,
	TITLE_INSET = 8,
	CORNER = 8,
	BADGE = 24,
	BRACKET_LENGTH = 20,
})

-- The light: the glow at rest, how much the hand, a gain and a pick lift it; the brackets; the rule at rest, under the
-- hand and picked; the band's warmth picked.
local Light = table.freeze({
	GLOW = 0.7,
	GLOW_LIT = 0.35,
	GLOW_PICKED = 0.18,
	BRACKETS = 0.6,
	BRACKETS_LIT = 0.3,
	RULE = 0.6,
	RULE_PICKED = 0,
	BAND_PICKED = 0.22,
	-- A card becoming the picked one: its band flares this much brighter and settles.
	BAND_FLARE = 0.45,
	FLASH = 0.75,
})

local Gesture = table.freeze({
	-- Under the hand the picture grows this share and rises this many px with the hand's rise.
	PICTURE_GROW = 0.1,
	PICTURE_LIFT = 4,
	-- A press that goes through pops the picture this share, on a spring that rings once.
	POP = 0.16,
	POP_PERIOD = 0.3,
	POP_DAMPING = 0.5,
	-- Picked or not, the band and the rule settle in this long, with no overshoot; the flare as it is picked dies over
	-- FLARE_PERIOD, with none either.
	PICK_PERIOD = 0.18,
	FLARE_PERIOD = 0.35,
	-- A gain's ring: how far it grows past the card's outline and how thick it is.
	RING_REACH = 24,
	RING_LINE = 3,
})

export type TSpec = {
	-- The instance's name.
	Name: string,
	-- The card's outer drawn rect, edge included.
	Size: Vector2,
	Position: any,
	ZIndex: number?,
	Hand: Hand.TReaction,
	Accent: Color3 | () -> Color3,
	-- The glow's colour where it is not the accent.
	Glow: (Color3 | () -> Color3)?,
	Title: string | () -> string,
	-- 0 to 1: how far the thing is the player's (owned, discovered); the title goes from lavender to white. nil: 1.
	Lit: (() -> number)?,
	IsSelected: (() -> boolean)?,
	-- What the whole card grows by as it is dealt in (0 to 1, eased by the caller), and a pop added to the hand's scale.
	Grown: (() -> number)?,
	Pop: (() -> number)?,
	-- A gain: the flash (1 at the strike, fading to 0) and the ring (0 to 1 as it grows; 1 or more, none).
	Flash: (() -> number)?,
	Ring: (() -> number)?,
	-- How much brighter the glow is besides (a call while something waits).
	GlowLift: (() -> number)?,
	-- Another light crossing the face (a landing, a call), 1 at rest: it shares the hand's glint's layer.
	Sheen: (() -> number)?,
	-- The picture, centred in the room over the band: built by the caller around the middle of the frame it is put
	-- in (AnchorPoint 0.5, Position 0.5), which rises and grows with the hand and pops on a press.
	Picture: Instance?,
	-- Badges, chips, ribbons and the rest, laid over the face (ItemCard.TopLeft / TopRight place a badge).
	Children: { any }?,
	Activated: (() -> ())?,
}

local ItemCard = {}

ItemCard.BADGE = Look.BADGE

-- A badge's middle in the top left corner, and in the top right of a card `width` px wide.
function ItemCard.TopLeft(): Vector2
	local half = Look.BADGE / 2
	return Vector2.new(Look.CORNER + half, Look.CORNER + half)
end

function ItemCard.TopRight(width: number): Vector2
	local half = Look.BADGE / 2
	return Vector2.new(width - Look.CORNER - half, Look.CORNER + half)
end

-- The middle of the room over the band on a card `size` px: where the picture stands.
function ItemCard.PictureAt(size: Vector2): Vector2
	return Vector2.new(size.X / 2, math.round((size.Y - Look.BAND) / 2))
end

-- A chip in the top left corner (a price, ULT): `color`'s 1 px edge round ink and the text in `color`, or with
-- `isSolid` a flat block of `color` with ink text. `picture` (an EIcons name) stands before the text.
function ItemCard.Chip(text: string, color: Color3, isSolid: boolean?, picture: string?, props: { [any]: any }?): Frame
	return create("Frame")({
		Name = "Chip",
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.fromOffset(Look.CORNER, Look.CORNER),
		Size = UDim2.fromOffset(0, Look.BADGE),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = 5,
		create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		-- The face's 1 px offset is counted in the automatic width; this is the edge's px on the right.
		create("UIPadding")({ PaddingRight = UDim.new(0, 1) }),
		create("Frame")({
			Name = "Face",
			AutomaticSize = Enum.AutomaticSize.X,
			Position = UDim2.fromOffset(1, 1),
			Size = UDim2.fromOffset(0, Look.BADGE - 2),
			BackgroundColor3 = Palette.Ink,
			BackgroundTransparency = if isSolid then 1 else 0,
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
			create("UIPadding")({ PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 7) }),
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 4),
			}),
			if picture
				then Components.Picture(picture, {
					LayoutOrder = 1,
					Size = Components.PictureBox(15),
				})
				else nil,
			create("TextLabel")({
				LayoutOrder = 2,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 14),
				BackgroundTransparency = 1,
				FontFace = Font.Display,
				TextSize = 14,
				TextColor3 = if isSolid then Palette.Ink else color,
				Text = text,
			}),
		}),
		props,
	})
end

local function nothing(): number
	return 0
end

-- The band warming toward the accent while the card is picked, flaring as it becomes the picked one (never as it is
-- built picked), on a card `width` px wide whose band starts `top` px down.
local function pickedBand(
	accent: () -> Color3,
	picked: () -> number,
	isSelected: () -> boolean,
	width: number,
	top: number
): Frame
	local flare, strikeFlare = Hand.Kick(Gesture.FLARE_PERIOD, 1)
	local wasSelected = isSelected()
	vide.effect(function()
		local selected = isSelected()
		vide.untrack(function()
			if selected and not wasSelected then strikeFlare(1) end
			wasSelected = selected
		end)
	end)
	local shown = derive(function(): number
		return math.min(Light.BAND_PICKED * picked() + Light.BAND_FLARE * flare(), 1)
	end)

	return create("Frame")({
		Name = "BandLight",
		Position = UDim2.fromOffset(Look.EDGE, top),
		Size = UDim2.fromOffset(width - 2 * Look.EDGE, Look.BAND),
		BackgroundColor3 = accent,
		BackgroundTransparency = function()
			return 1 - shown()
		end,
		Visible = function()
			return shown() > 0.005
		end,
		BorderSizePixel = 0,
		ZIndex = 3,
	})
end

function ItemCard.Build(spec: TSpec): TextButton
	local hand = spec.Hand
	local size = spec.Size
	local lit = spec.Lit
	local flash = spec.Flash
	local ring = spec.Ring
	local grown = spec.Grown
	local gained = spec.Pop
	local glowLift = spec.GlowLift
	local isSelected = spec.IsSelected
	local given = spec.Accent
	local accent: () -> Color3 = if type(given) == "function"
		then given
		else function(): Color3
			return given
		end
	local bandTop = size.Y - Look.EDGE - Look.BAND
	local pop, strikePop = Hand.Kick(Gesture.POP_PERIOD, Gesture.POP_DAMPING)
	-- What a card that cannot be picked (the rail's) cannot do is not built.
	local picked, bandLight = nothing, nil
	if isSelected then
		picked = Hand.Spring(function(): number
			return if isSelected() then 1 else 0
		end, Gesture.PICK_PERIOD)
		bandLight = pickedBand(accent, picked, isSelected, size.X, bandTop)
	end
	local light = derive(function(): number
		return math.max(hand.Light(), picked())
	end)
	local pictureAt = ItemCard.PictureAt(size)
	local isRinging = if ring
		then derive(function(): boolean
			local at = ring()
			return at > 0 and at < 1
		end)
		else nil

	return Components.Button({
		Name = spec.Name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = spec.Position,
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		ZIndex = spec.ZIndex or 3,
		Activated = function()
			hand.Commit()
			strikePop(Gesture.POP)
			if spec.Activated then spec.Activated() end
		end,
		hand.Events,
		Components.Card({
			Accent = function()
				local color = accent()
				local share = Look.EDGE_SHARE
				return Color3.new(color.R * share, color.G * share, color.B * share)
			end,
			Glow = spec.Glow or accent,
			GlowTransparency = function()
				local lift = math.max(hand.Light(), if flash then flash() else 0)
				return math.max(
					Light.GLOW
						- Light.GLOW_LIT * lift
						- Light.GLOW_PICKED * picked()
						- (if glowLift then glowLift() else 0),
					0
				)
			end,
			Tint = Look.TINT,
			Band = Look.BAND,
			Marks = true,
			Brackets = hand.Rise,
			BracketLength = Look.BRACKET_LENGTH,
			BracketTransparency = function()
				return Light.BRACKETS - Light.BRACKETS_LIT * hand.Light()
			end,
			BracketsClosed = isSelected,
		}, {
			Name = "Card",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			create("UIScale")({
				Scale = function()
					return (if grown then grown() else 1) * (hand.Scale() + (if gained then gained() else 0))
				end,
			}),
			-- A gain's one ring, the card's own outline grown off it.
			if ring
				then create("Frame")({
					Name = "Ring",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = function()
						local grow = math.round(Gesture.RING_REACH * Motion.Out(math.clamp(ring(), 0, 1)))
						return UDim2.new(1, 2 * grow, 1, 2 * grow)
					end,
					BackgroundTransparency = 1,
					Visible = isRinging,
					create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
					create("UIStroke")({
						Color = accent,
						Thickness = Gesture.RING_LINE,
						Transparency = ring,
					}),
				})
				else nil,
			Hand.WashLayer(hand, 3, 2),
			Components.Sheen(if spec.Sheen then Hand.Sheen(hand, spec.Sheen) else hand.Glint, 3),
			bandLight,
			create("Frame")({
				Name = "Rule",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(size.X / 2, bandTop),
				Size = function()
					local inset = Look.RULE_INSET + (Look.EDGE - Look.RULE_INSET) * light()
					return UDim2.fromOffset(math.round(size.X - 2 * inset), Look.RULE_HEIGHT)
				end,
				BackgroundColor3 = accent,
				BackgroundTransparency = function()
					return Light.RULE + (Light.RULE_PICKED - Light.RULE) * light()
				end,
				BorderSizePixel = 0,
				ZIndex = 4,
			}),
			create("Frame")({
				Name = "Art",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = function()
					return UDim2.fromOffset(pictureAt.X, pictureAt.Y - math.round(Gesture.PICTURE_LIFT * hand.Rise()))
				end,
				Size = UDim2.fromOffset(size.X, bandTop),
				BackgroundTransparency = 1,
				ZIndex = 4,
				create("UIScale")({
					Scale = function()
						return 1 + Gesture.PICTURE_GROW * hand.Rise() + pop()
					end,
				}),
				spec.Picture,
			}),
			create("TextLabel")({
				Name = "Title",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(size.X / 2, bandTop + Look.BAND / 2),
				Size = UDim2.fromOffset(size.X - 2 * Look.TITLE_INSET, Look.TITLE_TEXT),
				BackgroundTransparency = 1,
				FontFace = Font.Display,
				TextScaled = true,
				TextColor3 = function()
					return if lit then Palette.Lavender:Lerp(Palette.White, lit()) else Palette.White
				end,
				Text = spec.Title,
				ZIndex = 5,
				create("UITextSizeConstraint")({ MaxTextSize = Look.TITLE_TEXT }),
			}),
			spec.Children,
			if flash
				then create("Frame")({
					Name = "Flash",
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = Palette.White,
					BorderSizePixel = 0,
					ZIndex = 7,
					Visible = function()
						return flash() > 0.01
					end,
					BackgroundTransparency = function()
						return 1 - Light.FLASH * flash()
					end,
					create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
				})
				else nil,
		}),
	}) :: TextButton
end

return ItemCard
