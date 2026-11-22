local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Retail right-click menus: adds Add/Remove shopping to Blizzard's crafter order list and recipe list menus.

if not Tradewright.IS_RETAIL then
	return
end

local getLiveCraftingOrderView = Tradewright.CraftingOrderShared.getLiveCraftingOrderView

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
		if Tradewright:IsCraftingOrderQueued(oid) then
			rootDescription:CreateButton(L["Remove from queue"], function()
				local live = ownerRegion and ownerRegion.option
				local liveID = live and tonumber(live.orderID) or oid
				Tradewright:RemoveCraftingOrderFromQueue(liveID)
				Tradewright:CraftingOrderViewRefreshButtons(getLiveCraftingOrderView(), live)
				if Tradewright.ScheduleRefreshProfessionCraftEconomyPanel then
					Tradewright:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
				end
			end)
		else
			rootDescription:CreateButton(L["Add to queue"], function()
				local live = ownerRegion and ownerRegion.option
				if type(live) ~= "table" or not live.orderID then
					return
				end
				Tradewright:PrintMessage(string.format(L["Adding crafting order #%s to the queue…"], tostring(live.orderID)))
				Tradewright:AddCraftingOrderToQueue(live)
				Tradewright:CraftingOrderViewRefreshButtons(getLiveCraftingOrderView(), live)
				if Tradewright.ScheduleRefreshProfessionCraftEconomyPanel then
					Tradewright:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
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
		if Tradewright.GetOpenCraftingOrder and Tradewright:GetOpenCraftingOrder() then
			return
		end
		rootDescription:CreateDivider()
		local inQueue = Tradewright.IsRecipeInCraftQueue
			and Tradewright:IsRecipeInCraftQueue(recipeID)
		if inQueue then
			rootDescription:CreateButton(L["Remove from queue"], function()
				if Tradewright.RemoveCraftQueueLinesForRecipeID then
					Tradewright:RemoveCraftQueueLinesForRecipeID(recipeID)
				end
				if Tradewright.ScheduleRefreshProfessionCraftEconomyPanel then
					Tradewright:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
				end
			end)
		else
			rootDescription:CreateButton(L["Add to queue"], function()
				if Tradewright.QueueOpenProfessionRecipe then
					Tradewright:QueueOpenProfessionRecipe(1, { recipeID = recipeID })
				end
			end)
		end
	end)
end

Tradewright.CraftingOrderMenus = {
	ensureCrafterOrderListContextMenuHook = ensureCrafterOrderListContextMenuHook,
	ensureRecipeListContextMenuHook = ensureRecipeListContextMenuHook,
}
