local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Reagent planning: classifies reagent slots, picks the cheapest reagent per slot (Enchanting Vellum for enchants) and prices the plan.

local ENCHANTING_VELLUM_ITEM_ID = 38682

-- An enchant makes no item of its own; for sale it goes on a vellum (see Tradewright_EnchantLogic.lua).
local function craftIsEnchantRecipe(recipeData)
	local outs = recipeData and recipeData.outputs
	local enchantRecipeType = Enum and Enum.TradeskillRecipeType and Enum.TradeskillRecipeType.Enchant
	return Tradewright.EnchantLogic.IsEnchantRecipe(outs and outs.recipeType, enchantRecipeType,
		Tradewright.ENCHANT_SCROLL_DATA, Tradewright:GetRecipeSpellID(recipeData))
end

local function buildPlanIndexBySlot(plan)
	local index = {}
	for _, entry in ipairs(plan or {}) do
		local slotIndex = entry and entry.slotIndex
		if slotIndex ~= nil then
			index[tostring(slotIndex)] = entry
		end
	end
	return index
end

local function reagentPlanHasRequiredTarget(plan)
	for _, entry in ipairs(plan or {}) do
		if entry and entry.slotClass == "required_target" then
			return true
		end
	end
	return false
end

local function reagentPlanContainsLiveSelection(plan)
	for _, entry in ipairs(plan or {}) do
		if entry and entry.liveSelected then
			return true
		end
	end
	return false
end

local function classifyCraftReagentSlot(recipeData, slot)
	local qty = tonumber(slot and slot.quantityRequired) or 0
	if qty <= 0 then
		return nil
	end

	local reagentType = tonumber(slot and slot.reagentType)
	local basicType = Enum and Enum.CraftingReagentType and tonumber(Enum.CraftingReagentType.Basic) or nil
	local finishingType = Enum and Enum.CraftingReagentType and tonumber(Enum.CraftingReagentType.Finishing) or nil
	if basicType and reagentType == basicType then
		return "mandatory_base"
	end

	-- Finishing/optional embellishments are never the enchant target (vellum/gear).
	if finishingType and reagentType == finishingType then
		return "optional"
	end

	if slot and slot.required == true then
		-- Enchant recipes mark some non-basic slots required; treat as target only when not basic.
		if craftIsEnchantRecipe(recipeData) then
			return "required_target"
		end
		return "required_target"
	end

	if slot and slot.optional == true then
		-- Enchanting vellum/gear slots are usually optional in the schematic.
		if craftIsEnchantRecipe(recipeData) then
			return "required_target"
		end
		return "optional"
	end

	-- Enchant recipes with an unlabeled non-basic/non-finishing slot: treat as target.
	if craftIsEnchantRecipe(recipeData) then
		return "required_target"
	end

	return "mandatory_base"
end

local function slotHasReagentItem(slot, itemID)
	itemID = tonumber(itemID)
	if not itemID or type(slot) ~= "table" then
		return false
	end
	for _, reagent in ipairs(slot.reagents or {}) do
		if tonumber(reagent and reagent.itemID) == itemID then
			return true
		end
	end
	return false
end

local function pickCheapestReagentForSlot(slot, unitPriceFn)
	if type(slot) ~= "table" then
		return nil, nil
	end
	local bestId, bestPrice = nil, nil
	local firstId = nil
	for _, reagent in ipairs(slot.reagents or {}) do
		local id = tonumber(reagent.itemID)
		if id then
			if not firstId then
				firstId = id
			end
			if type(unitPriceFn) == "function" then
				-- unitPriceFn returns (price, source); extra parens keep only the first value for tonumber().
				local price = tonumber((unitPriceFn(id)))
				if price and (not bestPrice or price < bestPrice) then
					bestPrice = price
					bestId = id
				end
			end
		end
	end
	-- Shopping still needs a concrete item even when AH/ledger prices are missing.
	return bestId or firstId, bestPrice
end

--- Prefer Enchanting Vellum when present; otherwise cheapest (or first) reagent in the slot.
local function pickReagentForSlot(slot, unitPriceFn, preferItemID)
	preferItemID = tonumber(preferItemID)
	if preferItemID and slotHasReagentItem(slot, preferItemID) then
		return preferItemID
	end
	return pickCheapestReagentForSlot(slot, unitPriceFn)
end

--- Ensure enchant recipes include Enchanting Vellum as the target reagent.
--- When forceReplace is true, only replace existing required_target entries (not finishing slots).
local function ensureEnchantingVellumInPlan(plan, recipeData, forceReplace)
	if not craftIsEnchantRecipe(recipeData) then
		return plan
	end
	plan = plan or {}
	local foundTarget = false
	for _, entry in ipairs(plan) do
		if entry and entry.slotClass == "required_target" then
			foundTarget = true
			if forceReplace and tonumber(entry.itemID) ~= ENCHANTING_VELLUM_ITEM_ID then
				entry.itemID = ENCHANTING_VELLUM_ITEM_ID
				entry.autoSelected = true
				entry.autoSelectedTarget = true
				entry.liveSelected = false
				entry.forcedVellum = true
			end
		end
	end
	if not foundTarget then
		plan[#plan + 1] = {
			itemID = ENCHANTING_VELLUM_ITEM_ID,
			quantityRequired = 1,
			slotIndex = "vellum",
			slotClass = "required_target",
			slotRequired = true,
			slotOptional = true,
			slotLabel = L["Target item"],
			synthetic = true,
			legacyFallback = true,
			autoSelected = true,
			autoSelectedTarget = true,
			forcedVellum = true,
		}
	end
	return plan
end

local function extractOutputItemIDFromApiResult(outputData)
	if type(outputData) ~= "table" then
		return nil
	end
	local id = tonumber(outputData.itemID or outputData.outputItemID or outputData.id)
	if id then
		return id
	end
	local link = outputData.hyperlink or outputData.itemLink or outputData.link
	local getItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
	if type(link) == "string" and link ~= "" and getItemInfoInstant then
		local fromLink = tonumber((getItemInfoInstant(link)))
		if fromLink then
			return fromLink
		end
	end
	return nil
end

-- The scroll the game reports for an enchant with a vellum as its reagent, or for a recipe as it is.
local function outputItemIDFromGame(recipeID, withVellum)
	if not C_TradeSkillUI or not C_TradeSkillUI.GetRecipeOutputItemData then
		return nil
	end
	local attempts = { {} }
	if withVellum then
		table.insert(attempts, 1, { { reagent = { itemID = ENCHANTING_VELLUM_ITEM_ID }, quantity = 1 } })
	end
	for _, reagents in ipairs(attempts) do
		-- The call raises on reagents a client does not accept; that is the same as no answer.
		local ok, outputData = pcall(C_TradeSkillUI.GetRecipeOutputItemData, recipeID, reagents)
		local id = ok and extractOutputItemIDFromApiResult(outputData)
		if id then
			return id
		end
	end
	return nil
end

--- The item a recipe makes when its scan data names none, which is the case for enchants: the
--- scroll from the shipped list, else what the game reports (enchants newer than the list).
local function resolveCraftOutputItemID(self, recipeID, recipeData, opts)
	opts = opts or {}
	local spellID = tonumber(self:GetRecipeSpellID(recipeData)) or tonumber(recipeID)
	local scrollItemID = Tradewright.EnchantLogic.ScrollItemID(Tradewright.ENCHANT_SCROLL_DATA, spellID)
	if scrollItemID then
		return scrollItemID
	end
	recipeID = tonumber(recipeID) or spellID
	if not recipeID then
		return nil
	end
	return outputItemIDFromGame(recipeID, opts.forceEnchantingVellum or craftIsEnchantRecipe(recipeData))
end

local function cloneReagentPlan(plan)
	local out = {}
	for _, entry in ipairs(plan or {}) do
		local copy = {}
		for key, value in pairs(entry) do
			copy[key] = value
		end
		out[#out + 1] = copy
	end
	return out
end

local function reagentSlotLabel(slot)
	return slot.slotInfo and (slot.slotInfo.slotText or slot.slotInfo.label or slot.slotInfo.name) or nil
end

--- Plan this slot? Mandatory/target slots with reagents always; optional ones only when overridden.
local function reagentSlotIncluded(qty, slotClass, slot, override)
	if not (qty > 0 and slotClass and type(slot.reagents) == "table" and #slot.reagents > 0) then
		return false
	end
	if slotClass == "mandatory_base" or slotClass == "required_target" then
		return true
	end
	return slotClass == "optional" and override
end

--- Build a baseline reagent plan from slot metadata and optional live selections.
function Tradewright:PickCheapestReagentsPerSlot(recipeData, unitPriceFn, opts)
	local slots = self:RecipeDataSlots(recipeData)
	local plan = {}
	opts = opts or {}
	if type(slots) ~= "table" or type(unitPriceFn) ~= "function" then
		return plan
	end

	local overrideBySlot = buildPlanIndexBySlot(opts.reagentPlanOverride)
	local enchantRecipe = craftIsEnchantRecipe(recipeData)
	local forceVellum = enchantRecipe and opts.forceEnchantingVellum == true

	for _, slot in ipairs(slots) do
		local qty = tonumber(slot.quantityRequired) or 0
		local slotClass = classifyCraftReagentSlot(recipeData, slot)
		local override = overrideBySlot[tostring(slot.slotIndex)]
		if forceVellum and slotClass == "required_target" then
			-- Shopping/queue: ignore live gear target and always plan for vellum.
			override = nil
		end
		if reagentSlotIncluded(qty, slotClass, slot, override) then
			local itemID = override and tonumber(override.itemID) or nil
			if not itemID then
				local prefer = (enchantRecipe and slotClass == "required_target") and ENCHANTING_VELLUM_ITEM_ID or nil
				itemID = pickReagentForSlot(slot, unitPriceFn, prefer)
			elseif enchantRecipe and slotClass == "required_target" and forceVellum then
				itemID = ENCHANTING_VELLUM_ITEM_ID
			end
			if itemID then
				plan[#plan + 1] = {
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
					forcedVellum = enchantRecipe and slotClass == "required_target" and tonumber(itemID) == ENCHANTING_VELLUM_ITEM_ID
						and (forceVellum or override == nil) or nil,
				}
			end
		end
	end

	if enchantRecipe then
		ensureEnchantingVellumInPlan(plan, recipeData, forceVellum)
	end
	return plan
end

function Tradewright:ComputeMatCostForReagentPlan(plan, unitPriceFn, sourceMode, getInventoryTotalsFn)
	sourceMode = sourceMode or "market"
	local total = 0
	local fullMarketTotal = 0
	local missingPrice = false
	local coverageNum, coverageDen = 0, 0
	if type(unitPriceFn) ~= "function" then
		return nil, true, 0
	end
	if type(getInventoryTotalsFn) ~= "function" then
		getInventoryTotalsFn = function(id)
			return self:BuildAccountItemInventoryTotals(id)
		end
	end
	for _, entry in ipairs(plan or {}) do
		local id = entry.itemID
		local need = tonumber(entry.quantityRequired) or 0
		if id and need > 0 then
			local inv = getInventoryTotalsFn(id)
			local owned = tonumber(inv.total) or 0
			local market, priceSource = unitPriceFn(id)
			market = tonumber(market)
			if not market or market < 0 then
				missingPrice = true
			end
			local useOwned = (sourceMode == "owned_first" or sourceMode == "mixed")
			local fromOwned = useOwned and math.min(owned, need) or 0
			local fromMarket = need - fromOwned
			local lineCost = 0
			coverageDen = coverageDen + need
			coverageNum = coverageNum + fromOwned
			entry.priceUnit = market
			entry.priceSource = priceSource
			entry.requiredQuantity = need
			entry.ownedQuantity = fromOwned
			entry.purchasedQuantity = fromMarket
			if market then
				fullMarketTotal = fullMarketTotal + (need * market)
			end
			if fromMarket > 0 then
				if market then
					lineCost = fromMarket * market
					total = total + lineCost
				else
					missingPrice = true
				end
			end
			entry.lineCost = lineCost
			entry.fullLineCost = market and (need * market) or nil
		end
	end
	local coverage = coverageDen > 0 and (coverageNum / coverageDen) or 0
	return total, missingPrice, coverage, fullMarketTotal
end

function Tradewright:ReagentPlanMeetsInventory(plan, getInventoryTotalsFn)
	if type(getInventoryTotalsFn) ~= "function" then
		getInventoryTotalsFn = function(id)
			return self:BuildAccountItemInventoryTotals(id)
		end
	end
	for _, entry in ipairs(plan or {}) do
		local id = entry.itemID
		local need = tonumber(entry.quantityRequired) or 0
		if id and need > 0 then
			local inv = getInventoryTotalsFn(id)
			if (tonumber(inv.total) or 0) < need then
				return false
			end
		end
	end
	return true
end

function Tradewright:ProfessionRecipeIsVendorSourced(recipeID, recipeData)
	local recipeSpellID = self:GetRecipeSpellID(recipeData) or tonumber(recipeID)
	local function sourceIsVendor(st)
		st = tonumber(st)
		if st == nil then
			return false
		end
		local E = Enum.TradeskillRecipeSource
		if E and E.Vendor and st == E.Vendor then
			return true
		end
		return st == 4
	end
	local info = recipeData and self:RecipeDataInfo(recipeData)
	if info and sourceIsVendor(info.sourceType or info.recipeSource) then
		return true
	end
	if recipeSpellID and C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
		local ok, live = pcall(C_TradeSkillUI.GetRecipeInfo, recipeSpellID)
		if ok and live and sourceIsVendor(live.sourceType or live.recipeSource) then
			return true
		end
	end
	return false
end

Tradewright.CraftReagentPlan = {
	ENCHANTING_VELLUM_ITEM_ID = ENCHANTING_VELLUM_ITEM_ID,
	craftIsEnchantRecipe = craftIsEnchantRecipe,
	classifyCraftReagentSlot = classifyCraftReagentSlot,
	ensureEnchantingVellumInPlan = ensureEnchantingVellumInPlan,
	cloneReagentPlan = cloneReagentPlan,
	reagentPlanHasRequiredTarget = reagentPlanHasRequiredTarget,
	reagentPlanContainsLiveSelection = reagentPlanContainsLiveSelection,
	resolveCraftOutputItemID = resolveCraftOutputItemID,
	buildPlanIndexBySlot = buildPlanIndexBySlot,
	pickReagentForSlot = pickReagentForSlot,
	reagentSlotLabel = reagentSlotLabel,
	reagentSlotIncluded = reagentSlotIncluded,
}
