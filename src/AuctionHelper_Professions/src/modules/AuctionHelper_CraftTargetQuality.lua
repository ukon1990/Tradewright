local _, AuctionHelper = ...

-- Picks the cheapest reagent qualities that still reach a chosen output rank (branch-and-bound over quality slots).

local CraftQuality = AuctionHelper.CraftQuality
local schematicMaxQuality = CraftQuality.schematicMaxQuality
local reachableQualityIndex = CraftQuality.reachableQualityIndex
local currentOperationTotalSkill = CraftQuality.currentOperationTotalSkill
local targetQualityRequiredSkill = CraftQuality.targetQualityRequiredSkill
local ReagentPlan = AuctionHelper.CraftReagentPlan
local ENCHANTING_VELLUM_ITEM_ID = ReagentPlan.ENCHANTING_VELLUM_ITEM_ID
local craftIsEnchantRecipe = ReagentPlan.craftIsEnchantRecipe
local buildPlanIndexBySlot = ReagentPlan.buildPlanIndexBySlot
local classifyCraftReagentSlot = ReagentPlan.classifyCraftReagentSlot
local pickReagentForSlot = ReagentPlan.pickReagentForSlot
local ensureEnchantingVellumInPlan = ReagentPlan.ensureEnchantingVellumInPlan
local reagentSlotLabel = ReagentPlan.reagentSlotLabel
local reagentSlotIncluded = ReagentPlan.reagentSlotIncluded

local function buildBestReagentChoicesPerSlot(slot, unitPriceFn)
	local byQuality = {}
	for reagentPos, reagent in ipairs(slot and slot.reagents or {}) do
		local itemID = tonumber(reagent and reagent.itemID)
		if itemID then
			local quality = tonumber(reagent and reagent.quality) or tonumber(reagent and reagent.reagentIndex) or reagentPos or 1
			quality = math.max(1, math.floor(quality))
			local unitPrice = tonumber((unitPriceFn and unitPriceFn(itemID)) or nil)
			local lineCost = unitPrice and ((tonumber(slot.quantityRequired) or 0) * unitPrice) or math.huge
			local current = byQuality[quality]
			if not current or lineCost < current.lineCost then
				byQuality[quality] = {
					itemID = itemID,
					quality = quality,
					lineCost = lineCost,
				}
			end
		end
	end
	local qualities = {}
	for _, entry in pairs(byQuality) do
		qualities[#qualities + 1] = entry
	end
	table.sort(qualities, function(a, b)
		if a.quality ~= b.quality then
			return a.quality < b.quality
		end
		return a.lineCost < b.lineCost
	end)
	return qualities
end

local function clonePlanEntries(plan)
	local out = {}
	for i, entry in ipairs(plan or {}) do
		local row = {}
		for k, v in pairs(entry) do
			row[k] = v
		end
		out[i] = row
	end
	return out
end
-- Target-quality planning state `planState`: recipeData, professionData, unitPriceFn, opts, crafting, maxQ,
-- targetQualityIndex, basePlan; collectTargetQualitySlots adds qualitySlots, staticPlan, totalWeight.
local function addQualityChoiceSlot(planState, slot, slotClass, qty)
	local choices = buildBestReagentChoicesPerSlot(slot, planState.unitPriceFn)
	if #choices == 0 then
		return
	end
	local maxQuality = tonumber(choices[#choices].quality) or 1
	planState.qualitySlots[#planState.qualitySlots + 1] = {
		slot = slot,
		slotClass = slotClass,
		qty = qty,
		maxQuality = maxQuality,
		choices = choices,
		weight = qty,
	}
	planState.totalWeight = planState.totalWeight + qty
end

local function staticTargetPlanEntry(slot, slotClass, qty, override, itemID)
	return {
		itemID = itemID,
		quantityRequired = qty,
		slotIndex = slot.slotIndex,
		slotClass = slotClass,
		slotRequired = slot.required == true,
		slotOptional = slot.optional == true,
		slotLabel = reagentSlotLabel(slot),
		liveSelected = override and override.liveSelected == true or false,
		autoSelected = override == nil,
		autoSelectedTarget = slotClass == "required_target" and override == nil,
	}
end

local function addStaticTargetSlot(planState, slot, slotClass, qty, override)
	local isTarget = slotClass == "required_target"
	local prefer = (planState.enchantRecipe and isTarget) and ENCHANTING_VELLUM_ITEM_ID or nil
	local itemID = override and tonumber(override.itemID) or pickReagentForSlot(slot, planState.unitPriceFn, prefer)
	if planState.forceVellum and isTarget then
		itemID = ENCHANTING_VELLUM_ITEM_ID
	end
	if itemID then
		planState.staticPlan[#planState.staticPlan + 1] = staticTargetPlanEntry(slot, slotClass, qty, override, itemID)
	end
end

local function addTargetQualitySlot(planState, slot)
	local qty = tonumber(slot.quantityRequired) or 0
	local slotClass = classifyCraftReagentSlot(planState.professionData, planState.recipeData, slot)
	local override = planState.overrideBySlot[tostring(slot.slotIndex)]
	if planState.forceVellum and slotClass == "required_target" then
		override = nil
	end
	if not reagentSlotIncluded(qty, slotClass, slot, override) then
		return
	end
	if slotClass == "mandatory_base" and not override then
		addQualityChoiceSlot(planState, slot, slotClass, qty)
	else
		addStaticTargetSlot(planState, slot, slotClass, qty, override)
	end
end

--- Split slots into quality-choice slots (unpinned basic mats) and a static plan (targets, overrides).
local function collectTargetQualitySlots(planState, slots)
	planState.overrideBySlot = buildPlanIndexBySlot(planState.opts.reagentPlanOverride)
	planState.enchantRecipe = craftIsEnchantRecipe(planState.professionData, planState.recipeData)
	planState.forceVellum = planState.enchantRecipe and planState.opts.forceEnchantingVellum == true
	planState.qualitySlots, planState.staticPlan, planState.totalWeight = {}, {}, 0
	for _, slot in ipairs(slots) do
		addTargetQualitySlot(planState, slot)
	end
end

local function targetQualityPlanEntry(slotInfo, choice)
	local slot = slotInfo.slot
	return {
		itemID = choice.itemID,
		quantityRequired = slotInfo.qty,
		slotIndex = slot.slotIndex,
		slotClass = slotInfo.slotClass,
		slotRequired = slot.required == true,
		slotOptional = slot.optional == true,
		slotLabel = reagentSlotLabel(slot),
		qualityChoice = choice.quality,
		targetQualityPlan = true,
		autoSelected = true,
	}
end

local function buildTargetQualityPlan(planState, selection)
	local out = clonePlanEntries(planState.staticPlan)
	for slotIdx, choice in ipairs(selection or {}) do
		out[#out + 1] = targetQualityPlanEntry(planState.qualitySlots[slotIdx], choice)
	end
	return out
end

local function maxQualitySelection(qualitySlots)
	local selection = {}
	for idx, slotInfo in ipairs(qualitySlots) do
		selection[idx] = slotInfo.choices[#slotInfo.choices]
	end
	return selection
end

--- Branch-and-bound: cheapest choice per slot whose weighted quality score reaches needFraction.
local function searchTargetQualityPlan(planState, needFraction)
	local qualitySlots = planState.qualitySlots
	local bestPlan, bestCost = nil, math.huge
	local targetWeightedScore = math.max(0, needFraction) * planState.totalWeight
	local chosen = {}
	local function recurse(idx, weightedScore, weightedCost)
		if weightedCost >= bestCost then
			return
		end
		if idx > #qualitySlots then
			if weightedScore + 1e-6 >= targetWeightedScore then
				bestCost = weightedCost
				bestPlan = buildTargetQualityPlan(planState, chosen)
			end
			return
		end
		local slotInfo = qualitySlots[idx]
		for _, choice in ipairs(slotInfo.choices) do
			chosen[idx] = choice
			local norm = slotInfo.maxQuality > 1 and ((choice.quality - 1) / (slotInfo.maxQuality - 1)) or 0
			recurse(idx + 1, weightedScore + norm * slotInfo.weight, weightedCost + (choice.lineCost or 0))
		end
		chosen[idx] = nil
	end
	recurse(1, 0, 0)
	return bestPlan
end

local function targetQualitySearchBlocked(planState, targetSkill, maxExtra)
	return planState.totalWeight <= 0 or #planState.qualitySlots == 0 or not targetSkill or maxExtra <= 0
end

--- Plan for a rank above the reachable one; returns plan, reachable.
local function planForHigherTargetQuality(self, planState)
	local crafting = planState.crafting
	local currentTotal = currentOperationTotalSkill(crafting)
	local targetSkill = targetQualityRequiredSkill(crafting, planState.maxQ, planState.targetQualityIndex)
	local maxExtra = tonumber(crafting and (crafting.requiredReagentSkillDelta or 0)) or 0
	local slots = self:RecipeDataSlots(planState.recipeData)
	if type(slots) ~= "table" then
		return planState.basePlan, false
	end
	collectTargetQualitySlots(planState, slots)
	local maxPlan = buildTargetQualityPlan(planState, maxQualitySelection(planState.qualitySlots))
	if targetQualitySearchBlocked(planState, targetSkill, maxExtra) then
		return (#maxPlan > 0 and maxPlan or planState.basePlan), false
	end
	local needFraction = (targetSkill - currentTotal) / maxExtra
	if needFraction > 1 then
		return maxPlan, false
	end
	local bestPlan = searchTargetQualityPlan(planState, needFraction)
	return (bestPlan or maxPlan), bestPlan ~= nil
end

function AuctionHelper:PickCheapestReagentsPerSlotForTargetQuality(recipeData, professionData, unitPriceFn, targetQualityIndex, opts)
	opts = opts or {}
	local basePlan = self:PickCheapestReagentsPerSlot(recipeData, professionData, unitPriceFn, opts)
	local crafting = recipeData and recipeData.crafting or nil
	local maxQ = schematicMaxQuality(recipeData)
	local currentQ = reachableQualityIndex(crafting, maxQ)
	targetQualityIndex = math.max(1, math.min(maxQ, tonumber(targetQualityIndex) or currentQ))
	local forceVellumFinalize = craftIsEnchantRecipe(professionData, recipeData) and opts.forceEnchantingVellum == true
	local plan, reachable = basePlan, targetQualityIndex == currentQ
	if targetQualityIndex > currentQ then
		plan, reachable = planForHigherTargetQuality(self, {
			recipeData = recipeData, professionData = professionData, unitPriceFn = unitPriceFn, opts = opts,
			crafting = crafting, maxQ = maxQ, targetQualityIndex = targetQualityIndex, basePlan = basePlan,
		})
	end
	return ensureEnchantingVellumInPlan(plan, professionData, recipeData, forceVellumFinalize), reachable
end
