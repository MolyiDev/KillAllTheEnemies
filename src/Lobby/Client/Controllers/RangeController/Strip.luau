--!nonstrict
-- The range's strip of guns across the bottom, in the match hotbar's look (UIMatt.md, Hotbar): the guns the range
-- offers (state.Shown: the player's loadout, one a tier, or only the gun TRY brought), each on its rarity's card with
-- its number key in the corner. The one in hand stands raised in a white frame, its name stamped over the strip. A
-- click or its number picks one. The strip rises in slot by slot from the middle out as the player walks into the
-- range or a lobby screen over it shuts, and drops away as they leave or one opens (state.IsUp).
--
-- Also the cover drawn over TRY's trip to the range, so the player is not seen sliding across the lobby.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local GunPicture = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.GunPicture)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Parts = require(script.Parent.Parent.WeaponsController.Parts)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local LoadoutCore = require(ReplicatedStorage.GlobalShared.Core.LoadoutCore)
local TData = require(ReplicatedStorage.Types.TData)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local spring = vide.spring
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress

-- Design px at 1080, x from the screen's middle. A slot is the hotbar's: 96 square, its key in the corner.
local Layout = table.freeze({
	SLOT = 96,
	GAP = 14,
	-- Over the lobby HUD's WEAPONS / PLAY / CLASSES row, which stays up in the range: PLAY reaches 189 up
	-- (LobbyController/Hud: SLAB_BOTTOM 70, SLAB_SIZE.Y 101 and brackets 5 at its 1.12), and the slot in hand grows
	-- below its own.
	BOTTOM = 217,
	KEY = 4,
	KEY_SIZE = 24,
	-- The gun in hand: this much bigger, raised, and framed this far off its edge.
	HELD_SCALE = 1.2,
	HELD_LIFT = 14,
	HELD_OUTSET = 4,
	GUN_SHARE = 0.95,
	GUN_TILT = -30,
	-- The name over the strip and the rarity word over the name.
	NAME_TEXT = 40,
	NAME_UP = 44,
	RARITY_TEXT = 20,
})

local Timing = table.freeze({
	-- Each slot rises in over ARRIVE, this much later per slot out from the middle, from this far down; all of them
	-- drop away over LEAVE.
	ARRIVE = 0.42,
	STAGGER = 0.05,
	RISE = 150,
	LEAVE = 0.24,
	-- A pick: the slot in hand is punched and its gun swings; the name lands from this much bigger and white.
	SWAP = 0.4,
	SWAP_PUNCH = 0.16,
	SWAP_SPIN = 14,
	NAME_IN = 0.28,
	NAME_FROM = 1.35,
	-- The cover closes over this long and opens again over this long.
	COVER_IN = 0.14,
	COVER_OUT = 0.4,
})

-- The slot in hand rises on a spring that rings a little past its mark: the overshoot is the punch.
local HELD_PERIOD = 0.24
local HELD_DAMPING = 0.55
local DIM = Color3.fromRGB(176, 172, 190)

local GUNS = DataCore.Guns.ById
-- A slot's step along the strip.
local PITCH = Layout.SLOT + Layout.GAP

local Strip = {}

-- The number that picks each slot, left to right; the strip holds at most one gun a tier.
Strip.SLOT_KEYS = table.freeze({ Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four })
-- A pad's bumpers step through the slots.
Strip.PREVIOUS_KEY = Enum.KeyCode.ButtonL1
Strip.NEXT_KEY = Enum.KeyCode.ButtonR1
Strip.COVER_IN = Timing.COVER_IN
-- Every gesture is over this long after its stamp.
Strip.SETTLED = Timing.ARRIVE + Timing.STAGGER * LoadoutCore.TIERS + Timing.COVER_OUT
-- The widest strip, design px, the slot in hand grown: a screen narrower than this shrinks it to fit.
Strip.WIDTH = LoadoutCore.TIERS * PITCH - Layout.GAP + Layout.SLOT * (Layout.HELD_SCALE - 1)

local function rarityOf(gunId: number): typeof(Parts.RARITIES.Common)
	local gun = GUNS[gunId]
	return if gun then Parts.RARITIES[gun.Rarity] else Parts.RARITIES.Common
end

-- 0 in place, 1 gone: slots rise in from the middle out, and leave together.
local function awayOf(state: Types.TRangeState, delay: number): () -> number
	return derive(function(): number
		local now = state.Now()
		local at = state.UpAt()
		if state.IsUp() then return 1 - Motion.Decelerate(Progress(now, at, Timing.ARRIVE, delay)) end
		return Motion.Accelerate(Progress(now, at, Timing.LEAVE))
	end)
end

-- A white frame standing `outset` off the slot's edge, as the hotbar frames the slot in hand.
local function frameRound(transparency: () -> number): Frame
	local reach = 2 * Layout.HELD_OUTSET
	return create("Frame")({
		Name = "Held",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, reach, 1, reach),
		BackgroundTransparency = 1,
		Visible = function()
			return transparency() < 0.99
		end,
		create("UIStroke")({
			Color = Palette.White,
			Thickness = 2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Transparency = transparency,
		}),
		create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
	})
end

-- The slot at `index` of what is shown: its gun may change under it as the offer does.
local function slot(
	state: Types.TRangeState,
	actions: Types.TRangeActions,
	gunId: () -> number,
	index: number
): TextButton
	local hand = Hand.React("Operate")
	local count = derive(function(): number
		return #state.Shown()
	end)
	local accent = derive(function(): Color3
		return rarityOf(gunId()).Accent
	end)
	local away = awayOf(state, math.abs(index - (LoadoutCore.TIERS + 1) / 2) * Timing.STAGGER)
	local isHeld = derive(function(): boolean
		return state.Held() == gunId()
	end)
	local held = spring(function(): number
		return if isHeld() then 1 else 0
	end, HELD_PERIOD, HELD_DAMPING)
	-- 0 to 1 through the pick that put this gun in hand; 1 at rest, and on every other slot.
	local swapped = derive(function(): number
		if not isHeld() then return 1 end
		return Progress(state.Now(), state.HeldAt(), Timing.SWAP)
	end)
	local punch = function(): number
		local k = 1 - swapped()
		return k * k
	end

	return Components.Button({
		Name = `Slot{index}`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(Layout.SLOT, Layout.SLOT),
		BackgroundTransparency = 1,
		ZIndex = function()
			return if isHeld() then 3 else 2
		end,
		Visible = function()
			return away() < 1
		end,
		Position = function()
			local x = (index - (count() + 1) / 2) * PITCH
			local lift = Layout.HELD_LIFT * held() - Timing.RISE * away()
			return UDim2.new(0.5, math.round(x), 1, math.round(-Layout.BOTTOM - Layout.SLOT / 2 - lift))
		end,
		Activated = function()
			hand.Commit()
			actions.Pick(gunId())
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				local grown = 1 + (Layout.HELD_SCALE - 1) * math.max(held(), 0)
				return grown * hand.Scale() * (1 + Timing.SWAP_PUNCH * punch())
			end,
		}),
		Components.Card({
			Accent = accent,
			Tint = function()
				return 0.2 + 0.35 * held()
			end,
			Marks = true,
			GlowTransparency = function()
				return 1 - math.clamp(0.75 * held() + 0.4 * hand.Light() + 0.25 * punch(), 0, 1)
			end,
		}, {
			Name = "Card",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			frameRound(function()
				return 1 - 0.91 * math.clamp(held(), 0, 1)
			end),
			GunPicture.Build(function()
				return GunPicture.FromGun(gunId())
			end, {
				Lean = -Layout.GUN_TILT,
				Rotation = function()
					return Timing.SWAP_SPIN * Motion.Swing(if isHeld() then swapped() else 1)
				end,
				Tint = function()
					return DIM:Lerp(Palette.White, math.clamp(held() + hand.Light(), 0, 1))
				end,
			}, {
				Name = "Gun",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(Layout.GUN_SHARE, Layout.GUN_SHARE),
				ZIndex = 2,
				create("UIScale")({
					Scale = function()
						return 1 + 0.1 * hand.Rise() + 0.12 * punch()
					end,
				}),
			}),
			-- Its number, when there is more than one to pick between.
			Components.KeyBadge(Strip.SLOT_KEYS[index], Layout.KEY_SIZE, {
				Position = UDim2.fromOffset(Layout.KEY, Layout.KEY),
				Visible = function()
					return count() > 1
				end,
				ZIndex = 6,
			}),
			Hand.WashLayer(hand, 3, 3),
			Components.Sheen(function()
				return if isHeld() then swapped() else hand.Glint()
			end, 4),
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 5,
				BackgroundTransparency = function()
					return 1 - 0.55 * punch()
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
			}),
		}),
	}) :: TextButton
end

-- The gun in hand's name and rarity, landing big and white on every pick.
local function title(state: Types.TRangeState): Frame
	local away = awayOf(state, 0)
	local gun = derive(function(): TData.TGun?
		return GUNS[state.Held()]
	end)
	local rarity = derive(function()
		return rarityOf(state.Held())
	end)
	local landed = derive(function(): number
		return Progress(state.Now(), state.HeldAt(), Timing.NAME_IN)
	end)

	return create("Frame")({
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(900, Layout.NAME_TEXT + Layout.RARITY_TEXT + 4),
		BackgroundTransparency = 1,
		Visible = function()
			return gun() ~= nil and away() < 1
		end,
		Position = function()
			local top = Layout.BOTTOM + Layout.SLOT + Layout.NAME_UP
			return UDim2.new(0.5, 0, 1, math.round(-top + Timing.RISE * away()))
		end,
		create("UIScale")({
			Scale = function()
				return Motion.Lerp(Timing.NAME_FROM, 1, Motion.Decelerate(landed()))
			end,
		}),
		create("TextLabel")({
			Name = "Rarity",
			Size = UDim2.new(1, 0, 0, Layout.RARITY_TEXT),
			BackgroundTransparency = 1,
			FontFace = Font.Display,
			TextSize = Layout.RARITY_TEXT,
			TextColor3 = function()
				return rarity().Accent
			end,
			Text = function()
				return rarity().Text
			end,
			create("UIStroke")({ Color = Palette.Ink, Thickness = 2 }),
		}),
		create("TextLabel")({
			Name = "Name",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, Layout.NAME_TEXT),
			BackgroundTransparency = 1,
			FontFace = Font.Display,
			TextSize = Layout.NAME_TEXT,
			TextColor3 = function()
				return Palette.White:Lerp(rarity().Accent, 0.15 * landed())
			end,
			Text = function()
				local current = gun()
				return if current then string.upper(current.Name) else ""
			end,
			create("UIStroke")({
				Color = Palette.Ink,
				Thickness = math.max(2, math.round(Layout.NAME_TEXT * Theme.INK_SHARE)),
			}),
		}),
	})
end

function Strip.Build(state: Types.TRangeState, actions: Types.TRangeActions): Frame
	return create("Frame")({
		Name = "Strip",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		title(state),
		vide.indexes(state.Shown, function(gunId: () -> number, index: number): TextButton
			return slot(state, actions, gunId, index)
		end),
	})
end

-- The ink drawn over TRY's trip: closing fast, opening slower once the player stands in the range.
function Strip.Cover(state: Types.TRangeState): Frame
	local transparency = derive(function(): number
		local now = state.Now()
		if state.CoverAt() > state.UncoverAt() then
			return 1 - Motion.Out(Progress(now, state.CoverAt(), Timing.COVER_IN))
		end
		return Motion.Accelerate(Progress(now, state.UncoverAt(), Timing.COVER_OUT))
	end)

	return create("Frame")({
		Name = "Cover",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.Ink,
		BorderSizePixel = 0,
		BackgroundTransparency = transparency,
		Visible = function()
			return transparency() < 1
		end,
	})
end

return Strip
