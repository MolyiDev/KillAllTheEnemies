-- The Orbital Cannon as it is seen, in the house look (VFX.md 30 and 37). Four beats: the mark (a red pixel on the
-- floor under a thin line to the sky, a square ring closing onto it), the slam (a fat white-core square beam landing
-- at its widest and whitest, a square shock, a pillar of pixels up it, the floor's own bricks thrown out), the burn
-- (the beam dragged across the floor on a fountain of pixels, leaving glowing embers behind it), and the end (it
-- thins to a line and goes). The beam is square, as every ring here is, and stands to the sky, so the whole squad
-- sees it from anywhere.
-- AbilityController says where each beam is and steps it. The look is on templates at
-- ReplicatedStorage.Effects.HumanFx, a place instance, not Rojo, made by Assets/effects/abilities (its README.md).
-- No --!native: this is engine calls end to end.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local motorParts = require(script.Parent.Parent.Parent.GlobalClient.Utils.motorParts)
local thrownPieces = require(script.Parent.Parent.Parent.GlobalClient.Utils.thrownPieces)
local burstLayers = require(script.Parent.burstLayers)
local sightCast = require(ReplicatedStorage.GlobalShared.Utils.sightCast)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)

local orbitalFx = {}

type TLayers = burstLayers.TLayers

local layersOf = burstLayers.Clone
local emit = burstLayers.Emit
local roll = burstLayers.Roll
local between = burstLayers.Between

local KIT = "HumanFx"

local Tune = table.freeze({
	-- Beams drawn at once: one a caster, and a squad is few.
	BEAMS = 4,
	-- How tall the beam stands, and how far under the floor it starts so no gap shows on a slope.
	HEIGHT = 700,
	SINK = 1,
	-- The floor under the beam is looked for from this far over it to this far under.
	FLOOR_LOOK_UP = 6,
	FLOOR_SEARCH = 40,
	LIFT = 0.08,
	-- The floor is looked up again once the beam has moved this far: a ray a frame for a beam standing still is wasted.
	FLOOR_RECAST = 0.5,
	-- Another caster's beam eases toward where the server last said it was at this rate (per second, exponential):
	-- the updates come ten times a second.
	FOLLOW_RATE = 12,
	-- The mark: the line to the sky this wide as it is called and this wide as the beam is about to land, the pixel
	-- on the floor breathing this much at this rate, a closing ring this often and pixels up the line this many a
	-- second.
	GUIDE_WIDTH = 0.22,
	GUIDE_WIDTH_END = 0.9,
	DOT_PULSE = 0.25,
	DOT_RATE = 14,
	RETICLE_SECONDS = 0.25,
	SIGNAL_RATE = 26,
	-- The beam: its white core and the red round it, studs across. It lands SLAM_WIDTH times as wide and is down to
	-- size in SLAM_SECONDS; burning, its width shivers by FLICKER at two rates that never line up.
	CORE_WIDTH = 4.2,
	SHELL_WIDTH = 7.4,
	SLAM_WIDTH = 2.3,
	SLAM_SECONDS = 0.2,
	FLICKER = 0.07,
	FLICKER_RATE = 47,
	FLICKER_RATE_SLOW = 31,
	-- What the slam throws, a layer (an emitter has no burst count).
	SLAM_PILLAR = NumberRange.new(30, 36),
	SLAM_PIXELS = NumberRange.new(34, 42),
	SLAM_FLECKS = NumberRange.new(16, 22),
	SLAM_PUFFS = NumberRange.new(10, 13),
	SLAM_BRICKS = NumberRange.new(10, 14),
	-- What the burn throws, a second: counted against the frame's length, so it is the same at any frame rate.
	FLASH_RATE = 26,
	SPARKS_RATE = 150,
	RISE_RATE = 60,
	FLECKS_RATE = 34,
	PUFFS_RATE = 9,
	BRICKS_RATE = 12,
	RING_SECONDS = 0.2,
	-- An ember is left on the floor every this many studs the beam is dragged, and when it stands still this often.
	EMBER_SPACING = 1.8,
	EMBER_SECONDS = 0.5,
	-- A brick the beam tears out is thrown this fast across the floor and up, from this far off its middle.
	BRICK_OUT = NumberRange.new(6, 18),
	BRICK_LIFT = NumberRange.new(14, 30),
	BRICK_SPREAD = 4,
	PIECE_PARTS = 64,
	-- Its end: thins to END_WIDTH of its size over this long, slowly then all at once.
	END_SECONDS = 0.4,
	END_WIDTH = 0.03,
	END_MOTES = NumberRange.new(14, 18),
	END_PUFFS = NumberRange.new(5, 7),
	-- The light it throws on the world, only when it is this near the camera: at its brightest as it lands.
	LIGHT_COLOR = Color3.fromRGB(255, 120, 90),
	LIGHT_RANGE = 46,
	LIGHT_BRIGHTNESS = 4,
	LIGHT_SLAM_BRIGHTNESS = 10,
	LIGHT_REACH = 170,
	-- Past this from the camera the floor's bursts are not thrown; the beam itself always stands.
	RANGE = 260,
})

-- One beam's instances, made the first time its slot is used and kept: its parts (motorParts movers, parked when
-- free), its bursts under Workspace.Terrain (where an attachment's CFrame is its world CFrame) and its light.
type TSlot = {
	Core: motorParts.TMover,
	Shell: motorParts.TMover,
	Guide: motorParts.TMover,
	Dot: motorParts.TMover,
	Target: TLayers,
	Slam: TLayers,
	Burn: TLayers,
	End: TLayers,
	Light: PointLight,
}

type TBeam = {
	Slot: number,
	-- Where it is drawn on the floor, and where it is headed.
	Position: Vector3,
	Goal: Vector3,
	CalledAt: number,
	FireAt: number,
	EndsAt: number,
	-- GameClock it started to thin out, or 0 while it burns.
	EndedAt: number,
	HasFired: boolean,
	NextReticleAt: number,
	NextRingAt: number,
	NextEmberAt: number,
	LastEmber: Vector3,
	-- What each steady layer is owed, carried between frames.
	Owed: { [string]: number },
	-- The floor as last looked up, and where from: it is looked up again once the beam has moved FLOOR_RECAST.
	Ground: Vector3,
	Floor: BasePart?,
	CastAt: Vector3?,
	-- What its light was last given.
	Brightness: number,
}

local random = Random.new()
local pieces = thrownPieces.NewPool("OrbitalPieces", Tune.PIECE_PARTS)
pieces.Landed = thrownPieces.BrickLanded
local parts = motorParts.NewPool("OrbitalBeams", Tune.BEAMS * 4)
local templates: Instance? = nil
local bricks: { BasePart } = {}
local hasWarned = false
local slots: { TSlot } = {}
local slotUsers: { [number]: number } = {}
local beams: { [number]: TBeam } = {}

-- The kit's templates; nil (said once) while they are not in the place, when the cannon draws nothing. A miss is
-- asked again, so templates that reach the client late are still found.
local function templatesOf(): Instance?
	if templates then return templates end

	local effects = ReplicatedStorage:FindFirstChild("Effects")
	local found = if effects then effects:FindFirstChild(KIT) else nil
	if not found or not found:FindFirstChild("Orbital") or not found:FindFirstChild("OrbitalSlam") then
		if not hasWarned then
			hasWarned = true
			warn(`[orbitalFx] no ReplicatedStorage.Effects.{KIT}; the orbital cannon draws nothing`)
		end
		return nil
	end

	local debris = found:FindFirstChild("Debris")
	if debris then
		for _, child in debris:GetChildren() do
			if child:IsA("BasePart") then bricks[#bricks + 1] = child end
		end
	end

	templates = found
	return found
end

local function buildSlot(found: Instance): TSlot?
	local folder = found:FindFirstChild("Orbital")
	local function mover(name: string): motorParts.TMover?
		local template = if folder then folder:FindFirstChild(name) else nil
		return if template and template:IsA("BasePart") then motorParts.Take(parts, template) else nil
	end

	local core, shell, guide, dot = mover("Core"), mover("Shell"), mover("Guide"), mover("Dot")
	local target = layersOf(found:FindFirstChild("OrbitalTarget"))
	local slam = layersOf(found:FindFirstChild("OrbitalSlam"))
	local burn = layersOf(found:FindFirstChild("OrbitalBurn"))
	local ending = layersOf(found:FindFirstChild("OrbitalEnd"))
	if not core or not shell or not guide or not dot or not target or not slam or not burn or not ending then
		return nil
	end

	local light = Instance.new("PointLight")
	light.Name = "OrbitalFxLight"
	light.Color = Tune.LIGHT_COLOR
	light.Range = Tune.LIGHT_RANGE
	light.Shadows = false
	light.Enabled = false
	light.Parent = burn.Attachment
	return {
		Core = core,
		Shell = shell,
		Guide = guide,
		Dot = dot,
		Target = target,
		Slam = slam,
		Burn = burn,
		End = ending,
		Light = light,
	}
end

-- A free slot's index and instances, or nothing when every one is burning (the beam is then not drawn).
local function takeSlot(key: number): (number?, TSlot?)
	local found = templatesOf()
	if not found then return nil, nil end

	for index = 1, Tune.BEAMS do
		if slotUsers[index] then continue end
		local slot = slots[index]
		if not slot then
			slot = buildSlot(found) :: TSlot
			if not slot then return nil, nil end
			slots[index] = slot
		end
		slotUsers[index] = key
		return index, slot
	end

	return nil, nil
end

-- How many of a layer thrown `rate` a second this frame owes, the remainder carried to the next.
local function owed(beam: TBeam, layer: string, rate: number, dt: number): number
	local total = (beam.Owed[layer] or 0) + rate * dt
	local count = math.floor(total)
	beam.Owed[layer] = total - count
	return count
end

-- The floor under `position` and the part it is, or `position` itself over nothing.
local function floorUnder(position: Vector3): (Vector3, BasePart?)
	local result = sightCast(position + Vector3.new(0, Tune.FLOOR_LOOK_UP, 0), Vector3.new(0, -Tune.FLOOR_SEARCH, 0))
	if not result then return position, nil end
	return result.Position, result.Instance :: BasePart
end

-- Stands a column `width` across on `ground`, up to the sky.
local function column(mover: motorParts.TMover, ground: Vector3, width: number)
	local mesh = mover.Mesh
	if mesh then mesh.Scale = Vector3.new(width, Tune.HEIGHT, width) end
	mover.Joint.Transform = CFrame.new(ground.X, ground.Y - Tune.SINK + Tune.HEIGHT / 2, ground.Z)
end

local function park(mover: motorParts.TMover)
	mover.Joint.Transform = motorParts.PARK
end

local function throwBricks(ground: Vector3, floor: BasePart?, count: number, distance: number)
	if not floor or #bricks == 0 then return end
	for _ = 1, thrownPieces.Allowed(pieces, count, distance) do
		local turn = random:NextNumber(0, math.pi * 2)
		local out = Vector3.new(math.cos(turn), 0, math.sin(turn))
		thrownPieces.Throw(
			pieces,
			bricks[random:NextInteger(1, #bricks)],
			floor.Color,
			ground + out * random:NextNumber(0, Tune.BRICK_SPREAD) + Vector3.new(0, 0.6, 0),
			out * between(Tune.BRICK_OUT) + Vector3.new(0, between(Tune.BRICK_LIFT), 0),
			ground.Y
		)
	end
end

-- An orbital cannon was called: `key` names it (its caster's character id), the mark is at `position` on the floor,
-- the beam lands in `targetSeconds` and then burns for `burnSeconds`.
function orbitalFx.Call(key: number, position: Vector3, targetSeconds: number, burnSeconds: number)
	if beams[key] then orbitalFx.Remove(key) end
	local index = takeSlot(key)
	if not index then return end

	local now = TimeCore.GameClock
	beams[key] = {
		Slot = index,
		Position = position,
		Goal = position,
		CalledAt = now,
		FireAt = now + targetSeconds,
		EndsAt = now + targetSeconds + burnSeconds,
		EndedAt = 0,
		HasFired = false,
		NextReticleAt = 0,
		NextRingAt = 0,
		NextEmberAt = 0,
		LastEmber = position,
		Owed = {},
		Ground = position,
		Floor = nil,
		CastAt = nil,
		Brightness = -1,
	}
end

-- Where the beam is, by the server's word ten times a second: it eases there.
function orbitalFx.Aim(key: number, position: Vector3)
	local beam = beams[key]
	if not beam then return end
	beam.Goal = position
end

-- The point on the floor a beam is drawn at, or nil for none.
function orbitalFx.GroundOf(key: number): Vector3?
	local beam = beams[key]
	return if beam then beam.Position else nil
end

-- Whether a beam has landed and is still burning.
function orbitalFx.IsBurning(key: number): boolean
	local beam = beams[key]
	return beam ~= nil and beam.HasFired and beam.EndedAt == 0
end

-- The beam is over: it thins out and goes. One that never landed just goes.
function orbitalFx.End(key: number)
	local beam = beams[key]
	if not beam or beam.EndedAt > 0 then return end
	if not beam.HasFired then
		orbitalFx.Remove(key)
		return
	end

	beam.EndedAt = TimeCore.GameClock
	local slot = slots[beam.Slot]
	local ground = floorUnder(beam.Position)
	slot.End.Attachment.CFrame = CFrame.new(ground + Vector3.new(0, Tune.LIFT, 0))
	emit(slot.End, "Frame", 1)
	emit(slot.End, "Motes", roll(Tune.END_MOTES))
	emit(slot.End, "Puffs", roll(Tune.END_PUFFS))
end

-- Takes a beam down at once and frees its slot.
function orbitalFx.Remove(key: number)
	local beam = beams[key]
	if not beam then return end
	beams[key] = nil
	slotUsers[beam.Slot] = nil
	local slot = slots[beam.Slot]
	park(slot.Core)
	park(slot.Shell)
	park(slot.Guide)
	park(slot.Dot)
	slot.Light.Enabled = false
end

-- The mark, until the beam lands: the pixel on the floor, the line to the sky fattening as the moment nears, a ring
-- closing onto it every beat and pixels climbing the line.
local function stepMark(beam: TBeam, slot: TSlot, ground: Vector3, now: number, dt: number)
	local share = math.clamp((now - beam.CalledAt) / math.max(beam.FireAt - beam.CalledAt, 1e-3), 0, 1)
	local pulse = 1 + Tune.DOT_PULSE * math.sin(now * Tune.DOT_RATE)
	local dot = slot.Dot
	dot.Joint.Transform = CFrame.new(ground + Vector3.new(0, dot.Size.Y / 2, 0)) * CFrame.Angles(0, now * 3, 0)
	column(slot.Guide, ground, (Tune.GUIDE_WIDTH + (Tune.GUIDE_WIDTH_END - Tune.GUIDE_WIDTH) * share * share) * pulse)

	local target = slot.Target
	target.Attachment.CFrame = CFrame.new(ground + Vector3.new(0, Tune.LIFT, 0))
	emit(target, "Signal", owed(beam, "Signal", Tune.SIGNAL_RATE, dt))
	if now < beam.NextReticleAt then return end
	beam.NextReticleAt = now + Tune.RETICLE_SECONDS
	emit(target, "Reticle", 1)
end

-- The frame the beam lands: everything at its biggest and whitest, and the floor's bricks thrown out round it.
local function slam(beam: TBeam, slot: TSlot, ground: Vector3, floor: BasePart?, distance: number)
	beam.HasFired = true
	beam.LastEmber = ground
	park(slot.Guide)
	park(slot.Dot)

	local layers = slot.Slam
	layers.Attachment.CFrame = CFrame.new(ground + Vector3.new(0, Tune.LIFT, 0))
	emit(layers, "Wash", 1)
	emit(layers, "Bloom", 1)
	emit(layers, "Core", 1)
	emit(layers, "Shock", 1)
	emit(layers, "Echo", 1)
	emit(layers, "Pillar", roll(Tune.SLAM_PILLAR))
	emit(layers, "Pixels", roll(Tune.SLAM_PIXELS))
	emit(layers, "Flecks", roll(Tune.SLAM_FLECKS))
	emit(layers, "Puffs", roll(Tune.SLAM_PUFFS))
	emit(slot.Burn, "Ember", 1)
	throwBricks(ground, floor, roll(Tune.SLAM_BRICKS), distance)
end

-- The burn under the beam this frame: a lick of light, the fountain, pixels up the beam, the floor's bricks, a ring
-- every beat, and an ember left behind every few studs.
local function burn(
	beam: TBeam,
	slot: TSlot,
	ground: Vector3,
	floor: BasePart?,
	distance: number,
	now: number,
	dt: number
)
	local layers = slot.Burn
	emit(layers, "Flash", owed(beam, "Flash", Tune.FLASH_RATE, dt))
	emit(layers, "Sparks", owed(beam, "Sparks", Tune.SPARKS_RATE, dt))
	emit(layers, "Rise", owed(beam, "Rise", Tune.RISE_RATE, dt))
	emit(layers, "Flecks", owed(beam, "Flecks", Tune.FLECKS_RATE, dt))
	emit(layers, "Puffs", owed(beam, "Puffs", Tune.PUFFS_RATE, dt))
	throwBricks(ground, floor, owed(beam, "Bricks", Tune.BRICKS_RATE, dt), distance)

	if now >= beam.NextRingAt then
		beam.NextRingAt = now + Tune.RING_SECONDS
		emit(layers, "Ring", 1)
	end

	local dragged = ground - beam.LastEmber
	if dragged.Magnitude < Tune.EMBER_SPACING and now < beam.NextEmberAt then return end
	beam.LastEmber = ground
	beam.NextEmberAt = now + Tune.EMBER_SECONDS
	emit(layers, "Ember", 1)
end

local function stepBeam(key: number, beam: TBeam, now: number, dt: number, cameraPosition: Vector3)
	local slot = slots[beam.Slot]
	beam.Position = beam.Position:Lerp(beam.Goal, 1 - math.exp(-Tune.FOLLOW_RATE * dt))
	local castAt = beam.CastAt
	if not castAt or (beam.Position - castAt).Magnitude >= Tune.FLOOR_RECAST then
		beam.CastAt = beam.Position
		beam.Ground, beam.Floor = floorUnder(beam.Position)
	end
	-- The beam stands where it is drawn; only the floor's height and part are the last look's.
	local ground, floor = Vector3.new(beam.Position.X, beam.Ground.Y, beam.Position.Z), beam.Floor
	local distance = (cameraPosition - ground).Magnitude
	if now < beam.FireAt and beam.EndedAt == 0 then
		stepMark(beam, slot, ground, now, dt)
		return
	end

	local light = slot.Light
	slot.Burn.Attachment.CFrame = CFrame.new(ground + Vector3.new(0, Tune.LIFT, 0))
	if not beam.HasFired then
		slam(beam, slot, ground, floor, distance)
		light.Enabled = distance <= Tune.LIGHT_REACH
	end

	-- Wide as it lands and down to size at once, shivering while it burns, thinning to a line as it ends.
	local sinceFire = now - beam.FireAt
	local landing = math.exp(-sinceFire / Tune.SLAM_SECONDS * 4)
	local width = 1
		+ (Tune.SLAM_WIDTH - 1) * landing
		+ Tune.FLICKER * (math.sin(now * Tune.FLICKER_RATE) + 0.6 * math.sin(now * Tune.FLICKER_RATE_SLOW))
	local brightness = Tune.LIGHT_BRIGHTNESS + (Tune.LIGHT_SLAM_BRIGHTNESS - Tune.LIGHT_BRIGHTNESS) * landing
	if beam.EndedAt > 0 then
		local t = (now - beam.EndedAt) / Tune.END_SECONDS
		if t >= 1 then
			orbitalFx.Remove(key)
			return
		end
		local left = 1 - t * t * t
		width *= Tune.END_WIDTH + (1 - Tune.END_WIDTH) * left
		brightness *= left
	elseif now >= beam.EndsAt then
		orbitalFx.End(key)
	elseif distance <= Tune.RANGE then
		burn(beam, slot, ground, floor, distance, now, dt)
	end

	column(slot.Core, ground, Tune.CORE_WIDTH * width)
	column(slot.Shell, ground, Tune.SHELL_WIDTH * width)
	-- Rounded, so the light is written while it changes (landing, ending) and not once it has settled.
	brightness = math.round(brightness * 20) / 20
	if brightness == beam.Brightness then return end
	beam.Brightness = brightness
	light.Brightness = brightness
end

-- Once a frame: every beam, and the bricks in the air.
function orbitalFx.Step(dt: number)
	thrownPieces.Step(pieces, TimeCore.TimeScale)
	if not next(beams) then return end

	local now = TimeCore.GameClock
	local cameraPosition = Workspace.CurrentCamera.CFrame.Position
	for key, beam in beams do
		stepBeam(key, beam, now, dt, cameraPosition)
	end
end

return orbitalFx
