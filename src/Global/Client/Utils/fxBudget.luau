-- Every burst of particles goes through Emit, so the screen's particles cost what this client can draw rather than what
-- four players and a crowd ask for: the count is scaled by the graphics tier, thinned with distance from the camera's
-- focus (none behind the camera or past the cull), and spent from one estimate of the burst particles alive, past
-- which a burst is thinned, never dropped. Emitters with a Rate do not pass through here. Ground warnings do not
-- either: a warning is the hitbox, and a thinned one would lie about where it hits.
local Workspace = game:GetService("Workspace")
local GraphicsQualityController = require(script.Parent.Parent.Controllers.GraphicsQualityController)

local fxBudget = {}

-- By tier (GraphicsQualityController.LOW / MEDIUM / HIGH). Share: of each burst. Budget: burst particles alive at once,
-- a starting point not yet measured on a phone (unofficial mobile guides put a phone's comfortable ceiling at ~150-300
-- live). The follow camera sits ~40-60 studs off the player: past FarStuds from its focus a burst is at a screen's edge
-- or off it and throws FarShare of its particles; past CullStuds nothing.
local BY_TIER = table.freeze({
	table.freeze({ Share = 0.35, Budget = 180, FarStuds = 50, FarShare = 0.35, CullStuds = 120 }),
	table.freeze({ Share = 0.6, Budget = 300, FarStuds = 70, FarShare = 0.5, CullStuds = 170 }),
	table.freeze({ Share = 1, Budget = 700, FarStuds = 90, FarShare = 0.5, CullStuds = 220 }),
})
-- A point behind the camera's plane and this far from the focus is not on screen.
local BEHIND_STUDS = 40
-- About a burst particle's life: what was emitted is taken to die away over this.
local LIFETIME_SECONDS = 0.6

local alive = 0
local aliveAt = 0
local random = Random.new()

-- 1 draw it all, below 1 thin it, 0 skip it: where `at` is from the camera.
local function distanceShare(tune: typeof(BY_TIER[1]), at: Vector3): number
	local camera = Workspace.CurrentCamera
	if not camera then return 1 end
	local distance = (camera.Focus.Position - at).Magnitude
	if distance > tune.CullStuds then return 0 end
	local view = camera.CFrame
	if distance > BEHIND_STUDS and (at - view.Position):Dot(view.LookVector) < 0 then return 0 end
	if distance > tune.FarStuds then return tune.FarShare end
	return 1
end

-- The estimate of burst particles alive now, the one the budget is spent from (the debug readout's).
function fxBudget.Alive(): number
	return alive * math.exp((aliveAt - os.clock()) / LIFETIME_SECONDS)
end

-- emitter:Emit(count) as much as this client can afford. `at`, where it is drawn, defaults to the emitter's parent. A
-- burst of one or two (a flash, a core: the moment itself) still draws one while it is on screen, whatever the tier
-- and the budget; only its distance can take it away.
function fxBudget.Emit(emitter: ParticleEmitter, count: number, at: Vector3?)
	local tune = BY_TIER[GraphicsQualityController.Tier()]
	local where = at
	if not where then
		local parent = emitter.Parent
		where = if parent and parent:IsA("Attachment")
			then parent.WorldPosition
			elseif parent and parent:IsA("BasePart") then parent.Position
			else nil
	end
	local share = if where then distanceShare(tune, where) else 1
	if share <= 0 then return end
	local scaled = count * tune.Share * share

	local now = os.clock()
	alive *= math.exp((aliveAt - now) / LIFETIME_SECONDS)
	aliveAt = now
	-- What fits is drawn whole; the rest is thinned harder the further over the budget it would go (squared, so a
	-- steady stream settles near twice the budget rather than running away).
	local budget = tune.Budget
	local room = math.max(budget - alive, 0)
	if scaled > room then scaled = room + (scaled - room) * (budget / (alive + scaled)) ^ 2 end

	-- Rounded up by chance, so a single-particle burst still fires in proportion instead of snapping to nothing.
	local whole = math.floor(scaled)
	if random:NextNumber() < scaled - whole then
		whole += 1
	end
	if count <= 2 then whole = math.max(whole, 1) end
	if whole < 1 then return end
	alive += whole
	emitter:Emit(whole)
end

return fxBudget
