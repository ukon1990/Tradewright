local _, Tradewright = ...

-- The sightings store: which NPC sells or teaches what, what was looted from where, and where all of
-- that is. It grows from windows the player opens (vendor, trainer, loot) and is read together with
-- the data shipped in Tradewright_SourceData.lua. The rules live in Tradewright_SourceLogic.lua.
-- Nothing here acts for the player; it only writes down what a window showed.

local SourceLogic = Tradewright.SourceLogic

local shippedStore = SourceLogic.EnsureStore(Tradewright.SOURCE_DATA)

-- Tells this player's loot counts apart from other collectors' once data is shipped.
local function newCollectorID()
	return string.format("%08x%04x", time(), math.random(0, 0xffff))
end

-- Only call from an event or later: saved variables are not loaded while the addon's files run.
local function savedStore()
	if not (TradewrightSourcesDB and TradewrightSourcesDB.collectorID) then
		TradewrightSourcesDB = SourceLogic.EnsureStore(TradewrightSourcesDB, newCollectorID())
	end
	return TradewrightSourcesDB
end

local function stores()
	return { shippedStore, savedStore() }
end

local function playerFaction()
	return UnitFactionGroup and UnitFactionGroup("player") or nil
end

--- Where the player stands: `{ zone, mapID, x, y }`.
function Tradewright:GetPlayerPlace()
	local place = { zone = GetRealZoneText and GetRealZoneText() or nil }
	local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local position = mapID and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
	if position then
		place.mapID = mapID
		place.x, place.y = position:GetXY()
	end
	return place
end

function Tradewright:GetMapName(mapID)
	local map = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
	return map and map.name or nil
end

--- The item's class (Enum.ItemClass), read without a server round trip; nil when the client lacks the call.
function Tradewright:GetItemClassID(itemID)
	local getItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
	if not (itemID and getItemInfoInstant) then
		return nil
	end
	return (select(6, getItemInfoInstant(itemID)))
end

-- Stored places carry a map, not its name.
local function nameZones(pe, placesByName)
	for _, place in pairs(placesByName) do
		place.zone = pe:GetMapName(place.mapID)
	end
	return placesByName
end

--- Records the NPC whose window is open, with where the player stands. Returns its npcKey, or nil
--- when the client names no NPC.
function Tradewright:RememberOpenNpc()
	local kind, id = SourceLogic.SourceOfGUID(UnitGUID and UnitGUID("npc"))
	return SourceLogic.RememberNpc(savedStore(), {
		npcID = kind == "npc" and id or nil, name = UnitName and UnitName("npc") or nil,
		faction = playerFaction(), place = self:GetPlayerPlace(),
	})
end

--- Records what the open vendor sells. `entries` as VendorLogic.SellerEntries gives them.
function Tradewright:RecordVendorSighting(entries)
	local npcKey = self:RememberOpenNpc()
	if npcKey then
		SourceLogic.RecordSold(savedStore(), npcKey, entries)
	end
end

--- Records what the open trainer offers: `recipes` and `ranks` as LevelingRouteLogic.TrainerEntries
--- gives them.
function Tradewright:RecordTrainerSighting(recipes, ranks)
	local npcKey = self:RememberOpenNpc()
	if npcKey then
		SourceLogic.RecordTaught(savedStore(), "taught", npcKey, recipes)
		SourceLogic.RecordTaught(savedStore(), "ranks", npcKey, ranks)
	end
end

--- Records that `itemID` is the item teaching a recipe, when its name and class say so.
function Tradewright:RecordRecipeItem(itemID, itemName, classID)
	local recipeName = SourceLogic.RecipeNameOfItem(itemName, classID)
	if itemID and recipeName then
		savedStore().recipeItems[recipeName] = itemID
	end
end

--- Records one opened loot. `source = { kind, id, name, itemIDs }`: `kind` is "kill", "gather",
--- "object" or "fishing"; `name` is the creature's when the client gave it.
function Tradewright:RecordLootSighting(source)
	local store, place = savedStore(), self:GetPlayerPlace()
	if source.kind == "object" then
		SourceLogic.RememberObject(store, source.id, place)
	elseif source.kind ~= "fishing" then
		SourceLogic.RememberNpc(store, { npcID = source.id, name = source.name, place = place })
	end
	SourceLogic.RecordLoot(store, SourceLogic.SourceKey(source.kind, source.id), source.itemIDs)
end

--- Vendors seen selling `itemID` to this character's faction:
--- `{ [npcName] = { price, limited, zone, mapID, x, y, seenAt } }`.
function Tradewright:GetSellers(itemID)
	return nameZones(self, SourceLogic.SellersOf(stores(), itemID, playerFaction()))
end

--- What trainers have been seen to offer for a profession, to this character's faction:
--- `{ [serviceName] = { skillRequired, cost, seenAt, trainers = { [npcName] = { zone, mapID, x, y } } } }`.
--- `kind` is "taught" (recipes) or "ranks" (rank training).
function Tradewright:GetTrainerOffers(kind, skillLineID)
	local offers = SourceLogic.TaughtOf(stores(), kind, tostring(skillLineID), playerFaction())
	for _, offer in pairs(offers) do
		nameZones(self, offer.trainers)
	end
	return offers
end

--- Where `itemID` has been looted, the likeliest source first; see SourceLogic.DropSources.
function Tradewright:GetDropSources(itemID)
	return SourceLogic.DropSources(stores(), tonumber(itemID))
end

--- Where the item that teaches `recipeName` comes from: `{ itemID, sellers, drops }`, or nil when
--- that item was never seen at a vendor or in loot.
function Tradewright:GetRecipeSource(recipeName)
	local source = SourceLogic.RecipeSource(stores(), recipeName, playerFaction())
	if source then
		nameZones(self, source.sellers)
	end
	return source
end

-- Vendor and trainer sightings were kept by NPC name in two other places before this store existed.
-- Whatever is still there is taken over once; the profession and auction modules may be switched
-- off, in which case their part waits until they are loaded again.
local function moveEarlierSightings(pe)
	local store = savedStore()
	if TradewrightAuctionDB and TradewrightAuctionDB.vendorSellers then
		SourceLogic.MoveVendorSellers(store, TradewrightAuctionDB.vendorSellers)
		TradewrightAuctionDB.vendorSellers = nil
	end
	for _, characterData in pairs(pe.db and pe.db.characters or {}) do
		local faction = characterData.meta and characterData.meta.faction
		SourceLogic.MoveTrainerEntries(store, "taught", characterData.trainerRecipes, faction)
		SourceLogic.MoveTrainerEntries(store, "ranks", characterData.trainerRanks, faction)
		characterData.trainerRecipes, characterData.trainerRanks = nil, nil
	end
end

local function countKeys(byKey)
	local count = 0
	for _ in pairs(byKey) do
		count = count + 1
	end
	return count
end

--- `/tradewright sources`: how much has been collected. `/tradewright sources seal` closes the loot
--- counts collected so far, so scripts/build-source-data.mjs can build them into the shipped data.
function Tradewright:HandleSourcesSlash(rest)
	local store = savedStore()
	if string.lower(rest or "") ~= "seal" then
		self:PrintMessage(string.format("Own sightings: %d NPCs, %d items sold by vendors, %d loot sources in the open count.",
			countKeys(store.npcs), countKeys(store.sold), countKeys(store.tallies[store.epoch] or {})))
		return
	end
	if SourceLogic.Seal(store) then
		self:PrintMessage("Loot counts so far are closed. Log out or /reload so they are written, then run: npm run sources:build")
	else
		self:PrintMessage("No loot counted since the last seal.")
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
	Tradewright:InitDB()
	moveEarlierSightings(Tradewright)
	-- Whatever the shipped data already states need not be saved a second time.
	SourceLogic.Prune(savedStore(), shippedStore)
end)
