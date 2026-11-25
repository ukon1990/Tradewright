-- The game's sell frame: placing a bag item in it and finding its post button.
local _, Tradewright = ...

local shared = Tradewright.AuctionShared
local normalizeItemID = shared.normalizeItemID

-- Sets the sell frame's quantity to all the player can post of the item, as its Max button does.
local function fillWholeQuantity(sellFrame)
	if type(sellFrame.SetToMaxQuantity) == "function" then
		pcall(sellFrame.SetToMaxQuantity, sellFrame)
		return
	end
	local maxButton = sellFrame.QuantityInput and sellFrame.QuantityInput.MaxButton
	if maxButton and maxButton.Click then
		maxButton:Click()
	end
end

-- Modern sell frame (retail and Forever): SetPostItem is what a bag right-click calls. It opens
-- the Sell tab on the item or commodity pane, and returns silently when the item can't be sold
-- or its data isn't loaded, so success is read back from the sell frames.
local function placeInSellFrame(pe, ah, bag, slot)
	if not (ItemLocation and ItemLocation.CreateFromBagAndSlot) then
		return false
	end
	local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
	if not pcall(ah.SetPostItem, ah, loc) then
		return false
	end
	for _, sellFrame in ipairs({ ah.ItemSellFrame, ah.CommoditiesSellFrame }) do
		if sellFrame.GetItem and sellFrame:GetItem() == loc then
			if pe:GetSetting("auction.postFullQuantity", true) ~= false then
				fillWholeQuantity(sellFrame)
			end
			return true
		end
	end
	return false
end

function Tradewright:TrySendItemToAuctionSellFrame(itemID, bag, slot)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return false
	end
	if not bag or not slot then
		bag, slot = self:GetAuctionRepresentativeBagSlot(itemID)
	end
	bag = tonumber(bag)
	slot = tonumber(slot)
	if bag == nil or slot == nil then
		return false
	end
	if C_Container and C_Container.GetContainerItemID then
		local bagItemID = normalizeItemID(C_Container.GetContainerItemID(bag, slot))
		if bagItemID ~= itemID then
			bag, slot = self:GetAuctionRepresentativeBagSlot(itemID, self.GetAuctionOwnedBagState and self:GetAuctionOwnedBagState(true) or nil)
			bag = tonumber(bag)
			slot = tonumber(slot)
			if bag == nil or slot == nil then
				return false
			end
			bagItemID = normalizeItemID(C_Container.GetContainerItemID(bag, slot))
			if bagItemID ~= itemID then
				return false
			end
		end
	end

	local ah = _G.AuctionHouseFrame
	local hasSetPostItem = ah and type(ah.SetPostItem) == "function" and true or false

	if hasSetPostItem and placeInSellFrame(self, ah, bag, slot) then
		return true
	end

	-- Classic cursor inject. Do not use on true retail when the modern sell frame exists
	-- (Blizzard sell frame can hard-error on stale cursor placements during auto-refresh).
	local shouldClassic = self.AuctionLogic
		and self.AuctionLogic.ShouldUseClassicSellInject
		and self.AuctionLogic.ShouldUseClassicSellInject(self.IS_FOREVER == true, hasSetPostItem)
	if not shouldClassic then
		ClearCursor()
		return false
	end

	local ahOpen = self.IsAuctionHouseFrameOpen and self:IsAuctionHouseFrameOpen()
	if not ahOpen then
		ClearCursor()
		return false
	end
	if type(ClickAuctionSellItemButton) ~= "function" then
		ClearCursor()
		return false
	end
	local pickup = (C_Container and C_Container.PickupContainerItem) or _G.PickupContainerItem
	if type(pickup) ~= "function" then
		ClearCursor()
		return false
	end

	-- Ensure classic Auctions tab is active when present.
	local auctionsTab = _G.AuctionFrameTab3
	if auctionsTab and type(AuctionFrameTab_OnClick) == "function" then
		pcall(AuctionFrameTab_OnClick, auctionsTab, 3)
	elseif auctionsTab and auctionsTab.Click then
		pcall(auctionsTab.Click, auctionsTab)
	end

	ClearCursor()
	local picked = pcall(pickup, bag, slot)
	if not picked then
		ClearCursor()
		return false
	end
	local clicked = pcall(ClickAuctionSellItemButton)
	ClearCursor()
	return clicked == true
end

local POST_BUTTON_KEYS = { "PostButton", "CreateAuctionButton" }

-- IsVisible, not IsShown: the hidden pane's button still reports itself as shown.
local function visibleButton(button)
	if type(button) == "table" and button.IsVisible and button:IsVisible() and button.Click then
		return button
	end
	return nil
end

function Tradewright:GetAuctionPostButton()
	local ah = _G.AuctionHouseFrame
	if not ah then
		return nil
	end
	local commodities, items = ah.CommoditiesSellFrame, ah.ItemSellFrame
	local sellFrames = { commodities, items, commodities and commodities.SaleFrame, items and items.SaleFrame }
	for index = 1, 4 do -- not ipairs: a missing frame leaves a nil hole in the list
		local button = self:FirstValueFrom(sellFrames[index], nil, POST_BUTTON_KEYS, visibleButton)
		if button then
			return button
		end
	end
	return nil
end

function Tradewright:TryClickAuctionPostButton()
	local button = self:GetAuctionPostButton()
	if button and button.IsEnabled and button:IsEnabled() and button.Click then
		button:Click()
		return true
	end
	return false
end
