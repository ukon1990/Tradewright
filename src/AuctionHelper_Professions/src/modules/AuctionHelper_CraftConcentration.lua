local _, AuctionHelper = ...

-- Concentration, retail only (The War Within and later): points needed for the next rank and the live UI toggle;
-- without concentration data (Forever) these return nil or the saved scenario.

local CraftQuality = AuctionHelper.CraftQuality
local currentOperationTotalSkill = CraftQuality.currentOperationTotalSkill
local targetQualityRequiredSkill = CraftQuality.targetQualityRequiredSkill
local estimatePlanSkillFromReagentPlan = CraftQuality.estimatePlanSkillFromReagentPlan
local outputItemForQuality = CraftQuality.outputItemForQuality
local cloneReagentPlan = AuctionHelper.CraftReagentPlan.cloneReagentPlan

local function estimateConcentrationNeeded(crafting, maxQ, baseQ, targetQ, plan)
	local concCost = tonumber(crafting and crafting.concentrationCost) or nil
	if not concCost or concCost <= 0 then
		return nil, nil
	end
	baseQ = tonumber(baseQ) or 1
	targetQ = tonumber(targetQ) or 1
	if targetQ ~= math.min(maxQ, baseQ + 1) then
		return nil, nil
	end
	local currentTotal = currentOperationTotalSkill(crafting)
	local baselineTargetSkill = targetQualityRequiredSkill(crafting, maxQ, targetQ)
	if not baselineTargetSkill or baselineTargetSkill <= currentTotal then
		return nil, nil
	end
	local baselineShortfall = baselineTargetSkill - currentTotal
	local plannedSkill = estimatePlanSkillFromReagentPlan(crafting, plan)
	local plannedShortfall = math.max(0, baselineTargetSkill - plannedSkill)
	local needed = math.floor((concCost * (plannedShortfall / baselineShortfall)) + 0.5)
	return math.max(0, needed), plannedShortfall
end

local FORM_CONCENTRATION_METHODS = { "IsConcentrating", "IsUsingConcentration", "GetUseConcentration" }
local FORM_CONCENTRATION_FIELDS = { "useConcentration", "usingConcentration", "isConcentrating" }
local TRANSACTION_CONCENTRATION_METHODS = { "IsApplyingConcentration", "IsConcentrating", "GetUseConcentration", "IsUsingConcentration" }

local function booleanOnly(value)
	if type(value) == "boolean" then
		return value
	end
	return nil
end

-- Best-effort detection of live concentration toggle in Blizzard profession UI.
-- Falls back to addon scenario setting when UI internals are unavailable.
function AuctionHelper:GetOpenProfessionScenario()
	local fallback = self:GetSetting("crafts.scenario", "default")
	if not self.IS_RETAIL then
		return fallback
	end
	local form = self.GetOpenProfessionSchematicForm and self:GetOpenProfessionSchematicForm() or nil
	if not form then
		return fallback
	end
	local concentrating = self:FirstValueFrom(form, FORM_CONCENTRATION_METHODS, FORM_CONCENTRATION_FIELDS, booleanOnly)
	if concentrating == nil then
		local transaction = rawget(form, "transaction") or rawget(form, "Transaction")
		concentrating = self:FirstValueFrom(transaction, TRANSACTION_CONCENTRATION_METHODS, nil, booleanOnly)
	end
	if concentrating == nil then
		return fallback
	end
	return concentrating and "concentration" or "default"
end

local function resolveCraftEvalConcentration(evaluation)
	evaluation.concCost = tonumber(evaluation.crafting and evaluation.crafting.concentrationCost) or nil
	if evaluation.qualityReachable == false and evaluation.qualityIndex > evaluation.baseQ then
		evaluation.concentrationNeeded, evaluation.concentrationSkillShortfall =
			estimateConcentrationNeeded(evaluation.crafting, evaluation.maxQ, evaluation.baseQ, evaluation.qualityIndex, evaluation.plan)
	end
end

local function craftEvalBaseSaleCopper(self, evaluation)
	local baseItem = select(1, outputItemForQuality(evaluation.recipeData, evaluation.baseQ))
	if not baseItem then
		return nil
	end
	local baseSale
	if evaluation.vendorRecipe then
		baseSale = self:GetItemVendorSellCopper(baseItem)
	end
	if not baseSale then
		baseSale = select(1, self:GetMarketEstimateCopper(baseItem, evaluation.tsmMarket, evaluation.fallbackTsm))
	end
	return baseSale
end

--- Extra profit of the upgraded rank per concentration point (concentration scenario only).
local function craftEvalProfitPerConcentration(self, evaluation)
	if not (evaluation.scenario == "concentration" and evaluation.concCost and evaluation.concCost > 0 and evaluation.baseQ < evaluation.maxQ) then
		return nil
	end
	local baseSale = craftEvalBaseSaleCopper(self, evaluation)
	local baseNet = baseSale and self:ApplyAhCutToSaleCopper(baseSale)
	local _, missConc = self:ComputeMatCostForReagentPlan(
		cloneReagentPlan(evaluation.plan), evaluation.saleUnitFn, evaluation.sourceMode, evaluation.inventoryFn)
	if not missConc and evaluation.saleNet and baseNet then
		local dProfit = (evaluation.saleNet - baseNet) * evaluation.outQty
		return dProfit / evaluation.concCost
	end
	return nil
end

-- Shared with AuctionHelper_CraftEvaluation.lua, which passes its evaluation table.
AuctionHelper.CraftConcentration = {
	estimateConcentrationNeeded = estimateConcentrationNeeded,
	resolveCraftEvalConcentration = resolveCraftEvalConcentration,
	craftEvalProfitPerConcentration = craftEvalProfitPerConcentration,
}
