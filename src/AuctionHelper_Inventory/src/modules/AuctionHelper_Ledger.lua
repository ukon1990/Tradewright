local _, ProfessionExporter = ...

local MAX_EVENTS = 2500

--- Normalized transaction ledger (purchases, sales, crafts). Best-effort capture; many sources are not exposed by the WoW API.
--- Must not call InitDB (InitDB invokes InitLedger at the end — would recurse).
function ProfessionExporter:InitLedger()
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

--- @param entry table { kind, ts, characterKey, itemID, itemName?, quantity, unitCopper, totalCopper, source, recipeID?, meta? }
--- An entry needs an itemID, or at least an itemName when the id could not be resolved.
function ProfessionExporter:LedgerAppendEvent(entry)
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
	end
	while #L.events > MAX_EVENTS do
		table.remove(L.events, 1)
	end
end

-- Auction sales are read from the auction house's sale mails. Every inbox update lists the sale
-- invoices that still hold their gold; a sale is written to the ledger when that gold is taken,
-- so each one is counted once, however often the mailbox is opened.
local AUCTION_MAIL_DAYS = 30
local pendingSales = {}

function ProfessionExporter:OnMailInboxUpdate()
	wipe(pendingSales)
	for index = 1, GetInboxNumItems() do
		local _, _, _, _, money, _, daysLeft = GetInboxHeaderInfo(index)
		local invoiceType, itemName, buyer, bid, _, _, consignment, _, _, _, count = GetInboxInvoiceInfo(index)
		if invoiceType == "seller" and itemName and (tonumber(money) or 0) > 0 and (tonumber(bid) or 0) > 0 then
			local quantity = math.max(1, tonumber(count) or 1)
			-- The mail was sent when the sale paid out; its age comes from how long it has left.
			local age = (AUCTION_MAIL_DAYS - (tonumber(daysLeft) or AUCTION_MAIL_DAYS)) * 86400
			pendingSales[index] = {
				kind = "sell",
				ts = time() - math.max(0, math.min(AUCTION_MAIL_DAYS * 86400, age)),
				itemID = (C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant)(itemName),
				itemName = itemName,
				quantity = quantity,
				unitCopper = bid / quantity,
				totalCopper = bid,
				netCopper = bid - (tonumber(consignment) or 0),
				buyer = buyer,
				source = "mail",
			}
		end
	end
end

local function recordCollectedSale(index)
	local sale = pendingSales[index]
	if sale then
		pendingSales[index] = nil
		ProfessionExporter:LedgerAppendEvent(sale)
	end
end

if hooksecurefunc and TakeInboxMoney and AutoLootMailItem then
	hooksecurefunc("TakeInboxMoney", recordCollectedSale)
	hooksecurefunc("AutoLootMailItem", recordCollectedSale)
end

--- Sales statistics for the last `days` days (nil for all time); see ForeverLogic.SummarizeSales.
function ProfessionExporter:GetSalesSummary(days)
	local L = self:InitLedger()
	return self.ForeverLogic.SummarizeSales(L and L.events or {}, time(), days)
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
function ProfessionExporter:LedgerAverageUnitBuyCopper(itemID, characterKey)
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

function ProfessionExporter:LedgerAverageUnitSellCopper(itemID, characterKey)
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

function ProfessionExporter:LedgerPurchaseStats(itemID, characterKey)
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

function ProfessionExporter:LedgerSaleStats(itemID, characterKey)
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
