-- Studio and test places only: the ground-warning bench (VFX.md section 1). The console's `telebench` stands every
-- warning shape in rows in front of the player, looping its wind-up and hit on the real TelegraphController, with one
-- circle taken back mid-wind-up the way a killed exploder's is. Run it beside a deck or a stair to see the layers.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Conch = require(ReplicatedStorage.Packages.conch)
local TelegraphController = require(script.Parent.Parent.TelegraphController)
local ArenaCore = require(ReplicatedStorage.Shared.Core.ArenaCore)
local ETelegraphs = require(ReplicatedStorage.Types.Enums.ETelegraphs)
local EPlaceIds = require(ReplicatedStorage.Types.Enums.EPlaceIds)
local TCharacter = require(ReplicatedStorage.Types.TCharacter)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)

local DebugTelegraphController = {}

-- Far above the server's u16 ids.
local FIRST_ID = 70000
local CYCLE_SECONDS = 3.4
local WINDUP_SECONDS = 1.4
local CANCEL_AT_SECONDS = 0.6
-- Each stand: studs ahead and to the right of the player, the shape (facing the player), whether it is taken back, and
-- whether a boss cast it.
local STANDS = table.freeze({
	{ ahead = 24, right = -33, kind = ETelegraphs.Circle, size = 8, width = 0 },
	{ ahead = 24, right = -11, kind = ETelegraphs.Cone, size = 12, width = 60 },
	{ ahead = 24, right = 11, kind = ETelegraphs.Cone, size = 12, width = 90 },
	{ ahead = 24, right = 33, kind = ETelegraphs.Cone, size = 12, width = 120 },
	{ ahead = 58, right = -30, kind = ETelegraphs.Circle, size = 18, width = 0 },
	{ ahead = 68, right = 0, kind = ETelegraphs.Line, size = 22, width = 5 },
	{ ahead = 58, right = 30, kind = ETelegraphs.Ring, size = 16, width = 0, speed = 18, isBoss = true },
	{ ahead = 58, right = 55, kind = ETelegraphs.Circle, size = 8, width = 0, isCancelled = true },
	{ ahead = 92, right = 0, kind = ETelegraphs.Circle, size = 12, width = 0, isBoss = true },
})

local selfRoot: BasePart? = nil
local selfHumanoid: Humanoid? = nil
-- The bench's frame, fixed when it is put up; nil while it is down.
local origin: CFrame? = nil
local cycleElapsed = 0
local isCancelSent = false

function DebugTelegraphController.PutUp()
	local root, humanoid = selfRoot, selfHumanoid
	if not root or not humanoid then return end

	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z).Unit
	local feet = root.Position - Vector3.new(0, root.Size.Y / 2 + humanoid.HipHeight, 0)
	origin = CFrame.lookAt(feet, feet + flat)
	cycleElapsed = CYCLE_SECONDS
end

function DebugTelegraphController.TakeDown()
	origin = nil
	for index in STANDS do
		TelegraphController.End(FIRST_ID + index)
	end
end

local function showAll(frame: CFrame)
	for index, stand in STANDS do
		local at = frame * Vector3.new(stand.right, 0, -stand.ahead)
		local floorY = ArenaCore.GetFloorY(at.X, at.Z, at.Y + 3) or at.Y
		local center = Vector3.new(at.X, floorY, at.Z)
		local toPlayer = frame.Position - center
		local yaw = math.atan2(toPlayer.X, toPlayer.Z)
		local id = FIRST_ID + index
		local speed = stand.speed or 0
		local isBoss = stand.isBoss == true
		TelegraphController.Show(
			id,
			stand.kind,
			center,
			yaw,
			stand.size,
			stand.width,
			WINDUP_SECONDS,
			speed,
			isBoss,
			false
		)
	end
end

local function step(dt: number)
	local frame = origin
	if not frame then return end

	cycleElapsed += dt
	if cycleElapsed >= CYCLE_SECONDS then
		cycleElapsed = 0
		isCancelSent = false
		showAll(frame)
	end

	if isCancelSent or cycleElapsed < CANCEL_AT_SECONDS then return end
	isCancelSent = true
	for index, stand in STANDS do
		if stand.isCancelled then TelegraphController.End(FIRST_ID + index) end
	end
end

DebugTelegraphController.OnSelfCharacterAdded = function(character: TCharacter.TCharacter)
	selfRoot = character.HumanoidRootPart
	selfHumanoid = character.Humanoid
end :: TCharacterEvents.OnCharacterAdded

DebugTelegraphController.OnSelfCharacterRemoving = function()
	selfRoot = nil
	selfHumanoid = nil
end :: TCharacterEvents.OnCharacterRemoving

DebugTelegraphController.OnStart = function()
	if not RunService:IsStudio() and not EPlaceIds.IsTest then return end

	Conch.register("telebench", {
		permissions = {},
		description = "Stand every ground-warning shape in front of you, looping (run again to take it down).",
		arguments = function() end,
		callback = function()
			if origin then
				DebugTelegraphController.TakeDown()
				Conch.log("normal", "Telegraph bench taken down.")
				return
			end

			DebugTelegraphController.PutUp()
			Conch.log("normal", if origin then "Telegraph bench up." else "No character to stand it by.")
		end,
	})

	RunService.Heartbeat:Connect(step)
end

return Ignis.Register(DebugTelegraphController)
