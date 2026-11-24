-- The queue pads, as both sides see them. A pad is a Part under Workspace.Lobby.Pads, a Model whose
-- ModelStreamingMode is Persistent (set in Studio): the lobby streams, and a client must hold every pad all the time,
-- to light it, hang its board and know which one it stands on. The first player on an empty pad is its host and
-- picks the party (size, map, difficulty, access); the rest who step on are its party, and when its countdown runs out
-- the party is teleported into a match together.
--
-- Pads are numbered by NAME ORDER on both sides, which is what lets the network name a pad with one byte.
local RunService = game:GetService("RunService")
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
	-- Its host is still picking the party.
	Busy = 4,
	-- To the host himself: he took longer than CHOOSE_SECONDS to pick and was taken off.
	Idle = 5,
	-- JOIN on an invite that had run out, or whose party had left or broken up.
	Expired = 6,
})

-- What came of an invite, as the network carries it to the player who sent it.
PadsCore.EInvite = table.freeze({
	Sent = 1,
	Joined = 2,
	Declined = 3,
	-- On a pad already (this one or another).
	InParty = 4,
	-- The party's map is not open to them.
	Locked = 5,
	Full = 6,
	-- Not ready for it: still loading, or between bodies.
	Away = 7,
})

-- How long an invite stands, and how long a party that was turned down waits before it may invite that player again,
-- in seconds.
PadsCore.INVITE_SECONDS = 20
PadsCore.INVITE_DECLINED_SECONDS = 30

-- TBD (GDD 23: party-size limit). The arena's own server size must be at least this.
PadsCore.MAX_PLAYERS = 4
-- What the host's menu opens on.
PadsCore.DEFAULT_PLAYERS = 4

-- Seconds a host has to pick the party before he is taken off the pad, so an idle player never holds one.
PadsCore.CHOOSE_SECONDS = 30
-- Seconds from the host starting the party to the teleport, and what it drops to once the pad is full.
PadsCore.COUNTDOWN_SECONDS = 15
PadsCore.FULL_COUNTDOWN_SECONDS = 3
-- How tall the zone above a pad's top face is.
PadsCore.ZONE_HEIGHT = 8

-- Where a party stands, in pad space on its top face, by the order its members took them: the first in the middle, the
-- rest out to the sides, each a little further back. One per player (MAX_PLAYERS). Everyone is turned toward a point
-- AUDIENCE studs out in front (+Z, the way out), where the camera frames them.
PadsCore.SPOTS = table.freeze({
	Vector3.new(0, 0, 0.5),
	Vector3.new(-4.5, 0, -0.3),
	Vector3.new(4.5, 0, -0.3),
	Vector3.new(-9, 0, -1.2),
})
PadsCore.AUDIENCE = 24

type TZone = {
	-- World to the pad's own space.
	ToPad: CFrame,
	HalfX: number,
	HalfZ: number,
	-- The zone's floor and ceiling over the pad's middle, in its own space.
	Bottom: number,
	Top: number,
}

local pads: { BasePart }? = nil
-- Each pad's zone, worked out on its first check.
local zones: { [BasePart]: TZone } = {}

-- Every pad, in name order. Index into this is the pad's network number (1-based; 0 means none).
function PadsCore.GetPads(): { BasePart }
	if pads then return pads end
	-- A client's scripts can start before the place has finished arriving: the Pads folder is there, its parts not yet
	-- (a playtest built the lobby with no pads at all, so no queue, board or pad light ever showed).
	if RunService:IsClient() and not game:IsLoaded() then game.Loaded:Wait() end
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

	-- An empty list is not kept: the next caller looks again.
	if #list > 0 then pads = list end
	return list
end

-- Whether a point stands on the pad: inside its footprint and within ZONE_HEIGHT above its top face, or no further than
-- `slack` studs outside that.
-- Called per pad per body every frame, so it reads the zone kept for the pad, never the part's properties: pads never
-- move or resize while the place runs.
function PadsCore.IsOnPad(pad: BasePart, point: Vector3, slack: number?): boolean
	local zone = zones[pad]
	if not zone then
		local half = pad.Size / 2
		zone = {
			ToPad = pad.CFrame:Inverse(),
			HalfX = half.X,
			HalfZ = half.Z,
			Bottom = half.Y - 1,
			Top = half.Y + PadsCore.ZONE_HEIGHT,
		}
		zones[pad] = zone
	end

	local reach = slack or 0
	local localPoint = zone.ToPad * point
	if math.abs(localPoint.X) > zone.HalfX + reach or math.abs(localPoint.Z) > zone.HalfZ + reach then return false end
	return localPoint.Y >= zone.Bottom - reach and localPoint.Y <= zone.Top + reach
end

-- Spot `index` on the pad's top face, facing the front.
function PadsCore.SpotAt(pad: BasePart, index: number): CFrame
	local top = Vector3.new(0, pad.Size.Y / 2, 0)
	local feet = pad.CFrame:PointToWorldSpace(PadsCore.SPOTS[index] + top)
	local audience = pad.CFrame:PointToWorldSpace(Vector3.new(0, pad.Size.Y / 2, PadsCore.AUDIENCE))
	return CFrame.lookAt(feet, audience)
end

return PadsCore
