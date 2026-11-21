local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local WorldRef = require(ReplicatedStorage.GlobalShared.ECS.References.WorldRef)
local Tags = require(ReplicatedStorage.GlobalShared.ECS.Tags)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local getCharacterEntityFromPlayer =
	require(ReplicatedStorage.GlobalShared.Utils.Functions.getCharacterEntityFromPlayer)
local Butler = require(ReplicatedStorage.Packages.Butler)
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local jecs = require(ReplicatedStorage.Packages.jecs)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)
local TCharacter = require(ReplicatedStorage.Types.TCharacter)

local CharacterEvents = {}

local onCharacterAdded =
	Ignis.RegisterLifecycle("OnCharacterAdded") :: Ignis.Lifecycle<TCharacter.TCharacter, jecs.Entity<any>>
local onCharacterRemoving =
	Ignis.RegisterLifecycle("OnCharacterRemoving") :: Ignis.Lifecycle<TCharacter.TCharacter, jecs.Entity<any>>
-- Client only: the same two, for the local player's own rig (input, camera, his locomotion clips).
local onSelfCharacterAdded =
	Ignis.RegisterLifecycle("OnSelfCharacterAdded") :: Ignis.Lifecycle<TCharacter.TCharacter, jecs.Entity<any>>
local onSelfCharacterRemoving =
	Ignis.RegisterLifecycle("OnSelfCharacterRemoving") :: Ignis.Lifecycle<TCharacter.TCharacter, jecs.Entity<any>>

local LocalPlayer = if RunService:IsClient() then Players.LocalPlayer else nil

local function CharacterAdded(playerEntity: jecs.Entity<any>, character: TCharacter.TCharacter)
	local characterEntity = WorldRef:EntityRef(character)
	local characterButler = Butler.new()

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	if humanoid.Health > 0 then
		World:add(characterEntity, Tags.Alive)
		characterButler:Once(humanoid.Died, function()
			World:remove(characterEntity, Tags.Alive)
		end)
	end

	jecs.bulk_insert(World, characterEntity, {
		Components.Model,
		Components.Butler,
		Components.Humanoid,
		Components.HumanoidRootPart,
		Components.Animator,
		Components.Cleanup,
		jecs.pair(jecs.ChildOf, playerEntity),
		Tags.Character,
	}, {
		character,
		characterButler,
		humanoid,
		character:WaitForChild("HumanoidRootPart"),
		humanoid:WaitForChild("Animator"),
		function()
			characterButler:Destroy()
		end,
	})

	-- TCharacter promises the Head too, and it can replicate after the parts above.
	character:WaitForChild("Head")
	onCharacterAdded:Fire(character, characterEntity)
	if LocalPlayer and character == LocalPlayer.Character then onSelfCharacterAdded:Fire(character, characterEntity) end
end

CharacterEvents.OnPlayerConnected = function(player: Player, playerEntity: jecs.Entity<any>)
	local playerButler = World:get(playerEntity, Components.Butler) :: Butler.Butler
	if player.Character then CharacterAdded(playerEntity, player.Character :: TCharacter.TCharacter) end

	playerButler:Connect(player.CharacterAdded, function(character)
		CharacterAdded(playerEntity, (character :: any) :: TCharacter.TCharacter)
	end)

	playerButler:Connect(player.CharacterRemoving, function(character: Model)
		local characterEntity = getCharacterEntityFromPlayer(player)
		if not characterEntity then return end

		onCharacterRemoving:Fire(character :: any, characterEntity)
		if player == LocalPlayer then onSelfCharacterRemoving:Fire(character :: any, characterEntity) end

		WorldRef:Nuke(character, characterEntity)
	end)
end :: TPlayerEvents.OnPlayerConnected

return Ignis.Register(CharacterEvents)
