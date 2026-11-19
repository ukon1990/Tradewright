local addonName, ProfessionExporter = ...

local ROW_H = 24
local MAX_ROWS = 500

local function trim(s)
	if not s then
		return ""
	end
	return (string.gsub(tostring(s), "^%s*(.-)%s*$", "%1"))
end

local DETAIL_WIDTH = 288
local GAP = 12
local PAD = 10

function ProfessionExporter:BuildMarketTableColumns()
	local pe = self
	local function money(id, label, field, fallback)
		return {
			id = id, label = label, justifyH = "RIGHT", width = 86, sortable = true, defaultSort = "desc",
			sortValue = function(row) return row[field] or (fallback and row[fallback]) or 0 end,
			getText = function(row) return pe:FormatCopperShort(row[field] or (fallback and row[fallback])) end,
		}
	end
	local function count(id, label, field, width, optional)
		return {
			id = id, label = label, justifyH = "RIGHT", width = width, sortable = true, defaultSort = "desc", optional = optional,
			sortValue = function(row) return row[field] or 0 end,
			getText = function(row)
				local n = tonumber(row[field]) or 0
				return n > 0 and pe:FormatNumberGrouped(n) or "-"
			end,
		}
	end
	return {
		self:CreateItemColumn({
			label = "Item", defaultSort = "asc",
			getItemID = function(row) return row.itemID end,
			getName = function(row) return row.name end,
		}),
		money("price", "Lowest", "price"),
		money("marketHigh", "Highest", "marketHigh", "price"),
		count("sampleSize", "Qty", "sampleSize", 60),
		count("listingCount", "Listings", "listingCount", 60, true),
		{
			id = "seenAt", label = "Seen", justifyH = "RIGHT", width = 64, sortable = true, defaultSort = "desc", optional = true,
			sortValue = function(row) return row.seenAt or 0 end,
			getText = function(row) return pe:FormatShortTime(row.seenAt) end,
		},
	}
end

function ProfessionExporter:LayoutMarketPanel(panel)
	if not panel then
		return
	end
	local selected = self.ui.marketSelectedRow ~= nil
	panel.detailEmpty:SetShown(not selected)
	panel.detailBody:SetShown(selected)
	if panel.marketDetailGraph then
		panel.marketDetailGraph:SetWidth(DETAIL_WIDTH - PAD * 2)
	end
end

function ProfessionExporter:EnsureMarketPanel(container)
	local ui = self.ui
	if ui.marketPanel then
		return ui.marketPanel
	end
	local pe = self
	local panel = CreateFrame("Frame", nil, container)
	panel:SetAllPoints()
	ui.marketPanel = panel

	-- Toolbar: search, a hint, and when the last full scan ran.
	panel.toolbar = CreateFrame("Frame", nil, panel)
	panel.toolbar:SetPoint("TOPLEFT")
	panel.toolbar:SetPoint("TOPRIGHT")
	panel.toolbar:SetHeight(26)
	ui.marketSearchBox = self:CreateSearchBox(panel.toolbar, "Search the last scan", function()
		ProfessionExporter:RefreshMarketTab()
	end)
	ui.marketSearchBox:SetPoint("LEFT", 6, 0)
	ui.marketSearchBox:SetWidth(254)
	panel.scanBadge = self:CreateBadge(panel.toolbar)
	panel.scanBadge:SetPoint("RIGHT")
	panel.hint = self:CreateText(panel.toolbar, "GameFontHighlightSmall", "textMuted")
	panel.hint:SetPoint("LEFT", ui.marketSearchBox, "RIGHT", 14, 0)
	panel.hint:SetPoint("RIGHT", panel.scanBadge, "LEFT", -12, 0)
	panel.hint:SetText("Works away from the auction house")

	-- Detail pane, always shown: empty state until a row is picked.
	panel.detailCard = self:CreateInset(panel)
	panel.detailCard:SetPoint("TOPRIGHT", panel.toolbar, "BOTTOMRIGHT", 0, -GAP)
	panel.detailCard:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
	panel.detailCard:SetWidth(DETAIL_WIDTH)
	panel.detailEmpty = self:CreateEmptyState(panel.detailCard)
	panel.detailEmpty:SetAllPoints()
	panel.detailEmpty:SetMessage("Select an item", "Click a row to see its prices and hourly history from past scans.")

	panel.detailBody = CreateFrame("Frame", nil, panel.detailCard)
	panel.detailBody:SetPoint("TOPLEFT", PAD, -PAD)
	panel.detailBody:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	panel.detailHeader = self:CreateDetailHeader(panel.detailBody)
	panel.detailHeader:SetPoint("TOPLEFT")
	panel.detailHeader:SetPoint("TOPRIGHT")
	panel.detailFacts = self:CreateKeyValueList(panel.detailBody)
	panel.detailFacts:SetPoint("TOPLEFT", panel.detailHeader, "BOTTOMLEFT", 0, -10)
	panel.detailFacts:SetPoint("TOPRIGHT", panel.detailHeader, "BOTTOMRIGHT", 0, -10)
	panel.graphHeading = self:CreateHeading(panel.detailBody, "Hourly price")
	panel.graphHeading:SetPoint("TOPLEFT", panel.detailFacts, "BOTTOMLEFT", 0, -10)
	panel.graphHeading:SetPoint("TOPRIGHT", panel.detailFacts, "BOTTOMRIGHT", 0, -10)
	panel.marketDetailGraph = self:CreateTimeSeriesGraph(panel.detailBody, {
		showTitle = false,
		plotHeight = 96,
		emptyText = "No hourly history yet. Run a full scan at the auction house.",
		yFormatter = function(v) return ProfessionExporter:FormatCopperShort(v) end,
	})
	panel.marketDetailGraph:SetPoint("TOPLEFT", panel.graphHeading, "BOTTOMLEFT", 0, -6)
	panel.historyTable = self:CreateReusableTable(panel.detailBody, {
		autoFitToScroll = true,
		emptyTitle = "No history",
		emptyHint = "Each full scan adds an hour.",
	})
	panel.historyTable.frame:SetPoint("TOPLEFT", panel.marketDetailGraph, "BOTTOMLEFT", 0, -8)
	panel.historyTable.frame:SetPoint("BOTTOMRIGHT", panel.detailBody, "BOTTOMRIGHT", 0, 0)
	panel.historyTable:SetColumns({
		{ id = "at", label = "Hour", width = 80, flex = 1, minWidth = 60, getText = function(p) return pe:FormatScanTimestamp(p.at) end },
		{ id = "last", label = "Price", width = 78, justifyH = "RIGHT", getText = function(p) return pe:FormatCopperShort(p.last or p.avg or p.min) end },
		{ id = "qty", label = "Qty", width = 52, justifyH = "RIGHT", getText = function(p) return pe:FormatNumberGrouped(p.qty or 0) end },
	})

	-- Table fills the rest.
	local sortKey = self:GetSetting("market.sortColumn", "name")
	local sortAsc = self:GetSetting("market.sortAsc", true)
	ui.marketTable = self:CreateReusableTable(panel, {
		footer = true,
		emptyTitle = "No prices yet",
		emptyHint = "Open the auction house and run a full scan.",
		isRowSelected = function(rowData)
			return rowData and rowData.storageKey ~= nil and rowData.storageKey == ProfessionExporter.ui.marketSelectedStorageKey
		end,
		maxRows = MAX_ROWS,
		viewportVirtualize = true,
		virtualOverscan = 8,
		autoFitToScroll = true,
		sortKey = sortKey,
		sortAsc = sortAsc ~= false,
		onSortChanged = function(key, asc)
			ProfessionExporter:SetSetting("market.sortColumn", key)
			ProfessionExporter:SetSetting("market.sortAsc", asc)
		end,
		onRowEnter = function(rowFrame, rowData)
			ProfessionExporter:ShowItemRowTooltip(rowFrame, rowData and rowData.itemID, {
				{ "Lowest", ProfessionExporter:FormatCopperShort(rowData and rowData.price) },
				{ "Highest", ProfessionExporter:FormatCopperShort(rowData and (rowData.marketHigh or rowData.price)) },
				{ "Quantity", ProfessionExporter:FormatNumberGrouped(rowData and rowData.sampleSize or 0) },
			}, "Click for history")
		end,
		onRowLeave = function()
			GameTooltip:Hide()
		end,
		onRowClick = function(rowFrame, rowData, button, tableWidget)
			if ProfessionExporter:HandleItemRowModifiedClick(rowData and rowData.itemID) then
				return
			end
			ui.marketSelectedStorageKey = rowData and rowData.storageKey
			ui.marketSelectedRow = rowData
			tableWidget:SetSelectedRow(rowData)
			ProfessionExporter:RenderMarketDetails(rowData)
			ProfessionExporter:LayoutMarketPanel(panel)
		end,
	})
	ui.marketTable.frame:SetPoint("TOPLEFT", panel.toolbar, "BOTTOMLEFT", 0, -GAP)
	ui.marketTable.frame:SetPoint("BOTTOMRIGHT", panel.detailCard, "BOTTOMLEFT", -GAP, 0)
	panel.marketTable = ui.marketTable
	ui.marketTable:SetColumns(self:BuildMarketTableColumns())

	panel:SetScript("OnSizeChanged", function()
		ProfessionExporter:LayoutMarketPanel(panel)
	end)
	self:LayoutMarketPanel(panel)
	return panel
end

function ProfessionExporter:CollectMarketBrowserRows()
	local auction = self:InitAuctionDB()
	if not auction then
		return {}
	end
	local ui = self.ui or {}
	local FL = self.ForeverLogic
	if not FL or not FL.BuildMarketBrowserRows then
		return {}
	end
	local query = trim(ui.marketSearchBox and ui.marketSearchBox:GetText() or "")
	local sortKey = (ui.marketTable and ui.marketTable.sortKey) or self:GetSetting("market.sortColumn", "name")
	local sortAsc = true
	if ui.marketTable and ui.marketTable.sortAsc ~= nil then
		sortAsc = ui.marketTable.sortAsc
	else
		sortAsc = self:GetSetting("market.sortAsc", true) ~= false
	end
	return FL.BuildMarketBrowserRows(auction.snapshot.commodities, auction.snapshot.items, {
		query = query,
		sortKey = sortKey,
		sortAsc = sortAsc,
		resolveName = function(itemID)
			return ProfessionExporter:GetItemDisplayName(itemID)
		end,
	})
end

function ProfessionExporter:RenderMarketDetails(rowData)
	local ui = self.ui
	local panel = ui and ui.marketPanel
	if not panel then
		return
	end
	if not rowData then
		self:LayoutMarketPanel(panel)
		return
	end

	panel.detailHeader:SetItem(rowData.itemID, rowData.name or self:GetItemDisplayName(rowData.itemID),
		string.format("Item %s · %s", tostring(rowData.itemID or "?"), rowData.scope == "commodity" and "commodity" or "item"))
	panel.detailFacts:SetRows({
		{ "Lowest", self:FormatCopperFull(rowData.price) },
		{ "Highest", self:FormatCopperFull(rowData.marketHigh or rowData.price) },
		{ "Quantity", self:FormatNumberGrouped(rowData.sampleSize or 0) },
		{ "Listings", (tonumber(rowData.listingCount) or 0) > 0 and self:FormatNumberGrouped(rowData.listingCount) or "-" },
		{ "Seen", self:FormatScanTimestamp(rowData.seenAt) },
	})

	local auction = self:InitAuctionDB()
	local hourly = auction and auction.history and auction.history.hourly and auction.history.hourly[rowData.storageKey]
	local FL = self.ForeverLogic
	local points = FL and FL.BuildMarketHistorySeries and FL.BuildMarketHistorySeries(hourly) or {}
	local primary, secondary, quantity, recent = {}, {}, {}, {}
	for i = math.max(1, #points - 47), #points do
		local p = points[i]
		primary[#primary + 1] = { at = p.at, value = p.last or p.avg or p.min or 0 }
		if p.min then
			secondary[#secondary + 1] = { at = p.at, value = p.min }
		end
		quantity[#quantity + 1] = { at = p.at, value = p.qty or 0 }
		table.insert(recent, 1, p)
	end
	for index, p in ipairs(recent) do
		p._rowIdentity = index
	end
	panel.historyTable:SetRows(recent)
	panel.historyTable:Refresh()

	local graph = panel.marketDetailGraph
	graph:SetSeries(primary)
	graph:SetSecondarySeries(secondary)
	graph:SetQuantitySeries(quantity)
	graph:SetTooltipBuilder(function(tip, hit)
		local pt = hit and hit.pt
		if pt then
			tip:AddLine(ProfessionExporter:FormatScanTimestamp(pt.at), 1, 1, 1)
			tip:AddLine(ProfessionExporter:FormatCopperFull(pt.value))
		end
	end)
	graph:Refresh()
	self:LayoutMarketPanel(panel)
end

function ProfessionExporter:RefreshMarketTab()
	self:InitDB()
	local ui = self.ui
	if not ui or not ui.marketPanel then
		return
	end
	if ui.activeMainTab and ui.activeMainTab ~= "market" then
		return
	end

	local rows = self:CollectMarketBrowserRows()
	ui.marketWorkingRows = rows
	if ui.marketTable then
		ui.marketTable:SetRows(rows)
	end

	local state = (type(self.GetState) == "function" and self:GetState()) or {}
	local lastDump = tonumber(state.auctionLastFullDumpAt)
	local panel = ui.marketPanel
	if lastDump and lastDump > 0 then
		panel.scanBadge:SetBadge("Full scan " .. self:FormatScanTimestamp(lastDump), "accent")
	else
		panel.scanBadge:SetBadge("No full scan yet", "warning")
	end
	ui.marketTable:Refresh()
	ui.marketTable:SetFooterText(string.format("%s items", self:FormatNumberGrouped(#rows)), "Search to narrow the list")

	local selectedKey = ui.marketSelectedStorageKey
	local selected = nil
	if selectedKey then
		for _, row in ipairs(rows) do
			if row.storageKey == selectedKey then
				selected = row
				break
			end
		end
	end
	ui.marketSelectedRow = selected
	self:RenderMarketDetails(selected)
	self:LayoutMarketPanel(panel)
end
