-- Run with: lua5.1 tests/test_craft_queue.lua (from Tradewright root)
-- Loads the craft queue, the retail crafting-order queue and the craft-result handler against a fake saved table:
-- add, deduct after a craft, remove, and the queue summary.
local root = arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]") or "."
local addons = root .. "/.."

local failed = 0
local function check(name, cond, detail)
	if cond then
		print("OK  " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
	end
end

-- WoW globals the loaded files use; rawset because they are read-only globals for luacheck.
local clock = 1000
local gameTime = 0
local wowGlobals = {
	time = function()
		clock = clock + 1
		return clock
	end,
	GetTime = function()
		return gameTime
	end,
	wipe = function(t)
		for k in pairs(t) do
			t[k] = nil
		end
		return t
	end,
	Enum = {},
	C_TradeSkillUI = {
		GetRecipeInfo = function(recipeID)
			return { name = "Recipe " .. tostring(recipeID) }
		end,
	},
	C_Item = {
		GetItemInfoInstant = function(link)
			return tonumber(link:match("item:(%d+)"))
		end,
	},
}
for name, value in pairs(wowGlobals) do
	rawset(_G, name, value)
end

local bags, prices = {}, {}

local function newAddon(isRetail)
	local pe = { db = {}, IS_RETAIL = isRetail, soldNotes = {} }
	function pe:InitDB() end
	function pe:GetSetting(_, default)
		return default
	end
	function pe:GetCharacterKey()
		return "Me-Realm"
	end
	function pe:GetItemDisplayName(itemID)
		return "Item " .. tostring(itemID)
	end
	function pe:ResolveCraftConfidenceState()
		return "known"
	end
	function pe:GetCraftRecommendedCrafter()
		return "Me"
	end
	function pe:GetDashboardSidebarCharacterLabel(characterKey)
		return characterKey
	end
	function pe:RefreshCraftsTabIfVisible() end
	function pe:GetItemCountByLocation(itemID)
		local count = bags[itemID] or 0
		return count, 0, 0, count
	end
	function pe:GetMarketEstimateCopper(itemID)
		return prices[itemID], "ah"
	end
	function pe:FormatNumberGrouped(n)
		return tostring(n)
	end
	function pe:NoteCraftForSeller(itemID, quantity)
		self.soldNotes[#self.soldNotes + 1] = { itemID = itemID, quantity = quantity }
	end
	function pe:PrintMessage() end

	local files = {
		"/Tradewright/src/util/Tradewright_MaterialLogic.lua",
		"/Tradewright_Inventory/src/modules/Tradewright_CraftQueue.lua",
		"/Tradewright_Inventory/src/modules/Tradewright_CraftQueueSummary.lua",
		"/Tradewright_Inventory/src/modules/Tradewright_CraftQueueOrders.lua",
		"/Tradewright_Professions/src/modules/Tradewright_OrderReagents.lua",
		"/Tradewright_Professions/src/modules/Tradewright_CraftingOrdersMaterials.lua",
		"/Tradewright_Professions/src/modules/Tradewright_CraftingOrderMenus.lua",
		"/Tradewright_Professions/src/modules/Tradewright_CraftingOrderView.lua",
		"/Tradewright_UI/src/ui/Tradewright_ProfessionCraftAction.lua",
	}
	for _, file in ipairs(files) do
		local chunk, err = loadfile(addons .. file)
		assert(chunk, err)
		chunk("Tradewright", pe)
	end
	function pe:ExtractCrafterShoppingReagentsFromOrder(order)
		return order.testMats
	end
	return pe
end

local function addCraft(pe, recipeID, outputItemID, quantity, snapshot)
	snapshot = snapshot or {}
	return pe:AddCraftToQueue({
		recipeID = recipeID,
		characterKey = "Me-Realm",
		eval = {
			recipeID = recipeID,
			outputItemID = outputItemID,
			matCost = snapshot.matCost,
			saleNet = snapshot.saleNet,
			profit = snapshot.profit,
			canCraftNow = snapshot.canCraftNow,
			outputQty = snapshot.outputQty,
			reagentPlan = snapshot.reagentPlan or {},
		},
	}, quantity)
end

local function crafted(pe, itemID, quantity)
	pe:OnProfessionRecipeCraftedResult({ hyperlink = "item:" .. itemID, quantity = quantity })
end

local function pendOn(pe, queueKey, outputItemID, startedAt)
	pe._pendingProfessionQueueCraft = { queueKey = queueKey, outputItemID = outputItemID, startedAt = startedAt or 0 }
end

local function quantityOf(pe, queueKey)
	local entry = pe:GetCraftQueueStorage()[queueKey]
	return entry and entry.quantity
end

local function orderStore(pe)
	return pe:GetCraftingOrderQueueStorage()
end

-- Add

do
	local pe = newAddon(true)
	local key = addCraft(pe, 11, 100, 3)
	check("Add: key is recipe|output|character|scenario", key == "11|100|Me-Realm|default", key)
	check("Add: entry stored with quantity", quantityOf(pe, key) == 3)
	check("Add: saved under db.craftQueue", pe.db.craftQueue[key] ~= nil)
	local again = addCraft(pe, 11, 100, 2)
	check("Add: same craft merges into one line", again == key and quantityOf(pe, key) == 5)
	check("Add: one row", #pe:GetCraftQueueRows() == 1)
	check("Add: recipe counted as queued", pe:IsRecipeInCraftQueue(11) == true)
	check("Add: other recipe not queued", pe:IsRecipeInCraftQueue(12) == false)
	check("Add: bad argument", select(2, pe:AddCraftToQueue(nil)) == "bad_arg")
	check("Add: missing eval", select(2, pe:AddCraftToQueue({ characterKey = "Me-Realm" })) == "no_eval")
	check("Add: quantity for opportunity row", pe:GetCraftQueueQuantityForOpportunityRow({ recipeID = 11, outputItemID = 100 }) == 5)
end

-- Deduct after a craft

do
	local pe = newAddon(true)
	local key = addCraft(pe, 11, 100, 3)
	pendOn(pe, key, 100)
	crafted(pe, 100, 2)
	check("Deduct: pending craft counts down", quantityOf(pe, key) == 1)
	check("Deduct: pending stays while the line is open", pe._pendingProfessionQueueCraft ~= nil)
	check("Deduct: craft noted for the seller", #pe.soldNotes == 1 and pe.soldNotes[1].quantity == 2)
	crafted(pe, 100, 5)
	check("Deduct: craft larger than the line finishes it", quantityOf(pe, key) == nil)
	check("Deduct: finished line clears the pending craft", pe._pendingProfessionQueueCraft == nil)
end

do
	local pe = newAddon(true)
	local first = addCraft(pe, 11, 100, 1)
	local second = addCraft(pe, 12, 200, 2)
	crafted(pe, 200, 2)
	check("Deduct: without pending, match by output item", quantityOf(pe, second) == nil and quantityOf(pe, first) == 1)
	crafted(pe, 300, 1)
	check("Deduct: unknown output leaves the queue alone", quantityOf(pe, first) == 1)
	crafted(pe, 100, 0)
	check("Deduct: zero quantity ignored", quantityOf(pe, first) == 1)
	crafted(pe, 100, 1)
	check("Deduct: successive crafts finish both lines", #pe:GetCraftQueueRows() == 0)
end

do
	local pe = newAddon(true)
	local pendingKey = addCraft(pe, 11, 100, 3)
	local otherKey = addCraft(pe, 12, 200, 3)
	gameTime = 100
	pendOn(pe, pendingKey, nil, 50)
	crafted(pe, 200, 1)
	check("Deduct: pending older than the timeout is dropped", quantityOf(pe, pendingKey) == 3 and quantityOf(pe, otherKey) == 2)
	check("Deduct: dropped pending cleared", pe._pendingProfessionQueueCraft == nil)
	pendOn(pe, pendingKey, nil, 90)
	crafted(pe, 200, 1)
	check("Deduct: fresh pending without output wins over the output match",
		quantityOf(pe, pendingKey) == 2 and quantityOf(pe, otherKey) == 2)
	pendOn(pe, pendingKey, 100, 90)
	crafted(pe, 200, 1)
	check("Deduct: pending for another output falls back to the output match",
		quantityOf(pe, pendingKey) == 2 and quantityOf(pe, otherKey) == 1)
	gameTime = 0
end

-- Crafting orders: one craft finishes the order line in both queues

local function sampleOrder(orderID)
	return { orderID = orderID, spellID = 21, itemID = 500, testMats = { [900] = 4, [901] = 1 } }
end

do
	local pe = newAddon(true)
	local orderKey = pe:AddCraftingOrderToQueue(sampleOrder(77))
	check("Order: stored by order id", orderKey == "77" and orderStore(pe)["77"] ~= nil)
	check("Order: saved under db.craftingOrderWorkQueue", pe.db.craftingOrderWorkQueue["77"] ~= nil)
	local stored = orderStore(pe)["77"]
	check("Order: recipe name from recipe info", stored.recipeName == "Recipe 21", stored.recipeName)
	check("Order: crafter mats kept", stored.crafterMatTotals[900] == 4)
	local queueKey = pe:CraftQueueMakeOrderKey(77)
	local marker = pe:GetCraftQueueStorage()[queueKey]
	check("Order: craft queue gets an order line", marker and marker.source == "craftingOrder" and marker.orderID == 77)
	check("Order: order line reagents from crafter mats", marker and #marker.reagentPlan == 2)
	check("Order: order line is not a recipe queue line", pe:IsRecipeInCraftQueue(21) == false)
	check("Order: in order queue", pe:IsCraftingOrderQueued(77) == true)

	pendOn(pe, queueKey, 500)
	crafted(pe, 500, 1)
	check("Order: craft finishes the craft queue line", pe:GetCraftQueueStorage()[queueKey] == nil)
	check("Order: craft finishes the order queue entry", orderStore(pe)["77"] == nil)
	check("Order: order crafts are not noted for the seller", #pe.soldNotes == 0)
end

do
	local pe = newAddon(true)
	pe:AddCraftingOrderToQueue(sampleOrder(78))
	pe:GetCraftQueueStorage()[pe:CraftQueueMakeOrderKey(78)] = nil
	_G.ProfessionsFrame = { OrdersPage = { OrderView = { order = { orderID = 78, spellID = 21 } } } }
	crafted(pe, 999, 1)
	check("Order: open order matched by spell finishes the order entry", orderStore(pe)["78"] == nil)
	_G.ProfessionsFrame = nil
end

do
	local pe = newAddon(true)
	pe:AddCraftingOrderToQueue(sampleOrder(79))
	local again = sampleOrder(79)
	again.testMats = { [902] = 3 }
	pe:AddCraftingOrderToQueue(again)
	local marker = pe:GetCraftQueueStorage()[pe:CraftQueueMakeOrderKey(79)]
	check("Order: re-adding refreshes the order line reagents",
		#marker.reagentPlan == 1 and marker.reagentPlan[1].itemID == 902 and marker.reagentPlan[1].quantityRequired == 3)
	check("Order: remove by order id", pe:RemoveCraftQueueByOrderID(79) == 1)
	check("Order: remove by order id again finds nothing", pe:RemoveCraftQueueByOrderID(79) == 0)
end

do
	local pe = newAddon(true)
	check("Order: bad order", select(2, pe:AddCraftingOrderToQueue({})) == "bad_order")
	check("Order: bad order id", select(2, pe:AddCraftingOrderToQueue({ orderID = "x" })) == "bad_id")
	local recipeInfo = C_TradeSkillUI.GetRecipeInfo
	rawset(C_TradeSkillUI, "GetRecipeInfo", function() return nil end)
	pe:AddCraftingOrderToQueue({ orderID = 83, itemID = 500, testMats = {} })
	check("Order: name falls back to the item", orderStore(pe)["83"].recipeName == "Item 500")
	pe:AddCraftingOrderToQueue({ orderID = 84, testMats = {} })
	check("Order: name falls back to a label", orderStore(pe)["84"].recipeName == "Crafting order")
	rawset(C_TradeSkillUI, "GetRecipeInfo", recipeInfo)
end

-- Reopening a stored order after a reload builds the order from the queue entry.
do
	local pe = newAddon(true)
	rawset(_G, "C_Timer", { After = function(_, callback) callback() end })
	local shown
	_G.ProfessionsFrame = {
		IsShown = function() return true end,
		OrdersPage = { ViewOrder = function(_, order) shown = order end },
	}
	pe.CraftingOrderViewRefreshButtons = function() end
	pe:AddCraftingOrderToQueue({ orderID = 85, spellID = 21, itemID = 500, tipAmount = 7, testMats = {},
		customerName = "Buyer", reagents = {} })
	check("Open: stored order opens", pe:OpenCraftingOrderQueueEntry({ orderID = 85 }) == true)
	check("Open: order rebuilt from the stored payload", shown and shown.orderID == 85 and shown.spellID == 21
		and shown.itemID == 500 and shown.tipAmount == 7 and shown.customerName == "Buyer")
	check("Open: missing fields get defaults", shown and shown.consortiumCut == 0 and shown.customerNotes == ""
		and type(shown.npcOrderRewards) == "table" and shown.isRecraft == false)
	orderStore(pe)["85"].orderPayload = nil
	shown = nil
	pe:OpenCraftingOrderQueueEntry({ orderID = 85 })
	check("Open: order rebuilt from entry fields without a payload", shown and shown.orderID == 85
		and shown.spellID == 21 and shown.tipAmount == 7 and shown.customerName == "?")
	check("Open: no order id", pe:OpenCraftingOrderQueueEntry({}) == false)
	_G.ProfessionsFrame = nil
	check("Open: needs the professions window", pe:OpenCraftingOrderQueueEntry({ orderID = 85 }) == false)
end

-- Remove

do
	local pe = newAddon(true)
	local key = addCraft(pe, 11, 100, 3)
	pe:UpdateCraftQueueQuantity(key, 7)
	check("Remove: quantity update", quantityOf(pe, key) == 7)
	pe:UpdateCraftQueueQuantity(key, 0)
	check("Remove: quantity 0 removes the line", quantityOf(pe, key) == nil)

	pe:AddCraftingOrderToQueue(sampleOrder(80))
	pe:RemoveCraftFromQueue(pe:CraftQueueMakeOrderKey(80))
	check("Remove: removing an order line clears the order entry", orderStore(pe)["80"] == nil)

	local reagentPlan = { { itemID = 900, quantityRequired = 1 } }
	addCraft(pe, 11, 100, 1, { reagentPlan = reagentPlan })
	addCraft(pe, 12, 200, 1, { reagentPlan = reagentPlan })
	addCraft(pe, 13, 300, 1)
	pe:AddCraftingOrderToQueue(sampleOrder(81))
	check("Remove: by reagent removes every line that uses it", pe:RemoveCraftQueueLinesByReagentItem(900) == 3)
	check("Remove: by reagent clears the order entry", orderStore(pe)["81"] == nil)
	check("Remove: by reagent keeps other lines", #pe:GetCraftQueueRows() == 1)
	check("Remove: by recipe", pe:RemoveCraftQueueLinesForRecipeID(13) == 1)

	addCraft(pe, 11, 100, 1)
	pe:AddCraftingOrderToQueue(sampleOrder(82))
	pe:ClearCraftQueue()
	check("Remove: clear empties both queues", #pe:GetCraftQueueRows() == 0 and next(orderStore(pe)) == nil)
end

do
	local pe = newAddon(false)
	check("Forever: no crafting-order queue", pe.GetCraftingOrderQueueStorage == nil)
	check("Forever: no crafting-order lines in the craft queue",
		pe.UpsertCraftQueueForCraftingOrder == nil and pe.RemoveCraftQueueByOrderID == nil)
	local key = addCraft(pe, 11, 100, 1)
	pe:RemoveCraftFromQueue(key)
	check("Forever: remove works without the order queue", #pe:GetCraftQueueRows() == 0)
	addCraft(pe, 11, 100, 1)
	pe:ClearCraftQueue()
	check("Forever: clear works without the order queue", #pe:GetCraftQueueRows() == 0)
end

-- Summary

do
	local pe = newAddon(true)
	bags = { [900] = 2 }
	prices = { [900] = 50, [901] = 10 }
	addCraft(pe, 11, 100, 2, {
		matCost = 100, saleNet = 70, profit = 40, outputQty = 2, canCraftNow = true,
		reagentPlan = { { itemID = 900, quantityRequired = 3 } },
	})
	addCraft(pe, 12, 200, 1, {
		matCost = 30, reagentPlan = { { itemID = 900, quantityRequired = 1 }, { itemID = 901, quantityRequired = 2 } },
	})
	local summary = pe:BuildCraftQueueSummary()
	check("Summary: line count", summary.lineCount == 2)
	check("Summary: material cost", summary.totalMatCost == 230, summary.totalMatCost)
	check("Summary: sale unknown when one line lacks it", summary.totalSaleNet == nil and summary.totalSaleNetValue == 280)
	check("Summary: profit unknown when one line lacks it", summary.totalProfit == nil and summary.totalProfitValue == 80)
	check("Summary: craftable and missing lines", summary.craftableLineCount == 1 and summary.missingMaterialsLineCount == 1)
	local line900 = summary.reagentTotals[900]
	check("Summary: reagent need summed", line900.quantityNeeded == 7)
	check("Summary: reagent to buy after bags", line900.quantityToBuy == 5 and line900.currentCharacterAvailable == 2)
	check("Summary: reagent buy cost", line900.estimatedBuyCost == 250)
	check("Summary: reagent sources", #line900.sources == 2)
	check("Summary: buy cost total", summary.totalCurrentCharacterBuyCost == 270, summary.totalCurrentCharacterBuyCost)
	check("Summary: lines sorted by name", summary.reagentLines[1].itemID == 900 and summary.reagentLines[2].itemID == 901)
	prices = {}
	check("Summary: buy cost unknown without a price", pe:BuildCraftQueueSummary().totalCurrentCharacterBuyCost == nil)

	-- A queued craft makes a material another queued craft needs.
	local maker = newAddon(true)
	bags = { [900] = 3 }
	prices = { [900] = 50, [901] = 10 }
	addCraft(maker, 21, 300, 25, { reagentPlan = { { itemID = 900, quantityRequired = 5 } } })
	addCraft(maker, 22, 900, 23, { reagentPlan = { { itemID = 901, quantityRequired = 5 } } })
	local made = maker:BuildCraftQueueSummary().reagentTotals[900]
	check("Summary: what queued crafts make is not bought", made.quantityNeeded == 125 and made.quantityFromQueue == 23 and made.quantityToBuy == 99,
		tostring(made.quantityToBuy))
	check("Summary: buy cost follows", made.estimatedBuyCost == 99 * 50)
	check("Summary: the material craft's own materials are on the list", maker:BuildCraftQueueSummary().reagentTotals[901].quantityToBuy == 115)
	for _, entry in pairs(maker:GetCraftQueueStorage()) do
		if entry.outputItemID == 900 then
			entry.characterKey = "Alt-Realm"
		end
	end
	function maker:GetAuctionCartEffectiveHave(itemID)
		return (bags[itemID] or 0) + (itemID == 900 and 40 or 0)
	end
	check("Summary: an auction purchase not yet in the bags counts as had",
		maker:BuildCraftQueueSummary().reagentTotals[900].quantityToBuy == 82)
	maker.GetAuctionCartEffectiveHave = nil
	check("Summary: a craft queued for another character is not counted on",
		maker:BuildCraftQueueSummary().reagentTotals[900].quantityToBuy == 122)
	check("Pure: bags first, then queued crafts, never below zero",
		select(2, maker.MaterialLogic.ToBuyAfterQueuedCrafts(10, 8, 50)) == 2 and maker.MaterialLogic.ToBuyAfterQueuedCrafts(10, 20, 50) == 0)

	bags = { [900] = 2 }
	prices = { [900] = 50 }
	pe:AddCraftingOrderToQueue(sampleOrder(90))
	local orders = pe:BuildCraftingOrderQueueSummary()
	check("Order summary: one line", orders.lineCount == 1)
	local orderLine = orders.reagentTotals[900]
	check("Order summary: need, buy and cost", orderLine.quantityNeeded == 4 and orderLine.quantityToBuy == 2
		and orderLine.estimatedBuyCost == 100)
	check("Order summary: source names the order", orderLine.sources[1].orderID == 90)
	check("Order summary: no price, no cost", orders.reagentTotals[901].estimatedBuyCost == nil)
	bags, prices = {}, {}
end

if failed > 0 then
	print(failed .. " craft queue checks failed")
	os.exit(1)
end
print("All craft queue checks passed")
