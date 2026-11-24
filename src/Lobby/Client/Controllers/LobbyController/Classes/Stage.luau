--!nonstrict
-- The classes screen's stage (UIMatt.md, Classes › Stage Container), on his drawn rects at 1080 with x from the
-- screen's middle: the class's name and rarity tag, the art behind the avatar (his two rings, or a Showcase look), the
-- floor, and the player's own avatar standing on it, turning slowly (avatarTurntable).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Showcase = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Showcase)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local avatarTurntable = require(script.Parent.Parent.Parent.Parent.Utils.avatarTurntable)
local TData = require(ReplicatedStorage.Types.TData)
local Types = require(script.Parent.Parent.Types)

local create = vide.create
local source = vide.source
local Palette = Theme.Palette
local Font = Theme.Font

-- His drawn rects: the name's top, the tag, the rings' middle and radii, the floor; and the avatar's frame: its top
-- and side, where the feet stand in it and how tall the body is.
local Layout = table.freeze({
	NAME_Y = 216,
	NAME_TEXT = 92,
	TAG = Vector2.new(-60, 312),
	TAG_SIZE = Vector2.new(120, 34),
	TAG_TEXT = 17,
	RINGS_Y = 560,
	OUTER_RADIUS = 260,
	INNER_RADIUS = 190,
	-- The art behind the avatar when it is not his rings.
	SHOWCASE = 580,
	FLOOR_Y = 830,
	FLOOR_SIZE = Vector2.new(461, 84),
	EDGE = 2,
	VIEW_TOP = 330,
	VIEW = 520,
	FEET = 500,
	BODY = 400,
})

-- The pieces' way in: the rings and the floor grow from this share of their size, the name drops and the avatar
-- rises this far (px), and the tag stamps down from this much bigger.
local Arrive = table.freeze({
	RINGS_FROM = 0.82,
	NAME_FROM = 40,
	AVATAR_FROM = 40,
	STAMP = 0.4,
})

-- How far in each piece is, 0 to 1: the rings and floor, the name, the tag, the avatar.
export type TShown = {
	Rings: () -> number,
	Name: () -> number,
	Tag: () -> number,
	Body: () -> number,
}

local Stage = {}

-- A class rarity's colour, word, and whether its tag is lettered in ink (Theme's).
Stage.RARITIES = Theme.Rarities

local function label(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		ZIndex = 4,
		props,
	})
end

-- The stage for `class`, its pieces as far in as `shown` says, its avatar turning while `isActive` (its page is on show).
-- Returns the stage and the avatar's cheer, which the class's card calls too.
function Stage.Build(
	state: Types.TLobbyState,
	class: TData.TClass,
	shown: TShown,
	isActive: () -> boolean
): (Frame, () -> ())
	local look = Showcase.Looks.Classes
	local isRings = look == "Rings"
	local rarity = Stage.RARITIES[class.Rarity]
	local view, celebrateAvatar = avatarTurntable.Build({
		Avatar = state.Avatar,
		IsActive = isActive,
		Shown = shown.Body,
		Frame = {
			ViewTop = Layout.VIEW_TOP,
			View = Layout.VIEW,
			Feet = Layout.FEET,
			Body = Layout.BODY,
			FloorY = Layout.FLOOR_Y,
			FloorSize = Layout.FLOOR_SIZE,
			Edge = Layout.EDGE,
			RiseFrom = Arrive.AVATAR_FROM,
		},
		HasFloorRing = isRings,
	})
	local grown = function(): number
		return Arrive.RINGS_FROM + (1 - Arrive.RINGS_FROM) * shown.Rings()
	end
	local cheeredAt = source(-math.huge)
	local function celebrate()
		celebrateAvatar()
		cheeredAt(os.clock())
	end

	-- The art behind the avatar, and the look's particles over it.
	local art, front = avatarTurntable.Art({
		Look = look,
		RingsY = Layout.RINGS_Y,
		OuterRadius = Layout.OUTER_RADIUS,
		InnerRadius = Layout.INNER_RADIUS,
		Diameter = Layout.SHOWCASE,
		FloorY = Layout.FLOOR_Y,
		FloorSize = Layout.FLOOR_SIZE,
		Edge = Layout.EDGE,
		Shown = shown.Rings,
		Grown = grown,
		Accent = function(): Color3
			return rarity.Accent
		end,
		CheeredAt = cheeredAt,
		IsActive = isActive,
	})

	local stage = create("Frame")({
		Name = "Stage",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		art,
		view,
		front,
		label({
			Name = "ClassName",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = function()
				return UDim2.new(0.5, 0, 0, Layout.NAME_Y - math.round(Arrive.NAME_FROM * (1 - shown.Name())))
			end,
			Size = UDim2.fromOffset(Layout.VIEW + 180, Layout.NAME_TEXT),
			TextSize = Layout.NAME_TEXT,
			TextTransparency = function()
				return 1 - shown.Name()
			end,
			Text = string.upper(class.Name),
		}),
		create("Frame")({
			Name = "Rarity",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, Layout.TAG.X + Layout.TAG_SIZE.X / 2, 0, Layout.TAG.Y + Layout.TAG_SIZE.Y / 2),
			Size = UDim2.fromOffset(Layout.TAG_SIZE.X, Layout.TAG_SIZE.Y),
			BackgroundColor3 = rarity.Accent,
			BackgroundTransparency = function()
				return 1 - shown.Tag()
			end,
			BorderSizePixel = 0,
			ZIndex = 4,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			create("UIScale")({
				Scale = function()
					return 1 + Arrive.STAMP * (1 - shown.Tag())
				end,
			}),
			label({
				Size = UDim2.fromScale(1, 1),
				TextYAlignment = Enum.TextYAlignment.Center,
				TextSize = Layout.TAG_TEXT,
				TextColor3 = if rarity.IsInk then Palette.Ink else Palette.White,
				TextTransparency = function()
					return 1 - shown.Tag()
				end,
				Text = rarity.Text,
			}),
		}),
	})

	return stage, celebrate
end

return Stage
