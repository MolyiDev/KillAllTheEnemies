-- Loads the project's modules under lune by mapping Roblox paths onto files, with the engine stubbed.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local ROOT = ""
local MOUNTS = {
	["ReplicatedStorage/Packages"] = "Packages",
	["ReplicatedStorage/Shared"] = "src/Game/Shared",
	["ReplicatedStorage/GlobalShared"] = "src/Global/Shared",
	["ReplicatedStorage/Types"] = "src/Global/Types",
	["ReplicatedStorage/Data"] = "src/Global/Data",
	["ServerScriptService/Server"] = "src/Game/Server",
	["StarterPlayer/StarterPlayerScripts/Client"] = "src/Game/Client",
}
local STUBS = {
	["ReplicatedStorage/Packages/jabby"] = { register = function() end, applets = { world = {} } },
	["ReplicatedStorage/Packages/Butler"] = {},
	["ReplicatedStorage/Packages/Ignis"] = {
		Register = function(module)
			return module
		end,
	},
	["ReplicatedStorage/Packages/Signal"] = {
		new = function()
			local listeners = {}
			return {
				Connect = function(_, fn)
					table.insert(listeners, fn)
				end,
				Fire = function(_, ...)
					for _, fn in listeners do
						fn(...)
					end
				end,
			}
		end,
	},
}

local Harness = { Gravity = 196.2, Heartbeats = {} }
local cache = {}
local proxyOf

local function fileFor(path: string): string?
	for prefix, dir in MOUNTS do
		if path == prefix or string.sub(path, 1, #prefix + 1) == prefix .. "/" then
			local rest = string.sub(path, #prefix + 2)
			local file = ROOT .. "/" .. dir .. (if rest ~= "" then "/" .. rest else "")
			for _, candidate in { file .. ".luau", file .. ".lua", file .. "/init.luau", file .. "/init.lua" } do
				if fs.isFile(candidate) then return candidate end
			end
			local project = file .. "/default.project.json"
			if fs.isFile(project) then
				local tree = serde.decode("json", fs.readFile(project)).tree
				if tree["$path"] then return file .. "/" .. tree["$path"] end
			end
			if fs.isDir(file) then return file end
		end
	end
	return nil
end

local signal = {
	Connect = function(_, fn)
		table.insert(Harness.Heartbeats, fn)
		return { Disconnect = function() end }
	end,
}
local services = {
	RunService = {
		Heartbeat = signal,
		PreSimulation = signal,
		PreRender = signal,
		IsStudio = function()
			return true
		end,
	},
	Workspace = {
		Gravity = 196.2,
		FindFirstChild = function()
			return nil
		end,
	},
}

-- Roblox's Random, as far as the modules loaded here use it. Not the engine's sequence: only as repeatable.
local Random = {}
Random.__index = Random

function Random.new(seed: number?)
	return setmetatable(
		{ State = (math.floor(seed or os.clock() * 1e6) * 2654435761 + 1013904223) % 4294967296 },
		Random
	)
end

function Random:NextNumber(low: number?, high: number?): number
	local state = self.State
	state = bit32.bxor(state, bit32.lshift(state, 13))
	state = bit32.bxor(state, bit32.rshift(state, 17))
	state = bit32.bxor(state, bit32.lshift(state, 5))
	self.State = state
	local unit = state / 4294967296
	return if low then low + (high - low) * unit else unit
end

function Random:NextInteger(low: number, high: number): number
	return math.min(low + math.floor(self:NextNumber() * (high - low + 1)), high)
end

Harness.Random = Random

local function requireModule(proxy)
	local path = rawget(proxy, "__path")
	if STUBS[path] then return STUBS[path] end
	if cache[path] ~= nil then return cache[path] end
	local file = fileFor(path)
	assert(file and fs.isFile(file), "cannot resolve " .. path)
	local isInit = string.find(file, "/init%.luau?$") ~= nil
	local env = setmetatable({
		game = proxyOf("game"),
		script = proxyOf(path),
		require = requireModule,
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		Vector2 = roblox.Vector2,
		Random = Random,
		Color3 = roblox.Color3,
		debug = { profilebegin = function() end, profileend = function() end },
		warn = print,
		task = require("@lune/task"),
	}, { __index = _G })
	local fn =
		luau.load(luau.compile(fs.readFile(file)), { debugName = path, environment = env, codegenEnabled = true })
	local result = fn()
	cache[path] = result
	return result
end

function proxyOf(path: string)
	return setmetatable({ __path = path }, {
		__index = function(self, key)
			if key == "Parent" then
				local parent = string.match(path, "^(.*)/[^/]+$")
				return proxyOf(parent or "game")
			end
			if key == "GetService" then
				return function(_, name)
					return services[name] or proxyOf(name)
				end
			end
			if key == "WaitForChild" then
				return function(_, child)
					return proxyOf(path .. "/" .. child)
				end
			end
			if key == "FindFirstChild" then
				return function()
					return nil
				end
			end
			if key == "GetChildren" then
				return function()
					local dir = fileFor(path)
					local out = {}
					if dir and fs.isDir(dir) then
						for _, name in fs.readDir(dir) do
							local base = string.match(name, "^(.-)%.luau?$")
							if base then
								local child = proxyOf(path .. "/" .. base)
								rawset(child, "IsA", function(_, class)
									return class == "ModuleScript"
								end)
								table.insert(out, child)
							end
						end
					end
					return out
				end
			end
			if key == "Name" then return string.match(path, "[^/]+$") end
			return proxyOf(path .. "/" .. key)
		end,
	})
end

function Harness.require(path: string)
	return requireModule(proxyOf(path))
end

function Harness.step(dt: number)
	for _, fn in Harness.Heartbeats do
		fn(dt)
	end
end

return function(root)
	ROOT = root
	return Harness
end
