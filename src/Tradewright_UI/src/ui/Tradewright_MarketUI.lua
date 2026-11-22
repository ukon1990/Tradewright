local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
local MAX_ROWS = 500

local DETAIL_WIDTH = 288
local GAP = 12
local PAD = 10

-- "12g 40s over 14 days", or why there is none yet.
local function usualPriceText(pe, rowData)
	local usual = pe.GetUsualPrice and pe:GetUsualPrice(rowData.storageKey)
	if not usual then
		return L["Needs scans on 5 days"]
	end
	return string.format(L["%s over %d days"], pe:FormatCopperFull(usual.usual), usual.days)
end

local function usualRangeText(pe, rowData)
	local usual = pe.GetUsualPrice and pe:GetUsualPrice(rowData.storageKey)
	if not usual then
		return "-"
	end
	return string.format("%s – %s", pe:FormatCopperShort(usual.low), pe:FormatCopperShort(usual.high))
end

-- Estimated units sold per day for a Market row, or nil when the scans do not say.
local function sellsPerDay(pe, rowData)
	local sells = pe.GetSellsPerDay and pe:GetSellsPerDay(rowData.storageKey)
	return sells and sells.perDay, sells and sells.confidence
end

-- "12" for a busy item, "0.4" for a slow one.
local function sellsText(perDay)
	if perDay >= 10 then
		return Tradewright:FormatNumberGrouped(math.floor(perDay + 0.5))
	end
	return string.format("%.1f", perDay)
end

local function sellsFactText(pe, rowData)
	local perDay, confidence = sellsPerDay(pe, rowData)
	if not perDay then
		return L["Needs two scans a day apart or less"]
	end
	return sellsText(perDay) .. (confidence == "few" and L[" (few sales seen)"] or "")
end

local function supplyFactText(pe, rowData)
	local days = pe.MarketSignals.DaysOfSupply(rowData.sampleSize, (sellsPerDay(pe, rowData)))
	if not days then
		return "-"
	end
	return days < 1 and L["under a day"] or string.format(L["about %d days"], math.floor(days + 0.5))
end

local function sellsColumn(pe)
	return {
		id = "sellsPerDay", label = L["Sales a day"], justifyH = "RIGHT", width = 70, sortable = true, defaultSort = "desc",
		sortValue = function(row) return sellsPerDay(pe, row) or 0 end,
		getText = function(row)
			local perDay = sellsPerDay(pe, row)
			return perDay and sellsText(perDay) or "-"
		end,
	}
end

-- The Market table's "Usual" and "Vs usual" columns; "-" until an item has 5 days of scans.
local function usualColumns(pe)
	local function usualOf(row)
		local usual = pe.GetUsualPrice and pe:GetUsualPrice(row.storageKey)
		return usual and usual.usual
	end
	local function vsUsual(row)
		local usual = usualOf(row)
		return usual and row.price and (row.price - usual) / usual
	end
	return pe:MoneyColumn({ id = "usual", label = L["Usual"], width = 86, value = usualOf }), {
		id = "vsUsual", label = L["Vs usual"], justifyH = "RIGHT", width = 64, sortable = true, defaultSort = "asc",
		sortValue = function(row) return vsUsual(row) or 0 end,
		getText = function(row) return pe:FormatSignedPercent(vsUsual(row)) end,
	}
end

-- "26g x4 · 30g x12 · 38g x70": the cheapest price levels from the last full scan.
local function priceStepsText(pe, rowData)
	local steps = pe.GetPriceSteps and pe:GetPriceSteps(rowData.itemID)
	if not steps or #steps == 0 then
		return "-"
	end
	local parts = {}
	for index = 1, math.min(#steps, 6), 2 do
		parts[#parts + 1] = pe:FormatCopperShort(steps[index]) .. " x" .. pe:FormatNumberGrouped(steps[index + 1])
	end
	return table.concat(parts, " · ")
end

-- "+46% after 9 for 26g 40s": the largest jump between price levels and what clearing up to it costs.
local function priceGapText(pe, rowData)
	local steps = pe.GetPriceSteps and pe:GetPriceSteps(rowData.itemID)
	local gap = steps and pe.MarketSignals.FindPriceGap(steps, 0.1)
	if not gap then
		return "-"
	end
	return string.format(L["+%d%% after %s for %s"], math.floor(gap.gapPct * 100 + 0.5),
		pe:FormatNumberGrouped(gap.belowQty), pe:FormatCopperShort(gap.belowCost))
end

local WEEKDAYS = { L["Mon"], L["Tue"], L["Wed"], L["Thu"], L["Fri"], L["Sat"], L["Sun"] }

-- "Cheapest Wed -6%, dearest Tue +8% (6 weeks)", from the item's own scans.
local function weekdayText(pe, rowData)
	local pattern = pe.GetWeekdayPattern and pe:GetWeekdayPattern(rowData.storageKey)
	if not pattern then
		return L["Not enough scans yet"]
	end
	local function part(weekday)
		return string.format("%s %+d%%", WEEKDAYS[weekday], math.floor(pattern.byDay[weekday] * 100 + 0.5))
	end
	return string.format(L["Cheapest %s, priciest %s (%d weeks)"], part(pattern.cheapest), part(pattern.dearest), pattern.weeks)
end

-- Key facts of one Market row for the item view.
local function marketFactRows(pe, rowData)
	return {
		{ "Lowest", pe:FormatCopperFull(rowData.price) },
		{ "Highest", pe:FormatCopperFull(rowData.marketHigh or rowData.price) },
		{ L["Usual price"], usualPriceText(pe, rowData) },
		{ L["Usual range"], usualRangeText(pe, rowData) },
		{ L["Sales a day, estimated"], sellsFactText(pe, rowData) },
		{ L["Listed supply lasts"], supplyFactText(pe, rowData) },
		{ L["By weekday"], weekdayText(pe, rowData) },
		{ L["Cheapest steps"], priceStepsText(pe, rowData) },
		{ L["Biggest price jump"], priceGapText(pe, rowData) },
		{ "Quantity", pe:FormatNumberGrouped(rowData.sampleSize or 0) },
		{ "Listings", (tonumber(rowData.listingCount) or 0) > 0 and pe:FormatNumberGrouped(rowData.listingCount) or "-" },
		{ "Seen", pe:FormatScanTimestamp(rowData.seenAt) },
	}
end

function Tradewright:BuildMarketTableColumns()
	local pe = self
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
	local usual, vsUsual = usualColumns(pe)
	return {
		self:CreateItemColumn({
			label = L["Item"], defaultSort = "asc",
			getItemID = function(row) return row.itemID end,
			getName = function(row) return pe:GetItemDisplayName(row.itemID) end,
			sortValue = function(row) return row.name or "" end,
		}),
		pe:MoneyColumn({ id = "price", label = L["Lowest"], width = 86 }),
		pe:MoneyColumn({ id = "marketHigh", label = L["Highest"], width = 86, value = function(row) return row.marketHigh or row.price end }),
		usual, vsUsual, sellsColumn(pe),
		count("sampleSize", "Qty", "sampleSize", 60),
		count("listingCount", "Listings", "listingCount", 60, true),
		{
			id = "seenAt", label = L["Seen"], justifyH = "RIGHT", width = 64, sortable = true, defaultSort = "desc", optional = true,
			sortValue = function(row) return row.seenAt or 0 end,
			getText = function(row) return pe:FormatShortTime(row.seenAt) end,
		},
	}
end

function Tradewright:LayoutMarketPanel(panel)
	if not panel then
		return
	end
	local selected = self.ui.marketSelectedRow ~= nil
	panel.detailEmpty:SetShown(not selected)
	panel.detailBody:SetShown(selected)
end

-- One auction listing's history: optional header, key facts, hourly price graph and the recent hours.
-- Used by the Market tab detail card and the item details window. `opts.noHeader` hides the header.
-- The newest 48 hours of a listing's history as chart series, and as table rows newest first.
function Tradewright:BuildMarketChartSeries(points)
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
	return { primary = primary, secondary = secondary, quantity = quantity }, recent
end

-- The hourly history points saved for one auction storage key, oldest first.
function Tradewright:GetMarketHistoryPoints(storageKey)
	local auction = self:InitAuctionDB()
	local hourly = auction and auction.history and auction.history.hourly and auction.history.hourly[storageKey]
	local MarketLogic = self.MarketLogic
	return MarketLogic and MarketLogic.BuildMarketHistorySeries and MarketLogic.BuildMarketHistorySeries(hourly) or {}
end

local function createHistoryTable(pe, view)
	view.historyTable = pe:CreateReusableTable(view, {
		autoFitToScroll = true,
		emptyTitle = L["No history"],
		emptyHint = L["Each full scan saves one hour of prices."],
	})
	view.historyTable.frame:SetPoint("TOPLEFT", view.graph, "BOTTOMLEFT", 0, -8)
	view.historyTable.frame:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, 0)
	view.historyTable:SetColumns({
		{ id = "at", label = L["Hour"], width = 80, flex = 1, minWidth = 60, getText = function(p) return pe:FormatScanTimestamp(p.at) end },
		{ id = "last", label = L["Price"], width = 78, justifyH = "RIGHT", getText = function(p) return pe:FormatCopperShort(p.last or p.avg or p.min) end },
		{ id = "qty", label = L["Qty"], width = 52, justifyH = "RIGHT", getText = function(p) return pe:FormatNumberGrouped(p.qty or 0) end },
	})
end

-- The optional item header and the key facts list below it.
local function createHistoryFacts(pe, view, opts)
	local top = view
	if not opts.noHeader then
		view.header = pe:CreateDetailHeader(view)
		view.header:SetPoint("TOPLEFT")
		view.header:SetPoint("TOPRIGHT")
		top = view.header
	end
	view.facts = pe:CreateKeyValueList(view)
	view.facts:SetPoint("TOPLEFT", top, top == view and "TOPLEFT" or "BOTTOMLEFT", 0, top == view and 0 or -10)
	view.facts:SetPoint("TOPRIGHT", top, top == view and "TOPRIGHT" or "BOTTOMRIGHT", 0, top == view and 0 or -10)
end

function Tradewright:CreateMarketHistoryView(parent, opts)
	opts = opts or {}
	local pe = self
	local view = CreateFrame("Frame", nil, parent)
	createHistoryFacts(self, view, opts)
	local graphHeading = self:CreateMarketChartHeading(view)
	view.graph = self:CreateTimeSeriesGraph(view, {
		showTitle = false,
		plotHeight = opts.plotHeight or 96,
		emptyText = L["No price history for this range yet. Run a full scan at the auction house."],
		yFormatter = function(v) return pe:FormatCopperShort(v) end,
	})
	view.graph:SetPoint("TOPLEFT", graphHeading, "BOTTOMLEFT", 0, -6)
	createHistoryTable(self, view)
	view:SetScript("OnSizeChanged", function(self, width)
		self.graph:SetWidth(width)
	end)

	-- rowData: a Market browser row (storageKey, itemID, price, marketHigh, sampleSize, listingCount, seenAt).
	function view:ShowRow(rowData)
		if self.header then
			self.header:SetItem(rowData.itemID, rowData.name or pe:GetItemDisplayName(rowData.itemID),
				string.format(L["Item %s · %s"], tostring(rowData.itemID or "?"), rowData.scope == "commodity" and "commodity" or "item"))
		end
		self.facts:SetRows(marketFactRows(pe, rowData))
		local series, recent = pe:BuildMarketChartSeries(pe:GetMarketHistoryPoints(rowData.storageKey))
		self.historyTable:SetRows(recent)
		self.historyTable:Refresh()
		pe:ShowMarketChart(self, rowData, series)
	end
	return view
end

-- The Market browser row for one storage key, or nil when nothing is saved under it.
function Tradewright:GetMarketRowForStorageKey(storageKey)
	local auction = self:InitAuctionDB()
	if not (auction and storageKey) then
		return nil
	end
	local commodity = auction.snapshot.commodities[storageKey]
	local item = auction.snapshot.items[storageKey]
	if not (commodity or item) then
		return nil
	end
	return self.MarketLogic.BuildMarketBrowserRows(
		commodity and { [storageKey] = commodity } or {},
		item and { [storageKey] = item } or {},
		{ resolveName = function(itemID) return Tradewright:GetItemDisplayName(itemID, true) end })[1]
end

function Tradewright:OnMarketFilterChanged()
	self:SaveMarketFilters()
	self:RefreshMarketTab()
end

-- A dropdown editing the market filter `key` (a multi-choice selection).
function Tradewright:CreateMarketFilterDropdown(parent, key, config)
	local pe, filters = self, self:GetMarketFilters()
	config.getSelection = function() return filters[key] end
	config.setSelection = config.setSelection or function(selection) filters[key] = selection end
	config.onChanged = function() pe:OnMarketFilterChanged() end
	return self:CreateMultiSelectDropdown(parent, config)
end

-- Row 1: search, item class, subclass, quality.
function Tradewright:CreateMarketToolbar(panel)
	local pe, filters = self, self:GetMarketFilters()
	panel.toolbar = CreateFrame("Frame", nil, panel)
	panel.toolbar:SetPoint("TOPLEFT")
	panel.toolbar:SetPoint("TOPRIGHT")
	panel.toolbar:SetHeight(26)
	panel.qualityDropdown = self:CreateMarketFilterDropdown(panel.toolbar, "qualities", {
		width = 128, allLabel = L["Any quality"], getOptions = function() return pe:GetQualityFilterOptions() end })
	panel.qualityDropdown:SetPoint("RIGHT")
	panel.subclassDropdown = self:CreateMarketFilterDropdown(panel.toolbar, "subclasses", { width = 150, allLabel = L["All subclasses"] })
	panel.classDropdown = self:CreateMarketFilterDropdown(panel.toolbar, "classes", { width = 150, allLabel = L["All classes"],
		setSelection = function(selection)
			filters.classes = selection
			filters.subclasses = {}
		end })
	self:ChainLeft({ panel.qualityDropdown, panel.subclassDropdown, panel.classDropdown }, 8)
	self.ui.marketSearchBox = self:CreateSearchBox(panel.toolbar, L["Search the last scan"], function()
		pe:RefreshMarketTab()
	end)
	self.ui.marketSearchBox:SetPoint("LEFT", 6, 0)
	self.ui.marketSearchBox:SetPoint("RIGHT", panel.classDropdown, "LEFT", -14, 0)
end

-- A gold amount box for the market filter `key`.
function Tradewright:CreateMarketPriceBox(parent, placeholder, key)
	local pe, filters = self, self:GetMarketFilters()
	local box = self:CreateSearchBox(parent, placeholder, function(text)
		filters[key] = tonumber(text)
		pe:OnMarketFilterChanged()
	end, 0.4)
	box:SetNumeric(true)
	box:SetMaxLetters(7)
	box:SetWidth(64)
	box:SetJustifyH("RIGHT")
	return box
end

-- Row 2: owned only, price range in gold, reset; when the last full scan ran on the right.
function Tradewright:CreateMarketFilterRow(panel)
	local pe, filters = self, self:GetMarketFilters()
	local row = CreateFrame("Frame", nil, panel)
	row:SetPoint("TOPLEFT", panel.toolbar, "BOTTOMLEFT", 0, -8)
	row:SetPoint("TOPRIGHT", panel.toolbar, "BOTTOMRIGHT", 0, -8)
	row:SetHeight(26)
	panel.filterRow = row
	panel.ownedOnly = self:CreateCheckbox(row, L["Only items I own"], function(checked)
		filters.ownedOnly = checked
		pe:OnMarketFilterChanged()
	end)
	panel.ownedOnly:SetPoint("LEFT")
	panel.priceLabel = self:CreateText(row, "GameFontHighlightSmall", "textMuted")
	panel.priceLabel:SetPoint("LEFT", panel.ownedOnly, "RIGHT", 16, 0)
	panel.priceLabel:SetText(L["Lowest price"])
	panel.minGold = self:CreateMarketPriceBox(row, L["Min g"], "minGold")
	panel.minGold:SetPoint("LEFT", panel.priceLabel, "RIGHT", 12, 0)
	panel.priceDash = self:CreateText(row, "GameFontHighlightSmall", "textMuted")
	panel.priceDash:SetPoint("LEFT", panel.minGold, "RIGHT", 10, 0)
	panel.priceDash:SetText("to")
	panel.maxGold = self:CreateMarketPriceBox(row, L["Max g"], "maxGold")
	panel.maxGold:SetPoint("LEFT", panel.priceDash, "RIGHT", 12, 0)
	panel.resetFilters = self:CreateButton(row, L["Reset filters"], function() pe:ResetMarketFilters() end, { small = true })
	panel.resetFilters:SetPoint("LEFT", panel.maxGold, "RIGHT", 14, 0)
	panel.scanBadge = self:CreateBadge(row)
	panel.scanBadge:SetPoint("RIGHT")
end

-- Detail pane, always shown: empty state until a row is picked.
function Tradewright:CreateMarketDetailCard(panel)
	panel.detailCard = self:CreateInset(panel)
	panel.detailCard:SetPoint("TOPRIGHT", panel.filterRow, "BOTTOMRIGHT", 0, -GAP)
	panel.detailCard:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
	panel.detailCard:SetWidth(DETAIL_WIDTH)
	panel.detailEmpty = self:CreateEmptyState(panel.detailCard)
	panel.detailEmpty:SetAllPoints()
	panel.detailEmpty:SetMessage(L["Select an item"], L["Click a row to see its prices and hourly history from past scans."])
	panel.detailBody = self:CreateMarketHistoryView(panel.detailCard)
	panel.detailBody:SetPoint("TOPLEFT", PAD, -PAD)
	panel.detailBody:SetPoint("BOTTOMRIGHT", -PAD, PAD)
end

function Tradewright:OnMarketRowClick(panel, rowData, tableWidget)
	if self:HandleItemRowModifiedClick(rowData and rowData.itemID) then
		return
	end
	self.ui.marketSelectedStorageKey = rowData and rowData.storageKey
	self.ui.marketSelectedRow = rowData
	tableWidget:SetSelectedRow(rowData)
	self:RenderMarketDetails(rowData)
	self:LayoutMarketPanel(panel)
end

-- Table fills the rest.
function Tradewright:CreateMarketTable(panel)
	local pe, ui = self, self.ui
	local marketTable = self:CreateReusableTable(panel, {
		footer = true,
		emptyTitle = L["No prices yet"],
		emptyHint = L["Open the auction house and run a full scan."],
		isRowSelected = function(rowData)
			return rowData and rowData.storageKey ~= nil and rowData.storageKey == ui.marketSelectedStorageKey
		end,
		maxRows = MAX_ROWS, viewportVirtualize = true, virtualOverscan = 8, autoFitToScroll = true,
		sortKey = self:GetSetting("market.sortColumn", "name"),
		sortAsc = self:GetSetting("market.sortAsc", true) ~= false,
		onSortChanged = function(key, asc)
			pe:SetSetting("market.sortColumn", key)
			pe:SetSetting("market.sortAsc", asc)
		end,
		onRowEnter = function(rowFrame, rowData)
			pe:ShowItemRowTooltip(rowFrame, rowData and rowData.itemID, {
				{ L["Highest listing"], pe:FormatCopperShort(rowData and (rowData.marketHigh or rowData.price)) },
			}, L["Click for history · Shift-click to link"])
		end,
		onRowLeave = function() GameTooltip:Hide() end,
		onRowClick = function(_, rowData, _, tableWidget) pe:OnMarketRowClick(panel, rowData, tableWidget) end,
	})
	marketTable.frame:SetPoint("TOPLEFT", panel.filterRow, "BOTTOMLEFT", 0, -GAP)
	marketTable.frame:SetPoint("BOTTOMRIGHT", panel.detailCard, "BOTTOMLEFT", -GAP, 0)
	marketTable:SetColumns(self:BuildMarketTableColumns())
	return marketTable
end

function Tradewright:EnsureMarketPanel(container)
	local ui = self.ui
	if ui.marketPanel then
		return ui.marketPanel
	end
	local panel = CreateFrame("Frame", nil, container)
	panel:SetAllPoints()
	ui.marketPanel = panel
	self:CreateMarketToolbar(panel)
	self:CreateMarketFilterRow(panel)
	self:CreateMarketDetailCard(panel)
	ui.marketTable = self:CreateMarketTable(panel)
	panel.marketTable = ui.marketTable
	panel:SetScript("OnSizeChanged", function()
		Tradewright:LayoutMarketPanel(panel)
	end)
	self:LayoutMarketPanel(panel)
	return panel
end

-- Market filter state, kept in settings so it survives a reload.
function Tradewright:GetMarketFilters()
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

function Tradewright:SaveMarketFilters()
	self:SetSetting("market.filters", self:GetMarketFilters())
end

function Tradewright:ResetMarketFilters()
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
function Tradewright:GetOwnedItemSet()
	local owned = {}
	for _, row in ipairs(self:BuildInventoryRowsAggregatedByItem(self.db, {}, "") or {}) do
		if (tonumber(row.total) or 0) > 0 and row.itemID then
			owned[tonumber(row.itemID)] = true
		end
	end
	return owned
end

-- The Market table's sort, or the saved one before the table exists.
function Tradewright:GetMarketSort()
	local marketTable = self.ui and self.ui.marketTable
	local sortKey = marketTable and marketTable.sortKey or self:GetSetting("market.sortColumn", "name")
	if marketTable and marketTable.sortAsc ~= nil then
		return sortKey, marketTable.sortAsc
	end
	return sortKey, self:GetSetting("market.sortAsc", true) ~= false
end

function Tradewright:CollectMarketBrowserRows()
	local auction = self:InitAuctionDB()
	if not auction then
		return {}
	end
	local ui = self.ui or {}
	local MarketLogic = self.MarketLogic
	if not MarketLogic or not MarketLogic.BuildMarketBrowserRows then
		return {}
	end
	local query = self:Trim(ui.marketSearchBox and ui.marketSearchBox:GetText() or "")
	local sortKey, sortAsc = self:GetMarketSort()
	return MarketLogic.BuildMarketBrowserRows(auction.snapshot.commodities, auction.snapshot.items, {
		query = query,
		sortKey = sortKey,
		sortAsc = sortAsc,
		resolveName = function(itemID)
			return Tradewright:GetItemDisplayName(itemID, true)
		end,
	})
end

-- Switches to the Market tab with this listing selected (shown when the current filters include it).
function Tradewright:OpenMarketItem(storageKey)
	self.ui.marketSelectedStorageKey = storageKey
	self:ShowDashboardTab("market")
end

function Tradewright:RenderMarketDetails(rowData)
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

-- Fills the class and subclass dropdowns from the listed items and syncs the other filter controls.
function Tradewright:RefreshMarketFilterControls(panel, filters, allRows)
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
	-- Restore a saved gold bound into an empty box, but never overwrite what the player is typing.
	for _, key in ipairs({ "minGold", "maxGold" }) do
		local box = panel[key]
		if filters[key] and box:GetText() == "" and not box:HasFocus() then
			box:SetText(tostring(filters[key]))
		end
	end
end

function Tradewright:FilterMarketBrowserRows(allRows, filters)
	return self.MarketLogic.FilterMarketRows(allRows, {
		classes = filters.classes,
		subclasses = filters.subclasses,
		qualities = filters.qualities,
		ownedOnly = filters.ownedOnly,
		owned = filters.ownedOnly and self:GetOwnedItemSet() or nil,
		minPrice = filters.minGold and filters.minGold * 10000 or nil,
		maxPrice = filters.maxGold and filters.maxGold * 10000 or nil,
	}, function(itemID)
		return Tradewright:GetItemFilterInfo(itemID)
	end)
end

function Tradewright:RefreshMarketScanBadge(panel)
	local lastScanAt = self.GetLastFullAuctionScanAt and self:GetLastFullAuctionScanAt()
	if lastScanAt then
		panel.scanBadge:SetBadge(string.format(L["Full scan %s"], self:FormatScanTimestamp(lastScanAt)), "accent")
	else
		panel.scanBadge:SetBadge(L["No full scan yet"], "warning")
	end
end

-- Empty-state and footer texts: an empty table means "no prices" before any scan, else "nothing matches".
function Tradewright:RefreshMarketTableTexts(marketTable, shownCount, totalCount)
	if totalCount > 0 then
		marketTable:SetEmptyText(L["Nothing matches"], L["Change the search or press Reset filters."])
	else
		marketTable:SetEmptyText(L["No prices yet"], L["Open the auction house and run a full scan."])
	end
	marketTable:SetFooterText(string.format(L["%s of %s items"], self:FormatNumberGrouped(shownCount), self:FormatNumberGrouped(totalCount)),
		L["Works away from the auction house"])
end

-- The shown row with the selected storage key, or nil when the filters hide it.
local function findRowByStorageKey(rows, storageKey)
	if not storageKey then
		return nil
	end
	for _, row in ipairs(rows) do
		if row.storageKey == storageKey then
			return row
		end
	end
	return nil
end

function Tradewright:RefreshMarketTab()
	self:InitDB()
	local ui = self.ui
	if not ui or not ui.marketPanel then
		return
	end
	if ui.activeMainTab and ui.activeMainTab ~= "market" then
		return
	end
	local panel = ui.marketPanel
	local allRows = self:CollectMarketBrowserRows()
	local filters = self:GetMarketFilters()
	self:RefreshMarketFilterControls(panel, filters, allRows)
	local rows = self:FilterMarketBrowserRows(allRows, filters)
	ui.marketWorkingRows = rows
	ui.marketTable:SetRows(rows)
	self:RefreshMarketScanBadge(panel)
	ui.marketTable:Refresh()
	self:RefreshMarketTableTexts(ui.marketTable, #rows, #allRows)

	ui.marketSelectedRow = findRowByStorageKey(rows, ui.marketSelectedStorageKey)
	self:RenderMarketDetails(ui.marketSelectedRow)
	self:LayoutMarketPanel(panel)
end
