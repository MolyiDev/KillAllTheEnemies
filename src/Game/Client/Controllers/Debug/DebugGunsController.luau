-- Studio and test places only: every starting gun's shot side by side (VFX.md section 32). The console's `gunbench`
-- stands one gun a kit in a row in front of the player, each firing on its own interval, pellets and spread at its own
-- brick wall, then the floor, then a body. A gun whose templates are not in the place is left out. `bulletbench`
-- stands one gun's bullet, the Comet, beside the styles that lost to it the same way (Assets/effects/bullets).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Conch = require(ReplicatedStorage.Packages.conch)
local bulletBenchStyles = require(script.Parent.Parent.Parent.Utils.bulletBenchStyles)
local gunFx = require(script.Parent.Parent.Parent.Utils.gunFx)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local GunsCore = require(ReplicatedStorage.GlobalShared.Core.GunsCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local sightCast = require(ReplicatedStorage.Shared.Utils.sightCast)
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local EPlaceIds = require(ReplicatedStorage.Types.Enums.EPlaceIds)
local CommandTypes = require(ReplicatedStorage.Types.CommandTypes)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)
local TData = require(ReplicatedStorage.Types.TData)

local DebugGunsController = {}

-- The run's ladder in order, then the sniper.
local GUNS = table.freeze({
	EGunsIds.StarterPistol,
	EGunsIds.TerminatorGun,
	EGunsIds.StarterRifle,
	EGunsIds.StarterSmg,
	EGunsIds.StarterShotgun,
})
-- Studs: the first gun ahead of the player, between guns, chest height over the feet, and where each target stands
-- ahead of its gun (and to its right).
local Layout = table.freeze({
	AHEAD = 10,
	SPACING = 13,
	HEIGHT = 4.2,
	WALL_AHEAD = 24,
	WALL_SIZE = Vector3.new(11, 9, 1),
	FLOOR_AHEAD = 10,
	FLOOR_RIGHT = -1.5,
	BODY_AHEAD = 14,
	BODY_RIGHT = 2.2,
	BODY_SIZE = Vector3.new(2, 5, 1.2),
})
-- The bullet bench's row: narrower, and its targets far enough out that a bullet is seen for a few frames.
local BulletLayout = table.freeze({
	AHEAD = 8,
	SPACING = 8,
	HEIGHT = 4.2,
	WALL_AHEAD = 60,
	WALL_SIZE = Vector3.new(7, 9, 1),
	FLOOR_AHEAD = 30,
	FLOOR_RIGHT = -1.5,
	BODY_AHEAD = 40,
	BODY_RIGHT = 1.6,
	BODY_SIZE = Vector3.new(2, 5, 1.2),
})
local BULLET_GUN = EGunsIds.StarterPistol
-- Seconds on each target before the next.
local TARGET_SECONDS = 1.6
local TARGETS = table.freeze({ "Wall", "Floor", "Body" })
local WALL_COLOR = Color3.fromRGB(196, 40, 28)
local BODY_COLOR = Color3.fromRGB(99, 95, 98)
local GUN_COLOR = Color3.fromRGB(40, 42, 48)
local SOUND_VOICES = 4

-- One cell of a row: the gun it fires, the kit it is drawn with and the name over it.
type TStand = { gun: TData.TGun, kit: string, label: string }

type TCell = {
	gun: TData.TGun,
	kit: string,
	handle: BasePart,
	muzzle: Attachment,
	wall: BasePart,
	floorPoint: Vector3,
	body: BasePart,
	nextShotAt: number,
	shots: number,
	sounds: { SoundsCore.TSoundPool },
}

local selfRoot: BasePart? = nil
local benchFolder: Folder? = nil
local cells: { TCell } = {}
-- What the last put-up found no templates for.
local leftOut: { string } = {}
local startedAt = 0
local pelletDirections: { Vector3 } = {}
local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Include

-- ============================== Public API ==============================
function DebugGunsController.TakeDown()
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
	gui.Size = UDim2.fromOffset(180, 40)
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

local function standRow(root: BasePart, stands: { TStand }, layout: typeof(Layout))
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	local forward = if look.Magnitude > 1e-3 then look.Unit else Vector3.zAxis
	local right = forward:Cross(Vector3.yAxis)
	local feet = root.Position - Vector3.new(0, root.Size.Y / 2 + 2, 0)
	local folder = Instance.new("Folder")
	folder.Name = "GunBench"
	folder.Parent = Workspace
	benchFolder = folder

	for i, stand in stands do
		local gun = stand.gun
		local base = feet + forward * layout.AHEAD + right * ((i - (#stands + 1) / 2) * layout.SPACING)
		local at = base + Vector3.new(0, layout.HEIGHT, 0)
		local handle =
			newPart("Handle", Vector3.new(0.35, 0.5, gun.Length), CFrame.lookAt(at, at + forward), GUN_COLOR, folder)
		handle.CanQuery = false
		local muzzle = Instance.new("Attachment")
		muzzle.Name = "Muzzle"
		muzzle.Position = Vector3.new(0, 0.1, -gun.Length / 2)
		muzzle.Parent = handle
		label(stand.label, handle)

		local wallAt = at + forward * layout.WALL_AHEAD
		local bodyAt = base
			+ forward * layout.BODY_AHEAD
			+ right * layout.BODY_RIGHT
			+ Vector3.new(0, layout.BODY_SIZE.Y / 2, 0)
		cells[i] = {
			gun = gun,
			kit = stand.kit,
			handle = handle,
			muzzle = muzzle,
			wall = newPart("Wall", layout.WALL_SIZE, CFrame.lookAt(wallAt, at), WALL_COLOR, folder),
			floorPoint = base + forward * layout.FLOOR_AHEAD + right * layout.FLOOR_RIGHT,
			body = newPart(
				"Body",
				layout.BODY_SIZE,
				CFrame.lookAt(bodyAt, Vector3.new(at.X, bodyAt.Y, at.Z)),
				BODY_COLOR,
				folder
			),
			-- Staggered, so the row does not fire as one.
			nextShotAt = 0.1 * i,
			shots = 0,
			sounds = SoundsCore.CreateVariantPools("Guns", gun.Sound, SOUND_VOICES),
		}
	end

	local filter: { Instance } = { folder }
	local arena = Workspace:FindFirstChild("Arena")
	if arena then filter[2] = arena end
	castParams.FilterDescendantsInstances = filter
	-- The bricks the bench's shots throw bounce on what its shots hit.
	gunFx.FloorParams = castParams
	startedAt = os.clock()
end

function DebugGunsController.PutUp()
	DebugGunsController.TakeDown()
	local root = selfRoot
	if not root then return end

	local stands: { TStand } = {}
	local effects = ReplicatedStorage:FindFirstChild("Effects")
	table.clear(leftOut)
	for _, id in GUNS do
		local gun = DataCore.Guns.ById[id]
		local kit = if gun then gun.Fx else nil
		if not gun or not kit then continue end
		if not effects or not effects:FindFirstChild(kit) then
			leftOut[#leftOut + 1] = gun.Name
			continue
		end
		stands[#stands + 1] = { gun = gun, kit = kit, label = gun.Name }
	end
	if #stands == 0 then return end

	standRow(root, stands, Layout)
end

-- `gunId`'s own bullet, then each style that lost to it (VFX.md 1 and 34), side by side.
function DebugGunsController.PutUpBullets(gunId: number)
	DebugGunsController.TakeDown()
	local root = selfRoot
	local gun = DataCore.Guns.ById[gunId]
	local kit = if gun then gun.Fx else nil
	if not root or not gun or not kit then return end
	local effects = ReplicatedStorage:FindFirstChild("Effects")
	table.clear(leftOut)
	if not effects or not effects:FindFirstChild(kit) then
		leftOut[1] = gun.Name
		return
	end

	local stands: { TStand } = { { gun = gun, kit = kit, label = "Comet (in game)" } }
	for _, style in bulletBenchStyles.STYLES do
		local name = `{kit}.{style}`
		if bulletBenchStyles.Use(kit, style, name) then
			stands[#stands + 1] = { gun = gun, kit = name, label = style }
		else
			leftOut[#leftOut + 1] = style
		end
	end

	standRow(root, stands, BulletLayout)
end

-- ============================== Internals ==============================
-- A console gun name (lower case) as its id.
local function gunIdOf(name: string): number?
	for key, id in EGunsIds :: { [string]: number } do
		if string.lower(key) == name then return id end
	end
	return nil
end

local function targetOf(cell: TCell, kind: string): Vector3
	if kind == "Wall" then return cell.wall.Position end
	if kind == "Body" then return cell.body.Position end
	return cell.floorPoint
end

local function fire(cell: TCell, kind: string)
	local gun = cell.gun
	local target = targetOf(cell, kind)
	cell.handle.CFrame = CFrame.lookAt(cell.handle.Position, target)
	local from = cell.muzzle.WorldPosition
	local pellets = math.min(gun.Pellets, GunsCore.Tune.MAX_PELLETS)
	cell.shots += 1
	GunsCore.PelletDirections((target - from).Unit, cell.shots, gun.SpreadDeg, pellets, pelletDirections)
	SoundsCore.PlayPooledRandom(cell.sounds, from)

	local kit = cell.kit
	for pellet = 1, pellets do
		local direction = pelletDirections[pellet]
		local result = sightCast(from, direction * gun.Range, castParams)
		local to = if result then result.Position else from + direction * gun.Range
		local isBody = result ~= nil and result.Instance == cell.body
		local normal = if result and not isBody then result.Normal else nil
		local surface = if result and not isBody then gunFx.SurfaceColor(result) else nil
		gunFx.Shot(kit, from, to, normal, surface, isBody, false)
	end
	gunFx.Muzzle(kit, cell.muzzle, false)
end

local function step()
	if #cells == 0 then return end
	local elapsed = os.clock() - startedAt
	local kind = TARGETS[math.floor(elapsed / TARGET_SECONDS) % #TARGETS + 1]
	for _, cell in cells do
		if elapsed < cell.nextShotAt then continue end
		-- One shot a frame at most: a hitch is not made up with a volley.
		cell.nextShotAt = math.max(cell.nextShotAt + cell.gun.FireInterval, elapsed)
		fire(cell, kind)
	end
end

-- ============================== Wiring ==============================
DebugGunsController.OnSelfCharacterAdded = function(character)
	selfRoot = character.HumanoidRootPart
end :: TCharacterEvents.OnCharacterAdded

DebugGunsController.OnSelfCharacterRemoving = function()
	selfRoot = nil
end :: TCharacterEvents.OnCharacterRemoving

DebugGunsController.OnStart = function()
	if not RunService:IsStudio() and not EPlaceIds.IsTest then return end

	Conch.register("gunbench", {
		permissions = {},
		description = "Stand every starting gun's shot in a row, firing (run again to take it down).",
		arguments = function() end,
		callback = function()
			if #cells > 0 then
				DebugGunsController.TakeDown()
				Conch.log("normal", "Gun bench taken down.")
				return
			end

			DebugGunsController.PutUp()
			Conch.log("normal", if #cells > 0 then "Gun bench up." else "No character or no kit to stand.")
			if #leftOut > 0 then
				Conch.log(
					"warn",
					`Not in the place: {table.concat(leftOut, ", ")}. Paste Assets/effects/guns/gun_effects.luau`
						.. " into the command bar."
				)
			end
		end,
	})

	Conch.register("bulletbench", {
		permissions = {},
		description = "Stand a gun's bullet beside the styles that lost to it, firing (run again to take it down).",
		arguments = function()
			return Conch.args.optional(CommandTypes.gunName("gun", "The gun to fire (the pistol without one)."))
		end,
		callback = function(name: string?)
			if #cells > 0 then
				DebugGunsController.TakeDown()
				Conch.log("normal", "Bullet bench taken down.")
				return
			end

			local gunId = if name then gunIdOf(name) else BULLET_GUN
			if not gunId then
				Conch.log("warn", `No gun {name}.`)
				return
			end
			DebugGunsController.PutUpBullets(gunId)
			Conch.log("normal", if #cells > 0 then "Bullet bench up." else "No character or no kit to stand.")
			if #leftOut > 0 then
				Conch.log(
					"warn",
					`Not in the place: {table.concat(leftOut, ", ")}. Paste Assets/effects/bullets/bullet_styles.luau`
						.. " (or the gun's kit) into the command bar."
				)
			end
		end,
	})

	-- After WeaponController's PreRender, which steps gunFx.
	RunService.Heartbeat:Connect(step)
end

return Ignis.Register(DebugGunsController)
