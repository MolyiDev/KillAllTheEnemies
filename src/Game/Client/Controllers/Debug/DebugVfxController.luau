-- Studio and test places only: the enemy-burst bench (VFX.md sections 1 and 31). The console's `vfxbench` stands one
-- body of every enemy type in a row in front of the player, each looping three hits, a kill, a vanish and an overkill
-- through the game's own enemyImpacts, the blows dealt from where the player stood, so the bursts are judged on
-- every body's colours and size.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Conch = require(ReplicatedStorage.Packages.conch)
local EnemyImpacts = require(script.Parent.Parent.Parent.Parent.GlobalClient.Utils.enemyImpacts)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local EnemiesCore = require(ReplicatedStorage.Shared.Core.EnemiesCore)
local EPlaceIds = require(ReplicatedStorage.Types.Enums.EPlaceIds)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)
local TData = require(ReplicatedStorage.Types.TData)

local DebugVfxController = {}

-- Studs ahead of the player and between bodies.
local BENCH_DISTANCE = 14
local BENCH_SPACING = 8
-- One cycle, in seconds from its start: what happens when. A killed body is hidden (it cannot ragdoll here) until it
-- comes back.
local CYCLE_SECONDS = 5.8
-- Each body runs this far behind the one before it: the game draws a few bursts a frame, and a row is read better
-- as a ripple than all at once.
local STAGGER_SECONDS = 0.12
local SCRIPT = table.freeze({
	{ at = 0, kind = "Hit" },
	{ at = 0.35, kind = "Hit" },
	{ at = 0.7, kind = "Hit" },
	{ at = 1.3, kind = "Kill" },
	{ at = 2.3, kind = "Show" },
	{ at = 2.7, kind = "Vanish" },
	{ at = 3.8, kind = "Show" },
	{ at = 4.2, kind = "Overkill" },
	{ at = 5.4, kind = "Show" },
})
local FLASH_SECONDS = 0.12

local WHITE = Color3.new(1, 1, 1)

type TStand = {
	model: Model,
	highlight: Highlight,
	enemyData: TData.TEnemy,
	chest: Vector3,
	aim: vector,
	-- Where it is in its cycle.
	startedAt: number,
	nextStep: number,
	flashEndsAt: number,
}

local selfRoot: BasePart? = nil
local benchFolder: Folder? = nil
local stands: { TStand } = {}
-- Where the bench's blows come from: where the player stood when it went up.
local blowsFrom = Vector3.zero

-- ============================== Public API ==============================
function DebugVfxController.TakeDown()
	if benchFolder then benchFolder:Destroy() end
	benchFolder = nil
	table.clear(stands)
end

local function label(text: string, adornee: BasePart, height: number, parent: Instance)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 40)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = adornee
	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.GothamBlack
	textLabel.TextScaled = true
	textLabel.TextColor3 = WHITE
	textLabel.TextStrokeTransparency = 0
	textLabel.Text = text
	textLabel.Parent = gui
	gui.Parent = parent
end

-- A body stood as the renderer stands one: anchored at the origin, its Root bone carrying the world frame, half a
-- body up because a skinned body deforms about its MeshPart's centre.
local function standBody(template: Model, feet: CFrame, parent: Instance): (Model, Highlight)
	local model = template:Clone()
	local highlight = Instance.new("Highlight")
	highlight.FillColor = WHITE
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	model.Parent = parent
	local root = (model :: any).PrimaryPart.Root :: Bone
	root.Transform = feet * CFrame.new(0, model:GetExtentsSize().Y / 2, 0)
	return model, highlight
end

function DebugVfxController.PutUp()
	DebugVfxController.TakeDown()
	local root = selfRoot
	if not root then return end

	local types = {}
	for _, enemyData in DataCore.Enemies.All do
		if EnemiesCore.HasModel(enemyData) then types[#types + 1] = enemyData end
	end
	if #types == 0 then return end

	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	local forward = if look.Magnitude > 1e-3 then look.Unit else Vector3.zAxis
	local right = forward:Cross(Vector3.yAxis)
	local feetY = root.Position.Y - root.Size.Y / 2 - 2
	local center = Vector3.new(root.Position.X, feetY, root.Position.Z) + forward * BENCH_DISTANCE
	local folder = Instance.new("Folder")
	folder.Name = "VfxBench"
	folder.Parent = Workspace
	benchFolder = folder
	blowsFrom = root.Position

	local now = os.clock()
	for i, enemyData in types do
		local aim = EnemiesCore.AimShape(enemyData)
		local feet = center + right * ((i - (#types + 1) / 2) * BENCH_SPACING)
		-- A rig faces its own +Z, so it looks at the player with its LookVector pointing away.
		local model, highlight = standBody(EnemiesCore.GetModel(enemyData), CFrame.lookAt(feet, feet + forward), folder)
		-- The mesh stays at the origin (its bone carries it), so the label hangs on a marker where the body stands.
		local marker = Instance.new("Part")
		marker.Anchored = true
		marker.CanCollide = false
		marker.CanQuery = false
		marker.Transparency = 1
		marker.Size = Vector3.one
		marker.Position = feet
		marker.Parent = folder
		label(enemyData.Name, marker, aim.y + 1.5, folder)
		stands[i] = {
			model = model,
			highlight = highlight,
			enemyData = enemyData,
			chest = feet + Vector3.new(0, aim.x, 0),
			aim = aim,
			startedAt = now + (i - 1) * STAGGER_SECONDS,
			nextStep = 1,
			flashEndsAt = 0,
		}
	end
end

-- ============================== Internals ==============================
local function setHidden(stand: TStand, isHidden: boolean)
	local part = (stand.model :: any).PrimaryPart :: BasePart
	part.Transparency = if isHidden then 1 else 0
end

-- A kill is the kill's burst, a vanish that and the puffs, an overkill its own burst alone, as in the game.
local function play(stand: TStand, kind: string, now: number)
	local enemyData, chest, aim = stand.enemyData, stand.chest, stand.aim
	if kind == "Hit" then
		EnemyImpacts.EmitHit(enemyData, chest, aim, blowsFrom)
	elseif kind == "Kill" or kind == "Vanish" then
		EnemyImpacts.EmitKill(enemyData, chest, aim, blowsFrom)
		if kind == "Vanish" then EnemyImpacts.EmitVanish(enemyData, chest, aim) end
	elseif kind == "Overkill" then
		EnemyImpacts.EmitOverkill(enemyData, chest, aim, blowsFrom)
	end

	if kind ~= "Hit" then setHidden(stand, kind ~= "Show") end
	if kind ~= "Show" and kind ~= "Overkill" then
		stand.highlight.FillTransparency = 0
		stand.flashEndsAt = now + FLASH_SECONDS
	end
end

local function step()
	local now = os.clock()
	for _, stand in stands do
		if now - stand.startedAt >= CYCLE_SECONDS then
			stand.startedAt += CYCLE_SECONDS
			stand.nextStep = 1
		end

		local elapsed = now - stand.startedAt
		while stand.nextStep <= #SCRIPT and SCRIPT[stand.nextStep].at <= elapsed do
			local kind = SCRIPT[stand.nextStep].kind
			stand.nextStep += 1
			play(stand, kind, now)
		end

		if stand.flashEndsAt > 0 and now >= stand.flashEndsAt then
			stand.flashEndsAt = 0
			stand.highlight.FillTransparency = 1
		end
	end
end

-- ============================== Wiring ==============================
DebugVfxController.OnSelfCharacterAdded = function(character)
	selfRoot = character.HumanoidRootPart
end :: TCharacterEvents.OnCharacterAdded

DebugVfxController.OnSelfCharacterRemoving = function()
	selfRoot = nil
end :: TCharacterEvents.OnCharacterRemoving

DebugVfxController.OnStart = function()
	if not RunService:IsStudio() and not EPlaceIds.IsTest then return end

	Conch.register("vfxbench", {
		permissions = {},
		description = "Stand the enemy bursts in front of you, one body per enemy type (run again to take it down).",
		arguments = function() end,
		callback = function()
			if #stands > 0 then
				DebugVfxController.TakeDown()
				Conch.log("normal", "VFX bench taken down.")
				return
			end

			DebugVfxController.PutUp()
			Conch.log("normal", if #stands > 0 then "VFX bench up." else "No character or no zombie rig to stand.")
		end,
	})

	RunService.Heartbeat:Connect(step)
end

return Ignis.Register(DebugVfxController)
