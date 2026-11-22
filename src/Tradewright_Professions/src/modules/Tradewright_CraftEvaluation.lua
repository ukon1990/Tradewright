local _, Tradewright = ...

-- Evaluates one learned recipe for one quality target: reagent plan, material cost, sale price, profit and ROI.

local CraftQuality = Tradewright.CraftQuality
local schematicMaxQuality = CraftQuality.schematicMaxQuality
local reachableQualityIndex = CraftQuality.reachableQualityIndex
local outputItemForQuality = CraftQuality.outputItemForQuality
local CraftCategories = Tradewright.CraftCategories
local recipeDisplayName = CraftCategories.recipeDisplayName
local recipeCategoryId = CraftCategories.recipeCategoryId
local recipeCategoryName = CraftCategories.recipeCategoryName
local ReagentPlan = Tradewright.CraftReagentPlan
local reagentPlanHasRequiredTarget = ReagentPlan.reagentPlanHasRequiredTarget
local reagentPlanContainsLiveSelection = ReagentPlan.reagentPlanContainsLiveSelection
local ensureEnchantingVellumInPlan = ReagentPlan.ensureEnchantingVellumInPlan
local resolveCraftOutputItemID = ReagentPlan.resolveCraftOutputItemID
local CraftConcentration = Tradewright.CraftConcentration
local resolveCraftEvalConcentration = CraftConcentration.resolveCraftEvalConcentration
local craftEvalProfitPerConcentration = CraftConcentration.craftEvalProfitPerConcentration

-- EvaluateCraftScenario helpers share one table `evaluation` (inputs + intermediate results).
local function resolveCraftEvalQuality(self, evaluation)
	local recipeData = evaluation.recipeData
	local info = self:RecipeDataInfo(recipeData)
	evaluation.learned = not (info and info.learned == false)
	evaluation.maxQ = schematicMaxQuality(recipeData)
	evaluation.crafting = recipeData.crafting
	evaluation.baseQ = reachableQualityIndex(evaluation.crafting, evaluation.maxQ)
	evaluation.defaultScenarioQ = evaluation.baseQ
	if evaluation.scenario == "concentration" and evaluation.baseQ < evaluation.maxQ then
		evaluation.defaultScenarioQ = math.min(evaluation.maxQ, evaluation.baseQ + 1)
	end
	evaluation.qualityIndex = math.max(1, math.min(evaluation.maxQ, tonumber(evaluation.opts.targetQualityIndex) or evaluation.defaultScenarioQ))
end

local function resolveCraftEvalOutputItem(self, evaluation)
	local outputItemID = select(1, outputItemForQuality(evaluation.recipeData, evaluation.qualityIndex))
	if not outputItemID then
		outputItemID = resolveCraftOutputItemID(self, evaluation.recipeID, evaluation.recipeData, {
			forceEnchantingVellum = evaluation.opts.forceEnchantingVellum == true,
			professionData = evaluation.professionData,
		})
	end
	if not outputItemID and evaluation.opts.allowMissingOutput then
		-- Shopping/queue still needs a stable key; recipe spell id is unique per line.
		outputItemID = tonumber(self:GetRecipeSpellID(evaluation.recipeData)) or tonumber(evaluation.recipeID)
	end
	evaluation.outputItemID = outputItemID
	return outputItemID
end

local function craftEvalVendorBuyCopper(self, evaluation, id)
	if not evaluation.vendorRecipe then
		return nil
	end
	local vb = self:GetItemVendorPurchaseCopper(id)
	if vb and vb > 0 then
		return vb
	end
	return nil
end

local function craftEvalSaleUnit(self, evaluation, id)
	local vb = craftEvalVendorBuyCopper(self, evaluation, id)
	if vb then
		return vb, "Vendor"
	end
	return self:GetMarketEstimateCopper(id)
end

local function craftEvalMatUnit(self, evaluation, id)
	local vb = craftEvalVendorBuyCopper(self, evaluation, id)
	if vb then
		return vb, "Vendor"
	end
	if evaluation.useLedgerMats then
		local ledgerAvg = self:LedgerAverageUnitBuyCopper(id, nil)
		if ledgerAvg then
			return ledgerAvg, "Ledger"
		end
	end
	local marketEstimate, marketSource = self:GetMarketEstimateCopper(id)
	if marketEstimate and marketEstimate > 0 then
		return marketEstimate, marketSource
	end
	return nil, nil
end

local function craftEvalPickUnit(self, evaluation, id)
	if evaluation.sourceMode == "market_only" then
		return craftEvalSaleUnit(self, evaluation, id)
	end
	return self:CheapestMaterialUnit(id, craftEvalMatUnit(self, evaluation, id))
end

local function newCraftEvalInventoryLookup(self)
	local cache = {}
	return function(itemID)
		local id = tonumber(itemID)
		if not id then
			return { bags = 0, bank = 0, warband = 0, total = 0 }
		end
		local cached = cache[id]
		if cached then
			return cached
		end
		local totals = self:BuildAccountItemInventoryTotals(id)
		cache[id] = totals
		return totals
	end
end

--- Price/inventory callbacks; pick and cost get separate closures with the same rules.
local function bindCraftEvalPricing(self, evaluation)
	local costBasis = evaluation.opts.costBasis or "auto"
	evaluation.useLedgerMats = costBasis == "ledger" or costBasis == "auto"
	evaluation.saleUnitFn = function(id) return craftEvalSaleUnit(self, evaluation, id) end
	evaluation.pickUnitFn = function(id) return craftEvalPickUnit(self, evaluation, id) end
	evaluation.costUnitFn = function(id) return craftEvalPickUnit(self, evaluation, id) end
	evaluation.inventoryFn = newCraftEvalInventoryLookup(self)
end

local function resolveCraftEvalPlan(self, evaluation)
	local forceVellum = evaluation.opts.forceEnchantingVellum == true
	local plan, qualityReachable = self:PickCheapestReagentsPerSlotForTargetQuality(
		evaluation.recipeData, evaluation.professionData, evaluation.pickUnitFn, evaluation.qualityIndex,
		{ reagentPlanOverride = evaluation.opts.reagentPlanOverride, forceEnchantingVellum = forceVellum }
	)
	if not plan then
		return nil
	end
	if forceVellum then
		ensureEnchantingVellumInPlan(plan, evaluation.professionData, evaluation.recipeData, true)
	end
	evaluation.plan, evaluation.qualityReachable = plan, qualityReachable
	evaluation.usesRequiredTarget = reagentPlanHasRequiredTarget(plan)
	return plan
end

--- saleBasis ledger/auto: replace a market (not vendor) sale price with the ledger sell average.
local function applyCraftEvalLedgerSale(self, evaluation, saleGross, saleSrc)
	local saleBasis = evaluation.opts.saleBasis or "auto"
	if not (saleGross and saleSrc ~= "Vendor sell" and saleBasis ~= "market" and (saleBasis == "ledger" or saleBasis == "auto")) then
		return saleGross, saleSrc
	end
	local avgs, n = self:LedgerAverageUnitSellCopper(evaluation.outputItemID, nil)
	if avgs and n and n >= 1 then
		return avgs, "ledger"
	end
	return saleGross, saleSrc
end

local function resolveCraftEvalSale(self, evaluation)
	local saleGross, saleSrc = self:GetMarketEstimateCopper(evaluation.outputItemID)
	if evaluation.vendorRecipe then
		local vs = self:GetItemVendorSellCopper(evaluation.outputItemID)
		if vs and vs > 0 then
			saleGross = vs
			saleSrc = "Vendor sell"
		end
	end
	saleGross, saleSrc = applyCraftEvalLedgerSale(self, evaluation, saleGross, saleSrc)
	evaluation.saleGross, evaluation.saleSrc = saleGross, saleSrc
	evaluation.saleNet = saleGross and self:ApplyAhCutToSaleCopper(saleGross) or nil
end

local function craftEvalProfitBlocked(evaluation)
	if evaluation.matMissingPrice or not evaluation.saleGross then
		return true
	end
	return evaluation.qualityReachable == false and (evaluation.scenario ~= "concentration" or not evaluation.concentrationNeeded)
end

local function resolveCraftEvalProfit(evaluation)
	evaluation.matPerCraft = evaluation.fullMatCost or evaluation.outOfPocketMatCost
	local matPerCraft = evaluation.matPerCraft
	local profit = (evaluation.saleNet and matPerCraft) and (evaluation.saleNet * evaluation.outQty - matPerCraft) or nil
	resolveCraftEvalConcentration(evaluation)
	if craftEvalProfitBlocked(evaluation) then
		profit = nil
	end
	evaluation.profit = profit
	evaluation.roi = (profit and matPerCraft and matPerCraft > 0) and (profit / matPerCraft) * 100 or nil
end

--- First required_target entry's item and auto flag (only when the plan has one).
local function craftEvalRequiredTarget(plan, usesRequiredTarget)
	if not usesRequiredTarget then
		return nil, false
	end
	for _, entry in ipairs(plan or {}) do
		if entry.slotClass == "required_target" then
			return tonumber(entry.itemID), entry.autoSelectedTarget == true
		end
	end
	return nil, false
end

local function buildCraftEvalResult(self, evaluation)
	local recipeID, recipeData, professionData, plan = evaluation.recipeID, evaluation.recipeData, evaluation.professionData, evaluation.plan
	local characterKey = evaluation.characterKey
	local exportRecipeID = self:GetRecipeExportID(recipeData) or tonumber(recipeID) or recipeID
	local recipeSpellID = self:GetRecipeSpellID(recipeData) or tonumber(recipeID) or recipeID
	local usesTarget = evaluation.usesRequiredTarget
	local targetItemID, targetAuto = craftEvalRequiredTarget(plan, usesTarget)
	return {
		characterKey = characterKey, recipeID = exportRecipeID, recipeSpellID = recipeSpellID,
		recipeName = recipeDisplayName(recipeData),
		professionName = professionData.professionName, skillLineID = professionData.skillLineID,
		expansionTag = self:GetCraftExpansionTag(professionData, recipeData, evaluation.outputItemID),
		learned = evaluation.learned, qualityIndex = evaluation.qualityIndex, baseQualityIndex = evaluation.baseQ,
		scenarioBaseQualityIndex = evaluation.defaultScenarioQ, qualityReachable = evaluation.qualityReachable ~= false,
		outputItemID = evaluation.outputItemID, outputQty = evaluation.outQty, outputIcon = evaluation.outputDesc and evaluation.outputDesc.icon,
		matCost = evaluation.matPerCraft, outOfPocketMatCost = evaluation.outOfPocketMatCost, fullMatCost = evaluation.fullMatCost,
		matMissingPrice = evaluation.matMissingPrice, saleGross = evaluation.saleGross, saleNet = evaluation.saleNet, saleSource = evaluation.saleSrc,
		profit = evaluation.profit, roi = evaluation.roi, coverage = evaluation.coverage, canCraftNow = evaluation.canCraftNow, reagentPlan = plan,
		concentrationCost = evaluation.concCost, concentrationNeeded = evaluation.concentrationNeeded,
		concentrationSkillShortfall = evaluation.concentrationSkillShortfall, profitPerConcentration = evaluation.profitPerConc,
		categoryID = recipeCategoryId(recipeData), categoryName = recipeCategoryName(recipeData, professionData),
		scanAt = self.db.characters[characterKey] and self.db.characters[characterKey].scanFinishedAt,
		enchantUsesVellum = usesTarget, requiredTargetReagent = usesTarget,
		requiredTargetReagentItemID = targetItemID, requiredTargetReagentAuto = targetAuto,
		liveSelectedPlan = reagentPlanContainsLiveSelection(plan),
	}
end

--- Evaluate one character's learned recipe for a specific quality target.
function Tradewright:EvaluateCraftScenario(characterKey, professionData, recipeID, recipeData, opts)
	opts = opts or {}
	local evaluation = {
		characterKey = characterKey, professionData = professionData, recipeID = recipeID, recipeData = recipeData,
		opts = opts, scenario = opts.scenario or "default", sourceMode = opts.sourceMode or "owned_first",
	}
	resolveCraftEvalQuality(self, evaluation)
	if not resolveCraftEvalOutputItem(self, evaluation) then
		return nil
	end
	evaluation.vendorRecipe = self:ProfessionRecipeIsVendorSourced(recipeID, recipeData)
	evaluation.outputDesc = self:ResolveItemDescriptor(evaluation.outputItemID)
	bindCraftEvalPricing(self, evaluation)
	if not resolveCraftEvalPlan(self, evaluation) then
		return nil
	end
	evaluation.outOfPocketMatCost, evaluation.matMissingPrice, evaluation.coverage, evaluation.fullMatCost =
		self:ComputeMatCostForReagentPlan(evaluation.plan, evaluation.costUnitFn, evaluation.sourceMode, evaluation.inventoryFn)
	evaluation.outQty = math.max(1, self:GetRecipeOutputQuantityForCost(recipeData))
	resolveCraftEvalSale(self, evaluation)
	resolveCraftEvalProfit(evaluation)
	evaluation.profitPerConc = craftEvalProfitPerConcentration(self, evaluation)
	evaluation.canCraftNow = evaluation.learned and evaluation.qualityReachable ~= false
		and self:ReagentPlanMeetsInventory(evaluation.plan, evaluation.inventoryFn)
	return buildCraftEvalResult(self, evaluation)
end
