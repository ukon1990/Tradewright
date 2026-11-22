local _, Tradewright = ...

local MAX_ROWS = 450

local function isPlaceholderItemLabel(s)
	local t = Tradewright:Trim(s)
	if t == "" or t == "?" then
		return true
	end
	return string.match(t, "^#%d+$") ~= nil
end

-- Shared with the Crafts queue pane and details files.
Tradewright.CraftsLayout = { gap = 12, pad = 10, detailWidth = 300, tallRow = 36 }
local GAP = Tradewright.CraftsLayout.gap
local TALL_ROW = Tradewright.CraftsLayout.tallRow

local function rankMarkup(rankIndex)
	return Tradewright:GetRankMarkup(rankIndex)
end

-- A stored character's plain name, or its key when the character is unknown.
function Tradewright:GetCrafterName(characterKey)
	local data = characterKey and self.db.characters and self.db.characters[characterKey]
	local meta = data and data.meta
	return meta and meta.name or tostring(characterKey or "?")
end

-- Why a craft row's profit cannot be trusted, or nil.
local function craftRowWarning(row)
	if not row.matCost then
		return "no material price"
	end
	if row.qualityReachable == false then
		return (row.concentrationNeeded or row.concentrationCost) and "needs concentration" or "rank out of reach"
	end
	return nil
end

-- Second line of a craft row: profession, best crafter, queued count, and a warning when it applies.
local function craftRowDetail(pe, row)
	local parts = { row.professionName or "?" }
	if row.bestCharacterKey then
		parts[#parts + 1] = pe:GetCrafterName(row.bestCharacterKey)
	end
	if pe.IS_RETAIL and row.expansionTag and row.expansionTag ~= "" then
		parts[#parts + 1] = row.expansionTag
	end
	local queued = pe:GetCraftQueueQuantityForOpportunityRow(row)
	if queued > 0 then
		parts[#parts + 1] = pe:Colorize(queued .. " queued", "gold")
	end
	local warning = craftRowWarning(row)
	if warning then
		parts[#parts + 1] = pe:Colorize(warning, "warning")
	end
	return table.concat(parts, " · ")
end

-- The crafted item's name with its rank, or the recipe name while the item is unknown.
function Tradewright:GetCraftRowName(row)
	local item = self:Trim(self:GetItemDisplayName(row and row.outputItemID))
	if isPlaceholderItemLabel(item) then
		item = self:Trim(row and row.recipeName or "") ~= "" and row.recipeName or "Craft"
	end
	return item .. rankMarkup(row and row.qualityIndex)
end

-- The evaluation of a craft row for its best crafter.
function Tradewright:GetBestCraftEvaluation(row)
	return row and row.bestCharacterKey and row.perChar and row.perChar[row.bestCharacterKey] or nil
end

local ROI_COLUMN = {
	id = "roi", label = "ROI", justifyH = "RIGHT", width = 48, sortable = true, defaultSort = "desc", optional = true,
	tooltipTitle = "Return", tooltipText = "Profit divided by material cost.",
	sortValue = function(row) return row.roi or -1e15 end,
	getText = function(row) return row.roi and string.format("%.0f%%", row.roi) or "-" end,
}

local function materialsOwnedColumn(pe)
	return {
		id = "coverage", label = "Owned", justifyH = "RIGHT", width = 50, sortable = true, defaultSort = "desc", optional = true,
		tooltipTitle = "Materials owned", tooltipText = "Share of the best crafter's materials that your characters already own.",
		sortValue = function(row)
			local evaluation = pe:GetBestCraftEvaluation(row)
			return evaluation and (evaluation.coverage or 0) or 0
		end,
		getText = function(row)
			local evaluation = pe:GetBestCraftEvaluation(row)
			return evaluation and evaluation.coverage and string.format("%.0f%%", evaluation.coverage * 100) or "-"
		end,
	}
end

function Tradewright:GetCraftsColumnDefinitions()
	local pe = self
	local function money(id, label, field, width, signed)
		return {
			id = id, label = label, justifyH = "RIGHT", width = width, sortable = true, defaultSort = "desc",
			sortValue = function(row) return row[field] or -1e15 end,
			getText = function(row)
				if signed then
					return pe:FormatSignedMoney(row[field])
				end
				return row[field] and pe:FormatCopperShort(row[field]) or "-"
			end,
		}
	end
	return {
		self:CreateItemColumn({
			id = "recipe",
			label = "Item",
			defaultSort = "asc",
			getItemID = function(row) return row.outputItemID end,
			getIcon = function(row) return row.outputIcon end,
			getName = function(row) return pe:GetCraftRowName(row) end,
			getDetail = function(row) return craftRowDetail(pe, row) end,
			sortValue = function(row) return row.outputName or "" end,
		}),
		money("sale", "Sale, net", "saleNet", 80),
		money("mats", "Materials", "matCost", 80),
		money("profit", "Profit", "profit", 86, true),
		ROI_COLUMN,
		materialsOwnedColumn(pe),
	}
end

function Tradewright:BuildCraftsTableColumns()
	return self:AddCraftPlanningColumns(self:GetCraftsColumnDefinitions())
end

--- Among opportunities with this output item, prefer the highest profit (stable tie: first in list order).
function Tradewright:SelectCraftOpportunityByOutputItemID(itemID)
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
				if not best or (p and (not bestProfit or p > bestProfit)) then
					best, bestProfit = r, p
				end
			end
		end
		return best
	end
	return pickBest(ui.craftsWorkingRows) or pickBest(ui.craftsUnfilteredRows)
end

function Tradewright:LayoutCraftsPanel(panel)
	if not panel then
		return
	end
	local view = self.ui.craftsDetailView or "details"
	panel.detailsView:SetShown(view == "details")
	panel.queueView:SetShown(view == "queue")
	self:StyleShellButton(panel.detailsTab, view == "details")
	self:StyleShellButton(panel.queueTab, view == "queue")
	local hasRow = self.ui.craftsSelectedRowData ~= nil or self.ui.craftsItemDetailOnlyItemID ~= nil
	panel.detailsEmpty:SetShown(not hasRow)
	panel.detailsBody:SetShown(hasRow)
end

function Tradewright:OnCraftsRowClick(rowData, tableWidget)
	if self:HandleItemRowModifiedClick(rowData and rowData.outputItemID) then
		return
	end
	local ui = self.ui
	ui.craftsItemDetailOnlyItemID = nil
	ui.craftsSelectedRowKey = rowData and rowData.rowKey
	ui.craftsDetailView = "details"
	self:SetSetting("crafts.selectedRowKey", ui.craftsSelectedRowKey)
	tableWidget:SetSelectedRow(rowData)
	self:RenderCraftsDetails(rowData)
end

-- The opportunities table: left of the detail card, below the toolbar rows.
function Tradewright:CreateCraftsTable(panel)
	local pe, ui = self, self.ui
	local craftsTable = self:CreateReusableTable(panel, {
		rowHeight = TALL_ROW,
		footer = true,
		emptyTitle = "No crafts",
		emptyHint = "Scan a profession, or change the filters.",
		isRowSelected = function(rowData)
			return rowData and rowData.rowKey ~= nil and rowData.rowKey == ui.craftsSelectedRowKey
		end,
		maxRows = MAX_ROWS,
		viewportVirtualize = true,
		virtualOverscan = 8,
		autoFitToScroll = true,
		sortKey = self:GetSetting("crafts.sortColumn", "profit"),
		sortAsc = self:GetSetting("crafts.sortAsc", false),
		onSortChanged = function(key, asc)
			pe:SetSetting("crafts.sortColumn", key)
			pe:SetSetting("crafts.sortAsc", asc)
		end,
		onRowEnter = function(rowFrame, rowData) pe:ShowCraftRowTooltip(rowFrame, rowData) end,
		onRowLeave = function() GameTooltip:Hide() end,
		onRowClick = function(_, rowData, _, tableWidget) pe:OnCraftsRowClick(rowData, tableWidget) end,
	})
	craftsTable.frame:SetPoint("TOPLEFT", panel.options, "BOTTOMLEFT", 0, -GAP)
	craftsTable.frame:SetPoint("BOTTOMRIGHT", panel.detailCard, "BOTTOMLEFT", -GAP, 0)
	craftsTable:SetColumns(self:BuildCraftsTableColumns())
	craftsTable.scrollFrame:HookScript("OnVerticalScroll", function()
		if pe.QueueVisibleCraftsTabAuctionRefresh then
			C_Timer.After(0.12, function()
				pe:QueueVisibleCraftsTabAuctionRefresh(false)
			end)
		end
	end)
	return craftsTable
end

function Tradewright:EnsureCraftsPanel(mainFrame)
	local ui = self.ui
	if ui.craftsPanel then
		return
	end
	local panel = CreateFrame("Frame", nil, mainFrame)
	panel:SetAllPoints()
	ui.craftsPanel = panel
	ui.craftsDetailView = ui.craftsDetailView or "details"
	self:RestoreCraftsFilterSelections()
	self:CreateCraftsFilterRow(panel)
	self:CreateCraftsOptionsRow(panel)
	self:CreateCraftsDetailCard(panel)
	ui.craftsTable = self:CreateCraftsTable(panel)
	panel.craftsTable = ui.craftsTable
	self:SkinTree(panel)
	self:LayoutCraftsPanel(panel)
	ui.craftsSelectedRowKey = self:GetSetting("crafts.selectedRowKey")
end

function Tradewright:BuildCraftsFilterState()
	local ui = self.ui or {}
	return {
		text = self:Trim(ui.craftsSearchBox and ui.craftsSearchBox:GetText() or ""),
		characters = ui.craftsCharacterFilterValues or {},
		professions = ui.craftsProfessionFilterValues or {},
		expansions = self.IS_RETAIL and ui.craftsExpansionFilterValues or {},
		categories = ui.craftsCategoryFilterValues or {},
		profitState = self:GetSetting("crafts.profitState", "all"),
	}
end

-- All craft opportunities, each with the identity the table keeps its selection by.
function Tradewright:BuildCraftsUnfilteredRows()
	local rows = self:BuildCraftOpportunityRows()
	for _, row in ipairs(rows) do
		row._rowIdentity = row.rowKey or tostring(row.recipeID)
	end
	return rows
end

-- Fills the filter dropdowns with the options the current rows offer and drops stale selections.
function Tradewright:RefreshCraftsFilterDropdowns(panel, rows)
	local ui = self.ui
	local filters = {
		{ values = "craftsCharacterFilterValues", dropdown = ui.craftsCharacterDropdown, options = self:GetInventoryCharacterFilterOptions() },
		{ values = "craftsProfessionFilterValues", dropdown = ui.craftsProfessionDropdown, options = self:GetCraftProfessionFilterOptions() },
		{ values = "craftsCategoryFilterValues", dropdown = ui.craftsCategoryDropdown, options = self:GetCraftCategoryFilterOptions(rows) },
	}
	if ui.craftsExpansionDropdown then
		filters[#filters + 1] = { values = "craftsExpansionFilterValues", dropdown = ui.craftsExpansionDropdown, options = self:GetExpansionFilterOptions() }
	end
	for _, filter in ipairs(filters) do
		ui[filter.values] = self:NormalizeFilterSelection(ui[filter.values] or {}, filter.options)
		filter.dropdown:SetOptions(filter.options)
	end
	for _, dropdown in ipairs({ ui.craftsProfitDropdown, panel.sourceDropdown, panel.basisDropdown, panel.craftsRangeDropdown, panel.scenarioDropdown }) do
		dropdown:RefreshText()
	end
end

--- Recipes checked and recipes to check while craft profit is worked out in the background, else nil.
function Tradewright:GetCraftEvalProgress()
	local state = self:GetState()
	local workList = state.craftEvalInProgress and state.craftEvalWorkList
	if workList and #workList > 0 then
		return math.max(0, (state.craftEvalIdx or 1) - 1), #workList
	end
	return nil
end

--- The loading line of craft tables. A function without arguments, so a table's SetLoading can read
--- it again while the check moves on.
function Tradewright.CraftProfitLoadingNote()
	local done, total = Tradewright:GetCraftEvalProgress()
	return done and string.format("Working out craft profit · %d of %d recipes", done, total) or nil
end

-- The note under the options row: evaluation progress while recipes update, else the AH cut and price source.
function Tradewright:GetCraftsOptionsNote()
	local done, total = self:GetCraftEvalProgress()
	if done then
		return self:Colorize(string.format("Updating %d of %d recipes…", done, total), "warning")
	end
	return string.format("Auction cut %d%% · Prices from the last auction house scan",
		tonumber(self:GetSetting("crafts.ahCutPercent", 5)) or 5)
end

-- Footer texts: profitable crafts of all shown, and how many professions they span.
function Tradewright:GetCraftsFooterTexts(rows)
	local profitable, professions = 0, {}
	for _, row in ipairs(rows) do
		if (tonumber(row.profit) or 0) > 0 then
			profitable = profitable + 1
		end
		professions[row.professionName or "?"] = true
	end
	return string.format("%s profitable of %s crafts", self:FormatNumberGrouped(profitable), self:FormatNumberGrouped(#rows)),
		string.format("%d professions", self:TableCount(professions))
end

-- The selected row if it is still shown, else the first row (unless an item-only detail is open).
function Tradewright:PickCraftsSelectedRow(rows)
	local ui = self.ui
	for _, row in ipairs(rows) do
		if row.rowKey == ui.craftsSelectedRowKey then
			return row
		end
	end
	if rows[1] and not ui.craftsItemDetailOnlyItemID then
		ui.craftsSelectedRowKey = rows[1].rowKey
		return rows[1]
	end
	return nil
end

function Tradewright:RefreshCraftsTab()
	self:InitDB()
	local ui = self.ui
	if not ui or not ui.craftsPanel or ui.activeMainTab ~= "crafts" then
		return
	end
	local panel = ui.craftsPanel
	local rows = self:BuildCraftsUnfilteredRows()
	ui.craftsUnfilteredRows = rows
	self:RefreshCraftsFilterDropdowns(panel, rows)
	rows = self:FilterCraftRows(rows, self:BuildCraftsFilterState())
	ui.craftsWorkingRows = rows
	panel.optionsNote:SetText(self:GetCraftsOptionsNote())

	ui.craftsTable.sortKey = self:GetSetting("crafts.sortColumn", "profit")
	ui.craftsTable.sortAsc = self:GetSetting("crafts.sortAsc", false)
	ui.craftsTable:SetRows(rows)
	ui.craftsTable:SetLoading(self:GetCraftEvalProgress() and self.CraftProfitLoadingNote or nil)
	ui.craftsTable:Refresh()
	ui.craftsTable:SetFooterText(self:GetCraftsFooterTexts(rows))

	self:RenderCraftsDetails(self:PickCraftsSelectedRow(rows))
	self:RefreshCraftsQueuePanel()
	if self.QueueVisibleCraftsTabAuctionRefresh then
		self:QueueVisibleCraftsTabAuctionRefresh(false)
	end
end

function Tradewright:RefreshCraftsTabIfVisible()
	local ui = self.ui
	if ui and ui.activeMainTab == "crafts" then
		self:RefreshCraftsTab()
	elseif ui and ui.activeMainTab == "overview" and ui.goldDashboard and ui.goldDashboard:IsVisible() then
		ui.goldDashboard:RefreshCrafts()
	end
end

-- Name and muted second line for a craft opportunity row, as the Crafts table shows them.
function Tradewright:GetCraftRowLabels(row)
	return self:GetCraftRowName(row), craftRowDetail(self, row)
end

-- Switches to the Crafts tab with `row` selected and its details open.
function Tradewright:OpenCraftRow(row)
	local ui = self.ui
	ui.craftsSelectedRowKey = row and row.rowKey
	ui.craftsItemDetailOnlyItemID = nil
	ui.craftsDetailView = "details"
	self:ShowDashboardTab("crafts")
	self:RenderCraftsDetails(row)
end
