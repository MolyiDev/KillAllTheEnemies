-- The lobby's shooting range on this client (RangeCore). The shooting is the match's own (WeaponController and the
-- rest of GlobalClient: the first person, the recoil and shake, the body's jolt, the crosshair and its markers, the
-- damage numbers); this adds what only the range has:
--   - its dummies drawn where the server has them (some swaying side to side), each an EnemyWorld row the guns aim at,
--     answering every blow (RangeService's Range.Hit) as an enemy does: the white flash, the jolt away from the
--     shooter, the stand-in monster's bursts and sounds, and a killed one knocked flat and back up;
--   - the strip of the guns the range offers across the bottom while the player stands in it and no lobby screen is up
--     (Strip): their loadout, or only the gun TRY brought;
--   - the weapons screen's TRY: the screen covers over, the player is stood in a booth facing the targets with that gun.
--
-- The engine draws at most 255 Highlights; the lobby has no enemies, so the dummies' twelve flashes are its only ones.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local jecs = require(ReplicatedStorage.Packages.jecs)
local vide = require(ReplicatedStorage.Packages.vide)
local Network = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Network)
local CharacterController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.CharacterController)
local WeaponController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.WeaponController)
local EnemyImpacts = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Utils.enemyImpacts)
local gunFx = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Utils.gunFx)
local targetHits = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Utils.targetHits)
local CharacterCore = require(ReplicatedStorage.GlobalShared.Core.CharacterCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local RangeCore = require(ReplicatedStorage.Shared.Core.RangeCore)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local Tags = require(ReplicatedStorage.GlobalShared.ECS.Tags)
local EnemyWorld = require(ReplicatedStorage.GlobalShared.ECS.Worlds.EnemyWorld)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)
local TData = require(ReplicatedStorage.Types.TData)
local Strip = require(script.Strip)
local Types = require(script.Types)

local ServerNetworkRange = Network.Server.Range
local ClientNetworkRange = Network.Client.Range
local LocalPlayer = Players.LocalPlayer
local source = vide.source

local TAU = math.pi * 2
local V3_YAXIS = Vector3.yAxis
local FLAT_XZ = Vector3.new(1, 0, 1)
-- Called per dummy every frame, so hoisted out of its module.
local feetOf = RangeCore.Feet

local Tune = table.freeze({
	-- The dummies are drawn while the camera is this close to the range's middle.
	DRAW_DISTANCE = 320,
	-- Looked for again this often until the range has streamed in.
	GATHER_RETRY_SECONDS = 1,
	-- The hit flash (EnemiesController's): white, gone in this long.
	FLASH_TIME = 0.12,
	-- The jolt of a hit, as an enemy's (EnemiesController): a lean away from the shooter on the feet, a push and a
	-- sideways shake. A hit inside RETRIGGER of the last does not restart it.
	FLINCH_ANGLE = math.rad(24),
	FLINCH_PUSH = 0.8,
	FLINCH_SPEED = 24,
	FLINCH_DAMPER = 0.32,
	FLINCH_SHAKE_TIME = 0.22,
	FLINCH_SHAKE_SPEED = 95,
	FLINCH_SHAKE_STUDS = 0.45,
	FLINCH_RETRIGGER = 0.22,
	-- A body's hit sound plays at most once in this long; the flash shows every hit.
	HIT_SOUND_DEBOUNCE = 0.5,
	-- Flat on its back is this far over; it lands with a bounce this high (share of the way back up) that dies at
	-- this rate, ringing this fast. An overkill throws it over in this share of the time.
	FLAT = math.rad(88),
	BOUNCE = 0.14,
	BOUNCE_SPEED = 26,
	BOUNCE_DAMPER = 9,
	OVERKILL_FALL_SHARE = 0.6,
	-- A pick (or TRY) the server has not answered in this long gives way to the gun really in hand: a pick it let go
	-- (RangeService's PICK_SECONDS) must not leave the strip showing another gun.
	PICK_ANSWER_SECONDS = 0.6,
	-- TRY waits this long for the player to stand in a booth before it opens the cover anyway; a player this close to
	-- one stands in it.
	TRY_TIMEOUT = 2,
	TRY_BOOTH_STUDS = 4,
	-- The camera put behind the player as TRY lands: this far back and up, looking this far down the range.
	TRY_CAMERA_BACK = 11,
	TRY_CAMERA_UP = 4,
	TRY_CAMERA_AHEAD = 30,
	DISPLAY_ORDER = 4,
	COVER_DISPLAY_ORDER = 20,
})

type TBody = {
	Dummy: RangeCore.TDummy,
	Entity: jecs.Entity<any>,
	Look: TData.TEnemy,
	Flash: Highlight,
	FlashEndsAt: number,
	-- The Flash is lit, so the frame fades it rather than reading it back off the Highlight.
	IsFlashing: boolean,
	FlinchAt: number,
	Away: Vector3,
	DownAt: number,
	IsOverkill: boolean,
	IsAiming: boolean,
	HitSoundAt: number,
	-- Drawn at rest last frame: a still dummy is not moved again until something moves it.
	IsAtRest: boolean,
}

local RangeController = {}

local state: Types.TRangeState = {
	Scale = source(1),
	Now = source(os.clock()),
	IsInside = source(false),
	IsUp = source(false),
	UpAt = source(-math.huge),
	Shown = source({} :: { number }),
	Held = source(0),
	HeldAt = source(-math.huge),
	CoverAt = source(-math.huge),
	UncoverAt = source(-math.huge),
}

local bodies: { TBody } = {}
local nextGatherAt = 0
local selfRoot: BasePart? = nil
-- os.clock until which Now keeps ticking.
local motionUntil = -math.huge
-- The gun WeaponController last said is in hand, so the strip follows the server's word, and when the strip last
-- showed one in hand ahead of it.
local lastGun: TData.TGun? = nil
local heldAheadAt = -math.huge
-- TRY's trip while one runs (tryGun 0 between trips): the gun, when to ask for it (the cover closed), whether it was
-- asked for, and when to stop waiting for the player to stand in a booth.
local tryGun = 0
local tryAskAt = 0
local hasAskedTry = false
local tryGiveUpAt = 0
-- The server took its offer back; the strip lets it go once it has dropped away.
local isOfferWithdrawn = false
-- A lobby screen is up (LobbyController's word, through SetCovered).
local isCovered = false
-- Scratch for one BulkMoveTo a frame.
local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}

-- Whether the local player stands in the range. Reads a vide source, so a view that calls it follows it.
function RangeController.IsInside(): boolean
	return state.IsInside()
end

local function stamp(at: Types.Source<number>, moment: number)
	at(moment)
	motionUntil = math.max(motionUntil, moment + Strip.SETTLED)
end

-- The strip is up while the player stands in the range and no lobby screen covers it, so a screen shut after walking
-- out does not bring it back.
local function updateUp(now: number)
	local isUp = state.IsInside() and not isCovered
	if isUp == state.IsUp() then return end
	vide.batch(function()
		state.IsUp(isUp)
		stamp(state.UpAt, now)
	end)
end

-- A lobby screen opened or shut: the strip drops away under it as the lobby HUD does, and rises again as it shuts.
function RangeController.SetCovered(isCoveredNow: boolean)
	isCovered = isCoveredNow
	updateUp(os.clock())
end

local function hold(gunId: number)
	if state.Held() == gunId then return end
	vide.batch(function()
		state.Held(gunId)
		stamp(state.HeldAt, os.clock())
	end)
end

-- Shows `gunId` in hand before the server's Weapons.Equipped says so.
local function holdAhead(gunId: number)
	heldAheadAt = os.clock()
	hold(gunId)
end

-- Takes the local player to a free booth of the range holding `gunId`, any gun (RangeService decides).
function RangeController.Try(gunId: number)
	local now = os.clock()
	tryGun = gunId
	tryAskAt = now + Strip.COVER_IN
	hasAskedTry = false
	stamp(state.CoverAt, now)
end

-- Picks a gun off the strip: shown in hand at once, held as soon as the server hands it over.
local function pick(gunId: number)
	if state.Held() == gunId or not table.find(state.Shown(), gunId) then return end
	SoundsCore.PlayClick()
	holdAhead(gunId)
	ClientNetworkRange.Pick.Fire(gunId)
end

local function step(by: number)
	local shown = state.Shown()
	if #shown < 2 then return end
	local index = table.find(shown, state.Held()) or 1
	pick(shown[(index - 1 + by) % #shown + 1])
end

local function pickSlot(index: number)
	local gunId = state.Shown()[index]
	if gunId then pick(gunId) end
end

local actions: Types.TRangeActions = {
	Pick = pick,
}

-- ============================== Dummies ==============================

local function gather()
	local dummies = RangeCore.GatherDummies()
	if #dummies == 0 then return end

	for _, dummy in dummies do
		local highlight = Instance.new("Highlight")
		highlight.Name = "Flash"
		highlight.FillColor = Color3.new(1, 1, 1)
		-- Resting: invisible, and an invisible highlight renders for free.
		highlight.FillTransparency = 1
		highlight.OutlineTransparency = 1
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = dummy.Model

		local entity = EnemyWorld:entity()
		EnemyWorld:set(entity, Components.CFrame, dummy.Home)
		EnemyWorld:set(entity, Components.AimShape, dummy.Aim)
		EnemyWorld:add(entity, Tags.Enemy)

		bodies[dummy.Index] = {
			Dummy = dummy,
			Entity = entity,
			Look = RangeCore.LookOf(dummy),
			Flash = highlight,
			FlashEndsAt = -math.huge,
			IsFlashing = false,
			FlinchAt = -math.huge,
			Away = Vector3.zero,
			DownAt = -math.huge,
			IsOverkill = false,
			IsAiming = true,
			HitSoundAt = -math.huge,
			IsAtRest = false,
		}
	end

	-- The lobby has no arena: a shot, its bricks and a burst's pieces stop on the range's hall.
	local params = RangeCore.SightParams()
	WeaponController.SightParams = params
	gunFx.FloorParams = params
	EnemyImpacts.SetFloorParams(params)
end

-- How far over a dummy is (0 standing, 1 flat on its back, a little under 0 as it rocks forward getting up), or nil
-- once it is up again.
local function overOf(body: TBody, now: number): number?
	local since = now - body.DownAt
	if since >= RangeCore.DOWN_SECONDS then return nil end
	local fall = RangeCore.FALL_SECONDS * (if body.IsOverkill then Tune.OVERKILL_FALL_SHARE else 1)
	if since < fall then
		local t = since / fall
		return t * t
	end

	local rest = RangeCore.FALL_SECONDS + RangeCore.HOLD_SECONDS
	if since < rest then
		local landed = since - fall
		local bounce = math.abs(math.sin(landed * Tune.BOUNCE_SPEED)) * math.exp(-landed * Tune.BOUNCE_DAMPER)
		return 1 - Tune.BOUNCE * bounce
	end

	-- Up on easeOutBack: it swings a little past upright, onto its toes, and settles.
	local s = 1.70158
	local u = (since - rest) / RangeCore.RISE_SECONDS - 1
	return -((s + 1) * u * u * u + s * u * u)
end

-- A reeling dummy as drawn (EnemiesController's flinched): leaned away from the shooter on its feet and shaken
-- sideways, the lean outlasting the shake. nil once it has settled.
local function flinched(body: TBody, cframe: CFrame, elapsed: number): CFrame?
	local phase = elapsed * Tune.FLINCH_SPEED
	if phase >= TAU then return nil end

	local lean = math.sin(phase) * math.exp(-phase * Tune.FLINCH_DAMPER)
	local shake = if elapsed < Tune.FLINCH_SHAKE_TIME
		then math.sin(elapsed * Tune.FLINCH_SHAKE_SPEED) * (1 - elapsed / Tune.FLINCH_SHAKE_TIME) * Tune.FLINCH_SHAKE_STUDS
		else 0
	local away = body.Away
	local side = V3_YAXIS:Cross(away)
	return CFrame.new(cframe.Position + away * (lean * Tune.FLINCH_PUSH) + side * shake)
		* CFrame.fromAxisAngle(side, lean * Tune.FLINCH_ANGLE)
		* cframe.Rotation
end

local function setAiming(body: TBody, isAiming: boolean)
	if body.IsAiming == isAiming then return end
	body.IsAiming = isAiming
	if isAiming then
		EnemyWorld:add(body.Entity, Tags.Enemy)
	else
		EnemyWorld:remove(body.Entity, Tags.Enemy)
	end
end

local function drawBodies(now: number)
	local serverTime = Workspace:GetServerTimeNow()
	local count = 0
	for _, body in bodies do
		if body.IsFlashing then
			local remaining = body.FlashEndsAt - now
			body.IsFlashing = remaining > 0
			body.Flash.FillTransparency = if remaining > 0 then 1 - remaining / Tune.FLASH_TIME else 1
		end

		local dummy = body.Dummy
		local over = overOf(body, now)
		setAiming(body, over == nil)
		local feet = feetOf(dummy, serverTime)
		local pose = flinched(body, feet, now - body.FlinchAt)
		local isAtRest = dummy.SwayStuds == 0 and over == nil and pose == nil
		if isAtRest and body.IsAtRest then continue end
		body.IsAtRest = isAtRest

		EnemyWorld:set(body.Entity, Components.CFrame, feet)
		local upright = pose or feet
		local frame = if over then upright * CFrame.Angles(over * Tune.FLAT, 0, 0) else upright
		for index, part in dummy.Parts do
			count += 1
			moveParts[count] = part
			moveFrames[count] = (if dummy.IsBody[index] then frame else feet) * dummy.Offsets[index]
		end
	end

	for index = count + 1, #moveParts do
		moveParts[index] = nil
		moveFrames[index] = nil
	end
	if count > 0 then Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged) end
end

-- The shooter's root, when this client knows the character.
local function attackerPosition(attackerId: number): Vector3?
	local entity = CharacterCore.GetCharacterByInstanceId(attackerId)
	local root = if entity then World:get(entity, Components.HumanoidRootPart) else nil
	return if root then root.Position else nil
end

-- ============================== The trip and the strip ==============================

local function updateInside(now: number)
	local root = selfRoot
	local isInside = root ~= nil and root.Parent ~= nil and RangeCore.IsInside(root.Position)
	if isInside ~= state.IsInside() then
		state.IsInside(isInside)
		updateUp(now)
	end

	-- The strip shows the gun the server put in hand, as soon as it changes, and once a pick shown ahead of it has gone
	-- unanswered.
	local gun = WeaponController.Gun
	if not isInside or not gun then return end
	local isStale = state.Held() ~= gun.Id and now - heldAheadAt >= Tune.PICK_ANSWER_SECONDS
	if gun ~= lastGun or isStale then hold(gun.Id) end
	lastGun = gun
end

local function isAtBooth(position: Vector3): boolean
	for _, booth in RangeCore.BOOTHS do
		if (booth.Position - position).Magnitude < Tune.TRY_BOOTH_STUDS then return true end
	end

	return false
end

local function updateTrip(now: number)
	if tryGun == 0 then return end
	if not hasAskedTry then
		if now < tryAskAt then return end
		hasAskedTry = true
		tryGiveUpAt = now + Tune.TRY_TIMEOUT
		-- The server offers only the tried gun too (Range.Offer); shown at once so the strip rises with it.
		state.Shown({ tryGun })
		holdAhead(tryGun)
		ClientNetworkRange.Try.Fire(tryGun)
		return
	end

	local root = selfRoot
	local hasArrived = root ~= nil and isAtBooth(root.Position)
	if not hasArrived and now < tryGiveUpAt then return end
	tryGun = 0

	-- The view behind the player, down the range, as the cover opens.
	if hasArrived and root then
		local camera = Workspace.CurrentCamera
		local ahead = root.CFrame.LookVector * FLAT_XZ
		local eye = root.Position - ahead * Tune.TRY_CAMERA_BACK + V3_YAXIS * Tune.TRY_CAMERA_UP
		camera.CFrame = CFrame.lookAt(eye, root.Position + ahead * Tune.TRY_CAMERA_AHEAD)
	end
	stamp(state.UncoverAt, now)
end

local function frame()
	local now = os.clock()
	EnemyImpacts.BeginFrame()
	updateTrip(now)
	updateInside(now)

	if #bodies == 0 and now >= nextGatherAt then
		nextGatherAt = now + Tune.GATHER_RETRY_SECONDS
		gather()
	end
	local camera = Workspace.CurrentCamera
	if #bodies > 0 and (camera.CFrame.Position - bodies[1].Dummy.Home.Position).Magnitude < Tune.DRAW_DISTANCE then
		drawBodies(now)
	end

	if isOfferWithdrawn and not state.IsUp() and now - state.UpAt() >= Strip.SETTLED then
		isOfferWithdrawn = false
		state.Shown({})
	end

	if now < motionUntil then state.Now(now) end
end

-- The design's 1080 tall to the screen's height under the top bar, and never wider than the screen.
local function updateScale()
	local viewport = Workspace.CurrentCamera.ViewportSize
	-- The lobby HUD's scale (LobbyController), so the strip keeps its place over the HUD's bottom row.
	local inset = GuiService:GetGuiInset().Y
	local byHeight = math.clamp((viewport.Y - inset) / Theme.DESIGN_HEIGHT, Theme.MIN_SCALE, Theme.MAX_SCALE)
	local byWidth = (viewport.X - 2 * Theme.EDGE) / Strip.WIDTH
	state.Scale(math.max(math.min(byHeight, byWidth), 0.01))
end

-- ============================== Wiring ==============================

-- Every blow on a dummy, anybody's: what an enemy shows of it, and the crosshair's and the numbers' share.
ServerNetworkRange.Hit.On(function(index: number, attackerId: number, damage: number, outcome: number)
	local body = bodies[index]
	if not body then return end
	local now = os.clock()
	local dummy = body.Dummy
	local aim = dummy.Aim
	local feet = EnemyWorld:get(body.Entity, Components.CFrame) or dummy.Home
	local chest = feet.Position + V3_YAXIS * aim.x
	local from = attackerPosition(attackerId)
	local isOwn = attackerId ~= 0 and attackerId == CharacterController.GetLocalCharacterId()
	local heard = if isOwn then Workspace.CurrentCamera.CFrame.Position else chest

	body.FlashEndsAt = now + Tune.FLASH_TIME
	body.IsFlashing = true
	body.IsAtRest = false
	if now - body.FlinchAt >= Tune.FLINCH_RETRIGGER then
		-- Away from the shooter; back off the firing line when there is none (feet face it, level).
		local away = if from then (chest - from) * FLAT_XZ else Vector3.zero
		body.Away = if away.Magnitude > 0.1 then away.Unit else -feet.LookVector
		body.FlinchAt = now
	end

	if outcome == 0 then
		EnemyImpacts.EmitHit(body.Look, chest, aim, from)
		if now - body.HitSoundAt >= Tune.HIT_SOUND_DEBOUNCE then
			body.HitSoundAt = now
			EnemyImpacts.PlayHit(body.Look, chest, heard)
		end
		targetHits.Damaged:Fire(index, attackerId, damage, chest)
		return
	end

	local isOverkill = outcome == 2
	if isOverkill then
		EnemyImpacts.EmitOverkill(body.Look, chest, aim, from)
	else
		EnemyImpacts.EmitKill(body.Look, chest, aim, from)
	end
	EnemyImpacts.PlayHit(body.Look, chest, heard)
	EnemyImpacts.PlayDeath(body.Look, chest, heard, isOverkill)
	EnemyImpacts.AddKills(1, heard)
	body.DownAt = now
	body.IsOverkill = isOverkill
	setAiming(body, false)
	targetHits.Killed:Fire(index, attackerId, damage, isOverkill, chest)
end)

-- What the strip holds. A withdrawn offer (the player walked out) is let go only once the strip has dropped away, so
-- its slots leave rather than vanish.
ServerNetworkRange.Offer.On(function(gunIds: { number })
	if #gunIds == 0 then
		isOfferWithdrawn = true
		return
	end
	isOfferWithdrawn = false
	state.Shown(gunIds)
end)

RangeController.OnSelfCharacterAdded = function(character)
	selfRoot = character.HumanoidRootPart
end :: TCharacterEvents.OnCharacterAdded

RangeController.OnSelfCharacterRemoving = function()
	selfRoot = nil
end :: TCharacterEvents.OnCharacterRemoving

RangeController.OnStart = function()
	vide.mount(function()
		local isDrawn = vide.derive(function(): boolean
			return state.IsUp() or state.Now() - state.UpAt() < Strip.SETTLED
		end)

		return {
			vide.create("ScreenGui")({
				Name = "Range",
				ResetOnSpawn = false,
				IgnoreGuiInset = true,
				ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
				DisplayOrder = Tune.DISPLAY_ORDER,
				Enabled = isDrawn,
				vide.create("Frame")({
					Name = "Root",
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					vide.create("Frame")({
						Name = "Design",
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.fromScale(0.5, 1),
						Size = function()
							local scale = state.Scale()
							return UDim2.fromScale(1 / scale, 1 / scale)
						end,
						BackgroundTransparency = 1,
						vide.create("UIScale")({ Scale = state.Scale }),
						Strip.Build(state, actions),
					}),
				}),
			}),
			vide.create("ScreenGui")({
				Name = "RangeCover",
				ResetOnSpawn = false,
				IgnoreGuiInset = true,
				DisplayOrder = Tune.COVER_DISPLAY_ORDER,
				Strip.Cover(state),
			}),
		}
	end, LocalPlayer:WaitForChild("PlayerGui"))

	UserInputService.InputBegan:Connect(function(input: InputObject, isProcessed: boolean)
		if isProcessed or not state.IsUp() then return end
		local keyCode = input.KeyCode
		local index = table.find(Strip.SLOT_KEYS, keyCode)
		if index then
			pickSlot(index)
		elseif keyCode == Strip.PREVIOUS_KEY then
			step(-1)
		elseif keyCode == Strip.NEXT_KEY then
			step(1)
		end
	end)

	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	updateScale()
	RunService.PreRender:Connect(frame)
end

return Ignis.Register(RangeController)
