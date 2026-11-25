--!nonstrict
-- The gift list over the shop (the reference's GIFT PLAYER): his dark panel with the offer it gives in its header, and
-- every other player in this server as a row (their head, their name, SELECT). It grows in from 0.6 while it fades, and
-- the shop's EXIT (over its dim) or a click on the dim shuts it. While it leaves it takes no presses, so the shop under
-- it answers at once.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Scrollbar = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Scrollbar)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local ShopCore = require(ReplicatedStorage.GlobalShared.Core.ShopCore)
local Parts = require(script.Parent.Parts)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Label = Parts.Label

local Layout = table.freeze({
	PANEL = Vector2.new(620, 640),
	HEADER = 96,
	ROW = Vector2.new(560, 88),
	ROW_GAP = 14,
	LIST_PADDING = 8,
	HEAD = 68,
	SELECT = Vector2.new(150, 54),
})

local Timing = table.freeze({
	IN = 0.3,
	OUT = 0.18,
	FROM = 0.6,
	DIM = 0.35,
	ROW_DELAY = 0.08,
	ROW_STAGGER = 0.04,
})

local Gift = {}

-- How far in it is: 0 gone, 1 up.
local function shownOf(state: Types.TShopState): () -> number
	return derive(function(): number
		local t = state.Now() - state.GiftToggledAt()
		if state.GiftOffer() then return Motion.Decelerate(math.clamp(t / Timing.IN, 0, 1)) end
		return 1 - Motion.Accelerate(math.clamp(t / Timing.OUT, 0, 1))
	end)
end

-- One player's row: their head (Roblox's own thumbnail, no request to wait on), their display and user names, SELECT.
local function row(
	state: Types.TShopState,
	actions: Types.TShopActions,
	player: Types.TGiftPlayer,
	order: number
): Frame
	local hand = Hand.React("Operate")
	local dealt = derive(function(): number
		if not state.GiftOffer() then return 1 end
		local t = state.Now() - state.GiftToggledAt() - Timing.ROW_DELAY - Timing.ROW_STAGGER * math.min(order - 1, 6)
		return Motion.Decelerate(math.clamp(t / Timing.IN, 0, 1))
	end)

	-- The list places the slot; the row grows into it from its middle as it deals in.
	local panel = Components.Panel({ Stroke = Color3.fromRGB(70, 60, 100) }, {
		Name = "Row",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		create("UIScale")({
			Scale = function()
				return 0.94 + 0.06 * dealt()
			end,
		}),
		create("Frame")({
			Name = "Head",
			Position = UDim2.fromOffset(10, (Layout.ROW.Y - Layout.HEAD) / 2),
			Size = UDim2.fromOffset(Layout.HEAD, Layout.HEAD),
			BackgroundColor3 = Palette.Ink,
			BorderSizePixel = 0,
			ZIndex = 3,
			create("UIStroke")({ Color = Parts.RULE, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
			create("ImageLabel")({
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Image = `rbxthumb://type=AvatarHeadShot&id={player.UserId}&w=150&h=150`,
				ZIndex = 4,
			}),
		}),
		Label({
			Name = "DisplayName",
			Position = UDim2.fromOffset(Layout.HEAD + 26, 18),
			Size = UDim2.fromOffset(300, 28),
			TextSize = 28,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = player.DisplayName,
		}),
		Label({
			Name = "UserName",
			Position = UDim2.fromOffset(Layout.HEAD + 26, 52),
			Size = UDim2.fromOffset(300, 16),
			FontFace = Font.DisplayBold,
			TextSize = 16,
			TextColor3 = Palette.Lavender,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = `@{player.Name}`,
		}),
		Components.Button({
			Name = "Select",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -18 - Layout.SELECT.X / 2, 0.5, 0),
			Size = UDim2.fromOffset(Layout.SELECT.X, Layout.SELECT.Y),
			BackgroundTransparency = 1,
			ZIndex = 5,
			Activated = function()
				hand.Commit()
				actions.SendGift(player.UserId)
			end,
			hand.Events,
			create("UIScale")({ Scale = hand.Scale }),
			Components.Slab({ Kind = "Go", Marks = true, Brackets = hand.Rise }, {
				Name = "Slab",
				Size = UDim2.fromScale(1, 1),
				Hand.WashLayer(hand, 3, 3),
				Components.Sheen(hand.Glint, 3),
				Components.Tracked("SELECT", 24, 1, Font.Display, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
				}),
			}),
		}),
	})

	return create("Frame")({
		Name = player.Name,
		LayoutOrder = order,
		Size = UDim2.fromOffset(Layout.ROW.X, Layout.ROW.Y),
		BackgroundTransparency = 1,
		panel,
	})
end

function Gift.Build(state: Types.TShopState, actions: Types.TShopActions): { Instance }
	local shown = shownOf(state)
	local isUp = derive(function(): boolean
		return shown() > 0
	end)
	-- The offer last gifted: shut, GiftOffer is nil at once, and the title keeps its name while the list fades out (a
	-- derive is handed its last value).
	local shownOffer = derive(function(last: string?): string
		return state.GiftOffer() or last or ""
	end)
	local offerTitle = function(): string
		local offer = ShopCore.ByName[shownOffer()]
		if not offer then return "" end
		if offer.Section == "Gems" then return offer.Title end
		if offer.Rarity then return string.upper(ShopCore.FeaturedGun(os.time())) end
		return if offer.Subtitle then `{offer.Title} {offer.Subtitle}` else offer.Title
	end

	-- Its canvas is sized from the rows rather than automatically: the scrollbar reads it in the canvas's own px.
	local list = create("ScrollingFrame")({
		Name = "List",
		Position = UDim2.fromOffset(0, Layout.HEADER + 12),
		Size = UDim2.fromOffset(Layout.PANEL.X, Layout.PANEL.Y - Layout.HEADER - 24),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = function()
			local count = #state.GiftPlayers()
			local rows = count * Layout.ROW.Y + math.max(count - 1, 0) * Layout.ROW_GAP
			return UDim2.fromOffset(0, rows + 2 * Layout.LIST_PADDING)
		end,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 0,
		ZIndex = 3,
		create("UIPadding")({
			PaddingTop = UDim.new(0, Layout.LIST_PADDING),
			PaddingBottom = UDim.new(0, Layout.LIST_PADDING),
		}),
		create("UIListLayout")({
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, Layout.ROW_GAP),
		}),
		vide.values(state.GiftPlayers, function(player: Types.TGiftPlayer, index: () -> number)
			return row(state, actions, player, vide.untrack(index))
		end),
	}) :: ScrollingFrame

	return {
		create("TextButton")({
			Name = "GiftDim",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(4, 4),
			BackgroundColor3 = Color3.new(),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 20,
			Visible = isUp,
			-- Leaving it is only a picture: it stops taking presses the moment it starts to go.
			Interactable = function()
				return state.GiftOffer() ~= nil
			end,
			BackgroundTransparency = function()
				return 1 - Timing.DIM * shown()
			end,
			Activated = actions.CloseGift,
		}),
		-- A CanvasGroup only while it fades (Components.FadeGroup): at rest a hover on a row would redraw it whole.
		create("Frame")({
			Name = "GiftPanel",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(960, 540),
			Size = UDim2.fromOffset(Layout.PANEL.X + 80, Layout.PANEL.Y + 80),
			BackgroundTransparency = 1,
			ZIndex = 21,
			Visible = isUp,
			Interactable = function()
				return state.GiftOffer() ~= nil
			end,
			create("UIScale")({
				Scale = function()
					return Timing.FROM + (1 - Timing.FROM) * shown()
				end,
			}),
			Components.FadeGroup("Content", shown, { Size = UDim2.fromScale(1, 1), ZIndex = 21 }, {
				Components.Panel({ Brackets = true, Tall = true }, {
					Name = "Panel",
					Position = UDim2.fromOffset(40, 40),
					Size = UDim2.fromOffset(Layout.PANEL.X, Layout.PANEL.Y),
					Components.Picture(EIcons.GiftBox, {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromOffset(44, 46),
						Size = Components.PictureBox(36),
						ZIndex = 4,
					}),
					Label({
						Position = UDim2.fromOffset(74, 24),
						Size = UDim2.fromOffset(420, 32),
						TextSize = 32,
						Text = "GIFT A PLAYER",
					}),
					Label({
						Position = UDim2.fromOffset(76, 62),
						Size = UDim2.fromOffset(440, 17),
						FontFace = Font.DisplayBold,
						TextSize = 17,
						TextColor3 = Palette.Gold,
						TextTruncate = Enum.TextTruncate.AtEnd,
						Text = function()
							return `GIVES {offerTitle()}`
						end,
					}),
					create("Frame")({
						Name = "Rule",
						Position = UDim2.fromOffset(24, Layout.HEADER),
						Size = UDim2.new(1, -48, 0, 1),
						BackgroundColor3 = Parts.RULE,
						BorderSizePixel = 0,
						ZIndex = 3,
					}),
					list,
					Scrollbar.Build(list, { Length = Layout.PANEL.Y - Layout.HEADER - 40 }, {
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromOffset(Layout.PANEL.X - 15, Layout.HEADER + 20),
						ZIndex = 4,
					}),
					Label({
						Name = "Empty",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.55),
						Size = UDim2.fromOffset(500, 60),
						FontFace = Font.DisplayBold,
						TextSize = 20,
						TextWrapped = true,
						TextXAlignment = Enum.TextXAlignment.Center,
						TextColor3 = Palette.Lavender,
						Visible = function()
							return #state.GiftPlayers() == 0
						end,
						Text = "Nobody else is in this server yet. Invite a friend to give them a gift!",
					}),
				}),
			}),
		}),
	}
end

-- Seconds the list takes to leave: the controller keeps the clock ticking this long.
Gift.LEAVE_SECONDS = Timing.OUT

return Gift
