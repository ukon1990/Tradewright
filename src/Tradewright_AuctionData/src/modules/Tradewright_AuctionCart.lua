-- The cart of reagents to buy for queued crafts: its rows and columns, and purchases credited until the bags catch up.
local _, Tradewright = ...

local AL = Tradewright.AuctionLogic
local shared = Tradewright.AuctionShared
local containsText = shared.containsText

-- Purchased items reach the bags after a moment: refresh the cart again at each of these delays.
local PURCHASE_REFRESH_DELAYS_SEC = { 0.15, 0.45, 1.0 }
local normalizeItemID = shared.normalizeItemID

--- Track AH purchases until bags catch up so cart Have/Buy update immediately.
function Tradewright:NoteAuctionCartPurchase(itemID, quantity, source)
	itemID = normalizeItemID(itemID)
	quantity = math.max(0, math.floor(tonumber(quantity) or 0))
	if not itemID or quantity <= 0 then
		return false
	end
	local state = self:GetState()
	local currentCharacterKey = self:GetCharacterKey()
	local live = 0
	if self.GetCharacterItemTotal then
		live = tonumber(self:GetCharacterItemTotal(currentCharacterKey, itemID)) or 0
	end
	state.auctionCartPurchaseCredits = state.auctionCartPurchaseCredits or {}
	local entry = state.auctionCartPurchaseCredits[itemID]
	if type(entry) ~= "table" then
		entry = { baseline = live, credit = 0 }
		state.auctionCartPurchaseCredits[itemID] = entry
	end
	entry.credit = (tonumber(entry.credit) or 0) + quantity
	self:DebugLog("AH", "cart purchase credit", {
		string.format("itemID=%s qty=%s source=%s baseline=%s credit=%s", tostring(itemID), tostring(quantity),
			tostring(source or "?"), tostring(entry.baseline), tostring(entry.credit)),
	})
	return true
end

function Tradewright:GetAuctionCartEffectiveHave(itemID)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return 0
	end
	local currentCharacterKey = self:GetCharacterKey()
	local live = 0
	if self.GetCharacterItemTotal then
		live = tonumber(self:GetCharacterItemTotal(currentCharacterKey, itemID)) or 0
	end
	local state = self:GetState()
	local credits = state.auctionCartPurchaseCredits
	local entry = credits and credits[itemID] or nil
	if type(entry) ~= "table" then
		return live
	end
	local baseline = tonumber(entry.baseline) or live
	local credit = math.max(0, tonumber(entry.credit) or 0)
	local target = baseline + credit
	if live >= target then
		credits[itemID] = nil
		return live
	end
	return math.max(live, target)
end

function Tradewright:ClearSettledAuctionCartPurchaseCredits()
	local state = self:GetState()
	local credits = state.auctionCartPurchaseCredits
	if type(credits) ~= "table" then
		return
	end
	local currentCharacterKey = self:GetCharacterKey()
	for itemID, entry in pairs(credits) do
		local live = 0
		if self.GetCharacterItemTotal then
			live = tonumber(self:GetCharacterItemTotal(currentCharacterKey, itemID)) or 0
		end
		if type(entry) ~= "table" then
			credits[itemID] = nil
		else
			local target = (tonumber(entry.baseline) or 0) + math.max(0, tonumber(entry.credit) or 0)
			if live >= target then
				credits[itemID] = nil
			end
		end
	end
end

function Tradewright:ScheduleAuctionCartPurchaseRefresh()
	local state = self:GetState()
	if state.auctionCartPurchaseRefreshPending then
		return
	end
	state.auctionCartPurchaseRefreshPending = true
	local function refreshOnce()
		state.auctionCartPurchaseRefreshPending = nil
		self:ClearSettledAuctionCartPurchaseCredits()
		if self.ScheduleLiveInventoryRefresh then
			self:ScheduleLiveInventoryRefresh()
		end
		if self.RefreshAuctionHousePanel then
			self:RefreshAuctionHousePanel()
		end
		if self.RefreshProfessionCraftEconomyPanel then
			self:RefreshProfessionCraftEconomyPanel()
		end
	end
	refreshOnce()
	for _, delaySec in ipairs(PURCHASE_REFRESH_DELAYS_SEC) do
		C_Timer.After(delaySec, function()
			Tradewright:ClearSettledAuctionCartPurchaseCredits()
			if Tradewright.RefreshAuctionHousePanel then
				Tradewright:RefreshAuctionHousePanel()
			end
		end)
	end
end

local NO_ITEM_DESCRIPTOR = {}

-- What the queue's own crafts make of a material is not bought.
local function neededFromOutside(reagent)
	return (tonumber(reagent.quantityNeeded) or 0) - (tonumber(reagent.quantityFromQueue) or 0)
end

function Tradewright:BuildAuctionCraftCartRow(itemID, reagent)
	local desc = self:ResolveItemDescriptor(itemID) or NO_ITEM_DESCRIPTOR
	local priceState = self:BuildAuctionPanelPriceState(itemID)
	local quantityOnCharacter = tonumber(self:GetAuctionCartEffectiveHave(itemID)) or 0
	local unitPrice = tonumber(reagent.estimatedUnitPrice)
	local quantityHave, quantityToBuy, buyCost = AL.CartQuantities(neededFromOutside(reagent), quantityOnCharacter, unitPrice)
	local mailAllocations, mailToText
	if self.BuildReagentMailAllocations then
		mailAllocations = self:BuildReagentMailAllocations(itemID, reagent.sources)
		mailToText = self:FormatMailAllocationsShort(mailAllocations)
	end
	local sourceText, sourceCount = AL.CartSourceText(reagent.sources)
	return {
		itemID = itemID,
		itemName = reagent.name,
		itemIcon = desc.icon or 134400,
		itemClassLabel = desc.itemType or "",
		itemSubclassLabel = desc.itemSubType or "",
		quantityNeeded = tonumber(reagent.quantityNeeded) or 0,
		quantityHave = quantityHave,
		quantityOnCharacter = quantityOnCharacter,
		quantityToBuy = quantityToBuy,
		estimatedUnitPrice = unitPrice,
		estimatedBuyCost = buyCost,
		estimatedPriceSource = reagent.estimatedPriceSource,
		mailAllocations = mailAllocations,
		mailToText = mailToText or "—",
		sourceText = sourceText,
		sourceCount = sourceCount,
		sources = reagent.sources or {},
		currentPrice = tonumber(priceState.currentPrice),
		currentPriceSource = priceState.currentPriceSource,
		currentPriceSeenAt = tonumber(priceState.currentPriceSeenAt),
		currentPriceIsNative = priceState.currentPriceIsNative == true,
		nativePrice = tonumber(priceState.nativePrice),
		fallbackPrice = tonumber(priceState.fallbackPrice),
	}
end

--- Puts `quantity` more of an item in the cart, on top of what the character holds now. The entry
--- lasts until that many are bought, or until the next /reload.
function Tradewright:AddAuctionCartItem(itemID, quantity, unitPrice, reason)
	local state = self:GetState()
	state.auctionCartExtras = state.auctionCartExtras or {}
	local held = tonumber(self:GetAuctionCartEffectiveHave(itemID)) or 0
	local extra = state.auctionCartExtras[itemID] or { quantity = held }
	extra.quantity = math.max(extra.quantity, held) + math.max(1, tonumber(quantity) or 1)
	extra.unitPrice, extra.reason = unitPrice, reason
	state.auctionCartExtras[itemID] = extra
	if self.RefreshAuctionHousePanel then
		self:RefreshAuctionHousePanel()
	end
end

-- Hand-added items the character now holds enough of leave the cart.
local function dropBoughtCartExtras(pe)
	local extras = pe:GetState().auctionCartExtras or {}
	for itemID, extra in pairs(extras) do
		if (tonumber(pe:GetAuctionCartEffectiveHave(itemID)) or 0) >= extra.quantity then
			extras[itemID] = nil
		end
	end
	return extras
end

function Tradewright:BuildAuctionCraftCartRows()
	self:ClearSettledAuctionCartPurchaseCredits()
	local summary = self:BuildCraftQueueSummary()
	local orderSummary = self.BuildCraftingOrderQueueSummary and self:BuildCraftingOrderQueueSummary() or { reagentLines = {} }
	local merged = AL.MergeCartReagents(summary.reagentLines, orderSummary.reagentLines, self:GetCraftQueueRows(),
		function(itemID) return self:GetItemDisplayName(itemID) end)
	AL.MergeCartExtras(merged, dropBoughtCartExtras(self), function(itemID) return self:GetItemDisplayName(itemID) end)
	local rows = {}
	for itemID, reagent in pairs(merged) do
		rows[#rows + 1] = self:BuildAuctionCraftCartRow(itemID, reagent)
	end
	table.sort(rows, function(a, b)
		return tostring(a.itemName) < tostring(b.itemName)
	end)
	return rows, summary, orderSummary
end

function Tradewright:FilterAuctionCraftCartRows(rows)
	self.ui = self.ui or {}
	local text = string.lower(tostring(self.ui.auctionCartFilterText or ""))
	local out = {}
	for _, row in ipairs(rows or {}) do
		local satisfied = (tonumber(row.quantityToBuy) or 0) <= 0 -- hide satisfied buy rows
		if not satisfied and (text == "" or containsText(row.itemName, text) or containsText(row.sourceText, text)
			or containsText(row.mailToText, text) or containsText(row.itemID, text)) then
			out[#out + 1] = row
		end
	end
	return out
end

function Tradewright:BuildAuctionCartColumns()
	local pe = self
	local function count(id, label, field, optional)
		return {
			id = id, label = label, justifyH = "RIGHT", width = 40, sortable = true, defaultSort = "desc", optional = optional,
			sortValue = function(row) return tonumber(row and row[field]) or 0 end,
			getText = function(row) return pe:FormatNumberGrouped(row and row[field] or 0) end,
		}
	end
	local have = count("quantityHave", "Have", "quantityOnCharacter")
	have.getText = function(row) return pe:FormatNumberGrouped(row and (row.quantityOnCharacter or row.quantityHave) or 0) end
	return {
		self:CreateItemColumn({
			id = "item",
			label = "Item",
			defaultSort = "asc",
			minWidth = 110,
			getItemID = function(row) return row and row.itemID end,
			getIcon = function(row) return row and row.itemIcon end,
			getName = function(row) return row and row.itemName or "-" end,
			getDetail = function(row) return pe:AuctionCartRowDetail(row) end,
			sortValue = function(row) return row and row.itemName end,
		}),
		have,
		count("quantityToBuy", "Buy", "quantityToBuy"),
		pe:MoneyColumn({ id = "estimatedUnitPrice", label = "Each", width = 78, optional = true }),
		pe:MoneyColumn({ id = "estimatedBuyCost", label = "Cost", width = 78 }),
	}
end

function Tradewright:OnCommodityPurchased(itemID, quantity)
	itemID = normalizeItemID(itemID)
	quantity = math.max(0, math.floor(tonumber(quantity) or 0))
	self:DebugLog("AH", "event commodity purchased", {
		string.format("itemID=%s quantity=%s", tostring(itemID), tostring(quantity)),
	})
	local state = self:GetState()
	local pending = state.auctionCartPendingConfirm
	if type(pending) == "table" and tonumber(pending.itemID) == tonumber(itemID) then
		-- Prefer explicit purchased quantity; fall back to confirm qty if event omits it.
		if quantity <= 0 then
			quantity = math.max(0, math.floor(tonumber(pending.quantity) or 0))
		end
		state.auctionCartPendingConfirm = nil
		pending.__credited = true
	end
	if itemID and quantity > 0 then
		self:NoteAuctionCartPurchase(itemID, quantity, "commodity_purchased")
	end
	self:ScheduleAuctionCartPurchaseRefresh()
end

function Tradewright:OnItemPurchased(itemID)
	itemID = normalizeItemID(itemID)
	self:DebugLog("AH", "event item purchased", {
		string.format("itemID=%s", tostring(itemID)),
	})
	-- Item auctions only expose itemID here; bags will correct the exact stack size.
	if itemID then
		self:NoteAuctionCartPurchase(itemID, 1, "item_purchased")
	end
	self:ScheduleAuctionCartPurchaseRefresh()
end

function Tradewright:OnAuctionHousePurchaseCompleted(auctionID)
	self:DebugLog("AH", "event auction house purchase completed", {
		string.format("auctionID=%s", tostring(auctionID)),
	})
	self:ScheduleAuctionCartPurchaseRefresh()
end

function Tradewright:OnCommodityPurchaseSucceeded(...)
	local a1, a2, a3 = ...
	self:DebugLog("AH", "event commodity purchase succeeded", {
		string.format("args=%s", table.concat({ tostring(a1), tostring(a2), tostring(a3) }, ",")),
	})
	local state = self:GetState()
	local pending = state.auctionCartPendingConfirm
	-- Only credit from pending if COMMODITY_PURCHASED did not already consume it.
	if type(pending) == "table" and not pending.__credited then
		self:NoteAuctionCartPurchase(pending.itemID, pending.quantity, "commodity_succeeded_pending")
		state.auctionCartPendingConfirm = nil
	else
		state.auctionCartPendingConfirm = nil
	end
	self:ScheduleAuctionCartPurchaseRefresh()
end

function Tradewright:OnCommodityPurchaseFailed(...)
	local a1, a2, a3 = ...
	self:DebugLog("AH", "event commodity purchase failed", {
		string.format("args=%s", table.concat({ tostring(a1), tostring(a2), tostring(a3) }, ",")),
	})
	local state = self:GetState()
	state.auctionCartPendingConfirm = nil
	if self.RefreshAuctionHousePanel then
		self:RefreshAuctionHousePanel()
	end
	if self.RefreshProfessionCraftEconomyPanel then
		self:RefreshProfessionCraftEconomyPanel()
	end
end

if not Tradewright.__ahCartPurchaseHooksInstalled then
	Tradewright.__ahCartPurchaseHooksInstalled = true
	if C_AuctionHouse and C_AuctionHouse.ConfirmCommoditiesPurchase then
		hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, quantity)
			local pe = Tradewright
			itemID = normalizeItemID(itemID)
			quantity = math.max(0, math.floor(tonumber(quantity) or 0))
			if not itemID or quantity <= 0 then
				return
			end
			local state = pe:GetState()
			state.auctionCartPendingConfirm = {
				itemID = itemID,
				quantity = quantity,
				at = GetTime and GetTime() or 0,
			}
		end)
	end
end
