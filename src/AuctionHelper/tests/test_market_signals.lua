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
check("Rollup remembers how far it got", auction.history.dailyThrough == today)
check("Days past retention are dropped", auction.history.daily["old"] == nil)
rolled[today - DAY].p = 999
pe:RollupDailyAuctionHistory()
check("A second load does not redo finished days", rolled[today - DAY].p == 999)
rolled[today - DAY].p = 101
local usual = pe:GetUsualPrice("k")
check("Usual price needs 5 days and uses the daily middle", usual and usual.days == 6 and usual.usual == 103.5, usual and usual.usual)
check("Unknown listing has no usual price", pe:GetUsualPrice("missing") == nil)
auction.history.daily["few"] = { [today - DAY] = { p = 10 }, [today - 2 * DAY] = { p = 12 } }
state.auctionDataRevision = 2
check("Fewer than 5 days gives no usual price", pe:GetUsualPrice("few") == nil)
settings["auction.usualPriceDays"] = 3
check("Changing the window recomputes", pe:GetUsualPrice("k") == nil)

if failed > 0 then
	print(failed .. " check(s) failed")
	os.exit(1)
end
print("All market signal checks passed")
