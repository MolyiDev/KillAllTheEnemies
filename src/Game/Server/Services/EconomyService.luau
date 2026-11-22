-- The two currencies (GDD 8): Gold for the run, in memory and gone when it ends; Gems saved as they are awarded.
-- A leaf on purpose: whoever decides a reward calls Add, and nothing in here knows why it was earned.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Network = require(ServerScriptService.GlobalServer.Network)
local DatabaseService = require(ServerScriptService.GlobalServer.Services.DatabaseService)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local ServerNetworkEconomy = Network.Server.Economy

local EconomyService = {}

local gold: { [Player]: number } = {}
-- The Gems each player's play has earned this run, the 2x pass included.
local runGems: { [Player]: number } = {}

local function sendGold(player: Player)
	ServerNetworkEconomy.Gold.Fire(player, gold[player] or 0)
end

function EconomyService.GetGold(player: Player): number
	return gold[player] or 0
end

function EconomyService.AddGold(player: Player, amount: number)
	if amount <= 0 or not player.Parent then return end
	gold[player] = (gold[player] or 0) + math.floor(amount)
	sendGold(player)
end

-- Takes `amount` if he has it. The one way Gold is spent, so a cost is checked and paid in a single step.
function EconomyService.TrySpendGold(player: Player, amount: number): boolean
	local balance = gold[player] or 0
	if amount < 0 or balance < amount then return false end
	gold[player] = balance - amount
	sendGold(player)
	return true
end

-- Gems from playing (a cleared round, a boss). The 2x Gems pass doubles these and only these: packs and the starter
-- pack grant their advertised amount (GDD 19).
function EconomyService.AddGameplayGems(player: Player, amount: number)
	if amount <= 0 then return end
	local granted = 0
	local isGranted = DatabaseService.Update(player, function(profile)
		local scale = if profile.Entitlements.DoubleGems then 2 else 1
		granted = math.floor(amount * scale)
		profile.Gems += granted
		return true
	end)
	if not isGranted then return end

	runGems[player] = (runGems[player] or 0) + granted
	DatabaseService.SaveAsync(player)
end

function EconomyService.GetRunGems(player: Player): number
	return runGems[player] or 0
end

-- A new run: everyone back to zero Gold, and nothing earned yet.
function EconomyService.ResetRun()
	table.clear(runGems)
	for player in gold do
		gold[player] = 0
		sendGold(player)
	end
end

EconomyService.OnPlayerConnected = function(player: Player)
	gold[player] = 0
	sendGold(player)
end :: TPlayerEvents.OnPlayerConnected

EconomyService.OnPlayerDisconnected = function(player: Player)
	gold[player] = nil
	runGems[player] = nil
end :: TPlayerEvents.OnPlayerDisconnected

return Ignis.Register(EconomyService)
