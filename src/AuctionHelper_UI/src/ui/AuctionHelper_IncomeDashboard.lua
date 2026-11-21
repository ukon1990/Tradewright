local _, AuctionHelper = ...

-- Income (Overview → Income): where gold comes from and where it goes. Headline numbers,
-- gold in and out per day, one row per source, and the item types that earn at the auction house.
-- Sources come from the gold-change log, the auction split from sale origins.

local GAP = 12
local PAD = 10
local STATS_HEIGHT = 58
local CHART_HEIGHT = 190
local TOP_ITEMS = 3

local SOURCE_LABELS = {
	vendor = "Vendor", quest = "Quests", loot = "Looted coin", auction = "Auction house",
	mail = "Mail", trade = "Trade", other = "Other",
}
local ORIGINS = { { "crafted", "Crafted" }, { "resold", "Resold" }, { "farmed", "Farmed" }, { "unknown", "Not known" } }

local function percent(fraction)
	return fraction and string.format("%.0f%%", fraction * 100) or "-"
end

local function textColumn(id, label)
	return {
		id = id, label = label, flex = 1, minWidth = 110, sortable = true,
		sortValue = function(row) return row[id] or "" end,
		getText = function(row) return row[id] or "-" end,
	}
end

local function showTooltip(owner, title, lines)
	local muted = AuctionHelper:GetTheme().textMuted
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine(title, 1, 1, 1)
	for _, line in ipairs(lines) do
		GameTooltip:AddDoubleLine(line[1], line[2], muted.r, muted.g, muted.b, 1, 1, 1)
	end
	GameTooltip:Show()
end

local function attachTable(pe, card, spec)
	local tbl = pe:CreateReusableTable(card, {
		autoFitToScroll = true,
		rowHeight = 24,
		sortKey = spec.sortKey,
		sortAsc = false,
		emptyTitle = spec.emptyTitle,
		emptyHint = spec.emptyHint,
		onRowEnter = function(rowFrame, row)
			if row then
				showTooltip(rowFrame, row.label, spec.tooltip(row))
			end
		end,
		onRowLeave = function()
			GameTooltip:Hide()
		end,
	})
	tbl:SetColumns(spec.columns)
	tbl.frame:SetPoint("TOPLEFT", card.heading, "BOTTOMLEFT", 0, -10)
	tbl.frame:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -PAD, PAD)
	card.table = tbl
end

local function sourceColumns(pe)
	local column = pe.DashboardNumberColumn
	local money = function(copper) return pe:FormatCopperShort(copper) end
	local signed = function(copper) return pe:FormatSignedMoney(copper) end
	return {
		textColumn("label", "Source"),
		column("gain", "In", 78, money),
		column("spend", "Out", 78, money, true),
		column("net", "Net", 84, signed),
		column("share", "Share", 52, percent),
		column("perDay", "A day", 78, signed, true),
	}
end

local function typeColumns(pe)
	local column = pe.DashboardNumberColumn
	return {
		textColumn("label", "Item type"),
		column("sales", "Sales", 46, function(n) return pe:FormatNumberGrouped(n) end),
		column("net", "Earned", 78, function(copper) return pe:FormatCopperShort(copper) end),
		column("share", "Share", 52, percent),
		column("sellRate", "Sold", 46, percent, true),
	}
end

-- The auction row's tooltip: how its sales split by where the items came from.
local function sourceTooltip(pe, dash, row)
	local lines = {
		{ "Gold in", pe:FormatCopperFull(row.gain) },
		{ "Gold out", pe:FormatCopperFull(row.spend) },
	}
	if row.source == "auction" then
		for _, origin in ipairs(ORIGINS) do
			local copper = dash.split[origin[1]]
			if copper and copper > 0 then
				lines[#lines + 1] = { "Sales, " .. origin[2]:lower(), pe:FormatCopperFull(copper) }
			end
		end
	end
	return lines
end

local function typeTooltip(pe, row)
	local items = {}
	for key, net in pairs(row.items) do
		items[#items + 1] = { key = key, net = net }
	end
	table.sort(items, function(a, b) return a.net > b.net end)
	local lines = { { "Sold", string.format("%d sales, %d items", row.sales, row.units) } }
	for index = 1, math.min(TOP_ITEMS, #items) do
		local key = items[index].key
		local name = type(key) == "number" and pe:GetItemDisplayName(key) or tostring(key)
		lines[#lines + 1] = { name, pe:FormatCopperFull(items[index].net) }
	end
	return lines
end

-- "Trade Goods · Leather" for an item, from the client's item classes.
local function classOf(itemID)
	local getInfo = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
	if not getInfo or not itemID then
		return nil
	end
	local _, typeName, subTypeName, _, _, classID, subClassID = getInfo(itemID)
	if not classID then
		return nil
	end
	local label = subTypeName and subTypeName ~= typeName and (typeName .. " · " .. subTypeName) or typeName
	return classID .. ":" .. tostring(subClassID), label
end

local function createHeader(pe, dash)
	dash.statsRow = CreateFrame("Frame", nil, dash)
	dash.statsRow:SetPoint("TOPLEFT")
	dash.statsRow:SetPoint("TOPRIGHT")
	dash.statsRow:SetHeight(STATS_HEIGHT)
	dash.stats = {}
	for index = 1, 4 do
		dash.stats[index] = pe:CreateStat(dash.statsRow)
	end
	dash.chart = pe:CreateDashboardCard(dash, "Gold in and out, per day")
	dash.chart:SetPoint("TOPLEFT", dash.statsRow, "BOTTOMLEFT", 0, -GAP)
	dash.chart:SetPoint("TOPRIGHT", dash.statsRow, "BOTTOMRIGHT", 0, -GAP)
	dash.chart:SetHeight(CHART_HEIGHT)
	dash.periodButtons = pe:CreatePeriodButtons(dash.chart, function() dash:Refresh() end)
	dash.character = pe:CreateSingleSelectDropdown(dash.chart, {
		width = 150,
		getOptions = function() return pe:GetInventoryCharacterFilterOptions() end,
		getValue = function() return pe:GetSetting("income.character", "all") end,
		setValue = function(value) pe:SetSetting("income.character", value) end,
		onChanged = function() dash:Refresh() end,
		tooltip = "Whose gold to show",
	})
	dash.character:SetPoint("RIGHT", dash.periodButtons[#dash.periodButtons], "LEFT", -8, 0)
	dash.chart.heading:SetPoint("RIGHT", dash.character, "LEFT", -8, 0)
	dash.graph = pe:CreateTimeSeriesGraph(dash.chart, {
		showTitle = false,
		plotHeight = CHART_HEIGHT - 76,
		emptyText = "No gold has come in or gone out in this period yet.",
	})
	dash.graph:SetPoint("BOTTOMLEFT", dash.chart, "BOTTOMLEFT", PAD, 8)
	dash.graph:SetYFormatter(function(value) return pe:FormatCopperShort(tonumber(value) or 0) end)
	dash.graph:SetSeriesLabels("Gold in", "Gold out", nil, "Net")
end

local function createTables(pe, dash)
	dash.sources = pe:CreateDashboardCard(dash, "Where gold comes from")
	attachTable(pe, dash.sources, {
		columns = sourceColumns(pe), sortKey = "gain",
		emptyTitle = "No gold tracked yet",
		emptyHint = "Gold is tracked from the moment this view was added: sell, loot, quest, collect mail.",
		tooltip = function(row) return sourceTooltip(pe, dash, row) end,
	})
	dash.types = pe:CreateDashboardCard(dash, "What item types earn")
	attachTable(pe, dash.types, {
		columns = typeColumns(pe), sortKey = "net",
		emptyTitle = "No auction sales in this period",
		emptyHint = "A sale is added when you collect its gold from the mailbox.",
		tooltip = function(row) return typeTooltip(pe, row) end,
	})
end

local function refreshStats(pe, dash, summary, rows)
	local money = function(copper) return pe:FormatCopperShort(copper) end
	local biggest = rows[1] and rows[1].gain > 0 and rows[1] or nil
	dash.stats[1]:SetValues("Earned", money(summary.gain), string.format("%s a day", money(summary.gain / dash.spanDays)),
		summary.gain > 0 and "success" or nil)
	dash.stats[2]:SetValues("Spent", money(summary.spend), string.format("%s a day", money(summary.spend / dash.spanDays)))
	local net = summary.gain - summary.spend
	dash.stats[3]:SetValues("Net", pe:FormatSignedMoney(net), "Earned minus spent", net >= 0 and "success" or "danger")
	if biggest then
		dash.stats[4]:SetValues("Biggest source", biggest.label, string.format("%s of all gold in", percent(biggest.share)), "gold")
	else
		dash.stats[4]:SetValues("Biggest source", "-", "Nothing earned in this period")
	end
end

local function refreshChart(pe, dash, daily)
	local gains, spends = {}, {}
	for _, point in ipairs(daily) do
		local at = point.day * 86400 + 43200
		gains[#gains + 1] = { at = at, value = point.gain }
		spends[#spends + 1] = { at = at, value = point.spend }
	end
	local theme = pe:GetTheme()
	dash.graph:SetAccentColor(theme.success)
	dash.graph:SetSecondaryAccentColor(theme.danger)
	dash.graph:SetSeries(gains)
	dash.graph:SetSecondarySeries(spends)
	dash.graph:SetQuantitySeries({})
	dash.graph:Refresh()
end

-- Days in the period: the chosen length, or for all time the days since the first gold tracked.
local function periodSpan(days, daily, today)
	if days > 0 then
		return days
	end
	return daily[1] and (today - daily[1].day + 1) or 1
end

local function layout(pe, dash)
	pe:LayoutEvenRow(dash.statsRow, dash.stats, 0, GAP)
	dash.graph:SetWidth(math.max(80, dash.chart:GetWidth() - PAD * 2))
	local half = math.max(200, (dash:GetWidth() - GAP) / 2)
	dash.sources:ClearAllPoints()
	dash.sources:SetPoint("TOPLEFT", dash.chart, "BOTTOMLEFT", 0, -GAP)
	dash.sources:SetPoint("BOTTOMLEFT")
	dash.sources:SetWidth(half)
	dash.types:ClearAllPoints()
	dash.types:SetPoint("TOPLEFT", dash.sources, "TOPRIGHT", GAP, 0)
	dash.types:SetPoint("BOTTOMRIGHT")
end

local function setTableRows(card, rows, identity)
	for _, row in ipairs(rows) do
		row._rowIdentity = row[identity]
	end
	card.table:SetRows(rows)
	card.table:Refresh()
end

local function refresh(pe, dash)
	local IncomeLogic = pe.IncomeLogic
	local days = pe:StylePeriodButtons(dash.periodButtons)
	local character = pe:GetSetting("income.character", "all")
	character = character ~= "all" and character or nil
	local today = IncomeLogic.DayOf(time())
	local firstDay = days > 0 and today - days + 1 or 0
	local summary = IncomeLogic.SummarizeIncome(pe:GetIncomeDays(), character, firstDay)
	dash.spanDays = periodSpan(days, summary.daily, today)
	local rows = IncomeLogic.SourceRows(summary, dash.spanDays)
	for _, row in ipairs(rows) do
		row.label = SOURCE_LABELS[row.source] or row.source
	end
	local events, since = pe:GetLedgerEvents(), firstDay * 86400
	dash.split = IncomeLogic.SplitSalesByOrigin(events, pe:GetSaleOrigins(), since, character)
	refreshStats(pe, dash, summary, rows)
	refreshChart(pe, dash, summary.daily)
	setTableRows(dash.sources, rows, "source")
	setTableRows(dash.types, IncomeLogic.SummarizeItemTypes(events, since, character, classOf), "key")
	layout(pe, dash)
end

function AuctionHelper:CreateIncomeDashboard(parent)
	local pe = self
	local dash = CreateFrame("Frame", nil, parent)
	dash:SetAllPoints()
	dash.split = {}
	createHeader(pe, dash)
	createTables(pe, dash)
	function dash:Layout()
		layout(pe, self)
	end
	function dash:Refresh()
		refresh(pe, self)
	end
	dash:SetScript("OnSizeChanged", function()
		layout(pe, dash)
	end)
	layout(pe, dash)
	return dash
end
