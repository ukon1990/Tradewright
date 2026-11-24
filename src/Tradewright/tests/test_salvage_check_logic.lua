-- Run with: lua5.1 tests/test_salvage_check_logic.lua (from Tradewright root)
-- Whether salvage values are good enough to act on: each level and each reason.
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
local chunk, err = loadfile(root .. "/src/util/Tradewright_SalvageCheckLogic.lua")
assert(chunk, err)
chunk("Tradewright", pe)
local Check = pe.SalvageCheckLogic.Check

local DUST, ESSENCE, SHARD, VENDOR_ITEM = 10940, 10938, 10978, 999
local NOW, HOUR = 1000000, 3600

-- A counted yield giving mostly dust; `prices` maps an item to `{ priced, days }`, default priced with 14 days.
local function facts(overrides, prices)
	local f = {
		now = NOW, lastFullScanAt = NOW - HOUR,
		yields = { { basis = "own", perInput = { [DUST] = 1.5, [ESSENCE] = 0.4, [SHARD] = 0.05 } } },
		priceOf = function(itemID)
			local price = (prices or {})[itemID] or { true, 14 }
			return price[1], price[2]
		end,
	}
	for key, value in pairs(overrides or {}) do
		f[key] = value
	end
	return f
end

local function codes(result)
	local list = {}
	for _, reason in ipairs(result.reasons) do
		list[#list + 1] = reason.code .. (reason.itemID and (":" .. reason.itemID) or "")
	end
	return table.concat(list, ",")
end

-- Good data
do
	local result = Check(facts())
	check("Counted yields, priced materials and a fresh scan: good", result.level == "good" and #result.reasons == 0, codes(result))
	result = Check(facts({ yields = { { basis = "own", perInput = { [DUST] = 1, [VENDOR_ITEM] = 1 } } } },
		{ [VENDOR_ITEM] = { true, nil } }))
	check("A vendor price needs no history", result.level == "good")
end

-- Not enough
do
	local result = Check(facts({ lastFullScanAt = false }))
	check("No full scan: none", result.level == "none" and result.reasons[1].code == "no_full_scan", codes(result))
	result = Check(facts({ yields = {} }))
	check("No yields: none", result.level == "none" and codes(result) == "no_yields", codes(result))
	result = Check(facts({ lastFullScanAt = false, yields = {} }))
	check("No scan and no yields: both named, scan first", codes(result) == "no_full_scan,no_yields", codes(result))
	result = Check(facts({}, { [DUST] = { false } }))
	check("Most of what the yields give has no price: none", result.level == "none", codes(result))
	check("... and that material is named", result.reasons[1].code == "no_price" and result.reasons[1].itemID == DUST, codes(result))
end

-- Weak
do
	local result = Check(facts({}, { [SHARD] = { false } }))
	check("A material with no price but a small share only weakens", result.level == "weak"
		and codes(result) == "no_price:" .. SHARD, codes(result))
	result = Check(facts({}, { [ESSENCE] = { true, 2 } }))
	check("Too few days of prices: weak, with the days", result.level == "weak"
		and result.reasons[1].code == "few_price_days" and result.reasons[1].days == 2, codes(result))
	result = Check(facts({ lastFullScanAt = NOW - 30 * HOUR }))
	check("A scan older than a day: weak, with its age", result.level == "weak"
		and result.reasons[1].code == "old_scan" and result.reasons[1].hours == 30, codes(result))
	result = Check(facts({ yields = {
		{ basis = "researched", perInput = { [DUST] = 1 } }, { basis = "own", perInput = { [DUST] = 1 } },
	} }))
	local reason = result.reasons[1]
	check("Researched yields alone stay good, and are named, counted out of all", result.level == "good"
		and reason.code == "estimated_yields" and reason.count == 1 and reason.total == 2, codes(result))
	result = Check(facts({ yields = { { basis = "researched", perInput = { [DUST] = 1 } } } }, { [DUST] = { true, 2 } }))
	check("Researched yields with another reason: weak", result.level == "weak", codes(result))
end

-- Order of the reasons
do
	local result = Check(facts({ lastFullScanAt = NOW - 30 * HOUR, yields = {
		{ basis = "researched", perInput = { [DUST] = 1.5, [ESSENCE] = 0.4, [SHARD] = 0.05 } },
	} }, { [SHARD] = { false }, [ESSENCE] = { true, 3 } }))
	check("Scan age, then materials by share, then estimates", codes(result)
		== "old_scan,few_price_days:" .. ESSENCE .. ",no_price:" .. SHARD .. ",estimated_yields", codes(result))
end

-- Facts for the stat tiles
do
	local result = Check(facts({ lastFullScanAt = NOW - 3 * HOUR, yields = {
		{ basis = "researched", kind = "a", perInput = { [DUST] = 1.5, [SHARD] = 0.5 } },
		{ basis = "researched", kind = "a", perInput = { [DUST] = 1.5, [SHARD] = 0.5 } },
		{ basis = "own", kind = "b", perInput = { [DUST] = 1 } },
	} }, { [SHARD] = { true, 2 } }))
	check("The scan's age in hours", result.scanHours == 3)
	check("Every material, largest share first, with whether its price is usual",
		result.materials[1].itemID == DUST and result.materials[1].usual and result.materials[2].itemID == SHARD
		and not result.materials[2].usual and result.materials[2].days == 2)
	check("Kinds of input, and those resting on counted outcomes", result.kinds.total == 2 and result.kinds.counted == 1)
	result = Check(facts({ lastFullScanAt = false, yields = {} }))
	check("No scan and no yields: no age, no materials, no kinds", result.scanHours == nil and #result.materials == 0
		and result.kinds.total == 0)
end

if failed > 0 then
	print(failed .. " salvage check test(s) failed")
	os.exit(1)
end
print("All salvage check tests passed")
