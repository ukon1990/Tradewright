-- Run with: lua5.1 tests/test_income_logic.lua (from Tradewright root)
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
local chunk, err = loadfile(root .. "/src/util/Tradewright_IncomeLogic.lua")
assert(chunk, err)
chunk("Tradewright", pe)
local IL = pe.IncomeLogic
assert(IL, "IncomeLogic missing")

-- Sources
local classify = IL.ClassifyMoneyChange
check("Source: nothing going on is other", classify({}, 100) == "other")
check("Source: merchant open is vendor", classify({ open = { merchant = true } }, 100) == "vendor")
check("Source: trade window is trade", classify({ open = { trade = true, merchant = true } }, 100) == "trade")
check("Source: trade gold landing just after the window closed", classify({ closedAt = { trade = 99.5 } }, 100) == "trade")
check("Source: a window closed long ago does not count", classify({ closedAt = { merchant = 50 } }, 100) == "other")
check("Source: auction house open is auction", classify({ open = { auctionHouse = true } }, 100) == "auction")
check("Source: mailbox open is mail", classify({ open = { mailbox = true } }, 100) == "mail")
check("Source: auction mail taken beats the mailbox", classify({ open = { mailbox = true }, at = { auctionMail = 99.5 } }, 100) == "auction")
check("Source: quest turned in just before", classify({ at = { quest = 98.5 } }, 100) == "quest")
check("Source: quest turned in just after (events out of order)", classify({ at = { quest = 101 } }, 100) == "quest")
check("Source: old quest turn-in does not count", classify({ at = { quest = 90 } }, 100) == "other")
check("Source: coin looted is loot", classify({ at = { loot = 100 } }, 100) == "loot")
check("Source: quest beats an open merchant", classify({ open = { merchant = true }, at = { quest = 100 } }, 100) == "quest")

-- Vendor sales merged per item and day
local day5 = 86400 * 5
local events = {
	{ kind = "vendor", itemID = 7, characterKey = "A", ts = day5 + 10, quantity = 2, totalCopper = 20 },
	{ kind = "sell", itemID = 7, characterKey = "A", ts = day5 + 20, quantity = 1, totalCopper = 99 },
}
local function vendorSale(itemID, characterKey, ts)
	return { kind = "vendor", itemID = itemID, characterKey = characterKey, ts = ts, quantity = 3, totalCopper = 30 }
end
check("Vendor: same item and day merges", IL.MergeIntoDayEvent(events, vendorSale(7, "A", day5 + 30), 50)
	and events[1].quantity == 5 and events[1].totalCopper == 50 and events[1].unitCopper == 10 and events[2].quantity == 1)
check("Vendor: another day does not merge", not IL.MergeIntoDayEvent(events, vendorSale(7, "A", day5 + 86400), 50))
check("Vendor: another character does not merge", not IL.MergeIntoDayEvent(events, vendorSale(7, "B", day5 + 30), 50))
check("Vendor: only the latest events are searched", not IL.MergeIntoDayEvent(events, vendorSale(7, "A", day5 + 30), 1))
check("Vendor: empty ledger", not IL.MergeIntoDayEvent({}, vendorSale(7, "A", day5), 50))

-- Per-day totals
local days = {}
IL.AddToDay(days, 10, "vendor", 500)
IL.AddToDay(days, 10, "vendor", -200)
IL.AddToDay(days, 10, "vendor", 100)
IL.AddToDay(days, 11, "quest", 0)
check("Days: gains and spends kept apart", days[10].vendor.gain == 600 and days[10].vendor.spend == 200)
check("Days: a zero change adds no day", days[11] == nil)
IL.AddToDay(days, 3, "loot", 5)
IL.PruneDays(days, 5)
check("Days: old days dropped", days[3] == nil and days[10] ~= nil)
local byItem = { [1] = { [2] = {} }, [2] = { [9] = {} } }
IL.PruneAllDays(byItem, 5)
check("Days: items left without days are dropped", byItem[1] == nil and byItem[2][9] ~= nil)
check("Days: day of a timestamp", IL.DayOf(86400 * 3 + 5) == 3)

-- Item chat lines
local patterns = {
	{ IL.FormatToPattern("You create: %sx%d."), "craft" },
	{ IL.FormatToPattern("You create: %s."), "craft" },
	{ IL.FormatToPattern("You receive loot: %sx%d."), "loot" },
	{ IL.FormatToPattern("You receive loot: %s."), "loot" },
}
local link = "|cffffffff|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|r"
local function parse(message)
	return { IL.ParseItemMessage(message, patterns) }
end
local r = parse("You create: " .. link .. "x5.")
check("Chat: crafted stack", r[1] == "craft" and r[2] == 2589 and r[3] == 5)
r = parse("You create: " .. link .. ".")
check("Chat: crafted single", r[1] == "craft" and r[2] == 2589 and r[3] == 1)
r = parse("You receive loot: " .. link .. "x2.")
check("Chat: looted stack", r[1] == "loot" and r[3] == 2)
check("Chat: someone else's loot is ignored", parse("Bob receives loot: " .. link .. ".")[1] == nil)
check("Chat: a line without an item link is ignored", parse("You receive loot: Gold.")[1] == nil)

-- Where sold items came from
local acquired = {}
IL.AddAcquired(acquired, 7, 10, "craft", 6)
IL.AddAcquired(acquired, 7, 11, "loot", 4)
IL.AddAcquired(acquired, 7, 30, "craft", 9)
IL.AddAcquired(acquired, 8, 10, "loot", 1)
local function at(day) return day * 86400 + 100 end
local ledger = {
	{ kind = "sell", itemID = 7, ts = at(12), quantity = 10 },
	{ kind = "sell", itemID = 7, ts = at(20), quantity = 3 },
	{ kind = "buy", itemID = 9, ts = at(5), quantity = 2 },
	{ kind = "sell", itemID = 9, ts = at(6), quantity = 2 },
	{ kind = "sell", itemID = 8, ts = at(9), quantity = 1 },
	{ kind = "sell", itemName = "Mystery", ts = at(9), quantity = 4 },
}
local labels = IL.LabelSaleOrigins(ledger, acquired)
check("Origin: 6 crafted and 4 looted split a sale of 10", labels[ledger[1]].crafted == 6 and labels[ledger[1]].farmed == 4)
check("Origin: crafts made after the sale do not count", labels[ledger[2]].unknown == 3 and labels[ledger[2]].crafted == nil)
check("Origin: bought then sold is resold", labels[ledger[4]].resold == 2)
check("Origin: looted after the sale does not count", labels[ledger[5]].unknown == 1)
check("Origin: a sale without an item id is unknown", labels[ledger[6]].unknown == 4)
check("Origin: buys are not labelled", labels[ledger[3]] == nil)
check("Origin: empty ledger", next(IL.LabelSaleOrigins({}, {})) == nil)

-- Income view
local income = {
	A = { [10] = { vendor = { gain = 100, spend = 40 }, quest = { gain = 300, spend = 0 } }, [3] = { loot = { gain = 999, spend = 0 } } },
	B = { [11] = { vendor = { gain = 50, spend = 0 } } },
}
local all = IL.SummarizeIncome(income, nil, 5)
check("Income: totals from the first day on", all.gain == 450 and all.spend == 40 and all.sources.loot == nil)
check("Income: one point per day, oldest first", #all.daily == 2 and all.daily[1].day == 10 and all.daily[1].gain == 400)
local onlyB = IL.SummarizeIncome(income, "B", 0)
check("Income: one character", onlyB.gain == 50 and onlyB.sources.quest == nil)
local sourceRows = IL.SourceRows(all, 10)
check("Income: sources, most gold in first", sourceRows[1].source == "quest" and sourceRows[2].source == "vendor"
	and sourceRows[2].net == 110 and math.abs(sourceRows[1].share - 300 / 450) < 1e-9 and sourceRows[1].perDay == 30)
check("Income: empty", #IL.SourceRows(IL.SummarizeIncome({}, nil, 0), 30) == 0)

local sales = {
	{ kind = "sell", itemID = 7, ts = at(12), quantity = 10, netCopper = 1000, characterKey = "A" },
	{ kind = "sell", itemID = 8, ts = at(12), quantity = 1, netCopper = 300, characterKey = "B" },
	{ kind = "expired", itemID = 7, ts = at(12), quantity = 1, characterKey = "A" },
	{ kind = "sell", itemID = 7, ts = at(1), quantity = 1, netCopper = 50, characterKey = "A" },
}
local split = IL.SplitSalesByOrigin(sales, { [sales[1]] = { crafted = 6, farmed = 4 }, [sales[2]] = { unknown = 1 } }, at(10), nil)
check("Split: sale gold shared by units", split.crafted == 600 and split.farmed == 400 and split.unknown == 300)
check("Split: one character", IL.SplitSalesByOrigin(sales, { [sales[2]] = { unknown = 1 } }, 0, "A").unknown == nil)
local function classOf(itemID)
	if itemID == 7 then return "7:1", "Trade Goods · Leather" end
	return nil
end
local types = IL.SummarizeItemTypes(sales, at(10), nil, classOf)
check("Types: most earned first, unknown type kept", types[1].label == "Trade Goods · Leather" and types[1].net == 1000
	and types[2].label == "Unknown type" and math.abs(types[1].share - 1000 / 1300) < 1e-9)
check("Types: sell rate from sales and misses", types[1].sellRate == 0.5 and types[2].sellRate == 1)
local noMisses = IL.SummarizeItemTypes({ sales[1] }, 0, nil, classOf)
check("Types: no sell rate before misses are tracked", noMisses[1].sellRate == nil and noMisses[1].items[7] == 1000)

-- Auction house mail
local returnSubjects = { { IL.FormatToPattern("Auction expired: %s"), "expired" }, { IL.FormatToPattern("Auction cancelled: %s"), "cancelled" } }
local soldMail = { invoiceType = "seller", itemName = "Iron Bar", buyer = "Bo", bid = 1000, consignment = 50, deposit = 12, count = 5,
	money = 962, ageSeconds = 3600 }
local soldEvent, soldBy = IL.AuctionMailEvent(soldMail, returnSubjects, 10000)
check("Mail: a sale is settled by its gold and records what the house kept", soldBy == "money" and soldEvent.kind == "sell"
	and soldEvent.netCopper == 950 and soldEvent.consignmentCopper == 50 and soldEvent.unitCopper == 200 and soldEvent.ts == 6400)
soldMail.money = 0
check("Mail: a sale whose gold is already taken writes nothing", IL.AuctionMailEvent(soldMail, returnSubjects, 10000) == nil)
local wonEvent, wonBy = IL.AuctionMailEvent({ invoiceType = "buyer", itemName = "Iron Bar", bid = 600,
	attachment = { name = "Iron Bar", itemID = 2772, count = 3 } }, returnSubjects, 10000)
check("Mail: a won auction is a buy at the price paid, settled by its item", wonBy == "item" and wonEvent.kind == "buy"
	and wonEvent.itemID == 2772 and wonEvent.quantity == 3 and wonEvent.unitCopper == 200)
check("Mail: a won auction whose item is already taken writes nothing",
	IL.AuctionMailEvent({ invoiceType = "buyer", itemName = "Iron Bar", bid = 600 }, returnSubjects, 10000) == nil)
local expiredEvent = IL.AuctionMailEvent({ subject = "Auction expired: Iron Bar", attachment = { name = "Iron Bar", itemID = 2772, count = 4 } },
	returnSubjects, 10000)
local cancelledEvent = IL.AuctionMailEvent({ subject = "Auction cancelled: Iron Bar", attachment = { name = "Iron Bar", itemID = 2772 } },
	returnSubjects, 10000)
check("Mail: expired and cancelled auctions come back as their own kinds", expiredEvent.kind == "expired" and expiredEvent.quantity == 4
	and cancelledEvent.kind == "cancelled" and cancelledEvent.quantity == 1)
check("Mail: a letter from a friend with an item is not an auction",
	IL.AuctionMailEvent({ subject = "For you", attachment = { name = "Iron Bar", itemID = 2772 } }, returnSubjects, 10000) == nil)

-- Per-item totals
local function ledgerEvent(kind, quantity, total, net, ts)
	return { kind = kind, itemID = 2772, quantity = quantity, totalCopper = total, netCopper = net, ts = ts }
end
local barEvents = {
	ledgerEvent("buy", 10, 1000, nil, 5), ledgerEvent("buy", 10, 3000, nil, 9),
	ledgerEvent("sell", 5, 2000, 1900, 6), ledgerEvent("sell", 5, 2000, 1900, 7), ledgerEvent("sell", 1, 400, 380, 8),
	ledgerEvent("sell", 1, 400, 380, 8), ledgerEvent("expired", 5, nil, nil, 9), { kind = "vendor", itemID = 2772, quantity = 1, totalCopper = 9 },
}
local bars = IL.TallyByItem(barEvents)[2772]
local bought = IL.PurchaseSummary(bars)
check("Purchases: units, average price and last buy", bought.units == 20 and bought.avgUnit == 200 and bought.lastAt == 9)
check("Purchases: nothing bought", IL.PurchaseSummary(IL.TallyByItem({ barEvents[3] })[2772]) == nil and IL.PurchaseSummary(nil) == nil)
check("Sale chance: 4 sales and 1 expiry is 80%", IL.SaleChance(bars) == 0.8)
check("Sale chance: unknown below the minimum postings", IL.SaleChance(IL.TallyByItem({ barEvents[3], barEvents[7] })[2772]) == nil
	and IL.SaleChance(nil) == nil)
local realized = IL.RealizedProfit(bars)
check("Realized profit: average sale after the cut less average buy", realized.units == 12 and realized.profitEach == 4560 / 12 - 200)
check("Realized profit: none without buys", IL.RealizedProfit(IL.TallyByItem({ barEvents[3] })[2772]) == nil)
local rolledOff = {}
IL.AddRolledOff(rolledOff, barEvents[1])
IL.AddRolledOff(rolledOff, barEvents[7])
local afterRollOff = IL.TallyByItem({ barEvents[2], barEvents[3], barEvents[4], barEvents[5], barEvents[6] }, rolledOff)[2772]
check("Roll-off: totals survive events leaving the ledger", IL.PurchaseSummary(afterRollOff).avgUnit == 200 and IL.SaleChance(afterRollOff) == 0.8)
local latest = IL.LatestEvents(barEvents, { buy = true, expired = true }, 6, 2)
check("Latest: chosen kinds since a time, newest first, capped", #latest == 2 and latest[1].ts == 9 and latest[2].ts == 9 and latest[1].kind ~= "sell")

-- Auction cut measured from sale mails
local function sale(total, kept) return { kind = "sell", totalCopper = total, consignmentCopper = kept } end
local mixedCuts = { sale(1000, 50), sale(1000, 50), sale(1000, 100), sale(2000, 100), sale(1000, 150) }
local measured = IL.MeasureAuctionCut(mixedCuts)
check("Cut: median share over mixed cuts", measured.cut == 0.05 and measured.sales == 5, measured.cut)
local tooFew = IL.MeasureAuctionCut({ sale(1000, 50), sale(1000, 50) })
check("Cut: not measured below the minimum, sales still counted", tooFew.cut == nil and tooFew.sales == 2)
local older = { sale(1000, nil), { kind = "sell", totalCopper = 0, consignmentCopper = 5 }, { kind = "vendor", totalCopper = 9, consignmentCopper = 1 } }
check("Cut: sales without the kept amount, empty sales and other kinds are skipped", IL.MeasureAuctionCut(older).sales == 0)
check("Cut: even count takes the middle two", IL.MeasureAuctionCut({ sale(100, 4), sale(100, 6) }, 2).cut == 0.05)

if failed > 0 then
	print(failed .. " check(s) failed")
	os.exit(1)
end
print("All income logic checks passed")
