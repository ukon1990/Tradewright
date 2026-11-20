local ProfessionExporter = select(2, ...)

-- Opportunities tab (F50): flips priced after fees, with the sums in a side pane.

local OpportunitiesTab = {}
ProfessionExporter.OpportunitiesTab = OpportunitiesTab

local GAP = 12
local PAD = 10
local DETAIL_WIDTH = 300
local TALL_ROW = 36

local function percent(fraction)
	return string.format("%d%%", math.floor((fraction or 0) * 100 + 0.5))
end

-- "12" for a busy item, "0.4" for a slow one.
local function perDayText(pe, perDay)
	if perDay >= 10 then
		return pe:FormatNumberGrouped(math.floor(perDay + 0.5))
	end
	return string.format("%.1f", perDay)
end

-- Second line of a flip row: how far under usual, and the caveat that matters most.
local function rowDetail(pe, row)
	local detail = percent(row.discount) .. " under usual"
	if row.fewSales then
		return detail .. " · few sales seen"
	elseif row.slow then
		return detail .. " · sells slowly"
	elseif row.listedUnder then
		return string.format("%s · %s listed under %s", detail, pe:FormatNumberGrouped(row.listedUnder), pe:FormatCopperShort(row.limitPrice))
	end
	return detail
end

local function flipColumns(pe)
	local function money(id, label, field, width)
		return {
			id = id, label = label, justifyH = "RIGHT", width = width or 76, sortable = true, defaultSort = "desc",
			sortValue = function(row) return row[field] or 0 end,
			getText = function(row) return pe:FormatCopperShort(row[field]) end,
		}
	end
	return {
		pe:CreateItemColumn({
			label = "Item", defaultSort = "asc",
			getItemID = function(row) return row.itemID end,
			getName = function(row) return pe:GetItemDisplayName(row.itemID) end,
			getDetail = function(row) return rowDetail(pe, row) end,
		}),
		money("price", "Buy at", "price"),
		money("usual", "Usual", "usual"),
		{
			id = "buyQty", label = "Buy", justifyH = "RIGHT", width = 44, sortable = true, defaultSort = "desc",
			sortValue = function(row) return row.buyQty or 0 end,
			getText = function(row) return row.buyQty and pe:FormatNumberGrouped(row.buyQty) or "-" end,
		},
		{
			id = "profit", label = "Profit", justifyH = "RIGHT", width = 84, sortable = true, defaultSort = "desc",
			sortValue = function(row) return row.profit or 0 end,
			getText = function(row) return pe:FormatSignedMoney(row.profit) end,
		},
		{
			id = "sellsPerDay", label = "Sells a day", justifyH = "RIGHT", width = 70, sortable = true, defaultSort = "desc",
			sortValue = function(row) return row.sellsPerDay or 0 end,
			getText = function(row) return perDayText(pe, row.sellsPerDay) end,
		},
	}
end

-- The sums behind one flip, as label and value pairs.
local function detailRows(pe, row)
	local units = row.buyQty or 1
	return {
		{ "Cheapest now", pe:FormatCopperFull(row.price) },
		{ string.format("Usual price, %d days", row.usualDays or 0), pe:FormatCopperFull(row.usual) },
		{ string.format("Sale after %s cut", percent(1 - row.saleNet / row.usual)), pe:FormatCopperFull(row.saleNet) },
		{ "Profit each", pe:FormatSignedMoney(row.profitEach), "success" },
		{ "Return", percent(row.roi) },
		{ "", "" },
		{ "Listed under " .. pe:FormatCopperShort(row.limitPrice), row.listedUnder and pe:FormatNumberGrouped(row.listedUnder) or "-" },
		{ "Sells a day, estimated", perDayText(pe, row.sellsPerDay) },
		{ string.format("Buy %s and spend", pe:FormatNumberGrouped(units)), pe:FormatCopperFull(row.cost) },
		{ "Profit if all sell at the usual price", pe:FormatSignedMoney(row.profit), "success" },
	}
end

local function riskText(pe, row)
	local range = string.format("Its price stayed between %s and %s on the middle half of the last %d days.",
		pe:FormatCopperShort(row.usualLow or row.usual), pe:FormatCopperShort(row.usualHigh or row.usual), row.usualDays or 0)
	local breakEven = string.format(" Below %s you lose gold on each one.", pe:FormatCopperShort(row.breakEven))
	local caveat = ""
	if row.fewSales then
		caveat = " Few sales were seen, so it may sell slower than shown."
	elseif not row.buyQty then
		caveat = " No price steps are kept, so the quantity at this price is unknown."
	end
	return range .. breakEven .. caveat
end

local function buildDetail(pe, panel)
	local card = pe:CreateInset(panel)
	card:SetWidth(DETAIL_WIDTH)
	card.empty = pe:CreateEmptyState(card)
	card.empty:SetAllPoints()
	card.empty:SetMessage("Select a flip", "Click a row to see the sums behind it and what could go wrong.")
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
	panel.selected = row
	card.empty:SetShown(row == nil)
	card.body:SetShown(row ~= nil)
	if not row then
		return
	end
	card.header:SetItem(row.itemID, pe:GetItemDisplayName(row.itemID), percent(row.discount) .. " under its usual price")
	card.facts:SetRows(detailRows(pe, row))
	card.risk:SetText(riskText(pe, row))
	local ahOpen = pe.IsAuctionHouseFrameOpen and pe:IsAuctionHouseFrameOpen()
	card.open:SetEnabled(ahOpen == true)
	card.openHint:SetText(ahOpen and "" or "Open the auction house to go to this item.")
end

local function buildTable(pe, panel)
	return pe:CreateReusableTable(panel, {
		footer = true,
		rowHeight = TALL_ROW,
		emptyTitle = "No flips right now",
		emptyHint = "Scan the auction house on a few different days to build usual prices.",
		autoFitToScroll = true,
		sortKey = "profit",
		sortAsc = false,
		isRowSelected = function(row)
			return panel.selected ~= nil and row ~= nil and row.itemID == panel.selected.itemID
		end,
		onRowEnter = function(rowFrame, row)
			pe:ShowItemRowTooltip(rowFrame, row and row.itemID, {
				{ "Profit each after the cut", pe:FormatSignedMoney(row and row.profitEach) },
			}, "Click for the sums · Right-click to open in the auction house · Shift-click to link")
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

local function buildPanel(pe, container)
	local panel = CreateFrame("Frame", nil, container)
	panel:SetAllPoints()
	panel.statsRow = CreateFrame("Frame", nil, panel)
	panel.statsRow:SetPoint("TOPLEFT")
	panel.statsRow:SetPoint("TOPRIGHT")
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
	panel.table:SetColumns(flipColumns(pe))
	panel:SetScript("OnSizeChanged", function(self)
		pe:LayoutEvenRow(self.statsRow, self.stats, 0, GAP)
	end)
	showDetail(pe, panel, nil)
	return panel
end

local function refreshStats(pe, panel, rows, insights)
	local profit, cost = 0, 0
	for _, row in ipairs(rows) do
		profit, cost = profit + row.profit, cost + row.cost
	end
	local opts = pe:GetFlipOptions()
	panel.stats[1]:SetValues(string.format("Expected profit, all %d", #rows), pe:FormatSignedMoney(profit), "After the auction cut", "success")
	panel.stats[2]:SetValues("Gold needed", pe:FormatCopperShort(cost), "You have " .. pe:FormatCopperShort(GetMoney()))
	panel.stats[3]:SetValues("Usual price from", pe:GetSetting("auction.usualPriceDays", 14) .. " days", "Middle price of your scans")
	local lastScan = insights.lastSeenAt and pe:FormatScanTimestamp(insights.lastSeenAt) or "not yet"
	panel.stats[4]:SetValues("Auction cut", percent(opts.cut), "Last scan " .. lastScan)
	pe:LayoutEvenRow(panel.statsRow, panel.stats, 0, GAP)
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
	local rows, insights = pe:GetFlipRows(function()
		if panel:IsVisible() then
			self:Refresh()
		end
	end)
	if not rows then
		panel.table:SetRows({})
		panel.table:SetFooterText("Reading the last scan…", "")
		panel.table:Refresh()
		return
	end
	refreshStats(pe, panel, rows, insights)
	panel.table:SetRows(rows)
	panel.table:SetFooterText(string.format("%d flips from %s items", #rows, pe:FormatNumberGrouped(insights.itemCount or 0)),
		"Buy is capped at a share of a day's sales")
	panel.table:Refresh()
	if panel.selected then
		local stillThere
		for _, row in ipairs(rows) do
			stillThere = stillThere or (row.itemID == panel.selected.itemID and row)
		end
		showDetail(pe, panel, stillThere or nil)
	end
end
