-- A helper module in a SEPARATE ModuleScript, so calls into it cross a compilation unit. Luau's
-- interprocedural optimizations are limited to one module, so this is the case that actually matches how
-- Tools.Lerp is called in this codebase.
--
-- Parented as `Helpers`, a sibling of the pass 3 suite modules.
local Helpers = {}

function Helpers.Lerp(a, b, t)
	return a + (b - a) * t
end

return Helpers
