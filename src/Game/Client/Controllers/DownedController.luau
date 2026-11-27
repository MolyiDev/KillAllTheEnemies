-- Being down, as every client draws it: any player's body bursting into a pile of bricks where it fell and built back
-- from it by a revive (Utils/reviveFx). For this client's own player it is also the down itself: the camera lifting
-- off the body and gliding to a standing squadmate's shoulder (the HUD's arrows step through them), the shock of it (the
-- world blurred and, on the HUD, dimmed, both clearing as the camera reaches the squadmate), the world drained of
-- colour and heard muffled, the pointer free for REVIVE, and the camera back over the pile to watch the body built. The
-- HUD draws its side from the fields below. Nothing is decided here: the server revives (CharacterService).
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local StarterPlayer = game:GetService("StarterPlayer")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Network = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Network)
local HealthController = require(script.Parent.HealthController)
local MatchController = require(script.Parent.MatchController)
local BossIntroController = require(script.Parent.BossIntroController)
local CameraController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.CameraController)
local reviveFx = require(script.Parent.Parent.Utils.reviveFx)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local getCharacterEntityFromPlayer =
	require(ReplicatedStorage.GlobalShared.Utils.Functions.getCharacterEntityFromPlayer)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local ServerNetworkCharacters = Network.Server.Characters
local LocalPlayer = Players.LocalPlayer
local UP = Vector3.yAxis

local Tune = table.freeze({
	FOV = 70,
	-- The camera lifting off the body: from where it was to over it, backed off and to one side, turning a little as
	-- it goes.
	LIFT_SECONDS = 1.85,
	LIFT_BACK = 13,
	LIFT_SIDE = 7,
	LIFT_UP = 15,
	LIFT_TURN = math.rad(-14),
	-- A squadmate's shoulder, the third-person framing the game holds a gun in; the camera eases onto it (and from one
	-- squadmate to the next) at this rate a second, and follows their facing at the slower one.
	SHOULDER_BACK = 11,
	SHOULDER_UP = 3.2,
	SHOULDER_SIDE = 2.6,
	LOOK_AHEAD = 26,
	LOOK_UP = 0.6,
	GLIDE_RATE = 5,
	FOLLOW_RATE = 4,
	-- Over the pile as the body is built: back, up and to the side of the feet (the R6 root's ROOT_HEIGHT under where it
	-- fell), looking at the middle of the body.
	ROOT_HEIGHT = 3,
	BUILD_BACK = 8.5,
	BUILD_UP = 8,
	BUILD_SIDE = 3,
	BUILD_LOOK_UP = 2.6,
	-- As the body shows the camera glides back behind it over RETURN_SECONDS, onto exactly where the PlayerModule
	-- takes over (CameraController.ReturnPose), so the hand-back is no cut.
	RETURN_SECONDS = 0.9,
	-- The world drained while the body lies there, partly back while watching a squadmate (the fight must read, but it
	-- is not yours), and back on the way to the rebuild.
	DRAINED = -0.75,
	WATCHING = -0.3,
	DIM = -0.05,
	COLOR_RATE = 2.5,
	-- A revived notice counts for the body that comes this soon after it.
	REVIVED_WITHIN = 5,
	-- The shock of going down, 0 to 1: in over SHOCK_IN, held while YOU DIED is in the middle, then cleared over
	-- SHOCK_OUT from SHOCK_OUT_AT (as the title flies off, the camera reaching the squadmate), or over SHOCK_CUT once the
	-- body is being built back. The world's blur at its height.
	SHOCK_IN = 0.25,
	SHOCK_OUT_AT = 2.05,
	SHOCK_OUT = 1.4,
	SHOCK_CUT = 0.4,
	SHOCK_BLUR = 20,
})

local DownedController = {}

-- This client's player is down in a run.
DownedController.IsDown = false
-- os.clock of going down, and of the last squadmate switch (an arrow, or the one watched gone).
DownedController.DownAt = -math.huge
DownedController.SwitchedAt = -math.huge
-- The squadmate the camera is on, nil while none stands.
DownedController.Watched = nil :: Player?
-- os.clock this client's body started being built back, and when it showed.
DownedController.RebuildAt = -math.huge
DownedController.StoodAt = -math.huge

local downAt = Vector3.zero
local liftFrom = CFrame.identity
local shown = CFrame.identity
local followLook: Vector3? = nil
local correction: ColorCorrectionEffect? = nil
-- Its own blur rather than BlurController's: it follows the shock frame by frame, in step with the HUD's dim.
local shockBlur: BlurEffect? = nil
-- A boss's intro takes the camera; the down takes it back as the intro ends.
local wasIntro = false
local saturation = 0
local isRebuilding = false
-- The camera's way back once the body shows: when it started, from where, and what it ends looking at.
local returnAt: number? = nil
local returnFrom = CFrame.identity
local returnLook = Vector3.zero
-- The players the server said are being revived, and when: their next body is built from their pile if it comes within
-- REVIVED_WITHIN (a revive whose body never came must not turn a later fresh one into a rebuild).
local revived: { [Player]: number } = {}

-- The squadmates standing, in a stable order (the arrows step through it).
function DownedController.Mates(): { Player }
	local mates = {}
	for _, player in Players:GetPlayers() do
		if player == LocalPlayer or HealthController.IsPlayerDown(player) then continue end
		if not getCharacterEntityFromPlayer(player) then continue end
		table.insert(mates, player)
	end
	table.sort(mates, function(a, b)
		return a.UserId < b.UserId
	end)

	return mates
end

-- How shocked the player still is by going down at `now`, 0 to 1 (the HUD's dim and the world's blur).
function DownedController.Shock(now: number): number
	if not DownedController.IsDown then return 0 end
	local since = now - DownedController.DownAt
	if since < 0 then return 0 end
	local t = math.min(since / Tune.SHOCK_IN, 1)
	local rise = 1 - (1 - t) * (1 - t)
	local u = math.clamp((since - Tune.SHOCK_OUT_AT) / Tune.SHOCK_OUT, 0, 1)
	local shock = rise * (1 - u * u * (3 - 2 * u))
	if DownedController.RebuildAt > DownedController.DownAt then
		shock *= 1 - math.clamp((now - DownedController.RebuildAt) / Tune.SHOCK_CUT, 0, 1)
	end

	return shock
end

-- Watches the next standing squadmate (`step` 1) or the one before (-1).
function DownedController.Spectate(step: number)
	if not DownedController.IsDown or isRebuilding then return end
	local mates = DownedController.Mates()
	if #mates == 0 then return end
	local index = table.find(mates, DownedController.Watched :: Player) or 0
	DownedController.Watched = mates[(index - 1 + step) % #mates + 1]
	DownedController.SwitchedAt = os.clock()
end

local function rootOf(player: Player): BasePart?
	local characterEntity = getCharacterEntityFromPlayer(player)
	return if characterEntity then World:get(characterEntity, Components.HumanoidRootPart) else nil
end

local function flatLook(cframe: CFrame): Vector3
	local look = cframe.LookVector * Vector3.new(1, 0, 1)
	return if look.Magnitude > 1e-3 then look.Unit else -Vector3.zAxis
end

-- Over the body, backed off the way the camera faced as it went down and turned `share` of LIFT_TURN round it.
local function liftedOver(at: Vector3, share: number): CFrame
	local back = -flatLook(liftFrom)
	local side = back:Cross(UP)
	local turn = CFrame.new(at) * CFrame.Angles(0, Tune.LIFT_TURN * share, 0) * CFrame.new(-at)
	return turn * CFrame.lookAt(at + back * Tune.LIFT_BACK + side * Tune.LIFT_SIDE + UP * Tune.LIFT_UP, at)
end

local function shoulderOf(root: BasePart, dt: number): CFrame
	local look = flatLook(root.CFrame)
	local held = followLook or look
	held = held:Lerp(look, 1 - math.exp(-dt * Tune.FOLLOW_RATE))
	if held.Magnitude > 1e-3 then held = held.Unit end
	followLook = held
	local right = held:Cross(UP)
	local base = root.Position
	local eye = base + UP * Tune.SHOULDER_UP - held * Tune.SHOULDER_BACK + right * Tune.SHOULDER_SIDE
	return CFrame.lookAt(eye, base + UP * Tune.LOOK_UP + held * Tune.LOOK_AHEAD + right * Tune.SHOULDER_SIDE)
end

-- The down camera, a frame at a time (CameraController.Script).
local function cameraStep(dt: number): (CFrame, number)
	local now = os.clock()
	local since = now - DownedController.DownAt
	local goal
	local startedBack = returnAt
	if startedBack then
		local pose, fov = CameraController.ReturnPose(returnLook)
		local t = math.clamp((now - startedBack) / Tune.RETURN_SECONDS, 0, 1)
		t = t * t * t * (t * (t * 6 - 15) + 10)
		if pose then shown = returnFrom:Lerp(pose, t) end
		return shown, Tune.FOV + (fov - Tune.FOV) * t
	elseif isRebuilding then
		local back = -flatLook(shown)
		local side = back:Cross(UP)
		local feet = downAt - UP * Tune.ROOT_HEIGHT
		goal = CFrame.lookAt(
			feet + back * Tune.BUILD_BACK + side * Tune.BUILD_SIDE + UP * Tune.BUILD_UP,
			feet + UP * Tune.BUILD_LOOK_UP
		)
	elseif since < Tune.LIFT_SECONDS then
		local t = math.clamp(since / Tune.LIFT_SECONDS, 0, 1)
		t = t * t * (3 - 2 * t)
		shown = liftFrom:Lerp(liftedOver(downAt, t), t)
		return shown, Tune.FOV
	else
		local watched = DownedController.Watched
		local root = if watched then rootOf(watched) else nil
		goal = if root then shoulderOf(root, dt) else liftedOver(downAt, 1)
	end
	shown = shown:Lerp(goal, 1 - math.exp(-dt * Tune.GLIDE_RATE))

	return shown, Tune.FOV
end

-- This client's player just went down.
local function goDown(root: BasePart?)
	local camera = Workspace.CurrentCamera
	DownedController.IsDown = true
	DownedController.DownAt = os.clock()
	DownedController.Watched = DownedController.Mates()[1]
	downAt = if root then root.Position else camera.Focus.Position
	liftFrom = camera.CFrame
	shown = liftFrom
	followLook = nil
	isRebuilding = false
	returnAt = nil
	CameraController.SetMouseFreed("Down", true)
	-- Down during a boss's intro, the intro keeps the camera; it is the down's as the intro hands it back (stepIntro).
	if not BossIntroController.IsPlaying() then CameraController.Script(cameraStep) end
	SoundsCore.SetMuffled("Down", true)
	if not correction then
		local effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "Downed"
		effect.Parent = Lighting
		correction = effect
	end
end

-- The new body shows: the camera starts back behind it.
local function stood()
	local now = os.clock()
	DownedController.StoodAt = now
	local root = rootOf(LocalPlayer)
	returnAt = now
	returnFrom = shown
	returnLook = if root then root.Position + flatLook(shown) * Tune.LOOK_AHEAD else shown.Position + shown.LookVector
end

-- Back behind the body: the camera handed over where it already is, the down over.
local function handBack()
	returnAt = nil
	isRebuilding = false
	DownedController.IsDown = false
	CameraController.SetMouseFreed("Down", false)
	local characterEntity = getCharacterEntityFromPlayer(LocalPlayer)
	local humanoid = if characterEntity then World:get(characterEntity, Components.Humanoid) else nil
	-- The camera follows the new body: a respawn under a scripted camera leaves the subject on the old one.
	if humanoid then Workspace.CurrentCamera.CameraSubject = humanoid end
	CameraController.Script(nil, returnLook)
end

-- The world blurred by the shock, out of the renderer once clear. None over a boss's intro, which is the fight's.
local function stepShock(now: number, isIntro: boolean)
	local amount = if isIntro then 0 else DownedController.Shock(now)
	if amount > 0.005 then
		local blur = shockBlur
		if not blur then
			blur = Instance.new("BlurEffect")
			blur.Name = "DownedShock"
			blur.Parent = Lighting
			shockBlur = blur
		end
		blur.Size = Tune.SHOCK_BLUR * amount
	elseif shockBlur then
		shockBlur:Destroy()
		shockBlur = nil
	end
end

-- A boss's intro handed the camera back as a player's own; while down it is the down's again, gliding on from there.
local function stepIntro(isIntro: boolean)
	if wasIntro and not isIntro and DownedController.IsDown then
		shown = Workspace.CurrentCamera.CFrame
		followLook = nil
		CameraController.Script(cameraStep)
	end
	wasIntro = isIntro
end

local function step(dt: number)
	reviveFx.Step(dt)
	local now = os.clock()
	local startedBack = returnAt
	if startedBack and now - startedBack >= Tune.RETURN_SECONDS then handBack() end
	local isIntro = BossIntroController.IsPlaying()
	stepIntro(isIntro)
	stepShock(now, isIntro)

	if DownedController.IsDown then
		local watched = DownedController.Watched
		if not isRebuilding and (not watched or not watched.Parent or HealthController.IsPlayerDown(watched)) then
			local mates = DownedController.Mates()
			if mates[1] ~= watched then
				DownedController.Watched = mates[1]
				DownedController.SwitchedAt = now
			end
		end
	end

	local effect = correction
	if not effect then return end
	local since = now - DownedController.DownAt
	-- A boss's intro is graded for everyone alike.
	local target = if not DownedController.IsDown
			or isRebuilding
			or isIntro
		then 0
		elseif since < Tune.LIFT_SECONDS or not DownedController.Watched then Tune.DRAINED
		else Tune.WATCHING
	saturation += (target - saturation) * (1 - math.exp(-dt * Tune.COLOR_RATE))
	effect.Saturation = saturation
	effect.Brightness = Tune.DIM * (saturation / Tune.DRAINED)
	if not DownedController.IsDown and math.abs(saturation) < 0.01 then
		effect:Destroy()
		correction = nil
		saturation = 0
	end
end

HealthController.OnBodyDown:Connect(function(player: Player, character: Model)
	reviveFx.Crumble(player, character)
	if player ~= LocalPlayer or not MatchController.IsRunning then return end
	goDown(character:FindFirstChild("HumanoidRootPart") :: BasePart?)
end)

ServerNetworkCharacters.Revived.On(function(player: Player)
	revived[player] = os.clock()
end)

-- A new body the server said is a revive is built from the pile; any other (a run started over) is a fresh one and the
-- pile goes.
DownedController.OnCharacterAdded = function(character, _)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end
	local revivedAt = revived[player]
	local isRevive = revivedAt ~= nil and os.clock() - revivedAt < Tune.REVIVED_WITHIN
	revived[player] = nil
	if not isRevive then reviveFx.Clear(player) end
	local isOwn = player == LocalPlayer and DownedController.IsDown
	local isBuilt = isRevive
		and reviveFx.Rebuild(player, character, character.HumanoidRootPart, if isOwn then stood else nil)
	if not isOwn then return end

	-- The down is over either way: built from the pile (the camera hands back as it shows), or fresh (at once).
	isRebuilding = true
	DownedController.RebuildAt = os.clock()
	SoundsCore.SetMuffled("Down", false)
	if not isBuilt then stood() end
end :: TCharacterEvents.OnCharacterAdded

DownedController.OnPlayerDisconnected = function(player: Player)
	revived[player] = nil
	reviveFx.Clear(player)
end :: TPlayerEvents.OnPlayerDisconnected

DownedController.OnStart = function()
	RunService.PreRender:Connect(step)
end

return Ignis.Register(DownedController)
