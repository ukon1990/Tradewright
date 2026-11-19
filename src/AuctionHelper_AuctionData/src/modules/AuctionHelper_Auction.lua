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

local function isAuctionHousePanelReady(panel)
	return panel
		and panel.__ahAuctionPanelInitialized == true
		and panel.tabCart
		and panel.tableHost
		and panel.cartTableHost
end

local function wipeFrameChildren(frame)
	if not frame or not frame.GetNumChildren then
		return
	end
	for i = frame:GetNumChildren(), 1, -1 do
		local child = select(i, frame:GetChildren())
		if child and child.SetParent then
			child:SetParent(nil)
		end
	end
end

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

local function setFontColor(fontString, color)
	if not fontString or not color then
		return
	end
	fontString:SetTextColor(color.r or 1, color.g or 1, color.b or 1)
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

local function containsText(haystack, needle)
	return string.find(string.lower(tostring(haystack or "")), string.lower(tostring(needle or "")), 1, true) ~= nil
end

local function applyRankBadge(texture, text, rankIndex)
	if not texture or not text or not rankIndex or rankIndex <= 0 then
		if texture then texture:Hide() end
		if text then text:Hide() end
		return
	end
	local atlas = "Professions-Icon-Quality-Tier" .. tostring(rankIndex) .. "-Inv"
	if texture.SetAtlas then
		texture:SetAtlas(atlas, true)
	end
	texture:Show()
	text:SetText(tostring(rankIndex))
	text:Show()
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

local function attachSimpleTooltip(widget, title, body)
	if not widget then
		return
	end
	widget:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(title or "", 1, 0.82, 0.2)
		if body and body ~= "" then
			GameTooltip:AddLine(body, 0.82, 0.88, 0.96, true)
		end
		GameTooltip:Show()
	end)
	widget:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
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
	local expected = self:MakeAuctionHouseItemKey(scanItemID, scanKeyFields)
	return expected and evKey and tostring(expected) == tostring(evKey)
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
			local minUnit = nil
			for i = 1, n do
				local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
				if info then
					totalQty = totalQty + math.max(0, tonumber(info.quantity) or 0)
					local u = tonumber(info.unitPrice)
					if u and u > 0 then
						minUnit = minUnit and math.min(minUnit, u) or u
					end
				end
			end
			if minUnit and minUnit > 0 then
				return {
					kind = "commodity",
					itemID = itemID,
					minUnitPrice = minUnit,
					totalQuantity = math.max(1, totalQty),
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
	local expectedKey = self:NormalizeAuctionItemKeyFields(keyFields) and self:MakeAuctionHouseItemKey(itemID, keyFields) or nil
	local groups = {}
	for i = 1, m do
		local info = C_AuctionHouse.GetItemSearchResultInfo(queryKey, i)
		if info and info.itemKey then
			if expectedKey and tostring(info.itemKey) ~= tostring(expectedKey) then
				-- Narrow search: ignore rows that do not match the requested ItemKey.
			else
				local rowKey = tostring(info.itemKey)
				local g = groups[rowKey]
				if not g then
					g = { itemKey = info.itemKey, totalQuantity = 0, minUnitPrice = nil }
					groups[rowKey] = g
				end
				local qty = math.max(1, tonumber(info.quantity) or 1)
				g.totalQuantity = g.totalQuantity + qty
				local buyout = tonumber(info.buyoutAmount)
				if buyout and buyout > 0 then
					local unit = math.floor(buyout / qty)
					if unit and unit > 0 then
						g.minUnitPrice = g.minUnitPrice and math.min(g.minUnitPrice, unit) or unit
					end
				end
			end
		end
	end
	local variantList = {}
	local totalAll = 0
	local cheapestGlobal = nil
	for _, g in pairs(groups) do
		if g.minUnitPrice and g.minUnitPrice > 0 then
			variantList[#variantList + 1] = g
			totalAll = totalAll + math.max(1, tonumber(g.totalQuantity) or 1)
			cheapestGlobal = cheapestGlobal and math.min(cheapestGlobal, g.minUnitPrice) or g.minUnitPrice
		end
	end
	if #variantList == 0 then
		return nil
	end
	table.sort(variantList, function(a, b)
		return tostring(a.itemKey) < tostring(b.itemKey)
	end)
	return {
		kind = "item",
		itemID = itemID,
		variants = variantList,
		cheapestUnitPrice = cheapestGlobal,
		totalQuantityAll = math.max(1, totalAll),
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

function ProfessionExporter:FinishQueuedAuctionRefreshItem(itemID, priceStateIgnored)
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
	bulk.buttonAttempts = 0
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
	state.auctionRefreshPaused = not (state.auctionRefreshPaused == true)
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
	bulk.buttonAttempts = 0
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
	bulk.buttonAttempts = 0
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

function ProfessionExporter:ProcessAuctionBulkPhase(token)
	local state = self:GetState()
	local bulk = state.auctionBulk
	if not bulk or bulk.running ~= true or tonumber(bulk.token) ~= tonumber(token) then
		return
	end
	if bulk.paused == true then
		return
	end
	if bulk.phase == "waiting_button" then
		if self:TryClickAuctionPostButton() then
			bulk.phase = "waiting_confirmation"
			bulk.confirmationStartedAt = GetTime and GetTime() or 0
			bulk.status = string.format("Waiting for confirmation: %s", self:GetItemDisplayName(bulk.currentItemID))
			self:DebugLog("AH", "bulk click post", {
				string.format("itemID=%s token=%s", tostring(bulk.currentItemID), tostring(token)),
			})
			self:RefreshAuctionHousePanel()
			C_Timer.After(0.25, function()
				ProfessionExporter:ProcessAuctionBulkPhase(token)
			end)
			return
		end
		bulk.buttonAttempts = (tonumber(bulk.buttonAttempts) or 0) + 1
		if (tonumber(bulk.buttonAttempts) or 0) >= (tonumber(bulk.maxRetries) or 8) then
			self:FailAuctionBulkCurrent("Failed to post")
			return
		end
		bulk.status = string.format("Waiting post button (%d/%d): %s", bulk.buttonAttempts, bulk.maxRetries, self:GetItemDisplayName(bulk.currentItemID))
		self:DebugLog("AH", "bulk wait button", {
			string.format("itemID=%s attempts=%d/%d", tostring(bulk.currentItemID), bulk.buttonAttempts, bulk.maxRetries),
		})
		self:RefreshAuctionHousePanel()
		C_Timer.After(0.12, function()
			ProfessionExporter:ProcessAuctionBulkPhase(token)
		end)
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
			bulk.buttonAttempts = 0
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
		bulk.buttonAttempts = 0
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
	bulk.buttonAttempts = 0
	bulk.token = (tonumber(bulk.token) or 0) + 1
	self:RefreshAuctionHousePanel()
	C_Timer.After(0.15, function()
		ProfessionExporter:ProcessAuctionBulkPhase(bulk.token)
	end)
end

function ProfessionExporter:OnOwnedAuctionsUpdated()
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
	bulk.paused = not (bulk.paused == true)
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
		if bulk.phase == "waiting_button" or bulk.phase == "waiting_confirmation" then
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
	return auction
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
	auction.history.daily = nil
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
	local state = self:GetState()
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

function ProfessionExporter:ShowAuctionReservePrompt(itemID)
	itemID = normalizeItemID(itemID)
	if not itemID then
		self:PrintMessage("Select an auction row first.")
		return
	end
	local function getPopupEditBox(dialog)
		if not dialog then
			return nil
		end
		return dialog.editBox or dialog.EditBox or dialog.editbox
	end
	local dialogKey = addonName .. "AuctionReserveQty"
	StaticPopupDialogs[dialogKey] = StaticPopupDialogs[dialogKey] or {
		text = "Keep at least this many items in bags:",
		button1 = ACCEPT,
		button2 = CANCEL,
		hasEditBox = true,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		OnAccept = function(dialog)
			local editBox = getPopupEditBox(dialog)
			local value = editBox and editBox:GetText() or ""
			local qty = math.max(0, math.floor(tonumber(value) or 0))
			ProfessionExporter:SetAuctionItemRule(itemID, { reserveQty = qty > 0 and qty or nil })
			ProfessionExporter:DebugLog("AH", "rule reserve set", {
				string.format("itemID=%d reserveQty=%d", itemID, qty),
			})
			ProfessionExporter:PrimeAuctionPanelRows()
			ProfessionExporter:RefreshAuctionHousePanel()
		end,
		EditBoxOnEnterPressed = function(editBox)
			local parent = editBox and editBox:GetParent()
			if parent then
				parent.button1:Click()
			end
		end,
		OnShow = function(dialog)
			local rule = ProfessionExporter:GetAuctionItemRule(itemID) or {}
			local current = tonumber(rule.reserveQty) or 0
			local editBox = getPopupEditBox(dialog)
			if not editBox then
				ProfessionExporter:DebugLog("AH", "reserve dialog missing edit box", {
					string.format("itemID=%d", itemID),
				})
				return
			end
			editBox:SetText(current > 0 and tostring(current) or "")
			editBox:SetFocus()
			editBox:HighlightText()
		end,
	}
	StaticPopup_Show(dialogKey)
end

function ProfessionExporter:GetAuctionPanelActiveTab(defaultTab)
	self.ui = self.ui or {}
	local tab = tostring(self.ui.auctionPanelActiveTab or defaultTab or "sell")
	if tab ~= "cart" then
		tab = "sell"
	end
	return tab
end

function ProfessionExporter:SetAuctionPanelActiveTab(tabId, manual)
	self.ui = self.ui or {}
	tabId = tostring(tabId or "sell")
	if tabId ~= "cart" then
		tabId = "sell"
	end
	self.ui.auctionPanelActiveTab = tabId
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
		string.format("itemID=%s qty=%s source=%s baseline=%s credit=%s", tostring(itemID), tostring(quantity), tostring(source or "?"), tostring(entry.baseline), tostring(entry.credit)),
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
	local currentCharacterKey = self:GetCharacterKey()
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
		if (tonumber(row.quantityToBuy) or 0) <= 0 then
			-- hide satisfied buy rows
		elseif text == "" then
			out[#out + 1] = row
		elseif containsText(row.itemName, text) or containsText(row.sourceText, text) or containsText(row.mailToText, text) or containsText(row.itemID, text) then
			out[#out + 1] = row
		end
	end
	return out
end

function ProfessionExporter:BuildAuctionCartColumns()
	return {
		{
			id = "item",
			label = "Item",
			width = 150,
			minWidth = 100,
			flex = 3,
			sortable = true,
			defaultSort = "asc",
			sortValue = function(row) return row and row.itemName end,
			createCell = function(rowFrame)
				local root = CreateFrame("Frame", nil, rowFrame)
				root:SetHeight(20)
				if root.SetClipsChildren then
					root:SetClipsChildren(true)
				end
				local icon = root:CreateTexture(nil, "ARTWORK")
				icon:SetSize(16, 16)
				icon:SetPoint("LEFT", root, "LEFT", 0, 0)
				local text = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
				text:SetPoint("RIGHT", root, "RIGHT", 0, 0)
				text:SetJustifyH("LEFT")
				text:SetWordWrap(false)
				return { root = root, icon = icon, text = text }
			end,
			updateCell = function(cell, row)
				cell.icon:SetTexture((row and row.itemIcon) or 134400)
				cell.text:SetText(row and row.itemName or "-")
			end,
		},
		{
			id = "quantityNeeded",
			label = "Need",
			width = 42,
			minWidth = 36,
			flex = 0,
			sortable = true,
			defaultSort = "desc",
			sortValue = function(row) return tonumber(row and row.quantityNeeded) or 0 end,
			getText = function(row) return self:FormatNumberGrouped(row and row.quantityNeeded or 0) end,
		},
		{
			id = "quantityHave",
			label = "Have",
			width = 42,
			minWidth = 36,
			flex = 0,
			sortable = true,
			defaultSort = "desc",
			sortValue = function(row) return tonumber(row and (row.quantityOnCharacter or row.quantityHave)) or 0 end,
			getText = function(row) return self:FormatNumberGrouped(row and (row.quantityOnCharacter or row.quantityHave) or 0) end,
		},
		{
			id = "quantityToBuy",
			label = "Buy",
			width = 42,
			minWidth = 36,
			flex = 0,
			sortable = true,
			defaultSort = "desc",
			sortValue = function(row) return tonumber(row and row.quantityToBuy) or 0 end,
			getText = function(row) return self:FormatNumberGrouped(row and row.quantityToBuy or 0) end,
		},
		{
			id = "estimatedUnitPrice",
			label = "Est",
			width = 58,
			minWidth = 48,
			flex = 0,
			sortable = true,
			defaultSort = "desc",
			sortValue = function(row) return tonumber(row and row.estimatedUnitPrice) or -1 end,
			getText = function(row) return row and row.estimatedUnitPrice and self:FormatCopperShort(row.estimatedUnitPrice) or "-" end,
		},
		{
			id = "currentPrice",
			label = "Live",
			width = 58,
			minWidth = 48,
			flex = 0,
			sortable = true,
			defaultSort = "desc",
			sortValue = function(row) return tonumber(row and row.currentPrice) or -1 end,
			getText = function(row) return row and row.currentPrice and self:FormatCopperShort(row.currentPrice) or "-" end,
		},
		{
			id = "estimatedBuyCost",
			label = "Cost",
			width = 64,
			minWidth = 52,
			flex = 0,
			sortable = true,
			defaultSort = "desc",
			sortValue = function(row) return tonumber(row and row.estimatedBuyCost) or -1 end,
			getText = function(row) return row and row.estimatedBuyCost and self:FormatCopperShort(row.estimatedBuyCost) or "-" end,
		},
		{
			id = "mailToText",
			label = "Mail to",
			width = 90,
			minWidth = 60,
			flex = 1,
			sortable = true,
			defaultSort = "asc",
			sortValue = function(row) return row and row.mailToText end,
			getText = function(row) return row and row.mailToText or "-" end,
		},
		{
			id = "sourceText",
			label = "Sources",
			width = 110,
			minWidth = 70,
			flex = 2,
			sortable = true,
			defaultSort = "asc",
			sortValue = function(row) return row and row.sourceText end,
			getText = function(row) return row and row.sourceText or "-" end,
		},
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
		ah.CommoditiesBuyFrame and ah.CommoditiesBuyFrame.BuyDisplay and ah.CommoditiesBuyFrame.BuyDisplay.QuantityInput and ah.CommoditiesBuyFrame.BuyDisplay.QuantityInput.InputBox,
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

function ProfessionExporter:EnsureAuctionHousePanel()
	self.ui = self.ui or {}
	local ui = self.ui
	local frameName = addonName .. "AuctionPanel"
	if ui.auctionPanel and ui.auctionPanel:IsObjectType("Frame") then
		if isAuctionHousePanelReady(ui.auctionPanel) then
			self:HideExtraAuctionHousePanels(ui.auctionPanel)
			return ui.auctionPanel
		end
		ui.auctionPanel = nil
	end
	local existing = _G[frameName]
	if existing and existing.IsObjectType and existing:IsObjectType("Frame") then
		if isAuctionHousePanelReady(existing) then
			ui.auctionPanel = existing
			self:HideExtraAuctionHousePanels(existing)
			return existing
		end
		existing:Hide()
		existing:SetParent(nil)
		_G[frameName] = nil
	end
	local ah = self:GetAuctionHouseAnchorFrame()
	if not ah then
		return nil
	end
	local helperPanel = _G["AuctionHelper_AuctionDataAuctionPanel"]
	if helperPanel and helperPanel.IsObjectType and helperPanel:IsObjectType("Frame") and frameName ~= "AuctionHelper_AuctionDataAuctionPanel" then
		ui.auctionPanel = helperPanel
		self:HideExtraAuctionHousePanels(helperPanel)
		return helperPanel
	end
	local template = BackdropTemplateMixin and "BackdropTemplate" or nil
	local panel = template and CreateFrame("Frame", frameName, ah, template) or CreateFrame("Frame", frameName, ah)
	if isAuctionHousePanelReady(panel) then
		ui.auctionPanel = panel
		self:HideExtraAuctionHousePanels(panel)
		return panel
	end
	if panel.__ahAuctionPanelInitInProgress then
		ui.auctionPanel = panel
		return panel
	end
	if panel.GetNumChildren and panel:GetNumChildren() > 0 then
		wipeFrameChildren(panel)
	end
	panel.__ahAuctionPanelInitInProgress = true
	panel:SetSize(500, 500)
	panel:SetPoint("TOPLEFT", ah, "TOPRIGHT", 8, -20)
	panel:SetPoint("BOTTOMLEFT", ah, "BOTTOMRIGHT", 8, 16)
	panel:SetResizable(true)
	if panel.SetResizeBounds then
		panel:SetResizeBounds(380, 320, 760, 900)
	elseif panel.SetMinResize and panel.SetMaxResize then
		panel:SetMinResize(380, 320)
		panel:SetMaxResize(760, 900)
	end
	self:StylePanel(panel, "surface2")
	panel:Hide()

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -10)
	title:SetPoint("TOPRIGHT", -10, -10)
	title:SetJustifyH("LEFT")
	title:SetText("AuctionHelper AH")
	panel.title = title

	local tabSell = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	tabSell:SetSize(64, 20)
	tabSell:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -78, -8)
	tabSell:SetText("Sell")
	tabSell:SetScript("OnClick", function()
		ProfessionExporter:SetAuctionPanelActiveTab("sell", true)
	end)
	panel.tabSell = tabSell

	local tabCart = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	tabCart:SetSize(92, 20)
	tabCart:SetPoint("RIGHT", tabSell, "LEFT", -4, 0)
	tabCart:SetText("Shopping cart")
	tabCart:SetScript("OnClick", function()
		ProfessionExporter:SetAuctionPanelActiveTab("cart", true)
	end)
	panel.tabCart = tabCart

	local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	subtitle:SetPoint("TOPRIGHT", -10, -4)
	subtitle:SetJustifyH("LEFT")
	subtitle:SetText("Current character sellables")
	panel.subtitle = subtitle

	local stats = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	stats:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -8)
	stats:SetPoint("TOPRIGHT", -10, -8)
	stats:SetJustifyH("LEFT")
	stats:SetJustifyV("TOP")
	stats:SetWordWrap(true)
	panel.stats = stats

	local btnRefresh = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	btnRefresh:SetSize(86, 20)
	btnRefresh:SetPoint("TOPLEFT", stats, "BOTTOMLEFT", 0, -6)
	btnRefresh:SetText("Refresh")
	btnRefresh:SetScript("OnClick", function()
		if not ProfessionExporter:CanStartFullAuctionSideActions(true) then
			return
		end
		local ids = ProfessionExporter:BuildAuctionVisibleItemIDs()
		ProfessionExporter:QueueVisibleAuctionRefresh(ids)
		ProfessionExporter:RefreshAuctionHousePanel()
	end)

	local btnScanCraftPrices = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	btnScanCraftPrices:SetSize(60, 20)
	btnScanCraftPrices:SetPoint("LEFT", btnRefresh, "RIGHT", 4, 0)
	btnScanCraftPrices:SetText("Crafts")
	btnScanCraftPrices:SetScript("OnClick", function()
		ProfessionExporter:QueueAuctionEconomyScan({ crafts = true })
	end)
	attachSimpleTooltip(
		btnScanCraftPrices,
		"Scan crafts",
		"AH price lookups for outputs and reagents from learned recipes in your saved profession scan (/profexport scan). Refreshes craft/dashboard pricing when finished."
	)
	panel.btnScanCraftPrices = btnScanCraftPrices

	local btnScanAccountInv = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	btnScanAccountInv:SetSize(64, 20)
	btnScanAccountInv:SetPoint("LEFT", btnScanCraftPrices, "RIGHT", 4, 0)
	btnScanAccountInv:SetText("Account")
	btnScanAccountInv:SetScript("OnClick", function()
		ProfessionExporter:QueueAuctionEconomyScan({ accountInventory = true })
	end)
	attachSimpleTooltip(
		btnScanAccountInv,
		"Scan account inventory",
		"AH lookups for item IDs that appear in any character snapshot with stock > 0, excluding items whose static bind type is BoP / quest / account / warband-style (C_Item.GetItemInfo). Does not know if your specific stack is soulbound."
	)
	panel.btnScanAccountInv = btnScanAccountInv

	local btnScanCraftAndAccount = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	btnScanCraftAndAccount:SetSize(46, 20)
	btnScanCraftAndAccount:SetPoint("LEFT", btnScanAccountInv, "RIGHT", 4, 0)
	btnScanCraftAndAccount:SetText("Both")
	btnScanCraftAndAccount:SetScript("OnClick", function()
		ProfessionExporter:QueueAuctionEconomyScan({ crafts = true, accountInventory = true })
	end)
	attachSimpleTooltip(
		btnScanCraftAndAccount,
		"Scan crafts + account",
		"Runs craft economy targets and tradable account inventory targets in one queue (duplicates deduped)."
	)
	panel.btnScanCraftAndAccount = btnScanCraftAndAccount

	local btnDump = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	btnDump:SetSize(62, 20)
	btnDump:SetPoint("LEFT", btnScanCraftAndAccount, "RIGHT", 4, 0)
	btnDump:SetText("Dump")
	btnDump:SetScript("OnClick", function()
		if not ProfessionExporter:CanStartFullAuctionSideActions(true) then
			return
		end
		ProfessionExporter:StartAuctionDump("visible")
		ProfessionExporter:RefreshAuctionHousePanel()
	end)
	panel.btnDumpVisible = btnDump

	local btnDumpFull = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	btnDumpFull:SetSize(72, 20)
	btnDumpFull:SetPoint("LEFT", btnDump, "RIGHT", 4, 0)
	btnDumpFull:SetText("Full dump")
	btnDumpFull:SetScript("OnClick", function()
		ProfessionExporter:StartAuctionDump("full")
		ProfessionExporter:RefreshAuctionHousePanel()
	end)
	attachSimpleTooltip(
		btnDumpFull,
		"Dump Full AH",
		"Runs a full replicate scan of the auction house, stores per-item snapshots, and records market history."
	)
	panel.btnDumpFull = btnDumpFull

	local btnPostProfitable = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	btnPostProfitable:SetSize(96, 20)
	btnPostProfitable:SetPoint("TOPLEFT", btnRefresh, "BOTTOMLEFT", 0, -4)
	btnPostProfitable:SetText("Post profit")
	btnPostProfitable:SetScript("OnClick", function()
		ProfessionExporter:RunAuctionPanelBulkAction("post_profitable")
	end)
	attachSimpleTooltip(
		btnPostProfitable,
		"Post profitable",
		"Posts visible rows where ROI is positive and price is not flagged as dumped unusually low."
	)
	panel.btnPostProfitable = btnPostProfitable

	local btnPostAll = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	btnPostAll:SetSize(68, 20)
	btnPostAll:SetPoint("LEFT", btnPostProfitable, "RIGHT", 4, 0)
	btnPostAll:SetText("Post all")
	btnPostAll:SetScript("OnClick", function()
		ProfessionExporter:RunAuctionPanelBulkAction("post_all")
	end)
	attachSimpleTooltip(
		btnPostAll,
		"Post all",
		"Attempts to post all visible rows, including low-margin items and items flagged as dumped low."
	)
	panel.btnPostAll = btnPostAll

	local btnPauseBulk = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	btnPauseBulk:SetSize(58, 20)
	btnPauseBulk:SetPoint("LEFT", btnPostAll, "RIGHT", 4, 0)
	btnPauseBulk:SetText("Pause")
	btnPauseBulk:SetScript("OnClick", function()
		ProfessionExporter:ToggleAuctionBulkPause()
	end)
	attachSimpleTooltip(
		btnPauseBulk,
		"Pause / Resume",
		"Pauses or resumes the current bulk post worker without clearing its queue position."
	)
	btnPauseBulk:Hide()
	panel.btnPauseBulk = btnPauseBulk

	local btnIgnoreItem = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	btnIgnoreItem:SetSize(58, 20)
	btnIgnoreItem:SetPoint("LEFT", btnPauseBulk, "RIGHT", 4, 0)
	btnIgnoreItem:SetText("Ignore")
	btnIgnoreItem:SetScript("OnClick", function()
		local itemID = ProfessionExporter:GetSelectedAuctionPanelItemID()
		if not itemID then
			ProfessionExporter:PrintMessage("Select an auction row first.")
			return
		end
		local rule = ProfessionExporter:GetAuctionItemRule(itemID) or {}
		ProfessionExporter:SetAuctionItemRule(itemID, { ignore = rule.ignore == true and nil or true })
		ProfessionExporter:DebugLog("AH", "rule ignore toggled", {
			string.format("itemID=%d ignore=%s", itemID, tostring(not (rule.ignore == true))),
		})
		ProfessionExporter:PrimeAuctionPanelRows()
		ProfessionExporter:RefreshAuctionHousePanel()
	end)
	attachSimpleTooltip(
		btnIgnoreItem,
		"Ignore Item",
		"Prevents the selected item from being included in bulk posting."
	)
	panel.btnIgnoreItem = btnIgnoreItem

	local btnReserveItem = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	btnReserveItem:SetSize(58, 20)
	btnReserveItem:SetPoint("LEFT", btnIgnoreItem, "RIGHT", 4, 0)
	btnReserveItem:SetText("Keep...")
	btnReserveItem:SetScript("OnClick", function()
		ProfessionExporter:ShowAuctionReservePrompt(ProfessionExporter:GetSelectedAuctionPanelItemID())
	end)
	attachSimpleTooltip(
		btnReserveItem,
		"Keep Amount",
		"Sets a reserve quantity for the selected item so bulk posting will not use its first stack if that would drop you below the reserve."
	)
	panel.btnReserveItem = btnReserveItem

	local btnClearRule = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	btnClearRule:SetSize(58, 20)
	btnClearRule:SetPoint("LEFT", btnReserveItem, "RIGHT", 4, 0)
	btnClearRule:SetText("Clear")
	btnClearRule:SetScript("OnClick", function()
		local itemID = ProfessionExporter:GetSelectedAuctionPanelItemID()
		if not itemID then
			ProfessionExporter:PrintMessage("Select an auction row first.")
			return
		end
		ProfessionExporter:ClearAuctionItemRule(itemID)
		ProfessionExporter:DebugLog("AH", "rule cleared", {
			string.format("itemID=%d", itemID),
		})
		ProfessionExporter:PrimeAuctionPanelRows()
		ProfessionExporter:RefreshAuctionHousePanel()
	end)
	attachSimpleTooltip(
		btnClearRule,
		"Clear Rule",
		"Removes ignore and keep rules from the selected item."
	)
	panel.btnClearRule = btnClearRule

	local search = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
	search:SetSize(118, 20)
	search:SetAutoFocus(false)
	search:SetPoint("TOPLEFT", btnPostProfitable, "BOTTOMLEFT", 6, -8)
	search:SetScript("OnTextChanged", function(box)
		ui.ahFilterText = box:GetText() or ""
		ProfessionExporter:RefreshAuctionHousePanel()
	end)
	panel.searchBox = search

	local craftedOnly = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	craftedOnly:SetPoint("LEFT", search, "RIGHT", 6, -1)
	local craftedLabel = craftedOnly.Text or (craftedOnly.GetName and craftedOnly:GetName() and _G[craftedOnly:GetName() .. "Text"]) or nil
	if craftedLabel then
		craftedLabel:SetText("Craft")
	end
	craftedOnly:SetScript("OnClick", function(btn)
		ui.ahCraftedOnly = btn:GetChecked() == true
		ProfessionExporter:RefreshAuctionHousePanel()
	end)
	panel.craftedOnly = craftedOnly

	local profitableOnly = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	profitableOnly:SetPoint("LEFT", craftedOnly, "RIGHT", 54, 0)
	local profitableLabel = profitableOnly.Text or (profitableOnly.GetName and profitableOnly:GetName() and _G[profitableOnly:GetName() .. "Text"]) or nil
	if profitableLabel then
		profitableLabel:SetText("Profit")
	end
	profitableOnly:SetScript("OnClick", function(btn)
		ui.ahProfitableOnly = btn:GetChecked() == true
		ProfessionExporter:RefreshAuctionHousePanel()
	end)
	panel.profitableOnly = profitableOnly

	ui.ahClassDropdown = self:CreateMultiSelectDropdown(panel, {
		label = "Class",
		allLabel = "All classes",
		width = 114,
		getSelection = function()
			return ui.ahClassFilterValues or {}
		end,
		setSelection = function(selection)
			ui.ahClassFilterValues = selection or {}
		end,
		onChanged = function()
			ui.ahSubclassFilterValues = {}
			ProfessionExporter:RefreshAuctionHousePanel()
		end,
	})
	ui.ahClassDropdown:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -8)
	panel.classDropdown = ui.ahClassDropdown

	ui.ahSubclassDropdown = self:CreateMultiSelectDropdown(panel, {
		label = "Subclass",
		allLabel = "All subclasses",
		width = 114,
		getSelection = function()
			return ui.ahSubclassFilterValues or {}
		end,
		setSelection = function(selection)
			ui.ahSubclassFilterValues = selection or {}
		end,
		onChanged = function()
			ProfessionExporter:RefreshAuctionHousePanel()
		end,
	})
	ui.ahSubclassDropdown:SetPoint("TOPLEFT", ui.ahClassDropdown, "TOPRIGHT", 4, 0)
	panel.subclassDropdown = ui.ahSubclassDropdown

	local function ahCopyBoolMap(t)
		local out = {}
		if type(t) == "table" then
			for k, v in pairs(t) do
				if v then
					out[k] = true
				end
			end
		end
		return out
	end
	ui.ahExpansionFilterValues = ahCopyBoolMap(self:GetSetting("auction.selectedExpansions", {}))

	ui.ahExpansionDropdown = self:CreateMultiSelectDropdown(panel, {
		label = "Expansion",
		width = 114,
		allLabel = "All expansions",
		getOptions = function()
			return ProfessionExporter:GetExpansionFilterOptions()
		end,
		getSelection = function()
			return ui.ahExpansionFilterValues or {}
		end,
		setSelection = function(selection)
			ui.ahExpansionFilterValues = selection or {}
			ProfessionExporter:SetSetting("auction.selectedExpansions", selection)
		end,
		onChanged = function()
			ProfessionExporter:RefreshAuctionHousePanel()
		end,
	})
	ui.ahExpansionDropdown:SetPoint("TOPLEFT", ui.ahSubclassDropdown, "TOPRIGHT", 4, 0)
	panel.expansionDropdown = ui.ahExpansionDropdown

	local clearBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	clearBtn:SetSize(52, 18)
	clearBtn:SetPoint("LEFT", profitableOnly, "RIGHT", 48, 0)
	clearBtn:SetText("Clear")
	clearBtn:SetScript("OnClick", function()
		ui.ahFilterText = ""
		ui.ahCraftedOnly = false
		ui.ahProfitableOnly = false
		ui.ahClassFilterValues = {}
		ui.ahSubclassFilterValues = {}
		ui.ahExpansionFilterValues = {}
		panel.searchBox:SetText("")
		panel.craftedOnly:SetChecked(false)
		panel.profitableOnly:SetChecked(false)
		ProfessionExporter:SetSetting("auction.selectedExpansions", {})
		if ui.ahClassDropdown then
			ui.ahClassDropdown:RefreshText()
		end
		if ui.ahSubclassDropdown then
			ui.ahSubclassDropdown:RefreshText()
		end
		if ui.ahExpansionDropdown then
			ui.ahExpansionDropdown:RefreshText()
		end
		ProfessionExporter:RefreshAuctionHousePanel()
	end)
	panel.clearBtn = clearBtn

	panel.tableHost = CreateFrame("Frame", nil, panel)
	panel.tableHost:SetPoint("TOPLEFT", ui.ahClassDropdown, "BOTTOMLEFT", -2, -8)
	panel.tableHost:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 52)
	ui.ahSortKey = ui.ahSortKey or "potentialROI"
	if ui.ahSortAsc == nil then
		ui.ahSortAsc = false
	end
	if ui.ahFilterText == nil then
		ui.ahFilterText = ""
	end
	if ui.ahCraftedOnly == nil then
		ui.ahCraftedOnly = false
	end
	if ui.ahProfitableOnly == nil then
		ui.ahProfitableOnly = false
	end
	ui.ahClassFilterValues = ui.ahClassFilterValues or {}
	ui.ahSubclassFilterValues = ui.ahSubclassFilterValues or {}
	ui.ahExpansionFilterValues = ui.ahExpansionFilterValues or {}
	panel.table = self:CreateReusableTable(panel.tableHost, {
		rowHeight = 20,
		maxRows = 120,
		sortKey = ui.ahSortKey,
		sortAsc = ui.ahSortAsc,
		onSortChanged = function(sortKey, sortAsc)
			ui.ahSortKey = sortKey
			ui.ahSortAsc = sortAsc
		end,
		onRowEnter = function(_, rowData)
			local itemID = rowData and rowData.itemID
			if not itemID then
				return
			end
			GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
			if GameTooltip.SetItemByID then
				GameTooltip:SetItemByID(itemID)
			else
				GameTooltip:SetText("#" .. tostring(itemID))
			end
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(string.format("Owned: %s", ProfessionExporter:FormatNumberGrouped(tonumber(rowData.quantityOwned) or 0)), 0.82, 0.88, 0.96)
			if rowData.isIgnoredByRule then
				GameTooltip:AddLine("Rule: ignored for bulk posting", 1.0, 0.4, 0.4)
			elseif (tonumber(rowData.reserveQty) or 0) > 0 then
				GameTooltip:AddLine(string.format("Rule: keep at least %s (sellable now: %s)", ProfessionExporter:FormatNumberGrouped(tonumber(rowData.reserveQty) or 0), ProfessionExporter:FormatNumberGrouped(tonumber(rowData.quantitySellable) or 0)), 0.82, 0.88, 0.96)
				if rowData.canBulkPost ~= true then
					GameTooltip:AddLine("Bulk posting will skip this item because the first stack would violate the reserve.", 1.0, 0.82, 0.3, true)
				end
			end
			GameTooltip:AddLine(string.format("Shown price: %s", rowData.currentPrice and ProfessionExporter:FormatCopperShort(rowData.currentPrice) or "-"), 0.82, 0.88, 0.96)
			GameTooltip:AddLine(string.format("Shown source: %s", tostring(rowData.currentPriceSource or "unknown")), 0.82, 0.88, 0.96)
			if tonumber(rowData.currentPriceSeenAt) then
				GameTooltip:AddLine(string.format("Seen: %s", date("%H:%M:%S", tonumber(rowData.currentPriceSeenAt))), 0.82, 0.88, 0.96)
			end
			if rowData.nativePrice and rowData.nativePrice > 0 then
				GameTooltip:AddLine(string.format("Live lowest buyout: %s", ProfessionExporter:FormatCopperShort(rowData.nativePrice)), 0.65, 0.9, 0.7)
			else
				GameTooltip:AddLine("Live lowest buyout: unavailable", 1.0, 0.82, 0.3)
			end
			if rowData.fallbackPrice and rowData.fallbackPrice > 0 then
				GameTooltip:AddLine(string.format("Fallback price: %s (%s)", ProfessionExporter:FormatCopperShort(rowData.fallbackPrice), tostring(rowData.fallbackPriceSource or "fallback")), 0.82, 0.88, 0.96, true)
			end
			GameTooltip:AddLine(string.format("ROI: %s", formatPercent(rowData.potentialROI)), 0.82, 0.88, 0.96)
			GameTooltip:AddLine(string.format("Personal SR: %s", rowData.personalSaleRateDisplay or "-"), 0.82, 0.88, 0.96)
			if rowData.isDumpedLow then
				GameTooltip:AddLine("Warning: price appears dumped unusually low.", 1.0, 0.35, 0.35, true)
			end
			GameTooltip:AddLine("Click row to select item in AH sell frame.", 0.75, 0.82, 0.9)
			GameTooltip:Show()
		end,
		onRowLeave = function()
			GameTooltip:Hide()
		end,
		onRowClick = function(_, rowData)
			local id = rowData and rowData.itemID
			if not id then
				return
			end
			-- Clicking a row should also revalidate this item's current market value.
			if ProfessionExporter:CanStartFullAuctionSideActions(true) then
				ProfessionExporter:QueueVisibleAuctionRefresh({ id })
			end
			local ok = ProfessionExporter:TrySendItemToAuctionSellFrame(id, rowData and rowData.firstBag, rowData and rowData.firstSlot)
			if ok then
				ProfessionExporter:GetState().auctionPanelSelectedItemID = id
				ProfessionExporter:GetState().auctionLastSellSelectionItemID = id
				ProfessionExporter:RefreshAuctionPanelRules()
				ProfessionExporter:PrintMessage(string.format("Selected %s for AH sell.", ProfessionExporter:GetItemDisplayName(id)))
			else
				ProfessionExporter:GetState().auctionPanelSelectedItemID = id
				ProfessionExporter:RefreshAuctionPanelRules()
				ProfessionExporter:PrintMessage("Could not auto-select item in Sell frame (UI variant/focus mismatch).")
			end
		end,
	})
	if panel.table and panel.table.frame then
		panel.table.frame:ClearAllPoints()
		panel.table.frame:SetPoint("TOPLEFT", panel.tableHost, "TOPLEFT", 0, 0)
		panel.table.frame:SetPoint("BOTTOMRIGHT", panel.tableHost, "BOTTOMRIGHT", 0, 0)
	end
	panel.table:SetColumns(self:BuildAuctionPanelColumns())
	panel.searchBox:SetText(ui.ahFilterText or "")
	panel.craftedOnly:SetChecked(ui.ahCraftedOnly == true)
	panel.profitableOnly:SetChecked(ui.ahProfitableOnly == true)
	panel.classDropdown:RefreshText()
	panel.subclassDropdown:RefreshText()
	if panel.expansionDropdown then
		panel.expansionDropdown:RefreshText()
	end
	self:RefreshAuctionPanelRules()

	panel.progressText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.progressText:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 44)
	panel.progressText:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 44)
	panel.progressText:SetJustifyH("LEFT")
	panel.progressText:SetText("Idle")

	panel.progressBar = CreateFrame("StatusBar", nil, panel)
	panel.progressBar:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 24)
	panel.progressBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 24)
	panel.progressBar:SetHeight(14)
	panel.progressBar:SetStatusBarTexture("Interface/TARGETINGFRAME/UI-StatusBar")
	panel.progressBar:SetMinMaxValues(0, 1)
	panel.progressBar:SetValue(0)
	panel.progressBar:SetStatusBarColor(0.30, 0.70, 0.95)
	local bg = panel.progressBar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.12, 0.12, 0.14, 1)
	panel.progressBarBg = bg

	panel.btnPauseScan = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	panel.btnPauseScan:SetSize(64, 18)
	panel.btnPauseScan:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 4)
	panel.btnPauseScan:SetText("Pause")
	panel.btnPauseScan:SetScript("OnClick", function()
		ProfessionExporter:ToggleAuctionRefreshPause()
	end)
	attachSimpleTooltip(
		panel.btnPauseScan,
		"Pause / Resume Scan",
		"Pauses or resumes the queued auction price scan without clearing its progress."
	)
	panel.btnPauseScan:Hide()

	panel.progressTiming = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	panel.progressTiming:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 6)
	panel.progressTiming:SetPoint("BOTTOMRIGHT", panel.btnPauseScan, "BOTTOMLEFT", -8, 0)
	panel.progressTiming:SetJustifyH("LEFT")
	panel.progressTiming:SetText("")
	panel.progressTiming:Hide()

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

	panel.btnCartSearch = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	panel.btnCartSearch:SetSize(58, 20)
	panel.btnCartSearch:SetPoint("LEFT", panel.cartSearchBox, "RIGHT", 4, 0)
	panel.btnCartSearch:SetText("Search")
	panel.btnCartSearch:SetScript("OnClick", function()
		local rows = panel.cartTable and panel.cartTable.rows or nil
		local selected = ProfessionExporter:GetState().auctionCartSelectedItemID
		if selected then
			ProfessionExporter:SearchAuctionCartRow({ itemID = selected })
		elseif type(rows) == "table" and #rows > 0 then
			ProfessionExporter:SearchAuctionCartRow(rows[1])
		end
	end)
	panel.btnCartSearch:Hide()
	attachSimpleTooltip(panel.btnCartSearch, "Search selected", "Runs an AH search for the selected shopping-cart row and refreshes the live price.")

	panel.btnCartRefresh = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	panel.btnCartRefresh:SetSize(64, 20)
	panel.btnCartRefresh:SetPoint("LEFT", panel.btnCartSearch, "RIGHT", 4, 0)
	panel.btnCartRefresh:SetText("Scan all")
	panel.btnCartRefresh:SetScript("OnClick", function()
		local rows = ProfessionExporter:FilterAuctionCraftCartRows(select(1, ProfessionExporter:BuildAuctionCraftCartRows()))
		ProfessionExporter:SearchAuctionCartRows(rows)
	end)
	panel.btnCartRefresh:Hide()
	attachSimpleTooltip(panel.btnCartRefresh, "Scan all cart rows", "Queues AH searches for all shopping-cart rows that still need to be bought.")

	panel.btnCartBuy = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	panel.btnCartBuy:SetSize(86, 20)
	panel.btnCartBuy:SetPoint("TOPLEFT", panel.cartSearchBox, "BOTTOMLEFT", 0, -6)
	panel.btnCartBuy:SetText("Buy cheapest")
	panel.btnCartBuy:SetScript("OnClick", function()
		local selected = ProfessionExporter:GetState().auctionCartSelectedItemID
		if not selected and panel.cartTable and panel.cartTable.rows then
			local rows = panel.cartTable.rows or {}
			selected = rows[1] and rows[1].itemID or nil
		end
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
	end)
	panel.btnCartBuy:Hide()
	attachSimpleTooltip(panel.btnCartBuy, "Buy cheapest", "Attempts a first-pass commodity purchase for the selected shopping-cart row using the current cheapest live result.")

	panel.btnCartRemove = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	panel.btnCartRemove:SetSize(70, 20)
	panel.btnCartRemove:SetPoint("LEFT", panel.btnCartBuy, "RIGHT", 4, 0)
	panel.btnCartRemove:SetText("Remove")
	panel.btnCartRemove:SetScript("OnClick", function()
		local selected = ProfessionExporter:GetState().auctionCartSelectedItemID
		if not selected then
			ProfessionExporter:PrintMessage("Select a shopping-cart row first.")
			return
		end
		local removedCrafts = ProfessionExporter.RemoveCraftQueueLinesByReagentItem and ProfessionExporter:RemoveCraftQueueLinesByReagentItem(selected) or 0
		local removedOrders = ProfessionExporter.RemoveCraftingOrdersByReagentItem and ProfessionExporter:RemoveCraftingOrdersByReagentItem(selected) or 0
		if (removedCrafts + removedOrders) > 0 then
			ProfessionExporter:PrintMessage(string.format("Removed %d craft queue entries and %d crafting orders for item #%s.", removedCrafts, removedOrders, tostring(selected)))
		else
			ProfessionExporter:PrintMessage("No shopping-cart sources were removed for the selected item.")
		end
		ProfessionExporter:GetState().auctionCartSelectedItemID = nil
		ProfessionExporter:RefreshAuctionHousePanel()
	end)
	panel.btnCartRemove:Hide()
	attachSimpleTooltip(panel.btnCartRemove, "Remove selected item", "Removes queued crafts and queued crafting orders that contribute to the selected shopping-cart item.")

	panel.btnCartClear = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	panel.btnCartClear:SetSize(56, 20)
	panel.btnCartClear:SetPoint("LEFT", panel.btnCartRemove, "RIGHT", 4, 0)
	panel.btnCartClear:SetText("Clear")
	panel.btnCartClear:SetScript("OnClick", function()
		if ProfessionExporter.ClearCraftQueue then
			ProfessionExporter:ClearCraftQueue()
		end
		if ProfessionExporter.ClearCraftingOrderWorkQueue then
			ProfessionExporter:ClearCraftingOrderWorkQueue()
		end
		ProfessionExporter:GetState().auctionCartSelectedItemID = nil
		ProfessionExporter:PrintMessage("Cleared shopping-cart sources.")
		ProfessionExporter:RefreshAuctionHousePanel()
	end)
	panel.btnCartClear:Hide()
	attachSimpleTooltip(panel.btnCartClear, "Clear shopping cart", "Clears queued crafts and queued crafting orders that feed the shopping cart.")

	panel.cartTableHost = CreateFrame("Frame", nil, panel)
	panel.cartTableHost:SetPoint("TOPLEFT", panel.btnCartBuy, "BOTTOMLEFT", 0, -8)
	panel.cartTableHost:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 52)
	panel.cartTableHost:Hide()
	panel.cartTable = self:CreateReusableTable(panel.cartTableHost, {
		rowHeight = 20,
		maxRows = 120,
		sortKey = "quantityToBuy",
		sortAsc = false,
		autoFitToScroll = true,
		onRowEnter = function(_, rowData)
			local itemID = rowData and rowData.itemID
			if not itemID then
				return
			end
			GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
			if GameTooltip.SetItemByID then
				GameTooltip:SetItemByID(itemID)
			else
				GameTooltip:SetText("#" .. tostring(itemID))
			end
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(string.format("Need %s  |  Have %s  |  Buy %s", ProfessionExporter:FormatNumberGrouped(rowData.quantityNeeded or 0), ProfessionExporter:FormatNumberGrouped(rowData.quantityHave or 0), ProfessionExporter:FormatNumberGrouped(rowData.quantityToBuy or 0)), 0.82, 0.88, 0.96)
			if rowData.mailToText and rowData.mailToText ~= "—" and rowData.mailToText ~= "" then
				GameTooltip:AddLine(string.format("Mail to: %s", tostring(rowData.mailToText)), 0.82, 0.88, 0.96, true)
			end
			if type(rowData.mailAllocations) == "table" then
				for _, alloc in ipairs(rowData.mailAllocations) do
					local label = alloc.characterKey
					if ProfessionExporter.GetDashboardSidebarCharacterLabel then
						label = ProfessionExporter:GetDashboardSidebarCharacterLabel(alloc.characterKey, nil, ProfessionExporter:GetCharacterKey())
					end
					GameTooltip:AddLine(string.format("  %s: need %s, have %s, mail %s", label, ProfessionExporter:FormatNumberGrouped(alloc.quantityNeeded or 0), ProfessionExporter:FormatNumberGrouped(alloc.quantityHave or 0), ProfessionExporter:FormatNumberGrouped(alloc.mailQuantity or 0)), 0.75, 0.82, 0.9)
				end
			end
			GameTooltip:AddLine(string.format("Planned crafts: %s", tostring(rowData.sourceText or "—")), 0.82, 0.88, 0.96, true)
			if rowData.currentPrice then
				GameTooltip:AddLine(string.format("Live AH: %s (%s)", ProfessionExporter:FormatCopperShort(rowData.currentPrice), tostring(rowData.currentPriceSource or "?")), 0.65, 0.9, 0.7)
			end
			if rowData.estimatedBuyCost then
				GameTooltip:AddLine(string.format("Estimated buy cost: %s", ProfessionExporter:FormatCopperShort(rowData.estimatedBuyCost)), 0.82, 0.88, 0.96)
			end
			GameTooltip:AddLine("Click row to select. Use Search to refresh the AH listing and Buy cheapest for commodity reagents.", 0.75, 0.82, 0.9, true)
			GameTooltip:Show()
		end,
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

	panel.sellControls = {
		btnRefresh,
		btnScanCraftPrices,
		btnScanAccountInv,
		btnScanCraftAndAccount,
		btnDump,
		btnDumpFull,
		btnPostProfitable,
		btnPostAll,
		btnPauseBulk,
		btnIgnoreItem,
		btnReserveItem,
		btnClearRule,
		search,
		craftedOnly,
		profitableOnly,
		ui.ahClassDropdown,
		ui.ahSubclassDropdown,
		ui.ahExpansionDropdown,
		clearBtn,
		panel.tableHost,
		panel.table and panel.table.frame or nil,
	}

	panel.resizeHandle = CreateFrame("Button", nil, panel)
	panel.resizeHandle:SetSize(18, 18)
	panel.resizeHandle:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 6)
	panel.resizeHandle:SetNormalTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
	panel.resizeHandle:SetHighlightTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Highlight")
	panel.resizeHandle:SetPushedTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Down")
	panel.resizeHandle:RegisterForDrag("LeftButton")
	panel.resizeHandle:SetScript("OnDragStart", function()
		panel:StartSizing("BOTTOMRIGHT")
	end)
	panel.resizeHandle:SetScript("OnDragStop", function()
		panel:StopMovingOrSizing()
	end)
	attachSimpleTooltip(panel.resizeHandle, "Resize", "Drag to resize the auction side panel.")

	panel.__ahAuctionPanelInitInProgress = nil
	panel.__ahAuctionPanelInitialized = true
	ui.auctionPanel = panel
	self:HideExtraAuctionHousePanels(panel)
	return panel
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

function ProfessionExporter:BuildAuctionPanelColumns()
	return {
		{
			id = "itemRecipe",
			label = "Item / Recipe",
			width = 136,
			sortable = true,
			defaultSort = "asc",
			sortValue = function(row) return row and row.itemName end,
			createCell = function(rowFrame)
				local root = CreateFrame("Frame", nil, rowFrame)
				root:SetHeight(20)
				local icon = root:CreateTexture(nil, "ARTWORK")
				icon:SetSize(16, 16)
				icon:SetPoint("LEFT", root, "LEFT", 0, 0)
				local rankIcon = root:CreateTexture(nil, "OVERLAY")
				rankIcon:SetSize(16, 16)
				rankIcon:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
				rankIcon:Hide()
				local rankText = root:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
				rankText:SetPoint("CENTER", rankIcon, "CENTER", 0, 0)
				rankText:SetTextColor(1, 1, 1)
				rankText:Hide()
				local text = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
				text:SetPoint("RIGHT", root, "RIGHT", 0, 0)
				text:SetJustifyH("LEFT")
				text:SetWordWrap(false)
				return { root = root, icon = icon, rankIcon = rankIcon, rankText = rankText, text = text }
			end,
			updateCell = function(cell, row)
				cell.icon:SetTexture((row and row.itemIcon) or 134400)
				applyRankBadge(cell.rankIcon, cell.rankText, row and row.qualityIndex)
				local scanMarker = (row and row._isScanning) and "[-] " or ""
				if row and row.recipeName and row.recipeName ~= "" then
					cell.text:SetText(string.format("%s%s (%s)", scanMarker, row.itemName or "?", row.recipeName))
				else
					cell.text:SetText(scanMarker .. (row and row.itemName or "-"))
				end
			end,
		},
		{
			id = "quantityOwned",
			label = "Qty",
			width = 52,
			sortable = true,
			defaultSort = "desc",
			sortValue = function(row) return tonumber(row and row.quantityOwned) or 0 end,
			getText = function(row)
				if not row then
					return "0"
				end
				local owned = self:FormatNumberGrouped((row and row.quantityOwned) or 0)
				local sellable = tonumber(row.quantitySellable) or 0
				if row.isIgnoredByRule then
					return "0/" .. owned
				end
				if (tonumber(row.reserveQty) or 0) > 0 then
					return self:FormatNumberGrouped(sellable) .. "/" .. owned
				end
				return owned
			end,
		},
		{
			id = "auctionRule",
			label = "Rule",
			width = 42,
			sortable = true,
			defaultSort = "desc",
			sortValue = function(row)
				if row and row.isIgnoredByRule then
					return 2
				end
				if (tonumber(row and row.reserveQty) or 0) > 0 then
					return 1
				end
				return 0
			end,
			getText = function(row) return row and row.auctionRuleLabel or "-" end,
		},
		{
			id = "currentPrice",
			label = "Price",
			width = 72,
			sortable = true,
			defaultSort = "desc",
			sortValue = function(row) return tonumber(row and row.currentPrice) or -1 end,
			getText = function(row)
				if not row or not row.currentPrice then
					return "-"
				end
				local text = self:FormatCopperShort(row.currentPrice)
				if row.currentPriceIsNative ~= true then
					text = text .. " *"
				end
				if row.isDumpedLow then
					return text .. " !"
				end
				return text
			end,
		},
		{
			id = "lastAuctionScan",
			label = "Scan",
			width = 68,
			sortable = true,
			defaultSort = "desc",
			sortValue = function(row) return tonumber(row and row.lastAuctionScanAtTs) or 0 end,
			getText = function(row) return row and row.auctionScanAgeDisplay or "never" end,
		},
		{
			id = "potentialROI",
			label = "ROI",
			width = 44,
			sortable = true,
			defaultSort = "desc",
			sortValue = function(row) return tonumber(row and row.potentialROI) or -9999 end,
			getText = function(row) return formatPercent(row and row.potentialROI) end,
		},
		{
			id = "personalSaleRate",
			label = "P-SR",
			width = 46,
			sortable = true,
			defaultSort = "desc",
			sortValue = function(row) return tonumber(row and row.personalSaleRateValue) or -1 end,
			getText = function(row) return row and row.personalSaleRateDisplay or "-" end,
		},
		{
			id = "dumpAlert",
			label = "Alert",
			width = 50,
			sortable = true,
			defaultSort = "desc",
			sortValue = function(row) return row and row.isDumpedLow and 1 or 0 end,
			getText = function(row) return (row and row.isDumpedLow) and "LOW" or "-" end,
		},
	}
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
	local itemSellFrame = ah and (ah.ItemSellFrame or (ah.CommoditiesSellFrame and ah.CommoditiesSellFrame.ItemSellFrame)) or nil
	local hasSetItemByLocation = itemSellFrame and type(itemSellFrame.SetItemByLocation) == "function" and true or false

	-- Retail path first: optional display-mode focus, then SetItemByLocation.
	if ah and hasSetItemByLocation and ItemLocation and ItemLocation.CreateFromBagAndSlot then
		if ah.SetDisplayMode then
			local modes = Enum and Enum.AuctionHouseFrameDisplayMode or _G.AuctionHouseFrameDisplayMode
			local sellMode = modes and (modes.ItemSell or modes.CommoditiesSell)
			if sellMode then
				pcall(ah.SetDisplayMode, ah, sellMode)
			end
		end
		local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
		if loc and ((not C_Item or not C_Item.DoesItemExist) or C_Item.DoesItemExist(loc)) then
			local ok = pcall(itemSellFrame.SetItemByLocation, itemSellFrame, loc)
			if ok then
				return true
			end
		end
	end

	-- Classic / Forever cursor inject. Do not use on true retail when SetItemByLocation exists
	-- (Blizzard sell frame can hard-error on stale cursor placements during auto-refresh).
	local shouldClassic = self.ForeverLogic
		and self.ForeverLogic.ShouldUseClassicSellInject
		and self.ForeverLogic.ShouldUseClassicSellInject(self.IS_FOREVER == true, hasSetItemByLocation)
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
		if button and button.IsShown and button:IsShown() and button.Click then
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
		buttonAttempts = 0,
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

function ProfessionExporter:RefreshAuctionHousePanel()
	local panel = self:EnsureAuctionHousePanel()
	if not panel then
		return
	end
	self:HideExtraAuctionHousePanels(panel)
	self:RefreshAuctionPanelRules()
	self.ui = self.ui or {}
	local ui = self.ui
	local theme = self.GetTheme and self:GetTheme() or nil
	if theme then
		setFontColor(panel.title, theme.textPrimary)
		setFontColor(panel.subtitle, theme.textMuted)
		if panel.cartSummary then
			setFontColor(panel.cartSummary, theme.textMuted)
		end
	end
	local refreshState = self:GetState()
	local cartRows, queueSummary = self:BuildAuctionCraftCartRows()
	local cartOutstanding = 0
	local cartQuantityToBuy = 0
	local cartEstimatedBuyCost = 0
	local cartEstimatedBuyCostKnown = true
	for _, row in ipairs(cartRows or {}) do
		if (tonumber(row.quantityToBuy) or 0) > 0 then
			cartOutstanding = cartOutstanding + 1
			cartQuantityToBuy = cartQuantityToBuy + (tonumber(row.quantityToBuy) or 0)
			if tonumber(row.estimatedBuyCost) then
				cartEstimatedBuyCost = cartEstimatedBuyCost + (tonumber(row.estimatedBuyCost) or 0)
			else
				cartEstimatedBuyCostKnown = false
			end
		end
	end
	local cartEstimatedBuyCostText = cartEstimatedBuyCost > 0 and self:FormatCopperShort(cartEstimatedBuyCost) or "—"
	if cartEstimatedBuyCost > 0 and not cartEstimatedBuyCostKnown then
		cartEstimatedBuyCostText = cartEstimatedBuyCostText .. "+"
	end
	if ui.auctionPanelTabManual ~= true then
		ui.auctionPanelActiveTab = cartOutstanding > 0 and "cart" or "sell"
	end
	local activeTab = self:GetAuctionPanelActiveTab(cartOutstanding > 0 and "cart" or "sell")
	local rows = refreshState.auctionPanelRows
	if type(rows) ~= "table" then
		rows = self:PrimeAuctionPanelRows() or {}
		refreshState.auctionPanelRows = rows
	end
	for _, row in ipairs(rows) do
		local roi = refreshState.auctionRoiCache and refreshState.auctionRoiCache[row.itemID] or nil
		row.potentialROI = roi and roi.potentialROI or nil
		row.recipeName = roi and roi.recipeName or nil
		row.qualityIndex = row.qualityIndex or (roi and roi.qualityIndex or nil)
		row._isScanning = tonumber(refreshState.auctionActiveItemID) == tonumber(row.itemID)
		local scanTs = self:GetItemLastAuctionScanAt(row.itemID)
		row.lastAuctionScanAtTs = scanTs
		row.auctionScanAgeDisplay = self:FormatAuctionScanAge(scanTs)
	end
	local preFilterCount = #rows
	local classOptions = self:GetAuctionClassFilterOptions(rows)
	ui.ahClassFilterValues = self:NormalizeFilterSelection(ui.ahClassFilterValues or {}, classOptions)
	if panel.classDropdown then
		panel.classDropdown:SetOptions(classOptions)
	end
	local subclassOptions = self:GetAuctionSubclassFilterOptions(rows, ui.ahClassFilterValues)
	ui.ahSubclassFilterValues = self:NormalizeFilterSelection(ui.ahSubclassFilterValues or {}, subclassOptions)
	if panel.subclassDropdown then
		panel.subclassDropdown:SetOptions(subclassOptions)
	end
	local expOpts = self:GetExpansionFilterOptions()
	ui.ahExpansionFilterValues = self:NormalizeFilterSelection(ui.ahExpansionFilterValues or {}, expOpts)
	if panel.expansionDropdown then
		panel.expansionDropdown:SetOptions(expOpts)
		panel.expansionDropdown:RefreshText()
	end
	rows = self:FilterAuctionPanelRows(rows)
	refreshState.auctionVisibleRows = rows
	local queuedCount = 0
	for _ in pairs(refreshState.auctionRefreshQueue or {}) do
		queuedCount = queuedCount + 1
	end
	local src = refreshState.auctionSourceCounts or {}
	local dumpState = refreshState.auctionDump
	local cooldownRemaining = self:GetFullAuctionDumpCooldownRemaining()
	local lastFullDumpLabel = (tonumber(refreshState.auctionLastFullDumpAt) and date("%H:%M:%S", tonumber(refreshState.auctionLastFullDumpAt))) or "never"
	local fullDumpStatus = "idle"
	if dumpState and dumpState.mode == "full" and dumpState.running == true then
		if dumpState.status == "requesting" then
			fullDumpStatus = "requesting replicate list"
		elseif dumpState.persistTotal and dumpState.persistTotal > 0 then
			fullDumpStatus = string.format(
				"persisting %s/%s",
				self:FormatNumberGrouped(math.min(tonumber(dumpState.persistDone) or 0, tonumber(dumpState.persistTotal) or 0)),
				self:FormatNumberGrouped(tonumber(dumpState.persistTotal) or 0)
			)
		else
			fullDumpStatus = string.format(
				"processing %s/%s",
				self:FormatNumberGrouped(math.min(tonumber(dumpState.done) or 0, tonumber(dumpState.total) or 0)),
				self:FormatNumberGrouped(tonumber(dumpState.total) or 0)
			)
		end
	elseif cooldownRemaining > 0 then
		fullDumpStatus = "cooldown " .. formatDurationShort(cooldownRemaining)
	end
	local loadingLine = "idle"
	if refreshState.auctionRefreshRunning then
		local sm = tostring(refreshState.auctionScanMode or "")
		if sm == "crafts" then
			loadingLine = "craft prices..."
		elseif sm == "account_inv" then
			loadingLine = "account inventory..."
		elseif sm == "mixed" then
			loadingLine = "crafts + account..."
		else
			loadingLine = "prices..."
		end
	elseif refreshState.auctionRoiRunning then
		loadingLine = "roi..."
	end
	local selID = self:GetSelectedAuctionPanelItemID()
	local selScanLabel = selID and self:FormatAuctionScanAge(self:GetItemLastAuctionScanAt(selID)) or "n/a"
	if activeTab ~= "cart" then
		panel.subtitle:SetText("Current character sellables")
		panel.stats:SetText(string.format(
			"Rows %d/%d  |  Queue %d  |  Load %s  |  Src N/F %d/%d\nLast queue %s  |  Selected %s  |  Full dump %s  |  Last full %s",
			#rows,
			preFilterCount,
			queuedCount,
			loadingLine,
			tonumber(src.native) or 0,
			tonumber(src.fallback) or 0,
			self:FormatAuctionScanAge(self:GetLastAuctionQueueScanAt()),
			selScanLabel,
			fullDumpStatus,
			lastFullDumpLabel
		))
	end
	local total = tonumber(refreshState.auctionScanTotal) or 0
	local done = tonumber(refreshState.auctionScanDone) or 0
	local activeName = refreshState.auctionActiveItemID and self:GetItemDisplayName(refreshState.auctionActiveItemID) or "idle"
	local mode = tostring(refreshState.auctionScanMode or "idle")
	if mode == "crafts" then
		mode = "craft prices"
	elseif mode == "account_inv" then
		mode = "account inv"
	elseif mode == "mixed" then
		mode = "crafts+account"
	end
	local bulk = refreshState.auctionBulk
	local fullDumpActive = dumpState and dumpState.mode == "full" and dumpState.running == true
	local scanActive = ((refreshState.auctionRefreshRunning == true) or (refreshState.auctionRoiRunning == true)) and (total <= 0 or done < total)
		or (total > 0 and done < total)
	local scanPaused = refreshState.auctionRefreshPaused == true and refreshState.auctionRefreshRunning == true
	local bulkActive = bulk and bulk.running == true
	if panel.btnDumpFull then
		if fullDumpActive then
			panel.btnDumpFull:SetEnabled(false)
			panel.btnDumpFull:SetText("Dumping...")
		elseif cooldownRemaining > 0 then
			panel.btnDumpFull:SetEnabled(false)
			panel.btnDumpFull:SetText("CD " .. formatDurationShort(cooldownRemaining))
		else
			panel.btnDumpFull:SetEnabled(true)
			panel.btnDumpFull:SetText("Full dump")
		end
	end
	if panel.btnDumpVisible then
		panel.btnDumpVisible:SetEnabled(not fullDumpActive)
	end
	if panel.btnScanCraftPrices then
		local scanBusy = refreshState.auctionRefreshRunning == true
		panel.btnScanCraftPrices:SetEnabled(not fullDumpActive and not scanBusy)
	end
	if panel.btnScanAccountInv then
		local scanBusy = refreshState.auctionRefreshRunning == true
		panel.btnScanAccountInv:SetEnabled(not fullDumpActive and not scanBusy)
	end
	if panel.btnScanCraftAndAccount then
		local scanBusy = refreshState.auctionRefreshRunning == true
		panel.btnScanCraftAndAccount:SetEnabled(not fullDumpActive and not scanBusy)
	end
	if panel.btnPauseBulk then
		if bulkActive then
			panel.btnPauseBulk:SetText((bulk.paused == true) and "Resume" or "Pause")
			panel.btnPauseBulk:Show()
		else
			panel.btnPauseBulk:Hide()
		end
	end
	if panel.btnPauseScan then
		if refreshState.auctionRefreshRunning == true or scanPaused then
			panel.btnPauseScan:SetText(scanPaused and "Resume" or "Pause")
			panel.btnPauseScan:Show()
		else
			panel.btnPauseScan:Hide()
		end
	end
	local displayTotal = total
	local displayDone = done
	if panel.progressText then
		if fullDumpActive then
			if dumpState.status == "requesting" then
				panel.progressText:SetText("Full dump: requesting replicate list...")
			elseif dumpState.persistTotal and dumpState.persistTotal > 0 then
				panel.progressText:SetText(string.format(
					"Full dump persist %s/%s",
					self:FormatNumberGrouped(math.min(tonumber(dumpState.persistDone) or 0, tonumber(dumpState.persistTotal) or 0)),
					self:FormatNumberGrouped(tonumber(dumpState.persistTotal) or 0)
				))
			else
				panel.progressText:SetText(string.format(
					"Full dump %s/%s",
					self:FormatNumberGrouped(math.min(tonumber(dumpState.done) or 0, tonumber(dumpState.total) or 0)),
					self:FormatNumberGrouped(tonumber(dumpState.total) or 0)
				))
			end
			panel.progressText:Show()
		elseif bulkActive then
			displayTotal = tonumber(bulk.total) or 0
			displayDone = tonumber(bulk.done) or 0
			local modeLabel = bulk.mode == "post_profitable" and "post-profitable" or "post-all"
			local currentLabel = bulk.currentItemID and self:GetItemDisplayName(bulk.currentItemID) or "-"
			panel.progressText:SetText(string.format(
				"Bulk %d/%d (%s): %s | posted %d | skipped %d | failed %d",
				math.min(displayDone, displayTotal),
				displayTotal,
				modeLabel,
				bulk.status or currentLabel,
				tonumber(bulk.posted) or 0,
				tonumber(bulk.skippedDumped) or 0,
				tonumber(bulk.failed) or 0
			))
			panel.progressText:Show()
		elseif (scanActive or scanPaused) and total > 0 then
			local verb = scanPaused and "Paused" or "Scanning"
			panel.progressText:SetText(string.format("%s %d/%d (%s): %s", verb, math.min(done, total), total, mode, activeName))
			panel.progressText:Show()
		elseif cooldownRemaining > 0 then
			panel.progressText:SetText("Full dump cooldown: " .. formatDurationShort(cooldownRemaining))
			panel.progressText:Show()
		else
			panel.progressText:SetText("Idle")
			panel.progressText:Hide()
		end
	end
	if panel.progressBar then
		if (fullDumpActive and ((tonumber(dumpState.persistTotal) or 0) > 0 or (tonumber(dumpState.total) or 0) > 0))
			or (bulkActive and displayTotal > 0)
			or (scanActive and total > 0) then
			local denom
			local numer
			if fullDumpActive then
				if (tonumber(dumpState.persistTotal) or 0) > 0 then
					denom = tonumber(dumpState.persistTotal) or 0
					numer = tonumber(dumpState.persistDone) or 0
				else
					denom = tonumber(dumpState.total) or 0
					numer = tonumber(dumpState.done) or 0
				end
			else
				denom = (bulkActive and displayTotal or total)
				numer = (bulkActive and displayDone or done)
			end
			local frac = math.max(0, math.min(1, numer / denom))
			panel.progressBar:SetValue(frac)
			panel.progressBar:Show()
			if panel.progressBarBg then
				panel.progressBarBg:Show()
			end
		else
			panel.progressBar:SetValue(0)
			panel.progressBar:Hide()
			if panel.progressBarBg then
				panel.progressBarBg:Hide()
			end
		end
	end
	if panel.progressTiming then
		local gt = GetTime and GetTime() or 0
		if (scanActive or scanPaused) and total > 0 and refreshState.auctionRefreshRunning == true then
			local started = tonumber(refreshState.auctionRefreshStartedAt) or gt
			local elapsed = math.max(0, gt - started)
			if scanPaused then
				panel.progressTiming:SetText(string.format("Elapsed: %s  |  Paused", formatDurationShort(elapsed)))
			else
				local etaStr = "…"
				if done > 0 and total > done then
					etaStr = formatDurationShort((elapsed / done) * (total - done))
				elseif total > 0 and done >= total then
					etaStr = "0s"
				end
				panel.progressTiming:SetText(string.format("Elapsed: %s  |  Est. remaining: ~%s", formatDurationShort(elapsed), etaStr))
			end
			panel.progressTiming:Show()
		else
			panel.progressTiming:Hide()
		end
	end

	if panel.tabSell then
		panel.tabSell:SetEnabled(true)
		if self.StyleShellButton then
			self:StyleShellButton(panel.tabSell, activeTab == "sell")
		end
		panel.tabSell:SetAlpha(activeTab == "sell" and 1 or 0.9)
		panel.tabSell:EnableMouse(true)
		panel.tabSell:RegisterForClicks("LeftButtonUp")
	end
	if panel.tabCart then
		panel.tabCart:SetEnabled(true)
		if self.StyleShellButton then
			self:StyleShellButton(panel.tabCart, activeTab == "cart")
		end
		panel.tabCart:SetAlpha(activeTab == "cart" and 1 or 0.9)
		panel.tabCart:EnableMouse(true)
		panel.tabCart:RegisterForClicks("LeftButtonUp")
		panel.tabCart:SetText(cartOutstanding > 0 and string.format("Cart (%d)", cartOutstanding) or "Shopping cart")
		if panel.tabCart.GetTextWidth and panel.tabCart.SetWidth then
			panel.tabCart:SetWidth(math.max(92, math.min(148, panel.tabCart:GetTextWidth() + 24)))
		end
	end
	for _, control in ipairs(panel.sellControls or {}) do
		if control and control.SetShown then
			control:SetShown(activeTab == "sell")
		elseif control and control.Show and control.Hide then
			if activeTab == "sell" then control:Show() else control:Hide() end
		end
	end
	if panel.subtitle then panel.subtitle:SetShown(activeTab == "sell") end
	if panel.stats then panel.stats:SetShown(activeTab == "sell") end
	if panel.btnPauseScan then panel.btnPauseScan:SetShown(activeTab == "sell") end
	if panel.progressText then panel.progressText:SetShown(activeTab == "sell" and panel.progressText:GetText() ~= "") end
	if panel.progressTiming then panel.progressTiming:SetShown(activeTab == "sell") end
	if panel.tableHost then
		panel.tableHost:SetShown(activeTab == "sell")
	end
	if panel.table and panel.table.frame then
		panel.table.frame:SetShown(activeTab == "sell")
	end
	if panel.cartSummary then
		panel.cartSummary:SetShown(activeTab == "cart")
		panel.cartSummary:SetText(string.format(
			"Buy on this character; mail destinations per row  |  %d lines  |  Buy %s  |  Est. %s",
			cartOutstanding,
			self:FormatNumberGrouped(cartQuantityToBuy),
			cartEstimatedBuyCostText
		))
		if activeTab == "cart" then
			panel.cartSummary:ClearAllPoints()
			-- Left-align like Sell subtitle/stats (do not anchor to right-side tab buttons).
			panel.cartSummary:SetPoint("TOPLEFT", panel.title or panel, "BOTTOMLEFT", 0, -4)
			panel.cartSummary:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
		else
			panel.cartSummary:ClearAllPoints()
			panel.cartSummary:SetPoint("TOPLEFT", panel.stats, "BOTTOMLEFT", 0, -6)
			panel.cartSummary:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
		end
	end
	if panel.cartSearchBox then
		panel.cartSearchBox:SetShown(activeTab == "cart")
		local desiredCartText = ui.auctionCartFilterText or ""
		if panel.cartSearchBox:GetText() ~= desiredCartText then
			panel.cartSearchBox:SetText(desiredCartText)
			panel.cartSearchBox:HighlightText(0, 0)
		end
	end
	if panel.btnCartSearch then panel.btnCartSearch:SetShown(activeTab == "cart") end
	if panel.btnCartRefresh then panel.btnCartRefresh:SetShown(activeTab == "cart") end
	if panel.btnCartBuy then panel.btnCartBuy:SetShown(activeTab == "cart") end
	if panel.btnCartRemove then panel.btnCartRemove:SetShown(activeTab == "cart") end
	if panel.btnCartClear then panel.btnCartClear:SetShown(activeTab == "cart") end
	if panel.cartTableHost then panel.cartTableHost:SetShown(activeTab == "cart") end
	if panel.cartTable and panel.cartTable.frame then
		panel.cartTable.frame:SetShown(activeTab == "cart")
	end

	panel.table.sortKey = self.ui.ahSortKey or panel.table.sortKey
	panel.table.sortAsc = self.ui.ahSortAsc
	panel.table:SetRows(rows)
	if panel.cartTable then
		if not panel.__ahCartLayoutV3 then
			panel.__ahCartLayoutV3 = true
			panel.cartTable.autoFitToScroll = true
			panel.cartTable:SetColumns(self:BuildAuctionCartColumns())
			if panel.cartSummary and panel.title then
				panel.cartSummary:ClearAllPoints()
				panel.cartSummary:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -4)
				panel.cartSummary:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
			end
			if panel.cartSearchBox and panel.cartSummary then
				panel.cartSearchBox:ClearAllPoints()
				panel.cartSearchBox:SetPoint("TOPLEFT", panel.cartSummary, "BOTTOMLEFT", 0, -8)
			end
			if panel.btnCartBuy and panel.cartSearchBox and panel.cartTableHost then
				panel.btnCartBuy:ClearAllPoints()
				panel.btnCartBuy:SetPoint("TOPLEFT", panel.cartSearchBox, "BOTTOMLEFT", 0, -6)
				panel.btnCartBuy:SetSize(86, 20)
				if panel.btnCartRemove then
					panel.btnCartRemove:ClearAllPoints()
					panel.btnCartRemove:SetPoint("LEFT", panel.btnCartBuy, "RIGHT", 4, 0)
					panel.btnCartRemove:SetSize(70, 20)
				end
				if panel.btnCartClear then
					panel.btnCartClear:ClearAllPoints()
					panel.btnCartClear:SetPoint("LEFT", panel.btnCartRemove or panel.btnCartBuy, "RIGHT", 4, 0)
					panel.btnCartClear:SetSize(56, 20)
				end
				panel.cartTableHost:ClearAllPoints()
				panel.cartTableHost:SetPoint("TOPLEFT", panel.btnCartBuy, "BOTTOMLEFT", 0, -8)
				panel.cartTableHost:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 52)
			end
		end
		local filteredCartRows = self:FilterAuctionCraftCartRows(cartRows)
		panel.cartTable:SetRows(filteredCartRows)
		local selectedStillVisible = false
		for _, row in ipairs(filteredCartRows) do
			if tonumber(row.itemID) == tonumber(refreshState.auctionCartSelectedItemID) then
				selectedStillVisible = true
				break
			end
		end
		if not selectedStillVisible then
			refreshState.auctionCartSelectedItemID = filteredCartRows[1] and filteredCartRows[1].itemID or nil
		elseif not refreshState.auctionCartSelectedItemID and filteredCartRows[1] then
			refreshState.auctionCartSelectedItemID = filteredCartRows[1].itemID
		end
		local selectedRow = nil
		for _, row in ipairs(filteredCartRows) do
			if tonumber(row.itemID) == tonumber(refreshState.auctionCartSelectedItemID) then
				selectedRow = row
				break
			end
		end
		if panel.btnCartBuy then
			panel.btnCartBuy:SetEnabled(selectedRow ~= nil and (tonumber(selectedRow.quantityToBuy) or 0) > 0)
		end
		if panel.btnCartRemove then
			panel.btnCartRemove:SetEnabled(selectedRow ~= nil)
		end
		if panel.btnCartClear then
			panel.btnCartClear:SetEnabled(#filteredCartRows > 0)
		end
	end
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
	local keyPart = itemKey and tostring(itemKey) or tostring(itemID)
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
	local auction = self:InitAuctionDB()
	local settings = self.db and self.db.settings and self.db.settings.auction or nil
	local retentionDays = tonumber(settings and settings.historyRetentionDays) or 14
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

function ProfessionExporter:GetCraftCostEstimateForItem(itemID, opts)
	opts = opts or {}
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

function ProfessionExporter:GetFullAuctionDumpCooldownRemaining()
	local state = self:GetState()
	local untilTs = tonumber(state.auctionFullDumpCooldownUntil) or 0
	return math.max(0, untilTs - now())
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
	local function addTarget(target, sourceKind)
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
			self:PrintMessage("No remaining craft targets to scan in this AH session. Run /profexport scan first if needed.")
		elseif wantInv and not wantCrafts then
			self:PrintMessage("No remaining tradable account inventory items to scan in this AH session. Run /profexport scan on your characters if needed.")
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
	state.auctionLastFullDumpAt = tonumber(dump.finishedAt) or now()
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
	state.auctionLastFullDumpAt = tonumber(dump.finishedAt) or now()
	state.auctionFullDumpCooldownUntil = (tonumber(dump.finishedAt) or now()) + FULL_AH_DUMP_COOLDOWN_SEC
	self:PrintMessage(string.format("Full AH dump complete: %s items aggregated.", self:FormatNumberGrouped(tonumber(dump.persistTotal) or 0)))
	self:RefreshAuctionHousePanel()
	if self.RefreshMarketTab then
		self:RefreshMarketTab()
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
		local name, texture, count, qualityID, usable, level, levelType, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, bidderFullName, owner, ownerFullName, saleStatus, itemID = C_AuctionHouse.GetReplicateItemInfo(i)
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

function ProfessionExporter:OnFullAuctionDumpTimeout(token)
	local state = self:GetState()
	local dump = state.auctionDump
	if not dump or dump.mode ~= "full" or tonumber(dump.token) ~= tonumber(token) or dump.status ~= "requesting" or dump.running ~= true then
		return
	end
	if self:OnReplicateItemListUpdate() == true then
		return
	end
	local startedAt = tonumber(dump.requestStartedAt) or now()
	if (now() - startedAt) >= FULL_AH_DUMP_REQUEST_TIMEOUT_SEC then
		self:FailFullAuctionDump("Timed out waiting for replicate results.")
		return
	end
	C_Timer.After(FULL_AH_DUMP_REQUEST_POLL_SEC, function()
		ProfessionExporter:OnFullAuctionDumpTimeout(token)
	end)
end

function ProfessionExporter:OnReplicateItemListUpdate()
	local state = self:GetState()
	local dump = state.auctionDump
	if not dump or dump.mode ~= "full" or dump.running ~= true then
		return false
	end
	if dump.status ~= "requesting" then
		return false
	end
	local total = C_AuctionHouse and C_AuctionHouse.GetNumReplicateItems and tonumber(C_AuctionHouse.GetNumReplicateItems()) or nil
	if not total or total <= 0 then
		return false
	end
	dump.total = total
	dump.done = 0
	dump.index = 0
	dump.seenAt = now()
	dump.aggregate = {}
	dump.status = "processing"
	self:RefreshAuctionHousePanel()
	C_Timer.After(0, function()
		ProfessionExporter:ProcessFullAuctionDumpChunk(dump.token)
	end)
	return true
end

function ProfessionExporter:TrimFullDumpMarketHistory()
	self:InitDB()
	local settings = self.db and self.db.settings and self.db.settings.auction or nil
	local retentionDays = tonumber(settings and settings.historyRetentionDays) or 14
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
		local name, texture, count, qualityID, usable, level, levelType, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, bidderFullName, owner, ownerFullName, saleStatus, itemID = GetAuctionItemInfo("list", i)
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
			}
			local ok = pcall(C_AuctionHouse.ReplicateItems)
			if not ok then
				return self:StartClassicFullAuctionDump(token)
			end
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
	self:UpdateAuctionPanelRowPrice(itemID, self:BuildAuctionPanelPriceState(itemID))
	return true
end

function ProfessionExporter:OnAuctionHouseBrowseResultsUpdated(...)
	local state = self:GetState()
	self:DebugLog("AH", "event browse results", {
		string.format("pending=%s", tostring(state and state.auctionPendingBrowseSearch and state.auctionPendingBrowseSearch.itemID)),
	})
	if self:TrySelectPendingAuctionBrowseResult() then
		C_Timer.After(0, function()
			ProfessionExporter:TrySelectPendingAuctionBrowseResult()
		end)
	end
	self:RefreshAuctionHousePanel()
end

function ProfessionExporter:OnCommoditySearchResultsUpdated(itemID)
	local state = self:GetState()
	self:DebugLog("AH", "event commodity results", {
		string.format("arg=%s selected=%s ctx=%s", tostring(normalizeSearchEventItemID(itemID)), tostring(state and state.auctionLastSellSelectionItemID), tostring(state and state.auctionSearchContext and state.auctionSearchContext.itemID)),
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
		string.format("arg=%s selected=%s ctx=%s", tostring(normalizeSearchEventItemID(itemKey)), tostring(state and state.auctionLastSellSelectionItemID), tostring(state and state.auctionSearchContext and state.auctionSearchContext.itemID)),
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
