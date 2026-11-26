--!strict
-- Every screen's UI giving way to a cutscene as one (a boss's intro): `Shown` runs from 1 (up) to 0 (gone) while
-- `SetHidden(true)` holds, and back after. Each ScreenGui wraps its content in `Group`, so nothing is drawn through a
-- CanvasGroup at rest, and takes `IsUp` as its Enabled.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)

local UiFade = {}

local Tune = table.freeze({
	HIDE_SECONDS = 0.5,
	SHOW_SECONDS = 0.6,
})

UiFade.Shown = vide.source(1)
-- Anything left to draw. Set only as it flips, so an Enabled bound to it is not rewritten every frame of the fade.
UiFade.IsUp = vide.source(true)
-- What was last asked for, for a piece with its own way out (a top bar icon stepping aside).
UiFade.IsHidden = vide.source(false)

-- Linear 0 (gone) to 1 (up); Shown is it eased.
local progress = 1
local connection: RBXScriptConnection? = nil

-- `content` in a screen-sized frame that fades with every screen's UI.
function UiFade.Group(content: { any }): { Instance }
	return Components.FadeGroup("Fade", UiFade.Shown, { Size = UDim2.fromScale(1, 1) }, content)
end

-- Runs only while the fade moves.
local function step(dt: number)
	local isHidden = UiFade.IsHidden()
	local seconds = if isHidden then Tune.HIDE_SECONDS else Tune.SHOW_SECONDS
	progress = math.clamp(progress + (if isHidden then -dt else dt) / seconds, 0, 1)
	UiFade.Shown(progress * progress * (3 - 2 * progress))

	local isUp = progress > 0
	if isUp ~= UiFade.IsUp() then UiFade.IsUp(isUp) end
	local isSettled = if isHidden then progress <= 0 else progress >= 1
	if isSettled and connection then
		connection:Disconnect()
		connection = nil
	end
end

function UiFade.SetHidden(isHidden: boolean)
	if isHidden == UiFade.IsHidden() then return end
	UiFade.IsHidden(isHidden)
	if not connection then connection = RunService.PreRender:Connect(step) end
end

return UiFade
