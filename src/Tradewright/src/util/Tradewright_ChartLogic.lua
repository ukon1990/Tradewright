local _, Tradewright = ...

--- Pure axis and layout maths for the time-series chart. No WoW API.
local ChartLogic = {}
Tradewright.ChartLogic = ChartLogic

--- Rounded tick step (1, 2 or 5 times a power of ten) covering `range` in about `count` steps.
function ChartLogic.NiceStep(range, count)
	local raw = range / math.max(1, count)
	if raw <= 0 then
		return 1
	end
	local power = 10 ^ math.floor(math.log10(raw))
	local fraction = raw / power
	local nice = fraction <= 1 and 1 or fraction <= 2 and 2 or fraction <= 5 and 5 or 10
	return nice * power
end

--- Axis `low, high, step` on rounded ticks around minValue..maxValue. A flat range is widened by one
--- each way first; floorAtZero keeps a range that starts at or above zero from dipping below it.
function ChartLogic.NiceScale(minValue, maxValue, count, floorAtZero)
	if minValue == maxValue then
		minValue, maxValue = minValue - 1, maxValue + 1
	end
	local step = ChartLogic.NiceStep(maxValue - minValue, count)
	local low = math.floor(minValue / step) * step
	local high = math.ceil(maxValue / step) * step
	if floorAtZero and minValue >= 0 then
		low = math.max(0, low)
	end
	return low, high, step
end

--- Tick values from low up to high (with float slack), at most 12.
function ChartLogic.TickValues(low, high, step)
	local ticks, tick = {}, low
	while tick <= high + step * 0.001 and #ticks < 12 do
		ticks[#ticks + 1] = tick
		tick = tick + step
	end
	return ticks
end

local function lower(current, value)
	return current and math.min(current, value) or value
end

local function upper(current, value)
	return current and math.max(current, value) or value
end

--- Widens minT..maxT and minV..maxV (nil = empty) to cover every point with a numeric `at` and `value`.
function ChartLogic.ExpandRange(points, minT, maxT, minV, maxV)
	for _, p in ipairs(points or {}) do
		local t, v = tonumber(p.at), tonumber(p.value)
		if t and v then
			minT, maxT = lower(minT, t), upper(maxT, t)
			minV, maxV = lower(minV, v), upper(maxV, v)
		end
	end
	return minT, maxT, minV, maxV
end

--- `{ minT, maxT, minV, maxV, maxQ }`: times span all three series, values the price lines only, maxQ is
--- the largest quantity. A single instant is widened by an hour each way.
function ChartLogic.Bounds(series, secondarySeries, quantitySeries)
	local minT, maxT, minV, maxV = ChartLogic.ExpandRange(series)
	minT, maxT, minV, maxV = ChartLogic.ExpandRange(secondarySeries, minT, maxT, minV, maxV)
	local qMinT, qMaxT, _, maxQ = ChartLogic.ExpandRange(quantitySeries)
	if qMinT then
		minT, maxT = lower(minT, qMinT), upper(maxT, qMaxT)
	end
	if minT and minT == maxT then
		minT, maxT = minT - 3600, maxT + 3600
	end
	return { minT = minT, maxT = maxT, minV = minV, maxV = maxV, maxQ = maxQ }
end

--- Pixel mapping inside `box = { left, bottom, width, height }`: `{ low, high, step, qHigh, minT, maxT,
--- xAt(t), yAt(value), yAtQuantity(quantity) }`. Quantities get their own 0..qHigh axis when hasQuantity.
function ChartLogic.Scales(bounds, box, tickCount, hasQuantity)
	local low, high, step = ChartLogic.NiceScale(bounds.minV, bounds.maxV, tickCount, true)
	local qHigh = hasQuantity and select(2, ChartLogic.NiceScale(0, math.max(1, bounds.maxQ or 1), tickCount, true)) or 1
	local minT, maxT = bounds.minT, bounds.maxT
	local scales = { low = low, high = high, step = step, qHigh = qHigh, minT = minT, maxT = maxT }
	function scales.xAt(t)
		return box.left + (t - minT) / (maxT - minT) * box.width
	end
	function scales.yAt(v)
		return box.bottom + (v - low) / (high - low) * box.height
	end
	function scales.yAtQuantity(v)
		return box.bottom + (v / qHigh) * box.height
	end
	return scales
end

--- Mean value of the points, or nil when there are none.
function ChartLogic.Average(points)
	if #points == 0 then
		return nil
	end
	local total = 0
	for _, p in ipairs(points) do
		total = total + p.value
	end
	return total / #points
end

--- Hover targets `{ kind, pt, x, y }` for every point; quantities sit on the right axis.
function ChartLogic.HitTargets(scales, series, secondarySeries, quantitySeries)
	local targets = {}
	local function add(points, kind, yFn)
		for _, p in ipairs(points) do
			targets[#targets + 1] = { kind = kind, pt = p, x = scales.xAt(p.at), y = yFn(p.value) }
		end
	end
	add(series, "primary", scales.yAt)
	add(secondarySeries, "secondary", scales.yAt)
	add(quantitySeries, "quantity", scales.yAtQuantity)
	return targets
end
