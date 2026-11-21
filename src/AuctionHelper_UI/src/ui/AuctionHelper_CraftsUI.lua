local _, AuctionHelper = ...

local MAX_ROWS = 450

local function trim(s)
	if not s then
		return ""
	end
	return (string.gsub(tostring(s), "^%s*(.-)%s*$", "%1"))
end

local function isPlaceholderItemLabel(s)
    local t = trim(s)
    if t == "" or t == "?" then
        return true
    end
    return string.match(t, "^#%d+$") ~= nil
end

local GAP = 12
local PAD = 10
local DETAIL_WIDTH = 300
local TALL_ROW = 36

local function rankMarkup(rankIndex)
	return AuctionHelper:GetRankMarkup(rankIndex)
end

local function colorize(pe, colorKey, text)
	local c = pe:GetTheme()[colorKey]
	return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, text)
end

local function crafterName(pe, characterKey)
	local data = characterKey and pe.db.characters and pe.db.characters[characterKey]
	local meta = data and data.meta
	return meta and meta.name or tostring(characterKey or "?")
end

-- Second line of a craft row: profession, best crafter, queued count, and a warning when it applies.
local function craftRowDetail(pe, row)
	local parts = { row.professionName or "?" }
	if row.bestCharacterKey then
		parts[#parts + 1] = crafterName(pe, row.bestCharacterKey)
	end
	if pe.IS_RETAIL and row.expansionTag and row.expansionTag ~= "" then
		parts[#parts + 1] = row.expansionTag
	end
	local queued = pe:GetCraftQueueQuantityForOpportunityRow(row)
	if queued > 0 then
		parts[#parts + 1] = colorize(pe, "gold", queued .. " queued")
	end
	if not row.matCost then
		parts[#parts + 1] = colorize(pe, "warning", "no material price")
	elseif row.qualityReachable == false then
		parts[#parts + 1] = colorize(pe, "warning", (row.concentrationNeeded or row.concentrationCost) and "needs concentration" or "rank out of reach")
	end
	return table.concat(parts, " · ")
end

local function craftRowName(pe, row)
	local item = trim(pe:GetItemDisplayName(row and row.outputItemID))
	if isPlaceholderItemLabel(item) then
		item = trim(row and row.recipeName or "") ~= "" and row.recipeName or "Craft"
	end
	return item .. rankMarkup(row and row.qualityIndex)
end

local function bestEvaluation(row)
	return row and row.bestCharacterKey and row.perChar and row.perChar[row.bestCharacterKey] or nil
end

function AuctionHelper:GetCraftsColumnDefinitions()
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
			getName = function(row) return craftRowName(pe, row) end,
			getDetail = function(row) return craftRowDetail(pe, row) end,
			sortValue = function(row) return row.outputName or "" end,
		}),
		money("sale", "Sale, net", "saleNet", 80),
		money("mats", "Materials", "matCost", 80),
		money("profit", "Profit", "profit", 86, true),
		{
			id = "roi", label = "ROI", justifyH = "RIGHT", width = 48, sortable = true, defaultSort = "desc", optional = true,
			tooltipTitle = "Return", tooltipText = "Profit divided by material cost.",
			sortValue = function(row) return row.roi or -1e15 end,
			getText = function(row) return row.roi and string.format("%.0f%%", row.roi) or "-" end,
		},
		{
			id = "coverage", label = "Owned", justifyH = "RIGHT", width = 50, sortable = true, defaultSort = "desc", optional = true,
			tooltipTitle = "Materials owned", tooltipText = "Share of the best crafter's materials that your characters already own.",
			sortValue = function(row)
				local ev = bestEvaluation(row)
				return ev and (ev.coverage or 0) or 0
			end,
			getText = function(row)
				local ev = bestEvaluation(row)
				return ev and ev.coverage and string.format("%.0f%%", ev.coverage * 100) or "-"
			end,
		},
	}
end

function AuctionHelper:BuildCraftsTableColumns()
	return self:AddCraftPlanningColumns(self:GetCraftsColumnDefinitions())
end

--- Among opportunities with this output item, prefer the highest profit (stable tie: first in list order).
function AuctionHelper:SelectCraftOpportunityByOutputItemID(itemID)
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

function AuctionHelper:LayoutCraftsPanel(panel)
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

function AuctionHelper:RenderCraftsDetails(row)
	local panel = self.ui and self.ui.craftsPanel
	if not panel then
		return
	end
	local ui = self.ui
	ui.craftsSelectedRowData = row
	if row then
		ui.craftsItemDetailOnlyItemID = nil
	end
	local itemOnlyID = not row and ui.craftsItemDetailOnlyItemID and tonumber(ui.craftsItemDetailOnlyItemID) or nil

	if not row and not itemOnlyID then
		self:LayoutCraftsPanel(panel)
		return
	end
	if not row then
		panel.detailHeader:SetItem(itemOnlyID, self:GetItemDisplayName(itemOnlyID), "Not in the current list. Check the filters.")
		panel.detailHeader.badge:SetBadge(nil)
		panel.detailFacts:SetRows({})
		panel.materialsTable:SetRows({})
		panel.materialsTable:Refresh()
		self:LayoutCraftsPanel(panel)
		return
	end

	local ev = bestEvaluation(row) or {}
	local crafter = row.bestCharacterKey and crafterName(self, row.bestCharacterKey) or "-"
	panel.detailHeader:SetItem(row.outputItemID, craftRowName(self, row), (row.professionName or "?") .. " · best crafter " .. crafter, row.outputIcon)
	if not row.matCost then
		panel.detailHeader.badge:SetBadge("No price", "warning")
	elseif row.canCraftNow then
		panel.detailHeader.badge:SetBadge("Can craft", "success")
	elseif row.qualityReachable == false then
		panel.detailHeader.badge:SetBadge("Out of reach", "warning")
	else
		local missing = 0
		for _, slot in ipairs(ev.reagentPlan or {}) do
			missing = missing + math.max(0, tonumber(slot.purchasedQuantity) or 0)
		end
		panel.detailHeader.badge:SetBadge(missing > 0 and ("Missing " .. missing) or "Missing", "danger")
	end

	local cut = tonumber(self:GetSetting("crafts.ahCutPercent", 5)) or 5
	panel.detailFacts:SetRows({
		{ string.format("Sale after %d%% cut", cut), row.saleNet and self:FormatCopperFull(row.saleNet) or "-" },
		{ "Materials at market price", row.matCost and self:FormatCopperFull(row.matCost) or "-" },
		{ "Profit per craft", self:FormatSignedMoney(row.profit) },
		{ "Return", row.roi and string.format("%.0f%%", row.roi) or "-" },
		{ "Materials you already own", ev.coverage and string.format("%.0f%%", ev.coverage * 100) or "-" },
		{ "Still to buy", row.outOfPocketMatCost and self:FormatCopperFull(row.outOfPocketMatCost) or "-" },
	})

	local materials = {}
	for index, slot in ipairs(ev.reagentPlan or {}) do
		materials[#materials + 1] = {
			_rowIdentity = index,
			itemID = slot.itemID,
			need = tonumber(slot.quantityRequired) or 0,
			have = tonumber(slot.ownedQuantity),
			cost = tonumber(slot.lineCost),
		}
	end
	panel.materialsTable:SetRows(materials)
	panel.materialsTable:Refresh()
	self:LayoutCraftsPanel(panel)
end

local function createSelect(pe, parent, width, options, settingKey, default, onChanged, tooltip)
	return pe:CreateSingleSelectDropdown(parent, {
		width = width,
		getOptions = function() return options end,
		getValue = function() return pe:GetSetting(settingKey, default) end,
		setValue = function(value) pe:SetSetting(settingKey, value) end,
		onChanged = onChanged or function() pe:RefreshCraftsTab() end,
		tooltip = tooltip,
	})
end

local function createFilter(pe, parent, width, allLabel, getOptions, field, settingKey)
	return pe:CreateMultiSelectDropdown(parent, {
		width = width,
		allLabel = allLabel,
		getOptions = getOptions,
		getSelection = function() return pe.ui[field] end,
		setSelection = function(selection)
			pe.ui[field] = selection
			pe:SetSetting(settingKey, selection)
		end,
		onChanged = function() pe:RefreshCraftsTab() end,
	})
end

-- A label to the left of a control, as one 26px-high group.
local function labelled(pe, parent, label, control)
	local group = CreateFrame("Frame", nil, parent)
	group:SetHeight(26)
	group.label = pe:CreateText(group, "GameFontHighlightSmall", "textMuted")
	group.label:SetPoint("LEFT")
	group.label:SetText(label)
	control:SetParent(group)
	control:ClearAllPoints()
	control:SetPoint("LEFT", group.label, "RIGHT", 6, 0)
	group:SetWidth(math.ceil(group.label:GetStringWidth()) + 6 + control:GetWidth())
	return group
end

local function copyBoolMap(t)
	local out = {}
	for k, v in pairs(type(t) == "table" and t or {}) do
		if v then
			out[k] = true
		end
	end
	return out
end

function AuctionHelper:CreateCraftsQueueView(parent)
	local pe = self
	local view = CreateFrame("Frame", nil, parent)
	view.summary = self:CreateParagraph(view)
	view.summary:SetPoint("TOPLEFT")
	view.summary:SetPoint("TOPRIGHT")

	view.craftHeading = self:CreateHeading(view, "To craft")
	view.craftHeading:SetPoint("TOPLEFT", view.summary, "BOTTOMLEFT", 0, -8)
	view.craftHeading:SetPoint("TOPRIGHT", view.summary, "BOTTOMRIGHT", 0, -8)
	view.craftTable = self:CreateReusableTable(view, {
		rowHeight = TALL_ROW,
		autoFitToScroll = true,
		emptyTitle = "Nothing queued",
		emptyHint = "Pick a craft and press Add to queue.",
	})
	view.craftTable.frame:SetPoint("TOPLEFT", view.craftHeading, "BOTTOMLEFT", 0, -6)
	view.craftTable.frame:SetPoint("TOPRIGHT", view.craftHeading, "BOTTOMRIGHT", 0, -6)
	view.craftTable:SetColumns({
		{ id = "recipe", label = "Recipe", width = 100, flex = 1, minWidth = 80,
			createCell = function(rowFrame)
				local cell = CreateFrame("Frame", nil, rowFrame)
				cell.name = pe:CreateText(cell, "GameFontHighlightSmall")
				cell.name:SetPoint("BOTTOMLEFT", cell, "LEFT", 5, 1)
				cell.name:SetPoint("RIGHT", cell, "RIGHT", -5, 0)
				cell.detail = pe:CreateText(cell, "GameFontHighlightSmall", "textMuted")
				cell.detail:SetPoint("TOPLEFT", cell, "LEFT", 5, -1)
				cell.detail:SetPoint("RIGHT", cell, "RIGHT", -5, 0)
				return cell
			end,
			updateCell = function(cell, entry)
				cell.name:SetText(entry.recipeName or "?")
				cell.detail:SetText(crafterName(pe, entry.characterKey))
			end },
		{ id = "qty", label = "Qty", width = 34, justifyH = "RIGHT", getText = function(entry) return tostring(entry.quantity or 0) end },
		{ id = "profit", label = "Profit", width = 76, justifyH = "RIGHT",
			getText = function(entry)
				local profit = entry.snapshot and tonumber(entry.snapshot.profit)
				return profit and pe:FormatSignedMoney(profit * (tonumber(entry.quantity) or 0)) or "-"
			end },
		{ id = "remove", label = "", width = 30,
			createCell = function(rowFrame)
				local cell = CreateFrame("Frame", nil, rowFrame)
				cell.button = CreateFrame("Button", nil, cell, "UIPanelCloseButton")
				cell.button:ClearAllPoints()
				cell.button:SetPoint("CENTER")
				pe:SkinCloseButton(cell.button)
				return cell
			end,
			updateCell = function(cell, entry)
				cell.button:SetScript("OnClick", function()
					pe:RemoveCraftFromQueue(entry.queueKey)
				end)
			end },
	})

	view.buyHeading = self:CreateHeading(view, "To buy")
	view.buyHeading:SetPoint("TOPLEFT", view.craftTable.frame, "BOTTOMLEFT", 0, -10)
	view.buyHeading:SetPoint("TOPRIGHT", view.craftTable.frame, "BOTTOMRIGHT", 0, -10)
	view.buyTable = self:CreateReusableTable(view, {
		autoFitToScroll = true,
		footer = true,
		emptyTitle = "Nothing to buy",
		emptyHint = "This character has every material the queue needs.",
	})
	view.buyTable.frame:SetPoint("TOPLEFT", view.buyHeading, "BOTTOMLEFT", 0, -6)
	view.buyTable:SetColumns({
		self:CreateItemColumn({ label = "Reagent", sortable = false,
			getItemID = function(line) return line.itemID end,
			getName = function(line) return line.name end }),
		{ id = "buy", label = "Buy", width = 40, justifyH = "RIGHT", getText = function(line) return pe:FormatNumberGrouped(line.quantityToBuy or 0) end },
		{ id = "cost", label = "Cost", width = 76, justifyH = "RIGHT",
			getText = function(line) return line.estimatedBuyCost and pe:FormatCopperShort(line.estimatedBuyCost) or "-" end },
	})

	view.footer = CreateFrame("Frame", nil, view)
	view.footer:SetPoint("BOTTOMLEFT")
	view.footer:SetPoint("BOTTOMRIGHT")
	view.footer:SetHeight(26)
	view.clearButton = self:CreateButton(view.footer, "Clear queue", function() pe:ClearCraftQueue() end)
	view.clearButton:SetPoint("RIGHT")
	view.clearButton:GetFontString():SetTextColor(pe:GetTheme().danger.r, pe:GetTheme().danger.g, pe:GetTheme().danger.b)
	view.clearOrdersButton = self:CreateButton(view.footer, "Clear orders", function()
		if pe.ClearCraftingOrderWorkQueue then
			pe:ClearCraftingOrderWorkQueue()
		end
	end)
	view.clearOrdersButton:SetPoint("RIGHT", view.clearButton, "LEFT", -8, 0)
	view.clearOrdersButton:SetShown(self.IS_RETAIL == true)
	view.hint = self:CreateText(view.footer, "GameFontHighlightSmall", "textMuted")
	view.hint:SetPoint("LEFT")
	view.hint:SetPoint("RIGHT", self.IS_RETAIL and view.clearOrdersButton or view.clearButton, "LEFT", -8, 0)
	view.hint:SetText("Buy from the auction house panel")
	view.buyTable.frame:SetPoint("BOTTOMRIGHT", view.footer, "TOPRIGHT", 0, 8)
	return view
end

function AuctionHelper:EnsureCraftsPanel(mainFrame)
	local ui = self.ui
	if ui.craftsPanel then
		return
	end
	local pe = self
	local panel = CreateFrame("Frame", nil, mainFrame)
	panel:SetAllPoints()
	ui.craftsPanel = panel
	ui.craftsDetailView = ui.craftsDetailView or "details"

	ui.craftsCharacterFilterValues = copyBoolMap(self:GetSetting("crafts.characterFilter", {}))
	ui.craftsProfessionFilterValues = copyBoolMap(self:GetSetting("crafts.professionFilter", {}))
	ui.craftsExpansionFilterValues = copyBoolMap(self:GetSetting("crafts.selectedExpansions", {}))
	ui.craftsCategoryFilterValues = copyBoolMap(self:GetSetting("crafts.categoryFilter", {}))

	-- Row 1: search and filters.
	panel.filters = CreateFrame("Frame", nil, panel)
	panel.filters:SetPoint("TOPLEFT")
	panel.filters:SetPoint("TOPRIGHT")
	panel.filters:SetHeight(26)
	panel.refreshButton = self:CreateButton(panel.filters, "Refresh", function() pe:RefreshCraftsTab() end, { primary = true })
	panel.refreshButton:SetPoint("RIGHT")
	ui.craftsClearBtn = self:CreateButton(panel.filters, "Reset", function()
		ui.craftsCharacterFilterValues = {}
		ui.craftsProfessionFilterValues = {}
		ui.craftsExpansionFilterValues = {}
		ui.craftsCategoryFilterValues = {}
		ui.craftsSearchBox:SetText("")
		ui.craftsSearchBox:UpdatePlaceholder()
		for _, key in ipairs({ "crafts.characterFilter", "crafts.professionFilter", "crafts.categoryFilter", "crafts.selectedExpansions" }) do
			pe:SetSetting(key, {})
		end
		pe:SetSetting("crafts.profitState", "all")
		pe:RefreshCraftsTab()
	end, { tooltip = "Clear the search and every filter." })
	ui.craftsProfitDropdown = createSelect(self, panel.filters, 112, {
		{ value = "all", label = "Any profit" },
		{ value = "profitable", label = "Profitable" },
		{ value = "negative", label = "Losing money" },
		{ value = "missing_price", label = "Missing price" },
		{ value = "uncraftable", label = "Can't craft now" },
	}, "crafts.profitState", "all")
	ui.craftsCategoryDropdown = createFilter(self, panel.filters, 120, "All categories",
		function() return pe:GetCraftCategoryFilterOptions(ui.craftsUnfilteredRows or {}) end, "craftsCategoryFilterValues", "crafts.categoryFilter")
	ui.craftsProfessionDropdown = createFilter(self, panel.filters, 128, "All professions",
		function() return pe:GetCraftProfessionFilterOptions() end, "craftsProfessionFilterValues", "crafts.professionFilter")
	ui.craftsCharacterDropdown = createFilter(self, panel.filters, 132, "All characters",
		function() return pe:GetInventoryCharacterFilterOptions() end, "craftsCharacterFilterValues", "crafts.characterFilter")
	local chain = { panel.refreshButton, ui.craftsClearBtn, ui.craftsProfitDropdown, ui.craftsCategoryDropdown, ui.craftsProfessionDropdown }
	if self.IS_RETAIL then
		ui.craftsExpansionDropdown = createFilter(self, panel.filters, 120, "All expansions",
			function() return pe:GetExpansionFilterOptions() end, "craftsExpansionFilterValues", "crafts.selectedExpansions")
		chain[#chain + 1] = ui.craftsExpansionDropdown
	end
	chain[#chain + 1] = ui.craftsCharacterDropdown
	self:ChainLeft(chain, 8)
	ui.craftsSearchBox = self:CreateSearchBox(panel.filters, "Search item or recipe", function()
		pe:RefreshCraftsTab()
	end)
	ui.craftsSearchBox:SetPoint("LEFT", 6, 0)
	ui.craftsSearchBox:SetPoint("RIGHT", ui.craftsCharacterDropdown, "LEFT", -14, 0)

	-- Row 2: how prices are worked out.
	panel.options = CreateFrame("Frame", nil, panel)
	panel.options:SetPoint("TOPLEFT", panel.filters, "BOTTOMLEFT", 0, -8)
	panel.options:SetPoint("TOPRIGHT", panel.filters, "BOTTOMRIGHT", 0, -8)
	panel.options:SetHeight(26)
	panel.sourceDropdown = createSelect(self, panel, 110, {
		{ value = "owned_first", label = "Owned first" },
		{ value = "market_only", label = "Market only" },
		{ value = "mixed", label = "Mixed" },
	}, "crafts.reagentSourceMode", "owned_first", nil, "Which materials count as already paid for")
	panel.basisDropdown = createSelect(self, panel, 92, {
		{ value = "auto", label = "Auto" },
		{ value = "market", label = "Market" },
		{ value = "ledger", label = "Ledger" },
	}, "crafts.costBasis", "auto", function(value)
		pe:SetSetting("crafts.saleBasis", value == "market" and "market" or value == "ledger" and "ledger" or "auto")
		pe:RefreshCraftsTab()
	end, "Where sale and cost prices come from")
	panel.craftsRangeDropdown = createSelect(self, panel, 92, self:GetInventoryMetricRangeOptions(), "inventory.metricRange", "30d", function()
		pe:RenderCraftsDetails(ui.craftsSelectedRowData)
	end, "Time range for price history")
	local groups = {
		labelled(self, panel.options, "Materials", panel.sourceDropdown),
		labelled(self, panel.options, "Price basis", panel.basisDropdown),
		labelled(self, panel.options, "History", panel.craftsRangeDropdown),
	}
	if self.IS_RETAIL then
		panel.scenarioDropdown = createSelect(self, panel, 140, {
			{ value = "default", label = "No concentration" },
			{ value = "concentration", label = "With concentration" },
		}, "crafts.scenario", "default")
		groups[#groups + 1] = labelled(self, panel.options, "Scenario", panel.scenarioDropdown)
	end
	groups[1]:SetPoint("LEFT")
	self:ChainRight(groups, 16)
	panel.optionsNote = self:CreateText(panel.options, "GameFontHighlightSmall", "textMuted", "RIGHT")
	panel.optionsNote:SetPoint("RIGHT")
	panel.optionsNote:SetPoint("LEFT", groups[#groups], "RIGHT", 16, 0)

	-- Detail pane: Details / Queue.
	panel.detailCard = self:CreateInset(panel)
	panel.detailCard:SetPoint("TOPRIGHT", panel.options, "BOTTOMRIGHT", 0, -GAP)
	panel.detailCard:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
	panel.detailCard:SetWidth(DETAIL_WIDTH)
	if panel.detailCard.SetClipsChildren then
		panel.detailCard:SetClipsChildren(true)
	end
	local inner = DETAIL_WIDTH - PAD * 2
	panel.detailsTab = self:CreateButton(panel.detailCard, "Details", function()
		ui.craftsDetailView = "details"
		pe:LayoutCraftsPanel(panel)
	end, { small = true, width = math.floor(inner / 2) + 1 })
	panel.detailsTab:SetPoint("TOPLEFT", PAD, -PAD)
	panel.queueTab = self:CreateButton(panel.detailCard, "Queue", function()
		ui.craftsDetailView = "queue"
		pe:LayoutCraftsPanel(panel)
	end, { small = true, width = inner - math.floor(inner / 2) })
	panel.queueTab:SetPoint("LEFT", panel.detailsTab, "RIGHT", -1, 0)

	panel.detailsView = CreateFrame("Frame", nil, panel.detailCard)
	panel.detailsView:SetPoint("TOPLEFT", panel.detailsTab, "BOTTOMLEFT", 0, -10)
	panel.detailsView:SetPoint("BOTTOMRIGHT", panel.detailCard, "BOTTOMRIGHT", -PAD, PAD)
	panel.detailsEmpty = self:CreateEmptyState(panel.detailsView)
	panel.detailsEmpty:SetAllPoints()
	panel.detailsEmpty:SetMessage("Select a craft", "Click a row to see its materials and profit.")
	panel.detailsBody = CreateFrame("Frame", nil, panel.detailsView)
	panel.detailsBody:SetAllPoints()
	panel.detailHeader = self:CreateDetailHeader(panel.detailsBody)
	panel.detailHeader:SetPoint("TOPLEFT")
	panel.detailHeader:SetPoint("TOPRIGHT")
	panel.detailFacts = self:CreateKeyValueList(panel.detailsBody)
	panel.detailFacts:SetPoint("TOPLEFT", panel.detailHeader, "BOTTOMLEFT", 0, -10)
	panel.detailFacts:SetPoint("TOPRIGHT", panel.detailHeader, "BOTTOMRIGHT", 0, -10)
	panel.materialsHeading = self:CreateHeading(panel.detailsBody, "Materials per craft")
	panel.materialsHeading:SetPoint("TOPLEFT", panel.detailFacts, "BOTTOMLEFT", 0, -10)
	panel.materialsHeading:SetPoint("TOPRIGHT", panel.detailFacts, "BOTTOMRIGHT", 0, -10)
	panel.detailActions = CreateFrame("Frame", nil, panel.detailsBody)
	panel.detailActions:SetPoint("BOTTOMLEFT")
	panel.detailActions:SetPoint("BOTTOMRIGHT")
	panel.detailActions:SetHeight(26)
	panel.detailQueueQty = CreateFrame("EditBox", nil, panel.detailActions, "InputBoxTemplate")
	panel.detailQueueQty:SetSize(32, 22)
	panel.detailQueueQty:SetPoint("LEFT", 6, 0)
	panel.detailQueueQty:SetAutoFocus(false)
	panel.detailQueueQty:SetNumeric(true)
	panel.detailQueueQty:SetMaxLetters(4)
	panel.detailQueueQty:SetJustifyH("RIGHT")
	panel.detailQueueQty:SetText("1")
	self:SkinEditBox(panel.detailQueueQty)
	panel.detailQueueQty:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
	panel.detailQueueRemove = self:CreateButton(panel.detailActions, "Remove", function()
		if ui.craftsSelectedRowData then
			pe:RemoveCraftQueueLinesForOpportunityRow(ui.craftsSelectedRowData)
		end
	end)
	panel.detailQueueRemove:SetPoint("RIGHT")
	panel.detailQueueAddN = self:CreateButton(panel.detailActions, "Add to queue", function()
		local n = tonumber(panel.detailQueueQty:GetText()) or 1
		if ui.craftsSelectedRowData and n > 0 then
			pe:AddCraftToQueue(ui.craftsSelectedRowData, n)
		end
	end, { primary = true })
	panel.detailQueueAddN:SetPoint("LEFT", panel.detailQueueQty, "RIGHT", 10, 0)
	panel.detailQueueAddN:SetPoint("RIGHT", panel.detailQueueRemove, "LEFT", -8, 0)
	panel.materialsTable = self:CreateReusableTable(panel.detailsBody, {
		autoFitToScroll = true,
		emptyTitle = "No materials",
		emptyHint = "This recipe has no stored reagents.",
	})
	panel.materialsTable.frame:SetPoint("TOPLEFT", panel.materialsHeading, "BOTTOMLEFT", 0, -6)
	panel.materialsTable.frame:SetPoint("BOTTOMRIGHT", panel.detailActions, "TOPRIGHT", 0, 10)
	panel.materialsTable:SetColumns({
		self:CreateItemColumn({ label = "Reagent", sortable = false,
			getItemID = function(slot) return slot.itemID end,
			getName = function(slot) return pe:GetItemDisplayName(slot.itemID) end }),
		{ id = "need", label = "Need", width = 38, justifyH = "RIGHT", getText = function(slot) return tostring(slot.need) end },
		{ id = "have", label = "Have", width = 40, justifyH = "RIGHT",
			getText = function(slot)
				if slot.have == nil then
					return "-"
				end
				return slot.have < slot.need and colorize(pe, "danger", tostring(slot.have)) or tostring(slot.have)
			end },
		{ id = "cost", label = "Cost", width = 70, justifyH = "RIGHT", getText = function(slot) return slot.cost and pe:FormatCopperShort(slot.cost) or "-" end },
	})

	panel.queueView = self:CreateCraftsQueueView(panel.detailCard)
	panel.queueView:SetPoint("TOPLEFT", panel.detailsTab, "BOTTOMLEFT", 0, -10)
	panel.queueView:SetPoint("BOTTOMRIGHT", panel.detailCard, "BOTTOMRIGHT", -PAD, PAD)

	-- The opportunities table fills the rest.
	ui.craftsTable = self:CreateReusableTable(panel, {
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
		onRowEnter = function(rowFrame, rowData)
			pe:ShowCraftRowTooltip(rowFrame, rowData)
		end,
		onRowLeave = function()
			GameTooltip:Hide()
		end,
		onRowClick = function(_, rowData, _, tableWidget)
			if pe:HandleItemRowModifiedClick(rowData and rowData.outputItemID) then
				return
			end
			ui.craftsItemDetailOnlyItemID = nil
			ui.craftsSelectedRowKey = rowData and rowData.rowKey
			ui.craftsDetailView = "details"
			pe:SetSetting("crafts.selectedRowKey", ui.craftsSelectedRowKey)
			tableWidget:SetSelectedRow(rowData)
			pe:RenderCraftsDetails(rowData)
		end,
	})
	ui.craftsTable.frame:SetPoint("TOPLEFT", panel.options, "BOTTOMLEFT", 0, -GAP)
	ui.craftsTable.frame:SetPoint("BOTTOMRIGHT", panel.detailCard, "BOTTOMLEFT", -GAP, 0)
	panel.craftsTable = ui.craftsTable
	ui.craftsTable:SetColumns(self:BuildCraftsTableColumns())
	ui.craftsTable.scrollFrame:HookScript("OnVerticalScroll", function()
		if pe.QueueVisibleCraftsTabAuctionRefresh then
			C_Timer.After(0.12, function()
				pe:QueueVisibleCraftsTabAuctionRefresh(false)
			end)
		end
	end)

	self:SkinTree(panel)
	self:LayoutCraftsPanel(panel)
	ui.craftsSelectedRowKey = self:GetSetting("crafts.selectedRowKey")
end

function AuctionHelper:ShowCraftRowTooltip(rowFrame, row)
	if not row or not row.outputItemID then
		return
	end
	local ev = bestEvaluation(row) or {}
	local pairs = {
		{ "Recipe", row.recipeName or "-" },
		{ "Best crafter", row.bestCharacterKey and crafterName(self, row.bestCharacterKey) or "-" },
		{ "Sale, net", row.saleNet and self:FormatCopperFull(row.saleNet) or "-" },
		{ "Materials", row.matCost and self:FormatCopperFull(row.matCost) or "-" },
		{ "Profit", self:FormatSignedMoney(row.profit) },
	}
	for index, slot in ipairs(ev.reagentPlan or {}) do
		if index > 6 then
			break
		end
		pairs[#pairs + 1] = {
			string.format("  %s x%s", self:GetItemDisplayName(slot.itemID), self:FormatNumberGrouped(slot.quantityRequired or 0)),
			slot.lineCost and self:FormatCopperShort(slot.lineCost) or "-",
		}
	end
	self:ShowItemRowTooltip(rowFrame, row.outputItemID, pairs, "Click for details · Shift-click to link")
end

function AuctionHelper:BuildCraftsFilterState()
	local ui = self.ui or {}
	return {
		text = trim(ui.craftsSearchBox and ui.craftsSearchBox:GetText() or ""),
		characters = ui.craftsCharacterFilterValues or {},
		professions = ui.craftsProfessionFilterValues or {},
		expansions = self.IS_RETAIL and ui.craftsExpansionFilterValues or {},
		categories = ui.craftsCategoryFilterValues or {},
		profitState = self:GetSetting("crafts.profitState", "all"),
	}
end

function AuctionHelper:RefreshCraftsTab()
	self:InitDB()
	local ui = self.ui
	if not ui or not ui.craftsPanel or ui.activeMainTab ~= "crafts" then
		return
	end
	local panel = ui.craftsPanel

	local rows = self:BuildCraftOpportunityRows()
	ui.craftsUnfilteredRows = rows
	for _, row in ipairs(rows) do
		row._rowIdentity = row.rowKey or tostring(row.recipeID)
	end

	local charOpts = self:GetInventoryCharacterFilterOptions()
	local profOpts = self:GetCraftProfessionFilterOptions()
	local catOpts = self:GetCraftCategoryFilterOptions(rows)
	ui.craftsCharacterFilterValues = self:NormalizeFilterSelection(ui.craftsCharacterFilterValues or {}, charOpts)
	ui.craftsProfessionFilterValues = self:NormalizeFilterSelection(ui.craftsProfessionFilterValues or {}, profOpts)
	ui.craftsCategoryFilterValues = self:NormalizeFilterSelection(ui.craftsCategoryFilterValues or {}, catOpts)
	ui.craftsCharacterDropdown:SetOptions(charOpts)
	ui.craftsProfessionDropdown:SetOptions(profOpts)
	ui.craftsCategoryDropdown:SetOptions(catOpts)
	if ui.craftsExpansionDropdown then
		local expOpts = self:GetExpansionFilterOptions()
		ui.craftsExpansionFilterValues = self:NormalizeFilterSelection(ui.craftsExpansionFilterValues or {}, expOpts)
		ui.craftsExpansionDropdown:SetOptions(expOpts)
	end
	for _, dropdown in ipairs({ ui.craftsProfitDropdown, panel.sourceDropdown, panel.basisDropdown, panel.craftsRangeDropdown, panel.scenarioDropdown }) do
		dropdown:RefreshText()
	end

	rows = self:FilterCraftRows(rows, self:BuildCraftsFilterState())
	ui.craftsWorkingRows = rows

	local craftState = self:GetState()
	local note = string.format("Auction cut %d%% · %s", tonumber(self:GetSetting("crafts.ahCutPercent", 5)) or 5,
		self.IS_RETAIL and "Prices from TSM, Auctionator or scans" or "Prices from the last auction house scan")
	if craftState.craftEvalInProgress and craftState.craftEvalWorkList and #craftState.craftEvalWorkList > 0 then
		local done = math.max(0, (craftState.craftEvalIdx or 1) - 1)
		note = colorize(self, "warning", string.format("Updating %d of %d recipes…", done, #craftState.craftEvalWorkList))
	end
	panel.optionsNote:SetText(note)

	ui.craftsTable.sortKey = self:GetSetting("crafts.sortColumn", "profit")
	ui.craftsTable.sortAsc = self:GetSetting("crafts.sortAsc", false)
	ui.craftsTable:SetRows(rows)
	ui.craftsTable:Refresh()
	local profitable, professions = 0, {}
	for _, row in ipairs(rows) do
		if (tonumber(row.profit) or 0) > 0 then
			profitable = profitable + 1
		end
		professions[row.professionName or "?"] = true
	end
	ui.craftsTable:SetFooterText(string.format("%s profitable of %s crafts", self:FormatNumberGrouped(profitable), self:FormatNumberGrouped(#rows)),
		string.format("%d professions", self:TableCount(professions)))

	local picked
	for _, r in ipairs(rows) do
		if r.rowKey == ui.craftsSelectedRowKey then
			picked = r
			break
		end
	end
	if not picked and rows[1] and not ui.craftsItemDetailOnlyItemID then
		picked = rows[1]
		ui.craftsSelectedRowKey = picked.rowKey
	end
	self:RenderCraftsDetails(picked)
	self:RefreshCraftsQueuePanel()
	if self.QueueVisibleCraftsTabAuctionRefresh then
		self:QueueVisibleCraftsTabAuctionRefresh(false)
	end
end

function AuctionHelper:FocusCraftsQueuePanel()
	local panel = self.ui and self.ui.craftsPanel
	if not panel then
		return
	end
	self.ui.craftsDetailView = "queue"
	self:LayoutCraftsPanel(panel)
	if UIFrameFlash then
		UIFrameFlash(panel.queueView, 0.4, 0.4, 0.6, false, 0, 0)
	end
end

function AuctionHelper:RefreshCraftsQueuePanel()
	local panel = self.ui and self.ui.craftsPanel
	if not panel or not panel.queueView then
		return
	end
	local view = panel.queueView
	local sum = self:BuildCraftQueueSummary()
	local lines = sum.lines or {}
	local crafts = 0
	for _, entry in ipairs(lines) do
		crafts = crafts + (tonumber(entry.quantity) or 0)
	end
	self:SetButtonLabel(panel.queueTab, #lines > 0 and string.format("Queue (%d)", #lines) or "Queue", true)
	panel.queueTab:SetWidth(DETAIL_WIDTH - PAD * 2 - panel.detailsTab:GetWidth() + 1)
	view.summary:SetText(#lines == 0 and "The queue is empty." or string.format("%d crafts of %d recipes · potential profit %s",
		crafts, #lines, sum.totalProfit and self:FormatSignedMoney(sum.totalProfit) or "unknown"))

	for index, entry in ipairs(lines) do
		entry._rowIdentity = index
	end
	view.craftTable:SetRows(lines)
	view.craftTable:Refresh()
	view.craftTable.frame:SetHeight(22 + 2 + TALL_ROW * math.max(1, math.min(#lines, 4)))

	local buy = {}
	for _, line in ipairs(sum.reagentLines or {}) do
		if (tonumber(line.quantityToBuy) or 0) > 0 then
			line._rowIdentity = line.itemID
			buy[#buy + 1] = line
		end
	end
	local me = self:GetCharacterKey()
	view.buyHeading:SetText("To buy on " .. crafterName(self, me))
	view.buyTable:SetRows(buy)
	view.buyTable:Refresh()
	local mail = {}
	for _, line in ipairs(buy) do
		if line.mailToText and line.mailToText ~= "" then
			mail[#mail + 1] = line.mailToText
		end
	end
	view.buyTable:SetFooterText(#mail > 0 and ("Mail: " .. table.concat(mail, ", ")) or nil,
		sum.totalCurrentCharacterBuyCost and self:FormatCopperShort(sum.totalCurrentCharacterBuyCost) or nil)
	view.clearButton:SetEnabled(#lines > 0)
end

function AuctionHelper:RefreshCraftsTabIfVisible()
	local ui = self.ui
	if ui and ui.activeMainTab == "crafts" then
		self:RefreshCraftsTab()
	elseif ui and ui.activeMainTab == "overview" and ui.goldDashboard and ui.goldDashboard:IsVisible() then
		ui.goldDashboard:RefreshCrafts()
	end
end

-- Name and muted second line for a craft opportunity row, as the Crafts table shows them.
function AuctionHelper:GetCraftRowLabels(row)
	return craftRowName(self, row), craftRowDetail(self, row)
end

-- Switches to the Crafts tab with `row` selected and its details open.
function AuctionHelper:OpenCraftRow(row)
	local ui = self.ui
	ui.craftsSelectedRowKey = row and row.rowKey
	ui.craftsItemDetailOnlyItemID = nil
	ui.craftsDetailView = "details"
	self:ShowDashboardTab("crafts")
	self:RenderCraftsDetails(row)
end
