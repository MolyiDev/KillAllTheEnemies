-- The arena's console commands. Every one needs the developer permission, which GlobalCommandsService gives by group
-- rank (everybody in Studio and the test places).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Conch = require(ReplicatedStorage.Packages.conch)
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local AbilityService = require(script.Parent.AbilityService)
local BossIntroService = require(script.Parent.BossIntroService)
local BossService = require(script.Parent.BossService)
local CharacterService = require(script.Parent.CharacterService)
local EconomyService = require(script.Parent.EconomyService)
local EnemiesService = require(script.Parent.EnemiesService)
local MatchService = require(script.Parent.MatchService)
local QuestProgressService = require(script.Parent.QuestProgressService)
local RoundService = require(script.Parent.RoundService)
local TimeService = require(script.Parent.TimeService)
local UpgradesService = require(script.Parent.UpgradesService)
local WeaponService = require(script.Parent.WeaponService)
local ArenaCore = require(ReplicatedStorage.Shared.Core.ArenaCore)
local RoundCore = require(ReplicatedStorage.Shared.Core.RoundCore)
local QuestsCore = require(ReplicatedStorage.GlobalShared.Core.QuestsCore)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local getCharacterEntityFromPlayer =
	require(ReplicatedStorage.GlobalShared.Utils.Functions.getCharacterEntityFromPlayer)
local CommandTypes = require(ReplicatedStorage.Types.CommandTypes)
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)

local args = Conch.args

local CommandsService = {}

local PERMISSION_DEV = "command.dev"
local SPAWN_SPREAD_STUDS = 12

local function getContextPlayer(): Player?
	return (Conch.get_command_context() :: any).executor.player
end

local function getEnemyId(name: string): number?
	for key, id in EEnemiesIds :: { [string]: number } do
		if string.lower(key) == name then return id end
	end

	return nil
end

local function getGunId(name: string): number?
	for key, id in EGunsIds :: { [string]: number } do
		if string.lower(key) == name then return id end
	end

	return nil
end

-- The players a command's `who` names: the caller when empty, everybody for "all", else every player whose name or
-- display name starts with it (any case).
local function getTargets(who: string?): { Player }
	local caller = getContextPlayer()
	if not who or who == "" then return if caller then { caller } else {} end
	local wanted = string.lower(who)
	if wanted == "all" then return Players:GetPlayers() end
	local found = {}
	for _, player in Players:GetPlayers() do
		local name, display = string.lower(player.Name), string.lower(player.DisplayName)
		if string.sub(name, 1, #wanted) == wanted or string.sub(display, 1, #wanted) == wanted then
			table.insert(found, player)
		end
	end

	return found
end

local function onOff(isOn: boolean): string
	return if isOn then "paused" else "resumed"
end

local function registerPause()
	Conch.register("pause", {
		permissions = { PERMISSION_DEV },
		description = "Toggle a pause: enemies (frozen in place), spawns, all (the whole match), or reset.",
		arguments = function()
			return CommandTypes.pauseTarget("target", "What to pause (enemies, spawns, all, reset).")
		end,
		callback = function(target: string)
			if target == "enemies" then
				TimeService.SetEnemiesPaused(not TimeCore.IsEnemiesManualPaused)
				Conch.log("normal", `Enemies {onOff(TimeCore.IsEnemiesManualPaused)}.`)
			elseif target == "spawns" then
				RoundService.IsSpawningPaused = not RoundService.IsSpawningPaused
				Conch.log("normal", `Spawns {onOff(RoundService.IsSpawningPaused)}.`)
			elseif target == "all" then
				TimeService.SetManualPause(not TimeCore.IsManualPaused)
				Conch.log("normal", `Match {onOff(TimeCore.IsManualPaused)}.`)
			elseif target == "reset" then
				TimeService.SetEnemiesPaused(false)
				TimeService.SetManualPause(false)
				RoundService.IsSpawningPaused = false
				Conch.log("normal", "All pauses reset.")
			end
		end,
	})
end

local function registerTimeScale()
	Conch.register("timescale", {
		permissions = { PERMISSION_DEV },
		description = "Change the match's time scale, on every side.",
		arguments = function()
			return args.overload({
				{
					description = "Set the time scale",
					arguments = { args.number("scale", "The time scale (0 to inf).") },
				},
				{
					description = "Reset the time scale to 1",
					arguments = { args.literal("reset") },
				},
			})
		end,
		callback = function(value: number | string)
			local scale = if value == "reset" then 1 else math.max(value :: number, 0)
			TimeService.SetTimeScale(scale)
			Conch.log("normal", `Time scale set to {scale}.`)
		end,
	})
end

-- A boss as a boss wave brings it: on its stage, with its intro, nothing else pouring in while it is up, and with the
-- first boss wave's health for the players in the server, so the fight tested is the fight played. Outside a round,
-- so no wave's clear waits on its kill.
local function registerBoss()
	Conch.register("boss", {
		permissions = { PERMISSION_DEV },
		description = "Bring a boss on as its wave does: its stage, its intro, its fight.",
		arguments = function()
			return CommandTypes.enemyName("name", "The boss.")
		end,
		callback = function(name: string)
			local dataId = getEnemyId(name)
			if not dataId then
				Conch.log("error", `Unknown enemy: {name}`)
				return
			end
			local healthScale = RoundCore.GetBossHealthScale(RoundCore.BOSS_EVERY, #Players:GetPlayers())
			local enemyEntity = BossIntroService.Arrive(dataId, healthScale)
			if not enemyEntity then
				Conch.log("error", "Nowhere to stage it: nobody standing, or no floor round them.")
				return
			end
			RoundService.HoldForBoss(enemyEntity)

			Conch.log("normal", `{name} is coming.`)
		end,
	})
end

-- Any of a boss's moves on demand, to see and tune each one.
local function registerBossMove()
	Conch.register("bossmove", {
		permissions = { PERMISSION_DEV },
		description = "Make the boss up take a move next. T-Rex: chomp, tailsweep, stomp, quake, charge, barrage, barrage4, dive, summon. Spider: scythecross, scytheflurry, impale, impale2, pounce, webvolley, webvolley5, brood.",
		arguments = function()
			return args.string("move", "The move: its clip's name or its kind.")
		end,
		callback = function(move: string)
			local count = BossService.ForceNext(move)
			Conch.log(
				if count > 0 then "normal" else "error",
				if count > 0 then `Next move: {move}.` else "No boss up."
			)
		end,
	})
end

local function registerEnemy()
	Conch.register("enemy", {
		permissions = { PERMISSION_DEV },
		description = "Spawn enemies around you, or clear every enemy.",
		arguments = function()
			return args.overload({
				{
					description = "Spawn enemies around you",
					arguments = {
						args.literal("spawn"),
						CommandTypes.enemyName("name", "The enemy to spawn."),
						args.optional(args.number("amount", "How many (default 1).")),
					},
				},
				{
					description = "Remove every enemy",
					arguments = { args.literal("clear") },
				},
			})
		end,
		callback = function(action: string, name: string?, amount: number?)
			if action == "clear" then
				EnemiesService.ClearAll()
				Conch.log("normal", "Cleared every enemy.")
				return
			end

			local dataId = getEnemyId(name :: string)
			if not dataId then
				Conch.log("error", `Unknown enemy: {name}`)
				return
			end
			local player = getContextPlayer()
			local characterEntity = if player then getCharacterEntityFromPlayer(player) else nil
			local rootPart = if characterEntity then World:get(characterEntity, Components.HumanoidRootPart) else nil
			if not rootPart then
				Conch.log("error", "No character to spawn around.")
				return
			end

			-- Spawned outside a round: no round counts them, so they never hold a wave open.
			local origin = rootPart.Position
			local spawned = 0
			for _ = 1, amount or 1 do
				local x = origin.X + math.random(-SPAWN_SPREAD_STUDS, SPAWN_SPREAD_STUDS)
				local z = origin.Z + math.random(-SPAWN_SPREAD_STUDS, SPAWN_SPREAD_STUDS)
				local floorY = ArenaCore.GetFloorY(x, z, origin.Y)
				if not floorY then continue end
				if EnemiesService.Spawn(dataId, vector.create(x, floorY, z)) then
					spawned += 1
				end
			end

			Conch.log("normal", `Spawned {spawned}x {name}.`)
		end,
	})
end

local function registerGun()
	Conch.register("gun", {
		permissions = { PERMISSION_DEV },
		description = "Put a gun in your hands.",
		arguments = function()
			return CommandTypes.gunName("name", "The gun to hold.")
		end,
		callback = function(name: string)
			local gunId = getGunId(name)
			local player = getContextPlayer()
			if not gunId or not player then
				Conch.log("error", `Unknown gun: {name}`)
				return
			end

			if WeaponService.Equip(player, gunId) then
				Conch.log("normal", `Holding {name}.`)
			else
				Conch.log("error", `Could not hand you {name} (no character, or no model).`)
			end
		end,
	})
end

-- `quest <daily|weekly|all>` finishes the board's quests as if played, so their notices come up in the HUD.
local function registerQuest()
	Conch.register("quest", {
		permissions = { PERMISSION_DEV },
		description = "Complete your daily or weekly quests, or both, and see their notices.",
		arguments = function()
			return CommandTypes.questBoardOrAll("board", "Daily, weekly, or all.")
		end,
		callback = function(target: string)
			local player = getContextPlayer()
			if not player then return end
			local kind: QuestsCore.TBoardKind? = nil
			for _, boardKind in QuestsCore.BOARDS do
				if string.lower(boardKind) == target then kind = boardKind end
			end

			local finished = QuestProgressService.Complete(player, kind)
			Conch.log("normal", `Completed {finished} quest(s).`)
		end,
	})
end

local function registerGold()
	Conch.register("gold", {
		permissions = { PERMISSION_DEV },
		description = "Give yourself run Gold.",
		arguments = function()
			return args.number("amount", "How much Gold to add.")
		end,
		callback = function(amount: number)
			local player = getContextPlayer()
			if not player then return end
			if amount <= 0 then
				Conch.log("error", "The amount must be above 0.")
				return
			end

			EconomyService.AddGold(player, amount)
			Conch.log("normal", `Added {math.floor(amount)} Gold ({EconomyService.GetGold(player)} now).`)
		end,
	})
end

-- The Gold packs' grant without the purchase (MatchService.GrantGold), for seeing its show.
local function registerGoldPack()
	Conch.register("goldpack", {
		permissions = { PERMISSION_DEV },
		description = "Get a Gold pack's Gold as if you had bought it, with its show.",
		arguments = function()
			return args.number("amount", "How much Gold the pack holds (1000 and 99999 are the two sold).")
		end,
		callback = function(amount: number)
			local player = getContextPlayer()
			if not player then return end
			if amount <= 0 then
				Conch.log("error", "The amount must be above 0.")
				return
			end

			MatchService.GrantGold(player, math.floor(amount))
			Conch.log("normal", `Gold pack of {math.floor(amount)} granted ({EconomyService.GetGold(player)} now).`)
		end,
	})
end

local function registerUlt()
	Conch.register("ult", {
		permissions = { PERMISSION_DEV },
		description = "Fill your ultimate's meter.",
		arguments = function() end,
		callback = function()
			local player = getContextPlayer()
			if not player then return end
			AbilityService.FillUltimate(player)
			Conch.log("normal", "Ultimate ready.")
		end,
	})
end

local function registerGod()
	Conch.register("god", {
		permissions = { PERMISSION_DEV },
		description = "Toggle god mode: nothing hurts you.",
		arguments = function() end,
		callback = function()
			local player = getContextPlayer()
			if not player then return end
			local isGod = CharacterService.ToggleGod(player)
			Conch.log("normal", if isGod then "God mode on." else "God mode off.")
		end,
	})
end

-- Down as a blow would down them: the body falls to bricks, and the run goes on (or ends, if nobody is left standing).
local function registerKill()
	Conch.register("kill", {
		permissions = { PERMISSION_DEV },
		description = "Down a player: you, a name, or all.",
		arguments = function()
			return args.optional(args.string("who", "A player's name (its start), or all. Default: you."))
		end,
		callback = function(who: string?)
			local count = 0
			for _, player in getTargets(who) do
				local characterEntity = getCharacterEntityFromPlayer(player)
				if not characterEntity then continue end
				CharacterService.Kill(characterEntity)
				count += 1
			end
			Conch.log("normal", `Downed {count} player(s).`)
		end,
	})
end

-- Down without ending the run, even alone, to see being down (spectating, the plate, REVIVE) until `revive`.
local function registerKillTest()
	Conch.register("killtest", {
		permissions = { PERMISSION_DEV },
		description = "Go down without ending the run, even alone; `revive` brings you back.",
		arguments = function() end,
		callback = function()
			local player = getContextPlayer()
			if not player then return end
			local characterEntity = getCharacterEntityFromPlayer(player)
			if not characterEntity then return end
			MatchService.HoldDown(player)
			CharacterService.Kill(characterEntity)
			Conch.log("normal", "Down (the run goes on). `revive` to come back.")
		end,
	})
end

-- Back up as a wave's end or a bought revive brings a player: rebuilt where the body fell.
local function registerRevive()
	Conch.register("revive", {
		permissions = { PERMISSION_DEV },
		description = "Revive a downed player: you, a name, or all.",
		arguments = function()
			return args.optional(args.string("who", "A player's name (its start), or all. Default: you."))
		end,
		callback = function(who: string?)
			local count = 0
			for _, player in getTargets(who) do
				if CharacterService.IsAlive(player) then continue end
				task.spawn(CharacterService.Revive, player)
				count += 1
			end
			Conch.log("normal", `Reviving {count} player(s).`)
		end,
	})
end

-- A hand of upgrade cards without clearing a wave, for seeing the pick. Only during a run.
local function registerUpgrade()
	Conch.register("upgrade", {
		permissions = { PERMISSION_DEV },
		description = "Deal yourself a hand of upgrade cards.",
		arguments = function() end,
		callback = function()
			local player = getContextPlayer()
			if not player then return end
			UpgradesService.Grant(player, 0)
			Conch.log("normal", "A hand of upgrades is owed (dealt once the one that is up is picked).")
		end,
	})
end

CommandsService.OnStart = function()
	registerPause()
	registerTimeScale()
	registerEnemy()
	registerBoss()
	registerBossMove()
	registerGun()
	registerGold()
	registerGoldPack()
	registerUlt()
	registerGod()
	registerUpgrade()
	registerQuest()
	registerKill()
	registerKillTest()
	registerRevive()
end

return Ignis.Register(CommandsService)
