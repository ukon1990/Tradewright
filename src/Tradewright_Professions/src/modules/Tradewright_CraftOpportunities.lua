local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Builds the Crafts tab rows: evaluates every learned recipe in chunks and caches the result until inputs change.

local schematicMaxQuality = Tradewright.CraftQuality.schematicMaxQuality

local function boolToken(value)
	return value and "1" or "0"
end

local function getCraftEvaluationSettings(self)
	return {
		scenario = tostring(self:GetSetting("crafts.scenario", "default")),
		sourceMode = tostring(self:GetSetting("crafts.reagentSourceMode", "owned_first")),
		costBasis = tostring(self:GetSetting("crafts.costBasis", "auto")),
		saleBasis = tostring(self:GetSetting("crafts.saleBasis", "auto")),
		auctionCut = self:GetAuctionCut(),
		metricRange = tostring(self:GetSetting("inventory.metricRange", "30d")),
		economyShowColumns = self:GetSetting("inventory.economyShowColumns", true) ~= false,
		currentCharacterKey = self:GetCharacterKey(),
	}
end

local function getCraftEvaluationCacheKey(self, settings)
	local state = self:GetState()
	return table.concat({
		tostring(state.dataRevision or 0),
		settings.scenario,
		settings.sourceMode,
		settings.costBasis,
		settings.saleBasis,
		tostring(settings.auctionCut),
		settings.metricRange,
		boolToken(settings.economyShowColumns),
	}, "|")
end

local function buildCraftCostEstimateIndex(rows)
	local index = {}
	for _, row in ipairs(rows or {}) do
		local outputItemID = tonumber(row.outputItemID)
		local matCost = tonumber(row.matCost)
		if outputItemID and matCost then
			local current = index[outputItemID]
			if not current or matCost < (tonumber(current.estimatedMaterialCost) or math.huge) then
				index[outputItemID] = {
					itemID = outputItemID,
					estimatedMaterialCost = matCost,
					confidence = row.confidence or "medium",
					source = "crafts_engine",
					rowKey = row.rowKey,
				}
			end
		end
	end
	return index
end

local CRAFT_EVAL_CHUNK = 85

local function collectCraftEvalWorkList(self)
	local list = {}
	for characterKey, characterData in pairs(self.db.characters or {}) do
		for _, professionData in pairs(characterData.professions or {}) do
			for rid, recipeData in pairs(professionData.recipes or {}) do
				local recipeID = tonumber(rid) or rid
				local info = self:RecipeDataInfo(recipeData)
				if info and info.learned ~= false then
					list[#list + 1] = { characterKey, professionData, recipeID, recipeData }
				end
			end
		end
	end
	return list
end

local function applyCraftEvalWorkItem(self, settings, workItem, byKey, roiIndex)
	local characterKey, professionData, recipeID, recipeData = workItem[1], workItem[2], workItem[3], workItem[4]
	local maxQ = schematicMaxQuality(recipeData)
	for targetQ = 1, maxQ do
		local eval = self:EvaluateCraftScenario(characterKey, professionData, recipeID, recipeData, {
			scenario = settings.scenario,
			sourceMode = settings.sourceMode,
			costBasis = settings.costBasis,
			saleBasis = settings.saleBasis,
			targetQualityIndex = targetQ,
		})
		if eval and eval.outputItemID then
			local outItem = eval.outputItemID
			local rowKey = tostring(recipeID) .. ":" .. tostring(outItem) .. ":Q" .. tostring(eval.qualityIndex or targetQ)
			local bucket = byKey[rowKey]
			if not bucket then
				bucket = {
					rowKey = rowKey,
					recipeID = eval.recipeID,
					recipeSpellID = eval.recipeSpellID,
					outputItemID = outItem,
					recipeName = eval.recipeName,
					outputName = self:GetItemDisplayName(outItem),
					displayName = self:GetItemDisplayName(outItem),
					sourceRecipeName = eval.recipeName,
					outputIcon = eval.outputIcon,
					skillLineID = professionData.skillLineID,
					professionName = professionData.professionName,
					expansionTag = eval.expansionTag,
					categoryID = eval.categoryID,
					categoryName = eval.categoryName,
					qualityIndex = eval.qualityIndex,
					perChar = {},
				}
				byKey[rowKey] = bucket
			end
			bucket.perChar[characterKey] = eval
			bucket.outputIcon = bucket.outputIcon or eval.outputIcon
			bucket.categoryName = bucket.categoryName or eval.categoryName
			bucket.qualityIndex = eval.qualityIndex or bucket.qualityIndex

			if characterKey == settings.currentCharacterKey then
				local matCost = tonumber(eval.matCost)
				local saleUnit = tonumber(eval.saleNet or eval.saleGross)
				local profit = tonumber(eval.profit)
				local roi = tonumber(eval.roi)
				if matCost and matCost > 0 and saleUnit and saleUnit > 0 and profit and roi then
					local candidate = {
						itemID = outItem,
						recipeID = eval.recipeID,
						recipeSpellID = eval.recipeSpellID,
						recipeName = eval.recipeName,
						qualityIndex = tonumber(eval.qualityIndex),
						materialCost = matCost,
						saleUnit = saleUnit,
						outputQty = math.max(1, tonumber(eval.outputQty) or 1),
						profit = profit,
						potentialROI = roi,
					}
					local current = roiIndex[outItem]
					if not current or candidate.potentialROI > (tonumber(current.potentialROI) or -math.huge) then
						roiIndex[outItem] = candidate
					end
				end
			end
		end
	end
end

-- Profitable and priced, but the character cannot craft it yet (missing reagents).
local function isGoldLocked(evaluation)
	return (evaluation.profit or 0) > 0 and not evaluation.canCraftNow and not evaluation.matMissingPrice
		and evaluation.qualityReachable ~= false
end

local function finalizeCraftOpportunityRowsFromBuckets(self, settings, byKey, roiIndex)
	local rows = {}
	local histMemo = {}
	for _, bucket in pairs(byKey) do
		local bestChar, bestProfit = nil, nil
		for characterKey, evaluation in pairs(bucket.perChar) do
			local profit = evaluation.profit
			if profit ~= nil and (bestProfit == nil or profit > bestProfit) then
				bestProfit = profit
				bestChar = characterKey
			end
		end
		if not bestChar then
			bestChar = next(bucket.perChar) -- no priced character: any one (first pairs() key)
		end
		local best = bestChar and bucket.perChar[bestChar]
		if best then
			local hist = self:GetItemHistoryStatsMemo(bucket.outputItemID, "market", settings.metricRange, histMemo)
			local stale = not best.saleGross
			local thin = (hist.count or 0) < 2
			local badges = {}
			if stale then badges[#badges + 1] = "no_price" end
			if thin and not stale then badges[#badges + 1] = "thin_history" end
			if best.matMissingPrice then badges[#badges + 1] = "missing_mats_price" end
			if best.qualityReachable == false then
				badges[#badges + 1] = best.concentrationNeeded and "needs_concentration" or "rank_unreachable"
			end
			if best.canCraftNow then badges[#badges + 1] = "craftable" end
			if isGoldLocked(best) then badges[#badges + 1] = "gold_locked" end
			if best.requiredTargetReagent then
				badges[#badges + 1] = best.requiredTargetReagentAuto and "target_auto" or "target_selected"
			end
			if settings.scenario == "concentration" and (tonumber(best.concentrationCost) or 0) > 0 then badges[#badges + 1] = "concentration" end

			bucket.bestCharacterKey = bestChar
			bucket.profit = best.profit
			bucket.roi = best.roi
			bucket.matCost = best.matCost
			bucket.outOfPocketMatCost = best.outOfPocketMatCost
			bucket.fullMatCost = best.fullMatCost
			bucket.saleNet = best.saleNet
			bucket.saleSource = best.saleSource
			bucket.qualityIndex = best.qualityIndex
			bucket.coverage = best.coverage
			bucket.canCraftNow = best.canCraftNow
			bucket.qualityReachable = best.qualityReachable
			bucket.matMissingPrice = best.matMissingPrice
			bucket.profitPerConcentration = best.profitPerConcentration
			bucket.concentrationCost = best.concentrationCost
			bucket.concentrationNeeded = best.concentrationNeeded
			bucket.concentrationSkillShortfall = best.concentrationSkillShortfall
			bucket.outputQty = best.outputQty
			bucket.badges = badges
			bucket.enchantUsesVellum = best.enchantUsesVellum
			bucket.requiredTargetReagent = best.requiredTargetReagent
			bucket.requiredTargetReagentItemID = best.requiredTargetReagentItemID
			bucket.requiredTargetReagentAuto = best.requiredTargetReagentAuto
			bucket.sourceRecipeName = bucket.recipeName
			bucket.freshnessNote = best.concentrationNeeded and L["Needs concentration"]
				or (best.qualityReachable == false and L["Target rank unreachable"] or (stale and L["No auction price"] or (thin and L["Thin AH history"] or "OK")))
			bucket.confidence = self:ResolveCraftConfidenceState(best, "scan_row")
			rows[#rows + 1] = bucket
		end
	end

	table.sort(rows, function(a, b)
		local pa = a.profit
		local pb = b.profit
		if pa == nil and pb == nil then return tostring(a.outputName) < tostring(b.outputName) end
		if pa == nil then return false end
		if pb == nil then return true end
		if pa ~= pb then return pa > pb end
		if tostring(a.outputName) ~= tostring(b.outputName) then
			return tostring(a.outputName) < tostring(b.outputName)
		end
		return tostring(a.recipeName) < tostring(b.recipeName)
	end)

	return rows, buildCraftCostEstimateIndex(rows), roiIndex
end

local function commitCraftOpportunityCache(self, settings, cacheKey, rows, costIndex, roiIndex)
	local state = self:GetState()
	if state.craftsEvaluationCacheKey ~= cacheKey then
		state.craftsEvaluationRevision = (state.craftsEvaluationRevision or 0) + 1
	end
	state.craftsEvaluationCacheKey = cacheKey
	state.craftOpportunityRowsCacheKey = cacheKey
	state.craftOpportunityRows = rows
	state.craftOpportunityCostIndexCacheKey = cacheKey
	state.craftOpportunityCostIndex = costIndex
	state.craftOpportunityRoiIndexCacheKey = cacheKey
	state.craftOpportunityRoiIndex = roiIndex
	state.craftOpportunityRoiIndexCharacterKey = settings.currentCharacterKey
end

local function runCraftOpportunityFullSync(self, settings, cacheKey)
	local workList = collectCraftEvalWorkList(self)
	local byKey, roiIndex = {}, {}
	for i = 1, #workList do
		applyCraftEvalWorkItem(self, settings, workList[i], byKey, roiIndex)
	end
	local rows, costIndex, roiFinal = finalizeCraftOpportunityRowsFromBuckets(self, settings, byKey, roiIndex)
	commitCraftOpportunityCache(self, settings, cacheKey, rows, costIndex, roiFinal)
	return rows
end

local function abortCraftEvalAsyncBuild(state)
	if not state.craftEvalInProgress then
		return
	end
	state.craftEvalAsyncGen = (state.craftEvalAsyncGen or 0) + 1
	state.craftEvalInProgress = false
	state.craftEvalWorkList = nil
	state.craftEvalByKey = nil
	state.craftEvalRoiIndex = nil
	state.craftEvalSettings = nil
	state.craftEvalIdx = nil
end

function Tradewright:InvalidateCraftOpportunityCaches()
	local state = self:GetState()
	abortCraftEvalAsyncBuild(state)
	self:InvalidateLevelingRoute()
	state.craftsEvaluationCacheKey = nil
	state.craftOpportunityRowsCacheKey = nil
	state.craftOpportunityCostIndexCacheKey = nil
	state.craftOpportunityRoiIndexCacheKey = nil
	state.craftOpportunityRows = nil
	state.craftOpportunityCostIndex = nil
	state.craftOpportunityRoiIndex = nil
end

function Tradewright:CraftEvalProcessNextChunk(gen)
	local state = self:GetState()
	if gen ~= (state.craftEvalAsyncGen or 0) then
		return
	end
	if not state.craftEvalInProgress or not state.craftEvalWorkList then
		return
	end
	local settings = state.craftEvalSettings
	local list = state.craftEvalWorkList
	local byKey = state.craftEvalByKey
	local roiIndex = state.craftEvalRoiIndex
	local idx = state.craftEvalIdx or 1
	local maxIdx = math.min(idx + CRAFT_EVAL_CHUNK - 1, #list)
	for i = idx, maxIdx do
		applyCraftEvalWorkItem(self, settings, list[i], byKey, roiIndex)
	end
	state.craftEvalIdx = maxIdx + 1

	if state.craftEvalIdx <= #list then
		C_Timer.After(0, function()
			self:CraftEvalProcessNextChunk(gen)
		end)
		if self.RefreshCraftsTabIfVisible then
			self:RefreshCraftsTabIfVisible()
		end
		return
	end

	if gen ~= (state.craftEvalAsyncGen or 0) then
		return
	end
	local targetKey = state.craftEvalTargetCacheKey
	local curSettings = getCraftEvaluationSettings(self)
	local curKey = getCraftEvaluationCacheKey(self, curSettings)
	if curKey ~= targetKey then
		abortCraftEvalAsyncBuild(state)
		C_Timer.After(0, function()
			Tradewright:BuildCraftOpportunityRows()
		end)
		return
	end

	local rows, costIndex, roiFinal = finalizeCraftOpportunityRowsFromBuckets(self, settings, byKey, roiIndex)
	commitCraftOpportunityCache(self, settings, targetKey, rows, costIndex, roiFinal)
	state.craftEvalInProgress = false
	state.craftEvalWorkList = nil
	state.craftEvalByKey = nil
	state.craftEvalRoiIndex = nil
	state.craftEvalSettings = nil
	state.craftEvalIdx = nil
	if self.RefreshCraftsTabIfVisible then
		self:RefreshCraftsTabIfVisible()
	end
end

function Tradewright:BuildCraftOpportunityRows(opts)
	opts = type(opts) == "table" and opts or {}
	self:InitDB()
	local state = self:GetState()
	local settings = getCraftEvaluationSettings(self)
	local cacheKey = getCraftEvaluationCacheKey(self, settings)
	if state.craftOpportunityRowsCacheKey == cacheKey and type(state.craftOpportunityRows) == "table" then
		return state.craftOpportunityRows
	end

	if opts.forceSync then
		abortCraftEvalAsyncBuild(state)
		return runCraftOpportunityFullSync(self, settings, cacheKey)
	end

	if state.craftEvalInProgress and state.craftEvalTargetCacheKey == cacheKey then
		return state.craftOpportunityRowsStale or state.craftOpportunityRows or {}
	end

	if state.craftEvalInProgress then
		state.craftEvalAsyncGen = (state.craftEvalAsyncGen or 0) + 1
	end

	local workList = collectCraftEvalWorkList(self)
	state.craftEvalInProgress = true
	state.craftEvalTargetCacheKey = cacheKey
	state.craftEvalAsyncGen = (state.craftEvalAsyncGen or 0) + 1
	local gen = state.craftEvalAsyncGen
	state.craftOpportunityRowsStale = state.craftOpportunityRows
	state.craftEvalWorkList = workList
	state.craftEvalByKey = {}
	state.craftEvalRoiIndex = {}
	state.craftEvalIdx = 1
	state.craftEvalSettings = settings

	if #workList == 0 then
		abortCraftEvalAsyncBuild(state)
		return runCraftOpportunityFullSync(self, settings, cacheKey)
	end

	C_Timer.After(0, function()
		self:CraftEvalProcessNextChunk(gen)
	end)
	return state.craftOpportunityRowsStale or {}
end
