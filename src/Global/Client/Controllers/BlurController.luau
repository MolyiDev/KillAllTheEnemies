-- The one blur over the world, held by every screen that covers it (UI.md 5o). A BlurEffect never blurs the GUI, so
-- the HUD a screen pays into stays sharp.
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Tune = table.freeze({
	SIZE = 20,
	-- Eased on a sine in-out (UI.md 5o, "ease what is perceived").
	IN = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
	OUT = TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
})

local BlurController = {}

local reasons: { [string]: true } = {}
local isBlurred = false

local effect = Instance.new("BlurEffect")
effect.Name = "ScreenBlur"
effect.Size = 0
effect.Enabled = false
effect.Parent = Lighting
local blurIn = TweenService:Create(effect, Tune.IN, { Size = Tune.SIZE })
local blurOut = TweenService:Create(effect, Tune.OUT, { Size = 0 })

-- The world is blurred while any reason holds it, so two screens handing over never let it clear between them.
function BlurController.SetBlurred(reason: string, isOn: boolean)
	reasons[reason] = if isOn then true else nil
	local shouldBlur = next(reasons) ~= nil
	if shouldBlur == isBlurred then return end
	isBlurred = shouldBlur

	if shouldBlur then
		effect.Enabled = true
		blurIn:Play()
	else
		blurOut:Play()
	end
end

-- Switched off once it has eased out, so no blur pass runs while nothing covers the world. Playing the other tween
-- cancels this one, which is not a completion.
blurOut.Completed:Connect(function(playbackState: Enum.PlaybackState)
	if playbackState == Enum.PlaybackState.Completed then effect.Enabled = false end
end)

return BlurController
