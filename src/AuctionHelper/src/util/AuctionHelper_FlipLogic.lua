local _, AuctionHelper = ...

--- Pure flip maths for the Opportunities tab (offline-testable, no WoW API). Builds on MarketSignals.
local FlipLogic = {}
AuctionHelper.FlipLogic = FlipLogic

local DEFAULTS = { minDiscount = 0.25, minProfit = 10000, minSellsPerDay = 1, dayShare = 1 / 3, cut = 0.05 }

local function option(opts, key)
	local value = opts and tonumber(opts[key])
	return value or DEFAULTS[key]
end

-- How many to buy and what it costs. With price steps: everything listed at or under the limit price,
-- capped at a share of a day's sales. Without: one unit at the lowest price, quantity unknown.
local function flipQuantity(item, limitPrice, opts)
	local MS = AuctionHelper.MarketSignals
	if not (item.steps and #item.steps > 0) then
		return { units = 1, cost = item.price }
	end
	local listedUnder = MS.CostToClear(item.steps, limitPrice).qty
	local cap = math.max(1, math.ceil(option(opts, "dayShare") * item.sellsPerDay))
	local buyQty = math.min(listedUnder, cap)
	if buyQty < 1 then
		return nil
	end
	return { units = buyQty, buyQty = buyQty, listedUnder = listedUnder, cost = MS.AverageFill(item.steps, buyQty) * buyQty }
end

-- Why an item is not a flip candidate: "discount" (not far enough under usual, or no price) or "sells"
-- (sells too slowly); nil when it is one.
local function rejectReason(item, opts)
	local usual, price, sells = tonumber(item.usual), tonumber(item.price), tonumber(item.sellsPerDay)
	if not (usual and price and sells) or usual <= 0 or price <= 0 or (usual - price) / usual < option(opts, "minDiscount") then
		return "discount"
	end
	if sells < option(opts, "minSellsPerDay") then
		return "sells"
	end
	return nil
end

--- One flip row for `item = { itemID, storageKey, price, usual, sellsPerDay, confidence, steps, depositLoss }`,
--- or nil and the reason ("discount", "sells" or "profit") when it is not worth showing. Profit is after
--- the cut and the expected deposit loss.
function FlipLogic.BuildFlipRow(item, opts)
	local reason = rejectReason(item, opts)
	if reason then
		return nil, reason
	end
	local cut = option(opts, "cut")
	local limitPrice = item.usual * (1 - option(opts, "minDiscount"))
	local buy = flipQuantity(item, limitPrice, opts)
	local profit = buy and buy.units * item.usual * (1 - cut) - buy.cost - (tonumber(item.depositLoss) or 0) * buy.units
	if not profit or profit < option(opts, "minProfit") then
		return nil, "profit"
	end
	return {
		itemID = item.itemID, storageKey = item.storageKey, price = item.price, usual = item.usual,
		discount = (item.usual - item.price) / item.usual, limitPrice = limitPrice,
		buyQty = buy.buyQty, listedUnder = buy.listedUnder, cost = buy.cost,
		profit = profit, profitEach = profit / buy.units, roi = profit / buy.cost,
		saleNet = item.usual * (1 - cut), breakEven = buy.cost / buy.units / (1 - cut),
		sellsPerDay = item.sellsPerDay, depositLoss = tonumber(item.depositLoss) or 0,
		slow = buy.buyQty ~= nil and buy.buyQty > item.sellsPerDay,
		fewSales = item.confidence == "few",
	}
end

--- Flip rows for a list of items, most profit first. With `drops`, counts the items left out per reason.
function FlipLogic.BuildFlipRows(items, opts, drops)
	local rows = {}
	for _, item in ipairs(items or {}) do
		local row, reason = FlipLogic.BuildFlipRow(item, opts)
		if row then
			rows[#rows + 1] = row
		elseif drops then
			drops[reason] = (drops[reason] or 0) + 1
		end
	end
	table.sort(rows, function(a, b)
		return a.profit > b.profit
	end)
	return rows
end

-- Units listed under `vendorSell` and what they cost. Without price steps: one unit at the lowest price.
local function underVendor(item)
	if not (item.steps and #item.steps > 0) then
		return 1, item.price
	end
	local qty, cost = 0, 0
	for index = 1, #item.steps, 2 do
		if item.steps[index] >= item.vendorSell then
			break
		end
		qty = qty + item.steps[index + 1]
		cost = cost + item.steps[index] * item.steps[index + 1]
	end
	return qty, cost
end

--- One "sure thing" row for `item = { itemID, storageKey, price, vendorSell, steps }`: units listed
--- below what a vendor pays, or nil. The gain has no auction cut: the items are sold to a vendor.
function FlipLogic.BuildVendorRow(item, opts)
	local price, vendorSell = tonumber(item.price), tonumber(item.vendorSell)
	if not (price and vendorSell) or price <= 0 or price >= vendorSell then
		return nil
	end
	local qty, cost = underVendor(item)
	local gain = qty * vendorSell - cost
	if qty < 1 or gain < (opts and tonumber(opts.minGain) or 1000) then
		return nil
	end
	return {
		itemID = item.itemID, storageKey = item.storageKey, price = price, vendorSell = vendorSell,
		qty = qty, cost = cost, gain = gain, qtyKnown = item.steps ~= nil and #item.steps > 0,
	}
end

--- Sure-thing rows for a list of items, most gain first.
function FlipLogic.BuildVendorRows(items, opts)
	local rows = {}
	for _, item in ipairs(items or {}) do
		local row = FlipLogic.BuildVendorRow(item, opts)
		if row then
			rows[#rows + 1] = row
		end
	end
	table.sort(rows, function(a, b)
		return a.gain > b.gain
	end)
	return rows
end

-- Units already listed at exactly `price` in flat price steps.
local function quantityAt(steps, price)
	for index = 1, #steps, 2 do
		if steps[index] == price then
			return steps[index + 1]
		end
	end
	return 0
end

local function gapOption(opts, key, default)
	return opts and tonumber(opts[key]) or default
end

-- A gap is worth showing when the item sells, clearing it is affordable and the next price is one the
-- item has really traded near (at or under the top of its usual range).
local function gapQualifies(item, gap, opts)
	local sells, usualHigh = tonumber(item.sellsPerDay), tonumber(item.usualHigh)
	if not (gap and sells and usualHigh) then
		return false
	end
	return sells >= gapOption(opts, "minSellsPerDay", 5)
		and gap.belowCost <= gapOption(opts, "maxCost", 1000000)
		and gap.nextPrice <= usualHigh
end

--- One price-gap row for `item = { itemID, storageKey, steps, usualHigh, sellsPerDay, deposit }`: a few
--- cheap listings under a much higher next price, or nil. Gain assumes all of them resell at the next price.
function FlipLogic.BuildGapRow(item, opts)
	if not (item.steps and #item.steps >= 4) then
		return nil
	end
	local gap = AuctionHelper.MarketSignals.FindPriceGap(item.steps, gapOption(opts, "minGapPct", 0.25))
	if not gapQualifies(item, gap, opts) then
		return nil
	end
	local cut = gapOption(opts, "cut", 0.05)
	local deposit = (tonumber(item.deposit) or 0) * gap.belowQty
	local gain = gap.belowQty * gap.nextPrice * (1 - cut) - gap.belowCost - deposit
	if gain <= 0 then
		return nil
	end
	return {
		itemID = item.itemID, storageKey = item.storageKey, steps = item.steps,
		price = gap.floorPrice, nextPrice = gap.nextPrice, gapPct = gap.gapPct,
		buyQty = gap.belowQty, cost = gap.belowCost, gain = gain, deposit = deposit,
		sellsPerDay = item.sellsPerDay, daysToSell = gap.belowQty / item.sellsPerDay,
		waitingAtNext = quantityAt(item.steps, gap.nextPrice),
	}
end

--- Price-gap rows for a list of items, most gain first.
function FlipLogic.BuildGapRows(items, opts)
	local rows = {}
	for _, item in ipairs(items or {}) do
		local row = FlipLogic.BuildGapRow(item, opts)
		if row then
			rows[#rows + 1] = row
		end
	end
	table.sort(rows, function(a, b)
		return a.gain > b.gain
	end)
	return rows
end

--- One "sell now" row for `item = { itemID, storageKey, total, bags, bank, price, usual, sellsPerDay }`:
--- something you own that is priced above usual and sells, or nil. Worth is after the cut.
function FlipLogic.BuildSellNowRow(item, opts)
	local total, price, usual, sells = tonumber(item.total), tonumber(item.price), tonumber(item.usual), tonumber(item.sellsPerDay)
	if not (total and price and usual and sells) or total <= 0 or usual <= 0 or sells <= 0 then
		return nil
	end
	local premium = (price - usual) / usual
	if premium < gapOption(opts, "minPremium", 0.1) then
		return nil
	end
	local daysToSell = total / sells
	return {
		itemID = item.itemID, storageKey = item.storageKey, total = total, bags = item.bags, bank = item.bank,
		price = price, usual = usual, premium = premium, sellsPerDay = sells,
		worth = total * price * (1 - gapOption(opts, "cut", 0.05)),
		daysToSell = daysToSell, slow = daysToSell > 1,
	}
end

--- Sell-now rows for a list of owned items, most worth first.
function FlipLogic.BuildSellNowRows(items, opts)
	local rows = {}
	for _, item in ipairs(items or {}) do
		local row = FlipLogic.BuildSellNowRow(item, opts)
		if row then
			rows[#rows + 1] = row
		end
	end
	table.sort(rows, function(a, b)
		return a.worth > b.worth
	end)
	return rows
end

-- ---------- How sure a row is: early prices (F56), where sales come from (F57) ----------

-- Fields about the data behind a row, copied from its candidate.
local CARRIED = { "early", "usualDays", "usualLow", "usualHigh", "sellsSource", "sellsPairs", "sellsConfidence" }

--- Set the sells-a-day fields of a candidate from `MarketSignals.SellsPerDay`'s result.
function FlipLogic.SetSells(item, sells)
	item.sellsPerDay, item.sellsSource, item.sellsPairs, item.sellsConfidence = sells.perDay, sells.source, sells.pairs, sells.confidence
	return item
end

--- Copy the data fields (early, usual range, sales source) from the candidates onto the rows built from them.
function FlipLogic.CarryOver(rows, candidates)
	local byItem = {}
	for _, item in ipairs(candidates or {}) do
		byItem[item.itemID] = item
	end
	for _, row in ipairs(rows or {}) do
		local item = byItem[row.itemID] or {}
		for _, field in ipairs(CARRIED) do
			if row[field] == nil then
				row[field] = item[field]
			end
		end
	end
	return rows
end

-- ---------- Why a list is empty (F58) ----------

--- The flip funnel: how many items are left after each rule, from the candidate counts and the drops
--- counted by `BuildFlipRows`. A list of `{ key, count }` in the order the rules apply.
function FlipLogic.FlipFunnel(counts, drops, rowCount)
	local under = counts.withSells - (drops.discount or 0)
	return {
		{ key = "scanned", count = counts.scanned },
		{ key = "usual", count = counts.withUsual },
		{ key = "sells", count = counts.withSells },
		{ key = "under", count = under },
		{ key = "sellEnough", count = under - (drops.sells or 0) },
		{ key = "worth", count = rowCount },
	}
end

--- The first step of a funnel that nothing passed, or nil when every step kept something.
function FlipLogic.FirstEmptyStep(funnel)
	for _, step in ipairs(funnel or {}) do
		if (tonumber(step.count) or 0) <= 0 then
			return step
		end
	end
	return nil
end

--- True when a row's sells a day rests on little: few scan pairs or the player's own sales alone.
function FlipLogic.SellsUnsure(row)
	return row.sellsSource == "own" or row.sellsConfidence == "few"
end

--- Sum of `field` over the rows that are not early, and how many early rows were left out.
function FlipLogic.SumSettled(rows, field)
	local total, early = 0, 0
	for _, row in ipairs(rows or {}) do
		if row.early then
			early = early + 1
		else
			total = total + (tonumber(row[field]) or 0)
		end
	end
	return total, early
end

--- How much price history the scanned items have, from one day count per item:
--- `{ scanned, full = items with minDays or more, early = items with earlyDays to minDays - 1, bestDays }`.
function FlipLogic.HistoryCoverage(dayCounts, minDays, earlyDays)
	local out = { scanned = 0, full = 0, early = 0, bestDays = 0 }
	for _, days in ipairs(dayCounts or {}) do
		out.scanned = out.scanned + 1
		out.bestDays = math.max(out.bestDays, days)
		if days >= minDays then
			out.full = out.full + 1
		elseif days >= earlyDays then
			out.early = out.early + 1
		end
	end
	return out
end

return FlipLogic
