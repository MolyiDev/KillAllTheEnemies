-- The equipment a boss drops (TData.TEquipment.Drop): as one dies, every player in the match rolls each piece it drops
-- that they do not own yet, on its own chance. A piece won is theirs at once (EquipmentService.Grant saves it) and
-- shown to them where they stand (Equipment.Dropped).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(ServerScriptService.GlobalServer.NetworkMeta)
local EquipmentService = require(ServerScriptService.GlobalServer.Services.EquipmentService)
local EnemiesService = require(script.Parent.EnemiesService)
local EquipmentCore = require(ReplicatedStorage.GlobalShared.Core.EquipmentCore)
local TData = require(ReplicatedStorage.Types.TData)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local ServerNetworkEquipment = NetworkMeta.Server.Equipment

local EquipmentDropsService = {}

local random = Random.new()
-- os.clock each player's won pieces are shown until, one card after another.
local shownUntil: { [Player]: number } = {}

-- The os.clock the last piece `player` won is shown until on their screen (0 for none).
function EquipmentDropsService.ShownUntil(player: Player): number
	return shownUntil[player] or 0
end

-- Rolls each of `drops` for `player`. A piece they own already is won for nothing: there is no second copy.
local function roll(player: Player, drops: { TData.TEquipment })
	for _, item in drops do
		local drop = item.Drop
		if not drop or random:NextNumber() >= drop.Chance then continue end
		if not EquipmentService.Grant(player, item) then continue end
		ServerNetworkEquipment.Dropped.Fire(player, item.Id)
		shownUntil[player] = math.max(shownUntil[player] or 0, os.clock()) + EquipmentCore.DROP_SHOW_SECONDS
	end
end

EquipmentDropsService.OnPlayerDisconnected = function(player: Player)
	shownUntil[player] = nil
end :: TPlayerEvents.OnPlayerDisconnected

EnemiesService.OnEnemyDied:Connect(function(_, enemyData: TData.TEnemy)
	local drops = EquipmentCore.DropsOf(enemyData.Id)
	if #drops == 0 then return end
	-- Each player's on its own thread: a piece won is saved before it is told (Grant yields), and the boss bar shows
	-- the rolls only for as long as its fall holds, so one player's save must not hold back the next one's result.
	for _, player in Players:GetPlayers() do
		task.spawn(roll, player, drops)
	end
end)

return Ignis.Register(EquipmentDropsService)
