local _, ProfessionExporter = ...

local INV_MAX_ROWS = 550

-- Fixed column widths: money columns fit a short amount such as "1,240[g] 35[s]".
local COL = {
	qty = 52,
	holders = 170,
	loc = 92,
	currentAh = 86,
	lastSeen = 86,
	avgSeen = 86,
	avgCraft = 86,
	lastCraft = 86,
	profitUnit = 90,
	profitStack = 90,
	saleRate = 44,
	seenAt = 56,
}

local function trim(text)
	if not text then
		return ""
	end
	return (string.gsub(tostring(text), "^%s*(.-)%s*$", "%1"))
end

local function compareTriple(leftA, leftB, leftC, rightA, rightB, rightC)
	leftA = tonumber(leftA) or 0
	leftB = tonumber(leftB) or 0
	leftC = tonumber(leftC) or 0
	rightA = tonumber(rightA) or 0
	rightB = tonumber(rightB) or 0
	rightC = tonumber(rightC) or 0
	if leftA ~= rightA then
		return leftA < rightA and -1 or 1
	end
	if leftB ~= rightB then
		return leftB < rightB and -1 or 1
	end
	if leftC ~= rightC then
		return leftC < rightC and -1 or 1
	end
	return 0
end

local function rankMarkup(rankIndex)
	return ProfessionExporter:GetRankMarkup(rankIndex)
end

-- "Bånkey 30, Alt 10": who holds the item (bags + bank), most first.
local function holdersText(pe, row)
	local muted = pe:GetTheme().textMuted
	local countFmt = string.format(" |cff%02x%02x%02x%%s|r", muted.r * 255, muted.g * 255, muted.b * 255)
	local parts = {}
	for _, holder in ipairs(row.holders or {}) do
		parts[#parts + 1] = pe:GetCharacterNameMarkup(holder.key) .. string.format(countFmt, pe:FormatNumberGrouped(holder.count))
	end
	return #parts > 0 and table.concat(parts, ", ") or "-"
end

function ProfessionExporter:BuildInventoryFilterState()
	local ui = self.ui or {}
	return {
		text = trim(ui.invSearchBox and ui.invSearchBox:GetText() or ""),
		characters = ui.invCharacterFilterValues or {},
		role = ui.invRoleFilterValues or {},
		itemType = ui.invTypeFilterValues or {},
		expansions = self.IS_RETAIL and ui.invExpansionFilterValues or {},
		qualities = ui.invQualityFilterValues or {},
		locations = ui.invLocationFilterValues or {},
		hasPrice = ui.invHasPriceOnly == true,
		profitable = ui.invProfitableOnly == true,
	}
end

function ProfessionExporter:FilterInventoryRows(rows, filters)
	filters = filters or {}
	local filter = string.lower(trim(filters.text))
	local characterFilter = filters.characters or {}
	local roleFilter = filters.role or {}
	local itemTypeFilter = filters.itemType or {}
	local expSel = filters.expansions or {}
	local showAllExpansions = self:IsFilterSelectionEmpty(expSel)
	local out = {}

	for _, row in ipairs(rows or {}) do
		local matchesText = true
		if filter ~= "" then
			matchesText = false
			local haystacks = {
				tostring(row.itemID or ""),
				tostring(row.name or ""),
				tostring(row.roleLabel or ""),
				tostring(row.itemTypeLabel or ""),
				tostring(row.itemSubTypeLabel or ""),
			}
			for _, text in ipairs(haystacks) do
				if string.find(string.lower(text), filter, 1, true) then
					matchesText = true
					break
				end
			end
		end

		local matchesCharacter = row.aggregatedInventory
			or self:IsFilterSelectionEmpty(characterFilter)
			or characterFilter[row.characterKey] == true
		local matchesRole = self:IsFilterSelectionEmpty(roleFilter) or roleFilter[row.roleKey] == true
		local matchesType = self:IsFilterSelectionEmpty(itemTypeFilter) or itemTypeFilter[row.itemTypeLabel] == true
		local expTag = row.expansionTag or "legacy"
		local matchesExpansion = showAllExpansions or expSel[expTag] == true
		local matchesExtra = (not filters.hasPrice or (tonumber(row.currentAhCopper) or 0) > 0)
			and (not filters.profitable or (tonumber(row.profitCopperPerUnit) or 0) > 0)
		if matchesExtra and not self:IsFilterSelectionEmpty(filters.locations) then
			matchesExtra = (filters.locations.bags and (tonumber(row.bags) or 0) > 0)
				or (filters.locations.bank and (tonumber(row.bank) or 0) > 0)
				or (filters.locations.warband and (tonumber(row.warband) or 0) > 0)
				or false
		end
		if matchesExtra and not self:IsFilterSelectionEmpty(filters.qualities) then
			local quality = self:GetItemFilterInfo(row.itemID).quality
			matchesExtra = quality ~= nil and filters.qualities[quality] == true
		end
		if matchesText and matchesCharacter and matchesRole and matchesType and matchesExpansion and matchesExtra then
			out[#out + 1] = row
		end
	end

	return out
end

function ProfessionExporter:GetInventoryRoleFilterOptions()
	return {
		{ value = "all", label = "All roles" },
		{ value = "crafted", label = "Crafted" },
		{ value = "crafting_reagent", label = "Crafting reagent" },
		{ value = "crafted_reagent", label = "Crafted + reagent" },
		{ value = "tracked", label = "Tracked" },
	}
end

function ProfessionExporter:GetInventoryCharacterFilterOptions()
	self:InitDB()
	local db = self.db
	local currentKey = self:GetCharacterKey()
	local options = {
		{ value = "all", label = "All characters" },
	}
	for _, characterKey in ipairs(self:GetDashboardCharacterKeyList(db)) do
		options[#options + 1] = {
			value = characterKey,
			label = self:GetDashboardSidebarCharacterLabel(characterKey, db.characters and db.characters[characterKey], currentKey),
		}
	end
	return options
end

function ProfessionExporter:GetInventoryTypeFilterOptions(rows)
	local seen = {}
	local options = {
		{ value = "all", label = "All item types" },
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

function ProfessionExporter:UpgradeLegacyInventoryFilterSelection(singleValue)
	if type(singleValue) == "string" and singleValue ~= "" and singleValue ~= "all" then
		return {
			[singleValue] = true,
		}
	end
	return {}
end

function ProfessionExporter:GetInventoryColumnDefinitions()
	return {
		ProfessionExporter:CreateItemColumn({
			label = "Item",
			defaultSort = "asc",
			getItemID = function(row) return row.itemID end,
			getName = function(row)
				return ProfessionExporter:GetItemDisplayName(row.itemID) .. rankMarkup(row.rankIndex)
			end,
			getIcon = function(row) return row.icon end,
			sortValue = function(row) return row.name or "" end,
		}),
		{
			id = "qty",
			label = "Qty",
			justifyH = "RIGHT",
			width = COL.qty,
			minWidth = 40,
			flex = 0,
			sortable = true,
			defaultSort = "desc",
			defaultVisible = true,
			sortValue = function(row)
				return row.total or 0
			end,
			getText = function(row)
				return ProfessionExporter:FormatNumberGrouped(row.total or 0)
			end,
		},
		{
			id = "holders",
			label = "Characters",
			optional = true,
			dropFirst = true, -- first column to go when the window is narrow
			tooltipTitle = "Characters",
			tooltipText = "Who holds the item in bags and bank, most first. Hover a row for the full list.",
			width = COL.holders,
			minWidth = 100,
			flex = 0,
			sortable = true,
			defaultSort = "desc",
			defaultVisible = true,
			sortValue = function(row)
				return #(row.holders or {})
			end,
			getText = function(row)
				return holdersText(ProfessionExporter, row)
			end,
		},
		{
			id = "loc",
			label = "Bags / bank",
			optional = true,
			justifyH = "RIGHT",
			width = COL.loc,
			minWidth = 56,
			flex = 0,
			sortable = true,
			defaultSort = "desc",
			defaultVisible = false,
			compare = function(left, right)
				return compareTriple(left.bags, left.bank, left.warband, right.bags, right.bank, right.warband)
			end,
			getText = function(row)
				local text = ProfessionExporter:FormatNumberGrouped(row.bags or 0) .. " / " .. ProfessionExporter:FormatNumberGrouped(row.bank or 0)
				if ProfessionExporter.IS_RETAIL and (row.warband or 0) > 0 then
					text = text .. " / " .. ProfessionExporter:FormatNumberGrouped(row.warband)
				end
				return text
			end,
		},
		{
			id = "currentAh",
			label = "Current AH",
			optional = true,
			justifyH = "RIGHT",
			width = COL.currentAh,
			minWidth = 56,
			flex = 0,
			sortable = true,
			defaultSort = "desc",
			defaultVisible = true,
			sortValue = function(row)
				return row.currentAhCopper or -1
			end,
			getText = function(row)
				return row.currentAhCopper and ProfessionExporter:FormatCopperShort(row.currentAhCopper) or "-"
			end,
		},
		{
			id = "lastSeen",
			label = "Last AH",
			optional = true,
			justifyH = "RIGHT",
			width = COL.lastSeen,
			minWidth = 56,
			flex = 0,
			sortable = true,
			defaultSort = "desc",
			defaultVisible = false,
			sortValue = function(row)
				return row.lastObservedPrice or -1
			end,
			getText = function(row)
				return row.lastObservedPrice and ProfessionExporter:FormatCopperShort(row.lastObservedPrice) or "-"
			end,
		},
		{
			id = "avgSeen",
			label = "Avg AH",
			optional = true,
			justifyH = "RIGHT",
			width = COL.avgSeen,
			minWidth = 56,
			flex = 0,
			sortable = true,
			defaultSort = "desc",
			defaultVisible = false,
			sortValue = function(row)
				return row.avgObservedPrice or -1
			end,
			getText = function(row)
				return row.avgObservedPrice and ProfessionExporter:FormatCopperShort(row.avgObservedPrice) or "-"
			end,
		},
		{
			id = "avgCraft",
			label = "Avg craft",
			optional = true,
			justifyH = "RIGHT",
			width = COL.avgCraft,
			minWidth = 56,
			flex = 0,
			sortable = true,
			defaultSort = "desc",
			defaultVisible = true,
			sortValue = function(row)
				return row.avgCraftCost or -1
			end,
			getText = function(row)
				return row.avgCraftCost and ProfessionExporter:FormatCopperShort(row.avgCraftCost) or "-"
			end,
		},
		{
			id = "lastCraft",
			label = "Last craft",
			optional = true,
			justifyH = "RIGHT",
			width = COL.lastCraft,
			minWidth = 56,
			flex = 0,
			sortable = true,
			defaultSort = "desc",
			defaultVisible = false,
			sortValue = function(row)
				return row.lastCraftCost or -1
			end,
			getText = function(row)
				return row.lastCraftCost and ProfessionExporter:FormatCopperShort(row.lastCraftCost) or "-"
			end,
		},
		{
			id = "profitUnit",
			label = "Profit each",
			optional = true,
			justifyH = "RIGHT",
			width = COL.profitUnit,
			minWidth = 56,
			flex = 0,
			sortable = true,
			defaultSort = "desc",
			defaultVisible = true,
			sortValue = function(row)
				return row.profitCopperPerUnit or -1
			end,
			getText = function(row)
				return row.profitCopperPerUnit and ProfessionExporter:FormatCopperShort(row.profitCopperPerUnit) or "-"
			end,
		},
		{
			id = "profitStack",
			label = "Profit, all",
			optional = true,
			justifyH = "RIGHT",
			width = COL.profitStack,
			minWidth = 56,
			flex = 0,
			sortable = true,
			defaultSort = "desc",
			defaultVisible = false,
			sortValue = function(row)
				return row.profitCopperStack or -1
			end,
			getText = function(row)
				return row.profitCopperStack and ProfessionExporter:FormatCopperShort(row.profitCopperStack) or "-"
			end,
		},
		{
			id = "saleRate",
			label = "SR",
			optional = true,
			tooltipTitle = "Sale rate",
			tooltipText = "TSM regional sale rate: the share of listings that sell.",
			justifyH = "RIGHT",
			width = COL.saleRate,
			minWidth = 44,
			flex = 0,
			sortable = true,
			defaultSort = "desc",
			defaultVisible = true,
			sortValue = function(row)
				return row.saleRateValue or -1
			end,
			getText = function(row)
				return row.saleRateDisplay or "-"
			end,
		},
		{
			id = "seenAt",
			label = "Seen",
			optional = true,
			justifyH = "RIGHT",
			width = COL.seenAt,
			minWidth = 88,
			flex = 0,
			sortable = true,
			defaultSort = "desc",
			defaultVisible = false,
			sortValue = function(row)
				return row.currentAhAt or 0
			end,
			getText = function(row)
				return ProfessionExporter:FormatShortTime(row.currentAhAt)
			end,
		},
	}
end

function ProfessionExporter:GetInventoryColumnOrder()
	local savedOrder = self:GetSetting("inventory.columnOrder", {})
	-- The item column always comes first.
	local definitions = self:GetInventoryColumnDefinitions()
	local byId = {}
	local ordered = {}
	for _, definition in ipairs(definitions) do
		byId[definition.id] = definition
	end
	for _, columnId in ipairs(savedOrder or {}) do
		if byId[columnId] then
			ordered[#ordered + 1] = byId[columnId]
			byId[columnId] = nil
		end
	end
	for _, definition in ipairs(definitions) do
		if byId[definition.id] then
			ordered[#ordered + 1] = definition
		end
	end
	return ordered
end

function ProfessionExporter:SaveInventoryColumnOrder(columns)
	local order = {}
	for _, column in ipairs(columns or {}) do
		order[#order + 1] = column.id
	end
	self:SetSetting("inventory.columnOrder", order)
end

function ProfessionExporter:IsInventoryColumnVisible(columnId)
	local hidden = self:GetSetting("inventory.hiddenColumns", {})
	for _, definition in ipairs(self:GetInventoryColumnDefinitions()) do
		if definition.id == columnId then
			if hidden[columnId] == nil then
				return definition.defaultVisible ~= false
			end
			return hidden[columnId] ~= true
		end
	end
	return hidden[columnId] ~= true
end

function ProfessionExporter:SetInventoryColumnVisible(columnId, visible)
	local hidden = self:GetSetting("inventory.hiddenColumns", {})
	local defaultVisible = true
	for _, definition in ipairs(self:GetInventoryColumnDefinitions()) do
		if definition.id == columnId then
			defaultVisible = definition.defaultVisible ~= false
			break
		end
	end
	if visible == defaultVisible then
		hidden[columnId] = nil
	else
		hidden[columnId] = not visible
	end
	self:SetSetting("inventory.hiddenColumns", hidden)
end

function ProfessionExporter:BuildInventoryTableColumns()
	local hidden = self:GetSetting("inventory.hiddenColumns", {})
	local columns = {}
	for _, definition in ipairs(self:GetInventoryColumnOrder()) do
		local column = {}
		for key, value in pairs(definition) do
			column[key] = value
		end
		local baseVisible = definition.visible
		column.visible = function(context)
			if hidden[definition.id] == true or (hidden[definition.id] == nil and definition.defaultVisible == false) then
				return false
			end
			if type(baseVisible) == "function" then
				return baseVisible(context) ~= false
			end
			if baseVisible == nil then
				return true
			end
			return baseVisible ~= false
		end
		columns[#columns + 1] = column
	end
	return columns
end

function ProfessionExporter:HandleInventoryRowEnter(rowFrame, rowData)
	if not rowData or not rowData.itemID then
		return
	end
	local where = string.format("%s bags · %s bank", self:FormatNumberGrouped(rowData.bags or 0), self:FormatNumberGrouped(rowData.bank or 0))
	if self.IS_RETAIL and (rowData.warband or 0) > 0 then
		where = where .. " · " .. self:FormatNumberGrouped(rowData.warband) .. " warband"
	end
	local lines = {
		{ "On the shown characters", self:FormatNumberGrouped(rowData.total or 0) .. " · " .. where },
	}
	for _, holder in ipairs(rowData.holders or {}) do
		lines[#lines + 1] = { self:GetCharacterNameMarkup(holder.key), self:FormatNumberGrouped(holder.count) }
	end
	self:ShowItemRowTooltip(rowFrame, rowData.itemID, lines, "Click for details · Shift-click to link")
end

local GAP = 12
local DETAIL_WIDTH = 288

function ProfessionExporter:LayoutInventoryPanel(panel)
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

function ProfessionExporter:RenderInventoryDetails(itemID)
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

-- Item detail pane shared by item views: header, key facts, a chart with three views, and the
-- recipes that make or use the item. `opts.metricSettingKey` stores the chosen chart.
function ProfessionExporter:CreateItemDetailPane(parent, opts)
	opts = opts or {}
	local pe = self
	local pad = 10
	local pane = self:CreateInset(parent)
	pane:SetWidth(opts.width or DETAIL_WIDTH)
	if pane.SetClipsChildren then
		pane:SetClipsChildren(true)
	end
	pane.header = self:CreateDetailHeader(pane, opts.onClose)
	pane.header:SetPoint("TOPLEFT", pad, -pad)
	pane.header:SetPoint("TOPRIGHT", -pad, -pad)
	pane.facts = self:CreateKeyValueList(pane)
	pane.facts:SetPoint("TOPLEFT", pane.header, "BOTTOMLEFT", 0, -10)
	pane.facts:SetPoint("TOPRIGHT", pane.header, "BOTTOMRIGHT", 0, -10)

	pane.metricButtons = {}
	local metrics = { { "market", "Price" }, { "crafting", "Craft cost" }, { "quantity", "Quantity" } }
	for index, metric in ipairs(metrics) do
		local button = self:CreateButton(pane, metric[2], function()
			pe:SetSetting(opts.metricSettingKey, metric[1])
			pane:ShowItem(pane.itemID, pane.context)
		end, { small = true })
		button.metric = metric[1]
		pane.metricButtons[index] = button
	end
	pane.graph = self:CreateTimeSeriesGraph(pane, { showTitle = false, plotHeight = 92, emptyText = "No history in this range." })

	pane.madeHeading = self:CreateHeading(pane, "Made by")
	pane.madeList = self:CreateKeyValueList(pane)
	pane.usedHeading = self:CreateHeading(pane, "Used in")
	pane.usedList = self:CreateKeyValueList(pane)
	pane.usedEmpty = self:CreateText(pane, "GameFontHighlightSmall", "textMuted")
	pane.madeEmpty = self:CreateText(pane, "GameFontHighlightSmall", "textMuted")

	function pane:Layout()
		local inner = self:GetWidth() - pad * 2
		local buttonWidth = math.floor((inner + 1 * (#self.metricButtons - 1)) / #self.metricButtons)
		for index, button in ipairs(self.metricButtons) do
			button:ClearAllPoints()
			button:SetWidth(buttonWidth)
			button:SetPoint("TOPLEFT", self.facts, "BOTTOMLEFT", (index - 1) * (buttonWidth - 1), -10)
		end
		self.graph:ClearAllPoints()
		self.graph:SetPoint("TOPLEFT", self.metricButtons[1], "BOTTOMLEFT", 0, -6)
		self.graph:SetWidth(inner)
		local function place(heading, list, empty, anchor)
			heading:ClearAllPoints()
			heading:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
			heading:SetWidth(inner)
			list:ClearAllPoints()
			list:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -6)
			list:SetWidth(inner)
			empty:ClearAllPoints()
			empty:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -6)
			empty:SetWidth(inner)
			return empty:IsShown() and empty or list
		end
		local last = place(self.madeHeading, self.madeList, self.madeEmpty, self.graph)
		place(self.usedHeading, self.usedList, self.usedEmpty, last)
	end

	function pane:ShowItem(itemID, context)
		self.itemID, self.context = itemID, context or {}
		if not itemID then
			return
		end
		local detail = pe:BuildItemDetailSnapshot(itemID, self.context)
		local economy = detail.economy or {}
		local crafting = detail.crafting or {}
		local totals = economy.inventoryTotals or {}
		local desc = pe:ResolveItemDescriptor(itemID) or {}
		local kind = desc.itemType and (desc.itemSubType and (desc.itemType .. " · " .. desc.itemSubType) or desc.itemType) or ("Item " .. tostring(itemID))
		self.header:SetItem(itemID, pe:GetItemDisplayName(itemID), kind, detail.icon)
		local owned = string.format("%s bags · %s bank", pe:FormatNumberGrouped(totals.bags or 0), pe:FormatNumberGrouped(totals.bank or 0))
		if pe.IS_RETAIL and (totals.warband or 0) > 0 then
			owned = owned .. " · " .. pe:FormatNumberGrouped(totals.warband)
		end
		self.facts:SetRows({
			{ "Auction price", pe:FormatCopperFull(economy.currentMarket) },
			{ "Average auction price", pe:FormatCopperFull(economy.avgObservedPrice) },
			{ "Average craft cost", pe:FormatCopperFull(crafting.avgCraftCost) },
			{ "Owned", owned },
			{ "Price seen", pe:FormatScanTimestamp(economy.currentMarketAt) },
		})

		local metric = pe:GetSetting(opts.metricSettingKey, "market")
		for _, button in ipairs(self.metricButtons) do
			pe:StyleShellButton(button, button.metric == metric)
		end
		local produced = crafting.producedBy or {}
		local canCraft = #produced > 0
		local matEst = canCraft and pe:EstimateBestMatCostPerUnitAmongSelection(pe.db, itemID, self.context.selectedCharacters, nil) or nil
		pe:ApplyItemDetailTimeSeriesGraph(itemID, self.graph, {
			metricSettingKey = opts.metricSettingKey,
			rangeKey = detail.rangeKey or pe:GetInventoryMetricRange(),
			quantityCharacterFilter = self.context.selectedCharacters,
			secondaryCraftingOverlay = canCraft and matEst ~= nil,
			currentCraftCostCopper = matEst,
			quantityOverlay = pe:GetSetting("inventory.detailsGraphShowQuantity", true) ~= false,
		})

		local madeRows = {}
		for index = 1, math.min(6, #produced) do
			local entry = produced[index]
			madeRows[#madeRows + 1] = { tostring(entry.recipeName), tostring(entry.characterLabel) .. " · " .. tostring(entry.professionName) }
		end
		self.madeList:SetRows(madeRows)
		self.madeList:SetShown(#madeRows > 0)
		self.madeEmpty:SetShown(#madeRows == 0)
		self.madeEmpty:SetText("No scanned recipe makes this item.")
		local used = crafting.usedBy or {}
		local usedRows = {}
		for index = 1, math.min(6, #used) do
			local entry = used[index]
			usedRows[#usedRows + 1] = {
				string.format("%s x%d", tostring(entry.recipeName), tonumber(entry.quantityRequired) or 0),
				tostring(entry.characterLabel),
			}
		end
		self.usedList:SetRows(usedRows)
		self.usedList:SetShown(#usedRows > 0)
		self.usedEmpty:SetShown(#usedRows == 0)
		self.usedEmpty:SetText("No scanned recipe uses this item.")
		self:Layout()
	end
	return pane
end

local function createFilterDropdown(pe, parent, width, allLabel, getOptions, getSelection, setSelection)
	return pe:CreateMultiSelectDropdown(parent, {
		width = width,
		allLabel = allLabel,
		getOptions = getOptions,
		getSelection = getSelection,
		setSelection = setSelection,
		onChanged = function()
			pe:RefreshInventoryTab()
		end,
	})
end

function ProfessionExporter:EnsureInventoryPanel(mainFrame)
	local ui = self.ui
	if ui.inventoryPanel then
		return
	end
	local pe = self
	local panel = CreateFrame("Frame", nil, mainFrame)
	panel:SetAllPoints()
	ui.inventoryPanel = panel

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

	-- Toolbar: search fills the space left of the filters, Columns and Refresh.
	panel.toolbar = CreateFrame("Frame", nil, panel)
	panel.toolbar:SetPoint("TOPLEFT")
	panel.toolbar:SetPoint("TOPRIGHT")
	panel.toolbar:SetHeight(26)
	panel.refreshButton = self:CreateButton(panel.toolbar, "Refresh", function()
		ProfessionExporter:DashboardRefreshInventory()
	end, { primary = true, tooltip = "Read bags and bank again on this character." })
	panel.refreshButton:SetPoint("RIGHT")
	panel.columnsDropdown = self:CreateMenuDropdown(panel.toolbar, {
		width = 104,
		getText = function()
			local visible, total = 0, 0
			for _, column in ipairs(ProfessionExporter:GetInventoryColumnOrder()) do
				if column.id ~= "name" then
					total = total + 1
					if ProfessionExporter:IsInventoryColumnVisible(column.id) then
						visible = visible + 1
					end
				end
			end
			return string.format("Columns %d/%d", visible, total)
		end,
		initializeMenu = function(level)
			if level ~= 1 then
				return
			end
			for _, column in ipairs(ProfessionExporter:GetInventoryColumnOrder()) do
				if column.id ~= "name" then
					local info = UIDropDownMenu_CreateInfo()
					info.text = column.label
					info.isNotRadio = true
					info.keepShownOnClick = true
					info.checked = ProfessionExporter:IsInventoryColumnVisible(column.id)
					info.func = function()
						ProfessionExporter:SetInventoryColumnVisible(column.id, not ProfessionExporter:IsInventoryColumnVisible(column.id))
						ProfessionExporter:RefreshInventoryTab()
					end
					UIDropDownMenu_AddButton(info, level)
				end
			end
			local reset = UIDropDownMenu_CreateInfo()
			reset.text = "Reset columns"
			reset.notCheckable = true
			reset.func = function()
				ProfessionExporter:SetSetting("inventory.columnOrder", {})
				ProfessionExporter:SetSetting("inventory.hiddenColumns", {})
				ProfessionExporter:RefreshInventoryTab()
			end
			UIDropDownMenu_AddButton(reset, level)
		end,
	})
	panel.rangeDropdown = self:CreateSingleSelectDropdown(panel.toolbar, {
		width = 100,
		getOptions = function() return ProfessionExporter:GetInventoryMetricRangeOptions() end,
		getValue = function() return ProfessionExporter:GetInventoryMetricRange() end,
		setValue = function(value) ProfessionExporter:SetInventoryMetricRange(value) end,
		onChanged = function() ProfessionExporter:RefreshInventoryTab() end,
		tooltip = "Time range for averages and charts",
	})
	ui.invTypeDropdown = createFilterDropdown(pe, panel.toolbar, 124, "All item types",
		function() return pe:GetInventoryTypeFilterOptions(ui.invTypeFilterSeedRows or {}) end,
		function() return ui.invTypeFilterValues end,
		function(selection) ui.invTypeFilterValues = selection end)
	ui.invRoleDropdown = createFilterDropdown(pe, panel.toolbar, 116, "All roles",
		function() return pe:GetInventoryRoleFilterOptions() end,
		function() return ui.invRoleFilterValues end,
		function(selection) ui.invRoleFilterValues = selection end)
	ui.invCharacterDropdown = createFilterDropdown(pe, panel.toolbar, 136, "All characters",
		function() return pe:GetInventoryCharacterFilterOptions() end,
		function() return ui.invCharacterFilterValues end,
		function(selection) ui.invCharacterFilterValues = selection end)
	local chain = { panel.refreshButton, panel.columnsDropdown, panel.rangeDropdown, ui.invTypeDropdown, ui.invRoleDropdown }
	if self.IS_RETAIL then
		ui.invExpansionDropdown = createFilterDropdown(pe, panel.toolbar, 124, "All expansions",
			function() return pe:GetExpansionFilterOptions() end,
			function() return ui.invExpansionFilterValues end,
			function(selection)
				ui.invExpansionFilterValues = selection
				pe:SetSetting("inventory.selectedExpansions", selection)
			end)
		chain[#chain + 1] = ui.invExpansionDropdown
	end
	chain[#chain + 1] = ui.invCharacterDropdown
	self:ChainLeft(chain, 8)
	ui.invSearchBox = self:CreateSearchBox(panel.toolbar, "Search name, ID or type", function()
		ProfessionExporter:RefreshInventoryTab()
	end)
	ui.invSearchBox:SetPoint("LEFT", panel.toolbar, "LEFT", 6, 0)
	ui.invSearchBox:SetPoint("RIGHT", ui.invCharacterDropdown, "LEFT", -14, 0)

	-- Row 2: quality, where stored, has a price, profitable only, reset.
	local saved = self:GetSetting("inventory.extraFilters", {}) or {}
	ui.invQualityFilterValues = ui.invQualityFilterValues or saved.qualities or {}
	ui.invLocationFilterValues = ui.invLocationFilterValues or saved.locations or {}
	if ui.invHasPriceOnly == nil then
		ui.invHasPriceOnly = saved.hasPrice == true
	end
	if ui.invProfitableOnly == nil then
		ui.invProfitableOnly = saved.profitable == true
	end
	local function saveAndRefresh()
		pe:SetSetting("inventory.extraFilters", {
			qualities = ui.invQualityFilterValues,
			locations = ui.invLocationFilterValues,
			hasPrice = ui.invHasPriceOnly,
			profitable = ui.invProfitableOnly,
		})
		pe:RefreshInventoryTab()
	end
	panel.filterRow = CreateFrame("Frame", nil, panel)
	panel.filterRow:SetPoint("TOPLEFT", panel.toolbar, "BOTTOMLEFT", 0, -8)
	panel.filterRow:SetPoint("TOPRIGHT", panel.toolbar, "BOTTOMRIGHT", 0, -8)
	panel.filterRow:SetHeight(26)
	ui.invQualityDropdown = self:CreateMultiSelectDropdown(panel.filterRow, {
		width = 128, allLabel = "Any quality",
		getOptions = function() return pe:GetQualityFilterOptions() end,
		getSelection = function() return ui.invQualityFilterValues end,
		setSelection = function(selection) ui.invQualityFilterValues = selection end,
		onChanged = saveAndRefresh,
	})
	ui.invQualityDropdown:SetPoint("LEFT")
	ui.invLocationDropdown = self:CreateMultiSelectDropdown(panel.filterRow, {
		width = 136, allLabel = "Bags and bank",
		getOptions = function()
			local options = { { value = "bags", label = "In bags" }, { value = "bank", label = "In the bank" } }
			if pe.IS_RETAIL then
				options[#options + 1] = { value = "warband", label = "In the warband bank" }
			end
			return options
		end,
		getSelection = function() return ui.invLocationFilterValues end,
		setSelection = function(selection) ui.invLocationFilterValues = selection end,
		onChanged = saveAndRefresh,
	})
	panel.hasPrice = self:CreateCheckbox(panel.filterRow, "Has a price", function(checked)
		ui.invHasPriceOnly = checked
		saveAndRefresh()
	end)
	panel.profitable = self:CreateCheckbox(panel.filterRow, "Profitable only", function(checked)
		ui.invProfitableOnly = checked
		saveAndRefresh()
	end)
	panel.resetFilters = self:CreateButton(panel.filterRow, "Reset filters", function()
		ui.invCharacterFilterValues, ui.invRoleFilterValues, ui.invTypeFilterValues = {}, {}, {}
		ui.invExpansionFilterValues, ui.invQualityFilterValues, ui.invLocationFilterValues = {}, {}, {}
		ui.invHasPriceOnly, ui.invProfitableOnly = false, false
		ui.invSearchBox:SetText("")
		ui.invSearchBox:UpdatePlaceholder()
		pe:SetSetting("inventory.selectedExpansions", {})
		saveAndRefresh()
	end, { small = true })
	self:ChainRight({ ui.invQualityDropdown, ui.invLocationDropdown, panel.hasPrice, panel.profitable, panel.resetFilters }, 12)

	panel.detailPane = self:CreateItemDetailPane(panel, {
		metricSettingKey = "inventory.detailsGraphMetric",
		onClose = function()
			ui.invSelectedItemID = nil
			ui.inventoryTable:SetSelectedRow(nil)
			ProfessionExporter:LayoutInventoryPanel(panel)
		end,
	})
	panel.detailPane:SetPoint("TOPRIGHT", panel.filterRow, "BOTTOMRIGHT", 0, -GAP)
	panel.detailPane:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)

	ui.inventoryTable = self:CreateReusableTable(panel, {
		footer = true,
		emptyTitle = "No items",
		emptyHint = "Press Refresh to read bags and bank, or change the filters.",
		isRowSelected = function(rowData)
			return rowData and ProfessionExporter.ui.invSelectedItemID ~= nil and tonumber(rowData.itemID) == ProfessionExporter.ui.invSelectedItemID
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
		onColumnReordered = function(_, _, columns)
			ProfessionExporter:SaveInventoryColumnOrder(columns)
		end,
		onRowEnter = function(rowFrame, rowData)
			ProfessionExporter:HandleInventoryRowEnter(rowFrame, rowData)
		end,
		onRowLeave = function()
			GameTooltip:Hide()
		end,
		onRowClick = function(_, rowData, _, tableWidget)
			if ProfessionExporter:HandleItemRowModifiedClick(rowData and rowData.itemID) then
				return
			end
			ProfessionExporter:OpenItemDetails(rowData and rowData.itemID, {
				selectedCharacters = ui.invCharacterFilterValues,
				rangeKey = ProfessionExporter:GetInventoryMetricRange(),
			})
			tableWidget:SetSelectedRow(rowData)
		end,
	})
	panel.inventoryTable = ui.inventoryTable
	ui.inventoryTable:SetColumns(self:BuildInventoryTableColumns())

	panel:SetScript("OnSizeChanged", function()
		ProfessionExporter:LayoutInventoryPanel(panel)
	end)
	self:LayoutInventoryPanel(panel)
	self:RenderInventoryDetails(ui.invSelectedItemID)
end

function ProfessionExporter:RefreshInventoryTab()
	self:InitDB()
	local ui = self.ui
	if not ui or not ui.inventoryPanel or ui.activeMainTab ~= "inventory" then
		return
	end

	local db = self.db
	local metricRange = self:GetInventoryMetricRange()
	local characterOptions = self:GetInventoryCharacterFilterOptions()
	ui.invCharacterFilterValues = self:NormalizeFilterSelection(ui.invCharacterFilterValues, characterOptions)
	local characterColumnLabel = self:GetFilterSelectionSummary(characterOptions, ui.invCharacterFilterValues, "All characters")
	local mergedRoleMap, perCharRoleMaps = self:BuildMergedItemRoleMapForSelection(db, ui.invCharacterFilterValues)
	local rows = self:BuildInventoryRowsAggregatedByItem(db, ui.invCharacterFilterValues, characterColumnLabel, mergedRoleMap)
	local allCharsLabel = self:GetFilterSelectionSummary(characterOptions, {}, "All characters")
	ui.invTypeFilterSeedRows = self:BuildInventoryRowsAggregatedByItem(db, {}, allCharsLabel)

	local rankIndex = self:BuildOutputItemQualityRankIndex(ui.invCharacterFilterValues)
	ui.invQualityRankIndex = rankIndex
	local historyStatsMemo = {}

	for _, row in ipairs(rows) do
		self:EnrichInventoryRowAnalytics(row, nil, mergedRoleMap, ui.invCharacterFilterValues, metricRange, rankIndex, historyStatsMemo, perCharRoleMaps)
	end
	local roleOptions = self:GetInventoryRoleFilterOptions()
	local typeOptions = self:GetInventoryTypeFilterOptions(ui.invTypeFilterSeedRows or {})
	ui.invRoleFilterValues = self:NormalizeFilterSelection(ui.invRoleFilterValues, roleOptions)
	ui.invTypeFilterValues = self:NormalizeFilterSelection(ui.invTypeFilterValues, typeOptions)
	local expOpts = self:GetExpansionFilterOptions()
	ui.invExpansionFilterValues = self:NormalizeFilterSelection(ui.invExpansionFilterValues or {}, expOpts)
	if ui.invExpansionDropdown then
		ui.invExpansionDropdown:SetOptions(expOpts)
		ui.invExpansionDropdown:RefreshText()
	end
	ui.invCharacterDropdown:SetOptions(characterOptions)
	ui.invCharacterDropdown:RefreshText()
	ui.invRoleDropdown:SetOptions(roleOptions)
	ui.invRoleDropdown:RefreshText()
	ui.invTypeDropdown:SetOptions(typeOptions)
	ui.invTypeDropdown:RefreshText()

	rows = self:FilterInventoryRows(rows, self:BuildInventoryFilterState())
	ui.invWorkingRows = rows

	local totalQty = 0
	local totalValue = 0
	local totalCraft = 0
	for _, row in ipairs(rows) do
		totalQty = totalQty + (row.total or 0)
		if row.currentAhCopper then
			totalValue = totalValue + (row.currentAhCopper * (row.total or 0))
		end
		if row.avgCraftCost then
			totalCraft = totalCraft + (row.avgCraftCost * (row.total or 0))
		end
	end

	local storedCharacterCount = math.max(0, #characterOptions - 1)
	local selectedCharacterCount = self:CountFilterSelection(ui.invCharacterFilterValues)
	local characterSummary = selectedCharacterCount == 0
		and string.format("all %d characters", storedCharacterCount)
		or string.format("%d of %d characters", selectedCharacterCount, storedCharacterCount)

	ui.inventoryPanel.rangeDropdown:RefreshText()
	ui.invQualityDropdown:RefreshText()
	ui.invLocationDropdown:RefreshText()
	ui.inventoryPanel.hasPrice.check:SetChecked(ui.invHasPriceOnly == true)
	ui.inventoryPanel.profitable.check:SetChecked(ui.invProfitableOnly == true)
	ui.inventoryPanel.columnsDropdown:RefreshText()

	ui.inventoryTable:SetColumns(self:BuildInventoryTableColumns())
	ui.inventoryTable:SetContext({
		accountMode = true,
	})
	ui.inventoryTable:SetRows(rows)
	ui.inventoryTable:Refresh()
	ui.inventoryTable:SetFooterText(
		string.format("%s items · %s in total · %s", self:FormatNumberGrouped(#rows), self:FormatNumberGrouped(totalQty), characterSummary),
		string.format("Auction value %s · Craft value %s", self:FormatCopperShort(totalValue), self:FormatCopperShort(totalCraft)))

	self:LayoutInventoryPanel(ui.inventoryPanel)
	self:RenderInventoryDetails(ui.invSelectedItemID)
end

function ProfessionExporter:RefreshInventoryTabIfVisible()
	local ui = self.ui
	if ui and ui.activeMainTab == "inventory" then
		self:RefreshInventoryTab()
	end
end

