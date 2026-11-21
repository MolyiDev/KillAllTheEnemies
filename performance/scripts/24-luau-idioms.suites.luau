-- LUAU IDIOM MICROBENCHMARKS - suite definitions.
--
-- This module is injected THREE times as a child of the driver, byte-identical except for the header
-- directives the driver prepends:
--
--   O1      (no directive)          what every script in this repo gets by default
--   O2      --!optimize 2           what CLAUDE.md tells us to put on math-heavy modules
--   NATIVE  --!native --!optimize 2 what CLAUDE.md tells us to put on Actor scripts
--
-- Keep the body identical across the three copies or the comparison is meaningless.
--
-- Every variant inside a suite performs the SAME number of logical operations (`Ops`), so ns/op is
-- comparable down a column. Across suites it is not - each suite measures a different unit of work.
--
-- Every variant returns a checksum. The driver prints them and flags any suite whose variants disagree,
-- which is the guard against a variant being accidentally optimized into nothing or measuring the wrong
-- thing.

local N = 10000 -- array / dict element count
local M = 4000 -- objects or closures built per run
local C = 20000 -- calls per run

-- ── fixtures ────────────────────────────────────────────────────────────────────────────────────────

local ARRAY = table.create(N)
for i = 1, N do
	ARRAY[i] = i % 97
end

local DICT = {}
for i = 1, N do
	DICT["key" .. i] = i % 97
end

local STR = string.rep("abcdefghij", 100)

local BUCKET = table.create(M)

local STUB_PLAIN = { Id = 0, Kind = 0, X = 0, Y = 0, Z = 0, Health = 0, Speed = 0, IsAlive = false }

local OBJ_MT = {}
OBJ_MT.__index = OBJ_MT
function OBJ_MT.Step(self)
	return self.X + self.Y
end

local STUB_WITH_MT =
	setmetatable({ Id = 0, Kind = 0, X = 0, Y = 0, Z = 0, Health = 0, Speed = 0, IsAlive = false }, OBJ_MT)

-- one object, reused by the dispatch suites
local OBJ = setmetatable({ X = 3, Y = 4 }, OBJ_MT)

-- __index chain three deep: LEAF -> MID -> BASE, method lives on BASE
local BASE = {}
BASE.__index = BASE
function BASE.Step(self)
	return self.X + self.Y
end
local MID = setmetatable({}, BASE)
MID.__index = MID
local LEAF = setmetatable({}, MID)
LEAF.__index = LEAF
local OBJ_DEEP = setmetatable({ X = 3, Y = 4 }, LEAF)

-- __index as a function
local FN_MT = {}
FN_MT.__index = function(_, key)
	if key == "Step" then return BASE.Step end
	return nil
end
local OBJ_FNINDEX = setmetatable({ X = 3, Y = 4 }, FN_MT)

-- static field carried on the class table
local CLASS = { Static = 7 }
CLASS.__index = CLASS
local OBJ_STATIC = setmetatable({ X = 3 }, CLASS)

-- four differently shaped tables that all carry X, for the inline-cache shape test
local SHAPES = {
	{ X = 1 },
	{ A = 1, X = 2 },
	{ A = 1, B = 2, C = 3, X = 3 },
	{ Q = 1, R = 2, X = 4, S = 3, T = 5 },
}
local SHAPE_UNIFORM = {
	{ X = 1 },
	{ X = 2 },
	{ X = 3 },
	{ X = 4 },
}

-- module-scope immutable local, for the closure-capture suite
local BIAS = 1

local function NAMED(a)
	return a + 1
end

local function MODULE_LERP(a, b, t)
	return a + (b - a) * t
end

local TOOLS = {
	Lerp = function(a, b, t)
		return a + (b - a) * t
	end,
}

-- ── suites ──────────────────────────────────────────────────────────────────────────────────────────

local Suites = {}

Suites[#Suites + 1] = {
	Name = "A. Array iteration, sum 10k numbers",
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
			Name = "for i = 1, n (len hoisted)",
			Fn = function()
				local t = ARRAY
				local n = #t
				local sum = 0
				for i = 1, n do
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
			Name = "for i, v in t (index kept)",
			Fn = function()
				local t = ARRAY
				local sum = 0
				local last = 0
				for i, v in t do
					sum += v
					last = i
				end
				return sum + last - last
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
	Name = "B. Hash iteration, sum 10k dict values",
	Ops = N,
	Variants = {
		{
			Name = "for _, v in d (generalized)",
			Fn = function()
				local d = DICT
				local sum = 0
				for _, v in d do
					sum += v
				end
				return sum
			end,
		},
		{
			Name = "for _, v in pairs(d)",
			Fn = function()
				local d = DICT
				local sum = 0
				for _, v in pairs(d) do
					sum += v
				end
				return sum
			end,
		},
		{
			Name = "for _, v in next, d",
			Fn = function()
				local d = DICT
				local sum = 0
				for _, v in next, d do
					sum += v
				end
				return sum
			end,
		},
	},
}

Suites[#Suites + 1] = {
	Name = "C. Append 10k elements",
	Ops = N,
	Variants = {
		{
			Name = "{} + t[#t + 1] = v",
			Fn = function()
				local t = {}
				for i = 1, N do
					t[#t + 1] = i % 97
				end
				return #t
			end,
		},
		{
			Name = "{} + table.insert(t, v)",
			Fn = function()
				local t = {}
				for i = 1, N do
					table.insert(t, i % 97)
				end
				return #t
			end,
		},
		{
			Name = "{} + counter t[c] = v",
			Fn = function()
				local t = {}
				local c = 0
				for i = 1, N do
					c += 1
					t[c] = i % 97
				end
				return #t
			end,
		},
		{
			Name = "create(n) + t[#t + 1] = v",
			Fn = function()
				local t = table.create(N)
				for i = 1, N do
					t[#t + 1] = i % 97
				end
				return #t
			end,
		},
		{
			Name = "create(n) + table.insert",
			Fn = function()
				local t = table.create(N)
				for i = 1, N do
					table.insert(t, i % 97)
				end
				return #t
			end,
		},
		{
			Name = "create(n) + t[i] = v",
			Fn = function()
				local t = table.create(N)
				for i = 1, N do
					t[i] = i % 97
				end
				return #t
			end,
		},
	},
}

Suites[#Suites + 1] = {
	Name = "D. Build 4k eight-field objects",
	Ops = M,
	Variants = {
		{
			Name = "table.clone(STUB) + 4 writes",
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
			Name = "{} + 8 field writes",
			Fn = function()
				local sum = 0
				for i = 1, M do
					local o = {}
					o.Id = i
					o.Kind = 0
					o.X = i % 13
					o.Y = i % 7
					o.Z = 0
					o.Health = 100
					o.Speed = 0
					o.IsAlive = false
					BUCKET[i] = o
					sum += o.X
				end
				return sum
			end,
		},
		{
			Name = "clone(STUB w/ metatable) + 4",
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
			Name = "setmetatable(clone(STUB), MT)",
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

Suites[#Suites + 1] = {
	Name = "E. Create + call 4k closures",
	Ops = M,
	Variants = {
		{
			Name = "no closure, named upvalue fn",
			Fn = function()
				local sum = 0
				for i = 1, M do
					sum += NAMED(i)
				end
				return sum
			end,
		},
		{
			Name = "closure, no upvalues",
			Fn = function()
				local sum = 0
				for i = 1, M do
					local f = function(a)
						return a + 1
					end
					sum += f(i)
				end
				return sum
			end,
		},
		{
			Name = "closure, module-scope upvalue",
			Fn = function()
				local sum = 0
				for i = 1, M do
					local f = function(a)
						return a + BIAS
					end
					sum += f(i)
				end
				return sum
			end,
		},
		{
			Name = "closure, immutable local upval",
			Fn = function()
				local sum = 0
				for i = 1, M do
					local bias = 1
					local f = function(a)
						return a + bias
					end
					sum += f(i)
				end
				return sum
			end,
		},
		{
			Name = "closure, mutable local upval",
			Fn = function()
				local sum = 0
				for i = 1, M do
					local bias = 1
					local f = function(a)
						bias += 0
						return a + bias
					end
					sum += f(i)
				end
				return sum
			end,
		},
		{
			Name = "closure, value passed as param",
			Fn = function()
				local sum = 0
				for i = 1, M do
					local f = function(self, a)
						return a + self
					end
					sum += f(1, i)
				end
				return sum
			end,
		},
	},
}

Suites[#Suites + 1] = {
	Name = "F. 20k lerp calls",
	Ops = C,
	Variants = {
		{
			Name = "inline expression",
			Fn = function()
				local sum = 0
				for i = 1, C do
					local a, b, t = i % 13, i % 7, 0.5
					sum += a + (b - a) * t
				end
				return sum
			end,
		},
		{
			Name = "local function, same scope",
			Fn = function()
				local function lerp(a, b, t)
					return a + (b - a) * t
				end
				local sum = 0
				for i = 1, C do
					sum += lerp(i % 13, i % 7, 0.5)
				end
				return sum
			end,
		},
		{
			Name = "module-scope local function",
			Fn = function()
				local sum = 0
				for i = 1, C do
					sum += MODULE_LERP(i % 13, i % 7, 0.5)
				end
				return sum
			end,
		},
		{
			Name = "Tools.Lerp (table field)",
			Fn = function()
				local sum = 0
				for i = 1, C do
					sum += TOOLS.Lerp(i % 13, i % 7, 0.5)
				end
				return sum
			end,
		},
		{
			Name = "localized Tools.Lerp",
			Fn = function()
				local lerp = TOOLS.Lerp
				local sum = 0
				for i = 1, C do
					sum += lerp(i % 13, i % 7, 0.5)
				end
				return sum
			end,
		},
	},
}

Suites[#Suites + 1] = {
	Name = "G. 20k math.floor calls",
	Ops = C,
	Variants = {
		{
			Name = "math.floor(x) (import)",
			Fn = function()
				local sum = 0
				for i = 1, C do
					sum += math.floor(i * 0.5)
				end
				return sum
			end,
		},
		{
			Name = "local floor = math.floor",
			Fn = function()
				local floor = math.floor
				local sum = 0
				for i = 1, C do
					sum += floor(i * 0.5)
				end
				return sum
			end,
		},
		{
			Name = "//1 integer division",
			Fn = function()
				local sum = 0
				for i = 1, C do
					sum += (i * 0.5) // 1
				end
				return sum
			end,
		},
	},
}

Suites[#Suites + 1] = {
	Name = "H. 20k string.byte calls",
	Ops = C,
	Variants = {
		{
			Name = "string.byte(s, i) (fastcall)",
			Fn = function()
				local s = STR
				local sum = 0
				for i = 1, C do
					sum += string.byte(s, (i % 1000) + 1)
				end
				return sum
			end,
		},
		{
			Name = "localized string.byte",
			Fn = function()
				local s = STR
				local byte = string.byte
				local sum = 0
				for i = 1, C do
					sum += byte(s, (i % 1000) + 1)
				end
				return sum
			end,
		},
		{
			Name = "s:byte(i) (namecall)",
			Fn = function()
				local s = STR
				local sum = 0
				for i = 1, C do
					sum += s:byte((i % 1000) + 1)
				end
				return sum
			end,
		},
	},
}

Suites[#Suites + 1] = {
	Name = "I. 20k mutable-global reads",
	Ops = C,
	Variants = {
		{
			Name = "workspace.Gravity",
			Fn = function()
				local sum = 0
				for _ = 1, C do
					sum += workspace.Gravity
				end
				return sum
			end,
		},
		{
			Name = "local ws = workspace",
			Fn = function()
				local ws = workspace
				local sum = 0
				for _ = 1, C do
					sum += ws.Gravity
				end
				return sum
			end,
		},
		{
			Name = "cached local gravity",
			Fn = function()
				local g = workspace.Gravity
				local sum = 0
				for _ = 1, C do
					sum += g
				end
				return sum
			end,
		},
	},
}

Suites[#Suites + 1] = {
	Name = "J. 20k method dispatches",
	Ops = C,
	Variants = {
		{
			Name = "obj:Method()",
			Fn = function()
				local o = OBJ
				local sum = 0
				for _ = 1, C do
					sum += o:Step()
				end
				return sum
			end,
		},
		{
			Name = "obj.Method(obj)",
			Fn = function()
				local o = OBJ
				local sum = 0
				for _ = 1, C do
					sum += o.Step(o)
				end
				return sum
			end,
		},
		{
			Name = "cached local method(obj)",
			Fn = function()
				local o = OBJ
				local step = OBJ_MT.Step
				local sum = 0
				for _ = 1, C do
					sum += step(o)
				end
				return sum
			end,
		},
		{
			Name = "obj:Method(), __index 3 deep",
			Fn = function()
				local o = OBJ_DEEP
				local sum = 0
				for _ = 1, C do
					sum += o:Step()
				end
				return sum
			end,
		},
		{
			Name = "obj:Method(), __index fn",
			Fn = function()
				local o = OBJ_FNINDEX
				local sum = 0
				for _ = 1, C do
					sum += o:Step()
				end
				return sum
			end,
		},
	},
}

Suites[#Suites + 1] = {
	Name = "K. 20k field reads",
	Ops = C,
	Variants = {
		{
			Name = "own field, obj.X",
			Fn = function()
				local o = OBJ
				local sum = 0
				for _ = 1, C do
					sum += o.X
				end
				return sum
			end,
		},
		{
			Name = "inherited, obj.Static",
			Fn = function()
				local o = OBJ_STATIC
				local sum = 0
				for _ = 1, C do
					sum += o.Static
				end
				return sum
			end,
		},
		{
			Name = "class table, Class.Static",
			Fn = function()
				local c = CLASS
				local sum = 0
				for _ = 1, C do
					sum += c.Static
				end
				return sum
			end,
		},
		{
			Name = "obj[const string]",
			Fn = function()
				local o = OBJ
				local sum = 0
				for _ = 1, C do
					sum += o["X"]
				end
				return sum
			end,
		},
		{
			Name = "monomorphic .X over 4 tables",
			Fn = function()
				local s = SHAPE_UNIFORM
				local sum = 0
				for i = 1, C do
					sum += s[(i % 4) + 1].X
				end
				return sum
			end,
		},
		{
			Name = "polymorphic .X over 4 shapes",
			Fn = function()
				local s = SHAPES
				local sum = 0
				for i = 1, C do
					sum += s[(i % 4) + 1].X
				end
				return sum
			end,
		},
	},
}

Suites[#Suites + 1] = {
	Name = "L. 20k vector ops",
	Ops = C,
	Variants = {
		{
			Name = "Vector3 add + mul",
			Fn = function()
				local acc = Vector3.zero
				local step = Vector3.new(1, 2, 3)
				for _ = 1, C do
					acc += step * 0.5
				end
				return math.floor(acc.X)
			end,
		},
		{
			Name = "three separate numbers",
			Fn = function()
				local ax, ay, az = 0, 0, 0
				local sx, sy, sz = 1, 2, 3
				for _ = 1, C do
					ax += sx * 0.5
					ay += sy * 0.5
					az += sz * 0.5
				end
				return math.floor(ax)
			end,
		},
		{
			Name = "Vector3.new per iteration",
			Fn = function()
				local acc = Vector3.zero
				for _ = 1, C do
					acc += Vector3.new(0.5, 1, 1.5)
				end
				return math.floor(acc.X)
			end,
		},
	},
}

return Suites
