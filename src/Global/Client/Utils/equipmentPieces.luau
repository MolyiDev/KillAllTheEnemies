-- A piece of equipment's accessories (ReplicatedStorage.Models.Equipment, one per body attachment), and the ways they
-- are put on: welded to a body by the attachment each one names, as Roblox's own accessories are (R6 bodies carry every
-- attachment these use: HatAttachment on the Head, Left/RightShoulderAttachment on the arms, WaistCenterAttachment on
-- the Torso), or laid out as they would sit on a body, for a picture.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Motion = require(script.Parent.Parent.UI.Motion)
local TData = require(ReplicatedStorage.Types.TData)

-- Where each attachment sits on a standard R6 body, from the Torso's middle: the Head 1.5 up with HatAttachment 0.6 up
-- in it, the arms 1.5 out with their shoulder attachments 1 up, the waist 1 down.
local BODY_ATTACHMENTS = table.freeze({
	HatAttachment = CFrame.new(0, 2.1, 0),
	HairAttachment = CFrame.new(0, 2.1, 0),
	LeftShoulderAttachment = CFrame.new(-1.5, 1, 0),
	RightShoulderAttachment = CFrame.new(1.5, 1, 0),
	WaistCenterAttachment = CFrame.new(0, -1, 0),
})

-- The avatar's own accessories a piece on an attachment covers, hidden while it is shown: a closed helm hides the hats,
-- the hair and anything on the face; elsewhere only what is on the same attachment.
local COVERS = table.freeze({
	HatAttachment = table.freeze({
		HatAttachment = true,
		HairAttachment = true,
		FaceFrontAttachment = true,
		FaceCenterAttachment = true,
	}),
})

-- A piece put on falls onto its spot from over it, small and turning, growing as it falls, still picking up speed as
-- it lands so it knocks; then it squashes, bounces a little and jellies still. Taken off, it is flicked up turning and
-- shrinks to nothing. Seconds, studs up from its spot, shares of its size and degrees about its up axis.
local Fall = table.freeze({
	ARRIVE = 0.3,
	FROM_HEIGHT = 2.6,
	FROM_SCALE = 0.3,
	FROM_SPIN_DEG = 220,
	SETTLE = 0.5,
	SQUASH = 0.22,
	BOUNCE = 0.16,
	BOUNCE_SHARE = 0.4,
	LEAVE = 0.26,
	LEAVE_RISE = 1.8,
	LEAVE_SPIN_DEG = 140,
	MIN_SCALE = 0.04,
})

export type TPiece = {
	Accessory: Accessory,
	Handle: BasePart,
	Mesh: SpecialMesh?,
	-- The attachment in the handle it is worn by, and the one on the body it is welded to (nil when the body has none).
	Attachment: Attachment,
	BodyAttachment: Attachment?,
	Weld: Weld?,
	-- The mesh's own scale, as it rests.
	BaseScale: Vector3,
}

local equipmentPieces = {}

-- A fresh copy of each of `item`'s accessories, unparented; empty when its model is missing (warned once).
local warned: { [string]: boolean } = {}
function equipmentPieces.Clone(item: TData.TEquipment): { Accessory }
	-- Looked up here, not waited for at require: every screen that draws a picture requires this module.
	local models = ReplicatedStorage:FindFirstChild("Models")
	local equipment = if models then models:FindFirstChild("Equipment") else nil
	local folder = if equipment then equipment:FindFirstChild(item.ModelName) else nil
	if not folder then
		if not warned[item.ModelName] then
			warned[item.ModelName] = true
			warn(`[equipmentPieces] no ReplicatedStorage.Models.Equipment.{item.ModelName}`)
		end
		return {}
	end

	local copies = {}
	for _, child in folder:GetChildren() do
		if child:IsA("Accessory") then table.insert(copies, child:Clone()) end
	end

	return copies
end

-- The body's own attachment called `name`: on one of its parts, never inside an accessory.
local function findBodyAttachment(body: Model, name: string): Attachment?
	for _, part in body:GetChildren() do
		if not part:IsA("BasePart") then continue end
		local attachment = part:FindFirstChild(name)
		if attachment and attachment:IsA("Attachment") then return attachment end
	end

	return nil
end

local function pieceOf(accessory: Accessory): TPiece?
	local handle = accessory:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then return nil end
	local attachment = handle:FindFirstChildOfClass("Attachment")
	if not attachment then return nil end
	local mesh = handle:FindFirstChildOfClass("SpecialMesh")

	return {
		Accessory = accessory,
		Handle = handle,
		Mesh = mesh,
		Attachment = attachment,
		BodyAttachment = nil,
		Weld = nil,
		BaseScale = if mesh then mesh.Scale else Vector3.one,
	}
end

-- Welds `accessory` to `body` by its attachment and parents it to `parent` (under the body). The weld is the handle's
-- own child, so moving the piece is writing its C1; nil when the body has no such attachment.
function equipmentPieces.Attach(body: Model, accessory: Accessory, parent: Instance): TPiece?
	local piece = pieceOf(accessory)
	if not piece then return nil end
	local bodyAttachment = findBodyAttachment(body, piece.Attachment.Name)
	if not bodyAttachment then return nil end
	local bodyPart = bodyAttachment.Parent :: BasePart

	local weld = Instance.new("Weld")
	weld.Name = "EquipmentWeld"
	weld.Part0 = bodyPart
	weld.Part1 = piece.Handle
	weld.C0 = bodyAttachment.CFrame
	weld.C1 = piece.Attachment.CFrame
	weld.Parent = piece.Handle
	piece.BodyAttachment = bodyAttachment
	piece.Weld = weld
	accessory.Parent = parent

	return piece
end

-- How long a piece takes to land and settle, and to leave.
equipmentPieces.ARRIVE_SECONDS = Fall.ARRIVE
equipmentPieces.SETTLE_SECONDS = Fall.ARRIVE + Fall.SETTLE
equipmentPieces.LEAVE_SECONDS = Fall.LEAVE

-- Holds `piece` `offset` (studs, in its spot's space) off its spot, turned `spinDeg` about its up axis and scaled by
-- `scale` (per axis) about its spot, by writing its weld and mesh only: the body it is welded to never moves for it.
local function pose(piece: TPiece, offset: Vector3, spinDeg: number, scale: Vector3)
	local weld = piece.Weld
	if not weld then return end
	if piece.Mesh then piece.Mesh.Scale = piece.BaseScale * scale end
	local own = piece.Attachment.CFrame
	local moved = CFrame.new(offset) * CFrame.Angles(0, math.rad(spinDeg), 0)
	weld.C1 = CFrame.new(own.Position * scale) * own.Rotation * moved:Inverse()
end

-- `elapsed` seconds into `piece`'s way on (or off, `isLeaving`), posed there. True once that way is over: on, the piece
-- is back at rest on its spot.
function equipmentPieces.Step(piece: TPiece, elapsed: number, isLeaving: boolean): boolean
	if isLeaving then
		local t = math.clamp(elapsed / Fall.LEAVE, 0, 1)
		local flicked = Motion.Out(t)
		local size = Motion.Lerp(1, Fall.MIN_SCALE, t * t)
		pose(piece, Vector3.yAxis * Fall.LEAVE_RISE * flicked, Fall.LEAVE_SPIN_DEG * flicked, Vector3.one * size)
		return t >= 1
	end

	local t = math.clamp(elapsed / Fall.ARRIVE, 0, 1)
	local settled = math.clamp((elapsed - Fall.ARRIVE) / Fall.SETTLE, 0, 1)
	if settled >= 1 then
		pose(piece, Vector3.zero, 0, Vector3.one)
		return true
	end

	-- The fall is t squared: still over the spot, fastest on it. It turns and grows early, so it lands square.
	local fallen = t * t
	local grown = Motion.Decelerate(t)
	local jelly = Motion.Swing(settled)
	local bounce = Fall.BOUNCE * Motion.Bump(settled / Fall.BOUNCE_SHARE)
	local size = Motion.Lerp(Fall.FROM_SCALE, 1, grown)
	local squash = Fall.SQUASH * jelly
	pose(
		piece,
		Vector3.yAxis * (Fall.FROM_HEIGHT * (1 - fallen) + bounce),
		Fall.FROM_SPIN_DEG * (1 - grown),
		Vector3.new(size * (1 + 0.6 * squash), size * (1 - squash), size * (1 + 0.6 * squash))
	)
	return false
end

-- Whether a piece on `pieceAttachment` covers the avatar's own accessory on `attachment`.
function equipmentPieces.Covers(pieceAttachment: string, attachment: string): boolean
	local covered = COVERS[pieceAttachment]
	if covered then return covered[attachment] == true end
	return pieceAttachment == attachment
end

-- Hides `body`'s own accessories that the pieces worn on `attachments` (attachment name -> true) cover, and shows the
-- rest again. A hidden handle's transparency is kept in `kept` to be put back; without `kept` (a copy of a body) a
-- shown one is opaque, as an avatar's accessories are.
function equipmentPieces.CoverAvatar(body: Model, attachments: { [string]: boolean }, kept: { [BasePart]: number }?)
	for _, accessory in body:GetChildren() do
		if not accessory:IsA("Accessory") then continue end
		local handle = accessory:FindFirstChild("Handle")
		local own = if handle then handle:FindFirstChildOfClass("Attachment") else nil
		if not handle or not handle:IsA("BasePart") or not own then continue end

		local isCovered = false
		for name in attachments do
			if equipmentPieces.Covers(name, own.Name) then
				isCovered = true
				break
			end
		end

		if isCovered then
			if kept and kept[handle] == nil then kept[handle] = handle.Transparency end
			handle.Transparency = 1
		elseif kept then
			local was = kept[handle]
			if was then
				handle.Transparency = was
				kept[handle] = nil
			end
		else
			handle.Transparency = 0
		end
	end
end

-- `accessories` anchored in a Model as they would sit on an R6 body standing at the origin facing -Z, for a picture.
-- `spread` scales how far apart they stand across the body: a pair worn on both shoulders reads small framed whole, so a
-- picture pulls it in.
function equipmentPieces.Arrange(accessories: { Accessory }, spread: number?): Model
	local across = spread or 1
	local model = Instance.new("Model")
	for _, accessory in accessories do
		local piece = pieceOf(accessory)
		if not piece then continue end
		local at = BODY_ATTACHMENTS[piece.Attachment.Name] or CFrame.identity
		at = at - Vector3.xAxis * at.Position.X * (1 - across)
		piece.Handle.Anchored = true
		piece.Handle.CFrame = at * piece.Attachment.CFrame:Inverse()
		accessory.Parent = model
	end

	return model
end

return equipmentPieces
