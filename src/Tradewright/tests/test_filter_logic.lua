-- Run with: lua5.1 tests/test_filter_logic.lua (from Tradewright root)
-- Which rows the Inventory, Crafts and Market filters keep, through the methods the tabs call.
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
for _, path in ipairs({
	"/src/util/Tradewright_CoreHelpers.lua",
	"/src/util/Tradewright_ForeverLogic.lua",
	"/src/util/Tradewright_MarketLogic.lua",
	"/src/util/Tradewright_FilterLogic.lua",
	"/../Tradewright_UI/src/ui/Tradewright_InventoryUI.lua",
	"/../Tradewright_Professions/src/modules/Tradewright_CraftReagentPlan.lua",
	"/../Tradewright_Professions/src/modules/Tradewright_CraftQueries.lua",
}) do
	local chunk, err = loadfile(root .. path)
	assert(chunk, err)
	chunk("Tradewright", pe)
end
local qualityByItem = { [1] = 1, [2] = 3, [3] = nil, [4] = 4 }
local qualityLookups = 0
function pe:GetItemFilterInfo(itemID)
	qualityLookups = qualityLookups + 1
	return { quality = qualityByItem[itemID] }
end

-- The kept rows' ids in order, e.g. "1,3".
local function ids(rows, field)
	local out = {}
	for _, row in ipairs(rows) do
		out[#out + 1] = tostring(row[field or "id"])
	end
	return table.concat(out, ",")
end

local function expect(name, rows, want, field)
	local got = ids(rows, field)
	check(name, got == want, "got " .. got .. ", want " .. want)
end

-- Inventory
local inv = {
	{ id = 1, itemID = 1, name = "Linen Cloth", roleKey = "crafting_reagent", roleLabel = "Crafting reagent",
		itemTypeLabel = "Tradeskill", itemSubTypeLabel = "Cloth", characterKey = "A", expansionTag = "classic",
		currentAhCopper = 50, profitCopperPerUnit = 0, bags = 10, bank = 0, warband = 0 },
	{ id = 2, itemID = 2, name = "Healing Potion", roleKey = "crafted", roleLabel = "Crafted",
		itemTypeLabel = "Consumable", itemSubTypeLabel = "Potion", characterKey = "B", expansionTag = "tww",
		currentAhCopper = 0, profitCopperPerUnit = 25, bags = 0, bank = 5, warband = 0 },
	{ id = 3, itemID = 3, name = "Mystery Box", roleKey = "tracked", characterKey = "A",
		currentAhCopper = "12", profitCopperPerUnit = -4, bags = 0, bank = 0, warband = 2 },
	{ id = 4, itemID = 4, name = "Account Ore", roleKey = "crafted_reagent", itemTypeLabel = "Tradeskill",
		itemSubTypeLabel = "Metal & Stone", aggregatedInventory = true, characterKey = "C", expansionTag = "legacy" },
}
local function inventory(filters)
	return pe:FilterInventoryRows(inv, filters)
end

expect("Inventory: nil filters keep all", pe:FilterInventoryRows(inv, nil), "1,2,3,4")
expect("Inventory: nil rows give none", pe:FilterInventoryRows(nil, {}), "")
expect("Inventory: blank search keeps all", inventory({ text = "   " }), "1,2,3,4")
expect("Inventory: search by name, case and spaces ignored", inventory({ text = "  LINEN " }), "1")
expect("Inventory: search by item ID", inventory({ text = "2" }), "2")
expect("Inventory: search by role label", inventory({ text = "crafted" }), "2")
expect("Inventory: search by type label", inventory({ text = "tradeskill" }), "1,4")
expect("Inventory: search by subtype label", inventory({ text = "metal &" }), "4")
expect("Inventory: search is plain text, not a pattern", inventory({ text = "m%" }), "")
expect("Inventory: character filter keeps account-wide rows", inventory({ characters = { A = true } }), "1,3,4")
expect("Inventory: character filter needs true", inventory({ characters = { B = 1 } }), "4")
expect("Inventory: role filter", inventory({ role = { crafted = true, tracked = true } }), "2,3")
expect("Inventory: type filter skips rows without a type", inventory({ itemType = { Tradeskill = true } }), "1,4")
expect("Inventory: expansion filter", inventory({ expansions = { tww = true } }), "2")
expect("Inventory: missing expansion counts as legacy", inventory({ expansions = { legacy = true } }), "3,4")
expect("Inventory: has price (text numbers count)", inventory({ hasPrice = true }), "1,3")
expect("Inventory: profitable", inventory({ profitable = true }), "2")
expect("Inventory: location bags", inventory({ locations = { bags = true } }), "1")
expect("Inventory: location bank or warband", inventory({ locations = { bank = true, warband = true } }), "2,3")
expect("Inventory: location set to false matches nothing", inventory({ locations = { bags = false } }), "")
expect("Inventory: quality filter hides unknown quality", inventory({ qualities = { [1] = true, [4] = true } }), "1,4")
expect("Inventory: has price and bags", inventory({ hasPrice = true, locations = { bags = true } }), "1")
expect("Inventory: search, role and character together",
	inventory({ text = "o", role = { crafted_reagent = true, crafted = true }, characters = { B = true } }), "2,4")
expect("Inventory: conflicting filters keep none", inventory({ hasPrice = true, profitable = true }), "")
qualityLookups = 0
inventory({ text = "zzz" })
check("Inventory: no quality lookups without a quality filter", qualityLookups == 0, qualityLookups)

-- Crafts
local crafts = {
	{ id = 1, recipeName = "Bolt of Linen", outputName = "Bolt of Linen Cloth", perChar = { A = {} },
		skillLineID = 197, expansionTag = "classic", categoryID = 10, profit = 120, canCraftNow = true },
	{ id = 2, recipeName = "Minor Healing", outputName = "Minor Healing Potion", perChar = { B = {} },
		skillLineID = 171, expansionTag = "tww", categoryID = 20, profit = -30, canCraftNow = false },
	{ id = 3, recipeName = "Copper Rod", perChar = { A = {}, B = {} }, skillLineID = 333,
		categoryID = 30, profit = nil, canCraftNow = true },
	{ id = 4, outputName = "Hide Armor", skillLineID = 165, expansionTag = "classic",
		profit = 10, matMissingPrice = true },
}
local function craftRows(filters)
	return pe:FilterCraftRows(crafts, filters)
end

expect("Crafts: nil filters keep all", pe:FilterCraftRows(crafts, nil), "1,2,3,4")
expect("Crafts: nil rows give none", pe:FilterCraftRows(nil, {}), "")
expect("Crafts: blank search keeps all", craftRows({ text = " " }), "1,2,3,4")
expect("Crafts: search recipe name", craftRows({ text = "LINEN" }), "1")
expect("Crafts: search output name", craftRows({ text = "armor" }), "4")
expect("Crafts: search is plain text", craftRows({ text = "(" }), "")
expect("Crafts: character any of", craftRows({ characters = { B = true } }), "2,3")
expect("Crafts: character skips rows without perChar", craftRows({ characters = { A = true, C = true } }), "1,3")
expect("Crafts: profession by skill line text", craftRows({ professions = { ["171"] = true } }), "2")
expect("Crafts: profession 'all' keeps all", craftRows({ professions = { all = true, ["171"] = true } }), "1,2,3,4")
expect("Crafts: profession needs true", craftRows({ professions = { ["171"] = 1 } }), "")
expect("Crafts: expansion filter skips untagged rows", craftRows({ expansions = { classic = true } }), "1,4")
expect("Crafts: category filter skips rows without a category", craftRows({ categories = { ["10"] = true, ["30"] = true } }), "1,3")
expect("Crafts: category 'all' keeps all", craftRows({ categories = { all = true } }), "1,2,3,4")
expect("Crafts: profit all", craftRows({ profitState = "all" }), "1,2,3,4")
expect("Crafts: profitable", craftRows({ profitState = "profitable" }), "1,4")
expect("Crafts: cooldowns keeps rows the caller says have one",
	craftRows({ profitState = "cooldown", hasCooldown = function(row) return row.id == 3 end }), "3")
expect("Crafts: cooldowns without a cooldown check keeps none", craftRows({ profitState = "cooldown" }), "")
expect("Crafts: negative", craftRows({ profitState = "negative" }), "2")
expect("Crafts: missing price (no profit or a material without price)", craftRows({ profitState = "missing_price" }), "3,4")
expect("Crafts: uncraftable", craftRows({ profitState = "uncraftable" }), "2,4")
expect("Crafts: unknown profit state keeps all", craftRows({ profitState = "weird" }), "1,2,3,4")
expect("Crafts: character, expansion and profit together",
	craftRows({ characters = { A = true }, expansions = { classic = true }, profitState = "profitable" }), "1")
expect("Crafts: search and uncraftable", craftRows({ text = "heal", profitState = "uncraftable" }), "2")

-- Market
local marketInfo = {
	[10] = { classLabel = "Trade Goods", subclassLabel = "Cloth", quality = 1 },
	[11] = { classLabel = "Trade Goods", subclassLabel = "Metal", quality = 2 },
	[12] = { classLabel = "Consumable", subclassLabel = "Potion" },
}
local market = {
	{ itemID = 10, price = 15 },
	{ itemID = 11, price = "400" },
	{ itemID = 12, price = 30 },
	{ itemID = 13 },
}
local infoCalls = 0
local function getInfo(itemID)
	infoCalls = infoCalls + 1
	return marketInfo[itemID]
end
local function marketRows(filters, lookup)
	return pe.MarketLogic.FilterMarketRows(market, filters, lookup == nil and getInfo or lookup)
end

expect("Market: nil filters keep all", pe.MarketLogic.FilterMarketRows(market, nil, getInfo), "10,11,12,13", "itemID")
expect("Market: nil rows give none", pe.MarketLogic.FilterMarketRows(nil, {}, getInfo), "", "itemID")
expect("Market: min price (missing price is 0)", marketRows({ minPrice = 20 }), "11,12", "itemID")
expect("Market: max price keeps missing price", marketRows({ maxPrice = "30" }), "10,12,13", "itemID")
expect("Market: price range", marketRows({ minPrice = 15, maxPrice = 30 }), "10,12", "itemID")
expect("Market: owned only", marketRows({ ownedOnly = true, owned = { [11] = true, [13] = true } }), "11,13", "itemID")
expect("Market: owned only without an owned set keeps none", marketRows({ ownedOnly = true }), "", "itemID")
expect("Market: owned set ignored when not owned only", marketRows({ owned = { [11] = true } }), "10,11,12,13", "itemID")
expect("Market: class", marketRows({ classes = { ["Trade Goods"] = true } }), "10,11", "itemID")
expect("Market: subclass", marketRows({ subclasses = { Potion = true, Metal = true } }), "11,12", "itemID")
expect("Market: quality hides unknown", marketRows({ qualities = { [1] = true, [2] = true } }), "10,11", "itemID")
expect("Market: class and quality", marketRows({ classes = { ["Trade Goods"] = true }, qualities = { [2] = true } }), "11", "itemID")
expect("Market: class without getInfo keeps none", marketRows({ classes = { ["Trade Goods"] = true } }, false), "", "itemID")
expect("Market: empty class label matches the '' key", marketRows({ classes = { [""] = true } }), "13", "itemID")
infoCalls = 0
marketRows({ minPrice = 1 })
check("Market: no info lookups without an info filter", infoCalls == 0, infoCalls)
infoCalls = 0
marketRows({ classes = { ["Trade Goods"] = true }, subclasses = { Cloth = true }, qualities = { [1] = true } })
check("Market: one info lookup per row", infoCalls == 4, infoCalls)
infoCalls = 0
marketRows({ maxPrice = 20, classes = { ["Trade Goods"] = true } })
check("Market: price filters run before info lookups", infoCalls == 2, infoCalls)

if failed > 0 then
	print(failed .. " test(s) failed")
	os.exit(1)
end
print("All filter logic tests passed")
