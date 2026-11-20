-- Run with: lua5.1 tests/test_mail_logic.lua (from AuctionHelper root)
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
local chunk, err = loadfile(root .. "/src/util/AuctionHelper_MailLogic.lua")
assert(chunk, err)
chunk("AuctionHelper", pe)
local ML = pe.MailLogic
assert(ML, "MailLogic missing")

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
	local off = quantities(ML.BuildSurplusPlan(bags, keep, held, false))
	check("Surplus: keep amount below stock sends the rest", off[1] == 80)
	check("Surplus: keep amount above stock sends nothing", off[2] == nil)
	check("Surplus: toggle off leaves items without a keep amount", off[3] == nil and off[7] == nil)
	check("Surplus: keep amount and queued need both held back", off[6] == 15)
	local on = quantities(ML.BuildSurplusPlan(bags, keep, held, true))
	check("Surplus: toggle on sends other items above what is held", on[3] == 30 and on[1] == 80)
	check("Surplus: queued need larger than stock sends nothing", on[7] == nil)
	check("Surplus: poor quality and unsellable never go", on[4] == nil and on[5] == nil)
	local sorted = ML.BuildSurplusPlan(bags, keep, held, true)
	check("Surplus: sorted by name", sorted[1].name == "Cloth" and sorted[#sorted].name == "Ore")
	check("Surplus: nothing configured", #ML.BuildSurplusPlan(bags, {}, {}, false) == 0)
end

-- Mail review rows
do
	local function bag(name, quantity, quality, sellable) return { name = name, quantity = quantity, quality = quality, sellable = sellable } end
	local bags = {
		[1] = bag("Ore", 100, 1, true), [2] = bag("Herb", 15, 1, true), [3] = bag("Cloth", 40, 1, true),
		[4] = bag("Junk", 9, 0, true), [5] = bag("Bound", 3, 2, false), [6] = bag("Flux", 30, 1, true), [7] = bag("Bar", 10, 1, true),
	}
	local keep = { [1] = 20, [2] = 50, [6] = 5, [8] = 12 }
	local held = { [3] = 10, [6] = 10, [7] = 25 }
	local function byID(rows)
		local out = {}
		for _, row in ipairs(rows) do out[row.itemID] = row end
		return out
	end
	local off = byID(ML.BuildReviewRows(bags, keep, held, false, {}))
	check("Review: keep below bags sends the rest", off[1].send == 80 and off[1].reason == nil and off[1].keep == 20)
	check("Review: keep above bags is kept", off[2].send == 0 and off[2].reason == "kept")
	check("Review: no keep with others off", off[3].send == 0 and off[3].reason == "othersOff")
	check("Review: keep and held both held back", off[6].send == 15 and off[6].held == 10)
	check("Review: trash and unsellable are not listed", off[4] == nil and off[5] == nil)
	check("Review: kept item not in bags is listed", off[8] and off[8].bags == 0 and off[8].send == 0 and off[8].reason == "kept")
	local on = byID(ML.BuildReviewRows(bags, keep, held, true, { [1] = true }))
	check("Review: held above bags sends nothing", on[7].send == 0 and on[7].reason == "held")
	check("Review: others on sends above held", on[3].send == 30)
	check("Review: skipped sends nothing this visit", on[1].send == 0 and on[1].reason == "skipped")
	local plan = {}
	for _, item in ipairs(ML.BuildSurplusPlan(bags, keep, held, true, { [1] = true })) do plan[item.itemID] = item.quantity end
	local agrees = true
	for itemID, row in pairs(on) do
		if (plan[itemID] or 0) ~= row.send then agrees = false end
	end
	check("Review: surplus plan equals the review rows", agrees and plan[1] == nil and plan[3] == 30)
end

-- Mail review list and totals
do
	local rows = {
		{ itemID = 1, name = "Ore", send = 80, reason = nil, unitPrice = 10 },
		{ itemID = 2, name = "Herb", send = 0, reason = "kept" },
		{ itemID = 3, name = "Cloth", send = 30, reason = nil },
		{ itemID = 4, name = "Potion", send = 0, reason = "skipped", unitPrice = 50 },
	}
	local sum = ML.SummarizeReviewRows(rows)
	check("Review sum: counts", sum.sending == 2 and sum.kept == 2 and sum.all == 4 and sum.skipped == 1)
	check("Review sum: units and worth", sum.send == 110 and sum.worth == 800)
	local class = { [1] = "Trade Goods", [2] = "Trade Goods", [3] = "Trade Goods", [4] = "Consumable" }
	local function classOf(row) return class[row.itemID] end
	local all = ML.ListReviewRows(rows, "all", "", classOf)
	check("Review list: groups sorted, rows sorted inside", all[1].group and all[1].label == "Consumable" and all[3].group
		and all[3].count == 3 and all[4].name == "Cloth" and all[6].name == "Ore")
	local sending = ML.ListReviewRows(rows, "sending", "", classOf)
	check("Review list: sending filter drops empty groups", #sending == 3 and sending[1].label == "Trade Goods")
	local kept = ML.ListReviewRows(rows, "kept", "", classOf)
	check("Review list: kept filter", #kept == 4 and kept[2].name == "Potion" and kept[4].name == "Herb")
	local found = ML.ListReviewRows(rows, "all", "ORE", classOf)
	check("Review list: search ignores case", #found == 2 and found[2].name == "Ore")
end


if failed > 0 then
	print(failed .. " check(s) failed")
	os.exit(1)
end
print("All mail logic checks passed")
