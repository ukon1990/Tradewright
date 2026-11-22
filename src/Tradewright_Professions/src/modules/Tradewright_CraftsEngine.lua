local _, Tradewright = ...

-- Craft basics the other Craft* files build on: expansion tags, AH cut, output quality ranks (Tradewright.CraftQuality), recommended crafter.

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

function Tradewright:GetCraftExpansionTag(professionData, recipeData, outputItemID)
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

function Tradewright:ApplyAhCutToSaleCopper(copper)
	if not copper or copper ~= copper or copper <= 0 then
		return nil
	end
	return copper * (1 - self:GetAuctionCut())
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
	local pid = Tradewright:RecipeOutputsPrimaryItemId(outs)
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

local function craftCharacterLabel(pe, characterKey)
	return pe:GetDashboardSidebarCharacterLabel(characterKey, pe.db and pe.db.characters and pe.db.characters[characterKey], pe:GetCharacterKey())
end

function Tradewright:GetCraftRecommendedCrafter(row)
	if not row or not row.bestCharacterKey then
		return nil, nil
	end
	local evaluation = row.perChar and row.perChar[row.bestCharacterKey] or nil
	local reason = evaluation and evaluation.profit ~= nil and "Best profit" or "Fallback available"
	return craftCharacterLabel(self, row.bestCharacterKey), reason
end

--- Aggregate item totals across all stored character snapshots.
function Tradewright:BuildAccountItemInventoryTotals(itemID)
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

Tradewright.CraftQuality = {
	schematicMaxQuality = schematicMaxQuality,
	reachableQualityIndex = reachableQualityIndex,
	outputItemForQuality = outputItemForQuality,
	currentOperationTotalSkill = currentOperationTotalSkill,
	targetQualityRequiredSkill = targetQualityRequiredSkill,
	estimatePlanSkillFromReagentPlan = estimatePlanSkillFromReagentPlan,
}
