local _, AuctionHelper = ...

-- Sales ledger (Overview → Sales): what the auction house has paid out. Four headline numbers,
-- gold earned per day, the items that sell best and the latest sales. The numbers come from the
-- ledger, which gains a sale whenever auction gold is collected from the mailbox.

local GAP = 12
local PAD = 10
local STATS_HEIGHT = 58
local CHART_HEIGHT = 190
local RECENT_ROWS = 100

-- Table options shared by both cards: rows sort high to low on `sortKey`, item rows link on shift-click.
local function salesTableOptions(pe, sortKey, tooltipPairs)
	return {
		rowHeight = 24,
		sortKey = sortKey,
		sortAsc = false,
		emptyTitle = "No sales recorded yet",
		emptyHint = "A sale is added when you collect its gold from the mailbox.",
		onRowEnter = function(rowFrame, row)
			if row then
				pe:ShowItemRowTooltip(rowFrame, row.itemID, tooltipPairs(row), row.itemID and "Shift-click to link." or nil)
			end
		end,
		onRowClick = function(_, row)
			if row then
				pe:HandleItemRowModifiedClick(row.itemID)
			end
		end,
	}
end

local ORIGINS = { "crafted", "resold", "farmed", "unknown" }

-- "6 crafted, 4 farmed": where the item's sold units came from.
local function originText(origins)
	local parts = {}
	for _, origin in ipairs(ORIGINS) do
		if (origins[origin] or 0) > 0 then
			parts[#parts + 1] = string.format("%d %s", origins[origin], origin)
		end
	end
	return #parts > 0 and table.concat(parts, ", ") or "-"
end

-- Sums each sale's origin labels into its item row (rows matched by item id, else name).
local function addOrigins(items, sales, labels)
	local byKey = {}
	for _, item in ipairs(items) do
		item.origins = {}
		byKey[item.itemID or item.name] = item
	end
	for _, sale in ipairs(sales) do
		local item = byKey[sale.itemID or sale.itemName]
		for origin, units in pairs(item and labels[sale] or {}) do
			item.origins[origin] = (item.origins[origin] or 0) + units
		end
	end
end

local function itemTooltipPairs(pe, row)
	local count = function(n) return pe:FormatNumberGrouped(n) end
	return {
		{ "Sales", string.format("%s, %s items", count(row.sales), count(row.units)) },
		{ "Earned after cut", pe:FormatCopperFull(row.net) },
		{ "Sold for", pe:FormatCopperFull(row.gross) },
		{ "Sales a week", string.format("%.1f", row.perWeek) },
		{ "Last sold", pe:FormatScanTimestamp(row.lastAt) },
		{ "Came from", originText(row.origins or {}) },
	}
end

local function itemsColumns(pe)
	local count = function(n) return pe:FormatNumberGrouped(n) end
	return {
		pe:ItemColumn({ minWidth = 120 }),
		pe:NumberColumn({ id = "sales", label = "Sales", width = 46, format = count }),
		pe:NumberColumn({ id = "units", label = "Units", width = 46, format = count, optional = true }),
		pe:MoneyColumn({ id = "net", label = "Earned", width = 78 }),
		pe:MoneyColumn({ id = "avgUnit", label = "Each", width = 70, optional = true }),
		pe:NumberColumn({ id = "perWeek", label = "A week", width = 56, format = function(n) return string.format("%.1f", n) end }),
	}
end

local function recentColumns(pe)
	return {
		pe:ItemColumn({ minWidth = 120 }),
		pe:MoneyColumn({ id = "net", label = "Earned", width = 78 }),
		{ id = "ts", label = "When", justifyH = "RIGHT", width = 104, sortable = true, defaultSort = "desc",
			sortValue = function(row) return row.ts end,
			getText = function(row) return pe:FormatScanTimestamp(row.ts) end },
	}
end

local function recentTooltipPairs(pe, row)
	return {
		{ "Earned after cut", pe:FormatCopperFull(row.net) },
		{ "Sold for", pe:FormatCopperFull(row.gross) },
		{ "Buyer", row.buyer or "several buyers" },
		{ "Sold by", row.characterKey },
	}
end

-- The latest sales as table rows, newest first.
local function recentRows(pe, events)
	local rows = {}
	for index = 1, math.min(RECENT_ROWS, #events) do
		local event = events[index]
		local quantity = tonumber(event.quantity) or 1
		local name = event.itemName or pe:GetItemDisplayName(event.itemID)
		rows[index] = {
			_rowIdentity = tostring(index),
			itemID = event.itemID,
			name = quantity > 1 and string.format("%s x%d", name, quantity) or name,
			ts = tonumber(event.ts) or 0,
			net = tonumber(event.netCopper) or tonumber(event.totalCopper) or 0,
			gross = tonumber(event.totalCopper) or 0,
			buyer = event.buyer,
			characterKey = event.characterKey,
		}
	end
	return rows
end

local SalesDashboardMixin = {}

function AuctionHelper:CreateSalesDashboard(parent)
	local pe = self
	local dash = CreateFrame("Frame", nil, parent)
	for name, method in pairs(SalesDashboardMixin) do
		dash[name] = method
	end
	dash.pe = pe
	dash:SetAllPoints()
	dash.statsRow = CreateFrame("Frame", nil, dash)
	dash.statsRow:SetPoint("TOPLEFT")
	dash.statsRow:SetPoint("TOPRIGHT")
	dash.statsRow:SetHeight(STATS_HEIGHT)
	dash.stats = pe:CreateStats(dash.statsRow, { "earned", "sales", "bestEarner", "mostOften" })
	dash:CreateChartCard()
	-- What sells: one row per item, sortable by how much, how many and how often.
	dash.items = pe:CreateTableCard(dash, {
		title = "What sells",
		columns = itemsColumns(pe),
		table = salesTableOptions(pe, "net", function(row) return itemTooltipPairs(pe, row) end),
	})
	dash.recent = pe:CreateTableCard(dash, {
		title = "Latest sales",
		columns = recentColumns(pe),
		table = salesTableOptions(pe, "ts", function(row) return recentTooltipPairs(pe, row) end),
	})
	dash:SetScript("OnSizeChanged", function()
		dash:Layout()
	end)
	dash:Layout()
	return dash
end

-- Gold per day, with the period switch that drives the whole view.
function SalesDashboardMixin:CreateChartCard()
	local pe = self.pe
	self.chart = pe:CreateDashboardCard(self, "Gold from sales, per day")
	self.chart:SetPoint("TOPLEFT", self.statsRow, "BOTTOMLEFT", 0, -GAP)
	self.chart:SetPoint("TOPRIGHT", self.statsRow, "BOTTOMRIGHT", 0, -GAP)
	self.chart:SetHeight(CHART_HEIGHT)
	self.periodButtons = pe:CreatePeriodButtons(self.chart, function() self:Refresh() end)
	self.graph = pe:CreateTimeSeriesGraph(self.chart, {
		showTitle = false,
		plotHeight = CHART_HEIGHT - 76,
		emptyText = "No sales in this period yet.",
	})
	self.graph:SetPoint("BOTTOMLEFT", self.chart, "BOTTOMLEFT", PAD, 8)
	self.graph:SetYFormatter(function(value) return pe:FormatCopperShort(tonumber(value) or 0) end)
	self.graph:SetTooltipBuilder(function(tip, hit)
		local point = hit and hit.pt or hit
		tip:AddLine(date("%Y-%m-%d", point.at), 1, 1, 1)
		tip:AddLine(pe:FormatCopperFull(tonumber(point.value) or 0))
	end)
end

function SalesDashboardMixin:Layout()
	self.pe:LayoutEvenRow(self.statsRow, self.stats, 0, GAP)
	self.graph:SetWidth(math.max(80, self.chart:GetWidth() - PAD * 2))
	local half = math.max(200, (self:GetWidth() - GAP) / 2)
	self.items:ClearAllPoints()
	self.items:SetPoint("TOPLEFT", self.chart, "BOTTOMLEFT", 0, -GAP)
	self.items:SetPoint("BOTTOMLEFT")
	self.items:SetWidth(half)
	self.recent:ClearAllPoints()
	self.recent:SetPoint("TOPLEFT", self.items, "TOPRIGHT", GAP, 0)
	self.recent:SetPoint("BOTTOMRIGHT")
end

-- Names the summary items and returns the one that earned most and the one sold most often.
local function topItems(pe, items)
	local bestEarner, mostOften
	for _, item in ipairs(items) do
		item._rowIdentity = tostring(item.itemID or item.name)
		item.name = item.name or pe:GetItemDisplayName(item.itemID)
		if not bestEarner or item.net > bestEarner.net then
			bestEarner = item
		end
		if not mostOften or item.sales > mostOften.sales then
			mostOften = item
		end
	end
	return bestEarner, mostOften
end

function SalesDashboardMixin:RefreshTotals(summary)
	local pe, totals = self.pe, summary.totals
	local function money(copper) return pe:FormatCopperShort(copper) end
	self.stats.earned:SetValues("Earned from sales", money(totals.net),
		string.format("%s a day · %s paid in auction cut", money(totals.net / summary.spanDays), money(totals.gross - totals.net)),
		totals.net > 0 and "success" or nil)
	self.stats.sales:SetValues("Sales", pe:FormatNumberGrouped(totals.sales),
		string.format("%s items of %s kinds", pe:FormatNumberGrouped(totals.units), pe:FormatNumberGrouped(#summary.items)))
end

function SalesDashboardMixin:RefreshTopItems(items)
	local pe = self.pe
	local bestEarner, mostOften = topItems(pe, items)
	local nothing = "Nothing sold in this period"
	if bestEarner then
		self.stats.bestEarner:SetValues("Best earner", bestEarner.name, pe:FormatCopperShort(bestEarner.net) .. " earned", "gold")
		self.stats.mostOften:SetValues("Sells most often", mostOften.name,
			string.format("%s sales, %.1f a week", pe:FormatNumberGrouped(mostOften.sales), mostOften.perWeek))
	else
		self.stats.bestEarner:SetValues("Best earner", "-", nothing, nil)
		self.stats.mostOften:SetValues("Sells most often", "-", nothing)
	end
end

function SalesDashboardMixin:Refresh()
	local pe = self.pe
	local days = pe:StylePeriodButtons(self.periodButtons)
	-- The ledger lives in the Inventory module; without it the view stays empty.
	local summary = pe.GetSalesSummary and pe:GetSalesSummary(days > 0 and days or nil)
		or pe.ForeverLogic.SummarizeSales({}, time(), nil)
	self:RefreshTotals(summary)
	self:RefreshTopItems(summary.items)
	self.graph:SetAccentColor(pe:GetTheme().accent)
	self.graph:SetSeries(summary.daily)
	self.graph:SetSecondarySeries({})
	self.graph:SetQuantitySeries({})
	self.graph:Refresh()
	addOrigins(summary.items, summary.recent, pe:GetSaleOrigins())
	self.items.table:SetRows(summary.items)
	self.items.table:Refresh()
	self.recent.table:SetRows(recentRows(pe, summary.recent))
	self.recent.table:Refresh()
	self:Layout()
end
