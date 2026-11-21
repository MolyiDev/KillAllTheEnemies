--!optimize 2
-- DOES A HIGHLIGHT INSIDE A NEVER-PARENTED MODEL COUNT AGAINST THE 255 CAP?
--
-- 22-highlight-cap-parentless established two things by eye:
--
--   a Highlight whose own Parent is never set        does NOT take a slot
--   a Highlight sitting in ReplicatedStorage          DOES take a slot
--
-- Neither covers the arrangement that actually matters for enemy templates: the Highlight IS parented, to a
-- Model, and it is the MODEL that has no parent. The plan it enables is worth being sure about - keep one
-- detached template per enemy type in a Lua table, each with its Highlight already inside, and clone from those.
-- With 100 enemy types that is the difference between 0 slots and 100 of the 255 spent before a single enemy
-- exists.
--
-- The DataModel-membership rule from run 22 predicts this is free, since a detached Model is no more part of the
-- DataModel than a detached Highlight. Predicted is not measured.
--
-- Nothing in the API reports slot usage, so this is visual, same as 22. One slime sits in front of the camera
-- with a full-white highlight, and its highlight is created LAST every stage so it is last in line for a slot.
--
--   A  control, 0 extras                                    must be WHITE
--   B  300 detached Models, each containing a Highlight      the plan
--   C  300 Models in ReplicatedStorage, each with a Highlight the thing the plan avoids, as contrast
--   D  control again                                        proves it reverses
--
-- If B is white and C is not, the plan works.

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

-- A stand-in for an enemy template: a Model with a part and a Highlight inside it. Cheap enough to make 300 of.
local function newTemplateModel()
	local model = Instance.new("Model")
	local part = Instance.new("Part")
	part.Anchored = true
	part.Size = Vector3.one
	part.Parent = model
	model.PrimaryPart = part
	newHighlight().Parent = model
	return model
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

-- where: "none" | "detached" | "rs"
local function makeExtras(where)
	if where == "none" then return 0 end

	if where == "rs" then
		extraFolder = Instance.new("Folder")
		extraFolder.Name = "CapExtras"
		extraFolder.Parent = ReplicatedStorage
	end

	for i = 1, EXTRA_COUNT do
		local model = newTemplateModel()
		if where == "rs" then model.Parent = extraFolder end
		-- "detached": the Model's Parent is never assigned. The Highlight inside it IS parented, to the Model.
		extras[i] = model
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

	local label = Instance.new("TextLabel")
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
		{ Name = "A  CONTROL, 0 extras            expect WHITE", Where = "none" },
		{ Name = "B  " .. EXTRA_COUNT .. " DETACHED models + HL     the plan", Where = "detached" },
		{ Name = "C  " .. EXTRA_COUNT .. " models in ReplicatedStorage  contrast", Where = "rs" },
		{ Name = "D  CONTROL again                expect WHITE", Where = "none" },
	}

	print("[CAP2] ===== does a Highlight inside a NEVER-PARENTED MODEL take a slot? =====")
	print("[CAP2] WHITE slime = the slime's highlight got a slot.  Normal blue slime = it did not.")
	print("[CAP2] B is the arrangement enemy templates would use. If B is WHITE, detached templates are free.")

	for cycle = 1, CYCLES do
		for _, stage in stages do
			clearSubject()
			clearExtras()
			task.wait(0.75)

			local made = makeExtras(stage.Where)
			makeSubject()

			label.Text = string.format("cycle %d/%d   %s", cycle, CYCLES, stage.Name)
			print(string.format("[CAP2] cycle %d  %-52s extras=%d", cycle, stage.Name, made))

			task.wait(HOLD_SECONDS)
		end
	end

	clearSubject()
	clearExtras()
	label.Text = "done"
	print("[CAP2] ===== done =====")
end)
