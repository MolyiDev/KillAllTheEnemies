-- The Gems a level is paid with, flying out of the HUD's Gems counter into the star it lights (GemFlight). This page
-- is laid on the whole screen, whose width follows the viewport, so both ends are read off the counter's glyph and the
-- star themselves as the Gems set off. Each landing ticks, and the last sounds the level.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local GemFlight = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.GemFlight)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local Types = require(script.Parent.Parent.Types)

local create = vide.create
local derive = vide.derive

export type TEnds = {
	-- Where the Gems set off from and land, in screen px (AbsolutePosition), nil when it is not on screen.
	From: () -> Vector2?,
	To: () -> Vector2?,
}

local Flight = {}

-- How long from the Gems setting off to the last landing: the moment the level is shown.
Flight.SECONDS = GemFlight.SECONDS

local function onLanded(isLast: boolean)
	SoundsCore.PlayUINamed("UI.UpgradePick", "Tick")
	if isLast then SoundsCore.PlayUINamed("UI", "WeaponUpgrade") end
end

-- A layer over the whole panel it is put in, holding the Gems.
function Flight.Build(state: Types.TLobbyState, ends: TEnds): Frame
	local layer: Frame? = nil
	local isFlying = derive(function(): boolean
		local now = state.Now()
		local paidAt = state.UpgradePaidAt()
		return now >= paidAt and now < paidAt + Flight.SECONDS
	end)
	-- Both ends in the layer's px, taken once as the Gems set off: the counter and the star stand still meanwhile.
	local trip = derive(function(): { From: Vector2, To: Vector2 }
		isFlying()
		return vide.untrack(function()
			local from, to = ends.From(), ends.To()
			if not layer or not from or not to then return { From = Vector2.zero, To = Vector2.zero } end
			local origin = layer.AbsolutePosition
			local scale = state.Scale()
			return { From = (from - origin) / scale, To = (to - origin) / scale }
		end)
	end)

	layer = create("Frame")({
		Name = "Flight",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 20,
		GemFlight.Build({
			Now = state.Now,
			PaidAt = state.UpgradePaidAt,
			From = function(): Vector2
				return trip().From
			end,
			To = function(): Vector2
				return trip().To
			end,
			OnLanded = onLanded,
		}),
	})
	return layer :: Frame
end

return Flight
