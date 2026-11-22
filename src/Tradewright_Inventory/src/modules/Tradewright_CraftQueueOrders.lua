local _, Tradewright = ...

-- Crafting orders are retail-only; on WoW Forever the craft queue holds recipe lines only.
if not Tradewright.IS_RETAIL then
	return
end

-- Craft queue lines that mirror entries of the crafting-order queue, so their mats show on the shopping list.

function Tradewright:RemoveCraftQueueByOrderID(orderID)
	orderID = tonumber(orderID)
	if not orderID then
		return 0
	end
	local removed = 0
	local storage = self:GetCraftQueueStorage()
	for key, entry in pairs(storage) do
		if type(entry) == "table" and tonumber(entry.orderID) == orderID then
			storage[key] = nil
			removed = removed + 1
		end
	end
	if removed > 0 then
		self:NotifyCraftQueueChanged()
	end
	return removed
end

function Tradewright:CraftQueueMakeOrderKey(orderID)
	return string.format("craftingOrder|%s", tostring(orderID or ""))
end

local function isBlank(text)
	return not text or text == ""
end

local function resolveOrderRecipeName(self, orderEntry, recipeID, itemID)
	local recipeName = orderEntry.recipeName
	if isBlank(recipeName) and recipeID then
		local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
		recipeName = recipeInfo and recipeInfo.name or recipeName
	end
	if isBlank(recipeName) and itemID then
		recipeName = self:GetItemDisplayName(itemID)
	end
	return recipeName
end

local function resolveItemIcon(self, itemID)
	local descriptor = itemID and self.ResolveItemDescriptor and self:ResolveItemDescriptor(itemID)
	return descriptor and descriptor.icon or nil
end

local function readOrderFields(self, orderEntry)
	local recipeID = tonumber(orderEntry.spellID)
	local itemID = tonumber(orderEntry.itemID)
	return {
		characterKey = tostring(orderEntry.characterKey or self:GetCharacterKey()),
		recipeID = recipeID,
		recipeName = resolveOrderRecipeName(self, orderEntry, recipeID, itemID),
		outputItemID = itemID,
		outputName = itemID and self:GetItemDisplayName(itemID) or nil,
		outputIcon = resolveItemIcon(self, itemID),
		addedAt = tonumber(orderEntry.addedAt),
	}
end

local function newOrderLine(queueKey, orderID, fields)
	return {
		queueKey = queueKey,
		orderID = orderID,
		source = "craftingOrder",
		recipeID = fields.recipeID,
		outputItemID = fields.outputItemID,
		characterKey = fields.characterKey,
		scenario = "craftingOrder",
		quantity = 1,
		recipeName = fields.recipeName,
		outputName = fields.outputName,
		outputIcon = fields.outputIcon,
		reagentPlan = {},
		snapshot = { canCraftNow = false },
		addedAt = fields.addedAt or time(),
	}
end

-- Fields a re-added order overwrites only when the new order data has them.
local REFRESHED_FIELDS = { "recipeID", "recipeName", "outputItemID", "outputName", "outputIcon", "addedAt" }

local function refreshOrderLine(entry, fields)
	entry.characterKey = fields.characterKey
	for _, field in ipairs(REFRESHED_FIELDS) do
		if fields[field] ~= nil then
			entry[field] = fields[field]
		end
	end
	wipe(entry.reagentPlan)
end

local function addCrafterMats(reagentPlan, crafterMatTotals)
	for matItemID, quantity in pairs(crafterMatTotals or {}) do
		local itemID, need = tonumber(matItemID), tonumber(quantity) or 0
		if itemID and need > 0 then
			reagentPlan[#reagentPlan + 1] = { itemID = itemID, quantityRequired = need }
		end
	end
end

--- Adds or refreshes the craft queue line for a crafting-order queue entry. Returns its queue key.
function Tradewright:UpsertCraftQueueForCraftingOrder(orderEntry)
	local orderID = type(orderEntry) == "table" and tonumber(orderEntry.orderID)
	if not orderID then
		return nil
	end
	local key = self:CraftQueueMakeOrderKey(orderID)
	local storage = self:GetCraftQueueStorage()
	local fields = readOrderFields(self, orderEntry)
	local entry = storage[key]
	if entry then
		refreshOrderLine(entry, fields)
	else
		entry = newOrderLine(key, orderID, fields)
		storage[key] = entry
	end
	addCrafterMats(entry.reagentPlan, orderEntry.crafterMatTotals)
	self:NotifyCraftQueueChanged()
	return key
end
