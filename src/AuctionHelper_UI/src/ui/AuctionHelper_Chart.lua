local _, AuctionHelper = ...

-- Time-series chart in the style of Highcharts: faint gridlines on rounded ticks, a 2px line with a
-- fading area fill, round markers on sparse series, quantity as columns on a right axis, a legend,
-- and a crosshair that snaps to the nearest point on hover.

local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local MAX_MARKERS = 24
local Y_TICKS = 4
local X_TICKS = 4
local ChartLogic = AuctionHelper.ChartLogic

local function timeLabel(at, span)
	if span <= 36 * 3600 then
		return date("%H:%M", at)
	end
	return date("%b %d", at)
end

function AuctionHelper:CreateTimeSeriesGraph(parent, opts)
	opts = opts or {}
	local pe = self
	local theme = self:GetTheme()
	local plotH = tonumber(opts.plotHeight) or 118
	local padL = tonumber(opts.padLeft) or 58
	local padRBase = tonumber(opts.padRight) or 10
	local padQtyAxis = 34
	local padT = tonumber(opts.padTop) or 16
	local padB = tonumber(opts.padBottom) or 20
	local showTitle = opts.showTitle ~= false

	local holder = CreateFrame("Frame", nil, parent)
	holder:SetHeight(plotH + padT + padB + (showTitle and 16 or 0))
	local title = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	title:SetPoint("TOPLEFT", 0, 0)
	title:SetShown(showTitle)

	local plot = CreateFrame("Frame", nil, holder)
	plot:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, showTitle and -16 or 0)
	plot:SetPoint("BOTTOMRIGHT")
	plot:EnableMouse(true)
	if plot.SetClipsChildren then
		plot:SetClipsChildren(true)
	end

	local function mutedText(justify)
		local fs = plot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetWordWrap(false)
		fs:SetJustifyH(justify or "LEFT")
		fs:SetTextColor(theme.textMuted.r, theme.textMuted.g, theme.textMuted.b)
		return fs
	end
	local emptyText = mutedText("CENTER")
	emptyText:SetPoint("LEFT", 20, 0)
	emptyText:SetPoint("RIGHT", -20, 0)
	emptyText:SetWordWrap(true)

	-- Pools of drawable regions, reused on every paint.
	local pools = {}
	local function take(name, make)
		local pool = pools[name]
		if not pool then
			pool = { items = {}, used = 0 }
			pools[name] = pool
		end
		pool.used = pool.used + 1
		local item = pool.items[pool.used]
		if not item then
			item = make()
			pool.items[pool.used] = item
		end
		item:Show()
		return item
	end
	local function resetPools()
		for _, pool in pairs(pools) do
			for index = 1, #pool.items do
				pool.items[index]:Hide()
			end
			pool.used = 0
		end
	end
	local function newLine(layer, sublevel)
		return function()
			return plot:CreateLine(nil, layer or "ARTWORK", nil, sublevel or 0)
		end
	end
	local function newTexture(layer, sublevel, file)
		return function()
			local t = plot:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 0)
			t:SetTexture(file or WHITE)
			return t
		end
	end
	local newLabel = function()
		return mutedText("RIGHT")
	end

	local series, secondarySeries, quantitySeries = {}, {}, {}
	local labels = { primary = "Price", secondary = "Craft cost", quantity = "Listed", margin = "Margin" }
	local yFormatter = opts.yFormatter or function(v)
		return pe:FormatNumberGrouped(v)
	end
	local rightYFormatter = function(v)
		return pe:FormatNumberGrouped(v)
	end
	local tooltipBuilder = opts.tooltipBuilder
	local emptyStateText = opts.emptyText or "No data in this range."
	local colors = {
		primary = opts.accentColor or theme.accent,
		secondary = theme.warning,
		quantity = theme.success,
	}
	local canFill = plot.CreateTexture and plot:CreateTexture().SetVertexOffset ~= nil

	local function drawLine(name, x1, y1, x2, y2, color, thickness, alpha)
		local line = take(name, newLine("ARTWORK", name == "primaryLine" and 2 or 1))
		line:SetThickness(thickness)
		line:SetColorTexture(color.r, color.g, color.b, alpha or 1)
		line:SetStartPoint("BOTTOMLEFT", plot, x1, y1)
		line:SetEndPoint("BOTTOMLEFT", plot, x2, y2)
	end

	-- Area under one segment: a rectangle from the baseline up to the higher end, with its top
	-- corners pulled down to the line, fading out towards the baseline.
	local function drawFill(x1, y1, x2, y2, baseline, color)
		if not canFill or x2 - x1 < 0.5 then
			return
		end
		local top = math.max(y1, y2)
		local area = take("fill", newTexture("BACKGROUND", 1))
		area:ClearAllPoints()
		area:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", x1, baseline)
		area:SetPoint("TOPRIGHT", plot, "BOTTOMLEFT", x2, top)
		area:SetVertexOffset(1, 0, y1 - top)
		area:SetVertexOffset(3, 0, y2 - top)
		area:SetVertexOffset(2, 0, 0)
		area:SetVertexOffset(4, 0, 0)
		area:SetColorTexture(1, 1, 1, 1)
		if area.SetGradient and CreateColor then
			area:SetGradient("VERTICAL", CreateColor(color.r, color.g, color.b, 0.02), CreateColor(color.r, color.g, color.b, 0.32))
		else
			area:SetVertexColor(color.r, color.g, color.b, 0.18)
		end
	end

	local function drawMarker(name, x, y, color, size)
		local dot = take(name, newTexture("OVERLAY", 1, CIRCLE))
		dot:ClearAllPoints()
		dot:SetSize(size, size)
		dot:SetPoint("CENTER", plot, "BOTTOMLEFT", x, y)
		dot:SetVertexColor(color.r, color.g, color.b, 1)
	end

	local geometry, box, scales

	local function drawValueAxes()
		local low, high, qHigh = scales.low, scales.high, scales.qHigh
		local right = padL + box.width
		for index, tick in ipairs(ChartLogic.TickValues(low, high, scales.step)) do
			local y = scales.yAt(tick)
			drawLine("grid", padL, y, right, y, theme.borderSubtle, 1, index == 1 and 1 or 0.7)
			local label = take("yLabel", newLabel)
			label:ClearAllPoints()
			label:SetPoint("RIGHT", plot, "BOTTOMLEFT", padL - 6, y)
			label:SetText(yFormatter(tick))
			if #quantitySeries > 0 then
				local qLabel = take("qLabel", newLabel)
				qLabel:ClearAllPoints()
				qLabel:SetJustifyH("LEFT")
				qLabel:SetPoint("LEFT", plot, "BOTTOMLEFT", right + 6, y)
				qLabel:SetText(rightYFormatter(qHigh * (tick - low) / (high - low)))
			end
		end
	end

	local function drawTimeAxis()
		local span = scales.maxT - scales.minT
		for index = 0, X_TICKS - 1 do
			local t = scales.minT + span * index / (X_TICKS - 1)
			local label = take("xLabel", newLabel)
			label:ClearAllPoints()
			local justify = index == 0 and "LEFT" or index == X_TICKS - 1 and "RIGHT" or "CENTER"
			label:SetJustifyH(justify)
			label:SetPoint(justify == "CENTER" and "BOTTOM" or ("BOTTOM" .. justify), plot, "BOTTOMLEFT", scales.xAt(t), 3)
			label:SetText(timeLabel(t, span))
		end
	end

	-- Quantity columns behind the lines.
	local function drawQuantityColumns()
		local columnWidth = math.max(2, math.min(8, box.width / #quantitySeries * 0.6))
		local qc = colors.quantity
		for _, p in ipairs(quantitySeries) do
			local h = scales.yAtQ(p.value) - padB
			if h > 0.5 then
				local column = take("column", newTexture("BACKGROUND", 2))
				column:ClearAllPoints()
				column:SetPoint("BOTTOM", plot, "BOTTOMLEFT", scales.xAt(p.at), padB)
				column:SetSize(columnWidth, h)
				column:SetColorTexture(qc.r, qc.g, qc.b, 0.35)
			end
		end
	end

	local function drawSeries(points, color, thickness, name, withFill)
		local xAt, yAt = scales.xAt, scales.yAt
		local markers = #points <= MAX_MARKERS
		for index, p in ipairs(points) do
			local x, y = xAt(p.at), yAt(p.value)
			local nextPoint = points[index + 1]
			if nextPoint then
				local x2, y2 = xAt(nextPoint.at), yAt(nextPoint.value)
				if withFill then
					drawFill(x, y, x2, y2, padB, color)
				end
				drawLine(name .. "Line", x, y, x2, y2, color, thickness)
			end
			if markers or index == #points then
				drawMarker(name .. "Marker", x, y, color, thickness >= 2 and 6 or 5)
			end
		end
	end

	-- Average of the range as a dashed line with its value.
	local function drawAverage(average)
		local y = scales.yAt(average)
		local right = padL + box.width
		local x = padL
		while x < right do
			drawLine("avgDash", x, y, math.min(x + 5, right), y, theme.textMuted, 1, 0.7)
			x = x + 9
		end
		local avgLabel = take("avgLabel", newLabel)
		avgLabel:ClearAllPoints()
		avgLabel:SetJustifyH("LEFT")
		avgLabel:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", padL + 4, y + 2)
		avgLabel:SetText("avg " .. yFormatter(average))
	end

	-- The latest value as a pill above (or below) the last point.
	local function drawLatestValue()
		local last = series[#series]
		local lastX, lastY = scales.xAt(last.at), scales.yAt(last.value)
		local pill = take("pill", newTexture("OVERLAY", 4))
		local pillText = take("pillText", function()
			local fs = plot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			fs:SetWordWrap(false)
			return fs
		end)
		pillText:SetText(yFormatter(last.value))
		pillText:SetTextColor(theme.surface1.r, theme.surface1.g, theme.surface1.b)
		pillText:ClearAllPoints()
		local pillW = math.ceil(pillText:GetStringWidth()) + 10
		local pillX = math.min(lastX, padL + box.width)
		local pillY = lastY + 14 <= padB + box.height and lastY + 6 or lastY - 22
		pill:ClearAllPoints()
		pill:SetSize(pillW, 16)
		pill:SetPoint("BOTTOMRIGHT", plot, "BOTTOMLEFT", pillX, pillY)
		pill:SetColorTexture(colors.primary.r, colors.primary.g, colors.primary.b, 1)
		pillText:SetPoint("CENTER", pill, "CENTER", 0, 0)
		pillText:SetDrawLayer("OVERLAY", 5)
	end

	-- Legend when more than one series is drawn.
	local function drawLegend()
		local keys = { "primary" }
		if #secondarySeries > 0 then
			keys[#keys + 1] = "secondary"
		end
		if #quantitySeries > 0 then
			keys[#keys + 1] = "quantity"
		end
		if #keys < 2 then
			return
		end
		local x = padL + box.width
		for index = #keys, 1, -1 do
			local key = keys[index]
			local label = take("legendLabel", newLabel)
			label:ClearAllPoints()
			label:SetPoint("TOPRIGHT", plot, "TOPLEFT", x, -1)
			label:SetText(labels[key])
			local swatch = take("legendSwatch", newTexture("OVERLAY", 0))
			swatch:ClearAllPoints()
			swatch:SetSize(10, key == "quantity" and 6 or 2)
			swatch:SetPoint("RIGHT", label, "LEFT", -4, 0)
			local c = colors[key]
			swatch:SetColorTexture(c.r, c.g, c.b, 1)
			x = x - label:GetStringWidth() - 30
		end
	end

	local function paint()
		resetPools()
		geometry = nil
		emptyText:Hide()
		local bounds = ChartLogic.Bounds(series, secondarySeries, quantitySeries)
		local hasQty = #quantitySeries > 0
		local padR = padRBase + (hasQty and padQtyAxis or 0)
		box = { left = padL, bottom = padB, width = plot:GetWidth() - padL - padR, height = plot:GetHeight() - padT - padB }
		if #series == 0 or not bounds.minV or box.width < 20 or box.height < 20 then
			emptyText:SetText(emptyStateText)
			emptyText:Show()
			return
		end
		scales = ChartLogic.Scales(bounds, box, Y_TICKS - 1, hasQty)
		drawValueAxes()
		drawTimeAxis()
		if hasQty then
			drawQuantityColumns()
		end
		drawSeries(secondarySeries, colors.secondary, 1.5, "secondary", false)
		drawSeries(series, colors.primary, 2, "primary", true)
		local average = ChartLogic.Average(series)
		if #series >= 2 then
			drawAverage(average)
		end
		drawLatestValue()
		drawLegend()
		local targets = ChartLogic.HitTargets(scales, series, secondarySeries, quantitySeries)
		geometry = { targets = targets, top = padB + box.height, bottom = padB, average = average }
	end

	-- Hover: snap to the nearest point (by horizontal distance first), draw a crosshair, enlarge the
	-- point and place the tooltip beside it.
	local crosshair = plot:CreateLine(nil, "OVERLAY", nil, 0)
	crosshair:SetThickness(1)
	crosshair:SetColorTexture(theme.textMuted.r, theme.textMuted.g, theme.textMuted.b, 0.6)
	crosshair:Hide()
	local halo = plot:CreateTexture(nil, "OVERLAY", nil, 2)
	halo:SetTexture(CIRCLE)
	halo:SetSize(12, 12)
	halo:Hide()
	local dot = plot:CreateTexture(nil, "OVERLAY", nil, 3)
	dot:SetTexture(CIRCLE)
	dot:SetSize(7, 7)
	dot:Hide()
	local hoverKey

	local function clearHover()
		if hoverKey then
			GameTooltip:Hide()
		end
		hoverKey = nil
		crosshair:Hide()
		halo:Hide()
		dot:Hide()
	end

	plot:SetScript("OnUpdate", function()
		if not geometry or not plot:IsMouseOver() then
			if hoverKey then
				clearHover()
			end
			return
		end
		local scale = plot:GetEffectiveScale()
		local cx, cy = GetCursorPosition()
		local px, py = cx / scale - plot:GetLeft(), cy / scale - plot:GetBottom()
		local best, bestScore
		for _, target in ipairs(geometry.targets) do
			local score = math.abs(px - target.x) * 4 + math.abs(py - target.y)
			if not bestScore or score < bestScore then
				best, bestScore = target, score
			end
		end
		if not best then
			return
		end
		local key = best.kind .. ":" .. tostring(best.pt.at)
		if key == hoverKey then
			return
		end
		hoverKey = key
		local color = colors[best.kind]
		crosshair:SetStartPoint("BOTTOMLEFT", plot, best.x, geometry.bottom)
		crosshair:SetEndPoint("BOTTOMLEFT", plot, best.x, geometry.top)
		crosshair:Show()
		halo:ClearAllPoints()
		halo:SetPoint("CENTER", plot, "BOTTOMLEFT", best.x, best.y)
		halo:SetVertexColor(1, 1, 1, 0.9)
		halo:Show()
		dot:ClearAllPoints()
		dot:SetPoint("CENTER", plot, "BOTTOMLEFT", best.x, best.y)
		dot:SetVertexColor(color.r, color.g, color.b, 1)
		dot:Show()

		GameTooltip:SetOwner(plot, "ANCHOR_NONE")
		GameTooltip:ClearAllPoints()
		if best.x > plot:GetWidth() / 2 then
			GameTooltip:SetPoint("BOTTOMRIGHT", plot, "BOTTOMLEFT", best.x - 10, best.y + 10)
		else
			GameTooltip:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", best.x + 10, best.y + 10)
		end
		GameTooltip:ClearLines()
		if type(tooltipBuilder) == "function" then
			tooltipBuilder(GameTooltip, best)
		else
			holder:BuildSharedTooltip(GameTooltip, best.pt.at)
		end
		GameTooltip:Show()
	end)
	plot:SetScript("OnLeave", clearHover)

	-- The point of a series nearest to time `at` (within half an hour), or nil.
	local function pointAt(points, at)
		local found, foundIndex, distance
		for index, p in ipairs(points) do
			local d = math.abs(p.at - at)
			if d <= 1800 and (not distance or d < distance) then
				found, foundIndex, distance = p, index, d
			end
		end
		return found, foundIndex
	end

	-- Highcharts-style shared tooltip: every series' value at the hovered time, the change since the
	-- previous point, the gap to the range average, and the margin when price and craft cost both exist.
	function holder:BuildSharedTooltip(tip, at)
		local muted = theme.textMuted
		tip:AddLine(pe.FormatScanTimestamp and pe:FormatScanTimestamp(at) or date("%Y-%m-%d %H:%M", at), 1, 1, 1)
		local primary, index = pointAt(series, at)
		if primary then
			local c = colors.primary
			tip:AddDoubleLine(labels.primary, yFormatter(primary.value), c.r, c.g, c.b, 1, 1, 1)
			local previous = series[index - 1]
			if previous and previous.value > 0 then
				local change = (primary.value - previous.value) / previous.value * 100
				local sign = change >= 0 and "+" or ""
				local tone = change > 0.5 and theme.success or change < -0.5 and theme.danger or muted
				tip:AddDoubleLine("Since previous", string.format("%s%.1f%%", sign, change), muted.r, muted.g, muted.b, tone.r, tone.g, tone.b)
			end
			local average = geometry and geometry.average
			if average and average > 0 and #series >= 2 then
				local gap = (primary.value - average) / average * 100
				tip:AddDoubleLine("Vs range average", string.format("%s%.1f%%", gap >= 0 and "+" or "", gap), muted.r, muted.g, muted.b, 1, 1, 1)
			end
			local meta = primary.meta or {}
			if meta.min and meta.max and meta.max > meta.min then
				tip:AddDoubleLine("Hour low / high", yFormatter(meta.min) .. " / " .. yFormatter(meta.max), muted.r, muted.g, muted.b, 1, 1, 1)
			end
		end
		local secondary = pointAt(secondarySeries, at)
		if secondary then
			local c = colors.secondary
			tip:AddDoubleLine(labels.secondary, yFormatter(secondary.value), c.r, c.g, c.b, 1, 1, 1)
			if primary and labels.margin then
				local margin = primary.value - secondary.value
				local tone = margin >= 0 and theme.success or theme.danger
				tip:AddDoubleLine(labels.margin, (margin >= 0 and "+" or "-") .. yFormatter(math.abs(margin)), muted.r, muted.g, muted.b, tone.r, tone.g, tone.b)
			end
		end
		local quantity = pointAt(quantitySeries, at)
		if quantity then
			local c = colors.quantity
			tip:AddDoubleLine(labels.quantity, rightYFormatter(quantity.value), c.r, c.g, c.b, 1, 1, 1)
		end
	end

	holder.plot = plot
	holder.title = title
	function holder:SetTitle(text)
		title:SetText(text or "")
	end
	function holder:SetEmptyText(text)
		emptyStateText = text or emptyStateText
	end
	function holder:SetSeries(data)
		series = type(data) == "table" and data or {}
	end
	function holder:SetSecondarySeries(data)
		secondarySeries = type(data) == "table" and data or {}
	end
	function holder:SetQuantitySeries(data)
		quantitySeries = type(data) == "table" and data or {}
	end
	-- Names shown in the legend: primary, secondary, quantity.
	-- `margin`: label for price minus craft cost in the tooltip (nil hides it).
	function holder:SetSeriesLabels(primary, secondary, quantity, margin)
		labels.primary = primary or labels.primary
		labels.secondary = secondary or labels.secondary
		labels.quantity = quantity or labels.quantity
		labels.margin = margin
	end
	function holder:SetYFormatter(fn)
		if type(fn) == "function" then
			yFormatter = fn
		end
	end
	function holder:SetRightYFormatter(fn)
		if type(fn) == "function" then
			rightYFormatter = fn
		end
	end
	function holder:SetTooltipBuilder(fn)
		tooltipBuilder = fn
	end
	function holder:SetAccentColor(c)
		if type(c) == "table" then
			colors.primary = c
		end
	end
	function holder:SetSecondaryAccentColor(c)
		if type(c) == "table" then
			colors.secondary = c
		end
	end
	function holder:SetQuantityAccentColor(c)
		if type(c) == "table" then
			colors.quantity = c
		end
	end
	function holder:Refresh()
		clearHover()
		paint()
	end
	holder:SetScript("OnSizeChanged", function()
		paint()
	end)

	title:SetText(opts.title or "")
	holder:SetSeries(opts.series)
	paint()
	return holder
end
