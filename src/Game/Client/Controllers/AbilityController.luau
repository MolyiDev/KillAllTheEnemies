-- The local player's class: its ability keys, what the HUD shows of them (cooldowns, the ultimate's meter), and
-- everything any player's abilities look like (Utils/decoyFx, foamFx, orbitalFx). It tells the server only a slot and
-- where it aimed (Abilities.Cast); what happens is AbilityService's. The caster's own spray is drawn ahead of the
-- server's word, from their own aim, so the hands answer at once.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Network = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Network)
local CameraController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.CameraController)
local BodyPoseController = require(script.Parent.BodyPoseController)
local CharacterController = require(script.Parent.CharacterController)
local EnemiesController = require(script.Parent.EnemiesController)
local MatchController = require(script.Parent.MatchController)
local TweensController = require(script.Parent.TweensController)
local WeaponController = require(script.Parent.WeaponController)
local burstLayers = require(script.Parent.Parent.Utils.burstLayers)
local decoyFx = require(script.Parent.Parent.Utils.decoyFx)
local foamFx = require(script.Parent.Parent.Utils.foamFx)
local orbitalFx = require(script.Parent.Parent.Utils.orbitalFx)
local CharacterCore = require(ReplicatedStorage.GlobalShared.Core.CharacterCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local AbilitiesCore = require(ReplicatedStorage.Shared.Core.AbilitiesCore)
local EnemiesCore = require(ReplicatedStorage.Shared.Core.EnemiesCore)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local EnemyWorldRef = require(ReplicatedStorage.GlobalShared.ECS.References.EnemyWorldRef)
local EnemyWorld = require(ReplicatedStorage.GlobalShared.ECS.Worlds.EnemyWorld)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local sightCast = require(ReplicatedStorage.GlobalShared.Utils.sightCast)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)
local TData = require(ReplicatedStorage.Types.TData)

local ServerNetworkAbilities = Network.Server.Abilities
local ClientNetworkAbilities = Network.Client.Abilities

local Tune = table.freeze({
	AIM_RANGE = 400,
	-- The sounds, under ReplicatedStorage.Sounds.Abilities: each one clip or a bag of takes, silent until it is there.
	SOUND_GROUP = "Abilities",
	-- A foamed body's tint (its own Highlight: EnemiesController.SetStiff).
	FOAM_COLOR = Color3.fromRGB(247, 236, 206),
	-- What a cast does to the caster's view and arms: the camera's kick (studs a second, on the weapon's spring) and
	-- the arms' jolt (in shots).
	DECOY_RECOIL = 9,
	DECOY_POSE_KICK = 1.6,
	FOAM_RECOIL = 16,
	FOAM_POSE_KICK = 2.2,
	FOAM_SHAKE = 1.4,
	FOAM_SHAKE_SECONDS = 0.4,
	-- A doll bursting shakes every view within POP_REACH of it, hardest at POP_NEAR or closer.
	POP_SHAKE = 2.6,
	POP_SHAKE_SECONDS = 0.35,
	POP_NEAR = 14,
	POP_REACH = 90,
	-- The beam landing shakes every view within SLAM_REACH of it, hardest at SLAM_NEAR or closer, and the caster's
	-- breathes out; burning, it rumbles the views near it.
	SLAM_SHAKE = 5,
	SLAM_SHAKE_SECONDS = 0.6,
	SLAM_NEAR = 30,
	SLAM_REACH = 260,
	SLAM_FOV_PUNCH = 9,
	SLAM_FOV_RETURN = 0.7,
	RUMBLE_SHAKE = 0.9,
	RUMBLE_SECONDS = 0.3,
	RUMBLE_REACH = 90,
	SHAKE_ROUGHNESS = 0.35,
})

-- One slot as the HUD draws it.
export type TSlot = {
	Ability: TData.TAbility,
	-- When its cooldown is over (TimeCore.GameClock), and the last time it was used and the last time a press was
	-- refused (os.clock, the HUD's gestures).
	ReadyAt: number,
	UsedAt: number,
	DeniedAt: number,
}

-- A beam as this client keeps it: when it lands and burns out, whether it has shaken the view for landing, and when it
-- next rumbles. Burning, its loop rides an Attachment at its foot.
type TBeam = {
	FireAt: number,
	EndsAt: number,
	HasLanded: boolean,
	NextRumbleAt: number,
	Burn: Attachment?,
	BurnSound: Sound?,
}

local AbilityController = {}

-- The abilities' keys by slot, and the ultimate's.
AbilityController.KEYS = table.freeze({ Enum.KeyCode.Q, Enum.KeyCode.E })
AbilityController.ULTIMATE_KEY = Enum.KeyCode.G
-- The class the server has this player on, its slots (the ultimate last) and the ultimate's meter.
AbilityController.Class = AbilitiesCore.ClassOf(nil)
AbilityController.Slots = {} :: { TSlot }
AbilityController.Charge = 0
-- os.clock the meter last filled, and the GameClock until which this player's own beam is out (0 for none) and how
-- long it lasts.
AbilityController.ChargedAt = -math.huge
AbilityController.BeamUntil = 0
AbilityController.BeamSeconds = 0

local selfCharacter: Model? = nil
local selfRoot: BasePart? = nil
local selfHumanoid: Humanoid? = nil
local selfId = 0
-- Foamed bodies this client was shown: the GameClock each is let go.
local foamedUntil: { [number]: number } = {}
local beams: { [number]: TBeam } = {}
-- The match is stopped: the beams' loops are paused.
local isFrozen = false

local function setClass(class: TData.TClass)
	if AbilityController.Class == class and #AbilityController.Slots > 0 then return end
	AbilityController.Class = class
	local slots = table.create(#class.Abilities + 1)
	for slot = 1, #class.Abilities + 1 do
		slots[slot] = {
			Ability = AbilitiesCore.AbilityAt(class, slot) :: TData.TAbility,
			ReadyAt = 0,
			UsedAt = -math.huge,
			DeniedAt = -math.huge,
		}
	end

	AbilityController.Slots = slots
end

local function playSound(name: string, position: Vector3)
	SoundsCore.PlayWorldNamed(Tune.SOUND_GROUP, name, position)
end

-- What the crosshair is over on the arena (never an enemy: a doll and a beam come down on the floor), or the floor's
-- height under the ray where it meets nothing.
local function aimPoint(root: BasePart): Vector3
	local eye, direction = WeaponController.PointerRay()
	local result = sightCast(eye, direction * Tune.AIM_RANGE)
	if result then return result.Position end

	local feetY = root.Position.Y - 3
	if direction.Y < -0.01 then return eye + direction * math.min((feetY - eye.Y) / direction.Y, Tune.AIM_RANGE) end
	local out = eye + direction * Tune.AIM_RANGE
	return Vector3.new(out.X, feetY, out.Z)
end

-- What the caster sees and feels the frame they press, ahead of the server.
local function castAhead(ability: TData.TAbility, root: BasePart, aim: Vector3)
	CameraController.SetRecoilSpring(18, 0.6, 0.25)
	if ability.Kind == "Decoy" then
		CameraController.AddRecoil(Tune.DECOY_RECOIL, 0)
		BodyPoseController.Kick(selfCharacter, Tune.DECOY_POSE_KICK)
		playSound("DecoyThrow", root.Position)
	elseif ability.Kind == "FoamCannon" then
		local flat = Vector3.new(aim.X - root.Position.X, 0, aim.Z - root.Position.Z)
		if flat.Magnitude > 0.5 then foamFx.Spray(root, flat.Unit) end
		CameraController.AddRecoil(Tune.FOAM_RECOIL, 0)
		CameraController.Shake(Tune.FOAM_SHAKE, Tune.SHAKE_ROUGHNESS, Tune.FOAM_SHAKE_SECONDS)
		BodyPoseController.Kick(selfCharacter, Tune.FOAM_POSE_KICK)
		playSound("FoamSpray", root.Position)
	else
		playSound("OrbitalCall", root.Position)
	end
end

-- Uses the ability in `slot` where the crosshair is. Refused here, for the HUD to show it, when the match is stopped,
-- the body is down, a beam is already out, the slot is not ready or its Gold is short; the server checks them all
-- again.
function AbilityController.Cast(slot: number)
	local state = AbilityController.Slots[slot]
	if not state then return end
	local ability = state.Ability
	local root, humanoid = selfRoot, selfHumanoid
	local now = os.clock()
	local gameNow = TimeCore.GameClock
	local isStanding = root ~= nil and humanoid ~= nil and humanoid.Health > 0 and selfId ~= 0
	local isReady = if ability.Cooldown
		then gameNow >= state.ReadyAt
		else AbilityController.Charge >= (ability.ChargeKills or math.huge)
	local canPay = MatchController.Gold >= (ability.Cost or 0)
	if TimeCore.IsPaused or not isStanding or not isReady or not canPay or gameNow < AbilityController.BeamUntil then
		state.DeniedAt = now
		return
	end

	local aim = aimPoint(root :: BasePart)
	ClientNetworkAbilities.Cast.Fire(slot, aim)
	state.UsedAt = now
	state.ReadyAt = gameNow + (ability.Cooldown or 0)
	castAhead(ability, root :: BasePart, aim)
end

local function modelOf(characterId: number): Model?
	local entity = CharacterCore.GetCharacterByInstanceId(characterId)
	return if entity then World:get(entity, Components.Model) else nil
end

local function shakeBy(position: Vector3, magnitude: number, seconds: number, near: number, reach: number)
	local distance = (Workspace.CurrentCamera.CFrame.Position - position).Magnitude
	local share = 1 - math.clamp((distance - near) / (reach - near), 0, 1)
	if share <= 0 then return end
	CameraController.Shake(magnitude * share, Tune.SHAKE_ROUGHNESS, seconds)
end

local function endBeam(characterId: number)
	local beam = beams[characterId]
	if not beam then return end
	beams[characterId] = nil
	if beam.Burn then beam.Burn:Destroy() end
	orbitalFx.End(characterId)
	local at = orbitalFx.GroundOf(characterId)
	if at then playSound("OrbitalEnd", at) end
	if characterId ~= selfId then return end
	AbilityController.BeamUntil = 0
end

-- The beam's loop (OrbitalBurn, Looped in the tree) on an Attachment that follows its foot; destroying it stops it.
local function startBurn(at: Vector3): (Attachment?, Sound?)
	local source = SoundsCore.FindNamed(Tune.SOUND_GROUP, "OrbitalBurn")
	if not source then return nil, nil end

	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = at
	anchor.Parent = Workspace.Terrain

	local sound = source:Clone()
	sound.Parent = anchor
	sound:Play()
	-- A clock eased almost to a stop still runs: a beam can land the frame the match is already stopped.
	if isFrozen then sound:Pause() end

	return anchor, sound
end

local function stepBeams(now: number)
	for characterId, beam in beams do
		local at = orbitalFx.GroundOf(characterId)
		if not at or now < beam.FireAt then continue end

		local burn = beam.Burn
		if burn then burn.WorldPosition = at end

		if not beam.HasLanded then
			beam.HasLanded = true
			playSound("OrbitalFire", at)
			playSound("OrbitalBurnStart", at)
			beam.Burn, beam.BurnSound = startBurn(at)
			shakeBy(at, Tune.SLAM_SHAKE, Tune.SLAM_SHAKE_SECONDS, Tune.SLAM_NEAR, Tune.SLAM_REACH)
			if characterId == selfId then TweensController.PunchFov(Tune.SLAM_FOV_PUNCH, Tune.SLAM_FOV_RETURN) end
		elseif now >= beam.NextRumbleAt then
			beam.NextRumbleAt = now + Tune.RUMBLE_SECONDS * 0.5
			shakeBy(at, Tune.RUMBLE_SHAKE, Tune.RUMBLE_SECONDS, Tune.SLAM_NEAR, Tune.RUMBLE_REACH)
		end

		-- The server's end is the word; this is for one that never came.
		if now >= beam.EndsAt + 1 then endBeam(characterId) end
	end
end

-- The foamed bodies: each one's blocks follow it while it is in view, and fall off it when the foam lets go. A volley
-- lets go on one frame and is heard once, where its first body was.
local function stepFoamed(now: number)
	local heardAt: Vector3? = nil
	for instanceId, untilAt in foamedUntil do
		local ground = EnemiesController.GetCFrame(instanceId)
		if now < untilAt then
			if ground then foamFx.Follow(instanceId, ground) end
			continue
		end

		foamedUntil[instanceId] = nil
		EnemiesController.SetStiff(instanceId, nil)
		foamFx.Crumble(instanceId)
		if ground then heardAt = heardAt or ground.Position end
	end

	if heardAt then playSound("FoamCrumble", heardAt) end
end

-- On the match's clock, as the server's are: a pick's hold or the console's time scale slows them with everything else.
local function step(dt: number)
	local now = TimeCore.GameClock
	local gameDt = TimeCore.GetDeltaTime(dt)
	stepFoamed(now)
	stepBeams(now)
	decoyFx.Step(gameDt)
	foamFx.Step()
	orbitalFx.Step(gameDt)
end

ServerNetworkAbilities.State.On(function(classId: number, charge: number)
	-- Sent as each character is ready, which is once every client knows its id: this is where the local one is read.
	selfId = CharacterController.GetLocalCharacterId() or 0
	setClass(AbilitiesCore.ClassOf(classId))
	local needed = AbilityController.Class.Ultimate.ChargeKills or math.huge
	if charge >= needed and AbilityController.Charge < needed then AbilityController.ChargedAt = os.clock() end
	AbilityController.Charge = charge
end)

ServerNetworkAbilities.DecoyThrown.On(
	function(decoyId: number, throwerId: number, feet: Vector3, flightSeconds: number, lifeSeconds: number)
		local model = modelOf(throwerId)
		local hand = if model then model:FindFirstChild("Right Arm") else nil
		local from = if hand and hand:IsA("BasePart")
			then hand.Position
			elseif model then model:GetPivot().Position
			else feet + Vector3.new(0, 3, 0)
		decoyFx.Throw(decoyId, model, from, feet, flightSeconds, lifeSeconds)
		if throwerId ~= selfId then playSound("DecoyThrow", from) end
	end
)

ServerNetworkAbilities.DecoyHit.On(function(decoyId: number)
	decoyFx.Squeak(decoyId)
end)

ServerNetworkAbilities.DecoyPopped.On(function(decoyId: number)
	local blastAt = decoyFx.Pop(decoyId)
	if blastAt then shakeBy(blastAt, Tune.POP_SHAKE, Tune.POP_SHAKE_SECONDS, Tune.POP_NEAR, Tune.POP_REACH) end
end)

ServerNetworkAbilities.FoamSprayed.On(function(casterId: number, aim: Vector3)
	local model = modelOf(casterId)
	local root = if model then model:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then return end
	local flat = Vector3.new(aim.X - root.Position.X, 0, aim.Z - root.Position.Z)
	if flat.Magnitude < 0.5 then return end
	foamFx.Spray(root, flat.Unit)
	playSound("FoamSpray", root.Position)
end)

-- Only the bodies this client holds a row for; the rest it was never shown.
ServerNetworkAbilities.Foamed.On(function(instanceIds: { number }, seconds: number)
	local untilAt = TimeCore.GameClock + seconds
	local heardAt: Vector3? = nil
	for _, instanceId in instanceIds do
		local entity = EnemyWorldRef:Search(instanceId)
		local enemyData = if entity then EnemyWorld:get(entity, Components.Data) else nil
		if not enemyData then continue end
		foamedUntil[instanceId] = untilAt
		EnemiesController.SetStiff(instanceId, Tune.FOAM_COLOR)
		local ground = EnemiesController.GetCFrame(instanceId)
		if not ground then continue end
		foamFx.Encase(instanceId, ground, EnemiesCore.AimShape(enemyData))
		heardAt = heardAt or ground.Position
	end

	if heardAt then playSound("FoamSet", heardAt) end
end)

ServerNetworkAbilities.OrbitalCalled.On(
	function(casterId: number, position: Vector3, targetSeconds: number, burnSeconds: number)
		local now = TimeCore.GameClock
		orbitalFx.Call(casterId, position, targetSeconds, burnSeconds)
		beams[casterId] = {
			FireAt = now + targetSeconds,
			EndsAt = now + targetSeconds + burnSeconds,
			HasLanded = false,
			NextRumbleAt = 0,
		}
		playSound("OrbitalMark", position)
		if casterId ~= selfId then return end
		AbilityController.BeamUntil = now + targetSeconds + burnSeconds
		AbilityController.BeamSeconds = targetSeconds + burnSeconds
	end
)

ServerNetworkAbilities.OrbitalMoved.On(orbitalFx.Aim)

ServerNetworkAbilities.OrbitalEnded.On(endBeam)

-- What the clock does not hold by itself: the particles already thrown, and the beams' loops (paused, never slowed).
TimeCore.OnTimeScaleChange:Connect(function(scale: number)
	burstLayers.SetTimeScale(scale)
	if TimeCore.IsPaused == isFrozen then return end
	isFrozen = TimeCore.IsPaused
	for _, beam in beams do
		local sound = beam.BurnSound
		if not sound then continue end
		if isFrozen then
			sound:Pause()
		else
			sound:Resume()
		end
	end
end)

-- A body that dies in its foam throws its blocks (its own burst is EnemiesController's, which breaks it apart).
EnemiesController.OnEnemyKilled:Connect(function(instanceId: number, _, _, _, at: Vector3)
	if not foamedUntil[instanceId] then return end
	foamedUntil[instanceId] = nil
	foamFx.Shatter(instanceId)
	playSound("FoamShatter", at)
end)

AbilityController.OnSelfCharacterAdded = function(character)
	selfCharacter = character
	selfRoot = character.HumanoidRootPart
	selfHumanoid = character.Humanoid
	selfId = 0
end :: TCharacterEvents.OnCharacterAdded

AbilityController.OnSelfCharacterRemoving = function()
	if selfId ~= 0 then endBeam(selfId) end
	selfCharacter = nil
	selfRoot = nil
	selfHumanoid = nil
	selfId = 0
end :: TCharacterEvents.OnCharacterRemoving

AbilityController.OnStart = function()
	setClass(AbilityController.Class)
	for slot, key in AbilityController.KEYS do
		ContextActionService:BindAction(`Ability{slot}`, function(_, state)
			if state == Enum.UserInputState.Begin then AbilityController.Cast(slot) end
			return Enum.ContextActionResult.Sink
		end, false, key)
	end

	ContextActionService:BindAction("Ultimate", function(_, state)
		if state == Enum.UserInputState.Begin then
			AbilityController.Cast(AbilitiesCore.UltimateSlot(AbilityController.Class))
		end
		return Enum.ContextActionResult.Sink
	end, false, AbilityController.ULTIMATE_KEY)

	-- After WeaponController's PreRender, so the aim is the view as shown.
	RunService.PreRender:Connect(step)
end

return Ignis.Register(AbilityController)
