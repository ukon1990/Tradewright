local addonName, ProfessionExporter = ...

local ROW_H = 20
local MAX_ROWS = 500

local function trim(s)
	if not s then
		return ""
	end
	return (string.gsub(tostring(s), "^%s*(.-)%s*$", "%1"))
end

local function formatTimestamp(ts)
	ts = tonumber(ts)
	if not ts or ts <= 0 then
		return "-"
	end
	return date("%Y-%m-%d %H:%M", ts)
end

function ProfessionExporter:BuildMarketTableColumns()
	local pe = self
	return {
		{
			id = "name",
			label = "Item",
			width = 220,
			minWidth = 120,
			flex = 3,
			sortable = true,
			defaultSort = "asc",
			sortValue = function(row)
				return row.name or ""
			end,
			getText = function(row)
				return row.name or ("#" .. tostring(row.itemID or "?"))
			end,
		},
		{
			id = "price",
			label = "Min",
			width = 110,
			minWidth = 72,
			flex = 0,
			sortable = true,
			defaultSort = "desc",
			sortValue = function(row)
				return row.price or 0
			end,
			getText = function(row)
				return pe:FormatCopperShort(row.price)
			end,
		},
		{
			id = "marketHigh",
			label = "Max",
			width = 110,
			minWidth = 72,
			flex = 0,
			sortable = true,
			defaultSort = "desc",
			sortValue = function(row)
				return row.marketHigh or row.price or 0
			end,
			getText = function(row)
				return pe:FormatCopperShort(row.marketHigh or row.price)
			end,
		},
		{
			id = "sampleSize",
			label = "Qty",
			width = 64,
			minWidth = 48,
			flex = 0,
			sortable = true,
			defaultSort = "desc",
			sortValue = function(row)
				return row.sampleSize or 0
			end,
			getText = function(row)
				return pe:FormatNumberGrouped(row.sampleSize or 0)
			end,
		},
		{
			id = "listingCount",
			label = "Listings",
			width = 72,
			minWidth = 56,
			flex = 0,
			sortable = true,
			defaultSort = "desc",
			sortValue = function(row)
				return row.listingCount or 0
			end,
			getText = function(row)
				local n = tonumber(row.listingCount) or 0
				if n <= 0 then
					return "-"
				end
				return pe:FormatNumberGrouped(n)
			end,
		},
		{
			id = "seenAt",
			label = "Seen",
			width = 120,
			minWidth = 90,
			flex = 0,
			sortable = true,
			defaultSort = "desc",
			sortValue = function(row)
				return row.seenAt or 0
			end,
			getText = function(row)
				return formatTimestamp(row.seenAt)
			end,
		},
	}
end

function ProfessionExporter:LayoutMarketPanel(panel)
	if not panel then
		return
	end
	local width = math.max(840, panel:GetWidth() - 20)
	local detailsOpen = self:GetSetting("market.detailsOpen", true) ~= false
	local detailsWidth = detailsOpen and math.max(260, math.min(360, math.floor(width * 0.34))) or 0
	local gap = 10
	local tableWidth = width - detailsWidth - (detailsOpen and gap or 0)

	panel.headerCard:ClearAllPoints()
	panel.headerCard:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
	panel.headerCard:SetSize(width, 72)
	panel.headerTitle:SetWidth(width - 40)
	panel.headerSubtitle:SetWidth(width - 40)

	panel.filterCard:ClearAllPoints()
	panel.filterCard:SetPoint("TOPLEFT", panel.headerCard, "BOTTOMLEFT", 0, -8)
	panel.filterCard:SetSize(width, 58)

	panel.tableCard:ClearAllPoints()
	panel.tableCard:SetPoint("TOPLEFT", panel.filterCard, "BOTTOMLEFT", 0, -8)
	panel.tableCard:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
	panel.tableCard:SetWidth(tableWidth)
	if panel.tableTitle then
		panel.tableTitle:SetWidth(tableWidth - 24)
	end

	if panel.marketTable and panel.marketTable.frame then
		panel.marketTable.frame:ClearAllPoints()
		panel.marketTable.frame:SetPoint("TOPLEFT", panel.tableCard, "TOPLEFT", 10, -34)
		panel.marketTable.frame:SetPoint("BOTTOMRIGHT", panel.tableCard, "BOTTOMRIGHT", -10, 10)
		if panel.marketTable.Refresh then
			panel.marketTable:Refresh()
		end
	end

	panel.detailCard:ClearAllPoints()
	if detailsOpen then
		panel.detailCard:Show()
		panel.detailCard:SetPoint("TOPLEFT", panel.tableCard, "TOPRIGHT", gap, 0)
		panel.detailCard:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
		panel.detailTitle:SetWidth(detailsWidth - 44)
		panel.detailMeta:SetWidth(detailsWidth - 28)
		if panel.detailGraphBlock then
			panel.detailGraphBlock:SetWidth(detailsWidth - 28)
			if panel.marketDetailGraph then
				panel.marketDetailGraph:SetWidth(detailsWidth - 36)
			end
		end
		panel.detailBody:SetWidth(detailsWidth - 44)
	else
		panel.detailCard:Hide()
	end
end

function ProfessionExporter:EnsureMarketPanel(container)
	local ui = self.ui
	if ui.marketPanel then
		return ui.marketPanel
	end

	local panel = CreateFrame("Frame", nil, container)
	panel:SetAllPoints()
	ui.marketPanel = panel

	panel.headerCard = self:CreateCard(panel, 860, 72, "surface2")
	panel.headerTitle = self:CreateSectionTitle(panel.headerCard, "Market")
	panel.headerTitle:SetPoint("TOPLEFT", 12, -10)
	panel.headerSubtitle = self:CreateMutedText(panel.headerCard, 800)
	panel.headerSubtitle:SetPoint("TOPLEFT", panel.headerTitle, "BOTTOMLEFT", 0, -6)
	panel.headerSubtitle:SetText("Browse last AH snapshot and item history without visiting the auction house.")

	panel.filterCard = self:CreateCard(panel, 860, 58, "surface2")
	local searchLabel = panel.filterCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	searchLabel:SetPoint("TOPLEFT", 12, -8)
	searchLabel:SetText("Search")
	ui.marketSearchBox = CreateFrame("EditBox", addonName .. "MarketSearch", panel.filterCard, "InputBoxTemplate")
	ui.marketSearchBox:SetSize(240, 22)
	ui.marketSearchBox:SetPoint("TOPLEFT", searchLabel, "BOTTOMLEFT", -6, -4)
	ui.marketSearchBox:SetAutoFocus(false)
	ui.marketSearchBox:SetMaxLetters(64)
	ui.marketSearchBox:SetScript("OnEnterPressed", function(box)
		box:ClearFocus()
		ProfessionExporter:RefreshMarketTab()
	end)
	ui.marketSearchBox:SetScript("OnTextChanged", function()
		ProfessionExporter:RefreshMarketTab()
	end)

	panel.clearButton = CreateFrame("Button", nil, panel.filterCard, "UIPanelButtonTemplate")
	panel.clearButton:SetSize(70, 22)
	panel.clearButton:SetPoint("LEFT", ui.marketSearchBox, "RIGHT", 10, 0)
	panel.clearButton:SetText("Clear")
	panel.clearButton:SetScript("OnClick", function()
		ui.marketSearchBox:SetText("")
		ProfessionExporter:RefreshMarketTab()
	end)

	panel.countLabel = self:CreateMutedText(panel.filterCard, 280)
	panel.countLabel:SetPoint("LEFT", panel.clearButton, "RIGHT", 14, 0)

	panel.tableCard = self:CreateCard(panel, 540, 400, "surface2")
	panel.tableTitle = panel.tableCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	panel.tableTitle:SetPoint("TOPLEFT", 12, -10)
	panel.tableTitle:SetText("Cached auction snapshot")
	panel.detailCard = self:CreateCard(panel, 320, 400, "surface2")
	panel.detailTitle = self:CreateSectionTitle(panel.detailCard, "Select an item")
	panel.detailTitle:SetPoint("TOPLEFT", 12, -12)
	panel.detailCloseButton = CreateFrame("Button", nil, panel.detailCard, "UIPanelCloseButton")
	panel.detailCloseButton:SetPoint("TOPRIGHT", 2, 2)
	panel.detailCloseButton:SetScript("OnClick", function()
		ProfessionExporter:SetSetting("market.detailsOpen", false)
		ProfessionExporter:LayoutMarketPanel(panel)
	end)
	panel.detailMeta = self:CreateMutedText(panel.detailCard, 280)
	panel.detailMeta:SetPoint("TOPLEFT", panel.detailTitle, "BOTTOMLEFT", 0, -6)

	panel.detailGraphBlock = CreateFrame("Frame", nil, panel.detailCard)
	panel.detailGraphBlock:SetHeight(160)
	panel.detailGraphBlock:SetPoint("TOPLEFT", panel.detailMeta, "BOTTOMLEFT", 0, -8)
	panel.detailGraphBlock:SetPoint("TOPRIGHT", panel.detailCard, "TOPRIGHT", -12, -8)
	panel.marketDetailGraph = self:CreateTimeSeriesGraph(panel.detailGraphBlock, {
		showTitle = true,
		plotHeight = 110,
		emptyText = "No hourly history for this item yet. Run a full AH dump.",
		yFormatter = function(v)
			return ProfessionExporter:FormatCopperShort(v)
		end,
	})
	panel.marketDetailGraph:SetPoint("TOPLEFT", panel.detailGraphBlock, "TOPLEFT", 0, 0)
	panel.marketDetailGraph:SetPoint("TOPRIGHT", panel.detailGraphBlock, "TOPRIGHT", 0, 0)
	panel.marketDetailGraph:SetTitle("Hourly price")

	panel.detailScroll = CreateFrame("ScrollFrame", addonName .. "MarketDetailsScroll", panel.detailCard, "UIPanelScrollFrameTemplate")
	panel.detailScroll:SetPoint("TOPLEFT", panel.detailGraphBlock, "BOTTOMLEFT", 0, -8)
	panel.detailScroll:SetPoint("BOTTOMRIGHT", panel.detailCard, "BOTTOMRIGHT", -28, 10)
	panel.detailContent = CreateFrame("Frame", nil, panel.detailScroll)
	panel.detailContent:SetWidth(280)
	panel.detailContent:SetHeight(200)
	panel.detailScroll:SetScrollChild(panel.detailContent)
	panel.detailBody = self:CreateMutedText(panel.detailContent, 280)
	panel.detailBody:SetPoint("TOPLEFT", 2, -4)

	local sortKey = self:GetSetting("market.sortColumn", "name")
	local sortAsc = self:GetSetting("market.sortAsc", true)
	ui.marketTable = self:CreateReusableTable(panel.tableCard, {
		rowHeight = ROW_H,
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
		onRowEnter = function(_, rowData)
			if not rowData or not rowData.itemID then
				return
			end
			GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
			if GameTooltip.SetItemByID then
				GameTooltip:SetItemByID(rowData.itemID)
			else
				GameTooltip:SetText(rowData.name or ("#" .. tostring(rowData.itemID)))
			end
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(
				string.format(
					"Min %s  |  Max %s  |  Qty %s",
					ProfessionExporter:FormatCopperShort(rowData.price),
					ProfessionExporter:FormatCopperShort(rowData.marketHigh or rowData.price),
					ProfessionExporter:FormatNumberGrouped(rowData.sampleSize or 0)
				),
				0.8,
				0.9,
				1
			)
			GameTooltip:AddLine("Click for history.", 0.75, 0.82, 0.9)
			GameTooltip:Show()
		end,
		onRowLeave = function()
			GameTooltip:Hide()
		end,
		onRowClick = function(_, rowData)
			ProfessionExporter:SetSetting("market.detailsOpen", true)
			ui.marketSelectedStorageKey = rowData and rowData.storageKey
			ui.marketSelectedRow = rowData
			ProfessionExporter:RenderMarketDetails(rowData)
			ProfessionExporter:LayoutMarketPanel(panel)
		end,
	})
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
		panel.detailTitle:SetText("Select an item")
		panel.detailMeta:SetText("Click a snapshot row to see cached prices and hourly history.")
		panel.detailBody:SetText("")
		if panel.marketDetailGraph then
			panel.marketDetailGraph:SetSeries({})
			panel.marketDetailGraph:SetSecondarySeries({})
			panel.marketDetailGraph:SetQuantitySeries({})
			if panel.marketDetailGraph.Refresh then
				panel.marketDetailGraph:Refresh()
			end
		end
		return
	end

	local name = rowData.name or self:GetItemDisplayName(rowData.itemID)
	panel.detailTitle:SetText(name)
	panel.detailMeta:SetText(string.format(
		"#%s  |  %s\nMin %s  ·  Max %s\nQty %s  ·  Listings %s\nSeen %s  ·  %s",
		tostring(rowData.itemID or "?"),
		tostring(rowData.scope or "item"),
		self:FormatCopperShort(rowData.price),
		self:FormatCopperShort(rowData.marketHigh or rowData.price),
		self:FormatNumberGrouped(rowData.sampleSize or 0),
		(tonumber(rowData.listingCount) or 0) > 0 and self:FormatNumberGrouped(rowData.listingCount) or "-",
		formatTimestamp(rowData.seenAt),
		tostring(rowData.source or "-")
	))

	local auction = self:InitAuctionDB()
	local hourly = auction and auction.history and auction.history.hourly and auction.history.hourly[rowData.storageKey]
	local FL = self.ForeverLogic
	local points = FL and FL.BuildMarketHistorySeries and FL.BuildMarketHistorySeries(hourly) or {}

	local primary, secondary, quantity = {}, {}, {}
	local lines = {}
	if #points == 0 then
		lines[#lines + 1] = "No hourly history stored for this item yet."
		lines[#lines + 1] = "Run a full AH dump while the house is open."
	else
		lines[#lines + 1] = string.format("%d hourly buckets (newest last):", #points)
		lines[#lines + 1] = ""
		local startIdx = math.max(1, #points - 47)
		for i = startIdx, #points do
			local p = points[i]
			primary[#primary + 1] = { at = p.at, value = p.last or p.avg or p.min or 0 }
			if p.min then
				secondary[#secondary + 1] = { at = p.at, value = p.min }
			end
			quantity[#quantity + 1] = { at = p.at, value = p.qty or 0 }
			lines[#lines + 1] = string.format(
				"%s  last %s  min %s  max %s  qty %s",
				formatTimestamp(p.at),
				self:FormatCopperShort(p.last),
				self:FormatCopperShort(p.min),
				self:FormatCopperShort(p.max),
				self:FormatNumberGrouped(p.qty or 0)
			)
		end
	end
	panel.detailBody:SetText(table.concat(lines, "\n"))
	panel.detailContent:SetHeight(math.max(200, #lines * 14 + 20))

	if panel.marketDetailGraph then
		panel.marketDetailGraph:SetSeries(primary)
		panel.marketDetailGraph:SetSecondarySeries(secondary)
		panel.marketDetailGraph:SetQuantitySeries(quantity)
		panel.marketDetailGraph:SetTooltipBuilder(function(tip, hit)
			local pt = hit and hit.pt
			if not pt then
				return
			end
			tip:AddLine(formatTimestamp(pt.at), 1, 1, 1)
			tip:AddLine(ProfessionExporter:FormatCopperShort(pt.value), 0.8, 0.9, 1)
		end)
		if panel.marketDetailGraph.Refresh then
			panel.marketDetailGraph:Refresh()
		end
	end
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
	if panel and panel.countLabel then
		panel.countLabel:SetText(string.format("%s cached items", self:FormatNumberGrouped(#rows)))
	end
	if panel and panel.headerSubtitle then
		if lastDump and lastDump > 0 then
			panel.headerSubtitle:SetText("Last full dump: " .. formatTimestamp(lastDump) .. " — search works offline from snapshot.")
		else
			panel.headerSubtitle:SetText("No full dump recorded yet. Open the AH and run a full dump to fill the Market.")
		end
	end

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
