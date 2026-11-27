-- How much this client draws, from the player's Roblox graphics level: a tier (Low, Medium, High) for the effects
-- budget (fxBudget) and a scale for the distances and counts (EnemiesController's animation limits and render
-- distance, DamageNumbersController's reach). There is no setting of its own: the norm is High on a PC and Medium on a
-- phone, and the graphics slider moves it down or up.
--
-- Automatic (SavedQualityLevel 0) cannot be read back as a level from a game script, so it is a guess by device; a
-- client on Automatic that cannot hold MIN_FPS over a CHECK_SECONDS window drops a tier, never back up.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Signal = require(ReplicatedStorage.Packages.Signal)

local UserGameSettings = UserSettings():GetService("UserGameSettings")

local GraphicsQualityController = {}

GraphicsQualityController.LOW = 1
GraphicsQualityController.MEDIUM = 2
GraphicsQualityController.HIGH = 3
GraphicsQualityController.IS_PHONE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
-- Fired with nothing when the tier or the scale moves.
GraphicsQualityController.OnChanged = Signal.new()

local Tune = table.freeze({
	-- The slider's level 1 to 10 scales the distances and counts from MIN_SCALE to MAX_SCALE, 1 in the middle.
	MIN_SCALE = 0.4,
	MAX_SCALE = 1.6,
	-- What an Automatic client scales them by after dropping no tier, one, two.
	DROPPED_SCALES = table.freeze({ 1, 0.7, 0.4 }),
	MIN_FPS = 45,
	CHECK_SECONDS = 20,
	-- Not judged in the first seconds of a place: loading and streaming in are not the game's frame rate.
	WARMUP_SECONDS = 10,
})

-- What each tier switches off in Lighting, as long as it holds; a higher tier puts back the place's own values. Phones
-- are GPU-bound in a fight (41.7 ms of GPU on a Samsung A13, performance/ingame-2026-11-08).
local LIGHTING_OFF = table.freeze({
	[GraphicsQualityController.LOW] = table.freeze({
		BloomEffect = true,
		SunRaysEffect = true,
		DepthOfFieldEffect = true,
		-- Lighting.GlobalShadows, not an effect.
		Shadows = true,
	}),
	[GraphicsQualityController.MEDIUM] = table.freeze({ SunRaysEffect = true, DepthOfFieldEffect = true }),
	[GraphicsQualityController.HIGH] = table.freeze({}),
})

local tier = GraphicsQualityController.HIGH
local scale = 1
-- The place's own post effects of the classes a tier switches, as the place has them (read once at start), and its
-- GlobalShadows. Effects made later (a cutscene's focus, the screens' blur) are their owners' alone.
local placeEnabled: { [PostEffect]: boolean } = {}
local placeShadows = Lighting.GlobalShadows
-- Tiers an Automatic client dropped for its frame rate.
local droppedTiers = 0

-- LOW, MEDIUM or HIGH.
function GraphicsQualityController.Tier(): number
	return tier
end

-- What distances and counts are multiplied by: 1 is the norm.
function GraphicsQualityController.Scale(): number
	return scale
end

-- The level the player set (1-10), or what the engine reports for Automatic where a script may read it; 0 for neither.
local function graphicsLevel(): number
	local saved = UserGameSettings.SavedQualityLevel.Value
	if saved > 0 then return saved end
	local isRead, level = pcall(function()
		return (UserGameSettings :: any).GraphicsQualityLevel
	end)
	return if isRead and type(level) == "number" then level else 0
end

local function refresh()
	local level = graphicsLevel()
	local newTier, newScale
	if level > 0 then
		newTier = if level <= 3
			then GraphicsQualityController.LOW
			elseif level <= 6 then GraphicsQualityController.MEDIUM
			else GraphicsQualityController.HIGH
		newScale = Tune.MIN_SCALE + (Tune.MAX_SCALE - Tune.MIN_SCALE) * (math.clamp(level, 1, 10) - 1) / 9
	else
		local norm = if GraphicsQualityController.IS_PHONE
			then GraphicsQualityController.MEDIUM
			else GraphicsQualityController.HIGH
		newTier = math.max(norm - droppedTiers, GraphicsQualityController.LOW)
		newScale = Tune.DROPPED_SCALES[math.min(droppedTiers + 1, #Tune.DROPPED_SCALES)]
	end
	if newTier == tier and newScale == scale then return end
	tier = newTier
	scale = newScale
	GraphicsQualityController.OnChanged:Fire()
end

-- The tier's Lighting: the place's own Bloom, SunRays and DepthOfField, and its shadows.
local function applyLighting()
	local off = LIGHTING_OFF[tier]
	for effect, own in placeEnabled do
		local isEnabled = own and not off[effect.ClassName]
		if effect.Enabled ~= isEnabled then effect.Enabled = isEnabled end
	end
	local hasShadows = placeShadows and not off.Shadows
	if Lighting.GlobalShadows ~= hasShadows then Lighting.GlobalShadows = hasShadows end
end

-- At load, so every controller reads the tier and scale from its own start.
refresh()

GraphicsQualityController.OnStart = function()
	for _, effect in Lighting:GetChildren() do
		if effect:IsA("BloomEffect") or effect:IsA("SunRaysEffect") or effect:IsA("DepthOfFieldEffect") then
			placeEnabled[effect] = effect.Enabled
		end
	end
	applyLighting()
	GraphicsQualityController.OnChanged:Connect(applyLighting)
	UserGameSettings:GetPropertyChangedSignal("SavedQualityLevel"):Connect(refresh)

	-- One window per place, after the warmup: a single heavy moment later (a nuke) never takes a tier away.
	local elapsed, frames, windowSeconds = 0, 0, 0
	local connection: RBXScriptConnection
	connection = RunService.PreRender:Connect(function(dt: number)
		elapsed += dt
		if elapsed < Tune.WARMUP_SECONDS then return end
		frames += 1
		windowSeconds += dt
		if windowSeconds < Tune.CHECK_SECONDS then return end
		connection:Disconnect()
		if graphicsLevel() > 0 or frames / windowSeconds >= Tune.MIN_FPS then return end
		droppedTiers += 1
		refresh()
	end)
end

return Ignis.Register(GraphicsQualityController)
