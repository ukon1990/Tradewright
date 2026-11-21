local _, AuctionHelper = ...

-- Retail right-click menus: adds Add/Remove shopping to Blizzard's crafter order list and recipe list menus.

if not AuctionHelper.IS_RETAIL then
	return
end

local getLiveCraftingOrderView = AuctionHelper.CraftingOrderShared.getLiveCraftingOrderView

local _crafterOrderListMenuHooked = false
local _recipeListMenuHooked = false

local function getRecipeIDFromMenuOwner(ownerRegion)
	if not ownerRegion then
		return nil
	end
	if type(ownerRegion.GetElementData) == "function" then
		local ok, node = pcall(ownerRegion.GetElementData, ownerRegion)
		if ok and node then
			local data = node
			if type(node.GetData) == "function" then
				local ok2, d = pcall(node.GetData, node)
				if ok2 and type(d) == "table" then
					data = d
				end
			end
			local info = type(data) == "table" and data.recipeInfo or nil
			local recipeID = info and tonumber(info.recipeID)
			if recipeID then
				return recipeID
			end
		end
	end
	local info = ownerRegion.recipeInfo
	if type(info) == "table" and tonumber(info.recipeID) then
		return tonumber(info.recipeID)
	end
	return nil
end

--- Inject Add/Remove shopping into Blizzard's crafter order list right-click menu
--- (tagged MENU_PROFESSIONS_CRAFTER_ORDER; same menu as Favorite).
local function ensureCrafterOrderListContextMenuHook()
	if _crafterOrderListMenuHooked then
		return
	end
	if not (Menu and Menu.ModifyMenu) then
		return
	end
	_crafterOrderListMenuHooked = true
	Menu.ModifyMenu("MENU_PROFESSIONS_CRAFTER_ORDER", function(ownerRegion, rootDescription)
		-- Flat order rows carry a full CraftingOrderInfo on .option (with orderID).
		-- Bucketed recipe rows only have spellID — favorites still work, shopping does not.
		local order = ownerRegion and ownerRegion.option
		if type(order) ~= "table" or not tonumber(order.orderID) then
			return
		end
		rootDescription:CreateDivider()
		local oid = tonumber(order.orderID)
		if AuctionHelper:IsCraftingOrderQueued(oid) then
			rootDescription:CreateButton("Remove from shopping", function()
				local live = ownerRegion and ownerRegion.option
				local liveID = live and tonumber(live.orderID) or oid
				AuctionHelper:RemoveCraftingOrderFromQueue(liveID)
				AuctionHelper:CraftingOrderViewRefreshButtons(getLiveCraftingOrderView(), live)
				if AuctionHelper.ScheduleRefreshProfessionCraftEconomyPanel then
					AuctionHelper:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
				end
			end)
		else
			rootDescription:CreateButton("Add to shopping", function()
				local live = ownerRegion and ownerRegion.option
				if type(live) ~= "table" or not live.orderID then
					return
				end
				AuctionHelper:PrintMessage(string.format("Queueing crafting order #%s...", tostring(live.orderID)))
				AuctionHelper:AddCraftingOrderToQueue(live)
				AuctionHelper:CraftingOrderViewRefreshButtons(getLiveCraftingOrderView(), live)
				if AuctionHelper.ScheduleRefreshProfessionCraftEconomyPanel then
					AuctionHelper:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
				end
			end)
		end
	end)
end

--- Inject Add/Remove shopping into Blizzard's Crafting-tab recipe list right-click menu
--- (tagged MENU_PROFESSIONS_RECIPE_LIST_FAVORITE; same menu as Favorite).
local function ensureRecipeListContextMenuHook()
	if _recipeListMenuHooked then
		return
	end
	if not (Menu and Menu.ModifyMenu) then
		return
	end
	_recipeListMenuHooked = true
	Menu.ModifyMenu("MENU_PROFESSIONS_RECIPE_LIST_FAVORITE", function(ownerRegion, rootDescription)
		local recipeID = getRecipeIDFromMenuOwner(ownerRegion)
		if not recipeID then
			return
		end
		-- Skip when an order is open on the Orders page — order shopping owns that flow.
		if AuctionHelper.GetOpenCraftingOrder and AuctionHelper:GetOpenCraftingOrder() then
			return
		end
		rootDescription:CreateDivider()
		local inQueue = AuctionHelper.IsRecipeInCraftQueue
			and AuctionHelper:IsRecipeInCraftQueue(recipeID)
		if inQueue then
			rootDescription:CreateButton("Remove from shopping", function()
				if AuctionHelper.RemoveCraftQueueLinesForRecipeID then
					AuctionHelper:RemoveCraftQueueLinesForRecipeID(recipeID)
				end
				if AuctionHelper.ScheduleRefreshProfessionCraftEconomyPanel then
					AuctionHelper:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
				end
			end)
		else
			rootDescription:CreateButton("Add to shopping", function()
				if AuctionHelper.QueueOpenProfessionRecipe then
					AuctionHelper:QueueOpenProfessionRecipe(1, { recipeID = recipeID })
				end
			end)
		end
	end)
end

AuctionHelper.CraftingOrderMenus = {
	ensureCrafterOrderListContextMenuHook = ensureCrafterOrderListContextMenuHook,
	ensureRecipeListContextMenuHook = ensureRecipeListContextMenuHook,
}
