-- The codes, in both places: the live list (EConfigKeys.Codes, never sent to clients) and redeeming one, which pays it
-- and records it in the same write, so a code pays each player once.
--
-- The list is MainConfig.json's "Codes": a code -> { Gems: number?, Xp: number? (percents of a level), Expired: true? }.
-- An expired code stays listed so a player who tries it is told so rather than that it never existed.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(ServerScriptService.GlobalServer.NetworkMeta)
local DatabaseService = require(ServerScriptService.GlobalServer.Services.DatabaseService)
local CodesCore = require(ReplicatedStorage.GlobalShared.Core.CodesCore)
local ConfigsCore = require(ReplicatedStorage.GlobalShared.Core.ConfigsCore)
local EConfigKeys = require(ReplicatedStorage.Types.Enums.EConfigKeys)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)
local TProfile = require(ReplicatedStorage.Types.TProfile)

local ServerNetworkCodes = NetworkMeta.Server.Codes
local ClientNetworkCodes = NetworkMeta.Client.Codes
local Status = CodesCore.Status

type TCode = {
	Gems: number,
	Xp: number,
	IsExpired: boolean,
}

-- A redeem is cheap to send, so a script could walk the list by trying codes: one try a second is more than anybody
-- types.
local TRY_COOLDOWN_SECONDS = 1
-- Codes.Redeemed's u32 and u16.
local MAX_GEMS = 2 ^ 32 - 1
local MAX_XP = 2 ^ 16 - 1

local CodesService = {}

local codes: { [string]: TCode } = {}
-- os.clock of each player's last try.
local triedAt: { [Player]: number } = {}

-- A whole amount from the config, or nil for a missing or broken one.
local function readAmount(name: string, field: string, value: any, max: number): number?
	if value == nil then return 0 end
	if type(value) ~= "number" or value < 0 or value > max or value ~= math.floor(value) then
		warn(`[CodesService] {name}.{field} is not a whole amount from 0 to {max}; the code is left out`)
		return nil
	end

	return value
end

local function rebuild(raw: any)
	table.clear(codes)
	if type(raw) ~= "table" then return end
	for name, entry in raw do
		if type(name) ~= "string" or type(entry) ~= "table" then continue end
		local key = CodesCore.Normalize(name)
		if key ~= name then
			warn(`[CodesService] "{name}" is not as it is typed (capitals and digits, at most {CodesCore.MAX_LENGTH})`)
			continue
		end
		local gems = readAmount(name, "Gems", entry.Gems, MAX_GEMS)
		local xp = readAmount(name, "Xp", entry.Xp, MAX_XP)
		if not gems or not xp then continue end
		if gems == 0 and xp == 0 then
			warn(`[CodesService] {name} pays nothing; it is left out`)
			continue
		end

		codes[key] = { Gems = gems, Xp = xp, IsExpired = entry.Expired == true }
	end
end

local function pay(profile: TProfile.TProfile, key: string, code: TCode)
	local redeemed = profile.RedeemedCodes or {}
	redeemed[key] = true
	profile.RedeemedCodes = redeemed
	profile.Gems += code.Gems
	profile.Xp += code.Xp
	while profile.Xp >= 100 do
		profile.Xp -= 100
		profile.Level += 1
	end
end

-- Works out the answer to one try: its status, and the code when it pays.
local function redeem(player: Player, text: string): (number, TCode?)
	local now = os.clock()
	local last = triedAt[player]
	if last and now - last < TRY_COOLDOWN_SECONDS then return Status.TooFast end
	triedAt[player] = now

	local key = CodesCore.Normalize(text)
	local code = codes[key]
	if not code then return Status.NotFound end
	if code.IsExpired then return Status.Expired end
	local profile = DatabaseService.Get(player)
	if not profile then return Status.Failed end
	if profile.RedeemedCodes and profile.RedeemedCodes[key] then return Status.AlreadyRedeemed end

	local isPaid = DatabaseService.Update(player, function(draft)
		if draft.RedeemedCodes and draft.RedeemedCodes[key] then return false end
		pay(draft, key, code)
		return true
	end)
	if not isPaid then return Status.Failed end
	DatabaseService.SaveAsync(player)
	return Status.Redeemed, code
end

CodesService.OnPlayerDisconnected = function(player: Player)
	triedAt[player] = nil
end :: TPlayerEvents.OnPlayerDisconnected

ConfigsCore.Observe(EConfigKeys.Codes, rebuild)

-- Needs no character: a code is the player's own, typed from a menu whatever his body is doing. Every try is answered,
-- so the screen waiting on it always settles. The answer goes out in the same frame as the profile it paid, so the
-- HUD's hold is in place before it draws the new Gems.
ClientNetworkCodes.Redeem.On(function(player: Player, text: string)
	-- The screen sends a code as Normalize leaves it, so anything longer came from elsewhere.
	if #text > CodesCore.MAX_LENGTH then return end
	local status, code = redeem(player, text)
	ServerNetworkCodes.Redeemed.Fire(player, status, if code then code.Gems else 0, if code then code.Xp else 0)
end)

return Ignis.Register(CodesService)
