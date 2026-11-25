-- The price shown on each AH panel row: which source wins, the quality rank, what posting earns,
-- and writing it into the row.
local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })

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

-- What the item sells for, to hold its lowest price against: the market price of the listings
-- above the cheapest (from the kept price steps), else the usual price of the last days, else the
-- player's own average sale or buy price.
local function marketPrice(pe, row)
	local steps = pe.GetPriceSteps and pe:GetPriceSteps(row.itemID)
	local share = pe:GetSetting("auction.marketPriceShare", pe.DEFAULT_MARKET_PRICE_SHARE)
	local fromSteps = pe.AuctionLogic.MarketPriceFromSteps(steps, share)
	if fromSteps then
		return fromSteps
	end
	local usual = pe.GetItemPriceSignals and pe:GetItemPriceSignals(row.itemID)
	return tonumber(usual and usual.usual) or tonumber(row.avgSale) or tonumber(row.avgBuy)
end

--- Marks a row whose lowest price is far under the item's market price (`isDumpedLow`, with
--- `dumpBaseline` and `dumpRatio`): someone may have listed one cheap to bait an undercut. The share
--- comes from Settings; posting then warns first.
function Tradewright:UpdateAuctionRowDumpState(row)
	if type(row) ~= "table" then
		return
	end
	local factor = tonumber(self:GetSetting("auction.dumpLowFactor", self.DEFAULT_DUMP_LOW_FACTOR))
	local baseline = marketPrice(self, row)
	row.dumpRatio = self.AuctionLogic.LowPriceRatio(row.currentPrice, baseline, factor)
	row.isDumpedLow = row.dumpRatio ~= nil
	row.dumpBaseline = row.isDumpedLow and baseline or nil
end

--- Chat warning that a row's item is about to be posted far under its usual price.
function Tradewright:WarnLowAuctionPrice(row)
	self:PrintMessage(self:Colorize(string.format(L["Careful: %s is listed for %s, %d%% of its market price %s. Someone may be baiting a low post."],
		self:GetItemDisplayName(row.itemID), self:FormatCopperShort(row.currentPrice),
		math.floor((row.dumpRatio or 0) * 100 + 0.5), self:FormatCopperShort(row.dumpBaseline)), "warning"))
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

--- Share of the player's own postings of an item that sold: sales / (sales + expired + cancelled),
--- from the mail ledger, so each sale counts for the item that actually sold. Returns the fraction
--- and its "80%" text, or nil and "-" while the item was never posted (or Inventory is off).
function Tradewright:GetAuctionPanelPersonalSaleRate(itemID)
	itemID = normalizeItemID(itemID)
	local tally = itemID and self.GetLedgerItemTally and self:GetLedgerItemTally(itemID)
	local ratio = self.IncomeLogic.SaleChance(tally, 1)
	if not ratio then
		return nil, "-"
	end
	return ratio, string.format("%.0f%%", ratio * 100)
end

-- Material cost per unit from the craft estimate, nil when the item is not crafted.
local function craftCostPerUnit(roi)
	local cost = tonumber(roi and roi.materialCost)
	return cost and cost / math.max(1, tonumber(roi.outputQty) or 1) or nil
end

--- What posting one unit of the row earns over its best other value; see AuctionLogic.PostGain.
function Tradewright:GetAuctionRowPostGain(row)
	local roi = (self:GetState().auctionRoiCache or {})[row.itemID]
	return self.AuctionLogic.PostGain({
		price = row.currentPrice,
		vendorSell = self:GetItemVendorSellCopper(row.itemID),
		paid = row.avgBuy,
		craftCost = craftCostPerUnit(roi),
	}, self:GetAuctionCut())
end

function Tradewright:IsAuctionRowProfitableToPost(row)
	local post = self:GetAuctionRowPostGain(row)
	return post ~= nil and post.gain > 0
end
