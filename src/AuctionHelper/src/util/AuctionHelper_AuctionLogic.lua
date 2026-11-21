local _, AuctionHelper = ...

--- Pure helpers for the craft cart and the live auction search aggregate. No WoW API.
local AuctionLogic = {}
AuctionHelper.AuctionLogic = AuctionLogic
local FL = AuctionHelper.ForeverLogic

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
			copy.recipeName = sourcePrefix .. "Order #" .. tostring(copy.orderID)
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

local function sourceLabel(source)
	return tostring(source.recipeName or source.outputName or (source.orderID and ("Order #" .. tostring(source.orderID))) or "")
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
