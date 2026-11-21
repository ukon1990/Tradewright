-- Run with: lua5.1 tests/test_market_signals.lua (from AuctionHelper root)
local root = arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]") or "."

local failed = 0
local function check(name, cond, detail)
	if cond then
		print("OK  " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
	end
end

local pe = {}
for _, file in ipairs({ "AuctionHelper_CoreHelpers.lua", "AuctionHelper_MarketSignals.lua" }) do
	local chunk, err = loadfile(root .. "/src/util/" .. file)
	assert(chunk, err)
	chunk("AuctionHelper", pe)
end
local MS = pe.MarketSignals
assert(MS, "MarketSignals missing")

local DAY, HOUR = 86400, 3600
local day1 = 20000 * DAY

-- Median
check("Median odd count", MS.Median({ 5, 1, 3 }) == 3)
check("Median even count", MS.Median({ 1, 2, 3, 4 }) == 2.5)
check("Median empty", MS.Median({}) == nil)

-- Daily rollup
local hourly = {
	[tostring(day1 + 1 * HOUR)] = { m = 100, x = 120, l = 110, n = 1, q = 50 },
	[tostring(day1 + 5 * HOUR)] = { m = 90, x = 95, l = 90, n = 2, q = 160 },
	[tostring(day1 + 9 * HOUR)] = { m = 130, x = 130, l = 130, n = 1, q = 40 },
	[tostring(day1 + DAY + HOUR)] = { m = 200, x = 200, l = 200, n = 1, q = 10 },
	[tostring(day1 - HOUR)] = { m = 999, n = 1, q = 1 },
}
local days = MS.RollupItemDays(hourly, day1, day1 + DAY)
local d = days[day1]
check("Rollup keeps only the asked day", d ~= nil and days[day1 + DAY] == nil and days[day1 - DAY] == nil)
check("Rollup price is the median of hourly lows", d and d.p == 100, d and d.p)
check("Rollup low and high", d and d.lo == 90 and d.hi == 130)
check("Rollup quantity is the highest per-scan quantity", d and d.q == 80, d and d.q)
check("Rollup counts scans", d and d.n == 4)
check("Rollup of missing history is empty", next(MS.RollupItemDays(nil, 0, day1)) == nil)
check("Rollup skips hours without a price", next(MS.RollupItemDays({ [tostring(day1)] = { n = 1 } }, day1, day1 + DAY)) == nil)

-- Usual price
local function dailyOf(prices, firstDay)
	local out = {}
	for index, price in ipairs(prices) do
		out[firstDay + (index - 1) * DAY] = { p = price }
	end
	return out
end
local now = day1 + 10 * DAY + HOUR
local steady = MS.UsualPrice(dailyOf({ 100, 102, 98, 101, 99, 100, 103, 97, 100, 100 }, day1), now, 14)
check("Usual price is the median", steady and steady.usual == 100 and steady.days == 10)
check("Usual range is the quartiles", steady and steady.low <= 100 and steady.high >= 100 and steady.low >= 97 and steady.high <= 103)
local withOutlier = MS.UsualPrice(dailyOf({ 100, 102, 98, 10, 99, 100, 103, 97, 100, 100 }, day1), now, 14)
check("One listing at a tenth does not move the usual price", withOutlier and withOutlier.usual == 100, withOutlier and withOutlier.usual)
local flat = MS.UsualPrice(dailyOf({ 50, 50, 50, 50, 50 }, day1 + 5 * DAY), now, 14)
check("Flat price has MAD 0", flat and flat.usual == 50 and flat.mad == 0)
local windowed = MS.UsualPrice(dailyOf({ 10, 10, 10, 10, 10, 10, 10, 200, 200, 200 }, day1), now, 3)
check("Window shorter than history uses only recent days", windowed and windowed.usual == 200 and windowed.days == 3)
local gaps = MS.UsualPrice({ [day1] = { p = 80 }, [day1 + 4 * DAY] = { p = 100 }, [day1 + 9 * DAY] = { p = 120 } }, now, 14)
check("Missing days are skipped", gaps and gaps.usual == 100 and gaps.days == 3)
check("No history gives nil", MS.UsualPrice(nil, now, 14) == nil and MS.UsualPrice({}, now, 14) == nil)
check("String day keys from saved data work", MS.UsualPrice({ [tostring(day1 + 9 * DAY)] = { p = 70 } }, now, 14).usual == 70)

-- Deal score
local score = MS.DealScore(60, 100, 4)
check("Deal score percentage", score and math.abs(score.pct + 0.4) < 1e-9)
check("Deal score is the modified z-score", score and math.abs(score.score - (0.6745 * -40 / 4)) < 1e-9)
local noSpread = MS.DealScore(60, 100, 0)
check("MAD 0 gives a percentage and no score", noSpread and noSpread.score == nil and math.abs(noSpread.pct + 0.4) < 1e-9)
check("No usual price gives nil", MS.DealScore(60, nil, 4) == nil and MS.DealScore(60, 0, 4) == nil)

-- Estimated sales from quantity drops between scans
local function qtyHours(list)
	local out = {}
	for _, pair in ipairs(list) do
		out[tostring(pair[1])] = { m = 10, l = 10, n = 1, q = pair[2] }
	end
	return out
end
local sold = MS.EstimateSoldByDay(qtyHours({ { day1 + 2 * HOUR, 100 }, { day1 + 14 * HOUR, 70 } }), day1, day1 + DAY)
check("A drop of 30 over 12 hours is counted", sold[day1] and sold[day1].s == 30 and sold[day1].g == 12 and sold[day1].c == 1)
local rose = MS.EstimateSoldByDay(qtyHours({ { day1 + 2 * HOUR, 50 }, { day1 + 6 * HOUR, 90 } }), day1, day1 + DAY)
check("A rise counts as 0 sold", rose[day1] and rose[day1].s == 0 and rose[day1].g == 4)
local far = MS.EstimateSoldByDay(qtyHours({ { day1 + HOUR, 100 }, { day1 + 3 * DAY, 10 } }), day1, day1 + 4 * DAY)
check("Scans 3 days apart add nothing", next(far) == nil)
local across = MS.EstimateSoldByDay(qtyHours({ { day1 - 2 * HOUR, 80 }, { day1 + 3 * HOUR, 60 } }), day1, day1 + DAY)
check("A pair across midnight counts on the later day", across[day1] and across[day1].s == 20 and across[day1 - DAY] == nil)
local averaged = MS.EstimateSoldByDay({
	[tostring(day1 + HOUR)] = { m = 10, n = 2, q = 200 },
	[tostring(day1 + 5 * HOUR)] = { m = 10, n = 1, q = 60 },
}, day1, day1 + DAY)
check("Quantity is averaged over the scans in an hour", averaged[day1] and averaged[day1].s == 40)
check("One scan gives no estimate", next(MS.EstimateSoldByDay(qtyHours({ { day1 + HOUR, 5 } }), day1, day1 + DAY)) == nil)

local sellsDaily = {
	[day1 + 8 * DAY] = { p = 10, s = 30, g = 12, c = 1 },
	[day1 + 9 * DAY] = { p = 10, s = 10, g = 12, c = 1 },
}
local sells = MS.SellsPerDay(sellsDaily, now, 14)
check("Sells a day scales the covered hours to 24", sells and sells.perDay == 40 and sells.confidence == "few" and sells.pairs == 2)
sellsDaily[day1 + 7 * DAY] = { p = 10, s = 0, g = 24, c = 3 }
local confident = MS.SellsPerDay(sellsDaily, now, 14)
check("Five scan pairs give good confidence", confident and confident.confidence == "good" and confident.perDay == 20)
check("Own sales are a floor", MS.SellsPerDay(sellsDaily, now, 14, 55).perDay == 55)
check("One scan pair shows nothing", MS.SellsPerDay({ [day1 + 9 * DAY] = { s = 5, g = 3, c = 1 } }, now, 14) == nil)
local ownOnly = MS.SellsPerDay({ [day1 + 9 * DAY] = { s = 5, g = 3, c = 1 } }, now, 14, 10)
check("Own sales alone give a figure", ownOnly and ownOnly.perDay == 10 and ownOnly.confidence == "few")
check("Source: scans only", confident.source == "scans" and MS.SellsPerDay(sellsDaily, now, 14, 5).source == "scans")
check("Source: own sales alone", ownOnly.source == "own")
check("Source: scans raised to own sales", MS.SellsPerDay(sellsDaily, now, 14, 55).source == "both")
check("Days without an estimate are ignored", MS.SellsPerDay({ [day1 + 9 * DAY] = { p = 10 } }, now, 14) == nil)
check("Days of supply", MS.DaysOfSupply(86, 12) == 86 / 12)
check("Days of supply needs sales", MS.DaysOfSupply(86, 0) == nil and MS.DaysOfSupply(86, nil) == nil)

-- Price steps
local levels = {}
for _, row in ipairs({ { 310, 2 }, { 280, 3 }, { 410, 22 }, { 295, 4 }, { 280, 0 }, { 425, 31 }, { 440, 40 } }) do
	MS.AddPriceStep(levels, row[1], row[2], 8)
end
local steps = MS.BuildPriceSteps(levels)
check("Steps are cheapest first", steps[1] == 280 and steps[3] == 295 and steps[5] == 310 and steps[7] == 410)
check("Equal prices merge", steps[2] == 3 and #steps == 12)
local capped = {}
for price = 20, 1, -1 do
	MS.AddPriceStep(capped, price, 1, 8)
end
check("Only the 8 cheapest levels are kept", #capped == 8 and capped[1][1] == 1 and capped[8][1] == 8)
local single = MS.BuildPriceSteps(MS.AddPriceStep({}, 50, 7, 8))
check("One price gives one step with its quantity", #single == 2 and single[1] == 50 and single[2] == 7)
local clear = MS.CostToClear(steps, 310)
check("Cost to clear up to a price", clear.qty == 9 and clear.cost == 3 * 280 + 4 * 295 + 2 * 310)
check("Cost to clear below the floor is nothing", MS.CostToClear(steps, 100).qty == 0)
check("Average fill walks the steps", MS.AverageFill(steps, 5) == (3 * 280 + 2 * 295) / 5)
check("Average fill beyond the kept steps is nil", MS.AverageFill(steps, 1000) == nil)
local gap = MS.FindPriceGap(steps, 0.25)
check("Largest gap: buy 9 for 26g 40s, next 4g 10s", gap and gap.belowQty == 9 and gap.belowCost == 2640 and gap.nextPrice == 410 and gap.floorPrice == 280)
check("No gap under the threshold", MS.FindPriceGap(steps, 0.5) == nil)
check("A single level has no gap", MS.FindPriceGap(single, 0) == nil)

-- Flips
local flipChunk, flipErr = loadfile(root .. "/src/util/AuctionHelper_FlipLogic.lua")
assert(flipChunk, flipErr)
flipChunk("AuctionHelper", pe)
local Flip = pe.FlipLogic
local arcanite = { itemID = 1, price = 260000, usual = 380000, sellsPerDay = 12, steps = { 260000, 4, 300000, 10, 380000, 70 } }
local flip = Flip.BuildFlipRow(arcanite, { minProfit = 50000 })
check("Flip buys what is listed under the limit price", flip and flip.buyQty == 4 and flip.listedUnder == 4 and flip.cost == 4 * 260000)
check("Flip profit is after the cut", flip and flip.profit == 4 * 380000 * 0.95 - 4 * 260000, flip and flip.profit)
check("Flip profit each and break-even", flip and flip.profitEach == flip.profit / 4 and math.abs(flip.breakEven - 260000 / 0.95) < 1e-6)
local cappedBuy = Flip.BuildFlipRow({ itemID = 2, price = 31, usual = 48, sellsPerDay = 30, steps = { 31, 500 } }, { minProfit = 0 })
check("Buy is capped at a third of a day's sales", cappedBuy and cappedBuy.buyQty == 10 and cappedBuy.listedUnder == 500)
local free = { minProfit = 0 }
check("Discount just under the threshold is dropped", Flip.BuildFlipRow({ itemID = 3, price = 76, usual = 100, sellsPerDay = 9 }, free) == nil)
check("Discount at the threshold is kept", Flip.BuildFlipRow({ itemID = 3, price = 75, usual = 100, sellsPerDay = 9 }, free) ~= nil)
check("Profit floor drops small flips", Flip.BuildFlipRow({ itemID = 4, price = 50, usual = 100, sellsPerDay = 9 }, { minProfit = 1000 }) == nil)
check("Unknown sells a day is not listed", Flip.BuildFlipRow({ itemID = 5, price = 50, usual = 100 }, { minProfit = 0 }) == nil)
check("Slow sellers are dropped by the turnover floor", Flip.BuildFlipRow({ itemID = 6, price = 50, usual = 100, sellsPerDay = 0.2 }, { minProfit = 0 }) == nil)
local noSteps = Flip.BuildFlipRow({ itemID = 7, price = 50, usual = 100, sellsPerDay = 9 }, { minProfit = 0 })
check("Without price steps the quantity is unknown", noSteps and noSteps.buyQty == nil and noSteps.cost == 50 and noSteps.profit == 45)
local flagged = Flip.BuildFlipRow({ itemID = 8, price = 50, usual = 100, sellsPerDay = 1, confidence = "few", steps = { 50, 9 } },
	{ minProfit = 0, dayShare = 5 })
check("Flags: sells slowly and few sales", flagged and flagged.slow == true and flagged.fewSales == true and flagged.buyQty == 5)
local withDeposit = Flip.BuildFlipRow({ itemID = 9, price = 50, usual = 100, sellsPerDay = 9, depositLoss = 5 }, { minProfit = 0 })
check("Expected deposit loss is subtracted", withDeposit and withDeposit.profit == 40)
local sorted = Flip.BuildFlipRows({ noSteps and { itemID = 7, price = 50, usual = 100, sellsPerDay = 9 }, arcanite }, { minProfit = 0 })
check("Rows are sorted by profit", #sorted == 2 and sorted[1].itemID == 1 and sorted[2].itemID == 7)
-- Profit floor under 1g: buy 2 at 1s 50c, usual 3s, 5% cut → 2 × 285 - 300 = 270 copper
local smallFlip = { itemID = 10, price = 150, usual = 300, sellsPerDay = 9, steps = { 150, 2 } }
local floor25s = { minProfit = 2500 }
check("A 25s floor keeps a 45s flip",
	Flip.BuildFlipRow({ itemID = 11, price = 5000, usual = 10000, sellsPerDay = 3, steps = { 5000, 1 } }, floor25s) ~= nil)
check("A 25s floor drops a 20s flip",
	Flip.BuildFlipRow({ itemID = 12, price = 7000, usual = 9500, sellsPerDay = 3, steps = { 7000, 1 } }, floor25s) == nil)
check("Copper floor between rows", Flip.BuildFlipRow(smallFlip, { minProfit = 270 }) ~= nil and Flip.BuildFlipRow(smallFlip, { minProfit = 271 }) == nil)
check("Default floor is 1g", Flip.BuildFlipRow({ itemID = 13, price = 5000, usual = 20000, sellsPerDay = 3, steps = { 5000, 1 } }) ~= nil)
-- Early rows
local marked = Flip.CarryOver({ { itemID = 1, profit = 100 }, { itemID = 2, profit = 40, usualDays = 6 } },
	{ { itemID = 1, early = true, usualDays = 3 }, { itemID = 2, usualDays = 6 } })
check("Early flag and days copied from the candidate", marked[1].early == true and marked[1].usualDays == 3 and marked[2].early == nil)
local settledProfit, earlyLeftOut = Flip.SumSettled(marked, "profit")
check("Totals leave early rows out", settledProfit == 40 and earlyLeftOut == 1)
local sourced = Flip.CarryOver({ { itemID = 3 } }, { Flip.SetSells({ itemID = 3 }, { perDay = 4, source = "own", pairs = 0, confidence = "few" }) })[1]
check("Sales source carried onto the row", sourced.sellsSource == "own" and sourced.sellsPairs == 0 and Flip.SellsUnsure(sourced))
check("Five pairs from scans are sure", not Flip.SellsUnsure({ sellsSource = "scans", sellsConfidence = "good" }))
-- Why a list is empty
local drops = {}
local funnelRows = Flip.BuildFlipRows({
	{ itemID = 20, price = 90, usual = 100, sellsPerDay = 9 },
	{ itemID = 21, price = 50, usual = 100, sellsPerDay = 0.1 },
	{ itemID = 22, price = 50, usual = 100, sellsPerDay = 9 },
	{ itemID = 23, price = 10000, usual = 20000, sellsPerDay = 9, steps = { 10000, 1 } },
}, { minProfit = 5000 }, drops)
check("Drops counted per reason", drops.discount == 1 and drops.sells == 1 and drops.profit == 1 and #funnelRows == 1)
local funnel = Flip.FlipFunnel({ scanned = 10, withUsual = 6, withSells = 4 }, drops, #funnelRows)
local funnelCounts = {}
for index, step in ipairs(funnel) do
	funnelCounts[index] = step.count
end
check("Flip funnel narrows step by step", table.concat(funnelCounts, ",") == "10,6,4,3,2,1", table.concat(funnelCounts, ","))
check("A full funnel has no empty step", Flip.FirstEmptyStep(funnel) == nil)
check("First empty step is found", Flip.FirstEmptyStep({ { key = "a", count = 3 }, { key = "b", count = 0 }, { key = "c", count = 0 } }).key == "b")
local coverage = Flip.HistoryCoverage({ 0, 1, 2, 4, 5, 9 }, 5, 2)
check("Coverage counts full, early and best days",
	coverage.scanned == 6 and coverage.full == 2 and coverage.early == 2 and coverage.bestDays == 9)
check("Coverage of nothing", Flip.HistoryCoverage({}, 5, 2).scanned == 0)

-- Sure things: listed under vendor price
local sure = Flip.BuildVendorRow({ itemID = 1, price = 1000, vendorSell = 2500, steps = { 1000, 3, 2000, 2, 2500, 9, 4000, 50 } })
check("Units under vendor price and their cost", sure and sure.qty == 5 and sure.cost == 7000 and sure.qtyKnown == true)
check("Gain has no auction cut", sure and sure.gain == 5 * 2500 - 7000)
check("A step exactly at vendor price is excluded", sure and sure.qty == 5)
check("No vendor price, no row", Flip.BuildVendorRow({ itemID = 2, price = 100 }) == nil)
check("Not under vendor price, no row", Flip.BuildVendorRow({ itemID = 3, price = 250, vendorSell = 250 }) == nil)
check("Gain floor drops tiny gains", Flip.BuildVendorRow({ itemID = 4, price = 100, vendorSell = 150 }) == nil)
local oneUnit = Flip.BuildVendorRow({ itemID = 5, price = 100, vendorSell = 5000 })
check("Without steps one unit at the lowest price", oneUnit and oneUnit.qty == 1 and oneUnit.gain == 4900 and oneUnit.qtyKnown == false)
local sureRows = Flip.BuildVendorRows({ { itemID = 5, price = 100, vendorSell = 5000 }, { itemID = 6, price = 100, vendorSell = 90000 } })
check("Sure things are sorted by gain", #sureRows == 2 and sureRows[1].itemID == 6)

-- Price gaps
local potion = { itemID = 1, steps = { 280, 3, 295, 4, 310, 2, 410, 22, 425, 31, 440, 40 }, usualHigh = 420, sellsPerDay = 14 }
local gapRow = Flip.BuildGapRow(potion, { cut = 0.05 })
check("Gap: buy 9 for 26g 40s, next 4g 10s", gapRow and gapRow.buyQty == 9 and gapRow.cost == 2640 and gapRow.nextPrice == 410)
check("Gap gain is after the cut", gapRow and math.abs(gapRow.gain - (9 * 410 * 0.95 - 2640)) < 1e-6)
check("Gap knows who already waits at the next price", gapRow and gapRow.waitingAtNext == 22 and gapRow.daysToSell == 9 / 14)
local function gapWith(changes, opts)
	local copy = { itemID = 1, steps = potion.steps, usualHigh = potion.usualHigh, sellsPerDay = potion.sellsPerDay }
	for key, value in pairs(changes) do
		copy[key] = value
	end
	return Flip.BuildGapRow(copy, opts)
end
check("Next price far above the usual range is ignored", gapWith({ usualHigh = 300 }) == nil)
check("No usual range, no row", Flip.BuildGapRow({ itemID = 1, steps = potion.steps, sellsPerDay = 14 }) == nil)
check("Unknown turnover is not listed", Flip.BuildGapRow({ itemID = 1, steps = potion.steps, usualHigh = 420 }) == nil)
check("Slow turnover is not listed", gapWith({ sellsPerDay = 2 }) == nil)
check("Cost limit drops dear gaps", gapWith({}, { maxCost = 2000 }) == nil)
check("A single level has no gap", gapWith({ steps = { 280, 3 } }) == nil)
check("A deposit can turn the gain negative", gapWith({ deposit = 200 }) == nil)
local gapRows = Flip.BuildGapRows({ potion, { itemID = 2, steps = { 100, 50, 200, 9 }, usualHigh = 210, sellsPerDay = 80 } })
check("Gaps are sorted by gain", #gapRows == 2 and gapRows[1].itemID == 2)

-- Weekday pattern
local weekdayChunk, weekdayErr = loadfile(root .. "/src/util/AuctionHelper_WeekdayPattern.lua")
assert(weekdayChunk, weekdayErr)
weekdayChunk("AuctionHelper", pe)
local WP = pe.WeekdayPattern
check("1970-01-01 was a Thursday", WP.Weekday(0) == 4 and WP.Weekday(4 * DAY) == 1)
local function dailySeries(count, priceOf)
	local out = {}
	for index = 0, count - 1 do
		local at = day1 + index * DAY
		out[at] = { p = priceOf(at, index) }
	end
	return out
end
local tuesdays = dailySeries(42, function(at)
	return WP.Weekday(at) == 2 and 110 or 100
end)
local pattern = WP.Build(tuesdays)
check("A planted Tuesday premium is found", pattern and pattern.dearest == 2 and pattern.byDay[2] > 0.07 and pattern.weeks == 6)
check("The other days sit just under the trend", pattern and pattern.byDay[4] < 0 and pattern.byDay[4] > -0.03)
check("Flat prices show no pattern", WP.Build(dailySeries(42, function() return 100 end)) == nil)
check("Two weeks of history show no pattern", WP.Build(dailySeries(14, function(at) return WP.Weekday(at) == 2 and 110 or 100 end)) == nil)
local seed = 7
local noise = dailySeries(42, function()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return 100 + (seed % 9) - 4
end)
check("Noise alone shows no pattern", WP.Build(noise) == nil)
local shifted = dailySeries(42, function(_, index) return index < 21 and 100 or 200 end)
check("A level shift in the middle is not a weekday pattern", WP.Build(shifted) == nil)
local noSundays = dailySeries(42, function(at) return WP.Weekday(at) == 2 and 110 or 100 end)
for at in pairs(noSundays) do
	if WP.Weekday(at) == 7 then
		noSundays[at] = nil
	end
end
check("A weekday without scans gives no pattern", WP.Build(noSundays) == nil)
check("No history gives no pattern", WP.Build(nil) == nil and WP.Build({}) == nil)

-- Sell now
local owned = Flip.BuildSellNowRow({ itemID = 1, total = 40, bags = 12, bank = 28, price = 120, usual = 100, sellsPerDay = 80 }, { cut = 0.05 })
check("Owned item 20% above usual is listed with its worth", owned and math.abs(owned.premium - 0.2) < 1e-9 and owned.worth == 40 * 120 * 0.95)
check("Days of sales and the slow flag", owned and owned.daysToSell == 0.5 and owned.slow == false)
check("Premium edge: 9% above is not listed", Flip.BuildSellNowRow({ itemID = 2, total = 5, price = 109, usual = 100, sellsPerDay = 9 }) == nil)
check("Premium edge: 10% above is listed", Flip.BuildSellNowRow({ itemID = 2, total = 5, price = 110, usual = 100, sellsPerDay = 9 }) ~= nil)
check("Unknown turnover is not listed", Flip.BuildSellNowRow({ itemID = 3, total = 5, price = 150, usual = 100 }) == nil)
check("No usual price, no row", Flip.BuildSellNowRow({ itemID = 4, total = 5, price = 150, sellsPerDay = 9 }) == nil)
local heavy = Flip.BuildSellNowRow({ itemID = 5, total = 60, price = 150, usual = 100, sellsPerDay = 20 })
check("More than a day of sales is flagged", heavy and heavy.slow == true and heavy.daysToSell == 3)
local sellList = Flip.BuildSellNowRows({
	{ itemID = 6, total = 1, price = 150, usual = 100, sellsPerDay = 9 },
	{ itemID = 7, total = 50, price = 150, usual = 100, sellsPerDay = 9 },
})
check("Sell now is sorted by worth", #sellList == 2 and sellList[1].itemID == 7)

-- Cheapest material source
local materialChunk, materialErr = loadfile(root .. "/src/util/AuctionHelper_MaterialLogic.lua")
assert(materialChunk, materialErr)
materialChunk("AuctionHelper", pe)
local ML = pe.MaterialLogic
local cost, from = ML.CheapestSource({ { 60, "Market" }, { 52, "Craft" } })
check("Crafting wins when cheaper", cost == 52 and from == "Craft")
cost, from = ML.CheapestSource({ { 60, "Market" }, { 75, "Craft" } })
check("Buying wins when cheaper", cost == 60 and from == "Market")
cost, from = ML.CheapestSource({ { 60, "Market" }, { 60, "Craft" } })
check("On a tie the first source is kept", cost == 60 and from == "Market")
cost, from = ML.CheapestSource({ { nil, nil }, { 40, "Craft" } })
check("A missing price falls to the other source", cost == 40 and from == "Craft")
cost, from = ML.CheapestSource({ { nil, nil }, { nil, "Craft" }, { 0, "Vendor" } })
check("No usable price gives nil", cost == nil and from == nil)
local unitIndex = ML.UnitCostIndex({
	{ outputItemID = 10, matCost = 300, fullMatCost = 260, outputQty = 5, bestCharacterKey = "Brannoc" },
	{ outputItemID = 10, matCost = 400, outputQty = 5, bestCharacterKey = "Maelis" },
	{ outputItemID = 11, matCost = 90, matMissingPrice = true },
	{ outputItemID = 12, matCost = 90, hasCooldown = true },
	{ outputItemID = 13, matCost = 70 },
})
check("Unit cost is the full material cost over the output quantity", unitIndex[10] and unitIndex[10].cost == 52 and unitIndex[10].crafter == "Brannoc")
check("Rows with a missing price or a cooldown are left out", unitIndex[11] == nil and unitIndex[12] == nil)
check("Output quantity defaults to 1", unitIndex[13] and unitIndex[13].cost == 70)

-- How many to make
check("Sells 8 a day, 2 owned, 1 day: make 6", ML.RestockQuantity({ sellsPerDay = 8, owned = 2, profit = 100 }) == 6)
check("Sells 35 a day, 60 owned: make 0", ML.RestockQuantity({ sellsPerDay = 35, owned = 60, profit = 100 }) == 0)
check("Unknown sells a day: nil", ML.RestockQuantity({ owned = 2, profit = 100 }) == nil)
check("A loss-making craft: make 0", ML.RestockQuantity({ sellsPerDay = 8, owned = 0, profit = -5 }) == 0)
check("Three days triples the target", ML.RestockQuantity({ sellsPerDay = 8, owned = 2, profit = 100, days = 3 }) == 22)
check("Sales round to whole items", ML.RestockQuantity({ sellsPerDay = 2.6, owned = 0, profit = 100 }) == 3)
check("Cap limits the quantity", ML.RestockQuantity({ sellsPerDay = 80, owned = 0, profit = 100, cap = 1 }) == 1)
check("Listed counts once", ML.RestockQuantity({ sellsPerDay = 8, owned = 2, listed = 3, profit = 100 }) == 3)

-- Cooldowns
check("No cooldown on record", ML.CooldownState(nil, 1000).state == "none")
check("A cooldown in the past is ready", ML.CooldownState(900, 1000).state == "ready")
local waiting = ML.CooldownState(1000 + 28 * 3600, 1000)
check("A cooldown in the future is waiting", waiting.state == "waiting" and waiting.secondsLeft == 28 * 3600)
check("Cooldown text: days and hours", ML.FormatCooldown(28 * 3600) == "1 day 4 hours")
check("Cooldown text: whole days", ML.FormatCooldown(48 * 3600) == "2 days")
check("Cooldown text: hours", ML.FormatCooldown(3 * 3600) == "3 hours" and ML.FormatCooldown(3600) == "1 hour")
check("Cooldown text: minutes, never zero", ML.FormatCooldown(20 * 60) == "20 minutes" and ML.FormatCooldown(5) == "1 minute")
check("A ready cooldown caps Make at 1", ML.RestockQuantity({ sellsPerDay = 12, owned = 0, profit = 100, cap = 1 }) == 1)
check("A waiting cooldown caps Make at 0", ML.RestockQuantity({ sellsPerDay = 12, owned = 0, profit = 100, cap = 0 }) == 0)

-- Farm runs
local farmChunk, farmErr = loadfile(root .. "/src/util/AuctionHelper_FarmLogic.lua")
assert(farmChunk, farmErr)
farmChunk("AuctionHelper", pe)
local Farm = pe.FarmLogic
check("Active time leaves out pauses", Farm.ActiveSeconds({ startedAt = 100, endedAt = 4100, pausedSeconds = 400 }, 9999) == 3600)
check("A pause in progress is not counted", Farm.ActiveSeconds({ startedAt = 100, pausedSeconds = 0, pausedAt = 700 }, 1000) == 600)
check("A run that has not started counts 0", Farm.ActiveSeconds({}, 500) == 0)
local value, kind = Farm.ItemValue({ vendor = 10, usual = 100, sellsPerDay = 40 }, { cut = 0.05 })
check("An item that sells counts at its usual price after the cut", value == 95 and kind == "auction")
value, kind = Farm.ItemValue({ vendor = 10, usual = 100 }, { cut = 0.05 })
check("An item with no sells-a-day estimate counts at vendor price", value == 10 and kind == "vendor")
value, kind = Farm.ItemValue({ vendor = 10, usual = 100, sellsPerDay = 0.2 }, { cut = 0.05 })
check("An item that rarely sells counts at vendor price", value == 10 and kind == "vendor")
value, kind = Farm.ItemValue({ vendor = 200, usual = 100, sellsPerDay = 40 }, { cut = 0.05 })
check("Vendor price wins when it is higher", value == 200 and kind == "vendor")
value = Farm.ItemValue(nil)
check("An unknown item counts 0", value == 0)
local farmPrices = { [1] = { vendor = 10, usual = 100, sellsPerDay = 40 }, [2] = { vendor = 25 } }
local farmRun = { startedAt = 0, endedAt = 1800, pausedSeconds = 0, coin = 500, vendorSold = 120, items = { [1] = 10, [2] = 4 } }
local farmSummary = Farm.SummarizeRun(farmRun, function(itemID) return farmPrices[itemID] end, 9999, { cut = 0.05 })
check("Coin and vendor sales stay separate", farmSummary.coin == 500 and farmSummary.vendorSold == 120)
check("Vendor value and auction estimate stay separate", farmSummary.vendorValue == 100 and farmSummary.auctionValue == 950)
check("Total and gold an hour", farmSummary.total == 1670 and farmSummary.perHour == 3340 and farmSummary.activeSeconds == 1800)
check("Items are listed most valuable first", farmSummary.byItem[1].itemID == 1 and farmSummary.byItem[2].kind == "vendor")
local emptyRun = Farm.SummarizeRun({ startedAt = 5, endedAt = 5 }, function() return nil end, 5)
check("An empty run with no time is 0 an hour", emptyRun.total == 0 and emptyRun.perHour == 0)
check("Selling to a vendor takes items out of the run", Farm.RemoveItems(farmRun, 2, 3) == 3 and farmRun.items[2] == 1)
check("Selling more than was looted removes only what was looted", Farm.RemoveItems(farmRun, 2, 9) == 1 and farmRun.items[2] == nil)
check("Selling something not looted in the run changes nothing", Farm.RemoveItems(farmRun, 77, 5) == 0)

-- Saved farms
local savedFarm = { zone = "Felwood", runs = {
	{ items = { [1] = 10, [2] = 4 }, coin = 500, vendorSold = 100, activeSeconds = 1800, endedAt = 5000, valueWhenSaved = 1200 },
	{ items = { [1] = 20 }, coin = 300, vendorSold = 0, activeSeconds = 1800, endedAt = 9000, valueWhenSaved = 1800 },
} }
local farmNow = Farm.SummarizeFarm(savedFarm, function(itemID) return farmPrices[itemID] end, { cut = 0.05 })
check("A farm adds up its runs", farmNow.runs == 2 and farmNow.activeSeconds == 3600 and farmNow.lastRunAt == 9000)
check("Then is the value when saved, per hour", farmNow.thenPerHour == 3000)
check("Now values the same loot at today's prices", farmNow.nowPerHour == 30 * 95 + 4 * 25 + 800 + 100)
check("Change compares now with then", math.abs(farmNow.changePct - (farmNow.nowPerHour - 3000) / 3000) < 1e-9)
check("Shares add up to 1", math.abs(farmNow.liquidShare + farmNow.coinShare - 1) < 1e-9 and farmNow.liquidShare > 0.7)
local itemSum = 0
for _, item in ipairs(farmNow.perHourByItem) do
	itemSum = itemSum + item.valuePerHour
end
check("Per-item rows plus coin and vendor sales add up to gold an hour", itemSum + 900 == farmNow.nowPerHour and farmNow.perHourByItem[1].qtyPerHour == 30)
local dearer = Farm.SummarizeFarm(savedFarm, function(itemID)
	return itemID == 1 and { vendor = 10, usual = 200, sellsPerDay = 40 } or farmPrices[itemID]
end, { cut = 0.05 })
check("A price rise lifts Now and leaves Then", dearer.nowPerHour > farmNow.nowPerHour and dearer.thenPerHour == 3000)
local unpriced = Farm.SummarizeFarm({ runs = { { items = { [9] = 3 }, activeSeconds = 600, valueWhenSaved = 0 } } }, function() return nil end)
check("A farm with no priced items is 0 an hour with no change", unpriced.nowPerHour == 0 and unpriced.changePct == nil)

-- What to farm
local lootIndex = Farm.BuildLootIndex({
	["Felwood herb loop"] = { runs = { { items = { [1] = 38, [3] = 14 }, activeSeconds = 3600 } } },
	["Slow loop"] = { runs = { { items = { [1] = 10 }, activeSeconds = 3600 }, { items = { [1] = 10 }, activeSeconds = 3600 } } },
})
check("Loot index names the farm with the higher rate", lootIndex[1].farm == "Felwood herb loop" and lootIndex[1].perHour == 38)
check("Loot index covers every looted item", lootIndex[3] and lootIndex[3].perHour == 14 and lootIndex[9] == nil)
local targetItems = {
	{ itemID = 1, usual = 4800, sellsPerDay = 400, quantity = 3200, usedByRecipes = true },
	{ itemID = 2, usual = 9600, sellsPerDay = 2, quantity = 8 },
	{ itemID = 3, usual = 5500, sellsPerDay = 180, quantity = 90 },
	{ itemID = 4, usual = 100 },
}
local targets = Farm.BuildFarmTargets(targetItems, lootIndex, { cut = 0.05 })
check("Traded a day is usual price times sells a day", targets[1].itemID == 1 and targets[1].tradedPerDay == 4800 * 400)
check("Targets are ranked by gold traded a day", #targets == 3 and targets[2].itemID == 3 and targets[3].itemID == 2)
check("A farmed item names its farm and your rate", targets[1].source == "Felwood herb loop" and targets[1].yoursPerHour == 38 * 4800 * 0.95)
check("An item never looted in a farm has no source or rate", targets[3].source == nil and targets[3].yoursPerHour == nil)
check("An item without a sells-a-day estimate is not listed", targets[4] == nil)
check("Days of supply", targets[1].daysOfSupply == 8 and targets[2].daysOfSupply == 0.5)
local farmedOnly = Farm.BuildFarmTargets(targetItems, lootIndex, { onlyFarmed = true })
check("Only farmed before", #farmedOnly == 2 and farmedOnly[1].itemID == 1 and farmedOnly[2].itemID == 3)
local recipeOnly = Farm.BuildFarmTargets(targetItems, lootIndex, { onlyRecipes = true })
check("My recipes use it", #recipeOnly == 1 and recipeOnly[1].itemID == 1)
local earlyItems = {
	{ itemID = 1, usual = 4800, sellsPerDay = 400, quantity = 3200 },
	{ itemID = 5, usual = 200, quantity = 10, early = true, days = 2 },
	{ itemID = 6, usual = 100, quantity = 500, early = true, days = 1 },
	{ itemID = 7, usual = 300, sellsPerDay = 2, quantity = 4, early = true, days = 3 },
	{ itemID = 8, quantity = 9, early = true },
}
local early = Farm.BuildFarmTargets(earlyItems, {}, {})
check("Early estimates are listed, an item with no price is not", #early == 4)
check("Known sales rank above early rows without sales", early[1].itemID == 1 and early[2].itemID == 7 and early[2].early)
check("Early rows without sales rank by gold listed", early[3].itemID == 6 and early[4].itemID == 5)
check("An early row without sales has no traded or supply figure", early[3].tradedPerDay == nil and early[3].daysOfSupply == nil)
check("Without the early flag a row needs sales", #Farm.BuildFarmTargets({ { itemID = 5, usual = 200, quantity = 10 } }, {}, {}) == 0)
local emptyTitle = Farm.FarmTargetsEmptyText({ tradeGoods = 0, priced = 0 }, { onlyRecipes = true })
check("Empty list without trade goods asks for a scan", emptyTitle == "No trade goods scanned yet")
local historyTitle, historyHint = Farm.FarmTargetsEmptyText({ tradeGoods = 12, priced = 0 }, { onlyRecipes = true })
check("Empty list without history says 5 days", historyTitle == "Not enough price history yet"
	and historyHint:find("12 trade goods") and historyHint:find("5 different days"))
local filterTitle, filterHint = Farm.FarmTargetsEmptyText({ tradeGoods = 12, priced = 4 }, { onlyRecipes = true })
check("Empty list hidden by a filter names it", filterTitle == "Hidden by filters" and filterHint:find("My recipes use it", 1, true))

-- Daily history glue (AuctionData module) against a stub addon table
local settings = {}
local auction = { history = { hourly = {}, daily = {} } }
local state = { auctionDataRevision = 1 }
function pe:InitAuctionDB() return auction end
function pe:GetState() return state end
function pe:GetSetting(path, default) -- luacheck: ignore 212
	if settings[path] ~= nil then
		return settings[path]
	end
	return default
end
local today = MS.DayStart(os.time())
_G.GetServerTime = function() return today + HOUR end
function pe:Now() return GetServerTime() end
local glue, glueErr = loadfile(root .. "/../AuctionHelper_AuctionData/src/modules/AuctionHelper_PriceHistory.lua")
assert(glue, glueErr)
glue("AuctionHelper_AuctionData", pe)
local stepsGlue, stepsErr = loadfile(root .. "/../AuctionHelper_AuctionData/src/modules/AuctionHelper_PriceSteps.lua")
assert(stepsGlue, stepsErr)
stepsGlue("AuctionHelper_AuctionData", pe)
local logic, logicErr = loadfile(root .. "/src/util/AuctionHelper_ForeverLogic.lua")
assert(logic, logicErr)
logic("AuctionHelper", pe)
local auctionLogic, auctionLogicErr = loadfile(root .. "/src/util/AuctionHelper_AuctionLogic.lua")
assert(auctionLogic, auctionLogicErr)
auctionLogic("AuctionHelper", pe)

for back = 1, 6 do
	auction.history.hourly["k"] = auction.history.hourly["k"] or {}
	auction.history.hourly["k"][tostring(today - back * DAY + 2 * HOUR)] = { m = 100 + back, x = 110, l = 100, n = 1, q = 20 }
end
auction.history.hourly["k"][tostring(today + HOUR)] = { m = 50, x = 50, l = 50, n = 1, q = 5 }
auction.history.daily["old"] = { [today - 400 * DAY] = { p = 1 } }
pe:RollupDailyAuctionHistory()
local rolled = auction.history.daily["k"]
check("Load rolls up each finished day", rolled and rolled[today - DAY] and rolled[today - 6 * DAY] and rolled[today - DAY].p == 101)
check("Today is not rolled up yet", rolled and rolled[today] == nil)
check("Rolled days carry the sold estimate", rolled and rolled[today - DAY].g == 24 and rolled[today - DAY].s == 0 and rolled[today - 6 * DAY].g == nil)
local glueSells = pe:GetSellsPerDay("k")
check("Sells a day comes from finished days", glueSells and glueSells.perDay == 0 and glueSells.pairs == 5)
check("Rollup remembers how far it got", auction.history.dailyThrough == today)
check("Days past retention are dropped", auction.history.daily["old"] == nil)
rolled[today - DAY].p = 999
pe:RollupDailyAuctionHistory()
check("A second load does not redo finished days", rolled[today - DAY].p == 999)
rolled[today - DAY].p = 101
local usual = pe:GetUsualPrice("k")
check("Usual price needs 5 days and uses the daily middle", usual and usual.days == 6 and usual.usual == 103.5, usual and usual.usual)
check("Unknown listing has no usual price", pe:GetUsualPrice("missing") == nil)
auction.indexes = { byItemID = { ["42"] = { k = true, few = true } } }
local itemUsual, itemSells = pe:GetItemPriceSignals(42)
check("Item lookup uses the listing with the most history", itemUsual and itemUsual.days == 6 and itemSells ~= nil)
check("Item without listings has no signals", pe:GetItemPriceSignals(7) == nil)
local realLogic = pe.ForeverLogic
pe.ForeverLogic = { ParseItemIDFromStorageKey = function() return 42 end }
function pe:GetSalesSummary(windowDays) -- luacheck: ignore 212
	return { items = { { itemID = 42, units = 14 * windowDays } } }
end
state.auctionDataRevision = 5
check("The ledger's own sales are the floor", pe:GetSellsPerDay("k").perDay == 14)
pe.GetSalesSummary = nil
pe.ForeverLogic = realLogic
state.ownSalesPerDay = nil
auction.history.daily["few"] = { [today - DAY] = { p = 10 }, [today - 2 * DAY] = { p = 12 } }
state.auctionDataRevision = 2
check("Fewer than 5 days gives no usual price", pe:GetUsualPrice("few") == nil)
settings["auction.usualPriceDays"] = 3
check("Changing the window recomputes", pe:GetUsualPrice("k") == nil)

-- Price steps glue: aggregate rows of a full scan, then persist one item
local persisted, historyPoints = {}, 0
function pe:PersistAuctionDumpObservation(observation) -- luacheck: ignore 212
	persisted[#persisted + 1] = observation
	return true
end
function pe:RecordItemHistoryObservation() -- luacheck: ignore 212
	historyPoints = historyPoints + 1
end
local scan = {}
pe.AggregateAuctionRow(scan, 99, 20, 2000)
pe.AggregateAuctionRow(scan, 99, 1, 140)
pe.AggregateAuctionRow(scan, 99, 5, 0)
check("Rows aggregate as before", scan[99].sampleSize == 21 and scan[99].listingCount == 2 and scan[99].marketLow == 100)
check("Stacks are priced per unit, rows without a buyout skipped", #scan[99].levels == 2 and scan[99].levels[1][1] == 100 and scan[99].levels[1][2] == 20)
pe:PersistDumpAggregate(99, scan[99], { classic = true }, today)
check("Persist keeps the snapshot fields", #persisted == 1 and persisted[1].marketLow == 100 and persisted[1].source == "classic_full" and historyPoints == 1)
local kept, keptAt = pe:GetPriceSteps(99)
check("Steps are saved per item, first step is the lowest price", kept and kept[1] == persisted[1].marketLow and kept[2] == 20 and keptAt == today)
settings["auction.keepPriceSteps"] = false
pe:PersistDumpAggregate(99, scan[99], { classic = true }, today)
check("Turning the setting off drops the steps", pe:GetPriceSteps(99) == nil)
settings["auction.keepPriceSteps"] = nil
auction.priceSteps[5] = { t = today - 400 * DAY, l = { 1, 1 } }
pe:TrimPriceSteps()
check("Old steps are trimmed", pe:GetPriceSteps(5) == nil)

-- Shopping list: other characters' stock is used before buying
do
	local alts = { { characterKey = "Mule-R", quantity = 5 }, { characterKey = "Bank-R", quantity = 20 },
		{ characterKey = "Empty-R", quantity = 0 } }
	local fromAlts, toBuy, ranked = ML.CoverFromHolders(30, alts)
	check("Holders: stock covers part, rest is bought", fromAlts == 25 and toBuy == 5)
	check("Holders: largest stock first, empty ones dropped",
		#ranked == 2 and ranked[1].characterKey == "Bank-R" and ranked[2].characterKey == "Mule-R")
	fromAlts, toBuy = ML.CoverFromHolders(12, alts)
	check("Holders: stock covers everything", fromAlts == 12 and toBuy == 0)
	fromAlts, toBuy, ranked = ML.CoverFromHolders(7, nil)
	check("Holders: nobody has it", fromAlts == 0 and toBuy == 7 and #ranked == 0)
	local _, _, tied = ML.CoverFromHolders(1, { { characterKey = "B", quantity = 3 }, { characterKey = "A", quantity = 3 } })
	check("Holders: equal stock sorts by character", tied[1].characterKey == "A")
end

-- Queue: how many crafts the bags cover right now
do
	local bags = { [1] = 107, [2] = 5, [3] = 2 }
	local function have(itemID) return bags[itemID] end
	local plan = { { itemID = 1, quantityRequired = 4 }, { itemID = 2, quantityRequired = 2 }, { itemID = 3, quantityRequired = 2 } }
	check("Craftable: the scarcest material decides", ML.CraftableCount(plan, have) == 1)
	check("Craftable: a missing material means none", ML.CraftableCount({ { itemID = 9, quantityRequired = 1 } }, have) == 0)
	check("Craftable: optional slots do not count",
		ML.CraftableCount({ { itemID = 2, quantityRequired = 1 }, { itemID = 9, quantityRequired = 1, slotOptional = true } }, have) == 5)
	check("Craftable: no required material, cannot tell", ML.CraftableCount({}, have) == nil and ML.CraftableCount(nil, have) == nil)
end

if failed > 0 then
	print(failed .. " check(s) failed")
	os.exit(1)
end
print("All market signal checks passed")
