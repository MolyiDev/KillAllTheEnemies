-- BALLARC_BENCH probe (client, top-level dump): injected by run.py, never in src. Never publish.
-- Each closed screen's top-level children and its descendants that still count as visible.
local R = game:GetService("ReplicatedStorage")
local H = game:GetService("HttpService")
local P = game:GetService("Players")
task.wait(4)
local function log(v) v.label = "__LABEL__"; print("[BALLARC_BENCH_CLIENT] " .. H:JSONEncode(v)) end
R:WaitForChild("BallarcBenchReady"):FireServer()
task.wait(10)
local playerGui = P.LocalPlayer:WaitForChild("PlayerGui")
local NAMES = { "InfoGui", "SettingsUI", "SettingsUIBackdrop", "RestartRadialUI", "KickUI", "KickUIBackdrop", "PauseUI", "SelfReviveUI", "DialogueUI", "InGameTutorialSide", "RarityImpactScreen", "AugmentGui", "UpgradeGui", "RewardConfettiGui", "QuestStowGui", "PassiveChangesUI", "OffScreenIndicatorUI", "ChestGui", "WinBoxUI", "FinalStatsUI", "SpectatorUI", "ColorDanceUI", "QuestLockWarningUI", "AnnouncementsUI" }
for _, name in NAMES do
	local gui = playerGui:FindFirstChild(name)
	if not gui then continue end
	local tops = {}
	for _, child in gui:GetChildren() do
		tops[#tops + 1] = string.format("%s:%s vis=%s", child.Name, child.ClassName, if child:IsA("GuiObject") then tostring(child.Visible) else "-")
	end
	local shown = {}
	for _, d in gui:GetDescendants() do
		if d:IsA("GuiObject") then
			local ok = d.Visible
			local node = d.Parent
			while ok and node and node ~= gui do
				if node:IsA("GuiObject") and not node.Visible then ok = false end
				node = node.Parent
			end
			if ok and #shown < 6 then
				shown[#shown + 1] = string.format("%s bgT=%.2f size=%s", d:GetFullName():sub(#gui:GetFullName() + 2), d.BackgroundTransparency, tostring(d.AbsoluteSize))
			end
		end
	end
	log({ gui = name, enabled = gui.Enabled, tops = tops, shown = shown })
end
local all = {}
for _, child in playerGui:GetChildren() do
	if child:IsA("LayerCollector") then all[#all + 1] = child.Name .. (if child.Enabled then "" else "(off)") end
end
log({ all = all })
log({ phase = "done" })
