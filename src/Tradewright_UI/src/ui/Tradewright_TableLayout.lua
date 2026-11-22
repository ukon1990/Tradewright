local _, Tradewright = ...

-- Table layout: which columns fit and how wide each one is (methods of the reusable table).

local TableMixin = Tradewright.TableMixin

local DEFAULT_WIDTH = 80
local DEFAULT_MIN_FLEX_WIDTH = 60

local function fixedWidth(column)
	return tonumber(column.width) or DEFAULT_WIDTH
end

local function flexWeight(column)
	return math.max(0, tonumber(column.flex) or 0)
end

local function minFlexWidth(column)
	return tonumber(column.minWidth) or DEFAULT_MIN_FLEX_WIDTH
end

-- Width taken by fixed columns, the least the flex columns need, and the sum of flex weights.
local function measure(columns)
	local fixed, minFlex, totalFlex = 0, 0, 0
	for _, column in ipairs(columns) do
		if flexWeight(column) > 0 then
			minFlex = minFlex + minFlexWidth(column)
			totalFlex = totalFlex + flexWeight(column)
		else
			fixed = fixed + fixedWidth(column)
		end
	end
	return fixed, minFlex, totalFlex
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
	return width or fixedWidth(column)
end

function TableMixin:SetFixedColumnWidths(columns)
	local sum = 0
	for _, column in ipairs(columns) do
		self._layoutColumnWidths[column.id] = fixedWidth(column)
		sum = sum + fixedWidth(column)
	end
	self.contentWidth = self.paddingX * 2 + sum
end

-- Drops optional columns (into `_droppedColumns`) until the rest fit `viewport`; returns the kept ones.
function TableMixin:DropColumnsToFit(visible, viewport)
	local columns = {}
	for index, column in ipairs(visible) do
		columns[index] = column
	end
	local fixed, minFlex = measure(columns)
	while fixed + minFlex > viewport do
		local dropIndex = dropCandidate(columns)
		if not dropIndex then
			break
		end
		self._droppedColumns[columns[dropIndex].id] = true
		table.remove(columns, dropIndex)
		fixed, minFlex = measure(columns)
	end
	return columns
end

-- Layout rule: fixed columns keep their width; flex columns share what is left (never below
-- minWidth). When even that does not fit, `optional` columns are dropped: those marked
-- `dropFirst` before any other, then from the right.
function TableMixin:RecomputeLayoutColumnWidths()
	local visible = self:GetVisibleColumns()
	self._layoutColumnWidths = {}
	self._droppedColumns = {}
	if not self.autoFitToScroll or not self.scrollFrame or #visible == 0 then
		return self:SetFixedColumnWidths(visible)
	end
	local viewport = math.max(DEFAULT_WIDTH, math.floor((self.scrollFrame:GetWidth() or 400) - self.paddingX * 2))
	local columns = self:DropColumnsToFit(visible, viewport)
	local fixed, _, totalFlex = measure(columns)
	local spare = viewport - fixed
	local sum = 0
	for _, column in ipairs(columns) do
		local width = fixedWidth(column)
		if flexWeight(column) > 0 then
			width = math.max(minFlexWidth(column), math.floor(spare * flexWeight(column) / totalFlex))
		end
		self._layoutColumnWidths[column.id] = width
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
