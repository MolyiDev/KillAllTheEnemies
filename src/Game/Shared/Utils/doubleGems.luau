-- The results' DOUBLE YOUR GEMS: which product doubles a run's Gems, by how many there are to double. The server
-- sells it (MatchService); the client reads the same table for the price on the button.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EProducts = require(ReplicatedStorage.Types.Enums.EProducts)

export type TTier = {
	-- The fewest Gems this tier doubles.
	MinGems: number,
	ProductId: number,
	-- The product's price, as set on the product itself.
	Robux: number,
}

-- Biggest first. A run that fell before its first boss earns under 30 Gems (RoundCore's 2 a round); one boss down
-- is 48, two are past 100.
local TIERS: { TTier } = table.freeze({
	table.freeze({ MinGems = 100, ProductId = EProducts.DoubleGemsLarge, Robux = 33 }),
	table.freeze({ MinGems = 30, ProductId = EProducts.DoubleGemsMedium, Robux = 22 }),
	table.freeze({ MinGems = 1, ProductId = EProducts.DoubleGemsSmall, Robux = 11 }),
})

local doubleGems = {}

-- The tier that doubles `gems`, or nil with nothing to double or its product not created yet.
function doubleGems.GetTier(gems: number): TTier?
	for _, tier in TIERS do
		if gems < tier.MinGems then continue end
		return if tier.ProductId ~= 0 then tier else nil
	end

	return nil
end

-- What `productId` costs, or nil when it is not one of the tiers.
function doubleGems.GetRobux(productId: number): number?
	for _, tier in TIERS do
		if tier.ProductId == productId then return tier.Robux end
	end

	return nil
end

return table.freeze(doubleGems)
