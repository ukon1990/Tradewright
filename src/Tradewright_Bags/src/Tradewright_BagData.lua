local _, Tradewright = ...

-- Bag data: reads the carried bags for the bag window, and turns the per-character holdings
-- of the inventory database (Tradewright_Holdings.lua) into items for the read-only tabs.

local BACKPACK = 0

function Tradewright:GetReagentBagIndex()
	return Enum and Enum.BagIndex and tonumber(Enum.BagIndex.ReagentBag) or nil
end

local function sellPrice(itemID)
	local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
	return getInfo and tonumber((select(11, getInfo(itemID)))) or 0
end

-- Quality and name last read per item, and with them every item the window has described. Under
-- load (a full auction scan) the game drops item data for a moment and a slot's link comes back
-- with an empty name; sorted under that, the item would jump away and back.
local lastQuality, lastName, described = {}, {}, {}

local function cachedQualityAndName(pe, itemID)
	local desc = pe:ResolveItemDescriptor(itemID) or {}
	return desc.quality, desc.name ~= "" and desc.name or nil
end

-- Quality and name: from the live slot when it gave them, else from the item cache, else as last read.
local function qualityAndName(pe, itemID, info)
	local quality, name = info.quality, pe.BagLogic.LinkName(info.link)
	if not quality or not name then
		local cachedQuality, cachedName = cachedQualityAndName(pe, itemID)
		quality, name = quality or cachedQuality, name or cachedName
	end
	quality, name = quality or lastQuality[itemID], name or lastName[itemID]
	lastQuality[itemID], lastName[itemID], described[itemID] = quality, name, true
	return quality or 1, name or pe:GetItemDisplayName(itemID)
end

-- Words the search also looks in: item type, subtype, equip slot and quality, as the game names them.
local function keywords(typeName, subtypeName, equipLoc, quality)
	local words = { typeName or "", subtypeName or "" }
	words[#words + 1] = equipLoc and equipLoc ~= "" and _G[equipLoc] or nil
	words[#words + 1] = _G["ITEM_QUALITY" .. quality .. "_DESC"]
	return table.concat(words, " ")
end

--- One item of the bag window: what it is and how to draw it. `info` holds what the caller already
--- knows: count, and for a live slot quality, icon and link.
function Tradewright:DescribeBagItem(itemID, info)
	local _, typeName, subtypeName, equipLoc, icon, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
	local quality, name = qualityAndName(self, itemID, info)
	return {
		keywords = keywords(typeName, subtypeName, equipLoc, quality),
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

-- Whether the slot holds a quest item, and whether the item starts a quest (accepted or not).
-- Some clients return the fields as a table, older ones as three values.
local function questSlotInfo(bag, slot)
	if not C_Container.GetContainerItemQuestInfo then
		return false, false
	end
	local info, questID = C_Container.GetContainerItemQuestInfo(bag, slot)
	local isQuestItem = info
	if type(info) == "table" then
		isQuestItem, questID = info.isQuestItem, info.questID
	end
	return isQuestItem == true or questID ~= nil, questID ~= nil
end

-- What a redraw marks on live slots: `sets` (split gear by saved equipment set) and `new` (mark
-- items the game counts as new). Each needs its setting on and the client to have the API.
local function slotMarks(pe)
	local sets = C_EquipmentSet and C_EquipmentSet.GetNumEquipmentSets and C_Container.GetContainerItemEquipmentSetInfo
	return {
		sets = pe:GetSetting("bags.splitGearSets", true) == true and sets ~= nil and C_EquipmentSet.GetNumEquipmentSets() > 0,
		new = pe:GetSetting("bags.markNew", true) == true and C_NewItems ~= nil and C_NewItems.IsNewItem ~= nil,
	}
end

-- Sets `inSet` and `isNew` on a live item, and lets the search find them ("set", a set's name, "new").
local function addMarks(item, marks)
	if marks.sets then
		local inSet, setNames = C_Container.GetContainerItemEquipmentSetInfo(item.bag, item.slot)
		item.inSet = inSet == true
		if item.inSet then
			item.keywords = item.keywords .. " set " .. tostring(setNames or "")
		end
	end
	-- Junk is never marked: it is new all the time.
	if marks.new and item.quality ~= 0 and C_NewItems.IsNewItem(item.bag, item.slot) then
		item.isNew = true
		item.keywords = item.keywords .. " new"
	end
end

local function readSlot(pe, bag, slot, marks)
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
	item.isQuest, item.startsQuest = questSlotInfo(bag, slot)
	addMarks(item, marks)
	return item
end

local function carriedBagIDs(pe)
	local ids = {}
	for bag = BACKPACK, pe:GetLastBagIndex() do
		ids[#ids + 1] = bag
	end
	return ids
end

--- The containers `bagIDs` (default: the carried bags) as they are now: `items` (one per filled
--- slot), `bags` ({ bag, slots, free, isReagent }) and `firstFree` ({ bag, slot } in a normal
--- bag, or nil).
function Tradewright:ScanBags(bagIDs)
	local scan = { items = {}, bags = {} }
	local marks = slotMarks(self)
	local reagentBag = self:GetReagentBagIndex()
	for _, bag in ipairs(bagIDs or carriedBagIDs(self)) do
		local slots = C_Container.GetContainerNumSlots(bag) or 0
		local entry = { bag = bag, slots = slots, free = 0, isReagent = bag == reagentBag }
		scan.bags[#scan.bags + 1] = entry
		for slot = 1, slots do
			local item = readSlot(self, bag, slot, marks)
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

Tradewright.BAG_WARBAND_KEY = "warband"

--- Saved holdings for the bag window: every character, and the warband bank (retail) under
--- BAG_WARBAND_KEY once it has been seen. It has the shape of a character with only a bank.
function Tradewright:GetBagHoldings()
	local characters = self:GetItemHoldings()
	local warband = self:GetWarbandHoldings()
	if not warband then
		return characters
	end
	local all = { [self.BAG_WARBAND_KEY] = warband }
	for key, record in pairs(characters) do
		all[key] = record
	end
	return all
end

--- Read-only items of a saved character, or of all of them (`tabKey` "all"), for `mode`
--- ("bags", "bank" or "both"): one entry per item with the count added up.
function Tradewright:GetSavedBagItems(tabKey, mode)
	local characters = self:GetBagHoldings()
	local logic = self.BagLogic
	local counts = tabKey == "all" and logic.MergeAll(characters, mode) or logic.MergeCounts(characters[tabKey] or {}, mode)
	local items = {}
	for itemID, count in pairs(counts) do
		items[#items + 1] = self:DescribeBagItem(itemID, { count = count })
	end
	return items
end

-- Counts saved by this module before they moved to the inventory database: copied over once.
local function adoptOldBagCounts(pe)
	local old = TradewrightBagsDB
	if type(old) == "table" and type(old.characters) == "table" then
		pe.BagLogic.AdoptHoldings(pe:GetItemHoldings(), old.characters)
	end
	TradewrightBagsDB = nil
end

local function refreshWindow(pe)
	pe:RequestBagWindowRefresh()
end

-- Holdings are saved by the inventory module on the same events; the redraw runs a frame later.
local handlers = {
	BAG_UPDATE_DELAYED = refreshWindow,
	PLAYER_MONEY = refreshWindow,
	ITEM_LOCK_CHANGED = refreshWindow,
	BAG_UPDATE_COOLDOWN = refreshWindow,
	PLAYERBANKSLOTS_CHANGED = refreshWindow,
	PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED = refreshWindow,
	EQUIPMENT_SETS_CHANGED = refreshWindow,
	BAG_NEW_ITEMS_UPDATED = refreshWindow,
}

-- An auction scan loads data for every item on the house: only an item of the window redraws it.
function handlers.GET_ITEM_INFO_RECEIVED(pe, itemID)
	if described[itemID] then
		refreshWindow(pe)
	end
end

function handlers.PLAYER_LOGIN(pe)
	adoptOldBagCounts(pe)
	pe:ApplyBagTakeover()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
	handlers[event](Tradewright, ...)
end)
for event in pairs(handlers) do
	-- Not every client has every event.
	pcall(events.RegisterEvent, events, event)
end
