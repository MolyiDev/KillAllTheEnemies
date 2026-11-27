-- The server side of MatchMutation.story.luau: fires the real Mutation events at the times below (seconds since the
-- player joined), as MutationService does in a match. Each lands on the client 3 frames after its time (the loopback's
-- latency): where its sound goes on the film (the chip's punch in the sequence's trace.json marks each drop).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local EPotionsIds = require(ReplicatedStorage.Types.Enums.Data.EPotionsIds)
local ERarities = require(ReplicatedStorage.Types.Enums.ERarities)

-- The run starts: two potions drunk. Then the fight: a stream of Basic souls that stacks, a Heavy's, and the boss's.
local TIMELINE = {
	{ At = 0.5, Drunk = { { EPotionsIds.GoldenPulse, ERarities.Rare }, { EPotionsIds.IronHide, ERarities.Epic } } },
	{ At = 6.2, Soul = EEnemiesIds.Basic },
	{ At = 6.7, Soul = EEnemiesIds.Basic },
	{ At = 7.0, Soul = EEnemiesIds.Basic },
	{ At = 7.6, Soul = EEnemiesIds.Basic },
	{ At = 7.9, Soul = EEnemiesIds.Basic },
	{ At = 8.8, Soul = EEnemiesIds.Heavy },
	{ At = 12.2, Soul = EEnemiesIds.TRex },
}

return {
	Server = function()
		local Mutation = require(ServerScriptService.GlobalServer.NetworkMeta).Server.Mutation
		local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
		local start = os.clock()

		for _, step in TIMELINE do
			local ahead = step.At - (os.clock() - start)
			if ahead > 0 then task.wait(ahead) end
			if step.Drunk then
				local recipeIds, rarities = table.create(#step.Drunk), table.create(#step.Drunk)
				for index, pair in step.Drunk do
					recipeIds[index] = pair[1]
					rarities[index] = pair[2]
				end
				Mutation.Drunk.Fire(player, recipeIds, rarities)
			else
				Mutation.EnergyDropped.Fire(player, step.Soul)
			end
			print(`[MatchMutation] fire {if step.Drunk then "Drunk" else "Soul"} {os.clock() - start}`)
		end
	end,
}
