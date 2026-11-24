--!nonstrict
-- The padlock over something still locked (an index card, a map on the party screen), the two parts split_lock.py cut
-- from the Lock picture, and its opening: it shakes in its hasp, the shackle clicks up out of its sockets and swings open
-- on its long leg, the body jumps at the click, and it all rises, swells and fades.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local Progress = Motion.Progress

-- Seconds into the opening unless named otherwise.
local Open = table.freeze({
	SHAKE = 0.2,
	SHAKE_DEGREES = 12,
	-- The click, as the shake ends.
	CLICK = 0.2,
	LIFT = 0.1,
	-- How far the shackle lifts and turns, as a share of the padlock's box and in degrees (anticlockwise).
	LIFT_SHARE = 0.07,
	SWING_DELAY = 0.04,
	SWING = 0.22,
	SWING_DEGREES = -22,
	JUMP = 0.18,
	JUMP_GROW = 0.16,
	-- It blows away from LEAVE_AT over LEAVE, rising a share of its picture's longer side.
	LEAVE_AT = 0.5,
	LEAVE = 0.3,
	LEAVE_RISE = 18 / 80,
	LEAVE_GROW = 0.35,
	LEAVE_DEGREES = -8,
})
-- The shackle's long leg's foot, which it swings on, from the box's middle as a share of its side (split_lock.py's
-- lock.png pixels 305, 453 of 1024), and the shackle's middle from that foot.
local SHACKLE_PIVOT = Vector2.new(305 / 1024 - 0.5, 453 / 1024 - 0.5)
local SHACKLE_FROM_PIVOT = -SHACKLE_PIVOT

local padlock = {}

-- When in the opening the shackle clicks (the unlock sound goes then), and when the padlock starts to blow away.
padlock.CLICK_SECONDS = Open.CLICK
padlock.OPEN_SECONDS = Open.LEAVE_AT
padlock.SECONDS = Open.LEAVE_AT + Open.LEAVE

-- `Unlocking` is seconds into its opening (0 shut); `Turn` (degrees) and `Grow` (a share of its size, nil for none) are
-- the caller's own on top of it, a rattle or the hand's rise. Placed by its middle at `At`, its picture `Longest` px.
function padlock.Build(props: {
	Unlocking: () -> number,
	Turn: () -> number,
	Grow: (() -> number)?,
	At: Vector2,
	Longest: number,
	ZIndex: number,
}): Frame
	local unlocking = props.Unlocking
	local grow = props.Grow
	local at = props.At
	local rise = Open.LEAVE_RISE * props.Longest
	-- 0 to 1 as it blows away, and how far it has faded.
	local leaving = derive(function(): number
		return Progress(unlocking(), Open.LEAVE_AT, Open.LEAVE)
	end)
	local faded = derive(function(): number
		return Motion.Out(leaving())
	end)
	local box = Components.PictureBox(props.Longest)
	local side = box.X.Offset
	local shake = function(): number
		return Open.SHAKE_DEGREES * Motion.Swing(Progress(unlocking(), 0, Open.SHAKE))
	end
	local lift = function(): number
		return Open.LIFT_SHARE * side * Motion.OutBack(Progress(unlocking(), Open.CLICK, Open.LIFT))
	end
	local swing = function(): number
		local swung = Progress(unlocking(), Open.CLICK + Open.SWING_DELAY, Open.SWING)
		return Open.SWING_DEGREES * Motion.OutBack(swung)
	end

	return create("Frame")({
		Name = "Lock",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(at.X, at.Y - rise * Motion.Decelerate(leaving()))
		end,
		Size = box,
		Rotation = function()
			return shake() + props.Turn() + Open.LEAVE_DEGREES * faded()
		end,
		BackgroundTransparency = 1,
		-- Taken out only once it has faded away; derived, so it is written once, not every frame of the fade.
		Visible = derive(function(): boolean
			return leaving() < 1
		end),
		ZIndex = props.ZIndex,
		create("UIScale")({
			Scale = function()
				local jump = Open.JUMP_GROW * Motion.Bump(Progress(unlocking(), Open.CLICK, Open.JUMP))
				return 1 + (if grow then grow() else 0) + jump + Open.LEAVE_GROW * faded()
			end,
		}),
		Components.Picture(EIcons.LockBody, {
			Name = "Body",
			Size = UDim2.fromScale(1, 1),
			ImageTransparency = faded,
		}),
		-- A GuiObject turns about its own middle, so swinging on the long leg's foot moves the middle round that foot.
		Components.Picture(EIcons.LockShackle, {
			Name = "Shackle",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				local radians = math.rad(swing())
				local cos, sin = math.cos(radians), math.sin(radians)
				local out = SHACKLE_FROM_PIVOT
				local turned = Vector2.new(out.X * cos - out.Y * sin, out.X * sin + out.Y * cos)
				local offset = (SHACKLE_PIVOT + turned) * side
				return UDim2.new(0.5, offset.X, 0.5, offset.Y - lift())
			end,
			Size = UDim2.fromScale(1, 1),
			Rotation = swing,
			ImageTransparency = faded,
			ZIndex = 2,
		}),
	})
end

return padlock
