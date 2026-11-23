--!nonstrict
-- A soft dark patch behind what stands straight on the stage (the squad's tags, the match stats): no edge of its own,
-- it fades out on every side, so it reads as a shadow under them rather than a panel. Two crossed fades: the group's
-- gradient across it, its face's down it, and a gradient on a CanvasGroup fades the whole group.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.vide)

local create = vide.create

-- The fade over a side's FEATHER, eased, so neither its start nor its end shows as a line.
local function fade(feather: number): NumberSequence
	local keys = { NumberSequenceKeypoint.new(0, 1) }
	for step = 1, 4 do
		local t = step / 4
		local eased = t * t * (3 - 2 * t)
		keys[#keys + 1] = NumberSequenceKeypoint.new(feather * t, 1 - eased)
	end
	for step = 4, 1, -1 do
		local t = step / 4
		local eased = t * t * (3 - 2 * t)
		keys[#keys + 1] = NumberSequenceKeypoint.new(1 - feather * t, 1 - eased)
	end
	keys[#keys + 1] = NumberSequenceKeypoint.new(1, 1)
	return NumberSequence.new(keys)
end

-- A patch `size` px (or a getter, for one that follows what it is under), fading out over `featherPx` at each side,
-- `strength` dark at its middle (0 to 1). `props` is the group's: its place, and GroupTransparency to bring it in and
-- out with what it is under.
return function(size: Vector2 | () -> Vector2, featherPx: number, strength: number, props: { [any]: any }): CanvasGroup
	local sizeOf = if type(size) == "function"
		then size
		else function(): Vector2
			return size
		end

	return create("CanvasGroup")({
		Name = "Scrim",
		Size = function()
			local at = sizeOf()
			return UDim2.fromOffset(at.X, at.Y)
		end,
		BackgroundTransparency = 1,
		Interactable = false,
		create("UIGradient")({
			Transparency = function()
				return fade(math.min(featherPx / sizeOf().X, 0.49))
			end,
		}),
		create("Frame")({
			Name = "Face",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(),
			BackgroundTransparency = 1 - strength,
			BorderSizePixel = 0,
			create("UIGradient")({
				Rotation = 90,
				Transparency = function()
					return fade(math.min(featherPx / sizeOf().Y, 0.49))
				end,
			}),
		}),
		props,
	})
end
