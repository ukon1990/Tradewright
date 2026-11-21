local _, AuctionHelper = ...

--- Last-resort: profession variant line when output item expansionID is not available yet.
--- TWW / Midnight IDs from https://wowpedia.fandom.com/wiki/TradeSkillLineID
local SKILL_LINE_EXPANSION = {
	[2822] = "tww",
	[2823] = "tww",
	[2824] = "tww",
	[2825] = "tww",
	[2826] = "tww",
	[2827] = "tww",
	[2828] = "tww",
	[2829] = "tww",
	[2830] = "tww",
	[2831] = "tww",
	[2832] = "tww",
	[2833] = "tww",
	[2834] = "tww",
	[2871] = "midnight",
	[2872] = "midnight",
	[2873] = "midnight",
	[2874] = "midnight",
	[2875] = "midnight",
	[2876] = "midnight",
	[2877] = "midnight",
	[2878] = "midnight",
	[2879] = "midnight",
	[2880] = "midnight",
	[2881] = "midnight",
	[2882] = "midnight",
	[2883] = "midnight",
}

local EXPANSION_PATTERNS = {
	{ tag = "midnight", patterns = { "midnight" } },
	{ tag = "tww", patterns = { "the war within", "war within", "khaz algar" } },
	{ tag = "df", patterns = { "dragonflight", "dragon isles" } },
}

local ENCHANTING_VELLUM_ITEM_ID = 38682

function AuctionHelper:GetCraftExpansionTag(professionData, recipeData, outputItemID)
	local desc = outputItemID and self:ResolveItemDescriptor(outputItemID) or nil
	local expansionID = desc and tonumber(desc.expansionID) or nil
	if expansionID then
		return self:ExpansionLeToFilterTag(expansionID)
	end

	local info = self:RecipeDataInfo(recipeData)
	local candidates = {
		professionData and professionData.currentLevelName,
		professionData and professionData.professionName,
		professionData and professionData.baseProfessionInfo and professionData.baseProfessionInfo.parentProfessionName,
		professionData and professionData.baseProfessionInfo and professionData.baseProfessionInfo.professionName,
		professionData and professionData.childProfessionInfo and professionData.childProfessionInfo.professionName,
		info and info.categoryName,
		info and info.recipeCategoryName,
		info and info.name,
	}
	for _, value in ipairs(candidates) do
		local lowered = string.lower(tostring(value or ""))
		for _, expansion in ipairs(EXPANSION_PATTERNS) do
			for _, pattern in ipairs(expansion.patterns) do
				if string.find(lowered, pattern, 1, true) then
					return expansion.tag
				end
			end
		end
	end

	local skillLineID = professionData and tonumber(professionData.skillLineID) or tonumber(professionData)
	if skillLineID and SKILL_LINE_EXPANSION[skillLineID] then
		return SKILL_LINE_EXPANSION[skillLineID]
	end

	return "legacy"
end

function AuctionHelper:GetCraftsAhCutFraction()
	local pct = tonumber(self:GetSetting("crafts.ahCutPercent", 5)) or 5
	pct = math.max(0, math.min(50, pct))
	return pct / 100
end

function AuctionHelper:ApplyAhCutToSaleCopper(copper)
	if not copper or copper ~= copper or copper <= 0 then
		return nil
	end
	local f = self:GetCraftsAhCutFraction()
	return copper * (1 - f)
end

local function schematicMaxQuality(recipeData)
	local sc = recipeData and recipeData.schematic
	if type(sc) == "table" then
		local mq = tonumber(sc.maxQuality)
		if mq and mq > 0 then
			return mq
		end
	end
	local outs = recipeData and recipeData.outputs
	local n = outs and outs.qualityVariants and #outs.qualityVariants or 0
	if n > 0 then
		return n
	end
	return 1
end

--- Reachable output quality index (1..maxQ) from stored operation snapshot (no concentration).
local function reachableQualityIndex(crafting, maxQ)
	maxQ = math.max(1, tonumber(maxQ) or 1)
	if not crafting or type(crafting) ~= "table" then
		return 1
	end
	local totalSkill = (tonumber(crafting.baseSkill) or 0) + (tonumber(crafting.bonusSkill) or 0)
	local diff = tonumber(crafting.baseDifficulty) or 0
	if diff <= 0 then
		local g = tonumber(crafting.guaranteedCraftingQualityID)
		if g and g >= 1 and g <= maxQ then
			return math.min(maxQ, math.floor(g))
		end
		return 1
	end
	local thresholds = crafting.qualityThresholds
	if type(thresholds) ~= "table" or #thresholds == 0 then
		local g = tonumber(crafting.guaranteedCraftingQualityID)
		if g and g >= 1 and g <= maxQ then
			return math.min(maxQ, math.floor(g))
		end
		return 1
	end
	local tier = 1
	for _, th in ipairs(thresholds) do
		local t = tonumber(th)
		if t and totalSkill >= t then
			tier = tier + 1
		end
	end
	if tier > maxQ then
		tier = maxQ
	end
	local g = tonumber(crafting.guaranteedCraftingQualityID)
	if g and g >= 1 then
		tier = math.max(tier, math.min(maxQ, math.floor(g)))
	end
	return math.max(1, math.min(maxQ, tier))
end

local function outputItemForQuality(recipeData, qualityIndex)
	local outs = recipeData and recipeData.outputs
	if not outs then
		return nil, nil
	end
	local variants = outs.qualityVariants
	if type(variants) == "table" and #variants > 0 then
		local idx = math.max(1, math.min(#variants, tonumber(qualityIndex) or 1))
		local v = variants[idx]
		if v and v.itemID then
			return tonumber(v.itemID), tonumber(v.qualityIndex) or idx
		end
	end
	local pid = AuctionHelper:RecipeOutputsPrimaryItemId(outs)
	return tonumber(pid), 1
end

local function currentOperationTotalSkill(crafting)
	if type(crafting) ~= "table" then
		return 0
	end
	local base = tonumber(crafting.baseSkill) or 0
	local bonus = tonumber(crafting.bonusSkill) or 0
	return base + bonus
end

local function targetQualityRequiredSkill(crafting, _maxQ, targetQualityIndex)
	targetQualityIndex = math.max(1, math.floor(tonumber(targetQualityIndex) or 1))
	if targetQualityIndex <= 1 then
		return 0
	end
	local thresholds = crafting and crafting.qualityThresholds or nil
	if type(thresholds) ~= "table" then
		return nil
	end
	local idx = math.min(#thresholds, targetQualityIndex - 1)
	return tonumber(thresholds[idx])
end

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

local function estimatePlanSkillFromReagentPlan(crafting, plan)
	local currentTotal = currentOperationTotalSkill(crafting)
	local maxExtra = tonumber(crafting and crafting.requiredReagentSkillDelta) or 0
	if maxExtra <= 0 then
		return currentTotal
	end
	local weightedScore, totalWeight = 0, 0
	for _, entry in ipairs(plan or {}) do
		local qty = tonumber(entry and entry.quantityRequired) or 0
		local chosenQ = tonumber(entry and entry.qualityChoice)
		local slotMaxQ = tonumber(entry and entry.slotMaxQuality)
		if qty > 0 and chosenQ and slotMaxQ and slotMaxQ > 1 then
			local norm = math.max(0, math.min(1, (chosenQ - 1) / (slotMaxQ - 1)))
			weightedScore = weightedScore + (norm * qty)
			totalWeight = totalWeight + qty
		end
	end
	if totalWeight <= 0 then
		return currentTotal
	end
	return currentTotal + (weightedScore / totalWeight) * maxExtra
end

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

local function recipeDisplayName(recipeData)
	local info = AuctionHelper:RecipeDataInfo(recipeData)
	return (info and info.name) and tostring(info.name) or "Recipe"
end

local function recipeCategoryId(recipeData)
	local info = AuctionHelper:RecipeDataInfo(recipeData)
	if not info then
		return nil
	end
	return tonumber(info.categoryID or info.recipeCategoryID)
end

local function categoryInfoName(info)
	local name = info and (info.name or info.categoryName)
	if name and tostring(name) ~= "" then
		return tostring(name)
	end
	return nil
end

local function categoryNodeName(node)
	return categoryInfoName(node and node.info or nil)
end

--- Name of entry's subcategory with categoryID (falls back to entry's own name).
local function subCategoryName(entry, categoryID)
	for _, subCategory in ipairs((entry and entry.subCategories) or {}) do
		if tonumber(subCategory and subCategory.categoryID) == tonumber(categoryID) then
			return categoryNodeName(subCategory) or categoryNodeName(entry)
		end
	end
	return nil
end

local function subCategoryIdParentName(entry, categoryID)
	for _, subCategoryID in ipairs((entry and entry.subCategoryIDs) or {}) do
		if tonumber(subCategoryID) == tonumber(categoryID) then
			return categoryNodeName(entry)
		end
	end
	return nil
end

--- Category name from the stored profession category tree; nil when unknown or nameless.
local function storedCategoryName(professionData, categoryID)
	for _, entry in ipairs((professionData and professionData.categories) or {}) do
		if tonumber(entry and entry.categoryID) == tonumber(categoryID) then
			return categoryNodeName(entry)
		end
		local name = subCategoryName(entry, categoryID) or subCategoryIdParentName(entry, categoryID)
		if name then
			return name
		end
	end
	return nil
end

local function liveCategoryName(categoryID)
	if not (C_TradeSkillUI and C_TradeSkillUI.GetCategoryInfo) then
		return nil
	end
	return categoryInfoName(AuctionHelper:SafeCall(C_TradeSkillUI.GetCategoryInfo, categoryID))
end

local function recipeCategoryName(recipeData, professionData)
	local info = AuctionHelper:RecipeDataInfo(recipeData)
	if info then
		local directName = info.categoryName or info.recipeCategoryName or info.category
		if directName and tostring(directName) ~= "" then
			return tostring(directName)
		end
	end
	local categoryID = recipeCategoryId(recipeData)
	if not categoryID then
		return nil
	end
	return storedCategoryName(professionData, categoryID) or liveCategoryName(categoryID)
end

local function resolveCategoryLabelFromProfessionCategory(categoryEntry, categoryID)
	if not categoryEntry then
		return nil
	end
	local function joinPath(parts)
		local out = {}
		for _, part in ipairs(parts) do
			if part and part ~= "" then
				out[#out + 1] = part
			end
		end
		if #out == 0 then
			return nil
		end
		return table.concat(out, " / ")
	end

	local function walk(node, targetID, path)
		if not node then
			return nil
		end
		local nextPath = {}
		for i = 1, #path do
			nextPath[i] = path[i]
		end
		nextPath[#nextPath + 1] = categoryNodeName(node)

		if tonumber(node.categoryID) == tonumber(targetID) then
			return joinPath(nextPath)
		end
		for _, child in ipairs(node.subCategories or {}) do
			local found = walk(child, targetID, nextPath)
			if found then
				return found
			end
		end
		for _, childID in ipairs(node.subCategoryIDs or {}) do
			if tonumber(childID) == tonumber(targetID) then
				return joinPath(nextPath)
			end
		end
		return nil
	end

	return walk(categoryEntry, categoryID, {})
end

function AuctionHelper:ResolveCraftCategoryLabel(skillLineID, categoryID)
	self:InitDB()
	local cid = tonumber(categoryID)
	if not cid then
		return nil
	end
	for _, characterData in pairs(self.db.characters or {}) do
		for _, professionData in pairs(characterData.professions or {}) do
			if tonumber(professionData.skillLineID) == tonumber(skillLineID) then
				for _, categoryEntry in ipairs(professionData.categories or {}) do
					local label = resolveCategoryLabelFromProfessionCategory(categoryEntry, cid)
					if label and label ~= "" then
						return label
					end
				end
			end
		end
	end
	return nil
end

local function containsText(haystack, needle)
	return string.find(string.lower(tostring(haystack or "")), needle, 1, true) ~= nil
end

local function craftCharacterLabel(pe, characterKey)
	return pe:GetDashboardSidebarCharacterLabel(characterKey, pe.db and pe.db.characters and pe.db.characters[characterKey], pe:GetCharacterKey())
end

local function craftIsEnchantRecipe(professionData, recipeData)
	local outs = recipeData and recipeData.outputs
	local recipeType = tonumber(outs and outs.recipeType)
	if Enum and Enum.TradeskillRecipeType and recipeType == tonumber(Enum.TradeskillRecipeType.Enchant) then
		return true
	end
	-- Fallback: some clients/scans store Enchant as recipeType 3 without a reliable Enum match.
	if recipeType == 3 then
		local info = AuctionHelper:RecipeDataInfo(recipeData)
		local recipeName = string.lower(tostring(info and info.name or ""))
		if string.find(recipeName, "enchant", 1, true) ~= nil then
			return true
		end
	end
	if containsText(professionData and professionData.professionName, "enchant") then
		local info = AuctionHelper:RecipeDataInfo(recipeData)
		local recipeName = string.lower(tostring(info and info.name or ""))
		return string.find(recipeName, "enchant", 1, true) ~= nil
	end
	return false
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

local function classifyCraftReagentSlot(professionData, recipeData, slot)
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
		if craftIsEnchantRecipe(professionData, recipeData) then
			return "required_target"
		end
		return "required_target"
	end

	if slot and slot.optional == true then
		-- Enchanting vellum/gear slots are usually optional in the schematic.
		if craftIsEnchantRecipe(professionData, recipeData) then
			return "required_target"
		end
		return "optional"
	end

	-- Enchant recipes with an unlabeled non-basic/non-finishing slot: treat as target.
	if craftIsEnchantRecipe(professionData, recipeData) then
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
				local p = tonumber((unitPriceFn(id)))
				if p and (not bestPrice or p < bestPrice) then
					bestPrice = p
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
local function ensureEnchantingVellumInPlan(plan, professionData, recipeData, forceReplace)
	if not craftIsEnchantRecipe(professionData, recipeData) then
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
			slotLabel = "Target item",
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

--- Resolve a craftable output item ID when schematic/scan data has none (common for enchants).
local function resolveCraftOutputItemID(self, recipeID, recipeData, opts)
	opts = opts or {}
	recipeID = tonumber(recipeID) or tonumber(self:GetRecipeSpellID(recipeData))
	if not recipeID or not C_TradeSkillUI or not C_TradeSkillUI.GetRecipeOutputItemData then
		return nil
	end

	local attempts = {}
	-- Prefer vellum allocation for enchant recipes so Blizzard returns the scroll item.
	if opts.forceEnchantingVellum or craftIsEnchantRecipe(opts.professionData, recipeData) then
		attempts[#attempts + 1] = {
			{ itemID = ENCHANTING_VELLUM_ITEM_ID, quantity = 1 },
		}
	end
	attempts[#attempts + 1] = {}

	for _, reagents in ipairs(attempts) do
		local ok, outputData = pcall(C_TradeSkillUI.GetRecipeOutputItemData, recipeID, reagents)
		if ok then
			local id = extractOutputItemIDFromApiResult(outputData)
			if id then
				return id
			end
		end
	end
	return nil
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

function AuctionHelper:GetCraftRecommendedCrafter(row)
	if not row or not row.bestCharacterKey then
		return nil, nil
	end
	local ev = row.perChar and row.perChar[row.bestCharacterKey] or nil
	local reason = ev and ev.profit ~= nil and "Best profit" or "Fallback available"
	return craftCharacterLabel(self, row.bestCharacterKey), reason
end

--- Aggregate item totals across all stored character snapshots.
function AuctionHelper:BuildAccountItemInventoryTotals(itemID)
	self:InitDB()
	itemID = tonumber(itemID)
	local totals = { bags = 0, bank = 0, warband = 0, total = 0 }
	if not itemID then
		return totals
	end
	for _, characterData in pairs(self.db.characters or {}) do
		local inv = characterData.inventorySnapshot and characterData.inventorySnapshot.items
		local entry = inv and inv[tostring(itemID)]
		if entry then
			totals.bags = totals.bags + (tonumber(entry.bags) or 0)
			totals.bank = totals.bank + (tonumber(entry.bank) or 0)
			totals.warband = totals.warband + (tonumber(entry.warband) or 0)
			totals.total = totals.total + (tonumber(entry.total) or 0)
		end
	end
	return totals
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
function AuctionHelper:PickCheapestReagentsPerSlot(recipeData, professionData, unitPriceFn, opts)
	local slots = self:RecipeDataSlots(recipeData)
	local plan = {}
	opts = opts or {}
	if type(slots) ~= "table" or type(unitPriceFn) ~= "function" then
		return plan
	end

	local overrideBySlot = buildPlanIndexBySlot(opts.reagentPlanOverride)
	local enchantRecipe = craftIsEnchantRecipe(professionData, recipeData)
	local forceVellum = enchantRecipe and opts.forceEnchantingVellum == true

	for _, slot in ipairs(slots) do
		local qty = tonumber(slot.quantityRequired) or 0
		local slotClass = classifyCraftReagentSlot(professionData, recipeData, slot)
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
		ensureEnchantingVellumInPlan(plan, professionData, recipeData, forceVellum)
	end
	return plan
end

-- Target-quality planning state `st`: recipeData, professionData, unitPriceFn, opts, crafting, maxQ,
-- targetQualityIndex, basePlan; collectTargetQualitySlots adds qualitySlots, staticPlan, totalWeight.
local function addQualityChoiceSlot(st, slot, slotClass, qty)
	local choices = buildBestReagentChoicesPerSlot(slot, st.unitPriceFn)
	if #choices == 0 then
		return
	end
	local maxQuality = tonumber(choices[#choices].quality) or 1
	st.qualitySlots[#st.qualitySlots + 1] = {
		slot = slot,
		slotClass = slotClass,
		qty = qty,
		maxQuality = maxQuality,
		choices = choices,
		weight = qty,
	}
	st.totalWeight = st.totalWeight + qty
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

local function addStaticTargetSlot(st, slot, slotClass, qty, override)
	local isTarget = slotClass == "required_target"
	local prefer = (st.enchantRecipe and isTarget) and ENCHANTING_VELLUM_ITEM_ID or nil
	local itemID = override and tonumber(override.itemID) or pickReagentForSlot(slot, st.unitPriceFn, prefer)
	if st.forceVellum and isTarget then
		itemID = ENCHANTING_VELLUM_ITEM_ID
	end
	if itemID then
		st.staticPlan[#st.staticPlan + 1] = staticTargetPlanEntry(slot, slotClass, qty, override, itemID)
	end
end

local function addTargetQualitySlot(st, slot)
	local qty = tonumber(slot.quantityRequired) or 0
	local slotClass = classifyCraftReagentSlot(st.professionData, st.recipeData, slot)
	local override = st.overrideBySlot[tostring(slot.slotIndex)]
	if st.forceVellum and slotClass == "required_target" then
		override = nil
	end
	if not reagentSlotIncluded(qty, slotClass, slot, override) then
		return
	end
	if slotClass == "mandatory_base" and not override then
		addQualityChoiceSlot(st, slot, slotClass, qty)
	else
		addStaticTargetSlot(st, slot, slotClass, qty, override)
	end
end

--- Split slots into quality-choice slots (unpinned basic mats) and a static plan (targets, overrides).
local function collectTargetQualitySlots(st, slots)
	st.overrideBySlot = buildPlanIndexBySlot(st.opts.reagentPlanOverride)
	st.enchantRecipe = craftIsEnchantRecipe(st.professionData, st.recipeData)
	st.forceVellum = st.enchantRecipe and st.opts.forceEnchantingVellum == true
	st.qualitySlots, st.staticPlan, st.totalWeight = {}, {}, 0
	for _, slot in ipairs(slots) do
		addTargetQualitySlot(st, slot)
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

local function buildTargetQualityPlan(st, selection)
	local out = clonePlanEntries(st.staticPlan)
	for slotIdx, choice in ipairs(selection or {}) do
		out[#out + 1] = targetQualityPlanEntry(st.qualitySlots[slotIdx], choice)
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
local function searchTargetQualityPlan(st, needFraction)
	local qualitySlots = st.qualitySlots
	local bestPlan, bestCost = nil, math.huge
	local targetWeightedScore = math.max(0, needFraction) * st.totalWeight
	local chosen = {}
	local function recurse(idx, weightedScore, weightedCost)
		if weightedCost >= bestCost then
			return
		end
		if idx > #qualitySlots then
			if weightedScore + 1e-6 >= targetWeightedScore then
				bestCost = weightedCost
				bestPlan = buildTargetQualityPlan(st, chosen)
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

local function targetQualitySearchBlocked(st, targetSkill, maxExtra)
	return st.totalWeight <= 0 or #st.qualitySlots == 0 or not targetSkill or maxExtra <= 0
end

--- Plan for a rank above the reachable one; returns plan, reachable.
local function planForHigherTargetQuality(self, st)
	local crafting = st.crafting
	local currentTotal = currentOperationTotalSkill(crafting)
	local targetSkill = targetQualityRequiredSkill(crafting, st.maxQ, st.targetQualityIndex)
	local maxExtra = tonumber(crafting and (crafting.requiredReagentSkillDelta or 0)) or 0
	local slots = self:RecipeDataSlots(st.recipeData)
	if type(slots) ~= "table" then
		return st.basePlan, false
	end
	collectTargetQualitySlots(st, slots)
	local maxPlan = buildTargetQualityPlan(st, maxQualitySelection(st.qualitySlots))
	if targetQualitySearchBlocked(st, targetSkill, maxExtra) then
		return (#maxPlan > 0 and maxPlan or st.basePlan), false
	end
	local needFraction = (targetSkill - currentTotal) / maxExtra
	if needFraction > 1 then
		return maxPlan, false
	end
	local bestPlan = searchTargetQualityPlan(st, needFraction)
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

function AuctionHelper:ComputeMatCostForReagentPlan(plan, unitPriceFn, sourceMode, getInventoryTotalsFn)
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

function AuctionHelper:ReagentPlanMeetsInventory(plan, getInventoryTotalsFn)
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

function AuctionHelper:ProfessionRecipeIsVendorSourced(recipeID, recipeData)
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

-- EvaluateCraftScenario helpers share one context table `c` (inputs + intermediate results).
local function resolveCraftEvalQuality(self, c)
	local recipeData = c.recipeData
	local info = self:RecipeDataInfo(recipeData)
	c.learned = not (info and info.learned == false)
	c.maxQ = schematicMaxQuality(recipeData)
	c.crafting = recipeData.crafting
	c.baseQ = reachableQualityIndex(c.crafting, c.maxQ)
	c.defaultScenarioQ = c.baseQ
	if c.scenario == "concentration" and c.baseQ < c.maxQ then
		c.defaultScenarioQ = math.min(c.maxQ, c.baseQ + 1)
	end
	c.qualityIndex = math.max(1, math.min(c.maxQ, tonumber(c.opts.targetQualityIndex) or c.defaultScenarioQ))
end

local function resolveCraftEvalOutputItem(self, c)
	local outputItemID = select(1, outputItemForQuality(c.recipeData, c.qualityIndex))
	if not outputItemID then
		outputItemID = resolveCraftOutputItemID(self, c.recipeID, c.recipeData, {
			forceEnchantingVellum = c.opts.forceEnchantingVellum == true,
			professionData = c.professionData,
		})
	end
	if not outputItemID and c.opts.allowMissingOutput then
		-- Shopping/queue still needs a stable key; recipe spell id is unique per line.
		outputItemID = tonumber(self:GetRecipeSpellID(c.recipeData)) or tonumber(c.recipeID)
	end
	c.outputItemID = outputItemID
	return outputItemID
end

local function craftEvalVendorBuyCopper(self, c, id)
	if not c.vendorRecipe then
		return nil
	end
	local vb = self:GetItemVendorPurchaseCopper(id)
	if vb and vb > 0 then
		return vb
	end
	return nil
end

local function craftEvalSaleUnit(self, c, id)
	local vb = craftEvalVendorBuyCopper(self, c, id)
	if vb then
		return vb, "Vendor"
	end
	return self:GetMarketEstimateCopper(id, c.tsmMarket, c.fallbackTsm)
end

local function craftEvalMatUnit(self, c, id)
	local vb = craftEvalVendorBuyCopper(self, c, id)
	if vb then
		return vb, "Vendor"
	end
	if c.useLedgerMats then
		local ledgerAvg = self:LedgerAverageUnitBuyCopper(id, nil)
		if ledgerAvg then
			return ledgerAvg, "Ledger"
		end
	end
	local marketEstimate, marketSource = self:GetMarketEstimateCopper(id, c.tsmMat, c.fallbackTsm)
	if marketEstimate and marketEstimate > 0 then
		return marketEstimate, marketSource
	end
	return nil, nil
end

local function craftEvalPickUnit(self, c, id)
	if c.sourceMode == "market_only" then
		return craftEvalSaleUnit(self, c, id)
	end
	return self:CheapestMaterialUnit(id, craftEvalMatUnit(self, c, id))
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
local function bindCraftEvalPricing(self, c)
	local tsm = self:GetTsmPriceStrings()
	c.tsmMarket, c.fallbackTsm, c.tsmMat = tsm.market, tsm.fallback, tsm.material
	local costBasis = c.opts.costBasis or "auto"
	c.useLedgerMats = costBasis == "ledger" or costBasis == "auto"
	c.saleUnitFn = function(id) return craftEvalSaleUnit(self, c, id) end
	c.pickUnitFn = function(id) return craftEvalPickUnit(self, c, id) end
	c.costUnitFn = function(id) return craftEvalPickUnit(self, c, id) end
	c.inventoryFn = newCraftEvalInventoryLookup(self)
end

local function resolveCraftEvalPlan(self, c)
	local forceVellum = c.opts.forceEnchantingVellum == true
	local plan, qualityReachable = self:PickCheapestReagentsPerSlotForTargetQuality(
		c.recipeData, c.professionData, c.pickUnitFn, c.qualityIndex,
		{ reagentPlanOverride = c.opts.reagentPlanOverride, forceEnchantingVellum = forceVellum }
	)
	if not plan then
		return nil
	end
	if forceVellum then
		ensureEnchantingVellumInPlan(plan, c.professionData, c.recipeData, true)
	end
	c.plan, c.qualityReachable = plan, qualityReachable
	c.usesRequiredTarget = reagentPlanHasRequiredTarget(plan)
	return plan
end

--- saleBasis ledger/auto: replace a market (not vendor) sale price with the ledger sell average.
local function applyCraftEvalLedgerSale(self, c, saleGross, saleSrc)
	local saleBasis = c.opts.saleBasis or "auto"
	if not (saleGross and saleSrc ~= "Vendor sell" and saleBasis ~= "market" and (saleBasis == "ledger" or saleBasis == "auto")) then
		return saleGross, saleSrc
	end
	local avgs, n = self:LedgerAverageUnitSellCopper(c.outputItemID, nil)
	if avgs and n and n >= 1 then
		return avgs, "ledger"
	end
	return saleGross, saleSrc
end

local function resolveCraftEvalSale(self, c)
	local saleGross, saleSrc = self:GetMarketEstimateCopper(c.outputItemID, c.tsmMarket, c.fallbackTsm)
	if c.vendorRecipe then
		local vs = self:GetItemVendorSellCopper(c.outputItemID)
		if vs and vs > 0 then
			saleGross = vs
			saleSrc = "Vendor sell"
		end
	end
	saleGross, saleSrc = applyCraftEvalLedgerSale(self, c, saleGross, saleSrc)
	c.saleGross, c.saleSrc = saleGross, saleSrc
	c.saleNet = saleGross and self:ApplyAhCutToSaleCopper(saleGross) or nil
end

local function resolveCraftEvalConcentration(c)
	c.concCost = tonumber(c.crafting and c.crafting.concentrationCost) or nil
	if c.qualityReachable == false and c.qualityIndex > c.baseQ then
		c.concentrationNeeded, c.concentrationSkillShortfall =
			estimateConcentrationNeeded(c.crafting, c.maxQ, c.baseQ, c.qualityIndex, c.plan)
	end
end

local function craftEvalProfitBlocked(c)
	if c.matMissingPrice or not c.saleGross then
		return true
	end
	return c.qualityReachable == false and (c.scenario ~= "concentration" or not c.concentrationNeeded)
end

local function resolveCraftEvalProfit(c)
	c.matPerCraft = c.fullMatCost or c.oopMatCost
	local matPerCraft = c.matPerCraft
	local profit = (c.saleNet and matPerCraft) and (c.saleNet * c.outQty - matPerCraft) or nil
	resolveCraftEvalConcentration(c)
	if craftEvalProfitBlocked(c) then
		profit = nil
	end
	c.profit = profit
	c.roi = (profit and matPerCraft and matPerCraft > 0) and (profit / matPerCraft) * 100 or nil
end

local function craftEvalBaseSaleCopper(self, c)
	local baseItem = select(1, outputItemForQuality(c.recipeData, c.baseQ))
	if not baseItem then
		return nil
	end
	local baseSale
	if c.vendorRecipe then
		baseSale = self:GetItemVendorSellCopper(baseItem)
	end
	if not baseSale then
		baseSale = select(1, self:GetMarketEstimateCopper(baseItem, c.tsmMarket, c.fallbackTsm))
	end
	return baseSale
end

--- Extra profit of the upgraded rank per concentration point (concentration scenario only).
local function craftEvalProfitPerConcentration(self, c)
	if not (c.scenario == "concentration" and c.concCost and c.concCost > 0 and c.baseQ < c.maxQ) then
		return nil
	end
	local baseSale = craftEvalBaseSaleCopper(self, c)
	local baseNet = baseSale and self:ApplyAhCutToSaleCopper(baseSale)
	local _, missConc = self:ComputeMatCostForReagentPlan(cloneReagentPlan(c.plan), c.saleUnitFn, c.sourceMode, c.inventoryFn)
	if not missConc and c.saleNet and baseNet then
		local dProfit = (c.saleNet - baseNet) * c.outQty
		return dProfit / c.concCost
	end
	return nil
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

local function buildCraftEvalResult(self, c)
	local recipeID, recipeData, professionData, plan = c.recipeID, c.recipeData, c.professionData, c.plan
	local ck = c.characterKey
	local exportRecipeID = self:GetRecipeExportID(recipeData) or tonumber(recipeID) or recipeID
	local recipeSpellID = self:GetRecipeSpellID(recipeData) or tonumber(recipeID) or recipeID
	local usesTarget = c.usesRequiredTarget
	local targetItemID, targetAuto = craftEvalRequiredTarget(plan, usesTarget)
	return {
		characterKey = ck, recipeID = exportRecipeID, recipeSpellID = recipeSpellID,
		recipeName = recipeDisplayName(recipeData),
		professionName = professionData.professionName, skillLineID = professionData.skillLineID,
		expansionTag = self:GetCraftExpansionTag(professionData, recipeData, c.outputItemID),
		learned = c.learned, qualityIndex = c.qualityIndex, baseQualityIndex = c.baseQ,
		scenarioBaseQualityIndex = c.defaultScenarioQ, qualityReachable = c.qualityReachable ~= false,
		outputItemID = c.outputItemID, outputQty = c.outQty, outputIcon = c.outputDesc and c.outputDesc.icon,
		matCost = c.matPerCraft, outOfPocketMatCost = c.oopMatCost, fullMatCost = c.fullMatCost,
		matMissingPrice = c.matMissingPrice, saleGross = c.saleGross, saleNet = c.saleNet, saleSource = c.saleSrc,
		profit = c.profit, roi = c.roi, coverage = c.coverage, canCraftNow = c.canCraftNow, reagentPlan = plan,
		concentrationCost = c.concCost, concentrationNeeded = c.concentrationNeeded,
		concentrationSkillShortfall = c.concentrationSkillShortfall, profitPerConcentration = c.profitPerConc,
		categoryID = recipeCategoryId(recipeData), categoryName = recipeCategoryName(recipeData, professionData),
		scanAt = self.db.characters[ck] and self.db.characters[ck].scanFinishedAt,
		enchantUsesVellum = usesTarget, requiredTargetReagent = usesTarget,
		requiredTargetReagentItemID = targetItemID, requiredTargetReagentAuto = targetAuto,
		liveSelectedPlan = reagentPlanContainsLiveSelection(plan),
	}
end

--- Evaluate one character's learned recipe for a specific quality target.
function AuctionHelper:EvaluateCraftScenario(characterKey, professionData, recipeID, recipeData, opts)
	opts = opts or {}
	local c = {
		characterKey = characterKey, professionData = professionData, recipeID = recipeID, recipeData = recipeData,
		opts = opts, scenario = opts.scenario or "default", sourceMode = opts.sourceMode or "owned_first",
	}
	resolveCraftEvalQuality(self, c)
	if not resolveCraftEvalOutputItem(self, c) then
		return nil
	end
	c.vendorRecipe = self:ProfessionRecipeIsVendorSourced(recipeID, recipeData)
	c.outputDesc = self:ResolveItemDescriptor(c.outputItemID)
	bindCraftEvalPricing(self, c)
	if not resolveCraftEvalPlan(self, c) then
		return nil
	end
	c.oopMatCost, c.matMissingPrice, c.coverage, c.fullMatCost =
		self:ComputeMatCostForReagentPlan(c.plan, c.costUnitFn, c.sourceMode, c.inventoryFn)
	c.outQty = math.max(1, self:GetRecipeOutputQuantityForCost(recipeData))
	resolveCraftEvalSale(self, c)
	resolveCraftEvalProfit(c)
	c.profitPerConc = craftEvalProfitPerConcentration(self, c)
	c.canCraftNow = c.learned and c.qualityReachable ~= false and self:ReagentPlanMeetsInventory(c.plan, c.inventoryFn)
	return buildCraftEvalResult(self, c)
end

-- Prefer OrderView schematic when Crafting Orders tab is showing an order.
function AuctionHelper:GetOpenProfessionSchematicForm()
	if not self.IS_SUPPORTED then
		return nil
	end
	local pf = _G.ProfessionsFrame
	if not pf then
		return nil
	end
	if self.IS_RETAIL then
		local ordersPage = pf.OrdersPage
		if ordersPage and ordersPage.IsShown and ordersPage:IsShown() then
			local orderView = ordersPage.OrderView
			local orderForm = orderView and orderView.OrderDetails and orderView.OrderDetails.SchematicForm
			if orderForm and (not orderForm.IsShown or orderForm:IsShown()) then
				return orderForm
			end
		end
	end
	local form = pf.CraftingPage and pf.CraftingPage.SchematicForm
	if form and (not form.IsShown or form:IsShown()) then
		return form
	end
	return form
end

function AuctionHelper:GetOpenCraftingOrder()
	if not self.IS_RETAIL then
		return nil
	end
	local pf = _G.ProfessionsFrame
	local ordersPage = pf and pf.OrdersPage
	if not (ordersPage and ordersPage.IsShown and ordersPage:IsShown()) then
		return nil
	end
	local orderView = ordersPage.OrderView
	local order = orderView and orderView.order
	if type(order) == "table" and tonumber(order.orderID) and tonumber(order.spellID) then
		return order
	end
	return nil
end

-- Build reagent plan from currently selected allocations in Blizzard's transaction.
-- Returns nil when no usable live allocations are available.
function AuctionHelper:BuildLiveSelectedReagentPlanForOpenRecipe(recipeData)
	if not self.IS_SUPPORTED then
		return nil
	end
	local form = self:GetOpenProfessionSchematicForm()
	if not form or not form.GetTransaction then
		return nil
	end
	local transaction = form:GetTransaction()
	if not transaction or type(transaction.GetAllocations) ~= "function" then
		return nil
	end

	local slots = self:RecipeDataSlots(recipeData)
	if type(slots) ~= "table" or #slots == 0 then
		return nil
	end

	local plan = {}
	for _, slot in ipairs(slots) do
		local slotIndex = slot and slot.slotIndex
		local qty = tonumber(slot and slot.quantityRequired) or 0
		if slotIndex and qty > 0 then
			local allocations = transaction:GetAllocations(slotIndex)
			if type(allocations) == "table" and #allocations > 0 then
				local first = allocations[1]
				local reagent = first and first.GetReagent and first:GetReagent() or nil
				local itemID = reagent and tonumber(reagent.itemID)
				if itemID then
					plan[#plan + 1] = {
						itemID = itemID,
						quantityRequired = qty,
						slotIndex = slotIndex,
						slotClass = classifyCraftReagentSlot(nil, recipeData, slot),
						liveSelected = true,
					}
				end
			end
		end
	end
	if #plan == 0 then
		return nil
	end
	return plan
end

local function boolToken(value)
	return value and "1" or "0"
end

local function getCraftEvaluationSettings(self)
	local tsm = self:GetTsmPriceStrings()
	return {
		scenario = tostring(self:GetSetting("crafts.scenario", "default")),
		sourceMode = tostring(self:GetSetting("crafts.reagentSourceMode", "owned_first")),
		costBasis = tostring(self:GetSetting("crafts.costBasis", "auto")),
		saleBasis = tostring(self:GetSetting("crafts.saleBasis", "auto")),
		ahCutPercent = tonumber(self:GetSetting("crafts.ahCutPercent", 5)) or 5,
		metricRange = tostring(self:GetSetting("inventory.metricRange", "30d")),
		economyShowColumns = self:GetSetting("inventory.economyShowColumns", true) ~= false,
		economyUseAuctionatorFallback = self:GetSetting("integrations.economyUseAuctionatorFallback", true) ~= false,
		tsmMarketString = tsm.market,
		tsmFallbackString = tsm.fallback,
		tsmMatString = tsm.material,
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
		tostring(settings.ahCutPercent),
		settings.metricRange,
		boolToken(settings.economyShowColumns),
		boolToken(settings.economyUseAuctionatorFallback),
		settings.tsmMarketString,
		settings.tsmFallbackString,
		settings.tsmMatString,
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

--- Unique sorted item IDs for AH pricing: outputs + reagents from stored learned recipes.
--- opts.characterKey: restrict to one character; default = all characters in db.
function AuctionHelper:BuildCraftEconomyItemIDs(opts)
	self:InitDB()
	opts = type(opts) == "table" and opts or {}
	local includeOptional = self:GetSetting("auction.craftScanIncludeOptionalSlots", false) == true
	local scopeKey = opts.characterKey and tostring(opts.characterKey) or nil
	local seen = {}
	local function add(id)
		id = tonumber(id)
		if id and id > 0 then
			seen[id] = true
		end
	end

	for characterKey, characterData in pairs(self.db.characters or {}) do
		if not scopeKey or tostring(characterKey) == scopeKey then
			for _, professionData in pairs(characterData.professions or {}) do
				for _, recipeData in pairs(professionData.recipes or {}) do
					local info = self:RecipeDataInfo(recipeData)
					if info and info.learned ~= false then
						local outs = recipeData.outputs
						if outs then
							add(self:RecipeOutputsPrimaryItemId(outs))
							if type(outs.qualityVariants) == "table" then
								for _, variant in ipairs(outs.qualityVariants) do
									add(variant and variant.itemID)
								end
							end
						end
						local slots = self:RecipeDataSlots(recipeData)
						if type(slots) == "table" then
							for _, slot in ipairs(slots) do
								local slotClass = classifyCraftReagentSlot(professionData, recipeData, slot)
								local include = false
								if slotClass == "mandatory_base" or slotClass == "required_target" then
									include = true
								elseif slotClass == "optional" and includeOptional then
									include = true
								end
								if include and type(slot.reagents) == "table" then
									for _, reagent in ipairs(slot.reagents) do
										add(reagent and reagent.itemID)
									end
								end
							end
						end
					end
				end
			end
		end
	end

	local ids = {}
	for id in pairs(seen) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	return ids
end

--- Targets for AH search queue: itemID plus optional auction item-key fields when present on stored outputs.
function AuctionHelper:BuildCraftEconomyAuctionTargets(opts)
	opts = type(opts) == "table" and opts or {}
	local ids = self:BuildCraftEconomyItemIDs(opts)
	local targets = {}
	for _, id in ipairs(ids) do
		targets[#targets + 1] = { itemID = id, itemKeyFields = nil }
	end
	return targets
end

local function applyCraftEvalWorkItem(self, settings, w, byKey, roiIndex)
	local characterKey, professionData, recipeID, recipeData = w[1], w[2], w[3], w[4]
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

local function finalizeCraftOpportunityRowsFromBuckets(self, settings, byKey, roiIndex)
	local rows = {}
	local histMemo = {}
	for _, bucket in pairs(byKey) do
		local bestChar, bestProfit = nil, nil
		for ck, ev in pairs(bucket.perChar) do
			local p = ev.profit
			if p ~= nil and (bestProfit == nil or p > bestProfit) then
				bestProfit = p
				bestChar = ck
			end
		end
		if not bestChar then
			bestChar = next(bucket.perChar) -- no priced character: any one (first pairs() key)
		end
		local ev = bestChar and bucket.perChar[bestChar]
		if ev then
			local hist = self:GetItemHistoryStatsMemo(bucket.outputItemID, "market", settings.metricRange, histMemo)
			local stale = not ev.saleGross
			local thin = (hist.count or 0) < 2
			local badges = {}
			if stale then badges[#badges + 1] = "no_price" end
			if thin and not stale then badges[#badges + 1] = "thin_history" end
			if ev.matMissingPrice then badges[#badges + 1] = "missing_mats_price" end
			if ev.qualityReachable == false then
				badges[#badges + 1] = ev.concentrationNeeded and "needs_concentration" or "rank_unreachable"
			end
			if ev.canCraftNow then badges[#badges + 1] = "craftable" end
			if (ev.profit or 0) > 0 and not ev.canCraftNow and not ev.matMissingPrice and ev.qualityReachable ~= false then badges[#badges + 1] = "gold_locked" end
			if ev.requiredTargetReagent then
				badges[#badges + 1] = ev.requiredTargetReagentAuto and "target_auto" or "target_selected"
			end
			if settings.scenario == "concentration" and (tonumber(ev.concentrationCost) or 0) > 0 then badges[#badges + 1] = "concentration" end

			bucket.bestCharacterKey = bestChar
			bucket.profit = ev.profit
			bucket.roi = ev.roi
			bucket.matCost = ev.matCost
			bucket.outOfPocketMatCost = ev.outOfPocketMatCost
			bucket.fullMatCost = ev.fullMatCost
			bucket.saleNet = ev.saleNet
			bucket.saleSource = ev.saleSource
			bucket.qualityIndex = ev.qualityIndex
			bucket.coverage = ev.coverage
			bucket.canCraftNow = ev.canCraftNow
			bucket.qualityReachable = ev.qualityReachable
			bucket.matMissingPrice = ev.matMissingPrice
			bucket.profitPerConcentration = ev.profitPerConcentration
			bucket.concentrationCost = ev.concentrationCost
			bucket.concentrationNeeded = ev.concentrationNeeded
			bucket.concentrationSkillShortfall = ev.concentrationSkillShortfall
			bucket.outputQty = ev.outputQty
			bucket.badges = badges
			bucket.enchantUsesVellum = ev.enchantUsesVellum
			bucket.requiredTargetReagent = ev.requiredTargetReagent
			bucket.requiredTargetReagentItemID = ev.requiredTargetReagentItemID
			bucket.requiredTargetReagentAuto = ev.requiredTargetReagentAuto
			bucket.sourceRecipeName = bucket.recipeName
			bucket.freshnessNote = ev.concentrationNeeded and "Needs concentration"
				or (ev.qualityReachable == false and "Target rank unreachable" or (stale and "No TSM/Auc price" or (thin and "Thin AH history" or "OK")))
			bucket.confidence = self:ResolveCraftConfidenceState(ev, "scan_row")
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

function AuctionHelper:InvalidateCraftOpportunityCaches()
	local state = self:GetState()
	abortCraftEvalAsyncBuild(state)
	state.craftsEvaluationCacheKey = nil
	state.craftOpportunityRowsCacheKey = nil
	state.craftOpportunityCostIndexCacheKey = nil
	state.craftOpportunityRoiIndexCacheKey = nil
	state.craftOpportunityRows = nil
	state.craftOpportunityCostIndex = nil
	state.craftOpportunityRoiIndex = nil
end

function AuctionHelper:CraftEvalProcessNextChunk(gen)
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
			AuctionHelper:BuildCraftOpportunityRows()
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

function AuctionHelper:BuildCraftOpportunityRows(opts)
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

function AuctionHelper:FilterCraftRows(rows, filters)
	return self.FilterLogic.FilterCraftRows(rows, filters)
end

function AuctionHelper:GetCraftProfessionFilterOptions()
	self:InitDB()
	local seen = {}
	local opts = { { value = "all", label = "All professions" } }
	for _, characterData in pairs(self.db.characters or {}) do
		for skillLineID, professionData in pairs(characterData.professions or {}) do
			local sid = tostring(skillLineID)
			if not seen[sid] then
				seen[sid] = true
				opts[#opts + 1] = {
					value = sid,
					label = professionData.professionName or sid,
				}
			end
		end
	end
	table.sort(opts, function(a, b)
		if a.value == "all" then
			return true
		end
		if b.value == "all" then
			return false
		end
		return tostring(a.label) < tostring(b.label)
	end)
	return opts
end

function AuctionHelper:GetCraftCategoryFilterOptions(rows)
	local seen = {}
	local opts = { { value = "all", label = "All categories" } }
	for _, row in ipairs(rows or {}) do
		local cid = row.categoryID
		if cid and not seen[cid] then
			seen[cid] = true
			local label = row.categoryName and tostring(row.categoryName)
			if not label or label == "" then
				label = self:ResolveCraftCategoryLabel(row.skillLineID, cid)
			end
			if not label or label == "" then
				label = "Category " .. tostring(cid)
			end
			opts[#opts + 1] = { value = tostring(cid), label = label }
		end
	end
	table.sort(opts, function(a, b)
		if a.value == "all" then
			return true
		end
		if b.value == "all" then
			return false
		end
		return tostring(a.label) < tostring(b.label)
	end)
	return opts
end

function AuctionHelper:ResolveCraftConfidenceState(eval, dataSource)
	if not eval then
		return "stale_scan"
	end
	if not eval.saleGross then
		return "missing_sale_price"
	end
	if eval.matMissingPrice then
		return "missing_mat_price"
	end
	if dataSource == "scan_fallback_live" then
		return "stale_scan"
	end
	return "ok"
end

function AuctionHelper:FindCraftOpportunityRowForRecipe(recipeID, outputItemID)
	if not recipeID or not outputItemID then
		return nil
	end
	local rows = self:BuildCraftOpportunityRows({ forceSync = true })
	for _, row in ipairs(rows) do
		if tonumber(row.outputItemID) == tonumber(outputItemID)
			and (tonumber(row.recipeID) == tonumber(recipeID)
				or tonumber(row.recipeSpellID) == tonumber(recipeID)) then
			return row
		end
	end
	return nil
end

local function recipeDataHasUsableOutput(recipeData)
	if not recipeData then
		return false
	end
	local outs = recipeData.outputs
	if not outs then
		return false
	end
	if tonumber(AuctionHelper:RecipeOutputsPrimaryItemId(outs)) then
		return true
	end
	for _, variant in ipairs(outs.qualityVariants or {}) do
		if tonumber(variant and variant.itemID) then
			return true
		end
	end
	return false
end

--- Prefer live C_TradeSkillUI data when the profession window is open; else last scanned recipe blob for this character.
function AuctionHelper:GetLiveOrScannedRecipeDataForOpenProfession(recipeID)
	recipeID = tonumber(recipeID)
	if not recipeID then
		return nil, nil
	end
	local rd = self:CollectRecipeData(recipeID)
	if rd and recipeDataHasUsableOutput(rd) then
		return rd, "live"
	end
	self:InitDB()
	local ck = self:GetCharacterKey()
	local charData = self.db.characters[ck]
	if not charData then
		return nil, nil
	end
	local profInfo = C_TradeSkillUI.GetProfessionInfoByRecipeID and C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)
	local lineId = profInfo and tonumber(profInfo.professionID or profInfo.skillLineID)
	local professionData = lineId and charData.professions[tostring(lineId)]
	if not professionData or type(professionData.recipes) ~= "table" then
		for _, pdata in pairs(charData.professions or {}) do
			local _, found = self:FindStoredRecipe(pdata, recipeID)
			if found then
				professionData = pdata
				break
			end
		end
	end
	if not professionData or type(professionData.recipes) ~= "table" then
		return nil, nil
	end
	local _, stored = self:FindStoredRecipe(professionData, recipeID)
	if stored then
		local ds = "scan"
		if C_TradeSkillUI.IsTradeSkillReady and C_TradeSkillUI.IsTradeSkillReady() then
			ds = "scan_fallback_live"
		end
		return stored, ds
	end
	return nil, nil
end

function AuctionHelper:GetProfessionDescriptorForOpenRecipe(recipeID)
	recipeID = tonumber(recipeID)
	if not recipeID then
		return nil
	end
	local profByRecipe = C_TradeSkillUI.GetProfessionInfoByRecipeID and C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)
	local targetLine = profByRecipe and tonumber(profByRecipe.professionID or profByRecipe.skillLineID)
	if not targetLine then
		local baseInfo = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo() or nil
		targetLine = tonumber(baseInfo and (baseInfo.professionID or baseInfo.profession or baseInfo.skillLineID))
	end
	if not targetLine then
		return nil
	end
	for _, desc in ipairs(self:GetPlayerProfessions()) do
		if tonumber(desc.skillLineID) == targetLine then
			return {
				professionIndex = desc.professionIndex,
				skillLineID = desc.skillLineID,
				professionName = desc.professionName,
				currentLevelName = desc.currentLevelName,
				skillLevel = desc.skillLevel,
				maxSkillLevel = desc.maxSkillLevel,
				bonusSkill = desc.bonusSkill,
				icon = desc.icon,
			}
		end
	end
	return {
		skillLineID = targetLine,
		professionName = tostring(profByRecipe and profByRecipe.professionName or "Profession"),
		currentLevelName = "",
		skillLevel = 0,
		maxSkillLevel = 0,
		bonusSkill = 0,
		icon = nil,
	}
end

--- UI may expose a spell/skill-line ability id; scans and C_TradeSkillUI use TradeSkillRecipe id. Prefer info.recipeID when GetRecipeInfo succeeds.
function AuctionHelper:NormalizeTradeSkillRecipeId(candidate)
	candidate = tonumber(candidate)
	if not candidate or candidate <= 0 then
		return nil
	end
	if C_TradeSkillUI.GetRecipeInfo then
		local info = C_TradeSkillUI.GetRecipeInfo(candidate)
		if info then
			local rid = tonumber(info.recipeID)
			if rid and rid > 0 then
				return rid
			end
		end
	end
	return candidate
end

local function positiveNumber(value)
	value = tonumber(value)
	return value and value > 0 and value or nil
end

function AuctionHelper:GetOpenProfessionRecipeID()
	if not self.IS_SUPPORTED then
		return nil
	end
	-- Crafting Orders tab: prefer the open order's spell, not the stale Recipes-tab selection.
	local openOrder = self.GetOpenCraftingOrder and self:GetOpenCraftingOrder() or nil
	if openOrder and tonumber(openOrder.spellID) then
		return self:NormalizeTradeSkillRecipeId(openOrder.spellID)
	end
	local form = self.GetOpenProfessionSchematicForm and self:GetOpenProfessionSchematicForm() or nil
	if form then
		if form.GetRecipeInfo then
			local info = form:GetRecipeInfo()
			local recipeID = info and tonumber(info.recipeID)
			if recipeID and recipeID > 0 then
				return self:NormalizeTradeSkillRecipeId(recipeID)
			end
		end
		local transaction = form.GetTransaction and form:GetTransaction() or nil
		local recipeID = self:FirstValueFrom(transaction, { "GetRecipeID", "GetRecipeSchematicID" }, nil, positiveNumber)
			or self:FirstValueFrom(form, nil, { "recipeID", "selectedRecipeID" }, positiveNumber)
		if recipeID then
			return self:NormalizeTradeSkillRecipeId(recipeID)
		end
	end
	if C_TradeSkillUI.GetSelectedRecipeID then
		local selected = tonumber(C_TradeSkillUI.GetSelectedRecipeID())
		if selected and selected > 0 then
			return self:NormalizeTradeSkillRecipeId(selected)
		end
	end
	local page = _G.ProfessionsFrame and _G.ProfessionsFrame.CraftingPage
	local pageRecipeID = self:FirstValueFrom(page, nil, { "selectedRecipeID", "recipeID" }, positiveNumber)
	return pageRecipeID and self:NormalizeTradeSkillRecipeId(pageRecipeID) or nil
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

--- Live evaluation for the recipe selected in Blizzard's profession UI (same rules as Crafts tab).
function AuctionHelper:EvaluateSelectedProfessionRecipe()
	self:InitDB()
	if not self.IS_SUPPORTED then
		return nil, "not_supported"
	end
	if C_TradeSkillUI.IsTradeSkillReady and not C_TradeSkillUI.IsTradeSkillReady() then
		return nil, "not_ready"
	end
	local recipeID = self:GetOpenProfessionRecipeID()
	if not recipeID then
		return nil, "no_recipe"
	end

	local recipeData, dataSource = self:GetLiveOrScannedRecipeDataForOpenProfession(recipeID)
	if not recipeData then
		return nil, "no_data", { recipeID = recipeID }
	end

	local professionData = self:GetProfessionDescriptorForOpenRecipe(recipeID)
	if not professionData then
		return nil, "no_profession"
	end

	local ck = self:GetCharacterKey()
	local liveScenario = self:GetOpenProfessionScenario()
	local opts = {
		scenario = liveScenario,
		sourceMode = self:GetSetting("crafts.reagentSourceMode", "owned_first"),
		costBasis = self:GetSetting("crafts.costBasis", "auto"),
		saleBasis = self:GetSetting("crafts.saleBasis", "auto"),
	}
	local livePlan = self:BuildLiveSelectedReagentPlanForOpenRecipe(recipeData)
	if livePlan and #livePlan > 0 then
		opts.reagentPlanOverride = livePlan
	end
	local eval = self:EvaluateCraftScenario(ck, professionData, recipeID, recipeData, opts)
	if not eval then
		return nil, "no_eval"
	end

	local opportunityRow = self:FindCraftOpportunityRowForRecipe(recipeID, eval.outputItemID)
	local recommendedLabel, recommendedReason
	if opportunityRow then
		recommendedLabel, recommendedReason = self:GetCraftRecommendedCrafter(opportunityRow)
	else
		recommendedLabel = self:GetDashboardSidebarCharacterLabel(ck, self.db.characters and self.db.characters[ck], ck)
	end

	local confidence = self:ResolveCraftConfidenceState(eval, dataSource)

	return {
		recipeID = recipeID,
		professionData = professionData,
		characterKey = ck,
		scenario = liveScenario,
		eval = eval,
		opportunityRow = opportunityRow,
		recommendedCrafterLabel = recommendedLabel,
		recommendedCrafterReason = recommendedReason,
		dataSource = dataSource,
		confidence = confidence,
	}, "ok"
end

--- Build an eval context for shopping/queue for a recipe (forces Enchanting Vellum for enchants).
--- `opts`: { skillLineID, skipSelect }. Returns the context and "ok", or nil and a reason.
function AuctionHelper:BuildProfessionRecipeQueueContext(recipeID, opts)
	self:InitDB()
	opts = opts or {}
	if not self.IS_SUPPORTED then
		return nil, "not_supported"
	end
	recipeID = tonumber(recipeID) or self:GetOpenProfessionRecipeID()
	if not recipeID then
		return nil, "no_recipe"
	end

	if not opts.skipSelect then
		local openID = self:GetOpenProfessionRecipeID()
		if openID ~= recipeID and self.JumpToProfessionRecipe then
			self:JumpToProfessionRecipe(recipeID, opts.skillLineID)
		end
	end

	if C_TradeSkillUI.IsTradeSkillReady and not C_TradeSkillUI.IsTradeSkillReady() then
		return nil, "not_ready"
	end

	local recipeData, dataSource = self:GetLiveOrScannedRecipeDataForOpenProfession(recipeID)
	if not recipeData then
		return nil, "no_data"
	end

	local professionData = self:GetProfessionDescriptorForOpenRecipe(recipeID)
	if not professionData then
		return nil, "no_profession"
	end

	local ck = self:GetCharacterKey()
	local liveScenario = (self.GetOpenProfessionScenario and self:GetOpenProfessionScenario())
		or self:GetSetting("crafts.scenario", "default")
	local evalOpts = {
		scenario = liveScenario,
		sourceMode = self:GetSetting("crafts.reagentSourceMode", "owned_first"),
		costBasis = self:GetSetting("crafts.costBasis", "auto"),
		saleBasis = self:GetSetting("crafts.saleBasis", "auto"),
		forceEnchantingVellum = true,
		allowMissingOutput = true,
	}
	-- Keep live selections for mandatory mats, but forceEnchantingVellum strips target overrides.
	local livePlan = self:BuildLiveSelectedReagentPlanForOpenRecipe(recipeData)
	if livePlan and #livePlan > 0 then
		evalOpts.reagentPlanOverride = livePlan
	end

	local eval = self:EvaluateCraftScenario(ck, professionData, recipeID, recipeData, evalOpts)
	if not eval then
		-- Fall back to the side-panel eval (same recipe) and force vellum onto its plan.
		local last = self._lastProfessionEvalContext
		if type(last) == "table"
			and tonumber(last.recipeID) == tonumber(recipeID)
			and type(last.eval) == "table"
		then
			eval = last.eval
			if type(eval.reagentPlan) == "table" then
				eval.reagentPlan = cloneReagentPlan(eval.reagentPlan)
			else
				eval.reagentPlan = {}
			end
		else
			return nil, "no_eval"
		end
	end

	-- Shopping always assumes vellum for enchants, whichever eval the plan came from.
	if craftIsEnchantRecipe(professionData, recipeData) and type(eval.reagentPlan) == "table" then
		ensureEnchantingVellumInPlan(eval.reagentPlan, professionData, recipeData, true)
		eval.requiredTargetReagent = true
		eval.requiredTargetReagentItemID = ENCHANTING_VELLUM_ITEM_ID
		eval.requiredTargetReagentAuto = true
		eval.enchantUsesVellum = true
	end

	local opportunityRow = self:FindCraftOpportunityRowForRecipe(recipeID, eval.outputItemID)
	local recommendedLabel
	if opportunityRow then
		recommendedLabel = select(1, self:GetCraftRecommendedCrafter(opportunityRow))
	else
		recommendedLabel = self:GetDashboardSidebarCharacterLabel(ck, self.db.characters and self.db.characters[ck], ck)
	end

	return {
		recipeID = recipeID,
		professionData = professionData,
		characterKey = ck,
		scenario = liveScenario,
		eval = eval,
		opportunityRow = opportunityRow,
		recommendedCrafterLabel = recommendedLabel,
		dataSource = dataSource,
		confidence = self:ResolveCraftConfidenceState(eval, dataSource),
		recipeName = eval.recipeName,
		professionName = eval.professionName,
		skillLineID = eval.skillLineID or opts.skillLineID,
	}, "ok"
end

--- Add the open (or given) profession recipe to the craft/shopping queue.
--- Enchant recipes always queue Enchanting Vellum as the target reagent.
--- `opts`: { recipeID, skillLineID, quiet }. Returns the queue key, or nil and an error.
function AuctionHelper:QueueOpenProfessionRecipe(quantity, opts)
	opts = opts or {}
	quantity = math.max(1, math.floor(tonumber(quantity) or 1))
	local recipeID = tonumber(opts.recipeID) or self:GetOpenProfessionRecipeID()
	local ctx, reason = self:BuildProfessionRecipeQueueContext(recipeID, opts)
	if not ctx then
		if not opts.quiet then
			local msg = "Could not add recipe to shopping."
			if reason == "no_recipe" then
				msg = "No recipe selected to add to shopping."
			elseif reason == "no_data" then
				msg = "No stored data for this recipe — run a profession scan first."
			elseif reason == "no_eval" then
				msg = "Could not resolve materials for this recipe yet."
			elseif reason == "not_ready" then
				msg = "Profession UI not ready yet."
			end
			self:PrintMessage(msg)
		end
		return nil, reason or "failed"
	end

	if not self.AddCraftToQueue then
		return nil, "no_queue"
	end
	local key, err = self:AddCraftToQueue(ctx, quantity)
	if not key then
		if not opts.quiet then
			self:PrintMessage("Could not add recipe to shopping queue.")
		end
		return nil, err or "add_failed"
	end

	if not opts.quiet then
		local name = ctx.recipeName or ctx.eval and ctx.eval.recipeName or ("#" .. tostring(ctx.recipeID))
		self:PrintMessage(string.format("Queued %s x%d for shopping.", tostring(name), quantity))
	end
	if self.ScheduleRefreshProfessionCraftEconomyPanel then
		self:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
	end
	return key, nil
end
