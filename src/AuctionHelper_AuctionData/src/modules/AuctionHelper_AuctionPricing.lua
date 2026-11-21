-- Prices read from the store: the AH price of an item, reagent and craft cost estimates, and how fresh a scan is.
local _, AuctionHelper = ...

local shared = AuctionHelper.AuctionShared
local normalizeItemID = shared.normalizeItemID
local shallowCopy = shared.shallowCopy

function AuctionHelper:GetAuctionPriceFreshnessWindowSeconds()
	local minutes = tonumber(self:GetSetting("auction.priceFreshnessMinutes", 15)) or 15
	return math.max(60, minutes * 60)
end

function AuctionHelper:IsItemAuctionScanStale(itemID, freshnessWindowSeconds, nowTs)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return false
	end
	local lastScanAt = self:GetItemLastAuctionScanAt(itemID)
	if not lastScanAt or lastScanAt <= 0 then
		return true
	end
	local window = tonumber(freshnessWindowSeconds) or self:GetAuctionPriceFreshnessWindowSeconds()
	window = math.max(60, window)
	local curTs = tonumber(nowTs) or AuctionHelper:Now()
	return (curTs - lastScanAt) >= window
end

function AuctionHelper:GetItemLastAuctionScanAt(itemID)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return nil
	end
	local auction = self:InitAuctionDB()
	return tonumber(auction.itemLastScanAt and auction.itemLastScanAt[tostring(itemID)])
end

function AuctionHelper:TouchItemAuctionScanTimestamp(itemID, ts)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return
	end
	ts = tonumber(ts) or AuctionHelper:Now()
	local auction = self:InitAuctionDB()
	auction.itemLastScanAt = auction.itemLastScanAt or {}
	local k = tostring(itemID)
	local prev = tonumber(auction.itemLastScanAt[k]) or 0
	if ts >= prev then
		auction.itemLastScanAt[k] = ts
	end
end

function AuctionHelper:MarkAuctionQueueScanCompleted()
	local ts = AuctionHelper:Now()
	local auction = self:InitAuctionDB()
	auction.lastQueueScanAt = ts
	self:GetState().auctionLastQueueScanCompletedAt = ts
end

function AuctionHelper:FormatAuctionScanAge(ts)
	ts = tonumber(ts)
	if not ts or ts <= 0 then
		return "never"
	end
	local sec = math.max(0, AuctionHelper:Now() - ts)
	if sec < 120 then
		return "just now"
	end
	if sec < 3600 then
		return string.format("%dm ago", math.floor(sec / 60))
	end
	if sec < 86400 then
		return string.format("%.1fh ago", sec / 3600)
	end
	if date then
		return date("%Y-%m-%d %H:%M", ts)
	end
	return tostring(ts)
end

function AuctionHelper:GetItemEconomySummary(itemID, opts)
	opts = opts or {}
	itemID = normalizeItemID(itemID)
	if not itemID then
		return nil
	end
	local auction = self:InitAuctionDB()
	local byItem = auction.indexes.byItemID[tostring(itemID)] or {}
	local bestSnap = nil
	for storageKey in pairs(byItem) do
		local snap = self:NormalizeAuctionSnapshotEntry(auction.snapshot.commodities[storageKey] or auction.snapshot.items[storageKey])
		if snap and (not bestSnap or (tonumber(snap.seenAt) or 0) > (tonumber(bestSnap.seenAt) or 0)) then
			bestSnap = snap
		end
	end
	if not bestSnap then
		bestSnap = self:GetAuctionSnapshot(itemID, "item")
	end

	local purchaseStats = self:LedgerPurchaseStats(itemID, opts.characterKey)
	local saleStats = self:LedgerSaleStats(itemID, opts.characterKey)
	local freshWindowSec = self:GetAuctionPriceFreshnessWindowSeconds()
	local nowTs = AuctionHelper:Now()
	local lastAuctionScanAt = self:GetItemLastAuctionScanAt(itemID)
	local scanFresh = lastAuctionScanAt and (nowTs - lastAuctionScanAt) <= freshWindowSec
	local snapFresh = false
	if bestSnap and bestSnap.seenAt then
		snapFresh = (nowTs - tonumber(bestSnap.seenAt or 0)) <= freshWindowSec
	end
	-- Trust saved AH data if we recently touched this item *or* the snapshot row is still in-window.
	-- Requiring both made session-only native + stale-looking snapshot fall through to TSM after closing the AH.
	local addonAhFresh = scanFresh or snapFresh
	local stale = not addonAhFresh

	return {
		itemID = itemID,
		snapshot = bestSnap and shallowCopy(bestSnap) or nil,
		lastSeenAt = bestSnap and bestSnap.seenAt or nil,
		lastPrice = bestSnap and bestSnap.marketLow or nil,
		lastAuctionScanAt = lastAuctionScanAt,
		auctionScanFresh = scanFresh == true,
		avgBuy = purchaseStats and purchaseStats.averageUnit or nil,
		lastBuy = purchaseStats and purchaseStats.lastUnit or nil,
		avgSale = saleStats and saleStats.averageUnit or nil,
		lastSale = saleStats and saleStats.lastUnit or nil,
		freshnessState = stale and "stale" or "fresh",
	}
end

function AuctionHelper:UpsertNativeAuctionPrice(itemID, price, source, sampleSize, seenAt)
	itemID = normalizeItemID(itemID)
	price = tonumber(price)
	if not itemID or not price or price <= 0 then
		return false
	end
	local state = self:GetState()
	state.auctionNativePriceByItem = state.auctionNativePriceByItem or {}
	local ts = tonumber(seenAt) or AuctionHelper:Now()
	state.auctionNativePriceByItem[itemID] = {
		price = price,
		seenAt = ts,
		source = tostring(source or "native"),
		sampleSize = math.max(1, tonumber(sampleSize) or 1),
	}
	self:TouchItemAuctionScanTimestamp(itemID, ts)
	return true
end

function AuctionHelper:GetNativeAhPrice(itemID)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return nil
	end
	local state = self:GetState()
	local entry = state.auctionNativePriceByItem and state.auctionNativePriceByItem[itemID]
	if not entry or not tonumber(entry.price) or tonumber(entry.price) <= 0 then
		return nil
	end
	return tonumber(entry.price), tostring(entry.source or "native"), tonumber(entry.seenAt), tonumber(entry.sampleSize)
end

function AuctionHelper:ResolveCurrentAuctionPrice(itemID, opts)
	opts = opts or {}
	itemID = normalizeItemID(itemID)
	if not itemID then
		return nil, "missing", nil
	end
	local livePrice, liveSource, liveQty = self:GetLiveAuctionResultUnitPrice(itemID)
	if livePrice and livePrice > 0 then
		self:UpsertNativeAuctionPrice(itemID, livePrice, liveSource or "results_live", liveQty or 1, AuctionHelper:Now())
		return livePrice, liveSource or "results_live", AuctionHelper:Now()
	end
	local nativePrice, nativeSource, nativeSeenAt = self:GetNativeAhPrice(itemID)
	if nativePrice and nativePrice > 0 then
		if self:IsDebugEnabled() then
			self:DebugLog("AH", "ResolveCurrentAuctionPrice", {
				string.format("itemID=%d source=%s price=%s", itemID, tostring(nativeSource), tostring(nativePrice)),
			})
		end
		return nativePrice, nativeSource or "native", nativeSeenAt
	end
	local function trySnapshotPrice()
		local summary = self:GetItemEconomySummary(itemID, {})
		local snapshotPrice = summary and tonumber(summary.lastPrice) or nil
		if snapshotPrice and snapshotPrice > 0 then
			if self:IsDebugEnabled() then
				self:DebugLog("AH", "ResolveCurrentAuctionPrice", {
					string.format("itemID=%d source=snapshot price=%s", itemID, tostring(snapshotPrice)),
				})
			end
			return snapshotPrice, "snapshot", summary and tonumber(summary.lastSeenAt) or nil
		end
		return nil
	end

	local function tryFallbackTSM()
		if opts.allowFallback == false then
			return nil
		end
		local fallbackPrice, fallbackSource = self:GetMarketEstimateCopper(itemID, self:GetTsmPriceStrings().market)
		if fallbackPrice and fallbackPrice > 0 then
			if self:IsDebugEnabled() then
				self:DebugLog("AH", "ResolveCurrentAuctionPrice", {
					string.format("itemID=%d source=fallback(%s) price=%s", itemID, tostring(fallbackSource), tostring(fallbackPrice)),
				})
			end
			return fallbackPrice, "fallback:" .. tostring(fallbackSource or "market"), AuctionHelper:Now()
		end
		return nil
	end

	local sp, ss, sa = trySnapshotPrice()
	if sp then
		return sp, ss, sa
	end
	local fp, fs, fa = tryFallbackTSM()
	if fp then
		return fp, fs, fa
	end
	return nil, "missing", nil
end

function AuctionHelper:ResolveReagentUnitPrice(itemID, opts)
	opts = opts or {}
	local price, source, seenAt = self:ResolveCurrentAuctionPrice(itemID, {
		allowFallback = opts.allowFallback ~= false,
	})
	if price and price > 0 then
		return price, source, seenAt
	end
	local avgBuy = self:LedgerAverageUnitBuyCopper(itemID, nil)
	if avgBuy and avgBuy > 0 then
		return avgBuy, "ledger_buy", nil
	end
	local avgSell = self:LedgerAverageUnitSellCopper(itemID, nil)
	if avgSell and avgSell > 0 then
		return avgSell, "ledger_sell", nil
	end
	return nil, "missing", nil
end

function AuctionHelper:EstimateCraftROIForItem(itemID)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return nil
	end
	local state = self:GetState()
	self:BuildCraftOpportunityRows({ forceSync = true })
	local best = state.craftOpportunityRoiIndex and state.craftOpportunityRoiIndex[itemID]
	return best and shallowCopy(best) or nil
end

function AuctionHelper:GetCraftCostEstimateForItem(itemID, _opts)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return nil
	end
	local state = self:GetState()
	self:BuildCraftOpportunityRows({ forceSync = true })
	local best = state.craftOpportunityCostIndex and state.craftOpportunityCostIndex[itemID]
	if best then
		return shallowCopy(best)
	end
	return {
		itemID = itemID,
		estimatedMaterialCost = nil,
		confidence = "low",
		source = "none",
	}
end
