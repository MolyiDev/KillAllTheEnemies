--!nonstrict
-- An enemy drawn as its own rig, standing, three quarters on, with its shadow under it like a gun's (GunPicture): a
-- ViewportFrame per layer holding a copy each, one lit, one a flat silhouette, so an unknown enemy shows only its shape
-- and a discovery can burn the shape white and come through it, and one drawn black and dropped for the shadow. Each
-- copy stands in a WorldModel, which a skinned body needs to deform and an Animator needs to play.
--
-- The rigs are ReplicatedStorage.Models.Enemies, the clips ReplicatedStorage.Animations.Enemies, as in the Game place;
-- a place without them draws nothing and holds still.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local GunPicture = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.GunPicture)
local TData = require(ReplicatedStorage.Types.TData)
local Parts = require(script.Parent.Parts)

local create = vide.create
local Palette = Theme.Palette

-- A long lens, so a body reads flat like his glyphs, with this much air over and under it.
local FOV = 18
-- The body at rest is turned this far to the camera's left, and looked at from this far over it.
local REST_YAW = -28
local PITCH = 7
local AMBIENT = Color3.fromRGB(150, 140, 172)
local LIGHT = Color3.fromRGB(255, 244, 250)
-- Where the key light travels in the camera's own frame: past it, down and to the right, so it comes over the
-- camera's left shoulder.
local KEY_LIGHT = Vector3.new(0.44, -0.64, -0.63).Unit
-- A viewport blends its edge pixels toward its BackgroundColor3 even when the background is transparent, so the
-- default white leaves a light line round the body.
local FRINGE = Color3.new()
local SHADOW_DROP = GunPicture.SHADOW_DROP
local SHADOW_TRANSPARENCY = GunPicture.SHADOW_TRANSPARENCY
-- Below this a layer is taken out of the renderer.
local SHOWN_FLOOR = 0.002
-- How old a Poke stamp may be and still play the attack, in seconds.
local POKE_WINDOW = 0.25
-- The clip every body is posed and moved with: the walk, as a crowd is seen coming at you. The set's Idle moves none of
-- these rigs' arms, so a body idling stands in its rest pose, arms straight out.
local LOOP_CLIP = "Walk"
-- Where in it a still body stands: mid stride, its arms reaching forward.
local POSE_SECONDS = 1
-- The point looked at and the height that fills the box, as shares of the body's height from its feet.
local LOOK_AT = 0.5
local SPAN = 1.16

local Picture = {}

local warned: { [string]: boolean } = {}

local function warnOnce(key: string, message: string)
	if warned[key] then return end
	warned[key] = true
	warn(message)
end

-- `enemy`'s rig, or nil when the place does not have it.
function Picture.Rig(enemy: TData.TEnemy): Model?
	local models = ReplicatedStorage:FindFirstChild("Models")
	local folder = if models then models:FindFirstChild("Enemies") else nil
	local rig = if folder then folder:FindFirstChild(enemy.ModelName) else nil
	if rig and rig:IsA("Model") then return rig end
	warnOnce(enemy.ModelName, `[IndexController] no rig ReplicatedStorage.Models.Enemies.{enemy.ModelName}`)
	return nil
end

-- `enemy`'s clip called `name` from its set, or nil.
function Picture.Clip(enemy: TData.TEnemy, name: string): Animation?
	local animations = ReplicatedStorage:FindFirstChild("Animations")
	local enemies = if animations then animations:FindFirstChild("Enemies") else nil
	local set = if enemies then enemies:FindFirstChild(enemy.AnimationSet) else nil
	local clip = if set then set:FindFirstChild(name) else nil
	return if clip and clip:IsA("Animation") then clip else nil
end

-- The clip its first attack winds up with: what it does when poked.
local function attackClip(enemy: TData.TEnemy): Animation?
	local attack = enemy.Attacks[1]
	return Picture.Clip(enemy, if attack then attack.AnimationName or "Attack" else "Attack")
end

-- Paints `copy` one flat white, for the silhouette: lit by nothing but a white ambient, a white body with no texture
-- comes out its frame's ImageColor3 everywhere.
local function blank(copy: Model)
	for _, item in copy:GetDescendants() do
		if item:IsA("MeshPart") then item.TextureID = "" end
		if item:IsA("BasePart") then
			item.Color = Palette.White
			item.Material = Enum.Material.SmoothPlastic
		elseif item:IsA("SurfaceAppearance") or item:IsA("Decal") then
			item:Destroy()
		end
	end
end

local function animator(copy: Model): Animator?
	local controller = copy:FindFirstChildOfClass("AnimationController")
	return if controller then controller:FindFirstChildOfClass("Animator") else nil
end

-- Stands `track` at the pose's frame, once its clip has loaded: before that it has no length and the frame is lost.
local function pose(track: AnimationTrack)
	if track.Length > 0 then
		track.TimePosition = POSE_SECONDS % track.Length
		return
	end
	local connection: RBXScriptConnection? = nil
	connection = track:GetPropertyChangedSignal("Length"):Connect(function()
		if track.Length <= 0 then return end
		if connection then connection:Disconnect() end
		track.TimePosition = POSE_SECONDS % track.Length
	end)
end

-- One of the frames: the viewport, its world, whether it is drawn, and the copy it holds while it is, with that copy's
-- rest, its walk and its attack.
type TLayer = {
	IsSilhouette: boolean,
	Shown: () -> boolean,
	View: ViewportFrame,
	World: WorldModel,
	Copy: Model?,
	Rest: CFrame,
	Loop: AnimationTrack?,
	Attack: AnimationTrack?,
}

-- A layer drawn `alpha()` solid (0 gone, 1 solid). The shadow is lit by nothing and multiplied to black on the way out,
-- so Neon, which ignores the light, is black too.
local function layer(kind: "Lit" | "Silhouette" | "Shadow", alpha: () -> number, props: { [any]: any }?): TLayer
	local isSilhouette = kind == "Silhouette"
	local isShadow = kind == "Shadow"
	local shown = vide.derive(function(): boolean
		return alpha() > SHOWN_FLOOR
	end)
	local camera = create("Camera")({ FieldOfView = FOV })
	local world = create("WorldModel")({})
	local view = create("ViewportFrame")({
		Name = kind,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, if isShadow then 0.5 + SHADOW_DROP else 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BackgroundColor3 = FRINGE,
		Ambient = if isSilhouette then Palette.White elseif isShadow then FRINGE else AMBIENT,
		LightColor = if isSilhouette or isShadow then FRINGE else LIGHT,
		CurrentCamera = camera,
		ImageColor3 = if isShadow then FRINGE else nil,
		ImageTransparency = function()
			return 1 - alpha()
		end,
		ZIndex = if isShadow then 1 elseif isSilhouette then 2 else 3,
		Visible = shown,
		camera,
		world,
		props,
	}) :: ViewportFrame
	return { IsSilhouette = isSilhouette, Shown = shown, View = view, World = world, Rest = CFrame.identity }
end

-- A box drawing `enemy()` (nil draws nothing), redrawn when it changes. `spec` fields, each optional, the functions
-- sources: Yaw (degrees on top of the three-quarter rest, about the body's middle), Transparency (0 shown, 1 gone),
-- Burned and Lit (a reveal's halves, Parts.Burned / Lit: 0 and 0 is the silhouette, Lit 1 the enemy; leave both out for
-- an enemy always shown), Moving (whether it walks; it holds mid stride while not, and walks always when left out),
-- Poke (a stamp: each change plays its attack). `props` are the box's own.
--
-- A layer holds its copy, and that copy its Animator and tracks, only while the layer is drawn: a card is nearly always
-- lit or a silhouette, not both, and the stage turns whatever is held every frame.
function Picture.Build(enemy: () -> TData.TEnemy?, spec: { [any]: any }, props: { [any]: any }): Frame
	local faded = spec.Transparency or function()
		return 0
	end
	local lit = spec.Lit or function()
		return 1
	end
	local burned = spec.Burned
	local yaw = spec.Yaw
	local moving = spec.Moving

	local litLayer = layer(
		"Lit",
		vide.derive(function(): number
			return lit() * (1 - faded())
		end)
	)
	-- Under the lit body and the silhouette alike, so it fades only with the whole picture.
	local shadowLayer = layer(
		"Shadow",
		vide.derive(function(): number
			return (1 - SHADOW_TRANSPARENCY) * (1 - faded())
		end)
	)
	local layers: { TLayer } = { litLayer, shadowLayer }
	-- Only a picture that can be unknown has a silhouette.
	local silhouetteLayer: TLayer? = nil
	if spec.Lit then
		silhouetteLayer = layer(
			"Silhouette",
			vide.derive(function(): number
				return (1 - lit()) * (1 - faded())
			end),
			{
				ImageColor3 = function()
					return Parts.SILHOUETTE:Lerp(Palette.White, if burned then burned() else 0)
				end,
			}
		)
		layers[3] = silhouetteLayer
	end

	-- What the enemy on show is drawn with, set as it changes: the rig copies are made from, its clips, and the axis a
	-- turn goes round.
	local current: TData.TEnemy? = nil
	local rig: Model? = nil
	local loopClip: Animation? = nil
	local attackClipNow: Animation? = nil
	local axis = Vector3.zero

	local function turn()
		local by = CFrame.new(axis) * CFrame.Angles(0, math.rad(REST_YAW + (if yaw then yaw() else 0)), 0)
		local around = CFrame.new(-axis)
		for _, each in layers do
			local copy = each.Copy
			if copy then copy:PivotTo(by * (around * each.Rest)) end
		end
	end

	local function speed(): number
		return if not moving or moving() then 1 else 0
	end

	local function drop(each: TLayer)
		if each.Copy then each.Copy:Destroy() end
		each.Copy = nil
		each.Loop = nil
		each.Attack = nil
	end

	-- Gives `each` its copy, walking in step with another layer's when one is held (the shadow's, a reveal crossing over).
	local function hold(each: TLayer)
		if each.Copy or not rig then return end
		local copy = rig:Clone()
		if each.IsSilhouette then blank(copy) end
		each.Rest = copy:GetPivot()
		copy.Parent = each.World
		each.Copy = copy
		turn()

		local playing = animator(copy)
		if not playing then return end
		if loopClip then
			local track = playing:LoadAnimation(loopClip)
			track.Looped = true
			track:Play(0)
			local inStep: AnimationTrack? = nil
			for _, other in layers do
				local otherLoop = other.Loop
				if other ~= each and otherLoop and otherLoop.Length > 0 then inStep = otherLoop end
			end
			if inStep then
				track.TimePosition = inStep.TimePosition
			else
				pose(track)
			end
			track:AdjustSpeed(speed())
			each.Loop = track
		end
		if attackClipNow and not each.IsSilhouette then
			local track = playing:LoadAnimation(attackClipNow)
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = false
			each.Attack = track
		end
	end

	-- Frames a new enemy: the camera in front of the body, a little over it, looking at LOOK_AT with SPAN filling the
	-- box's height. A rig's face is on its +Z side: from -Z it is seen from behind.
	local function frame(shownEnemy: TData.TEnemy?)
		for _, each in layers do
			drop(each)
		end
		current = shownEnemy
		rig = if shownEnemy then Picture.Rig(shownEnemy) else nil
		if not shownEnemy or not rig then return end
		loopClip = Picture.Clip(shownEnemy, LOOP_CLIP)
		attackClipNow = if spec.Poke then attackClip(shownEnemy) else nil

		local box, size = rig:GetBoundingBox()
		local feet = box.Position.Y - size.Y / 2
		axis = Vector3.new(box.Position.X, 0, box.Position.Z)
		local target = Vector3.new(box.Position.X, feet + size.Y * LOOK_AT, box.Position.Z)
		local distance = size.Y * SPAN / 2 / math.tan(math.rad(FOV / 2))
		local pitch = math.rad(PITCH)
		local eye = target + Vector3.new(0, math.sin(pitch), math.cos(pitch)) * distance
		local cameraFrame = CFrame.lookAt(eye, target)
		local light = cameraFrame:VectorToWorldSpace(KEY_LIGHT)
		for _, each in layers do
			(each.View.CurrentCamera :: Camera).CFrame = cameraFrame
			each.View.LightDirection = light
			if each.Shown() then hold(each) end
		end
	end

	vide.effect(function()
		local shownEnemy = enemy()
		vide.untrack(function()
			frame(shownEnemy)
		end)
	end)
	for _, each in layers do
		vide.effect(function()
			local isShown = each.Shown()
			vide.untrack(function()
				if not current then return end
				if isShown then
					hold(each)
				else
					drop(each)
				end
			end)
		end)
	end
	vide.cleanup(function()
		for _, each in layers do
			drop(each)
		end
	end)

	-- The copies follow the turn and the pace on their own, without being copied again.
	local function follow()
		yaw()
		vide.untrack(turn)
	end
	local function pace()
		local rate = speed()
		vide.untrack(function()
			for _, each in layers do
				if each.Loop then each.Loop:AdjustSpeed(rate) end
			end
		end)
	end
	if yaw then vide.effect(follow) end
	if moving then vide.effect(pace) end

	-- Only a stamp made just now plays: the source also changes as it starts or stops being passed through (an enemy
	-- becoming known), and that is no click. The shadow attacks with the body.
	local poke = spec.Poke
	if poke then
		vide.effect(function()
			local at = poke()
			vide.untrack(function()
				if os.clock() - at > POKE_WINDOW then return end
				for _, each in layers do
					if each.Attack then each.Attack:Play(0.08) end
				end
			end)
		end)
	end

	return create("Frame")({
		BackgroundTransparency = 1,
		shadowLayer.View,
		if silhouetteLayer then silhouetteLayer.View else nil,
		litLayer.View,
		props,
	}) :: Frame
end

return Picture
