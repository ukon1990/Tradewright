local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
if not Tradewright.IS_RETAIL then
	return
end

local ReagentSource = Enum.CraftingOrderReagentSource

local OrderReagents = Tradewright.OrderReagents

-- Key by unique schematic slotIndex (not bare dataSlotIndex). Recipes like
-- Attuned Thalassian Rune-Prism reuse dataSlotIndex across dataSlotTypes.
local function buildOrderSlotSchematicLookup(order)
	local lookup = {}
	local recipeID = Tradewright.NormalizeTradeSkillRecipeId and Tradewright:NormalizeTradeSkillRecipeId(order and order.spellID)
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

local function buildOrderItemToSlotLookup(slotSchematicLookup)
	local lookup = {}
	for slotIndex, slot in pairs(slotSchematicLookup) do
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

local function copyReagentsList(reagents)
	local out = {}
	if type(reagents) ~= "table" then
		return out
	end
	for i, entry in ipairs(reagents) do
		if type(entry) == "table" then
			local r = OrderReagents.Describe(entry)
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

local function addProvidedReagent(providedBySlot, slotIndex, reagent)
	local provided = providedBySlot[slotIndex] or { quantity = 0, items = {} }
	providedBySlot[slotIndex] = provided
	provided.quantity = provided.quantity + reagent.quantity
	if reagent.itemID then
		provided.items[reagent.itemID] = true
	end
end

local function isCustomerReagent(entry)
	local customer = ReagentSource and ReagentSource.Customer
	return type(entry) == "table" and customer ~= nil and entry.source == customer
end

-- Customer-provided quantity and items per schematic slot.
local function collectCustomerProvidedBySlot(order, slotSchematicLookup, itemToSlotLookup)
	local providedBySlot = {}
	for _, entry in ipairs(type(order.reagents) == "table" and order.reagents or {}) do
		if isCustomerReagent(entry) then
			local reagent = OrderReagents.Describe(entry)
			local slotIndex = findSchematicSlotKeyForProvidedReagent(slotSchematicLookup, itemToSlotLookup, reagent)
			if slotIndex and reagent.quantity > 0 then
				addProvidedReagent(providedBySlot, slotIndex, reagent)
			end
		end
	end
	return providedBySlot
end

--- Reagents the crafter may need to supply.
--- Only Customer-provided reagents reduce the buy need; Crafter/Any entries in
--- order.reagents must not be treated as already supplied (that under-counts).
function Tradewright:ExtractCrafterShoppingReagentsFromOrder(order)
	if type(order) ~= "table" then
		return {}
	end
	local slotSchematicLookup = buildOrderSlotSchematicLookup(order)
	local providedBySlot = collectCustomerProvidedBySlot(order, slotSchematicLookup, buildOrderItemToSlotLookup(slotSchematicLookup))
	local basicReagentType = Enum and Enum.CraftingReagentType and tonumber(Enum.CraftingReagentType.Basic) or nil
	return OrderReagents.RemainingShoppingTotals(slotSchematicLookup, providedBySlot, basicReagentType)
end

-- "craftingOrderWorkQueue" is the saved name; kept so existing queues survive.
function Tradewright:GetCraftingOrderQueueStorage()
	self:InitDB()
	if type(self.db.craftingOrderWorkQueue) ~= "table" then
		self.db.craftingOrderWorkQueue = {}
	end
	return self.db.craftingOrderWorkQueue
end

function Tradewright:IsCraftingOrderQueued(orderID)
	orderID = tonumber(orderID)
	if not orderID then
		return false
	end
	local st = self:GetCraftingOrderQueueStorage()
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

-- Fields a live order always has; the orders UI errors on nil.
local function applyOrderDisplayDefaults(order)
	order.tipAmount = tonumber(order.tipAmount) or 0
	order.consortiumCut = tonumber(order.consortiumCut) or 0
	order.customerName = tostring(order.customerName or "?")
	order.customerNotes = tostring(order.customerNotes or "")
	order.npcOrderRewards = type(order.npcOrderRewards) == "table" and order.npcOrderRewards or {}
end

local function applyOrderStateDefaults(order)
	if order.orderState == nil and Enum and Enum.CraftingOrderState then
		order.orderState = Enum.CraftingOrderState.Created
	end
	if order.reagentState == nil and Enum and Enum.CraftingOrderReagentsType then
		order.reagentState = Enum.CraftingOrderReagentsType.Some
	end
end

-- Fills what the stored payload lacks from the queue entry's own fields.
local function applyQueueEntryFields(order, entry)
	for _, field in ipairs({ "orderID", "spellID", "itemID", "tipAmount" }) do
		order[field] = tonumber(order[field]) or tonumber(entry[field])
	end
	if order.orderType == nil then
		order.orderType = entry.orderType
	end
	order.isRecraft = order.isRecraft == true or entry.isRecraft == true
	order.reagents = type(order.reagents) == "table" and order.reagents or copyReagentsList(entry.reagents)
end

local function buildOrderFromQueueEntry(entry)
	if type(entry) ~= "table" or not entry.orderID then
		return nil
	end
	local order = type(entry.orderPayload) == "table" and copyPlainValue(entry.orderPayload, 0) or {}
	applyQueueEntryFields(order, entry)
	applyOrderDisplayDefaults(order)
	applyOrderStateDefaults(order)
	return order
end

local function resolveOrderRecipeName(self, order, recipeID)
	local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
	local recipeName = recipeInfo and recipeInfo.name
	if not recipeName and tonumber(order.itemID) then
		recipeName = self:GetItemDisplayName(order.itemID)
	end
	if not recipeName or recipeName == "" then
		return L["Crafting order"]
	end
	return recipeName
end

local function newOrderQueueEntry(self, order, orderID)
	local recipeID = self.NormalizeTradeSkillRecipeId and self:NormalizeTradeSkillRecipeId(order.spellID) or order.spellID
	return {
		orderID = orderID,
		spellID = tonumber(recipeID or order.spellID),
		itemID = tonumber(order.itemID),
		orderType = order.orderType,
		isRecraft = order.isRecraft == true,
		reagents = copyReagentsList(order.reagents),
		orderPayload = copyOrderPayload(order),
		crafterMatTotals = self:ExtractCrafterShoppingReagentsFromOrder(order),
		recipeName = resolveOrderRecipeName(self, order, recipeID),
		tipAmount = tonumber(order.tipAmount),
		characterKey = self:GetCharacterKey(),
		addedAt = time(),
	}
end

--- Stores the order in the crafting-order queue and mirrors it as a craft queue line. Returns its key.
function Tradewright:AddCraftingOrderToQueue(order)
	if type(order) ~= "table" or not order.orderID then
		self:PrintMessage(L["Crafting order add failed: missing order data."])
		return nil, "bad_order"
	end
	local orderID = tonumber(order.orderID)
	if not orderID then
		self:PrintMessage(L["Crafting order add failed: bad order ID."])
		return nil, "bad_id"
	end
	local key = tostring(orderID)
	local entry = newOrderQueueEntry(self, order, orderID)
	self:GetCraftingOrderQueueStorage()[key] = entry
	if self.UpsertCraftQueueForCraftingOrder then
		self:UpsertCraftQueueForCraftingOrder(entry)
	end
	self:NotifyCraftingOrderQueueChanged()
	return key
end

function Tradewright:RemoveCraftingOrderFromQueue(orderID)
	orderID = tonumber(orderID)
	if not orderID then
		return
	end
	self:GetCraftingOrderQueueStorage()[tostring(orderID)] = nil
	if self.RemoveCraftQueueByOrderID then
		self:RemoveCraftQueueByOrderID(orderID)
	end
	self:NotifyCraftingOrderQueueChanged()
end

function Tradewright:RemoveCraftingOrdersByReagentItem(itemID)
	itemID = tonumber(itemID)
	if not itemID then
		return 0
	end
	local removed = 0
	local storage = self:GetCraftingOrderQueueStorage()
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
		self:NotifyCraftingOrderQueueChanged()
	end
	return removed
end

function Tradewright:ClearCraftingOrderQueue()
	local st = self:GetCraftingOrderQueueStorage()
	for k in pairs(st) do
		st[k] = nil
	end
	self:NotifyCraftingOrderQueueChanged()
end

function Tradewright:GetCraftingOrderQueueRows()
	local st = self:GetCraftingOrderQueueStorage()
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

local function addOrderReagents(self, reagentTotals, entry, currentCharacterKey)
	for matItemID, quantity in pairs(type(entry.crafterMatTotals) == "table" and entry.crafterMatTotals or {}) do
		local itemID, need = tonumber(matItemID), tonumber(quantity) or 0
		if itemID and need > 0 then
			local line = reagentTotals[itemID] or { itemID = itemID, quantity = 0, quantityNeeded = 0,
				name = self:GetItemDisplayName(itemID), currentCharacterKey = currentCharacterKey, sources = {} }
			reagentTotals[itemID] = line
			line.quantity = line.quantity + need
			line.quantityNeeded = line.quantityNeeded + need
			line.sources[#line.sources + 1] = { orderID = tonumber(entry.orderID), recipeName = entry.recipeName,
				quantity = need, characterKey = tostring(entry.characterKey or currentCharacterKey) }
		end
	end
end

-- What the current character still has to buy and mail for one reagent.
local function finishOrderReagentLine(self, line)
	local have = self.GetCharacterItemTotal and self:GetCharacterItemTotal(line.currentCharacterKey, line.itemID) or 0
	line.currentCharacterQuantity = have
	line.currentCharacterAvailable = math.min(have, line.quantityNeeded)
	line.quantityToBuy = math.max(0, line.quantityNeeded - have)
	if self.BuildReagentMailAllocations then
		line.mailAllocations = self:BuildReagentMailAllocations(line.itemID, line.sources)
		line.mailToText = self:FormatMailAllocationsShort(line.mailAllocations)
	end
	if self.GetMarketEstimateCopper then
		line.estimatedUnitPrice = select(1, self:GetMarketEstimateCopper(line.itemID))
	end
	if line.estimatedUnitPrice and line.quantityToBuy > 0 then
		line.estimatedBuyCost = line.estimatedUnitPrice * line.quantityToBuy
	end
end

function Tradewright:BuildCraftingOrderQueueSummary()
	local rows = self:GetCraftingOrderQueueRows()
	local currentCharacterKey = self:GetCharacterKey()
	local reagentTotals, reagentLines = {}, {}
	for _, entry in ipairs(rows) do
		addOrderReagents(self, reagentTotals, entry, currentCharacterKey)
	end
	for _, line in pairs(reagentTotals) do
		finishOrderReagentLine(self, line)
		reagentLines[#reagentLines + 1] = line
	end
	table.sort(reagentLines, function(a, b)
		return tostring(a.name) < tostring(b.name)
	end)
	return { lineCount = #rows, lines = rows, reagentTotals = reagentTotals, reagentLines = reagentLines }
end

function Tradewright:NotifyCraftingOrderQueueChanged()
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

function Tradewright:OnCraftingOrderFulfilled(orderID)
	orderID = tonumber(orderID)
	if not orderID then
		return
	end
	local nextEntry = self.GetAdjacentCraftingOrderQueueEntry and self:GetAdjacentCraftingOrderQueueEntry(orderID, 1) or nil
	local orderViewVisible = false
	local liveView = getLiveCraftingOrderView()
	if liveView and liveView.IsShown and liveView:IsShown() then
		orderViewVisible = true
	end
	self:RemoveCraftingOrderFromQueue(orderID)
	if orderViewVisible and nextEntry and self.OpenCraftingOrderQueueEntry then
		C_Timer.After(0.25, function()
			Tradewright:OpenCraftingOrderQueueEntry(nextEntry)
		end)
	end
end

function Tradewright:GetCraftingOrderQueueIndex(orderID)
	orderID = tonumber(orderID)
	if not orderID then
		return nil, 0
	end
	local rows = self:GetCraftingOrderQueueRows()
	for i, entry in ipairs(rows) do
		if tonumber(entry.orderID) == orderID then
			return i, #rows
		end
	end
	return nil, #rows
end

function Tradewright:GetAdjacentCraftingOrderQueueEntry(orderID, delta)
	orderID = tonumber(orderID)
	delta = tonumber(delta) or 0
	if not orderID or delta == 0 then
		return nil
	end
	local rows = self:GetCraftingOrderQueueRows()
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

-- Shared with Tradewright_CraftingOrderMenus.lua and Tradewright_CraftingOrderView.lua.
Tradewright.CraftingOrderShared = {
	copyReagentsList = copyReagentsList,
	copyOrderPayload = copyOrderPayload,
	buildOrderFromQueueEntry = buildOrderFromQueueEntry,
	getLiveCraftingOrderView = getLiveCraftingOrderView,
}
