local _, ProfessionExporter = ...

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

function ProfessionExporter:TrySetCurrentProfessionCraftQuantity(amount)
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
function ProfessionExporter:BuildCurrentProfessionCraftingReagentInfo(_recipeID)
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

function ProfessionExporter:FindCurrentProfessionCreateButton()
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
function ProfessionExporter:TryTriggerCurrentProfessionCraft(recipeID, amount)
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

--- Crafts a queue row inside the click: through the open recipe's Create button, or by recipe id
--- while another recipe shows, which is then opened with the queued quantity filled in. A crafting
--- order row instead steps through its order in the orders tab.
function ProfessionExporter:CraftProfessionQueueRecipe(row)
	if type(row) ~= "table" then
		return false
	end
	local recipeSpellID = tonumber(row.recipeSpellID or row.recipeID)
	if not recipeSpellID then
		return false
	end
	notePendingCraft(self, row, recipeSpellID)
	local orderID = tonumber(row.orderID)
	if orderID and self.IS_RETAIL and self.OpenCraftingOrderWorkQueueEntry then
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
