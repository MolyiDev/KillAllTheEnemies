-- The plus on an open place's body (LobbyController/Party/Ghosts) drawn flat, its billboard's contents laid on a
-- frame, for rur (which draws no world-space billboards): its landing ring, at rest, and under the hand.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Ghosts = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.LobbyController.Party.Ghosts)

return {
	vide = vide,
	story = function()
		local stage = Instance.new("Frame")
		stage.Size = UDim2.fromOffset(1920, 1080)
		stage.BackgroundTransparency = 1
		local pad = Instance.new("Part")
		pad.Size = Vector3.new(24, 1, 10)
		pad.CFrame = CFrame.new()
		-- Each column: its moment (seconds after it opened) and whether the hand is on it.
		local columns = { { 0.55, false }, { 2, false }, { 2, true } }
		for index, column in columns do
			local ghost = Ghosts.Build(pad, 2, Instance.new("Folder"))
			Ghosts.Open(ghost, true, false, 0)
			for frame = 0, 60 do
				Ghosts.Step(ghost, column[1] * frame / 60, column[1] / 60, column[2])
			end
			local board = ghost.Model:FindFirstChildOfClass("BillboardGui") :: BillboardGui
			local back = Instance.new("Frame")
			back.Position = UDim2.fromOffset(160 + (index - 1) * 560, 240)
			back.Size = UDim2.fromOffset(440, 440)
			back.BackgroundColor3 = Color3.fromRGB(10, 7, 21)
			back.BorderSizePixel = 0
			back.Parent = stage
			for _, child in board:GetChildren() do
				child.Parent = back
			end
		end
		return stage
	end,
}
