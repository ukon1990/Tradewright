local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Time-series chart in the style of Highcharts: faint gridlines on rounded ticks, a 2px line with a
-- fading area fill, round markers on sparse series, quantity as columns on a right axis, a legend,
-- and a crosshair that snaps to the nearest point on hover.

local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local MAX_MARKERS = 24
local Y_TICKS = 4
local X_TICKS = 4
local QUANTITY_AXIS_WIDTH = 34
local TITLE_HEIGHT = 16
-- Points closer than this to the hovered time count as "at" that time in the tooltip.
local TOOLTIP_MATCH_SEC = 1800
local ChartLogic = Tradewright.ChartLogic

local ChartMixin = {}

local function timeLabel(at, span)
	if span <= 36 * 3600 then
		return date("%H:%M", at)
	end
	return date("%b %d", at)
end

local function signedPercent(value)
	return string.format("%s%.1f%%", value >= 0 and "+" or "", value)
end

-- The point of a series nearest to time `at` (within TOOLTIP_MATCH_SEC), and its index.
local function pointAt(points, at)
	local found, foundIndex, distance
	for index, p in ipairs(points) do
		local d = math.abs(p.at - at)
		if d <= TOOLTIP_MATCH_SEC and (not distance or d < distance) then
			found, foundIndex, distance = p, index, d
		end
	end
	return found, foundIndex
end

--- Builds a chart frame. `opts`: title, series, plotHeight, padLeft, padRight, padTop, padBottom,
--- showTitle, yFormatter, tooltipBuilder, emptyText, accentColor.
function Tradewright:CreateTimeSeriesGraph(parent, opts)
	local holder = CreateFrame("Frame", nil, parent)
	for name, method in pairs(ChartMixin) do
		holder[name] = method
	end
	holder:InitChart(self, opts or {})
	return holder
end

function ChartMixin:InitChart(pe, opts)
	self.pe = pe
	self.theme = pe:GetTheme()
	self.padLeft = tonumber(opts.padLeft) or 58
	self.padRightBase = tonumber(opts.padRight) or 10
	self.padTop = tonumber(opts.padTop) or 16
	self.padBottom = tonumber(opts.padBottom) or 20
	self.pools = {}
	self.series, self.secondarySeries, self.quantitySeries = {}, {}, {}
	self.labels = { primary = "Price", secondary = L["Craft cost"], quantity = "Listed", margin = "Margin" }
	self.yFormatter = opts.yFormatter or function(v)
		return pe:FormatNumberGrouped(v)
	end
	self.rightYFormatter = function(v)
		return pe:FormatNumberGrouped(v)
	end
	self.tooltipBuilder = opts.tooltipBuilder
	self.emptyStateText = opts.emptyText or L["No data in this range."]
	self.colors = { primary = opts.accentColor or self.theme.accent, secondary = self.theme.warning, quantity = self.theme.success }
	self:CreatePlot(opts)
	self:CreateHoverMarks()
	self:SetScript("OnSizeChanged", self.Paint)
	self.title:SetText(opts.title or "")
	self:SetSeries(opts.series)
	self:Paint()
end

function ChartMixin:CreatePlot(opts)
	local showTitle = opts.showTitle ~= false
	local plotHeight = tonumber(opts.plotHeight) or 118
	self:SetHeight(plotHeight + self.padTop + self.padBottom + (showTitle and TITLE_HEIGHT or 0))
	local title = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	title:SetPoint("TOPLEFT", 0, 0)
	title:SetShown(showTitle)
	self.title = title
	local plot = CreateFrame("Frame", nil, self)
	plot:SetPoint("TOPLEFT", self, "TOPLEFT", 0, showTitle and -TITLE_HEIGHT or 0)
	plot:SetPoint("BOTTOMRIGHT")
	plot:EnableMouse(true)
	if plot.SetClipsChildren then
		plot:SetClipsChildren(true)
	end
	self.plot = plot
	self.canFill = plot.CreateTexture and plot:CreateTexture().SetVertexOffset ~= nil
	local emptyText = self:MutedText("CENTER")
	emptyText:SetPoint("LEFT", 20, 0)
	emptyText:SetPoint("RIGHT", -20, 0)
	emptyText:SetWordWrap(true)
	self.emptyText = emptyText
	plot:SetScript("OnUpdate", function()
		self:UpdateHover()
	end)
	plot:SetScript("OnLeave", function()
		self:ClearHover()
	end)
end

function ChartMixin:MutedText(justify)
	local muted = self.theme.textMuted
	local fs = self.plot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetWordWrap(false)
	fs:SetJustifyH(justify or "LEFT")
	fs:SetTextColor(muted.r, muted.g, muted.b)
	return fs
end

-- Pools of drawable regions, reused on every paint.
function ChartMixin:Take(name, make)
	local pool = self.pools[name]
	if not pool then
		pool = { items = {}, used = 0 }
		self.pools[name] = pool
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

function ChartMixin:ResetPools()
	for _, pool in pairs(self.pools) do
		for index = 1, #pool.items do
			pool.items[index]:Hide()
		end
		pool.used = 0
	end
end

function ChartMixin:TakeTexture(name, layer, sublevel, file)
	return self:Take(name, function()
		local texture = self.plot:CreateTexture(nil, layer, nil, sublevel)
		texture:SetTexture(file or WHITE)
		return texture
	end)
end

function ChartMixin:TakeLabel(name)
	return self:Take(name, function()
		return self:MutedText("RIGHT")
	end)
end

--- A pooled line from (x1, y1) to (x2, y2); `style` = { color, thickness, alpha }.
function ChartMixin:DrawLine(name, from, to, style)
	local line = self:Take(name, function()
		return self.plot:CreateLine(nil, "ARTWORK", nil, name == "primaryLine" and 2 or 1)
	end)
	local color = style.color
	line:SetThickness(style.thickness)
	line:SetColorTexture(color.r, color.g, color.b, style.alpha or 1)
	line:SetStartPoint("BOTTOMLEFT", self.plot, from.x, from.y)
	line:SetEndPoint("BOTTOMLEFT", self.plot, to.x, to.y)
end

-- Area under one segment: a rectangle from the baseline up to the higher end, with its top
-- corners pulled down to the line, fading out towards the baseline.
function ChartMixin:DrawFill(from, to, color)
	if not self.canFill or to.x - from.x < 0.5 then
		return
	end
	local top = math.max(from.y, to.y)
	local area = self:TakeTexture("fill", "BACKGROUND", 1)
	area:ClearAllPoints()
	area:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", from.x, self.padBottom)
	area:SetPoint("TOPRIGHT", self.plot, "BOTTOMLEFT", to.x, top)
	area:SetVertexOffset(1, 0, from.y - top)
	area:SetVertexOffset(3, 0, to.y - top)
	area:SetVertexOffset(2, 0, 0)
	area:SetVertexOffset(4, 0, 0)
	area:SetColorTexture(1, 1, 1, 1)
	if area.SetGradient and CreateColor then
		area:SetGradient("VERTICAL", CreateColor(color.r, color.g, color.b, 0.02), CreateColor(color.r, color.g, color.b, 0.32))
	else
		area:SetVertexColor(color.r, color.g, color.b, 0.18)
	end
end

function ChartMixin:DrawMarker(name, at, color, size)
	local dot = self:TakeTexture(name, "OVERLAY", 1, CIRCLE)
	dot:ClearAllPoints()
	dot:SetSize(size, size)
	dot:SetPoint("CENTER", self.plot, "BOTTOMLEFT", at.x, at.y)
	dot:SetVertexColor(color.r, color.g, color.b, 1)
end

function ChartMixin:PlotRight()
	return self.padLeft + self.box.width
end

-- Gridlines with price labels on the left and, with quantities, listed counts on the right.
function ChartMixin:DrawAxes()
	local scales = self.scales
	local low, high = scales.low, scales.high
	local right = self:PlotRight()
	for index, tick in ipairs(ChartLogic.TickValues(low, high, scales.step)) do
		local y = scales.yAt(tick)
		self:DrawLine("grid", { x = self.padLeft, y = y }, { x = right, y = y }, { color = self.theme.borderSubtle, thickness = 1, alpha = index == 1 and 1 or 0.7 })
		local label = self:TakeLabel("yLabel")
		label:ClearAllPoints()
		label:SetPoint("RIGHT", self.plot, "BOTTOMLEFT", self.padLeft - 6, y)
		label:SetText(self.yFormatter(tick))
		if #self.quantitySeries > 0 then
			local quantityLabel = self:TakeLabel("qLabel")
			quantityLabel:ClearAllPoints()
			quantityLabel:SetJustifyH("LEFT")
			quantityLabel:SetPoint("LEFT", self.plot, "BOTTOMLEFT", right + 6, y)
			quantityLabel:SetText(self.rightYFormatter(scales.qHigh * (tick - low) / (high - low)))
		end
	end
	self:DrawTimeAxis()
end

function ChartMixin:DrawTimeAxis()
	local scales = self.scales
	local span = scales.maxT - scales.minT
	for index = 0, X_TICKS - 1 do
		local t = scales.minT + span * index / (X_TICKS - 1)
		local label = self:TakeLabel("xLabel")
		label:ClearAllPoints()
		local justify = index == 0 and "LEFT" or index == X_TICKS - 1 and "RIGHT" or "CENTER"
		label:SetJustifyH(justify)
		label:SetPoint(justify == "CENTER" and "BOTTOM" or ("BOTTOM" .. justify), self.plot, "BOTTOMLEFT", scales.xAt(t), 3)
		label:SetText(timeLabel(t, span))
	end
end

-- Quantity columns behind the lines.
function ChartMixin:DrawQuantityColumns()
	local columnWidth = math.max(2, math.min(8, self.box.width / #self.quantitySeries * 0.6))
	local color = self.colors.quantity
	for _, p in ipairs(self.quantitySeries) do
		local height = self.scales.yAtQuantity(p.value) - self.padBottom
		if height > 0.5 then
			local column = self:TakeTexture("column", "BACKGROUND", 2)
			column:ClearAllPoints()
			column:SetPoint("BOTTOM", self.plot, "BOTTOMLEFT", self.scales.xAt(p.at), self.padBottom)
			column:SetSize(columnWidth, height)
			column:SetColorTexture(color.r, color.g, color.b, 0.35)
		end
	end
end

--- `style` = { name, color, thickness, withFill }.
function ChartMixin:DrawSeries(points, style)
	local xAt, yAt = self.scales.xAt, self.scales.yAt
	local markers = #points <= MAX_MARKERS
	for index, p in ipairs(points) do
		local from = { x = xAt(p.at), y = yAt(p.value) }
		local nextPoint = points[index + 1]
		if nextPoint then
			local to = { x = xAt(nextPoint.at), y = yAt(nextPoint.value) }
			if style.withFill then
				self:DrawFill(from, to, style.color)
			end
			self:DrawLine(style.name .. "Line", from, to, style)
		end
		if markers or index == #points then
			self:DrawMarker(style.name .. "Marker", from, style.color, style.thickness >= 2 and 6 or 5)
		end
	end
end

-- Average of the range as a dashed line with its value.
function ChartMixin:DrawAverage(average)
	local y = self.scales.yAt(average)
	local right = self:PlotRight()
	local dash = { color = self.theme.textMuted, thickness = 1, alpha = 0.7 }
	local x = self.padLeft
	while x < right do
		self:DrawLine("avgDash", { x = x, y = y }, { x = math.min(x + 5, right), y = y }, dash)
		x = x + 9
	end
	local label = self:TakeLabel("avgLabel")
	label:ClearAllPoints()
	label:SetJustifyH("LEFT")
	label:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", self.padLeft + 4, y + 2)
	label:SetText(L["avg "] .. self.yFormatter(average))
end

-- The latest value as a pill above (or below) the last point.
function ChartMixin:DrawLastValue()
	local last = self.series[#self.series]
	local lastX, lastY = self.scales.xAt(last.at), self.scales.yAt(last.value)
	local pill = self:TakeTexture("pill", "OVERLAY", 4)
	local pillText = self:Take("pillText", function()
		local fs = self.plot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetWordWrap(false)
		return fs
	end)
	local surface, accent = self.theme.surface1, self.colors.primary
	pillText:SetText(self.yFormatter(last.value))
	pillText:SetTextColor(surface.r, surface.g, surface.b)
	pillText:ClearAllPoints()
	local pillY = lastY + 14 <= self.padBottom + self.box.height and lastY + 6 or lastY - 22
	pill:ClearAllPoints()
	pill:SetSize(math.ceil(pillText:GetStringWidth()) + 10, 16)
	pill:SetPoint("BOTTOMRIGHT", self.plot, "BOTTOMLEFT", math.min(lastX, self:PlotRight()), pillY)
	pill:SetColorTexture(accent.r, accent.g, accent.b, 1)
	pillText:SetPoint("CENTER", pill, "CENTER", 0, 0)
	pillText:SetDrawLayer("OVERLAY", 5)
end

function ChartMixin:LegendKeys()
	local keys = { "primary" }
	if #self.secondarySeries > 0 then
		keys[#keys + 1] = "secondary"
	end
	if #self.quantitySeries > 0 then
		keys[#keys + 1] = "quantity"
	end
	return keys
end

-- Legend when more than one series is drawn.
function ChartMixin:DrawLegend()
	local keys = self:LegendKeys()
	if #keys < 2 then
		return
	end
	local x = self:PlotRight()
	for index = #keys, 1, -1 do
		local key = keys[index]
		local label = self:TakeLabel("legendLabel")
		label:ClearAllPoints()
		label:SetPoint("TOPRIGHT", self.plot, "TOPLEFT", x, -1)
		label:SetText(self.labels[key])
		local swatch = self:TakeTexture("legendSwatch", "OVERLAY", 0)
		swatch:ClearAllPoints()
		swatch:SetSize(10, key == "quantity" and 6 or 2)
		swatch:SetPoint("RIGHT", label, "LEFT", -4, 0)
		local color = self.colors[key]
		swatch:SetColorTexture(color.r, color.g, color.b, 1)
		x = x - label:GetStringWidth() - 30
	end
end

function ChartMixin:ShowEmpty()
	self.emptyText:SetText(self.emptyStateText)
	self.emptyText:Show()
end

function ChartMixin:Paint()
	self:ResetPools()
	self.geometry = nil
	self.emptyText:Hide()
	local bounds = ChartLogic.Bounds(self.series, self.secondarySeries, self.quantitySeries)
	local hasQuantity = #self.quantitySeries > 0
	local padRight = self.padRightBase + (hasQuantity and QUANTITY_AXIS_WIDTH or 0)
	local plot = self.plot
	local box = {
		left = self.padLeft,
		bottom = self.padBottom,
		width = plot:GetWidth() - self.padLeft - padRight,
		height = plot:GetHeight() - self.padTop - self.padBottom,
	}
	self.box = box
	if #self.series == 0 or not bounds.minV or box.width < 20 or box.height < 20 then
		return self:ShowEmpty()
	end
	self.scales = ChartLogic.Scales(bounds, box, Y_TICKS - 1, hasQuantity)
	self:DrawAxes()
	if hasQuantity then
		self:DrawQuantityColumns()
	end
	self:DrawSeries(self.secondarySeries, { name = "secondary", color = self.colors.secondary, thickness = 1.5 })
	self:DrawSeries(self.series, { name = "primary", color = self.colors.primary, thickness = 2, withFill = true })
	local average = ChartLogic.Average(self.series)
	if #self.series >= 2 then
		self:DrawAverage(average)
	end
	self:DrawLastValue()
	self:DrawLegend()
	self:BuildHoverTargets(average)
end

function ChartMixin:BuildHoverTargets(average)
	local targets = ChartLogic.HitTargets(self.scales, self.series, self.secondarySeries, self.quantitySeries)
	self.geometry = { targets = targets, top = self.padBottom + self.box.height, bottom = self.padBottom, average = average }
end

-- Hover marks: a crosshair, a white halo and a coloured dot on the snapped point.
function ChartMixin:CreateHoverMarks()
	local muted = self.theme.textMuted
	local crosshair = self.plot:CreateLine(nil, "OVERLAY", nil, 0)
	crosshair:SetThickness(1)
	crosshair:SetColorTexture(muted.r, muted.g, muted.b, 0.6)
	crosshair:Hide()
	self.crosshair = crosshair
	self.halo = self:CreateHoverDot(2, 12)
	self.hoverDot = self:CreateHoverDot(3, 7)
end

function ChartMixin:CreateHoverDot(sublevel, size)
	local dot = self.plot:CreateTexture(nil, "OVERLAY", nil, sublevel)
	dot:SetTexture(CIRCLE)
	dot:SetSize(size, size)
	dot:Hide()
	return dot
end

function ChartMixin:ClearHover()
	if self.hoverKey then
		GameTooltip:Hide()
	end
	self.hoverKey = nil
	self.crosshair:Hide()
	self.halo:Hide()
	self.hoverDot:Hide()
end

-- The hit target nearest the cursor, weighting horizontal distance first.
function ChartMixin:NearestTarget()
	local plot = self.plot
	local scale = plot:GetEffectiveScale()
	local cursorX, cursorY = GetCursorPosition()
	local px, py = cursorX / scale - plot:GetLeft(), cursorY / scale - plot:GetBottom()
	local best, bestScore
	for _, target in ipairs(self.geometry.targets) do
		local score = math.abs(px - target.x) * 4 + math.abs(py - target.y)
		if not bestScore or score < bestScore then
			best, bestScore = target, score
		end
	end
	return best
end

-- Hover: snap to the nearest point, draw a crosshair, enlarge the point and place the tooltip beside it.
function ChartMixin:UpdateHover()
	if not self.geometry or not self.plot:IsMouseOver() then
		if self.hoverKey then
			self:ClearHover()
		end
		return
	end
	local best = self:NearestTarget()
	if not best then
		return
	end
	local key = best.kind .. ":" .. tostring(best.pt.at)
	if key == self.hoverKey then
		return
	end
	self.hoverKey = key
	self:ShowHoverMarks(best)
	self:ShowHoverTooltip(best)
end

function ChartMixin:ShowHoverMarks(target)
	local plot, color = self.plot, self.colors[target.kind]
	self.crosshair:SetStartPoint("BOTTOMLEFT", plot, target.x, self.geometry.bottom)
	self.crosshair:SetEndPoint("BOTTOMLEFT", plot, target.x, self.geometry.top)
	self.crosshair:Show()
	self.halo:ClearAllPoints()
	self.halo:SetPoint("CENTER", plot, "BOTTOMLEFT", target.x, target.y)
	self.halo:SetVertexColor(1, 1, 1, 0.9)
	self.halo:Show()
	self.hoverDot:ClearAllPoints()
	self.hoverDot:SetPoint("CENTER", plot, "BOTTOMLEFT", target.x, target.y)
	self.hoverDot:SetVertexColor(color.r, color.g, color.b, 1)
	self.hoverDot:Show()
end

function ChartMixin:ShowHoverTooltip(target)
	local plot = self.plot
	GameTooltip:SetOwner(plot, "ANCHOR_NONE")
	GameTooltip:ClearAllPoints()
	if target.x > plot:GetWidth() / 2 then
		GameTooltip:SetPoint("BOTTOMRIGHT", plot, "BOTTOMLEFT", target.x - 10, target.y + 10)
	else
		GameTooltip:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", target.x + 10, target.y + 10)
	end
	GameTooltip:ClearLines()
	if type(self.tooltipBuilder) == "function" then
		self.tooltipBuilder(GameTooltip, target)
	else
		self:BuildSharedTooltip(GameTooltip, target.pt.at)
	end
	GameTooltip:Show()
end

-- Highcharts-style shared tooltip: every series' value at the hovered time, the change since the
-- previous point, the gap to the range average, and the margin when price and craft cost both exist.
function ChartMixin:BuildSharedTooltip(tip, at)
	local pe = self.pe
	tip:AddLine(pe.FormatScanTimestamp and pe:FormatScanTimestamp(at) or date("%Y-%m-%d %H:%M", at), 1, 1, 1)
	local primary, index = pointAt(self.series, at)
	if primary then
		self:AddPrimaryTooltipLines(tip, primary, index)
	end
	local secondary = pointAt(self.secondarySeries, at)
	if secondary then
		self:AddSecondaryTooltipLines(tip, secondary, primary)
	end
	local quantity = pointAt(self.quantitySeries, at)
	if quantity then
		local color = self.colors.quantity
		tip:AddDoubleLine(self.labels.quantity, self.rightYFormatter(quantity.value), color.r, color.g, color.b, 1, 1, 1)
	end
end

function ChartMixin:AddPrimaryTooltipLines(tip, primary, index)
	local color = self.colors.primary
	tip:AddDoubleLine(self.labels.primary, self.yFormatter(primary.value), color.r, color.g, color.b, 1, 1, 1)
	self:AddChangeTooltipLine(tip, primary, self.series[index - 1])
	local muted = self.theme.textMuted
	local average = self.geometry and self.geometry.average
	if average and average > 0 and #self.series >= 2 then
		local gap = (primary.value - average) / average * 100
		tip:AddDoubleLine(L["Vs range average"], signedPercent(gap), muted.r, muted.g, muted.b, 1, 1, 1)
	end
	local meta = primary.meta or {}
	if meta.min and meta.max and meta.max > meta.min then
		tip:AddDoubleLine(L["Hour low / high"], self.yFormatter(meta.min) .. " / " .. self.yFormatter(meta.max), muted.r, muted.g, muted.b, 1, 1, 1)
	end
end

function ChartMixin:AddChangeTooltipLine(tip, point, previous)
	if not previous or previous.value <= 0 then
		return
	end
	local theme, muted = self.theme, self.theme.textMuted
	local change = (point.value - previous.value) / previous.value * 100
	local tone = change > 0.5 and theme.success or change < -0.5 and theme.danger or muted
	tip:AddDoubleLine(L["Since previous"], signedPercent(change), muted.r, muted.g, muted.b, tone.r, tone.g, tone.b)
end

function ChartMixin:AddSecondaryTooltipLines(tip, secondary, primary)
	local theme, color, muted = self.theme, self.colors.secondary, self.theme.textMuted
	tip:AddDoubleLine(self.labels.secondary, self.yFormatter(secondary.value), color.r, color.g, color.b, 1, 1, 1)
	if primary and self.labels.margin then
		local margin = primary.value - secondary.value
		local tone = margin >= 0 and theme.success or theme.danger
		local text = (margin >= 0 and "+" or "-") .. self.yFormatter(math.abs(margin))
		tip:AddDoubleLine(self.labels.margin, text, muted.r, muted.g, muted.b, tone.r, tone.g, tone.b)
	end
end

function ChartMixin:SetTitle(text)
	self.title:SetText(text or "")
end

function ChartMixin:SetEmptyText(text)
	self.emptyStateText = text or self.emptyStateText
end

function ChartMixin:SetSeries(data)
	self.series = type(data) == "table" and data or {}
end

function ChartMixin:SetSecondarySeries(data)
	self.secondarySeries = type(data) == "table" and data or {}
end

function ChartMixin:SetQuantitySeries(data)
	self.quantitySeries = type(data) == "table" and data or {}
end

-- Names shown in the legend: primary, secondary, quantity.
-- `margin`: label for price minus craft cost in the tooltip (nil hides it).
function ChartMixin:SetSeriesLabels(primary, secondary, quantity, margin)
	local labels = self.labels
	labels.primary = primary or labels.primary
	labels.secondary = secondary or labels.secondary
	labels.quantity = quantity or labels.quantity
	labels.margin = margin
end

function ChartMixin:SetYFormatter(fn)
	if type(fn) == "function" then
		self.yFormatter = fn
	end
end

function ChartMixin:SetRightYFormatter(fn)
	if type(fn) == "function" then
		self.rightYFormatter = fn
	end
end

function ChartMixin:SetTooltipBuilder(fn)
	self.tooltipBuilder = fn
end

function ChartMixin:SetAccentColor(color)
	if type(color) == "table" then
		self.colors.primary = color
	end
end

function ChartMixin:SetSecondaryAccentColor(color)
	if type(color) == "table" then
		self.colors.secondary = color
	end
end

function ChartMixin:SetQuantityAccentColor(color)
	if type(color) == "table" then
		self.colors.quantity = color
	end
end

function ChartMixin:Refresh()
	self:ClearHover()
	self:Paint()
end
