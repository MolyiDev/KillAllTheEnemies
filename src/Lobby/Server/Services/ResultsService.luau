-- The last run, back in the lobby (UIMatt.md, Lobby Entering): the Game place leaves it in the profile
-- (TProfile.LastMatch) as the run ends or as the player walks out of it, and it is shown on every load until they
-- press LOBBY, so a player who left the game before seeing it sees it the next time they come in.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Conch = require(ReplicatedStorage.Packages.conch)
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(ServerScriptService.GlobalServer.NetworkMeta)
local DatabaseService = require(ServerScriptService.GlobalServer.Services.DatabaseService)
local MapsCore = require(ReplicatedStorage.GlobalShared.Core.MapsCore)
local EClassesIds = require(ReplicatedStorage.Types.Enums.Data.EClassesIds)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)
local TProfile = require(ReplicatedStorage.Types.TProfile)

local ServerNetworkResults = NetworkMeta.Server.Results
local ClientNetworkResults = NetworkMeta.Client.Results

local PERMISSION_DEV = "command.dev"
-- The made-up squad mates of the `results` command: real accounts, so their avatars load.
local SAMPLE_SQUAD = table.freeze({
	{ UserId = 1, Name = "Roblox" },
	{ UserId = 156, Name = "builderman" },
	{ UserId = 261, Name = "Shedletsky" },
})
-- The Game place's figures (RoundCore), which the lobby does not load: Xp a cleared wave pays, and every how many
-- waves a boss comes.
local SAMPLE_XP_PER_WAVE = 4
local SAMPLE_BOSS_EVERY = 15

local ResultsService = {}

local function show(player: Player)
	local profile = DatabaseService.Get(player)
	local record = if profile then profile.LastMatch else nil
	if record then ServerNetworkResults.Show.Fire(player, record) end
end

-- A run that never happened, written as the Game place would write it: a squad of `size` with `player` in it.
local function sample(player: Player, profile: TProfile.TProfile, size: number): TProfile.TMatchRecord
	local random = Random.new()
	local squad: { TProfile.TMatchMember } = {
		{
			UserId = player.UserId,
			Name = player.Name,
			ClassId = EClassesIds.Human,
			Kills = random:NextInteger(150, 1200),
		},
	}
	local squadKills = squad[1].Kills
	for index = 1, math.min(size, #SAMPLE_SQUAD + 1) - 1 do
		local mate = SAMPLE_SQUAD[index]
		local kills = random:NextInteger(150, 1200)
		squad[#squad + 1] = { UserId = mate.UserId, Name = mate.Name, ClassId = EClassesIds.Human, Kills = kills }
		squadKills += kills
	end

	local wave = random:NextInteger(12, 40)
	local seconds = wave * random:NextInteger(30, 45)
	local waves = 0
	local bosses = 0
	for round = 1, wave - 1 do
		if round % SAMPLE_BOSS_EVERY == 0 then
			bosses += SAMPLE_XP_PER_WAVE
		else
			waves += SAMPLE_XP_PER_WAVE
		end
	end

	return {
		MapName = MapsCore.LIST[1].Name,
		Wave = wave,
		BestWaveBefore = wave - random:NextInteger(-3, 2),
		Seconds = seconds,
		BestSecondsBefore = seconds - random:NextInteger(-120, 60),
		Gems = random:NextInteger(40, 400),
		Kills = squad[1].Kills,
		SquadKills = squadKills,
		LevelBefore = profile.Level,
		XpBefore = profile.Xp,
		XpWaves = waves,
		XpBosses = bosses,
		Squad = squad,
	}
end

local function registerResults()
	Conch.register("results", {
		permissions = { PERMISSION_DEV },
		description = "Show the lobby's results of a made-up run, with a squad of this many (1 to 4).",
		arguments = function()
			return Conch.args.number("size", "How many in the squad, you included.")
		end,
		callback = function(size: number)
			local player = (Conch.get_command_context() :: any).executor.player :: Player?
			local profile = if player then DatabaseService.Get(player) else nil
			if not player or not profile then return end
			local record = sample(player, profile, math.clamp(math.floor(size), 1, 4))
			ServerNetworkResults.Show.Fire(player, record)
			Conch.log("normal", `Results of wave {record.Wave} shown.`)
		end,
	})
end

ResultsService.OnStart = function()
	registerResults()
end

ResultsService.OnDataLoaded = function(player: Player)
	show(player)
end :: TPlayerEvents.OnDataLoaded

-- Nothing to check but that there is a run to drop: it is the player's own, and seeing it is all LOBBY does.
ClientNetworkResults.Dismiss.On(function(player: Player)
	local profile = DatabaseService.Get(player)
	if not profile or not profile.LastMatch then return end
	DatabaseService.Update(player, function(changed)
		changed.LastMatch = nil
		return true
	end)
end)

return Ignis.Register(ResultsService)
