-- Spawns a player as their whole avatar, R6 as the place's avatar type says. Yields on the web.
local Players = game:GetService("Players")

return function(player: Player)
	-- Loading from the description dresses the body before it appears; a plain load shows the default body first and
	-- adds the avatar's pieces a moment later. Studio's test players have no account, so nothing to fetch.
	local fetched, description = false, nil
	if player.UserId > 0 then
		fetched, description = pcall(Players.GetHumanoidDescriptionFromUserIdAsync, Players, player.UserId)
	end
	if not player.Parent then return end

	if fetched then
		player:LoadCharacterWithHumanoidDescriptionAsync(description)
	else
		player:LoadCharacterAsync()
	end
end
