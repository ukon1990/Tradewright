local _, AuctionHelper = ...

-- Plain-text detail panel for one Crafts tab row (split out of AuctionHelper_CraftsEngine.lua).

local ROW_REACH_FORMATS = { "|cffffff80+%s conc|r", "|cffffff80+conc|r", "|cffff8080Unreachable|r" }
local BEST_REACH_FORMATS = { "Status: +%s conc", "Status: +conc", "Status: unreachable" }
local CONFIDENCE_LINES = {
    " ",
    "|cffffffffConfidence|r",
    "Profit uses TSM/Auctionator where available, with ledger averages when enabled and data exists.",
    "Mats/profit use full market material cost; owned coverage and out-of-pocket spend are shown separately.",
    "Quality reachability is derived from the last profession scan (skill + thresholds), not live reagent swaps.",
}

local function craftCharacterName(pe, characterKey)
    local characterData = pe.db and pe.db.characters and pe.db.characters[characterKey] or nil
    if characterData and characterData.meta and characterData.meta.name then
        return tostring(characterData.meta.name)
    end
    return tostring(characterKey or "?")
end

local function appendLine(lines, line)
    if line then
        lines[#lines + 1] = line
    end
end

local function moneyOrDash(self, copper)
    return copper and self:FormatCopperShort(copper) or "-"
end

--- formats: { "+%s conc" pattern, "+conc" text, unreachable text } for an unreachable rank.
local function concentrationStatusText(self, evaluation, formats)
    if evaluation.concentrationNeeded then
        return string.format(formats[1], self:FormatNumberGrouped(evaluation.concentrationNeeded))
    elseif evaluation.concentrationCost and evaluation.concentrationCost > 0 then
        return formats[2]
    end
    return formats[3]
end

local function appendHeader(self, lines, row)
    local crafterLabel, crafterReason = self:GetCraftRecommendedCrafter(row)
    lines[#lines + 1] = "|cffffffff" .. tostring(row.outputName or "?") .. "|r"
    lines[#lines + 1] = string.format("Source: %s  |  Profession: %s", row.recipeName or "?", row.professionName or "?")
    lines[#lines + 1] = string.format(
        "Item: #%s  |  Rank %d  |  Expansion: %s",
        tostring(row.outputItemID), tonumber(row.qualityIndex) or 0, row.expansionTag or "?"
    )
    if row.qualityReachable == false then
        lines[#lines + 1] = concentrationStatusText(self, row, ROW_REACH_FORMATS)
    end
    if crafterLabel then
        lines[#lines + 1] = string.format("Recommended crafter: %s  |  %s", crafterLabel, crafterReason or "Best available")
    end
end

local function slotClassFlag(slot)
    if slot.slotClass == "required_target" then
        return slot.liveSelected and "target selected" or "target auto"
    elseif slot.slotClass == "optional" then
        return "optional selected"
    end
    return nil
end

local function reagentFlags(self, slot)
    local flags = {}
    appendLine(flags, slotClassFlag(slot))
    if slot.synthetic then
        flags[#flags + 1] = "legacy fallback"
    end
    if slot.priceUnit and slot.lineCost ~= nil then
        flags[#flags + 1] = string.format(
            "%s each via %s, total %s",
            self:FormatCopperShort(slot.priceUnit),
            tostring(slot.priceSource or "?"),
            self:FormatCopperShort(slot.lineCost)
        )
    end
    if (tonumber(slot.ownedQuantity) or 0) > 0 then
        flags[#flags + 1] = string.format("owned %s", self:FormatNumberGrouped(slot.ownedQuantity))
    end
    return flags
end

local function reagentLine(self, slot)
    local nm = self:GetItemDisplayName(slot.itemID)
    local inv = self:BuildAccountItemInventoryTotals(slot.itemID)
    local flags = reagentFlags(self, slot)
    local suffix = #flags > 0 and ("  [" .. table.concat(flags, ", ") .. "]") or ""
    return string.format(
        "  %s x%s  (account stock %s)%s",
        nm,
        self:FormatNumberGrouped(tonumber(slot.quantityRequired) or 0),
        self:FormatNumberGrouped(tonumber(inv.total) or 0),
        suffix
    )
end

local function appendMaterials(self, lines, row, best)
    local rank = tonumber(row.qualityIndex) or 0
    lines[#lines + 1] = " "
    if best and best.liveSelectedPlan then
        lines[#lines + 1] = string.format("|cffffffffMaterials (live selection + required slots for rank %d)|r", rank)
    else
        lines[#lines + 1] = string.format("|cffffffffMaterials (cheapest plan for rank %d)|r", rank)
    end
    if not (best and best.reagentPlan) then
        lines[#lines + 1] = "  (no plan)"
        return
    end
    for _, slot in ipairs(best.reagentPlan) do
        lines[#lines + 1] = reagentLine(self, slot)
    end
end

local function rankPlanLine(best)
    local rank, baseRank = tonumber(best.qualityIndex), tonumber(best.scenarioBaseQualityIndex)
    if not (best.scenarioBaseQualityIndex and baseRank and rank and rank > baseRank) then
        return nil
    end
    return string.format(
        "Chosen rank plan: upgraded materials selected to target rank %d (baseline scenario rank %d).", rank, baseRank
    )
end

local function concentrationLine(self, best)
    if not best.concentrationNeeded then
        return nil
    end
    local line = string.format("Conc: +%s", self:FormatNumberGrouped(best.concentrationNeeded))
    if best.concentrationSkillShortfall and best.concentrationSkillShortfall > 0 then
        line = line .. string.format("  |  skill shortfall %.1f", best.concentrationSkillShortfall)
    end
    return line
end

local function profitPerConcentrationLine(self, best)
    if not (best.profitPerConcentration and tonumber(best.qualityIndex or 0) > tonumber(best.baseQualityIndex or 0)) then
        return nil
    end
    return string.format("Profit / concentration: %s", self:FormatCopperShort(best.profitPerConcentration))
end

local function targetReagentLine(self, best)
    if not (best.requiredTargetReagent and best.requiredTargetReagentItemID) then
        return nil
    end
    return string.format(
        "Required target reagent: %s (%s).",
        self:GetItemDisplayName(best.requiredTargetReagentItemID),
        best.requiredTargetReagentAuto and "auto-selected from valid targets" or "taken from the live profession setup"
    )
end

local function appendEconomics(self, lines, best)
    lines[#lines + 1] = string.format(
        "Sale (net est.): %s  |  Mats: %s  |  Profit: %s",
        moneyOrDash(self, best.saleNet), moneyOrDash(self, best.matCost), moneyOrDash(self, best.profit)
    )
    if best.outOfPocketMatCost and best.outOfPocketMatCost ~= best.matCost then
        lines[#lines + 1] = string.format("Out-of-pocket mats in current source mode: %s", self:FormatCopperShort(best.outOfPocketMatCost))
    end
    if best.qualityReachable == false then
        lines[#lines + 1] = concentrationStatusText(self, best, BEST_REACH_FORMATS)
    end
    lines[#lines + 1] = string.format(
        "Output quantity: %s  |  ROI: %s  |  Coverage: %.0f%%",
        self:FormatNumberGrouped(best.outputQty or 1),
        best.roi and string.format("%.1f%%", best.roi) or "-",
        (best.coverage or 0) * 100
    )
    appendLine(lines, rankPlanLine(best))
    appendLine(lines, concentrationLine(self, best))
    appendLine(lines, profitPerConcentrationLine(self, best))
    appendLine(lines, targetReagentLine(self, best))
end

local function appendComparison(self, lines, row)
    lines[#lines + 1] = " "
    lines[#lines + 1] = "|cffffffffCharacter comparison|r"
    for characterKey, evaluation in pairs(row.perChar or {}) do
        lines[#lines + 1] = string.format(
            "%s  |  profit %s  |  Q%d  |  cov %.0f%%",
            craftCharacterName(self, characterKey), moneyOrDash(self, evaluation.profit),
            tonumber(evaluation.qualityIndex) or 0, (evaluation.coverage or 0) * 100
        )
    end
end

function AuctionHelper:BuildCraftDetailText(row)
    if not row then
        return "Select a craft row."
    end
    local best = row.bestCharacterKey and row.perChar[row.bestCharacterKey] or nil
    local lines = {}
    appendHeader(self, lines, row)
    appendMaterials(self, lines, row, best)
    lines[#lines + 1] = " "
    lines[#lines + 1] = "|cffffffffEconomics|r"
    if best then
        appendEconomics(self, lines, best)
    end
    appendComparison(self, lines, row)
    for _, line in ipairs(CONFIDENCE_LINES) do
        lines[#lines + 1] = line
    end
    return table.concat(lines, "\n")
end
