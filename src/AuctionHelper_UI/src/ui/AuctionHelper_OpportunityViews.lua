local ProfessionExporter = select(2, ...)

-- The lists of the Opportunities tab. Each view supplies: id, label, getRows(pe, onReady),
-- columns(pe), detailRows(pe, row), riskText(pe, row), subtitle(pe, row), tooltipPairs(pe, row),
-- setStats(pe, stats, rows, insights), footer(pe, rows, insights), emptyTitle, emptyHint.
-- Both lists sort on a column with the id "profit", so the table keeps its sort across a switch.

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

local function moneyColumn(pe, id, label, field, width)
	return {
		id = id, label = label, justifyH = "RIGHT", width = width or 76, sortable = true, defaultSort = "desc",
		sortValue = function(row) return row[field] or 0 end,
		getText = function(row) return pe:FormatCopperShort(row[field]) end,
	}
end

local function signedColumn(pe, label, field)
	return {
		id = "profit", label = label, justifyH = "RIGHT", width = 84, sortable = true, defaultSort = "desc",
		sortValue = function(row) return row[field] or 0 end,
		getText = function(row) return pe:FormatSignedMoney(row[field]) end,
	}
end

local function itemColumn(pe, detail)
	return pe:CreateItemColumn({
		label = "Item", defaultSort = "asc",
		getItemID = function(row) return row.itemID end,
		getName = function(row) return pe:GetItemDisplayName(row.itemID) end,
		getDetail = function(row) return detail(pe, row) end,
	})
end

local function lastScanText(pe, insights)
	return insights.lastSeenAt and pe:FormatScanTimestamp(insights.lastSeenAt) or "not yet"
end

local function sumOf(rows, field)
	local total = 0
	for _, row in ipairs(rows) do
		total = total + (row[field] or 0)
	end
	return total
end

-- ---------- Flips ----------

-- Second line of a flip row: how far under usual, and the caveat that matters most.
local function flipDetail(pe, row)
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
	return {
		itemColumn(pe, flipDetail),
		moneyColumn(pe, "price", "Buy at", "price"),
		moneyColumn(pe, "usual", "Usual", "usual"),
		{
			id = "buyQty", label = "Buy", justifyH = "RIGHT", width = 44, sortable = true, defaultSort = "desc",
			sortValue = function(row) return row.buyQty or 0 end,
			getText = function(row) return row.buyQty and pe:FormatNumberGrouped(row.buyQty) or "-" end,
		},
		signedColumn(pe, "Profit", "profit"),
		{
			id = "sellsPerDay", label = "Sells a day", justifyH = "RIGHT", width = 70, sortable = true, defaultSort = "desc",
			sortValue = function(row) return row.sellsPerDay or 0 end,
			getText = function(row) return perDayText(pe, row.sellsPerDay) end,
		},
	}
end

local function flipDetailRows(pe, row)
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

local function flipRiskText(pe, row)
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

local function flipStats(pe, stats, rows, insights)
	local opts = pe:GetFlipOptions()
	stats[1]:SetValues(string.format("Expected profit, all %d", #rows), pe:FormatSignedMoney(sumOf(rows, "profit")), "After the auction cut", "success")
	stats[2]:SetValues("Gold needed", pe:FormatCopperShort(sumOf(rows, "cost")), "You have " .. pe:FormatCopperShort(GetMoney()))
	stats[3]:SetValues("Usual price from", pe:GetSetting("auction.usualPriceDays", 14) .. " days", "Middle price of your scans")
	stats[4]:SetValues("Auction cut", percent(opts.cut), "Last scan " .. lastScanText(pe, insights))
end

local flips = {
	id = "flips", label = "Flips",
	emptyTitle = "No flips right now",
	emptyHint = "Scan the auction house on a few different days to build usual prices.",
	getRows = function(pe, onReady) return pe:GetFlipRows(onReady) end,
	columns = flipColumns,
	detailRows = flipDetailRows,
	riskText = flipRiskText,
	setStats = flipStats,
	subtitle = function(_, row) return percent(row.discount) .. " under its usual price" end,
	tooltipPairs = function(pe, row) return { { "Profit each after the cut", pe:FormatSignedMoney(row and row.profitEach) } } end,
	footer = function(pe, rows, insights)
		return string.format("%d flips from %s items", #rows, pe:FormatNumberGrouped(insights.itemCount or 0)),
			"Buy is capped at a share of a day's sales"
	end,
}

-- ---------- Sure things: listed under vendor price ----------

local function vendorDetail(pe, row)
	if not row.qtyKnown then
		return "Under vendor price · quantity at this price unknown"
	end
	return string.format("%s listed under vendor price", pe:FormatNumberGrouped(row.qty))
end

local function vendorColumns(pe)
	return {
		itemColumn(pe, vendorDetail),
		moneyColumn(pe, "price", "Listed at", "price"),
		moneyColumn(pe, "vendorSell", "Vendor pays", "vendorSell", 84),
		{
			id = "qty", label = "Qty", justifyH = "RIGHT", width = 50, sortable = true, defaultSort = "desc",
			sortValue = function(row) return row.qty or 0 end,
			getText = function(row) return row.qtyKnown and pe:FormatNumberGrouped(row.qty) or "-" end,
		},
		signedColumn(pe, "Gain", "gain"),
	}
end

local function vendorDetailRows(pe, row)
	return {
		{ "Cheapest listing", pe:FormatCopperFull(row.price) },
		{ "A vendor pays", pe:FormatCopperFull(row.vendorSell) },
		{ "", "" },
		{ "Units under vendor price", row.qtyKnown and pe:FormatNumberGrouped(row.qty) or "at least 1" },
		{ "Cost to buy them", pe:FormatCopperFull(row.cost) },
		{ "Vendor pays in total", pe:FormatCopperFull(row.qty * row.vendorSell) },
		{ "Gain", pe:FormatSignedMoney(row.gain), "success" },
		{ "", "" },
		{ "Bag slots needed", "depends on stack size" },
		{ "Auction cut", "none, sold to a vendor" },
	}
end

local function vendorRiskText(_, row)
	local stale = "The listings may be gone: this comes from your last scan."
	if not row.qtyKnown then
		return stale .. " No price steps are kept for it, so only the cheapest listing is counted."
	end
	return stale .. " Check the vendor's price in the item tooltip before buying many."
end

local function vendorStats(pe, stats, rows, insights)
	stats[1]:SetValues(string.format("Gain, all %d", #rows), pe:FormatSignedMoney(sumOf(rows, "gain")), "Sold to a vendor, no auction cut", "success")
	stats[2]:SetValues("Gold needed", pe:FormatCopperShort(sumOf(rows, "cost")), "You have " .. pe:FormatCopperShort(GetMoney()))
	stats[3]:SetValues("Items", tostring(#rows), "Listed under their vendor price")
	stats[4]:SetValues("Last scan", lastScanText(pe, insights), "Listings may have changed since")
end

local vendor = {
	id = "vendor", label = "Sure things",
	emptyTitle = "Nothing under vendor price",
	emptyHint = "No item in the last scan is listed for less than a vendor pays.",
	getRows = function(pe, onReady) return pe:GetVendorRows(onReady) end,
	columns = vendorColumns,
	detailRows = vendorDetailRows,
	riskText = vendorRiskText,
	setStats = vendorStats,
	subtitle = function(pe, row) return "Listed under the " .. pe:FormatCopperShort(row.vendorSell) .. " a vendor pays" end,
	tooltipPairs = function(pe, row) return { { "A vendor pays", pe:FormatCopperFull(row and row.vendorSell) } } end,
	footer = function(pe, rows, insights)
		return string.format("%d items from %s scanned", #rows, pe:FormatNumberGrouped(insights.itemCount or 0)),
			"Gain = vendor price less what you pay"
	end,
}

ProfessionExporter.OpportunityViews = { flips, vendor }
