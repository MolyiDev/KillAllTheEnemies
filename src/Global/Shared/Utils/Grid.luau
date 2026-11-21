export type Offset = { X: number, Y: number }

export type Grid<T> = {
	CellSize: number,
	Height: number,
	Width: number,
	OriginX: number,
	OriginZ: number,
	Grid: { T },
	SetCell: (self: Grid<T>, x: number, y: number, value: T) -> (),
	GetCell: (self: Grid<T>, x: number, y: number) -> T,
	GetCellIndex: (self: Grid<T>, x: number, y: number) -> number,
	GetCellXY: (self: Grid<T>, index: number) -> (number, number),
	GetWorldXZ: (self: Grid<T>, x: number, y: number) -> (number, number),
	GetCellXYFromWorldPos: (self: Grid<T>, pos: vector) -> (number?, number?),
	GetCellFromWorldPos: (self: Grid<T>, pos: vector) -> T?,
	GetCellFromWorldPos3: (self: Grid<T>, pos: Vector3) -> T?,
	GetRandomIndex: (self: Grid<T>, borderForgiver: number) -> (number, number, number),
	IsCellInBounds: (self: Grid<T>, x: number, y: number) -> boolean,
	ForNeighbors: (
		self: Grid<T>,
		index: number,
		neighbors: { Offset },
		funct: (nx: number, ny: number, visitedIndex: number, dxyIndex: number) -> ()
	) -> (),
	ClearGrid: (self: Grid<T>) -> (),
}

--==[ Grid ]==--
local Grid = {}
Grid.__index = Grid

function Grid.GetCellIndex<T>(self: Grid<T>, x: number, y: number): number
	return y * self.Width + x
end

-- Sets the cell at (x,y) to value. Integer coordinates must be used.
function Grid.SetCell<T>(self: Grid<T>, x: number, y: number, value: T)
	self.Grid[self:GetCellIndex(x, y)] = value
end

-- Returns the value of cell at (x,y). Integer coordinates must be used.
function Grid.GetCell<T>(self: Grid<T>, x: number, y: number): T
	return self.Grid[self:GetCellIndex(x, y)]
end

function Grid.GetWorldXZ<T>(self: Grid<T>, x: number, y: number): (number, number)
	local worldX = self.OriginX + x * self.CellSize
	local worldZ = self.OriginZ + y * self.CellSize
	return worldX, worldZ
end

function Grid.GetCellXYFromWorldPos<T>(self: Grid<T>, pos: vector): (number?, number?)
	local relativeX = pos.x - self.OriginX
	local relativeZ = pos.z - self.OriginZ

	local gridX = math.floor(relativeX / self.CellSize + 0.5)
	local gridY = math.floor(relativeZ / self.CellSize + 0.5)

	if self:IsCellInBounds(gridX, gridY) then
		return gridX, gridY
	else
		return nil, nil
	end
end

function Grid.GetCellFromWorldPos<T>(self: Grid<T>, pos: vector): T?
	local relativeX = pos.x - self.OriginX
	local relativeZ = pos.z - self.OriginZ

	local gridX = math.floor(relativeX / self.CellSize + 0.5)
	local gridY = math.floor(relativeZ / self.CellSize + 0.5)

	if self:IsCellInBounds(gridX, gridY) then
		return self:GetCell(gridX, gridY)
	else
		return nil
	end
end

function Grid.GetCellFromWorldPos3<T>(self: Grid<T>, pos: Vector3): T?
	local relativeX = pos.X - self.OriginX
	local relativeZ = pos.Z - self.OriginZ

	local gridX = math.floor(relativeX / self.CellSize + 0.5)
	local gridY = math.floor(relativeZ / self.CellSize + 0.5)

	if self:IsCellInBounds(gridX, gridY) then
		return self:GetCell(gridX, gridY)
	else
		return nil
	end
end

function Grid.GetRandomIndex<T>(self: Grid<T>, borderForgiver: number): (number, number, number)
	local minX = borderForgiver
	local maxX = self.Width - borderForgiver - 1
	local minY = borderForgiver
	local maxY = self.Height - borderForgiver - 1

	-- Check if the border is too large for the grid
	if minX > maxX or minY > maxY then
		error(
			("Grid:GetRandomIndex: borderForgiver (%d) is too large for grid dimensions (%d, %d)"):format(
				borderForgiver,
				self.Width,
				self.Height
			)
		)
	end

	local x = math.random(minX, maxX)
	local y = math.random(minY, maxY)

	local idx = self:GetCellIndex(x, y)
	return idx, x, y
end

function Grid.IsCellInBounds<T>(self: Grid<T>, x: number, y: number): boolean
	return x >= 0 and x < self.Width and y >= 0 and y < self.Height
end

-- Calls funct for each neighbor in the provided neighbors table.
-- neighbours is an array of Offset (e.g. GridStatic.ADJACENT)
function Grid.ForNeighbors<T>(
	self: Grid<T>,
	index: number,
	neighbors: { Offset },
	funct: (nx: number, ny: number, visitedIndex: number, dxyIndex: number) -> ()
)
	local x, y = self:GetCellXY(index)
	for i = 1, #neighbors do
		local dxy = neighbors[i]
		local nx = x + dxy.X
		local ny = y + dxy.Y
		if not self:IsCellInBounds(nx, ny) then continue end
		funct(nx, ny, self:GetCellIndex(nx, ny), i)
	end
end

function Grid.GetCellXY<T>(self: Grid<T>, index: number): (number, number)
	local x = index % self.Width
	local y = math.floor(index / self.Width)
	return x, y
end

function Grid.ClearGrid<T>(self: Grid<T>)
	table.clear(self.Grid)
end

--==[ GridStatic ]==--
local GridStatic = {}

GridStatic.ADJACENT = {
	{ X = 1, Y = 0 },
	{ X = 0, Y = 1 },
	{ X = -1, Y = 0 },
	{ X = 0, Y = -1 },
}

GridStatic.DIAGONAL = {
	{ X = 1, Y = 1 },
	{ X = -1, Y = 1 },
	{ X = -1, Y = -1 },
	{ X = 1, Y = -1 },
}

GridStatic.ALL_DIRS = {
	{ X = 1, Y = 0 },
	{ X = 0, Y = 1 },
	{ X = -1, Y = 0 },
	{ X = 0, Y = -1 },
	{ X = 1, Y = 1 },
	{ X = -1, Y = 1 },
	{ X = -1, Y = -1 },
	{ X = 1, Y = -1 },
}

function GridStatic.new<T>(cellSize: number, width: number, height: number, fill: T?): Grid<T>
	local self = (setmetatable({}, Grid) :: any) :: Grid<T>
	self.CellSize = cellSize
	self.Width = math.floor(width)
	self.Height = math.floor(height)
	self.OriginX = -((self.Width * cellSize) / 2) + (cellSize / 2)
	self.OriginZ = -((self.Height * cellSize) / 2) + (cellSize / 2)

	local maxIndex = self.Width * self.Height
	self.Grid = table.create(maxIndex)

	if fill ~= nil then
		for i = 0, maxIndex - 1 do
			if typeof(fill) == "table" then
				self.Grid[i] = table.clone(fill)
			else
				self.Grid[i] = fill
			end
		end
	end

	return self
end

function GridStatic.fromGrid<T>(grid: Grid<T>): Grid<T>
	local self = (setmetatable(grid, Grid) :: any) :: Grid<T>
	return self
end

function GridStatic.ForBox(x1: number, y1: number, x2: number, y2: number, funct: (x: number, y: number) -> ())
	for x = x1, x2 do
		for y = y1, y2 do
			funct(x, y)
		end
	end
end

function GridStatic.ForBox2(pos1: Vector2, pos2: Vector2, funct: (x: number, y: number) -> ())
	for x = pos1.X, pos2.X do
		for y = pos1.Y, pos2.Y do
			funct(x, y)
		end
	end
end

return GridStatic
