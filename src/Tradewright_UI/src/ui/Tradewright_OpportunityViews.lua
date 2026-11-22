local Tradewright = select(2, ...)

-- The lists of the Opportunities tab. Each view supplies: id, label, getRows(pe, onReady) → rows, insights, funnel,
-- columns(pe), detailRows(pe, row), riskText(pe, row), subtitle(pe, row), tooltipPairs(pe, row),
-- setStats(pe, stats, rows, insights) with the four stat tiles left to right, footer(pe, rows, insights), emptyTitle, emptyHint.
-- Both lists sort on a column with the id "profit", so the table keeps its sort across a switch.

-- "12" for a busy item, "0.4" for a slow one.
local function perDayText(pe, perDay)
	if perDay >= 10 then
		return pe:FormatNumberGrouped(math.floor(perDay + 0.5))
	end
	return string.format("%.1f", perDay)
end

-- "Sales a day", with a "?" when the estimate rests on few scan pairs or on own sales alone.
local function sellsColumn(pe, width)
	return {
		id = "sellsPerDay", label = "Sales a day", justifyH = "RIGHT", width = width, sortable = true, defaultSort = "desc",
		sortValue = function(row) return row.sellsPerDay or 0 end,
		getText = function(row) return perDayText(pe, row.sellsPerDay) .. (pe.FlipLogic.SellsUnsure(row) and " ?" or "") end,
	}
end

-- Where a row's sales a day comes from.
local function sellsSourceText(pe, row)
	local pairsText = string.format("%s scan pairs", pe:FormatNumberGrouped(row.sellsPairs or 0))
	if row.sellsSource == "own" then
		return "your own sales"
	elseif row.sellsSource == "both" then
		return pairsText .. " and your sales"
	end
	return pairsText
end

-- The two side-pane lines about sales.
local function sellsLines(pe, row)
	return { "Sales a day, estimated", perDayText(pe, row.sellsPerDay) },
		{ "Estimated from", sellsSourceText(pe, row), pe.FlipLogic.SellsUnsure(row) and "warning" or nil }
end

local function signedColumn(pe, label, field)
	return {
		id = "profit", label = label, justifyH = "RIGHT", width = 84, sortable = true, defaultSort = "desc",
		sortValue = function(row) return row[field] or 0 end,
		getText = function(row) return pe:FormatSignedMoney(row[field]) end,
	}
end

-- An early row's second line starts with how few days its usual price rests on.
local function itemColumn(pe, detail)
	return pe:ItemColumn({
		label = "Item", defaultSort = "asc",
		getName = function(row) return pe:GetItemDisplayName(row.itemID) end,
		getDetail = function(row)
			if row.early then
				return pe:Colorize(string.format("Early · %d days of prices", row.usualDays or 0), "warning") .. " · " .. detail(pe, row)
			end
			return detail(pe, row)
		end,
	})
end

-- What the sales estimate cannot tell, when it rests on little.
local function sellsCaveat(row)
	if row.sellsSource == "own" then
		return " Only your own sales are known. Scan at least twice within a day to see the whole market."
	elseif row.sellsConfidence == "few" then
		return string.format(" Sales were seen over only %d pairs of scans, and cancelled or expired auctions count as sold,"
			.. " so it may sell slower.", row.sellsPairs or 0)
	end
	return ""
end

-- The risk text of a list, led by a warning on early rows and followed by one on thin sales data.
local function withDataWarnings(riskText)
	return function(pe, row)
		local early = row.early and string.format("Usual price from only %d days, so one odd day moves it a lot. ", row.usualDays or 0) or ""
		return early .. riskText(pe, row) .. sellsCaveat(row)
	end
end

-- Sum of `field` over the rows that are not early, and a note naming the early rows left out.
local function settledSum(pe, rows, field, note)
	local total, early = pe.FlipLogic.SumSettled(rows, field)
	if early > 0 then
		note = string.format("%s · %d early not counted", note, early)
	end
	return total, note, #rows - early
end

-- "Usual price known for N of M items", and what is missing.
local function coverageStat(pe, stat, insights)
	local coverage = pe:GetHistoryCoverage(insights)
	local note
	if coverage.full == 0 then
		note = string.format("Best item has %d of 5 scan days · today's scans count tomorrow", coverage.bestDays)
	elseif (coverage.withSells or 0) < coverage.full / 2 then
		note = string.format("Only %s know what sells · scan twice within a day", pe:FormatNumberGrouped(coverage.withSells or 0))
	elseif coverage.early > 0 then
		local shown = pe:GetSetting("opportunities.allowEarly", false) and ", shown as Early" or ", hidden in Settings"
		note = string.format("%s more have 2 to 4 days%s", pe:FormatNumberGrouped(coverage.early), shown)
	else
		note = string.format("5+ scan days in the last %d days", pe:GetSetting("auction.usualPriceDays", 14))
	end
	local value = string.format("%s of %s", pe:FormatNumberGrouped(coverage.full), pe:FormatNumberGrouped(coverage.scanned))
	stat:SetValues("Usual price known for", value, note, coverage.full == 0 and "warning" or nil)
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
	local detail = pe:FormatPercent(row.discount) .. " below usual"
	if row.fewSales then
		return detail .. " · few sales seen"
	elseif row.slow then
		return detail .. " · sells slowly"
	elseif row.listedUnder then
		return string.format("%s · %s listed below %s", detail, pe:FormatNumberGrouped(row.listedUnder), pe:FormatCopperShort(row.limitPrice))
	end
	return detail
end

local function flipColumns(pe)
	return {
		itemColumn(pe, flipDetail),
		pe:MoneyColumn({ id = "price", label = "Buy at", width = 76 }),
		pe:MoneyColumn({ id = "usual", label = "Usual", width = 76 }),
		{
			id = "buyQty", label = "Buy", justifyH = "RIGHT", width = 44, sortable = true, defaultSort = "desc",
			sortValue = function(row) return row.buyQty or 0 end,
			getText = function(row) return row.buyQty and pe:FormatNumberGrouped(row.buyQty) or "-" end,
		},
		signedColumn(pe, "Profit", "profit"),
		sellsColumn(pe, 70),
	}
end

local function flipDetailRows(pe, row)
	local units = row.buyQty or 1
	local sells, source = sellsLines(pe, row)
	return {
		{ "Cheapest now", pe:FormatCopperFull(row.price) },
		{ string.format("Usual price, %d days", row.usualDays or 0), pe:FormatCopperFull(row.usual) },
		{ string.format("Sale after %s cut", pe:FormatPercent(1 - row.saleNet / row.usual)), pe:FormatCopperFull(row.saleNet) },
		{ "Deposit lost on unsold postings, each", row.depositLoss > 0 and pe:FormatCopperFull(row.depositLoss) or "unknown" },
		{ "Profit each", pe:FormatSignedMoney(row.profitEach), "success" },
		{ "Return", pe:FormatPercent(row.roi) },
		{ "Listed below " .. pe:FormatCopperShort(row.limitPrice), row.listedUnder and pe:FormatNumberGrouped(row.listedUnder) or "-" },
		sells, source,
		{ string.format("Buy %s and spend", pe:FormatNumberGrouped(units)), pe:FormatCopperFull(row.cost) },
		{ "Profit if all sell at the usual price", pe:FormatSignedMoney(row.profit), "success" },
	}
end

local function flipRiskText(pe, row)
	local range = string.format("Its price stayed between %s and %s on the middle half of the last %d days.",
		pe:FormatCopperShort(row.usualLow or row.usual), pe:FormatCopperShort(row.usualHigh or row.usual), row.usualDays or 0)
	local breakEven = string.format(" Below %s you lose gold on each one.", pe:FormatCopperShort(row.breakEven))
	local caveat = row.buyQty and "" or " No price steps are kept, so the quantity at this price is unknown."
	return range .. breakEven .. caveat
end

local function flipStats(pe, stats, rows, insights)
	local profitTile, goldNeededTile, coverageTile, cutTile = unpack(stats)
	local opts = pe:GetFlipOptions()
	local profit, note, settled = settledSum(pe, rows, "profit", "After the auction cut")
	profitTile:SetValues(string.format("Expected profit, all %d", settled), pe:FormatSignedMoney(profit), note, "success")
	goldNeededTile:SetValues("Gold needed", pe:FormatCopperShort((settledSum(pe, rows, "cost", ""))), "You have " .. pe:FormatCopperShort(GetMoney()))
	coverageStat(pe, coverageTile, insights)
	cutTile:SetValues("Auction cut", pe:FormatPercent(opts.cut), "Last scan " .. lastScanText(pe, insights))
end

local flips = {
	id = "flips", label = "Flips",
	emptyTitle = "No flips right now",
	emptyHint = "Scan the auction house on a few different days to build usual prices.",
	getRows = function(pe, onReady) return pe:GetFlipRows(onReady) end,
	columns = flipColumns,
	detailRows = flipDetailRows,
	riskText = withDataWarnings(flipRiskText),
	setStats = flipStats,
	subtitle = function(pe, row) return pe:FormatPercent(row.discount) .. " below its usual price" end,
	tooltipPairs = function(pe, row) return { { "Profit each after the cut", pe:FormatSignedMoney(row and row.profitEach) } } end,
	footer = function(pe, rows, insights)
		return string.format("%d flips from %s items", #rows, pe:FormatNumberGrouped(insights.itemCount or 0)),
			"Auction cut " .. pe:DescribeAuctionCut() .. " · Buy is capped at a share of a day's sales"
	end,
}

-- ---------- Sure things: listed under vendor price ----------

local function vendorDetail(pe, row)
	if not row.qtyKnown then
		return "Below vendor price · quantity at this price unknown"
	end
	return string.format("%s listed below vendor price", pe:FormatNumberGrouped(row.qty))
end

local function vendorColumns(pe)
	return {
		itemColumn(pe, vendorDetail),
		pe:MoneyColumn({ id = "price", label = "Listed at", width = 76 }),
		pe:MoneyColumn({ id = "vendorSell", label = "Vendor pays", width = 84 }),
		{
			id = "qty", label = "Qty", justifyH = "RIGHT", width = 50, sortable = true, defaultSort = "desc",
			sortValue = function(row) return row.qty or 0 end,
			getText = function(row) return row.qtyKnown and pe:FormatNumberGrouped(row.qty) or "-" end,
		},
		signedColumn(pe, "Profit", "gain"),
	}
end

local function vendorDetailRows(pe, row)
	return {
		{ "Cheapest listing", pe:FormatCopperFull(row.price) },
		{ "A vendor pays", pe:FormatCopperFull(row.vendorSell) },
		{ "", "" },
		{ "Units below vendor price", row.qtyKnown and pe:FormatNumberGrouped(row.qty) or "at least 1" },
		{ "Cost to buy them", pe:FormatCopperFull(row.cost) },
		{ "Vendor pays in total", pe:FormatCopperFull(row.qty * row.vendorSell) },
		{ "Profit", pe:FormatSignedMoney(row.gain), "success" },
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
	local gainTile, goldNeededTile, itemsTile, lastScanTile = unpack(stats)
	gainTile:SetValues(string.format("Profit, all %d", #rows), pe:FormatSignedMoney(sumOf(rows, "gain")), "Sold to a vendor, no auction cut", "success")
	goldNeededTile:SetValues("Gold needed", pe:FormatCopperShort(sumOf(rows, "cost")), "You have " .. pe:FormatCopperShort(GetMoney()))
	itemsTile:SetValues("Items", tostring(#rows), "Listed below their vendor price")
	lastScanTile:SetValues("Last scan", lastScanText(pe, insights), "Listings may have changed since")
end

local vendor = {
	id = "vendor", label = "Sure things",
	emptyTitle = "Nothing below vendor price",
	emptyHint = "No item in the last scan is listed for less than a vendor pays.",
	getRows = function(pe, onReady) return pe:GetVendorRows(onReady) end,
	columns = vendorColumns,
	detailRows = vendorDetailRows,
	riskText = vendorRiskText,
	setStats = vendorStats,
	subtitle = function(pe, row) return "Listed below the " .. pe:FormatCopperShort(row.vendorSell) .. " a vendor pays" end,
	tooltipPairs = function(pe, row) return { { "A vendor pays", pe:FormatCopperFull(row and row.vendorSell) } } end,
	footer = function(pe, rows, insights)
		return string.format("%d items from %s scanned", #rows, pe:FormatNumberGrouped(insights.itemCount or 0)),
			"Profit = vendor price minus what you pay"
	end,
}

-- ---------- Price gaps: a few cheap listings under a much higher next price ----------

local function daysText(days)
	if days <= 1 then
		return "sells out in under a day"
	end
	return string.format("takes about %d days to sell", math.floor(days + 0.5))
end

local function gapDetail(pe, row)
	return string.format("Buy %s · %s", pe:FormatNumberGrouped(row.buyQty), daysText(row.daysToSell))
end

local function gapColumns(pe)
	return {
		itemColumn(pe, gapDetail),
		pe:MoneyColumn({ id = "price", label = "Cheapest", width = 70 }),
		pe:MoneyColumn({ id = "nextPrice", label = "Next price", width = 70 }),
		pe:MoneyColumn({ id = "cost", label = "To clear", width = 74 }),
		signedColumn(pe, "Profit if it holds", "gain"),
		sellsColumn(pe, 66),
	}
end

-- The sums, then the cheapest price levels with the gap after the ones to buy.
local function gapDetailRows(pe, row)
	local sells, source = sellsLines(pe, row)
	local rows = {
		{ string.format("Cost to clear, %s", pe:FormatNumberGrouped(row.buyQty)), pe:FormatCopperFull(row.cost) },
		{ "Relist at", pe:FormatCopperFull(row.nextPrice) },
		{ "Profit if all sell", pe:FormatSignedMoney(row.gain), "success" },
		sells, source,
		{ "Already waiting at that price", pe:FormatNumberGrouped(row.waitingAtNext) },
		{ "", "" },
	}
	for index = 1, math.min(#row.steps, 8), 2 do
		local price = row.steps[index]
		local label = price < row.nextPrice and "Buy at " or "Stays at "
		rows[#rows + 1] = { label .. pe:FormatCopperShort(price), "x" .. pe:FormatNumberGrouped(row.steps[index + 1]) }
	end
	return rows
end

local function gapRiskText(pe, row)
	local text = "Anyone can list under you before these sell, and the listings come from your last scan."
	if row.waitingAtNext > 0 then
		text = text .. string.format(" %s already wait at %s, so yours may sell after them unless you list lower.",
			pe:FormatNumberGrouped(row.waitingAtNext), pe:FormatCopperShort(row.nextPrice))
	end
	return text
end

local function gapStats(pe, stats, rows, insights)
	local gainTile, goldNeededTile, riskTile, lastScanTile = unpack(stats)
	local gain, note, settled = settledSum(pe, rows, "gain", "After the auction cut")
	gainTile:SetValues(string.format("Profit if all %d hold", settled), pe:FormatSignedMoney(gain), note, "warning")
	goldNeededTile:SetValues("Gold needed", pe:FormatCopperShort((settledSum(pe, rows, "cost", ""))), "You have " .. pe:FormatCopperShort(GetMoney()))
	riskTile:SetValues("Risky", "Read first", "Pays only if nobody lists under you", "warning")
	lastScanTile:SetValues("Last scan", lastScanText(pe, insights), "Listings may have changed since")
end

local gaps = {
	id = "gaps", label = "Price gaps",
	emptyTitle = "No price gaps",
	emptyHint = "No item in the last full scan has a few cheap listings below a much higher price.",
	getRows = function(pe, onReady) return pe:GetGapRows(onReady) end,
	columns = gapColumns,
	detailRows = gapDetailRows,
	riskText = withDataWarnings(gapRiskText),
	setStats = gapStats,
	subtitle = function(pe, row) return "Risky · next price is " .. pe:FormatPercent(row.gapPct) .. " higher" end,
	tooltipPairs = function(pe, row) return { { "Cost to clear", pe:FormatCopperFull(row and row.cost) } } end,
	footer = function(pe, rows, insights)
		return string.format("%d price gaps from %s items", #rows, pe:FormatNumberGrouped(insights.itemCount or 0)),
			"Risky: profit counts the " .. pe:DescribeAuctionCut() .. " cut, not undercuts"
	end,
}

-- ---------- Sell now: owned items priced above usual that sell ----------

-- One candidate per owned item with a scanned price, a usual price and a sales-a-day estimate.
local function sellCandidates(pe, insights)
	local items, owned, scanned = {}, 0, 0
	for _, inv in ipairs(pe:BuildInventoryRowsAggregatedByItem(pe.db, {}, "") or {}) do
		local market = insights.byItemID[tonumber(inv.itemID)]
		owned, scanned = owned + 1, scanned + (market and 1 or 0)
		local usual, early
		if market then
			usual, early = pe:GetOpportunityUsual(market.storageKey)
		end
		local sells = usual and pe:GetSellsPerDay(market.storageKey)
		if sells then
			items[#items + 1] = pe.FlipLogic.SetSells({
				itemID = tonumber(inv.itemID), storageKey = market.storageKey, total = inv.total, bags = inv.bags, bank = inv.bank,
				price = market.price, usual = usual.usual, early = early or nil, usualDays = usual.days,
			}, sells)
		end
	end
	return items, { { key = "owned", count = owned }, { key = "scanned", count = scanned }, { key = "known", count = #items } }
end

--- "Sell now" rows, most worth first, the insights and the funnel, or nil while the market insights
--- are still being built (`onReady` then fires). Rebuilt at most every 10 seconds: bags change
--- without a new scan.
function Tradewright:GetSellNowRows(onReady)
	local pe = self
	local insights = pe:GetMarketInsights(onReady)
	if not insights then
		return nil
	end
	local state = pe:GetState()
	local opts = pe:GetFlipOptions()
	local revision = table.concat({ tostring(insights.builtAt), math.floor(time() / 10), tostring(opts.allowEarly) }, ":")
	if state.sellNowRevision ~= revision then
		local candidates, funnel = sellCandidates(pe, insights)
		local rows = pe.FlipLogic.CarryOver(pe.FlipLogic.BuildSellNowRows(candidates, { cut = opts.cut }), candidates)
		for _, row in ipairs(rows) do
			row._rowIdentity = tostring(row.itemID)
		end
		funnel[#funnel + 1] = { key = "worth", count = #rows }
		state.sellNowRows, state.sellNowRevision, state.sellNowFunnel = rows, revision, funnel
	end
	return state.sellNowRows, insights, state.sellNowFunnel
end

local function whereText(pe, row)
	return string.format("%s bags · %s bank", pe:FormatNumberGrouped(row.bags or 0), pe:FormatNumberGrouped(row.bank or 0))
end

local function sellDetail(pe, row)
	if row.slow then
		return whereText(pe, row) .. " · more than a day of sales"
	end
	return whereText(pe, row)
end

local function sellColumns(pe)
	return {
		itemColumn(pe, sellDetail),
		pe:MoneyColumn({ id = "price", label = "Price", width = 70 }),
		{
			id = "premium", label = "Vs usual", justifyH = "RIGHT", width = 60, sortable = true, defaultSort = "desc",
			sortValue = function(row) return row.premium or 0 end,
			getText = function(row) return "+" .. pe:FormatPercent(row.premium) end,
		},
		{
			id = "total", label = "Owned", justifyH = "RIGHT", width = 56, sortable = true, defaultSort = "desc",
			sortValue = function(row) return row.total or 0 end,
			getText = function(row) return pe:FormatNumberGrouped(row.total) end,
		},
		signedColumn(pe, "Worth", "worth"),
		sellsColumn(pe, 66),
	}
end

local function sellDetailRows(pe, row)
	local sells, source = sellsLines(pe, row)
	return {
		{ "Lowest price now", pe:FormatCopperFull(row.price) },
		{ "Usual price", pe:FormatCopperFull(row.usual) },
		{ "Above usual by", pe:FormatPercent(row.premium), "success" },
		{ "", "" },
		{ "You own", pe:FormatNumberGrouped(row.total) },
		{ "Where", whereText(pe, row) },
		{ "Worth after the cut", pe:FormatCopperFull(row.worth), "success" },
		{ "", "" },
		sells, source,
		{ "Your stock is", string.format("%.1f days of sales", row.daysToSell) },
	}
end

local function sellRiskText(pe, row)
	local text = "Worth assumes every one sells at today's lowest price. Prices above usual tend to come back down."
	if row.slow then
		text = text .. string.format(" You own more than a day of sales, so listing all %s at once will likely push the price down.",
			pe:FormatNumberGrouped(row.total))
	end
	return text
end

local function sellStats(pe, stats, rows, insights)
	local worthTile, coverageTile, thresholdTile, lastScanTile = unpack(stats)
	local worth, note, settled = settledSum(pe, rows, "worth", "After the auction cut")
	worthTile:SetValues(string.format("Worth, all %d", settled), pe:FormatCopperShort(worth), note, "success")
	coverageStat(pe, coverageTile, insights)
	thresholdTile:SetValues("Counts as above usual", "10% or more", "Against the usual price of your scans")
	lastScanTile:SetValues("Last scan", lastScanText(pe, insights), "Prices may have changed since")
end

local sell = {
	id = "sell", label = "Sell now",
	emptyTitle = "Nothing to sell right now",
	emptyHint = "Nothing you own is priced 10% or more above its usual price and known to sell.",
	getRows = function(pe, onReady) return pe:GetSellNowRows(onReady) end,
	columns = sellColumns,
	detailRows = sellDetailRows,
	riskText = withDataWarnings(sellRiskText),
	setStats = sellStats,
	subtitle = function(pe, row) return pe:FormatPercent(row.premium) .. " above its usual price" end,
	tooltipPairs = function(pe, row) return { { "Worth after the cut", pe:FormatCopperFull(row and row.worth) } } end,
	footer = function(pe, rows)
		return string.format("%d of your items", #rows),
			"Worth = owned at today's lowest price, after the " .. pe:DescribeAuctionCut() .. " cut"
	end,
}

Tradewright.OpportunityViews = { flips, vendor, gaps, sell }
