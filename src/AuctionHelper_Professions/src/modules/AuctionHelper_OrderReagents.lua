local _, AuctionHelper = ...

-- Pure reading of crafting-order reagents. Blizzard hands out several entry shapes
-- (order reagents, schematic reagents, UI reagent infos); each field is read from the first shape that has it.
local OrderReagents = {}
AuctionHelper.OrderReagents = OrderReagents

local ENTRY = {}
local SLOT_PATHS = { { "reagent" }, { "reagent", "reagent" }, { "reagentInfo" }, { "reagentInfo", "reagent" }, ENTRY, { "reagentSlot" } }
local CURRENCY_PATHS = { { "reagent", "reagent" }, { "reagent" }, { "reagentInfo", "reagent" }, { "reagentInfo" } }
local ITEM_PATHS = { { "reagent", "reagent" }, { "reagent" }, { "reagentInfo", "reagent" }, { "reagentInfo" }, ENTRY }
local QUANTITY_PATHS = { ENTRY, { "reagent" }, { "reagentInfo" }, { "reagentSlot" } }

local function nodeAt(entry, path)
	local node = entry
	for _, step in ipairs(path) do
		node = type(node) == "table" and node[step] or nil
	end
	return type(node) == "table" and node or nil
end

local function firstField(entry, paths, key)
	for _, path in ipairs(paths) do
		local node = nodeAt(entry, path)
		if node and node[key] then
			return node[key]
		end
	end
	return nil
end

--- Flat view of one order reagent entry: source, dataSlotIndex, dataSlotType, itemID, currencyID, quantity.
function OrderReagents.Describe(entry)
	if not entry then
		return { quantity = 0 }
	end
	return {
		source = entry.source,
		dataSlotIndex = tonumber(firstField(entry, SLOT_PATHS, "dataSlotIndex")),
		dataSlotType = tonumber(firstField(entry, SLOT_PATHS, "dataSlotType")),
		itemID = tonumber(firstField(entry, ITEM_PATHS, "itemID")),
		currencyID = tonumber(firstField(entry, CURRENCY_PATHS, "currencyID")),
		quantity = tonumber(firstField(entry, QUANTITY_PATHS, "quantity")) or 0,
	}
end

--- A schematic slot the crafter has to fill: required, or a basic reagent, never optional.
function OrderReagents.CrafterFillsSlot(slot, basicReagentType)
	if type(slot) ~= "table" or (tonumber(slot.quantityRequired) or 0) <= 0 or slot.optional == true then
		return false
	end
	return slot.required == true or (basicReagentType ~= nil and tonumber(slot.reagentType) == basicReagentType)
end

local function firstSlotItem(slot, skipItems)
	for _, reagent in ipairs(slot.reagents or {}) do
		local itemID = tonumber(reagent and reagent.itemID)
		if itemID and not (skipItems and skipItems[itemID]) then
			return itemID
		end
	end
	return nil
end

--- Item to buy for a slot: prefer one the customer did not already send.
function OrderReagents.PickShoppingItem(slot, providedItems)
	return firstSlotItem(slot, providedItems) or firstSlotItem(slot, nil)
end

--- itemID -> quantity still to buy, given the schematic slots and what the customer provided per slot.
function OrderReagents.RemainingShoppingTotals(slotLookup, providedBySlot, basicReagentType)
	local totals = {}
	for slotIndex, slot in pairs(slotLookup) do
		local provided = providedBySlot[tonumber(slotIndex)]
		local remaining = math.max(0, (tonumber(slot.quantityRequired) or 0) - (tonumber(provided and provided.quantity) or 0))
		if remaining > 0 and OrderReagents.CrafterFillsSlot(slot, basicReagentType) then
			local itemID = OrderReagents.PickShoppingItem(slot, provided and provided.items)
			if itemID then
				totals[itemID] = (totals[itemID] or 0) + remaining
			end
		end
	end
	return totals
end
