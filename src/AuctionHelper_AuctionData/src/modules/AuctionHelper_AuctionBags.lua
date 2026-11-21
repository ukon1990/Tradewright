-- What the bags hold for the sell tab: sellable stacks, representative slots, keep rules per row and the owned-item rows.
local _, AuctionHelper = ...

local shared = AuctionHelper.AuctionShared
local normalizeItemID = shared.normalizeItemID

local function findBagSlotForItemID(itemID)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return nil, nil
	end
	local foundBag, foundSlot
	AuctionHelper:ForEachBagSlot(nil, function(bag, slot, info)
		if info and tonumber(info.itemID) == itemID then
			foundBag, foundSlot = bag, slot
			return true
		end
	end)
	return foundBag, foundSlot
end

local function isAuctionSellItemValid(bag, slot)
	if not bag or not slot then
		return false
	end
	if not C_AuctionHouse or not C_AuctionHouse.IsSellItemValid then
		return true
	end
	if not ItemLocation or not ItemLocation.CreateFromBagAndSlot then
		return true
	end
	local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
	if not loc then
		return false
	end
	local ok, result = pcall(C_AuctionHouse.IsSellItemValid, loc)
	if ok then
		return result == true
	end
	ok, result = pcall(C_AuctionHouse.IsSellItemValid, loc, false)
	if ok then
		return result == true
	end
	return true
end

local function buildLiveOwnedBagState()
	local out, representatives, validSlots = {}, {}, {}
	AuctionHelper:ForEachBagSlot(nil, function(bag, slot, info)
		local itemID = info and normalizeItemID(info.itemID)
		if not itemID or info.isBound == true or not isAuctionSellItemValid(bag, slot) then
			return
		end
		local stackCount = tonumber(info.stackCount)
		local count = stackCount and stackCount > 0 and stackCount or 1
		out[itemID] = (out[itemID] or 0) + count
		representatives[itemID] = representatives[itemID] or { bag = bag, slot = slot, stackQty = count }
		validSlots[#validSlots + 1] = string.format("%d:%d:%d:%d", bag, slot, itemID, count)
	end)
	local orderedItemIDs = {}
	for itemID in pairs(out) do
		orderedItemIDs[#orderedItemIDs + 1] = itemID
	end
	table.sort(orderedItemIDs)
	return {
		items = out,
		orderedItemIDs = orderedItemIDs,
		representatives = representatives,
		signature = table.concat(validSlots, "|"),
	}
end

local function buildLiveOwnedBagMap()
	return buildLiveOwnedBagState().items
end

local function getBagSlotStackCount(bag, slot)
	if not C_Container or not C_Container.GetContainerItemInfo then
		return nil
	end
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if info and tonumber(info.stackCount) and tonumber(info.stackCount) > 0 then
		return tonumber(info.stackCount)
	end
	return nil
end

function AuctionHelper:GetAuctionOwnedBagState(forceRefresh)
	local state = self:GetState()
	if forceRefresh ~= true and type(state.auctionOwnedBagState) == "table" then
		return state.auctionOwnedBagState
	end
	local bagState = buildLiveOwnedBagState()
	local prev = state.auctionOwnedBagState
	if not prev or prev.signature ~= bagState.signature then
		state.auctionViewRevision = (state.auctionViewRevision or 0) + 1
	end
	state.auctionOwnedBagState = bagState
	return bagState
end

function AuctionHelper:GetAuctionRepresentativeBagSlot(itemID, bagState)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return nil, nil, nil
	end
	bagState = bagState or self:GetAuctionOwnedBagState(false)
	local representative = bagState and bagState.representatives and bagState.representatives[itemID] or nil
	if representative then
		return representative.bag, representative.slot, representative.stackQty
	end
	return findBagSlotForItemID(itemID)
end

function AuctionHelper:GetAuctionRowProtectionState(itemID, quantityOwned, bagState)
	itemID = normalizeItemID(itemID)
	quantityOwned = math.max(0, tonumber(quantityOwned) or 0)
	local rule = self:GetAuctionItemRule(itemID) or {}
	local reserveQty = math.max(0, tonumber(rule.reserveQty) or 0)
	local ignored = rule.ignore == true
	local bag, slot, repStackQty = self:GetAuctionRepresentativeBagSlot(itemID, bagState)
	local stackQty = (bag and slot) and (repStackQty or getBagSlotStackCount(bag, slot) or 1) or nil
	local quantitySellable = math.max(0, quantityOwned - reserveQty)
	local canBulkPost = ignored ~= true and quantitySellable > 0 and bag ~= nil and slot ~= nil
	if canBulkPost and reserveQty > 0 and stackQty and (quantityOwned - stackQty) < reserveQty then
		canBulkPost = false
	end
	local label = "-"
	if ignored then
		label = "IGN"
	elseif reserveQty > 0 then
		label = "K" .. tostring(reserveQty)
	end
	return {
		ignored = ignored,
		reserveQty = reserveQty,
		quantitySellable = quantitySellable,
		firstBag = bag,
		firstSlot = slot,
		firstStackQty = stackQty,
		canBulkPost = canBulkPost,
		label = label,
	}
end

function AuctionHelper:BuildAuctionInventoryRows(opts)
	opts = opts or {}
	local includeCraftEstimates = opts.includeCraftEstimates == true
	local bagState = opts.bagState or self:GetAuctionOwnedBagState(false)
	local items = bagState and bagState.items or buildLiveOwnedBagMap()
	local rows = {}
	for itemID, qty in pairs(items or {}) do
		if itemID and qty > 0 then
			local itemDesc = self:ResolveItemDescriptor(itemID)
			local econ = self:GetItemEconomySummary(itemID, {})
			local craft = includeCraftEstimates and self:GetCraftCostEstimateForItem(itemID, {}) or nil
			local estProfit = nil
			local priceState = self:BuildAuctionPanelPriceState(itemID)
			local craftCost = craft and craft.estimatedMaterialCost or nil
			if priceState.currentPrice and craftCost then
				estProfit = priceState.currentPrice - craftCost
			end
			local scanTs = self:GetItemLastAuctionScanAt(itemID)
			local row = {
				itemID = itemID,
				itemName = self:GetItemDisplayName(itemID),
				itemIcon = itemDesc and itemDesc.icon or nil,
				itemClassLabel = itemDesc and itemDesc.itemType or "Unknown",
				itemSubclassLabel = itemDesc and itemDesc.itemSubType or "",
				classID = itemDesc and itemDesc.classID or nil,
				subclassID = itemDesc and itemDesc.subclassID or nil,
				quantityOwned = qty,
				lastSale = econ and econ.lastSale or nil,
				avgSale = econ and econ.avgSale or nil,
				avgBuy = econ and econ.avgBuy or nil,
				estCraftCost = craftCost,
				estProfit = estProfit,
				freshness = econ and econ.freshnessState or "stale",
				lastAuctionScanAtTs = scanTs,
				auctionScanAgeDisplay = self:FormatAuctionScanAge(scanTs),
				potentialROI = nil,
				personalSaleRateValue = nil,
				personalSaleRateDisplay = "-",
			}
			local protection = self:GetAuctionRowProtectionState(itemID, qty, bagState)
			row.reserveQty = protection.reserveQty
			row.quantitySellable = protection.quantitySellable
			row.isIgnoredByRule = protection.ignored
			row.canBulkPost = protection.canBulkPost
			row.firstBag = protection.firstBag
			row.firstSlot = protection.firstSlot
			row.firstStackQty = protection.firstStackQty
			row.auctionRuleLabel = protection.label
			row.qualityIndex = self:GetAuctionDisplayProfessionQualityRank(itemID)
			self:ApplyAuctionPanelPriceState(row, priceState)
			rows[#rows + 1] = row
		end
	end
	local characterKey = self:GetCharacterKey()
	for _, row in ipairs(rows) do
		local v, display = self:GetAuctionPanelPersonalSaleRate(row.itemID, characterKey)
		row.personalSaleRateValue = v
		row.personalSaleRateDisplay = display or "-"
		self:UpdateAuctionRowDumpState(row)
	end
	table.sort(rows, function(a, b)
		local ap = tonumber(a.estProfit)
		local bp = tonumber(b.estProfit)
		if ap and bp and ap ~= bp then
			return ap > bp
		end
		if ap and not bp then
			return true
		end
		if bp and not ap then
			return false
		end
		return tostring(a.itemName or "") < tostring(b.itemName or "")
	end)
	return rows
end
