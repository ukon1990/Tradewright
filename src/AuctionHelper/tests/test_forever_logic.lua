-- Run with: lua5.1 tests/test_forever_logic.lua (from AuctionHelper root)
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

-- Minimal addon table so ForeverLogic can attach.
local pe = {}
_G.AuctionHelper = pe
_G.ProfessionExporter = pe

local chunk, err = loadfile(root .. "/src/util/AuctionHelper_ForeverLogic.lua")
assert(chunk, err)
chunk("AuctionHelper", pe)

local FL = pe.ForeverLogic
assert(FL, "ForeverLogic missing")

-- Client flags
local forever = FL.DetectClientFlags(16001, 1, 1)
check("Forever on 16001+mainline project", forever.IS_FOREVER == true and forever.IS_RETAIL == false and forever.IS_SUPPORTED == true)

local retail = FL.DetectClientFlags(120001, 1, 1)
check("Retail on 120001+mainline", retail.IS_FOREVER == false and retail.IS_RETAIL == true and retail.IS_SUPPORTED == true)

local classicProj = FL.DetectClientFlags(11507, 2, 1)
check("Classic project unsupported", classicProj.IS_SUPPORTED == false)

local bandLo = FL.DetectClientFlags(16000, 1, 1)
local bandHi = FL.DetectClientFlags(16999, 1, 1)
local bandOut = FL.DetectClientFlags(17000, 1, 1)
check("Forever band includes 16000", bandLo.IS_FOREVER == true)
check("Forever band includes 16999", bandHi.IS_FOREVER == true)
check("Forever band excludes 17000", bandOut.IS_FOREVER == false)

-- Classic AH aggregate
local agg = {}
FL.AggregateClassicAuctionRow(agg, 2589, 5, 100) -- 20c/unit
FL.AggregateClassicAuctionRow(agg, 2589, 2, 30) -- 15c/unit lower
check("Aggregate min marketLow", agg[2589] and agg[2589].marketLow == 15)
check("Aggregate max marketHigh", agg[2589] and agg[2589].marketHigh == 20)
check("Aggregate sampleSize", agg[2589] and agg[2589].sampleSize == 7)
check("Aggregate listingCount", agg[2589] and agg[2589].listingCount == 2)
check("Aggregate ignores nil item", next(FL.AggregateClassicAuctionRow({}, nil, 1, 10)) == nil)
check("Aggregate ignores zero buyout sample but keeps item", (function()
	local a = {}
	FL.AggregateClassicAuctionRow(a, 123, 3, 0)
	return a[123] and a[123].sampleSize == 0 and a[123].marketLow == nil and a[123].listingCount == 0
end)())

-- Market browser helpers
check("Parse storage key commodity", FL.ParseItemIDFromStorageKey("EU:2589") == 2589)
check("Parse storage key item", FL.ParseItemIDFromStorageKey("EU:1:2589") == 2589)
check("Parse storage key bad", FL.ParseItemIDFromStorageKey("nope") == nil)
check("Parse storage key item with key fields", FL.ParseItemIDFromStorageKey("3:1084:2589:0:0:0") == 2589)
check("Parse storage key from table address is nil", FL.ParseItemIDFromStorageKey("3:1084:table: 000001F2A3B4C510") == nil)
check("Serialize table item key", FL.SerializeItemKey({ itemID = 2589, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }) == "2589")
check("Serialize table item key with level", FL.SerializeItemKey({ itemID = 19019, itemLevel = 71, itemSuffix = 0, battlePetSpeciesID = 0 }) == "19019:71:0:0")
check("Serialize plain item key", FL.SerializeItemKey(nil, 2589) == "2589")
do
	local broken = "3:1084:table: 000001F2A3B4C510"
	local orphan = "3:1084:table: 00000000DEADBE10"
	local auction = {
		snapshot = { items = { [broken] = { p = 50, t = 10 }, [orphan] = { p = 1, t = 1 } } },
		history = { hourly = { [broken] = { ["3600"] = { l = 50 } } } },
		indexes = { byItemID = { ["2589"] = { [broken] = true } } },
	}
	local moved = FL.RepairAuctionStorageKeys(auction, function(id) return "3:1084:" .. id end)
	check("Repair moves broken snapshot entry", moved == 1 and auction.snapshot.items["3:1084:2589"] and auction.snapshot.items["3:1084:2589"].p == 50)
	check("Repair moves history and index", auction.history.hourly["3:1084:2589"] ~= nil and auction.indexes.byItemID["2589"]["3:1084:2589"] == true)
	check("Repair drops untraceable entries", auction.snapshot.items[broken] == nil and auction.snapshot.items[orphan] == nil)
end

local fields = FL.NormalizeMarketSnapshotFields({ p = 150, q = 10, n = 3, h = 200, t = 1000, s = "classic_full" })
check("Normalize compact snapshot", fields and fields.price == 150 and fields.listingCount == 3 and fields.marketHigh == 200)

local rows = FL.BuildMarketBrowserRows(
	{ ["EU:2589"] = { p = 15, q = 7, n = 2, h = 20, t = 50, s = "classic_full" } },
	{ ["EU:1:2592"] = { p = 40, q = 1, n = 1, h = 40, t = 60, s = "classic_full" } },
	{
		query = "wool",
		sortKey = "name",
		sortAsc = true,
		resolveName = function(id)
			if id == 2589 then return "Linen Cloth" end
			if id == 2592 then return "Wool Cloth" end
			return "#" .. tostring(id)
		end,
	}
)
check("Market filter by name", #rows == 1 and rows[1].itemID == 2592)
local byPrice = FL.BuildMarketBrowserRows(
	nil,
	{
		["EU:1:1"] = { p = 100, q = 1, t = 1, s = "x" },
		["EU:1:2"] = { p = 50, q = 1, t = 1, s = "x" },
	},
	{ sortKey = "price", resolveName = function(id) return "Item" .. tostring(id) end }
)
check("Market sort price desc default", #byPrice == 2 and byPrice[1].price == 100 and byPrice[2].price == 50)

do
	local info = {
		[2589] = { classLabel = "Trade Goods", subclassLabel = "Cloth", quality = 1 },
		[2592] = { classLabel = "Trade Goods", subclassLabel = "Cloth", quality = 1 },
		[118] = { classLabel = "Consumable", subclassLabel = "Potion", quality = nil },
	}
	local marketRows = {
		{ itemID = 2589, price = 15 },
		{ itemID = 2592, price = 400 },
		{ itemID = 118, price = 30 },
	}
	local getInfo = function(id) return info[id] end
	check("Market filter class", #FL.FilterMarketRows(marketRows, { classes = { ["Trade Goods"] = true } }, getInfo) == 2)
	check("Market filter subclass", #FL.FilterMarketRows(marketRows, { subclasses = { Potion = true } }, getInfo) == 1)
	check("Market filter quality hides unknown", #FL.FilterMarketRows(marketRows, { qualities = { [1] = true } }, getInfo) == 2)
	check("Market filter owned", #FL.FilterMarketRows(marketRows, { ownedOnly = true, owned = { [118] = true } }, getInfo) == 1)
	local priced = FL.FilterMarketRows(marketRows, { minPrice = 20, maxPrice = 100 }, getInfo)
	check("Market filter price range", #priced == 1 and priced[1].itemID == 118)
	check("Market filter none", #FL.FilterMarketRows(marketRows, {}, getInfo) == 3)
end

local hist = FL.BuildMarketHistorySeries({
	["3600"] = { m = 10, x = 20, l = 15, n = 2, q = 5, w = 75, t = 3600 },
	["7200"] = { m = 12, x = 18, l = 16, n = 1, q = 2, w = 32, t = 7200 },
})
check("History series sorted", #hist == 2 and hist[1].at == 3600 and hist[2].last == 16)
check("History series avg", hist[1].avg == 15)

-- Location counts
local bags, bank, warband, total = FL.ResolveLocationCounts(5, 8, nil)
check("No warband → warband 0", bags == 5 and bank == 3 and warband == 0 and total == 8)
bags, bank, warband, total = FL.ResolveLocationCounts(5, 8, 12)
check("With warband split", bags == 5 and bank == 3 and warband == 7 and total == 15)

-- Classic reagent slot
local slot = FL.MakeClassicReagentSlot(1, 2589, 2)
check("Reagent slot shape", slot and slot.quantityRequired == 2 and slot.reagents[1].itemID == 2589)
check("Reagent slot rejects bad", FL.MakeClassicReagentSlot(1, 0, 2) == nil)

-- Lua export
local payload, perr = FL.BuildPlainLuaExportPayload({ meta = { scope = "character" }, n = 1 })
check("AHLUA1 prefix", type(payload) == "string" and payload:sub(1, 7) == "AHLUA1:" and not perr)
local body = payload:match("^AHLUA1:(.+)$")
local loaded = assert(loadstring(body))()
check("AHLUA1 roundtrip scope", loaded.meta.scope == "character" and loaded.n == 1)

local bad, badErr = FL.BuildPlainLuaExportPayload("nope")
check("AHLUA1 rejects non-table", bad == nil and type(badErr) == "string")

-- Market insights: hourly summary, deal and mover flags, top N
do
	local now = 1000 * 3600
	local hourly = {
		[tostring(now - 3600)] = { n = 2, q = 40, w = 4000, l = 100, m = 90, x = 110 }, -- avg 100, qty 20
		[tostring(now - 2 * 3600)] = { n = 1, q = 10, w = 2000, l = 200, m = 200, x = 200 }, -- avg 200, qty 10
		[tostring(now - 48 * 3600)] = { n = 1, q = 30, w = 9000, l = 300, m = 300, x = 300 }, -- avg 300, qty 30
		[tostring(now - 8 * 24 * 3600)] = { n = 1, q = 1, w = 99999, l = 99999 }, -- outside 7 days
	}
	local s = FL.SummarizeHourlyHistory(hourly, now)
	check("Summary hours in 7 days", s.hours == 3)
	check("Summary 7-day average", s.avg7d == 200)
	check("Summary 24-hour average", s.avg24h == 150)
	check("Summary latest price and qty", s.lastPrice == 100 and s.qtyNow == 20)
	check("Summary range", s.low7d == 90 and s.high7d == 300)
	check("Summary average qty", s.qtyAvg7d == 20)
	check("Summary empty", FL.SummarizeHourlyHistory(nil, now).hours == 0)

	local deal = FL.ClassifyMarketItem(100, s, s.avg7d, { dealThreshold = 0.3 })
	check("Deal at 50% below average", deal.isDeal == true and deal.discount == 0.5)
	check("Deal gain after cut", deal.gain == 200 * 0.95 - 100)
	check("Faller at 50% below average", deal.isFaller == true and deal.isRiser == false)
	check("Supply unchanged", deal.supplyChange == 0)
	check("No deal at 10% below", FL.ClassifyMarketItem(180, s, 200).isDeal == false)
	check("Riser above threshold", FL.ClassifyMarketItem(260, s, 200).isRiser == true)
	local thin = FL.ClassifyMarketItem(100, { hours = 1, avg7d = 200 }, 200)
	check("Thin history: no own deal", thin.isDeal == nil and thin.change == nil)
	check("Thin history: external ref still deals", FL.ClassifyMarketItem(100, { hours = 0 }, 200, { refExternal = true }).isDeal == true)

	local top = FL.TopN({ { v = 3 }, { v = 9 }, {}, { v = 5 } }, 2, "v")
	check("TopN largest first, skips missing", #top == 2 and top[1].v == 9 and top[2].v == 5)
	check("TopN ascending", FL.TopN({ { v = 3 }, { v = 1 } }, 1, "v", true)[1].v == 1)
end

-- Classic sell inject gate (retail keeps SetItemByLocation-only when API exists)
check("Classic sell: Forever with SetItemByLocation", FL.ShouldUseClassicSellInject(true, true) == true)
check("Classic sell: Forever without SetItemByLocation", FL.ShouldUseClassicSellInject(true, false) == true)
check("Classic sell: retail with SetItemByLocation blocked", FL.ShouldUseClassicSellInject(false, true) == false)
check("Classic sell: non-Forever without API allowed", FL.ShouldUseClassicSellInject(false, false) == true)

-- TOC sniff (Forever load markers)
local toc = assert(io.open(root .. "/AuctionHelper.toc", "r")):read("*a")
check("TOC Interface 16001", toc:find("Interface: 16001", 1, true) ~= nil)
check("TOC camelot", toc:find("AllowLoadGameType: camelot", 1, true) ~= nil)
check("TOC ForeverLogic listed", toc:find("AuctionHelper_ForeverLogic.lua", 1, true) ~= nil)
check("TOC Blizzard_Professions optional", toc:find("OptionalDeps: Blizzard_Professions", 1, true) ~= nil)

if failed > 0 then
	print(string.format("%d failure(s)", failed))
	os.exit(1)
end
print("All forever logic checks passed")
