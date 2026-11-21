local _, AuctionHelper = ...

if not AuctionHelper.IS_RETAIL then
	return
end

local ReagentSource = Enum.CraftingOrderReagentSource

local function getOrderReagentDescriptor(entry)
	if not entry then
		return { dataSlotIndex = nil, dataSlotType = nil, itemID = nil, currencyID = nil, quantity = 0 }
	end

	local dataSlotIndex = nil
	if entry.reagent and entry.reagent.dataSlotIndex then
		dataSlotIndex = entry.reagent.dataSlotIndex
	elseif entry.reagent and entry.reagent.reagent and entry.reagent.reagent.dataSlotIndex then
		dataSlotIndex = entry.reagent.reagent.dataSlotIndex
	elseif entry.reagentInfo and entry.reagentInfo.dataSlotIndex then
		dataSlotIndex = entry.reagentInfo.dataSlotIndex
	elseif entry.reagentInfo and entry.reagentInfo.reagent and entry.reagentInfo.reagent.dataSlotIndex then
		dataSlotIndex = entry.reagentInfo.reagent.dataSlotIndex
	elseif entry.dataSlotIndex then
		dataSlotIndex = entry.dataSlotIndex
	elseif entry.reagentSlot and entry.reagentSlot.dataSlotIndex then
		dataSlotIndex = entry.reagentSlot.dataSlotIndex
	end

	local dataSlotType = nil
	if entry.reagent and entry.reagent.dataSlotType then
		dataSlotType = entry.reagent.dataSlotType
	elseif entry.reagent and entry.reagent.reagent and entry.reagent.reagent.dataSlotType then
		dataSlotType = entry.reagent.reagent.dataSlotType
	elseif entry.reagentInfo and entry.reagentInfo.dataSlotType then
		dataSlotType = entry.reagentInfo.dataSlotType
	elseif entry.reagentInfo and entry.reagentInfo.reagent and entry.reagentInfo.reagent.dataSlotType then
		dataSlotType = entry.reagentInfo.reagent.dataSlotType
	elseif entry.dataSlotType then
		dataSlotType = entry.dataSlotType
	elseif entry.reagentSlot and entry.reagentSlot.dataSlotType then
		dataSlotType = entry.reagentSlot.dataSlotType
	end

	local currencyID = nil
	if entry.reagent then
		if entry.reagent.reagent and entry.reagent.reagent.currencyID then
			currencyID = entry.reagent.reagent.currencyID
		elseif entry.reagent.currencyID then
			currencyID = entry.reagent.currencyID
		end
	end
	if not currencyID and entry.reagentInfo and entry.reagentInfo.reagent and entry.reagentInfo.reagent.currencyID then
		currencyID = entry.reagentInfo.reagent.currencyID
	elseif not currencyID and entry.reagentInfo and entry.reagentInfo.currencyID then
		currencyID = entry.reagentInfo.currencyID
	end

	local itemID = nil
	if entry.reagent then
		if entry.reagent.reagent and entry.reagent.reagent.itemID then
			itemID = entry.reagent.reagent.itemID
		elseif entry.reagent.itemID then
			itemID = entry.reagent.itemID
		end
	end
	if not itemID and entry.reagentInfo and entry.reagentInfo.reagent and entry.reagentInfo.reagent.itemID then
		itemID = entry.reagentInfo.reagent.itemID
	elseif not itemID and entry.reagentInfo and entry.reagentInfo.itemID then
		itemID = entry.reagentInfo.itemID
	elseif not itemID and entry.itemID then
		itemID = entry.itemID
	end

	local quantity = tonumber(
		entry.quantity or
		(entry.reagent and entry.reagent.quantity) or
		(entry.reagentInfo and entry.reagentInfo.quantity) or
		(entry.reagentSlot and entry.reagentSlot.quantity)
	) or 0

	return {
		dataSlotIndex = tonumber(dataSlotIndex),
		dataSlotType = tonumber(dataSlotType),
		itemID = tonumber(itemID),
		currencyID = tonumber(currencyID),
		quantity = quantity,
	}
end

-- Key by unique schematic slotIndex (not bare dataSlotIndex). Recipes like
-- Attuned Thalassian Rune-Prism reuse dataSlotIndex across dataSlotTypes.
local function buildOrderSlotSchematicLookup(order)
	local lookup = {}
	local recipeID = AuctionHelper.NormalizeTradeSkillRecipeId and AuctionHelper:NormalizeTradeSkillRecipeId(order and order.spellID)
	recipeID = tonumber(recipeID or order and order.spellID)
	if not recipeID or not C_TradeSkillUI or not C_TradeSkillUI.GetRecipeSchematic then
		return lookup
	end
	local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, order and order.isRecraft == true)
		or C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
	if not schematic or type(schematic.reagentSlotSchematics) ~= "table" then
		return lookup
	end
	for arrayIndex, slot in ipairs(schematic.reagentSlotSchematics) do
		local uniqueSlotIndex = tonumber(slot and slot.slotIndex) or arrayIndex
		lookup[uniqueSlotIndex] = {
			slotIndex = uniqueSlotIndex,
			dataSlotIndex = tonumber(slot and slot.dataSlotIndex),
			dataSlotType = tonumber(slot and slot.dataSlotType),
			quantityRequired = tonumber(slot.quantityRequired) or 0,
			reagents = slot.reagents or {},
			reagentType = tonumber(slot.reagentType),
			required = slot.required == true,
			optional = slot.optional == true,
		}
	end
	return lookup
end

local function buildOrderItemToSlotLookup(order)
	local lookup = {}
	for slotIndex, slot in pairs(buildOrderSlotSchematicLookup(order)) do
		for _, reagent in ipairs(slot.reagents or {}) do
			local itemID = tonumber(reagent and reagent.itemID)
			if itemID and lookup[itemID] == nil then
				lookup[itemID] = slotIndex
			end
		end
	end
	return lookup
end

--- Resolve a provided order reagent to a unique schematic slot key.
--- Prefer itemID membership so shared dataSlotIndex values cannot collide.
local function findSchematicSlotKeyForProvidedReagent(slotSchematicLookup, itemToSlotLookup, reagent)
	if type(slotSchematicLookup) ~= "table" or type(reagent) ~= "table" then
		return nil
	end

	local itemID = tonumber(reagent.itemID)
	if itemID then
		if itemToSlotLookup and itemToSlotLookup[itemID] ~= nil then
			return tonumber(itemToSlotLookup[itemID])
		end
		for slotKey, slot in pairs(slotSchematicLookup) do
			for _, slotReagent in ipairs(slot.reagents or {}) do
				if tonumber(slotReagent and slotReagent.itemID) == itemID then
					return tonumber(slotKey)
				end
			end
		end
	end

	local dataSlotIndex = tonumber(reagent.dataSlotIndex)
	local dataSlotType = tonumber(reagent.dataSlotType)
	if dataSlotIndex == nil then
		return nil
	end

	if dataSlotType ~= nil then
		local typedMatches = {}
		for slotKey, slot in pairs(slotSchematicLookup) do
			if tonumber(slot.dataSlotIndex) == dataSlotIndex and tonumber(slot.dataSlotType) == dataSlotType then
				typedMatches[#typedMatches + 1] = tonumber(slotKey)
			end
		end
		if #typedMatches == 1 then
			return typedMatches[1]
		end
	end

	local indexMatches = {}
	for slotKey, slot in pairs(slotSchematicLookup) do
		if tonumber(slot.dataSlotIndex) == dataSlotIndex then
			indexMatches[#indexMatches + 1] = tonumber(slotKey)
		end
	end
	if #indexMatches == 1 then
		return indexMatches[1]
	end

	return nil
end

local function resolveOrderReagentEntry(entry)
	local descriptor = getOrderReagentDescriptor(entry)
	-- Preserve Blizzard dataSlotIndex; unique schematic slot is resolved via
	-- findSchematicSlotKeyForProvidedReagent (itemID membership first).

	return {
		source = entry and entry.source,
		dataSlotIndex = descriptor.dataSlotIndex,
		dataSlotType = descriptor.dataSlotType,
		itemID = descriptor.itemID,
		quantity = descriptor.quantity,
		currencyID = descriptor.currencyID,
	}
end

local function copyReagentsList(reagents)
	local out = {}
	if type(reagents) ~= "table" then
		return out
	end
	for i, entry in ipairs(reagents) do
		if type(entry) == "table" then
			local r = resolveOrderReagentEntry(entry)
			out[i] = {
				source = entry.source,
				reagentSlot = entry.reagentSlot,
				reagent = {
					itemID = r.itemID,
					quantity = r.quantity,
					dataSlotIndex = r.dataSlotIndex,
					dataSlotType = r.dataSlotType,
					currencyID = r.currencyID,
				},
			}
		end
	end
	return out
end

--- Reagents the crafter may need to supply.
--- Only Customer-provided reagents reduce the buy need; Crafter/Any entries in
--- order.reagents must not be treated as already supplied (that under-counts).
function AuctionHelper:ExtractCrafterShoppingReagentsFromOrder(order)
	local totals = {}
	if type(order) ~= "table" then
		return totals
	end

	local itemToSlotLookup = buildOrderItemToSlotLookup(order)
	local slotSchematicLookup = buildOrderSlotSchematicLookup(order)
	local providedBySlot = {}

	if type(order.reagents) == "table" then
		for _, entry in ipairs(order.reagents) do
			if type(entry) == "table" then
				local src = entry.source
				-- Customer-locked reagents are already on the order; everything else
				-- is still the crafter's responsibility (see CraftingOrderReagentSource).
				local isCustomer = ReagentSource and src == ReagentSource.Customer
				if isCustomer then
					local reagent = resolveOrderReagentEntry(entry)
					local itemID = tonumber(reagent.itemID)
					local qty = tonumber(reagent.quantity) or 0
					local slotIndex = findSchematicSlotKeyForProvidedReagent(slotSchematicLookup, itemToSlotLookup, reagent)
					if slotIndex and qty > 0 then
						providedBySlot[slotIndex] = providedBySlot[slotIndex] or { quantity = 0, items = {} }
						providedBySlot[slotIndex].quantity = (providedBySlot[slotIndex].quantity or 0) + qty
						if itemID then
							providedBySlot[slotIndex].items[itemID] = true
						end
					end
				end
			end
		end
	end

	local basicReagentType = Enum and Enum.CraftingReagentType and tonumber(Enum.CraftingReagentType.Basic) or nil
	for slotIndex, slot in pairs(slotSchematicLookup) do
		local requiredQty = tonumber(slot and slot.quantityRequired) or 0
		local includeSlot = requiredQty > 0 and slot and slot.optional ~= true and (
			slot.required == true or
			(basicReagentType ~= nil and tonumber(slot.reagentType) == basicReagentType)
		)
		local provided = providedBySlot[tonumber(slotIndex)]
		local providedQty = tonumber(provided and provided.quantity) or 0
		local remainingQty = math.max(0, requiredQty - providedQty)
		if includeSlot and remainingQty > 0 then
			local chosenItemID = nil
			local providedItems = provided and provided.items or nil
			-- Prefer a quality/item the customer did not already send.
			for _, reagent in ipairs(slot.reagents or {}) do
				local itemID = tonumber(reagent and reagent.itemID)
				if itemID and not (providedItems and providedItems[itemID]) then
					chosenItemID = itemID
					break
				end
			end
			if not chosenItemID then
				for _, reagent in ipairs(slot.reagents or {}) do
					local itemID = tonumber(reagent and reagent.itemID)
					if itemID then
						chosenItemID = itemID
						break
					end
				end
			end
			if chosenItemID then
				totals[chosenItemID] = (totals[chosenItemID] or 0) + remainingQty
			end
		end
	end

	return totals
end

function AuctionHelper:GetCraftingOrderWorkQueueStorage()
	self:InitDB()
	if type(self.db.craftingOrderWorkQueue) ~= "table" then
		self.db.craftingOrderWorkQueue = {}
	end
	return self.db.craftingOrderWorkQueue
end

function AuctionHelper:IsCraftingOrderInWorkQueue(orderID)
	orderID = tonumber(orderID)
	if not orderID then
		return false
	end
	local st = self:GetCraftingOrderWorkQueueStorage()
	return st[tostring(orderID)] ~= nil
end

local function copyPlainValue(value, depth)
	depth = depth or 0
	local valueType = type(value)
	if valueType == "number" or valueType == "string" or valueType == "boolean" or valueType == "nil" then
		return value
	end
	if valueType ~= "table" or depth > 6 then
		return nil
	end
	local out = {}
	local isArray = #value > 0
	if isArray then
		for i, item in ipairs(value) do
			local copied = copyPlainValue(item, depth + 1)
			if copied ~= nil then
				out[i] = copied
			end
		end
	else
		for key, item in pairs(value) do
			local keyType = type(key)
			if keyType == "string" or keyType == "number" then
				local copied = copyPlainValue(item, depth + 1)
				if copied ~= nil then
					out[key] = copied
				end
			end
		end
	end
	return out
end

--- Snapshot enough of a live crafting order for later OrderView:SetOrder after UI reopen.
local function copyOrderPayload(order)
	if type(order) ~= "table" then
		return nil
	end
	local payload = copyPlainValue(order, 0)
	if type(payload) ~= "table" then
		return nil
	end
	payload.orderID = tonumber(payload.orderID or order.orderID)
	payload.spellID = tonumber(payload.spellID or order.spellID)
	payload.itemID = tonumber(payload.itemID or order.itemID)
	payload.tipAmount = tonumber(payload.tipAmount or order.tipAmount) or 0
	payload.consortiumCut = tonumber(payload.consortiumCut or order.consortiumCut) or 0
	payload.customerName = tostring(payload.customerName or order.customerName or "?")
	payload.customerNotes = tostring(payload.customerNotes or order.customerNotes or "")
	payload.npcOrderRewards = type(payload.npcOrderRewards) == "table" and payload.npcOrderRewards or {}
	payload.reagents = type(payload.reagents) == "table" and payload.reagents or copyReagentsList(order.reagents) or {}
	if payload.orderState == nil and order.orderState ~= nil then
		payload.orderState = order.orderState
	end
	if payload.reagentState == nil and order.reagentState ~= nil then
		payload.reagentState = order.reagentState
	end
	return payload
end

local function buildOrderFromWorkQueueEntry(entry)
	if type(entry) ~= "table" or not entry.orderID then
		return nil
	end
	local order = nil
	if type(entry.orderPayload) == "table" then
		order = copyPlainValue(entry.orderPayload, 0)
	end
	order = order or {}
	order.orderID = tonumber(order.orderID) or tonumber(entry.orderID)
	order.spellID = tonumber(order.spellID) or tonumber(entry.spellID)
	order.itemID = tonumber(order.itemID) or tonumber(entry.itemID)
	order.orderType = order.orderType ~= nil and order.orderType or entry.orderType
	order.isRecraft = order.isRecraft == true or entry.isRecraft == true
	order.tipAmount = tonumber(order.tipAmount) or tonumber(entry.tipAmount) or 0
	order.consortiumCut = tonumber(order.consortiumCut) or 0
	order.customerName = tostring(order.customerName or "?")
	order.customerNotes = tostring(order.customerNotes or "")
	order.npcOrderRewards = type(order.npcOrderRewards) == "table" and order.npcOrderRewards or {}
	order.reagents = type(order.reagents) == "table" and order.reagents
		or copyReagentsList(entry.reagents)
		or {}
	if order.orderState == nil and Enum and Enum.CraftingOrderState then
		order.orderState = Enum.CraftingOrderState.Created
	end
	if order.reagentState == nil and Enum and Enum.CraftingOrderReagentsType then
		order.reagentState = Enum.CraftingOrderReagentsType.Some
	end
	return order
end

function AuctionHelper:AddCraftingOrderToWorkQueue(order)
	if type(order) ~= "table" or not order.orderID then
		self:PrintMessage("Crafting order add failed: missing order data.")
		return nil, "bad_order"
	end
	local oid = tonumber(order.orderID)
	if not oid then
		self:PrintMessage("Crafting order add failed: bad order ID.")
		return nil, "bad_id"
	end
	local key = tostring(oid)
	local mats = self:ExtractCrafterShoppingReagentsFromOrder(order)
	local recipeName
	local recipeID = self.NormalizeTradeSkillRecipeId and self:NormalizeTradeSkillRecipeId(order.spellID) or order.spellID
	local ri = C_TradeSkillUI.GetRecipeInfo(recipeID)
	if ri and ri.name then
		recipeName = ri.name
	end
	if not recipeName and tonumber(order.itemID) then
		recipeName = self:GetItemDisplayName(order.itemID)
	end
	if not recipeName or recipeName == "" then
		recipeName = "Crafting order"
	end
	local reagentTypes = 0
	local totalQty = 0
	for _, qty in pairs(mats or {}) do
		reagentTypes = reagentTypes + 1
		totalQty = totalQty + (tonumber(qty) or 0)
	end
	local entry = {
		orderID = oid,
		spellID = tonumber(recipeID or order.spellID),
		itemID = tonumber(order.itemID),
		orderType = order.orderType,
		isRecraft = order.isRecraft == true,
		reagents = copyReagentsList(order.reagents),
		orderPayload = copyOrderPayload(order),
		crafterMatTotals = mats,
		recipeName = recipeName,
		tipAmount = tonumber(order.tipAmount),
		characterKey = self:GetCharacterKey(),
		addedAt = time(),
	}
	self:GetCraftingOrderWorkQueueStorage()[key] = entry
	if self.UpsertCraftQueueForCraftingOrder then
		self:UpsertCraftQueueForCraftingOrder(entry)
	end
	self:NotifyWorkOrderQueueChanged()
	return key
end

function AuctionHelper:RemoveCraftingOrderFromWorkQueue(orderID)
	orderID = tonumber(orderID)
	if not orderID then
		return
	end
	self:GetCraftingOrderWorkQueueStorage()[tostring(orderID)] = nil
	if self.RemoveCraftQueueByOrderID then
		self:RemoveCraftQueueByOrderID(orderID)
	end
	self:NotifyWorkOrderQueueChanged()
end

function AuctionHelper:RemoveCraftingOrdersByReagentItem(itemID)
	itemID = tonumber(itemID)
	if not itemID then
		return 0
	end
	local removed = 0
	local storage = self:GetCraftingOrderWorkQueueStorage()
	local removedOrderIDs = {}
	for key, entry in pairs(storage) do
		if type(entry) == "table" and tonumber(entry.crafterMatTotals and entry.crafterMatTotals[itemID]) and tonumber(entry.crafterMatTotals[itemID]) > 0 then
			local orderID = tonumber(entry.orderID)
			storage[key] = nil
			removed = removed + 1
			if orderID then
				removedOrderIDs[#removedOrderIDs + 1] = orderID
			end
		end
	end
	for _, orderID in ipairs(removedOrderIDs) do
		if self.RemoveCraftQueueByOrderID then
			self:RemoveCraftQueueByOrderID(orderID)
		end
	end
	if removed > 0 then
		self:NotifyWorkOrderQueueChanged()
	end
	return removed
end

function AuctionHelper:ClearCraftingOrderWorkQueue()
	local st = self:GetCraftingOrderWorkQueueStorage()
	for k in pairs(st) do
		st[k] = nil
	end
	self:NotifyWorkOrderQueueChanged()
end

function AuctionHelper:GetCraftingOrderWorkQueueRows()
	local st = self:GetCraftingOrderWorkQueueStorage()
	local list = {}
	local currentKey = self:GetCharacterKey()
	for _, entry in pairs(st) do
		if type(entry) == "table" then
			if not entry.characterKey or entry.characterKey == "" then
				entry.characterKey = currentKey
			end
			list[#list + 1] = entry
		end
	end
	table.sort(list, function(a, b)
		return (tonumber(a.addedAt) or 0) < (tonumber(b.addedAt) or 0)
	end)
	return list
end

function AuctionHelper:BuildCraftingOrderWorkQueueSummary()
	local rows = self:GetCraftingOrderWorkQueueRows()
	local reagentTotals = {}
	local currentCharacterKey = self:GetCharacterKey()
	for _, entry in ipairs(rows) do
		local mats = entry.crafterMatTotals
		local destKey = tostring(entry.characterKey or currentCharacterKey)
		if type(mats) == "table" then
			for itemID, qty in pairs(mats) do
				local id = tonumber(itemID)
				local q = tonumber(qty) or 0
				if id and q > 0 then
					local line = reagentTotals[id]
					if not line then
						line = {
							itemID = id,
							quantity = 0,
							quantityNeeded = 0,
							name = self:GetItemDisplayName(id),
							currentCharacterKey = currentCharacterKey,
							currentCharacterQuantity = self.GetCharacterItemTotal and self:GetCharacterItemTotal(currentCharacterKey, id) or 0,
							sources = {},
						}
						reagentTotals[id] = line
					end
					line.quantity = (tonumber(line.quantity) or 0) + q
					line.quantityNeeded = (tonumber(line.quantityNeeded) or 0) + q
					line.sources[#line.sources + 1] = {
						orderID = tonumber(entry.orderID),
						recipeName = entry.recipeName,
						quantity = q,
						characterKey = destKey,
					}
				end
			end
		end
	end
	local matLines = {}
	for itemID, line in pairs(reagentTotals) do
		if self.GetCharacterItemTotal then
			line.currentCharacterQuantity = self:GetCharacterItemTotal(currentCharacterKey, itemID)
		else
			local _, _, _, total = self.GetItemCountByLocation and self:GetItemCountByLocation(itemID) or nil, nil, nil, 0
			line.currentCharacterQuantity = tonumber(total) or 0
		end
		line.currentCharacterAvailable = math.min(tonumber(line.currentCharacterQuantity) or 0, tonumber(line.quantityNeeded) or 0)
		line.quantityToBuy = math.max(0, (tonumber(line.quantityNeeded) or 0) - (tonumber(line.currentCharacterQuantity) or 0))
		if self.BuildReagentMailAllocations then
			line.mailAllocations = self:BuildReagentMailAllocations(itemID, line.sources)
			line.mailToText = self:FormatMailAllocationsShort(line.mailAllocations)
		end
		if self.GetMarketEstimateCopper then
			line.estimatedUnitPrice = select(1, self:GetMarketEstimateCopper(itemID, self:GetSetting("integrations.economyTSMMatString", "Crafting"), self:GetSetting("integrations.economyTSMFallbackString", "DBMinBuyout")))
		end
		if line.estimatedUnitPrice and line.quantityToBuy > 0 then
			line.estimatedBuyCost = line.estimatedUnitPrice * line.quantityToBuy
		end
		matLines[#matLines + 1] = line
	end
	table.sort(matLines, function(a, b)
		return tostring(a.name) < tostring(b.name)
	end)
	return {
		lineCount = #rows,
		lines = rows,
		reagentTotals = reagentTotals,
		reagentLines = matLines,
	}
end

function AuctionHelper:NotifyWorkOrderQueueChanged()
	if self.RefreshCraftsQueuePanel then
		self:RefreshCraftsQueuePanel()
	end
	self:RefreshCraftsTabIfVisible()
	if self.RefreshAuctionHousePanel then
		self:RefreshAuctionHousePanel()
	end
	if self.RefreshProfessionCraftEconomyPanel then
		self:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
	end
end

-- Declared before OnCraftingOrderFulfilled so the local is in scope there (Lua local scope starts at declaration).
local function getLiveCraftingOrderView()
	local pf = _G.ProfessionsFrame
	local ordersPage = pf and pf.OrdersPage
	return ordersPage and ordersPage.OrderView or nil
end

function AuctionHelper:OnCraftingOrderFulfilled(orderID)
	orderID = tonumber(orderID)
	if not orderID then
		return
	end
	local nextEntry = self.GetAdjacentCraftingOrderWorkQueueEntry and self:GetAdjacentCraftingOrderWorkQueueEntry(orderID, 1) or nil
	local orderViewVisible = false
	local liveView = getLiveCraftingOrderView()
	if liveView and liveView.IsShown and liveView:IsShown() then
		orderViewVisible = true
	end
	self:RemoveCraftingOrderFromWorkQueue(orderID)
	if orderViewVisible and nextEntry and self.OpenCraftingOrderWorkQueueEntry then
		C_Timer.After(0.25, function()
			AuctionHelper:OpenCraftingOrderWorkQueueEntry(nextEntry)
		end)
	end
end

function AuctionHelper:GetCraftingOrderWorkQueueIndex(orderID)
	orderID = tonumber(orderID)
	if not orderID then
		return nil, 0
	end
	local rows = self:GetCraftingOrderWorkQueueRows()
	for i, entry in ipairs(rows) do
		if tonumber(entry.orderID) == orderID then
			return i, #rows
		end
	end
	return nil, #rows
end

function AuctionHelper:GetAdjacentCraftingOrderWorkQueueEntry(orderID, delta)
	orderID = tonumber(orderID)
	delta = tonumber(delta) or 0
	if not orderID or delta == 0 then
		return nil
	end
	local rows = self:GetCraftingOrderWorkQueueRows()
	local idx = nil
	for i, entry in ipairs(rows) do
		if tonumber(entry.orderID) == orderID then
			idx = i
			break
		end
	end
	if not idx then
		return nil
	end
	local target = idx + delta
	if target < 1 or target > #rows then
		return nil
	end
	return rows[target]
end

function AuctionHelper:FindLiveCraftingOrder(orderID)
	orderID = tonumber(orderID)
	if not orderID or not C_CraftingOrders then
		return nil
	end
	if C_CraftingOrders.GetClaimedOrder then
		local claimed = C_CraftingOrders.GetClaimedOrder()
		if claimed and tonumber(claimed.orderID) == orderID then
			return claimed
		end
	end
	if C_CraftingOrders.GetCrafterOrders then
		for _, order in ipairs(C_CraftingOrders.GetCrafterOrders() or {}) do
			if tonumber(order.orderID) == orderID then
				return order
			end
		end
	end
	return nil
end

function AuctionHelper:OpenCraftingOrderWorkQueueEntry(entry)
	if type(entry) ~= "table" then
		return false
	end
	local orderID = tonumber(entry.orderID)
	if not orderID then
		return false
	end
	-- Prefer the latest stored work-queue entry (includes orderPayload after reopen).
	local stored = self:GetCraftingOrderWorkQueueStorage()[tostring(orderID)]
	if type(stored) == "table" then
		entry = stored
	end

	local pf = _G.ProfessionsFrame
	if not pf then
		self:PrintMessage(string.format("Open Professions to view crafting order #%s.", tostring(orderID)))
		return false
	end

	local function ensureOrdersTab()
		if not (C_CraftingOrders and C_CraftingOrders.ShouldShowCraftingOrderTab and C_CraftingOrders.ShouldShowCraftingOrderTab()) then
			return false
		end
		if not (pf.isCraftingOrdersTabEnabled and pf.GetTabButton) then
			return false
		end
		local ordersPage = pf.OrdersPage
		if ordersPage and ordersPage.IsVisible and ordersPage:IsVisible() then
			return false
		end
		local tabBtn = pf:GetTabButton(3)
		if tabBtn and tabBtn.Click then
			tabBtn:Click()
			return true
		end
		return false
	end

	local function resolveOrder()
		return self:FindLiveCraftingOrder(orderID) or buildOrderFromWorkQueueEntry(entry)
	end

	local function applyOrder(order)
		if not order then
			self:PrintMessage(string.format("Could not open crafting order #%s in the orders UI.", tostring(orderID)))
			return false
		end
		local ordersPage = pf.OrdersPage
		local orderView = ordersPage and ordersPage.OrderView
		local opened = false
		if ordersPage and type(ordersPage.ViewOrder) == "function" then
			local ok = pcall(ordersPage.ViewOrder, ordersPage, order)
			opened = ok == true
		end
		if not opened and orderView and type(orderView.SetOrder) == "function" then
			local ok = pcall(orderView.SetOrder, orderView, order)
			opened = ok == true
			if opened and orderView.Show then
				orderView:Show()
			end
		end
		if not opened then
			self:PrintMessage(string.format("Could not open crafting order #%s in the orders UI.", tostring(orderID)))
			return false
		end
		if self._professionCraftPanel then
			self._professionCraftPanel._navOrderID = orderID
		end
		C_Timer.After(0, function()
			AuctionHelper:CraftingOrderViewRefreshButtons(getLiveCraftingOrderView(), order)
			if AuctionHelper.ScheduleRefreshProfessionCraftEconomyPanel then
				AuctionHelper:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
			end
		end)
		return true
	end

	if not pf:IsShown() then
		ShowUIPanel(pf)
	end

	local switchedTab = ensureOrdersTab()
	local delay = switchedTab and 0.20 or 0.05
	C_Timer.After(delay, function()
		applyOrder(resolveOrder())
	end)
	return true
end

local function resolveCurrentWorkQueueOrderID(orderView, panel)
	local order = orderView and orderView.order
	local oid = order and tonumber(order.orderID)
	if oid then
		return oid
	end
	if panel and tonumber(panel._navOrderID) then
		return tonumber(panel._navOrderID)
	end
	if C_CraftingOrders and C_CraftingOrders.GetClaimedOrder then
		local claimed = C_CraftingOrders.GetClaimedOrder()
		if claimed and claimed.orderID then
			return tonumber(claimed.orderID)
		end
	end
	return nil
end

local _orderViewButtonsHooked

local function isOrdersPageActive()
	local pf = _G.ProfessionsFrame
	local ordersPage = pf and pf.OrdersPage
	return ordersPage and ordersPage.IsShown and ordersPage:IsShown()
end

local function hideLegacyOrderInfoButtons(orderView)
	local info = orderView and orderView.OrderInfo
	if not info then
		return
	end
	-- Legacy OrderInfo-hosted controls (pre side-panel). Keep hidden if still present.
	if info.peAddWorkOrderBtn and info.peAddWorkOrderBtn ~= (AuctionHelper._professionCraftPanel and AuctionHelper._professionCraftPanel.peAddWorkOrderBtn) then
		info.peAddWorkOrderBtn:Hide()
	end
	if info.peRemoveWorkOrderBtn and info.peRemoveWorkOrderBtn ~= (AuctionHelper._professionCraftPanel and AuctionHelper._professionCraftPanel.peRemoveWorkOrderBtn) then
		info.peRemoveWorkOrderBtn:Hide()
	end
	if info.pePrevOrderBtn and info.pePrevOrderBtn ~= (AuctionHelper._professionCraftPanel and AuctionHelper._professionCraftPanel.pePrevOrderBtn) then
		info.pePrevOrderBtn:Hide()
	end
	if info.peNextOrderBtn and info.peNextOrderBtn ~= (AuctionHelper._professionCraftPanel and AuctionHelper._professionCraftPanel.peNextOrderBtn) then
		info.peNextOrderBtn:Hide()
	end
	if info.peQueueStatusText and info.peQueueStatusText ~= (AuctionHelper._professionCraftPanel and AuctionHelper._professionCraftPanel.peQueueStatusText) then
		info.peQueueStatusText:Hide()
	end
end

local function getProfessionSidePanelOrderControls()
	if not AuctionHelper.EnsureProfessionCraftEconomyPanel then
		return nil
	end
	local panel = AuctionHelper:EnsureProfessionCraftEconomyPanel()
	if not panel or not panel.peAddWorkOrderBtn then
		return nil
	end
	return panel
end

local function layoutOrderQueueButtons(panel)
	if not panel or not panel.peAddWorkOrderBtn or not panel.orderNav then
		return
	end
	panel.peAddWorkOrderBtn:ClearAllPoints()
	panel.peAddWorkOrderBtn:SetPoint("TOPLEFT", panel.orderNav, "TOPLEFT", 0, 0)
	panel.peRemoveWorkOrderBtn:ClearAllPoints()
	panel.peRemoveWorkOrderBtn:SetPoint("LEFT", panel.peAddWorkOrderBtn, "RIGHT", 6, 0)
	if panel.pePrevOrderBtn then
		panel.pePrevOrderBtn:ClearAllPoints()
		panel.pePrevOrderBtn:SetPoint("TOPLEFT", panel.peAddWorkOrderBtn, "BOTTOMLEFT", 0, -4)
	end
	if panel.peNextOrderBtn then
		panel.peNextOrderBtn:ClearAllPoints()
		panel.peNextOrderBtn:SetPoint("LEFT", panel.pePrevOrderBtn, "RIGHT", 6, 0)
	end
	if panel.peQueueStatusText then
		panel.peQueueStatusText:ClearAllPoints()
		panel.peQueueStatusText:SetPoint("LEFT", panel.peNextOrderBtn or panel.pePrevOrderBtn or panel.peAddWorkOrderBtn, "RIGHT", 8, 0)
	end
end

function AuctionHelper:EnsureCraftingOrderViewActionButtons(orderView)
	hideLegacyOrderInfoButtons(orderView)
	local panel = getProfessionSidePanelOrderControls()
	if not panel then
		return
	end
	if panel.__ahOrderQueueControlsWired then
		return
	end
	panel.__ahOrderQueueControlsWired = true

	local function navigateWorkQueue(delta)
		local view = getLiveCraftingOrderView()
		local oid = resolveCurrentWorkQueueOrderID(view, panel)
		if not oid then
			AuctionHelper:PrintMessage("No crafting order selected to navigate from.")
			return
		end
		local nextEntry = AuctionHelper:GetAdjacentCraftingOrderWorkQueueEntry(oid, delta)
		if nextEntry then
			AuctionHelper:OpenCraftingOrderWorkQueueEntry(nextEntry)
		end
	end

	panel.pePrevOrderBtn:SetScript("OnClick", function()
		navigateWorkQueue(-1)
	end)
	panel.peNextOrderBtn:SetScript("OnClick", function()
		navigateWorkQueue(1)
	end)
end

function AuctionHelper:CraftingOrderViewRefreshButtons(orderView, order)
	orderView = orderView or getLiveCraftingOrderView()
	self:EnsureCraftingOrderViewActionButtons(orderView)
	local panel = getProfessionSidePanelOrderControls()
	order = order or (orderView and orderView.order) or nil
	if not panel or not panel.peAddWorkOrderBtn then
		return
	end

	local showOrderNav = isOrdersPageActive() and order and order.orderID
	local recipeID = (not showOrderNav) and self.GetOpenProfessionRecipeID and tonumber(self:GetOpenProfessionRecipeID()) or nil
	local showRecipeNav = (not showOrderNav) and recipeID ~= nil

	if panel.orderNav then
		panel.orderNav:SetShown((showOrderNav or showRecipeNav) and true or false)
		if showRecipeNav and not showOrderNav then
			panel.orderNav:SetHeight(26)
		else
			panel.orderNav:SetHeight(48)
		end
	end

	local function layoutQueueCardBelowNav(useNav)
		if not (panel.queueCard and panel.queueHost) then
			return
		end
		panel.queueCard:ClearAllPoints()
		if useNav and panel.orderNav then
			panel.queueCard:SetPoint("TOPLEFT", panel.orderNav, "BOTTOMLEFT", 0, -6)
			panel.queueCard:SetPoint("TOPRIGHT", panel.queueHost, "TOPRIGHT", 0, 0)
			panel.queueCard:SetPoint("BOTTOMLEFT", panel.queueHost, "BOTTOMLEFT", 0, 30)
		else
			panel.queueCard:SetPoint("TOPLEFT", panel.queueHost, "TOPLEFT", 0, 0)
			panel.queueCard:SetPoint("TOPRIGHT", panel.queueHost, "TOPRIGHT", 0, 0)
			panel.queueCard:SetPoint("BOTTOMLEFT", panel.queueHost, "BOTTOMLEFT", 0, 30)
		end
	end

	if not showOrderNav and not showRecipeNav then
		panel.peAddWorkOrderBtn:Hide()
		panel.peRemoveWorkOrderBtn:Hide()
		if panel.pePrevOrderBtn then panel.pePrevOrderBtn:Hide() end
		if panel.peNextOrderBtn then panel.peNextOrderBtn:Hide() end
		if panel.peQueueStatusText then panel.peQueueStatusText:Hide() end
		layoutQueueCardBelowNav(false)
		return
	end

	if showRecipeNav then
		layoutQueueCardBelowNav(true)
		layoutOrderQueueButtons(panel)
		if panel.pePrevOrderBtn then panel.pePrevOrderBtn:Hide() end
		if panel.peNextOrderBtn then panel.peNextOrderBtn:Hide() end
		if panel.peQueueStatusText then panel.peQueueStatusText:Hide() end

		local inQ = self.IsRecipeInCraftShoppingQueue and self:IsRecipeInCraftShoppingQueue(recipeID)
		panel.peAddWorkOrderBtn:SetShown(not inQ)
		panel.peRemoveWorkOrderBtn:SetShown(inQ and true or false)
		panel.peAddWorkOrderBtn:SetEnabled(true)
		panel.peRemoveWorkOrderBtn:SetEnabled(true)
		panel.peAddWorkOrderBtn:SetScript("OnEnter", function(btn)
			GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
			GameTooltip:AddLine("AuctionHelper", 1, 1, 1)
			GameTooltip:AddLine(
				"Adds this recipe to AuctionHelper shopping. Reagents (including Enchanting Vellum for enchants) are included in the cart.",
				1,
				0.9,
				0.6,
				true
			)
			GameTooltip:Show()
		end)
		panel.peAddWorkOrderBtn:SetScript("OnLeave", GameTooltip_Hide)
		panel.peAddWorkOrderBtn:SetScript("OnClick", function()
			if AuctionHelper.QueueOpenProfessionRecipe then
				AuctionHelper:QueueOpenProfessionRecipe(1, { recipeID = recipeID })
			end
			AuctionHelper:CraftingOrderViewRefreshButtons()
		end)
		panel.peRemoveWorkOrderBtn:SetScript("OnClick", function()
			if AuctionHelper.RemoveCraftQueueLinesForRecipeID then
				AuctionHelper:RemoveCraftQueueLinesForRecipeID(recipeID)
			end
			if AuctionHelper.ScheduleRefreshProfessionCraftEconomyPanel then
				AuctionHelper:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
			end
			AuctionHelper:CraftingOrderViewRefreshButtons()
		end)
		return
	end

	layoutQueueCardBelowNav(true)

	layoutOrderQueueButtons(panel)
	local oid = tonumber(order.orderID)
	panel._navOrderID = oid
	local inQ = self:IsCraftingOrderInWorkQueue(oid)
	if inQ and type(order) == "table" then
		local stored = self:GetCraftingOrderWorkQueueStorage()[tostring(oid)]
		if type(stored) == "table" then
			stored.orderPayload = copyOrderPayload(order)
			stored.reagents = copyReagentsList(order.reagents) or stored.reagents
			stored.tipAmount = tonumber(order.tipAmount) or stored.tipAmount
			stored.spellID = tonumber(order.spellID) or stored.spellID
			stored.itemID = tonumber(order.itemID) or stored.itemID
			local mats = self:ExtractCrafterShoppingReagentsFromOrder(order)
			stored.crafterMatTotals = mats
			if self.UpsertCraftQueueForCraftingOrder then
				self:UpsertCraftQueueForCraftingOrder(stored)
			end
		end
	end
	panel.peAddWorkOrderBtn:SetShown(not inQ)
	panel.peRemoveWorkOrderBtn:SetShown(inQ)
	panel.peAddWorkOrderBtn:SetEnabled(true)
	panel.peRemoveWorkOrderBtn:SetEnabled(true)
	panel.peAddWorkOrderBtn:SetScript("OnEnter", function(btn)
		GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
		GameTooltip:AddLine("AuctionHelper", 1, 1, 1)
		GameTooltip:AddLine(
			"Adds this crafting order to AuctionHelper shopping without starting the order. Only crafter-supplied reagents are included.",
			1,
			0.9,
			0.6,
			true
		)
		GameTooltip:Show()
	end)
	panel.peAddWorkOrderBtn:SetScript("OnLeave", GameTooltip_Hide)
	panel.peAddWorkOrderBtn:SetScript("OnClick", function()
		local live = getLiveCraftingOrderView()
		local o = (live and live.order) or order
		if o then
			AuctionHelper:PrintMessage(string.format("Queueing crafting order #%s...", tostring(o.orderID or "?")))
			AuctionHelper:AddCraftingOrderToWorkQueue(o)
			AuctionHelper:CraftingOrderViewRefreshButtons(getLiveCraftingOrderView(), o)
		else
			AuctionHelper:PrintMessage("Crafting order button clicked, but no live order data was found.")
		end
	end)
	panel.peRemoveWorkOrderBtn:SetScript("OnClick", function()
		local live = getLiveCraftingOrderView()
		local o = (live and live.order) or order
		if o and o.orderID then
			AuctionHelper:RemoveCraftingOrderFromWorkQueue(o.orderID)
			AuctionHelper:CraftingOrderViewRefreshButtons(getLiveCraftingOrderView(), o)
		end
	end)
	panel.peAddWorkOrderBtn:Show()
	if inQ then
		panel.peRemoveWorkOrderBtn:Show()
	else
		panel.peRemoveWorkOrderBtn:Hide()
	end
	local idx, total = self:GetCraftingOrderWorkQueueIndex(oid)
	local hasQueue = (total or 0) > 0
	if panel.pePrevOrderBtn then
		panel.pePrevOrderBtn:SetShown(hasQueue and inQ)
		panel.pePrevOrderBtn:SetEnabled(inQ and idx ~= nil and idx > 1)
	end
	if panel.peNextOrderBtn then
		panel.peNextOrderBtn:SetShown(hasQueue and inQ)
		panel.peNextOrderBtn:SetEnabled(inQ and idx ~= nil and idx < total)
	end
	if panel.peQueueStatusText then
		if hasQueue and inQ and idx then
			panel.peQueueStatusText:SetText(string.format("Queue %d/%d", idx, total))
			panel.peQueueStatusText:Show()
		else
			panel.peQueueStatusText:Hide()
		end
	end
end

function AuctionHelper:HookLiveCraftingOrderView(orderView)
	if not orderView or orderView.__ahOrderButtonsHooked then
		return
	end
	orderView.__ahOrderButtonsHooked = true
	self:EnsureCraftingOrderViewActionButtons(orderView)
	if type(orderView.SetOrder) == "function" then
		hooksecurefunc(orderView, "SetOrder", function(view, order)
			C_Timer.After(0, function()
				AuctionHelper:CraftingOrderViewRefreshButtons(view, order)
				if AuctionHelper.ScheduleRefreshProfessionCraftEconomyPanel then
					AuctionHelper:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
				end
			end)
		end)
	end
	if orderView.HookScript then
		orderView:HookScript("OnShow", function(view)
			C_Timer.After(0, function()
				AuctionHelper:CraftingOrderViewRefreshButtons(view, view.order)
				if AuctionHelper.ScheduleRefreshProfessionCraftEconomyPanel then
					AuctionHelper:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
				end
			end)
		end)
		orderView:HookScript("OnHide", function()
			AuctionHelper:CraftingOrderViewRefreshButtons(getLiveCraftingOrderView(), nil)
		end)
	end
	local pf = _G.ProfessionsFrame
	local ordersPage = pf and pf.OrdersPage
	if ordersPage and type(ordersPage.ViewOrder) == "function" and not ordersPage.__ahViewOrderHooked then
		ordersPage.__ahViewOrderHooked = true
		hooksecurefunc(ordersPage, "ViewOrder", function(_, order)
			C_Timer.After(0, function()
				AuctionHelper:CraftingOrderViewRefreshButtons(getLiveCraftingOrderView(), order)
				if AuctionHelper.ScheduleRefreshProfessionCraftEconomyPanel then
					AuctionHelper:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
				end
			end)
		end)
	end
end

local _crafterOrderListMenuHooked = false
local _recipeListMenuHooked = false

local function getRecipeIDFromMenuOwner(ownerRegion)
	if not ownerRegion then
		return nil
	end
	if type(ownerRegion.GetElementData) == "function" then
		local ok, node = pcall(ownerRegion.GetElementData, ownerRegion)
		if ok and node then
			local data = node
			if type(node.GetData) == "function" then
				local ok2, d = pcall(node.GetData, node)
				if ok2 and type(d) == "table" then
					data = d
				end
			end
			local info = type(data) == "table" and data.recipeInfo or nil
			local recipeID = info and tonumber(info.recipeID)
			if recipeID then
				return recipeID
			end
		end
	end
	local info = ownerRegion.recipeInfo
	if type(info) == "table" and tonumber(info.recipeID) then
		return tonumber(info.recipeID)
	end
	return nil
end

--- Inject Add/Remove shopping into Blizzard's crafter order list right-click menu
--- (tagged MENU_PROFESSIONS_CRAFTER_ORDER; same menu as Favorite).
local function ensureCrafterOrderListContextMenuHook()
	if _crafterOrderListMenuHooked then
		return
	end
	if not (Menu and Menu.ModifyMenu) then
		return
	end
	_crafterOrderListMenuHooked = true
	Menu.ModifyMenu("MENU_PROFESSIONS_CRAFTER_ORDER", function(ownerRegion, rootDescription)
		-- Flat order rows carry a full CraftingOrderInfo on .option (with orderID).
		-- Bucketed recipe rows only have spellID — favorites still work, shopping does not.
		local order = ownerRegion and ownerRegion.option
		if type(order) ~= "table" or not tonumber(order.orderID) then
			return
		end
		rootDescription:CreateDivider()
		local oid = tonumber(order.orderID)
		if AuctionHelper:IsCraftingOrderInWorkQueue(oid) then
			rootDescription:CreateButton("Remove from shopping", function()
				local live = ownerRegion and ownerRegion.option
				local liveID = live and tonumber(live.orderID) or oid
				AuctionHelper:RemoveCraftingOrderFromWorkQueue(liveID)
				AuctionHelper:CraftingOrderViewRefreshButtons(getLiveCraftingOrderView(), live)
				if AuctionHelper.ScheduleRefreshProfessionCraftEconomyPanel then
					AuctionHelper:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
				end
			end)
		else
			rootDescription:CreateButton("Add to shopping", function()
				local live = ownerRegion and ownerRegion.option
				if type(live) ~= "table" or not live.orderID then
					return
				end
				AuctionHelper:PrintMessage(string.format("Queueing crafting order #%s...", tostring(live.orderID)))
				AuctionHelper:AddCraftingOrderToWorkQueue(live)
				AuctionHelper:CraftingOrderViewRefreshButtons(getLiveCraftingOrderView(), live)
				if AuctionHelper.ScheduleRefreshProfessionCraftEconomyPanel then
					AuctionHelper:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
				end
			end)
		end
	end)
end

--- Inject Add/Remove shopping into Blizzard's Crafting-tab recipe list right-click menu
--- (tagged MENU_PROFESSIONS_RECIPE_LIST_FAVORITE; same menu as Favorite).
local function ensureRecipeListContextMenuHook()
	if _recipeListMenuHooked then
		return
	end
	if not (Menu and Menu.ModifyMenu) then
		return
	end
	_recipeListMenuHooked = true
	Menu.ModifyMenu("MENU_PROFESSIONS_RECIPE_LIST_FAVORITE", function(ownerRegion, rootDescription)
		local recipeID = getRecipeIDFromMenuOwner(ownerRegion)
		if not recipeID then
			return
		end
		-- Skip when an order is open on the Orders page — order shopping owns that flow.
		if AuctionHelper.GetOpenCraftingOrder and AuctionHelper:GetOpenCraftingOrder() then
			return
		end
		rootDescription:CreateDivider()
		local inQueue = AuctionHelper.IsRecipeInCraftShoppingQueue
			and AuctionHelper:IsRecipeInCraftShoppingQueue(recipeID)
		if inQueue then
			rootDescription:CreateButton("Remove from shopping", function()
				if AuctionHelper.RemoveCraftQueueLinesForRecipeID then
					AuctionHelper:RemoveCraftQueueLinesForRecipeID(recipeID)
				end
				if AuctionHelper.ScheduleRefreshProfessionCraftEconomyPanel then
					AuctionHelper:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
				end
			end)
		else
			rootDescription:CreateButton("Add to shopping", function()
				if AuctionHelper.QueueOpenProfessionRecipe then
					AuctionHelper:QueueOpenProfessionRecipe(1, { recipeID = recipeID })
				end
			end)
		end
	end)
end

function AuctionHelper:InitCraftingOrdersMaterialsHooks()
	ensureCrafterOrderListContextMenuHook()
	ensureRecipeListContextMenuHook()
	if _orderViewButtonsHooked then
		local liveView = getLiveCraftingOrderView()
		if liveView then
			self:HookLiveCraftingOrderView(liveView)
		end
		return
	end
	_orderViewButtonsHooked = true
	local liveView = getLiveCraftingOrderView()
	if liveView then
		self:HookLiveCraftingOrderView(liveView)
	end
	local mixin = _G.ProfessionsCrafterOrderViewMixin
	if mixin and type(mixin.SetOrder) == "function" then
		hooksecurefunc(mixin, "SetOrder", function(orderView, order)
			C_Timer.After(0, function()
				AuctionHelper:HookLiveCraftingOrderView(orderView)
				AuctionHelper:CraftingOrderViewRefreshButtons(orderView, order)
			end)
		end)
	end
	C_Timer.After(0.5, function()
		local delayedView = getLiveCraftingOrderView()
		if delayedView then
			AuctionHelper:HookLiveCraftingOrderView(delayedView)
			AuctionHelper:CraftingOrderViewRefreshButtons(delayedView, delayedView.order)
		end
	end)
end
