-- What the bought items do to the world when one is used (MatchController.OnNukedAll, OnHealedAll, OnGoldBought):
-- the nuke's blast and rolling front (Utils/nukeFx), the heal on every body (Utils/healFx), a Gold pack's burst on its
-- buyer (Utils/goldFx), and with each a shake, a wash of colour over the view and its sound. The announcement is the HUD's. Decides nothing: the server has already
-- killed and healed.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local MatchController = require(script.Parent.MatchController)
local CoinFlight = require(script.Parent.Parent.Utils.coinFlight)
local goldFx = require(script.Parent.Parent.Utils.goldFx)
local healFx = require(script.Parent.Parent.Utils.healFx)
local nukeFx = require(script.Parent.Parent.Utils.nukeFx)
-- Through PlayerScripts, the copy that runs (HudController's note on ProfileController).
local CameraController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.CameraController)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local EnemiesCore = require(ReplicatedStorage.Shared.Core.EnemiesCore)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local Tags = require(ReplicatedStorage.GlobalShared.ECS.Tags)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local getCharacterEntityFromPlayer =
	require(ReplicatedStorage.GlobalShared.Utils.Functions.getCharacterEntityFromPlayer)
local TCharacter = require(ReplicatedStorage.Types.TCharacter)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)

local ItemsController = {}

local SOUND_GROUP = "Items"
local WHITE = Color3.new(1, 1, 1)

local Tune = table.freeze({
	-- The blast's jolt: the shake's ceiling (CameraController's SHAKE_MAX_MAGNITUDE) at the blast, down to
	-- NUKE_SHAKE_FAR of it this far off, over this long at this many swings (a blast's, 2.6 to 5.5).
	NUKE_SHAKE = 4,
	NUKE_SHAKE_SECONDS = 0.6,
	NUKE_SHAKE_SWINGS = 5,
	NUKE_SHAKE_FAR = 0.35,
	NUKE_SHAKE_REACH = 160,
	-- The ground rumbling under the front for as long as it rolls.
	NUKE_RUMBLE = 1.1,
	NUKE_RUMBLE_SWINGS = 5.5,
	-- The view washed white-gold by the blast, and pale green by a heal: how bright at its first frame, the tint it
	-- starts from, and how long it takes to clear.
	NUKE_WASH = 0.5,
	NUKE_TINT = Color3.fromRGB(255, 232, 190),
	NUKE_WASH_SECONDS = 0.5,
	HEAL_WASH = 0.14,
	HEAL_TINT = Color3.fromRGB(205, 255, 215),
	HEAL_WASH_SECONDS = 0.7,
	-- The buyer's own view as his Gold pack lands: a pale gold wash and a small jolt (a blow's, 3 swings), both
	-- bigger for the big pack.
	GOLD_WASH = 0.1,
	GOLD_WASH_BIG = 0.2,
	GOLD_TINT = Color3.fromRGB(255, 236, 170),
	GOLD_WASH_SECONDS = 0.45,
	GOLD_SHAKE = 0.8,
	GOLD_SHAKE_BIG = 1.8,
	GOLD_SHAKE_SECONDS = 0.3,
	GOLD_SHAKE_SWINGS = 3,
	-- A body that comes back up this soon after a heal was one it revived: it gets the heal's burst as it arrives.
	HEAL_LATE_SECONDS = 4,
})

local CharactersQuery = World:query(Components.HumanoidRootPart, Components.Humanoid):with(Tags.Character):cached()

-- Made on the first use, in Lighting: it tints the world and leaves the HUD as it is.
local wash: ColorCorrectionEffect? = nil
local washAt = -math.huge
local washSeconds = 1
local washBrightness = 0
local washTint = WHITE
local healedAt = -math.huge

local function startWash(brightness: number, tint: Color3, seconds: number)
	local effect = wash
	if not effect then
		effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "ItemWash"
		effect.Parent = Lighting
		wash = effect
	end

	washAt = os.clock()
	washSeconds = seconds
	washBrightness = brightness
	washTint = tint
	effect.Enabled = true
end

-- Full on its first frame, then away fast and gently to nothing: a flash, not a fade in.
local function stepWash()
	local effect = wash
	if not effect or not effect.Enabled then return end
	local left = 1 - (os.clock() - washAt) / washSeconds
	if left <= 0 then
		effect.Enabled = false
		return
	end

	local strength = left * left
	effect.Brightness = washBrightness * strength
	effect.TintColor = WHITE:Lerp(washTint, strength)
end

local function onNukedAll(_, origin: Vector3)
	nukeFx.Blast(origin, EnemiesCore.NUKE_SPEED, EnemiesCore.NUKE_SECONDS)

	local cameraPosition = Workspace.CurrentCamera.CFrame.Position
	local near = 1 - math.clamp((cameraPosition - origin).Magnitude / Tune.NUKE_SHAKE_REACH, 0, 1)
	local felt = Tune.NUKE_SHAKE_FAR + (1 - Tune.NUKE_SHAKE_FAR) * near
	CameraController.Shake(
		Tune.NUKE_SHAKE * felt,
		4 * Tune.NUKE_SHAKE_SECONDS / Tune.NUKE_SHAKE_SWINGS,
		Tune.NUKE_SHAKE_SECONDS
	)
	CameraController.Shake(
		Tune.NUKE_RUMBLE * felt,
		4 * EnemiesCore.NUKE_SECONDS / Tune.NUKE_RUMBLE_SWINGS,
		EnemiesCore.NUKE_SECONDS
	)
	startWash(Tune.NUKE_WASH * felt, Tune.NUKE_TINT, Tune.NUKE_WASH_SECONDS)
	-- At the camera: it is the whole squad's moment, as loud for whoever stands far from the buyer.
	SoundsCore.PlayWorldNamed(SOUND_GROUP, "Nuke", cameraPosition)
end

local function onHealedAll(buyer: Player)
	healedAt = os.clock()
	local buyerCharacter = buyer.Character
	for _, root, humanoid in CharactersQuery do
		-- A body that is down stays where it fell: its new one gets the burst when it arrives.
		if humanoid.Health <= 0 then continue end
		healFx.Cast(root, buyerCharacter ~= nil and root:IsDescendantOf(buyerCharacter))
	end

	startWash(Tune.HEAL_WASH, Tune.HEAL_TINT, Tune.HEAL_WASH_SECONDS)
	SoundsCore.PlayWorldNamed(SOUND_GROUP, "Heal", Workspace.CurrentCamera.CFrame.Position)
end

-- On the buyer's body for everybody; the wash and the jolt are the buyer's alone. The buyer hears it at the camera,
-- at its full level, and the squad from where he stands.
local function onGoldBought(buyer: Player, amount: number)
	local entity = getCharacterEntityFromPlayer(buyer)
	local root = if entity then World:get(entity, Components.HumanoidRootPart) else nil
	local isBig = amount >= CoinFlight.Shower.BIG_FROM
	local isSelf = buyer == Players.LocalPlayer
	if root then goldFx.Cast(root, isBig) end
	if isSelf then
		startWash(if isBig then Tune.GOLD_WASH_BIG else Tune.GOLD_WASH, Tune.GOLD_TINT, Tune.GOLD_WASH_SECONDS)
		CameraController.Shake(
			if isBig then Tune.GOLD_SHAKE_BIG else Tune.GOLD_SHAKE,
			4 * Tune.GOLD_SHAKE_SECONDS / Tune.GOLD_SHAKE_SWINGS,
			Tune.GOLD_SHAKE_SECONDS
		)
	end

	local heardAt = if isSelf then Workspace.CurrentCamera.CFrame.Position elseif root then root.Position else nil
	if heardAt then SoundsCore.PlayWorldNamed(SOUND_GROUP, "GoldPack", heardAt) end
end

MatchController.OnNukedAll:Connect(onNukedAll)
MatchController.OnHealedAll:Connect(onHealedAll)
MatchController.OnGoldBought:Connect(onGoldBought)

ItemsController.OnCharacterAdded = function(character: TCharacter.TCharacter)
	if os.clock() - healedAt > Tune.HEAL_LATE_SECONDS then return end
	healFx.Cast(character.HumanoidRootPart, false)
end :: TCharacterEvents.OnCharacterAdded

ItemsController.OnStart = function()
	RunService.PreRender:Connect(function()
		nukeFx.Step()
		healFx.Step()
		goldFx.Step()
		stepWash()
	end)
end

return Ignis.Register(ItemsController)
