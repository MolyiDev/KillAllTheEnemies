-- The raycast for anything that stands for sight: aim, shots, line of sight, and where an effect lands. It passes
-- through every part nobody can see (Transparency 1: the Blockers and Caps players collide with, trunk boxes, emitter
-- holders, invisible water, spawn pads), so nothing is aimed at, hit or landed on in thin air. Every such ray goes
-- through here; a raw Workspace:Raycast at the arena finds the invisible walls.
local Workspace = game:GetService("Workspace")

-- A ray that starts inside a part does not hit it, so an invisible part is passed by casting again from just inside.
local STEP_IN = 0.01
-- A ray across the map can cross a cap over every roof and tree it passes.
local MAX_PASSES = 16

local arenaParams = RaycastParams.new()
arenaParams.FilterType = Enum.RaycastFilterType.Include
local paramsArena: Instance? = nil

local function getArenaParams(): RaycastParams?
	local arena = Workspace:FindFirstChild("Arena")
	if arena ~= paramsArena then
		paramsArena = arena
		arenaParams.FilterDescendantsInstances = if arena then { arena } else {}
	end

	return if arena then arenaParams else nil
end

-- The first visible part along `direction` (its full length) and how far from `origin` it is, or nil and the full
-- length. `params` defaults to Workspace.Arena; with no arena nothing is in the way.
local function sightCast(origin: Vector3, direction: Vector3, params: RaycastParams?): (RaycastResult?, number)
	local length = direction.Magnitude
	local castParams = params or getArenaParams()
	if not castParams or length == 0 then return nil, length end

	local unit = direction / length
	local travelled = 0
	for _ = 1, MAX_PASSES do
		local result = Workspace:Raycast(origin + unit * travelled, unit * (length - travelled), castParams)
		if not result then return nil, length end
		if result.Instance.Transparency < 1 then return result, travelled + result.Distance end
		travelled += result.Distance + STEP_IN
		if travelled >= length then return nil, length end
	end

	return nil, length
end

return sightCast
