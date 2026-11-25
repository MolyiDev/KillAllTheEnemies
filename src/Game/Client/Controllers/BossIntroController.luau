-- A boss's intro (Bosses.Intro), played for everyone every time a boss arrives while the server holds the match:
-- the delivered scene's cutscene on our rig. Its Intro clip at full speed whatever the held clock, the delivered
-- camera shots in the boss's own frame (BossesCore.INTRO_SHOTS) with their handheld drift and impact jolts, a grade,
-- the letterbox and the title card, and the walk-in's footfalls, stomp, roar and bite thrown in the house look.
-- Everything runs off BossesCore.IntroClock, the clock the server holds the match by.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local vide = require(ReplicatedStorage.Packages.vide)
local Network = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Network)
local EnemiesController = require(script.Parent.EnemiesController)
-- Through PlayerScripts, the copy that runs (see HudController).
local CameraController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.CameraController)
local MusicController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.MusicController)
local trexFx = require(script.Parent.Parent.Utils.trexFx)
local trexSounds = require(script.Parent.Parent.Utils.trexSounds)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local BossesCore = require(ReplicatedStorage.Shared.Core.BossesCore)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local TData = require(ReplicatedStorage.Types.TData)

local ServerNetworkBosses = Network.Server.Bosses

local LocalPlayer = Players.LocalPlayer
local ENEMIES = DataCore.Enemies.ById
local create = vide.create
local source = vide.source
local UP = Vector3.yAxis

local GREEN = Color3.fromRGB(90, 255, 140)
local TITLE_INK = Color3.fromRGB(10, 40, 20)

local Tune = table.freeze({
	-- Seconds to wait for the boss's rig before playing without it.
	RIG_WAIT = 1.5,
	-- The handheld drift's size over the intro's clock (as delivered): (clock, degrees of wander).
	HANDHELD = table.freeze({ { 0, 0.06 }, { 3.6, 0.05 }, { 7.35, 0.3 }, { 9.4, 0.12 }, { 12.9, 0.05 } }),
	DRIFT_DEGREES = 6,
	-- The impact jolt: each beat sets it at least this high; it decays this much a second; the field of view kicks
	-- this many degrees at a jolt of 1.
	JOLT_STEP = 0.3,
	JOLT_STOMP = 1,
	JOLT_ROAR = 1.4,
	JOLT_CHOMP = 0.6,
	JOLT_ROARING = 0.35,
	JOLT_DECAY = 1.6,
	JOLT_FOV = 8,
	-- The roar's breath lasts this long on the clock (it rides the slow motion).
	ROAR_FROM = 7.3,
	ROAR_UNTIL = 9.25,
	-- The grade (clock, value[, ease]) as delivered.
	SATURATION = table.freeze({ { 0, -0.35 }, { 7.3, -0.3 }, { 7.45, 0.15, "Out" }, { 9.5, -0.15 }, { 12.9, -0.2 } }),
	CONTRAST = table.freeze({ { 0, 0.15 }, { 7.3, 0.2 }, { 7.45, 0.35, "Out" }, { 9.5, 0.2 } }),
	TINT_CALM = Color3.fromRGB(205, 232, 222),
	TINT_ROAR = Color3.fromRGB(185, 255, 200),
	-- Depth of field held round what the shot looks at.
	FOCUS_RADIUS = 7,
	NEAR_BLUR = 0.5,
	FAR_BLUR = 0.55,
	-- The screen's white flash on each beat, and how fast it fades (a second).
	FLASH_STOMP = 0.25,
	FLASH_ROAR = 0.45,
	FLASH_CHOMP = 0.6,
	FLASH_FADE = 2.5,
	-- The letterbox's bars (a share of the screen's height each) sliding in and out.
	BARS = 0.125,
	BARS_SECONDS = 0.6,
	-- The title card: in at this clock, the name punching down from this scale, the line and subtitle after it.
	TITLE_AT = 10.05,
	TITLE_SCALE = 1.3,
	TITLE_IN = 0.6,
	SUBTITLE_AFTER = 0.25,
	SWEEP_SECONDS = 2.2,
	-- The fade to black before the hand back, and out of it after.
	FADE_OUT = 0.6,
	FADE_IN = 0.8,
	-- A walk-in step lands this hard (trexFx.Footfall), the feet planted for the roar this hard; the stomp's wave and
	-- the roar's run out this far.
	STEP_STRENGTH = 1.2,
	ROAR_FEET = 1.5,
	STOMP_REACH = 40,
	STOMP_WAVE_SPEED = 50,
	STOMP_WAVE = 1.2,
	-- The stomp as big as the Quake's last beat: the moment the intro is built round.
	STOMP_SIZE = 1.5,
	ROAR_REACH = 70,
	-- The roar pours out of a mouth this far ahead of the jaw bone, for as long as the roar lasts on the clock
	-- (ROAR_FROM to ROAR_UNTIL); its ride is given this long at most.
	MOUTH_AHEAD = 2,
	ROAR_RIDE = 6,
	-- The maw closes round the snout's tip, this far ahead of the body and this high: its U runs from 2.6 behind this
	-- point to 4.5 past it, so at the Intro clip's bite the snout's 20.7-stud reach sits inside its back teeth.
	MAW_AHEAD = 19,
	MAW_HEIGHT = 7,
	-- The hunt, the neck's moves between the walk-in and the stomp, on the Intro clip's seconds (the clock runs at them
	-- until the roar). Its right eye socket, right nostril and front teeth in the Head bone's frame (+Z out of the
	-- snout, studs at the game's scale), measured on the rig; the left ones mirror them.
	EYE = Vector3.new(1.7, -0.5, 1.8),
	NOSTRIL = Vector3.new(0.7, -2.1, 7.3),
	TEETH = Vector3.new(0, -4, 7.3),
	-- Breath puffed out of the nostrils as the head rises with the jaws parted.
	SNORTS = table.freeze({ 3.64, 3.8, 3.96 }),
	-- The sockets' glare (clock, strength[, ease]): kindling as the head whips round, flaring as it locks on at GLINT,
	-- easing off as it turns away, gone by the stomp's shot.
	GLARE = table.freeze({
		{ 4.1, 0 },
		{ 4.8, 0.7, "In" },
		{ 4.86, 1.3, "Out" },
		{ 4.95, 1 },
		{ 5.47, 0.3 },
		{ 5.75, 0, "Out" },
	}),
	GLINT = 4.85,
	-- Dust and bone shaken off the neck (clock, size): the whip, the snap back.
	SHAKES = table.freeze({ { 4.68, 1 }, { 5.3, 0.6 } }),
	-- The teeth shutting.
	CLICKS = table.freeze({ 4.36, 5.12 }),
	-- Dust pulled into the jaws on the crouch before the roar; they spring open at 7.15.
	INHALE_FROM = 6.62,
	INHALE_UNTIL = 7.12,
	-- The hand back looks at the boss this high.
	LOOK_HEIGHT = 7.5,
	-- The music clears room for the stomp, the roar and the chomp, since a sound is heard against the second before
	-- it: down to this share from this long before the stomp, back this long after the chomp (clock seconds).
	MUSIC_DUCK = 0.2,
	MUSIC_DOWN_BEFORE = 1,
	MUSIC_DOWN_SECONDS = 0.8,
	MUSIC_UP_AFTER = 0.4,
	MUSIC_UP_SECONDS = 2.5,
})

type TPlaying = {
	InstanceId: number,
	Data: TData.TEnemy,
	Intro: TData.TEnemyBossIntro,
	Shots: { { BossesCore.TShotKey } },
	Stage: CFrame,
	Frame: CFrame,
	StartedAt: number,
	Track: AnimationTrack?,
	Clock: number,
	Speed: number,
	Jolt: number,
	-- Beats already thrown, by name.
	Done: { [string]: boolean },
	-- Its bones by name, found once; where its head was last frame (a shake flings along the swing).
	Bones: { [string]: Bone },
	HeadAt: Vector3?,
	Grade: ColorCorrectionEffect,
	Focus: DepthOfFieldEffect,
	IsEnding: boolean,
}

local BossIntroController = {}

-- An intro is on screen: the HUD gives way to it.
BossIntroController.IsPlaying = source(false)

local playing: TPlaying? = nil
-- What the overlay draws: the bars in (0 to 1), the black (0 to 1), the white flash, the title's time since it came
-- in (negative before), the boss's name and subtitle.
local bars = source(0)
local black = source(0)
local flash = source(0)
local titleAge = source(-1)
local titleText = source("")
local subtitleText = source("")
-- The overlay stays up after the intro while the black and the bars go (os.clock it ended at).
local isOverlayUp = source(false)
local endedAt = -math.huge

-- ============================== Curves ==============================

local function ease(name: string?, u: number): number
	if name == "Linear" then return u end
	if name == "Out" then return 1 - (1 - u) ^ 3 end
	if name == "In" then return u ^ 3 end
	return if u < 0.5 then 4 * u ^ 3 else 1 - (-2 * u + 2) ^ 3 / 2
end

local function catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: number): Vector3
	local u2, u3 = u * u, u * u * u
	return 0.5 * ((2 * p1) + (p2 - p0) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u2 + (3 * p1 - p0 - 3 * p2 + p3) * u3)
end

-- A keyed number (clock, value[, ease]) at `t`.
local function keyed(keys: { { any } }, t: number): number
	if t <= keys[1][1] then return keys[1][2] end
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t < b[1] then return a[2] + (b[2] - a[2]) * ease(b[3], (t - a[1]) / (b[1] - a[1])) end
	end

	return keys[#keys][2]
end

-- The shot at clock `t`: (eye, look, field of view, roll), in the keys' own frame and scale.
local function evalShot(shots: { { BossesCore.TShotKey } }, t: number): (Vector3, Vector3, number, number)
	local shot = shots[1]
	for _, candidate in shots do
		if t >= candidate[1].Time then shot = candidate end
	end

	for i = 1, #shot - 1 do
		local a, b = shot[i], shot[i + 1]
		if t < b.Time or i == #shot - 1 then
			local u = ease(b.Ease, math.clamp((t - a.Time) / (b.Time - a.Time), 0, 1))
			local before, after = shot[i - 1] or a, shot[i + 2] or b
			return catmull(before.Eye, a.Eye, b.Eye, after.Eye, u),
				catmull(before.Look, a.Look, b.Look, after.Look, u),
				a.Fov + (b.Fov - a.Fov) * u,
				a.Roll + (b.Roll - a.Roll) * u
		end
	end

	local only = shot[1]
	return only.Eye, only.Look, only.Fov, only.Roll
end

-- ============================== Effects ==============================

local floorUnder = trexFx.FloorUnder

-- A bone's world frame, looked up once (the hunt reads the head every frame).
local function boneFrame(intro: TPlaying, name: string): CFrame?
	local found = intro.Bones[name]
	if not found then
		local model = EnemiesController.GetModel(intro.InstanceId)
		local child = if model then model:FindFirstChild(name, true) else nil
		if not child or not child:IsA("Bone") then return nil end
		found = child
		intro.Bones[name] = child
	end
	return found.TransformedWorldCFrame
end

local function bone(intro: TPlaying, name: string): Vector3?
	local frame = boneFrame(intro, name)
	return if frame then frame.Position else nil
end

local function floorAtFoot(intro: TPlaying, side: string): (Vector3?, Vector3, Color3)
	return floorUnder(bone(intro, if side == "l" then "ToeL" else "ToeR") or intro.Stage.Position)
end

local function step(intro: TPlaying, side: string, strength: number)
	local floor, normal, color = floorAtFoot(intro, side)
	if not floor then return end
	trexFx.Footfall(floor, normal, color, strength)
	trexSounds.Play("Step", floor)
end

-- The roar's breath and rings, out of the jaws for as long as the roar lasts on the clock (it rides the slow
-- motion); the ride ends the moment this answers nothing.
local function mouth(intro: TPlaying): () -> (Vector3?, Vector3?)
	return function()
		if playing ~= intro or intro.Clock > Tune.ROAR_UNTIL then return nil, nil end
		local head, jaw = bone(intro, "Head"), bone(intro, "Jaw")
		if not head or not jaw then return nil, nil end
		local forward = intro.Stage.ZVector
		return jaw + forward * Tune.MOUTH_AHEAD, (forward * 2 + (jaw - head).Unit).Unit
	end
end

-- The hunt's moments, each thrown once when the clock passes it, off the head's own frame (the neck turns it well off
-- the body's facing).
local function hunt(intro: TPlaying, clock: number)
	local done = intro.Done
	if done.Inhale then return end
	local head = boneFrame(intro, "Head")
	local headWas = intro.HeadAt
	intro.HeadAt = if head then head.Position else nil
	if not head then return end
	local mirror = Vector3.new(-1, 1, 1)

	for i, at in Tune.SNORTS do
		local name = `Snort{i}`
		if done[name] or clock < at then continue end
		done[name] = true
		trexFx.Snort(head:PointToWorldSpace(Tune.NOSTRIL), head.ZVector)
		trexFx.Snort(head:PointToWorldSpace(Tune.NOSTRIL * mirror), head.ZVector)
	end

	-- The sockets ride the head for as long as the glare's keys run.
	if not done.Glare and clock >= Tune.GLARE[1][1] then
		done.Glare = true
		-- One file for the whole glare, its fire following the same keys.
		trexSounds.Play("Glare", head.Position)
		local untilClock = Tune.GLARE[#Tune.GLARE][1]
		trexFx.Glare(function()
			if playing ~= intro or intro.Clock > untilClock then return nil, nil, 0 end
			local now = boneFrame(intro, "Head")
			if not now then return nil, nil, 0 end
			return now:PointToWorldSpace(Tune.EYE),
				now:PointToWorldSpace(Tune.EYE * mirror),
				keyed(Tune.GLARE, intro.Clock)
		end)
	end

	if not done.Glint and clock >= Tune.GLINT then
		done.Glint = true
		trexFx.Glint(head:PointToWorldSpace(Tune.EYE), head:PointToWorldSpace(Tune.EYE * mirror))
	end

	for i, at in Tune.CLICKS do
		local name = `Click{i}`
		if done[name] or clock < at then continue end
		done[name] = true
		trexFx.Click(head:PointToWorldSpace(Tune.TEETH), head.ZVector)
	end

	for i, shake in Tune.SHAKES do
		local name = `Shake{i}`
		if done[name] or clock < shake[1] or not headWas then continue end
		done[name] = true
		local neck = {}
		for _, boneName in { "Neck1", "Neck2", "Neck3" } do
			local at = bone(intro, boneName)
			if at then neck[#neck + 1] = at end
		end
		neck[#neck + 1] = head.Position
		trexFx.Shake(neck, head.Position - headWas, shake[2])
	end

	if not done.Inhale and clock >= Tune.INHALE_FROM then
		done.Inhale = true
		local teeth = head:PointToWorldSpace(Tune.TEETH)
		trexSounds.Play("Inhale", teeth)
		local floor, _, color = floorUnder(teeth)
		trexFx.Inhale(function()
			if playing ~= intro then return nil, nil end
			local now = boneFrame(intro, "Head")
			if not now then return nil, nil end
			return now:PointToWorldSpace(Tune.TEETH), now.ZVector
		end, Tune.INHALE_UNTIL - Tune.INHALE_FROM, floor, color)
	end
end

-- The clip's beats, each thrown once when the clock passes it.
local function beats(intro: TPlaying, clock: number)
	local data = intro.Intro
	local done = intro.Done
	for i, beat in data.Steps do
		local name = `Step{i}`
		if done[name] or clock < beat.Time then continue end
		done[name] = true
		intro.Jolt = math.max(intro.Jolt, Tune.JOLT_STEP)
		step(intro, beat.Side, Tune.STEP_STRENGTH)
	end

	if not done.Hunt and clock >= data.Hunt then
		done.Hunt = true
		trexSounds.Play("Hunt", bone(intro, "Head") or intro.Stage.Position + UP * Tune.LOOK_HEIGHT)
	end

	hunt(intro, clock)

	if not done.MusicDown and clock >= data.Stomp - Tune.MUSIC_DOWN_BEFORE then
		done.MusicDown = true
		MusicController.Duck(Tune.MUSIC_DUCK, Tune.MUSIC_DOWN_SECONDS)
	end

	if not done.MusicUp and clock >= data.Chomp + Tune.MUSIC_UP_AFTER then
		done.MusicUp = true
		MusicController.Duck(1, Tune.MUSIC_UP_SECONDS)
	end

	if not done.Stomp and clock >= data.Stomp then
		done.Stomp = true
		intro.Jolt = Tune.JOLT_STOMP
		flash(Tune.FLASH_STOMP)
		local floor, normal, color = floorAtFoot(intro, data.StompSide)
		if floor then
			trexFx.Stomp(floor, normal, color, Tune.STOMP_SIZE)
			trexFx.Wave(floor, Tune.STOMP_REACH, Tune.STOMP_WAVE_SPEED, Tune.STOMP_WAVE)
			trexSounds.Play("Stomp", floor)
		end
	end

	-- The roar's and the chomp's voices build before their beats (trexSounds.Lead); the clock runs at real time there.
	if not done.RoarVoice and clock >= data.Roar - trexSounds.Lead("Roar") then
		done.RoarVoice = true
		trexSounds.Play("Roar", bone(intro, "Head") or intro.Stage.Position + UP * Tune.LOOK_HEIGHT)
	end

	if not done.BiteVoice and clock >= data.Chomp - trexSounds.Lead("Bite") then
		done.BiteVoice = true
		trexSounds.Play("Bite", bone(intro, "Jaw") or intro.Stage.Position + UP * Tune.LOOK_HEIGHT)
	end

	if not done.Roar and clock >= data.Roar then
		done.Roar = true
		intro.Jolt = Tune.JOLT_ROAR
		flash(Tune.FLASH_ROAR)
		step(intro, "l", Tune.ROAR_FEET)
		step(intro, "r", Tune.ROAR_FEET)
		local floor, _, color = floorUnder(intro.Stage.Position)
		trexFx.Roar(mouth(intro), Tune.ROAR_RIDE, floor, color, Tune.ROAR_REACH)
	end

	if clock >= Tune.ROAR_FROM and clock <= Tune.ROAR_UNTIL then
		intro.Jolt = math.max(intro.Jolt, Tune.JOLT_ROARING)
	end

	-- The maw opens ahead of the bite and snaps shut on it.
	if not done.Maw and clock >= data.Chomp - trexFx.MawOpenSeconds then
		done.Maw = true
		local here = EnemiesController.GetCFrame(intro.InstanceId)
		local base = if here then here.Position else intro.Stage.Position
		local forward = intro.Stage.ZVector
		trexFx.Maw(base + forward * Tune.MAW_AHEAD + UP * Tune.MAW_HEIGHT, forward)
	end

	if not done.Chomp and clock >= data.Chomp then
		done.Chomp = true
		intro.Jolt = math.max(intro.Jolt, Tune.JOLT_CHOMP)
		flash(Tune.FLASH_CHOMP)
		local jaw = bone(intro, "Jaw")
		if jaw then trexFx.Bite(jaw, intro.Stage.ZVector) end
	end
end

-- ============================== The cutscene ==============================

local function finish(intro: TPlaying)
	playing = nil
	EnemiesController.Drive(intro.InstanceId, nil)
	EnemiesController.StopClip(intro.InstanceId, "Intro", 0.25)
	intro.Grade:Destroy()
	intro.Focus:Destroy()
	if intro.Done.MusicDown and not intro.Done.MusicUp then MusicController.Duck(1, Tune.MUSIC_UP_SECONDS) end
	CameraController.Script(nil, intro.Stage.Position + UP * Tune.LOOK_HEIGHT)
	BossIntroController.IsPlaying(false)
	titleAge(-1)
	endedAt = os.clock()
	isOverlayUp(true)
end

local function cameraStep(dt: number): (CFrame, number)
	local intro = playing
	if not intro then return Workspace.CurrentCamera.CFrame, Workspace.CurrentCamera.FieldOfView end
	local elapsed = os.clock() - intro.StartedAt
	local clock, clip, speed = BossesCore.IntroClock(intro.Intro, elapsed)
	intro.Clock = clock

	-- The clip follows the clock: slowed for the roar, held on its last pose.
	local track = intro.Track
	if track then
		if speed ~= intro.Speed then
			intro.Speed = speed
			track:AdjustSpeed(speed)
		end
		if math.abs(track.TimePosition - clip) > 0.06 then track.TimePosition = clip end
	end

	beats(intro, clock)
	intro.Jolt = math.max(intro.Jolt - dt * Tune.JOLT_DECAY, 0)
	flash(math.max(flash() - dt * Tune.FLASH_FADE, 0))
	bars(math.min(elapsed / Tune.BARS_SECONDS, 1))
	titleAge(clock - Tune.TITLE_AT)
	local data = intro.Intro
	black(math.clamp(1 - (data.End - clock) / Tune.FADE_OUT, 0, 1))

	-- The grade.
	local grade = intro.Grade
	grade.Saturation = keyed(Tune.SATURATION, clock)
	grade.Contrast = keyed(Tune.CONTRAST, clock)
	grade.TintColor = Tune.TINT_CALM:Lerp(Tune.TINT_ROAR, math.clamp(1 - math.abs(clock - 7.9) / 1.2, 0, 1))

	-- The shot, its handheld wander and the jolt of each beat.
	local scale = BossesCore.INTRO_KEY_SCALE
	local eye, look, fov, roll = evalShot(intro.Shots, clock)
	local worldEye = intro.Frame:PointToWorldSpace(eye * scale)
	local worldLook = intro.Frame:PointToWorldSpace(look * scale)
	local wander = keyed(Tune.HANDHELD, clock) * Tune.DRIFT_DEGREES
	local n = os.clock()
	local drift = CFrame.Angles(
		math.rad(math.noise(n * 0.7, 1.3) * wander),
		math.rad(math.noise(n * 0.6, 7.1) * wander),
		math.rad(math.noise(n * 0.5, 3.7) * wander / 2)
	)
	local jolt = intro.Jolt * intro.Jolt
	local kick = CFrame.new((math.random() - 0.5) * jolt * 0.5, (math.random() - 0.5) * jolt * 0.5, 0)
		* CFrame.Angles((math.random() - 0.5) * jolt * 0.06, (math.random() - 0.5) * jolt * 0.06, 0)
	intro.Focus.FocusDistance = (worldLook - worldEye).Magnitude

	local cframe = CFrame.lookAt(worldEye, worldLook) * CFrame.Angles(0, 0, math.rad(roll)) * drift * kick
	if clock >= data.End and not intro.IsEnding then
		intro.IsEnding = true
		task.defer(finish, intro)
	end
	return cframe, fov + intro.Jolt * Tune.JOLT_FOV
end

-- `startedAt`: when the server's hold began, as near as this side knows (the event's arrival), so the view is handed
-- back as the match lets go even when the rig was late.
local function begin(instanceId: number, enemyData: TData.TEnemy, stage: CFrame, startedAt: number)
	local kit = enemyData.Boss :: TData.TEnemyBoss
	local shots = BossesCore.INTRO_SHOTS[enemyData.AnimationSet]
	if not shots then return end

	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "BossIntroGrade"
	grade.Parent = Lighting
	local focus = Instance.new("DepthOfFieldEffect")
	focus.Name = "BossIntroFocus"
	focus.InFocusRadius = Tune.FOCUS_RADIUS
	focus.NearIntensity = Tune.NEAR_BLUR
	focus.FarIntensity = Tune.FAR_BLUR
	focus.Parent = Lighting

	local intro: TPlaying = {
		InstanceId = instanceId,
		Data = enemyData,
		Intro = kit.Intro,
		Shots = shots,
		Stage = stage,
		Frame = BossesCore.IntroFrame(stage, kit.Intro),
		StartedAt = startedAt,
		Track = nil,
		Clock = 0,
		Speed = 1,
		Jolt = 0,
		Done = {},
		Bones = {},
		HeadAt = nil,
		Grade = grade,
		Focus = focus,
		IsEnding = false,
	}
	playing = intro
	titleText(kit.Title)
	-- Spaced out, as delivered.
	subtitleText(table.concat(string.split(kit.Subtitle, ""), " "))
	EnemiesController.Drive(instanceId, function()
		return stage
	end)
	intro.Track = EnemiesController.PlayClip(
		instanceId,
		"Intro",
		{ Fade = 0, IsUnscaled = true, Priority = Enum.AnimationPriority.Action4 }
	)
	BossIntroController.IsPlaying(true)
	CameraController.Script(cameraStep)
end

-- The letterbox, the flashes, the black and the title card.
local function overlay()
	local font = Theme.Font
	local function shown(): number
		return math.clamp(titleAge() / Tune.TITLE_IN, 0, 1)
	end

	local function bar(isTop: boolean)
		return create("Frame")({
			Name = if isTop then "Top" else "Bottom",
			AnchorPoint = Vector2.new(0, if isTop then 0 else 1),
			Position = UDim2.fromScale(0, if isTop then 0 else 1),
			Size = function()
				local u = bars()
				return UDim2.fromScale(1, Tune.BARS * (1 - (1 - u) ^ 3))
			end,
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			ZIndex = 8,
		})
	end

	return create("ScreenGui")({
		Name = "BossIntro",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 50,
		Enabled = function()
			return BossIntroController.IsPlaying() or isOverlayUp()
		end,
		bar(true),
		bar(false),
		create("Frame")({
			Name = "Flash",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = function()
				return 1 - flash()
			end,
			BorderSizePixel = 0,
			ZIndex = 9,
		}),
		create("Frame")({
			Name = "Black",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = function()
				return 1 - black()
			end,
			BorderSizePixel = 0,
			ZIndex = 10,
		}),
		create("Frame")({
			Name = "Title",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.74),
			Size = UDim2.fromScale(0.7, 0.2),
			BackgroundTransparency = 1,
			ZIndex = 7,
			create("UIScale")({
				Scale = function()
					local u = shown()
					return Tune.TITLE_SCALE + (1 - Tune.TITLE_SCALE) * (1 - (1 - u) ^ 3)
				end,
			}),
			create("TextLabel")({
				Name = "Name",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0),
				Size = UDim2.fromScale(1, 0.62),
				BackgroundTransparency = 1,
				FontFace = font.Display,
				TextScaled = true,
				Text = titleText,
				TextColor3 = Color3.new(1, 1, 1),
				TextTransparency = function()
					return 1 - shown()
				end,
				ZIndex = 7,
				create("UIStroke")({
					Color = TITLE_INK,
					Thickness = 3,
					Transparency = function()
						return 1 - shown()
					end,
				}),
				create("UIGradient")({
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, GREEN),
						ColorSequenceKeypoint.new(0.5, Color3.fromRGB(235, 255, 240)),
						ColorSequenceKeypoint.new(1, GREEN),
					}),
					Offset = function()
						local u = math.clamp(titleAge() / Tune.SWEEP_SECONDS, 0, 1)
						return Vector2.new(-1 + 2 * ease("InOut", u), 0)
					end,
				}),
			}),
			create("Frame")({
				Name = "Line",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.7),
				Size = function()
					local u = math.clamp((titleAge() - Tune.SUBTITLE_AFTER) / Tune.TITLE_IN, 0, 1)
					return UDim2.new(0.55 * (1 - (1 - u) ^ 4), 0, 0, 2)
				end,
				BackgroundColor3 = Color3.fromRGB(120, 255, 160),
				BorderSizePixel = 0,
				ZIndex = 7,
			}),
			create("TextLabel")({
				Name = "Subtitle",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.78),
				Size = UDim2.fromScale(1, 0.2),
				BackgroundTransparency = 1,
				FontFace = font.Bold,
				TextScaled = true,
				Text = subtitleText,
				TextColor3 = Color3.fromRGB(200, 230, 210),
				TextTransparency = function()
					return 1 - math.clamp((titleAge() - Tune.SUBTITLE_AFTER) / Tune.TITLE_IN, 0, 1)
				end,
				ZIndex = 7,
			}),
		}),
	})
end

ServerNetworkBosses.Intro.On(function(instanceId: number, dataId: number, position: Vector3, yaw: number)
	local enemyData = ENEMIES[dataId]
	if not enemyData or not enemyData.Boss then return end
	if playing then finish(playing) end
	local stage = CFrame.new(position) * CFrame.Angles(0, yaw, 0)

	-- Its rig comes off the renderer's queue within a frame or two of its arrival.
	local waitedFrom = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.PreRender:Connect(function()
		local hasRig = EnemiesController.GetModel(instanceId) ~= nil
		if not hasRig and os.clock() - waitedFrom < Tune.RIG_WAIT then return end
		connection:Disconnect()
		begin(instanceId, enemyData, stage, waitedFrom)
	end)
end)

-- After the hand back: the black lifts off the player's own view and the bars slide away.
local function stepAfter()
	if not isOverlayUp() then return end
	local u = (os.clock() - endedAt) / Tune.FADE_IN
	if u >= 1 then
		black(0)
		bars(0)
		isOverlayUp(false)
		return
	end

	black(1 - u)
	bars(1 - u)
end

BossIntroController.OnStart = function()
	vide.mount(overlay, LocalPlayer:WaitForChild("PlayerGui"))
	RunService.PreRender:Connect(stepAfter)
end

return Ignis.Register(BossIntroController)
