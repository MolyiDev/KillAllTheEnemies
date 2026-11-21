-- Compiles every authored module at -O2, which catches the 200-local limit Selene cannot see:
--   lune run tools/lune/compile.luau src
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local failed = 0
local function walk(dir)
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			if name ~= "PlayerModule" then walk(path) end
		elseif string.sub(name, -5) == ".luau" then
			local ok, err = pcall(luau.compile, fs.readFile(path), { optimizationLevel = 2 })
			if not ok then
				failed += 1
				print("FAIL", path, err)
			end
		end
	end
end
walk(process.args[1])
print("compile failures:", failed)
