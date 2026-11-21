--!nonstrict
-- The show of a bought weapon upgrade, over the rest of the HUD: the gun leaves the weapon card (Upgrades), arcs down
-- into its hotbar slot (Hotbar lands it), its name is stamped mid-screen with the ladder's steps, and the price
-- comes off the money plate. Every piece runs off state.Weapon.BoughtAt and Timing, so the card, the slot and these
-- stay in step.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local GunsCore = require(ReplicatedStorage.GlobalShared.Core.GunsCore)
local GunPicture = require(script.Parent.GunPicture)
local Hotbar = require(script.Parent.Hotbar)
local Motion = require(script.Parent.Motion)
local Types = require(script.Parent.Types)

local create = vide.create
local Palette = Theme.Palette
local Font = Theme.Font
local LADDER = GunsCore.LADDER

local WeaponUpgrade = {}

-- Seconds from the server's word (state.Weapon.BoughtAt) unless named otherwise.
WeaponUpgrade.Timing = table.freeze({
	-- The card punches and flashes.
	PUNCH = 0.42,
	-- The bought gun is thrown out of the card against drag until THROW, hangs, then is pulled into its slot,
	-- accelerating, and lands at FLIGHT. The upgrade sound's landing hit is part of its file at 0.66 s: moving FLIGHT
	-- means rebuilding it (Assets/sounds/Review/Upgrade/make_round1.py, LAND_MS).
	THROW = 0.18,
	FLIGHT = 0.66,
	-- The next offer deals up into the card, and its price counts up from nothing.
	DEAL_AT = 0.34,
	DEAL = 0.3,
	ROLL_AT = 0.4,
	ROLL = 0.36,
	-- The banner comes in, its new step lights, and it leaves.
	BANNER_AT = 0.04,
	BANNER_IN = 0.2,
	PIP_AT = 0.3,
	PIP = 0.4,
	BANNER_LEAVE_AT = 1.22,
	BANNER_OUT = 0.28,
	SPEND = 0.95,
	-- Everything above is over by this.
	TOTAL = 1.5,
	-- From their own stamps: the card dips on an ask, a light sweeps it as it becomes affordable, a refusal jolts it.
	PRESS = 0.14,
	READY = 0.6,
	JOLT = 0.16,
	DENIED = 0.5,
})
local Timing = WeaponUpgrade.Timing

-- The flight, in design px: the hang point off the card's picture, and the pull's control point past it along the
-- throw, so the gun keeps going the way it was thrown before it turns down into the slot.
local THROW_OFFSET = UDim2.fromOffset(110, -80)
local PULL_OFFSET = UDim2.fromOffset(170, -10)
local THROW_SCALE = 1.5
local THROW_TURN = 8
-- The banner's centre (design px from the top), the panel and the room round it for its glow (a CanvasGroup clips).
local BANNER_Y = 700
local BANNER = Vector2.new(480, 124)
local BANNER_ROOM = 48
local BANNER_FROM_SCALE = 1.14
local BANNER_LEAVE_RISE = 14
local CAPTION_TEXT = 20
local NAME_TEXT = 58
local PIP = 14
local PIP_GAP = 8
local SPEND_TEXT = 34
local SPEND_RISE = 40

-- Seconds since the last buy (huge at rest).
local function since(state: Types.THudState): number
	return state.Weapon.Clock() - state.Weapon.BoughtAt()
end

-- Where the bought gun is on its flight `t` seconds in: false and 0 to 1 through the throw, or true and 0 to 1 through
-- the pull.
local function stage(t: number): (boolean, number)
	if t < Timing.THROW then return false, Motion.Decelerate(t / Timing.THROW) end
	local u = math.clamp((t - Timing.THROW) / (Timing.FLIGHT - Timing.THROW), 0, 1)
	return true, u * u
end

-- The bought gun, from the card's picture to the gun's slot. `from` is the card picture's centre, `size` its side and
-- `tilt` its rotation.
local function flight(state: Types.THudState, from: UDim2, size: number, tilt: number): ViewportFrame
	local hang = from + THROW_OFFSET
	local pull = hang + PULL_OFFSET
	local finish = Hotbar.GUN_SLOT
	local landScale = Hotbar.GUN_PICTURE / size

	return GunPicture.Build(function()
		local held = state.Weapon.Held()
		return if held then GunPicture.FromGun(held.Gun) else nil
	end, {
		Name = "Flight",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		ZIndex = 3,
		Visible = function()
			local t = since(state)
			return t >= 0 and t < Timing.FLIGHT
		end,
		Position = function()
			local isPull, k = stage(since(state))
			if not isPull then return from:Lerp(hang, k) end
			return hang:Lerp(pull, k):Lerp(pull:Lerp(finish, k), k)
		end,
		Rotation = function()
			local isPull, k = stage(since(state))
			return if isPull then Motion.Lerp(THROW_TURN, 0, k) else Motion.Lerp(tilt, THROW_TURN, k)
		end,
		create("UIScale")({
			Scale = function()
				local isPull, k = stage(since(state))
				return if isPull then Motion.Lerp(THROW_SCALE, landScale, k) else Motion.Lerp(1, THROW_SCALE, k)
			end,
		}),
	})
end

local function pips(state: Types.THudState): Frame
	local children = table.create(#LADDER)
	for index in LADDER do
		-- The step just bought lights last, popping white.
		local isLit = function(): boolean
			local step = state.Weapon.Step()
			return index < step or (index == step and since(state) >= Timing.PIP_AT)
		end

		local pop = function(): number
			if index ~= state.Weapon.Step() or not isLit() then return 0 end
			local k = Motion.Fade(since(state), Timing.PIP_AT, Timing.PIP)
			return k * k
		end

		children[index] = create("Frame")({
			Name = `Step{index}`,
			Size = UDim2.fromOffset(PIP, PIP),
			LayoutOrder = index,
			BorderSizePixel = 0,
			BackgroundColor3 = function()
				return if isLit() then Palette.Green:Lerp(Palette.White, pop()) else Palette.Ink
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			create("UIStroke")({
				Color = Palette.Lavender,
				Transparency = 0.5,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
			create("UIScale")({
				Scale = function()
					return 1 + 0.8 * pop()
				end,
			}),
		})
	end

	return create("Frame")({
		Name = "Steps",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(#LADDER * (PIP + PIP_GAP), PIP),
		BackgroundTransparency = 1,
		ZIndex = 3,
		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, PIP_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		children,
	})
end

-- The bought gun's name stamped below the crosshair: arrives decelerating from a little big, holds, rises away.
local function banner(state: Types.THudState): CanvasGroup
	local appear = function(): number
		return Motion.Progress(since(state), 0, Timing.BANNER_IN, Timing.BANNER_AT)
	end

	local leave = function(): number
		return Motion.Progress(since(state), 0, Timing.BANNER_OUT, Timing.BANNER_LEAVE_AT)
	end

	local room = BANNER + Vector2.one * 2 * BANNER_ROOM
	return create("CanvasGroup")({
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(room.X, room.Y),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Visible = function()
			return appear() > 0 and leave() < 1
		end,
		Position = function()
			return UDim2.new(0.5, 0, 0, BANNER_Y - math.round(BANNER_LEAVE_RISE * Motion.Accelerate(leave())))
		end,
		GroupTransparency = function()
			return 1 - Motion.Decelerate(appear()) * (1 - Motion.Accelerate(leave()))
		end,
		create("UIScale")({
			Scale = function()
				return Motion.Lerp(BANNER_FROM_SCALE, 1, Motion.Decelerate(appear()))
			end,
		}),
		Components.Panel({ Glow = Palette.Green, GlowTransparency = 0.45, Brackets = 8 }, {
			Name = "Plate",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(BANNER.X, BANNER.Y),
			create("TextLabel")({
				Name = "Caption",
				Position = UDim2.fromOffset(0, 12),
				Size = UDim2.new(1, 0, 0, CAPTION_TEXT),
				BackgroundTransparency = 1,
				FontFace = Font.Display,
				TextSize = CAPTION_TEXT,
				TextColor3 = Palette.Lavender,
				Text = "WEAPON UPGRADE",
				ZIndex = 3,
			}),
			create("TextLabel")({
				Name = "Gun",
				Position = UDim2.fromOffset(0, 34),
				Size = UDim2.new(1, 0, 0, NAME_TEXT),
				BackgroundTransparency = 1,
				FontFace = Font.Display,
				TextSize = NAME_TEXT,
				TextColor3 = Palette.White,
				ZIndex = 3,
				Text = function()
					local held = state.Weapon.Held()
					return if held then held.Label else ""
				end,
			}),
			pips(state),
		}),
	})
end

-- The price leaving the money plate as the counter drops by it.
local function spend(state: Types.THudState): TextLabel
	local progress = function(): number
		return Motion.Progress(since(state), 0, Timing.SPEND)
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
			local t = since(state)
			return t >= 0 and t < Timing.SPEND
		end,
		Position = function()
			return Hotbar.MONEY_TOP + UDim2.fromOffset(0, -math.round(SPEND_RISE * Motion.Decelerate(progress())))
		end,
		TextTransparency = function()
			return Motion.Accelerate(math.clamp(progress() * 2 - 1, 0, 1))
		end,
		Text = function()
			local held = state.Weapon.Held()
			return if held then `-${Components.Commas(held.Price)}` else ""
		end,
		create("UIScale")({
			Scale = function()
				local k = 1 - math.clamp(progress() * 4, 0, 1)
				return 1 + 0.3 * k * k
			end,
		}),
	})
end

-- The overlay. `from` is the weapon card picture's centre, `size` its side and `tilt` its rotation (Upgrades).
function WeaponUpgrade.Build(state: Types.THudState, from: UDim2, size: number, tilt: number): Frame
	return create("Frame")({
		Name = "WeaponUpgrade",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		-- Over the hotbar, which the gun flies into.
		ZIndex = 5,
		Visible = function()
			return state.Phase() ~= "Ended"
		end,
		banner(state),
		spend(state),
		flight(state, from, size, tilt),
	})
end

return WeaponUpgrade
