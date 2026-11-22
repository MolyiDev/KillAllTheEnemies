--!nonstrict
-- The ABILITIES column on the right (UIMatt.md, Abilities), his cards on his drawn rects: the class's two abilities,
-- then his ULT card with its charge bar beside it, for the class's ultimate. The run's defenses
-- are not offered for now.
-- Each card draws its ability as a model (GunPicture), from ReplicatedStorage.Models.Abilities (Rojo's, made by
-- Assets/models/Abilities). A kind with no model there draws nothing, as a gun with none does.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local GunPicture = require(script.Parent.GunPicture)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font

-- His drawn rects at 1080: the cards' left edge from the screen's right, the first card's top and the step down, the
-- title's right edge and top; inside a card the key, price, name, band and glyph; the charge bar beside the ULT card.
local RIGHT = 190
local TOP = 336
local CARD = 150
local STEP = 166
local TITLE_RIGHT = 32
local TITLE_TOP = 302
local TITLE_TEXT = 19
local KEY = Vector2.new(112, 8)
local KEY_SIZE = 30
local PRICE = Vector2.new(12, 81)
local PRICE_TEXT = 28
local NAME = Vector2.new(12, 120)
local NAME_TEXT = 19
local BAND = 35
local GLYPH = Vector2.new(75, 58)
-- An ability's model on its card: the box it is fitted to (its centre is the glyph's), and by kind how it is looked
-- at: the camera's turn round it from its front and its height over it (deg), and how far the picture leans.
local PICTURE = 100
local VIEWS = table.freeze({
	Decoy = { Yaw = 28, Pitch = 13, Lean = 0 },
	FoamCannon = { Yaw = 26, Pitch = 14, Lean = 14 },
	OrbitalCannon = { Yaw = 28, Pitch = 10, Lean = -12 },
})
-- What the model does on its card: grown with the card's rise under the pointer, punched and swung as the ability is
-- used and as it comes ready (shares of its size, deg), and on the ULT card breathing while it waits to be fired. The
-- brackets stand off the card BRACKETS px and open BRACKETS_OPEN more under the hand.
local Gesture = table.freeze({
	HOVER = 0.08,
	BRACKETS = 8,
	BRACKETS_OPEN = 4,
	USED_POP = 0.26,
	USED_SPIN = -16,
	READY_POP = 0.3,
	READY_SPIN = 14,
	BREATH = 0.06,
	BREATH_SPIN = 4,
})
local CHARGE_RIGHT = 234
local CHARGE_BAR = Vector2.new(6, 32)
local CHARGE_BAR_SIZE = Vector2.new(26, 118)
local CHARGE_TAG = Vector2.new(38, 26)
local CHARGE_TEXT = 16
local CHARGE_EDGE = Color3.fromRGB(144, 109, 44)
-- A refused click knocks the card sideways this far and stops dead (UI.md 5c: a jolt, not a swing).
local JOLT = 7
local JOLT_SECONDS = 0.16
local PLACED_SECONDS = 0.4
local PLACING_HZ = 1.6
-- The ULT card as its meter fills: the pop, the light across it.
local CHARGED_SECONDS = 0.5
-- An ability's card as it is used and as it comes ready, and how dark its cooldown's shade is.
local USED_SECONDS = 0.3
local USED_DIP = 0.1
local READY_POP = 0.14
local SHADE = 0.3

local Shop = {}

local pictures: { [string]: GunPicture.TPicture | false } = {}

-- The picture of the model of ability `kind`, or nil when the place has none.
local function pictureOf(kind: string): GunPicture.TPicture?
	local cached = pictures[kind]
	if cached ~= nil then return cached or nil end

	local models = ReplicatedStorage:FindFirstChild("Models")
	local folder = if models then models:FindFirstChild("Abilities") else nil
	local model = if folder then folder:FindFirstChild(kind) else nil
	local view = VIEWS[kind]
	local picture: GunPicture.TPicture | false = false
	if model and model:IsA("Model") and view then picture = GunPicture.FromModel(model, view.Yaw, view.Pitch) end

	pictures[kind] = picture
	return picture or nil
end

-- The picture of `avatar` (a copy of a character), looked at from its front (a character faces down its root's -Z)
-- and from the side of its right arm, the one that waves (AvatarPose), so the head never hides it.
local function avatarPicture(avatar: Model): GunPicture.TPicture?
	local root = avatar:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return nil end

	local view = VIEWS.Decoy
	local frame = root.CFrame.Rotation
		* CFrame.Angles(0, math.pi - math.rad(view.Yaw), 0)
		* CFrame.Angles(-math.rad(view.Pitch), 0, 0)
	return { Model = avatar, Origin = avatar:GetBoundingBox().Position, Barrel = frame.XVector, Up = frame.YVector }
end

-- The model of ability `kind` where a card's glyph sits. `spec` holds sources: Rotation (a turn in the card's plane,
-- deg), Transparency and Scale. The Decoy is the player's own avatar once `avatar` has one, as the doll is.
local function modelPicture(kind: string, spec: { [string]: any }, avatar: (() -> Model?)?): Frame
	local picture = pictureOf(kind)
	-- Derived, so the frames a gesture is not running write nothing: state.Now ticks for every coin that lands, and
	-- these hold one value at rest.
	local rotation = derive(spec.Rotation)
	local scale = derive(spec.Scale)

	return GunPicture.Build(function()
		local copy = if avatar then avatar() else nil
		return (if copy then avatarPicture(copy) else nil) or picture
	end, {
		Lean = VIEWS[kind].Lean,
		Rotation = rotation,
		Transparency = spec.Transparency,
		Ambient = GunPicture.FLAT_AMBIENT,
		Light = GunPicture.FLAT_LIGHT,
	}, {
		Name = "Picture",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(GLYPH.X, GLYPH.Y),
		Size = UDim2.fromOffset(PICTURE, PICTURE),
		ZIndex = 3,
		create("UIScale")({ Scale = scale }),
	})
end

-- An ability's card: in its own colour with its price in Gold while it can be used; steel when the Gold is short, and
-- under a shade that drains off the top with the seconds left while it cools. A use punches it down and flashes it, the moment it is ready again it pops
-- with a light across its face, and a press it refuses knocks it sideways.
local function abilityCard(state: Types.THudState, actions: Types.TActions, index: number): TextButton
	local ability = state.Abilities[index]
	local isCooling = function(): boolean
		return ability.Cooling() > 0
	end

	local canUse = function(): boolean
		return not isCooling() and state.Gold() >= ability.Cost
	end
	local hand = Hand.React("Take", canUse)

	local used = function(): number
		local k = Motion.Fade(state.Now(), ability.UsedAt(), USED_SECONDS)
		return k * k
	end

	-- 0 to 1 through the moment it comes ready; 1 at rest.
	local ready = function(): number
		return Motion.Progress(state.Now(), ability.ReadyAt(), CHARGED_SECONDS)
	end

	local jolt = function(): number
		local t = Motion.Progress(state.Now(), ability.DeniedAt(), JOLT_SECONDS)
		if t >= 1 then return 0 end
		return JOLT * math.sin(t * math.pi * 2) * (1 - t)
	end

	return Components.Button({
		Name = `Ability{index}`,
		Position = UDim2.new(1, -RIGHT, 0, TOP + STEP * (index - 1)),
		Size = UDim2.fromOffset(CARD, CARD),
		BackgroundTransparency = 1,
		Activated = function()
			hand.Commit()
			actions.CastAbility(ability.Slot)
		end,
		hand.Events,
		Components.Card({
			Accent = function()
				return if canUse() then ability.Accent else Palette.Steel
			end,
			Band = BAND,
			Brackets = function()
				return Gesture.BRACKETS + Gesture.BRACKETS_OPEN * hand.Rise()
			end,
			BracketTransparency = function()
				return 0.65 - 0.35 * hand.Light()
			end,
			GlowTransparency = function()
				if not canUse() then return 0.9 end
				local pop = 1 - ready()
				return 0.7 - math.max(0.5 * pop * pop, 0.4 * hand.Light())
			end,
		}, {
			Name = "Card",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			Position = function()
				return UDim2.new(0.5, math.round(jolt()), 0.5, 0)
			end,
			create("UIScale")({
				Scale = function()
					local pop = 1 - ready()
					return hand.Scale() - USED_DIP * used() + READY_POP * pop * pop
				end,
			}),
			modelPicture(ability.Kind, {
				Transparency = function()
					return if isCooling() then 0.3 elseif canUse() then 0 else 0.25
				end,
				Rotation = function()
					return Gesture.USED_SPIN
							* Motion.Swing(Motion.Progress(state.Now(), ability.UsedAt(), CHARGED_SECONDS))
						+ Gesture.READY_SPIN * Motion.Swing(ready())
				end,
				Scale = function()
					local pop = 1 - ready()
					return 1 + Gesture.HOVER * hand.Rise() + Gesture.USED_POP * used() + Gesture.READY_POP * pop * pop
				end,
			}, if ability.Kind == "Decoy" then state.Avatar else nil),
			create("TextLabel")({
				Name = "State",
				Position = UDim2.fromOffset(PRICE.X, PRICE.Y),
				Size = UDim2.new(1, -PRICE.X, 0, PRICE_TEXT),
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				FontFace = Font.Display,
				TextSize = PRICE_TEXT,
				ZIndex = 4,
				TextColor3 = function()
					if isCooling() then return Palette.White end
					return Palette.Gold:Lerp(Palette.Pink, Motion.Fade(state.Now(), ability.DeniedAt(), 0.5))
				end,
				TextTransparency = function()
					return if isCooling() or canUse() then 0 else 0.35
				end,
				Text = function()
					return if isCooling() then `{ability.Seconds()}s` else `${Components.Commas(ability.Cost)}`
				end,
			}),
			create("TextLabel")({
				Name = "Name",
				Position = UDim2.fromOffset(NAME.X, NAME.Y),
				Size = UDim2.new(1, -NAME.X - 6, 0, NAME_TEXT),
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				FontFace = Font.Display,
				TextScaled = true,
				TextColor3 = Palette.White,
				ZIndex = 4,
				Text = string.upper(ability.Name),
				create("UITextSizeConstraint")({ MaxTextSize = NAME_TEXT }),
			}),
			-- The cooldown, behind the model and over the rest of the picture's ground, not the name band: full as the
			-- ability is used, draining off the top.
			create("Frame")({
				Name = "Shade",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 0, 1, -BAND),
				BackgroundColor3 = Palette.Ink,
				BackgroundTransparency = SHADE,
				BorderSizePixel = 0,
				ZIndex = 2,
				Visible = isCooling,
				Size = function()
					return UDim2.new(1, 0, 0, math.round((CARD - BAND) * ability.Cooling()))
				end,
			}),
			Components.KeyBadge(ability.Key, KEY_SIZE, {
				Position = UDim2.fromOffset(KEY.X, KEY.Y),
				ZIndex = 5,
			}),
			Components.Sheen(Hand.Sheen(hand, ready), 4),
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 5,
				BackgroundTransparency = function()
					local pop = 1 - ready()
					return 1 - math.max(0.6 * used(), 0.45 * pop * pop, hand.Wash())
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
			}),
		}),
	}) :: TextButton
end

-- His ULT card and the charge bar beside it, for the class's ultimate. Steel while the meter fills (the bar climbing
-- with every kill, the tag counting the percent); gold, breathing and reading READY once it is full; a flash as it is
-- used, and the bar then drains with what is left of it. A press it refuses knocks the card sideways.
local function ultimate(state: Types.THudState, actions: Types.TActions, top: number): { Frame }
	local ult = state.Ultimate
	local hand = Hand.React("Take", ult.IsReady)

	local isLit = function(): boolean
		return ult.IsReady() or ult.Burning() > 0
	end

	local breath = function(): number
		if not ult.IsReady() then return 0 end
		return 0.5 + 0.5 * math.sin(state.Now() * math.pi * 2 * PLACING_HZ)
	end

	local used = function(): number
		local k = Motion.Fade(state.Now(), ult.UsedAt(), PLACED_SECONDS)
		return k * k
	end

	-- The moment the meter fills: 0 to 1 over the gesture, 1 at rest.
	local charged = function(): number
		return Motion.Progress(state.Now(), ult.ChargedAt(), CHARGED_SECONDS)
	end

	local jolt = function(): number
		local t = Motion.Progress(state.Now(), ult.DeniedAt(), JOLT_SECONDS)
		if t >= 1 then return 0 end
		return JOLT * math.sin(t * math.pi * 2) * (1 - t)
	end

	local fill = function(): number
		local burning = ult.Burning()
		return if burning > 0 then burning else ult.Charge()
	end

	local card = Components.Button({
		Name = "Ultimate",
		Position = UDim2.new(1, -RIGHT, 0, top),
		Size = UDim2.fromOffset(CARD, CARD),
		BackgroundTransparency = 1,
		Activated = function()
			hand.Commit()
			actions.CastAbility(ult.Slot)
		end,
		hand.Events,
		Components.Card({
			Accent = function()
				return if isLit() then Palette.Gold else Palette.Steel
			end,
			Band = BAND,
			Brackets = function()
				return Gesture.BRACKETS + Gesture.BRACKETS_OPEN * hand.Rise()
			end,
			BracketTransparency = function()
				return 0.65 - 0.35 * hand.Light()
			end,
			GlowTransparency = function()
				if not isLit() then return 0.9 end
				return 0.7 - math.max(0.35 * breath(), 0.5 * used(), 0.5 * (1 - charged()), 0.4 * hand.Light())
			end,
		}, {
			Name = "Card",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			Position = function()
				return UDim2.new(0.5, math.round(jolt()), 0.5, 0)
			end,
			create("UIScale")({
				Scale = function()
					local pop = 1 - charged()
					return hand.Scale() + 0.1 * used() + 0.14 * pop * pop
				end,
			}),
			modelPicture(ult.Kind, {
				Transparency = function()
					return if isLit() then 0 else 0.2
				end,
				Rotation = function()
					return Gesture.BREATH_SPIN * (2 * breath() - 1) * (if ult.IsReady() then 1 else 0)
						+ Gesture.READY_SPIN * Motion.Swing(charged())
						+ Gesture.USED_SPIN
							* Motion.Swing(Motion.Progress(state.Now(), ult.UsedAt(), CHARGED_SECONDS))
				end,
				Scale = function()
					local pop = 1 - charged()
					return 1
						+ Gesture.HOVER * hand.Rise()
						+ Gesture.BREATH * breath()
						+ Gesture.USED_POP * used()
						+ Gesture.READY_POP * pop * pop
				end,
			}),
			create("TextLabel")({
				Name = "State",
				Position = UDim2.fromOffset(PRICE.X, PRICE.Y),
				Size = UDim2.new(1, -PRICE.X, 0, PRICE_TEXT),
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				FontFace = Font.Display,
				TextSize = PRICE_TEXT,
				ZIndex = 3,
				TextColor3 = function()
					return if isLit() then Palette.Gold else Palette.Lavender
				end,
				Text = function()
					return if ult.IsReady() then "READY" else "ULT"
				end,
			}),
			create("TextLabel")({
				Name = "Name",
				Position = UDim2.fromOffset(NAME.X, NAME.Y),
				Size = UDim2.new(1, -NAME.X - 6, 0, NAME_TEXT),
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				FontFace = Font.Display,
				TextScaled = true,
				TextColor3 = Palette.White,
				ZIndex = 3,
				Text = string.upper(ult.Name),
				create("UITextSizeConstraint")({ MaxTextSize = NAME_TEXT }),
			}),
			Components.KeyBadge(ult.Key, KEY_SIZE, {
				Position = UDim2.fromOffset(KEY.X, KEY.Y),
				ZIndex = 3,
			}),
			Components.Sheen(Hand.Sheen(hand, charged), 4),
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 4,
				BackgroundTransparency = function()
					local pop = 1 - charged()
					return 1 - math.max(0.6 * used(), 0.5 * pop * pop, hand.Wash())
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
			}),
		}),
	})

	local charge = create("Frame")({
		Name = "Charge",
		Position = UDim2.new(1, -CHARGE_RIGHT, 0, top),
		Size = UDim2.fromOffset(CHARGE_TAG.X, CHARGE_BAR.Y + CHARGE_BAR_SIZE.Y),
		BackgroundTransparency = 1,
		create("Frame")({
			Name = "Bar",
			Position = UDim2.fromOffset(CHARGE_BAR.X, CHARGE_BAR.Y),
			Size = UDim2.fromOffset(CHARGE_BAR_SIZE.X, CHARGE_BAR_SIZE.Y),
			BackgroundColor3 = CHARGE_EDGE,
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			create("Frame")({
				Position = UDim2.fromOffset(2, 2),
				Size = UDim2.new(1, -4, 1, -4),
				BackgroundColor3 = Palette.Ink,
				BackgroundTransparency = 0.15,
				BorderSizePixel = 0,
				create("Frame")({
					Name = "Fill",
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.fromScale(0, 1),
					BorderSizePixel = 0,
					Size = function()
						return UDim2.fromScale(1, fill())
					end,
					BackgroundColor3 = function()
						return Palette.Gold:Lerp(Palette.White, math.max(0.5 * breath(), 1 - charged()))
					end,
				}),
			}),
		}),
		create("Frame")({
			Name = "Tag",
			Size = UDim2.fromOffset(CHARGE_TAG.X, CHARGE_TAG.Y),
			BackgroundColor3 = Palette.Gold,
			BorderSizePixel = 0,
			ZIndex = 2,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			create("TextLabel")({
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				FontFace = Font.Display,
				TextSize = CHARGE_TEXT,
				TextColor3 = Palette.Ink,
				Text = function()
					return tostring(math.floor(ult.Charge() * 100))
				end,
			}),
		}),
	})

	return { card, charge }
end

function Shop.Abilities(state: Types.THudState, actions: Types.TActions): Frame
	local cards = table.create(#state.Abilities)
	for index in state.Abilities do
		cards[index] = abilityCard(state, actions, index)
	end

	return create("Frame")({
		Name = "Abilities",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = function()
			return state.Phase() ~= "Ended"
		end,
		create("TextLabel")({
			Name = "Title",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -TITLE_RIGHT, 0, TITLE_TOP),
			Size = UDim2.fromOffset(CARD, TITLE_TEXT),
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextYAlignment = Enum.TextYAlignment.Top,
			FontFace = Font.Display,
			TextSize = TITLE_TEXT,
			TextColor3 = Palette.Lavender,
			Text = "ABILITIES",
		}),
		cards,
		ultimate(state, actions, TOP + STEP * #state.Abilities),
	})
end

return Shop
