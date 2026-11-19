local addonName, ProfessionExporter = ...

local TableMixin = {}

local function shallowCopy(list)
	local out = {}
	if type(list) ~= "table" then
		return out
	end
	for index, value in ipairs(list) do
		out[index] = value
	end
	return out
end

local function normalizeText(value)
	return string.lower(tostring(value or ""))
end

local function compareValues(left, right)
	local leftType = type(left)
	local rightType = type(right)
	if leftType == "number" or rightType == "number" then
		left = tonumber(left) or 0
		right = tonumber(right) or 0
		if left < right then
			return -1
		end
		if left > right then
			return 1
		end
		return 0
	end

	left = normalizeText(left)
	right = normalizeText(right)
	if left < right then
		return -1
	end
	if left > right then
		return 1
	end
	return 0
end

local function isColumnVisible(column, context)
	if type(column.visible) == "function" then
		return column.visible(context) ~= false
	end
	if column.visible == nil then
		return true
	end
	return column.visible ~= false
end

local function getCellRegion(cell)
	if type(cell) == "table" and cell.root then
		return cell.root
	end
	return cell
end

function TableMixin:GetColumn(columnId)
	return self.columnsById and self.columnsById[columnId] or nil
end

function TableMixin:GetVisibleColumns()
	local visible = {}
	for _, column in ipairs(self.columns or {}) do
		if isColumnVisible(column, self.context or {}) then
			table.insert(visible, column)
		end
	end
	return visible
end

function TableMixin:SetColumns(columns)
	self.columns = columns or {}
	self.columnsById = {}
	for _, column in ipairs(self.columns) do
		self.columnsById[column.id] = column
	end

	if not self.sortKey then
		for _, column in ipairs(self.columns) do
			if column.sortable and column.defaultSort then
				self.sortKey = column.id
				self.sortAsc = column.defaultSort == "asc"
				break
			end
		end
	end

	self:Refresh()
end

function TableMixin:ReorderColumns(sourceId, targetId)
	if not sourceId or not targetId or sourceId == targetId then
		return
	end
	local sourceIndex, targetIndex
	for index, column in ipairs(self.columns or {}) do
		if column.id == sourceId then
			sourceIndex = index
		elseif column.id == targetId then
			targetIndex = index
		end
	end
	if not sourceIndex or not targetIndex then
		return
	end

	local moved = table.remove(self.columns, sourceIndex)
	if not moved then
		return
	end
	if sourceIndex < targetIndex then
		targetIndex = targetIndex - 1
	end
	table.insert(self.columns, targetIndex, moved)
	self:SetColumns(self.columns)
	if type(self.onColumnReordered) == "function" then
		self.onColumnReordered(sourceId, targetId, self.columns)
	end
end

function TableMixin:SetRows(rows)
	self.rows = rows or {}
	self:RefreshRows()
end

function TableMixin:SetContext(context)
	self.context = context or {}
	self:Refresh()
end

function TableMixin:SetSort(columnId, asc)
	local column = self:GetColumn(columnId)
	if not column or not column.sortable then
		return
	end
	self.sortKey = columnId
	if asc == nil then
		self.sortAsc = column.defaultSort ~= "desc"
	else
		self.sortAsc = asc == true
	end
	self:Refresh({ resetVerticalScroll = true })
	if type(self.onSortChanged) == "function" then
		self.onSortChanged(self.sortKey, self.sortAsc)
	end
end

function TableMixin:ToggleSort(columnId)
	local column = self:GetColumn(columnId)
	if not column or not column.sortable then
		return
	end
	if self.sortKey == columnId then
		self.sortAsc = not self.sortAsc
	else
		self.sortKey = columnId
		self.sortAsc = column.defaultSort ~= "desc"
	end
	self:Refresh({ resetVerticalScroll = true })
	if type(self.onSortChanged) == "function" then
		self.onSortChanged(self.sortKey, self.sortAsc)
	end
end

function TableMixin:GetSortValue(column, rowData)
	if type(column.sortValue) == "function" then
		return column.sortValue(rowData, self.context or {}, self)
	end
	if column.sortField then
		return rowData and rowData[column.sortField]
	end
	return rowData and rowData[column.id]
end

function TableMixin:CompareRows(left, right)
	local column = self:GetColumn(self.sortKey)
	local cmp = 0
	if column then
		if type(column.compare) == "function" then
			cmp = column.compare(left, right, self.context or {}, self) or 0
		else
			cmp = compareValues(self:GetSortValue(column, left), self:GetSortValue(column, right))
		end
	end

	if cmp == 0 then
		cmp = compareValues(left and left._rowIdentity, right and right._rowIdentity)
	end

	if self.sortAsc then
		return cmp < 0
	end
	return cmp > 0
end

function TableMixin:GetSortedRows()
	local rows = shallowCopy(self.rows)
	for _, row in ipairs(rows) do
		if row._rowIdentity == nil then
			if row.aggregatedInventory then
				row._rowIdentity = tostring(row.itemID or "")
			else
				row._rowIdentity = string.format("%s:%s", tostring(row.characterKey or ""), tostring(row.itemID or ""))
			end
		end
	end
	if self.sortKey then
		table.sort(rows, function(left, right)
			return self:CompareRows(left, right)
		end)
	end
	return rows
end

function TableMixin:ShowHeaderTooltip(button)
	local column = button and button.column or nil
	if not column then
		return
	end

	local lines = column.tooltipLines
	if type(column.getTooltipLines) == "function" then
		lines = column.getTooltipLines(self.context or {}, self)
	end
	local text = column.tooltipText
	local hasLines = type(lines) == "table" and #lines > 0
	if not column.tooltipTitle and not text and not hasLines then
		return
	end

	GameTooltip:SetOwner(button, "ANCHOR_BOTTOMRIGHT")
	GameTooltip:SetText(column.tooltipTitle or column.label or column.id or "Column", 1, 0.82, 0.2)
	if text and text ~= "" then
		GameTooltip:AddLine(text, 0.82, 0.88, 0.96, true)
	end
	if hasLines then
		for _, line in ipairs(lines) do
			if type(line) == "table" then
				GameTooltip:AddLine(line.text or "", line.r or 0.82, line.g or 0.88, line.b or 0.96, line.wrap == true)
			else
				GameTooltip:AddLine(tostring(line), 0.82, 0.88, 0.96, true)
			end
		end
	end
	GameTooltip:Show()
end

function TableMixin:AcquireHeaderButton(index)
	local button = self.headerButtons[index]
	if button then
		return button
	end

	button = CreateFrame("Button", nil, self.header)
	button:SetHeight(self.headerHeight)
	button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	button.text:SetJustifyH("LEFT")
	button.text:SetPoint("LEFT", button, "LEFT", 0, 0)
	button.text:SetPoint("RIGHT", button, "RIGHT", 0, 0)
	button:RegisterForDrag("LeftButton")
	button:SetScript("OnClick", function(btn)
		if btn.columnId then
			self:ToggleSort(btn.columnId)
		end
	end)
	button:SetScript("OnEnter", function(btn)
		self:ShowHeaderTooltip(btn)
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	button:SetScript("OnDragStart", function(btn)
		if not btn.columnId then
			return
		end
		self.dragColumnId = btn.columnId
		btn:SetAlpha(0.45)
	end)
	button:SetScript("OnDragStop", function(btn)
		local sourceId = self.dragColumnId
		self.dragColumnId = nil
		btn:SetAlpha(1)
		if not sourceId then
			return
		end
		for _, target in ipairs(self.headerButtons or {}) do
			if target ~= btn and target:IsShown() and target.columnId and target:IsMouseOver() then
				self:ReorderColumns(sourceId, target.columnId)
				break
			end
		end
	end)

	self.headerButtons[index] = button
	return button
end

function TableMixin:CreateDefaultCell(rowFrame, column)
	local fontString = rowFrame:CreateFontString(nil, "OVERLAY", column.fontObject or "GameFontHighlightSmall")
	fontString:SetJustifyH(column.justifyH or "LEFT")
	fontString:SetWordWrap(false)
	return fontString
end

function TableMixin:AcquireRow(index)
	local row = self.rowPool[index]
	if row then
		return row
	end

	row = CreateFrame("Button", nil, self.scrollChild)
	row:SetHeight(self.rowHeight)
	row:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight", "ADD")
	row.cells = {}

	row:SetScript("OnEnter", function(frame)
		if type(self.onRowEnter) == "function" then
			self.onRowEnter(frame, frame.rowData, self)
		end
	end)
	row:SetScript("OnLeave", function(frame)
		if type(self.onRowLeave) == "function" then
			self.onRowLeave(frame, frame.rowData, self)
		end
	end)
	row:SetScript("OnClick", function(frame, buttonName)
		if type(self.onRowClick) == "function" then
			self.onRowClick(frame, frame.rowData, buttonName, self)
		end
	end)

	self.rowPool[index] = row
	return row
end

function TableMixin:AcquireCell(row, column)
	local cell = row.cells[column.id]
	if cell then
		return cell
	end

	if type(column.createCell) == "function" then
		cell = column.createCell(row, column, self)
	else
		cell = self:CreateDefaultCell(row, column)
	end
	row.cells[column.id] = cell
	return cell
end

function TableMixin:GetLayoutColumnWidth(column)
	if not column then
		return 80
	end
	local w = self._layoutColumnWidths and self._layoutColumnWidths[column.id]
	if w then
		return w
	end
	return tonumber(column.width) or 80
end

function TableMixin:RecomputeLayoutColumnWidths()
	local visible = self:GetVisibleColumns()
	self._layoutColumnWidths = {}
	local n = #visible
	if n == 0 then
		self.contentWidth = self.paddingX * 2
		return
	end

	if not self.autoFitToScroll or not self.scrollFrame then
		local sumCols = 0
		for _, col in ipairs(visible) do
			local w = tonumber(col.width) or 80
			self._layoutColumnWidths[col.id] = w
			sumCols = sumCols + w
		end
		self.contentWidth = self.paddingX * 2 + sumCols
		return
	end

	local viewport = (self.scrollFrame:GetWidth() or 400) - (self.scrollbarReserve or 28) - self.paddingX * 2
	viewport = math.max(80, math.floor(viewport))

	local prefs, mins, flexW = {}, {}, {}
	local totalPref, totalFlex = 0, 0
	for i, col in ipairs(visible) do
		prefs[i] = tonumber(col.width) or 80
		mins[i] = tonumber(col.minWidth)
		if not mins[i] then
			mins[i] = prefs[i]
		end
		if mins[i] > prefs[i] then
			mins[i] = prefs[i]
		end
		flexW[i] = tonumber(col.flex) or 0
		if flexW[i] < 0 then
			flexW[i] = 0
		end
		totalPref = totalPref + prefs[i]
		totalFlex = totalFlex + flexW[i]
	end

	if totalPref <= viewport then
		local extra = viewport - totalPref
		for i, col in ipairs(visible) do
			local w = prefs[i]
			if totalFlex > 0 and extra > 0 and flexW[i] > 0 then
				w = w + extra * (flexW[i] / totalFlex)
			end
			self._layoutColumnWidths[col.id] = math.max(mins[i], math.floor(w + 0.5))
		end
	else
		local scale = viewport / totalPref
		for i, col in ipairs(visible) do
			local w = math.max(mins[i], math.floor(prefs[i] * scale + 0.5))
			self._layoutColumnWidths[col.id] = w
		end
		local sumCols = 0
		for _, col in ipairs(visible) do
			sumCols = sumCols + self._layoutColumnWidths[col.id]
		end
		if sumCols ~= viewport and n > 0 then
			local last = visible[n]
			local li = n
			local id = last.id
			self._layoutColumnWidths[id] = math.max(mins[li], self._layoutColumnWidths[id] + (viewport - sumCols))
		end
	end

	local sumCols = 0
	for _, col in ipairs(visible) do
		sumCols = sumCols + self._layoutColumnWidths[col.id]
	end
	self.contentWidth = self.paddingX * 2 + sumCols
end

function TableMixin:UpdateHeader()
	self:RecomputeLayoutColumnWidths()
	local visibleColumns = self:GetVisibleColumns()
	local x = self.paddingX

	for index, column in ipairs(visibleColumns) do
		local button = self:AcquireHeaderButton(index)
		local hasTooltip = column.tooltipTitle or column.tooltipText or column.tooltipLines or column.getTooltipLines
		button.column = column
		button.columnId = column.sortable and column.id or nil
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", self.header, "TOPLEFT", x, 0)
		local lw = self:GetLayoutColumnWidth(column)
		button:SetWidth(lw)
		button:EnableMouse(column.sortable == true or hasTooltip ~= nil)

		local label = column.label or column.id
		if column.sortable and self.sortKey == column.id then
			label = label .. (self.sortAsc and " ^" or " v")
		end
		button.text:SetText(label)
		button:Show()

		x = x + lw
	end

	for index = #visibleColumns + 1, #self.headerButtons do
		self.headerButtons[index]:Hide()
	end

	self.header:SetHeight(self.headerHeight)
end

function TableMixin:UpdateRow(rowFrame, rowData, rowIndex)
	local visibleColumns = self:GetVisibleColumns()
	local x = self.paddingX
	rowFrame.rowData = rowData
	rowFrame:SetWidth(self.contentWidth)

	for _, column in ipairs(visibleColumns) do
		local cell = self:AcquireCell(rowFrame, column)
		local region = getCellRegion(cell)
		region:ClearAllPoints()
		region:SetPoint("LEFT", rowFrame, "LEFT", x, 0)
		if region.SetWidth then
			region:SetWidth(self:GetLayoutColumnWidth(column))
		end
		if region.SetHeight and region ~= rowFrame then
			region:SetHeight(self.rowHeight)
		end
		region:Show()

		if type(column.updateCell) == "function" then
			column.updateCell(cell, rowData, self.context or {}, self, rowFrame, rowIndex)
		else
			local text = ""
			if type(column.getText) == "function" then
				text = column.getText(rowData, self.context or {}, self) or ""
			elseif rowData then
				text = rowData[column.field or column.id] or ""
			end

			if type(cell) == "table" and cell.text and cell.text.SetText then
				cell.text:SetText(tostring(text))
			elseif cell and cell.SetText then
				cell:SetText(tostring(text))
			end
		end

		x = x + self:GetLayoutColumnWidth(column)
	end

	for columnId, cell in pairs(rowFrame.cells) do
		local column = self:GetColumn(columnId)
		local region = getCellRegion(cell)
		if not column or not isColumnVisible(column, self.context or {}) then
			region:Hide()
		end
	end

	rowFrame:ClearAllPoints()
	rowFrame:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, -((rowIndex - 1) * self.rowHeight))
	rowFrame:Show()
end

function TableMixin:RefreshVirtualRowWindow()
	if not self.useViewportVirtualization or not self.scrollFrame then
		return
	end
	local displayRows = self.displayRows or {}
	local count = #displayRows
	if count == 0 then
		for slot = 1, #self.rowPool do
			self.rowPool[slot]:Hide()
		end
		return
	end
	local scroll = self.scrollFrame:GetVerticalScroll() or 0
	local rawH = self.scrollFrame:GetHeight()
	local viewH = (rawH and rawH > 40) and rawH or 320
	local rowH = self.rowHeight
	local overscan = self.virtualOverscan or 6
	local firstVis = math.floor(scroll / rowH) + 1
	local lastVis = math.min(count, math.ceil((scroll + viewH) / rowH))
	local first = math.max(1, firstVis - overscan)
	local last = math.min(count, lastVis + overscan)
	if first > last then
		first = math.max(1, count - overscan * 2)
		last = count
	end
	local poolSlots = last - first + 1
	for slot = 1, poolSlots do
		local i = first + slot - 1
		local row = self:AcquireRow(slot)
		self:UpdateRow(row, displayRows[i], i)
		row:Show()
	end
	for slot = poolSlots + 1, #self.rowPool do
		self.rowPool[slot]:Hide()
	end
end

function TableMixin:GetVisibleRows()
	local rows = self.displayRows or {}
	if not self.scrollFrame then
		return shallowCopy(rows)
	end
	local count = #rows
	if count == 0 then
		return {}
	end
	local scroll = self.scrollFrame:GetVerticalScroll() or 0
	local rawH = self.scrollFrame:GetHeight()
	local viewH = (rawH and rawH > 40) and rawH or 320
	local rowH = self.rowHeight or 20
	local first = math.max(1, math.floor(scroll / rowH) + 1)
	local last = math.min(count, math.ceil((scroll + viewH) / rowH))
	local out = {}
	for index = first, last do
		out[#out + 1] = rows[index]
	end
	return out
end

function TableMixin:RefreshRows(opts)
	opts = opts or {}
	self.displayRows = self:GetSortedRows()

	local count = #self.displayRows
	if self.maxRows and count > self.maxRows then
		local trimmed = {}
		for index = 1, self.maxRows do
			trimmed[index] = self.displayRows[index]
		end
		self.displayRows = trimmed
		count = #trimmed
	end

	local resetScroll = opts.resetVerticalScroll == true
	local prevScroll = 0
	if self.scrollFrame and not resetScroll then
		prevScroll = self.scrollFrame:GetVerticalScroll() or 0
	end

	local function applyScrollAfterContentSize()
		if not self.scrollFrame or not self.scrollChild then
			return
		end
		if resetScroll then
			self.scrollFrame:SetVerticalScroll(0)
			return
		end
		local childH = self.scrollChild:GetHeight() or 0
		local viewH = self.scrollFrame:GetHeight() or 0
		local maxScroll = math.max(0, childH - viewH)
		self.scrollFrame:SetVerticalScroll(math.min(prevScroll, maxScroll))
	end

	if self.useViewportVirtualization then
		self.scrollChild:SetWidth(self.contentWidth)
		self.scrollChild:SetHeight(math.max(self.rowHeight, count * self.rowHeight + 4))
		applyScrollAfterContentSize()
		self:RefreshVirtualRowWindow()
		return
	end

	for index, rowData in ipairs(self.displayRows) do
		local row = self:AcquireRow(index)
		self:UpdateRow(row, rowData, index)
	end

	for index = count + 1, #self.rowPool do
		self.rowPool[index]:Hide()
	end

	self.scrollChild:SetWidth(self.contentWidth)
	self.scrollChild:SetHeight(math.max(self.rowHeight, count * self.rowHeight + 4))
	applyScrollAfterContentSize()
end

function TableMixin:Refresh(opts)
	self:UpdateHeader()
	self:RefreshRows(opts)
end

function ProfessionExporter:CreateReusableTable(parent, options)
	options = options or {}

	local widget = setmetatable({}, { __index = TableMixin })
	widget.columns = {}
	widget.columnsById = {}
	widget.rows = {}
	widget.context = {}
	widget.rowPool = {}
	widget.headerButtons = {}
	widget.paddingX = options.paddingX or 4
	widget.rowHeight = options.rowHeight or 20
	widget.headerHeight = options.headerHeight or widget.rowHeight
	widget.maxRows = options.maxRows
	widget.sortKey = options.sortKey
	widget.sortAsc = options.sortAsc ~= false
	widget.onSortChanged = options.onSortChanged
	widget.onColumnReordered = options.onColumnReordered
	widget.onRowEnter = options.onRowEnter
	widget.onRowLeave = options.onRowLeave
	widget.onRowClick = options.onRowClick
	widget.contentWidth = 0
	widget.autoFitToScroll = options.autoFitToScroll == true
	widget.scrollbarReserve = options.scrollbarReserve or 28
	widget._layoutColumnWidths = {}
	widget.useViewportVirtualization = options.viewportVirtualize == true

	local frame = CreateFrame("Frame", nil, parent)
	widget.frame = frame
	if frame.SetClipsChildren then
		frame:SetClipsChildren(true)
	end

	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -28, 0)
	header:SetHeight(widget.headerHeight)
	widget.header = header

	local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
	scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 0)
	widget.scrollFrame = scrollFrame

	local scrollChild = CreateFrame("Frame", nil, scrollFrame)
	scrollChild:SetWidth(1)
	scrollChild:SetHeight(widget.rowHeight)
	scrollFrame:SetScrollChild(scrollChild)
	widget.scrollChild = scrollChild

	if widget.useViewportVirtualization then
		scrollFrame:SetScript("OnVerticalScroll", function()
			widget:RefreshVirtualRowWindow()
		end)
		scrollFrame:HookScript("OnSizeChanged", function()
			if widget.autoFitToScroll then
				widget:Refresh()
			else
				widget:RefreshVirtualRowWindow()
			end
		end)
	elseif widget.autoFitToScroll then
		scrollFrame:HookScript("OnSizeChanged", function()
			widget:Refresh()
		end)
	end

	frame:HookScript("OnSizeChanged", function()
		widget:Refresh()
	end)

	return widget
end

