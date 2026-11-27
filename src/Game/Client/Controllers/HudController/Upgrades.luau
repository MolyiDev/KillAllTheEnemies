--!nonstrict
-- The left of the screen (UIMatt.md, In-Game HUD): his UPGRADES column and the two Robux money packs under it, on his
-- drawn rects. The HEALTH card sells the next level of max health (Shared/Utils/healthUpgrades), the weapon card
-- (where he drew SHOTGUN) the next step of the player's ladder, and the packs prompt their Gold products. The two cards
-- are one card (upgradeCard) told what to draw and when: each draws its thing as a model (GunPicture).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local EProducts = require(ReplicatedStorage.Types.Enums.EProducts)
local GunPicture = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.GunPicture)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local HealthUpgrade = require(script.Parent.HealthUpgrade)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local WeaponUpgrade = require(script.Parent.WeaponUpgrade)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font

-- His drawn rects at 1080 (from the screen's left and top), and the insides of a card as Shop draws them.
local LEFT = 40
local TITLE_TOP = 302
local TITLE_TEXT = 20
local TOP = 336
local CARD = 150
-- 169, as the shop's cards.
local STEP = 169
local KEY = Vector2.new(112, 8)
local KEY_SIZE = 30
local PRICE = Vector2.new(12, 81)
local PRICE_TEXT = 28
local NAME = Vector2.new(12, 120)
local NAME_TEXT = 19
local BAND = 35
-- The packs: his gold slabs, the gold pack picture and the value on them, the green price tag over the top-right corner.
local PACK_LEFT = 39
local PACK_TOP = 689
local PACK = Vector2.new(242, 78)
-- 98, not his 92: the second pack's price tag stands 9 px over its top, and at his it met the first pack's brackets.
local PACK_STEP = 98
local PACK_COINS = Vector2.new(35, 34)
local PACK_COINS_SIZE = 40
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
local PICTURE_TILT = GunPicture.CARD_TILT
-- The HEALTH card's first-aid kit, where his glyph sits: its box, and the swing a light across the card gives it.
local KIT_CENTER = Vector2.new(72, 50)
local KIT_SIZE = 86
local KIT_SWING = 10
local DEAL_RISE = 22
local TEXT_DEAL_RISE = 11
local LEAVE_RISE = 12
-- The card as a buy lands: a tilt that swings out and back and dies, and a refused click's shake this far to each
-- side (Motion.Shake).
local WOBBLE_DEG = 5
local JOLT = 7
-- Under the hand: how much the picture grows with the card's rise.
local PICTURE_RISE = 0.08

local PACKS = table.freeze({
	{ Value = "+$99,999", Amount = 99999, Price = "R$ 367", TagWidth = 72, ProductId = EProducts.GoldPackLarge },
	{ Value = "+$1,000", Amount = 1000, Price = "R$ 67", TagWidth = 64, ProductId = EProducts.GoldPackSmall },
})
-- A pack as it is bought (state.GoldPack): its slab swells and goes white, and a light crosses it.
local BOUGHT_SECONDS = 0.5
local BOUGHT_POP = 0.12
local BOUGHT_FLASH = 0.8
-- Under the hand: how much the coins grow with the slab's rise.
local PACK_COINS_RISE = 0.18

local Upgrades = {}

-- A Robux buy's green price tag over the top-right corner of the slab it is put in, as the packs wear theirs.
function Upgrades.PriceTag(width: number, price: string): Frame
	return create("Frame")({
		Name = "Price",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -TAG_RIGHT, 0, TAG_TOP),
		Size = UDim2.fromOffset(width, TAG_HEIGHT),
		BackgroundColor3 = TAG_COLOR,
		BorderSizePixel = 0,
		ZIndex = 4,
		create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		create("TextLabel")({
			Position = UDim2.fromOffset(TAG_PAD, 0),
			Size = UDim2.new(1, -TAG_PAD, 1, 0),
			BackgroundTransparency = 1,
			FontFace = Font.Display,
			TextColor3 = Palette.White,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextSize = TAG_TEXT,
			ZIndex = 3,
			Text = price,
		}),
	}) :: Frame
end

-- The weapon card's picture: its centre on the screen, its side and its lean, for the bought gun's flight to start
-- from (WeaponUpgrade).
Upgrades.WEAPON_PICTURE = UDim2.fromOffset(LEFT + PICTURE_CENTER.X, TOP + STEP + PICTURE_CENTER.Y)
Upgrades.PICTURE_SIZE = PICTURE_SIZE
Upgrades.PICTURE_TILT = PICTURE_TILT
-- The HEALTH card's picture: its centre on the screen and its side, for the bought kit's flight (HealthUpgrade).
Upgrades.HEALTH_PICTURE = UDim2.fromOffset(LEFT + KIT_CENTER.X, TOP + KIT_CENTER.Y)
Upgrades.HEALTH_PICTURE_SIZE = KIT_SIZE

-- What a card's picture is told of the card's motion, each 0 to 1: `Leaving` as what was bought goes (1 at rest,
-- when it is gone), `Deal` as the next offer comes in (1 at rest), `Ready` as the light crosses a card that became
-- affordable (1 at rest), `ReadyPop`, the lift that light gives (0 at rest), and `Rise`, the card's rise under the
-- hand (0 at rest).
type TCardMotion = {
	Leaving: () -> number,
	Deal: () -> number,
	Ready: () -> number,
	ReadyPop: () -> number,
	Rise: () -> number,
}

-- One card of the column. `Stamps` is its part of the HUD's state and `Timing` the show its buy runs on
-- (WeaponUpgrade.Timing's names). `Label` and `Cost` are asked with true for what was just bought, while it leaves
-- the card, and false for what is on offer; a nil cost is a card with nothing left to sell.
type TCardSpec = {
	Name: string,
	Top: number,
	Stamps: Types.TWeaponUpgrade | Types.THealthUpgrade,
	Timing: { [string]: number },
	Key: Enum.KeyCode,
	Activated: () -> (),
	Label: (isLeaving: boolean) -> string,
	Cost: (isLeaving: boolean) -> number?,
	Picture: (motion: TCardMotion) -> Frame,
}

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

-- A card selling the next step of something. Green when the Gold covers it and steel when not, as his are; gold and
-- MAX once there is nothing left to buy. A buy punches it gold, sends what was bought off (the show's own module)
-- and deals the next one up with its price counting in.
local function upgradeCard(spec: TCardSpec): TextButton
	local stamps = spec.Stamps
	local timing = spec.Timing
	local isMaxed = function()
		return spec.Cost(false) == nil
	end
	local hand = Hand.React("Take", function()
		return stamps.CanAfford() and not isMaxed()
	end)

	-- Seconds since the last buy, held at the show's length once it is over. Derived, so what runs off the buy alone
	-- is not worked out again on the frames the clock runs for a press, a refusal or the light.
	local since = derive(function(): number
		return math.min(stamps.Clock() - stamps.BoughtAt(), timing.TOTAL)
	end)

	local punch = function(): number
		local k = Motion.Fade(since(), 0, timing.PUNCH)
		return k * k
	end

	-- A dip as the ask goes out, before the server's word.
	local press = function(): number
		return Motion.Bump(Motion.Progress(stamps.Clock(), stamps.AskedAt(), timing.PRESS))
	end

	local wobble = function(): number
		local t = Motion.Progress(since(), 0, timing.PUNCH)
		if t >= 1 then return 0 end
		return WOBBLE_DEG * math.sin(t * math.pi * 3) * (1 - t) * (1 - t)
	end

	local jolt = function(): number
		local at = stamps.DeniedAt()
		return JOLT * Motion.Shake(Motion.Progress(stamps.Clock(), at, timing.JOLT), at)
	end

	local denied = function(): number
		return Motion.Fade(stamps.Clock(), stamps.DeniedAt(), timing.DENIED)
	end

	-- 0 to 1 as the next offer deals in after a buy; 1 at rest.
	local deal = function(): number
		return Motion.Progress(since(), 0, timing.DEAL, timing.DEAL_AT)
	end

	-- 0 to 1 as what was bought leaves the card, before the deal; 1 at rest, when it is not drawn.
	local leaving = function(): number
		return math.clamp(since() / timing.DEAL_AT, 0, 1)
	end

	-- The light sweeping the card as it becomes affordable, and the lift it gives the picture.
	local ready = function(): number
		return Motion.Progress(stamps.Clock(), stamps.ReadyAt(), timing.READY)
	end

	local readyPop = function(): number
		return Motion.Bump(ready())
	end

	local accent = function(): Color3
		local base = if isMaxed() then Palette.Gold elseif stamps.CanAfford() then Palette.Green else Palette.Steel
		return base:Lerp(Palette.Gold, punch())
	end

	local label = function(): string
		return spec.Label(leaving() < 1)
	end

	local price = function(): string
		if leaving() < 1 then
			local paid = spec.Cost(true)
			return if paid then `${Components.Commas(paid)}` else ""
		end

		local cost = spec.Cost(false)
		if not cost then return "MAX" end
		local roll = Motion.Progress(since(), 0, timing.ROLL, timing.ROLL_AT)
		return `${Components.Commas(math.floor(cost * Motion.Out(roll) + 0.5))}`
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
		Name = spec.Name,
		Position = UDim2.fromOffset(LEFT, spec.Top),
		Size = UDim2.fromOffset(CARD, CARD),
		BackgroundTransparency = 1,
		Activated = function()
			hand.Commit()
			spec.Activated()
		end,
		hand.Events,
		Components.Card({
			Accent = accent,
			Band = BAND,
			GlowTransparency = function()
				return 0.7 - math.max(0.55 * punch(), 0.3 * readyPop(), 0.4 * hand.Light())
			end,
			Brackets = hand.Rise,
			BracketTransparency = function()
				return 0.65 - 0.35 * hand.Light()
			end,
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
					return hand.Scale() - 0.06 * press() + 0.14 * punch()
				end,
			}),
			spec.Picture({ Leaving = leaving, Deal = deal, Ready = ready, ReadyPop = readyPop, Rise = hand.Rise }),
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
				Size = UDim2.new(1, -NAME.X * 2, 0, NAME_TEXT),
				-- A loadout gun's name can be far longer than the card was drawn for: it shrinks to fit.
				TextScaled = true,
				TextTransparency = textTransparency,
				Text = label,
				create("UITextSizeConstraint")({ MaxTextSize = NAME_TEXT }),
			}),
			Components.KeyBadge(spec.Key, KEY_SIZE, {
				Position = UDim2.fromOffset(KEY.X, KEY.Y),
				ZIndex = 3,
			}),
			Components.Sheen(Hand.Sheen(hand, ready), 4),
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 4,
				BackgroundTransparency = function()
					return 1 - math.max(0.7 * punch(), hand.Wash())
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
			}),
		}),
	}) :: TextButton
end

-- What a card's picture does as its card deals: gone while what was bought flies off it, then risen into place.
local function dealtTransparency(motion: TCardMotion): () -> number
	return function()
		return if motion.Leaving() < 1 then 1 else 1 - motion.Deal()
	end
end

local function dealtPosition(motion: TCardMotion, center: Vector2): () -> UDim2
	return function()
		local rise = if motion.Leaving() < 1 then 0 else DEAL_RISE * (1 - Motion.Decelerate(motion.Deal()))
		return UDim2.fromOffset(center.X, center.Y + math.round(rise))
	end
end

-- The step on offer, or the last one in hand once the ladder is climbed.
local function shownStep(state: Types.THudState)
	return state.Weapon.Offer() or state.Weapon.Held()
end

-- HEALTH: the first-aid kit, the next level's price. A buy throws the kit into the health bar (HealthUpgrade).
local function healthCard(state: Types.THudState, actions: Types.TActions): TextButton
	local vital = state.Vital
	return upgradeCard({
		Name = "Health",
		Top = TOP,
		Stamps = vital,
		Timing = HealthUpgrade.Timing,
		Key = state.Keys.Health,
		Activated = function()
			actions.UpgradeHealth()
		end,
		Label = function()
			return "HEALTH"
		end,
		Cost = function(isLeaving: boolean)
			return if isLeaving then vital.Paid() else vital.Price()
		end,
		Picture = function(motion: TCardMotion)
			return GunPicture.Build(HealthUpgrade.Picture, {
				Ambient = GunPicture.FLAT_AMBIENT,
				Light = GunPicture.FLAT_LIGHT,
				Rotation = function()
					return KIT_SWING * Motion.Swing(motion.Ready())
				end,
				Transparency = dealtTransparency(motion),
			}, {
				Name = "Kit",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(KIT_SIZE, KIT_SIZE),
				ZIndex = 2,
				Position = dealtPosition(motion, KIT_CENTER),
				create("UIScale")({
					Scale = function()
						return 1 + 0.12 * motion.ReadyPop() + PICTURE_RISE * motion.Rise()
					end,
				}),
			})
		end,
	})
end

-- The weapon: the gun of the next step and its price. A buy sends its gun off to the hotbar (WeaponUpgrade).
local function weaponCard(state: Types.THudState, actions: Types.TActions): TextButton
	local weapon = state.Weapon
	return upgradeCard({
		Name = "Weapon",
		Top = TOP + STEP,
		Stamps = weapon,
		Timing = WeaponUpgrade.Timing,
		Key = state.Keys.Upgrade,
		Activated = function()
			actions.UpgradeWeapon()
		end,
		Label = function(isLeaving: boolean)
			local step = if isLeaving then weapon.Held() else shownStep(state)
			return if step then step.Label else ""
		end,
		Cost = function(isLeaving: boolean)
			local step = if isLeaving then weapon.Held() else weapon.Offer()
			return if step then step.Price else nil
		end,
		Picture = function(motion: TCardMotion)
			return GunPicture.Build(function()
				local step = shownStep(state)
				return if step then GunPicture.FromGun(step.Gun) else nil
			end, {
				Rotation = PICTURE_TILT,
				Transparency = dealtTransparency(motion),
			}, {
				Name = "Gun",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(PICTURE_SIZE, PICTURE_SIZE),
				ZIndex = 2,
				Position = dealtPosition(motion, PICTURE_CENTER),
				create("UIScale")({
					Scale = function()
						return 1 + 0.12 * motion.ReadyPop() + PICTURE_RISE * motion.Rise()
					end,
				}),
			})
		end,
	})
end

local function pack(state: Types.THudState, index: number, actions: Types.TActions): TextButton
	local product = PACKS[index]
	-- 0 to 1 through the moment this pack is bought; 1 at rest, and for the other pack. Derived, so the frames it
	-- is not moving redraw nothing here.
	local bought = derive(function(): number
		if state.GoldPack.Amount() ~= product.Amount then return 1 end
		return Motion.Progress(state.Now(), state.GoldPack.At(), BOUGHT_SECONDS)
	end)
	local pop = function(): number
		local k = 1 - bought()
		return k * k
	end
	local hand = Hand.React("Take")

	-- Anchored at its centre, so it swells from the middle.
	return Components.Button({
		Name = `Pack{index}`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(PACK_LEFT + PACK.X / 2, PACK_TOP + PACK_STEP * (index - 1) + PACK.Y / 2),
		Size = UDim2.fromOffset(PACK.X, PACK.Y),
		BackgroundTransparency = 1,
		Activated = function()
			hand.Commit()
			actions.BuyProduct(product.ProductId)
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return hand.Scale() + BOUGHT_POP * pop()
			end,
		}),
		Components.Slab({
			Kind = "Gold",
			Marks = true,
			Brackets = hand.Rise,
			GlowTransparency = function()
				return 0.6 - 0.35 * hand.Light()
			end,
		}, {
			Size = UDim2.fromScale(1, 1),
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 5,
				BackgroundTransparency = function()
					return 1 - math.max(BOUGHT_FLASH * pop(), hand.Wash())
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
			}),
			create("Frame")({
				Name = "SheenWindow",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ClipsDescendants = true,
				ZIndex = 5,
				Components.Sheen(Hand.Sheen(hand, bought), 5),
			}),
			Components.Picture(EIcons.GoldSack, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(PACK_COINS.X, PACK_COINS.Y),
				Size = Components.PictureBox(PACK_COINS_SIZE),
				ZIndex = 3,
				create("UIScale")({
					Scale = function()
						return 1 + PACK_COINS_RISE * hand.Rise()
					end,
				}),
			}),
			text({
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, PACK_VALUE, 0.5, 0),
				Size = UDim2.new(1, -PACK_VALUE, 0, PACK_TEXT),
				TextYAlignment = Enum.TextYAlignment.Center,
				TextSize = PACK_TEXT,
				Text = product.Value,
			}),
			Upgrades.PriceTag(product.TagWidth, product.Price),
		}),
	})
end

function Upgrades.Build(state: Types.THudState, actions: Types.TActions): Frame
	local children = { healthCard(state, actions), weaponCard(state, actions) }
	for index in PACKS do
		table.insert(children, pack(state, index, actions))
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
