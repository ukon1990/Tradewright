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
local chunk, err = loadfile(root .. "/src/util/AuctionHelper_MarketSignals.lua")
assert(chunk, err)
chunk("AuctionHelper", pe)
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
local glue, glueErr = loadfile(root .. "/../AuctionHelper_AuctionData/src/modules/AuctionHelper_PriceHistory.lua")
assert(glue, glueErr)
glue("AuctionHelper_AuctionData", pe)
local stepsGlue, stepsErr = loadfile(root .. "/../AuctionHelper_AuctionData/src/modules/AuctionHelper_PriceSteps.lua")
assert(stepsGlue, stepsErr)
stepsGlue("AuctionHelper_AuctionData", pe)
local logic, logicErr = loadfile(root .. "/src/util/AuctionHelper_ForeverLogic.lua")
assert(logic, logicErr)
logic("AuctionHelper", pe)

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

if failed > 0 then
	print(failed .. " check(s) failed")
	os.exit(1)
end
print("All market signal checks passed")
