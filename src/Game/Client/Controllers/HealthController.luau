-- The local player's health as the server last said it (CharacterService runs it in ECS), and the one place a drop in
-- it becomes feedback: HurtAt moves for the HUD, which reads it every frame. A hit does not shake the camera: a crowd
-- lands one every few frames, and the view would never hold still.
--
-- Down is health 0 during a run (no auto-respawn): the body stays, so read it off the number, never off Humanoid.Died.
--
-- It also asks for the HEALTH card's levels (Shared/Utils/healthUpgrades) and shows one bought: the cue and the
-- camera for the buyer, the burst on the buyer's body for everyone (healthUpFx). The HUD reads the stamps.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Network = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Network)
local CharacterController = require(script.Parent.CharacterController)
local MatchController = require(script.Parent.MatchController)
local TweensController = require(script.Parent.TweensController)
local healthUpFx = require(script.Parent.Parent.Utils.healthUpFx)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local healthUpgrades = require(ReplicatedStorage.Shared.Utils.healthUpgrades)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local getCharacterEntityFromPlayer =
	require(ReplicatedStorage.GlobalShared.Utils.Functions.getCharacterEntityFromPlayer)
local ESoundsIds = require(ReplicatedStorage.Types.Enums.Sounds.ESoundsIds)

local ServerNetworkCharacters = Network.Server.Characters
local ClientNetworkCharacters = Network.Client.Characters
local LocalPlayer = Players.LocalPlayer

local Tune = table.freeze({
	-- The view opens this much as a level lands on the body and comes back over this long: lighter than a new gun's.
	UPGRADE_FOV_PUNCH = 4,
	UPGRADE_FOV_RETURN = 0.5,
})

local HealthController = {}

HealthController.UPGRADE_KEY = Enum.KeyCode.C

-- 0 / 0 until the server's first report for this character.
HealthController.Health = 0
HealthController.MaxHealth = 0
-- os.clock() of the last drop.
HealthController.HurtAt = -math.huge
-- The HEALTH levels bought this run, and os.clock() of the last one the server confirmed, the last ask sent and the
-- last ask refused here.
HealthController.Level = 0
HealthController.UpgradedAt = -math.huge
HealthController.UpgradeAskedAt = -math.huge
HealthController.UpgradeDeniedAt = -math.huge

function HealthController.IsDown(): boolean
	return HealthController.MaxHealth > 0 and HealthController.Health <= 0
end

-- Asks for the next HEALTH level. Refused here, for the HUD to show it, when there is none left, the body is down or
-- the Gold is short; the server checks them all again.
function HealthController.Upgrade()
	local price = healthUpgrades.PRICES[HealthController.Level + 1]
	local now = os.clock()
	if not price or HealthController.Health <= 0 or MatchController.Gold < price then
		HealthController.UpgradeDeniedAt = now
		return
	end

	HealthController.UpgradeAskedAt = now
	ClientNetworkCharacters.UpgradeHealth.Fire()
end

ServerNetworkCharacters.Health.On(function(instanceId: number, current: number, max: number)
	if instanceId ~= CharacterController.GetLocalCharacterId() then return end
	local lost = HealthController.Health - current
	HealthController.Health = current
	HealthController.MaxHealth = max

	-- A first report, or a new body's (Health is 0 again), only rises: never a hit.
	if lost <= 0 or max <= 0 then return end
	HealthController.HurtAt = os.clock()
end)

-- A level above none is one just bought; 0 is a new run taking them back, which is not shown.
ServerNetworkCharacters.HealthLevel.On(function(player: Player, level: number)
	local isOwn = player == LocalPlayer
	if isOwn then HealthController.Level = level end
	if level <= 0 then return end

	local characterEntity = getCharacterEntityFromPlayer(player)
	local root = if characterEntity then World:get(characterEntity, Components.HumanoidRootPart) else nil
	if root then healthUpFx.Cast(root) end
	if not isOwn then return end

	HealthController.UpgradedAt = os.clock()
	SoundsCore.PlayUISound(ESoundsIds.HealthUpgrade)
	TweensController.PunchFov(Tune.UPGRADE_FOV_PUNCH, Tune.UPGRADE_FOV_RETURN)
end)

HealthController.OnSelfCharacterRemoving = function()
	HealthController.Health = 0
	HealthController.MaxHealth = 0
end

HealthController.OnStart = function()
	ContextActionService:BindAction("UpgradeHealth", function(_, state)
		if state == Enum.UserInputState.Begin then HealthController.Upgrade() end
		return Enum.ContextActionResult.Sink
	end, false, HealthController.UPGRADE_KEY)

	RunService.PreRender:Connect(healthUpFx.Step)
end

return Ignis.Register(HealthController)
