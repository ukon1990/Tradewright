-- Run with: lua5.1 tests/test_bag_logic.lua (from AuctionHelper root)
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
local chunk, err = loadfile(root .. "/../AuctionHelper_Bags/src/AuctionHelper_BagLogic.lua")
assert(chunk, err)
chunk("AuctionHelper_Bags", pe)
local BL = pe.BagLogic
assert(BL, "BagLogic missing")

-- Categories
local cat = BL.CategoryOf
check("Category: weapon is gear", cat({ classID = 2, quality = 3 }) == "gear")
check("Category: armor is gear", cat({ classID = 4, quality = 2 }) == "gear")
check("Category: profession gear is gear", cat({ classID = 19, quality = 2 }) == "gear")
check("Category: potion is consumable", cat({ classID = 0, subclassID = 1, quality = 1 }) == "consumable")
check("Category: food is food", cat({ classID = 0, subclassID = 5, quality = 1 }) == "food")
check("Category: trade goods", cat({ classID = 7, quality = 1 }) == "trade")
check("Category: reagent is trade", cat({ classID = 5, quality = 1 }) == "trade")
check("Category: gem is trade", cat({ classID = 3, quality = 2 }) == "trade")
check("Category: quest class is quest", cat({ classID = 12, quality = 1 }) == "quest")
check("Category: quest flag beats class", cat({ classID = 0, isQuest = true, quality = 1 }) == "quest")
check("Category: poor quest item stays quest", cat({ classID = 12, quality = 0 }) == "quest")
check("Category: poor armor is junk", cat({ classID = 4, quality = 0 }) == "junk")
check("Category: recipe is other", cat({ classID = 9, quality = 2 }) == "other")
check("Category: unknown class is other", cat({ quality = 1 }) == "other")

-- Grouping
local items = {
	{ name = "Runecloth", classID = 7, quality = 1, count = 20, bag = 1, slot = 2 },
	{ name = "Runecloth", classID = 7, quality = 1, count = 5, bag = 0, slot = 1 },
	{ name = "Arcanite Bar", classID = 7, quality = 3, count = 1 },
	{ name = "Broken Fang", classID = 15, quality = 0, count = 3, sellPrice = 10 },
	{ name = "Sword", classID = 2, quality = 4, count = 1 },
	{ name = "Dreamfoil", classID = 7, quality = 1, count = 20 },
}
local groups = BL.GroupItems(items)
check("Groups: only non-empty, in display order", #groups == 3 and groups[1].key == "gear" and groups[2].key == "trade"
	and groups[3].key == "junk")
check("Groups: labels", groups[2].label == "Trade goods")
local trade = groups[2].items
check("Groups: best quality first", trade[1].name == "Arcanite Bar")
check("Groups: then by name", trade[2].name == "Dreamfoil" and trade[3].name == "Runecloth")
check("Groups: then larger stack", trade[3].count == 20 and trade[4].count == 5)
check("Groups: empty input", #BL.GroupItems({}) == 0)

-- Layout
local opts = { columns = 3, slot = 36, gap = 4, heading = 18, headingGap = 4, groupGap = 8 }
local layout = BL.Layout(groups, opts)
check("Layout: a heading per group", #layout.headings == 3 and layout.headings[1].y == 0)
check("Layout: a slot per item", #layout.slots == 6)
check("Layout: first slot under its heading", layout.slots[1].x == 0 and layout.slots[1].y == 22)
-- gear: 22 + 36 = 58; +8 gap -> trade heading at 66; slots at 88; 4 items wrap to 2 rows.
check("Layout: second heading", layout.headings[2].y == 66)
check("Layout: columns step by slot and gap", layout.slots[3].x == 40 and layout.slots[4].x == 80)
check("Layout: wraps to the next row", layout.slots[5].x == 0 and layout.slots[5].y == 88 + 40)
-- trade ends at 88 + 76 = 164; junk heading 172; slot 194; height 230.
check("Layout: height", layout.height == 230, layout.height)
check("Layout: empty", BL.Layout({}, opts).height == 0)
groups[3].extra = { { free = true }, { free = true }, { free = true }, { free = true } }
local withExtra = BL.Layout(groups, opts)
check("Layout: extra tiles follow the items", #withExtra.slots == 10 and withExtra.slots[7].x == 40)
check("Layout: extra tiles wrap", withExtra.slots[9].x == 0 and withExtra.height == 270, withExtra.height)

-- Counts
local maelis = { name = "Maelis", seenAt = 50, bags = { [1] = 200, [2] = 3 }, bank = {} }
local bankey = { name = "Bånkey", seenAt = 90, bags = { [1] = 240 }, bank = { [1] = 1000, [3] = 4 } }
local thalric = { name = "Thalric", seenAt = 70, bags = {}, bank = { [1] = 40 } }
local characters = { ["Maelis-R"] = maelis, ["Bankey-R"] = bankey, ["Thalric-R"] = thalric }
local both = BL.MergeCounts(bankey, "both")
check("Merge: both adds bags and bank", both[1] == 1240 and both[3] == 4)
check("Merge: bags only", BL.MergeCounts(bankey, "bags")[1] == 240 and BL.MergeCounts(bankey, "bags")[3] == nil)
check("Merge: bank only", BL.MergeCounts(bankey, "bank")[1] == 1000)
check("Merge: missing tables", next(BL.MergeCounts({}, "both")) == nil)
check("Merge: all characters", BL.MergeAll(characters, "both")[1] == 1480 and BL.MergeAll(characters, "bags")[1] == 440)

local owners, total = BL.Owners(characters, 1)
check("Owners: largest first", #owners == 3 and owners[1].name == "Bånkey" and owners[2].name == "Maelis")
check("Owners: split and total", owners[1].bags == 240 and owners[1].bank == 1000 and total == 1480)
check("Owners: nobody", #BL.Owners(characters, 99) == 0)

-- Totals
local totals = BL.BagTotals({
	{ slots = 16, free = 0 }, { slots = 14, free = 7 }, { slots = 6, free = 2 }, { slots = 32, free = 18, isReagent = true },
})
check("Totals: slots and used", totals.slots == 68 and totals.used == 41)
check("Totals: reagent bag counted apart", totals.free == 9 and totals.reagentFree == 18)

check("Junk value", BL.JunkValue(items) == 30)
check("Search: empty matches", BL.Matches({ name = "Runecloth" }, "") and BL.Matches({ name = "Runecloth" }, nil))
check("Search: any case", BL.Matches({ name = "Runecloth" }, "RUNE"))
check("Search: plain text", not BL.Matches({ name = "Runecloth" }, "r.n"))
check("Search: no match", not BL.Matches({ name = "Runecloth" }, "silk"))

local bagItems = {
	{ name = "Runecloth Bag", classID = 1, subclassID = 0, quality = 1 },
	{ name = "Mooncloth Bag", classID = 1, subclassID = 0, quality = 2 },
	{ name = "Herb Pouch", classID = 1, subclassID = 11, quality = 2 },
	{ name = "Runecloth", classID = 7, quality = 1 },
}
local normal = BL.ReplacementBags(bagItems, false)
check("Replacements: normal slot", #normal == 2 and normal[1].name == "Mooncloth Bag")
local reagent = BL.ReplacementBags(bagItems, true)
check("Replacements: reagent slot", #reagent == 1 and reagent[1].name == "Herb Pouch")

local tabs = BL.TabOrder(characters, "Maelis-R")
check("Tabs: current first, then most recently seen", tabs[1] == "Maelis-R" and tabs[2] == "Bankey-R" and tabs[3] == "Thalric-R")
check("Tabs: limit", #BL.TabOrder(characters, "Maelis-R", 2) == 2)
check("Tabs: current even when unsaved", BL.TabOrder({}, "New-R")[1] == "New-R")

if failed > 0 then
	print(string.format("%d failure(s)", failed))
	os.exit(1)
end
print("All bag logic checks passed")
