-- Run with: lua5.1 tests/test_auction_logic.lua (from AuctionHelper root)
-- Pins the craft cart rows (queue and order merge, have / buy split, cost, source text) and the live
-- search aggregate (commodity fold, per item key variants, narrowing by item key).
local root = arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]") or "."
local repo = root .. "/.."

local failed = 0
local function check(name, cond, detail)
	if cond then
		print("OK  " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
	end
end

_G.C_Timer = { After = function() end }
_G.GetBuildInfo = function() return "1.16.1", "1", "", 16001 end
_G.CreateFrame = function() return {} end
_G.GetServerTime = function() return 1700000000 end

local pe = {}
local function load(path)
	local chunk, err = loadfile(repo .. "/" .. path)
	assert(chunk, err)
	chunk("AuctionHelper", pe)
end
load("AuctionHelper/src/core/AuctionHelper.lua")
load("AuctionHelper/src/util/AuctionHelper_ForeverLogic.lua")
load("AuctionHelper/src/util/AuctionHelper_AuctionLogic.lua")
load("AuctionHelper/src/util/AuctionHelper_CoreHelpers.lua")
load("AuctionHelper/src/util/AuctionHelper_Util.lua")
load("AuctionHelper/src/util/AuctionHelper_JsonCodec.lua")
load("AuctionHelper/src/util/AuctionHelper_ItemInfo.lua")
load("AuctionHelper/src/core/AuctionHelper_Data.lua")
load("AuctionHelper/src/core/AuctionHelper_ProfessionSpecTree.lua")
load("AuctionHelper/src/core/AuctionHelper_ProfessionScan.lua")
load("AuctionHelper/src/core/AuctionHelper_ExportBuild.lua")
load("AuctionHelper/src/core/AuctionHelper_CopyBox.lua")
load("AuctionHelper/src/core/AuctionHelper_SlashCommands.lua")
for _, path in ipairs(dofile(root .. "/tests/auction_data_files.lua")(repo)) do
	load(path)
end
local AL = pe.AuctionLogic

pe.DebugLog = function() end

-- Craft cart rows
local queueRows = { { orderID = 7 }, { recipeID = 1 } }
local summary = {
	reagentLines = {
		{ itemID = 2589, name = "Linen Cloth", quantityNeeded = 4, estimatedUnitPrice = 100, estimatedPriceSource = "snapshot",
			sources = { { recipeName = "Bandage" } } },
		{ itemID = 2592, quantity = 2, sources = { { recipeName = "Bolt" }, { recipeName = "Bandage" }, { recipeName = "Bolt" } } },
	},
}
local orderSources = { { orderID = 7, quantity = 3 }, { orderID = 8, quantity = 2 } }
local orderSummary = {
	reagentLines = {
		{ itemID = 2589, name = "Linen Cloth", estimatedUnitPrice = 90, priceSource = "tsm", sources = orderSources },
		{ itemID = 3000, name = "Mirrored Only", estimatedUnitPrice = 5, sources = { { orderID = 7, quantity = 4 } } },
		{ itemID = 4000, name = "Zinc", sources = { { quantity = 1, outputName = "Ring" } } },
	},
}
local have = { [2589] = 1, [2592] = 5 }
pe.BuildCraftQueueSummary = function() return summary end
pe.BuildCraftingOrderQueueSummary = function() return orderSummary end
pe.GetCraftQueueRows = function() return queueRows end
pe.GetCharacterKey = function() return "Me-Realm" end
pe.GetCharacterItemTotal = function(_, _, itemID) return have[itemID] or 0 end
pe.GetItemDisplayName = function(_, itemID) return "Item " .. itemID end
pe.ResolveItemDescriptor = function(_, itemID)
	if itemID == 2589 then
		return { icon = 132889, itemType = "Tradeskill", itemSubType = "Cloth" }
	end
end
pe.BuildAuctionPanelPriceState = function(_, itemID)
	return { currentPrice = itemID == 2589 and 95 or nil, currentPriceSource = "native", currentPriceSeenAt = 1699990000,
		currentPriceIsNative = itemID == 2589, nativePrice = 95, fallbackPrice = "120" }
end
pe.BuildReagentMailAllocations = function(_, itemID, sources) return { itemID = itemID, count = #sources } end
pe.FormatMailAllocationsShort = function(_, allocations) return allocations.itemID == 2589 and "Alt x2" or nil end

local rows, gotSummary, gotOrderSummary = pe:BuildAuctionCraftCartRows()
local byItem = {}
for _, row in ipairs(rows) do
	byItem[row.itemID] = row
end
check("Cart returns both summaries", gotSummary == summary and gotOrderSummary == orderSummary)
check("Cart has one row per item, mirrored-only order items dropped", #rows == 3 and not byItem[3000], #rows)
check("Cart rows sort by name", rows[1].itemName == "Item 2592" and rows[2].itemName == "Linen Cloth" and rows[3].itemName == "Zinc")

local linen = byItem[2589]
check("Queue and unmirrored order need add up", linen.quantityNeeded == 6, linen.quantityNeeded)
check("Have is what the character holds", linen.quantityHave == 1 and linen.quantityOnCharacter == 1)
check("Buy is need minus have", linen.quantityToBuy == 5, linen.quantityToBuy)
check("Cheaper order price wins with its source", linen.estimatedUnitPrice == 90 and linen.estimatedPriceSource == "tsm",
	tostring(linen.estimatedUnitPrice) .. " " .. tostring(linen.estimatedPriceSource))
check("Buy cost is price times buy", linen.estimatedBuyCost == 450, linen.estimatedBuyCost)
check("Order sources are prefixed", linen.sourceText == "Bandage, WO: Order #8", linen.sourceText)
check("Mirrored order source is left out", #linen.sources == 2 and linen.sources[2].orderID == 8, #linen.sources)
check("Order sources are copied, not renamed in place", orderSources[2].recipeName == nil)
check("Descriptor fills icon and class", linen.itemIcon == 132889 and linen.itemClassLabel == "Tradeskill"
	and linen.itemSubclassLabel == "Cloth")
check("Price state fills current price", linen.currentPrice == 95 and linen.currentPriceIsNative == true
	and linen.currentPriceSource == "native" and linen.currentPriceSeenAt == 1699990000 and linen.nativePrice == 95
	and linen.fallbackPrice == 120)
check("Mail text comes from the allocations", linen.mailToText == "Alt x2" and linen.mailAllocations.count == 2)

local bolt = byItem[2592]
check("Plain quantity counts as need", bolt.quantityNeeded == 2)
check("Have is capped at need", bolt.quantityHave == 2 and bolt.quantityOnCharacter == 5)
check("Covered item buys nothing and has no cost", bolt.quantityToBuy == 0 and bolt.estimatedBuyCost == nil)
check("Unpriced item has no price", bolt.estimatedUnitPrice == nil and bolt.currentPrice == nil
	and bolt.currentPriceIsNative == false)
check("Source names are unique and sorted", bolt.sourceText == "Bandage, Bolt" and bolt.sourceCount == 2, bolt.sourceText)
check("Missing name falls back to the item name", bolt.itemName == "Item 2592")
check("Missing descriptor uses the default icon", bolt.itemIcon == 134400 and bolt.itemClassLabel == ""
	and bolt.itemSubclassLabel == "")
check("Missing mail text shows a dash", bolt.mailToText == "—")

local zinc = byItem[4000]
check("Order without an order ID is kept", zinc.quantityNeeded == 1 and zinc.quantityToBuy == 1)
check("Output name labels a source", zinc.sourceText == "Ring", zinc.sourceText)

pe.BuildCraftingOrderQueueSummary = nil
pe.BuildReagentMailAllocations = nil
local plainRows = pe:BuildAuctionCraftCartRows()
check("Without orders only the queue is merged", #plainRows == 2 and plainRows[2].quantityNeeded == 4,
	plainRows[2] and plainRows[2].quantityNeeded)
check("Without mail allocations the mail text is a dash", plainRows[2].mailToText == "—" and plainRows[2].mailAllocations == nil)

pe:GetState().auctionCartPurchaseCredits = { [2589] = { baseline = 1, credit = 2 } }
local creditRows = pe:BuildAuctionCraftCartRows()
check("Pending purchase credit counts as have", creditRows[2].quantityOnCharacter == 3 and creditRows[2].quantityToBuy == 1,
	creditRows[2].quantityOnCharacter)
pe:GetState().auctionCartPurchaseCredits = nil

-- Live search aggregate
local commodityResults, itemResults = {}, {}
_G.C_AuctionHouse = {
	GetNumCommoditySearchResults = function() return #commodityResults end,
	GetCommoditySearchResultInfo = function(_, index) return commodityResults[index] end,
	MakeItemKey = function(itemID, itemLevel, itemSuffix, petID)
		return { itemID = itemID, itemLevel = itemLevel, itemSuffix = itemSuffix, battlePetSpeciesID = petID }
	end,
	GetNumItemSearchResults = function() return #itemResults end,
	GetItemSearchResultInfo = function(_, index) return itemResults[index] end,
}

commodityResults = { { quantity = 5, unitPrice = 100 }, { quantity = 10, unitPrice = 80 }, { unitPrice = 0 }, false }
local commodity = pe:GetLiveAuctionSearchAggregate(2589)
check("Commodity aggregate kind", commodity and commodity.kind == "commodity" and commodity.itemID == 2589)
check("Commodity min and max unit", commodity.minUnitPrice == 80 and commodity.maxUnitPrice == 100)
check("Commodity quantity sums listed rows", commodity.totalQuantity == 15, commodity.totalQuantity)
check("Commodity listing count is the result count", commodity.listingCount == 4, commodity.listingCount)

commodityResults = { { quantity = 0, unitPrice = 7 } }
check("Commodity quantity is at least one", pe:GetLiveAuctionSearchAggregate(2589).totalQuantity == 1)

local function itemRow(itemLevel, quantity, buyout)
	return { itemKey = { itemID = 19019, itemLevel = itemLevel, itemSuffix = 0, battlePetSpeciesID = 0 },
		quantity = quantity, buyoutAmount = buyout }
end
commodityResults = { { quantity = 3 } }
itemResults = {
	itemRow(71, 1, 1000),
	itemRow(60, 1, 500),
	itemRow(60, 2, 901),
	itemRow(60, nil, nil),
	itemRow(80, 4, 0),
	{ quantity = 1, buyoutAmount = 1 },
}
local item = pe:GetLiveAuctionSearchAggregate(19019)
check("Unpriced commodity falls back to the item search", item and item.kind == "item" and item.itemID == 19019)
check("Unpriced variants are dropped", #item.variants == 2, #item.variants)
local v60, v71 = item.variants[1], item.variants[2]
check("Variants sort by item key", v60.key == "19019:60:0:0" and v71.key == "19019:71:0:0")
check("Variant unit price floors buyout per unit", v60.minUnitPrice == 450 and v60.maxUnitPrice == 500,
	tostring(v60.minUnitPrice) .. " " .. tostring(v60.maxUnitPrice))
check("Variant counts unpriced listings in its quantity", v60.totalQuantity == 4 and v60.listingCount == 3,
	v60.totalQuantity .. " " .. v60.listingCount)
check("Variant keeps its item key", v60.itemKey.itemLevel == 60)
check("Item aggregate cheapest and highest", item.cheapestUnitPrice == 450 and item.highestUnitPrice == 1000)
check("Item aggregate totals priced variants", item.totalQuantityAll == 5 and item.listingCountAll == 4,
	item.totalQuantityAll .. " " .. item.listingCountAll)

local narrowed = pe:GetLiveAuctionSearchAggregate(19019, { itemLevel = 71 })
check("Item key narrows to its variant", #narrowed.variants == 1 and narrowed.variants[1].key == "19019:71:0:0"
	and narrowed.cheapestUnitPrice == 1000 and narrowed.listingCountAll == 1)
local zero = pe:GetLiveAuctionSearchAggregate(19019, { itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 })
check("All-zero item key narrows nothing", #zero.variants == 2)
check("Item key without listings gives nothing", pe:GetLiveAuctionSearchAggregate(19019, { itemLevel = 80 }) == nil)

itemResults = {}
check("No results give nothing", pe:GetLiveAuctionSearchAggregate(19019) == nil)
check("Bad item ID gives nothing", pe:GetLiveAuctionSearchAggregate(0) == nil)

-- Pure parts
if AL then
	local merged = {}
	AL.MergeCartReagentLine(merged, { itemID = "5", quantityNeeded = 2,
		sources = { { orderID = 3 } } }, "WO: ", function(itemID) return "N" .. itemID end)
	AL.MergeCartReagentLine(merged, { itemID = 5, quantity = 1, estimatedUnitPrice = 40, priceSource = "p" }, nil)
	AL.MergeCartReagentLine(merged, { itemID = 5, quantity = 1, estimatedUnitPrice = 60 }, nil)
	AL.MergeCartReagentLine(merged, { quantity = 9 }, nil)
	local row = merged[5]
	check("Merge adds need per item", row.quantityNeeded == 4 and row.name == "N5")
	check("Merge keeps the lowest positive price", row.estimatedUnitPrice == 40 and row.estimatedPriceSource == "p")
	check("Merge names an order source", row.sources[1].recipeName == "WO: Order #3")
	check("Merge skips lines without an item", next(merged, next(merged)) == nil)

	local filtered = AL.FilterCartOrderReagentLine({ itemID = 9, estimatedUnitPrice = 3, priceSource = "x",
		sources = { { orderID = 1, quantity = 2 }, { orderID = 2, quantity = 5 } } }, { [1] = true })
	check("Order line keeps unmirrored need", filtered.quantityNeeded == 5 and filtered.quantity == 5
		and #filtered.sources == 1 and filtered.estimatedPriceSource == "x")
	check("Fully mirrored order line is dropped",
		AL.FilterCartOrderReagentLine({ itemID = 9, sources = { { orderID = 1, quantity = 2 } } }, { [1] = true }) == nil)

	local text, count = AL.CartSourceText({ { recipeName = "B" }, { orderID = 4 }, { recipeName = "B" }, {} })
	check("Source text is unique and sorted", text == "B, Order #4" and count == 2, text)
	check("No sources give a dash", select(1, AL.CartSourceText(nil)) == "—")

	local acc = { totalQuantity = 0 }
	AL.AddCommodityResult(acc, { quantity = 2, unitPrice = 30 })
	AL.AddCommodityResult(acc, { quantity = -1, unitPrice = 10 })
	check("Commodity fold", acc.totalQuantity == 2 and acc.minUnitPrice == 10 and acc.maxUnitPrice == 30)

	local groups = {}
	AL.AddItemResult(groups, "k", { itemKey = {}, quantity = 3, buyoutAmount = 10 })
	check("Item fold floors the unit price", groups.k.minUnitPrice == 3 and groups.k.totalQuantity == 3)
	local summaryOfGroups = AL.SummarizeItemVariants(groups)
	check("Variant summary", summaryOfGroups.totalQuantityAll == 3 and summaryOfGroups.cheapestUnitPrice == 3
		and #summaryOfGroups.variants == 1)
	check("Variant summary without prices is nothing", AL.SummarizeItemVariants({ x = { key = "x", totalQuantity = 1,
		listingCount = 1 } }) == nil)
end

if failed > 0 then
	print(failed .. " test(s) failed")
	os.exit(1)
end
print("All auction logic tests passed")
