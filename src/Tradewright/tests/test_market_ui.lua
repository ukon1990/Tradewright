-- Run with: lua5.1 tests/test_market_ui.lua (from Tradewright root)
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

local settings = {}
local pe = { ui = {} }
function pe:GetSetting(key, default) if settings[key] ~= nil then return settings[key] end return default end
local chunk, err = loadfile(root .. "/../Tradewright_UI/src/ui/Tradewright_MarketUI.lua")
assert(chunk, err)
chunk("Tradewright_UI", pe)

-- Chart series: newest 48 points, table rows newest first
local points = {}
for i = 1, 50 do
	points[i] = { at = i, last = i * 10, min = (i % 2 == 0) and i or nil, qty = i }
end
points[50].last = nil
points[50].avg = 7
local series, recent = pe:BuildMarketChartSeries(points)
check("keeps the newest 48 hours", #series.primary == 48 and series.primary[1].at == 3 and series.primary[48].at == 50)
check("price falls back to average", series.primary[48].value == 7, series.primary[48].value)
check("minimum series skips hours without one", #series.secondary == 24, #series.secondary)
check("quantity per hour", series.quantity[1].value == 3)
check("table rows newest first with identity", recent[1].at == 50 and recent[1]._rowIdentity == 1 and recent[48].at == 3)
series, recent = pe:BuildMarketChartSeries({})
check("no history gives empty series", #series.primary == 0 and #recent == 0)
series = pe:BuildMarketChartSeries({ { at = 1 } })
check("hour without prices charts zero", series.primary[1].value == 0 and series.quantity[1].value == 0)

-- Sort
local key, asc = pe:GetMarketSort()
check("default sort by name ascending", key == "name" and asc == true)
settings["market.sortColumn"], settings["market.sortAsc"] = "price", false
key, asc = pe:GetMarketSort()
check("saved sort before the table exists", key == "price" and asc == false)
pe.ui.marketTable = { sortKey = "qty", sortAsc = true }
key, asc = pe:GetMarketSort()
check("table sort wins", key == "qty" and asc == true)
pe.ui.marketTable = { sortKey = "qty" }
key, asc = pe:GetMarketSort()
check("table without direction uses saved direction", key == "qty" and asc == false)

if failed > 0 then
	print(failed .. " market UI check(s) failed")
	os.exit(1)
end
print("All market UI checks passed")
