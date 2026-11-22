local _, Tradewright = ...

-- The craft queue added up for its views: totals, and the shopping list of materials the current
-- character still has to buy. A material that another queued craft of this character makes (Heavy
-- Leather for a queued cloak) is not bought: the list counts on that craft.

local MaterialLogic = Tradewright.MaterialLogic

local function resolveQueueReagentUnitPrice(self, itemID, slot)
	local direct = tonumber(slot and slot.priceUnit)
	if direct and direct > 0 then
		return direct, slot and slot.priceSource
	end
	if not itemID or not self.GetMarketEstimateCopper then
		return nil, nil
	end
	local tsm = self:GetTsmPriceStrings()
	return self:GetMarketEstimateCopper(itemID, tsm.material, tsm.fallback)
end

-- Adds `value` to totals[name], or marks the total unknown when the line has no value.
local function addKnownTotal(totals, name, value)
	if value then
		totals[name] = totals[name] + value
	else
		totals[name .. "Known"] = false
	end
end

local function knownTotal(totals, name)
	return totals[name .. "Known"] and totals[name] or nil
end

local function addEntryTotals(totals, entry)
	local quantity = tonumber(entry.quantity) or 0
	local outputQty = math.max(1, tonumber(entry.outputQty) or 1)
	local snapshot = entry.snapshot or {}
	local matCost, saleNet, profit = tonumber(snapshot.matCost), tonumber(snapshot.saleNet), tonumber(snapshot.profit)
	addKnownTotal(totals, "mat", matCost and matCost * quantity)
	addKnownTotal(totals, "sale", saleNet and saleNet * outputQty * quantity)
	addKnownTotal(totals, "profit", profit and profit * quantity)
	if snapshot.canCraftNow then
		totals.craftableLines = totals.craftableLines + 1
	else
		totals.missingMatLines = totals.missingMatLines + 1
	end
end

-- What the current character has of an item, counting auction purchases that have not reached the
-- bags yet (the auction module credits those until the bags catch up).
local function quantityOnCharacter(self, characterKey, itemID)
	if self.GetAuctionCartEffectiveHave then
		return self:GetAuctionCartEffectiveHave(itemID)
	end
	return self:GetCharacterItemTotal(characterKey, itemID)
end

local function newReagentLine(self, itemID, currentCharacterKey)
	return {
		itemID = itemID,
		quantity = 0,
		quantityNeeded = 0,
		name = self:GetItemDisplayName(itemID),
		currentCharacterKey = currentCharacterKey,
		currentCharacterQuantity = quantityOnCharacter(self, currentCharacterKey, itemID),
		currentCharacterAvailable = 0,
		quantityToBuy = 0,
		estimatedUnitPrice = nil,
		estimatedBuyCost = nil,
		sources = {},
	}
end

-- Keeps the cheapest unit price any queue line saw for this reagent.
local function noteCheapestUnitPrice(self, line, slot)
	local unitPrice, priceSource = resolveQueueReagentUnitPrice(self, line.itemID, slot)
	unitPrice = tonumber(unitPrice)
	if unitPrice and unitPrice > 0 and (not line.estimatedUnitPrice or unitPrice < line.estimatedUnitPrice) then
		line.estimatedUnitPrice = unitPrice
		line.estimatedPriceSource = priceSource
	end
end

local function reagentSource(entry, slot, need)
	return {
		queueKey = entry.queueKey,
		recipeID = tonumber(entry.recipeID),
		recipeName = entry.recipeName,
		outputItemID = tonumber(entry.outputItemID),
		outputName = entry.outputName,
		quantity = need,
		scenario = entry.scenario,
		characterKey = entry.characterKey,
		qualityIndex = tonumber(entry.qualityIndex),
		slotClass = slot.slotClass,
	}
end

local function addEntryReagents(self, reagentTotals, entry, currentCharacterKey)
	local quantity = tonumber(entry.quantity) or 0
	for _, slot in ipairs(entry.reagentPlan or {}) do
		local itemID = tonumber(slot.itemID)
		local need = (tonumber(slot.quantityRequired) or 0) * quantity
		if itemID and need > 0 then
			local line = reagentTotals[itemID] or newReagentLine(self, itemID, currentCharacterKey)
			reagentTotals[itemID] = line
			line.quantity = line.quantity + need
			line.quantityNeeded = line.quantityNeeded + need
			noteCheapestUnitPrice(self, line, slot)
			line.sources[#line.sources + 1] = reagentSource(entry, slot, need)
		end
	end
end

-- Adds what a queued craft of the current character makes to `queuedOutput[itemID]`.
local function addEntryOutput(queuedOutput, entry, currentCharacterKey)
	local itemID = tonumber(entry.outputItemID)
	if itemID and entry.characterKey == currentCharacterKey then
		local made = (tonumber(entry.quantity) or 0) * math.max(1, tonumber(entry.outputQty) or 1)
		queuedOutput[itemID] = (queuedOutput[itemID] or 0) + made
	end
end

-- What the current character still has to buy and mail; adds the buy cost to totals.
-- `queuedOutput[itemID]` is what the queue's own crafts make of each item.
local function finishReagentLine(self, line, totals, queuedOutput)
	local have = tonumber(line.currentCharacterQuantity) or 0
	line.currentCharacterAvailable = math.min(have, line.quantityNeeded)
	line.quantityToBuy, line.quantityFromQueue = MaterialLogic.ToBuyAfterQueuedCrafts(line.quantityNeeded, have, queuedOutput[line.itemID])
	line.mailAllocations = self:BuildReagentMailAllocations(line.itemID, line.sources)
	line.mailToText = self:FormatMailAllocationsShort(line.mailAllocations)
	if line.estimatedUnitPrice and line.quantityToBuy > 0 then
		line.estimatedBuyCost = line.estimatedUnitPrice * line.quantityToBuy
	end
	if line.quantityToBuy > 0 then
		addKnownTotal(totals, "buyCost", line.estimatedBuyCost)
	end
end

local function sortedReagentLines(reagentTotals)
	local lines = {}
	for _, line in pairs(reagentTotals) do
		lines[#lines + 1] = line
	end
	table.sort(lines, function(a, b)
		return tostring(a.name) < tostring(b.name)
	end)
	return lines
end

local function newSummaryTotals()
	return {
		mat = 0, matKnown = true,
		sale = 0, saleKnown = true,
		profit = 0, profitKnown = true,
		buyCost = 0, buyCostKnown = true,
		craftableLines = 0, missingMatLines = 0,
	}
end

--- Aggregated totals and reagents for the queue views and the shopping list.
function Tradewright:BuildCraftQueueSummary()
	local rows = self:GetCraftQueueRows()
	local currentCharacterKey = self:GetCharacterKey()
	local totals, reagentTotals, queuedOutput = newSummaryTotals(), {}, {}
	for _, entry in ipairs(rows) do
		addEntryTotals(totals, entry)
		addEntryReagents(self, reagentTotals, entry, currentCharacterKey)
		addEntryOutput(queuedOutput, entry, currentCharacterKey)
	end
	for _, line in pairs(reagentTotals) do
		finishReagentLine(self, line, totals, queuedOutput)
	end
	return {
		lineCount = #rows,
		lines = rows,
		currentCharacterKey = currentCharacterKey,
		totalMatCost = knownTotal(totals, "mat"),
		totalMatCostValue = totals.mat,
		totalMatCostKnown = totals.matKnown,
		totalSaleNet = knownTotal(totals, "sale"),
		totalSaleNetValue = totals.sale,
		totalSaleNetKnown = totals.saleKnown,
		totalProfit = knownTotal(totals, "profit"),
		totalProfitValue = totals.profit,
		totalProfitKnown = totals.profitKnown,
		totalCurrentCharacterBuyCost = knownTotal(totals, "buyCost"),
		totalCurrentCharacterBuyCostValue = totals.buyCost,
		totalCurrentCharacterBuyCostKnown = totals.buyCostKnown,
		reagentTotals = reagentTotals,
		reagentLines = sortedReagentLines(reagentTotals),
		craftableLineCount = totals.craftableLines,
		missingMaterialsLineCount = totals.missingMatLines,
	}
end
