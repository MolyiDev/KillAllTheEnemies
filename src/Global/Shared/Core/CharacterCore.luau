-- The one map from a character's network id to its entity, on both sides. A character only gets an id once
-- every client has acknowledged it (Game/Server/Services/CharacterService), so anything that resolves an id
-- from the wire - a kill credit, a damage target - can trust the other side knows it too.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local WorldRef = require(ReplicatedStorage.GlobalShared.ECS.References.WorldRef)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local Signal = require(ReplicatedStorage.Packages.Signal)
local jecs = require(ReplicatedStorage.Packages.jecs)

local CharacterCore = {}

-- (characterEntity, instanceId)
CharacterCore.OnCharacterIdAssigned = Signal.new()

function CharacterCore.GetCharacterByInstanceId(instanceId: number): jecs.Entity<any>?
	return WorldRef:Search(instanceId)
end

function CharacterCore.AddCharacter(characterEntity: jecs.Entity<any>, instanceId: number)
	World:set(characterEntity, Components.InstanceId, instanceId)
	WorldRef:List(instanceId, characterEntity)
	CharacterCore.OnCharacterIdAssigned:Fire(characterEntity, instanceId)
end

-- Drops the id mapping only; the entity itself belongs to CharacterEvents, which nukes it with the rig.
function CharacterCore.RemoveCharacter(instanceId: number)
	WorldRef:Unlist(instanceId)
end

return CharacterCore
