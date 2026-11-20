local _, ProfessionExporter = ...

-- Holdings: everything each character carries and banks, and its gold, saved per character in the
-- inventory database (AuctionHelperInventoryDB.holdings). Unlike inventorySnapshot, which only
-- counts items of scanned recipes, this counts every item. The bags module reads it (E11 F94).
--
-- holdings[characterKey] = { name, seenAt, money, bags = { [itemID] = count },
--                            bank = { [itemID] = count }, bankSeenAt }
--
-- The warband bank (retail) belongs to the whole account, so it is saved apart from the characters,
-- in the shape of a character that only has a bank:
-- AuctionHelperInventoryDB.warbandBank = { name, bank = { [itemID] = count }, bankSeenAt, money }

local BACKPACK = 0
local BANK_SETTLE_SECONDS = 0.3
local bankOpen = false

--- Every character's holdings, keyed by character key.
function ProfessionExporter:GetItemHoldings()
	if not self.inventoryDb then
		self:InitDB()
	end
	self.inventoryDb.holdings = self.inventoryDb.holdings or {}
	return self.inventoryDb.holdings
end

--- The logged-in character's holdings, created on first use.
function ProfessionExporter:GetOwnItemHoldings()
	local holdings = self:GetItemHoldings()
	local key = self:GetCharacterKey()
	holdings[key] = holdings[key] or { bags = {}, bank = {} }
	holdings[key].name = UnitName("player") or key
	return holdings[key]
end

--- The other characters that hold `itemID` in their bags or bank, as saved when each was last
--- played: { { characterKey, quantity }, … } (unsorted).
function ProfessionExporter:GetItemHoldersOnOtherCharacters(itemID)
	itemID = tonumber(itemID)
	local own = self:GetCharacterKey()
	local holders = {}
	for characterKey, held in pairs(self:GetItemHoldings()) do
		local quantity = (held.bags and held.bags[itemID] or 0) + (held.bank and held.bank[itemID] or 0)
		if characterKey ~= own and quantity > 0 then
			holders[#holders + 1] = { characterKey = characterKey, quantity = quantity }
		end
	end
	return holders
end

local function countItems(bagIDs)
	local counts = {}
	for _, bag in ipairs(bagIDs) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local itemID = info and tonumber(info.itemID)
			if itemID then
				counts[itemID] = (counts[itemID] or 0) + (tonumber(info.stackCount) or 1)
			end
		end
	end
	return counts
end

-- The bank's containers: the classic bank and its bags, or the bank tabs, whichever the client has.
local function bankBagIDs(pe)
	local index = Enum and Enum.BagIndex or {}
	local ids = {}
	if index.Bank then
		ids[#ids + 1] = index.Bank
	end
	for tab = 1, 8 do
		local id = index["CharacterBankTab_" .. tab]
		if id then
			ids[#ids + 1] = id
		end
	end
	if not index.CharacterBankTab_1 then
		local first = pe:GetLastBagIndex() + 1
		for bag = first, first + (tonumber(NUM_BANKBAGSLOTS) or 7) - 1 do
			ids[#ids + 1] = bag
		end
	end
	return ids
end

--- Save what the logged-in character carries, and its gold.
function ProfessionExporter:SaveBagHoldings()
	local own = self:GetOwnItemHoldings()
	local bagIDs = {}
	for bag = BACKPACK, self:GetLastBagIndex() do
		bagIDs[#bagIDs + 1] = bag
	end
	own.bags = countItems(bagIDs)
	own.money = GetMoney()
	own.seenAt = time()
end

--- Save the bank's contents. Does nothing unless the bank is open.
function ProfessionExporter:SaveBankHoldings()
	if not bankOpen then
		return
	end
	local own = self:GetOwnItemHoldings()
	own.bank = countItems(bankBagIDs(self))
	own.bankSeenAt = time()
end

--- The saved warband bank, or nil when it was never seen (always nil on Forever).
function ProfessionExporter:GetWarbandHoldings()
	if not self.inventoryDb then
		self:InitDB()
	end
	return self.inventoryDb.warbandBank
end

-- The warband bank tabs this account has bought; none on a client without a warband bank.
local function warbandBagIDs()
	local index, ids = Enum and Enum.BagIndex or {}, {}
	for tab = 1, 8 do
		local id = index["AccountBankTab_" .. tab]
		if id and (C_Container.GetContainerNumSlots(id) or 0) > 0 then
			ids[#ids + 1] = id
		end
	end
	return ids
end

local function warbandMoney()
	local account = Enum and Enum.BankType and Enum.BankType.Account
	return account and C_Bank and C_Bank.FetchDepositedMoney and tonumber(C_Bank.FetchDepositedMoney(account)) or nil
end

--- Save the warband bank's contents and gold. Does nothing unless the bank is open and has tabs.
function ProfessionExporter:SaveWarbandHoldings()
	local bagIDs = bankOpen and warbandBagIDs() or {}
	if #bagIDs == 0 then
		return
	end
	self:GetItemHoldings() -- makes sure the database is loaded
	self.inventoryDb.warbandBank = {
		name = "Warband bank", bank = countItems(bagIDs), bankSeenAt = time(), money = warbandMoney(),
	}
end

local handlers = {}

function handlers.PLAYER_LOGIN(pe)
	pe:SaveBagHoldings()
end

function handlers.BAG_UPDATE_DELAYED(pe)
	pe:SaveBagHoldings()
	pe:SaveBankHoldings()
	pe:SaveWarbandHoldings()
end

function handlers.PLAYER_MONEY(pe)
	pe:GetOwnItemHoldings().money = GetMoney()
end

function handlers.BANKFRAME_OPENED(pe)
	bankOpen = true
	-- The bank's slots fill in just after the frame opens.
	C_Timer.After(BANK_SETTLE_SECONDS, function()
		pe:SaveBankHoldings()
		pe:SaveWarbandHoldings()
		if pe.RequestBagWindowRefresh then
			pe:RequestBagWindowRefresh()
		end
	end)
end

function handlers.BANKFRAME_CLOSED()
	bankOpen = false
end

function handlers.PLAYERBANKSLOTS_CHANGED(pe)
	pe:SaveBankHoldings()
end

function handlers.PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED(pe)
	pe:SaveWarbandHoldings()
end

function handlers.ACCOUNT_MONEY(pe)
	pe:SaveWarbandHoldings()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	handlers[event](ProfessionExporter)
end)
for event in pairs(handlers) do
	-- Not every client has every event.
	pcall(events.RegisterEvent, events, event)
end
