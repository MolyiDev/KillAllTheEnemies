-- Who may open the conch command console, in both places: a role by the player's rank in the studio's group, and
-- the full role for everybody in Studio and in the test places.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Conch = require(ReplicatedStorage.Packages.conch)
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(ServerScriptService.GlobalServer.NetworkMeta)
local EPlaceIds = require(ReplicatedStorage.Types.Enums.EPlaceIds)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local ServerNetworkConsole = NetworkMeta.Server.Console

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

Conch.initiate_default_lifecycle()

GlobalCommandsService.OnPlayerConnected = function(player)
	GlobalCommandsService.AssignRoles(player)
end :: TPlayerEvents.OnPlayerConnected

return Ignis.Register(GlobalCommandsService)
