-- PASS 2 suites. Injected three times as children of the pass 2 driver, byte-identical except for the
-- header directives (none / `--!optimize 2` / `--!native` + `--!optimize 2`).
--
-- The `Probe` function is not a timing measurement. It counts stack frames from inside a leaf function,
-- once called directly and once through a trivial `wrapper`. If the wrapper's frame is gone, the wrapper
-- was inlined - and since inlining is an optimization level 2 feature, seeing that in the copy with NO
-- directive means the engine already compiles at level 2 and `--!optimize 2` buys nothing.

local N = 10000
local M = 4000
local C = 20000

local ARRAY = table.create(N)
for i = 1, N do
	ARRAY[i] = i % 97
end

local ARGS = table.create(C)
for i = 1, C do
	ARGS[i] = i % 13
end

local BUCKET = table.create(M)

local STUB_PLAIN = { Id = 0, Kind = 0, X = 0, Y = 0, Z = 0, Health = 0, Speed = 0, IsAlive = false }
local OBJ_MT = {}
OBJ_MT.__index = OBJ_MT
local STUB_WITH_MT = setmetatable(table.clone(STUB_PLAIN), OBJ_MT)

local TRUE_CONST = true

local function MODULE_LERP(a, b, t)
	return a + (b - a) * t
end

local TOOLS = {
	Lerp = function(a, b, t)
		return a + (b - a) * t
	end,
}

local function leafDepth()
	local n = 0
	while debug.info(n + 1, "f") do
		n += 1
	end
	return n
end

local function wrapper()
	local v = leafDepth()
	return v
end

local function Probe()
	local direct = leafDepth()
	local wrapped = wrapper()
	return direct, wrapped
end

local Suites = {}

Suites[#Suites + 1] = {
	Name = "M. Array iteration, sum 10k numbers",
	Ops = N,
	Variants = {
		{
			Name = "for i = 1, #t",
			Fn = function()
				local t = ARRAY
				local sum = 0
				for i = 1, #t do
					sum += t[i]
				end
				return sum
			end,
		},
		{
			Name = "for _, v in t (generalized)",
			Fn = function()
				local t = ARRAY
				local sum = 0
				for _, v in t do
					sum += v
				end
				return sum
			end,
		},
		{
			Name = "for _, v in ipairs(t)",
			Fn = function()
				local t = ARRAY
				local sum = 0
				for _, v in ipairs(t) do
					sum += v
				end
				return sum
			end,
		},
		{
			Name = "for _, v in pairs(t)",
			Fn = function()
				local t = ARRAY
				local sum = 0
				for _, v in pairs(t) do
					sum += v
				end
				return sum
			end,
		},
	},
}

Suites[#Suites + 1] = {
	Name = "N. 20k lerps, no fmod in the loop",
	Ops = C,
	Variants = {
		{
			Name = "floor: loop + read only",
			Fn = function()
				local t = ARGS
				local sum = 0
				for i = 1, C do
					sum += t[i]
				end
				return sum
			end,
		},
		{
			Name = "inline expression",
			Fn = function()
				local t = ARGS
				local sum = 0
				for i = 1, C do
					local a = t[i]
					sum += a + (10 - a) * 0.5
				end
				return sum
			end,
		},
		{
			Name = "local function, same scope",
			Fn = function()
				local function lerp(a, b, x)
					return a + (b - a) * x
				end
				local t = ARGS
				local sum = 0
				for i = 1, C do
					sum += lerp(t[i], 10, 0.5)
				end
				return sum
			end,
		},
		{
			Name = "module-scope local function",
			Fn = function()
				local t = ARGS
				local sum = 0
				for i = 1, C do
					sum += MODULE_LERP(t[i], 10, 0.5)
				end
				return sum
			end,
		},
		{
			Name = "Tools.Lerp (table field)",
			Fn = function()
				local t = ARGS
				local sum = 0
				for i = 1, C do
					sum += TOOLS.Lerp(t[i], 10, 0.5)
				end
				return sum
			end,
		},
	},
}

Suites[#Suites + 1] = {
	Name = "O. 20k global lookups, no property read",
	Ops = C,
	Variants = {
		{
			Name = "local constant (baseline)",
			Fn = function()
				local n = 0
				for _ = 1, C do
					if TRUE_CONST then
						n += 1
					end
				end
				return n
			end,
		},
		{
			Name = "workspace (mutable global)",
			Fn = function()
				local n = 0
				for _ = 1, C do
					if workspace then
						n += 1
					end
				end
				return n
			end,
		},
		{
			Name = "local ws = workspace",
			Fn = function()
				local ws = workspace
				local n = 0
				for _ = 1, C do
					if ws then
						n += 1
					end
				end
				return n
			end,
		},
		{
			Name = "math (import global)",
			Fn = function()
				local n = 0
				for _ = 1, C do
					if math then
						n += 1
					end
				end
				return n
			end,
		},
	},
}

Suites[#Suites + 1] = {
	Name = "P. Build 4k eight-field objects",
	Ops = M,
	Variants = {
		{
			Name = "clone(plain stub) + 4 writes",
			Fn = function()
				local sum = 0
				for i = 1, M do
					local o = table.clone(STUB_PLAIN)
					o.Id = i
					o.X = i % 13
					o.Y = i % 7
					o.Health = 100
					BUCKET[i] = o
					sum += o.X
				end
				return sum
			end,
		},
		{
			Name = "full literal, 8 fields",
			Fn = function()
				local sum = 0
				for i = 1, M do
					local o = {
						Id = i,
						Kind = 0,
						X = i % 13,
						Y = i % 7,
						Z = 0,
						Health = 100,
						Speed = 0,
						IsAlive = false,
					}
					BUCKET[i] = o
					sum += o.X
				end
				return sum
			end,
		},
		{
			Name = "clone(stub w/ metatable) + 4",
			Fn = function()
				local sum = 0
				for i = 1, M do
					local o = table.clone(STUB_WITH_MT)
					o.Id = i
					o.X = i % 13
					o.Y = i % 7
					o.Health = 100
					BUCKET[i] = o
					sum += o.X
				end
				return sum
			end,
		},
		{
			Name = "setmetatable(clone(plain), MT)",
			Fn = function()
				local sum = 0
				for i = 1, M do
					local o = setmetatable(table.clone(STUB_PLAIN), OBJ_MT)
					o.Id = i
					o.X = i % 13
					o.Y = i % 7
					o.Health = 100
					BUCKET[i] = o
					sum += o.X
				end
				return sum
			end,
		},
		{
			Name = "setmetatable(literal, MT)",
			Fn = function()
				local sum = 0
				for i = 1, M do
					local o = setmetatable({
						Id = i,
						Kind = 0,
						X = i % 13,
						Y = i % 7,
						Z = 0,
						Health = 100,
						Speed = 0,
						IsAlive = false,
					}, OBJ_MT)
					BUCKET[i] = o
					sum += o.X
				end
				return sum
			end,
		},
	},
}

return { Probe = Probe, Suites = Suites }
