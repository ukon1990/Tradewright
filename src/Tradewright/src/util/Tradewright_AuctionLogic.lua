local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
--- Pure helpers for the craft cart, the live auction search aggregate, the full scan row fold, own
--- auctions and the classic sell gate. No WoW API.
local AuctionLogic = {}
Tradewright.AuctionLogic = AuctionLogic
local FL = Tradewright.ForeverLogic

local function widen(low, high, value)
	return low and math.min(low, value) or value, high and math.max(high, value) or value
end

local function appendSources(target, sources, sourcePrefix)
	for _, source in ipairs(sources or {}) do
		local copy = {}
		for key, value in pairs(source) do
			copy[key] = value
		end
		if sourcePrefix and copy.recipeName then
			copy.recipeName = sourcePrefix .. tostring(copy.recipeName)
		elseif sourcePrefix and copy.orderID then
			copy.recipeName = sourcePrefix .. L["Order #"] .. tostring(copy.orderID)
		end
		target[#target + 1] = copy
	end
end

local function priceSourceOf(reagent)
	return reagent.estimatedPriceSource or reagent.priceSource
end

local function newCartRow(merged, itemID, reagent, resolveName)
	local row = {
		itemID = itemID,
		name = reagent.name or resolveName(itemID),
		quantityNeeded = 0,
		estimatedUnitPrice = tonumber(reagent.estimatedUnitPrice),
		estimatedPriceSource = priceSourceOf(reagent),
		sources = {},
	}
	merged[itemID] = row
	return row
end

--- Adds one reagent line to `merged[itemID]`: need adds up, the lowest positive price wins and the
--- sources are copied (prefixed with `sourcePrefix`). `resolveName(itemID)` names an unnamed new row.
function AuctionLogic.MergeCartReagentLine(merged, reagent, sourcePrefix, resolveName)
	local itemID = tonumber(reagent.itemID)
	if not itemID then
		return
	end
	local row = merged[itemID] or newCartRow(merged, itemID, reagent, resolveName)
	row.quantityNeeded = row.quantityNeeded + (tonumber(reagent.quantityNeeded or reagent.quantity) or 0)
	local unitPrice = tonumber(reagent.estimatedUnitPrice)
	if unitPrice and unitPrice > 0 and (not row.estimatedUnitPrice or unitPrice < row.estimatedUnitPrice) then
		row.estimatedUnitPrice = unitPrice
		row.estimatedPriceSource = priceSourceOf(reagent)
	end
	appendSources(row.sources, reagent.sources, sourcePrefix)
end

--- A crafting-order reagent line without the sources of `mirroredOrderIDs` (orders already in the
--- craft queue), or nil when nothing is left to buy.
function AuctionLogic.FilterCartOrderReagentLine(reagent, mirroredOrderIDs)
	local need, sources = 0, {}
	for _, source in ipairs(reagent.sources or {}) do
		local orderID = tonumber(source and source.orderID)
		if not orderID or not mirroredOrderIDs[orderID] then
			need = need + (tonumber(source and source.quantity) or 0)
			sources[#sources + 1] = source
		end
	end
	if need <= 0 then
		return nil
	end
	return {
		itemID = reagent.itemID,
		name = reagent.name,
		quantityNeeded = need,
		quantity = need,
		estimatedUnitPrice = reagent.estimatedUnitPrice,
		estimatedPriceSource = priceSourceOf(reagent),
		sources = sources,
	}
end

--- Craft queue and crafting-order reagent lines merged per item. Orders that the queue already
--- mirrors (a queue row with that orderID) are not counted twice.
function AuctionLogic.MergeCartReagents(queueLines, orderLines, queueRows, resolveName)
	local mirroredOrderIDs = {}
	for _, entry in ipairs(queueRows or {}) do
		local orderID = tonumber(entry and entry.orderID)
		if orderID then
			mirroredOrderIDs[orderID] = true
		end
	end
	local merged = {}
	for _, reagent in ipairs(queueLines or {}) do
		AuctionLogic.MergeCartReagentLine(merged, reagent, nil, resolveName)
	end
	for _, reagent in ipairs(orderLines or {}) do
		local unmirrored = AuctionLogic.FilterCartOrderReagentLine(reagent, mirroredOrderIDs)
		if unmirrored then
			AuctionLogic.MergeCartReagentLine(merged, unmirrored, "WO: ", resolveName)
		end
	end
	return merged
end

--- Adds the items the player put in the cart by hand to `merged`. `extras[itemID] = { quantity,
--- unitPrice, reason }`: `quantity` is how many the character should end up holding, so the row
--- empties as purchases arrive; `reason` shows as the row's source.
function AuctionLogic.MergeCartExtras(merged, extras, resolveName)
	for itemID, extra in pairs(extras or {}) do
		AuctionLogic.MergeCartReagentLine(merged, {
			itemID = itemID, quantityNeeded = extra.quantity, estimatedUnitPrice = extra.unitPrice,
			sources = { { recipeName = extra.reason } },
		}, nil, resolveName)
	end
	return merged
end

local function sourceLabel(source)
	return tostring(source.recipeName or source.outputName or (source.orderID and (L["Order #"] .. tostring(source.orderID))) or "")
end

--- Unique source labels, sorted and joined: text ("—" when none), count.
function AuctionLogic.CartSourceText(sources)
	local names, seen = {}, {}
	for _, source in ipairs(sources or {}) do
		local label = sourceLabel(source)
		if label ~= "" and not seen[label] then
			seen[label] = true
			names[#names + 1] = label
		end
	end
	table.sort(names)
	return (#names > 0 and table.concat(names, ", ")) or "—", #names
end

--- What the character covers and what to buy: have (capped at need), toBuy, buyCost (nil when unpriced
--- or nothing to buy).
function AuctionLogic.CartQuantities(quantityNeeded, quantityOnCharacter, unitPrice)
	quantityNeeded = tonumber(quantityNeeded) or 0
	local toBuy = math.max(0, quantityNeeded - quantityOnCharacter)
	return math.min(quantityOnCharacter, quantityNeeded), toBuy, unitPrice and toBuy > 0 and unitPrice * toBuy or nil
end

--- Folds one commodity search result into `searchAggregate` ({ totalQuantity = 0 } to start).
function AuctionLogic.AddCommodityResult(searchAggregate, info)
	if not info then
		return
	end
	searchAggregate.totalQuantity = searchAggregate.totalQuantity + math.max(0, tonumber(info.quantity) or 0)
	local unitPrice = tonumber(info.unitPrice)
	if unitPrice and unitPrice > 0 then
		searchAggregate.minUnitPrice, searchAggregate.maxUnitPrice =
			widen(searchAggregate.minUnitPrice, searchAggregate.maxUnitPrice, unitPrice)
	end
end

--- The serialized key item search rows must match, or nil when `fields` (normalized) narrow nothing.
function AuctionLogic.NarrowingItemKey(fields, itemID)
	if not fields or (fields.itemLevel <= 0 and fields.itemSuffix <= 0 and fields.battlePetSpeciesID <= 0) then
		return nil
	end
	return FL.SerializeItemKey(fields, itemID)
end

--- Folds one item search result into its variant group `variantGroups[rowKey]`.
function AuctionLogic.AddItemResult(variantGroups, rowKey, info)
	local variantGroup = variantGroups[rowKey]
	if not variantGroup then
		variantGroup = { key = rowKey, itemKey = info.itemKey, totalQuantity = 0, minUnitPrice = nil, maxUnitPrice = nil, listingCount = 0 }
		variantGroups[rowKey] = variantGroup
	end
	local quantity = math.max(1, tonumber(info.quantity) or 1)
	variantGroup.totalQuantity = variantGroup.totalQuantity + quantity
	variantGroup.listingCount = variantGroup.listingCount + 1
	local buyout = tonumber(info.buyoutAmount)
	local unitPrice = buyout and buyout > 0 and math.floor(buyout / quantity) or 0
	if unitPrice > 0 then
		variantGroup.minUnitPrice, variantGroup.maxUnitPrice =
			widen(variantGroup.minUnitPrice, variantGroup.maxUnitPrice, unitPrice)
	end
end

--- The item aggregate over the priced variant groups (sorted by key), or nil when none is priced.
function AuctionLogic.SummarizeItemVariants(variantGroups, itemID)
	local variants, totalQuantity, listingCount = {}, 0, 0
	local cheapest, highest
	for _, variantGroup in pairs(variantGroups) do
		if variantGroup.minUnitPrice and variantGroup.minUnitPrice > 0 then
			variants[#variants + 1] = variantGroup
			totalQuantity = totalQuantity + math.max(1, tonumber(variantGroup.totalQuantity) or 1)
			listingCount = listingCount + variantGroup.listingCount
			cheapest = cheapest and math.min(cheapest, variantGroup.minUnitPrice) or variantGroup.minUnitPrice
			highest = highest and math.max(highest, variantGroup.maxUnitPrice) or variantGroup.maxUnitPrice
		end
	end
	if #variants == 0 then
		return nil
	end
	table.sort(variants, function(a, b)
		return a.key < b.key
	end)
	return {
		kind = "item",
		itemID = itemID,
		variants = variants,
		cheapestUnitPrice = cheapest,
		highestUnitPrice = highest,
		totalQuantityAll = math.max(1, totalQuantity),
		listingCountAll = listingCount,
	}
end

--- Fold one classic/replicate auction list row into a full-dump aggregate bucket (by itemID).
--- Tracks listingCount (auctions with buyout) and marketHigh (max unit price) for Market UI.
function AuctionLogic.AggregateClassicAuctionRow(aggregate, itemID, count, buyoutPrice)
	aggregate = aggregate or {}
	itemID = tonumber(itemID)
	if not itemID or itemID <= 0 then
		return aggregate
	end
	local quantity = math.max(1, tonumber(count) or 1)
	local rawBuyout = tonumber(buyoutPrice)
	local bucket = aggregate[itemID] or {
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
	aggregate[itemID] = bucket
	return aggregate
end

--- Gate classic cursor sell inject (PickupContainerItem + ClickAuctionSellItemButton).
--- Retail keeps the modern sell frame (SetPostItem) only when it exists; Forever always may use classic.
--- Clients without the modern sell frame may use classic even when not Forever.
function AuctionLogic.ShouldUseClassicSellInject(isForever, hasModernSellFrame)
	if isForever == true then
		return true
	end
	return hasModernSellFrame ~= true
end

---- Totals and undercut flags for the player's own auctions.
--- auctions: { { itemID, quantity, sold, buyout, bid, deposit } } — the price is per unit while listed
--- and the whole incoming amount once sold; deposit is the listing's whole deposit, nil when unknown
--- or not counted. lowestByItem[itemID] is the lowest scanned unit price, if any.
--- Each row gets `undercut`: true / false, or nil when the item has no scanned price to compare;
--- undercut rows also get `undercutBy` (copper per unit) and `undercutPct` (of the player's price).
--- ahCut (fraction, default `Tradewright.DEFAULT_AUCTION_CUT`) gives `net`, what a listing pays out after the auction house cut,
--- and for undercut rows `repostNet`, the payout if it were cancelled (forfeiting the deposit) and
--- reposted at the lowest scanned price.
function AuctionLogic.SummarizeOwnedAuctions(auctions, lowestByItem, ahCut)
	local keep = 1 - (tonumber(ahCut) or Tradewright.DEFAULT_AUCTION_CUT)
	local rows = {}
	local totals = { soldValue = 0, soldCount = 0, listedValue = 0, listedNet = 0, listedCount = 0, undercutCount = 0 }
	for _, auction in ipairs(auctions or {}) do
		local quantity = math.max(1, tonumber(auction.quantity) or 1)
		local price = tonumber(auction.buyout) or tonumber(auction.bid) or 0
		local row = { auctionID = auction.auctionID, itemID = auction.itemID, quantity = quantity, sold = auction.sold == true }
		if row.sold then
			row.value = price
			totals.soldValue = totals.soldValue + price
			totals.soldCount = totals.soldCount + 1
		else
			row.unitPrice = price
			row.value = price * quantity
			row.net = math.floor(row.value * keep)
			row.deposit = tonumber(auction.deposit)
			row.marketPrice = tonumber(lowestByItem and lowestByItem[auction.itemID])
			if row.marketPrice and price > 0 then
				row.undercut = row.marketPrice < price
				if row.undercut then
					row.undercutBy = price - row.marketPrice
					row.undercutPct = row.undercutBy / price * 100
					row.repostNet = math.floor(row.marketPrice * quantity * keep) - (row.deposit or 0)
				end
			end
			totals.listedValue = totals.listedValue + row.value
			totals.listedNet = totals.listedNet + row.net
			totals.listedCount = totals.listedCount + 1
			totals.undercutCount = totals.undercutCount + (row.undercut and 1 or 0)
		end
		rows[#rows + 1] = row
	end
	return rows, totals
end

-- True when a live auction house search differs from the saved scan entry ({ p = price, q = quantity, n = auctions }).
-- A value the search did not report (nil) is never a difference.
function AuctionLogic.LiveSearchDiffers(saved, price, quantity, listings)
	if type(saved) ~= "table" then
		return true
	end
	local function differs(old, new)
		return tonumber(new) ~= nil and tonumber(old) ~= tonumber(new)
	end
	return differs(saved.p, price) or differs(saved.q, quantity) or differs(saved.n, listings)
end

-- Up to this many stale prices are quick to check one by one on any server; above it a full scan
-- is the better choice.
AuctionLogic.FULL_SCAN_SUGGESTION_MIN_STALE = 20

--- What to do with the stale craft and inventory prices when the auction house opens:
--- `queueBulk` checks them one by one, `highlightFullScan` leaves them for a full scan and points
--- the player to it. `status` is `{ fullScanReady, suggestFullScan, staleBulkCount }`.
function AuctionLogic.PlanScanOnOpen(status)
	local leaveForFullScan = status.fullScanReady == true and status.suggestFullScan == true
		and status.staleBulkCount > AuctionLogic.FULL_SCAN_SUGGESTION_MIN_STALE
	return { queueBulk = not leaveForFullScan, highlightFullScan = leaveForFullScan }
end

-- A full scan saves one price per item and hour, so prices this old can be improved by another one.
AuctionLogic.FULL_SCAN_PRICE_FRESH_SEC = 3600

--- Whether the Full scan button should stand out: a full scan can start now and would bring
--- something new. `status` is `{ active, cooldown, lastFullScanAt, now, waiting }`: `lastFullScanAt`
--- is nil before the first full scan, `waiting` counts the prices left for a full scan on opening.
function AuctionLogic.FullScanStandsOut(status)
	if status.active or (status.cooldown or 0) > 0 then
		return false
	end
	local lastFullScanAt = status.lastFullScanAt
	return lastFullScanAt == nil
		or status.now - lastFullScanAt > AuctionLogic.FULL_SCAN_PRICE_FRESH_SEC
		or (status.waiting or 0) > 0
end

--- The item name in the game's "You won an auction for %s" system message, or nil when `message` is
--- something else. `wonFormat` is the client's own text for it, so this works in any language.
function AuctionLogic.WonAuctionItemName(message, wonFormat)
	if type(message) ~= "string" or type(wonFormat) ~= "string" then
		return nil
	end
	local escaped = wonFormat:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
	local pattern = "^" .. escaped:gsub("%%s", "(.+)") .. "$"
	return message:match(pattern)
end

--- The buyout the game has just confirmed for an item of this name, taken out of `pending`
--- (`{ { itemID, name, quantity } }`, oldest first), or nil. Buyouts are confirmed in the order they
--- were made, so older ones still waiting were refused and are dropped.
function AuctionLogic.TakeConfirmedBuyout(pending, itemName)
	for index, buyout in ipairs(pending) do
		if buyout.name == itemName then
			for _ = 1, index do
				table.remove(pending, 1)
			end
			return buyout
		end
	end
	return nil
end
