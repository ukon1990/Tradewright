local _, ProfessionExporter = ...

-- Bag data (E11): reads the carried bags for the bag window, and keeps per-character item counts
-- in AuctionHelperBagsDB so other characters can be shown (F94).

local BACKPACK = 0
local BANK_SETTLE_SECONDS = 0.3
local bankOpen = false

function ProfessionExporter:GetBagsDB()
	AuctionHelperBagsDB = AuctionHelperBagsDB or {}
	AuctionHelperBagsDB.characters = AuctionHelperBagsDB.characters or {}
	return AuctionHelperBagsDB
end

--- The logged-in character's saved record, created on first use.
function ProfessionExporter:GetOwnBagRecord()
	local characters = self:GetBagsDB().characters
	local key = self:GetCharacterKey()
	characters[key] = characters[key] or { bags = {}, bank = {} }
	characters[key].name = UnitName("player") or key
	return characters[key]
end

function ProfessionExporter:GetReagentBagIndex()
	return Enum and Enum.BagIndex and tonumber(Enum.BagIndex.ReagentBag) or nil
end

local function sellPrice(itemID)
	local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
	return getInfo and tonumber((select(11, getInfo(itemID)))) or 0
end

-- Quality and name: from the live slot when it gave them, else from the item cache.
local function qualityAndName(pe, itemID, info)
	local quality, name = info.quality, info.link and string.match(info.link, "%[(.-)%]")
	if not quality or not name then
		local desc = pe:ResolveItemDescriptor(itemID) or {}
		quality, name = quality or desc.quality, name or desc.name
	end
	return quality or 1, name or pe:GetItemDisplayName(itemID)
end

--- One item of the bag window: what it is and how to draw it. `info` holds what the caller already
--- knows: count, and for a live slot quality, icon and link.
function ProfessionExporter:DescribeBagItem(itemID, info)
	local _, _, _, _, icon, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
	local quality, name = qualityAndName(self, itemID, info)
	return {
		itemID = itemID,
		count = info.count or 1,
		quality = quality,
		name = name,
		icon = info.icon or icon,
		link = info.link,
		classID = classID,
		subclassID = subclassID,
		sellPrice = sellPrice(itemID),
	}
end

local function isQuestSlot(bag, slot)
	local quest = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
	return type(quest) == "table" and (quest.isQuestItem == true or quest.questID ~= nil)
end

local function readSlot(pe, bag, slot)
	local info = C_Container.GetContainerItemInfo(bag, slot)
	local itemID = info and tonumber(info.itemID)
	if not itemID then
		return nil
	end
	local item = pe:DescribeBagItem(itemID, {
		count = tonumber(info.stackCount),
		quality = tonumber(info.quality),
		icon = info.iconFileID,
		link = info.hyperlink,
	})
	item.bag, item.slot = bag, slot
	item.locked = info.isLocked == true
	item.isQuest = isQuestSlot(bag, slot)
	return item
end

--- The carried bags as they are now: `items` (one per filled slot), `bags`
--- ({ bag, slots, free, isReagent }) and `firstFree` ({ bag, slot } in a normal bag, or nil).
function ProfessionExporter:ScanBags()
	local scan = { items = {}, bags = {} }
	local reagentBag = self:GetReagentBagIndex()
	for bag = BACKPACK, self:GetLastBagIndex() do
		local slots = C_Container.GetContainerNumSlots(bag) or 0
		local entry = { bag = bag, slots = slots, free = 0, isReagent = bag == reagentBag }
		scan.bags[#scan.bags + 1] = entry
		for slot = 1, slots do
			local item = readSlot(self, bag, slot)
			if item then
				scan.items[#scan.items + 1] = item
			else
				entry.free = entry.free + 1
				if not entry.isReagent and not scan.firstFree then
					scan.firstFree = { bag = bag, slot = slot }
				end
			end
		end
	end
	return scan
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
function ProfessionExporter:SaveBagSnapshot()
	local record = self:GetOwnBagRecord()
	local bagIDs = {}
	for bag = BACKPACK, self:GetLastBagIndex() do
		bagIDs[#bagIDs + 1] = bag
	end
	record.bags = countItems(bagIDs)
	record.money = GetMoney()
	record.seenAt = time()
end

--- Save the bank's contents. Only meaningful while the bank is open.
function ProfessionExporter:SaveBankSnapshot()
	if not bankOpen then
		return
	end
	local record = self:GetOwnBagRecord()
	record.bank = countItems(bankBagIDs(self))
	record.bankSeenAt = time()
end

--- Read-only items of a saved character, or of all of them (`tabKey` "all"), for `mode`
--- ("bags", "bank" or "both"): one entry per item with the count added up.
function ProfessionExporter:GetSavedBagItems(tabKey, mode)
	local characters = self:GetBagsDB().characters
	local logic = self.BagLogic
	local counts = tabKey == "all" and logic.MergeAll(characters, mode) or logic.MergeCounts(characters[tabKey] or {}, mode)
	local items = {}
	for itemID, count in pairs(counts) do
		items[#items + 1] = self:DescribeBagItem(itemID, { count = count })
	end
	return items
end

local function refreshWindow(pe)
	pe:RequestBagWindowRefresh()
end

local handlers = {
	ITEM_LOCK_CHANGED = refreshWindow,
	BAG_UPDATE_COOLDOWN = refreshWindow,
	GET_ITEM_INFO_RECEIVED = refreshWindow,
}

function handlers.PLAYER_LOGIN(pe)
	pe:SaveBagSnapshot()
	pe:ApplyBagTakeover()
end

function handlers.BAG_UPDATE_DELAYED(pe)
	pe:SaveBagSnapshot()
	pe:SaveBankSnapshot()
	pe:RequestBagWindowRefresh()
end

function handlers.PLAYER_MONEY(pe)
	pe:GetOwnBagRecord().money = GetMoney()
	pe:RequestBagWindowRefresh()
end

function handlers.BANKFRAME_OPENED(pe)
	bankOpen = true
	-- The bank's slots fill in just after the frame opens.
	C_Timer.After(BANK_SETTLE_SECONDS, function()
		pe:SaveBankSnapshot()
		pe:RequestBagWindowRefresh()
	end)
end

function handlers.BANKFRAME_CLOSED()
	bankOpen = false
end

function handlers.PLAYERBANKSLOTS_CHANGED(pe)
	pe:SaveBankSnapshot()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	handlers[event](ProfessionExporter)
end)
for event in pairs(handlers) do
	-- Not every client has every event.
	pcall(events.RegisterEvent, events, event)
end
