-- Studio and test places only: the pistol's shot beside the plain tracers it replaced and the looks that lost to it
-- (VFX.md sections 1 and 30). The console's `pistolbench` stands one pistol a look in a row in front of the player,
-- each firing on the pistol's own rhythm at its own brick wall, the floor and a body. The looks are
-- Utils/pistolBenchLooks; one whose templates are not in the place is left out.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Conch = require(ReplicatedStorage.Packages.conch)
local gunFx = require(script.Parent.Parent.Parent.Utils.gunFx)
local pistolBenchLooks = require(script.Parent.Parent.Parent.Utils.pistolBenchLooks)
local tracers = require(script.Parent.Parent.Parent.Utils.tracers)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local sightCast = require(ReplicatedStorage.GlobalShared.Utils.sightCast)
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local EPlaceIds = require(ReplicatedStorage.Types.Enums.EPlaceIds)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)

local DebugPistolController = {}

local BEFORE = "Before"
-- Studs: the first gun ahead of the player, between guns, chest height over the feet, and where each target stands
-- ahead of its gun (and to its right).
local Layout = table.freeze({
	AHEAD = 10,
	SPACING = 9,
	HEIGHT = 4.2,
	WALL_AHEAD = 22,
	WALL_SIZE = Vector3.new(7, 7, 1),
	FLOOR_AHEAD = 9,
	FLOOR_RIGHT = -1.5,
	BODY_AHEAD = 13,
	BODY_RIGHT = 2.2,
	BODY_SIZE = Vector3.new(2, 5, 1.2),
})
-- One cycle: a shot at the wall, the floor and the body on the pistol's FireInterval, then a pause.
local CYCLE_SECONDS = 2.2
local TARGETS = table.freeze({ "Wall", "Floor", "Body" })
local WALL_COLOR = Color3.fromRGB(196, 40, 28)
local BODY_COLOR = Color3.fromRGB(99, 95, 98)
local GUN_COLOR = Color3.fromRGB(40, 42, 48)
local LIGHT_COLOR = Color3.fromRGB(255, 214, 20)
local LIGHT_SECONDS = 0.05

type TCell = {
	-- The kit this cell fires; nil is Before, the plain tracers.
	kit: string?,
	gun: Model,
	muzzle: Attachment,
	wall: BasePart,
	floorPoint: Vector3,
	body: BasePart,
	light: PointLight?,
}

local pistol = DataCore.Guns.ById[EGunsIds.StarterPistol]
local selfCharacter: Model? = nil
local selfRoot: BasePart? = nil
local benchFolder: Folder? = nil
local cells: { TCell } = {}
-- The looks the last PutUp found no templates for.
local leftOut: { string } = {}
local cycleStartedAt = 0
local nextShot = 1
local lightOffAt = 0
local soundPools: { SoundsCore.TSoundPool }? = nil
local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Include

-- ============================== Public API ==============================
function DebugPistolController.TakeDown()
	if benchFolder then benchFolder:Destroy() end
	benchFolder = nil
	table.clear(cells)
	if gunFx.FloorParams == castParams then gunFx.FloorParams = nil end
end

local function newPart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.Plastic
	part.Parent = parent
	return part
end

local function label(text: string, adornee: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 40)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = adornee
	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.GothamBlack
	textLabel.TextScaled = true
	textLabel.TextColor3 = Color3.new(1, 1, 1)
	textLabel.TextStrokeTransparency = 0
	textLabel.Text = text
	textLabel.Parent = gui
	gui.Parent = adornee
end

-- A copy of the pistol in the player's hands (its Handle with the Muzzle, and its model), anchored; a block with a
-- muzzle when the player holds something else.
local function newGun(parent: Instance): (Model, Attachment)
	local gun = Instance.new("Model")
	gun.Name = "Pistol"
	local tool = if selfCharacter then selfCharacter:FindFirstChildOfClass("Tool") else nil
	if tool and pistol and tool.Name == pistol.Name and tool:FindFirstChild("Handle") then
		-- The whole Tool, never its Handle alone: a cloned weld keeps pointing outside the clone, so a Handle cloned on
		-- its own stays welded to the player's gun, and anchoring and aiming it dragged the player along.
		local copy = tool:Clone()
		for _, descendant in copy:GetDescendants() do
			if
				descendant:IsA("JointInstance")
				or descendant:IsA("WeldConstraint")
				or descendant:IsA("LuaSourceContainer")
			then
				descendant:Destroy()
			elseif descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
			end
		end

		local handle = copy:FindFirstChild("Handle") :: BasePart
		-- Effect rigs gunFx put on the player's gun come along in the clone; the bench builds its own.
		for _, child in handle:GetChildren() do
			if child:IsA("Attachment") and child.Name ~= "Muzzle" then child:Destroy() end
		end

		local muzzle = handle:FindFirstChild("Muzzle") :: Attachment
		local light = muzzle:FindFirstChild("GunFxLight")
		if light then light:Destroy() end
		handle.Parent = gun
		local model = copy:FindFirstChild("Model")
		if model then model.Parent = gun end
		copy:Destroy()
		gun.PrimaryPart = handle
		gun.Parent = parent
		return gun, muzzle
	end

	local body = newPart("Handle", Vector3.new(0.35, 0.5, 1.9), CFrame.identity, GUN_COLOR, gun)
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0.1, -0.95)
	muzzle.Parent = body
	gun.PrimaryPart = body
	gun.Parent = parent
	return gun, muzzle
end

function DebugPistolController.PutUp()
	DebugPistolController.TakeDown()
	local root = selfRoot
	if not root then return end

	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	local forward = if look.Magnitude > 1e-3 then look.Unit else Vector3.zAxis
	local right = forward:Cross(Vector3.yAxis)
	local feet = root.Position - Vector3.new(0, root.Size.Y / 2 + 2, 0)
	local folder = Instance.new("Folder")
	folder.Name = "PistolBench"
	folder.Parent = Workspace
	benchFolder = folder

	-- Before, then every look whose templates are in the place.
	local stands: { { Name: string, Kit: string? } } = { { Name = BEFORE } }
	local effects = ReplicatedStorage:FindFirstChild("Effects")
	table.clear(leftOut)
	for _, entry in pistolBenchLooks do
		if not effects or not effects:FindFirstChild(entry.Kit) then
			leftOut[#leftOut + 1] = entry.Name
			continue
		end
		if entry.Look then gunFx.SetLook(entry.Kit, entry.Look) end
		stands[#stands + 1] = entry
	end

	for i, stand in stands do
		local base = feet + forward * Layout.AHEAD + right * ((i - (#stands + 1) / 2) * Layout.SPACING)
		local at = base + Vector3.new(0, Layout.HEIGHT, 0)
		local gun, muzzle = newGun(folder)
		gun:PivotTo(CFrame.lookAt(at, at + forward))
		label(stand.Name, gun.PrimaryPart :: BasePart)
		local wallAt = at + forward * Layout.WALL_AHEAD
		local wall = newPart("Wall", Layout.WALL_SIZE, CFrame.lookAt(wallAt, at), WALL_COLOR, folder)
		local bodyAt = base
			+ forward * Layout.BODY_AHEAD
			+ right * Layout.BODY_RIGHT
			+ Vector3.new(0, Layout.BODY_SIZE.Y / 2, 0)
		local body = newPart(
			"Body",
			Layout.BODY_SIZE,
			CFrame.lookAt(bodyAt, Vector3.new(at.X, bodyAt.Y, at.Z)),
			BODY_COLOR,
			folder
		)
		local floorPoint = base + forward * Layout.FLOOR_AHEAD + right * Layout.FLOOR_RIGHT
		local light: PointLight? = nil
		if not stand.Kit then
			light = Instance.new("PointLight")
			light.Color = LIGHT_COLOR
			light.Range = 8
			light.Enabled = false
			light.Parent = muzzle
		end

		cells[i] = {
			kit = stand.Kit,
			gun = gun,
			muzzle = muzzle,
			wall = wall,
			floorPoint = floorPoint,
			body = body,
			light = light,
		}
	end

	local filter: { Instance } = { folder }
	local arena = Workspace:FindFirstChild("Arena")
	if arena then filter[2] = arena end
	castParams.FilterDescendantsInstances = filter
	-- The bricks the bench's shots throw bounce on what its shots hit.
	gunFx.FloorParams = castParams
	cycleStartedAt = os.clock()
	nextShot = 1
end

-- ============================== Internals ==============================
local function targetOf(cell: TCell, kind: string): Vector3
	if kind == "Wall" then return cell.wall.Position end
	if kind == "Body" then return cell.body.Position end
	return cell.floorPoint
end

local function fire(cell: TCell, kind: string)
	local target = targetOf(cell, kind)
	local pivot = cell.gun:GetPivot()
	cell.gun:PivotTo(CFrame.lookAt(pivot.Position, target))
	local from = cell.muzzle.WorldPosition
	local direction = (target - from).Unit
	-- Past the target, so the floor point (on the ground, not in it) is still met.
	local result = sightCast(from, direction * ((target - from).Magnitude + 3), castParams)
	local to = if result then result.Position else target
	local isBody = result ~= nil and result.Instance == cell.body

	if not soundPools then
		soundPools = SoundsCore.CreateVariantPools("Guns", if pistol then pistol.Sound else "Starter", 4)
	end
	SoundsCore.PlayPooledRandom(soundPools :: { SoundsCore.TSoundPool }, from)

	local kit = cell.kit
	if not kit then
		tracers.Fire(from, to, false)
		tracers.Sparks(cell.muzzle.WorldCFrame, false)
		local light = cell.light :: PointLight
		light.Brightness = 4
		light.Enabled = true
		lightOffAt = os.clock() + LIGHT_SECONDS
		return
	end

	gunFx.Shot(kit, from, to, if isBody then nil else result, isBody, false)
	gunFx.Muzzle(kit, cell.muzzle, false)
end

local function step()
	if #cells == 0 then return end
	local now = os.clock()
	if now >= lightOffAt then
		for _, cell in cells do
			if cell.light then cell.light.Enabled = false end
		end
	end

	if now - cycleStartedAt >= CYCLE_SECONDS then
		cycleStartedAt += CYCLE_SECONDS
		nextShot = 1
	end

	local interval = if pistol then pistol.FireInterval else 0.4
	while nextShot <= #TARGETS and (nextShot - 1) * interval <= now - cycleStartedAt do
		local kind = TARGETS[nextShot]
		nextShot += 1
		for _, cell in cells do
			fire(cell, kind)
		end
	end
end

-- ============================== Wiring ==============================
DebugPistolController.OnSelfCharacterAdded = function(character)
	selfCharacter = character
	selfRoot = character.HumanoidRootPart
end :: TCharacterEvents.OnCharacterAdded

DebugPistolController.OnSelfCharacterRemoving = function()
	selfCharacter = nil
	selfRoot = nil
end :: TCharacterEvents.OnCharacterRemoving

DebugPistolController.OnStart = function()
	if not RunService:IsStudio() and not EPlaceIds.IsTest then return end

	Conch.register("pistolbench", {
		permissions = {},
		description = "Stand the pistol's shot beside the plain tracers and the looks that lost, firing (run again to take it down).",
		arguments = function() end,
		callback = function()
			if #cells > 0 then
				DebugPistolController.TakeDown()
				Conch.log("normal", "Pistol bench taken down.")
				return
			end

			DebugPistolController.PutUp()
			Conch.log("normal", if #cells > 0 then "Pistol bench up." else "No character to stand it by.")
			if #leftOut > 0 then
				Conch.log(
					"warn",
					`Not in the place: {table.concat(leftOut, ", ")}. Paste Assets/effects/pistol/pistol_effects.luau`
						.. " and pistol_bench_effects.luau into the command bar."
				)
			end
		end,
	})

	-- After WeaponController's PreRender, which steps gunFx and the tracers the bench fires.
	RunService.Heartbeat:Connect(step)
end

return Ignis.Register(DebugPistolController)
