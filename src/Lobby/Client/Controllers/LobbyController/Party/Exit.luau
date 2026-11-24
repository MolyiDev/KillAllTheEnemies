--!nonstrict
-- The pad's one EXIT: up for as long as this player is on a pad, from the host's party screen through the queue after
-- CREATE, so the button the hand found on the first is the one on the second. It takes the player off the pad, and
-- goes away as the party leaves: a party on its way cannot be left.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local PadsCore = require(ReplicatedStorage.Shared.Core.PadsCore)
local Types = require(script.Parent.Parent.Types)

local create = vide.create
local derive = vide.derive
local source = vide.source
local Progress = Motion.Progress
local EPhase = PadsCore.EPhase

local Timing = table.freeze({
	-- It rises in once the party screen or the queue has started to come up, and shrinks away as they leave, or as
	-- the party teleports.
	DELAY = 0.3,
	IN = 0.42,
	OUT = 0.2,
	TELEPORT = 0.2,
})

local Exit = {}

function Exit.Build(state: Types.TLobbyState, actions: Types.TLobbyActions): ScreenGui
	local isTeleporting = derive(function(): boolean
		local pad = state.Pads[state.CurrentPad()]
		return pad ~= nil and pad.Phase() == EPhase.Teleporting
	end)
	-- Set as the pad is stepped on or left.
	local isShown = source(false)
	local toggledAt = source(-math.huge)
	vide.effect(function()
		local isOnPad = state.CurrentPad() ~= 0
		vide.untrack(function()
			if isOnPad == isShown() then return end
			isShown(isOnPad)
			toggledAt(os.clock())
			actions.Stir(Timing.DELAY + Timing.IN)
		end)
	end)
	local away = derive(function(): number
		local elapsed = state.Now() - toggledAt()
		if isShown() then return 1 - Motion.Decelerate(Progress(elapsed, Timing.DELAY, Timing.IN)) end
		return Motion.Accelerate(Progress(elapsed, 0, Timing.OUT))
	end)
	local teleported = Hand.Spring(function(): number
		return if isTeleporting() then 1 else 0
	end, Timing.TELEPORT)
	-- How far it still has to come, 1 to 0: on its way in or out, or going with the party.
	local gone = derive(function(): number
		return 1 - (1 - away()) * (1 - Motion.Accelerate(math.clamp(teleported(), 0, 1)))
	end)

	return create("ScreenGui")({
		Name = "PadExit",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		-- Over the party screen and its dim (5), which would take its presses.
		DisplayOrder = 6,
		Enabled = derive(function(): boolean
			return gone() < 0.999
		end),
		create("Frame")({
			Name = "Root",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(1920, 1080),
			BackgroundTransparency = 1,
			create("UIScale")({ Scale = state.PageScale }),
			Components.Exit(gone, actions.Leave, {
				Interactable = derive(function(): boolean
					return isShown() and not isTeleporting()
				end),
			}),
		}),
	})
end

return Exit
