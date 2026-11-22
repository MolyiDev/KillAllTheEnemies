-- The registry of every data table in ReplicatedStorage.Data, built once at require time. One folder a kind;
-- each kind answers ById and All, so a system that needs "every enemy" never walks the Instance tree.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TData = require(ReplicatedStorage.Types.TData)

export type TCollection<T> = {
	ById: { [number]: T },
	All: { T },
}

local DataCore = {}

local function collect<T>(folder: Instance): TCollection<T>
	local byId: { [number]: T } = {}
	local all: { T } = {}

	for _, module in folder:GetChildren() do
		if not module:IsA("ModuleScript") then continue end
		local data = (require :: any)(module)
		assert(byId[data.Id] == nil, `[DataCore] duplicate id {data.Id} in {folder.Name}/{module.Name}`)
		byId[data.Id] = data
		all[#all + 1] = data
	end

	-- Id order, so anything that iterates All (a round's draw, the client's preload) is the same on every run.
	table.sort(all, function(a: any, b: any)
		return a.Id < b.Id
	end)

	return table.freeze({ ById = table.freeze(byId), All = table.freeze(all) })
end

DataCore.Enemies = collect(ReplicatedStorage.Data.Enemies) :: TCollection<TData.TEnemy>
DataCore.Defenses = collect(ReplicatedStorage.Data.Defenses) :: TCollection<TData.TDefense>
DataCore.Guns = collect(ReplicatedStorage.Data.Guns) :: TCollection<TData.TGun>
DataCore.Classes = collect(ReplicatedStorage.Data.Classes) :: TCollection<TData.TClass>
DataCore.Upgrades = collect(ReplicatedStorage.Data.Upgrades) :: TCollection<TData.TUpgrade>

return table.freeze(DataCore)
