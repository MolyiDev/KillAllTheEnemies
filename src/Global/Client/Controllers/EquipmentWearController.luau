-- The equipment each player wears and shows (Equipment.Worn, EquipmentService), drawn on every character by every
-- client in both places: each piece's accessories welded to the body by their attachments (equipmentPieces), in a
-- folder of their own. Put on, a piece falls onto its spot and knocks; taken off, it is flicked away. The avatar's own
-- accessories a shown piece covers (a helm over the hats and hair) are hidden while it is on. The pieces are children
-- of the character, so first person hides them with the body.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(StarterPlayer.StarterPlayerScripts.GlobalClient.NetworkMeta)
local equipmentPieces = require(script.Parent.Parent.Utils.equipmentPieces)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local TCharacter = require(ReplicatedStorage.Types.TCharacter)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)
local TData = require(ReplicatedStorage.Types.TData)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local ServerNetworkEquipment = NetworkMeta.Server.Equipment

local PIECES = DataCore.Equipment.ById

local Tune = table.freeze({
	-- Further from the camera than this a piece goes on and off at once and silently.
	MOTION_RANGE = 120,
	-- The folder each character's pieces are kept in.
	FOLDER = "Equipment",
})

-- One piece of equipment on a body: its accessories, and its motion while it has one.
type TWorn = {
	Character: Model,
	Item: TData.TEquipment,
	Parts: { equipmentPieces.TPiece },
	At: number,
	IsLeaving: boolean,
	HasKnocked: boolean,
}

type TWearer = {
	Player: Player,
	Character: Model,
	Folder: Folder,
	-- By piece Id.
	Worn: { [number]: TWorn },
	-- The avatar's own handles hidden under a piece, and their transparency before.
	Kept: { [BasePart]: number },
	Connections: { RBXScriptConnection },
}

local EquipmentWearController = {}

-- Each player's worn and shown piece Ids as the server last sent them.
local wornIds: { [Player]: { number } } = {}
local wearers: { [Model]: TWearer } = {}
-- Every piece in motion, the leaving ones too: the frame loop runs only while this has any.
local moving: { TWorn } = {}

local function isNearCamera(part: BasePart): boolean
	local offset = part.Position - Workspace.CurrentCamera.CFrame.Position
	return offset:Dot(offset) < Tune.MOTION_RANGE * Tune.MOTION_RANGE
end

local function stop(worn: TWorn)
	local index = table.find(moving, worn)
	if not index then return end
	moving[index] = moving[#moving]
	moving[#moving] = nil
end

local function destroy(worn: TWorn)
	stop(worn)
	for _, part in worn.Parts do
		part.Accessory:Destroy()
	end
end

-- Hides the avatar's accessories under the pieces on, coming on and still flicking off, and shows the rest: a hat
-- comes back once the helm that hid it is gone, not as it starts to go.
local function cover(wearer: TWearer)
	local attachments = {}
	local function mark(worn: TWorn)
		for _, part in worn.Parts do
			attachments[part.Attachment.Name] = true
		end
	end
	for _, worn in wearer.Worn do
		mark(worn)
	end
	for _, worn in moving do
		if worn.IsLeaving and worn.Character == wearer.Character then mark(worn) end
	end
	equipmentPieces.CoverAvatar(wearer.Character, attachments, wearer.Kept)
end

local function putOn(wearer: TWearer, item: TData.TEquipment, isMoved: boolean): TWorn
	local parts = {}
	for _, accessory in equipmentPieces.Clone(item) do
		local part = equipmentPieces.Attach(wearer.Character, accessory, wearer.Folder)
		if part then
			table.insert(parts, part)
		else
			accessory:Destroy()
		end
	end

	local worn: TWorn = {
		Character = wearer.Character,
		Item = item,
		Parts = parts,
		At = os.clock(),
		IsLeaving = false,
		HasKnocked = false,
	}
	local first = parts[1]
	if isMoved and first and isNearCamera(first.Handle) then
		for _, part in parts do
			equipmentPieces.Step(part, 0, false)
		end
		table.insert(moving, worn)
	end

	return worn
end

local function takeOff(worn: TWorn, isMoved: boolean)
	local first = worn.Parts[1]
	if not isMoved or not first or not isNearCamera(first.Handle) then
		destroy(worn)
		return
	end

	worn.At = os.clock()
	worn.IsLeaving = true
	if not table.find(moving, worn) then table.insert(moving, worn) end
end

-- Puts on and takes off the wearer's pieces to match what they wear. `isMoved` false sets them straight there (a
-- character just in), true plays their motion.
local function refresh(wearer: TWearer, isMoved: boolean)
	local wanted = {}
	for _, itemId in wornIds[wearer.Player] or {} do
		local item = PIECES[itemId]
		if item then wanted[itemId] = item end
	end

	for itemId, worn in wearer.Worn do
		if wanted[itemId] then continue end
		wearer.Worn[itemId] = nil
		takeOff(worn, isMoved)
	end
	for itemId, item in wanted do
		if wearer.Worn[itemId] then continue end
		wearer.Worn[itemId] = putOn(wearer, item, isMoved)
	end

	cover(wearer)
end

-- One frame of a piece's motion; true once it is over.
local function step(worn: TWorn, now: number): boolean
	local elapsed = now - worn.At
	local isDone = true
	for _, part in worn.Parts do
		if not equipmentPieces.Step(part, elapsed, worn.IsLeaving) then isDone = false end
	end

	local first = worn.Parts[1]
	if not worn.IsLeaving and not worn.HasKnocked and first and elapsed >= equipmentPieces.ARRIVE_SECONDS then
		worn.HasKnocked = true
		SoundsCore.PlayNamedOnPart("Equip", "Cloth", first.Handle)
	end

	return isDone
end

local function frame()
	if #moving == 0 then return end
	local now = os.clock()
	for index = #moving, 1, -1 do
		local worn = moving[index]
		if not step(worn, now) then continue end
		moving[index] = moving[#moving]
		moving[#moving] = nil
		if not worn.IsLeaving then continue end
		destroy(worn)
		local wearer = wearers[worn.Character]
		if wearer then cover(wearer) end
	end
end

EquipmentWearController.OnStart = function()
	RunService.PreRender:Connect(frame)
end

EquipmentWearController.OnCharacterAdded = function(character: TCharacter.TCharacter)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end

	local folder = Instance.new("Folder")
	folder.Name = Tune.FOLDER
	folder.Parent = character
	local wearer: TWearer = {
		Player = player,
		Character = character,
		Folder = folder,
		Worn = {},
		Kept = {},
		Connections = {},
	}
	wearers[character] = wearer
	-- The avatar's accessories can arrive after the body: each is covered as it comes.
	table.insert(
		wearer.Connections,
		character.ChildAdded:Connect(function(child: Instance)
			if child:IsA("Accessory") then cover(wearer) end
		end)
	)
	refresh(wearer, false)
end :: TCharacterEvents.OnCharacterAdded

EquipmentWearController.OnCharacterRemoving = function(character: TCharacter.TCharacter)
	local wearer = wearers[character]
	if not wearer then return end
	wearers[character] = nil
	for _, connection in wearer.Connections do
		connection:Disconnect()
	end

	-- Its leaving pieces go with it.
	for index = #moving, 1, -1 do
		local worn = moving[index]
		if worn.Character == character then destroy(worn) end
	end
	for _, worn in wearer.Worn do
		destroy(worn)
	end
end :: TCharacterEvents.OnCharacterRemoving

EquipmentWearController.OnPlayerDisconnected = function(player: Player)
	wornIds[player] = nil
end :: TPlayerEvents.OnPlayerDisconnected

ServerNetworkEquipment.Worn.On(function(player: Player, itemIds: { number })
	if not player or player.Parent ~= Players then return end
	wornIds[player] = itemIds
	for _, wearer in wearers do
		if wearer.Player == player then refresh(wearer, true) end
	end
end)

return Ignis.Register(EquipmentWearController)
