-- The lobby's console commands. Every one needs the developer permission, which GlobalCommandsService gives by group
-- rank (everybody in Studio and the test places).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Conch = require(ReplicatedStorage.Packages.conch)
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local DatabaseService = require(ServerScriptService.GlobalServer.Services.DatabaseService)

local args = Conch.args

local CommandsService = {}

local PERMISSION_DEV = "command.dev"
-- Profile.Sync sends Gems as a u32.
local MAX_GEMS = 2 ^ 32 - 1

local function getContextPlayer(): Player?
	return (Conch.get_command_context() :: any).executor.player
end

local function registerGems()
	Conch.register("gems", {
		permissions = { PERMISSION_DEV },
		description = "Give yourself Gems.",
		arguments = function()
			return args.number("amount", "How many Gems to add.")
		end,
		callback = function(amount: number)
			local player = getContextPlayer()
			if not player then return end
			local gems = math.floor(amount)
			-- Written so NaN fails it too.
			if not (gems >= 1) then
				Conch.log("error", "The amount must be at least 1.")
				return
			end

			local added, total = 0, 0
			local isGranted = DatabaseService.Update(player, function(profile)
				added = math.min(gems, MAX_GEMS - profile.Gems)
				profile.Gems += added
				total = profile.Gems
				return true
			end)
			if not isGranted then
				Conch.log("error", "Your profile is not loaded.")
				return
			end
			DatabaseService.SaveAsync(player)

			Conch.log("normal", `Added {added} Gems ({total} now).`)
		end,
	})
end

CommandsService.OnStart = function()
	registerGems()
end

return Ignis.Register(CommandsService)
