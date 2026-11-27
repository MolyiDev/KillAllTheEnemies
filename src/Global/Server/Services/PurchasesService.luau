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
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)
local TProfile = require(ReplicatedStorage.Types.TProfile)

-- Grants into the draft and returns true, or returns false when it cannot be fulfilled right now (the GDD's
-- "charge only for a revive that can be fulfilled": the receipt stays pending and Roblox retries or refunds).
-- `afterSave` runs once the grant is in the profile, for run-side effects (respawn the player, add Gold). `receiptId`
-- names the purchase, for a grant that travels on (a gift).
export type THandler = (player: Player, profile: TProfile.TProfile, receiptId: string) -> (boolean, (() -> ())?)

type TDialogWait = { Thread: thread, ProductId: number, Timeout: thread? }

local PurchasesService = {}

local Tune = table.freeze({
	-- A receipt waiting on its dialog goes on without it after this long: a close the server never hears must not
	-- lose what was paid for.
	DIALOG_WAIT_SECONDS = 10,
})

local handlers: { [number]: THandler } = {}
-- Products granted only once the buyer has closed Roblox's purchase dialog (pressed its OK), so what they do happens
-- in front of the player instead of under the dialog.
local afterDialog: { [number]: boolean } = {}
-- Each player's receipt waiting on its dialog, and a dialog closed on a purchase before its receipt came (when).
local dialogWaits: { [Player]: TDialogWait } = {}
local dialogClosed: { [Player]: { ProductId: number, At: number } } = {}

-- `isAfterDialog`: the grant waits for the purchase dialog to close, and checks it can be fulfilled only then.
function PurchasesService.Register(productId: number, handler: THandler, isAfterDialog: boolean?)
	if productId == 0 then return end
	handlers[productId] = handler
	afterDialog[productId] = isAfterDialog == true
end

-- Yields until `player` closes the dialog of their purchase of `productId`, or Tune.DIALOG_WAIT_SECONDS.
local function awaitDialog(player: Player, productId: number)
	local closed = dialogClosed[player]
	dialogClosed[player] = nil
	if closed and closed.ProductId == productId and os.clock() - closed.At < Tune.DIALOG_WAIT_SECONDS then return end

	local waiting: TDialogWait = { Thread = coroutine.running(), ProductId = productId }
	dialogWaits[player] = waiting
	waiting.Timeout = task.delay(Tune.DIALOG_WAIT_SECONDS, function()
		if dialogWaits[player] ~= waiting then return end
		dialogWaits[player] = nil
		task.spawn(waiting.Thread)
	end)
	coroutine.yield()
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local handler = handlers[receipt.ProductId]
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not handler or not player or not DatabaseService.Get(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- A buyer gone meanwhile has no document, so the Update below declines it.
	if afterDialog[receipt.ProductId] then awaitDialog(player, receipt.ProductId) end

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

-- Resumes the receipt waiting on `player`'s dialog.
local function endDialogWait(player: Player)
	local waiting = dialogWaits[player]
	dialogWaits[player] = nil
	if waiting.Timeout then task.cancel(waiting.Timeout) end
	task.spawn(waiting.Thread)
end

PurchasesService.OnStart = function()
	MarketplaceService.ProcessReceipt = processReceipt
end

PurchasesService.OnPlayerDisconnected = function(player: Player)
	dialogClosed[player] = nil
	-- A receipt still waiting goes on, to find the player gone.
	if dialogWaits[player] then endDialogWait(player) end
end :: TPlayerEvents.OnPlayerDisconnected

-- The dialog's OK. It may come before the receipt (kept for it) or after (resumes the receipt waiting on it).
MarketplaceService.PromptProductPurchaseFinished:Connect(
	function(userId: number, productId: number, isPurchased: boolean)
		if not isPurchased or not afterDialog[productId] then return end
		local player = Players:GetPlayerByUserId(userId)
		if not player then return end
		local waiting = dialogWaits[player]
		if waiting and waiting.ProductId == productId then
			endDialogWait(player)
			return
		end
		dialogClosed[player] = { ProductId = productId, At = os.clock() }
	end
)

return Ignis.Register(PurchasesService)
