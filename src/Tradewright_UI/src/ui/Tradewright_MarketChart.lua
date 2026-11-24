local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- The price chart of the Market item view: the last 48 scanned hours, or 14 or 90 days of daily prices
-- with the usual price drawn as a flat line.

local DAY = 24 * 3600
local RANGES = {
	{ id = "d90", label = L["90 days"], days = 90 },
	{ id = "d14", label = L["14 days"], days = 14 },
	{ id = "hours", label = L["48 hours"] },
}

local function rangeById(id)
	for _, range in ipairs(RANGES) do
		if range.id == id then
			return range
		end
	end
	return RANGES[#RANGES]
end

-- Daily points of one stored listing, oldest first, covering today and the `days - 1` days before it.
-- Shows whatever days are saved so far, so a range is never empty just because it is not full yet.
local function dailyPoints(pe, storageKey, days)
	local MS = pe.MarketSignals
	local fromTs = MS.DayStart(Tradewright:Now()) - (days - 1) * DAY
	return MS.DailyPoints(pe:GetDailyPriceHistory(storageKey), fromTs)
end

-- Chart series for a daily range: the day's middle price, the usual price as a flat line, listed quantity.
local function dailySeries(pe, storageKey, days)
	local usual = pe.GetUsualPrice and pe:GetUsualPrice(storageKey)
	local series = { primary = {}, secondary = {}, quantity = {} }
	for index, point in ipairs(dailyPoints(pe, storageKey, days)) do
		series.primary[index] = { at = point.at, value = point.p, meta = { min = point.lo, max = point.hi } }
		series.quantity[index] = { at = point.at, value = point.q }
		if usual then
			series.secondary[index] = { at = point.at, value = usual.usual }
		end
	end
	return series
end

--- Heading above the Market item chart with its range buttons. Replaces the plain "Hourly price" heading.
function Tradewright:CreateMarketChartHeading(view)
	local pe = self
	local heading = self:CreateHeading(view, L["Price history"])
	heading:SetPoint("TOPLEFT", view.facts, "BOTTOMLEFT", 0, -10)
	view.rangeButtons = {}
	local previous
	for _, range in ipairs(RANGES) do
		local button = self:CreateButton(view, range.label, function()
			pe:SetSetting("market.chartRange", range.id)
			if view.chartRow then
				view:ShowRow(view.chartRow)
			end
		end, { small = true })
		button.rangeId = range.id
		if previous then
			button:SetPoint("RIGHT", previous, "LEFT", 1, 0)
		else
			button:SetPoint("TOPRIGHT", view.facts, "BOTTOMRIGHT", 0, -8)
		end
		previous = button
		view.rangeButtons[#view.rangeButtons + 1] = button
	end
	heading:SetPoint("RIGHT", previous, "LEFT", -8, 0)
	return heading
end

--- Draw the chart of `view` for a Market row in the chosen range. `hourly` holds the series the view
--- already built from the last 48 scanned hours: `{ primary, secondary, quantity }`.
function Tradewright:ShowMarketChart(view, rowData, hourly)
	local range = rangeById(self:GetSetting("market.chartRange", "hours"))
	view.chartRow = rowData
	for _, button in ipairs(view.rangeButtons or {}) do
		self:StyleShellButton(button, button.rangeId == range.id)
	end
	local series = hourly
	if range.days then
		series = dailySeries(self, rowData.storageKey, range.days)
		view.graph:SetSeriesLabels(L["Daily price"], L["Usual price"], "Listed", L["Above usual"])
	else
		view.graph:SetSeriesLabels("Price", "Lowest", "Listed", nil)
	end
	view.graph:SetSeries(series.primary)
	view.graph:SetSecondarySeries(series.secondary)
	view.graph:SetQuantitySeries(series.quantity)
	view.graph:SetTooltipBuilder(nil)
	view.graph:Refresh()
end
