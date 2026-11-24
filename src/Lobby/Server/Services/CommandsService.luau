-- The lobby's console commands. Every one needs the developer permission, which GlobalCommandsService gives by group
-- rank (everybody in Studio and the test places).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Conch = require(ReplicatedStorage.Packages.conch)
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local ClassesService = require(script.Parent.ClassesService)
local LoadoutService = require(script.Parent.LoadoutService)
local RangeService = require(script.Parent.RangeService)
local DatabaseService = require(ServerScriptService.GlobalServer.Services.DatabaseService)
local EquipmentService = require(ServerScriptService.GlobalServer.Services.EquipmentService)
local AbilitiesCore = require(ReplicatedStorage.GlobalShared.Core.AbilitiesCore)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local EquipmentCore = require(ReplicatedStorage.GlobalShared.Core.EquipmentCore)
local LoadoutCore = require(ReplicatedStorage.GlobalShared.Core.LoadoutCore)
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

CommandsService.OnStart = function()
	registerGems()
	registerWeapons()
	registerClasses()
	registerUnlock()
	registerQuest()
end

return Ignis.Register(CommandsService)
