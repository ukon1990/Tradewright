-- Run with: lua5.1 tests/test_source_logic.lua (from Tradewright root)
local root = arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]") or "."

local failed = 0
local function check(name, cond, detail)
	if cond then
		print("OK  " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
	end
end

local pe = {}
local chunk, err = loadfile(root .. "/src/util/Tradewright_SourceLogic.lua")
assert(chunk, err)
chunk("Tradewright", pe)
local SL = pe.SourceLogic
assert(SL, "SourceLogic missing")

local THUNDER_BLUFF, MULGORE = 1456, 1412
local UNA, KODO = 3007, 2956
local LIGHT_LEATHER, FINE_THREAD, PATTERN = 2318, 2321, 5786

-- What a GUID stands for
do
	local kind, id = SL.SourceOfGUID("Creature-0-4460-1-12-3007-000012AB34")
	check("GUID: creature id", kind == "npc" and id == 3007)
	kind, id = SL.SourceOfGUID("GameObject-0-4460-1-12-1731-000012AB34")
	check("GUID: object id", kind == "object" and id == 1731)
	check("GUID: a player, an item and nothing give nil",
		SL.SourceOfGUID("Player-4460-0012AB34") == nil and SL.SourceOfGUID("Item-4460-0-40000012AB34") == nil and SL.SourceOfGUID(nil) == nil)
	local sourceKind, sourceID = SL.ParseSourceKey(SL.SourceKey("gather", 2956))
	check("Source key: round trip", sourceKind == "gather" and sourceID == 2956)
end

-- Places stay few
do
	local places = {}
	check("Place: first one is kept", SL.AddPlace(places, { mapID = MULGORE, x = 0.5012, y = 0.3 }) and #places == 1)
	check("Place: kept to a thousandth of the map", places[1][2] == 0.501)
	check("Place: one nearby is the same place", not SL.AddPlace(places, { mapID = MULGORE, x = 0.505, y = 0.305 }) and #places == 1)
	check("Place: the same spot on another map is another place", SL.AddPlace(places, { mapID = THUNDER_BLUFF, x = 0.5, y = 0.3 }))
	check("Place: no position, nothing kept", not SL.AddPlace(places, { mapID = MULGORE }) and not SL.AddPlace(places, nil))
	for step = 1, 30 do
		SL.AddPlace(places, { mapID = MULGORE, x = step * 0.03, y = 0.9 })
	end
	local onMulgore = 0
	for _, place in ipairs(places) do
		onMulgore = onMulgore + (place[1] == MULGORE and 1 or 0)
	end
	check("Place: a map holds at most 12", onMulgore == SL.PLACES_PER_MAP, onMulgore)
end

-- Vendors
do
	local store = SL.EnsureStore(nil, "me")
	local key = SL.RememberNpc(store, { npcID = UNA, name = "Una", faction = "Horde", place = { mapID = THUNDER_BLUFF, x = 0.42, y = 0.43 } })
	SL.RecordSold(store, key, { [FINE_THREAD] = { price = 100, seenAt = 10 }, [PATTERN] = { price = 550, limited = true, seenAt = 10 } })
	local sellers = SL.SellersOf({ store }, FINE_THREAD, "Horde")
	check("Sold: seller by name with price and place",
		sellers.Una and sellers.Una.price == 100 and sellers.Una.mapID == THUNDER_BLUFF and sellers.Una.x == 0.42)
	check("Sold: limited stock is passed on", SL.SellersOf({ store }, PATTERN, "Horde").Una.limited == true)
	check("Sold: the other faction's vendor is left out", next(SL.SellersOf({ store }, FINE_THREAD, "Alliance")) == nil)
	SL.RememberNpc(store, { npcID = UNA, name = "Una", faction = "Alliance" })
	check("Sold: a vendor met by both factions sells to both", SL.SellersOf({ store }, FINE_THREAD, "Alliance").Una ~= nil)
	check("Sold: unknown item", next(SL.SellersOf({ store }, 1, "Horde")) == nil)

	local shipped = SL.EnsureStore({})
	SL.RememberNpc(shipped, { npcID = UNA, name = "Una", faction = "Horde", place = { mapID = THUNDER_BLUFF, x = 0.42, y = 0.43 } })
	SL.RecordSold(shipped, UNA, { [FINE_THREAD] = { price = 90, seenAt = 1 } })
	check("Stores: the own sighting wins over the shipped one", SL.SellersOf({ shipped, store }, FINE_THREAD, "Horde").Una.price == 100)
	local own = SL.EnsureStore(nil, "me")
	check("Stores: shipped data answers alone", SL.SellersOf({ shipped, own }, FINE_THREAD, "Horde").Una.price == 90)
end

-- Trainers
do
	local store = SL.EnsureStore(nil, "me")
	local una = SL.RememberNpc(store, { npcID = UNA, name = "Una", faction = "Horde", place = { mapID = THUNDER_BLUFF, x = 0.42, y = 0.43 } })
	local karolek = SL.RememberNpc(store, { npcID = 3365, name = "Karolek", faction = "Horde", place = { mapID = 1454, x = 0.63, y = 0.44 } })
	SL.RecordTaught(store, "taught", una, { ["165"] = { ["Dusky Belt"] = { skillRequired = 170, cost = 2250, seenAt = 100 } } })
	SL.RecordTaught(store, "taught", karolek, { ["165"] = { ["Dusky Belt"] = { skillRequired = 170, cost = 2000, seenAt = 200 } } })
	SL.RecordTaught(store, "ranks", una, { ["165"] = { ["Expert Leatherworker"] = { skillRequired = 125, cost = 5000, seenAt = 100 } } })
	local belt = SL.TaughtOf({ store }, "taught", "165", "Horde")["Dusky Belt"]
	check("Taught: terms from the newer sighting", belt.cost == 2000 and belt.skillRequired == 170)
	check("Taught: every trainer with its place", belt.trainers.Una.mapID == THUNDER_BLUFF and belt.trainers.Karolek.x == 0.63)
	SL.RecordTaught(store, "taught", una, { ["165"] = { ["Dusky Belt"] = { skillRequired = 170, cost = 9999, seenAt = 50 } } })
	check("Taught: an older sighting does not change the terms", SL.TaughtOf({ store }, "taught", "165", "Horde")["Dusky Belt"].cost == 2000)
	check("Taught: rank training is kept apart", SL.TaughtOf({ store }, "ranks", "165", "Horde")["Expert Leatherworker"].cost == 5000
		and SL.TaughtOf({ store }, "taught", "165", "Horde")["Expert Leatherworker"] == nil)
	local forAlliance = SL.TaughtOf({ store }, "taught", "165", "Alliance")["Dusky Belt"]
	check("Taught: the other faction sees the terms but no trainer", forAlliance.cost == 2000 and next(forAlliance.trainers) == nil)
	check("Taught: another profession has nothing", next(SL.TaughtOf({ store }, "taught", "197", "Horde")) == nil)
end

-- Loot
do
	local bySource = SL.LootBySource({
		{ itemID = LIGHT_LEATHER, tallied = true, guids = { "a", "b" } },
		{ itemID = 117, tallied = false, guids = { "a" } },
		{ itemID = nil, guids = { "c" } },
	})
	check("Loot: tallied items go to each source of the slot", bySource.a[1] == LIGHT_LEATHER and #bySource.a == 1 and bySource.b[1] == LIGHT_LEATHER)
	check("Loot: a source that held nothing of interest was still opened", bySource.c and #bySource.c == 0)

	local store = SL.EnsureStore(nil, "me")
	SL.RememberNpc(store, { npcID = KODO, name = "Adult Plainstrider", place = { mapID = MULGORE, x = 0.5, y = 0.5 } })
	local gather = SL.SourceKey("gather", KODO)
	SL.RecordLoot(store, gather, { LIGHT_LEATHER, LIGHT_LEATHER })
	SL.RecordLoot(store, gather, {})
	SL.RecordLoot(store, gather, { LIGHT_LEATHER })
	SL.RecordLoot(store, gather, {})
	SL.RememberObject(store, 1731, { mapID = MULGORE, x = 0.2, y = 0.2 })
	SL.RecordLoot(store, SL.SourceKey("object", 1731), { LIGHT_LEATHER })
	SL.RecordLoot(store, SL.SourceKey("fishing", MULGORE), { 6291 })
	local drops = SL.DropSources({ store }, LIGHT_LEATHER)
	check("Drops: the likeliest source first", #drops == 2 and drops[1].kind == "object" and drops[1].share == 1)
	check("Drops: an item twice in one loot counts once", drops[2].held == 2 and drops[2].opened == 4 and drops[2].share == 0.5)
	check("Drops: a creature has its name and places", drops[2].kind == "gather" and drops[2].name == "Adult Plainstrider" and drops[2].places[1][1] == MULGORE)
	check("Drops: a node has its places", drops[1].places[1][2] == 0.2)
	local fish = SL.DropSources({ store }, 6291)[1]
	check("Drops: fishing names the map", fish.kind == "fishing" and fish.id == MULGORE and #fish.places == 0)
	check("Drops: never seen", #SL.DropSources({ store }, 1) == 0)

	check("Seal: closes the epoch that holds loot", SL.Seal(store) == 1 and store.epoch == 2)
	check("Seal: an empty epoch is not closed", SL.Seal(store) == nil and store.epoch == 2)
	SL.RecordLoot(store, gather, { LIGHT_LEATHER })
	local total = SL.DropSources({ store }, LIGHT_LEATHER)
	check("Drops: epochs add up", total[2].held == 3 and total[2].opened == 5)
	local shipped = SL.EnsureStore({})
	SL.RecordLoot(shipped, gather, { LIGHT_LEATHER })
	local withShipped = SL.DropSources({ shipped, store }, LIGHT_LEATHER)
	check("Drops: shipped tallies add to the own ones", withShipped[2].opened == 6 and withShipped[2].name == "Adult Plainstrider")
end

-- Recipe items
do
	check("Recipe item: name after the colon", SL.RecipeNameOfItem("Pattern: Dusky Belt", 9) == "Dusky Belt")
	check("Recipe item: another class is no recipe", SL.RecipeNameOfItem("Potion: Something", 0) == nil)
	check("Recipe item: a name without the form", SL.RecipeNameOfItem("Dusky Belt", 9) == nil)
	check("Tallied classes: materials and recipes, not gear",
		SL.IsTalliedClass(7) and SL.IsTalliedClass(9) and not SL.IsTalliedClass(4) and not SL.IsTalliedClass(nil))

	local store = SL.EnsureStore(nil, "me")
	check("Recipe source: item never seen", SL.RecipeSource({ store }, "Dusky Belt", "Horde") == nil)
	store.recipeItems["Dusky Belt"] = PATTERN
	local key = SL.RememberNpc(store, { npcID = UNA, name = "Una", faction = "Horde", place = { mapID = THUNDER_BLUFF, x = 0.42, y = 0.43 } })
	SL.RecordSold(store, key, { [PATTERN] = { price = 550, limited = true, seenAt = 10 } })
	SL.RecordLoot(store, SL.SourceKey("kill", KODO), { PATTERN })
	local source = SL.RecipeSource({ store }, "Dusky Belt", "Horde")
	check("Recipe source: vendor and drop of the recipe item",
		source.itemID == PATTERN and source.sellers.Una.price == 550 and source.drops[1].kind == "kill")
end

-- Sightings kept by name before the store existed
do
	local store = SL.EnsureStore(nil, "me")
	SL.MoveVendorSellers(store, { [FINE_THREAD] = { Una = { price = 100, mapID = THUNDER_BLUFF, x = 0.42, y = 0.43, seenAt = 5 } } })
	SL.MoveTrainerEntries(store, "taught", {
		["165"] = { ["Dusky Belt"] = { skillRequired = 170, cost = 2250, seenAt = 5, trainers = { Una = { mapID = THUNDER_BLUFF, x = 0.42, y = 0.43 } } } },
	}, "Horde")
	check("Move: vendor known by name", SL.SellersOf({ store }, FINE_THREAD, "Horde").Una.price == 100)
	check("Move: trainer known by name", SL.TaughtOf({ store }, "taught", "165", "Horde")["Dusky Belt"].trainers.Una.mapID == THUNDER_BLUFF)
	check("Move: nothing to move", pcall(SL.MoveVendorSellers, store, nil) and pcall(SL.MoveTrainerEntries, store, "ranks", nil, "Horde"))

	SL.RememberNpc(store, { npcID = UNA, name = "Una", faction = "Horde", place = { mapID = THUNDER_BLUFF, x = 0.421, y = 0.431 } })
	check("Move: meeting the NPC hands its sightings to the id", store.npcs["name:Una"] == nil and store.sold[FINE_THREAD][UNA] ~= nil
		and store.sold[FINE_THREAD]["name:Una"] == nil and store.taught["165"]["Dusky Belt"].npcs[UNA] == true)
	check("Move: the place is not kept twice", #store.npcs[UNA].places == 1)
	check("Move: readers answer as before", SL.SellersOf({ store }, FINE_THREAD, "Horde").Una.price == 100)
end

-- Shipping collected data, and dropping what is then kept twice
do
	local function collect(collectorID)
		local store = SL.EnsureStore(nil, collectorID)
		local una = SL.RememberNpc(store, { npcID = UNA, name = "Una", faction = "Horde", place = { mapID = THUNDER_BLUFF, x = 0.42, y = 0.43 } })
		SL.RecordSold(store, una, { [FINE_THREAD] = { price = 100, seenAt = 10 } })
		SL.RecordTaught(store, "taught", una, { ["165"] = { ["Dusky Belt"] = { skillRequired = 170, cost = 2250, seenAt = 10 } } })
		store.recipeItems["Dusky Belt"] = PATTERN
		SL.RememberNpc(store, { npcID = KODO, name = "Adult Plainstrider", place = { mapID = MULGORE, x = 0.5, y = 0.5 } })
		SL.RecordLoot(store, SL.SourceKey("gather", KODO), { LIGHT_LEATHER })
		SL.RecordLoot(store, SL.SourceKey("gather", KODO), {})
		return store
	end
	local function gathered(stores)
		return SL.DropSources(stores, LIGHT_LEATHER)[1]
	end

	local mine = collect("me")
	SL.MoveVendorSellers(mine, { [FINE_THREAD] = { Wik = { price = 120, mapID = MULGORE, x = 0.1, y = 0.1 } } })
	local shipped = SL.ShipStore(nil, mine)
	check("Ship: facts are shipped", SL.SellersOf({ shipped }, FINE_THREAD, "Horde").Una.price == 100
		and SL.TaughtOf({ shipped }, "taught", "165", "Horde")["Dusky Belt"].trainers.Una ~= nil and shipped.recipeItems["Dusky Belt"] == PATTERN)
	check("Ship: an NPC known by name only waits for its id", SL.SellersOf({ shipped }, FINE_THREAD, "Horde").Wik == nil)
	check("Ship: an open epoch is not shipped", gathered({ shipped }) == nil and shipped.collected.me == 0)

	SL.Seal(mine)
	SL.ShipStore(shipped, mine)
	check("Ship: a closed epoch is shipped", gathered({ shipped }).opened == 2 and shipped.collected.me == 1)
	SL.ShipStore(shipped, mine)
	check("Ship: shipping the same store again adds nothing", gathered({ shipped }).opened == 2)

	local before = gathered({ shipped, mine }).opened
	SL.Prune(mine, shipped)
	check("Prune: own counts are inside the shipped ones, so before pruning they count twice", before == 4)
	check("Prune: the collector's shipped epochs are dropped", mine.tallies[1] == nil and gathered({ shipped, mine }).opened == 2)
	check("Prune: shipped facts are dropped", mine.sold[FINE_THREAD][UNA] == nil and mine.taught["165"] == nil
		and mine.recipeItems["Dusky Belt"] == nil and mine.npcs[UNA] == nil)
	check("Prune: what was not shipped stays", mine.sold[FINE_THREAD]["name:Wik"] ~= nil and mine.npcs["name:Wik"] ~= nil)
	check("Prune: readers answer as before", SL.SellersOf({ shipped, mine }, FINE_THREAD, "Horde").Una.price == 100
		and SL.SellersOf({ shipped, mine }, FINE_THREAD, "Horde").Wik.price == 120)
	SL.RecordLoot(mine, SL.SourceKey("gather", KODO), { LIGHT_LEATHER })
	check("Prune: new loot goes to a fresh epoch and adds to the shipped counts", mine.epoch == 2 and gathered({ shipped, mine }).opened == 3)

	local theirs = collect("them")
	SL.RecordSold(theirs, UNA, { [FINE_THREAD] = { price = 110, seenAt = 20 } })
	SL.RememberNpc(theirs, { npcID = UNA, name = "Una", faction = "Alliance", place = { mapID = MULGORE, x = 0.9, y = 0.9 } })
	SL.Prune(theirs, shipped)
	check("Prune: another collector keeps its own counts", gathered({ shipped, theirs }).opened == 4)
	check("Prune: a sighting that differs from the shipped one stays", theirs.sold[FINE_THREAD][UNA].price == 110)
	check("Prune: an NPC keeps only what the shipped data lacks",
		theirs.npcs[UNA] ~= nil and #theirs.npcs[UNA].places == 1 and theirs.npcs[UNA].places[1][1] == MULGORE)
	check("Prune: the NPC met by the other faction still sells to it", SL.SellersOf({ shipped, theirs }, FINE_THREAD, "Alliance").Una.price == 110)
	check("Prune: an NPC the shipped data fully covers is dropped", theirs.npcs[KODO] == nil)
end

if failed > 0 then
	print(failed .. " check(s) failed")
	os.exit(1)
end
print("All source logic checks passed")
