export type ObjectPoolerAPI<T> = {
	Object: T,
	ReturnFunction: (object: T) -> (),
	Parent: Instance?,
	RepoolQuantity: number,
	Pool: { T },
	Get: (self: ObjectPoolerAPI<T>) -> T,
	Return: (self: ObjectPoolerAPI<T>, object: T) -> (),
	Repoblate: (self: ObjectPoolerAPI<T>, quantity: number) -> (),
	Purge: (self: ObjectPoolerAPI<T>) -> (),
}

local ObjectPoolerStatic = {}
ObjectPoolerStatic.IDLE_CF = CFrame.new(2 ^ 24, 2 ^ 24, 2 ^ 24)

local ObjectPooler = {}
ObjectPooler.__index = ObjectPooler

function ObjectPoolerStatic.new<T>(
	object: T,
	initialQuantity: number,
	repoolQuantity: number,
	returnFunction: (object: T) -> (),
	parent: Instance?
): ObjectPoolerAPI<T>
	local self = (setmetatable({}, ObjectPooler) :: any) :: ObjectPoolerAPI<T>
	self.Object = object
	self.ReturnFunction = returnFunction
	self.Parent = parent
	self.RepoolQuantity = repoolQuantity
	self.Pool = {}

	returnFunction(object)
	self:Repoblate(initialQuantity)
	return self
end

function ObjectPoolerStatic.ReturnBoneModel(object: any)
	object.PrimaryPart.Root.CFrame = ObjectPoolerStatic.IDLE_CF
end

function ObjectPoolerStatic.ReturnBoneTransform(object: any)
	object.PrimaryPart.Root.Transform = ObjectPoolerStatic.IDLE_CF
end

function ObjectPoolerStatic.ReturnCF(object: any)
	object.CFrame = ObjectPoolerStatic.IDLE_CF
end

function ObjectPoolerStatic.ReturnPrimaryCF(object: any)
	object.PrimaryPart.CFrame = ObjectPoolerStatic.IDLE_CF
end

function ObjectPoolerStatic.ReturnUIObject(object: any)
	if not object.Visible then return end
	object.Visible = false
end

function ObjectPoolerStatic.ReturnParentNil(object: any)
	object.Parent = nil
end

function ObjectPoolerStatic.ReturnAdornee(object: any)
	object.Adornee = nil
end

function ObjectPooler.Repoblate<T>(self: ObjectPoolerAPI<T>, quantity: number)
	debug.profilebegin("Pool Repoblate")
	for _ = 1, quantity do
		local clone = (self.Object :: any):Clone()
		clone.Parent = self.Parent
		self.Pool[#self.Pool + 1] = clone
	end
	debug.profileend()
end

function ObjectPooler.Get<T>(self: ObjectPoolerAPI<T>): T
	debug.profilebegin("Pool Get")
	if #self.Pool == 0 then
		if self.RepoolQuantity == 0 then
			debug.profileend()
			return nil :: any
		end
		self:Repoblate(self.RepoolQuantity)
	end

	local item = table.remove(self.Pool) :: T
	debug.profileend()
	return item
end

function ObjectPooler.Purge<T>(self: ObjectPoolerAPI<T>)
	debug.profilebegin("Pool Purge")
	local pool = self.Pool
	for i = 1, #pool do
		(pool[i] :: any):Destroy()
	end
	table.clear(pool)
	debug.profileend()
end

function ObjectPooler.Return<T>(self: ObjectPoolerAPI<T>, object: T)
	debug.profilebegin("Pool Return")
	-- Reset the object before pooling it. If the return function throws (e.g. reparenting a
	-- destroyed instance), the object never enters the pool, so a later Get() can't hand out
	-- a broken object.
	self.ReturnFunction(object)
	self.Pool[#self.Pool + 1] = object
	debug.profileend()
end

return ObjectPoolerStatic
