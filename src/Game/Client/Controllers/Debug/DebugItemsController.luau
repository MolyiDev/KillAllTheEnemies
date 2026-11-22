-- Studio and test places only: the bought items' bench (VFX.md sections 1 and 36). The console's `itembench nuke`
-- stands a crowd of every enemy type round the player and sets the nuke off there again and again; `itembench heal`
-- stands a squad beside the player and heals it again and again. Both go through the game's own signals
-- (MatchController.OnNukedAll, OnHealedAll), so the blast, the shake, the wash, the sound and the banner are the
-- game's; only the bodies are stand-ins, burst as the front reaches them the way the server would kill them.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Conch = require(ReplicatedStorage.Packages.conch)
local MatchController = require(script.Parent.Parent.MatchController)
local EnemyImpacts = require(script.Parent.Parent.Parent.Utils.enemyImpacts)
local healFx = require(script.Parent.Parent.Parent.Utils.healFx)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local EnemiesCore = require(ReplicatedStorage.Shared.Core.EnemiesCore)
local sightCast = require(ReplicatedStorage.GlobalShared.Utils.sightCast)
local EPlaceIds = require(ReplicatedStorage.Types.Enums.EPlaceIds)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)
local TData = require(ReplicatedStorage.Types.TData)

local args = Conch.args
local LocalPlayer = Players.LocalPlayer

local DebugItemsController = {}

local Tune = table.freeze({
	-- The nuke's crowd: how many bodies, from this near the player to this far (more of them near), each put on the
	-- floor found from this far over the player's feet to this far down.
	CROWD = 90,
	CROWD_NEAR = 7,
	CROWD_FAR = 110,
	FLOOR_LOOK_UP = 14,
	FLOOR_SEARCH = 44,
	-- Seconds between one nuke and the next, and between heals: the whole moment and a beat of quiet.
	NUKE_EVERY = 5,
	HEAL_EVERY = 4,
	-- The heal's squad: stand-ins this far ahead of the player, this far apart.
	SQUAD = 3,
	SQUAD_AHEAD = 10,
	SQUAD_SPACING = 7,
})
local SQUAD_COLORS = table.freeze({
	Skin = Color3.fromRGB(245, 205, 48),
	Top = Color3.fromRGB(60, 130, 220),
	Legs = Color3.fromRGB(40, 60, 140),
})

type TBody = {
	Part: BasePart,
	EnemyData: TData.TEnemy,
	Chest: Vector3,
	Aim: vector,
	-- Flat studs from where the nuke goes off.
	Distance: number,
	IsStanding: boolean,
}

local benchKind = Conch.register_type("item_bench", args.enum_new({ "nuke", "heal", "off" }, "item_bench"))

local selfRoot: BasePart? = nil
local benchFolder: Folder? = nil
-- "nuke", "heal", or nil with no bench up.
local kind: string? = nil
local crowd: { TBody } = {}
local squad: { BasePart } = {}
local origin = Vector3.zero
local nextAt = 0
-- os.clock the nuke last went off, for the front.
local blastAt = math.huge

-- ============================== Public API ==============================
function DebugItemsController.TakeDown()
	if benchFolder then benchFolder:Destroy() end
	benchFolder = nil
	kind = nil
	blastAt = math.huge
	table.clear(crowd)
	table.clear(squad)
end

local function newFolder(): Folder
	local folder = Instance.new("Folder")
	folder.Name = "ItemBench"
	folder.Parent = Workspace
	benchFolder = folder
	return folder
end

-- Every enemy type's rig round the player, each stood as the renderer stands one: anchored at the origin, its Root
-- bone carrying the world frame, half a body up because a skinned body deforms about its MeshPart's centre.
function DebugItemsController.PutUpNuke(): number
	DebugItemsController.TakeDown()
	local root = selfRoot
	if not root then return 0 end

	local types = {}
	for _, enemyData in DataCore.Enemies.All do
		if EnemiesCore.HasModel(enemyData) and not enemyData.IsBoss then types[#types + 1] = enemyData end
	end
	if #types == 0 then return 0 end

	local folder = newFolder()
	local random = Random.new()
	origin = root.Position
	local over = Vector3.new(0, Tune.FLOOR_LOOK_UP, 0)
	local down = Vector3.new(0, -Tune.FLOOR_SEARCH, 0)
	for i = 1, Tune.CROWD do
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = Tune.CROWD_NEAR + (Tune.CROWD_FAR - Tune.CROWD_NEAR) * random:NextNumber() ^ 1.6
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local floor = sightCast(origin + out * distance + over, down)
		if not floor then continue end

		local enemyData = types[(i - 1) % #types + 1]
		local feet = floor.Position
		local model = EnemiesCore.GetModel(enemyData):Clone()
		model.Parent = folder
		local part = (model :: any).PrimaryPart :: BasePart
		-- A rig faces its own +Z: toward the player.
		local bone = (part :: any).Root :: Bone
		bone.Transform = CFrame.lookAt(feet, feet + out) * CFrame.new(0, model:GetExtentsSize().Y / 2, 0)
		local aim = EnemiesCore.AimShape(enemyData)
		crowd[#crowd + 1] = {
			Part = part,
			EnemyData = enemyData,
			Chest = feet + Vector3.new(0, aim.x, 0),
			Aim = aim,
			Distance = distance,
			IsStanding = true,
		}
	end

	kind = "nuke"
	nextAt = os.clock() + 1
	return #crowd
end

local function limb(size: Vector3, offset: Vector3, color: Color3, feet: CFrame, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Size = size
	part.CFrame = feet * CFrame.new(offset)
	part.Color = color
	part.Material = Enum.Material.Plastic
	part.Parent = parent
	return part
end

-- A squad of R6-shaped stand-ins ahead of the player; the player's own body is healed by the game.
function DebugItemsController.PutUpHeal(): number
	DebugItemsController.TakeDown()
	local root = selfRoot
	if not root then return 0 end

	local folder = newFolder()
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	local forward = if look.Magnitude > 1e-3 then look.Unit else Vector3.zAxis
	local right = forward:Cross(Vector3.yAxis)
	local feetY = root.Position.Y - root.Size.Y / 2 - 2
	local center = Vector3.new(root.Position.X, feetY, root.Position.Z) + forward * Tune.SQUAD_AHEAD
	for i = 1, Tune.SQUAD do
		local at = center + right * ((i - (Tune.SQUAD + 1) / 2) * Tune.SQUAD_SPACING)
		local feet = CFrame.lookAt(at, at - forward)
		limb(Vector3.new(1, 2, 1), Vector3.new(-0.5, 1, 0), SQUAD_COLORS.Legs, feet, folder)
		limb(Vector3.new(1, 2, 1), Vector3.new(0.5, 1, 0), SQUAD_COLORS.Legs, feet, folder)
		limb(Vector3.new(1, 2, 1), Vector3.new(-1.5, 3, 0), SQUAD_COLORS.Skin, feet, folder)
		limb(Vector3.new(1, 2, 1), Vector3.new(1.5, 3, 0), SQUAD_COLORS.Skin, feet, folder)
		limb(Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 4.6, 0), SQUAD_COLORS.Skin, feet, folder)
		-- Where a character's root is: the heal rides it.
		squad[i] = limb(Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), SQUAD_COLORS.Top, feet, folder)
	end

	kind = "heal"
	nextAt = os.clock() + 1
	return #squad
end

-- ============================== Internals ==============================
local function stepNuke(now: number)
	if now >= nextAt then
		nextAt = now + Tune.NUKE_EVERY
		blastAt = now
		for _, body in crowd do
			body.IsStanding = true
			body.Part.Transparency = 0
		end

		MatchController.OnNukedAll:Fire(LocalPlayer, origin, #crowd)
	end

	-- The server's kill, drawn: everything the front has passed, then whatever is left when it stops.
	local elapsed = now - blastAt
	local reach = if elapsed >= EnemiesCore.NUKE_SECONDS then math.huge else elapsed * EnemiesCore.NUKE_SPEED
	for _, body in crowd do
		if not body.IsStanding or body.Distance > reach then continue end
		body.IsStanding = false
		body.Part.Transparency = 1
		EnemyImpacts.EmitOverkill(body.EnemyData, body.Chest, body.Aim, origin)
	end
end

local function stepHeal(now: number)
	if now < nextAt then return end
	nextAt = now + Tune.HEAL_EVERY
	MatchController.OnHealedAll:Fire(LocalPlayer)
	for _, root in squad do
		healFx.Cast(root, false)
	end
end

local function step()
	if not kind then return end
	local now = os.clock()
	if kind == "nuke" then
		stepNuke(now)
	else
		stepHeal(now)
	end
end

-- ============================== Wiring ==============================
DebugItemsController.OnSelfCharacterAdded = function(character)
	selfRoot = character.HumanoidRootPart
end :: TCharacterEvents.OnCharacterAdded

DebugItemsController.OnSelfCharacterRemoving = function()
	selfRoot = nil
end :: TCharacterEvents.OnCharacterRemoving

DebugItemsController.OnStart = function()
	if not RunService:IsStudio() and not EPlaceIds.IsTest then return end

	Conch.register("itembench", {
		permissions = {},
		description = "Set NUKE ALL off in a crowd round you, or heal a squad beside you, again and again (off takes it down).",
		arguments = function()
			return benchKind("item", "nuke, heal, or off.")
		end,
		callback = function(item: string)
			if item == "off" then
				DebugItemsController.TakeDown()
				Conch.log("normal", "Item bench taken down.")
				return
			end

			local stood = if item == "nuke" then DebugItemsController.PutUpNuke() else DebugItemsController.PutUpHeal()
			Conch.log(
				"normal",
				if stood > 0
					then `Item bench up: {item}, {stood} bodies. 'itembench off' takes it down.`
					else "No character, or no enemy rig to stand."
			)
			local effects = ReplicatedStorage:FindFirstChild("Effects")
			if not effects or not effects:FindFirstChild("NukeFx") then
				Conch.log(
					"warn",
					"NukeFx / HealFx are not in the place: paste Assets/effects/items/item_effects.luau into the command bar."
				)
			end
		end,
	})

	-- After EnemiesController's PreSimulation, which opens the frame's burst budget the bench's bodies draw on.
	RunService.Heartbeat:Connect(step)
end

return Ignis.Register(DebugItemsController)
