-- The Giant Spider's moves as this client plays them (BossController routes them here): each clip's beats thrown off
-- the body at the clip's own timing, its leap drawn on the server's arc, its web, its brood's line and drop, its sacs
-- hatching, and a footfall wherever its IK legs come down. Every spot is the server's (its attacks' Strikes, the
-- landing it sends), so the effect lands on the warning. Its look is Utils/spiderFx, its voice Utils/spiderSounds.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EnemiesController = require(script.Parent.Parent.EnemiesController)
local spiderFx = require(script.Parent.Parent.Parent.Utils.spiderFx)
local spiderLegs = require(script.Parent.Parent.Parent.Utils.spiderLegs)
local spiderSounds = require(script.Parent.Parent.Parent.Utils.spiderSounds)
local trexFx = require(script.Parent.Parent.Parent.Utils.trexFx)
local BossesCore = require(ReplicatedStorage.Shared.Core.BossesCore)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)
local TData = require(ReplicatedStorage.Types.TData)
local Types = require(script.Parent.Types)

local Spider = {}

local UP = Vector3.yAxis
local floorUnder = trexFx.FloorUnder

local Tune = table.freeze({
	-- Shakes (magnitude, seconds[, kick]), as BossController's: a blade biting the floor, a stab, a footfall, its
	-- leap's takeoff and landing, the drop onto its belly, a glob landing, a sac hatching.
	BLADE = { 1.5, 0.3, 0.26 },
	STAB = { 0.9, 0.22, 0.12 },
	STEP = { 0.3, 0.2 },
	TAKEOFF = { 1.2, 0.3, 0.15 },
	LAND = { 3.6, 0.55, 0.55 },
	DROP = { 4.2, 0.6, 0.7 },
	GLOB = { 0.7, 0.22, 0.08 },
	HATCH = { 1.4, 0.35, 0.18 },
	-- A stab's spot bursts as a short red slash this long, outward from its body.
	STAB_SLASH = 1.6,
	-- A footfall throws this much of a T-Rex step's dust, and is heard every few landings.
	STEP_STRENGTH = 0.4,
	STEP_SOUND_EVERY = 2,
	-- Its leap's and its drop's landings: the stamp's size and its wave out over the floor.
	LAND_SIZE = 0.9,
	LAND_WAVE_SPEED = 45,
	DROP_SIZE = 1.25,
	DROP_WAVE_SPEED = 40,
	-- The line runs up from its spinnerets into the sky this fast as it is shot (studs a second).
	SHOOT_SPEED = 320,
	-- A pounce's crouch draws in and scrapes the floor this far into its clip.
	CROUCH_AT = 0.3,
})

-- The bones whose turn the hurt rears it by (BossController.poseHurts): the thorax back off its front legs, head and
-- jaws thrown up, the abdomen swung down and away from the shots.
Spider.HURT_POSE = table.freeze({
	{ Bone = "Thorax", Pitch = -0.12, Yaw = 0.08, Lag = 0 },
	{ Bone = "Head", Pitch = -0.2, Yaw = 0.1, Lag = 0.05 },
	{ Bone = "Chelicera_L", Pitch = -0.35, Yaw = 0, Lag = 0.07 },
	{ Bone = "Chelicera_R", Pitch = -0.35, Yaw = 0, Lag = 0.07 },
	{ Bone = "Abdomen", Pitch = 0.16, Yaw = -0.12, Lag = 0.06 },
	{ Bone = "Tail", Pitch = 0.12, Yaw = -0.14, Lag = 0.12 },
})

local feetScratch: { Vector3 } = {}

-- ============================== Helpers ==============================

-- A spot in the body's frame (+X its left, +Z ahead) in the world, for the body at `from` facing `yaw`.
local function pointOf(from: Vector3, yaw: number, spot: Vector3): Vector3
	local c, s = math.cos(yaw), math.sin(yaw)
	return Vector3.new(from.X + spot.X * c + spot.Z * s, from.Y + spot.Y, from.Z - spot.X * s + spot.Z * c)
end

local function frameOf(boss: Types.TBoss): CFrame?
	return EnemiesController.GetCFrame(boss.InstanceId)
end

-- Its spinnerets (TEnemyBoss.Spinnerets), or its abdomen while the rig has no tail.
local function spinnerets(api: Types.TApi, boss: Types.TBoss): Vector3?
	local tail = api.BoneFrame(boss, "Tail")
	if not tail then return api.BonePosition(boss, "Abdomen") end
	return tail:PointToWorldSpace(boss.Kit.Spinnerets or Vector3.zero)
end

-- Its head, or over its middle while the rig is missing.
local function headOf(api: Types.TApi, boss: Types.TBoss): Vector3?
	local head = api.BonePosition(boss, "Head")
	if head then return head end
	local here = frameOf(boss)
	return if here then here.Position + UP * 6 else nil
end

-- ============================== Blades ==============================

-- Each blade's strike at its moment: a gash cut along its line on the floor, sparks and dust where it bit, and the
-- shake; the whoosh builds into it.
local function blades(
	api: Types.TApi,
	boss: Types.TBoss,
	attack: TData.TEnemyAttack,
	from: Vector3,
	yaw: number,
	tempo: number
)
	local strikes = attack.Strikes
	if not strikes then return end
	local now = TimeCore.EnemyClock
	local heard: { [number]: boolean } = {}
	for _, strike in strikes do
		local at = strike.At
		local to = strike.To
		local hit = pointOf(from, yaw, strike.From)
		local rake = if to then pointOf(from, yaw, to) else hit
		if not heard[at] then
			heard[at] = true
			api.Schedule(boss, now + at * tempo - spiderSounds.Lead("Whoosh"), function()
				spiderSounds.Play("Whoosh", headOf(api, boss) or hit, boss.InstanceId)
			end)
			api.Schedule(boss, now + at * tempo, function()
				spiderSounds.Play("BladeHit", hit, boss.InstanceId)
				api.Shake(hit, Tune.BLADE)
			end)
		end
		api.Schedule(boss, now + at * tempo, function()
			local floorHit, normal, color = floorUnder(hit)
			local floorRake = floorUnder(rake)
			if not floorHit then return end
			spiderFx.Gash(floorHit, floorRake or floorHit)
			trexFx.Scrape(floorHit, normal, color, rake - hit)
			trexFx.Footfall(floorHit, normal, color, 0.8)
		end)
	end
end

-- Each stab at its moment: a short slash outward from its body where the foot goes in, its dust and bricks.
local function stabs(
	api: Types.TApi,
	boss: Types.TBoss,
	attack: TData.TEnemyAttack,
	from: Vector3,
	yaw: number,
	tempo: number
)
	local strikes = attack.Strikes
	if not strikes then return end
	local now = TimeCore.EnemyClock
	spiderSounds.Play("Rear", headOf(api, boss) or from, boss.InstanceId)
	for _, strike in strikes do
		local spot = pointOf(from, yaw, strike.From)
		api.Schedule(boss, now + strike.At * tempo, function()
			local floor, normal, color = floorUnder(spot)
			if not floor then return end
			local out = Vector3.new(floor.X - from.X, 0, floor.Z - from.Z)
			local along = if out.Magnitude > 1e-3 then out.Unit else Vector3.zAxis
			spiderFx.Gash(floor - along * (Tune.STAB_SLASH / 2), floor + along * (Tune.STAB_SLASH / 2))
			trexFx.Footfall(floor, normal, color, 1.2)
			spiderSounds.Play("Stab", floor, boss.InstanceId)
			api.Shake(floor, Tune.STAB)
		end)
	end
end

-- ============================== The brood ==============================

-- Up its line: shot into the sky from its spinnerets at BroodShoot, the line held until its drop lets go, the hang
-- looping on from the end of the rise.
local function rise(api: Types.TApi, boss: Types.TBoss, from: Vector3)
	local kit = boss.Kit
	local id = boss.InstanceId
	local now = TimeCore.EnemyClock
	local shootAt = now + (kit.BroodShoot or 0.55)
	api.Schedule(boss, shootAt, function()
		local here = frameOf(boss)
		local base = spinnerets(api, boss) or from
		spiderSounds.Play("Shoot", base, boss.InstanceId)
		api.Shake(base, Tune.STAB)
		boss.IsThreaded = true
		local threadAt = if here and kit.BroodThread then here:PointToWorldSpace(kit.BroodThread) else base
		local sky = threadAt + UP * spiderFx.THREAD_SKY
		spiderFx.Thread(function()
			if not boss.IsThreaded then return nil, nil end
			local body = spinnerets(api, boss)
			if not body then return nil, nil end
			-- Shot up out of the spinnerets, then held where it caught.
			local reach = (TimeCore.EnemyClock - shootAt) * Tune.SHOOT_SPEED
			local top = (sky - body).Magnitude
			return if reach >= top then sky else body + (sky - body).Unit * reach, body
		end)
	end)
	api.Schedule(boss, now + (kit.BroodRiseLength or 2.4), function()
		if boss.IsThreaded then EnemiesController.PlayClip(id, "BroodHang", { Fade = 0.1, IsLooped = true }) end
	end)
end

-- ============================== Moves ==============================

-- One of its attacks begun (its clip already playing, BossController): what each clip throws, when.
function Spider.OnAttack(
	api: Types.TApi,
	boss: Types.TBoss,
	attack: TData.TEnemyAttack,
	from: Vector3,
	yaw: number,
	tempo: number
)
	local name = attack.AnimationName
	local now = TimeCore.EnemyClock
	if name == "ScytheCross" or name == "ScytheFlurry" then
		spiderSounds.Play("Rear", headOf(api, boss) or from, boss.InstanceId)
		blades(api, boss, attack, from, yaw, tempo)
	elseif name == "Impale" or name == "Impale2" then
		stabs(api, boss, attack, from, yaw, tempo)
	elseif attack.Kind == "Pounce" then
		api.Schedule(boss, now + Tune.CROUCH_AT * tempo, function()
			spiderSounds.Play("Crouch", headOf(api, boss) or from, boss.InstanceId)
			local floor, normal, color = floorUnder(from)
			if floor then trexFx.Scrape(floor, normal, color, api.Facing(boss)) end
		end)
	elseif attack.IsVolley then
		spiderSounds.Play("Rear", spinnerets(api, boss) or from, boss.InstanceId)
	elseif attack.Kind == "Brood" then
		rise(api, boss, from)
	end
end

-- Off the floor at `from`, onto `to` in `seconds`, on the server's arc; down with a stamp, its wave out to the
-- pounce's circle and the hardest shake of its moves.
function Spider.OnLeap(
	api: Types.TApi,
	boss: Types.TBoss,
	attack: TData.TEnemyAttack,
	from: Vector3,
	to: Vector3,
	seconds: number
)
	local id = boss.InstanceId
	local startedAt = TimeCore.EnemyClock
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local yaw = if flat.Magnitude > 1e-3 then math.atan2(flat.X, flat.Z) else 0
	EnemiesController.StopClip(id, "PounceCrouch", 0.05)
	EnemiesController.PlayClip(id, "PounceAir", { Fade = 0.08, IsLooped = true })
	EnemiesController.Drive(id, function(now: number): CFrame?
		local u = (now - startedAt) / seconds
		if u >= 1 then return nil end
		local at = BossesCore.LeapPoint(from :: any, to :: any, u) :: any
		return CFrame.new(at) * CFrame.Angles(0, yaw, 0)
	end)

	local floor, normal, color = floorUnder(from)
	if floor then trexFx.Footfall(floor, normal, color, 1.5) end
	spiderSounds.Play("Whoosh", from, boss.InstanceId)
	api.Shake(from, Tune.TAKEOFF)

	api.Schedule(boss, startedAt + seconds, function()
		EnemiesController.StopClip(id, "PounceAir", 0)
		EnemiesController.PlayClip(id, "PounceLand", { Fade = 0.05 })
		local landing, landNormal, landColor = floorUnder(to)
		local at = landing or to
		spiderSounds.Play("Land", at, boss.InstanceId)
		api.Shake(at, Tune.LAND)
		if not landing then return end
		trexFx.Stomp(landing, landNormal, landColor, Tune.LAND_SIZE)
		trexFx.Wave(landing, attack.Radius or 11, Tune.LAND_WAVE_SPEED)
	end)
end

-- Its brood over: the hang let go so the drop lands on its belly at `to` in `seconds`, the line snapping as it
-- falls, its wave out to the drop's circle, then dazed.
function Spider.OnDrop(api: Types.TApi, boss: Types.TBoss, attack: TData.TEnemyAttack, to: Vector3, seconds: number)
	local kit = boss.Kit
	local id = boss.InstanceId
	local now = TimeCore.EnemyClock
	local land = kit.BroodLand or 0.66
	api.Schedule(boss, now + math.max(seconds - land, 0), function()
		EnemiesController.StopClip(id, "BroodHang", 0.05)
		EnemiesController.StopClip(id, "BroodRise", 0.05)
		EnemiesController.PlayClip(id, "BroodDrop", { Fade = 0.08 })
		local base = spinnerets(api, boss)
		boss.IsThreaded = false
		if base then
			trexFx.Snap(base)
			spiderSounds.Play("ThreadSnap", base, boss.InstanceId)
		end
		spiderSounds.Play("Drop", to, boss.InstanceId)
	end)

	api.Schedule(boss, now + seconds, function()
		local floor, normal, color = floorUnder(to)
		local at = floor or to
		spiderSounds.Play("Land", at, boss.InstanceId)
		api.Shake(at, Tune.DROP)
		if floor then
			trexFx.Stomp(floor, normal, color, Tune.DROP_SIZE)
			trexFx.Wave(floor, attack.Radius or 12, Tune.DROP_WAVE_SPEED)
		end
		local dazed = (kit.BroodDropLength or 2.8) - land + BossesCore.BROOD_DAZE
		spiderFx.Daze(function()
			return headOf(api, boss)
		end, dazed)
	end)
end

-- A sac at `at` burst and its young came out.
function Spider.OnHatch(api: Types.TApi, at: Vector3)
	spiderFx.Hatch(at)
	spiderSounds.Play("Hatch", at)
	api.Shake(at, Tune.HATCH)
	local floor, normal, color = floorUnder(at)
	if floor then trexFx.Sink(floor, normal, color, 0.7) end
end

-- A sac popped by the players.
function Spider.OnSacGone(at: Vector3)
	spiderFx.Pop(at)
end

-- One glob of a volley, spat at its beat off the raised abdomen, landing on `to` as the warning there resolves and
-- leaving its sticky patch.
function Spider.OnGlob(api: Types.TApi, boss: Types.TBoss, attack: TData.TEnemyAttack, to: Vector3, seconds: number)
	local flight = attack.Flight or 0.8
	local startedAt = TimeCore.EnemyClock + math.max(seconds - flight, 0)
	api.Schedule(boss, startedAt, function()
		local from = spinnerets(api, boss) or to + UP * 14
		spiderSounds.Play("Spit", from, boss.InstanceId)
		spiderFx.Glob(from, to, flight, function(landed: Vector3)
			local floor, normal = floorUnder(landed)
			local at = floor or landed
			spiderFx.Splat(at)
			spiderSounds.Play("GlobLand", at, boss.InstanceId)
			api.Shake(at, Tune.GLOB)
			if floor and attack.PatchRadius and attack.PatchSeconds then
				spiderFx.Patch(floor, normal, attack.PatchRadius, attack.PatchSeconds)
			end
		end)
	end)
end

-- A frame of it: a footfall for every leg group its IK puts down.
function Spider.Step(api: Types.TApi, boss: Types.TBoss)
	local legs = EnemiesController.GetLegs(boss.InstanceId)
	if not legs or legs.Landings == boss.LegLandings then return end
	boss.LegLandings = legs.Landings
	if legs.Weight < 0.5 then return end
	local feet = spiderLegs.FeetOf(legs, legs.LandedGroup, feetScratch)
	for _, foot in feet do
		local floor, normal, color = floorUnder(foot)
		if floor then trexFx.Footfall(floor, normal, color, Tune.STEP_STRENGTH) end
	end
	local here = frameOf(boss)
	if not here then return end
	api.Shake(here.Position, Tune.STEP)
	if legs.Landings % Tune.STEP_SOUND_EVERY == 0 then spiderSounds.Play("Step", here.Position, boss.InstanceId) end
end

return Spider
