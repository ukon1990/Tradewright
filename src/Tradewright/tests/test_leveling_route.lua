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
rawset(_G, "C_TradeSkillUI", { GetRecipeInfo = function(spellID) return liveRecipeInfo[spellID] end })
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
	function pe:InitDB() end
	function pe:GetState() return self.state end
	function pe:GetCharacterKey() return CHARACTER end
	function pe:GetSetting(key, default)
		if self.settings[key] ~= nil then
			return self.settings[key]
		end
		return default
	end
	function pe:RecipeDataInfo(recipeData) return recipeData.info end
	function pe:GetRecipeSpellID(recipeData) return recipeData.recipeSpellID end
	function pe:GetItemVendorSellCopper() return 40 end
	function pe:EvaluateCraftScenario(_, _, _, recipeData)
		if not recipeData.materialCost then
			return { matMissingPrice = true }
		end
		return { fullMatCost = recipeData.materialCost, outputQty = 2, outputItemID = 1, saleNet = 70, recipeName = recipeData.info.name }
	end
	function pe:FormatCopperShort(copper) return tostring(copper) .. "c" end
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

-- The profession's highest skill
do
	local recipes = { ["11"] = recipe("Long", 400, true, 100) }
	check("Forever: the route stops at 300 though the recipe stays orange", routeFor(newAddon(recipes, 100)).toSkill == 300)
	local retail = newAddon(recipes, 100)
	retail.IS_RETAIL = true
	local retailRoute = routeFor(retail)
	check("Retail has no ranks: the profession's own cap is the highest skill, with no rank step",
		retailRoute.toSkill == 150 and #retailRoute.steps == 1)
	local _, reason = routeFor(newAddon(recipes, 300))
	check("At the highest skill: finished", reason == "finished")
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
	check("Rank cap row", cap.kind == "rankCap" and cap.skillText == "150" and cap.detailText == "at a Leatherworking trainer" and cap.action == nil)
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
	pe.settings["professions.leveling.giveBack"] = "none"
	local materialsOnly = routeFor(pe)
	check("Crafted items counted as nothing: the row shows materials",
		pe:LevelingStepRow(materialsOnly, materialsOnly.steps[1], 1, true).cost == materialsOnly.steps[1].materials)
end

if failed > 0 then
	os.exit(1)
end
