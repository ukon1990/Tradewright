-- Run with: lua5.1 tests/test_bag_logic.lua (from Tradewright root)
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
local chunk, err = loadfile(root .. "/../Tradewright_Bags/src/Tradewright_BagLogic.lua")
assert(chunk, err)
chunk("Tradewright_Bags", pe)
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
check("Category: gear in a saved set", cat({ classID = 4, quality = 3, inSet = true }) == "gearset")
check("Category: gear in no set", cat({ classID = 2, quality = 3, inSet = false }) == "gearloose")
check("Category: set split leaves other items alone", cat({ classID = 7, quality = 1, inSet = false }) == "trade")
check("Category: poor gear stays junk when split", cat({ classID = 4, quality = 0, inSet = false }) == "junk")
local splitGroups = BL.GroupItems({ { name = "A", classID = 4, quality = 2, inSet = false }, { name = "B", classID = 4, quality = 2, inSet = true } })
check("Groups: set gear first, then gear in no set", splitGroups[1].label == "Gear in a set" and splitGroups[2].label == "Gear not in a set")
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

-- Gold
maelis.money, bankey.money = 124986, 12040000
local gold, goldTotal = BL.GoldByCharacter(characters)
check("Gold: richest first, unsaved left out", #gold == 2 and gold[1].name == "Bånkey" and gold[2].money == 124986)
check("Gold: total", goldTotal == 12164986)
check("Gold: nobody", select(2, BL.GoldByCharacter({})) == 0)

-- Adopting counts saved under the old database
local into = { A = { seenAt = 10, money = 1 }, B = { seenAt = 50, money = 2 } }
BL.AdoptHoldings(into, { A = { seenAt = 20, money = 3 }, B = { seenAt = 40, money = 4 }, C = { money = 5 } })
check("Adopt: newer record wins", into.A.money == 3)
check("Adopt: older record is ignored", into.B.money == 2)
check("Adopt: unknown character is added", into.C.money == 5)

-- Cheapest stack to delete
local drop = BL.CheapestToDrop({
	{ itemID = 1, name = "Fang", quality = 0, classID = 15, sellPrice = 10, count = 3 },
	{ itemID = 2, name = "Claw", quality = 0, classID = 15, sellPrice = 4, count = 5 },
	{ itemID = 3, name = "Linen", quality = 1, classID = 7, sellPrice = 1, count = 1 },
})
check("Drop: cheapest junk stack, even when other items are cheaper", drop.item.name == "Claw" and drop.value == 20 and drop.isJunk)
drop = BL.CheapestToDrop({
	{ itemID = 1, name = "Fang", quality = 0, classID = 15, sellPrice = 1, count = 1, locked = true },
	{ itemID = 3, name = "Linen", quality = 1, classID = 7, sellPrice = 5, count = 10 },
	{ itemID = 4, name = "Silk", quality = 1, classID = 7, sellPrice = 2, count = 4 },
	{ itemID = 5, name = "Hearthstone", quality = 1, classID = 15, sellPrice = 0, count = 1 },
	{ itemID = 6, name = "Quest Note", quality = 1, classID = 12, sellPrice = 1, count = 1 },
	{ itemID = 7, name = "Rare Sword", quality = 3, classID = 2, sellPrice = 1, count = 1 },
	{ itemID = 8, name = "Small Pouch", quality = 1, classID = 1, sellPrice = 1, count = 1 },
}, function(itemID) return itemID == 4 and 100 or nil end)
check("Drop: locked junk is skipped, then the cheapest other stack", drop.item.name == "Linen" and drop.value == 50 and not drop.isJunk,
	drop.item.name)
check("Drop: auction price counts when higher", BL.CheapestToDrop({
	{ itemID = 4, name = "Silk", quality = 1, classID = 7, sellPrice = 2, count = 4 },
}, function() return 100 end).value == 400)
check("Drop: no value, quest, rare and bags are never offered", BL.CheapestToDrop({
	{ itemID = 5, quality = 1, classID = 15, sellPrice = 0 }, { itemID = 6, quality = 1, classID = 12, sellPrice = 1 },
	{ itemID = 7, quality = 3, classID = 2, sellPrice = 1 }, { itemID = 8, quality = 1, classID = 1, sellPrice = 1 },
}) == nil)
check("Drop: worthless junk goes first", BL.CheapestToDrop({
	{ itemID = 1, quality = 0, classID = 15, sellPrice = 0 }, { itemID = 2, quality = 0, classID = 15, sellPrice = 3 },
}).value == 0)
check("Drop: empty bags", BL.CheapestToDrop({}) == nil)

-- Profession tools: the last one of a kind is never offered, a spare may go
local knife = { itemID = 7005, name = "Skinning Knife", quality = 1, classID = 7, sellPrice = 1, count = 1 }
local pick = { itemID = 2901, name = "Mining Pick", quality = 1, classID = 7, sellPrice = 1, count = 1 }
local pole = { itemID = 6256, name = "Fishing Pole", quality = 1, classID = 2, subclassID = 20, sellPrice = 1, count = 1 }
local linen = { itemID = 3, name = "Linen", quality = 1, classID = 7, sellPrice = 5, count = 10 }
drop = BL.CheapestToDrop({ knife, pick, pole, linen })
check("Tools: only tools are cheaper, yet the next item is offered", drop and drop.item.name == "Linen", drop and drop.item.name)
check("Tools: the only tools of each kind are never offered", BL.CheapestToDrop({ knife, pick, pole }) == nil)
local finkle = { itemID = 12709, name = "Finkle's Skinner", quality = 1, classID = 7, sellPrice = 3, count = 1 }
drop = BL.CheapestToDrop({ knife, finkle, linen })
check("Tools: with two skinning tools the cheaper spare may go", drop and drop.item.name == "Skinning Knife", drop and drop.item.name)
drop = BL.CheapestToDrop({ pole, { itemID = 6365, name = "Strong Fishing Pole", quality = 1, classID = 2, subclassID = 20, sellPrice = 2, count = 1 } })
check("Tools: fishing poles are found by subclass and count together", drop and drop.item.name == "Fishing Pole", drop and drop.item.name)
check("Tools: kind of an ordinary item is nil", BL.ToolKind(linen) == nil and BL.ToolKind(pole) == "fishing" and BL.ToolKind(pick) == "mining")

-- Loot worth swapping in
local lootList = { { slot = 1, name = "Linen", value = 10 }, { slot = 2, name = "Arcanite", value = 5000 }, { slot = 3, name = "Fang", value = 40 } }
check("Loot swap: most valuable loot above the dropped stack", BL.BestLootSwap(lootList, { value = 30 }).slot == 2)
check("Loot swap: equal value is not worth it", BL.BestLootSwap({ { slot = 1, value = 30 } }, { value = 30 }) == nil)
check("Loot swap: nothing to loot", BL.BestLootSwap({}, { value = 0 }) == nil)

-- Selecting
local selection = {}
local stackA = { itemID = 1, bag = 0, slot = 3, sellPrice = 5, count = 4, quality = 1, classID = 7 }
local stackB = { itemID = 2, bag = -1, slot = 3, sellPrice = 0, count = 1, quality = 1, classID = 7 }
check("Select: slot keys differ per bag", BL.SlotKey(0, 3) ~= BL.SlotKey(-1, 3) and BL.SlotKey(1, 3) ~= BL.SlotKey(0, 3))
check("Select: toggle on", BL.ToggleSelected(selection, stackA) and BL.ToggleSelected(selection, stackB))
check("Select: picked in item order", #BL.SelectedItems(selection, { stackB, stackA }) == 2
	and BL.SelectedItems(selection, { stackB, stackA })[1] == stackB)
check("Select: toggle off", not BL.ToggleSelected(selection, stackB) and #BL.SelectedItems(selection, { stackB, stackA }) == 1)
local replaced = { itemID = 9, bag = 0, slot = 3 }
check("Select: a slot holding another item is dropped", #BL.SelectedItems(selection, { replaced }) == 0 and next(selection) == nil)
check("Select: saved items have no slot", #BL.SelectedItems({ [3] = 1 }, { { itemID = 1 } }) == 0)

-- Where a stack can go
local function targetKeys(place, state)
	local keys = {}
	for _, target in ipairs(BL.MoveTargets(place, state)) do
		keys[#keys + 1] = target.key
	end
	return table.concat(keys, ",")
end
check("Move: nowhere while the bank is closed", targetKeys("bags", { hasWarband = true }) == "")
check("Move: bags to bank only without a warband bank", targetKeys("bags", { bankOpen = true }) == "bank")
check("Move: bags to bank or warband", targetKeys("bags", { bankOpen = true, hasWarband = true }) == "bank,warband")
check("Move: warband to bags or bank", targetKeys("warband", { bankOpen = true, hasWarband = true }) == "bags,bank")
check("Move: label", BL.MoveTargets("bank", { bankOpen = true })[1].label == "Move to bags")
local moves, left = BL.PlanMoves({ stackA, stackB, replaced }, { { bag = 5, slot = 1 }, { bag = 5, slot = 2 } })
check("Move: a free slot per stack", #moves == 2 and moves[2].item == stackB and moves[2].bag == 5 and moves[2].slot == 2)
check("Move: the rest is reported", left == 1 and select(2, BL.PlanMoves({}, {})) == 0)

-- Selling and destroying several
local sellQueue, sellTotal = BL.SellQueue({ stackA, stackB, { itemID = 3, sellPrice = 9, count = 1, locked = true } })
check("Sell: only unlocked stacks a vendor buys", #sellQueue == 1 and sellTotal == 20)
local destroyQueue, destroyTotal, refused = BL.DestroyQueue({
	stackA, stackB,
	{ itemID = 6, quality = 1, classID = 12, sellPrice = 1 }, { itemID = 7, quality = 3, classID = 2, sellPrice = 1 },
	{ itemID = 8, quality = 1, classID = 1, sellPrice = 1 }, { itemID = 9, quality = 0, classID = 15, locked = true },
}, function(itemID) return itemID == 1 and 50 or nil end)
check("Destroy: quest, rare, bags and locked are refused", #destroyQueue == 2 and refused == 4)
check("Destroy: valued at the higher of vendor and auction", destroyTotal == 200, destroyTotal)

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
local helm = { name = "Wolf Helm", classID = 4, quality = 3, keywords = "Armor Leather Head Rare" }
check("Search: item type and subtype", BL.Matches(helm, "armor") and BL.Matches(helm, "leather"))
check("Search: equip slot and quality", BL.Matches(helm, "head") and BL.Matches(helm, "rare"))
check("Search: category heading", BL.Matches(helm, "gear") and BL.Matches({ name = "Fang", quality = 0 }, "junk"))
check("Search: every word must fit", BL.Matches(helm, "rare  leather wolf") and not BL.Matches(helm, "rare cloth"))
check("Search: only spaces matches", BL.Matches(helm, "  "))

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
characters.warband = { name = "Warband bank", bank = { [1] = 7 }, money = 500 }
tabs = BL.TabOrder(characters, "Maelis-R", 3, "warband")
check("Tabs: warband bank right after the current character", tabs[2] == "warband" and tabs[3] == "Bankey-R" and #tabs == 3)
check("Tabs: no warband tab before it is saved", BL.TabOrder({}, "New-R", 3, "warband")[2] == nil)
check("Merge: all includes the warband bank", BL.MergeAll(characters, "bank")[1] == 1047 and BL.MergeAll(characters, "bags")[1] == 440)

check("Link name: read from the link", BL.LinkName("|cff0070dd|Hitem:1::|h[Iron Bar]|h|r") == "Iron Bar")
check("Link name: empty name of an item without data is nil", BL.LinkName("|cff0070dd|Hitem:1::|h[]|h|r") == nil)
check("Link name: no link is nil", BL.LinkName(nil) == nil)

if failed > 0 then
	print(string.format("%d failure(s)", failed))
	os.exit(1)
end
print("All bag logic checks passed")
