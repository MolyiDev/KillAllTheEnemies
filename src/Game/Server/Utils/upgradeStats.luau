-- What each player's run upgrades add up to, by upgrade id. A leaf holding state on purpose: UpgradesService writes
-- it, and the services whose numbers an upgrade changes (EnemiesService, WeaponService, AbilityService,
-- CharacterService, RoundService) read it without requiring the service that requires them.
local upgradeStats = {}

local stats: { [Player]: { [number]: number } } = {}

-- The sum of every pick of `upgradeId`; 0 with none.
function upgradeStats.Get(player: Player, upgradeId: number): number
	local own = stats[player]
	return if own then own[upgradeId] or 0 else 0
end

function upgradeStats.Add(player: Player, upgradeId: number, amount: number)
	local own = stats[player]
	if not own then
		own = {}
		stats[player] = own
	end
	own[upgradeId] = (own[upgradeId] or 0) + amount
end

function upgradeStats.Clear(player: Player)
	stats[player] = nil
end

function upgradeStats.ClearAll()
	table.clear(stats)
end

return upgradeStats
