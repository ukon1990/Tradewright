-- Item and currency info: descriptors from the item API, auction tradeability, expansion filter tags and vendor prices.
local _, AuctionHelper = ...

--- Profession crafting tier (1+) embedded in item hyperlink; matches default tooltip quality diamond.
function AuctionHelper:ParseProfessionQualityTierFromItemLink(link)
	if type(link) ~= "string" or link == "" then
		return nil
	end
	local expPart, tierStr = string.match(link, "\124A:Professions%-ChatIcon%-Quality([%-%d]*)%-Tier(%d+)")
	if not tierStr then
		return nil
	end
	local tier = tonumber(tierStr)
	if not tier or tier < 1 then
		return nil
	end
	if expPart and expPart ~= "" and tonumber(expPart) then
		tier = tier + 10
	end
	if tier > 10 then
		tier = tier - 10
	end
	return tier
end

function AuctionHelper:ItemDescriptorFromID(itemID)
	if not itemID then
		return nil
	end

	local name, link, quality, itemLevel, minLevel, itemType, itemSubType, stackCount, equipLoc, icon, sellPrice,
		classID, subclassID, bindType, expansionID, setID, isCraftingReagent
	local getItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
	if getItemInfo then
		name, link, quality, itemLevel, minLevel, itemType, itemSubType, stackCount, equipLoc, icon, sellPrice,
			classID, subclassID, bindType, expansionID, setID, isCraftingReagent = getItemInfo(itemID)
	end

	local getItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
	local instantItemID, instantItemType, instantItemSubType, instantEquipLoc, instantIcon, instantClassID, instantSubClassID
	if getItemInfoInstant then
		instantItemID, instantItemType, instantItemSubType, instantEquipLoc, instantIcon, instantClassID,
			instantSubClassID = getItemInfoInstant(itemID)
	end

	return {
		itemID = itemID,
		name = name,
		link = link,
		quality = quality,
		itemLevel = itemLevel,
		minLevel = minLevel,
		itemType = itemType or instantItemType,
		itemSubType = itemSubType or instantItemSubType,
		stackCount = stackCount,
		equipLoc = equipLoc or instantEquipLoc,
		icon = icon or instantIcon,
		sellPrice = sellPrice,
		classID = classID or instantClassID,
		subclassID = subclassID or instantSubClassID,
		bindType = bindType,
		expansionID = expansionID,
		setID = setID,
		isCraftingReagent = isCraftingReagent,
		instantItemID = instantItemID,
	}
end

function AuctionHelper:ResolveItemDescriptor(itemID)
	if not itemID then
		return nil
	end
	local cache = self._itemDescCache
	if not cache then
		return self:ItemDescriptorFromID(itemID)
	end
	local existing = cache[itemID]
	if existing ~= nil then
		return existing
	end
	local desc = self:ItemDescriptorFromID(itemID)
	cache[itemID] = desc
	return desc
end

-- Enum.ItemBind members that keep an item off the auction house. Clients without a member skip it.
local UNTRADEABLE_BIND_TYPE_NAMES = {
	"OnAcquire", "Quest", "ToWoWAccount", "ToBnetAccount", "ToWoWAccountUntilEquipped", "ToBnetAccountUntilEquipped",
	"ToWarband",
}

local function isUntradeableBindType(bindType)
	local bindTypes = Enum and Enum.ItemBind
	if bindTypes then
		for _, name in ipairs(UNTRADEABLE_BIND_TYPE_NAMES) do
			if bindTypes[name] == bindType then
				return true
			end
		end
	end
	-- Older clients name only these two, as globals.
	return bindType == LE_ITEM_BIND_ON_ACQUIRE or bindType == LE_ITEM_BIND_QUEST
end

--- Uses static C_Item.GetItemInfo bind type only (not whether your stack is actually soulbound).
function AuctionHelper:IsItemLikelyTradeableOnAuctionByStaticInfo(itemID)
	itemID = tonumber(itemID)
	if not itemID or itemID <= 0 then
		return false
	end
	local desc = self:ResolveItemDescriptor(itemID)
	if not desc or not desc.name then
		return false
	end
	local bindType = tonumber(desc.bindType)
	return bindType == nil or not isUntradeableBindType(bindType)
end

--- Map C_Item.GetItemInfo expansionID (LE_EXPANSION) to crafts/inventory filter bucket.
--- Retail: 9 DF, 10 TWW, 11 Midnight. Other values (incl. Classic client sentinel 254) → legacy.
function AuctionHelper:ExpansionLeToFilterTag(expansionID)
	local e = tonumber(expansionID)
	if not e or e ~= e then
		return nil
	end
	local midnight = LE_EXPANSION_MIDNIGHT or 11
	local tww = LE_EXPANSION_WAR_WITHIN or 10
	local df = LE_EXPANSION_DRAGONFLIGHT or 9
	if e == midnight then
		return "midnight"
	end
	if e == tww then
		return "tww"
	end
	if e == df then
		return "df"
	end
	return "legacy"
end

function AuctionHelper:GetExpansionFilterOptions()
	return {
		{ value = "all", label = "All expansions" },
		{ value = "midnight", label = "Midnight" },
		{ value = "tww", label = "The War Within" },
		{ value = "df", label = "Dragonflight" },
		{ value = "legacy", label = "Older" },
	}
end

function AuctionHelper:ResolveCurrencyDescriptor(currencyID)
	if not currencyID then
		return nil
	end
	local cache = self._currencyDescCache
	if not cache then
		return self:CurrencyDescriptorFromID(currencyID)
	end
	local existing = cache[currencyID]
	if existing ~= nil then
		return existing
	end
	local desc = self:CurrencyDescriptorFromID(currencyID)
	cache[currencyID] = desc
	return desc
end

function AuctionHelper:CurrencyDescriptorFromID(currencyID)
	if not currencyID then
		return nil
	end

	local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(currencyID)
	return self:SanitizeValue(info)
end

--- Copper to buy one item from a vendor (Retail C_Item); nil if not sold by vendors.
function AuctionHelper:GetItemVendorPurchaseCopper(itemID)
	itemID = tonumber(itemID)
	if not itemID then
		return nil
	end
	if C_Item and C_Item.GetItemVendorPrice then
		local c = tonumber(C_Item.GetItemVendorPrice(itemID))
		if c and c > 0 then
			return c
		end
	end
	return nil
end

--- Vendor sell (to NPC) price per item; nil if unknown.
function AuctionHelper:GetItemVendorSellCopper(itemID)
	itemID = tonumber(itemID)
	if not itemID then
		return nil
	end
	if C_Item and C_Item.GetItemInfo then
		local _, _, _, _, _, _, _, _, _, _, sellPrice = C_Item.GetItemInfo(itemID)
		sellPrice = tonumber(sellPrice)
		if sellPrice and sellPrice > 0 then
			return sellPrice
		end
	end
	return nil
end
