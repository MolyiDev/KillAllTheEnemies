-- The one MarketplaceService.ProcessReceipt for the place; each place registers only the products it can grant.
--
-- A GRANT AND ITS RECEIPT ARE ONE WRITE (DatabaseService.ClaimReceipt), saved before acknowledging, and a receipt
-- already in the profile is acknowledged without granting. Roblox retries an unacknowledged receipt, so a crash
-- between grant and save only means the next server grants it, once.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local DatabaseService = require(script.Parent.DatabaseService)
local TProfile = require(ReplicatedStorage.Types.TProfile)

-- Grants into the draft and returns true, or returns false when it cannot be fulfilled right now (the GDD's
-- "charge only for a revive that can be fulfilled": the receipt stays pending and Roblox retries or refunds).
-- `afterSave` runs once the grant is in the profile, for run-side effects (respawn the player, add Gold). `receiptId`
-- names the purchase, for a grant that travels on (a gift).
export type THandler = (player: Player, profile: TProfile.TProfile, receiptId: string) -> (boolean, (() -> ())?)

local PurchasesService = {}

local handlers: { [number]: THandler } = {}

function PurchasesService.Register(productId: number, handler: THandler)
	if productId == 0 then return end
	handlers[productId] = handler
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local handler = handlers[receipt.ProductId]
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not handler or not player or not DatabaseService.Get(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local receiptId = tostring(receipt.PurchaseId)
	local isDuplicate = false
	local afterSave: (() -> ())? = nil
	local isGranted = DatabaseService.Update(player, function(profile)
		if not DatabaseService.ClaimReceipt(profile, receiptId) then
			isDuplicate = true
			return false
		end
		local ok, after = handler(player, profile, receiptId)
		afterSave = after
		return ok
	end)

	if isDuplicate then return Enum.ProductPurchaseDecision.PurchaseGranted end
	if not isGranted then return Enum.ProductPurchaseDecision.NotProcessedYet end

	-- On disk before acknowledging. If this fails the grant is still in the cache with its receipt, so the retry
	-- lands on the duplicate branch above and acknowledges without granting twice.
	if not DatabaseService.Save(player) then return Enum.ProductPurchaseDecision.NotProcessedYet end
	if afterSave then task.spawn(afterSave) end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

PurchasesService.OnStart = function()
	MarketplaceService.ProcessReceipt = processReceipt
end

return Ignis.Register(PurchasesService)
