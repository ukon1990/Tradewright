local _, Tradewright = ...

-- Table header: sortable, draggable column buttons and their tooltips (methods of the reusable table).

local TableMixin = Tradewright.TableMixin
local CELL_PAD = TableMixin.CELL_PAD

local function headerTooltipLines(table, column)
	if type(column.getTooltipLines) == "function" then
		return column.getTooltipLines(table.context or {}, table)
	end
	return column.tooltipLines
end

local function addTooltipLine(line, muted)
	if type(line) == "table" then
		GameTooltip:AddLine(line.text or "", line.r or muted.r, line.g or muted.g, line.b or muted.b, line.wrap == true)
	else
		GameTooltip:AddLine(tostring(line), muted.r, muted.g, muted.b, true)
	end
end

local function hasTooltip(column)
	return column.tooltipTitle or column.tooltipText or column.tooltipLines or column.getTooltipLines
end

local function tooltipTitle(column)
	return column.tooltipTitle or column.label or column.id or "Column"
end

function TableMixin:ShowHeaderTooltip(button)
	local column = button and button.column
	if not column then
		return
	end
	local lines = headerTooltipLines(self, column) or {}
	local text = column.tooltipText
	if not column.tooltipTitle and not text and #lines == 0 then
		return
	end
	local theme = Tradewright:GetTheme()
	local gold, muted = theme.gold, theme.textMuted
	GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
	GameTooltip:SetText(tooltipTitle(column), gold.r, gold.g, gold.b)
	if text and text ~= "" then
		GameTooltip:AddLine(text, muted.r, muted.g, muted.b, true)
	end
	for _, line in ipairs(lines) do
		addTooltipLine(line, muted)
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
	button.arrow = button:CreateTexture(nil, "OVERLAY")
	button.arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
	button.arrow:SetSize(9, 8)
	button.arrow:Hide()
	self:BindHeaderButtonScripts(button)
	self.headerButtons[index] = button
	return button
end

-- Click sorts, hover shows the column tooltip, dragging onto another header reorders the columns.
function TableMixin:BindHeaderButtonScripts(button)
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
		if btn.columnId then
			self.dragColumnId = btn.columnId
			btn:SetAlpha(0.45)
		end
	end)
	button:SetScript("OnDragStop", function(btn)
		self:DropHeaderButton(btn)
	end)
end

function TableMixin:DropHeaderButton(button)
	local sourceId = self.dragColumnId
	self.dragColumnId = nil
	button:SetAlpha(1)
	if not sourceId then
		return
	end
	for _, target in ipairs(self.headerButtons or {}) do
		if target ~= button and target:IsShown() and target.columnId and target:IsMouseOver() then
			self:ReorderColumns(sourceId, target.columnId)
			return
		end
	end
end

-- Label colour and sort arrow; the label makes room for the arrow on the sorted column.
function TableMixin:StyleHeaderButton(button, column)
	local theme = Tradewright:GetTheme()
	local sorted = column.sortable == true and self.sortKey == column.id
	local color = sorted and theme.gold or theme.textMuted
	button.text:SetText(column.label or column.id)
	button.text:SetJustifyH(column.justifyH or "LEFT")
	Tradewright:ColorText(button.text, color)
	button.text:ClearAllPoints()
	button.arrow:ClearAllPoints()
	button.text:SetPoint("LEFT", button, "LEFT", CELL_PAD, 0)
	button.text:SetPoint("RIGHT", button, "RIGHT", sorted and -(CELL_PAD + 11) or -CELL_PAD, 0)
	self:StyleSortArrow(button.arrow, sorted)
end

function TableMixin:StyleSortArrow(arrow, sorted)
	local gold = Tradewright:GetTheme().gold
	arrow:SetPoint("RIGHT", arrow:GetParent(), "RIGHT", -CELL_PAD, 0)
	arrow:SetShown(sorted)
	if sorted then
		Tradewright:TintTexture(arrow, gold)
		arrow:SetTexCoord(0, 0.5625, self.sortAsc and 1 or 0, self.sortAsc and 0 or 1)
	end
end

function TableMixin:UpdateHeader()
	self:RecomputeLayoutColumnWidths()
	local visibleColumns = self:GetLayoutColumns()
	local x = self.paddingX
	for index, column in ipairs(visibleColumns) do
		local button = self:AcquireHeaderButton(index)
		local width = self:GetLayoutColumnWidth(column)
		button.column = column
		button.columnId = column.sortable and column.id or nil
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", self.header, "TOPLEFT", x, 0)
		button:SetWidth(width)
		button:EnableMouse(column.sortable == true or hasTooltip(column) ~= nil)
		self:StyleHeaderButton(button, column)
		button:Show()
		x = x + width
	end
	for index = #visibleColumns + 1, #self.headerButtons do
		self.headerButtons[index]:Hide()
	end
	self.header:SetHeight(self.headerHeight)
end
