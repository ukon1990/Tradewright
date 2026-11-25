local _, Tradewright = ...

-- Table layout: which columns fit and how wide each one is (methods of the reusable table).

local TableMixin = Tradewright.TableMixin

local DEFAULT_WIDTH = 80
local DEFAULT_MIN_FLEX_WIDTH = 60

local function fixedWidth(column)
	return tonumber(column.width) or DEFAULT_WIDTH
end

-- A `fitContent` column wants at least the width of its widest text (measured on SetRows).
local function wantedWidth(column, fitWidths)
	return math.max(fixedWidth(column), fitWidths and fitWidths[column.id] or 0)
end

local function flexWeight(column)
	return math.max(0, tonumber(column.flex) or 0)
end

local function minFlexWidth(column)
	return tonumber(column.minWidth) or DEFAULT_MIN_FLEX_WIDTH
end

-- A fixed column with a smaller `minWidth` may shrink to it when the table is narrow.
local function fixedMinWidth(column)
	return math.min(fixedWidth(column), tonumber(column.minWidth) or fixedWidth(column))
end

-- Width fixed columns want, the least they and the flex columns need, and the sum of flex weights.
local function measure(columns, fitWidths)
	local fixed, minFixed, minFlex, totalFlex = 0, 0, 0, 0
	for _, column in ipairs(columns) do
		if flexWeight(column) > 0 then
			minFlex = minFlex + minFlexWidth(column)
			totalFlex = totalFlex + flexWeight(column)
		else
			fixed = fixed + wantedWidth(column, fitWidths)
			minFixed = minFixed + fixedMinWidth(column)
		end
	end
	return fixed, minFixed, minFlex, totalFlex
end

-- How far (0..1) shrinkable fixed columns grow from minWidth toward width with `room` to spare.
local function fixedGrowth(fixed, minFixed, room)
	if fixed <= minFixed then
		return 1
	end
	return math.max(0, math.min(1, room / (fixed - minFixed)))
end

local function fixedLayoutWidth(column, growth, fitWidths)
	local least = fixedMinWidth(column)
	return least + math.floor((wantedWidth(column, fitWidths) - least) * growth)
end

-- Index of the next optional column to drop: the right-most `dropFirst` one, else the right-most optional one.
local function dropCandidate(columns)
	local dropIndex
	for index = #columns, 1, -1 do
		local column = columns[index]
		if column.optional and column.dropFirst then
			return index
		end
		if column.optional and not dropIndex then
			dropIndex = index
		end
	end
	return dropIndex
end

function TableMixin:GetLayoutColumnWidth(column)
	if not column then
		return DEFAULT_WIDTH
	end
	local width = self._layoutColumnWidths and self._layoutColumnWidths[column.id]
	return width or wantedWidth(column, self._fitWidths)
end

function TableMixin:SetFixedColumnWidths(columns)
	local sum = 0
	for _, column in ipairs(columns) do
		self._layoutColumnWidths[column.id] = wantedWidth(column, self._fitWidths)
		sum = sum + self._layoutColumnWidths[column.id]
	end
	self.contentWidth = self.paddingX * 2 + sum
end

-- Drops optional columns (into `_droppedColumns`) until the rest fit `viewport`; returns the kept ones.
function TableMixin:DropColumnsToFit(visible, viewport)
	local columns = {}
	for index, column in ipairs(visible) do
		columns[index] = column
	end
	local _, minFixed, minFlex = measure(columns, self._fitWidths)
	while minFixed + minFlex > viewport do
		local dropIndex = dropCandidate(columns)
		if not dropIndex then
			break
		end
		self._droppedColumns[columns[dropIndex].id] = true
		table.remove(columns, dropIndex)
		_, minFixed, minFlex = measure(columns, self._fitWidths)
	end
	return columns
end

-- Layout rule: flex columns start at minWidth; fixed columns then grow from their minWidth (when smaller)
-- to their width, or to their widest text for `fitContent` columns; flex columns share what is left.
-- So the item name gives up room before the numbers do. When even every minWidth does not fit,
-- `optional` columns are dropped: those marked `dropFirst` before any other, then from the right.
function TableMixin:RecomputeLayoutColumnWidths()
	local visible = self:GetVisibleColumns()
	self._layoutColumnWidths = {}
	self._droppedColumns = {}
	if not self.autoFitToScroll or not self.scrollFrame or #visible == 0 then
		return self:SetFixedColumnWidths(visible)
	end
	local viewport = math.max(DEFAULT_WIDTH, math.floor((self.scrollFrame:GetWidth() or 400) - self.paddingX * 2))
	local columns = self:DropColumnsToFit(visible, viewport)
	local fixed, minFixed, minFlex, totalFlex = measure(columns, self._fitWidths)
	local growth = fixedGrowth(fixed, minFixed, viewport - minFixed - minFlex)
	local widths, flexRoom = self._layoutColumnWidths, viewport
	for _, column in ipairs(columns) do
		if flexWeight(column) == 0 then
			widths[column.id] = fixedLayoutWidth(column, growth, self._fitWidths)
			flexRoom = flexRoom - widths[column.id]
		end
	end
	local sum = 0
	for _, column in ipairs(columns) do
		widths[column.id] = widths[column.id]
			or math.max(minFlexWidth(column), math.floor(flexRoom * flexWeight(column) / totalFlex))
		sum = sum + widths[column.id]
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

-- Characters a cell text shows: colour codes take no room, a coin or other inline icon about two digits.
local function visibleLength(text)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	local stripped, icons = text:gsub("|T.-|t", "")
	return #stripped + icons * 2
end

-- The longest text the column shows over all rows. Not the largest number: short money drops
-- zero parts, so "100g" is narrower than "99g 99s 99c".
function TableMixin:WidestCellText(column)
	local widest, widestLength = nil, -1
	for _, row in ipairs(self.rows or {}) do
		local text = tostring(self:CellText(column, row))
		local length = visibleLength(text)
		if length > widestLength then
			widest, widestLength = text, length
		end
	end
	return widest
end

function TableMixin:MeasureCellText(column, text)
	if not self.measureText then
		self.measureText = self.frame:CreateFontString(nil, "OVERLAY")
		self.measureText:Hide()
	end
	local font = column.fontObject or (column.justifyH == "RIGHT" and "NumberFontNormalSmall" or "GameFontHighlightSmall")
	self.measureText:SetFontObject(font)
	self.measureText:SetText(text)
	return math.ceil(self.measureText:GetStringWidth()) + self.CELL_PAD * 2 + 2
end

-- Measures every `fitContent` column against the current rows; true when a width changed, so the
-- header and rows need laying out again.
function TableMixin:MeasureFitWidths()
	local widths, changed = {}, false
	for _, column in ipairs(self.columns or {}) do
		local text = column.fitContent and self:WidestCellText(column)
		widths[column.id] = text and self:MeasureCellText(column, text) or nil
		changed = changed or widths[column.id] ~= (self._fitWidths and self._fitWidths[column.id])
	end
	self._fitWidths = widths
	return changed
end
