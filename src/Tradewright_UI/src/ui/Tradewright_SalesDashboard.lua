local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Sales ledger (Overview → Sales): what the auction house has paid out. Four headline numbers,
-- gold earned per day, the items that sell best and the latest auction mails: sold, bought, or
-- come back unsold. The numbers come from the ledger, which gains an entry whenever an auction's
-- gold or item is collected from the mailbox.

local GAP = 12
local PAD = 10
local STATS_HEIGHT = 58
local CHART_HEIGHT = 190
local RECENT_ROWS = 100
-- What the "Latest" card can list; `amount` gives a row's gold: earned, paid (negative) or none.
local LATEST_KINDS = {
	{ key = "sold", label = L["Sold"], kinds = { sell = true },
		amount = function(event) return tonumber(event.netCopper) or tonumber(event.totalCopper) or 0 end },
	{ key = "bought", label = L["Bought"], kinds = { buy = true },
		amount = function(event) return -(tonumber(event.totalCopper) or 0) end },
	{ key = "returned", label = L["Came back"], kinds = { expired = true, cancelled = true }, amount = function() return nil end },
}
local KIND_TEXT = { sell = "Sold", buy = "Bought", expired = L["Expired unsold"], cancelled = "Cancelled" }

-- Table options shared by both cards: rows sort high to low on `sortKey`, item rows link on shift-click.
local function salesTableOptions(pe, sortKey, tooltipPairs)
	return {
		rowHeight = 24,
		sortKey = sortKey,
		sortAsc = false,
		emptyTitle = L["Nothing recorded yet"],
		emptyHint = L["An entry is added when you collect an auction's gold or item from the mailbox."],
		onRowEnter = function(rowFrame, row)
			if row then
				pe:ShowItemRowTooltip(rowFrame, row.itemID, tooltipPairs(row), row.itemID and L["Shift-click to link."] or nil)
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

-- How much of what this character posted sold (AuctionData's ledger; nil when never posted).
-- What each sold item cost to buy and what it made per unit, for items the ledger also saw bought.
local function addPurchases(pe, items)
	if not pe.GetLedgerItemTally then
		return
	end
	for _, item in ipairs(items) do
		local tally = pe:GetLedgerItemTally(item.itemID or item.name)
		local bought, realized = pe.IncomeLogic.PurchaseSummary(tally), pe.IncomeLogic.RealizedProfit(tally)
		item.boughtEach = bought and bought.avgUnit or nil
		item.profitEach = realized and realized.profitEach or nil
	end
end

local function addSaleRates(pe, items)
	if not pe.GetAuctionPanelPersonalSaleRate then
		return
	end
	for _, item in ipairs(items) do
		item.saleRate = item.itemID and pe:GetAuctionPanelPersonalSaleRate(item.itemID) or nil
	end
end

local function itemTooltipPairs(pe, row)
	local count = function(n) return pe:FormatNumberGrouped(n) end
	return {
		{ "Sales", string.format(L["%s, %s items"], count(row.sales), count(row.units)) },
		{ L["Earned after cut"], pe:FormatCopperFull(row.net) },
		{ L["Sold for"], pe:FormatCopperFull(row.gross) },
		{ L["Sales a week"], string.format("%.1f", row.perWeek) },
		{ L["Last sold"], pe:FormatScanTimestamp(row.lastAt) },
		{ L["Bought for, each"], row.boughtEach and pe:FormatCopperFull(row.boughtEach) or L["not bought at auction"] },
		{ L["Came from"], originText(row.origins or {}) },
	}
end

local function itemsColumns(pe)
	local count = function(n) return pe:FormatNumberGrouped(n) end
	return {
		pe:ItemColumn({ minWidth = 120 }),
		pe:NumberColumn({ id = "sales", label = L["Sales"], width = 46, format = count }),
		pe:PercentColumn({ id = "saleRate", label = L["Sold"], width = 46, optional = true }),
		pe:NumberColumn({ id = "units", label = L["Units"], width = 46, format = count, optional = true }),
		pe:MoneyColumn({ id = "net", label = L["Earned"], width = 78 }),
		pe:MoneyColumn({ id = "avgUnit", label = L["Each"], width = 70, optional = true }),
		pe:NumberColumn({ id = "perWeek", label = L["A week"], width = 56, format = function(n) return string.format("%.1f", n) end }),
		pe:MoneyColumn({ id = "boughtEach", label = L["Bought each"], width = 78, optional = true }),
		pe:NumberColumn({ id = "profitEach", label = L["Profit each"], width = 78, optional = true,
			format = function(copper) return pe:FormatSignedMoney(copper) end }),
	}
end

local function recentColumns(pe)
	return {
		pe:ItemColumn({ minWidth = 120 }),
		pe:NumberColumn({ id = "amount", label = L["Gold"], width = 78,
			format = function(copper) return pe:FormatSignedMoney(copper) end }),
		{ id = "ts", label = L["When"], justifyH = "RIGHT", width = 104, sortable = true, defaultSort = "desc",
			sortValue = function(row) return row.ts end,
			getText = function(row) return pe:FormatScanTimestamp(row.ts) end },
	}
end

local function recentTooltipPairs(pe, row)
	local lines = { { L["What happened"], KIND_TEXT[row.kind] } }
	if row.kind == "sell" then
		lines[#lines + 1] = { L["Earned after cut"], pe:FormatCopperFull(row.amount) }
		lines[#lines + 1] = { L["Sold for"], pe:FormatCopperFull(row.gross) }
		lines[#lines + 1] = { "Buyer", row.buyer or L["several buyers"] }
	elseif row.kind == "buy" then
		lines[#lines + 1] = { "Paid", pe:FormatCopperFull(row.gross) }
	end
	lines[#lines + 1] = { "Character", row.characterKey }
	return lines
end

-- The latest ledger events of one kind choice as table rows, newest first.
local function recentRows(pe, events, kindChoice)
	local rows = {}
	for index, event in ipairs(events) do
		local quantity = tonumber(event.quantity) or 1
		local name = event.itemName or pe:GetItemDisplayName(event.itemID)
		rows[index] = {
			_rowIdentity = tostring(index),
			itemID = event.itemID,
			name = quantity > 1 and string.format("%s × %d", name, quantity) or name,
			kind = event.kind,
			ts = tonumber(event.ts) or 0,
			amount = kindChoice.amount(event),
			gross = tonumber(event.totalCopper) or 0,
			buyer = event.buyer,
			characterKey = event.characterKey,
		}
	end
	return rows
end

local SalesDashboardMixin = {}

function Tradewright:CreateSalesDashboard(parent)
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
		title = L["What sells"],
		columns = itemsColumns(pe),
		table = salesTableOptions(pe, "net", function(row) return itemTooltipPairs(pe, row) end),
	})
	dash.recent = pe:CreateTableCard(dash, {
		title = L["Latest"],
		columns = recentColumns(pe),
		table = salesTableOptions(pe, "ts", function(row) return recentTooltipPairs(pe, row) end),
	})
	dash:CreateLatestKindButtons()
	dash:SetScript("OnSizeChanged", function()
		dash:Layout()
	end)
	dash:Layout()
	return dash
end

-- Gold per day, with the period switch that drives the whole view.
-- Sold / Bought / Came back at the Latest card's top right; the choice is a setting.
function SalesDashboardMixin:CreateLatestKindButtons()
	local pe, previous = self.pe, nil
	self.kindButtons = {}
	for index = #LATEST_KINDS, 1, -1 do
		local choice = LATEST_KINDS[index]
		local button = pe:CreateButton(self.recent, choice.label, function()
			pe:SetSetting("sales.latestKind", choice.key)
			self:Refresh()
		end, { small = true })
		button.choice = choice
		if previous then
			button:SetPoint("RIGHT", previous, "LEFT", 1, 0)
		else
			button:SetPoint("TOPRIGHT", -PAD, -7)
		end
		previous = button
		self.kindButtons[#self.kindButtons + 1] = button
	end
	self.recent.heading:SetPoint("RIGHT", previous, "LEFT", -8, 0)
end

-- Highlights the chosen kind button and returns its entry of LATEST_KINDS.
function SalesDashboardMixin:StyleLatestKindButtons()
	local chosenKey = self.pe:GetSetting("sales.latestKind", LATEST_KINDS[1].key)
	local chosen = LATEST_KINDS[1]
	for _, button in ipairs(self.kindButtons) do
		local isChosen = button.choice.key == chosenKey
		self.pe:StyleShellButton(button, isChosen)
		chosen = isChosen and button.choice or chosen
	end
	return chosen
end

function SalesDashboardMixin:RefreshLatest(days)
	local pe = self.pe
	local kindChoice = self:StyleLatestKindButtons()
	local since = days > 0 and (time() - days * 86400) or 0
	local events = pe.GetLedgerEvents and pe.IncomeLogic.LatestEvents(pe:GetLedgerEvents(), kindChoice.kinds, since, RECENT_ROWS) or {}
	self.recent.table:SetRows(recentRows(pe, events, kindChoice))
	self.recent.table:Refresh()
end

function SalesDashboardMixin:CreateChartCard()
	local pe = self.pe
	self.chart = pe:CreateDashboardCard(self, L["Gold from sales, per day"])
	self.chart:SetPoint("TOPLEFT", self.statsRow, "BOTTOMLEFT", 0, -GAP)
	self.chart:SetPoint("TOPRIGHT", self.statsRow, "BOTTOMRIGHT", 0, -GAP)
	self.chart:SetHeight(CHART_HEIGHT)
	self.periodButtons = pe:CreatePeriodButtons(self.chart, function() self:Refresh() end)
	self.graph = pe:CreateTimeSeriesGraph(self.chart, {
		showTitle = false,
		plotHeight = CHART_HEIGHT - 76,
		emptyText = L["No sales in this period yet."],
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
	self.stats.earned:SetValues(L["Earned from sales"], money(totals.net),
		string.format(L["%s a day · %s paid in auction cut"], money(totals.net / summary.spanDays), money(totals.gross - totals.net)),
		totals.net > 0 and "success" or nil)
	self.stats.sales:SetValues(L["Sales"], pe:FormatNumberGrouped(totals.sales),
		string.format(L["%s items, %s different"], pe:FormatNumberGrouped(totals.units), pe:FormatNumberGrouped(#summary.items)))
end

function SalesDashboardMixin:RefreshTopItems(items)
	local pe = self.pe
	local bestEarner, mostOften = topItems(pe, items)
	local nothing = L["Nothing sold in this period"]
	if bestEarner then
		self.stats.bestEarner:SetValues(L["Best earner"], bestEarner.name, pe:FormatCopperShort(bestEarner.net) .. L[" earned"], "gold")
		self.stats.mostOften:SetValues(L["Sells most often"], mostOften.name,
			string.format(L["%s sales, %.1f a week"], pe:FormatNumberGrouped(mostOften.sales), mostOften.perWeek))
	else
		self.stats.bestEarner:SetValues(L["Best earner"], "-", nothing, nil)
		self.stats.mostOften:SetValues(L["Sells most often"], "-", nothing)
	end
end

function SalesDashboardMixin:Refresh()
	local pe = self.pe
	local days = pe:StylePeriodButtons(self.periodButtons)
	-- The ledger lives in the Inventory module; without it the view stays empty.
	local summary = pe.GetSalesSummary and pe:GetSalesSummary(days > 0 and days or nil)
		or pe.IncomeLogic.SummarizeSales({}, time(), nil)
	self:RefreshTotals(summary)
	self:RefreshTopItems(summary.items)
	self.graph:SetAccentColor(pe:GetTheme().accent)
	self.graph:SetSeries(summary.daily)
	self.graph:SetSecondarySeries({})
	self.graph:SetQuantitySeries({})
	self.graph:Refresh()
	addOrigins(summary.items, summary.recent, pe:GetSaleOrigins())
	addSaleRates(pe, summary.items)
	addPurchases(pe, summary.items)
	self.items.table:SetRows(summary.items)
	self.items.table:Refresh()
	self:RefreshLatest(days)
	self:Layout()
end
