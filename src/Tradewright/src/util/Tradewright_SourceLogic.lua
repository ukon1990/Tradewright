local _, Tradewright = ...

--- Pure helpers for the sightings store: where things come from, as the player has seen it. No WoW API.
---
--- A store holds
---   npcs    = { [npcKey] = { name, faction, places = { { mapID, x, y }, … } } }
---   objects = { [objectID] = { places } }                      herb nodes, veins, chests
---   sold    = { [itemID] = { [npcKey] = { price, limited, seenAt } } }
---   taught  = { [skillLineKey] = { [recipeName] = { skillRequired, cost, seenAt, npcs = { [npcKey] = true } } } }
---   ranks   = the same shape as taught, for a trainer's rank training
---   recipeItems = { [recipeName] = itemID }                    the item that teaches a recipe
---   tallies = { [epoch] = { [sourceKey] = { opened, items = { [itemID] = loots that held it } } } }
---   collectorID, epoch                                         see Seal and Prune
---
--- An `npcKey` is the NPC's id. Sightings from before ids were kept sit under "name:<npc name>" and
--- are taken over by the id the next time that NPC is met.
--- A `sourceKey` says what was looted: "n<npcID>" a kill, "g<npcID>" gathering from a corpse
--- (skinning), "o<objectID>" a node or chest, "f<mapID>" fishing.
---
--- Readers take `stores`, a list read in order: the data shipped with the addon first, the player's
--- own sightings last, so an own sighting wins.
local SourceLogic = {}
Tradewright.SourceLogic = SourceLogic

-- Places kept per NPC or object on one map, and how close two places are before they count as the
-- same one (a share of the map's width). Together they bound what a much-farmed mob can cost.
SourceLogic.PLACES_PER_MAP = 12
SourceLogic.PLACE_GRID = 0.02

local STORE_TABLES = { "npcs", "objects", "sold", "taught", "ranks", "recipeItems", "tallies" }
local TAUGHT_KINDS = { "taught", "ranks" }
local SOURCE_KIND_BY_PREFIX = { n = "kill", g = "gather", o = "object", f = "fishing" }
local PREFIX_BY_SOURCE_KIND = { kill = "n", gather = "g", object = "o", fishing = "f" }
-- Item classes worth tallying in loot: gem, reagent, trade goods, recipe.
local TALLIED_CLASS = { [3] = true, [5] = true, [7] = true, [9] = true }
local RECIPE_CLASS = 9

--- Fills in whatever a store lacks, so readers and writers need no nil checks. Returns the store.
function SourceLogic.EnsureStore(store, collectorID)
	store = store or {}
	for _, name in ipairs(STORE_TABLES) do
		store[name] = store[name] or {}
	end
	store.epoch = store.epoch or 1
	store.collectorID = store.collectorID or collectorID
	return store
end

--- What a GUID stands for: "npc" or "object" and its id; nil for players, pets and items.
function SourceLogic.SourceOfGUID(guid)
	local kind, id = tostring(guid or ""):match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
	if kind == "Creature" or kind == "Vehicle" then
		return "npc", tonumber(id)
	elseif kind == "GameObject" then
		return "object", tonumber(id)
	end
	return nil
end

function SourceLogic.SourceKey(kind, id)
	return PREFIX_BY_SOURCE_KIND[kind] .. tostring(id)
end

--- "kill", "gather", "object" or "fishing", and the id in the key.
function SourceLogic.ParseSourceKey(sourceKey)
	local prefix, id = tostring(sourceKey):match("^(%a)(%d+)$")
	return SOURCE_KIND_BY_PREFIX[prefix], tonumber(id)
end

function SourceLogic.IsTalliedClass(classID)
	return TALLIED_CLASS[classID] == true
end

--- The recipe a recipe item teaches, by name: "Pattern: Dusky Belt" gives "Dusky Belt". nil for an
--- item of another class or a name without that form.
function SourceLogic.RecipeNameOfItem(itemName, classID)
	if classID ~= RECIPE_CLASS then
		return nil
	end
	return tostring(itemName or ""):match("^[^:]+:%s*(.+)$")
end

local function gridCell(value)
	return math.floor(value / SourceLogic.PLACE_GRID)
end

-- Whether `places` already has one on the same map within the same grid cell.
local function hasPlaceNear(places, mapID, x, y)
	for _, known in ipairs(places) do
		if known[1] == mapID and gridCell(known[2]) == gridCell(x) and gridCell(known[3]) == gridCell(y) then
			return true
		end
	end
	return false
end

local function placesOnMap(places, mapID)
	local count = 0
	for _, known in ipairs(places) do
		if known[1] == mapID then
			count = count + 1
		end
	end
	return count
end

local function roundToThousandth(value)
	return math.floor(value * 1000 + 0.5) / 1000
end

--- Adds `place = { mapID, x, y }` (named fields) to a list of `{ mapID, x, y }` unless one is
--- already kept nearby or the map is full. Returns whether it was added.
function SourceLogic.AddPlace(places, place)
	local mapID, x, y = place and place.mapID, place and tonumber(place.x), place and tonumber(place.y)
	if not (mapID and x and y) or hasPlaceNear(places, mapID, x, y) then
		return false
	end
	if placesOnMap(places, mapID) >= SourceLogic.PLACES_PER_MAP then
		return false
	end
	places[#places + 1] = { mapID, roundToThousandth(x), roundToThousandth(y) }
	return true
end

local function addPlaces(places, more)
	for _, known in ipairs(more or {}) do
		SourceLogic.AddPlace(places, { mapID = known[1], x = known[2], y = known[3] })
	end
end

-- Moves byKey[from] to byKey[to]; what is already under `to` stays.
local function rekey(byKey, from, to)
	if byKey[from] ~= nil then
		byKey[to] = byKey[to] or byKey[from]
		byKey[from] = nil
	end
end

-- Hands everything recorded under "name:<name>" to the NPC now known by id.
local function adoptNamedSightings(store, npcID, name)
	local nameKey = "name:" .. name
	local named = store.npcs[nameKey]
	if not named then
		return
	end
	store.npcs[nameKey] = nil
	addPlaces(store.npcs[npcID].places, named.places)
	for _, sellers in pairs(store.sold) do
		rekey(sellers, nameKey, npcID)
	end
	for _, kind in ipairs(TAUGHT_KINDS) do
		for _, services in pairs(store[kind]) do
			for _, service in pairs(services) do
				rekey(service.npcs, nameKey, npcID)
			end
		end
	end
end

-- Who an NPC deals with, from two sightings: one faction, or "both" once each has met it.
local function mergeFaction(known, seen)
	if known and seen and known ~= seen then
		return "both"
	end
	return known or seen
end

-- Creates the NPC, or notes that the other faction has met it too.
local function npcSeenBy(store, key, faction)
	local npc = store.npcs[key]
	if not npc then
		npc = { places = {} }
		store.npcs[key] = npc
	end
	npc.faction = mergeFaction(npc.faction, faction)
	return npc
end

--- Records an NPC the player met. `sighting = { npcID, name, faction, place }`: `faction` is the
--- player's ("Horde", "Alliance"), `place = { mapID, x, y }`. An NPC met by both factions is kept
--- as "both". Returns the npcKey, or nil when neither an id nor a name is known.
function SourceLogic.RememberNpc(store, sighting)
	local key = sighting.npcID or (sighting.name and ("name:" .. sighting.name))
	if not key then
		return nil
	end
	local npc = npcSeenBy(store, key, sighting.faction)
	npc.name = sighting.name or npc.name
	if sighting.npcID and sighting.name then
		adoptNamedSightings(store, sighting.npcID, sighting.name)
	end
	SourceLogic.AddPlace(npc.places, sighting.place)
	return key
end

--- Records a looted node or chest and where it was.
function SourceLogic.RememberObject(store, objectID, place)
	store.objects[objectID] = store.objects[objectID] or { places = {} }
	SourceLogic.AddPlace(store.objects[objectID].places, place)
end

--- Records what a vendor sells. `entries = { [itemID] = { price, limited, seenAt } }`, as
--- VendorLogic.SellerEntries gives them.
function SourceLogic.RecordSold(store, npcKey, entries)
	for itemID, entry in pairs(entries or {}) do
		store.sold[itemID] = store.sold[itemID] or {}
		store.sold[itemID][npcKey] = { price = entry.price, limited = entry.limited, seenAt = entry.seenAt }
	end
end

-- One trainer service seen again: terms from the newer sighting, every trainer kept.
local function mergeService(known, entry, npcKey)
	local service = known or { npcs = {} }
	if not known or (entry.seenAt or 0) >= (known.seenAt or 0) then
		service.skillRequired, service.cost, service.seenAt = entry.skillRequired, entry.cost, entry.seenAt
	end
	service.npcs[npcKey] = true
	return service
end

--- Records what a trainer offers. `kind` is "taught" (recipes) or "ranks" (rank training);
--- `entries = { [skillLineKey] = { [serviceName] = { skillRequired, cost, seenAt } } }`.
function SourceLogic.RecordTaught(store, kind, npcKey, entries)
	for skillLineKey, services in pairs(entries or {}) do
		local stored = store[kind][skillLineKey] or {}
		store[kind][skillLineKey] = stored
		for serviceName, entry in pairs(services) do
			stored[serviceName] = mergeService(stored[serviceName], entry, npcKey)
		end
	end
end

--- Records one opened loot: `sourceKey` was opened once and held each of `itemIDs`.
function SourceLogic.RecordLoot(store, sourceKey, itemIDs)
	local bucket = store.tallies[store.epoch] or {}
	store.tallies[store.epoch] = bucket
	local tally = bucket[sourceKey] or { opened = 0, items = {} }
	bucket[sourceKey] = tally
	tally.opened = tally.opened + 1
	local counted = {}
	for _, itemID in ipairs(itemIDs or {}) do
		if not counted[itemID] then
			counted[itemID] = true
			tally.items[itemID] = (tally.items[itemID] or 0) + 1
		end
	end
end

--- Splits one loot window by what it came from. `slots = { { itemID, tallied, guids = { guid, … } } }`
--- as the window lists them; several corpses looted at once share a window. Returns
--- `{ [guid] = { itemID, … } }` with the tallied items each source held; a source that held none
--- still gets an empty list, because it was opened.
function SourceLogic.LootBySource(slots)
	local bySource = {}
	for _, slot in ipairs(slots or {}) do
		for _, guid in ipairs(slot.guids or {}) do
			bySource[guid] = bySource[guid] or {}
			if slot.itemID and slot.tallied then
				table.insert(bySource[guid], slot.itemID)
			end
		end
	end
	return bySource
end

--- The NPC behind `npcKey` across `stores`: `{ name, faction, places }`, or nil.
function SourceLogic.Npc(stores, npcKey)
	local merged
	for _, store in ipairs(stores) do
		local npc = store.npcs[npcKey]
		if npc then
			merged = merged or { places = {} }
			merged.name, merged.faction = npc.name or merged.name, mergeFaction(merged.faction, npc.faction)
			addPlaces(merged.places, npc.places)
		end
	end
	return merged
end

-- Whether an NPC deals with a player of `faction`. An NPC only ever met by the other faction does not.
local function dealsWith(npc, faction)
	return not (faction and npc.faction) or npc.faction == "both" or npc.faction == faction
end

-- `{ mapID, x, y }` of the first place kept for an NPC, as named fields; empty when none.
local function firstPlace(npc)
	local place = npc.places[1]
	return place and { mapID = place[1], x = place[2], y = place[3] } or {}
end

--- Vendors selling `itemID` to a player of `faction`:
--- `{ [npcName] = { price, limited, mapID, x, y, seenAt } }`, the shape VendorLogic.Lookup reads.
function SourceLogic.SellersOf(stores, itemID, faction)
	local sellers = {}
	for _, store in ipairs(stores) do
		for npcKey, entry in pairs(store.sold[itemID] or {}) do
			local npc = SourceLogic.Npc(stores, npcKey)
			if npc and npc.name and dealsWith(npc, faction) then
				local seller = firstPlace(npc)
				seller.price, seller.limited, seller.seenAt = entry.price, entry.limited, entry.seenAt
				sellers[npc.name] = seller
			end
		end
	end
	return sellers
end

-- Adds the trainers of one stored service that deal with `faction`, by name with their place.
local function addTrainers(trainers, stores, service, faction)
	for npcKey in pairs(service.npcs) do
		local npc = SourceLogic.Npc(stores, npcKey)
		if npc and npc.name and dealsWith(npc, faction) then
			trainers[npc.name] = firstPlace(npc)
		end
	end
end

--- What trainers offer for one profession, to a player of `faction`:
--- `{ [serviceName] = { skillRequired, cost, seenAt, trainers = { [npcName] = { mapID, x, y } } } }`.
--- `kind` is "taught" or "ranks". The terms come from the last store that has the service.
function SourceLogic.TaughtOf(stores, kind, skillLineKey, faction)
	local offered = {}
	for _, store in ipairs(stores) do
		for serviceName, service in pairs(store[kind][skillLineKey] or {}) do
			local merged = offered[serviceName] or { trainers = {} }
			offered[serviceName] = merged
			merged.skillRequired, merged.cost, merged.seenAt = service.skillRequired, service.cost, service.seenAt
			addTrainers(merged.trainers, stores, service, faction)
		end
	end
	return offered
end

-- Loots opened and loots that held `itemID`, per source, added up over every store and epoch.
local function dropTallies(stores, itemID)
	local bySource = {}
	for _, store in ipairs(stores) do
		for _, bucket in pairs(store.tallies) do
			for sourceKey, tally in pairs(bucket) do
				local held = tally.items[itemID]
				if held then
					local total = bySource[sourceKey] or { opened = 0, held = 0 }
					bySource[sourceKey] = total
					total.opened, total.held = total.opened + tally.opened, total.held + held
				end
			end
		end
	end
	return bySource
end

-- Name and places of what a source key points at. Fishing has neither: its id is the map.
local function describeSource(stores, kind, id)
	if kind == "kill" or kind == "gather" then
		local npc = SourceLogic.Npc(stores, id) or {}
		return npc.name, npc.places or {}
	end
	local places = {}
	if kind == "object" then
		for _, store in ipairs(stores) do
			addPlaces(places, store.objects[id] and store.objects[id].places)
		end
	end
	return nil, places
end

--- Where `itemID` has been looted, the likeliest source first:
--- `{ { kind, id, name, opened, held, share, places = { { mapID, x, y }, … } }, … }`.
--- `kind` is "kill", "gather", "object" or "fishing" (then `id` is the map); `share` is the part of
--- the loots opened that held the item. A corpse with nothing on it opens no loot, so the share of
--- a kill reads a little high.
function SourceLogic.DropSources(stores, itemID)
	local sources = {}
	for sourceKey, total in pairs(dropTallies(stores, itemID)) do
		local kind, id = SourceLogic.ParseSourceKey(sourceKey)
		local name, places = describeSource(stores, kind, id)
		sources[#sources + 1] = {
			kind = kind, id = id, name = name, places = places,
			opened = total.opened, held = total.held, share = total.held / total.opened,
		}
	end
	table.sort(sources, function(a, b)
		if a.share ~= b.share then
			return a.share > b.share
		end
		return a.opened > b.opened
	end)
	return sources
end

--- Where the recipe item of `recipeName` comes from, for a player of `faction`:
--- `{ itemID, sellers, drops }` (see SellersOf and DropSources), or nil when the item was never seen.
function SourceLogic.RecipeSource(stores, recipeName, faction)
	local itemID
	for _, store in ipairs(stores) do
		itemID = store.recipeItems[recipeName] or itemID
	end
	if not itemID then
		return nil
	end
	return { itemID = itemID, sellers = SourceLogic.SellersOf(stores, itemID, faction), drops = SourceLogic.DropSources(stores, itemID) }
end

--- Takes over vendor sightings kept before this store existed:
--- `vendorSellers = { [itemID] = { [npcName] = { price, limited, mapID, x, y, seenAt } } }`.
function SourceLogic.MoveVendorSellers(store, vendorSellers)
	for itemID, sellers in pairs(vendorSellers or {}) do
		for npcName, entry in pairs(sellers) do
			local npcKey = SourceLogic.RememberNpc(store, { name = npcName, place = entry })
			SourceLogic.RecordSold(store, npcKey, { [itemID] = entry })
		end
	end
end

--- Takes over one character's trainer sightings kept before this store existed:
--- `entries = { [skillLineKey] = { [serviceName] = { skillRequired, cost, seenAt, trainers = { [npcName] = place } } } }`,
--- seen by a character of `faction`. `kind` is "taught" or "ranks".
function SourceLogic.MoveTrainerEntries(store, kind, entries, faction)
	for skillLineKey, services in pairs(entries or {}) do
		for serviceName, entry in pairs(services) do
			for npcName, place in pairs(entry.trainers or {}) do
				local npcKey = SourceLogic.RememberNpc(store, { name = npcName, faction = faction, place = place })
				SourceLogic.RecordTaught(store, kind, npcKey, { [skillLineKey] = { [serviceName] = entry } })
			end
		end
	end
end

--- Closes the current tally epoch so it can be shipped, and starts the next. Returns the epoch that
--- was closed, or nil when it held nothing.
function SourceLogic.Seal(store)
	if not next(store.tallies[store.epoch] or {}) then
		return nil
	end
	store.epoch = store.epoch + 1
	return store.epoch - 1
end

-- Shipping. Collected sightings can be built into the data file that ships with the addon
-- (ShipStore, run by scripts/build-source-data.lua). A player's saved store then drops whatever that
-- file already states (Prune), so nothing is kept twice.
-- A fact (a price, a place, a trainer's terms) is the same fact wherever it was seen, so it can be
-- compared. A loot count cannot: the collector's own counts are inside the shipped ones. Counts are
-- therefore kept per epoch; only closed epochs are shipped, and the shipped data notes per collector
-- up to which epoch it holds them (`collected = { [collectorID] = epoch }`).

-- Ids only: a name-keyed sighting waits until the NPC is met and its id is known.
local function isShippable(npcKey)
	return type(npcKey) == "number"
end

local function shipNpcs(shipped, store)
	for npcKey, npc in pairs(store.npcs) do
		if isShippable(npcKey) then
			local target = shipped.npcs[npcKey] or { places = {} }
			shipped.npcs[npcKey] = target
			target.name, target.faction = npc.name or target.name, mergeFaction(target.faction, npc.faction)
			addPlaces(target.places, npc.places)
		end
	end
	for objectID, object in pairs(store.objects) do
		shipped.objects[objectID] = shipped.objects[objectID] or { places = {} }
		addPlaces(shipped.objects[objectID].places, object.places)
	end
end

local function shipSold(shipped, store)
	for itemID, sellers in pairs(store.sold) do
		for npcKey, entry in pairs(sellers) do
			if isShippable(npcKey) then
				SourceLogic.RecordSold(shipped, npcKey, { [itemID] = entry })
			end
		end
	end
end

local function shipTaught(shipped, store, kind)
	for skillLineKey, services in pairs(store[kind]) do
		for serviceName, service in pairs(services) do
			for npcKey in pairs(service.npcs) do
				if isShippable(npcKey) then
					SourceLogic.RecordTaught(shipped, kind, npcKey, { [skillLineKey] = { [serviceName] = service } })
				end
			end
		end
	end
end

-- Shipped tallies sit in one bucket; which epoch a count came from no longer matters there.
local SHIPPED_EPOCH = 0

local function addTally(bucket, sourceKey, tally)
	local total = bucket[sourceKey] or { opened = 0, items = {} }
	bucket[sourceKey] = total
	total.opened = total.opened + tally.opened
	for itemID, held in pairs(tally.items) do
		total.items[itemID] = (total.items[itemID] or 0) + held
	end
end

-- Adds the store's closed epochs that are not shipped yet. Returns the last epoch now shipped.
local function shipTallies(shipped, store, shippedUpTo)
	local bucket = shipped.tallies[SHIPPED_EPOCH] or {}
	shipped.tallies[SHIPPED_EPOCH] = bucket
	for epoch, tallies in pairs(store.tallies) do
		if epoch > shippedUpTo and epoch < store.epoch then
			for sourceKey, tally in pairs(tallies) do
				addTally(bucket, sourceKey, tally)
			end
		end
	end
	return math.max(shippedUpTo, store.epoch - 1)
end

--- Adds a collector's saved store to the data to ship. Facts overwrite what is shipped; loot counts
--- of closed epochs are added once, however often the same store is shipped. Returns `shipped`.
function SourceLogic.ShipStore(shipped, store)
	shipped = SourceLogic.EnsureStore(shipped)
	shipped.collected = shipped.collected or {}
	shipNpcs(shipped, store)
	shipSold(shipped, store)
	for _, kind in ipairs(TAUGHT_KINDS) do
		shipTaught(shipped, store, kind)
	end
	for recipeName, itemID in pairs(store.recipeItems) do
		shipped.recipeItems[recipeName] = itemID
	end
	shipped.collected[store.collectorID] = shipTallies(shipped, store, shipped.collected[store.collectorID] or 0)
	return shipped
end

-- Removes the entries of `byKey` that have become empty tables.
local function dropEmpty(byKey)
	for key, value in pairs(byKey) do
		if next(value) == nil then
			byKey[key] = nil
		end
	end
end

-- The places of `places` that `known` has none near.
local function placesNotIn(places, known)
	local kept = {}
	for _, place in ipairs(places) do
		if not hasPlaceNear(known, place[1], place[2], place[3]) then
			kept[#kept + 1] = place
		end
	end
	return kept
end

-- An NPC is dropped once the shipped data says everything the saved entry says.
local function pruneNpcs(store, shipped)
	for npcKey, npc in pairs(store.npcs) do
		local known = shipped.npcs[npcKey]
		if known then
			npc.places = placesNotIn(npc.places, known.places)
			local sameName = npc.name == nil or npc.name == known.name
			if sameName and not npc.places[1] and mergeFaction(known.faction, npc.faction) == known.faction then
				store.npcs[npcKey] = nil
			end
		end
	end
end

-- A node or chest is only its places, so it goes once the shipped data has them all.
local function pruneObjects(store, shipped)
	for objectID, object in pairs(store.objects) do
		local known = shipped.objects[objectID]
		if known then
			object.places = placesNotIn(object.places, known.places)
			if not object.places[1] then
				store.objects[objectID] = nil
			end
		end
	end
end

local function pruneSold(store, shipped)
	for itemID, sellers in pairs(store.sold) do
		for npcKey, entry in pairs(sellers) do
			local known = shipped.sold[itemID] and shipped.sold[itemID][npcKey]
			if known and known.price == entry.price and known.limited == entry.limited then
				sellers[npcKey] = nil
			end
		end
	end
	dropEmpty(store.sold)
end

-- Same terms, and every trainer of `service` is among the shipped ones.
local function isShippedService(known, service)
	if not known or known.skillRequired ~= service.skillRequired or known.cost ~= service.cost then
		return false
	end
	for npcKey in pairs(service.npcs) do
		if not known.npcs[npcKey] then
			return false
		end
	end
	return true
end

local function pruneTaught(store, shipped, kind)
	for skillLineKey, services in pairs(store[kind]) do
		for serviceName, service in pairs(services) do
			if isShippedService(shipped[kind][skillLineKey] and shipped[kind][skillLineKey][serviceName], service) then
				services[serviceName] = nil
			end
		end
	end
	dropEmpty(store[kind])
end

-- Drops this collector's epochs that the shipped data already holds, and never reuses their numbers.
local function pruneTallies(store, shipped)
	local shippedUpTo = shipped.collected and shipped.collected[store.collectorID]
	if not shippedUpTo then
		return
	end
	for epoch in pairs(store.tallies) do
		if epoch <= shippedUpTo then
			store.tallies[epoch] = nil
		end
	end
	store.epoch = math.max(store.epoch, shippedUpTo + 1)
end

--- Deletes from a saved `store` everything the `shipped` data already states, so readers that use
--- both answer as before. Sightings that differ from or add to the shipped data stay.
function SourceLogic.Prune(store, shipped)
	pruneSold(store, shipped)
	for _, kind in ipairs(TAUGHT_KINDS) do
		pruneTaught(store, shipped, kind)
	end
	for recipeName, itemID in pairs(store.recipeItems) do
		if shipped.recipeItems[recipeName] == itemID then
			store.recipeItems[recipeName] = nil
		end
	end
	pruneNpcs(store, shipped)
	pruneObjects(store, shipped)
	pruneTallies(store, shipped)
end

return SourceLogic
