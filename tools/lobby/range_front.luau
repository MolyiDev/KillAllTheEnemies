-- The shooting range's front, as the plaza's other buildings have theirs: the SHOP's own portico, banners, ceiling
-- lamps and planters lifted out of the old Lobby place and stood in front of the range, with SHOOTING RANGE in the
-- same alphabet pack's neon letters on its band. Writes one Model to insert as Workspace.Lobby.Map.Range.Front
-- (Maps.md section 8); the porch's walls, roof and floor behind it are tools/lobby/range.py's.
--   python3 tools/uimatt/strip.py <LobbyOld.rbxl> /tmp/old.rbxl Tags
--   lune run tools/lobby/range_front.luau /tmp/old.rbxl Assets/models/Lobby/Range/RangeFront.rbxm
-- No plugin can write MeshPart.MeshId, so none of this can go in through Tripwire's create calls or Rojo.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Instance, Vector3, CFrame, Color3, Enum =
	roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum

-- The SHOP's front: its middle and the plane of its band (old Lobby place, Workspace.Map.Buildings.SHOP).
local SOURCE = Vector3.new(-68, 0, 31.4)
-- Where that lands: the range's front stands as far from the plaza's ring as the SHOP's does, on the plaza's axis
-- (tools/lobby/range.py: PORCH_X, AXIS).
local TARGET = Vector3.new(-23, 0, -13)
-- The SHOP faces -Z with its sign running toward -X; the range faces -X with its sign running toward +Z.
local TURN = CFrame.new(0, 0, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
local PLACE = CFrame.new(TARGET) * TURN * CFrame.new(-SOURCE)

local CREAM = Color3.fromRGB(176, 174, 146)
local TEXT = "SHOOTING RANGE"
-- Each letter's mesh and its own size (read off the mesh files); the pack's other letters sit at ids between these.
local LETTERS = {
	S = { Id = 3265176963, Size = Vector3.new(0.6005, 0.5996, 0.05) },
	H = { Id = 3265177579, Size = Vector3.new(0.6138, 0.6005, 0.05) },
	O = { Id = 3265177206, Size = Vector3.new(0.5996, 0.5996, 0.05) },
	R = { Id = 3265177028, Size = Vector3.new(0.6005, 0.5997, 0.05) },
	A = { Id = 3265177951, Size = Vector3.new(0.6005, 0.6001, 0.05) },
	E = { Id = 3265180705, Size = Vector3.new(0.5521, 0.6005, 0.05) },
	T = { Id = 3265176909, Size = Vector3.new(0.6005, 0.6005, 0.05) },
	I = { Id = 3265177517, Size = Vector3.new(0.1101, 0.6005, 0.05) },
	N = { Id = 3265177251, Size = Vector3.new(0.6005, 0.6005, 0.05) },
	G = { Id = 3265177634, Size = Vector3.new(0.6001, 0.5996, 0.05) },
}
-- LEADERBOARDS' letters are 6.75 times the mesh; fourteen characters fit the band's 52-stud panel at 5.8. Half a
-- stud deep, in the plaza's neon blue, their middles on the panel's face as the SHOP's are.
local SCALE = 5.8
local DEPTH = 0.5
local GAP = 0.5
local SPACE = 2.2
local LETTER_COLOR = Color3.fromRGB(89, 120, 206)
local LETTER_MIDDLE = Vector3.new(TARGET.X + 2.13, 25.8, TARGET.Z)

local game = roblox.deserializePlace(fs.readFile(process.args[1]))
local shop = game:GetService("Workspace").Map.Buildings.SHOP
local model = Instance.new("Model")
model.Name = "Front"

local function place(instance: any, shift: Vector3?)
	for _, part in { instance, table.unpack(instance:GetDescendants()) } do
		if part:IsA("BasePart") then part.CFrame = PLACE * part.CFrame + (shift or Vector3.zero) end
	end
end

local function isWithin(instance: any, low: Vector3, high: Vector3): boolean
	for _, part in { instance, table.unpack(instance:GetDescendants()) } do
		if part:IsA("BasePart") then
			local at = part.CFrame.Position
			return at.X >= low.X and at.X <= high.X and at.Z >= low.Z and at.Z <= high.Z
		end
	end
	return false
end

-- The portico: everything of the SHOP's Base but its body (the range's porch is built round the door instead) and
-- the cream strips on that body's sides.
local portico = Instance.new("Model")
portico.Name = "Portico"
portico.Parent = model
for _, child in shop.Building.Base:GetChildren() do
	local isBody = child.Name == "Cube"
	local isBodyNeon = child.Name == "neon" and child.Color == CREAM
	if isBody or isBodyNeon then continue end
	place(child)
	child.Parent = portico
end

-- The banners with their chevrons, on the frame that carries them.
local flags = shop.Building.flags
place(flags)
flags.Name = "Flags"
flags.Parent = model

-- Three of the ceiling's lamps: the front pair where they hang, the middle one brought forward into a porch that
-- is shallower than the SHOP.
local lamps = Instance.new("Model")
lamps.Name = "Lamps"
lamps.Parent = model
for _, lamp in shop.Building.Lamps:GetChildren() do
	if lamp.Name ~= "lamp" then continue end
	if isWithin(lamp, Vector3.new(-100, 0, 39), Vector3.new(-40, 0, 42.5)) then
		place(lamp)
		lamp.Parent = lamps
	elseif isWithin(lamp, Vector3.new(-73, 0, 44), Vector3.new(-63, 0, 50)) then
		place(lamp, Vector3.new(-5, 0, 0))
		lamp.Parent = lamps
	end
end

-- The two planters in the SHOP's front corners.
local planters = Instance.new("Model")
planters.Name = "Planters"
planters.Parent = model
for _, bed in shop.extra:GetChildren() do
	if bed.Name == "plantbed2" and isWithin(bed, Vector3.new(-92, 0, 37), Vector3.new(-44, 0, 41)) then
		place(bed)
		bed.Parent = planters
	end
end

local width = 0
for index = 1, #TEXT do
	local letter = LETTERS[string.sub(TEXT, index, index)]
	width += if letter then letter.Size.X * SCALE else SPACE - GAP
	if index < #TEXT then
		width += GAP
	end
end

local label = Instance.new("Model")
label.Name = "Label"
label.Parent = model
local at = -width / 2
for index = 1, #TEXT do
	local character = string.sub(TEXT, index, index)
	local letter = LETTERS[character]
	if not letter then
		at += SPACE
		continue
	end

	local size = letter.Size * Vector3.new(SCALE, SCALE, 0) + Vector3.new(0, 0, DEPTH)
	local part = Instance.new("MeshPart") :: any
	part.Name = character
	part.MeshId = `rbxassetid://{letter.Id}`
	part.InitialSize = letter.Size
	part.Size = size
	part.CFrame = CFrame.new(LETTER_MIDDLE + Vector3.new(0, 0, at + size.X / 2)) * TURN
	part.Color = LETTER_COLOR
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = label
	at += size.X + GAP
end

local count = 0
for _, descendant in model:GetDescendants() do
	if descendant:IsA("BasePart") then
		count += 1
	end
end
fs.writeFile(process.args[2], roblox.serializeModel({ model }, string.match(process.args[2], "%.rbxmx$") ~= nil))
print(`{count} parts, label {string.format("%.1f", width)} studs wide -> {process.args[2]}`)
