-- Coins popping out of a kill and homing into the player (GDD 17), and a bought Gold pack's coins showering out of
-- the buyer and back into him. The Gold was credited on the server before these were sent; the HUD holds back
-- `PendingGold` and counts each coin in as it lands, so the number climbs WITH them.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local ObjectPooler = require(ReplicatedStorage.GlobalShared.Utils.ObjectPooler)
local MatchController = require(script.Parent.MatchController)
local CoinFlight = require(script.Parent.Parent.Utils.coinFlight)
local TCharacter = require(ReplicatedStorage.Types.TCharacter)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)

local LocalPlayer = Players.LocalPlayer
local TemporalFolder = Workspace:WaitForChild("Temporal")
-- A place instance (the anime game's place has it), so it may not be in this place yet.
local CoinModel = ReplicatedStorage:WaitForChild("Models"):FindFirstChild("Coin") :: BasePart?

-- At most this many coins a kill, and this many in the air at once, whatever the amount.
local COINS_PER_KILL = 4
local MAX_COINS = 60
local COIN_DIAMETER = 1.4
-- Pooled voices per take. The bell rings for half a second on three takes, so a burst (about 30 landings a second)
-- restarted bells still ringing at 2; the thump and clink are short and have many takes.
local BELL_VOICES_EACH = 5
local COIN_VOICES_EACH = 2
local TAU = 2 * math.pi
-- The mesh is a disc in its own XZ plane; this stands it on its rim so a turn about Y shows it edge-on and back.
local STAND = CFrame.Angles(math.pi / 2, 0, 0)
-- Aimed at the chest rather than the root, so it lands in the body instead of at the hips.
local BODY_TARGET_UP = Vector3.new(0, 1, 0)

-- The anime sprites (Assets/effects/anime, VFX.md 15).
local Sprites = table.freeze({
	FLARE = "rbxassetid://128750342796317",
	STREAK = "rbxassetid://75972998756629",
})

-- Measured against the map's floors (Assets/effects/anime/measure_contrast.py): amber at a quarter additive scores
-- 39 on sand and at least that everywhere, where the old gold at full additive scored 17 and vanished.
local Colors = table.freeze({
	AMBER = Color3.fromRGB(255, 150, 0),
	AMBER_DEEP = Color3.fromRGB(255, 110, 0),
	GOLD_LIGHT = Color3.fromRGB(255, 225, 150),
	WHITE = Color3.new(1, 1, 1),
	LIGHT = 0.25,
})

local Pop = table.freeze({
	LIFT = Vector3.new(0, 2, 0),
	UP_SPEED = 18,
	SIDE_SPEED = 11,
	-- Thrown over this arc AWAY from the taker: a pull needs somewhere to come home from.
	THROW_ARC = 3.5,
	-- The hangs end on gaps that close (first at HANG_FIRST, last HANG_SPREAD later), so a kill pays out as a
	-- rattle speeding up rather than one clack.
	HANG_FIRST = 0.3,
	HANG_SPREAD = 0.22,
	HANG_JITTER = 0.03,
	SPIN = 14,
	TILT = 0.25,
})

local Pull = table.freeze({
	-- Tumbles faster the faster it flies, so the speed-up reads on the coin itself as well as its trail.
	TUMBLE = 6,
	TUMBLE_PER_STUD = 0.25,
	-- A bought pack's coin flips as a popped one does while it hangs, and this many times as fast coming in.
	SHOWER_SPIN = 3,
})

local Effects = table.freeze({
	POP_STREAKS = 7,
	POP_FLASHES = 1,
	-- A run of landings this close together climbs in pitch, step by step up to the cap.
	CHAIN_GAP_SECONDS = 0.45,
	CHAIN_STEP = 0.01,
	CHAIN_MAX_STEPS = 14,
	-- A landed coin is hidden and kept this long, so its trail fades where it was instead of being cut off.
	RETIRE_SECONDS = 0.25,
})

type TCoin = {
	Part: BasePart,
	Wake: ParticleEmitter,
	Trails: { Trail },
	-- A kill's coin has a Flight; a bought pack's has a Shower, flown from Born (os.clock).
	Flight: CoinFlight.TFlight?,
	Shower: CoinFlight.TShower?,
	Born: number,
	Value: number,
	Turn: number,
	Rotation: CFrame,
}

type TRetired = {
	Part: BasePart,
	ReturnAt: number,
}

local CoinsController = {}

-- Gold already credited that is still in the air; the HUD shows Gold minus this.
CoinsController.PendingGold = 0

local coins: { TCoin } = {}
local retired: { TRetired } = {}
local selfRoot: BasePart? = nil
local random = Random.new()
local chainSteps = 0
local lastLandAt = -math.huge
-- Three layers that are one sound, each rolling its own take.
local coinPoolsBell = SoundsCore.CreateVariantPools("Coin", "Bell", BELL_VOICES_EACH)
local coinPoolsThump = SoundsCore.CreateVariantPools("Coin", "Thump", COIN_VOICES_EACH)
local coinPoolsClink = SoundsCore.CreateVariantPools("Coin", "Clink", COIN_VOICES_EACH)
-- Reused every frame for one BulkMoveTo of every coin.
local moveParts: { BasePart } = table.create(MAX_COINS)
local moveCFrames: { CFrame } = table.create(MAX_COINS)
-- Reused per kill: who lands when, shuffled apart from where it was thrown.
local hangOrder: { number } = table.create(COINS_PER_KILL)

local function newEmitter(texture: string): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = texture
	emitter.LightEmission = Colors.LIGHT
	emitter.LightInfluence = 0
	emitter.Brightness = 1.2
	emitter.Color = ColorSequence.new(Colors.GOLD_LIGHT, Colors.AMBER)
	emitter.Rate = 0
	emitter.Enabled = false
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.SpreadAngle = Vector2.new(180, 180)
	return emitter
end

-- FaceCamera keeps the ribbon flat to the view however the coin tumbles; its width is the attachments' distance.
local function newTrail(part: BasePart, name: string, width: number, lifetime: number): Trail
	local a0 = Instance.new("Attachment")
	a0.Name = name .. "0"
	a0.Position = Vector3.new(-width / 2, 0, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Name = name .. "1"
	a1.Position = Vector3.new(width / 2, 0, 0)
	a1.Parent = part

	local trail = Instance.new("Trail")
	trail.Name = name
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.FaceCamera = true
	trail.Lifetime = lifetime
	trail.MinLength = 0.05
	trail.LightInfluence = 0
	trail.Enabled = false
	trail.Parent = part
	return trail
end

-- The template is scaled once here, never a live coin: a MeshPart.Size write rebuilds its geometry.
local function buildTemplate(): BasePart
	local template: BasePart
	if CoinModel then
		template = CoinModel:Clone()
	else
		warn("[CoinsController] no ReplicatedStorage.Models.Coin; coins are plain discs")
		local disc = Instance.new("Part")
		disc.Shape = Enum.PartType.Cylinder
		disc.Size = Vector3.new(0.2, COIN_DIAMETER, COIN_DIAMETER)
		disc.Color = Color3.fromRGB(255, 200, 60)
		disc.Material = Enum.Material.Neon
		template = disc
	end

	template.Size = template.Size * (COIN_DIAMETER / math.max(template.Size.X, template.Size.Z))
	template.Anchored = true
	template.CanCollide = false
	template.CanQuery = false
	template.CanTouch = false
	template.CastShadow = false

	-- A white-hot core inside an amber glow: the core alone would vanish on the concrete, the glow alone is flat.
	local glow = newTrail(template, "Glow", 1.1, 0.2)
	glow.Color = ColorSequence.new(Colors.AMBER, Colors.AMBER_DEEP)
	glow.Transparency = NumberSequence.new(0.25, 1)
	glow.WidthScale = NumberSequence.new(1, 0.2)
	glow.LightEmission = Colors.LIGHT
	local core = newTrail(template, "Core", 0.35, 0.14)
	core.Color = ColorSequence.new(Colors.WHITE, Colors.GOLD_LIGHT)
	core.Transparency = NumberSequence.new(0, 1)
	core.WidthScale = NumberSequence.new(1, 0)
	core.LightEmission = 0.6

	-- Glints shed in world space, left hanging behind it as it goes.
	local wake = newEmitter(Sprites.FLARE)
	wake.Name = "Wake"
	wake.Rate = 18
	wake.Lifetime = NumberRange.new(0.25, 0.45)
	wake.Speed = NumberRange.new(0.3, 1)
	wake.Drag = 4
	wake.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(1, 0),
	})
	wake.Transparency = NumberSequence.new(0, 1)
	wake.Parent = template
	return template
end

local coinPool = ObjectPooler.new(buildTemplate(), 16, 8, ObjectPooler.ReturnCF, TemporalFolder)

-- One world-space anchor for the kill bursts: moved to the spot, emitted, moved on. Emitted particles stay where
-- they were born, so a frame can fire it at many places.
local burstAnchor = Instance.new("Attachment")
burstAnchor.Name = "CoinBursts"
burstAnchor.Parent = Workspace.Terrain

local streaks = newEmitter(Sprites.STREAK)
streaks.Orientation = Enum.ParticleOrientation.VelocityParallel
streaks.Rotation = NumberRange.new(0)
streaks.Lifetime = NumberRange.new(0.18, 0.3)
streaks.Speed = NumberRange.new(16, 28)
streaks.Drag = 6
streaks.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1.6),
	NumberSequenceKeypoint.new(1, 0),
})
streaks.Parent = burstAnchor

local flash = newEmitter(Sprites.FLARE)
flash.Lifetime = NumberRange.new(0.16)
flash.Speed = NumberRange.new(0)
flash.LightEmission = 0.6
flash.Color = ColorSequence.new(Colors.WHITE, Colors.AMBER)
flash.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1.5),
	NumberSequenceKeypoint.new(0.25, 3.2),
	NumberSequenceKeypoint.new(1, 0),
})
flash.Transparency = NumberSequence.new(0, 1)
flash.Parent = burstAnchor

local function setTrails(coin: TCoin, isEnabled: boolean)
	for _, trail in coin.Trails do
		trail.Enabled = isEnabled
	end
end

-- A coin at `at` carrying `value` Gold, for its caller to give a Flight or a Shower; nil at the cap, when its Gold
-- is never held back and the counter takes it at once.
local function newCoin(at: Vector3, value: number): TCoin?
	if #coins >= MAX_COINS then return nil end

	local part = coinPool:Get()
	part.CFrame = CFrame.new(at) * STAND
	local coin: TCoin = {
		Part = part,
		Wake = part:FindFirstChild("Wake") :: ParticleEmitter,
		Trails = { part:FindFirstChild("Glow") :: Trail, part:FindFirstChild("Core") :: Trail },
		Flight = nil,
		Shower = nil,
		Born = 0,
		Value = value,
		Turn = random:NextNumber(0, TAU),
		Rotation = CFrame.identity,
	}
	-- Switched on only once placed: on at the parking spot, the trails would draw a ribbon from there.
	for _, trail in coin.Trails do
		trail:Clear()
	end
	setTrails(coin, true)
	coin.Wake.Enabled = true
	coins[#coins + 1] = coin
	CoinsController.PendingGold += value
	return coin
end

-- Hidden where it landed and kept a trail's lifetime before it goes back to the pool.
local function retireCoin(index: number, now: number)
	local coin = coins[index]
	setTrails(coin, false)
	coin.Wake.Enabled = false
	coin.Part.Transparency = 1
	retired[#retired + 1] = { Part = coin.Part, ReturnAt = now + Effects.RETIRE_SECONDS }
	CoinsController.PendingGold -= coin.Value

	local last = #coins
	coins[index] = coins[last]
	coins[last] = nil
end

local function returnRetired(now: number)
	for i = #retired, 1, -1 do
		local entry = retired[i]
		if now < entry.ReturnAt then continue end
		entry.Part.Transparency = 0
		coinPool:Return(entry.Part)
		retired[i] = retired[#retired]
		retired[#retired] = nil
	end
end

-- With nobody to fly to, every coin is in at once: the Gold is his either way.
local function landAll(now: number)
	for i = #coins, 1, -1 do
		retireCoin(i, now)
	end

	CoinsController.PendingGold = 0
end

-- One sound a frame however many landed in it, and one pitch step a sound.
local function onLanded(target: Vector3, now: number)
	chainSteps = if now - lastLandAt < Effects.CHAIN_GAP_SECONDS
		then math.min(chainSteps + 1, Effects.CHAIN_MAX_STEPS)
		else 0
	lastLandAt = now
	local pitch = 1 + chainSteps * Effects.CHAIN_STEP
	SoundsCore.PlayPooledRandom(coinPoolsBell, target, pitch)
	SoundsCore.PlayPooledRandom(coinPoolsThump, target, pitch)
	SoundsCore.PlayPooledRandom(coinPoolsClink, target, pitch)
end

local function update(dt: number)
	local now = os.clock()
	if #retired > 0 then returnRetired(now) end
	if #coins == 0 then return end
	local root = selfRoot
	if not root then
		landAll(now)
		return
	end

	local target = root.Position + BODY_TARGET_UP
	local step = CoinFlight.Step
	local showerAt = CoinFlight.ShowerAt
	local arrived = 0
	local moved = 0

	table.clear(moveParts)
	table.clear(moveCFrames)
	for i = #coins, 1, -1 do
		local coin = coins[i]
		local shower = coin.Shower
		if shower then
			local age = now - coin.Born
			if age >= shower.LandAt then
				arrived += 1
				retireCoin(i, now)
				continue
			end

			coin.Turn += Pop.SPIN * (if age < shower.HangAt then 1 else Pull.SHOWER_SPIN) * dt
			moved += 1
			moveParts[moved] = coin.Part
			moveCFrames[moved] = CFrame.new(target + showerAt(shower, age))
				* CFrame.Angles(0, coin.Turn, Pop.TILT)
				* STAND
			continue
		end

		local flight = coin.Flight :: CoinFlight.TFlight
		local wasPulling = flight.IsPulling
		if step(flight, target, dt) then
			arrived += 1
			retireCoin(i, now)
			continue
		end

		local cframe: CFrame
		if not flight.IsPulling then
			-- The pop: flipped edge-on and back like a tossed coin.
			coin.Turn += Pop.SPIN * dt
			cframe = CFrame.new(flight.Position) * CFrame.Angles(0, coin.Turn, Pop.TILT) * STAND
		else
			-- The pull starts turned as the pop left it, so the hand-over has no jump.
			if not wasPulling then
				coin.Rotation = CFrame.Angles(0, coin.Turn, Pop.TILT) * STAND
				coin.Turn = 0
			end
			coin.Turn += (Pull.TUMBLE + flight.Velocity.Magnitude * Pull.TUMBLE_PER_STUD) * dt
			local turn = coin.Turn
			cframe = CFrame.new(flight.Position) * CFrame.Angles(turn, turn * 0.7, 0) * coin.Rotation
		end

		moved += 1
		moveParts[moved] = coin.Part
		moveCFrames[moved] = cframe
	end

	if moved > 0 then Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged) end

	if arrived == 0 then return end
	onLanded(target, now)
end

MatchController.OnCoins:Connect(function(position: Vector3, amount: number)
	local at = position + Pop.LIFT
	local count = math.clamp(amount, 1, COINS_PER_KILL)
	local share = amount // count
	local remainder = amount - share * count
	local root = selfRoot
	local toward = if root then root.Position - position else Vector3.zero
	toward = Vector3.new(toward.X, 0, toward.Z)
	-- Fanned over the side away from him; round the whole circle when he stands on the kill.
	local arc = if toward.Magnitude > 1 then Pop.THROW_ARC else TAU
	local center = if toward.Magnitude > 1 then math.atan2(-toward.Z, -toward.X) else random:NextNumber(0, TAU)

	table.clear(hangOrder)
	for i = 1, count do
		hangOrder[i] = i
	end
	for i = count, 2, -1 do
		local j = random:NextInteger(1, i)
		hangOrder[i], hangOrder[j] = hangOrder[j], hangOrder[i]
	end

	for i = 1, count do
		local value = share + (if i <= remainder then 1 else 0)
		local angle = center + ((i - 0.5) / count - 0.5 + random:NextNumber(-0.12, 0.12) / count) * arc
		local side = random:NextNumber(0.7, 1) * Pop.SIDE_SPEED
		local velocity =
			Vector3.new(math.cos(angle) * side, random:NextNumber(0.9, 1.1) * Pop.UP_SPEED, math.sin(angle) * side)
		local order = if count > 1 then (hangOrder[i] - 1) / (count - 1) else 0
		local hang = Pop.HANG_FIRST + Pop.HANG_SPREAD * order ^ 0.8 + random:NextNumber(-1, 1) * Pop.HANG_JITTER
		local coin = newCoin(at, value)
		if coin then coin.Flight = CoinFlight.New(at, velocity, hang) end
	end

	burstAnchor.Position = at
	streaks:Emit(Effects.POP_STREAKS)
	flash:Emit(Effects.POP_FLASHES)
end)

-- The buyer's own pack: its Gold thrown out of him all round and pulled back in, each coin landing on its beat. With
-- no body to throw them from, the counter takes the Gold at once.
MatchController.OnGoldBought:Connect(function(buyer: Player, amount: number)
	local root = selfRoot
	if buyer ~= LocalPlayer or not root then return end

	local showers = CoinFlight.ThrowShower(amount, random)
	local count = #showers
	local share = amount // count
	local remainder = amount - share * count
	local at = root.Position + BODY_TARGET_UP
	local now = os.clock()
	for i, shower in showers do
		local coin = newCoin(at, share + (if i <= remainder then 1 else 0))
		if not coin then break end
		coin.Shower = shower
		coin.Born = now
	end
end)

CoinsController.OnStart = function()
	RunService.PreRender:Connect(update)
end

CoinsController.OnSelfCharacterAdded = function(character: TCharacter.TCharacter)
	selfRoot = character.HumanoidRootPart
end :: TCharacterEvents.OnCharacterAdded

CoinsController.OnSelfCharacterRemoving = function()
	selfRoot = nil
end :: TCharacterEvents.OnCharacterRemoving

return Ignis.Register(CoinsController)
