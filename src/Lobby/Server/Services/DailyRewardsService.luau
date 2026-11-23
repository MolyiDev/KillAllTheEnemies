-- The daily rewards (DailyRewardsCore): where each player's streak stands, told to his screen (DailyRewards.State), and
-- claiming today's reward. A gun day gives its gun, or its Gems when the gun is owned already.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(ServerScriptService.GlobalServer.NetworkMeta)
local DatabaseService = require(ServerScriptService.GlobalServer.Services.DatabaseService)
local LoadoutService = require(script.Parent.LoadoutService)
local LoadoutCore = require(ReplicatedStorage.GlobalShared.Core.LoadoutCore)
local DailyRewardsCore = require(ReplicatedStorage.Shared.Core.DailyRewardsCore)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)
local TProfile = require(ReplicatedStorage.Types.TProfile)

local ServerNetworkDailyRewards = NetworkMeta.Server.DailyRewards
local ClientNetworkDailyRewards = NetworkMeta.Client.DailyRewards

-- A second past midnight, so a clock a hair behind the server's still reads the new day.
local ROLLOVER_MARGIN = 1

local DailyRewardsService = {}

local function send(player: Player, profile: TProfile.TProfile)
	local now = os.time()
	local day, isClaimable = DailyRewardsCore.Current(profile.Daily, DailyRewardsCore.Today(now))

	local owned = {}
	local count = 0
	for prizeDay in DailyRewardsCore.REWARDS do
		local gun = DailyRewardsCore.GunOf(prizeDay)
		if not gun or not LoadoutCore.LevelOf(profile.Loadout.Owned, gun) then continue end
		count += 1
		owned[count] = prizeDay
	end

	ServerNetworkDailyRewards.State.Fire(player, day, isClaimable, DailyRewardsCore.SecondsLeft(now), owned)
end

-- At every UTC midnight each player's next day comes up, so everybody is told.
local function rollOver()
	for _, player in Players:GetPlayers() do
		local profile = DatabaseService.Get(player)
		if profile then send(player, profile) end
	end

	task.delay(DailyRewardsCore.SecondsLeft(os.time()) + ROLLOVER_MARGIN, rollOver)
end

DailyRewardsService.OnStart = function()
	task.delay(DailyRewardsCore.SecondsLeft(os.time()) + ROLLOVER_MARGIN, rollOver)
end

DailyRewardsService.OnDataLoaded = function(player: Player)
	local profile = DatabaseService.Get(player)
	if profile then send(player, profile) end
end :: TPlayerEvents.OnDataLoaded

-- A gun bought or a claim made changes what the screen shows.
DatabaseService.OnProfileChanged:Connect(send)

-- The claim needs no character: the streak is the player's own, claimed from the menu whatever his body is doing.
-- The day is worked out again inside the write, on the profile as it is then.
ClientNetworkDailyRewards.Claim.On(function(player: Player)
	local today = DailyRewardsCore.Today(os.time())
	local claimedDay, gems, gunId = 0, 0, 0
	local hasClaimed = DatabaseService.Update(player, function(profile)
		local day, isClaimable = DailyRewardsCore.Current(profile.Daily, today)
		if not isClaimable then return false end
		local reward = DailyRewardsCore.REWARDS[day]
		local gun = DailyRewardsCore.GunOf(day)
		if gun and not LoadoutCore.LevelOf(profile.Loadout.Owned, gun) then
			profile.Loadout.Owned[gun.Name] = 1
			gunId = gun.Id
		else
			profile.Gems += reward.Gems
			gems = reward.Gems
		end
		profile.Daily = { Day = day, LastDay = today }
		claimedDay = day
		return true
	end)

	-- The write sent the new State (OnProfileChanged); a refused one sends the State as it stands, so the screen
	-- waiting on an answer is put right.
	if hasClaimed then
		DatabaseService.SaveAsync(player)
		if gunId ~= 0 then LoadoutService.Sync(player) end
	else
		local profile = DatabaseService.Get(player)
		if profile then send(player, profile) end
	end
	ServerNetworkDailyRewards.Claimed.Fire(player, claimedDay, gems, gunId)
end)

return Ignis.Register(DailyRewardsService)
