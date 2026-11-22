local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
local INV_MAX_ROWS = 550

-- Filter-state field -> the ui key holding that dropdown's selection.
local SELECTION_FILTERS = {
	characters = "invCharacterFilterValues",
	role = "invRoleFilterValues",
	itemType = "invTypeFilterValues",
	qualities = "invQualityFilterValues",
	locations = "invLocationFilterValues",
}

function Tradewright:BuildInventoryFilterState()
	local ui = self.ui or {}
	local state = {
		text = self:Trim(ui.invSearchBox and ui.invSearchBox:GetText() or ""),
		expansions = self.IS_RETAIL and ui.invExpansionFilterValues or {},
		hasPrice = ui.invHasPriceOnly == true,
		profitable = ui.invProfitableOnly == true,
	}
	for field, uiKey in pairs(SELECTION_FILTERS) do
		state[field] = ui[uiKey] or {}
	end
	return state
end

function Tradewright:FilterInventoryRows(rows, filters)
	return self.FilterLogic.FilterInventoryRows(rows, filters, function(itemID)
		return self:GetItemFilterInfo(itemID).quality
	end)
end

function Tradewright:GetInventoryRoleFilterOptions()
	return {
		{ value = "all", label = L["All roles"] },
		{ value = "crafted", label = L["Crafted"] },
		{ value = "crafting_reagent", label = L["Crafting reagent"] },
		{ value = "crafted_reagent", label = L["Crafted + reagent"] },
		{ value = "tracked", label = L["Other"] },
	}
end

function Tradewright:GetInventoryCharacterFilterOptions()
	self:InitDB()
	local db = self.db
	local currentKey = self:GetCharacterKey()
	local options = {
		{ value = "all", label = L["All characters"] },
	}
	for _, characterKey in ipairs(self:GetDashboardCharacterKeyList(db)) do
		options[#options + 1] = {
			value = characterKey,
			label = self:GetDashboardSidebarCharacterLabel(characterKey, db.characters and db.characters[characterKey], currentKey),
		}
	end
	return options
end

function Tradewright:GetInventoryTypeFilterOptions(rows)
	local seen = {}
	local options = {
		{ value = "all", label = L["All item types"] },
	}
	for _, row in ipairs(rows or {}) do
		local label = row.itemTypeLabel
		if label and label ~= "" and not seen[label] then
			seen[label] = true
			options[#options + 1] = {
				value = label,
				label = label,
			}
		end
	end
	table.sort(options, function(left, right)
		if left.value == "all" then
			return true
		end
		if right.value == "all" then
			return false
		end
		return left.label < right.label
	end)
	return options
end

function Tradewright:UpgradeLegacyInventoryFilterSelection(singleValue)
	if type(singleValue) == "string" and singleValue ~= "" and singleValue ~= "all" then
		return {
			[singleValue] = true,
		}
	end
	return {}
end

-- "12 · 10 bags · 2 bank" (plus warband on retail): how many of the item the shown characters hold, and where.
function Tradewright:GetInventoryHeldText(rowData)
	local where = string.format(L["%s bags · %s bank"], self:FormatNumberGrouped(rowData.bags or 0), self:FormatNumberGrouped(rowData.bank or 0))
	if self.IS_RETAIL and (rowData.warband or 0) > 0 then
		where = where .. " · " .. self:FormatNumberGrouped(rowData.warband) .. L[" warband"]
	end
	return self:FormatNumberGrouped(rowData.total or 0) .. " · " .. where
end

function Tradewright:HandleInventoryRowEnter(rowFrame, rowData)
	if not rowData or not rowData.itemID then
		return
	end
	local lines = {
		{ L["On the shown characters"], self:GetInventoryHeldText(rowData) },
	}
	for _, holder in ipairs(rowData.holders or {}) do
		lines[#lines + 1] = { self:GetCharacterNameMarkup(holder.key), self:FormatNumberGrouped(holder.count) }
	end
	self:ShowItemRowTooltip(rowFrame, rowData.itemID, lines, L["Click for details · Shift-click to link"])
end

local GAP = 12

function Tradewright:LayoutInventoryPanel(panel)
	if not panel then
		return
	end
	local ui = self.ui
	local open = ui.invSelectedItemID ~= nil
	panel.detailPane:SetShown(open)
	panel.inventoryTable.frame:ClearAllPoints()
	panel.inventoryTable.frame:SetPoint("TOPLEFT", panel.filterRow, "BOTTOMLEFT", 0, -GAP)
	if open then
		panel.inventoryTable.frame:SetPoint("BOTTOMRIGHT", panel.detailPane, "BOTTOMLEFT", -GAP, 0)
	else
		panel.inventoryTable.frame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
	end
	panel.detailPane:Layout()
end

function Tradewright:RenderInventoryDetails(itemID)
	local ui = self.ui
	local panel = ui and ui.inventoryPanel or nil
	if not panel then
		return
	end
	if itemID then
		panel.detailPane:ShowItem(itemID, {
			selectedCharacters = ui.invCharacterFilterValues,
			rangeKey = self:GetInventoryMetricRange(),
			rankIndex = ui.invQualityRankIndex,
		})
	end
	self:LayoutInventoryPanel(panel)
end

-- An inventory filter whose selection is kept in `ui[uiKey]` (and saved in `setting` when given).
local function createFilter(pe, parent, options)
	options.onChanged = options.onChanged or function() pe:RefreshInventoryTab() end
	return pe:CreateFilterDropdown(parent, options)
end

-- Copies saved and legacy filter selections into `ui`, where the dropdowns read and change them.
function Tradewright:RestoreInventoryFilterSelections()
	local ui = self.ui
	ui.invRoleFilterValues = ui.invRoleFilterValues or self:UpgradeLegacyInventoryFilterSelection(ui.invRoleFilterValue)
	ui.invTypeFilterValues = ui.invTypeFilterValues or self:UpgradeLegacyInventoryFilterSelection(ui.invTypeFilterValue)
	ui.invCharacterFilterValues = ui.invCharacterFilterValues or {}
	ui.invRoleFilterValue = nil
	ui.invTypeFilterValue = nil
	ui.invExpansionFilterValues = {}
	for key, value in pairs(self:GetSetting("inventory.selectedExpansions", {}) or {}) do
		if value then
			ui.invExpansionFilterValues[key] = true
		end
	end
	self:RestoreInventoryExtraFilters()
end

-- Second-row filters (quality, location, has a price, profitable) from the saved settings.
function Tradewright:RestoreInventoryExtraFilters()
	local ui = self.ui
	local saved = self:GetSetting("inventory.extraFilters", {}) or {}
	ui.invQualityFilterValues = ui.invQualityFilterValues or saved.qualities or {}
	ui.invLocationFilterValues = ui.invLocationFilterValues or saved.locations or {}
	if ui.invHasPriceOnly == nil then
		ui.invHasPriceOnly = saved.hasPrice == true
	end
	if ui.invProfitableOnly == nil then
		ui.invProfitableOnly = saved.profitable == true
	end
end

-- "Columns 5/12": shown columns out of all but the item name.
function Tradewright:InventoryColumnsText()
	local visible, total = 0, 0
	for _, column in ipairs(self:GetInventoryColumnOrder()) do
		if column.id ~= "name" then
			total = total + 1
			if self:IsInventoryColumnVisible(column.id) then
				visible = visible + 1
			end
		end
	end
	return string.format(L["Columns %d/%d"], visible, total)
end

-- One check button per column, then Reset columns.
function Tradewright:InitializeInventoryColumnsMenu(level)
	if level ~= 1 then
		return
	end
	for _, column in ipairs(self:GetInventoryColumnOrder()) do
		if column.id ~= "name" then
			local info = UIDropDownMenu_CreateInfo()
			info.text = column.label
			info.isNotRadio = true
			info.keepShownOnClick = true
			info.checked = self:IsInventoryColumnVisible(column.id)
			info.func = function()
				self:SetInventoryColumnVisible(column.id, not self:IsInventoryColumnVisible(column.id))
				self:RefreshInventoryTab()
			end
			UIDropDownMenu_AddButton(info, level)
		end
	end
	local reset = UIDropDownMenu_CreateInfo()
	reset.text = L["Reset columns"]
	reset.notCheckable = true
	reset.func = function()
		self:SetSetting("inventory.columnOrder", {})
		self:SetSetting("inventory.hiddenColumns", {})
		self:RefreshInventoryTab()
	end
	UIDropDownMenu_AddButton(reset, level)
end

-- Type, role, (retail) expansion and character filters, right to left after `chain`.
function Tradewright:CreateInventoryFilterDropdowns(parent, chain)
	local pe, ui = self, self.ui
	ui.invTypeDropdown = createFilter(pe, parent, { width = 124, allLabel = L["All item types"], uiKey = "invTypeFilterValues",
		getOptions = function() return pe:GetInventoryTypeFilterOptions(ui.invTypeFilterSeedRows or {}) end })
	ui.invRoleDropdown = createFilter(pe, parent, { width = 116, allLabel = L["All roles"], uiKey = "invRoleFilterValues",
		getOptions = function() return pe:GetInventoryRoleFilterOptions() end })
	ui.invCharacterDropdown = createFilter(pe, parent, { width = 136, allLabel = L["All characters"], uiKey = "invCharacterFilterValues",
		getOptions = function() return pe:GetInventoryCharacterFilterOptions() end })
	chain[#chain + 1] = ui.invTypeDropdown
	chain[#chain + 1] = ui.invRoleDropdown
	if self.IS_RETAIL then
		ui.invExpansionDropdown = createFilter(pe, parent, { width = 124, allLabel = L["All expansions"],
			uiKey = "invExpansionFilterValues", setting = "inventory.selectedExpansions",
			getOptions = function() return pe:GetExpansionFilterOptions() end })
		chain[#chain + 1] = ui.invExpansionDropdown
	end
	chain[#chain + 1] = ui.invCharacterDropdown
	self:ChainLeft(chain, 8)
end

-- Toolbar: search fills the space left of the filters, Columns and Refresh.
function Tradewright:CreateInventoryToolbar(panel)
	local pe, ui = self, self.ui
	panel.toolbar = CreateFrame("Frame", nil, panel)
	panel.toolbar:SetPoint("TOPLEFT")
	panel.toolbar:SetPoint("TOPRIGHT")
	panel.toolbar:SetHeight(26)
	panel.refreshButton = self:CreateButton(panel.toolbar, L["Refresh"], function()
		pe:DashboardRefreshInventory()
	end, { primary = true, tooltip = L["Read bags and bank again on this character."] })
	panel.refreshButton:SetPoint("RIGHT")
	panel.columnsDropdown = self:CreateMenuDropdown(panel.toolbar, {
		width = 104,
		getText = function() return pe:InventoryColumnsText() end,
		initializeMenu = function(level) pe:InitializeInventoryColumnsMenu(level) end,
	})
	panel.rangeDropdown = self:CreateSingleSelectDropdown(panel.toolbar, {
		width = 100,
		getOptions = function() return pe:GetInventoryMetricRangeOptions() end,
		getValue = function() return pe:GetInventoryMetricRange() end,
		setValue = function(value) pe:SetInventoryMetricRange(value) end,
		onChanged = function() pe:RefreshInventoryTab() end,
		tooltip = L["Time range for averages and charts"],
	})
	self:CreateInventoryFilterDropdowns(panel.toolbar, { panel.refreshButton, panel.columnsDropdown, panel.rangeDropdown })
	ui.invSearchBox = self:CreateSearchBox(panel.toolbar, L["Search name, ID or type"], function()
		pe:RefreshInventoryTab()
	end)
	ui.invSearchBox:SetPoint("LEFT", panel.toolbar, "LEFT", 6, 0)
	ui.invSearchBox:SetPoint("RIGHT", ui.invCharacterDropdown, "LEFT", -14, 0)
end

-- Saves the second-row filters and redraws.
function Tradewright:SaveInventoryExtraFilters()
	local ui = self.ui
	self:SetSetting("inventory.extraFilters", {
		qualities = ui.invQualityFilterValues,
		locations = ui.invLocationFilterValues,
		hasPrice = ui.invHasPriceOnly,
		profitable = ui.invProfitableOnly,
	})
	self:RefreshInventoryTab()
end

function Tradewright:ResetInventoryFilters()
	local ui = self.ui
	ui.invCharacterFilterValues, ui.invRoleFilterValues, ui.invTypeFilterValues = {}, {}, {}
	ui.invExpansionFilterValues, ui.invQualityFilterValues, ui.invLocationFilterValues = {}, {}, {}
	ui.invHasPriceOnly, ui.invProfitableOnly = false, false
	ui.invSearchBox:SetText("")
	ui.invSearchBox:UpdatePlaceholder()
	self:SetSetting("inventory.selectedExpansions", {})
	self:SaveInventoryExtraFilters()
end

function Tradewright:GetInventoryLocationFilterOptions()
	local options = { { value = "bags", label = L["In bags"] }, { value = "bank", label = L["In the bank"] } }
	if self.IS_RETAIL then
		options[#options + 1] = { value = "warband", label = L["In the warband bank"] }
	end
	return options
end

-- Row 2: quality, where stored, has a price, profitable only, reset.
function Tradewright:CreateInventoryFilterRow(panel)
	local pe, ui = self, self.ui
	local function saveAndRefresh()
		pe:SaveInventoryExtraFilters()
	end
	panel.filterRow = CreateFrame("Frame", nil, panel)
	panel.filterRow:SetPoint("TOPLEFT", panel.toolbar, "BOTTOMLEFT", 0, -8)
	panel.filterRow:SetPoint("TOPRIGHT", panel.toolbar, "BOTTOMRIGHT", 0, -8)
	panel.filterRow:SetHeight(26)
	ui.invQualityDropdown = createFilter(pe, panel.filterRow, { width = 128, allLabel = L["Any quality"], uiKey = "invQualityFilterValues",
		getOptions = function() return pe:GetQualityFilterOptions() end, onChanged = saveAndRefresh })
	ui.invQualityDropdown:SetPoint("LEFT")
	ui.invLocationDropdown = createFilter(pe, panel.filterRow, { width = 136, allLabel = L["Bags and bank"], uiKey = "invLocationFilterValues",
		getOptions = function() return pe:GetInventoryLocationFilterOptions() end, onChanged = saveAndRefresh })
	panel.hasPrice = self:CreateCheckbox(panel.filterRow, L["Has a price"], function(checked)
		ui.invHasPriceOnly = checked
		saveAndRefresh()
	end)
	panel.profitable = self:CreateCheckbox(panel.filterRow, L["Profitable only"], function(checked)
		ui.invProfitableOnly = checked
		saveAndRefresh()
	end)
	panel.resetFilters = self:CreateButton(panel.filterRow, L["Reset filters"], function() pe:ResetInventoryFilters() end, { small = true })
	self:ChainRight({ ui.invQualityDropdown, ui.invLocationDropdown, panel.hasPrice, panel.profitable, panel.resetFilters }, 12)
end

function Tradewright:OnInventoryRowClick(rowData, tableWidget)
	if self:HandleItemRowModifiedClick(rowData and rowData.itemID) then
		return
	end
	self:OpenItemDetails(rowData and rowData.itemID, {
		selectedCharacters = self.ui.invCharacterFilterValues,
		rangeKey = self:GetInventoryMetricRange(),
	})
	tableWidget:SetSelectedRow(rowData)
end

function Tradewright:CreateInventoryTable(panel)
	local pe, ui = self, self.ui
	local inventoryTable = self:CreateReusableTable(panel, {
		footer = true,
		emptyTitle = L["No items"],
		emptyHint = L["Press Refresh to read bags and bank, or change the filters."],
		isRowSelected = function(rowData)
			return rowData and ui.invSelectedItemID ~= nil and tonumber(rowData.itemID) == ui.invSelectedItemID
		end,
		maxRows = INV_MAX_ROWS,
		viewportVirtualize = true,
		virtualOverscan = 8,
		autoFitToScroll = true,
		sortKey = ui.invSortKey or "qty",
		sortAsc = ui.invSortAsc == true,
		onSortChanged = function(sortKey, sortAsc)
			ui.invSortKey = sortKey
			ui.invSortAsc = sortAsc
		end,
		onColumnReordered = function(_, _, columns) pe:SaveInventoryColumnOrder(columns) end,
		onRowEnter = function(rowFrame, rowData) pe:HandleInventoryRowEnter(rowFrame, rowData) end,
		onRowLeave = function() GameTooltip:Hide() end,
		onRowClick = function(_, rowData, _, tableWidget) pe:OnInventoryRowClick(rowData, tableWidget) end,
	})
	inventoryTable:SetColumns(self:BuildInventoryTableColumns())
	return inventoryTable
end

function Tradewright:EnsureInventoryPanel(mainFrame)
	local pe, ui = self, self.ui
	if ui.inventoryPanel then
		return
	end
	local panel = CreateFrame("Frame", nil, mainFrame)
	panel:SetAllPoints()
	ui.inventoryPanel = panel
	self:RestoreInventoryFilterSelections()
	self:CreateInventoryToolbar(panel)
	self:CreateInventoryFilterRow(panel)
	panel.detailPane = self:CreateItemDetailPane(panel, {
		metricSettingKey = "inventory.detailsGraphMetric",
		onClose = function()
			ui.invSelectedItemID = nil
			ui.inventoryTable:SetSelectedRow(nil)
			pe:LayoutInventoryPanel(panel)
		end,
	})
	panel.detailPane:SetPoint("TOPRIGHT", panel.filterRow, "BOTTOMRIGHT", 0, -GAP)
	panel.detailPane:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
	ui.inventoryTable = self:CreateInventoryTable(panel)
	panel.inventoryTable = ui.inventoryTable
	panel:SetScript("OnSizeChanged", function()
		pe:LayoutInventoryPanel(panel)
	end)
	self:LayoutInventoryPanel(panel)
	self:RenderInventoryDetails(ui.invSelectedItemID)
end

-- One row per item held by the selected characters, with prices and craft analytics filled in.
-- Also seeds the item-type options from every character, so the type list does not shrink with the selection.
function Tradewright:BuildInventoryTabRows(characterOptions)
	local db, ui = self.db, self.ui
	local selection = ui.invCharacterFilterValues
	local characterColumnLabel = self:GetFilterSelectionSummary(characterOptions, selection, L["All characters"])
	local mergedRoleMap, perCharRoleMaps = self:BuildMergedItemRoleMapForSelection(db, selection)
	local rows = self:BuildInventoryRowsAggregatedByItem(db, selection, characterColumnLabel, mergedRoleMap)
	local allCharsLabel = self:GetFilterSelectionSummary(characterOptions, {}, L["All characters"])
	ui.invTypeFilterSeedRows = self:BuildInventoryRowsAggregatedByItem(db, {}, allCharsLabel)

	local metricRange = self:GetInventoryMetricRange()
	local rankIndex = self:BuildOutputItemQualityRankIndex(selection)
	ui.invQualityRankIndex = rankIndex
	local enrichOpts = {
		roleMap = mergedRoleMap,
		selectedCharacters = selection,
		rangeKey = metricRange,
		rankIndex = rankIndex,
		historyStatsMemo = {},
		perCharacterRoleMaps = perCharRoleMaps,
	}
	for _, row in ipairs(rows) do
		self:EnrichInventoryRowAnalytics(row, enrichOpts)
	end
	return rows
end

-- Gives the role, type, expansion and character dropdowns their options and drops stale selections.
function Tradewright:RefreshInventoryFilterDropdowns(characterOptions)
	local ui = self.ui
	local roleOptions = self:GetInventoryRoleFilterOptions()
	local typeOptions = self:GetInventoryTypeFilterOptions(ui.invTypeFilterSeedRows or {})
	local expansionOptions = self:GetExpansionFilterOptions()
	ui.invRoleFilterValues = self:NormalizeFilterSelection(ui.invRoleFilterValues, roleOptions)
	ui.invTypeFilterValues = self:NormalizeFilterSelection(ui.invTypeFilterValues, typeOptions)
	ui.invExpansionFilterValues = self:NormalizeFilterSelection(ui.invExpansionFilterValues or {}, expansionOptions)
	local dropdowns = {
		{ ui.invExpansionDropdown, expansionOptions },
		{ ui.invCharacterDropdown, characterOptions },
		{ ui.invRoleDropdown, roleOptions },
		{ ui.invTypeDropdown, typeOptions },
	}
	for _, entry in ipairs(dropdowns) do
		local dropdown, options = entry[1], entry[2]
		if dropdown then
			dropdown:SetOptions(options)
			dropdown:RefreshText()
		end
	end
end

-- Syncs the toolbar controls that keep their own state with the current settings.
function Tradewright:RefreshInventoryToolbarState()
	local ui = self.ui
	local panel = ui.inventoryPanel
	panel.rangeDropdown:RefreshText()
	ui.invQualityDropdown:RefreshText()
	ui.invLocationDropdown:RefreshText()
	panel.hasPrice.check:SetChecked(ui.invHasPriceOnly == true)
	panel.profitable.check:SetChecked(ui.invProfitableOnly == true)
	panel.columnsDropdown:RefreshText()
end

-- Footer texts: item and unit counts for the selected characters, then the auction and craft value of the shown rows.
function Tradewright:GetInventoryFooterTexts(rows, characterOptions)
	local totalQty, totalValue, totalCraft = 0, 0, 0
	for _, row in ipairs(rows) do
		local count = row.total or 0
		totalQty = totalQty + count
		totalValue = totalValue + (row.currentAhCopper or 0) * count
		totalCraft = totalCraft + (row.avgCraftCost or 0) * count
	end
	local storedCharacterCount = math.max(0, #characterOptions - 1)
	local selectedCharacterCount = self:CountFilterSelection(self.ui.invCharacterFilterValues)
	local characterSummary = selectedCharacterCount == 0
		and string.format(L["all %d characters"], storedCharacterCount)
		or string.format(L["%d of %d characters"], selectedCharacterCount, storedCharacterCount)
	return string.format(L["%s items · %s in total · %s"], self:FormatNumberGrouped(#rows), self:FormatNumberGrouped(totalQty), characterSummary),
		string.format(L["Auction value %s · Craft value %s"], self:FormatCopperShort(totalValue), self:FormatCopperShort(totalCraft))
end

function Tradewright:RefreshInventoryTab()
	self:InitDB()
	local ui = self.ui
	if not ui or not ui.inventoryPanel or ui.activeMainTab ~= "inventory" then
		return
	end
	local characterOptions = self:GetInventoryCharacterFilterOptions()
	ui.invCharacterFilterValues = self:NormalizeFilterSelection(ui.invCharacterFilterValues, characterOptions)
	local rows = self:BuildInventoryTabRows(characterOptions)
	self:RefreshInventoryFilterDropdowns(characterOptions)
	rows = self:FilterInventoryRows(rows, self:BuildInventoryFilterState())
	ui.invWorkingRows = rows
	self:RefreshInventoryToolbarState()

	ui.inventoryTable:SetColumns(self:BuildInventoryTableColumns())
	ui.inventoryTable:SetContext({
		accountMode = true,
	})
	ui.inventoryTable:SetRows(rows)
	ui.inventoryTable:Refresh()
	ui.inventoryTable:SetFooterText(self:GetInventoryFooterTexts(rows, characterOptions))

	self:LayoutInventoryPanel(ui.inventoryPanel)
	self:RenderInventoryDetails(ui.invSelectedItemID)
end

function Tradewright:RefreshInventoryTabIfVisible()
	local ui = self.ui
	if ui and ui.activeMainTab == "inventory" then
		self:RefreshInventoryTab()
	end
end

