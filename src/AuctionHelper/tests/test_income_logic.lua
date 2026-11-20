-- Run with: lua5.1 tests/test_income_logic.lua (from AuctionHelper root)
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
local chunk, err = loadfile(root .. "/src/util/AuctionHelper_IncomeLogic.lua")
assert(chunk, err)
chunk("AuctionHelper", pe)
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
check("Days: day of a timestamp", IL.DayOf(86400 * 3 + 5) == 3)

if failed > 0 then
	print(failed .. " check(s) failed")
	os.exit(1)
end
print("All income logic checks passed")
