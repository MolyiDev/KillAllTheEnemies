-- The gun each player wears on their back (Loadout.Worn, BackGunService), drawn on every character by every client: a
-- copy of the gun's model slung across the back. Put on, it swings over the shoulder, small and turned, lands with a
-- knock and rocks still; taken off, it lifts away rolling and shrinks to nothing. A worn gun held in hand (the range)
-- leaves the back for as long as it is held. The copy is a child of the character, so first person hides it with the
-- body. Lobby only: a match shows no back gun.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(StarterPlayer.StarterPlayerScripts.GlobalClient.NetworkMeta)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local backGunModel = require(script.Parent.Parent.Utils.backGunModel)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local TCharacter = require(ReplicatedStorage.Types.TCharacter)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)
local TData = require(ReplicatedStorage.Types.TData)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local ServerNetworkLoadout = NetworkMeta.Server.Loadout

local GUNS = DataCore.Guns.ById

local Tune = table.freeze({
	-- On: from over the right shoulder (torso space, studs), this much smaller, turned this far in the back's plane and
	-- tipped this far off it, it falls onto the back in ARRIVE seconds, still picking up speed as it lands, so it
	-- knocks. Then for SETTLE seconds it rocks this many degrees, jellies this share of its size and bounces this far
	-- off the back over the first BOUNCE_SHARE of it.
	ARRIVE = 0.3,
	FROM = Vector3.new(0.9, 2.2, 1.6),
	FROM_SCALE = 0.25,
	FROM_ROLL_DEG = -120,
	FROM_TIP_DEG = 70,
	SETTLE = 0.5,
	ROCK_DEG = 12,
	JELLY = 0.14,
	BOUNCE = 0.35,
	BOUNCE_SHARE = 0.4,
	-- Off: lifting up and back, rolling and shrinking to MIN_SCALE in LEAVE seconds; quicker drawn into the hand.
	LEAVE = 0.3,
	DRAW = 0.16,
	LEAVE_TO = Vector3.new(0, 1.4, 1.8),
	LEAVE_ROLL_DEG = 70,
	MIN_SCALE = 0.05,
	-- Further from the camera than this a gun goes on and off at once and silently.
	MOTION_RANGE = 120,
})

type TBack = {
	Character: Model,
	Torso: BasePart,
	Gun: TData.TGun,
	Model: Model,
	Weld: Weld,
	Parts: { BasePart },
	Welds: { WeldConstraint },
	-- The handle in the torso's space at rest, and the model's scale at full size.
	Slot: CFrame,
	Scale: number,
	-- When the current motion started, whether it is the way off, and how long the way off takes (into the hand is
	-- quicker).
	At: number,
	IsLeaving: boolean,
	LeaveSeconds: number,
	HasKnocked: boolean,
}

type TWearer = {
	Player: Player,
	Character: Model,
	Torso: BasePart,
	Back: TBack?,
	Connections: { RBXScriptConnection },
}

local BackGunController = {}

-- Each player's worn gun Id as the server last sent it, 0 for none.
local worn: { [Player]: number } = {}
local wearers: { [Model]: TWearer } = {}
-- Every back in motion, the leaving ones too: the frame loop runs only while this has any.
local moving: { TBack } = {}
-- Each gun's model built once (backGunModel), cloned for every back, and where it sits. Unparented, so they cost
-- nothing.
local templates: { [number]: { Model: Model, Fit: backGunModel.TFit } | false } = {}

local function getTemplate(gun: TData.TGun): { Model: Model, Fit: backGunModel.TFit }?
	local cached = templates[gun.Id]
	if cached == nil then
		local model, fit = backGunModel.Build(gun)
		cached = if model and fit then { Model = model, Fit = fit } else false
		templates[gun.Id] = cached
	end

	return cached or nil
end

local function isNearCamera(part: BasePart): boolean
	local offset = part.Position - Workspace.CurrentCamera.CFrame.Position
	return offset:Dot(offset) < Tune.MOTION_RANGE * Tune.MOTION_RANGE
end

-- Moved by hand: in motion every part is anchored and unwelded, since scaling or moving a copy welded into a body
-- would drag the body with it.
local function loosen(back: TBack)
	back.Weld.Enabled = false
	for _, weld in back.Welds do
		weld.Enabled = false
	end
	for _, part in back.Parts do
		part.Anchored = true
	end
end

-- Held still on the back: at full size on its slot, welded together and to the torso, and moved by the body like any
-- part of it. The welds go back on before the parts are let go, all in one frame, so no physics step sees it half done.
local function rest(back: TBack)
	back.Model:ScaleTo(back.Scale)
	back.Model:PivotTo(back.Torso.CFrame * back.Slot)
	for _, weld in back.Welds do
		weld.Enabled = true
	end
	back.Weld.C0 = back.Slot
	back.Weld.Enabled = true
	for _, part in back.Parts do
		part.Anchored = false
	end
end

local function stop(back: TBack)
	local index = table.find(moving, back)
	if not index then return end
	moving[index] = moving[#moving]
	moving[#moving] = nil
end

local function remove(back: TBack)
	stop(back)
	back.Model:Destroy()
	back.Weld:Destroy()
end

local function putOn(wearer: TWearer, gun: TData.TGun, isMoved: boolean): TBack?
	local template = getTemplate(gun)
	if not template then return nil end

	local torso = wearer.Torso
	local model = template.Model:Clone()
	local weld = Instance.new("Weld")
	weld.Name = "BackGunWeld"
	weld.Part0 = torso
	weld.Part1 = model.PrimaryPart
	weld.Enabled = false

	local parts, welds = {}, {}
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			table.insert(parts, item)
		elseif item:IsA("WeldConstraint") then
			table.insert(welds, item)
		end
	end

	local back: TBack = {
		Character = wearer.Character,
		Torso = torso,
		Gun = gun,
		Model = model,
		Weld = weld,
		Parts = parts,
		Welds = welds,
		Slot = backGunModel.Slot(template.Fit, torso),
		Scale = model:GetScale(),
		At = os.clock(),
		IsLeaving = false,
		LeaveSeconds = Tune.LEAVE,
		HasKnocked = false,
	}
	-- Straight on: the clone is already whole and unanchored, so only the torso's weld is wanted.
	if not isMoved or not isNearCamera(torso) then
		weld.C0 = back.Slot
		weld.Enabled = true
		weld.Parent = torso
		model.Parent = wearer.Character
		return back
	end

	loosen(back)
	weld.Parent = torso
	model.Parent = wearer.Character
	model:ScaleTo(back.Scale * Tune.FROM_SCALE)
	model:PivotTo(torso.CFrame * CFrame.new(Tune.FROM) * back.Slot)
	table.insert(moving, back)
	return back
end

local function takeOff(back: TBack, seconds: number)
	if not isNearCamera(back.Torso) then
		remove(back)
		return
	end

	loosen(back)
	back.At = os.clock()
	back.IsLeaving = true
	back.LeaveSeconds = seconds
	if not table.find(moving, back) then table.insert(moving, back) end
end

-- One frame of a back's motion; true once it is over.
local function step(back: TBack, now: number): boolean
	local elapsed = now - back.At
	local slot = back.Slot
	if back.IsLeaving then
		-- Flicked off at once (moving and turning fastest as it leaves the back), shrinking ever faster to nothing, so
		-- it is already small when it goes.
		local t = math.clamp(elapsed / back.LeaveSeconds, 0, 1)
		local flicked = Motion.Out(t)
		back.Model:ScaleTo(back.Scale * Motion.Lerp(1, Tune.MIN_SCALE, t * t))
		local offset = CFrame.new(Tune.LEAVE_TO * flicked)
		back.Model:PivotTo(
			back.Torso.CFrame * offset * slot * CFrame.Angles(0, 0, math.rad(Tune.LEAVE_ROLL_DEG * flicked))
		)
		return t >= 1
	end

	local t = math.clamp(elapsed / Tune.ARRIVE, 0, 1)
	local settled = math.clamp((elapsed - Tune.ARRIVE) / Tune.SETTLE, 0, 1)
	if t >= 1 and not back.HasKnocked then
		back.HasKnocked = true
		SoundsCore.PlayNamedOnPart("Weapons.Revolver", "Holster", back.Torso)
	end
	if settled >= 1 then
		rest(back)
		return true
	end

	-- The fall is t squared: still at the shoulder, fastest at the back. It turns and grows early, so it lands square.
	local fallen = t * t
	local turned = 1 - Motion.Decelerate(t)
	local jelly = Motion.Swing(settled)
	local roll = Tune.FROM_ROLL_DEG * turned + Tune.ROCK_DEG * jelly
	local tip = Tune.FROM_TIP_DEG * turned
	local bounce = Tune.BOUNCE * Motion.Bump(settled / Tune.BOUNCE_SHARE)
	local size = Motion.Lerp(Tune.FROM_SCALE, 1, Motion.Decelerate(t)) + Tune.JELLY * jelly
	back.Model:ScaleTo(back.Scale * size)
	back.Model:PivotTo(
		back.Torso.CFrame
			* CFrame.new(Tune.FROM * (1 - fallen) + Vector3.zAxis * bounce)
			* slot
			* CFrame.Angles(math.rad(tip), 0, math.rad(roll))
	)
	return false
end

local function frame()
	if #moving == 0 then return end
	local now = os.clock()
	for index = #moving, 1, -1 do
		local back = moving[index]
		if not step(back, now) then continue end
		moving[index] = moving[#moving]
		moving[#moving] = nil
		if back.IsLeaving then remove(back) end
	end
end

local function isHolding(character: Model, gun: TData.TGun): boolean
	local tool = character:FindFirstChild(gun.Name)
	return tool ~= nil and tool:IsA("Tool")
end

-- Puts on, swaps or takes off the wearer's back gun to match what they wear and hold. `isMoved` false sets it straight
-- there (a character just in), true plays its motion.
local function refresh(wearer: TWearer, isMoved: boolean)
	local gun = GUNS[worn[wearer.Player] or 0]
	local isHeld = gun ~= nil and isHolding(wearer.Character, gun)
	local wanted = if isHeld then nil else gun
	local back = wearer.Back
	if back and back.Gun == wanted then return end

	if back then
		wearer.Back = nil
		if isMoved then
			takeOff(back, if isHeld then Tune.DRAW else Tune.LEAVE)
		else
			remove(back)
		end
	end
	if wanted then wearer.Back = putOn(wearer, wanted, isMoved) end
end

BackGunController.OnStart = function()
	RunService.PreRender:Connect(frame)
end

BackGunController.OnCharacterAdded = function(character: TCharacter.TCharacter)
	local player = Players:GetPlayerFromCharacter(character)
	local torso = character:FindFirstChild("Torso")
	if not player or not torso or not torso:IsA("BasePart") then return end

	local wearer: TWearer = {
		Player = player,
		Character = character,
		Torso = torso,
		Back = nil,
		Connections = {},
	}
	wearers[character] = wearer
	local function onTool(child: Instance)
		if child:IsA("Tool") then refresh(wearer, true) end
	end
	table.insert(wearer.Connections, character.ChildAdded:Connect(onTool))
	table.insert(wearer.Connections, character.ChildRemoved:Connect(onTool))
	refresh(wearer, false)
end :: TCharacterEvents.OnCharacterAdded

BackGunController.OnCharacterRemoving = function(character: TCharacter.TCharacter)
	local wearer = wearers[character]
	if not wearer then return end
	wearers[character] = nil
	for _, connection in wearer.Connections do
		connection:Disconnect()
	end

	-- Its leaving backs go with it.
	for index = #moving, 1, -1 do
		local back = moving[index]
		if back.Character == character then remove(back) end
	end
	if wearer.Back then remove(wearer.Back) end
end :: TCharacterEvents.OnCharacterRemoving

BackGunController.OnPlayerDisconnected = function(player: Player)
	worn[player] = nil
end :: TPlayerEvents.OnPlayerDisconnected

ServerNetworkLoadout.Worn.On(function(player: Player, gunId: number)
	if not player or player.Parent ~= Players then return end
	worn[player] = gunId
	for _, wearer in wearers do
		if wearer.Player == player then refresh(wearer, true) end
	end
end)

return Ignis.Register(BackGunController)
