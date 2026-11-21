-- Which map this server plays. A reserved server runs one match, so the map its party queued for is moved once from
-- ServerStorage.Maps (a Model per MapsCore name) to Workspace.Arena, where ArenaCore bakes it. The maps live in
-- ServerStorage, not ReplicatedStorage, so a client never downloads the maps it is not playing.
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local arenaMap = {}

local isPlaced = false
local waiting: { thread } = {}

-- Only the first call places anything. With no such map there is no Workspace.Arena, which ArenaCore plays as a
-- flat floor.
function arenaMap.Place(mapName: string)
	if isPlaced then return end
	isPlaced = true

	local maps = ServerStorage:FindFirstChild("Maps")
	local map = if maps then maps:FindFirstChild(mapName) else nil
	if map then
		-- Scenery outside the play area (the sea, far islands): out of the arena, so the bake's grid (the arena's
		-- bounding box) and every ray at the arena skip it, and nothing walks or stands on it.
		local backdrop = map:FindFirstChild("Backdrop")
		if backdrop then backdrop.Parent = Workspace end
		map.Name = "Arena"
		-- Whole on every client and never streamed out: each client bakes its own nav grid from it (TelegraphController).
		map.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		map.Parent = Workspace
	else
		warn(`[arenaMap] no ServerStorage.Maps.{mapName}: the arena is a flat floor`)
	end

	for _, thread in waiting do
		task.spawn(thread)
	end
	table.clear(waiting)
end

-- Yields until a map is placed: a character loaded sooner would miss the map's SpawnLocations.
function arenaMap.WaitAsync()
	if isPlaced then return end
	table.insert(waiting, coroutine.running())
	coroutine.yield()
end

return arenaMap
