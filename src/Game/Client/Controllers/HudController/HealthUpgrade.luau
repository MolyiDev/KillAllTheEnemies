--!nonstrict
-- The show of a bought HEALTH level, over the rest of the HUD: the first-aid kit leaves its card (Upgrades), is
-- thrown out and pulled into the health bar, the bar takes the hit and its new cells (HealthBar), the gain is
-- stamped over it and the price comes off the money plate. Every piece runs off state.Vital.BoughtAt and Timing, so
-- the card, the bar and these stay in step.
-- The kit is a model at ReplicatedStorage.Models.Upgrades.Health (Rojo's, made by Assets/models/Upgrades); with
-- none there the card and the flight draw no picture.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local healthUpgrades = require(ReplicatedStorage.Shared.Utils.healthUpgrades)
local GunPicture = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.GunPicture)
local Hotbar = require(script.Parent.Hotbar)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font

local HealthUpgrade = {}

-- Seconds from the server's word (state.Vital.BoughtAt) unless named otherwise.
HealthUpgrade.Timing = table.freeze({
	-- The card punches and flashes.
	PUNCH = 0.42,
	-- The bought kit is thrown out of the card against drag until THROW, hangs, then is pulled into the health bar,
	-- accelerating, and lands at LAND. The body's halo (Client/Utils/healthUpFx, CROWN_AT) and the cue's second hit
	-- are on the same beat: move one and move them all.
	THROW = 0.16,
	LAND = 0.5,
	-- From the landing the bar is struck (HealthBar) and its cells narrow to fit the new ones over this long.
	GROW = 0.34,
	-- The next level deals up into the card, and its price counts up from nothing.
	DEAL_AT = 0.3,
	DEAL = 0.3,
	ROLL_AT = 0.36,
	ROLL = 0.36,
	-- The gain stamped over the bar: in from the landing, held, lifted away.
	PLUS_IN = 0.16,
	PLUS_LEAVE_AT = 1.55,
	PLUS_OUT = 0.3,
	SPEND = 0.95,
	-- Everything above is over by this.
	TOTAL = 1.9,
	-- From their own stamps: the card dips on an ask, a light sweeps it as it becomes affordable, a refusal jolts it.
	PRESS = 0.14,
	READY = 0.6,
	JOLT = 0.16,
	DENIED = 0.5,
})
local Timing = HealthUpgrade.Timing

-- How the kit is looked at: the camera's turn round it from its front and its height over it (deg).
local VIEW_YAW = 30
local VIEW_PITCH = 22
-- The flight, in design px: the hang point off the card's picture, the pull's control point over the bar (so the
-- kit comes down onto it), its size at the hang and as it lands, and the turn it picks up on the way.
local THROW_OFFSET = UDim2.fromOffset(120, -70)
local PULL_RISE = 150
local THROW_SCALE = 1.45
local LAND_SCALE = 0.3
local FLIGHT_TURN = 24
-- The gain over the bar: how far over its middle it sits, its text, how big it arrives and how far it lifts away.
local PLUS_OVER = 30
local PLUS_TEXT = 40
local PLUS_FROM_SCALE = 1.9
local PLUS_RISE = 26

local picture: GunPicture.TPicture | false | nil = nil

-- The picture of the first-aid kit, or nil when the place has no model for it.
function HealthUpgrade.Picture(): GunPicture.TPicture?
	if picture ~= nil then return picture or nil end

	local models = ReplicatedStorage:FindFirstChild("Models")
	local folder = if models then models:FindFirstChild("Upgrades") else nil
	local model = if folder then folder:FindFirstChild("Health") else nil
	local found: GunPicture.TPicture | false = false
	if model and model:IsA("Model") then found = GunPicture.FromModel(model, VIEW_YAW, VIEW_PITCH) end
	picture = found
	return found or nil
end

-- Where the bought kit is on its flight `t` seconds in: false and 0 to 1 through the throw, or true and 0 to 1
-- through the pull.
local function stage(t: number): (boolean, number)
	if t < Timing.THROW then return false, Motion.Decelerate(t / Timing.THROW) end
	local u = math.clamp((t - Timing.THROW) / (Timing.LAND - Timing.THROW), 0, 1)
	return true, u * u
end

-- The bought kit, from the card's picture to the health bar. `from` is the card picture's centre, `size` its side.
local function flight(state: Types.THudState, since: () -> number, from: UDim2, size: number): Frame
	local hang = from + THROW_OFFSET

	return GunPicture.Build(HealthUpgrade.Picture, {
		Ambient = GunPicture.FLAT_AMBIENT,
		Light = GunPicture.FLAT_LIGHT,
		Rotation = function()
			local isPull, k = stage(since())
			return if isPull then Motion.Lerp(-FLIGHT_TURN, FLIGHT_TURN, k) else -FLIGHT_TURN * k
		end,
	}, {
		Name = "Flight",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		ZIndex = 3,
		Visible = function()
			local t = since()
			return t >= 0 and t < Timing.LAND
		end,
		Position = function()
			local isPull, k = stage(since())
			if not isPull then return from:Lerp(hang, k) end
			-- The bar moves with the camera, so the pull is aimed at where it is now.
			local finish = state.Vital.BarAt()
			local pull = finish - UDim2.fromOffset(0, PULL_RISE)
			return hang:Lerp(pull, k):Lerp(pull:Lerp(finish, k), k)
		end,
		create("UIScale")({
			Scale = function()
				local isPull, k = stage(since())
				return if isPull then Motion.Lerp(THROW_SCALE, LAND_SCALE, k) else Motion.Lerp(1, THROW_SCALE, k)
			end,
		}),
	})
end

-- The gain, stamped over the bar as the kit lands: big and white on its first frame, down to size and green, held,
-- lifted away.
local function plus(state: Types.THudState, since: () -> number): TextLabel
	local arrive = function(): number
		return Motion.Progress(since(), 0, Timing.PLUS_IN, Timing.LAND)
	end

	local leave = function(): number
		return Motion.Progress(since(), 0, Timing.PLUS_OUT, Timing.PLUS_LEAVE_AT)
	end

	return create("TextLabel")({
		Name = "Gain",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(260, PLUS_TEXT),
		BackgroundTransparency = 1,
		FontFace = Font.Display,
		TextSize = PLUS_TEXT,
		Text = `+{healthUpgrades.GAIN} HEALTH`,
		ZIndex = 4,
		Visible = function()
			local t = since()
			return t >= Timing.LAND and leave() < 1
		end,
		Position = function()
			local rise = PLUS_OVER + PLUS_RISE * Motion.Accelerate(leave())
			return state.Vital.BarAt() - UDim2.fromOffset(0, math.round(rise))
		end,
		TextColor3 = function()
			return Palette.White:Lerp(Palette.Green, Motion.Out(arrive()))
		end,
		TextTransparency = function()
			return Motion.Accelerate(leave())
		end,
		Components.Ink(PLUS_TEXT),
		create("UIScale")({
			Scale = function()
				return Motion.Lerp(PLUS_FROM_SCALE, 1, Motion.Decelerate(arrive()))
			end,
		}),
	})
end

-- The overlay. `from` is the HEALTH card picture's centre and `size` its side (Upgrades).
function HealthUpgrade.Build(state: Types.THudState, from: UDim2, size: number): Frame
	local vital = state.Vital
	-- Seconds since the last buy, held at the show's length once it is over. Derived, so nothing here is worked out
	-- again on the frames the clock runs for the card alone (a press, a refusal).
	local since = derive(function(): number
		return math.min(vital.Clock() - vital.BoughtAt(), Timing.TOTAL)
	end)

	return create("Frame")({
		Name = "HealthUpgrade",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Visible = function()
			return state.Phase() ~= "Ended"
		end,
		Hotbar.Spend(since, vital.Paid, Timing.SPEND),
		flight(state, since, from, size),
		plus(state, since),
	})
end

return HealthUpgrade
