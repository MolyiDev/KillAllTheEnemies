-- The daily spins (SpinsCore): how many each player has left, told to his screen (Spins.State), spinning one, and the
-- extra spin sold for Robux. The prize is drawn here and paid in the same write that uses the spin.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(ServerScriptService.GlobalServer.NetworkMeta)
local DatabaseService = require(ServerScriptService.GlobalServer.Services.DatabaseService)
local PurchasesService = require(ServerScriptService.GlobalServer.Services.PurchasesService)
local ShopService = require(ServerScriptService.GlobalServer.Services.ShopService)
local ShopCore = require(ReplicatedStorage.GlobalShared.Core.ShopCore)
local DailyRewardsCore = require(ReplicatedStorage.Shared.Core.DailyRewardsCore)
local SpinsCore = require(ReplicatedStorage.Shared.Core.SpinsCore)
local EProducts = require(ReplicatedStorage.Types.Enums.EProducts)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)
local TProfile = require(ReplicatedStorage.Types.TProfile)

local ServerNetworkSpins = NetworkMeta.Server.Spins
local ClientNetworkSpins = NetworkMeta.Client.Spins

-- A second past midnight, so a clock a hair behind the server's still reads the new day.
local ROLLOVER_MARGIN = 1

local SpinsService = {}

local random = Random.new()

-- The free spins a day this player gets: the passes add theirs where random prizes may be sold.
local function perDay(player: Player, profile: TProfile.TProfile): number
	return SpinsCore.FREE_PER_DAY + ShopCore.ExtraFreeSpins(profile, ShopService.IsRandomRestricted(player))
end

local function send(player: Player, profile: TProfile.TProfile)
	local now = os.time()
	local spins = profile.Spins
	local daily = perDay(player, profile)
	ServerNetworkSpins.State.Fire(
		player,
		SpinsCore.FreeLeft(spins, DailyRewardsCore.Today(now), daily),
		if spins then spins.Bought else 0,
		DailyRewardsCore.SecondsLeft(now),
		daily
	)
end

-- At every UTC midnight the free spins come back, so everybody is told.
local function rollOver()
	for _, player in Players:GetPlayers() do
		local profile = DatabaseService.Get(player)
		if profile then send(player, profile) end
	end

	task.delay(DailyRewardsCore.SecondsLeft(os.time()) + ROLLOVER_MARGIN, rollOver)
end

-- Uses up a free spin if one is left today, else a bought one. False when there is neither.
local function useSpin(profile: TProfile.TProfile, today: number, free: number): boolean
	local spins = profile.Spins or { Day = today, Used = 0, Bought = 0 }
	if spins.Day ~= today then
		spins.Day = today
		spins.Used = 0
	end

	if spins.Used < free then
		spins.Used += 1
	elseif spins.Bought > 0 then
		spins.Bought -= 1
	else
		return false
	end

	profile.Spins = spins
	return true
end

local function pay(profile: TProfile.TProfile, prize: SpinsCore.TPrize)
	if prize.Kind == "Gems" then
		profile.Gems += prize.Amount
		return
	end

	profile.Xp += prize.Amount
	while profile.Xp >= 100 do
		profile.Xp -= 100
		profile.Level += 1
	end
end

SpinsService.OnStart = function()
	task.delay(DailyRewardsCore.SecondsLeft(os.time()) + ROLLOVER_MARGIN, rollOver)

	PurchasesService.Register(EProducts.ExtraSpin, function(player: Player, profile: TProfile.TProfile)
		local spins = profile.Spins or { Day = 0, Used = 0, Bought = 0 }
		spins.Bought += 1
		profile.Spins = spins
		return true
	end)
end

SpinsService.OnDataLoaded = function(player: Player)
	local profile = DatabaseService.Get(player)
	if profile then send(player, profile) end
end :: TPlayerEvents.OnDataLoaded

-- A spin used, a purchase or a prize paid changes what the screen shows.
DatabaseService.OnProfileChanged:Connect(send)

-- Needs no character: the spins are the player's own, spun from a menu whatever his body is doing. Every Spin is
-- answered with a Landed, a refused one too, so the reel waiting on it always stops. It is fired in the same frame as
-- the profile it changed, so the client hears both together and the HUD's hold puts its numbers back before drawing.
ClientNetworkSpins.Spin.On(function(player: Player)
	local today = DailyRewardsCore.Today(os.time())
	local index = 0
	local hasSpun = DatabaseService.Update(player, function(profile)
		index = SpinsCore.Draw(random, ShopCore.Luck(profile, ShopService.IsRandomRestricted(player)))
		if not useSpin(profile, today, perDay(player, profile)) then return false end
		local prize = SpinsCore.PRIZES[index]
		pay(profile, prize)
		return true
	end)

	ServerNetworkSpins.Landed.Fire(player, if hasSpun then index else 0)
	if hasSpun then DatabaseService.SaveAsync(player) end
end)

return Ignis.Register(SpinsService)
