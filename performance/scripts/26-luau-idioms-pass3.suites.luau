-- PASS 3 suites. Injected twice as children of the pass 3 driver, byte-identical except for the header
-- directives (none / `--!native` + `--!optimize 2`). O2 is not run here: pass 2 established it is a no-op.
--
-- Pass 2 found that a one-line helper costs nothing over writing the expression by hand. That result was
-- measured with the helper defined in the SAME module, which is not how `Tools.Lerp` is called anywhere in
-- this codebase - there it comes through a `require`. Luau's interprocedural optimizations stop at the
-- module boundary, so this pass puts the same helper in a separate ModuleScript (`Helpers`, a sibling) and
-- calls it both ways.
--
-- The `floor` row is the same loop with the lerp removed, so the marginal cost of each call form is
-- (row - floor) rather than a ratio against a baseline that already includes the loop and the table read.

local Helpers = require(script.Parent.Helpers)

local N = 10000
local C = 20000

local ARGS = table.create(C)
for i = 1, C do
	ARGS[i] = i % 13
end

local REUSED = table.create(N)

local function MODULE_LERP(a, b, t)
	return a + (b - a) * t
end

local TOOLS = {
	Lerp = function(a, b, t)
		return a + (b - a) * t
	end,
}

local Suites = {}

Suites[#Suites + 1] = {
	Name = "Q. 20k lerps, in-module vs cross-module",
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
			Name = "in-module local function",
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
			Name = "in-module table field",
			Fn = function()
				local t = ARGS
				local sum = 0
				for i = 1, C do
					sum += TOOLS.Lerp(t[i], 10, 0.5)
				end
				return sum
			end,
		},
		{
			Name = "cross-module Helpers.Lerp",
			Fn = function()
				local t = ARGS
				local sum = 0
				for i = 1, C do
					sum += Helpers.Lerp(t[i], 10, 0.5)
				end
				return sum
			end,
		},
		{
			Name = "cross-module, localized",
			Fn = function()
				local lerp = Helpers.Lerp
				local t = ARGS
				local sum = 0
				for i = 1, C do
					sum += lerp(t[i], 10, 0.5)
				end
				return sum
			end,
		},
	},
}

Suites[#Suites + 1] = {
	Name = "R. Fill a 10k array, fresh vs reused",
	Ops = N,
	Variants = {
		{
			Name = "fresh {} each time",
			Fn = function()
				local t = {}
				for i = 1, N do
					t[i] = i % 97
				end
				return #t
			end,
		},
		{
			Name = "fresh table.create(n)",
			Fn = function()
				local t = table.create(N)
				for i = 1, N do
					t[i] = i % 97
				end
				return #t
			end,
		},
		{
			Name = "reused + table.clear",
			Fn = function()
				local t = REUSED
				table.clear(t)
				for i = 1, N do
					t[i] = i % 97
				end
				return #t
			end,
		},
		{
			Name = "reused, overwrite in place",
			Fn = function()
				local t = REUSED
				for i = 1, N do
					t[i] = i % 97
				end
				return #t
			end,
		},
	},
}

return Suites
