-- The HEALTH card's levels for a run: what each adds to a character's max health (healing that much too) and what
-- it costs in Gold. The server sells them (CharacterService); the client reads the same table for the card's price.
local PRICES = table.freeze({ 40, 80, 140, 220, 320 })

return table.freeze({
	-- A character's max health with no level bought.
	BASE = 100,
	GAIN = 20,
	-- By the level being bought, 1 first.
	PRICES = PRICES,
	MAX_LEVEL = #PRICES,
})
