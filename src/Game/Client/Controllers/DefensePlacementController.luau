-- Placing a defense (GDD 15, 16): its key or HUD card starts it, a ghost of its footprint follows the aim, a click
-- places it. The server validates everything (DefenseService.Place); the ghost only shows where the request goes.
-- The turn key cannot be a defense key, since those switch to that defense.
--
-- The ghost is a plain transparent part, never a Highlight: those are the enemies' budget (EnemiesCore.MAX_ALIVE).
-- TODO: tint it by whether the spot is valid, once the client bakes the nav grid too.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Network = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Network)
local MatchController = require(script.Parent.MatchController)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local sightCast = require(ReplicatedStorage.Shared.Utils.sightCast)
local TData = require(ReplicatedStorage.Types.TData)

local ServerNetworkDefenses = Network.Server.Defenses
local ClientNetworkDefenses = Network.Client.Defenses

local LocalPlayer = Players.LocalPlayer
local DEFENSES = DataCore.Defenses.ById
local ALL_DEFENSES = DataCore.Defenses.All
local DEFENSE_KEYS = table.freeze({ Enum.KeyCode.E, Enum.KeyCode.R, Enum.KeyCode.T })
local TURN_KEY = Enum.KeyCode.F
local AIM_DISTANCE = 300
local ACTION = "PlaceDefense"
local PLACED_SOUND_GROUP = "Build"
local PLACED_SOUND = "Land"
-- Voices shared by every turret's shots, pooled because a turret fires twice a second and a clone per shot would be
-- two new instances a second for each one. Past this many overlapping, the oldest restarts.
local SHOT_VOICES = 6

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude

local DefensePlacementController = {}

DefensePlacementController.IsPlacing = false
-- The defense being placed, or 0.
DefensePlacementController.PlacingId = 0
-- The bindings, for the HUD's key caps: defenses in DataCore.Defenses.All order (past the last key, card only).
DefensePlacementController.KEYS = DEFENSE_KEYS
DefensePlacementController.TURN_KEY = TURN_KEY
-- The local player's standing defenses per dataId.
DefensePlacementController.Owned = {} :: { [number]: number }

-- Own defense id -> its dataId, so a Removed (which carries only the id) can be counted down.
local ownedIds: { [number]: number } = {}
-- Every standing defense's foot centre, anyone's, for its sounds.
local footCentres: { [number]: Vector3 } = {}
local shotSource = SoundsCore.FindNamed("Weapons", "Pistol")
local shotPool = if shotSource then SoundsCore.CreatePool(shotSource, SHOT_VOICES) else nil

local placingData: TData.TDefense? = nil
local quarterTurns = 0
local ghost: Part? = nil
local connection: RBXScriptConnection? = nil

local function aimPoint(): Vector3?
	local camera = Workspace.CurrentCamera
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	aimParams.FilterDescendantsInstances = { LocalPlayer.Character :: any, ghost :: any }
	local hit = sightCast(ray.Origin, ray.Direction * AIM_DISTANCE, aimParams)
	return if hit then hit.Position else nil
end

function DefensePlacementController.Cancel()
	DefensePlacementController.IsPlacing = false
	DefensePlacementController.PlacingId = 0
	placingData = nil
	if ghost then ghost:Destroy() end
	ghost = nil
	if connection then connection:Disconnect() end
	connection = nil
	ContextActionService:UnbindAction(ACTION)
end

local function onAction(_, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
	local data = placingData
	if not data then return Enum.ContextActionResult.Pass end
	if input.KeyCode == TURN_KEY then
		quarterTurns = (quarterTurns + 1) % 4
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		local point = aimPoint()
		if point then
			ClientNetworkDefenses.Place.Fire(data.Id, vector.create(point.X, point.Y, point.Z), quarterTurns)
		end
		DefensePlacementController.Cancel()
	else
		DefensePlacementController.Cancel()
	end

	return Enum.ContextActionResult.Sink
end

-- Starts placing `dataId`. Pressing it again while placing cancels.
function DefensePlacementController.Begin(dataId: number)
	local data = DEFENSES[dataId]
	if not data then return end
	local wasSame = placingData == data
	DefensePlacementController.Cancel()
	if wasSame then return end

	-- The server would refuse it, so a ghost would only promise a place that never comes.
	if MatchController.Gold < data.Cost then return end
	if (DefensePlacementController.Owned[dataId] or 0) >= data.MaxPerPlayer then return end

	placingData = data
	DefensePlacementController.IsPlacing = true
	DefensePlacementController.PlacingId = dataId
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 0.6
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(120, 220, 255)
	part.Size = Vector3.new(data.Footprint.X, 0.4, data.Footprint.Y)
	part.Parent = Workspace
	ghost = part

	-- Above the combat bindings, so the placing click does not also swing.
	ContextActionService:BindActionAtPriority(
		ACTION,
		onAction,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.UserInputType.MouseButton1,
		Enum.UserInputType.MouseButton2,
		TURN_KEY,
		Enum.KeyCode.Escape
	)
	connection = RunService.PreRender:Connect(function()
		local point = aimPoint()
		if not point or not ghost then return end
		ghost.CFrame = CFrame.new(point + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, quarterTurns * math.pi / 2, 0)
	end)
end

ServerNetworkDefenses.Placed.On(function(id: number, dataId: number, owner: Player, footCentre: Vector3)
	footCentres[id] = footCentre
	SoundsCore.PlayWorldRandom(PLACED_SOUND_GROUP, PLACED_SOUND, footCentre)
	if owner ~= LocalPlayer then return end
	ownedIds[id] = dataId
	DefensePlacementController.Owned[dataId] = (DefensePlacementController.Owned[dataId] or 0) + 1
end)

ServerNetworkDefenses.Removed.On(function(id: number)
	footCentres[id] = nil
	local dataId = ownedIds[id]
	if not dataId then return end
	ownedIds[id] = nil
	DefensePlacementController.Owned[dataId] = math.max((DefensePlacementController.Owned[dataId] or 1) - 1, 0)
end)

ServerNetworkDefenses.Shot.On(function(id: number, _)
	local footCentre = footCentres[id]
	if footCentre and shotPool then SoundsCore.PlayPooled(shotPool, footCentre) end
end)

DefensePlacementController.OnStart = function()
	for index, data in ALL_DEFENSES do
		local key = DEFENSE_KEYS[index]
		if not key then break end
		ContextActionService:BindAction(`Defense{index}`, function(_, state)
			if state == Enum.UserInputState.Begin then DefensePlacementController.Begin(data.Id) end
			return Enum.ContextActionResult.Sink
		end, false, key)
	end
end

return Ignis.Register(DefensePlacementController)
