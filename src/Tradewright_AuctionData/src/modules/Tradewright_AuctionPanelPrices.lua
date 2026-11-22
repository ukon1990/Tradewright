-- The price shown on each AH panel row: which source wins, the quality rank, and writing it into the row.
local _, Tradewright = ...

local shared = Tradewright.AuctionShared
local normalizeItemID = shared.normalizeItemID

function Tradewright:GetAuctionPanelFallbackPrice(itemID)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return nil, "missing", nil
	end

	local function trySnapshot()
		local summary = self:GetItemEconomySummary(itemID, {})
		local snapshotPrice = summary and tonumber(summary.lastPrice) or nil
		if snapshotPrice and snapshotPrice > 0 then
			return snapshotPrice, "snapshot", summary and tonumber(summary.lastSeenAt) or nil
		end
		return nil
	end

	local function tryMarketEstimate()
		local fallbackPrice, fallbackSource = self:GetMarketEstimateCopper(itemID)
		if fallbackPrice and fallbackPrice > 0 then
			return fallbackPrice, "fallback:" .. tostring(fallbackSource or "market"), Tradewright:Now()
		end
		return nil
	end

	local sp, ss, sa = trySnapshot()
	if sp then
		return sp, ss, sa
	end
	local fp, fs, fa = tryMarketEstimate()
	if fp then
		return fp, fs, fa
	end
	return nil, "missing", nil
end

function Tradewright:BuildAuctionPanelPriceState(itemID)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return {
			currentPrice = nil,
			currentPriceSource = "missing",
			currentPriceSeenAt = nil,
			currentPriceIsNative = false,
			nativePrice = nil,
			nativePriceSource = nil,
			nativePriceSeenAt = nil,
			fallbackPrice = nil,
			fallbackPriceSource = nil,
			fallbackPriceSeenAt = nil,
			nativeListingQuantity = nil,
		}
	end
	local livePrice, liveSource, liveQty = self:GetLiveAuctionResultUnitPrice(itemID)
	local nativeListingQuantity = nil
	if livePrice and livePrice > 0 then
		nativeListingQuantity = math.max(1, tonumber(liveQty) or 1)
		self:UpsertNativeAuctionPrice(itemID, livePrice, liveSource or "results_live", nativeListingQuantity, Tradewright:Now())
	end
	local nativePrice, nativeSource, nativeSeenAt = self:GetNativeAhPrice(itemID)
	local fallbackPrice, fallbackSource, fallbackSeenAt = self:GetAuctionPanelFallbackPrice(itemID)
	local currentPrice = nativePrice or fallbackPrice
	local currentSource = nativePrice and (nativeSource or "native") or fallbackSource or "missing"
	local currentSeenAt = nativePrice and nativeSeenAt or fallbackSeenAt
	return {
		currentPrice = currentPrice,
		currentPriceSource = currentSource,
		currentPriceSeenAt = currentSeenAt,
		currentPriceIsNative = nativePrice ~= nil,
		nativePrice = nativePrice,
		nativePriceSource = nativeSource,
		nativePriceSeenAt = nativeSeenAt,
		fallbackPrice = fallbackPrice,
		fallbackPriceSource = fallbackSource,
		fallbackPriceSeenAt = fallbackSeenAt,
		nativeListingQuantity = nativeListingQuantity,
	}
end

function Tradewright:ApplyAuctionPanelPriceState(row, priceState)
	if type(row) ~= "table" then
		return
	end
	priceState = priceState or {}
	row.currentPrice = tonumber(priceState.currentPrice)
	row.currentPriceSource = tostring(priceState.currentPriceSource or "missing")
	row.currentPriceSeenAt = tonumber(priceState.currentPriceSeenAt)
	row.currentPriceIsNative = priceState.currentPriceIsNative == true
	row.nativePrice = tonumber(priceState.nativePrice)
	row.nativePriceSource = priceState.nativePriceSource and tostring(priceState.nativePriceSource) or nil
	row.nativePriceSeenAt = tonumber(priceState.nativePriceSeenAt)
	row.fallbackPrice = tonumber(priceState.fallbackPrice)
	row.fallbackPriceSource = priceState.fallbackPriceSource and tostring(priceState.fallbackPriceSource) or nil
	row.fallbackPriceSeenAt = tonumber(priceState.fallbackPriceSeenAt)
end

function Tradewright:GetAuctionDisplayProfessionQualityRank(itemID)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return nil
	end
	if self.IS_SUPPORTED and C_Item and C_Item.GetItemInfo then
		local _, link = C_Item.GetItemInfo(itemID)
		local fromLink = link and self:ParseProfessionQualityTierFromItemLink(link) or nil
		if fromLink and fromLink >= 1 then
			return fromLink
		end
	end
	for _, characterData in pairs(self.db.characters or {}) do
		for _, professionData in pairs(characterData.professions or {}) do
			for _, recipeData in pairs(professionData.recipes or {}) do
				local outputs = recipeData and recipeData.outputs or nil
				local variants = outputs and outputs.qualityVariants or nil
				if type(variants) == "table" and #variants > 1 then
					for i, variant in ipairs(variants) do
						if tonumber(variant and variant.itemID) == itemID then
							return tonumber(variant.qualityIndex) or i
						end
					end
					local primary = tonumber(self:RecipeOutputsPrimaryItemId(outputs))
					if primary == itemID then
						return 1
					end
				end
			end
		end
	end
	return nil
end

function Tradewright:UpdateAuctionRowDumpState(row)
	if type(row) ~= "table" then
		return
	end
	local dumpFactor = tonumber(self:GetSetting("auction.dumpLowFactor", 0.35)) or 0.35
	dumpFactor = math.max(0.05, math.min(0.95, dumpFactor))
	local baseline = tonumber(row.avgSale) or tonumber(row.avgBuy)
	local current = tonumber(row.currentPrice)
	if baseline and baseline > 0 and current and current > 0 and current <= (baseline * dumpFactor) then
		row.isDumpedLow = true
		row.dumpRatio = current / baseline
	else
		row.isDumpedLow = false
		row.dumpRatio = nil
	end
end

function Tradewright:UpdateAuctionPanelRowPrice(itemID, priceState)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return
	end
	local state = self:GetState()
	local panelRows = state.auctionPanelRows or {}
	for _, row in ipairs(panelRows) do
		if tonumber(row.itemID) == tonumber(itemID) then
			self:ApplyAuctionPanelPriceState(row, priceState)
			local scanTs = self:GetItemLastAuctionScanAt(itemID)
			row.lastAuctionScanAtTs = scanTs
			row.auctionScanAgeDisplay = self:FormatAuctionScanAge(scanTs)
			self:UpdateAuctionRowDumpState(row)
			local roi = self:EstimateCraftROIForItem(itemID)
			state.auctionRoiCache = state.auctionRoiCache or {}
			state.auctionRoiCache[itemID] = roi
			row.potentialROI = roi and roi.potentialROI or nil
			row.recipeName = roi and roi.recipeName or nil
			row.qualityIndex = row.qualityIndex or (roi and roi.qualityIndex or nil)
			break
		end
	end
end

function Tradewright:GetAuctionPanelPersonalSaleRate(itemID, characterKey)
	local auction = self:InitAuctionDB()
	if not auction or not auction.transactions or type(auction.transactions.events) ~= "table" then
		return nil, "-"
	end
	itemID = normalizeItemID(itemID)
	if not itemID then
		return nil, "-"
	end
	characterKey = characterKey and tostring(characterKey) or self:GetCharacterKey()
	local posted, sold = 0, 0
	for _, event in ipairs(auction.transactions.events) do
		if tonumber(event and event.itemID) == itemID and tostring(event.characterKey or "") == characterKey then
			local kind = tostring(event.kind or "")
			if kind == "posted" then
				posted = posted + math.max(1, tonumber(event.quantity) or 1)
			elseif kind == "sold" then
				sold = sold + math.max(1, tonumber(event.quantity) or 1)
			end
		end
	end
	if posted <= 0 then
		return nil, "-"
	end
	local ratio = math.max(0, math.min(1, sold / posted))
	return ratio, string.format("%.0f%%", ratio * 100)
end
