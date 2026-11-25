local _, Tradewright = ...

-- The leveling route for a character's profession: prices every recipe that can still give skill (in
-- chunks, so a profession with hundreds of recipes does not freeze the game) and hands the priced
-- recipes to LevelingRouteLogic. Also keeps each recipe's stored colour current after a skill-up.

local SkillUpLogic = Tradewright.SkillUpLogic
local LevelingRouteLogic = Tradewright.LevelingRouteLogic

-- Milliseconds of one frame spent pricing recipes. Pricing a recipe costs far more on retail than
-- on WoW Forever, so the work is cut by time, not by a number of recipes.
local PRICING_BUDGET_MS = 5

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

-- On retail a profession is split by expansion: each has its own skill, cap and recipes, and the
-- profession window shows one at a time. The expansion shown, as
-- `{ skillLineID, name, skillLevel, maxSkillLevel }`, or nil where professions are not split (WoW Forever).
local function openExpansion(self, professionData)
	local info = self.IS_RETAIL and C_TradeSkillUI.GetChildProfessionInfo and C_TradeSkillUI.GetChildProfessionInfo()
	local skillLineID = info and tonumber(info.professionID)
	if not skillLineID or skillLineID == 0 or skillLineID == tonumber(professionData.skillLineID) then
		return nil
	end
	return {
		skillLineID = skillLineID, name = info.professionName,
		skillLevel = tonumber(info.skillLevel), maxSkillLevel = tonumber(info.maxSkillLevel),
	}
end

-- What a route levels: the whole profession, or one expansion of it. `{ name, fromSkill, rankCap,
-- maxSkill, expansionSkillLineID }`; an expansion has no ranks, so its cap is also its highest skill.
local function levelingScope(self, professionData, expansion)
	if expansion then
		return {
			name = expansion.name, fromSkill = expansion.skillLevel, rankCap = expansion.maxSkillLevel,
			maxSkill = expansion.maxSkillLevel, expansionSkillLineID = expansion.skillLineID,
		}
	end
	return {
		name = professionData.professionName, fromSkill = tonumber(professionData.skillLevel),
		rankCap = tonumber(professionData.maxSkillLevel), maxSkill = professionMaxSkill(self, professionData),
	}
end

local function recipeInScope(self, scope, recipeData)
	return not scope.expansionSkillLineID
		or C_TradeSkillUI.IsRecipeInSkillLine(self:GetRecipeSpellID(recipeData), scope.expansionSkillLineID) == true
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

-- The scope whose recipes are due a read from the game, or nil: read already at this skill for the
-- same expansion (unless `force`), or the skill or (on retail) the shown expansion is not known.
local function scopeDueForRead(self, professionData, force)
	local expansion = openExpansion(self, professionData)
	local scope = levelingScope(self, professionData, expansion)
	if not scope.fromSkill or (self.IS_RETAIL and not expansion) then
		return nil
	end
	local alreadyRead = professionData.difficultyReadAtSkill == scope.fromSkill
		and professionData.difficultyReadForExpansion == scope.expansionSkillLineID
	return (force or not alreadyRead) and scope or nil
end

--- Re-reads every recipe's colour and learned state for the open profession when its skill has
--- changed since the last read, or always with `force` (after training, which changes no skill).
--- On retail only the recipes of the expansion the window shows are read: a colour means something
--- only beside the skill of its own expansion.
--- A recipe that was learned or unlearned makes the route work itself out again.
function Tradewright:RefreshRecipeDifficulties(characterData, professionData, force)
	local scope = C_TradeSkillUI.GetRecipeInfo and scopeDueForRead(self, professionData, force)
	if not scope then
		return
	end
	local read = { skill = scope.fromSkill, observations = difficultyObservations(characterData, professionData.skillLineID) }
	local learnedChanged = false
	for recipeKey, recipeData in pairs(professionData.recipes or {}) do
		if recipeInScope(self, scope, recipeData) then
			learnedChanged = readRecipeFromGame(self, read, recipeKey, recipeData) or learnedChanged
		end
	end
	professionData.difficultyReadAtSkill, professionData.difficultyReadForExpansion = scope.fromSkill, scope.expansionSkillLineID
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

-- What the priced recipes depend on: what is leveled, the skill, the recipe list and prices. Bag
-- contents are left out on purpose (recipes are priced at market value), so a craft that gives no
-- skill point changes nothing here and the route is not worked out again.
local function candidatesKey(self, characterKey, professionData, scope)
	return table.concat({
		characterKey, skillLineKey(professionData.skillLineID), tostring(scope.expansionSkillLineID),
		tostring(scope.fromSkill), tostring(scope.rankCap), tostring(professionData.recipeCount),
		tostring(professionData.liveFingerprint), tostring(levelingState(self).revision),
	}, "|")
end

-- Recipes of the scope that can still give skill: `{ recipeKey, recipeData, greyLevel }`, and
-- whether any of the scope's recipes carries a grey level at all.
local function recipesWithSkillLeft(self, professionData, scope)
	local skill = scope.fromSkill or 0
	local work, anyGreyLevel = {}, false
	for recipeKey, recipeData in pairs(professionData.recipes or {}) do
		local usable = recipeInScope(self, scope, recipeData) and not self:IsReplacedRecipeRank(professionData, recipeData)
		local info = usable and self:RecipeDataInfo(recipeData)
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

-- What disenchanting the items of one craft gives: `value, basis` (see GetSalvageValue), or nil when
-- the crafted item cannot be disenchanted or nothing it gives has a price. Whether one of the
-- player's characters can disenchant does not matter: the route prices the items, not the work.
local function disenchantPerCraft(self, evaluation)
	local input = self.GetSalvageInput and self:GetSalvageInput("disenchant", evaluation.outputItemID)
	local worth = input and self.GetSalvageValue and self:GetSalvageValue("disenchant", input)
	if not worth then
		return nil
	end
	return worth.value * math.max(1, tonumber(evaluation.outputQty) or 1), worth.basis
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

-- What one craft gives back, in each give-back mode, and the item it makes for later steps to reuse.
local function priceGiveBack(self, candidate, evaluation)
	-- A salvage recipe (Prospecting, Milling) makes no one item: nothing to reuse or sell to a vendor,
	-- but what it gives on average can be sold at auction once its yield is known.
	if evaluation.isSalvage then
		candidate.auctionGiveBack = evaluation.saleNet and evaluation.saleNet * evaluation.outputQty or nil
	elseif evaluation.enchantsGear then
		-- An enchant cast on gear stays on that gear: nothing to sell or reuse. Its output id is a
		-- stand-in and must not be priced as an item.
		candidate.enchantsGear = true
	else
		candidate.vendorGiveBack, candidate.auctionGiveBack = giveBackPerCraft(self, evaluation)
		candidate.disenchantGiveBack, candidate.disenchantBasis = disenchantPerCraft(self, evaluation)
		candidate.outputItemID = tonumber(evaluation.outputItemID)
		candidate.outputQuantity = math.max(1, tonumber(evaluation.outputQty) or 1)
	end
end

-- Cost and give-back of one craft, read from the crafts engine. A recipe it cannot price (a missing
-- material price, or no crafted item to value) gets no `materialCost`. A salvage recipe is priced
-- with the cheapest item it can destroy; an enchant cast on gear by its reagents alone.
local function priceCandidate(self, candidate, build, workItem)
	local evaluation = self:EvaluateCraftScenario(
		build.characterKey, build.professionData, tonumber(workItem.recipeKey) or workItem.recipeKey, workItem.recipeData, MARKET_PRICING)
	if not evaluation or evaluation.matMissingPrice or not evaluation.fullMatCost then
		return
	end
	candidate.evaluation = evaluation
	candidate.name = evaluation.recipeName or candidate.name
	candidate.materialCost = evaluation.fullMatCost
	candidate.reagents = candidateReagents(evaluation)
	priceGiveBack(self, candidate, evaluation)
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
	local startedAt = debugprofilestop()
	repeat
		build.candidates[#build.candidates + 1] = buildCandidate(self, build, build.work[build.nextIndex])
		build.nextIndex = build.nextIndex + 1
	until build.nextIndex > #build.work or debugprofilestop() - startedAt >= PRICING_BUDGET_MS
	if build.nextIndex > #build.work then
		return finishBuild(self, build)
	end
	C_Timer.After(0, function()
		processCandidateChunk(self, build)
	end)
end

-- The priced recipes of the scope, started in the background when the inputs have changed.
local function currentBuild(self, characterKey, characterData, professionData, scope)
	local leveling = levelingState(self)
	local key = candidatesKey(self, characterKey, professionData, scope)
	-- A full scan replaces the profession's table, so the same key on another table is new data.
	if leveling.build and leveling.build.key == key and leveling.build.professionData == professionData then
		return leveling.build
	end
	local work, anyGreyLevel = recipesWithSkillLeft(self, professionData, scope)
	local build = {
		key = key, characterKey = characterKey, professionData = professionData, scope = scope, work = work, nextIndex = 1,
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
--- `{ giveBackMode = "vendor" | "auction" | "disenchant" | "none", recipeScope = "trainer" | "all" | "known" }`.
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
		local professionData, scope = build.professionData, build.scope
		local route = LevelingRouteLogic.BuildRoute({
			fromSkill = scope.fromSkill or 0, rankCap = scope.rankCap, maxSkill = scope.maxSkill,
			giveBackMode = settings.giveBackMode, recipeScope = settings.recipeScope, candidates = build.candidates,
		})
		route.professionName, route.skillLineID, route.characterKey = scope.name, professionData.skillLineID, build.characterKey
		route.expansionSkillLineID = scope.expansionSkillLineID
		route.giveBackMode, route.rankCap = settings.giveBackMode, scope.rankCap
		route.nextRank = self.GetNextRankTraining and self:GetNextRankTraining(professionData.skillLineID, route.rankCap) or nil
		build.routes[routeKey] = route
		levelingState(self).shownRoute = route
		if self.TrimLevelingCraftQueue then
			self:TrimLevelingCraftQueue(route)
		end
	end
	return build.routes[routeKey]
end

-- The last route handed out, when it leveled the same thing for this character.
local function previousRoute(self, characterKey, professionData, scope)
	local previous = levelingState(self).shownRoute
	if previous and previous.characterKey == characterKey and previous.skillLineID == professionData.skillLineID
		and previous.expansionSkillLineID == scope.expansionSkillLineID then
		return previous
	end
	return nil
end

--- The leveling route for one character's profession, from its last scan and current prices.
--- With `expansion` (see `openExpansion`) the route levels that expansion of the profession only.
--- Returns `route` (see `LevelingRouteLogic.BuildRoute`, plus `professionName` (the expansion's name
--- when it levels one), `skillLineID`, `expansionSkillLineID`, `characterKey`, `giveBackMode`,
--- `rankCap`, and `nextRank` when a trainer has been seen offering the training that lifts the rank
--- cap), or `nil, reason, progress`:
--- "no_data" (not scanned), "not_ready" (still pricing; `progress = { done, total }`), "unsupported"
--- (the game reports no grey levels), "no_prices", "finished" (nothing can give skill any more).
--- While recipes are priced again after a skill-up or new prices, the previous route of the same
--- profession and expansion is returned, so a window showing it does not empty and refill.
function Tradewright:GetLevelingRoute(characterKey, skillLineID, expansion)
	self:InitDB()
	local characterData = self.db.characters and self.db.characters[characterKey]
	local professionData = characterData and characterData.professions and characterData.professions[skillLineKey(skillLineID)]
	if not professionData or not next(professionData.recipes or {}) then
		return nil, "no_data"
	end
	local scope = levelingScope(self, professionData, expansion)
	local build = currentBuild(self, characterKey, characterData, professionData, scope)
	if not build.done then
		local previous = previousRoute(self, characterKey, professionData, scope)
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

--- The route for the profession whose window is open, for the logged-in character. On retail it
--- levels the expansion the window shows.
function Tradewright:GetOpenProfessionLevelingRoute()
	self:InitDB()
	local characterData, professionData = openProfession(self)
	if not professionData then
		return nil, "no_data"
	end
	syncSkillFromGame(self, professionData)
	-- Picks up a skill change, or a recipe learned while the window was closed.
	self:RefreshRecipeDifficulties(characterData, professionData)
	return self:GetLevelingRoute(self:GetCharacterKey(), professionData.skillLineID, openExpansion(self, professionData))
end

--- What the open profession window levels, to show while there is no route: `{ name, fromSkill }`
--- (see `levelingScope`), or nil when the profession is not stored.
function Tradewright:GetOpenProfessionLevelingScope()
	local _, professionData = openProfession(self)
	return professionData and levelingScope(self, professionData, openExpansion(self, professionData)) or nil
end
