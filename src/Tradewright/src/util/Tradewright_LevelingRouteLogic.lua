local _, Tradewright = ...

--- Pure helpers for the profession leveling route: which recipe to craft over which skill range, about
--- how many times, and what it costs. No WoW API. Needs `SkillUpLogic` loaded first.
---
--- A candidate is one priced recipe:
--- `{ recipeID, name, bounds, learned, learnSkill, learnCost, materialCost, vendorGiveBack,
---    auctionGiveBack, skillUpsPerCraft, outputItemID, outputQuantity, reagents }`, costs in copper for
--- one craft. `bounds` comes from `SkillUpLogic.DifficultyBounds`. `learnSkill` and `learnCost` only
--- matter for a recipe not learned. `reagents = { { itemID, quantity, unitPrice } }` per craft.
---
--- A recipe that makes a material for another recipe (Heavy Leather from Medium Leather) gives skill
--- and saves buying that material later. Its output then counts for what the material would cost,
--- see `reuseValues` and `creditReusedOutput`.
---
--- Each skill point is won on its own, so the cheapest route is the cheapest recipe at every point.
--- The one thing that spans points is the price of learning a recipe, handled by `dropCostlyLearns`.
local LevelingRouteLogic = {}
Tradewright.LevelingRouteLogic = LevelingRouteLogic

local SkillUpLogic = Tradewright.SkillUpLogic

-- Expected crafts are fractions; this keeps 6.0000001 from rounding up to 7.
local ROUNDING_SLACK = 1e-6

--- What one craft gives back, by the player's choice of `giveBackMode`: "vendor", "auction" or "none".
--- An item without an auction price counts for its vendor price in "auction" mode.
function LevelingRouteLogic.GiveBack(candidate, giveBackMode)
	if giveBackMode == "vendor" then
		return candidate.vendorGiveBack or 0
	elseif giveBackMode == "auction" then
		return candidate.auctionGiveBack or candidate.vendorGiveBack or 0
	end
	return 0
end

-- Expected crafts for one skill point at `skill`, or nil when the recipe cannot give one there.
local function craftsPerPoint(candidate, skill)
	local chance = SkillUpLogic.SkillUpChance(candidate.bounds, skill)
	if chance <= 0 then
		return nil
	end
	return 1 / (chance * math.max(1, candidate.skillUpsPerCraft or 1))
end

local function usableAt(candidate, skill, excluded)
	if excluded[candidate] then
		return false
	end
	return candidate.learned or not candidate.learnSkill or skill >= candidate.learnSkill
end

--- Whether the player can count on having the recipe: it is known, or a trainer has been seen to
--- teach it. Any other recipe may be a rare drop.
function LevelingRouteLogic.IsWithinReach(candidate)
	return candidate.learned == true or candidate.source == "trainer"
end

-- What the point at `skill` costs with this candidate, or nil when it cannot give that point.
local function pointCost(search, candidate, skill)
	local crafts = usableAt(candidate, skill, search.excluded) and craftsPerPoint(candidate, skill)
	if not crafts then
		return nil
	end
	local sold = LevelingRouteLogic.GiveBack(candidate, search.giveBackMode)
	local reused = search.reuseValue and search.reuseValue[candidate] or 0
	return crafts * (candidate.materialCost - math.max(sold, reused))
end

local function keepCheaper(cheapest, candidate, cost)
	if not cheapest.cost or cost < cheapest.cost then
		cheapest.candidate, cheapest.cost = candidate, cost
	end
end

-- The candidate for the point at `skill`: `candidate, costForThePoint`. The cheapest one; with
-- `search.withinReachFirst`, the cheapest recipe within reach, and another only when none of those
-- can give the point.
local function cheapestAt(search, skill)
	local withinReach, others = {}, {}
	for _, candidate in ipairs(search.candidates) do
		local cost = pointCost(search, candidate, skill)
		if cost then
			local preferred = not search.withinReachFirst or LevelingRouteLogic.IsWithinReach(candidate)
			keepCheaper(preferred and withinReach or others, candidate, cost)
		end
	end
	if withinReach.candidate then
		return withinReach.candidate, withinReach.cost
	end
	return others.candidate, others.cost
end

-- One pick per skill point from `fromSkill` until no recipe can give the next point, or the
-- profession's highest skill is reached. Recipes often stay orange past that skill.
local function pickPerPoint(search, fromSkill)
	local picks = {}
	local skill = fromSkill
	while not search.maxSkill or skill < search.maxSkill do
		local candidate, cost = cheapestAt(search, skill)
		if not candidate then
			break
		end
		picks[#picks + 1] = { skill = skill, candidate = candidate, cost = cost }
		skill = skill + 1
	end
	return picks
end

-- How much cheaper the route is with `candidate` than without it, over the points it won.
-- nil when a point has no other recipe: the route would end without it, so it stays.
local function savingFrom(search, picks, candidate)
	local saving = 0
	search.excluded[candidate] = true
	for _, pick in ipairs(picks) do
		if pick.candidate == candidate then
			local _, otherCost = cheapestAt(search, pick.skill)
			if not otherCost then
				saving = nil
				break
			end
			saving = saving + (otherCost - pick.cost)
		end
	end
	search.excluded[candidate] = nil
	return saving
end

-- A picked recipe whose price to learn is more than it saves, or nil.
local function costlyLearn(search, picks)
	local checked = {}
	for _, pick in ipairs(picks) do
		local candidate = pick.candidate
		if not checked[candidate] and not candidate.learned and (candidate.learnCost or 0) > 0 then
			checked[candidate] = true
			local saving = savingFrom(search, picks, candidate)
			if saving and saving < candidate.learnCost then
				return candidate
			end
		end
	end
	return nil
end

-- Picks again without each recipe that costs more to learn than it saves.
local function dropCostlyLearns(search, fromSkill)
	local picks = pickPerPoint(search, fromSkill)
	local costly = costlyLearn(search, picks)
	while costly do
		search.excluded[costly] = true
		picks = pickPerPoint(search, fromSkill)
		costly = costlyLearn(search, picks)
	end
	return picks
end

-- What one craft of a recipe is worth when its item is a material of a recipe in `picks`: the price
-- the route would pay for that material. `{ [candidate] = copper per craft }`.
local function reuseValues(candidates, picks)
	local materialPrice = {}
	for _, pick in ipairs(picks) do
		for _, reagent in ipairs(pick.candidate.reagents or {}) do
			materialPrice[reagent.itemID] = reagent.unitPrice
		end
	end
	local values = {}
	for _, candidate in ipairs(candidates) do
		local price = candidate.outputItemID and materialPrice[candidate.outputItemID]
		if price then
			values[candidate] = price * (candidate.outputQuantity or 1)
		end
	end
	return values
end

-- Picks once, then again with crafted materials counted for what they save. The second pass is what
-- lets a material recipe win a step it would lose on its vendor price alone. It values every craft
-- of such a recipe as reused; `creditReusedOutput` then counts only what later steps really use.
local function pickWithReuse(search, fromSkill)
	local picks = dropCostlyLearns(search, fromSkill)
	local values = reuseValues(search.candidates, picks)
	if not next(values) then
		return picks
	end
	search.reuseValue, search.excluded = values, {}
	return dropCostlyLearns(search, fromSkill)
end

-- What a step still needs of each material: `{ [itemID] = { quantity, unitPrice } }`.
local function materialNeeds(step)
	local needs = {}
	for _, reagent in ipairs(step.candidate.reagents or {}) do
		needs[reagent.itemID] = { quantity = step.crafts * (reagent.quantity or 1), unitPrice = reagent.unitPrice or 0 }
	end
	return needs
end

-- Hands up to `available` of the producer's item to a later step that uses it. Returns the amount taken.
local function reuseInStep(producer, consumer, available)
	if consumer.kind ~= "craft" or available <= 0 then
		return 0
	end
	consumer.unmetMaterials = consumer.unmetMaterials or materialNeeds(consumer)
	local need = consumer.unmetMaterials[producer.candidate.outputItemID]
	if not need then
		return 0
	end
	local taken = math.min(available, need.quantity)
	need.quantity = need.quantity - taken
	producer.reusedQuantity = producer.reusedQuantity + taken
	producer.reuseValue = producer.reuseValue + taken * need.unitPrice
	return taken
end

-- The step's give-back with its reused items counted for what they save and the rest sold as usual.
local function settleReuse(producer, giveBackMode)
	local perCraft = producer.candidate.outputQuantity or 1
	local soldPerItem = LevelingRouteLogic.GiveBack(producer.candidate, giveBackMode) / perCraft
	local leftOver = producer.crafts * perCraft - producer.reusedQuantity
	producer.giveBack = math.max(producer.giveBack, producer.reuseValue + leftOver * soldPerItem)
	producer.net = producer.materials - producer.giveBack
end

-- Items a step makes that later steps use as a material count for the price of that material.
-- Only later steps: what is crafted after it was needed saves nothing.
local function creditReusedOutput(steps, giveBackMode)
	for index, producer in ipairs(steps) do
		if producer.kind == "craft" and producer.candidate.outputItemID then
			producer.reusedQuantity, producer.reuseValue = 0, 0
			local available = producer.crafts * (producer.candidate.outputQuantity or 1)
			for later = index + 1, #steps do
				available = available - reuseInStep(producer, steps[later], available)
			end
			if producer.reusedQuantity > 0 then
				settleReuse(producer, giveBackMode)
			end
		end
	end
end

local function newCraftStep(pick)
	local candidate = pick.candidate
	return {
		kind = "craft", recipeID = candidate.recipeID, name = candidate.name, candidate = candidate,
		fromSkill = pick.skill, toSkill = pick.skill, expectedCrafts = 0,
		learned = candidate.learned == true, learnCost = (not candidate.learned) and candidate.learnCost or nil,
		estimated = candidate.bounds.estimated == true,
	}
end

-- Whole crafts and costs for a step whose points have all been added.
local function closeCraftStep(step, giveBackMode)
	step.crafts = math.ceil(step.expectedCrafts - ROUNDING_SLACK)
	step.materials = step.crafts * step.candidate.materialCost
	step.giveBack = step.crafts * LevelingRouteLogic.GiveBack(step.candidate, giveBackMode)
	step.net = step.materials - step.giveBack
end

-- Consecutive points on one recipe become one step; a rank-cap step goes where the route crosses the cap.
local function stepsFromPicks(picks, request)
	local steps, current = {}, nil
	for _, pick in ipairs(picks) do
		local atRankCap = request.rankCap and pick.skill == request.rankCap
		if atRankCap then
			steps[#steps + 1] = { kind = "rankCap", skill = request.rankCap }
		end
		if atRankCap or not current or current.candidate ~= pick.candidate then
			current = newCraftStep(pick)
			steps[#steps + 1] = current
		end
		current.expectedCrafts = current.expectedCrafts + craftsPerPoint(pick.candidate, pick.skill)
		current.toSkill = pick.skill + 1
	end
	for _, step in ipairs(steps) do
		if step.kind == "craft" then
			closeCraftStep(step, request.giveBackMode)
		end
	end
	creditReusedOutput(steps, request.giveBackMode)
	return steps
end

-- Each recipe's price to learn counts once, however many steps use it.
local function routeTotals(steps)
	local totals, learnPaid = { materials = 0, giveBack = 0, learnCost = 0 }, {}
	for _, step in ipairs(steps) do
		if step.kind == "craft" then
			totals.materials = totals.materials + step.materials
			totals.giveBack = totals.giveBack + step.giveBack
			if step.learnCost and not learnPaid[step.candidate] then
				learnPaid[step.candidate] = true
				totals.learnCost = totals.learnCost + step.learnCost
			end
		end
	end
	totals.net = totals.materials - totals.giveBack + totals.learnCost
	return totals
end

-- Whether the player's choice of recipes lets the route use this one. "known" keeps only learned
-- recipes; "all" and "trainer" keep every recipe ("trainer" then ranks them, see `cheapestAt`).
local function inRecipeScope(candidate, recipeScope)
	return candidate.learned or recipeScope ~= "known"
end

-- Candidates the route may use, and how many of those were left out for want of a material price.
local function usableCandidates(request)
	local usable, skippedForPrice = {}, 0
	for _, candidate in ipairs(request.candidates or {}) do
		if inRecipeScope(candidate, request.recipeScope) then
			if candidate.materialCost then
				usable[#usable + 1] = candidate
			else
				skippedForPrice = skippedForPrice + 1
			end
		end
	end
	return usable, skippedForPrice
end

--- The cheapest route. `request = { fromSkill, rankCap, maxSkill, giveBackMode, recipeScope, candidates }`.
--- `rankCap` is where the current rank stops; `maxSkill` is the highest skill the profession can reach.
--- `recipeScope`: "all" (cheapest of every recipe, the default here), "trainer" (known recipes and
--- ones a trainer teaches first; others only for points none of those can give) or "known".
--- Returns `{ steps, totals = { materials, giveBack, learnCost, net }, fromSkill, toSkill, skippedForPrice }`.
--- A step is `{ kind = "craft", recipeID, name, fromSkill, toSkill, crafts, materials, giveBack, net,
--- learned, learnCost, estimated, candidate, reusedQuantity, reuseValue }` or `{ kind = "rankCap", skill }`.
--- `reusedQuantity` of the step's items are a material of later steps and count for `reuseValue`. `crafts` is an
--- expected count, since a yellow or green recipe does not give a point on every craft.
function LevelingRouteLogic.BuildRoute(request)
	local usable, skippedForPrice = usableCandidates(request)
	local search = {
		candidates = usable, giveBackMode = request.giveBackMode, maxSkill = request.maxSkill, excluded = {},
		withinReachFirst = request.recipeScope == "trainer",
	}
	local picks = pickWithReuse(search, request.fromSkill)
	local steps = stepsFromPicks(picks, request)
	return {
		steps = steps, totals = routeTotals(steps), skippedForPrice = skippedForPrice,
		fromSkill = request.fromSkill, toSkill = request.fromSkill + #picks,
	}
end

--- The craft-queue entry for a step: `{ recipeID, quantity }`. Only a step for a learned recipe has one.
function LevelingRouteLogic.QueueEntry(step)
	if not step or step.kind ~= "craft" or not step.learned or step.crafts < 1 then
		return nil
	end
	return { recipeID = step.recipeID, quantity = step.crafts }
end

--- Whole crafts of a step for its skill points below `toSkill` (all of them when the step ends there
--- or earlier). 0 for a rank-cap step or a step that starts at or above `toSkill`.
function LevelingRouteLogic.CraftsUpTo(step, toSkill)
	if step.kind ~= "craft" then
		return 0
	end
	local expected = 0
	for skill = step.fromSkill, math.min(step.toSkill, toSkill) - 1 do
		expected = expected + craftsPerPoint(step.candidate, skill)
	end
	return math.ceil(expected - ROUNDING_SLACK)
end

--- What to queue to follow the route up to `toSkill`: `{ { recipeID, quantity, step } }` in route
--- order, one entry per recipe (the craft queue holds one line per recipe) with `step` its first
--- step. Recipes not learned yet are included: their line waits until the recipe is learned.
function LevelingRouteLogic.QueueEntriesUpTo(steps, toSkill)
	local entries, byRecipe = {}, {}
	for _, step in ipairs(steps or {}) do
		local crafts = LevelingRouteLogic.CraftsUpTo(step, toSkill)
		if crafts > 0 then
			local entry = byRecipe[step.recipeID]
			if not entry then
				entry = { recipeID = step.recipeID, quantity = 0, step = step }
				byRecipe[step.recipeID] = entry
				entries[#entries + 1] = entry
			end
			entry.quantity = entry.quantity + crafts
		end
	end
	return entries
end

--- Crafts to add (positive) or remove (negative) so a queued count matches what the recipe's steps
--- still need. `steps` are the route's current steps; a recipe no longer in the route needs none.
function LevelingRouteLogic.QueueAdjustment(queuedQuantity, recipeID, steps)
	local needed = 0
	for _, step in ipairs(steps or {}) do
		if step.kind == "craft" and step.recipeID == recipeID then
			needed = needed + step.crafts
		end
	end
	return needed - (queuedQuantity or 0)
end

--- Fills in what a trainer has been seen to ask for a recipe not learned, and which trainers teach it.
--- `trainerRecipes = { [recipeName] = { skillRequired, cost, trainers } }`.
function LevelingRouteLogic.ApplyTrainerData(candidates, trainerRecipes)
	for _, candidate in ipairs(candidates or {}) do
		local seen = (not candidate.learned) and trainerRecipes and trainerRecipes[candidate.name]
		if seen then
			candidate.learnSkill, candidate.learnCost, candidate.source = seen.skillRequired, seen.cost, "trainer"
			candidate.trainers = seen.trainers
		end
	end
	return candidates
end

-- One trainer service as a stored entry.
local function trainerEntry(service, sighting)
	local trainers = nil
	if sighting.trainerName then
		trainers = { [sighting.trainerName] = sighting.place or {} }
	end
	return { skillRequired = tonumber(service.skillRequired) or 0, cost = tonumber(service.cost) or 0, seenAt = sighting.now, trainers = trainers }
end

-- Services that are no scanned recipe, kept as rank training (Expert, Artisan) of the profession the
-- trainer's recipes belong to. Without recipes of exactly one profession there is no telling which
-- profession a service is for, and nothing is kept.
local function rankEntries(otherServices, professionsSeen, sighting)
	local skillLineKey = next(professionsSeen)
	if not skillLineKey or next(professionsSeen, skillLineKey) then
		return {}
	end
	local ranks = {}
	for _, service in ipairs(otherServices) do
		ranks[service.name] = trainerEntry(service, sighting)
	end
	return { [skillLineKey] = ranks }
end

--- What to remember from an open trainer window. `services = { { name, cost, skillRequired } }` as
--- the trainer lists them; `skillLineByRecipeName` says which profession each known recipe name
--- belongs to. `sighting = { now, trainerName, place = { zone, mapID, x, y } }` says who was asked,
--- where and when. Returns two tables of the same shape,
--- `{ [skillLineKey] = { [serviceName] = { skillRequired, cost, seenAt, trainers } } }` with
--- `trainers = { [trainerName] = place }`: the recipes, and the other services of a profession
--- trainer, which are its rank training. A window without scanned recipes (a class trainer) gives nothing.
function LevelingRouteLogic.TrainerEntries(services, skillLineByRecipeName, sighting)
	local recipes, otherServices, professionsSeen = {}, {}, {}
	sighting = sighting or {}
	for _, service in ipairs(services or {}) do
		local skillLineKey = service.name and skillLineByRecipeName[service.name]
		if skillLineKey then
			professionsSeen[skillLineKey] = true
			recipes[skillLineKey] = recipes[skillLineKey] or {}
			recipes[skillLineKey][service.name] = trainerEntry(service, sighting)
		elseif service.name then
			otherServices[#otherServices + 1] = service
		end
	end
	return recipes, rankEntries(otherServices, professionsSeen, sighting)
end

-- How far apart a profession's ranks are in skill: the caps are 75, 150, 225 and 300.
LevelingRouteLogic.RANK_STEP = 75

--- The training that lifts a rank cap of `rankCap`, out of the rank services seen at trainers
--- (`{ [serviceName] = { skillRequired, cost, trainers } }`): `{ name, skillRequired, cost, trainers }`
--- or nil. A rank is trained at a skill below the cap it lifts and above the cap before it, so that
--- is the service looked for; a lower rank's training, seen earlier, asks for less.
function LevelingRouteLogic.NextRankTraining(rankServices, rankCap)
	local best, bestName
	for name, service in pairs(rankServices or {}) do
		local skill = service.skillRequired or 0
		local liftsThisCap = skill <= rankCap and skill > rankCap - LevelingRouteLogic.RANK_STEP
		if liftsThisCap and (not best or skill > best.skillRequired) then
			best, bestName = service, name
		end
	end
	if not best then
		return nil
	end
	return { name = bestName, skillRequired = best.skillRequired, cost = best.cost, trainers = best.trainers }
end

local function addTrainers(target, trainers)
	for name, place in pairs(trainers or {}) do
		target[name] = place
	end
end

--- Two sightings of the same trainer recipe as one: cost and skill from the newer, every trainer
--- from both. `known` may be nil. With `withoutTrainers`, the trainers of `entry` are left out (a
--- sighting by a character of the other faction: its trainers will not teach this one).
function LevelingRouteLogic.MergeTrainerEntry(known, entry, withoutTrainers)
	local newer = entry
	if known and (known.seenAt or 0) > (entry.seenAt or 0) then
		newer = known
	end
	local merged = { skillRequired = newer.skillRequired, cost = newer.cost, seenAt = newer.seenAt, trainers = {} }
	addTrainers(merged.trainers, known and known.trainers)
	if not withoutTrainers then
		addTrainers(merged.trainers, entry.trainers)
	end
	return merged
end
