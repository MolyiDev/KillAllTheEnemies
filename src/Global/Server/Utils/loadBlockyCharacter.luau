-- Loads a player's avatar on the blocky body (GlobalShared.Utils.blockyBody).
-- A player with no account behind him (Studio's test players) gets the default avatar, so he wears the same body rather
-- than whatever a plain load gives. Yields.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local blockyBody = require(ReplicatedStorage.GlobalShared.Utils.blockyBody)

return function(player: Player)
	if player.Parent ~= Players then return end
	local found, description = pcall(Players.GetHumanoidDescriptionFromUserId, Players, player.UserId)
	if not found or not description then description = Instance.new("HumanoidDescription") end
	blockyBody.Describe(description)
	player:LoadCharacterWithHumanoidDescriptionAsync(description)
end
