-- The crosshair on the mouse (the lock holds it at the middle), in place of CameraController's dot, answering the local
-- player's shots, aim, hits, kills (targetHits, in both places) and hurts. Turrets credit their owner's character too,
-- so a hit or kill counts as the player's only within HIT_WINDOW of their own last shot.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local vide = require(ReplicatedStorage.Packages.vide)
local CameraController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.CameraController)
local CharacterController = require(script.Parent.CharacterController)
local WeaponController = require(script.Parent.WeaponController)
local targetHits = require(script.Parent.Parent.Utils.targetHits)
local GunsCore = require(ReplicatedStorage.GlobalShared.Core.GunsCore)
local Crosshair = require(script.Crosshair)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)
local TData = require(ReplicatedStorage.Types.TData)

local LocalPlayer = Players.LocalPlayer

local Tune = table.freeze({
	-- The crosshair is drawn for a screen this tall and scaled with the real one's height, never under MIN_UNIT.
	DESIGN_HEIGHT = 1080,
	MIN_UNIT = 0.6,
	-- A shot throws the corners out this many design pixels, plus this many per degree of the gun's kick, at most
	-- KICK_MAX.
	KICK_BASE = 3,
	KICK_PER_DEG = 3,
	KICK_MAX = 8,
	-- The gun's cone is drawn to this step of a design pixel, so a field of view punch redraws it in steps.
	SPREAD_STEP = 0.5,
	-- A blow this long after the player's own shot is theirs.
	HIT_WINDOW = 0.75,
	-- Hits closer together than STREAK_SECONDS are one streak; the marker restarts no sooner than RESTART_SECONDS, so
	-- a volley's blows are one answer.
	STREAK_SECONDS = 0.35,
	RESTART_SECONDS = 0.08,
})

local CrosshairController = {}

local state = Crosshair.State()
-- The clock runs while a gesture is under way, and once more after, so every gesture lands on its rest.
local awakeUntil = -math.huge
local isAwake = false
local lastMouse = Vector2.new(-1, -1)
-- What the damage events said since the last frame, written into the sources once a frame.
local hitAt = -math.huge
local streak = 1
local killAt = -math.huge
local isOverkill = false
local hurtAt = -math.huge
-- Whether the place wants the crosshair now: always in a match; in the lobby, only in the shooting range.
local isShown = true
local selfCharacterId: number? = nil
-- The gun the drawn cone is for; the cone is worked out again only for a new gun, field of view or screen.
local spreadGun: TData.TGun? = nil
local isSpreadStale = true

-- The local player was hurt (the match's HealthController): the crosshair flinches with the view.
function CrosshairController.Hurt()
	hurtAt = os.clock()
end

-- Draws the crosshair in place of the pointer, or takes it away and gives the pointer back (the lobby, which has the
-- crosshair only in its shooting range).
function CrosshairController.SetShown(shown: boolean)
	isShown = shown
	CameraController.SetPointerHidden(shown)
end

local function wake(now: number)
	awakeUntil = math.max(awakeUntil, now + Crosshair.LONGEST)
end

local function isOwnBlow(attackerId: number): boolean
	if attackerId == 0 or os.clock() - WeaponController.FiredAt > Tune.HIT_WINDOW then return false end
	if not selfCharacterId then selfCharacterId = CharacterController.GetLocalCharacterId() end
	return attackerId == selfCharacterId
end

local function markSpreadStale()
	isSpreadStale = true
end

local function resize()
	local height = Workspace.CurrentCamera.ViewportSize.Y
	state.Unit(math.max(height / Tune.DESIGN_HEIGHT, Tune.MIN_UNIT))
	markSpreadStale()
end

-- The gun's cone at the screen, in design pixels: SpreadDeg is the cone's half-angle (GunsCore.PelletDirections).
local function spreadOf(camera: Camera, gun: TData.TGun?): number
	if not gun or gun.SpreadDeg <= 0 then return 0 end
	local focal = camera.ViewportSize.Y * 0.5 / math.tan(math.rad(camera.FieldOfView) * 0.5)
	local pixels = math.tan(math.rad(gun.SpreadDeg)) * focal / state.Unit()
	return math.round(pixels / Tune.SPREAD_STEP) * Tune.SPREAD_STEP
end

-- Run inside a batch: the sources are written together, and only those that changed redraw anything.
local function updateFrame()
	local now = os.clock()
	local isVisible = isShown
		and (UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter or UserInputService.MouseEnabled)
	state.IsVisible(isVisible)
	if not isVisible then return end

	local mouse = UserInputService:GetMouseLocation()
	if mouse ~= lastMouse then
		lastMouse = mouse
		state.Position(UDim2.fromOffset(mouse.X, mouse.Y))
	end

	local gun = WeaponController.Gun
	if gun ~= spreadGun or isSpreadStale then
		spreadGun = gun
		isSpreadStale = false
		state.Spread(spreadOf(Workspace.CurrentCamera, gun))
	end

	local isArmed = WeaponController.IsArmed
	if isArmed ~= state.IsArmed() then
		state.IsArmed(isArmed)
		state.ArmedAt(now)
		wake(now)
	end

	local isOnTarget = WeaponController.IsOnEnemy
	if isOnTarget ~= state.IsOnTarget() then
		state.IsOnTarget(isOnTarget)
		state.TargetAt(now)
		wake(now)
	end

	local firedAt = WeaponController.FiredAt
	if firedAt ~= state.FiredAt() and gun then
		state.FiredAt(firedAt)
		state.Kick(math.min(Tune.KICK_BASE + Tune.KICK_PER_DEG * GunsCore.KickDeg(gun), Tune.KICK_MAX))
		wake(now)
	end

	if hurtAt ~= state.HurtAt() then
		state.HurtAt(hurtAt)
		wake(now)
	end

	if hitAt ~= state.HitAt() then
		state.HitAt(hitAt)
		state.Streak(streak)
		wake(now)
	end

	if killAt ~= state.KillAt() then
		state.KillAt(killAt)
		wake(now)
	end
	state.IsOverkill(isOverkill)

	if now <= awakeUntil then
		isAwake = true
		state.Now(now)
	elseif isAwake then
		isAwake = false
		state.Now(now)
	end
end

targetHits.Damaged:Connect(function(_, attackerId: number)
	if not isOwnBlow(attackerId) then return end
	local now = os.clock()
	if now - hitAt < Tune.RESTART_SECONDS then return end
	streak = if now - hitAt < Tune.STREAK_SECONDS then streak + 1 else 1
	hitAt = now
end)

targetHits.Killed:Connect(function(_, killerId: number, _, isOverkillBlow: boolean)
	if not isOwnBlow(killerId) then return end
	local now = os.clock()
	if now - killAt < Tune.RESTART_SECONDS then
		isOverkill = isOverkill or isOverkillBlow
		return
	end

	killAt = now
	isOverkill = isOverkillBlow
end)

CrosshairController.OnSelfCharacterRemoving = function()
	selfCharacterId = nil
end :: TCharacterEvents.OnCharacterRemoving

CrosshairController.OnStart = function()
	CameraController.HideDot()
	resize()
	local camera = Workspace.CurrentCamera
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
	-- A punched field of view (an upgrade landing) changes the cone on screen.
	camera:GetPropertyChangedSignal("FieldOfView"):Connect(markSpreadStale)

	vide.mount(function()
		return vide.create("ScreenGui")({
			Name = "Crosshair",
			-- The mouse location counts from the window's top, under the top bar.
			IgnoreGuiInset = true,
			ResetOnSpawn = false,
			DisplayOrder = 1000,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			Crosshair.Build(state),
		})
	end, LocalPlayer:WaitForChild("PlayerGui"))

	RunService.PreRender:Connect(function()
		vide.batch(updateFrame)
	end)
end

return Ignis.Register(CrosshairController)
