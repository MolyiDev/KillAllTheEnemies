export type IdGeneratorAPI = {
	MinId: number,
	MaxId: number,
	CurrentId: number,
	ReservedIds: { [number]: boolean }?,
	Reset: (min: number?, max: number) -> (),
	Generate: (self: IdGeneratorAPI) -> number,
}

local IdGeneratorStatic = {}
local IdGenerator = {}
IdGenerator.__index = IdGenerator

local CurrentGenerators: { [string]: IdGeneratorAPI } = {}
local PendingReservedIds: { [string]: { [number]: boolean } } = {}

function IdGeneratorStatic.new(name: string, min: number, max: number): IdGeneratorAPI
	local existing = CurrentGenerators[name]
	if existing then return existing end

	local self = (setmetatable({}, IdGenerator) :: any) :: IdGeneratorAPI
	self.MinId = min
	self.MaxId = max
	self.CurrentId = min
	self.ReservedIds = PendingReservedIds[name]

	CurrentGenerators[name] = self

	return self
end

-- Register IDs that Generate() should skip over for a given generator name.
-- Must be called before the first Generate() call for that generator.
function IdGeneratorStatic.SetReservedIds(name: string, ids: { [number]: boolean })
	local existing = CurrentGenerators[name]
	if existing then
		existing.ReservedIds = ids
	else
		PendingReservedIds[name] = ids
	end
end

function IdGenerator.Generate(self: IdGeneratorAPI)
	local reserved = self.ReservedIds
	repeat
		if self.CurrentId >= self.MaxId then
			self.CurrentId = self.MinId
		else
			self.CurrentId += 1
		end
	until not reserved or not reserved[self.CurrentId]

	return self.CurrentId
end

function IdGenerator.Reset(self: IdGeneratorAPI, min: number?, max: number)
	local _min = min or self.MinId
	local _max = max or self.MaxId

	self.CurrentId = _min
	self.MinId = _min
	self.MaxId = _max
end

return IdGeneratorStatic
