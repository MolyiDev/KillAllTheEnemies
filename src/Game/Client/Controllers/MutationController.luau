--!nonstrict
-- The Mutation Lab's part of a match on this player's screen: the souls a kill dropped for them (Mutation.EnergyDropped),
-- a chip right of the money plate that counts up while the same kind keeps dropping, and the potions they drank as the
-- run started (Mutation.Drunk), on a banner over the money plate. Built from his panel and his flat tags.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local vide = require(ReplicatedStorage.Packages.vide)
local NetworkMeta = require(StarterPlayer.StarterPlayerScripts.GlobalClient.NetworkMeta)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local PotionsCore = require(ReplicatedStorage.GlobalShared.Core.PotionsCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)
local ERarities = require(ReplicatedStorage.Types.Enums.ERarities)

local ServerNetworkMutation = NetworkMeta.Server.Mutation
local LocalPlayer = Players.LocalPlayer
local source = vide.source
local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress

local Layout = table.freeze({
	DESIGN_HEIGHT = 1080,
	-- Right of his money plate (its right edge 1096, its middle 901), clear of the hotbar under it.
	CHIP = Vector2.new(1120, 880),
	CHIP_SIZE = Vector2.new(250, 44),
	BOLT = 26,
	CHIP_TEXT = 17,
	-- Over the money plate, under the middle of the view.
	BANNER_BOTTOM = 840,
	ROW = 64,
	BANNER_WIDTH = 560,
	BOTTLE = 48,
})

local Timing = table.freeze({
	-- A chip stays this long after its last drop, then fades; another drop of the same kind within it counts up.
	CHIP = 2.6,
	CHIP_IN = 0.2,
	CHIP_OUT = 0.3,
	PUNCH = 0.25,
	-- The banner: in, held, out; its rows land one after another.
	BANNER = 5,
	BANNER_IN = 0.3,
	BANNER_OUT = 0.35,
	ROW_STAGGER = 0.18,
})

local MutationController = {}

local scale = source(1)
local now = source(os.clock())
local motionUntil = -math.huge
-- The chip: the kind on it, how many in a row, the last drop's stamp and the first's.
local chipKind = source(0)
local chipCount = source(0)
local chipAt = source(-math.huge)
local chipStartedAt = source(-math.huge)
-- The banner: what was drunk ({ Recipe, Rarity }) and when.
local drunk = source({} :: { { Recipe: number, Rarity: number } })
local drunkAt = source(-math.huge)

local function stir(seconds: number)
	motionUntil = math.max(motionUntil, os.clock() + seconds)
end

local function rarityOf(rarity: number)
	for name, value in ERarities do
		if value == rarity then return Theme.Rarities[name] end
	end
	return Theme.Rarities.Common
end

local function chip(): Frame
	local shown = derive(function(): number
		local since = now() - chipAt()
		local first = now() - chipStartedAt()
		if since < 0 or since > Timing.CHIP then return 0 end
		return math.min(
			Motion.Decelerate(math.clamp(first / Timing.CHIP_IN, 0, 1)),
			(Timing.CHIP - since) / Timing.CHIP_OUT,
			1
		)
	end)
	local punch = derive(function(): number
		return 1 + 0.18 * (1 - Motion.Decelerate(Progress(now(), chipAt(), Timing.PUNCH)))
	end)
	local color = derive(function(): Color3
		local enemy = DataCore.Enemies.ById[chipKind()]
		return if enemy and enemy.Energy then enemy.Energy.Color else Palette.White
	end)

	return Components.Panel({ Glow = color, GlowTransparency = 0.6 }, {
		Name = "EnergyChip",
		Position = function()
			return UDim2.fromOffset(Layout.CHIP.X - math.round(24 * (1 - shown())), Layout.CHIP.Y)
		end,
		Size = UDim2.fromOffset(Layout.CHIP_SIZE.X, Layout.CHIP_SIZE.Y),
		Visible = function()
			return shown() > 0.01
		end,
		create("UIScale")({
			Scale = function()
				return (0.85 + 0.15 * shown()) * punch()
			end,
		}),
		Components.Picture(EIcons.Soul, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(26, Layout.CHIP_SIZE.Y / 2),
			Size = Components.PictureBox(Layout.BOLT),
			ImageColor3 = color,
			ImageTransparency = function()
				return 1 - shown()
			end,
			ZIndex = 3,
		}),
		create("TextLabel")({
			Position = UDim2.fromOffset(48, (Layout.CHIP_SIZE.Y - Layout.CHIP_TEXT) / 2),
			Size = UDim2.new(1, -56, 0, Layout.CHIP_TEXT),
			BackgroundTransparency = 1,
			FontFace = Font.Display,
			TextSize = Layout.CHIP_TEXT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = color,
			TextTransparency = function()
				return 1 - shown()
			end,
			Text = function()
				local enemy = DataCore.Enemies.ById[chipKind()]
				if not enemy then return "" end
				local word = if enemy.IsBoss
					then "BOSS"
					else string.upper((string.gsub(enemy.Name, "%s*Zombie%s*", "")))
				return `+{chipCount()} {word} {if chipCount() == 1 then "SOUL" else "SOULS"}`
			end,
			ZIndex = 3,
		}),
	})
end

local function banner(): Frame
	local elapsed = derive(function(): number
		return math.min(now() - drunkAt(), Timing.BANNER)
	end)
	local shown = derive(function(): number
		local at = elapsed()
		if at >= Timing.BANNER then return 0 end
		local coming = Motion.Decelerate(math.clamp(at / Timing.BANNER_IN, 0, 1))
		local going = 1 - Motion.Accelerate(Progress(at, Timing.BANNER - Timing.BANNER_OUT, Timing.BANNER_OUT))
		return math.min(coming, going)
	end)
	local height = derive(function(): number
		return 46 + Layout.ROW * #drunk()
	end)

	return Components.Panel({ Brackets = true }, {
		Name = "Drunk",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = function()
			return UDim2.fromOffset(960, Layout.BANNER_BOTTOM + math.round(20 * (1 - shown())))
		end,
		Size = function()
			return UDim2.fromOffset(Layout.BANNER_WIDTH, height())
		end,
		Visible = function()
			return shown() > 0.01
		end,
		create("UIScale")({
			Scale = function()
				return 0.9 + 0.1 * shown()
			end,
		}),
		create("TextLabel")({
			Position = UDim2.fromOffset(20, 14),
			Size = UDim2.new(1, -40, 0, 20),
			BackgroundTransparency = 1,
			FontFace = Font.Display,
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Palette.Gold,
			TextTransparency = function()
				return 1 - shown()
			end,
			Text = "POTIONS ACTIVE THIS MATCH",
			ZIndex = 3,
		}),
		vide.indexes(drunk, function(entry: () -> { Recipe: number, Rarity: number }, index: number)
			local landed = derive(function(): number
				return Motion.Decelerate(Progress(elapsed(), Timing.BANNER_IN + Timing.ROW_STAGGER * (index - 1), 0.3))
			end)
			local look = derive(function()
				return rarityOf(entry().Rarity)
			end)
			local alpha = function(): number
				return 1 - landed() * shown()
			end
			return create("Frame")({
				Name = `Row{index}`,
				Position = function()
					return UDim2.fromOffset(20 + math.round(30 * (1 - landed())), 44 + Layout.ROW * (index - 1))
				end,
				Size = UDim2.new(1, -40, 0, Layout.ROW - 6),
				BackgroundTransparency = 1,
				ZIndex = 3,
				Components.Picture(EIcons.PotionBottle, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(Layout.BOTTLE / 2, (Layout.ROW - 6) / 2),
					Size = Components.PictureBox(Layout.BOTTLE),
					ImageColor3 = function()
						return look().Accent
					end,
					ImageTransparency = alpha,
				}),
				create("TextLabel")({
					Position = UDim2.fromOffset(Layout.BOTTLE + 14, 4),
					Size = UDim2.new(1, -Layout.BOTTLE - 14, 0, 20),
					BackgroundTransparency = 1,
					FontFace = Font.Display,
					TextSize = 20,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = function()
						return look().Accent
					end,
					TextTransparency = alpha,
					Text = function()
						local recipe = DataCore.Potions.ById[entry().Recipe]
						return if recipe then `{string.upper(recipe.Name)}  ·  {look().Text}` else ""
					end,
				}),
				create("TextLabel")({
					Position = UDim2.fromOffset(Layout.BOTTLE + 14, 30),
					Size = UDim2.new(1, -Layout.BOTTLE - 14, 0, 15),
					BackgroundTransparency = 1,
					FontFace = Font.DisplayBold,
					TextSize = 15,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = Palette.White,
					TextTransparency = alpha,
					Text = function()
						local recipe = DataCore.Potions.ById[entry().Recipe]
						if not recipe then return "" end
						local lines = {}
						for at, effect in PotionsCore.Effects(recipe, entry().Rarity) do
							lines[at] = PotionsCore.Describe(effect)
						end
						return table.concat(lines, "   ")
					end,
				}),
			})
		end),
	})
end

local function updateScale()
	scale(math.max(Workspace.CurrentCamera.ViewportSize.Y / Layout.DESIGN_HEIGHT, 0.01))
end

MutationController.OnStart = function()
	vide.mount(function()
		return create("ScreenGui")({
			Name = "Mutation",
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			DisplayOrder = 2,
			create("Frame")({
				Name = "Root",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0),
				Size = function()
					return UDim2.fromOffset(1920, Layout.DESIGN_HEIGHT)
				end,
				BackgroundTransparency = 1,
				create("UIScale")({ Scale = scale }),
				chip(),
				banner(),
			}),
		})
	end, LocalPlayer:WaitForChild("PlayerGui"))

	-- The clock runs only while a chip or the banner is up.
	RunService.PreRender:Connect(function()
		local at = os.clock()
		if at < motionUntil then now(at) end
	end)
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	updateScale()
end

ServerNetworkMutation.EnergyDropped.On(function(enemyId: number)
	local at = os.clock()
	local isStacking = chipKind() == enemyId and at - chipAt() < Timing.CHIP
	vide.batch(function()
		if not isStacking then
			chipKind(enemyId)
			chipCount(0)
			chipStartedAt(at)
		end
		chipCount(chipCount() + 1)
		chipAt(at)
	end)
	stir(Timing.CHIP + 0.1)
	SoundsCore.PlayUINamed("UI.UpgradePick", "Tick", 1 + 0.06 * math.min(chipCount(), 8))
end)

ServerNetworkMutation.Drunk.On(function(recipeIds: { number }, rarities: { number })
	local list = table.create(#recipeIds)
	for index, recipeId in recipeIds do
		list[index] = { Recipe = recipeId, Rarity = rarities[index] }
	end
	vide.batch(function()
		drunk(list)
		drunkAt(os.clock())
	end)
	stir(Timing.BANNER + 0.1)
	SoundsCore.PlayUINamed("UI.UpgradePick", "RevealEpic")
end)

return Ignis.Register(MutationController)
