local _, AuctionHelper = ...

-- Starting a craft in the open profession window: find its quantity box and Create button, set the
-- quantity, and press Create. Used by the queue's Craft button; every craft follows a click.

-- The crafting page of the open profession window and its recipe form, or nil while no recipe shows.
local function openCraftingPage()
	local page = _G.ProfessionsFrame and _G.ProfessionsFrame.CraftingPage
	local form = page and page.SchematicForm
	if not form or not form.IsShown or not form:IsShown() then
		return nil
	end
	return page, form
end

-- The first shown widget at one of `paths` that `accept` takes. The quantity box and the Create
-- button sit on the crafting page in the current client and on the recipe form in others.
local function findCraftingWidget(paths, accept)
	local page, form = openCraftingPage()
	for _, root in ipairs({ page, form }) do
		for _, path in ipairs(paths) do
			local node = root
			for _, key in ipairs(path) do
				node = node and node[key] or nil
			end
			if node and (not node.IsShown or node:IsShown()) and accept(node) then
				return node
			end
		end
	end
	return nil
end

local QUANTITY_PATHS = {
	{ "CreateMultipleInputBox" }, { "QuantityInput", "InputBox" }, { "QuantityInput" },
	{ "Details", "QuantityInput", "InputBox" }, { "Details", "QuantityInput" },
	{ "Footer", "QuantityInput", "InputBox" }, { "Footer", "QuantityInput" },
}

function AuctionHelper:TrySetCurrentProfessionCraftQuantity(amount)
	amount = math.max(1, math.floor(tonumber(amount) or 0))
	if not self.IS_SUPPORTED then
		return false
	end
	local input = findCraftingWidget(QUANTITY_PATHS, function(node) return node.SetValue or node.SetText end)
	if not input then
		return false
	end
	-- The client's quantity box is a spinner with SetValue; plain edit boxes take text.
	if input.SetValue then
		input:SetValue(amount)
	else
		input:SetText(tostring(amount))
		local onTextChanged = input.OnTextChanged or (input.GetScript and input:GetScript("OnTextChanged"))
		if onTextChanged then
			pcall(onTextChanged, input, true)
		end
	end
	if input.ClearFocus then
		input:ClearFocus()
	end
	return true
end

-- The open recipe's transaction (chosen reagents), or nil.
local function openTransaction()
	local _, form = openCraftingPage()
	return form and form.GetTransaction and form:GetTransaction() or nil
end

-- Calls `object[method]` when it exists; nil when it is missing or fails.
local function callIfPresent(object, method)
	if type(object[method]) ~= "function" then
		return nil
	end
	local ok, value = pcall(object[method], object)
	return ok and value or nil
end

--- The open recipe's reagent choices for the craft API: `reagentInfo, isRecraft, allocationGUID`.
function AuctionHelper:BuildCurrentProfessionCraftingReagentInfo(_recipeID)
	local transaction = self.IS_SUPPORTED and openTransaction()
	if not transaction then
		return nil, false, nil
	end
	return callIfPresent(transaction, "CreateCraftingReagentInfoTbl"), callIfPresent(transaction, "GetRecraftAllocation") ~= nil,
		callIfPresent(transaction, "GetAllocationItemGUID")
end

local CREATE_BUTTON_PATHS = {
	{ "CreateButton" }, { "CraftButton" }, { "Footer", "CreateButton" }, { "Footer", "CraftButton" },
	{ "Details", "CreateButton" }, { "DetailsView", "CreateButton" }, { "Schematic", "CreateButton" },
}

function AuctionHelper:FindCurrentProfessionCreateButton()
	return findCraftingWidget(CREATE_BUTTON_PATHS, function(node)
		return node.Click and node.IsEnabled and node:IsEnabled()
	end)
end

local function clickCreate(button)
	if pcall(button.Click, button) then
		return true
	end
	local onClick = button.GetScript and button:GetScript("OnClick")
	return type(onClick) == "function" and pcall(onClick, button, "LeftButton")
end

-- Crafts through the API when no Create button was found. Recrafts are left to the player.
local function craftThroughApi(pe, recipeID, amount)
	if not (recipeID and C_TradeSkillUI and C_TradeSkillUI.CraftRecipe) then
		return false
	end
	local reagentInfo, isRecraft = pe:BuildCurrentProfessionCraftingReagentInfo(recipeID)
	if isRecraft then
		return false
	end
	local transaction = openTransaction()
	local concentrating = transaction ~= nil and callIfPresent(transaction, "IsApplyingConcentration") == true
	-- Forever / older clients: craft without concentration or optional reagent arguments.
	return pcall(C_TradeSkillUI.CraftRecipe, recipeID, amount, reagentInfo, nil, nil, concentrating)
		or pcall(C_TradeSkillUI.CraftRecipe, recipeID, amount)
end

--- Starts the craft of the open recipe: presses its Create button, or uses the craft API without one.
function AuctionHelper:TryTriggerCurrentProfessionCraft(recipeID, amount)
	if not self.IS_SUPPORTED then
		return false
	end
	local button = self:FindCurrentProfessionCreateButton()
	return (button and clickCreate(button)) or craftThroughApi(self, tonumber(recipeID), math.max(1, math.floor(tonumber(amount) or 1)))
end

-- With the recipe showing: sets the quantity and starts the craft. Returns true when it was started.
local function startOpenRecipeCraft(pe, recipeID, amount)
	if tonumber(pe:GetOpenProfessionRecipeID()) ~= recipeID then
		return false
	end
	pe:TrySetCurrentProfessionCraftQuantity(amount)
	return pe:TryTriggerCurrentProfessionCraft(recipeID, amount)
end

-- The client starts a craft only from inside a click, so nothing can be crafted once the recipe has
-- finished opening a moment later. Forever recipes have no reagent choices, so the craft is asked for
-- right away by recipe id; retail recipes need the form's choices and take a second click.
local function craftUnopenedRecipe(pe, recipeID, amount)
	if pe.IS_RETAIL or not (C_TradeSkillUI and C_TradeSkillUI.CraftRecipe) then
		return false
	end
	return pcall(C_TradeSkillUI.CraftRecipe, recipeID, amount)
end

-- Fills in the quantity once the recipe shows, so a second click on Craft or Create makes the same amount.
local QUANTITY_RETRY_DELAYS = { 0.3, 0.6, 1.0 }
local function setQuantityWhenOpen(pe, recipeID, amount)
	for _, delay in ipairs(QUANTITY_RETRY_DELAYS) do
		C_Timer.After(delay, function()
			if tonumber(pe:GetOpenProfessionRecipeID()) == recipeID then
				pe:TrySetCurrentProfessionCraftQuantity(amount)
			end
		end)
	end
end

-- A shown, enabled button, or nil.
local function usableButton(button)
	return button and button:IsShown() and button:IsEnabled() and button or nil
end

-- The crafting-orders view while it shows order `orderID`, or nil.
local function orderViewShowing(orderID)
	local pf = _G.ProfessionsFrame
	local view = pf and pf.OrdersPage and pf.OrdersPage.OrderView
	local order = view and view:IsShown() and view.order
	return order and tonumber(order.orderID) == orderID and view or nil
end

-- A queued crafting order (retail) is worked on in the orders tab, one step per click like a player
-- would: open the order, then Start Order, then Create. Each step needs a click of its own, and
-- Create only works once the server has accepted Start Order.
local function stepCraftingOrder(pe, row, orderID)
	local view = orderViewShowing(orderID)
	if not view then
		pe:OpenProfessionQueueRow(row)
		return true
	end
	local button = usableButton(view.OrderInfo and view.OrderInfo.StartOrderButton) or usableButton(view.CreateButton)
	if button then
		return clickCreate(button)
	end
	pe:PrintMessage(string.format("Crafting order #%d cannot be started or crafted right now.", orderID))
	return false
end

-- Remembers which queue row the next finished craft belongs to.
local function notePendingCraft(pe, row, recipeID)
	pe._pendingProfessionQueueCraft = {
		queueKey = row.queueKey,
		recipeID = recipeID,
		outputItemID = tonumber(row.outputItemID),
		startedAt = GetTime and GetTime() or 0,
	}
end

-- A pending craft older than this no longer belongs to the next craft result.
local PENDING_CRAFT_TIMEOUT_SEC = 20

local function activePendingCraft(pe)
	local pending = pe._pendingProfessionQueueCraft
	if pending and pending.startedAt and GetTime() - pending.startedAt > PENDING_CRAFT_TIMEOUT_SEC then
		pe._pendingProfessionQueueCraft = nil
		return nil
	end
	return pending
end

local function craftResultItemID(result)
	local itemID = result.hyperlink and select(1, C_Item.GetItemInfoInstant(result.hyperlink)) or nil
	return itemID or tonumber(result.itemID)
end

-- Counts a finished craft off a queue line; a crafting-order line also leaves the crafting-order queue.
local function deductQueueEntry(pe, queueKey, entry, craftedItemID, craftedQuantity)
	local orderID = tonumber(entry.orderID)
	if not orderID and pe.NoteCraftForSeller then
		pe:NoteCraftForSeller(craftedItemID or entry.outputItemID, craftedQuantity)
	end
	pe:UpdateCraftQueueQuantity(queueKey, (tonumber(entry.quantity) or 0) - craftedQuantity)
	if orderID and pe.RemoveCraftingOrderFromQueue then
		pe:RemoveCraftingOrderFromQueue(orderID)
	end
end

local function deductPendingCraft(pe, storage, craftedItemID, craftedQuantity)
	local pending = activePendingCraft(pe)
	local queueKey = pending and pending.queueKey
	local entry = queueKey and storage[queueKey]
	if not entry then
		return false
	end
	if pending.outputItemID and craftedItemID and tonumber(craftedItemID) ~= tonumber(pending.outputItemID) then
		return false
	end
	deductQueueEntry(pe, queueKey, entry, craftedItemID, craftedQuantity)
	if not storage[queueKey] then
		pe._pendingProfessionQueueCraft = nil
	end
	return true
end

local function deductByOutputItem(pe, storage, craftedItemID, craftedQuantity)
	if not craftedItemID then
		return false
	end
	for queueKey, entry in pairs(storage) do
		if tonumber(entry and entry.outputItemID) == tonumber(craftedItemID) then
			deductQueueEntry(pe, queueKey, entry, craftedItemID, craftedQuantity)
			return true
		end
	end
	return false
end

local function openOrderViewOrder()
	local ordersPage = _G.ProfessionsFrame and _G.ProfessionsFrame.OrdersPage
	local orderView = ordersPage and ordersPage.OrderView
	return orderView and orderView.order
end

local function orderMatchesCraft(orderEntry, openOrder, craftedItemID)
	if craftedItemID and tonumber(orderEntry.itemID) == tonumber(craftedItemID) then
		return true
	end
	local spellID = tonumber(openOrder.spellID)
	return spellID ~= nil and tonumber(orderEntry.spellID) == spellID
end

-- An order crafted from the open order view that has no craft queue line left.
local function finishOpenCraftingOrder(pe, craftedItemID)
	if not (pe.IsCraftingOrderQueued and pe.RemoveCraftingOrderFromQueue) then
		return
	end
	local openOrder = openOrderViewOrder()
	local orderID = openOrder and tonumber(openOrder.orderID)
	if not orderID or not pe:IsCraftingOrderQueued(orderID) then
		return
	end
	local orderEntry = pe:GetCraftingOrderQueueStorage()[tostring(orderID)]
	if orderEntry and orderMatchesCraft(orderEntry, openOrder, craftedItemID) then
		pe:RemoveCraftingOrderFromQueue(orderID)
	end
end

--- TRADE_SKILL_ITEM_CRAFTED_RESULT: counts the craft off the pending queue row, else off a line with the
--- same output, else finishes the open crafting order.
function AuctionHelper:OnProfessionRecipeCraftedResult(craftingItemResultData)
	if type(craftingItemResultData) ~= "table" or not self.GetCraftQueueStorage then
		return
	end
	local craftedQuantity = tonumber(craftingItemResultData.quantity) or 0
	if craftedQuantity <= 0 then
		return
	end
	local craftedItemID = craftResultItemID(craftingItemResultData)
	local storage = self:GetCraftQueueStorage()
	if deductPendingCraft(self, storage, craftedItemID, craftedQuantity)
		or deductByOutputItem(self, storage, craftedItemID, craftedQuantity)
	then
		return
	end
	finishOpenCraftingOrder(self, craftedItemID)
end

--- Crafts a queue row inside the click: through the open recipe's Create button, or by recipe id
--- while another recipe shows, which is then opened with the queued quantity filled in. A crafting
--- order row instead steps through its order in the orders tab.
function AuctionHelper:CraftProfessionQueueRecipe(row)
	if type(row) ~= "table" then
		return false
	end
	local recipeSpellID = tonumber(row.recipeSpellID or row.recipeID)
	if not recipeSpellID then
		return false
	end
	notePendingCraft(self, row, recipeSpellID)
	local orderID = tonumber(row.orderID)
	if orderID and self.IS_RETAIL and self.OpenCraftingOrderQueueEntry then
		return stepCraftingOrder(self, row, orderID)
	end
	local craftAmount = math.max(1, math.floor(tonumber(row.quantity) or 1))
	if startOpenRecipeCraft(self, recipeSpellID, craftAmount) then
		return true
	end
	craftUnopenedRecipe(self, recipeSpellID, craftAmount)
	self:JumpToProfessionRecipe(recipeSpellID, row.skillLineID)
	setQuantityWhenOpen(self, recipeSpellID, craftAmount)
	return true
end
