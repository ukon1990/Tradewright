-- Run with: lua5.1 tests/test_vendor_logic.lua (from Tradewright root)
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
local chunk, err = loadfile(root .. "/src/util/Tradewright_VendorLogic.lua")
assert(chunk, err)
chunk("Tradewright", pe)
local VL = pe.VendorLogic
assert(VL, "VendorLogic missing")

local FINE_THREAD, GRAY_DYE, UNKNOWN = 2321, 4340, 999999

-- What is remembered from a merchant
do
	local entries = VL.SellerEntries({
		{ itemID = 1, price = 100, stack = 1, available = -1 },
		{ itemID = 2, price = 100, stack = 5, available = -1 },
		{ itemID = 3, price = 100, stack = 1, available = 2 },
		{ itemID = 4, price = 100, stack = 1, available = -1, extendedCost = true },
		{ itemID = 5, price = 0, stack = 1, available = -1 },
	}, { zone = "Stormwind City", mapID = 84, x = 0.5, y = 0.6 }, 1000)
	check("Sellers: endless coin item kept", entries[1] and entries[1].price == 100 and entries[1].zone == "Stormwind City")
	check("Sellers: bundle price is per unit", entries[2] and entries[2].price == 20)
	check("Sellers: limited stock kept and marked", entries[3] and entries[3].limited == true and entries[1].limited == nil)
	check("Sellers: token cost skipped", entries[4] == nil)
	check("Sellers: free item skipped", entries[5] == nil)
	check("Sellers: place and time recorded", entries[1].mapID == 84 and entries[1].x == 0.5 and entries[1].seenAt == 1000)
	check("Sellers: no place given", VL.SellerEntries({ { itemID = 1, price = 10 } })[1].price == 10)
end

-- Lookup and where
do
	local listed = VL.Lookup(FINE_THREAD, nil)
	check("Lookup: built-in list", listed and listed.price == 100 and listed.exact == false and #listed.sellers == 0)
	check("Lookup: unknown item", VL.Lookup(UNKNOWN, nil) == nil)
	check("Where: kind when no seller visited", VL.Where(listed) == "tailoring and leatherworking suppliers")
	local seen = VL.Lookup(FINE_THREAD, {
		Zed = { price = 95, zone = "Orgrimmar" }, Abe = { price = 95, zone = "Thunder Bluff" }, Mo = { price = 100, zone = "" },
	})
	check("Lookup: seen price wins and is exact", seen.price == 95 and seen.exact == true)
	check("Lookup: cheapest first, then by name", seen.sellers[1].name == "Abe" and seen.sellers[2].name == "Zed" and seen.sellers[3].name == "Mo")
	check("Where: seller, zone and the rest", VL.Where(seen) == "Abe in Thunder Bluff and 2 more")
	local onlySeen = VL.Lookup(UNKNOWN, { Mo = { price = 7 } })
	check("Lookup: seen item outside the list", onlySeen.price == 7 and onlySeen.kind == nil)
	check("Where: seller without a zone", VL.Where(onlySeen) == "Mo")
	local databaseOnly = VL.Lookup(UNKNOWN, nil, { Ann = { zone = "Goldshire", mapID = 37, x = 0.1, y = 0.2 } })
	check("Directory: a database seller alone does not make an item a vendor item", databaseOnly == nil)
	local mixed = VL.Lookup(FINE_THREAD, { Zed = { price = 95 } }, { Ann = { mapID = 87 }, Zed = { mapID = 1 } })
	check("Directory: visited seller wins, priced first", #mixed.sellers == 2 and mixed.sellers[1].name == "Zed" and mixed.sellers[1].price == 95)
	check("Directory: price from the visited seller", mixed.price == 95 and mixed.exact == true)
	check("Limited: a vendor that holds only a few is no vendor source", VL.Lookup(UNKNOWN, { Abe = { price = 50, limited = true } }) == nil)
	local both = VL.Lookup(UNKNOWN, { Abe = { price = 50, limited = true }, Zed = { price = 80 } }, { Ann = { mapID = 1 } })
	check("Limited: left out beside a seller with endless stock", #both.sellers == 2 and both.sellers[1].name == "Zed" and both.price == 80)
	check("Directory: database sellers count once a visited vendor had endless stock", both.sellers[2].name == "Ann")
	local supply = VL.Lookup(FINE_THREAD, { Abe = { price = 90, limited = true } })
	check("Limited: a built-in supply keeps its usual price", supply.price == 100 and supply.exact == false and #supply.sellers == 0)
	local unvisited = VL.Lookup(FINE_THREAD, nil, { Ann = { mapID = 87, x = 0.1, y = 0.2 } })
	check("Directory: built-in price with a database seller", unvisited.price == 100 and unvisited.exact == false and #unvisited.sellers == 1)
end

-- Advice
do
	local info = VL.Lookup(GRAY_DYE, nil)
	check("Advice: vendor cheaper", VL.Advice(info, 400).cheaper == true)
	check("Advice: tie goes to the vendor", VL.Advice(info, 350).cheaper == true)
	check("Advice: auction cheaper", VL.Advice(info, 344).cheaper == false)
	check("Advice: no auction price", VL.Advice(info, nil).cheaper == true)
	check("Advice: price and exactness passed on", VL.Advice(info, 400).price == 350 and VL.Advice(info, 400).exact == false)
	check("Advice: no vendor", VL.Advice(nil, 400) == nil)
end

-- Nearest seller
do
	local sellers = {
		{ name = "Far", mapID = 84, x = 0.9, y = 0.9, seenAt = 5 },
		{ name = "Near", mapID = 84, x = 0.52, y = 0.5, seenAt = 1 },
		{ name = "Elsewhere", mapID = 85, x = 0.5, y = 0.5, seenAt = 9 },
		{ name = "Old", mapID = 86, x = 0.5, y = 0.5, seenAt = 2 },
		{ name = "Nowhere", seenAt = 99 },
	}
	local best, sameMap = VL.Nearest(sellers, { mapID = 84, x = 0.5, y = 0.5 })
	check("Nearest: closest on the same map", best.name == "Near" and sameMap == true)
	best, sameMap = VL.Nearest(sellers, { mapID = 1, x = 0.5, y = 0.5 })
	check("Nearest: other map, most recently seen", best.name == "Elsewhere" and sameMap == false)
	best = VL.Nearest(sellers, nil)
	check("Nearest: position unknown", best.name == "Elsewhere")
	check("Nearest: no seller with a position", VL.Nearest({ { name = "Nowhere" } }, nil) == nil)
	check("Nearest: empty", VL.Nearest(nil, nil) == nil)
	local spread = {
		{ name = "OtherContinent", mapID = 10, x = 0.5, y = 0.5, seenAt = 50, world = { continent = 0, x = 1, y = 1 } },
		{ name = "FarSameContinent", mapID = 11, x = 0.5, y = 0.5, world = { continent = 1, x = 900, y = 900 } },
		{ name = "NearSameContinent", mapID = 12, x = 0.5, y = 0.5, world = { continent = 1, x = 110, y = 100 } },
	}
	best, sameMap = VL.Nearest(spread, { mapID = 99, x = 0.5, y = 0.5, world = { continent = 1, x = 100, y = 100 } })
	check("Nearest: same continent by world distance", best.name == "NearSameContinent" and sameMap == false)
	best = VL.Nearest(spread, { mapID = 11, x = 0.4, y = 0.4, world = { continent = 1, x = 100, y = 100 } })
	check("Nearest: same map beats a closer one elsewhere", best.name == "FarSameContinent")
end

-- Buy plan
do
	local function list(purchases) return table.concat(purchases, ",") end
	local purchases, total = VL.BuyPlan(45, 1, 20)
	check("Buy: split by stack size", list(purchases) == "20,20,5" and total == 45)
	purchases, total = VL.BuyPlan(7, 5, 20)
	check("Buy: bundles rounded up", list(purchases) == "5,5" and total == 10)
	purchases, total = VL.BuyPlan(3, 1, nil)
	check("Buy: unknown stack size buys singly", list(purchases) == "1,1,1" and total == 3)
	purchases, total = VL.BuyPlan(0, 1, 20)
	check("Buy: nothing", #purchases == 0 and total == 0)
	purchases, total = VL.BuyPlan(1000, 1, 20, 3)
	check("Buy: purchase limit", #purchases == 3 and total == 60)
end

if failed > 0 then
	print(failed .. " vendor logic check(s) failed")
	os.exit(1)
end
print("All vendor logic checks passed")
