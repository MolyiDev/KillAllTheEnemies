--!nonstrict
-- What the shop's pieces share: the clock every entrance reads, his section headers, tags and "+ ITEM" chips, the Robux
-- price slab and the gift button beside it, and a card's cheer when what it sells becomes the player's.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local ShopCore = require(ReplicatedStorage.GlobalShared.Core.ShopCore)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress

local Parts = {}

-- A screen's open and shut (UI.md 5o): pieces decelerate in, staged by what the screen is for, and accelerate out
-- faster; every fade runs on its own clock.
Parts.Timing = table.freeze({
	FADE = 0.3,
	SLIDE = 0.42,
	CLOSE = 0.22,
	-- Every gesture of an open is over by now; past it the clock's ticks redraw none of them.
	SETTLED = 1.8,
	-- A card's cheer as its offer becomes the player's: the white over its face, its one ring, its punch.
	CHEER_FLASH = 0.32,
	CHEER_RING = 0.55,
	CHEER_PUNCH = 0.4,
	-- A refused press shakes this long.
	SHAKE = 0.4,
	-- The price's word turning into OWNED, after the flash has peaked.
	OWNED_DELAY = 0.12,
	OWNED_IN = 0.3,
})
-- Every gesture keyed off a stamp is over by then.
Parts.STAMP_SECONDS = 1.2

-- The featured offers the hero card turns through ("Featured" is the featured gun's product of the moment), and how long
-- each is on show before it turns on by itself (paused while the hand is on the card).
Parts.HERO = table.freeze({ "Featured", "SurvivorBundle" })
Parts.PAGE_SECONDS = 7

-- His thin rules, and the dark gold edge round a chip.
Parts.RULE = Color3.fromRGB(72, 56, 112)
Parts.RARITIES = Theme.Rarities

-- Each section: its tab's word and glyph, its header's accent.
Parts.SECTIONS = table.freeze({
	table.freeze({ Key = "Featured", Word = "FEATURED", Glyph = EIcons.Star, Accent = Palette.Pink }),
	table.freeze({ Key = "Bundles", Word = "BUNDLES", Glyph = EIcons.GiftBox, Accent = Palette.Gold }),
	table.freeze({ Key = "Gems", Word = "GEMS", Glyph = EIcons.Gem, Accent = Palette.Violet }),
	table.freeze({ Key = "Passes", Word = "GAMEPASSES", Glyph = EIcons.Ticket, Accent = Palette.Green }),
} :: { { Key: ShopCore.TSection, Word: string, Glyph: string, Accent: Color3 } })

-- Each offer's accent, its picture and the Showcase look it stands in, by offer Name. A picture is the offer's own:
-- none is drawn for two offers.
Parts.LOOKS = table.freeze({
	SurvivorBundle = { Accent = Palette.Gold, Picture = EIcons.SurvivorVest, Art = "Spotlight" },
	StarterPack = { Accent = Palette.Green, Picture = EIcons.StarterCrate, Art = "Rays" },
	ArsenalBundle = { Accent = Palette.Violet, Picture = EIcons.ArsenalCase, Art = "Dots" },
	GemsSmall = { Accent = Palette.Steel, Picture = EIcons.GemTrio, Art = "Dots" },
	GemsMedium = { Accent = Palette.Green, Picture = EIcons.GemPouch, Art = "Dots" },
	GemsLarge = { Accent = Palette.Violet, Picture = EIcons.GemHeap, Art = "Rays" },
	GemsHuge = { Accent = Palette.Gold, Picture = EIcons.GemChest, Art = "Rays" },
	GemsMega = { Accent = Palette.Pink, Picture = EIcons.GemVault, Art = "Rays" },
	Vip = { Accent = Palette.Gold, Picture = EIcons.Crown, Art = "Rays" },
	DoubleGems = { Accent = Palette.Pink, Picture = EIcons.GemDouble, Art = "Dots" },
	DoubleXp = { Accent = Palette.Violet, Picture = EIcons.XpWings, Art = "Dots" },
	ExtraSpin = { Accent = Palette.Green, Picture = EIcons.SpinPlus, Art = "Orbit" },
	Luck = { Accent = Palette.Green, Picture = EIcons.Clover, Art = "Dots" },
	PotionSlot = { Accent = Palette.Pink, Picture = EIcons.PotionRack, Art = "Orbit" },
	ExtraBrew = { Accent = Palette.Violet, Picture = EIcons.Cauldron, Art = "Orbit" },
})

function Parts.Label(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		ZIndex = 4,
		props,
	})
end

function Parts.Darker(color: Color3, share: number): Color3
	return Color3.new(color.R * share, color.G * share, color.B * share)
end

-- Seconds since the screen opened or shut, held once every gesture is over, so the clock ticking for a later
-- gesture works none of the open out again.
function Parts.Elapsed(state: Types.TShopState): () -> number
	return derive(function(): number
		return math.min(state.Now() - state.ToggledAt(), Parts.Timing.SETTLED)
	end)
end

-- How far from its place a piece is, as a share of its travel: decelerating in after `delay`, accelerating out.
function Parts.Away(state: Types.TShopState, elapsed: () -> number, delay: number): () -> number
	return derive(function(): number
		if state.IsOpen() then return 1 - Motion.Decelerate(Progress(elapsed(), delay, Parts.Timing.SLIDE)) end
		return Motion.Accelerate(Progress(elapsed(), 0, Parts.Timing.CLOSE))
	end)
end

-- How transparent a piece is: its fade in after `delay` (away at once, gentle onto the mark), an even fade out.
function Parts.Faded(state: Types.TShopState, elapsed: () -> number, delay: number): () -> number
	return derive(function(): number
		if state.IsOpen() then return 1 - Motion.Out(Progress(elapsed(), delay, Parts.Timing.FADE)) end
		return Progress(elapsed(), 0, Parts.Timing.CLOSE)
	end)
end

-- Seconds since `stamps[name]` (the latest of several names), held at STAMP_SECONDS once over (and for a name never
-- stamped), so a tick of the clock for something else works nothing out here.
function Parts.Since(
	state: Types.TShopState,
	stamps: () -> { [string]: number },
	name: string | { string }
): () -> number
	local names = if type(name) == "table" then name else { name }
	return derive(function(): number
		local stamped = stamps()
		local at = -math.huge
		for _, each in names do
			at = math.max(at, stamped[each] or -math.huge)
		end
		if at == -math.huge then return Parts.STAMP_SECONDS end
		return math.clamp(state.Now() - at, 0, Parts.STAMP_SECONDS)
	end)
end

-- Whether `offer` is the player's for good: a pass held, or the featured gun owned.
function Parts.IsOwned(state: Types.TShopState, offer: ShopCore.TOffer): boolean
	if offer.GamePassId ~= 0 then return state.Owned()[offer.Name] == true end
	if offer.Rarity then return state.HasFeatured() end
	return false
end

-- "2D 14H", "5H 12M", "4M 09S": the two biggest units left.
function Parts.Countdown(seconds: number): string
	seconds = math.max(math.floor(seconds), 0)
	local days, hours = seconds // 86400, seconds // 3600 % 24
	local minutes, secs = seconds // 60 % 60, seconds % 60
	if days > 0 then return `{days}D {hours}H` end
	if hours > 0 then return `{hours}H {string.format("%02d", minutes)}M` end
	return `{minutes}M {string.format("%02d", secs)}S`
end

-- A section's header, his FEATURED / GEMS rows: its glyph, its word, `info` on the right in gold, and his rule under.
function Parts.Header(section, width: number, info: (() -> string)?, props: { [any]: any }): Frame
	return create("Frame")({
		Name = `{section.Key}Header`,
		Size = UDim2.fromOffset(width, 48),
		BackgroundTransparency = 1,
		Components.Picture(section.Glyph, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(14, 19),
			Size = Components.PictureBox(24),
			ZIndex = 4,
		}),
		Parts.Label({
			Position = UDim2.fromOffset(36, 4),
			Size = UDim2.fromOffset(500, 30),
			TextSize = 30,
			Text = section.Word,
		}),
		if info
			then Parts.Label({
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 10),
				Size = UDim2.fromOffset(500, 18),
				FontFace = Font.DisplayBold,
				TextSize = 18,
				TextColor3 = Palette.Gold,
				TextXAlignment = Enum.TextXAlignment.Right,
				Text = info,
			})
			else nil,
		create("Frame")({
			Name = "Rule",
			Position = UDim2.fromOffset(0, 44),
			Size = UDim2.new(1, 0, 0, 1),
			BorderSizePixel = 0,
			BackgroundColor3 = Parts.RULE,
			create("UIGradient")({
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(0.7, 0.2),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		}),
		props,
	})
end

-- His flat tag (NEW WEAPON, LEGENDARY): a block of `color` lettered in ink or white; `isOutlined` is his dark one with
-- a coloured edge and coloured words (MELEE WEAPON, 3 ITEMS). Sized to its word; `height` is his 30 where nil, its
-- words half of it.
function Parts.Tag(
	text: string,
	color: Color3,
	isInk: boolean,
	isOutlined: boolean?,
	props: { [any]: any }?,
	height: number?
): Frame
	local tall = height or 30
	return create("Frame")({
		Name = "Tag",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, tall),
		BackgroundColor3 = if isOutlined then Palette.Ink else color,
		BackgroundTransparency = if isOutlined then 0.2 else 0,
		BorderSizePixel = 0,
		ZIndex = 4,
		if isOutlined
			then create("UIStroke")({
				Color = Parts.Darker(color, 0.7),
				Thickness = 1.5,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			})
			else nil,
		create("UIPadding")({
			PaddingLeft = UDim.new(0, math.round(tall * 0.47)),
			PaddingRight = UDim.new(0, math.round(tall * 0.47)),
		}),
		Parts.Label({
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			TextSize = math.round(tall / 2),
			TextYAlignment = Enum.TextYAlignment.Center,
			TextColor3 = if isOutlined then color elseif isInk then Palette.Ink else Palette.White,
			Text = text,
			ZIndex = 5,
		}),
		props or {},
	})
end

-- His "+ 250,000 GEMS" chip: a faint block of the accent with its edge and its words in the accent. `pop` (0 to 1 and
-- back) punches it as the offer is granted. `height` as a Tag's.
function Parts.Chip(text: string, color: Color3, pop: () -> number, props: { [any]: any }?, height: number?): Frame
	local tall = height or 30
	return create("Frame")({
		Name = "Chip",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, tall),
		BackgroundColor3 = color,
		BackgroundTransparency = function()
			return 0.88 - 0.5 * pop()
		end,
		BorderSizePixel = 0,
		ZIndex = 4,
		create("UIStroke")({
			Color = Parts.Darker(color, 0.75),
			Thickness = 1.5,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		create("UIPadding")({
			PaddingLeft = UDim.new(0, math.round(tall * 0.47)),
			PaddingRight = UDim.new(0, math.round(tall * 0.47)),
		}),
		create("UIScale")({
			Scale = function()
				return 1 + 0.12 * pop()
			end,
		}),
		Parts.Label({
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			TextSize = math.round(tall / 2),
			TextYAlignment = Enum.TextYAlignment.Center,
			TextColor3 = function()
				return color:Lerp(Palette.White, pop())
			end,
			Text = text,
			ZIndex = 5,
		}),
		props or {},
	})
end

-- What an offer gives as his two tags joined: "+ SANDAN GUN" on a block of `color` (in ink on a bright one), then what
-- it is ("LEGENDARY") in the colour on his dark outlined tag. `pop` (0 to 1 and back) punches it and whitens the block.
-- `height` as a Tag's.
function Parts.Pair(
	text: string,
	kind: string,
	color: Color3,
	isInk: boolean,
	pop: () -> number,
	props: { [any]: any }?,
	height: number?
): Frame
	local tall = height or 30
	local pad = UDim.new(0, math.round(tall * 0.42))
	local textSize = math.round(tall / 2)
	-- Each block is its word, padded: a frame sized from a scaled child never settles (UI.md, the Mutation Lab).
	local function block(order: number, words: string, background: any, textColor: any, isOutlined: boolean): TextLabel
		return Parts.Label({
			Name = if isOutlined then "Kind" else "Item",
			LayoutOrder = order,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, tall),
			BackgroundColor3 = background,
			BackgroundTransparency = if isOutlined then 0.15 else 0,
			BorderSizePixel = 0,
			TextSize = textSize,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextColor3 = textColor,
			Text = words,
			ZIndex = 5,
			create("UIPadding")({ PaddingLeft = pad, PaddingRight = pad }),
			if isOutlined
				then create("UIStroke")({
					Color = Parts.Darker(color, 0.7),
					Thickness = 1.5,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				})
				else nil,
		})
	end

	return create("Frame")({
		Name = "Pair",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, tall),
		BackgroundTransparency = 1,
		ZIndex = 4,
		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		create("UIScale")({
			Scale = function()
				return 1 + 0.1 * pop()
			end,
		}),
		block(1, text, function()
			return color:Lerp(Palette.White, 0.6 * pop())
		end, if isInk then Palette.Ink else Palette.White, false),
		block(2, kind, Palette.Ink, color, true),
		props or {},
	})
end

-- A price struck through: what the offer would cost in the smallest Gem pack. The Robux glyph and the amount in
-- lavender, and a pink line drawn across them from the left as `strike` goes 0 to 1.
function Parts.Was(robux: number, size: number, strike: () -> number, props: { [any]: any }): Frame
	return create("Frame")({
		Name = "Was",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, size),
		BackgroundTransparency = 1,
		ZIndex = 5,
		create("Frame")({
			Name = "Amount",
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, size),
			BackgroundTransparency = 1,
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, math.round(size * 0.25)),
			}),
			Components.Icon("Robux", {
				LayoutOrder = 1,
				Size = Components.GlyphBox(math.round(size * 0.9)),
				ImageColor3 = Palette.Lavender,
				ZIndex = 5,
			}),
			Parts.Label({
				LayoutOrder = 2,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, size),
				TextSize = size,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextColor3 = Palette.Lavender,
				Text = Components.Commas(robux),
				ZIndex = 5,
			}),
		}),
		create("Frame")({
			Name = "Strike",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, -4, 0.5, 0),
			Size = function()
				local t = strike()
				return UDim2.new(t, 8 * t, 0, 3)
			end,
			BackgroundColor3 = Palette.Pink,
			BorderSizePixel = 0,
			ZIndex = 6,
		}),
		props,
	})
end

-- A card's cheer, 0 to 1 as each part of it runs off the offer's granted stamp (the latest of several offers'): Flash
-- (white over the face, squared and short), Ring (one outline growing out), Punch (a lift and back with no wobble).
function Parts.Cheer(state: Types.TShopState, name: string | { string })
	local since = Parts.Since(state, state.GrantedAt, name)
	local timing = Parts.Timing
	return {
		Since = since,
		Flash = derive(function(): number
			local left = 1 - since() / timing.CHEER_FLASH
			return if left > 0 then left * left else 0
		end),
		Ring = derive(function(): number
			return math.clamp(since() / timing.CHEER_RING, 0, 1)
		end),
		Punch = derive(function(): number
			return Motion.Bump(since() / timing.CHEER_PUNCH)
		end),
		-- A refusal's shake, -1 to 1. Only a price shakes, and a price is one offer's.
		Shake = derive(function(): number
			local at = if type(name) == "string" then state.RefusedAt()[name] else nil
			if not at then return 0 end
			return Motion.Shake(math.clamp((state.Now() - at) / timing.SHAKE, 0, 1), at)
		end),
	}
end

-- The white flash and the one ring of a cheer over a frame of `corner` px: children of the card.
function Parts.CheerLayers(cheer, corner: number, zIndex: number): { Instance }
	return {
		create("Frame")({
			Name = "Flash",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Palette.White,
			BorderSizePixel = 0,
			ZIndex = zIndex,
			Visible = function()
				return cheer.Flash() > 0
			end,
			BackgroundTransparency = function()
				return 1 - 0.55 * cheer.Flash()
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, corner) }),
		}),
		create("Frame")({
			Name = "CheerRing",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = function()
				local grow = math.round(36 * Motion.Out(cheer.Ring()))
				return UDim2.new(1, 2 * grow, 1, 2 * grow)
			end,
			BackgroundTransparency = 1,
			ZIndex = zIndex,
			Visible = function()
				local t = cheer.Ring()
				return t > 0 and t < 1
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, corner + 4) }),
			create("UIStroke")({
				Color = Palette.White,
				Thickness = 2,
				Transparency = function()
					return cheer.Ring()
				end,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		}),
	}
end

-- Robux and an amount, as his R$ prices: Roblox's own glyph (the one flat glyph left) beside the number.
local function robuxWord(robux: number, size: number, transparency: () -> number): Frame
	return create("Frame")({
		Name = "Robux",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, size),
		BackgroundTransparency = 1,
		ZIndex = 4,
		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, math.round(size * 0.3)),
		}),
		Components.Icon("Robux", {
			LayoutOrder = 1,
			Size = Components.GlyphBox(math.round(size * 0.95)),
			ImageTransparency = transparency,
			ZIndex = 5,
		}),
		Parts.Label({
			LayoutOrder = 2,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, size),
			TextSize = size,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextTransparency = transparency,
			Text = Components.Commas(robux),
			ZIndex = 5,
		}),
	})
end

-- His green price slab: Robux and the amount, OWNED in grey once the offer is the player's. It grows under the hand as
-- a thing you take (the offer is), goes in while Roblox's prompt is up, shakes when the buy is refused, and the cheer turns its
-- word. `size` is his drawn rect; `textSize` the amount's.
function Parts.Price(
	state: Types.TShopState,
	actions: Types.TShopActions,
	offer: ShopCore.TOffer,
	size: Vector2,
	textSize: number,
	props: { [any]: any },
	call: (() -> number)?
): TextButton
	local isOwned = derive(function(): boolean
		return Parts.IsOwned(state, offer)
	end)
	local hand = Hand.React("Take", function(): boolean
		return not isOwned()
	end)
	local cheer = Parts.Cheer(state, offer.Name)
	local pressed = Parts.Since(state, state.PressedAt, offer.Name)
	local isWaiting = derive(function(): boolean
		return state.PressedAt()[offer.Name] ~= nil
	end)
	-- 0 showing the price, 1 showing OWNED; the turn waits for the flash to peak.
	local owned = derive(function(): number
		if not isOwned() then return 0 end
		local since = cheer.Since()
		if since >= Parts.STAMP_SECONDS then return 1 end
		return Motion.Out(Progress(since, Parts.Timing.OWNED_DELAY, Parts.Timing.OWNED_IN))
	end)

	return Components.Button({
		Name = "Price",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Activated = function()
			if isOwned() then return end
			hand.Commit()
			actions.Buy(offer.Name)
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				-- In while the prompt is up, a little more the first instant it went.
				local wait = if isWaiting() then 0.04 + 0.03 * Motion.Bump(math.min(pressed() / 0.2, 1)) else 0
				return hand.Scale() * (1 - wait) * (1 + 0.1 * cheer.Punch())
			end,
		}),
		Components.Slab({
			Kind = function()
				return if owned() > 0.5 then "Off" else "Go"
			end,
			Marks = true,
			Brackets = hand.Rise,
			GlowTransparency = function()
				return 0.6 - 0.3 * hand.Light() - 0.3 * cheer.Flash()
			end,
		}, {
			Name = "Slab",
			Position = function()
				return UDim2.fromOffset(math.round(8 * cheer.Shake()), 0)
			end,
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 3, 3),
			-- The hand's glint, and the screen's call crossing it while it waits to be bought.
			Components.Sheen(
				if call
					then Hand.Sheen(hand, function(): number
						return if isOwned() then 1 else call()
					end)
					else hand.Glint,
				3
			),
			create("Frame")({
				Name = "Word",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 4,
				robuxWord(offer.Robux, textSize, function()
					return owned()
				end),
				create("Frame")({
					Name = "Owned",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromOffset(0, textSize),
					BackgroundTransparency = 1,
					ZIndex = 4,
					Visible = function()
						return owned() > 0
					end,
					create("UIScale")({
						Scale = function()
							return 0.6 + 0.4 * owned()
						end,
					}),
					create("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
					}),
					Components.Picture(EIcons.Check, {
						LayoutOrder = 1,
						Size = Components.PictureBox(math.round(textSize * 0.9)),
						ImageColor3 = Palette.Green,
						ImageTransparency = function()
							return 1 - owned()
						end,
						ZIndex = 5,
					}),
					Parts.Label({
						LayoutOrder = 2,
						AutomaticSize = Enum.AutomaticSize.X,
						Size = UDim2.fromOffset(0, textSize),
						TextSize = math.round(textSize * 0.8),
						TextYAlignment = Enum.TextYAlignment.Center,
						TextColor3 = Palette.Lavender,
						TextTransparency = function()
							return 1 - owned()
						end,
						Text = "OWNED",
						ZIndex = 5,
					}),
				}),
			}),
		}),
		props,
	}) :: TextButton
end

-- The gift button beside a price (the reference's violet square): opens the list of players to give the offer to.
-- It grows whole under the hand, as the price beside it does, the box riding it with only a little more of its own.
function Parts.Gift(
	actions: Types.TShopActions,
	offer: ShopCore.TOffer,
	size: number,
	props: { [any]: any }
): TextButton
	local hand = Hand.React("Take")

	return Components.Button({
		Name = "Gift",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Activated = function()
			hand.Commit()
			actions.OpenGift(offer.Name)
		end,
		hand.Events,
		create("UIScale")({ Scale = hand.Scale }),
		Components.Slab({
			Kind = "Violet",
			Marks = true,
			Brackets = hand.Rise,
			GlowTransparency = function()
				return 0.65 - 0.3 * hand.Light()
			end,
		}, {
			Name = "Slab",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 3, 3),
			Components.Sheen(hand.Glint, 3),
			Components.Picture(EIcons.GiftBox, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = Components.PictureBox(math.round(size * 0.62)),
				ZIndex = 5,
				create("UIScale")({
					Scale = function()
						return 1 + 0.06 * hand.Rise()
					end,
				}),
			}),
		}),
		props,
	}) :: TextButton
end

return Parts
