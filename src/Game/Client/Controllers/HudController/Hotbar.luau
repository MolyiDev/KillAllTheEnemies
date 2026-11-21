--!nonstrict
-- The bottom centre (UIMatt.md, Round Money and Hotbar): the run's Gold on a gold coin square and a plate, and the
-- five slots with the gun in hand in the first. In first person, where the overhead bar cannot be seen, a health bar
-- shows above the Gold instead.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local GunPicture = require(script.Parent.GunPicture)
local HealthBar = require(script.Parent.HealthBar)
local Motion = require(script.Parent.Motion)
local Types = require(script.Parent.Types)

local create = vide.create
local Palette = Theme.Palette
local Font = Theme.Font

-- His drawn rects at 1080, x from the screen's centre: the gold coin square and the money plate ending 136 above the
-- bottom, the coins glyph and the amount; the slots 96 square every 108 ending 24 above the bottom, the key in each
-- corner, and the white frame round the slot in hand.
local Layout = table.freeze({
	MONEY_BOTTOM = 136,
	MONEY_HEIGHT = 84,
	COIN_LEFT = -137,
	COIN_GLYPH = 51,
	PLATE_LEFT = -53,
	PLATE_WIDTH = 190,
	MONEY_TEXT = 53,
	SLOTS = 5,
	SLOT = 96,
	SLOT_STEP = 108,
	SLOT_FIRST = -264,
	SLOTS_BOTTOM = 24,
	KEY = 4,
	KEY_SIZE = 24,
	HELD_OUTSET = 4,
	-- The gun's picture, as a share of its slot.
	GUN_SHARE = 0.86,
	-- The overhead bar's shape (HealthBar), drawn bigger.
	HEALTH_WIDTH = 300,
	HEALTH_HEIGHT = 30,
})
local SWAP_SECONDS = 0.35
-- A bought upgrade landing in the gun's slot hits harder than a plain swap, and for longer.
local LAND_SECONDS = 0.5
local LAND_PUNCH = 0.2
local LAND_FLASH = 0.8
local SLOT_KEYS =
	table.freeze({ Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five })
local JOLT = 6
local COIN_EDGE = Color3.fromRGB(255, 221, 147)
local HELD = Color3.fromRGB(110, 74, 204)
local EMPTY = Color3.fromRGB(112, 89, 171)

local Hotbar = {}

-- Where the money block's top sits above the screen's bottom edge, for anything that must stay clear of it.
Hotbar.HEIGHT = Layout.MONEY_BOTTOM + Layout.MONEY_HEIGHT
-- The middle of the money plate's top edge, the gun's slot's centre and the size of the gun's picture in it, for
-- what flies to them.
Hotbar.MONEY_TOP = UDim2.new(0.5, Layout.PLATE_LEFT + Layout.PLATE_WIDTH / 2, 1, -Hotbar.HEIGHT)
Hotbar.GUN_SLOT = UDim2.new(0.5, Layout.SLOT_FIRST + Layout.SLOT / 2, 1, -Layout.SLOTS_BOTTOM - Layout.SLOT / 2)
Hotbar.GUN_PICTURE = Layout.SLOT * Layout.GUN_SHARE

-- ============================== Health (first person) ==============================

local function healthBar(state: Types.THudState): Frame
	return HealthBar.Build(state, {
		Name = "Health",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(Hotbar.HEIGHT + 14)),
		Size = UDim2.fromOffset(Layout.HEALTH_WIDTH, Layout.HEALTH_HEIGHT),
		Visible = state.IsFirstPerson,
	})
end

-- ============================== Gold ==============================

local function money(state: Types.THudState): Frame
	local pulse = function(): number
		local k = state.GoldPulse()
		return k * k
	end

	local jolt = function(): number
		local t = math.clamp((1 - state.GoldDenied()) * 3, 0, 1)
		if t >= 1 then return 0 end
		return JOLT * math.sin(t * math.pi * 2) * (1 - t)
	end

	return create("Frame")({
		Name = "Money",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		create("Frame")({
			Name = "Coin",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				return UDim2.new(
					0.5,
					Layout.COIN_LEFT + Layout.MONEY_HEIGHT / 2 + math.round(jolt()),
					1,
					-Layout.MONEY_BOTTOM - Layout.MONEY_HEIGHT / 2
				)
			end,
			Size = UDim2.fromOffset(Layout.MONEY_HEIGHT, Layout.MONEY_HEIGHT),
			BackgroundColor3 = COIN_EDGE,
			BorderSizePixel = 0,
			ZIndex = 2,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			create("UIScale")({
				Scale = function()
					return 1 + 0.1 * pulse()
				end,
			}),
			create("UIShadow")({
				BlurRadius = UDim.new(0, 20),
				Color = Palette.Gold,
				Spread = UDim2.new(),
				Transparency = function()
					return 1 - 0.5 * pulse()
				end,
				ZIndex = -1,
			}),
			create("Frame")({
				Position = UDim2.fromOffset(1, 1),
				Size = UDim2.new(1, -2, 1, -2),
				BackgroundColor3 = Palette.Gold,
				BorderSizePixel = 0,
				create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
			}),
			Components.Icon("Coins", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = Components.GlyphBox(Layout.COIN_GLYPH),
				ImageColor3 = Palette.Ink,
				ZIndex = 2,
				Rotation = function()
					return -8 * pulse()
				end,
			}),
		}),
		Components.Panel({
			Glow = Palette.Gold,
			GlowTransparency = function()
				return if pulse() > 0 then 1 - 0.45 * pulse() else 1
			end,
		}, {
			Name = "Plate",
			Position = function()
				return UDim2.new(
					0.5,
					Layout.PLATE_LEFT + math.round(jolt()),
					1,
					-Layout.MONEY_BOTTOM - Layout.MONEY_HEIGHT
				)
			end,
			Size = UDim2.fromOffset(Layout.PLATE_WIDTH, Layout.MONEY_HEIGHT),
			create("TextLabel")({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, -16, 0, Layout.MONEY_TEXT),
				BackgroundTransparency = 1,
				FontFace = Font.Display,
				TextScaled = true,
				ZIndex = 2,
				TextColor3 = function()
					return Palette.Gold:Lerp(Palette.White, 0.45 * pulse()):Lerp(Palette.Pink, state.GoldDenied())
				end,
				Text = function()
					return `${Components.Commas(state.GoldShown())}`
				end,
				create("UITextSizeConstraint")({ MaxTextSize = Layout.MONEY_TEXT }),
				create("UIScale")({
					Scale = function()
						return 1 + 0.08 * pulse()
					end,
				}),
			}),
		}),
	})
end

-- ============================== The gun's slot ==============================

-- The held gun side on, barrel to the right. The Tool's Handle faces out of the barrel with its up the gun's
-- (buildGunTool), so it gives the axes.
local function heldPicture(state: Types.THudState): GunPicture.TPicture?
	local held = state.GunModel()
	local handle = if held and held.Parent then held.Parent:FindFirstChild("Handle") :: BasePart? else nil
	if not held or not handle then return nil end
	local frame = handle.CFrame
	return { Model = held, Origin = frame.Position, Barrel = frame.LookVector, Up = frame.UpVector }
end

local function slot(state: Types.THudState, index: number): Frame
	local isGun = index == 1
	local isFilled = function()
		return isGun and state.GunModel() ~= nil
	end

	local swap = function(): number
		if not isGun then return 0 end
		local k = Motion.Fade(state.Now(), state.GunAt(), SWAP_SECONDS)
		return k * k
	end

	-- 1 as a bought gun lands, fading; 0 before it lands.
	local landed = function(): number
		if not isGun then return 0 end
		local now, landAt = state.Weapon.Clock(), state.Weapon.LandAt()
		if now < landAt then return 0 end
		local k = Motion.Fade(now, landAt, LAND_SECONDS)
		return k * k
	end

	-- The slot stands empty while the bought gun is in the air.
	local isAwaiting = function(): boolean
		local now = state.Weapon.Clock()
		return isGun and now >= state.Weapon.BoughtAt() and now < state.Weapon.LandAt()
	end

	-- Anchored at its centre, so the swap punch grows from the middle.
	return Components.Card({
		Accent = function()
			return if isFilled() then HELD else EMPTY
		end,
		Tint = function()
			return if isFilled() then 0.45 else 0.15
		end,
		Marks = true,
		GlowTransparency = function()
			return if isFilled() then 0.7 - math.max(0.3 * swap(), 0.6 * landed()) else 0.85
		end,
		-- The slot in hand wears the white frame instead.
		Brackets = 8,
		BracketTransparency = function()
			return if isFilled() then 1 else 0.65
		end,
	}, {
		Name = `Slot{index}`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(
			0.5,
			Layout.SLOT_FIRST + Layout.SLOT_STEP * (index - 1) + Layout.SLOT / 2,
			1,
			-Layout.SLOTS_BOTTOM - Layout.SLOT / 2
		),
		Size = UDim2.fromOffset(Layout.SLOT, Layout.SLOT),
		create("UIScale")({
			Scale = function()
				return 1 + 0.1 * swap() + LAND_PUNCH * landed()
			end,
		}),
		-- His white frame round the slot in hand, standing off its edge.
		create("Frame")({
			Name = "Held",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 2 * Layout.HELD_OUTSET, 1, 2 * Layout.HELD_OUTSET),
			BackgroundTransparency = 1,
			create("UIStroke")({
				Color = Palette.White,
				Thickness = 2,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Transparency = function()
					return if isFilled() then 0.09 else 1
				end,
			}),
			create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
		}),
		if isGun
			then GunPicture.Build(function()
				return heldPicture(state)
			end, {
				Name = "Gun",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.52),
				Size = UDim2.fromScale(Layout.GUN_SHARE, Layout.GUN_SHARE),
				ZIndex = 2,
				ImageTransparency = function()
					return if isAwaiting() then 1 else 0
				end,
			})
			else nil,
		Components.KeyBadge(SLOT_KEYS[index], Layout.KEY_SIZE, {
			Position = UDim2.fromOffset(Layout.KEY, Layout.KEY),
			ZIndex = 3,
		}),
		create("Frame")({
			Name = "Flash",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Palette.White,
			BorderSizePixel = 0,
			ZIndex = 4,
			BackgroundTransparency = function()
				return 1 - math.max(0.5 * swap(), LAND_FLASH * landed())
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
		}),
	})
end

function Hotbar.Build(state: Types.THudState): Frame
	local slots = table.create(Layout.SLOTS)
	for index = 1, Layout.SLOTS do
		slots[index] = slot(state, index)
	end

	return create("Frame")({
		Name = "Hotbar",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = function()
			return state.Phase() ~= "Ended"
		end,
		money(state),
		slots,
		healthBar(state),
	})
end

return Hotbar
