--!nonstrict
-- The Gems a purchase or a level is paid with, flying out of the HUD's Gems pill into what they buy: the gun on the
-- stage, or the star the level lights. Each is thrown out of the pill, hangs, and is pulled in on its own bend
-- (UI.md 5j); they land one after another, each with a tick, and the moment they buy starts on the last.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local LoadoutCore = require(ReplicatedStorage.GlobalShared.Core.LoadoutCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local Info = require(script.Parent.Info)
local Stage = require(script.Parent.Stage)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local Progress = Motion.Progress

local Tune = table.freeze({
	COUNT = 8,
	-- Each sets off this long after the one before it and flies this long.
	STAGGER = 0.03,
	FLIGHT = 0.45,
	-- The throw: how far out of the pill, in px, and the fan it is thrown across (degrees from straight down-left).
	THROW_MIN = 60,
	THROW_MAX = 120,
	FAN = 70,
	-- The bend of the pull home, as a share of the trip, to one side or the other.
	BEND_MIN = 0.2,
	BEND_MAX = 0.45,
	-- How much of the pace is kept from the throw (the rest is the pull, accelerating into the target).
	LINEAR = 0.35,
	GEM = 26,
	-- In and out of sight over these shares of a flight, never a blink.
	FADE_IN = 0.12,
	FADE_OUT = 0.15,
})

-- The gem on the HUD's Gems counter, docked at the right of his currency while this page is up, in his 1920 x 1080
-- (LobbyController's Hud: the counter's + ending 920 right of the middle, the counter 308 wide, the glyph 55 into
-- it; its middle 52 + 33 down).
local FROM = Vector2.new(960 + 920 - 308 + 55, 85)
local GEM_BLUE = Theme.Color.Gem

local Flight = {}

-- How long from the Gems setting off to the last landing: the moment a purchase is shown.
Flight.SECONDS = (Tune.COUNT - 1) * Tune.STAGGER + Tune.FLIGHT

-- The same throw for the same piece every time, so a purchase reads the same twice.
local function scatter(index: number, salt: number): number
	local x = math.sin(index * 12.9898 + salt * 78.233) * 43758.5453
	return x - math.floor(x)
end

local function bezier(a: Vector2, b: Vector2, c: Vector2, d: Vector2, t: number): Vector2
	local u = 1 - t
	return a * (u * u * u) + b * (3 * u * u * t) + c * (3 * u * t * t) + d * (t * t * t)
end

function Flight.Build(state: Types.TWeaponsState): { Instance }
	local target = derive(function(): Vector2
		if state.PaidFor() == "Buy" then return Stage.GUN_AT end
		local level = (state.Levels()[state.UpgradedGun()] or 1)
		-- Before the Sync is let through the level shown is the old one: the star lit is the next.
		local star = if state.Now() < state.UpgradedAt() then level + 1 else level
		return Info.StarAt(math.min(star, LoadoutCore.MAX_LEVEL))
	end)

	-- How many have landed, for a tick each and the reveal's sound on the last.
	local landed = derive(function(): number
		local since = state.Now() - state.PaidAt() - Tune.FLIGHT
		if since < 0 then return 0 end
		return math.min(Tune.COUNT, math.floor(since / Tune.STAGGER) + 1)
	end)
	local lastLanded = 0
	vide.effect(function()
		local count = landed()
		vide.untrack(function()
			if count > lastLanded then
				SoundsCore.PlayUINamed("UI.UpgradePick", "Tick")
				if count == Tune.COUNT and state.PaidFor() == "Buy" then
					SoundsCore.PlayUINamed("UI.UpgradePick", "RevealLegendary")
				elseif count == Tune.COUNT then
					SoundsCore.PlayUINamed("UI", "WeaponUpgrade")
				end
			end
			lastLanded = count
		end)
	end)

	local pieces = table.create(Tune.COUNT)
	for index = 1, Tune.COUNT do
		local angle = math.rad(180 + 45 + (scatter(index, 1) - 0.5) * Tune.FAN)
		local throw = Vector2.new(math.cos(angle), -math.sin(angle))
			* (Tune.THROW_MIN + (Tune.THROW_MAX - Tune.THROW_MIN) * scatter(index, 2))
		local bend = (Tune.BEND_MIN + (Tune.BEND_MAX - Tune.BEND_MIN) * scatter(index, 3))
			* (if index % 2 == 0 then 1 else -1)
		local t = derive(function(): number
			return Progress(state.Now(), state.PaidAt(), Tune.FLIGHT, Tune.STAGGER * (index - 1))
		end)

		pieces[index] = Components.Icon("Gem", {
			Name = `Gem{index}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				local progress = t()
				local to = target()
				local trip = to - FROM
				local side = Vector2.new(-trip.Y, trip.X) * bend
				local along = Tune.LINEAR * progress + (1 - Tune.LINEAR) * progress * progress
				local at = bezier(FROM, FROM + throw, to + side - trip * 0.15, to, along)
				return UDim2.fromOffset(at.X, at.Y)
			end,
			Size = Components.GlyphBox(Tune.GEM),
			ImageColor3 = GEM_BLUE,
			ImageTransparency = function()
				local progress = t()
				local appear = math.clamp(progress / Tune.FADE_IN, 0, 1)
				local vanish = math.clamp((1 - progress) / Tune.FADE_OUT, 0, 1)
				return 1 - math.min(appear, vanish)
			end,
			Visible = function()
				local progress = t()
				return progress > 0 and progress < 1
			end,
			ZIndex = 20,
			create("UIScale")({
				Scale = function()
					return 1 - 0.45 * t()
				end,
			}),
		})
	end

	return pieces
end

return Flight
