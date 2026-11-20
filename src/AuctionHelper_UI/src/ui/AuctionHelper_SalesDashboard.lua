local _, ProfessionExporter = ...

-- Sales ledger (Overview → Sales): what the auction house has paid out. Four headline numbers,
-- gold earned per day, the items that sell best and the latest sales. The numbers come from the
-- ledger, which gains a sale whenever auction gold is collected from the mailbox.

local GAP = 12
local PAD = 10
local STATS_HEIGHT = 58
local CHART_HEIGHT = 190
local RECENT_ROWS = 100
local PERIODS = { { 7, "7 days" }, { 30, "30 days" }, { 90, "90 days" }, { 0, "All time" } }

local function numberColumn(id, label, width, format, optional)
	return {
		id = id, label = label, justifyH = "RIGHT", width = width, sortable = true, defaultSort = "desc", optional = optional,
		sortValue = function(row) return tonumber(row[id]) or -1 end,
		getText = function(row) return row[id] and format(row[id]) or "-" end,
	}
end

local function createCard(pe, parent, title)
	local card = pe:CreateInset(parent)
	card.heading = pe:CreateHeading(card, title)
	card.heading:SetPoint("TOPLEFT", PAD, -PAD)
	card.heading:SetPoint("RIGHT", -PAD, 0)
	return card
end

local function attachTable(pe, card, columns, sortKey, tooltipPairs)
	local tbl = pe:CreateReusableTable(card, {
		autoFitToScroll = true,
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
		onRowLeave = function()
			GameTooltip:Hide()
		end,
		onRowClick = function(_, row)
			if row then
				pe:HandleItemRowModifiedClick(row.itemID)
			end
		end,
	})
	tbl:SetColumns(columns)
	tbl.frame:SetPoint("TOPLEFT", card.heading, "BOTTOMLEFT", 0, -10)
	tbl.frame:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -PAD, PAD)
	card.table = tbl
end

function ProfessionExporter:CreateSalesDashboard(parent)
	local pe = self
	local money = function(copper) return pe:FormatCopperShort(copper) end
	local count = function(n) return pe:FormatNumberGrouped(n) end
	local itemColumn = function()
		return pe:CreateItemColumn({
			minWidth = 120,
			getItemID = function(row) return row.itemID end,
			getName = function(row) return row.name end,
		})
	end
	local dash = CreateFrame("Frame", nil, parent)
	dash:SetAllPoints()

	dash.statsRow = CreateFrame("Frame", nil, dash)
	dash.statsRow:SetPoint("TOPLEFT")
	dash.statsRow:SetPoint("TOPRIGHT")
	dash.statsRow:SetHeight(STATS_HEIGHT)
	dash.stats = {}
	for index = 1, 4 do
		dash.stats[index] = pe:CreateStat(dash.statsRow)
	end

	-- Gold per day, with the period switch that drives the whole view.
	dash.chart = createCard(pe, dash, "Gold from sales, per day")
	dash.chart:SetPoint("TOPLEFT", dash.statsRow, "BOTTOMLEFT", 0, -GAP)
	dash.chart:SetPoint("TOPRIGHT", dash.statsRow, "BOTTOMRIGHT", 0, -GAP)
	dash.chart:SetHeight(CHART_HEIGHT)
	dash.periodButtons = {}
	local previous
	for index = #PERIODS, 1, -1 do
		local days, label = PERIODS[index][1], PERIODS[index][2]
		local button = pe:CreateButton(dash.chart, label, function()
			pe:SetSetting("sales.periodDays", days)
			dash:Refresh()
		end, { small = true })
		button.days = days
		if previous then
			button:SetPoint("RIGHT", previous, "LEFT", 1, 0)
		else
			button:SetPoint("TOPRIGHT", -PAD, -7)
		end
		previous = button
		dash.periodButtons[#dash.periodButtons + 1] = button
	end
	dash.chart.heading:SetPoint("RIGHT", previous, "LEFT", -8, 0)
	dash.graph = pe:CreateTimeSeriesGraph(dash.chart, {
		showTitle = false,
		plotHeight = CHART_HEIGHT - 76,
		emptyText = "No sales in this period yet.",
	})
	dash.graph:SetPoint("BOTTOMLEFT", dash.chart, "BOTTOMLEFT", PAD, 8)
	dash.graph:SetYFormatter(function(value) return money(tonumber(value) or 0) end)
	dash.graph:SetTooltipBuilder(function(tip, hit)
		local point = hit and hit.pt or hit
		tip:AddLine(date("%Y-%m-%d", point.at), 1, 1, 1)
		tip:AddLine(pe:FormatCopperFull(tonumber(point.value) or 0))
	end)

	-- What sells: one row per item, sortable by how much, how many and how often.
	dash.items = createCard(pe, dash, "What sells")
	attachTable(pe, dash.items, {
		itemColumn(),
		numberColumn("sales", "Sales", 46, count),
		numberColumn("units", "Units", 46, count, true),
		numberColumn("net", "Earned", 78, money),
		numberColumn("avgUnit", "Each", 70, money, true),
		numberColumn("perWeek", "A week", 56, function(n) return string.format("%.1f", n) end),
	}, "net", function(row)
		return {
			{ "Sales", string.format("%s, %s items", count(row.sales), count(row.units)) },
			{ "Earned after cut", pe:FormatCopperFull(row.net) },
			{ "Sold for", pe:FormatCopperFull(row.gross) },
			{ "Sales a week", string.format("%.1f", row.perWeek) },
			{ "Last sold", pe:FormatScanTimestamp(row.lastAt) },
		}
	end)

	-- Latest sales, newest first.
	dash.recent = createCard(pe, dash, "Latest sales")
	attachTable(pe, dash.recent, {
		itemColumn(),
		numberColumn("net", "Earned", 78, money),
		{ id = "ts", label = "When", justifyH = "RIGHT", width = 104, sortable = true, defaultSort = "desc",
			sortValue = function(row) return row.ts end,
			getText = function(row) return pe:FormatScanTimestamp(row.ts) end },
	}, "ts", function(row)
		return {
			{ "Earned after cut", pe:FormatCopperFull(row.net) },
			{ "Sold for", pe:FormatCopperFull(row.gross) },
			{ "Buyer", row.buyer or "several buyers" },
			{ "Sold by", row.characterKey },
		}
	end)

	function dash:Layout()
		pe:LayoutEvenRow(self.statsRow, self.stats, 0, GAP)
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

	function dash:Refresh()
		local days = tonumber(pe:GetSetting("sales.periodDays", 30)) or 30
		for _, button in ipairs(self.periodButtons) do
			pe:StyleShellButton(button, button.days == days)
		end
		-- The ledger lives in the Inventory module; without it the view stays empty.
		local summary = pe.GetSalesSummary and pe:GetSalesSummary(days > 0 and days or nil)
			or pe.ForeverLogic.SummarizeSales({}, time(), nil)
		local totals = summary.totals

		local bestEarner, mostOften
		for _, item in ipairs(summary.items) do
			item._rowIdentity = tostring(item.itemID or item.name)
			item.name = item.name or pe:GetItemDisplayName(item.itemID)
			if not bestEarner or item.net > bestEarner.net then
				bestEarner = item
			end
			if not mostOften or item.sales > mostOften.sales then
				mostOften = item
			end
		end
		self.stats[1]:SetValues("Earned from sales", money(totals.net),
			string.format("%s a day · %s paid in auction cut", money(totals.net / summary.spanDays), money(totals.gross - totals.net)),
			totals.net > 0 and "success" or nil)
		self.stats[2]:SetValues("Sales", count(totals.sales),
			string.format("%s items of %s kinds", count(totals.units), count(#summary.items)))
		self.stats[3]:SetValues("Best earner", bestEarner and bestEarner.name or "-",
			bestEarner and (money(bestEarner.net) .. " earned") or "Nothing sold in this period", bestEarner and "gold" or nil)
		self.stats[4]:SetValues("Sells most often", mostOften and mostOften.name or "-",
			mostOften and string.format("%s sales, %.1f a week", count(mostOften.sales), mostOften.perWeek) or "Nothing sold in this period")

		self.graph:SetAccentColor(pe:GetTheme().accent)
		self.graph:SetSeries(summary.daily)
		self.graph:SetSecondarySeries({})
		self.graph:SetQuantitySeries({})
		self.graph:Refresh()

		local recent = {}
		for index = 1, math.min(RECENT_ROWS, #summary.recent) do
			local event = summary.recent[index]
			local quantity = tonumber(event.quantity) or 1
			local name = event.itemName or pe:GetItemDisplayName(event.itemID)
			recent[index] = {
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
		self.items.table:SetRows(summary.items)
		self.items.table:Refresh()
		self.recent.table:SetRows(recent)
		self.recent.table:Refresh()
		self:Layout()
	end

	dash:SetScript("OnSizeChanged", function()
		dash:Layout()
	end)
	dash:Layout()
	return dash
end
