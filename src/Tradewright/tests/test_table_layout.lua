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
