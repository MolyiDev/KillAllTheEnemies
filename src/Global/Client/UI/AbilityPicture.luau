--!nonstrict
-- An ability as it is drawn on its card, the same everywhere a card shows it (the run's ABILITIES column, the lobby's
-- classes screen): its model from ReplicatedStorage.Models.Abilities (Rojo's, made by Assets/models/Abilities), looked
-- at from its own angle through GunPicture. The Decoy is the player's own avatar in the doll's pose once there is a
-- copy of it (Doll), as the doll thrown in a run is. A kind with no model draws nothing, as a gun with none does.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.vide)
local AvatarPose = require(script.Parent.AvatarPose)
local GunPicture = require(script.Parent.GunPicture)
local copyCharacter = require(script.Parent.Parent.Utils.copyCharacter)
local equipmentPieces = require(script.Parent.Parent.Utils.equipmentPieces)

local create = vide.create
local derive = vide.derive

-- By kind, how its model is looked at: the camera's turn round it from its front and its height over it (deg), and
-- how far the picture leans.
local VIEWS = table.freeze({
	Decoy = { Yaw = 28, Pitch = 13, Lean = 0 },
	FoamCannon = { Yaw = 26, Pitch = 14, Lean = 14 },
	OrbitalCannon = { Yaw = 28, Pitch = 10, Lean = -12 },
})

local AbilityPicture = {}

local pictures: { [string]: GunPicture.TPicture | false } = {}

-- A copy of `character` in the doll's pose, for the Decoy's picture, or nil when it cannot be copied. Copy it once its
-- clothes and hats are on. It is the avatar alone, as the thrown doll is: the equipment may or may not have arrived
-- on the body yet.
function AbilityPicture.Doll(character: Model): Model?
	local copy = copyCharacter(character)
	if not copy then return nil end
	equipmentPieces.Strip(copy)
	AvatarPose.Apply(copy, AvatarPose.DOLL)
	return copy
end

-- The picture of the model of ability `kind`, or nil when the place has none.
local function pictureOf(kind: string): GunPicture.TPicture?
	local cached = pictures[kind]
	if cached ~= nil then return cached or nil end

	local models = ReplicatedStorage:FindFirstChild("Models")
	local folder = if models then models:FindFirstChild("Abilities") else nil
	local model = if folder then folder:FindFirstChild(kind) else nil
	local view = VIEWS[kind]
	local picture: GunPicture.TPicture | false = false
	if model and model:IsA("Model") and view then picture = GunPicture.FromModel(model, view.Yaw, view.Pitch) end

	pictures[kind] = picture
	return picture or nil
end

-- The picture of `avatar` (a Doll), looked at from its front (a character faces down its root's -Z) and from the side
-- of its right arm, the one that waves (AvatarPose), so the head never hides it.
local function avatarPicture(avatar: Model): GunPicture.TPicture?
	local root = avatar:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return nil end

	local view = VIEWS.Decoy
	local frame = root.CFrame.Rotation
		* CFrame.Angles(0, math.pi - math.rad(view.Yaw), 0)
		* CFrame.Angles(-math.rad(view.Pitch), 0, 0)
	return { Model = avatar, Origin = avatar:GetBoundingBox().Position, Barrel = frame.XVector, Up = frame.YVector }
end

-- Ability `kind`'s picture. `spec` holds sources, each optional: Rotation (a turn in the card's plane, deg),
-- Transparency and Scale. `doll` is a source of the player's Doll, for the Decoy. `props` are the box's own (its
-- place and size: the picture is fitted to it).
function AbilityPicture.Build(
	kind: string,
	spec: { [string]: any },
	doll: (() -> Model?)?,
	props: { [any]: any }
): Frame
	local picture = pictureOf(kind)
	local view = VIEWS[kind]
	-- Derived, so the frames a gesture is not running write nothing: a screen's clock may tick for other things, and
	-- these hold one value at rest.
	local rotation = if spec.Rotation then derive(spec.Rotation) else 0
	local scale = if spec.Scale then derive(spec.Scale) else 1

	return GunPicture.Build(function()
		local copy = if doll and kind == "Decoy" then doll() else nil
		return (if copy then avatarPicture(copy) else nil) or picture
	end, {
		Lean = if view then view.Lean else 0,
		Rotation = rotation,
		Transparency = spec.Transparency,
		Ambient = GunPicture.FLAT_AMBIENT,
		Light = GunPicture.FLAT_LIGHT,
	}, {
		Name = "Picture",
		AnchorPoint = Vector2.new(0.5, 0.5),
		create("UIScale")({ Scale = scale }),
		props,
	})
end

return table.freeze(AbilityPicture)
