local _, AuctionHelper = ...

-- Trainer recipes. The profession scan does not say at which skill a recipe can be learned, what it
-- costs or who teaches it, but an open trainer window does. What a trainer lists is kept per
-- character, with the trainer's name and where it stands:
-- `db.characters[characterKey].trainerRecipes[skillLineKey][recipeName] =
--    { skillRequired, cost, seenAt, trainers = { [trainerName] = { zone, mapID, x, y } } }`.
-- The leveling route uses it for recipes not learned yet, and to point the way to a trainer.
-- Only reads the window; buys nothing. A trainer's own filters can hide services, so a recipe that
-- is absent proves nothing.

local LevelingRouteLogic = AuctionHelper.LevelingRouteLogic

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

local function storeTrainerEntries(characterData, entries)
	characterData.trainerRecipes = characterData.trainerRecipes or {}
	for skillLineKey, recipes in pairs(entries) do
		local stored = characterData.trainerRecipes[skillLineKey] or {}
		characterData.trainerRecipes[skillLineKey] = stored
		for recipeName, entry in pairs(recipes) do
			stored[recipeName] = LevelingRouteLogic.MergeTrainerEntry(stored[recipeName], entry)
		end
	end
end

-- Who is being asked, where and when.
local function trainerSighting(pe)
	return {
		now = pe:Now(), trainerName = UnitName and UnitName("npc") or nil,
		place = pe.GetPlayerPlace and pe:GetPlayerPlace() or nil,
	}
end

--- Records what the open trainer window lists for the character's scanned professions.
function AuctionHelper:ReadOpenTrainerRecipes()
	if not (GetNumTrainerServices and GetTrainerServiceInfo and GetTrainerServiceCost) then
		return
	end
	self:InitDB()
	local characterData = self.db.characters and self.db.characters[self:GetCharacterKey()]
	if not characterData then
		return
	end
	local entries = LevelingRouteLogic.TrainerEntries(listedServices(), skillLineByRecipeName(self, characterData), trainerSighting(self))
	if not next(entries) then
		return
	end
	storeTrainerEntries(characterData, entries)
	self:InvalidateLevelingRoute()
end

local function factionOf(characterData)
	return characterData.meta and characterData.meta.faction
end

--- Trainer recipes of one profession, seen by any character:
--- `{ [recipeName] = { skillRequired, cost, seenAt, trainers } }`. Trainers seen by a character of
--- the other faction are left out: they will not teach this one.
function AuctionHelper:GetTrainerRecipes(skillLineID)
	local characters = self.db and self.db.characters or {}
	local ownFaction = factionOf(characters[self:GetCharacterKey()] or {})
	local merged = {}
	for _, characterData in pairs(characters) do
		local recipes = characterData.trainerRecipes and characterData.trainerRecipes[tostring(skillLineID)]
		local otherFaction = factionOf(characterData) ~= ownFaction
		for recipeName, entry in pairs(recipes or {}) do
			merged[recipeName] = LevelingRouteLogic.MergeTrainerEntry(merged[recipeName], entry, otherFaction)
		end
	end
	return merged
end

-- `trainers` as a list of places with the trainer's name on each.
local function trainerPlaces(trainers)
	local places = {}
	for name, place in pairs(trainers or {}) do
		places[#places + 1] = { name = name, zone = place.zone, mapID = place.mapID, x = place.x, y = place.y, seenAt = place.seenAt }
	end
	return places
end

--- Points the way to the nearest trainer seen teaching `recipeName`, and says where it is in chat.
--- `trainers` is the recipe's `{ [trainerName] = place }`. Returns whether a waypoint was set.
function AuctionHelper:ShowRecipeTrainerWaypoint(recipeName, trainers)
	local trainer = self.NearestPlace and self:NearestPlace(trainerPlaces(trainers))
	if not trainer then
		self:PrintMessage(string.format(
			"No trainer has been seen teaching %s. Open a trainer of this profession once; trainer recipes then get directions.", recipeName))
		return false
	end
	local marked = self:SetWaypointTo(trainer, trainer.name .. " (" .. recipeName .. ")")
	local zone = trainer.zone and trainer.zone ~= "" and (" in " .. trainer.zone) or ""
	self:PrintMessage(string.format("%s teaches %s%s, at %.1f, %.1f.%s", trainer.name, recipeName, zone,
		trainer.x * 100, trainer.y * 100, marked and " Waypoint set." or ""))
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
		if AuctionHelper.db then
			AuctionHelper:RereadRecipesAfterLearning()
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
		AuctionHelper:ReadOpenTrainerRecipes()
	end
	if event ~= "TRAINER_SHOW" then
		rereadRecipesSoon()
	end
end)
