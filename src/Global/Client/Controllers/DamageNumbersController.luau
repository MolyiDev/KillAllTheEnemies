-- The numbers over the fight: what a blow did to a body, and the Gold a kill paid. Screen-space labels projected from
-- the world every frame, so they read at one size at any distance and are never hidden behind a body. Every blow is
-- its own number, left where it landed: a number that counted up stayed behind a body that had walked on. Each is
-- thrown somewhere over the body, not on one point, so a stream of blows spreads across it. Purely a picture.
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local CharacterController = require(script.Parent.CharacterController)
local GraphicsQualityController = require(script.Parent.GraphicsQualityController)
local WeaponController = require(script.Parent.WeaponController)
local targetHits = require(script.Parent.Parent.Utils.targetHits)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local UiFade = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.UiFade)

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- A heavy italic: a slanted figure reads as a blow in motion where an upright one reads as a price tag.
local FONT = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)

local Tune = table.freeze({
	MAX_POPUPS = 48,
	-- New numbers a frame: a blast through a crowd shows the nearest few, and past that nobody could read which number
	-- was whose.
	MAX_OWN_SPAWNS_PER_FRAME = 10,
	MAX_ALLY_SPAWNS_PER_FRAME = 3,
	OWN_DISTANCE = 160,
	ALLY_DISTANCE = 70,
	-- Gold from a kill this soon after the last, and this close to it, adds up on one figure; a body killed stays put,
	-- so the sum stands where all of them fell. Each kill counted grows it this much, up to the cap.
	GOLD_MERGE_SECONDS = 0.75,
	GOLD_MERGE_STUDS = 14,
	STACK_GROWTH = 0.06,
	MAX_STACK_SCALE = 1.5,
	-- The stamp: lands huge, slams through its size and settles. The rebound past it is damped, so a big stamp never
	-- squashes to nothing.
	PUNCH_SECONDS = 0.24,
	PUNCH_DECAY = 5,
	PUNCH_WOBBLE = 9,
	PUNCH_REBOUND = 0.35,
	REPUNCH_FROM = 1.45,
	-- The first frames draw the figure pure white, the impact frame, before its colour comes in.
	WHITE_SECONDS = 0.06,
	SHAKE_SECONDS = 0.2,
	FADE_SECONDS = 0.3,
	FADE_SHRINK = 0.4,
	-- Pixels at 1080 tall. Each number drifts to the other side from the last, so a string of fast blows on one body
	-- fans out instead of printing over itself.
	MIN_DRIFT_PIXELS = 14,
	MAX_DRIFT_PIXELS = 40,
	-- The tilt a number is thrown at; it straightens to this share of it as the stamp settles.
	TILT_DEG = 11,
	TILT_SETTLED = 0.35,
	-- Nearer numbers a little bigger, so a crowd's numbers have depth; never so small they stop reading.
	NEAR_STUDS = 20,
	FAR_STUDS = 140,
	NEAR_SCALE = 1.15,
	FAR_SCALE = 0.72,
	-- After the kill's number, so the eye reads the blow, then the pay.
	GOLD_DELAY = 0.12,
	GOLD_LIFT = Vector3.new(0, 2.5, 0),
	-- Above the chest the number was aimed at, so it starts clear of the head.
	DAMAGE_LIFT = Vector3.new(0, 1.6, 0),
	-- Where a number starts: anywhere across the view within this share of the body's half width round its anchor (a
	-- body that says none counts as DEFAULT_HALF_WIDTH, an R6 body's), or within BOSS_SCATTER_STUDS of where the
	-- player's bullet went into a boss, whose numbers stand where its shots land.
	SCATTER_SHARE = 0.9,
	DEFAULT_HALF_WIDTH = 1,
	BOSS_SCATTER_STUDS = 3,
})

-- Top to bottom: a white-hot top melting into the hue, the anime highlight. The stroke is the hue's own dark, never
-- black, so the figure keeps its colour at the edge.
type TStyle = {
	TextSize: number,
	Gradient: ColorSequence,
	Stroke: Color3,
	StrokeShare: number,
	Life: number,
	PunchFrom: number,
	RisePixels: number,
	ShakePixels: number,
	BaseTransparency: number,
	ZIndex: number,
}

local function gradient(top: Color3, middle: Color3, bottom: Color3): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, top),
		ColorSequenceKeypoint.new(0.45, middle),
		ColorSequenceKeypoint.new(1, bottom),
	})
end

local Styles = table.freeze({
	Hit = table.freeze({
		TextSize = 34,
		Gradient = gradient(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 236, 120), Color3.fromRGB(255, 160, 30)),
		Stroke = Color3.fromRGB(80, 34, 0),
		StrokeShare = 0.1,
		Life = 0.9,
		PunchFrom = 2.4,
		RisePixels = 60,
		ShakePixels = 5,
		BaseTransparency = 0,
		ZIndex = 2,
	} :: TStyle),
	-- The killing blow: hotter, bigger, held longer.
	Kill = table.freeze({
		TextSize = 44,
		Gradient = gradient(Color3.fromRGB(255, 250, 225), Color3.fromRGB(255, 150, 40), Color3.fromRGB(255, 36, 60)),
		Stroke = Color3.fromRGB(70, 0, 14),
		StrokeShare = 0.11,
		Life = 1.15,
		PunchFrom = 3,
		RisePixels = 80,
		ShakePixels = 10,
		BaseTransparency = 0,
		ZIndex = 3,
	} :: TStyle),
	-- The violet of the overkill burst (VFX.md section 15), so the number and the gore are one moment.
	Overkill = table.freeze({
		TextSize = 56,
		Gradient = gradient(Color3.fromRGB(255, 240, 255), Color3.fromRGB(255, 96, 220), Color3.fromRGB(140, 60, 255)),
		Stroke = Color3.fromRGB(36, 0, 66),
		StrokeShare = 0.11,
		Life = 1.35,
		PunchFrom = 3.4,
		RisePixels = 95,
		ShakePixels = 16,
		BaseTransparency = 0,
		ZIndex = 4,
	} :: TStyle),
	-- A teammate's blows: there, small and quiet, so your own still stand out in a shared crowd.
	Ally = table.freeze({
		TextSize = 22,
		Gradient = gradient(
			Color3.fromRGB(255, 255, 255),
			Color3.fromRGB(226, 230, 238),
			Color3.fromRGB(170, 178, 194)
		),
		Stroke = Color3.fromRGB(20, 22, 28),
		StrokeShare = 0.1,
		Life = 0.7,
		PunchFrom = 1.6,
		RisePixels = 40,
		ShakePixels = 0,
		BaseTransparency = 0.3,
		ZIndex = 1,
	} :: TStyle),
	Gold = table.freeze({
		TextSize = 38,
		Gradient = gradient(Color3.fromRGB(255, 255, 220), Theme.Color.Gold, Color3.fromRGB(232, 128, 0)),
		Stroke = Color3.fromRGB(84, 42, 0),
		StrokeShare = 0.11,
		Life = 1.4,
		PunchFrom = 2.8,
		RisePixels = 110,
		ShakePixels = 8,
		BaseTransparency = 0,
		ZIndex = 5,
	} :: TStyle),
})

type TPopup = {
	Label: TextLabel,
	Scale: UIScale,
	Stroke: UIStroke,
	Gradient: UIGradient,
	Style: TStyle,
	IsLive: boolean,
	Anchor: Vector3,
	-- Negative until it shows (the Gold waits for its kill's number).
	Age: number,
	PunchAge: number,
	PunchFrom: number,
	Amount: number,
	Stacks: number,
	Drift: number,
	TiltDeg: number,
	-- What the label's Rotation and its text and stroke Transparency were last written to: both hold still between the
	-- punch and the fade, and an unchanged write is still a reflection call (performance/optimization-2026-11-26).
	ShownRotation: number,
	ShownTransparency: number,
}

local DamageNumbersController = {}

-- The settings screen's DAMAGE NUMBERS switch (SettingsController). Off, no blow shows a number; a kill's Gold still
-- does, since it is pay, not damage.
DamageNumbersController.IsDamageShown = true

local popups: { TPopup } = table.create(Tune.MAX_POPUPS)
local lastGold: TPopup? = nil
local selfCharacterId: number? = nil
local ownSpawns = 0
local allySpawns = 0
local viewportScale = 1
-- The reaches and per-frame caps at this graphics scale (GraphicsQualityController), refreshed as it moves.
local ownDistance = Tune.OWN_DISTANCE
local allyDistance = Tune.ALLY_DISTANCE
local maxOwnSpawns = Tune.MAX_OWN_SPAWNS_PER_FRAME
local maxAllySpawns = Tune.MAX_ALLY_SPAWNS_PER_FRAME
local driftSide = 1
local random = Random.new()

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FloatingNumbers"
-- WorldToViewportPoint counts from the top of the window, under the topbar too.
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
-- Under the HUD's three roots (HudController, -2 to 0): a number never covers a button.
screenGui.DisplayOrder = -3
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local function newPopup(): TPopup
	local label = Instance.new("TextLabel")
	label.Name = "Number"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Size = UDim2.fromOffset(0, 0)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.AutoLocalize = false
	label.FontFace = FONT
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Visible = false

	local scale = Instance.new("UIScale")
	scale.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	local textGradient = Instance.new("UIGradient")
	textGradient.Rotation = 90
	textGradient.Parent = label

	label.Parent = screenGui
	return {
		Label = label,
		Scale = scale,
		Stroke = stroke,
		Gradient = textGradient,
		Style = Styles.Hit,
		IsLive = false,
		Anchor = Vector3.zero,
		Age = 0,
		PunchAge = 0,
		PunchFrom = 1,
		Amount = 0,
		Stacks = 0,
		Drift = 0,
		TiltDeg = 0,
		ShownRotation = 0,
		ShownTransparency = 0,
	}
end

for i = 1, Tune.MAX_POPUPS do
	popups[i] = newPopup()
end

-- Whole numbers, with thousands shortened past where the digits stop fitting over a body.
local function formatAmount(amount: number): string
	if amount >= 1e6 then return string.format("%.1fM", amount / 1e6) end
	if amount >= 1e4 then return string.format("%.1fK", amount / 1e3) end
	return tostring(math.round(amount))
end

local function setText(popup: TPopup)
	local amount = formatAmount(popup.Amount)
	popup.Label.Text = if popup.Style == Styles.Gold then `+${amount}` else amount
end

local function applyStyle(popup: TPopup, style: TStyle)
	popup.Style = style
	local label = popup.Label
	label.TextSize = style.TextSize
	label.ZIndex = style.ZIndex
	popup.Gradient.Color = style.Gradient
	popup.Stroke.Color = style.Stroke
	popup.Stroke.Thickness = math.max(math.round(style.TextSize * style.StrokeShare), 2)
end

local function release(popup: TPopup)
	popup.IsLive = false
	popup.Label.Visible = false
	if lastGold == popup then lastGold = nil end
end

-- A free one, or the one nearest its end: a fresh blow matters more than one already fading.
local function take(): TPopup
	local oldest = popups[1]
	local oldestShare = -math.huge
	for _, popup in popups do
		if not popup.IsLive then return popup end
		local share = popup.Age / popup.Style.Life
		if share > oldestShare then
			oldestShare = share
			oldest = popup
		end
	end

	release(oldest)
	return oldest
end

local function isWorthShowing(position: Vector3, maxDistance: number): boolean
	local offset = position - Camera.CFrame.Position
	if offset:Dot(offset) > maxDistance * maxDistance then return false end
	local _, isOnScreen = Camera:WorldToViewportPoint(position)
	return isOnScreen
end

local function restamp(popup: TPopup, from: number)
	popup.PunchAge = 0
	popup.PunchFrom = from
	popup.Gradient.Enabled = false
end

local function spawn(style: TStyle, anchor: Vector3, amount: number, delaySeconds: number): TPopup
	local popup = take()
	popup.IsLive = true
	if not screenGui.Enabled then screenGui.Enabled = true end
	popup.Anchor = anchor
	popup.Age = -delaySeconds
	popup.Amount = amount
	popup.Stacks = 1
	driftSide = -driftSide
	popup.Drift = driftSide * random:NextNumber(Tune.MIN_DRIFT_PIXELS, Tune.MAX_DRIFT_PIXELS)
	-- Leaning the way it drifts, as if thrown off that side of the body.
	popup.TiltDeg = -driftSide * random:NextNumber(0.3, 1) * Tune.TILT_DEG
	applyStyle(popup, style)
	setText(popup)
	restamp(popup, style.PunchFrom)
	return popup
end

-- Counts more onto a live number: up goes the figure, the stamp lands again and its life starts over.
local function addTo(popup: TPopup, amount: number)
	popup.Amount += amount
	popup.Stacks += 1
	popup.Age = 0
	restamp(popup, Tune.REPUNCH_FROM)
	setText(popup)
end

local function isOwn(attackerId: number): boolean
	if not selfCharacterId then selfCharacterId = CharacterController.GetLocalCharacterId() end
	return attackerId ~= 0 and attackerId == selfCharacterId
end

-- A point anywhere within `radius` of `center` across the view, spread evenly over the disc.
local function scattered(center: Vector3, radius: number): Vector3
	local view = Camera.CFrame
	local turn = random:NextNumber(0, math.pi * 2)
	local reach = radius * math.sqrt(random:NextNumber())
	return center + view.RightVector * (math.cos(turn) * reach) + view.UpVector * (math.sin(turn) * reach)
end

-- Where a blow's number starts: over the chest within the body's width, or round the player's own bullet in a boss.
local function anchorOf(bodyId: number, attackerId: number, at: Vector3, halfWidth: number?): Vector3
	local contact = if isOwn(attackerId) then WeaponController.BossContact(bodyId) else nil
	if contact then return scattered(contact, Tune.BOSS_SCATTER_STUDS) end

	return scattered(at + Tune.DAMAGE_LIFT, (halfWidth or Tune.DEFAULT_HALF_WIDTH) * Tune.SCATTER_SHARE)
end

local function showBlow(attackerId: number, damage: number, anchor: Vector3, style: TStyle)
	if damage < 0.5 or not DamageNumbersController.IsDamageShown then return end

	if not isOwn(attackerId) then
		if allySpawns >= maxAllySpawns or not isWorthShowing(anchor, allyDistance) then return end
		allySpawns += 1
		spawn(Styles.Ally, anchor, damage, 0)
		return
	end

	if ownSpawns >= maxOwnSpawns or not isWorthShowing(anchor, ownDistance) then return end
	ownSpawns += 1
	spawn(style, anchor, damage, 0)
end

-- The Gold a kill paid, over where it fell (the match's MatchController, as the coins fly).
function DamageNumbersController.ShowGold(position: Vector3, amount: number)
	local anchor = position + Tune.GOLD_LIFT
	local live = lastGold
	if live and live.Age < Tune.GOLD_MERGE_SECONDS and (live.Anchor - anchor).Magnitude < Tune.GOLD_MERGE_STUDS then
		-- Still waiting on its kill's number: the sum shows when it does.
		if live.Age < 0 then
			live.Amount += amount
			setText(live)
		else
			addTo(live, amount)
		end
		return
	end

	if not isWorthShowing(anchor, ownDistance) then return end
	lastGold = spawn(Styles.Gold, anchor, amount, Tune.GOLD_DELAY)
end

-- 1 at rest: lands at `from`, slams through 1 and settles, its rebound damped.
local function stampScale(from: number, progress: number): number
	local wave = math.cos(progress * Tune.PUNCH_WOBBLE)
	if wave < 0 then
		wave *= Tune.PUNCH_REBOUND
	end
	return 1 + (from - 1) * math.exp(-Tune.PUNCH_DECAY * progress) * wave
end

local function depthScale(distance: number): number
	local share = math.clamp((distance - Tune.NEAR_STUDS) / (Tune.FAR_STUDS - Tune.NEAR_STUDS), 0, 1)
	return Tune.NEAR_SCALE + (Tune.FAR_SCALE - Tune.NEAR_SCALE) * share
end

local function refreshViewportScale()
	local height = Camera.ViewportSize.Y
	if height <= 0 then return end
	viewportScale = math.clamp(height / Theme.DESIGN_HEIGHT, Theme.MIN_SCALE, Theme.MAX_SCALE)
end

local function update(dt: number)
	ownSpawns = 0
	allySpawns = 0
	selfCharacterId = CharacterController.GetLocalCharacterId()

	local cameraPosition = Camera.CFrame.Position
	local now = os.clock()
	-- Faded with every screen's UI for a cutscene.
	local shown = UiFade.Shown()
	local liveCount = 0
	for _, popup in popups do
		if not popup.IsLive then continue end
		liveCount += 1
		local style = popup.Style
		popup.Age += dt
		local age = popup.Age
		if age < 0 then continue end
		local life = style.Life
		if age >= life then
			release(popup)
			continue
		end

		local label = popup.Label
		local screen, isOnScreen = Camera:WorldToViewportPoint(popup.Anchor)
		if not isOnScreen then
			if label.Visible then label.Visible = false end
			continue
		end

		popup.PunchAge += dt
		local punch = math.min(popup.PunchAge / Tune.PUNCH_SECONDS, 1)
		local share = age / life
		local fade = math.clamp((age - (life - Tune.FADE_SECONDS)) / Tune.FADE_SECONDS, 0, 1)
		-- Ease-out: it leaps off the body and hangs, so the figure is still while it is read.
		local rise = 1 - (1 - share) ^ 3
		local pixels = viewportScale
		local x = screen.X + popup.Drift * rise * pixels
		local y = screen.Y - style.RisePixels * rise * pixels
		local shakeShare = 1 - math.min(popup.PunchAge / Tune.SHAKE_SECONDS, 1)
		if shakeShare > 0 and style.ShakePixels > 0 then
			local amplitude = style.ShakePixels * shakeShare * shakeShare * pixels
			x += math.sin(now * 97 + popup.Drift) * amplitude
			y += math.cos(now * 83 + popup.TiltDeg) * amplitude
		end

		local stack = math.min(1 + (popup.Stacks - 1) * Tune.STACK_GROWTH, Tune.MAX_STACK_SCALE)
		local distance = (popup.Anchor - cameraPosition).Magnitude
		popup.Scale.Scale = viewportScale
			* depthScale(distance)
			* stack
			* stampScale(popup.PunchFrom, punch)
			* (1 - Tune.FADE_SHRINK * fade)
		label.Position = UDim2.fromOffset(x, y)
		local rotation = popup.TiltDeg * (Tune.TILT_SETTLED + (1 - Tune.TILT_SETTLED) * (1 - punch))
		if rotation ~= popup.ShownRotation then
			popup.ShownRotation = rotation
			label.Rotation = rotation
		end

		local isWhite = popup.PunchAge < Tune.WHITE_SECONDS
		if popup.Gradient.Enabled == isWhite then popup.Gradient.Enabled = not isWhite end
		local transparency = 1 - (1 - style.BaseTransparency) * (1 - fade) * shown
		if transparency ~= popup.ShownTransparency then
			popup.ShownTransparency = transparency
			label.TextTransparency = transparency
			popup.Stroke.Transparency = transparency
		end
		if not label.Visible then label.Visible = true end
	end

	-- Off while nothing shows: a touch device walks every enabled ScreenGui each frame (1.26 ms over 116 calls on a
	-- Samsung A13, performance/runui-2026-11-09). spawn switches it back on.
	if liveCount == 0 and screenGui.Enabled then screenGui.Enabled = false end
end

targetHits.Damaged:Connect(function(bodyId: number, attackerId: number, damage: number, at: Vector3, halfWidth: number?)
	showBlow(attackerId, damage, anchorOf(bodyId, attackerId, at, halfWidth), Styles.Hit)
end)

targetHits.Killed:Connect(
	function(bodyId: number, killerId: number, damage: number, isOverkill: boolean, at: Vector3, halfWidth: number?)
		local style = if isOverkill then Styles.Overkill else Styles.Kill
		showBlow(killerId, damage, anchorOf(bodyId, killerId, at, halfWidth), style)
	end
)

local function applyGraphicsScale()
	local scale = GraphicsQualityController.Scale()
	ownDistance = Tune.OWN_DISTANCE * scale
	allyDistance = Tune.ALLY_DISTANCE * scale
	maxOwnSpawns = math.max(1, math.round(Tune.MAX_OWN_SPAWNS_PER_FRAME * scale))
	maxAllySpawns = math.max(1, math.round(Tune.MAX_ALLY_SPAWNS_PER_FRAME * scale))
end

DamageNumbersController.OnStart = function()
	applyGraphicsScale()
	GraphicsQualityController.OnChanged:Connect(applyGraphicsScale)
	screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	refreshViewportScale()
	Camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshViewportScale)
	RunService.PreRender:Connect(update)

	-- The italic faces are downloaded, not shipped with the client: fetched now, the first kill is not drawn in the
	-- fallback font.
	task.spawn(ContentProvider.PreloadAsync, ContentProvider, { popups[1].Label })
end

return Ignis.Register(DamageNumbersController)
