-- The gun's part of the run, which the lobby's range has none of: buying the next step of the player's ladder (V) and
-- the step landing in the hands, and the run's rules on the trigger (WeaponController.CanFire / GetFireRateBonus):
-- no shot while picking an upgrade or paused, and the Fire Rate upgrade. WeaponService holds the same rules.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Network = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Network)
local BodyPoseController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.BodyPoseController)
local CameraController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.CameraController)
local ViewmodelController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.ViewmodelController)
local WeaponController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.WeaponController)
local MatchController = require(script.Parent.MatchController)
local TweensController = require(script.Parent.TweensController)
local UpgradePickController = require(script.Parent.UpgradePickController)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local GunsCore = require(ReplicatedStorage.GlobalShared.Core.GunsCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)
local EUpgradesIds = require(ReplicatedStorage.Types.Enums.Data.EUpgradesIds)
local ESoundsIds = require(ReplicatedStorage.Types.Enums.Sounds.ESoundsIds)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)

local ClientNetworkWeapons = Network.Client.Weapons
local ServerNetworkWeapons = Network.Server.Weapons

local GUNS = DataCore.Guns.ById

local Tune = table.freeze({
	-- A bought upgrade landing in the hands: the view breathes out this many degrees and back over this long, the
	-- arms hoist the new gun with this many shots' jolt, and the camera kicks up this many studs at its peak (past
	-- any shotgun's), a share of it sideways, on a softer spring than a shot's so it settles with the breath.
	UPGRADE_FOV_PUNCH = 7,
	UPGRADE_FOV_RETURN = 0.55,
	UPGRADE_POSE_KICK = 2.8,
	UPGRADE_KICK_PEAK = 0.45,
	UPGRADE_KICK_SIDE_SHARE = 0.3,
	UPGRADE_RECOIL_FREQUENCY = 14,
	UPGRADE_RECOIL_DAMPING = 0.55,
	-- WeaponController's shot spring's roll, so the upgrade's kick rolls the same.
	RECOIL_ROLL = 0.25,
})

local UPGRADE_KICK_IMPULSE = Tune.UPGRADE_KICK_PEAK
	/ CameraController.RecoilPeakPerImpulse(Tune.UPGRADE_RECOIL_FREQUENCY, Tune.UPGRADE_RECOIL_DAMPING)

local WeaponRunController = {}

WeaponRunController.UPGRADE_KEY = Enum.KeyCode.V

-- This player's run ladder, from their lobby loadout (Weapons.Ladder); the starters' until the server sends it.
WeaponRunController.Ladder = GunsCore.STARTER_LADDER :: { GunsCore.TLadderStep }

-- os.clock of the last upgrade asked for, and the last one the purse refused.
WeaponRunController.UpgradeAskedAt = -math.huge
WeaponRunController.UpgradeDeniedAt = -math.huge

local selfCharacter: Model? = nil
local selfHumanoid: Humanoid? = nil
-- The last WeaponController.UpgradedAt celebrated.
local celebratedAt = -math.huge
local random = Random.new()

-- Asks for the next step of the ladder. Refused here, for the HUD to show it, when there is none, the body is down or
-- the Gold is short; the server checks them all again.
function WeaponRunController.Upgrade()
	local offer = WeaponRunController.Ladder[WeaponController.Step + 1]
	local humanoid = selfHumanoid
	local isStanding = WeaponController.Gun ~= nil and humanoid ~= nil and humanoid.Health > 0
	local now = os.clock()
	if not offer or not isStanding or MatchController.Gold < offer.Price then
		WeaponRunController.UpgradeDeniedAt = now
		return
	end

	WeaponRunController.UpgradeAskedAt = now
	ClientNetworkWeapons.Upgrade.Fire()
end

local function celebrate()
	SoundsCore.PlayUISound(ESoundsIds.WeaponUpgrade)
	ViewmodelController.Flourish()
	BodyPoseController.Kick(selfCharacter, Tune.UPGRADE_POSE_KICK)
	TweensController.PunchFov(Tune.UPGRADE_FOV_PUNCH, Tune.UPGRADE_FOV_RETURN)
	CameraController.SetRecoilSpring(Tune.UPGRADE_RECOIL_FREQUENCY, Tune.UPGRADE_RECOIL_DAMPING, Tune.RECOIL_ROLL)
	local side = UPGRADE_KICK_IMPULSE * Tune.UPGRADE_KICK_SIDE_SHARE * random:NextNumber(-1, 1)
	CameraController.AddRecoil(UPGRADE_KICK_IMPULSE, side)
end

WeaponRunController.OnSelfCharacterAdded = function(character)
	selfCharacter = character
	selfHumanoid = character.Humanoid
end :: TCharacterEvents.OnCharacterAdded

WeaponRunController.OnSelfCharacterRemoving = function()
	selfCharacter = nil
	selfHumanoid = nil
end :: TCharacterEvents.OnCharacterRemoving

WeaponRunController.OnStart = function()
	-- The server takes no shot from a picker or a stopped match: a trigger held into the pick draws none either.
	WeaponController.CanFire = function(): boolean
		return not UpgradePickController.IsPicking and not TimeCore.IsPaused
	end
	WeaponController.GetFireRateBonus = function(): number
		return UpgradePickController.GetStat(EUpgradesIds.FireRate)
	end

	ContextActionService:BindAction("UpgradeWeapon", function(_, state)
		if state == Enum.UserInputState.Begin then WeaponRunController.Upgrade() end
		return Enum.ContextActionResult.Sink
	end, false, WeaponRunController.UPGRADE_KEY)

	-- The step lands on Weapons.Equipped, which WeaponController hears; it is celebrated on the next frame.
	celebratedAt = WeaponController.UpgradedAt
	RunService.PreRender:Connect(function()
		if WeaponController.UpgradedAt == celebratedAt then return end
		celebratedAt = WeaponController.UpgradedAt
		celebrate()
	end)
end

ServerNetworkWeapons.Ladder.On(function(gunIds: { number })
	if #gunIds ~= #GunsCore.LADDER_PRICES then return end

	local ladder = table.create(#gunIds)
	for index, gunId in gunIds do
		local gun = GUNS[gunId]
		if not gun then return end
		ladder[index] = GunsCore.LadderStep(gun, index)
	end

	WeaponRunController.Ladder = table.freeze(ladder)
end)

return Ignis.Register(WeaponRunController)
