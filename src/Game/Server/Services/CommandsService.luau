-- The arena's console commands. Every one needs the developer permission, which GlobalCommandsService gives by group
-- rank (everybody in Studio and the test places).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Conch = require(ReplicatedStorage.Packages.conch)
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local AbilityService = require(script.Parent.AbilityService)
local EconomyService = require(script.Parent.EconomyService)
local EnemiesService = require(script.Parent.EnemiesService)
local MatchService = require(script.Parent.MatchService)
local RoundService = require(script.Parent.RoundService)
local TimeService = require(script.Parent.TimeService)
local UpgradesService = require(script.Parent.UpgradesService)
local WeaponService = require(script.Parent.WeaponService)
local ArenaCore = require(ReplicatedStorage.Shared.Core.ArenaCore)
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
	registerGun()
	registerGold()
	registerGoldPack()
	registerUlt()
	registerUpgrade()
end

return Ignis.Register(CommandsService)
