-- Run with: lua5.1 tests/test_table_layout.lua (from Tradewright root)
local root = arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]") or "."

local failed = 0
local function check(name, cond, detail)
	if cond then
		print("OK  " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
	end
end

local TableMixin = {}
local chunk, err = loadfile(root .. "/../Tradewright_UI/src/ui/Tradewright_TableLayout.lua")
assert(chunk, err)
chunk("Tradewright_UI", { TableMixin = TableMixin })

-- A table whose scroll frame is `viewport + 2 * paddingX` wide.
local function newTable(columns, viewport)
	local widget = setmetatable({ paddingX = 4, autoFitToScroll = viewport ~= nil }, { __index = TableMixin })
	function widget:GetVisibleColumns()
		return columns
	end
	if viewport then
		widget.scrollFrame = { GetWidth = function() return viewport + 8 end }
	end
	widget:RecomputeLayoutColumnWidths()
	return widget
end

local function ids(widget)
	local out = {}
	for _, column in ipairs(widget:GetLayoutColumns()) do
		out[#out + 1] = column.id
	end
	return table.concat(out, ",")
end

-- Fixed layout
local fixed = newTable({ { id = "a", width = 100 }, { id = "b" } })
check("Fixed: own width", fixed:GetLayoutColumnWidth({ id = "a", width = 100 }) == 100)
check("Fixed: default width", fixed:GetLayoutColumnWidth({ id = "b" }) == 80)
check("Fixed: content width adds padding", fixed.contentWidth == 188, fixed.contentWidth)
check("Fixed: no column is a default width", fixed:GetLayoutColumnWidth(nil) == 80)
check("Empty: only padding", newTable({}, 300).contentWidth == 8)

-- Flex layout
local flex = newTable({ { id = "name", flex = 2, minWidth = 50 }, { id = "price", width = 100 }, { id = "qty", flex = 1 } }, 400)
check("Flex: spare split by weight", flex._layoutColumnWidths.name == 200 and flex._layoutColumnWidths.qty == 100,
	tostring(flex._layoutColumnWidths.name) .. "/" .. tostring(flex._layoutColumnWidths.qty))
check("Flex: fixed column keeps its width", flex._layoutColumnWidths.price == 100)
check("Flex: content fills the viewport", flex.contentWidth == 408, flex.contentWidth)

local narrow = newTable({ { id = "name", flex = 1, minWidth = 90 }, { id = "qty", flex = 3 } }, 160)
check("Flex: never below minWidth", narrow._layoutColumnWidths.name == 90, narrow._layoutColumnWidths.name)

-- Shrinkable fixed columns: the name keeps its minWidth, the numbers give up room before any column is dropped.
local shrink = { { id = "name", flex = 1, minWidth = 100 }, { id = "price", width = 100, minWidth = 60 }, { id = "qty", width = 50 } }
local wide = newTable(shrink, 400)
check("Shrink: wide table gives numbers their width", wide._layoutColumnWidths.price == 100 and wide._layoutColumnWidths.name == 250,
	tostring(wide._layoutColumnWidths.price) .. "/" .. tostring(wide._layoutColumnWidths.name))
local mid = newTable(shrink, 230)
check("Shrink: numbers shrink before the name goes below minWidth", mid._layoutColumnWidths.price == 80 and mid._layoutColumnWidths.name == 100,
	tostring(mid._layoutColumnWidths.price) .. "/" .. tostring(mid._layoutColumnWidths.name))
local least = newTable(shrink, 150)
check("Shrink: never below minWidth", least._layoutColumnWidths.price == 60, least._layoutColumnWidths.price)
check("Shrink: minWidth above width is ignored", newTable({ { id = "a", width = 50, minWidth = 90 } }, 40)._layoutColumnWidths.a == 50)
local optionalShrink = { { id = "name", flex = 1, minWidth = 100 }, { id = "a", width = 100, minWidth = 60, optional = true } }
check("Shrink: an optional column shrinks before it is dropped",
	ids(newTable(optionalShrink, 160)) == "name,a" and ids(newTable(optionalShrink, 159)) == "name")

-- Fitting columns to their widest text. The fake font is 6px a character, an inline icon 12px.
TableMixin.CELL_PAD = 5
local function fitTable(columns, rows, viewport)
	local widget = setmetatable({ paddingX = 4, autoFitToScroll = true, columns = columns, rows = rows }, { __index = TableMixin })
	local shown = ""
	widget.frame = { CreateFontString = function()
		return { Hide = function() end, SetFontObject = function() end, SetText = function(_, text) shown = text end,
			GetStringWidth = function()
				local visible = shown:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "XX")
				return #visible * 6
			end }
	end }
	widget.scrollFrame = { GetWidth = function() return viewport + 8 end }
	function widget:GetVisibleColumns() return columns end
	function widget:CellText(column, row) return column.getText(row) end
	widget:MeasureFitWidths()
	widget:RecomputeLayoutColumnWidths()
	return widget
end
local money = { id = "price", width = 40, minWidth = 30, fitContent = true, getText = function(row) return row.text end }
local fitRows = { { text = "100|Tg|t" }, { text = "|cffff0000-|r99|Tg|t 99|Ts|t" }, { text = "5" } }
local fit = fitTable({ { id = "name", flex = 1, minWidth = 50 }, money }, fitRows, 300)
check("Fit: widest visible text, not the biggest number", fit._layoutColumnWidths.price == 10 * 6 + 12, fit._layoutColumnWidths.price)
check("Fit: the name takes the rest", fit._layoutColumnWidths.name == 300 - 72, fit._layoutColumnWidths.name)
check("Fit: never narrower than width", fitTable({ money }, { { text = "1" } }, 300)._layoutColumnWidths.price == 40)
check("Fit: shrinks toward minWidth when narrow", fitTable({ { id = "name", flex = 1, minWidth = 50 }, money }, fitRows, 80)._layoutColumnWidths.price == 30)

-- Dropping optional columns
local columns = {
	{ id = "name", flex = 1, minWidth = 100 },
	{ id = "a", width = 80, optional = true },
	{ id = "b", width = 80, optional = true, dropFirst = true },
	{ id = "c", width = 80, optional = true },
}
check("Drop: everything fits", ids(newTable(columns, 340)) == "name,a,b,c")
check("Drop: dropFirst goes before the right-most", ids(newTable(columns, 339)) == "name,a,c")
check("Drop: then from the right", ids(newTable(columns, 259)) == "name,a")
check("Drop: required columns stay", ids(newTable(columns, 50)) == "name")

if failed > 0 then
	print(failed .. " table layout check(s) failed")
	os.exit(1)
end
print("All table layout checks passed")
