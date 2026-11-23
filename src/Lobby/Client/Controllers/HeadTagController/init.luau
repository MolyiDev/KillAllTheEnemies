-- The head tags (UIMatt.md, Player Head Tag): over every character in the lobby, a BillboardGui with the player's
-- name, class, level, trophies and deaths (Tag), from the figures the server sends everybody (Profile.Public). It
-- replaces Roblox's own name over the head, which is turned off on this client. A player standing in the shooting
-- range (RangeCore) has no tag: it fades and shrinks away as they walk in and comes back as they walk out.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local vide = require(ReplicatedStorage.Packages.vide)
local NetworkMeta = require(StarterPlayer.StarterPlayerScripts.GlobalClient.NetworkMeta)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local RangeCore = require(ReplicatedStorage.Shared.Core.RangeCore)
local Tag = require(script.Tag)
local TCharacter = require(ReplicatedStorage.Types.TCharacter)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)

local ServerNetworkProfile = NetworkMeta.Server.Profile

local LocalPlayer = Players.LocalPlayer
local create = vide.create
-- Called per tag every frame, so hoisted out of their modules.
local isInsideRange = RangeCore.IsInside
local progress = Motion.Progress
local accelerate = Motion.Accelerate
local decelerate = Motion.Decelerate

-- The tag in studs (its drawn rect with room, at his 448 x 178 ratio), how far over the head's middle its middle
-- floats (the panel's bottom edge a little over the top of the head), and how far away it is still drawn.
local WIDTH_STUDS = 5.6
local HEIGHT_STUDS = WIDTH_STUDS * Tag.BOX.Y / Tag.BOX.X
local OFFSET = Vector3.new(0, 1.9, 0)
local MAX_DISTANCE = 70
-- Walking into the range the tag goes in HIDE_SECONDS, accelerating away; walking out it is back in SHOW_SECONDS,
-- decelerating onto its size with no overshoot. Gone, it is this share of its size.
local HIDE_SECONDS = 0.22
local SHOW_SECONDS = 0.32
local SHRUNK = 0.8

type THeadTag = {
	Root: BasePart,
	Unmount: () -> (),
	IsInside: boolean,
	-- When the current fade (out while IsInside, in otherwise) started, moved back on a turn mid-fade so the tag goes
	-- on from where it was.
	At: number,
	-- 1 shown, 0 gone.
	Shown: vide.Source<number>,
}

local HeadTagController = {}

-- Each player's figures as the server last sent them, a source per player so a tag already up follows them.
local publics: { [Player]: vide.Source<Tag.TPublic?> } = {}
-- The tag over each character.
local tags: { [Model]: THeadTag } = {}

local function publicOf(player: Player): vide.Source<Tag.TPublic?>
	local public = publics[player]
	if not public then
		public = vide.source(nil :: Tag.TPublic?)
		publics[player] = public
	end
	return public
end

local function mount(character: TCharacter.TCharacter, player: Player)
	local public = publicOf(player)
	local box = Tag.BOX
	local root = character.HumanoidRootPart
	local isInside = isInsideRange(root.Position)
	local shown = vide.source(if isInside then 0 else 1)

	local unmount = vide.root(function(destroy: () -> ())
		local scale = vide.source(1)
		-- Derived, so what they decide is written as a fade starts and ends, not every frame of it.
		local isMoving = vide.derive(function(): boolean
			local current = shown()
			return current > 0 and current < 1
		end)
		local isDrawn = vide.derive(function(): boolean
			return public() ~= nil and shown() > 0
		end)
		-- Both hold the tag at the Root's middle, so it shrinks from there. The tag fades as one picture only in the
		-- group, which re-renders every frame the camera moves, so it is there only while it fades.
		local still = create("Frame")({
			Name = "Still",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		})
		local fading = create("CanvasGroup")({
			Name = "Fading",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Visible = isMoving,
			GroupTransparency = function()
				return 1 - shown()
			end,
			create("UIScale")({
				Scale = function()
					return Motion.Lerp(SHRUNK, 1, shown())
				end,
			}),
		})
		local billboard = create("BillboardGui")({
			Name = `HeadTag{player.UserId}`,
			Adornee = character.Head,
			Size = UDim2.fromScale(WIDTH_STUDS, HEIGHT_STUDS),
			StudsOffsetWorldSpace = OFFSET,
			MaxDistance = MAX_DISTANCE,
			AlwaysOnTop = true,
			LightInfluence = 0,
			ResetOnSpawn = false,
			Enabled = isDrawn,
			Parent = LocalPlayer:FindFirstChildOfClass("PlayerGui"),
			-- The tag is laid out in his px; this fits it to however big the billboard is drawn. The scale is read off
			-- Root, not Scaled, whose AbsoluteSize the UIScale itself changes.
			create("Frame")({
				Name = "Root",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				vide.changed("AbsoluteSize", function(size: Vector2)
					scale(size.X / box.X)
				end),
				still,
				fading,
			}),
		})
		create("Frame")({
			Name = "Scaled",
			Size = UDim2.fromOffset(box.X, box.Y),
			BackgroundTransparency = 1,
			Parent = function()
				return if isMoving() then fading else still
			end,
			create("UIScale")({
				Scale = scale,
			}),
			Tag.Build(player.Name, public),
		})
		vide.cleanup(function()
			billboard:Destroy()
		end)
		return destroy
	end)

	tags[character] = {
		Root = root,
		Unmount = unmount,
		IsInside = isInside,
		At = -math.huge,
		Shown = shown,
	}
end

-- How shown a tag is `now`: going on its fade out while its player is inside, on its fade in otherwise.
local function shownBy(tag: THeadTag, now: number): number
	if tag.IsInside then return 1 - accelerate(progress(now, tag.At, HIDE_SECONDS)) end
	return decelerate(progress(now, tag.At, SHOW_SECONDS))
end

-- Turns a tag's fade round at `now`, started back as far as its new curve needs to be where the old one had it.
local function turn(tag: THeadTag, now: number)
	local current = shownBy(tag, now)
	tag.IsInside = not tag.IsInside
	-- The inverses of 1 - t^3 and 1 - (1 - t)^3.
	local along = if tag.IsInside then (1 - current) ^ (1 / 3) else 1 - (1 - current) ^ (1 / 3)
	local seconds = if tag.IsInside then HIDE_SECONDS else SHOW_SECONDS
	tag.At = now - along * seconds
end

-- A source ignores a write of the value it holds, so a tag at rest costs its range check and nothing else.
local function follow()
	local now = os.clock()
	for _, tag in tags do
		if isInsideRange(tag.Root.Position) ~= tag.IsInside then turn(tag, now) end
		tag.Shown(shownBy(tag, now))
	end
end

HeadTagController.OnCharacterAdded = function(character: TCharacter.TCharacter)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end
	character.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	mount(character, player)
end :: TCharacterEvents.OnCharacterAdded

HeadTagController.OnCharacterRemoving = function(character: TCharacter.TCharacter)
	local tag = tags[character]
	if not tag then return end
	tags[character] = nil
	tag.Unmount()
end :: TCharacterEvents.OnCharacterRemoving

HeadTagController.OnPlayerDisconnected = function(player: Player)
	publics[player] = nil
end

ServerNetworkProfile.Public.On(
	function(player: Player, level: number, classId: number, trophies: number, deaths: number)
		if not player or player.Parent ~= Players then return end
		publicOf(player)({ Level = level, ClassId = classId, Trophies = trophies, Deaths = deaths })
	end
)

HeadTagController.OnStart = function()
	RunService.PreRender:Connect(follow)
end

return Ignis.Register(HeadTagController)
