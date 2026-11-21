-- Run with: lua5.1 tests/test_chart_logic.lua (from AuctionHelper root)
-- Axis steps, scales, bounds and hover targets of the time-series chart.
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
local chunk, err = loadfile(root .. "/src/util/AuctionHelper_ChartLogic.lua")
assert(chunk, err)
chunk("AuctionHelper", pe)
local CL = pe.ChartLogic
assert(CL, "ChartLogic missing")

local function near(a, b)
	return type(a) == "number" and math.abs(a - b) < 1e-9
end

local function joined(list)
	local out = {}
	for i, v in ipairs(list) do
		out[i] = string.format("%.10g", v)
	end
	return table.concat(out, ",")
end

-- NiceStep: 1, 2 or 5 times a power of ten
for _, case in ipairs({
	{ 100, 3, 50 }, { 250, 3, 100 }, { 999, 3, 500 }, { 1500, 4, 500 }, { 3, 3, 1 }, { 12, 3, 5 },
	{ 45, 3, 20 }, { 0.3, 3, 0.1 }, { 1, 1, 1 },
}) do
	local got = CL.NiceStep(case[1], case[2])
	check(string.format("NiceStep(%s, %s) = %s", case[1], case[2], case[3]), near(got, case[3]), got)
end
check("NiceStep: zero range is 1", CL.NiceStep(0, 3) == 1)
check("NiceStep: negative range is 1", CL.NiceStep(-5, 3) == 1)
check("NiceStep: zero count counts as one step", CL.NiceStep(7, 0) == 10)

-- NiceScale: low, high, step
local function scale(name, args, low, high, step)
	local gotLow, gotHigh, gotStep = CL.NiceScale(args[1], args[2], args[3], args[4])
	check("NiceScale: " .. name, near(gotLow, low) and near(gotHigh, high) and near(gotStep, step),
		string.format("%s %s %s", tostring(gotLow), tostring(gotHigh), tostring(gotStep)))
end
scale("0..100", { 0, 100, 3, true }, 0, 100, 50)
scale("rounds out to whole steps", { 37, 412, 3, true }, 0, 600, 200)
scale("same without floor", { 37, 412, 3, false }, 0, 600, 200)
scale("negative minimum is not floored", { -20, 130, 3, true }, -50, 150, 50)
scale("flat value widened by one", { 5, 5, 3, true }, 4, 6, 1)
scale("flat zero widens below zero", { 0, 0, 3, true }, -1, 1, 1)
scale("flat fraction widens below zero", { 0.5, 0.5, 3, true }, -1, 2, 1)
scale("flat negative", { -5, -5, 3, true }, -6, -4, 1)
scale("narrow band far from zero", { 1200, 1260, 3, true }, 1200, 1260, 20)
scale("0..1", { 0, 1, 3, true }, 0, 1, 0.5)

-- TickValues
check("TickValues: inclusive of high", joined(CL.TickValues(0, 100, 50)) == "0,50,100")
check("TickValues: narrow band", joined(CL.TickValues(1200, 1260, 20)) == "1200,1220,1240,1260")
check("TickValues: float steps reach high", joined(CL.TickValues(0, 0.3, 0.1)) == "0,0.1,0.2,0.3", joined(CL.TickValues(0, 0.3, 0.1)))
check("TickValues: at most 12", #CL.TickValues(0, 100, 1) == 12)

-- ExpandRange
local function range(...)
	return table.concat({ tostring(select(1, ...)), tostring(select(2, ...)), tostring(select(3, ...)), tostring(select(4, ...)) }, " ")
end
check("ExpandRange: skips points without numbers",
	range(CL.ExpandRange({ { at = 5, value = 3 }, { at = 2, value = 9 }, { at = "x", value = 1 }, { at = 7 } })) == "2 5 3 9")
check("ExpandRange: grows a given range", range(CL.ExpandRange({ { at = 1, value = 4 } }, 3, 4, 5, 6)) == "1 4 4 6")
check("ExpandRange: nil points keep the range", range(CL.ExpandRange(nil, 1, 2, 3, 4)) == "1 2 3 4")
check("ExpandRange: no points give nil", range(CL.ExpandRange({})) == "nil nil nil nil")
check("ExpandRange: text numbers count", range(CL.ExpandRange({ { at = "10", value = "2" } })) == "10 10 2 2")

-- Bounds
local primary = { { at = 1000, value = 50 }, { at = 2000, value = 80 } }
local secondary = { { at = 1500, value = 20 } }
local quantity = { { at = 500, value = 7 }, { at = 2500, value = 3 } }
local b = CL.Bounds(primary, secondary, quantity)
check("Bounds: time spans all series", b.minT == 500 and b.maxT == 2500)
check("Bounds: values span the price lines only", b.minV == 20 and b.maxV == 80)
check("Bounds: largest quantity", b.maxQ == 7)
local single = CL.Bounds({ { at = 1000, value = 5 } }, {}, {})
check("Bounds: one instant widened by an hour each way", single.minT == 1000 - 3600 and single.maxT == 1000 + 3600)
check("Bounds: no quantity gives nil maxQ", single.maxQ == nil)
local none = CL.Bounds({}, {}, {})
check("Bounds: no points give nil values", none.minT == nil and none.minV == nil)
local qtyOnly = CL.Bounds({}, {}, quantity)
check("Bounds: quantity alone sets time but not values", qtyOnly.minT == 500 and qtyOnly.minV == nil)

-- Scales
local box = { left = 58, bottom = 20, width = 300, height = 100 }
local s = CL.Scales(b, box, 3, true)
check("Scales: value axis", s.low == 20 and s.high == 80 and s.step == 20)
check("Scales: quantity axis top", s.qHigh == 10, s.qHigh)
check("Scales: x at start and end", near(s.xAt(500), 58) and near(s.xAt(2500), 358))
check("Scales: x in the middle", near(s.xAt(1500), 208))
check("Scales: y at low and high", near(s.yAt(20), 20) and near(s.yAt(80), 120))
check("Scales: y for a value", near(s.yAt(65), 95))
check("Scales: quantity y", near(s.yAtQ(10), 120) and near(s.yAtQ(0), 20))
local noQty = CL.Scales(b, box, 3, false)
check("Scales: without quantity the quantity top is 1", noQty.qHigh == 1)
local tiny = CL.Scales(CL.Bounds({ { at = 1, value = 1 } }, {}, { { at = 1, value = 0 } }), box, 3, true)
check("Scales: quantity axis is at least 0..1", tiny.qHigh == 1, tiny.qHigh)

-- Average
check("Average: mean of values", CL.Average(primary) == 65)
check("Average: one point", CL.Average({ { value = 7 } }) == 7)
check("Average: no points", CL.Average({}) == nil)

-- HitTargets
local targets = CL.HitTargets(s, primary, secondary, quantity)
check("HitTargets: one per point", #targets == 5)
check("HitTargets: primary first with pixel position",
	targets[1].kind == "primary" and targets[1].pt == primary[1] and near(targets[1].x, 133) and near(targets[1].y, 70))
check("HitTargets: secondary after primary", targets[3].kind == "secondary" and near(targets[3].y, 20))
check("HitTargets: quantity uses the right axis", targets[4].kind == "quantity" and near(targets[4].y, 90))

if failed > 0 then
	print(failed .. " test(s) failed")
	os.exit(1)
end
print("All chart logic tests passed")
