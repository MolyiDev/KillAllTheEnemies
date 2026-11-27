--!nonstrict
-- The bar: his dark plate stretching open from its middle, a pink fill with a white leading edge and a light crossing
-- it now and then, the stage over it on the left and the percentage on the right. Full, the well flashes white and
-- the words turn to READY. Leaving, the plate closes back to its middle as it opened, and the words fade.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Progress = Motion.Progress

local Bar = {}

-- When the bar deals in, in seconds after the content began, and when the fill starts chasing the load (the plate
-- nearly open).
Bar.AT = 0.7
Bar.FILLS_AT = Bar.AT + 0.3

local Layout = table.freeze({
	-- From the screen's middle, in design px.
	Y = 126,
	SIZE = Vector2.new(860, 46),
	-- The well inside the plate.
	WELL_INSET = 20,
	WELL_HEIGHT = 14,
	CAPTION = 22,
	PERCENT = 34,
	-- The captions' bottoms over the plate's top edge.
	CAPTION_GAP = 12,
	EDGE_GLOW = 34,
})

local Look = table.freeze({
	TRACK = Color3.fromRGB(40, 32, 66),
	FILL = table.freeze({
		{ 0, Color3.fromRGB(255, 130, 188) },
		{ 0.45, Color3.fromRGB(255, 46, 139) },
		{ 1, Color3.fromRGB(186, 18, 96) },
	}),
	GLOW_TRANSPARENCY = 0.72,
})

local Timing = table.freeze({
	OPEN_SECONDS = 0.45,
	CAPTIONS_AT = 0.25,
	CAPTIONS_SECONDS = 0.3,
	CAPTIONS_RISE = 10,
	DOT_SECONDS = 0.35,
	SHEEN_EVERY = 3,
	SHEEN_SECONDS = 0.8,
	FLASH_SECONDS = 0.45,
	FLASH = 0.7,
})

-- When the plate is open and its words are in, in seconds after the content began.
Bar.UP_AT = Bar.AT + math.max(Timing.OPEN_SECONDS, Timing.CAPTIONS_AT + Timing.CAPTIONS_SECONDS)

function Bar.Build(state: Types.TState, clock: Types.TClock): { Instance }
	local since = derive(function(): number
		return clock.Since(state.BeganAt())
	end)
	local open = derive(function(): number
		return Motion.Decelerate(Progress(since(), Bar.AT, Timing.OPEN_SECONDS))
	end)
	local isPaid = derive(function(): boolean
		return state.PaidAt() ~= math.huge
	end)
	local flash = derive(function(): number
		local paid = clock.Since(state.PaidAt())
		if paid < 0 then return 0 end
		return 1 - math.min(1, paid / Timing.FLASH_SECONDS)
	end)
	local captions = derive(function(): number
		return Motion.Decelerate(Progress(since(), Bar.AT + Timing.CAPTIONS_AT, Timing.CAPTIONS_SECONDS))
	end)
	local plateWidth = derive(function(): number
		return math.round(Layout.SIZE.X * open() * clock.Close(0))
	end)
	local wellWidth = Layout.SIZE.X - 2 * Layout.WELL_INSET

	local fill = create("Frame")({
		Name = "Fill",
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 3,
		Size = function()
			return UDim2.fromScale(math.clamp(state.Reading(), 0, 1), 1)
		end,
		create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		Components.Gradient(Look.FILL),
		Components.Sheen(function(): number
			local t = since() - Bar.AT - Timing.OPEN_SECONDS
			if t < 0 then return 0 end
			return math.min(1, (t % Timing.SHEEN_EVERY) / Timing.SHEEN_SECONDS)
		end, 4, wellWidth / Layout.WELL_HEIGHT),
	})

	local well = create("Frame")({
		Name = "Well",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		-- Against the plate, so it opens with it.
		Size = UDim2.new(1, -2 * Layout.WELL_INSET, 0, Layout.WELL_HEIGHT),
		BackgroundColor3 = Look.TRACK,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 3,
		create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		fill,
		create("Frame")({
			Name = "Flash",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Palette.White,
			BorderSizePixel = 0,
			ZIndex = 6,
			Visible = function()
				return flash() > 0
			end,
			BackgroundTransparency = function()
				return 1 - Timing.FLASH * flash()
			end,
		}),
	})

	-- The edge's light reaches past the well's top and bottom, so it is laid in a lane the well's size over it rather
	-- than in the well, which clips. Sized against the plate like the well, so it opens and closes with it.
	local edgeLane = create("Frame")({
		Name = "EdgeLane",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -2 * Layout.WELL_INSET, 0, Layout.WELL_HEIGHT),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Visible = function()
			return state.Reading() > 0.002
		end,
		create("Frame")({
			Name = "Edge",
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundTransparency = 1,
			Position = function()
				return UDim2.fromScale(math.clamp(state.Reading(), 0, 1), 0.5)
			end,
			Size = UDim2.new(0, Layout.EDGE_GLOW, 1, 6),
			-- Light running back along the fill from its edge.
			create("Frame")({
				Name = "Glow",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				create("UIGradient")({
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 1),
						NumberSequenceKeypoint.new(1, 0.45),
					}),
				}),
			}),
			create("Frame")({
				Name = "Line",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.new(0, 3, 1, 0),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
			}),
		}),
	})

	local plate = Components.Panel({
		Brackets = true,
		Glow = Palette.Pink,
		GlowTransparency = Look.GLOW_TRANSPARENCY,
		Wide = true,
	}, {
		Name = "Plate",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = function()
			return UDim2.fromOffset(plateWidth(), Layout.SIZE.Y)
		end,
		Visible = function()
			return plateWidth() > 8
		end,
		ZIndex = 2,
		well,
		edgeLane,
	})

	local dots = derive(function(): string
		if isPaid() then return "" end
		return string.rep(".", math.floor(state.Now() / Timing.DOT_SECONDS) % 4)
	end)
	local captionY = -Layout.SIZE.Y / 2 - Layout.CAPTION_GAP
	local function captionProps(anchorX: number, x: number): { [any]: any }
		return {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(anchorX, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			ZIndex = 4,
			FontFace = Theme.Font.Display,
			TextXAlignment = if anchorX == 0 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
			TextYAlignment = Enum.TextYAlignment.Bottom,
			TextTransparency = function()
				return 1 - captions() * clock.Opacity(0)
			end,
			Position = function()
				local rise = (1 - captions()) * Timing.CAPTIONS_RISE
				return UDim2.new(0.5, x, 0.5, math.round(captionY + rise))
			end,
		}
	end

	return {
		create("Frame")({
			Name = "Bar",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, Layout.Y),
			Size = UDim2.fromOffset(Layout.SIZE.X, Layout.SIZE.Y),
			BackgroundTransparency = 1,
			ZIndex = 2,
			plate,
			create("TextLabel")({
				Name = "Phase",
				-- Rewritten as its dots step: not sent to translation each time.
				AutoLocalize = false,
				Size = UDim2.fromOffset(0, Layout.CAPTION),
				TextSize = Layout.CAPTION,
				Text = function()
					return (if isPaid() then "READY" else state.Phase()) .. dots()
				end,
				TextColor3 = function()
					return if isPaid() then Palette.Green else Palette.Lavender
				end,
				captionProps(0, math.round(-Layout.SIZE.X / 2 + 4)),
			}),
			create("TextLabel")({
				Name = "Percent",
				AutoLocalize = false,
				Size = UDim2.fromOffset(0, Layout.PERCENT),
				TextSize = Layout.PERCENT,
				TextColor3 = Palette.Gold,
				Text = function()
					return `{math.floor(math.clamp(state.Reading(), 0, 1) * 100 + 1e-6)}%`
				end,
				captionProps(1, math.round(Layout.SIZE.X / 2 - 4)),
			}),
		}),
	}
end

return Bar
