-- Results of a live AH search: aggregating them, saving them as observations and copying them to the full-scan entries.
local _, Tradewright = ...

local FL = Tradewright.ForeverLogic
local AL = Tradewright.AuctionLogic
local shared = Tradewright.AuctionShared
local normalizeItemID = shared.normalizeItemID

function Tradewright:GetLiveCommoditySearchAggregate(itemID)
	if not C_AuctionHouse.GetNumCommoditySearchResults or not C_AuctionHouse.GetCommoditySearchResultInfo then
		return nil
	end
	local commodityResultCount = tonumber(C_AuctionHouse.GetNumCommoditySearchResults(itemID)) or 0
	local searchAggregate = { kind = "commodity", itemID = itemID, totalQuantity = 0, listingCount = commodityResultCount }
	local rows = {}
	for index = 1, commodityResultCount do
		local row = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index)
		rows[#rows + 1] = row
		AL.AddCommodityResult(searchAggregate, row)
	end
	searchAggregate.levels = self.PriceLevelsFromSearchRows and self:PriceLevelsFromSearchRows(rows) or nil
	if not searchAggregate.minUnitPrice then
		return nil
	end
	searchAggregate.totalQuantity = math.max(1, searchAggregate.totalQuantity)
	return searchAggregate
end

function Tradewright:GetLiveItemSearchAggregate(itemID, keyFields)
	local queryKey = self:MakeAuctionHouseItemKey(itemID, keyFields)
	if not queryKey or not C_AuctionHouse.GetNumItemSearchResults or not C_AuctionHouse.GetItemSearchResultInfo then
		return nil
	end
	local itemResultCount = tonumber(C_AuctionHouse.GetNumItemSearchResults(queryKey)) or 0
	-- Item keys are tables, so rows are grouped and narrowed by what the key holds. A key whose
	-- fields are all zero asks for every variant and narrows nothing.
	local expectedKey = AL.NarrowingItemKey(self:NormalizeAuctionItemKeyFields(keyFields), itemID)
	local variantGroups = {}
	for index = 1, itemResultCount do
		local info = C_AuctionHouse.GetItemSearchResultInfo(queryKey, index)
		if info and info.itemKey then
			local rowKey = FL.SerializeItemKey(info.itemKey, itemID)
			if not expectedKey or rowKey == expectedKey then
				AL.AddItemResult(variantGroups, rowKey, info)
			end
		end
	end
	return AL.SummarizeItemVariants(variantGroups, itemID)
end

--- Sum listed quantity + cheapest unit for commodities; per–ItemKey groups for non-commodity items.
function Tradewright:GetLiveAuctionSearchAggregate(itemID, keyFields)
	itemID = normalizeItemID(itemID)
	if not itemID or not C_AuctionHouse then
		return nil
	end
	return self:GetLiveCommoditySearchAggregate(itemID) or self:GetLiveItemSearchAggregate(itemID, keyFields)
end

function Tradewright:RecordLiveAuctionObservationsFromAggregate(itemID, searchAggregate, sourceTag)
	itemID = normalizeItemID(itemID)
	if not itemID or type(searchAggregate) ~= "table" then
		return
	end
	sourceTag = tostring(sourceTag or "native_refresh")
	local seenAt = Tradewright:Now()
	if searchAggregate.kind == "commodity" then
		self:RecordAuctionObservation({
			itemID = itemID,
			isCommodity = true,
			marketLow = searchAggregate.minUnitPrice,
			minBuyout = searchAggregate.minUnitPrice,
			sampleSize = math.max(1, tonumber(searchAggregate.totalQuantity) or 1),
			source = sourceTag,
			seenAt = seenAt,
		})
		return
	end
	if searchAggregate.kind == "item" and type(searchAggregate.variants) == "table" then
		for _, v in ipairs(searchAggregate.variants) do
			if v.itemKey and v.minUnitPrice and v.minUnitPrice > 0 then
				self:RecordAuctionObservation({
					itemID = itemID,
					isCommodity = false,
					itemKey = v.itemKey,
					marketLow = v.minUnitPrice,
					minBuyout = v.minUnitPrice,
					sampleSize = math.max(1, tonumber(v.totalQuantity) or 1),
					source = sourceTag .. "_itemkey",
					seenAt = seenAt,
				})
			end
		end
	end
end

function Tradewright:ApplyLiveAggregateToNativePrice(itemID, searchAggregate)
	itemID = normalizeItemID(itemID)
	if not itemID or type(searchAggregate) ~= "table" then
		return
	end
	local src = searchAggregate.kind == "commodity" and "commodity_aggregate_live" or "item_aggregate_live"
	if searchAggregate.kind == "commodity" then
		self:UpsertNativeAuctionPrice(itemID, searchAggregate.minUnitPrice, src, math.max(1, tonumber(searchAggregate.totalQuantity) or 1), Tradewright:Now())
		return
	end
	if searchAggregate.kind == "item" and searchAggregate.cheapestUnitPrice and searchAggregate.cheapestUnitPrice > 0 then
		local quantity = math.max(1, tonumber(searchAggregate.totalQuantityAll) or 1)
		self:UpsertNativeAuctionPrice(itemID, searchAggregate.cheapestUnitPrice, src, quantity, Tradewright:Now())
	end
end

function Tradewright:ProcessAuctionRefreshItem(itemID, scanKeyFields)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return self:BuildAuctionPanelPriceState(nil)
	end
	local searchAggregate = self:GetLiveAuctionSearchAggregate(itemID, scanKeyFields)
	if searchAggregate then
		self:RecordLiveAuctionObservationsFromAggregate(itemID, searchAggregate, "native_refresh")
		self:ApplyLiveAggregateToNativePrice(itemID, searchAggregate)
	end
	return self:BuildAuctionPanelPriceState(itemID)
end

function Tradewright:GetLiveAuctionResultUnitPrice(itemID)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return nil, nil, nil
	end
	local searchAggregate = self:GetLiveAuctionSearchAggregate(itemID, nil)
	if not searchAggregate then
		return nil, nil, nil
	end
	if searchAggregate.kind == "commodity" then
		return searchAggregate.minUnitPrice, "commodity_results_live", searchAggregate.totalQuantity
	end
	if searchAggregate.kind == "item" then
		return searchAggregate.cheapestUnitPrice, "item_results_live", searchAggregate.totalQuantityAll
	end
	return nil, nil, nil
end

function Tradewright:ApplyAuctionSearchResultToDatabase(itemID, keyFields, sourceTag)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return false
	end
	self:MarkAuctionTargetSearched(itemID, keyFields, sourceTag or "manual_search", Tradewright:Now())
	local searchAggregate = self:GetLiveAuctionSearchAggregate(itemID, keyFields)
	if not searchAggregate then
		return false
	end
	self:RecordLiveAuctionObservationsFromAggregate(itemID, searchAggregate, tostring(sourceTag or "manual_search"))
	self:ApplyLiveAggregateToNativePrice(itemID, searchAggregate)
	self:SaveLiveSearchToScanEntry(itemID, searchAggregate)
	-- Only a commodity search lists every price level of the item; item searches are split by variant.
	if searchAggregate.kind == "commodity" then
		self:SavePriceSteps(itemID, searchAggregate.levels, Tradewright:Now())
	end
	self:UpdateAuctionPanelRowPrice(itemID, self:BuildAuctionPanelPriceState(itemID))
	return true
end

--- The full scan keeps one entry per item ID (item scope, key = item ID), and Market and the
--- Gold dashboard read that entry. A live search lands under other keys, so copy its price,
--- quantity and auction count there when they changed; otherwise only mark the entry as seen now.
--- `quiet` leaves the view refresh to the caller (a result list saves many items at once).
function Tradewright:SaveLiveSearchToScanEntry(itemID, searchAggregate, quiet)
	local price = tonumber(searchAggregate.minUnitPrice or searchAggregate.cheapestUnitPrice)
	if not price or price <= 0 then
		return false
	end
	local quantity = tonumber(searchAggregate.totalQuantity or searchAggregate.totalQuantityAll)
	local listings = tonumber(searchAggregate.listingCount or searchAggregate.listingCountAll)
	local auction = self:InitAuctionDB()
	local storageKey = self:BuildAuctionStorageKey(itemID, "item", tostring(itemID))
	local saved = storageKey and auction.snapshot.items[storageKey]
	if not self.AuctionLogic.LiveSearchDiffers(saved, price, quantity, listings) then
		saved.t = Tradewright:Now()
		return false
	end
	self:RecordAuctionObservation({
		itemID = itemID,
		isCommodity = false,
		itemKey = tostring(itemID),
		marketLow = price,
		minBuyout = price,
		marketHigh = tonumber(searchAggregate.maxUnitPrice or searchAggregate.highestUnitPrice),
		sampleSize = quantity,
		listingCount = listings,
		source = "results_live_search",
		seenAt = Tradewright:Now(),
	})
	if not quiet then
		self:RefreshViewsAfterLiveSearch()
	end
	return true
end

--- A live search changed saved prices: let the dashboard rebuild now instead of waiting out the
--- scan throttle.
function Tradewright:RefreshViewsAfterLiveSearch()
	self:GetState().marketInsightsForceRebuild = true
	local dash = self.ui and self.ui.goldDashboard
	if dash and dash:IsVisible() then
		dash:Refresh()
	end
	if self.RefreshMarketTab then
		self:RefreshMarketTab()
	end
end

--- The auction house's own result list (a name search, or browsing a category) carries the lowest
--- price and the quantity of every item it shows: save those too. An item ID can appear once per
--- variant, so the lowest price wins and the quantities add up.
function Tradewright:SaveBrowseResultsToScanEntries()
	local byItem = {}
	for _, result in ipairs(C_AuctionHouse.GetBrowseResults and C_AuctionHouse.GetBrowseResults() or {}) do
		local itemID = normalizeItemID(result.itemKey)
		local price = tonumber(result.minPrice) or 0
		if itemID and price > 0 then
			local searchAggregate = byItem[itemID] or { totalQuantity = 0 }
			byItem[itemID] = searchAggregate
			searchAggregate.minUnitPrice = math.min(searchAggregate.minUnitPrice or price, price)
			searchAggregate.totalQuantity = searchAggregate.totalQuantity + (tonumber(result.totalQuantity) or 0)
		end
	end
	local changed = false
	for itemID, searchAggregate in pairs(byItem) do
		changed = self:SaveLiveSearchToScanEntry(itemID, searchAggregate, true) or changed
	end
	if changed then
		self:RefreshViewsAfterLiveSearch()
	end
end
