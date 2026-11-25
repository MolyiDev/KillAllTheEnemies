-- A boss's body in the fight: each of its moves (Bosses.Move) played as its clip at the clip's own timing, its runs,
-- turns and dive drawn exactly where the server moves it (EnemiesController.Drive), and the weight of a body this big:
-- every footfall felt, its bite, tail, charge, spines, dive, roar, the shield its guards hold up and the beams that tie
-- them to it, and its fall. This says when and where off the body's own bones; Utils/trexFx draws it, and the shake is
-- this module's. Its ground warnings are TelegraphController's, like every enemy's. Its timing runs on
-- TimeCore.EnemyClock, so a freeze or a pause holds it with the fight.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Network = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Network)
local BossIntroController = require(script.Parent.BossIntroController)
local EnemiesController = require(script.Parent.EnemiesController)
-- Through PlayerScripts, the copy that runs (see HudController).
local CameraController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.CameraController)
local EnemyImpacts = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Utils.enemyImpacts)
local trexFx = require(script.Parent.Parent.Utils.trexFx)
local trexSounds = require(script.Parent.Parent.Utils.trexSounds)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local BossesCore = require(ReplicatedStorage.Shared.Core.BossesCore)
local EnemiesCore = require(ReplicatedStorage.Shared.Core.EnemiesCore)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)
local EBossMoves = require(ReplicatedStorage.Types.Enums.EBossMoves)
local TCharacter = require(ReplicatedStorage.Types.TCharacter)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)
local TData = require(ReplicatedStorage.Types.TData)

local ServerNetworkBosses = Network.Server.Bosses

local ENEMIES = DataCore.Enemies.ById
local UP = Vector3.yAxis

-- Its glow: the T-Rex's neon, the shield and the beams, its spines and its crack.
local GREEN = Color3.fromRGB(90, 255, 140)
local PALE_GREEN = Color3.fromRGB(205, 255, 195)

local Tune = table.freeze({
	-- An impact is felt in full this close to the player's body (the camera's, with none), falling off steeply (the
	-- square of what is left of the way) to nothing at FAR: a blow at its feet lands hard, one across the map barely.
	NEAR = 14,
	FAR = 120,
	-- Each impact's shake: (magnitude, seconds[, kick]), about three swings each (CameraController.Shake's 2.6-5.5
	-- band). A kick is the view knocked down and aside in peak studs, springing back, against the guns' 0.12-0.35.
	STEP = { 0.55, 0.3 },
	RUN_STEP = { 0.9, 0.3, 0.06 },
	BITE = { 1.6, 0.35, 0.3 },
	SWEEP = { 1.3, 0.4, 0.25 },
	STOMP = { 2.6, 0.45, 0.35 },
	-- The Quake's beats grow to its last (QUAKE_SIZES, trexFx.Stomp's size).
	QUAKE = { { 1.9, 0.4, 0.22 }, { 2.8, 0.45, 0.36 }, { 4.4, 0.6, 0.62 } },
	QUAKE_SIZES = { 0.75, 1.05, 1.5 },
	SKID = { 0.8, 0.6, 0.12 },
	CATCH = { 1.6, 0.35, 0.22 },
	SHAKE_LOOSE = { 0.5, 0.25 },
	ROAR = { 3.4, 1.4, 0.4 },
	RISE = { 4.6, 0.6, 0.7 },
	FALL = { 5.5, 0.7, 0.8 },
	RUN_OVER = { 4, 0.5 },
	-- A spine sticking in the floor, and a wave rolling along it going under the player (times its strength).
	SPINE_LAND = { 1, 0.25, 0.12 },
	WAVE_PASS = { 1.8, 0.35, 0.28 },
	-- Three swings over a shake's length.
	SWINGS = 3,
	-- The kick's spring: heavier and slower than a gun's, the ground jolting rather than the hands.
	KICK_FREQUENCY = 14,
	KICK_DAMPING = 0.5,
	KICK_ROLL = 0.35,
	KICK_SIDE_SHARE = 0.6,
	-- The floor heaving under it as it sinks, each heave this big (trexFx.Sink's size).
	SINK_SIZES = { 0.6, 0.8, 1 },
	-- Where it goes into the floor: DiveSink throws it forward, and its body crosses the floor 10-15 rig units ahead
	-- of Root (snout at 0.65 s, chest at 1.1 s), times the model's 1.25.
	SINK_AHEAD = 15,
	-- The maw closes round the snout's tip, this far ahead of Root and this high: its U, wider than the head, runs from
	-- 2.6 behind this point to 4.5 past it, so at the bite the snout's 26.9-stud reach sits inside its back teeth.
	MAW_AHEAD = 25,
	MAW_HEIGHT = 5,
	-- How hard a footfall lands (trexFx.Footfall's strength): walking, running, pawing the floor, catching itself.
	STEP_STRENGTH = 1,
	RUN_STRENGTH = 1.5,
	PAW_STRENGTH = 0.8,
	CATCH_STRENGTH = 1.3,
	-- A quick turn onto an attack's aim, drawn before the clip leans the body.
	AIM_TURN = 0.22,
	-- Under the floor it is drawn this far down, out of sight.
	UNDER_DEPTH = 60,
	-- Off its back: this high over Root and this far behind the chest.
	SPINE_FROM = Vector3.new(0, 13.75, -2.5),
	-- The volley's launch: this far over the chest bone.
	LAUNCH_LIFT = 3,
	-- The crack: a glowing step every CRACK_STEP studs, jittered this far to the sides.
	CRACK_STEP = 1.6,
	CRACK_JITTER = 0.8,
	-- A crack is heard about this often along the line (as it was picked), not on every step drawn: at the dive's
	-- speed the steps come 28 a second.
	CRACK_SOUND_SECONDS = 0.39,
	-- The tail's arc is drawn from this long before the sweep's blow for this long (times the tempo).
	SWEEP_LEAD = 0.45,
	SWEEP_SECONDS = 0.85,
	-- Its snort comes out this far ahead of the head bone and this far under it.
	NOSE_AHEAD = 3,
	NOSE_DOWN = 0.5,
	-- The roar's breath and rings pour out for this long, out of a mouth this far ahead of the jaw bone.
	ROAR_SECONDS = 1.2,
	MOUTH_AHEAD = 2,
	-- Its bones knock back together at these moments of the Reassemble clip.
	RATTLES = { 0.1, 0.5, 0.9 },
	-- Its soul leaves the pile for this long after the fall.
	SOUL_SECONDS = 3.5,
	-- The shield: a bubble round the body (its middle this high, this far forward of Root), breathing, swelling a little
	-- on each blow it takes.
	SHIELD_SIZE = 42.5,
	SHIELD_CENTER = Vector3.new(0, 7.5, 2.5),
	SHIELD_TRANSPARENCY = 0.55,
	SHIELD_BREATHE = 0.04,
	SHIELD_HIT_SWELL = 0.06,
	SHIELD_HIT_SECONDS = 0.18,
	SHIELD_FADE = 0.4,
	-- The shield's hit sound plays at most this often: a fast gun turns several blows a second, and each take rings for
	-- most of one.
	SHIELD_HIT_SOUND_GAP = 0.15,
	-- The beams from each guard's chest to the boss's: thin at the guard, wider at the boss, their width shivering
	-- this much at this rate.
	BEAM_WIDTH = 0.9,
	BEAM_SHIVER = 0.3,
	BEAM_SHIVER_RATE = 9,
	GUARD_CHEST = 3.5,
	BOSS_CHEST = 8.75,
	-- Its head this high over its root, for a voice while the rig is missing.
	HEAD_HEIGHT = 8,
	-- The roar's ground wave runs out this far; the Quake's is this much thicker than a plain wave.
	ROAR_REACH = 30,
	QUAKE_WAVE = 1.4,
})

type TBoss = {
	InstanceId: number,
	Data: TData.TEnemy,
	Kit: TData.TEnemyBoss,
	-- Effects due on the enemy clock, in order.
	Timeline: { { At: number, Run: () -> () } },
	-- Last place each step clip was read at, to see a footfall pass.
	StepClock: { [string]: number },
	Shield: BasePart?,
	ShieldAlpha: number,
	ShieldHitAt: number,
	ShieldSoundAt: number,
	ShieldTarget: boolean,
	-- The floor under the bubble's middle, looked up once as it rises.
	ShieldFloor: Vector3?,
	-- Each guard's beam, its own phase (so beams do not pulse together) and the motes it owes.
	Beams: { [number]: { Beam: Beam, From: Attachment, Phase: number, Owed: number } },
	Anchor: Attachment?,
	Guards: { number },
	LastCFrame: CFrame?,
}

local BossController = {}

-- (bossInstanceId, guardsStanding, guardsRaised), for the boss bar's marks.
BossController.OnShield = Signal.new()

local bosses: { [number]: TBoss } = {}
-- Effects due on the game clock, for a boss already gone (its fall).
local later: { { At: number, Run: () -> () } } = {}
local bones: { [Model]: { [string]: Bone } } = {}
-- The clock trexFx runs on: the fight's, or real time while the intro holds the match (its effects play through it).
local fxClock = 0
local lastEnemyClock = 0
local selfRoot: BasePart? = nil
local selfHumanoid: Humanoid? = nil

local KICK_PEAK_PER_IMPULSE = CameraController.RecoilPeakPerImpulse(Tune.KICK_FREQUENCY, Tune.KICK_DAMPING)

-- ============================== Helpers ==============================

-- How much of an impact at `at` reaches the player: 1 at their feet, nothing past FAR.
local function felt(at: Vector3): number
	local root = selfRoot
	local from = if root then root.Position else Workspace.CurrentCamera.CFrame.Position
	local distance = (from - at).Magnitude
	if distance <= Tune.NEAR then return 1 end
	local left = 1 - (distance - Tune.NEAR) / (Tune.FAR - Tune.NEAR)
	return if left > 0 then left * left else 0
end

-- The view shaken by an impact at `at`, and kicked down and to a side when its preset has a kick, as hard as it is
-- felt there (`scale` times that).
local function shake(at: Vector3, preset: { number }, scale: number?)
	local share = felt(at) * (scale or 1)
	if share <= 0 then return end
	local seconds = preset[2]
	CameraController.Shake(preset[1] * share, 4 * seconds / Tune.SWINGS, seconds)
	local kick = preset[3]
	if not kick then return end
	local impulse = kick * share * CameraController.ShakeMultiplier / KICK_PEAK_PER_IMPULSE
	local side = if math.random() < 0.5 then -1 else 1
	CameraController.SetRecoilSpring(Tune.KICK_FREQUENCY, Tune.KICK_DAMPING, Tune.KICK_ROLL)
	CameraController.AddRecoil(-impulse, impulse * Tune.KICK_SIDE_SHARE * side)
end

local floorUnder = trexFx.FloorUnder

local function boneOf(model: Model, name: string): Bone?
	local byName = bones[model]
	if not byName then
		byName = {}
		bones[model] = byName
	end

	local found = byName[name]
	if found and found.Parent then return found end
	local bone = model:FindFirstChild(name, true)
	if not bone or not bone:IsA("Bone") then return nil end
	byName[name] = bone
	return bone
end

local function bonePosition(boss: TBoss, name: string): Vector3?
	local model = EnemiesController.GetModel(boss.InstanceId)
	local bone = if model then boneOf(model, name) else nil
	return if bone then bone.TransformedWorldCFrame.Position else nil
end

-- Where its voice comes from: the head, or head height over `from` while the rig is not there.
local function headOf(boss: TBoss, from: Vector3): Vector3
	return bonePosition(boss, "Head") or (from + UP * Tune.HEAD_HEIGHT)
end

local function toeOf(side: string): string
	return if side == "l" or side == "L" then "ToeL" else "ToeR"
end

-- A footfall: the floor's ring, dust, pixels and bricks round the foot, and the shake of it.
local function footfall(boss: TBoss, side: string, strength: number, preset: { number })
	local foot = bonePosition(boss, toeOf(side))
	if not foot then return end
	local floor, normal, color = floorUnder(foot)
	if not floor then return end
	trexFx.Footfall(floor, normal, color, strength)
	trexSounds.Play("Step", floor)
	shake(floor, preset)
end

-- A stamp under the foot on `side`, `size` big (trexFx.Stomp's: 1 the Stomp).
local function stamp(boss: TBoss, side: string, size: number, preset: { number })
	local foot = bonePosition(boss, toeOf(side))
	if not foot then return end
	local floor, normal, color = floorUnder(foot)
	if not floor then return end
	trexFx.Stomp(floor, normal, color, size)
	trexSounds.Play("Stomp", floor)
	shake(floor, preset)
end

-- A foot dragged along the floor `along`: the dust, pixels and sparks it throws ahead of it.
local function scrape(boss: TBoss, toe: string, along: Vector3)
	local foot = bonePosition(boss, toe)
	if not foot then return end
	local floor, normal, color = floorUnder(foot)
	if floor then trexFx.Scrape(floor, normal, color, along) end
end

local function schedule(boss: TBoss, at: number, run: () -> ())
	local timeline = boss.Timeline
	table.insert(timeline, { At = at, Run = run })
	table.sort(timeline, function(a, b)
		return a.At < b.At
	end)
end

local function fxPart(shape: Enum.PartType, material: Enum.Material, color: Color3): Part
	local part = Instance.new("Part")
	part.Shape = shape
	part.Material = material
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

local function track(instanceId: number): TBoss?
	local found = bosses[instanceId]
	if found then return found end
	local enemyData = EnemiesController.Bosses[instanceId]
	local kit = if enemyData then enemyData.Boss else nil
	if not enemyData or not kit then return nil end
	local boss: TBoss = {
		InstanceId = instanceId,
		Data = enemyData,
		Kit = kit,
		Timeline = {},
		StepClock = {},
		Shield = nil,
		ShieldAlpha = 0,
		ShieldHitAt = -math.huge,
		ShieldSoundAt = -math.huge,
		ShieldTarget = false,
		ShieldFloor = nil,
		Beams = {},
		Anchor = nil,
		Guards = {},
		LastCFrame = nil,
	}
	bosses[instanceId] = boss
	return boss
end

local function yawOf(cframe: CFrame): number
	-- The body faces its model's +Z (EnemiesController's buildTarget): the CFrame's back.
	local back = cframe.ZVector
	return math.atan2(back.X, back.Z)
end

local function bodyFrame(position: Vector3, yaw: number): CFrame
	return CFrame.new(position) * CFrame.Angles(0, yaw, 0)
end

-- The way the body faces now, flat.
local function facing(boss: TBoss): Vector3
	local here = EnemiesController.GetCFrame(boss.InstanceId)
	local yaw = if here then yawOf(here) else 0
	return Vector3.new(math.sin(yaw), 0, math.cos(yaw))
end

-- Turns the body onto `yaw` where it stands over AIM_TURN, then lets the packets have it again.
local function aimAt(boss: TBoss, yaw: number)
	local from = EnemiesController.GetCFrame(boss.InstanceId)
	if not from then return end
	local startYaw = yawOf(from)
	local diff = math.atan2(math.sin(yaw - startYaw), math.cos(yaw - startYaw))
	if math.abs(diff) < 0.02 then return end
	local position = from.Position
	local startedAt = TimeCore.EnemyClock
	EnemiesController.Drive(boss.InstanceId, function(now: number): CFrame?
		local u = (now - startedAt) / Tune.AIM_TURN
		if u >= 1 then return nil end
		local eased = 1 - (1 - u) ^ 3
		return bodyFrame(position, startYaw + diff * eased)
	end)
end

-- ============================== Moves ==============================

-- `tempo`: how many times as long as authored the server times it (BossesCore.Tempo), so the clip plays at 1 / tempo
-- and its beats land on the warnings.
local function onAttack(boss: TBoss, index: number, from: Vector3, yaw: number, tempo: number)
	local attack = boss.Data.Attacks[index]
	if not attack then return end
	local id = boss.InstanceId
	local now = TimeCore.EnemyClock
	local kit = boss.Kit
	local kind = attack.Kind
	EnemiesController.PlayClip(id, attack.AnimationName or "Attack", { Fade = 0.12, Speed = 1 / tempo })
	aimAt(boss, yaw)

	if kind == "Dive" then
		-- Out of sight once it is under: the clip ends there, and its last frame is not held.
		schedule(boss, now + kit.DiveUnder, function()
			local here = EnemiesController.GetCFrame(id)
			local under = (here or bodyFrame(from, yaw)) - UP * Tune.UNDER_DEPTH
			EnemiesController.Drive(id, function()
				return under
			end)
		end)
		-- The floor heaving where it goes down into it, harder each time; under its feet if nothing is there.
		local floor, normal, color = floorUnder(from + Vector3.new(math.sin(yaw), 0, math.cos(yaw)) * Tune.SINK_AHEAD)
		if not floor then
			floor, normal, color = floorUnder(from)
		end
		if not floor then return end

		-- One cue carries all three heaves at these moments.
		trexSounds.Play("Sink", floor)
		for i, delay in { 0.3, 0.7, 1.1 } do
			schedule(boss, now + delay, function()
				local size = Tune.SINK_SIZES[i]
				trexFx.Sink(floor, normal, color, size)
				shake(floor, Tune.CATCH, size)
			end)
		end
		return
	end

	if kind == "Summon" then
		-- The voice builds before the jaws open on the roar.
		schedule(boss, now + attack.Delay - trexSounds.Lead("RoarShort"), function()
			trexSounds.Play("RoarShort", headOf(boss, from))
		end)
		schedule(boss, now + attack.Delay, function()
			local head = headOf(boss, from)
			shake(head, Tune.ROAR)
			local floor, _, color = floorUnder(from)
			trexFx.Roar(function()
				local headNow, jaw = bonePosition(boss, "Head"), bonePosition(boss, "Jaw")
				if not headNow or not jaw then return nil, nil end
				local ahead = facing(boss)
				return jaw + ahead * Tune.MOUTH_AHEAD, (ahead * 2 + (jaw - headNow).Unit).Unit
			end, Tune.ROAR_SECONDS, floor, color, Tune.ROAR_REACH)
		end)
		return
	end

	if kind == "Charge" then
		-- The wind-up: a foot pawing the floor back twice, a snort out of the nose each time.
		for _, delay in { 0.35, 0.75 } do
			schedule(boss, now + delay * tempo - trexSounds.Lead("Snort"), function()
				trexSounds.Play("Snort", headOf(boss, from))
			end)
			schedule(boss, now + delay * tempo, function()
				local ahead = facing(boss)
				footfall(boss, "r", Tune.PAW_STRENGTH, Tune.STEP)
				scrape(boss, "ToeR", -ahead)
				local head = bonePosition(boss, "Head")
				if head then trexFx.Snort(head + ahead * Tune.NOSE_AHEAD - UP * Tune.NOSE_DOWN, ahead) end
			end)
		end
		return
	end

	-- The tail's arc is drawn through the whole swing, the blow in the middle of it.
	if attack.AnimationName == "TailSweep" then
		schedule(boss, now + (attack.Delay - Tune.SWEEP_LEAD) * tempo, function()
			trexFx.Sweep(function()
				return bonePosition(boss, "Tail3")
			end, Tune.SWEEP_SECONDS * tempo)
		end)
		-- One swing whose whoosh peaks on the blow.
		schedule(boss, now + attack.Delay * tempo - trexSounds.Lead("TailSweep"), function()
			trexSounds.Play("TailSweep", bonePosition(boss, "Tail3") or from)
		end)
	end

	-- The maw opens ahead of the bite and shuts on it.
	if attack.AnimationName == "Chomp" then
		schedule(boss, now + attack.Delay * tempo - trexFx.MawOpenSeconds, function()
			local here = EnemiesController.GetCFrame(id)
			local base = if here then here.Position else from
			local ahead = facing(boss)
			trexFx.Maw(base + ahead * Tune.MAW_AHEAD + UP * Tune.MAW_HEIGHT, ahead)
		end)
		-- Its snarl builds into the jaws shutting on the blow.
		schedule(boss, now + attack.Delay * tempo - trexSounds.Lead("Bite"), function()
			trexSounds.Play("Bite", bonePosition(boss, "Jaw") or from)
		end)
	end

	-- A Slam round its body, once or on each beat; a Quake's beats grow to its last.
	local beats = attack.Beats or { attack.Delay }
	for i, beat in beats do
		local isLast = i == #beats
		schedule(boss, now + beat * tempo, function()
			local name = attack.AnimationName
			if name == "Chomp" then
				local jaw = bonePosition(boss, "Jaw") or from
				trexFx.Bite(jaw, facing(boss))
				shake(jaw, Tune.BITE)
			elseif name == "TailSweep" then
				local tail = bonePosition(boss, "Tail3")
				if tail then shake(tail, Tune.SWEEP) end
			elseif attack.IsVolley then
				local back = bonePosition(boss, "Chest") or from
				trexFx.Launch(back + UP * Tune.LAUNCH_LIFT)
				trexSounds.Play("SpineLaunch", back)
				shake(back, Tune.SHAKE_LOOSE)
			else
				-- Stomp and Quake land on alternate feet (left, right, left), read off the clips; the Quake's last
				-- beat sends its ring out along the floor as far and as fast as the server's.
				local side = if name == "Stomp" or i % 2 == 0 then "r" else "l"
				local isQuake = #beats > 1
				local size = if isQuake then Tune.QUAKE_SIZES[i] or 1 else 1
				stamp(boss, side, size, if isQuake then Tune.QUAKE[i] or Tune.STOMP else Tune.STOMP)
				local here = EnemiesController.GetCFrame(id)
				if isQuake and isLast and attack.FinisherRadius and attack.FinisherSpeed and here then
					trexFx.Wave(here.Position, attack.FinisherRadius, attack.FinisherSpeed, Tune.QUAKE_WAVE)
					trexSounds.Play("QuakeWave", here.Position)
				end
			end
		end)
	end
end

-- The run: drawn along its line at `speed`, held at its end until the skid takes it.
local function onChargeRun(boss: TBoss, from: Vector3, to: Vector3, speed: number)
	local id = boss.InstanceId
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local length = flat.Magnitude
	local direction = if length > 1e-3 then flat / length else Vector3.zAxis
	local yaw = math.atan2(direction.X, direction.Z)
	local startedAt = TimeCore.EnemyClock
	EnemiesController.StopClip(id, "ChargeWindup", 0.08)
	EnemiesController.StopClip(id, "ChargeTurn", 0.08)
	EnemiesController.PlayClip(id, "Charge", { Fade = 0.08, IsLooped = true, Speed = speed / boss.Kit.ChargeSpeed })
	boss.StepClock.Charge = 0
	EnemiesController.Drive(id, function(now: number): CFrame?
		local traveled = math.min((now - startedAt) * speed, length)
		return bodyFrame(from:Lerp(to, if length > 0 then traveled / length else 1), yaw)
	end)
end

-- The skid: the run (`speed`) bled off over SkidStop, feet scraping, then the catch.
local function onSkid(boss: TBoss, from: Vector3, to: Vector3, speed: number)
	local id = boss.InstanceId
	local kit = boss.Kit
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local room = flat.Magnitude
	local here = EnemiesController.GetCFrame(id)
	local yaw = if here then yawOf(here) else 0
	local direction = Vector3.new(math.sin(yaw), 0, math.cos(yaw))
	local startedAt = TimeCore.EnemyClock
	EnemiesController.StopClip(id, "Charge", 0.12)
	EnemiesController.PlayClip(id, "Skid", { Fade = 0.08 })
	EnemiesController.Drive(id, function(now: number): CFrame?
		local elapsed = now - startedAt
		if elapsed >= kit.SkidLength then return nil end
		local slid = math.min(BossesCore.SkidDistance(speed, kit.SkidStop, elapsed), room)
		return bodyFrame(from + direction * slid, yaw)
	end)

	-- Both feet tear the floor up while it slides, and land hard as they catch. The scrape is one cue as long as the
	-- slide.
	trexSounds.Play("Skid", from)
	for i = 0, 5 do
		schedule(boss, startedAt + i * kit.SkidStop / 6, function()
			for _, name in { "ToeL", "ToeR" } do
				scrape(boss, name, direction)
			end
			if i == 0 then shake(from, Tune.SKID) end
		end)
	end
	schedule(boss, startedAt + 0.9, function()
		footfall(boss, "l", Tune.CATCH_STRENGTH, Tune.CATCH)
	end)
end

-- The turn: braced on the spot, yawed at an even rate to its left onto the next line.
local function onTurn(boss: TBoss, yaw: number)
	local id = boss.InstanceId
	local here = EnemiesController.GetCFrame(id)
	if not here then return end
	local startYaw = yawOf(here)
	local position = here.Position
	local turnLength = boss.Kit.TurnLength
	local startedAt = TimeCore.EnemyClock
	EnemiesController.StopClip(id, "Skid", 0.1)
	EnemiesController.PlayClip(id, "ChargeTurn", { Fade = 0.1 })
	-- To its left: the yaw only grows, so the turn never takes the short way round.
	local delta = (yaw - startYaw) % (2 * math.pi)
	EnemiesController.Drive(id, function(now: number): CFrame?
		local u = math.min((now - startedAt) / turnLength, 1)
		return bodyFrame(position, startYaw + delta * u)
	end)
	for _, delay in { 0.15, 0.5 } do
		schedule(boss, startedAt + delay, function()
			for _, name in { "ToeL", "ToeR" } do
				scrape(boss, name, here.RightVector)
			end
		end)
	end
end

-- Up through the floor at `to`: the floor erupting, the hardest shake, then pulling itself together, its bones
-- knocking into place.
local function onRise(boss: TBoss, to: Vector3, yaw: number)
	local id = boss.InstanceId
	local kit = boss.Kit
	local startedAt = TimeCore.EnemyClock
	local frame = bodyFrame(to, yaw)
	EnemiesController.StopClip(id, "DiveSink", 0)
	EnemiesController.PlayClip(id, "DiveRise", { Fade = 0 })
	EnemiesController.Drive(id, function(now: number): CFrame?
		if now - startedAt >= kit.DiveRiseLength + kit.ReassembleLength then return nil end
		return frame
	end)
	schedule(boss, startedAt + kit.DiveRiseImpact - trexSounds.Lead("Rise"), function()
		trexSounds.Play("Rise", floorUnder(to) or to)
	end)
	schedule(boss, startedAt + kit.DiveRiseImpact, function()
		local floor, normal, color = floorUnder(to)
		shake(floor or to, Tune.RISE)
		if floor then trexFx.Rise(floor, normal, color) end
	end)
	schedule(boss, startedAt + 0.82, function()
		footfall(boss, "l", Tune.CATCH_STRENGTH, Tune.CATCH)
	end)
	-- The reassemble's cue is as long as its clip: the pieces knocking in build to the head snapping home at 1 s.
	schedule(boss, startedAt + kit.DiveRiseLength, function()
		EnemiesController.PlayClip(id, "Reassemble", { Fade = 0.1 })
		trexSounds.Play("Reassemble", bonePosition(boss, "Chest") or (to + UP * Tune.BOSS_CHEST))
	end)
	for _, delay in Tune.RATTLES do
		schedule(boss, startedAt + kit.DiveRiseLength + delay, function()
			local chest = bonePosition(boss, "Chest")
			if not chest then return end
			trexFx.Rattle(chest)
			shake(chest, Tune.SHAKE_LOOSE)
		end)
	end
end

-- The crack it runs under the floor, glowing step by step from `from` to `to` over `seconds`.
local function onCrack(boss: TBoss, from: Vector3, to: Vector3, seconds: number)
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local length = flat.Magnitude
	if length < 1 then return end
	local direction = flat / length
	local side = direction:Cross(UP)
	local count = math.floor(length / Tune.CRACK_STEP)
	local startedAt = TimeCore.EnemyClock
	local soundEvery = math.max(math.round(Tune.CRACK_SOUND_SECONDS * count / math.max(seconds, 1e-3)), 1)
	for i = 1, count do
		local share = i / count
		schedule(boss, startedAt + seconds * share, function()
			local point = from:Lerp(to, share) + side * ((math.random() * 2 - 1) * Tune.CRACK_JITTER)
			local floor, normal, color = floorUnder(point)
			if not floor then return end
			trexFx.Crack(floor, normal, color, direction)
			if (i - 1) % soundEvery == 0 then trexSounds.Play("Crack", floor) end
			if i % 6 == 0 then shake(floor, Tune.STEP) end
		end)
	end
end

-- One spine thrown off its back at its beat, landing on `to` as the warning there resolves.
local function onSpine(boss: TBoss, index: number, to: Vector3, seconds: number)
	local attack = boss.Data.Attacks[index]
	local flight = if attack and attack.Flight then attack.Flight else 0.8
	local startedAt = TimeCore.EnemyClock + math.max(seconds - flight, 0)
	schedule(boss, startedAt, function()
		local here = EnemiesController.GetCFrame(boss.InstanceId)
		local from = if here then here:PointToWorldSpace(Tune.SPINE_FROM) else to + UP * 12
		trexFx.Spine(from, to, flight)
	end)
	schedule(boss, startedAt + flight, function()
		trexSounds.Play("SpineLand", to)
		shake(to, Tune.SPINE_LAND)
	end)
end

-- ============================== Shield ==============================

local function setBeams(boss: TBoss, guardIds: { number })
	local anchor = boss.Anchor
	if not anchor then
		anchor = Instance.new("Attachment")
		anchor.Name = "BossBeamAnchor"
		anchor.Parent = Workspace.Terrain
		boss.Anchor = anchor
	end

	local keep: { [number]: boolean } = {}
	for _, guardId in guardIds do
		keep[guardId] = true
		if boss.Beams[guardId] then continue end
		local from = Instance.new("Attachment")
		from.Name = "GuardBeam"
		from.Parent = Workspace.Terrain
		local beam = Instance.new("Beam")
		beam.Attachment0 = from
		beam.Attachment1 = anchor
		-- Straight, so the motes trexFx flows along it lie on it.
		beam.Color = ColorSequence.new(PALE_GREEN, GREEN)
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Width0 = Tune.BEAM_WIDTH
		beam.Width1 = Tune.BEAM_WIDTH * 1.6
		beam.FaceCamera = true
		beam.Transparency = NumberSequence.new(0.1)
		beam.Parent = from
		boss.Beams[guardId] = { Beam = beam, From = from, Phase = math.random(), Owed = 0 }
	end

	for guardId, entry in boss.Beams do
		if keep[guardId] then continue end
		entry.From:Destroy()
		boss.Beams[guardId] = nil
		-- A guard falling snaps its beam: a burst where it stood, bone thrown off it.
		local at = EnemiesController.GetCFrame(guardId)
		if not at then continue end
		local chest = at.Position + UP * Tune.GUARD_CHEST
		trexFx.Snap(chest)
		trexSounds.Play("BeamSnap", chest)
	end
end

local function onShield(boss: TBoss, guardIds: { number }, total: number)
	boss.Guards = guardIds
	boss.ShieldTarget = #guardIds > 0
	setBeams(boss, guardIds)
	BossController.OnShield:Fire(boss.InstanceId, #guardIds, total)
	local here = EnemiesController.GetCFrame(boss.InstanceId)
	if boss.ShieldTarget and not boss.Shield then
		local bubble = fxPart(Enum.PartType.Ball, Enum.Material.ForceField, GREEN)
		bubble.Size = Vector3.one * Tune.SHIELD_SIZE
		bubble.Transparency = 1
		bubble.Parent = Workspace
		boss.Shield = bubble
		if not here then return end
		local center = here:PointToWorldSpace(Tune.SHIELD_CENTER)
		boss.ShieldFloor = floorUnder(here.Position)
		trexFx.ShieldUp(center)
		trexSounds.Play("ShieldUp", center)
		shake(center, Tune.SHAKE_LOOSE)
	elseif not boss.ShieldTarget and boss.Shield and here then
		-- It shatters: neon shards and a burst as big as the bubble.
		local center = here:PointToWorldSpace(Tune.SHIELD_CENTER)
		trexFx.ShieldBreak(center, Tune.SHIELD_SIZE / 2)
		trexSounds.Play("ShieldBreak", center)
		shake(here.Position, Tune.STOMP)
	end
end

local function stepShield(boss: TBoss, dt: number, now: number)
	local bubble = boss.Shield
	if not bubble then return end
	local target = if boss.ShieldTarget then 1 else 0
	boss.ShieldAlpha += math.clamp(target - boss.ShieldAlpha, -dt / Tune.SHIELD_FADE, dt / Tune.SHIELD_FADE)
	local here = EnemiesController.GetCFrame(boss.InstanceId)
	if boss.ShieldAlpha <= 0 or not here then
		if not boss.ShieldTarget then
			bubble:Destroy()
			boss.Shield = nil
		end
		return
	end

	local hit = math.max(1 - (now - boss.ShieldHitAt) / Tune.SHIELD_HIT_SECONDS, 0)
	local breathe = math.sin(now * 2.4) * Tune.SHIELD_BREATHE
	bubble.Size = Vector3.one * (Tune.SHIELD_SIZE * (1 + breathe + hit * Tune.SHIELD_HIT_SWELL))
	bubble.CFrame = here * CFrame.new(Tune.SHIELD_CENTER)
	bubble.Transparency = 1 - (1 - Tune.SHIELD_TRANSPARENCY * (1 - hit * 0.6)) * boss.ShieldAlpha

	local floor = boss.ShieldFloor
	if floor and boss.ShieldTarget then trexFx.ShieldRim(floor, Tune.SHIELD_SIZE / 2, dt) end

	local anchor = boss.Anchor
	local chest = here.Position + UP * Tune.BOSS_CHEST
	if anchor then anchor.WorldPosition = chest end
	for guardId, entry in boss.Beams do
		local guard = EnemiesController.GetCFrame(guardId)
		local beam = entry.Beam
		beam.Enabled = guard ~= nil
		if not guard then continue end
		local from = guard.Position + UP * Tune.GUARD_CHEST
		entry.From.WorldPosition = from
		entry.Phase += dt
		beam.Width0 = Tune.BEAM_WIDTH * (1 + Tune.BEAM_SHIVER * math.sin(now * Tune.BEAM_SHIVER_RATE + entry.Phase * 7))
		entry.Owed = trexFx.BeamFlow(from, chest, entry.Phase, dt, entry.Owed)
	end
end

-- ============================== Steps ==============================

-- A footfall on every step its walk or run passes this frame, read off where the clip is.
local function stepGait(boss: TBoss, clip: string, steps: { number }, strength: number, preset: { number })
	local trackNow = EnemiesController.GetTrack(boss.InstanceId, clip)
	if not trackNow or not trackNow.IsPlaying or trackNow.WeightCurrent < 0.5 then
		boss.StepClock[clip] = nil
		return
	end

	local position = trackNow.TimePosition
	local last = boss.StepClock[clip]
	boss.StepClock[clip] = position
	if not last then return end
	for i, stepAt in steps do
		local crossed = if position >= last
			then stepAt > last and stepAt <= position
			else stepAt > last or stepAt <= position
		if crossed then footfall(boss, if i == 1 then "l" else "r", strength, preset) end
	end
end

local function forget(boss: TBoss)
	if boss.Shield then boss.Shield:Destroy() end
	for _, entry in boss.Beams do
		entry.From:Destroy()
	end
	if boss.Anchor then boss.Anchor:Destroy() end
	bosses[boss.InstanceId] = nil
end

local function update(dt: number)
	local now = TimeCore.EnemyClock
	local clock = os.clock()
	for instanceId, boss in bosses do
		local timeline = boss.Timeline
		while timeline[1] and timeline[1].At <= now do
			local entry = table.remove(timeline, 1) :: { At: number, Run: () -> () }
			entry.Run()
		end

		stepShield(boss, dt, clock)
		local kit = boss.Kit
		stepGait(boss, "Walk", kit.WalkSteps, Tune.STEP_STRENGTH, Tune.STEP)
		stepGait(boss, "Charge", kit.ChargeSteps, Tune.RUN_STRENGTH, Tune.RUN_STEP)
		local here = EnemiesController.GetCFrame(instanceId)
		if here then boss.LastCFrame = here end
		if not EnemiesController.Bosses[instanceId] and not boss.Shield and #timeline == 0 then forget(boss) end
	end

	-- The server holds the match through a boss's intro and tells clients only the scale (TimeCore.IsCutscene is the
	-- server's), so the intro playing here is what says real time.
	local isIntro = BossIntroController.IsPlaying()
	local fxDt = if isIntro then dt else math.max(now - lastEnemyClock, 0)
	lastEnemyClock = now
	fxClock += fxDt
	local root = selfRoot
	local passedAt, passedStrength = trexFx.Update(
		fxDt,
		fxClock,
		if isIntro then 1 else TimeCore.TimeScale * TimeCore.EnemyTimeScale,
		if root then root.Position else nil
	)
	-- The intro's camera has its own jolts.
	if passedAt and not isIntro then shake(passedAt, Tune.WAVE_PASS, passedStrength) end

	local gameNow = TimeCore.GameClock
	for i = #later, 1, -1 do
		local entry = later[i]
		if entry.At > gameNow then continue end
		table.remove(later, i)
		entry.Run()
	end

	-- Every boss known to the renderer is followed, moves or none: its steps land from the first.
	for instanceId in EnemiesController.Bosses do
		track(instanceId)
	end
end

-- ============================== Wiring ==============================

ServerNetworkBosses.Move.On(
	function(instanceId: number, move: number, index: number, from: Vector3, to: Vector3, value: number, tempo: number)
		local boss = track(instanceId)
		if not boss then return end
		if move == EBossMoves.Attack then
			onAttack(boss, index, from, value, tempo)
		elseif move == EBossMoves.ChargeRun then
			onChargeRun(boss, from, to, value)
		elseif move == EBossMoves.Skid then
			onSkid(boss, from, to, value)
		elseif move == EBossMoves.ChargeTurn then
			onTurn(boss, value)
		elseif move == EBossMoves.DiveRise then
			onRise(boss, to, value)
		elseif move == EBossMoves.Crack then
			onCrack(boss, from, to, value)
		elseif move == EBossMoves.Spine then
			onSpine(boss, index, to, value)
		elseif move == EBossMoves.Pace then
			EnemiesController.SetWalkPace(instanceId, value)
		end
	end
)

ServerNetworkBosses.Shield.On(function(instanceId: number, guardIds: { number }, total: number)
	local boss = track(instanceId)
	if boss then onShield(boss, guardIds, total) end
end)

-- Every blow its shield turns: the bubble swells, and a ring lands on its skin on the side this view sees.
ServerNetworkBosses.ShieldHit.On(function(instanceId: number)
	local boss = bosses[instanceId]
	if not boss then return end
	boss.ShieldHitAt = os.clock()
	local here = EnemiesController.GetCFrame(instanceId)
	if not here or not boss.ShieldTarget then return end
	local center = here:PointToWorldSpace(Tune.SHIELD_CENTER)
	local eye = Workspace.CurrentCamera.CFrame.Position
	trexFx.ShieldHit(center, Tune.SHIELD_SIZE / 2, eye)

	-- Heard on the side of the bubble this view sees, where its ring lands.
	if boss.ShieldHitAt - boss.ShieldSoundAt < Tune.SHIELD_HIT_SOUND_GAP then return end
	boss.ShieldSoundAt = boss.ShieldHitAt
	local toEye = eye - center
	local skin = if toEye.Magnitude > 1e-3 then center + toEye.Unit * (Tune.SHIELD_SIZE / 2) else center
	trexSounds.Play("ShieldHit", skin)
end)

-- Run over: the body flies as the server threw it, and the screen takes the blow.
ServerNetworkBosses.Knocked.On(function(velocity: Vector3)
	local root, humanoid = selfRoot, selfHumanoid
	if not root or not humanoid then return end
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	root.AssemblyLinearVelocity = velocity
	CameraController.Shake(Tune.RUN_OVER[1], 4 * Tune.RUN_OVER[2] / Tune.SWINGS, Tune.RUN_OVER[2])
end)

-- Its fall: the overkill's burst and its bones flying whatever killed it, then the floor taking its weight as it lands
-- (its Death clip) and its soul leaving the pile.
EnemiesController.OnEnemyKilled:Connect(function(instanceId: number, _, _, _, chest: Vector3)
	local boss = bosses[instanceId]
	if not boss then return end
	local enemyData = ENEMIES[boss.Data.Id]
	if enemyData then EnemyImpacts.EmitOverkill(enemyData, chest, EnemiesCore.AimShape(enemyData), nil) end
	trexFx.Shatter(chest)
	-- The burst, its cry and its body coming apart, all on the killing blow (the cry's short build comes after it).
	trexSounds.Play("Shatter", chest)
	trexSounds.Play("DeathCry", chest)
	trexSounds.Play("Collapse", chest)
	shake(chest, Tune.STOMP)
	local last = boss.LastCFrame
	if not last then return end
	local kit = boss.Kit
	-- Game time, not enemy time: the body is no longer an enemy and falls through a freeze.
	table.insert(later, {
		At = TimeCore.GameClock + kit.DeathDown,
		Run = function()
			local floor, normal, color = floorUnder(last.Position)
			trexSounds.Play("Fall", floor or last.Position)
			shake(floor or last.Position, Tune.FALL)
			if floor then trexFx.Fall(floor, normal, color, last, Tune.SOUL_SECONDS) end
		end,
	})
end)

BossController.OnStart = function()
	RunService.PreRender:Connect(update)
end

BossController.OnSelfCharacterAdded = function(character: TCharacter.TCharacter)
	selfRoot = character.HumanoidRootPart
	selfHumanoid = character.Humanoid
end :: TCharacterEvents.OnCharacterAdded

BossController.OnSelfCharacterRemoving = function()
	selfRoot = nil
	selfHumanoid = nil
end

return Ignis.Register(BossController)
