-- Run with: lua5.1 tests/test_leveling_route.lua (from Tradewright root)
-- The leveling route built from a stored profession: why there is no route, what a priced recipe
-- becomes, stored colours after a skill-up, and the rows the side panel shows.
local root = arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]") or "."
local addons = root .. "/.."

local failed = 0
local function check(name, cond, detail)
	if cond then
		print("OK  " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
	end
end

local CHARACTER, SKILL_LINE = "Tester", 165

-- Timers run at once, so a route is ready on the second request.
rawset(_G, "C_Timer", { After = function(_, callback) callback() end })
local liveRecipeInfo = {}
-- The expansion the profession window shows (retail), and which recipes belong to which expansion.
local shownExpansion, recipeExpansion = nil, {}
rawset(_G, "C_TradeSkillUI", {
	GetRecipeInfo = function(spellID) return liveRecipeInfo[spellID] end,
	GetChildProfessionInfo = function() return shownExpansion end,
	IsRecipeInSkillLine = function(spellID, skillLineID) return recipeExpansion[spellID] == skillLineID end,
})
-- No time passes, so every recipe is priced in the first frame.
rawset(_G, "debugprofilestop", function() return 0 end)
rawset(_G, "CreateFrame", function()
	return { RegisterEvent = function() end, SetScript = function() end }
end)

local function loadInto(pe, path)
	local chunk, err = loadfile(path)
	assert(chunk, err)
	chunk("Tradewright", pe)
end

local function recipe(name, greyLevel, learned, materialCost)
	return { recipeSpellID = greyLevel * 10, materialCost = materialCost,
		info = { name = name, maxTrivialLevel = greyLevel, learned = learned, numSkillUps = 1, relativeDifficulty = 0 } }
end

local function newAddon(recipes, skill)
	local pe = { state = { dataRevision = 1 }, settings = {}, queued = {} }
	pe.db = { characters = { [CHARACTER] = { professions = { [tostring(SKILL_LINE)] = {
		professionName = "Leatherworking", skillLineID = SKILL_LINE, skillLevel = skill, maxSkillLevel = 150, recipes = recipes,
	} } } } }
	-- The real recipe readers; what follows replaces the parts that need the game.
	loadInto(pe, root .. "/src/util/Tradewright_Util.lua")
	function pe:InitDB() end
	function pe:GetState() return self.state end
	function pe:GetCharacterKey() return CHARACTER end
	-- What the game reports for the character's professions; nil skill means "as stored".
	function pe:GetPlayerProfessions()
		return { { skillLineID = SKILL_LINE, skillLevel = self.gameSkill, maxSkillLevel = self.gameRankCap } }
	end
	function pe:GetSetting(key, default)
		if self.settings[key] ~= nil then
			return self.settings[key]
		end
		return default
	end
	function pe:GetItemVendorSellCopper() return 40 end
	function pe:GetRecipeSource() return nil end
	function pe:EvaluateCraftScenario(_, _, _, recipeData)
		if not recipeData.materialCost then
			return { matMissingPrice = true }
		end
		if recipeData.salvageItemID then
			-- As the crafts engine answers for Prospecting or Milling: a cost, no crafted item.
			return { fullMatCost = recipeData.materialCost, isSalvage = true, outputItemID = recipeData.recipeSpellID,
				outputQty = 5, recipeName = recipeData.info.name, reagentPlan = { { itemID = recipeData.salvageItemID, quantityRequired = 5, priceUnit = 20 } } }
		end
		return { fullMatCost = recipeData.materialCost, outputQty = 2, outputItemID = 1, saleNet = 70, recipeName = recipeData.info.name }
	end
	function pe:FormatCopperShort(copper) return tostring(copper) .. "c" end
	function pe:GetItemDisplayName(itemID) return "Item " .. itemID end
	function pe:GetLevelingQueuedQuantity(_, recipeID) return self.queued[recipeID] or 0 end
	for _, path in ipairs({
		root .. "/src/util/Tradewright_SkillUpLogic.lua",
		root .. "/src/util/Tradewright_LevelingRouteLogic.lua",
		addons .. "/Tradewright_Professions/src/modules/Tradewright_LevelingRoute.lua",
		addons .. "/Tradewright_UI/src/ui/Tradewright_ProfessionLevelingView.lua",
	}) do
		loadInto(pe, path)
	end
	return pe
end

local function routeFor(pe)
	pe:GetLevelingRoute(CHARACTER, SKILL_LINE)
	return pe:GetLevelingRoute(CHARACTER, SKILL_LINE)
end

-- Why there is no route
do
	local _, reason = newAddon({}, 100):GetLevelingRoute(CHARACTER, SKILL_LINE)
	check("No recipes stored: no_data", reason == "no_data")
	_, reason = newAddon({ ["1"] = recipe("A", 200, true, 100) }, 100):GetLevelingRoute(CHARACTER, 999)
	check("Profession never scanned: no_data", reason == "no_data")

	local pending = newAddon({ ["1"] = recipe("A", 200, true, 100) }, 100)
	rawset(_G, "C_Timer", { After = function() end })
	local _, firstReason, progress = pending:GetLevelingRoute(CHARACTER, SKILL_LINE)
	rawset(_G, "C_Timer", { After = function(_, callback) callback() end })
	check("While recipes are priced: not_ready with progress", firstReason == "not_ready" and progress.done == 0 and progress.total == 1)

	local noGrey = recipe("A", 200, true, 100)
	noGrey.info.maxTrivialLevel = nil
	_, reason = routeFor(newAddon({ ["1"] = noGrey }, 100))
	check("No grey levels reported: unsupported", reason == "unsupported")
	_, reason = routeFor(newAddon({ ["1"] = recipe("A", 90, true, 100) }, 100))
	check("Every recipe grey: finished", reason == "finished")
	_, reason = routeFor(newAddon({ ["1"] = recipe("A", 200, true, nil) }, 100))
	check("Nothing priced: no_prices", reason == "no_prices")
end

-- A priced recipe
do
	local pe = newAddon({ ["11"] = recipe("Known", 200, true, 100), ["12"] = recipe("Unknown", 240, false, 100) }, 100)
	local route = routeFor(pe)
	check("Route carries the profession and the rank cap", route and route.professionName == "Leatherworking"
		and route.skillLineID == SKILL_LINE and route.characterKey == CHARACTER and route.rankCap == 150)
	local known = route.steps[1].candidate
	check("Costs come from the crafts engine, per craft", known.materialCost == 100 and known.vendorGiveBack == 80 and known.auctionGiveBack == 140)
	check("Recipe id is the crafting spell, which the profession window and the craft queue open", known.recipeID == 2000)
	check("Vendor sale is the default give-back", route.giveBackMode == "vendor" and route.steps[1].net == route.steps[1].crafts * 20)
	local unknown
	for _, step in ipairs(route.steps) do
		if step.name == "Unknown" then
			unknown = step
		end
	end
	check("A recipe not learned is assumed learnable 50 below its grey level", unknown and unknown.candidate.learnSkill == 190)
	check("Trainer recipes first is the default: it only takes over where the known recipe gives out", unknown.fromSkill == 200)

	pe.settings["professions.leveling.recipes"] = "known"
	pe.settings["professions.leveling.giveBack"] = "none"
	local learnedOnly = routeFor(pe)
	check("Settings change the route without pricing again", learnedOnly.toSkill == 200 and learnedOnly.totals.net == learnedOnly.totals.materials)

	local shown = routeFor(pe)
	local build = pe.state.leveling.build
	pe.state.dataRevision = 2
	check("A bag change alone does not price the recipes again",
		pe:GetLevelingRoute(CHARACTER, SKILL_LINE) == shown and pe.state.leveling.build == build)

	rawset(_G, "C_Timer", { After = function() end })
	pe:InvalidateLevelingRoute()
	local whilePricing, reason = pe:GetLevelingRoute(CHARACTER, SKILL_LINE)
	check("New prices: recipes are priced again", pe.state.leveling.build ~= build and not pe.state.leveling.build.done)
	check("... and the previous route stays up meanwhile", whilePricing == shown and reason == nil)
	rawset(_G, "C_Timer", { After = function(_, callback) callback() end })

	pe.db.characters[CHARACTER].professions[tostring(SKILL_LINE)].skillLevel = 101
	local afterSkillUp = routeFor(pe)
	check("A skill-up gives a new route from the new skill", afterSkillUp ~= shown and afterSkillUp.fromSkill == 101)
end

-- A salvage recipe (Prospecting, Milling)
do
	local ORE = 123918
	local prospecting = recipe("Prospecting", 200, true, 100)
	prospecting.salvageItemID = ORE
	local route = routeFor(newAddon({ ["11"] = prospecting }, 100))
	local step = route and route.steps[1]
	check("It is routed with the cost of the item it destroys", step and step.candidate.materialCost == 100)
	check("It makes no item: nothing is sold back or reused, so the step costs its reagents",
		step.candidate.outputItemID == nil and step.candidate.vendorGiveBack == nil and step.net == step.materials)
	local pe = newAddon({ ["11"] = prospecting }, 100)
	local shown = routeFor(pe)
	check("The row names the item it is priced with",
		pe:LevelingStepRow(shown, shown.steps[1], 1, true).detailText:find("with Item " .. ORE, 1, true) ~= nil)
end

-- The profession's highest skill
do
	local recipes = { ["11"] = recipe("Long", 400, true, 100) }
	check("Forever: the route stops at 300 though the recipe stays orange", routeFor(newAddon(recipes, 100)).toSkill == 300)
	local retail = newAddon(recipes, 100)
	retail.IS_RETAIL = true
-- Ranks of one recipe (separate spells; the profession window lists the highest known)
do
	local function ranked(greyLevel, learned, materialCost, nextSpellID)
		local recipeData = recipe("Word of Mastery", greyLevel, learned, materialCost)
		recipeData.info.nextRecipeID = nextSpellID
		return recipeData
	end
	local rankOne, rankTwo, rankThree = ranked(140, true, 50, 1410), ranked(141, true, 300, 1420), ranked(142, false, 10, nil)
	-- Stored under another key than the spell, as scanned recipes are.
	local pe = newAddon({ ["1"] = rankOne, ["2"] = rankTwo, ["3"] = rankThree }, 100)
	pe.settings["professions.leveling.recipes"] = "known"
	local route = routeFor(pe)
	check("Ranks: a rank replaced by a known higher one is left out, though cheaper",
		#route.steps == 1 and route.steps[1].recipeID == pe:GetRecipeSpellID(rankTwo), route.steps[1] and route.steps[1].recipeID)
	local professionData = pe.db.characters[CHARACTER].professions[tostring(SKILL_LINE)]
	check("Ranks: the highest known rank is not replaced by one still to learn",
		not pe:IsReplacedRecipeRank(professionData, rankTwo) and pe:IsReplacedRecipeRank(professionData, rankOne))
end

	local retailRoute = routeFor(retail)
	check("Retail has no ranks: the profession's own cap is the highest skill, with no rank step",
		retailRoute.toSkill == 150 and #retailRoute.steps == 1)
	local _, reason = routeFor(newAddon(recipes, 300))
	check("At the highest skill: finished", reason == "finished")
end

-- Skill and rank cap follow the game
do
	local pe = newAddon({ ["11"] = recipe("Long", 400, true, 100) }, 125)
	pe.state.liveProfessionSkillLineID = SKILL_LINE
	pe:GetOpenProfessionLevelingRoute()
	local stale = pe:GetOpenProfessionLevelingRoute()
	check("Stored skill and cap are used while the game says nothing else", stale.fromSkill == 125 and stale.rankCap == 150)
	pe.gameSkill, pe.gameRankCap = 150, 225
	pe:GetOpenProfessionLevelingRoute()
	local current = pe:GetOpenProfessionLevelingRoute()
	check("A skill-up the stored data missed is read from the game", current.fromSkill == 150)
	check("A new rank moves the rank cap", current.rankCap == 225 and current.steps[1].kind == "craft" and current.steps[2].kind == "rankCap")
	pe.gameRankCap = 300
	pe:GetOpenProfessionLevelingRoute()
	check("A new rank alone, without a skill change, redoes the route", pe:GetOpenProfessionLevelingRoute().rankCap == 300)
end

-- Retail: the route levels the expansion the profession window shows
do
	local DRAENOR, LEGION = 2540, 2541
	local pe = newAddon({ ["11"] = recipe("Draenor ring", 90, true, 100), ["12"] = recipe("Legion ring", 80, true, 100) }, 1)
	pe.IS_RETAIL = true
	pe.state.liveProfessionSkillLineID = SKILL_LINE
	recipeExpansion[900], recipeExpansion[800] = DRAENOR, LEGION
	liveRecipeInfo[900] = { maxTrivialLevel = 90, learned = true, relativeDifficulty = 0 }
	liveRecipeInfo[800] = { maxTrivialLevel = 80, learned = true, relativeDifficulty = 0 }
	shownExpansion = { professionID = LEGION, professionName = "Legion Leatherworking", skillLevel = 20, maxSkillLevel = 100 }
	pe:GetOpenProfessionLevelingRoute()
	local legion = pe:GetOpenProfessionLevelingRoute()
	check("The route starts at the shown expansion's skill and carries its name",
		legion.fromSkill == 20 and legion.rankCap == 100 and legion.professionName == "Legion Leatherworking"
		and legion.expansionSkillLineID == LEGION and legion.skillLineID == SKILL_LINE)
	check("Only that expansion's recipes are in the route", #legion.steps == 1 and legion.steps[1].name == "Legion ring")
	local observations = pe.db.characters[CHARACTER].difficultyObservations[tostring(SKILL_LINE)]
	check("Colours are recorded for that expansion's recipes only, at its skill",
		observations["12"] ~= nil and observations["11"] == nil)

	rawset(_G, "C_Timer", { After = function() end })
	shownExpansion = { professionID = DRAENOR, professionName = "Draenor Leatherworking", skillLevel = 50, maxSkillLevel = 100 }
	local whilePricing, reason = pe:GetOpenProfessionLevelingRoute()
	check("Another expansion picked: its route is worked out, the old one is not shown meanwhile",
		whilePricing == nil and reason == "not_ready")
	check("Without a route yet the panel still gets the expansion's name and skill",
		pe:GetOpenProfessionLevelingScope().name == "Draenor Leatherworking" and pe:GetOpenProfessionLevelingScope().fromSkill == 50)
	rawset(_G, "C_Timer", { After = function(_, callback) callback() end })
	-- The pricing started above was dropped with its timer; start it again.
	pe:InvalidateLevelingRoute()
	pe:GetOpenProfessionLevelingRoute()
	local draenor = pe:GetOpenProfessionLevelingRoute()
	check("... and then shows that expansion's recipes from its skill",
		draenor.fromSkill == 50 and #draenor.steps == 1 and draenor.steps[1].name == "Draenor ring")

	shownExpansion.skillLevel = 100
	local _, finishedReason = pe:GetOpenProfessionLevelingRoute()
	check("An expansion at its cap: finished, whatever the other expansions have left", finishedReason == "finished")
	shownExpansion = nil
end

-- Stored colours after a skill-up
do
	local pe = newAddon({ ["11"] = recipe("Known", 200, true, 100), ["12"] = recipe("Unknown", 240, false, 100) }, 180)
	local characterData = pe.db.characters[CHARACTER]
	local professionData = characterData.professions[tostring(SKILL_LINE)]
	liveRecipeInfo[2000] = { maxTrivialLevel = 200, learned = true, relativeDifficulty = 1 }
	liveRecipeInfo[2400] = { maxTrivialLevel = 240, learned = false, relativeDifficulty = 0 }
	pe:RefreshRecipeDifficulties(characterData, professionData)
	local observations = characterData.difficultyObservations[tostring(SKILL_LINE)]
	check("Colour is stored from the game", professionData.recipes["11"].info.relativeDifficulty == 1)
	check("A learned recipe's colour is recorded as a sighting", observations["11"] and observations["11"].yellowStartMax == 180)
	check("A recipe not learned is not recorded", observations["12"] == nil)
	liveRecipeInfo[2000].relativeDifficulty = 2
	pe:RefreshRecipeDifficulties(characterData, professionData)
	check("Same skill: not read again", professionData.recipes["11"].info.relativeDifficulty == 1)

	pe.state.liveProfessionSkillLineID = SKILL_LINE
	local before = routeFor(pe)
	check("Before training the recipe is not learned", before.steps[#before.steps].learned == false)
	liveRecipeInfo[2400].learned = true
	pe:RereadRecipesAfterLearning()
	check("After training it is stored as learned, without a skill change", professionData.recipes["12"].info.learned == true)
	pe:GetOpenProfessionLevelingRoute()
	local after = pe:GetOpenProfessionLevelingRoute()
	check("... and the route is worked out again with it learned", after ~= before and after.steps[#after.steps].learned == true)
end

-- Rows of the side panel
do
	local pe = newAddon({ ["11"] = recipe("Known", 200, true, 100), ["12"] = recipe("Unknown", 240, false, 100) }, 100)
	local route = routeFor(pe)
	local first = pe:LevelingStepRow(route, route.steps[1], 1, true)
	check("Craft row: skill range, next step, Queue", first.skillText == "100–150" and first.detailText:find("next step", 1, true)
		and first.action == "queue" and first.cost == route.steps[1].net, first.skillText .. " / " .. first.detailText)
	check("Colour bounds not yet seen in game: the craft count says about", first.detailText:find("^~%d+ crafts") ~= nil)
	local cap = pe:LevelingStepRow(route, route.steps[2], 2, false)
	check("Rank cap row", cap.kind == "rankCap" and cap.skillText == "150" and cap.detailText == "at a Leatherworking trainer")
	check("Rank cap row: no trainer seen offering the rank, Trainer is off", cap.action == "trainer" and cap.learnBlockedBy == "no_trainer")
	route.nextRank = { name = "Expert Leatherworker", skillRequired = 125, cost = 5000, trainers = { Karolek = { zone = "Orgrimmar" } } }
	local known = pe:LevelingStepRow(route, route.steps[2], 2, false)
	check("Rank cap row: names the rank and its skill", known.detailText == "Expert Leatherworker · skill 125")
	check("Rank cap row: skill below what the rank asks, Trainer is off", known.learnBlockedBy == "skill")
	route.nextRank.skillRequired = 100
	check("Rank cap row: skill reached and a trainer known, Trainer is on", pe:LevelingStepRow(route, route.steps[2], 2, false).learnBlockedBy == nil)
	route.nextRank = nil
	pe.queued[2000] = route.steps[1].crafts
	check("Queued in full: Queued", pe:LevelingStepRow(route, route.steps[1], 1, true).action == "queued")
	pe.queued[2000] = 3
	local partly = pe:LevelingStepRow(route, route.steps[1], 1, true)
	check("Queued in part: count shown, Queue offered again", partly.action == "queue" and partly.detailText:find("3 in queue", 1, true))
	local last = route.steps[#route.steps]
	local learn = pe:LevelingStepRow(route, last, #route.steps, false)
	check("Recipe not learned: Learn, source unknown", learn.action == "learn" and learn.detailText:find("source unknown", 1, true))
	check("No trainer seen teaching it: Learn is off", learn.learnBlockedBy == "no_trainer")
	check("A step for a known recipe is never blocked", first.learnBlockedBy == nil)
	last.candidate.source, last.candidate.learnCost, last.candidate.learnSkill = "trainer", 500, 190
	check("Trainer recipe shows the skill needed to learn it",
		pe:LevelingStepRow(route, last, #route.steps, false).detailText:find("trainer, skill 190", 1, true))
	last.candidate.trainers = { Karolek = { zone = "Orgrimmar" } }
	check("Trainer asks for more skill than the player has: Learn is off",
		pe:LevelingStepRow(route, last, #route.steps, false).learnBlockedBy == "skill")
	last.candidate.learnSkill = 100
	check("Skill reached and a trainer known: Learn is on", pe:LevelingStepRow(route, last, #route.steps, false).learnBlockedBy == nil)
	last.candidate.source, last.candidate.trainers, last.candidate.learnSkill = "vendor", nil, 190
	last.candidate.vendors = { Una = { price = 500 } }
	local sold = pe:LevelingStepRow(route, last, #route.steps, false)
	check("Vendor recipe shows its price, and an estimated skill does not turn Learn off",
		sold.detailText:find("vendor, 500c", 1, true) and sold.learnBlockedBy == nil)
	last.candidate.source, last.candidate.vendors = "drop", nil
	last.candidate.dropSource = { name = "Bristleback Shaman", held = 1, opened = 40 }
	local dropped = pe:LevelingStepRow(route, last, #route.steps, false)
	check("Dropped recipe names the creature, Learn stays off",
		dropped.detailText:find("drops from Bristleback Shaman", 1, true) and dropped.learnBlockedBy == "no_trainer")
	pe.settings["professions.leveling.giveBack"] = "none"
	local materialsOnly = routeFor(pe)
	check("Crafted items counted as nothing: the row shows materials",
		pe:LevelingStepRow(materialsOnly, materialsOnly.steps[1], 1, true).cost == materialsOnly.steps[1].materials)
end

if failed > 0 then
	os.exit(1)
end
