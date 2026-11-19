local addonName, ProfessionExporter = ...

local function copySelection(selection)
	local out = {}
	if type(selection) ~= "table" then
		return out
	end
	for key, value in pairs(selection) do
		if value then
			out[key] = true
		end
	end
	return out
end

function ProfessionExporter:IsFilterSelectionEmpty(selection)
	return type(selection) ~= "table" or next(selection) == nil
end

function ProfessionExporter:CountFilterSelection(selection)
	local count = 0
	if type(selection) ~= "table" then
		return count
	end
	for _, value in pairs(selection) do
		if value then
			count = count + 1
		end
	end
	return count
end

function ProfessionExporter:GetFilterSelectionSummary(options, selection, allLabel)
	if self:IsFilterSelectionEmpty(selection) then
		return allLabel
	end

	local selectedLabels = {}
	for _, option in ipairs(options or {}) do
		if option.value ~= "all" and selection[option.value] then
			table.insert(selectedLabels, option.label)
		end
	end

	if #selectedLabels == 0 then
		return allLabel
	end
	if #selectedLabels <= 2 then
		return table.concat(selectedLabels, ", ")
	end
	return string.format("%d selected", #selectedLabels)
end

function ProfessionExporter:NormalizeFilterSelection(selection, options)
	local valid = {}
	for _, option in ipairs(options or {}) do
		if option.value ~= "all" then
			valid[option.value] = true
		end
	end

	local normalized = {}
	for key, value in pairs(selection or {}) do
		if value and valid[key] then
			normalized[key] = true
		end
	end
	return normalized
end

function ProfessionExporter:CreateMultiSelectDropdown(parent, config)
	config = config or {}

	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize((config.width or 210) + 32, 52)

	local title = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	title:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
	title:SetText(config.label or "Filter")
	holder.title = title

	local dropdown = CreateFrame("Frame", nil, holder, "UIDropDownMenuTemplate")
	dropdown:SetPoint("TOPLEFT", holder, "TOPLEFT", -16, -12)
	holder.dropdown = dropdown
	holder.width = config.width or 210
	holder.allLabel = config.allLabel or "All"
	holder.options = config.options or {}
	holder.currentOptions = nil
	holder.getOptions = config.getOptions
	holder.getSelection = config.getSelection
	holder.setSelection = config.setSelection
	holder.onChanged = config.onChanged

	local function getOptions()
		if holder.currentOptions then
			return holder.currentOptions
		end
		if type(holder.getOptions) == "function" then
			return holder.getOptions() or {}
		end
		return holder.options or {}
	end

	local function getSelection()
		if type(holder.getSelection) == "function" then
			return holder.getSelection() or {}
		end
		return {}
	end

	local function setSelection(selection)
		selection = copySelection(selection)
		if type(holder.setSelection) == "function" then
			holder.setSelection(selection)
		end
		return selection
	end

	local function updateText()
		UIDropDownMenu_SetWidth(dropdown, holder.width)
		UIDropDownMenu_SetText(
			dropdown,
			ProfessionExporter:GetFilterSelectionSummary(getOptions(), getSelection(), holder.allLabel)
		)
	end

	holder.SetOptions = function(_, options)
		holder.currentOptions = options or {}
		updateText()
	end

	holder.RefreshText = updateText

	UIDropDownMenu_SetWidth(dropdown, holder.width)
	UIDropDownMenu_JustifyText(dropdown, "LEFT")
	UIDropDownMenu_Initialize(dropdown, function(_, level)
		if level ~= 1 then
			return
		end

		local allInfo = UIDropDownMenu_CreateInfo()
		allInfo.text = holder.allLabel
		allInfo.isNotRadio = true
		allInfo.keepShownOnClick = true
		allInfo.checked = function()
			return ProfessionExporter:IsFilterSelectionEmpty(getSelection())
		end
		allInfo.func = function()
			setSelection({})
			updateText()
			if type(holder.onChanged) == "function" then
				holder.onChanged({})
			end
		end
		UIDropDownMenu_AddButton(allInfo, level)

		for _, option in ipairs(getOptions()) do
			if option.value ~= "all" then
				local info = UIDropDownMenu_CreateInfo()
				info.text = option.label
				info.isNotRadio = true
				info.keepShownOnClick = true
				info.checked = function()
					return getSelection()[option.value] == true
				end
				info.func = function()
					local nextSelection = copySelection(getSelection())
					if nextSelection[option.value] then
						nextSelection[option.value] = nil
					else
						nextSelection[option.value] = true
					end
					setSelection(nextSelection)
					updateText()
					if type(holder.onChanged) == "function" then
						holder.onChanged(nextSelection)
					end
				end
				UIDropDownMenu_AddButton(info, level)
			end
		end
	end, "MENU")

	updateText()
	return holder
end

function ProfessionExporter:CreateSingleSelectDropdown(parent, config)
	config = config or {}

	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize((config.width or 210) + 32, 52)

	local title = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	title:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
	title:SetText(config.label or "Select")
	holder.title = title

	local dropdown = CreateFrame("Frame", nil, holder, "UIDropDownMenuTemplate")
	dropdown:SetPoint("TOPLEFT", holder, "TOPLEFT", -16, -12)
	holder.dropdown = dropdown
	holder.width = config.width or 210
	holder.options = config.options or {}
	holder.currentOptions = nil
	holder.getOptions = config.getOptions
	holder.getValue = config.getValue
	holder.setValue = config.setValue
	holder.onChanged = config.onChanged

	local function getOptions()
		if holder.currentOptions then
			return holder.currentOptions
		end
		if type(holder.getOptions) == "function" then
			return holder.getOptions() or {}
		end
		return holder.options or {}
	end

	local function getValue()
		if type(holder.getValue) == "function" then
			return holder.getValue()
		end
		return nil
	end

	local function updateText()
		local current = getValue()
		local label = config.placeholder or "Select"
		for _, option in ipairs(getOptions()) do
			if option.value == current then
				label = option.label
				break
			end
		end
		UIDropDownMenu_SetWidth(dropdown, holder.width)
		UIDropDownMenu_SetText(dropdown, label)
	end

	holder.SetOptions = function(_, options)
		holder.currentOptions = options or {}
		updateText()
	end

	holder.RefreshText = updateText

	UIDropDownMenu_SetWidth(dropdown, holder.width)
	UIDropDownMenu_JustifyText(dropdown, "LEFT")
	UIDropDownMenu_Initialize(dropdown, function(_, level)
		if level ~= 1 then
			return
		end

		local current = getValue()
		for _, option in ipairs(getOptions()) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = option.label
			info.checked = current == option.value
			info.func = function()
				if type(holder.setValue) == "function" then
					holder.setValue(option.value)
				end
				updateText()
				if type(holder.onChanged) == "function" then
					holder.onChanged(option.value)
				end
			end
			UIDropDownMenu_AddButton(info, level)
		end
	end, "MENU")

	updateText()
	return holder
end

function ProfessionExporter:CreateMenuDropdown(parent, config)
	config = config or {}

	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize((config.width or 210) + 32, 52)

	local title = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	title:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
	title:SetText(config.label or "Menu")
	holder.title = title

	local dropdown = CreateFrame("Frame", nil, holder, "UIDropDownMenuTemplate")
	dropdown:SetPoint("TOPLEFT", holder, "TOPLEFT", -16, -12)
	holder.dropdown = dropdown
	holder.width = config.width or 210
	holder.getText = config.getText
	holder.initializeMenu = config.initializeMenu

	holder.RefreshText = function()
		local label = type(holder.getText) == "function" and holder.getText() or (config.placeholder or "Menu")
		UIDropDownMenu_SetWidth(dropdown, holder.width)
		UIDropDownMenu_SetText(dropdown, label)
	end

	UIDropDownMenu_SetWidth(dropdown, holder.width)
	UIDropDownMenu_JustifyText(dropdown, "LEFT")
	UIDropDownMenu_Initialize(dropdown, function(_, level)
		if type(holder.initializeMenu) == "function" then
			holder.initializeMenu(level, holder)
		end
	end, "MENU")

	holder:RefreshText()
	return holder
end

function ProfessionExporter:CreateCard(parent, width, height, tone)
	local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	card:SetSize(width or 100, height or 100)
	self:StylePanel(card, tone or "surface2")
	return card
end

function ProfessionExporter:CreateSectionTitle(parent, text)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetText(text or "")
	label:SetJustifyH("LEFT")
	return label
end

function ProfessionExporter:CreateMutedText(parent, width)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetWidth(width or 200)
	label:SetJustifyH("LEFT")
	label:SetWordWrap(true)
	return label
end

function ProfessionExporter:CreateStatusBadge(parent, text, colorKey)
	local badge = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	badge:SetSize(120, 20)
	local theme = self:GetTheme()
	local border = theme[colorKey or "accent"] or theme.accent
	self:ApplyBackdrop(badge, theme.surface3, border, { left = 2, right = 2, top = 2, bottom = 2 })
	badge.text = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	badge.text:SetPoint("CENTER")
	badge.text:SetText(text or "")
	return badge
end

--- Reusable line chart: sorted points `{ at = unixHourOrTime, value = number, label?, meta? }`.
--- Optional `secondarySeries` (copper, left axis); optional `quantitySeries` (counts, right axis).
--- Tooltip callback: `builder(tip, hit)` where `hit = { kind = "primary"|"secondary"|"quantity", pt = point }`.
function ProfessionExporter:CreateTimeSeriesGraph(parent, opts)
	opts = opts or {}
	local plotH = tonumber(opts.plotHeight) or 118
	local padL = tonumber(opts.padLeft) or 46
	local padRBase = tonumber(opts.padRight) or 10
	local padQtyAxis = 34
	local padT = tonumber(opts.padTop) or 6
	local padB = tonumber(opts.padBottom) or 22

	local holder = CreateFrame("Frame", nil, parent)
	holder:SetHeight(plotH + padT + padB + (opts.showTitle ~= false and 16 or 0))

	local title = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	if opts.showTitle ~= false then
		title:SetPoint("TOPLEFT", holder, "TOPLEFT", 2, -2)
		title:SetJustifyH("LEFT")
	end

	local plot = CreateFrame("Frame", nil, holder)
	if opts.showTitle ~= false then
		plot:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -2, -4)
	else
		plot:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
	end
	plot:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
	plot:SetHeight(plotH)
	plot:EnableMouse(true)

	local emptyText = plot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	emptyText:SetPoint("CENTER", plot, "CENTER", 0, 0)
	emptyText:SetWidth(plot:GetWidth() > 0 and plot:GetWidth() - 20 or 200)
	emptyText:SetJustifyH("CENTER")
	emptyText:SetWordWrap(true)

	local innerPlotH = plotH - padT - padB
	local yLabels = {}
	for i = 1, 3 do
		local fs = plot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		fs:SetPoint("TOPRIGHT", plot, "TOPLEFT", padL - 4, -padT - (i - 1) * (innerPlotH / 2))
		fs:SetJustifyH("RIGHT")
		fs:SetWidth(padL - 2)
		yLabels[i] = fs
	end

	local yLabelsRight = {}
	for i = 1, 3 do
		local fs = plot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		fs:SetPoint("TOPRIGHT", plot, "TOPRIGHT", -4, -padT - (i - 1) * (innerPlotH / 2))
		fs:SetJustifyH("RIGHT")
		fs:SetWidth(padQtyAxis + padRBase - 4)
		yLabelsRight[i] = fs
		fs:Hide()
	end

	local xLabels = {}
	do
		local xl = plot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		xl:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", padL + 2, 2)
		xl:SetJustifyH("LEFT")
		xLabels[1] = xl
		local xr = plot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		xr:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", -padRBase - 2, 2)
		xr:SetJustifyH("RIGHT")
		xLabels[2] = xr
	end

	local gridLines = {}
	local segmentLines = {}
	local markers = {}
	local secondarySegmentLines = {}
	local secondaryMarkers = {}
	local quantitySegmentLines = {}
	local quantityMarkers = {}

	local series = {}
	local secondarySeries = {}
	local quantitySeries = {}
	local yFormatter = opts.yFormatter or function(v)
		return tostring(math.floor(tonumber(v) or 0))
	end
	local rightYFormatter = function(v)
		return ProfessionExporter:FormatNumberGrouped(math.floor(tonumber(v) or 0))
	end
	local tooltipBuilder = opts.tooltipBuilder
	local emptyStateText = opts.emptyText or "No data in this range."
	local accent = opts.accentColor or { r = 0.35, g = 0.75, b = 0.85, a = 0.95 }
	local secondaryAccent = { r = 0.92, g = 0.58, b = 0.18, a = 0.95 }
	local quantityAccent = { r = 0.42, g = 0.78, b = 0.5, a = 0.9 }
	local canUseCreateLine = type(plot.CreateLine) == "function"

	local function hidePool(pool)
		for _, region in ipairs(pool) do
			region:Hide()
		end
	end

	local function getGridLine(i)
		local ln = gridLines[i]
		if not ln and canUseCreateLine then
			ln = plot:CreateLine()
			ln:SetThickness(1)
			gridLines[i] = ln
		end
		return ln
	end

	local function getSegmentLine(pool, i, thickness)
		local ln = pool[i]
		if not ln and canUseCreateLine then
			ln = plot:CreateLine()
			ln:SetThickness(thickness or 2)
			pool[i] = ln
		end
		return ln
	end

	local function getMarker(pool, i, size)
		local t = pool[i]
		if not t then
			t = plot:CreateTexture(nil, "ARTWORK")
			t:SetSize(size or 6, size or 6)
			pool[i] = t
		end
		return t
	end

	local function tsFmt(at)
		if not at or at <= 0 then
			return "—"
		end
		return date("%m-%d %H:%M", at)
	end

	local function expandTimeRange(pts, minT, maxT)
		for _, p in ipairs(pts or {}) do
			local t = p.at
			if t then
				if not minT or t < minT then
					minT = t
				end
				if not maxT or t > maxT then
					maxT = t
				end
			end
		end
		return minT, maxT
	end

	local function layoutGeometry(hasQty)
		local w = plot:GetWidth()
		local h = plot:GetHeight()
		if w < 40 or h < 40 then
			return nil
		end
		local padR = hasQty and (padRBase + padQtyAxis) or padRBase
		local innerW = w - padL - padR
		local innerH = h - padT - padB
		if innerW < 20 or innerH < 20 then
			return nil
		end
		return w, h, innerW, innerH, padR
	end

	local function paint()
		hidePool(gridLines)
		hidePool(segmentLines)
		hidePool(markers)
		hidePool(secondarySegmentLines)
		hidePool(secondaryMarkers)
		hidePool(quantitySegmentLines)
		hidePool(quantityMarkers)
		emptyText:Hide()
		for _, fs in ipairs(yLabels) do
			fs:SetText("")
		end
		for _, fs in ipairs(yLabelsRight) do
			fs:SetText("")
			fs:Hide()
		end
		for _, fs in ipairs(xLabels) do
			fs:SetText("")
		end

		local hasQty = quantitySeries and #quantitySeries > 0
		local plotW, ph, innerW, innerH, padR = layoutGeometry(hasQty)
		if not plotW or not innerW or not innerH then
			emptyText:SetText(emptyStateText)
			emptyText:Show()
			return
		end

		if not series or #series == 0 then
			emptyText:SetText(emptyStateText)
			emptyText:Show()
			return
		end

		local minT, maxT = expandTimeRange(series, nil, nil)
		minT, maxT = expandTimeRange(secondarySeries, minT, maxT)
		minT, maxT = expandTimeRange(quantitySeries, minT, maxT)
		if not minT or not maxT then
			emptyText:SetText(emptyStateText)
			emptyText:Show()
			return
		end
		if minT == maxT then
			minT = minT - 3600
			maxT = maxT + 3600
		end

		local minV, maxV = series[1].value, series[1].value
		for i = 2, #series do
			local p = series[i]
			minV = math.min(minV, p.value)
			maxV = math.max(maxV, p.value)
		end
		for _, p in ipairs(secondarySeries or {}) do
			minV = math.min(minV, p.value)
			maxV = math.max(maxV, p.value)
		end
		if minV == maxV then
			minV = minV - 1
			maxV = maxV + 1
		end
		if maxV <= minV then
			maxV = minV + 1
		end

		local minQ, maxQ = 0, 1
		if hasQty then
			minQ = quantitySeries[1].value
			maxQ = quantitySeries[1].value
			for i = 2, #quantitySeries do
				local p = quantitySeries[i]
				minQ = math.min(minQ, p.value)
				maxQ = math.max(maxQ, p.value)
			end
			if minQ == maxQ then
				minQ = math.max(0, minQ - 1)
				maxQ = maxQ + 1
			end
			if maxQ <= minQ then
				maxQ = minQ + 1
			end
			for _, fs in ipairs(yLabelsRight) do
				fs:Show()
			end
			yLabelsRight[1]:SetText(rightYFormatter(maxQ))
			yLabelsRight[2]:SetText(rightYFormatter((maxQ + minQ) / 2))
			yLabelsRight[3]:SetText(rightYFormatter(minQ))
		end

		xLabels[2]:ClearAllPoints()
		xLabels[2]:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", -padR - 2, 2)

		local theme = ProfessionExporter:GetTheme()
		local gridColor = theme.borderSubtle or { r = 0.3, g = 0.32, b = 0.36, a = 0.45 }
		local gx, gy, ga = gridColor.r or 0.3, gridColor.g or 0.32, gridColor.b or 0.36
		local gaa = gridColor.a or 0.5

		for g = 1, 3 do
			local ln = getGridLine(g)
			if ln then
				local y = padB + (g - 1) * (innerH / 2)
				ln:SetColorTexture(gx, gy, ga, gaa)
				ln:SetStartPoint("BOTTOMLEFT", padL, y)
				ln:SetEndPoint("BOTTOMLEFT", padL + innerW, y)
				ln:Show()
			end
		end

		yLabels[1]:SetText(yFormatter(maxV))
		yLabels[2]:SetText(yFormatter((maxV + minV) / 2))
		yLabels[3]:SetText(yFormatter(minV))

		xLabels[1]:SetText(tsFmt(series[1].at))
		xLabels[2]:SetText(tsFmt(series[#series].at))

		local function xAt(at)
			return padL + ((at - minT) / (maxT - minT)) * innerW
		end
		local function yAt(val)
			return padB + ((val - minV) / (maxV - minV)) * innerH
		end
		local function yAtQ(val)
			if not hasQty then
				return padB
			end
			return padB + ((val - minQ) / (maxQ - minQ)) * innerH
		end

		local hitTargets = {}
		local function pushHits(pts, kind, yFn)
			for _, p in ipairs(pts or {}) do
				hitTargets[#hitTargets + 1] = {
					kind = kind,
					pt = p,
					x = xAt(p.at),
					y = yFn(p.value),
				}
			end
		end
		pushHits(series, "primary", yAt)
		pushHits(secondarySeries, "secondary", yAt)
		pushHits(quantitySeries, "quantity", yAtQ)

		plot._peGeom = {
			padL = padL,
			padR = padR,
			padT = padT,
			padB = padB,
			innerW = innerW,
			innerH = innerH,
			minT = minT,
			maxT = maxT,
			minV = minV,
			maxV = maxV,
			minQ = minQ,
			maxQ = maxQ,
			hasQty = hasQty,
			hitTargets = hitTargets,
			series = series,
		}

		local ar, ag, ab = accent.r or 0.35, accent.g or 0.75, accent.b or 0.85
		local aa = accent.a or 0.95

		for i = 1, #series - 1 do
			local a, b = series[i], series[i + 1]
			local x1, y1 = xAt(a.at), yAt(a.value)
			local x2, y2 = xAt(b.at), yAt(b.value)
			local ln = getSegmentLine(segmentLines, i, 2)
			if ln then
				ln:SetColorTexture(ar, ag, ab, aa)
				ln:SetStartPoint("BOTTOMLEFT", x1, y1)
				ln:SetEndPoint("BOTTOMLEFT", x2, y2)
				ln:Show()
			end
		end

		for i = 1, #series do
			local p = series[i]
			local mx, my = xAt(p.at), yAt(p.value)
			local t = getMarker(markers, i, 6)
			t:SetColorTexture(ar, ag, ab, aa)
			t:ClearAllPoints()
			t:SetPoint("CENTER", plot, "BOTTOMLEFT", mx, my)
			t:Show()
		end

		local sr, sg, sb = secondaryAccent.r or 0.92, secondaryAccent.g or 0.58, secondaryAccent.b or 0.18
		local sa = secondaryAccent.a or 0.95
		for i = 1, #(secondarySeries or {}) - 1 do
			local a, b = secondarySeries[i], secondarySeries[i + 1]
			local x1, y1 = xAt(a.at), yAt(a.value)
			local x2, y2 = xAt(b.at), yAt(b.value)
			local ln = getSegmentLine(secondarySegmentLines, i, 2)
			if ln then
				ln:SetColorTexture(sr, sg, sb, sa)
				ln:SetStartPoint("BOTTOMLEFT", x1, y1)
				ln:SetEndPoint("BOTTOMLEFT", x2, y2)
				ln:Show()
			end
		end
		for i = 1, #(secondarySeries or {}) do
			local p = secondarySeries[i]
			local mx, my = xAt(p.at), yAt(p.value)
			local t = getMarker(secondaryMarkers, i, 5)
			t:SetColorTexture(sr, sg, sb, sa)
			t:ClearAllPoints()
			t:SetPoint("CENTER", plot, "BOTTOMLEFT", mx, my)
			t:Show()
		end

		local qr, qg, qb = quantityAccent.r or 0.42, quantityAccent.g or 0.78, quantityAccent.b or 0.5
		local qa = quantityAccent.a or 0.9
		for i = 1, #(quantitySeries or {}) - 1 do
			local a, b = quantitySeries[i], quantitySeries[i + 1]
			local x1, y1 = xAt(a.at), yAtQ(a.value)
			local x2, y2 = xAt(b.at), yAtQ(b.value)
			local ln = getSegmentLine(quantitySegmentLines, i, 1)
			if ln then
				ln:SetColorTexture(qr, qg, qb, qa)
				ln:SetStartPoint("BOTTOMLEFT", x1, y1)
				ln:SetEndPoint("BOTTOMLEFT", x2, y2)
				ln:Show()
			end
		end
		for i = 1, #(quantitySeries or {}) do
			local p = quantitySeries[i]
			local mx, my = xAt(p.at), yAtQ(p.value)
			local t = getMarker(quantityMarkers, i, 4)
			t:SetColorTexture(qr, qg, qb, qa)
			t:ClearAllPoints()
			t:SetPoint("CENTER", plot, "BOTTOMLEFT", mx, my)
			t:Show()
		end
	end

	local hoverKey = nil
	plot:SetScript("OnUpdate", function()
		if not plot._peGeom or not plot:IsMouseOver() then
			if hoverKey then
				GameTooltip:Hide()
				hoverKey = nil
			end
			return
		end
		local g = plot._peGeom
		local mx, my = GetCursorPosition()
		local scale = plot:GetEffectiveScale()
		local lx, ly = plot:GetLeft(), plot:GetBottom()
		if not lx or not ly then
			return
		end
		local px = (mx / scale) - lx
		local py = (my / scale) - ly
		local bestIdx, bestDist = nil, 1e9
		local targets = g.hitTargets or {}
		for i = 1, #targets do
			local h = targets[i]
			local dx = px - h.x
			local dy = py - h.y
			local d = dx * dx + dy * dy
			if d < bestDist then
				bestDist = d
				bestIdx = i
			end
		end
		if not bestIdx or bestDist > 30 * 30 then
			if hoverKey then
				GameTooltip:Hide()
				hoverKey = nil
			end
			return
		end
		local hit = targets[bestIdx]
		local key = tostring(bestIdx) .. ":" .. tostring(hit.kind) .. ":" .. tostring(hit.pt.at)
		if hoverKey == key and GameTooltip:IsShown() then
			return
		end
		hoverKey = key
		GameTooltip:SetOwner(plot, "ANCHOR_CURSOR")
		if GameTooltip.ClearLines then
			GameTooltip:ClearLines()
		elseif GameTooltip_Clear then
			GameTooltip_Clear(GameTooltip)
		end
		if type(tooltipBuilder) == "function" then
			tooltipBuilder(GameTooltip, hit)
		else
			GameTooltip:AddLine(tsFmt(hit.pt.at), 1, 1, 1)
			GameTooltip:AddLine(yFormatter(hit.pt.value), 0.8, 0.9, 1)
		end
		GameTooltip:Show()
	end)

	plot:SetScript("OnLeave", function()
		GameTooltip:Hide()
		hoverKey = nil
	end)

	holder.plot = plot
	holder.title = title
	holder.SetTitle = function(_, text)
		title:SetText(text or "")
	end
	holder.SetEmptyText = function(_, text)
		emptyStateText = text or emptyStateText
	end
	holder.SetSeries = function(_, data)
		series = type(data) == "table" and data or {}
	end
	holder.SetSecondarySeries = function(_, data)
		secondarySeries = type(data) == "table" and data or {}
	end
	holder.SetQuantitySeries = function(_, data)
		quantitySeries = type(data) == "table" and data or {}
	end
	holder.SetYFormatter = function(_, fn)
		if type(fn) == "function" then
			yFormatter = fn
		end
	end
	holder.SetRightYFormatter = function(_, fn)
		if type(fn) == "function" then
			rightYFormatter = fn
		end
	end
	holder.SetTooltipBuilder = function(_, fn)
		tooltipBuilder = fn
	end
	holder.SetAccentColor = function(_, c)
		if type(c) == "table" then
			accent = c
		end
	end
	holder.SetSecondaryAccentColor = function(_, c)
		if type(c) == "table" then
			secondaryAccent = c
		end
	end
	holder.SetQuantityAccentColor = function(_, c)
		if type(c) == "table" then
			quantityAccent = c
		end
	end
	holder.Refresh = function()
		paint()
	end

	holder:SetScript("OnSizeChanged", function()
		paint()
	end)

	title:SetText(opts.title or "")
	holder:SetSeries(opts.series)
	holder:SetSecondarySeries({})
	holder:SetQuantitySeries({})
	holder:Refresh()
	return holder
end

local DETAIL_PANE_LAYOUT = {
	splitterWidth = 6,
	gapAfterSplitter = 6,
	minDetailWidth = 260,
	minTableWidth = 420,
}

function ProfessionExporter:GetDetailPaneLayoutConstants()
	return DETAIL_PANE_LAYOUT
end

function ProfessionExporter:ClampDetailsWidthForPanel(panel, detailsWidth)
	local c = DETAIL_PANE_LAYOUT
	if not panel or not panel.GetWidth then
		return math.max(c.minDetailWidth, tonumber(detailsWidth) or c.minDetailWidth)
	end
	local innerW = math.max(840, panel:GetWidth() - 20)
	local maxDetail = innerW - c.minTableWidth - c.splitterWidth - c.gapAfterSplitter
	if maxDetail < c.minDetailWidth then
		maxDetail = c.minDetailWidth
	end
	detailsWidth = tonumber(detailsWidth) or c.minDetailWidth
	return math.max(c.minDetailWidth, math.min(maxDetail, detailsWidth))
end

function ProfessionExporter:CreateDetailPaneSplitter(panel, config)
	config = config or {}
	local settingsKey = config.settingsKey
	local onLayout = config.onLayout
	local f = CreateFrame("Frame", nil, panel)
	f:SetWidth(DETAIL_PANE_LAYOUT.splitterWidth)
	f:EnableMouse(true)

	local tex = f:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	tex:SetColorTexture(0.35, 0.38, 0.45, 0.28)

	f:SetScript("OnEnter", function(self)
		tex:SetColorTexture(0.52, 0.58, 0.68, 0.65)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Resize details", 1, 1, 1)
		GameTooltip:AddLine("Drag horizontally.", 0.8, 0.85, 0.9, true)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function()
		tex:SetColorTexture(0.35, 0.38, 0.45, 0.28)
		GameTooltip:Hide()
	end)

	f:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" or not settingsKey then
			return
		end
		self.dragging = true
		self.dragStartX = select(1, GetCursorPosition()) / UIParent:GetEffectiveScale()
		self.dragStartW = tonumber(ProfessionExporter:GetSetting(settingsKey, DETAIL_PANE_LAYOUT.minDetailWidth)) or 340
		self:SetScript("OnUpdate", function(sf)
			if not sf.dragging then
				sf:SetScript("OnUpdate", nil)
				return
			end
			if not IsMouseButtonDown("LeftButton") then
				sf.dragging = false
				sf:SetScript("OnUpdate", nil)
				return
			end
			local x = select(1, GetCursorPosition()) / UIParent:GetEffectiveScale()
			-- Splitter sits on the table/detail boundary: drag left widens the detail pane, drag right narrows it.
			local newW = sf.dragStartW - (x - sf.dragStartX)
			newW = ProfessionExporter:ClampDetailsWidthForPanel(panel, newW)
			local cur = tonumber(ProfessionExporter:GetSetting(settingsKey)) or newW
			if math.abs(cur - newW) >= 0.5 then
				ProfessionExporter:SetSetting(settingsKey, math.floor(newW + 0.5))
				if type(onLayout) == "function" then
					onLayout()
				end
			end
		end)
	end)

	f:SetScript("OnMouseUp", function(self)
		self.dragging = false
	end)

	return f
end

--- Sizes detail title/meta/body/graph to match `detailsWidth` (scroll inner + word wrap).
function ProfessionExporter:ApplyDetailPaneContentWidths(panel, detailsWidth, options)
	options = options or {}
	if not panel or not detailsWidth or detailsWidth <= 0 then
		return
	end
	local padL = options.padLeft or 6
	local scrollR = options.scrollRightPad or 28
	local titleRight = options.titleRightReserve or 36
	local iconCol = options.iconColumnWide or 76
	local contentW = math.max(100, detailsWidth - padL - scrollR)
	local bodyTrim = options.bodyInnerPad or 4

	if panel.detailContent then
		panel.detailContent:SetWidth(contentW)
	end
	if panel.detailBody then
		panel.detailBody:SetWidth(math.max(72, contentW - bodyTrim))
	end
	if panel.detailMeta then
		panel.detailMeta:SetWidth(contentW)
	end
	if panel.detailHeader and panel.detailTitle then
		local closeR = options.closeButtonReserve or 34
		local iconGap = 38
		local rankR = options.rankBadgeReserve or 22
		local headerInner = detailsWidth - padL - closeR
		panel.detailTitle:SetWidth(math.max(40, headerInner - iconGap - rankR))
	elseif panel.detailTitle then
		panel.detailTitle:SetWidth(math.max(48, detailsWidth - iconCol - titleRight))
	end
	if panel.detailGraphBlock then
		panel.detailGraphBlock:SetWidth(math.max(160, detailsWidth - padL * 2))
	end
	if panel.craftsDetailGraphBlock then
		panel.craftsDetailGraphBlock:SetWidth(math.max(160, detailsWidth - padL * 2))
	end
end

--- One row for icon + name; height follows wrapped title. Call after title text is set (or from layout with stale text).
function ProfessionExporter:LayoutDetailPaneHeaderRow(panel)
	if not panel or not panel.detailHeader or not panel.detailTitle then
		return
	end
	local th = panel.detailTitle:GetStringHeight()
	if not th or th < 4 then
		th = 18
	end
	panel.detailHeader:SetHeight(math.max(32, math.floor(th + 10)))
end
