local _, AuctionHelper = ...

if not AuctionHelper.IS_RETAIL then
	return
end

local ReagentSource = Enum.CraftingOrderReagentSource

local OrderReagents = AuctionHelper.OrderReagents

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
function AuctionHelper:ExtractCrafterShoppingReagentsFromOrder(order)
	if type(order) ~= "table" then
		return {}
	end
	local slotSchematicLookup = buildOrderSlotSchematicLookup(order)
	local providedBySlot = collectCustomerProvidedBySlot(order, slotSchematicLookup, buildOrderItemToSlotLookup(slotSchematicLookup))
	local basicReagentType = Enum and Enum.CraftingReagentType and tonumber(Enum.CraftingReagentType.Basic) or nil
	return OrderReagents.RemainingShoppingTotals(slotSchematicLookup, providedBySlot, basicReagentType)
end

-- "craftingOrderWorkQueue" is the saved name; kept so existing queues survive.
function AuctionHelper:GetCraftingOrderQueueStorage()
	self:InitDB()
	if type(self.db.craftingOrderWorkQueue) ~= "table" then
		self.db.craftingOrderWorkQueue = {}
	end
	return self.db.craftingOrderWorkQueue
end

function AuctionHelper:IsCraftingOrderQueued(orderID)
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
		return "Crafting order"
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
function AuctionHelper:AddCraftingOrderToQueue(order)
	if type(order) ~= "table" or not order.orderID then
		self:PrintMessage("Crafting order add failed: missing order data.")
		return nil, "bad_order"
	end
	local orderID = tonumber(order.orderID)
	if not orderID then
		self:PrintMessage("Crafting order add failed: bad order ID.")
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

function AuctionHelper:RemoveCraftingOrderFromQueue(orderID)
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

function AuctionHelper:RemoveCraftingOrdersByReagentItem(itemID)
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

function AuctionHelper:ClearCraftingOrderQueue()
	local st = self:GetCraftingOrderQueueStorage()
	for k in pairs(st) do
		st[k] = nil
	end
	self:NotifyCraftingOrderQueueChanged()
end

function AuctionHelper:GetCraftingOrderQueueRows()
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
local function finishOrderReagentLine(self, line, tsm)
	local have = self.GetCharacterItemTotal and self:GetCharacterItemTotal(line.currentCharacterKey, line.itemID) or 0
	line.currentCharacterQuantity = have
	line.currentCharacterAvailable = math.min(have, line.quantityNeeded)
	line.quantityToBuy = math.max(0, line.quantityNeeded - have)
	if self.BuildReagentMailAllocations then
		line.mailAllocations = self:BuildReagentMailAllocations(line.itemID, line.sources)
		line.mailToText = self:FormatMailAllocationsShort(line.mailAllocations)
	end
	if self.GetMarketEstimateCopper then
		line.estimatedUnitPrice = select(1, self:GetMarketEstimateCopper(line.itemID, tsm.material, tsm.fallback))
	end
	if line.estimatedUnitPrice and line.quantityToBuy > 0 then
		line.estimatedBuyCost = line.estimatedUnitPrice * line.quantityToBuy
	end
end

function AuctionHelper:BuildCraftingOrderQueueSummary()
	local rows = self:GetCraftingOrderQueueRows()
	local currentCharacterKey = self:GetCharacterKey()
	local reagentTotals, reagentLines, tsm = {}, {}, self:GetTsmPriceStrings()
	for _, entry in ipairs(rows) do
		addOrderReagents(self, reagentTotals, entry, currentCharacterKey)
	end
	for _, line in pairs(reagentTotals) do
		finishOrderReagentLine(self, line, tsm)
		reagentLines[#reagentLines + 1] = line
	end
	table.sort(reagentLines, function(a, b)
		return tostring(a.name) < tostring(b.name)
	end)
	return { lineCount = #rows, lines = rows, reagentTotals = reagentTotals, reagentLines = reagentLines }
end

function AuctionHelper:NotifyCraftingOrderQueueChanged()
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
	local nextEntry = self.GetAdjacentCraftingOrderQueueEntry and self:GetAdjacentCraftingOrderQueueEntry(orderID, 1) or nil
	local orderViewVisible = false
	local liveView = getLiveCraftingOrderView()
	if liveView and liveView.IsShown and liveView:IsShown() then
		orderViewVisible = true
	end
	self:RemoveCraftingOrderFromQueue(orderID)
	if orderViewVisible and nextEntry and self.OpenCraftingOrderQueueEntry then
		C_Timer.After(0.25, function()
			AuctionHelper:OpenCraftingOrderQueueEntry(nextEntry)
		end)
	end
end

function AuctionHelper:GetCraftingOrderQueueIndex(orderID)
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

function AuctionHelper:GetAdjacentCraftingOrderQueueEntry(orderID, delta)
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

local function ordersTabAvailable(pf)
	return C_CraftingOrders and C_CraftingOrders.ShouldShowCraftingOrderTab and C_CraftingOrders.ShouldShowCraftingOrderTab()
		and pf.isCraftingOrdersTabEnabled and pf.GetTabButton
end

-- Switches the professions window to the orders tab; returns whether it had to switch.
local function ensureOrdersTab(pf)
	if not ordersTabAvailable(pf) then
		return false
	end
	local ordersPage = pf.OrdersPage
	if ordersPage and ordersPage.IsVisible and ordersPage:IsVisible() then
		return false
	end
	local tabButton = pf:GetTabButton(3)
	if tabButton and tabButton.Click then
		tabButton:Click()
		return true
	end
	return false
end

local function showOrderInView(ordersPage, order)
	if ordersPage and type(ordersPage.ViewOrder) == "function" and pcall(ordersPage.ViewOrder, ordersPage, order) then
		return true
	end
	local orderView = ordersPage and ordersPage.OrderView
	if not (orderView and type(orderView.SetOrder) == "function" and pcall(orderView.SetOrder, orderView, order)) then
		return false
	end
	if orderView.Show then
		orderView:Show()
	end
	return true
end

local function applyOrder(self, pf, orderID, order)
	if not order or not showOrderInView(pf.OrdersPage, order) then
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

function AuctionHelper:OpenCraftingOrderQueueEntry(entry)
	local orderID = type(entry) == "table" and tonumber(entry.orderID)
	if not orderID then
		return false
	end
	-- Prefer the stored queue entry: it carries the order payload after a reload.
	local stored = self:GetCraftingOrderQueueStorage()[tostring(orderID)]
	entry = type(stored) == "table" and stored or entry
	local pf = _G.ProfessionsFrame
	if not pf then
		self:PrintMessage(string.format("Open Professions to view crafting order #%s.", tostring(orderID)))
		return false
	end
	if not pf:IsShown() then
		ShowUIPanel(pf)
	end
	local delay = ensureOrdersTab(pf) and 0.20 or 0.05
	C_Timer.After(delay, function()
		applyOrder(self, pf, orderID, self:FindLiveCraftingOrder(orderID) or buildOrderFromQueueEntry(entry))
	end)
	return true
end

local function resolveCurrentQueuedOrderID(orderView, panel)
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

local function getProfessionSidePanelOrderControls()
	if not AuctionHelper.EnsureProfessionCraftEconomyPanel then
		return nil
	end
	local panel = AuctionHelper:EnsureProfessionCraftEconomyPanel()
	if not panel or not panel.peAddToQueueBtn then
		return nil
	end
	return panel
end

local function layoutOrderQueueButtons(panel)
	if not panel or not panel.peAddToQueueBtn or not panel.orderNav then
		return
	end
	panel.peAddToQueueBtn:ClearAllPoints()
	panel.peAddToQueueBtn:SetPoint("TOPLEFT", panel.orderNav, "TOPLEFT", 0, 0)
	panel.peRemoveFromQueueBtn:ClearAllPoints()
	panel.peRemoveFromQueueBtn:SetPoint("LEFT", panel.peAddToQueueBtn, "RIGHT", 6, 0)
	if panel.pePrevOrderBtn then
		panel.pePrevOrderBtn:ClearAllPoints()
		panel.pePrevOrderBtn:SetPoint("TOPLEFT", panel.peAddToQueueBtn, "BOTTOMLEFT", 0, -4)
	end
	if panel.peNextOrderBtn then
		panel.peNextOrderBtn:ClearAllPoints()
		panel.peNextOrderBtn:SetPoint("LEFT", panel.pePrevOrderBtn, "RIGHT", 6, 0)
	end
	if panel.peQueueStatusText then
		panel.peQueueStatusText:ClearAllPoints()
		panel.peQueueStatusText:SetPoint("LEFT", panel.peNextOrderBtn or panel.pePrevOrderBtn or panel.peAddToQueueBtn, "RIGHT", 8, 0)
	end
end

function AuctionHelper:EnsureCraftingOrderViewActionButtons()
	local panel = getProfessionSidePanelOrderControls()
	if not panel then
		return
	end
	if panel.__ahOrderQueueControlsWired then
		return
	end
	panel.__ahOrderQueueControlsWired = true

	local function navigateCraftingOrderQueue(delta)
		local view = getLiveCraftingOrderView()
		local oid = resolveCurrentQueuedOrderID(view, panel)
		if not oid then
			AuctionHelper:PrintMessage("No crafting order selected to navigate from.")
			return
		end
		local nextEntry = AuctionHelper:GetAdjacentCraftingOrderQueueEntry(oid, delta)
		if nextEntry then
			AuctionHelper:OpenCraftingOrderQueueEntry(nextEntry)
		end
	end

	panel.pePrevOrderBtn:SetScript("OnClick", function()
		navigateCraftingOrderQueue(-1)
	end)
	panel.peNextOrderBtn:SetScript("OnClick", function()
		navigateCraftingOrderQueue(1)
	end)
end

local RECIPE_QUEUE_TIP = "Adds this recipe to AuctionHelper shopping. Reagents (including Enchanting Vellum for enchants) are included in the cart."
local ORDER_QUEUE_TIP = "Adds this crafting order to AuctionHelper shopping without starting the order. Only crafter-supplied reagents are included."

local function setOrderNavShown(panel, showOrderNav, showRecipeNav)
	if not panel.orderNav then
		return
	end
	panel.orderNav:SetShown((showOrderNav or showRecipeNav) and true or false)
	panel.orderNav:SetHeight((showRecipeNav and not showOrderNav) and 26 or 48)
end

local function layoutQueueCardBelowNav(panel, useNav)
	if not (panel.queueCard and panel.queueHost) then
		return
	end
	panel.queueCard:ClearAllPoints()
	if useNav and panel.orderNav then
		panel.queueCard:SetPoint("TOPLEFT", panel.orderNav, "BOTTOMLEFT", 0, -6)
	else
		panel.queueCard:SetPoint("TOPLEFT", panel.queueHost, "TOPLEFT", 0, 0)
	end
	panel.queueCard:SetPoint("TOPRIGHT", panel.queueHost, "TOPRIGHT", 0, 0)
	panel.queueCard:SetPoint("BOTTOMLEFT", panel.queueHost, "BOTTOMLEFT", 0, 30)
end

local function hideOrderPaging(panel)
	for _, key in ipairs({ "pePrevOrderBtn", "peNextOrderBtn", "peQueueStatusText" }) do
		if panel[key] then
			panel[key]:Hide()
		end
	end
end

local function showQueueToggle(panel, inQueue)
	panel.peAddToQueueBtn:SetShown(not inQueue)
	panel.peRemoveFromQueueBtn:SetShown(inQueue and true or false)
	panel.peAddToQueueBtn:SetEnabled(true)
	panel.peRemoveFromQueueBtn:SetEnabled(true)
end

local function setQueueButtonTooltip(button, text)
	button:SetScript("OnEnter", function(btn)
		GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
		GameTooltip:AddLine("AuctionHelper", 1, 1, 1)
		GameTooltip:AddLine(text, 1, 0.9, 0.6, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
end

local function refreshRecipeQueueButtons(self, panel, recipeID)
	layoutQueueCardBelowNav(panel, true)
	layoutOrderQueueButtons(panel)
	hideOrderPaging(panel)
	showQueueToggle(panel, self.IsRecipeInCraftQueue and self:IsRecipeInCraftQueue(recipeID))
	setQueueButtonTooltip(panel.peAddToQueueBtn, RECIPE_QUEUE_TIP)
	panel.peAddToQueueBtn:SetScript("OnClick", function()
		if AuctionHelper.QueueOpenProfessionRecipe then
			AuctionHelper:QueueOpenProfessionRecipe(1, { recipeID = recipeID })
		end
		AuctionHelper:CraftingOrderViewRefreshButtons()
	end)
	panel.peRemoveFromQueueBtn:SetScript("OnClick", function()
		if AuctionHelper.RemoveCraftQueueLinesForRecipeID then
			AuctionHelper:RemoveCraftQueueLinesForRecipeID(recipeID)
		end
		if AuctionHelper.ScheduleRefreshProfessionCraftEconomyPanel then
			AuctionHelper:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
		end
		AuctionHelper:CraftingOrderViewRefreshButtons()
	end)
end

-- Keeps a queued order's saved copy in step with the live order being viewed.
local function syncQueuedOrderEntry(self, order, orderID)
	local stored = self:GetCraftingOrderQueueStorage()[tostring(orderID)]
	if type(stored) ~= "table" then
		return
	end
	stored.orderPayload = copyOrderPayload(order)
	stored.reagents = copyReagentsList(order.reagents) or stored.reagents
	stored.tipAmount = tonumber(order.tipAmount) or stored.tipAmount
	stored.spellID = tonumber(order.spellID) or stored.spellID
	stored.itemID = tonumber(order.itemID) or stored.itemID
	stored.crafterMatTotals = self:ExtractCrafterShoppingReagentsFromOrder(order)
	if self.UpsertCraftQueueForCraftingOrder then
		self:UpsertCraftQueueForCraftingOrder(stored)
	end
end

local function wireOrderQueueButtons(panel, order)
	setQueueButtonTooltip(panel.peAddToQueueBtn, ORDER_QUEUE_TIP)
	panel.peAddToQueueBtn:SetScript("OnClick", function()
		local live = getLiveCraftingOrderView()
		local o = (live and live.order) or order
		if o then
			AuctionHelper:PrintMessage(string.format("Queueing crafting order #%s...", tostring(o.orderID or "?")))
			AuctionHelper:AddCraftingOrderToQueue(o)
			AuctionHelper:CraftingOrderViewRefreshButtons(getLiveCraftingOrderView(), o)
		else
			AuctionHelper:PrintMessage("Crafting order button clicked, but no live order data was found.")
		end
	end)
	panel.peRemoveFromQueueBtn:SetScript("OnClick", function()
		local live = getLiveCraftingOrderView()
		local o = (live and live.order) or order
		if o and o.orderID then
			AuctionHelper:RemoveCraftingOrderFromQueue(o.orderID)
			AuctionHelper:CraftingOrderViewRefreshButtons(getLiveCraftingOrderView(), o)
		end
	end)
end

local function setPagingButton(button, shown, enabled)
	if button then
		button:SetShown(shown)
		button:SetEnabled(enabled)
	end
end

local function refreshOrderPaging(self, panel, orderID, inQueue)
	local idx, total = self:GetCraftingOrderQueueIndex(orderID)
	local showPaging = (total or 0) > 0 and inQueue
	local queued = inQueue and idx ~= nil
	setPagingButton(panel.pePrevOrderBtn, showPaging, queued and idx > 1)
	setPagingButton(panel.peNextOrderBtn, showPaging, queued and idx < total)
	local status = panel.peQueueStatusText
	if status and showPaging and idx then
		status:SetText(string.format("Queue %d/%d", idx, total))
		status:Show()
	elseif status then
		status:Hide()
	end
end

local function refreshOrderQueueButtons(self, panel, order)
	layoutQueueCardBelowNav(panel, true)
	layoutOrderQueueButtons(panel)
	local orderID = tonumber(order.orderID)
	panel._navOrderID = orderID
	local inQueue = self:IsCraftingOrderQueued(orderID)
	if inQueue then
		syncQueuedOrderEntry(self, order, orderID)
	end
	showQueueToggle(panel, inQueue)
	wireOrderQueueButtons(panel, order)
	panel.peAddToQueueBtn:Show()
	refreshOrderPaging(self, panel, orderID, inQueue)
end

function AuctionHelper:CraftingOrderViewRefreshButtons(orderView, order)
	orderView = orderView or getLiveCraftingOrderView()
	self:EnsureCraftingOrderViewActionButtons()
	local panel = getProfessionSidePanelOrderControls()
	order = order or (orderView and orderView.order) or nil
	if not panel or not panel.peAddToQueueBtn then
		return
	end
	local showOrderNav = isOrdersPageActive() and order and order.orderID
	local recipeID = (not showOrderNav) and self.GetOpenProfessionRecipeID and tonumber(self:GetOpenProfessionRecipeID()) or nil
	setOrderNavShown(panel, showOrderNav, recipeID ~= nil)
	if showOrderNav then
		refreshOrderQueueButtons(self, panel, order)
	elseif recipeID then
		refreshRecipeQueueButtons(self, panel, recipeID)
	else
		panel.peAddToQueueBtn:Hide()
		panel.peRemoveFromQueueBtn:Hide()
		hideOrderPaging(panel)
		layoutQueueCardBelowNav(panel, false)
	end
end

function AuctionHelper:HookLiveCraftingOrderView(orderView)
	if not orderView or orderView.__ahOrderButtonsHooked then
		return
	end
	orderView.__ahOrderButtonsHooked = true
	self:EnsureCraftingOrderViewActionButtons()
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
		if AuctionHelper:IsCraftingOrderQueued(oid) then
			rootDescription:CreateButton("Remove from shopping", function()
				local live = ownerRegion and ownerRegion.option
				local liveID = live and tonumber(live.orderID) or oid
				AuctionHelper:RemoveCraftingOrderFromQueue(liveID)
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
				AuctionHelper:AddCraftingOrderToQueue(live)
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
		local inQueue = AuctionHelper.IsRecipeInCraftQueue
			and AuctionHelper:IsRecipeInCraftQueue(recipeID)
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
