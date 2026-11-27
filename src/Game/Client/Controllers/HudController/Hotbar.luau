--!nonstrict
-- The bottom centre (UIMatt.md, Round Money and Hotbar): the run's Gold on a gold coin square and a plate, and under
-- it the slots that hold something, centred. An empty slot is not drawn, and the gun is all that is carried so far,
-- so its slot stands alone in the middle.
-- In first person, where the overhead bar cannot be seen, a health bar shows above the Gold instead.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local CoinFlight = require(script.Parent.Parent.Parent.Utils.coinFlight)
local GunPicture = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.GunPicture)
local HealthBar = require(script.Parent.HealthBar)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font

-- His drawn rects at 1080, x from the screen's centre: the gold coin square and the money plate ending 136 above the
-- bottom, the coins glyph and the amount; a slot 96 square ending 24 above the bottom, its key in the corner, and the
-- white frame round the slot in hand.
local Layout = table.freeze({
	MONEY_BOTTOM = 136,
	MONEY_HEIGHT = 84,
	COIN_LEFT = -137,
	COIN_GLYPH = 51,
	PLATE_LEFT = -53,
	PLATE_WIDTH = 190,
	MONEY_TEXT = 53,
	SLOT = 96,
	SLOTS_BOTTOM = 24,
	KEY = 4,
	KEY_SIZE = 24,
	HELD_OUTSET = 4,
	-- The gun's picture, as a share of its slot, and its lean (deg, as a Rotation): laid from the bottom left to the
	-- top right, the slot's longest line, so a long gun is drawn bigger than it could be lying flat.
	GUN_SHARE = 0.95,
	GUN_TILT = -30,
	-- The overhead bar's shape (HealthBar), drawn bigger, at one length whatever the max health, and this far over
	-- the money block.
	HEALTH_WIDTH = 300,
	HEALTH_HEIGHT = 30,
	HEALTH_GAP = 14,
})
local SWAP_SECONDS = 0.35
-- A bought upgrade landing in the gun's slot hits harder than a plain swap, and for longer.
local LAND_SECONDS = 0.5
local LAND_PUNCH = 0.2
local LAND_FLASH = 0.8
-- The slot coming in as the gun is first held and leaving when it is not: a loose spring, whose overshoot is the
-- punch.
local Arrive = table.freeze({
	PERIOD = 0.39,
	DAMPING = 0.52,
	-- It starts this far below its line (design px) and this far turned (deg), at no size.
	RISE = 26,
	SPIN = -40,
	-- Under this much of its size the slot is not drawn.
	GONE = 0.02,
})
-- What a gun arriving does to its picture and its slot. The picture grows (its shadow falls further with it) and
-- swings in its own plane, a damped swing that dies inside the gesture; the slot is knocked down the way the bought
-- gun came in and comes back, a light crosses its face, and its white frame throws a copy of itself outward.
local Knock = table.freeze({
	SWAP_POP = 0.14,
	SWAP_SPIN = 9,
	LAND_POP = 0.3,
	LAND_SPIN = 16,
	LAND_DIP = 9,
	SHEEN_SECONDS = 0.45,
	ECHO_SECONDS = 0.4,
	ECHO_REACH = 22,
	ECHO_TRANSPARENCY = 0.25,
})
-- A bought Gold pack (state.GoldPack), seconds from its arrival: its amount is stamped over the money block, born
-- white and a little large, holds while the pack's coins land (CoinsController), then drops into the plate as the last
-- one does (CoinFlight.Shower.LAST), and the block strikes: a white face, one ring thrown off it, a light across it.
local Pack = table.freeze({
	-- The stamp's centre over the money block's top (clear of the first-person health bar), its text, how large it
	-- is born and how long it takes to settle.
	STAMP_UP = 78,
	STAMP_TEXT = 54,
	STAMP_IN = 0.2,
	STAMP_IN_SCALE = 1.7,
	STAMP_WHITE = 0.35,
	-- It drifts up this far while it holds, then drops into the plate over DROP, shrinking to DROP_SCALE.
	HOLD_RISE = 8,
	DROP = 0.16,
	DROP_SCALE = 0.5,
	LAND = CoinFlight.Shower.LAST,
	-- The strike: the face's flash, the punch, the ring's growth (px) and the light.
	FLASH = 0.35,
	FLASH_PEAK = 0.8,
	PUNCH = 0.16,
	RING = 0.5,
	RING_GROWTH = 40,
	SHEEN = 0.55,
	SPIN = 16,
	-- Everything above is over by this.
	TOTAL = CoinFlight.Shower.LAST + 0.6,
})
local GUN_KEY = Enum.KeyCode.One
-- A price leaving the money plate (Hotbar.Spend): its text and how far it rises.
local SPEND_TEXT = 34
local SPEND_RISE = 40
local JOLT = 6
local COIN_EDGE = Color3.fromRGB(255, 221, 147)
local HELD = Color3.fromRGB(110, 74, 204)

local Hotbar = {}

-- Where the money block's top sits above the screen's bottom edge, for anything that must stay clear of it.
Hotbar.HEIGHT = Layout.MONEY_BOTTOM + Layout.MONEY_HEIGHT
-- The middle of the money plate's top edge, the gun's slot's centre and the size and lean of the gun's picture in it, for
-- what flies to them.
Hotbar.MONEY_TOP = UDim2.new(0.5, Layout.PLATE_LEFT + Layout.PLATE_WIDTH / 2, 1, -Hotbar.HEIGHT)
Hotbar.GUN_SLOT = UDim2.new(0.5, 0, 1, -Layout.SLOTS_BOTTOM - Layout.SLOT / 2)
Hotbar.GUN_PICTURE = Layout.SLOT * Layout.GUN_SHARE
Hotbar.GUN_TILT = Layout.GUN_TILT
-- How long a bought Gold pack's show runs on the money block: the HUD's clock runs that long for it.
Hotbar.GOLD_PACK_SECONDS = Pack.TOTAL
-- The middle of the first-person health bar, for what flies to it.
Hotbar.HEALTH = UDim2.new(0.5, 0, 1, -(Hotbar.HEIGHT + Layout.HEALTH_GAP + Layout.HEALTH_HEIGHT / 2))

-- A price leaving the money plate as the counter drops by it, for the show of a buy. `since` is the seconds since
-- that buy, `price` its Gold and `seconds` how long the price takes to go.
function Hotbar.Spend(since: () -> number, price: () -> number, seconds: number): TextLabel
	local progress = function(): number
		return Motion.Progress(since(), 0, seconds)
	end

	return create("TextLabel")({
		Name = "Spend",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(200, SPEND_TEXT),
		BackgroundTransparency = 1,
		FontFace = Font.Display,
		TextSize = SPEND_TEXT,
		TextColor3 = Palette.Gold,
		ZIndex = 2,
		Visible = function()
			local t = since()
			return t >= 0 and t < seconds
		end,
		Position = function()
			return Hotbar.MONEY_TOP + UDim2.fromOffset(0, -math.round(SPEND_RISE * Motion.Decelerate(progress())))
		end,
		TextTransparency = function()
			return Motion.Accelerate(math.clamp(progress() * 2 - 1, 0, 1))
		end,
		Text = function()
			return `-${Components.Commas(price())}`
		end,
		create("UIScale")({
			Scale = function()
				local k = 1 - math.clamp(progress() * 4, 0, 1)
				return 1 + 0.3 * k * k
			end,
		}),
	})
end

-- ============================== Health (first person) ==============================

local function healthBar(state: Types.THudState): Frame
	return HealthBar.Build(state, {
		Name = "Health",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = Hotbar.HEALTH,
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
		return JOLT * Motion.Shake(math.clamp((1 - state.GoldDenied()) * 3, 0, 1), state.GoldDeniedAt())
	end

	-- Seconds since a Gold pack arrived, held at TOTAL once its show is over: state.Now ticks for every coin that
	-- lands, and held, nothing below is worked out again for them.
	local packFor = derive(function(): number
		return math.min(state.Now() - state.GoldPack.At(), Pack.TOTAL)
	end)
	-- Each of the pack's gestures is derived too: it holds one value outside its own stretch of the show, so what
	-- hangs off it is written only while it moves.
	-- 1 as the pack's last coin lands, fading; 0 before it and at rest.
	local strike = derive(function(): number
		local k = Motion.Fade(packFor(), Pack.LAND, Pack.FLASH)
		return if k < 1 then k * k else 0
	end)
	-- 0 to 1 from the last coin's landing, for the ring and the glyph's swing.
	local struck = derive(function(): number
		return Motion.Progress(packFor(), Pack.LAND, Pack.RING)
	end)
	-- 0 to 1 through the stamp's drop into the plate.
	local drop = derive(function(): number
		return Motion.Accelerate(Motion.Progress(packFor(), Pack.LAND - Pack.DROP, Pack.DROP))
	end)
	-- The stamp is solid until the second half of its drop, and gone from the landing on.
	local stampTransparency = derive(function(): number
		return if packFor() >= Pack.LAND then 1 else math.clamp(drop() * 2 - 1, 0, 1)
	end)

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
					return 1 + 0.1 * pulse() + Pack.PUNCH * strike()
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
			Components.Picture(EIcons.GoldCoin, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = Components.PictureBox(Layout.COIN_GLYPH),
				ZIndex = 2,
				Rotation = function()
					return -8 * pulse() + Pack.SPIN * Motion.Swing(struck())
				end,
			}),
		}),
		Components.Panel({
			Glow = Palette.Gold,
			GlowTransparency = function()
				local lit = math.max(0.45 * pulse(), 0.7 * strike())
				return if lit > 0 then 1 - lit else 1
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
				AutoLocalize = false,
				Text = function()
					return `${Components.Commas(state.GoldShown())}`
				end,
				create("UITextSizeConstraint")({ MaxTextSize = Layout.MONEY_TEXT }),
				create("UIScale")({
					Scale = function()
						return 1 + 0.08 * pulse() + Pack.PUNCH * strike()
					end,
				}),
			}),
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 4,
				BackgroundTransparency = function()
					return 1 - Pack.FLASH_PEAK * strike()
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
					return Motion.Progress(packFor(), Pack.LAND, Pack.SHEEN)
				end, 3),
			}),
		}),
		-- One ring: the money block's outline thrown off it as the pack lands, growing by pixels and thinning out.
		create("Frame")({
			Name = "PackRing",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 1, -Layout.MONEY_BOTTOM - Layout.MONEY_HEIGHT / 2),
			BackgroundTransparency = 1,
			Size = function()
				local grown = math.round(Pack.RING_GROWTH * Motion.Out(struck()))
				return UDim2.fromOffset(
					Layout.PLATE_LEFT + Layout.PLATE_WIDTH - Layout.COIN_LEFT + grown * 2,
					Layout.MONEY_HEIGHT + grown * 2
				)
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, 5) }),
			create("UIStroke")({
				Thickness = 2,
				Color = Palette.Gold,
				Transparency = function()
					local t = struck()
					return if t > 0 then 0.1 + 0.9 * t else 1
				end,
			}),
		}),
		-- The pack's Gold, stamped over the block. Never faded in: its first frame is its white one.
		create("TextLabel")({
			Name = "PackStamp",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(420, Pack.STAMP_TEXT),
			BackgroundTransparency = 1,
			FontFace = Font.Display,
			TextSize = Pack.STAMP_TEXT,
			ZIndex = 5,
			Position = function()
				local rise = Pack.HOLD_RISE * Motion.Out(Motion.Progress(packFor(), 0, Pack.LAND - Pack.DROP))
				local fall = (Pack.STAMP_UP + Layout.MONEY_HEIGHT / 2) * drop()
				return UDim2.new(0.5, 0, 1, -Hotbar.HEIGHT - Pack.STAMP_UP + math.round(fall - rise))
			end,
			TextColor3 = function()
				return Palette.Gold:Lerp(Palette.White, Motion.Fade(packFor(), 0, Pack.STAMP_WHITE))
			end,
			TextTransparency = stampTransparency,
			AutoLocalize = false,
			Text = function()
				return `+${Components.Commas(state.GoldPack.Amount())}`
			end,
			create("UIStroke")({
				Color = Palette.Ink,
				Thickness = 3,
				LineJoinMode = Enum.LineJoinMode.Miter,
				Transparency = stampTransparency,
			}),
			create("UIScale")({
				Scale = function()
					local arriving = Motion.Lerp(
						Pack.STAMP_IN_SCALE,
						1,
						Motion.Decelerate(Motion.Progress(packFor(), 0, Pack.STAMP_IN))
					)
					return arriving * Motion.Lerp(1, Pack.DROP_SCALE, drop())
				end,
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

-- A white frame standing `outset` off the slot's edge, as he drew round the slot in hand. `props` are the frame's
-- own; `outset` and `transparency` may be sources.
local function frameRound(outset: any, transparency: any, props: { [any]: any }): Frame
	return create("Frame")({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Size = function()
			local reach = 2 * math.round(if type(outset) == "function" then outset() else outset)
			return UDim2.new(1, reach, 1, reach)
		end,
		create("UIStroke")({
			Color = Palette.White,
			Thickness = 2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Transparency = transparency,
		}),
		create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
		props,
	})
end

local function gunSlot(state: Types.THudState): Frame
	local weapon = state.Weapon

	-- The gestures' clocks, derived so that a frame which does not move them redraws nothing here: state.Now ticks
	-- for every coin that lands, and all of these hold one value at rest.
	-- 0 to 1 through a swap of the gun in hand; 1 at rest.
	local swapped = derive(function(): number
		return Motion.Progress(state.Now(), state.GunAt(), SWAP_SECONDS)
	end)
	-- Seconds since the bought gun landed: negative while it is in the air, huge at rest.
	local landedFor = derive(function(): number
		return weapon.Clock() - weapon.LandAt()
	end)
	-- The bought gun is in the air: the slot keeps its place, empty.
	local isAwaiting = derive(function(): boolean
		local now = weapon.Clock()
		return now >= weapon.BoughtAt() and now < weapon.LandAt()
	end)

	-- 0 out of the row, 1 in it, past 1 for a moment on the way in.
	local presence = Hand.Spring(function(): number
		return if state.GunModel() ~= nil or isAwaiting() then 1 else 0
	end, Arrive.PERIOD, Arrive.DAMPING)

	-- 0 to 1 over `seconds` from the landing; 0 while the gun is in the air, 1 at rest.
	local landing = function(seconds: number): number
		return math.clamp(landedFor() / seconds, 0, 1)
	end

	-- 1 as the gun is swapped or a bought one lands, fading; 0 at rest, and before the landing.
	local swap = function(): number
		local k = 1 - swapped()
		return k * k
	end

	local landed = function(): number
		local t = landing(LAND_SECONDS)
		if t <= 0 then return 0 end
		return (1 - t) * (1 - t)
	end

	-- Anchored at its centre, so it grows and is punched from the middle.
	return Components.Card({
		Accent = HELD,
		Tint = 0.45,
		Marks = true,
		GlowTransparency = function()
			return 0.7 - math.max(0.3 * swap(), 0.6 * landed())
		end,
	}, {
		Name = "GunSlot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(Layout.SLOT, Layout.SLOT),
		Visible = function()
			return presence() > Arrive.GONE
		end,
		Position = function()
			local rise = Arrive.RISE * (1 - presence())
			local dip = Knock.LAND_DIP * math.sin(landing(LAND_SECONDS) * math.pi * 2) * landed()
			return Hotbar.GUN_SLOT + UDim2.fromOffset(0, math.round(rise + dip))
		end,
		create("UIScale")({
			Scale = function()
				return math.max(presence(), 0) * (1 + 0.1 * swap() + LAND_PUNCH * landed())
			end,
		}),
		frameRound(Layout.HELD_OUTSET, 0.09, { Name = "Held" }),
		frameRound(function()
			return Layout.HELD_OUTSET + Knock.ECHO_REACH * Motion.Decelerate(landing(Knock.ECHO_SECONDS))
		end, function()
			return Motion.Lerp(Knock.ECHO_TRANSPARENCY, 1, landing(Knock.ECHO_SECONDS))
		end, {
			Name = "Echo",
			Visible = function()
				local t = landing(Knock.ECHO_SECONDS)
				return t > 0 and t < 1
			end,
		}),
		GunPicture.Build(function()
			return heldPicture(state)
		end, {
			Lean = -Layout.GUN_TILT,
			Rotation = function()
				return Arrive.SPIN * (1 - presence())
					+ Knock.SWAP_SPIN * Motion.Swing(swapped())
					+ Knock.LAND_SPIN * Motion.Swing(landing(LAND_SECONDS))
			end,
			Transparency = function()
				return if isAwaiting() then 1 else 0
			end,
		}, {
			Name = "Gun",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(Layout.GUN_SHARE, Layout.GUN_SHARE),
			ZIndex = 2,
			create("UIScale")({
				Scale = function()
					return 1 + Knock.SWAP_POP * swap() + Knock.LAND_POP * landed()
				end,
			}),
		}),
		Components.KeyBadge(GUN_KEY, Layout.KEY_SIZE, {
			Position = UDim2.fromOffset(Layout.KEY, Layout.KEY),
			ZIndex = 3,
		}),
		Components.Sheen(function()
			local land = landing(Knock.SHEEN_SECONDS)
			return if land < 1 then land else swapped()
		end, 4),
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
	return create("Frame")({
		Name = "Hotbar",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = function()
			return state.Phase() ~= "Ended"
		end,
		money(state),
		gunSlot(state),
		healthBar(state),
	})
end

return Hotbar
