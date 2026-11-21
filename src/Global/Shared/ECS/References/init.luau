local ReplicatedStorage = game:GetService("ReplicatedStorage")
local jecs = require(ReplicatedStorage.Packages.jecs)

export type TRefKey = string | number | Instance

export type ReferencesStaticAPI = {
	new: (world: number) -> ReferencesAPI,
}

export type ReferencesAPI = {
	References: { [TRefKey]: jecs.Entity<any> },
	World: jecs.World,
	EntityRef: (self: ReferencesAPI, reference: TRefKey) -> jecs.Entity<any>,
	Search: (self: ReferencesAPI, reference: TRefKey) -> jecs.Entity<any>?,
	List: (self: ReferencesAPI, reference: TRefKey, entity: jecs.Entity<any>) -> (),
	Unlist: (self: ReferencesAPI, reference: TRefKey) -> (),
	Nuke: (self: ReferencesAPI, reference: TRefKey, entity: jecs.Entity<any>?) -> (),
}

local ReferencesStatic = {}
local References = {}
References.__index = References

function ReferencesStatic.new(world: jecs.World): ReferencesAPI
	local self = (setmetatable({}, References) :: any) :: ReferencesAPI
	self.References = {}
	self.World = world

	return self
end

-- The world always picks the id: jecs's own components are entities 1-256, so `world:entity(id)` with a small
-- network id returns a live COMPONENT, and deleting that "entity" deletes the component for the whole world.
function References.EntityRef(self: ReferencesAPI, reference: TRefKey): jecs.Entity<any>
	local entity = self.World:entity()
	self.References[reference] = entity
	return entity
end

function References.Search(self: ReferencesAPI, reference: TRefKey): jecs.Entity<any>?
	return self.References[reference]
end

function References.List(self: ReferencesAPI, reference: TRefKey, entity: jecs.Entity<any>)
	self.References[reference] = entity
end

-- Leaves the entity in the world.
function References.Unlist(self: ReferencesAPI, reference: TRefKey): ()
	self.References[reference] = nil
end

-- `entity` defaults to the one `reference` points at.
function References.Nuke(self: ReferencesAPI, reference: TRefKey, entity: jecs.Entity<any>?): ()
	if not entity then entity = self:Search(reference) end

	self.References[reference] = nil

	if entity then self.World:delete(entity) end
end

return ReferencesStatic
