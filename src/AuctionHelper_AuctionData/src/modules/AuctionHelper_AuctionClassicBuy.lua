local _, AuctionHelper = ...

-- Buyouts in the classic auction house (WoW Forever), where the player buys in the game's own window.
-- A buyout is a bid at the buyout price; the game confirms it with its "You won an auction for …"
-- system message. The bought stack is then credited to the cart, so "Have" and "Buy" of the
-- shopping lists follow at once although the items wait in the mailbox. A refused bid gets no such
-- message and is dropped. Only watches what the player does; places no bids.

local AL = AuctionHelper.AuctionLogic

-- Buyouts waiting for the game's confirmation, oldest first: `{ { itemID, name, quantity } }`.
local pendingBuyouts = {}

local function noteBid(listType, index, bid)
	local name, _, count, _, _, _, _, _, _, buyoutPrice, _, _, _, _, _, _, itemID = GetAuctionItemInfo(listType, index)
	buyoutPrice = tonumber(buyoutPrice) or 0
	if itemID and name and buyoutPrice > 0 and (tonumber(bid) or 0) >= buyoutPrice then
		pendingBuyouts[#pendingBuyouts + 1] = { itemID = itemID, name = name, quantity = tonumber(count) or 1 }
	end
end

local function onSystemMessage(message)
	local itemName = #pendingBuyouts > 0 and AL.WonAuctionItemName(message, ERR_AUCTION_WON_S)
	local buyout = itemName and AL.TakeConfirmedBuyout(pendingBuyouts, itemName)
	if buyout and AuctionHelper.db then
		AuctionHelper:NoteAuctionCartPurchase(buyout.itemID, buyout.quantity, "classic_buyout")
		AuctionHelper:ScheduleAuctionCartPurchaseRefresh()
	end
end

if hooksecurefunc and PlaceAuctionBid and GetAuctionItemInfo then
	hooksecurefunc("PlaceAuctionBid", noteBid)
	local frame = CreateFrame("Frame")
	frame:SetScript("OnEvent", function(_, event, message)
		if event == "CHAT_MSG_SYSTEM" then
			onSystemMessage(message)
		else
			pendingBuyouts = {}
		end
	end)
	-- pcall: an event name the client does not know raises an error.
	for _, event in ipairs({ "CHAT_MSG_SYSTEM", "AUCTION_HOUSE_CLOSED" }) do
		pcall(frame.RegisterEvent, frame, event)
	end
end
