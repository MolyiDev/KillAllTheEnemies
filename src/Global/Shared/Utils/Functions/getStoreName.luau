-- The profile DataStore's name. The universe also holds the old Lobby and Game places, which saved their own schema:
-- a name of this game's own keeps their documents from ever being read as (or overwritten by) this game's profile.
local RunService = game:GetService("RunService")

return function()
	return if RunService:IsStudio() then "KillAllTheMonsters_Studio" else "KillAllTheMonsters_Live"
end
