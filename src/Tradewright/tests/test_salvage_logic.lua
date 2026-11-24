-- Run with: lua5.1 tests/test_salvage_logic.lua (from Tradewright root)
-- Salvage yields: recording what disenchanting, prospecting and milling gave, the average per
-- destroyed item, whose numbers are trusted, the value, and shipping with the sightings store.
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
for _, file in ipairs({ "Tradewright_SourceLogic.lua", "Tradewright_SalvageLogic.lua" }) do
	local chunk, err = loadfile(root .. "/src/util/" .. file)
	assert(chunk, err)
	chunk("Tradewright", pe)
end
local SourceLogic, SalvageLogic = pe.SourceLogic, pe.SalvageLogic

local COPPER_ORE, TIGERSEYE, MALACHITE, STRANGE_DUST = 2770, 818, 774, 10940
local ORE = { itemID = COPPER_ORE }

local function newStore(collectorID)
	return SourceLogic.EnsureStore({}, collectorID or "me")
end

-- `casts` prospects of five ore, each giving one tigerseye.
local function prospect(store, casts)
	for _ = 1, casts do
		SalvageLogic.RecordOutcome(store, "prospect", { input = ORE, inputCount = 5, results = { [TIGERSEYE] = 1 } })
	end
end

-- Recording and the average
do
	local store = newStore()
	SalvageLogic.RecordOutcome(store, "prospect", { input = ORE, inputCount = 5, results = { [TIGERSEYE] = 1, [MALACHITE] = 2 } })
	SalvageLogic.RecordOutcome(store, "prospect", { input = ORE, inputCount = 5, results = { [MALACHITE] = 1 } })
	SalvageLogic.RecordOutcome(store, "prospect", { input = ORE, inputCount = 5, results = {} })
	local yield = SalvageLogic.Yield({ own = store }, "prospect", ORE)
	check("Quantities are averaged per destroyed item, empty casts included",
		yield.casts == 3 and yield.perInput[MALACHITE] == 3 / 15 and yield.perInput[TIGERSEYE] == 1 / 15)
	check("How many items one cast destroys comes with it", yield.inputsPerCast == 5)
	check("Milling the same item is another record", SalvageLogic.Yield({ own = store }, "mill", ORE) == nil)
	check("Nothing known: nil", SalvageLogic.Yield({}, "prospect", { itemID = 1 }) == nil)
end

-- An outcome read from the bags before and after
do
	local before = { [COPPER_ORE] = 20, [TIGERSEYE] = 3, [STRANGE_DUST] = 7 }
	local outcome = SalvageLogic.OutcomeBetween(before, { [COPPER_ORE] = 15, [TIGERSEYE] = 4, [MALACHITE] = 2, [STRANGE_DUST] = 7 })
	check("Bags: what went down is the input, what went up the results",
		outcome.inputItemID == COPPER_ORE and outcome.inputCount == 5 and outcome.results[TIGERSEYE] == 1
		and outcome.results[MALACHITE] == 2 and outcome.results[STRANGE_DUST] == nil)
	check("Bags: the last of a stack counts as an input", SalvageLogic.OutcomeBetween({ [COPPER_ORE] = 5 }, { [MALACHITE] = 1 }).inputCount == 5)
	check("Bags: nothing received yet is no outcome", SalvageLogic.OutcomeBetween(before, { [COPPER_ORE] = 15, [TIGERSEYE] = 3, [STRANGE_DUST] = 7 }) == nil)
	check("Bags: two items going down is not one clean outcome",
		SalvageLogic.OutcomeBetween(before, { [COPPER_ORE] = 15, [TIGERSEYE] = 2, [MALACHITE] = 1, [STRANGE_DUST] = 7 }) == nil)
	check("Bags: nothing changed is no outcome", SalvageLogic.OutcomeBetween(before, before) == nil)
	local store = newStore()
	SalvageLogic.RecordOutcome(store, "prospect", { input = ORE, inputCount = 10, results = { [MALACHITE] = 3 }, casts = 2 })
	check("Several casts read as one change count as that many casts", SalvageLogic.Yield({ own = store }, "prospect", ORE).casts == 2)
end

-- Where a result comes from
do
	local TIN_ORE = 2771
	local own, shipped = newStore(), newStore("other")
	SalvageLogic.RecordOutcome(own, "prospect", { input = ORE, inputCount = 10, results = { [TIGERSEYE] = 4, [MALACHITE] = 1 }, casts = 2 })
	SalvageLogic.RecordOutcome(own, "prospect", { input = { itemID = TIN_ORE }, inputCount = 5, results = { [TIGERSEYE] = 1 } })
	SalvageLogic.RecordOutcome(shipped, "prospect", { input = ORE, inputCount = 10, results = { [TIGERSEYE] = 2 }, casts = 2 })
	SalvageLogic.RecordOutcome(own, "disenchant", { input = { expansionID = 0, quality = 2, itemLevel = 20 }, inputCount = 1, results = { [TIGERSEYE] = 1 } })
	local sources = SalvageLogic.SourcesOf({ shipped, own }, TIGERSEYE)
	check("Sources: every ore that gave the item, the most giving first, stores added up",
		#sources == 2 and sources[1].inputItemID == COPPER_ORE and sources[1].perInput == 6 / 20 and sources[1].casts == 4
		and sources[2].inputItemID == TIN_ORE and sources[2].perInput == 1 / 5)
	check("Sources: the action and how many one cast takes", sources[1].action == "prospect" and sources[1].inputsPerCast == 5)
	check("Sources: disenchanted gear is no source", #SalvageLogic.SourcesOf({ own }, STRANGE_DUST) == 0)
	check("Sources: an item nothing gave has none", #SalvageLogic.SourcesOf({ own }, 99) == 0)
end

-- Disenchanted gear is read in bands of item level
do
	local store = newStore()
	local function gear(itemLevel, quality, isWeapon)
		return { expansionID = 0, quality = quality or 2, isWeapon = isWeapon, itemLevel = itemLevel }
	end
	local function disenchant(input, dust)
		SalvageLogic.RecordOutcome(store, "disenchant", { input = input, inputCount = 1, results = { [STRANGE_DUST] = dust } })
	end
	disenchant(gear(16), 2)
	disenchant(gear(20), 4)
	disenchant(gear(21), 9)
	local yield = SalvageLogic.Yield({ own = store }, "disenchant", gear(18))
	check("Gear of nearby item level counts together", yield.casts == 2 and yield.perInput[STRANGE_DUST] == 3)
	check("The next band is apart", SalvageLogic.Yield({ own = store }, "disenchant", gear(25)).casts == 1)
	check("Another quality is apart", SalvageLogic.Yield({ own = store }, "disenchant", gear(18, 3)) == nil)
	check("Weapons and armor are apart", SalvageLogic.Yield({ own = store }, "disenchant", gear(18, 2, true)) == nil)
end

-- Whose numbers are trusted
do
	local own, shipped = newStore(), newStore("other")
	local researched = { prospect = { [COPPER_ORE] = { [TIGERSEYE] = 0.1 } } }
	shipped.yields[0] = { [SalvageLogic.YieldKey("prospect", ORE)] = { casts = 100, inputs = 500, items = { [MALACHITE] = 100 } } }
	check("No counted outcomes: researched yields", SalvageLogic.Yield({ own = own, researched = researched }, "prospect", ORE).basis == "researched")
	prospect(own, 3)
	local few = SalvageLogic.Yield({ own = own, researched = researched }, "prospect", ORE)
	check("A few own outcomes do not beat researched yields", few.basis == "researched" and few.casts == 0)
	check("... but are used when nothing else is known", SalvageLogic.Yield({ own = own }, "prospect", ORE).basis == "counted")
	local counted = SalvageLogic.Yield({ own = own, shipped = shipped, researched = researched }, "prospect", ORE)
	check("Enough counted outcomes together beat researched yields, own and shipped added up",
		counted.basis == "counted" and counted.casts == 103 and counted.perInput[MALACHITE] == 100 / 515)
	prospect(own, SalvageLogic.TRUSTED_CASTS - 3)
	local trusted = SalvageLogic.Yield({ own = own, shipped = shipped, researched = researched }, "prospect", ORE)
	check("Enough own outcomes win alone", trusted.basis == "own" and trusted.casts == SalvageLogic.TRUSTED_CASTS
		and trusted.perInput[MALACHITE] == nil and trusted.perInput[TIGERSEYE] == 1 / 5)
end

-- Researched disenchant rows cover a range of item levels
do
	local dust, shard = { [STRANGE_DUST] = 1.2 }, { [10978] = 1 } -- plain averages, as prospecting rows hold
	local researched = { disenchant = {
		{ expansionID = 0, quality = 2, isWeapon = false, fromLevel = 5, toLevel = 15, yield = dust },
		{ expansionID = 0, quality = 3, fromLevel = 1, toLevel = 25, yield = shard },
	} }
	local function yieldOf(input)
		return SalvageLogic.ResearchedYield(researched, "disenchant", input)
	end
	check("Row: gear inside the range", yieldOf({ expansionID = 0, quality = 2, itemLevel = 15 })[STRANGE_DUST] == 1.2)
	check("Row: outside the range, another quality, a weapon, another expansion: none",
		yieldOf({ expansionID = 0, quality = 2, itemLevel = 16 }) == nil and yieldOf({ expansionID = 0, quality = 4, itemLevel = 10 }) == nil
		and yieldOf({ expansionID = 0, quality = 2, itemLevel = 10, isWeapon = true }) == nil
		and yieldOf({ expansionID = 1, quality = 2, itemLevel = 10 }) == nil)
	check("Row without weapon or armor covers both", yieldOf({ expansionID = 0, quality = 3, itemLevel = 20, isWeapon = true })[10978] == 1
		and yieldOf({ expansionID = 0, quality = 3, itemLevel = 20 })[10978] == 1)
	local _, noChances = yieldOf({ expansionID = 0, quality = 3, itemLevel = 20 })
	check("Rows of plain averages have no chances", noChances == nil)
	check("No table for the action: none", SalvageLogic.ResearchedYield(researched, "mill", { itemID = 1 }) == nil)
end

-- The shipped researched tables
do
	local data = {}
	local chunk, err = loadfile(root .. "/src/data/Tradewright_SalvageData.lua")
	assert(chunk, err)
	chunk("Tradewright", data)
	local forever = data.SALVAGE_DATA.forever
	local function gear(quality, itemLevel, isWeapon)
		return SalvageLogic.ResearchedYield(forever, "disenchant", { expansionID = 0, quality = quality, itemLevel = itemLevel, isWeapon = isWeapon })
	end
	check("Shipped: a classic green armor piece gives mostly dust", gear(2, 18)[STRANGE_DUST] == 1.875)
	check("Shipped: a classic green weapon gives mostly essence", gear(2, 18, true)[10939] == 1.125)
	check("Shipped: classic rare and epic gear", gear(3, 60, true)[14344] == 0.995 and gear(4, 60)[20725] == 1)
	check("Shipped: no prospecting table, as WoW Forever has no Jewelcrafting", SalvageLogic.ResearchedYield(forever, "prospect", ORE) == nil)
	local covered = true
	for quality = 2, 3 do
		for itemLevel = 5, 65 do
			covered = covered and gear(quality, itemLevel) ~= nil and gear(quality, itemLevel, true) ~= nil
		end
	end
	check("Shipped: every classic item level of green and rare gear has a row", covered)
	check("Shipped: a retail table exists, even when empty", type(data.SALVAGE_DATA.retail) == "table")
	local perInput, chances = gear(2, 29)
	check("Shipped: chance and count per material, the average following from them",
		chances[11083].chance == 0.75 and chances[11083].min == 1 and chances[11083].max == 2 and perInput[11083] == 1.125)
	local consistent = true
	for _, row in ipairs(forever.disenchant) do
		local total = 0
		for _, material in pairs(row.yield) do
			consistent = consistent and material.min <= material.max and material.chance > 0
			total = total + material.chance
		end
		consistent = consistent and math.abs(total - 1) < 1e-9
	end
	check("Shipped: every row's chances add up to one disenchant", consistent)
end

-- Chances from the player's own disenchants
do
	local store = { epoch = 1, yields = {} }
	local gearInput = { expansionID = 0, quality = 2, isWeapon = false, itemLevel = 29 }
	for cast = 1, 4 do
		local results = cast == 4 and { [11082] = 1 } or { [11083] = 2 }
		SalvageLogic.RecordOutcome(store, "disenchant", { input = gearInput, inputCount = 1, results = results })
	end
	SalvageLogic.RecordOutcome(store, "disenchant", { input = gearInput, inputCount = 2, casts = 2, results = { [11083] = 3 } })
	local yield = SalvageLogic.Yield({ own = store }, "disenchant", gearInput)
	check("Only casts recorded one at a time give chances", yield.chances[11083].chance == 0.75 and yield.chances[11082].chance == 0.25)
	check("The count when it drops follows from the average", math.abs(yield.chances[11083].each - (9 / 6) / 0.75) < 1e-9)
	check("Own casts are counted even under researched yields", yield.ownCasts == 6)
	local old = { epoch = 1, yields = { { [SalvageLogic.YieldKey("disenchant", gearInput)] = { casts = 3, inputs = 3, items = { [11083] = 4 } } } } }
	local fromOld = SalvageLogic.Yield({ own = old }, "disenchant", gearInput)
	check("Records saved before chances give averages only", fromOld.chances == nil and fromOld.perInput[11083] == 4 / 3)
end

-- Value
do
	local yield = { perInput = { [TIGERSEYE] = 0.2, [MALACHITE] = 0.5, [STRANGE_DUST] = 1 } }
	local prices = { [TIGERSEYE] = 100, [MALACHITE] = 40 }
	local value, unvalued = SalvageLogic.Value(yield, function(itemID) return prices[itemID] end)
	check("Value: each item at its rate, items without a value counted apart", value == 40 and unvalued == 1)
end

-- Shipping with the sightings store
do
	local store = newStore("me")
	prospect(store, 2)
	check("Seal closes an epoch that holds only yields", SourceLogic.Seal(store) == 1 and store.epoch == 2)
	prospect(store, 1)
	local shipped = SourceLogic.ShipStore(nil, store)
	local key = SalvageLogic.YieldKey("prospect", ORE)
	check("Closed epochs ship, the open one does not", shipped.yields[0][key].casts == 2 and shipped.yields[0][key].inputs == 10
		and shipped.yields[0][key].items[TIGERSEYE] == 2)
	SourceLogic.ShipStore(shipped, store)
	check("Shipping the same store again adds nothing", shipped.yields[0][key].casts == 2)
	SourceLogic.Prune(store, shipped)
	check("Shipped epochs leave the saved store, the open one stays", store.yields[1] == nil and store.yields[2][key].casts == 1)
	check("Together they still give every outcome", SalvageLogic.Yield({ own = store, shipped = shipped }, "prospect", ORE).casts == 3)
end

-- The best use of one item
do
	local use, gain = SalvageLogic.BestUse({ vendor = 10, auction = 50, salvage = 80 })
	check("Disenchanting wins when it gets the most, by the gap to the next best", use == "salvage" and gain == 30)
	use, gain = SalvageLogic.BestUse({ vendor = 90, auction = 50, salvage = 80 })
	check("A vendor price can win", use == "vendor" and gain == 10)
	use, gain = SalvageLogic.BestUse({ vendor = 10, salvage = 40 })
	check("A bound item compares vendor and disenchant only", use == "salvage" and gain == 30)
	use, gain = SalvageLogic.BestUse({ salvage = 40 })
	check("A single open use gains all of its value", use == "salvage" and gain == 40)
	use, gain = SalvageLogic.BestUse({ vendor = 40, salvage = 40 })
	check("A tie goes to the least work", use == "vendor" and gain == 0)
	check("No use open: nil", SalvageLogic.BestUse({}) == nil)
end

-- Auctions below their disenchant value
do
	-- Worth 100 each; with a 20% margin the limit is 80.
	local rows = SalvageLogic.BuyBelowValue({
		{ itemID = 1, price = 50, value = 100, steps = { 50, 2, 70, 1, 80, 5, 90, 3 } },
		{ itemID = 2, price = 80, value = 100 },
		{ itemID = 3, price = 79, value = 100 },
		{ itemID = 4, price = 30, value = 100, basis = "researched" },
	}, 0.2)
	check("Only buyouts below the value less the margin pass; the limit itself does not", #rows == 3, #rows)
	local first = rows[1]
	check("Units listed below the limit are counted from the price steps", first.itemID == 1 and first.quantity == 3 and first.cost == 170)
	check("Gain is their value less their cost, and its share of the cost",
		first.gain == 130 and math.abs(first.gainShare - 130 / 170) < 1e-9 and first.limit == 80)
	check("Without price steps only the cheapest unit counts", rows[2].itemID == 4 and rows[2].quantity == 1 and rows[2].gain == 70)
	check("The item's own fields are kept", rows[2].basis == "researched")
	check("Most gain first", rows[3].itemID == 3 and rows[3].gain == 21)
	check("Price steps that disagree with the buyout give no row",
		#SalvageLogic.BuyBelowValue({ { itemID = 5, price = 50, value = 100, steps = { 95, 1 } } }, 0.2) == 0)
end

if failed > 0 then
	os.exit(1)
end
