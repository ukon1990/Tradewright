local _, AuctionHelper = ...

-- The price chart of the Market item view: the last 48 scanned hours, or 14 or 90 days of daily prices
-- with the usual price drawn as a flat line.

local DAY = 24 * 3600
local RANGES = {
	{ id = "d90", label = "90 days", days = 90 },
	{ id = "d14", label = "14 days", days = 14 },
	{ id = "hours", label = "48 hours" },
}

local function rangeById(id)
	for _, range in ipairs(RANGES) do
		if range.id == id then
			return range
		end
	end
	return RANGES[#RANGES]
end

-- Daily points of one stored listing, oldest first, no older than `days`.
local function dailyPoints(pe, storageKey, days)
	local auction = pe:InitAuctionDB()
	local byDay = auction and auction.history.daily and auction.history.daily[storageKey] or {}
	local cutoff = AuctionHelper:Now() - days * DAY
	local points = {}
	for dayKey, entry in pairs(byDay) do
		local at = tonumber(dayKey)
		if at and at >= cutoff and tonumber(entry.p) then
			points[#points + 1] = { at = at, price = entry.p, low = entry.lo, high = entry.hi, qty = entry.q or 0 }
		end
	end
	table.sort(points, function(a, b)
		return a.at < b.at
	end)
	return points
end

-- Chart series for a daily range: the day's middle price, the usual price as a flat line, listed quantity.
local function dailySeries(pe, storageKey, days)
	local usual = pe.GetUsualPrice and pe:GetUsualPrice(storageKey)
	local series = { primary = {}, secondary = {}, quantity = {} }
	for index, point in ipairs(dailyPoints(pe, storageKey, days)) do
		series.primary[index] = { at = point.at, value = point.price, meta = { min = point.low, max = point.high } }
		series.quantity[index] = { at = point.at, value = point.qty }
		if usual then
			series.secondary[index] = { at = point.at, value = usual.usual }
		end
	end
	return series
end

--- Heading above the Market item chart with its range buttons. Replaces the plain "Hourly price" heading.
function AuctionHelper:CreateMarketChartHeading(view)
	local pe = self
	local heading = self:CreateHeading(view, "Price history")
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
function AuctionHelper:ShowMarketChart(view, rowData, hourly)
	local range = rangeById(self:GetSetting("market.chartRange", "hours"))
	view.chartRow = rowData
	for _, button in ipairs(view.rangeButtons or {}) do
		self:StyleShellButton(button, button.rangeId == range.id)
	end
	local series = hourly
	if range.days then
		series = dailySeries(self, rowData.storageKey, range.days)
		view.graph:SetSeriesLabels("Daily price", "Usual price", "Listed", "Above usual")
	else
		view.graph:SetSeriesLabels("Price", "Lowest", "Listed", nil)
	end
	view.graph:SetSeries(series.primary)
	view.graph:SetSecondarySeries(series.secondary)
	view.graph:SetQuantitySeries(series.quantity)
	view.graph:SetTooltipBuilder(nil)
	view.graph:Refresh()
end
