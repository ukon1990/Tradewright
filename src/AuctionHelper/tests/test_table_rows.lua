-- Run with: lua5.1 tests/test_table_rows.lua (from AuctionHelper root)
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

local pe = {}
for _, path in ipairs({ root .. "/src/util/AuctionHelper_FilterLogic.lua", root .. "/../AuctionHelper_UI/src/ui/AuctionHelper_Table.lua" }) do
	local chunk, err = loadfile(path)
	assert(chunk, err)
	chunk("AuctionHelper", pe)
end
local TableMixin = pe.TableMixin

local function newTable(scroll, height)
	local widget = setmetatable({ rowHeight = 20, virtualOverscan = 2 }, { __index = TableMixin })
	widget.scrollFrame = {
		GetVerticalScroll = function() return scroll end,
		GetHeight = function() return height end,
	}
	return widget
end

-- Virtual row window
local first, last = newTable(0, 100):GetVirtualRowRange(50)
check("Window: top rows plus overscan below", first == 1 and last == 7, first .. "-" .. last)
first, last = newTable(200, 100):GetVirtualRowRange(50)
check("Window: overscan on both sides", first == 9 and last == 17, first .. "-" .. last)
first, last = newTable(0, nil):GetVirtualRowRange(50)
check("Window: unlaid-out frame uses default height", first == 1 and last == 18, first .. "-" .. last)
local _, tinyLast = newTable(0, 10):GetVirtualRowRange(50)
check("Window: tiny frame uses default height", tinyLast == 18, tinyLast)
first, last = newTable(2000, 100):GetVirtualRowRange(10)
check("Window: scrolled past the end shows the last rows", first == 6 and last == 10, first .. "-" .. last)
first, last = newTable(0, 100):GetVirtualRowRange(3)
check("Window: fewer rows than fit", first == 1 and last == 3)

-- Paging
local rows = {}
for i = 1, 25 do
	rows[i] = i
end
local paged = setmetatable({ displayRows = rows, maxRows = 10, pager = true, page = 3 }, { __index = TableMixin })
paged:ApplyPage()
check("Page: last page holds the rest", #paged.displayRows == 5 and paged.displayRows[1] == 21 and paged.totalRowCount == 25)
check("Page: bounds", paged.pageCount == 3 and paged.pageFirst == 21 and paged.pageLast == 25)
local noPager = setmetatable({ displayRows = rows, maxRows = 10, page = 3 }, { __index = TableMixin })
noPager:ApplyPage()
check("Page: without a pager only the first page", noPager.displayRows[1] == 1 and #noPager.displayRows == 10)
local single = setmetatable({ displayRows = { 1, 2 }, maxRows = 10 }, { __index = TableMixin })
single:ApplyPage()
check("Page: one page keeps every row", #single.displayRows == 2 and single.pageCount == 1)

if failed > 0 then
	print(failed .. " table row check(s) failed")
	os.exit(1)
end
print("All table row checks passed")
