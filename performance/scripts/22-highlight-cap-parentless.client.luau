--!optimize 2
-- DO HIGHLIGHTS THAT WERE NEVER PARENTED COUNT AGAINST THE 255 CAP?
--
-- Roblox's docs confirm a DISABLED highlight still takes a slot. A 2025 bug report claims one sitting in
-- ReplicatedStorage does too, but that is a user's observation with no staff reply, and neither source says
-- anything about a highlight whose Parent was never set at all.
--
-- This is a purely visual test, because nothing in the API reports how many slots are in use. One slime sits in
-- front of the camera with a full-white highlight. If it renders white, the highlight got a slot. If it renders
-- as a normal slime, it did not.
--
-- ORDER IS THE WHOLE TEST. The extra highlights are created FIRST and the visible slime's highlight LAST, so the
-- visible one is the last in line for a slot. Creating it first would let it keep a slot it grabbed early and
-- the test would pass no matter what.
--
-- Four stages, cycled twice so it can be checked rather than glimpsed:
--
--   A  no extras                     - control. Must be WHITE, or the harness itself is broken.
--   B  300 highlights, NEVER PARENTED - the question. Held only by a Lua table.
--   C  300 highlights in ReplicatedStorage - the forum claim, as a reference point.
--   D  no extras again               - proves the effect is the cap and reverses, not something sticky.
--
-- A big label on screen names the current stage, so it can be read off directly.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local SLIME = ReplicatedStorage:WaitForChild("Models"):WaitForChild("Enemies"):WaitForChild("Slime")

local EXTRA_COUNT = 300
local HOLD_SECONDS = 12
local CYCLES = 2

local WHITE = Color3.new(1, 1, 1)

local extras = {}
local extraFolder = nil
local subject = nil
local label = nil

local function newHighlight()
	local highlight = Instance.new("Highlight")
	highlight.FillColor = WHITE
	highlight.FillTransparency = 0
	highlight.OutlineColor = Color3.new(1, 0, 0)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = true
	return highlight
end

local function clearExtras()
	for i = 1, #extras do
		extras[i]:Destroy()
	end
	table.clear(extras)
	if extraFolder then
		extraFolder:Destroy()
		extraFolder = nil
	end
end

local function clearSubject()
	if subject then
		subject:Destroy()
		subject = nil
	end
end

-- where: "none" | "orphan" | "rs"
local function makeExtras(where)
	if where == "none" then return 0 end

	if where == "rs" then
		extraFolder = Instance.new("Folder")
		extraFolder.Name = "CapExtras"
		extraFolder.Parent = ReplicatedStorage
	end

	for i = 1, EXTRA_COUNT do
		local highlight = newHighlight()
		if where == "rs" then highlight.Parent = extraFolder end
		-- "orphan": Parent is never assigned. The table reference is the only thing keeping it alive.
		extras[i] = highlight
	end
	return EXTRA_COUNT
end

local function makeSubject()
	local model = SLIME:Clone()
	local mesh = model:FindFirstChildWhichIsA("MeshPart")
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.CFrame = CFrame.new(0, 0, 0)
	model.Parent = workspace
	subject = model
	-- Created LAST, on purpose.
	newHighlight().Parent = model
end

task.spawn(function()
	task.wait(3)
	local character = player.Character or player.CharacterAdded:Wait()
	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if hrp then
		hrp.Anchored = true
		hrp.CFrame = CFrame.new(0, 500, 0)
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 70
	camera.CFrame = CFrame.new(Vector3.new(0, 1.5, 9), Vector3.new(0, 0, 0))

	local gui = Instance.new("ScreenGui")
	gui.Name = "CapProbeUI"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 0.16)
	label.Position = UDim2.fromScale(0, 0.02)
	label.BackgroundTransparency = 0.35
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.TextColor3 = WHITE
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = "starting"
	label.Parent = gui

	local stages = {
		{ Name = "A  CONTROL, 0 extras", Where = "none" },
		{ Name = "B  " .. EXTRA_COUNT .. " highlights, NEVER PARENTED", Where = "orphan" },
		{ Name = "C  " .. EXTRA_COUNT .. " highlights in ReplicatedStorage", Where = "rs" },
		{ Name = "D  CONTROL again, 0 extras", Where = "none" },
	}

	print("[CAP] ===== does a never-parented Highlight take a slot? =====")
	print("[CAP] the slime's own highlight is created LAST every stage, so it is last in line for a slot")
	print("[CAP] WHITE slime = it got a slot.  Normal blue slime = it did not.")

	for cycle = 1, CYCLES do
		for _, stage in stages do
			clearSubject()
			clearExtras()
			task.wait(0.75)

			local made = makeExtras(stage.Where)
			makeSubject()

			label.Text = string.format("cycle %d/%d   %s", cycle, CYCLES, stage.Name)
			print(string.format("[CAP] cycle %d  %-46s extras=%d", cycle, stage.Name, made))

			task.wait(HOLD_SECONDS)
		end
	end

	clearSubject()
	clearExtras()
	label.Text = "done"
	print("[CAP] ===== done =====")
end)
