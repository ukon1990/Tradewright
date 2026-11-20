local _, ProfessionExporter = ...

local TableMixin = {}

local WHITE = "Interface\\Buttons\\WHITE8X8"
local CELL_PAD = 5

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
	-- The empty text and the footer (page position) follow every row change.
	self:UpdateEmptyState()
	self:UpdateFooter()
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
	self.page = 1
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
	self.page = 1
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

-- Sorts once per change of rows or sort column: each row's sort key is computed a single time
-- (not inside the comparator), and the result is reused until SetRows or a sort change.
function TableMixin:GetSortedRows()
	if self._sorted and self._sortedFrom == self.rows and self._sortedKey == self.sortKey and self._sortedAsc == self.sortAsc then
		return self._sorted
	end
	local rows = shallowCopy(self.rows)
	local column = self.sortKey and self:GetColumn(self.sortKey)
	if column then
		local keys, ids = {}, {}
		for _, row in ipairs(rows) do
			if row._rowIdentity == nil then
				if row.aggregatedInventory then
					row._rowIdentity = tostring(row.itemID or "")
				else
					row._rowIdentity = string.format("%s:%s", tostring(row.characterKey or ""), tostring(row.itemID or ""))
				end
			end
			ids[row] = tostring(row._rowIdentity)
			if not column.compare then
				local value = self:GetSortValue(column, row)
				keys[row] = type(value) == "number" and value or normalizeText(value)
			end
		end
		local asc = self.sortAsc
		local context = self.context or {}
		table.sort(rows, function(left, right)
			local cmp
			if column.compare then
				cmp = column.compare(left, right, context, self) or 0
			else
				local a, b = keys[left], keys[right]
				if type(a) ~= type(b) then
					a, b = tonumber(a) or 0, tonumber(b) or 0
				end
				cmp = a < b and -1 or (a > b and 1 or 0)
			end
			if cmp == 0 then
				local a, b = ids[left], ids[right]
				return a < b
			end
			if asc then
				return cmp < 0
			end
			return cmp > 0
		end)
	end
	self._sorted, self._sortedFrom, self._sortedKey, self._sortedAsc = rows, self.rows, self.sortKey, self.sortAsc
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

	local theme = ProfessionExporter:GetTheme()
	local gold, muted = theme.gold, theme.textMuted
	GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
	GameTooltip:SetText(column.tooltipTitle or column.label or column.id or "Column", gold.r, gold.g, gold.b)
	if text and text ~= "" then
		GameTooltip:AddLine(text, muted.r, muted.g, muted.b, true)
	end
	if hasLines then
		for _, line in ipairs(lines) do
			if type(line) == "table" then
				GameTooltip:AddLine(line.text or "", line.r or muted.r, line.g or muted.g, line.b or muted.b, line.wrap == true)
			else
				GameTooltip:AddLine(tostring(line), muted.r, muted.g, muted.b, true)
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
	button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.text:SetJustifyH("LEFT")
	button.text:SetWordWrap(false)
	button.text:SetPoint("LEFT", button, "LEFT", CELL_PAD, 0)
	button.text:SetPoint("RIGHT", button, "RIGHT", -CELL_PAD, 0)
	button.arrow = button:CreateTexture(nil, "OVERLAY")
	button.arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
	button.arrow:SetSize(9, 8)
	button.arrow:Hide()
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
	local fontString = rowFrame:CreateFontString(nil, "OVERLAY", column.fontObject or (column.justifyH == "RIGHT" and "NumberFontNormalSmall" or "GameFontHighlightSmall"))
	fontString:SetJustifyH(column.justifyH or "LEFT")
	fontString:SetWordWrap(false)
	local text = ProfessionExporter:GetTheme().textPrimary
	fontString:SetTextColor(text.r, text.g, text.b)
	return fontString
end

function TableMixin:AcquireRow(index)
	local row = self.rowPool[index]
	if row then
		return row
	end

	row = CreateFrame("Button", nil, self.scrollChild)
	row:SetHeight(self.rowHeight)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetHighlightTexture(WHITE)
	row:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.04)
	row.selectedFill = row:CreateTexture(nil, "BACKGROUND")
	row.selectedFill:SetAllPoints()
	local gold = ProfessionExporter:GetTheme().gold
	row.selectedFill:SetColorTexture(gold.r, gold.g, gold.b, 0.07)
	row.selectedFill:Hide()
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

-- Layout rule: fixed columns keep their width; flex columns share what is left (never below
-- minWidth). When even that does not fit, `optional` columns are dropped: those marked
-- `dropFirst` before any other, then from the right.
function TableMixin:RecomputeLayoutColumnWidths()
	local visible = self:GetVisibleColumns()
	self._layoutColumnWidths = {}
	self._droppedColumns = {}
	if #visible == 0 then
		self.contentWidth = self.paddingX * 2
		return
	end

	local function fixedWidth(col)
		return tonumber(col.width) or 80
	end
	local function flexWeight(col)
		return math.max(0, tonumber(col.flex) or 0)
	end

	if not self.autoFitToScroll or not self.scrollFrame then
		local sum = 0
		for _, col in ipairs(visible) do
			self._layoutColumnWidths[col.id] = fixedWidth(col)
			sum = sum + fixedWidth(col)
		end
		self.contentWidth = self.paddingX * 2 + sum
		return
	end

	local viewport = math.max(80, math.floor((self.scrollFrame:GetWidth() or 400) - self.paddingX * 2))
	local columns = {}
	for _, col in ipairs(visible) do
		columns[#columns + 1] = col
	end

	local function measure()
		local fixed, minFlex, totalFlex = 0, 0, 0
		for _, col in ipairs(columns) do
			if flexWeight(col) > 0 then
				minFlex = minFlex + (tonumber(col.minWidth) or 60)
				totalFlex = totalFlex + flexWeight(col)
			else
				fixed = fixed + fixedWidth(col)
			end
		end
		return fixed, minFlex, totalFlex
	end

	local fixed, minFlex, totalFlex = measure()
	while fixed + minFlex > viewport do
		local dropIndex
		for index = #columns, 1, -1 do
			local col = columns[index]
			if col.optional and (col.dropFirst or not dropIndex) then
				dropIndex = index
				if col.dropFirst then
					break
				end
			end
		end
		if not dropIndex then
			break
		end
		self._droppedColumns[columns[dropIndex].id] = true
		table.remove(columns, dropIndex)
		fixed, minFlex, totalFlex = measure()
	end

	local spare = viewport - fixed
	local sum = 0
	for _, col in ipairs(columns) do
		local width = fixedWidth(col)
		if flexWeight(col) > 0 then
			width = math.max(tonumber(col.minWidth) or 60, math.floor(spare * flexWeight(col) / totalFlex))
		end
		self._layoutColumnWidths[col.id] = width
		sum = sum + width
	end
	self.contentWidth = self.paddingX * 2 + sum
end

function TableMixin:GetLayoutColumns()
	local out = {}
	for _, col in ipairs(self:GetVisibleColumns()) do
		if not (self._droppedColumns and self._droppedColumns[col.id]) then
			out[#out + 1] = col
		end
	end
	return out
end

function TableMixin:UpdateHeader()
	self:RecomputeLayoutColumnWidths()
	local visibleColumns = self:GetLayoutColumns()
	local x = self.paddingX
	local theme = ProfessionExporter:GetTheme()

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

		local sorted = column.sortable and self.sortKey == column.id
		local color = sorted and theme.gold or theme.textMuted
		button.text:SetText(column.label or column.id)
		button.text:SetJustifyH(column.justifyH or "LEFT")
		button.text:SetTextColor(color.r, color.g, color.b)
		button.text:ClearAllPoints()
		button.arrow:ClearAllPoints()
		button.text:SetPoint("LEFT", button, "LEFT", CELL_PAD, 0)
		button.text:SetPoint("RIGHT", button, "RIGHT", sorted and -(CELL_PAD + 11) or -CELL_PAD, 0)
		button.arrow:SetPoint("RIGHT", button, "RIGHT", -CELL_PAD, 0)
		button.arrow:SetShown(sorted)
		if sorted then
			button.arrow:SetVertexColor(theme.gold.r, theme.gold.g, theme.gold.b)
			button.arrow:SetTexCoord(0, 0.5625, self.sortAsc and 1 or 0, self.sortAsc and 0 or 1)
		end
		button:Show()

		x = x + lw
	end

	for index = #visibleColumns + 1, #self.headerButtons do
		self.headerButtons[index]:Hide()
	end

	self.header:SetHeight(self.headerHeight)
end

function TableMixin:IsRowSelected(rowData)
	if type(self.isRowSelected) == "function" then
		return self.isRowSelected(rowData, self) == true
	end
	return rowData ~= nil and rowData == self.selectedRowData
end

function TableMixin:SetSelectedRow(rowData)
	self.selectedRowData = rowData
	for _, row in ipairs(self.rowPool) do
		if row:IsShown() then
			row.selectedFill:SetShown(self:IsRowSelected(row.rowData))
		end
	end
end

function TableMixin:UpdateRow(rowFrame, rowData, rowIndex)
	local visibleColumns = self:GetLayoutColumns()
	local x = self.paddingX
	rowFrame.rowData = rowData
	rowFrame:SetWidth(self.contentWidth)
	rowFrame.selectedFill:SetShown(self:IsRowSelected(rowData))

	for _, column in ipairs(visibleColumns) do
		local cell = self:AcquireCell(rowFrame, column)
		local region = getCellRegion(cell)
		local width = self:GetLayoutColumnWidth(column)
		local isFontString = region.GetObjectType and region:GetObjectType() == "FontString"
		local pad = isFontString and CELL_PAD or 0
		region:ClearAllPoints()
		region:SetPoint("LEFT", rowFrame, "LEFT", x + pad, 0)
		if region.SetWidth then
			region:SetWidth(width - pad * 2)
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
		if not column or not isColumnVisible(column, self.context or {}) or (self._droppedColumns and self._droppedColumns[columnId]) then
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
	self.totalRowCount = count
	-- maxRows is the page size. Paging needs the footer for its controls; without one only the
	-- first page is shown.
	self.page, self.pageCount, self.pageFirst, self.pageLast = ProfessionExporter.ForeverLogic.PageBounds(count, self.maxRows,
		self.pager and self.page or 1)
	if self.pageCount > 1 then
		local pageRows = {}
		for index = self.pageFirst, self.pageLast do
			pageRows[#pageRows + 1] = self.displayRows[index]
		end
		self.displayRows = pageRows
		count = #pageRows
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

function TableMixin:SetEmptyText(title, hint)
	self.emptyTitle = title
	self.emptyHint = hint
	self:UpdateEmptyState()
end

function TableMixin:UpdateEmptyState()
	local empty = #(self.displayRows or {}) == 0
	self.emptyFrame:SetShown(empty)
	self.emptyFrame.title:SetText(self.emptyTitle or "Nothing to show")
	self.emptyFrame.hint:SetText(self.emptyHint or "Change the search or filters.")
end

--- Shows another page of a table that has more rows than its page size.
function TableMixin:SetPage(page)
	self.page = page
	self:Refresh({ resetVerticalScroll = true })
end

-- Footer text: `left` is replaced by "Showing A-B of M" when the rows span more than one page.
function TableMixin:SetFooterText(left, right)
	if not self.footer then
		return
	end
	self.footerLeftOverride = left
	self.footer.right:SetText(right or "")
	self:UpdateFooter()
end

function TableMixin:UpdateFooter()
	if not self.footer then
		return
	end
	local pe = ProfessionExporter
	local left, right = self.footer.left, self.footer.right
	local paged = (self.pageCount or 1) > 1
	left:SetText(paged and string.format("Showing %s-%s of %s", pe:FormatNumberGrouped(self.pageFirst), pe:FormatNumberGrouped(self.pageLast),
		pe:FormatNumberGrouped(self.totalRowCount)) or self.footerLeftOverride or "")
	local pager = self.pager
	if not pager then
		return
	end
	pager:SetShown(paged)
	left:ClearAllPoints()
	right:ClearAllPoints()
	left:SetPoint("LEFT", 8, 0)
	if paged then
		-- Pager at the right edge. "Showing A-B of N" keeps its full width, and the caller's text
		-- gets what is left between the two, cut short when the table is narrow.
		pager.label:SetText(string.format("Page %d of %d", self.page, self.pageCount))
		pager.prev:SetEnabled(self.page > 1)
		pager.next:SetEnabled(self.page < self.pageCount)
		pager:SetWidth(pager.prev:GetWidth() + pager.next:GetWidth() + math.ceil(pager.label:GetStringWidth()) + 16)
		right:SetPoint("LEFT", left, "RIGHT", 12, 0)
		right:SetPoint("RIGHT", pager, "LEFT", -12, 0)
	else
		right:SetPoint("RIGHT", self.footer, "RIGHT", -pe:GetTheme().size.scrollGutter, 0)
		left:SetPoint("RIGHT", right, "LEFT", -12, 0)
	end
end

function TableMixin:Refresh(opts)
	self:UpdateHeader()
	self:RefreshRows(opts)
	self:UpdateEmptyState()
	self:UpdateFooter()
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
	local sizes = ProfessionExporter:GetTheme().size
	widget.paddingX = options.paddingX or 4
	widget.rowHeight = math.max(options.rowHeight or sizes.row, sizes.row)
	widget.headerHeight = options.headerHeight or sizes.tableHead
	widget.isRowSelected = options.isRowSelected
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
	widget._layoutColumnWidths = {}
	widget.useViewportVirtualization = options.viewportVirtualize == true

	local theme = ProfessionExporter:GetTheme()
	local gutter = theme.size.scrollGutter
	local frame = CreateFrame("Frame", nil, parent)
	widget.frame = frame
	if frame.SetClipsChildren then
		frame:SetClipsChildren(true)
	end
	ProfessionExporter:AddSurface(frame, { r = 0, g = 0, b = 0, a = 0 }, theme.borderSubtle)

	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
	header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
	header:SetHeight(widget.headerHeight)
	local headerFill = header:CreateTexture(nil, "BACKGROUND")
	headerFill:SetAllPoints()
	headerFill:SetColorTexture(theme.surface2.r, theme.surface2.g, theme.surface2.b, 1)
	local headerRule = header:CreateTexture(nil, "BORDER")
	headerRule:SetPoint("BOTTOMLEFT")
	headerRule:SetPoint("BOTTOMRIGHT")
	headerRule:SetHeight(1)
	headerRule:SetColorTexture(theme.borderSubtle.r, theme.borderSubtle.g, theme.borderSubtle.b, 1)
	widget.header = header

	local footerHeight = 0
	if options.footer then
		footerHeight = theme.size.footer
		local footer = CreateFrame("Frame", nil, frame)
		footer:SetPoint("BOTTOMLEFT", 1, 1)
		footer:SetPoint("BOTTOMRIGHT", -1, 1)
		footer:SetHeight(footerHeight)
		local fill = footer:CreateTexture(nil, "BACKGROUND")
		fill:SetAllPoints()
		fill:SetColorTexture(theme.surface2.r, theme.surface2.g, theme.surface2.b, 1)
		local rule = footer:CreateTexture(nil, "BORDER")
		rule:SetPoint("TOPLEFT")
		rule:SetPoint("TOPRIGHT")
		rule:SetHeight(1)
		rule:SetColorTexture(theme.borderSubtle.r, theme.borderSubtle.g, theme.borderSubtle.b, 1)
		footer.right = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		footer.right:SetPoint("RIGHT", -gutter, 0)
		footer.right:SetJustifyH("RIGHT")
		footer.right:SetWordWrap(false)
		footer.left = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		footer.left:SetPoint("LEFT", 8, 0)
		footer.left:SetPoint("RIGHT", footer.right, "LEFT", -12, 0)
		footer.left:SetJustifyH("LEFT")
		footer.left:SetWordWrap(false)
		for _, text in ipairs({ footer.left, footer.right }) do
			text:SetTextColor(theme.textMuted.r, theme.textMuted.g, theme.textMuted.b)
		end
		widget.footer = footer
		-- Tables with a page size get Prev / "Page N of M" / Next, shown once there is a second page.
		if widget.maxRows then
			local pager = CreateFrame("Frame", nil, footer)
			pager:SetPoint("RIGHT", -gutter, 0)
			pager:SetHeight(footerHeight)
			pager.next = ProfessionExporter:CreateButton(pager, "Next", function() widget:SetPage(widget.page + 1) end, { small = true })
			pager.next:SetPoint("RIGHT")
			pager.label = pager:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			pager.label:SetPoint("RIGHT", pager.next, "LEFT", -8, 0)
			pager.label:SetTextColor(theme.textMuted.r, theme.textMuted.g, theme.textMuted.b)
			pager.prev = ProfessionExporter:CreateButton(pager, "Prev", function() widget:SetPage(widget.page - 1) end, { small = true })
			pager.prev:SetPoint("RIGHT", pager.label, "LEFT", -8, 0)
			for _, button in ipairs({ pager.prev, pager.next }) do
				button:SetHeight(footerHeight - 6)
			end
			pager:Hide()
			widget.pager = pager
		end
	end

	local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	-- SetHeight(0) means "no height" in WoW, so a headerless table anchors to the frame instead.
	if widget.headerHeight > 0 then
		scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
	else
		header:Hide()
		scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
	end
	scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(gutter + 1), footerHeight + 1)
	widget.scrollFrame = scrollFrame
	ProfessionExporter:SkinTree(frame)

	local empty = CreateFrame("Frame", nil, frame)
	empty:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 24, -24)
	empty:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", -24, 24)
	empty.title = empty:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	empty.title:SetPoint("BOTTOM", empty, "CENTER", 0, 2)
	empty.title:SetPoint("LEFT")
	empty.title:SetPoint("RIGHT")
	empty.hint = empty:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	empty.hint:SetPoint("TOP", empty, "CENTER", 0, -4)
	empty.hint:SetPoint("LEFT")
	empty.hint:SetPoint("RIGHT")
	empty.hint:SetTextColor(theme.textMuted.r, theme.textMuted.g, theme.textMuted.b)
	empty:Hide()
	widget.emptyFrame = empty
	widget.emptyTitle = options.emptyTitle
	widget.emptyHint = options.emptyHint

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

