-- The cart tab of the AH panel: summary, search box, buy and remove buttons and the reagent table.
local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
local shared = Tradewright.AuctionShared
local attachSimpleTooltip = shared.attachSimpleTooltip
local panelButton = shared.panelButton

local function searchSelectedCartRow(panel)
	local rows = panel.cartTable and panel.cartTable.rows or nil
	local selected = Tradewright:GetState().auctionCartSelectedItemID
	if selected then
		Tradewright:SearchAuctionCartRow({ itemID = selected })
	elseif type(rows) == "table" and #rows > 0 then
		Tradewright:SearchAuctionCartRow(rows[1])
	end
end

local function priceAllCartRows()
	local rows = Tradewright:FilterAuctionCraftCartRows(select(1, Tradewright:BuildAuctionCraftCartRows()))
	Tradewright:SearchAuctionCartRows(rows)
end

-- Selected cart item, or the first shown cart row when nothing is selected.
local function selectedOrFirstCartItemID(panel)
	local selected = Tradewright:GetState().auctionCartSelectedItemID
	if not selected and panel.cartTable and panel.cartTable.rows then
		local rows = panel.cartTable.rows or {}
		selected = rows[1] and rows[1].itemID or nil
	end
	return selected
end

local function buyCheapestCartSelection(panel)
	local selected = selectedOrFirstCartItemID(panel)
	if not selected then
		Tradewright:PrintMessage(L["Select a cart row first."])
		return
	end
	local rows = Tradewright:FilterAuctionCraftCartRows(select(1, Tradewright:BuildAuctionCraftCartRows()))
	for _, row in ipairs(rows) do
		if tonumber(row.itemID) == tonumber(selected) then
			Tradewright:TryBuyAuctionCartRow(row)
			break
		end
	end
end

local function removeSelectedCartSources()
	local selected = Tradewright:GetState().auctionCartSelectedItemID
	if not selected then
		Tradewright:PrintMessage(L["Select a cart row first."])
		return
	end
	local pe = Tradewright
	local removedCrafts = pe.RemoveCraftQueueLinesByReagentItem and pe:RemoveCraftQueueLinesByReagentItem(selected) or 0
	local removedOrders = pe.RemoveCraftingOrdersByReagentItem and pe:RemoveCraftingOrdersByReagentItem(selected) or 0
	if (removedCrafts + removedOrders) > 0 then
		pe:PrintMessage(string.format(
			L["Removed %d queued crafts and %d crafting orders that needed item #%s."],
			removedCrafts, removedOrders, tostring(selected)
		))
	else
		pe:PrintMessage(L["Nothing in the queue needs the selected item."])
	end
	pe:GetState().auctionCartSelectedItemID = nil
	pe:RefreshAuctionHousePanel()
end

local function clearCartSources()
	if Tradewright.ClearCraftQueue then
		Tradewright:ClearCraftQueue()
	end
	if Tradewright.ClearCraftingOrderQueue then
		Tradewright:ClearCraftingOrderQueue()
	end
	Tradewright:GetState().auctionCartSelectedItemID = nil
	Tradewright:PrintMessage(L["Cart and craft queue cleared."])
	Tradewright:RefreshAuctionHousePanel()
end

-- Cart summary line and the search box that filters cart rows.
local function buildCartHeader(panel, title)
	panel.cartSummary = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.cartSummary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	panel.cartSummary:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
	panel.cartSummary:SetJustifyH("LEFT")
	panel.cartSummary:SetWordWrap(true)
	panel.cartSummary:Hide()
	panel.cartSearchBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
	panel.cartSearchBox:SetSize(140, 20)
	panel.cartSearchBox:SetAutoFocus(false)
	panel.cartSearchBox:SetPoint("TOPLEFT", panel.cartSummary, "BOTTOMLEFT", 0, -8)
	panel.cartSearchBox:SetScript("OnTextChanged", function(box)
		Tradewright.ui = Tradewright.ui or {}
		Tradewright.ui.auctionCartFilterText = box:GetText() or ""
		Tradewright:RefreshAuctionHousePanel()
	end)
	panel.cartSearchBox:Hide()
end

-- Cart-tab button, hidden until the refresh shows the cart tab.
local function cartButton(panel, size, text, point, onClick)
	local button = panelButton(panel, size, text, point, onClick)
	button:Hide()
	return button
end

local function buildCartButtons(panel)
	panel.btnCartSearch = cartButton(panel, { 58, 20 }, L["Find selected"], { "LEFT", panel.cartSearchBox, "RIGHT", 4, 0 }, function()
		searchSelectedCartRow(panel)
	end)
	attachSimpleTooltip(panel.btnCartSearch, L["Find selected"], L["Searches the auction house for the selected cart row and updates its price."])
	panel.btnCartRefresh = cartButton(panel, { 64, 20 }, L["Check all"], { "LEFT", panel.btnCartSearch, "RIGHT", 4, 0 }, priceAllCartRows)
	attachSimpleTooltip(panel.btnCartRefresh, L["Check all"], L["Looks up the price of every cart row that still has something to buy."])
	panel.btnCartBuy = cartButton(panel, { 86, 20 }, L["Buy cheapest"], { "TOPLEFT", panel.cartSearchBox, "BOTTOMLEFT", 0, -6 }, function()
		buyCheapestCartSelection(panel)
	end)
	attachSimpleTooltip(panel.btnCartBuy, L["Buy cheapest"],
		L["Buys the selected row at the cheapest price found."])
	panel.btnCartRemove = cartButton(panel, { 70, 20 }, L["Remove selected"], { "LEFT", panel.btnCartBuy, "RIGHT", 4, 0 }, removeSelectedCartSources)
	attachSimpleTooltip(panel.btnCartRemove, L["Remove selected"],
		L["Removes the crafts that need the selected item from the queue."])
	panel.btnCartClear = cartButton(panel, { 56, 20 }, L["Clear cart"], { "LEFT", panel.btnCartRemove, "RIGHT", 4, 0 }, clearCartSources)
	attachSimpleTooltip(panel.btnCartClear, L["Clear cart"], L["Empties the craft queue, and the cart with it."])
end

local function appendCartMailLines(pe, lines, mailAllocations)
	for _, alloc in ipairs(type(mailAllocations) == "table" and mailAllocations or {}) do
		if (tonumber(alloc.mailQuantity) or 0) > 0 then
			lines[#lines + 1] = { string.format(L["Mail to %s"], tostring(alloc.characterKey)), pe:FormatNumberGrouped(alloc.mailQuantity) }
		end
	end
end

local function showCartRowTooltip(rowFrame, rowData)
	if not rowData or not rowData.itemID then
		return
	end
	local pe = Tradewright
	local lines = {
		{ "Need", pe:FormatNumberGrouped(rowData.quantityNeeded or 0) },
		{ L["Have here"], pe:FormatNumberGrouped(rowData.quantityOnCharacter or rowData.quantityHave or 0) },
		{ "Buy", pe:FormatNumberGrouped(rowData.quantityToBuy or 0) },
		{ L["Cost to buy"], rowData.estimatedBuyCost and pe:FormatCopperFull(rowData.estimatedBuyCost) or L["no price yet"] },
	}
	appendCartMailLines(pe, lines, rowData.mailAllocations)
	pe:ShowItemRowTooltip(rowFrame, rowData.itemID, lines, pe:AppendCartSourceLines(lines, rowData, L["Click to find it at the auction house"]))
end

local function buildCartTable(self, panel)
	panel.cartTableHost = CreateFrame("Frame", nil, panel)
	panel.cartTableHost:SetPoint("TOPLEFT", panel.btnCartBuy, "BOTTOMLEFT", 0, -8)
	panel.cartTableHost:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 52)
	panel.cartTableHost:Hide()
	panel.cartTable = self:CreateReusableTable(panel.cartTableHost, {
		rowHeight = 36,
		footer = true,
		emptyTitle = L["Cart is empty"],
		emptyHint = L["Queue crafts to add their reagents here."],
		isRowSelected = function(rowData)
			return rowData and rowData.itemID ~= nil and rowData.itemID == Tradewright:GetState().auctionCartSelectedItemID
		end,
		maxRows = 120,
		sortKey = "quantityToBuy",
		sortAsc = false,
		autoFitToScroll = true,
		onRowEnter = showCartRowTooltip,
		onRowLeave = function()
			GameTooltip:Hide()
		end,
		onRowClick = function(_, rowData, button)
			Tradewright:GetState().auctionCartSelectedItemID = rowData and rowData.itemID or nil
			if button == "RightButton" and rowData then
				Tradewright:ShowItemSourceWaypoint(rowData.itemID)
			else
				Tradewright:SearchAuctionCartRow(rowData)
			end
			Tradewright:RefreshAuctionHousePanel()
		end,
	})
	if panel.cartTable and panel.cartTable.frame then
		panel.cartTable.frame:ClearAllPoints()
		panel.cartTable.frame:SetPoint("TOPLEFT", panel.cartTableHost, "TOPLEFT", 0, 0)
		panel.cartTable.frame:SetPoint("BOTTOMRIGHT", panel.cartTableHost, "BOTTOMRIGHT", 0, 0)
		panel.cartTable:SetColumns(self:BuildAuctionCartColumns())
	end
end

-- Cart tab: reagent summary, search, buy/remove/clear actions and the reagent table (hidden until shown).
function Tradewright:BuildAuctionPanelCartTab(panel, title)
	buildCartHeader(panel, title)
	buildCartButtons(panel)
	buildCartTable(self, panel)
end
