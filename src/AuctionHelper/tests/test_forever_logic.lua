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

-- Classic sell inject gate (retail keeps the modern sell frame when it exists)
check("Classic sell: Forever with modern sell frame", FL.ShouldUseClassicSellInject(true, true) == true)
check("Classic sell: Forever without modern sell frame", FL.ShouldUseClassicSellInject(true, false) == true)
check("Classic sell: retail with modern sell frame blocked", FL.ShouldUseClassicSellInject(false, true) == false)
check("Classic sell: non-Forever without API allowed", FL.ShouldUseClassicSellInject(false, false) == true)

-- Own auctions: sold = incoming total, listed = unit price x quantity, undercut vs lowest scan
do
	local rows, totals = FL.SummarizeOwnedAuctions({
		{ itemID = 1, quantity = 13, sold = true, buyout = 1300 },
		{ auctionID = 77, itemID = 2, quantity = 7, buyout = 289 },
		{ itemID = 3, quantity = 1, buyout = 620 },
		{ itemID = 4, quantity = 2, bid = 100 },
	}, { [2] = 250, [3] = 620 }, 0.05)
	check("Owned auctions: sold total", totals.soldValue == 1300 and totals.soldCount == 1)
	check("Owned auctions: listed total", totals.listedValue == 7 * 289 + 620 + 200 and totals.listedCount == 3)
	check("Owned auctions: undercut count", totals.undercutCount == 1)
	check("Owned auctions: cheaper scan is undercut", rows[2].undercut == true and rows[2].value == 2023)
	check("Owned auctions: undercut amount and auction id", rows[2].undercutBy == 39 and math.floor(rows[2].undercutPct) == 13 and rows[2].auctionID == 77)
	check("Owned auctions: after-cut payout now and if reposted", rows[2].net == 1921 and rows[2].repostNet == 1662 and rows[3].repostNet == nil)
	check("Owned auctions: listed total after cut", totals.listedNet == 1921 + 589 + 190)
	local withDeposit = FL.SummarizeOwnedAuctions({ { itemID = 2, quantity = 7, buyout = 289, deposit = 2000 } }, { [2] = 250 }, 0.05)
	check("Owned auctions: deposit comes off the repost payout", withDeposit[1].repostNet == 1662 - 2000 and withDeposit[1].net == 1921)
	check("Owned auctions: equal price is not undercut", rows[3].undercut == false and rows[3].undercutBy == nil)
	check("Owned auctions: unscanned stays unknown", rows[4].undercut == nil and rows[4].unitPrice == 100)
	check("Owned auctions: sold has no unit price", rows[1].unitPrice == nil and rows[1].value == 1300)
end

-- Sales ledger statistics
do
	local day = 86400
	local now = 100 * day + 1000
	local events = {
		{ kind = "sell", ts = now - 40 * day, itemID = 1, itemName = "Old", quantity = 1, totalCopper = 500, netCopper = 475 },
		{ kind = "sell", ts = now - 3 * day, itemID = 2, itemName = "Flesh", quantity = 7, totalCopper = 2100, netCopper = 1995 },
		{ kind = "sell", ts = now - 1 * day, itemID = 2, itemName = "Flesh", quantity = 3, totalCopper = 900, netCopper = 855 },
		{ kind = "sell", ts = now - 1 * day + 60, itemName = "Unknown gem", quantity = 1, totalCopper = 1000 },
		{ kind = "buy", ts = now - 1 * day, itemID = 2, quantity = 5, totalCopper = 100 },
	}
	local week = FL.SummarizeSales(events, now, 7)
	check("Sales: period filters old sales and non-sales", week.totals.sales == 3 and week.totals.units == 11)
	check("Sales: net falls back to gross", week.totals.net == 1995 + 855 + 1000 and week.totals.gross == 4000)
	check("Sales: grouped per item, by name without an id", #week.items == 2 and week.items[1].sales == 2 and week.items[2].name == "Unknown gem")
	check("Sales: average unit price and weekly frequency", week.items[1].avgUnit == 300 and week.items[1].perWeek == 2)
	check("Sales: one point per day, oldest first", #week.daily == 2 and week.daily[1].value == 1995 and week.daily[2].value == 1855)
	check("Sales: recent is newest first", week.recent[1].itemName == "Unknown gem" and #week.recent == 3)
	local all = FL.SummarizeSales(events, now, nil)
	check("Sales: all time spans back to the first sale", all.totals.sales == 4 and all.spanDays == 40)
	check("Sales: empty ledger", FL.SummarizeSales({}, now, 30).totals.sales == 0)
end

-- Auction house / bank character per realm
do
	local sellers = { Stormrage = "Banker-Stormrage", Draenor = "", Azralon = "Gone-Azralon" }
	local known = { ["Banker-Stormrage"] = true, ["Smith-Stormrage"] = true, ["Alt-Draenor"] = true }
	check("Seller: chosen character on this realm", FL.ResolveSellerCharacter(sellers, "Stormrage", known) == "Banker-Stormrage")
	check("Seller: none chosen", FL.ResolveSellerCharacter(sellers, "Draenor", known) == nil)
	check("Seller: realm without a choice", FL.ResolveSellerCharacter(sellers, "Ragnaros", known) == nil)
	check("Seller: unknown character resolves to none", FL.ResolveSellerCharacter(sellers, "Azralon", known) == nil)
	check("Seller: no settings table", FL.ResolveSellerCharacter(nil, "Stormrage", known) == nil)
end

-- Materials mail plan: complete sets, partial sets, shared stock
do
	local function alloc(key, quantity) return { characterKey = key, mailQuantity = quantity } end
	local plan = FL.BuildMailPlan({
		{ itemID = 1, name = "Ore", allocations = { alloc("Amy-R", 6), alloc("Bob-R", 6) } },
		{ itemID = 2, name = "Flux", allocations = { alloc("Amy-R", 2) } },
		{ itemID = 3, name = "Gem", allocations = { alloc("Cid-R", 1) } },
	}, { [1] = 10, [2] = 2 })
	check("Mail plan: destinations with items only, sorted", #plan == 2 and plan[1].characterKey == "Amy-R" and plan[2].mailName == "Bob")
	check("Mail plan: complete set", plan[1].complete == true and plan[1].totalQuantity == 8 and #plan[1].missing == 0)
	check("Mail plan: shared material runs out for the later crafter", plan[2].complete == false and plan[2].items[1].quantity == 4
		and plan[2].missing[1].quantity == 2)
	check("Mail plan: empty", #FL.BuildMailPlan({}, {}) == 0 and #FL.BuildMailPlan(nil, nil) == 0)
end

-- Crafted items going back to the seller
do
	local bags = { [10] = { quantity = 3, name = "Potion" }, [11] = { quantity = 9, name = "Elixir" } }
	local plan = FL.BuildReturnToSellerPlan({ [10] = 5, [11] = 4, [12] = 2 }, bags, "Banker-R")
	check("Return crafts: one destination for the seller", #plan == 1 and plan[1].characterKey == "Banker-R" and plan[1].mailName == "Banker"
		and plan[1].kind == "crafts")
	check("Return crafts: clamped to the bags, gone items dropped", #plan[1].items == 2 and plan[1].items[1].name == "Elixir"
		and plan[1].items[1].quantity == 4 and plan[1].items[2].quantity == 3 and plan[1].totalQuantity == 7)
	check("Return crafts: no seller", #FL.BuildReturnToSellerPlan({ [10] = 5 }, bags, nil) == 0)
	check("Return crafts: nothing owed or nothing in the bags", #FL.BuildReturnToSellerPlan({}, bags, "Banker-R") == 0
		and #FL.BuildReturnToSellerPlan({ [12] = 2 }, bags, "Banker-R") == 0)
end

-- Surplus above keep amounts
do
	local function bag(name, quantity, quality, sellable) return { name = name, quantity = quantity, quality = quality, sellable = sellable } end
	local bags = {
		[1] = bag("Ore", 100, 1, true), [2] = bag("Herb", 15, 1, true), [3] = bag("Cloth", 40, 1, true),
		[4] = bag("Junk", 9, 0, true), [5] = bag("Bound", 3, 2, false), [6] = bag("Flux", 30, 1, true), [7] = bag("Bar", 10, 1, true),
	}
	local keep = { [1] = 20, [2] = 50, [6] = 5 }
	local held = { [3] = 10, [6] = 10, [7] = 25 }
	local function quantities(items)
		local out = {}
		for _, item in ipairs(items) do out[item.itemID] = item.quantity end
		return out
	end
	local off = quantities(FL.BuildSurplusPlan(bags, keep, held, false))
	check("Surplus: keep amount below stock sends the rest", off[1] == 80)
	check("Surplus: keep amount above stock sends nothing", off[2] == nil)
	check("Surplus: toggle off leaves items without a keep amount", off[3] == nil and off[7] == nil)
	check("Surplus: keep amount and queued need both held back", off[6] == 15)
	local on = quantities(FL.BuildSurplusPlan(bags, keep, held, true))
	check("Surplus: toggle on sends other items above what is held", on[3] == 30 and on[1] == 80)
	check("Surplus: queued need larger than stock sends nothing", on[7] == nil)
	check("Surplus: poor quality and unsellable never go", on[4] == nil and on[5] == nil)
	local sorted = FL.BuildSurplusPlan(bags, keep, held, true)
	check("Surplus: sorted by name", sorted[1].name == "Cloth" and sorted[#sorted].name == "Ore")
	check("Surplus: nothing configured", #FL.BuildSurplusPlan(bags, {}, {}, false) == 0)
end

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
