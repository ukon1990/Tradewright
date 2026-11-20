local _, ProfessionExporter = ...

--- Pure price statistics built from scan history (offline-testable, no WoW API).
local MarketSignals = {}
ProfessionExporter.MarketSignals = MarketSignals

local DAY = 24 * 3600

local function sortedNumbers(values)
	local sorted = {}
	for _, value in pairs(values or {}) do
		local n = tonumber(value)
		if n then
			sorted[#sorted + 1] = n
		end
	end
	table.sort(sorted)
	return sorted
end

-- Linear-interpolated quantile of an ascending list; `q` in 0..1.
local function quantile(sorted, q)
	local count = #sorted
	if count == 0 then
		return nil
	end
	local pos = 1 + (count - 1) * q
	local lower = math.floor(pos)
	local upper = math.min(count, lower + 1)
	return sorted[lower] + (sorted[upper] - sorted[lower]) * (pos - lower)
end

function MarketSignals.Median(values)
	return quantile(sortedNumbers(values), 0.5)
end

--- Start of the day (UTC) that holds `ts`.
function MarketSignals.DayStart(ts)
	return math.floor((tonumber(ts) or 0) / DAY) * DAY
end

local function positive(value)
	local n = tonumber(value)
	if n and n > 0 then
		return n
	end
	return nil
end

-- Hourly buckets use the compact field names: m = lowest, x = highest, l = last, n = scans, q = summed quantity.
local function addHourToDay(day, bucket)
	local low = positive(bucket.m) or positive(bucket.l)
	if not low then
		return
	end
	local count = math.max(1, tonumber(bucket.n) or 1)
	day.lows[#day.lows + 1] = low
	day.lo = math.min(day.lo or low, low)
	day.hi = math.max(day.hi or low, positive(bucket.x) or low)
	day.q = math.max(day.q, (tonumber(bucket.q) or 0) / count)
	day.n = day.n + count
end

local function groupHoursByDay(hourlyByHour, fromTs, toTs)
	local days = {}
	if type(hourlyByHour) ~= "table" then
		return days
	end
	for hourKey, bucket in pairs(hourlyByHour) do
		local at = tonumber(hourKey)
		if at and at >= fromTs and at < toTs and type(bucket) == "table" then
			local dayTs = MarketSignals.DayStart(at)
			days[dayTs] = days[dayTs] or { lows = {}, q = 0, n = 0 }
			addHourToDay(days[dayTs], bucket)
		end
	end
	return days
end

--- One entry per day from `auction.history.hourly[storageKey]` for hours in `[fromTs, toTs)`:
--- `{ p = median of the hourly lowest prices, lo, hi, q = highest listed quantity, n = scans }`.
function MarketSignals.RollupItemDays(hourlyByHour, fromTs, toTs)
	local out = {}
	for dayTs, day in pairs(groupHoursByDay(hourlyByHour, fromTs, toTs)) do
		if #day.lows > 0 then
			local price = math.floor(MarketSignals.Median(day.lows) + 0.5)
			out[dayTs] = { p = price, lo = day.lo, hi = day.hi, q = math.floor(day.q + 0.5), n = day.n }
		end
	end
	return out
end

local function pricesSince(dailyByDay, cutoff)
	local prices = {}
	if type(dailyByDay) ~= "table" then
		return prices
	end
	for dayKey, entry in pairs(dailyByDay) do
		local price = type(entry) == "table" and positive(entry.p)
		if price and (tonumber(dayKey) or 0) >= cutoff then
			prices[#prices + 1] = price
		end
	end
	return prices
end

--- The usual price over the last `windowDays` of `auction.history.daily[storageKey]`:
--- `{ usual = median, mad = median absolute deviation, low, high = quartiles, days }`, or nil without history.
function MarketSignals.UsualPrice(dailyByDay, now, windowDays)
	local cutoff = MarketSignals.DayStart(now) - (tonumber(windowDays) or 14) * DAY
	local sorted = sortedNumbers(pricesSince(dailyByDay, cutoff))
	if #sorted == 0 then
		return nil
	end
	local usual = quantile(sorted, 0.5)
	local deviations = {}
	for index, price in ipairs(sorted) do
		deviations[index] = math.abs(price - usual)
	end
	return {
		usual = usual,
		mad = MarketSignals.Median(deviations),
		low = quantile(sorted, 0.25),
		high = quantile(sorted, 0.75),
		days = #sorted,
	}
end

--- How far `price` sits from the usual price: `pct` as a fraction, and the modified z-score
--- (0.6745 × distance / MAD; below -3.5 is an outlier). `score` is nil when the price never moved.
function MarketSignals.DealScore(price, usual, mad)
	price, usual, mad = tonumber(price), positive(usual), positive(mad)
	if not (price and usual) then
		return nil
	end
	return {
		pct = (price - usual) / usual,
		score = mad and 0.6745 * (price - usual) / mad or nil,
	}
end

-- Listed quantity per scanned hour in `[fromTs, toTs)`, oldest first.
local function quantityPoints(hourlyByHour, fromTs, toTs)
	local points = {}
	if type(hourlyByHour) ~= "table" then
		return points
	end
	for hourKey, bucket in pairs(hourlyByHour) do
		local at = tonumber(hourKey)
		if at and at >= fromTs and at < toTs and type(bucket) == "table" then
			local count = math.max(1, tonumber(bucket.n) or 1)
			points[#points + 1] = { at = at, qty = (tonumber(bucket.q) or 0) / count }
		end
	end
	table.sort(points, function(a, b)
		return a.at < b.at
	end)
	return points
end

--- Units that left the auction house, per day, from drops in listed quantity between consecutive scans
--- no more than `maxGapHours` apart: `{ [dayTs] = { s = units, g = hours covered, c = scan pairs } }`.
--- A drop is counted on the day of the later scan. Cancels and expiries count too, so this runs high.
function MarketSignals.EstimateSoldByDay(hourlyByHour, fromTs, toTs, maxGapHours)
	local maxGap = (tonumber(maxGapHours) or 26) * 3600
	local points = quantityPoints(hourlyByHour, fromTs - maxGap, toTs)
	local out = {}
	for index = 2, #points do
		local previous, current = points[index - 1], points[index]
		local gap = current.at - previous.at
		if current.at >= fromTs and gap <= maxGap then
			local dayTs = MarketSignals.DayStart(current.at)
			local day = out[dayTs] or { s = 0, g = 0, c = 0 }
			day.s = day.s + math.max(0, previous.qty - current.qty)
			day.g = day.g + gap / 3600
			day.c = day.c + 1
			out[dayTs] = day
		end
	end
	return out
end

local function soldSince(dailyByDay, cutoff)
	local sold, hours, scanPairs = 0, 0, 0
	if type(dailyByDay) ~= "table" then
		return sold, hours, scanPairs
	end
	for dayKey, entry in pairs(dailyByDay) do
		if type(entry) == "table" and entry.g and (tonumber(dayKey) or 0) >= cutoff then
			sold = sold + (tonumber(entry.s) or 0)
			hours = hours + (tonumber(entry.g) or 0)
			scanPairs = scanPairs + (tonumber(entry.c) or 0)
		end
	end
	return sold, hours, scanPairs
end

--- Estimated units sold per day over the last `windowDays` of daily history, never below `ownPerDay`
--- (the player's own sales): `{ perDay, confidence = "good" | "few", pairs }`, or nil with under 2 scan pairs.
function MarketSignals.SellsPerDay(dailyByDay, now, windowDays, ownPerDay)
	local cutoff = MarketSignals.DayStart(now) - (tonumber(windowDays) or 14) * DAY
	local sold, hours, scanPairs = soldSince(dailyByDay, cutoff)
	if scanPairs < 2 or hours <= 0 then
		return nil
	end
	return {
		perDay = math.max(sold / hours * 24, tonumber(ownPerDay) or 0),
		confidence = scanPairs >= 5 and "good" or "few",
		pairs = scanPairs,
	}
end

--- Days the listed quantity lasts at `perDay` sales, or nil when nothing is known to sell.
function MarketSignals.DaysOfSupply(quantity, perDay)
	quantity, perDay = tonumber(quantity), positive(perDay)
	if not (quantity and perDay) then
		return nil
	end
	return quantity / perDay
end

return MarketSignals
