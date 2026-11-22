local _, Tradewright = ...

function Tradewright:CraftQueueMakeKey(recipeID, outputItemID, characterKey, scenario)
	return table.concat({
		tostring(recipeID or ""),
		tostring(outputItemID or ""),
		tostring(characterKey or ""),
		tostring(scenario or "default"),
	}, "|")
end

function Tradewright:GetCraftQueueStorage()
	self:InitDB()
	if type(self.db.craftQueue) ~= "table" then
		self.db.craftQueue = {}
	end
	return self.db.craftQueue
end

--- Queue entries in order; each has `.queueKey`.
function Tradewright:GetCraftQueueRows()
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
function Tradewright:RemoveCraftQueueLinesForOpportunityRow(row)
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
function Tradewright:RemoveCraftQueueLinesForRecipeID(recipeID)
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

function Tradewright:IsRecipeInCraftQueue(recipeID)
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

function Tradewright:ClearCraftQueue()
	wipe(self:GetCraftQueueStorage())
	-- Crafting-order mats live in both the craft queue and the crafting-order queue; clear both
	-- so the shopping list keeps no orphan order needs.
	if self.GetCraftingOrderQueueStorage then
		wipe(self:GetCraftingOrderQueueStorage())
	end
	self:NotifyCraftQueueChanged()
	notifyCraftingOrderQueue(self, true)
end

function Tradewright:RemoveCraftFromQueue(queueKey)
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

function Tradewright:RemoveCraftQueueLinesByReagentItem(itemID)
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
function Tradewright:UpdateCraftQueueQuantity(queueKey, quantity)
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
	local scenario = ctx.scenario or Tradewright:GetSetting("crafts.scenario", "default")
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
		crafterLabel = select(1, Tradewright:GetCraftRecommendedCrafter(ctx.opportunityRow))
	end
	if not crafterLabel then
		crafterLabel = Tradewright:GetDashboardSidebarCharacterLabel(
			characterKey,
			Tradewright.db.characters and Tradewright.db.characters[characterKey],
			Tradewright:GetCharacterKey()
		)
	end

	local confidence = ctx.confidence or Tradewright:ResolveCraftConfidenceState(eval, ctx.dataSource)

	return {
		recipeID = recipeID,
		outputItemID = outputItemID,
		characterKey = characterKey,
		scenario = scenario,
		quantity = math.max(1, math.floor(tonumber(quantity) or 1)),
		recipeName = ctx.recipeName or eval.recipeName,
		outputName = ctx.outputName or Tradewright:GetItemDisplayName(outputItemID),
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
function Tradewright:AddCraftToQueue(rowOrContext, quantity)
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
function Tradewright:GetCraftQueueQuantityForOpportunityRow(row)
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

function Tradewright:GetCharacterItemTotal(characterKey, itemID)
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
function Tradewright:BuildReagentMailAllocations(itemID, sources)
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
function Tradewright:BuildShoppingMailSendPlan()
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

function Tradewright:FormatMailAllocationsShort(allocations, maxEntries)
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

function Tradewright:NotifyCraftQueueChanged()
	if self.RefreshProfessionCraftEconomyPanel then
		self:RefreshProfessionCraftEconomyPanel()
	end
	self:RefreshCraftsTabIfVisible()
	if self.RefreshAuctionHousePanel then
		self:RefreshAuctionHousePanel()
	end
end
