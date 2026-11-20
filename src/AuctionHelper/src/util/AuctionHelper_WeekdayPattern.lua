local _, ProfessionExporter = ...

--- Weekday price pattern learned from an item's own daily history (F53). Pure, offline-testable.
--- Method: divide each day's price by the median of the 7 days centred on it, take the median ratio per
--- weekday, and show the result only when the data supports it. No pattern ships with the addon.
local WeekdayPattern = {}
ProfessionExporter.WeekdayPattern = WeekdayPattern

local DAY = 24 * 3600
-- strictness 8: on pure noise about 2% of items show a false pattern with 6 weeks of daily prices, under
-- 0.5% with 12 weeks, while a 10% weekday bump is found whenever day-to-day noise is 3% or less.
local DEFAULTS = { minPerDay = 3, minWeeks = 5, minSpread = 0.03, strictness = 8 }

local function median(values)
	return ProfessionExporter.MarketSignals.Median(values)
end

-- Daily prices as `{ at, price }`, oldest first.
local function sortedDays(dailyByDay)
	local days = {}
	if type(dailyByDay) ~= "table" then
		return days
	end
	for dayKey, entry in pairs(dailyByDay) do
		local at, price = tonumber(dayKey), type(entry) == "table" and tonumber(entry.p)
		if at and price and price > 0 then
			days[#days + 1] = { at = at, price = price }
		end
	end
	table.sort(days, function(a, b)
		return a.at < b.at
	end)
	return days
end

-- A day's price over the median of the days within 3 days of it; nil with fewer than 5 such days.
local function trendRatio(days, index)
	local window = {}
	for other = math.max(1, index - 6), math.min(#days, index + 6) do
		if math.abs(days[other].at - days[index].at) <= 3 * DAY then
			window[#window + 1] = days[other].price
		end
	end
	if #window < 5 then
		return nil
	end
	return days[index].price / median(window)
end

--- Weekday of a UTC day start: 1 = Monday … 7 = Sunday.
function WeekdayPattern.Weekday(at)
	return (math.floor(at / DAY) + 3) % 7 + 1
end

-- Ratios grouped by weekday.
local function ratiosByWeekday(days)
	local byDay = { {}, {}, {}, {}, {}, {}, {} }
	for index, day in ipairs(days) do
		local ratio = trendRatio(days, index)
		if ratio then
			local list = byDay[WeekdayPattern.Weekday(day.at)]
			list[#list + 1] = ratio
		end
	end
	return byDay
end

-- Median ratio and spread (median absolute deviation) per weekday; nil when a weekday has too few days.
local function weekdayMedians(byDay, minPerDay)
	local medians, spreads = {}, {}
	for weekday = 1, 7 do
		local ratios = byDay[weekday]
		if #ratios < minPerDay then
			return nil
		end
		medians[weekday] = median(ratios)
		local deviations = {}
		for index, ratio in ipairs(ratios) do
			deviations[index] = math.abs(ratio - medians[weekday])
		end
		spreads[weekday] = median(deviations)
	end
	return medians, spreads
end

local function extremes(medians)
	local low, high = 1, 1
	for weekday = 2, 7 do
		if medians[weekday] < medians[low] then
			low = weekday
		end
		if medians[weekday] > medians[high] then
			high = weekday
		end
	end
	return low, high
end

local function setting(opts, key)
	return opts and opts[key] or DEFAULTS[key]
end

-- Is the gap between the cheapest and dearest weekday more than noise would produce?
-- Standard error of a weekday's median from its spread: 1.2533 × (1.4826 × MAD) / sqrt(days per weekday).
local function isClearGap(gap, spreads, dayCount, opts)
	local standardError = 1.2533 * 1.4826 * median(spreads) / math.sqrt(dayCount / 7)
	return gap >= setting(opts, "minSpread") and gap > setting(opts, "strictness") * standardError
end

-- Weekday medians as fractions above or below their own average.
local function aroundAverage(medians)
	local mean = 0
	for weekday = 1, 7 do
		mean = mean + medians[weekday] / 7
	end
	local byDay = {}
	for weekday = 1, 7 do
		byDay[weekday] = medians[weekday] / mean - 1
	end
	return byDay
end

--- `{ byDay = { [1..7] = fraction above or below the item's own trend }, weeks, cheapest, dearest }`,
--- or nil unless every weekday has `minPerDay` days, the history spans `minWeeks` weeks, and the gap
--- between the cheapest and dearest weekday is at least `minSpread` and larger than `strictness` standard
--- errors of a weekday median.
function WeekdayPattern.Build(dailyByDay, opts)
	local days = sortedDays(dailyByDay)
	if #days < 2 then
		return nil
	end
	local weeks = (days[#days].at - days[1].at) / (7 * DAY)
	local medians, spreads = weekdayMedians(ratiosByWeekday(days), setting(opts, "minPerDay"))
	if not medians or weeks < setting(opts, "minWeeks") then
		return nil
	end
	local cheapest, dearest = extremes(medians)
	if not isClearGap(medians[dearest] - medians[cheapest], spreads, #days, opts) then
		return nil
	end
	return { byDay = aroundAverage(medians), weeks = math.floor(weeks + 0.5), cheapest = cheapest, dearest = dearest }
end

return WeekdayPattern
