local ProfessionExporter = select(2, ...)

-- Opportunities tab: one table and side pane, switched between lists (views).
-- Each view lives in AuctionHelper_OpportunityViews.lua and supplies its rows, columns and side-pane text.

local OpportunitiesTab = {}
ProfessionExporter.OpportunitiesTab = OpportunitiesTab

local GAP = 12
local PAD = 10
local DETAIL_WIDTH = 300
local TALL_ROW = 36

local function currentView(pe)
	local views = pe.OpportunityViews
	local wanted = pe:GetSetting("opportunities.view", views[1].id)
	for _, view in ipairs(views) do
		if view.id == wanted then
			return view
		end
	end
	return views[1]
end

local function buildDetail(pe, panel)
	local card = pe:CreateInset(panel)
	card:SetWidth(DETAIL_WIDTH)
	card.empty = pe:CreateEmptyState(card)
	card.empty:SetAllPoints()
	card.body = CreateFrame("Frame", nil, card)
	card.body:SetPoint("TOPLEFT", PAD, -PAD)
	card.body:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	card.header = pe:CreateDetailHeader(card.body)
	card.header:SetPoint("TOPLEFT")
	card.header:SetPoint("TOPRIGHT")
	card.facts = pe:CreateKeyValueList(card.body)
	card.facts:SetPoint("TOPLEFT", card.header, "BOTTOMLEFT", 0, -10)
	card.facts:SetPoint("TOPRIGHT", card.header, "BOTTOMRIGHT", 0, -10)
	card.facts:SetHeight(10 * 16)
	card.riskHeading = pe:CreateHeading(card.body, "What could go wrong")
	card.riskHeading:SetPoint("TOPLEFT", card.facts, "BOTTOMLEFT", 0, -10)
	card.riskHeading:SetPoint("TOPRIGHT", card.facts, "BOTTOMRIGHT", 0, -10)
	card.risk = pe:CreateParagraph(card.body)
	card.risk:SetPoint("TOPLEFT", card.riskHeading, "BOTTOMLEFT", 0, -6)
	card.risk:SetPoint("TOPRIGHT", card.riskHeading, "BOTTOMRIGHT", 0, -6)
	card.open = pe:CreateButton(card.body, "Open in auction house", function()
		if panel.selected then
			pe:OpenItemInAuctionHouse(panel.selected.itemID)
		end
	end)
	card.open:SetPoint("BOTTOMLEFT")
	card.open:SetPoint("BOTTOMRIGHT")
	card.openHint = pe:CreateText(card.body, "GameFontHighlightSmall", "textMuted")
	card.openHint:SetPoint("BOTTOMLEFT", card.open, "TOPLEFT", 0, 6)
	card.openHint:SetPoint("BOTTOMRIGHT", card.open, "TOPRIGHT", 0, 6)
	return card
end

local function showDetail(pe, panel, row)
	local card = panel.detail
	local view = currentView(pe)
	panel.selected = row
	card.empty:SetShown(row == nil)
	card.body:SetShown(row ~= nil)
	if not row then
		card.empty:SetMessage(pe:GetOpportunityHelp(view))
		return
	end
	card.header:SetItem(row.itemID, pe:GetItemDisplayName(row.itemID), view.subtitle(pe, row))
	card.facts:SetRows(view.detailRows(pe, row))
	card.risk:SetText(view.riskText(pe, row))
	local ahOpen = pe.IsAuctionHouseFrameOpen and pe:IsAuctionHouseFrameOpen()
	card.open:SetEnabled(ahOpen == true)
	card.openHint:SetText(ahOpen and "" or "Open the auction house to go to this item.")
end

local function buildTable(pe, panel)
	return pe:CreateReusableTable(panel, {
		footer = true,
		rowHeight = TALL_ROW,
		autoFitToScroll = true,
		sortKey = "profit",
		sortAsc = false,
		isRowSelected = function(row)
			return panel.selected ~= nil and row ~= nil and row.itemID == panel.selected.itemID
		end,
		onRowEnter = function(rowFrame, row)
			pe:ShowItemRowTooltip(rowFrame, row and row.itemID, currentView(pe).tooltipPairs(pe, row),
				"Click for the sums · Right-click to open in the auction house · Shift-click to link")
		end,
		onRowLeave = function()
			GameTooltip:Hide()
		end,
		onRowClick = function(_, row, button, tableWidget)
			if not row or pe:HandleItemRowModifiedClick(row.itemID) then
				return
			end
			tableWidget:SetSelectedRow(row)
			showDetail(pe, panel, row)
			if button == "RightButton" and pe:IsAuctionHouseFrameOpen() then
				pe:OpenItemInAuctionHouse(row.itemID)
			end
		end,
	})
end

-- One button per list, left to right, above the stats.
local function buildViewButtons(pe, panel)
	panel.viewRow = CreateFrame("Frame", nil, panel)
	panel.viewRow:SetPoint("TOPLEFT")
	panel.viewRow:SetPoint("TOPRIGHT")
	panel.viewRow:SetHeight(26)
	panel.viewButtons = {}
	local previous
	for _, view in ipairs(pe.OpportunityViews) do
		local button = pe:CreateButton(panel.viewRow, view.label, function()
			pe:SetSetting("opportunities.view", view.id)
			panel.selected = nil
			OpportunitiesTab:Refresh()
		end)
		button.view = view
		if previous then
			button:SetPoint("LEFT", previous, "RIGHT", -1, 0)
		else
			button:SetPoint("LEFT")
		end
		previous = button
		panel.viewButtons[#panel.viewButtons + 1] = button
	end
end

local function buildPanel(pe, container)
	local panel = CreateFrame("Frame", nil, container)
	panel:SetAllPoints()
	buildViewButtons(pe, panel)
	panel.statsRow = CreateFrame("Frame", nil, panel)
	panel.statsRow:SetPoint("TOPLEFT", panel.viewRow, "BOTTOMLEFT", 0, -GAP)
	panel.statsRow:SetPoint("TOPRIGHT", panel.viewRow, "BOTTOMRIGHT", 0, -GAP)
	panel.statsRow:SetHeight(58)
	panel.stats = {}
	for index = 1, 4 do
		panel.stats[index] = pe:CreateStat(panel.statsRow)
	end
	panel.detail = buildDetail(pe, panel)
	panel.detail:SetPoint("TOPRIGHT", panel.statsRow, "BOTTOMRIGHT", 0, -GAP)
	panel.detail:SetPoint("BOTTOMRIGHT")
	panel.table = buildTable(pe, panel)
	panel.table.frame:SetPoint("TOPLEFT", panel.statsRow, "BOTTOMLEFT", 0, -GAP)
	panel.table.frame:SetPoint("BOTTOMRIGHT", panel.detail, "BOTTOMLEFT", -GAP, 0)
	panel:SetScript("OnSizeChanged", function(self)
		pe:LayoutEvenRow(self.statsRow, self.stats, 0, GAP)
	end)
	showDetail(pe, panel, nil)
	return panel
end

-- Button labels carry each list's row count once its rows are known.
local function refreshViewButtons(pe, panel, active)
	for _, button in ipairs(panel.viewButtons) do
		local rows = button.view.getRows(pe)
		button:SetText(rows and string.format("%s (%d)", button.view.label, #rows) or button.view.label)
		pe:StyleShellButton(button, button.view == active)
	end
end

-- Keep the selected row when it is still listed; otherwise show the empty side pane.
local function reselect(pe, panel, rows)
	local keep
	for _, row in ipairs(rows) do
		if panel.selected and row.itemID == panel.selected.itemID then
			keep = row
		end
	end
	showDetail(pe, panel, keep)
end

function OpportunitiesTab:Create(container, uiState)
	uiState.opportunitiesPanel = uiState.opportunitiesPanel or buildPanel(ProfessionExporter, container)
	uiState.opportunitiesPanel:Show()
	return uiState.opportunitiesPanel
end

function OpportunitiesTab:ApplyTheme() -- luacheck: ignore 212
end

function OpportunitiesTab:Refresh()
	local pe = ProfessionExporter
	local panel = pe.ui and pe.ui.opportunitiesPanel
	if not panel then
		return
	end
	local view = currentView(pe)
	local rows, insights, funnel = view.getRows(pe, function()
		if panel:IsVisible() then
			self:Refresh()
		end
	end)
	if panel.shownView ~= view then
		-- SetColumns redraws at once: drop the previous list's rows so its columns never draw them.
		panel.table:SetRows({})
		panel.shownView = view
	end
	panel.table:SetColumns(view.columns(pe))
	panel.table:SetEmptyText(view.emptyTitle, view.emptyHint)
	refreshViewButtons(pe, panel, view)
	if not rows then
		panel.table:SetRows({})
		panel.table:SetFooterText("Reading the last scan…", "")
		panel.table:Refresh()
		return
	end
	panel.table:SetEmptyText(pe:GetOpportunityEmptyText(view, funnel, insights))
	view.setStats(pe, panel.stats, rows, insights)
	pe:LayoutEvenRow(panel.statsRow, panel.stats, 0, GAP)
	panel.table:SetRows(rows)
	panel.table:SetFooterText(view.footer(pe, rows, insights))
	panel.table:Refresh()
	reselect(pe, panel, rows)
end
