local _, ProfessionExporter = ...

-- Bag data (E11): reads the carried bags for the bag window, and turns the per-character holdings
-- of the inventory database (AuctionHelper_Holdings.lua) into items for the read-only tabs (F94).

local BACKPACK = 0

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

-- Words the search also looks in: item type, subtype, equip slot and quality, as the game names them.
local function keywords(typeName, subtypeName, equipLoc, quality)
	local words = { typeName or "", subtypeName or "" }
	words[#words + 1] = equipLoc and equipLoc ~= "" and _G[equipLoc] or nil
	words[#words + 1] = _G["ITEM_QUALITY" .. quality .. "_DESC"]
	return table.concat(words, " ")
end

--- One item of the bag window: what it is and how to draw it. `info` holds what the caller already
--- knows: count, and for a live slot quality, icon and link.
function ProfessionExporter:DescribeBagItem(itemID, info)
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
function ProfessionExporter:ScanBags(bagIDs)
	local scan = { items = {}, bags = {} }
	local reagentBag = self:GetReagentBagIndex()
	for _, bag in ipairs(bagIDs or carriedBagIDs(self)) do
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

ProfessionExporter.BAG_WARBAND_KEY = "warband"

--- Saved holdings for the bag window: every character, and the warband bank (retail) under
--- BAG_WARBAND_KEY once it has been seen. It has the shape of a character with only a bank.
function ProfessionExporter:GetBagHoldings()
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
function ProfessionExporter:GetSavedBagItems(tabKey, mode)
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
	local old = AuctionHelperBagsDB
	if type(old) == "table" and type(old.characters) == "table" then
		pe.BagLogic.AdoptHoldings(pe:GetItemHoldings(), old.characters)
	end
	AuctionHelperBagsDB = nil
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
	GET_ITEM_INFO_RECEIVED = refreshWindow,
	PLAYERBANKSLOTS_CHANGED = refreshWindow,
	PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED = refreshWindow,
}

function handlers.PLAYER_LOGIN(pe)
	adoptOldBagCounts(pe)
	pe:ApplyBagTakeover()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	handlers[event](ProfessionExporter)
end)
for event in pairs(handlers) do
	-- Not every client has every event.
	pcall(events.RegisterEvent, events, event)
end
