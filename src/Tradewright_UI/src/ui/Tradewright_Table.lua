local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
local TableMixin = {}
Tradewright.TableMixin = TableMixin -- methods are spread over the Table*.lua files
Tradewright.ReusableTables = setmetatable({}, { __mode = "k" }) -- every table, to redraw item names as they load

local WHITE = "Interface\\Buttons\\WHITE8X8"
local CELL_PAD = 5
TableMixin.CELL_PAD = CELL_PAD

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

	self:MeasureFitWidths()
	self:Refresh()
end

function TableMixin:ColumnIndex(columnId)
	for index, column in ipairs(self.columns or {}) do
		if column.id == columnId then
			return index
		end
	end
end

function TableMixin:ReorderColumns(sourceId, targetId)
	if not sourceId or not targetId or sourceId == targetId then
		return
	end
	local sourceIndex, targetIndex = self:ColumnIndex(sourceId), self:ColumnIndex(targetId)
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
	if self:MeasureFitWidths() then
		self:UpdateHeader()
	end
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
-- A stable tiebreak so equal sort keys keep one order across refreshes.
local function rowIdentity(row)
	if row._rowIdentity == nil then
		if row.aggregatedInventory then
			row._rowIdentity = tostring(row.itemID or "")
		else
			row._rowIdentity = string.format("%s:%s", tostring(row.characterKey or ""), tostring(row.itemID or ""))
		end
	end
	return tostring(row._rowIdentity)
end

local function compareKeys(a, b)
	if type(a) ~= type(b) then
		a, b = tonumber(a) or 0, tonumber(b) or 0
	end
	return a < b and -1 or (a > b and 1 or 0)
end

-- A comparator for table.sort: the column's own `compare`, or its precomputed sort keys.
function TableMixin:RowComparator(column, rows)
	local keys, ids = {}, {}
	for _, row in ipairs(rows) do
		ids[row] = rowIdentity(row)
		if not column.compare then
			local value = self:GetSortValue(column, row)
			keys[row] = type(value) == "number" and value or normalizeText(value)
		end
	end
	local asc, context = self.sortAsc, self.context or {}
	return function(left, right)
		local cmp
		if column.compare then
			cmp = column.compare(left, right, context, self) or 0
		else
			cmp = compareKeys(keys[left], keys[right])
		end
		if cmp == 0 then
			return ids[left] < ids[right]
		end
		return (asc and cmp < 0) or (not asc and cmp > 0)
	end
end

function TableMixin:GetSortedRows()
	if self._sorted and self._sortedFrom == self.rows and self._sortedKey == self.sortKey and self._sortedAsc == self.sortAsc then
		return self._sorted
	end
	local rows = shallowCopy(self.rows)
	local column = self.sortKey and self:GetColumn(self.sortKey)
	if column then
		table.sort(rows, self:RowComparator(column, rows))
	end
	self._sorted, self._sortedFrom, self._sortedKey, self._sortedAsc = rows, self.rows, self.sortKey, self.sortAsc
	return rows
end

function TableMixin:CreateDefaultCell(rowFrame, column)
	local fontString = rowFrame:CreateFontString(nil, "OVERLAY", column.fontObject or (column.justifyH == "RIGHT" and "NumberFontNormalSmall" or "GameFontHighlightSmall"))
	fontString:SetJustifyH(column.justifyH or "LEFT")
	fontString:SetWordWrap(false)
	local text = Tradewright:GetTheme().textPrimary
	Tradewright:ColorText(fontString, text)
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
	Tradewright:TintTexture(row:GetHighlightTexture(), "hover")
	row.selectedFill = row:CreateTexture(nil, "BACKGROUND")
	row.selectedFill:SetAllPoints()
	Tradewright:ColorTexture(row.selectedFill, "gold", 0.07)
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

-- Places one cell region at `x` in the row, `width` wide; font strings get the cell padding.
function TableMixin:PlaceCell(rowFrame, region, x, width)
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
end

function TableMixin:CellText(column, rowData)
	if type(column.getText) == "function" then
		return column.getText(rowData, self.context or {}, self) or ""
	end
	return rowData and rowData[column.field or column.id] or ""
end

function TableMixin:FillCell(cell, column, rowData)
	local text = tostring(self:CellText(column, rowData))
	if type(cell) == "table" and cell.text and cell.text.SetText then
		cell.text:SetText(text)
	elseif cell and cell.SetText then
		cell:SetText(text)
	end
end

function TableMixin:IsColumnShown(columnId)
	local column = self:GetColumn(columnId)
	if not column or not isColumnVisible(column, self.context or {}) then
		return false
	end
	return not (self._droppedColumns and self._droppedColumns[columnId])
end

function TableMixin:UpdateRow(rowFrame, rowData, rowIndex)
	local x = self.paddingX
	rowFrame.rowData = rowData
	rowFrame:SetWidth(self.contentWidth)
	rowFrame.selectedFill:SetShown(self:IsRowSelected(rowData))
	for _, column in ipairs(self:GetLayoutColumns()) do
		local cell = self:AcquireCell(rowFrame, column)
		local width = self:GetLayoutColumnWidth(column)
		self:PlaceCell(rowFrame, getCellRegion(cell), x, width)
		if type(column.updateCell) == "function" then
			column.updateCell(cell, rowData, self.context or {}, self, rowFrame, rowIndex)
		else
			self:FillCell(cell, column, rowData)
		end
		x = x + width
	end
	for columnId, cell in pairs(rowFrame.cells) do
		if not self:IsColumnShown(columnId) then
			getCellRegion(cell):Hide()
		end
	end
	rowFrame:ClearAllPoints()
	rowFrame:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, -((rowIndex - 1) * self.rowHeight))
	rowFrame:Show()
end

-- The scroll frame's height, or a default while it has not been laid out yet.
function TableMixin:GetViewportHeight()
	local height = self.scrollFrame:GetHeight()
	return (height and height > 40) and height or 320
end

-- First and last display row to draw: the rows in view plus `virtualOverscan` rows on each side.
function TableMixin:GetVirtualRowRange(count)
	local scroll = self.scrollFrame:GetVerticalScroll() or 0
	local rowH = self.rowHeight
	local overscan = self.virtualOverscan or 6
	local firstVisible = math.floor(scroll / rowH) + 1
	local lastVisible = math.min(count, math.ceil((scroll + self:GetViewportHeight()) / rowH))
	local first = math.max(1, firstVisible - overscan)
	local last = math.min(count, lastVisible + overscan)
	if first > last then
		-- Scrolled past the end (rows were removed): draw the last rows instead of nothing.
		first = math.max(1, count - overscan * 2)
		last = count
	end
	return first, last
end

function TableMixin:HideRowsFrom(slot)
	for index = slot, #self.rowPool do
		self.rowPool[index]:Hide()
	end
end

function TableMixin:RefreshVirtualRowWindow()
	if not self.useViewportVirtualization or not self.scrollFrame then
		return
	end
	local displayRows = self.displayRows or {}
	local count = #displayRows
	if count == 0 then
		self:HideRowsFrom(1)
		return
	end
	local first, last = self:GetVirtualRowRange(count)
	local poolSlots = last - first + 1
	for slot = 1, poolSlots do
		local i = first + slot - 1
		local row = self:AcquireRow(slot)
		self:UpdateRow(row, displayRows[i], i)
		row:Show()
	end
	self:HideRowsFrom(poolSlots + 1)
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
	local rowH = self.rowHeight or 20
	local first = math.max(1, math.floor(scroll / rowH) + 1)
	local last = math.min(count, math.ceil((scroll + self:GetViewportHeight()) / rowH))
	local out = {}
	for index = first, last do
		out[#out + 1] = rows[index]
	end
	return out
end

-- maxRows is the page size. Paging needs the footer for its controls; without one only the
-- first page is shown. Narrows displayRows to the current page.
function TableMixin:ApplyPage()
	local count = #self.displayRows
	self.totalRowCount = count
	self.page, self.pageCount, self.pageFirst, self.pageLast = Tradewright.FilterLogic.PageBounds(count, self.maxRows,
		self.pager and self.page or 1)
	if self.pageCount > 1 then
		local pageRows = {}
		for index = self.pageFirst, self.pageLast do
			pageRows[#pageRows + 1] = self.displayRows[index]
		end
		self.displayRows = pageRows
	end
end

-- Sizes the scroll child for `count` rows, then scrolls to the top or back to `previousScroll`
-- (clamped, since the content may have shrunk).
function TableMixin:SizeScrollContent(count, resetScroll, previousScroll)
	self.scrollChild:SetWidth(self.contentWidth)
	self.scrollChild:SetHeight(math.max(self.rowHeight, count * self.rowHeight + 4))
	if not self.scrollFrame then
		return
	end
	if resetScroll then
		self.scrollFrame:SetVerticalScroll(0)
		return
	end
	local maxScroll = math.max(0, (self.scrollChild:GetHeight() or 0) - (self.scrollFrame:GetHeight() or 0))
	self.scrollFrame:SetVerticalScroll(math.min(previousScroll, maxScroll))
end

function TableMixin:RefreshRows(opts)
	opts = opts or {}
	self.displayRows = self:GetSortedRows()
	self:ApplyPage()
	local count = #self.displayRows
	local resetScroll = opts.resetVerticalScroll == true
	local previousScroll = self.scrollFrame and not resetScroll and self.scrollFrame:GetVerticalScroll() or 0

	if self.useViewportVirtualization then
		self:SizeScrollContent(count, resetScroll, previousScroll)
		self:RefreshVirtualRowWindow()
		return
	end
	for index, rowData in ipairs(self.displayRows) do
		local row = self:AcquireRow(index)
		self:UpdateRow(row, rowData, index)
	end
	self:HideRowsFrom(count + 1)
	self:SizeScrollContent(count, resetScroll, previousScroll)
end

function TableMixin:SetEmptyText(title, hint)
	self.emptyTitle = title
	self.emptyHint = hint
	self:UpdateEmptyState()
end

function TableMixin:UpdateEmptyState()
	local empty = #(self.displayRows or {}) == 0
	local loading = empty and self.loadingNote ~= nil
	self.emptyFrame:SetShown(empty and not loading)
	self:ShowLoadingState(loading)
	self.emptyFrame.title:SetText(self.emptyTitle or L["Nothing to show"])
	self.emptyFrame.hint:SetText(self.emptyHint or L["Change the search or filters."])
end

function TableMixin:Refresh(opts)
	self:UpdateHeader()
	self:RefreshRows(opts)
	self:UpdateEmptyState()
	self:UpdateFooter()
end

-- Settings copied from `options` onto the table as they are.
local OPTION_FIELDS = {
	"isRowSelected", "maxRows", "sortKey", "onSortChanged", "onColumnReordered",
	"onRowEnter", "onRowLeave", "onRowClick", "emptyTitle", "emptyHint",
}

function TableMixin:InitTableState(options)
	local sizes = Tradewright:GetTheme().size
	self.columns, self.columnsById = {}, {}
	self.rows, self.context = {}, {}
	self.rowPool = {}
	self.headerButtons = {}
	for _, field in ipairs(OPTION_FIELDS) do
		self[field] = options[field]
	end
	self.paddingX = options.paddingX or 4
	self.rowHeight = math.max(options.rowHeight or sizes.row, sizes.row)
	self.headerHeight = options.headerHeight or sizes.tableHead
	self.sortAsc = options.sortAsc ~= false
	self.contentWidth = 0
	self.autoFitToScroll = options.autoFitToScroll == true
	self._layoutColumnWidths = {}
	self.useViewportVirtualization = options.viewportVirtualize == true
end

function TableMixin:CreateHeaderBar()
	local header = CreateFrame("Frame", nil, self.frame)
	header:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 1, -1)
	header:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -1, -1)
	header:SetHeight(self.headerHeight)
	local headerFill = header:CreateTexture(nil, "BACKGROUND")
	headerFill:SetAllPoints()
	Tradewright:ColorTexture(headerFill, "surface2", 1)
	local headerRule = header:CreateTexture(nil, "BORDER")
	headerRule:SetPoint("BOTTOMLEFT")
	headerRule:SetPoint("BOTTOMRIGHT")
	headerRule:SetHeight(1)
	Tradewright:ColorTexture(headerRule, "borderSubtle", 1)
	self.header = header
end

function TableMixin:CreateScrollArea(footerHeight)
	local gutter = Tradewright:GetTheme().size.scrollGutter
	local scrollFrame = CreateFrame("ScrollFrame", nil, self.frame, "UIPanelScrollFrameTemplate")
	-- SetHeight(0) means "no height" in WoW, so a headerless table anchors to the frame instead.
	if self.headerHeight > 0 then
		scrollFrame:SetPoint("TOPLEFT", self.header, "BOTTOMLEFT", 0, 0)
	else
		self.header:Hide()
		scrollFrame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 1, -1)
	end
	scrollFrame:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -(gutter + 1), footerHeight + 1)
	self.scrollFrame = scrollFrame
	Tradewright:SkinTree(self.frame)
	local scrollChild = CreateFrame("Frame", nil, scrollFrame)
	scrollChild:SetWidth(1)
	scrollChild:SetHeight(self.rowHeight)
	scrollFrame:SetScrollChild(scrollChild)
	self.scrollChild = scrollChild
end

function TableMixin:CreateEmptyState()
	local muted = Tradewright:GetTheme().textMuted
	local empty = CreateFrame("Frame", nil, self.frame)
	empty:SetPoint("TOPLEFT", self.scrollFrame, "TOPLEFT", 24, -24)
	empty:SetPoint("BOTTOMRIGHT", self.scrollFrame, "BOTTOMRIGHT", -24, 24)
	empty.title = empty:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	empty.title:SetPoint("BOTTOM", empty, "CENTER", 0, 2)
	empty.title:SetPoint("LEFT")
	empty.title:SetPoint("RIGHT")
	empty.hint = empty:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	empty.hint:SetPoint("TOP", empty, "CENTER", 0, -4)
	empty.hint:SetPoint("LEFT")
	empty.hint:SetPoint("RIGHT")
	Tradewright:ColorText(empty.hint, muted)
	empty:Hide()
	self.emptyFrame = empty
end

-- Redraw on resize; virtualized tables also redraw the visible row window on scroll.
function TableMixin:BindResizeScripts()
	local scrollFrame = self.scrollFrame
	if self.useViewportVirtualization then
		scrollFrame:SetScript("OnVerticalScroll", function()
			self:RefreshVirtualRowWindow()
		end)
	end
	if self.useViewportVirtualization or self.autoFitToScroll then
		scrollFrame:HookScript("OnSizeChanged", function()
			if self.autoFitToScroll then
				self:Refresh()
			else
				self:RefreshVirtualRowWindow()
			end
		end)
	end
	self.frame:HookScript("OnSizeChanged", function()
		self:Refresh()
	end)
end

--- A sortable, reorderable, optionally paged and virtualized table. See OPTION_FIELDS and
--- InitTableState for `options`; `options.footer` adds a footer (and a pager with `maxRows`).
function Tradewright:CreateReusableTable(parent, options)
	options = options or {}
	local widget = setmetatable({}, { __index = TableMixin })
	Tradewright.ReusableTables[widget] = true
	widget:InitTableState(options)
	local theme = Tradewright:GetTheme()
	local frame = CreateFrame("Frame", nil, parent)
	widget.frame = frame
	if frame.SetClipsChildren then
		frame:SetClipsChildren(true)
	end
	Tradewright:AddSurface(frame, { r = 0, g = 0, b = 0, a = 0 }, theme.borderSubtle)
	widget:CreateHeaderBar()
	local footerHeight = 0
	if options.footer then
		footerHeight = theme.size.footer
		widget:CreateFooter(footerHeight)
	end
	widget:CreateScrollArea(footerHeight)
	widget:CreateEmptyState()
	widget:BindResizeScripts()
	return widget
end
