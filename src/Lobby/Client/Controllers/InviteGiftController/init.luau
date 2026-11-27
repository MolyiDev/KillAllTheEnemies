-- The surprise gift's toast (Toast): offered once a lobby visit by the server (Invites.Gift), it names one friend to
-- invite. INVITE sends Roblox's invite to that friend, tagged so the server pays the gift when they come
-- (InvitesService); the X turns it down. Left alone it goes by itself after Toast.LAPSE_SECONDS, untold to the server,
-- so it comes again next visit. It stands aside while the lobby says something covers it (SetBlocked) and comes back
-- after. What the gift pays is the server's.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local vide = require(ReplicatedStorage.Packages.vide)
local NetworkMeta = require(StarterPlayer.StarterPlayerScripts.GlobalClient.NetworkMeta)
local InvitesCore = require(ReplicatedStorage.Shared.Core.InvitesCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local Toast = require(script.Toast)
local Types = require(script.Types)

local ServerNetworkInvites = NetworkMeta.Server.Invites
local ClientNetworkInvites = NetworkMeta.Client.Invites
local LocalPlayer = Players.LocalPlayer
local source = vide.source

local Tune = table.freeze({
	-- His 1920 x 1080, fitted inside the viewport whole.
	DESIGN = Vector2.new(1920, 1080),
	-- The light crosses INVITE this often while it waits.
	CALL_EVERY = 2.6,
	-- How many online friends are asked for, and how many pages of the whole list are read when none of those will do.
	MAX_ONLINE = 200,
	FRIEND_PAGES = 4,
})

local InviteGiftController = {}

local state: Types.TToastState = {
	Scale = source(1),
	Now = source(os.clock()),
	Friend = source(nil :: Types.TFriend?),
	Gems = source(0),
	ShownAt = source(-math.huge),
	GoneAt = source(-math.huge),
	Answer = source(""),
	CallAt = source(-math.huge),
}

-- When the toast is due (os.clock; math.huge once answered, or while none is offered), whether the lobby covers it,
-- until when Now ticks, when the light next crosses INVITE, and when its Gems stamp down (math.huge once sounded).
-- Offers: counts Invites.Gift, so a friend still being picked for one the server has since taken back is dropped.
local dueAt = math.huge
local isBlocked = false
local motionUntil = -math.huge
local nextCall = math.huge
local stampAt = math.huge
local offers = 0

-- Whether anything covers the lobby (a screen, a pad, a party's invite): the toast slides out and comes back after.
function InviteGiftController.SetBlocked(isBlockedNow: boolean)
	isBlocked = isBlockedNow
end

local function stir(seconds: number)
	motionUntil = math.max(motionUntil, os.clock() + seconds)
end

local function isUp(): boolean
	return state.GoneAt() < state.ShownAt()
end

local function show(now: number)
	vide.batch(function()
		state.Answer("")
		state.ShownAt(now)
	end)
	nextCall = now + Tune.CALL_EVERY
	stampAt = now + Toast.STAMP_SECONDS
	-- Its bar drains the whole time it is up.
	stir(math.max(Toast.ARRIVE_SECONDS, Toast.LAPSE_SECONDS))
	-- It comes in as the quest card does; its Gems stamp with their own sound (Assets/sounds/Review/InviteGift).
	SoundsCore.PlayUINamed("UI.UpgradePick", "Deal")
end

local function hide(now: number, answer: string)
	vide.batch(function()
		state.Answer(answer)
		state.GoneAt(now)
	end)
	nextCall = math.huge
	stampAt = math.huge
	stir(Toast.LEAVE_SECONDS)
end

-- Roblox's invite screen for the friend named (any friend when none is), tagged so their first join pays the gift.
local function sendInvite(friend: Types.TFriend?)
	local options = Instance.new("ExperienceInviteOptions")
	options.LaunchData = InvitesCore.GIFT_LAUNCH_DATA
	if friend then options.InviteUser = friend.UserId end
	local ok, err = pcall(SocialService.PromptGameInvite, SocialService, LocalPlayer, options)
	if not ok then warn("[InviteGiftController] PromptGameInvite failed:", err) end
end

local actions: Types.TToastActions = {
	Invite = function()
		if not isUp() then return end
		dueAt = math.huge
		hide(os.clock(), "Invite")
		sendInvite(state.Friend())
	end,
	Close = function()
		if not isUp() then return end
		dueAt = math.huge
		hide(os.clock(), "Close")
		ClientNetworkInvites.DeclineGift.Fire()
	end,
}

-- The user ids of friends who have played this game; empty if Roblox will not say. Yields.
local function friendsWhoPlayed(): { [number]: boolean }
	local played = {}
	local ok, ids = pcall(function()
		return (LocalPlayer :: any):GetFriendsWhoPlayedAsync()
	end)
	if not ok or type(ids) ~= "table" then return played end

	for _, id in ids do
		if type(id) == "number" then played[id] = true end
	end

	return played
end

-- A friend a first join could pay for: online now (in another game too, where their privacy lets it be seen) if any is,
-- else any from the list, the online ones first; never one who has played this game, whose join would not pay. Nil when
-- none can be told. Yields.
local function pickFriend(): Types.TFriend?
	local played = friendsWhoPlayed()

	local online: { Types.TFriend } = {}
	local isOnlineRead, friends = pcall(LocalPlayer.GetFriendsOnline, LocalPlayer, Tune.MAX_ONLINE)
	if isOnlineRead and type(friends) == "table" then
		for _, friend in friends do
			local id = friend.VisitorId
			if type(id) ~= "number" or played[id] or Players:GetPlayerByUserId(id) then continue end
			table.insert(online, { UserId = id, Username = friend.UserName, IsOnline = true })
		end
	end
	if #online > 0 then return online[math.random(#online)] end

	local awake: { Types.TFriend } = {}
	local asleep: { Types.TFriend } = {}
	local isListed, pages = pcall(Players.GetFriendsAsync, Players, LocalPlayer.UserId)
	if isListed then
		for _ = 1, Tune.FRIEND_PAGES do
			for _, item in pages:GetCurrentPage() do
				if played[item.Id] or Players:GetPlayerByUserId(item.Id) then continue end
				local friend = { UserId = item.Id, Username = item.Username, IsOnline = item.IsOnline == true }
				table.insert(if friend.IsOnline then awake else asleep, friend)
			end
			if pages.IsFinished or not pcall(pages.AdvanceToNextPageAsync, pages) then break end
		end
	end

	if #awake > 0 then return awake[math.random(#awake)] end
	if #asleep > 0 then return asleep[math.random(#asleep)] end
	return nil
end

-- Each frame: in once it is due and nothing covers the lobby, aside while something does, out for good once its time
-- has run, the stamp's sound and the light's calls.
local function step(now: number)
	if isUp() and now >= state.ShownAt() + Toast.LAPSE_SECONDS then dueAt = math.huge end
	local isWanted = now >= dueAt and not isBlocked
	if isWanted and not isUp() then
		show(now)
	elseif not isWanted and isUp() then
		hide(now, "Aside")
	end

	if now >= stampAt then
		stampAt = math.huge
		SoundsCore.PlayUINamed("UI.InviteGift", "Stamp")
	end
	if now >= nextCall then
		nextCall = now + Tune.CALL_EVERY
		state.CallAt(now)
		stir(Toast.CALL_SECONDS)
	end
end

local function updateScale()
	local viewport = Workspace.CurrentCamera.ViewportSize
	state.Scale(math.max(math.min(viewport.Y / Tune.DESIGN.Y, viewport.X / Tune.DESIGN.X), 0.01))
end

InviteGiftController.OnStart = function()
	vide.mount(function()
		return Toast.Build(state, actions)
	end, LocalPlayer:WaitForChild("PlayerGui"))

	-- Now is written only while something moves, so the toast at rest redraws nothing.
	RunService.PreRender:Connect(function()
		local now = os.clock()
		vide.batch(function()
			step(now)
			if now < motionUntil then state.Now(now) end
		end)
	end)

	local camera = Workspace.CurrentCamera
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	updateScale()
end

-- Offered only to a player Roblox lets send invites; the friend is picked before it is due, so it comes in whole. No
-- Gems: the gift was paid (its receipt is the shop's), and the toast goes for good.
ServerNetworkInvites.Gift.On(function(gems: number, seconds: number)
	offers += 1
	if gems == 0 then
		dueAt = math.huge
		return
	end

	local offer = offers
	local at = os.clock() + seconds
	task.spawn(function()
		local isRead, canInvite = pcall(SocialService.CanSendGameInviteAsync, SocialService, LocalPlayer)
		if not isRead or not canInvite then return end
		local friend = pickFriend()
		if offer ~= offers then return end
		vide.batch(function()
			state.Friend(friend)
			state.Gems(gems)
		end)
		dueAt = at
	end)
end)

return Ignis.Register(InviteGiftController)
