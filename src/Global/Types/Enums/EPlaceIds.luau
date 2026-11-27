-- Every place in the universe. One Game place plays every map (MapsCore), picked by the party's teleport data.
-- The TEST set is a copy for playtests; which set is live is decided by the place we are running in, so a test
-- lobby can never send a party into a production match.
--
-- The OLD Game place, kept only to read its code and instances with Tripwire (list_studios shows each Studio's
-- placeId); nothing here may ever teleport to it:
--   Game  104435679031452
-- The Lobby is the universe's start place, whose id cannot change, so it was published over the old lobby there.
local PROD = {
	Lobby = 105859632802526,
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
