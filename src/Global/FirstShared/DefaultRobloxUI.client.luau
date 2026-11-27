-- Turns off Roblox's default UI in both places before anything else loads: the HUD draws its own health and kit, so
-- only the chat stays. Touch controls stay on: no custom mobile controls replace them. The default loading screen is
-- LoadingScreen.client's to remove, once its own cover is up.

local StarterGui = game:GetService("StarterGui")

-- All rather than a list, so a CoreGuiType Roblox adds later is off too. It can error while the CoreGui is still
-- loading, so retry until it takes.
while not pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.All, false) do
	task.wait()
end
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true)
