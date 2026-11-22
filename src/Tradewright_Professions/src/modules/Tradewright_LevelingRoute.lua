local _, Tradewright = ...

-- The leveling route for a character's profession: prices every recipe that can still give skill (in
-- chunks, so a profession with hundreds of recipes does not freeze the game) and hands the priced
-- recipes to LevelingRouteLogic. Also keeps each recipe's stored colour current after a skill-up.

local SkillUpLogic = Tradewright.SkillUpLogic
local LevelingRouteLogic = Tradewright.LevelingRouteLogic

local CANDIDATE_CHUNK_SIZE = 60

-- The game does not say at which skill a recipe can be learned. Until a trainer has been seen to
-- teach it, assume it can be learned this far below its grey level.
local ASSUMED_LEARN_SPAN = 50

-- Materials at market price whatever the player owns or once paid: the route compares recipes, and
-- what is still to buy comes from the craft queue's shopping list.
local MARKET_PRICING = { scenario = "default", costBasis = "market", saleBasis = "market" }

-- The highest profession skill outside retail (WoW Forever). No game call reports it: per
-- profession the game gives only the cap of the current rank (`maxSkillLevel`, 150 for a Journeyman).
local MAX_SKILL_WITH_RANKS = 300

-- The highest skill the profession can reach. Retail has no ranks, so the profession's own cap is it.
local function professionMaxSkill(self, professionData)
	if self.IS_RETAIL then
		return tonumber(professionData.maxSkillLevel)
	end
	return MAX_SKILL_WITH_RANKS
end

local function skillLineKey(skillLineID)
	return tostring(skillLineID)
end

-- Colours the game has shown per recipe, kept beside the professions because a full scan replaces
-- the profession's own table: `characterData.difficultyObservations[skillLineKey][recipeKey]`.
local function difficultyObservations(characterData, skillLineID)
	characterData.difficultyObservations = characterData.difficultyObservations or {}
	local bySkillLine = characterData.difficultyObservations
	bySkillLine[skillLineKey(skillLineID)] = bySkillLine[skillLineKey(skillLineID)] or {}
	return bySkillLine[skillLineKey(skillLineID)]
end

local function levelingState(self)
	local state = self:GetState()
	state.leveling = state.leveling or { revision = 0 }
	return state.leveling
end

--- Prices or the learned recipes changed: the next request prices the recipes again.
function Tradewright:InvalidateLevelingRoute()
	local leveling = levelingState(self)
	leveling.revision = leveling.revision + 1
end

-- Copies one recipe's colour, grey level and learned state from the game into the stored recipe and
-- records the colour as a sighting. The game only reports a meaningful colour for learned recipes,
-- so only those are recorded. Returns whether the recipe's learned state changed.
local function readRecipeFromGame(self, read, recipeKey, recipeData)
	local stored = self:RecipeDataInfo(recipeData)
	local live = stored and C_TradeSkillUI.GetRecipeInfo(self:GetRecipeSpellID(recipeData))
	local greyLevel = live and tonumber(live.maxTrivialLevel)
	if not greyLevel then
		return false
	end
	local learnedChanged = (stored.learned == true) ~= (live.learned == true)
	stored.relativeDifficulty, stored.maxTrivialLevel, stored.learned = live.relativeDifficulty, greyLevel, live.learned
	if live.learned then
		read.observations[recipeKey] = SkillUpLogic.RecordObservation(
			read.observations[recipeKey], greyLevel, read.skill, SkillUpLogic.DifficultyName(live.relativeDifficulty))
	end
	return learnedChanged
end

--- Re-reads every recipe's colour and learned state for the open profession when its skill has
--- changed since the last read, or always with `force` (after training, which changes no skill).
--- A recipe that was learned or unlearned makes the route work itself out again.
function Tradewright:RefreshRecipeDifficulties(characterData, professionData, force)
	local skill = tonumber(professionData.skillLevel)
	if not skill or not C_TradeSkillUI.GetRecipeInfo or (professionData.difficultyReadAtSkill == skill and not force) then
		return
	end
	local read = { skill = skill, observations = difficultyObservations(characterData, professionData.skillLineID) }
	local learnedChanged = false
	for recipeKey, recipeData in pairs(professionData.recipes or {}) do
		learnedChanged = readRecipeFromGame(self, read, recipeKey, recipeData) or learnedChanged
	end
	professionData.difficultyReadAtSkill = skill
	if learnedChanged then
		self:InvalidateLevelingRoute()
	end
end

-- The stored profession whose window is open, for the logged-in character: `characterData, professionData`.
local function openProfession(self)
	local skillLineID = self:GetState().liveProfessionSkillLineID
	local characterData = self.db and self.db.characters and self.db.characters[self:GetCharacterKey()]
	local professionData = skillLineID and characterData and characterData.professions
		and characterData.professions[skillLineKey(skillLineID)]
	return characterData, professionData
end

--- A recipe may have been learned (a trainer, a recipe item): reads the open profession's recipes
--- again and redraws the side panel. Professions that are not open are read when next opened.
function Tradewright:RereadRecipesAfterLearning()
	local characterData, professionData = openProfession(self)
	for _, profession in pairs(characterData and characterData.professions or {}) do
		profession.difficultyReadAtSkill = nil
	end
	if professionData then
		self:RefreshRecipeDifficulties(characterData, professionData, true)
		if self.ScheduleRefreshProfessionCraftEconomyPanel then
			self:ScheduleRefreshProfessionCraftEconomyPanel(0)
		end
	end
end

-- What the priced recipes depend on: the skill, the recipe list and prices. Bag contents are left
-- out on purpose (recipes are priced at market value), so a craft that gives no skill point changes
-- nothing here and the route is not worked out again.
local function candidatesKey(self, characterKey, professionData)
	return table.concat({
		characterKey, skillLineKey(professionData.skillLineID), tostring(professionData.skillLevel),
		tostring(professionData.maxSkillLevel), tostring(professionData.recipeCount),
		tostring(professionData.liveFingerprint), tostring(levelingState(self).revision),
	}, "|")
end

-- Recipes that can still give skill: `{ recipeKey, recipeData, greyLevel }`, and whether any recipe
-- carries a grey level at all.
local function recipesWithSkillLeft(self, professionData)
	local skill = tonumber(professionData.skillLevel) or 0
	local work, anyGreyLevel = {}, false
	for recipeKey, recipeData in pairs(professionData.recipes or {}) do
		local info = self:RecipeDataInfo(recipeData)
		local greyLevel = info and tonumber(info.maxTrivialLevel)
		if greyLevel then
			anyGreyLevel = true
			if greyLevel > skill then
				work[#work + 1] = { recipeKey = recipeKey, recipeData = recipeData, greyLevel = greyLevel }
			end
		end
	end
	return work, anyGreyLevel
end

-- What the items of one craft sell for: `vendor, auction` in copper, nil where there is no price.
local function giveBackPerCraft(self, evaluation)
	local outputQuantity = math.max(1, tonumber(evaluation.outputQty) or 1)
	local vendorSell = self:GetItemVendorSellCopper(evaluation.outputItemID)
	local vendor = vendorSell and vendorSell > 0 and vendorSell * outputQuantity or nil
	-- The crafts engine reports the vendor price as the sale when the recipe is vendor-sourced.
	local soldAtAuction = evaluation.saleNet and evaluation.saleSource ~= "Vendor sell"
	return vendor, soldAtAuction and evaluation.saleNet * outputQuantity or nil
end

-- The materials of one craft with the price the route pays for each: `{ { itemID, quantity, unitPrice } }`.
local function candidateReagents(evaluation)
	local reagents = {}
	for _, reagent in ipairs(evaluation.reagentPlan or {}) do
		if reagent.itemID and reagent.priceUnit then
			reagents[#reagents + 1] = {
				itemID = tonumber(reagent.itemID), quantity = tonumber(reagent.quantityRequired) or 1, unitPrice = reagent.priceUnit,
			}
		end
	end
	return reagents
end

-- Cost and give-back of one craft, read from the crafts engine. A recipe it cannot price (a missing
-- material price, or no crafted item to value, as with enchants) gets no `materialCost`.
local function priceCandidate(self, candidate, build, workItem)
	local evaluation = self:EvaluateCraftScenario(
		build.characterKey, build.professionData, tonumber(workItem.recipeKey) or workItem.recipeKey, workItem.recipeData, MARKET_PRICING)
	if not evaluation or evaluation.matMissingPrice or not evaluation.fullMatCost then
		return
	end
	candidate.evaluation = evaluation
	candidate.name = evaluation.recipeName or candidate.name
	candidate.materialCost = evaluation.fullMatCost
	candidate.vendorGiveBack, candidate.auctionGiveBack = giveBackPerCraft(self, evaluation)
	candidate.outputItemID = tonumber(evaluation.outputItemID)
	candidate.outputQuantity = math.max(1, tonumber(evaluation.outputQty) or 1)
	candidate.reagents = candidateReagents(evaluation)
end

local function buildCandidate(self, build, workItem)
	local info = self:RecipeDataInfo(workItem.recipeData)
	local learned = info.learned == true
	local candidate = {
		-- The crafting spell, not the key recipes are stored under: the profession window and the craft
		-- queue open a recipe by its spell.
		recipeID = self:GetRecipeSpellID(workItem.recipeData), name = info.name, learned = learned,
		greyLevel = workItem.greyLevel,
		bounds = SkillUpLogic.DifficultyBounds(workItem.greyLevel, build.observations[workItem.recipeKey]),
		skillUpsPerCraft = tonumber(info.numSkillUps) or 1,
		learnSkill = (not learned) and math.max(0, workItem.greyLevel - ASSUMED_LEARN_SPAN) or nil,
	}
	priceCandidate(self, candidate, build, workItem)
	return candidate
end

local function finishBuild(self, build)
	local trainerRecipes = self.GetTrainerRecipes and self:GetTrainerRecipes(build.professionData.skillLineID)
	LevelingRouteLogic.ApplyTrainerData(build.candidates, trainerRecipes)
	LevelingRouteLogic.ApplyRecipeSources(build.candidates, function(recipeName)
		return self:GetRecipeSource(recipeName)
	end)
	build.done = true
	if self.ScheduleRefreshProfessionCraftEconomyPanel then
		self:ScheduleRefreshProfessionCraftEconomyPanel(0)
	end
end

local function processCandidateChunk(self, build)
	if levelingState(self).build ~= build then
		return
	end
	local lastIndex = math.min(build.nextIndex + CANDIDATE_CHUNK_SIZE - 1, #build.work)
	for index = build.nextIndex, lastIndex do
		build.candidates[#build.candidates + 1] = buildCandidate(self, build, build.work[index])
	end
	build.nextIndex = lastIndex + 1
	if build.nextIndex > #build.work then
		return finishBuild(self, build)
	end
	C_Timer.After(0, function()
		processCandidateChunk(self, build)
	end)
end

-- The priced recipes for this profession, started in the background when the inputs have changed.
local function currentBuild(self, characterKey, characterData, professionData)
	local leveling = levelingState(self)
	local key = candidatesKey(self, characterKey, professionData)
	-- A full scan replaces the profession's table, so the same key on another table is new data.
	if leveling.build and leveling.build.key == key and leveling.build.professionData == professionData then
		return leveling.build
	end
	local work, anyGreyLevel = recipesWithSkillLeft(self, professionData)
	local build = {
		key = key, characterKey = characterKey, professionData = professionData, work = work, nextIndex = 1,
		anyGreyLevel = anyGreyLevel, candidates = {}, routes = {},
		observations = difficultyObservations(characterData, professionData.skillLineID),
	}
	leveling.build = build
	if #work == 0 then
		build.done = true
	else
		C_Timer.After(0, function()
			processCandidateChunk(self, build)
		end)
	end
	return build
end

--- The player's choices for the route:
--- `{ giveBackMode = "vendor" | "auction" | "none", recipeScope = "trainer" | "all" | "known" }`.
function Tradewright:GetLevelingSettings()
	return {
		giveBackMode = tostring(self:GetSetting("professions.leveling.giveBack", "vendor")),
		recipeScope = tostring(self:GetSetting("professions.leveling.recipes", "trainer")),
	}
end

-- Why a finished build has no route to show, or nil when it has one.
local function emptyRouteReason(build, route)
	if not build.anyGreyLevel then
		return "unsupported"
	elseif #build.work == 0 then
		return "finished"
	elseif #route.steps == 0 then
		return route.skippedForPrice > 0 and "no_prices" or "finished"
	end
	return nil
end

local function routeFromBuild(self, build)
	local settings = self:GetLevelingSettings()
	local routeKey = settings.giveBackMode .. "|" .. settings.recipeScope
	if not build.routes[routeKey] then
		local professionData = build.professionData
		local route = LevelingRouteLogic.BuildRoute({
			fromSkill = tonumber(professionData.skillLevel) or 0, rankCap = tonumber(professionData.maxSkillLevel),
			maxSkill = professionMaxSkill(self, professionData),
			giveBackMode = settings.giveBackMode, recipeScope = settings.recipeScope, candidates = build.candidates,
		})
		route.professionName, route.skillLineID, route.characterKey = professionData.professionName, professionData.skillLineID, build.characterKey
		route.giveBackMode, route.rankCap = settings.giveBackMode, tonumber(professionData.maxSkillLevel)
		route.nextRank = self.GetNextRankTraining and self:GetNextRankTraining(professionData.skillLineID, route.rankCap) or nil
		build.routes[routeKey] = route
		levelingState(self).shownRoute = route
		if self.TrimLevelingCraftQueue then
			self:TrimLevelingCraftQueue(route)
		end
	end
	return build.routes[routeKey]
end

-- The last route handed out, when it was for this character's profession.
local function previousRoute(self, characterKey, skillLineID)
	local previous = levelingState(self).shownRoute
	if previous and previous.characterKey == characterKey and previous.skillLineID == skillLineID then
		return previous
	end
	return nil
end

--- The leveling route for one character's profession, from its last scan and current prices.
--- Returns `route` (see `LevelingRouteLogic.BuildRoute`, plus `professionName`, `skillLineID`,
--- `characterKey`, `giveBackMode`, `rankCap`, and `nextRank` when a trainer has been seen offering the
--- training that lifts the rank cap), or `nil, reason, progress`:
--- "no_data" (not scanned), "not_ready" (still pricing; `progress = { done, total }`), "unsupported"
--- (the game reports no grey levels), "no_prices", "finished" (nothing can give skill any more).
--- While recipes are priced again after a skill-up or new prices, the previous route of the same
--- profession is returned, so a window showing it does not empty and refill.
function Tradewright:GetLevelingRoute(characterKey, skillLineID)
	self:InitDB()
	local characterData = self.db.characters and self.db.characters[characterKey]
	local professionData = characterData and characterData.professions and characterData.professions[skillLineKey(skillLineID)]
	if not professionData or not next(professionData.recipes or {}) then
		return nil, "no_data"
	end
	local build = currentBuild(self, characterKey, characterData, professionData)
	if not build.done then
		local previous = previousRoute(self, characterKey, professionData.skillLineID)
		if previous then
			return previous
		end
		return nil, "not_ready", { done = build.nextIndex - 1, total = #build.work }
	end
	local route = routeFromBuild(self, build)
	local reason = emptyRouteReason(build, route)
	if reason then
		levelingState(self).shownRoute = nil
		return nil, reason
	end
	return route
end

-- Brings the stored skill and rank cap of one of the logged-in character's professions up to what
-- the game reports now. The profession window's own events do not always carry a skill-up or a new
-- rank into the stored data on WoW Forever, which left the route starting from an old skill.
local function syncSkillFromGame(self, professionData)
	for _, profession in ipairs(self:GetPlayerProfessions()) do
		if profession.skillLineID == professionData.skillLineID then
			professionData.skillLevel = tonumber(profession.skillLevel) or professionData.skillLevel
			professionData.maxSkillLevel = tonumber(profession.maxSkillLevel) or professionData.maxSkillLevel
			return
		end
	end
end

--- The route for the profession whose window is open, for the logged-in character.
function Tradewright:GetOpenProfessionLevelingRoute()
	self:InitDB()
	local characterData, professionData = openProfession(self)
	if not professionData then
		return nil, "no_data"
	end
	syncSkillFromGame(self, professionData)
	-- Picks up a skill change, or a recipe learned while the window was closed.
	self:RefreshRecipeDifficulties(characterData, professionData)
	return self:GetLevelingRoute(self:GetCharacterKey(), professionData.skillLineID)
end
