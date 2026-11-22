local _, Tradewright = ...

-- Reagents that are cheaper at a vendor than at the auction house. Every merchant the player opens
-- is remembered (items in endless supply, their price, the vendor's name and position), so the cart
-- can warn, point the way to the nearest seller, and offer the reagents when the player is there.
-- Vendors not visited yet come from the Questie database when that addon is installed: a name and
-- a position, without a price.
-- This only reads the merchant window; buying happens on the player's own click.

local VendorLogic = Tradewright.VendorLogic

-- { [itemID] = { [npcName] = { price, zone, mapID, x, y, seenAt } } }, account-wide.
local function sellerStore()
	TradewrightAuctionDB = TradewrightAuctionDB or {}
	TradewrightAuctionDB.vendorSellers = TradewrightAuctionDB.vendorSellers or {}
	return TradewrightAuctionDB.vendorSellers
end

local function playerPlace()
	local place = { zone = GetRealZoneText and GetRealZoneText() or nil }
	local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local position = mapID and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
	if position then
		place.mapID = mapID
		place.x, place.y = position:GetXY()
	end
	return place
end

local function merchantItem(index)
	local item = { index = index, itemID = GetMerchantItemID and GetMerchantItemID(index) or nil }
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
		local info = C_MerchantFrame.GetItemInfo(index) or {}
		item.price, item.stack, item.available, item.extendedCost = info.price, info.stackCount, info.numAvailable, info.hasExtendedCost
	elseif GetMerchantItemInfo then
		local _, _, price, stack, available, _, _, extendedCost = GetMerchantItemInfo(index)
		item.price, item.stack, item.available, item.extendedCost = price, stack, available, extendedCost
	end
	return item
end

--- Everything the open merchant sells: `{ { index, itemID, price, stack, available, extendedCost } }`.
function Tradewright:GetMerchantItems()
	local items = {}
	for index = 1, GetMerchantNumItems and GetMerchantNumItems() or 0 do
		items[#items + 1] = merchantItem(index)
	end
	return items
end

local function rememberMerchant(pe)
	local name = UnitName and UnitName("npc")
	if not name then
		return
	end
	local store = sellerStore()
	for itemID, entry in pairs(VendorLogic.SellerEntries(pe:GetMerchantItems(), playerPlace(), pe:Now())) do
		store[itemID] = store[itemID] or {}
		store[itemID][name] = entry
	end
end

local function questieMapID(areaID)
	local zoneDB = QuestieLoader and QuestieLoader.ImportModule and QuestieLoader:ImportModule("ZoneDB")
	local mapID = zoneDB and zoneDB.GetUiMapIdByAreaId and zoneDB:GetUiMapIdByAreaId(areaID)
	return mapID and mapID > 0 and mapID or nil
end

-- Where one Questie NPC stands: its first spawn on a map the client knows, or nil.
local function questieSeller(npcID)
	for areaID, points in pairs(NpcDB.spawns(npcID) or {}) do
		local mapID, point = questieMapID(areaID), points[1]
		if mapID and point and point[1] and point[1] >= 0 then
			local map = C_Map.GetMapInfo(mapID)
			return { zone = map and map.name, mapID = mapID, x = point[1] / 100, y = point[2] / 100 }
		end
	end
	return nil
end

-- Vendors of an item that are friendly to the player: { [npcName] = { zone, mapID, x, y } }.
local function questieSellers(itemID)
	local sellers = {}
	local faction = UnitFactionGroup("player") == "Horde" and "H" or "A"
	for _, npcID in ipairs(ItemDB.vendors(itemID) or {}) do
		local friendly, name = NpcDB.friendlyToFaction(npcID), NpcDB.name(npcID)
		if name and (not friendly or friendly:find(faction, 1, true)) then
			sellers[name] = questieSeller(npcID)
		end
	end
	return sellers
end

-- Sellers from the Questie database per item, read once a session. Empty without Questie, and when
-- its database does not answer the way this expects.
local directoryCache = {}
local function directorySellers(itemID)
	if directoryCache[itemID] == nil then
		local ok, sellers = false, nil
		if ItemDB and ItemDB.vendors and NpcDB and NpcDB.spawns and C_Map and C_Map.GetMapInfo then
			ok, sellers = pcall(questieSellers, itemID)
		end
		directoryCache[itemID] = ok and sellers or {}
	end
	return directoryCache[itemID]
end

--- What is known about buying `itemID` from a vendor (see VendorLogic.Lookup), or nil.
function Tradewright:GetVendorSource(itemID)
	itemID = tonumber(itemID)
	return itemID and VendorLogic.Lookup(itemID, sellerStore()[itemID], directorySellers(itemID)) or nil
end

--- Vendor advice for a cart row: `{ price, exact, cheaper }` and the vendor source, or nil.
function Tradewright:GetCartVendorAdvice(row)
	local info = row and self:GetVendorSource(row.itemID)
	if not info then
		return nil
	end
	local auctionPrice = row.currentPriceIsNative and row.currentPrice or row.estimatedUnitPrice or row.currentPrice
	return VendorLogic.Advice(info, auctionPrice), info
end

local function priceText(pe, advice)
	return (advice.exact and "" or "about ") .. pe:FormatCopperShort(math.ceil(advice.price))
end

-- "Vendor: about 1s", or "Sold by a vendor" when the price is not known.
local function plainNote(pe, advice)
	return advice.price and ("Vendor: " .. priceText(pe, advice)) or "Sold by a vendor"
end

local function hasText(text)
	return text ~= nil and text ~= "" and text ~= "-" and text ~= "—"
end

--- Short vendor note for a shopping row (`{ itemID, estimatedUnitPrice }`), orange when the vendor
--- is the cheaper place to buy; nil when no vendor sells the item.
function Tradewright:GetVendorNote(row)
	local advice = self:GetCartVendorAdvice(row)
	if not advice then
		return nil
	end
	if advice.cheaper then
		return self:Colorize("Cheaper at a vendor: " .. priceText(self, advice), "warning")
	end
	return plainNote(self, advice)
end

--- Second line of a cart row: the vendor note, what the reagent is for and who it is mailed to.
function Tradewright:AuctionCartRowDetail(row)
	local parts = { self:GetVendorNote(row) }
	if row and hasText(row.sourceText) then
		parts[#parts + 1] = "For " .. row.sourceText
	end
	if row and hasText(row.mailToText) then
		parts[#parts + 1] = "mail to " .. row.mailToText
	end
	return table.concat(parts, " · ")
end

--- Adds the vendor price and seller to a cart row's tooltip lines. Returns `hint` with the vendor
--- click added to it.
function Tradewright:AppendCartVendorLines(lines, row, hint)
	local advice, info = self:GetCartVendorAdvice(row)
	if not advice then
		return hint
	end
	if advice.price then
		local price = priceText(self, advice) .. " each"
		lines[#lines + 1] = { "Vendor price", advice.cheaper and self:Colorize(price .. ", cheaper than the auction house", "warning") or price }
	end
	lines[#lines + 1] = { "Sold by", VendorLogic.Where(info) or "vendors" }
	return hint .. "\n" .. (VendorLogic.Nearest(info.sellers) and "Right-click to show the way to the nearest vendor"
		or "Visit a vendor that sells it once to get directions")
end

--- "2 items are cheaper at a vendor. " for the rows still to buy, or "".
function Tradewright:CartVendorHint(rows)
	local count = 0
	for _, row in ipairs(rows or {}) do
		local advice = self:GetCartVendorAdvice(row)
		if advice and advice.cheaper then
			count = count + 1
		end
	end
	if count == 0 then
		return ""
	end
	return self:Colorize(string.format("%d %s cheaper at a vendor. ", count, self:Plural(count, "item is", "items are")), "warning")
end

-- The game's own waypoint arrow, where the client has one and the map allows it.
local function setNativeWaypoint(seller)
	if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
		return false
	end
	if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(seller.mapID) then
		return false
	end
	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(seller.mapID, seller.x, seller.y))
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
		C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	end
	return true
end

-- TomTom's arrow, when that addon is installed.
local function setTomTomWaypoint(seller, title)
	if not (TomTom and TomTom.AddWaypoint) then
		return false
	end
	TomTom:AddWaypoint(seller.mapID, seller.x, seller.y, { title = title })
	return true
end

local function noSellerMessage(info, name)
	if not info then
		return string.format("No vendor is known to sell %s.", name)
	end
	return string.format("No vendor visited yet for %s. Look for %s; the first visit saves the place.",
		name, info.kind or "a vendor that sells it")
end

-- Position in the world (continent and yards), to compare sellers on different maps.
local function worldOf(mapID, x, y)
	if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then
		return nil
	end
	local continent, position = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
	if not (continent and position) then
		return nil
	end
	local worldX, worldY = position:GetXY()
	return { continent = continent, x = worldX, y = worldY }
end

--- Where the player stands: `{ zone, mapID, x, y }`.
function Tradewright:GetPlayerPlace()
	return playerPlace()
end

--- The nearest of `places` (`{ name, zone, mapID, x, y, seenAt }`, vendors or trainers) to the player;
--- see VendorLogic.Nearest. nil when none has a position.
function Tradewright:NearestPlace(places)
	local here = playerPlace()
	here.world = here.mapID and worldOf(here.mapID, here.x, here.y)
	for _, place in ipairs(places) do
		place.world = place.mapID and place.x and worldOf(place.mapID, place.x, place.y) or nil
	end
	return VendorLogic.Nearest(places, here)
end

--- Points the way to `place` with the game's waypoint, or TomTom's. Returns whether one was set.
function Tradewright:SetWaypointTo(place, title)
	return setNativeWaypoint(place) or setTomTomWaypoint(place, title)
end

--- Points the way to the nearest known vendor that sells `itemID`, and says where it is in chat.
function Tradewright:ShowVendorWaypoint(itemID)
	local info = self:GetVendorSource(itemID)
	local name = self:GetItemDisplayName(itemID)
	local seller = info and self:NearestPlace(info.sellers)
	if not seller then
		self:PrintMessage(noSellerMessage(info, name))
		return false
	end
	local marked = self:SetWaypointTo(seller, seller.name .. " (" .. name .. ")")
	local zone = hasText(seller.zone) and (" in " .. seller.zone) or ""
	self:PrintMessage(string.format("%s sells %s%s, at %.1f, %.1f.%s", seller.name, name, zone,
		seller.x * 100, seller.y * 100, marked and " Waypoint set." or ""))
	return marked
end

-- Materials the craft queue still misses on this character: { [itemID] = { name, need } }.
local function queueNeeds(pe)
	local needs = {}
	for _, line in ipairs(pe:BuildCraftQueueSummary().reagentLines or {}) do
		local need = tonumber(line.quantityToBuy) or 0
		if line.itemID and need > 0 then
			needs[tonumber(line.itemID)] = { name = line.name, need = need }
		end
	end
	return needs
end

-- One buy-window row for a merchant item the queue needs, or nil when the vendor is sold out.
local function merchantOffer(item, entry, wanted)
	local stock = entry.limited and tonumber(item.available) or nil
	if stock == 0 then
		return nil
	end
	return {
		index = item.index, itemID = item.itemID, name = wanted.name, need = math.min(wanted.need, stock or wanted.need),
		stock = stock, price = entry.price, stack = math.max(1, tonumber(item.stack) or 1),
		maxStack = GetMerchantItemMaxStack and GetMerchantItemMaxStack(item.index) or 1,
	}
end

--- Queue materials the open merchant sells: `{ { index, itemID, name, need, stock, price, stack, maxStack } }`,
--- by name. `price` is for one unit; `stock` is what a vendor with limited supply has left (nil when
--- endless), and `need` never exceeds it.
function Tradewright:GetMerchantCartOffers()
	local needs = queueNeeds(self)
	local items = self:GetMerchantItems()
	local sold = VendorLogic.SellerEntries(items)
	local offers = {}
	for _, item in ipairs(items) do
		local entry, wanted = sold[item.itemID], needs[item.itemID]
		if entry and wanted then
			needs[item.itemID] = nil
			offers[#offers + 1] = merchantOffer(item, entry, wanted)
		end
	end
	table.sort(offers, function(a, b) return tostring(a.name) < tostring(b.name) end)
	return offers
end

--- Buys `amount` of merchant item `offer` (see GetMerchantCartOffers). Returns the units bought.
function Tradewright:BuyMerchantCartOffer(offer, amount)
	local purchases, total = VendorLogic.BuyPlan(amount, offer.stack, offer.maxStack)
	for _, units in ipairs(purchases) do
		if offer.stack > 1 then
			BuyMerchantItem(offer.index)
		else
			BuyMerchantItem(offer.index, units)
		end
	end
	return total
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function()
	if Tradewright.db then
		rememberMerchant(Tradewright)
	end
end)
pcall(frame.RegisterEvent, frame, "MERCHANT_SHOW")
