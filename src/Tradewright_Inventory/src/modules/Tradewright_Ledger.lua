local _, Tradewright = ...

local MAX_EVENTS = 2500

--- Normalized transaction ledger (purchases, sales, crafts). Best-effort capture; many sources are not exposed by the WoW API.
--- Must not call InitDB (InitDB invokes InitLedger at the end — would recurse).
function Tradewright:InitLedger()
	local db = self.db or self:BuildMergedRuntimeDB(self.baseDb or {}, self.professionsDb or {}, self.inventoryDb or {}, self.auctionStorageDb or {})
	if type(db) ~= "table" then
		return nil
	end
	self.db = self.db or db
	db.ledger = db.ledger or {}
	local L = db.ledger
	L.version = L.version or 1
	L.events = L.events or {}
	return L
end

-- Kept between ledger changes: the cut is asked for once per priced row.
local measuredAuctionCut

--- The auction cut measured from the player's own sale mails: `{ cut, sales }`, `cut` nil until
--- enough sales are collected (see IncomeLogic.MeasureAuctionCut).
function Tradewright:LedgerMeasuredAuctionCut()
	if not measuredAuctionCut then
		local ledger = self:InitLedger()
		measuredAuctionCut = self.IncomeLogic.MeasureAuctionCut(ledger and ledger.events)
	end
	return measuredAuctionCut
end

local itemTallies

--- What the ledger knows about one item per event kind (see IncomeLogic.TallyByItem), or nil.
function Tradewright:GetLedgerItemTally(itemID)
	if not itemTallies then
		local ledger = self:InitLedger()
		itemTallies = self.IncomeLogic.TallyByItem(ledger and self:GetLedgerEvents(), ledger and ledger.rolledOff)
	end
	return itemTallies[itemID]
end

-- Keeps the ledger at its size limit; what leaves is kept as per-item totals.
local function dropOldestEvents(ledger)
	while #ledger.events > MAX_EVENTS do
		ledger.rolledOff = ledger.rolledOff or {}
		Tradewright.IncomeLogic.AddRolledOff(ledger.rolledOff, table.remove(ledger.events, 1))
	end
end

--- @param entry table { kind, ts, characterKey, itemID, itemName?, quantity, unitCopper, totalCopper, source, recipeID?, meta? }
--- An entry needs an itemID, or at least an itemName when the id could not be resolved.
function Tradewright:LedgerAppendEvent(entry)
	if type(entry) ~= "table" then
		return
	end
	local L = self:InitLedger()
	if not L then
		self:InitDB()
		L = self:InitLedger()
	end
	if not L then
		return
	end
	entry.ts = tonumber(entry.ts) or time()
	entry.kind = tostring(entry.kind or "unknown")
	entry.characterKey = entry.characterKey and tostring(entry.characterKey) or self:GetCharacterKey()
	entry.itemID = tonumber(entry.itemID)
	entry.quantity = math.max(0, tonumber(entry.quantity) or 0)
	entry.unitCopper = tonumber(entry.unitCopper)
	entry.totalCopper = tonumber(entry.totalCopper)
	entry.source = tostring(entry.source or "")
	if ((entry.itemID and entry.itemID > 0) or entry.itemName) and entry.quantity > 0 then
		table.insert(L.events, entry)
		measuredAuctionCut, itemTallies = nil, nil
	end
	dropOldestEvents(L)
end

-- Auction mails are read on every inbox update: sale invoices that still hold their gold, and won,
-- expired and cancelled auctions that still hold their item. Each is written to the ledger when the
-- player takes that gold or item, so it is counted once, however often the mailbox is opened.
local AUCTION_MAIL_DAYS = 30
local pendingMail = {}
local returnSubjects

-- The game's subject lines for auctions that came back unsold, as patterns.
local function auctionReturnSubjects()
	if not returnSubjects then
		returnSubjects = {}
		for kind, subject in pairs({ expired = AUCTION_EXPIRED_MAIL_SUBJECT, cancelled = AUCTION_REMOVED_MAIL_SUBJECT }) do
			returnSubjects[#returnSubjects + 1] = { Tradewright.IncomeLogic.FormatToPattern(subject), kind }
		end
	end
	return returnSubjects
end

local function readMail(index)
	local _, _, _, subject, money, _, daysLeft, itemCount = GetInboxHeaderInfo(index)
	local invoiceType, itemName, buyer, bid, _, deposit, consignment, _, _, _, count = GetInboxInvoiceInfo(index)
	local mail = {
		invoiceType = invoiceType, itemName = itemName, buyer = buyer, bid = bid, deposit = deposit,
		consignment = consignment, count = count, money = money, subject = subject,
		-- The mail was sent when the auction ended; its age comes from how long it has left.
		ageSeconds = math.min(AUCTION_MAIL_DAYS, AUCTION_MAIL_DAYS - (tonumber(daysLeft) or AUCTION_MAIL_DAYS)) * 86400,
	}
	if (tonumber(itemCount) or 0) > 0 and GetInboxItem then
		local name, itemID, _, stack = GetInboxItem(index, 1)
		mail.attachment = name and { name = name, itemID = itemID, count = stack } or nil
	end
	return mail
end

function Tradewright:OnMailInboxUpdate()
	wipe(pendingMail)
	for index = 1, GetInboxNumItems() do
		local event, settledBy = self.IncomeLogic.AuctionMailEvent(readMail(index), auctionReturnSubjects(), time())
		if event then
			event.itemID = event.itemID or self:ResolveItemIDByName(event.itemName)
			pendingMail[index] = { event = event, settledBy = settledBy }
		end
	end
end

-- `taken` is "money", "item", or nil when the whole mail is looted at once.
local function recordSettledMail(index, taken)
	local pending = pendingMail[index]
	if pending and (not taken or pending.settledBy == taken) then
		pendingMail[index] = nil
		Tradewright:LedgerAppendEvent(pending.event)
	end
end

if hooksecurefunc and TakeInboxMoney and AutoLootMailItem then
	hooksecurefunc("TakeInboxMoney", function(index) recordSettledMail(index, "money") end)
	hooksecurefunc("AutoLootMailItem", function(index) recordSettledMail(index) end)
	if TakeInboxItem then
		hooksecurefunc("TakeInboxItem", function(index) recordSettledMail(index, "item") end)
	end
end

local function itemIDsByName()
	local L = Tradewright:InitLedger()
	if L then
		L.itemIDsByName = L.itemIDsByName or {}
		return L.itemIDsByName
	end
end

local function lookupItemID(name)
	local getInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
	return getInstant and tonumber((getInstant(name)))
end

--- Remembers the name of an item the addon has shown, so a sale of it (whose mail names the item
--- but carries no id) still finds its icon after the item has left the client's cache.
function Tradewright:LearnItemName(itemID, name)
	local map = itemIDsByName()
	itemID = tonumber(itemID)
	if map and itemID and type(name) == "string" and name ~= "" then
		map[name] = itemID
	end
end

function Tradewright:ResolveItemIDByName(name)
	local map = itemIDsByName()
	return map and map[name] or lookupItemID(name)
end

-- Sale mails name the item but carry no id. Sales that have both teach the name map; the rest
-- take their id from it, or from the client when it still has the item cached.
local function fillMissingItemIDs(events, map)
	for _, event in ipairs(events) do
		if event.itemID and event.itemName then
			map[event.itemName] = map[event.itemName] or event.itemID
		end
	end
	for _, event in ipairs(events) do
		if not event.itemID and event.itemName then
			event.itemID = map[event.itemName] or lookupItemID(event.itemName)
		end
	end
end

--- The ledger's events, with the item ids of sales recorded by name filled in where known.
function Tradewright:GetLedgerEvents()
	local L = self:InitLedger()
	if not L then
		return {}
	end
	fillMissingItemIDs(L.events, itemIDsByName())
	return L.events
end

--- Sales statistics for the last `days` days (nil for all time); see IncomeLogic.SummarizeSales.
function Tradewright:GetSalesSummary(days)
	return self.IncomeLogic.SummarizeSales(self:GetLedgerEvents(), time(), days)
end

local function iterEvents(L, kind, itemID, characterKey)
	if type(L) ~= "table" or type(L.events) ~= "table" then
		return function() end
	end
	local i = 0
	local n = #L.events
	return function()
		while i < n do
			i = i + 1
			local e = L.events[i]
			if not e then
				return nil
			end
			local matches = not (kind and e.kind ~= kind)
				and not (itemID and tonumber(e.itemID) ~= itemID)
				and not (characterKey and e.characterKey ~= characterKey)
			if matches then
				return e
			end
		end
		return nil
	end
end

--- Weighted average unit copper for purchases of itemID (optional characterKey filter).
function Tradewright:LedgerAverageUnitBuyCopper(itemID, characterKey)
	local L = self:InitLedger()
	itemID = tonumber(itemID)
	if not itemID or not L then
		return nil, 0
	end
	local qty = 0
	local total = 0
	local n = 0
	for e in iterEvents(L, "buy", itemID, characterKey) do
		local q = tonumber(e.quantity) or 0
		local u = tonumber(e.unitCopper)
		if q > 0 and u and u > 0 then
			qty = qty + q
			total = total + q * u
			n = n + 1
		end
	end
	if qty <= 0 then
		return nil, n
	end
	return total / qty, n
end

function Tradewright:LedgerAverageUnitSellCopper(itemID, characterKey)
	local L = self:InitLedger()
	itemID = tonumber(itemID)
	if not itemID or not L then
		return nil, 0
	end
	local qty = 0
	local total = 0
	local n = 0
	for e in iterEvents(L, "sell", itemID, characterKey) do
		local q = tonumber(e.quantity) or 0
		local u = tonumber(e.unitCopper)
		if q > 0 and u and u > 0 then
			qty = qty + q
			total = total + q * u
			n = n + 1
		end
	end
	if qty <= 0 then
		return nil, n
	end
	return total / qty, n
end

function Tradewright:LedgerPurchaseStats(itemID, characterKey)
	local avg, count = self:LedgerAverageUnitBuyCopper(itemID, characterKey)
	local lastBuy, lastTs = nil, nil
	itemID = tonumber(itemID)
	if itemID then
		local L = self:InitLedger()
		if L then
			for e in iterEvents(L, "buy", itemID, characterKey) do
				local u = tonumber(e.unitCopper)
				if u and u > 0 then
					lastBuy = u
					lastTs = tonumber(e.ts) or lastTs
				end
			end
		end
	end
	return {
		averageUnit = avg,
		observationCount = count,
		lastUnit = lastBuy,
		lastAt = lastTs,
	}
end

function Tradewright:LedgerSaleStats(itemID, characterKey)
	local avg, count = self:LedgerAverageUnitSellCopper(itemID, characterKey)
	local lastSell, lastTs = nil, nil
	itemID = tonumber(itemID)
	if itemID then
		local L = self:InitLedger()
		if L then
			for e in iterEvents(L, "sell", itemID, characterKey) do
				local u = tonumber(e.unitCopper)
				if u and u > 0 then
					lastSell = u
					lastTs = tonumber(e.ts) or lastTs
				end
			end
		end
	end
	return {
		averageUnit = avg,
		observationCount = count,
		lastUnit = lastSell,
		lastAt = lastTs,
	}
end
