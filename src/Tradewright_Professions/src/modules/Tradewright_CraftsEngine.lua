local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Craft basics the other Craft* files build on: expansion tags, AH cut, output quality ranks (Tradewright.CraftQuality), recommended crafter.

-- Expansion of a profession's skill line, for crafts whose output item has no expansion ID yet.
-- Each expansion's thirteen profession lines are one run of IDs (https://warcraft.wiki.gg/wiki/TradeSkillLineID).
-- IDs, not names: the names are translated by the client.
local SKILL_LINE_RANGES = {
	{ first = 2906, last = 2918, tag = "midnight" },
	{ first = 2871, last = 2883, tag = "tww" },
	{ first = 2822, last = 2834, tag = "df" },
}

local function skillLineExpansionTag(skillLineID)
	for _, range in ipairs(SKILL_LINE_RANGES) do
		if skillLineID >= range.first and skillLineID <= range.last then
			return range.tag
		end
	end
	return nil
end

function Tradewright:GetCraftExpansionTag(professionData, _, outputItemID)
	local desc = outputItemID and self:ResolveItemDescriptor(outputItemID) or nil
	local expansionID = desc and tonumber(desc.expansionID) or nil
	if expansionID then
		return self:ExpansionLeToFilterTag(expansionID)
	end

	-- The open expansion tier first (child profession, specialization line), then the stored line itself.
	local profession = type(professionData) == "table" and professionData or {}
	local child = type(profession.childProfessionInfo) == "table" and profession.childProfessionInfo or {}
	for _, id in ipairs({ child.professionID or 0, profession.primarySpecializationSkillLineID or 0, profession.skillLineID or professionData or 0 }) do
		local tag = skillLineExpansionTag(tonumber(id) or 0)
		if tag then
			return tag
		end
	end

	return "legacy"
end

function Tradewright:ApplyAhCutToSaleCopper(copper)
	if not copper or copper ~= copper or copper <= 0 then
		return nil
	end
	return copper * (1 - self:GetAuctionCut())
end

--- What one item got from salvaging counts for: the better of its AH price after the cut and its
--- vendor price. nil when it has neither.
function Tradewright:GetSalvagedItemValue(itemID)
	local value = math.max(self:ApplyAhCutToSaleCopper((self:GetMarketEstimateCopper(itemID))) or 0, self:GetItemVendorSellCopper(itemID) or 0)
	return value > 0 and value or nil
end

--- What disenchanting, prospecting or milling one `input` is worth (see SalvageLogic.Yield for
--- `input`): `{ value, basis, casts, inputsPerCast, unvalued }`, the value in copper per destroyed
--- item after the auction cut, `basis` and `casts` saying where the yield comes from, `inputsPerCast`
--- how many items one cast destroys (nil when not known), `unvalued` how many of the items it gives
--- have no price. nil when no yield is known or nothing it gives has a price.
function Tradewright:GetSalvageValue(action, input)
	local yield = self.GetSalvageYield and self:GetSalvageYield(action, input)
	if not yield then
		return nil
	end
	local value, unvalued = self.SalvageLogic.Value(yield, function(itemID)
		return self:GetSalvagedItemValue(itemID)
	end)
	if value <= 0 then
		return nil
	end
	return { value = value, basis = yield.basis, casts = yield.casts, inputsPerCast = yield.inputsPerCast, unvalued = unvalued }
end

-- Whether an item got from salvaging has a price, and the days of scans behind it: nil days for an
-- item valued at its vendor price, which needs no history.
local function salvagedItemPriceFacts(self, itemID)
	if (self:GetMarketEstimateCopper(itemID) or 0) > 0 then
		return true, self.GetItemPriceDays and self:GetItemPriceDays(itemID) or 0
	end
	return (self:GetItemVendorSellCopper(itemID) or 0) > 0, nil
end

--- How far the values of salvaging `inputs` can be trusted (see SalvageCheckLogic.Check):
--- `inputs` is a list of SalvageLogic inputs, one per item valued, so a kind held often weighs more.
function Tradewright:CheckSalvageValues(action, inputs)
	local yields = {}
	for _, input in ipairs(inputs) do
		local yield = self:GetSalvageYield(action, input)
		if yield then
			yield.kind = self.SalvageLogic.GroupKey(action, input)
			yields[#yields + 1] = yield
		end
	end
	return self.SalvageCheckLogic.Check({
		now = self:Now(), yields = yields,
		lastFullScanAt = self.GetLastFullAuctionScanAt and self:GetLastFullAuctionScanAt() or nil,
		priceOf = function(itemID)
			return salvagedItemPriceFacts(self, itemID)
		end,
	})
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
	local reason = evaluation and evaluation.profit ~= nil and L["Best profit"] or L["Fallback available"]
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
