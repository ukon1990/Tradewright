-- Run with: lua5.1 tests/test_leveling_route_logic.lua (from Tradewright root)
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
for _, file in ipairs({ "Tradewright_SkillUpLogic.lua", "Tradewright_LevelingRouteLogic.lua" }) do
	local chunk, err = loadfile(root .. "/src/util/" .. file)
	assert(chunk, err)
	chunk("Tradewright", pe)
end
local RL = pe.LevelingRouteLogic
assert(RL, "LevelingRouteLogic missing")

-- A learned recipe that is orange up to `yellowStart` and grey at `greyStart`.
local function recipe(name, yellowStart, greyStart, materialCost)
	return {
		recipeID = name, name = name, learned = true, materialCost = materialCost,
		bounds = { yellowStart = yellowStart, greenStart = math.ceil((yellowStart + greyStart) / 2), greyStart = greyStart },
	}
end

local function route(candidates, options)
	options = options or {}
	return RL.BuildRoute({
		fromSkill = options.fromSkill or 100, rankCap = options.rankCap, giveBackMode = options.giveBackMode or "none",
		recipeScope = options.recipeScope, maxSkill = options.maxSkill, candidates = candidates,
	})
end

local function stepNames(built)
	local names = {}
	for _, step in ipairs(built.steps) do
		names[#names + 1] = step.kind == "rankCap" and "cap" or (step.name .. " " .. step.fromSkill .. "-" .. step.toSkill)
	end
	return table.concat(names, ", ")
end

-- Cheapest per point, merged into steps
do
	local built = route({ recipe("Cheap", 110, 120, 100), recipe("Dear", 130, 140, 300) })
	check("Cheaper orange recipe is used first, then the other takes over",
		stepNames(built) == "Cheap 100-117, Dear 117-140", stepNames(built))
	check("Route ends where nothing gives skill", built.toSkill == 140 and built.fromSkill == 100)
	local first = built.steps[1]
	check("Orange points take one craft each; yellow points more",
		first.crafts == 21, first.crafts)
	check("Step cost is crafts times cost per craft", first.materials == first.crafts * 100 and first.net == first.materials)
	check("Totals add up", built.totals.materials == built.steps[1].materials + built.steps[2].materials
		and built.totals.net == built.totals.materials and built.totals.giveBack == 0)
end

-- A yellow recipe loses when its cost per point is higher
do
	local built = route({ recipe("Yellow", 100, 104, 100), recipe("Orange", 150, 160, 150) }, { fromSkill = 102 })
	check("Dearer orange recipe beats a cheap one at half chance", built.steps[1].name == "Orange", stepNames(built))
end

-- What crafted items give back
do
	local sells = recipe("Sells", 150, 160, 300)
	sells.vendorGiveBack, sells.auctionGiveBack = 250, 290
	local plain = recipe("Plain", 150, 160, 100)
	check("Counted as nothing: cheaper materials win", route({ sells, plain }).steps[1].name == "Plain")
	local vendor = route({ sells, plain }, { giveBackMode = "vendor" })
	check("Sold to vendor: lower net cost wins", vendor.steps[1].name == "Sells")
	-- 50 orange points and 10 yellow ones come to 80 crafts.
	check("Materials and net are both reported", vendor.totals.materials == 80 * 300 and vendor.totals.net == 80 * 50
		and vendor.totals.giveBack == 80 * 250)
	check("Sold at auction uses the auction value", route({ sells, plain }, { giveBackMode = "auction" }).totals.net == 80 * 10)
	plain.vendorGiveBack = 95
	check("Auction mode falls back to the vendor value", RL.GiveBack(plain, "auction") == 95 and RL.GiveBack(plain, "none") == 0)
	check("Disenchant mode falls back to the vendor value for items that cannot be disenchanted",
		RL.GiveBack(plain, "disenchant") == 95)
end

-- Counting crafted gear at its disenchant value
do
	local gear = recipe("Gear", 150, 160, 300)
	gear.vendorGiveBack, gear.disenchantGiveBack = 50, 280
	local pouch = recipe("Pouch", 150, 160, 200)
	pouch.vendorGiveBack = 60
	check("Sold to vendor: the cheaper pouch wins", route({ gear, pouch }, { giveBackMode = "vendor" }).steps[1].name == "Pouch")
	local disenchanted = route({ gear, pouch }, { giveBackMode = "disenchant" })
	check("Disenchanted: the gear's value makes it the cheaper route", disenchanted.steps[1].name == "Gear")
	check("Disenchanted: give-back is the disenchant value", disenchanted.totals.giveBack == 80 * 280
		and disenchanted.totals.net == 80 * 20)
end

-- Recipes not learned
do
	local known, unknown = recipe("Known", 150, 160, 200), recipe("Unknown", 150, 160, 100)
	unknown.learned = false
	check("A recipe not learned may be used", route({ known, unknown }).steps[1].name == "Unknown")
	check("... and is marked", route({ known, unknown }).steps[1].learned == false)
	check("Only known leaves it out", route({ known, unknown }, { recipeScope = "known" }).steps[1].name == "Known")
	check("Trainer recipes first: a known recipe wins over a cheaper one of unknown source",
		route({ known, unknown }, { recipeScope = "trainer" }).steps[1].name == "Known")
	unknown.source = "trainer"
	check("Trainer recipes first: a cheaper trainer recipe is used", route({ known, unknown }, { recipeScope = "trainer" }).steps[1].name == "Unknown")
	unknown.source = nil
	local short, gapFiller = recipe("Short", 110, 120, 200), recipe("GapFiller", 150, 160, 100)
	gapFiller.learned = false
	check("Trainer recipes first: another recipe only fills the points nothing within reach gives",
		stepNames(route({ short, gapFiller }, { recipeScope = "trainer" })) == "Short 100-120, GapFiller 120-160",
		stepNames(route({ short, gapFiller }, { recipeScope = "trainer" })))
	check("All recipes: the cheaper one wins from the start", route({ short, gapFiller }).steps[1].name == "GapFiller")
	local unpricedDrop = recipe("Drop", 150, 160, nil)
	unpricedDrop.learned = false
	check("A recipe outside the choice is not counted as missing a price", route({ known, unpricedDrop }, { recipeScope = "known" }).skippedForPrice == 0)

	unknown.learnSkill = 120
	check("It is not used below the skill needed to learn it",
		stepNames(route({ known, unknown })) == "Known 100-120, Unknown 120-160", stepNames(route({ known, unknown })))

	unknown.learnSkill, unknown.learnCost = nil, 5000
	local worthIt = route({ known, unknown })
	check("Learn price below the saving: used, and counted once", worthIt.steps[1].name == "Unknown"
		and worthIt.totals.learnCost == 5000 and worthIt.totals.net == 80 * 100 + 5000)
	unknown.learnCost = 9000
	check("Learn price above the saving: not used", route({ known, unknown }).steps[1].name == "Known")
	check("Learn price is paid when nothing else gives the points", route({ unknown }).steps[1].name == "Unknown")
end

-- Rank cap
do
	local long = recipe("Long", 190, 200, 100)
	check("Cap splits the route", stepNames(route({ long }, { rankCap = 150 })) == "Long 100-150, cap, Long 150-200",
		stepNames(route({ long }, { rankCap = 150 })))
	check("Cap at the current skill comes first", stepNames(route({ long }, { rankCap = 100 })) == "cap, Long 100-200")
	check("No cap step when the route ends below it", stepNames(route({ recipe("Short", 110, 120, 100) }, { rankCap = 150 })) == "Short 100-120")
end

-- Highest skill of the profession
do
	local long = recipe("Long", 390, 400, 100)
	local capped = route({ long }, { maxSkill = 300, rankCap = 150 })
	check("Route stops at the profession's highest skill", capped.toSkill == 300 and stepNames(capped) == "Long 100-150, cap, Long 150-300", stepNames(capped))
	check("Already at the highest skill: empty route", #route({ long }, { fromSkill = 300, maxSkill = 300 }).steps == 0)
	check("No rank step when the rank cap is the highest skill", stepNames(route({ long }, { maxSkill = 150, rankCap = 150 })) == "Long 100-150")
end

-- Missing prices
do
	local unpriced = recipe("Unpriced", 150, 160, nil)
	local built = route({ unpriced, recipe("Priced", 110, 120, 100) })
	check("A recipe without a material price is left out and counted", built.skippedForPrice == 1 and #built.steps == 1)
	check("Nothing usable gives an empty route", #route({ unpriced }).steps == 0 and route({}).toSkill == 100)
end

-- Skill points per craft
do
	local double = recipe("Double", 150, 160, 100)
	double.skillUpsPerCraft = 2
	check("Two points per craft halves the crafts", route({ double }).steps[1].crafts == 40, route({ double }).steps[1].crafts)
end

-- A recipe that makes a material for a later step
do
	local LEATHER = 4304
	local function leatherRecipe()
		local makesLeather = recipe("Heavy Leather", 110, 120, 100)
		makesLeather.outputItemID, makesLeather.outputQuantity, makesLeather.vendorGiveBack = LEATHER, 1, 10
		return makesLeather
	end
	local function cloak()
		local usesLeather = recipe("Cloak", 150, 160, 500)
		usesLeather.reagents = { { itemID = LEATHER, quantity = 2, unitPrice = 90 } }
		return usesLeather
	end
	local other = recipe("Other", 110, 120, 60)
	other.vendorGiveBack = 10

	local withoutUse = route({ leatherRecipe(), other }, { giveBackMode = "vendor" })
	check("Nothing uses the material: the cheaper recipe wins", withoutUse.steps[1].name == "Other")

	local built = route({ leatherRecipe(), other, cloak() }, { giveBackMode = "vendor" })
	local first = built.steps[1]
	check("A later step uses the material: the recipe that makes it wins", first.name == "Heavy Leather", stepNames(built))
	check("Every crafted piece is used later and counts for the material price",
		first.reusedQuantity == first.crafts and first.reuseValue == first.crafts * 90 and first.giveBack == first.crafts * 90)
	check("The later step still shows its full material cost", built.steps[2].materials == built.steps[2].crafts * 500)
	check("Totals count the saving once", built.totals.net == built.totals.materials - built.totals.giveBack)

	local thirsty = cloak()
	thirsty.reagents[1].quantity = 0.1
	local surplus = route({ leatherRecipe(), other, thirsty }, { giveBackMode = "vendor" }).steps[1]
	local used = surplus.reusedQuantity
	check("More crafted than later steps use: the rest counts at its vendor price",
		used < surplus.crafts and surplus.giveBack == used * 90 + (surplus.crafts - used) * 10, surplus.giveBack)

	local early, late = cloak(), leatherRecipe()
	early.bounds, late.bounds = { yellowStart = 110, greenStart = 115, greyStart = 120 }, { yellowStart = 150, greenStart = 155, greyStart = 160 }
	local wrongOrder = route({ early, late }, { giveBackMode = "vendor" })
	check("A material crafted after the step that needs it saves nothing",
		wrongOrder.steps[#wrongOrder.steps].name == "Heavy Leather" and wrongOrder.steps[#wrongOrder.steps].reusedQuantity == 0)
end

-- Craft queue
do
	local built = route({ recipe("Cheap", 110, 120, 100), recipe("Dear", 130, 140, 300) })
	local entry = RL.QueueEntry(built.steps[1])
	check("A learned step gives a queue entry", entry and entry.recipeID == "Cheap" and entry.quantity == built.steps[1].crafts)
	check("A cap step gives none", RL.QueueEntry({ kind = "rankCap", skill = 150 }) == nil)
	local unknown = recipe("Unknown", 150, 160, 100)
	unknown.learned = false
	check("A step not learned gives none", RL.QueueEntry(route({ unknown }).steps[1]) == nil)

	local needed = built.steps[1].crafts
	check("Queued more than needed: trim", RL.QueueAdjustment(needed + 3, "Cheap", built.steps) == -3)
	check("Queued fewer than needed: top up", RL.QueueAdjustment(needed - 2, "Cheap", built.steps) == 2)
	check("Recipe no longer in the route: remove all", RL.QueueAdjustment(5, "Gone", built.steps) == -5)

	-- Cheap gives 100-117 (21 crafts), Dear 117-140.
	check("Up to a skill inside a step: only the crafts for those points", RL.CraftsUpTo(built.steps[1], 110) == 10)
	check("Up to a skill past a step: the whole step", RL.CraftsUpTo(built.steps[1], 130) == built.steps[1].crafts)
	check("A step that starts at or after the skill: nothing", RL.CraftsUpTo(built.steps[2], 117) == 0)
	local range = RL.QueueEntriesUpTo(built.steps, 120)
	check("Range: both recipes in route order", #range == 2 and range[1].recipeID == "Cheap" and range[2].recipeID == "Dear")
	check("Range: the last recipe only as far as the skill", range[1].quantity == 21 and range[2].quantity == 3)

	local long = recipe("Long", 190, 200, 100)
	long.learned = false
	local capped = route({ long }, { rankCap = 150 })
	local acrossCap = RL.QueueEntriesUpTo(capped.steps, 170)
	check("Range: a recipe split by the rank cap is one entry, not learned ones included",
		#acrossCap == 1 and acrossCap[1].quantity == 70 and acrossCap[1].step == capped.steps[1])
	-- 50 crafts to the cap and 70 after it.
	check("A queued recipe that is not learned is not trimmed away", RL.QueueAdjustment(70, "Long", capped.steps) == 50)
end

-- Trainer data
do
	local known, unknown = recipe("Known", 150, 160, 200), recipe("Unknown", 150, 160, 100)
	unknown.learned = false
	RL.ApplyTrainerData({ known, unknown }, { Unknown = { skillRequired = 125, cost = 500 }, Known = { skillRequired = 10, cost = 5 } })
	check("Trainer data fills a recipe not learned", unknown.learnSkill == 125 and unknown.learnCost == 500 and unknown.source == "trainer")
	check("... and leaves a learned one alone", known.learnSkill == nil and known.source == nil)
end

-- Recipe items seen at vendors and in loot
do
	local taught, sold, dropped = recipe("Taught", 150, 160, 100), recipe("Sold", 150, 160, 100), recipe("Dropped", 150, 160, 100)
	local unseen, known = recipe("Unseen", 150, 160, 100), recipe("Known", 150, 160, 100)
	taught.learned, sold.learned, dropped.learned, unseen.learned = false, false, false, false
	taught.source, sold.learnSkill = "trainer", 110
	local sources = {
		Taught = { sellers = { Una = { price = 1 } } },
		Sold = { sellers = { Una = { price = 700 }, Karolek = { price = 550 }, Wik = {} }, drops = { { name = "Kodo" } } },
		Dropped = { sellers = {}, drops = { { name = "Bristleback Shaman", share = 0.02 }, { name = "Kodo", share = 0.01 } } },
		Known = { sellers = { Una = { price = 1 } } },
	}
	RL.ApplyRecipeSources({ taught, sold, dropped, unseen, known }, function(recipeName) return sources[recipeName] end)
	check("Sources: a vendor recipe costs the cheapest price and keeps its skill estimate",
		sold.source == "vendor" and sold.learnCost == 550 and sold.learnSkill == 110 and sold.vendors.Una.price == 700)
	check("Sources: a recipe only seen in loot names its likeliest source", dropped.source == "drop" and dropped.dropSource.name == "Bristleback Shaman")
	check("Sources: a trainer recipe stays a trainer recipe", taught.source == "trainer" and taught.vendors == nil)
	check("Sources: nothing seen, nothing set", unseen.source == nil and known.source == nil)
	check("Reach: a vendor recipe is within reach, a dropped one is not", RL.IsWithinReach(sold) and not RL.IsWithinReach(dropped))
end

-- What is remembered from a trainer
do
	local orgrimmar = { zone = "Orgrimmar", mapID = 85, x = 0.6, y = 0.5 }
	local entries, ranks = RL.TrainerEntries({
		{ name = "Heavy Armor Kit", cost = 500, skillRequired = 150 },
		{ name = "Expert Leatherworker", cost = 5000, skillRequired = 125 },
		{ name = "Frostbolt", cost = 100 },
	}, { ["Heavy Armor Kit"] = "165" }, 1000)
	local kit = entries["165"] and entries["165"]["Heavy Armor Kit"]
	check("Trainer: a scanned recipe is kept with cost, skill and time", kit and kit.cost == 500 and kit.skillRequired == 150 and kit.seenAt == 1000)
	check("Trainer: ranks and other spells are skipped", entries["165"]["Expert Leatherworker"] == nil and next(entries, "165") == nil)
	check("Trainer: nothing listed, nothing kept", next((RL.TrainerEntries({}, {}, 1))) == nil)
	local expert = ranks["165"] and ranks["165"]["Expert Leatherworker"]
	check("Trainer: its other services are kept as rank training of that profession",
		expert and expert.skillRequired == 125 and expert.cost == 5000)
	local _, classRanks = RL.TrainerEntries({ { name = "Frostbolt", cost = 100 } }, { ["Heavy Armor Kit"] = "165" }, 1)
	check("Trainer: a window without this character's recipes gives no rank training", next(classRanks) == nil)
	local _, twoProfessions = RL.TrainerEntries({ { name = "A" }, { name = "B" }, { name = "Rank" } }, { A = "165", B = "197" }, 1)
	check("Trainer: recipes of two professions leave the other services unassigned", next(twoProfessions) == nil)

	local seen = {
		["Journeyman Leatherworker"] = { skillRequired = 50, cost = 500 },
		["Expert Leatherworker"] = { skillRequired = 125, cost = 5000, trainers = { Karolek = orgrimmar } },
	}
	local next150 = RL.NextRankTraining(seen, 150)
	check("Next rank: the training asked for just below the cap", next150 and next150.name == "Expert Leatherworker"
		and next150.skillRequired == 125 and next150.trainers.Karolek == orgrimmar)
	check("Next rank: a lower rank's training does not lift a higher cap", RL.NextRankTraining(seen, 225) == nil)
	seen["Artisan Leatherworker"] = { skillRequired = 200, cost = 50000 }
	check("Next rank: Artisan once a trainer was seen offering it", RL.NextRankTraining(seen, 225).name == "Artisan Leatherworker")
	check("Next rank: nothing seen", RL.NextRankTraining(nil, 150) == nil)

	local thunderBluff = { zone = "Thunder Bluff", mapID = 88, x = 0.4, y = 0.4 }
	local seenAtTrainer = { skillRequired = 150, cost = 450, seenAt = 2000, trainers = { Una = thunderBluff } }

	local unknown = recipe("Heavy Armor Kit", 150, 160, 100)
	unknown.learned = false
	RL.ApplyTrainerData({ unknown }, { ["Heavy Armor Kit"] = seenAtTrainer })
	check("Trainers reach the recipe in the route", unknown.trainers.Una == thunderBluff)
end

if failed > 0 then
	os.exit(1)
end
