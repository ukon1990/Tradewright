local _, Tradewright = ...

-- Retail crafting-order view: opens queued orders in Blizzard's order view and adds the queue and paging buttons there.

if not Tradewright.IS_RETAIL then
	return
end

local CraftingOrderShared = Tradewright.CraftingOrderShared
local copyReagentsList = CraftingOrderShared.copyReagentsList
local copyOrderPayload = CraftingOrderShared.copyOrderPayload
local buildOrderFromQueueEntry = CraftingOrderShared.buildOrderFromQueueEntry
local getLiveCraftingOrderView = CraftingOrderShared.getLiveCraftingOrderView
local CraftingOrderMenus = Tradewright.CraftingOrderMenus
local ensureCrafterOrderListContextMenuHook = CraftingOrderMenus.ensureCrafterOrderListContextMenuHook
local ensureRecipeListContextMenuHook = CraftingOrderMenus.ensureRecipeListContextMenuHook

function Tradewright:FindLiveCraftingOrder(orderID)
	orderID = tonumber(orderID)
	if not orderID or not C_CraftingOrders then
		return nil
	end
	if C_CraftingOrders.GetClaimedOrder then
		local claimed = C_CraftingOrders.GetClaimedOrder()
		if claimed and tonumber(claimed.orderID) == orderID then
			return claimed
		end
	end
	if C_CraftingOrders.GetCrafterOrders then
		for _, order in ipairs(C_CraftingOrders.GetCrafterOrders() or {}) do
			if tonumber(order.orderID) == orderID then
				return order
			end
		end
	end
	return nil
end

local function ordersTabAvailable(pf)
	return C_CraftingOrders and C_CraftingOrders.ShouldShowCraftingOrderTab and C_CraftingOrders.ShouldShowCraftingOrderTab()
		and pf.isCraftingOrdersTabEnabled and pf.GetTabButton
end

-- Switches the professions window to the orders tab; returns whether it had to switch.
local function ensureOrdersTab(pf)
	if not ordersTabAvailable(pf) then
		return false
	end
	local ordersPage = pf.OrdersPage
	if ordersPage and ordersPage.IsVisible and ordersPage:IsVisible() then
		return false
	end
	local tabButton = pf:GetTabButton(3)
	if tabButton and tabButton.Click then
		tabButton:Click()
		return true
	end
	return false
end

local function showOrderInView(ordersPage, order)
	if ordersPage and type(ordersPage.ViewOrder) == "function" and pcall(ordersPage.ViewOrder, ordersPage, order) then
		return true
	end
	local orderView = ordersPage and ordersPage.OrderView
	if not (orderView and type(orderView.SetOrder) == "function" and pcall(orderView.SetOrder, orderView, order)) then
		return false
	end
	if orderView.Show then
		orderView:Show()
	end
	return true
end

local function applyOrder(self, pf, orderID, order)
	if not order or not showOrderInView(pf.OrdersPage, order) then
		self:PrintMessage(string.format("Could not open crafting order #%s in the orders UI.", tostring(orderID)))
		return false
	end
	if self._professionCraftPanel then
		self._professionCraftPanel._navOrderID = orderID
	end
	C_Timer.After(0, function()
		Tradewright:CraftingOrderViewRefreshButtons(getLiveCraftingOrderView(), order)
		if Tradewright.ScheduleRefreshProfessionCraftEconomyPanel then
			Tradewright:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
		end
	end)
	return true
end

function Tradewright:OpenCraftingOrderQueueEntry(entry)
	local orderID = type(entry) == "table" and tonumber(entry.orderID)
	if not orderID then
		return false
	end
	-- Prefer the stored queue entry: it carries the order payload after a reload.
	local stored = self:GetCraftingOrderQueueStorage()[tostring(orderID)]
	entry = type(stored) == "table" and stored or entry
	local pf = _G.ProfessionsFrame
	if not pf then
		self:PrintMessage(string.format("Open Professions to view crafting order #%s.", tostring(orderID)))
		return false
	end
	if not pf:IsShown() then
		ShowUIPanel(pf)
	end
	local delay = ensureOrdersTab(pf) and 0.20 or 0.05
	C_Timer.After(delay, function()
		applyOrder(self, pf, orderID, self:FindLiveCraftingOrder(orderID) or buildOrderFromQueueEntry(entry))
	end)
	return true
end

local function resolveCurrentQueuedOrderID(orderView, panel)
	local order = orderView and orderView.order
	local oid = order and tonumber(order.orderID)
	if oid then
		return oid
	end
	if panel and tonumber(panel._navOrderID) then
		return tonumber(panel._navOrderID)
	end
	if C_CraftingOrders and C_CraftingOrders.GetClaimedOrder then
		local claimed = C_CraftingOrders.GetClaimedOrder()
		if claimed and claimed.orderID then
			return tonumber(claimed.orderID)
		end
	end
	return nil
end

local _orderViewButtonsHooked

local function isOrdersPageActive()
	local pf = _G.ProfessionsFrame
	local ordersPage = pf and pf.OrdersPage
	return ordersPage and ordersPage.IsShown and ordersPage:IsShown()
end

local function getProfessionSidePanelOrderControls()
	if not Tradewright.EnsureProfessionCraftEconomyPanel then
		return nil
	end
	local panel = Tradewright:EnsureProfessionCraftEconomyPanel()
	if not panel or not panel.peAddToQueueBtn then
		return nil
	end
	return panel
end

local function layoutOrderQueueButtons(panel)
	if not panel or not panel.peAddToQueueBtn or not panel.orderNav then
		return
	end
	panel.peAddToQueueBtn:ClearAllPoints()
	panel.peAddToQueueBtn:SetPoint("TOPLEFT", panel.orderNav, "TOPLEFT", 0, 0)
	panel.peRemoveFromQueueBtn:ClearAllPoints()
	panel.peRemoveFromQueueBtn:SetPoint("LEFT", panel.peAddToQueueBtn, "RIGHT", 6, 0)
	if panel.pePrevOrderBtn then
		panel.pePrevOrderBtn:ClearAllPoints()
		panel.pePrevOrderBtn:SetPoint("TOPLEFT", panel.peAddToQueueBtn, "BOTTOMLEFT", 0, -4)
	end
	if panel.peNextOrderBtn then
		panel.peNextOrderBtn:ClearAllPoints()
		panel.peNextOrderBtn:SetPoint("LEFT", panel.pePrevOrderBtn, "RIGHT", 6, 0)
	end
	if panel.peQueueStatusText then
		panel.peQueueStatusText:ClearAllPoints()
		panel.peQueueStatusText:SetPoint("LEFT", panel.peNextOrderBtn or panel.pePrevOrderBtn or panel.peAddToQueueBtn, "RIGHT", 8, 0)
	end
end

function Tradewright:EnsureCraftingOrderViewActionButtons()
	local panel = getProfessionSidePanelOrderControls()
	if not panel then
		return
	end
	if panel.__ahOrderQueueControlsWired then
		return
	end
	panel.__ahOrderQueueControlsWired = true

	local function navigateCraftingOrderQueue(delta)
		local view = getLiveCraftingOrderView()
		local oid = resolveCurrentQueuedOrderID(view, panel)
		if not oid then
			Tradewright:PrintMessage("No crafting order selected to navigate from.")
			return
		end
		local nextEntry = Tradewright:GetAdjacentCraftingOrderQueueEntry(oid, delta)
		if nextEntry then
			Tradewright:OpenCraftingOrderQueueEntry(nextEntry)
		end
	end

	panel.pePrevOrderBtn:SetScript("OnClick", function()
		navigateCraftingOrderQueue(-1)
	end)
	panel.peNextOrderBtn:SetScript("OnClick", function()
		navigateCraftingOrderQueue(1)
	end)
end

local RECIPE_QUEUE_TIP = "Adds this recipe to Tradewright shopping. Reagents (including Enchanting Vellum for enchants) are included in the cart."
local ORDER_QUEUE_TIP = "Adds this crafting order to Tradewright shopping without starting the order. Only crafter-supplied reagents are included."

local function setOrderNavShown(panel, showOrderNav, showRecipeNav)
	if not panel.orderNav then
		return
	end
	panel.orderNav:SetShown((showOrderNav or showRecipeNav) and true or false)
	panel.orderNav:SetHeight((showRecipeNav and not showOrderNav) and 26 or 48)
end

local function layoutQueueCardBelowNav(panel, useNav)
	if not (panel.queueCard and panel.queueHost) then
		return
	end
	panel.queueCard:ClearAllPoints()
	if useNav and panel.orderNav then
		panel.queueCard:SetPoint("TOPLEFT", panel.orderNav, "BOTTOMLEFT", 0, -6)
	else
		panel.queueCard:SetPoint("TOPLEFT", panel.queueHost, "TOPLEFT", 0, 0)
	end
	panel.queueCard:SetPoint("TOPRIGHT", panel.queueHost, "TOPRIGHT", 0, 0)
	panel.queueCard:SetPoint("BOTTOMLEFT", panel.queueHost, "BOTTOMLEFT", 0, 30)
end

local function hideOrderPaging(panel)
	for _, key in ipairs({ "pePrevOrderBtn", "peNextOrderBtn", "peQueueStatusText" }) do
		if panel[key] then
			panel[key]:Hide()
		end
	end
end

local function showQueueToggle(panel, inQueue)
	panel.peAddToQueueBtn:SetShown(not inQueue)
	panel.peRemoveFromQueueBtn:SetShown(inQueue and true or false)
	panel.peAddToQueueBtn:SetEnabled(true)
	panel.peRemoveFromQueueBtn:SetEnabled(true)
end

local function setQueueButtonTooltip(button, text)
	button:SetScript("OnEnter", function(btn)
		GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
		GameTooltip:AddLine(Tradewright.DISPLAY_NAME, 1, 1, 1)
		GameTooltip:AddLine(text, 1, 0.9, 0.6, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
end

local function refreshRecipeQueueButtons(self, panel, recipeID)
	layoutQueueCardBelowNav(panel, true)
	layoutOrderQueueButtons(panel)
	hideOrderPaging(panel)
	showQueueToggle(panel, self.IsRecipeInCraftQueue and self:IsRecipeInCraftQueue(recipeID))
	setQueueButtonTooltip(panel.peAddToQueueBtn, RECIPE_QUEUE_TIP)
	panel.peAddToQueueBtn:SetScript("OnClick", function()
		if Tradewright.QueueOpenProfessionRecipe then
			Tradewright:QueueOpenProfessionRecipe(1, { recipeID = recipeID })
		end
		Tradewright:CraftingOrderViewRefreshButtons()
	end)
	panel.peRemoveFromQueueBtn:SetScript("OnClick", function()
		if Tradewright.RemoveCraftQueueLinesForRecipeID then
			Tradewright:RemoveCraftQueueLinesForRecipeID(recipeID)
		end
		if Tradewright.ScheduleRefreshProfessionCraftEconomyPanel then
			Tradewright:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
		end
		Tradewright:CraftingOrderViewRefreshButtons()
	end)
end

-- Keeps a queued order's saved copy in step with the live order being viewed.
local function syncQueuedOrderEntry(self, order, orderID)
	local stored = self:GetCraftingOrderQueueStorage()[tostring(orderID)]
	if type(stored) ~= "table" then
		return
	end
	stored.orderPayload = copyOrderPayload(order)
	stored.reagents = copyReagentsList(order.reagents) or stored.reagents
	stored.tipAmount = tonumber(order.tipAmount) or stored.tipAmount
	stored.spellID = tonumber(order.spellID) or stored.spellID
	stored.itemID = tonumber(order.itemID) or stored.itemID
	stored.crafterMatTotals = self:ExtractCrafterShoppingReagentsFromOrder(order)
	if self.UpsertCraftQueueForCraftingOrder then
		self:UpsertCraftQueueForCraftingOrder(stored)
	end
end

local function wireOrderQueueButtons(panel, order)
	setQueueButtonTooltip(panel.peAddToQueueBtn, ORDER_QUEUE_TIP)
	panel.peAddToQueueBtn:SetScript("OnClick", function()
		local live = getLiveCraftingOrderView()
		local o = (live and live.order) or order
		if o then
			Tradewright:PrintMessage(string.format("Queueing crafting order #%s...", tostring(o.orderID or "?")))
			Tradewright:AddCraftingOrderToQueue(o)
			Tradewright:CraftingOrderViewRefreshButtons(getLiveCraftingOrderView(), o)
		else
			Tradewright:PrintMessage("Crafting order button clicked, but no live order data was found.")
		end
	end)
	panel.peRemoveFromQueueBtn:SetScript("OnClick", function()
		local live = getLiveCraftingOrderView()
		local o = (live and live.order) or order
		if o and o.orderID then
			Tradewright:RemoveCraftingOrderFromQueue(o.orderID)
			Tradewright:CraftingOrderViewRefreshButtons(getLiveCraftingOrderView(), o)
		end
	end)
end

local function setPagingButton(button, shown, enabled)
	if button then
		button:SetShown(shown)
		button:SetEnabled(enabled)
	end
end

local function refreshOrderPaging(self, panel, orderID, inQueue)
	local idx, total = self:GetCraftingOrderQueueIndex(orderID)
	local showPaging = (total or 0) > 0 and inQueue
	local queued = inQueue and idx ~= nil
	setPagingButton(panel.pePrevOrderBtn, showPaging, queued and idx > 1)
	setPagingButton(panel.peNextOrderBtn, showPaging, queued and idx < total)
	local status = panel.peQueueStatusText
	if status and showPaging and idx then
		status:SetText(string.format("Queue %d/%d", idx, total))
		status:Show()
	elseif status then
		status:Hide()
	end
end

local function refreshOrderQueueButtons(self, panel, order)
	layoutQueueCardBelowNav(panel, true)
	layoutOrderQueueButtons(panel)
	local orderID = tonumber(order.orderID)
	panel._navOrderID = orderID
	local inQueue = self:IsCraftingOrderQueued(orderID)
	if inQueue then
		syncQueuedOrderEntry(self, order, orderID)
	end
	showQueueToggle(panel, inQueue)
	wireOrderQueueButtons(panel, order)
	panel.peAddToQueueBtn:Show()
	refreshOrderPaging(self, panel, orderID, inQueue)
end

function Tradewright:CraftingOrderViewRefreshButtons(orderView, order)
	orderView = orderView or getLiveCraftingOrderView()
	self:EnsureCraftingOrderViewActionButtons()
	local panel = getProfessionSidePanelOrderControls()
	order = order or (orderView and orderView.order) or nil
	if not panel or not panel.peAddToQueueBtn then
		return
	end
	local showOrderNav = isOrdersPageActive() and order and order.orderID
	local recipeID = (not showOrderNav) and self.GetOpenProfessionRecipeID and tonumber(self:GetOpenProfessionRecipeID()) or nil
	setOrderNavShown(panel, showOrderNav, recipeID ~= nil)
	if showOrderNav then
		refreshOrderQueueButtons(self, panel, order)
	elseif recipeID then
		refreshRecipeQueueButtons(self, panel, recipeID)
	else
		panel.peAddToQueueBtn:Hide()
		panel.peRemoveFromQueueBtn:Hide()
		hideOrderPaging(panel)
		layoutQueueCardBelowNav(panel, false)
	end
end

function Tradewright:HookLiveCraftingOrderView(orderView)
	if not orderView or orderView.__ahOrderButtonsHooked then
		return
	end
	orderView.__ahOrderButtonsHooked = true
	self:EnsureCraftingOrderViewActionButtons()
	if type(orderView.SetOrder) == "function" then
		hooksecurefunc(orderView, "SetOrder", function(view, order)
			C_Timer.After(0, function()
				Tradewright:CraftingOrderViewRefreshButtons(view, order)
				if Tradewright.ScheduleRefreshProfessionCraftEconomyPanel then
					Tradewright:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
				end
			end)
		end)
	end
	if orderView.HookScript then
		orderView:HookScript("OnShow", function(view)
			C_Timer.After(0, function()
				Tradewright:CraftingOrderViewRefreshButtons(view, view.order)
				if Tradewright.ScheduleRefreshProfessionCraftEconomyPanel then
					Tradewright:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
				end
			end)
		end)
		orderView:HookScript("OnHide", function()
			Tradewright:CraftingOrderViewRefreshButtons(getLiveCraftingOrderView(), nil)
		end)
	end
	local pf = _G.ProfessionsFrame
	local ordersPage = pf and pf.OrdersPage
	if ordersPage and type(ordersPage.ViewOrder) == "function" and not ordersPage.__ahViewOrderHooked then
		ordersPage.__ahViewOrderHooked = true
		hooksecurefunc(ordersPage, "ViewOrder", function(_, order)
			C_Timer.After(0, function()
				Tradewright:CraftingOrderViewRefreshButtons(getLiveCraftingOrderView(), order)
				if Tradewright.ScheduleRefreshProfessionCraftEconomyPanel then
					Tradewright:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
				end
			end)
		end)
	end
end

function Tradewright:InitCraftingOrdersMaterialsHooks()
	ensureCrafterOrderListContextMenuHook()
	ensureRecipeListContextMenuHook()
	if _orderViewButtonsHooked then
		local liveView = getLiveCraftingOrderView()
		if liveView then
			self:HookLiveCraftingOrderView(liveView)
		end
		return
	end
	_orderViewButtonsHooked = true
	local liveView = getLiveCraftingOrderView()
	if liveView then
		self:HookLiveCraftingOrderView(liveView)
	end
	local mixin = _G.ProfessionsCrafterOrderViewMixin
	if mixin and type(mixin.SetOrder) == "function" then
		hooksecurefunc(mixin, "SetOrder", function(orderView, order)
			C_Timer.After(0, function()
				Tradewright:HookLiveCraftingOrderView(orderView)
				Tradewright:CraftingOrderViewRefreshButtons(orderView, order)
			end)
		end)
	end
	C_Timer.After(0.5, function()
		local delayedView = getLiveCraftingOrderView()
		if delayedView then
			Tradewright:HookLiveCraftingOrderView(delayedView)
			Tradewright:CraftingOrderViewRefreshButtons(delayedView, delayedView.order)
		end
	end)
end
