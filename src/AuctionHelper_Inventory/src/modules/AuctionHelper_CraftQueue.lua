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

--- Remove all queue lines matching the opportunity row (same recipe, output, scenario as crafts settings).
function AuctionHelper:RemoveCraftQueueLinesForOpportunityRow(row)
	if not row or not row.recipeID or not row.outputItemID then
		return
	end
	local scenario = self:GetSetting("crafts.scenario", "default")
	local storage = self:GetCraftQueueStorage()
	for k, entry in pairs(storage) do
		if type(entry) == "table"
			and tonumber(entry.recipeID) == tonumber(row.recipeID)
			and tonumber(entry.outputItemID) == tonumber(row.outputItemID)
			and entry.scenario == scenario
		then
			storage[k] = nil
		end
	end
	self:NotifyCraftQueueChanged()
end

--- Remove non-order craft-queue lines for a recipe ID (any output/scenario on this character's shopping).
--- Returns how many were removed.
function AuctionHelper:RemoveCraftQueueLinesForRecipeID(recipeID)
	recipeID = tonumber(recipeID)
	if not recipeID then
		return 0
	end
	local storage = self:GetCraftQueueStorage()
	local removed = 0
	for k, entry in pairs(storage) do
		if type(entry) == "table"
			and tonumber(entry.recipeID) == recipeID
			and entry.source ~= "craftingOrder"
			and not entry.orderID
		then
			storage[k] = nil
			removed = removed + 1
		end
	end
	if removed > 0 then
		self:NotifyCraftQueueChanged()
	end
	return removed
end

--- Whether any craft-queue lines exist for this recipe (non-order entries).
function AuctionHelper:IsRecipeInCraftShoppingQueue(recipeID)
	recipeID = tonumber(recipeID)
	if not recipeID then
		return false
	end
	local storage = self:GetCraftQueueStorage()
	for _, entry in pairs(storage) do
		if type(entry) == "table"
			and tonumber(entry.recipeID) == recipeID
			and entry.source ~= "craftingOrder"
			and not entry.orderID
		then
			return true
		end
	end
	return false
end

local function clearCraftingOrderWorkQueueEntry(self, orderID)
	orderID = tonumber(orderID)
	if not orderID or not self.GetCraftingOrderWorkQueueStorage then
		return false
	end
	local wo = self:GetCraftingOrderWorkQueueStorage()
	local key = tostring(orderID)
	if wo[key] == nil then
		return false
	end
	wo[key] = nil
	return true
end

function AuctionHelper:ClearCraftQueue()
	local storage = self:GetCraftQueueStorage()
	for k in pairs(storage) do
		storage[k] = nil
	end
	-- Crafting-order mats live in both craftQueue and craftingOrderWorkQueue; clear both
	-- so shopping cart / reagents-to-buy do not keep orphan work-order needs.
	if self.GetCraftingOrderWorkQueueStorage then
		local wo = self:GetCraftingOrderWorkQueueStorage()
		for k in pairs(wo) do
			wo[k] = nil
		end
	end
	self:NotifyCraftQueueChanged()
	if self.NotifyWorkOrderQueueChanged then
		self:NotifyWorkOrderQueueChanged()
	end
end

function AuctionHelper:RemoveCraftFromQueue(queueKey)
	if not queueKey then
		return
	end
	local storage = self:GetCraftQueueStorage()
	local entry = storage[queueKey]
	local orderID = entry and tonumber(entry.orderID)
	storage[queueKey] = nil
	local clearedOrder = clearCraftingOrderWorkQueueEntry(self, orderID)
	self:NotifyCraftQueueChanged()
	if clearedOrder and self.NotifyWorkOrderQueueChanged then
		self:NotifyWorkOrderQueueChanged()
	end
end

function AuctionHelper:RemoveCraftQueueLinesByReagentItem(itemID)
	itemID = tonumber(itemID)
	if not itemID then
		return 0
	end
	local removed = 0
	local clearedOrder = false
	local storage = self:GetCraftQueueStorage()
	for key, entry in pairs(storage) do
		if type(entry) == "table" then
			for _, slot in ipairs(entry.reagentPlan or {}) do
				if tonumber(slot and slot.itemID) == itemID then
					local orderID = tonumber(entry.orderID)
					storage[key] = nil
					removed = removed + 1
					if clearCraftingOrderWorkQueueEntry(self, orderID) then
						clearedOrder = true
					end
					break
				end
			end
		end
	end
	if removed > 0 then
		self:NotifyCraftQueueChanged()
	end
	if clearedOrder and self.NotifyWorkOrderQueueChanged then
		self:NotifyWorkOrderQueueChanged()
	end
	return removed
end

function AuctionHelper:UpdateCraftQueueQuantity(queueKey, quantity)
	if not queueKey then
		return
	end
	quantity = tonumber(quantity) or 0
	local storage = self:GetCraftQueueStorage()
	local clearedOrder = false
	if quantity <= 0 then
		local entry = storage[queueKey]
		local orderID = entry and tonumber(entry.orderID)
		storage[queueKey] = nil
		clearedOrder = clearCraftingOrderWorkQueueEntry(self, orderID)
	else
		local entry = storage[queueKey]
		if entry then
			entry.quantity = math.floor(quantity)
		end
	end
	self:NotifyCraftQueueChanged()
	if clearedOrder and self.NotifyWorkOrderQueueChanged then
		self:NotifyWorkOrderQueueChanged()
	end
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
		local ck = rowOrContext.bestCharacterKey
		local ev = ck and rowOrContext.perChar[ck]
		if not ev then
			return nil, "no_eval"
		end
		ctx = {
			recipeID = rowOrContext.recipeID,
			outputItemID = ev.outputItemID,
			characterKey = ck,
			scenario = scenario,
			recipeName = rowOrContext.recipeName,
			outputName = rowOrContext.outputName,
			professionName = rowOrContext.professionName,
			skillLineID = rowOrContext.skillLineID,
			eval = ev,
			opportunityRow = rowOrContext,
			dataSource = "scan_row",
			confidence = self:ResolveCraftConfidenceState(ev, "scan_row"),
			recommendedCrafterLabel = select(1, self:GetCraftRecommendedCrafter(rowOrContext)),
		}
	else
		local base = rowOrContext
		local opp = base.opportunityRow
		local craftChar = opp and opp.bestCharacterKey or base.characterKey
		local ev = opp and craftChar and opp.perChar[craftChar] or base.eval
		if not ev then
			return nil, "no_eval"
		end
		ctx = {
			recipeID = base.recipeID or ev.recipeID,
			outputItemID = ev.outputItemID,
			characterKey = craftChar or self:GetCharacterKey(),
			scenario = base.scenario or self:GetSetting("crafts.scenario", "default"),
			recipeName = ev.recipeName,
			professionName = ev.professionName,
			skillLineID = ev.skillLineID,
			eval = ev,
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
		if type(entry) == "table"
			and tonumber(entry.recipeID) == tonumber(row.recipeID)
			and tonumber(entry.outputItemID) == tonumber(row.outputItemID)
			and entry.scenario == scenario
		then
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

local function getCharacterSnapshotItemTotal(self, characterKey, itemID)
	return self:GetCharacterItemTotal(characterKey, itemID)
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
		local ck = tostring(src and src.characterKey or "")
		local qty = tonumber(src and src.quantity) or 0
		if ck ~= "" and qty > 0 then
			needByChar[ck] = (needByChar[ck] or 0) + qty
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

--- Per-crafter mail plan from the bags and the queue's material needs; see ForeverLogic.BuildMailPlan.
--- Rows of { characterKey, mailName, items, totalQuantity, missing, complete }.
function AuctionHelper:BuildShoppingMailSendPlan()
	local summary = self:BuildCraftQueueSummary()
	local woSummary = self.BuildCraftingOrderWorkQueueSummary and self:BuildCraftingOrderWorkQueueSummary() or { reagentLines = {} }
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
	-- Work orders already mirrored into the craft queue are counted there.
	for _, line in ipairs(woSummary.reagentLines or {}) do
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
	return self:SetMailRecipients(self.ForeverLogic.BuildMailPlan(lines, stock))
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

function AuctionHelper:RemoveCraftQueueByOrderID(orderID)
	orderID = tonumber(orderID)
	if not orderID then
		return 0
	end
	local removed = 0
	local storage = self:GetCraftQueueStorage()
	for key, entry in pairs(storage) do
		if type(entry) == "table" and tonumber(entry.orderID) == orderID then
			storage[key] = nil
			removed = removed + 1
		end
	end
	if removed > 0 then
		self:NotifyCraftQueueChanged()
	end
	return removed
end

function AuctionHelper:CraftQueueMakeOrderKey(orderID)
	return string.format("craftingOrder|%s", tostring(orderID or ""))
end

--- Upsert a craft-queue marker for a crafting-order work-queue entry.
function AuctionHelper:UpsertCraftQueueForCraftingOrder(orderEntry)
	if type(orderEntry) ~= "table" or not orderEntry.orderID then
		return nil
	end
	local orderID = tonumber(orderEntry.orderID)
	if not orderID then
		return nil
	end
	local characterKey = tostring(orderEntry.characterKey or self:GetCharacterKey())
	local key = self:CraftQueueMakeOrderKey(orderID)
	local storage = self:GetCraftQueueStorage()
	local recipeID = tonumber(orderEntry.spellID)
	local itemID = tonumber(orderEntry.itemID)
	local recipeName = orderEntry.recipeName
	if (not recipeName or recipeName == "") and recipeID and C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
		local ri = C_TradeSkillUI.GetRecipeInfo(recipeID)
		recipeName = ri and ri.name or recipeName
	end
	if (not recipeName or recipeName == "") and itemID then
		recipeName = self:GetItemDisplayName(itemID)
	end
	local outputIcon = nil
	if itemID and self.ResolveItemDescriptor then
		local desc = self:ResolveItemDescriptor(itemID)
		outputIcon = desc and desc.icon or nil
	end
	local entry = storage[key]
	if not entry then
		entry = {
			queueKey = key,
			orderID = orderID,
			source = "craftingOrder",
			recipeID = recipeID,
			outputItemID = itemID,
			characterKey = characterKey,
			scenario = "craftingOrder",
			quantity = 1,
			recipeName = recipeName,
			outputName = itemID and self:GetItemDisplayName(itemID) or nil,
			outputIcon = outputIcon,
			reagentPlan = {},
			snapshot = { canCraftNow = false },
			addedAt = tonumber(orderEntry.addedAt) or time(),
		}
		storage[key] = entry
	else
		entry.characterKey = characterKey
		entry.recipeID = recipeID or entry.recipeID
		entry.recipeName = recipeName or entry.recipeName
		entry.outputItemID = itemID or entry.outputItemID
		entry.outputName = (itemID and self:GetItemDisplayName(itemID)) or entry.outputName
		entry.outputIcon = outputIcon or entry.outputIcon
		entry.addedAt = tonumber(orderEntry.addedAt) or entry.addedAt
		wipe(entry.reagentPlan)
	end
	for matItemID, qty in pairs(orderEntry.crafterMatTotals or {}) do
		local id = tonumber(matItemID)
		local q = tonumber(qty) or 0
		if id and q > 0 then
			entry.reagentPlan[#entry.reagentPlan + 1] = {
				itemID = id,
				quantityRequired = q,
			}
		end
	end
	self:NotifyCraftQueueChanged()
	return key
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

--- Aggregated totals and reagents for UI / future shopping-list hooks.
function AuctionHelper:BuildCraftQueueSummary()
	local rows = self:GetCraftQueueRows()
	local reagentTotals = {}
	local totalMat = 0
	local totalSale = 0
	local totalProfit = 0
	local totalCurrentCharacterBuyCost = 0
	local matKnown = true
	local saleKnown = true
	local profitKnown = true
	local buyCostKnown = true
	local craftableLines = 0
	local missingMatLines = 0
	local currentCharacterKey = self:GetCharacterKey()

	for _, entry in ipairs(rows) do
		local q = tonumber(entry.quantity) or 0
		local outQty = math.max(1, tonumber(entry.outputQty) or 1)
		local snap = entry.snapshot or {}
		local matPer = tonumber(snap.matCost)
		local saleNet = tonumber(snap.saleNet)
		local profit = tonumber(snap.profit)

		if matPer then
			totalMat = totalMat + matPer * q
		else
			matKnown = false
		end
		if saleNet then
			totalSale = totalSale + saleNet * outQty * q
		else
			saleKnown = false
		end
		if profit then
			totalProfit = totalProfit + profit * q
		else
			profitKnown = false
		end

		if snap.canCraftNow then
			craftableLines = craftableLines + 1
		else
			missingMatLines = missingMatLines + 1
		end

		for _, slot in ipairs(entry.reagentPlan or {}) do
			local id = tonumber(slot.itemID)
			local need = (tonumber(slot.quantityRequired) or 0) * q
			if id and need > 0 then
				local row = reagentTotals[id]
				if not row then
					row = {
						itemID = id,
						quantity = 0,
						quantityNeeded = 0,
						name = self:GetItemDisplayName(id),
						currentCharacterKey = currentCharacterKey,
						currentCharacterQuantity = getCharacterSnapshotItemTotal(self, currentCharacterKey, id),
						currentCharacterAvailable = 0,
						quantityToBuy = 0,
						estimatedUnitPrice = nil,
						estimatedBuyCost = nil,
						sources = {},
					}
					reagentTotals[id] = row
				end
				row.quantity = row.quantity + need
				row.quantityNeeded = row.quantityNeeded + need
				local unitPrice, priceSource = resolveQueueReagentUnitPrice(self, id, slot)
				unitPrice = tonumber(unitPrice)
				if unitPrice and unitPrice > 0 and (not row.estimatedUnitPrice or unitPrice < row.estimatedUnitPrice) then
					row.estimatedUnitPrice = unitPrice
					row.estimatedPriceSource = priceSource
				end
				row.sources[#row.sources + 1] = {
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
		end
	end

	local matLines = {}
	for itemID, line in pairs(reagentTotals) do
		line.currentCharacterAvailable = math.min(tonumber(line.currentCharacterQuantity) or 0, tonumber(line.quantityNeeded) or 0)
		line.quantityToBuy = math.max(0, (tonumber(line.quantityNeeded) or 0) - (tonumber(line.currentCharacterQuantity) or 0))
		line.mailAllocations = self:BuildReagentMailAllocations(itemID, line.sources)
		line.mailToText = self:FormatMailAllocationsShort(line.mailAllocations)
		if line.estimatedUnitPrice and line.quantityToBuy > 0 then
			line.estimatedBuyCost = line.estimatedUnitPrice * line.quantityToBuy
			totalCurrentCharacterBuyCost = totalCurrentCharacterBuyCost + line.estimatedBuyCost
		elseif line.quantityToBuy > 0 then
			buyCostKnown = false
		end
		matLines[#matLines + 1] = line
	end
	table.sort(matLines, function(a, b)
		return tostring(a.name) < tostring(b.name)
	end)

	return {
		lineCount = #rows,
		lines = rows,
		currentCharacterKey = currentCharacterKey,
		totalMatCost = matKnown and totalMat or nil,
		totalMatCostValue = totalMat,
		totalMatCostKnown = matKnown,
		totalSaleNet = saleKnown and totalSale or nil,
		totalSaleNetValue = totalSale,
		totalSaleNetKnown = saleKnown,
		totalProfit = profitKnown and totalProfit or nil,
		totalProfitValue = totalProfit,
		totalProfitKnown = profitKnown,
		totalCurrentCharacterBuyCost = buyCostKnown and totalCurrentCharacterBuyCost or nil,
		totalCurrentCharacterBuyCostValue = totalCurrentCharacterBuyCost,
		totalCurrentCharacterBuyCostKnown = buyCostKnown,
		reagentTotals = reagentTotals,
		reagentLines = matLines,
		craftableLineCount = craftableLines,
		missingMaterialsLineCount = missingMatLines,
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
