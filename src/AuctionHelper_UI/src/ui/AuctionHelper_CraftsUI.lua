local addonName, ProfessionExporter = ...

local ROW_H = 20
local MAX_ROWS = 450
local DEFAULT_ICON = 134400

local function trim(s)
    if not s then
        return ""
    end
    return (string.gsub(tostring(s), "^%s*(.-)%s*$", "%1"))
end

local RANK_BADGE_PX = 16
local RANK_ICON_GAP = 4

local function formatCopperFull(pe, copper)
	return pe:FormatCopperFull(copper)
end

local function formatTimestamp(ts)
	if not ts or ts <= 0 then
		return "-"
	end
	return date("%Y-%m-%d %H:%M", ts)
end

local function isPlaceholderItemLabel(s)
    local t = trim(s)
    if t == "" or t == "?" then
        return true
    end
    return string.match(t, "^#%d+$") ~= nil
end

local function formatCraftConcentrationSuffix(pe, row)
    if not row or row.qualityReachable ~= false then
        return ""
    end
    if row.concentrationNeeded and row.concentrationNeeded > 0 then
        return "  |cffffff80(+" .. pe:FormatNumberGrouped(row.concentrationNeeded) .. " conc)|r"
    end
    if row.concentrationCost and row.concentrationCost > 0 then
        return "  |cffffff80(+conc)|r"
    end
    return "  |cffff8080(unreachable)|r"
end

local function formatCraftItemSourceCellText(pe, row, suffix)
    suffix = suffix or ""
    local reachSuffix = formatCraftConcentrationSuffix(pe, row)
    local itemLabel = trim(pe:GetItemDisplayName(row and row.outputItemID))
    local recipeLabel = trim(row and row.recipeName or "")
    if isPlaceholderItemLabel(itemLabel) and recipeLabel ~= "" then
        return recipeLabel .. reachSuffix .. suffix
    end
    if itemLabel ~= "" and itemLabel == recipeLabel then
        return itemLabel .. reachSuffix .. suffix
    end
    local left = itemLabel ~= "" and itemLabel or "?"
    local right = recipeLabel ~= "" and recipeLabel or "?"
    return left .. "  |cff7f8da3<- " .. right .. "|r" .. reachSuffix .. suffix
end

local function craftItemSourcePrimaryTitle(pe, row)
    if not row then
        return "Craft"
    end
    local itemLabel = trim(pe:GetItemDisplayName(row.outputItemID))
    local recipeLabel = trim(row.recipeName or "")
    if isPlaceholderItemLabel(itemLabel) and recipeLabel ~= "" then
        return recipeLabel
    end
    if itemLabel ~= "" and itemLabel == recipeLabel then
        return itemLabel
    end
    if not isPlaceholderItemLabel(itemLabel) and itemLabel ~= "" then
        return itemLabel
    end
    if recipeLabel ~= "" then
        return recipeLabel
    end
    if itemLabel ~= "" then
        return itemLabel
    end
    return "Craft"
end

local function applyRankBadge(texture, text, rankIndex)
    if not texture or not text or not rankIndex or rankIndex <= 0 then
        if texture then texture:Hide() end
        if text then text:Hide() end
        return
    end
    local atlas = "Professions-Icon-Quality-Tier" .. tostring(rankIndex) .. "-Inv"
    if texture.SetAtlas then
        texture:SetAtlas(atlas, true)
    end
    texture:SetSize(RANK_BADGE_PX, RANK_BADGE_PX)
    texture:Show()
    text:SetText(tostring(rankIndex))
    text:Show()
end

local function layoutCraftRecipeCellIcons(cell)
    if not cell or not cell.root or not cell.rankIcon or not cell.icon or not cell.text then
        return
    end
    local root, rankIcon, icon, text = cell.root, cell.rankIcon, cell.icon, cell.text
    local topPad = (ROW_H - RANK_BADGE_PX) / 2
    rankIcon:ClearAllPoints()
    icon:ClearAllPoints()
    text:ClearAllPoints()
    if rankIcon:IsShown() then
        rankIcon:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -topPad)
        icon:SetPoint("TOPLEFT", rankIcon, "TOPRIGHT", RANK_ICON_GAP, 0)
    else
        icon:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -topPad)
    end
    text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    text:SetPoint("RIGHT", root, "RIGHT", 0, 0)
end

function ProfessionExporter:CreateCraftRecipeCell(rowFrame)
    local root = CreateFrame("Frame", nil, rowFrame)
    root:SetHeight(ROW_H)

    local rankIcon = root:CreateTexture(nil, "OVERLAY")
    rankIcon:SetSize(RANK_BADGE_PX, RANK_BADGE_PX)
    rankIcon:Hide()

    local icon = root:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)

    local rankText = root:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rankText:SetPoint("CENTER", rankIcon, "CENTER", 0, 0)
    rankText:SetTextColor(1, 1, 1)
    rankText:Hide()

    local text = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)

    local cell = {
        root = root,
        icon = icon,
        rankIcon = rankIcon,
        rankText = rankText,
        text = text,
    }
    layoutCraftRecipeCellIcons(cell)
    return cell
end

function ProfessionExporter:GetCraftsColumnDefinitions()
    return {
        {
            id = "recipe",
            label = "Item / source",
            width = 272,
            minWidth = 140,
            flex = 4,
            sortable = true,
            defaultSort = "asc",
            lockVisible = true,
            defaultVisible = true,
            tooltipTitle = "Item / source",
            tooltipText = "Exact sellable output item with the source recipe shown inline.",
            createCell = function(rowFrame)
                return ProfessionExporter:CreateCraftRecipeCell(rowFrame)
            end,
            sortValue = function(row)
                return row.outputName or ""
            end,
            updateCell = function(cell, row)
                cell.icon:SetTexture(row.outputIcon or DEFAULT_ICON)
                applyRankBadge(cell.rankIcon, cell.rankText, row.qualityIndex)
                layoutCraftRecipeCellIcons(cell)
                local qn = ProfessionExporter:GetCraftQueueQuantityForOpportunityRow(row)
                local suffix = qn > 0 and ("  |cffffcc00(Q:" .. tostring(qn) .. ")|r") or ""
                cell.text:SetText(formatCraftItemSourceCellText(ProfessionExporter, row, suffix))
            end,
        },
        {
            id = "quality",
            label = "Q",
            width = 32,
            minWidth = 28,
            flex = 0,
            sortable = true,
            defaultSort = "desc",
            defaultVisible = true,
            tooltipTitle = "Quality",
            tooltipText = "Target output rank for this row. Unreachable ranks remain visible and are marked in the list/details.",
            sortValue = function(row)
                return row.qualityIndex or 0
            end,
            getText = function(row)
                local q = tostring(row.qualityIndex or "?")
                if row and row.qualityReachable == false then
                    return q .. ((row.concentrationNeeded or row.concentrationCost) and "C" or "!")
                end
                return q
            end,
        },
        {
            id = "profession",
            label = "Profession",
            width = 110,
            minWidth = 72,
            flex = 1,
            sortable = true,
            defaultSort = "asc",
            defaultVisible = true,
            tooltipTitle = "Profession",
            tooltipText = "Profession line that owns the recipe.",
            sortValue = function(row)
                return row.professionName or ""
            end,
            getText = function(row)
                return row.professionName or "?"
            end,
        },
        {
            id = "expansion",
            label = "Exp",
            width = 88,
            minWidth = 52,
            flex = 0,
            sortable = true,
            defaultSort = "asc",
            defaultVisible = true,
            tooltipTitle = "Expansion",
            tooltipText = "Expansion bucket inferred from scanned profession metadata, recipe metadata, and output item data.",
            sortValue = function(row)
                return row.expansionTag or ""
            end,
            getText = function(row)
                return row.expansionTag or "?"
            end,
        },
        {
            id = "sale",
            label = "Sale (net)",
            width = 120,
            minWidth = 72,
            flex = 0,
            sortable = true,
            defaultSort = "desc",
            defaultVisible = true,
            tooltipTitle = "Sale (net)",
            tooltipLines = {
                "Estimated sale value after the configured auction-house cut.",
                "Formula: sale estimate x (1 - AH cut).",
            },
            sortValue = function(row)
                return row.saleNet or -1
            end,
            getText = function(row)
                return row.saleNet and ProfessionExporter:FormatCopperShort(row.saleNet) or "-"
            end,
        },
        {
            id = "mats",
            label = "Mats",
            width = 120,
            minWidth = 72,
            flex = 0,
            sortable = true,
            defaultSort = "desc",
            defaultVisible = true,
            tooltipTitle = "Mats",
            tooltipLines = {
                "Estimated full market material cost for required slots plus any live-selected optional reagents.",
                "Owned coverage and out-of-pocket spend are tracked separately.",
                "Enchant rows auto-include required target reagents when needed for sellable outputs.",
            },
            sortValue = function(row)
                return row.matCost or -1
            end,
            getText = function(row)
                return row.matCost and ProfessionExporter:FormatCopperShort(row.matCost) or "-"
            end,
        },
        {
            id = "profit",
            label = "Profit",
            width = 120,
            minWidth = 72,
            flex = 0,
            sortable = true,
            defaultSort = "desc",
            defaultVisible = true,
            tooltipTitle = "Profit",
            tooltipLines = {
                "Estimated profit for the recommended crafter.",
                "Formula: sale net x output quantity - material cost.",
            },
            sortValue = function(row)
                return row.profit ~= nil and row.profit or -1e15
            end,
            getText = function(row)
                return row.profit and ProfessionExporter:FormatCopperShort(row.profit) or "-"
            end,
        },
        {
            id = "roi",
            label = "ROI%",
            width = 60,
            minWidth = 48,
            flex = 0,
            sortable = true,
            defaultSort = "desc",
            defaultVisible = true,
            tooltipTitle = "ROI%",
            tooltipText = "Return on investment for the recommended crafter. Formula: profit / material cost.",
            sortValue = function(row)
                return row.roi or -1e15
            end,
            getText = function(row)
                return row.roi and string.format("%.0f", row.roi) or "-"
            end,
        },
        {
            id = "coverage",
            label = "Owned",
            width = 64,
            minWidth = 52,
            flex = 0,
            sortable = true,
            defaultSort = "desc",
            defaultVisible = true,
            tooltipTitle = "Owned coverage",
            tooltipText = "Percentage of the recommended crafter reagent plan already covered by account inventory.",
            sortValue = function(row)
                local ev = row.bestCharacterKey and row.perChar and row.perChar[row.bestCharacterKey]
                return ev and (ev.coverage or 0) or 0
            end,
            getText = function(row)
                local ev = row.bestCharacterKey and row.perChar and row.perChar[row.bestCharacterKey]
                local c = ev and ev.coverage
                return c and string.format("%.0f%%", c * 100) or "-"
            end,
        },
    }
end

function ProfessionExporter:BuildCraftsTableColumns()
	local columns = {}
	for _, definition in ipairs(self:GetCraftsColumnDefinitions()) do
		local column = {}
		for key, value in pairs(definition) do
			column[key] = value
		end
		column.visible = true
		columns[#columns + 1] = column
	end
	return columns
end

--- Among opportunities with this output item, prefer the highest profit (stable tie: first in list order).
function ProfessionExporter:SelectCraftOpportunityByOutputItemID(itemID)
	itemID = tonumber(itemID)
	if not itemID or itemID <= 0 then
		return nil
	end
	local ui = self.ui or {}
	local function pickBest(rows)
		local best, bestProfit = nil, nil
		for _, r in ipairs(rows or {}) do
			if r and tonumber(r.outputItemID) == itemID then
				local p = tonumber(r.profit)
				if not best then
					best = r
					bestProfit = p
				elseif p and (not bestProfit or p > bestProfit) then
					best = r
					bestProfit = p
				end
			end
		end
		return best
	end
	local row = pickBest(ui.craftsWorkingRows)
	if row then
		return row
	end
	return pickBest(ui.craftsUnfilteredRows)
end

function ProfessionExporter:LayoutCraftsPanel(panel)
	if not panel then
		return
	end
	local width = math.max(840, panel:GetWidth() - 20)
	local detailsOpen = self:GetSetting("crafts.detailsOpen", true)
	local c = self:GetDetailPaneLayoutConstants()
	local savedDetailW = tonumber(self:GetSetting("crafts.detailsWidth", 340)) or 340
	local detailsWidth = detailsOpen and self:ClampDetailsWidthForPanel(panel, savedDetailW) or 0
	if detailsOpen and math.abs(savedDetailW - detailsWidth) >= 1 then
		self:SetSetting("crafts.detailsWidth", math.floor(detailsWidth + 0.5))
	end
	local gap = c.gapAfterSplitter
	local splitterW = c.splitterWidth

	panel.headerCard:ClearAllPoints()
	panel.headerCard:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
	panel.headerCard:SetSize(width, 96)
	panel.headerTitle:SetWidth(width - 320)
	panel.headerSubtitle:SetWidth(width - 320)
	panel.headerSummary:SetWidth(width - 320)
	panel.refreshButton:ClearAllPoints()
	panel.refreshButton:SetPoint("TOPRIGHT", panel.headerCard, "TOPRIGHT", -12, -12)

	panel.scenarioDropdown:SetPoint("TOPRIGHT", panel.refreshButton, "BOTTOMRIGHT", 18, -2)
	panel.sourceDropdown:SetPoint("RIGHT", panel.scenarioDropdown, "LEFT", -8, 0)
	panel.basisDropdown:SetPoint("RIGHT", panel.sourceDropdown, "LEFT", -8, 0)
	if panel.craftsRangeDropdown then
		panel.craftsRangeDropdown:SetPoint("RIGHT", panel.basisDropdown, "LEFT", -8, 0)
	end

	panel.filterCard:ClearAllPoints()
	panel.filterCard:SetPoint("TOPLEFT", panel.headerCard, "BOTTOMLEFT", 0, -10)
	panel.filterCard:SetSize(width, 86)

	panel.tableCard:ClearAllPoints()
	panel.tableCard:SetPoint("TOPLEFT", panel.filterCard, "BOTTOMLEFT", 0, -10)
	panel.tableCard:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
	panel.tableCard:SetWidth(width - (detailsOpen and (detailsWidth + splitterW + gap) or 0))

	if detailsOpen then
		if panel.detailsSplitter then
			panel.detailsSplitter:Show()
			panel.detailsSplitter:ClearAllPoints()
			panel.detailsSplitter:SetPoint("TOPLEFT", panel.tableCard, "TOPRIGHT", 0, 0)
			panel.detailsSplitter:SetPoint("BOTTOMLEFT", panel.tableCard, "BOTTOMRIGHT", 0, 0)
			panel.detailsSplitter:SetWidth(splitterW)
		end
		panel.detailCard:Show()
		panel.detailCard:ClearAllPoints()
		panel.detailCard:SetPoint("TOPLEFT", panel.detailsSplitter or panel.tableCard, "TOPRIGHT", gap, 0)
		panel.detailCard:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
		local queueReserve = 280
		if panel.queueCard then
			panel.queueCard:SetHeight(queueReserve)
			panel.queueCard:ClearAllPoints()
			panel.queueCard:SetPoint("BOTTOMLEFT", panel.detailCard, "BOTTOMLEFT", 8, 8)
			panel.queueCard:SetPoint("BOTTOMRIGHT", panel.detailCard, "BOTTOMRIGHT", -8, 8)
		end
		if panel.craftsDetailGraphBlock then
			panel.craftsDetailGraphBlock:ClearAllPoints()
			panel.craftsDetailGraphBlock:SetPoint("TOPLEFT", panel.detailMeta, "BOTTOMLEFT", 0, -8)
		end
		if panel.detailActions then
			panel.detailActions:ClearAllPoints()
			local graphShown = panel.craftsDetailGraphBlock and panel.craftsDetailGraphBlock:IsShown()
			if graphShown then
				panel.detailActions:SetPoint("TOPLEFT", panel.craftsDetailGraphBlock, "BOTTOMLEFT", 0, -6)
				panel.detailActions:SetPoint("TOPRIGHT", panel.craftsDetailGraphBlock, "BOTTOMRIGHT", 0, -6)
			else
				panel.detailActions:SetPoint("TOPLEFT", panel.detailMeta, "BOTTOMLEFT", 0, -6)
				panel.detailActions:SetPoint("TOPRIGHT", panel.detailMeta, "BOTTOMRIGHT", 0, -6)
			end
			panel.detailActions:SetHeight(30)
		end
		if panel.detailScroll then
			panel.detailScroll:ClearAllPoints()
			panel.detailScroll:SetPoint("TOPLEFT", panel.detailActions, "BOTTOMLEFT", 0, -6)
			panel.detailScroll:SetPoint("BOTTOMRIGHT", panel.detailCard, "BOTTOMRIGHT", -28, 16 + queueReserve)
		end
	else
		if panel.detailsSplitter then
			panel.detailsSplitter:Hide()
		end
		panel.detailCard:Hide()
	end

	if panel.craftsTable and panel.craftsTable.frame then
		panel.craftsTable.frame:ClearAllPoints()
		panel.craftsTable.frame:SetPoint("TOPLEFT", panel.tableCard, "TOPLEFT", 10, -34)
		panel.craftsTable.frame:SetPoint("BOTTOMRIGHT", panel.tableCard, "BOTTOMRIGHT", -10, 10)
	end

	if detailsOpen then
		self:ApplyDetailPaneContentWidths(panel, detailsWidth, {
			padLeft = 6,
			scrollRightPad = 28,
			titleRightReserve = 36,
			iconColumnWide = 76,
			closeButtonReserve = 34,
			rankBadgeReserve = 22,
		})
		self:LayoutDetailPaneHeaderRow(panel)
		if panel.queueSummary then
			panel.queueSummary:SetWidth(math.max(160, detailsWidth - 20))
		end
		if panel.queueBody then
			panel.queueBody:SetWidth(math.max(160, detailsWidth - 32))
		end
		if panel.queueContent then
			panel.queueContent:SetWidth(math.max(140, detailsWidth - 36))
		end
	end

	local ui = self.ui
	if ui and ui.craftsSearchBox then
		ui.craftsProfitDropdown:ClearAllPoints()
		ui.craftsProfitDropdown:SetPoint("TOPLEFT", ui.craftsSearchBox, "BOTTOMLEFT", -6, -36)

		local categoryOnTopRow = false
		local expansionRight = ui.craftsExpansionDropdown:GetRight()
		local filterRight = panel.filterCard:GetRight()
		local spacing = 8
		if expansionRight and filterRight then
			local available = filterRight - expansionRight - 12
			local needed = ui.craftsCategoryDropdown:GetWidth() + spacing + ui.craftsClearBtn:GetWidth()
			categoryOnTopRow = available >= needed
		end

		ui.craftsCategoryDropdown:ClearAllPoints()
		ui.craftsClearBtn:ClearAllPoints()
		if categoryOnTopRow then
			ui.craftsCategoryDropdown:SetPoint("TOPLEFT", ui.craftsExpansionDropdown, "TOPRIGHT", spacing, 0)
			ui.craftsClearBtn:SetPoint("TOPLEFT", ui.craftsCategoryDropdown, "TOPRIGHT", spacing, 12)
			panel.filterCard:SetHeight(86)
		else
			ui.craftsCategoryDropdown:SetPoint("TOPLEFT", ui.craftsExpansionDropdown, "BOTTOMLEFT", 0, -8)
			ui.craftsClearBtn:SetPoint("LEFT", ui.craftsCategoryDropdown, "RIGHT", spacing, 0)
			panel.filterCard:SetHeight(120)
		end
	end

	if panel.craftsTable and panel.craftsTable.Refresh then
		panel.craftsTable:Refresh()
	end
end

function ProfessionExporter:RenderCraftsDetails(row)
	local panel = self.ui and self.ui.craftsPanel
	if not panel or not panel.detailBody then
		return
	end
	local ui = self.ui
	local itemOnlyID = ui and (not row) and ui.craftsItemDetailOnlyItemID and tonumber(ui.craftsItemDetailOnlyItemID) or nil
	if ui then
		ui.craftsSelectedRowData = row
		if row then
			ui.craftsItemDetailOnlyItemID = nil
		end
	end

	local function applyOutputItemDetail(outputItemID, craftTextPrefix, graphItemIDOverride)
		self:InitDB()
		local rankMap = self:BuildOutputItemQualityRankIndex(ui.craftsCharacterFilterValues or {})
		local detailId = tonumber(graphItemIDOverride) or tonumber(outputItemID)
		local detail = self:BuildItemDetailSnapshot(detailId, {
			selectedCharacters = ui.craftsCharacterFilterValues,
			rangeKey = self:GetInventoryMetricRange(),
			rankIndex = rankMap,
		})
		local snapLines = self:BuildItemDetailScrollBodyLines(detail)
		local bodyCore = table.concat(snapLines, "\n")
		local bodyText = (craftTextPrefix and craftTextPrefix ~= "")
			and (craftTextPrefix .. "\n\n|cffffffffItem analytics|r\n" .. bodyCore)
			or bodyCore
		panel.detailBody:SetText(bodyText)
		panel.detailContent:SetHeight(math.max(240, panel.detailBody:GetStringHeight() + 24))
		local econLine = string.format(
			"Range: %s  |  Current AH: %s  |  Last seen: %s",
			tostring(detail.rangeKey or "all"),
			formatCopperFull(self, detail.economy.currentMarket),
			formatTimestamp(detail.economy.currentMarketAt)
		)
		return detail, econLine
	end

	if row then
		local craftText = self:BuildCraftDetailText(row)
		local econLine = nil
		local graphItemID = row.outputItemID and self:ResolveGraphItemIDForCraftRow(row) or nil
		if row.outputItemID then
			local detail
			detail, econLine = applyOutputItemDetail(row.outputItemID, craftText, graphItemID)
		else
			panel.detailBody:SetText(craftText)
			panel.detailContent:SetHeight(math.max(240, panel.detailBody:GetStringHeight() + 24))
		end
		local crafterLabel = select(1, self:GetCraftRecommendedCrafter(row))
		panel.detailTitle:SetText(craftItemSourcePrimaryTitle(self, row))
		local line1 = string.format(
			"Source: %s  |  Recommended crafter: %s  |  Sale: %s",
			row.recipeName or "-",
			crafterLabel or "-",
			row.saleNet and self:FormatCopperShort(row.saleNet) or "-"
		)
		panel.detailMeta:SetText(econLine and (line1 .. "\n" .. econLine) or line1)
		panel.detailIcon:SetTexture(row.outputIcon or DEFAULT_ICON)
		applyRankBadge(panel.detailRankIcon, panel.detailRankText, row.qualityIndex)
		local iconX = 0
		if row.qualityIndex and tonumber(row.qualityIndex) > 0 then
			iconX = RANK_BADGE_PX + RANK_ICON_GAP
		end
		panel.detailIcon:ClearAllPoints()
		panel.detailIcon:SetPoint("TOPLEFT", panel.detailHeader, "TOPLEFT", iconX, 0)
		if panel.craftsDetailGraphBlock then
			if row.outputItemID and panel.craftsDetailGraph then
				panel.craftsDetailGraphBlock:Show()
			else
				panel.craftsDetailGraphBlock:Hide()
			end
		end
		if panel.craftsDetailGraph and graphItemID then
			local matEst = row.matCost
			self:ApplyItemDetailTimeSeriesGraph(graphItemID, panel.craftsDetailGraph, {
				metricSettingKey = "crafts.detailsGraphMetric",
				rangeKey = self:GetInventoryMetricRange(),
				quantityCharacterFilter = ui.craftsCharacterFilterValues or {},
				secondaryCraftingOverlay = row.canCraftNow == true,
				currentCraftCostCopper = matEst,
				quantityOverlay = self:GetSetting("crafts.detailsGraphShowQuantity", true) ~= false,
			})
		end
	elseif itemOnlyID then
		local prefix = "|cffffcc00No matching craft opportunity in the current list (check filters).|r\n\n"
		local detail, econLine = applyOutputItemDetail(itemOnlyID, prefix)
		panel.detailTitle:SetText(self:GetItemDisplayName(itemOnlyID))
		panel.detailMeta:SetText(econLine)
		panel.detailIcon:SetTexture(detail.icon or DEFAULT_ICON)
		applyRankBadge(panel.detailRankIcon, panel.detailRankText, detail.rankIndex)
		local iconX = 0
		if detail.rankIndex and tonumber(detail.rankIndex) > 0 then
			iconX = RANK_BADGE_PX + RANK_ICON_GAP
		end
		panel.detailIcon:ClearAllPoints()
		panel.detailIcon:SetPoint("TOPLEFT", panel.detailHeader, "TOPLEFT", iconX, 0)
		if panel.craftsDetailGraphBlock and panel.craftsDetailGraph then
			panel.craftsDetailGraphBlock:Show()
			self:ApplyItemDetailTimeSeriesGraph(itemOnlyID, panel.craftsDetailGraph, {
				metricSettingKey = "crafts.detailsGraphMetric",
				rangeKey = detail.rangeKey or self:GetInventoryMetricRange(),
				quantityCharacterFilter = ui.craftsCharacterFilterValues or {},
				quantityOverlay = self:GetSetting("crafts.detailsGraphShowQuantity", true) ~= false,
			})
		end
	else
		panel.detailTitle:SetText("Details")
		panel.detailMeta:SetText("Select a craft row to inspect materials, economics, and the recommended crafter.")
		panel.detailIcon:SetTexture(DEFAULT_ICON)
		applyRankBadge(panel.detailRankIcon, panel.detailRankText, nil)
		panel.detailIcon:ClearAllPoints()
		panel.detailIcon:SetPoint("TOPLEFT", panel.detailHeader, "TOPLEFT", 0, 0)
		panel.detailBody:SetText("Select a craft row.")
		panel.detailContent:SetHeight(math.max(240, panel.detailBody:GetStringHeight() + 24))
		if panel.craftsDetailGraphBlock then
			panel.craftsDetailGraphBlock:Hide()
		end
	end
	self:LayoutDetailPaneHeaderRow(panel)
end

function ProfessionExporter:EnsureCraftsPanel(mainFrame)
	local ui = self.ui
	if ui.craftsPanel then
		return
	end

	local panel = CreateFrame("Frame", nil, mainFrame)
	panel:SetAllPoints()
	ui.craftsPanel = panel

	panel.headerCard = self:CreateCard(panel, 860, 96, "surface2")
	panel.headerTitle = panel.headerCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	panel.headerTitle:SetPoint("TOPLEFT", 12, -12)
	panel.headerTitle:SetJustifyH("LEFT")
	panel.headerTitle:SetText("Crafts (account)")

	panel.headerSubtitle = self:CreateMutedText(panel.headerCard, 640)
	panel.headerSubtitle:SetPoint("TOPLEFT", panel.headerTitle, "BOTTOMLEFT", 0, -6)
	panel.headerSubtitle:SetText("Profit board from scanned professions, TSM/Auctionator pricing, and inventory snapshots.")

	panel.headerSummary = self:CreateMutedText(panel.headerCard, 640)
	panel.headerSummary:SetPoint("TOPLEFT", panel.headerSubtitle, "BOTTOMLEFT", 0, -6)

	panel.refreshButton = CreateFrame("Button", nil, panel.headerCard, "UIPanelButtonTemplate")
	panel.refreshButton:SetSize(100, 24)
	panel.refreshButton:SetText("Refresh")
	panel.refreshButton:SetScript("OnClick", function()
		ProfessionExporter:RefreshCraftsTab()
	end)

	panel.scenarioDropdown = self:CreateSingleSelectDropdown(panel.headerCard, {
		label = "Scenario",
		width = 140,
		getOptions = function()
			return {
				{ value = "default", label = "No concentration" },
				{ value = "concentration", label = "With concentration" },
			}
		end,
		getValue = function()
			return ProfessionExporter:GetSetting("crafts.scenario", "default")
		end,
		setValue = function(value)
			ProfessionExporter:SetSetting("crafts.scenario", value)
		end,
		onChanged = function()
			ProfessionExporter:RefreshCraftsTab()
		end,
	})

	panel.sourceDropdown = self:CreateSingleSelectDropdown(panel.headerCard, {
		label = "Mats",
		width = 130,
		getOptions = function()
			return {
				{ value = "owned_first", label = "Owned first" },
				{ value = "market_only", label = "Market only" },
				{ value = "mixed", label = "Mixed" },
			}
		end,
		getValue = function()
			return ProfessionExporter:GetSetting("crafts.reagentSourceMode", "owned_first")
		end,
		setValue = function(value)
			ProfessionExporter:SetSetting("crafts.reagentSourceMode", value)
		end,
		onChanged = function()
			ProfessionExporter:RefreshCraftsTab()
		end,
	})

	panel.basisDropdown = self:CreateSingleSelectDropdown(panel.headerCard, {
		label = "Basis",
		width = 120,
		getOptions = function()
			return {
				{ value = "auto", label = "Auto" },
				{ value = "market", label = "Market" },
				{ value = "ledger", label = "Ledger" },
			}
		end,
		getValue = function()
			return ProfessionExporter:GetSetting("crafts.costBasis", "auto")
		end,
		setValue = function(value)
			ProfessionExporter:SetSetting("crafts.costBasis", value)
			if value == "market" then
				ProfessionExporter:SetSetting("crafts.saleBasis", "market")
			elseif value == "ledger" then
				ProfessionExporter:SetSetting("crafts.saleBasis", "ledger")
			else
				ProfessionExporter:SetSetting("crafts.saleBasis", "auto")
			end
			ProfessionExporter:RefreshCraftsTab()
		end,
		onChanged = function()
			ProfessionExporter:RefreshCraftsTab()
		end,
	})

	panel.craftsRangeDropdown = self:CreateSingleSelectDropdown(panel.headerCard, {
		label = "Range",
		width = 132,
		getOptions = function()
			return ProfessionExporter:GetInventoryMetricRangeOptions()
		end,
		getValue = function()
			return ProfessionExporter:GetInventoryMetricRange()
		end,
		setValue = function(value)
			ProfessionExporter:SetInventoryMetricRange(value)
		end,
		onChanged = function()
			local u = ProfessionExporter.ui
			if u and u.craftsPanel then
				ProfessionExporter:RenderCraftsDetails(u.craftsSelectedRowData)
				ProfessionExporter:LayoutCraftsPanel(u.craftsPanel)
			end
		end,
	})

	panel.filterCard = self:CreateCard(panel, 860, 86, "surface2")
	local searchLabel = panel.filterCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	searchLabel:SetPoint("TOPLEFT", 12, -10)
	searchLabel:SetText("Search")

	ui.craftsSearchBox = CreateFrame("EditBox", addonName .. "CraftsSearch", panel.filterCard, "InputBoxTemplate")
	ui.craftsSearchBox:SetSize(200, 22)
	ui.craftsSearchBox:SetPoint("TOPLEFT", searchLabel, "BOTTOMLEFT", -6, -6)
	ui.craftsSearchBox:SetAutoFocus(false)
	ui.craftsSearchBox:SetMaxLetters(64)
	ui.craftsSearchBox:SetScript("OnEnterPressed", function(box)
		box:ClearFocus()
	end)
	ui.craftsSearchBox:SetScript("OnTextChanged", function()
		ProfessionExporter:ScheduleCraftsSearchRefresh()
	end)

	local function copyBoolMap(t)
		local out = {}
		if type(t) == "table" then
			for k, v in pairs(t) do
				if v then
					out[k] = true
				end
			end
		end
		return out
	end

	ui.craftsCharacterFilterValues = copyBoolMap(self:GetSetting("crafts.characterFilter", {}))
	ui.craftsProfessionFilterValues = copyBoolMap(self:GetSetting("crafts.professionFilter", {}))
	ui.craftsExpansionFilterValues = copyBoolMap(self:GetSetting("crafts.selectedExpansions", {}))
	ui.craftsCategoryFilterValues = copyBoolMap(self:GetSetting("crafts.categoryFilter", {}))

	ui.craftsCharacterDropdown = self:CreateMultiSelectDropdown(panel.filterCard, {
		label = "Characters",
		width = 200,
		allLabel = "All characters",
		getOptions = function()
			return ProfessionExporter:GetInventoryCharacterFilterOptions()
		end,
		getSelection = function()
			return ui.craftsCharacterFilterValues
		end,
		setSelection = function(selection)
			ui.craftsCharacterFilterValues = selection
			ProfessionExporter:SetSetting("crafts.characterFilter", selection)
		end,
		onChanged = function()
			ProfessionExporter:RefreshCraftsTab()
		end,
	})
	ui.craftsCharacterDropdown:SetPoint("TOPLEFT", ui.craftsSearchBox, "TOPRIGHT", 12, 12)

	ui.craftsProfessionDropdown = self:CreateMultiSelectDropdown(panel.filterCard, {
		label = "Profession",
		width = 160,
		allLabel = "All",
		getOptions = function()
			return ProfessionExporter:GetCraftProfessionFilterOptions()
		end,
		getSelection = function()
			return ui.craftsProfessionFilterValues
		end,
		setSelection = function(selection)
			ui.craftsProfessionFilterValues = selection
			ProfessionExporter:SetSetting("crafts.professionFilter", selection)
		end,
		onChanged = function()
			ProfessionExporter:RefreshCraftsTab()
		end,
	})
	ui.craftsProfessionDropdown:SetPoint("TOPLEFT", ui.craftsCharacterDropdown, "TOPRIGHT", 8, 0)

	ui.craftsExpansionDropdown = self:CreateMultiSelectDropdown(panel.filterCard, {
		label = "Expansion",
		width = 160,
		allLabel = "All expansions",
		getOptions = function()
			return ProfessionExporter:GetExpansionFilterOptions()
		end,
		getSelection = function()
			return ui.craftsExpansionFilterValues
		end,
		setSelection = function(selection)
			ui.craftsExpansionFilterValues = selection
			ProfessionExporter:SetSetting("crafts.selectedExpansions", selection)
		end,
		onChanged = function()
			ProfessionExporter:RefreshCraftsTab()
		end,
	})
	ui.craftsExpansionDropdown:SetPoint("TOPLEFT", ui.craftsProfessionDropdown, "TOPRIGHT", 8, 0)

	ui.craftsProfitDropdown = self:CreateSingleSelectDropdown(panel.filterCard, {
		label = "Profit",
		width = 130,
		getOptions = function()
			return {
				{ value = "all", label = "All states" },
				{ value = "profitable", label = "Profitable" },
				{ value = "negative", label = "Negative" },
				{ value = "missing_price", label = "Missing price" },
				{ value = "uncraftable", label = "Uncraftable now" },
			}
		end,
		getValue = function()
			return ProfessionExporter:GetSetting("crafts.profitState", "all")
		end,
		setValue = function(value)
			ProfessionExporter:SetSetting("crafts.profitState", value)
		end,
		onChanged = function()
			ProfessionExporter:RefreshCraftsTab()
		end,
	})
	ui.craftsProfitDropdown:SetPoint("TOPLEFT", ui.craftsSearchBox, "BOTTOMLEFT", -6, -36)

	ui.craftsCategoryDropdown = self:CreateMultiSelectDropdown(panel.filterCard, {
		label = "Category",
		width = 160,
		allLabel = "All",
		getOptions = function()
			return ProfessionExporter:GetCraftCategoryFilterOptions(ui.craftsUnfilteredRows or {})
		end,
		getSelection = function()
			return ui.craftsCategoryFilterValues
		end,
		setSelection = function(selection)
			ui.craftsCategoryFilterValues = selection
			ProfessionExporter:SetSetting("crafts.categoryFilter", selection)
		end,
		onChanged = function()
			ProfessionExporter:RefreshCraftsTab()
		end,
	})
	ui.craftsCategoryDropdown:SetPoint("TOPLEFT", ui.craftsProfitDropdown, "TOPRIGHT", 12, 12)

	ui.craftsClearBtn = CreateFrame("Button", nil, panel.filterCard, "UIPanelButtonTemplate")
	ui.craftsClearBtn:SetSize(96, 22)
	ui.craftsClearBtn:SetPoint("TOPLEFT", ui.craftsCategoryDropdown, "TOPRIGHT", 8, 24)
	ui.craftsClearBtn:SetText("Reset")
	ui.craftsClearBtn:SetScript("OnClick", function()
		ui.craftsCharacterFilterValues = {}
		ui.craftsProfessionFilterValues = {}
		ui.craftsExpansionFilterValues = {}
		ui.craftsCategoryFilterValues = {}
		ui.craftsSearchBox:SetText("")
		ProfessionExporter:SetSetting("crafts.characterFilter", {})
		ProfessionExporter:SetSetting("crafts.professionFilter", {})
		ProfessionExporter:SetSetting("crafts.categoryFilter", {})
		ProfessionExporter:SetSetting("crafts.selectedExpansions", {})
		ProfessionExporter:SetSetting("crafts.profitState", "all")
		ProfessionExporter:RefreshCraftsTab()
	end)

	panel.tableCard = self:CreateCard(panel, 500, 360, "surface2")
	panel.tableTitle = panel.tableCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	panel.tableTitle:SetPoint("TOPLEFT", 10, -10)
	panel.tableTitle:SetText("Opportunities")

	panel.detailsSplitter = self:CreateDetailPaneSplitter(panel, {
		settingsKey = "crafts.detailsWidth",
		onLayout = function()
			ProfessionExporter:LayoutCraftsPanel(panel)
		end,
	})
	panel.detailsSplitter:SetFrameLevel(panel.tableCard:GetFrameLevel() + 4)

    panel.detailCard = self:CreateCard(panel, 340, 360, "surface2")
    panel.detailHeader = CreateFrame("Frame", nil, panel.detailCard)
    panel.detailHeader:SetPoint("TOPLEFT", panel.detailCard, "TOPLEFT", 6, -10)
    panel.detailHeader:SetPoint("TOPRIGHT", panel.detailCard, "TOPRIGHT", -34, -10)
    panel.detailHeader:SetHeight(36)

    panel.detailIcon = panel.detailHeader:CreateTexture(nil, "ARTWORK")
    panel.detailIcon:SetSize(32, 32)
    panel.detailIcon:SetPoint("TOPLEFT", panel.detailHeader, "TOPLEFT", 0, 0)
    panel.detailRankIcon = panel.detailHeader:CreateTexture(nil, "OVERLAY")
    panel.detailRankIcon:SetSize(RANK_BADGE_PX, RANK_BADGE_PX)
    panel.detailRankIcon:SetPoint("TOPRIGHT", panel.detailIcon, "TOPLEFT", -RANK_ICON_GAP, 8)
    panel.detailRankIcon:Hide()
    panel.detailRankText = panel.detailHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.detailRankText:SetPoint("CENTER", panel.detailRankIcon, "CENTER", 0, 0)
    panel.detailRankText:SetTextColor(1, 1, 1)
    panel.detailRankText:Hide()
    panel.detailTitle = panel.detailHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.detailTitle:SetPoint("TOPLEFT", panel.detailIcon, "TOPRIGHT", 6, -3)
    panel.detailTitle:SetJustifyH("LEFT")
    panel.detailTitle:SetWordWrap(true)
    panel.detailCloseButton = CreateFrame("Button", nil, panel.detailCard, "UIPanelCloseButton")
    panel.detailCloseButton:SetPoint("TOPRIGHT", 2, 2)
    panel.detailCloseButton:SetScript("OnClick", function()
        ProfessionExporter:SetSetting("crafts.detailsOpen", false)
        ProfessionExporter:LayoutCraftsPanel(panel)
    end)
    panel.detailMeta = self:CreateMutedText(panel.detailCard, 300)
    panel.detailMeta:SetPoint("TOPLEFT", panel.detailHeader, "BOTTOMLEFT", 0, -6)

    panel.craftsDetailGraphBlock = CreateFrame("Frame", nil, panel.detailCard)
    panel.craftsDetailGraphBlock:SetHeight(188)
    panel.craftsDetailMetricDropdown = self:CreateSingleSelectDropdown(panel.craftsDetailGraphBlock, {
        label = "Chart",
        width = 200,
        getOptions = function()
            return {
                { value = "market", label = "Price history" },
                { value = "crafting", label = "Crafting cost history" },
                { value = "quantity", label = "Quantity over time" },
            }
        end,
        getValue = function()
            return ProfessionExporter:GetSetting("crafts.detailsGraphMetric", "market")
        end,
        setValue = function(value)
            ProfessionExporter:SetSetting("crafts.detailsGraphMetric", value)
        end,
        onChanged = function()
            ProfessionExporter:RenderCraftsDetails(ProfessionExporter.ui.craftsSelectedRowData)
            ProfessionExporter:LayoutCraftsPanel(ProfessionExporter.ui.craftsPanel)
        end,
    })
    panel.craftsDetailMetricDropdown:SetPoint("TOPLEFT", panel.craftsDetailGraphBlock, "TOPLEFT", 0, 0)
    panel.craftsDetailGraph = self:CreateTimeSeriesGraph(panel.craftsDetailGraphBlock, {
        showTitle = false,
        plotHeight = 118,
        emptyText = "No observations in this range.",
    })
    panel.craftsDetailGraph:SetPoint("TOPLEFT", panel.craftsDetailMetricDropdown, "BOTTOMLEFT", -4, -2)
    panel.craftsDetailGraph:SetPoint("TOPRIGHT", panel.craftsDetailGraphBlock, "TOPRIGHT", 0, -54)

    panel.detailActions = CreateFrame("Frame", nil, panel.detailCard)
    panel.detailActions:SetHeight(28)
    panel.detailQueueAdd1 = CreateFrame("Button", nil, panel.detailActions, "UIPanelButtonTemplate")
    panel.detailQueueAdd1:SetSize(76, 22)
    panel.detailQueueAdd1:SetPoint("LEFT", panel.detailActions, "LEFT", 0, 0)
    panel.detailQueueAdd1:SetText("Queue +1")
    panel.detailQueueAdd1:SetScript("OnClick", function()
        local row = ProfessionExporter.ui.craftsSelectedRowData
        if row then
            ProfessionExporter:AddCraftToQueue(row, 1)
        end
    end)
    panel.detailQueueAdd5 = CreateFrame("Button", nil, panel.detailActions, "UIPanelButtonTemplate")
    panel.detailQueueAdd5:SetSize(44, 22)
    panel.detailQueueAdd5:SetPoint("LEFT", panel.detailQueueAdd1, "RIGHT", 4, 0)
    panel.detailQueueAdd5:SetText("+5")
    panel.detailQueueAdd5:SetScript("OnClick", function()
        local row = ProfessionExporter.ui.craftsSelectedRowData
        if row then
            ProfessionExporter:AddCraftToQueue(row, 5)
        end
    end)
    panel.detailQueueQty = CreateFrame("EditBox", nil, panel.detailActions, "InputBoxTemplate")
    panel.detailQueueQty:SetSize(40, 22)
    panel.detailQueueQty:SetPoint("LEFT", panel.detailQueueAdd5, "RIGHT", 6, 0)
    panel.detailQueueQty:SetAutoFocus(false)
    panel.detailQueueQty:SetNumeric(true)
    panel.detailQueueQty:SetMaxLetters(4)
    panel.detailQueueQty:SetText("1")
    panel.detailQueueQty:SetScript("OnEnterPressed", function(box)
        box:ClearFocus()
    end)
    panel.detailQueueAddN = CreateFrame("Button", nil, panel.detailActions, "UIPanelButtonTemplate")
    panel.detailQueueAddN:SetSize(52, 22)
    panel.detailQueueAddN:SetPoint("LEFT", panel.detailQueueQty, "RIGHT", 6, 0)
    panel.detailQueueAddN:SetText("Add")
    panel.detailQueueAddN:SetScript("OnClick", function()
        local row = ProfessionExporter.ui.craftsSelectedRowData
        local n = tonumber(ProfessionExporter.ui.craftsPanel.detailQueueQty:GetText()) or 1
        if row and n and n > 0 then
            ProfessionExporter:AddCraftToQueue(row, n)
        end
    end)
    panel.detailQueueRemove = CreateFrame("Button", nil, panel.detailActions, "UIPanelButtonTemplate")
    panel.detailQueueRemove:SetSize(96, 22)
    panel.detailQueueRemove:SetPoint("LEFT", panel.detailQueueAddN, "RIGHT", 4, 0)
    panel.detailQueueRemove:SetText("Remove")
    panel.detailQueueRemove:SetScript("OnClick", function()
        local row = ProfessionExporter.ui.craftsSelectedRowData
        if row then
            ProfessionExporter:RemoveCraftQueueLinesForOpportunityRow(row)
        end
    end)

    panel.queueCard = self:CreateCard(panel.detailCard, 300, 188, "surface3")
    panel.queueTitle = panel.queueCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.queueTitle:SetPoint("TOPLEFT", 8, -8)
    panel.queueTitle:SetText("Craft queue & shopping")
    panel.queueSummary = self:CreateMutedText(panel.queueCard, 280)
    panel.queueSummary:SetPoint("TOPLEFT", panel.queueTitle, "BOTTOMLEFT", 0, -4)
    panel.queueScroll = CreateFrame("ScrollFrame", addonName .. "CraftsQueueScroll", panel.queueCard, "UIPanelScrollFrameTemplate")
    panel.queueScroll:SetPoint("TOPLEFT", panel.queueSummary, "BOTTOMLEFT", -8, -4)
    panel.queueScroll:SetPoint("BOTTOMRIGHT", panel.queueCard, "BOTTOMRIGHT", -28, 30)
    panel.queueContent = CreateFrame("Frame", nil, panel.queueScroll)
    panel.queueContent:SetWidth(260)
    panel.queueBody = self:CreateMutedText(panel.queueContent, 260)
    panel.queueBody:SetPoint("TOPLEFT", 4, -4)
    panel.queueScroll:SetScrollChild(panel.queueContent)
    panel.queueClearBtn = CreateFrame("Button", nil, panel.queueCard, "UIPanelButtonTemplate")
    panel.queueClearBtn:SetSize(88, 22)
    panel.queueClearBtn:SetPoint("BOTTOMLEFT", 8, 6)
    panel.queueClearBtn:SetText("Clear queue")
    panel.queueClearBtn:SetScript("OnClick", function()
        ProfessionExporter:ClearCraftQueue()
    end)
    panel.queueClearWorkOrdersBtn = CreateFrame("Button", nil, panel.queueCard, "UIPanelButtonTemplate")
    panel.queueClearWorkOrdersBtn:SetSize(108, 22)
    panel.queueClearWorkOrdersBtn:SetPoint("LEFT", panel.queueClearBtn, "RIGHT", 6, 0)
    panel.queueClearWorkOrdersBtn:SetText("Clear orders")
    panel.queueClearWorkOrdersBtn:SetScript("OnClick", function()
        if ProfessionExporter.ClearCraftingOrderWorkQueue then
            ProfessionExporter:ClearCraftingOrderWorkQueue()
        end
    end)

    panel.detailScroll = CreateFrame("ScrollFrame", addonName .. "CraftsDetailsScroll", panel.detailCard, "UIPanelScrollFrameTemplate")
    panel.detailContent = CreateFrame("Frame", nil, panel.detailScroll)
    panel.detailContent:SetWidth(280)
    panel.detailContent:SetHeight(240)
    panel.detailScroll:SetScrollChild(panel.detailContent)
    panel.detailBody = self:CreateMutedText(panel.detailContent, 280)
    panel.detailBody:SetPoint("TOPLEFT", 2, -4)

	local sortKey = self:GetSetting("crafts.sortColumn", "profit")
	local sortAsc = self:GetSetting("crafts.sortAsc", false)
	ui.craftsTable = self:CreateReusableTable(panel.tableCard, {
		rowHeight = ROW_H,
		maxRows = MAX_ROWS,
		viewportVirtualize = true,
		virtualOverscan = 8,
		autoFitToScroll = true,
		sortKey = sortKey,
		sortAsc = sortAsc,
		onSortChanged = function(key, asc)
			ProfessionExporter:SetSetting("crafts.sortColumn", key)
			ProfessionExporter:SetSetting("crafts.sortAsc", asc)
		end,
        onRowEnter = function(_, rowData)
            if not rowData or not rowData.outputItemID then
                return
            end
            local crafterLabel, crafterReason = ProfessionExporter:GetCraftRecommendedCrafter(rowData)
            GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
            if GameTooltip.SetItemByID then
                GameTooltip:SetItemByID(rowData.outputItemID)
            else
                GameTooltip:SetText("#" .. tostring(rowData.outputItemID))
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format("Source recipe: %s", rowData.recipeName or "-"), 0.82, 0.88, 0.96)
            GameTooltip:AddLine(string.format("Recommended crafter: %s", crafterLabel or "-"), 1, 0.92, 0.65)
            GameTooltip:AddLine(string.format("Reason: %s", crafterReason or "Best available"), 0.82, 0.88, 0.96)
            GameTooltip:AddLine(string.format("Profession: %s  |  Expansion: %s", rowData.professionName or "?", rowData.expansionTag or "?"), 0.82, 0.88, 0.96)
            if rowData.qualityReachable == false then
                if rowData.concentrationNeeded then
                    GameTooltip:AddLine(string.format("+%s conc", ProfessionExporter:FormatNumberGrouped(rowData.concentrationNeeded)), 1, 0.82, 0.45, true)
                elseif rowData.concentrationCost and rowData.concentrationCost > 0 then
                    GameTooltip:AddLine("+conc", 1, 0.82, 0.45, true)
                else
                    GameTooltip:AddLine("Unreachable", 1, 0.5, 0.5, true)
                end
            end
            GameTooltip:AddLine(string.format("Sale: %s  |  Mats: %s  |  Profit: %s", rowData.saleNet and ProfessionExporter:FormatCopperShort(rowData.saleNet) or "-", rowData.matCost and ProfessionExporter:FormatCopperShort(rowData.matCost) or "-", rowData.profit and ProfessionExporter:FormatCopperShort(rowData.profit) or "-"), 0.8, 0.9, 1)
            if rowData.outOfPocketMatCost and rowData.outOfPocketMatCost ~= rowData.matCost then
                GameTooltip:AddLine(string.format("Out-of-pocket mats in current source mode: %s", ProfessionExporter:FormatCopperShort(rowData.outOfPocketMatCost)), 0.82, 0.88, 0.96, true)
            end
            if rowData.requiredTargetReagent and rowData.requiredTargetReagentItemID then
                GameTooltip:AddLine(
                    string.format(
                        "Required target reagent: %s (%s).",
                        ProfessionExporter:GetItemDisplayName(rowData.requiredTargetReagentItemID),
                        rowData.requiredTargetReagentAuto and "auto-selected" or "live-selected"
                    ),
                    0.85, 0.82, 0.62
                )
            end
            local bestEval = rowData.bestCharacterKey and rowData.perChar and rowData.perChar[rowData.bestCharacterKey] or nil
            if bestEval and bestEval.reagentPlan and #bestEval.reagentPlan > 0 then
                GameTooltip:AddLine(" ", 1, 1, 1)
                GameTooltip:AddLine("Material pricing:", 0.95, 0.85, 0.55)
                for _, slot in ipairs(bestEval.reagentPlan) do
                    local name = ProfessionExporter:GetItemDisplayName(slot.itemID)
                    local qty = ProfessionExporter:FormatNumberGrouped(slot.quantityRequired or 0)
                    local costSuffix = ProfessionExporter:FormatReagentSlotEconomicsTooltipSuffix(slot)
                    GameTooltip:AddLine(
                        string.format("  %s x%s  %s", name, qty, costSuffix),
                        0.75, 0.82, 0.88
                    )
                end
            end
            if #(rowData.badges or {}) > 0 then
                GameTooltip:AddLine("Flags: " .. table.concat(rowData.badges, ", "), 0.82, 0.88, 0.96)
            end
            GameTooltip:AddLine("Click for details (reopens side panel if closed).", 0.75, 0.82, 0.9)
            GameTooltip:Show()
        end,
        onRowLeave = function()
			GameTooltip:Hide()
		end,
		onRowClick = function(_, rowData)
			ui.craftsItemDetailOnlyItemID = nil
			ProfessionExporter:SetSetting("crafts.detailsOpen", true)
			ui.craftsSelectedRowKey = rowData and rowData.rowKey
			ui.craftsSelectedRowData = rowData
			ProfessionExporter:SetSetting("crafts.selectedRowKey", ui.craftsSelectedRowKey)
			ProfessionExporter:RenderCraftsDetails(rowData)
			ProfessionExporter:LayoutCraftsPanel(panel)
		end,
	})
	panel.craftsTable = ui.craftsTable
	ui.craftsTable:SetColumns(self:BuildCraftsTableColumns())
	if ui.craftsTable.scrollFrame and not ui.craftsTable.__ahVisibleScanHooked then
		ui.craftsTable.__ahVisibleScanHooked = true
		ui.craftsTable.scrollFrame:HookScript("OnVerticalScroll", function()
			if ProfessionExporter.QueueVisibleCraftsTabAuctionRefresh then
				C_Timer.After(0.12, function()
					ProfessionExporter:QueueVisibleCraftsTabAuctionRefresh(false)
				end)
			end
		end)
	end

	panel:SetScript("OnSizeChanged", function()
		ProfessionExporter:LayoutCraftsPanel(panel)
	end)
	self:LayoutCraftsPanel(panel)

	local sel = self:GetSetting("crafts.selectedRowKey")
	ui.craftsSelectedRowKey = sel
end

function ProfessionExporter:ScheduleCraftsSearchRefresh()
	local ui = self.ui
	if not ui then
		return
	end
	if ui.craftsSearchTimer then
		ui.craftsSearchTimer:Cancel()
	end
	ui.craftsSearchTimer = C_Timer.NewTimer(0.2, function()
		ui.craftsSearchTimer = nil
		if ui.activeMainTab == "crafts" then
			self:RefreshCraftsTab()
		end
	end)
end

function ProfessionExporter:BuildCraftsFilterState()
	local ui = self.ui or {}
	return {
		text = trim(ui.craftsSearchBox and ui.craftsSearchBox:GetText() or ""),
		characters = ui.craftsCharacterFilterValues or {},
		professions = ui.craftsProfessionFilterValues or {},
		expansions = ui.craftsExpansionFilterValues or {},
		categories = ui.craftsCategoryFilterValues or {},
		profitState = self:GetSetting("crafts.profitState", "all"),
	}
end

function ProfessionExporter:RefreshCraftsTab()
	self:InitDB()
	local ui = self.ui
	if not ui or not ui.craftsPanel or ui.activeMainTab ~= "crafts" then
		return
	end

	local rows = self:BuildCraftOpportunityRows()
	ui.craftsUnfilteredRows = rows

	local craftState = self:GetState()
	local craftBuildNote = ""
	if craftState.craftEvalInProgress and craftState.craftEvalWorkList and #craftState.craftEvalWorkList > 0 then
		local done = math.max(0, (craftState.craftEvalIdx or 1) - 1)
		craftBuildNote = string.format("  |cffffcc00(Updating %d/%d recipes…)|r", done, #craftState.craftEvalWorkList)
	end

    local currentKey = self:GetCharacterKey()
    for _, row in ipairs(rows) do
        local ck = row.bestCharacterKey
        row.characterDisplay = ck and self:GetDashboardSidebarCharacterLabel(ck, self.db.characters and self.db.characters[ck], currentKey) or "?"
        row._rowIdentity = row.rowKey or tostring(row.recipeID)
    end

	local charOpts = self:GetInventoryCharacterFilterOptions()
	local profOpts = self:GetCraftProfessionFilterOptions()
	local expOpts = self:GetExpansionFilterOptions()
	ui.craftsCharacterFilterValues = self:NormalizeFilterSelection(ui.craftsCharacterFilterValues or {}, charOpts)
	ui.craftsProfessionFilterValues = self:NormalizeFilterSelection(ui.craftsProfessionFilterValues or {}, profOpts)
	ui.craftsExpansionFilterValues = self:NormalizeFilterSelection(ui.craftsExpansionFilterValues or {}, expOpts)
	local catOpts = self:GetCraftCategoryFilterOptions(rows)
	ui.craftsCategoryFilterValues = self:NormalizeFilterSelection(ui.craftsCategoryFilterValues or {}, catOpts)

	ui.craftsCharacterDropdown:SetOptions(charOpts)
	ui.craftsCharacterDropdown:RefreshText()
	ui.craftsProfessionDropdown:SetOptions(profOpts)
	ui.craftsProfessionDropdown:RefreshText()
	ui.craftsExpansionDropdown:SetOptions(expOpts)
	ui.craftsExpansionDropdown:RefreshText()
	ui.craftsCategoryDropdown:SetOptions(catOpts)
	ui.craftsCategoryDropdown:RefreshText()

	rows = self:FilterCraftRows(rows, self:BuildCraftsFilterState())
	ui.craftsWorkingRows = rows

    ui.craftsPanel.headerSummary:SetText(string.format(
        "Items: %s  |  Scenario: %s  |  AH cut: %d%%  |  Pricing from TSM/Auctionator integrations.%s",
        self:FormatNumberGrouped(#rows),
        tostring(self:GetSetting("crafts.scenario", "default")),
        tonumber(self:GetSetting("crafts.ahCutPercent", 5)) or 5,
        craftBuildNote
    ))

	ui.craftsPanel.scenarioDropdown:RefreshText()
	ui.craftsPanel.sourceDropdown:RefreshText()
	ui.craftsPanel.basisDropdown:RefreshText()
	ui.craftsProfitDropdown:RefreshText()

	ui.craftsTable.sortKey = self:GetSetting("crafts.sortColumn", "profit")
	ui.craftsTable.sortAsc = self:GetSetting("crafts.sortAsc", false)
	ui.craftsTable:SetColumns(self:BuildCraftsTableColumns())
	ui.craftsTable:SetRows(rows)

	local selected = ui.craftsSelectedRowKey
	local picked = nil
	if selected then
		for _, r in ipairs(rows) do
			if r.rowKey == selected then
				picked = r
				break
			end
		end
	end
	if not picked and #rows > 0 then
		picked = rows[1]
		ui.craftsSelectedRowKey = picked.rowKey
	end
	self:RenderCraftsDetails(picked)
	self:LayoutCraftsPanel(ui.craftsPanel)
	self:RefreshCraftsQueuePanel()
	if self.QueueVisibleCraftsTabAuctionRefresh then
		self:QueueVisibleCraftsTabAuctionRefresh(false)
	end
end

function ProfessionExporter:FocusCraftsQueuePanel()
	local panel = self.ui and self.ui.craftsPanel
	if not panel or not panel.queueScroll then
		return
	end
	panel.queueScroll:SetVerticalScroll(0)
	if panel.queueCard and UIFrameFlash then
		UIFrameFlash(panel.queueCard, 0.4, 0.4, 0.6, false, 0, 0)
	end
end

function ProfessionExporter:RefreshCraftsQueuePanel()
	local panel = self.ui and self.ui.craftsPanel
	if not panel or not panel.queueBody then
		return
	end
	local sum = self:BuildCraftQueueSummary()
	local woSum = (type(self.BuildCraftingOrderWorkQueueSummary) == "function" and self:BuildCraftingOrderWorkQueueSummary())
		or {
		lineCount = 0,
		lines = {},
		reagentLines = {},
		reagentTotals = {},
	}
	panel.queueSummary:SetText(string.format(
		"%d queued  |  Profit %s  |  Buy now %s  |  Craftable %d",
		tonumber(sum.lineCount) or 0,
		sum.totalProfit and self:FormatCopperShort(sum.totalProfit) or "—",
		sum.totalCurrentCharacterBuyCost and self:FormatCopperShort(sum.totalCurrentCharacterBuyCost) or "—",
		tonumber(sum.craftableLineCount) or 0
	))

	local lines = {}
	lines[#lines + 1] = "|cffffffffQueued crafts|r"
	if #(sum.lines or {}) == 0 then
		lines[#lines + 1] = "  (empty)"
	else
		for _, e in ipairs(sum.lines or {}) do
			local lbl = self:GetDashboardSidebarCharacterLabel(
				e.characterKey,
				self.db.characters and self.db.characters[e.characterKey],
				self:GetCharacterKey()
			)
			local profitText = e.snapshot and e.snapshot.profit and self:FormatCopperShort((tonumber(e.snapshot.profit) or 0) * (tonumber(e.quantity) or 0)) or "—"
			local rankText = tonumber(e.qualityIndex) and ("R" .. tostring(e.qualityIndex)) or "R?"
			lines[#lines + 1] = string.format(
				"• %s x%d  |  %s  |  %s  |  %s",
				e.recipeName or "?",
				tonumber(e.quantity) or 0,
				rankText,
				tostring(e.scenario or "?"),
				profitText
			)
			lines[#lines + 1] = string.format("    %s", lbl)
		end
	end

	lines[#lines + 1] = " "
	lines[#lines + 1] = "|cffffffffShopping (current character)|r"
	if #(sum.reagentLines or {}) == 0 then
		lines[#lines + 1] = "  (empty)"
	else
		for _, li in ipairs(sum.reagentLines) do
			if (tonumber(li.quantityToBuy) or 0) > 0 then
				local mailText = li.mailToText and li.mailToText ~= "" and ("  |  mail " .. li.mailToText) or ""
				local buyCost = li.estimatedBuyCost and self:FormatCopperShort(li.estimatedBuyCost) or "—"
				lines[#lines + 1] = string.format(
					"• %s x%s  |  have %s  |  buy %s  |  %s%s",
					li.name,
					self:FormatNumberGrouped(li.quantityNeeded or li.quantity or 0),
					self:FormatNumberGrouped(li.currentCharacterAvailable or 0),
					self:FormatNumberGrouped(li.quantityToBuy or 0),
					buyCost,
					mailText
				)
			end
		end
	end

	lines[#lines + 1] = " "
	lines[#lines + 1] = "|cffffffffCrafting orders|r"
	lines[#lines + 1] = string.format("Orders: %d  |  Crafter-supplied materials only", woSum.lineCount or 0)
	if #(woSum.lines or {}) == 0 then
		lines[#lines + 1] = "  (none — use Professions order detail: Add to shopping)"
	else
		for i, e in ipairs(woSum.lines) do
			local tip = e.tipAmount and self:FormatCopperShort(e.tipAmount) or "—"
			local name = e.recipeName
			if (not name or name == "" or name == "?") and tonumber(e.spellID) and C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
				local ri = C_TradeSkillUI.GetRecipeInfo(tonumber(e.spellID))
				name = ri and ri.name or name
			end
			if (not name or name == "" or name == "?") and tonumber(e.itemID) then
				name = self:GetItemDisplayName(e.itemID)
			end
			lines[#lines + 1] = string.format("• %s  |  tip %s  |  click Open below", tostring(name or "?"), tip)
		end
	end

	lines[#lines + 1] = " "
	lines[#lines + 1] = "|cffffffffWork-order materials|r"
	if #(woSum.reagentLines or {}) == 0 then
		lines[#lines + 1] = "  (empty)"
	else
		for _, li in ipairs(woSum.reagentLines) do
			if (tonumber(li.quantityToBuy) or 0) > 0 then
				local mailText = li.mailToText and li.mailToText ~= "" and ("  |  mail " .. li.mailToText) or ""
				lines[#lines + 1] = string.format(
					"• %s x%s  |  buy %s%s",
					li.name,
					self:FormatNumberGrouped(li.quantityNeeded or li.quantity or 0),
					self:FormatNumberGrouped(li.quantityToBuy or 0),
					mailText
				)
			end
		end
	end

	panel.queueBody:SetText(table.concat(lines, "\n"))
	local bodyHeight = panel.queueBody:GetStringHeight() + 16

	if not panel.queueOrderButtons then
		panel.queueOrderButtons = {}
	end
	for _, btn in ipairs(panel.queueOrderButtons) do
		btn:Hide()
		btn:SetParent(nil)
	end
	wipe(panel.queueOrderButtons)

	if not panel.queueOrderButtonRow then
		panel.queueOrderButtonRow = CreateFrame("Frame", nil, panel.queueContent)
	end
	panel.queueOrderButtonRow:ClearAllPoints()
	panel.queueOrderButtonRow:SetPoint("TOPLEFT", panel.queueBody, "BOTTOMLEFT", 0, -8)
	panel.queueOrderButtonRow:SetWidth(260)

	local btnX = 0
	for _, e in ipairs(woSum.lines or {}) do
		local btn = CreateFrame("Button", nil, panel.queueOrderButtonRow, "UIPanelButtonTemplate")
		btn:SetSize(72, 18)
		btn:SetPoint("TOPLEFT", btnX, 0)
		btnX = btnX + 76
		btn:SetText(string.format("#%s", tostring(e.orderID or "?")))
		btn:SetScript("OnClick", function()
			if ProfessionExporter.OpenCraftingOrderWorkQueueEntry then
				ProfessionExporter:OpenCraftingOrderWorkQueueEntry(e)
			end
		end)
		panel.queueOrderButtons[#panel.queueOrderButtons + 1] = btn
	end
	local btnRowHeight = (#panel.queueOrderButtons > 0) and 24 or 0
	panel.queueOrderButtonRow:SetHeight(btnRowHeight)
	panel.queueContent:SetHeight(math.max(60, bodyHeight + btnRowHeight + 8))
	if panel.queueClearWorkOrdersBtn then
		panel.queueClearWorkOrdersBtn:SetShown(self.IS_RETAIL == true)
	end
end

function ProfessionExporter:RefreshCraftsTabIfVisible()
	local ui = self.ui
	if ui and ui.activeMainTab == "crafts" then
		self:RefreshCraftsTab()
	end
end



