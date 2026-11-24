-- Who may open the conch command console, in both places: a role by the player's rank in the studio's group, and
-- the full role for everybody in Studio and in the test places. Also the commands both places share (gear).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Conch = require(ReplicatedStorage.Packages.conch)
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(ServerScriptService.GlobalServer.NetworkMeta)
local DatabaseService = require(script.Parent.DatabaseService)
local EquipmentService = require(script.Parent.EquipmentService)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local CommandTypes = require(ReplicatedStorage.Types.CommandTypes)
local EEquipmentIds = require(ReplicatedStorage.Types.Enums.Data.EEquipmentIds)
local EPlaceIds = require(ReplicatedStorage.Types.Enums.EPlaceIds)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local ServerNetworkConsole = NetworkMeta.Server.Console
local ServerNetworkEquipment = NetworkMeta.Server.Equipment
local args = Conch.args

local GlobalCommandsService = {}

local CONSOLE_GROUP_ID = 34796361
-- "super-user" is conch's built-in role and passes every permission check, so it is given no permissions here.
local ROLE_ADMIN = "super-user"
local ROLE_DEVELOPER = "developer"
local ROLE_MODERATOR = "moderator"
-- A developer holds the moderator's permission too, so the player-support commands need no second role.
local PERMISSION_DEV = "command.dev"
local PERMISSION_MOD = "command.mod"
-- The lowest group rank for each role; below the moderator's there is no console at all.
local MIN_ADMIN_RANK = 254
local MIN_DEVELOPER_RANK = 200
local MIN_MODERATOR_RANK = 100

local areRolesInitialized = false

-- set_role_permissions fires a network event, so it only works once the lifecycle below has started the server side
-- of conch's network: it is deferred to the first player.
local function ensureRolesInitialized()
	if areRolesInitialized then return end
	areRolesInitialized = true
	Conch.set_role_permissions(ROLE_DEVELOPER, PERMISSION_DEV, PERMISSION_MOD)
	Conch.set_role_permissions(ROLE_MODERATOR, PERMISSION_MOD)
end

local function roleForRank(rank: number): string?
	if rank >= MIN_ADMIN_RANK then return ROLE_ADMIN end
	if rank >= MIN_DEVELOPER_RANK then return ROLE_DEVELOPER end
	if rank >= MIN_MODERATOR_RANK then return ROLE_MODERATOR end
	return nil
end

-- The player's role, given and announced to their client so it binds the console; nil when they get no console.
function GlobalCommandsService.AssignRoles(player: Player): string?
	ensureRolesInitialized()
	local user = Conch.get_user(player)
	if not user then return nil end

	local role: string? = ROLE_ADMIN
	if not RunService:IsStudio() and not EPlaceIds.IsTest then
		local isOk, rank = pcall(player.GetRankInGroup, player, CONSOLE_GROUP_ID)
		role = if isOk then roleForRank(rank) else nil
	end
	if not role then return nil end

	Conch.give_roles(user, role)
	ServerNetworkConsole.AccessGranted.Fire(player)
	return role
end

local function getContextPlayer(): Player?
	return (Conch.get_command_context() :: any).executor.player
end

-- `gear give <piece|all>` gives pieces as a boss drop would (in a match, its reveal plays); `gear clear` takes every
-- piece and choice back to a new player's.
local function registerGear()
	Conch.register("gear", {
		permissions = { PERMISSION_DEV },
		description = "Give yourself equipment as a boss drop would, or clear it back to a new player's.",
		arguments = function()
			return args.overload({
				{
					description = "Give a piece, or all",
					arguments = { args.literal("give"), CommandTypes.equipmentOrAll("piece", "The piece, or all.") },
				},
				{
					description = "Clear your equipment",
					arguments = { args.literal("clear") },
				},
			})
		end,
		callback = function(verb: string, target: string?)
			local player = getContextPlayer()
			if not player or not DatabaseService.Get(player) then
				Conch.log("error", "Your profile is not loaded.")
				return
			end

			if verb == "clear" then
				DatabaseService.Update(player, function(profile)
					profile.Equipment = nil
					return true
				end)
				EquipmentService.Sync(player)
				Conch.log("normal", "Equipment cleared.")
				return
			end

			local given = 0
			for name, itemId in EEquipmentIds :: { [string]: number } do
				if target ~= "all" and string.lower(name) ~= target then continue end
				local item = DataCore.Equipment.ById[itemId]
				if item and EquipmentService.Grant(player, item) then
					given += 1
					ServerNetworkEquipment.Dropped.Fire(player, item.Id)
				end
			end
			Conch.log("normal", `Gave {given} piece(s).`)
		end,
	})
end

Conch.initiate_default_lifecycle()

GlobalCommandsService.OnStart = function()
	registerGear()
end

GlobalCommandsService.OnPlayerConnected = function(player)
	GlobalCommandsService.AssignRoles(player)
end :: TPlayerEvents.OnPlayerConnected

return Ignis.Register(GlobalCommandsService)
