-- The queue pads, as both sides see them. A pad is a Part under Workspace.Lobby.Pads. The first player on an empty
-- pad is its host and picks the party (size, map, access); the rest who step on are its party, and when its
-- countdown runs out the party is teleported into a match together.
--
-- Pads are numbered by NAME ORDER on both sides, which is what lets the network name a pad with one byte.
local Workspace = game:GetService("Workspace")

local PadsCore = {}

-- A pad's phase, as the network carries it.
PadsCore.EPhase = table.freeze({
	Empty = 0,
	-- The host is picking the party; nobody else can join yet.
	Choosing = 1,
	Open = 2,
	Teleporting = 3,
})

-- Why a step onto a pad was refused, as the network carries it.
PadsCore.ERefusal = table.freeze({
	Locked = 1,
	FriendsOnly = 2,
	NoFreePad = 3,
})

-- TBD (GDD 23: party-size limit). The arena's own server size must be at least this.
PadsCore.MAX_PLAYERS = 4
-- What the host's menu opens on.
PadsCore.DEFAULT_PLAYERS = 4

-- Seconds from the host starting the party to the teleport, and what it drops to once the pad is full.
PadsCore.COUNTDOWN_SECONDS = 15
PadsCore.FULL_COUNTDOWN_SECONDS = 3
-- How tall the zone above a pad's top face is.
PadsCore.ZONE_HEIGHT = 8

local pads: { BasePart }? = nil

-- Every pad, in name order. Index into this is the pad's network number (1-based; 0 means none).
function PadsCore.GetPads(): { BasePart }
	if pads then return pads end
	local list = {}
	local lobby = Workspace:WaitForChild("Lobby", 10)
	local folder = if lobby then lobby:WaitForChild("Pads", 10) else nil
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("BasePart") then list[#list + 1] = child end
		end
	end

	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)

	pads = list
	return list
end

-- Whether a point stands on the pad: inside its footprint and within ZONE_HEIGHT above its top face.
function PadsCore.IsOnPad(pad: BasePart, point: Vector3): boolean
	local localPoint = pad.CFrame:PointToObjectSpace(point)
	local half = pad.Size / 2
	if math.abs(localPoint.X) > half.X or math.abs(localPoint.Z) > half.Z then return false end
	return localPoint.Y >= half.Y - 1 and localPoint.Y <= half.Y + PadsCore.ZONE_HEIGHT
end

return PadsCore
