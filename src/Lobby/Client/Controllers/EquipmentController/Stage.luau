--!nonstrict
-- The equipment page's middle (UIMatt.md, Equipment › Stage Container and Wearing Container), on his drawn rects at
-- 1080 with x from the screen's middle: the art behind the avatar (his rings, or the classes stage's Showcase look in
-- the picked piece's rarity), the floor, the player's avatar wearing what the page says it shows (avatarTurntable),
-- and WEARING with the three slots under it.
--
-- The avatar is a copy (init's takeAvatar) dressed here, so a piece put on or shown drops onto it the moment the server
-- answers, as EquipmentWearController drops it onto the body in the world, and the avatar cheers as it lands. The
-- pieces' motion runs on PreRender only while one moves.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Showcase = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Showcase)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local equipmentPieces = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Utils.equipmentPieces)
local avatarTurntable = require(script.Parent.Parent.Parent.Utils.avatarTurntable)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local EquipmentCore = require(ReplicatedStorage.GlobalShared.Core.EquipmentCore)
local Parts = require(script.Parent.Parts)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local source = vide.source
local Palette = Theme.Palette
local Progress = Motion.Progress
local Label = Parts.Label
local PIECES = DataCore.Equipment.ById

-- His drawn rects, x from the screen's middle: the rings' middle and radii, the floor, the avatar's frame (its top and
-- side, where the feet stand in it and how tall the body is); WEARING's top, and each slot's left, its top and size,
-- and inside a slot its word, its picture and the name of what it holds.
local Layout = table.freeze({
	RINGS_Y = 450,
	OUTER_RADIUS = 250,
	INNER_RADIUS = 180,
	SHOWCASE = 560,
	FLOOR_Y = 680,
	FLOOR_SIZE = Vector2.new(440, 80),
	EDGE = 2,
	VIEW_TOP = 210,
	VIEW = 500,
	FEET = 470,
	BODY = 380,
	-- WEARING and its slots stand in a box this wide and tall from this top, its middle the screen's.
	WEARING_BOX = Vector2.new(640, 300),
	WEARING_BOX_TOP = 710,
	WEARING_Y = 737,
	WEARING_TEXT = 29,
	SLOT_LEFTS = { -249, -75, 99 },
	SLOT_TOP = 780,
	SLOT = Vector2.new(150, 170),
	SLOT_WORD_Y = 14,
	SLOT_WORD_TEXT = 19,
	SLOT_PICTURE = Vector2.new(75, 82),
	SLOT_PICTURE_BOX = 92,
	SLOT_NAME_Y = 143,
	SLOT_NAME_TEXT = 13,
})

-- An empty slot's edge: his violet, this much of it kept.
local EMPTY_SHARE = 0.6

local Timing = table.freeze({
	-- The rings grow from this share of their size as the page comes up, the avatar rises this far (px).
	RINGS_FROM = 0.85,
	AVATAR_FROM = 30,
	AVATAR_DELAY = 0.06,
	-- WEARING and its slots come in after the grid's cards begin, one after another; as the screen shuts they sink this
	-- far (px), as his EXIT does.
	WEARING = 0.14,
	WEARING_IN = 0.3,
	SINK = 170,
	-- A change answered this recently was the hand's: the stage plays it. Older (a copy just taken), it is set there.
	BY_HAND = 0.2,
	SLOT = 0.18,
	SLOT_STAGGER = 0.06,
	SLOT_IN = 0.34,
	-- A piece put in a slot: its picture falls in from this far over (px) and this much bigger, the slot flashes and
	-- throws one ring this far; taken out, the picture is flicked up and fades.
	DROP_FROM = 34,
	DROP_SCALE = 0.5,
	DROP = 0.32,
	FLASH = 0.4,
	RING = 0.5,
	RING_REACH = 22,
	LIFT = 0.24,
	LIFT_TO = 26,
})

local Stage = {}

type TDressed = {
	Item: any,
	Parts: { equipmentPieces.TPiece },
	At: number,
	IsLeaving: boolean,
	HasLanded: boolean,
}

-- Dresses the avatar copy in what the page says it shows, and keeps it dressed: a piece put on or shown by the hand
-- drops on and the avatar cheers as it lands; one taken off is flicked away. A copy just taken is dressed at once.
local function dress(state: Types.TEquipmentState, celebrate: () -> ())
	local dressed: { [number]: TDressed } = {}
	local moving: { TDressed } = {}
	local model: Model? = nil
	local folder: Folder? = nil
	local stepper: RBXScriptConnection? = nil

	local function destroy(entry: TDressed)
		for _, part in entry.Parts do
			part.Accessory:Destroy()
		end
	end

	-- The avatar's own accessories under the pieces on and still flicking off are hidden: a hat comes back once the
	-- helm that hid it is gone.
	local function cover()
		if not model then return end
		local attachments = {}
		local function mark(entry: TDressed)
			for _, part in entry.Parts do
				attachments[part.Attachment.Name] = true
			end
		end
		for _, entry in dressed do
			mark(entry)
		end
		for _, entry in moving do
			if entry.IsLeaving then mark(entry) end
		end
		equipmentPieces.CoverAvatar(model, attachments)
	end

	local function frame()
		local now = os.clock()
		for index = #moving, 1, -1 do
			local entry = moving[index]
			local elapsed = now - entry.At
			local isDone = true
			for _, part in entry.Parts do
				if not equipmentPieces.Step(part, elapsed, entry.IsLeaving) then isDone = false end
			end
			if not entry.IsLeaving and not entry.HasLanded and elapsed >= equipmentPieces.ARRIVE_SECONDS then
				entry.HasLanded = true
				celebrate()
			end
			if not isDone then continue end
			moving[index] = moving[#moving]
			moving[#moving] = nil
			if not entry.IsLeaving then continue end
			destroy(entry)
			cover()
		end
		if #moving == 0 and stepper then
			stepper:Disconnect()
			stepper = nil
		end
	end

	local function move(entry: TDressed)
		entry.At = os.clock()
		if not table.find(moving, entry) then table.insert(moving, entry) end
		if not stepper then stepper = RunService.PreRender:Connect(frame) end
	end

	local function putOn(item, isMoved: boolean): TDressed?
		if not model or not folder then return nil end
		local parts = {}
		for _, accessory in equipmentPieces.Clone(item) do
			local part = equipmentPieces.Attach(model, accessory, folder)
			if part then
				table.insert(parts, part)
			else
				accessory:Destroy()
			end
		end

		local entry: TDressed = { Item = item, Parts = parts, At = 0, IsLeaving = false, HasLanded = not isMoved }
		if isMoved then
			for _, part in parts do
				equipmentPieces.Step(part, 0, false)
			end
			move(entry)
		end

		return entry
	end

	local function clear()
		for _, entry in dressed do
			destroy(entry)
		end
		for _, entry in moving do
			destroy(entry)
		end
		table.clear(dressed)
		table.clear(moving)
	end

	vide.effect(function()
		local copy = state.Avatar()
		local equipped, hidden = state.Equipped(), state.Hidden()
		vide.untrack(function()
			if copy ~= model then
				clear()
				model = copy
				folder = nil
				if copy then
					folder = Instance.new("Folder")
					folder.Name = "Equipment"
					folder.Parent = copy
				end
			end
			if not model then return end

			-- A piece changed by the hand moves; anything else (a copy just taken, a Sync) is set straight there.
			local isByHand = os.clock() - state.ChangedAt() < Timing.BY_HAND
			local wanted = {}
			for _, itemId in equipped do
				if not hidden[itemId] then wanted[itemId] = PIECES[itemId] end
			end
			for itemId, entry in dressed do
				if wanted[itemId] then continue end
				dressed[itemId] = nil
				if isByHand then
					entry.IsLeaving = true
					move(entry)
				else
					destroy(entry)
				end
			end
			for itemId, item in wanted do
				if dressed[itemId] then continue end
				dressed[itemId] = putOn(item, isByHand)
			end
			cover()
		end)
	end)

	vide.cleanup(function()
		clear()
		if stepper then stepper:Disconnect() end
	end)
end

-- One slot of WEARING: his card in the worn piece's rarity (his dim violet empty), its slot's word, the piece's picture
-- and name, or EMPTY. A piece put in falls into it and the slot flashes and throws one ring; one taken out is flicked
-- up. Pressing it picks the piece it holds, or its slot's pieces when it is empty.
local function slot(state: Types.TEquipmentState, actions: Types.TEquipmentActions, index: number, away: () -> number)
	local slotName = EquipmentCore.SLOTS[index]
	local hand = Hand.React("Operate")
	local dealt = Parts.Dealt(state, Timing.SLOT + Timing.SLOT_STAGGER * (index - 1), Timing.SLOT_IN)
	local landed = Parts.Landing(state, Timing.SLOT + Timing.SLOT_STAGGER * (index - 1))
	local worn = derive(function(): number
		return state.Equipped()[slotName] or 0
	end)
	local wornItem = function()
		return PIECES[worn()]
	end
	-- The piece last in this slot, held while its picture is flicked away.
	local shownItem = source(worn())
	vide.effect(function()
		local itemId = worn()
		vide.untrack(function()
			if itemId ~= 0 then shownItem(itemId) end
		end)
	end)
	local isMine = derive(function(): boolean
		local item = PIECES[state.ChangedItem()]
		return item ~= nil and item.Slot == slotName
	end)
	-- 0 to 1 as a piece falls in; 1 otherwise.
	local dropped = derive(function(): number
		if not isMine() or state.Change() ~= "Equip" then return 1 end
		return Progress(state.Now(), state.ChangedAt(), Timing.DROP)
	end)
	-- 0 to 1 as a piece is flicked out; 1 once it is gone, 0 while one is in.
	local lifted = derive(function(): number
		if worn() ~= 0 then return 0 end
		if not isMine() or state.Change() ~= "Unequip" then return 1 end
		return Progress(state.Now(), state.ChangedAt(), Timing.LIFT)
	end)
	local flash = derive(function(): number
		if not isMine() or state.Change() ~= "Equip" then return 0 end
		return Motion.Fade(state.Now(), state.ChangedAt(), Timing.FLASH)
	end)
	local ring = derive(function(): number
		if not isMine() or state.Change() ~= "Equip" then return 1 end
		return Progress(state.Now(), state.ChangedAt(), Timing.RING)
	end)
	local accent = derive(function(): Color3
		local item = wornItem()
		return if item then Parts.RARITIES[item.Rarity].Accent else Parts.Shade(Palette.Violet, EMPTY_SHARE)
	end)
	local size = Layout.SLOT

	return Components.Button({
		Name = slotName,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.new(
				0.5,
				Layout.SLOT_LEFTS[index] + size.X / 2,
				0,
				Layout.SLOT_TOP - Layout.WEARING_BOX_TOP + size.Y / 2 + math.round(Timing.SINK * away())
			)
		end,
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Activated = function()
			hand.Commit()
			local item = wornItem()
			if item then
				actions.Select(item.Id)
			else
				actions.Filter(slotName)
			end
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return Motion.Decelerate(dealt()) * hand.Scale()
			end,
		}),
		create("Frame")({
			Name = "Burst",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = function()
				local grow = math.round(Timing.RING_REACH * Motion.Out(ring()))
				return UDim2.new(1, 2 * grow, 1, 2 * grow)
			end,
			BackgroundTransparency = 1,
			Visible = function()
				return ring() < 1
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
			create("UIStroke")({ Color = accent, Thickness = 3, Transparency = ring }),
		}),
		Components.Card({
			Accent = function()
				return Parts.EdgeOf(accent())
			end,
			Glow = accent,
			GlowTransparency = function()
				return 0.75 - 0.35 * math.max(hand.Light(), flash())
			end,
			Tint = function()
				return if worn() ~= 0 then 0.35 else 0.15
			end,
			Marks = true,
			Brackets = hand.Rise,
			BracketLength = 20,
			BracketTransparency = function()
				return 0.6 - 0.3 * hand.Light()
			end,
		}, {
			Name = "Card",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 3, 2),
			Components.Sheen(Hand.Sheen(hand, landed), 3),
			Label({
				Name = "Word",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromOffset(size.X / 2, Layout.SLOT_WORD_Y),
				Size = UDim2.fromOffset(size.X, Layout.SLOT_WORD_TEXT),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextSize = Layout.SLOT_WORD_TEXT,
				TextColor3 = function()
					return if worn() ~= 0 then Palette.White else Palette.Lavender
				end,
				Text = string.upper(slotName),
			}),
			Parts.Picture(shownItem, {}, {
				Name = "Picture",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = function()
					local fall = Timing.DROP_FROM * (1 - dropped()) ^ 2
					local rise = Timing.LIFT_TO * Motion.Out(lifted())
					return UDim2.fromOffset(Layout.SLOT_PICTURE.X, Layout.SLOT_PICTURE.Y - math.round(fall + rise))
				end,
				Size = UDim2.fromOffset(Layout.SLOT_PICTURE_BOX, Layout.SLOT_PICTURE_BOX),
				Visible = function()
					return lifted() < 1
				end,
				ZIndex = 4,
				create("UIScale")({
					Scale = function()
						local grown = 1 + Timing.DROP_SCALE * (1 - Motion.Decelerate(dropped()))
						return grown * (1 - 0.4 * lifted()) * (1 + 0.08 * hand.Rise())
					end,
				}),
			}),
			Label({
				Name = "Held",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromOffset(size.X / 2, Layout.SLOT_NAME_Y),
				Size = UDim2.fromOffset(size.X - 16, Layout.SLOT_NAME_TEXT),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextScaled = true,
				TextColor3 = function()
					return if worn() ~= 0 then Palette.White else Palette.Lavender
				end,
				Text = function()
					local item = wornItem()
					return if item then string.upper(item.Name) else "EMPTY"
				end,
				create("UITextSizeConstraint")({ MaxTextSize = Layout.SLOT_NAME_TEXT }),
			}),
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 7,
				Visible = function()
					return flash() > 0.01
				end,
				BackgroundTransparency = function()
					return 1 - 0.7 * flash()
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			}),
		}),
	}) :: TextButton
end

function Stage.Build(state: Types.TEquipmentState, actions: Types.TEquipmentActions): { Instance }
	local look = Showcase.Looks.Equipment
	local isRings = look == "Rings"
	local shown = Parts.Shown(state)
	local away = Parts.Away(state)
	local body = Parts.Shown(state, Timing.AVATAR_DELAY)
	local isActive = function(): boolean
		return state.IsShown()
	end
	local view, celebrate = avatarTurntable.Build({
		Avatar = state.Avatar,
		IsActive = isActive,
		Shown = function(): number
			return body() * (1 - away())
		end,
		Frame = {
			ViewTop = Layout.VIEW_TOP,
			View = Layout.VIEW,
			Feet = Layout.FEET,
			Body = Layout.BODY,
			FloorY = Layout.FLOOR_Y,
			FloorSize = Layout.FLOOR_SIZE,
			Edge = Layout.EDGE,
			RiseFrom = Timing.AVATAR_FROM,
		},
		HasFloorRing = isRings,
	})
	dress(state, celebrate)

	local art = function(): number
		return shown() * (1 - away())
	end
	local grown = function(): number
		return Timing.RINGS_FROM + (1 - Timing.RINGS_FROM) * art()
	end
	-- The art cheers as a piece is put on: a reveal, as the weapons stage's does for a purchase.
	local cheeredAt = derive(function(): number
		return if state.Change() == "Equip" then state.ChangedAt() else -math.huge
	end)
	local accent = function(): Color3
		local item = PIECES[state.Selected()]
		return if item then Parts.RARITIES[item.Rarity].Accent else Palette.Grey
	end

	local back, front = avatarTurntable.Art({
		Look = look,
		RingsY = Layout.RINGS_Y,
		OuterRadius = Layout.OUTER_RADIUS,
		InnerRadius = Layout.INNER_RADIUS,
		Diameter = Layout.SHOWCASE,
		FloorY = Layout.FLOOR_Y,
		FloorSize = Layout.FLOOR_SIZE,
		Edge = Layout.EDGE,
		Shown = art,
		Grown = grown,
		Accent = accent,
		CheeredAt = cheeredAt,
		IsActive = isActive,
	})

	local wearingIn = Parts.Dealt(state, Timing.WEARING, Timing.WEARING_IN)
	local slots = table.create(#EquipmentCore.SLOTS)
	for index in EquipmentCore.SLOTS do
		slots[index] = slot(state, actions, index, away)
	end

	return {
		create("Frame")({
			Name = "Stage",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 2,
			back,
			view,
			front,
		}),
		create("Frame")({
			Name = "Wearing",
			BackgroundTransparency = 1,
			Visible = Parts.ArePanelsUp(state),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, Layout.WEARING_BOX_TOP),
			Size = UDim2.fromOffset(Layout.WEARING_BOX.X, Layout.WEARING_BOX.Y),
			ZIndex = 3,
			Label({
				Name = "Wearing",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = function()
					return UDim2.new(
						0.5,
						0,
						0,
						Layout.WEARING_Y - Layout.WEARING_BOX_TOP + math.round(Timing.SINK * away())
					)
				end,
				Size = UDim2.fromOffset(300, Layout.WEARING_TEXT),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextSize = Layout.WEARING_TEXT,
				TextTransparency = function()
					return 1 - Motion.Out(wearingIn())
				end,
				Text = "WEARING",
			}),
			slots,
		}),
	}
end

return Stage
