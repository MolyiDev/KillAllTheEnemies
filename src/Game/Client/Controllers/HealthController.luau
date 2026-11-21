-- The local player's health as the server last said it (CharacterService runs it in ECS), and the one place a drop in
-- it becomes feedback: HurtAt moves for the HUD, which reads it every frame. A hit does not shake the camera: a crowd
-- lands one every few frames, and the view would never hold still.
--
-- Down is health 0 during a run (no auto-respawn): the body stays, so read it off the number, never off Humanoid.Died.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Network = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Network)
local CharacterController = require(script.Parent.CharacterController)

local ServerNetworkCharacters = Network.Server.Characters

local HealthController = {}

-- 0 / 0 until the server's first report for this character.
HealthController.Health = 0
HealthController.MaxHealth = 0
-- os.clock() of the last drop.
HealthController.HurtAt = -math.huge

function HealthController.IsDown(): boolean
	return HealthController.MaxHealth > 0 and HealthController.Health <= 0
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

HealthController.OnSelfCharacterRemoving = function()
	HealthController.Health = 0
	HealthController.MaxHealth = 0
end

return Ignis.Register(HealthController)
