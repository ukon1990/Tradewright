-- The game's sell frame: placing a bag item in it and finding its post button.
local _, AuctionHelper = ...

local shared = AuctionHelper.AuctionShared
local normalizeItemID = shared.normalizeItemID

function AuctionHelper:TrySendItemToAuctionSellFrame(itemID, bag, slot)
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

	-- Modern sell frame (retail and Forever): SetPostItem is what a bag right-click calls. It opens
	-- the Sell tab on the item or commodity pane, and returns silently when the item can't be sold
	-- or its data isn't loaded, so success is read back from the sell frames.
	if hasSetPostItem and ItemLocation and ItemLocation.CreateFromBagAndSlot then
		local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
		if pcall(ah.SetPostItem, ah, loc) then
			for _, sellFrame in ipairs({ ah.ItemSellFrame, ah.CommoditiesSellFrame }) do
				if sellFrame.GetItem and sellFrame:GetItem() == loc then
					return true
				end
			end
		end
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

function AuctionHelper:GetAuctionPostButton()
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

function AuctionHelper:TryClickAuctionPostButton()
	local button = self:GetAuctionPostButton()
	if button and button.IsEnabled and button:IsEnabled() and button.Click then
		button:Click()
		return true
	end
	return false
end
