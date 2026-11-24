-- The equipment's rules, the same on both sides: one piece a slot, the EarlyUnlock pieces owned by everybody and worn
-- until a slot is emptied by hand, what the worn pieces add, and how each piece's numbers and origin are written. The
-- profile keeps pieces by Name (TProfile.Equipment); the wire carries their Ids.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataCore = require(script.Parent.DataCore)
local ERarities = require(ReplicatedStorage.Types.Enums.ERarities)
local TData = require(ReplicatedStorage.Types.TData)
local TProfile = require(ReplicatedStorage.Types.TProfile)

type TEquipment = TData.TEquipment
type TSave = TProfile.TEquipmentSave

-- How each stat is written on a stat row: the number (a share as a percentage) and its words.
local STAT_TEXT = table.freeze({
	MaxHealth = function(value: number): (string, string)
		return `+{math.round(value)}`, "MAX HP"
	end,
	Armor = function(value: number): (string, string)
		return `-{math.round(value * 100)}%`, "DAMAGE TAKEN"
	end,
	KillGold = function(value: number): (string, string)
		return `+{math.round(value * 100)}%`, "GOLD FROM KILLS"
	end,
})

local EquipmentCore = {}

EquipmentCore.SLOTS = table.freeze({ "Head", "Torso", "Legs" } :: { TData.TEquipmentSlot })
-- A save with nothing in it: what a profile holds before its first change.
EquipmentCore.EMPTY = table.freeze({
	Owned = table.freeze({}),
	Equipped = table.freeze({}),
	Hidden = table.freeze({}),
}) :: TSave

EquipmentCore.ByName = {} :: { [string]: TEquipment }
-- Every piece in the order the screen deals them: by rarity, then by slot, then by Id.
EquipmentCore.All = table.clone(DataCore.Equipment.All) :: { TEquipment }
-- Each slot's pieces in that order, and the EarlyUnlock piece a slot holds until it is emptied by hand.
EquipmentCore.BySlot = {} :: { [string]: { TEquipment } }
EquipmentCore.Starters = {} :: { [string]: TEquipment }

local function slotIndex(slot: string): number
	return table.find(EquipmentCore.SLOTS, slot :: any) or 0
end

table.sort(EquipmentCore.All, function(a: TEquipment, b: TEquipment): boolean
	if a.Rarity ~= b.Rarity then return ERarities[a.Rarity] < ERarities[b.Rarity] end
	if a.Slot ~= b.Slot then return slotIndex(a.Slot) < slotIndex(b.Slot) end
	return a.Id < b.Id
end)
for _, slot in EquipmentCore.SLOTS do
	EquipmentCore.BySlot[slot] = {}
end
for _, item in EquipmentCore.All do
	EquipmentCore.ByName[item.Name] = item
	table.insert(EquipmentCore.BySlot[item.Slot], item)
	if item.EarlyUnlock and not EquipmentCore.Starters[item.Slot] then EquipmentCore.Starters[item.Slot] = item end
end
table.freeze(EquipmentCore.All)
table.freeze(EquipmentCore.ByName)
table.freeze(EquipmentCore.BySlot)
table.freeze(EquipmentCore.Starters)

-- The most MaxHealth worn pieces can add together: the best of each slot.
EquipmentCore.MOST_MAX_HEALTH = 0
for _, slot in EquipmentCore.SLOTS do
	local best = 0
	for _, item in EquipmentCore.BySlot[slot] do
		for _, bonus in item.Stats do
			if bonus.Stat == "MaxHealth" then best = math.max(best, bonus.Value) end
		end
	end
	EquipmentCore.MOST_MAX_HEALTH += best
end

-- A profile's save, or the empty one when it has none yet.
function EquipmentCore.SaveOf(save: TSave?): TSave
	return save or EquipmentCore.EMPTY
end

function EquipmentCore.IsOwned(save: TSave, item: TEquipment): boolean
	return item.EarlyUnlock == true or save.Owned[item.Name] == true
end

-- The piece a slot holds, nil for none. A slot never picked holds its EarlyUnlock piece; one emptied by hand holds "".
function EquipmentCore.EquippedOf(save: TSave, slot: string): TEquipment?
	local name = save.Equipped[slot]
	if name == "" then return nil end
	local item = if name then EquipmentCore.ByName[name] else EquipmentCore.Starters[slot]
	if not item or item.Slot ~= slot or not EquipmentCore.IsOwned(save, item) then return nil end
	return item
end

function EquipmentCore.IsEquipped(save: TSave, item: TEquipment): boolean
	return EquipmentCore.EquippedOf(save, item.Slot) == item
end

function EquipmentCore.IsShown(save: TSave, item: TEquipment): boolean
	return save.Hidden[item.Name] ~= true
end

-- What the worn pieces add to `stat` together; 0 with none.
function EquipmentCore.StatOf(save: TSave, stat: TData.TEquipmentStat): number
	local total = 0
	for _, slot in EquipmentCore.SLOTS do
		local item = EquipmentCore.EquippedOf(save, slot)
		if not item then continue end
		for _, bonus in item.Stats do
			if bonus.Stat == stat then
				total += bonus.Value
			end
		end
	end

	return total
end

-- A bonus as a stat row writes it: the number, then its words.
function EquipmentCore.StatText(bonus: TData.TEquipmentBonus): (string, string)
	return STAT_TEXT[bonus.Stat](bonus.Value)
end

-- Who hands a piece out, in capitals: the boss that drops it, or nil for a piece everybody has.
function EquipmentCore.SourceOf(item: TEquipment): string?
	local drop = item.Drop
	local enemy = if drop then DataCore.Enemies.ById[drop.Enemy] else nil
	return if enemy then string.upper(enemy.Name) else nil
end

-- Where a piece comes from, as the screen's ? says it.
function EquipmentCore.WhereFrom(item: TEquipment): string
	if item.EarlyUnlock then return "Every player starts with one." end
	local drop = item.Drop
	local source = EquipmentCore.SourceOf(item)
	if not drop or not source then return "Not obtainable yet." end
	return `Drops from the {source} ({math.round(drop.Chance * 100)}% chance).`
end

return table.freeze(EquipmentCore)
