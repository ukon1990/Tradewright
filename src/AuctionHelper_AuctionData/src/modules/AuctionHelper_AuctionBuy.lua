-- Finding an item in the open auction house for the player to buy: browse search, result pick and buy quantity.
local _, AuctionHelper = ...

local shared = AuctionHelper.AuctionShared
local normalizeItemID = shared.normalizeItemID

-- The buy frame fills in over a few frames, so the quantity is set again at each of these delays.
local PREFILL_QUANTITY_DELAYS_SEC = { 0, 0.1, 0.25 }
local SEARCH_AGAIN_AFTER_BUY_SEC = 0.6 -- the result list shows what is left
local BUY_AFTER_SEARCH_SEC = 0.75 -- the search results arrive first

function AuctionHelper:PauseAuctionScanForManualBuy(reason)
	local state = self:GetState()
	if state.auctionRefreshRunning == true and state.auctionRefreshPaused ~= true then
		state.auctionRefreshPaused = true
		self:DebugLog("AH", "scan paused for manual buy", {
			string.format("reason=%s mode=%s itemID=%s", tostring(reason or "manual_buy"), tostring(state.auctionScanMode), tostring(state.auctionActiveItemID)),
		})
		if self.RefreshAuctionHousePanel then
			self:RefreshAuctionHousePanel()
		end
		return true
	end
	return false
end

function AuctionHelper:TryPrefillAuctionBuyQuantity(quantity)
	quantity = math.max(1, math.floor(tonumber(quantity) or 0))
	if quantity <= 0 then
		return false
	end
	local ah = _G.AuctionHouseFrame
	if not ah then
		return false
	end
	local candidates = {
		ah.CommoditiesBuyFrame and ah.CommoditiesBuyFrame.BuyDisplay and ah.CommoditiesBuyFrame.BuyDisplay.QuantityInput
			and ah.CommoditiesBuyFrame.BuyDisplay.QuantityInput.InputBox,
		ah.ItemBuyFrame and ah.ItemBuyFrame.QuantityInput and ah.ItemBuyFrame.QuantityInput.InputBox,
	}
	for _, input in ipairs(candidates) do
		if input and input.IsShown and input:IsShown() and input.SetText then
			input:SetText(tostring(quantity))
			if input.OnTextChanged then
				pcall(input.OnTextChanged, input, true)
			elseif input.GetScript and input:GetScript("OnTextChanged") then
				pcall(input:GetScript("OnTextChanged"), input, true)
			end
			if input.ClearFocus then
				input:ClearFocus()
			end
			return true
		end
	end
	return false
end

function AuctionHelper:OpenAuctionBrowseSearchForItem(itemID, itemName, quantity)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return false
	end
	local ah = _G.AuctionHouseFrame
	if not ah or not ah.IsShown or not ah:IsShown() then
		return false
	end
	if ah.SetDisplayMode then
		local buyMode = Enum and Enum.AuctionHouseFrameDisplayMode and Enum.AuctionHouseFrameDisplayMode.Buy
			or _G.AuctionHouseFrameDisplayMode and _G.AuctionHouseFrameDisplayMode.Buy
		if buyMode then
			pcall(ah.SetDisplayMode, ah, buyMode)
		end
	end
	itemName = tostring(itemName or self:GetItemDisplayName(itemID) or "")
	if itemName == "" or itemName == "?" then
		return false
	end
	local state = self:GetState()
	state.auctionPendingBrowseSearch = {
		itemID = itemID,
		itemName = itemName,
		quantity = math.max(1, math.floor(tonumber(quantity) or 1)),
		startedAt = GetTime and GetTime() or 0,
	}
	if C_AuctionHouse and C_AuctionHouse.SendBrowseQuery then
		local ok = pcall(C_AuctionHouse.SendBrowseQuery, {
			searchString = itemName,
			sorts = {},
			filters = {},
			itemClassFilters = {},
		})
		return ok == true
	end
	if ah.SendBrowseQuery then
		local ok = pcall(ah.SendBrowseQuery, ah, itemName, 0, 0, { 4, 5, 6, 7, 8, 10, 9 })
		return ok == true
	end
	return false
end

local function prefillBuyQuantitySoon(quantity)
	for _, delay in ipairs(PREFILL_QUANTITY_DELAYS_SEC) do
		C_Timer.After(delay, function()
			AuctionHelper:TryPrefillAuctionBuyQuantity(quantity)
		end)
	end
end

function AuctionHelper:TrySelectPendingAuctionBrowseResult()
	local state = self:GetState()
	local pending = state and state.auctionPendingBrowseSearch or nil
	if not pending then
		return false
	end
	local ah = _G.AuctionHouseFrame
	if not ah or not ah.SelectBrowseResult or not (C_AuctionHouse and C_AuctionHouse.GetBrowseResults) then
		return false
	end
	local results = C_AuctionHouse.GetBrowseResults() or {}
	local match = nil
	for _, result in ipairs(results) do
		local resultItemID = normalizeItemID(result and result.itemKey and result.itemKey.itemID)
		if tonumber(resultItemID) == tonumber(pending.itemID) then
			match = result
			break
		end
	end
	if not match then
		return false
	end
	local ok = pcall(ah.SelectBrowseResult, ah, match)
	if ok == true then
		state.auctionLastSellSelectionItemID = pending.itemID
		state.auctionCartSelectedItemID = pending.itemID
		local qty = tonumber(pending.quantity) or 1
		prefillBuyQuantitySoon(qty)
		state.auctionPendingBrowseSearch = nil
		return true
	end
	return false
end

-- Classic AuctionFrame: Browse tab, item name in the search box, run the browse search.
local function searchClassicAuctionFrame(itemName)
	local frame, nameBox = _G.AuctionFrame, _G.BrowseName
	if not (frame and frame:IsShown() and nameBox and type(AuctionFrameBrowse_Search) == "function") then
		return false
	end
	if _G.AuctionFrameTab1 and type(AuctionFrameTab_OnClick) == "function" then
		pcall(AuctionFrameTab_OnClick, _G.AuctionFrameTab1, 1)
	end
	nameBox:SetText(itemName)
	if type(CanSendAuctionQuery) == "function" and not CanSendAuctionQuery() then
		return false
	end
	return pcall(AuctionFrameBrowse_Search) == true
end

--- Show an item's buy page in the open auction house. Searches only; buying stays a player click.
function AuctionHelper:OpenItemInAuctionHouse(itemID)
	itemID = normalizeItemID(itemID)
	if not itemID or not self:IsAuctionHouseFrameOpen() then
		return false
	end
	local desc = self:ResolveItemDescriptor(itemID)
	local itemName = desc and desc.name
	if not itemName or itemName == "" then
		self:GetItemDisplayName(itemID) -- asks the client to load the item for the next click
		self:PrintMessage("Item info is still loading. Click again in a moment.")
		return false
	end
	self:PauseAuctionScanForManualBuy("dashboard_buy")
	local ok = self:OpenAuctionBrowseSearchForItem(itemID, itemName, 1) or searchClassicAuctionFrame(itemName)
	if not ok then
		self:PrintMessage(string.format("Could not search the auction house for %s right now. Try again in a moment.", itemName))
	end
	return ok
end

function AuctionHelper:SearchAuctionCartRow(row)
	row = type(row) == "table" and row or nil
	self:PauseAuctionScanForManualBuy("cart_search")
	local itemID = normalizeItemID(row and row.itemID or self:GetState().auctionCartSelectedItemID)
	if not itemID then
		return false
	end
	self:GetState().auctionCartSelectedItemID = itemID
	self:GetState().auctionLastSellSelectionItemID = itemID
	local itemName = row and (row.itemName or row.name) or self:GetItemDisplayName(itemID)
	local quantity = math.max(1, math.floor(tonumber(row and (row.quantityToBuy or row.quantity)) or 1))
	if self:OpenAuctionBrowseSearchForItem(itemID, itemName, quantity) then
		return true
	end
	return self:SendAuctionPanelSearchQuery(itemID, nil)
end

function AuctionHelper:SearchAuctionCartRows(rows)
	local ids = {}
	for _, row in ipairs(rows or {}) do
		local itemID = normalizeItemID(row and row.itemID)
		if itemID and (tonumber(row and row.quantityToBuy) or 0) > 0 then
			ids[#ids + 1] = itemID
		end
	end
	if #ids == 0 or not self:CanStartFullAuctionSideActions(true) then
		return false
	end
	self:QueueVisibleAuctionRefresh(ids)
	return true
end

function AuctionHelper:TryBuyAuctionCartRow(row)
	if not self.IS_RETAIL then -- Forever may expose the commodity purchase API, but buying is retail-only.
		return false
	end
	self:PauseAuctionScanForManualBuy("cart_buy")
	local itemID = normalizeItemID(row and row.itemID or self:GetState().auctionCartSelectedItemID)
	local quantity = math.max(1, math.floor(tonumber(row and row.quantityToBuy) or 0))
	if not itemID or quantity <= 0 then
		self:PrintMessage("Select a shopping-cart row with something left to buy.")
		return false
	end
	self:GetState().auctionCartSelectedItemID = itemID
	local function attemptPurchase()
		local searchAggregate = self:GetLiveAuctionSearchAggregate(itemID, nil)
		if not searchAggregate then
			self:PrintMessage("No live search results yet for that reagent.")
			return false
		end
		if searchAggregate.kind ~= "commodity" then
			self:PrintMessage("Auto-buy is currently limited to commodity reagents. Search results are ready in the Blizzard AH.")
			return false
		end
		if not (C_AuctionHouse and C_AuctionHouse.StartCommoditiesPurchase and C_AuctionHouse.ConfirmCommoditiesPurchase) then
			self:PrintMessage("Commodity buy API not available on this client.")
			return false
		end
		if not pcall(C_AuctionHouse.StartCommoditiesPurchase, itemID, quantity) then
			self:PrintMessage("Could not start commodity purchase.")
			return false
		end
		if not pcall(C_AuctionHouse.ConfirmCommoditiesPurchase, itemID, quantity) then
			self:PrintMessage("Commodity purchase confirmation failed.")
			return false
		end
		self:PrintMessage(string.format("Buying %s x%s.", self:GetItemDisplayName(itemID), self:FormatNumberGrouped(quantity)))
		self:ScheduleAuctionCartPurchaseRefresh()
		C_Timer.After(SEARCH_AGAIN_AFTER_BUY_SEC, function()
			AuctionHelper:SearchAuctionCartRow({ itemID = itemID })
			AuctionHelper:RefreshAuctionHousePanel()
		end)
		return true
	end
	if self:SearchAuctionCartRow({ itemID = itemID }) then
		C_Timer.After(BUY_AFTER_SEARCH_SEC, attemptPurchase)
		return true
	end
	return attemptPurchase()
end
