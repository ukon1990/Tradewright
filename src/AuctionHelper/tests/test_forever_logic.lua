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
