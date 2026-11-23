-- The codes' rules, the same on both sides (CodesService decides, CodesController shows): what a code may be made of
-- and the answers a redeem can get.
local CodesCore = {}

-- The longest code a player can type or the server will look up.
CodesCore.MAX_LENGTH = 20

-- Codes.Redeemed's first value.
CodesCore.Status = table.freeze({
	NotFound = 0,
	Redeemed = 1,
	AlreadyRedeemed = 2,
	Expired = 3,
	TooFast = 4,
	-- The profile was not open (still loading, or closing): nothing was used up, so it can be tried again.
	Failed = 5,
})

-- A code as it is stored and compared: capitals and digits only, so case, spaces and stray symbols typed or pasted
-- never turn a good code away.
function CodesCore.Normalize(text: string): string
	local stripped = string.gsub(text, "[^%w]", "")
	return string.sub(string.upper(stripped), 1, CodesCore.MAX_LENGTH)
end

return table.freeze(CodesCore)
