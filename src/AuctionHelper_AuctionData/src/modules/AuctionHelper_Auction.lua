local addonName, ProfessionExporter = ...

local AUCTION_TX_MAX_EVENTS = 3000
local AUTO_SCAN_MAX_AGE_SEC = 60 * 60
local FULL_AH_DUMP_COOLDOWN_SEC = 15 * 60
local FULL_AH_DUMP_ROW_CHUNK = 250
local FULL_AH_DUMP_PERSIST_CHUNK = 150
local FULL_AH_DUMP_REQUEST_TIMEOUT_SEC = 45
local FULL_AH_DUMP_REQUEST_POLL_SEC = 1
local CLASSIC_AH_DUMP_PAGE_SIZE = 50
local CLASSIC_AH_DUMP_QUERY_RETRY_SEC = 0.5
local CLASSIC_AH_DUMP_QUERY_MAX_RETRIES = 40
local KNOWN_AH_SIDE_PANELS = {
	"ProfessionExporterAuctionPanel",
	"AuctionHelper_AuctionDataAuctionPanel",
}

local function now()
	return time()
end

local function normalizeItemID(item)
	if type(item) == "number" then
		return item > 0 and math.floor(item) or nil
	end
	if type(item) == "string" then
		local n = tonumber(item)
		return n and n > 0 and math.floor(n) or nil
	end
	if type(item) == "table" then
		local itemID = tonumber(item.itemID)
		return itemID and itemID > 0 and math.floor(itemID) or nil
	end
	return nil
end

local function shallowCopy(source)
	if type(source) ~= "table" then
		return source
	end
	local out = {}
	for key, value in pairs(source) do
		out[key] = value
	end
	return out
end

local function auctionSnapshotSeenAt(entry)
	return tonumber(entry and (entry.t or entry.seenAt))
end

local function auctionSnapshotSource(entry)
	if type(entry) ~= "table" then
		return nil
	end
	return entry.s or entry.source
end

local function auctionSnapshotPrice(entry)
	if type(entry) ~= "table" then
		return nil
	end
	return tonumber(entry.p or entry.marketLow or entry.minBuyout or entry.price)
end

local function auctionSnapshotSampleSize(entry)
	if type(entry) ~= "table" then
		return nil
	end
	return tonumber(entry.q or entry.sampleSize)
end

local function auctionHistoryBucketCount(bucket)
	return tonumber(bucket and (bucket.n or bucket.count)) or 0
end

local function auctionHistoryBucketWeightedQty(bucket)
	return tonumber(bucket and (bucket.q or bucket.weightedQty)) or 0
end

local function auctionHistoryBucketWeightedSum(bucket)
	return tonumber(bucket and (bucket.w or bucket.weightedSum)) or 0
end

local function getMaxOwnedBagIndex()
	local maxBag = 4
	if Enum and Enum.BagIndex and tonumber(Enum.BagIndex.ReagentBag) then
		maxBag = math.max(maxBag, tonumber(Enum.BagIndex.ReagentBag))
	end
	if C_Container and C_Container.GetContainerNumSlots then
		local reagentSlots = C_Container.GetContainerNumSlots(5) or 0
		if reagentSlots > 0 then
			maxBag = math.max(maxBag, 5)
		end
	end
	return maxBag
end

local function findBagSlotForItemID(itemID)
	itemID = normalizeItemID(itemID)
	if not itemID or not C_Container or not C_Container.GetContainerNumSlots then
		return nil, nil
	end
	for bag = 0, getMaxOwnedBagIndex() do
		local slots = C_Container.GetContainerNumSlots(bag) or 0
		for slot = 1, slots do
			local slotItemID = C_Container.GetContainerItemID and C_Container.GetContainerItemID(bag, slot) or nil
			if tonumber(slotItemID) == itemID then
				return bag, slot
			end
		end
	end
	return nil, nil
end

local function isBagSlotSoulbound(bag, slot)
	if not C_Container or not C_Container.GetContainerItemInfo then
		return false
	end
	local info = C_Container.GetContainerItemInfo(bag, slot)
	return info and info.isBound == true
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
	local out = {}
	local representatives = {}
	local validSlots = {}
	if not C_Container or not C_Container.GetContainerNumSlots then
		return {
			items = out,
			orderedItemIDs = {},
			representatives = representatives,
			signature = "",
		}
	end
	for bag = 0, getMaxOwnedBagIndex() do
		local slots = C_Container.GetContainerNumSlots(bag) or 0
		for slot = 1, slots do
			local itemID = C_Container.GetContainerItemID and C_Container.GetContainerItemID(bag, slot) or nil
			itemID = normalizeItemID(itemID)
			if itemID and not isBagSlotSoulbound(bag, slot) and isAuctionSellItemValid(bag, slot) then
				local count = 1
				if C_Container.GetContainerItemInfo then
					local info = C_Container.GetContainerItemInfo(bag, slot)
					if info and tonumber(info.stackCount) and tonumber(info.stackCount) > 0 then
						count = tonumber(info.stackCount)
					end
				end
				out[itemID] = (out[itemID] or 0) + count
				representatives[itemID] = representatives[itemID] or {
					bag = bag,
					slot = slot,
					stackQty = count,
				}
				validSlots[#validSlots + 1] = string.format("%d:%d:%d:%d", bag, slot, itemID, count)
			end
		end
	end
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

function ProfessionExporter:GetAuctionOwnedBagState(forceRefresh)
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

function ProfessionExporter:GetAuctionRepresentativeBagSlot(itemID, bagState)
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

local function formatPercent(value)
	if not value then
		return "-"
	end
	return string.format("%.1f%%", value)
end

function ProfessionExporter:FormatPercent(value)
	return formatPercent(value)
end

local function containsText(haystack, needle)
	return string.find(string.lower(tostring(haystack or "")), string.lower(tostring(needle or "")), 1, true) ~= nil
end

local function formatDurationShort(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local minutes = math.floor(seconds / 60)
	local remaining = seconds % 60
	if minutes <= 0 then
		return string.format("%ds", remaining)
	end
	return string.format("%dm %02ds", minutes, remaining)
end

function ProfessionExporter:FormatDurationShort(seconds)
	return formatDurationShort(seconds)
end

local function attachSimpleTooltip(widget, title, body)
	if not widget then
		return
	end
	widget:SetScript("OnEnter", function(self)
		local theme = ProfessionExporter:GetTheme()
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(title or "", 1, 1, 1)
		if body and body ~= "" then
			GameTooltip:AddLine(body, theme.textMuted.r, theme.textMuted.g, theme.textMuted.b, true)
		end
		GameTooltip:Show()
	end)
	widget:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

function ProfessionExporter:AttachSimpleTooltip(widget, title, body)
	attachSimpleTooltip(widget, title, body)
end

-- UIPanelButtonTemplate button: size {w, h}, label, five-value anchor and click handler.
local function panelButton(panel, size, text, point, onClick)
	local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	button:SetSize(size[1], size[2])
	button:SetPoint(point[1], point[2], point[3], point[4], point[5])
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

function ProfessionExporter:CreateAuctionPanelButton(panel, size, text, point, onClick)
	return panelButton(panel, size, text, point, onClick)
end

local function normalizeSearchEventItemID(eventArg)
	if type(eventArg) == "number" or type(eventArg) == "string" then
		return normalizeItemID(eventArg)
	end
	if type(eventArg) ~= "table" then
		return nil
	end
	if eventArg.itemKey then
		return normalizeItemID(eventArg.itemKey)
	end
	return normalizeItemID(eventArg)
end

--- Normalize optional fields for C_AuctionHouse.MakeItemKey(itemID, itemLevel, itemSuffix, battlePetSpeciesID).
--- Returns nil when no narrowing fields are present (use generic item key / commodity path).
function ProfessionExporter:NormalizeAuctionItemKeyFields(fields)
	if type(fields) ~= "table" then
		return nil
	end
	local ilvl = fields.itemLevel
	local suffix = fields.itemSuffix
	local pet = fields.battlePetSpeciesID
	if ilvl == nil and suffix == nil and pet == nil then
		return nil
	end
	return {
		itemLevel = math.max(0, math.floor(tonumber(ilvl) or 0)),
		itemSuffix = math.max(0, math.floor(tonumber(suffix) or 0)),
		battlePetSpeciesID = math.max(0, math.floor(tonumber(pet) or 0)),
	}
end

--- Stable sort / map key for (itemID, optional item key fields).
function ProfessionExporter:SerializeAuctionItemKeyFields(itemID, keyFields)
	itemID = normalizeItemID(itemID) or 0
	local f = self:NormalizeAuctionItemKeyFields(keyFields)
	if not f then
		return string.format("%d:", itemID)
	end
	return string.format("%d:%d:%d:%d", itemID, f.itemLevel, f.itemSuffix, f.battlePetSpeciesID)
end

function ProfessionExporter:DoesAuctionSearchEventMatchItem(scanItemID, eventArg, scanKeyFields)
	scanItemID = normalizeItemID(scanItemID)
	if not scanItemID then
		return false
	end
	if type(eventArg) == "number" or type(eventArg) == "string" then
		return tonumber(normalizeItemID(eventArg)) == tonumber(scanItemID)
	end
	if type(eventArg) ~= "table" then
		return false
	end
	local evKey = eventArg.itemKey or eventArg
	local evId = normalizeSearchEventItemID(evKey)
	if evId == nil then
		evId = normalizeSearchEventItemID(eventArg)
	end
	if tonumber(evId) ~= tonumber(scanItemID) then
		return false
	end
	if not scanKeyFields or not self:NormalizeAuctionItemKeyFields(scanKeyFields) then
		return true
	end
	-- Item keys are tables: compare what they hold, never the tables themselves.
	return self:SerializeAuctionItemKeyFields(scanItemID, scanKeyFields) == self:SerializeAuctionItemKeyFields(evId, evKey)
end

function ProfessionExporter:MakeAuctionHouseItemKey(itemID, keyFields)
	itemID = normalizeItemID(itemID)
	if not itemID or not C_AuctionHouse then
		return nil
	end
	local f = self:NormalizeAuctionItemKeyFields(keyFields)
	if C_AuctionHouse.MakeItemKey then
		if f then
			local ok, key = pcall(C_AuctionHouse.MakeItemKey, itemID, f.itemLevel, f.itemSuffix, f.battlePetSpeciesID)
			if ok and key then
				return key
			end
		end
		local ok, key = pcall(C_AuctionHouse.MakeItemKey, itemID)
		if ok and key then
			return key
		end
	end
	if ItemKeyMixin and ItemKeyMixin.CreateFromItemID then
		return ItemKeyMixin:CreateFromItemID(itemID)
	end
	return nil
end

local function copyScanKeyFields(fields)
	local n = ProfessionExporter:NormalizeAuctionItemKeyFields(fields)
	if not n then
		return nil
	end
	return {
		itemLevel = n.itemLevel,
		itemSuffix = n.itemSuffix,
		battlePetSpeciesID = n.battlePetSpeciesID,
	}
end

function ProfessionExporter:AuctionScanEntryKey(itemID, keyFields)
	return self:SerializeAuctionItemKeyFields(itemID, keyFields)
end

function ProfessionExporter:GetAuctionSearchedTargetsState()
	local state = self:GetState()
	state.auctionSearchedTargets = state.auctionSearchedTargets or {}
	state.auctionSearchedTargetsMeta = state.auctionSearchedTargetsMeta or {}
	return state.auctionSearchedTargets, state.auctionSearchedTargetsMeta
end

function ProfessionExporter:HasAuctionTargetBeenSearchedThisSession(itemID, keyFields)
	local searched = self:GetAuctionSearchedTargetsState()
	local key = self:AuctionScanEntryKey(itemID, keyFields)
	return searched[key] == true
end

function ProfessionExporter:MarkAuctionTargetSearched(itemID, keyFields, source, seenAt)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return false
	end
	local searched, meta = self:GetAuctionSearchedTargetsState()
	local ts = tonumber(seenAt) or now()
	local key = self:AuctionScanEntryKey(itemID, keyFields)
	searched[key] = true
	meta[key] = {
		itemID = itemID,
		itemKeyFields = copyScanKeyFields(keyFields),
		source = tostring(source or "session"),
		seenAt = ts,
	}
	return true
end

function ProfessionExporter:ExtractAuctionItemKeyFieldsFromEventArg(eventArg)
	if type(eventArg) ~= "table" then
		return nil
	end
	local itemKey = eventArg.itemKey or eventArg
	if type(itemKey) ~= "table" then
		return nil
	end
	return self:NormalizeAuctionItemKeyFields({
		itemLevel = itemKey.itemLevel,
		itemSuffix = itemKey.itemSuffix,
		battlePetSpeciesID = itemKey.battlePetSpeciesID,
	})
end

--- Sum listed quantity + cheapest unit for commodities; per–ItemKey groups for non-commodity items.
function ProfessionExporter:GetLiveAuctionSearchAggregate(itemID, keyFields)
	itemID = normalizeItemID(itemID)
	if not itemID or not C_AuctionHouse then
		return nil
	end
	if C_AuctionHouse.GetNumCommoditySearchResults and C_AuctionHouse.GetCommoditySearchResultInfo then
		local n = tonumber(C_AuctionHouse.GetNumCommoditySearchResults(itemID)) or 0
		if n > 0 then
			local totalQty = 0
			local minUnit, maxUnit = nil, nil
			for i = 1, n do
				local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
				if info then
					totalQty = totalQty + math.max(0, tonumber(info.quantity) or 0)
					local u = tonumber(info.unitPrice)
					if u and u > 0 then
						minUnit = minUnit and math.min(minUnit, u) or u
						maxUnit = maxUnit and math.max(maxUnit, u) or u
					end
				end
			end
			if minUnit and minUnit > 0 then
				return {
					kind = "commodity",
					itemID = itemID,
					minUnitPrice = minUnit,
					maxUnitPrice = maxUnit,
					totalQuantity = math.max(1, totalQty),
					listingCount = n,
				}
			end
		end
	end
	local queryKey = self:MakeAuctionHouseItemKey(itemID, keyFields)
	if not queryKey or not C_AuctionHouse.GetNumItemSearchResults or not C_AuctionHouse.GetItemSearchResultInfo then
		return nil
	end
	local m = tonumber(C_AuctionHouse.GetNumItemSearchResults(queryKey)) or 0
	if m <= 0 then
		return nil
	end
	-- Item keys are tables, so rows are grouped and narrowed by what the key holds. A key whose
	-- fields are all zero asks for every variant and narrows nothing.
	local fields = self:NormalizeAuctionItemKeyFields(keyFields)
	local expectedKey = fields and (fields.itemLevel > 0 or fields.itemSuffix > 0 or fields.battlePetSpeciesID > 0)
		and self:SerializeAuctionItemKeyFields(itemID, fields) or nil
	local groups = {}
	for i = 1, m do
		local info = C_AuctionHouse.GetItemSearchResultInfo(queryKey, i)
		if info and info.itemKey then
			local rowKey = self:SerializeAuctionItemKeyFields(itemID, info.itemKey)
			-- Narrow search: ignore rows that do not match the requested ItemKey.
			if not expectedKey or rowKey == expectedKey then
				local g = groups[rowKey]
				if not g then
					g = { key = rowKey, itemKey = info.itemKey, totalQuantity = 0, minUnitPrice = nil, maxUnitPrice = nil, listingCount = 0 }
					groups[rowKey] = g
				end
				local qty = math.max(1, tonumber(info.quantity) or 1)
				g.totalQuantity = g.totalQuantity + qty
				g.listingCount = g.listingCount + 1
				local buyout = tonumber(info.buyoutAmount)
				if buyout and buyout > 0 then
					local unit = math.floor(buyout / qty)
					if unit and unit > 0 then
						g.minUnitPrice = g.minUnitPrice and math.min(g.minUnitPrice, unit) or unit
						g.maxUnitPrice = g.maxUnitPrice and math.max(g.maxUnitPrice, unit) or unit
					end
				end
			end
		end
	end
	local variantList = {}
	local totalAll, listingsAll = 0, 0
	local cheapestGlobal, highestGlobal = nil, nil
	for _, g in pairs(groups) do
		if g.minUnitPrice and g.minUnitPrice > 0 then
			variantList[#variantList + 1] = g
			totalAll = totalAll + math.max(1, tonumber(g.totalQuantity) or 1)
			listingsAll = listingsAll + g.listingCount
			cheapestGlobal = cheapestGlobal and math.min(cheapestGlobal, g.minUnitPrice) or g.minUnitPrice
			highestGlobal = highestGlobal and math.max(highestGlobal, g.maxUnitPrice) or g.maxUnitPrice
		end
	end
	if #variantList == 0 then
		return nil
	end
	table.sort(variantList, function(a, b)
		return a.key < b.key
	end)
	return {
		kind = "item",
		itemID = itemID,
		variants = variantList,
		cheapestUnitPrice = cheapestGlobal,
		highestUnitPrice = highestGlobal,
		totalQuantityAll = math.max(1, totalAll),
		listingCountAll = listingsAll,
	}
end

function ProfessionExporter:RecordLiveAuctionObservationsFromAggregate(itemID, agg, sourceTag)
	itemID = normalizeItemID(itemID)
	if not itemID or type(agg) ~= "table" then
		return
	end
	sourceTag = tostring(sourceTag or "native_refresh")
	local seenAt = now()
	if agg.kind == "commodity" then
		self:RecordAuctionObservation({
			itemID = itemID,
			isCommodity = true,
			marketLow = agg.minUnitPrice,
			minBuyout = agg.minUnitPrice,
			sampleSize = math.max(1, tonumber(agg.totalQuantity) or 1),
			source = sourceTag,
			seenAt = seenAt,
		})
		return
	end
	if agg.kind == "item" and type(agg.variants) == "table" then
		for _, v in ipairs(agg.variants) do
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

function ProfessionExporter:ApplyLiveAggregateToNativePrice(itemID, agg)
	itemID = normalizeItemID(itemID)
	if not itemID or type(agg) ~= "table" then
		return
	end
	local src = agg.kind == "commodity" and "commodity_aggregate_live" or "item_aggregate_live"
	if agg.kind == "commodity" then
		self:UpsertNativeAuctionPrice(itemID, agg.minUnitPrice, src, math.max(1, tonumber(agg.totalQuantity) or 1), now())
		return
	end
	if agg.kind == "item" and agg.cheapestUnitPrice and agg.cheapestUnitPrice > 0 then
		self:UpsertNativeAuctionPrice(itemID, agg.cheapestUnitPrice, src, math.max(1, tonumber(agg.totalQuantityAll) or 1), now())
	end
end

function ProfessionExporter:ProcessAuctionRefreshItem(itemID, scanKeyFields)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return self:BuildAuctionPanelPriceState(nil)
	end
	local agg = self:GetLiveAuctionSearchAggregate(itemID, scanKeyFields)
	if agg then
		self:RecordLiveAuctionObservationsFromAggregate(itemID, agg, "native_refresh")
		self:ApplyLiveAggregateToNativePrice(itemID, agg)
	end
	return self:BuildAuctionPanelPriceState(itemID)
end

function ProfessionExporter:GetAuctionPanelFallbackPrice(itemID)
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
		local st = self.db and self.db.settings or {}
		local marketStr = st.economyTSMMarketString or "dbmarket"
		local fallbackPrice, fallbackSource = self:GetMarketEstimateCopper(itemID, marketStr)
		if fallbackPrice and fallbackPrice > 0 then
			return fallbackPrice, "fallback:" .. tostring(fallbackSource or "market"), now()
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

function ProfessionExporter:BuildAuctionPanelPriceState(itemID)
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
		self:UpsertNativeAuctionPrice(itemID, livePrice, liveSource or "results_live", nativeListingQuantity, now())
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

function ProfessionExporter:ApplyAuctionPanelPriceState(row, priceState)
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

function ProfessionExporter:GetAuctionDisplayProfessionQualityRank(itemID)
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

function ProfessionExporter:UpdateAuctionRowDumpState(row)
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

function ProfessionExporter:UpdateAuctionPanelRowPrice(itemID, priceState)
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

function ProfessionExporter:SendAuctionPanelSearchQuery(itemID, scanKeyFields)
	itemID = normalizeItemID(itemID)
	if not itemID or not C_AuctionHouse then
		self:DebugLog("AH", "search skipped", {
			string.format("itemID=%s reason=no_c_auction_house", tostring(itemID)),
		})
		return false
	end
	local itemKey = self:MakeAuctionHouseItemKey(itemID, scanKeyFields)
	if not itemKey then
		self:DebugLog("AH", "search skipped", {
			string.format("itemID=%s reason=no_item_key", tostring(itemID)),
		})
		return false
	end
	local queryFunc = C_AuctionHouse.SendSearchQuery
	local queryApi = "SendSearchQuery"
	if type(queryFunc) ~= "function" and type(C_AuctionHouse.SendSellSearchQuery) == "function" then
		queryFunc = C_AuctionHouse.SendSellSearchQuery
		queryApi = "SendSellSearchQuery"
	end
	if type(queryFunc) ~= "function" then
		self:DebugLog("AH", "search skipped", {
			string.format("itemID=%d reason=no_query_func", itemID),
		})
		return false
	end
	local ok = pcall(queryFunc, itemKey, {}, true)
	if ok ~= true and queryApi ~= "SendSellSearchQuery" and type(C_AuctionHouse.SendSellSearchQuery) == "function" then
		local sellOk = pcall(C_AuctionHouse.SendSellSearchQuery, itemKey, {}, true)
		if sellOk == true then
			ok = true
			queryApi = "SendSellSearchQuery"
		end
	end
	self:DebugLog("AH", "search query", {
		string.format("itemID=%d ok=%s api=%s", itemID, tostring(ok == true), tostring(queryApi)),
	})
	return ok == true
end

function ProfessionExporter:FinishQueuedAuctionRefreshItem(itemID, _priceStateIgnored)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return
	end
	local state = self:GetState()
	local ctx = state.auctionSearchContext
	local scanKeyFields = nil
	if ctx and tonumber(ctx.itemID) == tonumber(itemID) then
		scanKeyFields = ctx.scanKeyFields
		state.auctionSearchContext = nil
	end
	self:MarkAuctionTargetSearched(itemID, scanKeyFields, "queue_finish", now())
	local priceState = self:ProcessAuctionRefreshItem(itemID, scanKeyFields)
	local currentPrice = tonumber(priceState.currentPrice)
	self:DebugLog("AH", "refresh resolved", {
		string.format("itemID=%d shown=%s source=%s native=%s fallback=%s", itemID, tostring(currentPrice), tostring(priceState.currentPriceSource), tostring(priceState.nativePrice), tostring(priceState.fallbackPrice)),
	})
	if currentPrice and currentPrice > 0 then
		local fetchedQty = tonumber(priceState.nativeListingQuantity)
		if not fetchedQty or fetchedQty <= 0 then
			local summary = self:GetItemEconomySummary(itemID, {})
			local snapshot = summary and summary.snapshot or nil
			fetchedQty = tonumber(snapshot and snapshot.sampleSize) or tonumber(snapshot and snapshot.quantity) or nil
		end
		self:DebugLog("AH", "refresh fetched", {
			string.format(
				"itemID=%d name=%s price=%s qty=%s source=%s",
				itemID,
				tostring(self:GetItemDisplayName(itemID) or "?"),
				tostring(currentPrice),
				tostring(fetchedQty or "?"),
				tostring(priceState.currentPriceSource or "unknown")
			),
		})
	end
	if currentPrice and currentPrice > 0 then
		state.auctionLivePriceByItem = state.auctionLivePriceByItem or {}
		state.auctionLivePriceByItem[itemID] = currentPrice
		state.auctionSourceCounts = state.auctionSourceCounts or { native = 0, snapshot = 0, fallback = 0 }
		if priceState.currentPriceIsNative then
			state.auctionSourceCounts.native = (state.auctionSourceCounts.native or 0) + 1
		elseif tostring(priceState.currentPriceSource or "") == "snapshot" then
			state.auctionSourceCounts.snapshot = (state.auctionSourceCounts.snapshot or 0) + 1
		else
			state.auctionSourceCounts.fallback = (state.auctionSourceCounts.fallback or 0) + 1
		end
	end
	self:UpdateAuctionPanelRowPrice(itemID, priceState)
	state.auctionScanDone = tonumber(state.auctionRefreshIndex) or 0
	state.auctionRefreshIndex = (tonumber(state.auctionRefreshIndex) or 1) + 1
	if (tonumber(state.auctionRefreshIndex) or 1) % 3 == 0 then
		self:RefreshAuctionHousePanel()
	end
	C_Timer.After(tonumber(state.auctionRefreshDelay) or 0.05, function()
		ProfessionExporter:ContinueQueuedAuctionRefresh()
	end)
end

function ProfessionExporter:OnAuctionRefreshSearchTimeout(token)
	local state = self:GetState()
	local ctx = state.auctionSearchContext
	if not ctx or tonumber(ctx.token) ~= tonumber(token) then
		return
	end
	self:DebugLog("AH", "search timeout", {
		string.format("itemID=%s token=%s", tostring(ctx.itemID), tostring(token)),
	})
	self:FinishQueuedAuctionRefreshItem(ctx.itemID, nil)
end

function ProfessionExporter:ContinueQueuedAuctionRefresh()
	local state = self:GetState()
	if not state.auctionRefreshRunning or state.auctionSearchContext then
		return
	end
	if state.auctionRefreshPaused == true then
		return
	end
	local scanList = state.auctionRefreshScanList or {}
	local index = tonumber(state.auctionRefreshIndex) or 1
	local entry = scanList[index]
	local itemID = entry and normalizeItemID(entry.itemID)
	local scanKeyFields = entry and entry.itemKeyFields or nil
	if not itemID then
		state.auctionRefreshRunning = false
		state.auctionRefreshQueue = {}
		state.auctionRefreshScanList = nil
		state.auctionRefreshIndex = nil
		state.auctionSearchContext = nil
		state.auctionRefreshPaused = false
		state.auctionRefreshPausedForBulk = false
		state.auctionRefreshStartedAt = nil
		self:MarkAuctionQueueScanCompleted()
		local invCrafts = state.auctionInvalidateCraftsAfterRefresh == true
		state.auctionInvalidateCraftsAfterRefresh = false
		if invCrafts and self.InvalidateCraftOpportunityCaches then
			self:InvalidateCraftOpportunityCaches()
			if self.NotifyDashboardUpdate then
				self:NotifyDashboardUpdate(true)
			end
			if self.RefreshCraftsTabIfVisible then
				self:RefreshCraftsTabIfVisible()
			end
		end
		if not state.auctionRoiRunning then
			state.auctionScanMode = "idle"
			state.auctionScanTotal = 0
			state.auctionScanDone = 0
			state.auctionActiveItemID = nil
		end
		self:MaybeStartDeferredAuctionBulk()
		self:RefreshAuctionHousePanel()
		return
	end
	state.auctionActiveItemID = itemID
	self:DebugLog("AH", "refresh step", {
		string.format("itemID=%d index=%d/%d", itemID, index, #scanList),
	})
	self:RecordAuctionTransaction({
		kind = "visible_refresh",
		itemID = itemID,
		quantity = 1,
		source = "queue",
	})
	-- Do not prime Blizzard's sell frame during automatic refresh scans.
	-- On first AH open, especially for commodities, Blizzard can throw internally while
	-- resolving the sell/post pane before its view state is fully initialized.
	-- We rely on explicit search queries here instead; manual sell/bulk-post paths still
	-- use TrySendItemToAuctionSellFrame where appropriate.
	if self:SendAuctionPanelSearchQuery(itemID, scanKeyFields) then
		local token = (tonumber(state.auctionSearchToken) or 0) + 1
		state.auctionSearchToken = token
		state.auctionSearchContext = {
			itemID = itemID,
			scanKeyFields = copyScanKeyFields(scanKeyFields),
			token = token,
			startedAt = GetTime and GetTime() or 0,
		}
		C_Timer.After(1.5, function()
			ProfessionExporter:OnAuctionRefreshSearchTimeout(token)
		end)
		return
	end
	self:FinishQueuedAuctionRefreshItem(itemID, nil)
end

function ProfessionExporter:BuildAuctionBulkRows(mode)
	mode = tostring(mode or "post_all")
	local state = self:GetState()
	local rows = {}
	local sourceRows = self:FilterAuctionPanelRows(state.auctionPanelRows or {})
	state.auctionVisibleRows = sourceRows
	for _, row in ipairs(sourceRows) do
		local keep = row and row.itemID and (tonumber(row.quantitySellable) or tonumber(row.quantityOwned) or 0) > 0
		if keep and row.isIgnoredByRule == true then
			keep = false
		end
		if keep and row.canBulkPost == false then
			keep = false
		end
		if keep and mode == "post_profitable" then
			keep = (tonumber(row.potentialROI) or -999) > 0
		end
		if keep then
			rows[#rows + 1] = row
		end
	end
	return rows
end

function ProfessionExporter:MaybeStartDeferredAuctionBulk()
	local state = self:GetState()
	local bulk = state.auctionBulk
	if not bulk or bulk.running ~= true or bulk.awaitingScan ~= true then
		return
	end
	if state.auctionRefreshRunning or state.auctionRoiRunning then
		return
	end
	local rows = self:BuildAuctionBulkRows(bulk.mode)
	if #rows == 0 then
		self:PrintMessage(bulk.mode == "post_profitable" and "No profitable visible rows to post." or "No visible auction rows to post.")
		state.auctionBulk = nil
		self:RefreshAuctionHousePanel()
		return
	end
	bulk.awaitingScan = false
	bulk.rows = rows
	bulk.total = #rows
	bulk.done = 0
	bulk.selected = 0
	bulk.posted = 0
	bulk.skippedDumped = 0
	bulk.failed = 0
	bulk.index = 1
	bulk.phase = "selecting"
	bulk.status = "Starting..."
	bulk.currentItemID = nil
	bulk.retryCount = 0
	bulk.currentSelectionCounted = false
	bulk.paused = false
	self:RefreshAuctionHousePanel()
	C_Timer.After(0.05, function()
		ProfessionExporter:ContinueAuctionBulkPost()
	end)
end

function ProfessionExporter:FinishAuctionBulkJob()
	local state = self:GetState()
	local bulk = state.auctionBulk
	if not bulk then
		return
	end
	local modeLabel = bulk.mode == "post_profitable" and "profitable" or "all"
	bulk.running = false
	bulk.phase = nil
	bulk.currentItemID = nil
	bulk.status = "Completed"
	bulk.paused = false
	self:PrintMessage(string.format(
		"Auction bulk post (%s) complete: selected %d/%d, posted %d, skipped dumped %d, failed %d.",
		modeLabel,
		tonumber(bulk.selected) or 0,
		tonumber(bulk.total) or 0,
		tonumber(bulk.posted) or 0,
		tonumber(bulk.skippedDumped) or 0,
		tonumber(bulk.failed) or 0
	))
	self:ResumeAuctionScanAfterBulkPost()
	self:RefreshAuctionHousePanel()
end

function ProfessionExporter:ToggleAuctionRefreshPause()
	local state = self:GetState()
	if state.auctionRefreshRunning ~= true then
		return
	end
	state.auctionRefreshPaused = state.auctionRefreshPaused ~= true
	if state.auctionRefreshPaused == true then
		self:DebugLog("AH", "scan paused", {
			string.format("mode=%s itemID=%s index=%s", tostring(state.auctionScanMode), tostring(state.auctionActiveItemID), tostring(state.auctionRefreshIndex)),
		})
	else
		state.auctionRefreshPausedForBulk = false
		self:DebugLog("AH", "scan resumed", {
			string.format("mode=%s itemID=%s index=%s", tostring(state.auctionScanMode), tostring(state.auctionActiveItemID), tostring(state.auctionRefreshIndex)),
		})
		if state.auctionSearchContext then
			self:RefreshAuctionHousePanel()
			return
		end
		C_Timer.After(0.05, function()
			ProfessionExporter:ContinueQueuedAuctionRefresh()
		end)
	end
	self:RefreshAuctionHousePanel()
end

function ProfessionExporter:FailAuctionBulkCurrent(reason)
	local state = self:GetState()
	local bulk = state.auctionBulk
	if not bulk or bulk.running ~= true then
		return
	end
	local itemID = normalizeItemID(bulk.currentItemID)
	bulk.failed = (tonumber(bulk.failed) or 0) + 1
	bulk.done = math.min(tonumber(bulk.total) or 0, tonumber(bulk.index) or 1)
	bulk.status = string.format("%s: %s", tostring(reason or "Failed"), itemID and self:GetItemDisplayName(itemID) or "?")
	bulk.index = (tonumber(bulk.index) or 1) + 1
	bulk.phase = "selecting"
	bulk.currentItemID = nil
	bulk.retryCount = 0
	bulk.currentSelectionCounted = false
	bulk.paused = false
	self:DebugLog("AH", "bulk failed current", {
		string.format("reason=%s itemID=%s index=%s", tostring(reason), tostring(itemID), tostring(bulk.index)),
	})
	self:RefreshAuctionHousePanel()
	C_Timer.After(0.08, function()
		ProfessionExporter:ContinueAuctionBulkPost()
	end)
end

function ProfessionExporter:ConfirmAuctionBulkCurrent(source)
	local state = self:GetState()
	local bulk = state.auctionBulk
	if not bulk or bulk.running ~= true or bulk.phase ~= "waiting_confirmation" then
		return false
	end
	local itemID = normalizeItemID(bulk.currentItemID)
	if not itemID then
		return false
	end
	self:RecordAuctionTransaction({
		kind = "posted",
		itemID = itemID,
		quantity = 1,
		source = tostring(source or "auction_event"),
	})
	bulk.posted = (tonumber(bulk.posted) or 0) + 1
	bulk.done = math.min(tonumber(bulk.total) or 0, tonumber(bulk.index) or 1)
	bulk.status = string.format("Confirmed: %s", self:GetItemDisplayName(itemID))
	bulk.index = (tonumber(bulk.index) or 1) + 1
	bulk.phase = "selecting"
	bulk.currentItemID = nil
	bulk.retryCount = 0
	bulk.currentSelectionCounted = false
	bulk.paused = false
	state.recentAuctionBulkConfirmation = {
		itemID = itemID,
		at = GetTime and GetTime() or 0,
	}
	self:DebugLog("AH", "bulk confirmed", {
		string.format("itemID=%d source=%s posted=%d/%d", itemID, tostring(source), tonumber(bulk.posted) or 0, tonumber(bulk.total) or 0),
	})
	self:PrimeAuctionPanelRows()
	self:RefreshAuctionHousePanel()
	C_Timer.After(0.18, function()
		ProfessionExporter:ContinueAuctionBulkPost()
	end)
	return true
end

-- Throttle for bulk actions: seconds between an item landing in the sell frame and its post being
-- accepted, and between two auction cancels.
local AUCTION_BULK_MIN_INTERVAL = 1.0

function ProfessionExporter:ProcessAuctionBulkPhase(token)
	local state = self:GetState()
	local bulk = state.auctionBulk
	if not bulk or bulk.running ~= true or tonumber(bulk.token) ~= tonumber(token) then
		return
	end
	if bulk.paused == true then
		return
	end
	if bulk.phase == "waiting_confirmation" then
		local elapsed = (GetTime and GetTime() or 0) - (tonumber(bulk.confirmationStartedAt) or 0)
		if elapsed >= 2.5 then
			bulk.retryCount = (tonumber(bulk.retryCount) or 0) + 1
			if (tonumber(bulk.retryCount) or 0) >= (tonumber(bulk.maxRetries) or 8) then
				self:FailAuctionBulkCurrent("Timed out")
				return
			end
			bulk.phase = "selecting"
			bulk.status = string.format("Timed out, retrying (%d/%d): %s", bulk.retryCount, bulk.maxRetries, self:GetItemDisplayName(bulk.currentItemID))
			self:DebugLog("AH", "bulk confirmation timeout", {
				string.format("itemID=%s retry=%d/%d", tostring(bulk.currentItemID), bulk.retryCount, bulk.maxRetries),
			})
			self:RefreshAuctionHousePanel()
			C_Timer.After(0.20, function()
				ProfessionExporter:ContinueAuctionBulkPost()
			end)
			return
		end
		self:RefreshAuctionHousePanel()
		C_Timer.After(0.25, function()
			ProfessionExporter:ProcessAuctionBulkPhase(token)
		end)
	end
end

function ProfessionExporter:ContinueAuctionBulkPost()
	local state = self:GetState()
	local bulk = state.auctionBulk
	if not bulk or bulk.running ~= true then
		return
	end
	if bulk.paused == true or bulk.awaitingScan == true or bulk.phase == "waiting_confirmation" then
		return
	end
	local row = bulk.rows and bulk.rows[bulk.index] or nil
	if not row then
		self:FinishAuctionBulkJob()
		return
	end
	bulk.currentItemID = row.itemID
	if row.isDumpedLow == true then
		bulk.skippedDumped = (tonumber(bulk.skippedDumped) or 0) + 1
		bulk.done = math.min(tonumber(bulk.total) or 0, tonumber(bulk.index) or 1)
		bulk.status = string.format("Skipped dumped: %s", self:GetItemDisplayName(row.itemID))
		bulk.index = (tonumber(bulk.index) or 1) + 1
		bulk.phase = "selecting"
		bulk.currentItemID = nil
		bulk.retryCount = 0
		bulk.currentSelectionCounted = false
		self:DebugLog("AH", "bulk skip dumped", {
			string.format("itemID=%s index=%s", tostring(row.itemID), tostring(bulk.index)),
		})
		self:RefreshAuctionHousePanel()
		C_Timer.After(0.05, function()
			ProfessionExporter:ContinueAuctionBulkPost()
		end)
		return
	end
	bulk.status = string.format("Selecting: %s", self:GetItemDisplayName(row.itemID))
	self:DebugLog("AH", "bulk select", {
		string.format("itemID=%s index=%s/%s retry=%s", tostring(row.itemID), tostring(bulk.index), tostring(bulk.total), tostring(bulk.retryCount or 0)),
	})
	local ok = self:TrySendItemToAuctionSellFrame(row.itemID)
	if not ok then
		self:FailAuctionBulkCurrent("Could not select")
		return
	end
	state.auctionActiveItemID = row.itemID
	state.auctionLastSellSelectionItemID = row.itemID
	if bulk.currentSelectionCounted ~= true then
		bulk.selected = (tonumber(bulk.selected) or 0) + 1
		bulk.currentSelectionCounted = true
	end
	bulk.phase = "waiting_button"
	bulk.token = (tonumber(bulk.token) or 0) + 1
	bulk.status = string.format("Click Post next: %s", self:GetItemDisplayName(row.itemID))
	-- Throttle: "Post next" unlocks a moment after the item lands in the sell frame, which also
	-- gives Blizzard's price lookup time to fill in the going price.
	bulk.nextPostAt = GetTime() + AUCTION_BULK_MIN_INTERVAL
	self:RefreshAuctionHousePanel()
	C_Timer.After(AUCTION_BULK_MIN_INTERVAL, function()
		ProfessionExporter:RefreshAuctionHousePanel()
	end)
end

--- Posts the item waiting in the sell frame. Must run from a real click: the client rejects
--- auction posts that don't come from a hardware event, so bulk posting is one click per auction.
function ProfessionExporter:PostAuctionBulkCurrent()
	local bulk = self:GetState().auctionBulk
	if not bulk or bulk.running ~= true or bulk.paused == true or bulk.phase ~= "waiting_button" then
		return
	end
	local nowSec = GetTime()
	if nowSec < (bulk.nextPostAt or 0) then
		return
	end
	local name = self:GetItemDisplayName(bulk.currentItemID)
	if not self:TryClickAuctionPostButton() then
		bulk.status = string.format("Auction house not ready, click again: %s", name)
		self:RefreshAuctionHousePanel()
		return
	end
	local token = bulk.token
	bulk.phase = "waiting_confirmation"
	bulk.confirmationStartedAt = nowSec
	bulk.status = string.format("Waiting for confirmation: %s", name)
	self:DebugLog("AH", "bulk click post", {
		string.format("itemID=%s token=%s", tostring(bulk.currentItemID), tostring(token)),
	})
	self:RefreshAuctionHousePanel()
	C_Timer.After(0.25, function()
		ProfessionExporter:ProcessAuctionBulkPhase(token)
	end)
end

function ProfessionExporter:OnOwnedAuctionsUpdated()
	if self:GetAuctionPanelActiveTab() == "auctions" then
		self:RefreshAuctionHousePanel()
	end
	local state = self:GetState()
	local bulk = state.auctionBulk
	if not bulk or bulk.running ~= true or bulk.phase ~= "waiting_confirmation" then
		return
	end
	local elapsed = (GetTime and GetTime() or 0) - (tonumber(bulk.confirmationStartedAt) or 0)
	if elapsed >= 0.20 then
		self:DebugLog("AH", "owned auctions updated confirm", {
			string.format("itemID=%s elapsed=%.2f", tostring(bulk.currentItemID), elapsed),
		})
		self:ConfirmAuctionBulkCurrent("owned_auctions_updated")
	end
end

function ProfessionExporter:ToggleAuctionBulkPause()
	local state = self:GetState()
	local bulk = state.auctionBulk
	if not bulk or bulk.running ~= true then
		return
	end
	bulk.paused = bulk.paused ~= true
	if bulk.paused then
		bulk.status = string.format("Paused: %s", bulk.currentItemID and self:GetItemDisplayName(bulk.currentItemID) or "idle")
		self:DebugLog("AH", "bulk paused", {
			string.format("phase=%s itemID=%s", tostring(bulk.phase), tostring(bulk.currentItemID)),
		})
	else
		bulk.status = string.format("Resuming: %s", bulk.currentItemID and self:GetItemDisplayName(bulk.currentItemID) or "next item")
		self:DebugLog("AH", "bulk resumed", {
			string.format("phase=%s itemID=%s", tostring(bulk.phase), tostring(bulk.currentItemID)),
		})
		if bulk.phase == "waiting_confirmation" then
			local token = tonumber(bulk.token)
			if token then
				C_Timer.After(0.05, function()
					ProfessionExporter:ProcessAuctionBulkPhase(token)
				end)
			end
		else
			C_Timer.After(0.05, function()
				ProfessionExporter:ContinueAuctionBulkPost()
			end)
		end
	end
	self:RefreshAuctionHousePanel()
end

function ProfessionExporter:InitAuctionDB()
	local db = self.db or self:BuildMergedRuntimeDB(self.baseDb or {}, self.professionsDb or {}, self.inventoryDb or {}, self.auctionStorageDb or {})
	if type(db) ~= "table" then
		return nil
	end
	self.db = self.db or db
	self.db.auction = self.db.auction or {}
	local auction = self.db.auction
	auction.snapshot = auction.snapshot or {}
	auction.snapshot.commodities = auction.snapshot.commodities or {}
	auction.snapshot.items = auction.snapshot.items or {}
	auction.history = auction.history or {}
	auction.history.hourly = auction.history.hourly or {}
	auction.history.daily = auction.history.daily or {}
	auction.transactions = auction.transactions or {}
	auction.transactions.events = auction.transactions.events or {}
	auction.indexes = auction.indexes or {}
	auction.indexes.byItemID = auction.indexes.byItemID or {}
	auction.indexes.byBagItem = auction.indexes.byBagItem or {}
	auction.indexes.byRecipeOutput = auction.indexes.byRecipeOutput or {}
	auction.indexes.byCharacterAuction = auction.indexes.byCharacterAuction or {}
	auction.rules = auction.rules or {}
	auction.rules.byItemID = auction.rules.byItemID or {}
	auction.itemLastScanAt = auction.itemLastScanAt or {}
	auction.itemDepositPerUnit = auction.itemDepositPerUnit or {}
	-- Version 2: item entries saved under a table address ("…:table: 0x…") are moved to real item keys.
	if (tonumber(auction.storageKeyVersion) or 1) < 2 and self.ForeverLogic and self.ForeverLogic.RepairAuctionStorageKeys then
		local moved = self.ForeverLogic.RepairAuctionStorageKeys(auction, function(itemID)
			return self:BuildAuctionStorageKey(itemID, "item")
		end)
		auction.storageKeyVersion = 2
		if moved > 0 then
			self:DebugLog("AH", "repaired auction storage keys", { string.format("moved=%d", moved) })
		end
	end
	return auction
end

-- A non-commodity item's deposit can only be asked for while the item is in the bags, so it is
-- remembered per item whenever one is posted and reused later for repost maths.
if C_AuctionHouse and C_AuctionHouse.PostItem and hooksecurefunc then
	hooksecurefunc(C_AuctionHouse, "PostItem", function(item, duration, quantity)
		pcall(function()
			local itemID = normalizeItemID(C_Item.GetItemID(item))
			local deposit = tonumber(C_AuctionHouse.CalculateItemDeposit(item, duration, quantity))
			if itemID and deposit and quantity > 0 then
				ProfessionExporter:InitAuctionDB().itemDepositPerUnit[tostring(itemID)] = deposit / quantity
			end
		end)
	end)
end

--- The deposit cancelling this auction forfeits, taken as what posting it again would cost at the
--- sell frame's current duration. Nil when unknown (an item posted before deposits were recorded)
--- or when the player has turned deposits off.
function ProfessionExporter:GetOwnedAuctionDeposit(info, itemID)
	if self:GetSetting("auction.repostIncludeDeposit", true) == false then
		return nil
	end
	local keyInfo = C_AuctionHouse.GetItemKeyInfo(info.itemKey)
	if keyInfo and keyInfo.isCommodity then
		local duration = tonumber(GetCVar("auctionHouseDurationDropdown")) or 2
		return tonumber(C_AuctionHouse.CalculateCommodityDeposit(itemID, duration, info.quantity))
	end
	local perUnit = tonumber(self:InitAuctionDB().itemDepositPerUnit[tostring(itemID)])
	return perUnit and math.floor(perUnit * info.quantity + 0.5) or nil
end

function ProfessionExporter:NormalizeAuctionSnapshotEntry(entry)
	if type(entry) ~= "table" then
		return nil
	end
	local fields = self.ForeverLogic and self.ForeverLogic.NormalizeMarketSnapshotFields(entry)
	if fields then
		return {
			seenAt = fields.seenAt,
			source = fields.source and tostring(fields.source) or nil,
			marketLow = fields.price,
			minBuyout = fields.price,
			marketHigh = fields.marketHigh,
			sampleSize = fields.sampleSize,
			listingCount = fields.listingCount,
		}
	end
	local price = auctionSnapshotPrice(entry)
	local seenAt = auctionSnapshotSeenAt(entry)
	local source = auctionSnapshotSource(entry)
	local sampleSize = auctionSnapshotSampleSize(entry)
	return {
		seenAt = seenAt,
		source = source and tostring(source) or nil,
		marketLow = price,
		minBuyout = price,
		marketHigh = tonumber(entry.h or entry.marketHigh),
		sampleSize = sampleSize,
		listingCount = tonumber(entry.n or entry.listingCount),
	}
end

function ProfessionExporter:BuildCompactAuctionSnapshotEntry(observation)
	if type(observation) ~= "table" then
		return nil
	end
	local price = tonumber(observation.p or observation.marketLow or observation.minBuyout or observation.price)
	local seenAt = tonumber(observation.t or observation.seenAt) or now()
	if not price or price <= 0 then
		return nil
	end
	local entry = {
		t = seenAt,
		p = price,
		s = tostring(observation.s or observation.source or "unknown"),
	}
	local qty = math.max(0, tonumber(observation.q or observation.sampleSize) or 0)
	if qty > 0 then
		entry.q = qty
	end
	local listingCount = tonumber(observation.n or observation.listingCount)
	if listingCount and listingCount > 0 then
		entry.n = math.floor(listingCount)
	end
	local marketHigh = tonumber(observation.h or observation.marketHigh)
	if marketHigh and marketHigh > 0 then
		entry.h = marketHigh
	end
	return entry
end

function ProfessionExporter:CompactAuctionStorageData()
	local auction = self:InitAuctionDB()
	if not auction then
		return
	end
	local function compactSnapshotRoot(root)
		for storageKey, entry in pairs(root or {}) do
			local compact = self:BuildCompactAuctionSnapshotEntry(entry)
			if compact then
				root[storageKey] = compact
			else
				root[storageKey] = nil
			end
		end
	end
	compactSnapshotRoot(auction.snapshot and auction.snapshot.commodities or nil)
	compactSnapshotRoot(auction.snapshot and auction.snapshot.items or nil)
	auction.history = auction.history or {}
	self:RollupDailyAuctionHistory()
	self:TrimAuctionHistory()
end

function ProfessionExporter:GetAuctionPriceFreshnessWindowSeconds()
	local minutes = tonumber(self:GetSetting("auction.priceFreshnessMinutes", 15)) or 15
	return math.max(60, minutes * 60)
end

function ProfessionExporter:IsItemAuctionScanStale(itemID, freshnessWindowSeconds, nowTs)
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
	local curTs = tonumber(nowTs) or now()
	return (curTs - lastScanAt) >= window
end

function ProfessionExporter:GetItemLastAuctionScanAt(itemID)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return nil
	end
	local auction = self:InitAuctionDB()
	return tonumber(auction.itemLastScanAt and auction.itemLastScanAt[tostring(itemID)])
end

function ProfessionExporter:TouchItemAuctionScanTimestamp(itemID, ts)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return
	end
	ts = tonumber(ts) or now()
	local auction = self:InitAuctionDB()
	auction.itemLastScanAt = auction.itemLastScanAt or {}
	local k = tostring(itemID)
	local prev = tonumber(auction.itemLastScanAt[k]) or 0
	if ts >= prev then
		auction.itemLastScanAt[k] = ts
	end
end

function ProfessionExporter:MarkAuctionQueueScanCompleted()
	local ts = now()
	local auction = self:InitAuctionDB()
	auction.lastQueueScanAt = ts
	self:GetState().auctionLastQueueScanCompletedAt = ts
end

function ProfessionExporter:GetLastAuctionQueueScanAt()
	local auction = self:InitAuctionDB()
	return tonumber(auction.lastQueueScanAt)
end

function ProfessionExporter:FormatAuctionScanAge(ts)
	ts = tonumber(ts)
	if not ts or ts <= 0 then
		return "never"
	end
	local sec = math.max(0, now() - ts)
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

function ProfessionExporter:GetAuctionItemRule(itemID)
	local auction = self:InitAuctionDB()
	itemID = normalizeItemID(itemID)
	if not auction or not itemID then
		return nil
	end
	local rules = auction.rules and auction.rules.byItemID or nil
	local rule = rules and rules[tostring(itemID)] or nil
	return rule and shallowCopy(rule) or nil
end

function ProfessionExporter:SetAuctionItemRule(itemID, updates)
	local auction = self:InitAuctionDB()
	itemID = normalizeItemID(itemID)
	if not auction or not itemID then
		return false
	end
	auction.rules = auction.rules or {}
	auction.rules.byItemID = auction.rules.byItemID or {}
	local key = tostring(itemID)
	local rule = auction.rules.byItemID[key] or {}
	for field, value in pairs(updates or {}) do
		if value == nil then
			rule[field] = nil
		else
			rule[field] = value
		end
	end
	if rule.ignore ~= true then
		rule.ignore = nil
	end
	local reserveQty = tonumber(rule.reserveQty)
	if reserveQty and reserveQty > 0 then
		rule.reserveQty = math.max(0, math.floor(reserveQty))
	else
		rule.reserveQty = nil
	end
	if next(rule) == nil then
		auction.rules.byItemID[key] = nil
	else
		rule.updatedAt = now()
		auction.rules.byItemID[key] = rule
	end
	return true
end

function ProfessionExporter:ClearAuctionItemRule(itemID)
	local auction = self:InitAuctionDB()
	itemID = normalizeItemID(itemID)
	if not auction or not itemID or not auction.rules or not auction.rules.byItemID then
		return false
	end
	auction.rules.byItemID[tostring(itemID)] = nil
	return true
end

function ProfessionExporter:GetAuctionRowProtectionState(itemID, quantityOwned, bagState)
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

function ProfessionExporter:GetSelectedAuctionPanelItemID()
	local state = self:GetState()
	return normalizeItemID(state and (state.auctionPanelSelectedItemID or state.auctionLastSellSelectionItemID))
end

function ProfessionExporter:RefreshAuctionPanelRules()
	local selectedItemID = self:GetSelectedAuctionPanelItemID()
	local rowState = self:GetAuctionRowProtectionState(selectedItemID, 0)
	local panel = self.ui and self.ui.auctionPanel or nil
	if not panel then
		return
	end
	if panel.btnIgnoreItem then
		panel.btnIgnoreItem:SetEnabled(selectedItemID ~= nil)
		panel.btnIgnoreItem:SetText((rowState.ignored == true) and "Unignore" or "Ignore")
	end
	if panel.btnReserveItem then
		panel.btnReserveItem:SetEnabled(selectedItemID ~= nil)
		if rowState.reserveQty and rowState.reserveQty > 0 then
			panel.btnReserveItem:SetText("Keep " .. tostring(rowState.reserveQty))
		else
			panel.btnReserveItem:SetText("Keep...")
		end
	end
	if panel.btnClearRule then
		panel.btnClearRule:SetEnabled(selectedItemID ~= nil and (rowState.ignored == true or (rowState.reserveQty or 0) > 0))
	end
end

function ProfessionExporter:ApplyAuctionReserve(itemID, value)
	local qty = math.max(0, math.floor(tonumber(value) or 0))
	self:SetAuctionItemRule(itemID, { reserveQty = qty > 0 and qty or nil })
	self:DebugLog("AH", "rule reserve set", { string.format("itemID=%d reserveQty=%d", itemID, qty) })
	self:PrimeAuctionPanelRows()
	self:RefreshAuctionHousePanel()
end

-- Small "Keep in bags" window beside the auction panel. It always acts on the item it was last opened
-- for (the old StaticPopup kept the first item it was ever shown with).
function ProfessionExporter:EnsureAuctionReserveWindow()
	if self._auctionReserveWindow then
		return self._auctionReserveWindow
	end
	local pe = self
	local theme = self:GetTheme()
	local f = CreateFrame("Frame", addonName .. "AuctionReserveWindow", UIParent, "BackdropTemplate")
	f:SetSize(300, theme.size.header + 1 + 12 + 18 + 10 + 14 + 4 + 26 + 12 + 26 + 12)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	self:StyleWindow(f)
	tinsert(UISpecialFrames, f:GetName())
	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:ClearAllPoints()
	f.close:SetPoint("RIGHT", f, "TOPRIGHT", -6, -(theme.size.header / 2))
	self:SkinCloseButton(f.close)
	f.close:SetScript("OnClick", function() f:Hide() end)
	f.title = self:CreateText(f, "GameFontNormalLarge", "gold")
	f.title:SetPoint("LEFT", f, "TOPLEFT", 12, -(theme.size.header / 2) - 1)
	f.title:SetPoint("RIGHT", f.close, "LEFT", -12, 0)
	f.title:SetText("Keep in bags")
	local rule = f:CreateTexture(nil, "BORDER")
	rule:SetPoint("TOPLEFT", 1, -theme.size.header)
	rule:SetPoint("TOPRIGHT", -1, -theme.size.header)
	rule:SetHeight(1)
	rule:SetColorTexture(theme.borderSubtle.r, theme.borderSubtle.g, theme.borderSubtle.b, 1)

	f.icon = self:CreateItemIcon(f)
	f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -(theme.size.header + 13))
	f.itemName = self:CreateText(f, "GameFontHighlightSmall")
	f.itemName:SetPoint("LEFT", f.icon, "RIGHT", 6, 0)
	f.itemName:SetPoint("RIGHT", f, "RIGHT", -12, 0)
	f.label = self:CreateText(f, "GameFontHighlightSmall", "textMuted")
	f.label:SetPoint("TOPLEFT", f.icon, "BOTTOMLEFT", 0, -10)
	f.input = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	f.input:SetHeight(22)
	f.input:SetPoint("TOPLEFT", f.label, "BOTTOMLEFT", 6, -6)
	f.input:SetPoint("RIGHT", f, "RIGHT", -18, 0)
	f.input:SetAutoFocus(false)
	f.input:SetNumeric(true)
	f.input:SetMaxLetters(6)
	self:SkinEditBox(f.input)
	local function accept()
		if f.itemID and f.onAccept then
			f.onAccept(f.itemID, f.input:GetText())
		end
		f:Hide()
	end
	f.input:SetScript("OnEnterPressed", accept)
	f.input:SetScript("OnEscapePressed", function() f:Hide() end)
	f.keep = self:CreateButton(f, "Keep", accept, { primary = true })
	f.keep:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
	f.cancel = self:CreateButton(f, "Cancel", function() f:Hide() end)
	f.cancel:SetPoint("RIGHT", f.keep, "LEFT", -8, 0)
	f.input:HookScript("OnTextChanged", function()
		local n = tonumber(f.input:GetText()) or 0
		pe:SetButtonLabel(f.keep, n > 0 and ("Keep " .. n) or "Remove keep")
	end)
	f:Hide()
	self._auctionReserveWindow = f
	return f
end

function ProfessionExporter:ShowAuctionReservePrompt(itemID)
	itemID = normalizeItemID(itemID)
	if not itemID then
		self:PrintMessage("Select an auction row first.")
		return
	end
	local current = tonumber((self:GetAuctionItemRule(itemID) or {}).reserveQty) or 0
	self:ShowKeepPrompt(itemID, "Never post below this many", current, self.ui and self.ui.auctionPanel, function(id, text)
		self:ApplyAuctionReserve(id, text)
	end)
end

--- The "Keep in bags" prompt for any keep rule: `label` under the item, the `current` amount, shown
--- over `anchor` when that is visible, and `onAccept(itemID, text)` when the player confirms.
function ProfessionExporter:ShowKeepPrompt(itemID, label, current, anchor, onAccept)
	local f = self:EnsureAuctionReserveWindow()
	f.itemID = itemID
	f.onAccept = onAccept
	f.label:SetText(label)
	f.icon:SetItem(itemID)
	local _, color = self:GetItemLook(itemID)
	f.itemName:SetText(self:GetItemDisplayName(itemID))
	f.itemName:SetTextColor(color.r, color.g, color.b)
	f.input:SetText(current > 0 and tostring(current) or "")
	f:ClearAllPoints()
	if anchor and anchor:IsShown() then
		f:SetPoint("TOPLEFT", anchor, "TOPLEFT", 40, -120)
	else
		f:SetPoint("CENTER")
	end
	f:Show()
	f.input:SetFocus()
	f.input:HighlightText()
end

local AUCTION_PANEL_TABS = { sell = true, cart = true, auctions = true }

--- The client only has the player's auctions after they are asked for; the answer arrives as
--- OWNED_AUCTIONS_UPDATED.
function ProfessionExporter:RequestOwnedAuctions()
	if C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions then
		pcall(C_AuctionHouse.QueryOwnedAuctions, {})
	end
end

function ProfessionExporter:OnAuctionCanceled()
	if self:GetAuctionPanelActiveTab() == "auctions" then
		self:RequestOwnedAuctions()
	end
end

function ProfessionExporter:GetAuctionPanelActiveTab(defaultTab)
	self.ui = self.ui or {}
	local tab = tostring(self.ui.auctionPanelActiveTab or defaultTab or "sell")
	return AUCTION_PANEL_TABS[tab] and tab or "sell"
end

function ProfessionExporter:SetAuctionPanelActiveTab(tabId, manual)
	self.ui = self.ui or {}
	tabId = AUCTION_PANEL_TABS[tabId] and tabId or "sell"
	self.ui.auctionPanelActiveTab = tabId
	if tabId == "auctions" then
		self:RequestOwnedAuctions()
	end
	if manual == true then
		self.ui.auctionPanelTabManual = true
	end
	if self.RefreshAuctionHousePanel then
		self:RefreshAuctionHousePanel()
	end
end

--- Track AH purchases until bags catch up so cart Have/Buy update immediately.
function ProfessionExporter:NoteAuctionCartPurchase(itemID, quantity, source)
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

function ProfessionExporter:GetAuctionCartEffectiveHave(itemID)
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

function ProfessionExporter:ClearSettledAuctionCartPurchaseCredits()
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

function ProfessionExporter:ScheduleAuctionCartPurchaseRefresh()
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
	for _, delaySec in ipairs({ 0.15, 0.45, 1.0 }) do
		C_Timer.After(delaySec, function()
			ProfessionExporter:ClearSettledAuctionCartPurchaseCredits()
			if ProfessionExporter.RefreshAuctionHousePanel then
				ProfessionExporter:RefreshAuctionHousePanel()
			end
		end)
	end
end

function ProfessionExporter:BuildAuctionCraftCartRows()
	self:ClearSettledAuctionCartPurchaseCredits()
	local summary = self:BuildCraftQueueSummary()
	local workSummary = self.BuildCraftingOrderWorkQueueSummary and self:BuildCraftingOrderWorkQueueSummary() or { reagentLines = {} }
	local merged = {}
	-- Order mats are upserted into craftQueue; skip those orderIDs when merging work-order summary.
	local mirroredOrderIDs = {}
	for _, entry in ipairs(self:GetCraftQueueRows()) do
		local oid = tonumber(entry and entry.orderID)
		if oid then
			mirroredOrderIDs[oid] = true
		end
	end

	local function mergeReagentLine(reagent, sourcePrefix)
		local itemID = tonumber(reagent.itemID)
		if not itemID then
			return
		end
		local need = tonumber(reagent.quantityNeeded or reagent.quantity) or 0
		local row = merged[itemID]
		if not row then
			row = {
				itemID = itemID,
				name = reagent.name or self:GetItemDisplayName(itemID),
				quantityNeeded = 0,
				currentCharacterQuantity = self:GetAuctionCartEffectiveHave(itemID),
				estimatedUnitPrice = tonumber(reagent.estimatedUnitPrice),
				estimatedPriceSource = reagent.estimatedPriceSource or reagent.priceSource,
				sources = {},
			}
			merged[itemID] = row
		end
		row.quantityNeeded = (tonumber(row.quantityNeeded) or 0) + need
		local unitPrice = tonumber(reagent.estimatedUnitPrice)
		if unitPrice and unitPrice > 0 and (not row.estimatedUnitPrice or unitPrice < row.estimatedUnitPrice) then
			row.estimatedUnitPrice = unitPrice
			row.estimatedPriceSource = reagent.estimatedPriceSource or reagent.priceSource
		end
		for _, src in ipairs(reagent.sources or {}) do
			local copy = {}
			for k, v in pairs(src) do
				copy[k] = v
			end
			if sourcePrefix and copy.recipeName then
				copy.recipeName = sourcePrefix .. tostring(copy.recipeName)
			elseif sourcePrefix and copy.orderID then
				copy.recipeName = sourcePrefix .. "Order #" .. tostring(copy.orderID)
			end
			row.sources[#row.sources + 1] = copy
		end
	end

	for _, reagent in ipairs(summary.reagentLines or {}) do
		mergeReagentLine(reagent, nil)
	end
	for _, reagent in ipairs(workSummary.reagentLines or {}) do
		local filteredNeed = 0
		local filteredSources = {}
		for _, src in ipairs(reagent.sources or {}) do
			local oid = tonumber(src and src.orderID)
			if not oid or not mirroredOrderIDs[oid] then
				filteredNeed = filteredNeed + (tonumber(src and src.quantity) or 0)
				filteredSources[#filteredSources + 1] = src
			end
		end
		if filteredNeed > 0 then
			local copy = {
				itemID = reagent.itemID,
				name = reagent.name,
				quantityNeeded = filteredNeed,
				quantity = filteredNeed,
				estimatedUnitPrice = reagent.estimatedUnitPrice,
				estimatedPriceSource = reagent.estimatedPriceSource or reagent.priceSource,
				sources = filteredSources,
			}
			mergeReagentLine(copy, "WO: ")
		end
	end

	local rows = {}
	for itemID, reagent in pairs(merged) do
		local desc = self:ResolveItemDescriptor(itemID) or nil
		local priceState = self:BuildAuctionPanelPriceState(itemID)
		reagent.currentCharacterQuantity = self:GetAuctionCartEffectiveHave(itemID)
		reagent.currentCharacterAvailable = math.min(tonumber(reagent.currentCharacterQuantity) or 0, tonumber(reagent.quantityNeeded) or 0)
		reagent.quantityToBuy = math.max(0, (tonumber(reagent.quantityNeeded) or 0) - (tonumber(reagent.currentCharacterQuantity) or 0))
		if self.BuildReagentMailAllocations then
			reagent.mailAllocations = self:BuildReagentMailAllocations(itemID, reagent.sources)
			reagent.mailToText = self:FormatMailAllocationsShort(reagent.mailAllocations)
		end
		if reagent.estimatedUnitPrice and reagent.quantityToBuy > 0 then
			reagent.estimatedBuyCost = reagent.estimatedUnitPrice * reagent.quantityToBuy
		end
		local sourceNames = {}
		local seenSources = {}
		for _, src in ipairs(reagent.sources or {}) do
			local label = tostring(src and src.recipeName or src and src.outputName or (src and src.orderID and ("Order #" .. tostring(src.orderID))) or "")
			if label ~= "" and not seenSources[label] then
				seenSources[label] = true
				sourceNames[#sourceNames + 1] = label
			end
		end
		table.sort(sourceNames)
		rows[#rows + 1] = {
			itemID = itemID,
			itemName = reagent.name,
			itemIcon = desc and desc.icon or 134400,
			itemClassLabel = desc and desc.itemType or "",
			itemSubclassLabel = desc and desc.itemSubType or "",
			quantityNeeded = tonumber(reagent.quantityNeeded) or 0,
			quantityHave = tonumber(reagent.currentCharacterAvailable) or 0,
			quantityOnCharacter = tonumber(reagent.currentCharacterQuantity) or 0,
			quantityToBuy = tonumber(reagent.quantityToBuy) or 0,
			estimatedUnitPrice = tonumber(reagent.estimatedUnitPrice),
			estimatedBuyCost = tonumber(reagent.estimatedBuyCost),
			estimatedPriceSource = reagent.estimatedPriceSource,
			mailAllocations = reagent.mailAllocations,
			mailToText = reagent.mailToText or "—",
			sourceText = (#sourceNames > 0 and table.concat(sourceNames, ", ")) or "—",
			sourceCount = #sourceNames,
			sources = reagent.sources or {},
			currentPrice = tonumber(priceState.currentPrice),
			currentPriceSource = priceState.currentPriceSource,
			currentPriceSeenAt = tonumber(priceState.currentPriceSeenAt),
			currentPriceIsNative = priceState.currentPriceIsNative == true,
			nativePrice = tonumber(priceState.nativePrice),
			fallbackPrice = tonumber(priceState.fallbackPrice),
		}
	end
	table.sort(rows, function(a, b)
		return tostring(a.itemName) < tostring(b.itemName)
	end)
	return rows, summary, workSummary
end

function ProfessionExporter:FilterAuctionCraftCartRows(rows)
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

local function moneyColumn(pe, id, label, field, optional)
	return {
		id = id, label = label, justifyH = "RIGHT", width = 78, sortable = true, defaultSort = "desc", optional = optional,
		sortValue = function(row) return tonumber(row and row[field]) or -1 end,
		getText = function(row) return row and row[field] and pe:FormatCopperShort(row[field]) or "-" end,
	}
end

function ProfessionExporter:BuildAuctionCartColumns()
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
			getDetail = function(row)
				local detail = row and row.sourceText and row.sourceText ~= "" and ("For " .. row.sourceText) or ""
				if row and row.mailToText and row.mailToText ~= "" and row.mailToText ~= "-" then
					detail = detail .. (detail ~= "" and " · " or "") .. "mail to " .. row.mailToText
				end
				return detail
			end,
			sortValue = function(row) return row and row.itemName end,
		}),
		have,
		count("quantityToBuy", "Buy", "quantityToBuy"),
		moneyColumn(pe, "estimatedUnitPrice", "Each", "estimatedUnitPrice", true),
		moneyColumn(pe, "estimatedBuyCost", "Cost", "estimatedBuyCost"),
	}
end

function ProfessionExporter:PauseAuctionScanForManualBuy(reason)
	local state = self:GetState()
	if state.auctionRefreshRunning == true and state.auctionRefreshPaused ~= true then
		state.auctionRefreshPaused = true
		self:DebugLog("AH", "scan paused for manual buy", {
			string.format("reason=%s mode=%s itemID=%s", tostring(reason or "manual_buy"), tostring(state.auctionScanMode), tostring(state.auctionActiveItemID)),
		})
		if self.RefreshAuctionHousePanel then
			self:RefreshAuctionHousePanel()
		end
		return true
	end
	return false
end

function ProfessionExporter:PauseAuctionScanForBulkPost()
	local state = self:GetState()
	if self:PauseAuctionScanForManualBuy("bulk_post") then
		state.auctionRefreshPausedForBulk = true
		return true
	end
	return false
end

function ProfessionExporter:StopAuctionScanForDump()
	local state = self:GetState()
	local wasRunning = state.auctionRefreshRunning == true
	if wasRunning then
		self:DebugLog("AH", "scan stopped for dump", {
			string.format("mode=%s itemID=%s index=%s", tostring(state.auctionScanMode), tostring(state.auctionActiveItemID), tostring(state.auctionRefreshIndex)),
		})
	end
	state.auctionSearchToken = (tonumber(state.auctionSearchToken) or 0) + 1
	state.auctionRefreshRunning = false
	state.auctionRefreshPaused = false
	state.auctionRefreshPausedForBulk = false
	state.auctionRefreshQueue = {}
	state.auctionRefreshScanList = nil
	state.auctionRefreshIndex = nil
	state.auctionSearchContext = nil
	state.auctionRefreshStartedAt = nil
	if wasRunning and not state.auctionRoiRunning then
		state.auctionScanMode = "idle"
		state.auctionScanTotal = 0
		state.auctionScanDone = 0
		state.auctionActiveItemID = nil
	end
	return wasRunning
end

function ProfessionExporter:ResumeAuctionScanAfterBulkPost()
	local state = self:GetState()
	if state.auctionRefreshPausedForBulk ~= true then
		return false
	end
	state.auctionRefreshPausedForBulk = false
	if state.auctionRefreshRunning ~= true or state.auctionRefreshPaused ~= true then
		return false
	end
	state.auctionRefreshPaused = false
	self:DebugLog("AH", "scan resumed after bulk", {
		string.format("mode=%s itemID=%s index=%s", tostring(state.auctionScanMode), tostring(state.auctionActiveItemID), tostring(state.auctionRefreshIndex)),
	})
	if state.auctionSearchContext then
		return true
	end
	C_Timer.After(0.05, function()
		ProfessionExporter:ContinueQueuedAuctionRefresh()
	end)
	return true
end

function ProfessionExporter:TryPrefillAuctionBuyQuantity(quantity)
	quantity = math.max(1, math.floor(tonumber(quantity) or 0))
	if quantity <= 0 then
		return false
	end
	local ah = _G.AuctionHouseFrame
	if not ah then
		return false
	end
	local candidates = {
		ah.CommoditiesBuyFrame and ah.CommoditiesBuyFrame.BuyDisplay and ah.CommoditiesBuyFrame.BuyDisplay.QuantityInput
			and ah.CommoditiesBuyFrame.BuyDisplay.QuantityInput.InputBox,
		ah.ItemBuyFrame and ah.ItemBuyFrame.QuantityInput and ah.ItemBuyFrame.QuantityInput.InputBox,
	}
	for _, input in ipairs(candidates) do
		if input and input.IsShown and input:IsShown() and input.SetText then
			input:SetText(tostring(quantity))
			if input.OnTextChanged then
				pcall(input.OnTextChanged, input, true)
			elseif input.GetScript and input:GetScript("OnTextChanged") then
				pcall(input:GetScript("OnTextChanged"), input, true)
			end
			if input.ClearFocus then
				input:ClearFocus()
			end
			return true
		end
	end
	return false
end

function ProfessionExporter:OpenAuctionBrowseSearchForItem(itemID, itemName, quantity)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return false
	end
	local ah = _G.AuctionHouseFrame
	if not ah or not ah.IsShown or not ah:IsShown() then
		return false
	end
	if ah.SetDisplayMode then
		local buyMode = Enum and Enum.AuctionHouseFrameDisplayMode and Enum.AuctionHouseFrameDisplayMode.Buy
			or _G.AuctionHouseFrameDisplayMode and _G.AuctionHouseFrameDisplayMode.Buy
		if buyMode then
			pcall(ah.SetDisplayMode, ah, buyMode)
		end
	end
	itemName = tostring(itemName or self:GetItemDisplayName(itemID) or "")
	if itemName == "" or itemName == "?" then
		return false
	end
	local state = self:GetState()
	state.auctionPendingBrowseSearch = {
		itemID = itemID,
		itemName = itemName,
		quantity = math.max(1, math.floor(tonumber(quantity) or 1)),
		startedAt = GetTime and GetTime() or 0,
	}
	if C_AuctionHouse and C_AuctionHouse.SendBrowseQuery then
		local ok = pcall(C_AuctionHouse.SendBrowseQuery, {
			searchString = itemName,
			sorts = {},
			filters = {},
			itemClassFilters = {},
		})
		return ok == true
	end
	if ah.SendBrowseQuery then
		local ok = pcall(ah.SendBrowseQuery, ah, itemName, 0, 0, { 4, 5, 6, 7, 8, 10, 9 })
		return ok == true
	end
	return false
end

function ProfessionExporter:TrySelectPendingAuctionBrowseResult()
	local state = self:GetState()
	local pending = state and state.auctionPendingBrowseSearch or nil
	if not pending then
		return false
	end
	local ah = _G.AuctionHouseFrame
	if not ah or not ah.SelectBrowseResult or not (C_AuctionHouse and C_AuctionHouse.GetBrowseResults) then
		return false
	end
	local results = C_AuctionHouse.GetBrowseResults() or {}
	local match = nil
	for _, result in ipairs(results) do
		local resultItemID = normalizeItemID(result and result.itemKey and result.itemKey.itemID)
		if tonumber(resultItemID) == tonumber(pending.itemID) then
			match = result
			break
		end
	end
	if not match then
		return false
	end
	local ok = pcall(ah.SelectBrowseResult, ah, match)
	if ok == true then
		state.auctionLastSellSelectionItemID = pending.itemID
		state.auctionCartSelectedItemID = pending.itemID
		local qty = tonumber(pending.quantity) or 1
		C_Timer.After(0, function()
			ProfessionExporter:TryPrefillAuctionBuyQuantity(qty)
		end)
		C_Timer.After(0.1, function()
			ProfessionExporter:TryPrefillAuctionBuyQuantity(qty)
		end)
		C_Timer.After(0.25, function()
			ProfessionExporter:TryPrefillAuctionBuyQuantity(qty)
		end)
		state.auctionPendingBrowseSearch = nil
		return true
	end
	return false
end

-- Classic AuctionFrame: Browse tab, item name in the search box, run the browse search.
local function searchClassicAuctionFrame(itemName)
	local frame, nameBox = _G.AuctionFrame, _G.BrowseName
	if not (frame and frame:IsShown() and nameBox and type(AuctionFrameBrowse_Search) == "function") then
		return false
	end
	if _G.AuctionFrameTab1 and type(AuctionFrameTab_OnClick) == "function" then
		pcall(AuctionFrameTab_OnClick, _G.AuctionFrameTab1, 1)
	end
	nameBox:SetText(itemName)
	if type(CanSendAuctionQuery) == "function" and not CanSendAuctionQuery() then
		return false
	end
	return pcall(AuctionFrameBrowse_Search) == true
end

--- Show an item's buy page in the open auction house (F30). Searches only; buying stays a player click.
function ProfessionExporter:OpenItemInAuctionHouse(itemID)
	itemID = normalizeItemID(itemID)
	if not itemID or not self:IsAuctionHouseFrameOpen() then
		return false
	end
	local desc = self:ResolveItemDescriptor(itemID)
	local itemName = desc and desc.name
	if not itemName or itemName == "" then
		self:GetItemDisplayName(itemID) -- asks the client to load the item for the next click
		self:PrintMessage("Item info is still loading. Click again in a moment.")
		return false
	end
	self:PauseAuctionScanForManualBuy("dashboard_buy")
	local ok = self:OpenAuctionBrowseSearchForItem(itemID, itemName, 1) or searchClassicAuctionFrame(itemName)
	if not ok then
		self:PrintMessage(string.format("Could not search the auction house for %s right now. Try again in a moment.", itemName))
	end
	return ok
end

function ProfessionExporter:SearchAuctionCartRow(row)
	row = type(row) == "table" and row or nil
	self:PauseAuctionScanForManualBuy("cart_search")
	local itemID = normalizeItemID(row and row.itemID or self:GetState().auctionCartSelectedItemID)
	if not itemID then
		return false
	end
	self:GetState().auctionCartSelectedItemID = itemID
	self:GetState().auctionLastSellSelectionItemID = itemID
	local itemName = row and (row.itemName or row.name) or self:GetItemDisplayName(itemID)
	local quantity = math.max(1, math.floor(tonumber(row and (row.quantityToBuy or row.quantity)) or 1))
	if self:OpenAuctionBrowseSearchForItem(itemID, itemName, quantity) then
		return true
	end
	return self:SendAuctionPanelSearchQuery(itemID, nil)
end

function ProfessionExporter:SearchAuctionCartRows(rows)
	local ids = {}
	for _, row in ipairs(rows or {}) do
		local itemID = normalizeItemID(row and row.itemID)
		if itemID and (tonumber(row and row.quantityToBuy) or 0) > 0 then
			ids[#ids + 1] = itemID
		end
	end
	if #ids == 0 or not self:CanStartFullAuctionSideActions(true) then
		return false
	end
	self:QueueVisibleAuctionRefresh(ids)
	return true
end

function ProfessionExporter:TryBuyAuctionCartRow(row)
	row = type(row) == "table" and row or nil
	self:PauseAuctionScanForManualBuy("cart_buy")
	local itemID = normalizeItemID(row and row.itemID or self:GetState().auctionCartSelectedItemID)
	local quantity = math.max(1, math.floor(tonumber(row and row.quantityToBuy) or 0))
	if not itemID or quantity <= 0 then
		self:PrintMessage("Select a shopping-cart row with something left to buy.")
		return false
	end
	self:GetState().auctionCartSelectedItemID = itemID
	local function attemptPurchase()
		local agg = self:GetLiveAuctionSearchAggregate(itemID, nil)
		if not agg then
			self:PrintMessage("No live search results yet for that reagent.")
			return false
		end
		if agg.kind ~= "commodity" then
			self:PrintMessage("Auto-buy is currently limited to commodity reagents. Search results are ready in the Blizzard AH.")
			return false
		end
		if not (C_AuctionHouse and C_AuctionHouse.StartCommoditiesPurchase and C_AuctionHouse.ConfirmCommoditiesPurchase) then
			self:PrintMessage("Commodity buy API not available on this client.")
			return false
		end
		local ok = pcall(C_AuctionHouse.StartCommoditiesPurchase, itemID, quantity)
		if not ok then
			self:PrintMessage("Could not start commodity purchase.")
			return false
		end
		local confirmOk = pcall(C_AuctionHouse.ConfirmCommoditiesPurchase, itemID, quantity)
		if not confirmOk then
			self:PrintMessage("Commodity purchase confirmation failed.")
			return false
		end
		self:PrintMessage(string.format("Buying %s x%s.", self:GetItemDisplayName(itemID), self:FormatNumberGrouped(quantity)))
		self:ScheduleAuctionCartPurchaseRefresh()
		C_Timer.After(0.6, function()
			ProfessionExporter:SearchAuctionCartRow({ itemID = itemID })
			ProfessionExporter:RefreshAuctionHousePanel()
		end)
		return true
	end
	if self:SearchAuctionCartRow({ itemID = itemID }) then
		C_Timer.After(0.75, attemptPurchase)
		return true
	end
	return attemptPurchase()
end

function ProfessionExporter:HideExtraAuctionHousePanels(keepPanel)
	for _, frameName in ipairs(KNOWN_AH_SIDE_PANELS) do
		local frame = _G[frameName]
		if frame and frame ~= keepPanel and frame.IsObjectType and frame:IsObjectType("Frame") and frame.Hide then
			frame:Hide()
		end
	end
end

local function searchSelectedCartRow(panel)
	local rows = panel.cartTable and panel.cartTable.rows or nil
	local selected = ProfessionExporter:GetState().auctionCartSelectedItemID
	if selected then
		ProfessionExporter:SearchAuctionCartRow({ itemID = selected })
	elseif type(rows) == "table" and #rows > 0 then
		ProfessionExporter:SearchAuctionCartRow(rows[1])
	end
end

local function priceAllCartRows()
	local rows = ProfessionExporter:FilterAuctionCraftCartRows(select(1, ProfessionExporter:BuildAuctionCraftCartRows()))
	ProfessionExporter:SearchAuctionCartRows(rows)
end

-- Selected cart item, or the first shown cart row when nothing is selected.
local function selectedOrFirstCartItemID(panel)
	local selected = ProfessionExporter:GetState().auctionCartSelectedItemID
	if not selected and panel.cartTable and panel.cartTable.rows then
		local rows = panel.cartTable.rows or {}
		selected = rows[1] and rows[1].itemID or nil
	end
	return selected
end

local function buyCheapestCartSelection(panel)
	local selected = selectedOrFirstCartItemID(panel)
	if not selected then
		ProfessionExporter:PrintMessage("Select a shopping-cart row first.")
		return
	end
	local rows = ProfessionExporter:FilterAuctionCraftCartRows(select(1, ProfessionExporter:BuildAuctionCraftCartRows()))
	for _, row in ipairs(rows) do
		if tonumber(row.itemID) == tonumber(selected) then
			ProfessionExporter:TryBuyAuctionCartRow(row)
			break
		end
	end
end

local function removeSelectedCartSources()
	local selected = ProfessionExporter:GetState().auctionCartSelectedItemID
	if not selected then
		ProfessionExporter:PrintMessage("Select a shopping-cart row first.")
		return
	end
	local pe = ProfessionExporter
	local removedCrafts = pe.RemoveCraftQueueLinesByReagentItem and pe:RemoveCraftQueueLinesByReagentItem(selected) or 0
	local removedOrders = pe.RemoveCraftingOrdersByReagentItem and pe:RemoveCraftingOrdersByReagentItem(selected) or 0
	if (removedCrafts + removedOrders) > 0 then
		pe:PrintMessage(string.format(
			"Removed %d craft queue entries and %d crafting orders for item #%s.",
			removedCrafts, removedOrders, tostring(selected)
		))
	else
		pe:PrintMessage("No shopping-cart sources were removed for the selected item.")
	end
	pe:GetState().auctionCartSelectedItemID = nil
	pe:RefreshAuctionHousePanel()
end

local function clearCartSources()
	if ProfessionExporter.ClearCraftQueue then
		ProfessionExporter:ClearCraftQueue()
	end
	if ProfessionExporter.ClearCraftingOrderWorkQueue then
		ProfessionExporter:ClearCraftingOrderWorkQueue()
	end
	ProfessionExporter:GetState().auctionCartSelectedItemID = nil
	ProfessionExporter:PrintMessage("Cleared shopping-cart sources.")
	ProfessionExporter:RefreshAuctionHousePanel()
end

-- Cart summary line and the search box that filters cart rows.
local function buildCartHeader(panel, title)
	panel.cartSummary = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.cartSummary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	panel.cartSummary:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
	panel.cartSummary:SetJustifyH("LEFT")
	panel.cartSummary:SetWordWrap(true)
	panel.cartSummary:Hide()
	panel.cartSearchBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
	panel.cartSearchBox:SetSize(140, 20)
	panel.cartSearchBox:SetAutoFocus(false)
	panel.cartSearchBox:SetPoint("TOPLEFT", panel.cartSummary, "BOTTOMLEFT", 0, -8)
	panel.cartSearchBox:SetScript("OnTextChanged", function(box)
		ProfessionExporter.ui = ProfessionExporter.ui or {}
		ProfessionExporter.ui.auctionCartFilterText = box:GetText() or ""
		ProfessionExporter:RefreshAuctionHousePanel()
	end)
	panel.cartSearchBox:Hide()
end

-- Cart-tab button, hidden until the refresh shows the cart tab.
local function cartButton(panel, size, text, point, onClick)
	local button = panelButton(panel, size, text, point, onClick)
	button:Hide()
	return button
end

local function buildCartButtons(panel)
	panel.btnCartSearch = cartButton(panel, { 58, 20 }, "Find selected", { "LEFT", panel.cartSearchBox, "RIGHT", 4, 0 }, function()
		searchSelectedCartRow(panel)
	end)
	attachSimpleTooltip(panel.btnCartSearch, "Search selected", "Runs an AH search for the selected shopping-cart row and refreshes the live price.")
	panel.btnCartRefresh = cartButton(panel, { 64, 20 }, "Price all", { "LEFT", panel.btnCartSearch, "RIGHT", 4, 0 }, priceAllCartRows)
	attachSimpleTooltip(panel.btnCartRefresh, "Scan all cart rows", "Queues AH searches for all shopping-cart rows that still need to be bought.")
	panel.btnCartBuy = cartButton(panel, { 86, 20 }, "Buy cheapest", { "TOPLEFT", panel.cartSearchBox, "BOTTOMLEFT", 0, -6 }, function()
		buyCheapestCartSelection(panel)
	end)
	attachSimpleTooltip(panel.btnCartBuy, "Buy cheapest",
		"Attempts a first-pass commodity purchase for the selected shopping-cart row using the current cheapest live result.")
	panel.btnCartRemove = cartButton(panel, { 70, 20 }, "Remove selected", { "LEFT", panel.btnCartBuy, "RIGHT", 4, 0 }, removeSelectedCartSources)
	attachSimpleTooltip(panel.btnCartRemove, "Remove selected item",
		"Removes queued crafts and queued crafting orders that contribute to the selected shopping-cart item.")
	panel.btnCartClear = cartButton(panel, { 56, 20 }, "Clear cart", { "LEFT", panel.btnCartRemove, "RIGHT", 4, 0 }, clearCartSources)
	attachSimpleTooltip(panel.btnCartClear, "Clear shopping cart", "Clears queued crafts and queued crafting orders that feed the shopping cart.")
end

local function appendCartMailLines(pe, lines, mailAllocations)
	for _, alloc in ipairs(type(mailAllocations) == "table" and mailAllocations or {}) do
		if (tonumber(alloc.mailQuantity) or 0) > 0 then
			lines[#lines + 1] = { "Mail to " .. tostring(alloc.characterKey), pe:FormatNumberGrouped(alloc.mailQuantity) }
		end
	end
end

local function showCartRowTooltip(rowFrame, rowData)
	if not rowData or not rowData.itemID then
		return
	end
	local pe = ProfessionExporter
	local lines = {
		{ "Need", pe:FormatNumberGrouped(rowData.quantityNeeded or 0) },
		{ "Have here", pe:FormatNumberGrouped(rowData.quantityOnCharacter or rowData.quantityHave or 0) },
		{ "Buy", pe:FormatNumberGrouped(rowData.quantityToBuy or 0) },
		{ "Cost to buy", rowData.estimatedBuyCost and pe:FormatCopperFull(rowData.estimatedBuyCost) or "no price yet" },
	}
	appendCartMailLines(pe, lines, rowData.mailAllocations)
	pe:ShowItemRowTooltip(rowFrame, rowData.itemID, lines, "Click to find it at the auction house")
end

local function buildCartTable(self, panel)
	panel.cartTableHost = CreateFrame("Frame", nil, panel)
	panel.cartTableHost:SetPoint("TOPLEFT", panel.btnCartBuy, "BOTTOMLEFT", 0, -8)
	panel.cartTableHost:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 52)
	panel.cartTableHost:Hide()
	panel.cartTable = self:CreateReusableTable(panel.cartTableHost, {
		rowHeight = 36,
		footer = true,
		emptyTitle = "Cart is empty",
		emptyHint = "Queue crafts to add their reagents here.",
		isRowSelected = function(rowData)
			return rowData and rowData.itemID ~= nil and rowData.itemID == ProfessionExporter:GetState().auctionCartSelectedItemID
		end,
		maxRows = 120,
		sortKey = "quantityToBuy",
		sortAsc = false,
		autoFitToScroll = true,
		onRowEnter = showCartRowTooltip,
		onRowLeave = function()
			GameTooltip:Hide()
		end,
		onRowClick = function(_, rowData)
			ProfessionExporter:GetState().auctionCartSelectedItemID = rowData and rowData.itemID or nil
			ProfessionExporter:SearchAuctionCartRow(rowData)
			ProfessionExporter:RefreshAuctionHousePanel()
		end,
	})
	if panel.cartTable and panel.cartTable.frame then
		panel.cartTable.frame:ClearAllPoints()
		panel.cartTable.frame:SetPoint("TOPLEFT", panel.cartTableHost, "TOPLEFT", 0, 0)
		panel.cartTable.frame:SetPoint("BOTTOMRIGHT", panel.cartTableHost, "BOTTOMRIGHT", 0, 0)
		panel.cartTable:SetColumns(self:BuildAuctionCartColumns())
	end
end

-- Cart tab: reagent summary, search, buy/remove/clear actions and the reagent table (hidden until shown).
function ProfessionExporter:BuildAuctionPanelCartTab(panel, title)
	buildCartHeader(panel, title)
	buildCartButtons(panel)
	buildCartTable(self, panel)
end

local OWNED_CANCEL_TIP = "Each click cancels one undercut auction, the most undercut first. "
	.. "The deposit is not refunded, and the item comes back by mail. Skips auctions with a bid, "
	.. "and ones where reposting at the lowest price would pay nothing after the cut and deposit."
local OWNED_CHECK_TIP = "Looks up the current lowest price of every item you have listed, to show which are undercut."

local function recheckOwnedAuctionPrices()
	local ids = {}
	for _, row in ipairs(ProfessionExporter:BuildOwnedAuctionRows()) do
		if not row.sold then
			ids[#ids + 1] = row.itemID
		end
	end
	ProfessionExporter:QueueVisibleAuctionRefresh(ids)
end

local function buildOwnedButtons(panel)
	panel.ownedSummary = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.ownedSummary:SetJustifyH("LEFT")
	panel.btnOwnedCheck = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	panel.btnOwnedCheck:SetText("Check prices")
	panel.btnOwnedCheck:SetScript("OnClick", recheckOwnedAuctionPrices)
	panel.btnOwnedCancel = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	panel.btnOwnedCancel:SetText("Cancel undercut")
	panel.btnOwnedCancel:SetScript("OnClick", function()
		ProfessionExporter:CancelNextUndercutAuction()
	end)
	attachSimpleTooltip(panel.btnOwnedCancel, "Cancel undercut", OWNED_CANCEL_TIP)
	attachSimpleTooltip(panel.btnOwnedCheck, "Check prices", OWNED_CHECK_TIP)
end

local function appendOwnedUndercutLines(pe, lines, rowData)
	lines[4] = { "Undercut by", string.format("%s each (%d%%)", pe:FormatCopperFull(rowData.undercutBy), math.max(1, math.floor(rowData.undercutPct + 0.5))) }
	if pe:GetSetting("auction.repostIncludeDeposit", true) ~= false then
		lines[#lines + 1] = { "Deposit lost on cancel", rowData.deposit and pe:FormatCopperFull(rowData.deposit) or "unknown, not counted" }
	end
	lines[#lines + 1] = { "If cancelled and reposted at lowest", rowData.repostNet > 0
		and string.format("%s (%s less)", pe:FormatCopperFull(rowData.repostNet), pe:FormatCopperFull(rowData.net - rowData.repostNet))
		or "not worth it" }
end

local function ownedRowTooltipLines(pe, panel, rowData)
	local lines = {}
	if not rowData.sold then
		local cutLabel = string.format("After %d%% cut", math.floor((panel.ownedCut or 0.05) * 100 + 0.5))
		lines[1] = { "Lowest scanned", rowData.marketPrice and pe:FormatCopperFull(rowData.marketPrice) or "not scanned this visit" }
		lines[2] = { "Scanned", pe:FormatAuctionScanAge(pe:GetItemLastAuctionScanAt(rowData.itemID)) }
		lines[3] = { cutLabel, pe:FormatCopperFull(rowData.net) }
		if rowData.undercut then
			appendOwnedUndercutLines(pe, lines, rowData)
		end
	end
	return lines
end

local function buildOwnedTable(self, panel)
	panel.ownedTableHost = CreateFrame("Frame", nil, panel)
	panel.ownedTable = self:CreateReusableTable(panel.ownedTableHost, {
		rowHeight = 24,
		footer = true,
		emptyTitle = "No auctions",
		emptyHint = "Items you post show up here.",
		maxRows = 200,
		sortKey = "status",
		sortAsc = false,
		autoFitToScroll = true,
		onRowEnter = function(rowFrame, rowData)
			local pe = ProfessionExporter
			local lines = ownedRowTooltipLines(pe, panel, rowData)
			pe:ShowItemRowTooltip(rowFrame, rowData.itemID, lines, not rowData.sold and "Click to recheck its price" or nil)
		end,
		onRowLeave = function()
			GameTooltip:Hide()
		end,
		onRowClick = function(_, rowData)
			if not rowData.sold then
				ProfessionExporter:QueueVisibleAuctionRefresh({ rowData.itemID })
			end
		end,
	})
	panel.ownedTable.frame:SetAllPoints(panel.ownedTableHost)
	panel.ownedTable:SetColumns(self:BuildOwnedAuctionColumns())
end

-- Auctions tab: totals, a price recheck and the player's own auctions.
function ProfessionExporter:BuildAuctionPanelOwnedTab(panel)
	buildOwnedButtons(panel)
	buildOwnedTable(self, panel)
end

local AH_PAD = 12
local AH_ROW = 26
local AH_ROW_GAP = 8

-- One scan control replaces four buttons: pick what to scan, then press Scan.
local AUCTION_SCAN_CHOICES = {
	{ value = "both", label = "Craft and account prices" },
	{ value = "crafts", label = "Craft prices" },
	{ value = "account", label = "Account items" },
	{ value = "shown", label = "Save shown prices" },
}

function ProfessionExporter:RunAuctionPanelScanChoice()
	local choice = self:GetSetting("auction.panelScanChoice", "both")
	if choice == "crafts" then
		self:QueueAuctionEconomyScan({ crafts = true })
	elseif choice == "account" then
		self:QueueAuctionEconomyScan({ accountInventory = true })
	elseif choice == "shown" then
		if not self:CanStartFullAuctionSideActions(true) then
			return
		end
		self:StartAuctionDump("visible")
	else
		self:QueueAuctionEconomyScan({ crafts = true, accountInventory = true })
	end
	self:RefreshAuctionHousePanel()
end

local function anchorRow(panel, frame, y)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", panel, "TOPLEFT", AH_PAD, -y)
	frame:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -AH_PAD, -y)
	frame:SetHeight(AH_ROW)
end

local function placeIn(row, frame, point, relative, relativePoint, x)
	frame:SetParent(row)
	frame:ClearAllPoints()
	frame:SetPoint(point, relative, relativePoint, x or 0, 0)
end

-- Re-anchors the panel to the shared design: 34px header with Sell / Cart / Auctions switch, rows of 26px controls
-- 8px apart inside a 12px inset, the table filling the rest, a progress row and a 24px status footer.
function ProfessionExporter:BuildAuctionPanelLayout(panel)
	local pe = self
	local ui = self.ui
	local theme = self:GetTheme()
	local headerHeight = theme.size.header

	panel:SetClampedToScreen(true)
	panel.title:SetFontObject("GameFontNormalLarge")
	panel.title:ClearAllPoints()
	panel.title:SetPoint("LEFT", panel, "TOPLEFT", 12, -(headerHeight / 2) - 1)
	panel.title:SetPoint("RIGHT", panel.tabCart, "LEFT", -12, 0)
	panel.title:SetWordWrap(false)
	panel.headerRule = panel:CreateTexture(nil, "BORDER")
	panel.headerRule:SetPoint("TOPLEFT", 1, -headerHeight)
	panel.headerRule:SetPoint("TOPRIGHT", -1, -headerHeight)
	panel.headerRule:SetHeight(1)
	panel.headerRule:SetColorTexture(theme.borderSubtle.r, theme.borderSubtle.g, theme.borderSubtle.b, 1)
	panel.subtitle:Hide()
	panel.stats:Hide()
	panel.subtitle.Show = panel.subtitle.Hide
	panel.stats.Show = panel.stats.Hide
	panel.subtitle.SetShown = function() end
	panel.stats.SetShown = function() end

	for _, tab in ipairs({ panel.tabSell, panel.tabCart, panel.tabAuctions }) do
		self:SkinButton(tab)
		tab:SetHeight(theme.size.controlSmall)
	end
	self:SetButtonLabel(panel.tabSell, "Sell", true)
	self:SetButtonLabel(panel.tabAuctions, "Auctions", true)
	-- Reading order: Sell, Cart, Auctions.
	panel.tabAuctions:ClearAllPoints()
	panel.tabAuctions:SetPoint("RIGHT", panel, "TOPRIGHT", -12, -(headerHeight / 2))
	panel.tabCart:ClearAllPoints()
	panel.tabCart:SetPoint("RIGHT", panel.tabAuctions, "LEFT", 1, 0)
	panel.tabSell:ClearAllPoints()
	panel.tabSell:SetPoint("RIGHT", panel.tabCart, "LEFT", 1, 0)
	panel.title:SetPoint("RIGHT", panel.tabSell, "LEFT", -12, 0)

	-- Footer: status text, resize grip.
	panel.footer = CreateFrame("Frame", nil, panel)
	panel.footer:SetPoint("BOTTOMLEFT", 1, 1)
	panel.footer:SetPoint("BOTTOMRIGHT", -1, 1)
	panel.footer:SetHeight(theme.size.footer)
	local footerRule = panel.footer:CreateTexture(nil, "BORDER")
	footerRule:SetPoint("TOPLEFT")
	footerRule:SetPoint("TOPRIGHT")
	footerRule:SetHeight(1)
	footerRule:SetColorTexture(theme.borderSubtle.r, theme.borderSubtle.g, theme.borderSubtle.b, 1)
	panel.resizeHandle:SetParent(panel.footer)
	panel.resizeHandle:ClearAllPoints()
	panel.resizeHandle:SetSize(14, 14)
	panel.resizeHandle:SetPoint("BOTTOMRIGHT", -2, 2)
	panel.footerText = self:CreateText(panel.footer, "GameFontHighlightSmall", "textMuted")
	panel.footerText:SetPoint("LEFT", AH_PAD, 0)
	panel.footerText:SetPoint("RIGHT", panel.resizeHandle, "LEFT", -8, 0)

	local y = headerHeight + 1 + AH_PAD
	-- Sell row 1: scan choice, Scan, Refresh shown, Full scan.
	panel.sellRow1 = CreateFrame("Frame", nil, panel)
	anchorRow(panel, panel.sellRow1, y)
	placeIn(panel.sellRow1, panel.btnDumpFull, "RIGHT", panel.sellRow1, "RIGHT")
	local refresh = panel.sellControls[1]
	placeIn(panel.sellRow1, refresh, "RIGHT", panel.btnDumpFull, "LEFT", -AH_ROW_GAP)
	panel.btnScanChoice = self:CreateButton(panel.sellRow1, "Scan", function()
		pe:RunAuctionPanelScanChoice()
	end, { tooltip = "Run the scan picked on the left. Keep the auction house open until it ends." })
	panel.btnScanChoice:SetPoint("RIGHT", refresh, "LEFT", -AH_ROW_GAP, 0)
	panel.scanChoice = self:CreateSingleSelectDropdown(panel.sellRow1, {
		width = 160,
		getOptions = function() return AUCTION_SCAN_CHOICES end,
		getValue = function() return pe:GetSetting("auction.panelScanChoice", "both") end,
		setValue = function(value) pe:SetSetting("auction.panelScanChoice", value) end,
		tooltip = "What to scan",
	})
	panel.scanChoice:SetPoint("LEFT", panel.sellRow1, "LEFT", 0, 0)
	panel.scanChoice:SetPoint("RIGHT", panel.btnScanChoice, "LEFT", -AH_ROW_GAP, 0)
	for _, old in ipairs({ panel.btnScanCraftPrices, panel.btnScanAccountInv, panel.btnScanCraftAndAccount, panel.btnDumpVisible }) do
		old:Hide()
		old.Show = old.Hide
		old.SetShown = function() end
	end

	-- Sell row 2: posting on the left, rules for the selected item on the right.
	y = y + AH_ROW + AH_ROW_GAP
	panel.sellRow2 = CreateFrame("Frame", nil, panel)
	anchorRow(panel, panel.sellRow2, y)
	placeIn(panel.sellRow2, panel.btnPostProfitable, "LEFT", panel.sellRow2, "LEFT")
	self:SetButtonPrimary(panel.btnPostProfitable, true)
	placeIn(panel.sellRow2, panel.btnPostAll, "LEFT", panel.btnPostProfitable, "RIGHT", AH_ROW_GAP)
	placeIn(panel.sellRow2, panel.btnPauseBulk, "LEFT", panel.btnPostAll, "RIGHT", AH_ROW_GAP)
	placeIn(panel.sellRow2, panel.btnClearRule, "RIGHT", panel.sellRow2, "RIGHT")
	placeIn(panel.sellRow2, panel.btnReserveItem, "RIGHT", panel.btnClearRule, "LEFT", -AH_ROW_GAP)
	placeIn(panel.sellRow2, panel.btnIgnoreItem, "RIGHT", panel.btnReserveItem, "LEFT", -AH_ROW_GAP)

	-- Sell row 3: search and item filters.
	y = y + AH_ROW + AH_ROW_GAP
	panel.sellRow3 = CreateFrame("Frame", nil, panel)
	anchorRow(panel, panel.sellRow3, y)
	local filters = { panel.subclassDropdown, panel.classDropdown }
	if self.IS_RETAIL then
		table.insert(filters, 1, panel.expansionDropdown)
	else
		panel.expansionDropdown:Hide()
		panel.expansionDropdown.Show = panel.expansionDropdown.Hide
		panel.expansionDropdown.SetShown = function() end
		ui.ahExpansionFilterValues = {}
	end
	placeIn(panel.sellRow3, filters[1], "RIGHT", panel.sellRow3, "RIGHT")
	for index = 2, #filters do
		placeIn(panel.sellRow3, filters[index], "RIGHT", filters[index - 1], "LEFT", -AH_ROW_GAP)
	end
	placeIn(panel.sellRow3, panel.searchBox, "LEFT", panel.sellRow3, "LEFT", 6)
	panel.searchBox:SetPoint("RIGHT", filters[#filters], "LEFT", -14, 0)
	self:AddSearchPlaceholder(panel.searchBox, "Search name or ID")

	-- Sell row 4: two filter checkboxes and Reset filters.
	y = y + AH_ROW + AH_ROW_GAP
	panel.sellRow4 = CreateFrame("Frame", nil, panel)
	anchorRow(panel, panel.sellRow4, y)
	placeIn(panel.sellRow4, panel.craftedOnly, "LEFT", panel.sellRow4, "LEFT", -4)
	self:SkinCheckButton(panel.craftedOnly)
	local craftedLabel = panel.craftedOnly.Text
	placeIn(panel.sellRow4, panel.profitableOnly, "LEFT", panel.craftedOnly, "RIGHT", (craftedLabel and craftedLabel:GetStringWidth() or 60) + 18)
	placeIn(panel.sellRow4, panel.clearBtn, "RIGHT", panel.sellRow4, "RIGHT")
	panel.clearBtn:SetHeight(theme.size.controlSmall)
	self:SetButtonLabel(panel.clearBtn, "Reset filters", true)

	panel.sellRows = { panel.sellRow1, panel.sellRow2, panel.sellRow3, panel.sellRow4 }
	panel.sellTableTop = y + AH_ROW + AH_PAD

	-- Progress row (shown while scanning or posting).
	panel.progressRow = CreateFrame("Frame", nil, panel)
	panel.progressRow:SetPoint("BOTTOMLEFT", panel.footer, "TOPLEFT", AH_PAD - 1, AH_ROW_GAP)
	panel.progressRow:SetPoint("BOTTOMRIGHT", panel.footer, "TOPRIGHT", -(AH_PAD - 1), AH_ROW_GAP)
	panel.progressRow:SetHeight(AH_ROW)
	placeIn(panel.progressRow, panel.btnPauseScan, "RIGHT", panel.progressRow, "RIGHT")
	panel.btnPauseScan:SetHeight(theme.size.controlSmall)
	placeIn(panel.progressRow, panel.progressText, "LEFT", panel.progressRow, "LEFT")
	panel.progressText:SetWidth(170)
	panel.progressText:SetWordWrap(false)
	panel.progressTiming:SetParent(panel.progressRow)
	panel.progressTiming:ClearAllPoints()
	panel.progressTiming:SetPoint("RIGHT", panel.btnPauseScan, "LEFT", -AH_ROW_GAP, 0)
	panel.progressTiming:SetFontObject("GameFontHighlightSmall")
	panel.progressTiming:SetTextColor(theme.textMuted.r, theme.textMuted.g, theme.textMuted.b)
	panel.progressTiming:SetWordWrap(false)
	panel.progressBar:SetParent(panel.progressRow)
	panel.progressBar:ClearAllPoints()
	panel.progressBar:SetPoint("LEFT", panel.progressText, "RIGHT", AH_ROW_GAP, 0)
	panel.progressBar:SetPoint("RIGHT", panel.progressTiming, "LEFT", -AH_ROW_GAP, 0)

	-- Cart: summary, search row, table, action row.
	y = headerHeight + 1 + AH_PAD
	panel.cartSummary:ClearAllPoints()
	panel.cartSummary:SetPoint("TOPLEFT", panel, "TOPLEFT", AH_PAD, -y)
	panel.cartSummary:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -AH_PAD, -y)
	panel.cartSummary:SetTextColor(theme.textMuted.r, theme.textMuted.g, theme.textMuted.b)
	panel.cartRow1 = CreateFrame("Frame", nil, panel)
	anchorRow(panel, panel.cartRow1, y + 32)
	placeIn(panel.cartRow1, panel.btnCartRefresh, "RIGHT", panel.cartRow1, "RIGHT")
	placeIn(panel.cartRow1, panel.btnCartSearch, "RIGHT", panel.btnCartRefresh, "LEFT", -AH_ROW_GAP)
	self:SetButtonPrimary(panel.btnCartSearch, true)
	placeIn(panel.cartRow1, panel.cartSearchBox, "LEFT", panel.cartRow1, "LEFT", 6)
	panel.cartSearchBox:SetPoint("RIGHT", panel.btnCartSearch, "LEFT", -14, 0)
	self:AddSearchPlaceholder(panel.cartSearchBox, "Search item, recipe or character")
	panel.cartRow2 = CreateFrame("Frame", nil, panel)
	panel.cartRow2:SetPoint("BOTTOMLEFT", panel.footer, "TOPLEFT", AH_PAD - 1, AH_ROW_GAP)
	panel.cartRow2:SetPoint("BOTTOMRIGHT", panel.footer, "TOPRIGHT", -(AH_PAD - 1), AH_ROW_GAP)
	panel.cartRow2:SetHeight(AH_ROW)
	placeIn(panel.cartRow2, panel.btnCartClear, "RIGHT", panel.cartRow2, "RIGHT")
	panel.btnCartClear:GetFontString():SetTextColor(theme.danger.r, theme.danger.g, theme.danger.b)
	placeIn(panel.cartRow2, panel.btnCartRemove, "RIGHT", panel.btnCartClear, "LEFT", -AH_ROW_GAP)
	if self.IS_RETAIL then
		placeIn(panel.cartRow2, panel.btnCartBuy, "RIGHT", panel.btnCartRemove, "LEFT", -AH_ROW_GAP)
	else
		panel.btnCartBuy:Hide()
		panel.btnCartBuy.Show = panel.btnCartBuy.Hide
		panel.btnCartBuy.SetShown = function() end
	end
	panel.cartHint = self:CreateText(panel.cartRow2, "GameFontHighlightSmall", "textMuted")
	panel.cartHint:SetPoint("LEFT")
	panel.cartHint:SetPoint("RIGHT", self.IS_RETAIL and panel.btnCartBuy or panel.btnCartRemove, "LEFT", -AH_ROW_GAP, 0)
	panel.cartTableHost:ClearAllPoints()
	panel.cartTableHost:SetPoint("TOPLEFT", panel.cartRow1, "BOTTOMLEFT", 0, -AH_PAD)
	panel.cartTableHost:SetPoint("BOTTOMRIGHT", panel.cartRow2, "TOPRIGHT", 0, AH_PAD)

	-- Auctions: a totals row, a row with the recheck and cancel buttons, then the table down to the footer.
	panel.ownedRow = CreateFrame("Frame", nil, panel)
	anchorRow(panel, panel.ownedRow, headerHeight + 1 + AH_PAD)
	placeIn(panel.ownedRow, panel.ownedSummary, "LEFT", panel.ownedRow, "LEFT")
	panel.ownedSummary:SetPoint("RIGHT", panel.ownedRow, "RIGHT")
	panel.ownedRow2 = CreateFrame("Frame", nil, panel)
	anchorRow(panel, panel.ownedRow2, headerHeight + 1 + AH_PAD + AH_ROW + AH_ROW_GAP)
	placeIn(panel.ownedRow2, panel.btnOwnedCheck, "LEFT", panel.ownedRow2, "LEFT")
	self:SetButtonPrimary(panel.btnOwnedCheck, true)
	placeIn(panel.ownedRow2, panel.btnOwnedCancel, "LEFT", panel.btnOwnedCheck, "RIGHT", AH_ROW_GAP)
	panel.btnOwnedCancel:GetFontString():SetTextColor(theme.danger.r, theme.danger.g, theme.danger.b)
	panel.ownedTableHost:ClearAllPoints()
	panel.ownedTableHost:SetPoint("TOPLEFT", panel.ownedRow2, "BOTTOMLEFT", 0, -AH_PAD)
	panel.ownedTableHost:SetPoint("BOTTOMRIGHT", panel.footer, "TOPRIGHT", -(AH_PAD - 1), AH_PAD)

	for _, button in ipairs({ panel.btnDumpFull, refresh, panel.btnPostProfitable, panel.btnPostAll, panel.btnPauseBulk,
		panel.btnIgnoreItem, panel.btnReserveItem, panel.btnClearRule, panel.btnCartSearch, panel.btnCartRefresh,
		panel.btnCartBuy, panel.btnCartRemove, panel.btnCartClear, panel.btnOwnedCheck, panel.btnOwnedCancel }) do
		self:SkinButton(button)
		self:SetButtonLabel(button, button:GetText())
		button:SetHeight(theme.size.control)
	end
	self:SkinButton(panel.btnPauseScan)
	self:SetButtonLabel(panel.btnPauseScan, "Pause", true)
	self:SkinTree(panel)
end

-- Places the active tab's table between its controls and the progress row or footer.
function ProfessionExporter:LayoutAuctionPanelBody(panel, activeTab, progressShown)
	local sell = activeTab == "sell"
	for _, row in ipairs(panel.sellRows or {}) do
		row:SetShown(sell)
	end
	panel.cartRow1:SetShown(activeTab == "cart")
	panel.cartRow2:SetShown(activeTab == "cart")
	panel.ownedRow:SetShown(activeTab == "auctions")
	panel.ownedRow2:SetShown(activeTab == "auctions")
	panel.ownedTableHost:SetShown(activeTab == "auctions")
	panel.progressRow:SetShown(sell and progressShown)
	panel.tableHost:ClearAllPoints()
	panel.tableHost:SetPoint("TOPLEFT", panel, "TOPLEFT", AH_PAD, -panel.sellTableTop)
	if sell and progressShown then
		panel.tableHost:SetPoint("BOTTOMRIGHT", panel.progressRow, "TOPRIGHT", 0, AH_ROW_GAP)
	else
		panel.tableHost:SetPoint("BOTTOMRIGHT", panel.footer, "TOPRIGHT", -(AH_PAD - 1), AH_PAD)
	end
end

function ProfessionExporter:GetAuctionClassFilterOptions(rows)
	local seen = {}
	local options = {
		{ value = "all", label = "All classes" },
	}
	for _, row in ipairs(rows or {}) do
		local label = tostring(row and row.itemClassLabel or "")
		if label ~= "" and not seen[label] then
			seen[label] = true
			options[#options + 1] = {
				value = label,
				label = label,
			}
		end
	end
	table.sort(options, function(left, right)
		if left.value == "all" then
			return true
		end
		if right.value == "all" then
			return false
		end
		return tostring(left.label) < tostring(right.label)
	end)
	return options
end

function ProfessionExporter:GetAuctionSubclassFilterOptions(rows, classSelection)
	local seen = {}
	local options = {
		{ value = "all", label = "All subclasses" },
	}
	for _, row in ipairs(rows or {}) do
		local classLabel = tostring(row and row.itemClassLabel or "")
		local subclassLabel = tostring(row and row.itemSubclassLabel or "")
		local classMatches = self:IsFilterSelectionEmpty(classSelection) or classSelection[classLabel] == true
		if classMatches and subclassLabel ~= "" and not seen[subclassLabel] then
			seen[subclassLabel] = true
			options[#options + 1] = {
				value = subclassLabel,
				label = subclassLabel,
			}
		end
	end
	table.sort(options, function(left, right)
		if left.value == "all" then
			return true
		end
		if right.value == "all" then
			return false
		end
		return tostring(left.label) < tostring(right.label)
	end)
	return options
end

local function rankMarkup(rankIndex)
	return ProfessionExporter:GetRankMarkup(rankIndex)
end

-- A badge-like word in its own colour, for the Flag column.
local function flagText(pe, text, colorKey)
	local color = pe:GetTheme()[colorKey]
	return string.format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, string.upper(text))
end

function ProfessionExporter:BuildAuctionPanelColumns()
	local pe = self
	return {
		self:CreateItemColumn({
			id = "itemRecipe",
			label = "Item",
			defaultSort = "asc",
			minWidth = 120,
			getItemID = function(row) return row and row.itemID end,
			getIcon = function(row) return row and row.itemIcon end,
			getName = function(row)
				local marker = (row and row._isScanning) and "› " or ""
				return marker .. tostring(row and row.itemName or "-") .. rankMarkup(row and row.qualityIndex)
			end,
			sortValue = function(row) return row and row.itemName end,
		}),
		{
			id = "quantityOwned", label = "Qty", justifyH = "RIGHT", width = 58, sortable = true, defaultSort = "desc",
			tooltipTitle = "Quantity", tooltipText = "Sellable / owned when a keep rule holds some back.",
			sortValue = function(row) return tonumber(row and row.quantityOwned) or 0 end,
			getText = function(row)
				local owned = pe:FormatNumberGrouped(row and row.quantityOwned or 0)
				if row and row.isIgnoredByRule then
					return "0/" .. owned
				end
				if (tonumber(row and row.reserveQty) or 0) > 0 then
					return pe:FormatNumberGrouped(tonumber(row.quantitySellable) or 0) .. "/" .. owned
				end
				return owned
			end,
		},
		{
			id = "currentPrice", label = "Price", justifyH = "RIGHT", width = 84, sortable = true, defaultSort = "desc",
			tooltipTitle = "Price", tooltipText = "Live lowest buyout. Grey when it comes from an older scan or another addon.",
			sortValue = function(row) return tonumber(row and row.currentPrice) or -1 end,
			getText = function(row)
				if not row or not row.currentPrice then
					return "-"
				end
				local text = pe:FormatCopperShort(row.currentPrice)
				if row.currentPriceIsNative ~= true then
					local muted = pe:GetTheme().textMuted
					return string.format("|cff%02x%02x%02x%s|r", muted.r * 255, muted.g * 255, muted.b * 255, text)
				end
				return text
			end,
		},
		{
			id = "lastAuctionScan", label = "Scan", justifyH = "RIGHT", width = 60, sortable = true, defaultSort = "desc", optional = true,
			tooltipTitle = "Last scanned",
			sortValue = function(row) return tonumber(row and row.lastAuctionScanAtTs) or 0 end,
			getText = function(row) return row and row.auctionScanAgeDisplay or "never" end,
		},
		{
			id = "potentialROI", label = "ROI", justifyH = "RIGHT", width = 46, sortable = true, defaultSort = "desc",
			tooltipTitle = "Return", tooltipText = "Profit over material cost for crafted items.",
			sortValue = function(row) return tonumber(row and row.potentialROI) or -9999 end,
			getText = function(row) return formatPercent(row and row.potentialROI) end,
		},
		{
			id = "personalSaleRate", label = "Sold", justifyH = "RIGHT", width = 44, sortable = true, defaultSort = "desc", optional = true,
			tooltipTitle = "Your sale rate", tooltipText = "Share of your own past listings of this item that sold.",
			sortValue = function(row) return tonumber(row and row.personalSaleRateValue) or -1 end,
			getText = function(row) return row and row.personalSaleRateDisplay or "-" end,
		},
		{
			id = "dumpAlert", label = "Flag", width = 64, sortable = true, defaultSort = "desc",
			tooltipTitle = "Flag", tooltipText = "Keep and Ignore rules, and prices that look dumped.",
			sortValue = function(row)
				return (row and row.isDumpedLow and 4 or 0) + (row and row.isIgnoredByRule and 2 or 0) + ((tonumber(row and row.reserveQty) or 0) > 0 and 1 or 0)
			end,
			getText = function(row)
				if not row then
					return ""
				end
				if row.isDumpedLow then
					return flagText(pe, "Low", "warning")
				end
				if row.isIgnoredByRule then
					return flagText(pe, "Ignored", "textMuted")
				end
				if (tonumber(row.reserveQty) or 0) > 0 then
					return flagText(pe, "Keep " .. tostring(row.reserveQty), "gold")
				end
				return ""
			end,
		},
	}
end

function ProfessionExporter:BuildOwnedAuctionColumns()
	local pe = self
	return {
		self:CreateItemColumn({
			id = "item",
			label = "Item",
			defaultSort = "asc",
			minWidth = 110,
			getItemID = function(row) return row and row.itemID end,
			getIcon = function(row) return row and row.itemIcon end,
			getName = function(row)
				return tostring(row and row.itemName or "-") .. (row and row.quantity > 1 and (" x" .. row.quantity) or "")
			end,
			sortValue = function(row) return row and row.itemName end,
		}),
		moneyColumn(pe, "unitPrice", "Each", "unitPrice", true),
		moneyColumn(pe, "value", "Total", "value"),
		{
			id = "status", label = "Status", width = 104, sortable = true, defaultSort = "desc",
			tooltipTitle = "Status", tooltipText = "Sold, or how your price compares with the lowest one scanned this visit.",
			-- Descending: most undercut first, then lowest, unchecked, sold.
			sortValue = function(row)
				return row.sold and -1 or (row.undercut and 1 + row.undercutPct) or (row.undercut == false and 0.5) or 0
			end,
			getText = function(row)
				if row.sold then
					return flagText(pe, "Sold", "success")
				elseif row.canceling then
					return flagText(pe, "Cancelling", "textMuted")
				elseif row.undercut then
					return flagText(pe, string.format("Undercut %d%%", math.max(1, math.floor(row.undercutPct + 0.5))), "danger")
				elseif row.undercut == false then
					return flagText(pe, "Lowest", "textMuted")
				end
				return "-"
			end,
		},
	}
end

--- The player's own auctions with totals; undercut compares against prices scanned this visit.
function ProfessionExporter:BuildOwnedAuctionRows()
	local owned, lowest = {}, {}
	local soldStatus = Enum and Enum.AuctionStatus and Enum.AuctionStatus.Sold
	for _, info in ipairs(C_AuctionHouse and C_AuctionHouse.GetOwnedAuctions and C_AuctionHouse.GetOwnedAuctions() or {}) do
		local itemID = normalizeItemID(info.itemKey and info.itemKey.itemID)
		if itemID then
			owned[#owned + 1] = {
				auctionID = info.auctionID,
				itemID = itemID,
				quantity = info.quantity,
				sold = soldStatus ~= nil and info.status == soldStatus,
				buyout = info.buyoutAmount,
				bid = info.bidAmount,
				deposit = soldStatus ~= info.status and self:GetOwnedAuctionDeposit(info, itemID) or nil,
			}
			lowest[itemID] = lowest[itemID] or self:GetNativeAhPrice(itemID)
		end
	end
	local cut = self.GetCraftsAhCutFraction and self:GetCraftsAhCutFraction() or 0.05
	local rows, totals = self.ForeverLogic.SummarizeOwnedAuctions(owned, lowest, cut)
	local cancelRequestedAt = self:GetState().auctionCancelRequestedAt or {}
	for _, row in ipairs(rows) do
		local desc = self:ResolveItemDescriptor(row.itemID)
		row.itemName = self:GetItemDisplayName(row.itemID)
		row.itemIcon = desc and desc.icon or 134400
		-- A cancel shows as pending until the client drops the auction (or 10s pass without that).
		row.canceling = GetTime() - (cancelRequestedAt[row.auctionID] or -100) < 10
	end
	return rows, totals, cut
end

--- Undercut auctions a bulk cancel may take, most undercut first. Left alone: auctions with a
--- cancel fee (someone has bid), and ones where a repost at the lowest price would pay nothing
--- after the cut and the forfeited deposit.
function ProfessionExporter:GetCancelableUndercutAuctions(rows)
	local out = {}
	for _, row in ipairs(rows) do
		if row.undercut and not row.canceling and row.repostNet > 0 and C_AuctionHouse.CanCancelAuction(row.auctionID)
			and (tonumber(C_AuctionHouse.GetCancelCost(row.auctionID)) or 0) == 0 then
			out[#out + 1] = row
		end
	end
	table.sort(out, function(a, b) return a.undercutPct > b.undercutPct end)
	return out
end

--- Cancels the most undercut auction. Must run from a real click: like posting, the client
--- rejects cancels that don't come from a hardware event, so it is one click per auction.
function ProfessionExporter:CancelNextUndercutAuction()
	local state = self:GetState()
	local nowSec = GetTime()
	if nowSec < (state.auctionNextCancelAt or 0) or not C_AuctionHouse.IsThrottledMessageSystemReady() then
		return
	end
	local target = self:GetCancelableUndercutAuctions((self:BuildOwnedAuctionRows()))[1]
	if not target then
		return
	end
	C_AuctionHouse.CancelAuction(target.auctionID)
	state.auctionCancelRequestedAt = state.auctionCancelRequestedAt or {}
	state.auctionCancelRequestedAt[target.auctionID] = nowSec
	state.auctionNextCancelAt = nowSec + AUCTION_BULK_MIN_INTERVAL
	self:RefreshAuctionHousePanel()
	C_Timer.After(AUCTION_BULK_MIN_INTERVAL, function()
		ProfessionExporter:RefreshAuctionHousePanel()
	end)
end

function ProfessionExporter:FilterAuctionPanelRows(rows)
	self.ui = self.ui or {}
	local ui = self.ui
	local text = string.lower(tostring(ui.ahFilterText or ""))
	local craftedOnly = ui.ahCraftedOnly == true
	local profitableOnly = ui.ahProfitableOnly == true
	local classSelection = ui.ahClassFilterValues or {}
	local subclassSelection = ui.ahSubclassFilterValues or {}
	local expSel = ui.ahExpansionFilterValues or {}
	local showAllExpansions = self:IsFilterSelectionEmpty(expSel)
	local out = {}
	for _, row in ipairs(rows or {}) do
		local keep = true
		if text ~= "" then
			keep = containsText(row.itemName, text) or containsText(row.itemID, text)
		end
		if keep and craftedOnly then
			keep = row.potentialROI ~= nil
		end
		if keep and profitableOnly then
			keep = tonumber(row.potentialROI) and tonumber(row.potentialROI) > 0
		end
		if keep and not self:IsFilterSelectionEmpty(classSelection) then
			keep = classSelection[tostring(row.itemClassLabel or "")] == true
		end
		if keep and not self:IsFilterSelectionEmpty(subclassSelection) then
			keep = subclassSelection[tostring(row.itemSubclassLabel or "")] == true
		end
		if keep and not showAllExpansions then
			local desc = row.itemID and self:ResolveItemDescriptor(row.itemID) or nil
			local expTag = self:ExpansionLeToFilterTag(desc and desc.expansionID) or "legacy"
			keep = expSel[expTag] == true
		end
		if keep then
			out[#out + 1] = row
		end
	end
	return out
end

function ProfessionExporter:TrySendItemToAuctionSellFrame(itemID, bag, slot)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return false
	end
	if not bag or not slot then
		bag, slot = self:GetAuctionRepresentativeBagSlot(itemID)
	end
	bag = tonumber(bag)
	slot = tonumber(slot)
	if bag == nil or slot == nil then
		return false
	end
	if C_Container and C_Container.GetContainerItemID then
		local bagItemID = normalizeItemID(C_Container.GetContainerItemID(bag, slot))
		if bagItemID ~= itemID then
			bag, slot = self:GetAuctionRepresentativeBagSlot(itemID, self.GetAuctionOwnedBagState and self:GetAuctionOwnedBagState(true) or nil)
			bag = tonumber(bag)
			slot = tonumber(slot)
			if bag == nil or slot == nil then
				return false
			end
			bagItemID = normalizeItemID(C_Container.GetContainerItemID(bag, slot))
			if bagItemID ~= itemID then
				return false
			end
		end
	end

	local ah = _G.AuctionHouseFrame
	local hasSetPostItem = ah and type(ah.SetPostItem) == "function" and true or false

	-- Modern sell frame (retail and Forever): SetPostItem is what a bag right-click calls. It opens
	-- the Sell tab on the item or commodity pane, and returns silently when the item can't be sold
	-- or its data isn't loaded, so success is read back from the sell frames.
	if hasSetPostItem and ItemLocation and ItemLocation.CreateFromBagAndSlot then
		local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
		if pcall(ah.SetPostItem, ah, loc) then
			for _, sellFrame in ipairs({ ah.ItemSellFrame, ah.CommoditiesSellFrame }) do
				if sellFrame.GetItem and sellFrame:GetItem() == loc then
					return true
				end
			end
		end
	end

	-- Classic cursor inject. Do not use on true retail when the modern sell frame exists
	-- (Blizzard sell frame can hard-error on stale cursor placements during auto-refresh).
	local shouldClassic = self.ForeverLogic
		and self.ForeverLogic.ShouldUseClassicSellInject
		and self.ForeverLogic.ShouldUseClassicSellInject(self.IS_FOREVER == true, hasSetPostItem)
	if not shouldClassic then
		ClearCursor()
		return false
	end

	local ahOpen = self.IsAuctionHouseFrameOpen and self:IsAuctionHouseFrameOpen()
	if not ahOpen then
		ClearCursor()
		return false
	end
	if type(ClickAuctionSellItemButton) ~= "function" then
		ClearCursor()
		return false
	end
	local pickup = (C_Container and C_Container.PickupContainerItem) or _G.PickupContainerItem
	if type(pickup) ~= "function" then
		ClearCursor()
		return false
	end

	-- Ensure classic Auctions tab is active when present.
	local auctionsTab = _G.AuctionFrameTab3
	if auctionsTab and type(AuctionFrameTab_OnClick) == "function" then
		pcall(AuctionFrameTab_OnClick, auctionsTab, 3)
	elseif auctionsTab and auctionsTab.Click then
		pcall(auctionsTab.Click, auctionsTab)
	end

	ClearCursor()
	local picked = pcall(pickup, bag, slot)
	if not picked then
		ClearCursor()
		return false
	end
	local clicked = pcall(ClickAuctionSellItemButton)
	ClearCursor()
	return clicked == true
end

function ProfessionExporter:GetAuctionPostButton()
	local ah = _G.AuctionHouseFrame
	if not ah then
		return nil
	end
	local candidates = {
		ah.CommoditiesSellFrame and ah.CommoditiesSellFrame.PostButton,
		ah.CommoditiesSellFrame and ah.CommoditiesSellFrame.CreateAuctionButton,
		ah.ItemSellFrame and ah.ItemSellFrame.PostButton,
		ah.ItemSellFrame and ah.ItemSellFrame.CreateAuctionButton,
		ah.CommoditiesSellFrame and ah.CommoditiesSellFrame.SaleFrame and ah.CommoditiesSellFrame.SaleFrame.PostButton,
		ah.CommoditiesSellFrame and ah.CommoditiesSellFrame.SaleFrame and ah.CommoditiesSellFrame.SaleFrame.CreateAuctionButton,
		ah.ItemSellFrame and ah.ItemSellFrame.SaleFrame and ah.ItemSellFrame.SaleFrame.PostButton,
		ah.ItemSellFrame and ah.ItemSellFrame.SaleFrame and ah.ItemSellFrame.SaleFrame.CreateAuctionButton,
	}
	for _, button in ipairs(candidates) do
		-- IsVisible, not IsShown: the hidden pane's button still reports itself as shown.
		if button and button.IsVisible and button:IsVisible() and button.Click then
			return button
		end
	end
	return nil
end

function ProfessionExporter:GetAuctionSellFrameUnitPriceCopper()
	local ah = _G.AuctionHouseFrame
	if not ah then
		return nil
	end
	local function readMoney(frame)
		if not frame then
			return nil
		end
		if MoneyInputFrame_GetCopper then
			local ok, copper = pcall(MoneyInputFrame_GetCopper, frame)
			if ok and tonumber(copper) and tonumber(copper) > 0 then
				return tonumber(copper)
			end
		end
		if frame.GetAmount then
			local ok, amount = pcall(frame.GetAmount, frame)
			if ok and tonumber(amount) and tonumber(amount) > 0 then
				return tonumber(amount)
			end
		end
		return nil
	end
	local candidates = {
		ah.CommoditiesSellFrame and ah.CommoditiesSellFrame.UnitPriceInput and ah.CommoditiesSellFrame.UnitPriceInput.MoneyInputFrame,
		ah.CommoditiesSellFrame and ah.CommoditiesSellFrame.PriceInput and ah.CommoditiesSellFrame.PriceInput.MoneyInputFrame,
		ah.ItemSellFrame and ah.ItemSellFrame.UnitPriceInput and ah.ItemSellFrame.UnitPriceInput.MoneyInputFrame,
		ah.ItemSellFrame and ah.ItemSellFrame.PriceInput and ah.ItemSellFrame.PriceInput.MoneyInputFrame,
		ah.CommoditiesSellFrame and ah.CommoditiesSellFrame.SaleFrame and ah.CommoditiesSellFrame.SaleFrame.UnitPriceInput and ah.CommoditiesSellFrame.SaleFrame.UnitPriceInput.MoneyInputFrame,
		ah.CommoditiesSellFrame and ah.CommoditiesSellFrame.SaleFrame and ah.CommoditiesSellFrame.SaleFrame.PriceInput and ah.CommoditiesSellFrame.SaleFrame.PriceInput.MoneyInputFrame,
		ah.ItemSellFrame and ah.ItemSellFrame.SaleFrame and ah.ItemSellFrame.SaleFrame.UnitPriceInput and ah.ItemSellFrame.SaleFrame.UnitPriceInput.MoneyInputFrame,
		ah.ItemSellFrame and ah.ItemSellFrame.SaleFrame and ah.ItemSellFrame.SaleFrame.PriceInput and ah.ItemSellFrame.SaleFrame.PriceInput.MoneyInputFrame,
	}
	for _, frame in ipairs(candidates) do
		local value = readMoney(frame)
		if value and value > 0 then
			return value
		end
	end
	return nil
end

function ProfessionExporter:GetLiveAuctionResultUnitPrice(itemID)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return nil, nil, nil
	end
	local agg = self:GetLiveAuctionSearchAggregate(itemID, nil)
	if not agg then
		return nil, nil, nil
	end
	if agg.kind == "commodity" then
		return agg.minUnitPrice, "commodity_results_live", agg.totalQuantity
	end
	if agg.kind == "item" then
		return agg.cheapestUnitPrice, "item_results_live", agg.totalQuantityAll
	end
	return nil, nil, nil
end

function ProfessionExporter:TryClickAuctionPostButton()
	local button = self:GetAuctionPostButton()
	if button and button.IsEnabled and button:IsEnabled() and button.Click then
		button:Click()
		return true
	end
	return false
end

function ProfessionExporter:GetAuctionPanelPersonalSaleRate(itemID, characterKey)
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

function ProfessionExporter:RunAuctionPanelBulkAction(mode)
	mode = tostring(mode or "post_all")
	local state = self:GetState()
	if state.auctionBulk and state.auctionBulk.running == true then
		-- The button that started the job is its "Post next" button while it runs.
		if state.auctionBulk.mode == mode then
			self:PostAuctionBulkCurrent()
		end
		return
	end
	if not self:CanStartFullAuctionSideActions(true) then
		return
	end
	if state.auctionRefreshRunning == true then
		if self:PauseAuctionScanForBulkPost() then
			self:PrintMessage("Paused auction scan to start bulk posting.")
		end
	end
	local rows = self:BuildAuctionBulkRows(mode)
	if #rows == 0 then
		self:PrintMessage(mode == "post_profitable" and "No profitable visible rows to post." or "No visible auction rows to post.")
		self:ResumeAuctionScanAfterBulkPost()
		return
	end
	state.auctionBulk = {
		running = true,
		mode = mode,
		awaitingScan = false,
		rows = rows,
		index = 1,
		total = #rows,
		done = 0,
		selected = 0,
		posted = 0,
		skippedDumped = 0,
		failed = 0,
		maxRetries = 8,
		retryCount = 0,
		currentSelectionCounted = false,
		phase = "selecting",
		status = "Starting...",
		currentItemID = nil,
	}
	self:RefreshAuctionHousePanel()
	-- If a queued scan has an in-flight search, wait for it to complete once.
	-- Pausing prevents the scan from scheduling the next search query, but we still need
	-- the sell UI to catch up (post button enabling depends on it).
	local function waitAndStart()
		local s = self:GetState()
		local b = s and s.auctionBulk or nil
		if not b or b.running ~= true then
			return
		end
		if s.auctionSearchContext then
			C_Timer.After(0.10, waitAndStart)
			return
		end
		b.awaitingScan = false
		b.status = "Starting..."
		self:RefreshAuctionHousePanel()
		ProfessionExporter:ContinueAuctionBulkPost()
	end
	if state.auctionSearchContext then
		state.auctionBulk.awaitingScan = true
		state.auctionBulk.status = "Waiting for scan step to finish..."
		self:RefreshAuctionHousePanel()
		C_Timer.After(0.10, waitAndStart)
		return
	end
	C_Timer.After(0.05, function()
		ProfessionExporter:ContinueAuctionBulkPost()
	end)
end

function ProfessionExporter:PrimeAuctionPanelRows()
	local state = self:GetState()
	local bagState = self:GetAuctionOwnedBagState(true)
	if type(state.auctionPanelRows) == "table"
		and state.auctionPanelRowsViewRevision == state.auctionViewRevision
		and state.auctionPanelRowsBagSignature == bagState.signature then
		return state.auctionPanelRows
	end
	state.auctionPanelRows = self:BuildAuctionInventoryRows({
		includeCraftEstimates = false,
		bagState = bagState,
	})
	state.auctionPanelRowsViewRevision = state.auctionViewRevision
	state.auctionPanelRowsBagSignature = bagState.signature
	return state.auctionPanelRows
end

function ProfessionExporter:RetryPrimeAuctionPanelRows(attempt)
	attempt = tonumber(attempt) or 1
	local state = self:GetState()
	local rows = (state and state.auctionPanelRows) or {}
	if type(rows) == "table" and #rows > 0 then
		return
	end
	if attempt > 6 then
		return
	end
	C_Timer.After(0.2, function()
		ProfessionExporter:PrimeAuctionPanelRows()
		ProfessionExporter:RefreshAuctionHousePanel()
		ProfessionExporter:RetryPrimeAuctionPanelRows(attempt + 1)
	end)
end

function ProfessionExporter:GetAuctionRegionKey()
	return tostring(GetCurrentRegion and GetCurrentRegion() or "unknown")
end

function ProfessionExporter:GetAuctionConnectedRealmID()
	local id = tonumber(GetNormalizedRealmID and GetNormalizedRealmID() or nil)
	if id and id > 0 then
		return id
	end
	return tonumber(GetRealmID and GetRealmID() or 0) or 0
end

function ProfessionExporter:BuildAuctionStorageKey(itemID, marketScope, itemKey)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return nil
	end
	local region = self:GetAuctionRegionKey()
	if marketScope == "commodity" then
		return string.format("%s:%d", region, itemID)
	end
	local connectedRealmID = self:GetAuctionConnectedRealmID()
	local keyPart = self.ForeverLogic.SerializeItemKey(itemKey, itemID)
	return string.format("%s:%d:%s", region, connectedRealmID, keyPart)
end

local function getBucketTable(root, storageKey)
	if type(root) ~= "table" or not storageKey then
		return nil
	end
	root[storageKey] = root[storageKey] or {}
	return root[storageKey]
end

function ProfessionExporter:RecordAuctionObservation(observation)
	if type(observation) ~= "table" then
		return false
	end
	local auction = self:InitAuctionDB()
	local state = self:GetState()
	state.auctionDataRevision = (state.auctionDataRevision or 0) + 1
	local itemID = normalizeItemID(observation.itemID)
	if not itemID then
		return false
	end
	local marketScope = observation.isCommodity and "commodity" or "item"
	local storageKey = self:BuildAuctionStorageKey(itemID, marketScope, observation.itemKey)
	if not storageKey then
		return false
	end

	local seenAt = tonumber(observation.seenAt) or now()
	local entry = self:BuildCompactAuctionSnapshotEntry(observation)
	if not entry then
		return false
	end

	local snapRoot = marketScope == "commodity" and auction.snapshot.commodities or auction.snapshot.items
	snapRoot[storageKey] = entry

	auction.indexes.byItemID[tostring(itemID)] = auction.indexes.byItemID[tostring(itemID)] or {}
	auction.indexes.byItemID[tostring(itemID)][storageKey] = true

	self:UpdateAuctionHistoryFromObservation(storageKey, entry)
	self:TouchItemAuctionScanTimestamp(itemID, seenAt)
	return true
end

function ProfessionExporter:IsAuctionDumpAhOriginPrice(row)
	if type(row) ~= "table" then
		return false
	end
	local price = tonumber(row.currentPrice or row.marketLow or row.minBuyout or row.price)
	if not price or price <= 0 then
		return false
	end
	if row.currentPriceIsNative == true then
		return true
	end
	local src = tostring(row.currentPriceSource or row.source or "")
	if src == "snapshot" or src == "native" then
		return true
	end
	if src:find("results_live", 1, true) or src:find("replicate", 1, true) or src:find("dump_", 1, true) or src:find("browse", 1, true) then
		return true
	end
	if src:find("fallback:", 1, true) or src:find("fallback", 1, true) then
		return false
	end
	return false
end

function ProfessionExporter:ResolveDumpItemCommodity(itemKey, fallback)
	if C_AuctionHouse and C_AuctionHouse.GetItemCommodityStatus and Enum and Enum.ItemCommodityStatus then
		local ok, status = pcall(C_AuctionHouse.GetItemCommodityStatus, itemKey)
		if ok and status == Enum.ItemCommodityStatus.Commodity then
			return true
		end
		if ok and status == Enum.ItemCommodityStatus.Item then
			return false
		end
	end
	if fallback == true or fallback == false then
		return fallback
	end
	return false
end

--- Persist a dump/replicate observation: always stamp last-updated and session-searched;
--- write snapshot/native price when a usable unit price is present.
--- Ignores the 1-hour auto-scan gate. Timestamps use now() unless the caller passes a newer value.
function ProfessionExporter:PersistAuctionDumpObservation(observation)
	if type(observation) ~= "table" then
		return false
	end
	local itemID = normalizeItemID(observation.itemID)
	if not itemID then
		return false
	end
	local nowTs = now()
	local requested = tonumber(observation.seenAt)
	local seenAt = nowTs
	if requested and requested > nowTs then
		seenAt = requested
	end
	local price = tonumber(observation.marketLow or observation.minBuyout or observation.price or observation.currentPrice)
	local sampleSize = math.max(1, tonumber(observation.sampleSize) or 1)
	local source = tostring(observation.source or "dump")
	local keyFields = observation.itemKeyFields
	self:TouchItemAuctionScanTimestamp(itemID, seenAt)
	self:MarkAuctionTargetSearched(itemID, keyFields, source, seenAt)
	if price and price > 0 then
		self:RecordAuctionObservation({
			itemID = itemID,
			isCommodity = observation.isCommodity == true,
			itemKey = observation.itemKey,
			marketLow = price,
			minBuyout = tonumber(observation.minBuyout) or price,
			marketHigh = tonumber(observation.marketHigh),
			sampleSize = sampleSize,
			listingCount = tonumber(observation.listingCount),
			source = source,
			seenAt = seenAt,
		})
		self:UpsertNativeAuctionPrice(itemID, price, source, sampleSize, seenAt)
	end
	return true
end

function ProfessionExporter:UpdateAuctionHistoryFromObservation(storageKey, entry)
	local auction = self:InitAuctionDB()
	if not storageKey or type(entry) ~= "table" then
		return
	end
	local hourBucketTs = math.floor((tonumber(auctionSnapshotSeenAt(entry) or entry.seenAt) or now()) / 3600) * 3600
	local itemHistory = getBucketTable(auction.history.hourly, storageKey)
	if not itemHistory then
		return
	end
	local bucketKey = tostring(hourBucketTs)
	local bucket = itemHistory[bucketKey] or {}
	local price = auctionSnapshotPrice(entry)
	local qty = math.max(1, tonumber(entry.sampleSize) or 1)
	if type(entry) == "table" then
		qty = math.max(1, auctionSnapshotSampleSize(entry) or 1)
	end
	if price and price > 0 then
		bucket.m = bucket.m and math.min(bucket.m, price) or bucket.min and math.min(bucket.min, price) or price
		bucket.x = bucket.x and math.max(bucket.x, price) or bucket.max and math.max(bucket.max, price) or price
		bucket.l = price
		bucket.n = auctionHistoryBucketCount(bucket) + 1
		bucket.q = auctionHistoryBucketWeightedQty(bucket) + qty
		bucket.w = auctionHistoryBucketWeightedSum(bucket) + (price * qty)
		bucket.t = auctionSnapshotSeenAt(entry) or now()
		bucket.min = nil
		bucket.max = nil
		bucket.last = nil
		bucket.count = nil
		bucket.weightedQty = nil
		bucket.weightedSum = nil
		bucket.avg = nil
		bucket.lastSeenAt = nil
		itemHistory[bucketKey] = bucket
	end
	self:TrimAuctionHistory()
end

function ProfessionExporter:TrimAuctionHistory()
	-- Called per observation; walking all history each time made full dumps quadratic.
	local state = self:GetState()
	if state.auctionHistoryTrimmedAt and now() - state.auctionHistoryTrimmedAt < 600 then
		return
	end
	state.auctionHistoryTrimmedAt = now()
	local auction = self:InitAuctionDB()
	local settings = self.db and self.db.settings and self.db.settings.auction or nil
	local retentionDays = tonumber(settings and settings.historyRetentionDays) or 30
	retentionDays = math.max(1, retentionDays)
	local cutoffTs = now() - retentionDays * 24 * 3600
	for storageKey, historyByHour in pairs(auction.history.hourly or {}) do
		for hourTs in pairs(historyByHour) do
			if tonumber(hourTs) and tonumber(hourTs) < cutoffTs then
				historyByHour[hourTs] = nil
			else
				local bucket = historyByHour[hourTs]
				if type(bucket) == "table" then
					local compact = {
						n = auctionHistoryBucketCount(bucket),
						q = auctionHistoryBucketWeightedQty(bucket),
						w = auctionHistoryBucketWeightedSum(bucket),
						l = tonumber(bucket.l or bucket.last),
						m = tonumber(bucket.m or bucket.min),
						x = tonumber(bucket.x or bucket.max),
						t = tonumber(bucket.t or bucket.lastSeenAt),
					}
					if compact.n <= 0 and compact.q <= 0 and not compact.l then
						historyByHour[hourTs] = nil
					else
						historyByHour[hourTs] = compact
					end
				end
			end
		end
		if next(historyByHour) == nil then
			auction.history.hourly[storageKey] = nil
		end
	end
	local function pruneSnapshotRoot(root)
		for storageKey, entry in pairs(root or {}) do
			local seenAt = auctionSnapshotSeenAt(entry)
			if not seenAt or seenAt < cutoffTs or not auctionSnapshotPrice(entry) then
				root[storageKey] = nil
			else
				root[storageKey] = self:BuildCompactAuctionSnapshotEntry(entry)
			end
		end
	end
	pruneSnapshotRoot(auction.snapshot and auction.snapshot.commodities or nil)
	pruneSnapshotRoot(auction.snapshot and auction.snapshot.items or nil)
	for itemKey, storageKeys in pairs(auction.indexes.byItemID or {}) do
		for storageKey in pairs(storageKeys or {}) do
			if not (auction.snapshot.commodities[storageKey] or auction.snapshot.items[storageKey] or auction.history.hourly[storageKey]) then
				storageKeys[storageKey] = nil
			end
		end
		if next(storageKeys) == nil then
			auction.indexes.byItemID[itemKey] = nil
		end
	end
end

--- Per-hour aggregated AH sample quantity (`weightedQty` in history buckets) for graph overlays.
--- Uses the same time range cutoff as item detail graphs (`GetHistoryRangeCutoff` from ItemAnalytics).
function ProfessionExporter:GetAuctionHistoryQuantitySeriesForItem(itemID, rangeKey)
	itemID = tonumber(itemID)
	if not itemID then
		return {}
	end
	local auction = self:InitAuctionDB()
	local byItem = auction.indexes and auction.indexes.byItemID and auction.indexes.byItemID[tostring(itemID)]
	if not byItem or type(byItem) ~= "table" then
		return {}
	end
	local cutoff = type(self.GetHistoryRangeCutoff) == "function" and self:GetHistoryRangeCutoff(rangeKey) or nil
	local merge = {}
	for storageKey in pairs(byItem) do
		local hist = auction.history and auction.history.hourly and auction.history.hourly[storageKey]
		if type(hist) == "table" then
			for hourKey, bucket in pairs(hist) do
				local at = tonumber(hourKey)
				if at and at > 0 and (not cutoff or at >= cutoff) and type(bucket) == "table" then
					local wq = auctionHistoryBucketWeightedQty(bucket)
					local ct = auctionHistoryBucketCount(bucket)
					if wq > 0 or ct > 0 then
						local agg = merge[at] or { weightedQty = 0, obsCount = 0 }
						agg.weightedQty = agg.weightedQty + wq
						agg.obsCount = agg.obsCount + ct
						merge[at] = agg
					end
				end
			end
		end
	end
	local list = {}
	for at, agg in pairs(merge) do
		list[#list + 1] = {
			at = at,
			value = agg.weightedQty,
			meta = {
				ahHistory = true,
				sampleCount = agg.obsCount,
			},
		}
	end
	table.sort(list, function(a, b)
		return a.at < b.at
	end)
	return list
end

function ProfessionExporter:RecordAuctionTransaction(event)
	if type(event) ~= "table" then
		return false
	end
	local auction = self:InitAuctionDB()
	local kind = tostring(event.kind or "unknown")
	local entry = shallowCopy(event)
	entry.kind = kind
	entry.ts = tonumber(event.ts) or now()
	entry.itemID = normalizeItemID(event.itemID)
	entry.characterKey = event.characterKey and tostring(event.characterKey) or self:GetCharacterKey()
	entry.quantity = math.max(0, tonumber(event.quantity) or 0)
	entry.unitCopper = tonumber(event.unitCopper)
	entry.totalCopper = tonumber(event.totalCopper)
	entry.source = tostring(event.source or "auction")
	table.insert(auction.transactions.events, entry)
	while #auction.transactions.events > AUCTION_TX_MAX_EVENTS do
		table.remove(auction.transactions.events, 1)
	end
	local charIdx = auction.indexes.byCharacterAuction
	charIdx[entry.characterKey] = charIdx[entry.characterKey] or {}
	table.insert(charIdx[entry.characterKey], {
		ts = entry.ts,
		itemID = entry.itemID,
		kind = entry.kind,
		quantity = entry.quantity,
		unitCopper = entry.unitCopper,
	})
	return true
end

function ProfessionExporter:GetAuctionSnapshot(itemKey, marketScope)
	local auction = self:InitAuctionDB()
	if not itemKey then
		return nil
	end
	local id = normalizeItemID(itemKey)
	local storageKey
	if type(itemKey) == "string" and string.find(itemKey, ":", 1, true) then
		storageKey = itemKey
	else
		storageKey = self:BuildAuctionStorageKey(id, marketScope == "commodity" and "commodity" or "item")
	end
	if not storageKey then
		return nil
	end
	local snap = auction.snapshot.commodities[storageKey] or auction.snapshot.items[storageKey]
	return snap and self:NormalizeAuctionSnapshotEntry(snap) or nil
end

function ProfessionExporter:GetItemEconomySummary(itemID, opts)
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
	local freshnessMinutes = tonumber(self:GetSetting("auction.priceFreshnessMinutes", 15)) or 15
	local freshWindowSec = math.max(60, freshnessMinutes * 60)
	local nowTs = now()
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

function ProfessionExporter:UpsertNativeAuctionPrice(itemID, price, source, sampleSize, seenAt)
	itemID = normalizeItemID(itemID)
	price = tonumber(price)
	if not itemID or not price or price <= 0 then
		return false
	end
	local state = self:GetState()
	state.auctionNativePriceByItem = state.auctionNativePriceByItem or {}
	local ts = tonumber(seenAt) or now()
	state.auctionNativePriceByItem[itemID] = {
		price = price,
		seenAt = ts,
		source = tostring(source or "native"),
		sampleSize = math.max(1, tonumber(sampleSize) or 1),
	}
	self:TouchItemAuctionScanTimestamp(itemID, ts)
	return true
end

function ProfessionExporter:GetNativeAhPrice(itemID)
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

function ProfessionExporter:ResolveCurrentAuctionPrice(itemID, opts)
	opts = opts or {}
	itemID = normalizeItemID(itemID)
	if not itemID then
		return nil, "missing", nil
	end
	local livePrice, liveSource, liveQty = self:GetLiveAuctionResultUnitPrice(itemID)
	if livePrice and livePrice > 0 then
		self:UpsertNativeAuctionPrice(itemID, livePrice, liveSource or "results_live", liveQty or 1, now())
		return livePrice, liveSource or "results_live", now()
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
		local st = self.db and self.db.settings or {}
		local marketStr = st.economyTSMMarketString or "dbmarket"
		local fallbackPrice, fallbackSource = self:GetMarketEstimateCopper(itemID, marketStr)
		if fallbackPrice and fallbackPrice > 0 then
			if self:IsDebugEnabled() then
				self:DebugLog("AH", "ResolveCurrentAuctionPrice", {
					string.format("itemID=%d source=fallback(%s) price=%s", itemID, tostring(fallbackSource), tostring(fallbackPrice)),
				})
			end
			return fallbackPrice, "fallback:" .. tostring(fallbackSource or "market"), now()
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

function ProfessionExporter:ResolveReagentUnitPrice(itemID, opts)
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

function ProfessionExporter:GetLastObservedAuctionPrice(itemID)
	local summary = self:GetItemEconomySummary(itemID, {})
	return summary and summary.lastPrice or nil
end

function ProfessionExporter:GetAuctionUnitPriceForCraftCost(itemID)
	local price, source = self:ResolveReagentUnitPrice(itemID, { allowFallback = true })
	return price, source
end

function ProfessionExporter:GetAuctionUnitPriceForCraftSale(itemID)
	local price, source = self:ResolveCurrentAuctionPrice(itemID, { allowFallback = true })
	if price and price > 0 then
		return price, source
	end
	local avgSell = self:LedgerAverageUnitSellCopper(itemID, nil)
	if avgSell and avgSell > 0 then
		return avgSell, "ledger_sell"
	end
	return nil, "missing"
end

function ProfessionExporter:EstimateCraftROIForItem(itemID)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return nil
	end
	local state = self:GetState()
	self:BuildCraftOpportunityRows({ forceSync = true })
	local best = state.craftOpportunityRoiIndex and state.craftOpportunityRoiIndex[itemID]
	return best and shallowCopy(best) or nil
end

function ProfessionExporter:GetCraftCostEstimateForItem(itemID, _opts)
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

function ProfessionExporter:BuildAuctionInventoryRows(opts)
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

function ProfessionExporter:OnAuctionHouseAuctionCreated()
	local state = self:GetState()
	if self:ConfirmAuctionBulkCurrent("auction_created") then
		return
	end
	local recent = state and state.recentAuctionBulkConfirmation or nil
	if recent and recent.itemID and ((GetTime and GetTime() or 0) - (tonumber(recent.at) or 0)) <= 2 then
		self:PrimeAuctionPanelRows()
		self:RefreshAuctionHousePanel()
		return
	end
	local itemID = normalizeItemID(state and state.auctionActiveItemID)
	if itemID then
		self:RecordAuctionTransaction({
			kind = "posted",
			itemID = itemID,
			quantity = 1,
			source = "auction_event",
		})
	end
	if not state.auctionRefreshRunning and not state.auctionRoiRunning then
		state.auctionActiveItemID = nil
	end
	self:PrimeAuctionPanelRows()
	self:RefreshAuctionHousePanel()
end

function ProfessionExporter:OnAuctionHouseAuctionSold()
	local state = self:GetState()
	local itemID = normalizeItemID(state and state.auctionActiveItemID)
	if itemID then
		self:RecordAuctionTransaction({
			kind = "sold",
			itemID = itemID,
			quantity = 1,
			source = "auction_event",
		})
	end
	self:PrimeAuctionPanelRows()
	self:RefreshAuctionHousePanel()
end

function ProfessionExporter:RunQueuedAuctionRefresh()
	local state = self:GetState()
	if not self:CanStartFullAuctionSideActions(false) then
		return
	end
	if state.auctionRefreshRunning then
		return
	end
	local queue = state.auctionRefreshQueue or {}
	local scanList = {}
	for key, entry in pairs(queue) do
		if entry == true then
			local id = normalizeItemID(key)
			if id then
				scanList[#scanList + 1] = { itemID = id, itemKeyFields = nil }
			end
		elseif type(entry) == "table" and entry.itemID then
			scanList[#scanList + 1] = {
				itemID = normalizeItemID(entry.itemID),
				itemKeyFields = copyScanKeyFields(entry.itemKeyFields),
				queueOrder = tonumber(entry.queueOrder) or 0,
			}
		end
	end
	if #scanList == 0 then
		return
	end
	table.sort(scanList, function(a, b)
		local ao = tonumber(a.queueOrder) or 0
		local bo = tonumber(b.queueOrder) or 0
		if ao ~= bo then
			return ao < bo
		end
		local ai, bi = tonumber(a.itemID) or 0, tonumber(b.itemID) or 0
		if ai ~= bi then
			return ai < bi
		end
		return self:SerializeAuctionItemKeyFields(a.itemID, a.itemKeyFields) < self:SerializeAuctionItemKeyFields(b.itemID, b.itemKeyFields)
	end)
	state.auctionScanMode = tostring(state.auctionPendingPriceScanMode or "price")
	state.auctionPendingPriceScanMode = nil
	state.auctionScanTotal = #scanList
	state.auctionScanDone = 0
	state.auctionLivePriceByItem = state.auctionLivePriceByItem or {}
	state.auctionNativePriceByItem = state.auctionNativePriceByItem or {}
	state.auctionSourceCounts = { native = 0, snapshot = 0, fallback = 0 }
	state.auctionSearchContext = nil
	state.auctionRefreshRunning = true
	state.auctionRefreshPaused = false
	state.auctionRefreshPausedForBulk = false
	local throttleMs = tonumber(self:GetSetting("auction.visibleRefreshThrottleMs", 150)) or 150
	state.auctionRefreshDelay = math.max(0.05, throttleMs / 1000)
	state.auctionRefreshScanList = scanList
	state.auctionRefreshIndex = 1
	state.auctionRefreshStartedAt = GetTime and GetTime() or nil
	self:ContinueQueuedAuctionRefresh()
end

-- The one record of when this realm's last full scan finished (saved, so it survives
-- /reload and relog). The badge, dashboard, AH panel and the cooldown all read it.
function ProfessionExporter:GetLastFullAuctionScanAt()
	local auction = self:InitAuctionDB()
	local byRealm = auction and auction.lastFullScanAt
	local realmKey = self:GetAuctionRegionKey() .. ":" .. self:GetAuctionConnectedRealmID()
	return type(byRealm) == "table" and tonumber(byRealm[realmKey]) or nil
end

function ProfessionExporter:SetLastFullAuctionScanAt(ts)
	local auction = self:InitAuctionDB()
	if not auction then
		return
	end
	auction.lastFullScanAt = type(auction.lastFullScanAt) == "table" and auction.lastFullScanAt or {}
	auction.lastFullScanAt[self:GetAuctionRegionKey() .. ":" .. self:GetAuctionConnectedRealmID()] = ts
end

--- The server answers one full scan request per cooldown, so the cooldown also runs from the last
--- request. That time is saved too: after a /reload in the middle of a scan the button shows the
--- wait instead of starting a scan the server will not answer.
function ProfessionExporter:SetLastFullAuctionScanRequestAt(ts)
	local auction = self:InitAuctionDB()
	auction.lastFullScanRequestAt = type(auction.lastFullScanRequestAt) == "table" and auction.lastFullScanRequestAt or {}
	auction.lastFullScanRequestAt[self:GetAuctionRegionKey() .. ":" .. self:GetAuctionConnectedRealmID()] = ts
end

function ProfessionExporter:GetFullAuctionDumpCooldownRemaining()
	local requests = self:InitAuctionDB().lastFullScanRequestAt
	local requestedAt = type(requests) == "table"
		and tonumber(requests[self:GetAuctionRegionKey() .. ":" .. self:GetAuctionConnectedRealmID()]) or 0
	local lastAt = math.max(self:GetLastFullAuctionScanAt() or 0, requestedAt)
	return math.max(0, lastAt + FULL_AH_DUMP_COOLDOWN_SEC - now())
end

function ProfessionExporter:IsFullAuctionDumpRunning()
	local dump = self:GetState().auctionDump
	return dump and dump.mode == "full" and dump.running == true
end

function ProfessionExporter:CanStartFullAuctionSideActions(announce)
	if self:IsFullAuctionDumpRunning() then
		if announce then
			self:PrintMessage("Full AH dump in progress. Wait for it to finish before starting another AH scan.")
		end
		return false
	end
	return true
end

function ProfessionExporter:QueueVisibleAuctionRefresh(itemIDs)
	if not self:CanStartFullAuctionSideActions(false) then
		return
	end
	local targets = {}
	for _, itemID in ipairs(itemIDs or {}) do
		local id = normalizeItemID(itemID)
		if id then
			targets[#targets + 1] = { itemID = id, itemKeyFields = nil }
		end
	end
	self:QueueAuctionScanTargets(targets)
end

function ProfessionExporter:BuildVisibleCraftsTabAuctionTargets()
	local ui = self.ui or nil
	local rows = ui and ui.craftsTable and ui.craftsTable.GetVisibleRows and ui.craftsTable:GetVisibleRows() or nil
	if type(rows) ~= "table" or #rows == 0 then
		rows = ui and ui.craftsWorkingRows or nil
	end
	if type(rows) ~= "table" then
		return {}
	end
	local targets = {}
	local seen = {}
	local function addTarget(itemID, itemKeyFields)
		local id = normalizeItemID(itemID)
		if not id then
			return
		end
		local fields = copyScanKeyFields(itemKeyFields)
		local key = self:AuctionScanEntryKey(id, fields)
		if seen[key] then
			return
		end
		seen[key] = true
		targets[#targets + 1] = {
			itemID = id,
			itemKeyFields = fields,
		}
	end
	for _, row in ipairs(rows) do
		addTarget(row and row.outputItemID, row and (row.itemKeyFields or row.auctionItemKey) or nil)
		local bestCharacterKey = row and row.bestCharacterKey or nil
		local eval = row and row.perChar and bestCharacterKey and row.perChar[bestCharacterKey] or nil
		for _, slot in ipairs(eval and eval.reagentPlan or {}) do
			addTarget(slot and slot.itemID, nil)
		end
	end
	return targets
end

function ProfessionExporter:QueueVisibleCraftsTabAuctionRefresh(force)
	if not self:CanStartFullAuctionSideActions(false) then
		return 0
	end
	local ui = self.ui or {}
	local targets = self:BuildVisibleCraftsTabAuctionTargets()
	if #targets == 0 then
		return 0
	end
	local signatureParts = {}
	for _, target in ipairs(targets) do
		signatureParts[#signatureParts + 1] = self:AuctionScanEntryKey(target.itemID, target.itemKeyFields)
	end
	local signature = table.concat(signatureParts, ",")
	if force ~= true and ui.craftsVisibleAuctionTargetsSignature == signature then
		return 0
	end
	ui.craftsVisibleAuctionTargetsSignature = signature

	local freshnessWindowSeconds = self:GetAuctionPriceFreshnessWindowSeconds()
	local currentTs = now()
	local filtered = {}
	for _, target in ipairs(targets) do
		local itemID = normalizeItemID(target.itemID)
		local fields = copyScanKeyFields(target.itemKeyFields)
		if itemID and (force == true or (not self:HasAuctionTargetBeenSearchedThisSession(itemID, fields) and self:IsItemAuctionScanStale(itemID, freshnessWindowSeconds, currentTs))) then
			filtered[#filtered + 1] = {
				itemID = itemID,
				itemKeyFields = fields,
			}
		end
	end
	if #filtered == 0 then
		return 0
	end
	local state = self:GetState()
		state.auctionPendingPriceScanMode = "crafts"
	state.auctionInvalidateCraftsAfterRefresh = true
	self:QueueAuctionScanTargets(filtered, { skipSessionSearched = true })
	return #filtered
end

function ProfessionExporter:QueueAuctionScanTargets(targets, opts)
	if not self:CanStartFullAuctionSideActions(false) then
		return
	end
	opts = type(opts) == "table" and opts or {}
	local state = self:GetState()
	state.auctionRefreshQueue = state.auctionRefreshQueue or {}
	local queued = state.auctionRefreshQueue
	state.auctionRefreshQueueOrderCounter = tonumber(state.auctionRefreshQueueOrderCounter) or 0
	for _, t in ipairs(targets or {}) do
		local id = normalizeItemID(t and t.itemID)
		if id then
			local fields = t.itemKeyFields or t.auctionItemKey
			fields = copyScanKeyFields(fields)
			local k = self:AuctionScanEntryKey(id, fields)
			if opts.skipSessionSearched ~= true or not self:HasAuctionTargetBeenSearchedThisSession(id, fields) then
				local existing = queued[k]
				if existing then
					existing.itemID = id
					existing.itemKeyFields = fields
				else
					state.auctionRefreshQueueOrderCounter = state.auctionRefreshQueueOrderCounter + 1
					queued[k] = {
						itemID = id,
						itemKeyFields = fields,
						queueOrder = state.auctionRefreshQueueOrderCounter,
					}
				end
			end
		end
	end
	self:RunQueuedAuctionRefresh()
end

function ProfessionExporter:BuildPrioritizedAuctionAutoScanTargets(opts)
	opts = type(opts) == "table" and opts or {}
	self:InitDB()
	local currentCharacterKey = tostring(self:GetCharacterKey() or "")
	local includeVisibleBags = opts.includeVisibleBags ~= false
	local includeCrafts = opts.includeCrafts ~= false
	local includeAccountInventory = opts.includeAccountInventory ~= false
	local includeSessionSearched = opts.includeSessionSearched == true
	local requireStaleNonVisible = opts.requireStaleNonVisible == true
	local freshnessWindowSeconds = tonumber(opts.freshnessWindowSeconds) or self:GetAuctionPriceFreshnessWindowSeconds()
	local currentTs = now()
	local targets = {}
	local seen = {}
	local function addTarget(target, _sourceKind)
		if type(target) ~= "table" then
			return
		end
		local itemID = normalizeItemID(target.itemID)
		if not itemID then
			return
		end
		local fields = copyScanKeyFields(target.itemKeyFields or target.auctionItemKey)
		local key = self:AuctionScanEntryKey(itemID, fields)
		if seen[key] then
			return
		end
		if includeSessionSearched ~= true and self:HasAuctionTargetBeenSearchedThisSession(itemID, fields) then
			return
		end
		if requireStaleNonVisible == true then
			if not self:IsItemAuctionScanStale(itemID, freshnessWindowSeconds, currentTs) then
				return
			end
		end
		seen[key] = true
		targets[#targets + 1] = {
			itemID = itemID,
			itemKeyFields = fields,
		}
	end

	if includeVisibleBags then
		for _, itemID in ipairs(self:BuildAuctionVisibleItemIDs() or {}) do
			addTarget({ itemID = itemID }, "visible")
		end
	end

	if includeCrafts and self.BuildCraftEconomyAuctionTargets then
		for _, t in ipairs(self:BuildCraftEconomyAuctionTargets({ characterKey = currentCharacterKey })) do
			addTarget(t, "craft")
		end
		local otherCharacterKeys = {}
		for rawCharacterKey in pairs(self.db.characters or {}) do
			local characterKey = tostring(rawCharacterKey)
			if characterKey ~= "" and characterKey ~= currentCharacterKey then
				otherCharacterKeys[#otherCharacterKeys + 1] = characterKey
			end
		end
		table.sort(otherCharacterKeys)
		for _, characterKey in ipairs(otherCharacterKeys) do
			for _, t in ipairs(self:BuildCraftEconomyAuctionTargets({ characterKey = characterKey })) do
				addTarget(t, "craft")
			end
		end
	end

	if includeAccountInventory then
		for _, t in ipairs(self:BuildAccountTradableInventoryAuctionTargets()) do
			addTarget(t, "account")
		end
	end

	return targets
end

--- Unique AH queue targets from saved snapshots: any item with stock on any character, tradable by static bind type.
function ProfessionExporter:BuildAccountTradableInventoryAuctionTargets()
	self:InitDB()
	local seenQty = {}
	for _, characterData in pairs(self.db.characters or {}) do
		local inv = characterData.inventorySnapshot
		if inv and type(inv.items) == "table" then
			for itemKey, entry in pairs(inv.items) do
				local id = tonumber(itemKey)
				if id and (tonumber(entry.total) or 0) > 0 then
					seenQty[id] = (seenQty[id] or 0) + (tonumber(entry.total) or 0)
				end
			end
		end
	end
	local targets = {}
	for id in pairs(seenQty) do
		if self.IsItemLikelyTradeableOnAuctionByStaticInfo and self:IsItemLikelyTradeableOnAuctionByStaticInfo(id) then
			targets[#targets + 1] = { itemID = id, itemKeyFields = nil }
		end
	end
	table.sort(targets, function(a, b)
		return (tonumber(a.itemID) or 0) < (tonumber(b.itemID) or 0)
	end)
	return targets
end

--- opts.crafts / opts.accountInventory: queue AH lookups (deduped). Crafts refresh invalidates craft caches when opts.crafts.
function ProfessionExporter:QueueAuctionEconomyScan(opts)
	opts = type(opts) == "table" and opts or {}
	if self:GetSetting("auction.enabled", true) == false then
		self:PrintMessage("Auction module is disabled.")
		return
	end
	local ah = _G.AuctionHouseFrame
	if not ah or not ah.IsShown or not ah:IsShown() then
		self:PrintMessage("Open the auction house first.")
		return
	end
	if not self:CanStartFullAuctionSideActions(true) then
		return
	end
	local state = self:GetState()
	if state.auctionRefreshRunning then
		self:PrintMessage("Auction price scan already running; wait for it to finish before starting another.")
		return
	end
	local wantCrafts = opts.crafts == true
	local wantInv = opts.accountInventory == true
	if not wantCrafts and not wantInv then
		return
	end
	local merged = self:BuildPrioritizedAuctionAutoScanTargets({
		includeVisibleBags = false,
		includeCrafts = wantCrafts,
		includeAccountInventory = wantInv,
		includeSessionSearched = false,
		requireStaleNonVisible = false,
	})
	if #merged == 0 then
		if wantCrafts and not wantInv then
			self:PrintMessage("No remaining craft targets to scan in this AH session. Run /ah scan first if needed.")
		elseif wantInv and not wantCrafts then
			self:PrintMessage("No remaining tradable account inventory items to scan in this AH session. Run /ah scan on your characters if needed.")
		else
			self:PrintMessage("Nothing left to scan in this AH session for the requested craft/account targets.")
		end
		return
	end
	if wantCrafts and wantInv then
		state.auctionPendingPriceScanMode = "mixed"
	elseif wantInv then
		state.auctionPendingPriceScanMode = "account_inv"
	else
		state.auctionPendingPriceScanMode = "crafts"
	end
	state.auctionInvalidateCraftsAfterRefresh = wantCrafts == true
	state.auctionRefreshQueue = {}
	state.auctionRefreshQueueOrderCounter = 0
	self:QueueAuctionScanTargets(merged, { skipSessionSearched = true })
	local label = wantCrafts and wantInv and "craft + account inventory" or wantInv and "account inventory" or "craft economy"
	self:PrintMessage(string.format("Queued %s AH scan (%d lookups). Keep the AH open until it finishes.", label, #merged))
	self:RefreshAuctionHousePanel()
end

function ProfessionExporter:QueueCraftEconomyAuctionRefresh(opts)
	opts = type(opts) == "table" and opts or {}
	opts.crafts = true
	opts.accountInventory = false
	self:QueueAuctionEconomyScan(opts)
end

function ProfessionExporter:StartAuctionRoiEnrichment(itemIDs)
	if not self:CanStartFullAuctionSideActions(false) then
		return
	end
	local state = self:GetState()
	local shareMainProgress = state.auctionRefreshRunning ~= true
	if state.auctionRoiRunning then
		return
	end
	state.auctionRoiQueue = {}
	for _, itemID in ipairs(itemIDs or {}) do
		local id = normalizeItemID(itemID)
		if id then
			state.auctionRoiQueue[#state.auctionRoiQueue + 1] = id
		end
	end
	if #state.auctionRoiQueue == 0 then
		return
	end
	if shareMainProgress then
		state.auctionScanMode = "roi"
		state.auctionScanTotal = #state.auctionRoiQueue
		state.auctionScanDone = 0
	end
	state.auctionRoiCache = state.auctionRoiCache or {}
	state.auctionRoiRunning = true
	local i = 1
	local throttleMs = math.max(20, tonumber(self:GetSetting("auction.visibleRefreshThrottleMs", 150)) or 150)
	local delay = throttleMs / 1000
	local function step()
		local itemID = state.auctionRoiQueue[i]
		if not itemID then
			state.auctionRoiRunning = false
			if shareMainProgress and not state.auctionRefreshRunning then
				state.auctionScanMode = "idle"
				state.auctionScanTotal = 0
				state.auctionScanDone = 0
				state.auctionActiveItemID = nil
			end
			self:MaybeStartDeferredAuctionBulk()
			self:RefreshAuctionHousePanel()
			return
		end
		state.auctionActiveItemID = itemID
		local roi = self:EstimateCraftROIForItem(itemID)
		state.auctionRoiCache[itemID] = roi
		local panelRows = state.auctionPanelRows or {}
		for _, row in ipairs(panelRows) do
			if tonumber(row.itemID) == tonumber(itemID) then
				row.potentialROI = roi and roi.potentialROI or nil
				row.recipeName = roi and roi.recipeName or nil
				row.qualityIndex = row.qualityIndex or (roi and roi.qualityIndex or nil)
				break
			end
		end
		if shareMainProgress then
			state.auctionScanDone = i
		end
		if i % 2 == 0 then
			self:RefreshAuctionHousePanel()
		end
		i = i + 1
		C_Timer.After(delay, step)
	end
	step()
end

--- Prefer retail AuctionHouseFrame; Forever / classic clients often expose AuctionFrame.
function ProfessionExporter:GetAuctionHouseAnchorFrame()
	local ah = _G.AuctionHouseFrame
	if ah then
		return ah
	end
	return _G.AuctionFrame
end

function ProfessionExporter:IsAuctionHouseFrameOpen()
	local ah = self:GetAuctionHouseAnchorFrame()
	return ah and ah.IsShown and ah:IsShown() and true or false
end

function ProfessionExporter:CanUseClassicAuctionDump()
	return type(QueryAuctionItems) == "function"
		and type(GetNumAuctionItems) == "function"
		and type(GetAuctionItemInfo) == "function"
end

function ProfessionExporter:CanUseReplicateAuctionDump()
	return C_AuctionHouse
		and type(C_AuctionHouse.ReplicateItems) == "function"
		and type(C_AuctionHouse.GetNumReplicateItems) == "function"
		and type(C_AuctionHouse.GetReplicateItemInfo) == "function"
end

function ProfessionExporter:FailFullAuctionDump(reason)
	local state = self:GetState()
	local dump = state.auctionDump
	if not dump or dump.mode ~= "full" then
		return
	end
	-- Prefer classic paging when replicate fails/times out and classic APIs exist.
	if dump.classic ~= true and self:CanUseClassicAuctionDump() then
		self:PrintMessage("Replicate dump unavailable (" .. tostring(reason or "unknown") .. "); trying classic AH scan.")
		local token = tonumber(dump.token)
		dump.running = false
		if self:StartClassicFullAuctionDump(token) then
			return
		end
		-- Fall through and mark failed if classic start also rejected.
		dump = state.auctionDump or dump
	end
	dump.running = false
	dump.status = "failed"
	dump.error = tostring(reason or "unknown")
	dump.finishedAt = now()
	self:PrintMessage("Full AH dump failed: " .. tostring(reason or "unknown"))
	self:RefreshAuctionHousePanel()
end

function ProfessionExporter:FinishFullAuctionDump()
	local state = self:GetState()
	local dump = state.auctionDump
	if not dump or dump.mode ~= "full" then
		return
	end
	dump.running = false
	dump.status = "complete"
	dump.finishedAt = now()
	self:SetLastFullAuctionScanAt(dump.finishedAt)
	self:PrintMessage(string.format("Full AH dump complete: %s items aggregated.", self:FormatNumberGrouped(tonumber(dump.persistTotal) or 0)))
	self:RefreshAuctionHousePanel()
	if self.RefreshMarketTab then
		self:RefreshMarketTab()
	end
	if self.RefreshShellStatus then
		self:RefreshShellStatus()
	end
end

function ProfessionExporter:PersistFullAuctionDumpChunk(token)
	local state = self:GetState()
	local dump = state.auctionDump
	if not dump or dump.mode ~= "full" or dump.running ~= true or tonumber(dump.token) ~= tonumber(token) then
		return
	end
	local keys = dump.persistKeys or {}
	local index = tonumber(dump.persistIndex) or 1
	if index > #keys then
		self:TrimFullDumpMarketHistory()
		self:PrimeAuctionPanelRows()
		self:FinishFullAuctionDump()
		return
	end
	dump.status = "processing"
	local last = math.min(#keys, index + FULL_AH_DUMP_PERSIST_CHUNK - 1)
	local seenAt = tonumber(dump.seenAt) or now()
	for i = index, last do
		local itemID = tonumber(keys[i])
		local aggregate = itemID and dump.aggregate and dump.aggregate[itemID] or nil
		if itemID and aggregate then
			local sourceLabel = tostring(dump.sourceLabel or (dump.classic and "classic_full" or "replicate_full"))
			self:PersistAuctionDumpObservation({
				itemID = itemID,
				isCommodity = false,
				itemKey = tostring(itemID),
				minBuyout = tonumber(aggregate.minBuyout),
				marketLow = tonumber(aggregate.marketLow),
				marketHigh = tonumber(aggregate.marketHigh),
				sampleSize = tonumber(aggregate.sampleSize) or 1,
				listingCount = tonumber(aggregate.listingCount),
				source = sourceLabel,
				seenAt = seenAt,
			})
			if tonumber(aggregate.weightedQty) and tonumber(aggregate.weightedQty) > 0 then
				self:RecordItemHistoryObservation(
					itemID,
					"market",
					tonumber(aggregate.weightedSum) / tonumber(aggregate.weightedQty),
					sourceLabel,
					seenAt
				)
			end
		end
	end
	dump.persistIndex = last + 1
	dump.persistDone = last
	if dump.persistIndex > #keys then
		dump.aggregate = nil
		dump.persistKeys = nil
		self:TrimFullDumpMarketHistory()
		self:PrimeAuctionPanelRows()
		self:FinishFullAuctionDump()
		return
	end
	self:RefreshAuctionHousePanel()
	C_Timer.After(0, function()
		ProfessionExporter:PersistFullAuctionDumpChunk(token)
	end)
end

function ProfessionExporter:ProcessFullAuctionDumpChunk(token)
	local state = self:GetState()
	local dump = state.auctionDump
	if not dump or dump.mode ~= "full" or dump.running ~= true or tonumber(dump.token) ~= tonumber(token) then
		return
	end
	if dump.status == "requesting" then
		return
	end
	local total = tonumber(dump.total) or 0
	local index = tonumber(dump.index) or 0
	if index >= total then
		dump.persistKeys = {}
		for itemID in pairs(dump.aggregate or {}) do
			dump.persistKeys[#dump.persistKeys + 1] = itemID
		end
		table.sort(dump.persistKeys)
		dump.persistIndex = 1
		dump.persistDone = 0
		dump.persistTotal = #dump.persistKeys
		self:PersistFullAuctionDumpChunk(token)
		return
	end
	dump.status = "processing"
	dump.aggregate = dump.aggregate or {}
	local aggregateRow = self.ForeverLogic and self.ForeverLogic.AggregateClassicAuctionRow
	local last = math.min(total - 1, index + FULL_AH_DUMP_ROW_CHUNK - 1)
	for i = index, last do
		local _, _, count, _, _, _, _, _, _, buyoutPrice, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(i)
		itemID = normalizeItemID(itemID)
		if aggregateRow then
			aggregateRow(dump.aggregate, itemID, count, buyoutPrice)
		elseif itemID then
			local quantity = math.max(1, tonumber(count) or 1)
			local rawBuyout = tonumber(buyoutPrice)
			local bucket = dump.aggregate[itemID] or {
				itemID = itemID,
				marketLow = nil,
				marketHigh = nil,
				minBuyout = nil,
				sampleSize = 0,
				listingCount = 0,
				weightedQty = 0,
				weightedSum = 0,
			}
			if rawBuyout and rawBuyout > 0 then
				local perUnit = rawBuyout / quantity
				bucket.marketLow = bucket.marketLow and math.min(bucket.marketLow, perUnit) or perUnit
				bucket.marketHigh = bucket.marketHigh and math.max(bucket.marketHigh, perUnit) or perUnit
				bucket.minBuyout = bucket.minBuyout and math.min(bucket.minBuyout, rawBuyout) or rawBuyout
				bucket.sampleSize = (tonumber(bucket.sampleSize) or 0) + quantity
				bucket.listingCount = (tonumber(bucket.listingCount) or 0) + 1
				bucket.weightedQty = (tonumber(bucket.weightedQty) or 0) + quantity
				bucket.weightedSum = (tonumber(bucket.weightedSum) or 0) + (perUnit * quantity)
			end
			dump.aggregate[itemID] = bucket
		end
	end
	dump.index = last + 1
	dump.done = dump.index
	self:RefreshAuctionHousePanel()
	C_Timer.After(0, function()
		ProfessionExporter:ProcessFullAuctionDumpChunk(token)
	end)
end

-- A fingerprint of the replicate list the client holds: its length and a few sampled rows.
-- The client keeps the list from the previous full scan, so "there is a list" does not mean the
-- server has answered the new request; a changed fingerprint does.
local function replicateListMark()
	local total = tonumber(C_AuctionHouse.GetNumReplicateItems()) or 0
	local parts = { total }
	for step = 0, total > 0 and 4 or -1 do
		local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(math.floor((total - 1) * step / 4))
		parts[#parts + 1] = string.format("%s/%s/%s", tostring(itemID), tostring(count), tostring(buyout))
	end
	return table.concat(parts, ":"), total
end

--- Polls once a second while a full scan waits for the server. Processing starts only when the
--- answer to this request is in (the list event fired, or the list changed) and the list has
--- stopped changing for one poll; a list left over from an earlier scan is never processed.
function ProfessionExporter:OnFullAuctionDumpTimeout(token)
	local state = self:GetState()
	local dump = state.auctionDump
	if not dump or dump.mode ~= "full" or tonumber(dump.token) ~= tonumber(token) or dump.status ~= "requesting" or dump.running ~= true then
		return
	end
	local mark, total = replicateListMark()
	if total > 0 and (dump.listUpdated or mark ~= dump.listMarkAtRequest) then
		if mark == dump.listMarkSettling then
			dump.total = total
			dump.done = 0
			dump.index = 0
			dump.seenAt = now()
			dump.aggregate = {}
			dump.status = "processing"
			self:RefreshAuctionHousePanel()
			self:ProcessFullAuctionDumpChunk(token)
			return
		end
		dump.listMarkSettling = mark
	end
	local startedAt = tonumber(dump.requestStartedAt) or now()
	if not dump.listMarkSettling and (now() - startedAt) >= FULL_AH_DUMP_REQUEST_TIMEOUT_SEC then
		self:FailFullAuctionDump("the server did not answer. It allows one full scan every "
			.. formatDurationShort(FULL_AH_DUMP_COOLDOWN_SEC) .. ", so try again later")
		return
	end
	C_Timer.After(FULL_AH_DUMP_REQUEST_POLL_SEC, function()
		ProfessionExporter:OnFullAuctionDumpTimeout(token)
	end)
end

--- REPLICATE_ITEM_LIST_UPDATE: the server answered the full scan request. The poll picks it up.
function ProfessionExporter:OnReplicateItemListUpdate()
	local dump = self:GetState().auctionDump
	if dump and dump.mode == "full" and dump.running == true and dump.status == "requesting" then
		dump.listUpdated = true
	end
end

function ProfessionExporter:TrimFullDumpMarketHistory()
	self:InitDB()
	local settings = self.db and self.db.settings and self.db.settings.auction or nil
	local retentionDays = tonumber(settings and settings.historyRetentionDays) or 30
	retentionDays = math.max(1, retentionDays)
	local cutoff = now() - (retentionDays * 24 * 3600)
	for _, itemHistory in pairs(self.db.itemHistory or {}) do
		local market = itemHistory and itemHistory.market or nil
		if market and market.buckets then
			for bucketAt in pairs(market.buckets) do
				local ts = tonumber(bucketAt)
				if ts and ts < cutoff then
					market.buckets[bucketAt] = nil
				end
			end
		end
	end
end

function ProfessionExporter:ContinueAuctionDump(token)
	local state = self:GetState()
	local dump = state.auctionDump
	if not dump or dump.running ~= true or tonumber(dump.token) ~= tonumber(token) then
		return
	end

	local rows = dump.rows or {}
	local index = tonumber(dump.index) or 1
	if index > #rows then
		dump.running = false
		dump.finishedAt = now()
		dump.remaining = 0
		dump.rows = nil
		dump.index = nil
		self:PrimeAuctionPanelRows()
		self:RefreshAuctionHousePanel()
		self:PrintMessage(string.format("Dump complete: %s items persisted.", self:FormatNumberGrouped(tonumber(dump.persistedCount) or tonumber(dump.total) or 0)))
		return
	end

	local batchSize = math.max(1, tonumber(dump.batchSize) or 1)
	local last = math.min(#rows, index + batchSize - 1)
	for i = index, last do
		local row = rows[i]
		if row and row.itemID then
			if self:PersistAuctionDumpObservation({
				itemID = row.itemID,
				isCommodity = row.isCommodity == true,
				itemKey = row.itemKey,
				itemKeyFields = row.itemKeyFields,
				marketLow = row.currentPrice,
				minBuyout = row.currentPrice,
				sampleSize = tonumber(row.sampleSize) or 1,
				source = tostring(row.source or ("dump_" .. tostring(dump.mode or "visible"))),
			}) then
				dump.persistedCount = (tonumber(dump.persistedCount) or 0) + 1
			end
		end
	end

	dump.index = last + 1
	dump.remaining = math.max(0, #rows - last)
	if dump.remaining <= 0 then
		dump.running = false
		dump.finishedAt = now()
		dump.rows = nil
		dump.index = nil
		self:PrimeAuctionPanelRows()
		self:RefreshAuctionHousePanel()
		self:PrintMessage(string.format("Dump complete: %s items persisted.", self:FormatNumberGrouped(tonumber(dump.persistedCount) or tonumber(dump.total) or 0)))
	else
		if ((tonumber(dump.total) or 0) - dump.remaining) % (batchSize * 2) == 0 then
			self:RefreshAuctionHousePanel()
		end
		C_Timer.After(0, function()
			ProfessionExporter:ContinueAuctionDump(token)
		end)
	end
end

function ProfessionExporter:CollectVisibleAuctionDumpRows()
	local rows = {}
	local seen = {}
	local function addOrOverlay(row, overlay)
		local itemID = normalizeItemID(row and row.itemID)
		if not itemID then
			return
		end
		row.itemID = itemID
		local existing = seen[itemID]
		if existing then
			if overlay then
				local overlayPrice = tonumber(row.currentPrice)
				if overlayPrice and overlayPrice > 0 then
					existing.currentPrice = overlayPrice
					existing.sampleSize = tonumber(row.sampleSize) or existing.sampleSize
					existing.isCommodity = row.isCommodity
					existing.itemKey = row.itemKey
					existing.itemKeyFields = row.itemKeyFields
					existing.source = row.source
				end
			end
			return
		end
		seen[itemID] = row
		rows[#rows + 1] = row
	end

	local state = self:GetState()
	local sourceRows = self:PrimeAuctionPanelRows()
	if type(sourceRows) ~= "table" then
		sourceRows = state.auctionPanelRows or {}
	end
	for _, row in ipairs(sourceRows or {}) do
		local itemID = normalizeItemID(row and row.itemID)
		if itemID and self:IsAuctionDumpAhOriginPrice(row) then
			addOrOverlay({
				itemID = itemID,
				currentPrice = tonumber(row.currentPrice),
				sampleSize = 1,
				isCommodity = self:ResolveDumpItemCommodity(itemID, true),
				itemKey = tostring(itemID),
				source = "dump_visible",
			}, false)
		end
	end

	if C_AuctionHouse and C_AuctionHouse.GetBrowseResults then
		local results = C_AuctionHouse.GetBrowseResults() or {}
		for _, result in pairs(results) do
			if type(result) == "table" then
				local itemKey = result.itemKey
				local itemID = normalizeItemID(itemKey and itemKey.itemID)
				if itemID then
					local keyFields = self:ExtractAuctionItemKeyFieldsFromEventArg(itemKey)
					addOrOverlay({
						itemID = itemID,
						currentPrice = tonumber(result.minPrice),
						sampleSize = math.max(1, tonumber(result.totalQuantity) or 1),
						isCommodity = self:ResolveDumpItemCommodity(itemKey, false),
						itemKey = tostring(itemID),
						itemKeyFields = keyFields,
						source = "dump_browse",
					}, true)
				end
			end
		end
	end
	return rows
end

function ProfessionExporter:StartClassicFullAuctionDump(existingToken)
	if not self:CanUseClassicAuctionDump() then
		self:PrintMessage("Full AH dump is unavailable in this client/API context.")
		return false
	end
	if not self:IsAuctionHouseFrameOpen() then
		self:PrintMessage("Open the auction house before starting a full dump.")
		return false
	end
	local state = self:GetState()
	local cooldownRemaining = self:GetFullAuctionDumpCooldownRemaining()
	if cooldownRemaining > 0 and not existingToken then
		self:PrintMessage("Full AH dump is on cooldown for " .. formatDurationShort(cooldownRemaining) .. ".")
		self:RefreshAuctionHousePanel()
		return false
	end
	self:StopAuctionScanForDump()
	local token = tonumber(existingToken)
	if not token then
		token = (tonumber(state.auctionDumpToken) or 0) + 1
		state.auctionDumpToken = token
	end
	state.auctionDump = {
		token = token,
		running = true,
		mode = "full",
		classic = true,
		status = "querying",
		startedAt = now(),
		requestStartedAt = now(),
		page = 0,
		total = 0,
		done = 0,
		index = 0,
		persistDone = 0,
		persistTotal = 0,
		aggregate = {},
		pageSize = CLASSIC_AH_DUMP_PAGE_SIZE,
		queryRetries = 0,
	}
	self:PrintMessage("Starting classic AH full dump (paged QueryAuctionItems).")
	self:RefreshAuctionHousePanel()
	self:QueryClassicAuctionDumpPage(token, 0)
	return true
end

function ProfessionExporter:QueryClassicAuctionDumpPage(token, page, retries)
	local state = self:GetState()
	local dump = state.auctionDump
	if not dump or dump.mode ~= "full" or dump.classic ~= true or dump.running ~= true or tonumber(dump.token) ~= tonumber(token) then
		return
	end
	retries = tonumber(retries) or 0
	if not self:IsAuctionHouseFrameOpen() then
		self:FailFullAuctionDump("Auction house closed during classic dump.")
		return
	end
	if type(CanSendAuctionQuery) == "function" and not CanSendAuctionQuery() then
		if retries >= CLASSIC_AH_DUMP_QUERY_MAX_RETRIES then
			self:FailFullAuctionDump("Timed out waiting to query auction listings.")
			return
		end
		dump.status = "waiting_query"
		dump.queryRetries = retries + 1
		C_Timer.After(CLASSIC_AH_DUMP_QUERY_RETRY_SEC, function()
			ProfessionExporter:QueryClassicAuctionDumpPage(token, page, retries + 1)
		end)
		return
	end
	dump.status = "querying"
	dump.page = tonumber(page) or 0
	dump.requestStartedAt = now()
	dump.queryRetries = 0
	local ok = pcall(QueryAuctionItems, "", nil, nil, dump.page, false, nil, false, false)
	if not ok then
		self:FailFullAuctionDump("Classic QueryAuctionItems failed.")
		return
	end
	self:RefreshAuctionHousePanel()
end

function ProfessionExporter:OnAuctionItemListUpdate()
	local state = self:GetState()
	local dump = state.auctionDump
	if not dump or dump.mode ~= "full" or dump.classic ~= true or dump.running ~= true then
		return false
	end
	if dump.status ~= "querying" and dump.status ~= "waiting_query" then
		return false
	end
	local numBatch, totalAuctions = GetNumAuctionItems("list")
	numBatch = tonumber(numBatch) or 0
	totalAuctions = tonumber(totalAuctions) or 0
	dump.total = totalAuctions
	dump.status = "processing"
	dump.seenAt = now()
	dump.aggregate = dump.aggregate or {}
	local aggregateRow = self.ForeverLogic and self.ForeverLogic.AggregateClassicAuctionRow
	for i = 1, numBatch do
		local _, _, count, _, _, _, _, _, _, buyoutPrice, _, _, _, _, _, _, itemID = GetAuctionItemInfo("list", i)
		itemID = normalizeItemID(itemID)
		if not itemID and type(GetAuctionItemLink) == "function" then
			local link = GetAuctionItemLink("list", i)
			if type(link) == "string" then
				itemID = normalizeItemID(link:match("item:(%d+)"))
			end
		end
		if aggregateRow then
			aggregateRow(dump.aggregate, itemID, count, buyoutPrice)
		elseif itemID then
			local quantity = math.max(1, tonumber(count) or 1)
			local rawBuyout = tonumber(buyoutPrice)
			local bucket = dump.aggregate[itemID] or {
				itemID = itemID,
				marketLow = nil,
				marketHigh = nil,
				minBuyout = nil,
				sampleSize = 0,
				listingCount = 0,
				weightedQty = 0,
				weightedSum = 0,
			}
			if rawBuyout and rawBuyout > 0 then
				local perUnit = rawBuyout / quantity
				bucket.marketLow = bucket.marketLow and math.min(bucket.marketLow, perUnit) or perUnit
				bucket.marketHigh = bucket.marketHigh and math.max(bucket.marketHigh, perUnit) or perUnit
				bucket.minBuyout = bucket.minBuyout and math.min(bucket.minBuyout, rawBuyout) or rawBuyout
				bucket.sampleSize = (tonumber(bucket.sampleSize) or 0) + quantity
				bucket.listingCount = (tonumber(bucket.listingCount) or 0) + 1
				bucket.weightedQty = (tonumber(bucket.weightedQty) or 0) + quantity
				bucket.weightedSum = (tonumber(bucket.weightedSum) or 0) + (perUnit * quantity)
			end
			dump.aggregate[itemID] = bucket
		end
	end
	local pageSize = tonumber(dump.pageSize) or CLASSIC_AH_DUMP_PAGE_SIZE
	local page = tonumber(dump.page) or 0
	dump.done = math.min(totalAuctions, (page * pageSize) + numBatch)
	self:RefreshAuctionHousePanel()
	if numBatch >= pageSize and dump.done < totalAuctions then
		C_Timer.After(0.15, function()
			ProfessionExporter:QueryClassicAuctionDumpPage(dump.token, page + 1)
		end)
		return true
	end
	-- Finished paging: persist aggregates through the shared dump pipeline.
	dump.persistKeys = {}
	for itemID in pairs(dump.aggregate or {}) do
		dump.persistKeys[#dump.persistKeys + 1] = itemID
	end
	table.sort(dump.persistKeys)
	dump.persistIndex = 1
	dump.persistDone = 0
	dump.persistTotal = #dump.persistKeys
	dump.sourceLabel = "classic_full"
	self:PersistFullAuctionDumpChunk(dump.token)
	return true
end

function ProfessionExporter:StartAuctionDump(mode)
	mode = tostring(mode or "visible")
	local state = self:GetState()
	local activeDump = state.auctionDump
	if activeDump and activeDump.running == true then
		self:PrintMessage("An auction dump is already running.")
		return false
	end
	if mode == "full" then
		local cooldownRemaining = self:GetFullAuctionDumpCooldownRemaining()
		if cooldownRemaining > 0 then
			self:PrintMessage("Full AH dump is on cooldown for " .. formatDurationShort(cooldownRemaining) .. ".")
			self:RefreshAuctionHousePanel()
			return false
		end
		if self:CanUseReplicateAuctionDump() then
			self:StopAuctionScanForDump()
			local token = (tonumber(state.auctionDumpToken) or 0) + 1
			state.auctionDumpToken = token
			state.auctionDump = {
				token = token,
				running = true,
				mode = "full",
				status = "requesting",
				startedAt = now(),
				requestStartedAt = now(),
				total = 0,
				done = 0,
				index = 0,
				persistDone = 0,
				persistTotal = 0,
				listMarkAtRequest = replicateListMark(),
			}
			local ok = pcall(C_AuctionHouse.ReplicateItems)
			if not ok then
				return self:StartClassicFullAuctionDump(token)
			end
			self:SetLastFullAuctionScanRequestAt(now())
			self:RefreshAuctionHousePanel()
			C_Timer.After(FULL_AH_DUMP_REQUEST_POLL_SEC, function()
				ProfessionExporter:OnFullAuctionDumpTimeout(token)
			end)
			return true
		end
		return self:StartClassicFullAuctionDump()
	end
	self:StopAuctionScanForDump()
	local rows = self:CollectVisibleAuctionDumpRows()
	local batchSize = tonumber(self:GetSetting("auction.dumpBatchSize", 50)) or 50
	batchSize = math.max(1, math.floor(batchSize))
	local token = (tonumber(state.auctionDumpToken) or 0) + 1
	state.auctionDumpToken = token
	state.auctionDump = {
		token = token,
		running = true,
		mode = mode,
		startedAt = now(),
		batchSize = batchSize,
		rows = rows,
		index = 1,
		total = #rows,
		remaining = #rows,
		persistedCount = 0,
	}
	if #rows == 0 then
		state.auctionDump.running = false
		state.auctionDump.finishedAt = now()
		self:RefreshAuctionHousePanel()
		self:PrintMessage("Dump complete: 0 items persisted.")
		return true
	end
	self:RefreshAuctionHousePanel()
	C_Timer.After(0, function()
		ProfessionExporter:ContinueAuctionDump(token)
	end)
	return true
end

function ProfessionExporter:BuildAuctionVisibleItemIDs()
	local bagState = self:GetAuctionOwnedBagState(false)
	return shallowCopy(bagState and bagState.orderedItemIDs or {})
end

function ProfessionExporter:OnAuctionHouseShow()
	if self:GetSetting("auction.enabled", true) == false then
		return
	end
	self.ui = self.ui or {}
	self.ui.auctionPanelTabManual = nil
	self.ui.auctionPanelActiveTab = nil
	if self:GetSetting("auction.sellPanelEnabled", true) then
		local panel = self:EnsureAuctionHousePanel()
		self:HideExtraAuctionHousePanels(panel)
		if panel then
			panel:Show()
		end
	end
	self:PrimeAuctionPanelRows()
	self:RefreshAuctionHousePanel()
	self:RetryPrimeAuctionPanelRows(1)
	if self:CanStartFullAuctionSideActions(false) then
		local state = self:GetState()
		local targets = self:BuildPrioritizedAuctionAutoScanTargets({
			includeVisibleBags = true,
			includeCrafts = true,
			includeAccountInventory = true,
			includeSessionSearched = false,
			requireStaleNonVisible = true,
			freshnessWindowSeconds = AUTO_SCAN_MAX_AGE_SEC,
		})
		if #targets > 0 then
			state.auctionPendingPriceScanMode = "mixed"
			state.auctionInvalidateCraftsAfterRefresh = true
			state.auctionRefreshQueue = {}
			state.auctionRefreshQueueOrderCounter = 0
			self:QueueAuctionScanTargets(targets, { skipSessionSearched = true })
		end
		self:StartAuctionRoiEnrichment(self:BuildAuctionVisibleItemIDs())
	end
end

function ProfessionExporter:OnAuctionHouseClosed()
	local state = self:GetState()
	if state.auctionDump and state.auctionDump.running == true then
		state.auctionDump.running = false
		state.auctionDump.finishedAt = now()
	end
	state.auctionRefreshQueue = {}
	state.auctionRefreshRunning = false
	state.auctionRefreshPaused = false
	state.auctionRefreshPausedForBulk = false
	state.auctionRefreshScanList = nil
	state.auctionRefreshIndex = nil
	state.auctionSearchContext = nil
	state.auctionPendingBrowseSearch = nil
	state.auctionRoiQueue = {}
	state.auctionRoiRunning = false
	state.auctionLivePriceByItem = {}
	state.auctionNativePriceByItem = {}
	state.auctionSourceCounts = nil
	state.auctionLastSellSelectionItemID = nil
	state.auctionPanelSelectedItemID = nil
	state.auctionCartSelectedItemID = nil
	state.auctionPanelRows = nil
	state.auctionPanelRowsViewRevision = nil
	state.auctionPanelRowsBagSignature = nil
	state.auctionOwnedBagState = nil
	state.auctionBulk = nil
	state.recentAuctionBulkConfirmation = nil
	state.auctionScanMode = "idle"
	state.auctionScanTotal = 0
	state.auctionScanDone = 0
	state.auctionActiveItemID = nil
	state.auctionInvalidateCraftsAfterRefresh = false
	state.auctionPendingPriceScanMode = nil
	state.auctionRefreshStartedAt = nil
	state.auctionRefreshQueueOrderCounter = nil
	state.auctionSearchedTargets = nil
	state.auctionSearchedTargetsMeta = nil
	if self.ui and self.ui.auctionPanel then
		self.ui.auctionPanel:Hide()
	end
end

function ProfessionExporter:ApplyAuctionSearchResultToDatabase(itemID, keyFields, sourceTag)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return false
	end
	self:MarkAuctionTargetSearched(itemID, keyFields, sourceTag or "manual_search", now())
	local agg = self:GetLiveAuctionSearchAggregate(itemID, keyFields)
	if not agg then
		return false
	end
	self:RecordLiveAuctionObservationsFromAggregate(itemID, agg, tostring(sourceTag or "manual_search"))
	self:ApplyLiveAggregateToNativePrice(itemID, agg)
	self:SaveLiveSearchToScanEntry(itemID, agg)
	self:UpdateAuctionPanelRowPrice(itemID, self:BuildAuctionPanelPriceState(itemID))
	return true
end

--- The full scan keeps one entry per item ID (item scope, key = item ID), and Market and the
--- Gold dashboard read that entry. A live search lands under other keys, so copy its price,
--- quantity and auction count there when they changed; otherwise only mark the entry as seen now.
--- `quiet` leaves the view refresh to the caller (a result list saves many items at once).
function ProfessionExporter:SaveLiveSearchToScanEntry(itemID, agg, quiet)
	local price = tonumber(agg.minUnitPrice or agg.cheapestUnitPrice)
	if not price or price <= 0 then
		return false
	end
	local quantity = tonumber(agg.totalQuantity or agg.totalQuantityAll)
	local listings = tonumber(agg.listingCount or agg.listingCountAll)
	local auction = self:InitAuctionDB()
	local storageKey = self:BuildAuctionStorageKey(itemID, "item", tostring(itemID))
	local saved = storageKey and auction.snapshot.items[storageKey]
	if not self.ForeverLogic.LiveSearchDiffers(saved, price, quantity, listings) then
		saved.t = now()
		return false
	end
	self:RecordAuctionObservation({
		itemID = itemID,
		isCommodity = false,
		itemKey = tostring(itemID),
		marketLow = price,
		minBuyout = price,
		marketHigh = tonumber(agg.maxUnitPrice or agg.highestUnitPrice),
		sampleSize = quantity,
		listingCount = listings,
		source = "results_live_search",
		seenAt = now(),
	})
	if not quiet then
		self:RefreshViewsAfterLiveSearch()
	end
	return true
end

--- A live search changed saved prices: let the dashboard rebuild now instead of waiting out the
--- scan throttle.
function ProfessionExporter:RefreshViewsAfterLiveSearch()
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
function ProfessionExporter:SaveBrowseResultsToScanEntries()
	local byItem = {}
	for _, result in ipairs(C_AuctionHouse.GetBrowseResults and C_AuctionHouse.GetBrowseResults() or {}) do
		local itemID = normalizeItemID(result.itemKey)
		local price = tonumber(result.minPrice) or 0
		if itemID and price > 0 then
			local agg = byItem[itemID] or { totalQuantity = 0 }
			byItem[itemID] = agg
			agg.minUnitPrice = math.min(agg.minUnitPrice or price, price)
			agg.totalQuantity = agg.totalQuantity + (tonumber(result.totalQuantity) or 0)
		end
	end
	local changed = false
	for itemID, agg in pairs(byItem) do
		changed = self:SaveLiveSearchToScanEntry(itemID, agg, true) or changed
	end
	if changed then
		self:RefreshViewsAfterLiveSearch()
	end
end

function ProfessionExporter:OnAuctionHouseBrowseResultsUpdated()
	local state = self:GetState()
	self:DebugLog("AH", "event browse results", {
		string.format("pending=%s", tostring(state and state.auctionPendingBrowseSearch and state.auctionPendingBrowseSearch.itemID)),
	})
	if self:TrySelectPendingAuctionBrowseResult() then
		C_Timer.After(0, function()
			ProfessionExporter:TrySelectPendingAuctionBrowseResult()
		end)
	end
	self:SaveBrowseResultsToScanEntries()
	self:RefreshAuctionHousePanel()
end

function ProfessionExporter:OnCommoditySearchResultsUpdated(itemID)
	local state = self:GetState()
	self:DebugLog("AH", "event commodity results", {
		string.format("arg=%s selected=%s ctx=%s", tostring(normalizeSearchEventItemID(itemID)),
			tostring(state and state.auctionLastSellSelectionItemID), tostring(state and state.auctionSearchContext and state.auctionSearchContext.itemID)),
	})
	local ctx = state and state.auctionSearchContext or nil
	if ctx and self:DoesAuctionSearchEventMatchItem(ctx.itemID, itemID, ctx.scanKeyFields) then
		self:FinishQueuedAuctionRefreshItem(ctx.itemID, nil)
		return
	end
	local selectedItemID = normalizeItemID(itemID) or normalizeItemID(state and state.auctionLastSellSelectionItemID)
	if selectedItemID then
		self:ApplyAuctionSearchResultToDatabase(selectedItemID, nil, "commodity_results_event")
	end
	self:RefreshAuctionHousePanel()
end

function ProfessionExporter:OnItemSearchResultsUpdated(itemKey)
	local state = self:GetState()
	self:DebugLog("AH", "event item results", {
		string.format("arg=%s selected=%s ctx=%s", tostring(normalizeSearchEventItemID(itemKey)),
			tostring(state and state.auctionLastSellSelectionItemID), tostring(state and state.auctionSearchContext and state.auctionSearchContext.itemID)),
	})
	local ctx = state and state.auctionSearchContext or nil
	if ctx and self:DoesAuctionSearchEventMatchItem(ctx.itemID, itemKey, ctx.scanKeyFields) then
		self:FinishQueuedAuctionRefreshItem(ctx.itemID, nil)
		return
	end
	local selectedItemID = normalizeSearchEventItemID(itemKey) or normalizeItemID(state and state.auctionLastSellSelectionItemID)
	local keyFields = self:ExtractAuctionItemKeyFieldsFromEventArg(itemKey)
	if selectedItemID then
		self:ApplyAuctionSearchResultToDatabase(selectedItemID, keyFields, "item_results_event")
	end
	self:RefreshAuctionHousePanel()
end

function ProfessionExporter:OnAuctionBagUpdate()
	if self:IsAuctionHouseFrameOpen() then
		local panel = self.ui and self.ui.auctionPanel
		if panel and panel.IsShown and panel:IsShown() then
			self:PrimeAuctionPanelRows()
			self:RefreshAuctionHousePanel()
		end
	end
	if self.RefreshCraftsTabIfVisible then
		self:RefreshCraftsTabIfVisible()
	end
	if self.RefreshProfessionCraftEconomyPanel then
		self:RefreshProfessionCraftEconomyPanel()
	end
end

function ProfessionExporter:OnCommodityPurchased(itemID, quantity)
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

function ProfessionExporter:OnItemPurchased(itemID)
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

function ProfessionExporter:OnAuctionHousePurchaseCompleted(auctionID)
	self:DebugLog("AH", "event auction house purchase completed", {
		string.format("auctionID=%s", tostring(auctionID)),
	})
	self:ScheduleAuctionCartPurchaseRefresh()
end

function ProfessionExporter:OnCommodityPurchaseSucceeded(...)
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

function ProfessionExporter:OnCommodityPurchaseFailed(...)
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

if not ProfessionExporter.__ahCartPurchaseHooksInstalled then
	ProfessionExporter.__ahCartPurchaseHooksInstalled = true
	if C_AuctionHouse and C_AuctionHouse.ConfirmCommoditiesPurchase then
		hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, quantity)
			local pe = ProfessionExporter
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
