--!nonstrict
-- The squad's announcement: who used NUKE ALL or HEAL ALL, on a banner under the wave plate, in the item's colour with
-- its glyph. It lands hard (a white face, one ring thrown off it, the glyph punched in), holds while the light runs
-- across it, and leaves by fading and shrinking. The nuke's counts its kills up as the blast rolls out
-- (EnemiesCore.NUKE_SECONDS). Not in the designer's set: built from his panel, his fonts and his two item colours.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local EnemiesCore = require(ReplicatedStorage.Shared.Core.EnemiesCore)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
local Lerp = Motion.Lerp

-- In px at 1080: the banner's centre from the screen's top (under the boss strip and the countdown), its size with
-- and without the kill count, and its pieces from its left edge.
local Layout = table.freeze({
	CENTER_Y = 290,
	HEIGHT = 84,
	WIDTH = 560,
	WIDTH_COUNTED = 680,
	-- Room round the banner inside the group that fades it, for its glow and brackets (a CanvasGroup clips).
	MARGIN = 64,
	GLYPH = Vector2.new(50, 42),
	PICTURE_SIZE = 56,
	TEXT_LEFT = 96,
	NAME_TOP = 15,
	NAME_SIZE = 20,
	WORDS_TOP = 39,
	WORDS_SIZE = 30,
	-- The kill count: a column at the right end, behind a divider.
	COUNT_WIDTH = 128,
	COUNT_TOP = 14,
	COUNT_SIZE = 36,
	COUNT_LABEL_TOP = 53,
	COUNT_LABEL_SIZE = 13,
})

local Timing = table.freeze({
	-- It arrives a little large and settles, with no overshoot; it leaves a little small. It is never faded in: its
	-- first frame is its white one, and at any less than solid that is a grey one.
	IN = 0.22,
	IN_SCALE = 1.2,
	OUT = 0.28,
	OUT_SCALE = 0.94,
	-- The white the face is born at, and the one ring thrown off the banner: how far it grows, in px.
	FLASH = 0.32,
	RING = 0.5,
	RING_GROWTH = 44,
	-- The glyph is punched in: this large, back to its size a little past it.
	GLYPH = 0.38,
	GLYPH_SCALE = 1.7,
	-- The light across the face, once the banner has settled.
	SHEEN_DELAY = 0.3,
	SHEEN = 0.7,
	-- The count's last number lands with a swell.
	COUNT_PUNCH = 0.28,
	COUNT_PUNCH_SCALE = 0.16,
})

local KINDS = table.freeze({
	Nuke = table.freeze({ Icon = EIcons.Bomb, Accent = Palette.Gold, Words = "NUKED ALL ENEMIES", IsCounted = true }),
	Heal = table.freeze({
		Icon = EIcons.Potion,
		Accent = Palette.Green,
		Words = "HEALED ALL PLAYERS",
		IsCounted = false,
	}),
})

local Announce = {}

-- How long a banner is up, start to gone: the HUD's clock runs that long for it.
Announce.SECONDS = 3.6

local function line(top: number, size: number, props: { [any]: any }): TextLabel
	return create("TextLabel")({
		Position = UDim2.fromOffset(Layout.TEXT_LEFT, top),
		Size = UDim2.new(1, -Layout.TEXT_LEFT - 12, 0, size),
		BackgroundTransparency = 1,
		FontFace = Font.Display,
		TextSize = size,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 2,
		props,
	})
end

function Announce.Build(state: Types.THudState): Frame
	local announce = state.Announce
	-- The last kind shown stays drawn while nothing is up, so the banner never changes under its own fade.
	local kind = function()
		return KINDS[announce.Kind()] or KINDS.Nuke
	end
	local accent = function(): Color3
		return kind().Accent
	end
	-- Seconds since it went up, held at SECONDS once it is gone: the HUD's clock also runs for other pieces (a
	-- prompted item breathes every frame), and held, nothing below is worked out again for them.
	local elapsed = derive(function(): number
		return math.min(state.Now() - announce.At(), Announce.SECONDS)
	end)
	-- 0 gone, 1 up.
	local shown = function(): number
		return 1 - Motion.Accelerate(Progress(elapsed(), Announce.SECONDS - Timing.OUT, Timing.OUT))
	end
	local width = function(): number
		return if kind().IsCounted then Layout.WIDTH_COUNTED else Layout.WIDTH
	end
	local counted = function(): number
		return math.round(announce.Count() * Motion.Out(Progress(elapsed(), 0, EnemiesCore.NUKE_SECONDS)))
	end

	return create("Frame")({
		Name = "Announce",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, Layout.CENTER_Y),
		Size = function()
			return UDim2.fromOffset(width(), Layout.HEIGHT)
		end,
		BackgroundTransparency = 1,
		ZIndex = 6,
		Visible = function()
			return announce.Kind() ~= "" and elapsed() < Announce.SECONDS
		end,
		create("UIScale")({
			Scale = function()
				local t = elapsed()
				local arriving = Lerp(Timing.IN_SCALE, 1, Motion.Decelerate(Progress(t, 0, Timing.IN)))
				local leaving =
					Lerp(1, Timing.OUT_SCALE, Motion.Accelerate(Progress(t, Announce.SECONDS - Timing.OUT, Timing.OUT)))
				return arriving * leaving
			end,
		}),
		-- One ring: the banner's outline thrown off it as it lands, growing by pixels and thinning out.
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
			Name = "Banner",
			Position = UDim2.fromOffset(-Layout.MARGIN, -Layout.MARGIN),
			Size = UDim2.new(1, Layout.MARGIN * 2, 1, Layout.MARGIN * 2),
			BackgroundTransparency = 1,
			GroupTransparency = function()
				return 1 - shown()
			end,
			Components.Panel({
				Stroke = accent,
				Glow = accent,
				GlowTransparency = 0.45,
				Brackets = true,
				TexturePhase = Vector2.new(120, 300),
			}, {
				Position = UDim2.fromOffset(Layout.MARGIN, Layout.MARGIN),
				Size = UDim2.new(1, -Layout.MARGIN * 2, 1, -Layout.MARGIN * 2),
				Components.Picture(function()
					return kind().Icon
				end, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(Layout.GLYPH.X, Layout.GLYPH.Y),
					Size = Components.PictureBox(Layout.PICTURE_SIZE),
					ZIndex = 2,
					create("UIScale")({
						Scale = function()
							return Lerp(Timing.GLYPH_SCALE, 1, Motion.OutBack(Progress(elapsed(), 0, Timing.GLYPH)))
						end,
					}),
				}),
				line(Layout.NAME_TOP, Layout.NAME_SIZE, {
					TextColor3 = accent,
					Text = function()
						return string.upper(announce.Name())
					end,
				}),
				line(Layout.WORDS_TOP, Layout.WORDS_SIZE, {
					TextColor3 = Palette.White,
					Text = function()
						return kind().Words
					end,
				}),
				create("Frame")({
					Name = "Count",
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.fromScale(1, 0),
					Size = UDim2.new(0, Layout.COUNT_WIDTH, 1, 0),
					BackgroundTransparency = 1,
					ZIndex = 2,
					Visible = function()
						return kind().IsCounted
					end,
					create("Frame")({
						Name = "Divider",
						Position = UDim2.fromOffset(0, 14),
						Size = UDim2.new(0, 2, 1, -28),
						BackgroundColor3 = accent,
						BackgroundTransparency = 0.6,
						BorderSizePixel = 0,
					}),
					create("TextLabel")({
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.new(0.5, 0, 0, Layout.COUNT_TOP + Layout.COUNT_SIZE / 2),
						Size = UDim2.new(1, -8, 0, Layout.COUNT_SIZE),
						BackgroundTransparency = 1,
						FontFace = Font.Display,
						TextSize = Layout.COUNT_SIZE,
						TextColor3 = accent,
						Text = function()
							return tostring(counted())
						end,
						create("UIScale")({
							Scale = function()
								local landed = Progress(elapsed(), EnemiesCore.NUKE_SECONDS, Timing.COUNT_PUNCH)
								return 1 + Timing.COUNT_PUNCH_SCALE * Motion.Bump(landed)
							end,
						}),
					}),
					create("TextLabel")({
						Position = UDim2.fromOffset(0, Layout.COUNT_LABEL_TOP),
						Size = UDim2.new(1, 0, 0, Layout.COUNT_LABEL_SIZE),
						BackgroundTransparency = 1,
						FontFace = Font.DisplayBold,
						TextSize = Layout.COUNT_LABEL_SIZE,
						TextColor3 = Palette.Lavender,
						Text = "KILLED",
					}),
				}),
				-- Born white: the banner's own first frame is its brightest.
				create("Frame")({
					Name = "Flash",
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = Palette.White,
					BorderSizePixel = 0,
					ZIndex = 4,
					BackgroundTransparency = function()
						local left = Motion.Fade(elapsed(), 0, Timing.FLASH)
						return 1 - 0.95 * left * left
					end,
					create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
				}),
				create("Frame")({
					Name = "SheenWindow",
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					ClipsDescendants = true,
					ZIndex = 3,
					Components.Sheen(function()
						return Progress(elapsed(), Timing.SHEEN_DELAY, Timing.SHEEN)
					end, 3),
				}),
			}),
		}),
	})
end

return Announce
