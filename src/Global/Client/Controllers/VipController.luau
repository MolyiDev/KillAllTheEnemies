-- Who holds VIP in this server (ShopService sends it, Shop.Vips), for the marks VIP wears: a gold [VIP] before their
-- name in chat here, and the head tag's VIP block in the lobby (HeadTagController reads IsVip).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local TextChatService = game:GetService("TextChatService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local vide = require(ReplicatedStorage.Packages.vide)
local NetworkMeta = require(StarterPlayer.StarterPlayerScripts.GlobalClient.NetworkMeta)

local ServerNetworkShop = NetworkMeta.Server.Shop

-- His gold (Theme.Palette.Gold), as rich text.
local PREFIX = `<font color="#FFC13B"><b>[VIP]</b></font> `

local VipController = {}

local vips = vide.source({} :: { [number]: boolean })

-- Whether the player with `userId` holds VIP. Reads a vide source, so a view that calls it follows it.
function VipController.IsVip(userId: number): boolean
	return vips()[userId] == true
end

VipController.OnStart = function()
	-- The one OnIncomingMessage callback on this client: a second assignment would replace this one.
	TextChatService.OnIncomingMessage = function(message: TextChatMessage): TextChatMessageProperties?
		local source = message.TextSource
		if not source or not vips()[source.UserId] then return nil end

		local properties = Instance.new("TextChatMessageProperties")
		properties.PrefixText = PREFIX .. message.PrefixText
		return properties
	end
end

ServerNetworkShop.Vips.On(function(userIds: { number })
	local byId = {}
	for _, userId in userIds do
		byId[userId] = true
	end

	vips(byId)
end)

return Ignis.Register(VipController)
