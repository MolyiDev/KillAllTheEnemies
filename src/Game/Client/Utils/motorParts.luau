-- Pooled effect parts, each on its own Motor6D off an anchored base at the origin, so the joint's Transform IS the
-- part's world CFrame. The assembly is anchored: the engine never simulates it, the owner moves it by writing
-- `mover.Joint.Transform` (cheaper to draw than anchored parts written by CFrame or billboards: performance/01). A free
-- part is parked far away, never faded (performance/README, decision 3), and a stretch goes through its SpecialMesh's
-- Scale, never the part's Size (performance/07).
local Workspace = game:GetService("Workspace")

local motorParts = {}

motorParts.PARK = CFrame.new(0, 100000, 0)

-- Size is the part's own and Width its mesh's authored Scale.X, both read once here: a property read is an engine
-- call, and the owner asks every time it takes one.
export type TMover = {
	Part: BasePart,
	Joint: Motor6D,
	Mesh: SpecialMesh?,
	Size: Vector3,
	Width: number,
	Template: BasePart,
}
export type TPool = { Folder: Folder?, Name: string, Free: { [BasePart]: { TMover } }, Count: number, Limit: number }

-- A pool of at most `limit` parts, built on first use under a Folder `name` in Workspace.
function motorParts.NewPool(name: string, limit: number): TPool
	return { Folder = nil, Name = name, Free = {}, Count = 0, Limit = limit }
end

local function build(pool: TPool, template: BasePart): TMover
	local folder = pool.Folder
	if not folder then
		local made = Instance.new("Folder")
		made.Name = pool.Name
		made.Parent = Workspace
		pool.Folder = made
		folder = made
	end

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Anchored = true
	base.CanCollide = false
	base.CanQuery = false
	base.CanTouch = false
	base.CastShadow = false
	base.Transparency = 1
	base.Size = Vector3.one
	base.CFrame = CFrame.identity
	local part = template:Clone()
	part.Anchored = false
	part.Parent = base
	local joint = Instance.new("Motor6D")
	joint.Part0 = base
	joint.Part1 = part
	joint.Transform = motorParts.PARK
	joint.Parent = base
	base.Parent = folder

	local mesh = part:FindFirstChildOfClass("SpecialMesh")
	return {
		Part = part,
		Joint = joint,
		Mesh = mesh,
		Size = part.Size,
		Width = if mesh then mesh.Scale.X else 0,
		Template = template,
	}
end

-- A copy of `template`, parked; nil once the pool's limit is out, so past it the piece is simply not drawn.
function motorParts.Take(pool: TPool, template: BasePart): TMover?
	local free = pool.Free[template]
	local pooled = if free then table.remove(free) else nil
	if pooled then return pooled end
	if pool.Count >= pool.Limit then return nil end

	pool.Count += 1
	return build(pool, template)
end

function motorParts.Release(pool: TPool, mover: TMover)
	mover.Joint.Transform = motorParts.PARK
	local free = pool.Free[mover.Template]
	if not free then
		free = {}
		pool.Free[mover.Template] = free
	end

	free[#free + 1] = mover
end

return motorParts
