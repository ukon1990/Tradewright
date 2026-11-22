-- Run with: lua5.1 tests/test_order_reagents.lua (from Tradewright root)
-- Retail crafting-order reagents: how an order reagent entry is read across the shapes Blizzard hands out,
-- what the crafter still has to buy for an order, and the queue state the order view buttons show.
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

local CUSTOMER, CRAFTER = 1, 2
local BASIC, MODIFYING = 1, 2
local schematics = {}
local clock = 1000
local wowGlobals = {
	time = function()
		clock = clock + 1
		return clock
	end,
	Enum = {
		CraftingOrderReagentSource = { Customer = CUSTOMER, Crafter = CRAFTER, Any = 3 },
		CraftingReagentType = { Basic = BASIC, Modifying = MODIFYING },
	},
	C_TradeSkillUI = {
		GetRecipeInfo = function(recipeID)
			return { name = "Recipe " .. tostring(recipeID) }
		end,
		GetRecipeSchematic = function(recipeID)
			return schematics[recipeID]
		end,
	},
	GameTooltip = {},
	GameTooltip_Hide = function() end,
}
for name, value in pairs(wowGlobals) do
	rawset(_G, name, value)
end

-- A frame stand-in that remembers what the buttons were told.
local function widget()
	local w = { shown = false, enabled = nil, scripts = {} }
	function w:Show() self.shown = true end
	function w:Hide() self.shown = false end
	function w:SetShown(v) self.shown = v and true or false end
	function w:SetEnabled(v) self.enabled = v and true or false end
	function w:SetScript(name, fn) self.scripts[name] = fn end
	function w:SetText(text) self.text = text end
	function w:SetHeight(h) self.height = h end
	function w:ClearAllPoints() end
	function w:SetPoint() end
	return w
end

local function newPanel()
	return {
		orderNav = widget(),
		queueCard = widget(),
		queueHost = widget(),
		peAddToQueueBtn = widget(),
		peRemoveFromQueueBtn = widget(),
		pePrevOrderBtn = widget(),
		peNextOrderBtn = widget(),
		peQueueStatusText = widget(),
	}
end

local function newAddon()
	local pe = { db = {}, IS_RETAIL = true, upserts = {}, openRecipeID = nil, queuedRecipes = {} }
	function pe:InitDB() end
	function pe:GetCharacterKey()
		return "Me-Realm"
	end
	function pe:GetItemDisplayName(itemID)
		return "Item " .. tostring(itemID)
	end
	function pe:PrintMessage() end
	function pe:RefreshCraftsTabIfVisible() end
	function pe:UpsertCraftQueueForCraftingOrder(entry)
		self.upserts[#self.upserts + 1] = entry
	end
	function pe:GetOpenProfessionRecipeID()
		return self.openRecipeID
	end
	function pe:IsRecipeInCraftQueue(recipeID)
		return self.queuedRecipes[recipeID] == true
	end
	pe.panel = newPanel()
	function pe:EnsureProfessionCraftEconomyPanel()
		return self.panel
	end
	local files = {
		"/Tradewright_Professions/src/modules/Tradewright_OrderReagents.lua",
		"/Tradewright_Professions/src/modules/Tradewright_CraftingOrdersMaterials.lua",
		"/Tradewright_Professions/src/modules/Tradewright_CraftingOrderMenus.lua",
		"/Tradewright_Professions/src/modules/Tradewright_CraftingOrderView.lua",
	}
	for _, file in ipairs(files) do
		local chunk, err = loadfile(addons .. file)
		assert(chunk, err)
		chunk("Tradewright", pe)
	end
	return pe
end

local function storedReagents(pe, reagents)
	local key = pe:AddCraftingOrderToQueue({ orderID = 1, spellID = 999, reagents = reagents })
	local out = {}
	for i, entry in ipairs(pe:GetCraftingOrderQueueStorage()[key].reagents) do
		out[i] = entry.reagent
	end
	return out
end

local function same(actual, expected)
	for _, field in ipairs({ "itemID", "quantity", "dataSlotIndex", "dataSlotType", "currencyID" }) do
		if actual[field] ~= expected[field] then
			return false, field .. "=" .. tostring(actual[field]) .. " want " .. tostring(expected[field])
		end
	end
	return true
end

local function checkSame(name, actual, expected)
	local ok, detail = same(actual, expected)
	check(name, ok, detail)
end

-- Reading one order reagent entry

do
	local pe = newAddon()
	local r = storedReagents(pe, {
		{ reagent = { dataSlotIndex = 1, dataSlotType = 2, itemID = 10, quantity = 3 } },
		{ reagent = { reagent = { itemID = 11, currencyID = 5, dataSlotIndex = 2, dataSlotType = 1 }, quantity = 4 } },
		{ reagentInfo = { dataSlotIndex = 3, dataSlotType = 1, itemID = 12, currencyID = 6, quantity = 2 } },
		{ reagentInfo = { reagent = { itemID = 13, dataSlotIndex = 4, dataSlotType = 0, currencyID = 7 } } },
		{ dataSlotIndex = 5, dataSlotType = 1, itemID = 14, quantity = "7" },
		{ reagentSlot = { dataSlotIndex = "6", dataSlotType = 2, quantity = 8 }, itemID = 15 },
		{},
	})
	checkSame("Reagent: plain reagent table", r[1], { itemID = 10, quantity = 3, dataSlotIndex = 1, dataSlotType = 2 })
	checkSame("Reagent: nested reagent.reagent", r[2], { itemID = 11, quantity = 4, dataSlotIndex = 2, dataSlotType = 1, currencyID = 5 })
	checkSame("Reagent: reagentInfo table", r[3], { itemID = 12, quantity = 2, dataSlotIndex = 3, dataSlotType = 1, currencyID = 6 })
	checkSame("Reagent: reagentInfo.reagent, zero slot type kept", r[4], { itemID = 13, quantity = 0, dataSlotIndex = 4, dataSlotType = 0, currencyID = 7 })
	checkSame("Reagent: flat entry, quantity string to number", r[5], { itemID = 14, quantity = 7, dataSlotIndex = 5, dataSlotType = 1 })
	checkSame("Reagent: reagentSlot fields, item on entry", r[6], { itemID = 15, quantity = 8, dataSlotIndex = 6, dataSlotType = 2 })
	checkSame("Reagent: empty entry", r[7], { quantity = 0 })
end

do
	local pe = newAddon()
	local r = storedReagents(pe, {
		{
			quantity = 9,
			itemID = 99,
			dataSlotIndex = 98,
			reagent = { itemID = 20, dataSlotIndex = 1, quantity = 2, reagent = { itemID = 21, dataSlotIndex = 2, dataSlotType = 3 } },
			reagentInfo = { itemID = 22, dataSlotType = 4, reagent = { itemID = 23 } },
		},
		{ reagent = { itemID = "30" }, reagentInfo = { reagent = { itemID = 31, currencyID = 32 } }, reagentSlot = { quantity = 5 } },
		{ reagentInfo = { itemID = 40, reagent = { dataSlotIndex = 7 } }, reagentSlot = { dataSlotIndex = 8, quantity = 1 } },
	})
	checkSame("Priority: inner item, outer slot index, entry quantity, nested slot type", r[1],
		{ itemID = 21, quantity = 9, dataSlotIndex = 1, dataSlotType = 3 })
	checkSame("Priority: reagent item beats reagentInfo, currency from reagentInfo", r[2],
		{ itemID = 30, quantity = 5, currencyID = 32 })
	checkSame("Priority: reagentInfo item when inner has none, reagentInfo.reagent slot beats reagentSlot", r[3],
		{ itemID = 40, quantity = 1, dataSlotIndex = 7 })
end

do
	local pe = newAddon()
	pe:AddCraftingOrderToQueue({ orderID = 2, spellID = 999, reagents = { { source = CUSTOMER, reagentSlot = { x = 1 }, reagent = { itemID = 5 } }, "junk" } })
	local stored = pe:GetCraftingOrderQueueStorage()["2"].reagents
	check("Reagent copy: keeps source and reagentSlot", stored[1].source == CUSTOMER and stored[1].reagentSlot.x == 1)
	check("Reagent copy: skips non-table entries", stored[2] == nil)
end

-- What the crafter still has to buy

schematics[100] = {
	reagentSlotSchematics = {
		{ slotIndex = 1, dataSlotIndex = 1, dataSlotType = 1, quantityRequired = 5, reagentType = BASIC, required = true,
			reagents = { { itemID = 201 }, { itemID = 202 } } },
		{ slotIndex = 2, dataSlotIndex = 1, dataSlotType = 2, quantityRequired = 2, reagentType = BASIC,
			reagents = { { itemID = 301 } } },
		{ slotIndex = 3, dataSlotIndex = 3, quantityRequired = 1, reagentType = BASIC, required = true, optional = true,
			reagents = { { itemID = 401 } } },
		{ slotIndex = 4, dataSlotIndex = 4, quantityRequired = 1, reagentType = MODIFYING,
			reagents = { { itemID = 501 } } },
		{ slotIndex = 5, dataSlotIndex = 5, quantityRequired = 0, required = true,
			reagents = { { itemID = 601 } } },
	},
}

local function shopping(reagents, spellID)
	return newAddon():ExtractCrafterShoppingReagentsFromOrder({ spellID = spellID or 100, reagents = reagents })
end

local function totalsEqual(actual, expected)
	for k, v in pairs(expected) do
		if actual[k] ~= v then
			return false
		end
	end
	for k in pairs(actual) do
		if expected[k] == nil then
			return false
		end
	end
	return true
end

local function describe(t)
	local parts = {}
	for k, v in pairs(t) do
		parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

local function checkTotals(name, actual, expected)
	check(name, totalsEqual(actual, expected), describe(actual))
end

checkTotals("Shopping: nothing provided buys required and basic slots", shopping(nil), { [201] = 5, [301] = 2 })
checkTotals("Shopping: partial customer item switches to the other quality",
	shopping({ { source = CUSTOMER, reagent = { itemID = 201, quantity = 2 } } }), { [202] = 3, [301] = 2 })
checkTotals("Shopping: fully provided slot drops out",
	shopping({ { source = CUSTOMER, reagent = { itemID = 201, quantity = 5 } } }), { [301] = 2 })
checkTotals("Shopping: crafter-sourced entries do not count as provided",
	shopping({ { source = CRAFTER, reagent = { itemID = 201, quantity = 5 } } }), { [201] = 5, [301] = 2 })
checkTotals("Shopping: slot found by data slot index and type",
	shopping({ { source = CUSTOMER, reagent = { dataSlotIndex = 1, dataSlotType = 2, quantity = 1 } } }), { [201] = 5, [301] = 1 })
checkTotals("Shopping: shared data slot index without type matches nothing",
	shopping({ { source = CUSTOMER, reagent = { dataSlotIndex = 1, quantity = 1 } } }), { [201] = 5, [301] = 2 })
checkTotals("Shopping: only item already sent is bought again",
	shopping({ { source = CUSTOMER, reagent = { itemID = 301, quantity = 1 } } }), { [201] = 5, [301] = 1 })
checkTotals("Shopping: two customer lines in one slot add up",
	shopping({
		{ source = CUSTOMER, reagent = { itemID = 201, quantity = 2 } },
		{ source = CUSTOMER, reagent = { itemID = 202, quantity = 2 } },
	}), { [201] = 1, [301] = 2 })
checkTotals("Shopping: zero quantity customer line ignored",
	shopping({ { source = CUSTOMER, reagent = { itemID = 201, quantity = 0 } } }), { [201] = 5, [301] = 2 })
checkTotals("Shopping: unknown recipe has nothing to buy", shopping(nil, 12345), {})
checkTotals("Shopping: no order", newAddon():ExtractCrafterShoppingReagentsFromOrder(nil), {})

-- Order view buttons

local function showOrdersPage(shown)
	rawset(_G, "ProfessionsFrame", { OrdersPage = { IsShown = function() return shown end } })
end

do
	local pe = newAddon()
	showOrdersPage(false)
	pe:CraftingOrderViewRefreshButtons(nil, nil)
	local p = pe.panel
	check("Buttons: nothing open hides every control",
		not p.peAddToQueueBtn.shown and not p.peRemoveFromQueueBtn.shown and not p.pePrevOrderBtn.shown and not p.peQueueStatusText.shown)
	check("Buttons: nav hidden", p.orderNav.shown == false and p.orderNav.height == 48)
end

do
	local pe = newAddon()
	showOrdersPage(false)
	pe.openRecipeID = 55
	pe.queuedRecipes[55] = true
	pe:CraftingOrderViewRefreshButtons(nil, nil)
	local p = pe.panel
	check("Buttons: queued recipe shows remove only", not p.peAddToQueueBtn.shown and p.peRemoveFromQueueBtn.shown)
	check("Buttons: recipe nav is the short row", p.orderNav.shown and p.orderNav.height == 26)
	check("Buttons: recipe nav hides order paging", not p.pePrevOrderBtn.shown and not p.peNextOrderBtn.shown and not p.peQueueStatusText.shown)
	local removed
	function pe:RemoveCraftQueueLinesForRecipeID(recipeID)
		removed = recipeID
	end
	p.peRemoveFromQueueBtn.scripts.OnClick()
	check("Buttons: recipe remove click drops that recipe", removed == 55)
end

do
	local pe = newAddon()
	showOrdersPage(true)
	pe:AddCraftingOrderToQueue({ orderID = 7, spellID = 100 })
	pe:AddCraftingOrderToQueue({ orderID = 8, spellID = 100 })
	pe.upserts = {}
	pe:CraftingOrderViewRefreshButtons(nil, { orderID = 8, spellID = 100, tipAmount = 50,
		reagents = { { source = CUSTOMER, reagent = { itemID = 201, quantity = 5 } } } })
	local p = pe.panel
	local stored = pe:GetCraftingOrderQueueStorage()["8"]
	check("Buttons: queued order refreshes stored materials", totalsEqual(stored.crafterMatTotals, { [301] = 2 }), describe(stored.crafterMatTotals))
	check("Buttons: queued order refreshes tip and reagents", stored.tipAmount == 50 and stored.reagents[1].reagent.itemID == 201)
	check("Buttons: queued order mirrored to the craft queue", #pe.upserts == 1 and pe.upserts[1] == stored)
	check("Buttons: queued order shows remove and add", p.peRemoveFromQueueBtn.shown and p.peAddToQueueBtn.shown)
	check("Buttons: last order can go back, not forward", p.pePrevOrderBtn.enabled and not p.peNextOrderBtn.enabled)
	check("Buttons: status shows position", p.peQueueStatusText.shown and p.peQueueStatusText.text == "Queue 2/2", p.peQueueStatusText.text)
	check("Buttons: nav remembers the order", p._navOrderID == 8 and p.orderNav.height == 48)
end

do
	local pe = newAddon()
	showOrdersPage(true)
	pe:CraftingOrderViewRefreshButtons(nil, { orderID = 9, spellID = 100 })
	local p = pe.panel
	check("Buttons: unqueued order hides remove and paging",
		p.peAddToQueueBtn.shown and not p.peRemoveFromQueueBtn.shown and not p.pePrevOrderBtn.shown and not p.peQueueStatusText.shown)
	check("Buttons: unqueued order not stored", pe:GetCraftingOrderQueueStorage()["9"] == nil)
	p.peAddToQueueBtn.scripts.OnClick()
	check("Buttons: add click queues the order", pe:IsCraftingOrderQueued(9))
	check("Buttons: after add, remove shows", p.peRemoveFromQueueBtn.shown)
end

if failed > 0 then
	print(string.format("%d check(s) failed", failed))
	os.exit(1)
end
print("All order reagent checks passed")
