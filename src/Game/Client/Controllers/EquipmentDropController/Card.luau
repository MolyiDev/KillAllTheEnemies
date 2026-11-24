--!nonstrict
-- The card a boss drop is shown on (EquipmentDropController): NEW EQUIPMENT on his card in the piece's rarity, under
-- the wave plate, with the piece's own model turning in it over the prize's rays. It lands a little big with a white
-- face and throws one ring (as the squad's banner does), the rays open behind the piece, the light crosses the card, it
-- holds, then leaves shrinking. Not in the designer's set: built from his card, his fonts and the classes' rarity
-- colours (Theme.Rarities). A pure view of the controller's sources, so a story can draw it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local GunPicture = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.GunPicture)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Showcase = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Showcase)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
local Lerp = Motion.Lerp
local PIECES = DataCore.Equipment.ById

-- In px at 1080: the card's middle from the screen's top (under the wave plate and the banner's place), its size, and
-- its pieces from its left edge.
local Layout = table.freeze({
	CENTER_Y = 420,
	SIZE = Vector2.new(600, 150),
	-- Room round the card inside the group that fades it, for its glow and brackets (a CanvasGroup clips).
	MARGIN = 64,
	PICTURE = Vector2.new(84, 75),
	PICTURE_BOX = 140,
	RAYS = 300,
	TEXT_LEFT = 168,
	CAPTION_TOP = 28,
	CAPTION_SIZE = 18,
	NAME_TOP = 54,
	NAME_SIZE = 40,
	TAG_TOP = 104,
	TAG_SIZE = Vector2.new(104, 24),
	TAG_TEXT = 13,
})

local Timing = table.freeze({
	-- How long it is up, start to gone.
	SECONDS = 4.6,
	-- It arrives a little large and settles with no overshoot, and leaves a little small; never faded in: its first
	-- frame is its white one.
	IN = 0.24,
	IN_SCALE = 1.22,
	OUT = 0.3,
	OUT_SCALE = 0.92,
	FLASH = 0.34,
	RING = 0.55,
	RING_GROWTH = 48,
	-- The piece is punched in from big a beat after the card, spinning once onto its sway.
	PICTURE_DELAY = 0.08,
	PICTURE = 0.5,
	PICTURE_SCALE = 1.8,
	SPIN_DEG = 360,
	SWAY_DEG = 24,
	SWAY = 3,
	-- The words come up after the piece, the tag stamps down last.
	WORDS_DELAY = 0.16,
	WORDS = 0.3,
	WORDS_FROM = 14,
	TAG_DELAY = 0.34,
	TAG = 0.28,
	TAG_STAMP = 0.6,
	SHEEN_DELAY = 0.45,
	SHEEN = 0.7,
})

-- What the card reads: the screen's scale, the clock, the piece on show (0 for none) and when it went up.
export type TSpec = {
	Scale: () -> number,
	Now: () -> number,
	Item: () -> number,
	At: () -> number,
}

local Card = {}

-- How long a drop is up, start to gone.
Card.SECONDS = Timing.SECONDS

function Card.Build(spec: TSpec): ScreenGui
	local elapsed = derive(function(): number
		return math.min(spec.Now() - spec.At(), Timing.SECONDS)
	end)
	local item = function()
		return PIECES[spec.Item()]
	end
	local rarity = function()
		local current = item()
		return Theme.Rarities[if current then current.Rarity else "Common"]
	end
	local accent = function(): Color3
		return rarity().Accent
	end
	-- 0 gone, 1 up.
	local shown = function(): number
		return 1 - Motion.Accelerate(Progress(elapsed(), Timing.SECONDS - Timing.OUT, Timing.OUT))
	end
	local pictureIn = function(): number
		return Progress(elapsed(), Timing.PICTURE_DELAY, Timing.PICTURE)
	end
	local wordsIn = function(): number
		return Motion.Decelerate(Progress(elapsed(), Timing.WORDS_DELAY, Timing.WORDS))
	end
	local tagIn = function(): number
		return Motion.Decelerate(Progress(elapsed(), Timing.TAG_DELAY, Timing.TAG))
	end
	local rays = Showcase.Build({
		Look = Showcase.Looks.Prize,
		Diameter = Layout.RAYS,
		Floor = 0,
		FloorSize = nil,
		Accent = accent,
		Shown = shown,
		CheeredAt = spec.At,
		IsActive = function(): boolean
			return elapsed() < Timing.SECONDS
		end,
	}, {
		Position = UDim2.fromOffset(Layout.MARGIN + Layout.PICTURE.X, Layout.MARGIN + Layout.PICTURE.Y),
		ZIndex = 1,
	}, {})

	local size = Layout.SIZE
	return create("ScreenGui")({
		Name = "EquipmentDrop",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		-- Over the HUD, under the upgrade pick and the settings.
		DisplayOrder = 2,
		Enabled = function()
			return spec.Item() ~= 0 and elapsed() < Timing.SECONDS
		end,
		create("Frame")({
			Name = "Root",
			BackgroundTransparency = 1,
			Size = function()
				return UDim2.fromScale(1 / spec.Scale(), 1 / spec.Scale())
			end,
			create("UIScale")({ Scale = spec.Scale }),
			create("Frame")({
				Name = "Drop",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, Layout.CENTER_Y),
				Size = UDim2.fromOffset(size.X, size.Y),
				BackgroundTransparency = 1,
				create("UIScale")({
					Scale = function()
						local t = elapsed()
						local arriving = Lerp(Timing.IN_SCALE, 1, Motion.Decelerate(Progress(t, 0, Timing.IN)))
						local leaving = Lerp(
							1,
							Timing.OUT_SCALE,
							Motion.Accelerate(Progress(t, Timing.SECONDS - Timing.OUT, Timing.OUT))
						)
						return arriving * leaving
					end,
				}),
				-- One ring: the card's outline thrown off it as it lands.
				create("Frame")({
					Name = "Ring",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					BackgroundTransparency = 1,
					Size = function()
						local grown = math.round(Timing.RING_GROWTH * Motion.Out(Progress(elapsed(), 0, Timing.RING)))
						return UDim2.new(1, grown * 2, 1, grown * 2)
					end,
					create("UICorner")({ CornerRadius = UDim.new(0, 5) }),
					create("UIStroke")({
						Thickness = 2,
						Color = accent,
						Transparency = function()
							return 1 - 0.9 * Motion.Fade(elapsed(), 0, Timing.RING)
						end,
					}),
				}),
				create("CanvasGroup")({
					Name = "Card",
					Position = UDim2.fromOffset(-Layout.MARGIN, -Layout.MARGIN),
					Size = UDim2.new(1, Layout.MARGIN * 2, 1, Layout.MARGIN * 2),
					BackgroundTransparency = 1,
					GroupTransparency = function()
						return 1 - shown()
					end,
					rays,
					Components.Card({
						Accent = function()
							return Color3.new():Lerp(accent(), 0.85)
						end,
						Glow = accent,
						GlowTransparency = 0.45,
						Tint = 0.35,
						Marks = true,
						Brackets = true,
						Wide = true,
					}, {
						Position = UDim2.fromOffset(Layout.MARGIN, Layout.MARGIN),
						Size = UDim2.fromOffset(size.X, size.Y),
						ZIndex = 2,
						Components.Sheen(function()
							return Progress(elapsed(), Timing.SHEEN_DELAY, Timing.SHEEN)
						end, 3),
						create("TextLabel")({
							Name = "Caption",
							Position = function()
								return UDim2.fromOffset(
									Layout.TEXT_LEFT,
									Layout.CAPTION_TOP + math.round(Timing.WORDS_FROM * (1 - wordsIn()))
								)
							end,
							Size = UDim2.fromOffset(size.X - Layout.TEXT_LEFT - 16, Layout.CAPTION_SIZE),
							BackgroundTransparency = 1,
							FontFace = Font.Display,
							TextSize = Layout.CAPTION_SIZE,
							TextXAlignment = Enum.TextXAlignment.Left,
							TextColor3 = accent,
							TextTransparency = function()
								return 1 - wordsIn()
							end,
							Text = "NEW EQUIPMENT",
							ZIndex = 4,
						}),
						create("TextLabel")({
							Name = "ItemName",
							Position = function()
								return UDim2.fromOffset(
									Layout.TEXT_LEFT,
									Layout.NAME_TOP + math.round(Timing.WORDS_FROM * (1 - wordsIn()))
								)
							end,
							Size = UDim2.fromOffset(size.X - Layout.TEXT_LEFT - 16, Layout.NAME_SIZE),
							BackgroundTransparency = 1,
							FontFace = Font.Display,
							TextScaled = true,
							TextXAlignment = Enum.TextXAlignment.Left,
							TextColor3 = Palette.White,
							TextTransparency = function()
								return 1 - wordsIn()
							end,
							Text = function()
								local current = item()
								return if current then string.upper(current.Name) else ""
							end,
							ZIndex = 4,
							create("UITextSizeConstraint")({ MaxTextSize = Layout.NAME_SIZE }),
						}),
						create("Frame")({
							Name = "Tag",
							AnchorPoint = Vector2.new(0.5, 0.5),
							Position = UDim2.fromOffset(
								Layout.TEXT_LEFT + Layout.TAG_SIZE.X / 2,
								Layout.TAG_TOP + Layout.TAG_SIZE.Y / 2
							),
							Size = UDim2.fromOffset(Layout.TAG_SIZE.X, Layout.TAG_SIZE.Y),
							BackgroundColor3 = accent,
							BackgroundTransparency = function()
								return 1 - tagIn()
							end,
							BorderSizePixel = 0,
							ZIndex = 4,
							create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
							create("UIScale")({
								Scale = function()
									return 1 + Timing.TAG_STAMP * (1 - tagIn())
								end,
							}),
							create("TextLabel")({
								Size = UDim2.fromScale(1, 1),
								BackgroundTransparency = 1,
								FontFace = Font.Display,
								TextSize = Layout.TAG_TEXT,
								TextColor3 = function()
									return if rarity().IsInk then Palette.Ink else Palette.White
								end,
								TextTransparency = function()
									return 1 - tagIn()
								end,
								Text = function()
									return rarity().Text
								end,
							}),
						}),
						GunPicture.Build(function()
							return GunPicture.FromEquipment(spec.Item())
						end, {
							Yaw = function()
								local t = elapsed()
								local spun = Timing.SPIN_DEG * (1 - Motion.Decelerate(pictureIn()))
								return spun + Timing.SWAY_DEG * math.sin(2 * math.pi * t / Timing.SWAY)
							end,
						}, {
							Name = "Picture",
							AnchorPoint = Vector2.new(0.5, 0.5),
							Position = UDim2.fromOffset(Layout.PICTURE.X, Layout.PICTURE.Y),
							Size = UDim2.fromOffset(Layout.PICTURE_BOX, Layout.PICTURE_BOX),
							ZIndex = 4,
							create("UIScale")({
								Scale = function()
									local t = pictureIn()
									return if t <= 0 then 0 else Lerp(Timing.PICTURE_SCALE, 1, Motion.OutBack(t))
								end,
							}),
						}),
						-- The white the card is born at.
						create("Frame")({
							Name = "Flash",
							Size = UDim2.fromScale(1, 1),
							BackgroundColor3 = Palette.White,
							BorderSizePixel = 0,
							ZIndex = 6,
							BackgroundTransparency = function()
								local flash = Motion.Fade(elapsed(), 0, Timing.FLASH)
								return 1 - 0.9 * flash * flash
							end,
							create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
						}),
					}),
				}),
			}),
		}),
	})
end

return Card
