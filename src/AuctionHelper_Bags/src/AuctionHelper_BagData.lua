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

--- Read-only items of a saved character, or of all of them (`tabKey` "all"), for `mode`
--- ("bags", "bank" or "both"): one entry per item with the count added up.
function ProfessionExporter:GetSavedBagItems(tabKey, mode)
	local characters = self:GetItemHoldings()
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
