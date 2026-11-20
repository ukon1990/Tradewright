local addonName, ProfessionExporter = ...

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
			getName = function(row) return pe:GetItemDisplayName(row.itemID) end,
			sortValue = function(row) return row.name or "" end,
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
end

-- One auction listing's history: optional header, key facts, hourly price graph and the recent hours.
-- Used by the Market tab detail card and the item details window. `opts.noHeader` hides the header.
function ProfessionExporter:CreateMarketHistoryView(parent, opts)
	opts = opts or {}
	local pe = self
	local view = CreateFrame("Frame", nil, parent)
	local top = view
	if not opts.noHeader then
		view.header = self:CreateDetailHeader(view)
		view.header:SetPoint("TOPLEFT")
		view.header:SetPoint("TOPRIGHT")
		top = view.header
	end
	view.facts = self:CreateKeyValueList(view)
	view.facts:SetPoint("TOPLEFT", top, top == view and "TOPLEFT" or "BOTTOMLEFT", 0, top == view and 0 or -10)
	view.facts:SetPoint("TOPRIGHT", top, top == view and "TOPRIGHT" or "BOTTOMRIGHT", 0, top == view and 0 or -10)
	local graphHeading = self:CreateHeading(view, "Hourly price")
	graphHeading:SetPoint("TOPLEFT", view.facts, "BOTTOMLEFT", 0, -10)
	graphHeading:SetPoint("TOPRIGHT", view.facts, "BOTTOMRIGHT", 0, -10)
	view.graph = self:CreateTimeSeriesGraph(view, {
		showTitle = false,
		plotHeight = opts.plotHeight or 96,
		emptyText = "No hourly history yet. Run a full scan at the auction house.",
		yFormatter = function(v) return pe:FormatCopperShort(v) end,
	})
	view.graph:SetPoint("TOPLEFT", graphHeading, "BOTTOMLEFT", 0, -6)
	view.historyTable = self:CreateReusableTable(view, {
		autoFitToScroll = true,
		emptyTitle = "No history",
		emptyHint = "Each full scan adds an hour.",
	})
	view.historyTable.frame:SetPoint("TOPLEFT", view.graph, "BOTTOMLEFT", 0, -8)
	view.historyTable.frame:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, 0)
	view.historyTable:SetColumns({
		{ id = "at", label = "Hour", width = 80, flex = 1, minWidth = 60, getText = function(p) return pe:FormatScanTimestamp(p.at) end },
		{ id = "last", label = "Price", width = 78, justifyH = "RIGHT", getText = function(p) return pe:FormatCopperShort(p.last or p.avg or p.min) end },
		{ id = "qty", label = "Qty", width = 52, justifyH = "RIGHT", getText = function(p) return pe:FormatNumberGrouped(p.qty or 0) end },
	})
	view:SetScript("OnSizeChanged", function(self, width)
		self.graph:SetWidth(width)
	end)

	-- rowData: a Market browser row (storageKey, itemID, price, marketHigh, sampleSize, listingCount, seenAt).
	function view:ShowRow(rowData)
		if self.header then
			self.header:SetItem(rowData.itemID, rowData.name or pe:GetItemDisplayName(rowData.itemID),
				string.format("Item %s · %s", tostring(rowData.itemID or "?"), rowData.scope == "commodity" and "commodity" or "item"))
		end
		self.facts:SetRows({
			{ "Lowest", pe:FormatCopperFull(rowData.price) },
			{ "Highest", pe:FormatCopperFull(rowData.marketHigh or rowData.price) },
			{ "Quantity", pe:FormatNumberGrouped(rowData.sampleSize or 0) },
			{ "Listings", (tonumber(rowData.listingCount) or 0) > 0 and pe:FormatNumberGrouped(rowData.listingCount) or "-" },
			{ "Seen", pe:FormatScanTimestamp(rowData.seenAt) },
		})

		local auction = pe:InitAuctionDB()
		local hourly = auction and auction.history and auction.history.hourly and auction.history.hourly[rowData.storageKey]
		local FL = pe.ForeverLogic
		local points = FL and FL.BuildMarketHistorySeries and FL.BuildMarketHistorySeries(hourly) or {}
		local primary, secondary, quantity, recent = {}, {}, {}, {}
		for i = math.max(1, #points - 47), #points do
			local p = points[i]
			primary[#primary + 1] = { at = p.at, value = p.last or p.avg or p.min or 0, meta = { min = p.min, max = p.max } }
			if p.min then
				secondary[#secondary + 1] = { at = p.at, value = p.min }
			end
			quantity[#quantity + 1] = { at = p.at, value = p.qty or 0 }
			table.insert(recent, 1, p)
		end
		for index, p in ipairs(recent) do
			p._rowIdentity = index
		end
		self.historyTable:SetRows(recent)
		self.historyTable:Refresh()

		self.graph:SetSeries(primary)
		self.graph:SetSecondarySeries(secondary)
		self.graph:SetQuantitySeries(quantity)
		self.graph:SetSeriesLabels("Price", "Lowest", "Listed", nil)
		self.graph:SetTooltipBuilder(nil)
		self.graph:Refresh()
	end
	return view
end

-- The Market browser row for one storage key, or nil when nothing is saved under it.
function ProfessionExporter:GetMarketRowForStorageKey(storageKey)
	local auction = self:InitAuctionDB()
	if not (auction and storageKey) then
		return nil
	end
	local commodity = auction.snapshot.commodities[storageKey]
	local item = auction.snapshot.items[storageKey]
	if not (commodity or item) then
		return nil
	end
	return self.ForeverLogic.BuildMarketBrowserRows(
		commodity and { [storageKey] = commodity } or {},
		item and { [storageKey] = item } or {},
		{ resolveName = function(itemID) return ProfessionExporter:GetItemDisplayName(itemID, true) end })[1]
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

	local filters = self:GetMarketFilters()
	local function changed()
		ProfessionExporter:SaveMarketFilters()
		ProfessionExporter:RefreshMarketTab()
	end
	local function setFilter(key)
		return function(selection)
			filters[key] = selection
		end
	end

	-- Row 1: search, item class, subclass, quality.
	panel.toolbar = CreateFrame("Frame", nil, panel)
	panel.toolbar:SetPoint("TOPLEFT")
	panel.toolbar:SetPoint("TOPRIGHT")
	panel.toolbar:SetHeight(26)
	panel.qualityDropdown = self:CreateMultiSelectDropdown(panel.toolbar, {
		width = 128, allLabel = "Any quality",
		getOptions = function() return pe:GetQualityFilterOptions() end,
		getSelection = function() return filters.qualities end,
		setSelection = setFilter("qualities"), onChanged = changed,
	})
	panel.qualityDropdown:SetPoint("RIGHT")
	panel.subclassDropdown = self:CreateMultiSelectDropdown(panel.toolbar, {
		width = 150, allLabel = "All subclasses",
		getSelection = function() return filters.subclasses end,
		setSelection = setFilter("subclasses"), onChanged = changed,
	})
	panel.classDropdown = self:CreateMultiSelectDropdown(panel.toolbar, {
		width = 150, allLabel = "All classes",
		getSelection = function() return filters.classes end,
		setSelection = function(selection)
			filters.classes = selection
			filters.subclasses = {}
		end,
		onChanged = changed,
	})
	self:ChainLeft({ panel.qualityDropdown, panel.subclassDropdown, panel.classDropdown }, 8)
	ui.marketSearchBox = self:CreateSearchBox(panel.toolbar, "Search the last scan", function()
		ProfessionExporter:RefreshMarketTab()
	end)
	ui.marketSearchBox:SetPoint("LEFT", 6, 0)
	ui.marketSearchBox:SetPoint("RIGHT", panel.classDropdown, "LEFT", -14, 0)

	-- Row 2: owned only, price range in gold, reset; when the last full scan ran on the right.
	panel.filterRow = CreateFrame("Frame", nil, panel)
	panel.filterRow:SetPoint("TOPLEFT", panel.toolbar, "BOTTOMLEFT", 0, -8)
	panel.filterRow:SetPoint("TOPRIGHT", panel.toolbar, "BOTTOMRIGHT", 0, -8)
	panel.filterRow:SetHeight(26)
	panel.ownedOnly = self:CreateCheckbox(panel.filterRow, "Only items I own", function(checked)
		filters.ownedOnly = checked
		changed()
	end)
	panel.ownedOnly:SetPoint("LEFT")
	panel.priceLabel = self:CreateText(panel.filterRow, "GameFontHighlightSmall", "textMuted")
	panel.priceLabel:SetPoint("LEFT", panel.ownedOnly, "RIGHT", 16, 0)
	panel.priceLabel:SetText("Lowest price")
	local function priceBox(placeholder, key)
		local box = pe:CreateSearchBox(panel.filterRow, placeholder, function(text)
			filters[key] = tonumber(text)
			changed()
		end, 0.4)
		box:SetNumeric(true)
		box:SetMaxLetters(7)
		box:SetWidth(64)
		box:SetJustifyH("RIGHT")
		return box
	end
	panel.minGold = priceBox("Min g", "minGold")
	panel.minGold:SetPoint("LEFT", panel.priceLabel, "RIGHT", 12, 0)
	panel.priceDash = self:CreateText(panel.filterRow, "GameFontHighlightSmall", "textMuted")
	panel.priceDash:SetPoint("LEFT", panel.minGold, "RIGHT", 10, 0)
	panel.priceDash:SetText("to")
	panel.maxGold = priceBox("Max g", "maxGold")
	panel.maxGold:SetPoint("LEFT", panel.priceDash, "RIGHT", 12, 0)
	panel.resetFilters = self:CreateButton(panel.filterRow, "Reset filters", function()
		pe:ResetMarketFilters()
	end, { small = true })
	panel.resetFilters:SetPoint("LEFT", panel.maxGold, "RIGHT", 14, 0)
	panel.scanBadge = self:CreateBadge(panel.filterRow)
	panel.scanBadge:SetPoint("RIGHT")

	-- Detail pane, always shown: empty state until a row is picked.
	panel.detailCard = self:CreateInset(panel)
	panel.detailCard:SetPoint("TOPRIGHT", panel.filterRow, "BOTTOMRIGHT", 0, -GAP)
	panel.detailCard:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
	panel.detailCard:SetWidth(DETAIL_WIDTH)
	panel.detailEmpty = self:CreateEmptyState(panel.detailCard)
	panel.detailEmpty:SetAllPoints()
	panel.detailEmpty:SetMessage("Select an item", "Click a row to see its prices and hourly history from past scans.")

	panel.detailBody = self:CreateMarketHistoryView(panel.detailCard)
	panel.detailBody:SetPoint("TOPLEFT", PAD, -PAD)
	panel.detailBody:SetPoint("BOTTOMRIGHT", -PAD, PAD)

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
				{ "Highest listing", ProfessionExporter:FormatCopperShort(rowData and (rowData.marketHigh or rowData.price)) },
			}, "Click for history · Shift-click to link")
		end,
		onRowLeave = function()
			GameTooltip:Hide()
		end,
		onRowClick = function(_, rowData, _, tableWidget)
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
	ui.marketTable.frame:SetPoint("TOPLEFT", panel.filterRow, "BOTTOMLEFT", 0, -GAP)
	ui.marketTable.frame:SetPoint("BOTTOMRIGHT", panel.detailCard, "BOTTOMLEFT", -GAP, 0)
	panel.marketTable = ui.marketTable
	ui.marketTable:SetColumns(self:BuildMarketTableColumns())

	panel:SetScript("OnSizeChanged", function()
		ProfessionExporter:LayoutMarketPanel(panel)
	end)
	self:LayoutMarketPanel(panel)
	return panel
end

-- Market filter state, kept in settings so it survives a reload.
function ProfessionExporter:GetMarketFilters()
	local ui = self.ui
	if not ui.marketFilters then
		local saved = self:GetSetting("market.filters", {}) or {}
		ui.marketFilters = {
			classes = saved.classes or {},
			subclasses = saved.subclasses or {},
			qualities = saved.qualities or {},
			ownedOnly = saved.ownedOnly == true,
			minGold = tonumber(saved.minGold),
			maxGold = tonumber(saved.maxGold),
		}
	end
	return ui.marketFilters
end

function ProfessionExporter:SaveMarketFilters()
	self:SetSetting("market.filters", self:GetMarketFilters())
end

function ProfessionExporter:ResetMarketFilters()
	local panel = self.ui.marketPanel
	self.ui.marketFilters = { classes = {}, subclasses = {}, qualities = {}, ownedOnly = false }
	self:SaveMarketFilters()
	if panel then
		panel.minGold:SetText("")
		panel.maxGold:SetText("")
		panel.minGold:UpdatePlaceholder()
		panel.maxGold:UpdatePlaceholder()
	end
	self:RefreshMarketTab()
end

-- Item IDs any stored character has in bags, bank or warband bank.
function ProfessionExporter:GetOwnedItemSet()
	local owned = {}
	for _, row in ipairs(self:BuildInventoryRowsAggregatedByItem(self.db, {}, "") or {}) do
		if (tonumber(row.total) or 0) > 0 and row.itemID then
			owned[tonumber(row.itemID)] = true
		end
	end
	return owned
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
	local sortAsc
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
			return ProfessionExporter:GetItemDisplayName(itemID, true)
		end,
	})
end

-- Switches to the Market tab with this listing selected (shown when the current filters include it).
function ProfessionExporter:OpenMarketItem(storageKey)
	self.ui.marketSelectedStorageKey = storageKey
	self:ShowDashboardTab("market")
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

	panel.detailBody:ShowRow(rowData)
	self:LayoutMarketPanel(panel)
end

local MODAL_W, MODAL_H = 760, 540

local function createItemDetailsWindow(pe)
	local theme = pe:GetTheme()
	local header = theme.size.header
	local frame = CreateFrame("Frame", addonName .. "ItemDetails", UIParent, "BackdropTemplate")
	frame:SetSize(MODAL_W, MODAL_H)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	pe:StyleWindow(frame)
	tinsert(UISpecialFrames, frame:GetName())

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:ClearAllPoints()
	close:SetPoint("RIGHT", frame, "TOPRIGHT", -6, -(header / 2))
	pe:SkinCloseButton(close)
	local title = pe:CreateText(frame, "GameFontNormalLarge", "gold")
	title:SetPoint("LEFT", frame, "TOPLEFT", GAP, -(header / 2) - 1)
	title:SetText("Item details")

	-- Left: the item (owned, craft cost, chart, recipes). Right: its auction listing history.
	frame.itemPane = pe:CreateItemDetailPane(frame, { metricSettingKey = "inventory.detailsGraphMetric" })
	frame.itemPane:SetPoint("TOPLEFT", GAP, -(header + GAP))
	frame.itemPane:SetPoint("BOTTOMLEFT", GAP, GAP)
	frame.marketCard = pe:CreateInset(frame)
	frame.marketCard:SetPoint("TOPLEFT", frame.itemPane, "TOPRIGHT", GAP, 0)
	frame.marketCard:SetPoint("BOTTOMRIGHT", -GAP, GAP)
	local heading = pe:CreateHeading(frame.marketCard, "Auction house")
	heading:SetPoint("TOPLEFT", PAD, -PAD)
	heading:SetPoint("TOPRIGHT", -PAD, -PAD)
	frame.market = pe:CreateMarketHistoryView(frame.marketCard, { noHeader = true, plotHeight = 140 })
	frame.market:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -8)
	frame.market:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	frame.marketEmpty = pe:CreateEmptyState(frame.marketCard)
	frame.marketEmpty:SetAllPoints()
	frame.marketEmpty:SetMessage("No auction data", "Scan the auction house to see this item's prices and hourly history.")
	frame:Hide()
	return frame
end

-- Item details window: everything the Inventory and Market detail panes show, for one item.
-- storageKey picks the auction listing; without one, the item's full-scan listing is used.
function ProfessionExporter:ShowItemDetailsWindow(itemID, storageKey)
	itemID = tonumber(itemID)
	if not itemID then
		return
	end
	local ui = self.ui
	ui.itemDetailsWindow = ui.itemDetailsWindow or createItemDetailsWindow(self)
	local frame = ui.itemDetailsWindow
	frame:Show()
	frame:Raise()
	frame.itemPane:ShowItem(itemID, { selectedCharacters = {}, rangeKey = self:GetInventoryMetricRange() })
	local row = self:GetMarketRowForStorageKey(storageKey)
		or (self.BuildAuctionStorageKey and self:GetMarketRowForStorageKey(self:BuildAuctionStorageKey(itemID, "item", tostring(itemID))))
	frame.market:SetShown(row ~= nil)
	frame.marketEmpty:SetShown(row == nil)
	if row then
		frame.market:ShowRow(row)
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

	local allRows = self:CollectMarketBrowserRows()
	local filters = self:GetMarketFilters()
	local panel = ui.marketPanel
	local itemIDs = {}
	for index, row in ipairs(allRows) do
		itemIDs[index] = row.itemID
	end
	local classOptions = self:BuildItemClassOptions(itemIDs, "classLabel")
	filters.classes = self:NormalizeFilterSelection(filters.classes, classOptions)
	local subclassOptions = self:BuildItemClassOptions(itemIDs, "subclassLabel", filters.classes)
	filters.subclasses = self:NormalizeFilterSelection(filters.subclasses, subclassOptions)
	panel.classDropdown:SetOptions(classOptions)
	panel.subclassDropdown:SetOptions(subclassOptions)
	panel.qualityDropdown:RefreshText()
	panel.ownedOnly.check:SetChecked(filters.ownedOnly)
	if filters.minGold and panel.minGold:GetText() == "" and not panel.minGold:HasFocus() then
		panel.minGold:SetText(tostring(filters.minGold))
	end
	if filters.maxGold and panel.maxGold:GetText() == "" and not panel.maxGold:HasFocus() then
		panel.maxGold:SetText(tostring(filters.maxGold))
	end
	local rows = self.ForeverLogic.FilterMarketRows(allRows, {
		classes = filters.classes,
		subclasses = filters.subclasses,
		qualities = filters.qualities,
		ownedOnly = filters.ownedOnly,
		owned = filters.ownedOnly and self:GetOwnedItemSet() or nil,
		minPrice = filters.minGold and filters.minGold * 10000 or nil,
		maxPrice = filters.maxGold and filters.maxGold * 10000 or nil,
	}, function(itemID)
		return ProfessionExporter:GetItemFilterInfo(itemID)
	end)
	ui.marketWorkingRows = rows
	if ui.marketTable then
		ui.marketTable:SetRows(rows)
	end

	local lastDump = self.GetLastFullAuctionScanAt and self:GetLastFullAuctionScanAt()
	if lastDump then
		panel.scanBadge:SetBadge("Full scan " .. self:FormatScanTimestamp(lastDump), "accent")
	else
		panel.scanBadge:SetBadge("No full scan yet", "warning")
	end
	ui.marketTable:Refresh()
	if #allRows > 0 then
		ui.marketTable:SetEmptyText("Nothing matches", "Change the search or press Reset filters.")
	else
		ui.marketTable:SetEmptyText("No prices yet", "Open the auction house and run a full scan.")
	end
	ui.marketTable:SetFooterText(string.format("%s of %s items", self:FormatNumberGrouped(#rows), self:FormatNumberGrouped(#allRows)),
		"Works away from the auction house")

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
