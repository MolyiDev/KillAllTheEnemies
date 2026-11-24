-- The lobby's console commands. Every one needs the developer permission, which GlobalCommandsService gives by group
-- rank (everybody in Studio and the test places).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Conch = require(ReplicatedStorage.Packages.conch)
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local ClassesService = require(script.Parent.ClassesService)
local LoadoutService = require(script.Parent.LoadoutService)
local LobbyService = require(script.Parent.LobbyService)
local RangeService = require(script.Parent.RangeService)
local DatabaseService = require(ServerScriptService.GlobalServer.Services.DatabaseService)
local EquipmentService = require(ServerScriptService.GlobalServer.Services.EquipmentService)
local AbilitiesCore = require(ReplicatedStorage.GlobalShared.Core.AbilitiesCore)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local EquipmentCore = require(ReplicatedStorage.GlobalShared.Core.EquipmentCore)
local LoadoutCore = require(ReplicatedStorage.GlobalShared.Core.LoadoutCore)
local MapsCore = require(ReplicatedStorage.GlobalShared.Core.MapsCore)
local QuestsCore = require(ReplicatedStorage.GlobalShared.Core.QuestsCore)
local CommandTypes = require(ReplicatedStorage.Types.CommandTypes)
local EClassesIds = require(ReplicatedStorage.Types.Enums.Data.EClassesIds)
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local TData = require(ReplicatedStorage.Types.TData)
local TProfile = require(ReplicatedStorage.Types.TProfile)

local args = Conch.args

local CommandsService = {}

local PERMISSION_DEV = "command.dev"
local ALL = "all"
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

-- The gives and clears below change the profile's draft only: `commit` writes and saves them, so a command that does
-- several is still one write and one save.

-- Owns `target`'s guns (a lowercased EGunsIds key, or all) at the top level. Returns how many changed.
local function giveGuns(profile: TProfile.TProfile, target: string): number
	local owned = profile.Loadout.Owned
	local given = 0
	for name, gunId in EGunsIds :: { [string]: number } do
		if target ~= ALL and string.lower(name) ~= target then continue end
		local gun = DataCore.Guns.ById[gunId]
		if not gun or owned[gun.Name] == LoadoutCore.MAX_LEVEL then continue end
		owned[gun.Name] = LoadoutCore.MAX_LEVEL
		given += 1
	end

	return given
end

-- Back to a new player's loadout: the starters, nothing upgraded, nothing on the back.
local function clearGuns(profile: TProfile.TProfile)
	profile.Loadout = { Owned = {}, Equipped = {} }
end

-- Owns `target`'s classes (a lowercased EClassesIds key, or all) with every ability at the top level. Returns how many
-- changed.
local function giveClasses(profile: TProfile.TProfile, target: string): number
	local levels = profile.AbilityLevels or {}
	local given = 0
	for name, classId in EClassesIds :: { [string]: number } do
		if target ~= ALL and string.lower(name) ~= target then continue end
		local class = DataCore.Classes.ById[classId]
		if not class then continue end
		local isChanged = false
		if not table.find(profile.OwnedClasses, class.Id) then
			table.insert(profile.OwnedClasses, class.Id)
			isChanged = true
		end
		for slot = 1, #class.Abilities + 1 do
			local key = AbilitiesCore.LevelKey(class, AbilitiesCore.AbilityAt(class, slot) :: TData.TAbility)
			if levels[key] == AbilitiesCore.MAX_LEVEL then continue end
			levels[key] = AbilitiesCore.MAX_LEVEL
			isChanged = true
		end
		if isChanged then
			given += 1
		end
	end
	profile.AbilityLevels = levels

	return given
end

-- Back to a new player's classes (DatabaseService's default): Human only, picked, nothing upgraded.
local function clearClasses(profile: TProfile.TProfile)
	profile.OwnedClasses = { EClassesIds.Human }
	profile.SelectedClass = EClassesIds.Human
	profile.AbilityLevels = nil
end

-- Every piece, without the boss drop's reveal that `gear give` plays. Returns how many were new.
local function giveEquipment(profile: TProfile.TProfile): number
	local save = profile.Equipment or DatabaseService.DeepClone(EquipmentCore.EMPTY)
	local given = 0
	for _, item in DataCore.Equipment.All do
		if EquipmentCore.IsOwned(save, item) then continue end
		save.Owned[item.Name] = true
		given += 1
	end
	profile.Equipment = save

	return given
end

local function clearEquipment(profile: TProfile.TProfile)
	profile.Equipment = nil
end

local function syncGuns(player: Player)
	RangeService.LoadoutChanged(player)
	LoadoutService.Sync(player)
end

local function syncAll(player: Player)
	syncGuns(player)
	ClassesService.Sync(player)
	EquipmentService.Sync(player)
end

-- Runs `mutate` on the command player's profile as one write and one save, then `sync` (when the change needs one)
-- sends their screens what changed. False, with the error logged, when their profile is not loaded.
local function commit(
	mutate: (profile: TProfile.TProfile, player: Player) -> (),
	sync: ((player: Player) -> ())?
): boolean
	local player = getContextPlayer()
	if not player or not DatabaseService.Update(player, function(profile)
		mutate(profile, player)
	end) then
		Conch.log("error", "Your profile is not loaded.")
		return false
	end

	DatabaseService.SaveAsync(player)
	if sync then sync(player) end
	return true
end

-- Fills every unclaimed quest on `kind`'s current board to its goal, so it is ready to claim. Returns how many moved.
local function completeQuests(profile: TProfile.TProfile, kind: QuestsCore.TBoardKind, userId: number): number
	local board = QuestsCore.Current(profile.Quests, kind, userId, os.time())
	local completed = 0
	for slot, name in board.Names do
		local quest = QuestsCore.ByName[name]
		if not quest or board.Claimed[slot] or (board.Progress[slot] or 0) >= quest.Goal then continue end
		board.Progress[slot] = quest.Goal
		completed += 1
	end
	profile.Quests[kind] = board

	return completed
end

local function clearAll(profile: TProfile.TProfile)
	clearGuns(profile)
	clearClasses(profile)
	clearEquipment(profile)
end

-- `weapons give <gun|all>` owns guns at the top level; `weapons clear` takes the loadout back to a new player's.
local function registerWeapons()
	Conch.register("weapons", {
		permissions = { PERMISSION_DEV },
		description = "Give yourself guns at the top level, or clear the loadout back to a new player's.",
		arguments = function()
			return args.overload({
				{
					description = "Give a gun, or all",
					arguments = { args.literal("give"), CommandTypes.gunOrAll("gun", "The gun, or all.") },
				},
				{
					description = "Clear your guns",
					arguments = { args.literal("clear") },
				},
			})
		end,
		callback = function(verb: string, target: string?)
			if verb == "clear" then
				if commit(clearGuns, syncGuns) then Conch.log("normal", "Guns cleared.") end
				return
			end

			local given = 0
			local isDone = commit(function(profile)
				given = giveGuns(profile, target or ALL)
			end, syncGuns)
			if isDone then Conch.log("normal", `Gave {given} gun(s).`) end
		end,
	})
end

-- `classes give <class|all>` owns classes with every ability at the top level; `classes clear` takes them back to a
-- new player's.
local function registerClasses()
	Conch.register("classes", {
		permissions = { PERMISSION_DEV },
		description = "Give yourself classes with every ability at the top level, or clear them back to a new player's.",
		arguments = function()
			return args.overload({
				{
					description = "Give a class, or all",
					arguments = { args.literal("give"), CommandTypes.classOrAll("class", "The class, or all.") },
				},
				{
					description = "Clear your classes",
					arguments = { args.literal("clear") },
				},
			})
		end,
		callback = function(verb: string, target: string?)
			if verb == "clear" then
				if commit(clearClasses, ClassesService.Sync) then Conch.log("normal", "Classes cleared.") end
				return
			end

			local given = 0
			local isDone = commit(function(profile)
				given = giveClasses(profile, target or ALL)
			end, ClassesService.Sync)
			if isDone then Conch.log("normal", `Gave {given} class(es).`) end
		end,
	})
end

-- `unlock all` gives every gun, class and piece of equipment; `unlock clear` takes all three back to a new player's.
local function registerUnlock()
	Conch.register("unlock", {
		permissions = { PERMISSION_DEV },
		description = "Unlock every gun, class and piece of equipment, or clear them back to a new player's.",
		arguments = function()
			return args.overload({
				{
					description = "Unlock everything",
					arguments = { args.literal("all") },
				},
				{
					description = "Clear every unlock",
					arguments = { args.literal("clear") },
				},
			})
		end,
		callback = function(verb: string)
			if verb == "clear" then
				if commit(clearAll, syncAll) then Conch.log("normal", "Guns, classes and equipment cleared.") end
				return
			end

			local guns, classes, pieces = 0, 0, 0
			local isDone = commit(function(profile)
				guns = giveGuns(profile, ALL)
				classes = giveClasses(profile, ALL)
				pieces = giveEquipment(profile)
			end, syncAll)
			if isDone then
				Conch.log("normal", `Gave {guns} gun(s), {classes} class(es) and {pieces} piece(s) of equipment.`)
			end
		end,
	})
end

-- `quest <daily|weekly|all>` fills the current board's quests to their goals, ready to claim on the quests screen.
local function registerQuest()
	Conch.register("quest", {
		permissions = { PERMISSION_DEV },
		description = "Complete your daily or weekly quests, or both, ready to claim.",
		arguments = function()
			return CommandTypes.questBoardOrAll("board", "Daily, weekly, or all.")
		end,
		callback = function(target: string)
			local completed = 0
			-- No sync: QuestsService sends the boards on every profile write.
			local isDone = commit(function(profile, player)
				for _, kind in QuestsCore.BOARDS do
					if target ~= ALL and string.lower(kind) ~= target then continue end
					completed += completeQuests(profile, kind, player.UserId)
				end
			end)
			if isDone then Conch.log("normal", `Completed {completed} quest(s).`) end
		end,
	})
end

-- The place along the path of the map `target` names (a lowercased Name), the last for "all"; nil for none.
local function mapIndexOf(target: string): number?
	if target == ALL then return #MapsCore.LIST end
	for index, map in MapsCore.LIST do
		if string.lower(map.Name) == target then return index end
	end

	return nil
end

-- Meets the requirement of every map up to `last` (the path is linear): the level the furthest one needs (kept if
-- already past it), and each boss beaten as often as the map after it asks. Their unlocks are left to play on the
-- party screen.
local function unlockMaps(profile: TProfile.TProfile, last: number)
	local kills = profile.BossKills or {}
	for index = 1, last do
		local map = MapsCore.LIST[index]
		profile.Level = math.max(profile.Level, map.UnlockLevel)
		local previous = MapsCore.PreviousOf(map)
		if previous then kills[previous.Name] = math.max(kills[previous.Name] or 0, map.UnlockBossKills) end
	end
	profile.BossKills = kills
end

-- Shuts every map from `first` on (the path is linear, so the ones after it go too): the bosses that open them
-- unbeaten and their unlocks unplayed. The level stays: it is the whole profile's.
local function lockMaps(profile: TProfile.TProfile, first: number)
	local kills = profile.BossKills or {}
	local shown = profile.MapsShown or {}
	for index = first, #MapsCore.LIST do
		local map = MapsCore.LIST[index]
		shown[map.Name] = nil
		local previous = MapsCore.PreviousOf(map)
		if previous then kills[previous.Name] = nil end
	end
	profile.BossKills = if next(kills) then kills else nil
	profile.MapsShown = if next(shown) then shown else nil
end

-- `maps unlock <map|all>` meets the requirements up to that map, so each unlock plays on the party screen; `maps lock
-- <map|all>` shuts it and every map after it; `maps replay` plays every open map's unlock again; `maps bosskills <map>
-- <amount>` sets how many times that map's boss has been beaten.
local function registerMaps()
	Conch.register("maps", {
		permissions = { PERMISSION_DEV },
		description = "Test the maps: unlock or lock them, replay their unlocks, or set boss kills.",
		arguments = function()
			return args.overload({
				{
					description = "Unlock a map and every one before it, or all: each unlock plays on the party screen",
					arguments = { args.literal("unlock"), CommandTypes.mapOrAll("map", "The map, or all.") },
				},
				{
					description = "Lock a map and every one after it, or all, as if their bosses were never beaten",
					arguments = { args.literal("lock"), CommandTypes.mapOrAll("map", "The map, or all.") },
				},
				{
					description = "Show every open map as just unlocked, so each unlock plays again",
					arguments = { args.literal("replay") },
				},
				{
					description = "Set how many times a map's boss has been beaten",
					arguments = {
						args.literal("bosskills"),
						CommandTypes.mapName("map", "The map."),
						args.number("amount", "How many times beaten."),
					},
				},
			})
		end,
		callback = function(action: string, target: string?, amount: number?)
			local index = mapIndexOf(target or ALL)
			if action ~= "replay" and not index then
				Conch.log("error", `Unknown map: {target}`)
				return
			end

			local map = MapsCore.LIST[index or 1]
			if action == "unlock" then
				if
					commit(function(profile)
						unlockMaps(profile, index :: number)
					end, LobbyService.SendMapRecords)
				then
					Conch.log("normal", `Unlocked up to {map.DisplayName}: create a party to see each unlock.`)
				end
			elseif action == "lock" then
				-- The first map is open from the start; "all" locks everything after it.
				local first = if target == ALL then 2 else index :: number
				if not MapsCore.HasRequirement(MapsCore.LIST[first]) then
					Conch.log("error", `{map.DisplayName} is always open.`)
					return
				end
				if commit(function(profile)
					lockMaps(profile, first)
				end, LobbyService.SendMapRecords) then
					Conch.log("normal", `Locked {MapsCore.LIST[first].DisplayName} and every map after it.`)
				end
			elseif action == "replay" then
				if commit(function(profile)
					profile.MapsShown = nil
				end, LobbyService.SendMapRecords) then
					Conch.log("normal", "Every open map's unlock plays again: create a party.")
				end
			elseif action == "bosskills" then
				local kills = math.clamp(math.floor(amount or 0), 0, 65535)
				if
					commit(function(profile)
						local all = profile.BossKills or {}
						all[map.Name] = if kills > 0 then kills else nil
						profile.BossKills = if next(all) then all else nil
					end, LobbyService.SendMapRecords)
				then
					Conch.log("normal", `{map.DisplayName}'s boss beaten: {kills}.`)
				end
			end
		end,
	})
end

CommandsService.OnStart = function()
	registerGems()
	registerWeapons()
	registerClasses()
	registerUnlock()
	registerQuest()
	registerMaps()
end

return Ignis.Register(CommandsService)
