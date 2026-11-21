-- Every place in the universe. One Game place plays every map (MapsCore), picked by the party's teleport data.
-- The TEST set is a copy for playtests; which set is live is decided by the place we are running in, so a test
-- lobby can never send a party into a production match.
--
-- The OLD places, kept only to read their code and instances with Tripwire (list_studios shows each Studio's
-- placeId); nothing here may ever teleport to them:
--   Lobby 105859632802526
--   Game  104435679031452
local PROD = {
	Lobby = 97384805316642,
	Game = 113327793187086,
}

local TEST = {
	Lobby = 0,
	Game = 0,
}

local isTest = game.PlaceId ~= 0 and (game.PlaceId == TEST.Lobby or game.PlaceId == TEST.Game)

local exported = if isTest then table.clone(TEST) else table.clone(PROD)
exported.IsTest = isTest

return table.freeze(exported)
