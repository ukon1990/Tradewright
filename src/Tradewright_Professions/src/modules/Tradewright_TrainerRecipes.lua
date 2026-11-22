local _, Tradewright = ...

-- Trainer recipes. The profession scan does not say at which skill a recipe can be learned, what it
-- costs or who teaches it, but an open trainer window does. What a trainer lists goes to the
-- sightings store (Tradewright_Sources.lua) with the trainer and where it stands; its services
-- that are no recipe are its rank training (Expert, Artisan).
-- The leveling route uses it for recipes not learned yet, and to point the way to a trainer.
-- Only reads the window; buys nothing. A trainer's own filters can hide services, so a recipe that
-- is absent proves nothing.

local LevelingRouteLogic = Tradewright.LevelingRouteLogic

-- Which of the character's professions each scanned recipe name belongs to. The trainer lists
-- services by name only.
local function skillLineByRecipeName(pe, characterData)
	local index = {}
	for skillLineKey, professionData in pairs(characterData.professions or {}) do
		for _, recipeData in pairs(professionData.recipes or {}) do
			local info = pe:RecipeDataInfo(recipeData)
			if info and info.name then
				index[info.name] = skillLineKey
			end
		end
	end
	return index
end

local function listedServices()
	local services = {}
	for index = 1, GetNumTrainerServices() or 0 do
		services[#services + 1] = {
			name = GetTrainerServiceInfo(index),
			cost = GetTrainerServiceCost(index),
			skillRequired = GetTrainerServiceSkillReq and select(2, GetTrainerServiceSkillReq(index)) or nil,
		}
	end
	return services
end

--- Records what the open trainer window lists for the character's scanned professions.
function Tradewright:ReadOpenTrainerRecipes()
	if not (GetNumTrainerServices and GetTrainerServiceInfo and GetTrainerServiceCost) then
		return
	end
	self:InitDB()
	local characterData = self.db.characters and self.db.characters[self:GetCharacterKey()]
	if not characterData then
		return
	end
	local recipes, ranks = LevelingRouteLogic.TrainerEntries(listedServices(), skillLineByRecipeName(self, characterData), self:Now())
	if not next(recipes) then
		return
	end
	self:RecordTrainerSighting(recipes, ranks)
	self:InvalidateLevelingRoute()
end

--- Trainer recipes of one profession: `{ [recipeName] = { skillRequired, cost, seenAt, trainers } }`.
function Tradewright:GetTrainerRecipes(skillLineID)
	return self:GetTrainerOffers("taught", skillLineID)
end

--- The training that lifts a rank cap of `rankCap` for a profession, when a trainer has been seen
--- offering it: `{ name, skillRequired, cost, trainers }`, or nil. Higher ranks are taught by few
--- trainers, so this is what tells the player where to go.
function Tradewright:GetNextRankTraining(skillLineID, rankCap)
	if not rankCap then
		return nil
	end
	return LevelingRouteLogic.NextRankTraining(self:GetTrainerOffers("ranks", skillLineID), rankCap)
end

-- `trainers` as a list of places with the trainer's name on each.
local function trainerPlaces(trainers)
	local places = {}
	for name, place in pairs(trainers or {}) do
		places[#places + 1] = { name = name, zone = place.zone, mapID = place.mapID, x = place.x, y = place.y, seenAt = place.seenAt }
	end
	return places
end

--- Points the way to the nearest NPC a recipe can be had from, and says where it is in chat.
--- `npcs` is `{ [npcName] = place }`: the trainers seen teaching it, or with `sold` the vendors seen
--- selling its recipe item. Returns whether a waypoint was set.
function Tradewright:ShowRecipeTrainerWaypoint(recipeName, npcs, sold)
	local npc = self.NearestPlace and self:NearestPlace(trainerPlaces(npcs))
	if not npc then
		self:PrintMessage(string.format(
			"No trainer has been seen teaching %s. Visit a trainer of this profession once to get directions.", recipeName))
		return false
	end
	local marked = self:SetWaypointTo(npc, npc.name .. " (" .. recipeName .. ")")
	local zone = npc.zone and npc.zone ~= "" and (" in " .. npc.zone) or ""
	self:PrintMessage(string.format("%s %s %s%s, at %.1f, %.1f.%s", npc.name, sold and "sells the recipe for" or "teaches",
		recipeName, zone, npc.x * 100, npc.y * 100, marked and " Waypoint set." or ""))
	return marked
end

-- The game marks a recipe learned a moment after the event that announces it.
local REREAD_DELAY_SEC = 0.3
local rereadPending = false

local function rereadRecipesSoon()
	if rereadPending then
		return
	end
	rereadPending = true
	C_Timer.After(REREAD_DELAY_SEC, function()
		rereadPending = false
		if Tradewright.db then
			Tradewright:RereadRecipesAfterLearning()
		end
	end)
end

local trainerEvents = CreateFrame("Frame")
-- pcall: an event name the client does not know raises an error.
-- TRAINER_UPDATE also follows buying a service, so it stands in where NEW_RECIPE_LEARNED is missing.
for _, event in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "NEW_RECIPE_LEARNED" }) do
	pcall(trainerEvents.RegisterEvent, trainerEvents, event)
end
trainerEvents:SetScript("OnEvent", function(_, event)
	if event ~= "NEW_RECIPE_LEARNED" then
		Tradewright:ReadOpenTrainerRecipes()
	end
	if event ~= "TRAINER_SHOW" then
		rereadRecipesSoon()
	end
end)
