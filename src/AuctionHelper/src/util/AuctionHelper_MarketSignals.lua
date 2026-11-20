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

return MarketSignals
