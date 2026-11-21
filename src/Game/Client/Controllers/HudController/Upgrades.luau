--!nonstrict
-- The left of the screen (UIMatt.md, In-Game HUD): his UPGRADES column and the two Robux money packs under it, on his
-- drawn rects. The weapon card (where he drew SHOTGUN) sells the next step of GunsCore.LADDER; HEALTH and the packs
-- have no system yet, so they are drawn as he did and do nothing.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local GunPicture = require(script.Parent.GunPicture)
local Motion = require(script.Parent.Motion)
local WeaponUpgrade = require(script.Parent.WeaponUpgrade)
local Types = require(script.Parent.Types)

local create = vide.create
local source = vide.source
local spring = vide.spring
local Timing = WeaponUpgrade.Timing
local Palette = Theme.Palette
local Font = Theme.Font

-- His drawn rects at 1080 (from the screen's left and top), and the insides of a card as Shop draws them.
local LEFT = 40
local TITLE_TOP = 302
local TITLE_TEXT = 20
local TOP = 336
local CARD = 150
local STEP = 166
local KEY = Vector2.new(112, 8)
local KEY_SIZE = 30
local PRICE = Vector2.new(12, 81)
local PRICE_TEXT = 28
local NAME = Vector2.new(12, 120)
local NAME_TEXT = 19
local BAND = 35
local GLYPH = Vector2.new(75, 58)
local GLYPH_SIZE = 75
-- The packs: his gold slabs, the coins glyph and the value on them, the green price tag over the top-right corner.
local PACK_LEFT = 39
local PACK_TOP = 689
local PACK = Vector2.new(242, 78)
local PACK_STEP = 92
local PACK_COINS = Vector2.new(35, 34)
local PACK_COINS_SIZE = 32
local PACK_VALUE = 61
local PACK_TEXT = 32
local TAG_TOP = -9
local TAG_RIGHT = -3
local TAG_HEIGHT = 24
local TAG_TEXT = 13
local TAG_PAD = 14
local TAG_COLOR = Color3.fromRGB(15, 158, 99)

-- The weapon card's gun, where his shotgun glyph sits and leaning as it does. As the next step deals in, the gun
-- rises DEAL_RISE into place and its price and name half that; what was bought fades up LEAVE_RISE as it goes.
local PICTURE_CENTER = Vector2.new(75, 54)
local PICTURE_SIZE = 112
local PICTURE_TILT = -18
local DEAL_RISE = 22
local TEXT_DEAL_RISE = 11
local LEAVE_RISE = 12
-- The card as a buy lands: a tilt that swings out and back and dies, and a refused click's knock sideways (UI.md 5c:
-- a jolt, not a swing).
local WOBBLE_DEG = 5
local JOLT = 7

local UPGRADES = table.freeze({
	{ Name = "HEALTH", Price = "$10", Key = Enum.KeyCode.C, Glyph = "Health", Accent = Palette.Green },
})
local PACKS = table.freeze({
	{ Value = "+$99,999", Price = "R$ 99", TagWidth = 64 },
	{ Value = "+$1,000", Price = "R$ 9", TagWidth = 56 },
})

local Upgrades = {}

-- The weapon card's picture: its centre on the screen, its side and its lean, for the bought gun's flight to start
-- from (WeaponUpgrade).
Upgrades.WEAPON_PICTURE = UDim2.fromOffset(LEFT + PICTURE_CENTER.X, TOP + STEP + PICTURE_CENTER.Y)
Upgrades.PICTURE_SIZE = PICTURE_SIZE
Upgrades.PICTURE_TILT = PICTURE_TILT

local function text(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 3,
		props,
	})
end

local function upgradeCard(index: number): Frame
	local upgrade = UPGRADES[index]
	return Components.Card({ Accent = upgrade.Accent, Band = BAND, Brackets = 8 }, {
		Name = upgrade.Name,
		Position = UDim2.fromOffset(LEFT, TOP + STEP * (index - 1)),
		Size = UDim2.fromOffset(CARD, CARD),
		Components.Icon(upgrade.Glyph, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(GLYPH.X, GLYPH.Y),
			Size = Components.GlyphBox(GLYPH_SIZE),
			ZIndex = 2,
		}),
		text({
			Position = UDim2.fromOffset(PRICE.X, PRICE.Y),
			Size = UDim2.new(1, -PRICE.X, 0, PRICE_TEXT),
			TextSize = PRICE_TEXT,
			TextColor3 = Palette.Gold,
			Text = upgrade.Price,
		}),
		text({
			Position = UDim2.fromOffset(NAME.X, NAME.Y),
			Size = UDim2.new(1, -NAME.X, 0, NAME_TEXT),
			TextSize = NAME_TEXT,
			Text = upgrade.Name,
		}),
		Components.KeyBadge(upgrade.Key, KEY_SIZE, {
			Position = UDim2.fromOffset(KEY.X, KEY.Y),
			ZIndex = 3,
		}),
	})
end

-- The step on offer, or the last one in hand once the ladder is climbed.
local function shownStep(state: Types.THudState)
	return state.Weapon.Offer() or state.Weapon.Held()
end

-- Green when the Gold covers it and steel when not, as his are; gold and MAX once the ladder is climbed. A buy punches
-- it gold, sends its gun off to the hotbar (WeaponUpgrade) and deals the next one up with its price counting in.
local function weaponCard(state: Types.THudState, actions: Types.TActions): TextButton
	local weapon = state.Weapon
	local isHovered = source(false)
	local isPressed = source(false)
	local isMaxed = function()
		return weapon.Offer() == nil
	end

	local since = function(): number
		return weapon.Clock() - weapon.BoughtAt()
	end

	local lift = spring(function()
		if isPressed() then return 0.95 end
		return if isHovered() then 1.04 else 1
	end, 0.17, 0.82)

	local punch = function(): number
		local k = Motion.Fade(since(), 0, Timing.PUNCH)
		return k * k
	end

	-- A dip as the ask goes out, before the server's word.
	local press = function(): number
		return Motion.Bump(Motion.Progress(weapon.Clock(), weapon.AskedAt(), Timing.PRESS))
	end

	local wobble = function(): number
		local t = Motion.Progress(since(), 0, Timing.PUNCH)
		if t >= 1 then return 0 end
		return WOBBLE_DEG * math.sin(t * math.pi * 3) * (1 - t) * (1 - t)
	end

	local jolt = function(): number
		local t = Motion.Progress(weapon.Clock(), weapon.DeniedAt(), Timing.JOLT)
		if t >= 1 then return 0 end
		return JOLT * math.sin(t * math.pi * 2) * (1 - t)
	end

	local denied = function(): number
		return Motion.Fade(weapon.Clock(), weapon.DeniedAt(), Timing.DENIED)
	end

	-- 0 to 1 as the next offer deals in after a buy; 1 at rest.
	local deal = function(): number
		return Motion.Progress(since(), 0, Timing.DEAL, Timing.DEAL_AT)
	end

	-- 0 to 1 as what was bought leaves the card, before the deal; 1 at rest, when it is not drawn.
	local leaving = function(): number
		return math.clamp(since() / Timing.DEAL_AT, 0, 1)
	end

	-- The light sweeping the card as it becomes affordable, and the lift it gives the picture.
	local ready = function(): number
		return Motion.Progress(weapon.Clock(), weapon.ReadyAt(), Timing.READY)
	end

	local readyPop = function(): number
		return Motion.Bump(ready())
	end

	local accent = function(): Color3
		local base = if isMaxed() then Palette.Gold elseif weapon.CanAfford() then Palette.Green else Palette.Steel
		return base:Lerp(Palette.Gold, punch())
	end

	local label = function(): string
		if leaving() < 1 then
			local held = weapon.Held()
			return if held then held.Label else ""
		end

		local step = shownStep(state)
		return if step then step.Label else ""
	end

	local price = function(): string
		if leaving() < 1 then
			local held = weapon.Held()
			return if held then `${Components.Commas(held.Price)}` else ""
		end

		local offer = weapon.Offer()
		if not offer then return "MAX" end
		local roll = Motion.Progress(since(), 0, Timing.ROLL, Timing.ROLL_AT)
		return `${Components.Commas(math.floor(offer.Price * Motion.Out(roll) + 0.5))}`
	end

	-- Text that fades up and out as the buy leaves, and rises into place as the next deals in.
	local textTransparency = function(): number
		if leaving() < 1 then return leaving() end
		return 1 - deal()
	end

	local textRise = function(): number
		if leaving() < 1 then return -LEAVE_RISE * leaving() end
		return TEXT_DEAL_RISE * (1 - Motion.Decelerate(deal()))
	end

	return Components.Button({
		Name = "Weapon",
		Position = UDim2.fromOffset(LEFT, TOP + STEP),
		Size = UDim2.fromOffset(CARD, CARD),
		BackgroundTransparency = 1,
		Activated = function()
			actions.UpgradeWeapon()
		end,
		MouseEnter = function()
			isHovered(true)
		end,
		MouseLeave = function()
			isHovered(false)
			isPressed(false)
		end,
		MouseButton1Down = function()
			isPressed(true)
		end,
		MouseButton1Up = function()
			isPressed(false)
		end,
		Components.Card({
			Accent = accent,
			Band = BAND,
			GlowTransparency = function()
				return 0.7 - 0.55 * punch() - 0.3 * readyPop()
			end,
			Brackets = 8,
		}, {
			Name = "Card",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			Position = function()
				return UDim2.new(0.5, math.round(jolt()), 0.5, 0)
			end,
			Rotation = wobble,
			create("UIScale")({
				Scale = function()
					return lift() - 0.06 * press() + 0.14 * punch()
				end,
			}),
			GunPicture.Build(function()
				local step = shownStep(state)
				return if step then GunPicture.FromGun(step.Gun) else nil
			end, {
				Name = "Gun",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(PICTURE_SIZE, PICTURE_SIZE),
				Rotation = PICTURE_TILT,
				ZIndex = 2,
				-- Gone while the bought one flies off it, then risen into place.
				Position = function()
					local rise = if leaving() < 1 then 0 else DEAL_RISE * (1 - Motion.Decelerate(deal()))
					return UDim2.fromOffset(PICTURE_CENTER.X, PICTURE_CENTER.Y + math.round(rise))
				end,
				ImageTransparency = function()
					return if leaving() < 1 then 1 else 1 - deal()
				end,
				create("UIScale")({
					Scale = function()
						return 1 + 0.12 * readyPop()
					end,
				}),
			}),
			text({
				Name = "Price",
				Position = function()
					return UDim2.fromOffset(PRICE.X, PRICE.Y + math.round(textRise()))
				end,
				Size = UDim2.new(1, -PRICE.X, 0, PRICE_TEXT),
				TextSize = PRICE_TEXT,
				TextColor3 = function()
					return Palette.Gold:Lerp(Palette.Pink, denied())
				end,
				TextTransparency = textTransparency,
				Text = price,
			}),
			text({
				Name = "Name",
				Position = function()
					return UDim2.fromOffset(NAME.X, NAME.Y + math.round(textRise()))
				end,
				Size = UDim2.new(1, -NAME.X, 0, NAME_TEXT),
				TextSize = NAME_TEXT,
				TextTransparency = textTransparency,
				Text = label,
			}),
			Components.KeyBadge(state.Keys.Upgrade, KEY_SIZE, {
				Position = UDim2.fromOffset(KEY.X, KEY.Y),
				ZIndex = 3,
			}),
			Components.Sheen(ready, 4),
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 4,
				BackgroundTransparency = function()
					return 1 - 0.7 * punch()
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
			}),
		}),
	}) :: TextButton
end

local function pack(index: number): Frame
	local product = PACKS[index]
	return Components.Slab({ Kind = "Gold", Marks = true, Brackets = 5 }, {
		Name = `Pack{index}`,
		Position = UDim2.fromOffset(PACK_LEFT, PACK_TOP + PACK_STEP * (index - 1)),
		Size = UDim2.fromOffset(PACK.X, PACK.Y),
		Components.Icon("Pack", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(PACK_COINS.X, PACK_COINS.Y),
			Size = Components.GlyphBox(PACK_COINS_SIZE),
			ZIndex = 3,
		}),
		text({
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, PACK_VALUE, 0.5, 0),
			Size = UDim2.new(1, -PACK_VALUE, 0, PACK_TEXT),
			TextYAlignment = Enum.TextYAlignment.Center,
			TextSize = PACK_TEXT,
			Text = product.Value,
		}),
		create("Frame")({
			Name = "Price",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -TAG_RIGHT, 0, TAG_TOP),
			Size = UDim2.fromOffset(product.TagWidth, TAG_HEIGHT),
			BackgroundColor3 = TAG_COLOR,
			BorderSizePixel = 0,
			ZIndex = 4,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			text({
				Position = UDim2.fromOffset(TAG_PAD, 0),
				Size = UDim2.new(1, -TAG_PAD, 1, 0),
				TextYAlignment = Enum.TextYAlignment.Center,
				TextSize = TAG_TEXT,
				Text = product.Price,
			}),
		}),
	})
end

function Upgrades.Build(state: Types.THudState, actions: Types.TActions): Frame
	local children = { weaponCard(state, actions) }
	for index in UPGRADES do
		table.insert(children, upgradeCard(index))
	end
	for index in PACKS do
		table.insert(children, pack(index))
	end

	return create("Frame")({
		Name = "Upgrades",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = function()
			return state.Phase() ~= "Ended"
		end,
		text({
			Name = "Title",
			Position = UDim2.fromOffset(LEFT, TITLE_TOP),
			Size = UDim2.fromOffset(CARD, TITLE_TEXT),
			TextSize = TITLE_TEXT,
			TextColor3 = Palette.Lavender,
			Text = "UPGRADES",
		}),
		children,
	})
end

return Upgrades
