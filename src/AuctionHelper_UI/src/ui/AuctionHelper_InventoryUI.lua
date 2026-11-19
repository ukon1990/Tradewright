local addonName, ProfessionExporter = ...

local INV_ROW_H = 20
local INV_MAX_ROWS = 550
local ACCT_KEY = ProfessionExporter.DASHBOARD_ACCOUNT_KEY or "__PE_ACCOUNT__"
local DEFAULT_ITEM_ICON = 134400
local RANK_BADGE_PX = 16
local RANK_ICON_GAP = 4

local COL = {
	name = 228,
	qty = 50,
	loc = 84,
	currentAh = 76,
	lastSeen = 76,
	avgSeen = 76,
	avgCraft = 82,
	lastCraft = 82,
	profitUnit = 82,
	profitStack = 82,
	saleRate = 54,
	seenAt = 102,
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

local function formatCopperFull(pe, copper)
	return pe:FormatCopperFull(copper)
end

local function formatTimestamp(ts)
	if not ts or ts <= 0 then
		return "-"
	end
	return date("%Y-%m-%d %H:%M", ts)
end

local function applyRankBadge(texture, text, rankIndex)
	if not texture or not text or not rankIndex or rankIndex <= 0 then
		if texture then
			texture:Hide()
		end
		if text then
			text:Hide()
		end
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

local function layoutInventoryNameCellIcons(cell)
	if not cell or not cell.root or not cell.rankIcon or not cell.icon or not cell.text then
		return
	end
	local root, rankIcon, icon, text = cell.root, cell.rankIcon, cell.icon, cell.text
	local topPad = (INV_ROW_H - RANK_BADGE_PX) / 2
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

function ProfessionExporter:BuildInventoryFilterState()
	local ui = self.ui or {}
	return {
		text = trim(ui.invSearchBox and ui.invSearchBox:GetText() or ""),
		characters = ui.invCharacterFilterValues or {},
		role = ui.invRoleFilterValues or {},
		itemType = ui.invTypeFilterValues or {},
		expansions = ui.invExpansionFilterValues or {},
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
		if matchesText and matchesCharacter and matchesRole and matchesType and matchesExpansion then
			out[#out + 1] = row
		end
	end

	return out
end

function ProfessionExporter:ScheduleInventorySearchRefresh()
	local ui = self.ui
	if not ui then
		return
	end
	if ui.invSearchTimer then
		ui.invSearchTimer:Cancel()
	end
	ui.invSearchTimer = C_Timer.NewTimer(0.2, function()
		ui.invSearchTimer = nil
		if ui.activeMainTab == "inventory" then
			self:RefreshInventoryTab()
		end
	end)
end

function ProfessionExporter:CreateInventoryNameCell(rowFrame)
	local root = CreateFrame("Frame", nil, rowFrame)
	root:SetHeight(INV_ROW_H)

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
	layoutInventoryNameCellIcons(cell)
	return cell
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
		{
			id = "name",
			label = "Item",
			width = COL.name,
			minWidth = 120,
			flex = 3,
			sortable = true,
			defaultSort = "asc",
			lockVisible = true,
			defaultVisible = true,
			sortValue = function(row)
				return row.name or ""
			end,
			createCell = function(rowFrame)
				return ProfessionExporter:CreateInventoryNameCell(rowFrame)
			end,
			updateCell = function(cell, row)
				cell.icon:SetTexture(row.icon or DEFAULT_ITEM_ICON)
				applyRankBadge(cell.rankIcon, cell.rankText, row.rankIndex)
				layoutInventoryNameCellIcons(cell)
				cell.text:SetText(ProfessionExporter:GetItemDisplayName(row.itemID))
			end,
		},
		{
			id = "qty",
			label = "Qty",
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
			id = "loc",
			label = "B / Bk / W",
			width = COL.loc,
			minWidth = 56,
			flex = 0,
			sortable = true,
			defaultSort = "desc",
			defaultVisible = true,
			compare = function(left, right)
				return compareTriple(left.bags, left.bank, left.warband, right.bags, right.bank, right.warband)
			end,
			getText = function(row)
				return string.format("%s/%s/%s", ProfessionExporter:FormatNumberGrouped(row.bags or 0), ProfessionExporter:FormatNumberGrouped(row.bank or 0), ProfessionExporter:FormatNumberGrouped(row.warband or 0))
			end,
		},
		{
			id = "currentAh",
			label = "Current AH",
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
			width = COL.lastSeen,
			minWidth = 56,
			flex = 0,
			sortable = true,
			defaultSort = "desc",
			defaultVisible = true,
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
			width = COL.avgSeen,
			minWidth = 56,
			flex = 0,
			sortable = true,
			defaultSort = "desc",
			defaultVisible = true,
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
			label = "Profit / u",
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
			label = "Profit row",
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
			label = "Seen at",
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
				return formatTimestamp(row.currentAhAt)
			end,
		},
	}
end

function ProfessionExporter:GetInventoryColumnOrder()
	local savedOrder = self:GetSetting("inventory.columnOrder", {})
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

function ProfessionExporter:HandleInventoryRowEnter(_, rowData)
	local itemID = rowData and rowData.itemID
	if not itemID then
		return
	end

	GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
	if GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(itemID)
	else
		GameTooltip:SetText("#" .. tostring(itemID))
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(
		string.format("Bags %d  Bank %d  Warband %d", rowData.bags or 0, rowData.bank or 0, rowData.warband or 0),
		1,
		1,
		1
	)
	if rowData.rankIndex then
		GameTooltip:AddLine("Rank: " .. tostring(rowData.rankIndex), 1, 0.92, 0.65)
	end
	GameTooltip:AddLine("Current AH: " .. formatCopperFull(self, rowData.currentAhCopper), 0.8, 0.9, 1)
	GameTooltip:AddLine("Average craft: " .. formatCopperFull(self, rowData.avgCraftCost), 0.8, 0.9, 1)
	GameTooltip:AddLine("Observed at: " .. formatTimestamp(rowData.currentAhAt), 0.8, 0.85, 0.9)
	GameTooltip:AddLine("Click to open item details.", 0.75, 0.82, 0.9)
	GameTooltip:Show()
end

function ProfessionExporter:LayoutInventoryPanel(panel)
	if not panel then
		return
	end
	local width = math.max(840, panel:GetWidth() - 20)
	local detailsOpen = self:GetSetting("inventory.detailsOpen", true)
	local c = self:GetDetailPaneLayoutConstants()
	local savedDetailW = tonumber(self:GetSetting("inventory.detailsWidth", 340)) or 340
	local detailsWidth = detailsOpen and self:ClampDetailsWidthForPanel(panel, savedDetailW) or 0
	if detailsOpen and math.abs(savedDetailW - detailsWidth) >= 1 then
		self:SetSetting("inventory.detailsWidth", math.floor(detailsWidth + 0.5))
	end
	local gap = c.gapAfterSplitter
	local splitterW = c.splitterWidth

	panel.headerCard:ClearAllPoints()
	panel.headerCard:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
	panel.headerCard:SetSize(width, 102)
	panel.headerTitle:SetWidth(width - 300)
	panel.headerSubtitle:SetWidth(width - 300)
	panel.headerSummary1:SetWidth(width - 300)
	panel.headerSummary2:SetWidth(width - 300)
	panel.refreshButton:ClearAllPoints()
	panel.refreshButton:SetPoint("TOPRIGHT", panel.headerCard, "TOPRIGHT", -12, -12)
	panel.rangeDropdown:ClearAllPoints()
	panel.rangeDropdown:SetPoint("TOPRIGHT", panel.refreshButton, "BOTTOMRIGHT", 18, -4)
	panel.columnsDropdown:ClearAllPoints()
	panel.columnsDropdown:SetPoint("RIGHT", panel.rangeDropdown, "LEFT", -8, 0)

	panel.filterCard:ClearAllPoints()
	panel.filterCard:SetPoint("TOPLEFT", panel.headerCard, "BOTTOMLEFT", 0, -10)
	panel.filterCard:SetSize(width, 120)

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
	else
		if panel.detailsSplitter then
			panel.detailsSplitter:Hide()
		end
		panel.detailCard:Hide()
	end

	if panel.inventoryTable and panel.inventoryTable.frame then
		panel.inventoryTable.frame:ClearAllPoints()
		panel.inventoryTable.frame:SetPoint("TOPLEFT", panel.tableCard, "TOPLEFT", 10, -34)
		panel.inventoryTable.frame:SetPoint("BOTTOMRIGHT", panel.tableCard, "BOTTOMRIGHT", -10, 10)
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
		if panel.detailGraphBlock then
			panel.detailGraphBlock:ClearAllPoints()
			panel.detailGraphBlock:SetPoint("TOPLEFT", panel.detailMeta, "BOTTOMLEFT", 0, -8)
			panel.detailScroll:ClearAllPoints()
			panel.detailScroll:SetPoint("TOPLEFT", panel.detailGraphBlock, "BOTTOMLEFT", 0, -8)
		else
			panel.detailScroll:ClearAllPoints()
			panel.detailScroll:SetPoint("TOPLEFT", panel.detailMeta, "BOTTOMLEFT", 0, -10)
		end
		panel.detailScroll:SetPoint("BOTTOMRIGHT", panel.detailCard, "BOTTOMRIGHT", -28, 10)
	end

	if panel.inventoryTable and panel.inventoryTable.Refresh then
		panel.inventoryTable:Refresh()
	end
end

function ProfessionExporter:RenderInventoryDetails(itemID)
	local ui = self.ui
	local panel = ui and ui.inventoryPanel or nil
	if not (ui and panel and panel.detailCard) then
		return
	end
	if not itemID then
		panel.detailTitle:SetText("Item details")
		panel.detailMeta:SetText("Select an item row to inspect price, crafting history, and recipe relationships.")
		panel.detailIcon:SetTexture(DEFAULT_ITEM_ICON)
		applyRankBadge(panel.detailRankIcon, panel.detailRankText, nil)
		panel.detailIcon:ClearAllPoints()
		panel.detailIcon:SetPoint("TOPLEFT", panel.detailHeader, "TOPLEFT", 0, 0)
		panel.detailBody:SetText("No item selected.")
		if panel.detailGraphBlock then
			panel.detailGraphBlock:Hide()
		end
		self:LayoutDetailPaneHeaderRow(panel)
		return
	end
	if panel.detailGraphBlock then
		panel.detailGraphBlock:Show()
	end

	local detail = self:BuildItemDetailSnapshot(itemID, {
		selectedCharacters = ui.invCharacterFilterValues,
		rangeKey = self:GetInventoryMetricRange(),
		rankIndex = ui.invQualityRankIndex,
	})
	panel.detailIcon:SetTexture(detail.icon or DEFAULT_ITEM_ICON)
	applyRankBadge(panel.detailRankIcon, panel.detailRankText, detail.rankIndex)
	local iconX = 0
	if detail.rankIndex and tonumber(detail.rankIndex) > 0 then
		iconX = RANK_BADGE_PX + RANK_ICON_GAP
	end
	panel.detailIcon:ClearAllPoints()
	panel.detailIcon:SetPoint("TOPLEFT", panel.detailHeader, "TOPLEFT", iconX, 0)
	panel.detailTitle:SetText(self:GetItemDisplayName(itemID))
	panel.detailMeta:SetText(string.format(
		"Range: %s  |  Current AH: %s  |  Last seen: %s",
		tostring(detail.rangeKey or "all"),
		formatCopperFull(self, detail.economy.currentMarket),
		formatTimestamp(detail.economy.currentMarketAt)
	))

	if panel.invDetailGraph then
		local produced = detail.crafting and detail.crafting.producedBy
		local canCraft = type(produced) == "table" and #produced > 0
		local matEst = canCraft and self:EstimateBestMatCostPerUnitAmongSelection(self.db, itemID, ui.invCharacterFilterValues, nil) or nil
		self:ApplyItemDetailTimeSeriesGraph(itemID, panel.invDetailGraph, {
			metricSettingKey = "inventory.detailsGraphMetric",
			rangeKey = detail.rangeKey or self:GetInventoryMetricRange(),
			quantityCharacterFilter = ui.invCharacterFilterValues,
			secondaryCraftingOverlay = canCraft and matEst ~= nil,
			currentCraftCostCopper = matEst,
			quantityOverlay = self:GetSetting("inventory.detailsGraphShowQuantity", true) ~= false,
		})
	end

	local lines = self:BuildItemDetailScrollBodyLines(detail)
	panel.detailBody:SetText(table.concat(lines, "\n"))
	panel.detailContent:SetHeight(math.max(220, panel.detailBody:GetStringHeight() + 20))
	self:LayoutDetailPaneHeaderRow(panel)
end

function ProfessionExporter:EnsureInventoryPanel(mainFrame)
	local ui = self.ui
	if ui.inventoryPanel then
		return
	end

	local panel = CreateFrame("Frame", nil, mainFrame)
	panel:SetAllPoints()
	ui.inventoryPanel = panel

	panel.headerCard = self:CreateCard(panel, 860, 102, "surface2")
	panel.headerTitle = panel.headerCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	panel.headerTitle:SetPoint("TOPLEFT", 12, -12)
	panel.headerTitle:SetJustifyH("LEFT")
	panel.headerTitle:SetText("Inventory workspace")

	panel.headerSubtitle = self:CreateMutedText(panel.headerCard, 640)
	panel.headerSubtitle:SetPoint("TOPLEFT", panel.headerTitle, "BOTTOMLEFT", 0, -6)
	panel.headerSubtitle:SetText("Tracked inventory with configurable columns, observed AH/crafting history, and reusable item details.")

	panel.headerSummary1 = self:CreateMutedText(panel.headerCard, 640)
	panel.headerSummary1:SetPoint("TOPLEFT", panel.headerSubtitle, "BOTTOMLEFT", 0, -8)
	panel.headerSummary2 = self:CreateMutedText(panel.headerCard, 640)
	panel.headerSummary2:SetPoint("TOPLEFT", panel.headerSummary1, "BOTTOMLEFT", 0, -4)

	panel.refreshButton = CreateFrame("Button", nil, panel.headerCard, "UIPanelButtonTemplate")
	panel.refreshButton:SetSize(114, 24)
	panel.refreshButton:SetText("Refresh inventory")
	panel.refreshButton:SetScript("OnClick", function()
		ProfessionExporter:DashboardRefreshInventory()
	end)

	panel.rangeDropdown = self:CreateSingleSelectDropdown(panel.headerCard, {
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
			ProfessionExporter:RefreshInventoryTab()
		end,
	})

	panel.columnsDropdown = self:CreateMenuDropdown(panel.headerCard, {
		label = "Columns",
		width = 132,
		getText = function()
			local visible = 0
			local total = 0
			for _, column in ipairs(ProfessionExporter:GetInventoryColumnOrder()) do
				if not column.lockVisible then
					total = total + 1
					if ProfessionExporter:IsInventoryColumnVisible(column.id) then
						visible = visible + 1
					end
				end
			end
			return string.format("Columns (%d/%d)", visible, total)
		end,
		initializeMenu = function(level)
			if level ~= 1 then
				return
			end
			for _, column in ipairs(ProfessionExporter:GetInventoryColumnOrder()) do
				if not column.lockVisible then
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
			local spacer = UIDropDownMenu_CreateInfo()
			spacer.disabled = true
			spacer.notCheckable = true
			spacer.text = " "
			UIDropDownMenu_AddButton(spacer, level)
			local reset = UIDropDownMenu_CreateInfo()
			reset.text = "Reset default layout"
			reset.notCheckable = true
			reset.func = function()
				ProfessionExporter:SetSetting("inventory.columnOrder", {})
				ProfessionExporter:SetSetting("inventory.hiddenColumns", {})
				ProfessionExporter:RefreshInventoryTab()
			end
			UIDropDownMenu_AddButton(reset, level)
		end,
	})

	panel.filterCard = self:CreateCard(panel, 860, 120, "surface2")
	local searchLabel = panel.filterCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	searchLabel:SetPoint("TOPLEFT", 12, -10)
	searchLabel:SetText("Search")

	ui.invSearchBox = CreateFrame("EditBox", addonName .. "InvSearch", panel.filterCard, "InputBoxTemplate")
	ui.invSearchBox:SetSize(220, 22)
	ui.invSearchBox:SetPoint("TOPLEFT", searchLabel, "BOTTOMLEFT", -6, -6)
	ui.invSearchBox:SetAutoFocus(false)
	ui.invSearchBox:SetMaxLetters(64)
	ui.invSearchBox:SetScript("OnEnterPressed", function(box)
		box:ClearFocus()
	end)
	ui.invSearchBox:SetScript("OnTextChanged", function()
		ProfessionExporter:ScheduleInventorySearchRefresh()
	end)

	ui.invRoleFilterValues = ui.invRoleFilterValues or self:UpgradeLegacyInventoryFilterSelection(ui.invRoleFilterValue)
	ui.invTypeFilterValues = ui.invTypeFilterValues or self:UpgradeLegacyInventoryFilterSelection(ui.invTypeFilterValue)
	ui.invCharacterFilterValues = ui.invCharacterFilterValues or {}
	ui.invRoleFilterValue = nil
	ui.invTypeFilterValue = nil

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
	ui.invExpansionFilterValues = copyBoolMap(self:GetSetting("inventory.selectedExpansions", {}))

	ui.invCharacterDropdown = self:CreateMultiSelectDropdown(panel.filterCard, {
		label = "Characters",
		width = 220,
		allLabel = "All characters",
		getOptions = function()
			return ProfessionExporter:GetInventoryCharacterFilterOptions()
		end,
		getSelection = function()
			return ui.invCharacterFilterValues
		end,
		setSelection = function(selection)
			ui.invCharacterFilterValues = selection
		end,
		onChanged = function()
			ProfessionExporter:RefreshInventoryTab()
		end,
	})
	ui.invCharacterDropdown:SetPoint("TOPLEFT", ui.invSearchBox, "TOPRIGHT", 16, 12)

	ui.invRoleDropdown = self:CreateMultiSelectDropdown(panel.filterCard, {
		label = "Role",
		width = 180,
		allLabel = "All roles",
		getOptions = function()
			return ProfessionExporter:GetInventoryRoleFilterOptions()
		end,
		getSelection = function()
			return ui.invRoleFilterValues
		end,
		setSelection = function(selection)
			ui.invRoleFilterValues = selection
		end,
		onChanged = function()
			ProfessionExporter:RefreshInventoryTab()
		end,
	})
	ui.invRoleDropdown:SetPoint("TOPLEFT", ui.invCharacterDropdown, "TOPRIGHT", 8, 0)

	ui.invTypeDropdown = self:CreateMultiSelectDropdown(panel.filterCard, {
		label = "Item type",
		width = 180,
		allLabel = "All item types",
		getOptions = function()
			return ProfessionExporter:GetInventoryTypeFilterOptions(ui.invTypeFilterSeedRows or {})
		end,
		getSelection = function()
			return ui.invTypeFilterValues
		end,
		setSelection = function(selection)
			ui.invTypeFilterValues = selection
		end,
		onChanged = function()
			ProfessionExporter:RefreshInventoryTab()
		end,
	})
	ui.invTypeDropdown:SetPoint("TOPLEFT", ui.invRoleDropdown, "TOPRIGHT", 8, 0)

	ui.invExpansionDropdown = self:CreateMultiSelectDropdown(panel.filterCard, {
		label = "Expansion",
		width = 180,
		allLabel = "All expansions",
		getOptions = function()
			return ProfessionExporter:GetExpansionFilterOptions()
		end,
		getSelection = function()
			return ui.invExpansionFilterValues
		end,
		setSelection = function(selection)
			ui.invExpansionFilterValues = selection
			ProfessionExporter:SetSetting("inventory.selectedExpansions", selection)
		end,
		onChanged = function()
			ProfessionExporter:RefreshInventoryTab()
		end,
	})
	ui.invExpansionDropdown:SetPoint("TOPLEFT", ui.invSearchBox, "BOTTOMLEFT", -6, -10)

	ui.invClearFiltersBtn = CreateFrame("Button", nil, panel.filterCard, "UIPanelButtonTemplate")
	ui.invClearFiltersBtn:SetSize(110, 22)
	ui.invClearFiltersBtn:SetPoint("TOPLEFT", ui.invExpansionDropdown, "TOPRIGHT", 12, 24)
	ui.invClearFiltersBtn:SetText("Reset filters")
	ui.invClearFiltersBtn:SetScript("OnClick", function()
		ui.invCharacterFilterValues = {}
		ui.invRoleFilterValues = {}
		ui.invTypeFilterValues = {}
		ui.invExpansionFilterValues = {}
		ui.invSearchBox:SetText("")
		ProfessionExporter:SetSetting("inventory.selectedExpansions", {})
		ProfessionExporter:RefreshInventoryTab()
	end)

	panel.tableCard = self:CreateCard(panel, 500, 360, "surface2")
	panel.tableTitle = panel.tableCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	panel.tableTitle:SetPoint("TOPLEFT", 10, -10)
	panel.tableTitle:SetText("Items")

	panel.detailsSplitter = self:CreateDetailPaneSplitter(panel, {
		settingsKey = "inventory.detailsWidth",
		onLayout = function()
			ProfessionExporter:LayoutInventoryPanel(panel)
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
	panel.detailTitle = panel.detailHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	panel.detailTitle:SetPoint("TOPLEFT", panel.detailIcon, "TOPRIGHT", 6, -3)
	panel.detailTitle:SetJustifyH("LEFT")
	panel.detailTitle:SetWordWrap(true)
	panel.detailRankIcon = panel.detailHeader:CreateTexture(nil, "OVERLAY")
	panel.detailRankIcon:SetSize(RANK_BADGE_PX, RANK_BADGE_PX)
	panel.detailRankIcon:SetPoint("TOPRIGHT", panel.detailIcon, "TOPLEFT", -RANK_ICON_GAP, 8)
	panel.detailRankIcon:Hide()
	panel.detailRankText = panel.detailHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	panel.detailRankText:SetPoint("CENTER", panel.detailRankIcon, "CENTER", 0, 0)
	panel.detailRankText:SetTextColor(1, 1, 1)
	panel.detailRankText:Hide()
	panel.detailCloseButton = CreateFrame("Button", nil, panel.detailCard, "UIPanelCloseButton")
	panel.detailCloseButton:SetPoint("TOPRIGHT", 2, 2)
	panel.detailCloseButton:SetScript("OnClick", function()
		ProfessionExporter:SetSetting("inventory.detailsOpen", false)
		ProfessionExporter:LayoutInventoryPanel(panel)
	end)
	panel.detailMeta = self:CreateMutedText(panel.detailCard, 300)
	panel.detailMeta:SetPoint("TOPLEFT", panel.detailHeader, "BOTTOMLEFT", 0, -6)

	panel.detailGraphBlock = CreateFrame("Frame", nil, panel.detailCard)
	panel.detailGraphBlock:SetHeight(188)
	panel.invDetailMetricDropdown = self:CreateSingleSelectDropdown(panel.detailGraphBlock, {
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
			return ProfessionExporter:GetSetting("inventory.detailsGraphMetric", "market")
		end,
		setValue = function(value)
			ProfessionExporter:SetSetting("inventory.detailsGraphMetric", value)
		end,
		onChanged = function()
			ProfessionExporter:RenderInventoryDetails(ProfessionExporter.ui.invSelectedItemID)
		end,
	})
	panel.invDetailMetricDropdown:SetPoint("TOPLEFT", panel.detailGraphBlock, "TOPLEFT", 0, 0)
	panel.invDetailGraph = self:CreateTimeSeriesGraph(panel.detailGraphBlock, {
		showTitle = false,
		plotHeight = 118,
		emptyText = "No observations in this range.",
	})
	panel.invDetailGraph:SetPoint("TOPLEFT", panel.invDetailMetricDropdown, "BOTTOMLEFT", -4, -2)
	panel.invDetailGraph:SetPoint("TOPRIGHT", panel.detailGraphBlock, "TOPRIGHT", 0, -54)

	panel.detailScroll = CreateFrame("ScrollFrame", addonName .. "InventoryDetailsScroll", panel.detailCard, "UIPanelScrollFrameTemplate")
	panel.detailContent = CreateFrame("Frame", nil, panel.detailScroll)
	panel.detailContent:SetWidth(280)
	panel.detailContent:SetHeight(220)
	panel.detailScroll:SetScrollChild(panel.detailContent)
	panel.detailBody = self:CreateMutedText(panel.detailContent, 280)
	panel.detailBody:SetPoint("TOPLEFT", 2, -4)

	ui.inventoryTable = self:CreateReusableTable(panel.tableCard, {
		rowHeight = INV_ROW_H,
		maxRows = INV_MAX_ROWS,
		viewportVirtualize = true,
		virtualOverscan = 8,
		autoFitToScroll = true,
		sortKey = ui.invSortKey or "qty",
		sortAsc = ui.invSortAsc ~= false,
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
		onRowClick = function(_, rowData)
			ProfessionExporter:OpenItemDetails(rowData and rowData.itemID, {
				selectedCharacters = ui.invCharacterFilterValues,
				rangeKey = ProfessionExporter:GetInventoryMetricRange(),
			})
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

	ui.inventoryPanel.headerSummary1:SetText(string.format(
		"Account inventory  |  Rows: %d  |  Total quantity: %d  |  Characters: %s",
		#rows,
		totalQty,
		characterSummary
	))
	ui.inventoryPanel.headerSummary2:SetText(string.format(
		"Observed AH total: %s  |  Average craft total: %s  |  Range: %s  |  Drag column headers to reorder.",
		formatCopperFull(self, totalValue),
		formatCopperFull(self, totalCraft),
		tostring(metricRange)
	))
	ui.inventoryPanel.rangeDropdown:RefreshText()
	ui.inventoryPanel.columnsDropdown:RefreshText()

	ui.inventoryTable:SetColumns(self:BuildInventoryTableColumns())
	ui.inventoryTable:SetContext({
		accountMode = true,
	})
	ui.inventoryTable:SetRows(rows)

	self:LayoutInventoryPanel(ui.inventoryPanel)
	self:RenderInventoryDetails(ui.invSelectedItemID)
end

function ProfessionExporter:RefreshInventoryTabIfVisible()
	local ui = self.ui
	if ui and ui.activeMainTab == "inventory" then
		self:RefreshInventoryTab()
	end
end

