local _, Tradewright = ...

-- Gold changes by source. Every change of the character's gold is filed under vendor,
-- quest, loot, auction, mail, trade or other, from the windows that were open and the events
-- around it, and added to per-day totals in `ledger.income[characterKey][day][source]`.
-- This only listens; it never acts for the player.

local IncomeLogic = Tradewright.IncomeLogic
local VENDOR_LOOK_BACK = 50

local context = { open = {}, closedAt = {}, at = {} }
local lastMoney

-- Window events: event -> { window, isOpen }.
local WINDOW_EVENTS = {
	MERCHANT_SHOW = { "merchant", true }, MERCHANT_CLOSED = { "merchant", false },
	TRADE_SHOW = { "trade", true }, TRADE_CLOSED = { "trade", false },
	AUCTION_HOUSE_SHOW = { "auctionHouse", true }, AUCTION_HOUSE_CLOSED = { "auctionHouse", false },
	MAIL_SHOW = { "mailbox", true }, MAIL_CLOSED = { "mailbox", false },
}
-- One-off events: event -> moment.
local MOMENT_EVENTS = { QUEST_TURNED_IN = "quest", CHAT_MSG_MONEY = "loot" }

-- The player's own "You create:" and "You receive loot:" lines, in the client's language.
-- The "x%d" forms come first so a stack is not read as a single item.
local ITEM_MESSAGES = {}
for _, entry in ipairs({
	{ LOOT_ITEM_CREATED_SELF_MULTIPLE, "craft" }, { LOOT_ITEM_CREATED_SELF, "craft" },
	{ LOOT_ITEM_SELF_MULTIPLE, "loot" }, { LOOT_ITEM_SELF, "loot" },
}) do
	if type(entry[1]) == "string" then
		ITEM_MESSAGES[#ITEM_MESSAGES + 1] = { IncomeLogic.FormatToPattern(entry[1]), entry[2] }
	end
end

-- Crafted and looted amounts per item and day, account-wide (items are mailed between
-- characters before they are sold): { [itemID] = { [day] = { craft = n, loot = n } } }.
local function acquiredStore()
	local L = Tradewright:InitLedger()
	if L then
		L.acquired = L.acquired or {}
		return L.acquired
	end
end

local function onItemMessage(message)
	local kind, itemID, quantity = IncomeLogic.ParseItemMessage(tostring(message or ""), ITEM_MESSAGES)
	local acquired = kind and acquiredStore()
	if acquired then
		IncomeLogic.AddAcquired(acquired, itemID, IncomeLogic.DayOf(time()), kind, quantity)
	end
end

local function pruneOldDays()
	local firstDay = IncomeLogic.DayOf(time()) - IncomeLogic.KEEP_DAYS
	local L = Tradewright:InitLedger()
	if L then
		IncomeLogic.PruneAllDays(L.income or {}, firstDay)
		IncomeLogic.PruneAllDays(L.acquired or {}, firstDay)
	end
end

local function incomeDays()
	local L = Tradewright:InitLedger()
	if not L then
		return nil
	end
	L.income = L.income or {}
	local key = Tradewright:GetCharacterKey()
	L.income[key] = L.income[key] or {}
	return L.income[key]
end

local function copy(map)
	local out = {}
	for key, value in pairs(map) do
		out[key] = value
	end
	return out
end

-- The source is decided a moment after the change, so an event that arrives just after the
-- gold (a quest turn-in, trade gold after the window closes) is still seen.
local function recordChange(delta)
	local changeAt, open = GetTime(), copy(context.open)
	C_Timer.After(IncomeLogic.EVENT_WINDOW, function()
		local days = incomeDays()
		if days then
			local source = IncomeLogic.ClassifyMoneyChange({ open = open, closedAt = context.closedAt, at = context.at }, changeAt)
			IncomeLogic.AddToDay(days, IncomeLogic.DayOf(time()), source, delta)
		end
	end)
end

local function onMoney()
	local money = GetMoney()
	if lastMoney and money ~= lastMoney then
		recordChange(money - lastMoney)
	end
	lastMoney = money
end

local function bagItem(bag, slot)
	if C_Container and C_Container.GetContainerItemInfo then
		local info = C_Container.GetContainerItemInfo(bag, slot)
		return info and info.itemID, info and info.stackCount
	end
	local _, count, _, _, _, _, _, _, _, itemID = GetContainerItemInfo(bag, slot)
	return itemID, count
end

-- Using a bag item while a merchant is open sells it. One ledger event per item and day.
local function onBagItemUsed(bag, slot)
	if not context.open.merchant then
		return
	end
	local itemID, count = bagItem(bag, slot)
	local price = itemID and select(11, (C_Item and C_Item.GetItemInfo or GetItemInfo)(itemID))
	if not price or price <= 0 or not count then
		return
	end
	local entry = {
		kind = "vendor", itemID = itemID, characterKey = Tradewright:GetCharacterKey(), ts = time(),
		quantity = count, unitCopper = price, totalCopper = price * count, source = "merchant",
	}
	local L = Tradewright:InitLedger()
	if L and not IncomeLogic.MergeIntoDayEvent(L.events, entry, VENDOR_LOOK_BACK) then
		Tradewright:LedgerAppendEvent(entry)
	end
end

-- Gold taken from an auction house mail (a sale or a cancelled bid) belongs to the auction house.
local function onInboxMoneyTaken(index)
	if GetInboxInvoiceInfo(index) then
		context.at.auctionMail = GetTime()
	end
end

local function onEvent(_, event, message)
	local window = WINDOW_EVENTS[event]
	if window then
		context.open[window[1]] = window[2] or nil
		if not window[2] then
			context.closedAt[window[1]] = GetTime()
		end
	elseif MOMENT_EVENTS[event] then
		context.at[MOMENT_EVENTS[event]] = GetTime()
	elseif event == "CHAT_MSG_LOOT" then
		onItemMessage(message)
	elseif event == "PLAYER_MONEY" then
		onMoney()
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- A baseline, not income: gold changed while logged out is not known here.
		lastMoney = GetMoney()
		pruneOldDays()
	end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", onEvent)
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_MONEY", "QUEST_TURNED_IN", "CHAT_MSG_MONEY", "CHAT_MSG_LOOT" }) do
	pcall(frame.RegisterEvent, frame, event)
end
for event in pairs(WINDOW_EVENTS) do
	pcall(frame.RegisterEvent, frame, event)
end

if hooksecurefunc then
	if C_Container and C_Container.UseContainerItem then
		hooksecurefunc(C_Container, "UseContainerItem", onBagItemUsed)
	elseif UseContainerItem then
		hooksecurefunc("UseContainerItem", onBagItemUsed)
	end
	if TakeInboxMoney and AutoLootMailItem then
		hooksecurefunc("TakeInboxMoney", onInboxMoneyTaken)
		hooksecurefunc("AutoLootMailItem", onInboxMoneyTaken)
	end
end

--- Every character's per-day totals: { [characterKey] = { [day] = { [source] = { gain, spend } } } }.
function Tradewright:GetIncomeDays()
	local L = self:InitLedger()
	return L and L.income or {}
end

--- Where each auction sale's units came from: { [sale event] = { origin = units } } (see
--- IncomeLogic.LabelSaleOrigins).
function Tradewright:GetSaleOrigins()
	local L = self:InitLedger()
	return IncomeLogic.LabelSaleOrigins(self:GetLedgerEvents(), L and L.acquired or {})
end
