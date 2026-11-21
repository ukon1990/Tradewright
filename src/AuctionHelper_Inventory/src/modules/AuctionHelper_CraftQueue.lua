local _, AuctionHelper = ...

function AuctionHelper:CraftQueueMakeKey(recipeID, outputItemID, characterKey, scenario)
	return table.concat({
		tostring(recipeID or ""),
		tostring(outputItemID or ""),
		tostring(characterKey or ""),
		tostring(scenario or "default"),
	}, "|")
end

function AuctionHelper:GetCraftQueueStorage()
	self:InitDB()
	if type(self.db.craftQueue) ~= "table" then
		self.db.craftQueue = {}
	end
	return self.db.craftQueue
end

--- Queue entries in order; each has `.queueKey`.
function AuctionHelper:GetCraftQueueRows()
	local storage = self:GetCraftQueueStorage()
	local list = {}
	for key, entry in pairs(storage) do
		if type(entry) == "table" then
			entry.queueKey = entry.queueKey or key
			list[#list + 1] = entry
		end
	end
	table.sort(list, function(a, b)
		return (tonumber(a.addedAt) or 0) < (tonumber(b.addedAt) or 0)
	end)
	return list
end

local function matchesOpportunityRow(entry, row, scenario)
	return type(entry) == "table"
		and tonumber(entry.recipeID) == tonumber(row.recipeID)
		and tonumber(entry.outputItemID) == tonumber(row.outputItemID)
		and entry.scenario == scenario
end

-- Recipe lines are the crafts the player queued; crafting-order lines mirror the crafting-order queue.
local function isRecipeLine(entry, recipeID)
	return type(entry) == "table"
		and tonumber(entry.recipeID) == recipeID
		and entry.source ~= "craftingOrder"
		and not entry.orderID
end

--- Remove all queue lines matching the opportunity row (same recipe, output, scenario as crafts settings).
function AuctionHelper:RemoveCraftQueueLinesForOpportunityRow(row)
	if not row or not row.recipeID or not row.outputItemID then
		return
	end
	local scenario = self:GetSetting("crafts.scenario", "default")
	local storage = self:GetCraftQueueStorage()
	for k, entry in pairs(storage) do
		if matchesOpportunityRow(entry, row, scenario) then
			storage[k] = nil
		end
	end
	self:NotifyCraftQueueChanged()
end

--- Remove the recipe lines for a recipe ID (any output/scenario). Returns how many were removed.
function AuctionHelper:RemoveCraftQueueLinesForRecipeID(recipeID)
	recipeID = tonumber(recipeID)
	if not recipeID then
		return 0
	end
	local storage = self:GetCraftQueueStorage()
	local removed = 0
	for k, entry in pairs(storage) do
		if isRecipeLine(entry, recipeID) then
			storage[k] = nil
			removed = removed + 1
		end
	end
	if removed > 0 then
		self:NotifyCraftQueueChanged()
	end
	return removed
end

function AuctionHelper:IsRecipeInCraftQueue(recipeID)
	recipeID = tonumber(recipeID)
	if not recipeID then
		return false
	end
	for _, entry in pairs(self:GetCraftQueueStorage()) do
		if isRecipeLine(entry, recipeID) then
			return true
		end
	end
	return false
end

local function clearCraftingOrderQueueEntry(self, orderID)
	orderID = tonumber(orderID)
	if not orderID or not self.GetCraftingOrderQueueStorage then
		return false
	end
	local orderStorage = self:GetCraftingOrderQueueStorage()
	local key = tostring(orderID)
	if orderStorage[key] == nil then
		return false
	end
	orderStorage[key] = nil
	return true
end

-- Removes one line and, for a crafting-order line, its crafting-order queue entry.
-- Returns whether a crafting-order queue entry was removed.
local function removeQueueLine(self, storage, queueKey)
	local entry = storage[queueKey]
	storage[queueKey] = nil
	return clearCraftingOrderQueueEntry(self, entry and entry.orderID)
end

local function notifyCraftingOrderQueue(self, clearedOrder)
	if clearedOrder and self.NotifyCraftingOrderQueueChanged then
		self:NotifyCraftingOrderQueueChanged()
	end
end

function AuctionHelper:ClearCraftQueue()
	wipe(self:GetCraftQueueStorage())
	-- Crafting-order mats live in both the craft queue and the crafting-order queue; clear both
	-- so the shopping list keeps no orphan order needs.
	if self.GetCraftingOrderQueueStorage then
		wipe(self:GetCraftingOrderQueueStorage())
	end
	self:NotifyCraftQueueChanged()
	notifyCraftingOrderQueue(self, true)
end

function AuctionHelper:RemoveCraftFromQueue(queueKey)
	if not queueKey then
		return
	end
	local clearedOrder = removeQueueLine(self, self:GetCraftQueueStorage(), queueKey)
	self:NotifyCraftQueueChanged()
	notifyCraftingOrderQueue(self, clearedOrder)
end

local function usesReagent(entry, itemID)
	for _, slot in ipairs(entry.reagentPlan or {}) do
		if tonumber(slot and slot.itemID) == itemID then
			return true
		end
	end
	return false
end

function AuctionHelper:RemoveCraftQueueLinesByReagentItem(itemID)
	itemID = tonumber(itemID)
	if not itemID then
		return 0
	end
	local removed, clearedOrder = 0, false
	local storage = self:GetCraftQueueStorage()
	for key, entry in pairs(storage) do
		if type(entry) == "table" and usesReagent(entry, itemID) then
			clearedOrder = removeQueueLine(self, storage, key) or clearedOrder
			removed = removed + 1
		end
	end
	if removed > 0 then
		self:NotifyCraftQueueChanged()
	end
	notifyCraftingOrderQueue(self, clearedOrder)
	return removed
end

--- A quantity of 0 or less removes the line.
function AuctionHelper:UpdateCraftQueueQuantity(queueKey, quantity)
	if not queueKey then
		return
	end
	quantity = tonumber(quantity) or 0
	local storage = self:GetCraftQueueStorage()
	local clearedOrder = false
	if quantity <= 0 then
		clearedOrder = removeQueueLine(self, storage, queueKey)
	elseif storage[queueKey] then
		storage[queueKey].quantity = math.floor(quantity)
	end
	self:NotifyCraftQueueChanged()
	notifyCraftingOrderQueue(self, clearedOrder)
end

local function copyReagentPlan(plan)
	local out = {}
	if type(plan) ~= "table" then
		return out
	end
	for _, slot in ipairs(plan) do
		out[#out + 1] = {
			itemID = tonumber(slot.itemID),
			quantityRequired = tonumber(slot.quantityRequired) or 0,
			slotIndex = slot.slotIndex,
			synthetic = slot.synthetic,
			slotClass = slot.slotClass,
			slotRequired = slot.slotRequired,
			slotOptional = slot.slotOptional,
			slotLabel = slot.slotLabel,
			liveSelected = slot.liveSelected == true,
			autoSelected = slot.autoSelected == true,
			autoSelectedTarget = slot.autoSelectedTarget == true,
			legacyFallback = slot.legacyFallback == true,
			qualityChoice = tonumber(slot.qualityChoice),
			slotMaxQuality = tonumber(slot.slotMaxQuality),
			targetQualityPlan = slot.targetQualityPlan == true,
			priceUnit = tonumber(slot.priceUnit),
			priceSource = slot.priceSource,
			requiredQuantity = tonumber(slot.requiredQuantity),
			ownedQuantity = tonumber(slot.ownedQuantity),
			purchasedQuantity = tonumber(slot.purchasedQuantity),
			lineCost = tonumber(slot.lineCost),
			fullLineCost = tonumber(slot.fullLineCost),
		}
	end
	return out
end

local function buildEntryFromEval(ctx, quantity)
	local eval = ctx.eval
	if not eval then
		return nil
	end
	local scenario = ctx.scenario or AuctionHelper:GetSetting("crafts.scenario", "default")
	local characterKey = ctx.characterKey
	if not characterKey then
		return nil
	end
	local recipeID = tonumber(ctx.recipeID or eval.recipeID)
	local outputItemID = tonumber(ctx.outputItemID or eval.outputItemID)
	if not recipeID or not outputItemID then
		return nil
	end

	local crafterLabel = ctx.recommendedCrafterLabel
	if not crafterLabel and ctx.opportunityRow then
		crafterLabel = select(1, AuctionHelper:GetCraftRecommendedCrafter(ctx.opportunityRow))
	end
	if not crafterLabel then
		crafterLabel = AuctionHelper:GetDashboardSidebarCharacterLabel(
			characterKey,
			AuctionHelper.db.characters and AuctionHelper.db.characters[characterKey],
			AuctionHelper:GetCharacterKey()
		)
	end

	local confidence = ctx.confidence or AuctionHelper:ResolveCraftConfidenceState(eval, ctx.dataSource)

	return {
		recipeID = recipeID,
		outputItemID = outputItemID,
		characterKey = characterKey,
		scenario = scenario,
		quantity = math.max(1, math.floor(tonumber(quantity) or 1)),
		recipeName = ctx.recipeName or eval.recipeName,
		outputName = ctx.outputName or AuctionHelper:GetItemDisplayName(outputItemID),
		professionName = ctx.professionName or eval.professionName,
		skillLineID = tonumber(ctx.skillLineID or eval.skillLineID),
		outputQty = math.max(1, tonumber(eval.outputQty) or 1),
		qualityIndex = tonumber(eval.qualityIndex),
		baseQualityIndex = tonumber(eval.baseQualityIndex),
		scenarioBaseQualityIndex = tonumber(eval.scenarioBaseQualityIndex),
		outputIcon = eval.outputIcon,
		reagentPlan = copyReagentPlan(eval.reagentPlan),
		snapshot = {
			saleNet = eval.saleNet,
			saleGross = eval.saleGross,
			matCost = eval.matCost,
			profit = eval.profit,
			coverage = eval.coverage,
			recommendedCrafterLabel = crafterLabel,
			confidence = confidence,
			canCraftNow = eval.canCraftNow == true,
			qualityReachable = eval.qualityReachable == true,
			qualityIndex = tonumber(eval.qualityIndex),
			baseQualityIndex = tonumber(eval.baseQualityIndex),
			scenarioBaseQualityIndex = tonumber(eval.scenarioBaseQualityIndex),
			concentrationCost = tonumber(eval.concentrationCost),
			concentrationNeeded = tonumber(eval.concentrationNeeded),
			requiredTargetReagent = eval.requiredTargetReagent == true,
			requiredTargetReagentItemID = tonumber(eval.requiredTargetReagentItemID),
			requiredTargetReagentAuto = eval.requiredTargetReagentAuto == true,
		},
		addedAt = time(),
	}
end

--- `rowOrContext` is an opportunity row from BuildCraftOpportunityRows, or a context from
--- EvaluateSelectedProfessionRecipe plus overrides.
function AuctionHelper:AddCraftToQueue(rowOrContext, quantity)
	if type(rowOrContext) ~= "table" then
		return nil, "bad_arg"
	end
	quantity = math.max(1, math.floor(tonumber(quantity) or 1))

	local ctx
	if rowOrContext.perChar and rowOrContext.recipeID and rowOrContext.rowKey then
		local scenario = self:GetSetting("crafts.scenario", "default")
		local characterKey = rowOrContext.bestCharacterKey
		local evaluation = characterKey and rowOrContext.perChar[characterKey]
		if not evaluation then
			return nil, "no_eval"
		end
		ctx = {
			recipeID = rowOrContext.recipeID,
			outputItemID = evaluation.outputItemID,
			characterKey = characterKey,
			scenario = scenario,
			recipeName = rowOrContext.recipeName,
			outputName = rowOrContext.outputName,
			professionName = rowOrContext.professionName,
			skillLineID = rowOrContext.skillLineID,
			eval = evaluation,
			opportunityRow = rowOrContext,
			dataSource = "scan_row",
			confidence = self:ResolveCraftConfidenceState(evaluation, "scan_row"),
			recommendedCrafterLabel = select(1, self:GetCraftRecommendedCrafter(rowOrContext)),
		}
	else
		local base = rowOrContext
		local opp = base.opportunityRow
		local craftChar = opp and opp.bestCharacterKey or base.characterKey
		local evaluation = opp and craftChar and opp.perChar[craftChar] or base.eval
		if not evaluation then
			return nil, "no_eval"
		end
		ctx = {
			recipeID = base.recipeID or evaluation.recipeID,
			outputItemID = evaluation.outputItemID,
			characterKey = craftChar or self:GetCharacterKey(),
			scenario = base.scenario or self:GetSetting("crafts.scenario", "default"),
			recipeName = evaluation.recipeName,
			professionName = evaluation.professionName,
			skillLineID = evaluation.skillLineID,
			eval = evaluation,
			opportunityRow = opp,
			dataSource = base.dataSource,
			confidence = base.confidence,
			recommendedCrafterLabel = opp and select(1, self:GetCraftRecommendedCrafter(opp)) or base.recommendedCrafterLabel,
		}
	end

	local entry = buildEntryFromEval(ctx, quantity)
	if not entry then
		return nil, "build_failed"
	end

	local key = self:CraftQueueMakeKey(entry.recipeID, entry.outputItemID, entry.characterKey, entry.scenario)
	local storage = self:GetCraftQueueStorage()
	local existing = storage[key]
	if existing then
		existing.quantity = math.max(1, (tonumber(existing.quantity) or 0) + entry.quantity)
		existing.snapshot = entry.snapshot
		existing.reagentPlan = entry.reagentPlan
		existing.outputQty = entry.outputQty
		existing.qualityIndex = entry.qualityIndex
		existing.baseQualityIndex = entry.baseQualityIndex
		existing.scenarioBaseQualityIndex = entry.scenarioBaseQualityIndex
		existing.outputIcon = entry.outputIcon
		existing.addedAt = time()
	else
		entry.queueKey = key
		storage[key] = entry
	end

	self:NotifyCraftQueueChanged()
	return key
end

--- Sum queue quantities matching opportunity row (same recipe, output, scenario as crafts settings).
function AuctionHelper:GetCraftQueueQuantityForOpportunityRow(row)
	if not row or not row.recipeID or not row.outputItemID then
		return 0
	end
	local scenario = self:GetSetting("crafts.scenario", "default")
	local storage = self:GetCraftQueueStorage()
	local sum = 0
	for _, entry in pairs(storage) do
		if matchesOpportunityRow(entry, row, scenario) then
			sum = sum + (tonumber(entry.quantity) or 0)
		end
	end
	return sum
end

function AuctionHelper:GetCharacterItemTotal(characterKey, itemID)
	characterKey = tostring(characterKey or "")
	itemID = tonumber(itemID)
	if characterKey == "" or not itemID then
		return 0
	end
	if characterKey == tostring(self:GetCharacterKey()) and self.GetItemCountByLocation then
		local _, _, _, total = self:GetItemCountByLocation(itemID)
		return tonumber(total) or 0
	end
	local charData = self.db and self.db.characters and self.db.characters[characterKey] or nil
	local entry = charData and charData.inventorySnapshot and charData.inventorySnapshot.items and charData.inventorySnapshot.items[tostring(itemID)] or nil
	return tonumber(entry and entry.total) or 0
end

--- `sources`: entries with characterKey and quantity.
--- Returns rows of { characterKey, quantityNeeded, quantityHave, mailQuantity }.
function AuctionHelper:BuildReagentMailAllocations(itemID, sources)
	itemID = tonumber(itemID)
	if not itemID or type(sources) ~= "table" then
		return {}
	end
	local currentCharacterKey = tostring(self:GetCharacterKey())
	local needByChar = {}
	for _, src in ipairs(sources) do
		local characterKey = tostring(src and src.characterKey or "")
		local qty = tonumber(src and src.quantity) or 0
		if characterKey ~= "" and qty > 0 then
			needByChar[characterKey] = (needByChar[characterKey] or 0) + qty
		end
	end
	local allocations = {}
	for characterKey, need in pairs(needByChar) do
		local have = self:GetCharacterItemTotal(characterKey, itemID)
		local mailQty = math.max(0, need - have)
		if characterKey ~= currentCharacterKey and mailQty > 0 then
			allocations[#allocations + 1] = {
				characterKey = characterKey,
				quantityNeeded = need,
				quantityHave = have,
				mailQuantity = mailQty,
			}
		end
	end
	table.sort(allocations, function(a, b)
		return tostring(a.characterKey) < tostring(b.characterKey)
	end)
	return allocations
end

--- Per-crafter mail plan from the bags and the queue's material needs; see MailLogic.BuildMailPlan.
--- Rows of { characterKey, mailName, items, totalQuantity, missing, complete }.
function AuctionHelper:BuildShoppingMailSendPlan()
	local summary = self:BuildCraftQueueSummary()
	local orderSummary = self.BuildCraftingOrderQueueSummary and self:BuildCraftingOrderQueueSummary() or { reagentLines = {} }
	local mirroredOrderIDs = {}
	for _, entry in ipairs(self:GetCraftQueueRows()) do
		local oid = tonumber(entry and entry.orderID)
		if oid then
			mirroredOrderIDs[oid] = true
		end
	end

	local lines, stock = {}, {}
	local function addLine(line, sources)
		local itemID = tonumber(line.itemID)
		if not itemID then
			return
		end
		-- Only bag items can be attached; what sits in the bank shows as missing ("not in bags").
		stock[itemID] = stock[itemID] or (self:GetItemCountByLocation(itemID))
		lines[#lines + 1] = {
			itemID = itemID,
			name = line.name or self:GetItemDisplayName(itemID),
			allocations = sources and self:BuildReagentMailAllocations(itemID, sources)
				or line.mailAllocations or self:BuildReagentMailAllocations(itemID, line.sources),
		}
	end

	for _, line in ipairs(summary.reagentLines or {}) do
		addLine(line)
	end
	-- Crafting orders already mirrored into the craft queue are counted there.
	for _, line in ipairs(orderSummary.reagentLines or {}) do
		local sources = {}
		for _, src in ipairs(line.sources or {}) do
			local oid = tonumber(src and src.orderID)
			if (not oid or not mirroredOrderIDs[oid]) and (tonumber(src and src.quantity) or 0) > 0 then
				sources[#sources + 1] = src
			end
		end
		if #sources > 0 then
			addLine(line, sources)
		end
	end
	return self:SetMailRecipients(self.MailLogic.BuildMailPlan(lines, stock))
end

function AuctionHelper:FormatMailAllocationsShort(allocations, maxEntries)
	allocations = allocations or {}
	maxEntries = tonumber(maxEntries) or 3
	local parts = {}
	for i = 1, math.min(#allocations, maxEntries) do
		local row = allocations[i]
		local label
		if self.GetDashboardSidebarCharacterLabel then
			label = self:GetDashboardSidebarCharacterLabel(
				row.characterKey,
				self.db and self.db.characters and self.db.characters[row.characterKey],
				self:GetCharacterKey()
			)
		else
			label = (tostring(row.characterKey):match("^([^%-]+)") or row.characterKey)
		end
		parts[#parts + 1] = string.format("%s:%s", label, self.FormatNumberGrouped and self:FormatNumberGrouped(row.mailQuantity) or tostring(row.mailQuantity))
	end
	if #allocations > maxEntries then
		parts[#parts + 1] = string.format("+%d", #allocations - maxEntries)
	end
	return table.concat(parts, ", ")
end

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

local function newReagentLine(self, itemID, currentCharacterKey)
	return {
		itemID = itemID,
		quantity = 0,
		quantityNeeded = 0,
		name = self:GetItemDisplayName(itemID),
		currentCharacterKey = currentCharacterKey,
		currentCharacterQuantity = self:GetCharacterItemTotal(currentCharacterKey, itemID),
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

-- What the current character still has to buy and mail; adds the buy cost to totals.
local function finishReagentLine(self, line, totals)
	local have = tonumber(line.currentCharacterQuantity) or 0
	line.currentCharacterAvailable = math.min(have, line.quantityNeeded)
	line.quantityToBuy = math.max(0, line.quantityNeeded - have)
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
function AuctionHelper:BuildCraftQueueSummary()
	local rows = self:GetCraftQueueRows()
	local currentCharacterKey = self:GetCharacterKey()
	local totals, reagentTotals = newSummaryTotals(), {}
	for _, entry in ipairs(rows) do
		addEntryTotals(totals, entry)
		addEntryReagents(self, reagentTotals, entry, currentCharacterKey)
	end
	for _, line in pairs(reagentTotals) do
		finishReagentLine(self, line, totals)
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

function AuctionHelper:NotifyCraftQueueChanged()
	if self.RefreshProfessionCraftEconomyPanel then
		self:RefreshProfessionCraftEconomyPanel()
	end
	self:RefreshCraftsTabIfVisible()
	if self.RefreshAuctionHousePanel then
		self:RefreshAuctionHousePanel()
	end
end
